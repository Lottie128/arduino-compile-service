# install.ps1 — set up the Arduino/ESP compile server LOCALLY on Windows for
# fully-offline use. Installs arduino-cli + Python (via winget if needed) + the
# board cores, then runs the compile server on http://localhost:3000 with CORS
# so a browser PWA can call it.
#
#   Right-click > Run with PowerShell, or:
#     powershell -ExecutionPolicy Bypass -File install.ps1
#     powershell -ExecutionPolicy Bypass -File install.ps1 -RunOnly
#
# No admin needed if winget installs to the user scope.
param([switch]$RunOnly)
$ErrorActionPreference = "Stop"
$server = Join-Path $PSScriptRoot "..\server\compile_server.py"

function Have($cmd) { return [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

function Install-All {
  if (-not (Have python)) {
    Write-Host "== Installing Python (winget) =="
    winget install -e --id Python.Python.3.12 --accept-source-agreements --accept-package-agreements
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","User") + ";" + $env:Path
  }
  if (-not (Have arduino-cli)) {
    Write-Host "== Installing arduino-cli (winget) =="
    winget install -e --id ArduinoSA.CLI --accept-source-agreements --accept-package-agreements
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","User") + ";" + $env:Path
  }
  arduino-cli version

  Write-Host "== Installing board cores (AVR + ESP8266 + ESP32) — first run downloads a lot =="
  arduino-cli config init --overwrite | Out-Null
  arduino-cli config add board_manager.additional_urls `
    https://arduino.esp8266.com/stable/package_esp8266com_index.json `
    https://espressif.github.io/arduino-esp32/package_esp32_index.json
  arduino-cli core update-index
  arduino-cli core install arduino:avr
  arduino-cli core install esp8266:esp8266
  arduino-cli core install esp32:esp32
  foreach ($lib in @("Servo","DHT sensor library","LiquidCrystal I2C","Adafruit NeoPixel")) {
    arduino-cli lib install "$lib"
  }

  Write-Host "== Warming build caches =="
  $warm = Join-Path ([System.IO.Path]::GetTempPath()) ("warm_" + [guid]::NewGuid())
  New-Item -ItemType Directory -Path "$warm\sketch" | Out-Null
  "void setup(){}`nvoid loop(){}" | Out-File -Encoding ascii "$warm\sketch\sketch.ino"
  foreach ($fqbn in @("arduino:avr:uno","esp8266:esp8266:nodemcuv2","esp32:esp32:esp32")) {
    arduino-cli compile --fqbn $fqbn "$warm\sketch" 2>$null | Out-Null
  }
}

function Run-Server {
  Write-Host "`n== Starting local compiler on http://localhost:3000 ==" -ForegroundColor Cyan
  Write-Host "Leave this window open. Point the app's compiler URL at http://localhost:3000."
  Write-Host "Press Ctrl+C to stop."
  $env:COMPILE_TOKEN = ""
  $env:CORS_ORIGIN = "*"
  $env:HOST = "127.0.0.1"
  $env:PORT = "3000"
  python $server
}

if (-not $RunOnly) { Install-All }
Run-Server
