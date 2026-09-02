// Package proxy implements the WebSocket server and HTTP proxy forwarding.
package proxy

import (
	"bytes"
	"context"
	"crypto/tls"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"hermes-proxy/internal/auth"
	"hermes-proxy/internal/config"
	"hermes-proxy/internal/crypto"
	"hermes-proxy/internal/protocol"
)

// Server is the WebSocket proxy server.
type Server struct {
	cfg       *config.Config
	validator *auth.Validator
	upgrader  websocket.Upgrader
	clients   map[string]*Client // clientID -> client
	mu        sync.RWMutex
	transport *http.Transport
}

// Client represents a connected hermes-hive client.
type Client struct {
	ID             string
	Conn           *websocket.Conn
	SharedKey      []byte
	ServerID       string // currently active server
	mu             sync.Mutex
	pending        map[string]chan *protocol.HTTPResponsePayload
	pendingCounter uint64
}

// NewServer creates a new proxy server.
func NewServer(cfg *config.Config) *Server {
	return &Server{
		cfg:       cfg,
		validator: auth.NewValidator(&cfg.Auth),
		upgrader: websocket.Upgrader{
			CheckOrigin: func(r *http.Request) bool {
				return true // Allow all origins (configurable)
			},
			ReadBufferSize:  64 * 1024,
			WriteBufferSize: 64 * 1024,
		},
		clients: make(map[string]*Client),
		transport: &http.Transport{
			MaxIdleConns:        100,
			MaxIdleConnsPerHost: 10,
			IdleConnTimeout:     90 * time.Second,
			TLSClientConfig:     &tls.Config{InsecureSkipVerify: true},
		},
	}
}

