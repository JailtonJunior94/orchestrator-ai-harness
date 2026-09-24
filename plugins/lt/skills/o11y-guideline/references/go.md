# OpenTelemetry em Go

<!-- TL;DR
Setup do SDK Go com resource vindo do ambiente, exportadores OTLP, propagator W3C, shutdown com errors.Join, handler HTTP instrumentado, span com status Error, contador com atributo limitado e log pelo bridge do slog com contexto.
Keywords: go.opentelemetry.io/otel, sdktrace, sdkmetric, sdklog, otlptracegrpc, otlpmetricgrpc, otlploggrpc, otelhttp, otelslog, resource.WithFromEnv, codes.Error, RecordError, Shutdown
Load complete when: a mudança configura ou usa o SDK do OpenTelemetry em código Go.
-->

- Escopo: serviço Go que emite traces, métricas ou logs com OpenTelemetry.
- Fonte: OTel, páginas "Go: Getting started", "Go: Instrumentation" e "Go: Exporters"; pacote
  `go.opentelemetry.io/contrib/bridges/otelslog`. Exemplo compilado com `go.opentelemetry.io/otel`
  v1.46.0, `otelhttp` v0.71.0 e `otelslog` v0.20.1. Em outra versão, confira a API com `go doc`.
- As regras de Go em si (erros, goroutines, `run() error`) vêm da skill `go-guideline`.

## Sumário

- O11Y-GO-001 Setup único com shutdown
- O11Y-GO-002 Resource e exportador pelo ambiente
- O11Y-GO-003 HTTP pela biblioteca de instrumentação
- O11Y-GO-004 Span manual com status
- O11Y-GO-005 Instrumento criado uma vez
- O11Y-GO-006 Log pelo bridge do slog

## O11Y-GO-001 Setup único com shutdown

- OTel: providers são criados uma vez, no início do processo, e registrados como globais.
- `Shutdown` de cada provider roda na saída, com prazo, para descarregar o que está em buffer. Sem
  ele, os últimos spans e pontos se perdem.

```go
func setupOTel(ctx context.Context) (func(context.Context) error, error) {
	var shutdownFuncs []func(context.Context) error
	shutdown := func(ctx context.Context) error {
		var err error
		for _, fn := range shutdownFuncs {
			err = errors.Join(err, fn(ctx))
		}
		shutdownFuncs = nil
		return err
	}

	res, err := resource.New(ctx, resource.WithFromEnv(), resource.WithTelemetrySDK())
	if err != nil {
		return shutdown, err
	}

	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{},
		propagation.Baggage{},
	))

	traceExporter, err := otlptracegrpc.New(ctx)
	if err != nil {
		return shutdown, errors.Join(err, shutdown(ctx))
	}
	tracerProvider := sdktrace.NewTracerProvider(
		sdktrace.WithResource(res),
		sdktrace.WithBatcher(traceExporter),
	)
	shutdownFuncs = append(shutdownFuncs, tracerProvider.Shutdown)
	otel.SetTracerProvider(tracerProvider)

	metricExporter, err := otlpmetricgrpc.New(ctx)
	if err != nil {
		return shutdown, errors.Join(err, shutdown(ctx))
	}
	meterProvider := sdkmetric.NewMeterProvider(
		sdkmetric.WithResource(res),
		sdkmetric.WithReader(sdkmetric.NewPeriodicReader(metricExporter)),
	)
	shutdownFuncs = append(shutdownFuncs, meterProvider.Shutdown)
	otel.SetMeterProvider(meterProvider)

	logExporter, err := otlploggrpc.New(ctx)
	if err != nil {
		return shutdown, errors.Join(err, shutdown(ctx))
	}
	loggerProvider := sdklog.NewLoggerProvider(
		sdklog.WithResource(res),
		sdklog.WithProcessor(sdklog.NewBatchProcessor(logExporter)),
	)
	shutdownFuncs = append(shutdownFuncs, loggerProvider.Shutdown)
	global.SetLoggerProvider(loggerProvider)

	return shutdown, nil
}
```

