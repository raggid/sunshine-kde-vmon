#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=sunshine-vmon-common.sh
source "${SCRIPT_DIR}/sunshine-vmon-common.sh"

ensure_virtual_monitor
apply_custom_mode
resolve_client_resolution

# Troca atomica: virtual ligado antes de desligar o fisico (evita "nenhum monitor")
kscreen-doctor \
  "output.${VMON_OUTPUT}.enable" \
  "output.${VMON_OUTPUT}.mode.${RES}@${FPS}" \
  "output.${VMON_OUTPUT}.priority.1" \
  "output.${PRIMARY_OUTPUT}.disable"

set_sunshine_output "${VMON_OUTPUT}"
