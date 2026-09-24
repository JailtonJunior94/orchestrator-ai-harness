# Alertas e dashboards

<!-- TL;DR
Alerta sobre os 4 sinais comparado com baseline ou objetivo, sem limiar ruidoso, com razão agregada corretamente, tráfego como contexto, correlação entre sinais no dashboard e validação com promtool.
Keywords: alerta, alert, alerting rule, recording rule, baseline, SLO, fadiga de alerta, dashboard, promtool, for, severity, sintético
Load complete when: a tarefa cria ou revisa regra de alerta, recording rule ou dashboard de serviço.
-->

- Escopo: regras de alerta, recording rules e dashboards sobre os sinais de um serviço.
- Fonte: SRE (groundcover e OpServices) e a mecânica de regras do Prometheus.

## Sumário

- O11Y-ALR-001 Alerta sobre os sinais, contra baseline
- O11Y-ALR-002 Sem limiar ruidoso
- O11Y-ALR-003 Consulta correta antes de limiar
- O11Y-ALR-004 Dashboard que correlaciona
- O11Y-ALR-005 Validar as regras

## O11Y-ALR-001 Alerta sobre os sinais, contra baseline

- SRE (groundcover): alertar sobre anomalia em relação ao baseline do serviço.
- SRE (OpServices): resposta acima do objetivo de latência conta como erro de política
  (ver `signals.md`, O11Y-SIG-004). Com objetivo definido, o alerta compara com ele.
- Sem objetivo nem baseline medido, o limiar proposto é explícito como ponto de partida e o
  relatório diz de onde saiu. Nunca apresentar número inventado como limite do serviço.

## O11Y-ALR-002 Sem limiar ruidoso

- SRE (groundcover): evitar limiar ruidoso, que gera fadiga de alerta.
- Prometheus: `for` exige que a condição se mantenha pelo período antes de disparar, o que filtra pico isolado.
- Razão de erro com tráfego muito baixo oscila muito. Condicione o alerta a um tráfego mínimo
  (ver `signals.md`, O11Y-SIG-003).

## O11Y-ALR-003 Consulta correta antes de limiar

- Percentil com `histogram_quantile` sobre `sum by (le, ...)` de `rate(..._bucket[...])`.
- Razão de erro com numerador e denominador agregados separadamente, com os mesmos labels no `by`.
- Latência de sucesso separada da de erro.
- Nome da métrica confirmado no backend (ver `metrics.md`, O11Y-MET-007).

Base completa: `assets/golden-signals.rules.yaml`.

## O11Y-ALR-004 Dashboard que correlaciona

- SRE (groundcover): visualizar os sinais juntos ajuda a interpretar e a achar tendência. Os quatro
  sinais do serviço ficam no mesmo dashboard, na mesma janela de tempo.
- SRE: tráfego ao lado de erro e latência, para dar escala ao número.
- SRE (groundcover): sem tráfego orgânico suficiente, monitoramento sintético gera o sinal.

## O11Y-ALR-005 Validar as regras

- Rodar `promtool check rules <arquivo>`. Sem `promtool`, reportar `não verificado`.
- `promtool` valida sintaxe, não o nome da métrica. Conferir no backend que a consulta retorna série.
