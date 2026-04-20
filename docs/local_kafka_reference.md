# Local Kafka & Schema Registry Quick Reference

Run these from the project root (`/home/kiran/Documents/Projects/Arbiter`).

## Start the dev stack

```bash
docker compose up -d
```

Broker address guide:

- Use `localhost:9092` when running Go commands on your host machine.
- Use `kafka:9092` when running from another container on the Compose network.
- The sample `producer-dev`, `consumer-dev`, and `ingestor-coinbase-dev` services set `KAFKA_BROKERS=kafka:9092` automatically.
- The sample `producer-dev`, `consumer-dev`, `ingestor-coinbase-dev`, `ingestor-kraken-dev`, `normalizer-dev`, `normalizer-kraken-dev`, and `detector-dev` services set `KAFKA_BROKERS=kafka:9092` automatically.

## Check running containers and logs

```bash
docker compose ps
docker compose logs --tail=200 schema-registry kafka zookeeper
```

## List Kafka topics

```bash
docker compose exec kafka kafka-topics --bootstrap-server localhost:9092 --list
```

## Create a topic (example)

```bash
docker compose exec kafka kafka-topics \
  --bootstrap-server localhost:9092 \
  --create --topic normalized.ticks --partitions 3 --replication-factor 1
```

Create the main local dev topics used by the repo:

```bash
docker compose exec kafka kafka-topics \
  --bootstrap-server localhost:9092 \
  --create --if-not-exists --topic raw.ticks.coinbase --partitions 1 --replication-factor 1

docker compose exec kafka kafka-topics \
  --bootstrap-server localhost:9092 \
  --create --if-not-exists --topic raw.ticks.kraken --partitions 1 --replication-factor 1

docker compose exec kafka kafka-topics \
  --bootstrap-server localhost:9092 \
  --create --if-not-exists --topic normalized.ticks --partitions 1 --replication-factor 1

docker compose exec kafka kafka-topics \
  --bootstrap-server localhost:9092 \
  --create --if-not-exists --topic arbitrage.signals --partitions 1 --replication-factor 1
```

## Produce a simple plaintext message

```bash
printf 'test-message\n' | docker compose exec -T kafka \
  kafka-console-producer --broker-list localhost:9092 --topic normalized.ticks
```

## Consume messages (from beginning, read 1 message)

```bash
docker compose exec kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 --topic normalized.ticks --from-beginning --max-messages 1
```

## Schema Registry checks

List registered subjects:

```bash
curl -s http://localhost:8081/subjects | jq .
```

Register a simple Protobuf schema (example):

```bash
curl -s -X POST -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  --data '{"schemaType":"PROTOBUF","schema":"syntax = \"proto3\"; package arbiter.proto; message TestProto { string msg = 1; }"}' \
  http://localhost:8081/subjects/test-proto-value/versions | jq .
```

Verify the subject versions:

```bash
curl -s http://localhost:8081/subjects/test-proto-value/versions | jq .
curl -s http://localhost:8081/subjects/test-proto-value/versions/1 | jq .
```

## Troubleshooting

- If `docker compose up -d` fails with socket errors, ensure your Docker context points to the running daemon:

```bash
docker context show
docker context use default
```

- View container logs for detailed errors:

```bash
docker compose logs kafka
docker compose logs schema-registry
```

- Watch logs for readiness (follow logs for core services):

```bash
docker compose logs -f --tail=200 kafka schema-registry kafdrop
```

## Run the Go examples inside the compose network (dev)

Run the consumer inside the compose network so it can resolve the `kafka` hostname directly:

```bash
# Run consumer (will exit on error or ctrl-c)
docker compose run --rm consumer-dev

# In another terminal run producer
docker compose run --rm producer-dev
```

Or run them as background services:

```bash
docker compose up -d consumer-dev producer-dev
docker compose logs -f consumer-dev producer-dev
```

Run the Coinbase ingestor inside the Compose network:

```bash
docker compose run --rm ingestor-coinbase-dev
```

Run the Kraken ingestor inside the Compose network:

```bash
docker compose run --rm ingestor-kraken-dev
```

Run the normalizer inside the Compose network:

```bash
docker compose run --rm normalizer-dev
docker compose run --rm normalizer-kraken-dev
```

Run the detector inside the Compose network:

```bash
docker compose run --rm detector-dev
```

## Run the Go examples on the host

The sample apps default to `localhost:9092` when `KAFKA_BROKERS` is not set:

```bash
go run ./cmd/consumer
go run ./cmd/producer
```

You can also override the brokers explicitly:

```bash
KAFKA_BROKERS=localhost:9092 go run ./cmd/consumer
KAFKA_BROKERS=localhost:9092 go run ./cmd/producer
KAFKA_BROKERS=localhost:9092 go run ./cmd/ingestor-coinbase
KAFKA_BROKERS=localhost:9092 go run ./cmd/ingestor-kraken
KAFKA_BROKERS=localhost:9092 go run ./cmd/normalizer
KAFKA_BROKERS=localhost:9092 go run ./cmd/detector
```

If you want a fresh consumer-group view of `normalized.ticks`, override the group id:

```bash
KAFKA_BROKERS=localhost:9092 KAFKA_GROUP_ID=arbiter-consumer-debug go run ./cmd/consumer
```

For this repo, the Compose-network path is the most reliable local dev workflow because the helper services are already configured to use `kafka:9092`.

---

Save this file for quick local reference while developing and testing the pipeline.
