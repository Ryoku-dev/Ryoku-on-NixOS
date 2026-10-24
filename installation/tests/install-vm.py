#!/usr/bin/env python3
# Boot a Ryoku ISO in QEMU, run the installer unattended against a virtual disk,
# and verify the result, so a broken install or a missing package is caught
# before a user hits it. Drives the live root shell over the serial console
# (pexpect); the backend is env-driven and prints @@RYOKU_DONE on success.
#
#   install-vm.py --iso ryoku.iso            full install + verify
#   install-vm.py --iso ryoku.iso --boot-only   just reach the live shell (quick check)
#
# Exits 0 when the install completes and the installed tree checks out, non-zero
# otherwise, printing the serial log tail. Uses KVM when /dev/kvm is present,
# else TCG (slow). See docs/updates.md.
import argparse
import base64
import os
import shutil
import shlex
import socket
import string
import re
import subprocess
import sys
import tarfile
import tempfile
import time

import pexpect

OVMF_CODE = next((p for p in (
    "/usr/share/edk2/x64/OVMF_CODE.4m.fd",
    "/usr/share/edk2-ovmf/x64/OVMF_CODE.4m.fd",
    "/usr/share/OVMF/OVMF_CODE_4M.fd",
    "/usr/share/OVMF/OVMF_CODE.fd",
    "/usr/share/OVMF/OVMF_CODE.4m.fd",
    "/usr/share/OVMF/x64/OVMF_CODE.fd",
) if os.path.exists(p)), None)
OVMF_VARS = next((p for p in (
    "/usr/share/edk2/x64/OVMF_VARS.4m.fd",
    "/usr/share/edk2-ovmf/x64/OVMF_VARS.4m.fd",
    "/usr/share/OVMF/OVMF_VARS_4M.fd",
    "/usr/share/OVMF/OVMF_VARS.fd",
    "/usr/share/OVMF/OVMF_VARS.4m.fd",
    "/usr/share/OVMF/x64/OVMF_VARS.fd",
) if os.path.exists(p)), None)

# where a shipped ISO bakes the package closure (iso/build.sh); the TUI keys its
# RYOKU_ONLINE=0 decision off the same path (tui/system.go offlineRepoPath).
OFFLINE_REPO = "/usr/share/ryoku/offline/repo"
COMPOSITOR_CHECKS = {
    "hyprland": {
        "config": "hypr/hyprland.lua",
        "keyboard": "hypr/keyboard.lua",
        "layout": 'kb_layout = "it"',
    },
    "niri": {
        "config": "niri/config.kdl",
        "keyboard": "niri/config.kdl",
        "layout": 'layout "it"',
    },
}


# the installed tree a real user must end up with: the package, the materialized
# config (including the files that used to reach no one), the bootloader, and the
# enabled greeter. checked by mounting the target root read-only after install.
INSTALLED_CHECKS = [
    ("d", "usr/share/ryoku/config"),
    ("f", "home/{user}/.config/quickshell/shell/shell.qml"),
    ("f", "home/{user}/.config/pip/pip.conf"),
    ("f", "home/{user}/.config/wireplumber/wireplumber.conf.d/51-ryoku-bluetooth.conf"),
    # The shipped default map stays in the site layer. The installer's explicit
    # browser and file-manager choices are user preferences, so xdg-mime records
    # only those selections in the user's own override.
    ("f", "usr/local/share/applications/mimeapps.list"),
    ("f", "home/{user}/.config/mimeapps.list"),
    ("f", "home/{user}/.config/chromium-flags.conf"),
    ("f", "home/{user}/.config/chrome-flags.conf"),
    ("f", "usr/share/applications/ryoku-nvim.desktop"),
    ("d", "boot/EFI"),
]


def qemu_cmd(work, iso=None, with_iso=False, monitor=False):
    vars_copy = os.path.join(work, "OVMF_VARS.fd")
    if not os.path.exists(vars_copy):
        shutil.copy(OVMF_VARS, vars_copy)
    accel = ["-enable-kvm", "-cpu", "host"] if os.path.exists("/dev/kvm") else ["-cpu", "max"]
    cmd = [
        "qemu-system-x86_64", "-machine", "q35", *accel, "-m", "4096", "-smp", "4",
        "-drive", f"if=pflash,format=raw,readonly=on,file={OVMF_CODE}",
        "-drive", f"if=pflash,format=raw,file={vars_copy}",
        "-drive", f"file={os.path.join(work, 'target.qcow2')},if=virtio,format=qcow2",
        "-netdev", "user,id=n0", "-device", "virtio-net-pci,netdev=n0",
    ]
    if with_iso:
        cmd += ["-nographic", "-drive", f"file={iso},media=cdrom,readonly=on",
                "-boot", "d"]
    else:
        cmd += ["-display", "none", "-vga", "std", "-serial", "stdio"]
    if monitor:
        cmd += ["-monitor",
                f"unix:{os.path.join(work, 'mon.sock')},server,nowait"]
    return cmd


