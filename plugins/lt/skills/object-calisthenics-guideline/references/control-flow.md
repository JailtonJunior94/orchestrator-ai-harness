# Fluxo de controle

<!-- TL;DR
Regra 1 (um nível de indentação por método) e regra 2 (sem else): enunciado de Bay, sinais, custo, refatoração do catálogo de Fowler, quando não aplicar e exemplo mínimo.
Keywords: indentação, aninhamento, nested if, loop dentro de loop, else, else if, switch, status, guard clause, early return, Extract Function, Null Object, polimorfismo
Load complete when: o código tem controle aninhado, cadeia de if/else ou switch por status ou tipo.
-->

- Escopo: estrutura de controle dentro de um método ou função.
- Fonte: ensaio de Jeff Bay (regras 1 e 2); refatorações do [catálogo de Fowler](https://refactoring.com/catalog/).

## Sumário

- OC-1 Um nível de indentação por método
- OC-2 Não use `else`

## OC-1 Um nível de indentação por método

Bay:
- Cada método faz exatamente uma coisa: uma estrutura de controle ou um bloco de instruções.
  Controle aninhado indica que o método trabalha em mais de um nível de abstração.
- A ferramenta é extrair método até sobrar um nível. O exemplo original quebra um `for` dentro de
  `for` em `collectRows` e `collectRow`.
- As primeiras tentativas parecem estranhas e dão pouco ganho percebido. O ganho vem com a prática.

Prática:
- As ferramentas divergem sobre o que conta como um nível: umas aceitam só o corpo do método, outras
  aceitam um `if` ou um laço, mas não os dois aninhados ([Code Cop](https://blog.code-cop.org/2018/01/compliance-with-object-calisthenics.html)).

Sinais:
- Laço dentro de laço, `if` dentro de laço, `if` dentro de `if`, `try` envolvendo lógica com ramos.
- Método cujo nome não descreve tudo o que o corpo faz.

Custo que vira achado em `produção`:
- Um nível interno repete lógica que já existe em outro método, ou é testado só por meio do externo.
- Bug ou mudança recente concentrado no bloco aninhado.
- Aninhamento de 3 ou mais níveis. Com 2 níveis e corpo curto, é sinal, não achado.

Refatoração: Extract Function; Replace Nested Conditional with Guard Clauses; Decompose Conditional.

Quando não aplicar:
- Laço aninhado curto sobre estrutura bidimensional em caminho quente, onde a extração atrapalha
  a leitura do algoritmo. Declarar a escolha.
- Linguagem cujo idioma já resolve o caso (compreensão, `map`/`filter`, `for ... range` com `continue`).

Exemplo:

```ts
function totalOverdue(invoices: Invoice[], today: Date): number {
  let total = 0;
  for (const invoice of invoices) {
    if (invoice.dueDate < today) {
      if (!invoice.paid) {
        total += invoice.amount;
      }
    }
  }
  return total;
}
```

```ts
function totalOverdue(invoices: Invoice[], today: Date): number {
  return invoices
    .filter((invoice) => invoice.isOverdue(today))
    .reduce((total, invoice) => total + invoice.amount, 0);
}
```

A cadeia de `filter` e `reduce` é fluent interface sobre a mesma coleção e não conta contra a OC-5.

## OC-2 Não use `else`

Bay:
- Condicional é fonte frequente de duplicação, e é fácil demais somar mais um ramo em vez de
  fatorar. Flag de status é o exemplo clássico.
- Polimorfismo trata condicional complexa com mais clareza. Null Object ajuda em alguns casos. O
  ensaio pede para achar o máximo de alternativas ao `else`.

Prática:
- Early return e programação defensiva resolvem a maioria dos casos; State e Strategy resolvem o
  condicional que escolhe comportamento ([William Durand](https://williamdurand.fr/2013/06/03/object-calisthenics/)).
- Introduzir polimorfismo cedo demais complica o código ([Stakater](https://developerhandbook.stakater.com/architecture/object-calisthenics.html)).

Sinais:
- `else` depois de um ramo que já retorna, lança ou sai do laço.
- `if`/`else if` ou `switch` sobre status, tipo ou flag repetido em mais de um método.
- Checagem de nulo repetida antes de chamar o mesmo objeto.

Custo que vira achado em `produção`:
- `else` redundante depois de `return`: custo de leitura baixo, correção trivial. Achado de baixa prioridade.
- O mesmo `switch` por tipo em 2 ou mais lugares: cada caso novo exige mudar todos. Achado de alta
  prioridade, e a escolha entre State e Strategy vai para `lt:design-patterns`.
- Checagem de nulo espalhada: candidata a Introduce Special Case (Null Object).

Refatoração: Replace Nested Conditional with Guard Clauses; Replace Conditional with Polymorphism;
Introduce Special Case.

Quando não aplicar:
- `if`/`else` de dois ramos simétricos que atribuem ou retornam valores equivalentes. A forma com
  `else` ou o ternário é a mais legível.
- Uma única ocorrência de condicional por tipo, sem pressão de novos casos. Polimorfismo ali é
  estrutura sem ganho.

Exemplo:

```java
double discount(Customer customer) {
    if (customer.isEmployee()) {
        return 0.2;
    } else {
        if (customer.isLoyal()) {
            return 0.1;
        } else {
            return 0;
        }
    }
}
```

```java
double discount(Customer customer) {
    if (customer.isEmployee()) {
        return 0.2;
    }
    if (customer.isLoyal()) {
        return 0.1;
    }
    return 0;
}
```
