#!/usr/bin/env python3

from pathlib import Path
import os
import re
import sys


def nix_string(value: str) -> str:
    if any(ch in value for ch in ("\n", "\r", "\x00")):
        raise ValueError("source reference must be one line")

    value = (
        value
        .replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("${", "\\${")
    )

    return f'"{value}"'


def set_source(text: str, source: str) -> str:
    outputs = re.search(r"(?m)^[ \t]*outputs[ \t]*=", text)

    if not outputs:
        raise ValueError("could not locate outputs in flake.nix")

    head = text[:outputs.start()]
    tail = text[outputs.start():]

    patterns = [
        re.compile(
            r'(?m)(^[ \t]*(?:inputs\.)?ryoku\.url[ \t]*=[ \t]*)'
            r'(?P<value>"(?:\\.|[^"\\])*")([ \t]*;)'
        ),
        re.compile(
            r'(?ms)(^[ \t]*inputs\.ryoku[ \t]*=[ \t]*\{'
            r'.*?^[ \t]*url[ \t]*=[ \t]*)'
            r'(?P<value>"(?:\\.|[^"\\])*")([ \t]*;)'
        ),
        re.compile(
            r'(?ms)(^[ \t]*inputs[ \t]*=[ \t]*\{'
            r'.*?^[ \t]*ryoku[ \t]*=[ \t]*\{'
            r'.*?^[ \t]*url[ \t]*=[ \t]*)'
            r'(?P<value>"(?:\\.|[^"\\])*")([ \t]*;)'
        ),
    ]

    for pattern in patterns:
        match = pattern.search(head)

        if not match:
            continue

        start, end = match.span("value")

        return (
            head[:start]
            + nix_string(source)
            + head[end:]
            + tail
        )

    raise ValueError(
        "could not safely locate the Ryoku flake input URL"
    )



HYPERION_SOURCE = "github:Ryoku-dev/Ryoku-on-NixOS/feature/hyperion-v2-nixos"
SWITCHER_TAG = "# ryoku-v2-switcher"
SLIM_TAG = "# ryoku-v2-slim"

RYOKU_ENABLED = re.compile(
    r"(?m)^([ \t]*)programs\.ryoku\.enable[ \t]*=[ \t]*true;[ \t]*$"
)
# The installer's ryoku.nix: programs.ryoku = { enable = true; ... };
RYOKU_BLOCK_ENABLED = re.compile(
    r"(?ms)^[ \t]*programs\.ryoku[ \t]*=[ \t]*\{[^{}]*?"
    r"^([ \t]*)enable[ \t]*=[ \t]*true;[ \t]*$"
)


class Target:
    """Where programs.ryoku is enabled, and how options are spelled there."""

    def __init__(self, enabled, prefix):
        self.enabled = enabled
        self.prefix = prefix

    def line(self, option, tag):
        return f"{self.prefix}{option}.enable = true; {tag}"

    def has_option(self, text, option):
        return re.search(
            r"(?m)^[ \t]*" + re.escape(self.prefix + option) + r"\.enable\b", text
        ) is not None

    def remove(self, text, option, tag):
        return re.sub(
            r"(?m)^[ \t]*" + re.escape(self.line(option, tag)) + r"[ \t]*\n",
            "",
            text,
            count=1,
        )


FLAKE_TARGET = Target(RYOKU_ENABLED, "programs.ryoku.")
MODULE_TARGET = Target(RYOKU_BLOCK_ENABLED, "")


def insert_after(text, match, line):
    return (
        text[:match.end()]
        + "\n"
        + match.group(1)
        + line
        + text[match.end():]
    )


def set_hyperion_mode(text: str, active: bool, target: Target = FLAKE_TARGET) -> str:
    marker = target.line("hyperionPackages", SWITCHER_TAG)
    if active:
        if marker in text:
            return text
        if target.has_option(text, "hyperionPackages"):
            raise ValueError("Hyperion is already managed by another NixOS module")

        matches = list(target.enabled.finditer(text))
        if len(matches) != 1:
            raise ValueError(
                "automatic Hyperion switching needs exactly one "
                "programs.ryoku.enable = true; declaration"
            )
        return insert_after(text, matches[0], marker)

    if marker in text:
        return target.remove(text, "hyperionPackages", SWITCHER_TAG)
    if target.has_option(text, "hyperionPackages"):
        raise ValueError("refusing to remove a manually managed Hyperion setting")
    return text


def set_niri_only(text: str, active: bool, target: Target = FLAKE_TARGET) -> str:
    marker = target.line("hyperionNiriOnly", SLIM_TAG)
    if not active:
        if marker in text:
            return target.remove(text, "hyperionNiriOnly", SLIM_TAG)
        if target.has_option(text, "hyperionNiriOnly"):
            raise ValueError("refusing to remove a manually managed Niri-only setting")
        return text

    if marker in text:
        return text
    if target.has_option(text, "hyperionNiriOnly"):
        raise ValueError("Niri-only is already managed by another NixOS module")

    switcher = target.line("hyperionPackages", SWITCHER_TAG)
    match = re.search(r"(?m)^([ \t]*)" + re.escape(switcher) + r"$", text)
    if not match:
        raise ValueError("enable Hyperion before selecting Niri-only")
    return insert_after(text, match, marker)


def remove_legacy_ryotunes_input(text: str) -> str:
    return re.sub(
        r'(?m)^[ \t]*inputs\.ryotunesNix\.url\s*=\s*'
        r'"github:Ryoku-dev/RyotunesNix/[^"\n]+";[ \t]*\n',
        "",
        text,
    )


def apply_mode(text: str, source: str, target: Target) -> str:
    if source == HYPERION_SOURCE:
        text = set_hyperion_mode(text, True, target)
        if os.environ.get("RYOKU_NIX_HYPERION_NIRI_ONLY") == "1":
            text = set_niri_only(text, True, target)
    elif source in (
        "github:Ryoku-dev/Ryoku-on-NixOS/main",
        "github:Ryoku-dev/Ryoku-on-NixOS/unstable-dev",
    ):
        text = set_niri_only(text, False, target)
        text = set_hyperion_mode(text, False, target)
    return text


def flake_owns_ryoku(text: str) -> bool:
    return bool(RYOKU_ENABLED.search(text)) or SWITCHER_TAG in text


def main() -> int:
    if len(sys.argv) not in (3, 4):
        print(
            "usage: ryoku-nix-track-edit.py FLAKE SOURCE [RYOKU_MODULE]",
            file=sys.stderr,
        )
        return 2

    path = Path(sys.argv[1])
    module = Path(sys.argv[3]) if len(sys.argv) == 4 else None

    try:
        source = sys.argv[2]
        flake = set_source(path.read_text(), source)
        if source == HYPERION_SOURCE and os.environ.get("RYOKU_NIX_HYPERION_NIRI_ONLY") == "1":
            flake = remove_legacy_ryotunes_input(flake)

        module_text = None
        if flake_owns_ryoku(flake) or module is None:
            flake = apply_mode(flake, source, FLAKE_TARGET)
        else:
            module_text = apply_mode(module.read_text(), source, MODULE_TARGET)

        path.write_text(flake)
        if module_text is not None:
            module.write_text(module_text)
    except (OSError, ValueError) as exc:
        print(f"ryoku-nix-track-edit: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
