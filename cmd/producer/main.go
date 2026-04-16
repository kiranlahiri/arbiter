package main

import (
    "context"
    "fmt"
    "os"
    "strings"
    "time"

    pb "github.com/kiran/arbiter/proto"
    "google.golang.org/protobuf/proto"
    "google.golang.org/protobuf/types/known/timestamppb"

    "github.com/segmentio/kafka-go"
)

func kafkaBrokers() []string {
    // Allow the same binary to run either on the host or inside Docker Compose.
    brokers := os.Getenv("KAFKA_BROKERS")
    if brokers == "" {
        return []string{"localhost:9092"}
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
        return []string{"localhost:9092"}
    }

    return resolved
}

func main() {
    // Build one sample protobuf message in memory.
    tick := &pb.NormalizedTick{
        Exchange:          "binance",
        Symbol:            "BTC-USDT",
        Bid:               67432.10,
        Ask:               67433.50,
        TimestampExchange: timestamppb.Now(),
        TimestampReceived: timestamppb.Now(),
        TimestampNormalized: timestamppb.Now(),
        SourceSequenceId:  "example-1",
        RawTopic:          "raw.ticks.binance",
        Metadata:          map[string]string{"note": "example"},
    }

    // Encode the structured protobuf message into bytes for Kafka transport.
    b, err := proto.Marshal(tick)
    if err != nil {
        panic(err)
    }

    // Create a Kafka writer for the normalized tick topic.
    w := kafka.NewWriter(kafka.WriterConfig{
        Brokers:  kafkaBrokers(),
        Topic:    "normalized.ticks",
        Balancer: &kafka.Hash{},
    })
    defer w.Close()

    // Use a timeout so the publish does not hang forever if Kafka is unavailable.
    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()

    // Publish the protobuf bytes to Kafka, keyed by symbol for stable partitioning.
    err = w.WriteMessages(ctx, kafka.Message{
        Key:   []byte(tick.Symbol),
        Value: b,
        Time:  time.Now(),
    })
    if err != nil {
        panic(err)
    }
    fmt.Println("Message written")
}
