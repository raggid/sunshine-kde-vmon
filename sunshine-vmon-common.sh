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

kscreen_outputs_ready() {
  kscreen-doctor -o >/dev/null 2>&1
}

primary_output_present() {
  kscreen-doctor -o 2>/dev/null | grep -qF "${PRIMARY_OUTPUT}"
}

virtual_output_present() {
  kscreen-doctor -o 2>/dev/null | grep -qF "${VMON_OUTPUT}"
}

wait_for_plasma_outputs() {
  local timeout="${1:-90}"
  local elapsed=0

  while (( elapsed < timeout )); do
    if kscreen_outputs_ready && primary_output_present; then
      return 0
    fi
    sleep 1
    ((elapsed++))
  done

  echo "sunshine-vmon: KDE/Plasma ou ${PRIMARY_OUTPUT} nao disponivel apos ${timeout}s." >&2
  return 1
}

wait_for_virtual_output() {
  local timeout="${1:-30}"
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

# Sempre religa o monitor fisico (corrige layout salvo pelo modo Exclusive apos crash/reboot)
ensure_primary_monitor() {
  if ! primary_output_present; then
    echo "sunshine-vmon: saida ${PRIMARY_OUTPUT} nao encontrada." >&2
    return 1
  fi

  kscreen-doctor \
    "output.${PRIMARY_OUTPUT}.enable" \
    "output.${PRIMARY_OUTPUT}.priority.1"
}

disable_virtual_monitor() {
  if ! virtual_output_present; then
    return 0
  fi

  kscreen-doctor "output.${VMON_OUTPUT}.disable"
}

# Layout seguro fora do stream: fisico ligado, virtual desligado
apply_idle_layout() {
  ensure_primary_monitor || return 1

  if virtual_output_present; then
    disable_virtual_monitor
  fi

  ensure_primary_monitor
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

  if ! wait_for_virtual_output 30; then
    echo "sunshine-vmon: monitor virtual '${VMON_OUTPUT}' nao apareceu a tempo." >&2
    echo "sunshine-vmon: verifique sunshine-vmon.service ou execute ./install.sh" >&2
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
