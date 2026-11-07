set -euo pipefail

source_ref="${RYOKU_INSTALL_SOURCE:-github:Ryoku-dev/Ryoku-on-NixOS/main}"
source_explicit=0
flake_arg="/etc/nixos"
assume_yes=0
dry_run=0
manual_recovery=0
compositor=""
browser=""
shell_choice=""
apps_spec=""
apps_set=0
default_apps="prompt,fastfetch,yazi,cli-tools,pavucontrol,songrec,openrgb,upscale,gamescope,gamemode,mangohud,vm,docker,mise"

iso_mode=0
install_disk=""
validated_disk_identity=""
filesystem=""
target_hostname=""
target_username=""
confirm_disk=""
firmware_choice="auto"
target_timezone=""
target_locale=""
target_keyboard=""
kernel_choice="default"
config_mode="ryoku"
import_flake=""
import_host=""
gpu_spec="auto"
gpu_vendors=()
nvidia_branch="stable"
nvidia_open=true
target_root="${RYOKU_INSTALL_TARGET_ROOT:-/mnt}"
iso_work=""
iso_config_templates="@ISO_CONFIGS@"

# nixos-install builds into the target store, so the disk must hold the whole
# fresh closure plus everything Ryoku compiles locally. Measured with a dry
# run of the generated configuration against an empty store: about 22 GiB is
# substituted from cache.nixos.org and roughly 700 derivations are built
# (Ryoku's own package set is not cached), before transient build trees and
# space for the first update. Smaller disks are wiped and then run out of
# space in the middle of nixos-install.
min_install_disk_gib=40
min_install_disk_bytes=$((min_install_disk_gib * 1024 * 1024 * 1024))

trusted_root_path="@TRUSTED_ROOT_PATH@:/run/current-system/sw/bin:/run/wrappers/bin"

run_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
    return
  fi

  if [ ! -x /run/wrappers/bin/sudo ]; then
    echo "ryoku-install: NixOS sudo wrapper is unavailable at /run/wrappers/bin/sudo" >&2
    exit 1
  fi

  /run/wrappers/bin/sudo \
    @COREUTILS_ENV@ \
    "PATH=$trusted_root_path" \
    "$@"
}

die() {
  printf 'ryoku-install: %s\n' "$*" >&2
  exit 1
}

choose_install_parallelism() {
  local mem_kib jobs cores

  mem_kib="$(awk '/^MemTotal:/ { print $2; exit }' /proc/meminfo 2>/dev/null || true)"
  case "$mem_kib" in
    ''|*[!0-9]*) mem_kib=0 ;;
  esac

  # Building the full Ryoku closure can include memory-heavy Rust, Elixir and
  # C++ derivations. Keep low-memory installs deliberately conservative so the
  # kernel does not OOM-kill nixos-install halfway through an otherwise valid
  # installation. More capable machines still get modest parallelism.
  if [ "$mem_kib" -gt 0 ] && [ "$mem_kib" -lt 12582912 ]; then
    jobs=1
    cores=2
  elif [ "$mem_kib" -gt 0 ] && [ "$mem_kib" -lt 25165824 ]; then
    jobs=2
    cores=2
  else
    jobs=4
    cores=0
  fi

  printf '%s %s\n' "$jobs" "$cores"
}

nix_quote() {
  python3 - "$1" <<'PY_QUOTE'
import json
import sys

value = sys.argv[1]
if "\x00" in value or "\n" in value or "\r" in value:
    raise SystemExit("ryoku-install: Nix string values must be single-line")
print(json.dumps(value).replace("${", "\\${"))
PY_QUOTE
}

# The live ISO exposes its embedded Ryoku tree through /etc/ryoku/source, which
# resolves through /etc/static and is not a valid target-flake input during
# pure evaluation. Persist that source beside the installed flake and use a
# relative path instead. Clean release ISOs still keep their exact Git revision.
target_source_ref_for_install() {
  local ref
  if [ "$source_explicit" -eq 1 ]; then
    ref="$source_ref"
  else
    ref="${RYOKU_INSTALL_TARGET_SOURCE:-$source_ref}"
  fi
  case "$ref" in
    path:/etc/ryoku/source|path:/etc/static/ryoku/source)
      printf '%s\n' 'path:./ryoku-source'
      ;;
    *)
      printf '%s\n' "$ref"
      ;;
  esac
}

# Installed flakes follow the branch the live ISO was built from, so a later
# `nix flake update` moves along that branch. flake.lock still pins the exact
# revision tested by the image. Dirty development ISOs have no Git revision and
# keep following the persisted local copy beside flake.nix.
target_track_ref_for_install() {
  if [ "$(target_source_ref_for_install)" = "path:./ryoku-source" ]; then
    printf '%s\n' 'path:./ryoku-source'
  else
    printf '%s\n' "${RYOKU_INSTALL_TARGET_TRACK:-github:Ryoku-dev/Ryoku-on-NixOS/main}"
  fi
}

valid_hostname() {
  [[ "$1" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]
}

valid_username() {
  [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

valid_timezone() {
  [[ "$1" =~ ^[A-Za-z0-9_+.-]+(/[A-Za-z0-9_+.-]+)*$ ]] && [[ "$1" != *".."* ]]
}

valid_locale() {
  [[ "$1" =~ ^[A-Za-z0-9_.@-]+$ ]]
}

valid_keyboard() {
  [[ "$1" =~ ^[A-Za-z0-9_,+-]+$ ]]
}


validate_import_flake() {
  local root="$1" candidate
  [ -d "$root" ] || die "import flake path is not a directory: $root"
  [ -f "$root/flake.nix" ] || die "import flake must contain flake.nix at its root"
  [ -f "$root/hardware-configuration.nix" ] || die "import flake must contain root hardware-configuration.nix so the installer can replace machine-specific hardware safely"

  while IFS= read -r -d '' candidate; do
    [ "$candidate" = "$root/hardware-configuration.nix" ] && continue
    if grep -Eq '(^|[^A-Za-z])(fileSystems\.|swapDevices[[:space:]]*=|/dev/disk/by-(uuid|partuuid)|UUID=)' "$candidate"; then
      die "import flake contains filesystem/disk declarations outside hardware-configuration.nix: ${candidate#"$root"/}"
    fi
  done < <(find "$root" -type f -name '*.nix' -print0)
}

resolve_import_host() {
  local root="$1" show

  # An explicit host is validated by the exact nixosConfigurations.<host>
  # preflight evaluation after the staged flake is locked. Avoid resolving the
  # imported flake twice (and requiring network access before lock preflight).
  if [ -n "$import_host" ]; then
    return 0
  fi

  if ! show="$(nix flake show "path:$root" --json --no-write-lock-file 2>/dev/null)"; then
    die "could not inspect import flake to discover its NixOS host"
  fi
  mapfile -t import_hosts < <(printf '%s\n' "$show" | jq -r '.nixosConfigurations // {} | keys[]' 2>/dev/null || true)

  case "${#import_hosts[@]}" in
    1) import_host="${import_hosts[0]}" ;;
    0) die "import flake exposes no nixosConfigurations; fix the flake before importing it" ;;
    *) die "import flake exposes multiple NixOS hosts; pass --import-host NAME" ;;
  esac
}

render_import_target() {
  local outdir="$1" root source_for_input
  root="$(readlink -f "$import_flake")"
  validate_import_flake "$root"
  resolve_import_host "$root"

  mkdir -p "$outdir"
  cp -a "$root/." "$outdir/"
  chmod -R u+w "$outdir"

  source_for_input="$(target_source_ref_for_install)"
  python3 @INSTALL_EDIT@ --input-only "$outdir/flake.nix" "$source_for_input"
}

detect_gpu_vendors() {
  command -v lspci >/dev/null 2>&1 || return 0

  lspci -Dn 2>/dev/null | awk '
    $2 ~ /^(0300|0302|0380):$/ {
      split($3, id, ":")
      vendor = tolower(id[1])
      if (vendor == "10de") print "nvidia"
      else if (vendor == "1002") print "amd"
      else if (vendor == "8086") print "intel"
    }
  ' | awk '!seen[$0]++'
}

