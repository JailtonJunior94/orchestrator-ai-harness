# Fatos do host — provados executando, não lendo

Toda linha aqui foi obtida rodando o comando na versão declarada. Quando a documentação (nossa ou
de terceiro) divergir do que está aqui, **o comando vence** e a doc é corrigida.

CLI de referência: **Claude Code 2.1.267** · macOS · `/bin/bash` 3.2.57.

## `--plugin-dir` é opção GLOBAL, não do subcomando

O que a mensagem de erro do próprio host sugere está errado. Ela diz:

```
Plugin "lt" not found. Run `claude plugin list` to see installed plugins,
or pass --plugin-dir <path> to load one from disk.
```

Mas passar a flag ao subcomando falha:

```console
$ claude plugin details lt --plugin-dir "$PWD/plugins/lt"
error: unknown option '--plugin-dir'

$ claude plugin details --plugin-dir "$PWD/plugins/lt"
error: unknown option '--plugin-dir'
```

A forma que funciona põe a flag **antes** do subcomando:

```console
$ claude --plugin-dir "$PWD/plugins/lt" plugin details lt
lt 0.1.4
  ...
```

`claude plugin details --help` não lista a opção. Consequência para `scripts/plugin-token-cost.sh`:
a medição usa `claude --plugin-dir <abs> plugin details <nome>`, e o gate falha alto se a forma
mudar — não cai para "pular a medição".

## Comando aparece como Skill no inventário

Com um `commands/lt-doctor.md` e um `skills/analyze-project/SKILL.md` em disco, o inventário reporta:

```
Component inventory
  Skills (2)  lt-doctor, analyze-project
  Agents (0)
```

Ou seja, a contagem de "Skills" do `plugin details` **soma commands e skills**. Não use esse número
como fonte para a contagem de skills em prosa; a fonte é o disco
(`ls -1d plugins/lt/skills/*/ | wc -l`).

## `cadence` é warning previsto, e a ausência dele é que reprova

```console
$ claude plugin validate .claude-plugin/marketplace.json
⚠ Found 1 warning:
  ❯ plugins[0].cadence: Unknown field 'cadence'. Claude Code ignores it at load time.
✔ Validation passed with warnings
```

Registrado em `config/validate-allowlist.txt` com data de caducidade.

## Baseline de custo always-on

Medido sob `HOME` descartável, porque o número com `~/.claude` populado é outro.

| Data | CLI | Componentes | Always-on |
|---|---|---|---|
| 2026-09-22 | 2.1.267 | 1 skill + 1 command | ~273 tok |

## `permissionDecision` sob `--dangerously-skip-permissions` — o valor importa

Documentação oficial (`code.claude.com/docs/en/hooks-guide`), verbatim:

> `PreToolUse` hooks fire before any permission-mode check, in every permission mode, including
> `dontAsk`. A hook that returns `permissionDecision: "deny"` blocks the tool even in
> `bypassPermissions` mode or with `--dangerously-skip-permissions`. (…) The reverse is not true.

E a semântica de cada valor:

| valor | efeito no `PreToolUse` |
|---|---|
| `"allow"` | pula o prompt interativo. Regras de deny e ask ainda se aplicam. |
| `"deny"` | **cancela a chamada** e devolve `permissionDecisionReason` ao agente |
| `"ask"` | mostra o prompt de permissão **normalmente** |
| `"defer"` | só em modo não interativo (`-p`) |

**A consequência que muda o desenho deste harness.** Os aliases desta organização rodam
`claude --dangerously-skip-permissions`. Onde não há prompt, `"ask"` não faz nada — a guarda
existe, roda, emite a decisão, e o host segue em frente. Uma guarda de segredos inteiramente em
`"ask"` ficaria **inerte exatamente nas máquinas que mais confiam nela**.

Por isso `plugins/lt/lib/secret_scan.py` separa a postura por severidade:

- `critical` (credencial de produção: DSN com senha, token do GitHub, PAT da DigitalOcean, URL
  do Appsmith com `?auth=`) → **`deny`**. Não se negocia com bypass.
