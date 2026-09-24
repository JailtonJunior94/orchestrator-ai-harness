---
name: object-calisthenics-guideline
description: Aplica as 9 regras de Object Calisthenics de Jeff Bay (indentação, else, primitivos, coleções, um ponto por linha, nomes, entidades pequenas, duas variáveis, sem getters) como heurística com evidência para revisar ou refatorar código orientado a objetos, e com rigor total só em kata. Use ao revisar classe inchada, if aninhado, obsessão por primitivo, cadeia de chamadas ou getter e setter. Não use para bug pontual, SQL, script nem para escolher design pattern.
metadata:
  version: 1.0.0
  category: processual
---

# Object Calisthenics

As 9 regras de Jeff Bay (The ThoughtWorks Anthology, Pragmatic Bookshelf, 2008) nasceram como **exercício**: escrever 1000 linhas cumprindo 100% das regras e, depois, voltar a
usá-las como diretriz. O próprio autor avisa que elas se contradizem em algumas situações e podem
levar a resultados degenerados. Por isso esta skill tem dois modos e, em produção, cada regra é um
sinal que só vira achado quando a evidência mostra um custo real.

Cada regra nas referências diz de onde veio:

- `Bay:` o ensaio original afirma isso.
- `Prática:` interpretação consolidada de fonte secundária, com a fonte citada. Nunca é atribuída a Bay.
- `Harness:` decisão deste harness. O motivo vem junto.

## Modo

| Modo | Quando | Como |
|---|---|---|
| `produção` | padrão, inclusive quando o pedido não diz o modo | Heurística: achado só com evidência e custo concreto. Limites numéricos são sinal, nunca gate. |
| `exercício` | só quando a pessoa pede kata, dojo ou rigor total | As 9 regras valem 100%, com os limites de Bay (50 linhas por classe, 10 arquivos por pacote, 2 variáveis de instância). |

Na dúvida, `produção`. Nunca aplique o modo `exercício` a código de produção por conta própria.

## Precedência

1. A constitution do harness (`R-STYLE-001`, `R-SEC`, `R-ERR`): regra hard vence qualquer fonte externa.
2. A skill de linguagem carregada para o diff (por exemplo, `go-guideline`: getter sem prefixo `Get`
   e nome curto de variável local são idiomáticos em Go e vencem as regras 6 e 9).
3. Esta skill.
4. A convenção já estabelecida no repositório, desde que não contradiga os itens acima.

## Piso inegociável

No modo `produção`, toda resposta cumpre estas regras sem precisar abrir nenhuma referência:

1. Todo achado cita `path:line` e a regra (`OC-1` a `OC-9`). Sem código, não há achado.
2. Todo achado diz o custo concreto que a evidência mostra (validação duplicada, branch que cresce a
   cada caso novo, acoplamento a estrutura interna alheia). "Viola a regra 8" sozinho não é achado.
3. Os limites numéricos de Bay (1 nível de indentação, 50 linhas, 10 arquivos, 2 variáveis) são
   sinal para investigar, nunca motivo suficiente para refatorar.
4. DTO, contrato de fronteira (request, response, evento, mensagem), mapeamento de ORM, configuração
   e código de teste ficam isentos das regras 3, 8 e 9. Dado que atravessa fronteira não tem
   comportamento a encapsular.
5. Tipo novo só nasce com invariante, comportamento ou risco de troca entre valores do mesmo
   primitivo. Wrapper sem nada disso é custo sem ganho.
6. Refatoração preserva o contrato público, as mensagens de erro e o comportamento observável.
7. Quando duas regras se contradizem, vence a forma mais legível, e a resposta declara a escolha.
8. Priorize: no máximo os 5 achados de maior custo, em ordem. O resto vira uma linha de resumo.

## Veredito

A primeira linha da resposta é exatamente uma destas:

- `Conforme` (nenhum achado com custo concreto)
- `Achados: <N>` (seguido da tabela)
- `Evidência insuficiente: <o que falta>`

## Referências

Abra só a referência das regras que a evidência aciona.

