FROM golang:1.23-bookworm AS builder

ARG CMD_PATH

WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN test -n "$CMD_PATH"
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /out/service "$CMD_PATH"

FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /out/service /usr/local/bin/service

ENTRYPOINT ["/usr/local/bin/service"]
