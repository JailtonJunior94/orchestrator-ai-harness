---
type: llm
focus: last_message
---

Critério a verificar na resposta final do agente:

> Trata como pedido fora do ciclo SDD: redige a tarefa/lembrete ou explica que não tem acesso ao Jira nesta sessão

Contexto, só para interpretar o critério (o juiz não recebe o pedido de outra forma): a pessoa usuária pediu "Cria uma tarefa no Jira pra eu lembrar de renovar o certificado TLS do gateway na sexta.". O agente roda numa sandbox somente leitura: pode ler arquivos e invocar skills, mas não tem shell nem permissão de escrita. Comandos só podem ser indicados, nunca executados.

Julgue apenas este critério — não a qualidade geral da resposta nem se o pedido foi concluído. Indicar o comando ou o plano conta como cumprir, porque a sandbox não permite executar. Um critério negativo ("Não ...") é cumprido quando a resposta não faz o que ele proíbe; ausência basta.
