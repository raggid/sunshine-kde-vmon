#!/usr/bin/env bash
# prep-cmd do — Desktop: cria o vmon na resolução do cliente; físico permanece ligado.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../vmon/sunshine-vmon-common.sh
source "${SCRIPT_DIR}/../vmon/sunshine-vmon-common.sh"

cleanup_on_abort() {
  apply_idle_layout || force_enable_all_physical || true
  kscreen-doctor "output.${PRIMARY_OUTPUT}.position.0,0" 2>/dev/null || true
  pkill -f "krfb-virtualmonitor.*--name ${VMON_NAME}" 2>/dev/null || true
}

unset WAYLAND_DISPLAY
import_plasma_session_env
trap '[[ $? -ne 0 ]] && cleanup_on_abort' EXIT

init_primary_output
resolve_client_resolution

# Mata qualquer krfb sobrevivente de sessão anterior
pkill -f "krfb-virtualmonitor.*--name ${VMON_NAME}" 2>/dev/null || true
sleep 0.5

# Cria o monitor virtual na resolução do cliente
krfb-virtualmonitor \
  --resolution "${RES}" \
  --name "${VMON_NAME}" \
  --password "${VMON_PASSWORD}" \
  --port "${VMON_PORT}" &

if ! wait_for_virtual_output 30; then
  echo "sunshine-vmon: monitor virtual não apareceu." >&2
  exit 1
fi

apply_custom_mode

mapfile -t _POS < <(get_left_positions)
VMON_POS="${_POS[0]:-0,0}"
PRIMARY_POS="${_POS[1]:-1746,0}"

kscreen-doctor \
  "output.${VMON_OUTPUT}.enable" \
  "output.${VMON_OUTPUT}.mode.${RES}@${FPS}" \
  "output.${VMON_OUTPUT}.priority.1" \
  "output.${VMON_OUTPUT}.position.${VMON_POS}" \
  "output.${PRIMARY_OUTPUT}.position.${PRIMARY_POS}"

if ! virtual_output_enabled; then
  echo "sunshine-vmon: vmon não ficou habilitado." >&2
  exit 1
fi

set_sunshine_output "${VMON_OUTPUT}"
trap - EXIT
