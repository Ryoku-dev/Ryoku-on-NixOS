#!/usr/bin/env python3
"""Configure the Google Drive rclone remote used by the II backup service."""

from __future__ import annotations

import json
import re
import subprocess
import sys
from typing import Any


REMOTE = "ii-gdrive"


def run_command(args: list[str], timeout: int = 120) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        text=True,
        capture_output=True,
        timeout=timeout,
        check=False,
    )


def safe_error(result: subprocess.CompletedProcess[str], *secrets: str) -> str:
    message = (result.stderr or result.stdout or "command failed").strip()
    for secret in secrets:
        if secret:
            message = message.replace(secret, "[redacted]")
    message = re.sub(r"\s+", " ", message)
    return message[:300] or f"command exited with status {result.returncode}"


def extract_token(output: str) -> dict[str, Any] | None:
    decoder = json.JSONDecoder()
    candidates: list[dict[str, Any]] = []
    for match in re.finditer(r"\{", output):
        try:
            value, _ = decoder.raw_decode(output[match.start():])
        except json.JSONDecodeError:
            continue
        if not isinstance(value, dict):
            continue
        nested = value.get("token")
        if isinstance(nested, dict) and nested.get("access_token"):
            candidates.append(nested)
        elif isinstance(nested, str):
            try:
                parsed = json.loads(nested)
            except json.JSONDecodeError:
                parsed = None
            if isinstance(parsed, dict) and parsed.get("access_token"):
                candidates.append(parsed)
        elif value.get("access_token"):
            candidates.append(value)
    return candidates[-1] if candidates else None


def fail(message: str) -> int:
    print(f"ERROR: {message}")
    return 1


def main() -> int:
    if len(sys.argv) != 3 or not sys.argv[1].strip() or not sys.argv[2].strip():
        return fail("usage: setup_rclone.py <client_id> <client_secret>")

    client_id, client_secret = sys.argv[1], sys.argv[2]
    try:
        # OAuth tokens are bound to the client that requested them. Authorize
        # with the same credentials that will be stored on the remote; mixing
        # rclone's built-in client token with a custom client causes refreshes
        # to fail with `unauthorized_client`.
        authorize = run_command([
            "rclone", "authorize", "drive", client_id, client_secret,
        ], timeout=300)
        if authorize.returncode != 0:
            return fail(safe_error(authorize, client_id, client_secret))

        token = extract_token(f"{authorize.stdout}\n{authorize.stderr}")
        if not token:
            return fail("OAuth authorization did not return a token")

        token_json = json.dumps(token, separators=(",", ":"))
        # Only mutate the persistent remote after authorization succeeds. A
        # cancelled browser flow must leave any existing working token intact.
        create = run_command([
            "rclone", "config", "create", REMOTE, "drive",
            "client_id", client_id,
            "client_secret", client_secret,
            "scope", "drive",
            "token", token_json,
            "--non-interactive",
        ])
        if create.returncode != 0:
            update = run_command([
                "rclone", "config", "update", REMOTE,
                "client_id", client_id,
                "client_secret", client_secret,
                "scope", "drive",
                "token", token_json,
                "--non-interactive",
            ])
            if update.returncode != 0:
                return fail(safe_error(update, client_id, client_secret, token_json))
    except FileNotFoundError:
        return fail("rclone is not installed or is not in PATH")
    except subprocess.TimeoutExpired:
        return fail("rclone authorization timed out")
    except OSError as exc:
        return fail(str(exc))

    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
