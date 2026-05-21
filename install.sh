#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEMD_USER="${HOME}/.config/systemd/user"
UNIT="${SYSTEMD_USER}/sunshine-vmon.service"

chmod +x \
  "${ROOT}/sunshine-vmon-common.sh" \
  "${ROOT}/sunshine-vmon-service.sh" \
  "${ROOT}/sunshine-start-vmon.sh" \
  "${ROOT}/sunshine-stop-vmon.sh" \
  "${ROOT}/sunshine-start-vmon-offmon.sh" \
  "${ROOT}/sunshine-stop-vmon-offmon.sh"

mkdir -p "${SYSTEMD_USER}"
cat > "${UNIT}" <<EOF
[Unit]
Description=Sunshine virtual monitor (persistent, disabled when idle)
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=${ROOT}/sunshine-vmon-service.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical-session.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now sunshine-vmon.service

echo "Monitor virtual persistente ativo (sunshine-vmon.service)."
echo "Scripts em: ${ROOT}"
