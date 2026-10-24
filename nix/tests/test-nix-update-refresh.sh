#!/usr/bin/env bash
set -euo pipefail

helper=${RYOKU_NIX_UPDATE_TEST_HELPER:?}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
bin="$work/bin"
mkdir -p "$bin"
bash_bin=$(command -v bash)

# Exercise the production function without running the helper's command dispatcher.
eval "$(awk '/^refresh_runtime\(\)/ {show=1} show {print} show && /^}/ {exit}' "$helper")"

printf '#!%s\n' "$bash_bin" >"$bin/pkill"
cat >>"$bin/pkill" <<'SH'
exit 0
SH
printf '#!%s\n' "$bash_bin" >"$bin/sleep"
cat >>"$bin/sleep" <<'SH'
exit 0
SH
chmod +x "$bin/pkill" "$bin/sleep"

printf '#!%s\n' "$bash_bin" >"$bin/systemctl"
cat >>"$bin/systemctl" <<'SH'
case " $* " in
  *' daemon-reload '*) exit 0 ;;
  *' restart ryoku-materialize.service '*) exit 0 ;;
  *' restart ryoku-shell.service '*) exit 0 ;;
  *' is-active --quiet ryoku-shell.service '*) exit 0 ;;
  *' try-restart ryoku-shell.service '*) exit 0 ;;
esac
exit 1
SH
chmod +x "$bin/systemctl"
PATH="$bin:$PATH" refresh_runtime true

printf '#!%s\n' "$bash_bin" >"$bin/systemctl"
cat >>"$bin/systemctl" <<'SH'
case " $* " in
  *' daemon-reload '*) exit 0 ;;
  *' restart ryoku-materialize.service '*) exit 0 ;;
  *' restart ryoku-shell.service '*) exit 0 ;;
  *' is-active --quiet ryoku-shell.service '*) exit 1 ;;
esac
exit 1
SH
chmod +x "$bin/systemctl"
if PATH="$bin:$PATH" refresh_runtime true; then
    printf 'expected active-session refresh to fail when the shell never recovers\n' >&2
    exit 1
fi

printf '#!%s\n' "$bash_bin" >"$bin/systemctl"
cat >>"$bin/systemctl" <<'SH'
exit 1
SH
chmod +x "$bin/systemctl"
PATH="$bin:$PATH" refresh_runtime false 2>"$work/deferred"
grep -Fq 'runtime refresh deferred' "$work/deferred"

printf 'nix-update-refresh: PASS\n'