resolve_nvidia_policy() {
  local info has_kepler=0 has_legacy580=0 has_modern=0

  # Reuse Ryoku's existing generation policy: Kepler uses 470, Maxwell/Pascal/
  # Volta use NVIDIA's final compatible 580 branch, and Turing+ uses the current
  # stable branch with the open kernel modules. pciutils' database exposes the
  # GK/GM/GP/GV chip prefixes even when the marketing name varies by laptop/OEM.
  info="$(lspci 2>/dev/null | grep -Ei 'VGA|3D|Display' | grep -i 'NVIDIA' || true)"
  if [ -z "$info" ]; then
    nvidia_branch="stable"
    nvidia_open=true
    return 0
  fi

  grep -Eq '(^|[^[:alnum:]])GK[0-9]+' <<< "$info" && has_kepler=1
  grep -Eq '(^|[^[:alnum:]])G(M|P|V)[0-9]+' <<< "$info" && has_legacy580=1
  if grep -Evq '(^|[^[:alnum:]])G(K|M|P|V)[0-9]+' <<< "$info"; then
    has_modern=1
  fi

  if [ "$has_kepler" -eq 1 ] && { [ "$has_legacy580" -eq 1 ] || [ "$has_modern" -eq 1 ]; }; then
    die "mixed Kepler and newer NVIDIA GPUs require manual driver configuration"
  fi

  if [ "$has_kepler" -eq 1 ]; then
    nvidia_branch="legacy_470"
    nvidia_open=false
  elif [ "$has_legacy580" -eq 1 ]; then
    nvidia_branch="legacy_580"
    nvidia_open=false
  else
    nvidia_branch="stable"
    nvidia_open=true
  fi
}

resolve_gpu_vendors() {
  local item
  local -A seen=()
  gpu_vendors=()

  if [ "$gpu_spec" = "auto" ]; then
    while IFS= read -r item; do
      [ -n "$item" ] || continue
      if [ -z "${seen[$item]+x}" ]; then
        gpu_vendors+=("$item")
        seen[$item]=1
      fi
    done < <(detect_gpu_vendors)
    return
  fi

  [ "$gpu_spec" = "none" ] && return

  IFS=',' read -r -a requested_gpus <<< "$gpu_spec"
  for item in "${requested_gpus[@]}"; do
    item="${item//[[:space:]]/}"
    case "$item" in
      nvidia|amd|intel) ;;
      *) die "invalid GPU vendor: $item (expected auto, none, nvidia, amd, intel, or a comma-separated hybrid set)" ;;
    esac
    if [ -z "${seen[$item]+x}" ]; then
      gpu_vendors+=("$item")
      seen[$item]=1
    fi
  done
}

canonical_whole_disk() {
  local dev="$1"
  local resolved type parent

  resolved="$(readlink -f "$dev" 2>/dev/null || true)"
  [ -n "$resolved" ] && [ -b "$resolved" ] || return 1

  type="$(lsblk -dnro TYPE "$resolved" 2>/dev/null || true)"
  if [ "$type" = "disk" ]; then
    printf '%s\n' "$resolved"
    return 0
  fi

  parent="$(lsblk -dnro PKNAME "$resolved" 2>/dev/null | head -n 1)"
  [ -n "$parent" ] || return 1
  printf '/dev/%s\n' "$parent"
}

