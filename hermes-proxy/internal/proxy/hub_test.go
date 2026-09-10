package proxy

import (
	"sync"
	"testing"
	"time"

	"hermes-proxy/internal/config"
)

// newTestServer builds a Server with a hub and a couple of enabled backends.
func newHubTestServer() *Server {
	cfg := &config.Config{
		Servers: []config.ServerConfig{
			{ID: "s1", Name: "one", URL: "http://127.0.0.1:1", Type: config.ServerTypeGenericWS, Enabled: true},
			{ID: "s2", Name: "two", URL: "http://127.0.0.1:2", Type: config.ServerTypeGenericWS, Enabled: true},
		},
	}
	s := NewServer(cfg)
	return s
}

func newHubTestClient(id string) *Client {
	return &Client{
		ID:         id,
		subscribed: make(map[string]struct{}),
	}
}

// TestHubSharesBackendAcrossClients verifies the core of the
// client/dispatch/service model: two clients attaching to the same server get
// the SAME *backendConn and both end up subscribed to it.
func TestHubSharesBackendAcrossClients(t *testing.T) {
	s := newHubTestServer()
	sc := s.cfg.GetServer("s1")

	c1 := newHubTestClient("c1")
	c2 := newHubTestClient("c2")

	bc1, err := s.hub.acquire(sc, c1, diCreds{})
	if err != nil {
		t.Fatalf("acquire c1: %v", err)
	}
	bc2, err := s.hub.acquire(sc, c2, diCreds{})
	if err != nil {
		t.Fatalf("acquire c2: %v", err)
	}

	if bc1 != bc2 {
		t.Fatal("expected both clients to share one backendConn, got two distinct conns")
	}

	subs := bc1.subscribers()
	if len(subs) != 2 {
		t.Fatalf("expected 2 subscribers, got %d", len(subs))
	}
	ids := map[string]bool{}
	for _, c := range subs {
		ids[c.ID] = true
	}
	if !ids["c1"] || !ids["c2"] {
		t.Fatalf("subscribers missing clients: %v", ids)
	}
}

// TestClientHoldsMultipleBackends verifies a client can stay attached to
// several servers at once (the old model replaced the single active backend).
func TestClientHoldsMultipleBackends(t *testing.T) {
	s := newHubTestServer()

	c := newHubTestClient("multi")
	for _, id := range []string{"s1", "s2"} {
		sc := s.cfg.GetServer(id)
		if _, err := s.attachBackend(c, sc, diCreds{}); err != nil {
			t.Fatalf("attach %s: %v", id, err)
		}
	}

	c.mu.Lock()
	n := len(c.subscribed)
	c.mu.Unlock()
	if n != 2 {
		t.Fatalf("expected client subscribed to 2 backends, got %d", n)
	}
	if s.hub.get("s1") == nil || s.hub.get("s2") == nil {
		t.Fatal("expected both backends registered in hub")
	}
}

// TestSwitchDoesNotDropPreviousBackend verifies switching focus keeps the
// earlier subscription alive, so background updates keep flowing.
func TestSwitchDoesNotDropPreviousBackend(t *testing.T) {
	s := newHubTestServer()

	c := newHubTestClient("switcher")
	sc1 := s.cfg.GetServer("s1")
	if _, err := s.attachBackend(c, sc1, diCreds{}); err != nil {
		t.Fatalf("attach s1: %v", err)
	}

	// Focus moves to s2.
	sc2 := s.cfg.GetServer("s2")
	if _, err := s.attachBackend(c, sc2, diCreds{}); err != nil {
		t.Fatalf("attach s2: %v", err)
	}

	c.mu.Lock()
	current := c.current
	_, stillOnS1 := c.subscribed["s1"]
	c.mu.Unlock()

	if current != "s2" {
		t.Fatalf("expected focus on s2, got %q", current)
	}
	if !stillOnS1 {
		t.Fatal("expected s1 subscription to survive the switch")
	}
	if n := len(s.hub.get("s1").subscribers()); n != 1 {
		t.Fatalf("expected s1 to still have 1 subscriber, got %d", n)
	}
}

