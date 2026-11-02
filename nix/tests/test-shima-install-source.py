#!/usr/bin/env python3
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--project-lock", required=True, type=Path)
parser.add_argument("--install-source", required=True, type=Path)
parser.add_argument("--overlay", required=True, type=Path)
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

print("RyoStore Shima matches Ryoku's pinned Qt and Quickshell package universe.")
