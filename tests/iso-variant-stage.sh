#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PROFILE=$ROOT/installation/iso
# shellcheck source=../installation/iso/stage-variant.sh
source "$PROFILE/stage-variant.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
items=(profiledef.sh packages.x86_64 pacman.conf airootfs efiboot syslinux grub)

copy_profile() {
  local destination=$1 item
  mkdir -p "$destination"
  for item in "${items[@]}"; do
    cp -a "$PROFILE/$item" "$destination/"
  done
}

fail() {
  printf 'iso-variant-stage: FAIL: %s\n' "$*" >&2
  exit 1
}

copy_profile "$tmp/plain"
ryoku_stage_variant plain "$tmp/plain"
for item in "${items[@]}"; do
  diff --no-dereference -qr "$PROFILE/$item" "$tmp/plain/$item" >/dev/null \
    || fail "plain staged $item differs from the committed profile"
done

cp -a "$tmp/plain" "$tmp/cachyos"
unset RYOKU_CACHYOS_MIRROR
ryoku_stage_variant cachyos "$tmp/cachyos"

packages=$tmp/cachyos/packages.x86_64
grep -qx 'linux-cachyos' "$packages" || fail 'linux-cachyos is absent from the live package set'
if grep -qx 'linux' "$packages"; then
  fail 'bare linux remains in the CachyOS live package set'
fi
for package in cachyos-keyring cachyos-mirrorlist cachyos-v3-mirrorlist \
  cachyos-v4-mirrorlist cachyos-hooks chwd; do
  [[ $(grep -cx "$package" "$packages") -eq 1 ]] \
    || fail "$package is not present exactly once in the live package set"
done
if grep -qx 'cachyos-settings' "$packages"; then
  fail 'cachyos-settings must not enable services in the live root'
fi

preset_dir=$tmp/cachyos/airootfs/etc/mkinitcpio.d
[[ ! -e $preset_dir/linux.preset ]] || fail 'stock linux.preset remains'
[[ -f $preset_dir/linux-cachyos.preset ]] || fail 'linux-cachyos.preset is absent'
grep -qx "ALL_kver='/boot/vmlinuz-linux-cachyos'" "$preset_dir/linux-cachyos.preset" \
  || fail 'preset does not name vmlinuz-linux-cachyos'
grep -qx 'archiso_image="/boot/initramfs-linux-cachyos.img"' "$preset_dir/linux-cachyos.preset" \
  || fail 'preset does not name initramfs-linux-cachyos.img'

mapfile -d '' boot_configs < <(
  find "$tmp/cachyos/efiboot" "$tmp/cachyos/grub" "$tmp/cachyos/syslinux" \
    -type f \( -name '*.conf' -o -name '*.cfg' \) -print0
)
((${#boot_configs[@]} > 0)) || fail 'no boot configs were discovered'
references=0
while IFS= read -r token; do
  references=$((references + 1))
  case $token in
    vmlinuz-linux-cachyos | initramfs-linux-cachyos.img) ;;
    *) fail "unexpected kernel path token in boot configs: $token" ;;
  esac
done < <(grep -hEo 'vmlinuz-[[:alnum:]_.-]+|initramfs-[[:alnum:]_.-]+\.img' \
  "${boot_configs[@]}" || true)
((references > 0)) || fail 'boot configs contain no kernel or initramfs paths'

pacman_conf=$tmp/cachyos/pacman.conf
cachyos_line=$(grep -n '^\[cachyos\]$' "$pacman_conf" | cut -d: -f1)
core_line=$(grep -n '^\[core\]$' "$pacman_conf" | cut -d: -f1)
[[ -n $cachyos_line && -n $core_line && $cachyos_line -lt $core_line ]] \
  || fail '[cachyos] is not above [core]'
grep -qxF 'Server = https://mirror.cachyos.org/repo/$arch/$repo' "$pacman_conf" \
  || fail '[cachyos] does not use the configured TLS mirror'

grep -qx 'iso_application="Ryoku Linux Installer (CachyOS)"' \
  "$tmp/cachyos/profiledef.sh" || fail 'CachyOS iso_application is absent'
grep -q 'installer (CachyOS edition, live)' "$tmp/cachyos/airootfs/etc/motd" \
  || fail 'CachyOS edition is absent from the motd'
for config in "${boot_configs[@]}"; do
  while IFS= read -r title; do
    [[ $title == *'Ryoku Linux installer (CachyOS)'* ]] \
      || fail "unbranded boot menu title in ${config#$tmp/cachyos/}: $title"
  done < <(grep -E '^[[:space:]]*(title|menuentry|MENU (TITLE|LABEL))[[:space:]].*Ryoku Linux installer' "$config" || true)
done

cp -a "$tmp/cachyos" "$tmp/once"
ryoku_stage_variant cachyos "$tmp/cachyos"
diff --no-dereference -qr "$tmp/once" "$tmp/cachyos" >/dev/null \
  || fail 'running the CachyOS transform twice changes its output'

printf 'iso-variant-stage: PASS\n'
