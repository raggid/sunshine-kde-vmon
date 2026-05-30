#!/usr/bin/env bash
# Launch Steam Big Picture on the KDE vmon stream desktop.
#
# Kills any existing Steam instance (single-instance IPC would otherwise
# redirect the launch to the physical-desktop Steam), then starts Steam
# in gamepadui mode on the KDE Wayland session.
#
# Usage in apps.json "detached":
#   setsid /path/to/sunshine-steam-bigpicture-vmon.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=sunshine-vmon-common.sh
source "${SCRIPT_DIR}/sunshine-vmon-common.sh"

unset WAYLAND_DISPLAY
import_plasma_session_env

echo "[steam-bp-vmon] stopping all Steam processes" >&2
pkill -x steam 2>/dev/null || true
pkill -f '/Steam/' 2>/dev/null || true
pkill -f 'steamwebhelper' 2>/dev/null || true
for _i in $(seq 1 40); do
    [[ -e "${HOME}/.steam/steam.pipe" ]] || break
    sleep 0.25
done
rm -f "${HOME}/.steam/steam.pipe" 2>/dev/null || true
sleep 0.5

LOG="${XDG_RUNTIME_DIR}/sunshine-vmon/steam-bigpicture.log"
mkdir -p "${XDG_RUNTIME_DIR}/sunshine-vmon"
echo "[steam-bp-vmon] starting Steam gamepadui on ${WAYLAND_DISPLAY}" >&2
echo "[steam-bp-vmon] log: ${LOG}" >&2
exec steam -gamepadui > "${LOG}" 2>&1
