package main

import (
	"context"
	"fmt"
	"io"
	"sync"
	"time"
)

const progressInterval = 100 * time.Millisecond

type progressContextKey struct{}

type progressReporter struct {
	mu       sync.Mutex
	writer   io.Writer
	now      func() time.Time
	interval time.Duration
	lastAt   time.Time
	stage    string
	done     int64
	total    int64
}

func newProgressReporter(writer io.Writer) *progressReporter {
	return &progressReporter{
		writer:   writer,
		now:      time.Now,
		interval: progressInterval,
	}
}

func withProgress(ctx context.Context, reporter *progressReporter) context.Context {
	return context.WithValue(ctx, progressContextKey{}, reporter)
}

func progressFromContext(ctx context.Context) *progressReporter {
	if ctx == nil {
		return nil
	}
	reporter, _ := ctx.Value(progressContextKey{}).(*progressReporter)
	return reporter
}

func validProgressStage(stage string) bool {
	switch stage {
	case "download", "extract", "verify", "apply":
		return true
	default:
		return false
	}
}

func (p *progressReporter) report(stage string, done, total int64, force bool) {
	if p == nil || p.writer == nil || !validProgressStage(stage) {
		return
	}
	if done < 0 {
		done = 0
	}
	if total < 0 {
		total = 0
	}
	if total > 0 && done > total {
		done = total
	}

	p.mu.Lock()
	defer p.mu.Unlock()
	if stage == p.stage && done == p.done && total == p.total {
		return
	}
	now := p.now()
	stageChanged := stage != p.stage
	if !force && !stageChanged && !p.lastAt.IsZero() && now.Sub(p.lastAt) < p.interval {
		return
	}
	fmt.Fprintf(p.writer, "RYOSTORE-PROGRESS %s %d %d\n", stage, done, total)
	p.stage = stage
	p.done = done
	p.total = total
	p.lastAt = now
}

func reportProgress(ctx context.Context, stage string, done, total int64) {
	if reporter := progressFromContext(ctx); reporter != nil {
		reporter.report(stage, done, total, false)
	}
}

func reportProgressNow(ctx context.Context, stage string, done, total int64) {
	if reporter := progressFromContext(ctx); reporter != nil {
		reporter.report(stage, done, total, true)
	}
}

type progressReader struct {
	reader io.Reader
	ctx    context.Context
	stage  string
	base   int64
	done   int64
	total  int64
}

func (r *progressReader) Read(buffer []byte) (int, error) {
	n, err := r.reader.Read(buffer)
	if n > 0 {
		r.done += int64(n)
		reportProgress(r.ctx, r.stage, r.base+r.done, r.total)
	}
	return n, err
}

func readerWithProgress(ctx context.Context, reader io.Reader, stage string, base, total int64) io.Reader {
	if progressFromContext(ctx) == nil {
		return reader
	}
	return &progressReader{
		reader: reader,
		ctx:    ctx,
		stage:  stage,
		base:   base,
		total:  total,
	}
}
