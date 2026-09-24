# Tradução para a Linguagem do Repositório

<!-- TL;DR
Como cada construção da notação vira código idiomático em Go, TypeScript, Python, Java, Kotlin e C#, com o limite de garantia de cada linguagem.
Keywords: tradução, go, typescript, python, java, kotlin, csharp, sealed, união discriminada, construtor, exaustivo
Load complete when: a etapa é traduzir o modelo para código ou revisar código de domínio existente.
-->

Regras para todo exemplo gerado: identificadores em inglês, nenhum comentário no código
(`R-STYLE-001`), versão da linguagem conferida no manifesto antes de usar recurso novo. Quando a
linguagem não garante algo em tempo de compilação, diga isso no modelo em vez de prometer.

## Mapa de construções

| Notação | Go | TypeScript | Python (3.11+) | Java (21+) | Kotlin | C# (10+) |
|---|---|---|---|---|---|---|
| Tipo restrito | struct com campo não exportado e `NewX(...) (X, error)` | branded type com `unique symbol` e função `createX` | `@dataclass(frozen=True)` que valida em `__post_init__` | `record` que valida no construtor compacto | `@JvmInline value class` com construtor privado e fábrica | `readonly record struct` com construtor privado e fábrica |
| AND | struct | `type` com `readonly` | `@dataclass(frozen=True)` | `record` | `data class` com `val` | `record` |
| OR | interface selada (método não exportado) + `switch` de tipo | união discriminada por `kind` | união de classes + `match` | `sealed interface` + `switch` com pattern | `sealed interface` + `when` | `abstract record` + `switch` com `_` que lança defeito |
| Exaustividade | Não verificada pelo compilador | `never` no `default` | `assert_never` com checador de tipos | Verificada pelo compilador | Verificada pelo compilador em `when` expressão | Aviso CS8509, não garantia |
| `Result` | `(T, error)` com erro de domínio tipado | união `{ ok: true; value } \| { ok: false; error }` | exceção de domínio tipada ou união de retorno, conforme o repo | exceção de domínio tipada ou tipo `Result` do repo | `sealed interface` de resultado | tipo `Result` do repo ou exceção de domínio |
| Dependência | tipo função ou interface pequena no parâmetro | tipo função no parâmetro | `Callable` ou `Protocol` | interface funcional | tipo função | `Func<>` ou interface |

Se o repositório já usa uma biblioteca de `Result` ou `Either`, siga a do repositório. Não adicione
dependência só para isso.

## Go

```go
type Email struct {
	value string
}

var ErrInvalidEmail = errors.New("invalid email")

func NewEmail(raw string) (Email, error) {
	if !strings.Contains(raw, "@") {
		return Email{}, fmt.Errorf("%w: %q", ErrInvalidEmail, raw)
	}
	return Email{value: raw}, nil
}

func (e Email) String() string { return e.value }

type Order interface {
	isOrder()
}

type UnvalidatedOrder struct {
	CustomerEmail string
	Lines         []UnvalidatedLine
}

type ValidatedOrder struct {
	ID            OrderID
	CustomerEmail Email
	Lines         []ValidatedLine
}

func (UnvalidatedOrder) isOrder() {}
func (ValidatedOrder) isOrder()   {}

type CheckProductExists func(ctx context.Context, code ProductCode) (bool, error)

type ValidateOrder func(ctx context.Context, checkProduct CheckProductExists, order UnvalidatedOrder) (ValidatedOrder, error)
```

- Limite: o valor zero (`Email{}`) continua construível fora do pacote. Trate o valor zero como
  ausente nas fronteiras ou exponha só construtores que devolvem o tipo validado.
- `switch o := order.(type)` precisa de `default` que devolve erro; o compilador não aponta caso
  esquecido. Teste um caso por estado.
- Erro de domínio com dados vira tipo (`type ProductNotFoundError struct{ Code ProductCode }`) e
  quem chama usa `errors.As`. Siga `lt:go-guideline` para o resto do estilo.

> **Camada de linguagem é opcional.** Confirme que `lt:go-guideline` existe com
> `bash "${CLAUDE_PLUGIN_ROOT}/scripts/lt-sdd.sh" skills-available --category language` antes de
> mandar carregá-la; sem ela, esta referência é o único guia.

## TypeScript

```ts
declare const emailBrand: unique symbol;
export type Email = string & { readonly [emailBrand]: true };

export type Result<T, E> =
  | { readonly ok: true; readonly value: T }
  | { readonly ok: false; readonly error: E };

export type ValidationError = { readonly kind: "invalid-email"; readonly raw: string };

export function createEmail(raw: string): Result<Email, ValidationError> {
  return raw.includes("@")
    ? { ok: true, value: raw as Email }
    : { ok: false, error: { kind: "invalid-email", raw } };
}

export type Order =
  | { readonly kind: "unvalidated"; readonly customerEmail: string }
  | { readonly kind: "validated"; readonly id: OrderId; readonly customerEmail: Email };

export function assertNever(value: never): never {
  throw new Error(`unexpected variant: ${JSON.stringify(value)}`);
}
```

- Exige `strict: true` no `tsconfig`. Sem isso, a união discriminada perde a garantia.
- O cast `as Email` fica só dentro de `createEmail`.

## Python, Java, Kotlin e C#

- **Python**: `@dataclass(frozen=True, slots=True)` com validação em `__post_init__` lançando uma
  subclasse de `DomainError`; escolha como `Unvalidated | Validated` e `match` terminando em
  `assert_never(order)`. A garantia depende de `mypy` ou `pyright` no CI; sem checador, registre.
- **Java 21+**: `sealed interface Order permits Unvalidated, Validated`, estados como `record`,
  `switch` com pattern matching sem `default` para o compilador cobrar os casos.
- **Kotlin**: `sealed interface` com `data class` por estado e `when` usado como expressão;
  tipo restrito como `@JvmInline value class` com `private constructor` e fábrica no
  `companion object`.
- **C#**: estados como `sealed record` derivados de um `abstract record`; o `switch` precisa de
  `_ => throw` porque o compilador não prova exaustividade de hierarquia de classes.

## Revisão de código existente

Para cada achado, registre `path:linha`, a regra do piso violada e a correção:

| Sinal no código | Regra do piso | Correção |
|---|---|---|
| `Status string` com `if o.Status == "paid"` | 2 | Um tipo por estado e transição como função |
| Campo que só vale num estado (`PaidAt *time.Time`) | 2 | Mover o campo para o tipo do estado |
| `Email string` validado no handler | 1 | Tipo restrito com construtor |
| Struct de domínio com `json:"..."` ou `gorm:"..."` | 8 | DTO na borda e função de tradução |
| `errors.New("invalid")` genérico para regras diferentes | 6 | Erro de domínio por reação distinta |
| Repositório chamado no meio das regras | 7 | Ler antes, decidir no núcleo, gravar depois |
