# Build stage
FROM golang:1.24-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY cmd ./cmd
COPY internal ./internal
RUN CGO_ENABLED=0 go build -o /out/server ./cmd/server

# Runtime stage
FROM alpine:3.20
RUN apk add --no-cache ca-certificates tzdata
WORKDIR /app
COPY --from=build /out/server ./server
COPY irvis ./irvis
COPY visual ./visual
ENV APP_MODE=docker \
    SERVER_PROTOCOL=http \
    GIN_MODE=release
EXPOSE 8080
CMD ["./server"]
