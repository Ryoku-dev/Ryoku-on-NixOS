#!/usr/bin/env python3

from pathlib import Path
import re
import sys


IDENT = r"[A-Za-z_][A-Za-z0-9_-]*"
NIXOS_SYSTEM = rf"(?:(?:{IDENT})\.)*nixosSystem"


class EditError(RuntimeError):
    pass


# ─────────────────────────────────────────────────────────────
# Nix lexical helpers
# ─────────────────────────────────────────────────────────────

def nix_string(value: str) -> str:
    if "\x00" in value or "\n" in value or "\r" in value:
        raise EditError("ryoku-install: source reference must be a single line")

    escaped = (
        value
        .replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("${", "\\${")
    )

    return f'"{escaped}"'


def skip_line_comment(text: str, i: int) -> int:
    end = text.find("\n", i)
    return len(text) if end < 0 else end + 1


def skip_block_comment(text: str, i: int) -> int:
    end = text.find("*/", i + 2)

    if end < 0:
        raise EditError(
            "ryoku-install: unterminated block comment in flake.nix"
        )

    return end + 2


def skip_double_string(text: str, i: int) -> int:
    i += 1

    while i < len(text):
        if text[i] == "\\":
            i += 2
            continue

        if text.startswith("${", i):
            close = find_matching(text, i + 1, "{", "}")
            i = close + 1
            continue

        if text[i] == '"':
            return i + 1

        i += 1

    raise EditError(
        "ryoku-install: unterminated string in flake.nix"
    )


def skip_indented_string(text: str, i: int) -> int:
    i += 2

    while i < len(text):
        if text.startswith("'''", i):
            i += 3
            continue

        if text.startswith("''${", i):
            i += 4
            continue

        if text.startswith("''\\", i):
            i += 3
            continue

        if text.startswith("${", i):
            close = find_matching(text, i + 1, "{", "}")
            i = close + 1
            continue

        if text.startswith("''", i):
            return i + 2

        i += 1

    raise EditError(
        "ryoku-install: unterminated indented string in flake.nix"
    )


def skip_opaque(text: str, i: int):
    if text.startswith("#", i):
        return skip_line_comment(text, i)

    if text.startswith("/*", i):
        return skip_block_comment(text, i)

    if text.startswith("''", i):
        return skip_indented_string(text, i)

    if text.startswith('"', i):
        return skip_double_string(text, i)

    return None


def find_matching(
    text: str,
    open_pos: int,
    opening: str,
    closing: str,
) -> int:
    if open_pos >= len(text) or text[open_pos] != opening:
        raise EditError(
            "ryoku-install: internal delimiter error"
        )

    depth = 0
    i = open_pos

    while i < len(text):
        skipped = skip_opaque(text, i)

        if skipped is not None:
            i = skipped
            continue

        ch = text[i]

        if ch == opening:
            depth += 1

        elif ch == closing:
            depth -= 1

            if depth == 0:
                return i

        i += 1

    raise EditError(
        f"ryoku-install: could not locate matching `{closing}` in flake.nix"
    )


# ─────────────────────────────────────────────────────────────
# Ryoku input
# ─────────────────────────────────────────────────────────────

