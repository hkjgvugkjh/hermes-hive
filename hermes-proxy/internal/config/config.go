// Package config manages hermes-proxy configuration.
package config

import (
	"encoding/json"
	"fmt"
	"os"
	"sync"
)

// AuthMethod defines the authentication method type.
type AuthMethod string

const (
	// AuthMethodStaticToken uses a pre-shared static token for authentication.
	AuthMethodStaticToken AuthMethod = "static_token"
	// AuthMethodHTTPAPI uses an external HTTP API to validate tokens.
	AuthMethodHTTPAPI AuthMethod = "http_api"
)

// StaticTokenAuth configures static token authentication.
type StaticTokenAuth struct {
	// Token is the pre-shared secret that clients must provide.
	Token string `json:"token"`
}

// HTTPAPIAuth configures HTTP API authentication.
type HTTPAPIAuth struct {
	// URL is the endpoint to validate tokens (e.g., https://auth.example.com/validate)
	URL string `json:"url"`
	// Header name to send the token in (default: Authorization)
	Header string `json:"header"`
	// TokenPrefix is the prefix before the token (e.g., "Bearer ")
	TokenPrefix string `json:"token_prefix"`
	// Timeout in seconds for the auth API call (default: 5)
	Timeout int `json:"timeout"`
}

// AuthConfig holds the authentication configuration.
type AuthConfig struct {
	// Method is the authentication method (required).
	Method AuthMethod `json:"method"`
	// StaticToken config (required when method=static_token)
	StaticToken *StaticTokenAuth `json:"static_token,omitempty"`
	// HTTPAPI config (required when method=http_api)
	HTTPAPI *HTTPAPIAuth `json:"http_api,omitempty"`
}

// ServerConfig represents a single Hermes Studio server configuration.
type ServerConfig struct {
	ID       string `json:"id"`       // Unique identifier
	Name     string `json:"name"`     // Display name
	URL      string `json:"url"`      // http://host:port
	Enabled  bool   `json:"enabled"`  // Whether this server is active
	// Credentials for auto-login (optional)
	Username string `json:"username,omitempty"`
	Password string `json:"password,omitempty"`
	// Profile to use (default: "default")
	Profile string `json:"profile"`
}

// Config is the top-level proxy configuration.
type Config struct {
	// Listen address for WebSocket connections from hermes-hive
	Listen string `json:"listen"`
	// Path for the WebSocket endpoint (e.g., /ws)
	WSPath string `json:"ws_path"`
	// Path for the admin API (e.g., /admin)
	AdminPath string `json:"admin_path"`
	// Auth configuration (required)
	Auth AuthConfig `json:"auth"`
	// Admin token for accessing the web UI and API
	AdminToken string `json:"admin_token"`
	// List of Hermes Studio servers
	Servers []ServerConfig `json:"servers"`
	// Logging level: debug, info, warn, error
	LogLevel string `json:"log_level"`
	// Path to the config file (for saving)
	ConfigPath string `json:"-"`
	// Mutex for thread-safe config updates
	mu sync.RWMutex `json:"-"`
}

// DefaultConfig returns a default configuration.
func DefaultConfig() *Config {
	return &Config{
		Listen:     ":8080",
		WSPath:     "/ws",
		AdminPath:  "/admin",
		LogLevel:   "info",
		Servers:    []ServerConfig{},
		AdminToken: "",
	}
}

// LoadConfig loads configuration from a JSON file.
func LoadConfig(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("failed to read config: %w", err)
	}
	cfg := DefaultConfig()
	if err := json.Unmarshal(data, cfg); err != nil {
		return nil, fmt.Errorf("failed to parse config: %w", err)
	}
	cfg.ConfigPath = path
	return cfg, nil
}

// SaveConfig saves configuration to a JSON file.
func SaveConfig(cfg *Config, path string) error {
	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal config: %w", err)
	}
	return os.WriteFile(path, data, 0644)
}

// Save persists the current config to disk.
func (c *Config) Save() error {
	c.mu.RLock()
	defer c.mu.RUnlock()
	if c.ConfigPath == "" {
		return fmt.Errorf("no config path set")
	}
	return SaveConfig(c, c.ConfigPath)
}

// GetServer returns a server config by ID.
func (c *Config) GetServer(id string) *ServerConfig {
	c.mu.RLock()
	defer c.mu.RUnlock()
	for i := range c.Servers {
		if c.Servers[i].ID == id {
			return &c.Servers[i]
		}
	}
	return nil
}

// GetServers returns a copy of all servers (for API responses).
func (c *Config) GetServers() []ServerConfig {
	c.mu.RLock()
	defer c.mu.RUnlock()
	servers := make([]ServerConfig, len(c.Servers))
	copy(servers, c.Servers)
	return servers
}

// UpdateServer updates or adds a server.
func (c *Config) UpdateServer(server ServerConfig) {
	c.mu.Lock()
	defer c.mu.Unlock()
	for i := range c.Servers {
		if c.Servers[i].ID == server.ID {
			c.Servers[i] = server
			return
		}
	}
	c.Servers = append(c.Servers, server)
}

// DeleteServer removes a server by ID.
func (c *Config) DeleteServer(id string) bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	for i := range c.Servers {
		if c.Servers[i].ID == id {
			c.Servers = append(c.Servers[:i], c.Servers[i+1:]...)
			return true
		}
	}
	return false
}

// Validate checks the configuration for errors.
func (c *Config) Validate() error {
	if c.Listen == "" {
		return fmt.Errorf("listen address is required")
	}
	if c.WSPath == "" {
		c.WSPath = "/ws"
	}
	if c.AdminPath == "" {
		c.AdminPath = "/admin"
	}

	// Auth is required
	if c.Auth.Method == "" {
		return fmt.Errorf("auth.method is required (static_token or http_api)")
	}
	switch c.Auth.Method {
	case AuthMethodStaticToken:
		if c.Auth.StaticToken == nil || c.Auth.StaticToken.Token == "" {
			return fmt.Errorf("auth.static_token.token is required when method=static_token")
		}
	case AuthMethodHTTPAPI:
		if c.Auth.HTTPAPI == nil || c.Auth.HTTPAPI.URL == "" {
			return fmt.Errorf("auth.http_api.url is required when method=http_api")
		}
		if c.Auth.HTTPAPI.Timeout <= 0 {
			c.Auth.HTTPAPI.Timeout = 5
		}
		if c.Auth.HTTPAPI.Header == "" {
			c.Auth.HTTPAPI.Header = "Authorization"
		}
	default:
		return fmt.Errorf("unknown auth method: %s (must be 'static_token' or 'http_api')", c.Auth.Method)
	}

	for i, s := range c.Servers {
		if s.ID == "" {
			return fmt.Errorf("server[%d]: ID is required", i)
		}
		if s.URL == "" {
			return fmt.Errorf("server[%d]: URL is required", i)
		}
	}
	return nil
}
