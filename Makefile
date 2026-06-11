SHELL := /bin/bash

ENV_FILE ?= .env.local
COMPOSE := docker compose --env-file $(ENV_FILE)

LIVE_RAW_TICKS_COINBASE_TOPIC ?= raw.ticks.coinbase.live
LIVE_RAW_TICKS_KRAKEN_TOPIC ?= raw.ticks.kraken.live
LIVE_NORMALIZED_TICKS_TOPIC ?= normalized.ticks.live
LIVE_SIGNALS_TOPIC ?= arbitrage.signals.live
LIVE_NORMALIZER_COINBASE_GROUP_ID ?= arbiter-normalizer-live
LIVE_NORMALIZER_KRAKEN_GROUP_ID ?= arbiter-normalizer-kraken-live
LIVE_DETECTOR_GROUP_ID ?= arbiter-detector-live
LIVE_NORMALIZER_START_OFFSET ?= latest
LIVE_DETECTOR_START_OFFSET ?= latest
LIVE_MAX_QUOTE_GAP_MS ?= 5000

.PHONY: help up up-minimal down logs logs-follow gen-protos create-topics-dev \
create-topics-live \
run-producer run-consumer run-signal-consumer run-ingestor-coinbase run-ingestor-kraken run-normalizer run-detector \
run-signal-writer run-api \
compose-run-producer compose-run-consumer compose-run-signal-consumer compose-run-ingestor-coinbase compose-run-ingestor-kraken compose-run-normalizer compose-run-normalizer-kraken compose-run-detector compose-run-signal-writer compose-run-api \
compose-up-dev compose-down-dev compose-up-pipeline compose-down-pipeline logs-pipeline \
compose-up-pipeline-live compose-up-pipeline-live-fresh compose-down-pipeline-live logs-pipeline-live

help:
	@echo "Makefile targets:"
	@echo "  ENV_FILE=$(ENV_FILE)"
	@echo "  up-minimal        Start zookeeper, kafka, schema-registry"
	@echo "  up                Start full dev stack (includes kafdrop)"
	@echo "  down              Stop and remove all compose services"
	@echo "  logs              Show recent logs for core services"
	@echo "  logs-follow       Follow logs for core services"
	@echo "  gen-protos        Generate Go protobufs (requires protoc + protoc-gen-go)"
	@echo "  create-topics-dev Create the local Kafka topics used during development"
	@echo "  create-topics-live Create an isolated set of Kafka topics for clean live validation"
	@echo "  run-ingestor-coinbase  Run the Coinbase ingestor locally"
	@echo "  run-ingestor-kraken Run the Kraken ingestor locally"
	@echo "  run-normalizer    Run the normalizer locally"
	@echo "  run-detector      Run the detector locally"
	@echo "  compose-run-producer  Run producer inside compose network (one-off)"
	@echo "  compose-run-consumer  Run consumer inside compose network (one-off)"
	@echo "  compose-run-signal-consumer  Run signal consumer inside compose network (one-off)"
	@echo "  compose-run-ingestor-coinbase  Run Coinbase ingestor inside compose network (one-off)"
	@echo "  compose-run-ingestor-kraken  Run Kraken ingestor inside compose network (one-off)"
	@echo "  compose-run-normalizer  Run normalizer inside compose network (one-off)"
	@echo "  compose-run-normalizer-kraken  Run Kraken normalizer inside compose network (one-off)"
	@echo "  compose-run-detector  Run detector inside compose network (one-off)"
	@echo "  compose-run-signal-writer  Run signal writer inside compose network (one-off)"
	@echo "  compose-run-api  Run API inside compose network (one-off)"
	@echo "  compose-up-dev    Launch producer-dev and consumer-dev as background services"
	@echo "  compose-up-pipeline Start ingestors, normalizers, detector, Postgres, signal writer, and API as long-lived services"
	@echo "  compose-down-pipeline Stop the long-lived pipeline services"
	@echo "  logs-pipeline     Follow logs for the live pipeline services"
	@echo "  compose-up-pipeline-live Start the pipeline against isolated live-validation topics"
	@echo "  compose-up-pipeline-live-fresh Start the live-validation pipeline with fresh consumer groups automatically"
	@echo "  compose-down-pipeline-live Stop the isolated live-validation pipeline"
	@echo "  logs-pipeline-live Follow logs for the isolated live-validation pipeline"
	@echo "  compose-down-dev  Stop background dev services"
	@echo "  Example fresh live restart:"
	@echo "    LIVE_NORMALIZER_COINBASE_GROUP_ID=arbiter-normalizer-live-$$(date +%s) \\"
	@echo "    LIVE_NORMALIZER_KRAKEN_GROUP_ID=arbiter-normalizer-kraken-live-$$(date +%s) \\"
	@echo "    LIVE_DETECTOR_GROUP_ID=arbiter-detector-live-$$(date +%s) \\"
	@echo "    make compose-up-pipeline-live"
	@echo "  Local config file: $(ENV_FILE)"

## Start minimal infra
up-minimal:
	$(COMPOSE) up -d zookeeper kafka schema-registry

