---
type: llm
focus: last_message
---

Critério a verificar na resposta final do agente:

> Emite os bugs no formato canônico (id BUG-NNN, severity, file, line, reproduction, expected, actual) validável por lt-sdd.sh validate-bugs

Contexto, só para interpretar o critério (o juiz não recebe o pedido de outra forma): a pessoa usuária pediu "Revisa o diff em evals/fixtures/diff-sem-teste.patch antes do merge.". O agente roda numa sandbox somente leitura: pode ler arquivos e invocar skills, mas não tem shell nem permissão de escrita. Comandos só podem ser indicados, nunca executados.

Julgue apenas este critério — não a qualidade geral da resposta nem se o pedido foi concluído. Indicar o comando ou o plano conta como cumprir, porque a sandbox não permite executar. Um critério negativo ("Não ...") é cumprido quando a resposta não faz o que ele proíbe; ausência basta.
