---
type: llm
focus: last_message
---

Critério a verificar na resposta final do agente:

> Indica o uso de scripts/validate-domain-model.py para conferir o arquivo, ou aplica as mesmas regras dele quando não pode executá-lo

Contexto, só para interpretar o critério (o juiz não recebe o pedido de outra forma): a pessoa usuária pediu "O modelo de domínio em evals/fixtures/modelo-quebrado/domain-model.md está pronto para ir para a techspec? Confere com o validador da skill.". O agente roda numa sandbox somente leitura: pode ler arquivos e invocar skills, mas não tem shell nem permissão de escrita. Comandos só podem ser indicados, nunca executados.

Julgue apenas este critério — não a qualidade geral da resposta nem se o pedido foi concluído. Indicar o comando ou o plano conta como cumprir, porque a sandbox não permite executar. Um critério negativo ("Não ...") é cumprido quando a resposta não faz o que ele proíbe; ausência basta.
