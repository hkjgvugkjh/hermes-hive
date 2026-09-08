// Package proxy — WebSocket tunneling.
//
// hermes-reader needs to speak the 小方盒 (Socket.IO) protocol with upstream
// Hermes Web UI servers. That protocol is a long-lived WebSocket, which the
// plain HTTP forwarding path cannot carry. This file implements an opaque
// WebSocket relay: the client opens a tunnel identified by a ConnID, and the
// proxy pumps frames in both directions without inspecting them.
package proxy

import (
	"context"
	"crypto/tls"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"hermes-proxy/internal/crypto"
	"hermes-proxy/internal/protocol"
)

// tunnelDialTimeout bounds how long we wait for the upstream handshake.
const tunnelDialTimeout = 15 * time.Second

// wsTunnel is one relayed upstream WebSocket connection.
type wsTunnel struct {
	connID  string
	upstream *websocket.Conn
	client  *Client
	cancel  context.CancelFunc
	once    sync.Once
}

// close tears the tunnel down exactly once.
func (t *wsTunnel) close(reason string) {
	t.once.Do(func() {
		t.client.removeTunnel(t.connID)
		t.cancel()
		t.upstream.Close()
		log.Printf("[proxy] WS tunnel %s closed: %s", t.connID, reason)
	})
}

// wsTunnelSet holds the tunnels belonging to a single client.
type wsTunnelSet struct {
	mu      sync.Mutex
	tunnels map[string]*wsTunnel
}

func newWSTunnelSet() *wsTunnelSet {
	return &wsTunnelSet{tunnels: make(map[string]*wsTunnel)}
}

// add registers a tunnel. Returns false when the ConnID is already in use.
func (s *wsTunnelSet) add(t *wsTunnel) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, exists := s.tunnels[t.connID]; exists {
		return false
	}
	s.tunnels[t.connID] = t
	return true
}

// remove deletes a tunnel by id.
func (s *wsTunnelSet) remove(connID string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.tunnels, connID)
}

// get looks up a tunnel by id.
func (s *wsTunnelSet) get(connID string) (*wsTunnel, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	t, ok := s.tunnels[connID]
	return t, ok
}

// closeAll tears down every tunnel, used when the client disconnects.
func (s *wsTunnelSet) closeAll() {
	s.mu.Lock()
	ids := make([]string, 0, len(s.tunnels))
	for id := range s.tunnels {
		ids = append(ids, id)
	}
	s.mu.Unlock()

	for _, id := range ids {
		if t, ok := s.get(id); ok {
			t.close("client disconnected")
		}
	}
}

// decryptFrame decrypts an inbound frame payload. All three WS entry points
// receive still-encrypted bytes from handleClient, matching the convention the
// HTTP handler already follows (it decrypts internally too).
func (s *Server) decryptFrame(client *Client, encrypted []byte) ([]byte, bool) {
	plaintext, err := crypto.Decrypt(client.SharedKey, encrypted)
	if err != nil {
		log.Printf("[proxy] WS decrypt error: %v", err)
		return nil, false
	}
	return plaintext, true
}

// handleWSOpen opens an upstream WebSocket on behalf of the client.
func (s *Server) handleWSOpen(client *Client, encrypted []byte) {
	plaintext, ok := s.decryptFrame(client, encrypted)
	if !ok {
		return
	}

	var req protocol.WSOpenPayload
	if err := protocol.DecodePayload(plaintext, &req); err != nil {
		log.Printf("[proxy] WS open decode error: %v", err)
		s.sendWSError(client, req.ConnID, 400, "invalid payload")
		return
	}
	if req.ConnID == "" {
		s.sendWSError(client, req.ConnID, 400, "missing conn_id")
		return
	}

	serverCfg := s.cfg.GetServer(req.ServerID)
	if serverCfg == nil {
		s.sendWSError(client, req.ConnID, 404, fmt.Sprintf("server '%s' not found", req.ServerID))
		return
	}
	if !serverCfg.Enabled {
		s.sendWSError(client, req.ConnID, 503, fmt.Sprintf("server '%s' disabled", req.ServerID))
		return
	}

	targetURL, err := wsURLFor(serverCfg.URL, req.Path)
	if err != nil {
		s.sendWSError(client, req.ConnID, 400, err.Error())
		return
	}

	dialer := &websocket.Dialer{
		HandshakeTimeout: tunnelDialTimeout,
		ReadBufferSize:   64 * 1024,
		WriteBufferSize:  64 * 1024,
	}
	if s.transport != nil && s.transport.TLSClientConfig != nil {
		dialer.TLSClientConfig = &tls.Config{
			InsecureSkipVerify: s.transport.TLSClientConfig.InsecureSkipVerify,
		}
	}

	hdr := http.Header{}
	for k, v := range req.Headers {
		hdr.Set(k, v)
	}

	//nolint:bodyclose // gorilla manages the underlying connection
	upstream, resp, err := dialer.Dial(targetURL, hdr)
	if err != nil {
		status := 0
		if resp != nil {
			status = resp.StatusCode
		}
		log.Printf("[proxy] WS dial %s failed (status=%d): %v", targetURL, status, err)
		s.sendWSError(client, req.ConnID, 502, fmt.Sprintf("upstream dial failed: %v", err))
		return
	}

	ctx, cancel := context.WithCancel(context.Background())
	t := &wsTunnel{
		connID:   req.ConnID,
		upstream: upstream,
		client:   client,
		cancel:   cancel,
	}

	// Reject duplicate ConnIDs so a stray client cannot hijack a live tunnel.
	if !client.tunnels.add(t) {
		cancel()
		upstream.Close()
		s.sendWSError(client, req.ConnID, 409, "conn_id already in use")
		return
	}

	// Announce success, then start pumping.
	s.sendWSOpened(client, req.ConnID)
	go s.pumpUpstream(ctx, t)
	log.Printf("[proxy] WS tunnel %s opened -> %s", req.ConnID, targetURL)
}

