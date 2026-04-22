# Arbiter

Arbiter is a Go-based streaming market-data project for detecting cross-exchange arbitrage opportunities in near real time.

The long-term architecture is:

`exchange feeds -> ingestors -> Kafka -> normalizer -> detector -> signals -> WebSocket/REST API`

Right now, this repository contains the early foundation for that pipeline:

- Protobuf schemas for raw ticks, normalized ticks, and arbitrage signals
- Generated Go bindings for those schemas
- A local Kafka development stack using Docker Compose
- A Coinbase WebSocket ingestor that publishes `RawTick` messages to Kafka
- A Kraken WebSocket ingestor that publishes `RawTick` messages to Kafka
- A normalizer service that converts `RawTick` messages into `NormalizedTick`
- A detector service that tracks latest quotes by symbol/exchange and emits `Signal` messages when spreads qualify
- Example Go producer and consumer apps that exchange `NormalizedTick` messages
- Local developer docs and Make targets for common workflows

## Current Status

This repo is currently in the scaffold stage.

Implemented:

- Kafka + Schema Registry local stack
- Protobuf message contracts
- Coinbase ticker-feed ingestor for one product
- Kraken ticker-feed ingestor for one product
- Kafka normalizer from raw to normalized ticks
- Detector state machine for multi-exchange spread checks
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
  detector/     Arbitrage detector consuming NormalizedTick and producing Signal
  ingestor-coinbase/ Coinbase WebSocket ingestor publishing RawTick messages
  ingestor-kraken/ Kraken WebSocket ingestor publishing RawTick messages
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

### 4. Start the live pipeline

The most reliable local dev workflow is to run the pipeline as long-lived Compose services:

```bash
make compose-up-pipeline
make logs-pipeline
```

This keeps the ingestors, normalizers, and detector alive continuously, which avoids stale-data issues caused by short-lived startup churn.

Stop the live pipeline with:

```bash
make compose-down-pipeline
```

For the cleanest arbitrage validation, use the isolated live-topic workflow so old topic history does not pollute the detector:

```bash
make create-topics-live
make compose-up-pipeline-live
make logs-pipeline-live
```

Stop that isolated validation pipeline with:

```bash
make compose-down-pipeline-live
```

### 5. Run the example consumer and producer

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

### 6. Run the Coinbase ingestor

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
- `INGESTOR_DEBUG` default: `false`

### 7. Run the Kraken ingestor

The Compose-network path is the recommended dev workflow.

Inside the Compose network:

```bash
make compose-run-ingestor-kraken
```

Or directly on your host if your local Kafka listener setup matches the host-run configuration:

```bash
go run ./cmd/ingestor-kraken
```

Useful environment variables:

- `KAFKA_BROKERS` default: `localhost:9092`
- `RAW_TICKS_TOPIC` default: `raw.ticks.kraken`
- `KRAKEN_SYMBOL` default: `BTC/USD`
- `KRAKEN_WS_URL` default: `wss://ws.kraken.com/v2`
- `INGESTOR_DEBUG` default: `false`

### 8. Run the normalizer

The Compose-network path is the recommended dev workflow.

Inside the Compose network:

```bash
make compose-run-normalizer
make compose-run-normalizer-kraken
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
- `NORMALIZER_DEBUG` default: `false`
- `NORMALIZER_LOG_EVERY_N` default: `25`

Use the same normalizer binary with `RAW_TICKS_TOPIC=raw.ticks.kraken` and a different consumer group for Kraken.

### 9. Run the detector

The Compose-network path is the recommended dev workflow.

Inside the Compose network:

```bash
make compose-run-detector
```

Or directly on your host if your local Kafka listener setup matches the host-run configuration:

```bash
go run ./cmd/detector
```

Useful environment variables:

- `KAFKA_BROKERS` default: `localhost:9092`
- `NORMALIZED_TICKS_TOPIC` default: `normalized.ticks`
- `SIGNALS_TOPIC` default: `arbitrage.signals`
- `KAFKA_GROUP_ID` default: `arbiter-detector`
- `FEE_BPS` default: `0`
- `MIN_SIGNAL_PROFIT` default: `0`
- `MAX_QUOTE_AGE_MS` default: `5000`
- `MIN_SIGNAL_INTERVAL_MS` default: `500`
- `DETECTOR_DEBUG` default: `false`

### 10. Run the signal consumer

This is a friendlier way to watch detected opportunities than reading the merged pipeline logs.

Inside the Compose network:

```bash
make compose-run-signal-consumer
```

Or directly on your host:

```bash
go run ./cmd/signal-consumer
```

Useful environment variables:

- `KAFKA_BROKERS` default: `localhost:9092`
- `SIGNALS_TOPIC` default: `arbitrage.signals`
- `KAFKA_GROUP_ID` default: `arbiter-signal-consumer`

Example output:

```text
2026-04-20T21:33:41Z | BTC-USD | buy coinbase @ 75983.34 | sell kraken @ 75990.24 | spread 6.90 | profit 6.90 | latency 4855ms
```

The sample apps use `KAFKA_BROKERS` when set.

- Host default: `localhost:9092`
- Compose helper containers: `kafka:9092`

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
make down
make logs
make logs-follow
make gen-protos
make compose-run-consumer
make compose-run-signal-consumer
make compose-run-producer
make compose-run-ingestor-coinbase
make compose-run-ingestor-kraken
make compose-run-normalizer
make compose-run-normalizer-kraken
make compose-run-detector
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
- `raw.ticks.kraken`
- `normalized.ticks`
- `arbitrage.signals`

## Documentation

- [Project overview and plan](docs/summary_for_codex.md)
- [Local Kafka reference](docs/local_kafka_reference.md)

## Roadmap

Near-term plan:

1. Build one real exchange ingestor.
2. Validate live cross-exchange signals between Coinbase and Kraken.
3. Add a live demo surface with WebSocket or REST.
4. Add more exchanges and symbol normalization rules.
5. Persist signals and latency metrics.

Longer-term plan:

1. Add Redis and TimescaleDB.
2. Add health checks and metrics.
3. Add Prometheus and Grafana dashboards.
4. Package each stage as an independently deployable service.
5. Move from local Compose development to Kubernetes deployment.

## Notes

This project is being developed incrementally. The current goal is to prove one narrow end-to-end slice before expanding into the full multi-exchange architecture.
