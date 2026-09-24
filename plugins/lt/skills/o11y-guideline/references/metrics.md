# Métricas

<!-- TL;DR
Escolha do instrumento certo, nome e unidade pela convenção semântica, histograma para latência com os buckets recomendados, atributo de cardinalidade limitada, views para ajustar saída, temporalidade e a tradução do nome OTLP para Prometheus.
Keywords: Counter, UpDownCounter, Gauge, Histogram, observable, async, unidade, UCUM, bucket, cardinalidade, overflow, view, delta, cumulative, Prometheus, _total, _bucket
Load complete when: a mudança cria ou altera instrumento de métrica, escolhe atributo de métrica ou escreve consulta sobre métrica exportada para Prometheus.
-->

- Escopo: todo instrumento de métrica e toda consulta sobre ele.
- Fonte: OTel, páginas "Metrics", "Naming", "HTTP metrics" e "Prometheus and OpenMetrics compatibility".

## Sumário

- O11Y-MET-001 Escolher o instrumento
- O11Y-MET-002 Unidade explícita
- O11Y-MET-003 Nome da métrica
- O11Y-MET-004 Latência em Histogram
- O11Y-MET-005 Cardinalidade limitada
- O11Y-MET-006 Views e temporalidade
- O11Y-MET-007 Nome no Prometheus
- O11Y-MET-008 MeterProvider único

## O11Y-MET-001 Escolher o instrumento

OTel:

| O valor | Instrumento síncrono | Assíncrono (lido a cada coleta) |
|---|---|---|
| Só cresce (requisições, bytes enviados) | `Counter` | `ObservableCounter` |
| Sobe e desce (itens na fila, conexões ativas) | `UpDownCounter` | `ObservableUpDownCounter` |
| Valor do momento, sem soma com sentido (temperatura, uso de CPU) | `Gauge` | `ObservableGauge` |
| Distribuição (latência, tamanho de payload) | `Histogram` | não existe |

- Use o assíncrono quando o valor já existe agregado em outro lugar e só precisa ser lido, como o
  tamanho atual de uma fila.
- Contar erro não pede instrumento próprio quando a duração já é um Histogram com `error.type`: a
  contagem sai do `_count` do histograma.

## O11Y-MET-002 Unidade explícita

- OTel: a unidade segue o UCUM, com a variante sensível a maiúsculas.
- OTel: duração é medida em segundos (`s`).
- OTel: métrica de utilização (fração de um total) é adimensional e usa a unidade `1`.
- OTel: contagem de coisas usa anotação entre chaves no singular, sem unidade na frente:
  `{request}`, `{packet}`, `{error}`.
- OTel: quando a unidade está no metadado, ela não vai no nome: `http.server.request.duration`,
  nunca `..._seconds`.

## O11Y-MET-003 Nome da métrica

OTel:

- Minúsculo, namespaces separados por ponto e snake_case dentro do segmento.
- Namespace de métrica não vai no plural.
- `Counter` não ganha sufixo `_total`; o exportador para Prometheus acrescenta.
- `UpDownCounter` não vai no plural: `system.process.count`, não `system.processes`.
- Padrões de nome: `<entidade>.limit`, `<entidade>.usage`, `<entidade>.utilization` (fração de uso
  sobre limite, de 0 a 1), `<entidade>.time` e `<operação>.duration`.
- Quando o lado da comunicação é ambíguo: `<área>.client.<métrica>` ou `<área>.server.<métrica>`.
- Métrica que a convenção semântica já define usa o nome dela. Métrica própria leva o prefixo do
  domínio da empresa invertido (`com.acme.checkout.duration`).

## O11Y-MET-004 Latência em Histogram

- OTel: `Histogram` faz a agregação no cliente e permite calcular percentis no backend.
- OTel: os buckets recomendados para `http.server.request.duration` e `http.client.request.duration` são
  `[0.005, 0.01, 0.025, 0.05, 0.075, 0.1, 0.25, 0.5, 0.75, 1, 2.5, 5, 7.5, 10]` segundos.
- Operação cuja latência típica fica fora dessa faixa (job de minutos, cache de microssegundos)
  declara buckets próprios que cercam o objetivo de latência. Percentil calculado sobre bucket que não
  cobre o valor real sai errado.
- A `R-OBS-001` prefere histograma a summary para latência: histograma se agrega entre instâncias,
  summary não.

## O11Y-MET-005 Cardinalidade limitada

- Cada combinação distinta de atributos cria uma série. Atributo de métrica só com valor de conjunto
  pequeno e fechado: método, rota, código de status, `error.type`.
- Nunca ID de usuário, pedido, request, sessão, e-mail ou URL completa. Esse detalhe vai no span ou no log.
- OTel: o SDK limita cada métrica a 2000 combinações por padrão. O excedente é somado numa série com
  `otel.metric.overflow=true`: o total fica certo, mas o filtro por atributo deixa de funcionar.
  Encostar no limite é defeito a corrigir, não configuração a aumentar.
- A `R-OBS-001` proíbe label derivado de input do usuário sem sanitização.

## O11Y-MET-006 Views e temporalidade

- OTel: view ajusta a saída sem mexer no código instrumentado: filtra instrumento, troca a agregação
  (buckets, por exemplo) e escolhe quais atributos são reportados. Use view para derrubar atributo
  de alta cardinalidade vindo de biblioteca de terceiros.
- OTel: temporalidade cumulativa mantém o estado entre coletas; delta zera o estado a cada coleta.
  Use a que o backend espera.
- OTel: na conversão para Prometheus, soma e histograma com temporalidade delta podem ser convertidos
  para cumulativa ou são descartados. Para backend Prometheus, exporte cumulativa e não dependa da
  conversão.

## O11Y-MET-007 Nome no Prometheus

OTel: a tradução de OTLP para Prometheus:

- Troca caractere não aceito (o ponto, por exemplo) por `_` e colapsa `_` repetido.
- Acrescenta o sufixo da unidade por extenso quando o nome ainda não termina nela (`s` vira `seconds`).
- Acrescenta `_total` em soma monotônica (Counter).
- Histograma vira `_bucket`, `_sum` e `_count`.
- `service.namespace` e `service.name` formam o label `job` (`<namespace>/<name>`, ou só `<name>`), e
  `service.instance.id` vira `instance`. Os demais atributos de resource vão para a métrica `target_info`
  ou são descartados.

Exemplo: `http.server.request.duration` em `s` vira `http_server_request_duration_seconds_bucket`,
`..._sum` e `..._count`. Backend, exportador e versão podem mudar essa tradução: confirme o nome na
lista de métricas do backend antes de escrever alerta ou dashboard.

## O11Y-MET-008 MeterProvider único

OTel: o MeterProvider é a fábrica de Meters e é criado uma vez no ciclo de vida da aplicação, junto
com resource e exporter. Biblioteca pede o Meter pela API global e não cria provider próprio.
Instrumento é criado uma vez e reutilizado, não a cada requisição.
