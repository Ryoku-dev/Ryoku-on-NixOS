package updater

import (
	"os"
	"os/signal"
	"sync"
	"sync/atomic"
	"syscall"
)

// A run can be stopped -- Ctrl-C, a closed terminal, or the Hub's Stop on a
// stalled step (`ryoku update --cancel`). Dying on the signal would leave
// whatever the run had quiesced quiesced: no shell, a sleep block that denies
// every suspend until logout. So a stop unwinds instead: each step that takes
// something registers how to give it back, the handler runs those in reverse,
// signals the run's own children (package managers excepted: they finish or
// roll back their transaction themselves), records the stop, and exits.

type abortHook struct {
	name string
	fn   func()
}

var (
	abortMu    sync.Mutex
	abortHooks []abortHook
	// stopping is set the moment a stop signal lands: the step the signal
	// also killed fails on the main goroutine at the same time, and that
	// failure must neither replace the stop on screen nor exit first.
	stopping atomic.Bool
)

// onAbort registers how to undo name if the run is stopped.
func onAbort(name string, fn func()) {
	abortMu.Lock()
	defer abortMu.Unlock()
	abortHooks = append(abortHooks, abortHook{name, fn})
}

// dropAbort forgets name once the run has given it back itself.
func dropAbort(name string) {
	abortMu.Lock()
	defer abortMu.Unlock()
	for i := len(abortHooks) - 1; i >= 0; i-- {
		if abortHooks[i].name == name {
			abortHooks = append(abortHooks[:i], abortHooks[i+1:]...)
			return
		}
	}
}

// trapStop installs the stop handler for this process's share of the run.
func trapStop() {
	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, syscall.SIGINT, syscall.SIGTERM, syscall.SIGHUP)
	go func() {
		<-sigs
		stopping.Store(true)
		signal.Ignore(syscall.SIGINT, syscall.SIGTERM, syscall.SIGHUP)
		terminateTree(os.Getpid())
		abortMu.Lock()
		hooks := abortHooks
		abortHooks = nil
		abortMu.Unlock()
		for i := len(hooks) - 1; i >= 0; i-- {
			hooks[i].fn()
		}
		progress.fail(errStopped)
		con.close()
		stopUpdateLog()
		os.Exit(130)
	}()
}
