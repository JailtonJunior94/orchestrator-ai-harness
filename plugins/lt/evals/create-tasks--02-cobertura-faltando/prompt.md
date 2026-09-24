O validate-sdd disse que RF-03 ficou sem tarefa no bundle em evals/fixtures/bundle-extrato/. Ajusta as tarefas.

O repositório não está disponível nesta sessão; o conteúdo atual dos arquivos citados vai abaixo.

`evals/fixtures/bundle-extrato/prd.md`:

```
# PRD — Extrato em CSV

## Requisitos Funcionais
- RF-01: exportar o extrato do mês corrente em CSV.
- RF-02: o CSV traz data, descrição, valor e saldo.
- RF-03: registrar auditoria de cada exportação.
```

`evals/fixtures/bundle-extrato/techspec.md`:

```
<!-- spec-hash-prd: 0000000000000000000000000000000000000000000000000000000000000000 -->
# TechSpec — Extrato em CSV

## Arquitetura
- Endpoint GET /extratos/{mes}.csv no serviço de extrato (RF-01, RF-02).
- Evento `extrato.exportado` gravado na trilha de auditoria (RF-03).
```

`evals/fixtures/bundle-extrato/tasks.md`:

```
<!-- spec-hash-prd: 0000000000000000000000000000000000000000000000000000000000000000 -->
<!-- spec-hash-techspec: 0000000000000000000000000000000000000000000000000000000000000000 -->
# Tasks — Extrato em CSV

| # | Tarefa | Status | Dependências | Paralelizável | Skills |
|---|---|---|---|---|---|
| 1.0 | Endpoint de exportação CSV | pending | — | — | — |
| 2.0 | Colunas data, descrição, valor e saldo | pending | 1.0 | — | — |

## Cobertura de Requisitos

| Tarefa | Requisitos cobertos |
|---|---|
| 1.0 | RF-01 |
| 2.0 | RF-02 |
```
