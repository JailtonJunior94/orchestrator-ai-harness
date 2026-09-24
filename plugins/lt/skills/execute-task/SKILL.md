---
name: execute-task
description: Executa uma tarefa de implementação aprovada via codificação, validação, revisão e captura de evidências. Carrega skills processuais declaradas em `## Skills Necessárias` (formato canônico estrito) + skills de linguagem inferidas do diff. Use quando um task file estiver pronto para implementação, para retomar uma tarefa após REJECTED do review com bugs canônicos, e para amarrar a evidência de uma tarefa ao commit (seal-evidence). Não use para planejamento.
metadata:
  version: 2.1.0
  category: governance
  depends_on:
  - review
  - bugfix
  - agent-governance
---

# Executar Tarefa

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

> **Camada de linguagem é opcional.** As skills `*-implementation` (Go, Node, Python, .NET) e as
> de design não vêm nesta versão do plugin. Antes de mandar carregar qualquer uma, **verifique o
> que existe**:
>
> ```bash
> bash "${CLAUDE_PLUGIN_ROOT}/scripts/lt-sdd.sh" skills-available --category language
> ```
>
> Saída vazia significa que a camada não está instalada — siga sem ela e diga isso à pessoa.
> Nunca instrua a carregar uma skill que você não confirmou existir: instruir o agente a abrir
> algo inexistente é o defeito mais caro deste harness.

## Procedimentos

**Etapa 1: Validar elegibilidade**
1. **Resolver lib de profundidade (B1, fallback agnóstico)**: procurar `check-invocation-depth.sh` na ordem `${CLAUDE_PLUGIN_ROOT}/lib/`. Ausente = erro, nunca degradacao silenciosa:
   ```bash
   _depth_lib=""
   for d in ${CLAUDE_PLUGIN_ROOT}/lib scripts/lib; do
     [[ -r "$d/check-invocation-depth.sh" ]] && { _depth_lib="$d/check-invocation-depth.sh"; break; }
   done
   [[ -n "$_depth_lib" ]] || { echo "failed: check-invocation-depth.sh ausente em ${CLAUDE_PLUGIN_ROOT}/lib/ e scripts/lib/ — vendor a lib ou reinstale o plugin lt pelo marketplace"; exit 1; }
   source "$_depth_lib" || { echo "failed: depth limit exceeded"; exit 1; }
   ```
   Fallback de método (sem `source`): `bash "$_depth_lib"` + `eval`.
2. **Gate do motor SDD (B2, sem degradação silenciosa)**: se a Etapa 1.3 abaixo for executar (`AI_PREFLIGHT_DONE` ausente), validar que o motor está presente antes:
   ```bash
   if [[ -z "${AI_PREFLIGHT_DONE:-}" ]] && [[ ! -f "${CLAUDE_PLUGIN_ROOT}/scripts/lt-sdd.sh" ]]; then
     echo "needs_input: motor SDD ausente em ${CLAUDE_PLUGIN_ROOT}/scripts/lt-sdd.sh. Reinstale o plugin, OU exporte AI_PREFLIGHT_DONE=1 quando o orquestrador já validou drift e skills lock."
     exit 1
   fi
   ```
   Sem o motor a skill **deve parar com `needs_input`** — não prosseguir em modo legado silencioso. Princípio: governança acima de automação mágica.

   > Este gate checava `command -v harness lt`, herdado do harness de origem, que instalava um
   > binário. Este plugin não instala binário nenhum: o gate reprovava em toda máquina, e
   > `execute-task` parava com `needs_input` **sempre**, sem nunca conseguir executar tarefa.
   > O que precisa existir é o dispatcher `scripts/lt-sdd.sh`.
3. **Pre-flight gates condicionais (F8)**:
   - `AI_PREFLIGHT_DONE=1` exportada → pular gates (orquestrador já validou).
   - Sem `AI_PREFLIGHT_DONE`, rodar nesta ordem e parar em qualquer falha:
     `lt-sdd.sh assert-approved <bundle> tasks`, `lt-sdd.sh check-spec-drift <bundle>` e
     `lt-sdd.sh validate-sdd <bundle>`.
4. Verificação de drift de skills: **não disponível nesta versão do harness** (o plugin ainda não mantém um lock de skills). Siga para o próximo passo.
5. Derivar `<slug>` do path. Ambíguo → `needs_input`.
6. Confirmar `tasks.md`, task file alvo, `prd.md`, `techspec.md` presentes.
7. Selecionar primeira tarefa elegível só se usuário não escolheu.
8. Confirmar deps em `done` → senão `blocked`.

