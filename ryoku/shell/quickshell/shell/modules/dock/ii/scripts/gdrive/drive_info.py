#!/usr/bin/env python3
"""Return Google Drive quota and II backup size in bytes."""

from __future__ import annotations

import json
import re
import subprocess
import sys
from typing import Any


REMOTE = "ii-gdrive"
DEFAULT_BASE_PATH = "ii-backup"
QUERY_TIMEOUT_SECONDS = 20


def valid_base_path(value: str) -> bool:
    return bool(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._/-]*", value)) and ".." not in value


def run_json(args: list[str]) -> dict[str, Any]:
    result = subprocess.run(args, text=True, capture_output=True, timeout=QUERY_TIMEOUT_SECONDS, check=False)
    if result.returncode != 0:
        message = (result.stderr or result.stdout or "rclone command failed").strip()
        raise RuntimeError(re.sub(r"\s+", " ", message)[:300])
    try:
        value = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError("rclone returned invalid JSON") from exc
    if not isinstance(value, dict):
        raise RuntimeError("rclone returned an unexpected JSON value")
    return value


def error_payload(message: str) -> dict[str, Any]:
    return {"total": 0, "used": 0, "free": 0, "backupSize": 0, "unit": "bytes", "error": message}


def query(args: list[str]) -> tuple[dict[str, Any] | None, str]:
    try:
        return run_json(args), ""
    except FileNotFoundError:
        return None, "rclone is not installed or is not in PATH"
    except subprocess.TimeoutExpired:
        return None, "rclone query timed out"
    except (OSError, RuntimeError, ValueError) as exc:
        return None, str(exc) or "could not read Drive information"


def main() -> int:
    base_path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_BASE_PATH
    if len(sys.argv) > 2:
        print(json.dumps(error_payload("usage: drive_info.py [base-path]")))
        return 2
    if not valid_base_path(base_path):
        print(json.dumps(error_payload("invalid Drive base path")))
        return 2

    quota, quota_error = query(["rclone", "about", f"{REMOTE}:", "--json"])
    size, size_error = query(["rclone", "size", f"{REMOTE}:{base_path}", "--json"])
    if quota is None and size is None:
        print(json.dumps(error_payload(quota_error or size_error or "could not read Drive information")))
        return 1

    errors = [error for error in (quota_error, size_error) if error]
    print(json.dumps({
        "total": int((quota or {}).get("total", 0) or 0),
        "used": int((quota or {}).get("used", 0) or 0),
        "free": int((quota or {}).get("free", 0) or 0),
        "backupSize": int((size or {}).get("bytes", (size or {}).get("size", 0)) or 0),
        "unit": "bytes",
        "error": "; ".join(errors),
    }))
    return 0


if __name__ == "__main__":
    sys.exit(main())