- `high` (JWT, chave FCM) → **`ask`**. Mantém o humano no loop onde existe prompt, e evita o
  bloqueio duro que ensina o agente a contornar o gate.

## `exit 2` sobrevive ao bypass — provado ao vivo

A documentação diz apenas "Exit 2: Claude Code blocks the action", sem qualificar por modo de
permissão. A prova direta veio de uma sessão real deste repositório, rodando com
`--dangerously-skip-permissions`: o `pre-bash-block-destructive.sh` bloqueou um comando com
`exit 2` e a chamada não aconteceu.

Isso confirma que os hooks de caminho sensível e de comando destrutivo, que usam `exit 2`,
**mantêm a proteção sob o alias da organização**. Só a classe que usa `permissionDecision`
precisava da correção acima.

## Onde colocar o campo importa — silêncio é a falha

> When your hook returns `permissionDecision` or `additionalContext` at the top level instead of
> inside `hookSpecificOutput`, the JSON still parses, and Claude Code ignores the field.

Campo no nível errado **não dá erro**: é ignorado. Todos os hooks deste plugin aninham dentro de
`hookSpecificOutput`, e o e2e verifica a forma da saída, não só o exit code.

## Multi-host — Codex, Copilot e OpenCode (provado executando, 2026-09-23)

Versões sondadas: Codex CLI `0.156.1`, GitHub Copilot CLI `1.0.88`, OpenCode `1.18.32`. Cada fato
abaixo saiu de execução real com marcador único; o que não pôde rodar está marcado **não provado**.
O reconciler (`plugins/lt/scripts/reconcile-hosts.py`) e o adaptador (`plugins/lt/lib/host-dispatch.py`)
foram escritos contra estes fatos.

### Descoberta de skills, agents e instruções

| Host | Skills (projeto / usuário) | Agents | Instruções |
|---|---|---|---|
| Codex | `.agents/skills`, `.codex/skills` / `$CODEX_HOME/skills`, `~/.agents/skills` — `description` obrigatório, `name` opcional | `.codex/agents/*.toml` (só em projeto confiável), `$CODEX_HOME/agents` — `developer_instructions` obrigatório | `AGENTS.md`, `$CODEX_HOME/AGENTS.md`; **não** lê `CLAUDE.md` |
| Copilot | `.github/skills`, `.agents/skills`, `.claude/skills` / `$COPILOT_HOME/skills`, `~/.agents/skills` | `.github/agents/*.agent.md`, `$COPILOT_HOME/agents` | `AGENTS.md`, `.github/copilot-instructions.md`, `$COPILOT_HOME/copilot-instructions.md` |
| OpenCode | `.agents/skills`, `.opencode/skills`, `.claude/skills` / `$XDG_CONFIG_HOME/opencode/skills`, `~/.agents/skills` — `name` obrigatório | `.opencode/agents/*.md` (`mode: subagent`) | `AGENTS.md` (cai para `CLAUDE.md` sem ele) |

`.agents/skills` (projeto) e `~/.agents/skills` (usuário) são lidos pelos três — é o único destino de
skill do reconciler, para não listar a mesma skill duas vezes.

### Hooks — o que liga e o que é pulado em silêncio

- **Codex:** `.codex/hooks.json` ou `$CODEX_HOME/hooks.json`, mesmo formato do Claude. Cada hook exige
  `[hooks.state."<arquivo>:<evento_snake>:<grupo>:<handler>"] trusted_hash = "sha256:…"` no
  `$CODEX_HOME/config.toml`; sem a entrada o hook é **pulado sem aviso**. O hash é SHA-256 do JSON
  compacto e ordenado de `{"event_name","matcher"?,"hooks":[{"type","command","timeout":600,"async":false}]}`.
  O projeto também precisa de `trust_level = "trusted"`; `codex exec --dangerously-bypass-approvals-and-sandbox`
  grava esse trust sozinho no `config.toml` real — sondas devem usar `CODEX_HOME` descartável.
