# Boots the Ryoku live ISO with UEFI and with legacy BIOS and checks the live
# installer: the guided installer opens on the first console, the image carries
# its own Ryoku source, and an unattended dry run renders an installed flake
# that follows the ISO's branch. Runs offline in the Nix build sandbox.
{ pkgs, isoSystem, source, track }:

let
  inherit (isoSystem.config.system.build) isoImage;
  iso = "${isoImage}/iso/${isoSystem.config.image.fileName}";
  qemu-common = import "${pkgs.path}/nixos/lib/qemu-common.nix" {
    inherit (pkgs) lib stdenv;
  };
  qemu = qemu-common.qemuBinary pkgs.qemu_test;
  followed = if source == "path:/etc/ryoku/source" then "path:./ryoku-source" else track;
in
pkgs.testers.runNixOSTest {
  name = "ryoku-iso-boot";
  nodes = { };

  testScript = ''
    import os
    import shlex
    import shutil
    import tempfile

    work = tempfile.mkdtemp()
    disk = os.path.join(work, "disk.img")
    with open(disk, "wb") as handle:
        handle.truncate(20 * 1024 ** 3)


    def live_machine(name, uefi):
        flags = [
            "-m 3072",
            "-smp 2",
            "-cdrom ${iso}",
            f"-drive file={disk},if=virtio,format=raw",
            "-netdev user,id=net0",
            "-device virtio-net-pci,netdev=net0",
        ]
        if uefi:
            variables = os.path.join(work, f"{name}-vars.fd")
            shutil.copyfile("${pkgs.OVMF.variables}", variables)
            os.chmod(variables, 0o644)
            flags += [
                "-drive if=pflash,format=raw,unit=0,readonly=on,file=${pkgs.OVMF.firmware}",
                f"-drive if=pflash,format=raw,unit=1,file={variables}",
            ]
        machine = create_machine("${qemu} " + " ".join(flags), name=name)
        # create_machine() leaves cleanup to the caller; registering the VM lets
        # the driver kill it when a subtest fails.
        machines_qemu.append(machine)
        return machine


    def as_live_user(command):
        return f"su - nixos -c {shlex.quote(command)}"


    uefi = live_machine("uefi", uefi=True)
    uefi.start()
    uefi.wait_for_unit("multi-user.target")

    with subtest("UEFI boot reaches the guided installer on tty1"):
        uefi.succeed("test -d /sys/firmware/efi")
        uefi.wait_until_succeeds("pgrep -u nixos -f 'ryoku-install.* --iso'")
        uefi.succeed("test -e /tmp/.ryoku-iso-installer-started")

    with subtest("Live store is intact"):
        uefi.succeed("nix store verify --no-trust -r --option experimental-features nix-command /run/current-system")

    with subtest("Image carries its Ryoku source and install targets"):
        uefi.succeed("test -f /etc/ryoku/source/flake.nix")
        uefi.succeed("test -f /etc/ryoku/source/nix/iso/default.nix")
        env = uefi.succeed(as_live_user("env"))
        assert "RYOKU_INSTALL_TARGET_SOURCE=${source}\n" in env, env
        assert "RYOKU_INSTALL_TARGET_TRACK=${track}\n" in env, env
        assert "RYOKU_INSTALL_SOURCE=path:/etc/ryoku/source\n" in env, env

    with subtest("Unattended dry run follows the ISO branch and pins the image revision"):
        output = uefi.succeed(as_live_user(
            "ryoku-install --cli --iso --dry-run --yes --gpu none "
            "--disk /dev/vda --confirm-disk /dev/vda 2>&1"
        ))
        assert 'ryoku.url = "${followed}";' in output, output
        assert "Follows    ${followed}" in output, output
        assert "Dry run complete. No disks or files were changed." in output, output
        assert "aethctl" not in output, output

    uefi.shutdown()

    bios = live_machine("bios", uefi=False)
    bios.start()
    bios.wait_for_unit("multi-user.target")

    with subtest("Legacy BIOS boot reaches the guided installer on tty1"):
        bios.succeed("test ! -d /sys/firmware/efi")
        bios.wait_until_succeeds("pgrep -u nixos -f 'ryoku-install.* --iso'")

    bios.shutdown()
  '';
}
