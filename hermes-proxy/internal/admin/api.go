// Package admin provides REST API and web UI for proxy configuration.
package admin

import (
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/http"
	"strconv"
	"strings"
	"time"

	"hermes-proxy/internal/config"
)

// Server manages the admin API and web UI.
type Server struct {
	cfg    *config.Config
	mux    *http.ServeMux
	server *http.Server
}

// NewServer creates a new admin server.
func NewServer(cfg *config.Config, addr string) *Server {
	s := &Server{
		cfg: cfg,
		mux: http.NewServeMux(),
	}
	s.setupRoutes()

	s.server = &http.Server{
		Addr:         addr,
		Handler:      s,
		ReadTimeout:  30 * time.Second,
		WriteTimeout: 30 * time.Second,
	}
	return s
}

// setupRoutes configures all admin routes.
func (s *Server) setupRoutes() {
	// API routes (require admin token)
	s.mux.HandleFunc("/api/servers", s.handleAuth(s.handleServers))
	s.mux.HandleFunc("/api/servers/", s.handleAuth(s.handleServerDetail))
	s.mux.HandleFunc("/api/test", s.handleAuth(s.handleTestConnection))
	s.mux.HandleFunc("/api/config", s.handleAuth(s.handleConfig))
	s.mux.HandleFunc("/api/validate-config", s.handleAuth(s.handleValidateConfig))

	// Web UI (static HTML/JS)
	s.mux.HandleFunc("/", s.handleWebUI)
	s.mux.HandleFunc("/index.html", s.handleWebUI)
	s.mux.HandleFunc("/config", s.handleWebUI)
	s.mux.HandleFunc("/qrcode.min.js", s.handleQRCodeJS)
}

// handleQRCodeJS serves the local qrcode.min.js file.
func (s *Server) handleQRCodeJS(w http.ResponseWriter, r *http.Request) {
	http.ServeFile(w, r, "qrcode.min.js")
}

// Run starts the admin HTTP server.
func (s *Server) Run() error {
	log.Printf("[admin] Web UI listening on %s", s.server.Addr)
	return s.server.ListenAndServe()
}

// ServeHTTP implements http.Handler.
func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	s.mux.ServeHTTP(w, r)
}

// handleAuth wraps a handler with admin token authentication.
func (s *Server) handleAuth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if s.cfg.AdminToken == "" {
			next(w, r)
			return
		}

		auth := r.Header.Get("Authorization")
		if strings.HasPrefix(auth, "Bearer ") {
			auth = auth[7:]
		}
		if auth == s.cfg.AdminToken {
			next(w, r)
			return
		}

		if r.URL.Query().Get("token") == s.cfg.AdminToken {
			next(w, r)
			return
		}

		s.writeError(w, http.StatusUnauthorized, "admin authentication required")
	}
}

// handleServers handles GET (list) and POST (add/update) servers.
func (s *Server) handleServers(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		servers := s.cfg.GetServers()
		s.writeJSON(w, http.StatusOK, map[string]interface{}{
			"servers": servers,
		})
	case http.MethodPost:
		var server config.ServerConfig
		if err := json.NewDecoder(r.Body).Decode(&server); err != nil {
			s.writeError(w, http.StatusBadRequest, "invalid JSON")
			return
		}
		if server.ID == "" || server.URL == "" {
			s.writeError(w, http.StatusBadRequest, "id and url are required")
			return
		}
		if server.Profile == "" {
			server.Profile = "default"
		}
		s.cfg.UpdateServer(server)
		if err := s.cfg.Save(); err != nil {
			s.writeError(w, http.StatusInternalServerError, "failed to save config")
			return
		}
		s.writeJSON(w, http.StatusOK, map[string]interface{}{
			"message": "server added/updated",
			"server":  server,
		})
	default:
		s.writeError(w, http.StatusMethodNotAllowed, "method not allowed")
	}
}

