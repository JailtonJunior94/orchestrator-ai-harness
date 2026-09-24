# Concorrência em Go

<!-- TL;DR
Toda goroutine tem parada previsível e alguém que espera o fim dela, sem goroutine em init, canal com buffer 0 ou 1, mutex como valor e não embutido, atomic tipado, errgroup para grupo com erro, goleak e -race nos testes.
Keywords: goroutine, go func, sync.WaitGroup, wg.Go, errgroup, chan, select, sync.Mutex, atomic, goleak, Close, Shutdown
Load complete when: a mudança dispara goroutine, cria canal, usa mutex ou atomic, ou define worker de fundo.
-->

- Escopo: todo código Go com goroutine, canal, lock ou operação atômica.
- Fonte: Uber, seções "Don't fire-and-forget goroutines", "Channel Size is One or None",
  "Zero-value Mutexes are Valid" e "Use go.uber.org/atomic". Os itens sobre errgroup vêm da
  documentação de `golang.org/x/sync/errgroup`.

## Sumário

- GO-CONC-001 Sem goroutine solta
- GO-CONC-002 Esperar a goroutine terminar
- GO-CONC-003 Worker de fundo é um objeto
- GO-CONC-004 Canal com buffer 0 ou 1
- GO-CONC-005 Mutex como valor
- GO-CONC-006 Operação atômica tipada
- GO-CONC-007 Grupo de goroutines com erro
- GO-CONC-008 Verificação

## GO-CONC-001 Sem goroutine solta

Uber: goroutine custa memória e escalonamento, e goroutine sem dono segura objetos que o coletor
de lixo não consegue liberar. Toda goroutine precisa de uma das duas coisas:

- um momento previsível em que para;
- um sinal que manda ela parar.

Nos dois casos, o código precisa conseguir **bloquear até ela terminar**.

Ruim, porque nada para este loop:

```go
go func() {
	for {
		flush()
		time.Sleep(delay)
	}
}()
```

Bom:

```go
stop := make(chan struct{})
done := make(chan struct{})
go func() {
	defer close(done)
	ticker := time.NewTicker(delay)
	defer ticker.Stop()
	for {
		select {
		case <-ticker.C:
			flush()
		case <-stop:
			return
		}
	}
}()

close(stop)
<-done
```

Quando o chamador já tem um `context.Context`, `case <-ctx.Done():` faz o papel do `stop`.

## GO-CONC-002 Esperar a goroutine terminar

Uber:
- Várias goroutines: `sync.WaitGroup`.
- Uma goroutine só: um canal `done` que ela fecha ao sair.

Com Go 1.25 ou superior, `wg.Go(f)` substitui o par `wg.Add(1)` e `defer wg.Done()`:

```go
var wg sync.WaitGroup
for _, item := range items {
	wg.Go(func() {
		process(item)
	})
}
wg.Wait()
```

Abaixo do Go 1.25, use `wg.Add(1)` antes do `go` e `defer wg.Done()` dentro da goroutine.

## GO-CONC-003 Worker de fundo é um objeto

Uber:
- `init()` não dispara goroutine.
- Pacote que precisa de trabalho em segundo plano expõe um objeto que dispara a goroutine só quando
  é pedido.
- O objeto tem um método (`Close`, `Stop` ou `Shutdown`) que sinaliza a parada **e espera** o fim.

```go
type Worker struct {
	interval time.Duration
	flush    func()
	stop     chan struct{}
	done     chan struct{}
}

func NewWorker(interval time.Duration, flush func()) *Worker {
	w := &Worker{
		interval: interval,
		flush:    flush,
		stop:     make(chan struct{}),
		done:     make(chan struct{}),
	}
	go w.run()
	return w
}

func (w *Worker) run() {
	defer close(w.done)
	ticker := time.NewTicker(w.interval)
	defer ticker.Stop()
	for {
		select {
		case <-ticker.C:
			w.flush()
		case <-w.stop:
			return
		}
	}
}

func (w *Worker) Shutdown() {
	close(w.stop)
	<-w.done
}
```

Se o worker gerencia várias goroutines, use `sync.WaitGroup` no lugar do canal `done`.

## GO-CONC-004 Canal com buffer 0 ou 1

Uber: canal é sem buffer ou tem buffer 1. Qualquer outro tamanho exige resposta explícita a três
perguntas:

- De onde vem esse número?
- O que impede o canal de encher sob carga?
- O que acontece com quem escreve quando ele enche?

`make(chan int, 64)` sem essa justificativa é defeito de revisão.

## GO-CONC-005 Mutex como valor

Uber:
- O valor zero de `sync.Mutex` e `sync.RWMutex` já é válido. Ponteiro para mutex é desnecessário.
- Não embuta o mutex, nem em struct não exportada: embutir expõe `Lock` e `Unlock` na API do tipo.

```go
type SMap struct {
	mu   sync.Mutex
	data map[string]string
}

func (m *SMap) Get(k string) string {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.data[k]
}
```

Uber, "Defer to Clean Up": use `defer` para liberar lock e fechar recurso. O custo do `defer` é
desprezível, a não ser em função comprovadamente medida em nanossegundos.

## GO-CONC-006 Operação atômica tipada

O Uber recomenda `go.uber.org/atomic` porque as funções de `sync/atomic` sobre tipos crus (`int32`,
`int64`) deixam fácil ler a variável sem a operação atômica.

Exceção deste harness: com Go 1.19 ou superior, use os tipos de `sync/atomic` (`atomic.Bool`,
`atomic.Int64`, `atomic.Pointer[T]`), que dão a mesma segurança de tipo sem dependência externa.
Abaixo do Go 1.19, vale o Uber.

```go
type foo struct {
	running atomic.Bool
}

func (f *foo) start() {
	if f.running.Swap(true) {
		return
	}
}

func (f *foo) isRunning() bool {
	return f.running.Load()
}
```

## GO-CONC-007 Grupo de goroutines com erro

Lacuna do Uber, coberta pela documentação de `errgroup`: quando várias goroutines podem falhar e a
primeira falha deve cancelar as outras, use `golang.org/x/sync/errgroup`.

```go
g, ctx := errgroup.WithContext(ctx)
for _, url := range urls {
	g.Go(func() error {
		return fetch(ctx, url)
	})
}
if err := g.Wait(); err != nil {
	return fmt.Errorf("fetch all: %w", err)
}
```

`g.SetLimit(n)` limita quantas goroutines rodam ao mesmo tempo. Use sempre que a entrada puder
crescer sem limite.

## GO-CONC-008 Verificação

- Uber: pacote que dispara goroutine testa vazamento com `go.uber.org/goleak`
  (`goleak.VerifyTestMain(m)` ou `defer goleak.VerifyNone(t)`).
- Rode `go test -race ./...` em todo pacote com concorrência. Teste concorrente que passa sem `-race`
  não prova nada.
