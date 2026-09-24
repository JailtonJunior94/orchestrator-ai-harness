---
type: llm
focus: last_message
---

Critério a verificar na resposta final do agente:

> Propõe reordenar ou dividir as tarefas para quebrar o ciclo

Contexto, só para interpretar o critério (o juiz não recebe o pedido de outra forma): a pessoa usuária pediu "Organiza as tarefas do extrato: a 2.0 depende da 3.0 e a 3.0 depende da 2.0.". O agente roda numa sandbox somente leitura: pode ler arquivos e invocar skills, mas não tem shell nem permissão de escrita. Comandos só podem ser indicados, nunca executados.

Julgue apenas este critério — não a qualidade geral da resposta nem se o pedido foi concluído. Indicar o comando ou o plano conta como cumprir, porque a sandbox não permite executar. Um critério negativo ("Não ...") é cumprido quando a resposta não faz o que ele proíbe; ausência basta.
