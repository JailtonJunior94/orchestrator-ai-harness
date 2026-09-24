# Gates de custo

<!-- TL;DR
Cinco gates obrigatórios antes de recomendar qualquer padrão: solução simples primeiro, economia total, eficiência com mecanismo, robustez explícita e barra alta para os padrões mais caros. Gate crítico reprovado leva a não aplicar padrão.
Keywords: overengineering, custo, economia, eficiência, robustez, Singleton, Abstract Factory, Builder, Visitor, Flyweight, recusa imediata
Load complete when: existe um candidato e é preciso decidir se ele paga o próprio custo.
-->

- Escopo: todo candidato que sai de `selection.md`.
- Fonte: regras de economia e eficiência da skill design-patterns-mandatory, reescritas para este harness.

## Sumário

- DP-GATE-001 Solução simples primeiro
- DP-GATE-002 Economia total
- DP-GATE-003 Eficiência
- DP-GATE-004 Robustez
- DP-GATE-005 Barra alta
- DP-GATE-006 Recusa imediata
- DP-GATE-007 Preferências

## DP-GATE-001 Solução simples primeiro

Gate crítico.

- Antes do padrão, avaliar função, módulo, mapa de funções, extração de método, extração de tipo ou
  composição direta.
- Reprovar quando há uma única variante concreta e nenhuma pressão real de mudança.
- Reprovar quando o único ganho é elegância, sem redução de custo ou de risco.

## DP-GATE-002 Economia total

Gate crítico.

- Medir em custo de mudança: quantos arquivos e condicionais uma nova variante toca hoje, e quantos
  tocaria com o padrão.
- Exigir evidência de duplicação, variação, branching ou acoplamento que já se repete.
- Reprovar quando o padrão adiciona mais tipos, indireção e pontos de falha do que remove.

## DP-GATE-003 Eficiência

- Separar eficiência de execução de eficiência de manutenção.
- Ganho de execução só com mecanismo explícito: menos alocação, menos I/O, cache, carga tardia,
  compartilhamento de memória.
- Ganho de manutenção só quando o padrão reduz branching, duplicação, acoplamento ou dependência de
  tipo concreto.
- Sem mecanismo, escrever "sem alegação de desempenho".

## DP-GATE-004 Robustez

Gate crítico.

- Nomear a falha que o padrão ajuda a evitar (transição inválida, variante esquecida num `switch`,
  estado global compartilhado entre testes).
- Preservar contratos, invariantes, mensagens de erro e testabilidade.
- Reprovar o padrão que torna a falha mais opaca, a depuração mais cara ou a ordem de execução mais
  difícil de rastrear.

## DP-GATE-005 Barra alta

Estes padrões exigem pelo menos dois sinais estruturais fortes e ganho operacional claro:
Abstract Factory, Builder, Bridge, Flyweight, Mediator, Visitor e Singleton.

## DP-GATE-006 Recusa imediata

| Padrão | Recusar quando |
|---|---|
| Singleton | O objetivo é conveniência, acesso fácil, cache improvisado ou estado global sem governança de concorrência e de teste |
| Abstract Factory | Há um único produto ou uma única família |
| Builder | Construtor simples, record, argumentos nomeados, literal de objeto, valor padrão ou functional options resolvem |
| Visitor | A estrutura muda com frequência, ou um método no próprio tipo basta |
| Flyweight | Não há pressão de memória medida nem cardinalidade alta de objetos equivalentes |
| Composite | A coleção é plana |
| Command | Não há fila, retry, undo, agendamento nem auditoria |
| Mediator | Um fluxo linear ou um evento simples resolve |

## DP-GATE-007 Preferências

- Composição antes de herança quando ambas resolvem.
- Composição antes de Template Method quando ambas resolvem.
- Desacoplamento local antes de estrutura grande.
- API explícita antes de indireção mágica (reflexão, registro global, injeção implícita).
- Tipos e módulos estáveis antes de árvores profundas de subclasses.
