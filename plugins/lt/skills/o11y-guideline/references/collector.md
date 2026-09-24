# OpenTelemetry Collector

<!-- TL;DR
Quando usar o Collector, agent ou gateway, ordem dos processors (memory_limiter primeiro, batch depois de sampling), GOMEMLIMIT, endpoint em localhost, segredo por variável de ambiente, fila e retry no exporter, WAL em disco e redação de dado sensível.
Keywords: collector, otelcol, receivers, processors, exporters, pipeline, memory_limiter, batch, GOMEMLIMIT, sending_queue, retry_on_failure, file_storage, agent, gateway, redaction, attributes, filter, transform, localhost, 0.0.0.0
Load complete when: a mudança cria ou altera configuração do Collector, decide a topologia de coleta ou trata dado sensível no pipeline.
-->

- Escopo: configuração e implantação do OpenTelemetry Collector.
- Fonte: OTel, páginas "Collector", "Configuration", "Deployment", "Agent", "Gateway",
  "Resiliency", "Handling sensitive data" e os READMEs dos componentes `memory_limiter`, `batch`,
  `redaction`, `attributes` e `otlphttp`.

## Sumário

- O11Y-COL-001 Collector em produção
- O11Y-COL-002 Agent ou gateway
- O11Y-COL-003 Ordem dos processors
- O11Y-COL-004 Limite de memória
- O11Y-COL-005 Exposição e segredo
- O11Y-COL-006 Dado sensível
- O11Y-COL-007 Resiliência do exporter
- O11Y-COL-008 Validar a configuração

## O11Y-COL-001 Collector em produção

- OTel: exportar direto do SDK para o backend serve para experimentar e para desenvolvimento em
  pequena escala.
- OTel: em produção, use Collector. O serviço descarrega a telemetria rápido e o Collector cuida de
  retry, batching, criptografia e filtro de dado sensível.
- OTel: o exportador OTLP do SDK aponta por padrão para um Collector local (`localhost:4317` gRPC,
  `localhost:4318` HTTP).

## O11Y-COL-002 Agent ou gateway

OTel:

| Padrão | Prós | Contras | Quando |
|---|---|---|---|
| Agent (um Collector junto de cada aplicação ou host) | Simples de começar; mapeamento claro entre aplicação e Collector | Escala mal para times e infraestrutura; pouco flexível | Time pequeno, desenvolvimento, primeira implantação |
| Gateway (endpoint OTLP central) | Credencial gerenciada num lugar; política central de filtro e sampling | Mais um componente que falha; latência extra em cascata; custo maior | Política central, tail sampling |

- OTel: tail sampling exige que todos os spans de um trace cheguem à mesma instância do Collector.
  Na frente dos gateways, use o exporter de load balancing com a chave `traceID`.
- OTel: os dois padrões se combinam: agentes enviam para o gateway.

## O11Y-COL-003 Ordem dos processors

- OTel: a ordem dos processors no pipeline é a ordem de processamento.
- OTel: `memory_limiter` é o primeiro processor do pipeline, para aplicar backpressure nos receivers.
- OTel: `batch` vem depois do `memory_limiter` e de qualquer processor de sampling, porque o batching
  acontece depois do descarte de dados.
- Processor de redação ou de atributo vem antes do exporter, para o dado sensível não sair do Collector.

```yaml
service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, redaction, batch]
      exporters: [otlphttp]
```

## O11Y-COL-004 Limite de memória

OTel (`memory_limiter`):

- Configure `memory_limiter` e a variável `GOMEMLIMIT` em todo Collector.
- `GOMEMLIMIT` em 80% do limite rígido de memória do Collector.
- `check_interval` recomendado: `1s`.
- Limite fixo com `limit_mib` quando o volume é conhecido; `limit_percentage` em plataforma dinâmica
  como container.
- `spike_limit_mib` começa em 20% do limite rígido.

## O11Y-COL-005 Exposição e segredo

- OTel: o Collector escuta em `localhost` por padrão. Os exemplos da documentação usam `0.0.0.0` só
  por conveniência. Use `0.0.0.0` apenas quando cliente fora do host precisa alcançar o endpoint (por
  exemplo, gateway atrás de serviço de rede) e restrinja o acesso na rede.
- OTel: a configuração aceita variável de ambiente (`${env:NOME}`, com padrão
  `${env:NOME:-valor}`). Credencial de backend entra por variável de ambiente vinda de secret, nunca
  escrita no arquivo.
- A extensão `health_check` segue a mesma regra de exposição.

## O11Y-COL-006 Dado sensível

- OTel: quem implementa é responsável pelo dado sensível; o OpenTelemetry não sabe o que é sensível no
  seu contexto. Colete só o que serve à observabilidade.
- OTel: processors para proteger dado no Collector:

| Processor | Uso |
|---|---|
| `attributes` | Remover (`delete`) ou trocar por hash (`hash`) atributo por `key` ou `pattern` |
| `filter` | Descartar span ou métrica inteira |
| `redaction` | Manter só os atributos permitidos (`allowed_keys`) e mascarar valor por padrão (`blocked_values`, `blocked_key_patterns`) |
| `transform` | Reescrever dado com expressão regular |

- OTel: hash de ID ou nome de usuário pode não anonimizar quando o conjunto de valores possíveis é
  pequeno e previsível.
- OTel: o `redaction` está em beta para traces e em alpha para logs e métricas. Verifique a
  estabilidade do componente na versão usada antes de depender dele.
- O filtro no Collector não substitui a regra de não emitir o dado (`logs.md`, O11Y-LOG-005).

## O11Y-COL-007 Resiliência do exporter

OTel:

- `sending_queue` guarda os dados em memória quando o destino está fora; `retry_on_failure` tenta de
  novo com backoff exponencial e jitter. Por padrão, desiste depois de 5 minutos (`max_elapsed_time`).
- Para sobreviver a crash do Collector, a extensão `file_storage` grava a fila em disco (WAL) e a
  retoma no restart.
- Há perda de dado quando: a rede fica fora além do timeout, a fila enche numa indisponibilidade
  longa, o Collector cai sem persistência, o disco falha ou enche, a fila de mensagens cai, a
  configuração está errada ou a resiliência foi desligada.
- Dimensione `queue_size` e `max_elapsed_time` pelo tempo de indisponibilidade do backend que o
  serviço precisa tolerar.

## O11Y-COL-008 Validar a configuração

- Rodar `otelcol validate --config <arquivo>` com o mesmo binário e a mesma distribuição (core ou
  contrib) usados em produção. Componente que não existe na distribuição reprova aqui.
- Sem o binário, rodar pela imagem oficial:
  `docker run --rm -v "$PWD/<arquivo>:/cfg.yaml" otel/opentelemetry-collector-contrib:<versão> validate --config=/cfg.yaml`.
- Sem binário nem imagem, reportar `não verificado`.
- Nome de componente muda entre versões. O exporter `otlphttp` passa no `validate` das versões 0.120,
  0.140 e 0.161 da distribuição contrib; o nome `otlp_http` só passa na 0.161. Na dúvida, o
  `validate` da versão usada decide.
