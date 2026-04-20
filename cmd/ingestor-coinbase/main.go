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
	defaultKafkaTopic       = "raw.ticks.coinbase"
	defaultCoinbaseFeedURL  = "wss://ws-feed.exchange.coinbase.com"
	defaultCoinbaseProduct  = "BTC-USD"
	defaultCoinbaseChannel  = "ticker"
	initialReconnectBackoff = time.Second
	maxReconnectBackoff     = 30 * time.Second
)

type subscribeMessage struct {
	Type       string   `json:"type"`
	ProductIDs []string `json:"product_ids"`
	Channels   []string `json:"channels"`
}

type coinbaseTickerMessage struct {
	Type      string `json:"type"`
	ProductID string `json:"product_id"`
	Sequence  int64  `json:"sequence"`
	Time      string `json:"time"`
	Price     string `json:"price"`
	BestBid   string `json:"best_bid"`
	BestAsk   string `json:"best_ask"`
	LastSize  string `json:"last_size"`
	Side      string `json:"side"`
	TradeID   int64  `json:"trade_id"`
}

type serviceConfig struct {
	debug bool
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

func parseFloat(value string) float64 {
	if value == "" {
		return 0
	}

	parsed, err := strconv.ParseFloat(value, 64)
	if err != nil {
		return 0
	}

	return parsed
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

func publishTicker(ctx context.Context, writer *kafka.Writer, payload []byte, msg coinbaseTickerMessage, receivedAt time.Time) error {
	rawTick := &pb.RawTick{
		Meta: &pb.TickMeta{
			Exchange:                  "coinbase",
			Symbol:                    msg.ProductID,
			SequenceId:                strconv.FormatInt(msg.Sequence, 10),
			TimestampExchange:         parseExchangeTime(msg.Time),
			TimestampIngestorReceived: timestamppb.New(receivedAt),
			Source:                    "coinbase:ticker",
		},
		RawPayload: payload,
		Price:      parseFloat(msg.Price),
		Bid:        parseFloat(msg.BestBid),
		Ask:        parseFloat(msg.BestAsk),
		Volume:     parseFloat(msg.LastSize),
		Metadata: map[string]string{
			"channel":    defaultCoinbaseChannel,
			"product_id": msg.ProductID,
			"side":       msg.Side,
			"trade_id":   strconv.FormatInt(msg.TradeID, 10),
		},
	}

	encoded, err := proto.Marshal(rawTick)
	if err != nil {
		return fmt.Errorf("marshal raw tick: %w", err)
	}

	return writer.WriteMessages(ctx, kafka.Message{
		Key:   []byte(msg.ProductID),
		Value: encoded,
		Time:  receivedAt,
	})
}

func consumeCoinbaseFeed(cfg serviceConfig, writer *kafka.Writer, topic, feedURL, productID string) error {
	conn, _, err := websocket.DefaultDialer.Dial(feedURL, nil)
	if err != nil {
		return fmt.Errorf("dial websocket: %w", err)
	}
	defer conn.Close()

	subscribe := subscribeMessage{
		Type:       "subscribe",
		ProductIDs: []string{productID},
		Channels:   []string{defaultCoinbaseChannel},
	}
	if err := conn.WriteJSON(subscribe); err != nil {
		return fmt.Errorf("send subscribe message: %w", err)
	}

	log.Printf("connected to Coinbase feed %s and subscribed to %s", feedURL, productID)

	for {
		_, payload, err := conn.ReadMessage()
		if err != nil {
			return fmt.Errorf("read websocket message: %w", err)
		}

		receivedAt := time.Now().UTC()

		var envelope struct {
			Type    string `json:"type"`
			Message string `json:"message"`
			Reason  string `json:"reason"`
		}
		if err := json.Unmarshal(payload, &envelope); err != nil {
			if cfg.debug {
				log.Printf("skipping unreadable message: %v", err)
			}
			continue
		}

		switch envelope.Type {
		case "subscriptions":
			log.Printf("subscription acknowledged for %s", productID)
			continue
		case "error":
			return fmt.Errorf("coinbase websocket error: %s %s", envelope.Reason, envelope.Message)
		case "ticker":
			var tickerMsg coinbaseTickerMessage
			if err := json.Unmarshal(payload, &tickerMsg); err != nil {
				if cfg.debug {
					log.Printf("skipping malformed ticker message: %v", err)
				}
				continue
			}

			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			err := publishTicker(ctx, writer, payload, tickerMsg, receivedAt)
			cancel()
			if err != nil {
				return fmt.Errorf("publish ticker to kafka: %w", err)
			}

			if cfg.debug {
				log.Printf(
					"published raw tick exchange=%s product=%s bid=%s ask=%s",
					"coinbase",
					tickerMsg.ProductID,
					tickerMsg.BestBid,
					tickerMsg.BestAsk,
				)
			}
		default:
			// Coinbase sends other message types too. Ignore them until we need them.
			continue
		}
	}
}

func main() {
	feedURL := envOrDefault("COINBASE_WS_URL", defaultCoinbaseFeedURL)
	productID := envOrDefault("COINBASE_PRODUCT_ID", defaultCoinbaseProduct)
	topic := envOrDefault("RAW_TICKS_TOPIC", defaultKafkaTopic)
	cfg := serviceConfig{
		debug: boolEnv("INGESTOR_DEBUG", false),
	}

	writer := kafka.NewWriter(kafka.WriterConfig{
		Brokers:  kafkaBrokers(),
		Topic:    topic,
		Balancer: &kafka.Hash{},
	})
	defer writer.Close()

	log.Printf("starting Coinbase ingestor product=%s topic=%s brokers=%s", productID, topic, strings.Join(kafkaBrokers(), ","))

	backoff := initialReconnectBackoff
	for {
		if err := consumeCoinbaseFeed(cfg, writer, topic, feedURL, productID); err != nil {
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
