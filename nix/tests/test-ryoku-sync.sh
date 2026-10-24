#!/usr/bin/env bash
set -euo pipefail

script=$(cd "$(dirname "${BASH_SOURCE[0]}")/../sync" && pwd)/ryoku-sync
root=$(mktemp -d "${TMPDIR:-/tmp}/test-ryoku-sync.XXXXXX")
trap 'rm -rf "$root"' EXIT

upstream="$root/upstream"
fork_seed="$root/fork-seed"
fork_bare="$root/fork.git"
runner="$root/runner"
checked="$root/checked.json"
gh_log="$root/gh.log"
output="$root/output"
gh_state="$root/gh-state"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local want=$1 got=$2 message=$3
  [[ $got == "$want" ]] || fail "$message (want '$want', got '$got')"
}

assert_file_at() {
  local repo=$1 commit=$2 path=$3 want=$4 got
  got=$(git -C "$repo" show "$commit:$path") || fail "$path missing at $commit"
  assert_eq "$want" "$got" "$path content"
}

assert_absent_at() {
  local repo=$1 commit=$2 path=$3
  ! git -C "$repo" cat-file -e "$commit:$path" 2>/dev/null \
    || fail "$path should be absent at $commit"
}

commit_all() {
  local repo=$1 subject=$2 author=${3:-Test Maintainer}
  git -C "$repo" add -A
  GIT_AUTHOR_NAME=$author GIT_AUTHOR_EMAIL=test@example.com \
    GIT_COMMITTER_NAME=$author GIT_COMMITTER_EMAIL=test@example.com \
    git -C "$repo" commit -q -m "$subject"
}

write_checked() {
  local commit=$1 state=${2:-passed}
  if [[ $state == passed ]]; then
    printf '{"state":"passed","commit":"%s"}\n' "$commit" >"$checked"
  else
    printf '{"state":"building","passed":{"commit":"%s"}}\n' "$commit" >"$checked"
  fi
}

run_sync() {
  local lane=$1
  shift
  : >"$output"
  (
    cd "$runner"
    RYOKU_CHECKED_URL="file://$checked" \
      RYOKU_SYNC_GH="$root/gh-stub" \
      GITHUB_REPOSITORY=Ryoku-dev/Ryoku-on-NixOS \
      "$script" --lane "$lane" --upstream "$upstream" --fork-remote origin "$@"
  ) >"$output"
}

mkdir -p "$gh_state"
cat >"$root/gh-stub" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$@" >>"${GH_LOG:?}"
printf '\n' >>"$GH_LOG"

endpoint=${2:-}
method=GET
body=""
head=""
while (($#)); do
  case "$1" in
    --method)
      method=$2
      shift 2
      ;;
    -f)
      field=$2
      case "$field" in
        body=*) body=${field#body=} ;;
        head=*) head=${field#head=} ;;
      esac
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

case "$endpoint" in
  repos/*/pulls)
    lane=${head##*/}
    if [[ $method == POST ]]; then
      if [[ $lane == unstable ]]; then number=17; else number=18; fi
      printf '%s\n' "$number" >"$GH_STATE_DIR/$lane.number"
      printf '%s' "$body" >"$GH_STATE_DIR/$lane.body"
      printf '%s\n' "$number"
    elif [[ -f $GH_STATE_DIR/$lane.number ]]; then
      cat "$GH_STATE_DIR/$lane.number"
    else
      printf '\n'
    fi
    ;;
  repos/*/pulls/*)
    number=${endpoint##*/}
    if [[ $number == 17 ]]; then lane=unstable; else lane=stable; fi
    if [[ $method == PATCH ]]; then
      printf '%s' "$body" >"$GH_STATE_DIR/$lane.body"
    elif [[ -f $GH_STATE_DIR/$lane.body ]]; then
      cat "$GH_STATE_DIR/$lane.body"
    fi
    ;;
esac
GH
chmod +x "$root/gh-stub"
export GH_LOG="$gh_log"
export GH_STATE_DIR="$gh_state"

mkdir -p "$upstream"
git -C "$upstream" init -q -b unstable-dev
git -C "$upstream" config user.name 'Test Maintainer'
git -C "$upstream" config user.email test@example.com
mkdir -p "$upstream/nix" "$upstream/.github" "$upstream/gone" "$upstream/elsewhere" \
  "$upstream/installation/recovery" "$upstream/component"
