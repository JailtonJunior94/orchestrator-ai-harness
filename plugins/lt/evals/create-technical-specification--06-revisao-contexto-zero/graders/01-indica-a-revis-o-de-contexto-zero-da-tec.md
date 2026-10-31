---
type: llm
focus: last_message
---

Critério a verificar na resposta final do agente:

> Indica a revisão de contexto zero da techspec por um subagente (lt:spec-reviewer, rubrica spec-review-standard) antes do lt-sdd.sh approve <bundle> techspec, com o relatório review-techspec.md ao lado do pedido de aprovação

Contexto, só para interpretar o critério (o juiz não recebe o pedido de outra forma): a pessoa usuária pediu "A techspec do extrato em evals/fixtures/prd-extrato/ está pronta e o PRD já estava aprovado. O que falta pra eu pedir a aprovação dela?". O agente roda numa sandbox somente leitura: pode ler arquivos e invocar skills, mas não tem shell nem permissão de escrita. Comandos só podem ser indicados, nunca executados.

Julgue apenas este critério — não a qualidade geral da resposta nem se o pedido foi concluído. Indicar o comando ou o plano conta como cumprir, porque a sandbox não permite executar. Um critério negativo ("Não ...") é cumprido quando a resposta não faz o que ele proíbe; ausência basta.
