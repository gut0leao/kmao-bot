"""Validate Bash/Windows argument boundaries without invoking Windows tools."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class WslBridgeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="kmao-wsl-bridge-")
        self.root = Path(self.temporary.name)
        self.capture = self.root / "arguments.json"
        for name, source in {
            "wslpath": "import sys\nprint('WIN:' + sys.argv[2])\n",
            "powershell.exe": (
                "import json, os, sys\n"
                "from pathlib import Path\n"
                "Path(os.environ['KMAO_WSL_CAPTURE']).write_text(json.dumps(sys.argv[1:]))\n"
                "sys.exit(int(os.environ.get('KMAO_WSL_EXIT', '0')))\n"
            ),
        }.items():
            executable = self.root / name
            executable.write_text("#!/usr/bin/env python3\n" + source)
            executable.chmod(0o755)
        self.env = os.environ.copy()
        self.env.update(
            PATH=str(self.root) + os.pathsep + self.env["PATH"],
            KMAO_WSL_CAPTURE=str(self.capture),
        )
        self.bridge = Path(__file__).resolve().parents[1] / "scripts/kmao.sh"

    def tearDown(self):
        self.temporary.cleanup()

    def run_bridge(self, *arguments):
        return subprocess.run(
            ["bash", str(self.bridge), *arguments], cwd=self.root, env=self.env,
            text=True, capture_output=True, check=False,
        )

    def test_paths_with_spaces_are_passed_as_individual_arguments(self):
        result = self.run_bridge(
            "build", "--output", "release folder", "--private-key", "/mnt/c/key folder/private.xml",
            "--public-key", "/mnt/c/key folder/public.xml", "--iscc", "/mnt/c/Program Files/ISCC.exe",
            "--skip-installer",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        args = json.loads(self.capture.read_text())
        for name, value in {
            "-OutputDirectory": "WIN:" + str(self.root / "release folder"),
            "-PrivateKeyPath": "WIN:/mnt/c/key folder/private.xml",
            "-PublicKeyPath": "WIN:/mnt/c/key folder/public.xml",
            "-IsccPath": "WIN:/mnt/c/Program Files/ISCC.exe",
        }.items():
            self.assertEqual(args[args.index(name) + 1], value)
        self.assertIn("-SkipInstaller", args)
        self.assertIn("-File", args)
        self.assertNotIn("-Command", args)

    def test_windows_failure_exit_code_is_preserved(self):
        self.env["KMAO_WSL_EXIT"] = "23"
        self.assertEqual(self.run_bridge("test").returncode, 23)

    def test_invalid_arguments_do_not_invoke_powershell(self):
        for arguments in [("unknown",), ("build", "--output"), ("test", "--skip-installer"), ("doctor", "--output", "x")]:
            self.assertEqual(self.run_bridge(*arguments).returncode, 2)
            self.assertFalse(self.capture.exists())

    def test_help_does_not_require_windows_tools(self):
        result = self.run_bridge("--help")
        self.assertEqual(result.returncode, 0)
        self.assertIn("doctor", result.stdout)
        self.assertFalse(self.capture.exists())


if __name__ == "__main__":
    unittest.main()
