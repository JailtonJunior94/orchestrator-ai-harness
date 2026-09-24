# Sinais de ouro

<!-- TL;DR
Os 4 sinais de ouro (latência, tráfego, erros e saturação), como medir cada um, a relação com RED e USE, a correlação entre sinais e as regras de agregação em PromQL que evitam número errado.
Keywords: golden signals, sinais de ouro, latência, tráfego, erros, saturação, RED, USE, percentil, histogram_quantile, PromQL
Load complete when: a tarefa decide o que medir num serviço, monta dashboard ou escreve PromQL sobre latência, tráfego, erro ou saturação.
-->

- Escopo: escolha e cálculo dos sinais de saúde de um serviço.
- Fonte: SRE (OpServices, "Os 4 sinais de ouro do SRE"; groundcover, "4 Golden Signals") e OTel
  (convenções semânticas de HTTP).

## Sumário

- O11Y-SIG-001 Medir os quatro sinais
- O11Y-SIG-002 Latência por percentil, separada por resultado
- O11Y-SIG-003 Tráfego como contexto
- O11Y-SIG-004 Erros explícitos, implícitos e de política
- O11Y-SIG-005 Saturação relativa à capacidade
- O11Y-SIG-006 Agregar antes de calcular
- O11Y-SIG-007 Correlacionar sinais
- O11Y-SIG-008 RED e USE

## O11Y-SIG-001 Medir os quatro sinais

SRE: todo serviço que atende requisições expõe os quatro sinais:

| Sinal | O que mede | Exemplo de medida |
|---|---|---|
| Latência | Tempo entre enviar a requisição e receber a resposta | Histograma de duração por rota |
| Tráfego | Demanda sobre o sistema | Requisições por segundo, mensagens consumidas por segundo, transações por segundo |
| Erros | Requisições que falham ou devolvem resposta inesperada | Taxa de 5xx, resposta incompleta ou corrompida |
| Saturação | Uso dos recursos em relação à capacidade total | CPU, memória, pool de conexões, fila, threads |

SRE: o diferencial dos 4 sinais é juntar demanda (tráfego) e limite de capacidade (saturação), o que
permite antecipar o colapso em vez de só constatar a falha.

## O11Y-SIG-002 Latência por percentil, separada por resultado

- SRE: medir percentis (p50, p95, p99), nunca só a média. O p99 mostra a experiência de quem é mais afetado.
- SRE: separar a latência das requisições com sucesso da latência das com erro. Uma requisição que
  falha rápido tem latência baixa, mas indica falha rápida, não saúde.
- OTel: a latência de servidor HTTP é o Histogram `http.server.request.duration`, em segundos, com o
  atributo `error.type` quando a requisição termina em erro. É por esse atributo (ou pelo
  `http.response.status_code`) que a separação acontece.

```promql
histogram_quantile(0.99,
  sum by (le, http_route) (
    rate(http_server_request_duration_seconds_bucket{error_type=""}[5m])
  )
)
```

O nome exato da métrica e dos labels depende da tradução para o backend (ver `metrics.md`,
O11Y-MET-007). Confirme no backend antes de usar.

## O11Y-SIG-003 Tráfego como contexto

SRE: tráfego dá escala aos outros sinais. Erro de 1% com 10 RPS tem impacto pequeno; erro de 1% com
10.000 RPS são 100 usuários afetados por segundo. Todo painel de erro ou latência mostra o tráfego ao lado.

```promql
sum by (http_route) (rate(http_server_request_duration_seconds_count[5m]))
```

## O11Y-SIG-004 Erros explícitos, implícitos e de política

SRE: contar os três tipos:

1. Explícito: resposta de falha, como HTTP 5xx.
2. Implícito: HTTP 200 com conteúdo errado. Só aparece com validação do lado do serviço ou teste sintético.
3. De política: resposta correta, mas acima do objetivo de latência.

OTel: `error.type` tem valor previsível e de baixa cardinalidade: nome da classe de exceção, código de
status como string ou identificador próprio do componente.

## O11Y-SIG-005 Saturação relativa à capacidade

- SRE: saturação é uso dividido pela capacidade, não o uso bruto. Medir o recurso que acaba primeiro:
  CPU, memória, conexões do pool, profundidade de fila, threads, inodes, banda.
- SRE: a OpServices cita CPU consistentemente acima de 80% ou memória acima de 90% como sistema
  saturado, mesmo ainda respondendo. Trate esses números como ponto de partida, não como limite do
  serviço: o limite certo vem do teste de carga ou do histórico.
- SRE: para memória em Linux, usar `MemAvailable`, nunca `MemFree`, porque o cache de página distorce `MemFree`.
- OTel: o padrão de nome para fração de uso é `<entidade>.utilization`, no intervalo [0, 1]
  (ver `metrics.md`, O11Y-MET-003).

## O11Y-SIG-006 Agregar antes de calcular

SRE: somar antes de ler e agregar numerador e denominador separadamente antes de dividir. Média de
razões por instância não é a razão do serviço.

```promql
sum by (service_name) (rate(http_server_request_duration_seconds_count{http_response_status_code=~"5.."}[5m]))
/
sum by (service_name) (rate(http_server_request_duration_seconds_count[5m]))
```

- Para percentil, `sum by (le, ...)` dentro do `histogram_quantile`. Nunca calcular o percentil por
  instância e depois tirar a média.
- Todo label que aparece no `by` do numerador aparece no `by` do denominador.

## O11Y-SIG-007 Correlacionar sinais

SRE (groundcover):

- Latência subindo junto com saturação perto de 100% aponta falta de recurso como causa provável.
- Saturação subindo sem aumento de tráfego sugere problema interno, como vazamento de memória.
- Dashboard de serviço põe os quatro sinais na mesma janela de tempo para permitir essa leitura.

## O11Y-SIG-008 RED e USE

SRE:

| Método | Cobre | Não cobre |
|---|---|---|
| 4 sinais de ouro | Latência, tráfego, erros, saturação | Detalhe por recurso individual |
| RED | Rate, errors, duration | Saturação |
| USE | Utilization, saturation, errors | Latência e demanda |

- Serviço que atende requisição: 4 sinais (RED mais saturação). A `R-OBS-001` exige no mínimo RED.
- Recurso de infraestrutura (disco, rede, pool): USE.
- Sem tráfego orgânico suficiente para medir, usar monitoramento sintético (groundcover).
