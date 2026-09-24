---
type: llm
focus: last_message
---

Critério a verificar na resposta final do agente:

> Indica o caminho lt-sdd.sh invalidate <bundle> --from prd depois da edição, em vez de sincronizar o hash para esconder o drift

Contexto, só para interpretar o critério (o juiz não recebe o pedido de outra forma): a pessoa usuária pediu "Atualiza o PRD em evals/fixtures/bundle-extrato/prd.md para incluir exportação em PDF. A techspec e as tasks desse bundle já foram aprovadas.". O agente roda numa sandbox somente leitura: pode ler arquivos e invocar skills, mas não tem shell nem permissão de escrita. Comandos só podem ser indicados, nunca executados.

Julgue apenas este critério — não a qualidade geral da resposta nem se o pedido foi concluído. Indicar o comando ou o plano conta como cumprir, porque a sandbox não permite executar. Um critério negativo ("Não ...") é cumprido quando a resposta não faz o que ele proíbe; ausência basta.