// handleServerDetail handles GET, PUT, DELETE for a specific server.
func (s *Server) handleServerDetail(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimPrefix(r.URL.Path, "/api/servers/")
	if id == "" {
		s.writeError(w, http.StatusBadRequest, "server ID required")
		return
	}

	switch r.Method {
	case http.MethodGet:
		server := s.cfg.GetServer(id)
		if server == nil {
			s.writeError(w, http.StatusNotFound, "server not found")
			return
		}
		s.writeJSON(w, http.StatusOK, server)
	case http.MethodPut:
		var server config.ServerConfig
		if err := json.NewDecoder(r.Body).Decode(&server); err != nil {
			s.writeError(w, http.StatusBadRequest, "invalid JSON")
			return
		}
		server.ID = id
		if server.Profile == "" {
			server.Profile = "default"
		}
		s.cfg.UpdateServer(server)
		if err := s.cfg.Save(); err != nil {
			s.writeError(w, http.StatusInternalServerError, "failed to save config")
			return
		}
		s.writeJSON(w, http.StatusOK, map[string]interface{}{
			"message": "server updated",
			"server":  server,
		})
	case http.MethodDelete:
		if s.cfg.DeleteServer(id) {
			if err := s.cfg.Save(); err != nil {
				s.writeError(w, http.StatusInternalServerError, "failed to save config")
				return
			}
			s.writeJSON(w, http.StatusOK, map[string]interface{}{
				"message": "server deleted",
			})
		} else {
			s.writeError(w, http.StatusNotFound, "server not found")
		}
	default:
		s.writeError(w, http.StatusMethodNotAllowed, "method not allowed")
	}
}

