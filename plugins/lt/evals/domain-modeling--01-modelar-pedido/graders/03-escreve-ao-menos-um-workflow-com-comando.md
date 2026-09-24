---
type: llm
focus: last_message
---

Critério a verificar na resposta final do agente:

> Escreve ao menos um workflow com comando de entrada, eventos de saída e erro de domínio (assinatura do tipo Comando -> Result de eventos ou erro) e cita os RF-NN que ele atende

Contexto, só para interpretar o critério (o juiz não recebe o pedido de outra forma): a pessoa usuária pediu "Modela o domínio da assinatura descrita em evals/fixtures/prd-assinatura/prd.md antes da gente escrever a techspec. O projeto é em Go.". O agente roda numa sandbox somente leitura: pode ler arquivos e invocar skills, mas não tem shell nem permissão de escrita. Comandos só podem ser indicados, nunca executados.

Julgue apenas este critério — não a qualidade geral da resposta nem se o pedido foi concluído. Indicar o comando ou o plano conta como cumprir, porque a sandbox não permite executar. Um critério negativo ("Não ...") é cumprido quando a resposta não faz o que ele proíbe; ausência basta.
