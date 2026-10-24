#!/usr/bin/env bash
# A Kepler GPU must select NVIDIA's 470xx legacy branch. 580xx can provide an
# on-disk module but does not support GK208/GeForce GT 710, which then leaves
# Nouveau blacklisted with no driver able to bind the display or HDMI audio.
set -euo pipefail

ROOT=${RYOKU_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
driver="$ROOT/system/hardware/drivers/nvidia.sh"

[[ -x $driver ]] || { echo "missing driver policy: $driver" >&2; exit 1; }

write_ryoku_host_fake() {
  local bin=$1
  cat >"$bin/ryoku-host" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == pkgmgr ]]; then
  printf '%s\n' pacman
  exit 0
fi
[[ ${1:-} == pkg ]] || exit 2
verb=${2:-}
shift 2
case $verb in
  installed) exec pacman -Q "$@" ;;
  available) exec pacman -Si "$@" ;;
  version) exec pacman -Q "$@" ;;
  install) exec pacman -S --needed --noconfirm "$@" ;;
  *) exit 2 ;;
esac
EOF
  chmod +x "$bin/ryoku-host"
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"

cat >"$work/bin/lspci" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '01:00.0 VGA compatible controller: NVIDIA Corporation GK208B [GeForce GT 710] (rev a1)'
EOF

cat >"$work/bin/pacman" <<'EOF'
#!/usr/bin/env bash
# No NVIDIA package is installed: exercise the installer selection branch.
exit 1
EOF

cat >"$work/bin/pacman-conf" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
write_ryoku_host_fake "$work/bin"
chmod +x "$work/bin"/*

out=$(PATH="$work/bin:$PATH" RYOKU_DRYRUN=1 bash "$driver")
[[ $out == *'Kepler GPU, using the legacy 470xx branch (nvidia-470xx-dkms).'* ]] || {
  printf 'expected 470xx for GK208/GT 710, got:\n%s\n' "$out" >&2
  exit 1
}

echo "nvidia driver selection: OK"

# A Turing+ GPU on a distro kernel whose repo ships the kernel-matched prebuilt
# (CachyOS: linux-cachyos-nvidia-open) must take the prebuilt, not force a
# DKMS compile on every kernel transaction (#214). A kernel no synced repo has
# a prebuilt for still falls back to nvidia-open-dkms.
select_case() {
  local label=$1 pkgbase=$2 repo_has=$3 want=$4
  local work bin
  work=$(mktemp -d)
  bin="$work/bin"; mkdir -p "$bin" "$work/mod/$pkgbase"
  printf '%s\n' "$pkgbase" >"$work/mod/$pkgbase/pkgbase"
  cat >"$bin/lspci" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' '01:00.0 VGA compatible controller: NVIDIA Corporation TU104 [GeForce RTX 2070 SUPER] (rev a1)'
EOS
  cat >"$bin/pacman" <<EOS
#!/usr/bin/env bash
# -Qq: nothing installed. -Si: the synced db carries the prebuilt only when
# the case says so, and only under the exact name asked for.
if [[ \${1:-} == -Si ]]; then
  [[ \${2:-} == '$repo_has' ]] && exit 0
  exit 1
fi
exit 1
EOS
  printf '#!/usr/bin/env bash\nexit 0\n' >"$bin/pacman-conf"
  write_ryoku_host_fake "$bin"
  chmod +x "$bin"/*
  local out
  # point the kernel enumeration at the fake module trees
  out=$(PATH="$bin:$PATH" RYOKU_DRYRUN=1 RYOKU_MODULES_DIR="$work/mod" bash "$driver" 2>&1)
  rm -rf "$work"
  [[ $out == *"$want"* ]] || {
    printf '%s: expected "%s", got:\n%s\n' "$label" "$want" "$out" >&2
    exit 1
  }
}

select_case "cachyos prebuilt" linux-cachyos linux-cachyos-nvidia-open \
  "using the prebuilt open module(s): linux-cachyos-nvidia-open"
select_case "custom kernel falls back" linux-myown no-such-package-in-any-repo \
  "no prebuilt module for kernel(s) linux-myown, using nvidia-open-dkms"

echo "nvidia driver selection: prebuilt mapping OK"

# A pre-Turing GPU on a target that already carries the Turing+ userspace
# (hardware.packages lays nvidia-utils, and CachyOS's hyprland/steam builds
# depend on it) must remove that pair first: the legacy utils conflict with it
# without replacing it, and pacman answers the conflict "no" under --noconfirm,
# which failed the driver install and left the card on nouveau. A box whose
# nvidia-utils name is only provided by the legacy utils removes nothing.
legacy_case() {
  local label=$1 lspci_line=$2 utils_owner=$3 want=$4 reject=$5
  local work bin
  work=$(mktemp -d)
  bin="$work/bin"; mkdir -p "$bin" "$work/mod/linux-cachyos"
  printf '%s\n' linux-cachyos >"$work/mod/linux-cachyos/pkgbase"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" %q\n' "$lspci_line" >"$bin/lspci"
  cat >"$bin/pacman" <<EOS
#!/usr/bin/env bash
# -Q answers for a provided name with the providing package, as pacman does.
case "\${1:-}" in
  -Q | -Qq)
    case "\${2:-}" in
      nvidia-utils) printf '%s\n' '$utils_owner'; exit 0 ;;
      lib32-nvidia-utils) printf '%s\n' 'lib32-$utils_owner'; exit 0 ;;
    esac
    ;;
esac
exit 1
EOS
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" core extra multilib\n' >"$bin/pacman-conf"
  write_ryoku_host_fake "$bin"
  chmod +x "$bin"/*
  local out
  out=$(PATH="$bin:$PATH" RYOKU_DRYRUN=1 RYOKU_MODULES_DIR="$work/mod" bash "$driver" 2>&1)
  rm -rf "$work"
  [[ $out == *"$want"* ]] || {
    printf '%s: expected "%s", got:\n%s\n' "$label" "$want" "$out" >&2
    exit 1
  }
  [[ -z $reject || $out != *"$reject"* ]] || {
    printf '%s: did not expect "%s", got:\n%s\n' "$label" "$reject" "$out" >&2
    exit 1
  }
}

pascal='01:00.0 VGA compatible controller: NVIDIA Corporation GP104 [GeForce GTX 1070 Ti] (rev a1)'
kepler='01:00.0 VGA compatible controller: NVIDIA Corporation GK208B [GeForce GT 710] (rev a1)'
legacy_case "pascal drops turing userspace" "$pascal" nvidia-utils \
  "pacman -Rdd --noconfirm nvidia-utils lib32-nvidia-utils" ""
legacy_case "pascal installs 580xx" "$pascal" nvidia-utils \
  "ryoku-host pkg install nvidia-580xx-dkms libva-nvidia-driver linux-cachyos-headers lib32-nvidia-580xx-utils" ""
legacy_case "kepler drops turing userspace" "$kepler" nvidia-utils \
  "pacman -Rdd --noconfirm nvidia-utils lib32-nvidia-utils" ""
legacy_case "legacy utils already present" "$pascal" nvidia-580xx-utils \
  "legacy 580xx branch" "pacman -Rdd"

echo "nvidia driver selection: legacy userspace swap OK"
