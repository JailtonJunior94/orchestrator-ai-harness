---
name: bugfix
description: Corrige bugs pela causa raiz com testes de regressao obrigatorios e evidencia de validacao. Use quando o usuario pedir para corrigir bugs ou referenciar bugs.md, especialmente a partir de achados emitidos pela skill review. Nao use para review ou auditoria sem alteracao, nem para refatoracao sem defeito confirmado.
metadata:
  version: 2.0.0
  category: governance
---

# Corrigir Bugs

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

**Etapa 1: Validar entrada e escopo**
1. Verificar profundidade de invocação: resolver a raiz com `repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"` e localizar `check-invocation-depth.sh` em cascata `${CLAUDE_PLUGIN_ROOT}/lib/` (B1):
   ```bash
   _depth_lib=""
   for d in "$repo_root/${CLAUDE_PLUGIN_ROOT}/lib" "$repo_root/scripts/lib"; do
     [[ -r "$d/check-invocation-depth.sh" ]] && { _depth_lib="$d/check-invocation-depth.sh"; break; }
   done
   [[ -n "$_depth_lib" ]] || { echo "failed: check-invocation-depth.sh ausente em ${CLAUDE_PLUGIN_ROOT}/lib/ e scripts/lib/"; exit 1; }
   source "$_depth_lib" || { echo "failed: depth limit exceeded"; exit 1; }
   ```
2. Confirmar que a lista de bugs foi recebida no formato canonico `{ id, severity, file, line, reproduction, expected, actual }`. A `severity` segue o enum do schema (`critical`, `major`, `minor`); interpretar conforme `skill lt:agent-governance, referencia severity-mapping.md` — `critical`/`major` exigem correcao no escopo, `minor` pode virar risco residual conforme orcamento.
3. Ler `references/canonical-bug-format.md` quando houver duvida sobre campos obrigatorios, severidades ou estados canonicos.
4. Se a lista vier em arquivo JSON, validar contra o schema canonico com `python3 "$repo_root/skill lt:bugfix/scripts/validate-bug-input.py" --input <caminho>` antes de prosseguir. O script tenta JSON Schema (`jsonschema`) e cai para validacao manual equivalente quando a lib nao esta disponivel.
5. Se a lista estiver ausente, incompleta ou fora do formato canonico, retornar `needs_input` com os campos faltantes.
6. Confirmar o escopo de bugs a corrigir antes de editar qualquer arquivo.

**Etapa 2: Carregar o contexto tecnico**
1. Confirmar que o contrato de carga base definido em `AGENTS.md` foi cumprido.
2. Se a correcao tocar codigo Go **e** `skills-available --category language` listar `go-implementation`, ler tambem `skill lt:go-implementation/SKILL.md` e apenas as referencias exigidas pela mudanca. Para outras linguagens, carregar a skill `skill lt:<lang>-implementation/SKILL.md` quando existir; caso contrario, seguir apenas com governanca transversal.
3. Ler `bugs.md`, `prd.md`, `techspec.md`, arquivos de tarefa ou contexto de issue quando estiverem disponiveis e forem relevantes para o bug.
4. Mapear contratos publicos, comportamento esperado, pontos de integracao e risco de regressao antes de propor a correcao.

**Etapa 3: Priorizar e diagnosticar**
1. Ordenar os bugs por severidade: `critical`, `major`, `minor`.
2. Identificar a causa raiz de cada bug antes de editar.
3. Marcar como `blocked` qualquer bug que dependa de contexto externo indisponivel e seguir com os demais bugs do escopo.
4. Evitar patches superficiais quando a causa raiz ainda nao estiver clara.

**Etapa 4: Corrigir e testar**
1. Aplicar a menor mudanca segura focada na causa raiz.
2. Criar um teste de regressao para cada bug corrigido que reproduza `reproduction` e valide `expected`.
3. Seguir Etapa 4 de `skill lt:agent-governance/SKILL.md`.
4. Se a validacao falhar, analisar o log e tentar apenas uma remediacao limitada adicional para o mesmo bug.
5. Se o limite de duas tentativas por bug for excedido, marcar o bug como `failed`, registrar o diagnostico e seguir para o proximo bug elegivel.

**Etapa 5: Revisar e registrar evidencias**
1. Registrar para cada bug o arquivo alterado, o teste de regressao adicionado e o resultado da validacao.
2. Registrar a **origem** de cada bug (campo `Origem:` com RF, task, finding de review ou issue) — rastreabilidade exigida por padrao pelo validador.
3. Atualizar o estado de cada bug usando apenas `fixed`, `blocked`, `skipped` ou `failed`.
4. Ler `assets/bugfix-report-template.md`.
5. Salvar o relatorio em `.lt/specs/prd-<feature-slug>/bugfix_report.md` quando estiver em contexto de tarefa; caso contrario, em `./bugfix_report.md`.
6. Validar o relatorio com o validador resolvido em cascata portátil (`${CLAUDE_PLUGIN_ROOT}/scripts/validate-bugfix-evidence.sh` → `.claude/scripts/validate-bugfix-evidence.sh` → `scripts/validate-bugfix-evidence.sh`): `bash "<primeiro-existente>" <caminho-do-relatorio>` (a rastreabilidade de origem e default-on; quando os IDs de RF forem conhecidos, passar `--rf <RF-ID>` para casar cada um); corrigir secoes faltantes antes de encerrar.

**Etapa 6: Encerrar o fluxo**
1. Informar total de bugs no escopo, quantos foram corrigidos, quantos testes de regressao foram adicionados e quais itens ficaram pendentes com motivo.
2. Retornar apenas um destes estados canonicos:
   - `done`: escopo acordado corrigido e validado
   - `blocked`: existe bug critico bloqueado por contexto externo
   - `needs_input`: faltam dados obrigatorios de reproducao ou escopo
   - `failed`: limite de remediacao excedido ou validacao nao comprovou a correcao

## Tratamento de Erros

* Se a entrada nao corresponder ao formato canonico, solicitar a conversao antes de prosseguir com a correcao.
* Se uma correcao alterar comportamento publico, parar e explicitar a mudanca a menos que ela tenha sido solicitada.
* Se `go test ./...` ou o equivalente do projeto falhar apos a correcao, analisar o log de falha antes de reexecutar.
* Se a baseline do repositorio ja estiver quebrada, separar claramente a falha preexistente das falhas introduzidas pela correcao.
* Respeitar o limite de profundidade de invocacao definido em `skill lt:agent-governance/SKILL.md`. Bugfix **nao** reinvoca review por conta propria: quem abre a rodada seguinte de revisao e o orquestrador do Ciclo de Aprovacao (RF-38). Cada rodada abre com a profundidade de invocacao resetada, e o que limita a cadeia `review -> bugfix -> review` e o **teto de rodadas** do Ciclo (default 5, RF-35), nao a profundidade.

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
