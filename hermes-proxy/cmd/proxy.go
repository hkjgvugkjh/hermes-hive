// Command hermes-proxy is the main entry point for the proxy server.
package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"

	"hermes-proxy/internal/admin"
	"hermes-proxy/internal/config"
	"hermes-proxy/internal/proxy"
)

var (
	configPath  = flag.String("config", "config.json", "Path to config file")
	genConfig   = flag.Bool("gen-config", false, "Generate a sample config file")
	adminAddr   = flag.String("admin", "", "Admin API/Web UI address (e.g., :8081)")
)

func main() {
	flag.Parse()

	if *genConfig {
		cfg := config.DefaultConfig()
		cfg.Auth = config.AuthConfig{
			Method: config.AuthMethodStaticToken,
			StaticToken: &config.StaticTokenAuth{
				Token: "change-me-to-your-secret",
			},
		}
		cfg.AdminToken = "admin-secret"
		cfg.Servers = []config.ServerConfig{
			{ID: "local", Name: "Local Hermes", URL: "http://localhost:3000", Enabled: true, Profile: "default"},
			{ID: "remote", Name: "Remote Hermes", URL: "http://10.0.0.1:3000", Enabled: true, Profile: "default"},
		}
		if err := config.SaveConfig(cfg, *configPath); err != nil {
			log.Fatalf("Failed to save config: %v", err)
		}
		fmt.Printf("Sample config written to %s\n", *configPath)
		return
	}

	cfg, err := config.LoadConfig(*configPath)
	if err != nil {
		log.Printf("Warning: using defaults, config load error: %v", err)
		cfg = config.DefaultConfig()
	}

	if err := cfg.Validate(); err != nil {
		log.Fatalf("Config validation failed: %v", err)
	}

	// Start admin server if address provided
	if *adminAddr != "" {
		adminServer := admin.NewServer(cfg, *adminAddr)
		go func() {
			if err := adminServer.Run(); err != nil {
				log.Printf("Admin server error: %v", err)
			}
		}()
	}

	proxyServer := proxy.NewServer(cfg)

	// Handle graceful shutdown
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sigCh
		log.Println("[proxy] Shutting down...")
		os.Exit(0)
	}()

	log.Printf("[proxy] Hermes Proxy starting...")
	log.Printf("[proxy] Auth method: %s", cfg.Auth.Method)
	if *adminAddr != "" {
		log.Printf("[proxy] Admin UI: http://localhost%s", *adminAddr)
	}
	log.Printf("[proxy] Servers configured: %d", len(cfg.Servers))
	for _, s := range cfg.Servers {
		log.Printf("  - %s (%s): %s [%s]", s.ID, s.Name, s.URL, enabledStr(s.Enabled))
	}

	if err := proxyServer.Run(); err != nil {
		log.Fatalf("Server error: %v", err)
	}
}

func enabledStr(b bool) string {
	if b {
		return "enabled"
	}
	return "disabled"
}
