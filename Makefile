SHELL := /bin/bash

.PHONY: help up up-minimal down logs logs-follow gen-protos create-topics-dev \
run-producer run-consumer run-ingestor-coinbase run-normalizer run-detector \
compose-run-producer compose-run-consumer compose-run-ingestor-coinbase compose-run-normalizer compose-run-detector \
compose-up-dev compose-down-dev

help:
	@echo "Makefile targets:"
	@echo "  up-minimal        Start zookeeper, kafka, schema-registry"
	@echo "  up                Start full dev stack (includes kafdrop)"
	@echo "  down              Stop and remove all compose services"
	@echo "  logs              Show recent logs for core services"
	@echo "  logs-follow       Follow logs for core services"
	@echo "  gen-protos        Generate Go protobufs (requires protoc + protoc-gen-go)"
	@echo "  create-topics-dev Create the local Kafka topics used during development"
	@echo "  run-ingestor-coinbase  Run the Coinbase ingestor locally"
	@echo "  run-normalizer    Run the normalizer locally"
	@echo "  run-detector      Run the detector locally"
	@echo "  compose-run-producer  Run producer inside compose network (one-off)"
	@echo "  compose-run-consumer  Run consumer inside compose network (one-off)"
	@echo "  compose-run-ingestor-coinbase  Run Coinbase ingestor inside compose network (one-off)"
	@echo "  compose-run-normalizer  Run normalizer inside compose network (one-off)"
	@echo "  compose-run-detector  Run detector inside compose network (one-off)"
	@echo "  compose-up-dev    Launch producer-dev and consumer-dev as background services"
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
	docker compose exec kafka kafka-topics --bootstrap-server localhost:9092 --create --if-not-exists --topic normalized.ticks --partitions 1 --replication-factor 1
	docker compose exec kafka kafka-topics --bootstrap-server localhost:9092 --create --if-not-exists --topic arbitrage.signals --partitions 1 --replication-factor 1

## Run Go examples inside compose network (one-off)
compose-run-producer:
	docker compose run --rm producer-dev

compose-run-consumer:
	docker compose run --rm consumer-dev

compose-run-ingestor-coinbase:
	docker compose run --rm ingestor-coinbase-dev

compose-run-normalizer:
	docker compose run --rm normalizer-dev

compose-run-detector:
	docker compose run --rm detector-dev

## Bring up dev services in background
compose-up-dev:
	docker compose up -d consumer-dev producer-dev

compose-down-dev:
	docker compose stop consumer-dev producer-dev || true

## Run examples locally (requires Go installed locally)
run-consumer:
	go run ./cmd/consumer

run-producer:
	go run ./cmd/producer

run-ingestor-coinbase:
	go run ./cmd/ingestor-coinbase

run-normalizer:
	go run ./cmd/normalizer

run-detector:
	go run ./cmd/detector
