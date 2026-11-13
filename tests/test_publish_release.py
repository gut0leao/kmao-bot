"""Release preparation and GitHub dispatch without network or publication."""
import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("kmao_publish", Path(__file__).resolve().parents[1] / "scripts/Publish-KmaoRelease.py")
publish = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(publish)


class PublishTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="kmao-publish-")
        self.repo = Path(self.temporary.name)
        (self.repo / "VERSION").write_text("1.2.3\n")
        self.output = self.repo / "dist/release-1.2.3"
        self.output.mkdir(parents=True)
        self.zip = self.output / "kmao-1.2.3.zip"
        self.zip.write_bytes(b"archive fixture")
        self.manifest = dict(version="1.2.3", asset=self.zip.name, channel="testing", sha256=hashlib.sha256(self.zip.read_bytes()).hexdigest())
        self.save_manifest()
        for name in ["kmao-setup-1.2.3.exe", "kmao-manifest.sig", "kmao-release-notes.md"]:
            (self.output / name).write_text("fixture")
        self.git = patch.object(publish, "run", side_effect=self.fake_run)
        self.git_mock = self.git.start()
        self.addCleanup(self.git.stop)
        self.addCleanup(self.temporary.cleanup)

    def save_manifest(self):
        (self.output / "kmao-manifest.json").write_text(json.dumps(self.manifest))

    def fake_run(self, *args, **kwargs):
        return {("git", "status", "--porcelain"): "", ("git", "show", "HEAD:VERSION"): "1.2.3",
                ("git", "rev-parse", "HEAD"): "a" * 40}.get(args, "a" * 40)

    def test_version_drives_tag_assets_title_and_target(self):
        version, commit, cmd = publish.prepare_release(self.repo)
        self.assertEqual(version, "1.2.3")
        self.assertEqual(cmd[:4], ["gh", "release", "create", "v1.2.3"])
        self.assertEqual(cmd[cmd.index("--target") + 1], commit)
        self.assertIn("--prerelease", cmd)
        self.assertNotIn("--draft", cmd)
        self.assertEqual(len(cmd[-4:]), 4)
        self.assertEqual([Path(p).name for p in cmd[-4:]], ["kmao-setup-1.2.3.exe", "kmao-1.2.3.zip", "kmao-manifest.json", "kmao-manifest.sig"])

    def test_custom_output_with_spaces_and_draft(self):
        target = self.repo / "custom release folder"
        self.output.rename(target)
        _, _, cmd = publish.prepare_release(self.repo, target, draft=True)
        self.assertIn("--draft", cmd)
        self.assertEqual(Path(cmd[-1]).parent, target)

    def test_default_build_directory_fallback(self):
        self.output.rename(self.repo / "dist/release")
        _, _, cmd = publish.prepare_release(self.repo)
        self.assertEqual(Path(cmd[-1]).parent, self.repo / "dist/release")

    def test_missing_files_version_and_corrupt_archive_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "Missing"):
            publish.prepare_release(self.repo, self.repo / "absent")
        self.manifest["version"] = "9.9.9"
        self.save_manifest()
        with self.assertRaisesRegex(ValueError, "does not match VERSION"):
            publish.prepare_release(self.repo)
        self.manifest["version"] = "1.2.3"
        self.save_manifest()
        self.zip.write_bytes(b"modified")
        with self.assertRaisesRegex(ValueError, "checksum"):
            publish.prepare_release(self.repo)

    def test_invalid_version_and_uncommitted_changes(self):
        (self.repo / "VERSION").write_text("1.2.3-beta\n")
        with self.assertRaisesRegex(ValueError, "three numbers"):
            publish.prepare_release(self.repo)
        (self.repo / "VERSION").write_text("1.2.3\n")
        self.git_mock.side_effect = lambda *args, **kw: " M dev.ps1"
        with self.assertRaisesRegex(ValueError, "uncommitted"):
            publish.prepare_release(self.repo)

    def invoke_main(self, *args):
        with patch.object(publish, "__file__", str(self.repo / "scripts/Publish-KmaoRelease.py")), patch.object(sys, "argv", ["publish", *args]), patch.object(publish.shutil, "which", return_value="tool"), contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return publish.main()

    def test_dry_run_does_not_contact_github(self):
        with patch.object(publish.subprocess, "run") as dispatch:
            self.assertEqual(self.invoke_main("--dry-run"), 0)
            dispatch.assert_not_called()
        self.assertFalse(any(call.args[0] == "gh" for call in self.git_mock.call_args_list))

    def test_unpushed_commit_prevents_publication(self):
        def missing_commit(*args, **kw):
            if args[0] == "gh":
                raise subprocess.CalledProcessError(1, args, stderr="not found")
            return self.fake_run(*args, **kw)
        self.git_mock.side_effect = missing_commit
        with patch.object(publish.subprocess, "run") as dispatch:
            self.assertEqual(self.invoke_main(), 1)
            dispatch.assert_not_called()

    def test_publication_uses_checked_command(self):
        with patch.object(publish.subprocess, "run") as dispatch:
            self.assertEqual(self.invoke_main("--draft"), 0)
            command = dispatch.call_args.args[0]
            self.assertEqual(command[:4], ["gh", "release", "create", "v1.2.3"])
            self.assertIn("--draft", command)
            self.assertTrue(dispatch.call_args.kwargs["check"])


if __name__ == "__main__":
    unittest.main()
