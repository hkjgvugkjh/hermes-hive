package protocol

import (
	"bytes"
	"testing"
)

func TestEncodeDecodeFrame(t *testing.T) {
	original := &Frame{
		Type:    TypeHTTPRequest,
		Payload: []byte("test payload data"),
	}

	encoded := EncodeFrame(original)

	if len(encoded) != 1+4+len(original.Payload) {
		t.Errorf("Encoded length mismatch: %d != %d", len(encoded), 1+4+len(original.Payload))
	}

	msgType, length, err := DecodeFrameHeader(encoded[:5])
	if err != nil {
		t.Fatalf("DecodeFrameHeader failed: %v", err)
	}

	if msgType != original.Type {
		t.Errorf("Type mismatch: %d != %d", msgType, original.Type)
	}

	if length != uint32(len(original.Payload)) {
		t.Errorf("Length mismatch: %d != %d", length, len(original.Payload))
	}

	if !bytes.Equal(encoded[5:], original.Payload) {
		t.Error("Payload mismatch")
	}
}

func TestEncodeDecodePayload(t *testing.T) {
	original := &HTTPRequestPayload{
		ServerID: "test-server",
		Method:   "POST",
		Path:     "/api/test",
		Headers:  map[string]string{"Content-Type": "application/json"},
		Body:     []byte(`{"test":true}`),
	}

	encoded, err := EncodePayload(original)
	if err != nil {
		t.Fatalf("EncodePayload failed: %v", err)
	}

	decoded := &HTTPRequestPayload{}
	if err := DecodePayload(encoded, decoded); err != nil {
		t.Fatalf("DecodePayload failed: %v", err)
	}

	if decoded.ServerID != original.ServerID {
		t.Errorf("ServerID mismatch: %s != %s", decoded.ServerID, original.ServerID)
	}
	if decoded.Method != original.Method {
		t.Errorf("Method mismatch: %s != %s", decoded.Method, original.Method)
	}
	if decoded.Path != original.Path {
		t.Errorf("Path mismatch: %s != %s", decoded.Path, original.Path)
	}
	if !bytes.Equal(decoded.Body, original.Body) {
		t.Error("Body mismatch")
	}
}

func TestDecodeFrameHeaderTooShort(t *testing.T) {
	_, _, err := DecodeFrameHeader([]byte{0x01, 0x02})
	if err == nil {
		t.Error("Expected error for short header")
	}
}
