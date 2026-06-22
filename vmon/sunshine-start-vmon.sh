#!/usr/bin/env bash
# Perfil Desktop: notebook como segunda tela — fisico DP-1 permanece ligado.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=sunshine-vmon-common.sh
source "${SCRIPT_DIR}/sunshine-vmon-common.sh"

unset WAYLAND_DISPLAY
import_plasma_session_env
trap '[[ $? -ne 0 ]] && abort_stream_layout' EXIT

init_primary_output
ensure_virtual_monitor || exit 1

# Compute positions before enabling so the entire layout change is atomic.
# vmon goes to (0,0); primary shifts right by vmon's logical width.
mapfile -t _POS < <(get_left_positions)
VMON_POS="${_POS[0]:-0,0}"
PRIMARY_POS="${_POS[1]:-1746,0}"

# Do NOT change the vmon mode here: Sunshine opens the KWin screencast before
# the prep-cmd runs, so a resolution change would tear down the PipeWire
# session mid-negotiation and prevent any video from flowing.
kscreen-doctor \
  "output.${VMON_OUTPUT}.enable" \
  "output.${VMON_OUTPUT}.priority.1" \
  "output.${VMON_OUTPUT}.position.${VMON_POS}" \
  "output.${PRIMARY_OUTPUT}.position.${PRIMARY_POS}"

if ! virtual_output_enabled; then
  echo "sunshine-vmon: ${VMON_OUTPUT} nao ficou habilitado." >&2
  exit 1
fi

set_sunshine_output "${VMON_OUTPUT}"

trap - EXIT
