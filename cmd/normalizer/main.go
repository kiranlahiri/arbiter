package main

import (
	"context"
	"log"
	"os"
	"strings"
	"time"

	pb "github.com/kiran/arbiter/proto"
	"github.com/segmentio/kafka-go"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
)

const (
	defaultKafkaBroker     = "localhost:9092"
	defaultRawTopic        = "raw.ticks.coinbase"
	defaultNormalizedTopic = "normalized.ticks"
	defaultConsumerGroup   = "arbiter-normalizer"
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

func cloneMetadata(input map[string]string) map[string]string {
	if len(input) == 0 {
		return map[string]string{}
	}

	cloned := make(map[string]string, len(input))
	for key, value := range input {
		cloned[key] = value
	}

	return cloned
}

func normalizeSymbol(exchange, symbol string) string {
	// Keep the current product id as the canonical symbol for now.
	// We can introduce true cross-exchange symbol mapping once more feeds exist.
	return symbol
}

func normalizeRawTick(rawTopic string, rawTick *pb.RawTick, normalizedAt time.Time) *pb.NormalizedTick {
	meta := rawTick.GetMeta()
	normalized := &pb.NormalizedTick{
		Exchange:            meta.GetExchange(),
		Symbol:              normalizeSymbol(meta.GetExchange(), meta.GetSymbol()),
		Bid:                 rawTick.GetBid(),
		Ask:                 rawTick.GetAsk(),
		TimestampExchange:   meta.GetTimestampExchange(),
		TimestampReceived:   meta.GetTimestampIngestorReceived(),
		TimestampNormalized: timestamppb.New(normalizedAt),
		SourceSequenceId:    meta.GetSequenceId(),
		RawTopic:            rawTopic,
		Metadata:            cloneMetadata(rawTick.GetMetadata()),
	}

	normalized.Metadata["source"] = meta.GetSource()
	normalized.Metadata["normalized_by"] = "arbiter-normalizer"

	return normalized
}

func main() {
	rawTopic := envOrDefault("RAW_TICKS_TOPIC", defaultRawTopic)
	normalizedTopic := envOrDefault("NORMALIZED_TICKS_TOPIC", defaultNormalizedTopic)
	groupID := envOrDefault("KAFKA_GROUP_ID", defaultConsumerGroup)

	reader := kafka.NewReader(kafka.ReaderConfig{
		Brokers: kafkaBrokers(),
		GroupID: groupID,
		Topic:   rawTopic,
	})
	defer reader.Close()

	writer := kafka.NewWriter(kafka.WriterConfig{
		Brokers:  kafkaBrokers(),
		Topic:    normalizedTopic,
		Balancer: &kafka.Hash{},
	})
	defer writer.Close()

	log.Printf(
		"starting normalizer raw_topic=%s normalized_topic=%s group_id=%s brokers=%s",
		rawTopic,
		normalizedTopic,
		groupID,
		strings.Join(kafkaBrokers(), ","),
	)

	ctx := context.Background()
	for {
		message, err := reader.ReadMessage(ctx)
		if err != nil {
			log.Printf("read error: %v", err)
			break
		}

		var rawTick pb.RawTick
		if err := proto.Unmarshal(message.Value, &rawTick); err != nil {
			log.Printf("failed to unmarshal raw tick: %v", err)
			continue
		}

		normalizedTick := normalizeRawTick(rawTopic, &rawTick, time.Now().UTC())
		encoded, err := proto.Marshal(normalizedTick)
		if err != nil {
			log.Printf("failed to marshal normalized tick: %v", err)
			continue
		}

		writeCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		err = writer.WriteMessages(writeCtx, kafka.Message{
			Key:   []byte(normalizedTick.GetSymbol()),
			Value: encoded,
			Time:  time.Now().UTC(),
		})
		cancel()
		if err != nil {
			log.Printf("failed to publish normalized tick: %v", err)
			continue
		}

		log.Printf(
			"published normalized tick exchange=%s symbol=%s bid=%0.2f ask=%0.2f",
			normalizedTick.GetExchange(),
			normalizedTick.GetSymbol(),
			normalizedTick.GetBid(),
			normalizedTick.GetAsk(),
		)
	}
}
