# Arbiter Project Overview And Plan

## Project Goal

Arbiter is being built as a streaming market-data pipeline for detecting cross-exchange arbitrage opportunities in near real time.

The intended long-term flow is:

`exchange websocket feeds -> ingestors -> Kafka -> normalizer -> detector -> signals topic -> WebSocket/REST API -> live consumers`

The project is less about placing trades and more about demonstrating strong distributed-systems design:

- event-driven service boundaries
- low-latency message flow
- schema-driven contracts
- observability and latency measurement
- infrastructure that can scale and recover cleanly

## What We Have Done So Far

The current repository is an early scaffold for the pipeline. We have built the foundation, but not the full system.

Completed so far:

- defined Protobuf schemas for the core message types
- generated Go bindings for those schemas
- set up a local Kafka-based development stack with Docker Compose
- implemented a first real Coinbase WebSocket ingestor that publishes `RawTick` messages
- added a sample Go producer that publishes a `NormalizedTick`
- added a sample Go consumer that reads and decodes `NormalizedTick`
- added a Makefile and local developer reference notes
- switched to a pure-Go Kafka client to simplify local development

At this stage, the repo proves that:

- Go code can serialize and deserialize the project message contracts
- Kafka can be run locally for development
- a simple producer/consumer loop works end to end

What it does not prove yet:

- live ingestion from a real exchange
- normalization from raw exchange-specific messages into a common model
- arbitrage detection logic
- signal fanout to clients
- persistence, dashboards, or production deployment

## How The Codebase Is Set Up

The repo is intentionally small right now and is organized around the core building blocks of the future pipeline.

### `cmd/ingestor-coinbase`

This is the first real service-shaped component in the repo.

It:

- connects to the public Coinbase WebSocket feed
- subscribes to ticker updates for one product
- converts incoming JSON messages into `RawTick`
- encodes them with Protobuf
- publishes them to the Kafka topic `raw.ticks.coinbase`
- reconnects with backoff if the WebSocket disconnects

### `proto/`

This folder contains the message contracts for the pipeline.

- `common.proto`
  Defines shared tick metadata such as exchange, symbol, sequence ID, and timestamps.
- `raw_tick.proto`
  Defines the exchange-facing raw event model with optional price fields and raw payload bytes.
- `normalized_tick.proto`
  Defines the common downstream tick format used after exchange-specific transformation.
- `signal.proto`
  Defines the arbitrage opportunity message emitted by the detector.

These contracts are the most important part of the current codebase because they shape the service boundaries.

### `cmd/producer`

This is a small example app that creates a `NormalizedTick`, marshals it with Protobuf, and publishes it to Kafka.

Today it acts as a stand-in for a future real service. Conceptually it is closest to a tiny test publisher, not a real normalizer or ingestor.

### `cmd/consumer`

This is a small example app that subscribes to the `normalized.ticks` topic, unmarshals each message, and prints the tick contents.

Today it acts as a stand-in for any future downstream consumer.

### `docker-compose.yml`

This provides the local dev stack.

Current services:

- Zookeeper
- Kafka
- Schema Registry
- Kafdrop
- `producer-dev` helper container
- `consumer-dev` helper container

This lets us run the messaging backbone locally before building more services.

### `Makefile`

The Makefile wraps common local commands such as:

- bringing the stack up and down
- following logs
- regenerating protobuf bindings
- running the producer and consumer examples

### `docs/`

Current documentation includes:

- this summary file
- a local Kafka reference doc with useful Compose and Kafka commands

## Tools And Technologies We Are Using

Current stack:

- Language: Go
- Messaging: Kafka
- Serialization: Protobuf
- Live exchange feed: Coinbase public WebSocket API
- Local orchestration: Docker Compose
- Kafka client: `segmentio/kafka-go`
- WebSocket client: `gorilla/websocket`
- Schema tooling: `protoc` + `protoc-gen-go`
- Local Kafka support services: Zookeeper, Schema Registry, Kafdrop

Why these choices make sense:

- Go is a strong fit for service-oriented, concurrent systems work.
- Kafka gives us durable streaming infrastructure and consumer-group semantics.
- Protobuf gives us compact payloads and explicit schemas.
- `kafka-go` avoids the friction of native `librdkafka` dependencies during early development.
- Docker Compose is a practical way to validate the pipeline locally before worrying about Kubernetes.

Planned later stack additions:

- Redis for current-state reads and lightweight hot data
- TimescaleDB for historical signal storage
- Prometheus and Grafana for metrics and dashboards
- Kubernetes, likely K3s or EKS, for deployment

## Current Architecture Status

This is the current maturity level by layer.

### Implemented

- message schemas
- generated language bindings
- local Kafka runtime
- first raw-tick ingestor for Coinbase
- example publish/consume flow

### Partially represented in design only

- raw exchange ingestion
- normalization stage
- arbitrage detector
- signal topic publishing
- live API layer
- observability
- storage
- deployment model

### Important note about current code

The docs correctly describe running services inside the Compose network with the broker hostname `kafka:9092`, but the example producer and consumer currently still use `localhost:9092`.

