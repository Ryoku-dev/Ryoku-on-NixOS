#!/usr/bin/env python3
"""Regression checks for the packaged Shima (iNiR) runtime.

- Every host patch Ryoku carries for the pinned iNiR source must be present in
  the built runtime. c84327f7 fixed a patch that existed for the shared runtime
  but was never applied by the Nix derivation.
- The injected Ryoku bridge must hand Ryoku's settings, wallpaper, theme and
  screenshot surfaces to Ryoku's own tools, and must route every surface the
  same way as the Arch runtime overlay. 30d5e4d0 fixed a bridge that opened
  Shima's own tools for those keys.
"""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

parser = argparse.ArgumentParser()
parser.add_argument("--runtime", required=True, type=Path, help="ryoku-shima package output")
parser.add_argument("--patch", action="append", default=[], type=lambda p: Path(p).resolve(),
                    help="host patch that must be applied in the runtime (repeatable)")
parser.add_argument("--patch-dir", action="append", default=[], type=Path,
                    help="directory whose *.patch files must all be applied (repeatable)")
parser.add_argument("--arch-overlay-patch", type=Path,
                    help="shima-overlay/runtime.patch used by the Arch runtime installer")
args = parser.parse_args()
args.patch += sorted(p.resolve() for d in args.patch_dir for p in d.glob("*.patch"))
RUNTIME = args.runtime / "share/quickshell/inir"


def patched_files(patch):
    names = set()
    for line in patch.read_text().splitlines():
        if line.startswith("+++ ") and not line.startswith("+++ /dev/null"):
            names.add(line[4:].split("\t")[0].removeprefix("b/"))
    return names


def has_context(patch):
    in_hunk = False
    for line in patch.read_text().splitlines():
        if line.startswith("@@"):
            in_hunk = True
        elif in_hunk and line.startswith(" "):
            return True
    return False


def reverse_applies(patch, tree):
    command = ["git", "apply", "-R", "--check"]
    if not has_context(patch):
        command.append("--unidiff-zero")
    result = subprocess.run(command + [str(patch)], cwd=tree, capture_output=True, text=True)
    if result.returncode == 0:
        subprocess.run(command[:3] + command[4:] + [str(patch)], cwd=tree, check=True,
                       capture_output=True, text=True)
    return result


def matching_brace(text, start):
    """Index of the brace closing text[start], skipping string literals and comments."""
    depth, i, quote = 0, start, None
    while i < len(text):
        c = text[i]
        if quote:
            if c == "\\":
                i += 1
            elif c == quote:
                quote = None
        elif c in "\"'`":
            quote = c
        elif text.startswith("//", i):
            i = text.index("\n", i)
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise ValueError("unbalanced braces")


FUNCTION = re.compile(r"function\s+(\w+)\s*\(([^)]*)\)\s*(?::\s*[\w.<>]+\s*)?\{")


def qml_function(text, name):
    for match in FUNCTION.finditer(text):
        if match.group(1) == name:
            end = matching_brace(text, match.end() - 1)
            params = [p.split(":")[0].strip() for p in match.group(2).split(",") if p.strip()]
            return {"params": params, "body": text[match.end():end]}
    raise AssertionError(f"QML function {name} not found")


def shell_ipc_block(text):
    for match in re.finditer(r"IpcHandler\s*\{", text):
        end = matching_brace(text, match.end() - 1)
        block = text[match.start():end + 1]
        if re.search(r'target:\s*"shell"', block):
            return block
    raise AssertionError('No IpcHandler with target "shell"')


def bridge_functions(text):
    block = shell_ipc_block(text)
    return {
        "openSurface": qml_function(block, "openSurface"),
        "closeSurface": qml_function(block, "closeSurface"),
        "ryokuSurfaceHandler": qml_function(text, "ryokuSurfaceHandler"),
    }


# Runs the extracted QML functions in a scope that records what they do.
HARNESS = r"""
const input = JSON.parse(require("fs").readFileSync(0, "utf8"));
const fns = input.functions;
const cases = input.cases;
const out = [];
for (const [family, verb, surface] of cases) {
  const trace = [];
  const recorder = (label) => new Proxy(function () {}, {
    get: (_, key) => typeof key === "symbol" ? undefined : recorder(label + "." + key),
    set: (_, key, value) => { trace.push(["set", label + "." + String(key), value]); return true; },
    apply: (_, __, argv) => { trace.push(["call", label, argv]); return undefined; },
  });
  const handlers = {};
  const handler = (name) => handlers[name] ??= {
    toggle: () => trace.push(["toggle", name]),
    close: () => trace.push(["close", name]),
    open: () => trace.push(["open", name]),
  };
  const fixed = {
    Quickshell: { execDetached: (argv) => trace.push(["exec", argv]) },
    Config: { options: { panelFamily: family }, ready: true },
    GlobalStates: recorder("GlobalStates"),
    root: {},
  };
  const scope = new Proxy(fixed, {
    has: (_, key) => typeof key === "string" && (key in fixed || /^ryoku[A-Z]/.test(key)),
    get: (_, key) => key in fixed ? fixed[key] : handler(key),
  });
  const compile = (name) => new Function("__scope",
    "with (__scope) { return function " + name + "(" + fns[name].params.join(", ") + ") {" + fns[name].body + "} }")(scope);
  fixed.root.ryokuSurfaceHandler = compile("ryokuSurfaceHandler");
  compile(verb)("DP-1", surface);
  out.push(trace);
}
process.stdout.write(JSON.stringify(out));
"""

