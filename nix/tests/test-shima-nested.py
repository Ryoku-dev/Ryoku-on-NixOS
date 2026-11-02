#!/usr/bin/env python3
"""Exercise Shima in an isolated nested compositor, never the live session."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime", required=True, type=Path)
    parser.add_argument("--daemon", required=True, type=Path)
    parser.add_argument("--native-root", required=True, type=Path)
    parser.add_argument("--bwrap", required=True)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    home = Path(tempfile.mkdtemp(prefix="home-", dir=output))
    (output/"probe.sh").write_text((Path(__file__).with_name("shima-nested-probe.sh")).read_text())
    (output/"probe.sh").chmod(0o755)
    (output/"niri.kdl").write_text("prefer-no-csd\nhotkey-overlay { skip-at-startup; }\n")
    (output/"start.sh").write_text("""#!/usr/bin/env bash
set -eu
mkdir -p /tmp/shima-runtime
chmod 700 /tmp/shima-runtime
export XDG_RUNTIME_DIR=/tmp/shima-runtime
unset NIRI_SOCKET DBUS_SESSION_BUS_ADDRESS
exec dbus-run-session -- niri -c /mnt/niri.kdl -- /mnt/probe.sh
""")
    (output/"start.sh").chmod(0o755)
    env = os.environ.copy()
    env["WAYLAND_DISPLAY"] = str(Path(env["XDG_RUNTIME_DIR"])/env["WAYLAND_DISPLAY"])
    env["QT_QPA_PLATFORM"] = "wayland"
    env["DBUS_SYSTEM_BUS_ADDRESS"] = "unix:path=/no-host-system-bus"
    env["XDG_CONFIG_HOME"] = str(Path.home()/".config/shima-probe-config")
    env["SHIMA_TEST_PACKAGE"] = str(args.runtime.resolve())
    env["SHIMA_TEST_DAEMON"] = str(args.daemon.resolve())
    env["SHIMA_TEST_NATIVE_ROOT"] = str(args.native_root.resolve())
    command = [args.bwrap, "--die-with-parent", "--new-session", "--unshare-pid",
               "--ro-bind", "/", "/", "--dev-bind", "/dev", "/dev",
               "--proc", "/proc", "--tmpfs", "/tmp",
               "--bind", str(home), str(Path.home()),
               "--bind", str(output), "/mnt", "/mnt/start.sh"]
    with (output/"compositor.log").open("w") as out:
        result = subprocess.run(command, env=env, stdout=out, stderr=subprocess.STDOUT, timeout=150)
    report = output/"result.json"
    if report.exists():
        data = json.loads(report.read_text())
        print(json.dumps(data, indent=2))
        if not data.get("passed"):
            raise SystemExit(1)
    else:
        raise SystemExit("Nested probe did not finish. Inspect compositor.log and daemon.log.")
    raise SystemExit(result.returncode)

if __name__ == "__main__":
    main()