That is fine for simple host execution, but it should be cleaned up before we lean on the helper containers as the standard dev path.

## What We Still Have Left To Do

The next work is about moving from a scaffold to one real vertical slice.

### Phase 1: Finish A Real End-To-End Slice

Build the smallest meaningful version of the system:

- one real exchange ingestor
- one raw topic
- one normalizer
- one detector
- one signal topic

The goal of this phase is not completeness. The goal is to prove the architecture with one symbol and one exchange-specific parser path.

### Phase 2: Expand To Multi-Exchange Comparison

Once one ingest path is stable:

- add the second and third exchange ingestors
- normalize all exchanges into the same schema
- compare exchange pairs in the detector
- emit real arbitrage signals

This is the point where the app starts to look like the system design you described.

### Phase 3: Add A Demo Surface

Build the consumption layer for humans and demos:

- WebSocket signal streaming
- REST endpoint for recent signals
- simple in-memory or Redis-backed recent-signal cache

This is the layer that makes the pipeline visible and easy to demonstrate.

### Phase 4: Add Observability

Once the pipeline exists, measure it properly:

- `/healthz` endpoints
- `/metrics` endpoints
- per-hop latency metrics
- Prometheus scraping
- Grafana dashboards

This is an important differentiator for the project because it shows operational thinking, not just message passing.

### Phase 5: Add Persistence

Add the longer-lived data stores:

- Redis for latest prices / fast reads
- TimescaleDB for historical arbitrage signals and analysis

This should come after the streaming path is stable, not before.

### Phase 6: Deployment And Scaling

After the local system works well:

- containerize each service cleanly
- define deployment manifests
- choose K3s or EKS
- scale detector workers by partition ownership

## What We Plan To Do Next

The recommended next milestone is a narrow but real vertical slice.

Suggested implementation order:

1. Convert the example apps into service-style code with shared config.
2. Build one exchange ingestor that emits `RawTick`.
3. Build the normalizer that emits `NormalizedTick`.
4. Build a simple detector with an in-memory price table.
5. Emit `Signal` messages to Kafka.
6. Add a basic consumer or CLI logger for signals.

Why this order:

- it validates the service boundaries early
- it keeps scope small
- it exposes schema or topic problems quickly
- it gives us an end-to-end demo before infrastructure complexity expands

## Decisions We Still Need To Make

Several important decisions are still open. None block the vision, but they will shape implementation details.

### 1. Which exchange should be first?

We should choose one exchange for the first ingestor based on:

- WebSocket API simplicity
- documentation quality
- data shape stability
- rate-limit behavior

The best first choice is usually the exchange with the simplest public market-data feed.

### 2. What is the first supported symbol set?

We do not need full coverage immediately.

A good first scope is:

- one symbol for the first vertical slice
- then BTC, ETH, and SOL as the first multi-symbol set

### 3. How much raw data should we preserve in `RawTick`?

Options include:

- keep the full raw payload for replay/debugging
- keep only extracted fields plus small metadata

Keeping the raw payload is useful early, but it increases message size.

### 4. How should service configuration be handled?

We need a consistent approach for:

- broker addresses
- topic names
- exchange URLs
- symbol allowlists
- fee thresholds

This likely means moving to environment-based config instead of hardcoded constants in `main.go`.

### 5. How should topics be created and managed?

We need to decide whether topics are:

- created manually for now
- created by setup scripts
- eventually managed by infrastructure definitions

### 6. How rich should the normalized schema be?

Current fields are enough for a start, but we may want to decide whether to include:

- best bid/ask only
- trade messages too
- source channel names
- exchange-native sequence numbers
- extra timestamps per hop

### 7. How should the detector handle stale data?

We need a clear policy for:

- how long a price remains valid
- whether missing exchanges block comparisons
- how fees are modeled
- how thresholds are configured

This is where correctness and demo quality will start to matter.

### 8. When should we add Redis and TimescaleDB?

The recommendation is:

- not in the first vertical slice
- Redis after we need fast read models
- TimescaleDB after signals are being emitted consistently

### 9. When do we switch from Compose to Kubernetes work?

The recommendation is:

- stay in Compose until one real end-to-end flow is stable
- move to Kubernetes only after the service boundaries are proven

That avoids solving deployment problems before the pipeline behavior is settled.

## Recommended Immediate Priorities

If we want to move efficiently, the immediate priorities should be:

1. clean up local configuration so broker addresses are not hardcoded inconsistently
2. create a shared internal package for Kafka/config/message helpers
3. implement one real ingestor
4. implement one real normalizer
5. wire a first detector path

## Summary

The project is in a good place conceptually. The architecture is coherent, the message contracts are already moving in the right direction, and the tooling choices are appropriate for a distributed streaming system.

The main gap is that the runtime pipeline has not been built yet beyond a toy producer/consumer example.

That means the right next move is not adding everything at once. The right next move is building one real vertical slice that proves:

- live ingestion
- Kafka transport
- normalization
- detection
- signal emission

Once that slice exists, the remaining layers become much easier to implement with confidence.
