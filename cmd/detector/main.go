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
	defaultKafkaBroker       = "localhost:9092"
	defaultNormalizedTopic   = "normalized.ticks"
	defaultSignalsTopic      = "arbitrage.signals"
	defaultDetectorGroupID   = "arbiter-detector"
	defaultMaxQuoteAge       = 5 * time.Second
	defaultMinSignalInterval = 500 * time.Millisecond
)

type quote struct {
	exchange          string
	symbol            string
	bid               float64
	ask               float64
	timestampExchange *timestamppb.Timestamp
	timestampReceived time.Time
	sequenceID        string
	rawTopic          string
	metadata          map[string]string
}

type detector struct {
	writer            *kafka.Writer
	signalsTopic      string
	minProfit         float64
	feeBps            float64
	maxQuoteAge       time.Duration
	minSignalInterval time.Duration
	quotesBySymbol    map[string]map[string]quote
	lastSignalAt      map[string]time.Time
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

func floatEnv(key string, fallback float64) float64 {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}

	parsed, err := strconv.ParseFloat(value, 64)
	if err != nil {
		return fallback
	}

	return parsed
}

func durationMsEnv(key string, fallback time.Duration) time.Duration {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}

	parsed, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}

	return time.Duration(parsed) * time.Millisecond
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

func timestampOrFallback(ts *timestamppb.Timestamp, fallback time.Time) time.Time {
	if ts == nil {
		return fallback
	}
	return ts.AsTime()
}

func newDetector(writer *kafka.Writer, signalsTopic string) *detector {
	return &detector{
		writer:            writer,
		signalsTopic:      signalsTopic,
		minProfit:         floatEnv("MIN_SIGNAL_PROFIT", 0),
		feeBps:            floatEnv("FEE_BPS", 0),
		maxQuoteAge:       durationMsEnv("MAX_QUOTE_AGE_MS", defaultMaxQuoteAge),
		minSignalInterval: durationMsEnv("MIN_SIGNAL_INTERVAL_MS", defaultMinSignalInterval),
		quotesBySymbol:    map[string]map[string]quote{},
		lastSignalAt:      map[string]time.Time{},
	}
}

func (d *detector) updateQuote(tick *pb.NormalizedTick, processedAt time.Time) quote {
	receivedAt := timestampOrFallback(tick.GetTimestampReceived(), processedAt)
	newQuote := quote{
		exchange:          tick.GetExchange(),
		symbol:            tick.GetSymbol(),
		bid:               tick.GetBid(),
		ask:               tick.GetAsk(),
		timestampExchange: tick.GetTimestampExchange(),
		timestampReceived: receivedAt,
		sequenceID:        tick.GetSourceSequenceId(),
		rawTopic:          tick.GetRawTopic(),
		metadata:          cloneMetadata(tick.GetMetadata()),
	}

	if d.quotesBySymbol[newQuote.symbol] == nil {
		d.quotesBySymbol[newQuote.symbol] = map[string]quote{}
	}
	d.quotesBySymbol[newQuote.symbol][newQuote.exchange] = newQuote

	return newQuote
}

func (d *detector) activeQuotes(symbol string, now time.Time) []quote {
	quotes := d.quotesBySymbol[symbol]
	active := make([]quote, 0, len(quotes))
	for _, q := range quotes {
		if q.timestampReceived.IsZero() {
			continue
		}
		if now.Sub(q.timestampReceived) > d.maxQuoteAge {
			continue
		}
		active = append(active, q)
	}
	return active
}

func feeCost(buyPrice, sellPrice, feeBps float64) float64 {
	rate := feeBps / 10000.0
	return (buyPrice * rate) + (sellPrice * rate)
}

func olderTime(a, b time.Time) time.Time {
	if a.IsZero() {
		return b
	}
	if b.IsZero() {
		return a
	}
	if a.Before(b) {
		return a
	}
	return b
}

func (d *detector) signalKey(symbol, buyExchange, sellExchange string) string {
	return symbol + "|" + buyExchange + "|" + sellExchange
}

