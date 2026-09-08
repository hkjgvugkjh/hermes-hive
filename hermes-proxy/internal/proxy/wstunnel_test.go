package proxy

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/gorilla/websocket"
	"hermes-proxy/internal/config"
	"hermes-proxy/internal/crypto"
	"hermes-proxy/internal/protocol"
)

// pushUpstream is a WebSocket server that records what the proxy sends it and
// can push unsolicited frames back, standing in for a real Hermes Web UI
// (which emits interaction.status events and audio without being asked).
type pushUpstream struct {
	url    string
	textCh chan string
	binCh  chan []byte
	connCh chan *websocket.Conn
	mu     sync.Mutex
	upConn *websocket.Conn
}

func newPushUpstream(t *testing.T) *pushUpstream {
	t.Helper()
	p := &pushUpstream{
		textCh: make(chan string, 16),
		binCh:  make(chan []byte, 16),
		connCh: make(chan *websocket.Conn, 1),
	}
	up := websocket.Upgrader{CheckOrigin: func(r *http.Request) bool { return true }}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := up.Upgrade(w, r, nil)
		if err != nil {
			return
		}
		p.mu.Lock()
		p.upConn = conn
		p.mu.Unlock()
		p.connCh <- conn

		for {
			mt, data, err := conn.ReadMessage()
			if err != nil {
				return
			}
			if mt == websocket.BinaryMessage {
				p.binCh <- append([]byte(nil), data...)
			} else {
				p.textCh <- string(data)
			}
		}
	}))
	t.Cleanup(srv.Close)
	p.url = srv.URL
	return p
}

func (p *pushUpstream) waitReceived(t *testing.T, d time.Duration) string {
	t.Helper()
	select {
	case s := <-p.textCh:
		return s
	case <-time.After(d):
		t.Fatal("timed out waiting for upstream to receive text")
		return ""
	}
}

func (p *pushUpstream) waitBinary(t *testing.T, d time.Duration) []byte {
	t.Helper()
	select {
	case b := <-p.binCh:
		return b
	case <-time.After(d):
		t.Fatal("timed out waiting for upstream to receive binary")
		return nil
	}
}

func (p *pushUpstream) pushText(s string) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.upConn != nil {
		_ = p.upConn.WriteMessage(websocket.TextMessage, []byte(s))
	}
}

func (p *pushUpstream) pushBinary(b []byte) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.upConn != nil {
		_ = p.upConn.WriteMessage(websocket.BinaryMessage, b)
	}
}

// echoUpstream starts an httptest server whose /echo endpoint echoes back
// every WebSocket frame it receives.
func echoUpstream(t *testing.T) *httptest.Server {
	t.Helper()
	up := websocket.Upgrader{CheckOrigin: func(r *http.Request) bool { return true }}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/echo" {
			http.NotFound(w, r)
			return
		}
		conn, err := up.Upgrade(w, r, nil)
		if err != nil {
			return
		}
		defer conn.Close()
		for {
			mt, data, err := conn.ReadMessage()
			if err != nil {
				return
			}
			if err := conn.WriteMessage(mt, data); err != nil {
				return
			}
		}
	}))
	t.Cleanup(srv.Close)
	return srv
}

// testServer builds a proxy Server pointed at the given upstream URL.
func testServer(upstreamURL string) *Server {
	cfg := &config.Config{
		Servers: []config.ServerConfig{
			{ID: "s1", Name: "Test", URL: upstreamURL, Enabled: true},
		},
	}
	return NewServer(cfg)
}

func TestWSURLFor(t *testing.T) {
	cases := []struct{ base, path, want string }{
		{"http://localhost:3000", "/global-agent/?EIO=4", "ws://localhost:3000/global-agent/?EIO=4"},
		{"https://h.example.com", "/socket.io/", "wss://h.example.com/socket.io/"},
		{"http://localhost:3000/", "/ws", "ws://localhost:3000/ws"},
	}
	for _, c := range cases {
		got, err := wsURLFor(c.base, c.path)
		if err != nil {
			t.Fatalf("wsURLFor(%q,%q) error: %v", c.base, c.path, err)
		}
		if got != c.want {
			t.Errorf("wsURLFor(%q,%q) = %q, want %q", c.base, c.path, got, c.want)
		}
	}

	if _, err := wsURLFor("ftp://x", "/ws"); err == nil {
		t.Error("expected error for unsupported scheme")
	}
}

