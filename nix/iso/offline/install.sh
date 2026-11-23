# Sourced by the existing backend only inside the offline ISO's network namespace.
# Variables below are shared with the backend's install_iso scope.
# shellcheck disable=SC2154,SC2034
offline_init() {
  [[ $EUID -eq 0 && ${NIX_REMOTE:-} == local ]] || die 'launch the offline ISO installer wrapper'
  [[ $(readlink /proc/self/ns/net) != "$(readlink /proc/1/ns/net)" ]] || die 'offline installer requires a private network namespace'
  [[ -d $RYOKU_INSTALL_OFFLINE ]] || die 'offline source payload is missing'
  bootstrap_cache=(--option substituters '' --option builders '' --option fallback false)
  kernel_choice=latest
  compositor=niri
  browser=firefox
  shell_choice=fish
  selected_apps=()
  [[ $config_mode == ryoku ]] || die 'the minimal offline image supports only its generated Ryoku configuration'
}

offline_write_profile() {
  python3 - "$iso_work/install-values.nix" <<'PY_PROFILE'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text().rstrip()
if not text.endswith('}'):
    raise SystemExit('invalid generated install-values.nix')
path.write_text(text[:-1] + '  minimal = true;\n}\n')
PY_PROFILE
}

# Also constrain subprocesses that use Nix during evaluation or system assembly.
nix() {
  command nix --offline --option substituters '' --option builders '' "$@"
}

offline_prepare_hardware() {
  # Allocate identifiers before erasing anything, so the exact final system can
  # be built and validated while the existing target disk is still untouched.
  offline_root_uuid=$(cat /proc/sys/kernel/random/uuid)
  offline_efi_id=$(od -An -N4 -tx4 /dev/urandom | tr -d ' \n' | tr '[:lower:]' '[:upper:]')
  local efi_uuid="${offline_efi_id:0:4}-${offline_efi_id:4:4}"
  nixos-generate-config --root "$iso_work" --show-hardware-config --no-filesystems \
    > "$iso_work/hardware-detected.nix"
  cat > "$iso_work/hardware-configuration.nix" <<EOF_HARDWARE
{ ... }: {
  imports = [ ./hardware-detected.nix ];
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/$offline_root_uuid";
    fsType = "$filesystem";
  };
  swapDevices = [ ];
EOF_HARDWARE
  if [[ $firmware == uefi ]]; then
    cat >> "$iso_work/hardware-configuration.nix" <<EOF_EFI
  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/$efi_uuid";
    fsType = "vfat";
  };
EOF_EFI
  fi
  printf '}\n' >> "$iso_work/hardware-configuration.nix"
}

offline_build_system() {
  local jobs cores
  read -r jobs cores < <(choose_install_parallelism)
  echo 'Building the selected configuration using only the installation medium...'
  if ! offline_system=$(nix build --print-build-logs --no-link --no-write-lock-file --print-out-paths \
    --max-jobs "$jobs" --cores "$cores" \
    "path:$iso_work#nixosConfigurations.$install_host.config.system.build.toplevel"); then
    die 'offline payload cannot build this configuration; no disk changes were made. Rebuild the ISO with the required hardware/packages.'
  fi
  [[ $offline_system == /nix/store/* && $offline_system != *$'\n'* && -x $offline_system/bin/switch-to-configuration ]] \
    || die 'offline build did not produce exactly one NixOS system'
}

offline_install_system() {
  nixos-install --root "$target_root" --system "$offline_system" \
    --no-root-passwd --no-channel-copy "${bootstrap_cache[@]}"
  # Preserve all locked input sources on the new disk, including transitive
  # flakes. A GC-rooted profile keeps the installed /etc/nixos references valid.
  nix-env --store "$target_root" --option substituters '' \
    --extra-substituters 'auto?trusted=1' \
    -p "$target_root/nix/var/nix/profiles/ryoku-offline-sources" \
    --set "$RYOKU_INSTALL_OFFLINE"
}
