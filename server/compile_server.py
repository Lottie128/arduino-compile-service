#!/usr/bin/env python3
"""Arduino / ESP compile server — Python standard library only (no pip deps).

POST /compile  {"code": "...", "board": "uno|esp32|esp8266", "token": "..."}
  -> 200 {"status":"done","format":"hex|bin","data":"<base64 firmware>"}
  -> 4xx/5xx {"status":"error","message":"..."}
GET  /health   -> 200 {"ok":true}

Configuration (environment variables):
  COMPILE_TOKEN    shared secret required on /compile (empty = no auth)
  PORT             listen port (default 3000, bound to 127.0.0.1)
  RATE_MAX         max requests per IP per window (default 20)
  RATE_WINDOW      rate-limit window in seconds (default 60)
  MAX_CONCURRENT   simultaneous compiles (default 2 — protects small boxes)
  COMPILE_TIMEOUT  per-compile subprocess timeout in seconds (default 280)
  BUILD_CACHE_DIR  persistent --build-path root, one dir per (board, slot)
                   (default /tmp/arduino-build-cache). Only the board's core
                   and library objects get reused across requests — each
                   request's own sketch.ino always lives in a fresh temp dir,
                   so it always recompiles; this just skips rebuilding the
                   (identical, much bigger) core every single time.
"""
import base64
import glob
import json
import os
import queue
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# ── Configuration ────────────────────────────────────────────────────────────
TOKEN = os.environ.get("COMPILE_TOKEN", "")
PORT = int(os.environ.get("PORT", "3000"))
RATE_MAX = int(os.environ.get("RATE_MAX", "20"))
RATE_WINDOW = int(os.environ.get("RATE_WINDOW", "60"))
MAX_CONCURRENT = int(os.environ.get("MAX_CONCURRENT", "2"))
COMPILE_TIMEOUT = int(os.environ.get("COMPILE_TIMEOUT", "280"))
BUILD_CACHE_DIR = os.environ.get("BUILD_CACHE_DIR", "/tmp/arduino-build-cache")
MAX_CODE = 256 * 1024
# CORS: leave empty in the cloud (Caddy adds CORS). For the local/offline server
# there's no proxy, so set CORS_ORIGIN (e.g. "*") to let the browser PWA call it.
CORS_ORIGIN = os.environ.get("CORS_ORIGIN", "")

# Board alias -> fully-qualified board name. esp8266 uses the NodeMCU variant so
# the D0–D8 / LED_BUILTIN constants resolve; the bare esp32 board uses raw GPIO.
FQBN = {
    "uno": "arduino:avr:uno",
    "esp32": "esp32:esp32:esp32",
    "esp8266": "esp8266:esp8266:nodemcuv2",
}

# ── Abuse protection ─────────────────────────────────────────────────────────
# A pool of MAX_CONCURRENT numbered slots, not a bare semaphore: each slot also
# owns a persistent build-cache directory (see BUILD_CACHE_DIR above), so the
# same slot's core/library objects survive across requests instead of being
# rebuilt from scratch on every compile.
_slots = queue.Queue()
for _i in range(MAX_CONCURRENT):
    _slots.put(_i)
_hits = {}
_hits_lock = threading.Lock()


def _client_ip(handler):
    """Real client IP — Caddy/most proxies set X-Forwarded-For."""
    xff = handler.headers.get("X-Forwarded-For", "")
    return xff.split(",")[0].strip() if xff else handler.client_address[0]


def _rate_ok(ip):
    """Sliding-window per-IP rate limiter."""
    now = time.time()
    with _hits_lock:
        q = [t for t in _hits.get(ip, []) if now - t < RATE_WINDOW]
        if len(q) >= RATE_MAX:
            _hits[ip] = q
            return False
        q.append(now)
        _hits[ip] = q
        if len(_hits) > 1000:  # opportunistic cleanup
            for k in [k for k, v in _hits.items() if all(now - t >= RATE_WINDOW for t in v)]:
                _hits.pop(k, None)
        return True


