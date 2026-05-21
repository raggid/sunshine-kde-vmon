#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=sunshine-vmon-common.sh
source "${SCRIPT_DIR}/sunshine-vmon-common.sh"

# Religa o fisico primeiro, depois desliga o virtual
kscreen-doctor \
  "output.${PRIMARY_OUTPUT}.enable" \
  "output.${PRIMARY_OUTPUT}.priority.1" \
  "output.${VMON_OUTPUT}.disable"

set_sunshine_output "${PRIMARY_OUTPUT}"
