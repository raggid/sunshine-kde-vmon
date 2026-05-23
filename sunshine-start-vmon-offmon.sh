#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=sunshine-vmon-common.sh
source "${SCRIPT_DIR}/sunshine-vmon-common.sh"

import_plasma_session_env
trap '[[ $? -ne 0 ]] && abort_stream_layout' EXIT

init_primary_output
ensure_virtual_monitor || exit 1
apply_custom_mode
resolve_client_resolution

# 1) Virtual ligado com fisico ainda ativo
kscreen-doctor \
  "output.${VMON_OUTPUT}.enable" \
  "output.${VMON_OUTPUT}.mode.${RES}@${FPS}" \
  "output.${VMON_OUTPUT}.priority.1"

sleep 2

if ! virtual_output_enabled; then
  echo "sunshine-vmon: ${VMON_OUTPUT} nao ficou habilitado." >&2
  exit 1
fi

# 2) Sunshine aponta para o virtual enquanto ambos existem
set_sunshine_output "${VMON_OUTPUT}"
reload_sunshine_if_running
sleep 4

# 3) So entao desliga o monitor fisico
kscreen-doctor "output.${PRIMARY_OUTPUT}.disable"

if ! virtual_output_enabled; then
  echo "sunshine-vmon: virtual desabilitado apos desligar o fisico." >&2
  exit 1
fi

trap - EXIT
