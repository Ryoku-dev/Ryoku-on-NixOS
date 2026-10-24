#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# fixture test for the bootloader step's limine.conf handling: the config must
# land at the ESP root (/boot/limine.conf, the one location limine-entry-tool
# manages -- anything else shadows the generated kernel + snapshot entries),
# default_entry must match the menu shape (1 = flat placeholder, else the
# kernel entry path), the post-AUR promote must retire the flat entry, and the
# adopted-layout repoint must strip the leftover boot stanza from the menu
# directory (a directory carrying a boot body cannot autoboot -- the countdown
# loops) without touching foreign entries. all hermetic: dry-run for the
# installer paths, a temp file for the surgery.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$here/.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }

# shellcheck source=../installation/backend/lib/common.sh
source "$repo/installation/backend/lib/common.sh"
# shellcheck source=../installation/backend/lib/bootloader.sh
source "$repo/installation/backend/lib/bootloader.sh"

export RYOKU_REPO="$repo"
export RYOKU_DRYRUN=1
CMDLINE="root=UUID=test-uuid rootflags=subvol=@ rw"

# --- with_entry: flat menu, ESP-root path, bootable default ----------------
out="$(ryoku_boot_limine_conf with_entry)"
grep -qF 'DRYRUN: write /mnt/boot/limine.conf:' <<<"$out" \
  || fail "with_entry must write /boot/limine.conf (the ESP root), nothing else"
grep -qF 'default_entry: 1' <<<"$out" \
  || fail "flat menu must default to entry 1 (there is no tree directory to skip)"
grep -qF 'remember_last_entry: yes' <<<"$out" \
  || fail "with_entry must ship remember_last_entry: yes"
grep -qF 'default_entry: 2' <<<"$out" \
  && fail "flat menu left default_entry: 2 (would autoboot a second entry, e.g. Windows)"
grep -qF '/Ryoku Linux' <<<"$out" || fail "with_entry missing the flat kernel entry"
grep -qF "cmdline: $CMDLINE quiet splash" <<<"$out" || fail "flat entry missing the real cmdline"
grep -qF 'rm -f' <<<"$out" || fail "with_entry must remove the shadowing config candidates"
grep -qF '/mnt/boot/limine/limine.conf' <<<"$out" \
  || fail "the shadow candidate /boot/limine/limine.conf is not in the cleanup list"

# --- branding_only: globals only; default + remember set, entries left to hook -
out="$(ryoku_boot_limine_conf branding_only)"
grep -qF 'default_entry: 1' <<<"$out" \
  || fail "branding_only must ship default_entry: 1 (finalize repoints to the kernel path once the hook builds the tree)"
grep -qF 'remember_last_entry: yes' <<<"$out" \
  || fail "branding_only must ship remember_last_entry: yes"
grep -qE '^/Ryoku Linux' <<<"$out" && fail "branding_only must not carry the placeholder entry"

# --- selected kernel: layer defaults CachyOS and keeps Arch fallback --------
out="$(RYOKU_VARIANT=plain RYOKU_CACHYOS_LAYER_ACTIVE=1 \
  RYOKU_CACHYOS_DEFAULT_KERNEL=1 ryoku_boot_limine_conf with_entry)"
grep -qxF '        | linux-cachyos' <<<"$out" \
  || fail "layer install did not record linux-cachyos as the default kernel"
grep -qxF '        |     kernel_path: boot():/vmlinuz-linux-cachyos' <<<"$out" \
  || fail "layer install did not put linux-cachyos in the default flat entry"
grep -qxF '        | /Arch Linux (fallback)' <<<"$out" \
  || fail "layer install did not title the stock-kernel fallback clearly"
grep -qxF '        |     kernel_path: boot():/vmlinuz-linux' <<<"$out" \
  || fail "layer install did not retain stock linux as the fallback"

# An NVIDIA module failure leaves the layer installed but keeps stock linux as
# default. The secondary entry then remains the CachyOS kernel.
out="$(RYOKU_VARIANT=plain RYOKU_CACHYOS_LAYER_ACTIVE=1 \
  RYOKU_CACHYOS_DEFAULT_KERNEL=0 ryoku_boot_limine_conf with_entry)"
grep -qxF '        | linux' <<<"$out" \
  || fail "NVIDIA fallback did not record stock linux as the default kernel"
