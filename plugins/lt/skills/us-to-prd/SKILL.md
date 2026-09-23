---
name: us-to-prd
description: Converte User Stories brutas em um PRD estruturado com objetivo, escopo, restricoes e requisitos funcionais numerados. Use como etapa anterior ao create-prd quando a entrada for historias de usuario (formato "Como <persona>, quero <acao>, para <valor>"). Nao use para criar PRDs a partir do zero sem historias de usuario.
metadata:
  category: governance
  version: 1.0.1
---

# User Stories para PRD

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

**Etapa 1: Receber e analisar as User Stories**
1. Confirmar que o contrato de carga base definido em `AGENTS.md` foi cumprido.
2. Coletar todas as User Stories fornecidas (formato livre ou "Como/Quero/Para").
2. Identificar personas, acoes e valores de negocio em cada historia.
3. Agrupar historias por tema ou modulo funcional.
4. Listar ambiguidades e lacunas que precisam de esclarecimento antes de prosseguir.

**Etapa 2: Derivar requisitos funcionais**
1. Converter cada historia em um ou mais requisitos funcionais (RF-nn).
2. Numerar sequencialmente a partir de RF-01.
3. Cada RF deve ser: atomico, testavel, sem detalhes de implementacao.
4. Identificar criterios de aceite para cada RF.

**Etapa 3: Estruturar o PRD**
1. Redigir as secoes: Objetivo, Escopo, Restricoes, Usuarios-alvo, Requisitos Funcionais.
2. Adicionar secao de Requisitos Nao-Funcionais quando identificados nas historias.
3. Incluir a lista original de User Stories como apendice para rastreabilidade.
4. Salvar em `.lt/specs/<slug-feature>/prd.md`.

**Etapa 4: Validar com o solicitante**
1. Apresentar o PRD gerado para revisao.
2. Destacar suposicoes feitas na conversao de historias para requisitos.
3. Aguardar aprovacao antes de prosseguir com `create-technical-specification`.

## Tratamento de Erros

* Se as historias forem incompletas ou contraditórias, listar os conflitos e perguntar antes de converter.
* Se uma historia nao tiver valor de negocio claro, marcar como `RF pendente` e pedir esclarecimento.
* Nao inferir requisitos tecnicos (ex: "usar PostgreSQL") a partir de historias que nao mencionam tecnologia.
