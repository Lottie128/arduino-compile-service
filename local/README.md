# Run the compiler locally (fully offline)

For classrooms or users with no/poor internet: run the **same** compile server on
the local machine so the PWA can compile & flash with **zero cloud dependency**.
The PWA itself already works offline (service-worker cached); this fills in the
one piece that needed a server.

```
Browser PWA  ──►  http://localhost:3000  ──►  arduino-cli (local)  ──►  firmware
```

## Install & run

### Linux / macOS
```bash
bash local/install.sh        # installs arduino-cli + cores, then runs the server
bash local/install.sh --run  # later: just run it again
```

### Windows
```powershell
powershell -ExecutionPolicy Bypass -File local\install.ps1
powershell -ExecutionPolicy Bypass -File local\install.ps1 -RunOnly   # run again
```
> Windows works too: `arduino-cli` ships a native Windows build. The installer
> uses **winget** to add Python + arduino-cli. The compile server
> (`server/compile_server.py`) is the same on every OS.

After the first run (which downloads the toolchains) everything is **offline** —
no internet required to compile.

## Point the app at it

The deployed app talks to the cloud compiler by default. To use the local one,
the app's compile URL must be `http://localhost:3000`. Two ways:

1. **In-app override** (recommended) — set it once and it's remembered:
   ```js
   // run in the app's browser console, or via a "Local compiler" setting
   localStorage.setItem('compileUrl', 'http://localhost:3000')
   ```
   (Ask the maintainer to wire a "Use local compiler" toggle that reads this.)

2. **Self-host the PWA** for a truly offline lab: build the app with
   `VITE_COMPILE_URL=http://localhost:3000` (or `http://<lab-server>:3000`) and
   serve it on the LAN. Now both app and compiler are local.

## Browser support / the HTTPS→localhost rule

| Browser | HTTPS app → `http://localhost` compiler |
|---|---|
| Chrome / Edge | ✅ allowed (localhost is treated as a secure context) |
| Firefox | ✅ allowed |
| Safari | ⚠️ often blocked — use option 2 (self-host the PWA over http on the LAN) |

This is why the local server enables **CORS** (`CORS_ORIGIN=*`) and runs without a
token — it's bound to `127.0.0.1`, reachable only from the same machine.

## Lab tip
On a shared lab server, run the server bound to the LAN and point thin clients at
it: start with `HOST=0.0.0.0 PORT=3000 CORS_ORIGIN=* python3 server/compile_server.py`
and have each PWA use `http://<lab-server-ip>:3000`. One install serves the room.
