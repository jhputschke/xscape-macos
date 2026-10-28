"""
The LBT tables (JETSCAPE/LBT-tables): GitHub's archive of one commit (no git needed: a Mac
without the Command Line Tools has none), its split archive put back together, as
external_packages/get_lbtTab.sh does (which needs bash 4).  Standard library only, so
release.sh runs it as a script too:

    python lbt.py TARGET_DIR COMMIT
"""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

LBT_ARCHIVE = "https://github.com/JETSCAPE/LBT-tables/archive/{commit}.tar.gz"


def download(target: Path, commit: str) -> None:
    """LBT-tables at ``commit`` into ``target`` (must not exist)."""
    target = Path(target)
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=target.parent) as tmp:
        url = LBT_ARCHIVE.format(commit=commit)
        print(f"LBT tables: {url} (about 240 MB) ...", flush=True)
        download = Path(tmp) / "lbt.tar.gz"
        try:
            with urllib.request.urlopen(url) as r, open(download, "wb") as f:
                shutil.copyfileobj(r, f, 1 << 22)
        except urllib.error.URLError:
            # a Python without CA certificates (python.org's before "Install Certificates"):
            # macOS's curl, with the system's trust store
            subprocess.run(["/usr/bin/curl", "-fsSL", "-o", str(download), url], check=True)
        with tarfile.open(download) as tf:
            tf.extractall(Path(tmp) / "repo", filter="data")
        download.unlink()
        repo = next((Path(tmp) / "repo").iterdir())          # LBT-tables-<commit>/
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
