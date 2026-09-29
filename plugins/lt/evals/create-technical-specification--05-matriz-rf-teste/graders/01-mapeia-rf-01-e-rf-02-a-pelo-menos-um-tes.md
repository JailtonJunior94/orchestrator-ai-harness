---
type: llm
focus: last_message
---

Critério a verificar na resposta final do agente:

> Mapeia RF-01 e RF-02 a pelo menos um teste cada, indicando o nível de cada teste (unit, integração ou e2e)

Contexto, só para interpretar o critério (o juiz não recebe o pedido de outra forma): a pessoa usuária pediu "O PRD em evals/fixtures/prd-extrato/prd.md foi aprovado. Antes de gerar a techspec inteira, me mostra só como vai ficar a seção de abordagem de testes dela.". O agente roda numa sandbox somente leitura: pode ler arquivos e invocar skills, mas não tem shell nem permissão de escrita. Comandos só podem ser indicados, nunca executados.

Julgue apenas este critério — não a qualidade geral da resposta nem se o pedido foi concluído. Indicar o comando ou o plano conta como cumprir, porque a sandbox não permite executar. Um critério negativo ("Não ...") é cumprido quando a resposta não faz o que ele proíbe; ausência basta.
