#!/usr/bin/env python3

import os
import re
from pathlib import Path


def require_env(name: str) -> Path:
    value = os.environ.get(name)
    if not value:
        raise SystemExit(f"{name} is required")
    path = Path(value)
    if not path.exists():
        raise SystemExit(f"{name} does not exist: {path}")
    return path


qsbar_variant = require_env("RYOKU_QSBAR_VARIANT")
bar_products = require_env("RYOKU_BAR_PRODUCTS")
python_root = require_env("RYOKU_PYTHON_BARSTYLE")

variant = qsbar_variant.read_text()
if 'import "." as QsBar' not in variant:
    raise SystemExit("QS Bar VariantRoot must alias its local module")
if "QsBar.Theme {" not in variant:
    raise SystemExit("QS Bar VariantRoot must instantiate the local Theme explicitly")
if re.search(r"(?m)^\s*Theme\s*\{", variant):
    raise SystemExit("QS Bar VariantRoot has an ambiguous unqualified Theme instantiation")

products = bar_products.read_text()
match = re.search(
    r"function\s+isFrameFamily\s*\([^)]*\)\s*\{(?P<body>.*?)\n\s*\}",
    products,
    re.S,
)
if not match:
    raise SystemExit("BarProducts.isFrameFamily is missing")
body = match.group("body")
for style in ("iris", "python", "ricelin"):
    if f'"{style}"' not in body:
        raise SystemExit(f"{style} must use the primary whole-desktop bar host")

serialized = []
for path in python_root.rglob("*"):
    if not path.is_file():
        continue
    try:
        text = path.read_text()
    except UnicodeDecodeError:
        continue

    # A sync regression once stored complete QML/qmldir sources as one line
    # containing literal "\n" escapes. Those files look present in Git but QML
    # cannot parse them. Flag that structural shape independent of filenames.
    real_newlines = text.count("\n")
    escaped_newlines = text.count("\\n")
    if real_newlines <= 2 and escaped_newlines >= 2:
        serialized.append(
            f"{path.relative_to(python_root)} "
            f"(real_newlines={real_newlines}, escaped_newlines={escaped_newlines})"
        )

if serialized:
    raise SystemExit(
        "Python bar style contains serialized source files:\n  "
        + "\n  ".join(serialized)
    )

# Guard against serialized (one-line) copies of the largest sources.
for relative, minimum_lines in (
    ("bar/faces/tray/TrayFace.qml", 200),
    ("guide/GuidePopup.qml", 1000),
    ("bar/BarModuleRegistry.qml", 200),
    ("widgets/faces/qmldir", 10),
):
    path = python_root / relative
    lines = path.read_text().splitlines()
    if len(lines) < minimum_lines:
        raise SystemExit(
            f"{relative} is unexpectedly short: {len(lines)} < {minimum_lines}"
        )

print("barstyle-source-integrity: QS Bar, Python and Ricelin host sources are sane")
