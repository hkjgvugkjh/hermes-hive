package admin

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"hermes-proxy/internal/config"
)

func TestAdminAPIServers(t *testing.T) {
	cfg := &config.Config{
		Listen:     ":8080",
		WSPath:     "/ws",
		AdminPath:  "/admin",
		AdminToken: "test-token",
		Auth: config.AuthConfig{
			Method: config.AuthMethodStaticToken,
			StaticToken: &config.StaticTokenAuth{
				Token: "proxy-token",
			},
		},
		Servers: []config.ServerConfig{
			{ID: "test1", Name: "Test Server", URL: "http://localhost:3000", Enabled: true},
		},
	}

	srv := NewServer(cfg, ":0")
	ts := httptest.NewServer(srv)
	defer ts.Close()

	// Test GET /api/servers without auth
	resp, err := http.Get(ts.URL + "/api/servers")
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != http.StatusUnauthorized {
		t.Errorf("Expected 401, got %d", resp.StatusCode)
	}

	// Test GET /api/servers with auth
	req, _ := http.NewRequest("GET", ts.URL+"/api/servers", nil)
	req.Header.Set("Authorization", "Bearer test-token")
	resp, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Errorf("Expected 200, got %d", resp.StatusCode)
	}

	var result map[string]interface{}
	json.NewDecoder(resp.Body).Decode(&result)
	servers := result["servers"].([]interface{})
	if len(servers) != 1 {
		t.Errorf("Expected 1 server, got %d", len(servers))
	}
}

func TestAdminAPIPostServer(t *testing.T) {
	cfg := &config.Config{
		Listen:     ":8080",
		WSPath:     "/ws",
		AdminPath:  "/admin",
		AdminToken: "test-token",
		Auth: config.AuthConfig{
			Method: config.AuthMethodStaticToken,
			StaticToken: &config.StaticTokenAuth{
				Token: "proxy-token",
			},
		},
		Servers: []config.ServerConfig{},
	}
	cfg.ConfigPath = "/tmp/test-config.json"

	srv := NewServer(cfg, ":0")
	ts := httptest.NewServer(srv)
	defer ts.Close()

	// POST a new server
	body := `{"id":"new1","name":"New Server","url":"http://example.com:3000","enabled":true,"profile":"default"}`
	req, _ := http.NewRequest("POST", ts.URL+"/api/servers", strings.NewReader(body))
	req.Header.Set("Authorization", "Bearer test-token")
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Errorf("Expected 200, got %d", resp.StatusCode)
	}

	// Verify server was added
	if len(cfg.Servers) != 1 {
		t.Errorf("Expected 1 server in config, got %d", len(cfg.Servers))
	}
	if cfg.Servers[0].ID != "new1" {
		t.Errorf("Expected server ID 'new1', got '%s'", cfg.Servers[0].ID)
	}
}

func TestAdminAPIDeleteServer(t *testing.T) {
	cfg := &config.Config{
		Listen:     ":8080",
		WSPath:     "/ws",
		AdminPath:  "/admin",
		AdminToken: "test-token",
		Auth: config.AuthConfig{
			Method: config.AuthMethodStaticToken,
			StaticToken: &config.StaticTokenAuth{
				Token: "proxy-token",
			},
		},
		Servers: []config.ServerConfig{
			{ID: "del1", Name: "To Delete", URL: "http://localhost:3000", Enabled: true},
		},
	}
	cfg.ConfigPath = "/tmp/test-config.json"

	srv := NewServer(cfg, ":0")
	ts := httptest.NewServer(srv)
	defer ts.Close()

	// DELETE the server
	req, _ := http.NewRequest("DELETE", ts.URL+"/api/servers/del1", nil)
	req.Header.Set("Authorization", "Bearer test-token")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Errorf("Expected 200, got %d", resp.StatusCode)
	}

	// Verify server was deleted
	if len(cfg.Servers) != 0 {
		t.Errorf("Expected 0 servers, got %d", len(cfg.Servers))
	}
}

func TestAdminAPITestConnection(t *testing.T) {
	// Create a test Hermes Studio server
	testServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/health" {
			w.WriteHeader(http.StatusOK)
			w.Write([]byte(`{"status":"ok"}`))
		} else {
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer testServer.Close()

	cfg := &config.Config{
		Listen:     ":8080",
		WSPath:     "/ws",
		AdminPath:  "/admin",
		AdminToken: "test-token",
		Auth: config.AuthConfig{
			Method: config.AuthMethodStaticToken,
			StaticToken: &config.StaticTokenAuth{
				Token: "proxy-token",
			},
		},
	}

	srv := NewServer(cfg, ":0")
	ts := httptest.NewServer(srv)
	defer ts.Close()

	// Test connection to the test server
	body := `{"url":"` + testServer.URL + `"}`
	req, _ := http.NewRequest("POST", ts.URL+"/api/test", strings.NewReader(body))
	req.Header.Set("Authorization", "Bearer test-token")
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Errorf("Expected 200, got %d", resp.StatusCode)
	}

	var result map[string]interface{}
	json.NewDecoder(resp.Body).Decode(&result)
	if result["success"] != true && result["health_ok"] != true {
		t.Errorf("Expected successful test, got: %v", result)
	}
}

func TestWebUI(t *testing.T) {
	cfg := &config.Config{
		Listen:     ":8080",
		WSPath:     "/ws",
		AdminPath:  "/admin",
		AdminToken: "",
		Auth: config.AuthConfig{
			Method: config.AuthMethodStaticToken,
			StaticToken: &config.StaticTokenAuth{
				Token: "proxy-token",
			},
		},
	}

	srv := NewServer(cfg, ":0")
	ts := httptest.NewServer(srv)
	defer ts.Close()

	// Get the web UI
	resp, err := http.Get(ts.URL + "/")
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Errorf("Expected 200, got %d", resp.StatusCode)
	}

	// Check content type
	ct := resp.Header.Get("Content-Type")
	if !strings.Contains(ct, "text/html") {
		t.Errorf("Expected text/html, got %s", ct)
	}
}