**Etapa 2: Carregar contexto**
1. Ler task file, `prd.md`, `techspec.md` por completo.
2. **Coerência temporal**: o pre-flight por hash é bloqueante; timestamp serve apenas como diagnóstico.
3. Confirmar AGENTS.md base contract.
4. **Detecção de linguagem (F1)**:
   - Inspecionar `Arquivos Relevantes`: Go (`*.go`), Node (`*.ts/.tsx/.js/.jsx/.mjs`), Python (`*.py`).
   - Linguagem detectada → confirmar a camada com `bash "${CLAUDE_PLUGIN_ROOT}/scripts/lt-sdd.sh" skills-available --category language`.
     - Camada instalada e skill da linguagem presente → ler `skill lt:<linguagem>-implementation/SKILL.md`.
     - Camada instalada e skill da linguagem ausente → `needs_input`.
     - Camada não instalada (saída vazia) → seguir sem ela e registrar em `## Suposições` do relatório, como manda o aviso do topo desta skill. `validate-skill-prerequisites.sh` aplica a mesma regra.
   - **Tarefas non-code** (docs, configs, SQL, shell, MD): nenhuma skill de linguagem; prosseguir.
5. **Skills processuais declaradas (F6+F16+F28)**:
   - Parsear seção `## Skills Necessárias` (gerada por `create-tasks` v1.4+).
   - **Normalizar antes de validar**: trim, colapsar espaços, aceitar separadores equivalentes (` — `, ` - `, `:`) e reformatar mentalmente para `^- \`([a-z0-9-]+)\` — .+$`. Linha semanticamente ambígua → `failed: malformed Skills Necessárias entry on task <id>: <linha>`.
   - Conteúdo canônico `Nenhuma além das auto-carregadas (governance + linguagem).` = vazio. Variações vazias equivalentes (`Nenhuma.`, `N/A`, `nenhuma`) = vazio com warning.
   - Ler coluna `Skills` em `tasks.md` (`—` = vazio).
   - **Sync gate (sem união silenciosa)**: divergente → `failed: skills sync drift on task <id> — file=<S_file> table=<S_table>`.
   - Ambas vazias: prosseguir (retrocompatível).
   - UMA fonte vazia outra preenchida: `failed: skills declaration missing in <fonte>`.
   - Para cada skill: validar `skill lt:<skill>/SKILL.md` existe (`needs_input` se não); ler description + procedimentos; refs sob demanda.
   - **Regras agnósticas**: nunca inferir por heurística textual; nunca carregar não-declaradas; descoberta via `ls "${CLAUDE_PLUGIN_ROOT}/skills/"`.
6. Mapear objetivo, critérios, subtarefas, arquivos-alvo antes de editar.

**Etapa 3: Implementação**
1. Seguir ordem das subtarefas. Implementar testes junto com produção.
2. Resolver entrypoint (parar no primeiro): `task test|lint|fmt` → `make test|lint|fmt` → nativo (`go test ./... && go vet`, `pnpm test && pnpm lint`, `pytest && ruff check`). Nenhum → `needs_input`.
3. Validação direcionada após cada subtarefa, não só no final.
4. Registrar comandos e arquivos. `needs_input` se decisão obrigatória bloquear.

**Etapa 4: Validação + revisão (F24)**
1. Seguir Etapa 4 de `agent-governance`.
2. Teste/lint do pacote afetado (mandatório). Suíte completa (`hard`) se diff cruzar pacote, alterar API pública, ou tocar config compartilhada.
3. Verificar critérios com evidência explícita. **Preencher `## Critérios de Aceite` do report com um item `-> comprovado: <evidência física>` por critério da task file (`## Critérios de Sucesso`/`## Critérios de Aceite`); marcar o DoD. O validador rejeita critério sem comprovação e `Testes: pass` sem comando de teste correspondente.**
4. Invocar `review` com prd.md + techspec.md como contexto.
5. **Mapear veredito**:
   - `APPROVED` → Etapa 5.
   - `APPROVED_WITH_REMARKS` → **encerra somente sem achado `[HIGH]`/`[CRITICAL]` (RF-33)**. Com pelo menos um achado high/critical, não encerra: tratar como entrada de `bugfix` no escopo, rerodar validações e abrir nova rodada de review. Sem achado high/critical, encerra e os achados `[MEDIUM]`/`[LOW]` ficam registrados no relatório como dívida declarada — visíveis, nunca apagados. Sem nenhum achado declarado, não encerra (fail-closed: prosa não parseada não é prova de ausência).
   - `REJECTED` com bugs canônicos → `bugfix` no escopo, rerodar validações + nova review. Diga
     sempre em qual rodada o ciclo `review → bugfix → review` está e qual é o teto (default 5,
     RF-35): estourado o teto sem veredito aprovador, a tarefa termina `failed`, nunca `done`.
   - `REJECTED` sem formato canônico → `failed`.
   - `BLOCKED` → `blocked`; **não** invocar `bugfix`.
