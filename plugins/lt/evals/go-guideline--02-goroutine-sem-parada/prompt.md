Isso aqui está pronto para produção? evals/fixtures/metrics/reporter.go

O repositório não está disponível nesta sessão; o conteúdo atual dos arquivos citados vai abaixo.

`evals/fixtures/metrics/reporter.go`:

```
package metrics

import (
	"sync"
	"time"
)

type Reporter struct {
	sync.Mutex
	counters map[string]int
	send     func(map[string]int)
	queue    chan string
}

func NewReporter(send func(map[string]int)) *Reporter {
	r := &Reporter{
		counters: map[string]int{},
		send:     send,
		queue:    make(chan string, 1000),
	}
	go func() {
		for {
			r.Lock()
			r.send(r.counters)
			r.Unlock()
			time.Sleep(10 * time.Second)
		}
	}()
	return r
}

func (r *Reporter) Counters() map[string]int {
	r.Lock()
	defer r.Unlock()
	return r.counters
}
```