| Tarefa | Referência |
|---|---|
| Regra 1 (um nível de indentação) e regra 2 (sem `else`) | `references/control-flow.md` |
| Regras 3 (primitivos), 4 (coleção de primeira classe), 8 (duas variáveis) e 9 (sem getters e setters) | `references/encapsulation.md` |
| Regras 5 (um ponto por linha), 6 (não abreviar) e 7 (entidades pequenas) | `references/coupling-naming-size.md` |
| Traduzir as regras para Go, TypeScript, Python, Java, Kotlin, C# ou estilo funcional | `references/paradigm-mapping.md` |
| Automatizar a checagem com linter | `references/tooling.md` |

## Procedimentos

**Etapa 1: Definir o modo e coletar a evidência**
1. Definir o modo pela tabela acima.
2. Ler o código citado inteiro, não só o trecho da pergunta. Registrar linguagem, versão e se o
   tipo é DTO, fronteira, ORM, configuração ou teste.
3. Sem código, parar com `Evidência insuficiente` e pedir o arquivo ou o diff.

**Etapa 2: Levantar os sinais**
1. Percorrer o código atrás dos sinais de cada regra (tabela de sinais em cada referência).
2. Abrir `references/paradigm-mapping.md` quando a linguagem não for Java ou C#: algumas regras não
   se traduzem, e isso não é achado.

**Etapa 3: Filtrar pelo custo**
1. Para cada sinal, abrir a referência da regra e conferir "Quando não aplicar".
2. Manter só o sinal que tem custo concreto na evidência (piso, itens 2 a 5). No modo `exercício`,
   todo sinal vira achado.

**Etapa 4: Propor a refatoração**
1. Nomear a refatoração pelo catálogo de [Fowler](https://refactoring.com/catalog/) (Extract
   Function, Replace Nested Conditional with Guard Clauses, Replace Primitive with Object, Hide
   Delegate) e mostrar o antes e depois mínimo no paradigma do repositório.
2. Se a solução da regra 2 pedir State ou Strategy, encaminhar a decisão para `lt:design-patterns`.
   Se a regra 3 virar modelagem de value object com regra de negócio, encaminhar para
   `lt:domain-modeling`.
3. Se a tarefa pede implementação, fazer a menor mudança que resolve os achados, com código e
   identificadores em inglês e sem comentários (`R-STYLE-001.1` e `.2`).

**Etapa 5: Validar**
1. Conferir a resposta contra o piso inegociável.
2. Rodar os testes existentes do módulo antes e depois. Comando que não pôde rodar é reportado como
   `não verificado`, com o motivo, nunca como aprovado.

## Formato de saída

```
Achados: <N>
Modo: <produção | exercício>

| # | Regra | Local | Sinal | Custo | Refatoração |
|---|---|---|---|---|---|
| 1 | OC-5 | path:line | cadeia de 3 chamadas | acopla X à estrutura de Y | Hide Delegate |

Esboço: <antes e depois mínimo do achado 1>
Isentos: <tipo e motivo, por exemplo DTO de resposta>
Contradições: <regras em conflito e a escolha feita, ou "nenhuma">
Testes: <o que cobrir e o resultado dos testes rodados, ou "não verificado: motivo">
```

## Tratamento de Erros

- Pedido "aplica as 9 regras" em código de produção sem citar kata: seguir no modo `produção`,
  dizer isso na segunda linha e explicar em uma frase que Bay define o rigor total como exercício.
- Regra da skill de linguagem contrária: seguir a precedência e citar a divergência em `Contradições`.
- Achado que exigiria mexer em contrato público: reportar com o risco e não aplicar sem
  confirmação da pessoa.
- Código procedural, script ou SQL sem objeto a encapsular: responder que a skill não se aplica e
  seguir sem ela.

## Atribuição

As 9 regras, os limites e os exemplos de origem são do ensaio "Object Calisthenics" de Jeff Bay,
publicado na The ThoughtWorks Anthology (Pragmatic Bookshelf, 2008). As interpretações marcadas
`Prática:` vêm do [Stakater Developer Handbook](https://developerhandbook.stakater.com/architecture/object-calisthenics.html),
de [William Durand](https://williamdurand.fr/2013/06/03/object-calisthenics/), do
[resumo em pt-BR de suissa](https://gist.github.com/suissa/79aa860161b13e50e5fa3a0120fb6d68) e de
[Code Cop](https://blog.code-cop.org/2018/01/compliance-with-object-calisthenics.html). A redação,
os modos, o piso e os exemplos são deste harness.
