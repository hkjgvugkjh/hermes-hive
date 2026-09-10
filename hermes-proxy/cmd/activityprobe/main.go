// Command activityprobe discovers whether the /chat-run namespace can carry
// activity for MANY sessions at once.
//
// Case A: connect namespace, do NOT resume -> what arrives?
// Case B: resume N sessions on one socket   -> what arrives?
package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

type probe struct {
	ws   *websocket.Conn
	mu   sync.Mutex
	evs  []string
	stop chan struct{}
}

func (p *probe) send(s string) {
	p.mu.Lock()
	_ = p.ws.WriteMessage(websocket.TextMessage, []byte(s))
	p.mu.Unlock()
}

func (p *probe) run() {
	for {
		select {
		case <-p.stop:
			return
		default:
		}
		_, msg, err := p.ws.ReadMessage()
		if err != nil {
			return
		}
		f := string(msg)
		if len(f) >= 2 && f[0] == '4' && f[1] == '2' {
			rest := f[2:]
			if i := strings.Index(rest, ","); i >= 0 {
				rest = rest[i+1:]
			}
			var arr []json.RawMessage
			if json.Unmarshal([]byte(rest), &arr) == nil && len(arr) > 0 {
				var n string
				_ = json.Unmarshal(arr[0], &n)
				var extra string
				if len(arr) > 1 {
					var m map[string]any
					if json.Unmarshal(arr[1], &m) == nil {
						if v, ok := m["session_id"].(string); ok {
							extra = " sid=" + v
						}
						if v, ok := m["status"].(string); ok {
							extra += " status=" + v
						}
						if v, ok := m["sessions"]; ok {
							b, _ := json.Marshal(v)
							if len(b) > 200 {
								b = b[:200]
							}
							extra += " sessions=" + string(b)
						}
					}
				}
				p.mu.Lock()
				p.evs = append(p.evs, n+extra)
				p.mu.Unlock()
				log.Printf("   << %s%s", n, extra)
			}
		} else if len(f) > 0 && f[0] == '2' {
			p.send("3")
		}
	}
}

func connect(base, jwt string) *probe {
	u, _ := url.Parse(base)
	u.Scheme = strings.Replace(u.Scheme, "http", "ws", 1)
	u.Path = strings.TrimRight(u.Path, "/") + "/socket.io/"
	q := u.Query()
	q.Set("EIO", "4")
	q.Set("transport", "websocket")
	q.Set("profile", "default")
	u.RawQuery = q.Encode()
	d := websocket.Dialer{HandshakeTimeout: 20 * time.Second}
	ws, _, err := d.Dial(u.String(), nil)
	if err != nil {
		log.Fatalf("dial: %v", err)
	}
	p := &probe{ws: ws, stop: make(chan struct{})}
	go p.run()
	auth, _ := json.Marshal(map[string]any{"token": jwt})
	p.send(fmt.Sprintf("40/chat-run,%s", auth))
	time.Sleep(400 * time.Millisecond)
	return p
}

func main() {
	base := "http://localhost:8648"
	if v := os.Getenv("STUDIO_URL"); v != "" {
		base = v
	}
	user, pass := "admin", "123456"
	if v := os.Getenv("STUDIO_USER"); v != "" {
		user = v
	}
	if v := os.Getenv("STUDIO_PASS"); v != "" {
		pass = v
	}

	inst := "PROXY-A" + fmt.Sprintf("%06X", time.Now().UnixNano()%0x1000000)
	body := map[string]any{
		"token": inst, "id": inst, "device_code": inst, "device_type": "hermes-proxy",
		"source": "global_agent", "account": user, "password": pass, "relayMode": "lan",
	}
	b, _ := json.Marshal(body)
	req, _ := http.NewRequest(http.MethodPost, base+"/api/auth/mcu-login", strings.NewReader(string(b)))
	req.Header.Set("Content-Type", "application/json")
	resp, err := (&http.Client{Timeout: 15 * time.Second}).Do(req)
	if err != nil {
		log.Fatal(err)
	}
	var lr struct{ Token string }
	_ = json.NewDecoder(resp.Body).Decode(&lr)
	resp.Body.Close()
	jwt := lr.Token
	log.Printf("jwt=%d", len(jwt))

	// top 3 sessions by last_active
	r2, _ := http.NewRequest(http.MethodGet, base+"/api/hermes/sessions", nil)
	r2.Header.Set("Authorization", "Bearer "+jwt)
	rp, _ := (&http.Client{Timeout: 15 * time.Second}).Do(r2)
	var sr struct {
		Sessions []struct {
			ID         string `json:"id"`
			LastActive int64  `json:"last_active"`
			Title      string `json:"title"`
		} `json:"sessions"`
	}
	_ = json.NewDecoder(rp.Body).Decode(&sr)
	rp.Body.Close()
	ids := []string{}
	for i, s := range sr.Sessions {
		if i >= 3 {
			break
		}
		ids = append(ids, s.ID)
	}
	log.Printf("top sessions: %v", ids)

	log.Printf("\n===== CASE A: connect only, NO resume (25s) =====")
	pa := connect(base, jwt)
	time.Sleep(25 * time.Second)
	close(pa.stop)
	pa.mu.Lock()
	fmt.Printf("CASE A events (%d):\n", len(pa.evs))
	for _, e := range pa.evs {
		fmt.Println("   ", e)
	}
	pa.mu.Unlock()
	pa.ws.Close()

	log.Printf("\n===== CASE B: resume %d sessions on ONE socket (50s) =====", len(ids))
	pb := connect(base, jwt)
	for _, id := range ids {
		pkt, _ := json.Marshal([]any{"resume", map[string]any{"session_id": id, "profile": "default"}})
		pb.send(fmt.Sprintf("42/chat-run,%s", pkt))
		log.Printf("   >> resume %s", id)
		time.Sleep(300 * time.Millisecond)
	}
	time.Sleep(50 * time.Second)
	close(pb.stop)
	pb.mu.Lock()
	fmt.Printf("\nCASE B events (%d):\n", len(pb.evs))
	for _, e := range pb.evs {
		fmt.Println("   ", e)
	}
	pb.mu.Unlock()
	pb.ws.Close()
}
