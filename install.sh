#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEMD_USER="${HOME}/.config/systemd/user"
UNIT="${SYSTEMD_USER}/sunshine-vmon.service"
ENABLE_SERVICE="${SUNSHINE_VMON_ENABLE_SERVICE:-ask}"

chmod +x \
  "${ROOT}/sunshine-vmon-common.sh" \
  "${ROOT}/sunshine-vmon-service.sh" \
  "${ROOT}/sunshine-vmon-recover.sh" \
  "${ROOT}/sunshine-start-vmon.sh" \
  "${ROOT}/sunshine-stop-vmon.sh" \
  "${ROOT}/sunshine-start-vmon-offmon.sh" \
  "${ROOT}/sunshine-stop-vmon-offmon.sh"

mkdir -p "${SYSTEMD_USER}"
cat > "${UNIT}" <<EOF
[Unit]
Description=Sunshine virtual monitor (persistent, disabled when idle)
After=graphical-session.target plasma-workspace.target
Wants=graphical-session.target

[Service]
Type=simple
Environment=WAYLAND_DISPLAY=wayland-0
Environment=XDG_RUNTIME_DIR=/run/user/%U
ExecStartPre=/bin/sleep 12
ExecStart=${ROOT}/sunshine-vmon-service.sh
Restart=on-failure
RestartSec=10
TimeoutStartSec=120

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload

do_enable=false
case "${ENABLE_SERVICE}" in
  1|yes|true)
    do_enable=true
    ;;
  0|no|false)
    do_enable=false
    ;;
  ask|*)
    echo ""
    echo "O servico sunshine-vmon roda no login e pode afetar o layout de monitores."
    echo "Versoes anteriores causaram tela preta se o fisico ficou desligado no KDE."
    echo "A versao atual corrige isso, mas teste antes de habilitar no boot."
    echo ""
    read -r -p "Habilitar sunshine-vmon.service agora? [s/N] " reply
    if [[ "${reply}" =~ ^[sSyY] ]]; then
      do_enable=true
    fi
    ;;
esac

if [[ "${do_enable}" == true ]]; then
  systemctl --user enable --now sunshine-vmon.service
  echo "sunshine-vmon.service habilitado."
else
  systemctl --user disable sunshine-vmon.service 2>/dev/null || true
  echo "Servico instalado mas NAO habilitado no boot."
  echo "Para testar manualmente: systemctl --user start sunshine-vmon.service"
fi

echo ""
echo "Scripts em: ${ROOT}"
echo "Recuperacao de tela preta: ${ROOT}/sunshine-vmon-recover.sh"
