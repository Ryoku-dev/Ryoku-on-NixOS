#!/usr/bin/env python3

import argparse
import base64
import getpass
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

AUDIENCE = "ryoku-hyperion-v2"
PUBLIC_KEY = Path(__file__).resolve().parents[1] / "keys/hyperion-invite-public.pem"
INVITE_PATH = Path.home() / ".config/ryoku/hyperion-invite"


def encode(data):
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def decode(value):
    if not value or any(c not in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_" for c in value):
        raise ValueError("invalid invite encoding")
    data = base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))
    # One token per invitation: reject encodings with stray padding bits.
    if encode(data) != value:
        raise ValueError("invalid invite encoding")
    return data


def openssl(payload, signature=None, private_key=None):
    with tempfile.TemporaryDirectory(prefix="ryoku-invite-") as directory:
        root = Path(directory)
        source = root / "message"
        source.write_bytes(payload)
        cmd = ["openssl", "pkeyutl"]
        if private_key:
            cmd += ["-sign", "-inkey", str(private_key)]
        else:
            signature_file = root / "signature"
            signature_file.write_bytes(signature)
            cmd += ["-verify", "-pubin", "-inkey", str(PUBLIC_KEY), "-sigfile", str(signature_file)]
        cmd += ["-rawin", "-in", str(source)]
        return subprocess.run(cmd, capture_output=True, check=True).stdout


def verify(token):
    try:
        payload_encoded, signature_encoded = token.strip().split(".")
        payload = decode(payload_encoded)
        signature = decode(signature_encoded)
        openssl(payload, signature=signature)
        invitation = json.loads(payload)
        if invitation.get("aud") != AUDIENCE or invitation.get("v") != 1:
            raise ValueError("invite belongs to another purpose")
        expires = invitation.get("exp")
        if type(expires) is not int or not time.time() < expires:
            raise ValueError("invite is expired")
    except (ValueError, json.JSONDecodeError, subprocess.CalledProcessError, OSError) as exc:
        raise ValueError("invalid or expired Hyperion invitation") from exc


def main():
    parser = argparse.ArgumentParser(description="Hyperion tester invitations")
    commands = parser.add_subparsers(dest="command", required=True)
    issue = commands.add_parser("issue")
    issue.add_argument("--days", type=int, default=7)
    issue.add_argument("--key", type=Path, required=True)
    commands.add_parser("authorize")
    commands.add_parser("check")
    args = parser.parse_args()

    try:
        if args.command == "issue":
            if not 1 <= args.days <= 30:
                raise ValueError("invites must expire within 1 to 30 days")
            payload = json.dumps(
                {"v": 1, "aud": AUDIENCE, "exp": int(time.time()) + args.days * 86400},
                separators=(",", ":"), sort_keys=True,
            ).encode()
            print(f"{encode(payload)}.{encode(openssl(payload, private_key=args.key))}")
        elif args.command == "authorize":
            token = getpass.getpass("Hyperion invite code: ")
            verify(token)
            INVITE_PATH.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            fd = os.open(INVITE_PATH, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, "w") as file:
                file.write(token.strip() + "\n")
            os.chmod(INVITE_PATH, 0o600)
            print("Hyperion invitation accepted.")
        else:
            verify(INVITE_PATH.read_text())
    except (ValueError, OSError) as exc:
        print(f"ryoku-hyperion-invite: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
