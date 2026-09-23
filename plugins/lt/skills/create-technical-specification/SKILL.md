---
name: create-technical-specification
description: Cria especificações técnicas prontas para implementação a partir de um PRD aprovado e do contexto do repositório. Registra spec-hash do PRD consumido no cabeçalho da techspec para rastreabilidade e detecção de drift downstream. Use quando arquitetura, interfaces, riscos, ADRs e estratégia de testes precisarem ser definidos antes da codificação. Não use para descoberta de produto, execução de tarefa ou revisão de código.
metadata:
  category: governance
  version: 2.0.0
---

# Criar Especificação Técnica

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

**Etapa 1: Validar o artefato de entrada**
1. Confirmar que o PRD alvo existe em `.lt/specs/prd-<slug-da-funcionalidade>/prd.md`.
2. Extrair requisitos, restrições, métricas e itens fora de escopo do PRD antes de explorar o codebase.
3. Parar com `needs_input` se o PRD estiver ausente ou incompleto demais para sustentar decisões de arquitetura.

**Etapa 2: Mapear o repositório e as restrições técnicas**
1. Ler `AGENTS.md` e explorar a estrutura do repositório relevante para o PRD.
2. Explorar apenas os caminhos de código, módulos, integrações e interfaces relevantes para o PRD.
3. Mapear impactos em arquitetura, fluxo de dados, observabilidade, tratamento de erros e testes.
4. Se dependências externas ou o comportamento atual de fornecedores forem relevantes, verificar em documentação primária ou oficial.

**Etapa 3: Resolver bloqueios de arquitetura**
1. Fazer perguntas técnicas de esclarecimento cobrindo:
   - fronteiras de domínio
   - fluxo de dados
   - contratos de interface
   - falhas esperadas e idempotência
   - estratégia de testes
2. Limitar o esclarecimento a duas rodadas.
   - **Trade-off de arquitetura/interface material** (caminhos com consequências divergentes): aplicar `skill lt:agent-governance, referencia multiple-choice-protocol.md` (2–5 opções, "(Recomendado)", uma pergunta por turno).
3. Se a arquitetura continuar bloqueada após duas rodadas, retornar `needs_input` com as decisões faltantes.

**Etapa 4: Verificar conformidade com as regras do repositório**
1. Ler `skill lt:agent-governance/SKILL.md` e carregar referências sob demanda:
   - `skill lt:agent-governance, referencia ddd.md`
   - `skill lt:agent-governance, referencia error-handling.md`
   - `skill lt:agent-governance, referencia security.md`
   - `skill lt:agent-governance, referencia testing.md`
2. Para cada desvio intencional, registrar a justificativa e a alternativa aderente rejeitada.

**Etapa 5: Redigir a especificação técnica**
1. Ler `assets/techspec-template.md` antes de redigir.
2. Focar em como implementar a funcionalidade, não em reexplicar o PRD.
3. Incluir um mapeamento de requisito para decisão e teste.
4. Documentar abordagens escolhidas, trade-offs, alternativas rejeitadas, riscos e implicações de observabilidade.
5. Manter interfaces e modelos de dados concretos o suficiente para orientar a implementação.

**Etapa 6: Criar ADRs para decisões materiais**
1. Ler `assets/adr-template.md`.
2. Para cada decisão material introduzida na especificação técnica, criar uma ADR separada em `.lt/specs/prd-<slug-da-funcionalidade>/`.
3. Usar nomes estáveis de arquivo como `adr-001-<slug-da-decisao>.md`.
4. Vincular as ADRs a partir da especificação técnica.

**Etapa 7: Persistir e reportar**
1. **Calcular e injetar spec-hash do PRD no topo da techspec** (mandatório):
   - `<!-- spec-hash-prd: $(bash "${CLAUDE_PLUGIN_ROOT}/scripts/lt-sdd.sh" hash .lt/specs/prd-<slug>/prd.md) -->`
   - Esse comentário rastreia qual versão do PRD foi consumida; se o PRD for editado depois, `create-tasks` e `execute-task` detectam o drift comparando este hash com o atual.
2. Salvar a especificação técnica como `.lt/specs/prd-<slug-da-funcionalidade>/techspec.md`.
3. Informar o caminho final, os caminhos das ADRs e os itens ainda em aberto.
4. Retornar estado final `done` ou `needs_input`.

## Tratamento de Erros

* Se o PRD misturar produto com detalhe de implementação, preservar a intenção de produto e mover apenas as decisões de implementação para a especificação técnica.
* Se a exploração do repositório mostrar que o desenho solicitado viola regras existentes de arquitetura ou segurança, documentar o conflito explicitamente em vez de normalizá-lo em silêncio.
* Se a documentação externa de uma dependência estiver indisponível, marcar a decisão afetada como suposição e reduzir o raio de impacto dessa suposição na implementação proposta.

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
