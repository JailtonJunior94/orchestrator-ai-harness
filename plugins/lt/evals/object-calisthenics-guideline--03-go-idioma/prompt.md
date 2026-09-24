Aplica Object Calisthenics no pacote Go em evals/fixtures/account/ (account.go e transfer.go).

O repositório não está disponível nesta sessão; o conteúdo atual dos arquivos citados vai abaixo.

`evals/fixtures/account/account.go`:

```
package account

import "errors"

var (
	ErrInsufficientFunds = errors.New("insufficient funds")
	ErrBlocked           = errors.New("account blocked")
)

type Account struct {
	owner   string
	balance int64
	blocked bool
}

func (a *Account) Owner() string      { return a.owner }
func (a *Account) GetBalance() int64  { return a.balance }
func (a *Account) SetBalance(b int64) { a.balance = b }
func (a *Account) IsBlocked() bool    { return a.blocked }
```

`evals/fixtures/account/transfer.go`:

```
package account

func Transfer(from, to *Account, amount int64) error {
	if from.GetBalance() >= amount {
		if !from.IsBlocked() {
			from.SetBalance(from.GetBalance() - amount)
			to.SetBalance(to.GetBalance() + amount)
			return nil
		} else {
			return ErrBlocked
		}
	} else {
		return ErrInsufficientFunds
	}
}
```
