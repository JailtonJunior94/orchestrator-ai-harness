# Acoplamento, nomes e tamanho

<!-- TL;DR
Regras 5 (um ponto por linha), 6 (não abreviar) e 7 (entidades pequenas): enunciado de Bay, sinais, custo, refatoração, exceções e exemplo mínimo.
Keywords: Law of Demeter, Lei de Deméter, cadeia de chamadas, train wreck, fluent interface, builder, abreviação, nome, 50 linhas, 10 arquivos, classe grande, god class, pacote
Load complete when: o código encadeia acesso a objetos internos, usa nome abreviado ou tem classe ou pacote grande.
-->

- Escopo: relação entre objetos, nomes e tamanho de classe e pacote.
- Fonte: ensaio de Jeff Bay (regras 5, 6 e 7); refatorações do [catálogo de Fowler](https://refactoring.com/catalog/).

## Sumário

- OC-5 Um ponto por linha
- OC-6 Não abrevie
- OC-7 Mantenha as entidades pequenas

## OC-5 Um ponto por linha

Bay:
- Mais de um ponto na linha indica atividade no lugar errado. Se os pontos ligam objetos
  diferentes, o objeto é um intermediário que sabe demais. Se os pontos descem por dentro de outro
  objeto, o encapsulamento foi violado: peça ao objeto que faça, em vez de mexer nas entranhas dele.
- A Lei de Deméter ("fale só com seus amigos") é o ponto de partida: você brinca com seus
  brinquedos, com os que você faz e com os que te dão, nunca com os brinquedos dos seus brinquedos.
- O próprio exemplo reconhece que o algoritmo fica mais difuso, em troca de um método com nome e
  responsabilidade coesos.

Prática:
- Fluent interface e builder são exceções aceitas ([William Durand](https://williamdurand.fr/2013/06/03/object-calisthenics/),
  [Stakater](https://developerhandbook.stakater.com/architecture/object-calisthenics.html)).
- O que conta é a dependência, não o caractere: a regra quer dizer Lei de Deméter
  ([Code Cop](https://blog.code-cop.org/2018/01/compliance-with-object-calisthenics.html)).

Sinais:
- `a.getB().getC().doSomething()` atravessando objetos de tipos diferentes.
- Método que navega a estrutura de um objeto recebido para ler um dado lá no fundo.

Custo que vira achado em `produção`: mudança na estrutura interna de `B` quebra quem chama `A`; a
mesma navegação repetida em vários pontos.

Refatoração: Hide Delegate; Move Function. Se `A` virar só repasse, Remove Middle Man.

Quando não aplicar: fluent interface e builder; `stream`, `filter`, `map` sobre a mesma coleção;
namespace ou pacote (`time.Now()`, `Math.max`); acesso a campo de DTO ou record.

```java
String city = order.getCustomer().getAddress().getCity();
```

```java
String city = order.shippingCity();
```

## OC-6 Não abrevie

Bay:
- Abreviação confunde e esconde problemas maiores. Se a vontade é abreviar porque o nome se repete
  muito, falta remover duplicação. Se o nome ficou longo, falta uma classe ou a responsabilidade
  está no lugar errado.
- Nomes de classe e método com 1 ou 2 palavras, sem repetir o contexto: em `Order`, o método é
  `ship()`, não `shipOrder()`.

Prática:
- Checar abreviação por dicionário falha com termos de domínio, e há ferramentas que não cobram a
  regra ([Code Cop](https://blog.code-cop.org/2018/01/compliance-with-object-calisthenics.html)).

Sinais: `mgr`, `ctx2`, `tmpVal`, `procOrd`; nome que repete o tipo que o contém; nome longo com `And`.

Custo que vira achado em `produção`: o nome esconde duas responsabilidades ou força quem lê a
abrir a implementação.

Refatoração: Rename Variable; Change Function Declaration; Extract Class quando o nome longo revela
duas responsabilidades.

Quando não aplicar: convenção da linguagem (índice `i`, receiver curto em Go); sigla consagrada do
domínio (`URL`, `ID`, `HTTP`, `CPF`); a skill de linguagem vence (ver precedência).

## OC-7 Mantenha as entidades pequenas

Bay:
- Nenhuma classe com mais de 50 linhas e nenhum pacote com mais de 10 arquivos.
- Classe com mais de 50 linhas costuma fazer mais de uma coisa, e 50 linhas cabem numa tela.
- Comportamentos que fazem sentido juntos vão para o mesmo pacote; pacote pequeno e coeso ganha
  identidade.
- O próprio ensaio admite que às vezes uma classe passa um pouco de 50 linhas.

Prática:
- Na prática se usa de 50 a 150 linhas por classe como faixa ([Stakater](https://developerhandbook.stakater.com/architecture/object-calisthenics.html),
  [William Durand](https://williamdurand.fr/2013/06/03/object-calisthenics/)).

Sinais: classe com grupos de métodos que não compartilham campos; muitos motivos diferentes para a
classe mudar; pacote que mistura conceitos sem relação.

Custo que vira achado em `produção`: mudanças sem relação colidem no mesmo arquivo; teste precisa
montar estado que o caso não usa.

Refatoração: Extract Class; Move Function; separar pacote por conceito.

Harness: em `produção`, contagem de linhas nunca é achado sozinha. O achado é a responsabilidade
misturada que a contagem ajudou a encontrar. Arquivo gerado por ferramenta fica fora.
