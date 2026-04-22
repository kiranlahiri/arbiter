package main

import (
	"context"
	"fmt"
	"os"
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

func formatTimestamp(ts time.Time) string {
	if ts.IsZero() {
		return "unknown"
	}
	return ts.Format(time.RFC3339)
}

func main() {
	groupID := envOrDefault("KAFKA_GROUP_ID", defaultConsumerGroup)
	topic := envOrDefault("SIGNALS_TOPIC", defaultSignalsTopic)

	reader := kafka.NewReader(kafka.ReaderConfig{
		Brokers: kafkaBrokers(),
		GroupID: groupID,
		Topic:   topic,
	})
	defer reader.Close()

	fmt.Printf("signal consumer subscribed to %s, waiting for opportunities...\n", topic)

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
		fmt.Printf(
			"%s | %s | buy %s @ %.2f | sell %s @ %.2f | spread %.2f | profit %.2f | latency %dms\n",
			formatTimestamp(opportunityAt),
			signal.GetSymbol(),
			signal.GetBuyExchange(),
			signal.GetBuyPrice(),
			signal.GetSellExchange(),
			signal.GetSellPrice(),
			signal.GetSpread(),
			signal.GetFeeAdjustedProfit(),
			signal.GetLatencyMs(),
		)
	}
}