def add_input(text: str, source: str) -> str:
    outputs_match = re.search(
        r"(?m)^[ \t]*outputs[ \t]*=",
        text,
    )

    if not outputs_match:
        raise EditError(
            "ryoku-install: could not locate `outputs`"
        )

    outputs_pos = outputs_match.start()
    input_region = text[:outputs_pos]

    if (
        re.search(
            r"(?m)^[ \t]*ryoku[ \t]*=",
            input_region,
        )
        or re.search(
            r"(?m)^[ \t]*inputs\.ryoku(?:\.|[ \t]*=)",
            input_region,
        )
    ):
        return text

    quoted_source = nix_string(source)

    block = re.search(
        r"(?m)^([ \t]*)inputs[ \t]*=[ \t]*\{",
        input_region,
    )

    if block:
        brace = block.end() - 1
        close = find_matching(text, brace, "{", "}")

        if close > outputs_pos:
            raise EditError(
                "ryoku-install: malformed `inputs` attribute set"
            )

        base_indent = block.group(1)
        indent = base_indent + "  "

        ryoku_block = (
            f"{indent}ryoku = {{\n"
            f"{indent}  url = {quoted_source};\n"
            f"{indent}}};"
        )

        inner = text[brace + 1:close]

        # Cleanly expand an inline inputs set.
        if "\n" not in inner:
            existing = inner.strip()
            pieces = [ryoku_block]

            if existing:
                pieces.append(f"{indent}{existing}")

            replacement = (
                "\n"
                + "\n".join(pieces)
                + "\n"
                + base_indent
            )

            return (
                text[:brace + 1]
                + replacement
                + text[close:]
            )

        inner_start = brace + 1

        if text.startswith("\r\n", inner_start):
            inner_start += 2
        elif text.startswith("\n", inner_start):
            inner_start += 1

        replacement = (
            "\n"
            + ryoku_block
            + "\n"
            + text[inner_start:close]
        )

        return (
            text[:brace + 1]
            + replacement
            + text[close:]
        )

    # Support flakes using:
    #
    #   inputs.nixpkgs.url = "...";
    #
    dotted = re.search(
        r"(?m)^([ \t]*)inputs\.",
        input_region,
    )

    outputs_line = text.rfind(
        "\n",
        0,
        outputs_pos,
    ) + 1

    if dotted:
        indent = dotted.group(1)

        addition = (
            f"{indent}inputs.ryoku.url = "
            f"{quoted_source};\n"
        )

        return (
            text[:outputs_line]
            + addition
            + text[outputs_line:]
        )

    # An unusual computed inputs expression cannot be safely rewritten.
    if re.search(
        r"(?m)^[ \t]*inputs[ \t]*=",
        input_region,
    ):
        raise EditError(
            "ryoku-install: unsupported `inputs` expression; "
            "use an attribute set or dotted `inputs.*` declarations"
        )

    # A flake with no inputs at all is still safe to extend.
    output_indent_match = re.match(
        r"[ \t]*",
        text[outputs_line:outputs_pos],
    )

    base_indent = (
        output_indent_match.group(0)
        if output_indent_match
        else ""
    )

    addition = (
        f"{base_indent}inputs = {{\n"
        f"{base_indent}  ryoku = {{\n"
        f"{base_indent}    url = {quoted_source};\n"
        f"{base_indent}  }};\n"
        f"{base_indent}}};\n\n"
    )

    return (
        text[:outputs_line]
        + addition
        + text[outputs_line:]
    )


# ─────────────────────────────────────────────────────────────
# outputs arguments
# ─────────────────────────────────────────────────────────────

def add_outputs_argument(text: str) -> str:
    outputs = re.search(
        rf"(?m)^([ \t]*)outputs[ \t]*=[ \t]*"
        rf"(?:(?P<pre>{IDENT})[ \t]*@[ \t]*)?"
        rf"\{{(?P<body>.*?)\}}"
        rf"(?:[ \t]*@[ \t]*(?P<post>{IDENT}))?"
        rf"[ \t]*:",
        text,
        re.S,
    )

    if not outputs:
        raise EditError(
            "ryoku-install: unsupported flake layout; "
            "could not parse outputs arguments"
        )

    body = outputs.group("body")

    if re.search(
        r"(?<![A-Za-z0-9_-])ryoku(?![A-Za-z0-9_-])",
        body,
    ):
        return text

    leading_len = len(body) - len(body.lstrip())

    updated = (
        body[:leading_len]
        + "ryoku, "
        + body[leading_len:]
    )

    return (
        text[:outputs.start("body")]
        + updated
        + text[outputs.end("body"):]
    )


# ─────────────────────────────────────────────────────────────
# Host detection
# ─────────────────────────────────────────────────────────────

def locate_system(text: str, host: str):
    escaped = re.escape(host)

    host_patterns = [
        (
            rf'(?m)^[ \t]*(?:"{escaped}"|{escaped})[ \t]*='
            rf"[ \t]*{NIXOS_SYSTEM}[ \t]*\{{"
        ),
        (
            rf"(?m)^[ \t]*nixosConfigurations\."
            rf'(?:"{escaped}"|{escaped})[ \t]*='
            rf"[ \t]*{NIXOS_SYSTEM}[ \t]*\{{"
        ),
    ]

    match = None

    for pattern in host_patterns:
        match = re.search(pattern, text)

        if match:
            break

    if match is None:
        systems = list(
            re.finditer(
                rf"{NIXOS_SYSTEM}[ \t]*\{{",
                text,
            )
        )

        # A single nixosSystem is unambiguous even if the surrounding
        # attribute layout is unconventional.
        if len(systems) == 1:
            match = systems[0]
        else:
            raise EditError(
                "ryoku-install: could not safely locate "
                f"nixosSystem for host `{host}`; "
                "the host may be imported from another file"
            )

    open_brace = text.find(
        "{",
        match.start(),
        match.end(),
    )

    if open_brace < 0:
        raise EditError(
            "ryoku-install: could not locate nixosSystem body"
        )

    close_brace = find_matching(
        text,
        open_brace,
        "{",
        "}",
    )

    return open_brace, close_brace


