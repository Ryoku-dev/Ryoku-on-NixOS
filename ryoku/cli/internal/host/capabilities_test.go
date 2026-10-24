package host

import "testing"

func TestCapabilitiesJSONForSupportedHosts(t *testing.T) {
	tests := []struct {
		name string
		env  map[string]string
		want string
	}{
		{
			name: "pacman-systemd",
			env:  map[string]string{"RYOKU_HOST_PKGMGR": "pacman", "RYOKU_HOST_INIT": "systemd"},
			want: "{\"packageManager\":\"pacman\",\"init\":\"systemd\",\"snapshots\":{\"supported\":true,\"reason\":\"\"},\"aur\":{\"supported\":true,\"reason\":\"\"},\"users\":{\"supported\":true,\"reason\":\"\",\"permissions\":[{\"id\":\"admin\",\"label\":\"Administrator\",\"groups\":[\"wheel\"]},{\"id\":\"devices\",\"label\":\"Devices\",\"groups\":[\"input\"]},{\"id\":\"virtualization\",\"label\":\"Virtualization\",\"groups\":[\"kvm\"]},{\"id\":\"containers\",\"label\":\"Containers\",\"groups\":[\"docker\"]}],\"storage\":{\"subvolumes\":false,\"quota\":false,\"reason\":\"Btrfs tools are not installed.\"}}}\n",
		},
		{
			name: "xbps-runit",
			env:  map[string]string{"RYOKU_HOST_PKGMGR": "xbps", "RYOKU_HOST_INIT": "runit"},
			want: "{\"packageManager\":\"xbps\",\"init\":\"runit\",\"snapshots\":{\"supported\":true,\"reason\":\"\"},\"aur\":{\"supported\":false,\"reason\":\"The AUR is an Arch Linux service; Void installs come from XBPS.\"},\"users\":{\"supported\":true,\"reason\":\"\",\"permissions\":[{\"id\":\"admin\",\"label\":\"Administrator\",\"groups\":[\"wheel\"]},{\"id\":\"devices\",\"label\":\"Devices\",\"groups\":[\"input\"]},{\"id\":\"virtualization\",\"label\":\"Virtualization\",\"groups\":[\"kvm\"]},{\"id\":\"containers\",\"label\":\"Containers\",\"groups\":[\"docker\"]}],\"storage\":{\"subvolumes\":false,\"quota\":false,\"reason\":\"Btrfs tools are not installed.\"}}}\n",
		},
		{
			name: "dnf-systemd",
			env:  map[string]string{"RYOKU_HOST_PKGMGR": "dnf", "RYOKU_HOST_INIT": "systemd"},
			want: "{\"packageManager\":\"dnf\",\"init\":\"systemd\",\"packageTable\":\"/usr/share/ryoku/packages/fedora.tsv\",\"snapshots\":{\"supported\":true,\"reason\":\"\"},\"aur\":{\"supported\":false,\"reason\":\"The AUR is an Arch Linux service; Fedora installs come from DNF.\"},\"users\":{\"supported\":true,\"reason\":\"\",\"permissions\":[{\"id\":\"admin\",\"label\":\"Administrator\",\"groups\":[\"wheel\"]},{\"id\":\"devices\",\"label\":\"Devices\",\"groups\":[\"input\"]},{\"id\":\"virtualization\",\"label\":\"Virtualization\",\"groups\":[\"kvm\"]},{\"id\":\"containers\",\"label\":\"Containers\",\"groups\":[\"docker\"]}],\"storage\":{\"subvolumes\":false,\"quota\":false,\"reason\":\"Btrfs tools are not installed.\"}}}\n",
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			runner := &fakeRunner{paths: map[string]bool{
				"chpasswd": true, "gpasswd": true, "useradd": true,
				"userdel": true, "usermod": true,
			}}
			app, stdout, stderr := testApp(runner, tc.env)
			app.cfg.PasswdPath, app.cfg.GroupPath = writeUsersFixtures(t)
			if code := app.Execute([]string{"capabilities"}); code != ExitOK {
				t.Fatalf("capabilities exit = %d", code)
			}
			if got := stdout.String(); got != tc.want {
				t.Fatalf("capabilities = %q, want %q", got, tc.want)
			}
			if stderr.Len() != 0 {
				t.Fatalf("stderr = %q", stderr.String())
			}
		})
	}
}

func TestCapabilitiesRejectsArguments(t *testing.T) {
	app, _, _ := testApp(&fakeRunner{}, map[string]string{"RYOKU_HOST_PKGMGR": "pacman", "RYOKU_HOST_INIT": "systemd"})
	if code := app.Execute([]string{"capabilities", "extra"}); code != ExitUsage {
		t.Fatalf("capabilities with argument exit = %d", code)
	}
}