detect_live_disk() {
  local mountpoint source disk

  for mountpoint in /iso /nix/.ro-store /run/rootfsbase /; do
    source="$(findmnt -nro SOURCE "$mountpoint" 2>/dev/null || true)"
    case "$source" in
      /dev/*)
        disk="$(canonical_whole_disk "$source" 2>/dev/null || true)"
        if [ -n "$disk" ]; then
          printf '%s\n' "$disk"
          return 0
        fi
        ;;
    esac
  done
}

disk_identity() {
  local disk="$1"
  local props wwn serial size model majmin

  props="$(udevadm info --query=property --name "$disk" 2>/dev/null || true)"
  wwn="$(sed -n 's/^ID_WWN_WITH_EXTENSION=//p; s/^ID_WWN=//p' <<< "$props" | head -n 1)"
  serial="$(sed -n 's/^ID_SERIAL=//p' <<< "$props" | head -n 1)"
  size="$(lsblk -bdnro SIZE "$disk" 2>/dev/null || true)"
  model="$(lsblk -dnro MODEL "$disk" 2>/dev/null | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' || true)"
  majmin="$(lsblk -dnro MAJ:MIN "$disk" 2>/dev/null || true)"

  [ -n "$size" ] && [ -n "$majmin" ] || return 1

  if [ -n "$wwn" ] || [ -n "$serial" ]; then
    printf 'wwn=%s|serial=%s|size=%s\n' "$wwn" "$serial" "$size"
  else
    printf 'dev=%s|model=%s|size=%s\n' "$majmin" "$model" "$size"
  fi
}

revalidate_install_disk() {
  local expected_path="$1"
  local expected_identity="$2"
  local current_identity

  validate_install_disk "$expected_path"
  [ "$install_disk" = "$expected_path" ] ||
    die "installation disk path changed before erase ($expected_path -> $install_disk)"

  current_identity="$(disk_identity "$install_disk" || true)"
  [ -n "$current_identity" ] ||
    die "could not re-identify $install_disk immediately before erase"

  [ "$current_identity" = "$expected_identity" ] ||
    die "installation disk identity changed before erase; refusing to wipe $install_disk"
}

validate_install_disk() {
  local disk="$1"
  local resolved type ro live_disk size mounts

  case "$disk" in
    /dev/*) ;;
    *) die "installation disk must be an absolute /dev path" ;;
  esac

  # Dry runs intentionally permit a synthetic /dev path so CI can exercise the
  # complete planning/config-generation path without a block device.
  if [ "$dry_run" -eq 1 ] && [ ! -b "$disk" ]; then
    install_disk="$disk"
    return 0
  fi

  resolved="$(readlink -f "$disk" 2>/dev/null || true)"
  [ -n "$resolved" ] && [ -b "$resolved" ] || die "$disk is not a block device"

  type="$(lsblk -dnro TYPE "$resolved" 2>/dev/null || true)"
  [ "$type" = "disk" ] || die "$resolved is not a whole disk"

  ro="$(lsblk -dnro RO "$resolved" 2>/dev/null || true)"
  [ "$ro" = "0" ] || die "$resolved is read-only"

  live_disk="$(detect_live_disk || true)"
  if [ -n "$live_disk" ] && [ "$resolved" = "$live_disk" ]; then
    die "refusing to erase the disk backing the live installer ($resolved)"
  fi

  size="$(lsblk -bdnro SIZE "$resolved" 2>/dev/null || true)"
  [ -n "$size" ] || die "could not determine the size of $resolved"
  if [ "$size" -lt "$min_install_disk_bytes" ]; then
    die "$resolved is smaller than the ${min_install_disk_gib} GiB minimum for a Ryoku installation"
  fi

  mounts="$(lsblk -nrpo MOUNTPOINTS "$resolved" 2>/dev/null | awk 'NF { print }')"
  if [ -n "$mounts" ]; then
    printf '%s\n' "ryoku-install: $resolved has mounted filesystems:" >&2
    printf '%s\n' "$mounts" >&2
    die "unmount them before installing"
  fi

  install_disk="$resolved"
}

choose_install_disk() {
  local live_disk path size model human choice
  local -a disks=()

  live_disk="$(detect_live_disk || true)"
  printf '\nInstallation disk\n'

  while IFS=$'\t' read -r path size model; do
    [ -n "$path" ] || continue
    [ "$path" = "$live_disk" ] && continue
    disks+=("$path")
    human="$(numfmt --to=iec --suffix=B "$size" 2>/dev/null || printf '%sB' "$size")"
    printf '  %d) %-16s %8s  %s\n' "${#disks[@]}" "$path" "$human" "${model:-Unknown disk}"
  done < <(
    lsblk -J -b -d -o PATH,SIZE,MODEL,TYPE,RO |
      jq -r --argjson min "$min_install_disk_bytes" '.blockdevices[] | select(.type == "disk" and (.ro == false or .ro == 0) and ((.size | tonumber) >= $min)) | [.path, (.size|tostring), (.model // "")] | @tsv'
  )

  [ "${#disks[@]}" -gt 0 ] || die "no writable installation disks found"

  while true; do
    printf 'Choose disk: '
    read -r choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#disks[@]}" ]; then
      install_disk="${disks[$((choice - 1))]}"
      return 0
    fi
    printf 'Invalid disk selection.\n' >&2
  done
}

partition_by_number() {
  local disk="$1" number="$2" part attempt
  for ((attempt = 0; attempt < 50; attempt++)); do
    part="$(lsblk -nrpo NAME,PARTN "$disk" 2>/dev/null | awk -v n="$number" '$2 == n { print $1; exit }')"
    if [ -n "$part" ]; then
      printf '%s\n' "$part"
      return 0
    fi
    sleep 0.1
  done
  return 1
}

render_iso_target() {
  local outdir="$1" firmware="$2" password_hash="$3"
  local apps_block="" gpu_block=""
  local nix_host nix_user nix_ryoku nix_nixpkgs nix_disk
  local nix_timezone nix_locale nix_keyboard nix_firmware
  local target_source_ref target_nixpkgs_ref

  target_source_ref="$(target_source_ref_for_install)"
  target_nixpkgs_ref="${RYOKU_INSTALL_NIXPKGS_SOURCE:-github:NixOS/nixpkgs/nixos-unstable}"

  nix_host="$(nix_quote "$target_hostname")"
  nix_user="$(nix_quote "$target_username")"
  nix_ryoku="$(nix_quote "$target_source_ref")"
  nix_nixpkgs="$(nix_quote "$target_nixpkgs_ref")"
  nix_disk="$(nix_quote "$install_disk")"
  nix_timezone="$(nix_quote "$target_timezone")"
  nix_locale="$(nix_quote "$target_locale")"
  nix_keyboard="$(nix_quote "$target_keyboard")"
  nix_firmware="$(nix_quote "$firmware")"
  nix_kernel="$(nix_quote "$kernel_choice")"

  if [ "${#selected_apps[@]}" -gt 0 ]; then
    apps_block="$(printf '    "%s"
' "${selected_apps[@]}")"
  fi
  if [ "${#gpu_vendors[@]}" -gt 0 ]; then
    gpu_block="$(printf '    "%s"
' "${gpu_vendors[@]}")"
  fi

  mkdir -p "$outdir"
  cp -a "$iso_config_templates/." "$outdir/"
  chmod -R u+w "$outdir"

  # Keep a moving branch URL in the installed flake so `nix flake update` can
  # advance it later; the lock step below pins the tested revision.
  python3 - "$outdir/flake.nix" "$(target_track_ref_for_install)" <<'PY_FLAKE'
import json
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
url = json.dumps(sys.argv[2]).replace("${", "\\${")
text, count = re.subn(
    r'(?m)^([ \t]*ryoku\.url[ \t]*=[ \t]*)"[^"\n]*";',
    lambda match: f"{match.group(1)}{url};",
    path.read_text(),
    count=1,
)
if count != 1:
    raise SystemExit("ryoku-install: flake template has no ryoku.url line")
path.write_text(text)
PY_FLAKE

  cat > "$outdir/install-values.nix" <<EOF_VALUES
# Generated by ryoku-install. Edit this file to change machine-specific choices.
{
  hostname = $nix_host;
  username = $nix_user;
  firmware = $nix_firmware;
  installDisk = $nix_disk;
  gpuVendors = [
$gpu_block
  ];
  nvidiaBranch = "${nvidia_branch}";
  nvidiaOpen = ${nvidia_open};

  timeZone = $nix_timezone;
  locale = $nix_locale;
  keyboardLayout = $nix_keyboard;
  kernel = $nix_kernel;

  compositor = "${compositor}";
  browser = "${browser}";
  shell = "${shell_choice}";
  optionalApps = [
$apps_block
  ];

  ryokuSource = $nix_ryoku;
  nixpkgsSource = $nix_nixpkgs;
}
EOF_VALUES
}

# Every binary cache nixos-install will use has to answer before the disk is
# erased. Otherwise substitution falls back to building, or fails, halfway
# through an installation that has already wiped the disk.
check_substituters() {
  local url
  for url in $(nix config show substituters 2>/dev/null || true); do
    case "$url" in
      http://*|https://*) ;;
      *) continue ;;
    esac
    if ! curl -fsS --connect-timeout 5 --max-time 10 -o /dev/null "${url%/}/nix-cache-info"; then
      die "binary cache ${url%/} did not answer. Check the network connection, then retry (in the guided installer: configure the network and start again). No disk changes were made"
    fi
  done
}

# "22.4" "GiB" -> whole MiB, rounded up.
plan_size_mib() {
  awk -v n="$1" -v u="$2" 'BEGIN {
    m = (u == "B") ? 1 / 1048576 : (u == "KiB") ? 1 / 1024 : (u == "MiB") ? 1 : (u == "GiB") ? 1024 : (u == "TiB") ? 1048576 : -1
    if (m < 0 || n !~ /^[0-9.]+$/) exit 1
    v = n * m
    printf "%d\n", (v == int(v)) ? v : int(v) + 1
  }'
}

# Ask Nix what installing the target would download and build on an empty
# disk, before that disk is touched. The live ISO's own store would hide paths
# the new system still needs, so the plan runs against a throwaway local store
# holding only the target's derivations. Only narinfo lookups go to the
# caches; nothing is downloaded or built.
plan_target_install() {
  local drv="$1" firmware="$2"
  local probe plan fetched builds=0 unpacked_mib=0 jobs cores
  local disk_bytes root_mib usable_mib need_mib build_mib esp_mib
  local -a heavy=()
  local name

  printf '\nPlanning the installation (what will be downloaded and built)...\n'
  probe="$iso_work/plan-store"
  if ! nix copy --no-check-sigs --derivation --to "local?root=$probe" "$drv" >/dev/null 2>&1 ||
     ! plan="$(nix build --dry-run --no-link --store "local?root=$probe" "$drv^*" 2>&1)"
  then
    chmod -R u+w "$probe" 2>/dev/null || true
    rm -rf "$probe"
    die "could not work out what the installation needs to download and build; check the network and retry. No disk changes were made"
  fi
  chmod -R u+w "$probe" 2>/dev/null || true
  rm -rf "$probe"

  builds="$(sed -nE 's/^these ([0-9]+) derivations will be built.*/\1/p; s/^this derivation will be built.*/1/p' <<< "$plan" | head -n 1)"
  builds="${builds:-0}"
  fetched="$(sed -nE 's/.*will be fetched \(.* download, ([0-9.]+) ([KMGT]?i?B) unpacked\).*/\1 \2/p' <<< "$plan" | head -n 1)"
  if [ -n "$fetched" ]; then
    # shellcheck disable=SC2086 # "<number> <unit>"
    unpacked_mib="$(plan_size_mib $fetched)" ||
      die "could not read the download size from the installation plan; no disk changes were made"
  fi

  # Compiler-heavy packages that are missing from every configured cache.
  while IFS= read -r name; do
    heavy+=("$name")
  done < <(
    grep -oE '/nix/store/[a-z0-9]{32}-[^ ]+\.drv' <<< "$plan" |
      sed -E 's|^/nix/store/[a-z0-9]{32}-||; s|\.drv$||' |
      grep -E '^(hyprland|niri|quickshell|ryoku-mango|xwayland-satellite|chromium|firefox|nodejs|linux|nvidia-x11|waifu2x-ncnn-vulkan|qtwebengine|qtbase|rustc|llvm|gcc)-[0-9][0-9A-Za-z.+]*$' |
      sort -u
  )

  read -r jobs cores <<EOF
$(choose_install_parallelism)
EOF

  # Everything is unpacked into the target store and stays there, plus the
  # outputs of local builds (measured about 1.2 GiB for a full source build)
  # and the build trees of the builds running at the same time.
  build_mib=0
  if [ "$builds" -gt 0 ]; then
    build_mib=2048
    if [ "${#heavy[@]}" -gt 0 ]; then
      [ "${#heavy[@]}" -lt "$jobs" ] && jobs="${#heavy[@]}"
      build_mib=$((build_mib + jobs * 3072))
    fi
  fi
  need_mib=$((unpacked_mib + build_mib + 4096))

  esp_mib=3
  [ "$firmware" = "uefi" ] && esp_mib=1025
  if [ -b "$install_disk" ]; then
    disk_bytes="$(lsblk -bdnro SIZE "$install_disk" 2>/dev/null || true)"
  else
    disk_bytes=""
  fi
  case "$disk_bytes" in
    ''|*[!0-9]*) die "could not determine the size of $install_disk" ;;
  esac
  root_mib=$((disk_bytes / 1048576 - esp_mib))
  # ext4 keeps 5% for root; Nix builds run as unprivileged build users.
  usable_mib=$((root_mib * 95 / 100))

  printf 'Download from binary caches: %s MiB unpacked\n' "$unpacked_mib"
  printf 'Packages built on this machine: %s\n' "$builds"
  printf 'Estimated space needed: %s GiB of about %s GiB usable on %s\n' \
    "$(( (need_mib + 1023) / 1024 ))" "$((usable_mib / 1024))" "$install_disk"

  if [ "${#heavy[@]}" -gt 0 ]; then
    printf '\nThese large packages are not in any configured binary cache and will be\n'
    printf 'compiled on this machine during the installation. That can take a long\n'
    printf 'time on a slow CPU or with little memory:\n'
    printf '  %s\n' "${heavy[@]}"
  fi

  if [ "$need_mib" -gt "$usable_mib" ]; then
    die "$install_disk is too small for this installation: it needs about $(( (need_mib + 1023) / 1024 )) GiB in the root filesystem but only about $((usable_mib / 1024)) GiB would be usable. Use a larger disk or select fewer optional apps. No disk changes were made"
  fi
}