- **Codex:** chave de topo escrita depois de uma tabela vira campo da tabela e é ignorada; só
  `--strict-config` acusa. O reconciler só anexa tabelas, sempre no fim, em bloco marcado.
- **Codex — deny:** exit 2 **com a razão no stderr** vira `PreToolUse Blocked`. Exit 2 com stderr vazio vira
  `PreToolUse Failed` e a ferramenta **executa** (provado: `apply_patch` com segredo passou). Por isso o
  `host-dispatch.py` sempre promove `permissionDecisionReason` do stdout para o stderr.
- **Copilot:** `.github/hooks/*.json` só carrega com a pasta em `trustedFolders` de `$COPILOT_HOME/config.json`
  (`--yolo` não confia a pasta); `$COPILOT_HOME/hooks/*.json` carrega sempre. Formato usado:
  `{"version":1,"hooks":{"preToolUse":[{"type":"command","bash":"…"}]}}`, payload camelCase
  (`toolName`, `toolArgs`, `sessionId`, `cwd`). Deny: exit 2 bloqueia, mas o modelo só vê
  `hook exited with code 2` e não sabe o motivo. O deny em JSON no stdout,
  `{"permissionDecision":"deny","permissionDecisionReason":"…"}` com exit 0, bloqueia **e** mostra o
  motivo (`Denied by preToolUse hook: <razão>`). Provado ao vivo com `--yolo`, tanto no `git push --force`
  quanto na escrita de segredo. É o formato que o adaptador usa no Copilot.
- **OpenCode:** plugin JS em `.opencode/plugins/` ou `$XDG_CONFIG_HOME/opencode/plugins/`, sem trust. Deny é
  lançar exceção em `tool.execute.before` (payload `{tool, sessionID}` + `output.args`).
- **Eventos sem equivalente:** nenhum dos três emitiu fim de subagente nas sondas — `SubagentStop` fica só no
  Claude Code. `permissionDecision: "ask"` não tem pergunta disparável nos modos `--yolo`/`--auto`/bypass:
  o adaptador converte em deny com a razão.

### Prova ao vivo nos perfis reais (aliases `claudiney`, `codexy`, `copiloty`, `opencodey`)

Repositório descartável com remoto **bare local**. Dois sentinelas observáveis no disco: `git push --force`
para `main` (o ref do remoto não pode mudar) e escrita de `fixture-secret.txt` com a chave de exemplo da
documentação AWS (o arquivo não pode existir).

| Host (modo) | Skill `using-lt` | force-push | segredo | Observado no disco |
|---|---|---|---|---|
| Claude Code (`--dangerously-skip-permissions`) | carregou, marcador emitido | negado (`PreToolUse:Bash hook error`) | negado (`PreToolUse:Write hook error`) | remoto intacto; arquivo ausente |
| Codex (`--dangerously-bypass-approvals-and-sandbox`) | carregou, marcador emitido | `PreToolUse Blocked` | `PreToolUse Blocked` (após o fix de stderr) | remoto intacto; arquivo ausente |
| OpenCode (`--auto`, modelo `opencode/mimo-v2.6-flash-free`) | carregou via tool `skill` | negado pelo plugin | negado pelo plugin | remoto intacto; arquivo ausente |
| Copilot (`--yolo`, BYOM Gemini) | descoberta e invocada (`skill(using-lt)`); corpo **não provado** — o provider devolveu 400 | `Denied by preToolUse hook` | `Denied by preToolUse hook` | remoto intacto; arquivo ausente |

Limitações registradas, não defeitos do harness: a cota mensal do Copilot estava esgotada (a sonda usou
BYOM); o alias `opencodey` (`opencode --auto`) só abre a TUI, então a sonda não interativa usou
`opencode run --auto`, com o mesmo binário, flag e configuração global. Sondas reprodutíveis sem modelo:
`codex debug prompt-input 'oi'`, `opencode debug skill`, `copilot skill list`, `copilot -p oi --agent zz-none`.

