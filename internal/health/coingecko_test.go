package health

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func newTestChecker(srv *httptest.Server) *CoinGeckoChecker {
	return &CoinGeckoChecker{client: srv.Client(), pingURL: srv.URL}
}

func TestCoinGeckoChecker_ok(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	result := newTestChecker(srv).Check(context.Background())

	if result.Status != "ok" {
		t.Errorf("got status %q, want %q", result.Status, "ok")
	}
	if result.LatencyMs < 0 {
		t.Errorf("latency_ms %d is negative", result.LatencyMs)
	}
}

func TestCoinGeckoChecker_timeout(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		time.Sleep(200 * time.Millisecond)
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
	defer cancel()

	result := newTestChecker(srv).Check(ctx)

	if result.Status != "unavailable" {
		t.Errorf("got status %q, want %q", result.Status, "unavailable")
	}
}

func TestCoinGeckoChecker_serverError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer srv.Close()

	result := newTestChecker(srv).Check(context.Background())

	if result.Status != "unavailable" {
		t.Errorf("got status %q, want %q", result.Status, "unavailable")
	}
}
