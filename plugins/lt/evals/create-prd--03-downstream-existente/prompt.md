Atualiza o PRD em evals/fixtures/bundle-extrato/prd.md para incluir exportação em PDF. A techspec e as tasks desse bundle já foram aprovadas.

O repositório não está disponível nesta sessão; o conteúdo atual dos arquivos citados vai abaixo.

`evals/fixtures/bundle-extrato/prd.md`:

```
<!-- spec-version: 1 -->
# PRD — Extrato em CSV

## Objetivo
Reduzir pedidos de extrato ao suporte.

## Requisitos Funcionais
- RF-01: o cliente exporta o extrato do mês corrente em CSV pelo app.
- RF-02: o CSV traz data, descrição, valor e saldo, em UTF-8.

## Fora de escopo
- Exportação em PDF.
```

`evals/fixtures/bundle-extrato/techspec.md`:

```
<!-- spec-hash-prd: 0000000000000000000000000000000000000000000000000000000000000000 -->
# TechSpec — Extrato em CSV

## Arquitetura
- Endpoint GET /extratos/{mes}.csv no serviço de extrato (RF-01, RF-02).
```

`evals/fixtures/bundle-extrato/tasks.md`:

```
<!-- spec-hash-prd: 0000000000000000000000000000000000000000000000000000000000000000 -->
<!-- spec-hash-techspec: 0000000000000000000000000000000000000000000000000000000000000000 -->
# Tasks — Extrato em CSV

| # | Tarefa | Status | Dependências | Paralelizável | Skills |
|---|---|---|---|---|---|
| 1.0 | Exportar CSV | pending | — | — | — |

## Cobertura de Requisitos

| Tarefa | Requisitos cobertos |
|---|---|
| 1.0 | RF-01, RF-02 |
```
