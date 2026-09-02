// Package protocol defines the WebSocket message protocol between hermes-hive and hermes-proxy.
//
// Message flow:
//  1. Handshake: exchange X25519 public keys, derive shared secret
//  2. Encrypted session: all subsequent messages are ChaCha20-Poly1305 encrypted
//
// Frame format (after handshake):
//   [4 bytes: payload length (big-endian)][encrypted payload]
package protocol

import (
	"encoding/binary"
	"encoding/json"
	"fmt"
)

// MessageType identifies the type of protocol message.
type MessageType byte

const (
	TypeHandshake   MessageType = 0x01 // Initial key exchange
	TypeHandshakeOK MessageType = 0x02 // Handshake acknowledgment
	TypeHTTPRequest MessageType = 0x10 // Encrypted HTTP request
	TypeHTTPResponse MessageType = 0x11 // Encrypted HTTP response
	TypeError       MessageType = 0xFF // Error notification
)

// Frame is the wire format for all protocol messages.
type Frame struct {
	Type    MessageType
	Payload []byte
}

// EncodeFrame encodes a frame to bytes: [1 type][4 length][payload].
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

// HTTPRequestPayload is the encrypted payload for HTTP proxy requests.
type HTTPRequestPayload struct {
	ServerID string            `json:"server_id"` // Target server identifier
	Method   string            `json:"method"`     // GET, POST, PUT, DELETE
	Path     string            `json:"path"`       // /api/...
	Headers  map[string]string `json:"headers"`
	Body     []byte            `json:"body"`
}

// HTTPResponsePayload is the encrypted payload for HTTP proxy responses.
type HTTPResponsePayload struct {
	StatusCode int               `json:"status_code"`
	Headers    map[string]string `json:"headers"`
	Body       []byte            `json:"body"`
}

// EncodePayload encodes a payload to JSON.
func EncodePayload(v interface{}) ([]byte, error) {
	return json.Marshal(v)
}

// DecodePayload decodes a JSON payload.
func DecodePayload(data []byte, v interface{}) error {
	return json.Unmarshal(data, v)
}

// ErrorPayload carries error information.
type ErrorPayload struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}
