# Work In Progress — 2026-05-30

## System State

Two Wayland sockets coexist at login:
- `wayland-0` → labwc compositor (`sunshine-labwc.service`)
- `wayland-1` → KDE/KWin
- `wayland-stream` → symlink to `wayland-0` (managed by labwc service)

Sunshine has `WAYLAND_DISPLAY=wayland-stream` locked via:
`~/.config/systemd/user/sunshine.service.d/labwc-stream.conf`

`sunshine.conf` at idle: `capture = wlr`, `output_name = HEADLESS-1`

Services:
- `sunshine-labwc.service` — enabled, running
- `sunshine-vmon.service` — **disabled** (pending fix)
- `sunshine.service` — enabled, running

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

---

## Still Broken

### 1. Headless stream input — mouse moves, clicks and keyboard do nothing

Relay log (`/run/user/1000/sunshine-labwc/relay.log`) confirms:
- Virtual pointer created ✓
- Virtual keyboard created + keymap sent ✓
- All 5 devices grabbed (event16–20: Mouse, Mouse abs, Keyboard, Touch, Pen) ✓
- Touch/Pen passthrough lost mid-session — now handled correctly ✓

**What is happening**: cursor moves (relative motion works), but mouse buttons and all keyboard input are ignored by apps.

**Hypotheses**:
1. `zwp_virtual_keyboard_v1` keycode offset — XKB keycodes = evdev + 8. The relay sends raw evdev codes; need to verify labwc adds the offset or expects XKB codes directly.
2. Silent Wayland protocol error in pywayland — errors may be swallowed without logging.
3. labwc focus issue — virtual pointer moves cursor but compositor doesn't deliver button/keyboard events to the focused surface.
4. `vp.button()` or `vk.key()` call signatures wrong for the labwc version in use.

**Next steps to try**:
- Run the relay manually with visible output while streaming to watch for errors:
  ```
  WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/run/user/1000 \
    python3 /home/raggid/projects/sunshine-kde-vmon/sunshine-labwc-input-relay.py
  ```
- Test `wtype` / `ydotool` directly against `WAYLAND_DISPLAY=wayland-0` to verify labwc accepts synthetic input at all
- Check if labwc requires `wl_seat` capability announcement before button/key events are accepted
- Try adding `+8` offset to evdev keycodes before passing to `vk.key()`

### 2. vmon mode — disabled, needs Sunshine restart to switch capture method

`capture` in `sunshine.conf` is read at **Sunshine startup only**, not per-connection.
`capture = wlr` is needed for labwc; `capture = kwin` is needed for KDE/vmon.
Since Sunshine has `WAYLAND_DISPLAY=wayland-stream` locked, it connects to labwc and can't see the KDE virtual monitor with `capture = wlr`.

**Plan (not yet implemented)**:
1. `sunshine-start-vmon.sh` changes `sunshine.conf` (`capture = kwin`, `output_name = Virtual-sunshine-vmon`) and redirects `wayland-stream → wayland-1`
2. Checks if Sunshine is already running with `capture = kwin` (via conf file check)
3. If not: clears EXIT trap, restarts `sunshine.service` in background, exits 0
4. Moonlight auto-reconnects to the restarted Sunshine (now using `capture = kwin` + KDE socket)
5. Second connection: conf already correct, stream proceeds normally
6. `sunshine-stop-vmon.sh` restores `capture = wlr`, `output_name = HEADLESS-1`, `wayland-stream → wayland-0`