FAMILIES = ["iris", "ii", "waffle"]
SURFACES = ["settings", "wallpaper", "theme", "screenshot", "launcher", "overview",
            "clipboard", "controls", "sidebar-left", "sidebar-right", "notifications",
            "session", "cheatsheet", "tools", "ask", "barToggle", "no-such-surface"]
RYOKU_TOOLS = {
    "settings": ["ryoku-shell", "hub", "open"],
    "wallpaper": ["ryogami", "wallpaper", "ui"],
    "theme": ["ryogami", "wallpaper", "ui"],
    "screenshot": ["ryoku-cmd-ryoshot"],
}


def run_bridge(functions, cases):
    result = subprocess.run(["node", "-e", HARNESS],
                            input=json.dumps({"functions": functions, "cases": cases}),
                            capture_output=True, text=True)
    if result.returncode != 0:
        raise AssertionError("bridge harness failed:\n" + result.stderr)
    return json.loads(result.stdout)


class ShimaRuntimePatchTests(unittest.TestCase):
    def test_every_host_patch_is_applied(self):
        self.assertTrue(args.patch, "no host patches given")
        with tempfile.TemporaryDirectory() as tmp:
            tree = Path(tmp)
            for patch in args.patch:
                for name in patched_files(patch):
                    source = RUNTIME / name
                    if source.is_file():
                        target = tree / name
                        target.parent.mkdir(parents=True, exist_ok=True)
                        shutil.copyfile(source, target)
            # Undo the patches newest first. A patch that cannot be reversed from
            # the runtime was never applied (or was overwritten afterwards).
            remaining, errors = list(args.patch), {}
            while remaining:
                for patch in reversed(remaining):
                    result = reverse_applies(patch, tree)
                    if result.returncode == 0:
                        remaining.remove(patch)
                        break
                    errors[patch.name] = result.stderr.strip()
                else:
                    self.fail("host patch not applied in the Shima runtime: "
                              + ", ".join(p.name for p in remaining) + "\n"
                              + "\n".join(errors.get(p.name, "") for p in remaining))


class ShimaBridgeRoutingTests(unittest.TestCase):
    def setUp(self):
        self.bridge = bridge_functions((RUNTIME / "shell.qml").read_text())

    def test_ryoku_surfaces_open_ryoku_tools(self):
        cases = [[f, "openSurface", s] for f in FAMILIES for s in RYOKU_TOOLS]
        for (family, _, surface), trace in zip(cases, run_bridge(self.bridge, cases)):
            with self.subTest(family=family, surface=surface):
                self.assertEqual(trace, [["exec", RYOKU_TOOLS[surface]]])

    def test_shima_surfaces_stay_inside_shima(self):
        shima = [s for s in SURFACES if s not in RYOKU_TOOLS and s != "no-such-surface"]
        cases = [[f, "openSurface", s] for f in FAMILIES for s in shima]
        for (family, _, surface), trace in zip(cases, run_bridge(self.bridge, cases)):
            with self.subTest(family=family, surface=surface):
                self.assertEqual(len(trace), 1, trace)
                self.assertEqual(trace[0][0], "toggle", trace)
        unknown = run_bridge(self.bridge, [["iris", "openSurface", "no-such-surface"]])
        self.assertEqual(unknown, [[]])

    @unittest.skipUnless(args.arch_overlay_patch, "no Arch runtime overlay given")
    def test_routing_matches_arch_runtime(self):
        added = "\n".join(line[1:] for line in args.arch_overlay_patch.read_text().splitlines()
                          if line.startswith("+") and not line.startswith("+++"))
        arch = bridge_functions(added)
        cases = [[f, v, s] for f in FAMILIES for v in ("openSurface", "closeSurface") for s in SURFACES]
        nix_trace = run_bridge(self.bridge, cases)
        arch_trace = run_bridge(arch, cases)
        for case, ours, theirs in zip(cases, nix_trace, arch_trace):
            with self.subTest(case=case):
                self.assertEqual(ours, theirs)


if __name__ == "__main__":
    unittest.main(argv=["test-subshell-runtime"], verbosity=2)
