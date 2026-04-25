package main

import (
	"context"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	pb "github.com/kiran/arbiter/proto"
	"github.com/segmentio/kafka-go"
	"google.golang.org/protobuf/proto"
)

const (
	defaultKafkaBroker   = "localhost:9092"
	defaultConsumerGroup = "arbiter-signal-consumer"
	defaultSignalsTopic  = "arbitrage.signals"
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

func formatTimestamp(ts time.Time) string {
	if ts.IsZero() {
		return "unknown"
	}
	return ts.Format(time.RFC3339Nano)
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

func main() {
	groupID := envOrDefault("KAFKA_GROUP_ID", defaultConsumerGroup)
	topic := envOrDefault("SIGNALS_TOPIC", defaultSignalsTopic)

	reader := kafka.NewReader(kafka.ReaderConfig{
		Brokers:     kafkaBrokers(),
		GroupID:     groupID,
		Topic:       topic,
		StartOffset: startOffsetEnv("KAFKA_START_OFFSET", kafka.LastOffset),
	})
	defer reader.Close()

	fmt.Printf("signal consumer subscribed to %s with group %s, waiting for opportunities...\n", topic, groupID)

	ctx := context.Background()
	for {
		message, err := reader.ReadMessage(ctx)
		if err != nil {
			fmt.Printf("read error: %v\n", err)
			break
		}

		var signal pb.Signal
		if err := proto.Unmarshal(message.Value, &signal); err != nil {
			fmt.Printf("failed to unmarshal signal: %v\n", err)
			continue
		}

		opportunityAt := signal.GetTimestampOpportunity().AsTime()
		quoteGapMs := metadataInt64(signal.GetMetadata(), "quote_gap_ms")
		buyQuoteAgeMs := metadataInt64(signal.GetMetadata(), "buy_quote_age_ms")
		sellQuoteAgeMs := metadataInt64(signal.GetMetadata(), "sell_quote_age_ms")
		oldestQuoteAgeMs := metadataInt64(signal.GetMetadata(), "oldest_quote_age_ms")
		if oldestQuoteAgeMs == 0 {
			// Older signals may only carry the legacy ingest_to_detect_ms field.
			oldestQuoteAgeMs = metadataInt64(signal.GetMetadata(), "ingest_to_detect_ms")
		}
		fmt.Printf(
			"%s | %s | buy %s @ %.2f | sell %s @ %.2f | spread %.2f | profit %.2f | quote gap %dms | oldest quote age %dms | buy age %dms | sell age %dms\n",
			formatTimestamp(opportunityAt),
			signal.GetSymbol(),
			signal.GetBuyExchange(),
			signal.GetBuyPrice(),
			signal.GetSellExchange(),
			signal.GetSellPrice(),
			signal.GetSpread(),
			signal.GetFeeAdjustedProfit(),
			quoteGapMs,
			oldestQuoteAgeMs,
			buyQuoteAgeMs,
			sellQuoteAgeMs,
		)
	}
}
