# Padrões criacionais

<!-- TL;DR
Factory Method, Abstract Factory, Builder, Prototype e Singleton: intenção, sinais fortes, sinais de exclusão, custo, alternativa direta, forma enxuta e o que testar.
Keywords: criação, construtor, new, factory, builder, clone, instância única, configuração, construtor telescópico
Load complete when: o candidato ou um vizinho dele é um padrão de criação.
-->

- Escopo: como objetos são criados e montados.
- Fonte: catálogo do [Refactoring.Guru](https://refactoring.guru/design-patterns/creational-patterns); redação própria.

## Sumário

- DP-CRE-001 Factory Method
- DP-CRE-002 Abstract Factory
- DP-CRE-003 Builder
- DP-CRE-004 Prototype
- DP-CRE-005 Singleton

## DP-CRE-001 Factory Method

[Refactoring.Guru](https://refactoring.guru/design-patterns/factory-method)

- Intenção: delegar a escolha do tipo concreto de um produto a um ponto de criação, sem expor o tipo concreto ao cliente.
- Sinais fortes: `single_product_variation`; o mesmo `if`/`switch` de criação aparece em mais de um lugar.
- Sinais de exclusão: família inteira de produtos; um único produto concreto; criação trivial.
- Custo estrutural: moderado.
- Alternativa direta: uma função `newNotifier(kind)` com um `switch` único costuma bastar; a forma de subclasses criadoras só se paga quando o criador também tem comportamento próprio.
- Forma enxuta: função construtora ou mapa `tipo -> construtor`.
- Testar: cada variante retorna o tipo esperado; tipo desconhecido falha de forma explícita.

## DP-CRE-002 Abstract Factory

[Refactoring.Guru](https://refactoring.guru/design-patterns/abstract-factory)

- Intenção: criar famílias de produtos relacionados que precisam permanecer compatíveis entre si.
- Sinais fortes: `family_of_related_products` e `cross_product_consistency`; misturar produtos de famílias diferentes já causou ou causaria defeito.
- Sinais de exclusão: um único produto; uma única família; troca de família rara ou hipotética.
- Custo estrutural: alto. Barra alta (DP-GATE-005).
- Alternativa direta: um módulo por família exportando funções construtoras.
- Forma enxuta: struct ou objeto com uma função por produto, escolhido uma vez na composição da aplicação.
- Testar: cada família produz peças compatíveis; não existe caminho que misture famílias.

## DP-CRE-003 Builder

[Refactoring.Guru](https://refactoring.guru/design-patterns/builder)

- Intenção: montar um objeto complexo passo a passo, sem construtor telescópico.
- Sinais fortes: `stepwise_construction`; muitos parâmetros opcionais; validação que envolve vários campos; representações diferentes do mesmo objeto.
- Sinais de exclusão: poucos campos; a linguagem oferece argumentos nomeados, literal de objeto ou valor padrão.
- Custo estrutural: médio a alto. Barra alta (DP-GATE-005).
- Alternativa direta: objeto de opções, record com valor padrão ou functional options (em Go, no formato definido pela `go-guideline`).
- Forma enxuta: acumulador imutável com `build()` que valida e devolve erro, em vez de builder mutável compartilhado.
- Testar: objeto mínimo válido; combinação inválida rejeitada no `build()`; valores padrão aplicados.

## DP-CRE-004 Prototype

[Refactoring.Guru](https://refactoring.guru/design-patterns/prototype)

- Intenção: criar objetos copiando um exemplar configurado, sem depender do tipo concreto.
- Sinais fortes: `clone_template`; criação cara (I/O, parsing, cálculo) repetida com pequenas variações.
- Sinais de exclusão: construção barata; cópia rasa compartilharia estado mutável; identidade única obrigatória.
- Custo estrutural: médio.
- Alternativa direta: função que devolve uma configuração base e recebe as variações.
- Forma enxuta: método `clone()` com cópia profunda explícita dos campos mutáveis.
- Testar: alterar o clone não altera o original; campos de referência são copiados, não compartilhados.

## DP-CRE-005 Singleton

[Refactoring.Guru](https://refactoring.guru/design-patterns/singleton)

- Intenção: garantir uma única instância de um recurso por contexto controlado.
- Sinais fortes: `single_process_shared_resource`, com inicialização coordenada e governança de concorrência.
- Sinais de exclusão: conveniência de acesso global; testes que precisam de instância isolada; multitenancy; chance de precisar de mais de uma instância.
- Custo estrutural: alto risco. Barra alta (DP-GATE-005) e recusa imediata (DP-GATE-006).
- Alternativa direta: criar a instância uma vez na composição da aplicação (`main`) e injetar em quem usa.
- Forma enxuta: quando realmente necessário, inicialização única e thread-safe da própria linguagem (`sync.Once`, `Lazy<T>`, módulo carregado uma vez), sem acesso global mutável.
- Testar: acesso concorrente cria uma única instância; os testes conseguem substituir a dependência sem estado vazando entre eles.
