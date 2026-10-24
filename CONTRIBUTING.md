# Contributing to Ryoku on NixOS

Ryoku on NixOS is a maintained platform port of the Ryoku desktop. Contributions
are easiest to review when they keep the upstream/NixOS boundary clear and show
how the change was actually tested.

Start with:

- [`docs/maintenance.md`](docs/maintenance.md) for port ownership and upstream sync;
- [`docs/structure.md`](docs/structure.md) for the repository map;
- [`docs/nixos.md`](docs/nixos.md) for NixOS behavior and supported integration;
- [`AGENTS.md`](AGENTS.md) if you are using an automated coding tool.

## Development setup

Enter the Nix development shell:

```bash
nix develop
```

Run the desktop from a checkout when working on shared shell behavior:

```bash
nix run .#ryoku-dev
```

Run the full flake checks before a release or broad integration change:

```bash
nix flake check
```

During development, prefer the narrowest relevant package or test so failures
stay attributable to the change you are making.

## Where a change belongs

Use the platform boundary rather than the package manager as the deciding rule.

- Shared desktop/application behavior belongs under `ryoku/`.
- Nix packaging belongs under `nix/packages/`.
- NixOS machine/service integration belongs under `nix/modules/`.
- Installer and materialization entry points belong under `nix/apps/`.
- Port-specific tests belong under `nix/tests/` or `tests/`.
- Arch-oriented top-level `installation/`, `system/` and `release/` trees are
  retained for upstream parity/reference; they are not the NixOS implementation.

If a bug also exists in upstream Ryoku and the fix is portable, prefer fixing it
upstream and carrying the same correction here rather than creating a permanent
Nix-only fork.

## Verification

Test the behavior you changed, not just the syntax around it.

Typical checks include:

```bash
bash -n path/to/script
qmllint path/to/file.qml
python3 nix/tests/test-ryoku-install-edit.py
nix build .#ryoku-shell
nix flake check
```

Hardware-facing and session-runtime changes need runtime evidence. In the pull
request, record the compositor/session used and what you actually exercised.

## Commits

Use short conventional subjects. Preferred forms are:

```text
fix(installer): preserve imported multi-host flakes
feat(hub): expose NixOS update channels
docs: document Niri workspace ownership
test(parser): cover dotted flake inputs
release: bump stable channel to 0.63.3-beta.19
```

Accepted types are `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `build`,
`ci`, `chore` and `release`.

Legacy impact prefixes such as `[ryoku]` or `[docs]` are still accepted so old
and new history remain compatible, but new work should prefer the conventional
form.

Keep each commit focused. Put technical explanation in the body when it helps
future maintainers understand why the change exists.

### Release-note trailers

User-visible changes keep the existing release trailer format:

<<<<<<< port (main)
```text
Note: New: expose stable and unstable update channels
Note: Fixed: preserve Home Manager-managed config symlinks
Note: Removed: retire the old update path
```

Release automation harvests these lines into the generated notes.
=======
A note only reaches a release if its commit reaches the tag intact, so `main`
takes `unstable-dev` through a merge commit, never a squash, and a release is the
**Stable Release** workflow run on `main` (`bump_type: none` tags the version
`main` carries). Never squash-merge into a release branch: squashing collapses
commits and drops their notes.

Nothing reaches `main` except a release, and only when it is ready: work and
fixes go to `unstable-dev`. Every push there runs the **Testing gate**, which
waits for all required checks and then records the commit in
`channels/testing/checked.json`; testers on `ryoku track unstable` build that
commit from source on their next `ryoku update`, about six minutes after the
push. The package publishers run their own gate on the same checks before they
upload the testing repositories, so a red check never reaches a channel. Wait
for the Testing gate, not for the publishers. GitHub accepts changes to `main`
only through a pull request: a release merges `unstable-dev` into `main` with a
merge commit and then fast-forwards `unstable-dev` to it, and the `pre-push` hook
refuses any direct push to `main` that does not name itself with
`RYOKU_RELEASE_PUSH=1`. A `VERSION` bump the workflow commits on `main` is merged
back into `unstable-dev` before the next release. The sequence is in
`docs/development.md`, "Branches and pushing".

A release line carries a name (`CODENAME`, its story in `release/names.md`);
the release is titled with it and a line's first release opens with the story.
Starting a new line is one commit that changes `CODENAME`, adds the section
and the line's ASCII mark (`ryoku/cli/internal/updater/art/<name>.txt`),
before the release that begins it.
>>>>>>> upstream Ryoku 1.0.1 (8c97b0d)

## Pull requests

A reviewable pull request should make the engineering decision visible:

- explain why the change is needed;
- say whether it touches shared Ryoku or the NixOS-only boundary;
- include the commands/checks that were run;
- include runtime evidence where CI cannot prove the behavior;
- say whether the same bug/change applies upstream.

Keep one logical problem per pull request when practical.

## Tool-assisted contributions

Use whatever editor, linter, generator or code-assistance tooling helps you work.
The submitter still owns the patch.

Automated output is not a substitute for understanding the change, removing
placeholder/chat residue, keeping the diff focused, or providing test evidence.
The project does not ban code-assistance tools or their attribution; patches are
reviewed on technical quality and reproducibility.

## Reporting bugs

For NixOS-port bugs, open an issue in this repository with:

- NixOS version/channel;
- Ryoku version/channel;
- compositor (Hyprland or Niri where applicable);
- relevant hardware when the issue is hardware-facing;
- exact reproduction steps;
- logs or command output needed to demonstrate the failure.

For a bug that is clearly shared with upstream Ryoku, link the upstream issue or
open one there as well.

Security reports follow [`SECURITY.md`](SECURITY.md).
