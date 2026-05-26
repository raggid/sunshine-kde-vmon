# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project does

Shell scripts for [Sunshine](https://github.com/LizardByte/Sunshine) game streaming on KDE Plasma (Wayland). A virtual monitor (`krfb-virtualmonitor`) is kept alive as a persistent systemd user service and only enabled/disabled at stream start/stop. Sunshine always captures `Virtual-sunshine-vmon`; what differs between profiles is whether the physical monitor stays on.

## Installation / service management

```bash
# Install (copies systemd unit, asks to enable)
./install.sh

# Service lifecycle
systemctl --user start sunshine-vmon.service
systemctl --user status sunshine-vmon.service
systemctl --user restart sunshine-vmon.service

# Force-enable service without interactive prompt
SUNSHINE_VMON_ENABLE_SERVICE=yes ./install.sh

# Inspect monitor state
kscreen-doctor -o
```

## Architecture

All shared logic lives in **`sunshine-vmon-common.sh`** — every other script sources it. No script has standalone logic; adding a feature means adding/editing a function there.

| Script | Role | Profile |
|--------|------|---------|
| `sunshine-vmon-service.sh` | Persistent systemd service: creates virtual monitor at login, keeps it alive, restores idle layout on exit | — |
| `sunshine-start-vmon.sh` | Stream start: enable virtual, confirm it is enabled, point Sunshine to it; physical stays on | Desktop |
| `sunshine-start-vmon-offmon.sh` | Stream start: enable virtual, confirm it is enabled, point Sunshine to it, then disable physical | Exclusive |
| `sunshine-stop-vmon.sh` | Stream stop (both profiles): restore idle layout (re-enables physical if needed), point Sunshine back to physical | Desktop + Exclusive |
| `sunshine-vmon-recover.sh` | Black-screen recovery: force all physical outputs on, disable virtual | — |

### Key functions in `sunshine-vmon-common.sh`

- `import_plasma_session_env` — sets `XDG_RUNTIME_DIR`, `DBUS_SESSION_BUS_ADDRESS`, `WAYLAND_DISPLAY` when running outside the graphical session (TTY, systemd)
- `detect_primary_output_name` — uses `kscreen-doctor -j | python3` to find the connected, enabled physical output with priority 1; falls back to `DP-1`
- `apply_idle_layout` — canonical "stream ended" state: enable all physical outputs, disable virtual; used by service trap, stop scripts, and recover
- `abort_stream_layout` — EXIT trap used in start scripts; runs if prep-cmd fails partway through, restores layout and restarts Sunshine
- `set_sunshine_output` — writes `output_name = <value>` to `~/.config/sunshine/sunshine.conf` via `sed`; Sunshine re-reads this file at each new client connection, so no service restart is needed after changing it

### Exclusive profile sequencing (order matters)

`sunshine-start-vmon-offmon.sh` must follow this exact order to avoid a black screen or infinite restart loop:
1. Enable virtual monitor (physical still on)
2. Wait 2 s and confirm virtual is enabled
3. Set `output_name` in `sunshine.conf` to the virtual output — **do NOT restart Sunshine here**
4. Disable the physical monitor

Sunshine re-reads `output_name` from the config when it sets up a new stream (after prep-cmd exits 0), so no restart is needed inside the prep-cmd. Restarting Sunshine from within the prep-cmd kills the process, Moonlight immediately reconnects to the new Sunshine, which runs the prep-cmd again, creating an infinite restart loop.

## Environment variables

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

## Sunshine `apps.json` integration

Sunshine prep-cmd `do`/`undo` must use **absolute paths**. The `env` key is required in `apps.json` or apps won't appear in Moonlight. See `examples/apps.json` for the Desktop, Desktop Exclusive, and Steam Big Picture app definitions (replace `/home/USER/` with the actual home path).

## Recovery from black screen

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
