#!/usr/bin/env bash
# Sunshine prep-cmd for the labwc headless stream mode.
#
# Sets the labwc virtual output to the client's requested resolution.
# Does not touch the physical KDE desktop.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=sunshine-labwc-common.sh
source "${SCRIPT_DIR}/sunshine-labwc-common.sh"

import_session_env

if ! labwc_is_running; then
  echo "sunshine-start-labwc: labwc compositor is not running." >&2
  echo "  Start sunshine-labwc.service first:" >&2
  echo "    systemctl --user start sunshine-labwc.service" >&2
  exit 1
fi

resolve_client_resolution

# Retry loop mirrors Polaris: wlr-randr occasionally needs a moment if
# labwc just restarted and the output is not yet fully initialised.
applied=false
for i in $(seq 1 20); do
  if set_labwc_mode "${WIDTH}" "${HEIGHT}" "${FPS}" 2>/dev/null; then
    applied=true
    break
  fi
  sleep 0.2
done

if [[ "${applied}" != "true" ]]; then
  echo "sunshine-start-labwc: failed to set ${WIDTH}x${HEIGHT}@${FPS}Hz on ${LABWC_OUTPUT}." >&2
  exit 1
fi

# Keep sunshine.conf pointing at the labwc output (idempotent).
set_sunshine_output "${LABWC_OUTPUT}"

echo "sunshine-start-labwc: stream started at ${WIDTH}x${HEIGHT}@${FPS}Hz on ${LABWC_OUTPUT}" >&2

# If plasmashell was killed by a previous Steam Big Picture session, revive it
# so Desktop Headless gets a full KDE desktop again.
if command -v plasmashell >/dev/null 2>&1 && ! pgrep -x plasmashell >/dev/null 2>&1; then
  echo "sunshine-start-labwc: restarting plasmashell" >&2
  WAYLAND_DISPLAY="${LABWC_SOCKET_LINK_NAME}" \
  XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR}" \
  QT_QPA_PLATFORM=wayland \
  KDE_FULL_SESSION=true \
  PLASMA_USE_QT_SCALING=1 \
    dbus-run-session -- plasmashell 2>/dev/null &
  echo "$!" > "$(_plasmashell_pid_file)"
fi
