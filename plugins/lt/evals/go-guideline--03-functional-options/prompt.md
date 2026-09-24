Refatora o construtor em evals/fixtures/dbclient/client.go: cada chamada precisa passar todos os parâmetros e isso vai crescer.

O repositório não está disponível nesta sessão; o conteúdo atual dos arquivos citados vai abaixo.

`evals/fixtures/dbclient/client.go`:

```
package dbclient

import (
	"log/slog"
	"time"
)

type Client struct {
	addr    string
	timeout time.Duration
	retries int
	cache   bool
	logger  *slog.Logger
}

func New(addr string, timeout int, retries int, cache bool, logger *slog.Logger) *Client {
	return &Client{
		addr:    addr,
		timeout: time.Duration(timeout) * time.Second,
		retries: retries,
		cache:   cache,
		logger:  logger,
	}
}
```
