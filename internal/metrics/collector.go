package metrics

import (
	"net/http"
	"sync"
	"sync/atomic"
)

// RouteStats holds atomic counters for a single route.
type RouteStats struct {
	TotalRequests       atomic.Int64
	RateLimitedRequests atomic.Int64
}

// RouteStatsJSON is the serializable snapshot of RouteStats.
type RouteStatsJSON struct {
	TotalRequests       int64 `json:"total_requests"`
	RateLimitedRequests int64 `json:"rate_limited_requests"`
}

// Collector tracks per-route request statistics.
type Collector struct {
	routes sync.Map // key: string, value: *RouteStats
}

// New returns an empty Collector.
func New() *Collector {
	return &Collector{}
}

// Record increments counters for the given route.
func (c *Collector) Record(route string, rateLimited bool) {
	v, _ := c.routes.LoadOrStore(route, &RouteStats{})
	stats := v.(*RouteStats)
	stats.TotalRequests.Add(1)
	if rateLimited {
		stats.RateLimitedRequests.Add(1)
	}
}

// Snapshot returns a point-in-time copy of all route statistics.
func (c *Collector) Snapshot() map[string]RouteStatsJSON {
	result := make(map[string]RouteStatsJSON)
	c.routes.Range(func(key, value any) bool {
		stats := value.(*RouteStats)
		result[key.(string)] = RouteStatsJSON{
			TotalRequests:       stats.TotalRequests.Load(),
			RateLimitedRequests: stats.RateLimitedRequests.Load(),
		}
		return true
	})
	return result
}

// Middleware wraps an http.Handler, recording stats for route on each request.
func (c *Collector) Middleware(route string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		rw := &responseWriter{ResponseWriter: w}
		next.ServeHTTP(rw, r)
		c.Record(route, rw.statusCode == http.StatusTooManyRequests)
	})
}

// WrapFunc wraps an http.HandlerFunc, recording stats for route on each request.
func (c *Collector) WrapFunc(route string, fn http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		rw := &responseWriter{ResponseWriter: w}
		fn(rw, r)
		c.Record(route, false)
	}
}

// responseWriter captures the status code written by a handler.
type responseWriter struct {
	http.ResponseWriter
	statusCode int
}

func (rw *responseWriter) WriteHeader(code int) {
	rw.statusCode = code
	rw.ResponseWriter.WriteHeader(code)
}

// Write intercepts implicit 200 responses (when handler calls Write without WriteHeader).
func (rw *responseWriter) Write(b []byte) (int, error) {
	if rw.statusCode == 0 {
		rw.statusCode = http.StatusOK
	}
	return rw.ResponseWriter.Write(b)
}
