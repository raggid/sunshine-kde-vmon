#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=sunshine-vmon-common.sh
source "${SCRIPT_DIR}/sunshine-vmon-common.sh"

# Resolucao padrao do monitor persistente (ajustada no inicio de cada stream)
SUNSHINE_CLIENT_WIDTH="${SUNSHINE_VMON_WIDTH:-1920}"
SUNSHINE_CLIENT_HEIGHT="${SUNSHINE_VMON_HEIGHT:-1080}"
SUNSHINE_CLIENT_FPS="${SUNSHINE_VMON_FPS:-60}"

resolve_client_resolution

if pgrep -f "krfb-virtualmonitor.*--name ${VMON_NAME}" >/dev/null; then
  echo "sunshine-vmon: krfb-virtualmonitor ja em execucao."
  exit 0
fi

krfb-virtualmonitor \
  --resolution "${RES}" \
  --name "${VMON_NAME}" \
  --password "${VMON_PASSWORD}" \
  --port "${VMON_PORT}" &
KRFB_PID=$!

cleanup() {
  kill "${KRFB_PID}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

if ! wait_for_virtual_output 20; then
  echo "sunshine-vmon: falha ao registrar o monitor virtual no KDE." >&2
  exit 1
fi

apply_custom_mode

# Monitor existe mas fica desligado no dia a dia; ligado apenas durante o stream
kscreen-doctor "output.${VMON_OUTPUT}.disable"

wait "${KRFB_PID}"
