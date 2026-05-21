#!/usr/bin/env bash

VMON_NAME="${SUNSHINE_VMON_NAME:-sunshine-vmon}"
VMON_OUTPUT="Virtual-${VMON_NAME}"
PRIMARY_OUTPUT="${SUNSHINE_PRIMARY_OUTPUT:-DP-2}"
SUNSHINE_CONF="${HOME}/.config/sunshine/sunshine.conf"
VMON_PORT="${SUNSHINE_VMON_PORT:-5905}"
VMON_PASSWORD="${SUNSHINE_VMON_PASSWORD:-sunshinepass}"

resolve_client_resolution() {
  SUNSHINE_CLIENT_WIDTH="${SUNSHINE_CLIENT_WIDTH:-1920}"
  SUNSHINE_CLIENT_HEIGHT="${SUNSHINE_CLIENT_HEIGHT:-1080}"
  SUNSHINE_CLIENT_FPS="${SUNSHINE_CLIENT_FPS%.*}"
  SUNSHINE_CLIENT_FPS="${SUNSHINE_CLIENT_FPS:-60}"

  WIDTH="${SUNSHINE_CLIENT_WIDTH}"
  HEIGHT="${SUNSHINE_CLIENT_HEIGHT}"
  FPS="${SUNSHINE_CLIENT_FPS}"
  FPS_MHZ=$(( FPS * 1000 ))
  RES="${WIDTH}x${HEIGHT}"
}

virtual_output_present() {
  kscreen-doctor -o 2>/dev/null | grep -qF "${VMON_OUTPUT}"
}

wait_for_virtual_output() {
  local timeout="${1:-15}"
  local elapsed=0

  while (( elapsed < timeout )); do
    if virtual_output_present; then
      return 0
    fi
    sleep 1
    ((elapsed++))
  done

  return 1
}

start_krfb_virtualmonitor() {
  resolve_client_resolution

  if pgrep -f "krfb-virtualmonitor.*--name ${VMON_NAME}" >/dev/null; then
    return 0
  fi

  krfb-virtualmonitor \
    --resolution "${RES}" \
    --name "${VMON_NAME}" \
    --password "${VMON_PASSWORD}" \
    --port "${VMON_PORT}" &
}

ensure_virtual_monitor() {
  if virtual_output_present; then
    return 0
  fi

  start_krfb_virtualmonitor

  if ! wait_for_virtual_output 15; then
    echo "sunshine-vmon: monitor virtual '${VMON_OUTPUT}' nao apareceu a tempo." >&2
    echo "sunshine-vmon: ative o servico: systemctl --user enable --now sunshine-vmon.service" >&2
    return 1
  fi
}

apply_custom_mode() {
  resolve_client_resolution
  kscreen-doctor "output.${VMON_OUTPUT}.addCustomMode.${WIDTH}.${HEIGHT}.${FPS_MHZ}.full" 2>/dev/null || true
}

set_sunshine_output() {
  local output="$1"
  sed -i '/^output_name/d' "${SUNSHINE_CONF}"
  echo "output_name = ${output}" >> "${SUNSHINE_CONF}"
}
