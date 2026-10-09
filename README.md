# irvis-go

Go + Gin web application for IRVIS.

## Run Locally (Go)

1. Copy `.env.example` to `.env` and adjust values.
2. Start the app:

```bash
go run ./cmd/server
```

By default, `SERVER_PROTOCOL=https`, so set `TLS_CERT_FILE` and `TLS_KEY_FILE` in `.env` for HTTPS local runs.

## Deploy on Railway

The repo includes a `Dockerfile` and `railway.json`. Railway builds the image, terminates HTTPS, and routes traffic to the app over HTTP on `$PORT`. One MySQL service can be shared by irvis, scvis, and eevis; each app creates its own database on first start.

1. In a Railway project, add a **MySQL** database (once, shared by all apps).
2. Add a service from this GitHub repo (`vaccs/irvis-go`).
3. In the service's **Variables**, set:

```text
DB_HOST=${{MySQL.MYSQLHOST}}
DB_PORT=${{MySQL.MYSQLPORT}}
DB_USER=${{MySQL.MYSQLUSER}}
DB_PASSWORD=${{MySQL.MYSQLPASSWORD}}
DB_NAME=irvis
DB_CREATE_DATABASE=true
SESSION_SECRET=<long random string, e.g. output of: openssl rand -hex 32>
ADMIN_EMAIL=<your email>
ADMIN_PASSWORD=<initial admin password>
GITHUB_TOKEN=<token, if the issue feature is used>
```

4. Under **Settings → Networking**, click **Generate Domain**. The app is at `https://<domain>/irvis`.

On startup the app creates the `users` table if missing, and creates the admin user from `ADMIN_*` only when the table is empty. After the first login you can remove `ADMIN_PASSWORD`.

To load existing users from another server, use `railway connect MySQL` and run your `mysqldump` file against the `irvis` database.

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
- `SESSION_SECRET`: key for signing session cookies (random per restart if unset)
- `DB_CREATE_DATABASE`: `true` to create `DB_NAME` on startup if it does not exist
- `ADMIN_USERNAME`, `ADMIN_EMAIL`, `ADMIN_PASSWORD`: initial admin user, created only when the users table is empty

## Health Check

- `GET /healthz`
