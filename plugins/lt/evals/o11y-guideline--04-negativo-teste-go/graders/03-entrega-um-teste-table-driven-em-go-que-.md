---
type: llm
focus: last_message
---

Critério a verificar na resposta final do agente:

> Entrega um teste table-driven em Go que cobre o caso válido sem vírgula ("100" vira 10000) e os erros de centavos com uma casa, valor negativo e texto não numérico, comparando o erro com ErrInvalidAmount

Contexto, só para interpretar o critério (o juiz não recebe o pedido de outra forma): a pessoa usuária pediu "Escreve um teste table-driven para ParseCents em evals/fixtures/money/parse.go cobrindo os casos de erro.". O agente roda numa sandbox somente leitura: pode ler arquivos e invocar skills, mas não tem shell nem permissão de escrita. Comandos só podem ser indicados, nunca executados.

Julgue apenas este critério — não a qualidade geral da resposta nem se o pedido foi concluído. Indicar o comando ou o plano conta como cumprir, porque a sandbox não permite executar. Um critério negativo ("Não ...") é cumprido quando a resposta não faz o que ele proíbe; ausência basta.
