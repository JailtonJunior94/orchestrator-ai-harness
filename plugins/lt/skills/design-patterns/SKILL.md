---
name: design-patterns
description: Decide com evidência do código se um dos 22 padrões clássicos do Refactoring.Guru resolve o problema, e qual, preferindo a solução direta quando ela custa menos. Use ao escolher, comparar, aplicar ou revisar um padrão de projeto (Strategy, State, Factory, Singleton, Adapter, Observer), ou quando switch por tipo ou if por status pedirem reorganização. Não use para bug pontual nem para padrões fora do catálogo (Repository, CQRS).
metadata:
  version: 1.0.0
  category: processual
---

# Design Patterns

Decide se um dos 22 padrões clássicos do [catálogo Refactoring.Guru](https://refactoring.guru/design-patterns/catalog)
resolve um problema real do código, e qual. O resultado mais comum e mais barato é **não aplicar
padrão**: função, tabela de dispatch, extração de método ou composição direta resolvem a maior parte
dos casos com menos tipos, menos indireção e menos pontos de falha.

## Precedência

A ordem abaixo resolve qualquer conflito:

1. A constitution do harness (`R-STYLE-001`, `R-SEC`, `R-ERR`): regra hard vence qualquer fonte externa.
2. A skill de linguagem carregada para o diff (por exemplo, `go-guideline` define o formato de
   functional options em Go e vence a forma genérica de Builder).
3. Esta skill.
4. A convenção já estabelecida no repositório, desde que não contradiga os itens acima.

## Piso inegociável

Toda decisão cumpre estas regras, sem precisar abrir nenhuma referência:

1. Sem evidência concreta (código, diff, tipos, contrato ou descrição estrutural), não há
   recomendação. Nunca recomendar padrão por analogia ou pelo nome do domínio.
2. A solução direta é avaliada primeiro. O padrão só vence se reduzir custo de mudança, branching,
   duplicação ou acoplamento que a evidência mostra que existe hoje.
3. No máximo um padrão primário. Um complementar só entra quando o desenho não fecha sem ele.
4. Só os 22 padrões do catálogo. Padrão fora dele é declarado fora de escopo, nunca aproximado sem
   prova de equivalência.
5. Toda recomendação nomeia a alternativa simples que quase venceu e os padrões vizinhos rejeitados,
   com o motivo de cada um.
6. Ganho de desempenho só é alegado com mecanismo explícito (memória, I/O, alocação, caminho quente).
7. Evidência de compatibilidade com o código existente cita `path:line`. Sem código, declarar `greenfield`.
8. Ao aplicar, o contrato público, as mensagens de erro e o comportamento observável ficam iguais.

## Veredito

A primeira linha da resposta é exatamente uma destas:

- `Recomendar: <Padrão>` (com `+ <Complementar>` apenas quando indispensável)
- `Recomendar: não aplicar padrão`
- `Evidência insuficiente: <o que falta>`

A mesma evidência leva sempre ao mesmo veredito. Empate que as regras de desempate não separam vira
`Evidência insuficiente`, com a pergunta que separa os candidatos.

## Referências

Abra só o que a decisão exige. Na Etapa 4, leia apenas a entrada do padrão primário e dos vizinhos.

| Tarefa | Referência |
|---|---|
| Converter evidência em sinais, desempatar candidatos, regras de recusa | `references/selection.md` |
| Gates de economia, eficiência e robustez; padrões de barra alta | `references/cost-gates.md` |
| Factory Method, Abstract Factory, Builder, Prototype, Singleton | `references/creational.md` |
| Adapter, Bridge, Composite, Decorator, Facade, Flyweight, Proxy | `references/structural.md` |
| Chain of Responsibility, Command, Iterator, Mediator, Memento, Observer, State, Strategy, Template Method, Visitor | `references/behavioral.md` |
| Traduzir o padrão para OO, tipagem estrutural ou funcional; code smell que aponta padrão | `references/paradigm-mapping.md` |

## Procedimentos

**Etapa 1: Coletar a evidência**
1. Ler o código citado. Ordem de força: código ou diff real, depois tipos e contratos, depois
   descrição textual.
2. Registrar o problema observável, as restrições reais (latência, memória, contrato público,
   testabilidade, frequência de mudança) e a linguagem e versão do projeto.
3. Listar o que **não** está provado. Sem essa lista a decisão tende a superprescrever.
4. Se faltar evidência material, parar com `Evidência insuficiente` e pedir só o dado que falta.

**Etapa 2: Normalizar os sinais**
1. Abrir `references/selection.md` e mapear a evidência para sinais canônicos. Só entra sinal que
   aponta para uma linha de código ou uma restrição declarada.
2. Aplicar as regras de desempate entre os candidatos.

**Etapa 3: Passar pelos gates de custo**
1. Abrir `references/cost-gates.md` e aplicar os cinco gates antes de escolher.
2. Gate crítico reprovado leva a `Recomendar: não aplicar padrão`, com a alternativa direta.

**Etapa 4: Conferir no catálogo**
1. Abrir a referência da família e ler só o primário e os vizinhos.
2. Confirmar: a intenção bate com o problema, os sinais fortes estão presentes, nenhum sinal de
   exclusão aparece e o custo estrutural cabe no caso. Falhou um item, voltar à Etapa 2.

**Etapa 5: Mapear para o paradigma real**
1. Abrir `references/paradigm-mapping.md` e escolher a forma mais simples que preserva a intenção
   (função, closure, mapa de funções, interface pequena) antes de hierarquia de classes.
2. Se a tarefa pede implementação, fazer a menor mudança que aplica a decisão, seguindo a skill de
   linguagem do diff, com código e identificadores em inglês (`R-STYLE-001.1`).
3. Se a forma escolhida exige mais estrutura do que o problema justifica, voltar para
   `não aplicar padrão`.

**Etapa 6: Validar**
1. Conferir a resposta contra o piso inegociável.
2. Rodar os testes existentes do módulo tocado. Comando que não pôde rodar é reportado como
   `não verificado`, com o motivo, nunca como aprovado.

## Formato de saída

```
Recomendar: <Padrão | não aplicar padrão>

Evidência: <path:line ou greenfield> e o sinal que cada uma sustenta
Alternativa simples rejeitada: <solução direta e por que perdeu, ou por que venceu>
Padrões rejeitados: <padrão: motivo objetivo> (os vizinhos da Etapa 4)
Ganho: economia <custo de mudança>; eficiência <mecanismo ou "sem alegação">; robustez <falha evitada>
Esboço: <código no paradigma do repo ou pseudocódigo mínimo>
Testes: positivo, negativo e regressão do comportamento preservado
Não provado: <o que a evidência não cobre>
```

## Tratamento de Erros

- Evidência insuficiente: pedir o menor conjunto de dados que decide (o trecho de código, quantas
  variantes existem hoje, se há transição de estado), sem sugerir padrão enquanto espera.
- Pedido explícito de um padrão que reprova nos gates (por exemplo, "transforma isso em Singleton"):
  explicar qual gate reprovou, propor a alternativa e só seguir o pedido original se a pessoa confirmar.
- Padrão fora do catálogo (Repository, Unit of Work, CQRS, Circuit Breaker, Saga): declarar que a
  skill não cobre e responder só sobre a parte que o catálogo cobre.
- Conflito com a skill de linguagem ou com a convenção do repo: seguir a precedência, apontar a
  divergência no relatório e não reescrever o resto do módulo por conta própria.

## Atribuição

O conjunto de padrões e a divisão em criacionais, estruturais e comportamentais seguem o catálogo
público do [Refactoring.Guru](https://refactoring.guru/design-patterns). A redação, os sinais, os
gates e os exemplos das referências são deste harness e adaptam a skill
[design-patterns-mandatory](https://github.com/JailtonJunior94/skills/blob/main/skills/design-patterns-mandatory/SKILL.md).
