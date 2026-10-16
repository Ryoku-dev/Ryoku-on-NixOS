#!/usr/bin/env python3
import json
import shutil
import subprocess
import sys

ATTRIBUTES = ["xdg:schema", "dev.ryoku.stage.email", "account", "gmail-accounts"]


def run(args, payload=None):
    return subprocess.run(args, input=payload, text=True, capture_output=True, timeout=15)


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else ""
    if shutil.which("secret-tool") is None:
        print(json.dumps({"ok": False, "error": "missing-secret-tool", "accounts": []}))
        return 1

    if action == "load":
        result = run(["secret-tool", "lookup", *ATTRIBUTES])
        if result.returncode != 0 or not result.stdout.strip():
            print(json.dumps({"ok": True, "accounts": []}))
            return 0
        try:
            accounts = json.loads(result.stdout)
        except (TypeError, ValueError):
            accounts = []
        print(json.dumps({"ok": True, "accounts": accounts if isinstance(accounts, list) else []}))
        return 0

    if action == "store":
        try:
            accounts = json.loads(sys.stdin.readline())
        except (TypeError, ValueError):
            print(json.dumps({"ok": False, "error": "invalid-json"}))
            return 1
        if not isinstance(accounts, list):
            print(json.dumps({"ok": False, "error": "invalid-accounts"}))
            return 1
        if not accounts:
            result = run(["secret-tool", "clear", *ATTRIBUTES])
        else:
            result = run(["secret-tool", "store", "--label=Ryoku Gmail", *ATTRIBUTES], json.dumps(accounts))
        print(json.dumps({"ok": result.returncode == 0, "error": result.stderr.strip()}))
        return result.returncode

    print(json.dumps({"ok": False, "error": "usage"}))
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
