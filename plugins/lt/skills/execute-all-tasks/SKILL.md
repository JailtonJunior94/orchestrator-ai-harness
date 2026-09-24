---
name: execute-all-tasks
description: Orquestra execução completa de PRD spawnando subagent fresh por tarefa para isolar contexto. Respeita DAG, usa somente capacidades detectadas pelo CLI, halt-first e retomada idempotente. Use para PRD inteiro; não use para uma tarefa única — use execute-task.
metadata:
  version: 2.0.0
  category: governance
  depends_on:
  - execute-task
  - agent-governance
---

# Executar Todas as Tarefas de um PRD

> **Onde a spec mora — inegociável.** O diretório de specs pertence ao **repositório em que o
> comando está sendo executado**, a partir de qualquer pasta dele. Em `lt-api` a spec é
> `lt-api/<specs>/prd-<slug>/`; em `dataflow` é `dataflow/<specs>/prd-<slug>/`.
>
> Nunca monte o caminho à mão. Pergunte:
>
> ```bash
> bash "${CLAUDE_PLUGIN_ROOT}/scripts/lt-sdd.sh" specs-root --slug <slug> --create
> ```
>
> O nome do diretório é detectado nesta ordem: `LT_TASKS_ROOT` → `AI_TASKS_ROOT` →
> `tasks_root:` em `.lt/config.yaml`/`.claude/config.yaml` → `.specs/` existente **ou
> versionado no git** → `.lt/specs/`. Alvo fora da raiz do repositório é recusado com
> exit 3. Invariante I-5 da constitution.

> **Camada de linguagem é opcional.** Go tem a skill `go-guideline`; as de Node, Python e .NET
> (`*-implementation`) e as de design não vêm nesta versão do plugin. Antes de mandar carregar
> qualquer uma, **verifique o que existe**:
>
> ```bash
> bash "${CLAUDE_PLUGIN_ROOT}/scripts/lt-sdd.sh" skills-available --category language
> ```
>
> Linguagem cuja skill não aparece na saída segue sem ela, e você diz isso à pessoa.
> Nunca instrua a carregar uma skill que você não confirmou existir: instruir o agente a abrir
> algo inexistente é o defeito mais caro deste harness.

## Visão Geral

Delega cada tarefa a subagent. Subagent carrega só o necessário, executa via `execute-task` e retorna YAML compacto. Orquestrador retém ≤100 tokens/tarefa.

Por tarefa: lê → carrega só governance + linguagem do diff + skills declaradas → executa → YAML → contexto descartado → próxima.

Paralelismo e isolamento são decididos pelo CLI a partir das capacidades locais detectadas;
as skills não mantêm inventários de versões ou ferramentas.

## Procedimentos

**Etapa 1: Validar PRD**
0. **Invocar hook programático** (enforcement real das fragilidades F17, F18, F27, F29):
   `bash ${CLAUDE_PLUGIN_ROOT}/scripts/cycle/pre-execute-all-tasks.sh <slug>` (resolver caminho na cascata `${CLAUDE_PLUGIN_ROOT}/hooks/` → `${CLAUDE_PLUGIN_ROOT}/scripts/cycle/`). Exit ≠ 0 → `failed` repassando stderr do hook. Hook valida regex de tasks.md, gaps numéricos, cross-PRD spec-hash e ciclos. **Ausente em todos os caminhos (sem degradação silenciosa)**: como `${CLAUDE_PLUGIN_ROOT}/hooks/` é instalado junto com o plugin, a ausência total indica integridade quebrada → `failed: hook de governança 'pre-execute-all-tasks.sh' ausente em todos os caminhos — reinstale o plugin lt pelo marketplace`. Não prosseguir em "modo legado".
1. **`unset AI_PREFLIGHT_DONE` (F17 — também executado pelo hook acima como redundância)** antes de qualquer comando — força orquestrador a rodar próprios gates; re-exporta apenas no prompt do subagent.
2. Input: slug curto, `prd-<slug>`, ou path. **Não normalizar à mão** — resolver com
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/lt-sdd.sh" specs-root --slug <slug>`, que aplica a
   cascata descrita em "Resolução de paths".
