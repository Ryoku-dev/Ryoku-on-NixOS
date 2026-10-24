#!/usr/bin/env bash
set -euo pipefail

root=${RYOKU_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
helper="$root/system/extras/ryoku-pkg-cachyos"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }

mkdir -p "$tmp/bin" "$tmp/runtime"
cat >"$tmp/bin/ryoku-host" <<'EOF'
#!/usr/bin/env bash
[[ ${1:-} == pkgmgr ]] && printf '%s\n' pacman
EOF
cat >"$tmp/bin/ld-linux" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'x86-64-v3 (supported, searched)'
EOF
cat >"$tmp/bin/pacman-key" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"$tmp/bin/pacman" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$RYOKU_TEST_CALLS"
EOF
chmod +x "$tmp/bin"/*

run_helper() {
  local conf=$1
  # The installer exports its host-side offline config under
  # RYOKU_PACMAN_CONF. The target helper must ignore that leaked path.
  PATH="$tmp/bin:$PATH" XDG_RUNTIME_DIR="$tmp/runtime" \
    RYOKU_PACMAN_CONF=/nonexistent/offline.conf \
    RYOKU_PKG_CACHYOS_CONF="$conf" RYOKU_PRIVILEGE_COMMAND='' \
    RYOKU_LD_LINUX="$tmp/bin/ld-linux" RYOKU_TEST_CALLS="$tmp/pacman.calls" \
    "$helper" >/dev/null
}

section_line() {
  local conf=$1 section=$2
  awk -v section="[$section]" '$0 == section { print NR; exit }' "$conf"
}

assert_appended_order() {
  local conf=$1 core extra multilib ryoku v3 cachyos
  core=$(section_line "$conf" core)
  extra=$(section_line "$conf" extra)
  multilib=$(section_line "$conf" multilib)
  ryoku=$(section_line "$conf" ryoku)
  v3=$(section_line "$conf" cachyos-v3)
  cachyos=$(section_line "$conf" cachyos)
  [[ -n $core && -n $extra && -n $multilib && -n $ryoku && -n $v3 && -n $cachyos ]] \
    || fail "missing repository stanza in $conf"
  (( core < extra && extra < multilib && multilib < ryoku && ryoku < v3 && v3 < cachyos )) \
    || fail "CachyOS repositories are not after Arch and ryoku in $conf"
  [[ $(grep -c '^\[cachyos-v3\]$' "$conf") -eq 1 ]] \
    || fail "expected one [cachyos-v3] stanza in $conf"
  [[ $(grep -c '^\[cachyos\]$' "$conf") -eq 1 ]] \
    || fail "expected one [cachyos] stanza in $conf"
  grep -qE '^Architecture[[:space:]]*=.*x86_64_v3' "$conf" \
    || fail "x86_64_v3 is not enabled in $conf"
}

stock="$tmp/stock.conf"
cat >"$stock" <<'EOF'
[options]
Architecture = auto

[core]
Server = https://arch.example/core

[extra]
Server = https://arch.example/extra

[multilib]
Server = https://arch.example/multilib

[ryoku]
Server = https://repo.example/ryoku
EOF
run_helper "$stock"
assert_appended_order "$stock"
grep -qxF 'Server = https://mirror.cachyos.org/repo/x86_64_v3/cachyos-v3' "$stock" \
  || fail "v3 mirror path is wrong"
grep -qxF 'Server = https://mirror.cachyos.org/repo/x86_64/cachyos' "$stock" \
  || fail "baseline mirror path is wrong"
grep -qxF -- '-Sy' "$tmp/pacman.calls" \
  || fail "repository databases were not synchronized"
grep -qxF -- '-S --needed --noconfirm cachyos-keyring' "$tmp/pacman.calls" \
  || fail "cachyos-keyring was not installed from the configured baseline repository"

old="$tmp/old-helper.conf"
cat >"$old" <<'EOF'
[options]
Architecture = auto x86_64_v3

[cachyos-v3]
Server = https://mirror.cachyos.org/repo/x86_64_v3/cachyos-v3

[core]
Server = https://arch.example/core

[extra]
Server = https://arch.example/extra

[multilib]
Server = https://arch.example/multilib

[ryoku]
Server = https://repo.example/ryoku
EOF
run_helper "$old"
assert_appended_order "$old"

edition="$tmp/cachyos-edition.conf"
cat >"$edition" <<'EOF'
[options]
Architecture = auto

[cachyos-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

[cachyos]
Include = /etc/pacman.d/cachyos-mirrorlist

[core]
Include = /etc/pacman.d/mirrorlist
EOF
cp "$edition" "$tmp/cachyos-edition.before"
run_helper "$edition"
cmp -s "$tmp/cachyos-edition.before" "$edition" \
  || fail "CachyOS edition pacman.conf was changed"

fixed="$tmp/already-fixed.conf"
cat >"$fixed" <<'EOF'
[options]
Architecture = auto x86_64_v3

[core]
Server = https://arch.example/core

[extra]
Server = https://arch.example/extra

[multilib]
Server = https://arch.example/multilib

[ryoku]
Server = https://repo.example/ryoku

[cachyos-v3]
Server = https://mirror.cachyos.org/repo/x86_64_v3/cachyos-v3

[cachyos]
Server = https://mirror.cachyos.org/repo/x86_64/cachyos
EOF
cp "$fixed" "$tmp/already-fixed.before"
run_helper "$fixed"
cmp -s "$tmp/already-fixed.before" "$fixed" \
  || fail "already-fixed pacman.conf was changed"

echo "cachyos-repo-placement: all checks passed"