## Start full stack (includes UI)
up:
	$(COMPOSE) up -d

down:
	$(COMPOSE) down --volumes --remove-orphans

logs:
	$(COMPOSE) logs --tail=200 kafka schema-registry zookeeper

logs-follow:
	$(COMPOSE) logs -f --tail=200 kafka schema-registry kafdrop

gen-protos:
	./scripts/generate_protos.sh

create-topics-dev:
	$(COMPOSE) exec kafka kafka-topics --bootstrap-server localhost:9092 --create --if-not-exists --topic raw.ticks.coinbase --partitions 1 --replication-factor 1
	$(COMPOSE) exec kafka kafka-topics --bootstrap-server localhost:9092 --create --if-not-exists --topic raw.ticks.kraken --partitions 1 --replication-factor 1
	$(COMPOSE) exec kafka kafka-topics --bootstrap-server localhost:9092 --create --if-not-exists --topic normalized.ticks --partitions 1 --replication-factor 1
	$(COMPOSE) exec kafka kafka-topics --bootstrap-server localhost:9092 --create --if-not-exists --topic arbitrage.signals --partitions 1 --replication-factor 1

create-topics-live:
	$(COMPOSE) exec kafka kafka-topics --bootstrap-server localhost:9092 --create --if-not-exists --topic raw.ticks.coinbase.live --partitions 1 --replication-factor 1
	$(COMPOSE) exec kafka kafka-topics --bootstrap-server localhost:9092 --create --if-not-exists --topic raw.ticks.kraken.live --partitions 1 --replication-factor 1
	$(COMPOSE) exec kafka kafka-topics --bootstrap-server localhost:9092 --create --if-not-exists --topic normalized.ticks.live --partitions 1 --replication-factor 1
	$(COMPOSE) exec kafka kafka-topics --bootstrap-server localhost:9092 --create --if-not-exists --topic arbitrage.signals.live --partitions 1 --replication-factor 1

## Run Go examples inside compose network (one-off)
compose-run-producer:
	$(COMPOSE) run --rm producer-dev

compose-run-consumer:
	$(COMPOSE) run --rm consumer-dev

compose-run-signal-consumer:
	$(COMPOSE) run --rm signal-consumer-dev

compose-run-ingestor-coinbase:
	$(COMPOSE) run --rm ingestor-coinbase-dev

compose-run-ingestor-kraken:
	$(COMPOSE) run --rm ingestor-kraken-dev

compose-run-normalizer:
	$(COMPOSE) run --rm normalizer-dev

compose-run-normalizer-kraken:
	$(COMPOSE) run --rm normalizer-kraken-dev

compose-run-detector:
	$(COMPOSE) run --rm detector-dev

compose-run-signal-writer:
	$(COMPOSE) run --rm signal-writer-dev

compose-run-api:
	$(COMPOSE) run --rm api-dev

## Bring up dev services in background
compose-up-dev:
	$(COMPOSE) up -d consumer-dev producer-dev

compose-up-pipeline:
	$(COMPOSE) up -d postgres ingestor-coinbase-dev ingestor-kraken-dev normalizer-dev normalizer-kraken-dev detector-dev signal-writer-dev api-dev

compose-down-pipeline:
	$(COMPOSE) stop ingestor-coinbase-dev ingestor-kraken-dev normalizer-dev normalizer-kraken-dev detector-dev signal-writer-dev api-dev postgres || true

logs-pipeline:
	$(COMPOSE) logs -f --tail=200 ingestor-coinbase-dev ingestor-kraken-dev normalizer-dev normalizer-kraken-dev detector-dev signal-writer-dev api-dev postgres

compose-up-pipeline-live:
	RAW_TICKS_COINBASE_TOPIC=$(LIVE_RAW_TICKS_COINBASE_TOPIC) RAW_TICKS_KRAKEN_TOPIC=$(LIVE_RAW_TICKS_KRAKEN_TOPIC) NORMALIZED_TICKS_TOPIC=$(LIVE_NORMALIZED_TICKS_TOPIC) SIGNALS_TOPIC=$(LIVE_SIGNALS_TOPIC) NORMALIZER_COINBASE_GROUP_ID=$(LIVE_NORMALIZER_COINBASE_GROUP_ID) NORMALIZER_KRAKEN_GROUP_ID=$(LIVE_NORMALIZER_KRAKEN_GROUP_ID) DETECTOR_GROUP_ID=$(LIVE_DETECTOR_GROUP_ID) SIGNAL_WRITER_GROUP_ID=arbiter-signal-writer-live SIGNAL_WRITER_START_OFFSET=latest NORMALIZER_START_OFFSET=$(LIVE_NORMALIZER_START_OFFSET) DETECTOR_START_OFFSET=$(LIVE_DETECTOR_START_OFFSET) MAX_QUOTE_GAP_MS=$(LIVE_MAX_QUOTE_GAP_MS) $(COMPOSE) up -d postgres ingestor-coinbase-dev ingestor-kraken-dev normalizer-dev normalizer-kraken-dev detector-dev signal-writer-dev api-dev

