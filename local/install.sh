#!/usr/bin/env bash
#
# install.sh — set up the Arduino/ESP compile server LOCALLY for fully-offline
# use on Linux or macOS. Installs arduino-cli + board cores, then runs the
# compile server on http://localhost:3000 with CORS enabled so a browser PWA
# can call it.
#
#   bash install.sh           # install + run
#   bash install.sh --run     # just run (skip install)
#
# No sudo, no Docker, no internet needed after the first install.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER="$SCRIPT_DIR/../server/compile_server.py"
BINDIR="${BINDIR:-$HOME/.local/bin}"
export PATH="$BINDIR:$PATH"

log() { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }

install_all() {
  command -v python3 >/dev/null || {
    echo "Python 3 is required. macOS: 'brew install python'. Linux: 'sudo apt install python3'."
    exit 1
  }

  if ! command -v arduino-cli >/dev/null; then
    log "Installing arduino-cli into $BINDIR"
    mkdir -p "$BINDIR"
    curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh \
      | BINDIR="$BINDIR" sh
  fi
  arduino-cli version

  log "Installing board cores (AVR + ESP8266 + ESP32) — first run downloads a lot"
  arduino-cli config init --overwrite >/dev/null
  arduino-cli config add board_manager.additional_urls \
    https://arduino.esp8266.com/stable/package_esp8266com_index.json \
    https://espressif.github.io/arduino-esp32/package_esp32_index.json
  arduino-cli core update-index
  arduino-cli core install arduino:avr
  arduino-cli core install esp8266:esp8266
  arduino-cli core install esp32:esp32
  for lib in "Servo" "DHT sensor library" "LiquidCrystal I2C" "Adafruit NeoPixel"; do
    arduino-cli lib install "$lib" || true
  done

  log "Warming build caches"
  WARM="$(mktemp -d)/sketch"; mkdir -p "$WARM"
  printf 'void setup(){}\nvoid loop(){}\n' > "$WARM/sketch.ino"
  for fqbn in arduino:avr:uno esp8266:esp8266:nodemcuv2 esp32:esp32:esp32; do
    arduino-cli compile --fqbn "$fqbn" "$WARM" >/dev/null 2>&1 || true
  done
}

run_server() {
  log "Starting local compiler on http://localhost:3000"
  echo "Leave this window open. Point the app's compiler URL at http://localhost:3000."
  echo "Press Ctrl+C to stop."
  # No token locally; CORS open so the browser PWA can reach it.
  COMPILE_TOKEN="" CORS_ORIGIN="*" HOST="127.0.0.1" PORT="3000" \
    python3 "$SERVER"
}

[ "${1:-}" = "--run" ] || install_all
run_server
