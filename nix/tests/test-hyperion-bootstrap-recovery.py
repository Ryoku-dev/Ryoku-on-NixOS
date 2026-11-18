#!/usr/bin/env python3
"""Exercise bootstrap control flow without touching the system or updating NixOS."""

import os
import re
import subprocess
import tempfile
from pathlib import Path

test_path = Path(__file__).resolve()
candidates = (
    test_path.parents[2] / "nix/bootstrap/package.nix",
    test_path.parents[1] / "bootstrap/package.nix",
)
package = next((candidate for candidate in candidates if candidate.is_file()), None)
assert package is not None, "Cannot find the bootstrap package"
source = package.read_text()
match = re.search(r"(?s)\n  text = ''\n(.*?)\n  '';\n}", source)
assert match, "Bootstrap shell body was not found"
shell = match.group(1).replace("''${", "${").replace("${files}", "/mock-nix-files")
assert '${files}' not in shell
with tempfile.TemporaryDirectory(prefix="ryoku-v2-recovery-") as tmp:
    base = Path(tmp)
    runner = base / "ryoku-v2"
    runner.write_text("#!/usr/bin/env bash\nset -euo pipefail\n" + shell + "\n")
    runner.chmod(0o755)
    subprocess.run(["bash", "-n", str(runner)], check=True)

    fake_bin = base / "bin"
    fake_bin.mkdir()
    stub = fake_bin / "ryoku-nix-update"
    stub.write_text("""#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  status)
    case "${MOCK_CHANNEL:-}" in
      ERROR) exit 1 ;;
      INVALID) printf '%s\\n' 'not JSON' ;;
      *) printf '{"channel":"%s","available":true}\\n' "${MOCK_CHANNEL:-feature/hyperion-v2-nixos}" ;;
    esac ;;
  *) printf '%s\\n' "$*" >> "${MOCK_LOG:?}" ;;
esac
""")
    stub.chmod(0o755)

    flake = base / "flake"
    flake.mkdir()
    (flake / "flake.nix").write_text("{}\n")
    log = base / "calls"
    env = os.environ.copy()
    env.update(
        PATH=f"{fake_bin}:{env['PATH']}",
        RYOKU_NIX_FLAKE=str(flake),
        MOCK_LOG=str(log),
    )

    def run(command, channel=None):
        log.unlink(missing_ok=True)
        e = env.copy()
        if channel:
            e["MOCK_CHANNEL"] = channel
        result = subprocess.run([str(runner), command], text=True, capture_output=True, env=e)
        calls = log.read_text().splitlines() if log.exists() else []
        return result, calls

    result, calls = run("authorize")
    assert result.returncode == 0 and not calls and "no longer requires" in result.stdout

    result, calls = run("check")
    assert result.returncode == 0 and not calls and "no longer requires" in result.stdout

    result, calls = run("enter")
    assert result.returncode == 0 and not calls and "Already tracking Hyperion" in result.stdout

    result, calls = run("update")
    assert result.returncode == 0 and calls == ["update"]

    result, calls = run("update", channel="unstable-dev")
    assert result.returncode == 1 and not calls and "not tracking Hyperion" in result.stderr

    for failed in ("ERROR", "INVALID"):
        for command in ("enter", "update"):
            result, calls = run(command, channel=failed)
            assert result.returncode != 0 and not calls
            assert "cannot determine the current channel" in result.stderr

    result, calls = run("enter", channel="unstable-dev")
    assert result.returncode == 0 and calls == ["track hyperion"]

    result, calls = run("slim", channel="unstable-dev")
    assert result.returncode == 0 and calls == ["track hyperion"]

    result, calls = run("leave")
    assert result.returncode == 0 and calls == ["track unstable"]

    result, calls = run("status")
    assert result.returncode == 0 and '"channel"' in result.stdout

    result, calls = run("nonsense")
    assert result.returncode == 2 and "update" in result.stderr

print("Hyperion bootstrap recovery: 14 isolated command cases PASS")
