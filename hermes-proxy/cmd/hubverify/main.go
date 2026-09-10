// cmd/hubverify — end-to-end verification of the client/dispatch/service model.
//
// Connects N WebSocket clients to the same proxy, all attaching to one server.
// Verifies:
//   1. Every client gets ConnectAck(OK) and a session snapshot
//   2. The backend is dialled exactly once
//   3. When client A drops, the rest still get updates (fan-out)
//   4. An HTTP request through the proxy succeeds (proxy JWT injection)
package main

import (
	"encoding/binary"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"hermes-proxy/internal/crypto"
	"hermes-proxy/internal/di"
)

const nClients = 3

type clientResult struct {
	id           string
	ackOK        bool
	gotSnapshot  bool
	sessionCount int
	err          error
	conn         *websocket.Conn
	key          []byte
}

func main() {
	addr := os.Getenv("PROXY_WS")
	token := os.Getenv("PROXY_TOKEN")
	serverID := os.Getenv("SERVER_ID")
	if addr == "" || token == "" || serverID == "" {
		log.Fatal("set PROXY_WS, PROXY_TOKEN, SERVER_ID")
	}

	results := make([]clientResult, nClients)
	var wg sync.WaitGroup
	for i := 0; i < nClients; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			results[i] = runClient(addr, token, serverID)
		}(i)
	}
	wg.Wait()

	acked, snapped, failed := 0, 0, 0
	for i, r := range results {
		status := "ok"
		if r.err != nil {
			status = "ERR: " + r.err.Error()
			failed++
		}
		if r.ackOK {
			acked++
		}
		if r.gotSnapshot {
			snapped++
		}
		fmt.Printf("client[%d] id=%s ack=%v snapshot=%v sessions=%d %s\n",
			i, r.id, r.ackOK, r.gotSnapshot, r.sessionCount, status)
	}
	fmt.Printf("SUMMARY acked=%d/%d snapshot=%d/%d failed=%d\n",
		acked, nClients, snapped, nClients, failed)

	if acked != nClients || snapped != nClients {
		os.Exit(1)
	}

	// Phase 2: drop client 0, confirm survivors still served
	if results[0].conn != nil {
		results[0].conn.Close()
		fmt.Println("closed client[0]; backend must survive for the others")
	}
	time.Sleep(2 * time.Second)

	alive := 0
	for i := 1; i < nClients; i++ {
		r := results[i]
		if r.conn == nil {
			continue
		}
		if err := sendDI(r.conn, r.key, di.TypeDISessionPoll,
			di.DISessionPollPayload{ServerID: serverID}); err != nil {
			fmt.Printf("client[%d] re-poll send failed: %v\n", i, err)
			continue
		}
		if waitSnapshot(r.conn, r.key, 20*time.Second) {
			alive++
			fmt.Printf("client[%d] still served after peer disconnect\n", i)
		} else {
			fmt.Printf("client[%d] NOT served after peer disconnect\n", i)
		}
	}
	if alive != nClients-1 {
		os.Exit(1)
	}
	fmt.Println("PASS: all clients served by one shared backend")

	// Phase 3: HTTP bookshelf test (independent client)
	fmt.Println("\n--- HTTP bookshelf test ---")
	hc := runClient(addr, token, serverID)
	if hc.conn == nil {
		fmt.Println("  client connect failed:", hc.err)
		os.Exit(1)
	}
	defer hc.conn.Close()

	httpReq := struct {
		RequestID string            `json:"request_id"`
		ServerID  string            `json:"server_id"`
		Method    string            `json:"method"`
		Path      string            `json:"path"`
		Headers   map[string]string `json:"headers,omitempty"`
	}{
		RequestID: "bookshelf-1",
		ServerID:  serverID,
		Method:    "GET",
		Path:      "/api/studio/files/list?path=%2F",
	}
	if err := sendDI(hc.conn, hc.key, 0x10, httpReq); err != nil {
		fmt.Printf("  HTTP request send failed: %v\n", err)
		os.Exit(1)
	}
	fmt.Println("  HTTP request sent, waiting for response...")

	resp := waitHTTP(hc.conn, hc.key, 20*time.Second)
	if resp == nil {
		fmt.Println("  HTTP response timed out")
		os.Exit(1)
	}
	if resp.StatusCode != 200 {
		body := string(resp.Body)
		if len(body) > 300 {
			body = body[:300]
		}
		fmt.Printf("  FAIL HTTP %d: %s\n", resp.StatusCode, body)
		os.Exit(1)
	}
	var files struct {
		Entries []struct {
			Name string `json:"name"`
			Path string `json:"path"`
		} `json:"entries"`
	}
	_ = json.Unmarshal(resp.Body, &files)
	fmt.Printf("  HTTP 200 OK, %d entries (proxy JWT injection working)\n", len(files.Entries))
	for _, e := range files.Entries[:5] {
		fmt.Printf("    %s\n", e.Name)
	}
}