Imports: `go.opentelemetry.io/otel`, `.../otel/propagation`, `.../otel/log/global`,
`.../otel/sdk/resource`, `sdktrace ".../otel/sdk/trace"`, `sdkmetric ".../otel/sdk/metric"`,
`sdklog ".../otel/sdk/log"`, `.../otel/exporters/otlp/otlptrace/otlptracegrpc`,
`.../otel/exporters/otlp/otlpmetric/otlpmetricgrpc` e `.../otel/exporters/otlp/otlplog/otlploggrpc`.

No `run() error`:

```go
shutdown, err := setupOTel(ctx)
if err != nil {
	return err
}
defer func() {
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	err = errors.Join(err, shutdown(shutdownCtx))
}()
```

## O11Y-GO-002 Resource e exportador pelo ambiente

- `resource.WithFromEnv()` lê `OTEL_SERVICE_NAME` e `OTEL_RESOURCE_ATTRIBUTES`. Nome, versão e
  ambiente do serviço vêm do deploy, não do código (ver `semconv.md`, O11Y-SEM-002).
- OTel: os exportadores OTLP do Go já leem `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_EXPORTER_OTLP_HEADERS`,
  `OTEL_EXPORTER_OTLP_TIMEOUT` e `OTEL_EXPORTER_OTLP_COMPRESSION`. Não fixe endpoint nem credencial
  com opção no código.
- Existem variantes HTTP (`otlptracehttp`, `otlploghttp`) quando o Collector recebe só OTLP/HTTP.

## O11Y-GO-003 HTTP pela biblioteca de instrumentação

Envolva o handler com `otelhttp` em vez de criar span de servidor à mão. Ele cria o span `SERVER`,
extrai o contexto propagado e registra as métricas HTTP.

```go
mux := http.NewServeMux()
mux.HandleFunc("GET /orders/{id}", getOrder)
srv := &http.Server{Addr: ":8080", Handler: otelhttp.NewHandler(mux, "server")}
```

Para cliente HTTP, use `otelhttp.NewTransport` no `http.Client`, para o contexto seguir na chamada
de saída.

## O11Y-GO-004 Span manual com status

OTel (Go): `RecordError` não muda o status do span; marque `codes.Error` junto.

```go
func (c *Checkout) Charge(ctx context.Context, orderID string, provider string) error {
	ctx, span := otel.Tracer(scope).Start(ctx, "charge order")
	defer span.End()

	span.SetAttributes(attribute.String("com.example.order.id", orderID))

	err := c.gateway.Charge(ctx, orderID)
	c.charged.Add(ctx, 1, metric.WithAttributes(attribute.String("com.example.payment.provider", provider)))
	if err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, "charge order")
		return fmt.Errorf("charge order %q: %w", orderID, err)
	}
	return nil
}
```

- O ID do pedido vai no span, que aceita alta cardinalidade. Na métrica vai só o provedor, de
  conjunto fechado.
- O `ctx` devolvido pelo `Start` é o que segue para as chamadas internas; usar o `ctx` antigo quebra
  a hierarquia do trace.

## O11Y-GO-005 Instrumento criado uma vez

Crie o instrumento no construtor e guarde no tipo. Criar a cada chamada repete trabalho e esconde erro.

```go
func NewCheckout(gateway Gateway) (*Checkout, error) {
	charged, err := otel.Meter(scope).Int64Counter(
		"com.example.checkout.charges",
		metric.WithDescription("Charges attempted."),
		metric.WithUnit("{charge}"),
	)
	if err != nil {
		return nil, fmt.Errorf("create charges counter: %w", err)
	}
	return &Checkout{gateway: gateway, charged: charged}, nil
}
```

## O11Y-GO-006 Log pelo bridge do slog

- OTel: não há API de log do OpenTelemetry para a aplicação; use o bridge da biblioteca de log.
- `otelslog.NewLogger(name)` devolve um `*slog.Logger` ligado ao LoggerProvider global.
- O SDK de log tira `TraceId` e `SpanId` do contexto recebido. Use os métodos com contexto
  (`InfoContext`, `ErrorContext`); `logger.Info` sem contexto sai sem correlação.

```go
logger := otelslog.NewLogger(scope)
logger.InfoContext(ctx, "order charged", "com.example.payment.provider", provider)
```

- Injete o `*slog.Logger` como dependência (regra de estado global da `go-guideline`).
