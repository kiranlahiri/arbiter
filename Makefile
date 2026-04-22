SHELL := /bin/bash

.PHONY: help up up-minimal down logs logs-follow gen-protos create-topics-dev \
create-topics-live \
run-producer run-consumer run-signal-consumer run-ingestor-coinbase run-ingestor-kraken run-normalizer run-detector \
compose-run-producer compose-run-consumer compose-run-signal-consumer compose-run-ingestor-coinbase compose-run-ingestor-kraken compose-run-normalizer compose-run-normalizer-kraken compose-run-detector \
compose-up-dev compose-down-dev compose-up-pipeline compose-down-pipeline logs-pipeline \
compose-up-pipeline-live compose-down-pipeline-live logs-pipeline-live

help:
	@echo "Makefile targets:"
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
	@echo "  compose-up-dev    Launch producer-dev and consumer-dev as background services"
	@echo "  compose-up-pipeline Start both ingestors, both normalizers, and detector as long-lived services"
	@echo "  compose-down-pipeline Stop the long-lived pipeline services"
	@echo "  logs-pipeline     Follow logs for the live pipeline services"
	@echo "  compose-up-pipeline-live Start the pipeline against isolated live-validation topics"
	@echo "  compose-down-pipeline-live Stop the isolated live-validation pipeline"
	@echo "  logs-pipeline-live Follow logs for the isolated live-validation pipeline"
	@echo "  compose-down-dev  Stop background dev services"

## Start minimal infra
up-minimal:
	docker compose up -d zookeeper kafka schema-registry

## Start full stack (includes UI)
up:
	docker compose up -d

down:
	docker compose down --volumes --remove-orphans

logs:
	docker compose logs --tail=200 kafka schema-registry zookeeper

logs-follow:
	docker compose logs -f --tail=200 kafka schema-registry kafdrop

gen-protos:
	./scripts/generate_protos.sh

create-topics-dev:
	docker compose exec kafka kafka-topics --bootstrap-server localhost:9092 --create --if-not-exists --topic raw.ticks.coinbase --partitions 1 --replication-factor 1
	docker compose exec kafka kafka-topics --bootstrap-server localhost:9092 --create --if-not-exists --topic raw.ticks.kraken --partitions 1 --replication-factor 1
	docker compose exec kafka kafka-topics --bootstrap-server localhost:9092 --create --if-not-exists --topic normalized.ticks --partitions 1 --replication-factor 1
	docker compose exec kafka kafka-topics --bootstrap-server localhost:9092 --create --if-not-exists --topic arbitrage.signals --partitions 1 --replication-factor 1

create-topics-live:
	docker compose exec kafka kafka-topics --bootstrap-server localhost:9092 --create --if-not-exists --topic raw.ticks.coinbase.live --partitions 1 --replication-factor 1
	docker compose exec kafka kafka-topics --bootstrap-server localhost:9092 --create --if-not-exists --topic raw.ticks.kraken.live --partitions 1 --replication-factor 1
	docker compose exec kafka kafka-topics --bootstrap-server localhost:9092 --create --if-not-exists --topic normalized.ticks.live --partitions 1 --replication-factor 1
	docker compose exec kafka kafka-topics --bootstrap-server localhost:9092 --create --if-not-exists --topic arbitrage.signals.live --partitions 1 --replication-factor 1

## Run Go examples inside compose network (one-off)
compose-run-producer:
	docker compose run --rm producer-dev

compose-run-consumer:
	docker compose run --rm consumer-dev

compose-run-signal-consumer:
	docker compose run --rm signal-consumer-dev

compose-run-ingestor-coinbase:
	docker compose run --rm ingestor-coinbase-dev

compose-run-ingestor-kraken:
	docker compose run --rm ingestor-kraken-dev

compose-run-normalizer:
	docker compose run --rm normalizer-dev

compose-run-normalizer-kraken:
	docker compose run --rm normalizer-kraken-dev

compose-run-detector:
	docker compose run --rm detector-dev

## Bring up dev services in background
compose-up-dev:
	docker compose up -d consumer-dev producer-dev

compose-up-pipeline:
	docker compose up -d ingestor-coinbase-dev ingestor-kraken-dev normalizer-dev normalizer-kraken-dev detector-dev

compose-down-pipeline:
	docker compose stop ingestor-coinbase-dev ingestor-kraken-dev normalizer-dev normalizer-kraken-dev detector-dev || true

logs-pipeline:
	docker compose logs -f --tail=200 ingestor-coinbase-dev ingestor-kraken-dev normalizer-dev normalizer-kraken-dev detector-dev

compose-up-pipeline-live:
	RAW_TICKS_COINBASE_TOPIC=raw.ticks.coinbase.live RAW_TICKS_KRAKEN_TOPIC=raw.ticks.kraken.live NORMALIZED_TICKS_TOPIC=normalized.ticks.live SIGNALS_TOPIC=arbitrage.signals.live NORMALIZER_COINBASE_GROUP_ID=arbiter-normalizer-live NORMALIZER_KRAKEN_GROUP_ID=arbiter-normalizer-kraken-live DETECTOR_GROUP_ID=arbiter-detector-live docker compose up -d ingestor-coinbase-dev ingestor-kraken-dev normalizer-dev normalizer-kraken-dev detector-dev

compose-down-pipeline-live:
	RAW_TICKS_COINBASE_TOPIC=raw.ticks.coinbase.live RAW_TICKS_KRAKEN_TOPIC=raw.ticks.kraken.live NORMALIZED_TICKS_TOPIC=normalized.ticks.live SIGNALS_TOPIC=arbitrage.signals.live NORMALIZER_COINBASE_GROUP_ID=arbiter-normalizer-live NORMALIZER_KRAKEN_GROUP_ID=arbiter-normalizer-kraken-live DETECTOR_GROUP_ID=arbiter-detector-live docker compose stop ingestor-coinbase-dev ingestor-kraken-dev normalizer-dev normalizer-kraken-dev detector-dev || true

logs-pipeline-live:
	RAW_TICKS_COINBASE_TOPIC=raw.ticks.coinbase.live RAW_TICKS_KRAKEN_TOPIC=raw.ticks.kraken.live NORMALIZED_TICKS_TOPIC=normalized.ticks.live SIGNALS_TOPIC=arbitrage.signals.live NORMALIZER_COINBASE_GROUP_ID=arbiter-normalizer-live NORMALIZER_KRAKEN_GROUP_ID=arbiter-normalizer-kraken-live DETECTOR_GROUP_ID=arbiter-detector-live docker compose logs -f --tail=200 ingestor-coinbase-dev ingestor-kraken-dev normalizer-dev normalizer-kraken-dev detector-dev

compose-down-dev:
	docker compose stop consumer-dev producer-dev || true

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