install_iso() {
  local firmware password_hash typed
  local root_part boot_part
  local target_source_ref target_nixpkgs_ref

  if [ -z "$install_disk" ]; then
    if [ "$assume_yes" -eq 1 ]; then
      die "--iso --yes requires --disk DEVICE"
    fi
    choose_install_disk
  fi
  validate_install_disk "$install_disk"
  if [ "$dry_run" -eq 0 ]; then
    validated_disk_identity="$(disk_identity "$install_disk" || true)"
    [ -n "$validated_disk_identity" ] || die "could not identify $install_disk for destructive-install safety"
  fi

  if [ -z "$filesystem" ]; then
    if [ "$assume_yes" -eq 1 ]; then
      filesystem="ext4"
    else
      printf '\nFilesystem\n  1) ext4   (default)\n  2) btrfs\nChoose [1]: '
      read -r answer
      case "$answer" in
        ""|1) filesystem="ext4" ;;
        2) filesystem="btrfs" ;;
        *) die "invalid filesystem selection" ;;
      esac
    fi
  fi
  case "$filesystem" in
    ext4|btrfs) ;;
    *) die "invalid filesystem: $filesystem" ;;
  esac

  if [ -z "$target_hostname" ]; then
    if [ "$assume_yes" -eq 1 ]; then
      target_hostname="ryoku"
    else
      printf '\nHostname [ryoku]: '
      read -r target_hostname
      target_hostname="${target_hostname:-ryoku}"
    fi
  fi
  valid_hostname "$target_hostname" || die "invalid hostname: $target_hostname"

  if [ -z "$target_username" ]; then
    if [ "$assume_yes" -eq 1 ]; then
      target_username="ryoku"
    else
      printf 'Username [ryoku]: '
      read -r target_username
      target_username="${target_username:-ryoku}"
    fi
  fi
  valid_username "$target_username" || die "invalid username: $target_username"

  if [ -z "$target_timezone" ]; then
    if [ "$assume_yes" -eq 1 ]; then
      target_timezone="UTC"
    else
      printf 'Timezone [UTC]: '
      read -r target_timezone
      target_timezone="${target_timezone:-UTC}"
    fi
  fi
  valid_timezone "$target_timezone" || die "invalid timezone: $target_timezone"
  [ -e "@ZONEINFO_ROOT@/$target_timezone" ] || die "unknown timezone: $target_timezone"

  if [ -z "$target_locale" ]; then
    if [ "$assume_yes" -eq 1 ]; then
      target_locale="en_US.UTF-8"
    else
      printf 'Locale [en_US.UTF-8]: '
      read -r target_locale
      target_locale="${target_locale:-en_US.UTF-8}"
    fi
  fi
  valid_locale "$target_locale" || die "invalid locale: $target_locale"

  if [ -z "$target_keyboard" ]; then
    if [ "$assume_yes" -eq 1 ]; then
      target_keyboard="us"
    else
      printf 'Keyboard layout [us]: '
      read -r target_keyboard
      target_keyboard="${target_keyboard:-us}"
    fi
  fi
  valid_keyboard "$target_keyboard" || die "invalid keyboard layout: $target_keyboard"

  case "$kernel_choice" in
    default|latest|zen) ;;
    *) die "invalid kernel: $kernel_choice (expected default, latest, or zen)" ;;
  esac

  case "$config_mode" in
    ryoku) ;;
    import)
      [ -n "$import_flake" ] || die "--config-mode import requires --import-flake PATH"
      ;;
    *) die "invalid configuration mode: $config_mode (expected ryoku or import)" ;;
  esac

  resolve_gpu_vendors
  for item in "${gpu_vendors[@]}"; do
    if [ "$item" = "nvidia" ]; then
      resolve_nvidia_policy
      break
    fi
  done

  case "$firmware_choice" in
    auto)
      if [ -d /sys/firmware/efi ]; then firmware="uefi"; else firmware="bios"; fi
      ;;
    uefi|bios) firmware="$firmware_choice" ;;
    *) die "invalid firmware mode: $firmware_choice" ;;
  esac

  if [ "$config_mode" = "import" ]; then
    # Input-only import mode owns its users and authentication policy.
    password_hash="*"
  elif [ "$dry_run" -eq 1 ]; then
    password_hash="*"
  elif [ -n "${RYOKU_INSTALL_PASSWORD_HASH:-}" ]; then
    password_hash="$RYOKU_INSTALL_PASSWORD_HASH"
  elif [ "$assume_yes" -eq 1 ]; then
    die "unattended ISO installation requires RYOKU_INSTALL_PASSWORD_HASH"
  else
    local password_a password_b
    while true; do
      printf 'Password for %s: ' "$target_username"
      read -r -s password_a
      printf '\nConfirm password: '
      read -r -s password_b
      printf '\n'
      [ -n "$password_a" ] || { printf 'Password cannot be empty.\n' >&2; continue; }
      [ "$password_a" = "$password_b" ] || { printf 'Passwords do not match.\n' >&2; continue; }
      password_hash="$(printf '%s' "$password_a" | mkpasswd -m yescrypt -s)"
      unset password_a password_b
      break
    done
  fi

  target_source_ref="$(target_source_ref_for_install)"
  target_nixpkgs_ref="${RYOKU_INSTALL_NIXPKGS_SOURCE:-github:NixOS/nixpkgs/nixos-unstable}"

  # Arm cleanup as soon as the staging tree exists. Preflight intentionally
  # happens before the destructive confirmation, so failures here must still
  # remove the temporary tree without relying on later partitioning setup.
  # shellcheck disable=SC2329 # invoked indirectly through EXIT/INT/TERM traps
  iso_cleanup() {
    local status=$?
    trap - EXIT INT TERM
    if [ "$status" -ne 0 ] && [ "${disk_modified:-0}" -eq 1 ]; then
      printf 'ryoku-install: INSTALLATION DID NOT COMPLETE. %s was already repartitioned and is not a bootable system.\n' "$install_disk" >&2
      printf 'ryoku-install: Do not reboot into it. Fix the error above and run the installer again; the disk contents before this run cannot be recovered by the installer.\n' >&2
    fi
    if findmnt -rn --mountpoint "$target_root" >/dev/null 2>&1; then
      if ! run_root umount -R "$target_root"; then
        printf 'ryoku-install: WARNING: could not unmount %s after installation stopped.\n' "$target_root" >&2
        printf 'ryoku-install: Inspect with findmnt -R %s before manually recovering.\n' "$target_root" >&2
        [ "$status" -ne 0 ] || status=1
      fi
    fi
    if [ -n "${iso_work:-}" ]; then
      chmod -R u+w "$iso_work" 2>/dev/null || true
      rm -rf "$iso_work" 2>/dev/null || true
    fi
    exit "$status"
  }

  iso_work="$(mktemp -d)"
  trap iso_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  if [ "$config_mode" = "import" ]; then
    render_import_target "$iso_work"
  else
    render_iso_target "$iso_work" "$firmware" "$password_hash"
  fi

  printf '\nRyoku NixOS full installation\n'
  printf '%s\n' '────────────────────────────────────────'
  printf 'Disk       %s\n' "$install_disk"
  printf 'Filesystem %s\n' "$filesystem"
  printf 'Firmware   %s\n' "$firmware"
  printf 'Hostname   %s\n' "$target_hostname"
  printf 'User       %s\n' "$target_username"
  printf 'Timezone   %s\n' "$target_timezone"
  printf 'Locale     %s\n' "$target_locale"
  printf 'Keyboard   %s\n' "$target_keyboard"
  printf 'Kernel     %s\n' "$kernel_choice"
  printf 'Config     %s\n' "$config_mode"
  if [ "$config_mode" = "import" ]; then
    printf 'Import     %s#%s\n' "$import_flake" "$import_host"
  fi
  printf 'GPU        %s\n' "$(IFS=,; echo "${gpu_vendors[*]:-auto/none}")"
  if [[ " ${gpu_vendors[*]} " == *" nvidia "* ]]; then
    printf 'NVIDIA     %s (%s modules)\n' "$nvidia_branch" "$([ "$nvidia_open" = true ] && printf open || printf proprietary)"
  fi
  printf 'WM         %s\n' "$compositor"
  printf 'Browser    %s\n' "$browser"
  printf 'Shell      %s\n' "$shell_choice"
  printf 'Ryoku      %s\n' "$target_source_ref"
  if [ "$config_mode" = "ryoku" ]; then
    printf 'Follows    %s\n' "$(target_track_ref_for_install)"
  fi
  printf 'Nixpkgs    %s\n' "$target_nixpkgs_ref"

  if [ "$dry_run" -eq 1 ]; then
    printf '\nGenerated flake.nix:\n'
    cat "$iso_work/flake.nix"
    if [ "$config_mode" = "ryoku" ]; then
      printf '\nGenerated configuration.nix:\n'
      cat "$iso_work/configuration.nix"
      printf '\nGenerated install-values.nix:\n'
      cat "$iso_work/install-values.nix"
    else
      printf '\nImported configuration is otherwise unchanged. hardware-configuration.nix is regenerated only during a real install.\n'
    fi
    trap - EXIT INT TERM
    rm -rf "$iso_work"
    iso_work=""
    printf '\nDry run complete. No disks or files were changed.\n'
    return 0
  fi

  if findmnt -rn --mountpoint "$target_root" >/dev/null 2>&1; then
    die "$target_root is already mounted; an earlier installation may be incomplete. Inspect with findmnt -R $target_root before recovering. The installer will not unmount or erase it automatically"
  fi

  # Resolve every flake input before asking to erase the target disk. A missing
  # network route or unavailable upstream must never leave the machine wiped.
  if [ "$target_source_ref" = "path:./ryoku-source" ]; then
    [ -e /etc/ryoku/source ] || die "embedded Ryoku source is missing from the live ISO"
    mkdir -p "$iso_work/ryoku-source"
    cp -a /etc/ryoku/source/. "$iso_work/ryoku-source/"
    chmod -R u+w "$iso_work/ryoku-source"
  fi

  local install_host="ryoku"
  if [ "$config_mode" = "import" ]; then
    install_host="$import_host"
  fi

  echo "@@RYOKU_STEP lock"
  local -a lock_args=(nix flake lock "path:$iso_work")
  # The generated Ryoku configuration deliberately pins both installer inputs.
  # An imported flake keeps the user's nixpkgs and other inputs untouched.
  if [ "$config_mode" = "ryoku" ]; then
    lock_args+=(--override-input nixpkgs "$target_nixpkgs_ref")
    if [ "$target_source_ref" != "path:./ryoku-source" ]; then
      lock_args+=(--override-input ryoku "$target_source_ref")
    fi
  fi
  if ! "${lock_args[@]}"; then
    die "flake input resolution failed before disk changes; check the network and input references, then retry"
  fi

  echo "@@RYOKU_STEP validate"
  local target_drv
  if ! target_drv="$(nix eval --raw \
    "path:$iso_work#nixosConfigurations.$install_host.config.system.build.toplevel.drvPath")"
  then
    die "target NixOS configuration does not evaluate; no disk changes were made"
  fi

  # Evaluation alone cannot expose an out-of-tree kernel module that fails at
  # compile time. On NVIDIA targets, realize the combined kernel module tree
  # before the destructive confirmation. This catches driver/kernel ABI
  # breakage while the installation disk is still completely untouched.
  if [[ " ${gpu_vendors[*]} " == *" nvidia "* ]]; then
    printf '\nValidating NVIDIA kernel modules against the selected kernel...\n'
    if ! nix build \
      --no-link \
      --no-write-lock-file \
      "path:$iso_work#nixosConfigurations.$install_host.config.system.modulesTree"
    then
      die "NVIDIA kernel-module preflight failed before disk changes; retry with --kernel default or another NVIDIA-compatible kernel"
    fi
  fi

  check_substituters
  plan_target_install "$target_drv" "$firmware"

  printf '\n%s\n' "WARNING: ALL DATA ON $install_disk WILL BE PERMANENTLY ERASED."
  if [ "$assume_yes" -eq 1 ]; then
    [ "$confirm_disk" = "$install_disk" ] || {
      die "--iso --yes requires --confirm-disk $install_disk"
    }
  else
    printf 'Type the exact disk path (%s) to continue: ' "$install_disk"
    read -r typed
    if [ "$typed" != "$install_disk" ]; then
      trap - EXIT INT TERM
      rm -rf "$iso_work"
      iso_work=""
      printf 'Cancelled. Nothing was changed.\n'
      return 0
    fi
  fi

  # Re-run every disk safety check after the destructive confirmation and
  # compare the underlying hardware identity. A hotplug/re-enumeration must
  # never let a reused /dev path point wipefs at a different disk.
  revalidate_install_disk "$install_disk" "$validated_disk_identity"

  # Global on purpose: the EXIT trap reads it after this function's frame.
  # From here on the disk is no longer in its original state: failures must
  # say so (see iso_cleanup).
  disk_modified=1
  echo "@@RYOKU_STEP partition"
  run_root wipefs -af "$install_disk"
  run_root parted -s "$install_disk" mklabel gpt

  if [ "$firmware" = "uefi" ]; then
    run_root parted -s -a optimal "$install_disk" mkpart ESP fat32 1MiB 1025MiB
    run_root parted -s "$install_disk" set 1 esp on
    run_root parted -s -a optimal "$install_disk" mkpart primary 1025MiB 100%
  else
    run_root parted -s -a optimal "$install_disk" mkpart BIOSBOOT 1MiB 3MiB
    run_root parted -s "$install_disk" set 1 bios_grub on
    run_root parted -s -a optimal "$install_disk" mkpart primary 3MiB 100%
  fi

  run_root partprobe "$install_disk"
  run_root udevadm settle

  boot_part="$(partition_by_number "$install_disk" 1 || true)"
  root_part="$(partition_by_number "$install_disk" 2 || true)"
  [ -n "$root_part" ] || die "root partition did not appear after partitioning"
  [ -n "$boot_part" ] || die "boot partition did not appear after partitioning"

  echo "@@RYOKU_STEP filesystems"
  if [ "$filesystem" = "ext4" ]; then
    run_root mkfs.ext4 -F -L nixos "$root_part"
  else
    run_root mkfs.btrfs -f -L nixos "$root_part"
  fi

  if [ "$firmware" = "uefi" ]; then
    run_root mkfs.fat -F 32 -n EFI "$boot_part"
  fi

  run_root mkdir -p "$target_root"
  run_root mount "$root_part" "$target_root"
  if [ "$firmware" = "uefi" ]; then
    run_root mkdir -p "$target_root/boot"
    # nixos-generate-config copies these options into hardware-configuration.
    # The default vfat umask leaves the ESP, and systemd-boot's random seed on
    # it, world-readable; bootctl reports that as a security hole.
    run_root mount -o umask=077 "$boot_part" "$target_root/boot"
  fi

  echo "@@RYOKU_STEP configuration"
  run_root mkdir -p "$target_root/etc/nixos"
  run_root nixos-generate-config --root "$target_root" --show-hardware-config > "$iso_work/hardware-configuration.nix"
  run_root cp -a "$iso_work/." "$target_root/etc/nixos/"
  # The staging tree belongs to the live `nixos` user. `cp -a` would preserve
  # that numeric ownership into the installed system, making /etc/nixos
  # writable by the first UID 1000 account. System configuration stays root-owned.
  run_root chown -R root:root "$target_root/etc/nixos"

  if [ "$config_mode" = "ryoku" ]; then
    # Password hashes are credentials too. Keep them out of flake source and the
    # world-readable Nix store; NixOS reads this root-only file on activation.
    local password_file="$iso_work/user-password.hash"
    (umask 077; printf '%s\n' "$password_hash" > "$password_file")
    run_root mkdir -p "$target_root/etc/ryoku"
    run_root install -m 0600 -o root -g root "$password_file" \
      "$target_root/etc/ryoku/user-password.hash"
  fi

  echo "@@RYOKU_STEP install"
  local install_jobs install_cores
  read -r install_jobs install_cores <<EOF
