#!/usr/bin/env bash
# hermetic test for bin/ryoku-discord, the one script every workflow uses to post
# to the Ryoku Discord. It checks what readers and moderators would notice: only
# the release announcement can ping, and only the configured role; untrusted
# issue and pull request text cannot hide links or break the layout; every
# message fits Discord's limits even for a release with hundreds of notes; the
# release bot's bumps never count as news; and a missing webhook or a rate limit
# never loses or fails a message. curl and sleep are stubbed, nothing is sent.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT/bin/ryoku-discord"
[[ -x $SCRIPT ]] || { echo "::error::missing $SCRIPT" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail=0
check() { if [[ $1 == "$2" ]]; then echo "  ok: $3"; else echo "::error::FAIL: $3 (got '$1' want '$2')" >&2; fail=1; fi; }
truthy() { if jq -e "$1" "$2" >/dev/null; then echo "  ok: $3"; else echo "::error::FAIL: $3 ($1 on $(head -c 600 "$2"))" >&2; fail=1; fi; }

export GITHUB_REPOSITORY=Ryoku-dev/ryoku GITHUB_SERVER_URL=https://github.com
unset DISCORD_WEBHOOK DISCORD_RELEASE_ROLE_ID

# Discord rejects a whole message when any one limit is crossed, so every payload
# the tests build goes through this.
fits='(.content // "" | length) <= 2000
  and (.embeds | length) <= 10
  and all(.embeds[]; (.title // "" | length) <= 256 and (.description // "" | length) <= 4096
      and ((.fields // []) | length) <= 25
      and all((.fields // [])[]; (.name | length) <= 256 and (.value | length) <= 1024 and (.value | length) > 0))
  and ([.embeds[] | [.title, .description, .author.name, .footer.text, ((.fields // [])[] | .name, .value)]
      | map(select(. != null) | length) | add] | add) <= 6000'
quiet='.allowed_mentions == {parse: []}'

post() { # post OUT KIND ARGS...: dry-run one message into OUT
  local out="$1"
  shift
  "$SCRIPT" "$@" --dry-run >"$out" 2>"$out.err"
}

echo "issues"
long=$(printf 'Line of detail number %s that keeps going for a while.\n' $(seq 1 60))
jq -n --arg long "$long" '{action: "opened", issue: {
  number: 501, title: "@everyone the bar vanished", html_url: "https://github.com/Ryoku-dev/ryoku/issues/501",
  created_at: "2026-10-24T10:00:00Z", labels: [{name: "bug"}],
  user: {login: "someone", html_url: "https://github.com/someone", avatar_url: "https://avatars.githubusercontent.com/u/1"},
  body: ("### System details\n\nRyoku Amaterasu 1.0.2 | niri\n\n### What'"'"'s wrong?\n\n<!-- hidden note -->\n#### Steps\n"
    + "Click [the bar](https://evil.example/phish) and see ![shot](https://example.com/a.png)\n_No response_\n```\nlog start\n" + $long + "```\n")}}' >"$work/issue.json"
GITHUB_EVENT_PATH="$work/issue.json" post "$work/issue.out" issue
truthy "$quiet" "$work/issue.out" "an issue never pings, whatever its title says"
truthy "$fits" "$work/issue.out" "a long issue fits Discord"
truthy '.embeds[0].description | (contains("<!--") or contains("](") or contains("_No response_")) | not' "$work/issue.out" \
  "hidden comments, masked links and empty form answers are gone"
truthy '.embeds[0].description | contains("the bar (https://evil.example/phish)")' "$work/issue.out" "a link shows where it points"
truthy '.embeds[0].description | startswith("**Steps**")' "$work/issue.out" "a deep heading becomes bold text"
truthy '.embeds[0].description | ([match("```"; "g")] | length) % 2 == 0' "$work/issue.out" "a cut code block is closed"
truthy '.embeds[0].description | length < 720' "$work/issue.out" "the excerpt stays short"
truthy '.embeds[0].fields[0] == {name: "System", value: "Ryoku Amaterasu 1.0.2 | niri"}' "$work/issue.out" "the form's system details become a field"

echo "pull requests"
template=$(<"$ROOT/.github/PULL_REQUEST_TEMPLATE.md")
pr() { # pr ACTION MERGED BASE BODY USERTYPE
  jq -n --arg a "$1" --argjson merged "$2" --arg base "$3" --arg body "$4" --arg type "${5:-User}" '{action: $a, pull_request: {
    number: 77, title: "[ryoku] dock: pin apps", html_url: "https://github.com/Ryoku-dev/ryoku/pull/77", draft: false,
    created_at: "2026-10-24T10:00:00Z", merged_at: "2026-10-25T10:00:00Z", closed_at: "2026-10-25T10:00:00Z",
    merged: $merged, merged_by: {login: "maintainer"}, base: {ref: $base},
    additions: 10, deletions: 2, changed_files: 1,
    user: {login: "contrib", type: $type, html_url: "https://github.com/contrib", avatar_url: "https://avatars.githubusercontent.com/u/2"},
    body: $body}}'
}
pr opened false unstable-dev "$template" >"$work/pr-empty.json"
GITHUB_EVENT_PATH="$work/pr-empty.json" post "$work/pr-empty.out" pull-request
truthy '.embeds[0] | has("description") | not' "$work/pr-empty.out" "an untouched template adds no description"
filled=${template/Describe the change and why it is needed./Pinned apps stay in the dock across restarts.}
pr opened false main "$filled" >"$work/pr-main.json"
GITHUB_EVENT_PATH="$work/pr-main.json" post "$work/pr-main.out" pull-request
check "$(jq -r '.embeds[0].description' "$work/pr-main.out")" "Pinned apps stay in the dock across restarts." "the author's own words are the description"
truthy '.embeds[0].fields[0].value | contains("unstable-dev")' "$work/pr-main.out" "a pull request into main is pointed at unstable-dev"
truthy "$quiet" "$work/pr-main.out" "a pull request never pings"
pr closed true unstable-dev "$filled" >"$work/pr-merged.json"
GITHUB_EVENT_PATH="$work/pr-merged.json" post "$work/pr-merged.out" pull-request
check "$(jq -r '.embeds[0].footer.text' "$work/pr-merged.out")" "Merged by maintainer" "a merge credits who merged it"
pr closed false unstable-dev "$filled" >"$work/pr-closed.json"
GITHUB_EVENT_PATH="$work/pr-closed.json" "$SCRIPT" pull-request --dry-run >"$work/pr-closed.out"
check "$(cat "$work/pr-closed.out")" "Nothing to announce for this pull-request event." "a pull request closed unmerged is not news"
pr opened false unstable-dev "$filled" Bot >"$work/pr-bot.json"
GITHUB_EVENT_PATH="$work/pr-bot.json" "$SCRIPT" pull-request --dry-run >"$work/pr-bot.out"
check "$(cat "$work/pr-bot.out")" "Nothing to announce for this pull-request event." "bot pull requests stay out of the feed"

echo "commits and the unstable roundup"
repo="$work/repo"
git init -q -b unstable-dev "$repo"
g() { git -C "$repo" -c user.name="${AUTHOR:-Dev}" -c user.email="${EMAIL:-dev@example.com}" "$@"; }
g commit -q --allow-empty -m "[ryoku] base"
base=$(g rev-parse HEAD)
g commit -q --allow-empty -m "[ryoku] dock: pin apps" -m "Note: New: pin an app from its menu"
AUTHOR='github-actions[bot]' EMAIL='41898282+github-actions[bot]@users.noreply.github.com' \
  g commit -q --allow-empty -m "release: bump unstable to 1.0.3"
g commit -q --allow-empty -m "[system] power: keep the lid closed" -m "Note: Fixed: the lid no longer wakes the screen"
g commit -q --allow-empty -m "[docs] typo"
AUTHOR='github-actions[bot]' EMAIL='41898282+github-actions[bot]@users.noreply.github.com' \
  g commit -q --allow-empty -m "release: bump unstable to 1.0.4"
tip=$(g rev-parse HEAD)
(cd "$repo" && post "$work/commits.out" commits --from "$base" --to "$tip")
check "$(jq -r '.embeds[0].title' "$work/commits.out")" "3 new commits on unstable-dev" "release bot bumps are not counted"
truthy '.embeds[0].description | contains("bump") | not' "$work/commits.out" "release bot bumps are not listed"
truthy '.embeds[0].description | contains("**system** · 1")' "$work/commits.out" "commits group by area"
bump_only=$(g rev-parse HEAD~1)
(cd "$repo" && "$SCRIPT" commits --from "$bump_only" --to "$tip" --dry-run >"$work/commits-bot.out")
check "$(cat "$work/commits-bot.out")" "Nothing to announce for this commits event." "a push of only bumps posts nothing"
(cd "$repo" && post "$work/unstable.out" unstable --from "$base" --to "$tip")
truthy '.embeds[0].description | startswith("**2 changes**")' "$work/unstable.out" "the roundup counts the notes"
truthy '.embeds[0].description | contains("pin an app from its menu") and contains("the lid no longer wakes the screen")' \
  "$work/unstable.out" "the roundup lists the notes"
truthy "$quiet" "$work/unstable.out" "the roundup never pings"
(cd "$repo" && "$SCRIPT" unstable --from "$(g rev-parse HEAD~2)" --to "$tip" --dry-run >"$work/unstable-none.out")
check "$(cat "$work/unstable-none.out")" "Nothing to announce for this unstable event." "no notes, no roundup"

echo "release announcement"
{
  echo "## Ryoku Amaterasu 1.0.3"
  echo
  printf 'The sun came up\nover the islands.\n\n'
  echo "### New"
  for i in $(seq 1 300); do echo "- new thing number $i that does something nice for people who use it every day"; done
  echo "  ![](https://example.com/demo.gif)"
  echo "### Fixed"
  for i in $(seq 1 450); do echo "- fixed thing number $i that used to annoy people on some machines and now behaves"; done
  echo "### Removed"
  for i in $(seq 1 40); do echo "- removed thing $i"; done
} >"$work/notes.md"
release() { "$SCRIPT" release --tag v1.0.3 --notes-file "$work/notes.md" --title "Ryoku Amaterasu 1.0.3" --live "Arch,CachyOS" --dry-run; }
DISCORD_RELEASE_ROLE_ID=1541644693295861900 release >"$work/release.out"
truthy "$fits" "$work/release.out" "a release with 790 notes fits Discord"
truthy '.allowed_mentions == {parse: [], roles: ["1541644693295861900"]} and (.content | startswith("<@&1541644693295861900> "))' \
  "$work/release.out" "the release pings the release role and nothing else"
truthy '.embeds[0].description | startswith("The sun came up over the islands.")' "$work/release.out" "the story reads as one paragraph"
truthy '.embeds[0].description | contains("**300 new · 450 fixed · 40 removed**")' "$work/release.out" "the release counts every note"
truthy '.embeds[1].description | contains("**Fixed**") and contains("**Removed**")' "$work/release.out" \
  "fixes and removals still show beside a long New list"
truthy '.embeds[0].image.url == "https://example.com/demo.gif"' "$work/release.out" "a release demo becomes the picture"
DISCORD_RELEASE_ROLE_ID=everyone release >"$work/release-norole.out"
truthy "$quiet"' and (.content | startswith("**"))' "$work/release-norole.out" "a malformed role id pings no one"

g commit -q --allow-empty -m "[release] cut 1.0.3"
mkdir -p "$repo/docs/media/showroom" && : >"$repo/docs/media/showroom/one.webp"
g add docs && g commit -q -m "[docs] showroom"
g tag v1.0.3
printf '## Ryoku 1.0.3\n\n### Fixed\n- a fix\n' >"$work/plain.md"
(cd "$repo" && "$SCRIPT" release --tag v1.0.3 --notes-file "$work/plain.md" --live Arch --dry-run >"$work/release-plain.out")
check "$(jq -r '.embeds[0].image.url' "$work/release-plain.out")" \
  "https://raw.githubusercontent.com/Ryoku-dev/ryoku/v1.0.3/docs/media/showroom/one.webp" \
  "a release without a demo shows a showroom desktop from its own tag"

echo "CI alerts"
"$SCRIPT" gate-failed --sha "$tip" --run https://example.com/run --checks "Delivery, Shell QML lint" --dry-run >"$work/gate.out"
check "$(jq -r '.embeds[0].fields[0].value' "$work/gate.out")" $'Delivery\nShell QML lint' "the failing checks are listed"
"$SCRIPT" iso --status success --variant plain --image ryoku.iso --publish true --stage stable --run https://example.com/run --dry-run >"$work/iso.out"
check "$(jq -r '.embeds[0].title' "$work/iso.out")" "Arch ISO published" "the plain ISO is the Arch edition"
truthy '[.embeds[0].fields[] | select(.name == "Image")][0].value | contains("https://iso.ryoku.dev/stable/ryoku.iso")' \
  "$work/iso.out" "a published ISO links its download"
"$SCRIPT" iso --status failure --variant void --publish true --run https://example.com/run --dry-run >"$work/iso-fail.out"
truthy '.embeds[0].title == "Void ISO build failed" and (.embeds[0] | has("description") | not)' "$work/iso-fail.out" \
  "a failed ISO says so without a download"

echo "sending"
stub="$work/bin"
mkdir -p "$stub"
cat >"$stub/curl" <<EOF
#!/usr/bin/env bash
out=""; url=""
while ((\$#)); do case "\$1" in -o) out=\$2; shift ;; -w|-H|-X|--max-time|--data-binary) shift ;; -*) ;; *) url=\$1 ;; esac; shift; done
cat >/dev/null
n=\$((\$(cat "$work/calls" 2>/dev/null || echo 0) + 1)); echo "\$n" >"$work/calls"
echo "\$url" >>"$work/urls"
code=\$(sed -n "\${n}p" "$work/codes")
case "\$code" in 429) echo '{"retry_after": 0.2}' >"\$out" ;; 200) echo '{"id": "42"}' >"\$out" ;; *) echo '{"message": "bad"}' >"\$out" ;; esac
printf '%s' "\$code"
EOF
printf '#!/bin/sh\n:\n' >"$stub/sleep"
chmod +x "$stub/curl" "$stub/sleep"
send() { rm -f "$work/calls" "$work/urls"; printf '%s\n' "$@" >"$work/codes"; PATH="$stub:$PATH" "$SCRIPT" gate-failed --sha "$tip" --run https://example.com/run; }

out=$(send 200)
check "$?:$(cat "$work/calls" 2>/dev/null || echo 0)" "0:0" "no webhook: skipped, nothing sent"
check "$out" "::notice::no Discord webhook configured for this message; skipped" "no webhook says why"
export DISCORD_WEBHOOK=https://discord.example/api/webhooks/1/token
send 429 200 >/dev/null
check "$?:$(cat "$work/calls")" "0:2" "a rate limit is waited out and the message sent"
check "$(head -1 "$work/urls")" "https://discord.example/api/webhooks/1/token?wait=true" "the send waits for Discord to confirm"
send 400 >/dev/null 2>&1
check "$?:$(cat "$work/calls")" "1:1" "a refused message fails without retrying"
DISCORD_WEBHOOK="https://discord.example/api/webhooks/1/token?thread_id=9" send 200 >/dev/null
check "$(cat "$work/urls")" "https://discord.example/api/webhooks/1/token?thread_id=9&wait=true" "a thread webhook keeps its thread"
unset DISCORD_WEBHOOK

((fail == 0)) && echo "ryoku-discord: all checks passed"
exit "$fail"
