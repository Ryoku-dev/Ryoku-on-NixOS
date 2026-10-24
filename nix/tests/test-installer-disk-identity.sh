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
# Read by revalidate_install_disk, imported through eval.
# shellcheck disable=SC2034
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
