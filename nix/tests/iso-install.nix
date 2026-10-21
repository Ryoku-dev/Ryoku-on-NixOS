# Full installation test for the Ryoku live ISO. It installs Ryoku onto an
# empty disk with the unattended installer, boots the installed system, logs in
# through SDDM, and checks that Hyprland and niri start with the Ryoku shell.
#
# The installation downloads the desktop closure, so this test needs network
# access and KVM and runs outside the Nix build sandbox:
#
#   nix run .#ryoku-iso-install-test
#
# RYOKU_VM_CORES, RYOKU_VM_MEMORY (MiB) and RYOKU_VM_DIR tune the VM.
# RYOKU_VM_RENDERNODE (default /dev/dri/renderD128) is the host GPU that
# renders the installed desktop.
# RYOKU_VM_NIX_CONFIG adds nix.conf lines to the live system, for example a
# local binary cache on the host (reachable as 10.0.2.2). QEMU cannot take
# screenshots of the virgl display, so the checks look at processes instead.
{ pkgs, isoSystem, source, track }:

let
  inherit (isoSystem.config.system.build) isoImage;
  iso = "${isoImage}/iso/${isoSystem.config.image.fileName}";
  qemu-common = import "${pkgs.path}/nixos/lib/qemu-common.nix" {
    inherit (pkgs) lib stdenv;
  };
  qemu = qemu-common.qemuBinary pkgs.qemu_test;
  # Hyprland needs OpenGL, so the installed system gets a virgl GPU rendered on
  # the host's render node. qemu_test is built without OpenGL support.
  qemuGL = qemu-common.qemuBinary pkgs.qemu;
  password = "ryoku";
  # Images from a dirty tree have no Git revision and install their embedded source.
  followed = if source == "path:/etc/ryoku/source" then "path:./ryoku-source" else track;

