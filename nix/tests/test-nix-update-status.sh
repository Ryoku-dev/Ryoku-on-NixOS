#!/usr/bin/env bash
# `ryoku-nix-update status` names the commits `ryoku status` compares for
# Urgent: trailers: the GitHub repository the Ryoku input follows, the commit
# this generation was built from and that branch's tip. git ls-remote and the
# raw VERSION fetch are stubbed, so the check needs no network.
set -euo pipefail

helper=${RYOKU_NIX_UPDATE_TEST_HELPER:?}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
bin="$work/bin"
mkdir -p "$bin" "$work/flake"
bash_bin=$(command -v bash)
real_git=$(command -v git)

printf '#!%s\n' "$bash_bin" >"$bin/git"
cat >>"$bin/git" <<SH
if [ "\$1" = ls-remote ]; then
    printf '%s\t%s\n' 4444444dddddddddddddddddddddddddddddddd "\$3"
    exit 0
fi
exec "$real_git" "\$@"
SH
printf '#!%s\n' "$bash_bin" >"$bin/curl"
cat >>"$bin/curl" <<'SH'
printf '0.103.0-beta.20\n'
SH
chmod +x "$bin/git" "$bin/curl"

fail() {
    printf 'nix-update-status: %s\n' "$*" >&2
    exit 1
}

status() {
    PATH="$bin:$PATH" RYOKU_NIX_FLAKE="$work/flake" RYOKU_NIX_VERSION=0.102.3-beta.20 bash "$helper" status
}

# A GitHub input: the locked rev against the tip of the branch it follows.
cat >"$work/flake/flake.lock" <<'JSON'
{
  "nodes": {
    "root": { "inputs": { "ryoku": "ryoku" } },
    "ryoku": {
      "locked": { "type": "github", "owner": "Ryoku-dev", "repo": "Ryoku-on-NixOS", "rev": "0000000aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" },
      "original": { "type": "github", "owner": "Ryoku-dev", "repo": "Ryoku-on-NixOS", "ref": "unstable-dev" }
    }
  },
  "root": "root",
  "version": 7
}
JSON
out=$(status)
[ "$(jq -r .repository <<<"$out")" = Ryoku-dev/Ryoku-on-NixOS ] || fail "github input: repository in $out"
[ "$(jq -r .installedRev <<<"$out")" = 0000000aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa ] || fail "github input: installedRev in $out"
[ "$(jq -r .latestRev <<<"$out")" = 4444444dddddddddddddddddddddddddddddddd ] || fail "github input: latestRev in $out"
[ "$(jq -r .available <<<"$out")" = true ] || fail "github input: a moved branch is an update: $out"

# A clean local checkout with a GitHub origin: its HEAD against the tip of its
# branch there.
src="$work/src"
"$real_git" init -q -b feat "$src"
printf '0.102.3-beta.20\n' >"$src/VERSION"
"$real_git" -C "$src" add VERSION
"$real_git" -C "$src" -c user.name=t -c user.email=t@example.com commit -q -m 'chore: seed'
"$real_git" -C "$src" remote add origin https://github.com/eximora-private/Ryoku-on-NixOS.git
head=$("$real_git" -C "$src" rev-parse HEAD)
jq -n --arg path "$src" '{
  nodes: {
    root: { inputs: { ryoku: "ryoku" } },
    ryoku: { locked: { type: "path", path: $path }, original: { type: "path", path: $path } }
  },
  root: "root",
  version: 7
}' >"$work/flake/flake.lock"
out=$(status)
[ "$(jq -r .repository <<<"$out")" = eximora-private/Ryoku-on-NixOS ] || fail "path input: repository in $out"
[ "$(jq -r .installedRev <<<"$out")" = "$head" ] || fail "path input: installedRev in $out"
[ "$(jq -r .latestRev <<<"$out")" = 4444444dddddddddddddddddddddddddddddddd ] || fail "path input: latestRev in $out"

# A local checkout without a GitHub origin has nothing to compare.
"$real_git" -C "$src" remote set-url origin https://git.example.org/ryoku.git
out=$(status)
[ "$(jq -r '.repository + .installedRev + .latestRev' <<<"$out")" = "" ] || fail "non-GitHub origin: $out"

printf 'nix-update-status: PASS\n'
