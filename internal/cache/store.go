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
	HitCount  int64
}

// CacheEntry is a read-only view of a cache item returned by Status.
type CacheEntry struct {
	CoinID   string
	TTLSec   int64
	HitCount int64
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
// Uses a write lock to increment HitCount atomically on cache hit.
func (s *Store) Get(coinID string) (*client.CoinPrice, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()

	snap, ok := s.items[coinID]
	if !ok || time.Now().After(snap.ExpiresAt) {
		return nil, false
	}
	snap.HitCount++
	s.items[coinID] = snap
	return snap.Price, true
}

// Set stores a price snapshot for coinID, resetting HitCount to 0.
func (s *Store) Set(coinID string, price *client.CoinPrice) {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.items[coinID] = Snapshot{
		Price:     price,
		ExpiresAt: time.Now().Add(s.ttl),
		HitCount:  0,
	}
}

// Status returns a snapshot view of all unexpired cache entries.
// Expired entries are excluded. Order is not guaranteed.
func (s *Store) Status() []CacheEntry {
	s.mu.RLock()
	defer s.mu.RUnlock()

	now := time.Now()
	entries := make([]CacheEntry, 0, len(s.items))
	for coinID, snap := range s.items {
		remaining := snap.ExpiresAt.Sub(now)
		if remaining < time.Second {
			continue
		}
		entries = append(entries, CacheEntry{
			CoinID:   coinID,
			TTLSec:   int64(remaining.Seconds()),
			HitCount: snap.HitCount,
		})
	}
	return entries
}
