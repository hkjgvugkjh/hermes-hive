// Package crypto provides X25519 key exchange and ChaCha20-Poly1305 encryption
// for secure WebSocket communication between hermes-hive and hermes-proxy.
package crypto

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"

	"golang.org/x/crypto/chacha20poly1305"
	"golang.org/x/crypto/curve25519"
)

// KeyPair represents an X25519 key pair for ECDH key exchange.
type KeyPair struct {
	PrivateKey [32]byte
	PublicKey  [32]byte
}

// GenerateKeyPair creates a new X25519 key pair using crypto/rand.
func GenerateKeyPair() (*KeyPair, error) {
	var priv, pub [32]byte
	if _, err := io.ReadFull(rand.Reader, priv[:]); err != nil {
		return nil, fmt.Errorf("failed to generate private key: %w", err)
	}
	// Clamp private key per RFC 7748
	priv[0] &= 248
	priv[31] &= 127
	priv[31] |= 64
	curve25519.ScalarBaseMult(&pub, &priv)
	return &KeyPair{PrivateKey: priv, PublicKey: pub}, nil
}

// SharedSecret computes the shared secret using X25519 ECDH.
func (kp *KeyPair) SharedSecret(peerPublicKey [32]byte) ([]byte, error) {
	var shared [32]byte
	curve25519.ScalarMult(&shared, &kp.PrivateKey, &peerPublicKey)
	// Derive a 32-byte key using SHA-256
	hash := sha256.Sum256(shared[:])
	return hash[:], nil
}

// Encrypt encrypts plaintext using ChaCha20-Poly1305 with the given key.
// Returns: nonce (12 bytes) || ciphertext || tag (16 bytes).
func Encrypt(key, plaintext []byte) ([]byte, error) {
	aead, err := chacha20poly1305.New(key)
	if err != nil {
		return nil, fmt.Errorf("failed to create AEAD: %w", err)
	}
	nonce := make([]byte, aead.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return nil, fmt.Errorf("failed to generate nonce: %w", err)
	}
	ciphertext := aead.Seal(nonce, nonce, plaintext, nil)
	return ciphertext, nil
}

// Decrypt decrypts ciphertext using ChaCha20-Poly1305 with the given key.
// Expects: nonce (12 bytes) || ciphertext || tag (16 bytes).
func Decrypt(key, ciphertext []byte) ([]byte, error) {
	aead, err := chacha20poly1305.New(key)
	if err != nil {
		return nil, fmt.Errorf("failed to create AEAD: %w", err)
	}
	if len(ciphertext) < aead.NonceSize() {
		return nil, fmt.Errorf("ciphertext too short")
	}
	nonce, ct := ciphertext[:aead.NonceSize()], ciphertext[aead.NonceSize():]
	return aead.Open(nil, nonce, ct, nil)
}

// PublicKeyBase64 returns the base64-encoded public key.
func (kp *KeyPair) PublicKeyBase64() string {
	return base64.StdEncoding.EncodeToString(kp.PublicKey[:])
}

// PublicKeyFromBase64 parses a base64-encoded public key.
func PublicKeyFromBase64(s string) ([32]byte, error) {
	var pub [32]byte
	b, err := base64.StdEncoding.DecodeString(s)
	if err != nil {
		return pub, fmt.Errorf("invalid base64: %w", err)
	}
	if len(b) != 32 {
		return pub, fmt.Errorf("invalid public key length: %d", len(b))
	}
	copy(pub[:], b)
	return pub, nil
}

// HandshakeMessage is exchanged during the WebSocket handshake.
type HandshakeMessage struct {
	PublicKey string `json:"public_key"` // Base64-encoded X25519 public key
	Token     string `json:"token"`      // Optional auth token
}

// EncodeHandshake encodes a handshake message to JSON.
func EncodeHandshake(msg *HandshakeMessage) ([]byte, error) {
	return json.Marshal(msg)
}

// DecodeHandshake decodes a JSON handshake message.
func DecodeHandshake(data []byte) (*HandshakeMessage, error) {
	var msg HandshakeMessage
	if err := json.Unmarshal(data, &msg); err != nil {
		return nil, fmt.Errorf("invalid handshake JSON: %w", err)
	}
	return &msg, nil
}