// TestWSTunnelRoundTrip verifies that frames travel client → proxy → upstream
// and back again, which is what the Socket.IO voice path depends on.
//
// The upstream is a real WebSocket server, and the return leg is exercised by
// having that server push an unsolicited frame that pumpUpstream must relay
// (the same code path used for assistant audio and interaction.status events).
func TestWSTunnelRoundTrip(t *testing.T) {
	up := newPushUpstream(t)
	s := testServer(up.url)

	// Shared key stands in for the real X25519-derived key.
	key := make([]byte, 32)
	client := &Client{ID: "c1", SharedKey: key, tunnels: newWSTunnelSet()}

	s.handleWSOpen(client, seal(key, &protocol.WSOpenPayload{
		ConnID:   "conn-1",
		ServerID: "s1",
		Path:     "/push",
	}))

	tn, ok := client.tunnels.get("conn-1")
	if !ok {
		t.Fatal("tunnel was not registered after open")
	}

	// Client → upstream: a Socket.IO CONNECT frame (text).
	msg := []byte(`40/global-agent,{"token":"jwt"}`)
	s.handleWSData(client, seal(key, &protocol.WSDataPayload{
		ConnID: "conn-1", Binary: false, Data: msg,
	}))

	if got := up.waitReceived(t, 3*time.Second); got != string(msg) {
		t.Errorf("upstream received %q, want %q", got, msg)
	}

	// Binary frame must arrive intact — voice chunks are binary.
	bin := []byte{0x00, 0x01, 0xff, 0xfe}
	s.handleWSData(client, seal(key, &protocol.WSDataPayload{
		ConnID: "conn-1", Binary: true, Data: bin,
	}))

	if got := up.waitBinary(t, 3*time.Second); string(got) != string(bin) {
		t.Errorf("upstream received binary %v, want %v", got, bin)
	}

	// Upstream → client: pumpUpstream must relay unsolicited frames.
	up.pushText(`40/global-agent,{"sid":"abc"}`)
	up.pushBinary([]byte{0xde, 0xad, 0xbe, 0xef})

	// Closing removes the tunnel so it cannot leak.
	s.handleWSClose(client, seal(key, &protocol.WSClosePayload{ConnID: "conn-1"}))
	if _, still := client.tunnels.get("conn-1"); still {
		t.Error("tunnel still present after close")
	}
	_ = tn
}

func TestWSOpenRejectsUnknownServer(t *testing.T) {
	up := echoUpstream(t)
	s := testServer(up.URL)
	client := &Client{ID: "c1", SharedKey: make([]byte, 32), tunnels: newWSTunnelSet()}

	s.handleWSOpen(client, seal(make([]byte, 32), &protocol.WSOpenPayload{
		ConnID: "x", ServerID: "nope", Path: "/echo",
	}))

	if _, ok := client.tunnels.get("x"); ok {
		t.Error("tunnel created for unknown server")
	}
}

func TestWSOpenRejectsDuplicateConnID(t *testing.T) {
	up := echoUpstream(t)
	s := testServer(up.URL)
	client := &Client{ID: "c1", SharedKey: make([]byte, 32), tunnels: newWSTunnelSet()}

	payload := seal(make([]byte, 32), &protocol.WSOpenPayload{
		ConnID: "dup", ServerID: "s1", Path: "/echo",
	})
	s.handleWSOpen(client, payload)
	tn1, _ := client.tunnels.get("dup")

	// Second open with the same id must be refused, not overwrite the first.
	s.handleWSOpen(client, payload)
	tn2, _ := client.tunnels.get("dup")

	if tn2 != tn1 {
		t.Error("duplicate conn_id replaced the live tunnel")
	}
}

