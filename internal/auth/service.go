package auth

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"strings"
)

var (
	// ErrInvalidCredentials is returned when email/password do not match
	ErrInvalidCredentials = errors.New("invalid email or password")
	// ErrInvalidInput is returned when input is missing or malformed
	ErrInvalidInput = errors.New("invalid input")
)

// LoginRequest represents login payload
type LoginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

// LoginResponse represents login response
type LoginResponse struct {
	Token string `json:"token"`
	User  User   `json:"user"`
}

// User represents a minimal user profile
type User struct {
	ID    string `json:"id"`
	Email string `json:"email"`
	Name  string `json:"name"`
}

// Service defines auth operations
type Service interface {
	Login(ctx context.Context, req LoginRequest) (LoginResponse, error)
}

type service struct{}

// NewService creates a new auth service
func NewService() Service { return &service{} }

// Login validates credentials and returns a fake token on success
func (s *service) Login(ctx context.Context, req LoginRequest) (LoginResponse, error) {
	_ = ctx
	email := strings.TrimSpace(strings.ToLower(req.Email))
	pass := req.Password
	if email == "" || pass == "" {
		return LoginResponse{}, ErrInvalidInput
	}

	// Simple hardcoded user check for demo purposes
	if email != "admin@example.com" || pass != "password123" {
		return LoginResponse{}, ErrInvalidCredentials
	}

	token := randomToken(32)
	return LoginResponse{
		Token: token,
		User: User{
			ID:    "1",
			Email: email,
			Name:  "Admin User",
		},
	}, nil
}

func randomToken(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}