def parse_intel_hex(text):
    """Intel HEX (AVR) -> raw binary image, gaps filled with 0xFF (erased flash)."""
    data = {}
    base = 0
    for line in text.splitlines():
        line = line.strip()
        if not line.startswith(":"):
            continue
        ln = int(line[1:3], 16)
        addr = int(line[3:7], 16)
        typ = int(line[7:9], 16)
        if typ == 1:               # EOF
            break
        if typ == 4:               # extended linear address
            base = int(line[9:13], 16) << 16
            continue
        if typ == 0:               # data
            for i in range(ln):
                data[base + addr + i] = int(line[9 + i * 2:11 + i * 2], 16)
    if not data:
        return b""
    out = bytearray(max(data) + 1)
    for i in range(len(out)):
        out[i] = data.get(i, 0xFF)
    return bytes(out)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _cors(self):
        if CORS_ORIGIN:
            self.send_header("Access-Control-Allow-Origin", CORS_ORIGIN)
            self.send_header("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "Content-Type")

    def _send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self._cors()
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass  # quiet by default

    def do_OPTIONS(self):
        # CORS preflight (only relevant when CORS_ORIGIN is set / local mode)
        self.send_response(204)
        self._cors()
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):
        if self.path == "/health":
            return self._send(200, {"ok": True})
        return self._send(404, {"status": "error", "message": "not found"})

    def do_POST(self):
        if self.path != "/compile":
            return self._send(404, {"status": "error", "message": "not found"})

        try:
            n = int(self.headers.get("Content-Length", 0))
            if n <= 0 or n > MAX_CODE:
                return self._send(413, {"status": "error", "message": "payload too large"})
            req = json.loads(self.rfile.read(n))
        except Exception:
            return self._send(400, {"status": "error", "message": "bad JSON"})

        if TOKEN and req.get("token") != TOKEN:
            return self._send(401, {"status": "error", "message": "unauthorized"})

        code = req.get("code") or ""
        fqbn = FQBN.get(req.get("board") or "uno")
        if not fqbn:
            return self._send(400, {"status": "error", "message": "unknown board"})
        if not code.strip():
            return self._send(400, {"status": "error", "message": "code is required"})

        if not _rate_ok(_client_ip(self)):
            return self._send(429, {"status": "error",
                                    "message": "Too many compiles — wait a minute and try again."})

        with tempfile.TemporaryDirectory() as d:
            sk = os.path.join(d, "sketch")
            os.makedirs(sk)
            with open(os.path.join(sk, "sketch.ino"), "w") as f:
                f.write(code)
            out = os.path.join(d, "build")

            try:
                slot = _slots.get(timeout=45)
            except queue.Empty:
                return self._send(429, {"status": "error",
                                        "message": "Compiler busy — try again in a moment."})
            try:
                build_path = os.path.join(BUILD_CACHE_DIR, req.get("board") or "uno", f"slot{slot}")
                os.makedirs(build_path, exist_ok=True)
                p = subprocess.run(
                    ["arduino-cli", "compile", "--fqbn", fqbn,
                     "--build-path", build_path, "--output-dir", out, sk],
                    capture_output=True, text=True, timeout=COMPILE_TIMEOUT,
                )
            except subprocess.TimeoutExpired:
                return self._send(504, {"status": "error", "message": "compile timed out"})
            finally:
                _slots.put(slot)

            if p.returncode != 0:
                msg = (p.stderr or p.stdout or "compile failed").strip()[-1500:]
                return self._send(200, {"status": "error", "message": msg})

            # AVR emits Intel HEX (parse to binary); ESP emits a raw .bin image.
            hexes = [h for h in glob.glob(out + "/*.hex") if "with_bootloader" not in h]
            if hexes:
                with open(hexes[0]) as f:
                    binary = parse_intel_hex(f.read())
                return self._send(200, {"status": "done", "format": "hex",
                                        "data": base64.b64encode(binary).decode()})
            bins = [b for b in glob.glob(out + "/*.bin")
                    if "bootloader" not in b and "partitions" not in b] or glob.glob(out + "/*.bin")
            if bins:
                with open(bins[0], "rb") as f:
                    return self._send(200, {"status": "done", "format": "bin",
                                            "data": base64.b64encode(f.read()).decode()})
            return self._send(200, {"status": "error", "message": "no firmware produced"})


if __name__ == "__main__":
    # Default to localhost (native install behind Caddy on the same host).
    # In Docker, set HOST=0.0.0.0 so the sibling Caddy container can reach it.
    host = os.environ.get("HOST", "127.0.0.1")
    ThreadingHTTPServer((host, PORT), Handler).serve_forever()
