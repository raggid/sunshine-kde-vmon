#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=sunshine-vmon-common.sh
source "${SCRIPT_DIR}/sunshine-vmon-common.sh"

unset WAYLAND_DISPLAY  # Sunshine inherits wayland-stream; vmon needs KDE's socket
import_plasma_session_env
init_primary_output
apply_idle_layout
set_sunshine_output "${PRIMARY_OUTPUT}"

# Restore wayland-stream back to the labwc socket so future labwc streams work.
WAYLAND_STREAM_LINK="${XDG_RUNTIME_DIR}/wayland-stream"
STREAM_BAK="${XDG_RUNTIME_DIR}/sunshine-labwc/wayland-stream.bak"
if [[ -f "${STREAM_BAK}" ]]; then
  ln -sf "$(cat "${STREAM_BAK}")" "${WAYLAND_STREAM_LINK}" 2>/dev/null || true
  rm -f "${STREAM_BAK}"
  echo "sunshine-vmon: wayland-stream restored to $(readlink "${WAYLAND_STREAM_LINK}")" >&2
elif [[ -f "${XDG_RUNTIME_DIR}/sunshine-labwc/labwc.socket" ]]; then
  LABWC_SOCK="$(cat "${XDG_RUNTIME_DIR}/sunshine-labwc/labwc.socket")"
  ln -sf "${XDG_RUNTIME_DIR}/${LABWC_SOCK}" "${WAYLAND_STREAM_LINK}" 2>/dev/null || true
  echo "sunshine-vmon: wayland-stream restored to ${LABWC_SOCK}" >&2
fi
