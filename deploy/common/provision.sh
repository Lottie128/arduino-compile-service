#!/usr/bin/env bash
#
# provision.sh — cloud-agnostic native setup of the Arduino compile service on a
# fresh Ubuntu/Debian VM. Installs swap, arduino-cli + board cores, the systemd
# service, and Caddy (automatic HTTPS). Idempotent: safe to re-run.
#
# Usage (run on the VM, as a sudo-capable user):
#   sudo COMPILE_TOKEN=xxxx DOMAIN=compile.example.com bash provision.sh
#
# Required:
#   COMPILE_TOKEN   shared secret the web app sends on every /compile
#   DOMAIN          public hostname pointing at this VM (for the TLS cert).
#                   No domain? Use sslip.io: <dash-ip>.sslip.io
#
# Optional:
#   SWAP_GB         swapfile size in GB (default 4; set 0 to skip)
#   SERVICE_USER    user to run the service as (default: the invoking sudo user)
#
# Reminder: open ports 80 + 443 at the CLOUD network layer too (Security
# List / Security Group / NSG) — the OS firewall is only half of it.
set -euo pipefail

COMPILE_TOKEN="${COMPILE_TOKEN:?Set COMPILE_TOKEN (e.g. \$(openssl rand -hex 24))}"
DOMAIN="${DOMAIN:?Set DOMAIN (public hostname or <dash-ip>.sslip.io)}"
SWAP_GB="${SWAP_GB:-4}"
SERVICE_USER="${SERVICE_USER:-${SUDO_USER:-$(id -un)}}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

log() { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }

# ── 1. Swap (ESP32 link steps spike RAM; protects small/1GB boxes) ────────────
if [ "$SWAP_GB" -gt 0 ] && ! grep -q '/swapfile' /etc/fstab; then
  log "Creating ${SWAP_GB}G swapfile"
  fallocate -l "${SWAP_GB}G" /swapfile
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# ── 2. Base packages + arduino-cli ────────────────────────────────────────────
log "Installing base packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl python3 ca-certificates gnupg debian-keyring debian-archive-keyring apt-transport-https

if ! command -v arduino-cli >/dev/null; then
  log "Installing arduino-cli"
  curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh \
    | BINDIR=/usr/local/bin sh
fi

# ── 3. Board cores + libraries (as the service user, so caches are reused) ─────
log "Installing board cores (AVR + ESP8266 + ESP32) — first run downloads a lot"
run_cli() { sudo -u "$SERVICE_USER" arduino-cli "$@"; }
run_cli config init --overwrite
run_cli config add board_manager.additional_urls \
  https://arduino.esp8266.com/stable/package_esp8266com_index.json \
  https://espressif.github.io/arduino-esp32/package_esp32_index.json
run_cli core update-index
run_cli core install arduino:avr
run_cli core install esp8266:esp8266
run_cli core install esp32:esp32
for lib in "Servo" "DHT sensor library" "LiquidCrystal I2C" "Adafruit NeoPixel"; do
  run_cli lib install "$lib" || true
done

# ── 4. Warm the build cache so the first real compile is fast ──────────────────
log "Warming build caches"
WARM="$(sudo -u "$SERVICE_USER" mktemp -d)/sketch"
sudo -u "$SERVICE_USER" mkdir -p "$WARM"
printf 'void setup(){}\nvoid loop(){}\n' | sudo -u "$SERVICE_USER" tee "$WARM/sketch.ino" >/dev/null
for fqbn in arduino:avr:uno esp8266:esp8266:nodemcuv2 esp32:esp32:esp32; do
  run_cli compile --fqbn "$fqbn" "$WARM" >/dev/null 2>&1 || true
done

# ── 5. Install the compile server + systemd unit ──────────────────────────────
log "Installing compile server"
install -d /opt/compiler
install -m 0644 "$REPO_ROOT/server/compile_server.py" /opt/compiler/compile_server.py

cat >/etc/systemd/system/compiler.service <<UNIT
[Unit]
Description=Arduino/ESP compile server
After=network.target

[Service]
User=${SERVICE_USER}
Environment=COMPILE_TOKEN=${COMPILE_TOKEN}
Environment=PORT=3000
Environment=HOST=127.0.0.1
ExecStart=/usr/bin/python3 /opt/compiler/compile_server.py
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now compiler.service

# ── 6. Caddy (automatic HTTPS reverse proxy) ──────────────────────────────────
if ! command -v caddy >/dev/null; then
  log "Installing Caddy"
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
  apt-get update -qq
  apt-get install -y -qq caddy
fi

log "Configuring Caddy for ${DOMAIN}"
cat >/etc/caddy/Caddyfile <<CADDY
${DOMAIN} {
	@options method OPTIONS
	respond @options 204
	header {
		Access-Control-Allow-Origin "*"
		Access-Control-Allow-Methods "POST, GET, OPTIONS"
		Access-Control-Allow-Headers "Content-Type"
		-Server
	}
	reverse_proxy 127.0.0.1:3000
}
CADDY
systemctl restart caddy

# ── 7. OS firewall (cloud network layer must also allow 80/443) ───────────────
log "Opening OS firewall for 80/443"
iptables -C INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport 80 -j ACCEPT
iptables -C INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport 443 -j ACCEPT
if command -v netfilter-persistent >/dev/null; then netfilter-persistent save || true; fi

log "Done"
cat <<DONE

Service:  systemctl status compiler caddy
Endpoint: https://${DOMAIN}/health   (cert issues once 80/443 are reachable)
Test:     curl -s https://${DOMAIN}/health

If HTTPS times out: open TCP 80 + 443 in your cloud's network firewall
(Oracle VCN Security List / AWS Security Group / Azure NSG).
DONE
