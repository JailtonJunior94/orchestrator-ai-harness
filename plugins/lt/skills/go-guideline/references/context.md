# Context em Go

<!-- TL;DR
context.Context é o primeiro parâmetro, nunca campo de struct, todo WithCancel/WithTimeout tem cancel em defer, I/O bloqueante respeita ctx.Done, context.WithoutCancel para trabalho que sobrevive à requisição e values só para dados de escopo de requisição.
Keywords: context.Context, ctx, WithCancel, WithTimeout, WithDeadline, WithoutCancel, ctx.Done, ctx.Err, context.Value
Load complete when: a mudança recebe ou propaga context, define timeout ou cancelamento, ou guarda valor em context.
-->

- Escopo: todo código Go que faz I/O, chama rede ou banco, ou atravessa fronteira de requisição.
- Fonte: o Uber não tem seção sobre context. As regras abaixo vêm da documentação do pacote
  [`context`](https://pkg.go.dev/context) e do Go Code Review Comments.

## GO-CTX-001 Primeiro parâmetro, nunca campo

`context.Context` é o primeiro parâmetro da função e se chama `ctx`:
`func (s *Store) Get(ctx context.Context, id string) (User, error)`.

A documentação do pacote proíbe guardar context dentro de struct. Ele é passado explicitamente a
cada chamada.

## GO-CTX-002 Nunca passar nil

Não passe `nil` como context. Sem context disponível, use `context.TODO()` enquanto a assinatura
não é corrigida. `context.Background()` só existe na raiz: `main`, inicialização e testes.

## GO-CTX-003 Cancelar sempre

Todo `WithCancel`, `WithTimeout` e `WithDeadline` devolve um `cancel`. Chame-o com `defer` logo em
seguida, ou os recursos do context ficam presos até o pai ser cancelado. `go vet` (analisador
`lostcancel`) aponta o esquecimento.

```go
ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
defer cancel()
```

## GO-CTX-004 Respeitar o cancelamento

- Loop longo e espera bloqueante incluem `case <-ctx.Done(): return ctx.Err()` no `select`.
- Chamadas de rede e banco usam a variante que recebe context (`http.NewRequestWithContext`,
  `db.QueryContext`).
- A causa do cancelamento, quando existir, sai por `context.Cause(ctx)` (Go 1.20 ou superior).

## GO-CTX-005 Trabalho que sobrevive à requisição

Trabalho que precisa continuar depois do fim da requisição (auditoria, envio assíncrono) não deve
herdar o cancelamento dela.

- Go 1.21 ou superior: use `context.WithoutCancel(ctx)`. Ele mantém os values e descarta o
  cancelamento.
- A goroutine que recebe esse context continua sujeita a GO-CONC-001: precisa ter dono e parada.

## GO-CTX-006 Values só para escopo de requisição

- `context.WithValue` carrega só dado de escopo de requisição que atravessa APIs: trace ID, identidade autenticada.
- Nunca carrega parâmetro opcional de função nem dependência.
- A chave é um tipo não exportado do próprio pacote, para não colidir com a de outro pacote:

```go
type ctxKey struct{}

func WithRequestID(ctx context.Context, id string) context.Context {
	return context.WithValue(ctx, ctxKey{}, id)
}

func RequestID(ctx context.Context) (string, bool) {
	id, ok := ctx.Value(ctxKey{}).(string)
	return id, ok
}
```
