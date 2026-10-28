# Building the xscape wheel

The recipe for the `xscape` wheel: X-SCAPE with MUSIC on the Metal GPU, for Apple Silicon
Macs on macOS 26 or later, Python 3.13, installed with uv. Design and decisions: the
"Packaging X-SCAPE for Metal Macs" doc (2026-10-28).

| file | what |
|---|---|
| `pins.env` | the X-SCAPE, js-contrib, music4gpu, iSS, 3dMCGlauber and LBT-tables commits, the version, Python and macOS |
| `build_wheel.sh` | CMake build, `cmake --install --component xscape_runtime`, staging (Pythia data, examples, `BUILD_INFO.txt`), `wheel pack`, `delocate-wheel`, the pyjetscape wheel, a hashed lock |
| `release.sh` | step 3: fresh clones at the pins (their `get_*.sh` fetch the EOS, iSS and LHAPDF data), `build_wheel.sh`, and with `--upload` a GitHub pre-release with the wheels and a lock that names them by URL |
| `src/xscape/` | the `xscape` package: paths, and the commands `runJetscape`, `xscape-run`, `xscape-fetch-data` (`lbt.py`: the LBT tables, also used by `release.sh`) |
| `test_wheel.sh` | install from the lock into a fresh uv environment, check no Homebrew library loads, run the Au+Au jet production and `hadronize.py`, compare bit for bit with a checkout's run |
| `cmp_h5.py` | every HDF5 dataset bit for bit |

## Build (local)

```bash
python -m venv tools && tools/bin/pip install uv delocate wheel
XSCAPE_SRC=~/JetScape/X-SCAPE PYTHON_BIN=<python 3.13 with pybind11 >= 3> TOOLS_BIN=$PWD/tools/bin ./build_wheel.sh
# -> dist/xscape-<ver>-cp313-cp313-macosx_26_0_arm64.whl, dist/pyjetscape-<ver>-py3-none-any.whl,
#    dist/xscape-<ver>-cp313.lock.txt
```

`XSCAPE_SRC` needs X-SCAPE, js-contrib and music4gpu at their `mac_wheel` branches (or
later commits that contain them) and the external packages fetched. The build tree is
`build/cmake`; the checkout's own build trees and its in-tree PyJetscape core are not touched.

## Release

```bash
PYTHON_BIN=<python 3.13 with pybind11 >= 3> TOOLS_BIN=$PWD/tools/bin ./release.sh --upload
```

## Use (from a release)

```bash
uv venv ~/.venvs/xscape --python 3.13 && source ~/.venvs/xscape/bin/activate
curl -LO https://github.com/jhputschke/xscape-macos/releases/download/v<ver>/xscape-<ver>-cp313.lock.txt
uv pip sync xscape-<ver>-cp313.lock.txt     # the lock names the wheels by URL, hash-checked
xscape-fetch-data lbt                 # LBT tables into ~/Library/Caches/xscape, linked in
xscape-examples ~/xscape/examples     # the production scripts and notebooks, editable
cd ~/xscape/examples/prod_AuAu_0_10_jet
python run_prod_jet.py --events 1 --seed 1 --outdir ~/xscape/runs/out
```
