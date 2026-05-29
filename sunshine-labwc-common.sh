#!/usr/bin/env bash
# Shared helpers for the headless labwc streaming mode.
# Source this file; do not execute directly.

LABWC_SOCKET_LINK_NAME="${SUNSHINE_LABWC_SOCKET:-wayland-stream}"
LABWC_OUTPUT="${SUNSHINE_LABWC_OUTPUT:-HEADLESS-1}"
LABWC_IDLE_WIDTH="${SUNSHINE_LABWC_IDLE_WIDTH:-1920}"
LABWC_IDLE_HEIGHT="${SUNSHINE_LABWC_IDLE_HEIGHT:-1080}"
LABWC_IDLE_FPS="${SUNSHINE_LABWC_IDLE_FPS:-60}"
SUNSHINE_CONF="${HOME}/.config/sunshine/sunshine.conf"

# State dir is set by init_state_paths() after XDG_RUNTIME_DIR is known.
_LABWC_STATE_DIR=""

import_session_env() {
  local uid
  uid="$(id -u)"
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/${uid}}"

  if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" && -S "${XDG_RUNTIME_DIR}/bus" ]]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
  fi

  init_state_paths
}

init_state_paths() {
  _LABWC_STATE_DIR="${XDG_RUNTIME_DIR}/sunshine-labwc"
  mkdir -p "${_LABWC_STATE_DIR}"
}

_pid_file()          { echo "${_LABWC_STATE_DIR}/labwc.pid"; }
_socket_file()       { echo "${_LABWC_STATE_DIR}/labwc.socket"; }
_display_file()      { echo "${_LABWC_STATE_DIR}/labwc.display"; }
_env_file()          { echo "${_LABWC_STATE_DIR}/labwc.env"; }
_plasmashell_pid_file() { echo "${_LABWC_STATE_DIR}/plasmashell.pid"; }
_socket_link()       { echo "${XDG_RUNTIME_DIR}/${LABWC_SOCKET_LINK_NAME}"; }

labwc_is_running() {
  local pid_file
  pid_file="$(_pid_file)"
  [[ -f "${pid_file}" ]] || return 1
  local pid
  pid="$(cat "${pid_file}" 2>/dev/null)"
  [[ -n "${pid}" ]] || return 1
  kill -0 "${pid}" 2>/dev/null
}

get_labwc_socket() {
  cat "$(_socket_file)" 2>/dev/null
}

get_labwc_display() {
  cat "$(_display_file)" 2>/dev/null
}

# Snapshot Wayland socket paths (wayland-N only, not lock files).
snapshot_wayland_sockets() {
  find "${XDG_RUNTIME_DIR}" -maxdepth 1 -name 'wayland-[0-9]*' -type s 2>/dev/null | sort
}

# Snapshot X11 display socket paths (/tmp/.X11-unix/XN).
snapshot_x11_displays() {
  find /tmp/.X11-unix -maxdepth 1 -name 'X[0-9]*' -type s 2>/dev/null | sort
}

# Wait for a new Wayland socket to appear that was not in $1 (newline-list of paths).
# Prints the bare socket name (e.g. "wayland-2") to stdout on success.
wait_for_new_wayland_socket() {
  local before="$1"
  local timeout="${2:-15}"
  local end=$(( SECONDS + timeout ))

  while (( SECONDS < end )); do
    local s
    while IFS= read -r s; do
      [[ -S "${s}" ]] || continue
      if ! grep -qF "${s}" <<< "${before}"; then
        basename "${s}"
        return 0
      fi
    done < <(snapshot_wayland_sockets)
    sleep 0.1
  done
  return 1
}

# Wait for a new X11 socket to appear. Prints the display name (e.g. ":1").
wait_for_new_x11_display() {
  local before="$1"
  local timeout="${2:-10}"
  local end=$(( SECONDS + timeout ))

  while (( SECONDS < end )); do
    local s display
    while IFS= read -r s; do
      display=":${s##*/X}"
      if ! grep -qF "${s}" <<< "${before}"; then
        echo "${display}"
        return 0
      fi
    done < <(snapshot_x11_displays)
    sleep 0.1
  done
  return 1
}

# Set the labwc output to a given resolution. Uses the stable socket link.
set_labwc_mode() {
  local width="$1" height="$2" fps="$3"
  # timeout guards against wlr-randr hanging when labwc is in a bad state
  # (e.g. after a client process crashed and left broken Wayland state).
  WAYLAND_DISPLAY="${LABWC_SOCKET_LINK_NAME}" \
    timeout 5 wlr-randr --output "${LABWC_OUTPUT}" \
              --custom-mode "${width}x${height}@${fps}Hz"
}

set_sunshine_output() {
  local output="$1"
  sed -i '/^output_name/d' "${SUNSHINE_CONF}"
  echo "output_name = ${output}" >> "${SUNSHINE_CONF}"
}

resolve_client_resolution() {
  SUNSHINE_CLIENT_WIDTH="${SUNSHINE_CLIENT_WIDTH:-1920}"
  SUNSHINE_CLIENT_HEIGHT="${SUNSHINE_CLIENT_HEIGHT:-1080}"
  SUNSHINE_CLIENT_FPS="${SUNSHINE_CLIENT_FPS%.*}"
  SUNSHINE_CLIENT_FPS="${SUNSHINE_CLIENT_FPS:-60}"
  WIDTH="${SUNSHINE_CLIENT_WIDTH}"
  HEIGHT="${SUNSHINE_CLIENT_HEIGHT}"
  FPS="${SUNSHINE_CLIENT_FPS}"
}
