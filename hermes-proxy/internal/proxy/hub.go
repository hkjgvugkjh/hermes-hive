package proxy

import (
	"log"
	"sync"
	"time"

	"hermes-proxy/internal/config"
)

// backendConn is one shared connection to a configured backend server.
//
// Under the client/dispatch/service model a backend connection is owned by the
// Server (the service layer), not by any single client. Many clients may
// subscribe to the same backendConn; the backend is dialled once and every
// event it produces is fanned out to all current subscribers.
type backendConn struct {
	id      string
	cfg     *config.ServerConfig
	adapter backendAdapter // nil for generic_ws (pure relay)

	mu      sync.Mutex
	deviceID string
	jwt      string
	state    backendState
	err      string
	lastErr  time.Time

	// dialMu serialises dial attempts; dialing blocks other acquirers so N
	// simultaneous first-attaches produce exactly one backend connection.
	dialMu   sync.Mutex
	dialed   bool

	// Session polling (hermes_studio only).
	pollStop chan struct{}

	// subscribers: clientID -> client. A client is added on DI connect and
	// removed on disconnect or when it switches away.
	subs map[string]*Client

	// refcount of in-flight operations; the conn is torn down when the last
	// subscriber leaves after idleTTL.
	lastUsed time.Time
	stopped  bool
}

type backendState string

const (
	backendConnecting backendState = "connecting"
	backendReady      backendState = "ready"
	backendFailed     backendState = "failed"
)

// backendIdleTTL is how long a shared backend is kept alive after its last
// subscriber goes away. Keeping it warm means a reconnecting client (or a
// second client) skips the mcu-login + Socket.IO handshake.
const backendIdleTTL = 5 * time.Minute

// backendHub owns every shared backend connection, keyed by server ID.
type backendHub struct {
	server *Server
	mu     sync.Mutex
	conns  map[string]*backendConn
}

func newBackendHub(s *Server) *backendHub {
	return &backendHub{server: s, conns: make(map[string]*backendConn)}
}

// acquire returns the shared backend for serverID, dialling it if needed, and
// subscribes client. It is safe for concurrent use by many clients.
//
// The returned status tells the caller whether this call actually established
// the connection (so it can log once) or joined an existing one.
func (h *backendHub) acquire(sc *config.ServerConfig, client *Client, creds diCreds) (*backendConn, error) {
	h.mu.Lock()
	bc := h.conns[sc.ID]
	if bc == nil {
		bc = &backendConn{
			id:       sc.ID,
			cfg:      sc,
			subs:     make(map[string]*Client),
			pollStop: make(chan struct{}),
		}
		h.conns[sc.ID] = bc
	}
	// Subscribe before releasing the hub lock so a concurrent release cannot
	// tear the conn down while we are still attaching.
	// A nil client means a service-layer warm-up (preconnect); nobody is
	// attached yet, so there is nothing to subscribe.
	if client != nil {
		bc.subscribe(client)
	}
	h.mu.Unlock()

	if bc.isReady() {
		bc.touch()
		return bc, nil
	}

	// Serialise dialling: whoever gets here first dials, everyone else waits
	// and then reuses the result. This is what makes N concurrent clients
	// share ONE backend connection instead of racing to open N of them.
	bc.dialMu.Lock()
	defer bc.dialMu.Unlock()
	if bc.dialed && bc.isReady() {
		bc.touch()
		return bc, nil
	}
	bc.dialed = true
	if err := h.dial(bc, creds); err != nil {
		// Leave the failed conn registered (with state=failed) so the error is
		// reported consistently to later clients instead of re-dialling in a
		// tight loop. release() will drop it once nobody is subscribed.
		return bc, err
	}
	return bc, nil
}

// dial establishes the backend session. Caller must not hold bc.mu.
func (h *backendHub) dial(bc *backendConn, creds diCreds) error {
	bc.mu.Lock()
	if bc.state == backendReady {
		bc.mu.Unlock()
		return nil
	}
	bc.state = backendConnecting
	bc.err = ""
	bc.mu.Unlock()

	if bc.cfg.Type == config.ServerTypeHermesStudio {
		ad := newStudioAdapter(h.server, bc.cfg, creds.user, creds.pass, bc)
		if creds.deviceCode != "" {
			ad.deviceID = upper(creds.deviceCode)
		}
		if creds.instanceID != "" {
			ad.instanceID = upper(creds.instanceID)
		}
		if err := ad.Connect(); err != nil {
			bc.mu.Lock()
			bc.state = backendFailed
			bc.err = err.Error()
			bc.lastErr = time.Now()
			bc.mu.Unlock()
			return err
		}
		bc.mu.Lock()
		bc.adapter = ad
		bc.deviceID = ad.deviceID
		bc.jwt = ad.jwt
		bc.state = backendReady
		bc.mu.Unlock()

		log.Printf("[hub] backend %s ready (device=%s)", bc.id, bc.deviceID)
		// One poller per backend, shared by all subscribers.
		go h.server.pollBackend(bc)
		return nil
	}

	// generic_ws: relay only, no adapter.
	bc.mu.Lock()
	bc.state = backendReady
	bc.mu.Unlock()
	log.Printf("[hub] backend %s ready (generic_ws relay)", bc.id)
	return nil
}