6. Final aceito com `APPROVED`, ou com `APPROVED_WITH_REMARKS` sem achado `[HIGH]`/`[CRITICAL]`, **e** mapa 1:1 completo entre cada critério de aceite e uma linha de evidência verificável (RF-33/RF-47). Qualquer outro veredito não encerra.

**Etapa 5: Persistir evidências (F25 checkpoint)**
1. Salvar `.lt/specs/prd-<slug>/[num]_execution_report.md` (overwrite com `# Generated: <ISO-8601 UTC>` no header — F36) a partir de `assets/task-execution-report-template.md`.
2. **`execution-result.json` v2 é obrigatório para `done`.** O validador reprova `done` sem ele; não é opcional. Gravar no diretório do bundle e apontar no relatório com a linha `result_path=<caminho relativo à raiz do repo>`. Campos exigidos por `validate-task-evidence.sh`:
   - `schema_version: 2`, `run_id`, `task_id` (igual ao `- ID:` do relatório), `attempt`, `status`, `base_sha` (a árvore `BEFORE` abaixo, ou o commit sobre o qual a tarefa começou);
   - `patch_sha256`: SHA-256 do patch **desta** tarefa, salvo em arquivo (`patch_ref`), e **o mesmo valor** na linha `sha=` do bloco `## Diff Reviewed` do relatório (64 hex). O harness não commita, então tarefas seguidas na mesma árvore não podem usar `git diff <commit>`: o patch da 2.0 carregaria o da 1.0. Tirar um snapshot de árvore antes e depois, sem criar commit nem mexer em branch ou índice real:
     ```bash
     BEFORE=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/lt-sdd.sh" snapshot)   # início da Etapa 3; vai em base_sha
     AFTER=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/lt-sdd.sh" snapshot)    # fim da Etapa 4, antes do relatório
     PATCH_SHA=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/lt-sdd.sh" task-patch "$BEFORE" "$AFTER" <patch_ref> --exclude <dir-do-bundle>)
     ```
     `snapshot` usa índice temporário: não cria commit, não move ref e não mexe no índice real. Não reescreva isso em shell: a receita manual falha com índice vazio e o `rm -rf` da limpeza é bloqueado pelo hook destrutivo.
     O `post-execute-task.sh` (F35) confere que esse arquivo ainda tem o hash declarado e que `git apply --reverse --check` passa, isto é, que as mudanças continuam na árvore;
   - `patch_ref`, `final_state_sha256`, `review_verdict`;
   - `evidence`: lista de caminhos relativos à raiz do repo, todos existentes, dentro do repositório;
   - `tests`: `[{command, exit_code, output_sha256}]`, com `exit_code: 0` e `output_sha256` igual ao SHA-256 de um arquivo listado em `evidence` (o log do teste);
   - `criteria`: `[{id, evidence_ref}]`, com cada `evidence_ref` presente em `evidence`.
   O bloco `## Coverage` exige `delta=<n>%`: medir a cobertura antes e depois da tarefa; delta negativo reprova.
   - Conferir o JSON contra o schema versionado (`config/schemas/execution-result.schema.json`) antes de seguir:
     ```bash
     bash "${CLAUDE_PLUGIN_ROOT}/scripts/lt-sdd.sh" validate-result execution <result_path> --task-id <num>
     ```
     Recusa campo desconhecido, `review_verdict` fora de `APPROVED | APPROVED_WITH_REMARKS | REJECTED | BLOCKED`, `done` sem veredito aprovador ou com teste de exit ≠ 0, e referência de evidência absoluta ou com `..`.
   - Na seção `## Tarefa` do relatório, uma linha `- Requisito: RF-nn[, RF-mm]` com os requisitos que a `## Cobertura de Requisitos` do tasks.md atribui a esta tarefa. É o que `check-traceability` confronta.
