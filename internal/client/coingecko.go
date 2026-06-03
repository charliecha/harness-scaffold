package client

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

const baseURL = "https://api.coingecko.com/api/v3"

// CoinPrice holds price data returned by CoinGecko.
type CoinPrice struct {
	ID         string  `json:"id"`
	Symbol     string  `json:"symbol"`
	Name       string  `json:"name"`
	PriceUSD   float64 `json:"current_price"`
	MarketCap  float64 `json:"market_cap"`
	Change24h  float64 `json:"price_change_percentage_24h"`
	UpdatedAt  time.Time
}

// CoinGecko is an HTTP client for the CoinGecko public API.
type CoinGecko struct {
	http    *http.Client
	baseURL string
}

// New returns a CoinGecko client with sensible timeout defaults.
func New() *CoinGecko {
	return &CoinGecko{
		http:    &http.Client{Timeout: 10 * time.Second},
		baseURL: baseURL,
	}
}

// FetchPrice fetches the current USD price for the given coin ID.
func (c *CoinGecko) FetchPrice(ctx context.Context, coinID string) (*CoinPrice, error) {
	url := fmt.Sprintf(
		"%s/coins/markets?vs_currency=usd&ids=%s&per_page=1&page=1",
		c.baseURL, coinID,
	)

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, fmt.Errorf("build request: %w", err)
	}
	req.Header.Set("Accept", "application/json")

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, fmt.Errorf("fetch price: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("unexpected status: %d", resp.StatusCode)
	}

	var prices []CoinPrice
	if err := json.NewDecoder(resp.Body).Decode(&prices); err != nil {
		return nil, fmt.Errorf("decode response: %w", err)
	}
	if len(prices) == 0 {
		return nil, fmt.Errorf("coin not found: %s", coinID)
	}

	prices[0].UpdatedAt = time.Now().UTC()
	return &prices[0], nil
}