grep -qxF '        |     kernel_path: boot():/vmlinuz-linux' <<<"$out" \
  || fail "NVIDIA fallback did not boot stock linux first"
grep -qxF '        | /CachyOS Linux' <<<"$out" \
  || fail "NVIDIA fallback did not retain the CachyOS kernel as the second entry"

# The full CachyOS edition uses the same selector but has no stock kernel entry.
out="$(RYOKU_VARIANT=cachyos RYOKU_CACHYOS_LAYER_ACTIVE=0 \
  RYOKU_CACHYOS_DEFAULT_KERNEL=0 ryoku_boot_limine_conf with_entry)"
grep -qxF '        | linux-cachyos' <<<"$out" \
  || fail "CachyOS edition did not record linux-cachyos"
grep -qxF '        | /Arch Linux (fallback)' <<<"$out" \
  && fail "CachyOS edition added a stock kernel it does not install"

# The shared-ESP stage-2 seed follows the same default/fallback contract.
out="$(RYOKU_VARIANT=plain RYOKU_CACHYOS_LAYER_ACTIVE=1 \
  RYOKU_CACHYOS_DEFAULT_KERNEL=1 ryoku_alongside_conf_text linux none deadbeef)"
grep -qF 'kernel_path: fslabel(RYOKUBOOT):/vmlinuz-linux-cachyos' <<<"$out" \
  || fail "alongside layer seed did not boot linux-cachyos first"
grep -qF '/Arch Linux (fallback)' <<<"$out" \
  || fail "alongside layer seed omitted the Arch fallback"

# --- install_efi: the tool-refreshed binary path, never limine.efi ---------
# shellcheck disable=SC2034  # consumed by the sourced ryoku_boot_install_efi
ESP_DEV=/dev/vda1 RYOKU_DISK=/dev/vda
out="$(ryoku_boot_install_efi)"
grep -qF '/mnt/boot/EFI/limine/limine_x64.efi' <<<"$out" \
  || fail "EFI binary must land on limine_x64.efi (the path limine-install refreshes on upgrades)"
grep -qF '\EFI\limine\limine_x64.efi' <<<"$out" \
  || fail "NVRAM entry must point at limine_x64.efi so the tool's dedup recognizes it"
grep -qF '/mnt/boot/EFI/limine/limine.efi ' <<<"$out" \
  && fail "the stale hand-copied limine.efi path is back"

# --- promote: drop the flat entry, repoint the default, keep foreigners ----
unset RYOKU_DRYRUN
conf="$tmp/limine.conf"
cat >"$conf" <<'EOF'
timeout: 3
default_entry: 1
interface_branding: Ryoku Bootloader

/Ryoku Linux
    protocol: linux
    kernel_path: boot():/vmlinuz-linux
    cmdline: root=UUID=x rw quiet splash
    module_path: boot():/initramfs-linux.img

/+Ryoku
    comment: Ryoku
//linux
    protocol: efi
    path: boot():/EFI/Linux/ryoku_linux.efi

# >>> ryoku-windows-entry (managed) >>>
/Windows
    comment: Boot into Windows
    protocol: efi_chainload
    path: uuid(abc):/EFI/Microsoft/Boot/bootmgfw.efi
# <<< ryoku-windows-entry (managed) <<<
EOF

ryoku_boot_limine_promote "$conf"
grep -qF '/Ryoku Linux' "$conf" && fail "promote left the flat placeholder entry"
grep -qF 'kernel_path: boot():/vmlinuz-linux' "$conf" && fail "promote left the placeholder's options"
grep -qxF 'default_entry: Ryoku/linux' "$conf" || fail "promote must repoint default_entry at the tree's first UKI entry path"
grep -qxF 'remember_last_entry: yes' "$conf" || fail "promote must enable remember_last_entry so the last kernel autoboots"
grep -qxF '/+Ryoku' "$conf" || fail "promote clobbered the tool's boot tree"
grep -qxF '/Windows' "$conf" || fail "promote clobbered the Windows chainload entry"
grep -qF 'interface_branding: Ryoku Bootloader' "$conf" || fail "promote clobbered the branding"