// handleTestConnection tests a connection to a Hermes Studio server.
func (s *Server) handleTestConnection(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		s.writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	var req struct {
		URL      string `json:"url"`
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		s.writeError(w, http.StatusBadRequest, "invalid JSON")
		return
	}

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Get(req.URL + "/health")
	if err != nil {
		s.writeJSON(w, http.StatusOK, map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
		return
	}
	defer resp.Body.Close()

	if req.Username != "" && req.Password != "" {
		loginResp, err := client.Post(
			req.URL+"/api/auth/login",
			"application/json",
			strings.NewReader(fmt.Sprintf(`{"username":%q,"password":%q}`, req.Username, req.Password)),
		)
		if err != nil {
			s.writeJSON(w, http.StatusOK, map[string]interface{}{
				"success":     resp.StatusCode == 200,
				"health_ok":   resp.StatusCode == 200,
				"login_ok":    false,
				"login_error": err.Error(),
			})
			return
		}
		defer loginResp.Body.Close()

		s.writeJSON(w, http.StatusOK, map[string]interface{}{
			"success":   resp.StatusCode == 200 && loginResp.StatusCode == 200,
			"health_ok": resp.StatusCode == 200,
			"login_ok":  loginResp.StatusCode == 200,
		})
		return
	}

	s.writeJSON(w, http.StatusOK, map[string]interface{}{
		"success":   resp.StatusCode == 200,
		"health_ok": resp.StatusCode == 200,
	})
}

// handleConfig handles GET (read) and PUT (update) the proxy configuration.
func (s *Server) handleConfig(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		// Return current config with tokens for display in UI
		resp := map[string]interface{}{
			"listen":       s.cfg.Listen,
			"ws_path":      s.cfg.WSPath,
			"admin_path":   s.cfg.AdminPath,
			"host":         s.cfg.Host,
			"auth_method":  s.cfg.Auth.Method,
			"token":        "",
			"admin_token":  "",
			"servers":      s.cfg.GetServers(),
		}
		if s.cfg.Auth.Method == "static_token" && s.cfg.Auth.StaticToken != nil {
			resp["token"] = s.cfg.Auth.StaticToken.Token
			resp["admin_token"] = s.cfg.AdminToken
		}
		s.writeJSON(w, http.StatusOK, resp)
	case http.MethodPut:
		var req struct {
			Listen     string         `json:"listen"`
			WSPath     string         `json:"ws_path"`
			AdminPath  string         `json:"admin_path"`
			Host       string         `json:"host"`
			Auth       config.AuthConfig `json:"auth"`
			AdminToken string         `json:"admin_token"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			s.writeError(w, http.StatusBadRequest, "invalid JSON")
			return
		}
		if req.Listen != "" {
			s.cfg.Listen = req.Listen
		}
		if req.WSPath != "" {
			s.cfg.WSPath = req.WSPath
		}
		if req.AdminPath != "" {
			s.cfg.AdminPath = req.AdminPath
		}
		if req.Host != "" {
			s.cfg.Host = req.Host
		}
		if req.Auth.Method != "" {
			s.cfg.Auth = req.Auth
		}
		if req.AdminToken != "" {
			s.cfg.AdminToken = req.AdminToken
		}
		if err := s.cfg.Save(); err != nil {
			s.writeError(w, http.StatusInternalServerError, "failed to save config")
			return
		}
		s.writeJSON(w, http.StatusOK, map[string]interface{}{
			"message": "config updated",
		})
	default:
		s.writeError(w, http.StatusMethodNotAllowed, "method not allowed")
	}
}

// handleValidateConfig validates proxy configuration parameters.
// Note: ports already used by this running proxy are considered valid.
func (s *Server) handleValidateConfig(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		s.writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	var req struct {
		Listen     string `json:"listen"`
		WSPath     string `json:"ws_path"`
		AdminPort  string `json:"admin_port"`
		Token      string `json:"token"`
		AdminToken string `json:"admin_token"`
		Host       string `json:"host"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		s.writeError(w, http.StatusBadRequest, "invalid JSON")
		return
	}

	var errors []string

	// Parse current ports for comparison
	currentListenPort := 0
	currentAdminPort := 0
	if p, err := strconv.Atoi(strings.TrimPrefix(s.cfg.Listen, ":")); err == nil {
		currentListenPort = p
	}
	if p, err := strconv.Atoi(strings.TrimPrefix(s.cfg.AdminPath, ":")); err == nil {
		currentAdminPort = p
	}

	// Validate listen port
	if req.Listen == "" {
		errors = append(errors, "WebSocket 监听端口不能为空")
	} else {
		port, err := strconv.Atoi(strings.TrimPrefix(req.Listen, ":"))
		if err != nil || port < 1 || port > 65535 {
			errors = append(errors, "WebSocket 监听端口无效（应为 1-65535）")
		} else if port != currentListenPort {
			// Only check availability if changing to a different port
			ln, err := net.Listen("tcp", fmt.Sprintf(":%d", port))
			if err != nil {
				errors = append(errors, fmt.Sprintf("端口 %d 已被其他程序占用", port))
			} else {
				ln.Close()
			}
		}
		// If port == currentListenPort, it's our own proxy - OK
	}

	// Validate admin port
	if req.AdminPort == "" {
		errors = append(errors, "Admin 端口不能为空")
	} else {
		port, err := strconv.Atoi(strings.TrimPrefix(req.AdminPort, ":"))
		if err != nil || port < 1 || port > 65535 {
			errors = append(errors, "Admin 端口无效（应为 1-65535）")
		} else if port != currentAdminPort {
			// Only check availability if changing to a different port
			ln, err := net.Listen("tcp", fmt.Sprintf(":%d", port))
			if err != nil {
				errors = append(errors, fmt.Sprintf("端口 %d 已被其他程序占用", port))
			} else {
				ln.Close()
			}
		}
		// If port == currentAdminPort, it's our own proxy - OK
	}

	// Validate WS path
	if req.WSPath != "" && !strings.HasPrefix(req.WSPath, "/") {
		errors = append(errors, "WebSocket 路径必须以 / 开头")
	}

	if len(errors) > 0 {
		s.writeJSON(w, http.StatusOK, map[string]interface{}{
			"valid":  false,
			"errors": errors,
		})
		return
	}

	s.writeJSON(w, http.StatusOK, map[string]interface{}{
		"valid": true,
	})
}

// handleWebUI serves the embedded web configuration UI.
func (s *Server) handleWebUI(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" && r.URL.Path != "/index.html" && r.URL.Path != "/config" {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Write([]byte(webUIHTML))
}

// writeJSON writes a JSON response.
func (s *Server) writeJSON(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

// writeError writes a JSON error response.
func (s *Server) writeError(w http.ResponseWriter, status int, msg string) {
	s.writeJSON(w, status, map[string]string{"error": msg})
}
