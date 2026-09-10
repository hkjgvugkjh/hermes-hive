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

// diCreds carries optional per-client credential overrides for a DI connect.
type diCreds struct {
	user       string
	pass       string
	deviceCode string
	instanceID string
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

// sendDIFrame encrypts and writes a DI frame to a single client.
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
		s.handleDISessionPoll(client, plain)
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

// attachBackend joins client to the shared backend for serverID, dialling it
// on first use. Unlike the old per-client model this no longer tears down any
// other backend, so a client can stay attached to several servers at once.
func (s *Server) attachBackend(client *Client, sc *config.ServerConfig, creds diCreds) (*backendConn, error) {
	bc, err := s.hub.acquire(sc, client, creds)
	if err != nil {
		return bc, err
	}
	client.mu.Lock()
	if client.subscribed == nil {
		client.subscribed = make(map[string]struct{})
	}
	client.subscribed[sc.ID] = struct{}{}
	client.current = sc.ID
	client.mu.Unlock()
	return bc, nil
}

// focusedBackend returns the backend the client is currently driving
// (voice/auth/events), falling back to its single subscription.
func (s *Server) focusedBackend(client *Client) *backendConn {
	client.mu.Lock()
	id := client.current
	if id == "" && len(client.subscribed) == 1 {
		for k := range client.subscribed {
			id = k
		}
	}
	client.mu.Unlock()
	if id == "" {
		return nil
	}
	return s.hub.get(id)
}

// handleDIConnect attaches the client to a configured server's shared backend.
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

	// Credentials: payload overrides config.
	creds := diCreds{user: sc.Username, pass: sc.Password, deviceCode: p.DeviceCode, instanceID: p.InstanceId}
	if p.Username != "" {
		creds.user = p.Username
	}
	if p.Password != "" {
		creds.pass = p.Password
	}

	bc, err := s.attachBackend(client, sc, creds)
	if err != nil {
		s.sendDIFrame(client, di.TypeDIConnectAck, di.DIConnectAckPayload{ServerID: p.ServerID, OK: false, Reason: err.Error()})
		return
	}

	bc.mu.Lock()
	deviceID := bc.deviceID
	bc.mu.Unlock()

	// generic_ws has no adapter/poller: send an empty snapshot so the UI settles.
	if sc.Type != config.ServerTypeHermesStudio {
		s.sendDIFrame(client, di.TypeDISessionUpdate, di.DISessionUpdatePayload{ServerID: p.ServerID, Full: true, Sessions: nil})
	}

	s.sendDIFrame(client, di.TypeDIConnectAck, di.DIConnectAckPayload{ServerID: p.ServerID, OK: true, DeviceID: deviceID})
	log.Printf("[di] client %s attached to server %s (type=%s, shared=%v)", client.ID, p.ServerID, sc.Type, deviceID != "")

	// Give the freshly attached client an immediate snapshot without making
	// it wait for the next poll tick.
	go s.clientSnapshot(client, bc, true)
}

// handleDIList returns the public server list.
func (s *Server) handleDIList(client *Client) {
	s.sendDIFrame(client, di.TypeDIListResp, di.DIListRespPayload{Servers: s.cfg.GetServerPublicList()})
}

// handleDISessionPoll pushes a snapshot for one server (or the focused one).
//
// The payload may name a server; when it does, the proxy ensures a shared
// backend exists for it. That lets a client poll several servers without
// detaching from any of them.
func (s *Server) handleDISessionPoll(client *Client, plain []byte) {
	var p di.DISessionPollPayload
	// Older clients send an empty body; treat that as "poll the focused one".
	_ = di.DecodePayload(plain, &p)

	if p.ServerID != "" {
		sc := s.cfg.GetServer(p.ServerID)
		if sc == nil || !sc.Enabled {
			s.sendDIFrame(client, di.TypeDIError, di.DIErrorPayload{
				ServerID: p.ServerID, Message: "server not found/disabled",
			})
			return
		}
		bc, err := s.attachBackend(client, sc, diCreds{user: sc.Username, pass: sc.Password})
		if err != nil {
			// Report the failure instead of leaving the client to time out.
			s.sendDIFrame(client, di.TypeDIError, di.DIErrorPayload{
				ServerID: p.ServerID, Message: err.Error(),
			})
			return
		}
		s.clientSnapshot(client, bc, true)
		return
	}

	bc := s.focusedBackend(client)
	if bc == nil {
		s.sendDIFrame(client, di.TypeDIError, di.DIErrorPayload{Message: "no active server"})
		return
	}
	s.clientSnapshot(client, bc, true)
}

