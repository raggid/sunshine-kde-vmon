#!/usr/bin/env bash
# Perfil Desktop: notebook como segunda tela — fisico DP-1 permanece ligado.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=sunshine-vmon-common.sh
source "${SCRIPT_DIR}/sunshine-vmon-common.sh"

unset WAYLAND_DISPLAY  # Sunshine inherits wayland-stream; vmon needs KDE's socket
import_plasma_session_env
trap '[[ $? -ne 0 ]] && abort_stream_layout' EXIT

init_primary_output
ensure_virtual_monitor || exit 1
apply_custom_mode

kscreen-doctor \
  "output.${VMON_OUTPUT}.enable" \
  "output.${VMON_OUTPUT}.mode.${RES}@${FPS}" \
  "output.${VMON_OUTPUT}.priority.1"

if ! virtual_output_enabled; then
  echo "sunshine-vmon: ${VMON_OUTPUT} nao ficou habilitado." >&2
  exit 1
fi

set_sunshine_output "${VMON_OUTPUT}"

# Redirect wayland-stream to KDE's socket so Sunshine's wlr capture sees the
# vmon. The labwc socket name is saved by sunshine-stop-vmon.sh for restore.
LABWC_SOCKET_FILE="${XDG_RUNTIME_DIR}/sunshine-labwc/labwc.socket"
WAYLAND_STREAM_LINK="${XDG_RUNTIME_DIR}/wayland-stream"
if [[ -L "${WAYLAND_STREAM_LINK}" ]]; then
  readlink "${WAYLAND_STREAM_LINK}" > "${XDG_RUNTIME_DIR}/sunshine-labwc/wayland-stream.bak" 2>/dev/null || true
  ln -sf "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" "${WAYLAND_STREAM_LINK}"
  echo "sunshine-vmon: wayland-stream → ${WAYLAND_DISPLAY}" >&2
fi

trap - EXIT
