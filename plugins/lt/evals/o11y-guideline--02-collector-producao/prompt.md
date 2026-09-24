Esse evals/fixtures/collector/otel-collector.yaml vai para produção amanhã. Está pronto? Corrige o que precisar.

O repositório não está disponível nesta sessão; o conteúdo atual dos arquivos citados vai abaixo.

`evals/fixtures/collector/otel-collector.yaml`:

```
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch: {}
  memory_limiter:
    check_interval: 1s
    limit_mib: 1500

exporters:
  otlphttp:
    endpoint: https://otlp.vendor.example.com
    headers:
      api-key: demo-plaintext-key-0001
    retry_on_failure:
      enabled: false
    sending_queue:
      enabled: false

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch, memory_limiter]
      exporters: [otlphttp]
    logs:
      receivers: [otlp]
      processors: [batch, memory_limiter]
      exporters: [otlphttp]
```
