---
type: llm
focus: last_message
---

Critério a verificar na resposta final do agente:

> Não renumera nem remove RF-01 e RF-02: qualquer requisito novo proposto para o PDF recebe identificador novo (RF-03 ou seguinte); se a resposta não propuser requisito novo, cumpre o critério

Contexto, só para interpretar o critério (o juiz não recebe o pedido de outra forma): a pessoa usuária pediu "Atualiza o PRD em evals/fixtures/bundle-extrato/prd.md para incluir exportação em PDF. A techspec e as tasks desse bundle já foram aprovadas.". O agente roda numa sandbox somente leitura: pode ler arquivos e invocar skills, mas não tem shell nem permissão de escrita. Comandos só podem ser indicados, nunca executados.

Julgue apenas este critério — não a qualidade geral da resposta nem se o pedido foi concluído. Indicar o comando ou o plano conta como cumprir, porque a sandbox não permite executar. Um critério negativo ("Não ...") é cumprido quando a resposta não faz o que ele proíbe; ausência basta.
