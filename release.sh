#!/bin/bash
# release.sh [--upload] -- rollout step 3: the xscape release from fresh clones.
#
#   PYTHON_BIN=<python 3.13 with pybind11 >= 3> TOOLS_BIN=<venv>/bin ./release.sh [--upload]
#
# 1. refuses a modified packaging repository (this one)
# 2. X-SCAPE at XSCAPE_REF into build/src/X-SCAPE, its external packages with their own
#    get_*.sh (which also download the EOS, iSS and LHAPDF data), then js-contrib and
#    music4gpu moved to JS_CONTRIB_REF / MUSIC4GPU_REF; iSS and 3dMCGlauber checked against
#    ISS_REF / GLAUBER_REF; the LBT tables at LBT_TABLES_COMMIT (for their checksums)
# 3. build_wheel.sh on that tree -> dist/
# 4. --upload: GitHub release v$XSCAPE_VERSION of this repository (a pre-release for dev/rc
#    versions) with the two wheels,
#    then a lock that names them by their release URLs (hash-checked), uploaded too
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/pins.env"
UPLOAD=0; [ "${1:-}" = "--upload" ] && UPLOAD=1
TOOLS_BIN=${TOOLS_BIN:-}
UV=${TOOLS_BIN:+$TOOLS_BIN/}uv
PYTHON_BIN=${PYTHON_BIN:-python3}
SRC=$HERE/build/src
X=$SRC/X-SCAPE
EP=$X/external_packages
REPO=${GITHUB_REPO:-jhputschke/xscape-macos}
TAG=v$XSCAPE_VERSION
PYTAG=cp${PYTHON_VERSION/./}

say() { printf '\n== %s\n' "$*"; }
at() {  # at DIR URL REF: DIR becomes a shallow checkout of REF
  rm -rf "$1"; git init -q "$1"
  git -C "$1" fetch -q --depth 1 "$2" "$3"; git -C "$1" checkout -q FETCH_HEAD
}
move_to() {  # move_to DIR REF: an existing clone to REF (fetched if needed)
  git -C "$1" cat-file -e "$2^{commit}" 2>/dev/null || git -C "$1" fetch -q origin "$2"
  git -C "$1" checkout -q "$2"
}

if [ -n "$(git -C "$HERE" status --porcelain)" ] && [ -z "${ALLOW_DIRTY:-}" ]; then
  echo "the packaging repository has changes: commit them first (ALLOW_DIRTY=1 to test)" >&2
  exit 1
fi

if [ -n "${REUSE_SRC:-}" ] && [ -d "$X" ]; then
  say "sources from an earlier run ($SRC; REUSE_SRC), checked against the pins"
else
  say "fresh sources at the pins ($SRC)"
  mkdir -p "$SRC"
  at "$X" "$XSCAPE_REPO" "$XSCAPE_REF"
  (
    cd "$EP"
    bash get_iSS.sh > "$SRC/get_iSS.log" 2>&1
    bash get_3dglauber.sh > "$SRC/get_3dglauber.log" 2>&1
    bash get_music4gpu.sh > "$SRC/get_music4gpu.log" 2>&1
    bash get_js_contrib.sh > "$SRC/get_js_contrib.log" 2>&1
  )
fi
move_to "$EP/js-contrib" "$JS_CONTRIB_REF"
move_to "$EP/music4gpu" "$MUSIC4GPU_REF"
for pair in ". $XSCAPE_REF" "external_packages/js-contrib $JS_CONTRIB_REF" \
            "external_packages/music4gpu $MUSIC4GPU_REF" "external_packages/iSS $ISS_REF" \
            "external_packages/3dMCGlauber $GLAUBER_REF"; do
  set -- $pair
  have=$(git -C "$X/$1" rev-parse HEAD)
  [ "$have" = "$2" ] || { echo "$1 is at $have, pins.env says $2" >&2; exit 1; }
  [ -z "$(git -C "$X/$1" status --porcelain --untracked-files=no)" ] \
    || { echo "$1 has local changes" >&2; exit 1; }