$(choose_install_parallelism)
EOF
  printf 'Ryoku installer: nix build parallelism: %s job(s), %s core(s) per job\n' \
    "$install_jobs" "$install_cores"
  run_root nixos-install \
    --max-jobs "$install_jobs" \
    --cores "$install_cores" \
    --root "$target_root" \
    --flake "path:$target_root/etc/nixos#$install_host" \
    --no-root-passwd

  echo "@@RYOKU_STEP finalize"
  run_root sync
  run_root umount -R "$target_root"

  disk_modified=0
  trap - EXIT INT TERM
  rm -rf "$iso_work"
  iso_work=""

  echo "@@RYOKU_DONE"
  printf '\nRyoku installation complete.\n'
  printf 'Remove the installation media and reboot into %s.\n' "$target_hostname"
}

usage() {
  cat <<'EOF'
Usage:
  ryoku-install-backend [options]

Options:
  --flake PATH[#HOST]   NixOS flake to configure (default: /etc/nixos)
  --source REF          Ryoku flake reference
  --compositor NAME     Initial compositor: hyprland, niri, or mango
  --browser NAME        Browser: chromium or firefox
  --shell NAME          Interactive shell: fish or zsh
  --apps CSV            Optional app IDs, comma-separated; use none for empty
  --iso                 Install a fresh NixOS + Ryoku system to a disk
  --disk DEVICE         Whole target disk for --iso
  --filesystem TYPE     ext4 or btrfs (default: ext4)
  --hostname NAME       Target hostname for --iso (default: ryoku)
  --username NAME       Target user for --iso (default: ryoku)
  --timezone ZONE       Target timezone (default: UTC)
  --locale LOCALE       Target locale (default: en_US.UTF-8)
  --keyboard LAYOUT     XKB keyboard layout (default: us)
  --kernel NAME         default, latest, or zen
  --config-mode MODE    ryoku or import (default: ryoku)
  --import-flake PATH   Existing flake directory for advanced import mode
  --import-host NAME    NixOS host from imported flake; auto when exactly one exists
  --gpu VENDORS         auto, none, or comma-separated nvidia,amd,intel
  --firmware MODE       auto, uefi, or bios (default: auto)
  --confirm-disk DEVICE Required with --iso --yes; must exactly match --disk
  --dry-run             Show proposed changes without writing them
  --manual-recovery     Continue after restoring a failed install's backup by hand
  -y, --yes             Skip non-destructive prompts; disk confirmation still required
  -h, --help            Show this help
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --flake)
      [ "$#" -ge 2 ] || {
        echo "ryoku-install: --flake requires a value" >&2
        exit 2
      }
      flake_arg="$2"
      shift 2
      ;;
    --source)
      [ "$#" -ge 2 ] || {
        echo "ryoku-install: --source requires a value" >&2
        exit 2
      }
      source_ref="$2"
      source_explicit=1
      shift 2
      ;;
    --compositor)
      [ "$#" -ge 2 ] || {
        echo "ryoku-install: --compositor requires a value" >&2
        exit 2
      }
      compositor="$2"
      shift 2
      ;;
    --browser)
      [ "$#" -ge 2 ] || {
        echo "ryoku-install: --browser requires a value" >&2
        exit 2
      }
      browser="$2"
      shift 2
      ;;
    --shell)
      [ "$#" -ge 2 ] || {
        echo "ryoku-install: --shell requires a value" >&2
        exit 2
      }
      shell_choice="$2"
      shift 2
      ;;
    --apps)
      [ "$#" -ge 2 ] || {
        echo "ryoku-install: --apps requires a value" >&2
        exit 2
      }
      apps_spec="$2"
      apps_set=1
      shift 2
      ;;
    --iso)
      iso_mode=1
      shift
      ;;
    --disk)
      [ "$#" -ge 2 ] || die "--disk requires a value"
      install_disk="$2"
      shift 2
      ;;
    --filesystem)
      [ "$#" -ge 2 ] || die "--filesystem requires a value"
      filesystem="$2"
      shift 2
      ;;
    --hostname)
      [ "$#" -ge 2 ] || die "--hostname requires a value"
      target_hostname="$2"
      shift 2
      ;;
    --username)
      [ "$#" -ge 2 ] || die "--username requires a value"
      target_username="$2"
      shift 2
      ;;
    --timezone)
      [ "$#" -ge 2 ] || die "--timezone requires a value"
      target_timezone="$2"
      shift 2
      ;;
    --locale)
      [ "$#" -ge 2 ] || die "--locale requires a value"
      target_locale="$2"
      shift 2
      ;;
    --keyboard)
      [ "$#" -ge 2 ] || die "--keyboard requires a value"
      target_keyboard="$2"
      shift 2
      ;;
    --kernel)
      [ "$#" -ge 2 ] || die "--kernel requires a value"
      kernel_choice="$2"
      shift 2
      ;;
    --config-mode)
      [ "$#" -ge 2 ] || die "--config-mode requires a value"
      config_mode="$2"
      shift 2
      ;;
    --import-flake)
      [ "$#" -ge 2 ] || die "--import-flake requires a value"
      import_flake="$2"
      shift 2
      ;;
    --import-host)
      [ "$#" -ge 2 ] || die "--import-host requires a value"
      import_host="$2"
      shift 2
      ;;
    --gpu)
      [ "$#" -ge 2 ] || die "--gpu requires a value"
      gpu_spec="$2"
      shift 2
      ;;
    --firmware)
      [ "$#" -ge 2 ] || die "--firmware requires a value"
      firmware_choice="$2"
      shift 2
      ;;
    --confirm-disk)
      [ "$#" -ge 2 ] || die "--confirm-disk requires a value"
      confirm_disk="$2"
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --manual-recovery)
      manual_recovery=1
      shift
      ;;
    -y|--yes)
      assume_yes=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ryoku-install: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$compositor" in
  ""|hyprland|niri|mango) ;;
  *)
    echo "ryoku-install: invalid compositor: $compositor" >&2
    exit 2
    ;;
