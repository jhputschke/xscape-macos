"""
The LBT tables (JETSCAPE/LBT-tables): fetched at one commit and their split archive put back
together, as external_packages/get_lbtTab.sh does (which needs bash 4).  Standard library
only, so release.sh runs it as a script too:

    python lbt.py TARGET_DIR COMMIT
"""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

LBT_REPO = "https://github.com/JETSCAPE/LBT-tables.git"


def download(target: Path, commit: str) -> None:
    """LBT-tables at ``commit`` into ``target`` (must not exist)."""
    target = Path(target)
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=target.parent) as tmp:
        repo = Path(tmp) / "repo"
        print(f"LBT tables: {LBT_REPO} at {commit[:7]} ...", flush=True)
        for cmd in (["git", "init", "-q", str(repo)],
                    ["git", "-C", str(repo), "fetch", "-q", "--depth", "1", LBT_REPO, commit],
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


if __name__ == "__main__":
    download(Path(sys.argv[1]), sys.argv[2])
