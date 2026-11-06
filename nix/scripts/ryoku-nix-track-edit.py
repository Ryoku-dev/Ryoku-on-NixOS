#!/usr/bin/env python3

from pathlib import Path
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


def main() -> int:
    if len(sys.argv) != 3:
        print(
            "usage: ryoku-nix-track-edit.py FLAKE SOURCE",
            file=sys.stderr,
        )
        return 2

    path = Path(sys.argv[1])

    try:
        path.write_text(
            set_source(
                path.read_text(),
                sys.argv[2],
            )
        )
    except (OSError, ValueError) as exc:
        print(f"ryoku-nix-track-edit: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
