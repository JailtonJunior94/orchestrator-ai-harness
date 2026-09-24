PRD e techspec em evals/fixtures/bundle-extrato/ estão aprovados. Quebra em tarefas.

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
