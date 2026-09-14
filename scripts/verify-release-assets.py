"""Refuse to publish a release whose uploaded files differ from local assets."""
import hashlib
import base64
import json
from pathlib import Path
import plistlib
import sys


def validate(remote, paths):
    assets = {item["name"]: item for item in remote["assets"]}
    for path in map(Path, paths):
        item = assets[path.name]
        assert item["state"] == "uploaded", f"Upload incomplete: {path.name}"
        assert item["size"] == path.stat().st_size, f"Size mismatch: {path.name}"
        digest = "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()
        assert item.get("digest") == digest, f"Digest missing or mismatched: {path.name}"


def validate_versions(current, previous):
    def version(info):
        return tuple(int(part) for part in info["CFBundleShortVersionString"].split("."))
    assert version(current) > version(previous), "Release version must increase"
    assert int(current["CFBundleVersion"]) > int(previous["CFBundleVersion"]), "Internal build number must increase for Sparkle"
    if previous.get("SUPublicEDKey"):
        assert current["SUPublicEDKey"] == previous["SUPublicEDKey"], "Unexpected update key rotation"


if __name__ == "__main__":
    if sys.argv[1] == "--versions":
        current = plistlib.loads(Path(sys.argv[2]).read_bytes())
        previous = json.loads(Path(sys.argv[3]).read_text())
        validate_versions(current, plistlib.loads(base64.b64decode(previous["content"])))
        print("PASS: release and internal build versions increase; update key is stable.")
    else:
        validate(json.loads(Path(sys.argv[1]).read_text()), sys.argv[2:])
        print("PASS: all release asset uploads and SHA-256 digests verified.")