// TestReleaseOtherClientKeepsBackend verifies one client leaving does not tear
// down a backend that another client is still using.
func TestReleaseOtherClientKeepsBackend(t *testing.T) {
	s := newHubTestServer()
	sc := s.cfg.GetServer("s1")

	c1 := newHubTestClient("a")
	c2 := newHubTestClient("b")
	bc, _ := s.hub.acquire(sc, c1, diCreds{})
	if _, err := s.hub.acquire(sc, c2, diCreds{}); err != nil {
		t.Fatalf("acquire b: %v", err)
	}

	s.hub.release("s1", c1)

	if n := len(bc.subscribers()); n != 1 {
		t.Fatalf("expected backend to keep 1 subscriber, got %d", n)
	}
	if s.hub.get("s1") == nil {
		t.Fatal("backend must not be dropped while another client is attached")
	}
}

// TestHubConcurrentAcquire hammers the hub from many goroutines to catch
// races in subscribe/register (run with -race).
func TestHubConcurrentAcquire(t *testing.T) {
	s := newHubTestServer()

	var wg sync.WaitGroup
	for i := 0; i < 32; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			c := newHubTestClient(string(rune('a'+i%16)) + "-" + string(rune('0'+i/16)))
			for _, id := range []string{"s1", "s2"} {
				if _, err := s.attachBackend(c, s.cfg.GetServer(id), diCreds{}); err != nil {
					t.Errorf("attach: %v", err)
					return
				}
			}
		}(i)
	}
	wg.Wait()

	// Reap is time-based; just assert both backends exist and have subscribers.
	for _, id := range []string{"s1", "s2"} {
		bc := s.hub.get(id)
		if bc == nil {
			t.Fatalf("backend %s missing", id)
		}
		if n := len(bc.subscribers()); n == 0 {
			t.Fatalf("backend %s has no subscribers", id)
		}
	}
}

// TestFocusedBackendFallsBackToSingle verifies focus resolution when current
// is unset but exactly one subscription exists.
func TestFocusedBackendFallsBackToSingle(t *testing.T) {
	s := newHubTestServer()
	c := newHubTestClient("solo")
	c.subscribed["s1"] = struct{}{}
	if _, err := s.hub.acquire(s.cfg.GetServer("s1"), c, diCreds{}); err != nil {
		t.Fatalf("acquire: %v", err)
	}
	if got := s.focusedBackend(c); got == nil || got.id != "s1" {
		t.Fatalf("expected focus to fall back to s1, got %v", got)
	}

	empty := newHubTestClient("none")
	if got := s.focusedBackend(empty); got != nil {
		t.Fatalf("expected nil focus for unattached client, got %v", got)
	}
}

// TestReapDropsIdleBackend verifies an unsubscribed backend is eventually
// removed. A short sleep keeps the test fast; the constant itself is 5m.
func TestReapDropsIdleBackend(t *testing.T) {
	s := newHubTestServer()
	sc := s.cfg.GetServer("s1")
	c := newHubTestClient("temp")
	if _, err := s.hub.acquire(sc, c, diCreds{}); err != nil {
		t.Fatalf("acquire: %v", err)
	}
	s.hub.release("s1", c)

	// Force the idle window to have elapsed.
	bc := s.hub.get("s1")
	bc.mu.Lock()
	bc.lastUsed = time.Now().Add(-backendIdleTTL - time.Second)
	bc.mu.Unlock()

	s.hub.reapIfIdle("s1")
	if s.hub.get("s1") != nil {
		t.Fatal("expected idle backend to be reaped")
	}
}

// TestConcurrentFirstAttachDialsOnce is the regression test for a real race:
// N clients attaching to the same server simultaneously used to each see
// state!=ready and dial their own backend, producing N connections (and N
// mcu-logins) instead of one shared one.
func TestConcurrentFirstAttachDialsOnce(t *testing.T) {
	s := newHubTestServer()
	sc := s.cfg.GetServer("s1")

	const n = 16
	clients := make([]*Client, n)
	for i := range clients {
		clients[i] = newHubTestClient("race-" + string(rune('A'+i)))
	}

	var wg sync.WaitGroup
	conns := make([]*backendConn, n)
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			bc, err := s.hub.acquire(sc, clients[i], diCreds{})
			if err != nil {
				t.Errorf("acquire: %v", err)
				return
			}
			conns[i] = bc
		}(i)
	}
	wg.Wait()

	first := conns[0]
	if first == nil {
		t.Fatal("no conn returned")
	}
	for i, bc := range conns {
		if bc != first {
			t.Fatalf("client %d got a different backendConn than client 0", i)
		}
	}
	if got := len(first.subscribers()); got != n {
		t.Fatalf("expected %d subscribers on the shared conn, got %d", n, got)
	}
}
