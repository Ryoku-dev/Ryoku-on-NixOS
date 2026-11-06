#!/usr/bin/env bash
set -euo pipefail

helper=${RYOKU_NIX_UPDATE_TEST_HELPER:?}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

remote="$work/remote.git"
source="$work/source"
flake="$work/flake"
bin="$work/bin"
old_system="$work/old-system"
marker="$work/rollback.marker"
switch_marker="$work/switch.marker"
materialize_marker="$work/materialize.marker"
shell_marker="$work/shell.marker"
mkdir -p "$flake" "$bin" "$old_system/bin"
bash_bin=$(command -v bash)

# A clean local path input exercises the real update transaction without any
# public network dependency.
git init --bare -q "$remote"
git clone -q "$remote" "$source"
git -C "$source" config user.name test
git -C "$source" config user.email test@example.invalid
printf '1\n' >"$source/VERSION"
git -C "$source" add VERSION
git -C "$source" commit -qm initial
git -C "$source" branch -M main
git -C "$source" push -q -u origin main

cat >"$flake/flake.lock" <<JSON
{"nodes":{"root":{"inputs":{"ryoku":"ryoku"}},"ryoku":{"original":{"type":"path","path":"$source"},"locked":{"type":"path","path":"$source"}}},"root":"root","version":7}
JSON
cp "$flake/flake.lock" "$work/lock.before"

printf '#!%s\n' "$bash_bin" >"$old_system/bin/switch-to-configuration"
cat >>"$old_system/bin/switch-to-configuration" <<'SH'
printf '%s\n' "$*" >"$ROLLBACK_MARKER"
SH
chmod +x "$old_system/bin/switch-to-configuration"

real_readlink=$(command -v readlink)
printf '#!%s\n' "$bash_bin" >"$bin/readlink"
cat >>"$bin/readlink" <<SH
if [ "\${1:-}" = -f ] && [ "\${2:-}" = /run/current-system ]; then
    printf '%s\\n' '$old_system'
    exit 0
fi
exec '$real_readlink' "\$@"
SH
printf '#!%s\n' "$bash_bin" >"$bin/sudo"
cat >>"$bin/sudo" <<'SH'
exec "$@"
SH
printf '#!%s\n' "$bash_bin" >"$bin/nix"
cat >>"$bin/nix" <<'SH'
if [ "${1:-}" = eval ]; then
    printf '["testhost"]\n'
    exit 0
fi
if [ "${1:-} ${2:-}" = 'flake update' ]; then
    exit 0
fi
if [ "${1:-}" = build ]; then
    # The user hits Ctrl-C / the session sends SIGTERM mid-build.
    kill -TERM "$PPID"
    exit 0
fi
exit 1
SH
printf '#!%s\n' "$bash_bin" >"$bin/nixos-rebuild"
cat >>"$bin/nixos-rebuild" <<'SH'
: >"$SWITCH_MARKER"
exit 0
SH
printf '#!%s\n' "$bash_bin" >"$bin/systemctl"
cat >>"$bin/systemctl" <<'SH'
exit 0
SH
chmod +x "$bin"/*

set +e
PATH="$bin:$PATH" \
   ROLLBACK_MARKER="$marker" \
   SWITCH_MARKER="$switch_marker" \
   RYOKU_NIX_FLAKE="$flake" \
   RYOKU_NIX_HOST=testhost \
   RYOKU_NIX_SUDO="$bin/sudo" \
   RYOKU_NIX_VERSION=1 \
   XDG_RUNTIME_DIR="$work" \
   bash "$helper" update >"$work/out" 2>&1
status=$?
set -e

[ "$status" -ne 0 ] || {
    printf 'an interrupted update must not exit successfully\n' >&2
    cat "$work/out" >&2
    exit 1
}
[ ! -e "$switch_marker" ] || {
    printf 'update kept going and switched generations after being interrupted\n' >&2
    cat "$work/out" >&2
    exit 1
}
cmp -s "$work/lock.before" "$flake/flake.lock" || {
    printf 'flake.lock was not restored after the interrupt\n' >&2
    exit 1
}
grep -Fq 'Restoring the previous Ryoku flake lock.' "$work/out"

# --- channel switch (track) -------------------------------------------------
# It edits flake.nix and the lock before building; a cancelled switch must put
# both back instead of leaving the flake pointing at a channel that was never
# built or activated.
rm -f "$switch_marker"
printf '{ outputs = _: {}; }\n' >"$flake/flake.nix"
cp "$flake/flake.nix" "$work/flake.before"
cat >"$work/editor.py" <<'PY'
import sys
with open(sys.argv[1], "a") as f:
    f.write("# tracking " + sys.argv[2] + "\n")
PY
real_python=$(command -v python3)
set +e
PATH="$bin:$PATH" \
   ROLLBACK_MARKER="$marker" \
   SWITCH_MARKER="$switch_marker" \
   RYOKU_NIX_FLAKE="$flake" \
   RYOKU_NIX_FLAKE_EDITOR="$work/editor.py" \
   RYOKU_NIX_HOST=testhost \
   RYOKU_NIX_SUDO="$bin/sudo" \
   RYOKU_NIX_VERSION=1 \
   XDG_RUNTIME_DIR="$work" \
   bash "$helper" track unstable >"$work/track.out" 2>&1
status=$?
set -e
[ "$status" -ne 0 ] || { printf 'an interrupted channel switch must not succeed\n' >&2; cat "$work/track.out" >&2; exit 1; }
[ ! -e "$switch_marker" ] || { printf 'channel switch activated after being interrupted\n' >&2; exit 1; }
cmp -s "$work/flake.before" "$flake/flake.nix" || {
    printf 'flake.nix was left pointing at the new channel after the interrupt\n' >&2
    cat "$flake/flake.nix" >&2
    exit 1
}
cmp -s "$work/lock.before" "$flake/flake.lock" || { printf 'flake.lock not restored after interrupted channel switch\n' >&2; exit 1; }
grep -Fq 'Restoring the previous Ryoku flake files.' "$work/track.out"

printf 'nix-update-interrupt: PASS\n'
