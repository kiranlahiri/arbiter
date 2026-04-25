package main

import (
	"context"
	"log"
	"os"
	"strconv"
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
	defaultLogEveryN       = 25
)

type serviceConfig struct {
	debug     bool
	logEveryN int
}

type quoteSnapshot struct {
	receivedAt time.Time
	bid        float64
	ask        float64
}

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

func boolEnv(key string, fallback bool) bool {
	value := strings.TrimSpace(strings.ToLower(os.Getenv(key)))
	switch value {
	case "":
		return fallback
	case "1", "true", "yes", "on":
		return true
	case "0", "false", "no", "off":
		return false
	default:
		return fallback
	}
}

func intEnv(key string, fallback int) int {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}

	parsed, err := strconv.Atoi(value)
	if err != nil || parsed <= 0 {
		return fallback
	}

	return parsed
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
	normalized := strings.ToUpper(strings.TrimSpace(symbol))
	normalized = strings.ReplaceAll(normalized, "/", "-")

	parts := strings.Split(normalized, "-")
	if len(parts) == 2 {
		if parts[0] == "XBT" {
			parts[0] = "BTC"
		}
		if parts[1] == "XBT" {
			parts[1] = "BTC"
		}
		return parts[0] + "-" + parts[1]
	}

	return normalized
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
	cfg := serviceConfig{
		debug:     boolEnv("NORMALIZER_DEBUG", false),
		logEveryN: intEnv("NORMALIZER_LOG_EVERY_N", defaultLogEveryN),
	}

	reader := kafka.NewReader(kafka.ReaderConfig{
		Brokers:     kafkaBrokers(),
		GroupID:     groupID,
		Topic:       rawTopic,
		StartOffset: startOffsetEnv("KAFKA_START_OFFSET", kafka.LastOffset),
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
	processedCount := 0
	lastByExchangeSymbol := map[string]quoteSnapshot{}
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

		processedCount++
		if cfg.debug {
			ingestorReceivedAt := normalizedTick.GetTimestampReceived().AsTime()
			normalizeLagMs := int64(0)
			if !ingestorReceivedAt.IsZero() {
				normalizeLagMs = normalizedTick.GetTimestampNormalized().AsTime().Sub(ingestorReceivedAt).Milliseconds()
			}

			key := normalizedTick.GetExchange() + "|" + normalizedTick.GetSymbol()
			lastSnapshot, hadLastSnapshot := lastByExchangeSymbol[key]
			sinceLastMs := int64(0)
			if hadLastSnapshot && !lastSnapshot.receivedAt.IsZero() && !ingestorReceivedAt.IsZero() {
				sinceLastMs = ingestorReceivedAt.Sub(lastSnapshot.receivedAt).Milliseconds()
			}
			bidChanged := !hadLastSnapshot || normalizedTick.GetBid() != lastSnapshot.bid
			askChanged := !hadLastSnapshot || normalizedTick.GetAsk() != lastSnapshot.ask

			log.Printf(
				"published normalized tick exchange=%s symbol=%s bid=%0.2f ask=%0.2f ingestor_received_at=%s normalized_at=%s ingest_to_normalize_ms=%d since_last_ms=%d bid_changed=%t ask_changed=%t",
				normalizedTick.GetExchange(),
				normalizedTick.GetSymbol(),
				normalizedTick.GetBid(),
				normalizedTick.GetAsk(),
				ingestorReceivedAt.Format(time.RFC3339Nano),
				normalizedTick.GetTimestampNormalized().AsTime().Format(time.RFC3339Nano),
				normalizeLagMs,
				sinceLastMs,
				bidChanged,
				askChanged,
			)

			lastByExchangeSymbol[key] = quoteSnapshot{
				receivedAt: ingestorReceivedAt,
				bid:        normalizedTick.GetBid(),
				ask:        normalizedTick.GetAsk(),
			}
			continue
		}

		if processedCount == 1 || processedCount%cfg.logEveryN == 0 {
			log.Printf(
				"normalized ticks processed=%d last_exchange=%s last_symbol=%s",
				processedCount,
				normalizedTick.GetExchange(),
				normalizedTick.GetSymbol(),
			)
		}
	}
}
