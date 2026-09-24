Executa a tarefa 1.0 do bundle em evals/fixtures/bundle-exec/.

O repositório não está disponível nesta sessão; o conteúdo atual dos arquivos citados vai abaixo.

`evals/fixtures/bundle-exec/tasks.md`:

```
# Tasks — Extrato em CSV

| # | Tarefa | Status | Dependências | Paralelizável | Skills |
|---|---|---|---|---|---|
| 1.0 | Exportar CSV | pending | — | — | — |
| 2.0 | Auditoria da exportação | pending | 1.0 | — | — |

## Cobertura de Requisitos

| Tarefa | Requisitos cobertos |
|---|---|
| 1.0 | RF-01, RF-02 |
| 2.0 | RF-03 |
```

`evals/fixtures/bundle-exec/task-1.0-exportar-csv.md`:

```
# Tarefa 1.0 — Exportar CSV

## Objetivo
Endpoint GET /extratos/{mes}.csv.

## Critérios de Sucesso
- responde 200 com cabeçalho data,descricao,valor,saldo
- responde 404 para mês sem movimento

## Testes da Tarefa
- teste de handler cobrindo 200 e 404
```
