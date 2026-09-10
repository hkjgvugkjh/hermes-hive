// Command chatsnoop connects to the studio /chat-run Socket.IO namespace the
// same way the Web UI does, resumes one session, and dumps every event.
//
// This is the missing piece: /global-agent is the 小方盒 device channel, while
// session run events (run.started / run.completed / message.delta / ...) are
// delivered on the /chat-run namespace after emitting "resume".
package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

type st struct {
	n     int
	first time.Time
	last  time.Time
	samp  string
}

func main() {
	base := envDef("STUDIO_URL", "http://localhost:8648")
	user := envDef("STUDIO_USER", "admin")
	pass := envDef("STUDIO_PASS", "123456")
	sid := os.Getenv("SESSION_ID")
	secs := 40
	fmt.Sscanf(os.Getenv("SNOOP_SECS"), "%d", &secs)
	if secs <= 0 {
		secs = 40
	}

	inst := "PROXY-C" + fmt.Sprintf("%06X", time.Now().UnixNano()%0x1000000)

	// mcu-login to get a JWT usable as socket.io auth token
	body := map[string]any{
		"token": inst, "id": inst, "device_code": inst,
		"device_type": "hermes-proxy", "source": "global_agent",
		"account": user, "password": pass, "relayMode": "lan",
	}
	b, _ := json.Marshal(body)
	req, _ := http.NewRequest(http.MethodPost, base+"/api/auth/mcu-login", strings.NewReader(string(b)))
	req.Header.Set("Content-Type", "application/json")
	resp, err := (&http.Client{Timeout: 15 * time.Second}).Do(req)
	if err != nil {
		log.Fatalf("mcu-login: %v", err)
	}
	var lr struct {
		Token    string   `json:"token"`
		Profiles []string `json:"profiles"`
	}
	_ = json.NewDecoder(resp.Body).Decode(&lr)
	resp.Body.Close()
	jwt := lr.Token
	if jwt == "" {
		log.Fatalf("no token (HTTP %d)", resp.StatusCode)
	}
	log.Printf("mcu-login ok profiles=%v jwt=%d", lr.Profiles, len(jwt))

	// if no session given, pick the most recently active one
	if sid == "" {
		r2, _ := http.NewRequest(http.MethodGet, base+"/api/hermes/sessions", nil)
		r2.Header.Set("Authorization", "Bearer "+jwt)
		rp, err := (&http.Client{Timeout: 15 * time.Second}).Do(r2)
		if err != nil {
			log.Fatalf("sessions: %v", err)
		}
		var sr struct {
			Sessions []struct {
				ID         string `json:"id"`
				LastActive int64  `json:"last_active"`
			} `json:"sessions"`
		}
		_ = json.NewDecoder(rp.Body).Decode(&sr)
		rp.Body.Close()
		best := int64(0)
		for _, s := range sr.Sessions {
			if s.LastActive > best {
				best, sid = s.LastActive, s.ID
			}
		}
		log.Printf("auto-picked session %s", sid)
	}

	u, _ := url.Parse(base)
	if u.Scheme == "https" {
		u.Scheme = "wss"
	} else {
		u.Scheme = "ws"
	}
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
	defer ws.Close()
	log.Printf("ws connected -> %s", u.String())

	var mu sync.Mutex
	stats := map[string]*st{}
	raws := map[string]int{}
	stop := make(chan struct{})

	send := func(s string) {
		mu.Lock()
		_ = ws.WriteMessage(websocket.TextMessage, []byte(s))
		mu.Unlock()
	}

	go func() {
		for {
			select {
			case <-stop:
				return
			default:
			}
			_, msg, err := ws.ReadMessage()
			if err != nil {
				log.Printf("read err: %v", err)
				return
			}
			f := string(msg)
			if f == "" {
				continue
			}
			mu.Lock()
			raws[f[:1]]++
			mu.Unlock()
			switch f[0] {
			case '2':
				send("3")
			case '4':
				if len(f) < 2 {
					continue
				}
				switch f[1] {
				case '0': // namespace CONNECT ack
					log.Printf("NS CONNECT ACK: %s", f)
					// now resume the session (subscribe to its events)
					pkt, _ := json.Marshal([]any{"resume", map[string]any{"session_id": sid, "profile": "default"}})
					send(fmt.Sprintf(`42/chat-run,%s`, pkt))
					log.Printf(">> resume session %s", sid)
				case '2':
					rest := f[2:]
					if i := strings.Index(rest, ","); i >= 0 {
						rest = rest[i+1:]
					}
					var arr []json.RawMessage
					if err := json.Unmarshal([]byte(rest), &arr); err != nil || len(arr) == 0 {
						continue
					}
					var name string
					_ = json.Unmarshal(arr[0], &name)
					data := ""
					if len(arr) > 1 {
						data = string(arr[1])
						if len(data) > 260 {
							data = data[:260] + "..."
						}
					}
					mu.Lock()
					x := stats[name]
					if x == nil {
						x = &st{first: time.Now(), samp: data}
						stats[name] = x
					}
					x.n++
					x.last = time.Now()
					mu.Unlock()
					log.Printf("<< %s  %s", name, data)
				}
			}
		}
	}()

	// namespace connect (socket.io v4: 40<namespace>,payload)
	auth, _ := json.Marshal(map[string]any{"token": jwt})
	send(fmt.Sprintf(`40/chat-run,%s`, auth))
	log.Printf("listening %ds ...", secs)

	go func() {
		t := time.NewTicker(20 * time.Second)
		defer t.Stop()
		for {
			select {
			case <-stop:
				return
			case <-t.C:
				send("2")
			}
		}
	}()

	time.Sleep(time.Duration(secs) * time.Second)
	close(stop)

	mu.Lock()
	defer mu.Unlock()
	fmt.Println("\n===== engine.io frames =====")
	for k, v := range raws {
		fmt.Printf("  %q x%d\n", k, v)
	}
	fmt.Printf("\n===== events (%d) =====\n", len(stats))
	names := make([]string, 0, len(stats))
	for k := range stats {
		names = append(names, k)
	}
	sort.Strings(names)
	for _, n := range names {
		x := stats[n]
		fmt.Printf("  %-28s x%-4d [%s -> %s]\n      %s\n", n, x.n,
			x.first.Format("15:04:05"), x.last.Format("15:04:05"), x.samp)
	}
}

func envDef(k, d string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return d
}
