#!/usr/bin/env bash

VMON_NAME="${SUNSHINE_VMON_NAME:-sunshine-vmon}"
VMON_OUTPUT="Virtual-${VMON_NAME}"
PRIMARY_OUTPUT=""
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

# Detecta o monitor fisico principal via kscreen (ignora Virtual-*)
detect_primary_output_name() {
  kscreen-doctor -j 2>/dev/null | python3 -c '
import json, sys

try:
    data = json.load(sys.stdin)
except (json.JSONDecodeError, ValueError):
    sys.exit(1)

physical = [
    o for o in data.get("outputs", [])
    if o.get("connected") and not str(o.get("name", "")).startswith("Virtual-")
]
if not physical:
    sys.exit(1)

for o in physical:
    if o.get("enabled") and o.get("priority") == 1:
        print(o["name"])
        sys.exit(0)

for o in physical:
    if o.get("enabled"):
        print(o["name"])
        sys.exit(0)

print(physical[0]["name"])
'
}

init_primary_output() {
  if [[ -n "${SUNSHINE_PRIMARY_OUTPUT:-}" ]]; then
    PRIMARY_OUTPUT="${SUNSHINE_PRIMARY_OUTPUT}"
  elif detected="$(detect_primary_output_name)"; then
    PRIMARY_OUTPUT="${detected}"
  else
    PRIMARY_OUTPUT="DP-1"
  fi
  export PRIMARY_OUTPUT
}

any_physical_output_present() {
  detect_primary_output_name >/dev/null 2>&1
}

primary_output_present() {
  [[ -n "${PRIMARY_OUTPUT}" ]] || init_primary_output
  kscreen-doctor -o 2>/dev/null | grep -qF "${PRIMARY_OUTPUT}"
}

virtual_output_present() {
  kscreen-doctor -o 2>/dev/null | grep -qF "${VMON_OUTPUT}"
}

wait_for_plasma_outputs() {
  local timeout="${1:-90}"
  local elapsed=0

  while (( elapsed < timeout )); do
    if kscreen_outputs_ready && any_physical_output_present; then
      init_primary_output
      if primary_output_present; then
        return 0
      fi
    fi
    sleep 1
    ((elapsed++))
  done

  init_primary_output
  echo "sunshine-vmon: KDE/Plasma ou monitor fisico nao disponivel apos ${timeout}s (esperado: ${PRIMARY_OUTPUT})." >&2
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
  init_primary_output
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

# output_name no sunshine.conf e lido no startup; reinicia o servico apos mudar o display
reload_sunshine_if_running() {
  if systemctl --user is-active sunshine.service >/dev/null 2>&1; then
    systemctl --user restart sunshine.service
  fi
}
