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
