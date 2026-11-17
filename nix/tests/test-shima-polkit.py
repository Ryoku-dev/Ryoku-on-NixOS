#!/usr/bin/env python3
"""Exercise the authentication view against a private fake daemon, without PAM."""
import argparse
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import threading

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime", required=True, type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="shima-polkit-") as directory:
        root = Path(directory)
        address = root/"ryoku-shell.sock"
        server = socket.socket(socket.AF_UNIX)
        server.bind(str(address))
        server.listen()
        subscriber = []
        received = []
        errors = []
        def frame(value):
            subscriber[0].sendall((json.dumps(value)+"\n").encode())
        def peer(conn):
            try:
                for line in conn.makefile():
                    if line.strip() == "subscribe polkit":
                        subscriber.append(conn)
                        frame(dict(active=True, message="Test authorization", prompt="Password:", echo=False))
                    elif line.startswith("call "):
                        _, method, raw = line.split(" ", 2)
                        value = json.loads(raw)
                        received.append(method)
                        if method == "polkit.submit":
                            assert value == {"password":"test-password"}
                            frame(dict(active=True, message="Test authorization", prompt="Try again:", error="Wrong", echo=True))
                        elif method == "polkit.cancel":
                            frame(dict(active=False))
            except Exception as error:
                errors.append(str(error))
        def accept():
            try:
                while True:
                    conn, _ = server.accept()
                    threading.Thread(target=peer,args=(conn,),daemon=True).start()
            except OSError:
                pass
        threading.Thread(target=accept,daemon=True).start()
        impl = args.runtime/"share/quickshell/inir/services/PolkitServiceImpl.qml"
        local_impl = root/"PolkitServiceImpl.qml"
        local_impl.write_text(impl.read_text())
        impl = local_impl
        qml = root/"shell.qml"
        qml.write_text("""
import QtQuick
import Quickshell
ShellRoot {
    property int stage: 0
    Loader { id: bridge; source: %s }
    Timer {
        interval: 20; repeat: true; running: true
        onTriggered: {
            const view = bridge.item
            if (!view) return
            if (stage === 0 && view.interactionAvailable) {
                if (view.flow.message !== "Test authorization" || view.flow.responseVisible) Qt.quit()
                stage = 1
                view.submit("test-password")
            } else if (stage === 1 && view.state.error === "Wrong" && view.interactionAvailable) {
                if (!view.flow.responseVisible || view.flow.inputPrompt !== "Try again:") Qt.quit()
                stage = 2
                view.cancel()
            } else if (stage === 2 && !view.active) {
                console.log("SHIMA_POLKIT_BRIDGE_PASS")
                Qt.quit()
            }
        }
    }
}
""" % json.dumps(impl.as_uri()))
        env = os.environ.copy()
        env.update(XDG_RUNTIME_DIR=directory, QT_QPA_PLATFORM="offscreen",
                   DBUS_SESSION_BUS_ADDRESS="unix:path="+str(root/"no-session-bus"),
                   DBUS_SYSTEM_BUS_ADDRESS="unix:path="+str(root/"no-system-bus"))
        try:
            result = subprocess.run([shutil.which("qs"), "-p", str(qml)], env=env,
                                    capture_output=True, text=True, timeout=15)
        except subprocess.TimeoutExpired as error:
            raise SystemExit((error.stdout or b"").decode() + (error.stderr or b"").decode() + str(received))
        finally:
            server.close()
        if result.returncode or "SHIMA_POLKIT_BRIDGE_PASS" not in result.stdout+result.stderr or errors:
            raise SystemExit(result.stdout+result.stderr+str(errors))
        assert received == ["polkit.submit","polkit.cancel"], received
        print("PASS: prompt, secret socket transport, retry, echo mode, cancellation")
if __name__ == "__main__":
    main()
