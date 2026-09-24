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
