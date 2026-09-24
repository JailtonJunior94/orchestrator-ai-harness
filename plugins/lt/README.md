# Plugin `lt` — LT AI Harness

Plugin core do harness de desenvolvimento assistido por IA da Lima Teixeira: o ciclo de
desenvolvimento orientado a especificação (SDD), os hooks de segurança, o audit trail e a
statusline. Distribuído pelo marketplace `lt` deste repositório, em cadência `lockstep`.

## Instalar

```bash
claude plugin marketplace add JailtonJunior94/orchestrator-ai-harness
claude plugin install lt@lt
```

Reinicie a sessão e rode `/lt:lt-doctor`. Instalação validada ponta a ponta, statusline e
adaptadores para outros hosts: `bash scripts/install.sh` a partir do clone (ver `PILOT-SETUP.md`
na raiz do repositório).

## O que tem dentro

| Diretório | Conteúdo |
|---|---|
| `skills/` | o ciclo SDD (`lt:analyze-project` → `lt:create-prd` → `lt:create-technical-specification` → `lt:create-tasks` → `lt:execute-task` / `lt:execute-all-tasks` → `lt:review`, com `lt:bugfix` e `lt:refactor`), a conversão `lt:us-to-prd`, a governança `lt:agent-governance`, a modelagem de domínio `lt:domain-modeling`, a seleção de padrões de projeto `lt:design-patterns`, a observabilidade `lt:o11y-guideline`, o banco `lt:postgres-guideline`, a diretriz de linguagem `lt:go-guideline` e a porta de entrada `lt:using-lt` |
| `commands/` | `lt:0-setup`, `lt:lt-approve`, `lt:lt-doctor`, `lt:lt-migrate-legacy` |
| `agents/` | subagentes que executam uma etapa do ciclo com contexto isolado, carregando a skill correspondente |
| `hooks/` | guardas de sessão, comando, escrita e prompt, registradas em `hooks/hooks.json` |
| `lib/` | resolvedores compartilhados (`destructive_guard.py`, `sensitive_paths.py`, `secret_scan.py`, `sdd.py`, `preferences.sh`, `lt-lock.sh`, …) e o despachante de hooks dos outros hosts (`host-dispatch.py`) |
| `scripts/` | porta única do audit trail (`approve.sh`), diagnóstico (`doctor.sh`), dial `guided` (`guided-mode.sh`), motor do ciclo (`lt-sdd.sh`), adaptadores multi-host (`reconcile-hosts.py`) e validadores de evidência |
| `config/` | `constitution.md`, `policy-texts.md`, `sensitive-paths.json`, `secret-patterns.json`, `preferences.defaults.json` |
| `statusline/` | `statusline.sh`, o shim de caminho estável e os segmentos |

Nomes canônicos e forma de invocar em cada host: `docs/command-glossary.md`.

## Guardas

| Guarda | Postura |
|---|---|
| comando destrutivo (`pre-bash-block-destructive.sh`) | reversível dentro de árvore git ganha snapshot e passa; irreversível **bloqueia** (`exit 2`) sem aprovação `destructive` recente |
| caminho sensível em comando e em leitura/escrita (`pre-bash-…`, `pre-write-block-sensitive-paths.sh`) | **bloqueia** por padrão; `ask` é opt-in persistente do squad, registrado no audit trail |
| segredo em escrita (`pre-write-scan-secrets.sh`) | `deny` para credencial crítica, `ask` para severidade alta |
| cobertura de spec (`pre-write-spec-coverage-warn.sh`) | segue o dial `guided`: `off` avisa, `balanced` pergunta, `strict` bloqueia |
| prompt com caminho sensível ou segredo (`user-prompt-…`) | só avisa; segredo vira pendência de rotação |
| janela de contexto (`user-prompt-context-warning.sh`) | aviso progressivo; cala quando a janela é desconhecida |
| telemetria (`post-…`) | local, em `~/.claude/lt/`; nada sai da máquina |

Hook de segurança **nunca** consulta o dial `guided`; só o hook de processo consulta. O dial nasce
`off` e atualizar o harness nunca o move.

## Audit trail

Toda linha de `~/.claude/lt/approve.log` sai de `scripts/approve.sh`, pelo command
`/lt:lt-approve`. Formato TSV de cinco campos (`epoch`, `token`, `contexto`, `operador`,
`mode=human|flow|auto`), vocabulário fechado, e recusa de token de liberação de guarda em
`--mode auto`: o ciclo autônomo não assina a própria licença.

## Repo consumidor

`/lt:0-setup` prepara `.lt/` no repositório do squad: `config.yaml` (dial `guided`, statusline),
`preferences.json` (lido **por enum**, nunca ecoado — ver `config/policy-texts.md`),
`sensitive-paths.json` (só **acrescenta** ao guarda, e vale depois de aprovação local por SHA-256),
specs do ciclo e audit local.

## Outros hosts

`bash scripts/install.sh --hosts codex,copilot,opencode --project <repo>` materializa no repo
consumidor as skills (`.agents/skills/`, `.github/skills/`), o bloco gerenciado do `AGENTS.md` e
de `.github/copilot-instructions.md`, `.codex/config.toml`, os hooks do Copilot e o plugin do
OpenCode, com um manifest de checksums em `.lt-harness/`. Este plugin continua sendo a fonte
canônica; os adaptadores são derivados e `reconcile-hosts.py verify` aponta drift.

## Desenvolver

`docs/PLUGIN-DEVELOPMENT.md` na raiz do repositório.
