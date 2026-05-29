#!/usr/bin/env bash
# Launch Steam Big Picture inside the labwc stream desktop.
#
# Kills plasmashell (not needed; Steam gamepadui is the whole UI) and any
# existing Steam instance (single-instance IPC would otherwise redirect the
# launch to the physical desktop Steam), then starts Steam in gamepadui mode
# pointing at the labwc compositor.
#
# Usage in apps.json "detached":
#   setsid /path/to/sunshine-steam-bigpicture.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=sunshine-labwc-common.sh
source "${SCRIPT_DIR}/sunshine-labwc-common.sh"

import_session_env

ENV_FILE="$(_env_file)"
if [[ -f "${ENV_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${ENV_FILE}"
else
    export WAYLAND_DISPLAY="${LABWC_SOCKET_LINK_NAME}"
fi

export AT_SPI_BUS_ADDRESS=

# plasmashell is not needed for Steam gamepadui; kill only the labwc instance
# (tracked by the service) so the physical KDE plasmashell is not affected.
PS_PID_FILE="${XDG_RUNTIME_DIR}/sunshine-labwc/plasmashell.pid"
if [[ -f "${PS_PID_FILE}" ]]; then
    kill -TERM "$(cat "${PS_PID_FILE}")" 2>/dev/null || true
    rm -f "${PS_PID_FILE}"
fi

# Steam uses a single-instance IPC pipe (~/.steam/steam.pipe). Any new
# invocation delegates to the running instance and exits immediately, even
# with a different WAYLAND_DISPLAY. pkill -x steam kills only the main
# process; helpers (steamwebhelper, pressure-vessel, etc.) keep the pipe
# alive. Kill everything steam-related and wait for the pipe to vanish.
echo "[steam-bp] stopping all Steam processes" >&2
pkill -f steam 2>/dev/null || true
for _i in $(seq 1 40); do
    [[ -e "${HOME}/.steam/steam.pipe" ]] || break
    sleep 0.25
done
# Final hard kill if anything survived
pkill -KILL -f steam 2>/dev/null || true
sleep 0.5

LOG="${XDG_RUNTIME_DIR}/sunshine-labwc/steam-bigpicture.log"
echo "[steam-bp] starting Steam gamepadui on ${WAYLAND_DISPLAY}" >&2
echo "[steam-bp] log: ${LOG}" >&2
exec steam -gamepadui > "${LOG}" 2>&1
