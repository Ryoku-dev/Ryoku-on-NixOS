import os
import json
import socket
import urllib.request
import urllib.parse
import urllib.error

# Force IPv4 preference to avoid hanging on networks where IPv6 is configured
# locally but has no route to Google endpoints (causing SYN_SENT hangs).
_orig_getaddrinfo = socket.getaddrinfo
def _ipv4_first_getaddrinfo(host, port, family=0, type=0, proto=0, flags=0):
    if family == 0 or family == socket.AF_UNSPEC:
        try:
            return _orig_getaddrinfo(host, port, socket.AF_INET, type, proto, flags)
        except Exception:
            pass
    return _orig_getaddrinfo(host, port, family, type, proto, flags)
socket.getaddrinfo = _ipv4_first_getaddrinfo

def _load_env():
    script_dir = os.path.dirname(os.path.realpath(__file__))
    candidates = []
    override = os.environ.get("RYOKU_GOOGLE_ENV", "").strip()
    if override:
        candidates.append(override)
    shell_dir = os.environ.get("RYOKU_SHELL_DIR", "").strip()
    if shell_dir:
        candidates.append(os.path.join(shell_dir, ".env"))
    candidates.extend([
        os.path.join(script_dir, "..", "..", "..", "shell", ".env"),
        os.path.join(script_dir, "..", "..", "..", ".env"),
        os.path.join(script_dir, "..", "..", ".env"),
        os.path.join(os.path.expanduser("~"), ".config", "quickshell", "shell", ".env"),
    ])

    for env_path in candidates:
        env = {}
        try:
            with open(os.path.realpath(env_path), "r", encoding="utf-8") as file:
                for line in file:
                    line = line.strip()
                    if line and not line.startswith("#") and "=" in line:
                        key, value = line.split("=", 1)
                        env[key.strip()] = value.strip().strip("\"'")
        except (FileNotFoundError, OSError):
            continue
        return env
    return {}


_env = _load_env()
CLIENT_ID = os.environ.get("GOOGLE_CLIENT_ID") or os.environ.get("GMAIL_CLIENT_ID") or _env.get("GOOGLE_CLIENT_ID") or _env.get("GMAIL_CLIENT_ID") or ""
CLIENT_SECRET = os.environ.get("GOOGLE_CLIENT_SECRET") or os.environ.get("GMAIL_CLIENT_SECRET") or _env.get("GOOGLE_CLIENT_SECRET") or _env.get("GMAIL_CLIENT_SECRET") or ""

def get_credentials():
    return CLIENT_ID, CLIENT_SECRET

def has_credentials():
    return bool(CLIENT_ID and CLIENT_SECRET)

def refresh_token_exchange(refresh_token):
    cid, sec = get_credentials()
    if not cid or not sec:
        raise Exception("Missing GOOGLE_CLIENT_ID or GOOGLE_CLIENT_SECRET in .env")

    data = urllib.parse.urlencode({
        "refresh_token": refresh_token,
        "client_id":     cid,
        "client_secret": sec,
        "grant_type":    "refresh_token",
    }).encode('utf-8')

    req = urllib.request.Request(
        "https://oauth2.googleapis.com/token",
        data=data,
        headers={"Content-Type": "application/x-www-form-urlencoded"}
    )

    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            body = json.loads(resp.read().decode('utf-8'))
            return body
    except urllib.error.HTTPError as e:
        error_body = ""
        try:
            error_body = e.read().decode('utf-8')
            parsed = json.loads(error_body)
            err_code = parsed.get("error", "http_error")
            if err_code == "invalid_grant":
                raise ValueError("invalid_grant")
        except ValueError:
            raise
        except Exception:
            pass
        raise Exception(f"HTTP {e.code}: {e.reason}")

def resolve_token(token_or_refresh):
    """
    Returns an access token string.
    If input starts with 'ya29.', it's assumed to be a valid access token.
    Otherwise, it's treated as a refresh token and exchanged.
    """
    if token_or_refresh.startswith("ya29."):
        return token_or_refresh
    res = refresh_token_exchange(token_or_refresh)
    if isinstance(res, dict):
        return res.get("access_token", "")
    return str(res)
