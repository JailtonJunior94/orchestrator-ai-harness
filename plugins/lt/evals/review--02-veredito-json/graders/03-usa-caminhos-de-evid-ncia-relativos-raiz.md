---
type: llm
focus: last_message
---

Critério a verificar na resposta final do agente:

> Usa caminhos de evidência relativos à raiz do repositório, sem caminho absoluto nem '..'; se a resposta não citar caminho de evidência nenhum, cumpre o critério

Contexto, só para interpretar o critério (o juiz não recebe o pedido de outra forma): a pessoa usuária pediu "Preciso do resultado da revisão da tarefa 1.0 em JSON para o orquestrador.". O agente roda numa sandbox somente leitura: pode ler arquivos e invocar skills, mas não tem shell nem permissão de escrita. Comandos só podem ser indicados, nunca executados.

Julgue apenas este critério — não a qualidade geral da resposta nem se o pedido foi concluído. Indicar o comando ou o plano conta como cumprir, porque a sandbox não permite executar. Um critério negativo ("Não ...") é cumprido quando a resposta não faz o que ele proíbe; ausência basta.
