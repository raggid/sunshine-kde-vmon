#!/usr/bin/env bash
# Persistent headless Wayland compositor (labwc) for stream isolation.
#
# Keeps labwc running permanently; stream start/stop only change output
# resolution — the physical KDE desktop is never touched.
#
# Requires: labwc, wlr-randr
# Optional: Xwayland (for X11 apps inside the stream desktop)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=sunshine-labwc-common.sh
source "${SCRIPT_DIR}/sunshine-labwc-common.sh"

import_session_env

LABWC_PID=0
PLASMASHELL_PID=0
SWAYBG_PID=0
RELAY_PID=0
LABWC_CONFIG_DIR="${HOME}/.config/labwc-stream"

cleanup() {
  echo "sunshine-labwc: stopping." >&2
  [[ "${RELAY_PID}" -gt 0 ]] && kill -TERM "${RELAY_PID}" 2>/dev/null || true
  [[ "${PLASMASHELL_PID}" -gt 0 ]] && kill -TERM "${PLASMASHELL_PID}" 2>/dev/null || true
  [[ "${SWAYBG_PID}" -gt 0 ]] && kill -TERM "${SWAYBG_PID}" 2>/dev/null || true
  if [[ "${LABWC_PID}" -gt 0 ]]; then
    kill -TERM "${LABWC_PID}" 2>/dev/null || true
    wait "${LABWC_PID}" 2>/dev/null || true
  fi
  rm -f "$(_socket_link)" 2>/dev/null || true
  rm -f "$(_pid_file)" "$(_socket_file)" "$(_display_file)" "$(_env_file)" \
        "$(_plasmashell_pid_file)" 2>/dev/null || true
}
trap cleanup SIGTERM SIGINT EXIT

# ---------------------------------------------------------------------------
# labwc config — write once if absent
# ---------------------------------------------------------------------------
mkdir -p "${LABWC_CONFIG_DIR}"

if [[ ! -f "${LABWC_CONFIG_DIR}/rc.xml" ]]; then
  cat > "${LABWC_CONFIG_DIR}/rc.xml" <<'RCXML'
<?xml version="1.0" encoding="UTF-8"?>
<labwc_config>
  <core>
    <!-- Four independent virtual desktops for the stream session. -->
    <numWorkspaces>4</numWorkspaces>
    <!-- Keep Xwayland running so X11 apps start without delay. -->
    <xwaylandPersistence>yes</xwaylandPersistence>
  </core>
  <keyboard>
    <keybind key="A-F4">
      <action name="Close"/>
    </keybind>
    <keybind key="W-Left">
      <action name="SnapToEdge" direction="left"/>
    </keybind>
    <keybind key="W-Right">
      <action name="SnapToEdge" direction="right"/>
    </keybind>
    <keybind key="W-Up">
      <action name="ToggleMaximize"/>
    </keybind>
  </keyboard>
  <mouse>
    <context name="Root">
      <mousebind button="Right" action="Press">
        <action name="ShowMenu" menu="root-menu"/>
      </mousebind>
    </context>
    <context name="Titlebar">
      <mousebind button="Left" action="DoubleClick">
        <action name="ToggleMaximize"/>
      </mousebind>
    </context>
  </mouse>
</labwc_config>
RCXML
fi

# A right-click desktop menu — edit to add your own launchers.
if [[ ! -f "${LABWC_CONFIG_DIR}/menu.xml" ]]; then
  cat > "${LABWC_CONFIG_DIR}/menu.xml" <<'MENUXML'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu>
  <menu id="root-menu" label="Stream Desktop">
    <item label="Terminal (foot)">
      <action name="Execute"><command>foot</command></action>
    </item>
    <item label="Terminal (kitty)">
      <action name="Execute"><command>kitty</command></action>
    </item>
  </menu>
</openbox_menu>
MENUXML
fi

# ---------------------------------------------------------------------------
# Verify dependencies
# ---------------------------------------------------------------------------
if ! command -v labwc >/dev/null 2>&1; then
  echo "sunshine-labwc: 'labwc' not found in PATH. Install labwc and retry." >&2
  exit 1
fi
if ! command -v wlr-randr >/dev/null 2>&1; then
  echo "sunshine-labwc: 'wlr-randr' not found in PATH. Install wlr-randr and retry." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Start labwc
# ---------------------------------------------------------------------------

# Startup command: set idle output mode then idle forever.
# wlr-randr may need a few retries while labwc initialises the output.
STARTUP_CMD="for i in \$(seq 1 50); do \
  wlr-randr --output ${LABWC_OUTPUT} \
    --custom-mode ${LABWC_IDLE_WIDTH}x${LABWC_IDLE_HEIGHT}@${LABWC_IDLE_FPS}Hz \
    >/dev/null 2>&1 && break; \
  sleep 0.1; \
done; exec sleep infinity"