3. **Resolver lib de profundidade (B1, fallback agnóstico)**: procurar `check-invocation-depth.sh` na ordem `${CLAUDE_PLUGIN_ROOT}/lib/` → `scripts/lib/` e fazer `source`. Ausente nas duas → `failed: check-invocation-depth.sh ausente em ${CLAUDE_PLUGIN_ROOT}/lib/ e scripts/lib/ — vendor a lib ou reinstale o plugin lt pelo marketplace`. Comando canônico:
   ```bash
   _depth_lib=""
   for d in ${CLAUDE_PLUGIN_ROOT}/lib scripts/lib; do
     [[ -r "$d/check-invocation-depth.sh" ]] && { _depth_lib="$d/check-invocation-depth.sh"; break; }
   done
   [[ -n "$_depth_lib" ]] || { echo "failed: depth lib missing"; exit 1; }
   source "$_depth_lib" || exit 1
   ```
4. **Gate do motor SDD (B2, sem degradação silenciosa)**: validar presença antes dos comandos do pré-voo. Ausente → `needs_input`:
   ```bash
   if [[ ! -f "${CLAUDE_PLUGIN_ROOT}/scripts/lt-sdd.sh" ]]; then
     echo "needs_input: motor SDD ausente em ${CLAUDE_PLUGIN_ROOT}/scripts/lt-sdd.sh. Reinstale o plugin lt. O orquestrador não pode degradar silenciosamente para 'modo legado' — princípio: governança acima de automação mágica."
     exit 1
   fi
   ```

   > A versão anterior checava `! bash "${CLAUDE_PLUGIN_ROOT}/scripts/lt-sdd.sh"` — o dispatcher
   > sem subcomando sai **2** (uso inválido), então a negação era verdadeira sempre e o
   > orquestrador parava com `needs_input` em toda execução. O que se quer saber é se o arquivo
   > existe, não o código de saída de uma invocação sem argumentos.
5. Verificação de drift de skills: **não disponível nesta versão do harness** (o plugin ainda não mantém um lock de skills). Siga para o próximo passo.
6. Confirmar `prd.md`, `techspec.md`, `tasks.md` → `needs_input` se faltar.
7. Rodar os **dois** comandos; eles respondem perguntas diferentes:
   - `bash "${CLAUDE_PLUGIN_ROOT}/scripts/lt-sdd.sh" assert-approved .lt/specs/prd-<slug> tasks` → `blocked` se algum artefato não estiver aprovado ou tiver mudado após a aprovação.
   - `bash "${CLAUDE_PLUGIN_ROOT}/scripts/lt-sdd.sh" check-spec-drift .lt/specs/prd-<slug>` → `blocked` se houver drift de hash entre PRD, techspec e tasks. **Não verifica cobertura.**
   - `bash "${CLAUDE_PLUGIN_ROOT}/scripts/lt-sdd.sh" validate-sdd .lt/specs/prd-<slug>` → `blocked` se algum `RF-nn`/`REQ-nn` do PRD ficar sem tarefa, ou se schema/DAG da tabela falharem.
8. **Registrar a execução (recuperável, idempotente)**: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/lt-sdd.sh" orchestrate .lt/specs/prd-<slug> --run-id <id>`. Recusa (exit 3) se prd/techspec/tasks não estiverem aprovados pelos bytes atuais ou se o `sdd-state.json` ainda estiver em v1 — nesse caso rodar `lt-sdd.sh migrate-sdd .lt/specs/prd-<slug>` primeiro (reversível com `rollback-sdd`). Retomar com o mesmo `--run-id` devolve o plano de waves gravado, sem reescrever o estado. O comando não executa tarefas: só registra o ponto de partida.
9. **Integridade das tarefas já `done` (F35, default-on; opt-out `AI_VALIDATE_GIT_HISTORY=0`)**: para cada tarefa `done`, o `sha=` do relatório é o `patch_sha256` (64 hex), não um commit. Conferir que o `patch_ref` do `execution-result.json` existe, que o SHA-256 dele bate com `sha=` e que `git apply --reverse --check <patch_ref>` passa. Falha → `needs_input: tarefa <id> done mas o patch declarado mudou ou foi revertido — (a) re-execute, (b) edite status, (c) cancele`. É a mesma checagem do `post-execute-task.sh`.

