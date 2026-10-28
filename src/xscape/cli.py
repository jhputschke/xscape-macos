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
import sys
from pathlib import Path

from . import LBT_TABLES_COMMIT, PACKAGE, TREE, environment, lbt

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
            lbt.download(target, LBT_TABLES_COMMIT)
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
