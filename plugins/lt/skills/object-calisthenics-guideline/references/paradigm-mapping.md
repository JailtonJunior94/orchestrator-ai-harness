# Mapeamento por linguagem e paradigma

<!-- TL;DR
Como cada regra se traduz em Go, TypeScript e JavaScript, Python, Java, Kotlin, C# e estilo funcional, e quais regras não se traduzem. Regra que não se traduz não é achado.
Keywords: Go, struct, receiver, getter, Effective Go, TypeScript, JavaScript, Python, property, dataclass, Java, record, Kotlin, data class, C#, funcional, lentes, parâmetros
Load complete when: a linguagem do código não é Java nem C#, ou o código usa record, data class, dataclass, property ou estilo funcional.
-->

- Escopo: tradução das 9 regras, escritas por Bay para Java, para outras linguagens.
- Fonte: documentação oficial de cada linguagem citada na seção; adaptação funcional de
  [suissa](https://gist.github.com/suissa/79aa860161b13e50e5fa3a0120fb6d68).

A skill de linguagem carregada para o diff vence esta tabela (ver precedência no `SKILL.md`).

## Go

- Sem classe: as regras 4, 7, 8 e 9 valem para `struct` e seus métodos; pacote substitui o pacote
  Java da regra 7.
- Regra 2: early return já é o idioma (`go-guideline`, GO-STY-005). `else` depois de `return` é
  achado de baixa prioridade.
- Regra 9: getter é aceito e se chama `Owner()`, não `GetOwner()`
  ([Effective Go, Getters](https://go.dev/doc/effective_go#Getters)). O achado é o cliente que
  decide pelo objeto, não a existência do método.
- Regra 6: nomes curtos para variável de escopo pequeno e receiver de uma ou duas letras são
  convenção ([Go Code Review Comments](https://go.dev/wiki/CodeReviewComments#variable-names)) e
  não contam como abreviação.
- Regra 2 com polimorfismo: interface pequena no lugar de hierarquia; não existe herança.

## TypeScript e JavaScript

- Regra 3: o ganho de segurança vem do tipo. Em TypeScript, tipo marcado (branded type) ou classe
  pequena; em JavaScript sem tipos, só vale com validação no construtor. O gist de suissa dispensa a
  regra em JavaScript.
- Regra 5: `array.filter(...).map(...)` e APIs fluentes não contam.
- Regra 9: campo privado (`#field` ou `private`) com método de comportamento; `readonly` para valor.
- Interface de tipo usada como DTO fica isenta das regras 3, 8 e 9.

## Python

- Regra 9: `@property` é o idioma de acesso; o achado é a decisão tomada fora do objeto.
- `@dataclass(frozen=True)` sem comportamento é valor, isento das regras 8 e 9.
- Regra 3: classe pequena com validação em `__post_init__` ou `NewType` para distinguir valores.

## Java

- Linguagem de origem do ensaio: as regras se aplicam como escritas.
- `record` (Java 16 ou superior) sem comportamento é valor ou DTO, isento das regras 8 e 9.

## Kotlin

- `data class` sem comportamento é valor ou DTO, isento das regras 8 e 9.
- Regra 2: `when` exaustivo sobre `sealed class` é a forma idiomática de polimorfismo fechado; não
  é achado.
- Regra 3: `value class` encapsula um primitivo sem alocação extra.

## C#

- Property é o idioma da linguagem; a regra 9 mira setter público que quebra invariante e decisão
  tomada fora do objeto, não a property somente leitura.
- `record` sem comportamento é valor ou DTO, isento das regras 8 e 9.

## Estilo funcional

A adaptação de suissa para JavaScript funcional troca três regras (adaptação do autor, não de Bay):

| Regra de Bay | Adaptação funcional |
|---|---|
| 4. Coleção de primeira classe | Funções de primeira classe |
| 7. Classes com menos de 50 linhas | Módulos com menos de 50 linhas |
| 8. Classe com no máximo duas variáveis de instância | Função com no máximo dois parâmetros |

- Regra 9: lentes dão acesso e atualização imutável sem expor a estrutura.
- Harness: em `produção`, "no máximo dois parâmetros" segue a mesma lógica da regra 8: a contagem
  é sinal; o achado é o grupo de parâmetros que sempre viaja junto (Introduce Parameter Object).
