#!/bin/bash
# test_wheel.sh OUT_DIR [REF_DIR] -- rollout step 2: install the built wheels into a fresh uv
# environment (uv's own Python, no conda, no X-SCAPE variables) and run from an empty
# directory: no Homebrew library may load, the Au+Au jet production (2 events, seed 1) and
# hadronize.py with a fixed seed UUID; with REF_DIR (the same run from a checkout:
# REF_DIR/out, REF_DIR/had), compare every dataset bit for bit.
#
#   TOOLS_BIN=<venv>/bin LBT_FROM=<checkout>/external_packages/LBT-tables ./test_wheel.sh /tmp/t ref
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/pins.env"
OUT=${1:?OUT_DIR}; REF=${2:-}
TOOLS_BIN=${TOOLS_BIN:-}
UV=${TOOLS_BIN:+$TOOLS_BIN/}uv
DIST=$HERE/dist
LOCK=$(ls "$DIST"/xscape-*.lock.txt)
U=11111111-2222-3333-4444-555555555555

# no X-SCAPE settings, no conda, no checkout on the path
unset XSCAPE JETSCAPE_BUILD XSCAPE_DATA_DIR HYDROPROGRAMPATH LBT_TABLES_PATH MUSIC_METALLIB \
      MUSIC_EOS_TABLE PYTHIA8DATA DYLD_LIBRARY_PATH PYTHONPATH CONDA_PREFIX CONDA_DEFAULT_ENV
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
export UV_PYTHON_PREFERENCE=only-managed

rm -rf "$OUT"; mkdir -p "$OUT"
"$UV" venv -q "$OUT/venv" --python "$PYTHON_VERSION"
# the lock names the local wheels by file name: let uv find them in dist/
"$UV" pip sync -q --python "$OUT/venv/bin/python" --find-links "$DIST" "$LOCK"
. "$OUT/venv/bin/activate"
python -V; python -c 'import sys; print(sys.executable)'

echo "== libraries loaded from outside the wheel and macOS (should be none)"
DYLD_PRINT_LIBRARIES=1 python -c 'import jetscape' 2>&1 | grep -E '/opt/homebrew|/usr/local|miniconda|anaconda' || echo "none"
DYLD_PRINT_LIBRARIES=1 runJetscape --help 2>&1 | grep -E '/opt/homebrew|/usr/local|miniconda' || echo "none (runJetscape)"

if [ -n "${LBT_FROM:-}" ]; then xscape-fetch-data lbt --from "$LBT_FROM"; else xscape-fetch-data lbt; fi

mkdir -p "$OUT/run" && cd "$OUT/run"
xscape-examples "$OUT/run/examples"
cd "$OUT/run/examples/prod_AuAu_0_10_jet"
python -c 'import jetscape as js; print("core", js.pyjetscape_core.__file__, js.pyjetscape_core.MUSIC_BACKEND)'
/usr/bin/time -p python run_prod_jet.py --events 2 --seed 1 --reuse 2 --write-particlize both \
  --outdir "$OUT/out" --seed-registry none > "$OUT/run.log" 2>&1
python hadronize.py "$OUT/out/AuAu_0_10_jet_seed0001_particlize.h5" --seed-uuid $U \
  --oversample 3 --n-frag 2 --out-dir "$OUT/had" > "$OUT/had.log" 2>&1
ls "$OUT/out" "$OUT/had"

if [ -n "$REF" ]; then
  echo "== compare with $REF"
  for f in $(ls "$REF/out" | grep '\.h5$'); do python "$HERE/cmp_h5.py" "$REF/out/$f" "$OUT/out/$f" | tail -3 || true; done
  for f in $(ls "$REF/had" | grep '\.h5$'); do python "$HERE/cmp_h5.py" "$REF/had/$f" "$OUT/had/$f" | tail -1 || true; done
fi
