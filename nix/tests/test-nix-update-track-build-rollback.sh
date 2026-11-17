#!/usr/bin/env bash
set -euo pipefail

helper=${RYOKU_NIX_UPDATE_TEST_HELPER:?}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/flake" "$work/bin"
flake="$work/flake"
bin="$work/bin"

printf '{ outputs = _: {}; }\n' > "$flake/flake.nix"
printf '{ "original": true }\n' > "$flake/flake.lock"
printf '{ ... }: { programs.ryoku.enable = true; }\n' > "$flake/ryoku.nix"
cp "$flake/flake.nix" "$work/flake.before"
cp "$flake/flake.lock" "$work/lock.before"
cp "$flake/ryoku.nix" "$work/module.before"

cat > "$work/editor.py" <<'PYEDIT'
import sys
for path in [sys.argv[1], *sys.argv[3:]]:
    with open(path, 'a') as f:
        f.write('# switched\n')
PYEDIT

cat > "$bin/sudo" <<'SH'
#!/usr/bin/env bash
exec "$@"
SH
cat > "$bin/nix" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = eval ]; then
    printf '["testhost"]\n'
    exit 0
fi
if [ "${1:-} ${2:-}" = 'flake update' ]; then
    printf '{ "updated": true }\n' > "$RYOKU_NIX_FLAKE/flake.lock"
    exit 0
fi
if [ "${1:-}" = build ]; then
    : > "$RYOKU_TEST_BUILD_MARKER"
    exit 42
fi
exit 1
SH
cat > "$bin/nixos-rebuild" <<'SH'
#!/usr/bin/env bash
exit 99
SH
sed -i "1c#!$(command -v bash)" "$bin/sudo" "$bin/nix" "$bin/nixos-rebuild"
chmod +x "$bin"/*

if PATH="$bin:$PATH" \
   RYOKU_NIX_FLAKE="$flake" \
   RYOKU_NIX_HOST=testhost \
   RYOKU_TEST_BUILD_MARKER="$work/build.reached" \
   RYOKU_NIX_FLAKE_EDITOR="$work/editor.py" \
   RYOKU_NIX_SUDO="$bin/sudo" \
   XDG_RUNTIME_DIR="$work" \
   bash "$helper" track hyperion > "$work/out" 2>&1; then
    printf 'expected simulated channel build failure\n' >&2
    exit 1
fi

test -f "$work/build.reached" || { cat "$work/out" >&2; exit 1; }
cmp -s "$work/flake.before" "$flake/flake.nix"
cmp -s "$work/lock.before" "$flake/flake.lock"
cmp -s "$work/module.before" "$flake/ryoku.nix"
[ "$(grep -Fc 'Restoring the previous Ryoku flake files.' "$work/out")" = 1 ] || {
    cat "$work/out" >&2
    exit 1
}
if grep -Eq 'cannot stat|No such file or directory' "$work/out"; then
    cat "$work/out" >&2
    exit 1
fi
grep -Fq 'channel switch build failed' "$work/out"
printf 'nix-update-track-build-rollback: PASS\n'
