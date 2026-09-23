---
name: create-prd
description: Cria documentos de requisitos do produto a partir de solicitações de funcionalidade. Use quando uma funcionalidade precisar de escopo, objetivos, restrições e requisitos funcionais numerados antes do desenho técnico. Detecta artefatos downstream (techspec, tasks) ao evoluir PRD existente e exige confirmação para evitar drift silencioso. Não use para planejamento de implementação, mudanças de código ou decisões de arquitetura técnica.
metadata:
  category: governance
  version: 2.0.0
---

# Criar PRD

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

## Procedimentos

**Etapa 1: Validar o ponto de partida**
1. Confirmar que a solicitação é de definição de produto ou funcionalidade, não de implementação ou correção.
2. Derivar um slug estável da funcionalidade em kebab-case e planejar a saída em `.lt/specs/prd-<slug-da-funcionalidade>/prd.md`.
3. Se a pasta alvo ou o PRD já existirem, ler primeiro e evoluir o artefato existente em vez de criar um documento concorrente.
4. **Gate de drift downstream (best-effort, depende do agente verificar)**: ao detectar PRD pré-existente, executar `ls .lt/specs/prd-<slug>/` e verificar a presença de QUALQUER um destes artefatos:
   - `.lt/specs/prd-<slug>/techspec.md`
   - `.lt/specs/prd-<slug>/tasks.md`
   - qualquer `task-*.md` (arquivos de tarefa individual)
   - qualquer `*_execution_report.md` (evidência de execução por tarefa)
   - `_orchestration_report.md` (rollup de orquestração via `execute-all-tasks`)
   - qualquer `adr-*.md` (decisões arquiteturais derivadas)
   Se algum existir, **parar com `needs_input` mandatório** com mensagem: "PRD será editado; <lista de artefatos detectados> podem ficar desatualizados. Spec-version será incrementada e o spec-hash em tasks.md vai divergir, disparando `blocked` em `execute-task` Stage 1 nas próximas execuções. Você quer (a) prosseguir e regenerar techspec/tasks depois, (b) editar só itens não-disruptivos (typos, clarificações sem mudança de RF), ou (c) cancelar?". Sem confirmação explícita, não editar.

   **Limite honesto**: este gate é **best-effort enforcement** — depende do agente seguir a instrução de listar o diretório. Não há validação programática que force a verificação. Se o agente pular esta etapa, drift silencioso pode ocorrer. Para auditoria robusta, adicionar `bash "${CLAUDE_PLUGIN_ROOT}/scripts/lt-sdd.sh" check-spec-drift .lt/specs/prd-<slug>/tasks.md` em pre-commit hook ou CI.

**Etapa 2: Coletar o contexto mínimo viável de produto**
1. Fazer perguntas de esclarecimento cobrindo as seis categorias obrigatórias:
   - problema e objetivo
   - usuário ou ator principal
   - escopo incluído
   - escopo excluído
   - restrições e conformidade
   - critérios de sucesso mensuráveis
2. Parar após no máximo duas rodadas de esclarecimento.
   - **Ambiguidade material** (escopo/fronteira/objetivo com caminhos divergentes): aplicar `skill lt:agent-governance, referencia multiple-choice-protocol.md` (2–5 opções, "(Recomendado)", uma pergunta por turno). Não usar em pontos triviais.
3. Se ainda faltarem respostas objetivas ou houver contradições, retornar `needs_input`, listar os pontos em aberto e não redigir o PRD final.

**Etapa 3: Carregar apenas o contexto necessário para escrever bem**
1. Ler `assets/prd-template.md` antes de redigir.
2. Ler o contexto do repositório (README, AGENTS.md) apenas quando a funcionalidade depender de restrições específicas do projeto.
3. Ler `skill lt:agent-governance, referencia security.md` ou outras referências apenas quando impactarem as restrições de produto declaradas.
4. Usar pesquisa na web apenas quando a solicitação depender de fatos externos atuais, regulações, integrações ou restrições de mercado. Se a navegação não estiver disponível, declarar a suposição explicitamente.

**Etapa 4: Redigir o PRD**
1. Escrever o documento com foco de produto no que e por que, não no como.
2. Seguir `assets/prd-template.md` com fidelidade suficiente para preservar a intenção das seções, adaptando o conteúdo à funcionalidade.
3. Numerar requisitos funcionais para rastreabilidade.
4. Manter o documento concreto, testável e orientado a decisão.
5. Incluir a seção `Suposições e Questões em Aberto` sempre que restarem suposições.

**Etapa 5: Persistir o artefato**
1. Criar `.lt/specs/prd-<slug-da-funcionalidade>/` quando não existir.
2. Salvar o documento final como `.lt/specs/prd-<slug-da-funcionalidade>/prd.md`.
3. Incluir `<!-- spec-version: 1 -->` no topo do PRD na primeira versao. Incrementar o numero ao editar um PRD existente.
4. Evitar criar cópias alternativas em pastas ad hoc.

**Etapa 6: Encerrar com status explícito**
1. Informar o caminho final.
2. Resumir a funcionalidade em 3-5 linhas.
3. Listar suposições abertas ou questões não resolvidas.
4. Retornar estado final `done` quando o PRD estiver completo, caso contrário `needs_input`.

## Tratamento de Erros

* Se a solicitação pular direto para detalhes de implementação, redirecionar o documento para a intenção de produto e registrar itens técnicos apenas como restrições de alto nível.
* Se a definição do problema for ampla o bastante para esconder múltiplas features, dividir o escopo e perguntar qual fatia deve virar o PRD.
* Se um PRD existente conflitar com novas instruções, preservar as duas versões da decisão no histórico do documento e explicitar o conflito antes de sobrescrever conteúdo.

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
