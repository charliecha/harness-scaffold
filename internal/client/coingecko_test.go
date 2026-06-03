package client

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestFetchPrice_success(t *testing.T) {
	fixture := []map[string]interface{}{
		{
			"id":                            "bitcoin",
			"symbol":                        "btc",
			"name":                          "Bitcoin",
			"current_price":                 50000.0,
			"market_cap":                    1e12,
			"price_change_percentage_24h":   2.5,
		},
	}
	body, _ := json.Marshal(fixture)

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write(body)
	}))
	defer srv.Close()

	c := &CoinGecko{
		http:    srv.Client(),
		baseURL: srv.URL,
	}

	price, err := c.FetchPrice(context.Background(), "bitcoin")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if price.ID != "bitcoin" {
		t.Errorf("got id %q, want %q", price.ID, "bitcoin")
	}
	if price.PriceUSD != 50000.0 {
		t.Errorf("got price %f, want 50000.0", price.PriceUSD)
	}
	if price.UpdatedAt.IsZero() {
		t.Error("UpdatedAt should be set")
	}
}

func TestFetchPrice_notFound(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte("[]"))
	}))
	defer srv.Close()

	c := &CoinGecko{http: srv.Client(), baseURL: srv.URL}
	_, err := c.FetchPrice(context.Background(), "unknown_coin")
	if err == nil {
		t.Fatal("expected error for empty result, got nil")
	}
}

func TestFetchPrice_serverError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer srv.Close()

	c := &CoinGecko{http: srv.Client(), baseURL: srv.URL}
	_, err := c.FetchPrice(context.Background(), "bitcoin")
	if err == nil {
		t.Fatal("expected error for 500, got nil")
	}
}

func TestFetchPrice_invalidJSON(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte("not json"))
	}))
	defer srv.Close()

	c := &CoinGecko{http: srv.Client(), baseURL: srv.URL}
	_, err := c.FetchPrice(context.Background(), "bitcoin")
	if err == nil {
		t.Fatal("expected error for invalid JSON, got nil")
	}
}
