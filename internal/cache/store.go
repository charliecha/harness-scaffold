package cache

import (
	"sync"
	"time"

	"github.com/harness-claude/crypto-snapshot/internal/client"
)

// Snapshot is a cached price entry with an expiry timestamp.
type Snapshot struct {
	Price     *client.CoinPrice
	ExpiresAt time.Time
}

// Store is a thread-safe in-memory cache for coin snapshots.
type Store struct {
	mu    sync.RWMutex
	items map[string]Snapshot
	ttl   time.Duration
}

// New returns a Store with the given TTL per entry.
func New(ttl time.Duration) *Store {
	return &Store{
		items: make(map[string]Snapshot),
		ttl:   ttl,
	}
}

// Get returns a cached snapshot if present and not expired.
func (s *Store) Get(coinID string) (*client.CoinPrice, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	snap, ok := s.items[coinID]
	if !ok || time.Now().After(snap.ExpiresAt) {
		return nil, false
	}
	return snap.Price, true
}

// Set stores a price snapshot for coinID.
func (s *Store) Set(coinID string, price *client.CoinPrice) {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.items[coinID] = Snapshot{
		Price:     price,
		ExpiresAt: time.Now().Add(s.ttl),
	}
}
