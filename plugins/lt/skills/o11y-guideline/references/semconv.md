# Convenções semânticas e resource

<!-- TL;DR
Resource com service.name, service.version, service.namespace, service.instance.id e deployment.environment.name; configuração pelas variáveis OTEL_*; nomes de atributo pela convenção semântica ou com prefixo de domínio invertido; atributos HTTP obrigatórios.
Keywords: semantic conventions, semconv, resource, service.name, service.version, service.namespace, service.instance.id, deployment.environment.name, OTEL_SERVICE_NAME, OTEL_RESOURCE_ATTRIBUTES, OTEL_EXPORTER_OTLP_ENDPOINT, http.route, error.type
Load complete when: a mudança configura resource, variáveis OTEL_*, cria atributo próprio ou instrumenta HTTP à mão.
-->

- Escopo: identidade do serviço, configuração do SDK por ambiente e nomes de atributo.
- Fonte: OTel, páginas "Semantic conventions", "Naming", registro de atributos `service` e
  `deployment`, "HTTP metrics", "SDK configuration" e "OTLP exporter configuration".

## Sumário

- O11Y-SEM-001 Identidade do serviço
- O11Y-SEM-002 Configuração por variável de ambiente
- O11Y-SEM-003 Nome de atributo
- O11Y-SEM-004 Atributos HTTP

## O11Y-SEM-001 Identidade do serviço

OTel, todos estáveis:

| Atributo | Regra |
|---|---|
| `service.name` | Nome lógico do serviço. Sem ele, o SDK usa `unknown_service` (mais o nome do executável, conforme o SDK). Obrigatório aqui. |
| `service.version` | Versão do componente, formato livre (`2.0.0`, hash de commit). |
| `service.namespace` | Agrupa serviços. `service.name` é único dentro do namespace. |
| `service.instance.id` | ID único por par namespace e nome. Recomendação: UUID v1, v4 ou v5. |
| `deployment.environment.name` | Ambiente: `development`, `staging`, `test`, `production`. Substitui o `deployment.environment`, obsoleto. |

- Resource é definido uma vez na inicialização e vale para traces, métricas e logs do processo.
- `service.name` e `service.namespace` viram o label `job` no Prometheus (ver `metrics.md`, O11Y-MET-007).

## O11Y-SEM-002 Configuração por variável de ambiente

OTel:

| Variável | Padrão |
|---|---|
| `OTEL_SERVICE_NAME` | `unknown_service` |
| `OTEL_RESOURCE_ATTRIBUTES` | vazio; formato `chave=valor,chave=valor` |
| `OTEL_TRACES_SAMPLER` | `parentbased_always_on` |
| `OTEL_TRACES_SAMPLER_ARG` | vazio; proporção entre 0 e 1 para samplers por proporção |
| `OTEL_PROPAGATORS` | `tracecontext,baggage` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://localhost:4317` (gRPC) ou `http://localhost:4318` (HTTP) |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | depende do SDK; valores `grpc`, `http/protobuf`, `http/json` |
| `OTEL_EXPORTER_OTLP_HEADERS` | vazio; formato `chave=valor,chave=valor` |
| `OTEL_EXPORTER_OTLP_TIMEOUT` | `10000` (10 s) |

- Configure por variável de ambiente o que muda por ambiente (endpoint, sampler, versão, ambiente).
  Não fixe no código.
- Credencial de backend em `OTEL_EXPORTER_OTLP_HEADERS` vem de secret do ambiente, nunca do repositório.

## O11Y-SEM-003 Nome de atributo

OTel:

- Minúsculo, namespaces separados por ponto e snake_case dentro do segmento
  (`http.response.status_code`).
- Nome completo e sem ambiguidade: `file.owner.name`, não `file.owner`.
- Singular para uma entidade (`host.name`), plural para array (`process.command_args`).
- Abreviação só quando for amplamente conhecida (HTTP, URL, K8s).
- Antes de criar atributo, procurar no registro da convenção semântica. Atributo próprio leva o
  prefixo do domínio da empresa invertido (`com.acme.shopname`), para não colidir em sistema distribuído.

## O11Y-SEM-004 Atributos HTTP

OTel, métricas estáveis `http.server.request.duration` e `http.client.request.duration`:

| Métrica | Obrigatório | Condicional |
|---|---|---|
| `http.server.request.duration` | `http.request.method`, `url.scheme` | `error.type` (se houve erro), `http.response.status_code` (se houve resposta), `http.route` (se disponível) |
| `http.client.request.duration` | `http.request.method`, `server.address`, `server.port` | `error.type`, `http.response.status_code` |

- `http.route` é o template (`/users/{id}`), nunca o caminho real.
- `error.type` com valor previsível e de baixa cardinalidade (ver `signals.md`, O11Y-SIG-004).
- Instrumentação HTTP da biblioteca já preenche esses atributos. Instrumentar à mão só onde ela não existe.
