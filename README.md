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

## Scripts

| Script | Descrição |
|--------|-----------|
| `sunshine-vmon-service.sh` | Serviço: cria o monitor virtual e deixa desabilitado |
| `sunshine-start-vmon.sh` | Liga o virtual (físico permanece ligado) |
| `sunshine-stop-vmon.sh` | Desliga o virtual, restaura o físico |
| `sunshine-start-vmon-offmon.sh` | Liga o virtual e desliga o físico (troca atomica) |
| `sunshine-stop-vmon-offmon.sh` | Religa o físico e desliga o virtual |

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

Variável `SUNSHINE_PRIMARY_OUTPUT` (padrão: `DP-2`) nos scripts `-offmon`.

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

Se após reboot a tela ficar preta (layout do KDE com monitor físico desligado + virtual desligado):

1. **TTY** (Ctrl+Alt+F3), login, execute:
   ```bash
   /home/raggid/projects/sunshine-kde-vmon/sunshine-vmon-recover.sh
   ```
2. Ou desative o serviço:
   ```bash
   systemctl --user disable --now sunshine-vmon.service
   rm ~/.config/systemd/user/sunshine-vmon.service
   systemctl --user daemon-reload
   ```
3. Só use Live CD se não tiver acesso a TTY/SSH.

**Causa:** o modo Desktop Exclusive desliga o monitor físico e o KDE pode salvar esse layout. No boot, o serviço antigo desligava só o virtual — ficando **nenhum monitor ligado**. Versões novas religam o físico **antes** de qualquer outra ação.

**Importante:** sempre encerre o stream (para o script `stop` rodar) antes de reiniciar o PC.

## Variáveis de ambiente

| Variável | Padrão | Uso |
|----------|--------|-----|
| `SUNSHINE_CLIENT_WIDTH` | `1920` | Resolução no início do stream |
| `SUNSHINE_CLIENT_HEIGHT` | `1080` | Resolução no início do stream |
| `SUNSHINE_CLIENT_FPS` | `60` | FPS no início do stream |
| `SUNSHINE_PRIMARY_OUTPUT` | `DP-2` | Monitor físico (modo Exclusive) |
| `SUNSHINE_VMON_WIDTH` | `1920` | Resolução base do serviço persistente |
| `SUNSHINE_VMON_HEIGHT` | `1080` | Resolução base do serviço persistente |
| `SUNSHINE_VMON_FPS` | `60` | FPS base do serviço persistente |

## Licença

MIT
