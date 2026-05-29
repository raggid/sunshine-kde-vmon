#!/usr/bin/env bash
# Launch Steam Big Picture inside the labwc stream desktop.
#
# Problem: Steam is a single-instance app. If Steam is already running on the
# physical KDE desktop, "steam steam://open/bigpicture" sends the URL to the
# existing KDE instance (via ~/.steam/steam.pipe) — it never opens in labwc.
#
# Solution: use gamescope, which creates a completely isolated nested compositor.
# Steam runs inside gamescope as a fresh session, independent of the KDE one.
# Without gamescope, we kill the existing Steam instance and restart it inside
# labwc (disruptive but functional).
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

WIDTH="${SUNSHINE_CLIENT_WIDTH:-1920}"
HEIGHT="${SUNSHINE_CLIENT_HEIGHT:-1080}"

# Steam uses a single-instance IPC pipe (~/.steam/steam.pipe).  Any new
# "steam" invocation sends its arguments to the already-running instance and
# exits — even inside gamescope.  We must kill the existing Steam first so
# gamescope gets a real Steam process as its client.
echo "[steam-bp] stopping existing Steam instance" >&2
pkill -x steam 2>/dev/null || true
sleep 2

if command -v gamescope &>/dev/null; then
    echo "[steam-bp] using gamescope ${WIDTH}x${HEIGHT}" >&2
    # -e  : Steam integration mode (overlay, HDR hints, etc.)
    # -f  : fullscreen inside the outer compositor (labwc)
    # -W/-H: resolution presented to Sunshine's screen capture
    exec gamescope \
        -W "${WIDTH}" -H "${HEIGHT}" \
        -w "${WIDTH}" -h "${HEIGHT}" \
        -e -f \
        -- steam -gamepadui
else
    exec steam -gamepadui
fi
