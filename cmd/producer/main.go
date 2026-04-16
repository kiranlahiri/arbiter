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
    // Create a sample NormalizedTick and publish to Kafka
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

    b, err := proto.Marshal(tick)
    if err != nil {
        panic(err)
    }

    // kafka-go writer
    w := kafka.NewWriter(kafka.WriterConfig{
        Brokers:  kafkaBrokers(),
        Topic:    "normalized.ticks",
        Balancer: &kafka.Hash{},
    })
    defer w.Close()

    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()

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
