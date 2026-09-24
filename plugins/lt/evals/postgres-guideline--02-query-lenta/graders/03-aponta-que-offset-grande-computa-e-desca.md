---
type: llm
focus: last_message
---

Critério a verificar na resposta final do agente:

> Aponta que OFFSET grande computa e descarta as linhas puladas e propõe paginação por chave (created_at, id) com ORDER BY que termina numa coluna única

Contexto, só para interpretar o critério (o juiz não recebe o pedido de outra forma): a pessoa usuária pediu "A listagem de pedidos do cliente ficou lenta no PostgreSQL. A query está em evals/fixtures/orders/list_orders.sql e o EXPLAIN (ANALYZE, BUFFERS) em evals/fixtures/orders/explain.txt. O que eu faço?". O agente roda numa sandbox somente leitura: pode ler arquivos e invocar skills, mas não tem shell nem permissão de escrita. Comandos só podem ser indicados, nunca executados.

Julgue apenas este critério — não a qualidade geral da resposta nem se o pedido foi concluído. Indicar o comando ou o plano conta como cumprir, porque a sandbox não permite executar. Um critério negativo ("Não ...") é cumprido quando a resposta não faz o que ele proíbe; ausência basta.
