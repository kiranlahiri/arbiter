SHELL := /bin/bash

.PHONY: help up up-minimal down logs logs-follow gen-protos \
run-producer run-consumer compose-run-producer compose-run-consumer \
compose-up-dev compose-down-dev

help:
	@echo "Makefile targets:"
	@echo "  up-minimal        Start zookeeper, kafka, schema-registry"
	@echo "  up                Start full dev stack (includes kafdrop)"
	@echo "  down              Stop and remove all compose services"
	@echo "  logs              Show recent logs for core services"
	@echo "  logs-follow       Follow logs for core services"
	@echo "  gen-protos        Generate Go protobufs (requires protoc + protoc-gen-go)"
	@echo "  compose-run-producer  Run producer inside compose network (one-off)"
	@echo "  compose-run-consumer  Run consumer inside compose network (one-off)"
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

## Run Go examples inside compose network (one-off)
compose-run-producer:
	docker compose run --rm producer-dev

compose-run-consumer:
	docker compose run --rm consumer-dev

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
