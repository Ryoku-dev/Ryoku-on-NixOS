import fcntl
import os
from pathlib import Path
import pty
import select
import signal
import struct
import termios
import tempfile
import time

# Self-contained so the check can run from a single store path.
flake = """{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { nixpkgs, ... }: {
    nixosConfigurations.host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ ./configuration.nix ];
    };
  };
}
"""
binary = os.environ["RYOKU_INSTALL_TEST_BINARY"]

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    (root / "flake.nix").write_text(flake)
    (root / "configuration.nix").write_text("{ ... }: { system.stateVersion = \"26.05\"; }\n")
    pid, fd = pty.fork()
    if pid == 0:
        os.environ["TERM"] = "xterm-256color"
        os.execv(binary, [binary, "--flake", directory + "#host", "--dry-run"])
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 112, 0, 0))
    output = bytearray()

    def pump(seconds):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            if select.select([fd], [], [], 0.05)[0]:
                try:
                    data = os.read(fd, 65536)
                except OSError:
                    return
                output.extend(data)
                if b"\x1b[6n" in data:
                    os.write(fd, b"\x1b[1;1R")

    def pump_until(needle, seconds):
        end = time.monotonic() + seconds
        while needle not in output and time.monotonic() < end:
            pump(0.1)
        return needle in output

    def wait_exit(seconds):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            done, status = os.waitpid(pid, os.WNOHANG)
            if done:
                return status
            pump(0.1)
        return None

    try:
        pump(2)
        for _ in range(6):
            os.write(fd, b"\r")
            pump(0.5)
        assert pump_until(b"Dry run complete", 60), "Backend dry run did not complete"
        # The backend has printed its result, but the TUI reports success only
        # after it exits and the TUI takes the terminal back. A key pressed
        # before that screen is up is read while still installing and ignored.
        assert pump_until(b"completed successfully", 30), "TUI did not show success"
        os.write(fd, b"\r")
        status = wait_exit(30)
        assert status is not None, "TUI did not close after success"
        pid = None
        assert os.waitstatus_to_exitcode(status) == 0
        assert (root / "flake.nix").read_text() == flake
        assert not (root / "ryoku.nix").exists()
        print("Packaged TUI and backend dry run passed. Fixture unchanged.")
    finally:
        if pid:
            os.kill(pid, signal.SIGTERM)
            os.waitpid(pid, 0)
        os.close(fd)
