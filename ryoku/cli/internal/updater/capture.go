package updater

import (
	"bytes"
	"io"
	"os"
	"regexp"
	"strings"
	"sync"
	"syscall"
	"time"
)

// capture points this process's stdout and stderr -- and so every child it
// starts -- at the per-update raw log, and tails that log so the console can
// show what is happening without printing all of it. Redirecting the file
// descriptors, rather than threading a writer through every helper, is what
// makes the curated view total: pacman, git, deploy.sh, the doctor, snapper
// notes and Go's own warnings all land in the log, none on the terminal.
//
// The sink is the log file itself, not a pipe. A daemon some step starts can
// inherit the descriptor and outlive the update; writing into a file costs it
// nothing, where a pipe would block it or kill it with SIGPIPE once nobody
// reads.
type capture struct {
	term    *os.File // the original stdout, kept for the console
	errFd   int      // the original stderr
	log     *os.File
	offset  int64
	partial []byte
	onLine  func(string)
	stop    chan struct{}
	done    chan struct{}
	mu      sync.Mutex
}

// startCapture redirects fds 1 and 2 into log (opened O_APPEND) and starts the
// tail. Returns nil when the descriptors cannot be moved; the caller then runs
// uncaptured.
func startCapture(log *os.File, onLine func(string)) *capture {
	outFd, err := syscall.Dup(1)
	if err != nil {
		return nil
	}
	errFd, err := syscall.Dup(2)
	if err != nil {
		syscall.Close(outFd)
		return nil
	}
	syscall.CloseOnExec(outFd)
	syscall.CloseOnExec(errFd)
	off, _ := log.Seek(0, io.SeekEnd)
	if syscall.Dup3(int(log.Fd()), 1, 0) != nil || syscall.Dup3(int(log.Fd()), 2, 0) != nil {
		_ = syscall.Dup3(outFd, 1, 0)
		_ = syscall.Dup3(errFd, 2, 0)
		syscall.Close(outFd)
		syscall.Close(errFd)
		return nil
	}
	c := &capture{
		term:   os.NewFile(uintptr(outFd), "terminal"),
		errFd:  errFd,
		log:    log,
		offset: off,
		onLine: onLine,
		stop:   make(chan struct{}),
		done:   make(chan struct{}),
	}
	go c.tail()
	return c
}

func (c *capture) tail() {
	defer close(c.done)
	t := time.NewTicker(120 * time.Millisecond)
	defer t.Stop()
	for {
		select {
		case <-c.stop:
			c.drain()
			return
		case <-t.C:
			c.drain()
		}
	}
}

// drain reads whatever the log gained since the last pass and hands each
// complete line on. A carriage return ends a line too, so a redrawn progress
// bar arrives as its updates rather than one buffered mega-line.
func (c *capture) drain() {
	c.mu.Lock()
	defer c.mu.Unlock()
	buf := make([]byte, 64*1024)
	for {
		n, err := c.log.ReadAt(buf, c.offset)
		if n > 0 {
			c.offset += int64(n)
			c.partial = append(c.partial, buf[:n]...)
			for {
				i := bytes.IndexAny(c.partial, "\r\n")
				if i < 0 {
					break
				}
				line := string(c.partial[:i])
				c.partial = c.partial[i+1:]
				if s := cleanLine(line); s != "" {
					c.onLine(s)
				}
			}
			if len(c.partial) > 16*1024 { // a line with no end in sight
				c.onLine(cleanLine(string(c.partial)))
				c.partial = c.partial[:0]
			}
		}
		if err != nil || n < len(buf) {
			return
		}
	}
}

// flush hands on whatever the log gained since the last pass, now, so a
// closing card sees the very last lines the run printed. nil-safe.
func (c *capture) flush() {
	if c != nil && c.term != nil {
		c.drain()
	}
}

// release puts fds 1 and 2 back on the terminal and stops the tail after one
// last pass. Safe to call twice.
func (c *capture) release() {
	if c == nil || c.term == nil {
		return
	}
	_ = syscall.Dup3(int(c.term.Fd()), 1, 0)
	_ = syscall.Dup3(c.errFd, 2, 0)
	close(c.stop)
	<-c.done
	c.term.Close()
	syscall.Close(c.errFd)
	c.term = nil
}

var ansiRe = regexp.MustCompile(`\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07]*\x07`)

// cleanLine strips terminal escapes and collapses runs of whitespace. pure.
func cleanLine(s string) string {
	s = ansiRe.ReplaceAllString(s, "")
	return strings.Join(strings.Fields(s), " ")
}
