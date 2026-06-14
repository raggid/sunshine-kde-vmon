# vmon mode

Creates a KDE virtual monitor (`krfb-virtualmonitor`) inside the existing KDE Plasma/Wayland session. The physical and stream desktops share the same compositor — KDE manages window placement, panels, and virtual desktops across both outputs.

Requires: `krfb`, `kscreen`, KDE Plasma on Wayland, Sunshine with `capture = kwin`.

## Scripts

| Script | Role |
|--------|------|
| `sunshine-vmon-common.sh` | Shared library — source this, do not run directly |
| `sunshine-vmon-service.sh` | Persistent systemd service: creates the virtual monitor at login, keeps it alive, restores the idle layout on exit |
| `sunshine-start-vmon.sh` | prep-cmd `do`: enables the virtual monitor alongside the physical display, points Sunshine at it |
| `sunshine-stop-vmon.sh` | prep-cmd `undo`: restores idle layout (physical output only), resets Sunshine output |
| `sunshine-start-exclusive.sh` | prep-cmd `do` (exclusive variant): enables virtual monitor and disables all physical outputs so the client gets the full desktop |
| `sunshine-vmon-recover.sh` | Black-screen recovery: force-enables all physical outputs and disables the virtual monitor |

## Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `SUNSHINE_PRIMARY_OUTPUT` | _(auto)_ | Force a specific physical connector (e.g. `DP-1`) |
| `SUNSHINE_CLIENT_WIDTH/HEIGHT/FPS` | `1920/1080/60` | Set by Sunshine at stream start |
| `SUNSHINE_VMON_WIDTH/HEIGHT/FPS` | `1920/1080/60` | Resolution for the persistent idle service |
| `SUNSHINE_VMON_NAME` | `sunshine-vmon` | Name passed to `krfb-virtualmonitor --name` |
| `SUNSHINE_VMON_PORT` | `5905` | krfb VNC port |
| `SUNSHINE_VMON_PASSWORD` | `sunshinepass` | krfb VNC password |

## Recovery

Run as the same user as the graphical session:

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
