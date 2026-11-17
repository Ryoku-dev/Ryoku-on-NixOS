#!/usr/bin/env python3
import argparse
import json
import re
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--project-lock", required=True, type=Path)
parser.add_argument("--install-source", required=True, type=Path)
parser.add_argument("--overlay", required=True, type=Path)
parser.add_argument("--tokens", required=True, type=Path)
args = parser.parse_args()

project = json.loads(args.project_lock.read_text())
generated = json.loads((args.install_source / "flake.lock").read_text())

expected = project["nodes"]["ryokuPackagesNixpkgs"]["locked"]
actual = generated["nodes"]["nixpkgs"]["locked"]
assert actual == expected, "RyoStore Shima must use Ryoku's pinned Nixpkgs"
assert generated["nodes"]["inirSrc"]["locked"] == project["nodes"]["inirSrc"]["locked"]
assert generated["nodes"]["root"]["inputs"] == {"nixpkgs": "nixpkgs", "inirSrc": "inirSrc"}

source = (args.install_source / "flake.nix").read_text()
assert f'github:NixOS/nixpkgs/{expected["rev"]}' in source
assert "overlays = [ (import ./quickshell-screencopy-overlay.nix) ]" in source
assert (args.install_source / "quickshell-screencopy-overlay.nix").read_bytes() == args.overlay.read_bytes()
assert (args.install_source / "ryoku/ui/Singletons/Tokens.qml").read_bytes() == args.tokens.read_bytes()

source_package = (args.install_source / "ryoku-shima.nix").read_text()
required = set(re.findall(r"\$\{\./shima/([A-Za-z0-9_.-]+)\}", source_package))
assert "ShellBridge.qmlfrag" in required, "Shima bridge is no longer referenced"
for filename in sorted(required):
    assert (args.install_source / "shima" / filename).is_file(), (
        f"Missing packaged Shima source file: {filename}"
    )

# The package is copied to the root of the standalone flake, so a parent-relative
# interpolation would escape it and fail pure evaluation during RyoStore installs.
escaping = re.findall(r"\$\{(\.\./[^}]*)\}", source_package)
assert not escaping, f"Shima package reaches outside the install source: {escaping}"
for relative in sorted(set(re.findall(r"=\s*\./([A-Za-z0-9_./-]+);", source))):
    assert (args.install_source / relative).is_file(), (
        f"Standalone Shima flake passes a missing file: {relative}"
    )
assert "overviewTerminalPatch = ./" in source, "Overview/terminal patch is not passed"

print("RyoStore Shima matches Ryoku's pinned Qt, Quickshell, and live theme tokens.")
