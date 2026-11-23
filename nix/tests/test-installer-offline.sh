#!/usr/bin/env bash
# Exercise the real whole-disk workflow with command doubles, never block devices.
set -euo pipefail
backend=${RYOKU_INSTALL_BACKEND_SOURCE:-nix/apps/ryoku-install-backend.sh}
helper=${RYOKU_INSTALL_OFFLINE_HELPER:-nix/iso/offline/install.sh}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/zoneinfo"
touch "$work/zoneinfo/UTC"
extract_function() {
  awk -v start="$1() {" '$0 == start { printing=1 } printing { print } printing && $0 == "}" { exit }' "$backend"
}
run_case() (
  set -euo pipefail
  scenario=$1
  trace="$work/$scenario.trace"
  : > "$trace"
  record() { printf '%s\n' "$*" >> "$trace"; }
  # shellcheck disable=SC1090
  source "$helper"
  body=$(extract_function install_iso)
  body=${body//@ZONEINFO_ROOT@/"$work/zoneinfo"}
  eval "$body"
  die() { echo "$*" >&2; exit 42; }
  run_root() { "$@"; }
  validate_install_disk() { record validate-disk; }
  disk_identity() { echo test-disk; }
  revalidate_install_disk() { record revalidate-disk; }
  resolve_gpu_vendors() { gpu_vendors=(); }
  choose_install_parallelism() { echo '1 2'; }
  valid_hostname() { return 0; }
  valid_username() { return 0; }
  valid_timezone() { return 0; }
  valid_locale() { return 0; }
  valid_keyboard() { return 0; }
  target_source_ref_for_install() { echo path:/test-source; }
  target_track_ref_for_install() { echo path:/test-source; }
  render_iso_target() {
    mkdir -p "$1"
    echo '{}' > "$1/flake.nix"
    echo '{}' > "$1/install-values.nix"
  }
  # Replace only external tools. Offline prebuild/UUID/install functions above
  # remain the production implementations.
  nix() {
    record "nix $*"
    case $1 in
      flake) return 0 ;;
      eval) return 0 ;;
      build)
        [[ $scenario != missing-package ]] || return 1
        printf '%s\n' "${RYOKU_INSTALL_TEST_SYSTEM:-$(readlink -f /run/current-system)}"
        ;;
      *) return 1 ;;
    esac
  }
  nixos-generate-config() { record "hardware-scan $*"; echo '{ ... }: {}'; }
  nixos-install() { record "nixos-install $*"; }
  nix-env() { record "nix-env $*"; }
  findmnt() { return 1; }
  partition_by_number() { echo "/dev/test$2"; }
  wipefs() { record "wipefs $*"; }
  parted() { record "parted $*"; }
  partprobe() { :; }
  udevadm() { :; }
  mkfs.ext4() { record "mkfs.ext4 $*"; }
  mkfs.btrfs() { record "mkfs.btrfs $*"; }
  mkfs.fat() { record "mkfs.fat $*"; }
  mount() { :; }
  umount() { :; }
  chown() { :; }
  install() { cp "${@: -2:1}" "${@: -1}"; }
  sync() { :; }
  install_disk=/dev/test
  assume_yes=1 dry_run=0 filesystem=ext4 firmware_choice=uefi
  [[ $scenario != btrfs ]] || filesystem=btrfs
  target_hostname=testhost target_username=testuser target_timezone=UTC
  target_locale=en_US.UTF-8 target_keyboard=us kernel_choice=default
  config_mode=ryoku gpu_vendors=() selected_apps=()
  compositor=niri browser=firefox shell_choice=zsh
  import_flake='' import_host='' iso_work=''
  target_root="$work/$scenario-target"
  mkdir -p "$target_root"
  confirm_disk=$install_disk
  bootstrap_cache=(--option substituters '' --option builders '')
  export RYOKU_INSTALL_OFFLINE=/test-sources
  export RYOKU_INSTALL_PASSWORD_HASH='$y$test-hash'
  install_iso
)
for scenario in missing-package ext4 btrfs; do
  set +e
  run_case "$scenario" > "$work/$scenario.log" 2>&1
  result=$?
  set -e
  trace="$work/$scenario.trace"
  if [[ $scenario == missing-package ]]; then
    [[ $result -eq 42 ]]
    ! grep -q '^wipefs ' "$trace"
    ! grep -q '^nixos-install ' "$trace"
    grep -q 'no disk changes were made' "$work/$scenario.log"
  else
    if [[ $result -ne 0 ]]; then cat "$work/$scenario.log"; exit 1; fi
    grep -q '^wipefs ' "$trace"
    grep -q 'nixos-install .*--system /nix/store/' "$trace"
    ! grep -q 'nixos-install .*--flake' "$trace"
    grep -q 'nix-env .*ryoku-offline-sources' "$trace"
    python3 - "$work/$scenario-target/etc/nixos/hardware-configuration.nix" "$trace" "$scenario" <<'PY'
import pathlib, re, sys
hardware = pathlib.Path(sys.argv[1]).read_text()
trace = pathlib.Path(sys.argv[2]).read_text()
uuids = re.findall(r'by-uuid/([^"\s]+)', hardware)
assert len(uuids) == 2, hardware
assert f'-U {uuids[0]}' in trace, trace
assert f'-i {uuids[1].replace("-", "")}' in trace, trace
assert f'mkfs.{sys.argv[3]} ' in trace
assert trace.index('nix build ') < trace.index('wipefs ')
assert trace.index('revalidate-disk') < trace.index('wipefs ')
PY
  fi
done
printf 'offline installer: missing dependencies stop before disk writes; ext4/Btrfs UUIDs and prebuilt installation verified\n'
