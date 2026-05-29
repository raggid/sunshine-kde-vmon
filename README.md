# sunshine-kde-vmon

Scripts para streaming com [Sunshine](https://github.com/LizardByte/Sunshine) no KDE Plasma (Wayland).

Dois modos independentes:

- **vmon** — monitor virtual dentro da sessão KDE. O desktop físico continua visível; o stream captura apenas o monitor virtual.
- **labwc** — compositor Wayland headless separado. O stream roda num desktop completamente isolado (painel, janelas, apps próprios), sem tocar na sessão KDE física.

## Três apps no Moonlight

| App | Modo | Comportamento |
|-----|------|---------------|
| **Desktop** | vmon | Monitor virtual ligado ao lado do físico; os dois coexistem |
| **Desktop Headless** | labwc | Desktop KDE (plasmashell) isolado; o físico fica intacto |
| **Steam Big Picture** | labwc | Steam Big Picture dentro do desktop headless |

## Instalação

```bash
git clone https://github.com/raggid/sunshine-kde-vmon.git ~/projects/sunshine-kde-vmon
cd ~/projects/sunshine-kde-vmon
./install.sh
```

O instalador habilita os serviços e escreve o drop-in para o `sunshine.service`. Veja `examples/apps.json` para os `prep-cmd` (substitua `/home/USER/` pelo caminho real).

## Requisitos

### vmon mode
- KDE Plasma 6 (Wayland)
- `krfb-virtualmonitor` (pacote `krfb`)
- `kscreen-doctor` (pacote `kscreen`)
- `capture = kwin` no `sunshine.conf`

### labwc mode
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

```bash
./sunshine-vmon-recover.sh
# De root no TTY:
sudo -u raggid \
  XDG_RUNTIME_DIR=/run/user/1000 \
  WAYLAND_DISPLAY=wayland-0 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
  ./sunshine-vmon-recover.sh
```

### labwc

```bash
./sunshine-labwc-recover.sh
# ou
systemctl --user restart sunshine-labwc.service
```

## Variáveis de ambiente

| Variável | Padrão | Modo |
|----------|--------|------|
| `SUNSHINE_PRIMARY_OUTPUT` | _(auto)_ | vmon |
| `SUNSHINE_VMON_WIDTH/HEIGHT/FPS` | `1920/1080/60` | vmon |
| `SUNSHINE_LABWC_IDLE_WIDTH/HEIGHT/FPS` | `1920/1080/60` | labwc |

## Licença

MIT
