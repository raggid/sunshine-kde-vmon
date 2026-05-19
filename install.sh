#!/usr/bin/env bash
set -euo pipefail

DEST="${HOME}/.local/bin"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

install -m 755 \
  "${ROOT}/sunshine-start-vmon.sh" \
  "${ROOT}/sunshine-stop-vmon.sh" \
  "${ROOT}/sunshine-start-vmon-offmon.sh" \
  "${ROOT}/sunshine-stop-vmon-offmon.sh" \
  "${DEST}/"

echo "Scripts instalados em ${DEST}"
