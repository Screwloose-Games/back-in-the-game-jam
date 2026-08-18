"""Publish the exported web build to itch.io through butler.

The local counterpart of .github/workflows/publish-to-itchio.yml: same zip layout, same
channel, so a hand-run publish and a tag-triggered one land in the same upload slot rather
than creating a second download. Credentials come from .env -- see .env.example.

Usage:
  python tools/publish-itch.py                    # dry run: what would be pushed
  python tools/publish-itch.py --apply            # zip releases/web and push it
  python tools/publish-itch.py --build --apply    # export the Web preset first, then push
  python tools/publish-itch.py --apply --version 1.2.0
"""

from __future__ import annotations

import argparse
import io
import os
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

from godot_bin import WINDOWS, find_godot, find_project_root

DEFAULT_USER = "jonathandavidlewis"
DEFAULT_GAME = "back-in-the-game-jam"
# Must match CHANNEL in publish-to-itchio.yml. A different name here would silently open a
# second channel on the page instead of updating the existing web build.
DEFAULT_CHANNEL = "web"

# The itch.io download page links expire, so they cannot be hard-coded; broth always serves
# the current stable build. Only amd64 is published -- Apple Silicon runs it under Rosetta.
BROTH_URL = "https://broth.itch.zone/butler/{channel}-amd64/LATEST/archive/default"
COI_URL = (
    "https://raw.githubusercontent.com/gzuidhof/coi-serviceworker/master/coi-serviceworker.js"
)
COI_TAG = '<script src="coi-serviceworker.js"></script>'
COI_NAME = "coi-serviceworker.js"

CACHE_DIR = Path(__file__).parent / ".cache"

# index.js loads index.side.wasm unconditionally, so a missing one of these will not boot.
REQUIRED_FILES = ("index.html", "index.js", "index.wasm", "index.side.wasm", "index.pck")

# The .import sidecars are the editor's doing and .deploy-manifest.json belongs to
# deploy-cloudflare.py; neither is something the runtime asks for.
EXCLUDED_NAMES = {".deploy-manifest.json"}
EXCLUDED_SUFFIXES = {".import"}


def human_size(size: int) -> str:
    mib = size / (1024 * 1024)
    return f"{mib:8.2f} MiB" if mib >= 0.01 else f"{size:8d} B  "


def load_env(project_root: Path) -> None:
    """Read .env if python-dotenv is installed; it is in no requirements file here."""
    try:
        from dotenv import load_dotenv
    except ImportError:
        return
    load_dotenv(project_root / ".env")


def resolve_api_key(required: bool) -> str:
    """The key only has to be present for a real push; a dry run just reports."""
    # butler reads BUTLER_API_KEY, so the repo's own name maps onto it here.
    key = os.environ.get("BUTLER_CREDENTIALS") or os.environ.get("BUTLER_API_KEY", "")
    if key:
        return key

    complaint = (
        "BUTLER_CREDENTIALS not set.\n"
        "Copy .env.example to .env and fill it in, or export the variable.\n"
        "Mint a key at https://itch.io/user/settings/api-keys, or run `butler login` once "
        "and read ~/.config/itch/butler_creds."
    )
    if required:
        sys.exit(complaint)
    print(f"WARNING: {complaint}\n")
    return ""


def fetch(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=60) as response:
        return response.read()


def install_butler(target_dir: Path) -> str:
    """Download the current stable butler from broth into tools/.cache/."""
    channel = "windows" if WINDOWS else ("darwin" if sys.platform == "darwin" else "linux")
    url = BROTH_URL.format(channel=channel)
    print(f"butler is not on PATH -- downloading {channel}-amd64 from broth")
    try:
        archive = fetch(url)
    except (urllib.error.URLError, OSError) as error:
        sys.exit(
            f"Could not download butler from {url}: {error}\n"
            "Install it from https://itchio.itch.io/butler and put it on PATH, or point "
            "BUTLER_BIN at the binary."
        )

    target_dir.mkdir(parents=True, exist_ok=True)
    # The archive also carries two 7-zip helper libraries; push does not need them, but
    # extracting everything keeps any other butler subcommand working too.
    with zipfile.ZipFile(io.BytesIO(archive)) as bundle:
        bundle.extractall(target_dir)

    binary = target_dir / ("butler.exe" if WINDOWS else "butler")
    if not binary.is_file():
        sys.exit(f"The broth archive did not contain {binary.name}.")
    binary.chmod(binary.stat().st_mode | 0o111)
    print(f"  installed {binary}")
    return str(binary)


