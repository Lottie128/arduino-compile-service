# compile_server.py

A single-file, dependency-free (Python stdlib) HTTP compile server. Spawns
`arduino-cli` per request, returns ready-to-flash firmware as base64.

## Run locally
```bash
# needs arduino-cli + cores on PATH (see ../deploy/common/provision.sh or the Dockerfile)
COMPILE_TOKEN=dev PORT=3000 python3 compile_server.py
curl -s localhost:3000/health
curl -s -X POST localhost:3000/compile -H 'Content-Type: application/json' \
  -d '{"token":"dev","board":"uno","code":"void setup(){}\nvoid loop(){}"}'
```

## Environment
| Var | Default | Purpose |
|---|---|---|
| `COMPILE_TOKEN` | `""` | shared secret for `/compile` (empty disables auth) |
| `HOST` | `127.0.0.1` | bind address (`0.0.0.0` in Docker) |
| `PORT` | `3000` | listen port |
| `RATE_MAX` / `RATE_WINDOW` | `20` / `60` | per-IP rate limit |
| `MAX_CONCURRENT` | `2` | simultaneous compiles |
| `COMPILE_TIMEOUT` | `280` | per-compile timeout (s) |

## Design notes
- **stdlib only** → trivial to audit, no supply chain, runs anywhere with Python 3.
- **AVR HEX is parsed to a raw binary** server-side, so the client gets flashable
  bytes for every board (ESP returns its `.bin` directly).
- **ThreadingHTTPServer** + a `BoundedSemaphore` gives concurrency without letting
  parallel ESP32 link steps exhaust RAM on a 1 GB box.
- Always sit it **behind Caddy/TLS** in production; bind to `127.0.0.1` natively.
