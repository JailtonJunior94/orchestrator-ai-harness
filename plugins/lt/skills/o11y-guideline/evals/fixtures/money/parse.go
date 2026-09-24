package money

import (
	"errors"
	"strconv"
	"strings"
)

var ErrInvalidAmount = errors.New("invalid amount")

func ParseCents(s string) (int64, error) {
	s = strings.TrimSpace(s)
	whole, frac, found := strings.Cut(s, ",")
	if !found {
		frac = "00"
	}
	if len(frac) != 2 {
		return 0, ErrInvalidAmount
	}
	w, err := strconv.ParseInt(whole, 10, 64)
	if err != nil || w < 0 {
		return 0, ErrInvalidAmount
	}
	f, err := strconv.ParseInt(frac, 10, 64)
	if err != nil || f < 0 {
		return 0, ErrInvalidAmount
	}
	return w*100 + f, nil
}
