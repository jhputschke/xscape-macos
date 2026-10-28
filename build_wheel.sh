#!/bin/bash
# build_wheel.sh -- build the xscape wheel (macOS arm64, Metal) and the pyjetscape wheel.
#
#   XSCAPE_SRC=~/JetScape/X-SCAPE ./build_wheel.sh
#
# XSCAPE_SRC: an X-SCAPE checkout with its external_packages fetched (get_*.sh), js-contrib
# included.  LBT_TABLES_DIR: the LBT tables the checksums come from (default: the checkout's).  The checkout is built in build/cmake (its own build_* trees are not touched;
# PyJetscape's core goes to build/cmake/pyjetscape, not into the checkout).  Steps:
#   1. CMake: USE_METAL, USE_ROOT=OFF, macOS $MACOSX_DEPLOYMENT_TARGET, PyJetscape
#   2. cmake --install --component xscape_runtime into build/stage/xscape
#   3. the xscape package, Pythia's xmldoc + pdfdata, the examples, BUILD_INFO.txt,
#      the LBT tables' checksums
#   4. wheel pack, then delocate-wheel (the Homebrew libraries into the wheel)
#   5. the pyjetscape wheel (pure Python, from js-contrib)
#   6. a hashed lock: uv pip compile
# Tools: python3 $PYTHON_VERSION with pybind11 >= 3 (PYTHON_BIN), uv, delocate-wheel and
# the wheel package (TOOLS_BIN: a venv's bin with them).  Homebrew: gsl, boost, hdf5,
# pythia, libomp.  Xcode with the Metal toolchain.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/pins.env"
XSCAPE_SRC=${XSCAPE_SRC:?set XSCAPE_SRC to the X-SCAPE checkout}
XSCAPE_SRC=$(cd "$XSCAPE_SRC" && pwd)
PYTHON_BIN=${PYTHON_BIN:-python3}
TOOLS_BIN=${TOOLS_BIN:-}
UV=${TOOLS_BIN:+$TOOLS_BIN/}uv
DELOCATE=${TOOLS_BIN:+$TOOLS_BIN/}delocate-wheel
LISTDEPS=${TOOLS_BIN:+$TOOLS_BIN/}delocate-listdeps
WHEELPY=${TOOLS_BIN:+$TOOLS_BIN/}python
BUILD=$HERE/build/cmake
STAGE=$HERE/build/stage
DIST=$HERE/dist
JS=$XSCAPE_SRC/external_packages/js-contrib
PYJS=$JS/contribs/PyJetscape
PYTAG=cp${PYTHON_VERSION/./}
JOBS=${JOBS:-$(sysctl -n hw.ncpu)}

say() { printf '\n== %s\n' "$*"; }

pyver=$("$PYTHON_BIN" -c 'import sys; print("%d.%d" % sys.version_info[:2])')
[ "$pyver" = "$PYTHON_VERSION" ] || { echo "PYTHON_BIN is Python $pyver, need $PYTHON_VERSION" >&2; exit 1; }
grep -q "^version = \"$PYJETSCAPE_VERSION\"" "$PYJS/pyproject.toml" \
  || { echo "js-contrib's pyjetscape is not version $PYJETSCAPE_VERSION" >&2; exit 1; }

say "1. configure and build ($BUILD)"
mkdir -p "$HERE/build"
# a build tree configured for another source tree can't be reused
if [ -f "$BUILD/CMakeCache.txt" ] && ! grep -qx "CMAKE_HOME_DIRECTORY:INTERNAL=$XSCAPE_SRC" "$BUILD/CMakeCache.txt"; then
  rm -rf "$BUILD"
fi
cmake -S "$XSCAPE_SRC" -B "$BUILD" -Wno-dev \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
  -DUSE_METAL=ON -DUSE_ROOT=OFF -DUSE_MUSIC=ON -DUSE_ISS=ON -DUSE_3DGlauber=ON \
  -DUSE_JS_CONTRIB=ON -DUSE_JS_PYJETSCAPE=ON -DUSE_JS_FNO_HYDRO=OFF -DUSE_SMASH=OFF \
  -DPython3_EXECUTABLE="$(command -v "$PYTHON_BIN")" \
  -DPYJETSCAPE_CORE_OUTPUT_DIR="$BUILD/pyjetscape" -DPYJETSCAPE_INSTALL_DIR=. \
  -DCMAKE_INSTALL_PREFIX="$STAGE/xscape" > "$HERE/build/configure.log"
cmake --build "$BUILD" -j "$JOBS" > "$HERE/build/build.log"

say "2. install component xscape_runtime"
rm -rf "$STAGE"
cmake --install "$BUILD" --component xscape_runtime --prefix "$STAGE/xscape" > "$HERE/build/install.log"
PKG=$STAGE/xscape
TREE=$PKG/share/xscape
# 3dMCGlauber reads LHAPDF's data (share/); its library, headers and tools are not needed
rm -rf "$TREE/LHAPDF_Lib/bin" "$TREE/LHAPDF_Lib/include" "$TREE/LHAPDF_Lib/lib"