esac

case "$browser" in
  ""|chromium|firefox) ;;
  *)
    echo "ryoku-install: invalid browser: $browser" >&2
    exit 2
    ;;
esac

if [ -z "$compositor" ]; then
  if [ "$assume_yes" -ne 1 ] && [ -t 0 ]; then
    printf '\nInitial compositor\n'
    printf '  1) Hyprland  (Ryoku default)\n'
    printf '  2) niri      (scrollable tiling)\n'
    printf '  3) MangoWM   (dynamic tiling, Ryoku Nix supported)\n'
    printf 'Choose [1]: '
    read -r answer
    case "$answer" in
      2) compositor="niri" ;;
      3) compositor="mango" ;;
      ""|1) compositor="hyprland" ;;
      *)
        echo "ryoku-install: invalid compositor selection" >&2
        exit 2
        ;;
    esac
  else
    compositor="hyprland"
  fi
fi

if [ -z "$browser" ]; then
  if [ "$assume_yes" -ne 1 ] && [ -t 0 ]; then
    printf '\nWeb browser\n'
    printf '  1) Chromium   (Ryoku NixOS default)\n'
    printf '  2) Firefox    (Gecko)\n'
    printf 'Choose [1]: '
    read -r answer
    case "$answer" in
      2) browser="firefox" ;;
      ""|1) browser="chromium" ;;
      *)
        echo "ryoku-install: invalid browser selection" >&2
        exit 2
        ;;
    esac
  else
    browser="chromium"
  fi
fi

case "$shell_choice" in
  ""|fish|zsh) ;;
  *)
    echo "ryoku-install: invalid shell: $shell_choice" >&2
    exit 2
    ;;
esac

if [ -z "$shell_choice" ]; then
  if [ "$assume_yes" -ne 1 ] && [ -t 0 ]; then
    printf '\nInteractive shell\n'
    printf '  1) Fish      (Ryoku default)\n'
    printf '  2) Zsh       (Ryoku integration, user .zshrc untouched)\n'
    printf 'Choose [1]: '
    read -r answer
    case "$answer" in
      2) shell_choice="zsh" ;;
      ""|1) shell_choice="fish" ;;
      *) echo "ryoku-install: invalid shell selection" >&2; exit 2 ;;
    esac
  else
    shell_choice="fish"
  fi
fi

if [ "$apps_set" -eq 0 ]; then
  apps_spec="$default_apps"
fi

selected_apps=()
if [ -n "$apps_spec" ] && [ "$apps_spec" != "none" ]; then
  IFS=',' read -r -a raw_apps <<< "$apps_spec"
  declare -A seen_apps=()
  for app in "${raw_apps[@]}"; do
    app="${app//[[:space:]]/}"
    [ -n "$app" ] || continue
    case "$app" in
      prompt|bash-edit|fastfetch|yazi|cli-tools|git-tools|pavucontrol|songrec|openrgb|upscale|localsend|gamescope|gamemode|mangohud|vm|docker|flatpak|go|pytools|mise) ;;
      *) echo "ryoku-install: invalid optional app id: $app" >&2; exit 2 ;;
    esac
    if [ -z "${seen_apps[$app]+x}" ]; then
      selected_apps+=("$app")
      seen_apps[$app]=1
    fi
  done
fi

if [ "$iso_mode" -eq 1 ]; then
  install_iso
  exit $?
fi

case "$flake_arg" in
  *#*)
    flake_root="${flake_arg%%#*}"
    host="${flake_arg#*#}"
    ;;
  *)
    flake_root="$flake_arg"
    host=""
    ;;
esac

flake_root="$(readlink -f "$flake_root")"
flake_file="$flake_root/flake.nix"
module_file="$flake_root/ryoku.nix"