// pumpUpstream forwards upstream frames down to the proxy client until the
// upstream closes or the context is cancelled.
func (s *Server) pumpUpstream(ctx context.Context, t *wsTunnel) {
	defer t.close("upstream closed")

	for {
		select {
		case <-ctx.Done():
			return
		default:
		}

		msgType, data, err := t.upstream.ReadMessage()
		if err != nil {
			if ctx.Err() == nil {
				// Tell the client the upstream went away so it can reconnect.
				s.sendWSClose(t.client, t.connID, err.Error())
			}
			return
		}

		payload, err := protocol.EncodePayload(&protocol.WSDataPayload{
			ConnID: t.connID,
			Binary: msgType == websocket.BinaryMessage,
			Data:   data,
		})
		if err != nil {
			log.Printf("[proxy] WS encode error on %s: %v", t.connID, err)
			return
		}
		s.sendWSFrame(t.client, protocol.TypeWSData, payload)
	}
}

// handleWSData relays a client-originated frame up to the target server.
func (s *Server) handleWSData(client *Client, encrypted []byte) {
	plaintext, ok := s.decryptFrame(client, encrypted)
	if !ok {
		return
	}

	var req protocol.WSDataPayload
	if err := protocol.DecodePayload(plaintext, &req); err != nil {
		log.Printf("[proxy] WS data decode error: %v", err)
		return
	}

	t, ok := client.tunnels.get(req.ConnID)
	if !ok {
		log.Printf("[proxy] WS data for unknown conn %s", req.ConnID)
		s.sendWSError(client, req.ConnID, 404, "unknown conn_id")
		return
	}

	msgType := websocket.TextMessage
	if req.Binary {
		msgType = websocket.BinaryMessage
	}

	// Serialize writes per tunnel — concurrent WriteMessage on one
	// gorilla Conn is a data race and would corrupt the stream.
	t.client.mu.Lock()
	err := t.upstream.WriteMessage(msgType, req.Data)
	t.client.mu.Unlock()

	if err != nil {
		log.Printf("[proxy] WS write error on %s: %v", t.connID, err)
		t.close("write failed")
		s.sendWSError(client, req.ConnID, 502, err.Error())
	}
}

// handleWSClose closes a tunnel at the client's request.
func (s *Server) handleWSClose(client *Client, encrypted []byte) {
	plaintext, ok := s.decryptFrame(client, encrypted)
	if !ok {
		return
	}

	var req protocol.WSClosePayload
	if err := protocol.DecodePayload(plaintext, &req); err != nil {
		return
	}
	if t, ok := client.tunnels.get(req.ConnID); ok {
		t.close("client requested")
	}
}

// wsURLFor converts an http(s) base URL plus a path into a ws(s) URL.
func wsURLFor(baseURL, path string) (string, error) {
	u, err := url.Parse(baseURL)
	if err != nil {
		return "", fmt.Errorf("invalid server URL: %w", err)
	}
	switch u.Scheme {
	case "http":
		u.Scheme = "ws"
	case "https":
		u.Scheme = "wss"
	default:
		return "", fmt.Errorf("unsupported server scheme %q", u.Scheme)
	}

	ref, err := url.Parse(path)
	if err != nil {
		return "", fmt.Errorf("invalid path: %w", err)
	}
	return u.ResolveReference(ref).String(), nil
}

// removeTunnel deletes a tunnel from the client's set.
func (c *Client) removeTunnel(connID string) {
	if c.tunnels != nil {
		c.tunnels.remove(connID)
	}
}

// ---------------------------------------------------------------------------
// Downstream frames (proxy → client)
// ---------------------------------------------------------------------------

// sendWSFrame encrypts a payload and writes it to the client connection.
// Safe to call when the client connection is closed or absent — the frame is
// dropped instead of panicking.
func (s *Server) sendWSFrame(client *Client, msgType protocol.MessageType, payload []byte) {
	if client == nil || client.Conn == nil {
		return
	}

	encrypted, err := crypto.Encrypt(client.SharedKey, payload)
	if err != nil {
		log.Printf("[proxy] WS encrypt error: %v", err)
		return
	}

	frame := &protocol.Frame{Type: msgType, Payload: encrypted}

	client.mu.Lock()
	defer client.mu.Unlock()
	if err := client.Conn.WriteMessage(websocket.BinaryMessage, protocol.EncodeFrame(frame)); err != nil {
		log.Printf("[proxy] WS write to client error: %v", err)
	}
}


// sendWSOpened tells the client that the upstream WebSocket is connected.
func (s *Server) sendWSOpened(client *Client, connID string) {
	payload, err := protocol.EncodePayload(&protocol.WSOpenedPayload{ConnID: connID})
	if err != nil {
		return
	}
	s.sendWSFrame(client, protocol.TypeWSOpened, payload)
}

// sendWSClose notifies the client that a tunnel went away.
func (s *Server) sendWSClose(client *Client, connID, reason string) {
	payload, err := protocol.EncodePayload(&protocol.WSClosePayload{ConnID: connID, Reason: reason})
	if err != nil {
		return
	}
	s.sendWSFrame(client, protocol.TypeWSClose, payload)
}

// sendWSError reports a tunnel error to the client.
func (s *Server) sendWSError(client *Client, connID string, code int, msg string) {
	payload, err := protocol.EncodePayload(&protocol.WSErrorPayload{
		ConnID: connID,
		Code:   code,
		Error:  msg,
	})
	if err != nil {
		return
	}
	s.sendWSFrame(client, protocol.TypeWSError, payload)
}
