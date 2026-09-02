package crypto

import (
	"bytes"
	"testing"
)

func TestGenerateKeyPair(t *testing.T) {
	kp, err := GenerateKeyPair()
	if err != nil {
		t.Fatalf("GenerateKeyPair failed: %v", err)
	}
	if bytes.Equal(kp.PublicKey[:], make([]byte, 32)) {
		t.Error("Public key is all zeros")
	}
	if bytes.Equal(kp.PrivateKey[:], make([]byte, 32)) {
		t.Error("Private key is all zeros")
	}
}

func TestSharedSecret(t *testing.T) {
	// Alice and Bob generate key pairs
	alice, err := GenerateKeyPair()
	if err != nil {
		t.Fatalf("Alice keypair failed: %v", err)
	}
	bob, err := GenerateKeyPair()
	if err != nil {
		t.Fatalf("Bob keypair failed: %v", err)
	}

	// Both compute shared secret
	aliceShared, err := alice.SharedSecret(bob.PublicKey)
	if err != nil {
		t.Fatalf("Alice shared secret failed: %v", err)
	}
	bobShared, err := bob.SharedSecret(alice.PublicKey)
	if err != nil {
		t.Fatalf("Bob shared secret failed: %v", err)
	}

	// Shared secrets must match
	if !bytes.Equal(aliceShared, bobShared) {
		t.Errorf("Shared secrets don't match:\n  alice: %x\n  bob:   %x", aliceShared, bobShared)
	}
}

func TestEncryptDecrypt(t *testing.T) {
	key := make([]byte, 32)
	for i := range key {
		key[i] = byte(i)
	}

	plaintext := []byte("Hello, Hermes Hive! This is a test message for ChaCha20-Poly1305 encryption.")

	// Encrypt
	ciphertext, err := Encrypt(key, plaintext)
	if err != nil {
		t.Fatalf("Encrypt failed: %v", err)
	}

	// Ciphertext should be longer than plaintext (nonce + tag)
	if len(ciphertext) <= len(plaintext) {
		t.Error("Ciphertext should be longer than plaintext")
	}

	// Decrypt
	decrypted, err := Decrypt(key, ciphertext)
	if err != nil {
		t.Fatalf("Decrypt failed: %v", err)
	}

	if !bytes.Equal(decrypted, plaintext) {
		t.Errorf("Decrypted doesn't match:\n  got:  %s\n  want: %s", decrypted, plaintext)
	}
}

func TestEncryptDecryptWrongKey(t *testing.T) {
	key := make([]byte, 32)
	for i := range key {
		key[i] = byte(i)
	}
	wrongKey := make([]byte, 32)
	for i := range wrongKey {
		wrongKey[i] = byte(i + 1)
	}

	plaintext := []byte("test message")
	ciphertext, _ := Encrypt(key, plaintext)

	_, err := Decrypt(wrongKey, ciphertext)
	if err == nil {
		t.Error("Decrypt with wrong key should fail")
	}
}

func TestPublicKeyBase64Roundtrip(t *testing.T) {
	kp, _ := GenerateKeyPair()
	encoded := kp.PublicKeyBase64()

	decoded, err := PublicKeyFromBase64(encoded)
	if err != nil {
		t.Fatalf("PublicKeyFromBase64 failed: %v", err)
	}

	if !bytes.Equal(decoded[:], kp.PublicKey[:]) {
		t.Error("Public key roundtrip failed")
	}
}

func TestHandshakeEncodeDecode(t *testing.T) {
	msg := &HandshakeMessage{
		PublicKey: "dGVzdF9wdWJsaWNfa2V5XzMyYnl0ZXNfMTIzNDU=",
		Token:     "test-token",
	}

	encoded, err := EncodeHandshake(msg)
	if err != nil {
		t.Fatalf("EncodeHandshake failed: %v", err)
	}

	decoded, err := DecodeHandshake(encoded)
	if err != nil {
		t.Fatalf("DecodeHandshake failed: %v", err)
	}

	if decoded.PublicKey != msg.PublicKey {
		t.Errorf("Public key mismatch: %s != %s", decoded.PublicKey, msg.PublicKey)
	}
	if decoded.Token != msg.Token {
		t.Errorf("Token mismatch: %s != %s", decoded.Token, msg.Token)
	}
}