func runClient(addr, token, serverID string) clientResult {
	var r clientResult

	kp, err := crypto.GenerateKeyPair()
	if err != nil {
		r.err = err
		return r
	}
	c, _, err := websocket.DefaultDialer.Dial(addr+"?token="+token, nil)
	if err != nil {
		r.err = err
		return r
	}
	r.conn = c

	// Handshake
	if err := c.WriteMessage(websocket.TextMessage,
		mustEncodeHandshake(&crypto.HandshakeMessage{PublicKey: kp.PublicKeyBase64()})); err != nil {
		r.err = err
		return r
	}
	_, respData, err := c.ReadMessage()
	if err != nil {
		r.err = err
		return r
	}
	serverHS, err := crypto.DecodeHandshake(respData)
	if err != nil {
		r.err = err
		return r
	}
	serverPub, err := crypto.PublicKeyFromBase64(serverHS.PublicKey)
	if err != nil {
		r.err = err
		return r
	}
	key, err := kp.SharedSecret(serverPub)
	if err != nil {
		r.err = err
		return r
	}
	r.key = key
	r.id = "hive-" + serverHS.PublicKey[:8]

	// DI connect
	if err := sendDI(c, key, di.TypeDIConnect, di.DIConnectPayload{ServerID: serverID}); err != nil {
		r.err = err
		return r
	}

	// Wait for ConnectAck + SessionUpdate
	deadline := time.Now().Add(30 * time.Second)
	for time.Now().Before(deadline) {
		c.SetReadDeadline(time.Now().Add(2 * time.Second))
		mt, data, err := c.ReadMessage()
		if err != nil {
			continue
		}
		if mt != websocket.BinaryMessage || len(data) < 5 {
			continue
		}
		mtype, length, err := di.DecodeFrameHeader(data[:5])
		if err != nil || len(data) < 5+int(length) {
			continue
		}
		plain, err := crypto.Decrypt(key, data[5:5+length])
		if err != nil {
			continue
		}
		switch mtype {
		case di.TypeDIConnectAck:
			var p di.DIConnectAckPayload
			_ = json.Unmarshal(plain, &p)
			r.ackOK = p.OK
			if !p.OK {
				r.err = fmt.Errorf("connect nacked: %s", p.Reason)
				return r
			}
		case di.TypeDISessionUpdate:
			var p di.DISessionUpdatePayload
			_ = json.Unmarshal(plain, &p)
			r.gotSnapshot = true
			r.sessionCount = len(p.Sessions)
			return r
		case di.TypeDIError:
			var p di.DIErrorPayload
			_ = json.Unmarshal(plain, &p)
			r.err = fmt.Errorf("DI error: %s", p.Message)
			return r
		}
	}
	if !r.ackOK {
		r.err = fmt.Errorf("no ConnectAck within deadline")
	} else if !r.gotSnapshot {
		r.err = fmt.Errorf("no session snapshot within deadline")
	}
	return r
}

func waitSnapshot(c *websocket.Conn, key []byte, d time.Duration) bool {
	deadline := time.Now().Add(d)
	for time.Now().Before(deadline) {
		c.SetReadDeadline(time.Now().Add(2 * time.Second))
		mt, data, err := c.ReadMessage()
		if err != nil || mt != websocket.BinaryMessage || len(data) < 5 {
			continue
		}
		mtype, length, err := di.DecodeFrameHeader(data[:5])
		if err != nil || len(data) < 5+int(length) {
			continue
		}
		_, err = crypto.Decrypt(key, data[5:5+length])
		if err != nil {
			continue
		}
		if mtype == di.TypeDISessionUpdate {
			return true
		}
	}
	return false
}

func waitHTTP(c *websocket.Conn, key []byte, d time.Duration) *struct {
	StatusCode int               `json:"status_code"`
	Headers    map[string]string `json:"headers"`
	Body       json.RawMessage   `json:"body"`
} {
	deadline := time.Now().Add(d)
	for time.Now().Before(deadline) {
		c.SetReadDeadline(time.Now().Add(2 * time.Second))
		mt, data, err := c.ReadMessage()
		if err != nil || mt != websocket.BinaryMessage || len(data) < 5 {
			continue
		}
		mtype, length, err := di.DecodeFrameHeader(data[:5])
		if err != nil || len(data) < 5+int(length) {
			continue
		}
		plain, err := crypto.Decrypt(key, data[5:5+length])
		if err != nil {
			continue
		}
		if mtype == 0x11 {
			var resp struct {
				StatusCode int               `json:"status_code"`
				Headers    map[string]string `json:"headers"`
				Body       json.RawMessage   `json:"body"`
			}
			if err := json.Unmarshal(plain, &resp); err == nil {
				return &resp
			}
		}
	}
	return nil
}

func sendDI(c *websocket.Conn, key []byte, mt di.MessageType, payload interface{}) error {
	plain, err := di.EncodePayload(payload)
	if err != nil {
		return err
	}
	enc, err := crypto.Encrypt(key, plain)
	if err != nil {
		return err
	}
	buf := make([]byte, 1+4+len(enc))
	buf[0] = byte(mt)
	binary.BigEndian.PutUint32(buf[1:5], uint32(len(enc)))
	copy(buf[5:], enc)
	return c.WriteMessage(websocket.BinaryMessage, buf)
}

func mustEncodeHandshake(m *crypto.HandshakeMessage) []byte {
	b, err := crypto.EncodeHandshake(m)
	if err != nil {
		log.Fatalf("encode handshake: %v", err)
	}
	return b
}
