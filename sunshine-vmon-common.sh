#!/usr/bin/env bash

VMON_NAME="${SUNSHINE_VMON_NAME:-sunshine-vmon}"
VMON_OUTPUT="Virtual-${VMON_NAME}"
PRIMARY_OUTPUT=""
SUNSHINE_CONF="${HOME}/.config/sunshine/sunshine.conf"
VMON_PORT="${SUNSHINE_VMON_PORT:-5905}"
VMON_PASSWORD="${SUNSHINE_VMON_PASSWORD:-sunshinepass}"

import_plasma_session_env() {
  local uid
  uid="$(id -u)"
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/${uid}}"

  if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" && -S "${XDG_RUNTIME_DIR}/bus" ]]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
  fi

  if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
    local wl_socket labwc_sock_name labwc_target
    # If labwc is running, its socket is reachable via the wayland-stream symlink.
    # Exclude it so kscreen-doctor connects to KDE, not labwc.
    labwc_sock_name=""
    if [[ -L "${XDG_RUNTIME_DIR}/wayland-stream" ]]; then
      labwc_target="$(readlink -f "${XDG_RUNTIME_DIR}/wayland-stream" 2>/dev/null)"
      labwc_sock_name="${labwc_target##*/}"
    fi
    wl_socket="$(find "${XDG_RUNTIME_DIR}" -maxdepth 1 -name 'wayland-[0-9]*' -type s 2>/dev/null \
      | grep -v "/${labwc_sock_name}$" | head -1)"
    if [[ -n "${wl_socket}" ]]; then
      export WAYLAND_DISPLAY="${wl_socket##*/}"
    else
      export WAYLAND_DISPLAY="wayland-0"
    fi
  fi

  export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland}"
}

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

virtual_output_enabled() {
  kscreen-doctor -j 2>/dev/null | python3 -c "
import json, sys
name = \"${VMON_OUTPUT}\"
data = json.load(sys.stdin)
for o in data.get('outputs', []):
    if o.get('name') == name:
        print('yes' if o.get('enabled') else 'no')
        sys.exit(0)
print('no')
" | grep -q '^yes$'
}

wait_for_plasma_outputs() {
  local timeout="${1:-90}"
  local elapsed=0

  import_plasma_session_env

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

# Liga todos os monitores fisicos conectados (fallback agressivo no recover)
force_enable_all_physical() {
  import_plasma_session_env
  kscreen-doctor -j 2>/dev/null | python3 -c '
import json, subprocess, sys

data = json.load(sys.stdin)
cmds = []
primary = None

for o in data.get("outputs", []):
    name = o.get("name", "")
    if not o.get("connected") or name.startswith("Virtual-"):
        continue
    if o.get("enabled") and o.get("priority") == 1:
        primary = name
    cmds.append(name)

if not cmds:
    sys.exit(1)

if not primary:
    primary = cmds[0]

for name in cmds:
    if name != primary:
        subprocess.run(
            ["kscreen-doctor", f"output.{name}.enable"],
            check=False,
        )

subprocess.run(
    ["kscreen-doctor", f"output.{primary}.enable", f"output.{primary}.priority.1"],
    check=False,
)
' || return 1
  init_primary_output
}

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

apply_idle_layout() {
  import_plasma_session_env

  if ! kscreen_outputs_ready; then
    echo "sunshine-vmon: kscreen-doctor indisponivel (sessao Plasma?)" >&2
    return 1
  fi

  force_enable_all_physical || ensure_primary_monitor || true

  if virtual_output_present; then
    disable_virtual_monitor || true
    # KDE's kscreen config restore may re-enable the virtual output after krfb
    # registers it. Retry until it actually stays disabled (up to 3 seconds).
    local _i
    for _i in $(seq 1 6); do
      sleep 0.5
      if virtual_output_enabled; then
        disable_virtual_monitor || true
      else
        break
      fi
    done
  fi

  ensure_primary_monitor || force_enable_all_physical
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
    return 1
  fi
}

apply_custom_mode() {
  resolve_client_resolution
  kscreen-doctor "output.${VMON_OUTPUT}.addCustomMode.${WIDTH}.${HEIGHT}.${FPS_MHZ}.full" 2>/dev/null || true
}

set_sunshine_capture() {
  local method="$1"
  sed -i '/^capture/d' "${SUNSHINE_CONF}"
  echo "capture = ${method}" >> "${SUNSHINE_CONF}"
}

set_sunshine_output() {
  local output="$1"
  sed -i '/^output_name/d' "${SUNSHINE_CONF}"
  echo "output_name = ${output}" >> "${SUNSHINE_CONF}"
}

# Restaura layout + sunshine.conf apos falha no prep-cmd (undo nao chegou a rodar)
abort_stream_layout() {
  echo "sunshine-vmon: restaurando layout apos falha..." >&2
  apply_idle_layout || force_enable_all_physical || true
  init_primary_output
  set_sunshine_output "${PRIMARY_OUTPUT}"
}
