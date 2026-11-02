"""
The xscape wheel's commands:

    runJetscape USER_XML [MAIN_XML]   X-SCAPE's runJetscape with this install's data, in the
                                       current directory (stops if the XML needs files it
                                       doesn't have: use xscape-run)
    xscape-run -w RUN_DIR -u USER_XML  run_in_workdir.sh: one run in its own directory, any
                                       XML as it is; checks modules, tags and inputs first
    xscape-fetch-data lbt [--from DIR] the LBT tables (236 MB download, 1.1 GB unpacked) into
                                       ~/Library/Caches/xscape, linked into this install
    xscape-selftest                    the environment: bindings, HDF5 filters, pelicanfs,
                                       paths, EOS table, LBT tables, one synthetic event

js-contrib's tools, run from the copy of utils/ in share/xscape/utils (xscape-utils copies
it), in this environment:

    xscape-osdf                        remote_transfer/js_osdf.py: production files on the OSDF
    xscape-upload-follow               upload_follow.py: upload a running production's jobs
    xscape-jobmon                      jobmon.py: watch a run_jobs.sh production
    xscape-prodwizard                  prodwizard.py: plan a production (--machine mac_wheel)
    xscape-h5-inspect                  h5_inspect.py: any HDF5 file, js-contrib formats decoded
    xscape-check-deposition            check_deposition.py: jet jobs with too little deposition
    xscape-gcs                         remote_transfer/js_gcs.py: Google Cloud Storage (its own
                                       environment in ~/.cache/js_gcs, made on first use)
"""

from __future__ import annotations

import argparse
import getopt
import hashlib
import os
import sys
import types
from pathlib import Path

from . import LBT_TABLES_COMMIT, PACKAGE, TREE, __version__, environment, lbt, xmlcheck

#: sha256 of every LBT table file, written at build time from the tables built against
LBT_SHA256 = PACKAGE / "lbt_tables.sha256"


#: exit status when a check stops a run before it starts (as X-SCAPE's run_xml.py)
EXIT_CHECK = 3
#: js-contrib's utils/, shipped in the wheel
UTILS = TREE / "utils"


def _stop(prog: str, problems: list[str], hint: str) -> int:
    for p in problems:
        print(f"{prog}: {p}", file=sys.stderr)
    print(f"{prog}: nothing was run. {hint}", file=sys.stderr)
    return EXIT_CHECK


def run_jetscape() -> None:
    args = sys.argv[1:]
    user = args[0] if args and not args[0].startswith("-") else None
    if user and os.path.isfile(user) and not os.environ.get("XSCAPE_RUN_HERE"):
        try:
            missing = xmlcheck.cwd_problems(user)
        except Exception:                        # a broken XML: X-SCAPE reports it
            missing = []
        if missing:
            sys.exit(_stop("runJetscape", [
                f"{user} reads files relative to the current directory, and "
                f"{os.getcwd()} lacks them:\n    " + "\n    ".join(missing)],
                "Run it with xscape-run, which prepares a run directory and makes the XML's "
                f"paths absolute:\n    xscape-run -w RUN_DIR -u {user}\n"
                "(XSCAPE_RUN_HERE=1 runs here anyway.)"))
    os.execve(str(PACKAGE / "bin" / "runJetscape"), ["runJetscape", *args], environment())


def _run_args(argv: list[str]) -> tuple[str | None, str | None, bool]:
    """-u, -m and -f of run_in_workdir.sh's arguments (anything else is its business)."""
    try:
        opts, _ = getopt.getopt(argv, "w:u:d:b:m:fh")
    except getopt.GetoptError:
        return None, None, False
    o = dict(opts)
    return o.get("-u"), o.get("-m"), "-f" in o


def run_in_workdir() -> None:
    argv = sys.argv[1:]
    user, main, force = _run_args(argv)
    if user and os.path.isfile(user) and not force:
        main = main or str(TREE / "config" / "jetscape_main.xml")
        try:
            problems = xmlcheck.check_run(user, main)
        except Exception as e:                   # a broken XML: run_xml.py reports it
            problems = [] if "ParseError" in type(e).__name__ else [str(e)]
        if problems:
            sys.exit(_stop("xscape-run", problems, "(-f runs anyway.)"))
    env = environment()
    env["PYTHON"] = sys.executable               # run_xml.py: this environment's Python
    os.execve("/bin/bash", ["bash", str(PACKAGE / "bin" / "run_in_workdir.sh"),
                            "-d", str(TREE), "-b", str(PACKAGE / "bin" / "runJetscape"),
                            *argv], env)


# ------------------------------------------------------------------- js-contrib's tools
def _tool(script: str, env: dict | None = None, args: list[str] | None = None) -> None:
    """Run utils/<script> of the wheel as its own __main__, under the command's name."""
    path = UTILS / script
    prog = os.path.basename(sys.argv[0])
    if not path.is_file():
        sys.exit(f"{prog}: {path} is not in this install (the xscape wheel ships js-contrib's "
                 "utils/ from 0.2.0)")
    os.environ.update(environment())
    os.environ.update(env or {})
    sys.argv = [prog, *(sys.argv[1:] if args is None else args)]
    sys.path.insert(0, str(path.parent))
    # as `python <script>` would run it, but under the command's name: runpy.run_path sets
    # sys.argv[0] to the script's path, which argparse shows in the usage
    main = types.ModuleType("__main__")
    main.__file__ = str(path)
    sys.modules["__main__"] = main
    exec(compile(path.read_text(), str(path), "exec"), main.__dict__)


#: js_osdf.py and upload_follow.py make an environment of their own in ~/.cache/js_osdf
#: unless told not to: this one has their packages (pelicanfs, google-crc32c, h5py)
_OSDF_ENV = {"JS_OSDF_NO_ENV": "1"}


def osdf() -> None:
    _tool("remote_transfer/js_osdf.py", _OSDF_ENV)


def upload_follow() -> None:
    _tool("upload_follow.py", _OSDF_ENV)


def jobmon() -> None:
    _tool("jobmon.py")


def prodwizard() -> None:
    _tool("prodwizard.py")


def h5_inspect() -> None:
    _tool("h5_inspect.py")


def check_deposition() -> None:
    _tool("check_deposition.py")


def gcs() -> None:
    _tool("remote_transfer/js_gcs.py")


def selftest() -> None:
    """The environment, after installing: this install, the LBT tables, then js-contrib's
    container/image_check.py --analysis (the bindings, HDF5 filters, pelicanfs, paths, the
    analysis packages, one synthetic event through awkward, FastJet and mplhep, MUSIC's EoS
    table)."""
    if any(a in ("-h", "--help") for a in sys.argv[1:]):
        print(selftest.__doc__.strip())
        return
    print(f"xscape-selftest: xscape {__version__} at {PACKAGE}")
    lbt_dir = TREE / "LBT-tables"
    if lbt_dir.is_dir():
        print(f"xscape-selftest: ok    LBT tables {os.path.realpath(lbt_dir)}")
    else:
        print("xscape-selftest: note  LBT tables not fetched yet: xscape-fetch-data lbt "
              "(needed by LBT and Matter's recoil)")
    _tool("container/image_check.py", args=["--analysis"])


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
