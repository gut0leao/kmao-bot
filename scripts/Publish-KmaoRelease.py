#!/usr/bin/env python3
"""Publish the already-built VERSION to GitHub; never build, commit or push."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys

REPOSITORY = "gut0leao/kmao-bot"


def run(*args, cwd):
    return subprocess.run(args, cwd=cwd, text=True, check=True, capture_output=True).stdout.strip()


def prepare_release(repo, output=None, draft=False):
    version = (repo / "VERSION").read_text(encoding="utf-8-sig").strip()
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError("VERSION must contain three numbers, for example 0.3.2.")
    if output is None:
        versioned = repo / "dist" / f"release-{version}"
        output = versioned if versioned.is_dir() else repo / "dist" / "release"
    output = output.resolve()
    names = [f"kmao-setup-{version}.exe", f"kmao-{version}.zip", "kmao-manifest.json", "kmao-manifest.sig"]
    assets = [output / name for name in names]
    notes = output / "kmao-release-notes.md"
    for path in [*assets, notes]:
        if not path.is_file() or path.stat().st_size == 0:
            raise ValueError(f"Missing or empty release file: {path}. Build this version first or specify --output.")
    manifest = json.loads(assets[2].read_text(encoding="utf-8-sig"))
    if manifest.get("version") != version or manifest.get("asset") != names[1]:
        raise ValueError("The package manifest does not match VERSION. Rebuild before publishing.")
    if manifest.get("channel") != "testing":
        raise ValueError("The package must use the testing channel.")
    with assets[1].open("rb") as stream:
        checksum = hashlib.sha256()
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            checksum.update(block)
    digest = checksum.hexdigest()
    if digest != manifest.get("sha256"):
        raise ValueError("The ZIP checksum does not match the manifest. Rebuild before publishing.")
    if run("git", "status", "--porcelain", cwd=repo):
        raise ValueError("The working tree has uncommitted changes. Commit before publishing.")
    if run("git", "show", "HEAD:VERSION", cwd=repo).strip() != version:
        raise ValueError("VERSION differs from the committed version.")
    commit = run("git", "rev-parse", "HEAD", cwd=repo)
    command = ["gh", "release", "create", f"v{version}", "--repo", REPOSITORY,
               "--target", commit, "--prerelease", "--title", f"KMAO {version} — testes",
               "--notes-file", str(notes)]
    if draft:
        command.append("--draft")
    command.extend(str(path) for path in assets)
    return version, commit, command


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="Release directory (default: dist/release-VERSION, or dist/release).")
    parser.add_argument("--draft", action="store_true", help="Create an unpublished prerelease draft.")
    parser.add_argument("--dry-run", action="store_true", help="Validate local files and print the command without contacting GitHub.")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    try:
        if not shutil.which("git") or (not args.dry_run and not shutil.which("gh")):
            raise ValueError("Install git and GitHub CLI (gh); use gh auth login before publishing.")
        version, commit, command = prepare_release(repo, args.output, args.draft)
        print(f"Version: {version}\nCommit: {commit}\n{shlex.join(command)}", flush=True)
        if args.dry_run:
            return 0
        # Verify the exact local commit exists in the target repository before
        # gh creates a tag. The user controls git push separately.
        try:
            remote = run("gh", "api", f"repos/{REPOSITORY}/commits/{commit}", "--jq", ".sha", cwd=repo)
        except subprocess.CalledProcessError as error:
            raise ValueError("Cannot confirm the commit on GitHub. Run git push and check gh auth status/network.\n" + (error.stderr or "")) from error
        if remote != commit:
            raise ValueError("The GitHub commit does not match HEAD. Run git push before publishing.")
        subprocess.run(command, cwd=repo, check=True)
        return 0
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"Publication failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
