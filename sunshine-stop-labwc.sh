#!/usr/bin/env bash
# Sunshine undo-cmd for the labwc headless stream mode.
#
# Resets the labwc virtual output back to its idle resolution.
# The compositor keeps running; only the mode changes.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=sunshine-labwc-common.sh
source "${SCRIPT_DIR}/sunshine-labwc-common.sh"

import_session_env

if labwc_is_running; then
  set_labwc_mode "${LABWC_IDLE_WIDTH}" "${LABWC_IDLE_HEIGHT}" "${LABWC_IDLE_FPS}" 2>/dev/null || true
fi

echo "sunshine-stop-labwc: reset to idle ${LABWC_IDLE_WIDTH}x${LABWC_IDLE_HEIGHT}@${LABWC_IDLE_FPS}Hz" >&2
