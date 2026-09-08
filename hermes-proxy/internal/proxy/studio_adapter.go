package proxy

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"hermes-proxy/internal/config"
	"hermes-proxy/internal/di"
)

// studioAdapter makes the proxy behave like the "小方盒" (MCU device) when
// talking to a hermes_studio backend. It performs mcu-login, opens the
// Socket.IO /global-agent namespace, sends mcu.ready, and translates events in
// both directions:
//
//	backend Socket.IO event  ->  DI frame to client (TypeDIAuthReq / TypeDIEvent / TypeDISessionUpdate)
//	client DI event/voice     ->  Socket.IO event to backend
type studioAdapter struct {
	proxy    *Server
	cfg      *config.ServerConfig
	user     string
	pass     string
	client   *Client // the hive client we push DI frames to

	mu       sync.Mutex
	ws       *websocket.Conn
	sid      string
	deviceID string // assigned by server after mcu.ready
	jwt      string

	done chan struct{}
	once sync.Once
}

// newStudioAdapter constructs the adapter.
func newStudioAdapter(p *Server, cfg *config.ServerConfig, user, pass string, client *Client) *studioAdapter {
	return &studioAdapter{
		proxy:    p,
		cfg:      cfg,
		user:     user,
		pass:     pass,
		client:   client,
		deviceID: "PROXY-" + shortID(),
		done:     make(chan struct{}),
	}
}

// Connect performs mcu-login then opens the Socket.IO session.
func (a *studioAdapter) Connect() error {
	jwt, err := a.mcuLogin()
	if err != nil {
		return fmt.Errorf("mcu-login: %w", err)
	}
	a.jwt = jwt

	if err := a.openSocketIO(); err != nil {
		return fmt.Errorf("socketio: %w", err)
	}
	return nil
}