printf '1.0.0\n' >"$upstream/VERSION"
printf 'base\n' >"$upstream/shared.txt"
printf 'base conflict\n' >"$upstream/conflict.txt"
printf 'base deleted\n' >"$upstream/remove-me.txt"
printf 'old directory file\n' >"$upstream/gone/existing.txt"
printf 'upstream nix base\n' >"$upstream/nix/upstream.txt"
printf 'upstream flake base\n' >"$upstream/flake.nix"
printf 'upstream workflow base\n' >"$upstream/.github/workflow.yml"
printf 'base stale installer\n' >"$upstream/installation/stale.txt"
printf 'base recovery\n' >"$upstream/installation/recovery/keep.txt"
printf 'base component changelog\n' >"$upstream/component/CHANGELOG.md"
printf 'old upstream copy\n' >"$upstream/stale-copy.txt"
printf 'base custom copy\n' >"$upstream/custom-copy.txt"
commit_all "$upstream" 'feat: initial upstream history'
printf 'current upstream copy\n' >"$upstream/stale-copy.txt"
commit_all "$upstream" 'feat: base'
base=$(git -C "$upstream" rev-parse HEAD)

# Build the fork from the common upstream base, then make its NixOS adaptations.
git clone -q "$upstream" "$fork_seed"
git -C "$fork_seed" switch -q -c main
mkdir -p "$fork_seed/nix/sync"
printf '%s\n' "$base" >"$fork_seed/nix/sync/ryoku-commit"
printf 'fork nix\n' >"$fork_seed/nix/upstream.txt"
printf 'fork flake\n' >"$fork_seed/flake.nix"
printf 'fork workflow\n' >"$fork_seed/.github/workflow.yml"
printf 'fork only\n' >"$fork_seed/fork.txt"
mkdir -p "$fork_seed/tests"
printf 'fork-only test helper\n' >"$fork_seed/tests/fork-only-helper.py"
printf 'old upstream copy\n' >"$fork_seed/stale-copy.txt"
printf 'fork custom copy\n' >"$fork_seed/custom-copy.txt"
rm "$fork_seed/remove-me.txt" "$fork_seed/gone/existing.txt"
commit_all "$fork_seed" 'feat(nix): initial port'
fork_base=$(git -C "$fork_seed" rev-parse HEAD)
git -C "$fork_seed" branch -f unstable-dev
git init -q --bare "$fork_bare"
git -C "$fork_seed" remote add fork "$fork_bare"
git -C "$fork_seed" push -q fork main unstable-dev
git --git-dir="$fork_bare" symbolic-ref HEAD refs/heads/main
git clone -q "$fork_bare" "$runner"
git -C "$runner" config user.name 'Test Maintainer'
git -C "$runner" config user.email test@example.com

# A clean target exercises owned paths, VERSION, deletes and upstream additions.
printf '1.1.0\n' >"$upstream/VERSION"
printf 'upstream changed\n' >"$upstream/shared.txt"
printf 'upstream changed deleted file\n' >"$upstream/remove-me.txt"
printf 'upstream nix changed\n' >"$upstream/nix/upstream.txt"
printf 'upstream flake changed\n' >"$upstream/flake.nix"
printf 'upstream workflow changed\n' >"$upstream/.github/workflow.yml"
printf 'new in removed directory\n' >"$upstream/gone/new.txt"
printf 'new elsewhere\n' >"$upstream/elsewhere/new.txt"
commit_all "$upstream" 'feat: clean upstream changes'
target_clean=$(git -C "$upstream" rev-parse HEAD)
write_checked "$target_clean"
run_sync unstable

git -C "$runner" fetch -q origin
clean_sync=$(git -C "$runner" rev-parse origin/sync/unstable)
clean_parents=$(git -C "$runner" show -s --format=%P "$clean_sync")
assert_eq "$fork_base" "$clean_parents" 'clean sync must have one fork parent'
assert_file_at "$runner" "$clean_sync" shared.txt 'upstream changed'
assert_file_at "$runner" "$clean_sync" nix/sync/ryoku-commit "$target_clean"
assert_file_at "$runner" "$clean_sync" nix/upstream.txt 'fork nix'
assert_file_at "$runner" "$clean_sync" flake.nix 'fork flake'
assert_file_at "$runner" "$clean_sync" .github/workflow.yml 'fork workflow'
assert_file_at "$runner" "$clean_sync" VERSION '1.1.0'
assert_file_at "$runner" "$clean_sync" elsewhere/new.txt 'new elsewhere'
assert_file_at "$runner" "$clean_sync" tests/fork-only-helper.py 'fork-only test helper'
assert_absent_at "$runner" "$clean_sync" remove-me.txt
assert_absent_at "$runner" "$clean_sync" gone/new.txt
[[ $(<"$output") == *'Conflicts: none'* ]] || fail 'clean sync reported conflicts'
assert_file_at "$runner" "$clean_sync" stale-copy.txt 'current upstream copy'
assert_file_at "$runner" "$clean_sync" custom-copy.txt 'fork custom copy'
[[ $(<"$gh_state/unstable.body") == *'`stale-copy.txt`'* ]] \
  || fail 'stale-copy refresh missing from pull request body'
