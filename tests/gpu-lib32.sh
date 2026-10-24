#!/usr/bin/env bash
# Hermetic behavior checks for ryoku-gpu-lib32. A fake DRM tree selects the
# vendors and a fake host seam records the packages the helper requests.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
cmd="$here/../system/hardware/gpu/ryoku-gpu-lib32"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }

conf="$tmp/pacman.conf"
printf '[multilib]\nInclude = /dev/null\n' >"$conf"
fakebin="$tmp/bin"
mkdir -p "$fakebin"
capture="$tmp/packages"

cat >"$fakebin/ryoku-host" <<'EOF'
#!/bin/sh
case "${1:-}" in
  pkgmgr)
    printf '%s\n' "${RYOKU_TEST_PKGMGR:-pacman}"
    ;;
  pkg)
    shift
    if [ "${1:-}" = --overlay ]; then
      printf '%s\n' "$2" >"$RYOKU_HOST_CAPTURE.overlay"
      shift 2
    fi
    case "${1:-}" in
      status)
        shift
        for name in "$@"; do
          case " ${RYOKU_TEST_PROVIDED:-} " in
            *" $name "*) printf '%s\tavailable\trepo\t\n' "$name" ;;
            *) printf '%s\tunavailable\t\tNot packaged here.\n' "$name" ;;
          esac
        done
        ;;
      install)
        shift
        while [ "$#" -gt 0 ] && [ "${1#--}" != "$1" ]; do shift; done
        printf '%s\n' "$@" >"$RYOKU_HOST_CAPTURE"
        exit "${RYOKU_HOST_INSTALL_EXIT:-0}"
        ;;
      *) exit 2 ;;
    esac
    ;;
  *)
    exit 2
    ;;
esac
EOF
chmod +x "$fakebin/ryoku-host"

cat >"$fakebin/sudo" <<'EOF'
#!/bin/sh
exec "$@"
EOF
chmod +x "$fakebin/sudo"

# -Qq answers a provided name with the providing package, as pacman does; with
# no owner set, nvidia-utils is not installed at all.
cat >"$fakebin/pacman" <<'EOF'
#!/bin/sh
[ "${1:-}" = -Qq ] && [ "${2:-}" = nvidia-utils ] && [ -n "${RYOKU_TEST_NVIDIA_UTILS:-}" ] || exit 1
printf '%s\n' "$RYOKU_TEST_NVIDIA_UTILS"
EOF
chmod +x "$fakebin/pacman"

mk_card() { # <drm-root> <cardN> <driver>
  local d="$1/$2/device"
  mkdir -p "$d"
  printf 'DRIVER=%s\nPCI_SLOT_NAME=0000:0%s:00.0\n' "$3" "${2#card}" >"$d/uevent"
}

packages_for() { # <drm-root>
  : >"$capture"
  RYOKU_PACMAN_CONF="$conf" RYOKU_GPU_DRM_ROOT="$1" \
    RYOKU_HOST_CAPTURE="$capture" PATH="$fakebin:/usr/bin:/bin" \
    bash "$cmd" >/dev/null || return
  cat "$capture"
}

root="$tmp/amd"; mk_card "$root" card0 amdgpu
out="$(packages_for "$root")"
grep -qx 'lib32-mesa' <<<"$out" || fail "amd: missing lib32-mesa baseline"
grep -qx 'lib32-vulkan-icd-loader' <<<"$out" || fail "amd: missing loader baseline"
grep -qx 'lib32-vulkan-radeon' <<<"$out" || fail "amd: missing Radeon ICD"
grep -qEx 'lib32-vulkan-(intel|nouveau)|lib32-nvidia-utils' <<<"$out" \
  && fail "amd: wrong-vendor package requested"

root="$tmp/intel"; mk_card "$root" card0 i915
grep -qx 'lib32-vulkan-intel' <<<"$(packages_for "$root")" \
  || fail "intel: missing Intel ICD"

root="$tmp/nvidia"; mk_card "$root" card0 nvidia
grep -qx 'lib32-nvidia-utils' <<<"$(packages_for "$root")" \
  || fail "nvidia: missing NVIDIA userspace"

