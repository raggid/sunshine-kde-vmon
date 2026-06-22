#!/usr/bin/env bash
# prep-cmd do — Exclusive: cria o vmon na resolução do cliente; desabilita o físico.
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

pkill -f "krfb-virtualmonitor.*--name ${VMON_NAME}" 2>/dev/null || true
sleep 0.5

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

kscreen-doctor \
  "output.${VMON_OUTPUT}.enable" \
  "output.${VMON_OUTPUT}.mode.${RES}@${FPS}" \
  "output.${VMON_OUTPUT}.priority.1" \
  "output.${VMON_OUTPUT}.position.0,0"

sleep 1

if ! virtual_output_enabled; then
  echo "sunshine-vmon: vmon não ficou habilitado." >&2
  exit 1
fi

kscreen-doctor "output.${PRIMARY_OUTPUT}.disable"

if ! virtual_output_enabled; then
  echo "sunshine-vmon: vmon desabilitado após desligar o físico." >&2
  exit 1
fi

set_sunshine_output "${VMON_OUTPUT}"
trap - EXIT
