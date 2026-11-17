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


# A NixOS host can enable Ryoku in any imported module. Add a host-local
# override to the flake's modules list rather than guessing where it lives.
HOST_OVERRIDE_TAG = "# ryoku-v2-host-override"
HOST_OVERRIDE = "{ programs.ryoku.hyperionPackages.enable = true; } " + HOST_OVERRIDE_TAG
HOST_SLIM_TAG = "# ryoku-v2-host-slim"
HOST_SLIM = "{ programs.ryoku.hyperionNiriOnly.enable = true; } " + HOST_SLIM_TAG
MODULES_LIST = re.compile(r"(?m)^[ \t]*modules[ \t]*=[ \t]*\[")


def host_modules(text: str) -> re.Match:
    matches = list(MODULES_LIST.finditer(text))
    if len(matches) == 1:
        return matches[0]

    host = os.environ.get("RYOKU_NIX_HOST", "")
    if not host or not re.fullmatch(r"[a-zA-Z0-9_-]+", host):
        raise ValueError("multiple NixOS hosts found; cannot choose a modules list safely")

    declaration = re.search(
        r"nixosConfigurations\." + re.escape(host) + r"[ \t]*=", text
    )
    if declaration is None:
        raise ValueError("cannot find host " + host + " in flake.nix")
    next_host = re.search(r"nixosConfigurations\.[a-zA-Z0-9_-]+[ \t]*=", text[declaration.end():])
    limit = declaration.end() + next_host.start() if next_host else len(text)
    local = [m for m in matches if declaration.end() <= m.start() < limit]
    if len(local) != 1:
        raise ValueError("cannot identify exactly one modules list for " + host)
    return local[0]


def set_host_override(text: str, source: str) -> str:
    if source == HYPERION_SOURCE:
        if FLAKE_TARGET.has_option(text, "hyperionPackages") and HOST_OVERRIDE not in text:
            raise ValueError("Hyperion option is already managed elsewhere in flake.nix")
        if HOST_OVERRIDE not in text:
            match = host_modules(text)
            text = text[:match.end()] + "\n      " + HOST_OVERRIDE + "\n" + text[match.end():]
        if os.environ.get("RYOKU_NIX_HYPERION_NIRI_ONLY") == "1" and HOST_SLIM not in text:
            if FLAKE_TARGET.has_option(text, "hyperionNiriOnly"):
                raise ValueError("Niri-only option is already managed elsewhere in flake.nix")
            match = host_modules(text)
            text = text[:match.end()] + "\n      " + HOST_SLIM + "\n" + text[match.end():]
    elif source in (
        "github:Ryoku-dev/Ryoku-on-NixOS/main",
        "github:Ryoku-dev/Ryoku-on-NixOS/unstable-dev",
    ):
        text = text.replace("\n      " + HOST_SLIM + "\n", "", 1)
        text = text.replace("\n      " + HOST_OVERRIDE + "\n", "", 1)
    return text


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
        if HOST_OVERRIDE_TAG in flake:
            flake = set_host_override(flake, source)
        elif SWITCHER_TAG in flake or (
            RYOKU_ENABLED.search(flake) and len(MODULES_LIST.findall(flake)) <= 1
        ):
            flake = apply_mode(flake, source, FLAKE_TARGET)
        elif module is not None and RYOKU_BLOCK_ENABLED.search(module.read_text()):
            module_text = apply_mode(module.read_text(), source, MODULE_TARGET)
        else:
            flake = set_host_override(flake, source)

        path.write_text(flake)
        if module_text is not None:
            module.write_text(module_text)
    except (OSError, ValueError) as exc:
        print(f"ryoku-nix-track-edit: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