# promote is idempotent: a second run changes nothing.
cp "$conf" "$tmp/before.conf"
ryoku_boot_limine_promote "$conf"
diff -q "$tmp/before.conf" "$conf" >/dev/null || fail "second promote changed the file"

# The generated hook tree follows the recorded layer default, not entry order.
conf="$tmp/layer-tree.conf"
cat >"$conf" <<'EOF'
timeout: 3
default_entry: 1
remember_last_entry: no

/+Ryoku
//linux
    protocol: efi
    path: boot():/EFI/Linux/ryoku_linux.efi
//linux-cachyos
    protocol: efi
    path: boot():/EFI/Linux/ryoku_linux-cachyos.efi
EOF
RYOKU_VARIANT=plain RYOKU_CACHYOS_DEFAULT_KERNEL=1 \
  ryoku_limine_autoboot "$conf"
grep -qxF 'default_entry: Ryoku/linux-cachyos' "$conf" \
  || fail "layer default did not repoint the hook tree to linux-cachyos"

# --- repoint: adopted layout keeps every entry, default moves inside -------
# limine-entry-tool 1.37+ nests the "//<kernel>" entries under the flat
# placeholder instead of writing a standalone /+ tree.
conf="$tmp/adopted.conf"
cat >"$conf" <<'EOF'
timeout: 3
default_entry: 1

/Ryoku Linux
    protocol: linux
    kernel_path: boot():/vmlinuz-linux
    cmdline: root=UUID=x rw quiet splash
    module_path: boot():/initramfs-linux.img

  //linux
  ### auto-generated by limine-entry-tool
  comment: Kernel version: 7.0.12
  protocol: efi
  path: boot():/EFI/Linux/ryoku_linux.efi

     //Snapshots
     comment: 1 / 5 snapshots
EOF

ryoku_boot_limine_repoint "$conf"
grep -qxF 'default_entry: Ryoku Linux/linux' "$conf" || fail "repoint must move the default onto the nested kernel entry path"
grep -qxF 'remember_last_entry: yes' "$conf" || fail "repoint must enable remember_last_entry so the last kernel autoboots"
grep -qF '/Ryoku Linux' "$conf" || fail "repoint dropped the adopted tree root"
grep -qF '  //linux' "$conf" || fail "repoint damaged the nested kernel entry"
grep -qF 'path: boot():/EFI/Linux/ryoku_linux.efi' "$conf" || fail "repoint damaged the UKI entry body"
grep -qF '//Snapshots' "$conf" || fail "repoint dropped the Snapshots submenu"
grep -qF 'comment: Kernel version: 7.0.12' "$conf" || fail "repoint dropped the UKI comment"
# the flat placeholder's boot stanza must be gone: a directory carrying a boot
# body cannot autoboot (Limine allows only a comment before the first
# sub-entry), which is the countdown-loop bug this repoint fixes.
grep -qF 'kernel_path:' "$conf" && fail "repoint left the placeholder boot stanza (kernel_path) on the directory"
grep -qF 'module_path:' "$conf" && fail "repoint left the placeholder boot stanza (module_path) on the directory"

cp "$conf" "$tmp/adopted-before.conf"
ryoku_boot_limine_repoint "$conf"
diff -q "$tmp/adopted-before.conf" "$conf" >/dev/null || fail "second repoint changed the file"

# --- alongside: the stage-loader refresh hook -------------------------------
# limine's own deploy hook only refreshes ESP_PATH/EFI/limine/limine_x64.efi,
# which the two-stage layout never boots. Without this hook both Ryoku stage
# loaders keep the version the ISO shipped while limine.conf moves on.
hookdir="$tmp/hooks/etc/pacman.d/hooks"
mkdir -p "$hookdir"
# the stubs stand in for common.sh's writers, called from the sourced lib.
# shellcheck disable=SC2329,SC2317
( set +u
  run() { :; }
  log() { :; }
  write_file() { cat >"${1/\/mnt/$tmp/hooks}"; }
  RYOKU_DRYRUN=""
  ryoku_alongside_stage_hook
) || fail "ryoku_alongside_stage_hook failed"
hook="$hookdir/ryoku-limine-stage.hook"
[[ -f $hook ]] || fail "the alongside path wrote no stage-loader refresh hook"
grep -qxF 'Target = limine' "$hook" || fail "the stage hook does not trigger on the limine package"
grep -qF '/boot/ryoku-limine.efi' "$hook" || fail "the stage hook does not refresh the second-stage loader"
grep -qF '/efi/EFI/ryoku/BOOTX64.EFI' "$hook" || fail "the stage hook does not refresh the stage-1 loader on the shared ESP"

