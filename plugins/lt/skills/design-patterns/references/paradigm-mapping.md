# Mapeamento por paradigma

<!-- TL;DR
Traduz o padrão escolhido para a forma mais simples do paradigma do projeto (OO clássico, tipagem estrutural, funcional ou híbrido) e liga code smells comuns aos padrões que costumam resolvê-los.
Keywords: interface, closure, função, mapa de funções, record, union discriminada, Go, TypeScript, Java, C#, Python, code smell, switch, construtor telescópico
Load complete when: a decisão já tem um padrão e é preciso escrever o esboço ou implementar.
-->

- Escopo: da decisão ao código no paradigma real do repositório.
- Fonte: regras de mapeamento da skill design-patterns-mandatory e catálogo de
  [refatorações](https://refactoring.guru/refactoring/smells) do Refactoring.Guru; redação própria.

## Sumário

- DP-MAP-001 OO clássico
- DP-MAP-002 Tipagem estrutural
- DP-MAP-003 Funcional
- DP-MAP-004 Híbrido
- DP-MAP-005 Code smells que apontam padrão
- DP-MAP-006 Robustez do mapeamento

## DP-MAP-001 OO clássico

Java, C#, Kotlin.

- Interface ou classe abstrata só quando há polimorfismo real com mais de uma implementação hoje.
- Variação em tipos pequenos e coesos; nada de classe base com muitos ganchos.
- Template Method só quando a herança já é natural no domínio.
- Recursos da linguagem vencem a forma do livro: `record` e parâmetros nomeados antes de Builder,
  `sealed` com `switch` exaustivo antes de Visitor, `enum` com comportamento antes de State para casos pequenos.

## DP-MAP-002 Tipagem estrutural

Go, TypeScript.

- Interfaces pequenas definidas por quem consome, objetos literais, composição.
- Strategy, Observer, Adapter, Decorator e Proxy podem ser funções, closures ou tipos de um método.
- Em Go não há herança de implementação: Template Method vira função que recebe interface; Builder
  vira functional options no formato da `go-guideline`; Singleton vira instância criada em `main` e
  injetada.
- Em TypeScript, union discriminada com `switch` exaustivo (`never` no `default`) substitui Visitor
  e muitas vezes State pequeno.

## DP-MAP-003 Funcional

- Strategy vira escolha explícita de função.
- Command vira payload imutável mais handler determinístico.
- State vira máquina de estados explícita com transições puras.
- Observer vira stream ou pub/sub só quando o runtime já oferece isso com rastreabilidade.
- Decorator vira composição de funções.

## DP-MAP-004 Híbrido

Python, JavaScript, Kotlin.

- Misturar objetos e funções só quando cada parte tem papel claro.
- Efeito colateral isolado nas bordas.
- Sem várias camadas de wrapper quando uma função de alto nível resolve.
- Em Python, módulo já é instância única: não há motivo para classe Singleton.

## DP-MAP-005 Code smells que apontam padrão

O smell é evidência de problema, não de padrão. Primeiro tentar a refatoração direta; o padrão só
entra se ela não resolver.

| Smell observado no código | Refatoração direta | Padrão, se a direta não bastar |
|---|---|---|
| `switch` ou `if` por tipo repetido em vários lugares | Substituir condicional por polimorfismo ou por mapa de funções | Strategy, ou State se houver transição |
| Construtor com muitos parâmetros, vários opcionais | Objeto de parâmetros ou valores padrão | Builder |
| `if status == ...` espalhado por várias operações | Tabela de transições centralizada | State |
| Mesma sequência de chamadas a um subsistema em vários chamadores | Extrair função | Facade |
| Tipo externo ou de legado usado direto no domínio | Função de conversão na borda | Adapter |
| Mudança pequena exige editar muitas classes (shotgun surgery) | Mover responsabilidade para um lugar só | Mediator ou Observer, conforme o acoplamento |
| Hierarquia que cresce pelo produto de duas dimensões | Extrair uma das dimensões para composição | Bridge |
| Mesmo passo a passo duplicado em várias classes com pequenas diferenças | Extrair função com parâmetros | Template Method ou Strategy |

## DP-MAP-006 Robustez do mapeamento

- Preservar mensagens de erro, contratos públicos e invariantes existentes.
- Não esconder ordem de execução, posse de recurso ou limite de transação atrás da indireção.
- Escolher a forma de menor surpresa para quem mantém o código hoje.
- Código, identificadores e mensagens em inglês; nenhum comentário no código produzido (`R-STYLE-001`).
