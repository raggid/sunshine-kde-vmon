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

# plasmashell is not needed for Steam gamepadui; killing it frees RAM and
# avoids any compositor z-order confusion with a fullscreen Steam window.
pkill -x plasmashell 2>/dev/null || true

# Steam uses a single-instance IPC pipe (~/.steam/steam.pipe). Any new
# invocation sends its arguments to the already-running instance and exits,
# even with a different WAYLAND_DISPLAY. Kill the physical-desktop Steam so
# the new invocation starts a fresh process connected to labwc.
echo "[steam-bp] stopping existing Steam instance" >&2
pkill -x steam 2>/dev/null || true
sleep 2

echo "[steam-bp] starting Steam gamepadui on ${WAYLAND_DISPLAY}" >&2
exec steam -gamepadui
