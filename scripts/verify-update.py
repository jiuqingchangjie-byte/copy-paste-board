"""Validate a release feed against its signed app and local archive before upload."""
import base64
from pathlib import Path
import plistlib
import subprocess
import sys
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
REPOSITORY = "https://github.com/jiuqingchangjie-byte/copy-paste-board"


def validate(directory, app, verify_signatures=True):
    directory, app = Path(directory), Path(app)
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    assert info["CFBundleIdentifier"] == "com.local.clipboardboard", "Unexpected application"
    assert len(base64.b64decode(info["SUPublicEDKey"], validate=True)) == 32, "Invalid public key"
    assert info["SUVerifyUpdateBeforeExtraction"] and info["SURequireSignedFeed"], "Update signatures are required"
    assert info["SUSignedFeedFailureExpirationInterval"] == 0, "Signed-feed validation must not expire"
    assert info["SUFeedURL"] == REPOSITORY + "/releases/latest/download/appcast.xml", "Wrong production feed"
    items = ET.parse(directory / "appcast.xml").getroot().findall("./channel/item")
    assert len(items) == 1, "Expected exactly one release in the feed"
    item = items[0]
    assert item.findtext(SPARKLE + "version") == info["CFBundleVersion"], "Build number mismatch"
    assert item.findtext(SPARKLE + "shortVersionString") == info["CFBundleShortVersionString"], "Version mismatch"
    assert item.findtext(SPARKLE + "minimumSystemVersion") == info["LSMinimumSystemVersion"], "OS mismatch"
    enclosure = item.find("enclosure")
    assert enclosure is not None, "Missing update archive"
    version = info["CFBundleShortVersionString"]
    name = f"ClipboardBoard-v{version}-update-arm64.zip"
    expected_url = REPOSITORY + f"/releases/download/v{version}/" + name
    assert enclosure.attrib["url"] == expected_url, "Unexpected update destination"
    archive = directory / name
    assert int(enclosure.attrib["length"]) == archive.stat().st_size, "Archive size mismatch"
    signature = enclosure.attrib[SPARKLE + "edSignature"]
    assert len(base64.b64decode(signature, validate=True)) == 64, "Invalid archive signature"
    with zipfile.ZipFile(archive) as zipped:
        names = zipped.namelist()
        assert names and all(n.startswith("ClipboardBoard.app/") and ".." not in n.split("/") for n in names), "Unexpected archive contents"
        packaged = plistlib.loads(zipped.read("ClipboardBoard.app/Contents/Info.plist"))
        assert packaged == info, "Archive contains a different app build"
        executable = "Contents/MacOS/" + info["CFBundleExecutable"]
        assert zipped.read("ClipboardBoard.app/" + executable) == (app / executable).read_bytes(), "Executable mismatch"
    if verify_signatures:
        tools = ROOT / ".build/artifacts/sparkle/Sparkle/bin"
        public = subprocess.check_output([tools / "generate_keys", "--account", "com.local.clipboardboard", "-p"], text=True).strip()
        assert public == info["SUPublicEDKey"], "Signing identity mismatch"
        for args in [(archive, signature), (directory / "appcast.xml",)]:
            subprocess.run([tools / "sign_update", "--account", "com.local.clipboardboard", "--verify", *args], check=True)
    return name


if __name__ == "__main__":
    validate(*sys.argv[1:])
    print("PASS: update version, archive, URL, embedded app and signatures verified.")
