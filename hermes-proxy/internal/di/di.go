// Package di defines the Device-Interconnect application-layer protocol that
// rides on top of the encrypted WebSocket tunnel established by hermes-proxy.
//
// Rationale (per design 2026-09-06):
//   - hermes-hive speaks ONLY this DI protocol.
//   - hermes-proxy adapts DI <-> each backend server type:
//       * hermes_studio  -> proxy acts as the "小方盒" (MCU device): performs
//                            mcu-login, opens Socket.IO /global-agent, and
//                            translates DI events to/from Socket.IO events.
//       * generic_ws     -> proxy relays DI frames to a backend that implements
//                            the DI server side itself.
//   - Session-state changes are produced by the PROXY (polling the backend's
//     HTTP API and diffing), so the client gets uniform push updates regardless
//     of whether the backend natively pushes.
package di

import (
	"encoding/binary"
	"encoding/json"
	"fmt"
)

// MessageType identifies a DI protocol message.
type MessageType byte

const (
	TypeDIConnect      MessageType = 0x30 // C->S: connect to a server (with creds)
	TypeDIConnectAck   MessageType = 0x31 // S->C: connect result
	TypeDIList         MessageType = 0x32 // C->S: request server list
	TypeDIListResp     MessageType = 0x33 // S->C: server list (no secrets)
	TypeDISessionPoll  MessageType = 0x34 // C->S: pull session snapshot
	TypeDISessionUpdate MessageType = 0x35 // S->C: session diff/state
	TypeDISwitchServer MessageType = 0x36 // C->S: switch active server
	TypeDIVoiceCmd     MessageType = 0x37 // C->S: voice command to a session
	TypeDIVoiceData    MessageType = 0x38 // both: voice chunk (multiple frames)
	TypeDIAuthReq      MessageType = 0x39 // S->C: backend requires auth
	TypeDIAuthResp     MessageType = 0x3A // C->S: user/voice auth decision
	TypeDIEvent        MessageType = 0x3B // both: opaque 小方盒 event passthrough
	TypeDIPing         MessageType = 0x3C // both: app-level heartbeat
	TypeDIPong         MessageType = 0x3D // both: heartbeat reply
	TypeDIError        MessageType = 0x3F // S->C: server-scoped error

)

// Frame is the DI wire format: [1 type][4 length][payload].
// (Same envelope as protocol.Frame; re-declared here to avoid importing the
// lower transport package transitively.)
type Frame struct {
	Type    MessageType
	Payload []byte
}

// EncodeFrame serializes a DI frame.
func EncodeFrame(f *Frame) []byte {
	buf := make([]byte, 1+4+len(f.Payload))
	buf[0] = byte(f.Type)
	binary.BigEndian.PutUint32(buf[1:5], uint32(len(f.Payload)))
	copy(buf[5:], f.Payload)
	return buf
}

// DecodeFrameHeader reads the type and length from a 5-byte header.
func DecodeFrameHeader(header []byte) (MessageType, uint32, error) {
	if len(header) < 5 {
		return 0, 0, fmt.Errorf("header too short")
	}
	return MessageType(header[0]), binary.BigEndian.Uint32(header[1:5]), nil
}

// EncodePayload JSON-marshals a payload.
func EncodePayload(v interface{}) ([]byte, error) { return json.Marshal(v) }

// DecodePayload JSON-unmarshals a payload.
func DecodePayload(data []byte, v interface{}) error { return json.Unmarshal(data, v) }

// ---------------------------------------------------------------------------
// Payload structs
// ---------------------------------------------------------------------------

// DIEventPayload passes through an opaque 小方盒 event (name + json payload).
type DIEventPayload struct {
	Direction string `json:"direction"` // "up" (device->server) | "down" (server->device)
	Event     string `json:"event"`     // e.g. mcu.ready, mcu.auth, voice.stream.start
	Data      string `json:"data"`      // raw JSON string
}

// DIConnectPayload connects (and authenticates) to a server.
type DIConnectPayload struct {
	ServerID string `json:"server_id"`
	// Optional per-connection credentials; override ServerConfig creds.
	Username string `json:"username,omitempty"`
	Password string `json:"password,omitempty"`
	// Optional device code (e.g. AE30BED4) for studio adapter identity.
	DeviceCode string `json:"device_code,omitempty"`
	// Optional full MAC (e.g. 4C11AE30BED4) for Socket.IO instanceId.
	InstanceId string `json:"instance_id,omitempty"`
}

// DIConnectAckPayload reports connect result.
type DIConnectAckPayload struct {
	ServerID string `json:"server_id"`
	OK       bool   `json:"ok"`
	Reason   string `json:"reason,omitempty"`
	// For hermes_studio: device id assigned by the server (after mcu.ready).
	DeviceID string `json:"device_id,omitempty"`
}

// ServerInfo is the public (non-secret) description of a server in the list.
type ServerInfo struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	Type    string `json:"type"`    // hermes_studio | generic_ws
	Enabled bool   `json:"enabled"`
}

// DIListRespPayload is the server list returned to the client.
type DIListRespPayload struct {
	Servers []ServerInfo `json:"servers"`
}

// Session is a unified session-state snapshot.
type Session struct {
	ID         string `json:"id"`
	Title      string `json:"title,omitempty"`
	Status     string `json:"status,omitempty"` // active | waiting | done | error
	Unread     int    `json:"unread,omitempty"`
	LastActive int64  `json:"last_active,omitempty"`
	ServerID   string `json:"server_id,omitempty"`
}

// DISessionUpdatePayload carries a diff/whole snapshot of sessions.
type DISessionUpdatePayload struct {
	ServerID string    `json:"server_id"`
	Full     bool      `json:"full"` // true = full snapshot, false = incremental diff
	Sessions []Session `json:"sessions"`
}

// DISessionPollPayload requests a session snapshot.
// ServerID may name a specific backend; empty means "the focused one".
type DISessionPollPayload struct {
	ServerID string `json:"server_id,omitempty"`
}

// DIErrorPayload reports a server-scoped failure so the client can surface it
// instead of waiting for a response that will never arrive.
type DIErrorPayload struct {
	ServerID string `json:"server_id,omitempty"`
	Message  string `json:"message"`
}

// DISwitchServerPayload switches the active server (single WS stays open).
type DISwitchServerPayload struct {
	ServerID string `json:"server_id"`
}

// DIVoiceCmdPayload begins a voice command targeted at a session.
type DIVoiceCmdPayload struct {
	SessionID string `json:"session_id"`
	ServerID  string `json:"server_id,omitempty"` // omit => active server
}

// DIVoiceDataPayload carries one voice chunk.
type DIVoiceDataPayload struct {
	SessionID string `json:"session_id"`
	Chunk     string `json:"chunk"` // base64
	Last      bool   `json:"last"`  // final frame of the utterance
}

// DIAuthReqPayload asks the user to make an authorization decision.
type DIAuthReqPayload struct {
	SessionID string   `json:"session_id,omitempty"`
	Prompt    string   `json:"prompt"`
	Choices   []string `json:"choices,omitempty"` // optional preset choices
}

// DIAuthRespPayload is the user's/voice decision.
type DIAuthRespPayload struct {
	SessionID string `json:"session_id,omitempty"`
	Choice    string `json:"choice,omitempty"` // selected choice / free text
	Value     string `json:"value,omitempty"`  // alternate field
}
