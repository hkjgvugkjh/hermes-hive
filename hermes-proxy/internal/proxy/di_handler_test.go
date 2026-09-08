package proxy

import (
	"testing"

	"hermes-proxy/internal/config"
	"hermes-proxy/internal/di"
)

// newTestServer builds a Server with a single in-memory config (no real
// listeners) for exercising DI control handlers.
func newTestServer() *Server {
	cfg := config.DefaultConfig()
	cfg.Auth.Method = config.AuthMethodStaticToken
	cfg.Auth.StaticToken = &config.StaticTokenAuth{Token: "test"}
	cfg.Servers = []config.ServerConfig{
		{ID: "local", Name: "Local Studio", URL: "http://localhost:8648", Type: config.ServerTypeHermesStudio, Enabled: true, Profile: "default"},
		{ID: "off", Name: "Disabled", URL: "http://localhost:9", Type: config.ServerTypeGenericWS, Enabled: false},
	}
	return NewServer(cfg)
}

func TestGetServerPublicListStripsSecrets(t *testing.T) {
	s := newTestServer()
	list := s.cfg.GetServerPublicList()
	if len(list) != 2 {
		t.Fatalf("expected 2 servers, got %d", len(list))
	}
	for _, sv := range list {
		if sv.Type == "" {
			t.Errorf("server %s missing type", sv.ID)
		}
	}
}

func TestDIEventMirrorsLocally(t *testing.T) {
	ev := diEvent{Direction: "down", Event: "mcu.auth", Data: `{"x":1}`}
	b, err := di.EncodePayload(ev)
	if err != nil {
		t.Fatal(err)
	}
	var round diEvent
	if err := di.DecodePayload(b, &round); err != nil {
		t.Fatal(err)
	}
	if round.Event != "mcu.auth" {
		t.Fatalf("round-trip event mismatch: %s", round.Event)
	}
}

