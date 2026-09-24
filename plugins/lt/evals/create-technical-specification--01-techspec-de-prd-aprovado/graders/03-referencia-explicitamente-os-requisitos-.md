---
type: llm
focus: last_message
---

Critério a verificar na resposta final do agente:

> Referencia explicitamente os requisitos RF-01 e RF-02 do PRD ao propor decisões técnicas ou ao fazer as perguntas técnicas

Contexto, só para interpretar o critério (o juiz não recebe o pedido de outra forma): a pessoa usuária pediu "O PRD em evals/fixtures/prd-extrato/prd.md foi aprovado. Gera a especificação técnica.". O agente roda numa sandbox somente leitura: pode ler arquivos e invocar skills, mas não tem shell nem permissão de escrita. Comandos só podem ser indicados, nunca executados.

Julgue apenas este critério — não a qualidade geral da resposta nem se o pedido foi concluído. Indicar o comando ou o plano conta como cumprir, porque a sandbox não permite executar. Um critério negativo ("Não ...") é cumprido quando a resposta não faz o que ele proíbe; ausência basta.
