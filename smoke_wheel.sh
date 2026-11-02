#!/bin/bash
# smoke_wheel.sh ENV OUT -- the smoke suite of an installed xscape environment (test_wheel.sh
# runs it after the Au+Au comparison; about 15 minutes on an M3 Max).
#
#   ./smoke_wheel.sh ~/.venvs/xscape-0.2.0 /tmp/smoke      # SMOKE_NET=0: skip the OSDF notebook
#
# One line per check in OUT/smoke_results.tsv (name, expected, exit status, seconds, ok/FAIL);
# exit 1 if any check failed. "stop" means the check must refuse with exit status 3 (xscape-run's
# and runJetscape's checks) and run nothing.
#   commands   import pelicanfs and google_crc32c; xscape-selftest; --help of every xscape-*
#              command, with its own name in the usage line
#   copies     xscape-examples and xscape-utils into new directories; neither overwrites
#   checks     runJetscape in an empty directory stops; xscape-run of the unchanged
#              examples/pythonic/oo_workflow.xml (one event) runs
#   test XMLs  one event of each X-SCAPE test XML in share/xscape/config with xscape-run: the
#              ones in RUNS run, every other one stops with its reason
#   examples   one event of each example script that runs X-SCAPE, from the xscape-examples copy,
#              including the multi_hard ones (Au+Au with extras, Ne+Ne 5.36 TeV with a trigger,
#              O+O 5.36 TeV minimum bias through run_jobs.sh, watched by xscape-jobmon, then
#              analysis/bulk/bulk_obs.py on it)
#   notebooks  pythonic/oo_workflow.ipynb and (SMOKE_NET=1, the default) oo_analysis.ipynb,
#              which streams from the OSDF
set -uo pipefail
ENV=$(cd "${1:?ENV (the environment)}" && pwd)
OUT=${2:?OUT}
rm -rf "$OUT"; mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
unset XSCAPE JETSCAPE_BUILD XSCAPE_DATA_DIR HYDROPROGRAMPATH LBT_TABLES_PATH MUSIC_METALLIB \
      MUSIC_EOS_TABLE PYTHIA8DATA DYLD_LIBRARY_PATH PYTHONPATH CONDA_PREFIX CONDA_DEFAULT_ENV
export PATH=$ENV/bin:/usr/bin:/bin:/usr/sbin:/sbin MPLBACKEND=Agg
. "$ENV/bin/activate"
TREE=$(python -c 'import xscape; print(xscape.TREE)')
R=$OUT/smoke_results.tsv
printf 'check\texpected\texit\tseconds\tresult\n' > "$R"
FAILED=0

# check NAME EXPECT DIR CMD...: run CMD in DIR (log OUT/logs/NAME.log, 20 min at most);
# EXPECT an exit status (0: success), or stop (exit 3)
mkdir -p "$OUT/logs"
check() {
  local name=$1 expect=$2 dir=$3; shift 3
  local t0=$SECONDS rc
  (cd "$dir" && perl -e 'alarm 1200; exec @ARGV' "$@") > "$OUT/logs/$name.log" 2>&1
  rc=$?
  local want=$expect; [ "$expect" = stop ] && want=3
  local res=ok; [ "$rc" = "$want" ] || { res=FAIL; FAILED=1; }
  printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$expect" "$rc" "$((SECONDS - t0))" "$res" | tee -a "$R"
}
# grep_log NAME PATTERN: the log of check NAME has PATTERN (else the check fails)
grep_log() {
  if ! grep -qE "$2" "$OUT/logs/$1.log"; then
    printf '%s\t%s\t-\t-\tFAIL\n' "$1: log lacks /$2/" "-" | tee -a "$R"; FAILED=1
  fi
}

echo "== commands"
check imports 0 "$OUT" python -c 'import pelicanfs, google_crc32c, fsspec; fsspec.filesystem("osdf")'
check selftest 0 "$OUT" xscape-selftest
for c in runJetscape xscape-run xscape-fetch-data xscape-examples xscape-utils xscape-osdf \
         xscape-upload-follow xscape-jobmon xscape-prodwizard xscape-h5-inspect \
         xscape-check-deposition xscape-gcs; do
  case $c in
    runJetscape) check "help_$c" 0 "$OUT" bash -c "$c --help; true" ;;   # X-SCAPE's own --help
    xscape-run) check "help_$c" 0 "$OUT" bash -c "$c -h" ;;
    xscape-gcs) check "help_$c" 0 "$OUT" env JS_GCS_NO_ENV=1 bash -c "$c --help" ;;   # (else it makes its environment in ~/.cache/js_gcs)
    *) check "help_$c" 0 "$OUT" bash -c "$c --help"; grep_log "help_$c" "usage: $c" ;;
  esac
done

echo "== copies"
check examples 0 "$OUT" xscape-examples "$OUT/ex"
check utils 0 "$OUT" xscape-utils "$OUT/utils"
check utils_again 1 "$OUT" xscape-utils "$OUT/utils"         # never overwrites
[ -f "$OUT/utils/jobmon.py" ] && [ -f "$OUT/utils/remote_transfer/js_osdf.py" ] \
  || { printf 'utils copy: files\t-\t-\t-\tFAIL\n' | tee -a "$R"; FAILED=1; }
EX=$OUT/ex

