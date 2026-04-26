# Arbiter

Arbiter is a real-time arbitrage signal monitoring platform built in Go. It ingests live BTC quotes from Coinbase and Kraken, normalizes them into a shared schema, detects cross-exchange spreads, persists emitted signals to Postgres, and serves them through a JSON API and live dashboard.

The current system is intentionally narrow:

- one asset: `BTC-USD`
- two exchanges: Coinbase and Kraken
- one product surface: live signal monitoring

That scope is deliberate. The goal of this version is not breadth. The goal is to produce a polished, interview-ready end-to-end system that demonstrates distributed streaming, persistence, live delivery, and clear operational tradeoffs.

## What It Does

- subscribes to live exchange WebSocket feeds
- publishes raw ticks into Kafka
- normalizes exchange-specific messages into a common format
- detects cross-exchange arbitrage opportunities
- persists signals into Postgres
- exposes recent history through `GET /signals`
- pushes new signals live over `WS /ws/signals`
- renders a dashboard at `GET /`

## Architecture

```text
Coinbase WS ----> ingestor-coinbase ----\
                                         \
                                          > raw Kafka topics ---> normalizers ---> normalized.ticks ---> detector ---> arbitrage.signals ---> signal-writer ---> Postgres
                                         /
Kraken WS ------> ingestor-kraken ------/

Postgres ---> API ---> Dashboard
                 \
                  ---> WebSocket live stream
```

Current pipeline stages:

- `ingestor-coinbase`
- `ingestor-kraken`
- `normalizer`
- `detector`
- `signal-writer`
- `api`

## Configuration

Use [.env.example](.env.example) as the starting point for local overrides:

```bash
cp .env.example .env
```

The project has two config modes:

- local live validation with fresh consumer groups
- deployed long-running services with stable consumer groups

That separation is important. Fresh groups are useful for local tailing, but deployment should use stable group identities.

For a VM deployment, use [.env.production.example](.env.production.example) as the starting point instead.

## Why Kafka

This project is best described as a small distributed streaming system, not a worker-pool compute cluster.

Kafka is useful here because it gives each stage:

- a clean boundary between responsibilities
- independent restart behavior
- durable event flow between services
- a realistic distributed-system shape for interview discussion

It also introduces real tradeoffs:

- more operational complexity
- more opportunities for consumer-group / backlog issues during local development
- higher end-to-end latency than an in-process hot path

Those tradeoffs are part of the project story, not something hidden from it.

## Current Product Surface

The dashboard shows:

- recent arbitrage signals
- buy and sell venues
- spread
- quote gap
- buy age / sell age
- oldest quote age
- live status for API and stream connectivity

The API currently exposes:

- `GET /`
- `GET /health`
- `GET /signals?limit=50`
- `GET /signals?limit=50&before_id=<id>`
- `WS /ws/signals`

## Current Status

Implemented:

- live Coinbase and Kraken ingestion
- Kafka-backed normalization and detection pipeline
- Postgres-backed signal persistence
- API for recent signal history
- WebSocket live signal delivery
- embedded dashboard served from the API
- local Docker Compose environment for the full stack

Not in scope for this version:

- order execution
- more exchanges and assets
- user accounts or auth
- Kubernetes
- Prometheus / Grafana

## Tech Stack

- Go
- Kafka
- Protobuf
- PostgreSQL
- Docker Compose
- `segmentio/kafka-go`
- `jackc/pgx`
- Gorilla WebSocket

## Repository Layout

```text
cmd/
  api/               HTTP API + embedded dashboard
  consumer/          Example Kafka consumer
  detector/          Arbitrage detector
  ingestor-coinbase/ Coinbase WebSocket ingestor
  ingestor-kraken/   Kraken WebSocket ingestor
  normalizer/        RawTick -> NormalizedTick transformer
  producer/          Example Kafka producer
  signal-consumer/   Human-readable signal stream reader
  signal-writer/     Kafka consumer that persists Signal rows to Postgres
docs/
  detector_debugging_notes.md
  deployment.md
  local_kafka_reference.md
  summary_for_codex.md
proto/
  common.proto
  normalized_tick.proto
  raw_tick.proto
  signal.proto
scripts/
  generate_protos.sh
docker-compose.yml
Makefile
```

## Local Run

### 1. Start infrastructure

```bash
make up-minimal
make create-topics-dev
```

Or start the full local stack:

