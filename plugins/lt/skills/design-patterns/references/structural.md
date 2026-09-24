# Padrões estruturais

<!-- TL;DR
Adapter, Bridge, Composite, Decorator, Facade, Flyweight e Proxy: intenção, sinais fortes, sinais de exclusão, custo, alternativa direta, forma enxuta e o que testar.
Keywords: wrapper, interface incompatível, integração, legado, árvore, middleware, cache, carga tardia, subsistema, memória
Load complete when: o candidato ou um vizinho dele organiza a composição entre objetos.
-->

- Escopo: como objetos e módulos se compõem em estruturas maiores.
- Fonte: catálogo do [Refactoring.Guru](https://refactoring.guru/design-patterns/structural-patterns); redação própria.

## Sumário

- DP-EST-001 Adapter
- DP-EST-002 Bridge
- DP-EST-003 Composite
- DP-EST-004 Decorator
- DP-EST-005 Facade
- DP-EST-006 Flyweight
- DP-EST-007 Proxy

## DP-EST-001 Adapter

[Refactoring.Guru](https://refactoring.guru/design-patterns/adapter)

- Intenção: tornar uma interface existente compatível com a interface que o cliente espera.
- Sinais fortes: `external_interface_mismatch`; tipos de SDK externo ou legado vazando para o domínio.
- Sinais de exclusão: o problema é simplificar um subsistema inteiro; duas dimensões variam.
- Custo estrutural: baixo a médio.
- Alternativa direta: função de conversão na borda, quando só um ponto consome a API externa.
- Forma enxuta: tipo pequeno que implementa a interface do domínio e traduz para o SDK, incluindo erros.
- Testar: tradução de entrada e saída; erro externo convertido para o erro do domínio; nenhum tipo externo atravessa a interface.

## DP-EST-002 Bridge

[Refactoring.Guru](https://refactoring.guru/design-patterns/bridge)

- Intenção: separar abstração e implementação para que variem de forma independente.
- Sinais fortes: `dual_axis_variation`; o número de classes cresce pelo produto de duas dimensões.
- Sinais de exclusão: só uma dimensão varia; composição simples basta.
- Custo estrutural: alto. Barra alta (DP-GATE-005).
- Alternativa direta: Strategy numa das dimensões.
- Forma enxuta: a abstração recebe a implementação por composição (`Report` com um `Renderer`).
- Testar: cada abstração com cada implementação relevante; nova implementação sem tocar a abstração.

## DP-EST-003 Composite

[Refactoring.Guru](https://refactoring.guru/design-patterns/composite)

- Intenção: tratar itens individuais e árvores de itens pela mesma interface.
- Sinais fortes: `recursive_tree_structure` e `uniform_component_contract`; operações recursivas.
- Sinais de exclusão: coleção plana; estrutura não recursiva.
- Custo estrutural: médio.
- Alternativa direta: função recursiva sobre o tipo existente.
- Forma enxuta: interface mínima (`size()`, `render()`) implementada por folha e nó.
- Testar: folha isolada; árvore aninhada; árvore vazia; profundidade que não estoura a pilha no uso real.

## DP-EST-004 Decorator

[Refactoring.Guru](https://refactoring.guru/design-patterns/decorator)

- Intenção: somar responsabilidades a um objeto em tempo de execução mantendo a interface.
- Sinais fortes: `add_responsibilities_dynamically`; combinações opcionais (log, retry, métrica) que explodiriam em subclasses.
- Sinais de exclusão: o objetivo é controlar acesso, carga tardia ou fronteira remota (Proxy); uma única variação fixa.
- Custo estrutural: médio. Penalizado em `performance_hot_path` com muitas camadas.
- Alternativa direta: middleware ou função que envolve função (`withRetry(fn)`).
- Forma enxuta: tipo que implementa a mesma interface e delega ao envolvido.
- Testar: cada camada isolada; ordem de composição relevante; erro do envolvido propagado sem ser engolido.

## DP-EST-005 Facade

[Refactoring.Guru](https://refactoring.guru/design-patterns/facade)

- Intenção: oferecer uma interface simples para um subsistema complexo.
- Sinais fortes: `subsystem_too_complex`; a mesma sequência de passos repetida em vários chamadores.
- Sinais de exclusão: só é preciso adaptar contrato; o cliente precisa da granularidade completa.
- Custo estrutural: baixo.
- Alternativa direta: extrair a sequência repetida para uma função.
- Forma enxuta: módulo com poucas operações de alto nível que orquestram o subsistema, sem esconder erros.
- Testar: fluxo feliz de cada operação; falha em cada passo do subsistema devolvida com contexto.

## DP-EST-006 Flyweight

[Refactoring.Guru](https://refactoring.guru/design-patterns/flyweight)

- Intenção: compartilhar estado intrínseco entre muitos objetos semelhantes para economizar memória.
- Sinais fortes: `high_memory_duplication` com `memory_pressure` medida (profiling, métrica de heap).
- Sinais de exclusão: poucos objetos; nenhuma medição de memória; separar estado intrínseco e extrínseco confunde o modelo.
- Custo estrutural: alto. Barra alta (DP-GATE-005).
- Alternativa direta: interning de valores imutáveis ou reduzir o tamanho do objeto.
- Forma enxuta: cache de instâncias imutáveis indexado pela chave do estado intrínseco.
- Testar: mesma chave devolve a mesma instância; instância compartilhada é imutável; medição antes e depois.

## DP-EST-007 Proxy

[Refactoring.Guru](https://refactoring.guru/design-patterns/proxy)

- Intenção: controlar o acesso a um objeto mantendo a mesma interface.
- Sinais fortes: `access_control_or_lazy_loading`; `remote_boundary`; cache, autorização ou limite de taxa diante de um recurso caro.
- Sinais de exclusão: extensão funcional arbitrária ou empilhável (Decorator).
- Custo estrutural: médio.
- Alternativa direta: cache ou verificação no próprio chamador, quando há um único chamador.
- Forma enxuta: tipo que implementa a interface, decide o acesso e delega ao objeto real.
- Testar: acerto e falta de cache; acesso negado; objeto real não criado antes do primeiro uso; invalidação.
