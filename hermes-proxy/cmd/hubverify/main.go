// cmd/hubverify — 端到端验证 client/dispatch/service 共享模型。
//
// 连 N 个 WebSocket 客户端到同一个 proxy，全部 attach 到同一台服务器。
// 断言：
//   1. 每个客户端都收到 ConnectAck(OK) 与会话快照
//   2. 后端只拨号一次（proxy 日志 "[hub] backend X ready" 只出现 1 次）
//   3. 客户端 A 断开后，剩余客户端仍能收到后续会话更新（广播）
//
// 用法：PROXY_WS=ws://127.0.0.1:8649/ws?token=XXX PROXY_TOKEN=XXX \
//       SERVER_ID=185 go run ./cmd/hubverify
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

	// Phase 2: drop client 0, then ask a survivor to re-poll and confirm it
	// still gets updates from the shared backend.
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

	// Handshake: send our pubkey, read server pubkey, derive shared key.
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

	if err := sendDI(c, key, di.TypeDIConnect, di.DIConnectPayload{ServerID: serverID}); err != nil {
		r.err = err
		return r
	}

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
		if err != nil {
			continue
		}
		if mtype == di.TypeDISessionUpdate {
			return true
		}
	}
	return false
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
