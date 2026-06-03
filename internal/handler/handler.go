package handler

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/harness-claude/crypto-snapshot/internal/cache"
	"github.com/harness-claude/crypto-snapshot/internal/client"
)

// PriceFetcher abstracts the CoinGecko client for testing.
type PriceFetcher interface {
	FetchPrice(ctx context.Context, coinID string) (*client.CoinPrice, error)
}

// Handler holds dependencies for all HTTP handlers.
type Handler struct {
	cache   *cache.Store
	client  PriceFetcher
	logger  *slog.Logger
	version VersionInfo
}

// VersionInfo carries build-time metadata.
type VersionInfo struct {
	Version   string
	Commit    string
	BuildTime string
}

// New returns a configured Handler.
func New(c *cache.Store, fetcher PriceFetcher, logger *slog.Logger, v VersionInfo) *Handler {
	return &Handler{
		cache:   c,
		client:  fetcher,
		logger:  logger,
		version: v,
	}
}

// RegisterRoutes wires all routes onto mux.
func (h *Handler) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/health", h.Health)
	mux.HandleFunc("/version", h.Version)
	mux.HandleFunc("/snapshot/", h.Snapshot)
}

// Health returns a 200 OK with a simple status body.
func (h *Handler) Health(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// Version returns build metadata.
func (h *Handler) Version(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{
		"version":    h.version.Version,
		"commit":     h.version.Commit,
		"build_time": h.version.BuildTime,
	})
}

// Snapshot returns the current (or cached) price for a coin.
// Route: /snapshot/{coinID}
func (h *Handler) Snapshot(w http.ResponseWriter, r *http.Request) {
	coinID := strings.TrimPrefix(r.URL.Path, "/snapshot/")
	coinID = strings.TrimSpace(coinID)
	if coinID == "" {
		writeJSON(w, http.StatusBadRequest, errResponse("missing coin ID"))
		return
	}

	if price, ok := h.cache.Get(coinID); ok {
		h.logger.Info("cache hit", slog.String("coin", coinID))
		writeJSON(w, http.StatusOK, toResponse(price))
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()

	price, err := h.client.FetchPrice(ctx, coinID)
	if err != nil {
		h.logger.Error("fetch failed", slog.String("coin", coinID), slog.Any("err", err))
		if strings.Contains(err.Error(), "coin not found") {
			writeJSON(w, http.StatusNotFound, errResponse("coin not found: "+coinID))
			return
		}
		writeJSON(w, http.StatusServiceUnavailable, errResponse("upstream unavailable"))
		return
	}

	h.cache.Set(coinID, price)
	h.logger.Info("cache miss — fetched", slog.String("coin", coinID), slog.Float64("price_usd", price.PriceUSD))
	writeJSON(w, http.StatusOK, toResponse(price))
}

type snapshotResponse struct {
	Coin      string    `json:"coin"`
	Symbol    string    `json:"symbol"`
	PriceUSD  float64   `json:"price_usd"`
	MarketCap float64   `json:"market_cap"`
	Change24h float64   `json:"change_24h_pct"`
	Timestamp time.Time `json:"timestamp"`
}

func toResponse(p *client.CoinPrice) snapshotResponse {
	return snapshotResponse{
		Coin:      p.ID,
		Symbol:    p.Symbol,
		PriceUSD:  p.PriceUSD,
		MarketCap: p.MarketCap,
		Change24h: p.Change24h,
		Timestamp: p.UpdatedAt,
	}
}

func errResponse(msg string) map[string]string {
	return map[string]string{"error": msg}
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}
