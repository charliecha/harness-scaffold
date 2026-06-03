package metrics

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestRecord_incrementsTotal(t *testing.T) {
	c := New()
	c.Record("/health", false)
	c.Record("/health", false)

	snap := c.Snapshot()
	if snap["/health"].TotalRequests != 2 {
		t.Errorf("got %d, want 2", snap["/health"].TotalRequests)
	}
	if snap["/health"].RateLimitedRequests != 0 {
		t.Errorf("got %d rate limited, want 0", snap["/health"].RateLimitedRequests)
	}
}

func TestRecord_incrementsRateLimited(t *testing.T) {
	c := New()
	c.Record("/snapshot/*", false)
	c.Record("/snapshot/*", true)
	c.Record("/snapshot/*", true)

	snap := c.Snapshot()
	if snap["/snapshot/*"].TotalRequests != 3 {
		t.Errorf("got total %d, want 3", snap["/snapshot/*"].TotalRequests)
	}
	if snap["/snapshot/*"].RateLimitedRequests != 2 {
		t.Errorf("got rate_limited %d, want 2", snap["/snapshot/*"].RateLimitedRequests)
	}
}

func TestRecord_routesAreIsolated(t *testing.T) {
	c := New()
	c.Record("/health", false)
	c.Record("/version", false)
	c.Record("/version", false)

	snap := c.Snapshot()
	if snap["/health"].TotalRequests != 1 {
		t.Errorf("/health: got %d, want 1", snap["/health"].TotalRequests)
	}
	if snap["/version"].TotalRequests != 2 {
		t.Errorf("/version: got %d, want 2", snap["/version"].TotalRequests)
	}
}

func TestSnapshot_emptyCollector(t *testing.T) {
	c := New()
	snap := c.Snapshot()
	if len(snap) != 0 {
		t.Errorf("expected empty snapshot, got %d entries", len(snap))
	}
}

func TestMiddleware_recordsNormalRequest(t *testing.T) {
	c := New()
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	handler := c.Middleware("/snapshot/*", inner)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/snapshot/bitcoin", nil))

	snap := c.Snapshot()
	if snap["/snapshot/*"].TotalRequests != 1 {
		t.Errorf("got %d, want 1", snap["/snapshot/*"].TotalRequests)
	}
	if snap["/snapshot/*"].RateLimitedRequests != 0 {
		t.Errorf("got %d rate limited, want 0", snap["/snapshot/*"].RateLimitedRequests)
	}
}

func TestMiddleware_recordsRateLimitedRequest(t *testing.T) {
	c := New()
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusTooManyRequests)
	})

	handler := c.Middleware("/snapshot/*", inner)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/snapshot/bitcoin", nil))

	snap := c.Snapshot()
	if snap["/snapshot/*"].RateLimitedRequests != 1 {
		t.Errorf("got %d rate limited, want 1", snap["/snapshot/*"].RateLimitedRequests)
	}
}

func TestWrapFunc_recordsRequest(t *testing.T) {
	c := New()
	fn := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	wrapped := c.WrapFunc("/health", fn)
	rec := httptest.NewRecorder()
	wrapped(rec, httptest.NewRequest(http.MethodGet, "/health", nil))

	snap := c.Snapshot()
	if snap["/health"].TotalRequests != 1 {
		t.Errorf("got %d, want 1", snap["/health"].TotalRequests)
	}
}

func TestMiddleware_implicitStatus200(t *testing.T) {
	c := New()
	// Handler writes body without calling WriteHeader (implicit 200)
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`{}`))
	})

	handler := c.Middleware("/snapshot/*", inner)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/snapshot/bitcoin", nil))

	snap := c.Snapshot()
	if snap["/snapshot/*"].TotalRequests != 1 {
		t.Errorf("got %d, want 1", snap["/snapshot/*"].TotalRequests)
	}
	if snap["/snapshot/*"].RateLimitedRequests != 0 {
		t.Errorf("implicit 200 should not be counted as rate limited, got %d", snap["/snapshot/*"].RateLimitedRequests)
	}
}

func TestConcurrentRecord(t *testing.T) {
	c := New()
	done := make(chan struct{})

	go func() {
		for i := 0; i < 1000; i++ {
			c.Record("/health", false)
		}
		close(done)
	}()

	for i := 0; i < 1000; i++ {
		c.Record("/health", false)
	}
	<-done

	snap := c.Snapshot()
	if snap["/health"].TotalRequests != 2000 {
		t.Errorf("got %d, want 2000", snap["/health"].TotalRequests)
	}
}
