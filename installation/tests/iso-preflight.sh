#!/usr/bin/env bash
# iso-preflight.sh: the gate an ISO build must clear BEFORE mkarchiso starts.
#
# An ISO build costs an hour or two and then ships to users, so the failure
# classes we have actually shipped are checked here first, in seconds:
#
#   offline resolution   an in-chroot pacman that cannot resolve from the baked
#                        repo (a registered repo with no synced db fails the whole
#                        transaction), so the desktop, drivers, or AUR set never
#                        install on a no-network box.
#   pacman hooks         a mask that collides with a packaged hook, or a hook left
#                        live through pacstrap (snapper with no config,
#                        limine-install against a /boot that is not an ESP).
#   package coverage     a package the installer can ask for that the offline bake
#                        does not carry.
#   boot menu            limine.conf shape, the alongside two-stage chain, the
#                        chainload entry for the existing OS.
#   installer contract   the dry-run step/sentinel matrix, the preflight refusals,
#                        the TUI's layout and safety gates.
#
# Everything here is hermetic and root-free: no disk, no network, no VM. The
# root-only partitioner and the QEMU boot chain stay in the Install backend tests
# workflow. Run it by hand before dispatching a build:
#
#   bash installation/tests/iso-preflight.sh
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
cd "$ROOT"

pass=0
fail=0
failed=()

gate() {
  local name=$1
  shift
  printf '\n=== %s ===\n' "$name"
  if "$@"; then
    pass=$((pass + 1))
    printf 'gate ok: %s\n' "$name"
  else
    fail=$((fail + 1))
    failed+=("$name")
    printf 'GATE FAILED: %s\n' "$name" >&2
  fi
}

# 1. shell syntax over every installer script, plus ShellCheck when present, with
#    the SAME flags as the ShellCheck workflow (-x -s bash --severity=warning).
#    Matching it matters: the runner's shellcheck is a different generation from a
#    rolling Arch box, and the info-level rules disagree between them.
syntax_gate() {
  local f rc=0
  while IFS= read -r f; do
    bash -n "$f" || { printf 'bash -n failed: %s\n' "$f" >&2; rc=1; }
  done < <(shell_files)
  return $rc
}

shellcheck_gate() {
  if ! command -v shellcheck >/dev/null 2>&1; then
    printf 'shellcheck absent; skipping (the ShellCheck workflow covers it)\n'
    return 0
  fi
  # shellcheck disable=SC2046  # deliberate word split: the file list has no spaces
  shellcheck -x -s bash --severity=warning $(shell_files | tr '\n' ' ')
}

shell_files() {
  printf '%s\n' installation/backend/ryoku-install
  # git, not find: a local build leaves gitignored trees (staging, the offline
  # cache) under installation/iso full of vendored and AUR scripts.
  git ls-files -co --exclude-standard -- installation/backend/lib installation/iso \
    system/hardware/drivers | grep '\.sh$' | sort
  find tests -maxdepth 1 -name 'install-*.sh' -o -maxdepth 1 -name 'limine-*.sh' \
    -o -maxdepth 1 -name 'offline-repo-integrity.sh' | sort
}

# 2. the installer's own regression suite, root-free half.
suite_gate() {
  local t rc=0
  for t in "$@"; do
    if bash "tests/$t.sh" >"/tmp/ryoku-preflight-$t.log" 2>&1; then
      printf '  %-32s ok\n' "$t"
    else
      printf '  %-32s FAILED\n' "$t" >&2
      tail -20 "/tmp/ryoku-preflight-$t.log" >&2
      rc=1
    fi
  done
  return $rc
}

# 3. the TUI has to build and pass its unit tests: it is the only thing a user
#    can reach on the ISO, and a build failure there ships an unbootable installer.
tui_gate() {
  if ! command -v go >/dev/null 2>&1; then
    printf 'go absent; skipping the TUI gate (the Go unit tests workflow covers it)\n'
    return 0
  fi
  (cd installation/tui && go build ./... && go vet ./... && go test ./...)
}

# 4. package lists have to be parseable and free of duplicates: a duplicate or a
#    stray token becomes a pacman "target not found" mid-pacstrap, after the wipe.
packages_gate() {
  local f rc=0 dupes
  for f in system/packages/*.packages; do
    while IFS= read -r line; do
      [[ $line =~ ^[[:space:]]*(#|$) ]] && continue
      [[ $line =~ ^\[[a-z0-9_-]+\]$ ]] && continue
      [[ $line =~ ^[a-z0-9][a-z0-9@._+-]*$ ]] && continue
      printf 'malformed package name in %s: %q\n' "$f" "$line" >&2
      rc=1
    done <"$f"
    dupes=$(grep -vE '^[[:space:]]*(#|\[|$)' "$f" | sort | uniq -d || true)
    if [[ -n $dupes ]]; then
      printf 'duplicate entries in %s: %s\n' "$f" "$(tr '\n' ' ' <<<"$dupes")" >&2
      rc=1
    fi
  done
  return $rc
}

# 5. delivery: a config that reaches no user is a silent regression for everyone
#    who installs this ISO and then runs `ryoku update`.
delivery_gate() {
  bin/ryoku-dev-verify-delivery --quiet
}

# 6. the inclusive-language gate that already blocks a push, so a build dispatch
#    does not discover it after the fact.
language_gate() {
  if ! command -v woke >/dev/null 2>&1; then
    printf 'woke absent; skipping (the Inclusive Language workflow covers it)\n'
    return 0
  fi
  # git's file list (already free of ignored paths) with --no-ignore: woke
  # otherwise opens every .gitignore under the repo, whatever it is asked to
  # lint, including those in a finished build's root-owned installation/iso/work/,
  # and dies on the permission error before linting anything.
  local -a files=()
  mapfile -t files < <(git ls-files -co --exclude-standard -- \
    installation docs tests system/hardware .github/workflows)
  woke --config .woke.yml --exit-1-on-failure --no-ignore "${files[@]}"
}

gate "shell syntax" syntax_gate
gate "shellcheck" shellcheck_gate
gate "package lists" packages_gate
gate "ISO variant staging" suite_gate iso-variant-stage cachyos-repo-placement
gate "offline install path" suite_gate install-offline install-hooks offline-repo-integrity \
  install-noninteractive
gate "boot menu" suite_gate limine-bootloader limine-windows
gate "installer contract" suite_gate install-dryrun-matrix install-preflight \
  install-chroot-safety install-partition-whole install-largest-free \
  install-disk-teardown install-dns install-mirrors install-clock-skew \
  installer-session-scale
gate "packaging offline" suite_gate release-offline-builds
gate "installer TUI" tui_gate
gate "update delivery" delivery_gate
gate "inclusive language" language_gate

printf '\n=== iso-preflight: %d gate(s) ok, %d failed ===\n' "$pass" "$fail"
if ((fail > 0)); then
  printf 'failed: %s\n' "${failed[*]}" >&2
  printf 'the ISO build must not start with these open.\n' >&2
  exit 1
fi
printf 'clear to build.\n'