func (d *detector) emitSignal(symbol string, buyQuote, sellQuote quote, now time.Time) error {
	spread := sellQuote.bid - buyQuote.ask
	feeAdjustedProfit := spread - feeCost(buyQuote.ask, sellQuote.bid, d.feeBps)
	if feeAdjustedProfit <= d.minProfit {
		return nil
	}

	key := d.signalKey(symbol, buyQuote.exchange, sellQuote.exchange)
	lastEmittedAt := d.lastSignalAt[key]
	if !lastEmittedAt.IsZero() && now.Sub(lastEmittedAt) < d.minSignalInterval {
		return nil
	}

	tickReceivedAt := olderTime(buyQuote.timestampReceived, sellQuote.timestampReceived)
	latencyMs := now.Sub(tickReceivedAt).Milliseconds()

	signal := &pb.Signal{
		Symbol:                symbol,
		BuyExchange:           buyQuote.exchange,
		SellExchange:          sellQuote.exchange,
		BuyPrice:              buyQuote.ask,
		SellPrice:             sellQuote.bid,
		Spread:                spread,
		FeeAdjustedProfit:     feeAdjustedProfit,
		TimestampOpportunity:  timestamppb.New(now),
		TimestampTickReceived: timestamppb.New(tickReceivedAt),
		LatencyMs:             latencyMs,
		Metadata: map[string]string{
			"buy_raw_topic":         buyQuote.rawTopic,
			"sell_raw_topic":        sellQuote.rawTopic,
			"buy_sequence_id":       buyQuote.sequenceID,
			"sell_sequence_id":      sellQuote.sequenceID,
			"buy_tick_received_at":  buyQuote.timestampReceived.Format(time.RFC3339Nano),
			"sell_tick_received_at": sellQuote.timestampReceived.Format(time.RFC3339Nano),
		},
	}

	encoded, err := proto.Marshal(signal)
	if err != nil {
		return err
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	err = d.writer.WriteMessages(ctx, kafka.Message{
		Key:   []byte(symbol),
		Value: encoded,
		Time:  now,
	})
	if err != nil {
		return err
	}

	d.lastSignalAt[key] = now
	log.Printf(
		"published signal symbol=%s buy=%s sell=%s spread=%0.2f fee_adjusted=%0.2f latency_ms=%d",
		symbol,
		buyQuote.exchange,
		sellQuote.exchange,
		spread,
		feeAdjustedProfit,
		latencyMs,
	)

	return nil
}

func (d *detector) processTick(tick *pb.NormalizedTick, processedAt time.Time) error {
	updatedQuote := d.updateQuote(tick, processedAt)
	active := d.activeQuotes(updatedQuote.symbol, processedAt)

	log.Printf(
		"updated detector state symbol=%s exchange=%s active_exchanges=%d",
		updatedQuote.symbol,
		updatedQuote.exchange,
		len(active),
	)

	if len(active) < 2 {
		return nil
	}

	for _, buyQuote := range active {
		if buyQuote.ask <= 0 {
			continue
		}

		for _, sellQuote := range active {
			if buyQuote.exchange == sellQuote.exchange || sellQuote.bid <= 0 {
				continue
			}

			if err := d.emitSignal(updatedQuote.symbol, buyQuote, sellQuote, processedAt); err != nil {
				return err
			}
		}
	}

	return nil
}

func main() {
	normalizedTopic := envOrDefault("NORMALIZED_TICKS_TOPIC", defaultNormalizedTopic)
	signalsTopic := envOrDefault("SIGNALS_TOPIC", defaultSignalsTopic)
	groupID := envOrDefault("KAFKA_GROUP_ID", defaultDetectorGroupID)

	reader := kafka.NewReader(kafka.ReaderConfig{
		Brokers: kafkaBrokers(),
		GroupID: groupID,
		Topic:   normalizedTopic,
	})
	defer reader.Close()

	writer := kafka.NewWriter(kafka.WriterConfig{
		Brokers:  kafkaBrokers(),
		Topic:    signalsTopic,
		Balancer: &kafka.Hash{},
	})
	defer writer.Close()

	d := newDetector(writer, signalsTopic)

	log.Printf(
		"starting detector normalized_topic=%s signals_topic=%s group_id=%s brokers=%s",
		normalizedTopic,
		signalsTopic,
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

		var tick pb.NormalizedTick
		if err := proto.Unmarshal(message.Value, &tick); err != nil {
			log.Printf("failed to unmarshal normalized tick: %v", err)
			continue
		}

		if err := d.processTick(&tick, time.Now().UTC()); err != nil {
			log.Printf("detector processing error: %v", err)
		}
	}
}
