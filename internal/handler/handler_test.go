package handler

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/harness-claude/crypto-snapshot/internal/cache"
	"github.com/harness-claude/crypto-snapshot/internal/client"
)

type mockFetcher struct {
	price *client.CoinPrice
	err   error
}

func (m *mockFetcher) FetchPrice(_ context.Context, coinID string) (*client.CoinPrice, error) {
	if m.err != nil {
		return nil, m.err
	}
	return m.price, nil
}

func newTestHandler(fetcher PriceFetcher) *Handler {
	logger := slog.New(slog.NewJSONHandler(os.Stderr, nil))
	return New(
		cache.New(time.Minute),
		fetcher,
		logger,
		VersionInfo{Version: "test", Commit: "abc", BuildTime: "2026-01-01T00:00:00Z"},
	)
}

func TestHealth(t *testing.T) {
	h := newTestHandler(&mockFetcher{})
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	h.Health(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("got %d, want 200", rec.Code)
	}

	var body map[string]string
	_ = json.NewDecoder(rec.Body).Decode(&body)
	if body["status"] != "ok" {
		t.Errorf("got status %q, want %q", body["status"], "ok")
	}
}

func TestVersion(t *testing.T) {
	h := newTestHandler(&mockFetcher{})
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/version", nil)
	h.Version(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("got %d, want 200", rec.Code)
	}

	var body map[string]string
	_ = json.NewDecoder(rec.Body).Decode(&body)
	if body["version"] != "test" {
		t.Errorf("got version %q, want %q", body["version"], "test")
	}
}

func TestSnapshot_success(t *testing.T) {
	price := &client.CoinPrice{
		ID: "bitcoin", Symbol: "btc", PriceUSD: 50000,
		UpdatedAt: time.Now(),
	}
	h := newTestHandler(&mockFetcher{price: price})

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/snapshot/bitcoin", nil)
	h.Snapshot(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("got %d, want 200", rec.Code)
	}

	var body snapshotResponse
	_ = json.NewDecoder(rec.Body).Decode(&body)
	if body.Coin != "bitcoin" {
		t.Errorf("got coin %q, want %q", body.Coin, "bitcoin")
	}
	if body.PriceUSD != 50000 {
		t.Errorf("got price %f, want 50000", body.PriceUSD)
	}
}

func TestSnapshot_cacheHit(t *testing.T) {
	callCount := 0
	fetcher := &countingFetcher{
		price: &client.CoinPrice{ID: "bitcoin", PriceUSD: 50000, UpdatedAt: time.Now()},
		onCall: func() { callCount++ },
	}
	h := newTestHandler(fetcher)

	for i := 0; i < 3; i++ {
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodGet, "/snapshot/bitcoin", nil)
		h.Snapshot(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("request %d: got %d, want 200", i, rec.Code)
		}
	}

	if callCount != 1 {
		t.Errorf("fetcher called %d times, want 1 (cache should absorb subsequent requests)", callCount)
	}
}

func TestSnapshot_missingCoinID(t *testing.T) {
	h := newTestHandler(&mockFetcher{})
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/snapshot/", nil)
	h.Snapshot(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Errorf("got %d, want 400", rec.Code)
	}
}

func TestSnapshot_coinNotFound(t *testing.T) {
	h := newTestHandler(&mockFetcher{err: errors.New("coin not found: xyz")})
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/snapshot/xyz", nil)
	h.Snapshot(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Errorf("got %d, want 404", rec.Code)
	}
}

func TestSnapshot_upstreamError(t *testing.T) {
	h := newTestHandler(&mockFetcher{err: errors.New("connection refused")})
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/snapshot/bitcoin", nil)
	h.Snapshot(rec, req)

	if rec.Code != http.StatusServiceUnavailable {
		t.Errorf("got %d, want 503", rec.Code)
	}

	// Verify internal error is not leaked to client
	var body map[string]string
	_ = json.NewDecoder(rec.Body).Decode(&body)
	if body["error"] == "connection refused" {
		t.Error("internal error details should not be exposed to client")
	}
}

type countingFetcher struct {
	price  *client.CoinPrice
	onCall func()
}

func (c *countingFetcher) FetchPrice(_ context.Context, _ string) (*client.CoinPrice, error) {
	c.onCall()
	return c.price, nil
}