say "3. package, Pythia data, examples, BUILD_INFO.txt"
cp "$HERE"/src/xscape/*.py "$PKG/"
printf 'VERSION = "%s"\nLBT_TABLES_COMMIT = "%s"\n' "$XSCAPE_VERSION" "$LBT_TABLES_COMMIT" > "$PKG/_build.py"
PYTHIA=$(brew --prefix pythia)
pythia_lib=$(sed -n 's/.*"Pythia:versionNumber".*default="\([0-9.]*\)".*/\1/p' "$PYTHIA/share/Pythia8/xmldoc/Version.xml")
pythia_brew=$(brew list --versions pythia | awk '{print $2}')
case "$pythia_brew" in "$pythia_lib"*) ;; *)
  echo "Pythia xmldoc $pythia_lib does not match Homebrew pythia $pythia_brew" >&2; exit 1 ;; esac
mkdir -p "$TREE/Pythia8"
cp -R "$PYTHIA/share/Pythia8/xmldoc" "$PYTHIA/share/Pythia8/pdfdata" "$TREE/Pythia8/"
mkdir -p "$TREE/examples"
(cd "$PYJS/example" && git ls-files -z . | tar --null -T - -cf -) | tar -C "$TREE/examples" -xf -
{
  echo "# xscape $XSCAPE_VERSION, built $(date -u +%Y-%m-%dT%H:%M:%SZ) on $(hostname -s)"
  for d in . external_packages/music4gpu external_packages/iSS external_packages/3dMCGlauber \
           external_packages/js-contrib; do
    echo "$d $(git -C "$XSCAPE_SRC/$d" rev-parse HEAD) $(git -C "$XSCAPE_SRC/$d" status --porcelain --untracked-files=no | wc -l | tr -d ' ') modified"
  done
  echo "LBT-tables $LBT_TABLES_COMMIT (not in the wheel: xscape-fetch-data lbt)"
  echo "macOS $(sw_vers -productVersion), $(xcodebuild -version | tr '\n' ' ')"
  echo "deployment target $MACOSX_DEPLOYMENT_TARGET, Python $("$PYTHON_BIN" -V 2>&1 | cut -d' ' -f2)"
  echo "Homebrew: $(brew list --versions gsl boost hdf5 pythia libomp | tr '\n' ' ')"
  echo "MUSIC music4gpu (Metal), USE_ROOT=OFF"
} > "$TREE/BUILD_INFO.txt"
cat "$TREE/BUILD_INFO.txt"
(cd "${LBT_TABLES_DIR:-$XSCAPE_SRC/external_packages/LBT-tables}" && find . -type f ! -name '.*' | sed 's|^\./||' | sort \
  | while read -r f; do printf '%s  %s\n' "$(shasum -a 256 "$f" | cut -d' ' -f1)" "$f"; done) \
  > "$PKG/lbt_tables.sha256"

say "4. wheel pack + delocate"
DI=$STAGE/xscape-$XSCAPE_VERSION.dist-info
mkdir -p "$DI"
cat > "$DI/METADATA" <<EOF
Metadata-Version: 2.1
Name: xscape
Version: $XSCAPE_VERSION
Summary: X-SCAPE with MUSIC on the Metal GPU, for Apple Silicon Macs
License: GPL-3.0-or-later
Requires-Python: ==$PYTHON_VERSION.*
Requires-Dist: pyjetscape==$PYJETSCAPE_VERSION
EOF
cat > "$DI/WHEEL" <<EOF
Wheel-Version: 1.0
Generator: xscape-macos build_wheel.sh
Root-Is-Purelib: false
Tag: $PYTAG-$PYTAG-macosx_${MACOSX_DEPLOYMENT_TARGET/./_}_arm64
EOF
cat > "$DI/entry_points.txt" <<EOF
[console_scripts]
runJetscape = xscape.cli:run_jetscape
xscape-run = xscape.cli:run_in_workdir
xscape-fetch-data = xscape.cli:fetch_data
EOF
echo xscape > "$DI/top_level.txt"
rm -rf "$DIST"; mkdir -p "$DIST/raw"
"$WHEELPY" -m wheel pack "$STAGE" -d "$DIST/raw"
"$DELOCATE" --require-archs arm64 -w "$DIST" "$DIST"/raw/xscape-*.whl
left=$("$LISTDEPS" --all "$DIST"/xscape-*.whl | grep -E '^/(opt|usr/local)/' || true)
[ -z "$left" ] || { echo "libraries outside the wheel left: $left" >&2; exit 1; }

say "5. pyjetscape wheel"
# from the tracked files only: no in-tree core, and setuptools' build/ and egg-info stay out
# of the checkout
rm -rf "$HERE/build/pyjetscape_src"; mkdir -p "$HERE/build/pyjetscape_src"
(cd "$PYJS" && git ls-files -z . | tar --null -T - -cf -) | tar -C "$HERE/build/pyjetscape_src" -xf -
"$UV" build --wheel --out-dir "$DIST" "$HERE/build/pyjetscape_src" > "$HERE/build/pyjetscape_build.log" 2>&1
if unzip -l "$DIST"/pyjetscape-*.whl | grep -q 'pyjetscape_core'; then
  echo "the pyjetscape wheel contains a compiled core" >&2; exit 1
fi

say "6. lock"
# uv takes the target macOS from MACOSX_DEPLOYMENT_TARGET (default 13.0 for arm64)
echo "xscape==$XSCAPE_VERSION" | MACOSX_DEPLOYMENT_TARGET=$MACOSX_DEPLOYMENT_TARGET "$UV" pip compile - --find-links "$DIST" --generate-hashes \
  --python-version "$PYTHON_VERSION" --python-platform aarch64-apple-darwin \
  -o "$DIST/xscape-$XSCAPE_VERSION-$PYTAG.lock.txt" -q
ls -la "$DIST"