**Etapa 2: Construir grafo**
1. Ler `tasks.md`. Parsear cada linha com regex canônicos (gerados por `create-tasks` v1.4+):
   - `status`: `^(pending|in_progress|needs_input|blocked|failed|done)$` → fora = `failed: malformed status on <id>`.
   - `dependências`: `^(—|(\w[\w-]*\/)?\d+\.\d+(,\s*(\w[\w-]*\/)?\d+\.\d+)*)$`. Cross-PRD via prefixo `<slug>/`. Resolução em 5 passos:
     1. Ler `.lt/specs/prd-<slug>/tasks.md`. Ausente → a dependente fica **bloqueada** (o pré-voo avisa, `waves` a lista com o motivo); as independentes seguem.
     2. Tarefa inexistente naquele tasks.md → `failed: cross-PRD task not found: <slug>/<id>`.
     3. **Spec-hash do PRD referenciado (F18)**: extrair `spec-hash-prd` do header e comparar com `bash "${CLAUDE_PLUGIN_ROOT}/scripts/lt-sdd.sh" hash .lt/specs/prd-<slug>/prd.md`. Divergente → `blocked: cross-PRD <slug> tem spec drift; rode 'bash "${CLAUDE_PLUGIN_ROOT}/scripts/lt-sdd.sh" check-spec-drift' e re-execute aquele PRD primeiro`.
     4. Status diferente de `done` → a dependente fica **bloqueada**, como no passo 1. Não é `failed`: é atraso de outro bundle.
     5. **Ciclo cross-PRD (F27)**: travessia recursiva limitada a 3 níveis verificando se algum elo aponta de volta para PRD ativo. Ciclo → `failed: cross-PRD circular dependency detected: <chain>`. Profundidade > 3 → `blocked: cross-PRD chain too deep (>3); refatorar`.
   - `paralelizável`: normalizar equivalentes seguros (`não`/`nao`/`NÃO` → `Não`, `com 2.0,3.0` → `Com 2.0, 3.0`, `-`/`none`/vazio → `—`) e então validar `^(—|Não|Com\s+\d+\.\d+(,\s*\d+\.\d+)*)$`. Valores ambíguos continuam `failed: malformed Paralelizável on <id>`.
2. Resolver `file_path` por convenção `task-<id>-*.md` ou `<id>_*.md`. Ambíguo → `needs_input`.
3. **Gaps de numeração (F29)**: extrair IDs e ordenar. Gap (ex.: 1.0, 3.0 sem 2.0) → warning + `needs_input` se não confirmado intencional.
4. Reportar snapshot inicial: total, contagem por estado, pendentes, done puladas.

**Etapa 3: Loop topológico**

