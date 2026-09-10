"""Isolated installer checks: no real apps, identities, or user data are changed."""
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class InstallWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='clipboardboard-install-test-')
        self.root = Path(self.temp.name)
        self.source = self.root / 'source/ClipboardBoard.app'
        self.target = self.root / 'installed/ClipboardBoard.app'
        (self.source / 'Contents').mkdir(parents=True)
        (self.source / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'com.local.clipboardboard'}))
        (self.source / 'new-version').write_text('new')
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        fake = self.bin / 'codesign'
        fake.write_text('''#!/bin/bash
if [[ "$1" == "-d" ]]; then
    echo 'designated => identifier "com.local.clipboardboard" and anchor trusted'
fi
if [[ " $* " == *" -R "* && "${REJECT_IDENTITY:-}" == "1" ]]; then exit 1; fi
''')
        fake.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.bin) + ':' + os.environ['PATH'])

    def tearDown(self):
        self.temp.cleanup()

    def install(self):
        return subprocess.run([str(ROOT / 'scripts/install-app.sh'), str(self.source), str(self.target)],
                              env=self.env, capture_output=True, text=True)

    def test_first_install_copies_data_without_private_signing_material(self):
        data = self.source.parent / 'ClipboardBoardData'
        data.mkdir()
        (data / 'history.json').write_text('[]')
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.target / 'new-version').exists())
        self.assertEqual((self.target.parent / 'ClipboardBoardData/history.json').read_text(), '[]')

    def test_update_keeps_existing_history_and_replaces_only_app(self):
        self.target.mkdir(parents=True)
        (self.target / 'old-version').write_text('old')
        data = self.target.parent / 'ClipboardBoardData'
        data.mkdir()
        (data / 'history.json').write_text('keep user data')
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.target / 'old-version').exists())
        self.assertEqual((data / 'history.json').read_text(), 'keep user data')

    def test_identity_mismatch_preserves_existing_app(self):
        self.target.mkdir(parents=True)
        (self.target / 'old-version').write_text('old')
        self.env['REJECT_IDENTITY'] = '1'
        result = self.install()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.target / 'old-version').read_text(), 'old')
        self.assertFalse((self.target / 'new-version').exists())

    def test_first_install_does_not_overwrite_existing_data_directory(self):
        data = self.target.parent / 'ClipboardBoardData'
        data.mkdir(parents=True)
        (data / 'history.json').write_text('retained after reinstall')
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((data / 'history.json').read_text(), 'retained after reinstall')


if __name__ == '__main__':
    unittest.main()
