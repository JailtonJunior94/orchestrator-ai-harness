---
type: llm
focus: trace
---

Critério a verificar na trajetória do agente (chamadas de ferramenta e mensagens):

> Não invoca a skill review para um pedido de implementação: nenhuma chamada da ferramenta Skill carrega review

Contexto, só para interpretar o critério (o juiz não recebe o pedido de outra forma): a pessoa usuária pediu "Implementa um endpoint GET /health no serviço de extrato.". O agente roda numa sandbox somente leitura: pode ler arquivos e invocar skills, mas não tem shell nem permissão de escrita. Comandos só podem ser indicados, nunca executados.

Julgue apenas este critério — não a qualidade geral da resposta nem se o pedido foi concluído. Indicar o comando ou o plano conta como cumprir, porque a sandbox não permite executar. Um critério negativo ("Não ...") é cumprido quando a resposta não faz o que ele proíbe; ausência basta.
