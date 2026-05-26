#!/usr/bin/env bash
# Perfil Exclusive (Android/jogos): tudo no client; fisico desligado no KDE apos virtual pronto.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=sunshine-vmon-common.sh
source "${SCRIPT_DIR}/sunshine-vmon-common.sh"

import_plasma_session_env
trap '[[ $? -ne 0 ]] && abort_stream_layout' EXIT

init_primary_output
ensure_virtual_monitor || exit 1
apply_custom_mode

# 1) Virtual ligado com fisico ainda ativo
kscreen-doctor \
  "output.${VMON_OUTPUT}.enable" \
  "output.${VMON_OUTPUT}.mode.${RES}@${FPS}" \
  "output.${VMON_OUTPUT}.priority.1"

sleep 2

if ! virtual_output_enabled; then
  echo "sunshine-vmon: ${VMON_OUTPUT} nao ficou habilitado." >&2
  exit 1
fi

# 2) Sunshine relera output_name ao iniciar o stream (apos prep-cmd terminar);
#    reiniciar aqui causaria um loop: sunshine morre → Moonlight reconecta → prep-cmd roda de novo.
set_sunshine_output "${VMON_OUTPUT}"

# 3) Desliga o monitor fisico; sunshine ainda nao iniciou o screencast (esta no prep-cmd)
kscreen-doctor "output.${PRIMARY_OUTPUT}.disable"

if ! virtual_output_enabled; then
  echo "sunshine-vmon: virtual desabilitado apos desligar o fisico." >&2
  exit 1
fi

trap - EXIT
