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
    r := kafka.NewReader(kafka.ReaderConfig{
        Brokers: kafkaBrokers(),
        GroupID: "arbiter-consumer",
        Topic:   "normalized.ticks",
    })
    defer r.Close()

    fmt.Println("consumer subscribed, waiting for messages...")
    ctx := context.Background()
    for {
        m, err := r.ReadMessage(ctx)
        if err != nil {
            fmt.Printf("read error: %v\n", err)
            break
        }
        var tick pb.NormalizedTick
        if err := proto.Unmarshal(m.Value, &tick); err != nil {
            fmt.Printf("failed to unmarshal: %v\n", err)
            continue
        }
        fmt.Printf("Received tick: %s %v/%v\n", tick.Symbol, tick.Bid, tick.Ask)
    }
}