# ─────────────────────────────────────────────────────────────
# modules list
# ─────────────────────────────────────────────────────────────

def find_top_level_modules(
    text: str,
    open_brace: int,
    close_brace: int,
):
    i = open_brace + 1

    brace_depth = 0
    bracket_depth = 0
    paren_depth = 0

    module_re = re.compile(
        r"modules[ \t]*=[ \t]*\["
    )

    while i < close_brace:
        skipped = skip_opaque(text, i)

        if skipped is not None:
            i = skipped
            continue

        ch = text[i]

        if ch == "{":
            brace_depth += 1
            i += 1
            continue

        if ch == "}":
            brace_depth -= 1
            i += 1
            continue

        if ch == "[":
            bracket_depth += 1
            i += 1
            continue

        if ch == "]":
            bracket_depth -= 1
            i += 1
            continue

        if ch == "(":
            paren_depth += 1
            i += 1
            continue

        if ch == ")":
            paren_depth -= 1
            i += 1
            continue

        if (
            brace_depth == 0
            and bracket_depth == 0
            and paren_depth == 0
        ):
            match = module_re.match(text, i)

            if match:
                return match.end() - 1

        i += 1

    raise EditError(
        "ryoku-install: target host has no directly editable "
        "`modules = [ ... ]` list; add "
        "`ryoku.nixosModules.default` and `./ryoku.nix` "
        "to that host manually"
    )


def line_indent(text: str, pos: int) -> str:
    start = text.rfind("\n", 0, pos) + 1

    match = re.match(
        r"[ \t]*",
        text[start:pos],
    )

    return match.group(0) if match else ""


def add_modules(text: str, host: str) -> str:
    system_open, system_close = locate_system(
        text,
        host,
    )

    modules_open = find_top_level_modules(
        text,
        system_open,
        system_close,
    )

    modules_close = find_matching(
        text,
        modules_open,
        "[",
        "]",
    )

    segment = text[
        modules_open + 1:modules_close
    ]

    base_indent = line_indent(
        text,
        modules_open,
    )

    indent = base_indent + "  "

    entries = []

    if "ryoku.nixosModules.default" not in segment:
        entries.append(
            f"{indent}ryoku.nixosModules.default"
        )

    if "./ryoku.nix" not in segment:
        entries.append(
            f"{indent}./ryoku.nix"
        )

    if not entries:
        return text

    # Turn an inline list into a clean multiline list.
    if "\n" not in segment:
        existing = segment.strip()
        pieces = list(entries)

        if existing:
            pieces.append(
                f"{indent}{existing}"
            )

        replacement = (
            "\n"
            + "\n".join(pieces)
            + "\n"
            + base_indent
        )

        return (
            text[:modules_open + 1]
            + replacement
            + text[modules_close:]
        )

    content_start = modules_open + 1

    if text.startswith("\r\n", content_start):
        content_start += 2
    elif text.startswith("\n", content_start):
        content_start += 1

    replacement = (
        "\n"
        + "\n".join(entries)
        + "\n"
        + text[content_start:modules_close]
    )

    return (
        text[:modules_open + 1]
        + replacement
        + text[modules_close:]
    )


# ─────────────────────────────────────────────────────────────
# Public editor
# ─────────────────────────────────────────────────────────────

def edit_flake(
    text: str,
    host: str,
    source: str,
) -> str:
    text = add_input(text, source)
    text = add_outputs_argument(text)
    text = add_modules(text, host)

    return text


def main() -> int:
    input_only = len(sys.argv) == 4 and sys.argv[1] == "--input-only"
    if input_only:
        path = Path(sys.argv[2])
        source = sys.argv[3]
        host = ""
    elif len(sys.argv) == 4:
        path = Path(sys.argv[1])
        host = sys.argv[2]
        source = sys.argv[3]
    else:
        print(
            "usage: ryoku-install-edit.py [--input-only] FLAKE [HOST] SOURCE",
            file=sys.stderr,
        )
        return 2

    try:
        text = path.read_text()

        path.write_text(add_input(text, source) if input_only else edit_flake(text, host, source))

    except EditError as exc:
        print(
            str(exc),
            file=sys.stderr,
        )
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
