# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project does

Shell scripts for [Sunshine](https://github.com/LizardByte/Sunshine) game streaming on KDE Plasma (Wayland). Three independent streaming modes are provided:

- **vmon-simple mode** (recommended): A virtual KDE monitor is created on-demand at stream start at the client's exact resolution, then destroyed on stop. A lightweight sentinel service keeps a dummy virtual output permanently connected so Sunshine never sees "zero outputs". Requires `capture = kwin`.
- **vmon mode** (original): A virtual KDE monitor lives persistently in the KDE session (created at login via a systemd service). The stream resolution is fixed to the service's configured resolution — it cannot adapt per client. Works without a physical monitor. Requires `capture = kwin`.
- **headless mode**: A completely separate headless Wayland compositor (labwc) runs as a persistent service. Sunshine is redirected to capture from labwc's `HEADLESS-1` output. The physical KDE session is **never touched** — each side has fully independent windows, panels, virtual desktops, and launched apps. Requires `capture = wlr`.

## Installation / service management

```bash
# Install (asks interactively which mode to enable)
./install.sh

# Force-enable specific modes without interactive prompts
SUNSHINE_VMON_MODE=simple SUNSHINE_LABWC_ENABLE_SERVICE=no ./install.sh
SUNSHINE_VMON_MODE=service SUNSHINE_LABWC_ENABLE_SERVICE=no ./install.sh
SUNSHINE_VMON_MODE=none SUNSHINE_LABWC_ENABLE_SERVICE=yes ./install.sh

# vmon-simple mode lifecycle
systemctl --user start sunshine-sentinel.service
systemctl --user status sunshine-sentinel.service
systemctl --user restart sunshine-sentinel.service

# vmon mode lifecycle
systemctl --user start sunshine-vmon.service
systemctl --user status sunshine-vmon.service
systemctl --user restart sunshine-vmon.service

# headless mode lifecycle
systemctl --user start sunshine-labwc.service
systemctl --user status sunshine-labwc.service
systemctl --user restart sunshine-labwc.service

# Inspect KDE monitor state (vmon modes)
kscreen-doctor -o

# Inspect labwc compositor outputs (headless mode)
WAYLAND_DISPLAY=wayland-stream wlr-randr
```

## Repository structure

```
vmon-simple/ — vmon-simple mode: on-demand vmon + sentinel service
vmon/        — vmon mode: persistent service-based virtual monitor
headless/    — headless (labwc) mode scripts and shared library
systemd/     — reference systemd unit and drop-in files
examples/    — example apps.json for Sunshine
install.sh   — installs chosen mode(s), systemd units, and drop-ins
```

## Architecture

### vmon-simple mode (`vmon-simple/`)

All vmon logic is shared from **`vmon/sunshine-vmon-common.sh`**. The simple scripts source it directly.

| Script | Role |
|--------|------|
| `sentinel-service.sh` | Persistent systemd service: creates `Virtual-sunshine-idle` at login, keeps it disabled. Ensures Sunshine always sees at least one connected output. |
| `start-desktop.sh` | prep-cmd `do`: kills any leftover krfb, creates `Virtual-sunshine-vmon` at client resolution, enables it alongside the physical monitor |
| `start-exclusive.sh` | prep-cmd `do` (exclusive): same as above but disables the physical monitor |
| `stop.sh` | prep-cmd `undo`: restores idle layout, kills the stream krfb (sentinel krfb stays alive) |

**Why on-demand creation fixes per-client resolution:** with the sentinel running, `Virtual-sunshine-idle` exists but `Virtual-sunshine-vmon` does not. `sunshine.conf` has `output_name = Virtual-sunshine-vmon`. When a client connects, KWin cannot open a screencast for a non-existent output, so Sunshine runs the prep-cmd first. The prep-cmd creates `Virtual-sunshine-vmon` at the client's exact resolution, then Sunshine opens the screencast against it. No scaling, no mode-change race.

### vmon mode (`vmon/`)

All shared logic lives in **`vmon/sunshine-vmon-common.sh`** — every other vmon script sources it.

| Script | Role |
|--------|------|
| `sunshine-vmon-service.sh` | Persistent systemd service: creates virtual monitor at login, keeps it alive, restores idle layout on exit |
| `sunshine-start-vmon.sh` | prep-cmd `do`: enable virtual monitor alongside physical, point Sunshine at it |
| `sunshine-stop-vmon.sh` | prep-cmd `undo`: restore idle layout, point Sunshine back to physical |
| `sunshine-start-exclusive.sh` | prep-cmd `do` (exclusive variant): enable virtual monitor and disable all physical outputs |
| `sunshine-vmon-recover.sh` | Black-screen recovery: force all physical outputs on, disable virtual |

### headless mode (`headless/`)

Shared logic lives in **`headless/sunshine-labwc-common.sh`**. No kscreen-doctor, no KDE interaction.

| Script | Role |
|--------|------|
| `sunshine-labwc-service.sh` | Persistent systemd service: starts labwc headless compositor, detects its socket, creates the stable `wayland-stream` symlink, waits on labwc |
| `sunshine-start-labwc.sh` | prep-cmd `do`: set labwc output to client resolution via `wlr-randr --custom-mode`, update `sunshine.conf output_name` |
| `sunshine-stop-labwc.sh` | prep-cmd `undo`: reset labwc output to idle resolution |
| `sunshine-labwc-run.sh` | Wrapper for app commands: sources the labwc env file so apps run inside the stream compositor, not on KDE |
| `sunshine-steam-bigpicture.sh` | Detached command: kills running Steam and starts it in Big Picture mode inside labwc |
| `sunshine-labwc-recover.sh` | Recovery: `systemctl --user restart sunshine-labwc.service` |

### systemd drop-ins (`systemd/`)

| File | Purpose |
|------|---------|
| `sunshine-sentinel.service` | Reference unit for the vmon-simple sentinel |
| `sunshine-vmon.service` | Reference unit for the vmon persistent service |
| `sunshine-labwc.service` | Reference unit for the headless persistent service |
| `sunshine-vmon-override.conf` | Drop-in for `sunshine.service`: runs `sunshine-stop-vmon.sh` via `ExecStopPost` so physical monitors are restored even on Sunshine crash |
| `sunshine-labwc-sunshine-override.conf` | Drop-in for `sunshine.service`: sets `WAYLAND_DISPLAY=wayland-stream` so Sunshine captures from labwc |
| `sunshine.service.example` | Reference unit for Sunshine itself |

`install.sh` generates these drop-ins with real paths and installs them to `~/.config/systemd/user/sunshine.service.d/`.

### Key functions in `vmon/sunshine-vmon-common.sh`

- `import_plasma_session_env` — sets `XDG_RUNTIME_DIR`, `DBUS_SESSION_BUS_ADDRESS`, `WAYLAND_DISPLAY` when running outside the graphical session (TTY, systemd)
- `detect_primary_output_name` — uses `kscreen-doctor -j | python3` to find the connected, enabled physical output with priority 1; falls back to `DP-1`
- `apply_idle_layout` — canonical "stream ended" state: enable all physical outputs, disable virtual; used by service trap, stop scripts, and recover
- `abort_stream_layout` — EXIT trap used in start scripts; runs if prep-cmd fails partway through, restores layout
- `set_sunshine_output` — writes `output_name = <value>` to `~/.config/sunshine/sunshine.conf` via `sed`; Sunshine re-reads this file at each new client connection, so no service restart is needed after changing it

### headless mode: how the socket handoff works

labwc auto-picks the next available `wayland-N` socket. The service script:
1. Snapshots existing sockets before starting labwc
2. Polls until a new socket appears (50 ms interval, 15 s timeout)
3. Creates a stable symlink: `$XDG_RUNTIME_DIR/wayland-stream → wayland-N`
4. Writes state files to `$XDG_RUNTIME_DIR/sunshine-labwc/`

Sunshine is configured via a drop-in with `WAYLAND_DISPLAY=wayland-stream`, so it always connects through the stable symlink regardless of which `wayland-N` labwc chose. When labwc restarts (new socket number), the service updates the symlink.

### headless mode: app environment

Apps launched by Sunshine need to run inside labwc, not KDE Plasma. Use `headless/sunshine-labwc-run.sh` as the command prefix — it sources the env file written at service start and sets `WAYLAND_DISPLAY=wayland-stream` (and `DISPLAY` if Xwayland is running). For manual wiring, the env file is at `$XDG_RUNTIME_DIR/sunshine-labwc/labwc.env`.

### headless mode: required sunshine.conf settings

`sunshine.conf` must have both of these for labwc capture to work:
```
capture = wlr          # kwin capture uses KDE-only protocols; labwc needs wlr-screencopy
output_name = HEADLESS-1
```
`capture = kwin` causes "Unable to initialize capture method" and falls through all encoders at startup. Sunshine still starts but cannot stream.

### headless mode: NVIDIA caveat

On NVIDIA with wlroots 0.19+, `WLR_BACKENDS=headless` causes `wlr-screencopy` to return SHM (CPU) frames instead of DMA-BUF. Sunshine handles this via its software scaler path, so capture works but the CPU-side copy adds latency compared to DMA-BUF on AMD/Intel. NVENC encoding itself remains hardware-accelerated.

## Environment variables

### vmon-simple mode

| Variable | Default | Purpose |
|----------|---------|---------|
| `SUNSHINE_PRIMARY_OUTPUT` | _(auto)_ | Force a specific physical connector (e.g. `DP-1`) |
| `SUNSHINE_CLIENT_WIDTH/HEIGHT/FPS` | `1920/1080/60` | Set by Sunshine at stream start (used directly for vmon size) |
| `SUNSHINE_VMON_NAME` | `sunshine-vmon` | Name of the stream virtual monitor |
| `SUNSHINE_VMON_PORT` | `5905` | krfb VNC port |
| `SUNSHINE_VMON_PASSWORD` | `sunshinepass` | krfb VNC password |
| `SUNSHINE_SENTINEL_NAME` | `sunshine-idle` | Name of the sentinel virtual monitor |
| `SUNSHINE_SENTINEL_PORT` | `5906` | krfb VNC port for the sentinel |

### vmon mode

| Variable | Default | Purpose |
|----------|---------|---------|
| `SUNSHINE_PRIMARY_OUTPUT` | _(auto)_ | Force a specific physical connector (e.g. `DP-1`) |
| `SUNSHINE_CLIENT_WIDTH/HEIGHT/FPS` | `1920/1080/60` | Set by Sunshine at stream start |
| `SUNSHINE_VMON_WIDTH/HEIGHT/FPS` | `1920/1080/60` | Resolution for the persistent idle service |
| `SUNSHINE_VMON_NAME` | `sunshine-vmon` | Name passed to `krfb-virtualmonitor --name` |
| `SUNSHINE_VMON_PORT` | `5905` | krfb VNC port |
| `SUNSHINE_VMON_PASSWORD` | `sunshinepass` | krfb VNC password |

Override vmon service defaults via a drop-in:
```
~/.config/systemd/user/sunshine-vmon.service.d/override.conf
[Service]
Environment=SUNSHINE_VMON_WIDTH=2560
Environment=SUNSHINE_VMON_HEIGHT=1440
```

### headless mode

| Variable | Default | Purpose |
|----------|---------|---------|
| `SUNSHINE_LABWC_SOCKET` | `wayland-stream` | Stable symlink name for the labwc socket |
| `SUNSHINE_LABWC_OUTPUT` | `HEADLESS-1` | labwc output name (wlroots headless backend always uses this) |
| `SUNSHINE_LABWC_IDLE_WIDTH/HEIGHT/FPS` | `1920/1080/60` | Idle resolution when no client is connected |

labwc desktop configuration lives in `~/.config/labwc-stream/rc.xml` and `menu.xml` (created by the service on first run; edit freely).

## Sunshine `apps.json` integration

Sunshine prep-cmd `do`/`undo` must use **absolute paths**. The `env` key is required in `apps.json` or apps won't appear in Moonlight. See `examples/apps.json` for all profiles; replace `/home/USER/` with the actual home path.

For the headless profiles, `headless/sunshine-labwc-run.sh` is the command wrapper that routes apps into the stream compositor. The prep-cmd `do`/`undo` only handles resolution; app routing is separate.

Steam Big Picture (vmon) uses `steam://open/bigpicture` and `steam://close/bigpicture` directly as prep-cmd `do`/`undo` — no wrapper script needed.

## Recovery from black screen (vmon mode)

The `sunshine.service.d/vmon-recovery.conf` drop-in (installed by `install.sh`) runs `sunshine-stop-vmon.sh` automatically via `ExecStopPost` whenever Sunshine stops, including crashes. Manual recovery is only needed if the drop-in is not installed.

Run as the **same user as the graphical session** (not root):

```bash
./vmon/sunshine-vmon-recover.sh
```

From a root TTY:
```bash
sudo -u <user> \
  XDG_RUNTIME_DIR=/run/user/1000 \
  WAYLAND_DISPLAY=wayland-0 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
  ./vmon/sunshine-vmon-recover.sh
```

## Recovery (headless mode)

No physical display state to restore. Just restart the compositor:

```bash
./headless/sunshine-labwc-recover.sh
# or
systemctl --user restart sunshine-labwc.service
```
