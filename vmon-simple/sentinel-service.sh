#!/usr/bin/env bash
# Serviço sentinela: mantém um vmon fictício sempre conectado ao KDE.
# Garante que o Sunshine nunca veja "nenhum monitor" mesmo sem monitor físico
# e mesmo quando o stream vmon (sunshine-vmon) ainda não foi criado.
#
# Este output (Virtual-sunshine-idle) permanece DESABILITADO — nunca visível
# no desktop. Só precisa existir para o KDE/Sunshine considerarem um output
# conectado.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../vmon/sunshine-vmon-common.sh
source "${SCRIPT_DIR}/../vmon/sunshine-vmon-common.sh"

SENTINEL_NAME="${SUNSHINE_SENTINEL_NAME:-sunshine-idle}"
SENTINEL_OUTPUT="Virtual-${SENTINEL_NAME}"
SENTINEL_PORT="${SUNSHINE_SENTINEL_PORT:-5906}"

sentinel_present() {
  kscreen-doctor -o 2>/dev/null | grep -qF "${SENTINEL_OUTPUT}"
}

wait_for_sentinel() {
  local timeout="${1:-30}" elapsed=0
  while (( elapsed < timeout )); do
    sentinel_present && return 0
    sleep 1; (( elapsed++ ))
  done
  return 1
}

KRFB_PID=""

stop_sentinel() {
  [[ -n "${KRFB_PID}" ]] && kill "${KRFB_PID}" 2>/dev/null || true
}
trap stop_sentinel SIGTERM SIGINT

if ! wait_for_plasma_outputs 90; then
  exit 1
fi

if pgrep -f "krfb-virtualmonitor.*--name ${SENTINEL_NAME}" >/dev/null; then
  KRFB_PID="$(pgrep -f "krfb-virtualmonitor.*--name ${SENTINEL_NAME}" | head -1)"
else
  krfb-virtualmonitor \
    --resolution "1920x1080" \
    --name "${SENTINEL_NAME}" \
    --password "${VMON_PASSWORD}" \
    --port "${SENTINEL_PORT}" &
  KRFB_PID=$!

  if ! wait_for_sentinel 30; then
    echo "sunshine-sentinel: monitor sentinela não apareceu." >&2
    kill "${KRFB_PID}" 2>/dev/null || true
    exit 1
  fi
fi

# Mantém desabilitado — apenas "conectado", nunca visível
kscreen-doctor "output.${SENTINEL_OUTPUT}.disable" 2>/dev/null || true

wait "${KRFB_PID}"
