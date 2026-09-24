# Estilo em Go

<!-- TL;DR
Consistência no pacote, nomes de pacote curtos e no singular, dois grupos de import, ordem de funções por chamada e receiver, menos aninhamento, declarações com var ou :=, nil como slice vazio, escopo mínimo, tipos nomeados no lugar de bool nu, inicialização de struct e map, sem estado global mutável, init só em casos aceitos, sem sombrear nomes built-in, linha de até 99 caracteres.
Keywords: package, import, alias, naming, MixedCaps, nesting, else, var, :=, nil slice, struct literal, make, map literal, init, global, built-in, Printf
Load complete when: a mudança cria pacote, arquivo, função ou declaração, ou reorganiza código existente.
-->

- Escopo: legibilidade e organização de todo código Go.
- Fonte: Uber, seções "Style", "Avoid Mutable Globals", "Avoid Using Built-In Names" e "Avoid init()".

## Sumário

- GO-STY-001 Consistência
- GO-STY-002 Pacotes e nomes
- GO-STY-003 Imports
- GO-STY-004 Agrupamento e ordem
- GO-STY-005 Aninhamento
- GO-STY-006 Declarações
- GO-STY-007 Slices nil
- GO-STY-008 Escopo
- GO-STY-009 Parâmetros nus
- GO-STY-010 Inicialização de struct e map
- GO-STY-011 Strings
- GO-STY-012 Estado global e `init()`
- GO-STY-013 Nomes built-in
- GO-STY-014 Comprimento de linha

## GO-STY-001 Consistência

Uber:
- Acima de tudo, seja consistente. Estilo misturado custa manutenção, revisão e bug.
- Mudança de estilo é aplicada no pacote inteiro ou em nada.
- Na mudança pontual, siga o estilo do arquivo tocado e aponte a divergência no relatório.

## GO-STY-002 Pacotes e nomes

Uber, nome de pacote:
- tudo minúsculo, sem maiúscula nem underline;
- curto, porque aparece inteiro em cada chamada;
- no singular: `net/url`, não `net/urls`;
- sem precisar de alias na maior parte dos imports;
- nunca `common`, `util`, `shared` nem `lib`.

Uber, nome de função: MixedCaps. Função de teste pode usar underline para agrupar casos:
`TestMyFunction_WhatIsBeingTested`.

Exceção deste harness: o Uber pede o prefixo `_` em `var` e `const` não exportados de nível de
pacote. Aqui o prefixo é proibido (`R-STYLE-001.3`). Use nome específico o bastante para não colidir
com variável local: `defaultPort`, e não `port`.

Uber: erro global continua com `Err` e `err`, e tipo de erro com o sufixo `Error` (ver `errors.md`).

## GO-STY-003 Imports

Uber:
- São dois grupos, separados por linha em branco: a stdlib e todo o resto. É o que o `goimports` faz por padrão.
- Use alias só quando o nome do pacote difere do último elemento do caminho (`client "example.com/client-go"`, `trace "example.com/trace/v2"`) ou quando dois imports colidem.
- Na colisão, aplique o alias ao pacote menos usado e mantenha o nome original no outro.

## GO-STY-004 Agrupamento e ordem

Uber:
- Agrupe `import`, `const`, `var` e `type` relacionados num bloco `( )`, e só os relacionados. Uma constante sem relação com o enum fica fora do bloco dele.
- Dentro de função, variáveis declaradas lado a lado ficam num único `var ( )`, mesmo sem relação entre si.
- Ordem das funções no arquivo:
  - aproximadamente na ordem de chamada, agrupadas por receiver;
  - exportadas primeiro, depois de `type`, `const` e `var`;
  - o construtor (`NewX` ou `newX`) logo depois do tipo, antes dos demais métodos;
  - funções utilitárias soltas no fim do arquivo.

## GO-STY-005 Aninhamento

Uber:
- Trate primeiro o erro e o caso especial, e saia cedo com `return` ou `continue`. O caminho feliz fica no nível mais raso.
- Se as duas pontas de um `if` só atribuem a mesma variável, atribua o padrão antes e use um `if` só:

```go
a := 10
if b {
	a = 100
}
```

## GO-STY-006 Declarações

