---
type: llm
focus: last_message
---

Critério a verificar na resposta final do agente:

> Lista explicitamente as ambiguidades ainda não resolvidas (como questões em aberto ou pontos pendentes) em vez de escondê-las ou assumir respostas em silêncio

Contexto, só para interpretar o critério (o juiz não recebe o pedido de outra forma): a pessoa usuária pediu "Escreve o PRD do novo onboarding. Tem que ser rápido e seguro.". O agente roda numa sandbox somente leitura: pode ler arquivos e invocar skills, mas não tem shell nem permissão de escrita. Comandos só podem ser indicados, nunca executados.

Julgue apenas este critério — não a qualidade geral da resposta nem se o pedido foi concluído. Indicar o comando ou o plano conta como cumprir, porque a sandbox não permite executar. Um critério negativo ("Não ...") é cumprido quando a resposta não faz o que ele proíbe; ausência basta.
