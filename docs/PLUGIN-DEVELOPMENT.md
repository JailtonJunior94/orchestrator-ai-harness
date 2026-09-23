# Desenvolvimento do plugin

Guia para quem acrescenta ou altera skill, command, agent, hook ou script no plugin `lt`. As
regras duras (bash 3.2, host, idioma, commits) estão no `CLAUDE.md` e não são repetidas aqui;
este guia diz **como** trabalhar dentro delas e **como provar** que funcionou.

## Doutrina: comportamento de host se prova executando

Mecanismo plausível na documentação não é mecanismo que funciona. Chave que o host ignora é chave
morta, e o host não avisa. Por isso toda afirmação sobre o host passa por um destes comandos:

| Comando | Responde | Gate do repo |
|---|---|---|
| `claude plugin validate <alvo> --json` | o manifesto e os componentes estão na forma que o host aceita? | `scripts/validate-plugins.sh` |
| `claude --plugin-dir <abs> plugin details lt` (HOME descartável) | quanto o plugin custa em toda sessão? | `scripts/plugin-token-cost.sh` |
| `claude plugin eval <alvo> --ablation with-without` | a skill dispara quando deveria, e melhora o resultado? | `.github/workflows/plugin-eval.yml` (pago, atrás de label) |
| `claude plugin tag plugins/lt --dry-run` | `plugin.json` e manifesto concordam? | `docs/RELEASE-CHECKLIST.md` |
| `claude -p --plugin-dir "$PWD/plugins/lt" '<sonda com marcador único>'` | o componente carregou numa sessão real? | manual, antes do PR |

Fatos já provados, com a versão do CLI, ficam em `docs/host-facts.md`. Descobriu um novo?
Acrescente lá, com o comando e a saída.

## Anatomia

```text
plugins/lt/
├── .claude-plugin/plugin.json   # name, version, description, author, homepage, repository, license, keywords
├── agents/                      # subagentes (frontmatter: name, description)
├── commands/                    # commands (frontmatter: description, argument-hint aspado)
├── config/                      # constitution, policy-texts, sensitive-paths, secret-patterns, preferences.defaults
├── hooks/                       # hooks.json + um script por hook
├── lib/                         # código compartilhado pelos hooks e scripts (bash e python)
├── scripts/                     # approve, doctor, guided-mode, lt-sdd, reconcile-hosts, validadores de evidência
├── skills/<nome>/SKILL.md       # + references/, assets/, scripts/ da própria skill
└── statusline/                  # statusline.sh, statusline-shim.sh, segments/
```

`plugin.json` usa um conjunto fechado de chaves. **Não** entram: `hooks` (quebra o carregamento;
hooks vivem só em `hooks/hooks.json`), `statusLine` (não existe no schema de manifesto),
`skillListingBudgetFraction` (é configuração de sessão) e `outputStylesPath` (declarar desliga o
auto-carregamento). O smoke reprova as quatro.

## Skill nova

1. `plugins/lt/skills/<nome>/SKILL.md`, com `<nome>` em kebab ASCII igual ao `name:`.
2. `description` em escalar **plano** (nunca `|` nem `>`: o host descarta o frontmatter inteiro),
   em pt-BR, com: o que faz, **quando usar** (gatilhos que a pessoa digitaria) e **quando não
   usar** (a skill vizinha certa). A `description` é o roteador: skill com description vaga não
   dispara, e skill sem description não é descoberta.
3. `description` + `when_to_use` ≤ 1536 caracteres — acima disso o host trunca.
4. Chaves fora do schema oficial não entram no frontmatter; dado próprio vai em `metadata`.
5. Script chamado pela skill é referenciado por `${CLAUDE_SKILL_DIR}/…` ou
   `${CLAUDE_PLUGIN_ROOT}/…`, nunca por caminho absoluto. Tudo que a skill promete tem de
   existir em disco — `tests/unit/scripts/no-phantom-refs.test.sh` cobra.
6. Linha em `docs/command-glossary.md`.
7. Prove: `bash scripts/validate-frontmatter.sh`, `bash tests/command-glossary-check.sh`,
   `bash scripts/measure-skill-budget.sh` (a skill nova sobe o agregado — regrave com
   `--write --cause` e justifique no PR) e uma sonda com marcador único.

