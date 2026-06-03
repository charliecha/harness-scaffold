package health

import "context"

// Result holds the outcome of a single dependency probe.
type Result struct {
	Status    string // "ok" or "unavailable"
	LatencyMs int64  // round-trip latency in milliseconds, non-negative
}

// Checker abstracts a probeable dependency.
// Implementations must respect ctx cancellation/timeout.
type Checker interface {
	Name() string
	Check(ctx context.Context) Result
}