Repetir até zerar `pending` ou disparar halt:
1. Re-ler `tasks.md`.
2. **A wave vem do motor, não de interpretação:** `bash "${CLAUDE_PLUGIN_ROOT}/scripts/lt-sdd.sh" waves <dir-do-prd> --next`. Regra implementada e testada: pronta = `pending` com todas as dependências `done` (as cross-PRD resolvidas pelo `spec_repos`); `—` e `Não` rodam sozinhas; `Com X.Y` agrupa só com quem declara a recíproca; entre as prontas vence o menor id, e o grupo dele é a wave. `waves <dir-do-prd>` sem `--next` mostra o plano inteiro e as bloqueadas com o motivo.
3. `--next` com saída vazia e exit 0 → não há mais `pending`. Exit 1 → há `pending` bloqueada e nenhuma pronta: encerrar pela Etapa 6 com `partial` (ou `failed`, se nenhuma wave rodou), reportando o motivo que o comando imprime.
4. Disparar a wave devolvida, e só ela.
5. **Capacidades do runtime, antes de paralelizar**:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/lt-sdd.sh" runtime-capabilities --host claude
   ```
   Saída: JSON com `isolated_worktrees`, `safe_concurrent_writes`, `lock_strategy`,
   `cancellation_strategy` e `ownership_validation` (nos outros hosts, `--host codex|copilot|opencode`).
   A coluna `Paralelizável` de tasks.md decide **o que pode** rodar junto; o JSON decide **se o
   runtime aguenta**. Com `isolated_worktrees: false` e `safe_concurrent_writes: false` (valores
   atuais do harness), tarefas de uma mesma wave que escrevem arquivos rodam **em sequência**;
   só leitura pode rodar em paralelo. Registrar a decisão no `_orchestration_report.md`.
6. Disparar Etapa 4. Coletar resultados. Qualquer `≠ done` após validação → Etapa 5 (halt).

**Etapa 4: Spawnar subagents**

**Qual subagente:** no Claude Code, o subagente do plugin `lt:task-executor` (ferramenta Agent,
`subagent_type: "lt:task-executor"`), que já traz `execute-task` e `agent-governance`
pré-carregadas. No Codex, Copilot e OpenCode o mesmo agente é projetado como `task-executor`.
No Claude Code o hook `SubagentStop` do plugin (`subagent-stop-wrapper.sh`) confere o envelope
de 3 campos, o relatório e o checkpoint quando o subagente termina, e devolve a violação ao
próprio subagente para ele corrigir. Isso não substitui a cadeia de validação abaixo — é a
primeira linha dela.

**Timeout + orçamento de tokens (F14, RF-21):** `AI_TASK_TIMEOUT_SECONDS` (default 1800s) e
`AI_TASK_TOKEN_BUDGET` (default 0 = sem limite; zero-value preserva comportamento F1) configuráveis
em `.claude/config.yaml`/`${CLAUDE_PLUGIN_ROOT}/config.yaml`. Override de timeout por tarefa:
`<!-- task-timeout-seconds: N -->` (regex `^task-timeout-seconds:\s*(\d+)\s*$`, sem unidades).
Quando o subagent reportar uso de tokens acumulado acima de `AI_TASK_TOKEN_BUDGET`, marcar
`failed: token budget <budget> exceeded` e não relançar.

**Timeout e cancelamento:** respeite os limites de `AI_TASK_TIMEOUT_SECONDS` antes do
spawn. O adaptador só pode aplicar a estratégia de interrupção declarada pelo CLI e deve registrar
o resultado (`killed`, `discarded` ou falha) no `_orchestration_report.md`. Sem capacidade de
cancelamento, marque a tentativa como `failed` ao expirar e descarte resultados tardios; não
presuma que um runtime ou versão específica consiga encerrar o trabalho.

Prompt do subagent:
- Paths absolutos do task file, prd.md, techspec.md, tasks.md.
- "Invoque `execute-task`. Carrega APENAS necessário. Não saia do escopo."
- "`export AI_INVOCATION_DEPTH=0` + resolver `check-invocation-depth.sh` em cascata (`${CLAUDE_PLUGIN_ROOT}/lib/` → `scripts/lib/`) e fazer `source`."
- "`export AI_PREFLIGHT_DONE=1` — orquestrador já validou; pule esses gates."
- Contrato de retorno (idêntico em todos os tools):
  ```yaml
  status: done | blocked | failed | needs_input
  report_path: .lt/specs/prd-<slug>/<id>_execution_report.md
  summary: <1 linha>
  ```
  - **`report_path` DEVE ser relativo à raiz do repositório** (F13). Absoluto rejeitado; relativo ao subdir do subagent rejeitado. Validação resolve via `realpath --no-symlinks <repo_root>/<path>`.
  - Sem diffs, código ou logs.

**Cadeia de validação ao YAML retornado:**

**Fallback de YAML ausente (F25, crash entre execute-task Stage 5/6):**
- Sem retorno ou corrompido: verificar `.lt/specs/prd-<slug>/.checkpoints/<id>.json` (escrito por `execute-task` Stage 5.3).
- Existe e passa em `bash "${CLAUDE_PLUGIN_ROOT}/scripts/lt-sdd.sh" validate-result checkpoint .lt/specs/prd-<slug>/.checkpoints/<id>.json` (schema em `config/schemas/checkpoint.schema.json`): ler `status`, `report_path`, `summary` e `timestamp`, usar como retorno válido e registrar o consumo no relatório. O checkpoint é imutável e não deve ser apagado.
- Ausente: `failed: no return and no checkpoint`.

Cadeia (do retorno OU checkpoint) — pode ser executada por **hook programático** (enforcement real) ou inline:

**Hook recomendado**: `echo "$YAML" | bash ${CLAUDE_PLUGIN_ROOT}/scripts/cycle/post-execute-task.sh <slug> <task-id>` (cascata portátil `${CLAUDE_PLUGIN_ROOT}/hooks/` → `${CLAUDE_PLUGIN_ROOT}/scripts/cycle/` → outros mirrors). Exit ≠ 0 = falha em F2/F13/F24/F25/F35; reclassificar tarefa para `failed` repassando stderr do hook. **Sem degradação silenciosa**: ausente em todos os caminhos → `failed: hook 'post-execute-task.sh' ausente — reinstale o plugin lt pelo marketplace`; a cadeia de validação inline abaixo é o contrato que o hook impõe, nunca um substituto silencioso.

1. **Formato canônico**: bloco com exatamente `status`, `report_path`, `summary`, sem campos extras, campos duplicados, comentários ou texto livre/diff → `failed: contract violation`.
2. **Status canônico**: ∈ `{done, blocked, failed, needs_input}`. Fora → `failed: invalid status`.
3. **Evidência física (F2+F13)** para `done`: normalizar `realpath --no-symlinks <repo_root>/<report_path>`, validar `[ -s "<resolved>" ]`. Ausente/vazio → `failed: missing evidence (resolved=<path>)`. Path absoluto rejeitado.
4. **Consistência tasks.md** para `done`: re-ler tasks.md, confirmar status atualizado para `done`. Divergente → `failed: status drift`.

**Etapa 5: Halt-first + relatório**
1. **Wait-all-then-halt (F3, contra race)**:
   - Spawnar todos da wave. Aguardar TODOS concluírem antes de decidir.
   - Aplicar cadeia de validação a cada retorno.
   - Só então decidir halt — subagents paralelos podem mutar tasks.md concorrentemente; halt prematuro deixa writes pendentes.
2. **File lock** em writes de tasks.md: subagents usam `flock -x`/rename atômico/partials (orientação do prompt → `execute-task` Stage 5.5).
3. **Checkpoint do orquestrador (F31) — invocar hook**:
   - Após cada wave concluída e validada: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/cycle/post-wave.sh <slug> <wave-id> <results-yaml-file>` (busca nos mirrors padrão). Hook escreve `.lt/specs/prd-<slug>/_orchestration_report.partial.md` append-only.
   - Próxima invocação detecta `.partial.md` na Etapa 1: lê, consolida com tasks.md atual, usa como ponto de partida.
   - Ao concluir todas as waves: rename atômico `.partial.md` → `_orchestration_report.md`.
   - Se ambos existem na Etapa 1: prefere `.partial.md` + warning para usuário decidir.
   - Hook ausente em todos os caminhos → `failed: hook 'post-wave.sh' ausente — reinstale o plugin lt pelo marketplace` (sem modo legado silencioso; `${CLAUDE_PLUGIN_ROOT}/hooks/` é instalado por padrão).
