#!/usr/bin/env bash
# Monitor virtual persistente. NUNCA desliga o monitor fisico — apenas o virtual.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=sunshine-vmon-common.sh
source "${SCRIPT_DIR}/sunshine-vmon-common.sh"

SUNSHINE_CLIENT_WIDTH="${SUNSHINE_VMON_WIDTH:-1920}"
SUNSHINE_CLIENT_HEIGHT="${SUNSHINE_VMON_HEIGHT:-1080}"
SUNSHINE_CLIENT_FPS="${SUNSHINE_VMON_FPS:-60}"

KRFB_PID=""

stop_service() {
  import_plasma_session_env
  if kscreen_outputs_ready; then
    apply_idle_layout || force_enable_all_physical || true
  fi
  if [[ -n "${KRFB_PID}" ]]; then
    kill "${KRFB_PID}" 2>/dev/null || true
  fi
}
trap stop_service SIGTERM SIGINT

if ! wait_for_plasma_outputs 90; then
  exit 1
fi

# Corrige layout salvo com fisico desligado (ex.: Desktop Exclusive + reboot)
apply_idle_layout || exit 1

if pgrep -f "krfb-virtualmonitor.*--name ${VMON_NAME}" >/dev/null; then
  KRFB_PID="$(pgrep -f "krfb-virtualmonitor.*--name ${VMON_NAME}" | head -1)"
else
  resolve_client_resolution
  krfb-virtualmonitor \
    --resolution "${RES}" \
    --name "${VMON_NAME}" \
    --password "${VMON_PASSWORD}" \
    --port "${VMON_PORT}" &
  KRFB_PID=$!

  if ! wait_for_virtual_output 30; then
    echo "sunshine-vmon: falha ao registrar o monitor virtual no KDE." >&2
    apply_idle_layout || true
    kill "${KRFB_PID}" 2>/dev/null || true
    exit 1
  fi

  apply_custom_mode
fi

# Keep Sunshine pointed at the virtual monitor permanently so it reads the
# right output_name before running the prep-cmd at connection time.
set_sunshine_output "${VMON_OUTPUT}"

apply_idle_layout || exit 1

wait "${KRFB_PID}"
