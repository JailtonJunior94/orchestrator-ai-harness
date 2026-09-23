# enterprise/ — política gerenciada da organização

Payload de distribuição **fora de qualquer plugin**. Um plugin não consegue se registrar nem se
habilitar sozinho numa máquina; a política gerenciada consegue, com prioridade sobre as settings
de usuário e sem que a pessoa possa desligá-la.

| Arquivo | Papel |
|---|---|
| `managed-settings.json` | o payload: marketplace `lt` pinado em tag, `lt@lt` habilitado, servidores MCP homologados, `permissions.deny` mínimo, bloco `_audit` |
| `bootstrap-mac.sh` | instala o payload no macOS |
| `bootstrap-linux.sh` | instala o payload no Linux e no WSL |
| `bootstrap-windows.ps1` | instala o payload no Windows (PowerShell como Administrador) |
| `verify.sh` | confere uma máquina: arquivo presente, JSON válido, pin == versão do manifesto, pin é tag semver, `lt@lt` habilitado, `deny` mínimo, nenhuma chave fora da referência oficial |
| `uninstall.sh` | remove a política no macOS e no Linux, com backup |
| `uninstall.ps1` | remove a política no Windows, com backup |

## Caminhos por SO

| SO | Caminho lido pelo Claude Code |
|---|---|
| macOS | `/Library/Application Support/ClaudeCode/managed-settings.json` |
| Linux e WSL | `/etc/claude-code/managed-settings.json` |
| Windows | `C:\Program Files\ClaudeCode\managed-settings.json` |

`C:\ProgramData\ClaudeCode\` é **legado e não é lido**. Instalar ali não dá erro e não faz nada —
o pior resultado possível para uma política de segurança. `tests/enterprise/bootstrap-dryrun.sh`
reprova o caminho errado.

## Instalar

A versão vem da release: use os artefatos anexados à tag, ou o clone do repositório no mesmo
commit da tag.

```bash
# macOS
bash enterprise/bootstrap-mac.sh
# Linux / WSL
bash enterprise/bootstrap-linux.sh
```

```powershell
# Windows, PowerShell como Administrador
powershell -ExecutionPolicy Bypass -File enterprise\bootstrap-windows.ps1
```

O bootstrap: exige `gh` autenticado e `jq`; **confere que a tag existe** antes de baixar (sem
isso um 404 seguia pelo pipe e o erro visível era do `base64`); baixa o payload da tag; valida o
JSON e o pin; copia com privilégio; roda `verify.sh`.

Depois, **o passo que todo mundo esquece**: `enabledPlugins` na política não materializa o cache.

```bash
claude plugin install lt@lt
# ou, a partir do clone:
bash scripts/install.sh
```

## Verificar e remover

```bash
bash enterprise/verify.sh          # VERIFY PASSOU
bash enterprise/uninstall.sh       # confirmação [y/N], backup em $TMPDIR
```

```powershell
powershell -ExecutionPolicy Bypass -File enterprise\uninstall.ps1
```

Os removedores tiram **só** a política. O plugin, o cache e os dados locais (`~/.claude/lt/`,
`.lt/` dos projetos) ficam; para remover o harness de uma pessoa, `bash scripts/uninstall.sh`.

## Testar sem sudo

`LT_DRYRUN=1` faz os bootstraps usarem o `managed-settings.json` local, validarem o pin e pararem
antes de qualquer cópia privilegiada. É o que o CI exercita:

```bash
LT_DRYRUN=1 bash enterprise/bootstrap-mac.sh
LT_VERIFY_TARGET=enterprise/managed-settings.json bash enterprise/verify.sh
```

## Mudar a política

Toda mudança neste diretório é PR com revisão do dono (`.github/CODEOWNERS`):

- servidor MCP novo: a mesma entrada em `docs/policy/ia-automacao.md`, avaliação de exfiltração
  no corpo do PR e registro `mcp-homologation` no audit trail;
- versão: nunca à mão — `scripts/bump-version.sh` reescreve pin e bootstraps juntos, e
  `tests/enterprise/version-pin.sh` reprova divergência;
- chave nova: só se estiver na referência oficial de settings. Governança sobre chave não
  documentada some num upgrade.

Ritmo de rollout, ondas e rollback: `docs/enterprise-rollout.md`.