4. **Rastreabilidade antes do relatório final**: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/lt-sdd.sh" check-traceability .lt/specs/prd-<slug>`. Exit 1 lista rupturas (RF sem tarefa, RF órfão, tarefa `done` sem relatório, relatório sem a linha `- Requisito:` do RF que a cobertura atribui à tarefa, critério sem `->`) — registrar no relatório e encerrar como `partial`.
5. Renderizar `_orchestration_report.md` (template em `assets/`) com snapshot inicial vs final, tabela executadas, puladas, waves, próximos passos.
6. NÃO mutar tasks.md no orquestrador — só subagents via `execute-task`.

**Etapa 6: Encerrar**
Retornar status: `done` (todas done), `partial` (alguma não-done), `failed` (pré-voo abortou), `needs_input`.

## Capacidades e adaptadores

O contrato de retorno é idêntico em todos os adaptadores. Antes de escolher spawn, paralelismo ou
modo de escrita, consulte `lt-sdd.sh runtime-capabilities --host <host>` e registre no relatório a
decisão tomada junto com o JSON retornado. Não inferir suporte por nome, versão, diretório ou tabela
desta skill. Se a capacidade necessária estiver ausente, escrita concorrente deve falhar fechada;
somente o caminho sequencial ou read-only aceito pelo CLI pode prosseguir.

