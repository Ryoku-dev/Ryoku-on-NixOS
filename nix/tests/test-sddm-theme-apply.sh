#!/usr/bin/env bash
# Regression tests for the passwordless ryoku-sddm-theme-apply helper.
# Runs unprivileged: setpriv and getent are stubbed, the state dir is a tempdir.
set -euo pipefail
repo=${RYOKU_PATH:-$(cd "$(dirname "$0")/../.." && pwd)}
script=$repo/nix/scripts/ryoku-sddm-theme-apply
tmp=$(mktemp -d)
trap 'chmod -R u+rwX "$tmp"; rm -rf "$tmp"' EXIT

cb=$(dirname "$(command -v cat)")
fb=$(dirname "$(command -v find)")
mkdir -p "$tmp/bin" "$tmp/home/.local/share/qylock/themes" "$tmp/state"
cat > "$tmp/bin/setpriv" <<STUB
#!$BASH
while [ "\$1" != -- ]; do shift; done; shift
printf '%s\n' "\$*" >> "$tmp/as-user.log"
exec "\$@"
STUB
cat > "$tmp/bin/getent" <<STUB
#!$BASH
printf 'tester:x:1000:1000::$tmp/home:/bin/sh\n'
STUB
printf '#!%s\nexit 0\n' "$BASH" > "$tmp/bin/flock"
chmod +x "$tmp/bin/setpriv" "$tmp/bin/getent" "$tmp/bin/flock"

sed -e '1d' \
  -e "s|@coreutils@|$cb|" -e "s|@findutils@|$fb|" \
  -e "s|@getent@|$tmp/bin/getent|" -e "s|@flock@|$tmp/bin/flock|" -e "s|@setpriv@|$tmp/bin/setpriv|" \
  -e "s|@stateDir@|$tmp/state/sddm-theme|" "$script" > "$tmp/apply"

themes=$tmp/home/.local/share/qylock/themes
secret=$tmp/root-only-secret
printf 'TOP-SECRET\n' > "$secret"
mkdir -p "$themes/good/sub" "$themes/evil/sub" "$themes/nomain"
echo qml > "$themes/good/Main.qml"; echo img > "$themes/good/sub/a.png"
echo qml > "$themes/evil/Main.qml"
ln -s "$secret" "$themes/evil/leak"
ln -s "$tmp" "$themes/evil/dirleak"
ln -s "$secret" "$themes/evil/sub/leak2"
ln -s "$secret" "$themes/onlylink-Main.qml"; mkdir "$themes/onlylink"
ln -s "$secret" "$themes/onlylink/Main.qml"
ln -s "$tmp" "$themes/escape"
echo x > "$themes/nomain/readme"

apply() { PKEXEC_UID=${UID_OVERRIDE:-1000} bash "$tmp/apply" "$@"; }
fail() { printf 'test-sddm-theme-apply: FAIL: %s\n' "$*" >&2; exit 1; }

apply good >/dev/null
[ -f "$tmp/state/sddm-theme/Main.qml" ] && [ -f "$tmp/state/sddm-theme/sub/a.png" ] || fail "good skin not installed"
[ "$(stat -c %a "$tmp/state/sddm-theme")" = 755 ] || fail "theme dir mode"

apply evil >/dev/null
[ -f "$tmp/state/sddm-theme/Main.qml" ] || fail "evil skin Main.qml missing"
[ -z "$(find "$tmp/state" -type l)" ] || fail "symlink copied into theme dir"
! grep -rq TOP-SECRET "$tmp/state" || fail "secret leaked via symlink"

before=$(find "$tmp/state/sddm-theme" -type f | sort)
for bad in escape onlylink nomain missing ../good /abs "" ; do
  if apply "$bad" >/dev/null 2>&1; then fail "slug '$bad' should be rejected"; fi
done
[ "$before" = "$(find "$tmp/state/sddm-theme" -type f | sort)" ] || fail "failed apply changed installed theme"
[ -z "$(ls -A "$tmp/state" | grep -E '^\.sddm-theme\.[A-Za-z0-9]{6}$')" ] || fail "staging dir leaked"
if UID_OVERRIDE=0 apply good >/dev/null 2>&1; then fail "root uid accepted"; fi
if env -u PKEXEC_UID -u SUDO_UID bash "$tmp/apply" good >/dev/null 2>&1; then fail "missing uid accepted"; fi

# Failure while installing must keep the previous theme (injected mv failure).
echo marker > "$tmp/state/sddm-theme/marker"
sed 's|if ! "$coreutils/mv" -T -- "$work/theme" "$state_dir"; then|if ! false; then|' "$tmp/apply" > "$tmp/apply-failmv"
cmp -s "$tmp/apply" "$tmp/apply-failmv" && fail "fault injection did not apply"
if PKEXEC_UID=1000 bash "$tmp/apply-failmv" good >/dev/null 2>&1; then fail "apply succeeded despite failed install"; fi
[ -f "$tmp/state/sddm-theme/marker" ] || fail "previous theme lost on failed install"

# Oversized skins are refused and leave the theme alone.
mkdir -p "$themes/big"; echo qml > "$themes/big/Main.qml"
for i in $(seq 1 4100); do : > "$themes/big/f$i"; done
if apply big >/dev/null 2>&1; then fail "file-count limit not enforced"; fi
[ -f "$tmp/state/sddm-theme/marker" ] || fail "previous theme lost after refused skin"
sed 's|^max_bytes=.*|max_bytes=10|' "$tmp/apply" > "$tmp/apply-small"
head -c 64 /dev/zero > "$themes/good/blob"
if PKEXEC_UID=1000 bash "$tmp/apply-small" good >/dev/null 2>&1; then fail "byte limit not enforced"; fi
[ -f "$tmp/state/sddm-theme/marker" ] || fail "previous theme lost after oversized skin"

# Every read of the user-controlled tree must be done as the invoking user.
grep -q "head -c [0-9]* -- $themes/good/Main.qml" "$tmp/as-user.log" || fail "skin read not performed as user"
grep -q "find $themes/good -type f" "$tmp/as-user.log" || fail "skin listing not performed as user"
! grep -Eq '(^|[^[:alnum:]_.-])(cp|rsync|tar)[[:space:]]' "$script" || fail "helper copies the user tree as root"
printf 'test-sddm-theme-apply: PASS\n'
