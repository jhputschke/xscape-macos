#!/bin/sh
# install.sh -- X-SCAPE on a Mac in one command: uv, the environment from a release's lock file,
# the LBT tables and the self-test (steps 1-4 of the README, "Get started").
#
#   curl -LsSf https://raw.githubusercontent.com/jhputschke/xscape-macos/main/install.sh | sh
#   curl -LsSf https://raw.githubusercontent.com/jhputschke/xscape-macos/main/install.sh | sh -s -- --version 0.2.0
#
# Options (after `sh -s --`):
#   --version VER    the release to install (default: the latest release on GitHub)
#   --venv DIR       the environment (default: ~/.venvs/xscape-VER)
#   --examples DIR   also copy the examples to DIR (xscape-examples; never overwrites)
#   --force          delete an existing environment DIR first (default: reuse it; the lock
#                    makes it exactly the release again)
#   --no-lbt         skip the LBT tables (xscape-fetch-data lbt, 240 MB download)
#   --no-selftest    skip xscape-selftest
#
# Writes only: uv in ~/.local/bin (if no suitable uv is found; Astral's installer also adds
# ~/.local/bin to the shell's PATH), the environment, uv's cache (~/.cache/uv, its Python in
# ~/.local/share/uv) and the LBT tables in ~/Library/Caches/xscape ($XSCAPE_CACHE).
# POSIX sh: it runs with macOS's /bin/sh, piped from curl.

set -eu

REPO=jhputschke/xscape-macos
PYVER=3.13
PYTAG=cp313

VER=""; VENV=""; EXAMPLES=""; FORCE=0; LBT=1; SELFTEST=1

say()  { printf '\033[1minstall.sh:\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31minstall.sh: %s\033[0m\n' "$*" >&2; exit 1; }
usage() { cat <<EOF
install.sh -- X-SCAPE on a Mac: uv, the environment from a release's lock file, the LBT tables
and the self-test.  Piped from curl, options go after 'sh -s --':
  curl -LsSf https://raw.githubusercontent.com/$REPO/main/install.sh | sh -s -- --version 0.2.0

  --version VER    the release to install (default: the latest on github.com/$REPO/releases)
  --venv DIR       the environment (default: ~/.venvs/xscape-VER)
  --examples DIR   also copy the examples to DIR (never overwrites)
  --force          delete an existing environment DIR first (default: reuse it)
  --no-lbt         skip the LBT tables (240 MB download)
  --no-selftest    skip xscape-selftest
EOF
}

while [ $# -gt 0 ]; do
  case $1 in
    --version)     [ $# -ge 2 ] || fail "--version needs a value"; VER=${2#v}; shift 2 ;;
    --version=*)   VER=${1#--version=}; VER=${VER#v}; shift ;;
    --venv)        [ $# -ge 2 ] || fail "--venv needs a value"; VENV=$2; shift 2 ;;
    --venv=*)      VENV=${1#--venv=}; shift ;;
    --examples)    [ $# -ge 2 ] || fail "--examples needs a value"; EXAMPLES=$2; shift 2 ;;
    --examples=*)  EXAMPLES=${1#--examples=}; shift ;;
    --force)       FORCE=1; shift ;;
    --no-lbt)      LBT=0; shift ;;
    --no-selftest) SELFTEST=0; shift ;;
    -h|--help)     usage; exit 0 ;;
    *)             fail "unknown option: $1 (--help lists them)" ;;
  esac
done

