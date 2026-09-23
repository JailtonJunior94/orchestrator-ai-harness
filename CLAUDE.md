# CLAUDE.md — contexto para quem edita este repositório

Este arquivo é lido por todo agente que abre este repo. Ele não descreve o que o harness faz para
os outros repos — isso está no `README.md`. Ele descreve as regras de quem mexe **aqui dentro**.

## 1. O que este repo é

Não é código de produto. É um framework de processo, governança e contexto para desenvolvimento
assistido por IA, distribuído como **marketplace de plugins do Claude Code**.

Três camadas, cada uma com o próprio contrato:

| Camada | Onde vive | O que é |
|---|---|---|
| Marketplace | `.claude-plugin/marketplace.json` | Catálogo: nome, versão, cadência e fonte de cada plugin. É o que `claude plugin marketplace add` lê. |
| Plugin | `plugins/lt/` | `.claude-plugin/plugin.json`, `commands/`, `skills/`, `agents/`, `hooks/`, `lib/`, `scripts/`, `config/`, `statusline/`, `evals/`. |
| Repo consumidor | `.lt/` no repo de cada squad | `config.yaml`, `preferences.json`, `sensitive-paths.json`, skills do squad, audit local. Gerado por `lt:0-setup`. |

## 2. Shell — regra dura bash 3.2

O `/bin/bash` dos Macs da frota é **3.2.57**. Não é uma preferência de estilo: é o interpretador
que vai rodar os hooks na máquina de quem usa o harness. CI verde no Linux com bash 5 e morto no
Mac é a classe de defeito mais cara deste repo.

**Proibido** (bash 4+):

- `mapfile` / `readarray`
- `declare -A` (arrays associativos)
- `${var,,}` / `${var^^}` — use `tr '[:upper:]' '[:lower:]'`
- `&>>` — use `>>arquivo 2>&1`
- `local -n` (nameref)
- `[[ -v var ]]`

**Obrigatório:**

- `#!/usr/bin/env bash` em todo script
- `set -euo pipefail` em script de CLI; `set -uo pipefail` em script de display tolerante
- aspas em tudo: `"$var"`, `"${arr[@]}"`
- sob `set -u`, expansão de array sempre como `${ARR[@]+"${ARR[@]}"}`
- `grep -e -- "$PAT"` quando o padrão pode começar com `-`
- `"${INPUT:0:100000}"` antes de qualquer regex custosa (cap de ReDoS sem depender de `head`)
- `sed -i '' -e … "$f" 2>/dev/null || sed -i -e … "$f"` (BSD, com fallback GNU)
- `flock(1)` **não existe no macOS** — use `lib/lt-lock.sh`, que cai para spin-lock por `mkdir`
- `stat -c … 2>/dev/null || stat -f …` — GNU **primeiro**: no Linux `stat -f` não falha (reporta o filesystem) e o fallback nunca roda
- `10#` ao comparar componentes numéricos (`08` e `09` são octal inválido e abortam sob `set -e`)

## 3. Regras do host

**Chave que o host ignora é chave morta.** Três mecanismos plausíveis na documentação não têm
efeito nenhum e não entram no `plugin.json`:

| Chave | Por que fica de fora |
|---|---|
| `hooks` | Quebra o carregamento do plugin. Hooks vivem **só** em `hooks/hooks.json`. |
| `statusLine` | Não existe no schema de manifesto. Só o instalador consegue entregar a barra. |
| `skillListingBudgetFraction` | É configuração de sessão; pertence ao `settings.json`. |
| `outputStylesPath` | Declarar **desliga** o auto-carregamento de `output-styles/`. |

**Toda referência a `${CLAUDE_PLUGIN_ROOT}` em `hooks.json` é aspada** — o cache do plugin pode
cair num caminho com espaço.

**Aspe o que parece estrutura.** Valor escalar não aspado que comece por `[ { * & ! % @` ou
contenha `: ` quebra o YAML. Com `description` em escalar plano o host repara em silêncio; com
`description` em bloco (`|` ou `>`) o host **descarta o frontmatter inteiro** e o componente passa
a anunciar o primeiro título do corpo como descrição. E `argument-hint: [slug]` parseia como
**lista**, não texto.

