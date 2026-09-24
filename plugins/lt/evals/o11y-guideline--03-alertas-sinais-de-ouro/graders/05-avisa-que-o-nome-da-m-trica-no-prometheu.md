---
type: llm
focus: last_message
---

Critério a verificar na resposta final do agente:

> Avisa que o nome da métrica no Prometheus (por exemplo http_server_request_duration_seconds) precisa ser confirmado no backend e que os limiares são ponto de partida a trocar pelo objetivo ou baseline do serviço

Contexto, só para interpretar o critério (o juiz não recebe o pedido de outra forma): a pessoa usuária pediu "Cria as regras de alerta Prometheus dos 4 sinais de ouro para a API de pedidos. Ela exporta via OpenTelemetry a métrica http.server.request.duration e roda no Kubernetes.". O agente roda numa sandbox somente leitura: pode ler arquivos e invocar skills, mas não tem shell nem permissão de escrita. Comandos só podem ser indicados, nunca executados.

Julgue apenas este critério — não a qualidade geral da resposta nem se o pedido foi concluído. Indicar o comando ou o plano conta como cumprir, porque a sandbox não permite executar. Um critério negativo ("Não ...") é cumprido quando a resposta não faz o que ele proíbe; ausência basta.
