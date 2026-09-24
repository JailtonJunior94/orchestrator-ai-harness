---
type: llm
focus: last_message
---

Critério a verificar na resposta final do agente:

> Aponta que SET NOT NULL direto varre a tabela com ACCESS EXCLUSIVE e propõe CHECK (status IS NOT NULL) NOT VALID, VALIDATE e depois SET NOT NULL

Contexto, só para interpretar o critério (o juiz não recebe o pedido de outra forma): a pessoa usuária pediu "Revisa a migração evals/fixtures/migrations/0042_orders_customer.sql antes de rodar no PostgreSQL de produção. A tabela orders tem uns 200 milhões de linhas e recebe escrita o tempo todo.". O agente roda numa sandbox somente leitura: pode ler arquivos e invocar skills, mas não tem shell nem permissão de escrita. Comandos só podem ser indicados, nunca executados.

Julgue apenas este critério — não a qualidade geral da resposta nem se o pedido foi concluído. Indicar o comando ou o plano conta como cumprir, porque a sandbox não permite executar. Um critério negativo ("Não ...") é cumprido quando a resposta não faz o que ele proíbe; ausência basta.
