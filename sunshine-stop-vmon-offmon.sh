#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=sunshine-vmon-common.sh
source "${SCRIPT_DIR}/sunshine-vmon-common.sh"

init_primary_output
apply_idle_layout
set_sunshine_output "${PRIMARY_OUTPUT}"
reload_sunshine_if_running
