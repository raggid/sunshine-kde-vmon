# sunshine-kde-vmon

Scripts para streaming com [Sunshine](https://github.com/LizardByte/Sunshine) no KDE Plasma (Wayland), usando monitor virtual (`krfb-virtualmonitor`) e `kscreen-doctor`.

O monitor virtual fica **sempre criado** (serviço systemd) e é apenas **ligado/desligado** ao iniciar ou terminar o stream. Isso evita o erro do Sunshine de “nenhum monitor conectado” quando o monitor físico está desligado.

## Arquitetura

```
Login → sunshine-vmon.service (krfb-virtualmonitor)
              ↓
        Virtual-sunshine-vmon existe, desabilitado no KDE
              ↓
Stream start → kscreen-doctor enable virtual (+ disable físico no modo Exclusive)
              ↓
Stream stop  → kscreen-doctor disable virtual, enable físico
              ↓
        krfb continua rodando em segundo plano
```

## Dois perfis no Moonlight

| App Sunshine | Quando usar | Monitor físico (host) | Monitor virtual | Moonlight vê |
|--------------|-------------|------------------------|-----------------|--------------|
| **Desktop** | Notebook como **segunda tela** do PC (trabalho, desktop estendido) | **Ligado** — você continua vendo e usando o ultrawide | Ligado, resolução do cliente | Só o virtual |
| **Desktop Exclusive** | Celular Android, **jogos / foco total** — nada deve aparecer no host | **Desligado** no KDE — tela física apagada | Ligado, único output ativo | Só o virtual |

São perfis **diferentes de propósito**, não redundantes:

- **Desktop** = dois monitores no KDE (físico + virtual), como um setup multi-monitor normal.
- **Exclusive** = um monitor só no host (o virtual); o físico fica off para privacidade e para não “vazar” imagem na sua mesa.

O Sunshine sempre captura `Virtual-sunshine-vmon` nos dois casos; a diferença é o que acontece **localmente** no quarto/escritório.

## Scripts

| Script | Descrição |
|--------|-----------|
| `sunshine-vmon-service.sh` | Serviço: cria o monitor virtual e deixa desabilitado |
| `sunshine-start-vmon.sh` | Perfil **Desktop**: virtual on, físico **permanece on** |
| `sunshine-stop-vmon.sh` | Desliga o virtual, físico continua on |
| `sunshine-start-vmon-offmon.sh` | Perfil **Exclusive**: virtual on, restart Sunshine, físico **off** |
| `sunshine-stop-vmon-offmon.sh` | Religa o físico, desliga o virtual |

## Requisitos

- KDE Plasma 6 (Wayland)
- [Sunshine](https://github.com/LizardByte/Sunshine) com `capture = kwin`
- `krfb-virtualmonitor` (pacote `krfb` no Arch)
- `kscreen-doctor` (pacote `kscreen`)

## Instalação

```bash
git clone https://github.com/raggid/sunshine-kde-vmon.git ~/projects/sunshine-kde-vmon
cd ~/projects/sunshine-kde-vmon
./install.sh
```

O `install.sh` habilita o serviço `sunshine-vmon.service` (monitor virtual persistente).

Aponte os `prep-cmd` do Sunshine para o diretório do clone (caminhos absolutos). Veja `examples/apps.json`.

## Configuração

### Monitor físico

```bash
kscreen-doctor -o
```

O monitor físico é **detectado automaticamente** via `kscreen-doctor` (no seu sistema: `DP-1`). Para forçar outro conector:

```bash
export SUNSHINE_PRIMARY_OUTPUT=DP-1
```

### Resolução padrão do monitor persistente

Definida no serviço (padrão 1920x1080). No início de cada stream, os scripts ajustam para a resolução do cliente (`SUNSHINE_CLIENT_*`).

```bash
# opcional, em ~/.config/systemd/user/sunshine-vmon.service.d/override.conf
[Service]
Environment=SUNSHINE_VMON_WIDTH=1920
Environment=SUNSHINE_VMON_HEIGHT=1080
Environment=SUNSHINE_VMON_FPS=60
```

### Sunshine `apps.json`

O Sunshine **exige** a chave `env` no `apps.json`. Sem ela, os apps não aparecem nos clientes Moonlight/Artemis.

```bash
systemctl --user restart sunshine
```

### Serviço do monitor virtual

```bash
systemctl --user status sunshine-vmon.service
systemctl --user restart sunshine-vmon.service
kscreen-doctor -o   # deve listar Virtual-sunshine-vmon (desabilitado fora do stream)
```

O serviço **não é habilitado automaticamente** no boot por padrão (`install.sh` pergunta antes). Teste com `systemctl --user start` antes de `enable`.

### Recuperação de tela preta

**TTY** (Ctrl+Alt+F3): faça login com o **mesmo usuário** da sessão (não use `root` direto):

```bash
/home/raggid/projects/sunshine-kde-vmon/sunshine-vmon-recover.sh
```

Se estiver como root:

```bash
sudo -u raggid \
  XDG_RUNTIME_DIR=/run/user/1000 \
  WAYLAND_DISPLAY=wayland-0 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
  /home/raggid/projects/sunshine-kde-vmon/sunshine-vmon-recover.sh
```

O recover antigo falhava no TTY sem `DBUS_SESSION_BUS_ADDRESS` e sem religar todos os outputs físicos.

**Causas comuns de tela preta:**
- Desktop Exclusive desliga o físico; o stream falha e o `undo` do Sunshine não roda.
- `reload_sunshine` no meio do prep-cmd (versões antigas) derrubava o `krfb` no pior momento.

**Importante:** encerre o stream no Moonlight antes de reiniciar o PC (`exit-timeout` = 30s nos apps).

## Variáveis de ambiente

| Variável | Padrão | Uso |
|----------|--------|-----|
| `SUNSHINE_CLIENT_WIDTH` | `1920` | Resolução no início do stream |
| `SUNSHINE_CLIENT_HEIGHT` | `1080` | Resolução no início do stream |
| `SUNSHINE_CLIENT_FPS` | `60` | FPS no início do stream |
| `SUNSHINE_PRIMARY_OUTPUT` | _(auto)_ | Monitor físico; detectado se omitido (fallback `DP-1`) |
| `SUNSHINE_VMON_WIDTH` | `1920` | Resolução base do serviço persistente |
| `SUNSHINE_VMON_HEIGHT` | `1080` | Resolução base do serviço persistente |
| `SUNSHINE_VMON_FPS` | `60` | FPS base do serviço persistente |

## Licença

MIT
