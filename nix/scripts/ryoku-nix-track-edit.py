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
HYPERION_MARKER = "programs.ryoku.hyperionPackages.enable = true; # ryoku-v2-switcher"
HYPERION_OPTION = "programs.ryoku.hyperionPackages.enable"
NIRI_MARKER = "programs.ryoku.hyperionNiriOnly.enable = true; # ryoku-v2-slim"
NIRI_OPTION = "programs.ryoku.hyperionNiriOnly.enable"

RYOKU_ENABLED = re.compile(
    r"(?m)^([ \t]*)programs\.ryoku\.enable[ \t]*=[ \t]*true;[ \t]*$"
)


def set_hyperion_mode(text: str, active: bool) -> str:
    if active:
        if HYPERION_MARKER in text:
            return text
        if HYPERION_OPTION in text:
            raise ValueError("Hyperion is already managed by another NixOS module")

        matches = list(RYOKU_ENABLED.finditer(text))
        if len(matches) != 1:
            raise ValueError(
                "automatic Hyperion switching needs exactly one "
                "programs.ryoku.enable = true; declaration in flake.nix"
            )

        match = matches[0]
        return (
            text[:match.end()]
            + "\n"
            + match.group(1)
            + HYPERION_MARKER
            + text[match.end():]
        )

    if HYPERION_MARKER in text:
        pattern = re.compile(
            r"(?m)^[ \t]*" + re.escape(HYPERION_MARKER) + r"\n"
        )
        return pattern.sub("", text, count=1)
    if HYPERION_OPTION in text:
        raise ValueError("refusing to remove a manually managed Hyperion setting")
    return text


def set_niri_only(text: str, active: bool) -> str:
    if not active:
        if NIRI_MARKER in text:
            return re.sub(
                r"(?m)^[ \t]*" + re.escape(NIRI_MARKER) + r"\n",
                "",
                text,
                count=1,
            )
        if NIRI_OPTION in text:
            raise ValueError("refusing to remove a manually managed Niri-only setting")
        return text

    if NIRI_MARKER in text:
        return text
    if NIRI_OPTION in text:
        raise ValueError("Niri-only is already managed by another NixOS module")

    match = re.search(r"(?m)^([ \t]*)" + re.escape(HYPERION_MARKER) + r"$", text)
    if not match:
        raise ValueError("enable Hyperion before selecting Niri-only")
    return (
        text[:match.end()]
        + "\n" + match.group(1) + NIRI_MARKER
        + text[match.end():]
    )


def remove_legacy_ryotunes_input(text: str) -> str:
    return re.sub(
        r'(?m)^[ \t]*inputs\.ryotunesNix\.url\s*=\s*'
        r'"github:Ryoku-dev/RyotunesNix/[^"\n]+";[ \t]*\n',
        "",
        text,
    )


def main() -> int:
    if len(sys.argv) != 3:
        print(
            "usage: ryoku-nix-track-edit.py FLAKE SOURCE",
            file=sys.stderr,
        )
        return 2

    path = Path(sys.argv[1])

    try:
        source = sys.argv[2]
        updated = set_source(path.read_text(), source)
        if source == HYPERION_SOURCE:
            updated = set_hyperion_mode(updated, True)
            if os.environ.get("RYOKU_NIX_HYPERION_NIRI_ONLY") == "1":
                updated = set_niri_only(updated, True)
                updated = remove_legacy_ryotunes_input(updated)
        elif source in (
            "github:Ryoku-dev/Ryoku-on-NixOS/main",
            "github:Ryoku-dev/Ryoku-on-NixOS/unstable-dev",
        ):
            updated = set_niri_only(updated, False)
            updated = set_hyperion_mode(updated, False)

        path.write_text(updated)
    except (OSError, ValueError) as exc:
        print(f"ryoku-nix-track-edit: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
