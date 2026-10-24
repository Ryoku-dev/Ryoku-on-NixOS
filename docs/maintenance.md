# Maintaining the NixOS port

Ryoku on NixOS tracks the Ryoku desktop closely while replacing the parts that
are specific to Arch Linux with Nix-native equivalents.

The important distinction is ownership. This repository does not need a second
copy of every desktop feature just because the host distribution is different.
It needs a clear platform boundary and a repeatable way to review upstream
changes.

## Source boundaries

The repository has three practical ownership classes.

| Area | Owner | Rule |
| --- | --- | --- |
| `ryoku/` | Shared Ryoku desktop | Keep behavior aligned with upstream unless the host platform genuinely changes it |
| `nix/` | NixOS port | Package ownership, NixOS modules, installer integration, system bridges and Nix-specific compatibility |
| `installation/`, `system/`, `release/` | Upstream Arch reference | Useful for parity work, but not the NixOS implementation |

A NixOS fix should not be buried in shared desktop code if the same behavior can
be expressed at the package/module boundary. Conversely, a real desktop bug
should not be hidden behind a Nix-only workaround when upstream has the same
problem.

## Upstream sync workflow

When upstream Ryoku moves:

1. Identify the upstream commit/range and the user-visible changes it contains.
2. Classify each change as shared desktop behavior, Arch-only integration or a
   cross-platform bug fix.
3. Bring shared desktop changes across with the smallest practical divergence.
4. Replace Arch package/service/filesystem assumptions with Nix-native
   equivalents under `nix/`.
5. Build the narrowest affected Nix outputs first.
6. Run the relevant unit/parser/lint checks.
7. Test user-visible runtime behavior on NixOS.
8. If a bug is also present upstream and the fix is portable, send the fix
   upstream rather than maintaining two independent patches.

The goal is not zero divergence. The goal is deliberate divergence with a clear
reason.

## NixOS-specific seams

Examples of work that belongs to the port include:

- package ownership and immutable store paths;
- Home Manager and materialized config ownership;
- NixOS services, portals and systemd integration;
- installer edits to an existing flake;
- NixOS generations, update channels and rollback;
- host/runtime bridges where an upstream component expects an Arch-specific
  command, path or package manager;
- ABI pinning for compositor/plugin combinations that must move together.

Keep these seams narrow enough that an upstream sync does not require
reimplementing the desktop.

## Validation ladder

Use the smallest useful check while developing, then widen validation before a
release.

### 1. Static and focused checks

Examples:

```bash
bash -n path/to/script
qmllint path/to/file.qml
python3 nix/tests/test-ryoku-install-edit.py
```

The repository also carries focused CI for shell, QML, Go, installer and
integration behavior.

### 2. Nix evaluation and package builds

The root flake is the canonical Nix interface:

```bash
nix flake check
```

For iterative work, build the affected output directly instead of rebuilding the
entire desktop after every edit.

### 3. Runtime verification

Runtime evidence matters for changes that CI cannot prove, especially:

- compositor/window-manager behavior;
- multi-monitor and display configuration;
- GPU and suspend/resume behavior;
- audio/Bluetooth integration;
- portals and desktop-session startup;
- installer/update/rollback flows.

Record what was tested in the pull request. "Builds successfully" and "works on
a running system" are different claims.

## Pull-request evidence

A useful pull request should answer four questions without making the reviewer
reverse-engineer the patch:

1. Why was this change needed?
2. Which ownership boundary does it touch?
3. How was it verified?
4. Does the same issue or change belong upstream too?

That context is more valuable than a long generated-looking summary.

## Tool-assisted development

Editors, linters, code generators and code-assistance tools are all just tools.
The project does not use them as evidence that a patch is correct.

The person submitting a change is responsible for understanding it, keeping the
diff focused, removing placeholder/chat residue, and providing real validation.
There is no project-specific ban on code-assistance tools or their attribution;
review quality is based on the patch and its evidence.

## Release discipline

Prefer one logical change per commit. Current commits use conventional subjects
such as:

```text
fix(installer): preserve imported multi-host flakes
feat(hub): expose NixOS update channels
docs: explain compositor ownership
release: bump stable channel to 0.63.3-beta.19
```

Legacy impact prefixes such as `[ryoku]` remain accepted while history converges
on the simpler format.

For user-visible changes, keep the existing `Note: New|Fixed|Removed: ...`
release trailer so release automation can harvest the plain-language result.
