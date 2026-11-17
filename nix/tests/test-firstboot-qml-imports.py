#!/usr/bin/env python3
"""Every third-party QML module the shell imports resolves under ryoku-shell.service.

The unit replaces QML2_IMPORT_PATH with an explicit list, so a module that is
installed system-wide but missing from that list fails at runtime: a hard
import breaks its surface, a Loader-guarded one silently drops the feature.

Ryoku's own modules (Ryoku.*), Quickshell's built-in modules and the shell's
local directory namespaces are not checked here; only imports of other
packages are.

Usage: test-firstboot-qml-imports.py QML2_IMPORT_PATH TREE...
"""
import os
import re
import sys

IMPORT = re.compile(r"^\s*import\s+([A-Za-z][\w.]*)", re.M)

# The experimental Shima runtime ships its own package and import path.
SEPARATE = {"inir", "shima-overlay"}


def imports(trees):
    found = {}
    local = {"Ryoku", "Quickshell", "qs"}
    for tree in trees:
        local.update(e for e in os.listdir(tree) if os.path.isdir(os.path.join(tree, e)))
    for tree in trees:
        for dirpath, dirs, files in os.walk(tree):
            if dirpath == tree:
                dirs[:] = [d for d in dirs if d not in SEPARATE]
            for name in files:
                if not name.endswith(".qml"):
                    continue
                path = os.path.join(dirpath, name)
                with open(path, errors="replace") as f:
                    for module in IMPORT.findall(f.read()):
                        if module.split(".")[0] not in local:
                            found.setdefault(module, os.path.relpath(path, tree))
    return found


def main():
    search = [d for d in sys.argv[1].split(":") if d]
    trees = sys.argv[2:]
    found = imports(trees)
    if not found:
        sys.exit("no QML imports found; wrong tree?")
    missing = []
    for module, where in sorted(found.items()):
        rel = module.replace(".", "/")
        if not any(os.path.isfile(os.path.join(d, rel, "qmldir")) for d in search):
            missing.append(f"{module} (imported by {where})")
    for line in missing:
        print(f"MISSING {line}", file=sys.stderr)
    if missing:
        sys.exit(f"{len(missing)} QML module(s) are not on ryoku-shell.service's import path")
    print(f"test-firstboot-qml-imports: PASS ({len(found)} modules)")


if __name__ == "__main__":
    main()
