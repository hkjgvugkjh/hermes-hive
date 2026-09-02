# hermes-proxy

WebSocket proxy server between hermes-hive and multiple Hermes Studio instances.

## Architecture

```
hermes-hive  <--WebSocket(X25519+ChaCha20)-->  hermes-proxy  <--HTTP-->  Hermes Studio × N
```

## Features

- **X25519 Key Exchange**: ECDH key agreement between hive and proxy
- **ChaCha20-Poly1305 Encryption**: All traffic encrypted with AEAD
- **Multi-server routing**: Proxy forwards requests to different Hermes Studio instances
- **WebSocket multiplex**: Single connection, multiple server endpoints
- **JSON config**: Simple configuration file

## Build

```bash
cd hermes-proxy
go build -o hermes-proxy ./cmd
```

## Usage

1. Generate sample config:
```bash
./hermes-proxy -gen-config -config config.json
```

2. Edit `config.json` to add your Hermes Studio servers

3. Run the proxy:
```bash
./hermes-proxy -config config.json
```

## Config format

```json
{
  "listen": ":8080",
  "ws_path": "/ws",
  "auth_token": "optional-shared-secret",
  "log_level": "info",
  "servers": [
    {"id": "local", "name": "Local", "url": "http://localhost:3000", "enabled": true},
    {"id": "remote", "name": "Remote", "url": "http://10.0.0.1:3000", "enabled": true}
  ]
}
```

## Protocol

### Handshake

1. Client sends: `{"public_key": "<base64 X25519 pubkey>", "token": "..."}`
2. Server responds: `{"public_key": "<base64 X25519 pubkey>"}`
3. Both sides derive shared secret: `SHA-256(X25519(priv, peer_pub))`

### Frame format (post-handshake)

```
[1 byte: type] [4 bytes: length (BE)] [payload: ChaCha20-Poly1305 encrypted]
```

### Message types

| Type | Value | Description |
|------|-------|-------------|
| Handshake | 0x01 | Key exchange |
| Handshake OK | 0x02 | Handshake ack |
| HTTP Request | 0x10 | Encrypted HTTP request |
| HTTP Response | 0x11 | Encrypted HTTP response |
| Error | 0xFF | Error notification |

### Encrypted payload (JSON)

Request:
```json
{"request_id": "req_0", "server_id": "local", "method": "GET", "path": "/health", "headers": {}, "body": null}
```

Response:
```json
{"request_id": "req_0", "status_code": 200, "headers": {}, "body": "..."}
```