def find_butler(required: bool) -> str | None:
    override = os.environ.get("BUTLER_BIN")
    if override:
        if not Path(override).is_file():
            sys.exit(f"BUTLER_BIN points at a missing file: {override}")
        return override

    found = shutil.which("butler")
    if found:
        return found

    cached = CACHE_DIR / "butler" / ("butler.exe" if WINDOWS else "butler")
    if cached.is_file():
        return str(cached)

    if not required:
        print("WARNING: butler is not on PATH. --apply would download it from broth.\n")
        return None
    return install_butler(cached.parent)


def git_version(project_root: Path) -> str | None:
    """A tag-shaped version when there is one, else <tag>-<n>-g<sha>, else the bare sha."""
    try:
        result = subprocess.run(
            ["git", "describe", "--tags", "--always", "--dirty"],
            cwd=project_root,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if result.returncode != 0:
        return None
    # The workflow pushes the tag name; strip the v so both spell 1.2.0 the same way.
    return result.stdout.strip().lstrip("v") or None


def collect_files(build_dir: Path) -> list[Path]:
    if not build_dir.is_dir():
        sys.exit(
            f"No build at {build_dir}.\n"
            "Export one first: python tools/publish-itch.py --build --apply"
        )

    files = sorted(
        path
        for path in build_dir.rglob("*")
        if path.is_file()
        and path.suffix not in EXCLUDED_SUFFIXES
        and path.name not in EXCLUDED_NAMES
    )

    names = {path.name for path in files}
    absent = [name for name in REQUIRED_FILES if name not in names]
    if absent:
        sys.exit(
            f"{build_dir} is missing {', '.join(absent)}.\n"
            "The export is incomplete -- re-run with --build, or check the Web preset."
        )
    return files


def coi_service_worker() -> bytes | None:
    """The cross-origin-isolation shim, cached so a repeat publish needs no network."""
    cached = CACHE_DIR / COI_NAME
    if cached.is_file():
        return cached.read_bytes()
    try:
        script = fetch(COI_URL)
    except (urllib.error.URLError, OSError) as error:
        print(f"WARNING: could not fetch {COI_NAME}: {error}")
        return None
    cached.parent.mkdir(parents=True, exist_ok=True)
    cached.write_bytes(script)
    return script


def inject_coi(html: str) -> str:
    if COI_TAG in html:
        return html
    marker = "<head>"
    index = html.find(marker)
    if index < 0:
        print(f"WARNING: no <head> in index.html, cannot inject {COI_NAME}.")
        return html
    cut = index + len(marker)
    return f"{html[:cut]}\n\t\t{COI_TAG}{html[cut:]}"


def build_zip(build_dir: Path, files: list[Path], zip_path: Path, coi: bytes | None) -> None:
    """Pack the build with index.html at the ROOT -- itch's HTML5 player 404s on a nested one."""
    zip_path.parent.mkdir(parents=True, exist_ok=True)
    # Stored, not deflated: butler unpacks the zip and diffs the files, so compressing here
    # only burns CPU on an already-compressed 78 MiB pack. It also keeps patches small --
    # a recompressed blob makes a one-byte change look like a whole-file rewrite.
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_STORED) as bundle:
        for path in files:
            name = path.relative_to(build_dir).as_posix()
            # Written from memory rather than copied, so releases/web stays a clean export
            # and a second run cannot inject the shim twice.
            if coi and name == "index.html":
                bundle.writestr(name, inject_coi(path.read_text(encoding="utf-8")))
            else:
                bundle.write(path, name)
        if coi:
            bundle.writestr(COI_NAME, coi)


def push(butler: str, zip_path: Path, target: str, version: str | None, key: str) -> None:
    args = [butler, "push", str(zip_path), target]
    if version:
        args += ["--userversion", version]
    print(f"Pushing {zip_path.name} to {target}")
    result = subprocess.run(
        args,
        env={**os.environ, "BUTLER_API_KEY": key},
        text=True,
        # butler banners its progress with box-drawing characters, which the Windows
        # default codec cannot decode -- without this the read thread dies instead.
        encoding="utf-8",
        errors="replace",
    )
    if result.returncode != 0:
        sys.exit(f"butler push failed (exit {result.returncode}).")


