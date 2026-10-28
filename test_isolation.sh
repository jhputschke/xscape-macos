#!/bin/bash
# test_isolation.sh ENV_HOME -- run an installed environment with everything else unreadable.
#
# ENV_HOME: a home folder as the README builds it (~/.venvs/xscape-VER from `uv venv
# --managed-python`, ~/xscape/examples, the LBT tables in ~/Library/Caches/xscape).  macOS's
# sandbox denies reading and writing /opt/homebrew (Homebrew, and conda installed by it),
# /usr/local, ~/miniconda3, ~/anaconda3, uv's own caches and the folders in $BLOCK (default:
# ~/JetScape, the checkouts); then the first O+O event, the Au+Au production, hadronize.py
# and xscape-run, with every library loaded listed.  Pass: all four exit 0 and no library
# comes from outside macOS and ENV_HOME.
set -euo pipefail
H=$(cd "${1:?ENV_HOME}" && pwd)
BLOCK=${BLOCK:-$HOME/JetScape}
PROFILE=$(mktemp -t xscape_isolation).sb
deny=""
for d in /opt/homebrew /usr/local "$HOME/miniconda3" "$HOME/anaconda3" "$HOME/.local/share/uv" \
         "$HOME/.cache/uv" $BLOCK; do deny="$deny (subpath \"$d\")"; done
printf '(version 1)\n(allow default)\n(deny file-read-data file-write*%s)\n(allow file-read-data file-write* (subpath "%s") (subpath "%s"))\n' \
  "$deny" "$H" "$(dirname "$PROFILE")" > "$PROFILE"
cd "$H"
sandbox-exec -f "$PROFILE" /bin/bash -s "$H" <<'INNER'
set -uo pipefail
export HOME=$1; cd ~
unset XSCAPE JETSCAPE_BUILD XSCAPE_DATA_DIR HYDROPROGRAMPATH LBT_TABLES_PATH MUSIC_METALLIB \
      PYTHIA8DATA DYLD_LIBRARY_PATH PYTHONPATH CONDA_PREFIX
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
source "$(ls -d ~/.venvs/xscape-* | tail -1)/bin/activate"
cat /opt/homebrew/bin/brew > /dev/null 2>&1 && echo "NOT ISOLATED: /opt/homebrew readable" || echo "isolated: /opt/homebrew unreadable"
O=~/xscape/isolation; rm -rf "$O"; mkdir "$O"
run() { name=$1; shift; DYLD_PRINT_LIBRARIES=1 "$@" > "$O/$name.log" 2>&1; echo "$name exit $?"; }
cd ~/xscape/examples/pythonic && run oo python oo_workflow.py --events 1 --outdir "$O/oo"
cd ~/xscape/examples/prod_AuAu_0_10_jet
run auau python run_prod_jet.py --events 2 --seed 1 --reuse 2 --write-particlize both --outdir "$O/out" --seed-registry none
run had python hadronize.py "$O/out/AuAu_0_10_jet_seed0001_particlize.h5" --seed-uuid 11111111-2222-3333-4444-555555555555 --oversample 3 --n-frag 2 --out-dir "$O/had"
run pp xscape-run -w "$O/pp" -u "$(python -c 'import xscape; print(xscape.TREE)')/config/jetscape_user.xml"
echo "== libraries from outside macOS and $HOME (should be none):"
cat "$O"/*.log | grep "dyld\[" | grep -oE "/[^ ]+\.(dylib|so)" | grep -vE "^/usr/lib/|^/System/" | grep -v "^$HOME/" | sort -u
echo "(end)"
INNER
rm -f "$PROFILE"
