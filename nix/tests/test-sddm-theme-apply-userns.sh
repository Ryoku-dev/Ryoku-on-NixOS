#!/usr/bin/env bash
# Manual, unprivileged end-to-end test of ryoku-sddm-theme-apply with the REAL
# setpriv, run inside a throw-away user namespace (needs /etc/subuid and
# newuidmap). Nothing outside a temporary directory is touched. Not part of CI:
# hosted runners restrict user namespaces.
#
# Usage: test-sddm-theme-apply-userns.sh <coreutils/bin> <findutils/bin> <setpriv> <flock>
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
if [ "${1:-}" != "--inside" ]; then
  [ $# -eq 4 ] || { echo "usage: $0 <coreutils-bin> <findutils-bin> <setpriv> <flock>" >&2; exit 2; }
  command -v newuidmap >/dev/null && unshare -U --map-root-user --map-auto true 2>/dev/null ||
    { echo "test-sddm-theme-apply-userns: SKIP (no usable user namespaces)"; exit 0; }
  exec unshare -U --map-root-user --map-auto "$BASH" "$0" --inside "$@"
fi
shift
cb=$1 fb=$2 setpriv=$3 flock=$4

# Inside the namespace: host user -> "root", ns uid 1000 -> unrelated subuid.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
chmod 0755 "$tmp"
fail() { printf 'test-sddm-theme-apply-userns: FAIL: %s\n' "$*" >&2; exit 1; }

# 1. The privilege drop itself, with groups and capabilities.
status=$("$setpriv" --reuid 1000 --regid 1000 --groups 5,6 --bounding-set -all \
  --inh-caps -all --reset-env --no-new-privs -- "$cb/cat" /proc/self/status)
grep -qP '^Uid:\t1000\t1000\t1000\t1000$' <<<"$status" || fail "uid not dropped"
grep -qP '^Gid:\t1000\t1000\t1000\t1000$' <<<"$status" || fail "gid not dropped"
grep -qP '^Groups:\t5 6 ?$' <<<"$status" || fail "supplementary groups not set"
for c in CapInh CapPrm CapEff CapBnd CapAmb; do
  grep -qP "^$c:\t0+\$" <<<"$status" || fail "$c not empty"
done
grep -q '^NoNewPrivs:.1$' <<<"$status" || fail "no_new_privs not set"

# 2. The dropped user cannot read a root-only file.
secret=$tmp/secret; printf 'TOP-SECRET\n' > "$secret"; chmod 0600 "$secret"
if "$setpriv" --reuid 1000 --regid 1000 --clear-groups -- "$cb/cat" "$secret" 2>/dev/null; then
  fail "dropped user read a root-only file"
fi

# 3. Full helper run with the real setpriv.
mkdir -p "$tmp/bin" "$tmp/state" "$tmp/home/.local/share/qylock/themes/evil/sub"
cat > "$tmp/bin/getent" <<STUB
#!$BASH
printf 'tester:x:1000:1000::$tmp/home:/bin/sh\n'
STUB
chmod +x "$tmp/bin/getent"
sed -e '1d' -e "s|@coreutils@|$cb|" -e "s|@findutils@|$fb|" -e "s|@getent@|$tmp/bin/getent|" \
  -e "s|@flock@|$flock|" -e "s|@setpriv@|$setpriv|" -e "s|@stateDir@|$tmp/state/sddm-theme|" \
  "$repo/nix/scripts/ryoku-sddm-theme-apply" > "$tmp/apply"
t=$tmp/home/.local/share/qylock/themes/evil
echo qml > "$t/Main.qml"; echo img > "$t/sub/a.png"
ln -s "$secret" "$t/leak"; ln -s "$tmp" "$t/dirleak"
chmod -R a+rX "$tmp/home"
# The skin is owned by ns-root; the ns-1000 reader still sees it via a+rX.
PKEXEC_UID=1000 bash "$tmp/apply" evil >/dev/null || fail "helper failed"
[ -f "$tmp/state/sddm-theme/Main.qml" ] || fail "theme not installed"
[ -z "$(find "$tmp/state" -type l)" ] || fail "symlink copied"
! grep -rq TOP-SECRET "$tmp/state" || fail "root-only data reached the destination"

# 4. A skin that is itself a symlink to a root-only directory exposes nothing.
mkdir "$tmp/rootdir"; chmod 0700 "$tmp/rootdir"; echo TOP-SECRET > "$tmp/rootdir/Main.qml"
ln -s "$tmp/rootdir" "$tmp/home/.local/share/qylock/themes/swap"
if PKEXEC_UID=1000 bash "$tmp/apply" swap >/dev/null 2>&1; then fail "unreadable skin accepted"; fi
! grep -rq TOP-SECRET "$tmp/state" || fail "root-only directory copied"
[ -f "$tmp/state/sddm-theme/Main.qml" ] || fail "previous theme lost"
printf 'test-sddm-theme-apply-userns: PASS\n'