// preconnect dials every enabled backend at start-up so that a client's
// first attach is served by an already-warm connection.
//
// Under the client/dispatch/service model the backend is owned by the service
// layer, not by any client, so warming them at boot is legitimate and removes
// the "first client waits for mcu-login" latency. Failures are logged and
// retried in the background; they never block start-up.
func (h *backendHub) preconnect() {
	for i := range h.server.cfg.GetServers() {
		sc := &h.server.cfg.Servers[i]
		if !sc.Enabled {
			continue
		}
		go func(sc *config.ServerConfig) {
			creds := diCreds{user: sc.Username, pass: sc.Password}
			bc, err := h.acquire(sc, nil, creds)
			if err != nil {
				log.Printf("[hub] preconnect %s failed: %v (will retry)", sc.ID, err)
				go h.retryLoop(sc)
				return
			}
			log.Printf("[hub] preconnect %s ok (device=%s)", sc.ID, bc.deviceID)
		}(sc)
	}
}

// retryLoop re-dials a backend that failed to come up, with capped exponential
// backoff, until it succeeds or the backend is already healthy.
func (h *backendHub) retryLoop(sc *config.ServerConfig) {
	const (
		initial = 5 * time.Second
		maxWait = 5 * time.Minute
	)
	wait := initial
	for {
		time.Sleep(wait)
		if bc := h.get(sc.ID); bc != nil && bc.isReady() {
			return
		}
		creds := diCreds{user: sc.Username, pass: sc.Password}
		bc, err := h.acquire(sc, nil, creds)
		if err == nil {
			log.Printf("[hub] backend %s recovered (device=%s)", sc.ID, bc.deviceID)
			return
		}
		log.Printf("[hub] retry %s failed: %v (next in %s)", sc.ID, err, wait)
		if wait < maxWait {
			wait *= 2
			if wait > maxWait {
				wait = maxWait
			}
		}
	}
}

// release removes a client's subscription. When the last subscriber leaves the
// backend is kept warm for backendIdleTTL and then closed.
func (h *backendHub) release(serverID string, client *Client) {
	h.mu.Lock()
	bc := h.conns[serverID]
	if bc == nil {
		h.mu.Unlock()
		return
	}
	h.mu.Unlock()

	if !bc.unsubscribe(client) {
		return
	}
	// Last subscriber gone: schedule teardown.
	time.AfterFunc(backendIdleTTL, func() { h.reapIfIdle(serverID) })
}

// releaseAll drops every subscription held by client (used on disconnect).
func (h *backendHub) releaseAll(client *Client) {
	h.mu.Lock()
	ids := make([]string, 0, len(h.conns))
	for id := range h.conns {
		ids = append(ids, id)
	}
	h.mu.Unlock()
	for _, id := range ids {
		h.release(id, client)
	}
}

// reapIfIdle closes the backend if it still has no subscribers.
func (h *backendHub) reapIfIdle(serverID string) {
	h.mu.Lock()
	bc := h.conns[serverID]
	if bc == nil {
		h.mu.Unlock()
		return
	}
	bc.mu.Lock()
	empty := len(bc.subs) == 0
	expired := time.Since(bc.lastUsed) >= backendIdleTTL
	bc.mu.Unlock()
	if !empty || !expired {
		h.mu.Unlock()
		return
	}
	delete(h.conns, serverID)
	h.mu.Unlock()
	bc.close()
	log.Printf("[hub] backend %s idle-reaped", serverID)
}

// get returns a backend without subscribing (used by HTTP-side lookups).
func (h *backendHub) get(serverID string) *backendConn {
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.conns[serverID]
}

// --- backendConn helpers -------------------------------------------------

// isReady reports whether the backend connection is established.
func (bc *backendConn) isReady() bool {
	bc.mu.Lock()
	defer bc.mu.Unlock()
	return bc.state == backendReady
}

// touch updates lastUsed so the idle reaper keeps the conn warm.
func (bc *backendConn) touch() {
	bc.mu.Lock()
	bc.lastUsed = time.Now()
	bc.mu.Unlock()
}

func (bc *backendConn) subscribe(c *Client) {
	bc.mu.Lock()
	defer bc.mu.Unlock()
	bc.subs[c.ID] = c
	bc.lastUsed = time.Now()
}

// unsubscribe removes c and reports whether the backend is now empty.
func (bc *backendConn) unsubscribe(c *Client) bool {
	bc.mu.Lock()
	defer bc.mu.Unlock()
	delete(bc.subs, c.ID)
	bc.lastUsed = time.Now()
	return len(bc.subs) == 0
}

// subscribers returns a snapshot of the subscribed clients.
func (bc *backendConn) subscribers() []*Client {
	bc.mu.Lock()
	defer bc.mu.Unlock()
	out := make([]*Client, 0, len(bc.subs))
	for _, c := range bc.subs {
		out = append(out, c)
	}
	return out
}

func (bc *backendConn) close() {
	bc.mu.Lock()
	if bc.stopped {
		bc.mu.Unlock()
		return
	}
	bc.stopped = true
	ad := bc.adapter
	bc.adapter = nil
	bc.state = backendFailed
	stop := bc.pollStop
	bc.mu.Unlock()

	if stop != nil {
		select {
		case <-stop:
			// already closed
		default:
			close(stop)
		}
	}
	if ad != nil {
		ad.Close()
	}
}

func upper(s string) string {
	out := []byte(s)
	for i := range out {
		if out[i] >= 'a' && out[i] <= 'z' {
			out[i] -= 32
		}
	}
	return string(out)
}
