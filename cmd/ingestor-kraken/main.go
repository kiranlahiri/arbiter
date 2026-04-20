package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/gorilla/websocket"
	pb "github.com/kiran/arbiter/proto"
	"github.com/segmentio/kafka-go"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
)

const (
	defaultKafkaBroker      = "localhost:9092"
	defaultKafkaTopic       = "raw.ticks.kraken"
	defaultKrakenFeedURL    = "wss://ws.kraken.com/v2"
	defaultKrakenSymbol     = "BTC/USD"
	defaultKrakenChannel    = "ticker"
	defaultKrakenEvent      = "bbo"
	initialReconnectBackoff = time.Second
	maxReconnectBackoff     = 30 * time.Second
)

type krakenSubscribeMessage struct {
	Method string                `json:"method"`
	Params krakenSubscribeParams `json:"params"`
}

type krakenSubscribeParams struct {
	Channel      string   `json:"channel"`
	Symbol       []string `json:"symbol"`
	EventTrigger string   `json:"event_trigger"`
	Snapshot     bool     `json:"snapshot"`
}

type krakenEnvelope struct {
	Channel string `json:"channel"`
	Type    string `json:"type"`
	Method  string `json:"method"`
	Success bool   `json:"success"`
	Error   string `json:"error"`
}

type krakenTickerPayload struct {
	Symbol    string  `json:"symbol"`
	Bid       float64 `json:"bid"`
	BidQty    float64 `json:"bid_qty"`
	Ask       float64 `json:"ask"`
	AskQty    float64 `json:"ask_qty"`
	Last      float64 `json:"last"`
	Volume    float64 `json:"volume"`
	Timestamp string  `json:"timestamp"`
}

type krakenTickerMessage struct {
	Channel string                `json:"channel"`
	Type    string                `json:"type"`
	Data    []krakenTickerPayload `json:"data"`
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

func parseExchangeTime(value string) *timestamppb.Timestamp {
	if value == "" {
		return nil
	}

	parsed, err := time.Parse(time.RFC3339Nano, value)
	if err != nil {
		return nil
	}

	return timestamppb.New(parsed)
}

func publishTicker(ctx context.Context, writer *kafka.Writer, payload []byte, tick krakenTickerPayload, messageType string, receivedAt time.Time) error {
	rawTick := &pb.RawTick{
		Meta: &pb.TickMeta{
			Exchange:                  "kraken",
			Symbol:                    tick.Symbol,
			SequenceId:                receivedAt.UTC().Format(time.RFC3339Nano),
			TimestampExchange:         parseExchangeTime(tick.Timestamp),
			TimestampIngestorReceived: timestamppb.New(receivedAt),
			Source:                    "kraken:ticker",
		},
		RawPayload: payload,
		Price:      tick.Last,
		Bid:        tick.Bid,
		Ask:        tick.Ask,
		Volume:     tick.Volume,
		Metadata: map[string]string{
			"channel":       defaultKrakenChannel,
			"event_trigger": defaultKrakenEvent,
			"symbol":        tick.Symbol,
			"message_type":  messageType,
			"bid_qty":       strconv.FormatFloat(tick.BidQty, 'f', -1, 64),
			"ask_qty":       strconv.FormatFloat(tick.AskQty, 'f', -1, 64),
		},
	}

	encoded, err := proto.Marshal(rawTick)
	if err != nil {
		return fmt.Errorf("marshal raw tick: %w", err)
	}

	return writer.WriteMessages(ctx, kafka.Message{
		Key:   []byte(tick.Symbol),
		Value: encoded,
		Time:  receivedAt,
	})
}

func consumeKrakenFeed(writer *kafka.Writer, feedURL, symbol string) error {
	conn, _, err := websocket.DefaultDialer.Dial(feedURL, nil)
	if err != nil {
		return fmt.Errorf("dial websocket: %w", err)
	}
	defer conn.Close()

	subscribe := krakenSubscribeMessage{
		Method: "subscribe",
		Params: krakenSubscribeParams{
			Channel:      defaultKrakenChannel,
			Symbol:       []string{symbol},
			EventTrigger: defaultKrakenEvent,
			Snapshot:     true,
		},
	}
	if err := conn.WriteJSON(subscribe); err != nil {
		return fmt.Errorf("send subscribe message: %w", err)
	}

	log.Printf("connected to Kraken feed %s and subscribed to %s", feedURL, symbol)

	for {
		_, payload, err := conn.ReadMessage()
		if err != nil {
			return fmt.Errorf("read websocket message: %w", err)
		}

		receivedAt := time.Now().UTC()

		var envelope krakenEnvelope
		if err := json.Unmarshal(payload, &envelope); err != nil {
			log.Printf("skipping unreadable message: %v", err)
			continue
		}

		if envelope.Method == "subscribe" {
			if !envelope.Success {
				return fmt.Errorf("kraken subscribe failed: %s", envelope.Error)
			}
			log.Printf("subscription acknowledged for %s", symbol)
			continue
		}

		if envelope.Channel != defaultKrakenChannel {
			continue
		}

		var tickerMessage krakenTickerMessage
		if err := json.Unmarshal(payload, &tickerMessage); err != nil {
			log.Printf("skipping malformed ticker message: %v", err)
			continue
		}

		for _, tick := range tickerMessage.Data {
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			err := publishTicker(ctx, writer, payload, tick, tickerMessage.Type, receivedAt)
			cancel()
			if err != nil {
				return fmt.Errorf("publish ticker to kafka: %w", err)
			}

			log.Printf(
				"published raw tick exchange=%s symbol=%s bid=%0.2f ask=%0.2f",
				"kraken",
				tick.Symbol,
				tick.Bid,
				tick.Ask,
			)
		}
	}
}

func main() {
	feedURL := envOrDefault("KRAKEN_WS_URL", defaultKrakenFeedURL)
	symbol := envOrDefault("KRAKEN_SYMBOL", defaultKrakenSymbol)
	topic := envOrDefault("RAW_TICKS_TOPIC", defaultKafkaTopic)

	writer := kafka.NewWriter(kafka.WriterConfig{
		Brokers:  kafkaBrokers(),
		Topic:    topic,
		Balancer: &kafka.Hash{},
	})
	defer writer.Close()

	log.Printf("starting Kraken ingestor symbol=%s topic=%s brokers=%s", symbol, topic, strings.Join(kafkaBrokers(), ","))

	backoff := initialReconnectBackoff
	for {
		if err := consumeKrakenFeed(writer, feedURL, symbol); err != nil {
			log.Printf("ingestor loop ended: %v", err)
		}

		log.Printf("reconnecting in %s", backoff)
		time.Sleep(backoff)

		backoff *= 2
		if backoff > maxReconnectBackoff {
			backoff = maxReconnectBackoff
		}
	}
}
