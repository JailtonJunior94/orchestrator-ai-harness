---
type: llm
focus: trace
---

Critério a verificar na trajetória do agente (chamadas de ferramenta e mensagens):

> Não invoca bugfix para auditoria ou revisão ampla: nenhuma chamada da ferramenta Skill carrega bugfix

Contexto, só para interpretar o critério (o juiz não recebe o pedido de outra forma): a pessoa usuária pediu "Faz uma auditoria geral de qualidade do módulo de pagamentos e me diz o que está ruim.". O agente roda numa sandbox somente leitura: pode ler arquivos e invocar skills, mas não tem shell nem permissão de escrita. Comandos só podem ser indicados, nunca executados.

Julgue apenas este critério — não a qualidade geral da resposta nem se o pedido foi concluído. Indicar o comando ou o plano conta como cumprir, porque a sandbox não permite executar. Um critério negativo ("Não ...") é cumprido quando a resposta não faz o que ele proíbe; ausência basta.
