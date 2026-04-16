# Arbiter

Arbiter is a Go-based streaming market-data project for detecting cross-exchange arbitrage opportunities in near real time.

The long-term architecture is:

`exchange feeds -> ingestors -> Kafka -> normalizer -> detector -> signals -> WebSocket/REST API`

Right now, this repository contains the early foundation for that pipeline:

- Protobuf schemas for raw ticks, normalized ticks, and arbitrage signals
- Generated Go bindings for those schemas
- A local Kafka development stack using Docker Compose
- A Coinbase WebSocket ingestor that publishes `RawTick` messages to Kafka
- A normalizer service that converts `RawTick` messages into `NormalizedTick`
- Example Go producer and consumer apps that exchange `NormalizedTick` messages
- Local developer docs and Make targets for common workflows

## Current Status

This repo is currently in the scaffold stage.

Implemented:

- Kafka + Schema Registry local stack
- Protobuf message contracts
- Coinbase ticker-feed ingestor for one product
- Kafka normalizer from raw to normalized ticks
- Example producer/consumer path
- Environment-based Kafka broker configuration

Not implemented yet:

- real exchange ingestors
- normalization service
- arbitrage detector
- signal API
- Redis / TimescaleDB
- Prometheus / Grafana
- Kubernetes deployment

## Tech Stack

- Go
- Kafka
- Protobuf
- Docker Compose
- `segmentio/kafka-go`
- Schema Registry
- Kafdrop

Planned later:

- Redis
- TimescaleDB
- Prometheus
- Grafana
- Kubernetes

## Repository Layout

```text
cmd/
  consumer/     Example Kafka consumer for NormalizedTick messages
  ingestor-coinbase/ Coinbase WebSocket ingestor publishing RawTick messages
  normalizer/   Kafka normalizer from RawTick to NormalizedTick
  producer/     Example Kafka producer for NormalizedTick messages
docs/
  local_kafka_reference.md
  summary_for_codex.md
proto/
  common.proto
  raw_tick.proto
  normalized_tick.proto
  signal.proto
scripts/
  generate_protos.sh
docker-compose.yml
Makefile
```

## Getting Started

### 1. Start the local stack

```bash
make up-minimal
```

Or start the full stack including Kafdrop:

```bash
make up
```

### 2. Generate protobuf bindings

```bash
make gen-protos
```

This requires `protoc` and `protoc-gen-go`.

### 3. Create the local Kafka topics

```bash
make create-topics-dev
```

### 4. Run the example consumer and producer

The Compose-network path is the recommended dev workflow.

Inside the Compose network:

```bash
make compose-run-consumer
make compose-run-producer
```

Or directly on your host:

```bash
go run ./cmd/consumer
go run ./cmd/producer
```

### 5. Run the Coinbase ingestor

The Compose-network path is the recommended dev workflow.

Inside the Compose network:

```bash
make compose-run-ingestor-coinbase
```

Or directly on your host if your local Kafka listener setup matches the host-run configuration:

```bash
go run ./cmd/ingestor-coinbase
```

Useful environment variables:

- `KAFKA_BROKERS` default: `localhost:9092`
- `KAFKA_TOPIC` default: `normalized.ticks`
- `KAFKA_GROUP_ID` default: `arbiter-consumer`
- `RAW_TICKS_TOPIC` default: `raw.ticks.coinbase`
- `COINBASE_PRODUCT_ID` default: `BTC-USD`
- `COINBASE_WS_URL` default: `wss://ws-feed.exchange.coinbase.com`

### 6. Run the normalizer

The Compose-network path is the recommended dev workflow.

Inside the Compose network:

```bash
make compose-run-normalizer
```

Or directly on your host if your local Kafka listener setup matches the host-run configuration:

```bash
go run ./cmd/normalizer
```

Useful environment variables:

- `KAFKA_BROKERS` default: `localhost:9092`
- `RAW_TICKS_TOPIC` default: `raw.ticks.coinbase`
- `NORMALIZED_TICKS_TOPIC` default: `normalized.ticks`
- `KAFKA_GROUP_ID` default: `arbiter-normalizer`

The sample apps use `KAFKA_BROKERS` when set.

- Host default: `localhost:9092`
- Compose helper containers: `kafka:9092`

## Common Commands

```bash
make up
make up-minimal
make create-topics-dev
make down
make logs
make logs-follow
make gen-protos
make compose-run-consumer
make compose-run-producer
make compose-run-ingestor-coinbase
make compose-run-normalizer
```

## Topics And Message Flow

The intended topic design is:

- `raw.ticks.binance`
- `raw.ticks.coinbase`
- `raw.ticks.kraken`
- `normalized.ticks`
- `arbitrage.signals`

At the moment, the example apps only use:

- `raw.ticks.coinbase`
- `normalized.ticks`

## Documentation

- [Project overview and plan](docs/summary_for_codex.md)
- [Local Kafka reference](docs/local_kafka_reference.md)

## Roadmap

Near-term plan:

1. Build one real exchange ingestor.
2. Build a simple arbitrage detector.
3. Emit `Signal` messages to Kafka.
4. Add a live demo surface with WebSocket or REST.
5. Add more exchanges and symbol normalization rules.

Longer-term plan:

1. Add Redis and TimescaleDB.
2. Add health checks and metrics.
3. Add Prometheus and Grafana dashboards.
4. Package each stage as an independently deployable service.
5. Move from local Compose development to Kubernetes deployment.

## Notes

This project is being developed incrementally. The current goal is to prove one narrow end-to-end slice before expanding into the full multi-exchange architecture.
