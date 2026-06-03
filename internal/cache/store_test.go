package cache

import (
	"testing"
	"time"

	"github.com/harness-claude/crypto-snapshot/internal/client"
)

func makePrice(id string, usd float64) *client.CoinPrice {
	return &client.CoinPrice{ID: id, PriceUSD: usd, UpdatedAt: time.Now()}
}

func TestStore_GetSet(t *testing.T) {
	s := New(time.Minute)

	_, ok := s.Get("bitcoin")
	if ok {
		t.Fatal("expected miss on empty store")
	}

	p := makePrice("bitcoin", 50000)
	s.Set("bitcoin", p)

	got, ok := s.Get("bitcoin")
	if !ok {
		t.Fatal("expected hit after Set")
	}
	if got.PriceUSD != 50000 {
		t.Errorf("got %f, want 50000", got.PriceUSD)
	}
}

func TestStore_Expiry(t *testing.T) {
	s := New(10 * time.Millisecond)
	s.Set("bitcoin", makePrice("bitcoin", 50000))

	time.Sleep(20 * time.Millisecond)

	_, ok := s.Get("bitcoin")
	if ok {
		t.Fatal("expected miss after TTL expiry")
	}
}

func TestStore_Overwrite(t *testing.T) {
	s := New(time.Minute)
	s.Set("bitcoin", makePrice("bitcoin", 40000))
	s.Set("bitcoin", makePrice("bitcoin", 60000))

	got, ok := s.Get("bitcoin")
	if !ok {
		t.Fatal("expected hit")
	}
	if got.PriceUSD != 60000 {
		t.Errorf("got %f, want 60000", got.PriceUSD)
	}
}

func TestStore_ConcurrentAccess(t *testing.T) {
	s := New(time.Minute)
	done := make(chan struct{})

	go func() {
		for i := 0; i < 100; i++ {
			s.Set("btc", makePrice("btc", float64(i)))
		}
		close(done)
	}()

	for i := 0; i < 100; i++ {
		s.Get("btc")
	}
	<-done
}
