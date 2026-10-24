package main

import "strings"

// ownership.go generates ownership.md: who writes each config path on this
// machine, so an agent never edits what an update overwrites. The body is the
// live `ryoku owner --map` output; when that verb is missing or fails, a plain
// fallback states the rules and points the agent at `ryoku owner <path>`.

const ownershipHeader = "# Ownership\n" +
	"\n" +
	"Who owns each config path on this machine, and where a change belongs so an\n" +
	"update never overwrites it. Generated: the content between the markers is\n" +
	"overwritten on every reindex."

// writeOwnershipVaultDoc writes ownership.md.
func writeOwnershipVaultDoc() error {
	return writeVaultDoc("ownership.md", ownershipHeader, ownershipBody())
}

// ownershipBody returns the `ryoku owner --map` markdown body, or the fallback
// when the CLI does not yet carry the verb.
func ownershipBody() string {
	if out, ok := probe(10, "ryoku", "owner", "--map"); ok {
		if body := strings.TrimRight(out, "\n"); strings.HasPrefix(strings.TrimSpace(body), "##") {
			return body
		}
	}
	return ownershipFallback
}

// ownershipFallback states the rules in plain words when `ryoku owner --map` is
// unavailable, and tells the agent to use `ryoku owner <path>` once it lands.
const ownershipFallback = "## The rule\n" +
	"\n" +
	"`ryoku update` re-lays the files Ryoku ships, so a change made in one of them\n" +
	"is lost on the next update. Put every change where an update leaves it alone.\n" +
	"\n" +
	"- **Never edit what an update overwrites:** `~/.config/quickshell` and every\n" +
	"  shipped file. Reading them is fine.\n" +
	"- **Prefer the tool's own user file.** Many configs read a dedicated override\n" +
	"  the package never ships and never touches (the compositor's `user.*` file,\n" +
	"  `kitty/user.conf`, `fish/user.fish`, and the like). Put the tweak there.\n" +
	"- **Fork a whole file** you must change by dropping your copy at the mirrored\n" +
	"  path under `~/.config/ryoku/user_edits/`; it wins over Ryoku's copy on every\n" +
	"  update. `ryoku reset <path>` hands it back.\n" +
	"- **Drive the stores under `~/.config/ryoku/` through their GUI or command**\n" +
	"  (Ryoku Settings, `ryoku-shell`, `ryogami`), never by hand, so one writer\n" +
	"  stays in charge.\n" +
	"\n" +
	"Once the `ryoku` CLI carries it, run `ryoku owner <path>` to classify any path\n" +
	"and print exactly where the change should go."