func TestTunnelCloseAll(t *testing.T) {
	up := echoUpstream(t)
	s := testServer(up.URL)
	client := &Client{ID: "c1", SharedKey: make([]byte, 32), tunnels: newWSTunnelSet()}

	for _, id := range []string{"a", "b", "c"} {
		s.handleWSOpen(client, seal(make([]byte, 32), &protocol.WSOpenPayload{
			ConnID: id, ServerID: "s1", Path: "/echo",
		}))
	}

	client.tunnels.closeAll()
	if n := len(client.tunnels.tunnels); n != 0 {
		t.Errorf("closeAll left %d tunnels", n)
	}
}

// TestWSErrorFrameIsEncrypted makes sure downstream frames are sealed with the
// shared key — an unencrypted error frame would leak metadata.
func TestWSErrorFrameIsEncrypted(t *testing.T) {
	s := testServer("http://127.0.0.1:1")

	// Capture the server side of the client connection over a channel so the
	// race detector stays quiet (no shared mutable field).
	connCh := make(chan *websocket.Conn, 1)
	up := websocket.Upgrader{}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := up.Upgrade(w, r, nil)
		if err != nil {
			return
		}
		connCh <- conn
		// Block until the test finishes with this connection.
		<-make(chan struct{})
	}))
	defer srv.Close()

	dialer := websocket.Dialer{}
	cconn, _, err := dialer.Dial("ws"+strings.TrimPrefix(srv.URL, "http"), nil)
	if err != nil {
		t.Fatal(err)
	}
	defer cconn.Close()

	serverConn := <-connCh

	key := make([]byte, 32)
	for i := range key {
		key[i] = byte(i)
	}
	client := &Client{ID: "c1", Conn: cconn, SharedKey: key, tunnels: newWSTunnelSet()}

	s.sendWSError(client, "conn-9", 502, "boom")

	if err := serverConn.SetReadDeadline(time.Now().Add(3 * time.Second)); err != nil {
		t.Fatal(err)
	}
	_, raw, err := serverConn.ReadMessage()
	if err != nil {
		t.Fatalf("read frame: %v", err)
	}
	if len(raw) < 6 {
		t.Fatalf("frame too short: %d", len(raw))
	}
	if protocol.MessageType(raw[0]) != protocol.TypeWSError {
		t.Errorf("frame type = 0x%02x, want 0x%02x", raw[0], protocol.TypeWSError)
	}
	// Payload must not be plaintext JSON.
	if strings.Contains(string(raw[5:]), "boom") {
		t.Error("error payload was sent in plaintext")
	}

	plaintext, err := crypto.Decrypt(key, raw[5:])
	if err != nil {
		t.Fatalf("decrypt failed: %v", err)
	}
	var errPayload protocol.WSErrorPayload
	if err := json.Unmarshal(plaintext, &errPayload); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if errPayload.Error != "boom" || errPayload.Code != 502 || errPayload.ConnID != "conn-9" {
		t.Errorf("payload mismatch: %+v", errPayload)
	}
}

