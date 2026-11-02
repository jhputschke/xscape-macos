#!/usr/bin/env python3
"""
sync_guide.py JS_CONTRIB -- write js-contrib's utils/README_Mac_Usage.md from this README.

The two are the same guide. This repository's README links to js-contrib by URL; the copy in
js-contrib's utils/ links to it relatively and to this repository by URL. Change README.md,
then run this and commit both:

    ./sync_guide.py ~/JetScape/X-SCAPE/external_packages/js-contrib
"""

import re
import sys
from pathlib import Path

JS = "https://github.com/jhputschke/js-contrib/blob/main/"
HEADER_HERE = ("> The same guide is in js-contrib, next to the container guide: "
               "[`utils/README_Mac_Usage.md`](https://github.com/jhputschke/js-contrib/blob/main/"
               "utils/README_Mac_Usage.md). Change both together.")
HEADER_THERE = ("> **Install:** the wheels and lock files are released by "
                "[jhputschke/xscape-macos](https://github.com/jhputschke/xscape-macos) "
                "([Releases](https://github.com/jhputschke/xscape-macos/releases)); this guide is "
                "also its README. The container guide for Linux with NVIDIA GPUs: "
                "[`README_Container_Usage.md`](README_Container_Usage.md).")
REPLACE = [
    (HEADER_HERE, HEADER_THERE),
    ("How it is built: [`BUILDING.md`](BUILDING.md).",
     "How it is built: [`BUILDING.md`](https://github.com/jhputschke/xscape-macos/blob/main/"
     "BUILDING.md) in the wheel's repository."),
    ("**Releases** are on [this repository's Releases page](https://github.com/jhputschke/"
     "xscape-macos/releases).",
     "**Releases** are on the [Releases page of jhputschke/xscape-macos](https://github.com/"
     "jhputschke/xscape-macos/releases), the repository that builds the wheel."),
]


def convert(text: str) -> str:
    for old, new in REPLACE:
        if old not in text:
            sys.exit(f"sync_guide.py: README.md no longer has: {old[:70]}...")
        text = text.replace(old, new)
    # js-contrib links: relative to utils/
    text = re.sub(re.escape(JS) + r"utils/", "", text)
    return re.sub(re.escape(JS), "../", text)


def main() -> int:
    js = Path(sys.argv[1] if len(sys.argv) > 1 else "").expanduser()
    target = js / "utils" / "README_Mac_Usage.md"
    if not target.is_file():
        sys.exit(f"usage: sync_guide.py JS_CONTRIB  ({target} not found)")
    here = Path(__file__).resolve().parent / "README.md"
    target.write_text(convert(here.read_text()))
    print(f"sync_guide.py: {here} -> {target}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