# Serialize manual integrations before inspecting the global restore record.
# An atomic root-owned directory also stops simultaneous invocations under
# different user accounts. A hard crash leaves the lock in place for inspection.
install_lock_dir="/var/backups/ryoku-nixos/.install-active"
install_lock_held=0
release_install_lock() {
  if [ "$install_lock_held" -eq 1 ]; then
    if ! run_root rmdir "$install_lock_dir"; then
      echo "ryoku-install: WARNING: could not release $install_lock_dir" >&2
    fi
    install_lock_held=0
  fi
}
if [ "$dry_run" -eq 0 ]; then
  run_root mkdir -p /var/backups/ryoku-nixos
  if ! run_root mkdir "$install_lock_dir" 2>/dev/null; then
    die "another Ryoku installation may be running. Inspect $install_lock_dir before retrying; remove it only if no installer is active"
  fi
  install_lock_held=1
  trap release_install_lock EXIT
fi

# While this record exists, the files under its root are a mix of the
# original configuration and an install whose restore failed. The backup it
# names is the only copy of the originals.
pending_restore="/var/backups/ryoku-nixos.restore-pending"

record_pending_restore() {
  local record
  record="$(mktemp)"
  printf 'root=%s\nbackup=%s\ngenerated_flake=%s\nhad_lock=%s\nhad_module=%s\n' \
    "$flake_root" "$backup_dir" "$generated_flake" "$had_lock" "$had_module" > "$record"
  if ! run_root install -m 0644 "$record" "$pending_restore"; then
    rm -f "$record"
    return 1
  fi
  rm -f "$record"
}

# Put back every pre-install file. A further Ctrl+C or a closing terminal must
# not stop this half-way, and one failed copy must not skip the others. The
# pending record goes only once every file is back.
rollback() {
  transaction_started=0
  trap '' INT TERM HUP
  restore_failed=0

  if [ "$generated_flake" -eq 1 ]; then
    run_root rm -f "$flake_file" || restore_failed=1
  else
    run_root cp -a "$backup_dir/flake.nix" "$flake_file" || restore_failed=1
  fi

  if [ "$had_lock" -eq 1 ]; then
    run_root cp -a "$backup_dir/flake.lock" "$flake_root/flake.lock" || restore_failed=1
  else
    run_root rm -f "$flake_root/flake.lock" || restore_failed=1
  fi

  if [ "$had_module" -eq 1 ]; then
    run_root cp -a "$backup_dir/ryoku.nix" "$module_file" || restore_failed=1
  else
    run_root rm -f "$module_file" || restore_failed=1
  fi

  if [ "$restore_failed" -eq 0 ]; then
    run_root rm -f "$pending_restore" || restore_failed=1
  fi

  if [ "$restore_failed" -ne 0 ]; then
    echo "ryoku-install: ERROR: could not restore every configuration file in $flake_root" >&2
    echo "ryoku-install: the original files are in $backup_dir; copy them back before rebuilding" >&2
    echo "ryoku-install: running the installer again retries the restore first; if you copy them back yourself, run it with --manual-recovery" >&2
    return 1
  fi
}

# Finish an earlier install's failed restore before reading or backing up
# anything, unless the user has restored the files by hand and says so. The
# record is world-readable, so checking for it needs no root.
if [ -e "$pending_restore" ]; then
  pending_record="$(run_root cat "$pending_restore")" ||
    die "could not read $pending_restore"
  pending_root="" pending_backup="" pending_generated="" pending_lock="" pending_module=""
  while IFS='=' read -r key value; do
    case "$key" in
      root) pending_root="$value" ;;
      backup) pending_backup="$value" ;;
      generated_flake) pending_generated="$value" ;;
      had_lock) pending_lock="$value" ;;
      had_module) pending_module="$value" ;;
    esac
  done <<< "$pending_record"

  # One global recovery record protects the previous installation, even if a
  # new invocation targets another flake. Never overwrite its only pointer to
  # the original configuration before that installation has been recovered.
  if [ "$pending_root" != "$flake_root" ]; then
    die "a previous installation for ${pending_root:-an unknown flake} needs recovery from $pending_backup; refusing to install into $flake_root until that restore is resolved"
  fi

  if [ "$pending_root" = "$flake_root" ]; then
    if [ "$manual_recovery" -eq 1 ]; then
      [ "$dry_run" -eq 0 ] ||
        die "a previous installation could not restore $flake_root; run without --dry-run to continue"
      run_root rm -f "$pending_restore" ||
        die "could not remove $pending_restore"
      echo "ryoku-install: continuing with $flake_root as restored by hand; the original files remain in $pending_backup"
    else
      [ "$dry_run" -eq 0 ] ||
        die "a previous installation could not restore $flake_root; run without --dry-run to restore it from $pending_backup first"
      case "$pending_generated$pending_lock$pending_module" in
        [01][01][01]) ;;
        *) die "$pending_restore is not a valid restore record; restore $flake_root from $pending_backup by hand, then run with --manual-recovery" ;;
      esac
      run_root test -f "$pending_backup/flake.nix" ||
        die "the backup $pending_backup recorded in $pending_restore is missing; restore $flake_root by hand, then run with --manual-recovery"

      echo "ryoku-install: a previous installation could not restore $flake_root; restoring it from $pending_backup"
      backup_dir="$pending_backup"
      generated_flake="$pending_generated"
      had_lock="$pending_lock"
      had_module="$pending_module"
      if ! rollback; then
        echo "ryoku-install: nothing else was changed" >&2
        exit 1
      fi
      trap - INT TERM HUP
      generated_flake=0
      echo "ryoku-install: restored $flake_root from $pending_backup"
    fi
  fi
fi

# Set when this run created a base flake.nix for a classic /etc/nixos. That
# file stays only once the install has switched; any earlier exit removes it,
# because a later plain `nixos-rebuild` would otherwise build from it instead
# of from the user's channels.
generated_flake=0
discard_generated_flake() {
  [ "$generated_flake" -eq 1 ] || return 0
  run_root rm -f "$flake_file" ||
    echo "ryoku-install: could not remove the generated $flake_file; delete it to keep the previous configuration" >&2
}

if [ ! -f "$flake_file" ]; then
  [ "$flake_root" = "/etc/nixos" ] ||
    die "no flake.nix found at $flake_root"

  [ -f "$flake_root/configuration.nix" ] ||
    die "configuration.nix not found at $flake_root"

  [ -f "$flake_root/hardware-configuration.nix" ] ||
    die "hardware-configuration.nix not found at $flake_root"

  if [ "$dry_run" -eq 1 ]; then
    die "no flake.nix found. Run the installer without --dry-run to create a base flake."
  fi

  current_host="$(cat /proc/sys/kernel/hostname)"
  valid_hostname "$current_host" ||
    die "could not use the current hostname to generate flake.nix"

  nixpkgs_url="github:NixOS/nixpkgs/nixos-unstable"

  temp_flake="$(mktemp)"

  cat > "$temp_flake" <<EOF
{
  description = "NixOS configuration bootstrapped by Ryoku";

  inputs.nixpkgs.url = "$nixpkgs_url";

  outputs = { self, nixpkgs, ... }: {
    nixosConfigurations."$current_host" = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";

      modules = [
        ./configuration.nix
      ];
    };
  };
}
EOF

  if ! run_root install -m 0644 "$temp_flake" "$flake_file"; then
    rm -f "$temp_flake"
    die "failed to create $flake_file"
  fi

  rm -f "$temp_flake"
  generated_flake=1
  trap 'discard_generated_flake; release_install_lock' EXIT

  echo "ryoku-install: created a base flake at $flake_file"
fi

if [ -z "$host" ]; then
  current_host="$(cat /proc/sys/kernel/hostname)"

  show="$(
    nix flake show "path:$flake_root" --json --no-write-lock-file 2>/dev/null ||
    nix flake show "path:$flake_root" --json --impure --no-write-lock-file
  )"

  mapfile -t hosts < <(
    printf '%s\n' "$show" |
      jq -r '.nixosConfigurations // {} | keys[]'
  )

  [ "${#hosts[@]}" -gt 0 ] || {
    echo "ryoku-install: no nixosConfigurations found" >&2
    exit 1
  }

  for candidate in "${hosts[@]}"; do
    if [ "$candidate" = "$current_host" ]; then
      host="$candidate"
      break
    fi
  done

  if [ -z "$host" ] && [ "${#hosts[@]}" -eq 1 ]; then
    host="${hosts[0]}"
  fi

  if [ -z "$host" ]; then
    echo "ryoku-install: multiple NixOS hosts found:" >&2
    printf '  %s\n' "${hosts[@]}" >&2
    echo "Re-run with --flake $flake_root#HOST" >&2
    exit 1
  fi
