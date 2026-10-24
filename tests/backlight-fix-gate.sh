#!/usr/bin/env bash
# Regression tests for ryoku-hw-backlight-fix's gates.
#   #54: the AMD-only acpi_backlight=native quirk must not fire on Intel+NVIDIA
#        laptops, where nvidia_wmi_ec_backlight also registers with no AMD GPU.
#   #176: it must not fire on AMD+NVIDIA boards whose panel is driven by the EC
#        (the FA507NV family), where native instead freezes the screen -- and a
#        drop-in an earlier release already added there must be removed.
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
helper="$here/system/hardware/display/ryoku-hw-backlight-fix"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# fake sysfs: two DRM cards (card0 the iGPU, card1 the NVIDIA dGPU) plus a
# backlight dir. $1 = amd|intel picks card0's PCI vendor.
setup() {
  local kind="$1" vendor="0x8086"
  [[ $kind == amd ]] && vendor="0x1002"
  rm -rf "$tmp/drm" "$tmp/bl"
  mkdir -p "$tmp/drm/card0/device" "$tmp/drm/card1/device" "$tmp/bl"
  printf '%s\n' "$vendor" >"$tmp/drm/card0/device/vendor"
  printf '%s\n' "0x10de" >"$tmp/drm/card1/device/vendor"
}

run_fix() { # $1 = board name to fake in DMI (default: an allowed board)
  local board="${1:-GA402XV}"
  mkdir -p "$tmp/dmi"; printf '%s\n' "$board" >"$tmp/dmi/product_name"
  RYOKU_DRYRUN=1 RYOKU_DRM_PATH="$tmp/drm" RYOKU_BACKLIGHT_PATH="$tmp/bl" \
    RYOKU_DROPIN="$tmp/dropin.conf" RYOKU_DMI_PATH="$tmp/dmi" "$helper" 2>&1
}

# 1. Intel+NVIDIA, nvidia_wmi_ec present, no amdgpu_bl: must NOT fire (#54).
setup intel
mkdir -p "$tmp/bl/nvidia_wmi_ec_backlight"
out="$(run_fix)"
case "$out" in
  *"no AMD GPU"*) ;;
  *) echo "FAIL: fired on Intel+NVIDIA (#54): $out" >&2; exit 1 ;;
esac
case "$out" in
  *write*) echo "FAIL: wrote a drop-in on Intel+NVIDIA (#54): $out" >&2; exit 1 ;;
esac

# 2. ASUS AMD+NVIDIA (an allowed board), nvidia_wmi_ec present, no amdgpu_bl:
#    must apply the fix.
setup amd
mkdir -p "$tmp/bl/nvidia_wmi_ec_backlight"
out="$(run_fix GA402XV)"
case "$out" in
  *"write $tmp/dropin.conf"*) ;;
  *) echo "FAIL: did not apply the fix on an allowed AMD+NVIDIA board: $out" >&2; exit 1 ;;
esac

# 3. AMD present but amdgpu_bl* already works: no-op.
setup amd
mkdir -p "$tmp/bl/nvidia_wmi_ec_backlight" "$tmp/bl/amdgpu_bl0"
out="$(run_fix GA402XV)"
case "$out" in
  *"already present"*) ;;
  *) echo "FAIL: did not no-op when amdgpu_bl* exists: $out" >&2; exit 1 ;;
esac

# 4. A denied board (FA507NV) that already has the drop-in from an earlier
#    release: must remove it, not add it (#176).
setup amd
mkdir -p "$tmp/bl/nvidia_wmi_ec_backlight"
printf 'KERNEL_CMDLINE[default]+= acpi_backlight=native\n' >"$tmp/dropin.conf"
out="$(run_fix "ASUS TUF Gaming A15 FA507NV_FA507NV")"
case "$out" in
  *"removing $tmp/dropin.conf"*) ;;
  *) echo "FAIL: did not remove the drop-in on a denied board: $out" >&2; exit 1 ;;
esac
case "$out" in
  *"DRYRUN: rm -f $tmp/dropin.conf"*) ;;
  *) echo "FAIL: no rm issued for the denied board's drop-in: $out" >&2; exit 1 ;;
esac

# 5. A denied board with no prior drop-in: skip cleanly, write nothing.
setup amd
mkdir -p "$tmp/bl/nvidia_wmi_ec_backlight"
rm -f "$tmp/dropin.conf"
out="$(run_fix "ASUS TUF Gaming A15 FA507NV_FA507NV")"
case "$out" in
  *"would break it, skipping"*) ;;
  *) echo "FAIL: denied board did not skip cleanly: $out" >&2; exit 1 ;;
esac
case "$out" in
  *write*) echo "FAIL: wrote a drop-in on a denied board: $out" >&2; exit 1 ;;
esac

echo "backlight-fix-gate: ok"
