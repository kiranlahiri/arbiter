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
	defaultMaxQuoteGap       = 500 * time.Millisecond
	defaultMinSignalInterval = 500 * time.Millisecond
)

type quote struct {
	exchange          string
	symbol            string
	bid               float64
	ask               float64
	timestampExchange *timestamppb.Timestamp
	timestampReceived time.Time
	timestampNormalized time.Time
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
	maxQuoteGap       time.Duration
	minSignalInterval time.Duration
	debug             bool
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
		maxQuoteGap:       durationMsEnv("MAX_QUOTE_GAP_MS", defaultMaxQuoteGap),
		minSignalInterval: durationMsEnv("MIN_SIGNAL_INTERVAL_MS", defaultMinSignalInterval),
		debug:             boolEnv("DETECTOR_DEBUG", false),
		quotesBySymbol:    map[string]map[string]quote{},
		lastSignalAt:      map[string]time.Time{},
	}
}

func absDuration(value time.Duration) time.Duration {
	if value < 0 {
		return -value
	}
	return value
}

func (d *detector) updateQuote(tick *pb.NormalizedTick, processedAt time.Time) quote {
	receivedAt := timestampOrFallback(tick.GetTimestampReceived(), processedAt)
	normalizedAt := timestampOrFallback(tick.GetTimestampNormalized(), processedAt)
	newQuote := quote{
		exchange:          tick.GetExchange(),
		symbol:            tick.GetSymbol(),
		bid:               tick.GetBid(),
		ask:               tick.GetAsk(),
		timestampExchange: tick.GetTimestampExchange(),
		timestampReceived: receivedAt,
		timestampNormalized: normalizedAt,
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
			if d.debug {
				log.Printf("skipping quote symbol=%s exchange=%s reason=missing_timestamp", symbol, q.exchange)
			}
			continue
		}
		age := now.Sub(q.timestampReceived)
		if age > d.maxQuoteAge {
			if d.debug {
				log.Printf(
					"skipping quote symbol=%s exchange=%s reason=stale age_ms=%d max_age_ms=%d",
					symbol,
					q.exchange,
					age.Milliseconds(),
					d.maxQuoteAge.Milliseconds(),
				)
			}
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
	if d.debug {
		log.Printf(
			"evaluated pair symbol=%s buy=%s sell=%s buy_ask=%0.2f sell_bid=%0.2f spread=%0.2f fee_adjusted=%0.2f",
			symbol,
			buyQuote.exchange,
			sellQuote.exchange,
			buyQuote.ask,
			sellQuote.bid,
			spread,
			feeAdjustedProfit,
		)
	}
	if feeAdjustedProfit <= d.minProfit {
		if d.debug {
			log.Printf(
				"skipping signal symbol=%s buy=%s sell=%s reason=below_threshold min_profit=%0.2f fee_adjusted=%0.2f",
				symbol,
				buyQuote.exchange,
				sellQuote.exchange,
				d.minProfit,
				feeAdjustedProfit,
			)
		}
		return nil
	}

	key := d.signalKey(symbol, buyQuote.exchange, sellQuote.exchange)
	lastEmittedAt := d.lastSignalAt[key]
	if !lastEmittedAt.IsZero() && now.Sub(lastEmittedAt) < d.minSignalInterval {
		if d.debug {
			log.Printf(
				"skipping signal symbol=%s buy=%s sell=%s reason=cooldown since_last_ms=%d min_interval_ms=%d",
				symbol,
				buyQuote.exchange,
				sellQuote.exchange,
				now.Sub(lastEmittedAt).Milliseconds(),
				d.minSignalInterval.Milliseconds(),
			)
		}
		return nil
	}

	tickReceivedAt := olderTime(buyQuote.timestampReceived, sellQuote.timestampReceived)
	tickNormalizedAt := olderTime(buyQuote.timestampNormalized, sellQuote.timestampNormalized)
	quoteGapMs := absDuration(buyQuote.timestampReceived.Sub(sellQuote.timestampReceived)).Milliseconds()
	buyQuoteAgeMs := now.Sub(buyQuote.timestampReceived).Milliseconds()
	sellQuoteAgeMs := now.Sub(sellQuote.timestampReceived).Milliseconds()
	quoteAgeMs := now.Sub(tickReceivedAt).Milliseconds()
	normalizeToDetectMs := now.Sub(tickNormalizedAt).Milliseconds()
	if quoteGapMs > d.maxQuoteGap.Milliseconds() {
		if d.debug {
			log.Printf(
				"skipping signal symbol=%s buy=%s sell=%s reason=quote_gap quote_gap_ms=%d max_quote_gap_ms=%d",
				symbol,
				buyQuote.exchange,
				sellQuote.exchange,
				quoteGapMs,
				d.maxQuoteGap.Milliseconds(),
			)
		}
		return nil
	}

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
		LatencyMs:             quoteAgeMs,
		Metadata: map[string]string{
			"buy_raw_topic":           buyQuote.rawTopic,
			"sell_raw_topic":          sellQuote.rawTopic,
			"buy_sequence_id":         buyQuote.sequenceID,
			"sell_sequence_id":        sellQuote.sequenceID,
			"buy_tick_received_at":    buyQuote.timestampReceived.Format(time.RFC3339Nano),
			"sell_tick_received_at":   sellQuote.timestampReceived.Format(time.RFC3339Nano),
			"buy_quote_age_ms":        strconv.FormatInt(buyQuoteAgeMs, 10),
			"sell_quote_age_ms":       strconv.FormatInt(sellQuoteAgeMs, 10),
			"oldest_quote_age_ms":     strconv.FormatInt(quoteAgeMs, 10),
			"signal_emit_age_ms":      strconv.FormatInt(quoteAgeMs, 10),
			"quote_gap_ms":            strconv.FormatInt(quoteGapMs, 10),
			"normalize_to_detect_ms":  strconv.FormatInt(normalizeToDetectMs, 10),
			"oldest_quote_exchange":   buyQuote.exchange,
			"newest_quote_exchange":   sellQuote.exchange,
		},
	}

	if sellQuote.timestampReceived.Before(buyQuote.timestampReceived) {
		signal.Metadata["oldest_quote_exchange"] = sellQuote.exchange
		signal.Metadata["newest_quote_exchange"] = buyQuote.exchange
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
		"published signal symbol=%s buy=%s sell=%s spread=%0.2f fee_adjusted=%0.2f quote_age_ms=%d",
		symbol,
		buyQuote.exchange,
		sellQuote.exchange,
		spread,
		feeAdjustedProfit,
		quoteAgeMs,
	)

	return nil
}