# A pre-Turing card runs a legacy branch whose utils provide nvidia-utils: the
# helper asks for that branch's 32-bit half, never the conflicting Turing+ one.
root="$tmp/nvidia-legacy"; mk_card "$root" card0 nvidia
out="$(RYOKU_TEST_NVIDIA_UTILS=nvidia-580xx-utils packages_for "$root")"
grep -qx 'lib32-nvidia-580xx-utils' <<<"$out" || fail "legacy nvidia: missing the branch's 32-bit userspace"
grep -qx 'lib32-nvidia-utils' <<<"$out" && fail "legacy nvidia: requested the conflicting Turing+ userspace"
out="$(RYOKU_TEST_NVIDIA_UTILS=nvidia-utils packages_for "$root")"
grep -qx 'lib32-nvidia-utils' <<<"$out" || fail "turing nvidia: missing NVIDIA userspace"

root="$tmp/hybrid"; mk_card "$root" card0 i915; mk_card "$root" card1 nvidia
out="$(packages_for "$root")"
grep -qx 'lib32-vulkan-intel' <<<"$out" || fail "hybrid: missing Intel ICD"
grep -qx 'lib32-nvidia-utils' <<<"$out" || fail "hybrid: missing NVIDIA userspace"
[[ $(grep -cx 'lib32-mesa' <<<"$out") -eq 1 ]] || fail "hybrid: lib32-mesa not deduped"

root="$tmp/none"; mkdir -p "$root"
out="$(packages_for "$root")"
grep -qx 'lib32-mesa' <<<"$out" || fail "none: missing baseline Mesa"
grep -qE '^lib32-vulkan-(radeon|intel|nouveau)$|^lib32-nvidia-utils$' <<<"$out" \
  && fail "none: a vendor package leaked in"

offconf="$tmp/pacman-noml.conf"
printf '[core]\nInclude = /dev/null\n' >"$offconf"
printf '#!/bin/sh\nexit 0\n' >"$fakebin/ryoku-pkg-multilib"
chmod +x "$fakebin/ryoku-pkg-multilib"
if RYOKU_PACMAN_CONF="$offconf" RYOKU_GPU_DRM_ROOT="$root" \
    RYOKU_HOST_CAPTURE="$capture" PATH="$fakebin:/usr/bin:/bin" \
    bash "$cmd" >/dev/null 2>&1; then
  fail "multilib off: should have exited non-zero"
fi

# Void ships only part of the lib32 set (the vendor ICDs, in multilib): the
# helper installs what the edition provides, forwards the catalogue table, and
# names what it skips instead of failing on Arch-only names.
root="$tmp/void"; mk_card "$root" card0 amdgpu
: >"$capture"
out="$(RYOKU_TEST_PKGMGR=xbps RYOKU_TEST_PROVIDED="lib32-vulkan-radeon" RYOKU_HOST_PKG_OVERLAY=/tables/void.tsv \
    RYOKU_GPU_DRM_ROOT="$root" RYOKU_HOST_CAPTURE="$capture" \
    PATH="$fakebin:/usr/bin:/bin" bash "$cmd" 2>&1)" || fail "Void lib32 install failed: $out"
[[ $(cat "$capture") == lib32-vulkan-radeon ]] || fail "Void: installed $(tr '\n' ' ' <"$capture") instead of the provided ICD only"
grep -Fq 'lib32-mesa has no package on this distribution' <<<"$out" || fail "Void: skipped baseline not named"
[[ $(cat "$capture.overlay") == /tables/void.tsv ]] || fail "Void: catalogue table not forwarded across sudo"

: >"$capture"
if ! out="$(RYOKU_TEST_PKGMGR=xbps RYOKU_GPU_DRM_ROOT="$root" RYOKU_HOST_CAPTURE="$capture" \
    PATH="$fakebin:/usr/bin:/bin" bash "$cmd" 2>&1)"; then
  fail "no Void libraries at all should be non-fatal"
fi
grep -Fq 'no 32-bit GPU packages are available on this distribution' <<<"$out" \
  || fail "no Void libraries: missing clear message"
[[ ! -s $capture ]] || fail "no Void libraries: an install still ran"

echo "gpu-lib32: all checks passed"
