import copy
import hashlib
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location("legacy_release", ROOT / "scripts/restore-legacy-release.py")
legacy = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(legacy)


def manifest():
    return "".join(f"{digest}  {name}\n" for name, digest in {
        legacy.PLUGIN: legacy.REPUBLISHED_SHA256,
        **{name: "a" * 64 for name in legacy.OTHER_FILES},
    }.items())


class FakeGithub:
    def __init__(self):
        self.data = {"SHA256SUMS": manifest().encode(), legacy.PLUGIN: b"later package"}
        self.state = {"id": 1, "body": "Historical release notes", "assets": [
            {"id": index + 1, "name": name, "size": 10} for index, name in enumerate([legacy.PLUGIN, "SHA256SUMS", *sorted(legacy.OTHER_FILES)])]}
        self.tag = {"sha": "fixed-source", "type": "commit"}
        self.mutations = 0

    def release(self):
        return copy.deepcopy(self.state)

    def assets(self):
        return {a["name"]: a for a in self.release()["assets"]}

    def download(self, name):
        return self.data[name]

    def ensure_asset(self, name, data):
        if name not in self.assets():
            self.mutations += 1
            self.state["assets"].append({"id": len(self.state["assets"]) + 1, "name": name, "size": len(data)})
            self.data[name] = data
        if self.data[name] != data:
            raise ValueError("Existing recovery asset differs")
        return self.assets()[name]

    def rename(self, item, name):
        self.mutations += 1
        if name in self.assets():
            raise ValueError("Asset already exists")
        current = next(a for a in self.state["assets"] if a["id"] == item["id"])
        self.data[name] = self.data.pop(current["name"])
        current["name"] = name
        return copy.deepcopy(current)

    def api(self, endpoint, data=None):
        if endpoint == "git/ref/tags/" + legacy.TAG:
            return {"object": self.tag}
        if endpoint == "releases/1" and data is not None:
            self.mutations += 1
            self.state["body"] = data["body"]
            return self.release()
        raise ValueError(endpoint)


class LegacyReleaseTests(unittest.TestCase):
    def test_saved_archive_matches_original_user_lockfile(self):
        data = (ROOT / "releases/legacy" / legacy.PLUGIN).read_bytes()
        legacy.validate_original(data)
        with self.assertRaises(ValueError):
            legacy.validate_original(data + b"changed")

    def test_manifest_restores_original_and_preserves_republication(self):
        text = legacy.restored_checksums(manifest()).decode()
        self.assertIn(legacy.ORIGINAL_SHA256 + "  " + legacy.PLUGIN, text)
        self.assertIn(legacy.REPUBLISHED_SHA256 + "  " + legacy.ARCHIVED, text)
        for name in legacy.OTHER_FILES:
            self.assertIn("a" * 64 + "  " + name, text)

    def test_unexpected_or_duplicate_manifest_is_rejected(self):
        for text in [manifest().replace(legacy.REPUBLISHED_SHA256, "b" * 64), manifest() + manifest(), manifest() + "a" * 64 + "  ../unrelated\n"]:
            with self.assertRaises(ValueError):
                legacy.restored_checksums(text)

    def test_unexpected_public_package_is_not_replaced(self):
        github = FakeGithub()
        with self.assertRaises(ValueError):
            legacy.restore(github)
        self.assertEqual(github.mutations, 0)

    def test_restore_preserves_tag_apks_archived_bytes_and_is_repeatable(self):
        github = FakeGithub()
        # The fake republication is small; integrity guards still compare its actual bytes.
        digest = hashlib.sha256(github.data[legacy.PLUGIN]).hexdigest()
        from unittest.mock import patch
        with patch.object(legacy, "REPUBLISHED_SHA256", digest):
            github.data["SHA256SUMS"] = manifest().encode()
            original = github.release()
            legacy.restore(github)
            state = github.release()
            self.assertEqual(github.data[legacy.ARCHIVED], b"later package")
            self.assertEqual(github.data[legacy.PLUGIN], (ROOT / "releases/legacy" / legacy.PLUGIN).read_bytes())
            self.assertEqual(len(state["assets"]), 7)
            for item in original["assets"]:
                if item["name"] in legacy.OTHER_FILES:
                    self.assertEqual(github.assets()[item["name"]], item)
            mutations = github.mutations
            legacy.restore(github)
            self.assertEqual(github.mutations, mutations)
            self.assertEqual(github.release(), state)

    def test_interrupted_asset_rename_can_resume_without_overwriting_bytes(self):
        github = FakeGithub()
        from unittest.mock import patch
        digest = hashlib.sha256(github.data[legacy.PLUGIN]).hexdigest()
        original_rename = github.rename
        def interrupted(item, name):
            result = original_rename(item, name)
            if name == legacy.ARCHIVED:
                raise RuntimeError("Network interrupted after preserving old archive")
            return result
        with patch.object(legacy, "REPUBLISHED_SHA256", digest):
            github.data["SHA256SUMS"] = manifest().encode()
            with patch.object(github, "rename", side_effect=interrupted):
                with self.assertRaises(RuntimeError):
                    legacy.restore(github)
            legacy.restore(github)
            self.assertEqual(github.data[legacy.ARCHIVED], b"later package")
            self.assertEqual(github.data[legacy.PLUGIN], (ROOT / "releases/legacy" / legacy.PLUGIN).read_bytes())
            self.assertEqual(len(github.release()["assets"]), 7)