[[ $(<"$gh_state/unstable.body") == *"<!-- ryoku-sync-head: $clean_sync -->"* ]] \
  || fail 'pull request body did not record the bot branch head'

# A real content conflict remains marked in the generated commit and is listed.
git -C "$fork_seed" switch -q unstable-dev
printf 'fork conflict\n' >"$fork_seed/conflict.txt"
printf 'fork stale installer\n' >"$fork_seed/installation/stale.txt"
printf 'fork recovery\n' >"$fork_seed/installation/recovery/keep.txt"
printf 'fork component changelog\n' >"$fork_seed/component/CHANGELOG.md"
commit_all "$fork_seed" 'fix(nix): adapt conflicting file'
fork_conflict_base=$(git -C "$fork_seed" rev-parse HEAD)
git -C "$fork_seed" push -q fork unstable-dev
printf 'upstream conflict\n' >"$upstream/conflict.txt"
printf 'upstream stale installer\n' >"$upstream/installation/stale.txt"
printf 'upstream recovery\n' >"$upstream/installation/recovery/keep.txt"
printf 'upstream component changelog\n' >"$upstream/component/CHANGELOG.md"
commit_all "$upstream" 'feat: conflict upstream file'
target_conflict=$(git -C "$upstream" rev-parse HEAD)
write_checked "$target_conflict"
run_sync unstable
git -C "$runner" fetch -q origin
conflict_sync=$(git -C "$runner" rev-parse origin/sync/unstable)
assert_eq "$fork_conflict_base" "$(git -C "$runner" show -s --format=%P "$conflict_sync")" \
  'conflict sync must have one fork parent'
conflict_text=$(git -C "$runner" show "$conflict_sync:conflict.txt")
[[ $conflict_text == *'<<<<<<<'* && $conflict_text == *'======='* && $conflict_text == *'>>>>>>>'* ]] \
  || fail 'content conflict markers missing'
[[ $(<"$output") == *'conflict.txt'* ]] || fail 'conflict path not listed'
assert_file_at "$runner" "$conflict_sync" installation/stale.txt 'upstream stale installer'
assert_file_at "$runner" "$conflict_sync" component/CHANGELOG.md 'upstream component changelog'
recovery_text=$(git -C "$runner" show "$conflict_sync:installation/recovery/keep.txt")
[[ $recovery_text == *'<<<<<<<'* && $recovery_text == *'======='* && $recovery_text == *'>>>>>>>'* ]] \
  || fail 'upstream-wins exception did not stay conflicted'
[[ $(<"$output") == *'installation/recovery/keep.txt'* ]] \
  || fail 'upstream-wins exception path not listed'
[[ $(<"$output") != *'installation/stale.txt'* ]] \
  || fail 'upstream-wins path remained conflicted'
[[ $(<"$output") != *'component/CHANGELOG.md'* ]] \
  || fail 'basename upstream-wins path remained conflicted'

# A checked target advances through release bump commits only.
printf 'bump one\n' >"$upstream/bump-one.txt"
commit_all "$upstream" 'release: bump unstable to 1.1.1' 'github-actions[bot]'
printf 'bump two\n' >"$upstream/bump-two.txt"
commit_all "$upstream" 'release: bump unstable to 1.1.2' 'github-actions[bot]'
bot_tip=$(git -C "$upstream" rev-parse HEAD)
write_checked "$target_conflict" building
run_sync unstable --dry-run
[[ $(<"$output") == *"Target: $bot_tip"* ]] || fail 'bot-only bump range did not resolve to tip'

# Any human-authored upstream commit keeps the checked target P.
printf 'human\n' >"$upstream/human.txt"
commit_all "$upstream" 'fix: human change'
run_sync unstable --dry-run
[[ $(<"$output") == *"Target: $target_conflict"* ]] || fail 'human range did not keep passed target'

