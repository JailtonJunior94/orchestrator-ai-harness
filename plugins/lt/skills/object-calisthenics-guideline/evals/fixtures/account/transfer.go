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
