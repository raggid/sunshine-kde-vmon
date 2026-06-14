# headless mode

Runs a completely separate headless Wayland compositor (labwc) as a persistent systemd service. Sunshine captures from labwc's `HEADLESS-1` output. The physical KDE session is never touched — each side has fully independent windows, panels, virtual desktops, and launched apps.

Requires: `labwc`, `wlr-randr`, Sunshine with `capture = wlr` and `output_name = HEADLESS-1`.

> **NVIDIA note:** On NVIDIA with wlroots 0.19+, `wlr-screencopy` returns SHM (CPU) frames instead of DMA-BUF. Capture works but the CPU-side copy adds latency. NVENC encoding itself stays hardware-accelerated.

## Scripts

| Script | Role |
|--------|------|
| `sunshine-labwc-common.sh` | Shared library — source this, do not run directly |
| `sunshine-labwc-service.sh` | Persistent systemd service: starts labwc, detects its socket, creates the stable `wayland-stream` symlink, launches plasmashell inside the compositor |
| `sunshine-start-labwc.sh` | prep-cmd `do`: sets labwc output to client resolution via `wlr-randr`, starts input relay |
| `sunshine-stop-labwc.sh` | prep-cmd `undo`: resets labwc output to idle resolution, stops input relay |
| `sunshine-labwc-run.sh` | Command wrapper for apps: sources the labwc env file so apps run inside the stream compositor, not on KDE |
| `sunshine-steam-bigpicture.sh` | Detached command: kills any running Steam and starts it in Big Picture mode inside labwc |
| `sunshine-labwc-input-relay.py` | Python service: relays Sunshine's uinput mouse/keyboard events into the labwc compositor |
| `sunshine-labwc-recover.sh` | Recovery: restarts `sunshine-labwc.service` |

## How the socket handoff works

labwc auto-picks the next available `wayland-N` socket. The service:
1. Snapshots existing sockets before starting labwc
2. Polls until a new socket appears (50 ms interval, 15 s timeout)
3. Creates a stable symlink: `$XDG_RUNTIME_DIR/wayland-stream → wayland-N`
4. Writes state files to `$XDG_RUNTIME_DIR/sunshine-labwc/`

Sunshine connects through `WAYLAND_DISPLAY=wayland-stream` (set via a drop-in), so it always finds the compositor regardless of which `wayland-N` labwc chose.

## App environment

Use `sunshine-labwc-run.sh` as a command prefix in `apps.json` or Sunshine's web UI to route apps into labwc instead of KDE:

```bash
/path/to/headless/sunshine-labwc-run.sh steam
/path/to/headless/sunshine-labwc-run.sh %command%   # Steam launch option
```

The env file written at service start is at `$XDG_RUNTIME_DIR/sunshine-labwc/labwc.env`.

## Required sunshine.conf settings

```
capture = wlr          # kwin uses KDE-only protocols; labwc needs wlr-screencopy
output_name = HEADLESS-1
```

## Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `SUNSHINE_LABWC_SOCKET` | `wayland-stream` | Stable symlink name for the labwc socket |
| `SUNSHINE_LABWC_OUTPUT` | `HEADLESS-1` | labwc output name |
| `SUNSHINE_LABWC_IDLE_WIDTH/HEIGHT/FPS` | `1920/1080/60` | Resolution when no client is connected |

## Recovery

```bash
./sunshine-labwc-recover.sh
# or
systemctl --user restart sunshine-labwc.service
```
