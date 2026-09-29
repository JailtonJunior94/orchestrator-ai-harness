# Tarefa X.0: [Título da Tarefa]

<critical>Ler prd.md e techspec.md desta pasta — sua tarefa será invalidada se você pular</critical>

## Visão Geral

[Descrição breve da tarefa]

<requirements>
[Lista de requisitos obrigatórios]
</requirements>

## Subtarefas

- [ ] X.1 [Descrição da subtarefa]
- [ ] X.2 [Descrição da subtarefa]

## Detalhes de Implementação

[Seções relevantes da tech spec — **referenciar techspec.md em vez de duplicar conteúdo**]

## Critérios de Sucesso

- [Resultados mensuráveis]
- [Requisitos de qualidade]

## Skills Necessárias

<!-- MANDATÓRIO: preenchido por `create-tasks` Etapa 4.1 via descoberta agnóstica em `${CLAUDE_PLUGIN_ROOT}/skills/`.
     NÃO inclua aqui skills cuja categoria no frontmatter seja `governance` ou `language`:
     elas são auto-carregadas em runtime. A classificação deriva exclusivamente de `category`,
     nunca do nome da skill.
     Use o conteúdo único `Nenhuma além das auto-carregadas (governance + linguagem).` se a tarefa
     não exigir skill processual extra. -->

- `<skill-name>` — <justificativa de 1 linha do gatilho detectado no PRD/techspec>

## Testes da Tarefa

<!-- Copie da Matriz Requisito → Teste da techspec as linhas dos RFs desta tarefa (R-TEST-002). -->

- [ ] Testes unitários: [cenários e comportamento que derrubam]
- [ ] Testes de integração: [adapters de fronteira tocados, ou "nenhum adapter tocado"]
- [ ] Testes E2E: [jornada crítica tocada, ou "nenhuma jornada crítica tocada"]
- [ ] Cobertura de cada pacote tocado ≥ 70%, sem queda (R-TEST-002.1)

<critical>SEMPRE CRIAR E EXECUTAR TESTES DA TAREFA ANTES DE CONSIDERAR A TAREFA COMO `done`</critical>

## Arquivos Relevantes
- [Arquivos relevantes para esta tarefa]
