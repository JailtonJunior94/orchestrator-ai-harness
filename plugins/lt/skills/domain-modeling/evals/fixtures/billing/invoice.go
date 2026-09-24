package billing

import (
	"errors"
	"time"
)

type Invoice struct {
	ID         string     `json:"id" gorm:"primaryKey"`
	CustomerID string     `json:"customer_id"`
	Email      string     `json:"email"`
	Amount     float64    `json:"amount"`
	Status     string     `json:"status"`
	PaidAt     *time.Time `json:"paid_at"`
	CanceledAt *time.Time `json:"canceled_at"`
}

func (i *Invoice) Pay(now time.Time) error {
	if i.Status == "canceled" {
		return errors.New("invalid operation")
	}
	if i.Amount <= 0 {
		return errors.New("invalid operation")
	}
	i.Status = "paid"
	i.PaidAt = &now
	return nil
}

func (i *Invoice) Cancel(now time.Time) error {
	if i.Status == "paid" {
		return errors.New("invalid operation")
	}
	i.Status = "canceled"
	i.CanceledAt = &now
	return nil
}
