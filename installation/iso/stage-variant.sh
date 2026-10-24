#!/usr/bin/env bash

_ryoku_stage_variant_die() {
  printf 'stage-variant.sh: error: %s\n' "$*" >&2
  return 1
}

_ryoku_stage_rewrite_file() {
  local file=$1 tmp
  tmp=$(mktemp "${file}.tmp.XXXXXX") || return 1
  if ! awk '
    /^[[:space:]]*(title|menuentry|MENU (TITLE|LABEL))[[:space:]]/ &&
      index($0, "Ryoku Linux installer") &&
      !index($0, "Ryoku Linux installer (CachyOS)") {
        sub(/Ryoku Linux installer/, "Ryoku Linux installer (CachyOS)")
      }
    { print }
  ' "$file" >"$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  chmod --reference="$file" "$tmp"
  mv "$tmp" "$file"
  sed -i -E \
    -e 's/vmlinuz-linux($|[^[:alnum:]_.-])/vmlinuz-linux-cachyos\1/g' \
    -e 's/initramfs-linux\.img($|[^[:alnum:]_.-])/initramfs-linux-cachyos.img\1/g' \
    "$file"
}

_ryoku_stage_cachyos_repo() {
  local pacman_conf=$1 mirror tmp
  mirror=${RYOKU_CACHYOS_MIRROR:-https://mirror.cachyos.org/repo}
  mirror=${mirror%/}
  [[ $mirror == https://* ]] || _ryoku_stage_variant_die \
    "RYOKU_CACHYOS_MIRROR must use HTTPS, got: $mirror" || return 1

  grep -qxF '[cachyos]' "$pacman_conf" && return 0
  tmp=$(mktemp "${pacman_conf}.tmp.XXXXXX") || return 1
  if ! awk -v server="Server = $mirror/\$arch/\$repo" '
    /^\[core\]$/ && !inserted {
      print "[cachyos]"
      print server
      print ""
      inserted = 1
    }
    { print }
    END { if (!inserted) exit 1 }
  ' "$pacman_conf" >"$tmp"; then
    rm -f "$tmp"
    _ryoku_stage_variant_die "cannot insert [cachyos]: [core] is absent from $pacman_conf"
    return 1
  fi
  chmod --reference="$pacman_conf" "$tmp"
  mv "$tmp" "$pacman_conf"
}

_ryoku_stage_cachyos_profile() {
  local profile=$1 packages preset config package
  local -a boot_configs cachyos_packages=(
    cachyos-keyring
    cachyos-mirrorlist
    cachyos-v3-mirrorlist
    cachyos-v4-mirrorlist
    cachyos-hooks
    chwd
  )

  [[ -d $profile ]] || _ryoku_stage_variant_die "profile directory not found: $profile" || return 1
  packages=$profile/packages.x86_64
  [[ -f $packages ]] || _ryoku_stage_variant_die "package manifest not found: $packages" || return 1

  if grep -qx 'linux' "$packages"; then
    sed -i 's/^linux$/linux-cachyos/' "$packages"
  elif ! grep -qx 'linux-cachyos' "$packages"; then
    _ryoku_stage_variant_die "package manifest has neither linux nor linux-cachyos"
    return 1
  fi
  for package in "${cachyos_packages[@]}"; do
    grep -qx "$package" "$packages" || printf '%s\n' "$package" >>"$packages"
  done

  _ryoku_stage_cachyos_repo "$profile/pacman.conf" || return 1

  if [[ -e $profile/airootfs/etc/mkinitcpio.d/linux.preset ]]; then
    [[ ! -e $profile/airootfs/etc/mkinitcpio.d/linux-cachyos.preset ]] || {
      _ryoku_stage_variant_die "both linux.preset and linux-cachyos.preset exist"
      return 1
    }
    mv "$profile/airootfs/etc/mkinitcpio.d/linux.preset" \
      "$profile/airootfs/etc/mkinitcpio.d/linux-cachyos.preset"
  fi
  preset=$profile/airootfs/etc/mkinitcpio.d/linux-cachyos.preset
  [[ -f $preset ]] || _ryoku_stage_variant_die "CachyOS mkinitcpio preset not found: $preset" || return 1
  _ryoku_stage_rewrite_file "$preset" || return 1

  mapfile -d '' boot_configs < <(
    find "$profile/efiboot" "$profile/grub" "$profile/syslinux" -type f \
      \( -name '*.conf' -o -name '*.cfg' \) -print0
  )
  ((${#boot_configs[@]} > 0)) || _ryoku_stage_variant_die "no staged boot configs found" || return 1
  for config in "${boot_configs[@]}"; do
    _ryoku_stage_rewrite_file "$config" || return 1
  done

  sed -i \
    's/^iso_application="Ryoku Linux Installer"$/iso_application="Ryoku Linux Installer (CachyOS)"/' \
    "$profile/profiledef.sh"
  sed -i \
    's/ installer (live)  (/ installer (CachyOS edition, live)  (/' \
    "$profile/airootfs/etc/motd"
}

ryoku_stage_variant() {
  local variant=$1 profile=$2
  case $variant in
    plain) return 0 ;;
    cachyos) _ryoku_stage_cachyos_profile "$profile" ;;
    *) _ryoku_stage_variant_die "unsupported variant: $variant" ;;
  esac
}

ryoku_trust_cachyos_build_host() {
  local mirror db desc filename expected_hash actual_hash trusted_fingerprint fingerprint_output
  local expected_fingerprint=882DCFE48E2051D48E2562ABF3B607488DB35A47
  local tmp package keyring_dir file
  local -a elevate=()

  mirror=${RYOKU_CACHYOS_MIRROR:-https://mirror.cachyos.org/repo}
  mirror=${mirror%/}
  [[ $mirror == https://* ]] || _ryoku_stage_variant_die \
    "RYOKU_CACHYOS_MIRROR must use HTTPS, got: $mirror" || return 1
  command -v curl >/dev/null 2>&1 || _ryoku_stage_variant_die "curl is required to fetch cachyos-keyring" || return 1
  command -v bsdtar >/dev/null 2>&1 || _ryoku_stage_variant_die "bsdtar is required to unpack cachyos-keyring" || return 1
  command -v pacman-key >/dev/null 2>&1 || _ryoku_stage_variant_die "pacman-key is required to trust CachyOS packages" || return 1
  if ((EUID != 0)); then
    command -v sudo >/dev/null 2>&1 || _ryoku_stage_variant_die "root or sudo is required to populate the CachyOS keyring" || return 1
    elevate=(sudo)
  fi

  tmp=$(mktemp -d) || return 1
  db=$tmp/cachyos.db
  if ! curl -fsSL --retry 2 --max-time 60 -o "$db" "$mirror/x86_64/cachyos/cachyos.db"; then
    rm -rf "$tmp"
    _ryoku_stage_variant_die "cannot fetch the CachyOS repository database from $mirror"
    return 1
  fi
  if ! desc=$(bsdtar -xOf "$db" 'cachyos-keyring-*/desc' 2>/dev/null); then
    rm -rf "$tmp"
    _ryoku_stage_variant_die "cachyos-keyring is absent from $mirror/x86_64/cachyos"
    return 1
  fi
  filename=$(awk '/^%FILENAME%$/{getline; print; exit}' <<<"$desc")
  expected_hash=$(awk '/^%SHA256SUM%$/{getline; print; exit}' <<<"$desc")
  [[ -n $filename && -n $expected_hash ]] || {
    rm -rf "$tmp"
    _ryoku_stage_variant_die "cachyos-keyring repository metadata is incomplete"
    return 1
  }

  package=$tmp/$filename
  if ! curl -fsSL --retry 2 --max-time 120 -o "$package" \
    "$mirror/x86_64/cachyos/$filename"; then
    rm -rf "$tmp"
    _ryoku_stage_variant_die "cannot fetch $filename from $mirror"
    return 1
  fi
  actual_hash=$(sha256sum "$package" | awk '{print $1}')
  [[ $actual_hash == "$expected_hash" ]] || {
    rm -rf "$tmp"
    _ryoku_stage_variant_die "cachyos-keyring checksum mismatch: expected $expected_hash, got $actual_hash"
    return 1
  }

  mkdir -p "$tmp/unpack"
  if ! bsdtar -xf "$package" -C "$tmp/unpack" usr/share/pacman/keyrings; then
    rm -rf "$tmp"
    _ryoku_stage_variant_die "cannot unpack the cachyos-keyring package"
    return 1
  fi
  keyring_dir=$tmp/unpack/usr/share/pacman/keyrings
  trusted_fingerprint=$(awk -F: 'NF && $1 !~ /^#/ {print toupper($1); exit}' \
    "$keyring_dir/cachyos-trusted")
  [[ $trusted_fingerprint == *F3B607488DB35A47 ]] || {
    rm -rf "$tmp"
    _ryoku_stage_variant_die "CachyOS trusted fingerprint has the wrong suffix: ${trusted_fingerprint:-missing}"
    return 1
  }
  [[ $trusted_fingerprint == "$expected_fingerprint" ]] || {
    rm -rf "$tmp"
    _ryoku_stage_variant_die "CachyOS trusted fingerprint mismatch: expected $expected_fingerprint, got $trusted_fingerprint"
    return 1
  }

  for file in cachyos.gpg cachyos-trusted cachyos-revoked; do
    "${elevate[@]}" install -Dm0644 "$keyring_dir/$file" "/usr/share/pacman/keyrings/$file"
  done
  # Fresh CI keyrings can have Arch keys but no local secret key for --populate.
  "${elevate[@]}" pacman-key --init
  "${elevate[@]}" pacman-key --populate cachyos
  fingerprint_output=$("${elevate[@]}" pacman-key --finger "$expected_fingerprint")
  fingerprint_output=${fingerprint_output//[[:space:]]/}
  [[ $fingerprint_output == *"$expected_fingerprint"* ]] || {
    rm -rf "$tmp"
    _ryoku_stage_variant_die "populated CachyOS keyring does not contain $expected_fingerprint"
    return 1
  }
  rm -rf "$tmp"
}
