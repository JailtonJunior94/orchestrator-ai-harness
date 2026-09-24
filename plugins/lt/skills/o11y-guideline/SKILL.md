---
name: o11y-guideline
description: Diretrizes de observabilidade para produção com OpenTelemetry e os 4 sinais de ouro (latência, tráfego, erros e saturação). Use ao instrumentar traces, métricas ou logs, revisar a configuração do OTel Collector ou criar dashboards e alertas de um serviço. Não use para a telemetria do próprio harness nem para depurar um bug sem relação com instrumentação.
metadata:
  version: 1.0.0
  category: processual
---

# Diretrizes de observabilidade

Piso de qualidade para telemetria que vai para produção. As regras vêm da
[documentação do OpenTelemetry](https://opentelemetry.io/docs/) (especificação, convenções semânticas
e Collector) e dos 4 sinais de ouro do SRE, conforme
[OpServices](https://www.opservices.com.br/4-sinais-de-ouro-do-sre/) e
[groundcover](https://www.groundcover.com/blog/4-golden-signals). Cada regra das referências cita a
fonte com o prefixo `OTel:` ou `SRE:`.

## Precedência

1. A constitution do harness e a regra `R-OBS-001` (`agent-governance/references/observability.md`),
   que é hard e vence qualquer fonte externa. Esta skill detalha a `R-OBS-001`, não a substitui.
2. A especificação e as convenções semânticas do OpenTelemetry.
3. Os artigos sobre os 4 sinais de ouro.
4. A convenção já estabelecida no repositório, desde que não contradiga os itens acima.

## Piso inegociável

Toda mudança de telemetria cumpre estas regras, sem precisar abrir nenhuma referência:

1. `service.name` sempre definido. Sem ele o SDK reporta `unknown_service`. `service.version` e
   `deployment.environment.name` entram pelo resource (`OTEL_RESOURCE_ATTRIBUTES`).
2. Sem PII, credencial ou token em atributo, evento, log, baggage ou nome de span. Baggage é
   propagado para serviços downstream, inclusive de terceiros.
3. Atributo de métrica com cardinalidade limitada: nunca ID de usuário, de pedido ou de request. O
   SDK corta cada métrica em 2000 combinações por padrão e joga o excedente em `otel.metric.overflow`.
4. Nome de span e de métrica com baixa cardinalidade: a rota (`GET /users/{id}`), nunca a URL com o ID.
5. Latência é Histogram em segundos (`s`), nunca média. Siga o nome da convenção semântica quando ela
   existir (`http.server.request.duration`).
6. Span com falha recebe status `Error`. `Ok` só por decisão explícita. Todo span iniciado é encerrado.
7. Latência de sucesso e de erro medidas em separado. Razão de erro agrega numerador e denominador
   antes de dividir.
8. Biblioteca depende só da API do OpenTelemetry. Quem escolhe SDK e exporter é a aplicação.
9. Em produção, a aplicação exporta para um Collector. No Collector, `memory_limiter` é o primeiro
   processor, endpoint escuta em `localhost` salvo necessidade real e segredo vem de variável de ambiente.
10. Alerta compara o sinal com um baseline ou objetivo definido e evita limiar ruidoso, que gera
    fadiga de alerta.

## Referências

Abra só a referência que a mudança exige. Para descobrir quais casam com o diff (`AGENTS_ROOT` é o
diretório que contém `skills/`, dois níveis acima desta skill em qualquer host):

```bash
git diff | AGENTS_ROOT="${CLAUDE_SKILL_DIR}/../.." bash "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-references.sh" o11y-guideline <arquivos tocados>
```

| Tarefa | Referência |
|---|---|
| Escolher o que medir, 4 sinais de ouro, RED e USE, PromQL | `references/signals.md` |
| Span, span kind, status, evento, link, propagação, baggage, sampling | `references/traces.md` |
| Instrumento, nome, unidade, bucket, cardinalidade, view, temporalidade | `references/metrics.md` |
| Log estruturado, bridge de log, correlação com trace | `references/logs.md` |
| Resource, `service.*`, variáveis `OTEL_*`, nomes de atributo | `references/semconv.md` |
| Configuração, deploy, resiliência e privacidade no Collector | `references/collector.md` |
| Regra de alerta, dashboard, fadiga de alerta | `references/alerting.md` |
| SDK do OpenTelemetry em Go | `references/go.md` |

Assets prontos para adaptar: `assets/otel-collector.yaml` e `assets/golden-signals.rules.yaml`.

## Procedimentos

**Etapa 1: Levantar o contexto**
1. Identificar a linguagem e a versão do SDK do OpenTelemetry no manifesto (`go.mod`, `package.json`,
   `pom.xml`, `*.csproj`, `pyproject.toml`). Sem manifesto acessível, não presumir versão.
2. Localizar a configuração do Collector e o backend de métricas, se existirem. Ausência de Collector
   em produção é achado a reportar.
3. Antes de escrever PromQL, descobrir o nome real da métrica no backend. A tradução OTLP para
   Prometheus acrescenta sufixo de unidade, `_total` e `_bucket` (ver `references/metrics.md`).

**Etapa 2: Carregar as regras certas**
1. Aplicar o piso inegociável sempre.
2. Rodar o `resolve-references.sh` acima e abrir apenas as referências listadas. Se o script não
   estiver disponível, escolher pela tabela de referências.

**Etapa 3: Implementar**
1. Começar pela instrumentação de biblioteca ou zero-code do framework, que cobre as bordas da
   aplicação (HTTP, banco, fila). Instrumentar à mão só o que ela não enxerga, como regra de negócio.
2. Escrever a menor mudança que resolve o pedido. Código, nomes de atributo e mensagens de log em inglês.
3. Não inventar atributo quando a convenção semântica já define um. Atributo próprio leva o prefixo
   do domínio da empresa invertido (`com.acme.cart.items`).

**Etapa 4: Validar**

Rodar os comandos que existirem no ambiente:

```bash
otelcol validate --config <arquivo>
promtool check rules <arquivo>
```

1. Rodar também os testes e o lint da linguagem do serviço.
2. Comando que não pôde rodar é reportado como `não verificado`, com o motivo. Nunca como aprovado.
3. Falha é reportada com o comando exato e a primeira mensagem relevante.

**Etapa 5: Revisar a própria mudança**
1. Conferir o diff contra o piso inegociável.
2. Registrar cada desvio intencional com o ID da regra (`O11Y-MET-003`, por exemplo) e o motivo.

## Tratamento de Erros

- Pedido que viola o piso (por exemplo, `user_id` como atributo de métrica): explicar a regra, propor
  a alternativa conforme (atributo no span ou campo no log) e só seguir o pedido original se a pessoa
  confirmar.
- Dúvida sobre API do SDK: consultar a documentação da versão instalada (`go doc`, por exemplo) antes
  de afirmar comportamento.
- Limiar numérico sem objetivo definido (SLO, baseline): propor como ponto de partida explícito, nunca
  como verdade do serviço.

## Atribuição

As regras marcadas com `OTel:` são adaptadas da documentação do
[OpenTelemetry](https://opentelemetry.io/docs/) (CC BY 4.0). As marcadas com `SRE:` resumem os artigos
da OpServices e da groundcover citados acima. A tradução e a seleção são deste harness.
