package main

import (
	"context"
	"encoding/json"
	"log"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	pb "github.com/kiran/arbiter/proto"
	"github.com/segmentio/kafka-go"
	"google.golang.org/protobuf/proto"
)

const (
	defaultKafkaBroker       = "localhost:9092"
	defaultSignalsTopic      = "arbitrage.signals"
	defaultSignalWriterGroup = "arbiter-signal-writer"
	defaultDatabaseURL       = "postgres://postgres:postgres@localhost:5432/arbiter?sslmode=disable"
)

func kafkaBrokers() []string {
	brokers := os.Getenv("KAFKA_BROKERS")
	if brokers == "" {
		return []string{defaultKafkaBroker}
	}

	parts := strings.Split(brokers, ",")
	resolved := make([]string, 0, len(parts))
	for _, part := range parts {
		broker := strings.TrimSpace(part)
		if broker != "" {
			resolved = append(resolved, broker)
		}
	}

	if len(resolved) == 0 {
		return []string{defaultKafkaBroker}
	}

	return resolved
}

func envOrDefault(key, fallback string) string {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}
	return value
}

func startOffsetEnv(key string, fallback int64) int64 {
	value := strings.TrimSpace(strings.ToLower(os.Getenv(key)))
	switch value {
	case "", "latest":
		return fallback
	case "first", "earliest":
		return kafka.FirstOffset
	default:
		return fallback
	}
}

func metadataInt64(metadata map[string]string, key string) int64 {
	if metadata == nil {
		return 0
	}

	value := strings.TrimSpace(metadata[key])
	if value == "" {
		return 0
	}

	parsed, err := strconv.ParseInt(value, 10, 64)
	if err != nil {
		return 0
	}

	return parsed
}

func ensureSchema(ctx context.Context, pool *pgxpool.Pool) error {
	const query = `
CREATE TABLE IF NOT EXISTS signals (
    id BIGSERIAL PRIMARY KEY,
    kafka_topic TEXT NOT NULL,
    kafka_partition INTEGER NOT NULL,
    kafka_offset BIGINT NOT NULL,
    symbol TEXT NOT NULL,
    buy_exchange TEXT NOT NULL,
    sell_exchange TEXT NOT NULL,
    buy_price DOUBLE PRECISION NOT NULL,
    sell_price DOUBLE PRECISION NOT NULL,
    spread DOUBLE PRECISION NOT NULL,
    fee_adjusted_profit DOUBLE PRECISION NOT NULL,
    timestamp_opportunity TIMESTAMPTZ NOT NULL,
    timestamp_tick_received TIMESTAMPTZ,
    quote_gap_ms BIGINT NOT NULL DEFAULT 0,
    buy_quote_age_ms BIGINT NOT NULL DEFAULT 0,
    sell_quote_age_ms BIGINT NOT NULL DEFAULT 0,
    oldest_quote_age_ms BIGINT NOT NULL DEFAULT 0,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (kafka_topic, kafka_partition, kafka_offset)
);

CREATE INDEX IF NOT EXISTS signals_timestamp_opportunity_idx
    ON signals (timestamp_opportunity DESC);

CREATE INDEX IF NOT EXISTS signals_symbol_timestamp_idx
    ON signals (symbol, timestamp_opportunity DESC);
`

	_, err := pool.Exec(ctx, query)
	return err
}

func insertSignal(ctx context.Context, pool *pgxpool.Pool, message kafka.Message, signal *pb.Signal) error {
	metadataJSON, err := json.Marshal(signal.GetMetadata())
	if err != nil {
		return err
	}

	_, err = pool.Exec(ctx, `
INSERT INTO signals (
    kafka_topic,
    kafka_partition,
    kafka_offset,
    symbol,
    buy_exchange,
    sell_exchange,
    buy_price,
    sell_price,
    spread,
    fee_adjusted_profit,
    timestamp_opportunity,
    timestamp_tick_received,
    quote_gap_ms,
    buy_quote_age_ms,
    sell_quote_age_ms,
    oldest_quote_age_ms,
    metadata
)
VALUES (
    $1, $2, $3, $4, $5, $6, $7, $8, $9, $10,
    $11, $12, $13, $14, $15, $16, $17::jsonb
)
ON CONFLICT (kafka_topic, kafka_partition, kafka_offset) DO NOTHING
`,
		message.Topic,
		message.Partition,
		message.Offset,
		signal.GetSymbol(),
		signal.GetBuyExchange(),
		signal.GetSellExchange(),
		signal.GetBuyPrice(),
		signal.GetSellPrice(),
		signal.GetSpread(),
		signal.GetFeeAdjustedProfit(),
		signal.GetTimestampOpportunity().AsTime(),
		signal.GetTimestampTickReceived().AsTime(),
		metadataInt64(signal.GetMetadata(), "quote_gap_ms"),
		metadataInt64(signal.GetMetadata(), "buy_quote_age_ms"),
		metadataInt64(signal.GetMetadata(), "sell_quote_age_ms"),
		metadataInt64(signal.GetMetadata(), "oldest_quote_age_ms"),
		string(metadataJSON),
	)

	return err
}

func main() {
	signalsTopic := envOrDefault("SIGNALS_TOPIC", defaultSignalsTopic)
	groupID := envOrDefault("KAFKA_GROUP_ID", defaultSignalWriterGroup)
	databaseURL := envOrDefault("DATABASE_URL", defaultDatabaseURL)

	ctx := context.Background()

	pool, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		log.Fatalf("failed to connect to postgres: %v", err)
	}
	defer pool.Close()

	if err := ensureSchema(ctx, pool); err != nil {
		log.Fatalf("failed to ensure signals schema: %v", err)
	}

	reader := kafka.NewReader(kafka.ReaderConfig{
		Brokers:     kafkaBrokers(),
		GroupID:     groupID,
		Topic:       signalsTopic,
		StartOffset: startOffsetEnv("KAFKA_START_OFFSET", kafka.LastOffset),
	})
	defer reader.Close()

	log.Printf(
		"starting signal writer signals_topic=%s group_id=%s brokers=%s database=%s",
		signalsTopic,
		groupID,
		strings.Join(kafkaBrokers(), ","),
		databaseURL,
	)

	processed := 0
	for {
		message, err := reader.ReadMessage(ctx)
		if err != nil {
			log.Printf("read error: %v", err)
			break
		}

		var signal pb.Signal
		if err := proto.Unmarshal(message.Value, &signal); err != nil {
			log.Printf(
				"failed to unmarshal signal topic=%s partition=%d offset=%d err=%v",
				message.Topic,
				message.Partition,
				message.Offset,
				err,
			)
			continue
		}

		insertCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
		err = insertSignal(insertCtx, pool, message, &signal)
		cancel()
		if err != nil {
			log.Printf(
				"failed to persist signal topic=%s partition=%d offset=%d err=%v",
				message.Topic,
				message.Partition,
				message.Offset,
				err,
			)
			continue
		}

		processed++
		if processed == 1 || processed%25 == 0 {
			log.Printf(
				"persisted signals processed=%d last_symbol=%s last_buy=%s last_sell=%s last_spread=%0.2f",
				processed,
				signal.GetSymbol(),
				signal.GetBuyExchange(),
				signal.GetSellExchange(),
				signal.GetSpread(),
			)
		}
	}
}
