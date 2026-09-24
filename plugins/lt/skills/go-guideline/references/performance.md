# Desempenho em Go

<!-- TL;DR
Regras de desempenho valem só no caminho quente e depois de medir: strconv no lugar de fmt, conversão de string para bytes uma vez só, capacidade em make para slice e map, profiling com pprof e comparação com benchstat antes de afirmar ganho.
Keywords: strconv, fmt.Sprint, []byte, make, capacity, hint, alloc, pprof, benchstat, benchmem, GOMEMLIMIT, PGO
Load complete when: a mudança mexe em caminho quente, laço de alta frequência, alocação ou pede otimização.
-->

- Escopo: código em caminho quente comprovado por medição.
- Fonte: Uber, seção "Performance". Profiling e medição vêm da documentação oficial do Go
  (`runtime/pprof`, `golang.org/x/perf/cmd/benchstat` e "Profile-guided optimization").

Uber: as regras desta seção valem **só no caminho quente**. Fora dele, legibilidade vence.

## GO-PERF-001 Medir antes de otimizar

Sem medição não há afirmação de ganho.

1. Isole o gargalo com benchmark ou profile. Antes de mexer em CPU, descarte que o custo seja externo: rede, banco, lock.
2. Capture a linha de base: `go test -bench . -benchmem -count 10 > old.txt`.
3. Aplique uma mudança por vez e capture `new.txt` do mesmo jeito.
4. Compare com `benchstat old.txt new.txt`. Ganho sem significância estatística não é ganho.
5. Para ver onde o tempo vai, use `-cpuprofile` e `-memprofile` com `go tool pprof`. Em serviço, use `net/http/pprof` protegido por autenticação ou exposto só em interface interna.

## GO-PERF-002 `strconv` no lugar de `fmt`

Uber: para converter primitivo de e para string, `strconv` é mais rápido que `fmt`. Use
`strconv.Itoa(n)` e não `fmt.Sprint(n)`. No benchmark do guia, o custo caiu de 143 ns e 2
alocações por operação para 64,2 ns e 1 alocação.

## GO-PERF-003 Conversão de string para bytes

Uber: não converta a mesma string fixa para `[]byte` a cada iteração. Converta uma vez e reutilize.

```go
data := []byte("Hello world")
for range n {
	w.Write(data)
}
```

`for range n` exige Go 1.22 ou superior. Em versões anteriores, use `for i := 0; i < n; i++`.

## GO-PERF-004 Capacidade em `make`

Uber:
- Slice: `make([]T, 0, size)` quando o tamanho final é conhecido. A capacidade é garantida, e os `append` não alocam até ela se esgotar.
- Map: `make(map[K]V, len(src))`. Para map, o número é só uma dica: ele reduz, mas não elimina, as realocações.

```go
m := make(map[string]os.DirEntry, len(files))
for _, f := range files {
	m[f.Name()] = f
}
```

## GO-PERF-005 Ajuste de runtime

Documentação oficial:
- `GOMEMLIMIT` define um limite suave de memória, útil em contêiner com limite rígido. Configure a partir do limite real do contêiner, com folga.
- PGO (Go 1.21 ou superior) usa um profile de CPU de produção, gravado como `default.pgo` no pacote `main`, para orientar o compilador. Só vale a pena com profile representativo, e o ganho precisa ser medido como em GO-PERF-001.