# ---- 1. this Mac --------------------------------------------------------------------------
[ "$(uname -s)" = Darwin ] || fail "this is for macOS; on Linux use the production container (js-contrib utils/README_Container_Usage.md)"
if [ "$(uname -m)" != arm64 ]; then
  if [ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" = 1 ]; then
    fail "this shell runs under Rosetta (x86_64): run it in a native Terminal (arm64)"
  fi
  fail "Intel Macs are not supported: X-SCAPE on a Mac needs Apple Silicon (M1 or later)"
fi
OSVER=$(sw_vers -productVersion)
[ "${OSVER%%.*}" -ge 26 ] 2>/dev/null || fail "macOS $OSVER: macOS 26 or later is needed (Apple menu > About This Mac; update macOS first)"
FREE_GB=$(df -Pk "$HOME" | awk 'NR==2 {print int($4/1048576)}')
[ "$FREE_GB" -ge 3 ] || fail "only $FREE_GB GB free in $HOME: about 3 GB are needed"
command -v curl > /dev/null || fail "curl not found"
for v in XSCAPE JETSCAPE_BUILD PYTHONPATH DYLD_LIBRARY_PATH; do
  eval "val=\${$v:-}"
  [ -z "$val" ] || say "note: $v is set ($val); it is for a source build and would point the environment elsewhere -- unset it (e.g. in ~/.zshrc)"
done
unset XSCAPE JETSCAPE_BUILD PYTHONPATH DYLD_LIBRARY_PATH VIRTUAL_ENV CONDA_PREFIX

# ---- 2. the release ------------------------------------------------------------------------
if [ -z "$VER" ]; then
  LOC=$(curl -sSI "https://github.com/$REPO/releases/latest" | tr -d '\r' | awk 'tolower($1)=="location:" {print $2}')
  VER=${LOC##*/tag/v}
  case $VER in ""|*/*) fail "could not find the latest release on github.com/$REPO/releases (no internet?); give one: --version VER" ;; esac
fi
LOCK=xscape-$VER-$PYTAG.lock.txt
VENV=${VENV:-$HOME/.venvs/xscape-$VER}
case $VENV in "~"/*) VENV=$HOME/${VENV#"~/"} ;; esac
case $EXAMPLES in "~"/*) EXAMPLES=$HOME/${EXAMPLES#"~/"} ;; esac
say "xscape $VER into $VENV (macOS $OSVER, $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo arm64))"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/xscape-install.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
curl -fsSL -o "$TMP/$LOCK" "https://github.com/$REPO/releases/download/v$VER/$LOCK" \
  || fail "no lock file $LOCK in release v$VER: the versions are on https://github.com/$REPO/releases"

# ---- 3. uv ---------------------------------------------------------------------------------
UV=""
if command -v uv > /dev/null 2>&1 && uv venv --help 2>/dev/null | grep -q -- --managed-python; then
  UV=$(command -v uv)
else
  BIN=${XDG_BIN_HOME:-$HOME/.local/bin}
  if [ -x "$BIN/uv" ] && "$BIN/uv" venv --help 2>/dev/null | grep -q -- --managed-python; then
    UV=$BIN/uv
  else
    if command -v uv > /dev/null 2>&1; then
      say "the uv found ($(command -v uv), $(uv --version 2>/dev/null)) is too old (no --managed-python): installing Astral's uv"
    else
      say "installing uv (Astral's installer, into $BIN)"
    fi
    curl -LsSf https://astral.sh/uv/install.sh | sh || fail "the uv installation failed"
    UV=$BIN/uv
    [ -x "$UV" ] || fail "uv not found in $BIN after its installation"
  fi
fi
say "uv: $UV ($("$UV" --version))"

# ---- 4. the environment --------------------------------------------------------------------
if [ -e "$VENV" ] && [ "$FORCE" = 1 ]; then
  say "--force: removing $VENV"
  rm -rf "$VENV"
fi
if [ -x "$VENV/bin/python" ]; then
  say "reusing $VENV (uv pip sync makes it exactly release $VER; --force builds it new)"
elif [ -e "$VENV" ]; then
  fail "$VENV exists but is no environment: remove it, give another --venv DIR, or --force"
else
  "$UV" venv --managed-python --python "$PYVER" "$VENV" || fail "uv venv failed"
fi
"$UV" pip sync --python "$VENV/bin/python" "$TMP/$LOCK" || fail "uv pip sync failed (troubleshooting: https://github.com/$REPO#troubleshooting)"
cp "$TMP/$LOCK" "$VENV/$LOCK"     # the record of what this environment is

# what `activate` does, without sourcing it (it is not `set -u` safe in every sh)
VIRTUAL_ENV=$VENV; PATH=$VENV/bin:$PATH; export VIRTUAL_ENV PATH

# ---- 5. LBT tables, self-test, examples ----------------------------------------------------
if [ "$LBT" = 1 ]; then
  say "the LBT tables (240 MB download, 1.1 GB in ${XSCAPE_CACHE:-~/Library/Caches/xscape}; reused when already there)"
  xscape-fetch-data lbt || fail "xscape-fetch-data lbt failed; run it again in the activated environment"
fi
if [ "$SELFTEST" = 1 ]; then
  say "xscape-selftest (the first run takes a little longer: matplotlib builds its font cache)"
  if [ "$LBT" = 1 ]; then
    xscape-selftest || fail "xscape-selftest failed (see the FAIL line above)"
  else
    xscape-selftest || say "xscape-selftest failed -- without the LBT tables (--no-lbt) that is expected"
  fi
fi
if [ -n "$EXAMPLES" ]; then
  xscape-examples "$EXAMPLES" || fail "xscape-examples $EXAMPLES failed"
fi

# ---- done ----------------------------------------------------------------------------------
EX=${EXAMPLES:-~/xscape/examples}
cat <<EOF

$(printf '\033[1;32m')xscape $VER is installed in $VENV$(printf '\033[0m')

In every new Terminal window, activate it:

    source $VENV/bin/activate

Your first event (one O+O event on the GPU, under a minute):

EOF
[ -n "$EXAMPLES" ] || echo "    xscape-examples ~/xscape/examples"
cat <<EOF
    cd $EX/pythonic
    python oo_workflow.py --events 1 --outdir ~/xscape/out_oo

The guide: https://github.com/$REPO#x-scape-on-a-mac
EOF
case ":$PATH:" in
  *":$(dirname "$UV"):"*) ;;
  *) echo; echo "uv itself is found in new Terminal windows (or now: source ~/.local/bin/env)." ;;
esac