# --- alongside: limine-install must not register its own NVRAM entry --------
# ESP_PATH is our XBOOTLDR here, not an ESP: a "Limine" entry pointing at it
# lands next to the real 'Ryoku' entry and boots nothing (seen on a user's box).
defaults="$tmp/etc/default/limine"
mkdir -p "$(dirname "$defaults")"
printf 'ESP_PATH="/boot"\n' >"$defaults"
( set +u
  RYOKU_DRYRUN=""
  RYOKU_DISK_STRATEGY=alongside
  chroot_has_pkg() { return 1; }
  eval "$(declare -f ryoku_bootloader_finalize_alongside | sed 's#/mnt/etc/default/limine#'"$defaults"'#')"
  ryoku_bootloader_finalize_alongside
) || fail "ryoku_bootloader_finalize_alongside failed"
grep -qxF 'EFI_REGISTER=no' "$defaults" || fail "alongside does not pin EFI_REGISTER=no in /etc/default/limine"
grep -qxF 'FIND_BOOTLOADERS=no' "$defaults" || fail "alongside stopped pinning FIND_BOOTLOADERS=no"

# --- dedicated alongside: preserve a detected Linux loader by PARTUUID -----
dedicated_conf="$tmp/dedicated-limine.conf"
dedicated_state="$tmp/limine-existing-esp"
printf 'timeout: 3\n/Ryoku Linux\n    protocol: linux\n' >"$dedicated_conf"
(
  RYOKU_DRYRUN=""
  RYOKU_DISK_STRATEGY=alongside
  RYOKU_ESP_MODE=dedicated
  RYOKU_DISK=/dev/loop0
  ESP_DEV=/dev/loop0p2
  RYOKU_PF_ESP=/dev/loop0p1
  RYOKU_PF_ESP_KIND=linux
  RYOKU_PF_ESP_BOOT=/EFI/systemd/systemd-bootx64.efi
  blkid() {
    [[ $* == *"/dev/loop0p1"* ]] || fail "dedicated entry used the new Ryoku ESP"
    printf '11111111-2222-3333-4444-555555555555\n'
  }
  log() { :; }
  ryoku_dedicated_existing_entry "$dedicated_conf" "$dedicated_state"
  ryoku_dedicated_existing_entry "$dedicated_conf" "$dedicated_state"
) || fail "dedicated existing-Linux entry generation failed"
[[ $(grep -c '^/Linux (existing)$' "$dedicated_conf") -eq 1 ]] \
  || fail "dedicated mode did not add exactly one existing-Linux entry"
grep -qF 'image_path: guid(11111111-2222-3333-4444-555555555555):/EFI/systemd/systemd-bootx64.efi' "$dedicated_conf" \
  || fail "dedicated existing-Linux entry is not addressed by ESP PARTUUID"
[[ $(cat "$dedicated_state") == $'linux\t11111111-2222-3333-4444-555555555555\t/EFI/systemd/systemd-bootx64.efi' ]] \
  || fail "dedicated mode did not persist the existing ESP metadata"

# --- dedicated alongside: use the own-ESP boot path, never shared stage 1 ---
calls=$(
  RYOKU_DISK_STRATEGY=alongside RYOKU_ESP_MODE=dedicated bash -c '
    source "'"$repo"'/installation/backend/lib/common.sh"
    source "'"$repo"'/installation/backend/lib/bootloader.sh"
    ryoku_cmdline() { :; }
    ryoku_boot_plymouth() { :; }
    ryoku_boot_default_limine() { :; }
    ryoku_boot_vmd() { :; }
    ryoku_bootloader_alongside() { echo shared; }
    ryoku_bootloader_own_esp() { echo dedicated; }
    run() { :; }
    ryoku_bootloader
  '
)
grep -qx 'dedicated' <<<"$calls" || fail "dedicated alongside did not use its own ESP path: $calls"
! grep -qx 'shared' <<<"$calls" || fail "dedicated alongside touched the shared-ESP path: $calls"

echo "limine-bootloader: all checks passed"