A skill também chega a Codex, Copilot e OpenCode: `plugins/lt/scripts/reconcile-hosts.py`
copia `skills/` para `.agents/skills/` (e `.github/skills/` no Copilot) no repo consumidor,
reescrevendo `${CLAUDE_PLUGIN_ROOT}` para `.lt-harness`. Não use recurso exclusivo do Claude
Code dentro do corpo da skill sem um caminho alternativo descrito.

## Command novo

`plugins/lt/commands/<nome>.md` com `description` (pt-BR) e, se receber argumento,
`argument-hint` **entre aspas** — `argument-hint: [slug]` parseia como lista. O corpo chama o
script do plugin na forma `bash "${CLAUDE_PLUGIN_ROOT}/scripts/<script>" $ARGUMENTS`, **sem
prefixo `VAR=x`**: o classificador de auto mode lê as duas formas de jeitos diferentes. Linha em
`docs/command-glossary.md`; invocação documentada como `/lt:<nome>`.

## Hook novo

**Ordem de postura**, a que o harness chegou depois de errar:

1. destrutivo irreversível → `exit 2`, sem flag;
2. segredo literal → `permissionDecision` (`deny` para crítico, `ask` para alto — ver
   `docs/host-facts.md` sobre o que `ask` vale sob `--dangerously-skip-permissions`);
3. caminho sensível → bloqueio por padrão; `ask` é opt-in persistente do squad;
4. hook de **processo** consulta o dial `guided`; hook de **segurança** nunca consulta;
5. `UserPromptSubmit` só avisa — apagar a mensagem do humano seria pior que o risco.

Mecânica:

- registre em `hooks/hooks.json` com a referência **aspada**:
  `"command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/<nome>.sh\""` e `"timeout"` explícito;
- `#!/usr/bin/env bash`, `set -uo pipefail`, `"${INPUT:0:100000}"` antes de regex, curto-circuito
  barato antes de qualquer fork;
- decisão estruturada **dentro** de `hookSpecificOutput` — no nível errado o campo é ignorado sem
  erro;
- config numa fonte única (`config/*.json`) e resolvedor numa invocação só de `python3 lib/…`
  (cada processo custa tempo em toda chamada de ferramenta), com modo degradado sem `python3` que
  **sobre-bloqueia** e anuncia no stderr;
- append em log pelo lock portátil `lib/lt-lock.sh` (`flock` não existe no macOS);
- preferência lida por `lib/preferences.sh`, **por enum**, nunca ecoando o arquivo.

Prova: teste em `tests/unit/hooks/` com casos positivos **e** negativos, `HOME` e
`CLAUDE_CONFIG_DIR` isolados (`assert_not_scratchpad`), e caso no `tests/e2e/run.sh` alimentando
o hook com o payload do host. Acrescente o script ao inventário de `tests/completeness-check.sh`.

## Escrita em `~/.claude/`

Sai **sempre** de um script do plugin, nunca de um `printf`/`echo` redigido no prompt. O
classificador de auto mode barra redirecionamento de shell para `~/.claude` — corretamente — e o
improviso abre furos (substring no campo errado, TAB deslocando colunas). O audit trail tem porta
única: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/approve.sh" --mode <human|flow|auto> <token> [contexto]`,
com vocabulário fechado e recusa de token de liberação em `--mode auto`.

## Script do repositório

Scripts em `scripts/`, `plugins/lt/{hooks,lib,scripts,statusline}/` e `tests/` carregam o
**porquê** em comentário pt-BR no ponto de decisão — é o registro de decisão deste repo (ver
`CLAUDE.md` §7). Gate que perde a dependência **falha** (exit 1) ou reporta "não rodou" (exit 2
para o `scripts/pilot-check.sh`), nunca sai verde.

## Gates que o CI cobra

| Gate | Natureza | Quando regravar |
|---|---|---|
| `scripts/validate-plugins.sh` | absoluto; allowlist com caducidade em `config/validate-allowlist.txt` | aviso novo aceito de propósito: entrada com motivo, owner e data |
| `scripts/validate-frontmatter.sh` | absoluto | — |
| `scripts/measure-skill-budget.sh` | per-item absoluto; agregado ratchet | `--write --cause`, justificativa no PR |
| `scripts/plugin-token-cost.sh` | ratchet | `--write --cause`, justificativa no PR |
| `scripts/validate-playbook-counts.sh` | absoluto | corrija a prosa, não o número |
| `tests/command-glossary-check.sh` | absoluto | — |
| `tests/language-policy-check.sh` | absoluto | — |

Tudo roda localmente em `bash scripts/pilot-check.sh`.
