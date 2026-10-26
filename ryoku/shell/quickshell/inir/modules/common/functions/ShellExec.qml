pragma Singleton

import QtQml

import Quickshell
import Quickshell.Io
import Ryoku.Ui.Singletons

import inir.modules.common

Singleton {
    id: root

    readonly property string fishPath: "/usr/bin/fish"
    readonly property string bashPath: "/usr/bin/bash"
    readonly property string gtkLaunchPath: "/usr/bin/gtk-launch"

    // -1 unknown, 0 no, 1 yes
    property int _fishAvailable: -1

    Process {
        id: fishCheckProc
        command: ["/usr/bin/test", "-x", root.fishPath]
        onExited: (exitCode, exitStatus) => {
            root._fishAvailable = (exitCode === 0) ? 1 : 0
        }
    }

    Component.onCompleted: {
        fishCheckProc.running = true
    }

    function supportsFish(): bool {
        if (root._fishAvailable === -1) {
            // Trigger async check, but default to bash until we know.
            fishCheckProc.running = true
            return false
        }
        return root._fishAvailable === 1
    }

    function execDetachedArgs(args, description = "", workingDirectory = ""): void {
        const argv = Array.from(args ?? []).map(arg => String(arg ?? "")).filter(arg => arg.length > 0)
        if (argv.length === 0) return

        Spawn.runApp(argv, {
            cwd: String(workingDirectory ?? "").trim(),
            label: String(description ?? "").trim()
        })
    }

    function openDirectory(path: string, description: string): void {
        const target = String(path ?? "").trim()
        if (target.length === 0) return

        const script = `
            target="$1"
            desktop_id="$(xdg-mime query default inode/directory 2>/dev/null || true)"
            case "$desktop_id" in
                ""|kitty-open*|*terminal*|foot*|alacritty*|konsole*|xterm*|wezterm*)
                    desktop_id=""
                    for candidate in org.gnome.Nautilus org.kde.dolphin thunar nemo pcmanfm-qt; do
                        if [ -f "/usr/share/applications/$candidate.desktop" ]; then
                            desktop_id="$candidate"
                            break
                        fi
                    done
                    ;;
                *) desktop_id="\${desktop_id%.desktop}" ;;
            esac

            if [ -n "$desktop_id" ] && command -v gtk-launch >/dev/null 2>&1; then
                exec gtk-launch "$desktop_id" "$target"
            fi
            exec xdg-open "$target"
        `
        root.execDetachedArgs([root.bashPath, "-lc", script, "inir-open-directory", target], description)
    }

    function execCmd(cmd: string, workingDirectory = ""): void {
        const c = String(cmd ?? "").trim()
        if (c.length === 0) return

        if (supportsFish()) {
            root.execDetachedArgs([root.fishPath, "-c", c], "", workingDirectory)
            return
        }

        root.execDetachedArgs([root.bashPath, "-lc", c], "", workingDirectory)
    }

    function execFishOrBashOneLiner(fishCmd: string, bashCmd: string): void {
        const f = String(fishCmd ?? "").trim()
        const b = String(bashCmd ?? "").trim()

        if (supportsFish()) {
            if (f.length === 0) return
            root.execDetachedArgs([root.fishPath, "-c", f])
            return
        }

        if (b.length === 0) return
        root.execDetachedArgs([root.bashPath, "-lc", b])
    }

    function launchDesktopEntry(desktopId: string, description = ""): bool {
        const id = String(desktopId ?? "").trim().replace(/\.desktop$/, "")
        if (id.length === 0) return false
        root.execDetachedArgs([root.gtkLaunchPath, id], description.length > 0 ? description : `Launch ${id}`)
        return true
    }

    function writeFileViaShell(path: string, content: string): void {
        const p = String(path ?? "").trim()
        if (p.length === 0) return

        const escapedContent = StringUtils.shellSingleQuoteEscape(content ?? "")
        const escapedPath = StringUtils.shellSingleQuoteEscape(p)
        const bash = "printf '%s' '" + escapedContent + "' > '" + escapedPath + "'"

        if (supportsFish()) {
            Quickshell.execDetached([root.fishPath, "-c", bash])
            return
        }

        Quickshell.execDetached([root.bashPath, "-lc", bash])
    }
}
