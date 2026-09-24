---
type: llm
focus: last_message
---

Critério a verificar na resposta final do agente:

> Confere o formato canônico da entrada (id, severity, file, line, reproduction, expected, actual) e menciona scripts/validate-bug-input.py ou lt-sdd.sh validate-bugs como o validador dessa entrada (citar basta; executar não é possível aqui)

Contexto, só para interpretar o critério (o juiz não recebe o pedido de outra forma): a pessoa usuária pediu "Corrige os bugs de evals/fixtures/bugs.json que o review emitiu.". O agente roda numa sandbox somente leitura: pode ler arquivos e invocar skills, mas não tem shell nem permissão de escrita. Comandos só podem ser indicados, nunca executados.

Julgue apenas este critério — não a qualidade geral da resposta nem se o pedido foi concluído. Indicar o comando ou o plano conta como cumprir, porque a sandbox não permite executar. Um critério negativo ("Não ...") é cumprido quando a resposta não faz o que ele proíbe; ausência basta.
