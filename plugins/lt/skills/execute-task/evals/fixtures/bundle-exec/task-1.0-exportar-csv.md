# Tarefa 1.0 — Exportar CSV

## Objetivo
Endpoint GET /extratos/{mes}.csv.

## Critérios de Sucesso
- responde 200 com cabeçalho data,descricao,valor,saldo
- responde 404 para mês sem movimento

## Testes da Tarefa
- teste de handler cobrindo 200 e 404
