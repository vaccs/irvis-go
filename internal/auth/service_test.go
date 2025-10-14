package auth

import (
	"context"
	"testing"
)

func TestLoginSuccess(t *testing.T) {
	svc := NewService()
	resp, err := svc.Login(context.Background(), LoginRequest{Email: "admin@example.com", Password: "password123"})
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if resp.Token == "" {
		t.Fatalf("expected token, got empty")
	}
	if resp.User.Email != "admin@example.com" {
		t.Fatalf("unexpected user email: %s", resp.User.Email)
	}
}

func TestLoginFailure(t *testing.T) {
	svc := NewService()
	_, err := svc.Login(context.Background(), LoginRequest{Email: "admin@example.com", Password: "wrong"})
	if err == nil {
		t.Fatalf("expected error, got nil")
	}
	if err != ErrInvalidCredentials {
		t.Fatalf("expected ErrInvalidCredentials, got %v", err)
	}
}
