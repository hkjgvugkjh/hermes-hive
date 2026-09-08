package proxy

import (
	"encoding/json"
	"log"
	"net/http"
	"time"

	"hermes-proxy/internal/di"
)

// pollSessions runs the session-state poller for a connected hermes_studio
// backend. Per design, the proxy is responsible for producing session updates
// even when the backend does not push them. We poll /api/sessions periodically
// and diff against the last snapshot, pushing only the changes.
func (s *Server) pollSessions(client *Client, ab *activeBackend) {
	ticker := time.NewTicker(sessionPollInterval)
	defer ticker.Stop()
	var last map[string]di.Session
	for {
		select {
		case <-ab.pollStop:
			return
		case <-ticker.C:
			snapshot, err := s.fetchSessionSnapshot(ab)
			if err != nil {
				log.Printf("[di][poll] fetch sessions for %s failed: %v", ab.cfg.ID, err)
				continue
			}
			diff := diffSessions(last, snapshot)
			if len(diff) == 0 {
				continue
			}
			last = snapshot
			s.sendDIFrame(client, di.TypeDISessionUpdate, di.DISessionUpdatePayload{
				ServerID: ab.cfg.ID,
				Full:     false,
				Sessions: diff,
			})
		}
	}
}

// pushSessionSnapshot sends the full current snapshot (used on explicit poll
// request or server switch).
func (s *Server) pushSessionSnapshot(client *Client, ab *activeBackend, full bool) {
	snap, err := s.fetchSessionSnapshot(ab)
	if err != nil {
		return
	}
	s.sendDIFrame(client, di.TypeDISessionUpdate, di.DISessionUpdatePayload{
		ServerID: ab.cfg.ID,
		Full:     full,
		Sessions: snapshotToList(snap),
	})
}

// fetchSessionSnapshot pulls the session list from a hermes_studio backend.
// It uses the JWT obtained during mcu-login (stored on the activeBackend) when
// available; otherwise falls back to basic auth from configured credentials.
func (s *Server) fetchSessionSnapshot(ab *activeBackend) (map[string]di.Session, error) {
	url := ab.cfg.URL + "/api/hermes/sessions"
	if ab.cfg.Profile != "" {
		url += "?profile=" + ab.cfg.Profile
	}
	req, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	if ab.jwt != "" {
		req.Header.Set("Authorization", "Bearer "+ab.jwt)
	} else if ab.cfg.Username != "" {
		req.SetBasicAuth(ab.cfg.Username, ab.cfg.Password)
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
			ServerID:   ab.cfg.ID,
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
	for id := range prev {
		if _, ok := cur[id]; !ok {
			out = append(out, di.Session{ID: id, Status: "gone", ServerID: cur[id].ServerID})
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
