#!/usr/bin/env python3
import ctypes
import os
import signal
import sys


def main():
    if len(sys.argv) < 2:
        raise SystemExit("usage: parent-owned.py COMMAND [ARG ...]")

    parent = os.getppid()
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.prctl(1, signal.SIGTERM, 0, 0, 0) != 0:  # PR_SET_PDEATHSIG
        err = ctypes.get_errno()
        raise OSError(err, os.strerror(err))
    if os.getppid() != parent:
        return

    os.execvp(sys.argv[1], sys.argv[1:])


if __name__ == "__main__":
    main()