HMP_KEYS = {key: key for key in string.digits + string.ascii_lowercase}
HMP_KEYS["\n"] = "ret"


def spawn_qemu(cmd, timeout, log_path, mode):
    child = pexpect.spawn(cmd[0], cmd[1:], timeout=timeout, encoding="utf-8",
                          codec_errors="replace")
    child.logfile = open(log_path, mode)
    return child


def serial_tail(log_path):
    try:
        with open(log_path) as serial:
            return serial.read()[-4000:]
    except OSError as error:
        return f"(could not read {log_path}: {error})"


def hmp_command(work, command, timeout=10):
    monitor = os.path.join(work, "mon.sock")
    deadline = time.monotonic() + timeout
    last_error = None
    while time.monotonic() < deadline:
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
                client.settimeout(max(0.1, deadline - time.monotonic()))
                client.connect(monitor)
                response = b""
                while b"(qemu)" not in response:
                    chunk = client.recv(4096)
                    if not chunk:
                        raise RuntimeError("QEMU monitor closed before its prompt")
                    response += chunk
                client.sendall(command.encode() + b"\n")
                response = b""
                while b"(qemu)" not in response:
                    chunk = client.recv(4096)
                    if not chunk:
                        raise RuntimeError("QEMU monitor closed before command completion")
                    response += chunk
                text = response.decode("utf-8", errors="replace")
                if "Error:" in text:
                    raise RuntimeError(text.strip())
                return text
        except (FileNotFoundError, ConnectionRefusedError, socket.timeout) as error:
            last_error = error
            time.sleep(0.1)
    raise RuntimeError(f"QEMU monitor unavailable: {last_error}")


def enter_passphrase(work, passphrase, keypad):
    for character in passphrase:
        key = f"kp_{character}" if keypad else HMP_KEYS[character]
        hmp_command(work, f"sendkey {key}")
        time.sleep(0.15)
    hmp_command(work, f"sendkey {HMP_KEYS[chr(10)]}")


def convert_screendump(ppm):
    png = os.path.splitext(ppm)[0] + ".png"
    if shutil.which("magick"):
        converted = subprocess.run(["magick", ppm, png], check=False,
                                   stdout=subprocess.DEVNULL,
                                   stderr=subprocess.DEVNULL)
        if converted.returncode != 0:
            print(f"install-vm: magick could not convert {ppm}", file=sys.stderr)
        return
    try:
        from PIL import Image
    except ImportError:
        return
    try:
        with Image.open(ppm) as image:
            image.save(png)
    except Exception as error:
        print(f"install-vm: Pillow could not convert {ppm}: {error}", file=sys.stderr)


def capture_unlock_screen(work, name):
    ppm = os.path.join(work, f"unlock-{name}.ppm")
    hmp_command(work, f"screendump {ppm}")
    convert_screendump(ppm)

    captures = []
    for filename in os.listdir(work):
        if filename.startswith("unlock-") and filename.endswith(".ppm"):
            try:
                captures.append((int(filename[7:-4]), filename))
            except ValueError:
                pass
    later = sorted(item for item in captures if item[0] > 1)
    for _, filename in later[:-4]:
        for extension in (".ppm", ".png"):
            path = os.path.join(
                work, os.path.splitext(filename)[0] + extension)
            try:
                os.remove(path)
            except FileNotFoundError:
                pass


def screendumps(work):
    return sorted(
        os.path.join(work, name)
        for name in os.listdir(work)
        if name.startswith("unlock-") and name.endswith((".ppm", ".png"))
    )


def close_qemu(child):
    try:
        if child.logfile:
            child.logfile.flush()
            child.logfile.close()
            child.logfile = None
    except Exception:
        pass
    try:
        child.close(force=True)
    except Exception:
        pass


def fail_installed_boot(child, log_path, work, message):
    if child is not None:
        close_qemu(child)
    print(f"\ninstall-vm: {message}", file=sys.stderr)
    print(f"--- serial tail ---\n{serial_tail(log_path)}", file=sys.stderr)
    shots = screendumps(work)
    print("--- unlock screendumps ---", file=sys.stderr)
    if shots:
        for path in shots:
            print(f"{path} ({os.path.getsize(path)} bytes)", file=sys.stderr)
    else:
        print("(none)", file=sys.stderr)
    sys.exit(1)


