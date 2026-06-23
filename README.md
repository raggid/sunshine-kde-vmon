# sunshine-kde-vmon

Scripts para streaming com [Sunshine](https://github.com/LizardByte/Sunshine) no KDE Plasma (Wayland).

Três modos independentes:

- **vmon-simple** — monitor virtual criado por stream na resolução exata do cliente. Um serviço sentinela mantém um output fictício conectado para o Sunshine não ver "zero outputs". Recomendado.
- **vmon** — monitor virtual persistente criado no login (serviço systemd). Resolução fixa; funciona sem monitor físico.
- **headless** — compositor Wayland headless separado (labwc). O stream roda num desktop completamente isolado (painel, janelas, apps próprios), sem tocar na sessão KDE física.

## Apps no Moonlight

| App | Modo | Comportamento |
|-----|------|---------------|
| **Desktop** | vmon-simple | Monitor virtual ao lado do físico; resolução do cliente |
| **Desktop Exclusive** | vmon-simple | Monitor virtual como única saída; físico desligado durante o stream; resolução do cliente |
| **Steam Big Picture** | vmon-simple | Steam Big Picture no monitor virtual exclusivo; resolução do cliente |
| **Desktop (persistente)** | vmon | Monitor virtual ao lado do físico; resolução fixa (definida no serviço) |
| **Desktop Exclusive (persistente)** | vmon | Monitor virtual exclusivo; resolução fixa |
| **Desktop Headless** | headless | Desktop isolado no labwc; KDE físico intacto |
| **Steam Big Picture (Headless)** | headless | Steam Big Picture dentro do desktop headless |

## Instalação

```bash
git clone https://github.com/raggid/sunshine-kde-vmon.git ~/projects/sunshine-kde-vmon
cd ~/projects/sunshine-kde-vmon
./install.sh
```

O instalador pergunta qual modo habilitar e escreve os drop-ins para o `sunshine.service`. Veja `examples/apps.json` para os `prep-cmd` (substitua `/home/USER/` pelo caminho real).

Instalação não-interativa:

```bash
# vmon-simple + sem headless
SUNSHINE_VMON_MODE=simple SUNSHINE_LABWC_ENABLE_SERVICE=no ./install.sh

# vmon persistente + sem headless
SUNSHINE_VMON_MODE=service SUNSHINE_LABWC_ENABLE_SERVICE=no ./install.sh

# apenas headless
SUNSHINE_VMON_MODE=none SUNSHINE_LABWC_ENABLE_SERVICE=yes ./install.sh
```

## Estrutura

```
vmon-simple/ — monitor on-demand + serviço sentinela
vmon/        — monitor persistente (serviço no login)
headless/    — compositor labwc isolado
systemd/     — units e drop-ins de referência
examples/    — apps.json de exemplo para o Sunshine
install.sh   — instala o modo escolhido, units e drop-ins
```

## Requisitos

### vmon-simple e vmon
- KDE Plasma 6 (Wayland)
- `krfb-virtualmonitor` (pacote `krfb`)
- `kscreen-doctor` (pacote `kscreen`)
- `capture = kwin` no `sunshine.conf`

### headless
- `labwc`, `wlr-randr`
- `python-evdev`, `python-pywayland` (relay de input)
- `swaybg` (fallback de wallpaper)
- `capture = wlr` e `output_name = HEADLESS-1` no `sunshine.conf`
- Usuário no grupo `input`: `sudo usermod -aG input $USER` (requer logout)

## sunshine.conf

### vmon-simple / vmon

```ini
capture = kwin
output_name = Virtual-sunshine-vmon
```

### headless

```ini
capture = wlr
output_name = HEADLESS-1
```

## Serviços

```bash
# vmon-simple
systemctl --user status sunshine-sentinel.service

# vmon
systemctl --user status sunshine-vmon.service

# headless
systemctl --user status sunshine-labwc.service

# Inspecionar outputs KDE
kscreen-doctor -o

# Inspecionar output labwc
WAYLAND_DISPLAY=wayland-stream wlr-randr
```

## Recuperação

### vmon-simple / vmon — tela preta

O drop-in `sunshine.service.d/vmon-recovery.conf` (instalado automaticamente) executa o stop script via `ExecStopPost` sempre que o Sunshine para, inclusive em crash.

Recuperação manual:

```bash
# vmon-simple
./vmon-simple/stop.sh

# vmon
./vmon/sunshine-vmon-recover.sh

# De root no TTY:
sudo -u $USER \
  XDG_RUNTIME_DIR=/run/user/$(id -u $USER) \
  WAYLAND_DISPLAY=wayland-0 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u $USER)/bus \
  ./vmon/sunshine-vmon-recover.sh
```

### headless

```bash
./headless/sunshine-labwc-recover.sh
# ou
systemctl --user restart sunshine-labwc.service
```

## Variáveis de ambiente

| Variável | Padrão | Modo |
|----------|--------|------|
| `SUNSHINE_PRIMARY_OUTPUT` | _(auto)_ | vmon-simple, vmon |
| `SUNSHINE_VMON_NAME` | `sunshine-vmon` | vmon-simple, vmon |
| `SUNSHINE_VMON_PORT` | `5905` | vmon-simple, vmon |
| `SUNSHINE_SENTINEL_NAME` | `sunshine-idle` | vmon-simple |
| `SUNSHINE_SENTINEL_PORT` | `5906` | vmon-simple |
| `SUNSHINE_VMON_WIDTH/HEIGHT/FPS` | `1920/1080/60` | vmon (serviço persistente) |
| `SUNSHINE_LABWC_IDLE_WIDTH/HEIGHT/FPS` | `1920/1080/60` | headless |

## Licença

MIT
