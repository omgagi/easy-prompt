"""Small App Store Connect API helper. Never prints a key or a bearer token."""

import argparse
import base64
import json
import os
import time
import urllib.error
import urllib.request
from pathlib import Path

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def token() -> str:
    key_id = os.environ["ASC_KEY_ID"]
    issuer_id = os.environ["ASC_ISSUER_ID"]
    key_path = Path(os.environ["ASC_KEY_PATH"])
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    now = int(time.time())
    claims = {"iss": issuer_id, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}
    message = ".".join(
        b64url(json.dumps(part, separators=(",", ":")).encode()) for part in (header, claims)
    )
    key = serialization.load_pem_private_key(key_path.read_bytes(), password=None)
    der_signature = key.sign(message.encode(), ec.ECDSA(hashes.SHA256()))
    r, s = decode_dss_signature(der_signature)
    signature = r.to_bytes(32, "big") + s.to_bytes(32, "big")
    return message + "." + b64url(signature)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("method", choices=["GET", "POST", "PATCH", "DELETE"])
    parser.add_argument("path", help="App Store Connect path beginning with /v1/")
    parser.add_argument("--body", type=Path, help="JSON request body file")
    args = parser.parse_args()
    if not args.path.startswith("/v1/") or "://" in args.path:
        parser.error("path must begin with /v1/")
    body = args.body.read_bytes() if args.body else None
    headers = {"Authorization": "Bearer " + token(), "Accept": "application/json"}
    if body is not None:
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(
        "https://api.appstoreconnect.apple.com" + args.path,
        data=body,
        headers=headers,
        method=args.method,
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            content = response.read()
            print(json.dumps(json.loads(content), indent=2) if content else response.status)
    except urllib.error.HTTPError as error:
        content = error.read()
        print(json.dumps(json.loads(content), indent=2) if content else error.code)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
