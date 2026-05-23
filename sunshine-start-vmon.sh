#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=sunshine-vmon-common.sh
source "${SCRIPT_DIR}/sunshine-vmon-common.sh"

init_primary_output
ensure_virtual_monitor
apply_custom_mode
resolve_client_resolution

# Liga o virtual como primario; monitor fisico permanece ligado
kscreen-doctor \
  "output.${VMON_OUTPUT}.enable" \
  "output.${VMON_OUTPUT}.mode.${RES}@${FPS}" \
  "output.${VMON_OUTPUT}.priority.1"

set_sunshine_output "${VMON_OUTPUT}"
