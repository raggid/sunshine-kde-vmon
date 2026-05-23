#!/usr/bin/env bash
# Recuperacao de tela preta: religa o monitor fisico e desliga o virtual.
# Execute em TTY (Ctrl+Alt+F3) ou SSH se a sessao grafica estiver preta.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=sunshine-vmon-common.sh
source "${SCRIPT_DIR}/sunshine-vmon-common.sh"

export DISPLAY="${DISPLAY:-:0}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

echo "sunshine-vmon-recover: religando ${PRIMARY_OUTPUT}..."

if wait_for_plasma_outputs 30; then
  apply_idle_layout && echo "sunshine-vmon-recover: layout restaurado." && exit 0
fi

echo "sunshine-vmon-recover: kscreen indisponivel; tentando mesmo assim..." >&2
kscreen-doctor \
  "output.${PRIMARY_OUTPUT}.enable" \
  "output.${PRIMARY_OUTPUT}.priority.1" 2>/dev/null || true

if virtual_output_present; then
  kscreen-doctor "output.${VMON_OUTPUT}.disable" 2>/dev/null || true
fi

echo "sunshine-vmon-recover: concluido. Se a tela continuar preta, reinicie o Plasma ou o PC."