### Latência do adaptador (mediana de 10 chamadas, Apple Silicon, runtime global)

| Evento (Codex) | Hooks em série | Hooks em paralelo (0.1.4) |
|---|---:|---:|
| `PreToolUse` Bash | 170 ms | 109 ms |
| `PreToolUse` apply_patch | 207 ms | 123 ms |
| `UserPromptSubmit` | 167 ms | 110 ms |

O piso é a partida do python do adaptador (~55 ms) mais o hook mais lento do evento. Os hooks rodam
em paralelo, como no Claude Code, e a decisão continua determinística: os resultados são lidos na
ordem do `hooks.json` e qualquer deny vence.

### Sinal de vida e frescor (0.1.4)

O `session-start` de cada host grava `$CLAUDE_CONFIG_DIR/lt/heartbeat/<host>.json`. O
`lt-doctor --hosts` cruza esse registro com a data da instalação e acusa o host cujos hooks nunca
dispararam. É a única verificação de ponta a ponta contra o trust do Codex quebrar numa versão nova.
O manifest da cópia instalada guarda o digest da fonte, e a sessão avisa quando a fonte mudou sem
reinstalação.

### Política gerenciada e sonda contínua (0.1.4)

- **Codex, provado em container com o 0.156.1:** `/etc/codex/requirements.toml` com
  `allowed_sandbox_modes = ["read-only", "workspace-write"]` faz o `--dangerously-bypass-approvals-and-sandbox`
  e o `-c sandbox_mode="danger-full-access"` serem **recusados antes de chamar o modelo**, com erro de
  política. `-s workspace-write` sem confirmação continua permitido. O payload é
  `enterprise/codex-requirements.toml`, e os bootstraps de macOS e Linux o instalam.
- **Codex — hooks na camada de sistema confiáveis sem `trusted_hash`: NÃO PROVADO.** A execução exigia
  modelo e a conta estava sem créditos. A instalação segue usando o `trusted_hash`, que está provado.
- **Copilot — política de dispositivo: NÃO PROVADA.**
  - O CLI 1.0.x tem uma camada `managed-settings` experimental (servidor, dispositivo ou SDK) com
    `permissions.disableBypassPermissionsMode`.
  - O caminho do arquivo de dispositivo fica no código nativo e não foi localizado.
  - A política de organização é configurada no GitHub, não em arquivo.
  - A cota esgotada impediu observar se `settings.json` recusa `--yolo`.
- **Sonda contínua:** `scripts/probe-hosts.sh`, que roda toda semana em `host-probe.yml` com a versão
  mais nova de cada CLI.
  - Sem credencial, prova as skills no Codex, OpenCode e Copilot, os agents e o plugin no OpenCode,
    o `config.toml` do Codex (`--strict-config` chega ao 401, não ao erro de config) e o
    `plugin validate` do Claude.
  - Com `--require-tested`, reprova a versão de host fora de `config/host-versions.json`: versão nova
    obriga a provar de novo, antes de confiar, os fatos desta página, a começar pela fórmula do
    `trusted_hash`.

### Uso diário com sandbox (recomendado)

Nos modos sem confirmação (`--yolo`, bypass, `--dangerously-skip-permissions`), os hooks do harness são a
**única** barreira. Os filtros de texto podem ser contornados com base64 ou `eval`. As alternativas
abaixo mantêm o fluxo sem prompts e colocam uma camada de sistema na frente:

| Host | Em vez de | Use |
|---|---|---|
| Claude Code | `--dangerously-skip-permissions` | `--permission-mode auto` |
| Codex | `--dangerously-bypass-approvals-and-sandbox` | `--sandbox workspace-write --ask-for-approval never` (a política gerenciada recusa o bypass) |
| Copilot | `--yolo` | `--allow-all-tools` (mantém a verificação de caminho e de URL) |
| OpenCode | `--auto` | `--auto`: não existe sandbox; a barreira são o plugin de governança e o `permission` do `opencode.json` |
