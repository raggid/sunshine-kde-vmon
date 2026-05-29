#!/usr/bin/env bash
# Recovery for the labwc headless stream mode.
#
# Unlike the vmon mode, there is no physical display state to restore —
# just restart the compositor service and let Sunshine reconnect.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=sunshine-labwc-common.sh
source "${SCRIPT_DIR}/sunshine-labwc-common.sh"

import_session_env

echo "sunshine-labwc-recover: restarting sunshine-labwc.service..."

if systemctl --user restart sunshine-labwc.service; then
  echo "sunshine-labwc-recover: service restarted."
  echo "  Sunshine will reconnect automatically when the socket reappears."
else
  echo "sunshine-labwc-recover: restart failed — check:" >&2
  echo "  journalctl --user -u sunshine-labwc.service" >&2
  exit 1
fi
