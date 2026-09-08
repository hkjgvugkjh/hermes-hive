package proxy

import (
	"encoding/json"
	"log"
	"time"

	"hermes-proxy/internal/config"
	"hermes-proxy/internal/crypto"
	"hermes-proxy/internal/di"
)

// sessionPollInterval is how often the proxy polls a backend for session
// changes and diffs them into TypeDISessionUpdate pushes (per design: the
// proxy is responsible for producing session updates even if the backend
// does not push).
const sessionPollInterval = 5 * time.Second

// diEvent is proxy-local mirror of di.DiEventPayload. We keep it local to
// avoid a cross-package export-resolution quirk in this build environment.
type diEvent struct {
	Direction string `json:"direction"`
	Event     string `json:"event"`
	Data      string `json:"data"`
}

// activeBackend is the live connection state for one client to one server.
type activeBackend struct {
	cfg     *config.ServerConfig
	adapter backendAdapter // nil for generic_ws (pure relay)
	// studio adapter state
	deviceID string
	jwt      string // JWT from mcu-login, used for session polling
	// session polling
	pollStop chan struct{}
}

// backendAdapter abstracts "speak the backend's protocol".
// For hermes_studio the adapter is the 小方盒 emulator; for generic_ws it is
// a no-op relay (frames pass straight through).
type backendAdapter interface {
	// Connect establishes the backend session (e.g. mcu-login + Socket.IO).
	Connect() error
	// SendEvent pushes an opaque DI event upstream (used by TypeDIEvent, voice).
	SendEvent(ev *diEvent) error
	// Close tears the backend session down.
	Close()
}

// sendDIFrame encrypts and writes a DI frame to the client.
func (s *Server) sendDIFrame(client *Client, mt di.MessageType, payload interface{}) {
	plain, err := di.EncodePayload(payload)
	if err != nil {
		log.Printf("[di] encode error: %v", err)
		return
	}
	enc, err := crypto.Encrypt(client.SharedKey, plain)
	if err != nil {
		log.Printf("[di] encrypt error: %v", err)
		return
	}
	frame := di.EncodeFrame(&di.Frame{Type: mt, Payload: enc})
	client.mu.Lock()
	defer client.mu.Unlock()
	if err := client.Conn.WriteMessage(wsFrameBinary, frame); err != nil {
		log.Printf("[di] write error: %v", err)
	}
}

// handleDI is the DI control-plane dispatcher, invoked from handleClient.
func (s *Server) handleDI(client *Client, msgType di.MessageType, encrypted []byte) {
	plain, err := crypto.Decrypt(client.SharedKey, encrypted)
	if err != nil {
		log.Printf("[di] decrypt error: %v", err)
		return
	}
	switch msgType {
	case di.TypeDIConnect:
		s.handleDIConnect(client, plain)
	case di.TypeDIList:
		s.handleDIList(client)
	case di.TypeDISessionPoll:
		s.handleDISessionPoll(client)
	case di.TypeDISwitchServer:
		s.handleDISwitchServer(client, plain)
	case di.TypeDIVoiceCmd:
		s.handleDIVoiceCmd(client, plain)
	case di.TypeDIVoiceData:
		s.handleDIVoiceData(client, plain)
	case di.TypeDIAuthResp:
		s.handleDIAuthResp(client, plain)
	case di.TypeDIEvent:
		s.handleDIEvent(client, plain)
	case di.TypeDIPing:
		s.sendDIFrame(client, di.TypeDIPong, map[string]string{"t": time.Now().UTC().Format(time.RFC3339)})
	default:
		log.Printf("[di] unhandled control type 0x%02x", msgType)
	}
}

