"""Verify the exact public DSH install text, with real pnpm and immutable release files."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
INSTALL = json.loads((ROOT / "releases/plugin-install.json").read_text(encoding="utf-8"))
RELEASE = json.loads((ROOT / "scripts/plugin-installer/release.json").read_text(encoding="utf-8"))
ARCHIVE = Path(os.environ["DSBOT_PLUGIN_ARCHIVE"]).resolve()
PNPM = shutil.which(os.environ.get("DSBOT_PNPM", "pnpm"))


class GitHubInstallationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not PNPM:
            raise RuntimeError("pnpm is required")
        if hashlib.sha256(ARCHIVE.read_bytes()).hexdigest() != RELEASE["sha256"]:
            raise RuntimeError("Release archive checksum mismatch")
        if INSTALL["spec"] != f'github:QingJ01/DS-Bot-App#{INSTALL["sourceCommit"]}&path:ds-bot':
            raise RuntimeError("Install text must pin the full release source commit")
        if len(INSTALL["sourceCommit"]) != 40 or INSTALL["version"] != RELEASE["version"]:
            raise RuntimeError("Invalid release source metadata")
        with tarfile.open(ARCHIVE) as archive:
            cls.files = {m.name.removeprefix("package/"): archive.extractfile(m).read()
                         for m in archive.getmembers() if m.isfile()}

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix=".dsh-test-github-install-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.profile = self.root / "用户 profile"
        self.profile.mkdir()
        (self.profile / "package.json").write_text(json.dumps({
            "name": "dsh-test-github-install", "private": True,
            "dependencies": {"is-number": "7.0.0"},
            "dsh": {"profile": {"bundles": ["ds-bot"]}},
        }), encoding="utf-8")
        (self.profile / "pnpm-workspace.yaml").write_text(
            "packages:\n  - .\n\nnodeLinker: hoisted\nautoInstallPeers: false\n", encoding="utf-8"
        )
        (self.profile / "chat-sentinel.txt").write_text("Preserve existing chats.", encoding="utf-8")

    def pnpm(self, *args, allow_failure=False, env=None):
        result = subprocess.run([
            PNPM, "--dir", str(self.profile), *args, "--store-dir", str(self.root / "store"),
            "--reporter", "append-only", "--config.fetch-retries=0",
        ], env=env, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=180)
        if not allow_failure:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def assert_installed(self):
        package = self.profile / "node_modules/ds-bot"
        for name, expected in self.files.items():
            self.assertEqual((package / name).read_bytes(), expected, name)
        manifest = json.loads((self.profile / "package.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["dependencies"]["ds-bot"], INSTALL["spec"])
        self.assertEqual(manifest["dependencies"]["is-number"], "7.0.0")
        self.assertEqual(manifest["dsh"], {"profile": {"bundles": ["ds-bot"]}})
        self.assertEqual((self.profile / "chat-sentinel.txt").read_text(), "Preserve existing chats.")
        lock = (self.profile / "pnpm-lock.yaml").read_text(encoding="utf-8")
        self.assertIn(f'tar.gz/{INSTALL["sourceCommit"]}', lock)
        self.assertIn("gitHosted: true", lock)
        self.assertNotIn(RELEASE["url"], lock)
        self.assertTrue((self.profile / "node_modules/is-number/package.json").is_file())

    def test_first_install_cached_reinstall_and_clean_frozen_install(self):
        self.pnpm("add", INSTALL["spec"])
        self.assert_installed()
        self.pnpm("remove", "ds-bot")
        self.pnpm("add", INSTALL["spec"])
        self.assert_installed()
        lock = (self.profile / "pnpm-lock.yaml").read_bytes()
        shutil.rmtree(self.profile / "node_modules")
        self.pnpm("install", "--frozen-lockfile")
        self.assert_installed()
        self.assertEqual((self.profile / "pnpm-lock.yaml").read_bytes(), lock)

    def test_failed_remote_install_recovers_from_the_same_gui_text(self):
        self.pnpm("add", RELEASE["url"])
        self.pnpm("remove", "ds-bot")
        cached = self.pnpm("add", RELEASE["url"], allow_failure=True)
        if cached.returncode:
            self.assertIn("ERR_PNPM_MISSING_TARBALL_INTEGRITY", cached.stdout + cached.stderr)
        self.pnpm("add", INSTALL["spec"])
        self.assert_installed()

    def test_no_git_or_build_approval_is_required(self):
        node = shutil.which("node")
        self.assertIsNotNone(node)
        # Exclude all Git directories while retaining Node and OS commands.
        paths = [str(Path(node).parent)]
        if os.name == "nt":
            paths.append(str(Path(os.environ["SystemRoot"]) / "System32"))
        environment = {**os.environ, "PATH": os.pathsep.join(paths)}
        self.assertIsNone(shutil.which("git", path=environment["PATH"]))
        # Scripts remain enabled: this must work without an ignore-scripts escape hatch.
        self.pnpm("add", INSTALL["spec"], env=environment)
        self.assert_installed()


if __name__ == "__main__":
    unittest.main(verbosity=2)