done
LBT=$SRC/LBT-tables
[ -d "$LBT" ] || "$PYTHON_BIN" "$HERE/src/xscape/lbt.py" "$LBT" "$LBT_TABLES_COMMIT"
for d in . external_packages/js-contrib external_packages/music4gpu external_packages/iSS \
         external_packages/3dMCGlauber; do
  echo "$d $(git -C "$X/$d" rev-parse HEAD)"
done

say "build (a clean build tree)"
rm -rf "$HERE/build/cmake"
XSCAPE_SRC=$X LBT_TABLES_DIR=$LBT "$HERE/build_wheel.sh"

[ "$UPLOAD" = 1 ] || exit 0

say "GitHub release $REPO $TAG"
XWHL=$(cd "$HERE/dist" && ls xscape-*.whl); PWHL=$(cd "$HERE/dist" && ls pyjetscape-*.whl)
# a pre-release only for dev/rc/alpha/beta versions (PEP 440), else the latest release
case "$XSCAPE_VERSION" in
  *dev*|*rc*|*a[0-9]*|*b[0-9]*) PRE=--prerelease; TITLE="xscape $XSCAPE_VERSION (test)";
    FIRST="Test build for Apple Silicon Macs, macOS 26 or later, Python $PYTHON_VERSION; not for production yet." ;;
  *) PRE=--latest; TITLE="xscape $XSCAPE_VERSION";
    FIRST="X-SCAPE with MUSIC on the Metal GPU for Apple Silicon Macs: macOS 26 or later, Python $PYTHON_VERSION, installed with uv." ;;
esac
XV=$(sed -n 's/.*XscapeVersion = "\([^"]*\)".*/\1/p' "$X/src/framework/Version.h")
JV=$(sed -n 's/.*JetScapeVersion = "\([^"]*\)".*/\1/p' "$X/src/framework/Version.h")
{
  echo "$FIRST"
  echo
  echo "Step-by-step guide: https://github.com/jhputschke/xscape-macos#readme"
  echo
  echo "Components: X-SCAPE $XV (JETSCAPE $JV), branch contrib at ${XSCAPE_REF:0:8}; pyjetscape $PYJETSCAPE_VERSION (js-contrib ${JS_CONTRIB_REF:0:7}); MUSIC4GPU ${MUSIC4GPU_REF:0:7}; iSS ${ISS_REF:0:7}; 3dMCGlauber ${GLAUBER_REF:0:7}; LBT tables ${LBT_TABLES_COMMIT:0:7}."
  echo
  echo '```bash'
  echo "curl -LO https://github.com/$REPO/releases/download/$TAG/xscape-$XSCAPE_VERSION-$PYTAG.lock.txt"
  echo "uv venv ~/.venvs/xscape --python $PYTHON_VERSION && source ~/.venvs/xscape/bin/activate"
  echo "uv pip sync xscape-$XSCAPE_VERSION-$PYTAG.lock.txt"
  echo "xscape-fetch-data lbt && xscape-examples ~/xscape/examples"
  echo '```'
  echo
  echo "Built from:"
  echo '```'
  sed -n '2,$p' "$HERE/build/stage/xscape/share/xscape/BUILD_INFO.txt"
  echo '```'
} > "$HERE/build/release_notes.md"
gh release create "$TAG" --repo "$REPO" $PRE --title "$TITLE" \
  --notes-file "$HERE/build/release_notes.md" "$HERE/dist/$XWHL" "$HERE/dist/$PWHL"
BASE=https://github.com/$REPO/releases/download/$TAG
LOCK=$HERE/dist/release/xscape-$XSCAPE_VERSION-$PYTAG.lock.txt
mkdir -p "$HERE/dist/release"
printf 'xscape @ %s/%s\npyjetscape @ %s/%s\n' "$BASE" "$XWHL" "$BASE" "$PWHL" \
  | MACOSX_DEPLOYMENT_TARGET=$MACOSX_DEPLOYMENT_TARGET "$UV" pip compile - --generate-hashes \
      --python-version "$PYTHON_VERSION" --python-platform aarch64-apple-darwin -o "$LOCK" -q
gh release upload "$TAG" --repo "$REPO" "$LOCK"
echo "released: https://github.com/$REPO/releases/tag/$TAG"
