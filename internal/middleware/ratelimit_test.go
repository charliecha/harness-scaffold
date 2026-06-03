package middleware

import (
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"golang.org/x/time/rate"
	"log/slog"
)

func testLogger() *slog.Logger {
	return slog.New(slog.NewJSONHandler(os.Stderr, nil))
}

func okHandler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
}

func TestLimit_allowsUnderLimit(t *testing.T) {
	rl := New(rate.Limit(10), 5, testLogger())
	handler := rl.Limit(okHandler())

	for i := 0; i < 5; i++ {
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodGet, "/snapshot/bitcoin", nil)
		req.RemoteAddr = "1.2.3.4:9000"
		handler.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Errorf("request %d: got %d, want 200", i, rec.Code)
		}
	}
}

func TestLimit_blocks429WhenBurstExceeded(t *testing.T) {
	// burst=2 means only 2 requests allowed immediately
	rl := New(rate.Limit(0.001), 2, testLogger())
	handler := rl.Limit(okHandler())

	results := make([]int, 5)
	for i := 0; i < 5; i++ {
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodGet, "/snapshot/bitcoin", nil)
		req.RemoteAddr = "1.2.3.4:9000"
		handler.ServeHTTP(rec, req)
		results[i] = rec.Code
	}

	allowed := 0
	blocked := 0
	for _, code := range results {
		if code == http.StatusOK {
			allowed++
		} else if code == http.StatusTooManyRequests {
			blocked++
		}
	}

	if allowed != 2 {
		t.Errorf("got %d allowed, want 2 (burst=2)", allowed)
	}
	if blocked != 3 {
		t.Errorf("got %d blocked, want 3", blocked)
	}
}

func TestLimit_429ResponseBody(t *testing.T) {
	rl := New(rate.Limit(0.001), 0, testLogger())
	handler := rl.Limit(okHandler())

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/snapshot/bitcoin", nil)
	req.RemoteAddr = "1.2.3.4:9000"
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("got %d, want 429", rec.Code)
	}
	body := rec.Body.String()
	if body != `{"error":"rate limit exceeded"}` {
		t.Errorf("unexpected body: %s", body)
	}
	if ct := rec.Header().Get("Content-Type"); ct != "application/json" {
		t.Errorf("got Content-Type %q, want application/json", ct)
	}
}

func TestLimit_perIPIsolation(t *testing.T) {
	// burst=1: each IP gets its own limiter
	rl := New(rate.Limit(0.001), 1, testLogger())
	handler := rl.Limit(okHandler())

	for _, ip := range []string{"1.1.1.1:0", "2.2.2.2:0", "3.3.3.3:0"} {
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodGet, "/snapshot/bitcoin", nil)
		req.RemoteAddr = ip
		handler.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Errorf("ip %s: got %d, want 200 (each IP has its own limiter)", ip, rec.Code)
		}
	}
}

func TestClientIP_forwardedFor(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Header.Set("X-Forwarded-For", "203.0.113.1")
	req.RemoteAddr = "10.0.0.1:1234"

	got := clientIP(req)
	if got != "203.0.113.1" {
		t.Errorf("got %q, want 203.0.113.1", got)
	}
}

func TestClientIP_remoteAddr(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.RemoteAddr = "10.0.0.2:5678"

	got := clientIP(req)
	if got != "10.0.0.2" {
		t.Errorf("got %q, want 10.0.0.2", got)
	}
}
