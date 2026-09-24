# Logs

<!-- TL;DR
O OpenTelemetry não cria uma API de log nova: a aplicação mantém a biblioteca de log e liga uma bridge. Log estruturado com schema estável, correlacionado ao trace pelo TraceId e SpanId, com severidade coerente e sem dado sensível.
Keywords: log, Logs Bridge API, appender, bridge, estruturado, JSON, TraceId, SpanId, severity, SeverityNumber, correlação, slog, pino, structlog
Load complete when: a mudança escreve log, configura biblioteca de log, liga a bridge de log ao OpenTelemetry ou precisa correlacionar log com trace.
-->

- Escopo: todo log emitido por serviço em produção.
- Fonte: OTel, página "Logs", e a regra `R-OBS-001` do harness.

## Sumário

- O11Y-LOG-001 Manter a biblioteca de log
- O11Y-LOG-002 Log estruturado com schema estável
- O11Y-LOG-003 Correlação com o trace
- O11Y-LOG-004 Severidade com intenção
- O11Y-LOG-005 Sem dado sensível

## O11Y-LOG-001 Manter a biblioteca de log

- OTel: não existe API de log do OpenTelemetry para a aplicação usar direto. A Logs Bridge API serve
  para quem escreve appender ou bridge, que liga a biblioteca de log existente (slog, logback, pino,
  logging do Python) ao exportador do OpenTelemetry.
- Não troque a biblioteca de log do serviço para adotar OpenTelemetry. Ligue a bridge dela.

## O11Y-LOG-002 Log estruturado com schema estável

- OTel: log estruturado é o preferido em produção, porque o schema estável facilita validar,
  interpretar, correlacionar com traces e métricas e analisar em escala.
- OTel: JSON sozinho não torna o log estruturado. Estruturado é ter os mesmos nomes de campo com os
  mesmos tipos em todo evento do mesmo tipo.
- A `R-OBS-001` exige os campos `level`, `msg`, `error`, `trace_id` e `request_id`.
- Mensagem fixa e dados em campos: `logger.Info("order created", "order.id", id)`, nunca o valor
  interpolado na mensagem.

## O11Y-LOG-003 Correlação com o trace

- OTel: o registro de log tem os campos `TraceId` e `SpanId`. Com a instrumentação ativa, o
  OpenTelemetry correlaciona o log ao trace e ao span ativos.
- A correlação depende do contexto chegar ao logger. Use a variante do logger que recebe o contexto
  (`InfoContext(ctx, ...)` no slog, por exemplo) dentro de código que tem span ativo.
- Sem bridge (log em stdout coletado por agente), escreva `trace_id` e `span_id` como campos do log
  para permitir a correlação no backend.

## O11Y-LOG-004 Severidade com intenção

OTel: o registro tem `SeverityText` e `SeverityNumber`. A `R-OBS-001` define o uso:

| Nível | Quando |
|---|---|
| `debug` | Diagnóstico em desenvolvimento |
| `info` | Evento operacional |
| `warn` | Degradação tolerada |
| `error` | Falha que exige atenção |

- Logar em fronteira de IO, erro e decisão de negócio relevante, não em cada linha (`R-OBS-001`).

## O11Y-LOG-005 Sem dado sensível

- A `R-OBS-001` proíbe logar token, segredo, senha, PII e corpo de request com dado pessoal.
- OTel: quem implementa é responsável pelo que coleta e deve revisar também a telemetria emitida
  pelas bibliotecas de instrumentação que usa. Filtro no Collector é a segunda linha de defesa, não
  a primeira (ver `collector.md`, O11Y-COL-006).
