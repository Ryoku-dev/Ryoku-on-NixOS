#!/usr/bin/env bash
# fixture test for controller and Bluetooth-adapter support: asserts the shipped
# policy, not its opposite. no hardware is touched and no root is needed; every
# check reads the repo's own package sets, PKGBUILDs and modprobe drop-in.
#
# each assertion here stands for a failure that is silent on the build host and
# only shows up as "my controller does not work" on a user's machine:
#
#   - ERTM back on             -> Xbox pads never finish pairing over Bluetooth
#   - autosuspend back on      -> Bluetooth headsets drop seconds after they
#                                 connect, reconnect, and drop again
#   - a driver left in the AUR -> `ryoku update` is pacman and can never install
#                                 it, so a box that missed the one-shot build
#                                 stays broken with no route to a fix
#   - a base entry with no     -> pacman cannot resolve it and the install breaks
#     [ryoku] recipe
#   - meson dropped            -> both meson packages fail on the build host
#                                 while building fine locally
#   - xone shipped by default  -> blacklists xpad AND mt76x2u, taking wired Xbox
#                                 pads, every XInput off-brand, and MediaTek USB
#                                 WiFi down with it
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$here/.."

base="$repo/system/packages/base.packages"
aur="$repo/system/packages/aur.packages"
ertm="$repo/system/hardware/input/99-ryoku-controller.conf"
autosuspend="$repo/system/hardware/bluetooth/99-ryoku-bt-autosuspend.conf"
toolchain="$repo/release/repo/build-toolchain.packages"

fails=0
fail() { printf 'FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

# a package set lists a name only as its own bare line, never as a substring of
# another entry or inside a comment.
listed() { grep -qxF "$1" "$2"; }

# ---- Xbox pads pair over Bluetooth ------------------------------------------

[[ -f $ertm ]] || fail "the ERTM drop-in is missing: $ertm"

if [[ -f $ertm ]]; then
  grep -qE '^options bluetooth disable_ertm=1$' "$ertm" ||
    fail 'the drop-in no longer sets disable_ertm=1, so Xbox pads will not pair'
fi

# ---- Bluetooth audio links survive the controller's autosuspend -------------

[[ -f $autosuspend ]] || fail "the btusb autosuspend drop-in is missing: $autosuspend"

if [[ -f $autosuspend ]]; then
  grep -qE '^options btusb enable_autosuspend=0$' "$autosuspend" ||
    fail 'the drop-in no longer sets btusb enable_autosuspend=0, so headsets drop seconds after connecting'
fi

# ---- the drivers a machine must have ----------------------------------------

for p in xpadneo-dkms game-devices-udev broadcom-bt-firmware; do
  listed "$p" "$base" || fail "$p is not in base.packages"

  # base.packages must be resolvable by pacman, so anything not in the official
  # repos needs a recipe in [ryoku].
  if ! pacman -Si "$p" >/dev/null 2>&1; then
    [[ -f $repo/release/packages/$p/PKGBUILD ]] ||
      fail "$p is in base.packages but neither an official package nor built by [ryoku]"
  fi
done

# ---- nothing controller-shaped may sit in the AUR set -----------------------

for p in xpadneo-dkms game-devices-udev broadcom-bt-firmware dualsensectl; do
  listed "$p" "$aur" &&
    fail "$p is in aur.packages, where \`ryoku update\` can never reach it"
done

# bake_aur_set dies on an empty set, so the file must keep real entries.
[[ $(grep -cvE '^\s*(#|$)' "$aur") -gt 0 ]] ||
  fail 'aur.packages is empty; the ISO offline bake refuses that'

# ---- opt-in packages stay opt-in --------------------------------------------

# dualsensectl is a control tool for a device most machines do not have.
listed dualsensectl "$base" &&
  fail 'dualsensectl is in base.packages; it is a control tool, not a driver'

# xone is the dongle driver. it ships `blacklist xpad` and `blacklist mt76x2u`,
# and upstream's own README says installing it disables xpad, so it must never
# arrive by default. its firmware is Microsoft-licensed and cannot be
# redistributed in a signed repo either.
for p in xone-dkms xone-dongle-firmware; do
  listed "$p" "$base" && fail "$p is in base.packages; it blacklists xpad and mt76x2u"
  [[ -f $repo/release/packages/$p/PKGBUILD ]] &&
    fail "$p has a [ryoku] recipe; its firmware is not ours to redistribute"
done

# ---- the recipes must be buildable on the host ------------------------------

# meson drives ninja; ninja alone is not enough. The list lives in one file now,
# read by both publish-repo.yml and container-install.sh: it used to be duplicated
# in both, and the copy that missed meson took the whole publish down.
grep -qxF meson "$toolchain" ||
  fail 'meson is missing from the build toolchain; the meson packages cannot build'
for consumer in .github/workflows/publish-repo.yml installation/tests/container-install.sh; do
  grep -q 'build-toolchain.packages' "$repo/$consumer" ||
    fail "$consumer no longer reads the shared build toolchain; a second copy will drift"
done

for p in xpadneo-dkms game-devices-udev dualsensectl broadcom-bt-firmware; do
  pkgbuild="$repo/release/packages/$p/PKGBUILD"
  [[ -f $pkgbuild ]] || { fail "$p has no PKGBUILD"; continue; }

  # a pinned checksum is the only thing standing between us and signing whatever
  # the upstream host served today.
  grep -qE '^(sha256sums|b2sums)=\(.[a-f0-9]{32}' "$pkgbuild" ||
    fail "$p has no pinned source checksum"

  grep -q 'SKIP' "$pkgbuild" && fail "$p skips source verification"
done

# game-devices-udev must not ship a second copy of the uinput module-load that
# ryoku-desktop already owns.
gdu="$repo/release/packages/game-devices-udev/PKGBUILD"
if [[ -f $gdu ]]; then
  grep -q 'modules-load' "$gdu" &&
    fail 'game-devices-udev ships a uinput modules-load file; ryoku-desktop already does'
fi

if ((fails)); then
  printf '\n%d check(s) failed\n' "$fails" >&2
  exit 1
fi

printf 'PASS: controllers and Bluetooth adapters ship as intended\n'