compose-up-pipeline-live-fresh:
	@RUN_ID=$$(date +%s); \
	RAW_TICKS_COINBASE_TOPIC=$(LIVE_RAW_TICKS_COINBASE_TOPIC) \
	RAW_TICKS_KRAKEN_TOPIC=$(LIVE_RAW_TICKS_KRAKEN_TOPIC) \
	NORMALIZED_TICKS_TOPIC=$(LIVE_NORMALIZED_TICKS_TOPIC) \
	SIGNALS_TOPIC=$(LIVE_SIGNALS_TOPIC) \
	NORMALIZER_COINBASE_GROUP_ID=arbiter-normalizer-live-$$RUN_ID \
	NORMALIZER_KRAKEN_GROUP_ID=arbiter-normalizer-kraken-live-$$RUN_ID \
	DETECTOR_GROUP_ID=arbiter-detector-live-$$RUN_ID \
	SIGNAL_WRITER_GROUP_ID=arbiter-signal-writer-live \
	SIGNAL_WRITER_START_OFFSET=latest \
	NORMALIZER_START_OFFSET=latest \
	DETECTOR_START_OFFSET=latest \
	MAX_QUOTE_GAP_MS=$(LIVE_MAX_QUOTE_GAP_MS) \
	$(COMPOSE) up -d postgres ingestor-coinbase-dev ingestor-kraken-dev normalizer-dev normalizer-kraken-dev detector-dev signal-writer-dev api-dev; \
	echo "Started live pipeline with RUN_ID=$$RUN_ID"

compose-down-pipeline-live:
	RAW_TICKS_COINBASE_TOPIC=$(LIVE_RAW_TICKS_COINBASE_TOPIC) RAW_TICKS_KRAKEN_TOPIC=$(LIVE_RAW_TICKS_KRAKEN_TOPIC) NORMALIZED_TICKS_TOPIC=$(LIVE_NORMALIZED_TICKS_TOPIC) SIGNALS_TOPIC=$(LIVE_SIGNALS_TOPIC) NORMALIZER_COINBASE_GROUP_ID=$(LIVE_NORMALIZER_COINBASE_GROUP_ID) NORMALIZER_KRAKEN_GROUP_ID=$(LIVE_NORMALIZER_KRAKEN_GROUP_ID) DETECTOR_GROUP_ID=$(LIVE_DETECTOR_GROUP_ID) SIGNAL_WRITER_GROUP_ID=arbiter-signal-writer-live SIGNAL_WRITER_START_OFFSET=latest NORMALIZER_START_OFFSET=$(LIVE_NORMALIZER_START_OFFSET) DETECTOR_START_OFFSET=$(LIVE_DETECTOR_START_OFFSET) MAX_QUOTE_GAP_MS=$(LIVE_MAX_QUOTE_GAP_MS) $(COMPOSE) stop ingestor-coinbase-dev ingestor-kraken-dev normalizer-dev normalizer-kraken-dev detector-dev signal-writer-dev api-dev postgres || true

logs-pipeline-live:
	RAW_TICKS_COINBASE_TOPIC=$(LIVE_RAW_TICKS_COINBASE_TOPIC) RAW_TICKS_KRAKEN_TOPIC=$(LIVE_RAW_TICKS_KRAKEN_TOPIC) NORMALIZED_TICKS_TOPIC=$(LIVE_NORMALIZED_TICKS_TOPIC) SIGNALS_TOPIC=$(LIVE_SIGNALS_TOPIC) NORMALIZER_COINBASE_GROUP_ID=$(LIVE_NORMALIZER_COINBASE_GROUP_ID) NORMALIZER_KRAKEN_GROUP_ID=$(LIVE_NORMALIZER_KRAKEN_GROUP_ID) DETECTOR_GROUP_ID=$(LIVE_DETECTOR_GROUP_ID) SIGNAL_WRITER_GROUP_ID=arbiter-signal-writer-live SIGNAL_WRITER_START_OFFSET=latest NORMALIZER_START_OFFSET=$(LIVE_NORMALIZER_START_OFFSET) DETECTOR_START_OFFSET=$(LIVE_DETECTOR_START_OFFSET) MAX_QUOTE_GAP_MS=$(LIVE_MAX_QUOTE_GAP_MS) $(COMPOSE) logs -f --tail=200 ingestor-coinbase-dev ingestor-kraken-dev normalizer-dev normalizer-kraken-dev detector-dev signal-writer-dev api-dev postgres

compose-down-dev:
	$(COMPOSE) stop consumer-dev producer-dev || true

## Run examples locally (requires Go installed locally)
run-consumer:
	go run ./cmd/consumer

run-signal-consumer:
	go run ./cmd/signal-consumer

run-producer:
	go run ./cmd/producer

run-ingestor-coinbase:
	go run ./cmd/ingestor-coinbase

run-ingestor-kraken:
	go run ./cmd/ingestor-kraken

run-normalizer:
	go run ./cmd/normalizer

run-detector:
	go run ./cmd/detector

run-signal-writer:
	go run ./cmd/signal-writer

run-api:
	go run ./cmd/api
