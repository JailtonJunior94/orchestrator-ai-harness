# Encapsulamento

<!-- TL;DR
Regras 3 (encapsular primitivos e strings), 4 (coleção de primeira classe), 8 (no máximo duas variáveis de instância) e 9 (sem getters, setters e properties): enunciado de Bay, sinais, custo, refatoração, isenções e exemplo mínimo.
Keywords: primitive obsession, value object, string, int, money, email, lista, coleção, filtro, campos, atributos, coesão, getter, setter, property, tell don't ask, DTO
Load complete when: o código valida o mesmo primitivo em vários lugares, expõe coleção, tem muitos campos ou é consultado por getters para decidir fora do objeto.
-->

- Escopo: estado de um objeto e como o resto do código chega a ele.
- Fonte: ensaio de Jeff Bay (regras 3, 4, 8 e 9); refatorações do [catálogo de Fowler](https://refactoring.com/catalog/).

## Sumário

- OC-3 Encapsule primitivos e strings
- OC-4 Coleção de primeira classe
- OC-8 No máximo duas variáveis de instância
- OC-9 Sem getters, setters e properties
- Isenções comuns

Bay: as regras 3 e 4 são isomórficas, e 7 das 9 regras são formas de enxergar e implementar
encapsulamento de dados.

## OC-3 Encapsule primitivos e strings

Bay:
- Um `int` sozinho é um escalar sem significado. Um parâmetro `Hour` diz o que o valor é, e o
  compilador impede passar um `Year` onde se espera `Hour`.
- Objetos pequenos como `Hour` ou `Money` dão um lugar óbvio para comportamento que estaria
  espalhado por outras classes.

Prática:
- Primitivo que tem comportamento deve ser encapsulado ([Stakater](https://developerhandbook.stakater.com/architecture/object-calisthenics.html)).
- Em JavaScript a regra costuma ser dispensada ([suissa](https://gist.github.com/suissa/79aa860161b13e50e5fa3a0120fb6d68)),
  e ferramentas a omitem por ser vaga demais para checar ([Code Cop](https://blog.code-cop.org/2018/01/compliance-with-object-calisthenics.html)).

Sinais:
- A mesma validação ou normalização do mesmo primitivo em 2 ou mais lugares (e-mail, CPF, moeda).
- Parâmetros vizinhos do mesmo tipo que podem ser trocados sem erro de compilação
  (`transfer(String from, String to)`, `schedule(int hour, int minute)`).
- Valor monetário em `double` ou `float`, ou quantia sem moeda.

Custo que vira achado em `produção`: validação duplicada, troca silenciosa de argumentos, regra de
arredondamento ou unidade reimplementada.

Refatoração: Replace Primitive with Object. Quando o tipo carrega regra de negócio, a modelagem vai
para `lt:domain-modeling`.

Quando não aplicar: valor só exibido ou repassado, sem regra; identificador opaco que nunca é
interpretado; métodos que o contrato da linguagem exige com primitivo (`equals`, `hashCode`).

```java
final class Email {
    private final String value;

    Email(String value) {
        if (value == null || !value.contains("@")) {
            throw new IllegalArgumentException("invalid email");
        }
        this.value = value.trim().toLowerCase();
    }

    boolean belongsTo(String domain) {
        return value.endsWith("@" + domain);
    }
}
```

## OC-4 Coleção de primeira classe

Bay:
- Toda classe que contém uma coleção não deve ter nenhuma outra variável de membro. O
  comportamento da coleção (filtro, junção de grupos, regra aplicada a cada item) ganha um lugar.

Sinais:
- O mesmo filtro, soma ou busca sobre a mesma coleção em 2 ou mais lugares.
- Coleção interna devolvida por referência mutável e alterada por quem chamou.
- Classe com uma lista e vários outros campos que só existem para operar sobre ela.

Custo que vira achado em `produção`: regra de agregação duplicada; invariante da coleção (sem
duplicata, limite de itens) quebrada por fora.

Refatoração: Encapsulate Collection; Extract Class; Combine Functions into Class.

Quando não aplicar: coleção local de um método; coleção em DTO; coleção sem nenhum comportamento
próprio.

## OC-8 No máximo duas variáveis de instância

Bay:
- A maioria das classes cuida de uma variável de estado; algumas precisam de duas. Cada variável
  nova reduz a coesão.
- Há dois tipos de classe: as que mantêm o estado de uma variável e as que coordenam duas. Não
  misture os dois papéis.
- O exemplo original decompõe `Name(first, middle, last)` em `Name(Surname, GivenNames)`, com
  `GivenNames` guardando uma lista.

Prática:
- É provavelmente a regra mais difícil ([Stakater](https://developerhandbook.stakater.com/architecture/object-calisthenics.html));
  o número 2 é arbitrário e há quem use 5 ([Code Cop](https://blog.code-cop.org/2018/01/compliance-with-object-calisthenics.html)).

Sinais:
- Grupos de campos que sempre mudam juntos ou sempre aparecem juntos em parâmetros.
- Métodos que usam só um subconjunto dos campos (coesão baixa).
- Campos com prefixo comum (`billingStreet`, `billingCity`, `billingZip`).

Custo que vira achado em `produção`: o grupo de campos tem regra própria duplicada; mudar um
conceito obriga a tocar métodos que não têm relação com ele.

Refatoração: Extract Class; Introduce Parameter Object; Replace Primitive with Object.

Harness: em `produção`, a contagem de campos nunca é achado sozinha. O achado é o grupo coeso de
campos que já tem comportamento próprio.

## OC-9 Sem getters, setters e properties

Bay:
- O comportamento não segue a variável se qualquer um pode pedir o valor onde ele está. Fronteiras
  fortes forçam quem vem depois a procurar e colocar o comportamento num lugar só.
- Outra forma de dizer a regra: "Tell, don't ask".

Prática:
- DTO é apropriado e útil para transferir dados entre fronteiras ([Stakater](https://developerhandbook.stakater.com/architecture/object-calisthenics.html)).
- No estilo funcional, lentes cumprem o papel de acesso sem expor estado mutável ([suissa](https://gist.github.com/suissa/79aa860161b13e50e5fa3a0120fb6d68)).

Sinais:
- Código fora do objeto lê dois ou mais getters dele para tomar uma decisão sobre ele.
- Setter público que permite deixar o objeto em estado inválido.
- Getter que devolve coleção interna mutável.

Custo que vira achado em `produção`: a mesma decisão reimplementada por vários clientes; invariante
que só vale se todo cliente lembrar de validar.

Refatoração: Move Function (levar a decisão para o dono do dado); Remove Setting Method; Encapsulate
Collection.

```java
if (account.getBalance() >= amount && !account.isBlocked()) {
    account.setBalance(account.getBalance() - amount);
}
```

```java
account.withdraw(amount);
```

## Isenções comuns

Nas regras 3, 8 e 9, em modo `produção`:
- DTO, request, response, evento e mensagem que cruzam fronteira de processo.
- Mapeamento de ORM exigido pelo framework, desde que a regra de negócio fique fora dele.
- Configuração carregada de arquivo ou ambiente.
- Código de teste e builders de fixture.
- Record, data class ou struct imutável sem comportamento, usados como valor.
