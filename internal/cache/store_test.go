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

func TestStore_HitCount_initial(t *testing.T) {
	s := New(time.Minute)
	s.Set("bitcoin", makePrice("bitcoin", 50000))

	entries := s.Status()
	if len(entries) != 1 {
		t.Fatalf("want 1 entry, got %d", len(entries))
	}
	if entries[0].HitCount != 0 {
		t.Errorf("AC-6: initial hit_count want 0, got %d", entries[0].HitCount)
	}
}

func TestStore_HitCount_increments(t *testing.T) {
	s := New(time.Minute)
	s.Set("bitcoin", makePrice("bitcoin", 50000))

	for range 3 {
		s.Get("bitcoin")
	}

	entries := s.Status()
	if len(entries) != 1 {
		t.Fatalf("want 1 entry, got %d", len(entries))
	}
	if entries[0].HitCount != 3 {
		t.Errorf("AC-7: hit_count want 3, got %d", entries[0].HitCount)
	}
}

func TestStore_HitCount_resetOnSet(t *testing.T) {
	s := New(time.Minute)
	s.Set("bitcoin", makePrice("bitcoin", 50000))
	s.Get("bitcoin")
	s.Get("bitcoin")

	s.Set("bitcoin", makePrice("bitcoin", 60000))

	entries := s.Status()
	if len(entries) != 1 {
		t.Fatalf("want 1 entry, got %d", len(entries))
	}
	if entries[0].HitCount != 0 {
		t.Errorf("AC-8: hit_count after Set want 0, got %d", entries[0].HitCount)
	}
}

func TestStore_Status_empty(t *testing.T) {
	s := New(time.Minute)
	entries := s.Status()
	if len(entries) != 0 {
		t.Errorf("want empty slice, got %d entries", len(entries))
	}
}

func TestStore_Status_excludesExpired(t *testing.T) {
	s := New(10 * time.Millisecond)
	s.Set("bitcoin", makePrice("bitcoin", 50000))
	time.Sleep(20 * time.Millisecond)

	entries := s.Status()
	if len(entries) != 0 {
		t.Errorf("want 0 entries after expiry, got %d", len(entries))
	}
}

func TestStore_Status_ttlPositive(t *testing.T) {
	s := New(time.Minute)
	s.Set("bitcoin", makePrice("bitcoin", 50000))

	entries := s.Status()
	if len(entries) != 1 {
		t.Fatalf("want 1 entry, got %d", len(entries))
	}
	if entries[0].TTLSec < 1 {
		t.Errorf("TTLSec want >= 1, got %d", entries[0].TTLSec)
	}
}

func TestStore_Status_excludesSubSecondTTL(t *testing.T) {
	// Entries with < 1s remaining must not appear (ttl_sec >= 1 hard constraint)
	s := New(500 * time.Millisecond)
	s.Set("bitcoin", makePrice("bitcoin", 50000))

	// Wait until remaining TTL < 1s but entry not yet expired
	time.Sleep(100 * time.Millisecond)

	entries := s.Status()
	if len(entries) != 0 {
		t.Errorf("want 0 entries when ttl < 1s, got %d (ttl_sec=%d)", len(entries), entries[0].TTLSec)
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
