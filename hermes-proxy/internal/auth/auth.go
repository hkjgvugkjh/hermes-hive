// Package auth implements authentication methods for hermes-proxy.
package auth

import (
	"context"
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"
	"time"

	"hermes-proxy/internal/config"
)

// Validator validates client authentication tokens.
type Validator struct {
	cfg    *config.AuthConfig
	client *http.Client
}

// NewValidator creates a new auth validator from config.
func NewValidator(cfg *config.AuthConfig) *Validator {
	return &Validator{
		cfg: cfg,
		client: &http.Client{
			Timeout: 10 * time.Second,
		},
	}
}

// Validate checks if the provided token is valid.
func (v *Validator) Validate(token string) (bool, error) {
	switch v.cfg.Method {
	case config.AuthMethodStaticToken:
		return v.validateStatic(token)
	case config.AuthMethodHTTPAPI:
		return v.validateHTTPAPI(token)
	default:
		return false, fmt.Errorf("unknown auth method: %s", v.cfg.Method)
	}
}

// validateStatic checks token against the pre-shared static token.
func (v *Validator) validateStatic(token string) (bool, error) {
	expected := v.cfg.StaticToken.Token
	if token == "" {
		return false, fmt.Errorf("token required")
	}
	if token != expected {
		return false, fmt.Errorf("invalid token")
	}
	return true, nil
}

// validateHTTPAPI calls an external API to validate the token.
func (v *Validator) validateHTTPAPI(token string) (bool, error) {
	apiCfg := v.cfg.HTTPAPI

	// Build request
	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(apiCfg.Timeout)*time.Second)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, apiCfg.URL, nil)
	if err != nil {
		return false, fmt.Errorf("create auth request: %w", err)
	}

	// Set auth header
	headerValue := token
	if apiCfg.TokenPrefix != "" {
		headerValue = apiCfg.TokenPrefix + token
	}
	req.Header.Set(apiCfg.Header, headerValue)

	// Execute
	resp, err := v.client.Do(req)
	if err != nil {
		return false, fmt.Errorf("auth API call failed: %w", err)
	}
	defer resp.Body.Close()

	// Read body for debugging
	body, _ := io.ReadAll(resp.Body)

	// Check response
	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		return true, nil
	}

	// Log failure details (truncate body)
	bodyStr := string(body)
	if len(bodyStr) > 200 {
		bodyStr = bodyStr[:200] + "..."
	}
	log.Printf("[auth] HTTP API rejected token: status=%d body=%s", resp.StatusCode, bodyStr)
	return false, fmt.Errorf("auth rejected (HTTP %d)", resp.StatusCode)
}

// ExtractToken extracts the token from a WebSocket request.
// Supports:
//   - X-Auth-Token header
//   - Authorization header (with optional Bearer prefix)
//   - token query parameter
func ExtractToken(r *http.Request) string {
	// Check X-Auth-Token header
	if token := r.Header.Get("X-Auth-Token"); token != "" {
		return token
	}

	// Check Authorization header
	if auth := r.Header.Get("Authorization"); auth != "" {
		// Strip Bearer prefix
		if strings.HasPrefix(auth, "Bearer ") {
			return auth[7:]
		}
		return auth
	}

	// Check query parameter
	return r.URL.Query().Get("token")
}
