#!/usr/bin/env bash
set -euo pipefail

backend=${RYOKU_INSTALL_BACKEND_SOURCE:?}

extract_function() {
  local name=$1
  awk -v start="$name() {" '
    $0 == start { printing=1 }
    printing { print }
    printing && $0 == "}" { exit }
  ' "$backend"
}

eval "$(extract_function disk_identity)"

udevadm() {
  printf 'ID_WWN=wwn-test\nID_SERIAL=serial-test\n'
}
lsblk() {
  case "$*" in
    *SIZE*) printf '500000000000\n' ;;
    *MODEL*) printf ' Test Disk \n' ;;
    *MAJ:MIN*) printf '8:240\n' ;;
    *) return 1 ;;
  esac
}

identity=$(disk_identity /dev/sdz)
[ "$identity" = 'wwn=wwn-test|serial=serial-test|size=500000000000' ] || {
  printf 'unexpected stable disk identity: %s\n' "$identity" >&2
  exit 1
}

eval "$(extract_function revalidate_install_disk)"
validate_install_disk() { install_disk=$1; }
install_disk=/dev/sdz
CURRENT_ID='wwn=one|serial=one|size=1'
disk_identity() { printf '%s\n' "$CURRENT_ID"; }
die() { printf '%s\n' "$*" >&2; exit 42; }

revalidate_install_disk /dev/sdz "$CURRENT_ID"

set +e
out="$({ CURRENT_ID='wwn=two|serial=two|size=1'; revalidate_install_disk /dev/sdz 'wwn=one|serial=one|size=1'; } 2>&1)"
rc=$?
set -e
[ "$rc" -eq 42 ] || {
  printf 'changed identity was not refused (rc=%s): %s\n' "$rc" "$out" >&2
  exit 1
}
grep -Fq 'installation disk identity changed before erase' <<< "$out"

# The size floor is enforced on the real disk before anything is erased. A
# disk that cannot hold the fresh closure would otherwise be wiped and then
# run out of space in the middle of nixos-install.
eval "$(grep -E '^min_install_disk_(gib|bytes)=' "$backend")"
eval "$(extract_function validate_install_disk)"
dry_run=0
readlink() { printf '%s\n' "${@: -1}"; }
detect_live_disk() { :; }
# validate_install_disk requires a block device; the sandbox has none.
function [ {
  if [[ $1 == -b && $2 == /dev/fake* ]]; then return 0; fi
  builtin [ "$@"
}
FAKE_SIZE=0
lsblk() {
  case "$*" in
    *TYPE*) printf 'disk\n' ;;
    *RO*) printf '0\n' ;;
    *SIZE*) printf '%s\n' "$FAKE_SIZE" ;;
    *MOUNTPOINTS*) : ;;
    *) return 1 ;;
  esac
}
gib=$((1024 * 1024 * 1024))

for small in 16 32 39; do
  set +e
  out="$( { FAKE_SIZE=$((small * gib)); validate_install_disk /dev/fakedisk; } 2>&1 )"
  rc=$?
  set -e
  [ "$rc" -eq 42 ] || {
    printf 'a %s GiB disk was accepted for installation (rc=%s): %s\n' "$small" "$rc" "$out" >&2
    exit 1
  }
  grep -Fq 'GiB minimum' <<< "$out"
done

FAKE_SIZE=$((40 * gib))
install_disk=""
validate_install_disk /dev/fakedisk
[ "$install_disk" = /dev/fakedisk ] || {
  printf 'a 40 GiB disk was refused: %s\n' "$install_disk" >&2
  exit 1
}
unset -f '['

python3 - "$backend" <<'PYCHECK'
from pathlib import Path
import sys
s = Path(sys.argv[1]).read_text()
confirm = s.index('Type the exact disk path')
recheck = s.index('revalidate_install_disk "$install_disk" "$validated_disk_identity"', confirm)
wipe = s.index('run_root wipefs -af "$install_disk"', recheck)
assert confirm < recheck < wipe
PYCHECK

printf 'installer-disk-identity: PASS\n'
