#!/usr/bin/env bash
# Recuperacao de tela preta. Rode como o MESMO usuario da sessao grafica.
# TTY: login normal (nao root). SSH tambem funciona.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=sunshine-vmon-common.sh
source "${SCRIPT_DIR}/sunshine-vmon-common.sh"

export QT_QPA_PLATFORM=wayland
unset WAYLAND_DISPLAY  # ensure detection finds KDE's socket, not labwc's
import_plasma_session_env

echo "sunshine-vmon-recover: XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}"
echo "sunshine-vmon-recover: WAYLAND_DISPLAY=${WAYLAND_DISPLAY}"
echo "sunshine-vmon-recover: DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-nao definido}"
echo "sunshine-vmon-recover: QT_QPA_PLATFORM=${QT_QPA_PLATFORM}"

init_primary_output
set_sunshine_output "${VMON_OUTPUT}"
echo "sunshine-vmon-recover: monitor fisico alvo: ${PRIMARY_OUTPUT}"

if ! kscreen_outputs_ready; then
  echo "sunshine-vmon-recover: ERRO - kscreen-doctor nao alcanca o Plasma." >&2
  echo "  - Faca login na sessao grafica (nao use su root)" >&2
  echo "  - Ou: sudo -u ${USER} DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus \\" >&2
  echo "         WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/run/user/$(id -u) $0" >&2
  exit 1
fi

echo "sunshine-vmon-recover: religando monitores fisicos..."
force_enable_all_physical || ensure_primary_monitor || true
disable_virtual_monitor || true
ensure_primary_monitor || force_enable_all_physical || true

init_primary_output
set_sunshine_output "${PRIMARY_OUTPUT}"

if systemctl --user is-active sunshine.service >/dev/null 2>&1; then
  systemctl --user restart sunshine.service
fi

echo ""
echo "Estado atual:"
kscreen-doctor -o 2>/dev/null | grep -E 'Output:|enabled|disabled' || true

echo ""
echo "sunshine-vmon-recover: concluido."
