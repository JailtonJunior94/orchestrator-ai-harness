---
type: llm
focus: last_message
---

Critério a verificar na resposta final do agente:

> Conclui que OrderResponse é um DTO de fronteira (resposta de API) e por isso fica isento das regras de duas variáveis de instância, de encapsular primitivos e de sem getters

Contexto, só para interpretar o critério (o juiz não recebe o pedido de outra forma): a pessoa usuária pediu "O OrderResponse em evals/fixtures/api/order-response.ts viola Object Calisthenics? Tem seis campos e nenhum comportamento.". O agente roda numa sandbox somente leitura: pode ler arquivos e invocar skills, mas não tem shell nem permissão de escrita. Comandos só podem ser indicados, nunca executados.

Julgue apenas este critério — não a qualidade geral da resposta nem se o pedido foi concluído. Indicar o comando ou o plano conta como cumprir, porque a sandbox não permite executar. Um critério negativo ("Não ...") é cumprido quando a resposta não faz o que ele proíbe; ausência basta.
