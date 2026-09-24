---
type: llm
focus: last_message
---

Critério a verificar na resposta final do agente:

> Faz perguntas de clarificação sobre escopo, usuários e restrições antes de fechar o PRD, em vez de inventar as respostas

Contexto, só para interpretar o critério (o juiz não recebe o pedido de outra forma): a pessoa usuária pediu "Quero um PRD para permitir que o cliente exporte o extrato mensal em CSV pelo app. Hoje ele só vê na tela e o suporte recebe muitos pedidos por e-mail.". O agente roda numa sandbox somente leitura: pode ler arquivos e invocar skills, mas não tem shell nem permissão de escrita. Comandos só podem ser indicados, nunca executados.

Julgue apenas este critério — não a qualidade geral da resposta nem se o pedido foi concluído. Indicar o comando ou o plano conta como cumprir, porque a sandbox não permite executar. Um critério negativo ("Não ...") é cumprido quando a resposta não faz o que ele proíbe; ausência basta.
