---
type: llm
focus: trace
---

Critério a verificar na trajetória do agente (chamadas de ferramenta e mensagens):

> Não invoca a skill object-calisthenics-guideline para um bug pontual em script shell: nenhuma chamada da ferramenta Skill carrega object-calisthenics-guideline

Contexto, só para interpretar o critério (o juiz não recebe o pedido de outra forma): a pessoa usuária pediu "O evals/fixtures/ops/rotate-logs.sh deveria apagar os logs com mais de 7 dias, mas quase nada é apagado. Corrige.". O agente roda numa sandbox somente leitura: pode ler arquivos e invocar skills, mas não tem shell nem permissão de escrita. Comandos só podem ser indicados, nunca executados.

Julgue apenas este critério — não a qualidade geral da resposta nem se o pedido foi concluído. Indicar o comando ou o plano conta como cumprir, porque a sandbox não permite executar. Um critério negativo ("Não ...") é cumprido quando a resposta não faz o que ele proíbe; ausência basta.
