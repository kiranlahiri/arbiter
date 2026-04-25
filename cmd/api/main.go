package main

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	defaultAPIAddress   = ":8080"
	defaultDatabaseURL  = "postgres://postgres:postgres@localhost:5432/arbiter?sslmode=disable"
	defaultSignalsLimit = 50
	maxSignalsLimit     = 500
	pollInterval        = time.Second
	writeWait           = 5 * time.Second
)

var websocketUpgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

type signalRecord struct {
	ID                    int64           `json:"id"`
	Symbol                string          `json:"symbol"`
	BuyExchange           string          `json:"buy_exchange"`
	SellExchange          string          `json:"sell_exchange"`
	BuyPrice              float64         `json:"buy_price"`
	SellPrice             float64         `json:"sell_price"`
	Spread                float64         `json:"spread"`
	FeeAdjustedProfit     float64         `json:"fee_adjusted_profit"`
	TimestampOpportunity  time.Time       `json:"timestamp_opportunity"`
	TimestampTickReceived *time.Time      `json:"timestamp_tick_received,omitempty"`
	QuoteGapMs            int64           `json:"quote_gap_ms"`
	BuyQuoteAgeMs         int64           `json:"buy_quote_age_ms"`
	SellQuoteAgeMs        int64           `json:"sell_quote_age_ms"`
	OldestQuoteAgeMs      int64           `json:"oldest_quote_age_ms"`
	Metadata              json.RawMessage `json:"metadata"`
	InsertedAt            time.Time       `json:"inserted_at"`
}

type websocketEvent struct {
	Type   string       `json:"type"`
	Signal signalRecord `json:"signal"`
}

type websocketHub struct {
	mu      sync.RWMutex
	clients map[*websocket.Conn]struct{}
}

type apiServer struct {
	pool *pgxpool.Pool
	hub  *websocketHub
}

func newWebsocketHub() *websocketHub {
	return &websocketHub{
		clients: make(map[*websocket.Conn]struct{}),
	}
}

func (h *websocketHub) add(conn *websocket.Conn) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.clients[conn] = struct{}{}
}

func (h *websocketHub) remove(conn *websocket.Conn) {
	h.mu.Lock()
	defer h.mu.Unlock()
	delete(h.clients, conn)
}

func (h *websocketHub) count() int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return len(h.clients)
}

func (h *websocketHub) broadcastSignal(signal signalRecord) {
	event := websocketEvent{
		Type:   "signal",
		Signal: signal,
	}

	h.mu.RLock()
	clients := make([]*websocket.Conn, 0, len(h.clients))
	for conn := range h.clients {
		clients = append(clients, conn)
	}
	h.mu.RUnlock()

	for _, conn := range clients {
		_ = conn.SetWriteDeadline(time.Now().Add(writeWait))
		if err := conn.WriteJSON(event); err != nil {
			log.Printf("websocket broadcast failed remote=%s err=%v", conn.RemoteAddr(), err)
			_ = conn.Close()
			h.remove(conn)
		}
	}
}

func envOrDefault(key, fallback string) string {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}
	return value
}

func signalsLimitFromRequest(r *http.Request) int {
	raw := strings.TrimSpace(r.URL.Query().Get("limit"))
	if raw == "" {
		return defaultSignalsLimit
	}

	limit, err := strconv.Atoi(raw)
	if err != nil || limit <= 0 {
		return defaultSignalsLimit
	}
	if limit > maxSignalsLimit {
		return maxSignalsLimit
	}
	return limit
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(payload); err != nil {
		log.Printf("failed to encode response status=%d err=%v", status, err)
	}
}

func (s *apiServer) healthHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()

	if err := s.pool.Ping(ctx); err != nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]any{
			"status": "error",
			"error":  err.Error(),
		})
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"status":            "ok",
		"time":              time.Now().UTC(),
		"websocket_clients": s.hub.count(),
	})
}

func scanSignal(rows pgxRows) (signalRecord, error) {
	var record signalRecord
	var metadata []byte

	err := rows.Scan(
		&record.ID,
		&record.Symbol,
		&record.BuyExchange,
		&record.SellExchange,
		&record.BuyPrice,
		&record.SellPrice,
		&record.Spread,
		&record.FeeAdjustedProfit,
		&record.TimestampOpportunity,
		&record.TimestampTickReceived,
		&record.QuoteGapMs,
		&record.BuyQuoteAgeMs,
		&record.SellQuoteAgeMs,
		&record.OldestQuoteAgeMs,
		&metadata,
		&record.InsertedAt,
	)
	if err != nil {
		return signalRecord{}, err
	}

	record.Metadata = json.RawMessage(metadata)
	return record, nil
}

