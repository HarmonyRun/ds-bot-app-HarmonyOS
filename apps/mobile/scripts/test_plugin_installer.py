import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location("plugin_installer", ROOT / "scripts/build-plugin-installer.py")
INSTALLER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(INSTALLER)


class PluginInstallerTests(unittest.TestCase):
    def test_untrusted_archive_is_rejected_before_creating_output(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            archive = path / "package.tgz"
            archive.write_bytes(b"unexpected release bytes")
            with self.assertRaisesRegex(ValueError, "checksum mismatch"):
                INSTALLER.build(archive, path / "out")
            self.assertFalse((path / "out").exists())