## Regras invioláveis

1. Toda tarefa em subagent fresh — orquestrador nunca executa `execute-task` inline.
2. Contrato YAML estrito; violação = `failed: contract violation`.
3. Paralelismo só com flag em tasks.md e capacidades aprovadas pelo CLI.
4. Não coordenar arquivos entre paralelos sem ownership disjunto validado pelo CLI.
5. Orquestrador inline apenas: parsing tasks.md, DAG, report final, pré-voo, checkpoint.

## Tratamento de Erros

* **DAG inválido**: `failed` com cadeia. Sem reparo automático.
* **Contrato violado**: `failed: contract violation`, halt, relatório, encerrar.
* **Subagent não-done**: respeitar. Não re-executar.
* **tasks.md mutado externamente**: `needs_input`.
* **Profundidade**: orquestrador top-level (depth 0); cada subagent reinicia `AI_INVOCATION_DEPTH=0`.

## Resolução de paths

Todo caminho `.lt/specs/prd-<slug>/` citado neste documento é **ilustrativo**. O caminho real
vem sempre de `lt-sdd.sh specs-root`, nunca de concatenação manual. A cascata, na ordem:

1. `LT_TASKS_ROOT` — caminho explícito, relativo à raiz do repo ou absoluto.
2. `AI_TASKS_ROOT` — mesma função, nome herdado.
3. `tasks_root:` em `.lt/config.yaml` ou `.claude/config.yaml` do repo consumidor.
4. `.specs/` — quando existe em disco **ou** está versionado no git deste repo.
5. `.lt/specs/` — padrão do harness.

O prefixo do diretório da spec segue `${AI_PRD_PREFIX:-prd-}`.

> O passo 4 consulta o git de propósito: `isdir` responde pelo checkout, não pelo repositório, e
> um worktree novo de um repo que versiona `.specs/` resolveria para `.lt/specs/` enquanto o
> checkout principal usa `.specs/` — o mesmo repo com duas raízes de spec.
>
> Se o repo usa `.specs/` **sem versioná-lo**, nenhuma detecção acerta: declare `tasks_root` no
> config. É o único jeito determinístico em qualquer checkout.

## Contrato resumido

| Campo | Valor |
|-------|-------|
| Input | slug ou path |
| Pré-condições | prd/techspec/tasks presentes; lockfile íntegro; RF coverage OK |
| Saída por tarefa | YAML `{status, report_path, summary}` validado em 4 passos + fallback checkpoint |
| Saída agregada | `.lt/specs/prd-<slug>/_orchestration_report.md` (com `.partial.md` durante execução) |
| Status final | `done \| partial \| failed \| needs_input` |
| Mutação direta tasks.md | Não |
| Re-execução automática | Não |
| Paralelismo | `runtime-capabilities` + flag `Paralelizável` + ownership disjunto |
| Timeout default | 1800s; estratégia de interrupção detectada e registrada pelo adaptador |
| Orçamento de tokens | `AI_TASK_TOKEN_BUDGET` (default 0 = ilimitado; zero-value preserva F1) |