3. Rodar validador de evidências (resolver em cascata portátil: `${CLAUDE_PLUGIN_ROOT}/scripts/...` → `.claude/scripts/...` → `scripts/...`). Nenhum → `failed`. Falha → `blocked`; não mutar tasks.md.
4. **Checkpoint JSON antes de mutar tasks.md (F25)**:
   - `mkdir -p .lt/specs/prd-<slug>/.checkpoints/`.
   - Escrever `.checkpoints/<num>.json.tmp` com `status`, `report_path`, `summary`, `timestamp` (ISO-8601 UTC).
   - `mv -n .json.tmp .json` atômico. Completo ou inexistente, nunca parcial.
   - Conferir: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/lt-sdd.sh" validate-result checkpoint .lt/specs/prd-<slug>/.checkpoints/<num>.json`.
5. **Só após checkpoint persistido**, mutar tasks.md para `done`.
6. **Lock atômico em tasks.md (F3+F32)** quando invocador é `execute-all-tasks` em wave paralela:
   - POSIX: `flock -x -w 30 .lt/specs/prd-<slug>/tasks.md.lock -c '<edit>'`.
   - Sem `flock`: temp + `mv -n` atômico.
   - Fallback final (Windows nativo, containers minimal): escrever em `.lt/specs/prd-<slug>/.partials/tasks.md.<num>.partial`; orquestrador consolida na sua Etapa 5.
   - Lock falha em 30s → `failed: tasks.md lock timeout`.

**Etapa 6: Conferir o contrato do relatório (RF-14)**
1. `bash "${CLAUDE_PLUGIN_ROOT}/scripts/lt-sdd.sh" seal-evidence <relatorio_execucao.md>`.
   - O comando recebe o **relatório** `.md`, não o `execution-result.json`.
   - Sem flags, confere as seções obrigatórias do contrato v2 e que cada item de `## Critérios de Aceite` está na forma `- <critério> -> comprovado: <evidência>`. Não grava nada.
   - Rejeição → `blocked`; não mutar estado.
2. O harness não cria commits (`R-GOV-001`). Nesta etapa a evidência fica verificada contra a árvore de trabalho: registrar isso em `## Riscos Residuais`.
3. **Selo de commit — opcional, depois que o humano commitar o trabalho.** Torna a evidência re-auditável sem a árvore viva:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/lt-sdd.sh" seal-evidence <relatorio_execucao.md> --commit <sha>
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/lt-sdd.sh" seal-evidence <relatorio_execucao.md> --verify
   ```
   - `--commit` lê o `execution-result.json` apontado por `result_path=`, exige `status: done`, confere que o commit descende de `base_sha` (`git merge-base --is-ancestor`) e grava `commit_sha` + `commit_patch_sha256` (SHA-256 de `git diff --binary <base_sha> <commit>`, sem o diretório do bundle, o `patch_ref` e as evidências). Resultado já selado é recusado.
   - Se `base_sha` for a árvore do `snapshot` (e não um commit), árvore não tem ancestralidade: passar também `--base <commit sobre o qual a tarefa começou>`. O digest continua calculado a partir de `base_sha`.
   - `--verify` recompõe o digest a partir dos dois SHAs e falha se divergir do selo.
   - O selo não prova que o commit é byte-idêntico à árvore do fechamento — essa árvore já não existe.

**Etapa 7: Encerrar**
Retornar `done`, `blocked`, `failed` ou `needs_input` (canônico) com path do relatório, validações, veredito do reviewer e o resultado de `seal-evidence`.

## Paralelismo e Subagentes

Spawn APENAS se: (1) saída excede o que principal precisa reter, (2) trabalho independente, (3) custo de spawn < custo de bruto no contexto. Não spawnar para: arquivo já carregado; sequencial dependente; paralelas tool calls (Bash/Edit) já resolvem.

Aplicação: Etapa 2 (refs grandes multi-linguagem), Etapa 3 (subtarefas em pacotes distintos). Etapa 4: `task test`+`task lint` paralelos via Bash, sem subagente. Etapa 5: sempre inline. Registrar em "Comandos Executados" como `subagent[<desc>] -> <resumo>`.

## Tratamento de Erros

* Task file desatualizado vs código/spec → parar e expor antes de editar.
* Validação falha → uma remediação limitada; falha mais profunda → `failed` com comando bloqueante + diagnóstico.
* Respeitar depth limit de `agent-governance`. O Ciclo é iterativo no mesmo nível de invocação: cada rodada abre com a profundidade resetada e o que limita a cadeia `review → bugfix → review` é o **teto de rodadas** (default 5, RF-35/RF-38), não a profundidade.

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