// mcuLogin obtains a JWT from the backend (小方盒 login flow).
func (a *studioAdapter) mcuLogin() (string, error) {
	body := map[string]interface{}{
		"token":        strings.ToUpper(a.deviceID),
		"id":           strings.ToUpper(a.deviceID),
		"device_code":  strings.ToUpper(a.deviceID),
		"device_type":  "hermes-proxy",
		"source":       "global_agent",
		"account":      a.user,
		"password":     a.pass,
		"relayMode":    "lan",
	}
	b, _ := json.Marshal(body)
	req, _ := http.NewRequest(http.MethodPost, a.cfg.URL+"/api/auth/mcu-login", strings.NewReader(string(b)))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Hermes-Device-Id", strings.ToUpper(a.deviceID))
	req.Header.Set("X-Hermes-Device-Name", "Hermes Proxy")

	hc := &http.Client{Timeout: 15 * time.Second}
	resp, err := hc.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("mcu-login HTTP %d", resp.StatusCode)
	}
	var out struct {
		Token    string   `json:"token"`
		Profiles []string `json:"profiles"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return "", err
	}
	if out.Token == "" {
		return "", fmt.Errorf("mcu-login: empty token")
	}
	return out.Token, nil
}

// openSocketIO runs the Engine.IO/Socket.IO handshake and the read loop.
func (a *studioAdapter) openSocketIO() error {
	u, err := url.Parse(a.cfg.URL)
	if err != nil {
		return err
	}
	if u.Scheme == "https" {
		u.Scheme = "wss"
	} else {
		u.Scheme = "ws"
	}
	u.Path = strings.TrimRight(u.Path, "/") + "/socket.io/"
	q := u.Query()
	q.Set("EIO", "4")
	q.Set("transport", "websocket")
	q.Set("token", a.jwt)
	q.Set("deviceCode", strings.ToUpper(a.deviceID))
	q.Set("device_code", strings.ToUpper(a.deviceID))
	u.RawQuery = q.Encode()

	dialer := websocket.Dialer{HandshakeTimeout: 15 * time.Second}
	ws, _, err := dialer.Dial(u.String(), nil)
	if err != nil {
		return err
	}
	a.mu.Lock()
	a.ws = ws
	a.mu.Unlock()

	// Read loop in a goroutine.
	go a.readLoop()

	// Wait for OPEN frame (0{...}) then send namespace CONNECT.
	if err := a.waitOpenAndConnect(); err != nil {
		return err
	}
	return nil
}

// waitOpenAndConnect performs the Socket.IO namespace connect + mcu.ready.
func (a *studioAdapter) waitOpenAndConnect() error {
	// The read loop already captures the OPEN frame; we send CONNECT after a
	// short delay to ensure the server's OPEN has arrived.
	deadline := time.After(10 * time.Second)
	for {
		a.mu.Lock()
		got := a.sid != ""
		a.mu.Unlock()
		if got {
			break
		}
		select {
		case <-deadline:
			return fmt.Errorf("timed out waiting for Engine.IO OPEN")
		case <-time.After(50 * time.Millisecond):
		}
	}

	// Namespace CONNECT.
	connect := fmt.Sprintf(`40/global-agent,{"token":%q,"deviceCode":%q,"device_code":%q,"role":"hermes-studio","instanceId":%q,"profile":%q}`,
		a.jwt, strings.ToUpper(a.deviceID), strings.ToUpper(a.deviceID), strings.ToUpper(a.deviceID), a.profile())
	if err := a.writeRaw(connect); err != nil {
		return err
	}

	// mcu.ready
	ready := fmt.Sprintf(`42/global-agent,["mcu.ready",{"apiToken":%q,"type":"mcu.ready","id":%q,"active_device":%q,"profile":%q,"capabilities":{"display":true,"audio_queue":true,"audio_playback":true,"pcm_stream":false}}]`,
		a.jwt, strings.ToUpper(a.deviceID), strings.ToUpper(a.deviceID), a.profile())
	if err := a.writeRaw(ready); err != nil {
		return err
	}
	return nil
}

func (a *studioAdapter) profile() string {
	if a.cfg.Profile != "" {
		return a.cfg.Profile
	}
	return "default"
}

// readLoop reads Engine.IO frames and dispatches them.
func (a *studioAdapter) readLoop() {
	defer a.Close()
	for {
		select {
		case <-a.done:
			return
		default:
		}
		a.mu.Lock()
		ws := a.ws
		a.mu.Unlock()
		if ws == nil {
			return
		}
		_, msg, err := ws.ReadMessage()
		if err != nil {
			log.Printf("[studio] read error: %v", err)
			return
		}
		a.handleFrame(string(msg))
	}
}

// handleFrame parses an Engine.IO frame and reacts.
func (a *studioAdapter) handleFrame(frame string) {
	if len(frame) == 0 {
		return
	}
	switch frame[0] {
	case '0': // OPEN
		// 0{...json...}
		var open struct {
			Sid string `json:"sid"`
		}
		if err := json.Unmarshal([]byte(frame[1:]), &open); err == nil {
			a.mu.Lock()
			a.sid = open.Sid
			a.mu.Unlock()
		}
	case '2': // PING
		a.writeRaw("3") // PONG
	case '3': // PONG (ignore)
	case '4': // MESSAGE (Socket.IO)
		a.handleSocketIO(frame[1:])
	case '1', '5', '6': // close/upgrade/noop
	default:
	}
}

// handleSocketIO parses a Socket.IO packet and dispatches events.
func (a *studioAdapter) handleSocketIO(pkt string) {
	if len(pkt) < 2 {
		return
	}
	// pkt[0] = socket.io packet type, optional '/nsp,' then payload.
	// For events: "42/global-agent,[\"event\",{...}]"
	if pkt[0] == '4' && len(pkt) > 1 && pkt[1] == '2' {
		// event
		rest := pkt[2:]
		// strip namespace prefix "/global-agent,"
		if i := strings.Index(rest, ","); i >= 0 {
			rest = rest[i+1:]
		}
		var arr []json.RawMessage
		if err := json.Unmarshal([]byte(rest), &arr); err != nil || len(arr) < 2 {
			return
		}
		var name string
		json.Unmarshal(arr[0], &name)
		data := arr[1]
		a.dispatchEvent(name, data)
	}
}

// dispatchEvent maps a backend Socket.IO event to a DI frame.
func (a *studioAdapter) dispatchEvent(name string, data json.RawMessage) {
	switch name {
	case "mcu.auth", "auth.invalid", "mcu.reauth.required":
		// Surface as an authorization request to the user.
		prompt := name
		if name == "auth.invalid" {
			prompt = "Authentication invalid, please re-authenticate"
		}
		a.proxy.sendDIFrame(a.client, di.TypeDIAuthReq, di.DIAuthReqPayload{
			Prompt: prompt,
		})
	case "mcu.interaction.status", "mcu.audio.enqueue", "mcu.session.clear":
		// Pass through as opaque DI events (down direction).
		a.proxy.sendDIFrame(a.client, di.TypeDIEvent, diEvent{
			Direction: "down",
			Event:     name,
			Data:      string(data),
		})
	default:
		// Everything else: forward as a generic DI event so the client can
		// react (e.g. session updates, custom events).
		a.proxy.sendDIFrame(a.client, di.TypeDIEvent, diEvent{
			Direction: "down",
			Event:     name,
			Data:      string(data),
		})
	}
}

// SendEvent forwards a client DI event/voice command to the backend.
func (a *studioAdapter) SendEvent(ev *diEvent) error {
	if ev == nil {
		return nil
	}
	// Map DI voice events to Socket.IO voice.stream.* events.
	name := ev.Event
	switch ev.Event {
	case "voice.stream.start":
		name = "voice.stream.start"
	case "voice.stream.chunk":
		name = "voice.stream.chunk"
	case "voice.stream.end":
		name = "voice.stream.end"
	case "mcu.auth.ok":
		name = "mcu.auth.ok"
	}
	pkt := fmt.Sprintf("42/global-agent,[\"%s\",%s]", name, ev.Data)
	return a.writeRaw(pkt)
}

// Close tears down the Socket.IO connection.
func (a *studioAdapter) Close() {
	a.once.Do(func() {
		close(a.done)
		a.mu.Lock()
		if a.ws != nil {
			a.ws.Close()
			a.ws = nil
		}
		a.mu.Unlock()
	})
}

// writeRaw writes a raw Engine.IO/Socket.IO text frame.
func (a *studioAdapter) writeRaw(s string) error {
	a.mu.Lock()
	ws := a.ws
	a.mu.Unlock()
	if ws == nil {
		return fmt.Errorf("not connected")
	}
	return ws.WriteMessage(websocket.TextMessage, []byte(s))
}

// shortID generates a short random device suffix.
func shortID() string {
	return fmt.Sprintf("%06X", time.Now().UnixNano()%0x1000000)
}
