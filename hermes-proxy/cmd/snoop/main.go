// Command snoop connects to a hermes_studio backend exactly the way the
// 小方盒 device does, then dumps every Socket.IO event it receives for a
// fixed duration. It is a diagnostics tool: used to discover which events a
// backend actually pushes, and whether per-session channels exist.
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

type evtStat struct {
	count  int
	sample string
	first  time.Time
	last   time.Time
}

func main() {
	base := os.Getenv("STUDIO_URL")
	if base == "" {
		base = "http://localhost:8648"
	}
	user := os.Getenv("STUDIO_USER")
	if user == "" {
		user = "admin"
	}
	pass := os.Getenv("STUDIO_PASS")
	if pass == "" {
		pass = "123456"
	}
	secs := 40
	fmt.Sscanf(os.Getenv("SNOOP_SECS"), "%d", &secs)
	if secs <= 0 {
		secs = 40
	}

	inst := "PROXY-" + fmt.Sprintf("%06X", time.Now().UnixNano()%0x1000000)
	dev := inst

	// --- mcu-login ---
	body := map[string]interface{}{
		"token": strings.ToUpper(inst), "id": strings.ToUpper(inst),
		"device_code": strings.ToUpper(dev), "device_type": "hermes-proxy",
		"source": "global_agent", "account": user, "password": pass, "relayMode": "lan",
	}
	b, _ := json.Marshal(body)
	req, _ := http.NewRequest(http.MethodPost, base+"/api/auth/mcu-login", strings.NewReader(string(b)))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Hermes-Device-Id", strings.ToUpper(inst))
	req.Header.Set("X-Hermes-Device-Name", "Hermes Snoop")
	resp, err := (&http.Client{Timeout: 15 * time.Second}).Do(req)
	if err != nil {
		log.Fatalf("mcu-login: %v", err)
	}
	var lr struct {
		Token    string   `json:"token"`
		Profiles []string `json:"profiles"`
	}
	json.NewDecoder(resp.Body).Decode(&lr)
	resp.Body.Close()
	if lr.Token == "" {
		log.Fatalf("mcu-login returned no token (HTTP %d)", resp.StatusCode)
	}
	jwt := lr.Token
	log.Printf("mcu-login ok, profiles=%v", lr.Profiles)

	// --- socket.io ---
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
	q.Set("token", jwt)
	q.Set("deviceCode", strings.ToUpper(dev))
	q.Set("device_code", strings.ToUpper(dev))
	u.RawQuery = q.Encode()

	h := http.Header{}
	h.Set("X-Hermes-Device-Id", strings.ToUpper(dev))
	h.Set("X-Hermes-Device-Name", "Hermes Snoop")
	d := websocket.Dialer{HandshakeTimeout: 15 * time.Second}
	ws, _, err := d.Dial(u.String(), h)
	if err != nil {
		log.Fatalf("dial: %v", err)
	}
	defer ws.Close()
	log.Printf("ws connected")

	var mu sync.Mutex
	sid := ""
	stats := map[string]*evtStat{}
	raw := map[string]int{} // engine.io frame prefix -> count
	stop := make(chan struct{})
	var once sync.Once

	// reader
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
			mu.Lock()
			if len(f) > 0 {
				raw[f[:1]]++
			}
			mu.Unlock()
			if len(f) == 0 {
				continue
			}
			switch f[0] {
			case '0':
				var o struct{ Sid string `json:"sid"` }
				json.Unmarshal([]byte(f[1:]), &o)
				mu.Lock()
				sid = o.Sid
				mu.Unlock()
			case '2':
				ws.WriteMessage(websocket.TextMessage, []byte("3"))
			case '4':
				// socket.io packet
				if len(f) > 2 && f[1] == '2' {
					rest := f[2:]
					if i := strings.Index(rest, ","); i >= 0 {
						rest = rest[i+1:]
					}
					var arr []json.RawMessage
					if err := json.Unmarshal([]byte(rest), &arr); err != nil || len(arr) < 1 {
						continue
					}
					var name string
					json.Unmarshal(arr[0], &name)
					data := ""
					if len(arr) > 1 {
						data = string(arr[1])
						if len(data) > 300 {
							data = data[:300] + "..."
						}
					}
					mu.Lock()
					st := stats[name]
					if st == nil {
						st = &evtStat{sample: data, first: time.Now()}
						stats[name] = st
					}
					st.count++
					st.last = time.Now()
					mu.Unlock()
				}
			}
		}
	}()

	// wait for OPEN
	deadline := time.Now().Add(10 * time.Second)
	for {
		mu.Lock()
		got := sid != ""
		mu.Unlock()
		if got {
			break
		}
		if time.Now().After(deadline) {
			log.Fatal("timeout waiting for OPEN")
		}
		time.Sleep(50 * time.Millisecond)
	}

	send := func(s string) {
		ws.WriteMessage(websocket.TextMessage, []byte(s))
	}
	send(fmt.Sprintf(`40/global-agent,{"token":%q,"deviceCode":%q,"device_code":%q,"role":"hermes-studio","instanceId":%q,"profile":"default"}`,
		jwt, strings.ToUpper(dev), strings.ToUpper(dev), strings.ToUpper(inst)))
	time.Sleep(150 * time.Millisecond)
	send(fmt.Sprintf(`42/global-agent,["mcu.ready",{"apiToken":%q,"type":"mcu.ready","id":%q,"active_device":%q,"profile":"default","capabilities":{"display":true,"audio_queue":true,"audio_playback":true,"pcm_stream":false}}]`,
		jwt, strings.ToUpper(inst), strings.ToUpper(inst)))
	log.Printf("handshake sent; listening %ds ...", secs)

	// heartbeat
	go func() {
		t := time.NewTicker(25 * time.Second)
		defer t.Stop()
		for {
			select {
			case <-stop:
				return
			case <-t.C:
				send(fmt.Sprintf(`42/global-agent,["mcu.status",{"id":%q,"active_device":%q,"profile":"default","status":"ready"}]`,
					strings.ToUpper(inst), strings.ToUpper(inst)))
			}
		}
	}()

	time.Sleep(time.Duration(secs) * time.Second)
	once.Do(func() { close(stop) })

	mu.Lock()
	defer mu.Unlock()
	fmt.Println("\n===== Engine.IO frame types =====")
	for k, v := range raw {
		fmt.Printf("  prefix %q x%d\n", k, v)
	}
	fmt.Printf("\n===== Socket.IO events (%d distinct) =====\n", len(stats))
	names := make([]string, 0, len(stats))
	for k := range stats {
		names = append(names, k)
	}
	sort.Strings(names)
	for _, n := range names {
		st := stats[n]
		fmt.Printf("\n- %s  x%d  [%s -> %s]\n", n, st.count,
			st.first.Format("15:04:05"), st.last.Format("15:04:05"))
		fmt.Printf("    sample: %s\n", st.sample)
	}
}
