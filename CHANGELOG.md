# Changelog

## 2026-06-23

### Fixed
- **AVR (Arduino Uno / Nano) upload "Could not reach the bootloader".**
  ESP8266/ESP32 uploads worked but every AVR upload was refused. The compile
  server was correct (Intel HEX → raw binary; ESP raw `.bin`); the fault was in
  the **browser client's** Web Serial STK500v1 flasher.

  Root cause: the client read helper raced `reader.read()` against a timeout that
  abandoned the pending read. The next call issued a second, overlapping
  `read()`, so the bootloader's `STK_INSYNC / STK_OK` reply landed on the
  abandoned read and was silently discarded — the board was answering, the client
  never saw it.

  Fix (client `webserial.ts`):
  - Single background read pump → rolling buffer; protocol polls it (no
    overlapping `read()`).
  - Proper auto-reset pulse (assert DTR/RTS → release), tried as DTR+RTS and
    DTR-only (CH340-clone friendly).
  - Complete STK500v1 handshake: `ENTER_PROGMODE` → per-page `LOAD_ADDRESS` +
    `PROG_PAGE` (each acked) → `LEAVE_PROGMODE`; serial monitor always restored.

  See the README "Troubleshooting" section. No server changes were required.
