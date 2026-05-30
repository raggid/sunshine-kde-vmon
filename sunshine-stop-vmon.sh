#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=sunshine-vmon-common.sh
source "${SCRIPT_DIR}/sunshine-vmon-common.sh"

unset WAYLAND_DISPLAY
import_plasma_session_env
init_primary_output
apply_idle_layout
# Restore primary output to origin after vmon is disabled.
kscreen-doctor "output.${PRIMARY_OUTPUT}.position.0,0" 2>/dev/null || true
