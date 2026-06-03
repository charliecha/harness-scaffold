package main

import (
	"context"
	"flag"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/harness-claude/crypto-snapshot/internal/cache"
	"github.com/harness-claude/crypto-snapshot/internal/client"
	"github.com/harness-claude/crypto-snapshot/internal/handler"
	"github.com/harness-claude/crypto-snapshot/internal/middleware"
	"golang.org/x/time/rate"
)

// Build-time variables injected via -ldflags.
var (
	Version   = "(dev)"
	Commit    = "(none)"
	BuildTime = "(none)"
)

func main() {
	showVersion := flag.Bool("version", false, "print version and exit")
	addr        := flag.String("addr", ":8080", "listen address")
	cacheTTL    := flag.Duration("cache-ttl", 60*time.Second, "price cache TTL")
	rateLimit   := flag.Float64("rate-limit", 10.0, "requests per second per IP")
	burst       := flag.Int("burst", 20, "burst size per IP")
	flag.Parse()

	if *showVersion {
		fmt.Printf("crypto-snapshot version=%s commit=%s built=%s\n", Version, Commit, BuildTime)
		os.Exit(0)
	}

	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	}))
	slog.SetDefault(logger)

	coinClient := client.New()
	priceCache := cache.New(*cacheTTL)
	h := handler.New(
		priceCache,
		coinClient,
		logger,
		handler.VersionInfo{Version: Version, Commit: Commit, BuildTime: BuildTime},
	)

	rl := middleware.New(rate.Limit(*rateLimit), *burst, logger)

	mux := http.NewServeMux()
	mux.HandleFunc("/health", h.Health)
	mux.HandleFunc("/version", h.Version)
	mux.Handle("/snapshot/", rl.Limit(http.HandlerFunc(h.Snapshot)))

	srv := &http.Server{
		Addr:         *addr,
		Handler:      mux,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	logger.Info("starting server",
		slog.String("addr", *addr),
		slog.Duration("cache_ttl", *cacheTTL),
		slog.String("version", Version),
	)

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Error("server error", slog.Any("err", err))
			os.Exit(1)
		}
	}()

	<-quit
	logger.Info("shutting down")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		logger.Error("shutdown error", slog.Any("err", err))
	}
}
