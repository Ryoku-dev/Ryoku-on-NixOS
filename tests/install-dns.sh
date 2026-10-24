#!/usr/bin/env bash
# fixture test for ryoku_ensure_dns (installation/backend/lib/network.sh): the
# pre-disk DNS gate that stops the install from wiping the disk and then dying at
# pacstrap with "Could not resolve host" (a box with a route but no working
# resolver). getent is mocked and the resolver file is a temp file
# (RYOKU_RESOLV_CONF), so we assert the heal, the gate, and the plan without
# touching /etc/resolv.conf or the network.
# the getent mocks are single-quoted on purpose: they are shell snippets eval'd
# in a subshell and must not expand here.
# shellcheck disable=SC2016
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$here/.."
fail() { echo "FAIL: $1" >&2; exit 1; }

# run_dns <getent-mock> [env-pre]: run ryoku_ensure_dns with the mock applied
# against a temp resolver file. leaves the log+stderr in $out, the resolver file
# contents in $written, and the exit code in $rc. the mock decides whether the
# resolver "works"; the real heal still writes the temp file under test.
run_dns() {
  local mock=$1 env_pre=${2:-}
  resolv="$(mktemp)"
  : >"$resolv"
  rc=0
  out="$(RYOKU_RESOLV_CONF="$resolv" RYOKU_DNS_PROBE_HOSTS=probe.invalid \
        ROOT="$root" MOCK="$mock" ENVPRE="$env_pre" bash -c '
    source "$ROOT/installation/backend/lib/common.sh"
    source "$ROOT/installation/backend/lib/network.sh"
    eval "$ENVPRE"
    eval "$MOCK"
    set -euo pipefail   # mirror the orchestrator
    ryoku_ensure_dns
  ' 2>&1)" || rc=$?
  written="$(cat "$resolv")"
  rm -f "$resolv"
}

# --- resolver already works: no write, no abort --------------------------------
run_dns 'getent() { return 0; }'
[[ $rc -eq 0 ]] || fail "aborted when DNS already works (rc=$rc): $out"
grep -qF 'name resolution works' <<<"$out" || fail "did not report working DNS"
[[ -z $written ]] || fail "wrote the resolver file when DNS already works"

# --- resolver broken, heal succeeds: fallback written, then proceeds -----------
# getent succeeds only once the fallback resolvers are in place, so it models a
# box that has connectivity but an empty resolver until we populate it.
run_dns 'getent() { grep -q 1.1.1.1 "$RYOKU_RESOLV_CONF" 2>/dev/null; }'
[[ $rc -eq 0 ]] || fail "aborted when the heal should have worked (rc=$rc): $out"
grep -qF 'nameserver 1.1.1.1' <<<"$written" || fail "did not write fallback resolvers"
grep -qF 'restored with the fallback' <<<"$out" || fail "did not report the resolver heal"

# --- resolver broken, heal fails: abort, with the disk untouched ----------------
run_dns 'getent() { return 2; }'
[[ $rc -ne 0 ]] || fail "did not abort when DNS is unrecoverable"
grep -qF 'no working DNS' <<<"$out" || fail "did not explain the DNS failure"
grep -qF 'has not been touched' <<<"$out" || fail "did not promise the disk is intact"
grep -qF 'nameserver 1.1.1.1' <<<"$written" || fail "did not attempt the fallback resolvers"

# --- offline install: skip the resolver check, write nothing --------------------
run_dns 'getent() { return 2; }' 'RYOKU_ONLINE=0'
[[ $rc -eq 0 ]] || fail "offline install aborted on the DNS check (rc=$rc): $out"
grep -qF 'offline install' <<<"$out" || fail "did not announce the offline skip"
[[ -z $written ]] || fail "offline install wrote the resolver file"

# --- dry run: narrate the plan, touch nothing -----------------------------------
run_dns 'getent() { return 2; }' 'RYOKU_DRYRUN=1'
[[ $rc -eq 0 ]] || fail "dry run aborted on the DNS check (rc=$rc): $out"
grep -qF 'would verify name resolution' <<<"$out" || fail "dry run did not narrate the plan"
[[ -z $written ]] || fail "dry run wrote the resolver file"

# --- filtered Ryoku DNS: explain the sinkhole before the TLS probe -------------
run_mirror() {
  local address=$1
  rc=0
  out="$(ROOT="$root" ADDRESS="$address" bash -c '
    source "$ROOT/installation/backend/lib/common.sh"
    source "$ROOT/installation/backend/lib/network.sh"
    export RYOKU_MIRROR_PROBE_URLS="https://repo.ryoku.dev/stable/x86_64/ryoku.db"
    export RYOKU_ONLINE=1
    getent() {
      printf "%s STREAM repo.ryoku.dev\n" "$ADDRESS"
    }
    curl() {
      return 0
    }
    set -euo pipefail
    ryoku_ensure_mirrors
  ' 2>&1)" || rc=$?
}

run_mirror 10.10.34.35
[[ $rc -ne 0 ]] || fail "private sinkhole resolution did not stop the mirror probe"
grep -qF 'DNS for ryoku.dev is being filtered on this network' <<<"$out" ||
  fail "private sinkhole resolution did not explain filtered DNS: $out"
grep -qF 'docs/updates.md#filtered-dns' <<<"$out" ||
  fail "filtered DNS message did not point to recovery guidance: $out"

run_mirror 104.21.19.117
[[ $rc -eq 0 ]] || fail "public mirror resolution failed the probe (rc=$rc): $out"
if grep -qF 'DNS for ryoku.dev is being filtered on this network' <<<"$out"; then
  fail "public mirror resolution was reported as filtered DNS: $out"
fi

echo "install-dns: all checks passed"
