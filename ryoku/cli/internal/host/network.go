package host

func (a *App) Network(args []string) int {
	if len(args) < 2 {
		return ExitUsage
	}
	switch args[0] {
	case "kill":
		if len(args) != 2 || (args[1] != "status" && args[1] != "on" && args[1] != "off") {
			return ExitUsage
		}
		if a.cfg.UID != 0 {
			return commandExit(a.run("pkexec", "/usr/bin/ryoku-network-kill", args[1]))
		}
		return commandExit(a.run("ryoku-network-kill", args[1]))
	case "wifi-backend":
		if len(args) == 2 && args[1] == "get" {
			return commandExit(a.run("ryoku-wifi-backend", "get"))
		}
		if len(args) != 3 || args[1] != "set" || (args[2] != "iwd" && args[2] != "wpa_supplicant") {
			return ExitUsage
		}
		if a.cfg.UID != 0 {
			return commandExit(a.run("pkexec", "ryoku-wifi-backend", args[2]))
		}
		return commandExit(a.run("ryoku-wifi-backend", args[2]))
	default:
		return ExitUsage
	}
}
