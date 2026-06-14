# sunshine-kde-vmon

Scripts para streaming com [Sunshine](https://github.com/LizardByte/Sunshine) no KDE Plasma (Wayland).

Dois modos independentes:

- **vmon** — monitor virtual dentro da sessão KDE. O desktop físico continua visível; o stream captura apenas o monitor virtual.
- **headless** — compositor Wayland headless separado (labwc). O stream roda num desktop completamente isolado (painel, janelas, apps próprios), sem tocar na sessão KDE física.

## Apps no Moonlight

| App | Modo | Comportamento |
|-----|------|---------------|
| **Desktop** | vmon | Monitor virtual ao lado do físico; os dois coexistem |
| **Desktop Exclusive** | vmon | Monitor virtual como única saída ativa; físico desligado durante o stream |
| **Steam Big Picture** | vmon | Steam Big Picture no monitor virtual exclusivo; abre/fecha via `steam://` sem reiniciar o Steam |
| **Desktop Headless** | headless | Desktop KDE (plasmashell) isolado no labwc; o físico fica intacto |
| **Steam Big Picture (Headless)** | headless | Steam Big Picture dentro do desktop headless |

## Instalação

```bash
git clone https://github.com/raggid/sunshine-kde-vmon.git ~/projects/sunshine-kde-vmon
cd ~/projects/sunshine-kde-vmon
./install.sh
```

O instalador habilita os serviços e escreve os drop-ins para o `sunshine.service`. Veja `examples/apps.json` para os `prep-cmd` (substitua `/home/USER/` pelo caminho real).

## Estrutura

```
vmon/       — scripts do modo vmon e biblioteca compartilhada
headless/   — scripts do modo headless (labwc) e biblioteca compartilhada
systemd/    — units e drop-ins de referência
examples/   — apps.json de exemplo para o Sunshine
install.sh  — instala ambos os modos, units e drop-ins
```

## Requisitos

### vmon
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

## Configuração

### Monitor físico (vmon)

```bash
kscreen-doctor -o
```

Detectado automaticamente. Para forçar um conector:

```bash
export SUNSHINE_PRIMARY_OUTPUT=DP-1
```

### Resolução padrão

```bash
# ~/.config/systemd/user/sunshine-vmon.service.d/override.conf
[Service]
Environment=SUNSHINE_VMON_WIDTH=1920
Environment=SUNSHINE_VMON_HEIGHT=1080
Environment=SUNSHINE_VMON_FPS=60
```

### Serviços

```bash
systemctl --user status sunshine-vmon.service
systemctl --user status sunshine-labwc.service
```

## Recuperação

### vmon — tela preta

O drop-in `sunshine.service.d/vmon-recovery.conf` (instalado automaticamente) executa `vmon/sunshine-stop-vmon.sh` via `ExecStopPost` sempre que o Sunshine para, inclusive em crash. A recuperação manual só é necessária se o drop-in não estiver instalado.

```bash
./vmon/sunshine-vmon-recover.sh
# De root no TTY:
sudo -u raggid \
  XDG_RUNTIME_DIR=/run/user/1000 \
  WAYLAND_DISPLAY=wayland-0 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
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
| `SUNSHINE_PRIMARY_OUTPUT` | _(auto)_ | vmon |
| `SUNSHINE_VMON_WIDTH/HEIGHT/FPS` | `1920/1080/60` | vmon |
| `SUNSHINE_LABWC_IDLE_WIDTH/HEIGHT/FPS` | `1920/1080/60` | headless |

## Licença

MIT