in
pkgs.testers.runNixOSTest {
  name = "ryoku-iso-install";
  nodes = { };
  globalTimeout = 4 * 60 * 60;

  testScript = ''
    import os
    import shlex
    import shutil
    import tempfile

    cores = os.environ.get("RYOKU_VM_CORES", "4")
    memory = os.environ.get("RYOKU_VM_MEMORY", "8192")
    work = os.environ.get("RYOKU_VM_DIR") or tempfile.mkdtemp(prefix="ryoku-iso-install-")
    os.makedirs(work, exist_ok=True)
    disk = os.path.join(work, "disk.img")
    variables = os.path.join(work, "efi-vars.fd")
    # RYOKU_VM_REUSE_DISK=1 skips the installation and checks the system
    # already installed in RYOKU_VM_DIR by an earlier run.
    reuse = os.environ.get("RYOKU_VM_REUSE_DISK") == "1" and os.path.exists(disk)
    if not reuse:
        with open(disk, "wb") as handle:
            handle.truncate(60 * 1024 ** 3)
        shutil.copyfile("${pkgs.OVMF.variables}", variables)
        os.chmod(variables, 0o644)


    rendernode = os.environ.get("RYOKU_VM_RENDERNODE", "/dev/dri/renderD128")

    # Without DISPLAY the driver appends -nographic, which turns off the
    # OpenGL display. Every VM here sets its display explicitly instead.
    if not any(name in os.environ for name in ("DISPLAY", "WAYLAND_DISPLAY")):
        os.environ["DISPLAY"] = ""


    def vm(name, cdrom):
        flags = [
            f"-m {memory}",
            f"-smp {cores}",
            "-drive if=pflash,format=raw,unit=0,readonly=on,file=${pkgs.OVMF.firmware}",
            f"-drive if=pflash,format=raw,unit=1,file={variables}",
            f"-drive file={disk},if=virtio,format=raw",
            "-netdev user,id=net0",
            "-device virtio-net-pci,netdev=net0",
            "-vga none",
        ]
        if cdrom:
            flags += ["-cdrom ${iso}", "-device virtio-vga", "-display none"]
            binary = "${qemu}"
        else:
            flags += ["-device virtio-vga-gl", f"-display egl-headless,rendernode={rendernode}"]
            binary = "${qemuGL}"
        machine = create_machine(binary + " " + " ".join(flags), name=name)
        # create_machine() leaves cleanup to the caller; registering the VM lets
        # the driver kill it when a subtest fails.
        machines_qemu.append(machine)
        return machine


    def write_file(machine, path, text):
        machine.succeed(f"cat > {path} <<'RYOKU_EOF'\n{text}\nRYOKU_EOF")


    def log_in(machine, user, process):
        machine.wait_until_succeeds("pgrep -f sddm-greeter")
        machine.sleep(5)
        machine.send_chars("${password}\n")
        machine.wait_until_succeeds(f"pgrep -u {user} -f {shlex.quote(process)}", timeout=300)
        machine.wait_until_succeeds(
            f"systemctl --user -M {user}@ is-active ryoku-shell.service", timeout=300
        )
        # The compositor must still be up once the session has settled.
        machine.sleep(20)
        machine.succeed(f"pgrep -u {user} -f {shlex.quote(process)}")
        machine.fail("coredumpctl list --no-legend 2>/dev/null | grep -qiE 'hyprland|niri|xwayland'")
        machine.fail("journalctl -b -o cat | grep -q 'ryoku-rashin: listen tcp 127.0.0.1:3600: bind: address already in use'")


    if not reuse:
        live = vm("live", cdrom=True)
        live.start()
        live.wait_for_unit("multi-user.target")

        with subtest("Live ISO is online"):
            live.wait_until_succeeds("curl -fsS --max-time 10 https://cache.nixos.org/nix-cache-info")
            env = live.succeed("su - nixos -c env")
            assert "RYOKU_INSTALL_TARGET_SOURCE=${source}\n" in env, env
            assert "RYOKU_INSTALL_TARGET_TRACK=${track}\n" in env, env

        extra_nix_config = os.environ.get("RYOKU_VM_NIX_CONFIG", "").strip()
        if extra_nix_config:
            with subtest("Apply RYOKU_VM_NIX_CONFIG to the live system"):
                live.succeed("cp --remove-destination \"$(readlink -f /etc/nix/nix.conf)\" /etc/nix/nix.conf")
                write_file(live, "/tmp/extra-nix.conf", extra_nix_config)
                live.succeed("cat /tmp/extra-nix.conf >> /etc/nix/nix.conf", "systemctl restart nix-daemon.service")

        with subtest("Unattended installation to /dev/vda"):
            # Run as the live user, like the guided installer on tty1 does.
            password_hash = live.succeed("mkpasswd -m yescrypt ${password}").strip()
            write_file(live, "/tmp/ryoku-install.sh", "\n".join([
                f"export RYOKU_INSTALL_PASSWORD_HASH={shlex.quote(password_hash)}",
                "ryoku-install --cli --iso --yes --gpu none --compositor hyprland \\",
                "  --disk /dev/vda --confirm-disk /dev/vda > /tmp/ryoku-install.log 2>&1",
                "echo $? > /tmp/ryoku-install.status",
            ]))
            live.succeed("systemd-run --unit=ryoku-install --uid=nixos bash -l /tmp/ryoku-install.sh")
            live.wait_until_succeeds("test -e /tmp/ryoku-install.status", timeout=3 * 60 * 60)
            print(live.succeed("tail -n 60 /tmp/ryoku-install.log"))
            assert live.succeed("cat /tmp/ryoku-install.status").strip() == "0", "installer failed"
            assert "@@RYOKU_DONE" in live.succeed("cat /tmp/ryoku-install.log")

        with subtest("Installed flake follows the ISO branch and pins the image revision"):
            live.succeed("mount /dev/disk/by-label/nixos /mnt", "mount /dev/disk/by-label/EFI /mnt/boot")
            flake = live.succeed("cat /mnt/etc/nixos/flake.nix")
            assert 'ryoku.url = "${followed}";' in flake, flake
            lock = live.succeed("cat /mnt/etc/nixos/flake.lock")
            if "${source}".startswith("github:"):
                assert "${source}".rsplit("/", 1)[1] in lock, lock
            live.succeed("test \"$(stat -c %U /mnt/etc/nixos/flake.nix)\" = root")
            live.succeed("test \"$(stat -c %a /mnt/etc/ryoku/user-password.hash)\" = 600")

        with subtest("Add the test backdoor to the installed system"):
            # The real installation stays exactly what a user gets; this module
            # only gives the installed system the test driver's backdoor shell.
            write_file(live, "/mnt/etc/nixos/modules/vm-test.nix", "\n".join([
                "{ modulesPath, ... }:",
                "{",
                "  imports = [ (modulesPath + \"/testing/test-instrumentation.nix\") ];",
                "}",
            ]))
            live.succeed(
                "sed -i 's|^    ./pkgs.nix$|    ./pkgs.nix\\n    ./modules/vm-test.nix|' /mnt/etc/nixos/configuration.nix",
                "grep -q modules/vm-test.nix /mnt/etc/nixos/configuration.nix",
            )
            live.succeed(
                "nixos-install --root /mnt --flake path:/mnt/etc/nixos#ryoku --no-root-passwd "
                "--option extra-substituters https://ryotunes.cachix.org "
                "--option extra-trusted-public-keys ryotunes.cachix.org-1:QNocajCsVm/IAMb8LPOWJi72XwqiexW9ec0UqeXLpGs= "
                ">&2",
                timeout=3600,
            )
            live.succeed("umount -R /mnt")

        live.shutdown()

    installed = vm("installed", cdrom=False)
    installed.start()

    with subtest("SDDM shows the qylock greeter"):
        installed.wait_for_unit("display-manager.service")
        installed.wait_until_succeeds("pgrep -f sddm-greeter")
        # Ryoku's SDDM theme is seeded from the qylock Orbital skin.
        installed.succeed("test -f /var/lib/ryoku/sddm-theme/Main.qml")
        greeter = installed.succeed("pgrep -af sddm-greeter")
        assert "themes/ryoku" in greeter, greeter

    with subtest("Hyprland session starts with the Ryoku shell"):
        log_in(installed, "ryoku", "bin/Hyprland")
        option = installed.succeed(
            "su ryoku -c 'XDG_RUNTIME_DIR=/run/user/1000 hyprctl --instance 0 getoption misc:disable_watchdog_warning'"
        )
        assert "int: 1" in option or "bool: true" in option, option

    with subtest("niri session starts with the Ryoku shell"):
        installed.succeed(
            "sed -i 's|compositor = \"hyprland\";|compositor = \"niri\";|' /etc/nixos/install-values.nix",
            "grep -q 'compositor = \"niri\";' /etc/nixos/install-values.nix",
        )
        installed.succeed("nixos-rebuild switch --flake /etc/nixos#ryoku >&2", timeout=3600)
        # Log out the way Ryoku's sign-out button does (session.exit ->
        # hl.dsp.exit() through the Lua parser). Hyprland may exit before
        # hyprctl reads its reply, so only the compositor going away counts.
        installed.execute(
            "su ryoku -c \"XDG_RUNTIME_DIR=/run/user/1000 hyprctl --instance 0 dispatch 'hl.dsp.exit()'\""
        )
        installed.wait_until_fails("pgrep -u ryoku -f bin/Hyprland")
        installed.succeed("rm -f /var/lib/sddm/state.conf", "systemctl restart display-manager.service")
        log_in(installed, "ryoku", "bin/niri --session")
        installed.fail("pgrep -u ryoku -f bin/Hyprland")

    installed.shutdown()
  '';
}