// handleDISwitchServer moves the client's focus to another server.
//
// The previous backend is NOT torn down: the client keeps its subscription, so
// it continues receiving that server's session updates in the background.
func (s *Server) handleDISwitchServer(client *Client, plain []byte) {
	var p di.DISwitchServerPayload
	if err := di.DecodePayload(plain, &p); err != nil {
		return
	}
	s.handleDIConnect(client, []byte(mustJSON(di.DIConnectPayload{ServerID: p.ServerID})))
}

// handleDIVoiceCmd begins a voice command on the focused backend.
func (s *Server) handleDIVoiceCmd(client *Client, plain []byte) {
	var p di.DIVoiceCmdPayload
	if err := di.DecodePayload(plain, &p); err != nil {
		return
	}
	client.voiceSession = p.SessionID
	bc := s.focusedBackend(client)
	if bc != nil {
		bc.mu.Lock()
		ad := bc.adapter
		bc.mu.Unlock()
		if ad != nil {
			_ = ad.SendEvent(&diEvent{Direction: "up", Event: "voice.stream.start", Data: mustJSON(map[string]string{"session_id": p.SessionID})})
		}
	}
}

// handleDIVoiceData forwards a voice chunk to the focused backend.
func (s *Server) handleDIVoiceData(client *Client, plain []byte) {
	var p di.DIVoiceDataPayload
	if err := di.DecodePayload(plain, &p); err != nil {
		return
	}
	bc := s.focusedBackend(client)
	if bc == nil {
		return
	}
	bc.mu.Lock()
	ad := bc.adapter
	bc.mu.Unlock()
	if ad == nil {
		return
	}
	_ = ad.SendEvent(&diEvent{Direction: "up", Event: "voice.stream.chunk", Data: string(plain)})
	if p.Last {
		_ = ad.SendEvent(&diEvent{Direction: "up", Event: "voice.stream.end", Data: mustJSON(map[string]string{"session_id": p.SessionID})})
	}
}

// handleDIAuthResp relays the user's auth decision to the focused backend.
func (s *Server) handleDIAuthResp(client *Client, plain []byte) {
	bc := s.focusedBackend(client)
	if bc == nil {
		return
	}
	bc.mu.Lock()
	ad := bc.adapter
	bc.mu.Unlock()
	if ad == nil {
		return
	}
	_ = ad.SendEvent(&diEvent{Direction: "up", Event: "mcu.auth.ok", Data: string(plain)})
}

// handleDIEvent passes an opaque event through to the focused backend.
func (s *Server) handleDIEvent(client *Client, plain []byte) {
	bc := s.focusedBackend(client)
	if bc == nil {
		return
	}
	var p diEvent
	if err := di.DecodePayload(plain, &p); err != nil {
		return
	}
	bc.mu.Lock()
	ad := bc.adapter
	bc.mu.Unlock()
	if ad == nil {
		return
	}
	_ = ad.SendEvent(&p)
}

// detachBackend is retained for API compatibility; the hub now owns teardown.
func (s *Server) detachBackend(client *Client) {
	s.hub.releaseAll(client)
}

// mustJSON helper.
func mustJSON(v interface{}) string {
	b, err := json.Marshal(v)
	if err != nil {
		return "{}"
	}
	return string(b)
}
