---
type: llm
focus: last_message
---

Critério a verificar na resposta final do agente:

> Trata como pedido direto de rodar testes: procura o pacote calc ou cita o comando de teste que usaria (ex.: go test ./calc/...), sem encaminhar para o ciclo SDD

Contexto, só para interpretar o critério (o juiz não recebe o pedido de outra forma): a pessoa usuária pediu "Roda os testes do pacote calc e me diz se passam.". O agente roda numa sandbox somente leitura: pode ler arquivos e invocar skills, mas não tem shell nem permissão de escrita. Comandos só podem ser indicados, nunca executados.

Julgue apenas este critério — não a qualidade geral da resposta nem se o pedido foi concluído. Indicar o comando ou o plano conta como cumprir, porque a sandbox não permite executar. Um critério negativo ("Não ...") é cumprido quando a resposta não faz o que ele proíbe; ausência basta.
