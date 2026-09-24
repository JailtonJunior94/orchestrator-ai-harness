# Traces

<!-- TL;DR
Como criar spans úteis: nome de baixa cardinalidade, span kind correto, status Error em falha, evento quando o instante importa, link para causalidade assíncrona, propagação por W3C Trace Context, baggage sem dado sensível e sampling com critério.
Keywords: span, tracer, SpanKind, status, Error, Ok, RecordError, event, link, traceparent, W3C, baggage, sampling, head, tail, ParentBased
Load complete when: a mudança cria ou altera span, propaga contexto entre processos, usa baggage ou configura sampling.
-->

- Escopo: todo código que cria span, propaga contexto de trace ou decide sampling.
- Fonte: OTel, páginas "Traces", "Context propagation", "Sampling" e "SDK configuration".

## Sumário

- O11Y-TRC-001 Nome de span
- O11Y-TRC-002 Span kind
- O11Y-TRC-003 Status
- O11Y-TRC-004 Todo span é encerrado
- O11Y-TRC-005 Atributo ou evento
- O11Y-TRC-006 Link para causalidade assíncrona
- O11Y-TRC-007 Propagação
- O11Y-TRC-008 Baggage
- O11Y-TRC-009 Sampling

## O11Y-TRC-001 Nome de span

- OTel: o nome é a string mais geral que identifica uma classe de spans, não uma instância, e ainda
  legível. `get_account` ou `get_account/{accountId}` servem; `get` é vago demais e
  `get_user/314159` é específico demais.
- OTel: ID, e-mail, URL completa ou qualquer valor variável vai para atributo, nunca para o nome.

## O11Y-TRC-002 Span kind

OTel: o kind diz ao backend como montar o trace.

| Kind | Quando |
|---|---|
| `SERVER` | Recebe chamada remota síncrona (requisição HTTP, RPC) |
| `CLIENT` | Faz chamada remota síncrona (requisição HTTP de saída, chamada a banco) |
| `PRODUCER` | Cria trabalho que será processado depois, de forma assíncrona |
| `CONSUMER` | Processa trabalho criado por um produtor, podendo começar muito depois |
| `INTERNAL` | Operação que não cruza a fronteira do processo (padrão) |

## O11Y-TRC-003 Status

OTel: três valores.

- `Unset` (padrão): terminou sem erro. Não precisa marcar nada.
- `Error`: houve erro. Obrigatório quando a operação falhou.
- `Ok`: decisão explícita de que a operação teve sucesso. Uma vez `Ok`, o status é final. Na
  maioria dos casos não é necessário.
- OTel: biblioteca de instrumentação deixa `Unset` e só marca `Error` quando há erro; `Ok` fica
  para a aplicação ou para quem opera.

OTel (Go): registrar o erro no span não muda o status. Chame os dois:

```go
span.RecordError(err)
span.SetStatus(codes.Error, "charge card")
```

A descrição do status é curta e sem dado sensível; o detalhe vai no evento de exceção.

## O11Y-TRC-004 Todo span é encerrado

OTel: todo span criado tem que ser encerrado, e isso é responsabilidade de quem o criou. Span
esquecido pode vazar memória e não chega ao backend. Encerre no mesmo escopo em que abriu,
em todos os caminhos, inclusive nos de erro (`defer span.End()` em Go, `try/finally` ou `with` nas
outras linguagens).

## O11Y-TRC-005 Atributo ou evento

- OTel: se o instante em que algo aconteceu importa, é evento (`AddEvent`); se não importa, é atributo.
- OTel: chave de atributo é string não nula; valor é string, booleano, ponto flutuante, inteiro ou
  array desses tipos.
- Nome de atributo segue a convenção semântica quando ela define um (ver `semconv.md`).

## O11Y-TRC-006 Link para causalidade assíncrona

OTel: link associa um span a outros com relação causal quando a execução é assíncrona, por exemplo
um consumidor que processa um lote de mensagens de traces diferentes. Não force relação pai e filho
entre operações que não são síncronas.

## O11Y-TRC-007 Propagação

- OTel: a propagação padrão usa os headers da especificação W3C Trace Context (`traceparent`).
  `OTEL_PROPAGATORS` tem padrão `tracecontext,baggage`.
- OTel: a propagação costuma ficar a cargo da biblioteca de instrumentação. Propagar à mão só onde
  não existe instrumentação, como protocolo próprio ou fila sem suporte, usando a API de Propagators
  sobre o carrier (headers, metadados da mensagem).
- OTel: trace ID, span ID e baggage enviados a serviços externos podem revelar detalhes da
  arquitetura interna. Avalie o que atravessa a fronteira com terceiros.

## O11Y-TRC-008 Baggage

- OTel: baggage carrega pares chave e valor através das fronteiras de serviço.
- OTel: nunca colocar credencial, chave de API ou PII em baggage. Ele pode ser logado ou enviado a
  serviços downstream não confiáveis.
- Baggage não vira atributo sozinho. Copie para o span só a chave que a análise precisa.

## O11Y-TRC-009 Sampling

OTel:

| Estratégia | Como decide | Vantagem | Limitação |
|---|---|---|---|
| Head | No início, pelo trace ID e uma porcentagem | Simples e barato | Não garante guardar todos os traces com erro |
| Tail | Depois de ver todos ou quase todos os spans | Guarda por erro, latência ou atributo | Regras para manter, sistema com estado e custo de recurso |

- OTel: amostrar faz sentido com 1000 ou mais traces por segundo, tráfego majoritariamente saudável,
  critério claro do que guardar e restrição de custo.
- OTel: não amostrar com volume baixo (dezenas de traces pequenos por segundo), quando só se usa dado
  agregado ou quando há restrição regulatória para descartar dado.
- OTel: head e tail podem ser combinados em sistemas de alto volume para proteger o pipeline.
- OTel: o sampler padrão do SDK é `parentbased_always_on`. Para head sampling por proporção, use
  `OTEL_TRACES_SAMPLER=parentbased_traceidratio` e `OTEL_TRACES_SAMPLER_ARG` entre 0 e 1. O prefixo
  `parentbased` respeita a decisão de quem chamou e mantém o trace inteiro.
- Tail sampling roda no Collector (processor de tail sampling), não no SDK.
