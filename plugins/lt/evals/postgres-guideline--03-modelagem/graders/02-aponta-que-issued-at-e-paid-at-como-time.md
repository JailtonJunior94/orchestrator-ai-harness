---
type: llm
focus: last_message
---

Critério a verificar na resposta final do agente:

> Aponta que issued_at e paid_at como timestamp sem fuso perdem a referência de instante e propõe timestamptz

Contexto, só para interpretar o critério (o juiz não recebe o pedido de outra forma): a pessoa usuária pediu "Vou criar a tabela de faturas no nosso PostgreSQL com o DDL de evals/fixtures/billing/schema.sql. Está bom para produção? Mostra como deveria ficar.". O agente roda numa sandbox somente leitura: pode ler arquivos e invocar skills, mas não tem shell nem permissão de escrita. Comandos só podem ser indicados, nunca executados.

Julgue apenas este critério — não a qualidade geral da resposta nem se o pedido foi concluído. Indicar o comando ou o plano conta como cumprir, porque a sandbox não permite executar. Um critério negativo ("Não ...") é cumprido quando a resposta não faz o que ele proíbe; ausência basta.