func (s *apiServer) fetchSignals(ctx context.Context, limit int) ([]signalRecord, error) {
	rows, err := s.pool.Query(ctx, `
SELECT
    id,
    symbol,
    buy_exchange,
    sell_exchange,
    buy_price,
    sell_price,
    spread,
    fee_adjusted_profit,
    timestamp_opportunity,
    timestamp_tick_received,
    quote_gap_ms,
    buy_quote_age_ms,
    sell_quote_age_ms,
    oldest_quote_age_ms,
    metadata,
    inserted_at
FROM signals
ORDER BY timestamp_opportunity DESC, id DESC
LIMIT $1
`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	signals := make([]signalRecord, 0, limit)
	for rows.Next() {
		record, err := scanSignal(rows)
		if err != nil {
			return nil, err
		}
		signals = append(signals, record)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	return signals, nil
}

func (s *apiServer) fetchSignalsAfterID(ctx context.Context, afterID int64) ([]signalRecord, error) {
	rows, err := s.pool.Query(ctx, `
SELECT
    id,
    symbol,
    buy_exchange,
    sell_exchange,
    buy_price,
    sell_price,
    spread,
    fee_adjusted_profit,
    timestamp_opportunity,
    timestamp_tick_received,
    quote_gap_ms,
    buy_quote_age_ms,
    sell_quote_age_ms,
    oldest_quote_age_ms,
    metadata,
    inserted_at
FROM signals
WHERE id > $1
ORDER BY id ASC
`, afterID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	signals := make([]signalRecord, 0)
	for rows.Next() {
		record, err := scanSignal(rows)
		if err != nil {
			return nil, err
		}
		signals = append(signals, record)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	return signals, nil
}

func (s *apiServer) latestSignalID(ctx context.Context) (int64, error) {
	var lastID int64
	err := s.pool.QueryRow(ctx, `SELECT COALESCE(MAX(id), 0) FROM signals`).Scan(&lastID)
	return lastID, err
}

func (s *apiServer) signalsHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	limit := signalsLimitFromRequest(r)
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	signals, err := s.fetchSignals(ctx, limit)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{
			"error": "failed to query signals",
		})
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"signals": signals,
		"count":   len(signals),
		"limit":   limit,
	})
}

func (s *apiServer) websocketSignalsHandler(w http.ResponseWriter, r *http.Request) {
	conn, err := websocketUpgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("websocket upgrade failed: %v", err)
		return
	}

	s.hub.add(conn)
	log.Printf("websocket client connected remote=%s clients=%d", conn.RemoteAddr(), s.hub.count())

	defer func() {
		s.hub.remove(conn)
		_ = conn.Close()
		log.Printf("websocket client disconnected remote=%s clients=%d", conn.RemoteAddr(), s.hub.count())
	}()

	for {
		if _, _, err := conn.ReadMessage(); err != nil {
			var closeErr *websocket.CloseError
			if !errors.As(err, &closeErr) && !websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				return
			}
			if err != nil {
				log.Printf("websocket read ended remote=%s err=%v", conn.RemoteAddr(), err)
			}
			return
		}
	}
}

func (s *apiServer) streamNewSignals(ctx context.Context) {
	lastID, err := s.latestSignalID(ctx)
	if err != nil {
		log.Printf("failed to initialize signal stream checkpoint: %v", err)
		lastID = 0
	}

	ticker := time.NewTicker(pollInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			pollCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
			signals, err := s.fetchSignalsAfterID(pollCtx, lastID)
			cancel()
			if err != nil {
				log.Printf("failed to fetch new signals for websocket stream: %v", err)
				continue
			}

			for _, signal := range signals {
				lastID = signal.ID
				s.hub.broadcastSignal(signal)
			}
		}
	}
}

type pgxRows interface {
	Scan(dest ...any) error
}

func main() {
	address := envOrDefault("API_ADDRESS", defaultAPIAddress)
	databaseURL := envOrDefault("DATABASE_URL", defaultDatabaseURL)

	ctx := context.Background()
	pool, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		log.Fatalf("failed to connect to postgres: %v", err)
	}
	defer pool.Close()

	server := &apiServer{
		pool: pool,
		hub:  newWebsocketHub(),
	}

	go server.streamNewSignals(ctx)

	mux := http.NewServeMux()
	mux.HandleFunc("/health", server.healthHandler)
	mux.HandleFunc("/signals", server.signalsHandler)
	mux.HandleFunc("/ws/signals", server.websocketSignalsHandler)

	log.Printf("starting api address=%s database=%s", address, databaseURL)
	if err := http.ListenAndServe(address, mux); err != nil {
		log.Fatalf("api server stopped: %v", err)
	}
}
