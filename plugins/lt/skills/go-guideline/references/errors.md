# Erros em Go

<!-- TL;DR
Escolha do tipo de erro pela necessidade de comparação, wrapping com %w ou %v, contexto curto sem "failed to", nomes Err e Error, tratar cada erro uma vez, sem panic em produção, comma-ok e saída só em main.
Keywords: errors.New, fmt.Errorf, %w, errors.Is, errors.As, sentinel, panic, recover, os.Exit, log.Fatal, run
Load complete when: a mudança cria, embrulha, compara, loga ou propaga erro, usa panic ou decide a saída do programa.
-->

- Escopo: todo código Go que cria, propaga, compara ou apresenta erro.
- Fonte: Uber, seções "Errors", "Handle Type Assertion Failures", "Don't Panic" e "Exit in Main".

## Sumário

- GO-ERR-001 Escolher o tipo de erro
- GO-ERR-002 Wrapping com `%w` ou `%v`
- GO-ERR-003 Contexto curto
- GO-ERR-004 Nomes de erro
- GO-ERR-005 Tratar uma vez
- GO-ERR-006 Asserção de tipo com comma-ok
- GO-ERR-007 Sem panic em produção
- GO-ERR-008 Saída só em `main`

## GO-ERR-001 Escolher o tipo de erro

Uber: a escolha depende de duas perguntas. O chamador precisa comparar o erro? A mensagem é fixa ou
dinâmica?

| Comparação? | Mensagem | Use |
|---|---|---|
| Não | fixa | `errors.New` |
| Não | dinâmica | `fmt.Errorf` |
| Sim | fixa | `var` de pacote com `errors.New` |
| Sim | dinâmica | tipo próprio que implementa `error` |

Exportar a variável ou o tipo de erro faz dele parte da API pública do pacote.

```go
var ErrCouldNotOpen = errors.New("could not open")

type NotFoundError struct {
	File string
}

func (e *NotFoundError) Error() string {
	return fmt.Sprintf("file %q not found", e.File)
}
```

Quem chama compara com `errors.Is(err, foo.ErrCouldNotOpen)` ou com
`var nf *NotFoundError; errors.As(err, &nf)`. Nunca compare pelo texto da mensagem.

## GO-ERR-002 Wrapping com `%w` ou `%v`

Uber: se uma chamada falhou, há três saídas.

1. Devolver o erro como veio, quando não há contexto útil a acrescentar.
2. `fmt.Errorf("...: %w", err)` quando o chamador deve conseguir inspecionar a causa. É o padrão
   para a maioria dos casos. Quando a causa embrulhada é um `var` ou tipo conhecido, ela vira
   contrato da função: documente no teste.
3. `fmt.Errorf("...: %v", err)` para esconder a causa. O chamador não consegue comparar, e ainda
   dá para trocar por `%w` depois sem quebrar ninguém.

## GO-ERR-003 Contexto curto

Uber: não use "failed to", "error while" ou equivalentes. Eles se acumulam a cada camada da pilha.

Ruim:

```go
s, err := store.New()
if err != nil {
	return fmt.Errorf("failed to create new store: %w", err)
}
```

Bom:

```go
s, err := store.New()
if err != nil {
	return fmt.Errorf("new store: %w", err)
}
```

A mensagem final fica `x: y: new store: the error`, e não
`failed to x: failed to y: failed to create new store: the error`. Quando o erro sai para outro
sistema (log, resposta de API), marque ali que é erro, por exemplo com o campo `err` no log.

## GO-ERR-004 Nomes de erro

Uber:
- Variável global de erro usa o prefixo `Err` quando exportada e `err` quando não exportada.
- Tipo de erro usa o sufixo `Error` (`NotFoundError`, `resolveError`).

## GO-ERR-005 Tratar uma vez

Uber: cada erro é tratado **uma única vez**. Formas válidas de tratar:

- comparar com `errors.Is` ou `errors.As` e seguir caminhos diferentes;
- logar e degradar, quando a operação não é essencial;
- devolver um erro de domínio bem definido;
- devolver o erro, embrulhado ou não.

Ruim, porque loga e retorna, e quem está acima vai logar de novo:

```go
u, err := getUser(id)
if err != nil {
	log.Printf("could not get user %q: %v", id, err)
	return err
}
```

Bom, porque embrulha e retorna:

```go
u, err := getUser(id)
if err != nil {
	return fmt.Errorf("get user %q: %w", id, err)
}
```

Bom, porque compara e degrada só no caso previsto no contrato:

```go
tz, err := getUserTimeZone(id)
if err != nil {
	if !errors.Is(err, ErrUserNotFound) {
		return fmt.Errorf("get user %q: %w", id, err)
	}
	tz = time.UTC
}
```

## GO-ERR-006 Asserção de tipo com comma-ok

Uber: a forma de retorno único (`t := i.(string)`) entra em panic se o tipo não bater. Use sempre
`t, ok := i.(string)` e trate `!ok`.

## GO-ERR-007 Sem panic em produção

Uber: panic é fonte de falha em cascata. A função devolve erro e o chamador decide.

- `panic` e `recover` não são estratégia de tratamento de erro.
- Panic só para o irrecuperável, como uma desreferência de nil.
- Exceção: falha na inicialização do programa, como `template.Must(...)` em variável de pacote.
- Em teste, use `t.Fatal` ou `t.FailNow`, nunca `panic`.

## GO-ERR-008 Saída só em `main`

Uber:
- `os.Exit` e `log.Fatal*` só aparecem em `main()`. As demais funções devolvem erro.
- Saída no meio do programa esconde o fluxo, impede teste e pula os `defer`.
- Chame a saída **uma vez**, com a lógica numa função que devolve erro:

```go
func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run() error {
	args := os.Args[1:]
	if len(args) != 1 {
		return errors.New("missing file")
	}
	data, err := os.ReadFile(args[0])
	if err != nil {
		return fmt.Errorf("read %s: %w", args[0], err)
	}
	return process(data)
}
```

O guia do Uber usa `os.Open` com `defer f.Close()` neste exemplo. Aqui o exemplo usa
`os.ReadFile`, porque o `errcheck` do próprio conjunto mínimo do Uber aponta o `Close` sem
checagem (ver `linting.md`).

Se o programa precisa de códigos de saída específicos, `run` pode devolver o código:
`os.Exit(run(os.Args[1:]))`.
