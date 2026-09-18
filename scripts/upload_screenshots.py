"""Upload App Store screenshots in order; never print signed upload URLs."""

import hashlib
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Optional

from asc_api import token


API = "https://api.appstoreconnect.apple.com/v1"


def api(method: str, path: str, body: Optional[dict] = None) -> dict:
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Authorization": "Bearer " + token(), "Accept": "application/json"}
    if data is not None:
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(API + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        details = error.read().decode(errors="replace")
        raise RuntimeError(f"API {method} {path}: HTTP {error.code}: {details}") from error


def upload_one(set_id: str, path: Path) -> None:
    payload = path.read_bytes()
    reservation = api("POST", "/appScreenshots", {
        "data": {
            "type": "appScreenshots",
            "attributes": {"fileSize": len(payload), "fileName": path.name},
            "relationships": {
                "appScreenshotSet": {
                    "data": {"type": "appScreenshotSets", "id": set_id}
                }
            },
        }
    })["data"]
    screenshot_id = reservation["id"]
    print(f"Reserved {path.name}: {screenshot_id}", flush=True)
    operations = reservation["attributes"]["uploadOperations"]
    for operation in operations:
        offset = operation["offset"]
        length = operation["length"]
        headers = {item["name"]: item["value"] for item in operation["requestHeaders"]}
        request = urllib.request.Request(
            operation["url"], data=payload[offset:offset + length],
            headers=headers, method=operation["method"],
        )
        with urllib.request.urlopen(request, timeout=90) as response:
            response.read()
    print(f"Uploaded {path.name}", flush=True)
    api("PATCH", "/appScreenshots/" + screenshot_id, {
        "data": {
            "type": "appScreenshots", "id": screenshot_id,
            "attributes": {
                "uploaded": True,
                "sourceFileChecksum": hashlib.md5(payload).hexdigest(),
            },
        }
    })
    for _ in range(15):
        result = api("GET", "/appScreenshots/" + screenshot_id)
        state = result["data"]["attributes"]["assetDeliveryState"]
        status = state.get("state", "UNKNOWN") if isinstance(state, dict) else str(state)
        if status == "COMPLETE":
            print(f"Complete {path.name}", flush=True)
            return
        if status == "FAILED":
            raise RuntimeError(f"Processing failed for {path.name}: {state}")
        time.sleep(2)
    print(f"Still processing {path.name}; check again later", flush=True)


def main() -> None:
    if len(sys.argv) < 3:
        raise SystemExit("Usage: upload_screenshots.py SET_ID IMAGE... ")
    set_id = sys.argv[1]
    for name in sys.argv[2:]:
        upload_one(set_id, Path(name))


if __name__ == "__main__":
    main()
