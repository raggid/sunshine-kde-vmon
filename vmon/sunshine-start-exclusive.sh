#!/usr/bin/env bash
# Sunshine prep-cmd for Desktop Exclusive mode.
#
# Enables the virtual monitor as the sole active output — DP-1 is disabled
# so the client gets the full desktop without a physical monitor competing.
# Stream ends via sunshine-stop-vmon.sh (undo-cmd), which re-enables DP-1.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=sunshine-vmon-common.sh
source "${SCRIPT_DIR}/sunshine-vmon-common.sh"

unset WAYLAND_DISPLAY
import_plasma_session_env
trap '[[ $? -ne 0 ]] && abort_stream_layout' EXIT

init_primary_output
ensure_virtual_monitor || exit 1
apply_custom_mode

# Enable vmon at origin — it will be the only active output.
kscreen-doctor \
  "output.${VMON_OUTPUT}.enable" \
  "output.${VMON_OUTPUT}.mode.${RES}@${FPS}" \
  "output.${VMON_OUTPUT}.priority.1" \
  "output.${VMON_OUTPUT}.position.0,0"

sleep 1

if ! virtual_output_enabled; then
  echo "sunshine-vmon: ${VMON_OUTPUT} nao ficou habilitado." >&2
  exit 1
fi

kscreen-doctor "output.${PRIMARY_OUTPUT}.disable"

if ! virtual_output_enabled; then
  echo "sunshine-vmon: virtual desabilitado apos desligar o fisico." >&2
  exit 1
fi

trap - EXIT
