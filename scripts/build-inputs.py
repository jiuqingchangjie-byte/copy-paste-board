"""Fingerprint shipped source/resources so an old same-version build is rejected."""
import hashlib
from pathlib import Path

root = Path(__file__).resolve().parents[1]
paths = [root / name for name in ["Package.swift", "Package.resolved", "scripts/build-app.sh",
                                 "scripts/embed-sparkle.sh", "scripts/build-inputs.py"]]
paths += [p for folder in ["Sources", "Resources"] for p in (root / folder).rglob("*") if p.is_file() and p.name != ".DS_Store"]
digest = hashlib.sha256()
for path in sorted(paths):
    digest.update(str(path.relative_to(root)).encode() + b"\0" + path.read_bytes() + b"\0")
print(digest.hexdigest())