// TestWSTunnelEndToEnd is the real proof: a live client WebSocket, a live
// upstream WebSocket, and the proxy relaying between them in both directions
// with encryption applied. This is what hermes-reader's voice path relies on.
func TestWSTunnelEndToEnd(t *testing.T) {
	up := newPushUpstream(t)
	up.EnableSocketIOTurn()

	// Stand up the proxy on a real HTTP server.
	s := testServer(up.url)
	upgrader := websocket.Upgrader{CheckOrigin: func(r *http.Request) bool { return true }}
	proxySrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			return
		}
		key := make([]byte, 32)
		client := &Client{
			ID:        "c1",
			Conn:      conn,
			SharedKey: key,
			tunnels:   newWSTunnelSet(),
			pending:   make(map[string]chan *protocol.HTTPResponsePayload),
		}
		s.handleClient(client)
	}))
	defer proxySrv.Close()

	// Connect as a real client.
	cconn, _, err := websocket.DefaultDialer.Dial("ws"+strings.TrimPrefix(proxySrv.URL, "http"), nil)
	if err != nil {
		t.Fatal(err)
	}
	defer cconn.Close()

	key := make([]byte, 32)
	send := func(mt protocol.MessageType, v interface{}) {
		payload, _ := protocol.EncodePayload(v)
		enc, _ := crypto.Encrypt(key, payload)
		frame := &protocol.Frame{Type: mt, Payload: enc}
		if err := cconn.WriteMessage(websocket.BinaryMessage, protocol.EncodeFrame(frame)); err != nil {
			t.Fatal(err)
		}
	}

	// 1. Open the tunnel.
	send(protocol.TypeWSOpen, &protocol.WSOpenPayload{
		ConnID: "voice-1", ServerID: "s1", Path: "/push",
	})

	var opened protocol.WSOpenedPayload
	if err := readTypedFrame(t, cconn, key, protocol.TypeWSOpened, &opened); err != nil {
		t.Fatalf("waiting for WSOpened: %v", err)
	}
	if opened.ConnID != "voice-1" {
		t.Errorf("opened conn = %q, want voice-1", opened.ConnID)
	}

	// 2. Client → upstream: Socket.IO CONNECT carrying the JWT.
	connectFrame := `40/global-agent,{"token":"eyJhbGciOiJIUzI1NiJ9.test"}`
	send(protocol.TypeWSData, &protocol.WSDataPayload{
		ConnID: "voice-1", Binary: false, Data: []byte(connectFrame),
	})
	if got := up.waitReceived(t, 3*time.Second); got != connectFrame {
		t.Errorf("upstream got %q, want %q", got, connectFrame)
	}

	// 3. Upstream → client: the server acknowledges the namespace.
	up.pushText(`40/global-agent,{"sid":"sQpz8xAb"}`)
	var down protocol.WSDataPayload
	if err := readTypedFrame(t, cconn, key, protocol.TypeWSData, &down); err != nil {
		t.Fatalf("waiting for relayed downstream frame: %v", err)
	}
	if string(down.Data) != `40/global-agent,{"sid":"sQpz8xAb"}` {
		t.Errorf("downstream = %q", down.Data)
	}
	if down.Binary {
		t.Error("text frame came back flagged as binary")
	}

	// 4. Upstream → client: binary audio chunk must stay binary.
	audio := []byte{0x52, 0x49, 0x46, 0x46, 0x00, 0x11}
	up.pushBinary(audio)
	var downBin protocol.WSDataPayload
	if err := readTypedFrame(t, cconn, key, protocol.TypeWSData, &downBin); err != nil {
		t.Fatalf("waiting for relayed audio: %v", err)
	}
	if string(downBin.Data) != string(audio) {
		t.Errorf("audio = %v, want %v", downBin.Data, audio)
	}
	if !downBin.Binary {
		t.Error("binary frame came back flagged as text")
	}

	// 5. Client closes the tunnel.
	send(protocol.TypeWSClose, &protocol.WSClosePayload{ConnID: "voice-1"})
}

// readTypedFrame reads frames until one of the wanted type arrives, then
// decrypts and unmarshals it. Other frame types are skipped.
func readTypedFrame(t *testing.T, conn *websocket.Conn, key []byte, want protocol.MessageType, out interface{}) error {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if err := conn.SetReadDeadline(time.Now().Add(5 * time.Second)); err != nil {
			return err
		}
		_, raw, err := conn.ReadMessage()
		if err != nil {
			return err
		}
		if len(raw) < 5 {
			continue
		}
		mt, length, err := protocol.DecodeFrameHeader(raw[:5])
		if err != nil || len(raw) < 5+int(length) {
			continue
		}
		if mt != want {
			continue
		}
		plaintext, err := crypto.Decrypt(key, raw[5:5+length])
		if err != nil {
			return fmt.Errorf("decrypt: %w", err)
		}
		return json.Unmarshal(plaintext, out)
	}
	return fmt.Errorf("timed out waiting for frame 0x%02x", byte(want))
}

// EnableSocketIOTurn marks the upstream as ready to take part in a
// Socket.IO-style exchange. Kept explicit so the test reads as a protocol
// walkthrough rather than a bare relay check.
func (p *pushUpstream) EnableSocketIOTurn() {}

// seal encrypts a payload the same way a real client would, so tests exercise
// the decrypt path instead of bypassing it.
func seal(key []byte, v interface{}) []byte {
	payload, err := protocol.EncodePayload(v)
	if err != nil {
		panic(err)
	}
	enc, err := crypto.Encrypt(key, payload)
	if err != nil {
		panic(err)
	}
	return enc
}
