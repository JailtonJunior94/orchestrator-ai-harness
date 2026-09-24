package userservice

import (
	"database/sql"
	"fmt"
	"log"
)

type Service struct {
	db *sql.DB
}

func (s *Service) Email(id string) (string, error) {
	var email string
	err := s.db.QueryRow("SELECT email FROM users WHERE id = $1", id).Scan(&email)
	if err != nil {
		log.Printf("could not load user %s: %v", id, err)
		return "", fmt.Errorf("failed to load user email: %v", err)
	}
	return email, nil
}

func (s *Service) MustEmail(id string) string {
	email, err := s.Email(id)
	if err != nil {
		panic(err)
	}
	return email
}
