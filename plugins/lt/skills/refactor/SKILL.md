---
name: refactor
description: Planeja ou executa refatorações incrementais seguras preservando comportamento e coletando evidências de não regressão. Use quando uma refatoração delimitada precisar de orientação consultiva ou execução com validação e revisão. Não use para entrega de nova funcionalidade, definição de escopo de produto ou reescritas cosméticas sem alvo verificado.
metadata:
  version: 1.2.0
  category: governance
  depends_on:
  - review
---

# Refatorar

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

## Procedimentos

**Etapa 1: Validar escopo e modo**
1. Confirmar que o escopo da refatoração é explícito o suficiente para limitar o risco.
2. Resolver o modo como `advisory`, a menos que `execution` tenha sido solicitado explicitamente.
3. Se o escopo for ambíguo ou amplo demais, retornar `needs_input` com os limites faltantes.

**Etapa 2: Carregar o contexto técnico relevante**
1. Confirmar que o contrato de carga base definido em `AGENTS.md` foi cumprido.
2. Se a refatoração tocar código Go **e** `skills-available --category language` listar `go-guideline`, ler também `skill lt:go-guideline/SKILL.md` e apenas as referências exigidas pela mudança.
3. Ler `skill lt:agent-governance, referencia ` sob demanda quando DDD, tratamento de erro, segurança ou testes afetarem a mudança proposta.
4. Mapear contratos públicos, pontos de integração e os caminhos de regressão mais prováveis antes de editar.

**Etapa 3: Produzir a saída consultiva ou executar a refatoração**
1. No modo `advisory`:
   - descrever os pontos de dor atuais
   - propor o menor plano seguro de refatoração
   - destacar invariantes, riscos e validações exigidas
   - evitar editar arquivos, a menos que o usuário mude explicitamente para `execution`
2. No modo `execution`:
   - aplicar o menor conjunto seguro de mudanças
   - preservar comportamento observável e contratos públicos
   - adicionar ou atualizar testes quando o comportamento puder regredir

**Etapa 4: Validar não regressão**
1. Seguir Etapa 4 de `skill lt:agent-governance/SKILL.md`.
2. Se a validação falhar, tentar apenas uma remediação limitada.

**Etapa 5: Revisar e persistir evidências**
1. No modo `execution`, invocar a skill `review` sobre o diff produzido.
2. Se `review` retornar `REJECTED` com bugs no formato canônico, invocar a skill `bugfix` para corrigir apenas esses itens dentro do escopo acordado.
3. Após `bugfix`, rerodar as validações proporcionais e uma nova revisão antes de concluir.
4. Aceitar como veredito aprovador final (RF-33): `APPROVED`, ou `APPROVED_WITH_REMARKS` desde que nenhum achado seja `[HIGH]` ou `[CRITICAL]`. Qualquer achado high/critical impede o encerramento e realimenta a correcao; achados `[MEDIUM]`/`[LOW]` permanecem registrados no relatorio como divida declarada. `APPROVED_WITH_REMARKS` sem nenhum achado declarado nao encerra (fail-closed).
5. Ler `assets/refactor-report-template.md`.
6. Salvar o relatório em `.lt/specs/prd-<feature-slug>/refactor_report.md` quando estiver em contexto de tarefa; caso contrário, em `./refactor_report.md`.
7. Validar o relatório com o validador resolvido em cascata portátil (`${CLAUDE_PLUGIN_ROOT}/scripts/validate-refactor-evidence.sh` → `.claude/scripts/validate-refactor-evidence.sh` → `scripts/validate-refactor-evidence.sh`): `bash "<primeiro-existente>" <caminho-do-relatorio>`; corrigir seções faltantes antes de encerrar.

**Etapa 6: Retornar o estado final**
1. Informar modo, validações, veredito do revisor quando aplicável e caminho do relatório.
2. Retornar `done`, `blocked`, `failed` ou `needs_input`.

## Tratamento de Erros

* Se a refatoração solicitada alterar comportamento público, explicitar isso e parar, a menos que a mudança de comportamento tenha sido pedida.
* Se o codebase não tiver testes adequados para proteger uma refatoração arriscada, reduzir o escopo da refatoração ou adicionar cobertura faltante antes de prosseguir.
* Se uma baseline quebrada impedir provar não regressão, documentar a falha da baseline separadamente das falhas induzidas pela refatoração.
* Respeitar o limite de profundidade de invocação definido em `skill lt:agent-governance/SKILL.md`. Se review invocar bugfix e bugfix precisar de nova review, esta é a profundidade máxima.