func (d *detector) processTick(tick *pb.NormalizedTick, processedAt time.Time) error {
	updatedQuote := d.updateQuote(tick, processedAt)
	active := d.activeQuotes(updatedQuote.symbol, processedAt)

	if d.debug {
		log.Printf(
			"updated detector state symbol=%s exchange=%s active_exchanges=%d",
			updatedQuote.symbol,
			updatedQuote.exchange,
			len(active),
		)
	}

	if len(active) < 2 {
		if d.debug {
			log.Printf(
				"not enough active quotes symbol=%s exchange=%s active_exchanges=%d",
				updatedQuote.symbol,
				updatedQuote.exchange,
				len(active),
			)
		}
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
		Brokers:     kafkaBrokers(),
		GroupID:     groupID,
		Topic:       normalizedTopic,
		StartOffset: startOffsetEnv("KAFKA_START_OFFSET", kafka.LastOffset),
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

		if d.debug {
			log.Printf(
				"received kafka message topic=%s partition=%d offset=%d key=%s bytes=%d",
				message.Topic,
				message.Partition,
				message.Offset,
				string(message.Key),
				len(message.Value),
			)
		}

		processedAt := time.Now().UTC()

		var tick pb.NormalizedTick
		if err := proto.Unmarshal(message.Value, &tick); err != nil {
			log.Printf(
				"failed to unmarshal normalized tick topic=%s partition=%d offset=%d err=%v",
				message.Topic,
				message.Partition,
				message.Offset,
				err,
			)
			continue
		}

		if d.debug {
			ingestToDetectMs := processedAt.Sub(tick.GetTimestampReceived().AsTime()).Milliseconds()
			normalizeToDetectMs := processedAt.Sub(tick.GetTimestampNormalized().AsTime()).Milliseconds()
			log.Printf(
				"decoded normalized tick exchange=%s symbol=%s bid=%0.2f ask=%0.2f received_at=%s normalized_at=%s ingest_to_detect_ms=%d normalize_to_detect_ms=%d",
				tick.GetExchange(),
				tick.GetSymbol(),
				tick.GetBid(),
				tick.GetAsk(),
				tick.GetTimestampReceived().AsTime().Format(time.RFC3339Nano),
				tick.GetTimestampNormalized().AsTime().Format(time.RFC3339Nano),
				ingestToDetectMs,
				normalizeToDetectMs,
			)
		}

		if err := d.processTick(&tick, processedAt); err != nil {
			log.Printf("detector processing error: %v", err)
		}
	}
}
