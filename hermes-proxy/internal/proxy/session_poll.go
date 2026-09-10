package proxy

import (
	"encoding/json"
	"log"
	"net/http"
	"time"

	"hermes-proxy/internal/di"
)

// pollBackend runs the session-state poller for one shared hermes_studio
// backend. There is exactly one poller per backend no matter how many clients
// are subscribed; its diffs are fanned out by broadcastDI.
func (s *Server) pollBackend(bc *backendConn) {
	ticker := time.NewTicker(sessionPollInterval)
	defer ticker.Stop()
	var last map[string]di.Session
	for {
		select {
		case <-bc.pollStop:
			return
		case <-ticker.C:
			snapshot, err := s.fetchSessionSnapshot(bc)
			if err != nil {
				log.Printf("[di][poll] fetch sessions for %s failed: %v", bc.id, err)
				continue
			}
			diff := diffSessions(last, snapshot)
			if len(diff) == 0 {
				continue
			}
			last = snapshot
			s.broadcastDI(bc, di.TypeDISessionUpdate, di.DISessionUpdatePayload{
				ServerID: bc.id,
				Full:     false,
				Sessions: diff,
			})
		}
	}
}

// pushSessionSnapshot sends the current snapshot to all subscribers of bc
// (used on connect and on explicit poll).
func (s *Server) pushSessionSnapshot(bc *backendConn, full bool) {
	snapshot, err := s.fetchSessionSnapshot(bc)
	if err != nil {
		log.Printf("[di] snapshot for %s failed: %v", bc.id, err)
		s.broadcastDI(bc, di.TypeDIError, di.DIErrorPayload{
			ServerID: bc.id, Message: err.Error(),
		})
		return
	}
	s.broadcastDI(bc, di.TypeDISessionUpdate, di.DISessionUpdatePayload{
		ServerID: bc.id,
		Full:     full,
		Sessions: snapshotToList(snapshot),
	})
}

// clientSnapshot sends a snapshot to one client only (used right after that
// client attaches, so it does not have to wait for the next poll tick).
func (s *Server) clientSnapshot(client *Client, bc *backendConn, full bool) {
	snapshot, err := s.fetchSessionSnapshot(bc)
	if err != nil {
		s.sendDIFrame(client, di.TypeDIError, di.DIErrorPayload{
			ServerID: bc.id, Message: err.Error(),
		})
		return
	}
	s.sendDIFrame(client, di.TypeDISessionUpdate, di.DISessionUpdatePayload{
		ServerID: bc.id,
		Full:     full,
		Sessions: snapshotToList(snapshot),
	})
}

// fetchSessionSnapshot pulls the session list from a hermes_studio backend.
// It uses the JWT obtained during mcu-login when available; otherwise falls
// back to basic auth from configured credentials.
func (s *Server) fetchSessionSnapshot(bc *backendConn) (map[string]di.Session, error) {
	bc.mu.Lock()
	cfg := bc.cfg
	jwt := bc.jwt
	bc.mu.Unlock()
	if cfg == nil {
		return nil, errHTTPStatus(0)
	}

	url := cfg.URL + "/api/hermes/sessions"
	if cfg.Profile != "" {
		url += "?profile=" + cfg.Profile
	}
	req, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	if jwt != "" {
		req.Header.Set("Authorization", "Bearer "+jwt)
	} else if cfg.Username != "" {
		req.SetBasicAuth(cfg.Username, cfg.Password)
	}
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, errHTTPStatus(resp.StatusCode)
	}
	var raw struct {
		Sessions []struct {
			ID         string `json:"id"`
			Title      string `json:"title"`
			LastActive int64  `json:"last_active"`
		} `json:"sessions"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&raw); err != nil {
		return nil, err
	}
	out := make(map[string]di.Session, len(raw.Sessions))
	for _, ss := range raw.Sessions {
		out[ss.ID] = di.Session{
			ID:         ss.ID,
			Title:      ss.Title,
			LastActive: ss.LastActive,
			ServerID:   bc.id,
		}
	}
	return out, nil
}

// diffSessions returns only the sessions that changed (added/updated/removed)
// between prev and cur. Removal is represented by Status="gone".
func diffSessions(prev, cur map[string]di.Session) []di.Session {
	out := make([]di.Session, 0)
	for id, cs := range cur {
		ps, ok := prev[id]
		if !ok || ps != cs {
			out = append(out, cs)
		}
	}
	for id, ps := range prev {
		if _, ok := cur[id]; !ok {
			out = append(out, di.Session{ID: id, Status: "gone", ServerID: ps.ServerID})
		}
	}
	return out
}

// snapshotToList converts a snapshot map to a slice.
func snapshotToList(m map[string]di.Session) []di.Session {
	out := make([]di.Session, 0, len(m))
	for _, v := range m {
		out = append(out, v)
	}
	return out
}

// errHTTPStatus is a small error wrapper.
type errHTTPStatus int

func (e errHTTPStatus) Error() string { return "unexpected HTTP status " + itoa(int(e)) }

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	buf := make([]byte, 0, 12)
	for n > 0 {
		buf = append([]byte{byte('0' + n%10)}, buf...)
		n /= 10
	}
	if neg {
		buf = append([]byte{'-'}, buf...)
	}
	return string(buf)
}
