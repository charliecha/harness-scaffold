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
	"github.com/harness-claude/crypto-snapshot/internal/health"
	"github.com/harness-claude/crypto-snapshot/internal/metrics"
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
		nil,
		3*time.Second,
	)
}

func newTestHandlerWithCheckers(fetcher PriceFetcher, checkers []health.Checker) *Handler {
	logger := slog.New(slog.NewJSONHandler(os.Stderr, nil))
	return New(
		cache.New(time.Minute),
		fetcher,
		logger,
		VersionInfo{Version: "test", Commit: "abc", BuildTime: "2026-01-01T00:00:00Z"},
		checkers,
		3*time.Second,
	)
}

// mockChecker is a test double for health.Checker.
type mockChecker struct {
	name   string
	result health.Result
}

func (m *mockChecker) Name() string                        { return m.name }
func (m *mockChecker) Check(_ context.Context) health.Result { return m.result }

func TestHealth_allOk(t *testing.T) {
	checkers := []health.Checker{
		&mockChecker{name: "coingecko", result: health.Result{Status: "ok", LatencyMs: 42}},
	}
	h := newTestHandlerWithCheckers(&mockFetcher{}, checkers)
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	h.Health(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("got %d, want 200", rec.Code)
	}
	var body map[string]any
	_ = json.NewDecoder(rec.Body).Decode(&body)
	if body["status"] != "ok" {
		t.Errorf("got status %q, want %q", body["status"], "ok")
	}
	deps, _ := body["dependencies"].(map[string]any)
	cg, _ := deps["coingecko"].(map[string]any)
	if cg["status"] != "ok" {
		t.Errorf("coingecko status: got %q, want %q", cg["status"], "ok")
	}
}

func TestHealth_degraded(t *testing.T) {
	checkers := []health.Checker{
		&mockChecker{name: "coingecko", result: health.Result{Status: "unavailable", LatencyMs: 3000}},
	}
	h := newTestHandlerWithCheckers(&mockFetcher{}, checkers)
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	h.Health(rec, req)

	// HTTP 200 even when degraded (AC-2b)
	if rec.Code != http.StatusOK {
		t.Errorf("got %d, want 200 even when degraded", rec.Code)
	}
	var body map[string]any
	_ = json.NewDecoder(rec.Body).Decode(&body)
	if body["status"] != "degraded" {
		t.Errorf("got status %q, want %q", body["status"], "degraded")
	}
}

func TestHealth_noCheckers(t *testing.T) {
	h := newTestHandler(&mockFetcher{})
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	h.Health(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("got %d, want 200", rec.Code)
	}
	var body map[string]any
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

	for range 3 {
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodGet, "/snapshot/bitcoin", nil)
		h.Snapshot(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("got %d, want 200", rec.Code)
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

// ── API 契约测试（对应 FR-002）────────────────────────────────
// 验证 /metrics 响应 schema 符合需求定义，把 Phase 6 PM 验收变为硬约束。

func TestMetrics_schema(t *testing.T) {
	col := metrics.New()
	h := newTestHandler(&mockFetcher{})

	rec := httptest.NewRecorder()
	h.Metrics(col)(rec, httptest.NewRequest(http.MethodGet, "/metrics", nil))

	if rec.Code != http.StatusOK {
		t.Fatalf("got %d, want 200", rec.Code)
	}
	if ct := rec.Header().Get("Content-Type"); ct != "application/json" {
		t.Errorf("Content-Type: got %q, want application/json", ct)
	}

	var body map[string]map[string]int64
	if err := json.NewDecoder(rec.Body).Decode(&body); err != nil {
		t.Fatalf("response is not valid JSON: %v", err)
	}
}

func TestMetrics_countsRoutes(t *testing.T) {
	col := metrics.New()
	col.Record("/health", false)
	col.Record("/health", false)
	col.Record("/snapshot/*", false)
	col.Record("/snapshot/*", true)

	h := newTestHandler(&mockFetcher{})
	rec := httptest.NewRecorder()
	h.Metrics(col)(rec, httptest.NewRequest(http.MethodGet, "/metrics", nil))

	var body map[string]map[string]int64
	if err := json.NewDecoder(rec.Body).Decode(&body); err != nil {
		t.Fatalf("decode: %v", err)
	}

	// FR-002 FR-01: 每个路由含 total_requests 和 rate_limited_requests
	for _, route := range []string{"/health", "/snapshot/*"} {
		stats, ok := body[route]
		if !ok {
			t.Errorf("route %q missing from /metrics response", route)
			continue
		}
		if _, ok := stats["total_requests"]; !ok {
			t.Errorf("route %q missing field total_requests", route)
		}
		if _, ok := stats["rate_limited_requests"]; !ok {
			t.Errorf("route %q missing field rate_limited_requests", route)
		}
	}

	// FR-002 FR-02: 数值正确累计
	if got := body["/health"]["total_requests"]; got != 2 {
		t.Errorf("/health total_requests: got %d, want 2", got)
	}
	if got := body["/snapshot/*"]["rate_limited_requests"]; got != 1 {
		t.Errorf("/snapshot/* rate_limited_requests: got %d, want 1", got)
	}

	// FR-002 FR-03: 路由分组独立
	if got := body["/health"]["rate_limited_requests"]; got != 0 {
		t.Errorf("/health should have 0 rate_limited, got %d", got)
	}
}

func TestMetrics_doesNotCountItself(t *testing.T) {
	col := metrics.New()
	h := newTestHandler(&mockFetcher{})

	// 多次调用 /metrics
	for range 3 {
		rec := httptest.NewRecorder()
		h.Metrics(col)(rec, httptest.NewRequest(http.MethodGet, "/metrics", nil))
	}

	var body map[string]map[string]int64
	rec := httptest.NewRecorder()
	h.Metrics(col)(rec, httptest.NewRequest(http.MethodGet, "/metrics", nil))
	if err := json.NewDecoder(rec.Body).Decode(&body); err != nil {
		t.Fatalf("decode: %v", err)
	}

	// NFR-01: /metrics 自身不出现在统计中
	if _, ok := body["/metrics"]; ok {
		t.Error("/metrics should not count itself (NFR-01 violated)")
	}
}
