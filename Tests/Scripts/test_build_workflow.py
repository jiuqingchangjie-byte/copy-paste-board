"""Build/launch checks use fake launchers and never operate real applications."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[2]


class BuildWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="clipboardboard-build-test-")
        self.root = Path(self.temporary.name)
        (self.root / "scripts").mkdir()
        (self.root / "bin").mkdir()
        self.bundle = self.root / "dist/ClipboardBoard.app"
        self.bundle.mkdir(parents=True)
        (self.bundle / "existing").write_text("keep the current signed app")
        self.environment = dict(os.environ)
        self.environment.pop("CODE_SIGN_IDENTITY", None)
        self.environment["PATH"] = str(self.root / "bin") + ":/usr/bin:/bin"

    def tearDown(self):
        self.temporary.cleanup()

    def script(self, name):
        target = self.root / "scripts" / name
        shutil.copy2(REPOSITORY / "scripts" / name, target)
        return target

    def fake(self, name, source):
        target = self.root / "bin" / name
        target.write_text("#!/bin/bash\nset -eu\n" + source)
        target.chmod(0o700)

    def run_script(self, name):
        return subprocess.run(["/bin/bash", str(self.script(name))], env=self.environment,
                              text=True, capture_output=True)

    def test_launch_of_existing_app_does_not_build_or_sign(self):
        self.fake("open", 'printf "%s" "$1" > "' + str(self.root / "opened") + '"\n')
        builder = self.root / "scripts/build-app.sh"
        builder.write_text('#!/bin/bash\ntouch "' + str(self.root / "rebuilt") + '"\n')
        builder.chmod(0o700)
        result = self.run_script("run.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / "rebuilt").exists())
        self.assertEqual((self.root / "opened").read_text(), str(self.bundle))

    def test_missing_identity_preserves_existing_bundle(self):
        self.fake("swift", "exit 90\n")
        result = self.run_script("build-app.sh")
        self.assertEqual(result.returncode, 1)
        self.assertIn("缺少固定签名身份", result.stderr)
        self.assertEqual((self.bundle / "existing").read_text(), "keep the current signed app")

    def test_ad_hoc_identity_is_rejected_before_building(self):
        self.environment["CODE_SIGN_IDENTITY"] = "-"
        self.fake("swift", "exit 90\n")
        result = self.run_script("build-app.sh")
        self.assertEqual(result.returncode, 1)
        self.assertIn("已禁用临时签名", result.stderr)
        self.assertTrue((self.bundle / "existing").exists())

    def test_unavailable_certificate_never_replaces_existing_app(self):
        self.environment["CODE_SIGN_IDENTITY"] = "Unavailable Certificate"
        self.fake("security", "printf '0 valid identities found\\n'\n")
        self.fake("swift", "exit 90\n")
        result = self.run_script("build-app.sh")
        self.assertEqual(result.returncode, 1)
        self.assertIn("找不到有效的签名身份", result.stderr)
        self.assertTrue((self.bundle / "existing").exists())


if __name__ == "__main__":
    unittest.main()