fi

if [ -f "$module_file" ] &&
   ! grep -Fq '# Managed by ryoku-install.' "$module_file"
then
  echo "ryoku-install: $module_file already exists and is not installer-managed" >&2
  echo "Refusing to overwrite it." >&2
  exit 1
fi

# Prove the selected host evaluates before a real install touches its flake or
# lock file. Dry-run remains side-effect/network-light and only renders the
# proposed integration. This catches pre-existing broken imports separately
# from Ryoku failures without making preview mode depend on Nix store access.
if [ "$dry_run" -eq 0 ]; then
  echo "@@RYOKU_STEP validate"
  printf '\nValidating existing NixOS host...\n'
  if ! nix --extra-experimental-features "nix-command flakes" eval --raw \
    "path:$flake_root#nixosConfigurations.\"$host\".config.system.build.toplevel.drvPath" \
    --no-write-lock-file \
    >/dev/null
  then
    echo "ryoku-install: existing NixOS host does not evaluate; no files were changed" >&2
    echo "Fix the flake error above, then re-run ryoku-install." >&2
    exit 1
  fi

  # Ryoku does not own the host kernel on an existing NixOS installation.
  # Before touching the user's flake, verify that an NVIDIA host can actually
  # realize its current kernel module tree. This distinguishes a pre-existing
  # NVIDIA/kernel incompatibility from a Ryoku integration failure.
  resolve_gpu_vendors
  if [[ " ${gpu_vendors[*]} " == *" nvidia "* ]]; then
    printf '\nValidating existing NVIDIA kernel modules...\n'
    if ! nix --extra-experimental-features "nix-command flakes" build \
      --no-link \
      --no-write-lock-file \
      "path:$flake_root#nixosConfigurations.\"$host\".config.system.modulesTree"
    then
      echo "ryoku-install: existing NixOS NVIDIA/kernel combination does not build; no files were changed" >&2
      echo "ryoku-install: if the error above mentions nvidia-kernel-modules, switch the host to boot.kernelPackages = pkgs.linuxPackages and retry" >&2
      exit 1
    fi
  fi
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"; discard_generated_flake; release_install_lock' EXIT

work_flake="$work_dir/flake.nix"
work_module="$work_dir/ryoku.nix"

cp "$flake_file" "$work_flake"

apps_block=""
if [ "${#selected_apps[@]}" -gt 0 ]; then
  apps_block="$(printf '      "%s"\n' "${selected_apps[@]}")"
fi

cat > "$work_module" <<EOF
# Managed by ryoku-install.
{ ... }:

{
  programs.ryoku = {
enable = true;
defaultCompositor = "$compositor";
browser = "$browser";
shell = "$shell_choice";
optionalApps = [
$apps_block
];
  };
}
EOF

python3 @INSTALL_EDIT@ "$work_flake" "$host" "$source_ref"

printf '\nRyoku NixOS installer\n'
printf '%s\n' '────────────────────────────────────────'
printf 'Flake   %s\n' "$flake_root"
printf 'Host    %s\n' "$host"
printf 'Source  %s\n' "$source_ref"
printf 'WM      %s\n' "$compositor"
printf 'Browser %s\n' "$browser"
printf 'Shell   %s\n' "$shell_choice"
if [ "${#selected_apps[@]}" -gt 0 ]; then
  printf 'Apps    %s\n' "$(IFS=,; echo "${selected_apps[*]}")"
else
  printf 'Apps    none\n'
fi

printf '\nProposed flake.nix changes:\n'
diff -u "$flake_file" "$work_flake" || true

printf '\nProposed ryoku.nix:\n'
cat "$work_module"

if [ "$dry_run" -eq 1 ]; then
  printf '\nDry run complete. No files were changed.\n'
  exit 0
fi

if [ "$assume_yes" -ne 1 ]; then
  printf '\nThe new NixOS generation will be built before it is switched.\n'
  printf 'Bootloader, kernel and partition settings are not modified.\n'
  printf 'Continue? [y/N] '

  read -r answer

  case "$answer" in
    y|Y|yes|YES)
      ;;
    *)
      echo "Cancelled."
      exit 0
      ;;
  esac
fi

if [ -x /run/current-system/sw/bin/nixos-rebuild ]; then
  nixos_rebuild=/run/current-system/sw/bin/nixos-rebuild
else
  nixos_rebuild="$(command -v nixos-rebuild || true)"
fi

[ -n "$nixos_rebuild" ] || {
  echo "ryoku-install: nixos-rebuild is unavailable" >&2
  exit 1
}

echo "@@RYOKU_STEP prepare"
timestamp="$(date +%Y%m%d-%H%M%S)"

had_lock=0
had_module=0

[ -f "$flake_root/flake.lock" ] && had_lock=1
[ -f "$module_file" ] && had_module=1

# A retry within the same second must not write into an earlier backup,
# which may hold the only copy of the original files.
run_root mkdir -p /var/backups/ryoku-nixos
backup_dir="/var/backups/ryoku-nixos/$timestamp"
backup_suffix=1
until run_root mkdir "$backup_dir" 2>/dev/null; do
  backup_suffix=$((backup_suffix + 1))
  [ "$backup_suffix" -le 100 ] ||
    die "could not create a backup directory under /var/backups/ryoku-nixos"
  backup_dir="/var/backups/ryoku-nixos/$timestamp-$backup_suffix"
done
run_root cp -a "$flake_file" "$backup_dir/flake.nix"

if [ "$had_lock" -eq 1 ]; then
  run_root cp -a "$flake_root/flake.lock" "$backup_dir/flake.lock"
fi

if [ "$had_module" -eq 1 ]; then
  run_root cp -a "$module_file" "$backup_dir/ryoku.nix"
fi

record_pending_restore ||
  die "could not record the backup in $pending_restore; nothing was changed"

# Roll back, then report the failure without claiming a restore that failed.
abort_transaction() {
  if rollback; then
    echo "ryoku-install: $1; $2" >&2
  else
    echo "ryoku-install: $1" >&2
  fi
}

transaction_started=0
cleanup() {
  result=$?
  trap - EXIT
  trap '' INT TERM HUP
  if [ "$transaction_started" -eq 1 ]; then
    abort_transaction "installation stopped" "files restored"
  fi
  rm -rf "$work_dir"
  release_install_lock
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

transaction_started=1
run_root cp "$work_flake" "$flake_file"
run_root install -m 0644 "$work_module" "$module_file"

echo "@@RYOKU_STEP lock"
printf '\nUpdating flake lock...\n'

if ! run_root nix flake lock "path:$flake_root"; then
  abort_transaction "flake lock failed" "files restored"
  exit 1
fi

echo "@@RYOKU_STEP build"
printf '\nBuilding NixOS generation...\n'

if ! run_root "$nixos_rebuild" build \
  --flake "path:$flake_root#$host"
then
  abort_transaction "build failed" "files restored"
  exit 1
fi

echo "@@RYOKU_STEP switch"
printf '\nSwitching generation...\n'

if ! run_root "$nixos_rebuild" switch \
  --flake "path:$flake_root#$host"
then
  abort_transaction "switch failed" "configuration files restored"
  # The new generation was built and may already be the system profile and
  # default boot entry even though activation failed. The files are restored,
  # so say how to inspect and, if wanted, undo that part.
  echo "ryoku-install: the failed generation may still be the current profile or boot entry." >&2
  echo "ryoku-install: inspect with: nixos-rebuild list-generations" >&2
  echo "ryoku-install: return to the previous generation with: sudo nixos-rebuild switch --rollback" >&2
  exit 1
fi

transaction_started=0
if ! run_root rm -f "$pending_restore"; then
  echo "ryoku-install: WARNING: delete $pending_restore, or the next run will restore the files from before this install" >&2
fi
echo "@@RYOKU_STEP materialize"
# The new generation is already live here. A failed user-config refresh is a
# warning to act on, not a failed installation: the files are kept and the
# next login (or running ryoku-materialize) retries it.
if [ -x /run/current-system/sw/bin/ryoku-materialize ]; then
  if ! /run/current-system/sw/bin/ryoku-materialize; then
    echo "ryoku-install: WARNING: ryoku-materialize failed after a successful switch." >&2
    echo "ryoku-install: the system is installed; run ryoku-materialize again from your session to finish." >&2
  fi
fi

systemctl --user daemon-reload >/dev/null 2>&1 || true
systemctl --user try-restart ryoku-shell.service >/dev/null 2>&1 || true

echo "@@RYOKU_DONE"
printf '\nRyoku installation complete.\n'
printf 'Backup: %s\n' "$backup_dir"
