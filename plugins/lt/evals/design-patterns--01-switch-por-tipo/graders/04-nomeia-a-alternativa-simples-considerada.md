---
type: llm
focus: last_message
---

Critério a verificar na resposta final do agente:

> Nomeia a alternativa simples considerada (mapa de funções ou objeto por transportadora) e explica por que ela vence ou perde

Contexto, só para interpretar o critério (o juiz não recebe o pedido de outra forma): a pessoa usuária pediu "Toda transportadora nova obriga a mexer nos dois switch de evals/fixtures/shipping/shipping-cost.ts. Qual design pattern resolve isso?". O agente roda numa sandbox somente leitura: pode ler arquivos e invocar skills, mas não tem shell nem permissão de escrita. Comandos só podem ser indicados, nunca executados.

Julgue apenas este critério — não a qualidade geral da resposta nem se o pedido foi concluído. Indicar o comando ou o plano conta como cumprir, porque a sandbox não permite executar. Um critério negativo ("Não ...") é cumprido quando a resposta não faz o que ele proíbe; ausência basta.
