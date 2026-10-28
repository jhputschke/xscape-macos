"""
The xscape wheel's commands:

    runJetscape USER_XML [MAIN_XML]   X-SCAPE's runJetscape with this install's data
    xscape-run -w RUN_DIR -u USER_XML  run_in_workdir.sh: one run in its own directory
    xscape-fetch-data lbt [--from DIR] the LBT tables (236 MB download, 1.1 GB unpacked) into
                                       ~/Library/Caches/xscape, linked into this install
"""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

from . import LBT_TABLES_COMMIT, PACKAGE, TREE, environment

LBT_REPO = "https://github.com/JETSCAPE/LBT-tables.git"
#: sha256 of every LBT table file, written at build time from the tables built against
LBT_SHA256 = PACKAGE / "lbt_tables.sha256"


def run_jetscape() -> None:
    os.execve(str(PACKAGE / "bin" / "runJetscape"), ["runJetscape", *sys.argv[1:]],
              environment())


def run_in_workdir() -> None:
    os.execve("/bin/bash", ["bash", str(PACKAGE / "bin" / "run_in_workdir.sh"),
                            "-d", str(TREE), "-b", str(PACKAGE / "bin" / "runJetscape"),
                            *sys.argv[1:]], environment())


def _cache() -> Path:
    return Path(os.environ.get("XSCAPE_CACHE", Path.home() / "Library" / "Caches" / "xscape"))


def _check_lbt(tables: Path) -> list[str]:
    """Files of ``tables`` whose sha256 differs from the build's (empty: all match)."""
    bad = []
    for line in LBT_SHA256.read_text().splitlines():
        digest, name = line.split(maxsplit=1)
        f = tables / name
        h = hashlib.sha256()
        try:
            with open(f, "rb") as fh:
                for block in iter(lambda: fh.read(1 << 22), b""):
                    h.update(block)
        except OSError:
            bad.append(name)
            continue
        if h.hexdigest() != digest:
            bad.append(name)
    return bad


def _download_lbt(target: Path) -> None:
    """JETSCAPE/LBT-tables at the pinned commit, its split archive put back together into
    ``target`` (what external_packages/get_lbtTab.sh does)."""
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=target.parent) as tmp:
        repo = Path(tmp) / "repo"
        print(f"xscape-fetch-data: {LBT_REPO} at {LBT_TABLES_COMMIT[:7]} ...", flush=True)
        for cmd in (["git", "init", "-q", str(repo)],
                    ["git", "-C", str(repo), "fetch", "-q", "--depth", "1", LBT_REPO,
                     LBT_TABLES_COMMIT],
                    ["git", "-C", str(repo), "checkout", "-q", "FETCH_HEAD"]):
            subprocess.run(cmd, check=True)
        parts = Path(tmp) / "parts"
        parts.mkdir()
        for archive in sorted((repo / "LBT-tables-split-archive").glob("*.tar.gz")):
            with tarfile.open(archive) as tf:
                tf.extractall(parts, filter="data")
        out = Path(tmp) / "LBT-tables"
        out.mkdir()
        groups: dict[str, list[tuple[int, Path]]] = {}
        for f in parts.iterdir():
            m = re.match(r"(.+)\.part(\d+)$", f.name)
            if not m:
                raise RuntimeError(f"unexpected file in the LBT archive: {f.name}")
            groups.setdefault(m.group(1), []).append((int(m.group(2)), f))
        for name, pieces in groups.items():
            with open(out / name, "wb") as dst:
                for _, piece in sorted(pieces):
                    with open(piece, "rb") as src:
                        shutil.copyfileobj(src, dst)
        out.rename(target)


def fetch_data(argv=None) -> int:
    p = argparse.ArgumentParser(prog="xscape-fetch-data",
                                description="Fetch the data that is not in the wheel.")
    p.add_argument("what", choices=["lbt"], help="lbt: the LBT tables")
    p.add_argument("--from", dest="src", metavar="DIR",
                   help="use LBT tables already on disk (e.g. a checkout's "
                        "external_packages/LBT-tables): checked, then linked, not copied")
    a = p.parse_args(argv)
    if a.src:
        target = Path(a.src).expanduser().resolve()
    else:
        target = _cache() / f"LBT-tables-{LBT_TABLES_COMMIT[:7]}"
        if not target.is_dir():
            _download_lbt(target)
    bad = _check_lbt(target)
    if bad:
        print(f"xscape-fetch-data: {target}: {len(bad)} file(s) missing or different from the "
              f"build's: {', '.join(bad[:5])}", file=sys.stderr)
        return 1
    link = TREE / "LBT-tables"
    if link.is_symlink():
        link.unlink()
    elif link.exists():
        print(f"xscape-fetch-data: {link} is a directory; left as it is", file=sys.stderr)
        return 1
    link.symlink_to(target, target_is_directory=True)
    print(f"xscape-fetch-data: LBT tables {target} (checked) -> {link}")
    return 0
