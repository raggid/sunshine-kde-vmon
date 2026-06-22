#!/usr/bin/env bash
# prep-cmd undo — restaura o físico e destrói o vmon.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../vmon/sunshine-vmon-common.sh
source "${SCRIPT_DIR}/../vmon/sunshine-vmon-common.sh"

unset WAYLAND_DISPLAY
import_plasma_session_env

init_primary_output
apply_idle_layout
kscreen-doctor "output.${PRIMARY_OUTPUT}.position.0,0" 2>/dev/null || true

pkill -f "krfb-virtualmonitor.*--name ${VMON_NAME}" 2>/dev/null || true
