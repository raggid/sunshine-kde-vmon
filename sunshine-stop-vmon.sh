#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=sunshine-vmon-common.sh
source "${SCRIPT_DIR}/sunshine-vmon-common.sh"

unset WAYLAND_DISPLAY  # Sunshine inherits wayland-stream; vmon needs KDE's socket
import_plasma_session_env
init_primary_output
apply_idle_layout
set_sunshine_output "${PRIMARY_OUTPUT}"
