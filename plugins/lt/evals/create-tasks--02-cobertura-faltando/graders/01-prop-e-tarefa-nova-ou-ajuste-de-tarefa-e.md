---
type: llm
focus: last_message
---

Critério a verificar na resposta final do agente:

> Propõe tarefa nova ou ajuste de tarefa existente que cubra RF-03 (auditoria de cada exportação) e a linha correspondente na tabela de Cobertura de Requisitos

Contexto, só para interpretar o critério (o juiz não recebe o pedido de outra forma): a pessoa usuária pediu "O validate-sdd disse que RF-03 ficou sem tarefa no bundle em evals/fixtures/bundle-extrato/. Ajusta as tarefas.". O agente roda numa sandbox somente leitura: pode ler arquivos e invocar skills, mas não tem shell nem permissão de escrita. Comandos só podem ser indicados, nunca executados.

Julgue apenas este critério — não a qualidade geral da resposta nem se o pedido foi concluído. Indicar o comando ou o plano conta como cumprir, porque a sandbox não permite executar. Um critério negativo ("Não ...") é cumprido quando a resposta não faz o que ele proíbe; ausência basta.
