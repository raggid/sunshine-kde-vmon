# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project does

Shell scripts for [Sunshine](https://github.com/LizardByte/Sunshine) game streaming on KDE Plasma (Wayland). Two independent streaming modes are provided:

- **vmon mode** (original): A virtual KDE monitor (`krfb-virtualmonitor`) lives in the same KDE Plasma session. Physical and stream desktops share the compositor; KDE can give each output its own panel and virtual-desktop stack.
- **labwc mode** (new): A completely separate headless Wayland compositor (labwc) runs as a persistent service. Sunshine is redirected to capture from labwc's `HEADLESS-1` output. The physical KDE session is **never touched** — each side has fully independent windows, panels, virtual desktops, and launched apps.

## Installation / service management

```bash
# Install both modes (asks interactively about each)
./install.sh

# Force-enable specific modes without interactive prompts
SUNSHINE_VMON_ENABLE_SERVICE=yes SUNSHINE_LABWC_ENABLE_SERVICE=no ./install.sh

# vmon mode lifecycle
systemctl --user start sunshine-vmon.service
systemctl --user status sunshine-vmon.service
systemctl --user restart sunshine-vmon.service

# labwc mode lifecycle
systemctl --user start sunshine-labwc.service
systemctl --user status sunshine-labwc.service
systemctl --user restart sunshine-labwc.service

# Inspect KDE monitor state (vmon mode)
kscreen-doctor -o

# Inspect labwc compositor outputs (labwc mode)
WAYLAND_DISPLAY=wayland-stream wlr-randr
```

## Architecture

The project has two independent modes, each with its own common library and script set.

### vmon mode

All shared logic lives in **`sunshine-vmon-common.sh`** — every other vmon script sources it.

| Script | Role |
|--------|------|
| `sunshine-vmon-service.sh` | Persistent systemd service: creates virtual monitor at login, keeps it alive, restores idle layout on exit |
| `sunshine-start-vmon.sh` | Stream start: enable virtual monitor, point Sunshine to it; physical stays on |
| `sunshine-stop-vmon.sh` | Stream stop: restore idle layout, point Sunshine back to physical |
| `sunshine-vmon-recover.sh` | Black-screen recovery: force all physical outputs on, disable virtual |

### labwc mode

Shared logic lives in **`sunshine-labwc-common.sh`**. No kscreen-doctor, no KDE interaction.

| Script | Role |
|--------|------|
| `sunshine-labwc-service.sh` | Persistent systemd service: starts labwc headless compositor, detects its socket, creates the stable `wayland-stream` symlink, waits on labwc |
| `sunshine-start-labwc.sh` | prep-cmd: set labwc output to client resolution via `wlr-randr --custom-mode`, update `sunshine.conf output_name` |
| `sunshine-stop-labwc.sh` | undo-cmd: reset labwc output to idle resolution |
| `sunshine-labwc-run.sh` | Wrapper for app commands: sources the labwc env file so apps run inside the stream compositor, not on KDE |
| `sunshine-labwc-recover.sh` | Recovery: `systemctl --user restart sunshine-labwc.service` |

### Key functions in `sunshine-vmon-common.sh`

- `import_plasma_session_env` — sets `XDG_RUNTIME_DIR`, `DBUS_SESSION_BUS_ADDRESS`, `WAYLAND_DISPLAY` when running outside the graphical session (TTY, systemd)
- `detect_primary_output_name` — uses `kscreen-doctor -j | python3` to find the connected, enabled physical output with priority 1; falls back to `DP-1`
- `apply_idle_layout` — canonical "stream ended" state: enable all physical outputs, disable virtual; used by service trap, stop scripts, and recover
- `abort_stream_layout` — EXIT trap used in start scripts; runs if prep-cmd fails partway through, restores layout and restarts Sunshine
- `set_sunshine_output` — writes `output_name = <value>` to `~/.config/sunshine/sunshine.conf` via `sed`; Sunshine re-reads this file at each new client connection, so no service restart is needed after changing it

### labwc mode: how the socket handoff works

labwc auto-picks the next available `wayland-N` socket. The service script:
1. Snapshots existing sockets before starting labwc
2. Polls until a new socket appears (50 ms interval, 15 s timeout)
3. Creates a stable symlink: `$XDG_RUNTIME_DIR/wayland-stream → wayland-N`
4. Writes state files to `$XDG_RUNTIME_DIR/sunshine-labwc/`

Sunshine is configured via a drop-in with `WAYLAND_DISPLAY=wayland-stream`, so it always connects through the stable symlink regardless of which `wayland-N` labwc chose. When labwc restarts (new socket number), the service updates the symlink.

### labwc mode: app environment

Apps launched by Sunshine need to run inside labwc, not KDE Plasma. Use `sunshine-labwc-run.sh` as the command prefix — it sources the env file written at service start and sets `WAYLAND_DISPLAY=wayland-stream` (and `DISPLAY` if Xwayland is running). For manual wiring, the env file is at `$XDG_RUNTIME_DIR/sunshine-labwc/labwc.env`.

### labwc mode: required sunshine.conf settings

`sunshine.conf` must have both of these for labwc capture to work:
```
capture = wlr          # kwin capture uses KDE-only protocols; labwc needs wlr-screencopy
output_name = HEADLESS-1
```
`capture = kwin` causes "Unable to initialize capture method" and falls through all encoders at startup. Sunshine still starts but cannot stream.

### labwc mode: NVIDIA caveat

On NVIDIA with wlroots 0.19+, `WLR_BACKENDS=headless` causes `wlr-screencopy` to return SHM (CPU) frames instead of DMA-BUF. Sunshine handles this via its software scaler path, so capture works but the CPU-side copy adds latency compared to DMA-BUF on AMD/Intel. NVENC encoding itself remains hardware-accelerated.

## Environment variables

### vmon mode

| Variable | Default | Purpose |
|----------|---------|---------|
| `SUNSHINE_PRIMARY_OUTPUT` | _(auto)_ | Force a specific physical connector (e.g. `DP-1`) |
| `SUNSHINE_CLIENT_WIDTH/HEIGHT/FPS` | `1920/1080/60` | Set by Sunshine at stream start |
| `SUNSHINE_VMON_WIDTH/HEIGHT/FPS` | `1920/1080/60` | Resolution for the persistent idle service |
| `SUNSHINE_VMON_NAME` | `sunshine-vmon` | Name passed to `krfb-virtualmonitor --name` |
| `SUNSHINE_VMON_PORT` | `5905` | krfb VNC port |
| `SUNSHINE_VMON_PASSWORD` | `sunshinepass` | krfb VNC password |

Override service defaults via a drop-in:
```
~/.config/systemd/user/sunshine-vmon.service.d/override.conf
[Service]
Environment=SUNSHINE_VMON_WIDTH=2560
Environment=SUNSHINE_VMON_HEIGHT=1440
```

### labwc mode

| Variable | Default | Purpose |
|----------|---------|---------|
| `SUNSHINE_LABWC_SOCKET` | `wayland-stream` | Stable symlink name for the labwc socket |
| `SUNSHINE_LABWC_OUTPUT` | `HEADLESS-1` | labwc output name (wlroots headless backend always uses this) |
| `SUNSHINE_LABWC_IDLE_WIDTH/HEIGHT/FPS` | `1920/1080/60` | Idle resolution when no client is connected |

labwc desktop configuration lives in `~/.config/labwc-stream/rc.xml` and `menu.xml` (created by the service on first run; edit freely).

## Sunshine `apps.json` integration

Sunshine prep-cmd `do`/`undo` must use **absolute paths**. The `env` key is required in `apps.json` or apps won't appear in Moonlight. See `examples/apps.json` for all profiles; replace `/home/USER/` with the actual home path.

For the labwc profiles, `sunshine-labwc-run.sh` is the command wrapper that routes apps into the stream compositor. The prep-cmd `do`/`undo` only handles resolution; app routing is separate.

## Recovery from black screen (vmon mode)

Run as the **same user as the graphical session** (not root):

```bash
./sunshine-vmon-recover.sh
```

From a root TTY:
```bash
sudo -u <user> \
  XDG_RUNTIME_DIR=/run/user/1000 \
  WAYLAND_DISPLAY=wayland-0 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
  ./sunshine-vmon-recover.sh
```

## Recovery (labwc mode)

No physical display state to restore. Just restart the compositor:

```bash
./sunshine-labwc-recover.sh
# or
systemctl --user restart sunshine-labwc.service
```