// Run starts the HTTP server and WebSocket endpoint.
func (s *Server) Run() error {
	mux := http.NewServeMux()
	mux.HandleFunc(s.cfg.WSPath, s.handleWebSocket)
	mux.HandleFunc("/health", s.handleHealth)

	log.Printf("[proxy] Listening on %s, WS path: %s", s.cfg.Listen, s.cfg.WSPath)
	log.Printf("[proxy] Auth method: %s", s.cfg.Auth.Method)
	return http.ListenAndServe(s.cfg.Listen, mux)
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"status":"ok"}`))
}

func (s *Server) handleWebSocket(w http.ResponseWriter, r *http.Request) {
	// Authentication is required - extract and validate token
	token := auth.ExtractToken(r)
	if token == "" {
		http.Error(w, `{"error":"authentication required"}`, http.StatusUnauthorized)
		return
	}

	valid, err := s.validator.Validate(token)
	if !valid {
		log.Printf("[proxy] Auth failed from %s: %v", r.RemoteAddr, err)
		http.Error(w, fmt.Sprintf(`{"error":"authentication failed: %s"}`, err.Error()), http.StatusForbidden)
		return
	}

	conn, err := s.upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("[proxy] WebSocket upgrade failed: %v", err)
		return
	}

	client, err := s.performHandshake(conn)
	if err != nil {
		log.Printf("[proxy] Handshake failed: %v", err)
		conn.Close()
		return
	}

	s.mu.Lock()
	s.clients[client.ID] = client
	s.mu.Unlock()

	log.Printf("[proxy] Client connected: %s from %s", client.ID, conn.RemoteAddr())

	// Start handling incoming frames
	s.handleClient(client)
}

// performHandshake does the X25519 key exchange with the client.
func (s *Server) performHandshake(conn *websocket.Conn) (*Client, error) {
	// Set read deadline for handshake
	conn.SetReadDeadline(time.Now().Add(10 * time.Second))

	// Read client's handshake message
	_, msgData, err := conn.ReadMessage()
	if err != nil {
		return nil, fmt.Errorf("read handshake: %w", err)
	}

	clientHandshake, err := crypto.DecodeHandshake(msgData)
	if err != nil {
		return nil, fmt.Errorf("decode handshake: %w", err)
	}

	// Generate our key pair
	keyPair, err := crypto.GenerateKeyPair()
	if err != nil {
		return nil, fmt.Errorf("generate keypair: %w", err)
	}

	// Parse client public key and compute shared secret
	clientPub, err := crypto.PublicKeyFromBase64(clientHandshake.PublicKey)
	if err != nil {
		return nil, fmt.Errorf("invalid client public key: %w", err)
	}
	sharedKey, err := keyPair.SharedSecret(clientPub)
	if err != nil {
		return nil, fmt.Errorf("compute shared secret: %w", err)
	}

	// Send our handshake response
	serverHandshake := &crypto.HandshakeMessage{
		PublicKey: keyPair.PublicKeyBase64(),
	}
	respData, err := crypto.EncodeHandshake(serverHandshake)
	if err != nil {
		return nil, fmt.Errorf("encode handshake: %w", err)
	}
	if err := conn.WriteMessage(websocket.TextMessage, respData); err != nil {
		return nil, fmt.Errorf("write handshake: %w", err)
	}

	// Clear deadline
	conn.SetReadDeadline(time.Time{})

	// Generate client ID from public key
	clientID := fmt.Sprintf("hive-%s", clientHandshake.PublicKey[:8])

	return &Client{
		ID:        clientID,
		Conn:      conn,
		SharedKey: sharedKey,
		pending:   make(map[string]chan *protocol.HTTPResponsePayload),
	}, nil
}

// handleClient reads and processes WebSocket frames from a client.
func (s *Server) handleClient(client *Client) {
	defer func() {
		s.mu.Lock()
		delete(s.clients, client.ID)
		s.mu.Unlock()
		client.Conn.Close()
		log.Printf("[proxy] Client disconnected: %s", client.ID)
	}()

	for {
		_, frameData, err := client.Conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseNormalClosure) {
				log.Printf("[proxy] Client %s read error: %v", client.ID, err)
			}
			return
		}

		if len(frameData) < 5 {
			continue
		}

		msgType, length, err := protocol.DecodeFrameHeader(frameData[:5])
		if err != nil {
			log.Printf("[proxy] Frame header error: %v", err)
			continue
		}

		if len(frameData) < 5+int(length) {
			log.Printf("[proxy] Frame truncated")
			continue
		}

		payload := frameData[5 : 5+length]

		switch msgType {
		case protocol.TypeHTTPRequest:
			s.handleHTTPRequest(client, payload)
		default:
			log.Printf("[proxy] Unknown message type: 0x%02x", msgType)
		}
	}
}

// handleHTTPRequest decrypts, forwards, encrypts, and sends back the response.
func (s *Server) handleHTTPRequest(client *Client, encryptedPayload []byte) {
	// Decrypt
	plaintext, err := crypto.Decrypt(client.SharedKey, encryptedPayload)
	if err != nil {
		log.Printf("[proxy] Decrypt error: %v", err)
		s.sendError(client, 400, "decryption failed")
		return
	}

	// Decode request
	var req protocol.HTTPRequestPayload
	if err := protocol.DecodePayload(plaintext, &req); err != nil {
		log.Printf("[proxy] Decode payload error: %v", err)
		s.sendError(client, 400, "invalid payload")
		return
	}

	// Find target server
	serverCfg := s.cfg.GetServer(req.ServerID)
	if serverCfg == nil {
		s.sendError(client, 404, fmt.Sprintf("server '%s' not found", req.ServerID))
		return
	}
	if !serverCfg.Enabled {
		s.sendError(client, 503, fmt.Sprintf("server '%s' disabled", req.ServerID))
		return
	}

	// Forward the request
	resp, err := s.forwardRequest(serverCfg, &req)
	if err != nil {
		log.Printf("[proxy] Forward error to %s: %v", serverCfg.URL, err)
		s.sendError(client, 502, fmt.Sprintf("upstream error: %v", err))
		return
	}

	// Send encrypted response
	s.sendHTTPResponse(client, resp)
}

// forwardRequest forwards the HTTP request to the target Hermes Studio server.
func (s *Server) forwardRequest(serverCfg *config.ServerConfig, req *protocol.HTTPRequestPayload) (*protocol.HTTPResponsePayload, error) {
	target, err := url.Parse(serverCfg.URL)
	if err != nil {
		return nil, fmt.Errorf("invalid server URL: %w", err)
	}

	// Build the request URL
	reqURL := target.ResolveReference(&url.URL{Path: req.Path})

	// Create HTTP request
	var bodyReader io.Reader
	if req.Body != nil {
		bodyReader = bytes.NewReader(req.Body)
	}
	httpReq, err := http.NewRequest(req.Method, reqURL.String(), bodyReader)
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}

	// Set headers
	for k, v := range req.Headers {
		httpReq.Header.Set(k, v)
	}

	// Execute
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()
	httpReq = httpReq.WithContext(ctx)

	httpResp, err := s.transport.RoundTrip(httpReq)
	if err != nil {
		return nil, fmt.Errorf("round trip: %w", err)
	}
	defer httpResp.Body.Close()

	// Read body
	respBody, err := io.ReadAll(httpResp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response body: %w", err)
	}

	// Build response headers
	respHeaders := make(map[string]string)
	for k, v := range httpResp.Header {
		if len(v) > 0 {
			respHeaders[k] = v[0]
		}
	}

	return &protocol.HTTPResponsePayload{
		StatusCode: httpResp.StatusCode,
		Headers:    respHeaders,
		Body:       respBody,
	}, nil
}

// sendHTTPResponse encrypts and sends an HTTP response.
func (s *Server) sendHTTPResponse(client *Client, resp *protocol.HTTPResponsePayload) {
	// Encode response
	respData, err := protocol.EncodePayload(resp)
	if err != nil {
		log.Printf("[proxy] Encode response error: %v", err)
		return
	}

	// Encrypt
	encrypted, err := crypto.Encrypt(client.SharedKey, respData)
	if err != nil {
		log.Printf("[proxy] Encrypt error: %v", err)
		return
	}

	// Build frame
	frame := &protocol.Frame{
		Type:    protocol.TypeHTTPResponse,
		Payload: encrypted,
	}

	client.mu.Lock()
	defer client.mu.Unlock()
	if err := client.Conn.WriteMessage(websocket.BinaryMessage, protocol.EncodeFrame(frame)); err != nil {
		log.Printf("[proxy] Write error: %v", err)
	}
}

// sendError sends an encrypted error response.
func (s *Server) sendError(client *Client, code int, msg string) {
	resp := &protocol.HTTPResponsePayload{
		StatusCode: code,
		Headers:    map[string]string{"Content-Type": "application/json"},
		Body:       []byte(fmt.Sprintf(`{"error":%q}`, msg)),
	}
	s.sendHTTPResponse(client, resp)
}

// Broadcast sends a message to all connected clients (for future use).
func (s *Server) Broadcast(msgType protocol.MessageType, payload []byte) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	frame := protocol.EncodeFrame(&protocol.Frame{Type: msgType, Payload: payload})
	for _, client := range s.clients {
		client.mu.Lock()
		client.Conn.WriteMessage(websocket.BinaryMessage, frame)
		client.mu.Unlock()
	}
}

// ClientCount returns the number of connected clients.
func (s *Server) ClientCount() int {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return len(s.clients)
}