def boot_installed(work, args, log_path):
    monitor = os.path.join(work, "mon.sock")
    try:
        os.remove(monitor)
    except FileNotFoundError:
        pass
    cmd = qemu_cmd(work, monitor=True)
    print("install-vm: booting the installed target disk")
    try:
        child = spawn_qemu(cmd, args.boot_timeout, log_path, "a")
    except OSError as error:
        fail_installed_boot(
            None, log_path, work, f"could not launch the installed boot: {error}")
    deadline = time.monotonic() + args.boot_timeout
    capture_number = 0
    try:
        if args.encrypt:
            wait = min(args.prompt_wait, max(0, deadline - time.monotonic()))
            result = child.expect([r"ryoku-test login:", pexpect.EOF,
                                   pexpect.TIMEOUT], timeout=wait)
            if result == 0:
                print("install-vm: installed system reached ryoku-test login:")
                close_qemu(child)
                return
            if result == 1:
                fail_installed_boot(child, log_path, work,
                                    "installed system exited before the unlock attempt")

            capture_unlock_screen(work, capture_number)
            capture_number += 1
            if args.wrong_first:
                enter_passphrase(
                    work, args.passphrase + "9", args.keypad)
                time.sleep(3)
                capture_unlock_screen(work, "wrong")
            enter_passphrase(work, args.passphrase, args.keypad)
            capture_unlock_screen(work, capture_number)
            capture_number += 1

        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                fail_installed_boot(
                    child, log_path, work,
                    f"installed system did not reach ryoku-test login: within "
                    f"{args.boot_timeout} seconds")
            wait = min(15, remaining) if args.encrypt else remaining
            result = child.expect([r"ryoku-test login:", pexpect.EOF,
                                   pexpect.TIMEOUT], timeout=wait)
            if result == 0:
                print("install-vm: installed system reached ryoku-test login:")
                close_qemu(child)
                return
            if result == 1:
                fail_installed_boot(child, log_path, work,
                                    "installed system exited before its login prompt")
            if args.encrypt:
                capture_unlock_screen(work, capture_number)
                capture_number += 1
    except (OSError, RuntimeError) as error:
        fail_installed_boot(child, log_path, work,
                            f"could not drive the installed boot: {error}")


def fail(child, msg):
    print(f"\ninstall-vm: {msg}", file=sys.stderr)
    try:
        child.close(force=True)
    except Exception:
        pass
    sys.exit(1)


def login(child):
    # archiso serial: an autologin root shell, or a login prompt (any hostname).
    i = child.expect([r"login:", r"# ", pexpect.TIMEOUT], timeout=300)
    if i == 0:
        child.sendline("root")
        if child.expect([r"Password:", r"# "], timeout=60) == 0:
            child.sendline("")
            child.expect(r"# ", timeout=60)
    elif i == 2:
        fail(child, "the live ISO never reached a serial prompt (see log)")


