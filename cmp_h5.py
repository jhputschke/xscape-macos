#!/usr/bin/env python
"""cmp_h5.py A.h5 B.h5 : compare every dataset bit for bit (and list differing attributes)."""
import sys
import h5py, numpy as np
try:
    import hdf5plugin  # noqa: F401  (Blosc-zstd)
except ImportError:
    pass

a_path, b_path = sys.argv[1], sys.argv[2]
bad = 0; nds = 0; attr_diff = []

def dsets(f):
    out = {}
    f.visititems(lambda n, o: out.__setitem__(n, o) if isinstance(o, h5py.Dataset) else None)
    return out

def attrs(f):
    out = {}
    def v(n, o):
        for k, val in o.attrs.items():
            out[(n, k)] = val
    for k, val in f.attrs.items():
        out[("/", k)] = val
    f.visititems(v)
    return out

with h5py.File(a_path, "r") as A, h5py.File(b_path, "r") as B:
    da, db = dsets(A), dsets(B)
    for n in sorted(set(da) | set(db)):
        if n not in da or n not in db:
            print(f"  only in {'A' if n in da else 'B'}: {n}"); bad += 1; continue
        x, y = da[n][()], db[n][()]
        nds += 1
        if x.dtype != y.dtype or x.shape != y.shape:
            print(f"  DIFF {n}: {x.dtype}{x.shape} vs {y.dtype}{y.shape}"); bad += 1; continue
        if x.dtype.kind in "fc":
            same = np.array_equal(x.view(np.uint8) if x.ndim else np.atleast_1d(x).view(np.uint8),
                                  y.view(np.uint8) if y.ndim else np.atleast_1d(y).view(np.uint8))
        else:
            same = np.array_equal(x, y)
        if not same:
            bad += 1
            msg = ""
            if x.dtype.kind in "fiu":
                d = np.abs(x.astype(float) - y.astype(float)); msg = f" max|d|={d.max():.3g} n={int((d>0).sum())}"
            print(f"  DIFF {n}{msg}")
    aa, ab = attrs(A), attrs(B)
    for k in sorted(set(aa) | set(ab), key=str):
        va, vb = aa.get(k, "<none>"), ab.get(k, "<none>")
        try:
            eq = np.array_equal(np.asarray(va), np.asarray(vb))
        except Exception:
            eq = str(va) == str(vb)
        if not eq:
            attr_diff.append(k)
print(f"{a_path.split('/')[-1]}: {nds} datasets compared, {bad} differ; attrs differing: "
      + (", ".join(f"{p}@{k}" for p, k in attr_diff[:25]) or "none")
      + (" ..." if len(attr_diff) > 25 else ""))
sys.exit(1 if bad else 0)