SOCKETS_BEFORE="$(snapshot_wayland_sockets)"
X11_BEFORE="$(snapshot_x11_displays)"

WLR_BACKENDS=headless \
WLR_HEADLESS_OUTPUTS=1 \
WLR_RENDERER=gles2 \
XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR}" \
  labwc \
    -C "${LABWC_CONFIG_DIR}" \
    -s "bash -c '${STARTUP_CMD}'" \
    &
LABWC_PID=$!
echo "${LABWC_PID}" > "$(_pid_file)"

# ---------------------------------------------------------------------------
# Detect socket and create stable symlink
# ---------------------------------------------------------------------------
LABWC_SOCKET=""
LABWC_SOCKET="$(wait_for_new_wayland_socket "${SOCKETS_BEFORE}" 15)" || {
  echo "sunshine-labwc: no new Wayland socket appeared within 15s." >&2
  exit 1
}
echo "${LABWC_SOCKET}" > "$(_socket_file)"

# Symlink gives Sunshine a stable WAYLAND_DISPLAY regardless of which
# wayland-N number labwc chose.
ln -sf "${XDG_RUNTIME_DIR}/${LABWC_SOCKET}" "$(_socket_link)"

echo "sunshine-labwc: compositor ready — socket=${LABWC_SOCKET}, link=${LABWC_SOCKET_LINK_NAME}" >&2

# ---------------------------------------------------------------------------
# Detect Xwayland display (labwc starts Xwayland when a client first needs it,
# or eagerly with xwaylandPersistence=yes — give it a few seconds).
# ---------------------------------------------------------------------------
LABWC_DISPLAY=""
LABWC_DISPLAY="$(wait_for_new_x11_display "${X11_BEFORE}" 8)" || true
if [[ -n "${LABWC_DISPLAY}" ]]; then
  echo "${LABWC_DISPLAY}" > "$(_display_file)"
  echo "sunshine-labwc: XWayland display ${LABWC_DISPLAY}" >&2
else
  echo "sunshine-labwc: XWayland not observed yet (starts on first X11 client)." >&2
fi

# Write a sourceable env file for wrapper scripts / apps.json.
cat > "$(_env_file)" <<ENV
export WAYLAND_DISPLAY=${LABWC_SOCKET_LINK_NAME}
${LABWC_DISPLAY:+export DISPLAY=${LABWC_DISPLAY}}
ENV

echo "sunshine-labwc: env file written to $(_env_file)" >&2

# ---------------------------------------------------------------------------
# Launch Plasma shell inside labwc for a full KDE desktop experience.
# plasmashell handles its own wallpaper, so swaybg is only used as a fallback.
# ---------------------------------------------------------------------------
if command -v plasmashell >/dev/null 2>&1; then
  # dbus-run-session gives plasmashell its own private bus so it does not
  # conflict with (or replace) the physical desktop's plasmashell instance.
  WAYLAND_DISPLAY="${LABWC_SOCKET_LINK_NAME}" \
  DISPLAY="${LABWC_DISPLAY:-:0}" \
  XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR}" \
  QT_QPA_PLATFORM=wayland \
  KDE_FULL_SESSION=true \
  PLASMA_USE_QT_SCALING=1 \
    dbus-run-session -- plasmashell 2>/dev/null &
  PLASMASHELL_PID=$!
  echo "${PLASMASHELL_PID}" > "$(_plasmashell_pid_file)"
  echo "sunshine-labwc: plasmashell started (pid=${PLASMASHELL_PID})" >&2
elif command -v swaybg >/dev/null 2>&1; then
  WAYLAND_DISPLAY="${LABWC_SOCKET_LINK_NAME}" \
  XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR}" \
    swaybg -c '#1a1a2e' &
  SWAYBG_PID=$!
  echo "sunshine-labwc: swaybg started as fallback (pid=${SWAYBG_PID})" >&2
else
  echo "sunshine-labwc: no plasmashell or swaybg — stream will show a black background" >&2
fi

# ---------------------------------------------------------------------------
# Wait for labwc to exit
# ---------------------------------------------------------------------------
# Note: input relay is started/stopped by sunshine-start-labwc.sh /
# sunshine-stop-labwc.sh (prep-cmd / undo-cmd) so it only runs during an
# active stream, not persistently. This avoids grabbing Sunshine's uinput
# devices when a vmon stream is active.
wait "${LABWC_PID}"