echo "== checks"
mkdir -p "$OUT/empty"
check runjetscape_unprepared stop "$OUT/empty" runJetscape "$EX/pythonic/oo_workflow.xml"
sed -E 's#<nEvents>[^<]*</nEvents>#<nEvents> 1 </nEvents>#' "$EX/pythonic/oo_workflow.xml" \
  > "$OUT/oo_workflow_1.xml"
check xscape_run_oo_workflow 0 "$OUT" xscape-run -w "$OUT/runs/oo_workflow" -u "$OUT/oo_workflow_1.xml"
grep_log xscape_run_oo_workflow "iSS"

echo "== X-SCAPE test XMLs ($TREE/config)"
# the test XMLs this wheel runs; every other one stops at a check (module, input, tag,
# LHAPDF6, automatic module setup off)
RUNS=" brick_hybrid_hadronization DIS MUSIC OO_ISR_MatterLBT_iColored photoproduction twostagehydro jetscape_user "
mkdir -p "$OUT/xml"
for x in $(cd "$TREE/config" && find . -name '*.xml' ! -name jetscape_main.xml ! -name 'HH_*' | sed 's#^\./##' | sort); do
  n=$(echo "$x" | tr / _ | sed 's/\.xml$//')
  short=${n#jetscape_user_}
  sed -E 's#<nEvents>[^<]*</nEvents>#<nEvents>1</nEvents>#' "$TREE/config/$x" > "$OUT/xml/$n.xml"
  case "$RUNS" in *" $short "*) e=0 ;; *) e=stop ;; esac
  check "xml_$n" $e "$OUT" xscape-run -w "$OUT/runs/$n" -u "$OUT/xml/$n.xml"
done

echo "== examples (from $EX)"
O=$OUT/py
check oo_workflow_py 0 "$EX/pythonic" python oo_workflow.py --events 1 --outdir "$O/oo_workflow"
check run_prod 0 "$EX/prod_AuAu_0_10" python run_prod.py --events 1 --outdir "$O/run_prod" --seed-registry none
check run_prod_vacuum 0 "$EX/prod_AuAu_0_10_jet" python run_prod_vacuum.py --events 1 --outdir "$O/run_prod_vacuum" --seed-registry none
check run_prod_oo_isr 0 "$EX/prod_OO_isr" python run_prod_oo_isr.py --events 1 --outdir "$O/run_prod_oo_isr" --seed-registry none
check per_event_loop 0 "$EX" python per_event_loop.py --events 1 --outdir "$O/per_event_loop"
check bulk_h5_writer 0 "$EX" python python_bulk_h5_writer.py --events 1 --out "$O/bulk_h5/hydro_evo.h5" --no-plot
check inspect_bulk_info 0 "$EX" python inspect_bulk_info.py --events 1 --outdir "$O/inspect_bulk" --no-show
check bulk_root_writer 0 "$O" python "$EX/python_bulk_root_writer.py"
check pymod_from_xml 0 "$EX/python_modules" python run_from_xml.py --outdir "$O/pymod_xml"
check pymod_by_hand 0 "$EX/python_modules" python run_by_hand.py --outdir "$O/pymod_hand"
check pymod_pythonic 0 "$EX/python_modules" python run_by_hand_pythonic.py --style new --outdir "$O/pymod_py"
check wake_hadrons_help 0 "$EX/analysis" python wake_hadrons.py --help
# multi_hard: the event's other hard scatterings
J=$EX/prod_AuAu_0_10_jet
check auau_extra_hard 0 "$J" python run_prod_jet.py --events 1 --seed 1 --extra-hard --hadrons-only \
  --outdir "$O/auau_extra" --seed-registry none
grep_log auau_extra_hard "extra scattering"
check nene_5360_extra_hard 0 "$J" python run_prod_jet.py --events 1 --seed 1 \
  --user-xml ../config/NeNe_5360_jet.xml --grid ../config/grid_oo.yaml --extra-hard --hadrons-only \
  --outdir "$O/nene" --out NeNe_5360_seed0001.h5 --seed-registry none
check oo_5360_mb_run_jobs 0 "$J" env TAG_PREFIX=OO_5360_seed ./run_jobs.sh --campaign smoke 1 1 1 "$O/oo_mb" \
  --user-xml ../config/OO_5360_jet.xml --grid ../config/grid_oo.yaml --hard none --extra-hard --hadrons-only
check jobmon 0 "$OUT" xscape-jobmon "$O/oo_mb" --njobs 1
check h5_inspect 0 "$OUT" bash -c "xscape-h5-inspect \$(ls '$O'/oo_mb/*_hadrons_bulk_jet.h5 | head -1)"
check bulk_obs 0 "$EX/analysis/bulk" python bulk_obs.py "$O/oo_mb"
check check_deposition 0 "$OUT" xscape-check-deposition "$O/auau_extra"

echo "== notebooks"
check nb_oo_workflow 0 "$EX/pythonic" jupyter nbconvert --to notebook --execute oo_workflow.ipynb \
  --output-dir "$O/nb" --ExecutePreprocessor.timeout=1200
if [ "${SMOKE_NET:-1}" = 1 ]; then
  check nb_oo_analysis 0 "$EX/pythonic" jupyter nbconvert --to notebook --execute oo_analysis.ipynb \
    --output-dir "$O/nb" --ExecutePreprocessor.timeout=1200
fi

echo
echo "== $(grep -c $'\tok$' "$R") ok, $(grep -c $'\tFAIL$' "$R") failed ($R)"
exit $FAILED
