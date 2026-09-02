package auth

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"hermes-proxy/internal/config"
)

func TestStaticTokenValid(t *testing.T) {
	cfg := &config.AuthConfig{
		Method: config.AuthMethodStaticToken,
		StaticToken: &config.StaticTokenAuth{
			Token: "test-secret",
		},
	}
	v := NewValidator(cfg)

	valid, err := v.Validate("test-secret")
	if err != nil {
		t.Fatalf("Validate failed: %v", err)
	}
	if !valid {
		t.Error("Expected valid token")
	}
}

func TestStaticTokenInvalid(t *testing.T) {
	cfg := &config.AuthConfig{
		Method: config.AuthMethodStaticToken,
		StaticToken: &config.StaticTokenAuth{
			Token: "test-secret",
		},
	}
	v := NewValidator(cfg)

	valid, err := v.Validate("wrong-token")
	if err == nil {
		t.Error("Expected error for wrong token")
	}
	if valid {
		t.Error("Expected invalid token")
	}
}

func TestStaticTokenEmpty(t *testing.T) {
	cfg := &config.AuthConfig{
		Method: config.AuthMethodStaticToken,
		StaticToken: &config.StaticTokenAuth{
			Token: "test-secret",
		},
	}
	v := NewValidator(cfg)

	valid, err := v.Validate("")
	if err == nil {
		t.Error("Expected error for empty token")
	}
	if valid {
		t.Error("Expected invalid token")
	}
}

func TestHTTPAPIValid(t *testing.T) {
	// Create test server
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		auth := r.Header.Get("Authorization")
		if auth == "Bearer valid-token" {
			w.WriteHeader(http.StatusOK)
			w.Write([]byte(`{"status":"ok"}`))
			return
		}
		w.WriteHeader(http.StatusUnauthorized)
	}))
	defer server.Close()

	cfg := &config.AuthConfig{
		Method: config.AuthMethodHTTPAPI,
		HTTPAPI: &config.HTTPAPIAuth{
			URL:          server.URL,
			Header:       "Authorization",
			TokenPrefix:  "Bearer ",
			Timeout:      5,
		},
	}
	v := NewValidator(cfg)

	valid, err := v.Validate("valid-token")
	if err != nil {
		t.Fatalf("Validate failed: %v", err)
	}
	if !valid {
		t.Error("Expected valid token")
	}
}

func TestHTTPAPIInvalid(t *testing.T) {
	// Create test server
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
		w.Write([]byte(`{"error":"invalid token"}`))
	}))
	defer server.Close()

	cfg := &config.AuthConfig{
		Method: config.AuthMethodHTTPAPI,
		HTTPAPI: &config.HTTPAPIAuth{
			URL:         server.URL,
			Header:      "Authorization",
			TokenPrefix: "Bearer ",
			Timeout:     5,
		},
	}
	v := NewValidator(cfg)

	valid, err := v.Validate("invalid-token")
	if err == nil {
		t.Error("Expected error for invalid token")
	}
	if valid {
		t.Error("Expected invalid token")
	}
}

func TestExtractTokenFromHeader(t *testing.T) {
	r := httptest.NewRequest("GET", "/ws", nil)
	r.Header.Set("X-Auth-Token", "test-token")

	token := ExtractToken(r)
	if token != "test-token" {
		t.Errorf("Expected 'test-token', got '%s'", token)
	}
}

func TestExtractTokenFromAuthorization(t *testing.T) {
	r := httptest.NewRequest("GET", "/ws", nil)
	r.Header.Set("Authorization", "Bearer my-token")

	token := ExtractToken(r)
	if token != "my-token" {
		t.Errorf("Expected 'my-token', got '%s'", token)
	}
}

func TestExtractTokenFromQuery(t *testing.T) {
	r := httptest.NewRequest("GET", "/ws?token=query-token", nil)

	token := ExtractToken(r)
	if token != "query-token" {
		t.Errorf("Expected 'query-token', got '%s'", token)
	}
}

func TestExtractTokenPriority(t *testing.T) {
	r := httptest.NewRequest("GET", "/ws?token=query-token", nil)
	r.Header.Set("X-Auth-Token", "header-token")
	r.Header.Set("Authorization", "Bearer auth-token")

	token := ExtractToken(r)
	// X-Auth-Token should take priority
	if token != "header-token" {
		t.Errorf("Expected 'header-token', got '%s'", token)
	}
}