def export_web_build(project_root: Path, build_dir: Path) -> None:
    # Godot fails the export rather than creating a missing output directory.
    build_dir.mkdir(parents=True, exist_ok=True)
    godot = find_godot()
    print(f"Exporting with {godot}")
    subprocess.run(
        [
            godot,
            "--headless",
            "--path",
            str(project_root),
            "--export-release",
            "Web",
            str(build_dir / "index.html"),
        ],
        check=True,
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Publish the exported web build to itch.io with butler."
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Actually zip and push. Without it, print the plan and stop.",
    )
    parser.add_argument(
        "--build", action="store_true", help="Run the headless Web export first."
    )
    parser.add_argument(
        "--dir", metavar="PATH", help="Build directory (default: releases/web)."
    )
    parser.add_argument(
        "--zip", metavar="PATH", help="Zip to write (default: releases/game_web.zip)."
    )
    parser.add_argument("--user", metavar="NAME", help="itch.io user (default: $ITCH_USERNAME).")
    parser.add_argument("--game", metavar="SLUG", help="itch.io game (default: $GAME_SLUG).")
    parser.add_argument(
        "--channel", metavar="NAME", help=f"butler channel (default: {DEFAULT_CHANNEL})."
    )
    parser.add_argument(
        "--version",
        metavar="STRING",
        help="User version (default: git describe; blank lets itch auto-increment).",
    )
    parser.add_argument(
        "--no-coi",
        action="store_true",
        help="Skip the coi-serviceworker shim. The build needs cross-origin isolation for "
        "threads, so only skip this if itch's SharedArrayBuffer option is on.",
    )
    args = parser.parse_args()

    # utf-8 because echoing butler's progress banners through cp1252 would raise; line
    # buffering because otherwise our progress trails the subprocess output it labels.
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(encoding="utf-8", errors="replace", line_buffering=True)

    project_root = find_project_root(Path(__file__).parent)
    load_env(project_root)

    user = args.user or os.environ.get("ITCH_USERNAME") or DEFAULT_USER
    game = args.game or os.environ.get("GAME_SLUG") or DEFAULT_GAME
    channel = args.channel or os.environ.get("ITCH_CHANNEL") or DEFAULT_CHANNEL
    target = f"{user}/{game}:{channel}"

    build_dir = Path(args.dir) if args.dir else project_root / "releases/web"
    zip_path = Path(args.zip) if args.zip else project_root / "releases/game_web.zip"
    version = args.version or git_version(project_root)

    key = resolve_api_key(required=args.apply)
    butler = find_butler(required=args.apply)

    if args.build:
        if not args.apply:
            print(f"Would export the Web preset to {build_dir}")
        else:
            export_web_build(project_root, build_dir)

    files = collect_files(build_dir)

    print(f"Build:    {build_dir}")
    print(f"Zip:      {zip_path}")
    print(f"Target:   https://{user}.itch.io/{game}  ({target})")
    print(f"Version:  {version or '<auto-incremented by itch.io>'}")
    print(f"Auth:     BUTLER_API_KEY={'<set>' if key else '<missing>'}")
    print(f"butler:   {butler or '<missing>'}")
    print(f"COI shim: {'skipped' if args.no_coi else 'injected into index.html'}")
    print()

    total = 0
    for path in files:
        size = path.stat().st_size
        total += size
        print(f"  {human_size(size)}  {path.relative_to(build_dir).as_posix()}")
    print(f"  {human_size(total)}  total")
    print()

    if not args.apply:
        print("Dry run. Re-run with --apply to zip and push.")
        return 0

    coi = None if args.no_coi else coi_service_worker()
    if coi is None and not args.no_coi:
        print(
            "Continuing without the shim -- tick \"SharedArrayBuffer support\" in the "
            "itch.io embed options or the build will not boot.\n"
        )

    print(f"Zipping {len(files)} file(s) into {zip_path}")
    build_zip(build_dir, files, zip_path, coi)
    print(f"  {human_size(zip_path.stat().st_size).strip()}\n")

    push(butler, zip_path, target, version, key)

    print()
    print(f"Live at https://{user}.itch.io/{game}")
    print(
        "First publish only: set the page Kind to HTML and tag the channel "
        '"playable in browser" on the Edit game page, then Save.'
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
