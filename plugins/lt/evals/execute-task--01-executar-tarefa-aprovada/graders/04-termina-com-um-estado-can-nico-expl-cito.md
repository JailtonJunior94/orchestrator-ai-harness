---
type: llm
focus: last_message
---

Critério a verificar na resposta final do agente:

> Termina com um estado canônico explícito (needs_input, blocked, failed ou done) e diz o que falta para seguir

Contexto, só para interpretar o critério (o juiz não recebe o pedido de outra forma): a pessoa usuária pediu "Executa a tarefa 1.0 do bundle em evals/fixtures/bundle-exec/.". O agente roda numa sandbox somente leitura: pode ler arquivos e invocar skills, mas não tem shell nem permissão de escrita. Comandos só podem ser indicados, nunca executados.

Julgue apenas este critério — não a qualidade geral da resposta nem se o pedido foi concluído. Indicar o comando ou o plano conta como cumprir, porque a sandbox não permite executar. Um critério negativo ("Não ...") é cumprido quando a resposta não faz o que ele proíbe; ausência basta.
