# irvis-go

Go + Gin web application for IRVIS.

## Run Locally (Go)

1. Copy `.env.example` to `.env` and adjust values.
2. Start the app:

```bash
go run ./cmd/server
```

By default, `SERVER_PROTOCOL=https`, so set `TLS_CERT_FILE` and `TLS_KEY_FILE` in `.env` for HTTPS local runs.

## Run with Docker (HTTP on port 8080)

This repository now includes Docker support to run the Go app and MySQL together without TLS.

1. Use the Docker env file (already configured): `.env.docker`
2. Build and start:

```bash
docker compose up --build
```

3. Access the app at:

```text
http://localhost:8080/irvis
```

To stop:

```bash
docker compose down
```

To stop and remove database data:

```bash
docker compose down -v
```

## Run with Script

Use the helper script to build, start, and quickly health-check the stack:

```bash
./run_docker_app.sh
```

The script uses `compose.yaml`, starts containers in detached mode, and checks `http://localhost:8080/healthz`.

## Environment Variables

- `PORT`: server port (default `8080`)
- `SERVER_PROTOCOL`: `http` or `https`
- `DB_NAME`: MySQL database name
- `DB_USER`: MySQL user
- `DB_PASSWORD`: MySQL password
- `DB_HOST`: MySQL host (use `mysql` in Docker Compose)
- `DB_PORT`: MySQL port (default `3306`)
- `MAX_OPEN_CONNS`: DB max open connections
- `MAX_IDLE_CONNS`: DB max idle connections
- `CONN_MAX_LIFETIME`: DB connection max lifetime in seconds
- `TLS_CERT_FILE`: required when `SERVER_PROTOCOL=https`
- `TLS_KEY_FILE`: required when `SERVER_PROTOCOL=https`
- `GITHUB_TOKEN`: optional token used by app features

## Health Check

- `GET /healthz`
