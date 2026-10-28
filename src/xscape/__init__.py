"""
xscape: X-SCAPE for Apple Silicon Macs, with MUSIC on the Metal GPU.

This package holds an installed X-SCAPE: bin/ (runJetscape, run_in_workdir.sh), lib/ (the
libraries, MUSIC's Metal shaders; the Homebrew libraries they need in .dylibs/),
share/xscape/ (config/, EOS, iSS, 3dMCGlauber and trento data, Pythia's xmldoc and pdfdata,
the PyJetscape examples, BUILD_INFO.txt) and the compiled PyJetscape core.  The Python
interface is the ``jetscape`` package (the pyjetscape wheel), which finds all of this
through jetscape.paths; the LBT tables come separately: ``xscape-fetch-data lbt``.
"""

from __future__ import annotations

import os
from pathlib import Path

from ._build import LBT_TABLES_COMMIT, VERSION as __version__  # noqa: F401

#: this package: bin/, lib/, share/
PACKAGE = Path(os.path.abspath(__file__)).parent
#: the installed X-SCAPE tree (the data folder of a build, and config/)
TREE = PACKAGE / "share" / "xscape"


def environment(base: dict | None = None) -> dict:
    """``base`` (default: this process's environment) with what X-SCAPE's C++ code reads to
    find this install: its data folder, MUSIC's EOS, the LBT tables, Pythia's data."""
    env = dict(os.environ if base is None else base)
    env["XSCAPE_DATA_DIR"] = str(TREE)
    env["HYDROPROGRAMPATH"] = str(TREE)
    env["LBT_TABLES_PATH"] = str(TREE / "LBT-tables")
    env["PYTHIA8DATA"] = str(TREE / "Pythia8" / "xmldoc")
    return env
