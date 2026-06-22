# Contributing

Contributions welcome — issues and PRs alike.

## Ground rules
- Keep `server/compile_server.py` **dependency-free** (Python stdlib only).
- Bash scripts must pass `shellcheck` (`-e SC1091` allowed for sourced files).
- Per-cloud scripts must use only that cloud's official CLI and assume nothing
  beyond a fresh account + a configured CLI.
- Don't commit secrets (`.env`, `*.pem`, `*.key` are git-ignored).

## Local checks before a PR
```bash
shellcheck $(git ls-files '*.sh')
python3 -m py_compile server/compile_server.py
docker compose config -q
```

## Adding a board
1. Add the `board → FQBN` entry in `server/compile_server.py`.
2. Add the core install to `server/Dockerfile` and `deploy/common/provision.sh`.
3. Note any pin-constant quirks in the README (e.g. ESP8266 needs the `nodemcuv2`
   variant for `D0–D8`; the bare ESP32 board has no `LED_BUILTIN`).
