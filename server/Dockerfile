# Arduino/ESP compile server with all board cores baked into the image.
# Build once, run anywhere — the slow core install happens at build time, not
# per request. Works on amd64 and arm64.
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    ARDUINO_DIRECTORIES_DATA=/arduino \
    ARDUINO_DIRECTORIES_DOWNLOADS=/arduino/staging \
    ARDUINO_DIRECTORIES_USER=/arduino/user

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl python3 \
    && rm -rf /var/lib/apt/lists/*

# arduino-cli
RUN curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh \
      | BINDIR=/usr/local/bin sh

# Board cores: AVR (default index) + ESP8266 + ESP32 (3rd-party indexes)
RUN arduino-cli config init --overwrite \
    && arduino-cli config add board_manager.additional_urls \
         https://arduino.esp8266.com/stable/package_esp8266com_index.json \
         https://espressif.github.io/arduino-esp32/package_esp32_index.json \
    && arduino-cli core update-index \
    && arduino-cli core install arduino:avr \
    && arduino-cli core install esp8266:esp8266 \
    && arduino-cli core install esp32:esp32

# Common libraries
RUN arduino-cli lib install "Servo" "DHT sensor library" "LiquidCrystal I2C" "Adafruit NeoPixel"

# Warm the build cache for each board so the first real request is fast
RUN mkdir -p /tmp/warm/sketch \
    && printf 'void setup(){}\nvoid loop(){}\n' > /tmp/warm/sketch/sketch.ino \
    && arduino-cli compile --fqbn arduino:avr:uno /tmp/warm/sketch || true \
    && arduino-cli compile --fqbn esp8266:esp8266:nodemcuv2 /tmp/warm/sketch || true \
    && arduino-cli compile --fqbn esp32:esp32:esp32 /tmp/warm/sketch || true \
    && rm -rf /tmp/warm

COPY compile_server.py /opt/compile_server.py

ENV HOST=0.0.0.0 PORT=3000
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD curl -fsS http://127.0.0.1:3000/health || exit 1
CMD ["python3", "/opt/compile_server.py"]
