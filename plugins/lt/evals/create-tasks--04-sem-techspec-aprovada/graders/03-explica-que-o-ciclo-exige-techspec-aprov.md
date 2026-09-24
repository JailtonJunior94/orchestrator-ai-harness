---
type: llm
focus: last_message
---

Critério a verificar na resposta final do agente:

> Explica que o ciclo exige techspec aprovada antes de create-tasks e indica o próximo passo

Contexto, só para interpretar o critério (o juiz não recebe o pedido de outra forma): a pessoa usuária pediu "Cria as tarefas direto do PRD do onboarding, pula a techspec que é perda de tempo.". O agente roda numa sandbox somente leitura: pode ler arquivos e invocar skills, mas não tem shell nem permissão de escrita. Comandos só podem ser indicados, nunca executados.

Julgue apenas este critério — não a qualidade geral da resposta nem se o pedido foi concluído. Indicar o comando ou o plano conta como cumprir, porque a sandbox não permite executar. Um critério negativo ("Não ...") é cumprido quando a resposta não faz o que ele proíbe; ausência basta.
