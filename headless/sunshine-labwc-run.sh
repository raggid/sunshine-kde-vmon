#!/usr/bin/env bash
# Wrapper: run a command inside the labwc stream desktop.
#
# Use this as the command prefix in Sunshine's apps.json or web UI:
#   /path/to/sunshine-labwc-run.sh steam
#   /path/to/sunshine-labwc-run.sh %command%   (Steam launch option)
#
# Sets WAYLAND_DISPLAY and DISPLAY (if Xwayland is running) so the app
# renders inside the isolated stream compositor, not on the KDE desktop.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=sunshine-labwc-common.sh
source "${SCRIPT_DIR}/sunshine-labwc-common.sh"

import_session_env

if [[ $# -eq 0 ]]; then
  echo "Usage: $(basename "$0") <command> [args...]" >&2
  exit 1
fi

# Source the env file the service writes at startup.
ENV_FILE="$(_env_file)"
if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck source=/dev/null
  source "${ENV_FILE}"
else
  # Fallback: use the stable socket link directly.
  export WAYLAND_DISPLAY="${LABWC_SOCKET_LINK_NAME}"
fi

# Suppress at-spi2 interference (can cause hangs in Steam on some distros).
export AT_SPI_BUS_ADDRESS=

exec "$@"
