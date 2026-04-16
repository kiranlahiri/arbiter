package main

import (
	"context"
	"fmt"
	"os"
	"strings"

	pb "github.com/kiran/arbiter/proto"
	"google.golang.org/protobuf/proto"

	"github.com/segmentio/kafka-go"
)

const (
	defaultKafkaBroker   = "localhost:9092"
	defaultConsumerGroup = "arbiter-consumer"
	defaultConsumerTopic = "normalized.ticks"
)

func kafkaBrokers() []string {
	// Allow the same binary to run either on the host or inside Docker Compose.
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

func main() {
	groupID := envOrDefault("KAFKA_GROUP_ID", defaultConsumerGroup)
	topic := envOrDefault("KAFKA_TOPIC", defaultConsumerTopic)

	// Subscribe to the normalized tick topic as a Kafka consumer group member.
	r := kafka.NewReader(kafka.ReaderConfig{
		Brokers: kafkaBrokers(),
		GroupID: groupID,
		Topic:   topic,
	})
	defer r.Close()

	fmt.Println("consumer subscribed, waiting for messages...")
	ctx := context.Background()
	for {
		// Block until Kafka delivers the next message from the topic.
		m, err := r.ReadMessage(ctx)
		if err != nil {
			fmt.Printf("read error: %v\n", err)
			break
		}

		var tick pb.NormalizedTick
		// Decode the protobuf bytes from Kafka back into a structured Go value.
		if err := proto.Unmarshal(m.Value, &tick); err != nil {
			fmt.Printf("failed to unmarshal: %v\n", err)
			continue
		}

		// Use the decoded fields like a normal Go struct.
		fmt.Printf("Received tick: %s %v/%v\n", tick.Symbol, tick.Bid, tick.Ask)
	}
}