**Comportamento de host se prova executando, não lendo.** Sonda com marcador único:

```bash
claude -p --plugin-dir "$PWD/plugins/lt" 'use a skill analyze-project e responda apenas LT-HARNESS-OK'
```

Nome inválido cai em silêncio — "não deu erro" não prova que carregou.

**Quatro hosts, uma fonte.** Claude Code recebe o plugin. Codex, Copilot e OpenCode recebem a projeção de
`plugins/lt/scripts/reconcile-hosts.py`, e os hooks deles passam por `plugins/lt/lib/host-dispatch.py`.
Skill, agent, comando ou hook novo nasce **só** em `plugins/lt/`. Se o `bash scripts/check-host-parity.sh`
reprovar, a paridade quebrou. Fato de host novo se prova executando o CLI com `CODEX_HOME`,
`COPILOT_HOME` e `XDG_CONFIG_HOME` descartáveis: o bypass do Codex grava trust no `config.toml` real.

## 4. O ambiente local não entra no repo

Sem caminho com nome de usuário, sem pin pessoal, sem contagem de instalações da sua máquina, sem
clone aninhado. Isso é troubleshooting local e vai no **corpo do PR** como evidência.

Pergunta-teste antes de commitar qualquer prosa:

> Outro dev, noutro time, leria isto como verdade sobre o harness?

## 5. Commits e branches

Branch base: **`main`**.

Branches: `<tipo>/<kebab-slug>` em ASCII, tipos `feat | fix | chore | docs | refactor | spike | proposal`.
A convenção se cobra na revisão, nunca por gate bloqueante — renomear branch com PR aberto perde
review e histórico de comentários.

Commits: Conventional Commits **em inglês**, escopo = plugin ou área.

```
^(feat|fix|chore|docs|refactor|perf|test|build|ci)(\([a-z0-9-]+\))?: .+
```

## 6. Idioma

Uma regra, um dono: afirmação absoluta sobre idioma vive **só** na tabela abaixo (para quem edita
este repo) e em `plugins/lt/config/policy-texts.md` (para o que o plugin diz aos repos consumidores).

| Artefato | Idioma |
|---|---|
| `description` de skill/agent/command, prosa de doc, mensagens de hook, constitution | pt-BR |
| `name:`, nomes de arquivo e diretório, IDs de regra (`LT-SEC-001`, `PG001`), tokens de audit, variáveis de ambiente | ASCII, inglês/kebab |
| Títulos de commit, títulos de PR, nomes de branch | inglês |
| Comentários dentro de `.sh` / `.py` **deste repo** | pt-BR — e são **obrigatórios** onde registram decisão (ver abaixo) |

## 7. Comentários de justificativa são o registro de decisão

Este repo **não tem ADRs numerados**. O registro de decisão são `docs/specs/_completed/<slug>/` e
os comentários longos de justificativa dentro dos próprios scripts.

Isso é uma **exceção explícita e com escopo** à regra `R-STYLE-001.2` da constitution, que proíbe
comentários em código. A regra vale para o código que as skills produzem nos repos dos times; os
scripts do próprio harness (`plugins/lt/{hooks,lib,scripts,statusline}/**`, `scripts/**`,
`tests/**`) são isentos e **devem** carregar o porquê no ponto de uso. A justificativa está em
`plugins/lt/config/constitution.md`.

`R-STYLE-001.1` (código em inglês) e `.3` (sem prefixo `_` em identificador) continuam universais.

## 8. Suítes e banners

Verde é o banner, não só o exit code — um `set -e` mal posto devolve 0 com metade dos testes pulados.

| Suíte | Banner de sucesso |
|---|---|
| `tests/smoke/run.sh` | `SUITE PASSOU` |
| `tests/completeness-check.sh` | `TUDO ENTREGUE` |
| `tests/e2e/run.sh` | `E2E PASSOU` |
| `tests/enterprise/run.sh` | `✓ pass` por arquivo |
| `tests/unit/run.sh` | `Suite unit passou` |

Agregador local: `bash scripts/pilot-check.sh` (inclui `scripts/check-host-parity.sh` → `PARIDADE OK`).

`skip` ≠ `fail`: teste que **não pode** rodar (dependência ausente) é `skip` contado, nunca verde silencioso.
