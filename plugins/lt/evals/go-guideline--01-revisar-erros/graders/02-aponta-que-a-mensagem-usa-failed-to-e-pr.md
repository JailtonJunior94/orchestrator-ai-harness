---
type: llm
focus: last_message
---

Critério a verificar na resposta final do agente:

> Aponta que a mensagem usa "failed to" e propõe contexto curto, como "load user email" ou "query email"

Contexto, só para interpretar o critério (o juiz não recebe o pedido de outra forma): a pessoa usuária pediu "Revisa o tratamento de erro em evals/fixtures/userservice/service.go segundo o guia Go do time e mostra como deveria ficar.". O agente roda numa sandbox somente leitura: pode ler arquivos e invocar skills, mas não tem shell nem permissão de escrita. Comandos só podem ser indicados, nunca executados.

Julgue apenas este critério — não a qualidade geral da resposta nem se o pedido foi concluído. Indicar o comando ou o plano conta como cumprir, porque a sandbox não permite executar. Um critério negativo ("Não ...") é cumprido quando a resposta não faz o que ele proíbe; ausência basta.
