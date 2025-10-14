# irvis-go

Simple Go Gin backend exposing a POST /login endpoint.

## Endpoints

- GET /healthz — health check
- POST /login — authenticate with JSON body

Request body:

{
  "email": "admin@example.com",
  "password": "password123"
}

Response (200):

{
  "token": "<random-hex-token>",
  "user": { "id": "1", "email": "admin@example.com", "name": "Admin User" }
}

Errors:
- 400 invalid JSON or missing fields
- 401 invalid email or password

## Run

- With Go 1.22+ installed:

```
go run ./cmd/server
```

Server listens on :8080 by default. Set PORT to override.

## Try it

Optional curl examples:

```
# Health
curl -s http://localhost:8080/healthz | jq

# Login OK
curl -s -X POST http://localhost:8080/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"admin@example.com","password":"password123"}' | jq

# Login fail
curl -s -X POST http://localhost:8080/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"admin@example.com","password":"wrong"}' | jq
```