// handleDIConnect connects to (and authenticates with) a configured server.
func (s *Server) handleDIConnect(client *Client, plain []byte) {
	var p di.DIConnectPayload
	if err := di.DecodePayload(plain, &p); err != nil {
		s.sendDIFrame(client, di.TypeDIConnectAck, di.DIConnectAckPayload{OK: false, Reason: "bad payload"})
		return
	}
	sc := s.cfg.GetServer(p.ServerID)
	if sc == nil || !sc.Enabled {
		s.sendDIFrame(client, di.TypeDIConnectAck, di.DIConnectAckPayload{ServerID: p.ServerID, OK: false, Reason: "server not found/disabled"})
		return
	}
	// Tear down any previous backend.
	s.detachBackend(client)

	ab := &activeBackend{cfg: sc, pollStop: make(chan struct{})}
	if sc.Type == config.ServerTypeHermesStudio {
		// Credentials: payload overrides config.
		user, pass := sc.Username, sc.Password
		if p.Username != "" {
			user = p.Username
		}
		if p.Password != "" {
			pass = p.Password
		}
		ad := newStudioAdapter(s, sc, user, pass, client)
		if err := ad.Connect(); err != nil {
			s.sendDIFrame(client, di.TypeDIConnectAck, di.DIConnectAckPayload{ServerID: p.ServerID, OK: false, Reason: err.Error()})
			return
		}
		ab.adapter = ad
		ab.deviceID = ad.deviceID
		ab.jwt = ad.jwt
		// Start session polling.
		go s.pollSessions(client, ab)
	} else {
		// generic_ws: relay-only; no polling here (backend pushes). We still
		// send an initial empty snapshot so the UI stabilizes.
		s.sendDIFrame(client, di.TypeDISessionUpdate, di.DISessionUpdatePayload{ServerID: p.ServerID, Full: true, Sessions: nil})
	}

	client.active = ab
	s.sendDIFrame(client, di.TypeDIConnectAck, di.DIConnectAckPayload{ServerID: p.ServerID, OK: true, DeviceID: ab.deviceID})
	log.Printf("[di] client %s connected to server %s (type=%s)", client.ID, p.ServerID, sc.Type)
}

// handleDIList returns the public server list.
func (s *Server) handleDIList(client *Client) {
	s.sendDIFrame(client, di.TypeDIListResp, di.DIListRespPayload{Servers: s.cfg.GetServerPublicList()})
}

// handleDISessionPoll pushes a full snapshot immediately.
func (s *Server) handleDISessionPoll(client *Client) {
	if client.active == nil {
		return
	}
	s.pushSessionSnapshot(client, client.active, true)
}

// handleDISwitchServer switches the active server without reopening the WS.
func (s *Server) handleDISwitchServer(client *Client, plain []byte) {
	var p di.DISwitchServerPayload
	if err := di.DecodePayload(plain, &p); err != nil {
		return
	}
	// Reuse connect path.
	s.handleDIConnect(client, []byte(mustJSON(di.DIConnectPayload{ServerID: p.ServerID})))
}

// handleDIVoiceCmd begins a voice command; we just record the target session
// on the client and forward to the adapter if present.
func (s *Server) handleDIVoiceCmd(client *Client, plain []byte) {
	var p di.DIVoiceCmdPayload
	if err := di.DecodePayload(plain, &p); err != nil {
		return
	}
	client.voiceSession = p.SessionID
	// Forward as a DI event to the studio adapter (it maps to voice.stream.start).
	if client.active != nil && client.active.adapter != nil {
		_ = client.active.adapter.SendEvent(&diEvent{Direction: "up", Event: "voice.stream.start", Data: mustJSON(map[string]string{"session_id": p.SessionID})})
	}
}

// handleDIVoiceData forwards a voice chunk to the active backend.
func (s *Server) handleDIVoiceData(client *Client, plain []byte) {
	var p di.DIVoiceDataPayload
	if err := di.DecodePayload(plain, &p); err != nil {
		return
	}
	if client.active == nil || client.active.adapter == nil {
		return
	}
	_ = client.active.adapter.SendEvent(&diEvent{Direction: "up", Event: "voice.stream.chunk", Data: string(plain)})
	if p.Last {
		_ = client.active.adapter.SendEvent(&diEvent{Direction: "up", Event: "voice.stream.end", Data: mustJSON(map[string]string{"session_id": p.SessionID})})
	}
}

// handleDIAuthResp relays the user's auth decision to the backend.
func (s *Server) handleDIAuthResp(client *Client, plain []byte) {
	if client.active == nil || client.active.adapter == nil {
		return
	}
	_ = client.active.adapter.SendEvent(&diEvent{Direction: "up", Event: "mcu.auth.ok", Data: string(plain)})
}

// handleDIEvent passes an opaque event through to the backend adapter.
func (s *Server) handleDIEvent(client *Client, plain []byte) {
	if client.active == nil || client.active.adapter == nil {
		return
	}
	var p diEvent
	if err := di.DecodePayload(plain, &p); err != nil {
		return
	}
	_ = client.active.adapter.SendEvent(&p)
}

// detachBackend tears down the client's current backend connection.
func (s *Server) detachBackend(client *Client) {
	if client.active == nil {
		return
	}
	if client.active.pollStop != nil {
		close(client.active.pollStop)
	}
	if client.active.adapter != nil {
		client.active.adapter.Close()
	}
	client.active = nil
}

// mustJSON helper.
func mustJSON(v interface{}) string {
	b, err := json.Marshal(v)
	if err != nil {
		return "{}"
	}
	return string(b)
}
