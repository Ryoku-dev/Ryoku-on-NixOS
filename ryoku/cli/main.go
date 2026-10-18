// ryoku = the user-facing CLI for the distro. one front door to updates,
// rollback, and the shell. It is a thin dispatcher: each command is owned by
// an internal package, orchestrating pacman / yay / snapper / materialize
// rather than reimplementing them.
//
//	ryoku update            snapshot -> the Ryoku packages (or the channel) -> deploy -> reload
//	ryoku update --system   the same, plus the distribution's own upgrade (pacman -Syu, AUR, Flatpak)
//	ryoku update --wait     wait for a channel build or source check to finish
//	ryoku update --force    update despite an in-progress build or source check
//	ryoku update -v         the same, streaming the raw output instead of the curated console
//	ryoku update --gui      the same, in the background, driven from Ryoku Hub
//	ryoku rollback          list releases + snapshots; --to <tag> moves back to a release; [id] guides a snapshot restore
//	ryoku snapshots         list snapper snapshots
//	ryoku boot-menu         Fedora's GRUB snapshot menu: sync; restore (from a look boot); restored
//	ryoku status            version, commits behind the channel, snapshot count
//	ryoku materialize       lay the base configs into ~/.config (override-safe)
//	ryoku reset [path]      drop a user_edits override, back to the Ryoku default
//	ryoku reload            restart the shell + reload Hyprland
//	ryoku deploy            DEV ONLY: build + materialize from a checkout
//	ryoku recovery          last resort: reset to main + redeploy (overwrites configs)
//	ryoku doctor            run convergent reconcilers (also runs inside update)
//	ryoku verify            report box-vs-release-package-set drift (read-only)
//	ryoku debug             print a shareable diagnostic bundle for bug reports
//
// The concerns live in their own folders: internal/updater (update, status,
// rollback, channel, run-state, materialize, version), internal/doctor (the
// convergent reconcilers), and internal/sys (shared low-level primitives).
package main

import (
	"errors"
	"fmt"
	"os"

	"ryoku-cli/internal/doctor"
	"ryoku-cli/internal/importer"
	"ryoku-cli/internal/keyboard"
	"ryoku-cli/internal/keyring"
	"ryoku-cli/internal/securitykey"
	"ryoku-cli/internal/sys"
	"ryoku-cli/internal/updater"

	i18n "ryoku-i18n"
)

func main() {
	scrubQuickshellCrashEnv()
	i18n.Use("") // reads /usr/share/ryoku/i18n on an installed Ryoku
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}
	var err error
	switch os.Args[1] {
	case "update":
		err = updater.Update(os.Args[2:])
	case "materialize":
		err = updater.Materialize()
	case "reset":
		err = updater.Reset(os.Args[2:])
	case "owner":
		err = updater.Owner(os.Args[2:])
	case "rollback":
		if sys.NixBackend() {
			err = fmt.Errorf("Ryoku package rollback is an Arch feature; use NixOS generation rollback on this system")
		} else {
			err = updater.Rollback(os.Args[2:])
		}
	case "boot-guard":
		if sys.NixBackend() {
			err = fmt.Errorf("the Arch Ryoku boot guard is not used on NixOS; recovery belongs to NixOS generations")
		} else {
			err = updater.BootGuard(os.Args[2:])
		}
	case "boot-menu":
		err = updater.BootMenu(os.Args[2:])
	case "snapshots":
		err = updater.Snapshots()
	case "status":
		err = updater.Status(os.Args[2:])
	case "version", "--version", "-v":
		err = updater.Version(os.Args[2:])
	case "reload":
		err = sys.Run("ryoku-shell", "reload")
	case "wm":
		cmdWm(os.Args[2:])
	case "deploy":
		err = updater.Deploy(os.Args[2:])
	case "recovery":
		if sys.NixBackend() {
			err = fmt.Errorf("Ryoku package recovery is unavailable on NixOS; recover through the configured flake and NixOS generations")
		} else {
			err = cmdRecovery(os.Args[2:])
		}
	case "track":
		if sys.NixBackend() {
			err = updater.NixTrack(os.Args[2:])
		} else {
			err = cmdTrack(os.Args[2:])
		}
	case "plugin":
		err = cmdPlugin(os.Args[2:])
	case "doctor":
		err = doctor.Run(os.Args[2:])
	case "migrate-shell-config":
		err = doctor.MigrateShellConfig()
	case "verify":
		err = doctor.Verify(os.Args[2:])
	case "debug":
		err = doctor.Debug(os.Args[2:])
	case "keyring":
		err = keyring.Run(os.Args[2:])
	case "security-key":
		err = securitykey.Run(os.Args[2:])
	case "keyboard":
		err = keyboard.Run(os.Args[2:])
	case "import":
		err = importer.Run(os.Args[2:])
	case "-h", "--help", "help", "":
		usage()
	default:
		die("unknown command: %s", os.Args[1])
	}
	if err != nil {
		// an update failure the console already showed in full
		var shown interface{ Reported() bool }
		if errors.As(err, &shown) && shown.Reported() {
			os.Exit(1)
		}
		die("%v", err)
	}
}

func usage() {
	fmt.Print(i18n.T("Usage: ryoku <command>\n\n  update         update Ryoku packages/channel commits, redeploy and reload\n  update --system  the same, plus the host distribution package upgrade\n  update --wait  wait for an in-progress channel build/source check\n  update --force update despite an in-progress build/source check\n  update -v      stream full raw update output instead of the summary\n  update --gui   run the update in the background, driven from Ryoku Hub\n  track <chan>   NixOS: stable|unstable; packages: stable|unstable|v<tag>; --source builds a checkout\n  rollback       list releases/snapshots; --to <tag> moves back to a release; [id] guides snapshot restore\n  snapshots      list snapper snapshots\n  status         show channel, installed/latest version, pending changes and snapshots\n  version        print version/commit information (--pretty, --branch)\n  materialize    compose the Ryoku base config into ~/.config while preserving overrides\n  reset [path]   drop a user_edits override (no path: all, -y skips confirmation)\n  owner <path>   classify config ownership (--json, --map)\n  reload         restart the shell and reload the compositor\n  wm <cmd>       provider-backed window-manager controls\n  host <cmd>     internal host abstraction used by scripts and the Hub\n  bind <cmd>     set/reset/list keybindings\n  bar <cmd>      add/remove/move/show/hide/list/configure bar modules\n  deploy         DEV ONLY: deploy from a repository checkout\n  recovery       last-resort reset/redeploy recovery path\n  doctor         converge system/config drift (--check, --explain)\n  verify         report whether this box matches its configured release/channel\n  debug          print a shareable diagnostic bundle\n  keyring        show or configure GNOME keyring sign-in unlock\n  security-key   enroll and wire a FIDO2/U2F security key for PAM\n  import <path>  import existing config with conflict resolution (--undo)\n  plugin <cmd>   create/validate/add/remove/share shell plugins\n  help           show this help\n"))
}

func die(format string, a ...any) {
	fmt.Fprintf(os.Stderr, "ryoku: "+format+"\n", a...)
	os.Exit(1)
}
