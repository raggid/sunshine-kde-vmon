# Work In Progress — 2026-05-30 (updated)

## System State

**Mode: kwin / vmon only** (labwc disabled — headless mode kept in repo for future work)

- `wayland-0` → KDE/KWin
- `sunshine.conf`: `capture = kwin`, `output_name = Virtual-sunshine-vmon` (permanent)
- No Sunshine drop-in override needed — base unit has `wayland-0`, KDE takes it at login

Services:
- `sunshine-labwc.service` — **disabled**
- `sunshine-vmon.service` — enabled, running ✓
- `sunshine.service` — enabled, running with `capture = kwin` ✓

Monitor layout during stream:
- `Virtual-sunshine-vmon` at `(0, 0)` — captured by Sunshine, streamed to client
- `DP-1` shifted right to `(vmon_logical_width, 0)`
- Restored to `DP-1` at `(0, 0)` when stream ends

---

## Fixed This Session

### vmon service connecting to labwc instead of KDE (commits 4060d12, 838e8ee)
`import_plasma_session_env` was picking `wayland-0` (labwc) as KDE's socket.
- Removed hardcoded `Environment=WAYLAND_DISPLAY=wayland-0` from the service unit and `install.sh`
- `sunshine-vmon-common.sh` now excludes the `wayland-stream` target when searching for KDE's socket
- vmon scripts unset `WAYLAND_DISPLAY` before calling `import_plasma_session_env`

### vmon idle layout: KDE restoring vmon as primary (commit b96a7d3)
After `disable_virtual_monitor`, KDE's kscreen config restore re-enabled the vmon asynchronously.
- Added retry loop (up to 3s) in `apply_idle_layout` that re-disables until `virtual_output_enabled` returns false

### Relay running persistently — blocking vmon inputs (commit 6e382b7)
Relay was started by the labwc service permanently, holding exclusive grabs even during vmon streams.
- Moved relay lifecycle to prep-cmd/undo-cmd: started by `sunshine-start-labwc.sh`, stopped by `sunshine-stop-labwc.sh`

### Relay missing keyboard on initial grab (commit c7955b2)
Mouse passthrough registers before keyboard. Relay broke out of the wait loop on first device found.
- Added 1s sleep + rescan after first device appears
- Added late-arrival check on 2s timeout in the inner loop

### Relay inner loop breaking on Touch/Pen passthrough loss (commit 11eaa1f)
Touch/Pen passthrough devices are destroyed mid-session. Lost devices were left in `self._devices` and `self._grabbed_paths`, causing `dev_fds` rebuild to include stale closed fds → `select.select` failure → inner loop break → `_release_devices()` (ungrabs everything).
- Remove lost devices from `self._devices` and `self._grabbed_paths` on loss
- Inner loop now only exits when core devices (mouse/keyboard) are gone

### Switched to kwin capture; vmon mode fully restored (commits 4a864c5, 239a2e6, 7f3c0b8)
labwc mode disabled. vmon streaming working end-to-end.

Key discoveries and fixes:
1. **`capture` is startup-only** — can't switch per-stream. Solution: stay on `capture = kwin` permanently.
2. **`output_name` is read before prep-cmd runs** — setting it inside `sunshine-start-vmon.sh` was always too late; Sunshine had already selected DP-1. Fix: `sunshine-vmon-service.sh` sets `output_name = Virtual-sunshine-vmon` at startup and keeps it there permanently.
3. **KDE clone mode** — both monitors at `x=0` caused KDE to treat them as mirrors. Fix: atomic `kscreen-doctor` call sets enable + mode + priority + position together; vmon placed at `(0,0)`, DP-1 shifted right.
4. **wayland-stream drop-in removed** — was locking Sunshine to the labwc socket. Now Sunshine inherits KDE's socket from the systemd user environment (KDE propagates it at login).

---

## Still Open

### Headless stream input — mouse moves, clicks and keyboard do nothing

labwc mode is disabled but kept in the repo. When resuming:

Relay log (`/run/user/1000/sunshine-labwc/relay.log`) confirmed all devices grabbed and virtual pointer/keyboard created. Cursor moves but buttons and keys are ignored.

**Hypotheses**:
1. `zwp_virtual_keyboard_v1` keycode offset — XKB = evdev + 8; relay sends raw evdev codes.
2. Silent Wayland protocol error in pywayland.
3. labwc focus issue — compositor not delivering events to focused surface.
4. `vp.button()` / `vk.key()` call signatures wrong for installed labwc version.

**Next steps**:
- Test `wtype` / `ydotool` against `WAYLAND_DISPLAY=wayland-0` to verify labwc accepts synthetic input at all
- Run relay manually with visible output during a stream
- Try `+8` offset on evdev keycodes passed to `vk.key()`
