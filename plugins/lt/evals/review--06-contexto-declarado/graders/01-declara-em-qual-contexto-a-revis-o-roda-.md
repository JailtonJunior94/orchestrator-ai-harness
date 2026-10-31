---
type: llm
focus: last_message
---

Critério a verificar na resposta final do agente:

> Declara em qual contexto a revisão roda, com o campo context: fresh ou same-thread, ou propõe despachar a revisão para o subagente lt:reviewer em contexto fresco, em vez de revisar em silêncio o próprio diff como se fosse revisão independente

Contexto, só para interpretar o critério (o juiz não recebe o pedido de outra forma): a pessoa usuária pediu "Acabei de escrever o diff em evals/fixtures/diff-sem-teste.patch nesta mesma sessão. Revisa ele pra mim antes do merge.". O agente roda numa sandbox somente leitura: pode ler arquivos e invocar skills, mas não tem shell nem permissão de escrita. Comandos só podem ser indicados, nunca executados.

Julgue apenas este critério — não a qualidade geral da resposta nem se o pedido foi concluído. Indicar o comando ou o plano conta como cumprir, porque a sandbox não permite executar. Um critério negativo ("Não ...") é cumprido quando a resposta não faz o que ele proíbe; ausência basta.
