package health

import (
	"context"
	"net/http"
	"time"
)

const defaultPingURL = "https://api.coingecko.com/api/v3/ping"

// CoinGeckoChecker probes the CoinGecko /ping endpoint.
// Timeout is controlled by the caller via ctx.
type CoinGeckoChecker struct {
	client  *http.Client
	pingURL string
}

// NewCoinGeckoChecker returns a CoinGeckoChecker.
// Timeout is owned by the caller's context, so http.Client has no global timeout.
func NewCoinGeckoChecker() *CoinGeckoChecker {
	return &CoinGeckoChecker{
		client:  &http.Client{},
		pingURL: defaultPingURL,
	}
}

func (c *CoinGeckoChecker) Name() string { return "coingecko" }

func (c *CoinGeckoChecker) Check(ctx context.Context) Result {
	t0 := time.Now()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.pingURL, nil)
	if err != nil {
		return Result{Status: "unavailable", LatencyMs: time.Since(t0).Milliseconds()}
	}

	resp, err := c.client.Do(req)
	latencyMs := time.Since(t0).Milliseconds()
	if err != nil {
		return Result{Status: "unavailable", LatencyMs: latencyMs}
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return Result{Status: "unavailable", LatencyMs: latencyMs}
	}
	return Result{Status: "ok", LatencyMs: latencyMs}
}
