"""Update metadata and publish guards; fixtures never contact GitHub or Keychain."""
import base64
import hashlib
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[2]


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


updates = load("verify-update")
release_assets = load("verify-release-assets")


class UpdateWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.app = self.root / "ClipboardBoard.app"
        (self.app / "Contents/MacOS").mkdir(parents=True)
        self.info = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())
        (self.app / "Contents/Info.plist").write_bytes(plistlib.dumps(self.info))
        (self.app / "Contents/MacOS/ClipboardBoard").write_bytes(b"test-executable")
        self.name = f"ClipboardBoard-v{self.info['CFBundleShortVersionString']}-update-arm64.zip"
        self.archive = self.root / self.name
        self.package()
        rss = ET.Element("rss")
        self.item = ET.SubElement(ET.SubElement(rss, "channel"), "item")
        for key, source in [("version", "CFBundleVersion"), ("shortVersionString", "CFBundleShortVersionString"), ("minimumSystemVersion", "LSMinimumSystemVersion")]:
            ET.SubElement(self.item, updates.SPARKLE + key).text = self.info[source]
        self.enclosure = ET.SubElement(self.item, "enclosure", {
            "url": updates.REPOSITORY + f"/releases/download/v{self.info['CFBundleShortVersionString']}/" + self.name,
            "length": str(self.archive.stat().st_size),
            updates.SPARKLE + "edSignature": base64.b64encode(b"s" * 64).decode(),
        })
        self.tree = ET.ElementTree(rss)

    def tearDown(self):
        self.temp.cleanup()

    def package(self, extra=None, executable=b"test-executable"):
        with zipfile.ZipFile(self.archive, "w") as archive:
            archive.write(self.app / "Contents/Info.plist", "ClipboardBoard.app/Contents/Info.plist")
            archive.writestr("ClipboardBoard.app/Contents/MacOS/ClipboardBoard", executable)
            if extra:
                archive.writestr(extra, b"do not distribute")

    def validate(self):
        self.tree.write(self.root / "appcast.xml")
        return updates.validate(self.root, self.app, verify_signatures=False)

    def test_complete_metadata_matches_packaged_app(self):
        self.assertEqual(self.validate(), self.name)

    def test_wrong_version_is_rejected(self):
        self.item.find(updates.SPARKLE + "version").text = "999"
        with self.assertRaisesRegex(AssertionError, "Build number"):
            self.validate()

    def test_external_download_is_rejected(self):
        self.enclosure.set("url", "https://example.invalid/update.zip")
        with self.assertRaisesRegex(AssertionError, "destination"):
            self.validate()

    def test_truncated_upload_is_rejected(self):
        self.enclosure.set("length", "1")
        with self.assertRaisesRegex(AssertionError, "size"):
            self.validate()

    def test_unexpected_archive_contents_are_rejected(self):
        for name in ["ClipboardBoardData/history.json", "ClipboardBoard.app/../secret"]:
            self.package(extra=name)
            self.enclosure.set("length", str(self.archive.stat().st_size))
            with self.assertRaisesRegex(AssertionError, "contents"):
                self.validate()

    def test_different_executable_cannot_be_published_as_accepted_build(self):
        self.package(executable=b"different-executable")
        self.enclosure.set("length", str(self.archive.stat().st_size))
        with self.assertRaisesRegex(AssertionError, "Executable"):
            self.validate()

    def test_remote_assets_must_have_matching_digest_size_and_state(self):
        asset = {"name": self.name, "size": self.archive.stat().st_size, "state": "uploaded",
                 "digest": "sha256:" + hashlib.sha256(self.archive.read_bytes()).hexdigest()}
        release_assets.validate({"assets": [asset]}, [self.archive])
        for key, value in [("size", 1), ("state", "starter"), ("digest", "sha256:wrong")]:
            wrong = dict(asset, **{key: value})
            with self.assertRaises(AssertionError):
                release_assets.validate({"assets": [wrong]}, [self.archive])
        with self.assertRaises(KeyError):
            release_assets.validate({"assets": []}, [self.archive])

    def test_release_is_draft_until_asset_verification_passes(self):
        workflow = (ROOT / ".github/workflows/release.yml").read_text()
        self.assertIn("--verify-tag --draft", workflow)
        publisher = (ROOT / "scripts/publish-release.sh").read_text()
        self.assertLess(publisher.index("verify-release-assets.py"), publisher.index("--draft=false --latest"))

    def test_release_versions_must_advance_without_changing_the_update_key(self):
        previous = dict(self.info, CFBundleVersion="15", CFBundleShortVersionString="1.6.1")
        release_assets.validate_versions(self.info, previous)
        for key, value in [("CFBundleVersion", "15"), ("CFBundleShortVersionString", "1.6.0"),
                           ("SUPublicEDKey", "different-key")]:
            with self.assertRaises(AssertionError):
                release_assets.validate_versions(dict(self.info, **{key: value}), previous)


if __name__ == "__main__":
    unittest.main()