def sh(child, line, timeout=120):
    child.sendline(line)
    child.expect(r"# ", timeout=timeout)
    return child.before


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--iso", required=True)
    ap.add_argument("--work", default=None)
    ap.add_argument("--user", default="test")
    ap.add_argument("--profile", default="vm")
    ap.add_argument("--compositor", choices=tuple(COMPOSITOR_CHECKS),
                    default=next(iter(COMPOSITOR_CHECKS)))
    ap.add_argument("--extra-admin", default="admin2",
                    help="additional administrator account to create and verify")
    ap.add_argument("--extra-standard", default="standard",
                    help="additional standard account to create and verify")
    ap.add_argument("--standard-limit-bytes", type=int, default=1073741824,
                    help="Btrfs qgroup limit for the standard account")
    ap.add_argument("--timeout", type=int, default=2400, help="install timeout (s)")
    ap.add_argument("--dry", action="store_true",
                    help="RYOKU_DRYRUN install-flow smoke (no real disk writes)")
    ap.add_argument("--boot-only", action="store_true", help="reach the live shell then stop")
    ap.add_argument("--repo-dir", default=None,
                    help="serve this [ryoku] repo (with <arch>/ryoku.db) to the "
                         "guest so the install pulls the desktop locally; needed in "
                         "CI, where Cloudflare 403s the public repo for datacenter IPs")
    ap.add_argument("--encrypt", action="store_true",
                    help="install the target with LUKS2 root encryption")
    ap.add_argument("--passphrase", default="123",
                    help="LUKS passphrase (default: 123)")
    ap.add_argument("--boot-installed", action="store_true",
                    help="boot the installed target and require its serial login prompt")
    ap.add_argument("--keypad", action="store_true",
                    help="type passphrase digits with QEMU keypad keys")
    ap.add_argument("--wrong-first", action="store_true",
                    help="try a wrong passphrase and capture the retry before unlocking")
    ap.add_argument("--prompt-wait", type=int, default=45,
                    help="seconds to wait before typing the LUKS passphrase (default: 45)")
    ap.add_argument("--boot-timeout", type=int, default=600,
                    help="installed-system boot timeout in seconds (default: 600)")
    ap.add_argument("--payload-dir", default=None,
                    help="overlay installation/backend and system from this checkout")
    args = ap.parse_args()
    if args.prompt_wait < 0:
        ap.error("--prompt-wait must not be negative")
    if args.boot_timeout <= 0:
        ap.error("--boot-timeout must be positive")
    if args.encrypt and not args.passphrase:
        ap.error("--passphrase must not be empty with --encrypt")
    if args.keypad:
        unsupported = sorted(set(args.passphrase) - set(string.digits))
        if unsupported:
            ap.error("--keypad requires an ASCII digits-only --passphrase "
                     f"(unsupported: {''.join(unsupported)!r})")
    if args.encrypt and args.boot_installed:
        unsupported = sorted(
            set(args.passphrase) - set(string.digits + string.ascii_lowercase))
        if unsupported:
            ap.error("--boot-installed can type only digits and lowercase letters "
                     f"in --passphrase (unsupported: {''.join(unsupported)!r})")
    account_names = (args.user, args.extra_admin, args.extra_standard)
    account_name_re = re.compile(r"^[a-z_][a-z0-9_-]{0,31}$")
    if any(not account_name_re.fullmatch(name) for name in account_names):
        ap.error("account names must match ^[a-z_][a-z0-9_-]{0,31}$")
    if len(set(account_names)) != len(account_names):
        ap.error("primary, extra administrator, and standard account names must differ")
    if args.standard_limit_bytes <= 0 or args.standard_limit_bytes > (1 << 63) - 1:
        ap.error("--standard-limit-bytes must be between 1 and 9223372036854775807")

    if not OVMF_CODE or not OVMF_VARS:
        print("install-vm: OVMF firmware not found (pacman -S edk2-ovmf)", file=sys.stderr)
        sys.exit(2)

    work = args.work or tempfile.mkdtemp(prefix="ryoku-vm-")
    os.makedirs(work, exist_ok=True)
    log = os.path.join(work, "serial.log")
    subprocess.run(["qemu-img", "create", "-f", "qcow2",
                    os.path.join(work, "target.qcow2"), "40G"], check=True,
                   stdout=subprocess.DEVNULL)
    pwhash = subprocess.check_output(["openssl", "passwd", "-6", "test"]).decode().strip()
    extra_users_file = "/tmp/ryoku-extra-users.tsv"
    extra_users = "\n".join((
        f"{args.extra_admin}\tAdditional Administrator\tadmin\tdevices\t{pwhash}\t0",
        f"{args.extra_standard}\tStandard User\tstandard\t\t{pwhash}\t"
        f"{args.standard_limit_bytes}",
    )) + "\n"
    servers = []
    repo_env = ""
    repo_pacman_conf = None
    if args.repo_dir:
        if not os.path.exists(os.path.join(args.repo_dir, "x86_64", "ryoku.db")):
            print(f"install-vm: --repo-dir has no x86_64/ryoku.db ({args.repo_dir})",
                  file=sys.stderr)
            sys.exit(2)
        repo_srv = subprocess.Popen(
            ["python3", "-m", "http.server", "8710", "--bind", "127.0.0.1",
             "--directory", os.path.abspath(args.repo_dir)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        servers.append(repo_srv)
        base = "http://10.0.2.2:8710"
        repo_env = (f" RYOKU_REPO_SERVER='{base}/$arch' RYOKU_REPO_SIGLEVEL=Never "
                    f"RYOKU_MIRROR_PROBE_URLS='https://geo.mirror.pkgbuild.com"
                    f"/core/os/x86_64/core.db {base}/x86_64/ryoku.db'")
        print(f"install-vm: serving [ryoku] repo from {args.repo_dir} at {base}")
        repo_pacman_conf = "\n".join((
            "[options]",
            "Architecture = auto",
            "SigLevel = Required DatabaseOptional",
            "LocalFileSigLevel = Optional",
            "ParallelDownloads = 5",
            "[core]",
            "Include = /etc/pacman.d/mirrorlist",
            "[extra]",
            "Include = /etc/pacman.d/mirrorlist",
            "[multilib]",
            "Include = /etc/pacman.d/mirrorlist",
            "[ryoku]",
            "SigLevel = Never",
            f"Server = {base}/$arch",
            "",
        ))

    payload_url = None
    if args.payload_dir:
        payload_dir = os.path.abspath(args.payload_dir)
        payload_parts = [
            (os.path.join(payload_dir, "installation", "backend"),
             "installation/backend"),
            (os.path.join(payload_dir, "system"), "system"),
        ]
        missing_parts = [path for path, _ in payload_parts if not os.path.isdir(path)]
        if missing_parts:
            print("install-vm: --payload-dir is missing: " + ", ".join(missing_parts),
                  file=sys.stderr)
            sys.exit(2)
        payload_tar = os.path.join(work, "payload.tar")
        with tarfile.open(payload_tar, "w") as archive:
            for path, archive_name in payload_parts:
                archive.add(path, arcname=archive_name)
        payload_srv = subprocess.Popen(
            ["python3", "-m", "http.server", "8711", "--bind", "127.0.0.1",
             "--directory", work],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        servers.append(payload_srv)
        payload_url = "http://10.0.2.2:8711/payload.tar"
        print(f"install-vm: serving installer payload from {payload_dir} at "
              f"{payload_url}")
    print(f"install-vm: booting {args.iso} (KVM={'yes' if os.path.exists('/dev/kvm') else 'no, TCG'}); log -> {log}")
    child = spawn_qemu(qemu_cmd(work, args.iso, with_iso=True),
                       args.timeout, log, "w")
    try:
        login(child)
        print("install-vm: live shell reached")
        if args.boot_only:
            sh(child, "echo READY:$(uname -r)")
            child.sendline("poweroff")
            child.expect(pexpect.EOF, timeout=120)
            print("install-vm: boot-only check OK")
            return

        if payload_url:
            overlay = (
                f"curl -fsSL {shlex.quote(payload_url)} -o /tmp/ryoku-payload.tar"
                " && rm -rf /usr/share/ryoku/installation/backend"
                " /usr/share/ryoku/system"
                " && tar -xf /tmp/ryoku-payload.tar -C /usr/share/ryoku"
                " && grep -q '/usr/local/lib/ryoku/backend/ryoku-install'"
                " /usr/local/bin/ryoku-install"
                " && rm -rf /usr/local/lib/ryoku/backend"
                " && cp -a /usr/share/ryoku/installation/backend"
                " /usr/local/lib/ryoku/backend"
                " && test -x /usr/local/lib/ryoku/backend/ryoku-install"
                " && echo PAYLOAD_OVERLAY_OK"
            )
            if "PAYLOAD_OVERLAY_OK" not in sh(child, overlay, timeout=180):
                fail(child, "could not overlay the working-tree installer payload")
            print("install-vm: overlaid /usr/share/ryoku and "
                  "/usr/local/lib/ryoku/backend")

        extra_users_b64 = base64.b64encode(extra_users.encode()).decode()
        extra_users_command = (
            f"printf %s {shlex.quote(extra_users_b64)} | base64 -d > "
            f"{shlex.quote(extra_users_file)}"
            f" && chmod 0600 {shlex.quote(extra_users_file)}"
            " && echo EXTRA_USERS_READY"
        )
        if "EXTRA_USERS_READY" not in sh(child, extra_users_command):
            fail(child, "could not create the extra-users TSV in the live system")
        if repo_pacman_conf is not None:
            pacman_conf_b64 = base64.b64encode(
                repo_pacman_conf.encode()).decode()
            pacman_conf_path = "/tmp/ryoku-vm-pacman.conf"
            command = (
                f"printf %s {shlex.quote(pacman_conf_b64)} | base64 -d > "
                f"{pacman_conf_path} && echo PACMAN_CONFIG_READY"
            )
            if "PACMAN_CONFIG_READY" not in sh(child, command):
                fail(child, "could not create the VM pacman configuration")
        else:
            pacman_conf_path = ""


        env = (f"RYOKU_DISK=/dev/vda RYOKU_PROFILE={shlex.quote(args.profile)} "
               f"RYOKU_HOSTNAME=ryoku-test RYOKU_USERNAME={shlex.quote(args.user)} "
               f"RYOKU_FULLNAME='Primary Administrator' RYOKU_ROOT_MODE=locked "
               f"RYOKU_EXTRA_USERS_FILE={shlex.quote(extra_users_file)} "
               f"RYOKU_DISK_STRATEGY=whole RYOKU_WIPE_CONFIRMED=1 RYOKU_SKIP_AUR=1 "
               f"RYOKU_COMPOSITOR={args.compositor} "
               f"RYOKU_COMPOSITOR_CONFIG_DIR={'hypr' if args.compositor == 'hyprland' else 'niri'} "
               f"RYOKU_BROWSER=chromium "
               f"RYOKU_REPO=/usr/share/ryoku RYOKU_KEYMAP=it RYOKU_XKB_LAYOUT=it "
               f"RYOKU_PASSWORD_HASH={shlex.quote(pwhash)}")
        if args.encrypt:
            env += (f" RYOKU_ENCRYPT=1 "
                    f"RYOKU_LUKS_PASSPHRASE={shlex.quote(args.passphrase)}")
        if args.dry:
            env += " RYOKU_DRYRUN=1"
        # Take the SAME package source the TUI would (system.go installEnv): a
        # shipped ISO bakes the whole closure, so the TUI always sends
        # RYOKU_ONLINE=0 and every real install is the offline path. Running the
        # backend without it exercised an online pacstrap no ISO user reaches, and
        # one that cannot work by construction: base.packages carries packages that
        # live only in [ryoku]/[offline], so pacstrap died on "target not found".
        baked = "R0E" in sh(
            child, f"ls {OFFLINE_REPO}/offline.db >/dev/null 2>&1; echo R$?E")
        if baked:
            env += f" RYOKU_ONLINE=0 RYOKU_OFFLINE_REPO={OFFLINE_REPO}"
            print("install-vm: offline path (the ISO's baked repo), as the TUI runs it")
        else:
            env += repo_env
            print("install-vm: online path (no baked repo on this ISO)")
        if pacman_conf_path:
            env += f" RYOKU_PACMAN_CONF={pacman_conf_path}"
        # skip the optional AUR builds (they compile from source for minutes and
        # are best-effort): RYOKU_SKIP_AUR covers a current ISO, emptying the set
        # also covers an older backend that predates the flag.
        sh(child, ": > /usr/share/ryoku/system/packages/aur.packages")
        # capability probe, BEFORE the install, and only meaningful on the online
        # path: an ISO whose backend predates RYOKU_REPO_SERVER cannot be pointed at
        # the locally served repo. This used to be inferred afterwards from
        # "repo.ryoku.dev" appearing anywhere in the serial log, which every real
        # failure also does (the backend prints that URL in its error text), so a
        # broken install reported success and the log was never even kept.
        stale_iso = "R0E" not in sh(
            child, "grep -rq RYOKU_REPO_SERVER /usr/share/ryoku/installation/backend; echo R$?E")
        child.sendline(f"export {env}; ryoku-install; echo BACKEND_EXIT:$?")
        i = child.expect([r"@@RYOKU_DONE", r"BACKEND_EXIT:[1-9]", pexpect.TIMEOUT],
                         timeout=args.timeout)
        if i != 0:
            if args.repo_dir and stale_iso and not baked:
                print("::warning::this ISO's backend predates RYOKU_REPO_SERVER; it "
                      "tried the public repo (Cloudflare 403s CI runners). Rebuild "
                      "the ISO for a full VM install -- skipping this run.",
                      file=sys.stderr)
                child.sendline("poweroff")
                try:
                    child.expect(pexpect.EOF, timeout=60)
                except (pexpect.TIMEOUT, pexpect.EOF):
                    pass
                return
            fail(child, "the installer did not reach @@RYOKU_DONE (see log)")
        child.expect(r"BACKEND_EXIT:0", timeout=120)
        child.expect(r"# ", timeout=60)
        print("install-vm: @@RYOKU_DONE, backend exit 0")
        if args.dry:
            child.sendline("poweroff")
            child.expect(pexpect.EOF, timeout=120)
            print("install-vm: dry-run install flow OK")
            return

        # Independent check: mount the installed tree (@ root, @home, ESP) and
        # assert it, so "the backend said done" is backed by real files on disk.
        sh(child, "umount -R /mnt 2>/dev/null; mkdir -p /mnt2")
        root_device = "/dev/vda2"
        verify_mapper_opened = False
        if args.encrypt:
            mapper = sh(
                child,
                "test -e /dev/mapper/root; echo VERIFY_ROOT_MAPPER_STATUS:$?")
            if "VERIFY_ROOT_MAPPER_STATUS:0" in mapper:
                root_device = "/dev/mapper/root"
            else:
                passphrase = shlex.quote(args.passphrase)
                opened = sh(
                    child,
                    f"printf '%s' {passphrase} | cryptsetup open --key-file=- "
                    "/dev/vda2 ryokuverify; echo VERIFY_OPEN_STATUS:$?",
                    timeout=120)
                if "VERIFY_OPEN_STATUS:0" not in opened:
                    print("install-vm: could not open the installed LUKS root:",
                          file=sys.stderr)
                    print(opened.strip(), file=sys.stderr)
                    fail(child, "encrypted-root verification failed")
                root_device = "/dev/mapper/ryokuverify"
                verify_mapper_opened = True
        mounted = sh(
            child,
            f"mount -o subvol=@ {root_device} /mnt2; "
            "echo VERIFY_MOUNT_STATUS:$?")
        if "VERIFY_MOUNT_STATUS:0" not in mounted:
            print(f"install-vm: could not mount {root_device} for verification:",
                  file=sys.stderr)
            print(mounted.strip(), file=sys.stderr)
            if verify_mapper_opened:
                sh(child, "cryptsetup close ryokuverify 2>/dev/null || true")
            fail(child, "installed-root verification mount failed")
        sh(child, f"mount -o subvol=@home {root_device} /mnt2/home 2>/dev/null || true")
        sh(child, "mount /dev/vda1 /mnt2/boot 2>/dev/null || true")
        missing = []
        for kind, rel in INSTALLED_CHECKS:
            path = "/mnt2/" + rel.format(user=args.user)
            # "!" asserts absence: some paths are a regression when they exist.
            if kind == "!":
                if "R0E" in sh(child, f"test -e {path}; echo R$?E"):
                    missing.append(f"must not exist:{path}")
                continue
            if "R0E" not in sh(child, f"test -{kind} {path}; echo R$?E"):
                missing.append(f"{kind}:{path}")
        compositor_check = COMPOSITOR_CHECKS[args.compositor]
        compositor_config = (
            f"home/{args.user}/.config/{compositor_check['config']}")
        if "R0E" not in sh(
                child, f"test -f /mnt2/{compositor_config}; echo R$?E"):
            missing.append(f"f:/mnt2/{compositor_config}")
        if "enabled" not in sh(child, "systemctl --root=/mnt2 is-enabled sddm 2>&1"):
            missing.append("sddm not enabled (no greeter on boot)")
        compositor_keyboard = (
            f"/mnt2/home/{args.user}/.config/{compositor_check['keyboard']}")
        for desc, cmd in [
            ("vconsole KEYMAP=it", "grep -q '^KEYMAP=it' /mnt2/etc/vconsole.conf && echo KBOK"),
            ("X11 XkbLayout it", "grep -q 'XkbLayout.*\"it\"' /mnt2/etc/X11/xorg.conf.d/00-keyboard.conf && echo KBOK"),
            (
                "selected compositor keyboard layout it",
                f"grep -Fq {shlex.quote(compositor_check['layout'])} "
                f"{shlex.quote(compositor_keyboard)} && echo KBOK",
            ),
        ]:
            if "KBOK" not in sh(child, cmd):
                missing.append("keymap: " + desc)
        mimeapps = f"/mnt2/home/{args.user}/.config/mimeapps.list"
        app_choice_check = (
            f"grep -qx 'x-scheme-handler/http=chromium.desktop' {mimeapps}"
            f" && grep -qx 'x-scheme-handler/https=chromium.desktop' {mimeapps}"
            f" && grep -qx 'text/html=chromium.desktop' {mimeapps}"
            f" && grep -qx 'inode/directory=org.gnome.Nautilus.desktop' {mimeapps}")
        app_choice_result = sh(
            child,
            f"{app_choice_check}; choice_status=$?; "
            "echo APP_CHOICE_STATUS:$choice_status")
        if "APP_CHOICE_STATUS:0" not in app_choice_result:
            missing.append("installer browser/file-manager choices are not in mimeapps.list")
        account_shell_names = " ".join(shlex.quote(name) for name in account_names)
        primary = shlex.quote(args.user)
        extra_admin = shlex.quote(args.extra_admin)
        extra_standard = shlex.quote(args.extra_standard)
        passwd_check = " && ".join(
            f"grep -q '^{name}:' /mnt2/etc/passwd" for name in account_names)
        account_checks = [
            ("passwd entries for all requested accounts", passwd_check),
            (
                "wheel contains only the two administrators",
                "IFS=: read -r _ _ _ members < <(grep '^wheel:' /mnt2/etc/group)"
                f" && case \",$members,\" in *',{args.user},'*) ;; *) false;; esac"
                f" && case \",$members,\" in *',{args.extra_admin},'*) ;; *) false;; esac"
                f" && case \",$members,\" in *',{args.extra_standard},'*) false;; esac"
                " && IFS=, read -ra wheel_users <<<\"$members\""
                f" && for wheel_user in \"${{wheel_users[@]}}\"; do"
                f" [[ $wheel_user == {primary} || $wheel_user == {extra_admin} ]]"
                " || exit 1; done",
            ),
            (
                "standard account has device access",
                "for group in input video; do "
                "IFS=: read -r _ _ _ members < <(grep \"^$group:\" /mnt2/etc/group)"
                f" && case \",$members,\" in *',{args.extra_standard},'*) ;; *) exit 1;; esac"
                " || exit 1; done",
            ),
            (
                "root account is locked",
                "IFS=: read -r _ root_password _ < <(grep '^root:' /mnt2/etc/shadow)"
                " && [[ $root_password == '!'* ]]",
            ),
            (
                "every requested home is a private user-owned Btrfs subvolume",
                f"for account in {account_shell_names}; do "
                "IFS=: read -r _ _ uid gid _ _ _ < <(grep \"^$account:\" /mnt2/etc/passwd)"
                " && [[ $(stat -c '%u:%g:%a' \"/mnt2/home/$account\") == \"$uid:$gid:700\" ]]"
                " && btrfs subvolume show \"/mnt2/home/$account\" >/dev/null"
                " || exit 1; done",
            ),
            (
                "standard account qgroup limit",
                f"read -r _ _ subvol_id _ < <(btrfs subvolume show "
                f"/mnt2/home/{extra_standard} | grep 'Subvolume ID:')"
                " && qgroup_found=1"
                " && while read -r qgroup rfer excl max_rfer max_excl; do "
                f"[[ $qgroup == \"0/$subvol_id\" && $max_rfer == "
                f"{args.standard_limit_bytes} ]] && qgroup_found=0; done "
                f"< <(btrfs qgroup show --raw -reF /mnt2/home/{extra_standard})"
                " && ((qgroup_found == 0))",
            ),
        ]
        for description, command in account_checks:
            result = sh(
                child,
                f"{command}; account_status=$?; "
                "echo ACCOUNT_ASSERTION_STATUS:$account_status")
            if "ACCOUNT_ASSERTION_STATUS:0" not in result:
                missing.append("accounts: " + description)
            else:
                print("install-vm: account assertion OK: " + description)
        if not any(item.startswith("accounts: ") for item in missing):
            sh(child, "echo USERS_ASSERTIONS_PASS:"
               f"{primary},{extra_admin},{extra_standard}")
        if args.encrypt:
            crypttab = sh(
                child,
                "test -f /mnt2/etc/crypttab; echo CRYPTTAB_STATUS:$?")
            if "CRYPTTAB_STATUS:0" not in crypttab:
                missing.append("encrypted install has no /etc/crypttab")
            cryptdevice = sh(
                child,
                "grep -R --include='*.conf' -q 'cryptdevice=' /mnt2/boot; "
                "echo CRYPTDEVICE_STATUS:$?")
            if "CRYPTDEVICE_STATUS:0" not in cryptdevice:
                missing.append("Limine config has no cryptdevice= kernel argument")
        if args.boot_installed:
            enabled = sh(
                child,
                "systemctl --root=/mnt2 enable serial-getty@ttyS0.service "
                ">/dev/null; echo SERIAL_GETTY_STATUS:$?")
            if "SERIAL_GETTY_STATUS:0" not in enabled:
                missing.append("serial-getty@ttyS0.service could not be enabled")
        sh(child, "umount -R /mnt2 2>/dev/null || true")
        if verify_mapper_opened:
            sh(child, "cryptsetup close ryokuverify")
        child.sendline("poweroff")
        child.expect(pexpect.EOF, timeout=120)
        if child.logfile:
            child.logfile.flush()
            child.logfile.close()
            child.logfile = None
        if missing:
            print("install-vm: installed tree is missing:", file=sys.stderr)
            for item in missing:
                print(f"  {item}", file=sys.stderr)
            sys.exit(1)
        print("install-vm: installed tree verified")
        if args.boot_installed:
            boot_installed(work, args, log)
    except (pexpect.TIMEOUT, pexpect.EOF) as error:
        try:
            if child.logfile:
                child.logfile.flush()
        except Exception:
            pass
        print(f"\ninstall-vm: {type(error).__name__}\n--- serial tail ---\n"
              f"{serial_tail(log)}", file=sys.stderr)
        sys.exit(1)
    finally:
        for server in servers:
            server.terminate()
        for server in servers:
            try:
                server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                server.kill()


if __name__ == "__main__":
    main()
