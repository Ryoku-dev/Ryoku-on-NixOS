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
    exit 0
fi
exit 1
SH
printf '#!%s\n' "$bash_bin" >"$bin/nixos-rebuild"
cat >>"$bin/nixos-rebuild" <<'SH'
# Simulate an activation that touched the live system and then failed.
exit 42
SH
printf '#!%s\n' "$bash_bin" >"$bin/systemctl"
cat >>"$bin/systemctl" <<'SH'
case " $* " in
  *' --failed '*)
    printf '● home-manager-test.service loaded failed failed Home Manager environment for test\n'
    exit 0
    ;;
  *' --user is-active --quiet ryoku-shell.service '*) exit 0 ;;
  *' --user daemon-reload '*) exit 0 ;;
  *' --user restart ryoku-materialize.service '*)
    : >"$MATERIALIZE_MARKER"
    exit 0
    ;;
  *' --user restart ryoku-shell.service '*)
    : >"$SHELL_MARKER"
    exit 0
    ;;
  *' --user try-restart ryoku-shell.service '*) exit 0 ;;
esac
exit 1
SH
printf '#!%s\n' "$bash_bin" >"$bin/journalctl"
cat >>"$bin/journalctl" <<'SH'
printf '%s\n' "Existing file '/home/test/.config/ryoku/desktop.json.backup' would be clobbered by backing up '/home/test/.config/ryoku/desktop.json'"
SH
chmod +x "$bin"/*

if PATH="$bin:$PATH" \
   ROLLBACK_MARKER="$marker" \
   MATERIALIZE_MARKER="$materialize_marker" \
   SHELL_MARKER="$shell_marker" \
   RYOKU_NIX_FLAKE="$flake" \
   RYOKU_NIX_HOST=testhost \
   RYOKU_NIX_SUDO="$bin/sudo" \
   RYOKU_NIX_VERSION=1 \
   XDG_RUNTIME_DIR="$work" \
   bash "$helper" update >"$work/out" 2>&1; then
    printf 'expected simulated activation failure\n' >&2
    exit 1
fi

[ -f "$marker" ] || {
    printf 'previous generation switcher was not invoked\n' >&2
    cat "$work/out" >&2
    exit 1
}
[ "$(cat "$marker")" = switch ] || {
    printf 'rollback switcher got unexpected arguments: %s\n' "$(cat "$marker")" >&2
    exit 1
}
cmp -s "$work/lock.before" "$flake/flake.lock" || {
    printf 'flake.lock was not restored after failed activation\n' >&2
    exit 1
}
grep -Fq 'NixOS activation failed with exit status 42.' "$work/out"
grep -Fq 'home-manager-test.service' "$work/out"
grep -Fq 'Home Manager refused to overwrite an existing backup.' "$work/out"
grep -Fq 'Restoring the previous NixOS runtime generation.' "$work/out"
grep -Fq 'Restoring the previous Ryoku desktop runtime.' "$work/out"
[ -f "$materialize_marker" ] || {
    printf 'previous Ryoku runtime was not re-materialized after rollback\n' >&2
    cat "$work/out" >&2
    exit 1
}
[ -f "$shell_marker" ] || {
    printf 'Ryoku shell was not restarted after rollback\n' >&2
    cat "$work/out" >&2
    exit 1
}

printf 'nix-update-activation-rollback: PASS\n'