Uber:
- No nível de pacote, use `var` sem tipo quando o tipo da expressão já é o desejado: `var defaultTimeout = 5 * time.Second`.
- Declare o tipo só quando ele difere do tipo da expressão, como `var e error = F()` com `F` devolvendo um tipo concreto.
- Dentro de função, use `:=` quando atribui um valor explícito e `var` quando o valor zero é a intenção: `var filtered []int`.

## GO-STY-007 Slices nil

Uber:
- `nil` é um slice válido de tamanho zero. Devolva `nil`, e não `[]int{}`.
- Teste vazio com `len(s) == 0`, nunca com `s == nil`.
- Slice declarado com `var` já aceita `append` sem `make`.

Atenção: slice nil e slice vazio alocado não são iguais em todo contexto. Em JSON, o nil vira
`null` e o vazio vira `[]`. Quando o contrato exige `[]`, inicialize explicitamente.

## GO-STY-008 Escopo

Uber:
- Reduza o escopo sempre que possível, por exemplo com `if err := f(); err != nil { ... }`.
- A exceção é quando isso conflita com GO-STY-005: se o resultado é usado depois do `if`, declare fora.
- Constante só vira global se é usada por várias funções ou arquivos, ou se faz parte do contrato externo do pacote.

## GO-STY-009 Parâmetros nus

Uber: `printInfo("foo", true, true)` não diz o que cada `true` significa. O Uber aceita comentário
`/* isLocal */` no argumento, mas recomenda como opção melhor um tipo nomeado. Aqui só vale o tipo
nomeado, porque `R-STYLE-001.2` proíbe comentário no código produzido.

```go
type Region int

const (
	UnknownRegion Region = iota
	Local
)

type Status int

const (
	StatusReady Status = iota + 1
	StatusDone
)

func printInfo(name string, region Region, status Status)
```

## GO-STY-010 Inicialização de struct e map

Uber, struct:
- Inicialize com nome de campo (`User{FirstName: "John"}`). `go vet` cobra. Tabela de teste com três campos ou menos pode omitir os nomes.
- Omita campo com valor zero, a não ser que o nome dê contexto útil, como nas tabelas de teste.
- Struct com todos os campos zerados é declarada com `var user User`, não `user := User{}`.
- Referência de struct é `&T{Name: "bar"}`, não `new(T)` seguido de atribuições.

Uber, map:
- Map vazio ou preenchido por código usa `make(map[K]V, n)`, com a dica de tamanho quando conhecida.
- Map com um conjunto fixo de elementos usa literal.

## GO-STY-011 Strings

Uber:
- Use raw string (crases) para evitar escape manual: ``wantError := `unknown error:"test"` ``.
- String de formato declarada fora da chamada `Printf` é `const`. Assim o `go vet` consegue checar os argumentos.
- Função no estilo `Printf` usa nome já conhecido pelo vet ou termina em `f` (`Wrapf`, não `Wrap`). Assim o vet valida as chamadas dela.

## GO-STY-012 Estado global e `init()`

Uber, estado global mutável:
- Evite. Dependência, inclusive ponteiro de função como `var timeNow = time.Now`, entra por injeção.
- Guarde a dependência num campo da struct e passe no construtor.

```go
type signer struct {
	now func() time.Time
}

func newSigner() *signer {
	return &signer{now: time.Now}
}
```

Uber, `init()`: evite. Quando for inevitável, ele precisa:

1. ser totalmente determinístico, independente do ambiente e da invocação;
2. não depender da ordem nem dos efeitos de outros `init()`;
3. não ler nem alterar estado global ou de ambiente: variável de ambiente, diretório de trabalho, argumentos;
4. não fazer I/O de arquivo, rede ou chamada de sistema.

Casos em que o Uber aceita `init()`:
- expressão complexa que não cabe numa atribuição simples;
- registro plugável, como dialeto de `database/sql`;
- pré-cálculo determinístico.

Quem não cumpre esses requisitos vira função chamada no `main()`. Biblioteca nunca faz "mágica de
init".

## GO-STY-013 Nomes built-in

Uber: não use identificador predeclarado como nome: `error`, `string`, `len`, `cap`, `new`,
`copy`, `min`, `max`. Ele sombreia o original no escopo. Mesmo como campo de struct, onde não chega
a sombrear, `error error` torna a busca no código ambígua. O `go vet` e os linters apontam o
sombreamento.

## GO-STY-014 Comprimento de linha

Uber: limite suave de 99 caracteres. Quebre a linha antes disso quando for natural. O limite não
é duro.