# Stable uses the newest compatible unstable fork state, not a newer incompatible one.
git -C "$upstream" tag v1.1.0 "$target_clean"
git -C "$fork_seed" switch -q unstable-dev
printf '%s\n' "$target_clean" >"$fork_seed/nix/sync/ryoku-commit"
printf 'stable-compatible adaptation\n' >"$fork_seed/adaptation.txt"
commit_all "$fork_seed" 'sync: record clean target'
stable_compatible=$(git -C "$fork_seed" rev-parse HEAD)
printf '%s\n' "$target_conflict" >"$fork_seed/nix/sync/ryoku-commit"
printf 'newer incompatible state\n' >"$fork_seed/adaptation.txt"
commit_all "$fork_seed" 'sync: record newer target'
git -C "$fork_seed" push -q fork unstable-dev
run_sync stable
git -C "$runner" fetch -q origin
stable_sync=$(git -C "$runner" rev-parse origin/sync/stable)
assert_eq "$fork_base" "$(git -C "$runner" show -s --format=%P "$stable_sync")" \
  'stable sync parent must be current main'
assert_file_at "$runner" "$stable_sync" adaptation.txt 'stable-compatible adaptation'
[[ $stable_compatible != "$(git -C "$fork_seed" rev-parse unstable-dev)" ]] \
  || fail 'stable fixture did not include a newer fork state'

# A newest release tag outside all recorded upstream histories is a clean no-op.
git -C "$upstream" switch -q --orphan unrelated-release
git -C "$upstream" rm -q -r --ignore-unmatch .
printf '9.0.0\n' >"$upstream/VERSION"
printf 'unrelated\n' >"$upstream/unrelated.txt"
commit_all "$upstream" 'release: unrelated'
git -C "$upstream" tag v9.0.0
run_sync stable --dry-run
[[ $(<"$output") == *'no fork state matches the stable release yet'* ]] \
  || fail 'stable no-match notice missing'
git -C "$upstream" switch -q unstable-dev

# A bot branch without an open PR is reusable after its head was merged.
current_base=$(git --git-dir="$fork_bare" rev-parse refs/heads/unstable-dev)
sync_tree=$(git --git-dir="$fork_bare" show -s --format=%T "$conflict_sync")
merged_base=$(printf 'merge sync fixture\n' \
  | GIT_AUTHOR_NAME='Test Maintainer' GIT_AUTHOR_EMAIL=test@example.com \
    GIT_COMMITTER_NAME='Test Maintainer' GIT_COMMITTER_EMAIL=test@example.com \
    git --git-dir="$fork_bare" commit-tree "$sync_tree" -p "$current_base" -p "$conflict_sync")
git --git-dir="$fork_bare" update-ref refs/heads/unstable-dev "$merged_base" "$current_base"
rm "$gh_state/unstable.number" "$gh_state/unstable.body"
printf 'later upstream\n' >"$upstream/later.txt"
commit_all "$upstream" 'fix: later upstream change'
later_target=$(git -C "$upstream" rev-parse HEAD)
write_checked "$later_target"
run_sync unstable
merged_reuse=$(git --git-dir="$fork_bare" rev-parse refs/heads/sync/unstable)
[[ $merged_reuse != "$conflict_sync" ]] || fail 'merged bot branch was not reused'
[[ $(<"$gh_state/unstable.body") == *"<!-- ryoku-sync-head: $merged_reuse -->"* ]] \
  || fail 'updated pull request marker does not match pushed head'

# Once a maintainer commits on the marked branch, the bot leaves it alone.
protector="$root/protector"
git clone -q "$fork_bare" "$protector"
git -C "$protector" switch -q --track origin/sync/unstable
printf 'maintainer\n' >"$protector/maintainer.txt"
commit_all "$protector" 'fix(nix): resolve sync locally'
git -C "$protector" push -q origin HEAD:sync/unstable
protected_before=$(git --git-dir="$fork_bare" rev-parse refs/heads/sync/unstable)
printf 'latest upstream\n' >"$upstream/latest.txt"
commit_all "$upstream" 'fix: latest upstream change'
write_checked "$(git -C "$upstream" rev-parse HEAD)"
run_sync unstable
protected_after=$(git --git-dir="$fork_bare" rev-parse refs/heads/sync/unstable)
assert_eq "$protected_before" "$protected_after" 'maintainer-owned sync branch was rewritten'
[[ $(<"$output") == *'has a maintainer commit'* ]] || fail 'protected branch notice missing'
[[ $(<"$gh_state/unstable.body") == *'Newer Ryoku waiting: '* ]] || fail 'waiting note missing from PR body'
run_sync unstable
[[ $(grep -c 'Newer Ryoku waiting: ' "$gh_state/unstable.body") == 1 ]] || fail 'waiting note repeated'
[[ $(<"$gh_state/unstable.body") == *"<!-- ryoku-sync-head: "* ]] || fail 'waiting note dropped the head marker'

printf 'ok: ryoku sync clean merge, conflict, lane targets and branch protection\n'
