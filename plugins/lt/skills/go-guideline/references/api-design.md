# Desenho de API em Go

<!-- TL;DR
Sem ponteiro para interface, conformidade verificada em compilação, sem embutir tipo em struct pública, functional options no formato interface do Uber, cópia de slice e map na fronteira, tag em campo serializado, time.Time e time.Duration, enums começando em 1 e generics só com mais de um tipo concreto.
Keywords: interface, var _, embedding, Option, apply, WithX, copy, make, json tag, time.Duration, iota, generics, constraint
Load complete when: a mudança cria ou altera tipo exportado, interface, construtor, enum, struct serializada ou função genérica.
-->

- Escopo: tipos, interfaces, construtores e assinaturas públicas de pacotes Go.
- Fonte: Uber, seções "Pointers to Interfaces", "Verify Interface Compliance", "Receivers and
  Interfaces", "Avoid Embedding Types in Public Structs", "Embedding in Structs", "Functional
  Options", "Copy Slices and Maps at Boundaries", "Use field tags in marshaled structs", "Use time
  to handle time" e "Start Enums at One". A seção de generics vem da documentação oficial do Go.

## Sumário

- GO-API-001 Sem ponteiro para interface
- GO-API-002 Conformidade em compilação
- GO-API-003 Receivers
- GO-API-004 Embedding
- GO-API-005 Functional options
- GO-API-006 Cópia na fronteira
- GO-API-007 Tags em struct serializada
- GO-API-008 Tempo
- GO-API-009 Enums
- GO-API-010 Generics

## GO-API-001 Sem ponteiro para interface

Uber: passe interface por valor, porque o dado por trás dela já pode ser um ponteiro. `*io.Reader`
quase nunca é o que se quer. Para que os métodos alterem o dado, quem implementa a interface é que
deve ser um ponteiro.

## GO-API-002 Conformidade em compilação

Uber: verifique em tempo de compilação, onde fizer sentido, que o tipo implementa a interface. Vale
para tipo exportado cujo contrato exige a interface, para tipos de uma mesma família de
implementações e para casos em que quebrar a interface quebraria quem usa.

```go
var _ http.Handler = (*Handler)(nil)
var _ http.Handler = LogHandler{}
```

O lado direito é o valor zero do tipo verificado: `nil` para ponteiro, slice e map; struct vazia
para struct.

## GO-API-003 Receivers

Uber: método com receiver de valor pode ser chamado em valor e em ponteiro. Método com receiver de
ponteiro só pode ser chamado em ponteiro ou em valor endereçável. Por isso um valor guardado em
map não aceita método de ponteiro. A mesma regra decide se o valor ou só o ponteiro satisfazem a
interface.

Complemento da documentação oficial (Go Code Review Comments): não misture os dois tipos de
receiver no mesmo tipo sem motivo. Se algum método precisa de ponteiro, ou se o tipo contém
`sync.Mutex`, use ponteiro em todos.

## GO-API-004 Embedding

Uber, em struct **pública**: não embuta tipos. O embutido vaza detalhe de implementação e trava a
evolução do tipo, porque:

- adicionar método a uma interface embutida quebra quem usa;
- remover método de uma struct embutida quebra quem usa;
- remover ou trocar o tipo embutido quebra quem usa.

Escreva os métodos de delegação à mão:

```go
type ConcreteList struct {
	list *AbstractList
}

func (l *ConcreteList) Add(e Entity) {
	l.list.Add(e)
}
```

Uber, onde embutir é aceitável:
- O campo embutido fica no topo da struct, separado dos demais por uma linha em branco.
- Só embuta quando houver ganho real e tangível.
- O embutido não pode vazar detalhe interno.
- Não pode alterar o valor zero útil do tipo.
- Não pode expor função que não deveria existir no tipo externo.
- Nunca embuta `sync.Mutex`.

## GO-API-005 Functional options

