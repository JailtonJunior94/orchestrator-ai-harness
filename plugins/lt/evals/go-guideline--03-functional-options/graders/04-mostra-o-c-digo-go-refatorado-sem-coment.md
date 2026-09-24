---
type: llm
focus: last_message
---

Critério a verificar na resposta final do agente:

> Mostra o código Go refatorado sem comentários e sem prefixo _ em identificadores

Contexto, só para interpretar o critério (o juiz não recebe o pedido de outra forma): a pessoa usuária pediu "Refatora o construtor em evals/fixtures/dbclient/client.go: cada chamada precisa passar todos os parâmetros e isso vai crescer.". O agente roda numa sandbox somente leitura: pode ler arquivos e invocar skills, mas não tem shell nem permissão de escrita. Comandos só podem ser indicados, nunca executados.

Julgue apenas este critério — não a qualidade geral da resposta nem se o pedido foi concluído. Indicar o comando ou o plano conta como cumprir, porque a sandbox não permite executar. Um critério negativo ("Não ...") é cumprido quando a resposta não faz o que ele proíbe; ausência basta.
