# Testes em Go

<!-- TL;DR
Table test com tests, tt, give e want, sem lógica condicional na tabela, t.Parallel com cópia do laço só abaixo do Go 1.22, t.Fatal no lugar de panic, -race e goleak em código concorrente, fuzz para parser e entrada externa, benchmark com b.Loop no Go 1.24 ou superior.
Keywords: _test.go, t.Run, table test, give, want, t.Parallel, t.Fatal, -race, goleak, fuzz, testing.F, benchmark, b.Loop, benchstat
Load complete when: a mudança cria ou altera arquivo _test.go, benchmark ou teste de fuzz.
-->

- Escopo: todo arquivo `_test.go`.
- Fonte: Uber, seções "Test Tables", "Avoid Unnecessary Complexity in Table Tests", "Parallel
  Tests", "Don't Panic" e "Don't fire-and-forget goroutines". Fuzz e benchmark vêm da documentação
  oficial do pacote `testing`.

## Sumário

- GO-TEST-001 Table tests
- GO-TEST-002 Tabela sem lógica condicional
- GO-TEST-003 Testes paralelos
- GO-TEST-004 Falha de teste
- GO-TEST-005 Concorrência em teste
- GO-TEST-006 Fuzz
- GO-TEST-007 Benchmark
- GO-TEST-008 Comandos

## GO-TEST-001 Table tests

Uber: quando o mesmo sistema é testado com várias entradas e saídas, use table test com subtestes.
Convenção de nomes:

- a lista de casos se chama `tests`;
- cada caso se chama `tt`;
- os campos de entrada levam o prefixo `give` e os de saída, `want`.

```go
func TestSplitHostPort(t *testing.T) {
	tests := []struct {
		give     string
		wantHost string
		wantPort string
	}{
		{give: "192.0.2.0:8000", wantHost: "192.0.2.0", wantPort: "8000"},
		{give: ":8000", wantHost: "", wantPort: "8000"},
	}
	for _, tt := range tests {
		t.Run(tt.give, func(t *testing.T) {
			host, port, err := net.SplitHostPort(tt.give)
			if err != nil {
				t.Fatalf("SplitHostPort(%q) error: %v", tt.give, err)
			}
			if host != tt.wantHost || port != tt.wantPort {
				t.Errorf("SplitHostPort(%q) = %q, %q; want %q, %q",
					tt.give, host, port, tt.wantHost, tt.wantPort)
			}
		})
	}
}
```

O Uber usa `testify` (`require` e `assert`) nos exemplos. Siga a biblioteca de asserção que o
repositório já usa e não introduza uma nova só por estilo.

## GO-TEST-002 Tabela sem lógica condicional

Uber: tabela com caminhos condicionais dentro do laço fica difícil de ler e de depurar. Sinais de
que a tabela deve virar testes separados:

- campos como `shouldCallX`, `expectCall` ou vários `shouldErr`;
- vários `if` montando expectativas de mock;
- função dentro da tabela (`setupMocks func(*FooMock)`).

Metas do Uber para a tabela:
- teste a menor unidade de comportamento;
- mantenha a profundidade de asserção rasa;
- use todos os campos em todos os casos;
- rode toda a lógica do teste em todos os casos.

Um único campo como `shouldErr`, com corpo curto, é aceitável.

## GO-TEST-003 Testes paralelos

O Uber manda que a variável do laço tenha escopo da iteração quando o subteste chama `t.Parallel()`.

Exceção deste harness, conforme a versão:
- `go.mod` com Go 1.22 ou superior: o próprio `for` já cria uma variável por iteração. Não escreva `tt := tt`.
- Abaixo do Go 1.22: escreva `tt := tt` antes do `t.Run`. Sem isso, os subtestes leem o valor errado.

## GO-TEST-004 Falha de teste

Uber: em teste, use `t.Fatal` ou `t.FailNow` para abortar, nunca `panic`. Panic não marca o teste
como falho do jeito certo e derruba o binário de teste inteiro. Use `t.Helper()` em função auxiliar
para a falha apontar a linha de quem chamou.

## GO-TEST-005 Concorrência em teste

- Uber: pacote que dispara goroutine verifica vazamento com `go.uber.org/goleak`:
  ```go
  func TestMain(m *testing.M) {
  	goleak.VerifyTestMain(m)
  }
  ```
- Rode `go test -race` em pacote com concorrência.
- Não use `time.Sleep` para sincronizar teste. Use canal, `sync.WaitGroup`, ou `testing/synctest`
  (estável a partir do Go 1.25) para código que depende de tempo.

## GO-TEST-006 Fuzz

Documentação oficial: parser, decodificador e qualquer função que recebe entrada externa ganham
teste de fuzz (Go 1.18 ou superior).

```go
func FuzzParse(f *testing.F) {
	f.Add("192.0.2.0:8000")
	f.Fuzz(func(t *testing.T, s string) {
		host, port, err := net.SplitHostPort(s)
		if err != nil {
			return
		}
		h2, p2, err := net.SplitHostPort(net.JoinHostPort(host, port))
		if err != nil || h2 != host || p2 != port {
			t.Errorf("round trip of %q: got %q, %q, %v", s, h2, p2, err)
		}
	})
}
```

O teste de fuzz verifica uma propriedade que vale para qualquer entrada válida (aqui, a ida e volta),
e não uma saída fixa.

O corpus que reproduz falha fica em `testdata/fuzz/` e é versionado.

## GO-TEST-007 Benchmark

Documentação oficial:
- Go 1.24 ou superior: use `for b.Loop() { ... }`. O laço impede que o compilador elimine a chamada medida e dispensa `b.ResetTimer()` após o preparo.
- Versões anteriores: use `for i := 0; i < b.N; i++`.
- Compare benchmarks com `benchstat` sobre várias execuções (`-count=10`). Uma execução única não prova ganho.

## GO-TEST-008 Comandos

```bash
go test ./...
go test -race ./...
go test -run TestName ./pkg/...
go test -fuzz FuzzParse -fuzztime 30s ./pkg/parser
go test -bench . -benchmem -count 10 ./pkg/... | tee new.txt
```
