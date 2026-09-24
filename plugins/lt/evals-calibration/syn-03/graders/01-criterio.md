---
type: llm
focus: last_message
---

Critério a verificar na resposta final do agente:

> Encaminha lt-sdd.sh invalidate <bundle> --from prd e nova aprovação do PRD, em vez de só reescrever o hash

Contexto, só para interpretar o critério (o juiz não recebe o pedido de outra forma): a pessoa usuária pediu "Mudei o PRD do extrato depois de aprovar a techspec. Atualiza a techspec pra refletir.". O agente roda numa sandbox somente leitura: pode ler arquivos e invocar skills, mas não tem shell nem permissão de escrita. Comandos só podem ser indicados, nunca executados.

Julgue apenas este critério — não a qualidade geral da resposta nem se o pedido foi concluído. Indicar o comando ou o plano conta como cumprir, porque a sandbox não permite executar. Um critério negativo ("Não ...") é cumprido quando a resposta não faz o que ele proíbe; ausência basta.
