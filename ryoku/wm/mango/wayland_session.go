package main

// sessionEntry is the wayland-session .desktop the installer writes as a
// fallback when the mango package ships none, and what `ryoku wm session`
// prints. Exec names the Ryoku wrapper, not the bare compositor: mango's
// upstream entry starts the compositor with no ordering hook, and a first
// login after `pacman -S ryoku-desktop-mango` would then read an
// unmaterialized ~/.config/mango — a bare session. The wrapper runs
// `ryoku materialize` synchronously when the tree is missing, then execs
// mango, which still activates its own session target and environment.
// DesktopNames stays mango so xdg-desktop-portal reads mango-portals.conf and
// the seam's XDG_CURRENT_DESKTOP fallback detects the provider.
const sessionEntry = `[Desktop Entry]
Name=Mango (Ryoku)
Comment=Ryoku desktop on the MangoWM compositor
Exec=ryoku-mango-session
Icon=mango
Type=Application
DesktopNames=mango;wlroots`

// runSession prints the wayland-session entry. It must work with no live
// compositor: the installer writes the file inside a chroot.
func runSession() error {
	_, err := stdout.WriteString(sessionEntry + "\n")
	return err
}
