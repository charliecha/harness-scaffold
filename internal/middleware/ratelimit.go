package middleware

import (
	"log/slog"
	"net"
	"net/http"
	"sync"

	"golang.org/x/time/rate"
)

// RateLimiter manages per-IP token bucket limiters.
type RateLimiter struct {
	limiters sync.Map
	r        rate.Limit
	b        int
	logger   *slog.Logger
}

// New returns a RateLimiter with the given rate and burst.
func New(r rate.Limit, b int, logger *slog.Logger) *RateLimiter {
	return &RateLimiter{r: r, b: b, logger: logger}
}

// Limit is an HTTP middleware that enforces per-IP rate limiting.
func (rl *RateLimiter) Limit(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ip := clientIP(r)
		limiter := rl.limiterFor(ip)

		if !limiter.Allow() {
			rl.logger.Warn("rate limited",
				slog.String("ip", ip),
				slog.String("path", r.URL.Path),
				slog.Bool("rate_limited", true),
			)
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusTooManyRequests)
			_, _ = w.Write([]byte(`{"error":"rate limit exceeded"}`))
			return
		}

		next.ServeHTTP(w, r)
	})
}

func (rl *RateLimiter) limiterFor(ip string) *rate.Limiter {
	v, _ := rl.limiters.LoadOrStore(ip, rate.NewLimiter(rl.r, rl.b))
	return v.(*rate.Limiter)
}

// clientIP extracts the real client IP, preferring X-Forwarded-For.
func clientIP(r *http.Request) string {
	if forwarded := r.Header.Get("X-Forwarded-For"); forwarded != "" {
		if host, _, err := net.SplitHostPort(forwarded); err == nil {
			return host
		}
		return forwarded
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}