```bash
make up
```

### 2. Start the long-lived pipeline

For ordinary local development:

```bash
make compose-up-pipeline
make logs-pipeline
```

### 3. Start a clean live-validation run

For the cleanest live view, use isolated `.live` topics and fresh consumer groups:

```bash
export RUN_ID=$(date +%s)
export LIVE_NORMALIZER_COINBASE_GROUP_ID=arbiter-normalizer-live-$RUN_ID
export LIVE_NORMALIZER_KRAKEN_GROUP_ID=arbiter-normalizer-kraken-live-$RUN_ID
export LIVE_DETECTOR_GROUP_ID=arbiter-detector-live-$RUN_ID
export LIVE_NORMALIZER_START_OFFSET=latest
export LIVE_DETECTOR_START_OFFSET=latest
export LIVE_MAX_QUOTE_GAP_MS=5000

make create-topics-live
make compose-up-pipeline-live
make logs-pipeline-live
```

Or use the helper target that generates fresh normalizer and detector groups automatically:

```bash
make compose-up-pipeline-live-fresh
```

Then open:

- dashboard: `http://localhost:8080/`
- API health: `http://localhost:8080/health`
- recent signals: `http://localhost:8080/signals?limit=10`

Stop the pipeline with:

```bash
make compose-down-pipeline-live
```

## Postgres Defaults

Local Compose defaults:

- host port: `5433`
- database: `arbiter`
- username: `postgres`
- password: `postgres`
- connection string:
  `postgres://postgres:postgres@localhost:5433/arbiter?sslmode=disable`

The `signal-writer` service creates the `signals` table automatically and deduplicates writes by Kafka topic, partition, and offset.

## Freshness And Signal Semantics

The signal stream intentionally surfaces timing metadata alongside spread data:

- `quote_gap_ms`
- `buy_quote_age_ms`
- `sell_quote_age_ms`
- `oldest_quote_age_ms`

These fields matter because a spread is only meaningful if the contributing quotes are recent enough and close enough together in time.

Important nuance:

- `quote_gap_ms` is the temporal distance between the buy and sell quotes
- `oldest_quote_age_ms` is the age of the older contributing quote at emission time
- `oldest_quote_age_ms` is not a fixed pipeline-latency metric

That distinction became a central part of the debugging process and is documented in [detector_debugging_notes.md](docs/detector_debugging_notes.md).

## Deployment Plan

The intended first deployment is intentionally simple:

- one VM running Docker Compose for Kafka and the Go pipeline services
- managed Postgres
- API serving both JSON endpoints and the dashboard
- production service images built from `Dockerfile`
- hosted runtime defined in `docker-compose.production.yml`

Production deployment strategy:

- stable consumer groups for long-running services
- managed Postgres connection through `DATABASE_URL`
- documented restart policy
- no fresh random group IDs on every restart

Local development and deployment differ on purpose:

- local live validation prefers fresh consumer groups to avoid backlog ambiguity
- deployed systems should run continuously with stable group identities

More detailed notes live in [deployment.md](docs/deployment.md).
There is also a concrete [deployment checklist](docs/deployment_checklist.md) for the first VM deployment.

## Operator Notes

Kafka retains messages and consumer groups retain offsets, so local restarts can accidentally drain old backlog instead of tailing fresh data.

For a clean local live run, prefer:

- `.live` topics
- fresh consumer groups
- `latest` start offsets

If the detector appears quiet, check whether the pipeline is consuming stale retained data before assuming the detection logic is broken.

## Common Commands

```bash
make up
make up-minimal
make create-topics-dev
make create-topics-live
make compose-up-pipeline
make compose-up-pipeline-live
make compose-down-pipeline
make compose-down-pipeline-live
make logs-pipeline
make logs-pipeline-live
make compose-run-signal-consumer
make compose-run-api
make down
```

## Documentation

- [Detector debugging notes](docs/detector_debugging_notes.md)
- [Deployment notes](docs/deployment.md)
- [Deployment checklist](docs/deployment_checklist.md)
- [Local Kafka reference](docs/local_kafka_reference.md)
- [Project planning notes](docs/summary_for_codex.md)

## Roadmap

Near-term:

1. deployment polish
2. API docs surface
3. README screenshots
4. environment cleanup for hosted deployment

Later:

1. more exchanges and assets
2. metrics / observability
3. deeper history exploration and analytics
4. more formal deployment packaging
