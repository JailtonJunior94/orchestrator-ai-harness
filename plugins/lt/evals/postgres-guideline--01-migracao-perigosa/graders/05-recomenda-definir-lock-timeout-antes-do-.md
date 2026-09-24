---
type: llm
focus: last_message
---

Critério a verificar na resposta final do agente:

> Recomenda definir lock_timeout antes do DDL para a migração falhar rápido em vez de enfileirar o tráfego

Contexto, só para interpretar o critério (o juiz não recebe o pedido de outra forma): a pessoa usuária pediu "Revisa a migração evals/fixtures/migrations/0042_orders_customer.sql antes de rodar no PostgreSQL de produção. A tabela orders tem uns 200 milhões de linhas e recebe escrita o tempo todo.". O agente roda numa sandbox somente leitura: pode ler arquivos e invocar skills, mas não tem shell nem permissão de escrita. Comandos só podem ser indicados, nunca executados.

Julgue apenas este critério — não a qualidade geral da resposta nem se o pedido foi concluído. Indicar o comando ou o plano conta como cumprir, porque a sandbox não permite executar. Um critério negativo ("Não ...") é cumprido quando a resposta não faz o que ele proíbe; ausência basta.