Uber: use em construtores e APIs públicas que devem crescer, principalmente a partir de três
parâmetros. O formato recomendado é uma interface `Option` com método não exportado gravando numa
struct `options` não exportada. O Uber prefere esse formato ao de closures porque as opções ficam
comparáveis em teste e podem implementar `fmt.Stringer`.

```go
type options struct {
	cache  bool
	logger *slog.Logger
}

type Option interface {
	apply(*options)
}

type cacheOption bool

func (c cacheOption) apply(opts *options) {
	opts.cache = bool(c)
}

func WithCache(c bool) Option {
	return cacheOption(c)
}

type loggerOption struct {
	log *slog.Logger
}

func (l loggerOption) apply(opts *options) {
	opts.logger = l.log
}

func WithLogger(log *slog.Logger) Option {
	return loggerOption{log: log}
}

func Open(addr string, opts ...Option) (*Connection, error) {
	o := options{
		cache:  defaultCache,
		logger: slog.Default(),
	}
	for _, opt := range opts {
		opt.apply(&o)
	}
	return connect(addr, o)
}
```

Chamada: `db.Open(addr)`, ou `db.Open(addr, db.WithCache(false), db.WithLogger(log))`.

## GO-API-006 Cópia na fronteira

Uber: slice e map carregam ponteiro para o dado.

- **Ao receber** um slice ou map que o tipo vai guardar, copie. Senão, quem chamou continua podendo alterar o estado interno.
- **Ao devolver** o estado interno, devolva uma cópia. Isso vale principalmente para dado protegido por mutex, que deixaria de estar protegido do lado de fora.

```go
func (d *Driver) SetTrips(trips []Trip) {
	d.trips = make([]Trip, len(trips))
	copy(d.trips, trips)
}

func (s *Stats) Snapshot() map[string]int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return maps.Clone(s.counters)
}
```

`maps.Clone` e `slices.Clone` existem a partir do Go 1.21. Em versões anteriores, copie com `make`
e um laço, como no guia do Uber.

## GO-API-007 Tags em struct serializada

Uber: todo campo serializado em JSON, YAML ou outro formato com nome por tag recebe a tag. A forma
serializada é contrato com outro sistema, e a tag deixa esse contrato explícito, o que impede que
um renomeio de campo quebre o formato por acidente.

```go
type Stock struct {
	Price int    `json:"price"`
	Name  string `json:"name"`
}
```

## GO-API-008 Tempo

Uber:
- `time.Time` para instante, com os métodos dele para comparar e somar (`Before`, `After`, `Add`, `AddDate`).
- `time.Duration` para período: `poll(10 * time.Second)`, e não `poll(10)`.
- Na fronteira com outros sistemas (flags, JSON, SQL, YAML), prefira os mesmos tipos. `flag` aceita `time.Duration`, e `encoding/json` serializa `time.Time` em RFC 3339.
- Onde o formato não aceitar esses tipos, use inteiro com a unidade no nome do campo (`IntervalMillis`), ou string em RFC 3339 para instante.

## GO-API-009 Enums

Uber: comece a enumeração em 1 (`iota + 1`). Assim o valor zero da variável não vira um membro
válido por acidente.

```go
type Operation int

const (
	Add Operation = iota + 1
	Subtract
	Multiply
)
```

Exceção do próprio Uber: quando o valor zero é o comportamento padrão desejado, comece em zero
(`LogToStdout LogOutput = iota`).

## GO-API-010 Generics

O Uber não trata de generics. Regras da documentação oficial do Go ("When To Use Generics"):

- Use type parameter quando o **mesmo código** serve a vários tipos: contêineres, algoritmos sobre slices e maps, funções de canal.
- Se só um tipo concreto existe hoje, escreva a função para esse tipo.
- Se o comportamento muda por tipo, use interface com métodos, e não type parameter com `switch` de tipo.
- Prefira as constraints da stdlib (`comparable`, `cmp.Ordered`) e os pacotes `slices` e `maps` antes de escrever os seus.
