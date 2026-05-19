# sunshine-kde-vmon

Scripts para streaming com [Sunshine](https://github.com/LizardByte/Sunshine) no KDE Plasma (Wayland), usando monitor virtual (`krfb-virtualmonitor`) e `kscreen-doctor`.

## Scripts

| Script | Descrição |
|--------|-----------|
| `sunshine-start-vmon.sh` | Cria display virtual na resolução do cliente; monitor físico permanece ligado |
| `sunshine-stop-vmon.sh` | Remove o display virtual e restaura o monitor físico |
| `sunshine-start-vmon-offmon.sh` | Igual ao anterior, mas **desativa** o monitor físico |
| `sunshine-stop-vmon-offmon.sh` | Reativa o monitor físico e remove o display virtual |

## Requisitos

- KDE Plasma 6 (Wayland)
- [Sunshine](https://github.com/LizardByte/Sunshine) com `capture = kwin`
- `krfb-virtualmonitor` (pacote `krfb` no Arch)
- `kscreen-doctor` (pacote `kscreen`)

## Instalação

```bash
git clone https://github.com/raggid/sunshine-kde-vmon.git ~/projects/sunshine-kde-vmon
```

Aponte os `prep-cmd` do Sunshine para o diretório do clone (caminhos absolutos).

Alternativa: `./install.sh` copia os scripts para `~/.local/bin`.

## Configuração

### Monitor físico

Descubra o nome do conector:

```bash
kscreen-doctor -o
```

Ajuste nos scripts conforme necessário:

- `sunshine-stop-vmon.sh` — linha `kscreen-doctor output.DP-2...` e `output_name` em `sunshine.conf`
- Scripts `-offmon` — variável `SUNSHINE_PRIMARY_OUTPUT` (padrão: `DP-2`)

```bash
export SUNSHINE_PRIMARY_OUTPUT=DP-2
```

### Sunshine `apps.json`

Veja `examples/apps.json` para integrar os scripts como `prep-cmd` nos apps Desktop, Desktop Exclusive e Steam Big Picture. Substitua `/home/USER/projects/sunshine-kde-vmon` pelo caminho do seu clone e ajuste os UUIDs se necessário (o Sunshine gera novos ao adicionar apps pela UI).

Reinicie o Sunshine após alterações:

```bash
systemctl --user restart sunshine
```

## Variáveis de ambiente (Sunshine)

O Sunshine expõe a resolução do cliente ao iniciar a sessão:

| Variável | Padrão |
|----------|--------|
| `SUNSHINE_CLIENT_WIDTH` | `1920` |
| `SUNSHINE_CLIENT_HEIGHT` | `1080` |
| `SUNSHINE_CLIENT_FPS` | `60` |
| `SUNSHINE_PRIMARY_OUTPUT` | `DP-2` (apenas scripts `-offmon`) |

## Licença

MIT
