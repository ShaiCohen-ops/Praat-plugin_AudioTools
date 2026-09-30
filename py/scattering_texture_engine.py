#!/usr/bin/env python3
"""
Scattering Texture Generator - Python backend (Praat AudioTools, Hybrid Systems)

    Sound -> wavelet scattering (orders 0, 1, 2) -> target transformation
          -> iterative waveform optimization (texture matching) -> new Sound

Scattering definition
    Filters come from Kymatio's own Morlet filter bank
    (kymatio.scattering1d.filter_bank.scattering_filter_factory) and the forward
    pass follows kymatio.scattering1d.core.scattering1d step for step
    (Fourier-domain filtering, dyadic subsampling by spectral periodization,
    modulus, low-pass phi_J). It is re-implemented here in plain NumPy together
    with its exact adjoint, so the gradient needed for waveform optimization
    is computed analytically: no PyTorch, no autograd, no GPU. `--selftest`
    checks the forward pass against Kymatio's Scattering1D and the gradient
    against finite differences.

    Order 0 note: Kymatio's S0 is x * phi_J, the low-passed WAVEFORM. For audio
    that is essentially zero (no DC) and carries no envelope. This tool therefore
    uses the envelope form |x| * phi_J for order 0, which is what "global energy
    envelope" means musically. Orders 1 and 2 are exactly Kymatio's.

    Order 2 is matched in NORMALIZED form, S2(l1,l2) / S1(l1): the modulation
    depth of each band independently of how loud that band is. Preserving
    temporal modulation therefore does not secretly re-impose the spectrum.

Reconstruction
    Not an inverse transform (scattering is not invertible). L-BFGS minimises
        w0*d(S0) + w1*d(S1) + w2*d(S2/S1)
    with d = mean squared log-domain distance per coefficient family, so no
    family dominates through scale or coefficient count.

v0.2 (speed): first-order filters sharing a subsampling are batched, and every
filter is applied only on its non-negligible frequency bins (|psi| > 1e-10 of
peak). Measured per loss+gradient evaluation: 1.7-2.3x faster than v0.1,
results within 4e-11 (gradient) of v0.1. Progress is logged every 10
iterations with an estimate of time left; a segment stops early if 10
iterations improve the loss by less than 0.1 %.

v0.3 (practicality): the waveform is BUILT from the target instead of being
optimized from noise - band carriers x envelopes whose order-1 level and
order-2 modulation depths are calibrated in 5 analysis-only rounds (see
direct_synthesis). Preview stops there; Standard/High add 15/150 L-BFGS
refinement iterations. Segments run in parallel worker processes and are
joined with equal-power crossfades. Measured on a 17 s file, one core:
Preview 55 s -> 17 s (measured); Standard 55 s (v0.2 Standard was not re-measured on
this file; ~4 min estimated from its per-iteration cost).

v0.3.2 (speed): carriers cached across calibration rounds, batched
modulation IFFTs, scipy.fft in direct synthesis, no repeated analysis in
Preview, single-precision modulation gains. Preview 1.6x faster, output
within 5e-8 of v0.3.1.

Dependencies: numpy, scipy, kymatio. Nothing is downloaded, no model weights.
"""

import sys
import os
import math
import time
import argparse
import traceback

REQUIRED = [("numpy", "numpy"), ("scipy", "scipy"), ("kymatio", "kymatio")]

PRESETS = {
    # name: (w0, w1, w2) or None = user sliders, base ops (always applied),
    #       transformation ops (scaled by Texture Transformation)
    "Custom": (None, [],
               [("time_smooth_S1", 0.6), ("mod_depth", 0.5), ("sparsify_S2", 0.4)]),
    "Spectral Skeleton": ((30, 100, 15), [],
               [("time_smooth_S1", 1.0), ("sparsify_S2", 0.6)]),
    "Temporal Texture": ((30, 35, 100), [("freq_blur_S1", 0.35)],
               [("freq_blur_S1", 0.65), ("spectral_shift", -1.0)]),
    "Modulation Ghost": ((60, 10, 100), [("freq_blur_S1", 1.0), ("dyn_compress_S1", 0.7)],
               [("mod_depth", 1.0)]),
    "Structure Without Identity": ((50, 50, 50), [("freq_blur_S1", 0.5), ("time_smooth_S1", 0.25)],
               [("perturb", 1.0), ("spectral_shift", 0.5)]),
    "Second-Order Reconstruction": ((20, 25, 100), [],
               [("mod_depth", 0.5)]),
    "Radical Texture": ((40, 60, 100), [],
               [("mod_rate_shift", 1.0), ("spectral_shift", -1.0), ("dyn_expand_S1", 1.0),
                ("sparsify_S2", 0.5), ("perturb", 0.6)]),
}

SCALE_SECONDS = {"Fine": 0.046, "Medium": 0.186, "Broad": 0.743}
DETAIL_Q = {"Low": (4, 1), "Medium": (8, 1), "High": (12, 2)}
QUALITY = {  # working-rate cap (Hz), calibration rounds, L-BFGS refinement iterations, max segment log2
    "Preview": (16000, 5, 0, 16),
    "Standard": (22050, 5, 15, 17),
    "High": (48000, 5, 150, 18),
}


# ----------------------------------------------------------------------------
# status / report
# ----------------------------------------------------------------------------
class Report:
    def __init__(self, workdir):
        self.path = os.path.join(workdir, "report.txt")
        self.logpath = os.path.join(workdir, "engine_log.txt")
        self.items = []
        self.t0 = time.time()
        open(self.logpath, "w", encoding="utf-8").close()

    def log(self, msg):
        with open(self.logpath, "a", encoding="utf-8") as f:
            f.write("[%7.2f s] %s\n" % (time.time() - self.t0, msg))

    def set(self, key, value):
        self.items.append((key, value))

    def write(self, status, message=""):
        # plain key=value lines: trivial to read from Praat with extractWord$/extractNumber
        with open(self.path, "w", encoding="utf-8", newline="\n") as f:
            f.write("status=%s\n" % status)
            f.write("message=%s\n" % message.replace("\n", " "))
            for k, v in self.items:
                if isinstance(v, float):
                    v = "%.6g" % v
                f.write("%s=%s\n" % (k, v))


def check_dependencies():
    missing = []
    for mod, pipname in REQUIRED:
        try:
            __import__(mod)
        except Exception:
            missing.append(pipname)
    return missing


# ----------------------------------------------------------------------------
# differentiable scattering (NumPy, Kymatio filters)
# ----------------------------------------------------------------------------
FFT_WORKERS = -1    # all cores; set to 1 inside worker processes


class _FFT:
    """scipy.fft on all cores (numpy fallback); transforms along the last axis."""
    def __init__(self):
        try:
            import scipy.fft as sf
            self.fft = lambda a: sf.fft(a, axis=-1, workers=FFT_WORKERS)
            self.ifft = lambda a: sf.ifft(a, axis=-1, workers=FFT_WORKERS)
        except Exception:
            import numpy as np
            self.fft = lambda a: np.fft.fft(a, axis=-1)
            self.ifft = lambda a: np.fft.ifft(a, axis=-1)


class Scattering:
    """Kymatio's 1-D scattering (orders 1-2 identical, order 0 in envelope form)
    with its exact adjoint.

    v0.2: filters are BATCHED. All first-order filters sharing a dyadic
    subsampling j1 are processed as one (G x N) array, and for each such group
    every second-order filter n2 is applied to all G band envelopes at once.
    That turns ~550 per-path Python iterations (x several FFTs each, forward
    and backward) into ~60 array operations; the arithmetic is unchanged.
    """

    def __init__(self, N, J, Q):
        import numpy as np
        from kymatio.scattering1d.filter_bank import scattering_filter_factory
        self.np = np
        self.fx = _FFT()
        self.N, self.J, self.Q = N, J, Q
        phi, psi1, psi2 = scattering_filter_factory(N, J, Q, 2 ** J)
        self.phi = [np.asarray(l, dtype=np.float64) for l in phi["levels"]]
        self.psi1 = psi1
        self.psi2 = psi2
        self.xi1 = np.array([p["xi"] for p in psi1])
        self.xi2 = np.array([p["xi"] for p in psi2])
        self.paths = []  # (n1, n2) pairs, Kymatio order
        pidx = {}
        for n1, p1 in enumerate(psi1):
            for n2, p2 in enumerate(psi2):
                if p2["j"] > p1["j"]:
                    pidx[(n1, n2)] = len(self.paths)
                    self.paths.append((n1, n2))
        self.path_n1 = np.array([p[0] for p in self.paths], dtype=int)
        self.path_n2 = np.array([p[1] for p in self.paths], dtype=int)
        self.T_frames = N // 2 ** J

        # batch plan: one group per distinct first-order subsampling j1
        self.groups = []
        j1s = [f["j"] for f in psi1]
        for j1 in sorted(set(j1s)):
            idx1 = np.array([n for n, j in enumerate(j1s) if j == j1], dtype=int)
            k1 = min(j1, J)
            g = {"idx1": idx1, "k1": k1, "s1": 2 ** k1, "M1": N // 2 ** k1,
                 "P1": np.stack([np.asarray(psi1[n]["levels"][0]) for n in idx1]),
                 "slp": 2 ** (J - k1), "sec": []}
            g["sup"], g["dst"] = self._support(np.abs(g["P1"]).max(axis=0), g["M1"])
            if g["sup"] is not None:
                g["P1s"] = g["P1"][:, g["sup"]] / g["s1"]
            for n2, f2 in enumerate(psi2):
                if f2["j"] <= j1:
                    continue
                k2 = max(min(f2["j"], J) - k1, 0)
                F = np.asarray(f2["levels"][k1])
                e = {"n2": n2, "k2": k2, "s2": 2 ** k2, "M2": g["M1"] // 2 ** k2,
                     "F": F[None, :], "lvl": k1 + k2, "slp": 2 ** (J - k1 - k2),
                     "pidx": np.array([pidx[(n1, n2)] for n1 in idx1], dtype=int)}
                e["sup"], e["dst"] = self._support(np.abs(F), e["M2"])
                if e["sup"] is not None:
                    e["Fs"] = F[e["sup"]][None, :] / e["s2"]
                g["sec"].append(e)
            self.groups.append(g)

    def _support(self, mag, M, rel=1e-10):
        """Frequency bins where a (group of) filter(s) is not negligible, and
        where they land after periodization to length M. Returns (None, None)
        when the landing bins collide (then the dense path is used)."""
        np = self.np
        sup = np.nonzero(mag > rel * mag.max())[0]
        dst = sup % M
        if len(np.unique(dst)) != len(dst) or len(sup) > 0.5 * len(mag):
            return None, None
        return sup, dst

    # --- primitives and their adjoints (row-wise on 2-D arrays) ------------
    @staticmethod
    def _sub(A, s):
        """dyadic subsampling in time = periodization of the spectrum"""
        if s == 1:
            return A
        return A.reshape(A.shape[:-1] + (s, A.shape[-1] // s)).mean(axis=-2)

    def _sub_adj(self, Y, s):
        if s == 1:
            return Y
        reps = (1,) * (Y.ndim - 1) + (s,)
        return self.np.tile(Y, reps) / s

    def _lowpass(self, Uh, level, s):
        """S = real(ifft(periodize(Uh * phi_level, s)))"""
        return self.fx.ifft(self._sub(Uh * self.phi[level], s)).real

    def _lowpass_adj(self, gS, level, s):
        M = gS.shape[-1]
        return self.phi[level] * self._sub_adj(self.fx.fft(gS) / M, s)

    def forward(self, x, keep=False):
        np = self.np
        fft = self.fx
        J = self.J
        X = fft.fft(x)
        u0 = np.sqrt(x * x + 1e-12)              # order 0, envelope form
        S0 = self._lowpass(fft.fft(u0), 0, 2 ** J)
        S1 = np.empty((len(self.psi1), self.T_frames))
        S2 = np.empty((len(self.paths), self.T_frames))
        cache = []
        for g in self.groups:
            if g["sup"] is not None:            # multiply only where the filters live
                A = np.zeros((len(g["idx1"]), g["M1"]), dtype=complex)
                A[:, g["dst"]] = X[g["sup"]][None, :] * g["P1s"]
            else:
                A = self._sub(X[None, :] * g["P1"], g["s1"])
            z1 = fft.ifft(A)
            u1 = np.sqrt(z1.real ** 2 + z1.imag ** 2 + 1e-20)
            U1 = fft.fft(u1)
            S1[g["idx1"]] = self._lowpass(U1, g["k1"], g["slp"])
            c2 = []
            for e in g["sec"]:
                if e["sup"] is not None:
                    Bm = np.zeros((len(g["idx1"]), e["M2"]), dtype=complex)
                    Bm[:, e["dst"]] = U1[:, e["sup"]] * e["Fs"]
                else:
                    Bm = self._sub(U1 * e["F"], e["s2"])
                z2 = fft.ifft(Bm)
                u2 = np.sqrt(z2.real ** 2 + z2.imag ** 2 + 1e-20)
                S2[e["pidx"]] = self._lowpass(fft.fft(u2), e["lvl"], e["slp"])
                if keep:
                    c2.append((z2, u2))
            if keep:
                cache.append((z1, u1, c2))
        c = {"x": x, "u0": u0, "groups": cache} if keep else {}
        return S0, S1, S2, c

    def backward(self, c, gS0, gS1, gS2):
        np = self.np
        fft = self.fx
        J = self.J
        N = self.N
        x = c["x"]
        gx = (N * fft.ifft(self._lowpass_adj(gS0, 0, 2 ** J))).real * (x / c["u0"])
        gX = np.zeros(N, dtype=complex)
        for g, (z1, u1, c2) in zip(self.groups, c["groups"]):
            M1 = g["M1"]
            gU1 = self._lowpass_adj(gS1[g["idx1"]], g["k1"], g["slp"]).astype(complex)
            for e, (z2, u2) in zip(g["sec"], c2):
                M2 = z2.shape[-1]
                gu2 = (M2 * fft.ifft(self._lowpass_adj(gS2[e["pidx"]], e["lvl"], e["slp"]))).real
                gY2 = fft.fft(gu2 * z2 / u2) / M2
                if e["sup"] is not None:
                    gU1[:, e["sup"]] += e["Fs"] * gY2[:, e["dst"]]
                else:
                    gU1 = gU1 + e["F"] * self._sub_adj(gY2, e["s2"])
            gu1 = (M1 * fft.ifft(gU1)).real
            gY1 = fft.fft(gu1 * z1 / u1) / M1
            if g["sup"] is not None:
                gX[g["sup"]] += (g["P1s"] * gY1[:, g["dst"]]).sum(axis=0)
            else:
                gX += (g["P1"] * self._sub_adj(gY1, g["s1"])).sum(axis=0)
        gx += (N * fft.ifft(gX)).real
        return gx


# ----------------------------------------------------------------------------
# target representation and its transformations
# ----------------------------------------------------------------------------
class Target:
    """Log-domain target: L0 (1 x T), L1 (n1 x T), L2n = log S2 - log S1[n1]."""

    def __init__(self, sc, S0, S1, S2):
        np = sc.np
        self.sc = sc
        self.e0 = 1e-3 * max(np.mean(np.abs(S0)), 1e-12)
        self.e1 = 1e-3 * max(np.mean(np.abs(S1)), 1e-12)
        self.e2 = 1e-3 * max(np.mean(np.abs(S2)), 1e-12)
        self.L0 = np.log(np.maximum(S0, 0) + self.e0)
        self.L1 = np.log(np.maximum(S1, 0) + self.e1)
        self.L2n = np.log(np.maximum(S2, 0) + self.e2) - self.L1[sc.path_n1]

    def copy(self):
        t = Target.__new__(Target)
        t.__dict__.update(self.__dict__)
        t.L0, t.L1, t.L2n = self.L0.copy(), self.L1.copy(), self.L2n.copy()
        return t


def apply_ops(tg, ops, amount, sr, rng, applied):
    """Modify the target itself. amount scales every op (base ops pass 1.0)."""
    import numpy as np
    from scipy.ndimage import gaussian_filter1d
    sc = tg.sc
    hop_s = 2 ** sc.J / sr
    lx1 = np.log2(np.maximum(sc.xi1, 1e-9))           # carrier log-frequency axis
    for name, a in ops:
        a = a * amount
        if abs(a) < 1e-6:
            continue
        if name == "time_smooth_S1":                   # blur spectral trajectory over time
            sig = a * 0.5 / hop_s
            if sig > 0.3:
                tg.L1 = gaussian_filter1d(tg.L1, sig, axis=1, mode="nearest")
                tg.L0 = gaussian_filter1d(tg.L0, sig, axis=-1, mode="nearest")
            applied.append("time smoothing of order 1 (sigma %.2f s)" % (a * 0.5))
        elif name == "freq_blur_S1":                   # smooth log-spectrum across bands
            sig = a * 1.0                               # octaves
            W = np.exp(-0.5 * ((lx1[:, None] - lx1[None, :]) / sig) ** 2)
            W /= W.sum(axis=1, keepdims=True)
            tg.L1 = W @ tg.L1
            applied.append("band blur of order 1 (%.2f oct)" % sig)
        elif name == "spectral_shift":                  # move spectral envelope in log-freq
            oct_ = a
            order = np.argsort(lx1)
            for t in range(tg.L1.shape[1]):
                col = tg.L1[order, t]
                tg.L1[order, t] = np.interp(lx1[order] - oct_, lx1[order], col)
            applied.append("spectral envelope shift %+.2f oct" % oct_)
        elif name == "mod_rate_shift":                  # move modulation energy in rate
            oct_ = a
            lx2 = np.log2(np.maximum(sc.xi2, 1e-12))
            for n1 in np.unique(sc.path_n1):
                idx = np.where(sc.path_n1 == n1)[0]
                if len(idx) < 2:
                    continue
                lr = lx2[sc.path_n2[idx]]
                o = np.argsort(lr)
                for t in range(tg.L2n.shape[1]):
                    col = tg.L2n[idx[o], t]
                    tg.L2n[idx[o], t] = np.interp(lr[o] - oct_, lr[o], col)
            applied.append("modulation-rate shift %+.2f oct" % oct_)
        elif name == "mod_depth":                       # exaggerate modulation depth
            tg.L2n = tg.L2n + a * math.log(2.0)
            applied.append("modulation depth x%.2f" % (2.0 ** a))
        elif name == "dyn_compress_S1":
            g = max(0.05, 1.0 - a)
            m = tg.L1.mean(axis=1, keepdims=True)
            tg.L1 = m + g * (tg.L1 - m)
            applied.append("order-1 dynamics x%.2f (compress)" % g)
        elif name == "dyn_expand_S1":
            g = 1.0 + a
            m = tg.L1.mean(axis=1, keepdims=True)
            tg.L1 = m + g * (tg.L1 - m)
            applied.append("order-1 dynamics x%.2f (expand)" % g)
        elif name == "sparsify_S2":                     # keep only strongest modulation paths
            keep = max(0.05, 1.0 - 0.7 * a)
            strength = tg.L2n.mean(axis=1)
            thr = np.quantile(strength, 1.0 - keep)
            weak = strength < thr
            tg.L2n[weak] += a * math.log(0.2)
            applied.append("modulation sparsification (keep %.0f%% of paths)" % (100 * keep))
        elif name == "perturb":                         # smooth random field in log domain
            sig_t = max(0.5, 0.5 / hop_s)
            f1 = gaussian_filter1d(rng.standard_normal(tg.L1.shape), sig_t, axis=1, mode="wrap")
            f1 = gaussian_filter1d(f1, 2.0, axis=0, mode="nearest")
            f1 /= max(f1.std(), 1e-9)
            f2 = gaussian_filter1d(rng.standard_normal(tg.L2n.shape), sig_t, axis=1, mode="wrap")
            f2 /= max(f2.std(), 1e-9)
            tg.L1 = tg.L1 + 0.6 * a * f1
            tg.L2n = tg.L2n + 0.6 * a * f2
            applied.append("smooth random target perturbation (%.2f log units)" % (0.6 * a))
    return tg


# ----------------------------------------------------------------------------
# loss
# ----------------------------------------------------------------------------
def make_loss(sc, tg, w, cont=None):
    np = sc.np
    n0, n1c, n2c = tg.L0.size, tg.L1.size, max(tg.L2n.size, 1)
    last = {}

    def f(x):
        S0, S1, S2, c = sc.forward(x, keep=True)
        A0 = np.maximum(S0, 0) + tg.e0
        A1 = np.maximum(S1, 0) + tg.e1
        A2 = np.maximum(S2, 0) + tg.e2
        D0 = np.log(A0) - tg.L0
        D1 = np.log(A1) - tg.L1
        D2 = np.log(A2) - np.log(A1[sc.path_n1]) - tg.L2n
        l0 = w[0] * np.sum(D0 ** 2) / n0
        l1 = w[1] * np.sum(D1 ** 2) / n1c
        l2 = w[2] * np.sum(D2 ** 2) / n2c
        g0 = (2 * w[0] / n0) * D0 / A0 * (S0 > 0)
        g1 = (2 * w[1] / n1c) * D1 / A1
        g2 = (2 * w[2] / n2c) * D2 / A2
        # normalized order 2 also pulls on its parent S1
        gp = np.zeros_like(A1)
        np.add.at(gp, sc.path_n1, -(2 * w[2] / n2c) * D2 / A1[sc.path_n1])
        g1 = (g1 + gp) * (S1 > 0)
        g2 = g2 * (S2 > 0)
        gx = sc.backward(c, g0, g1, g2)
        lc = 0.0
        if cont is not None:
            idx, ref, lam = cont
            d = x[idx] - ref
            den = max(np.mean(ref ** 2), 1e-9) * len(idx)
            lc = lam * np.sum(d ** 2) / den
            gx[idx] += lam * 2 * d / den
        L = l0 + l1 + l2 + lc
        last.update(l0=l0, l1=l1, l2=l2, lc=lc, L=L)
        if not np.isfinite(L) or not np.all(np.isfinite(gx)):
            raise FloatingPointError("non-finite loss or gradient")
        return L, gx

    return f, last


# ----------------------------------------------------------------------------
# helpers
# ----------------------------------------------------------------------------
def mirror_take(sig, start, length):
    """Window [start, start+length) with symmetric reflection outside the file."""
    import numpy as np
    L = len(sig)
    idx = np.arange(start, start + length)
    if L == 1:
        return np.full(length, sig[0])
    period = 2 * L
    m = np.mod(idx, period)
    m = np.where(m >= L, period - 1 - m, m)
    return sig[m]


def phase_randomized(sig, rng):
    import numpy as np
    S = np.fft.rfft(sig)
    ph = rng.uniform(0, 2 * np.pi, S.shape)
    ph[0] = 0
    return np.fft.irfft(np.abs(S) * np.exp(1j * ph), n=len(sig))


def smooth_spectrum_noise(sig, rng, frac_oct=1.0 / 3.0):
    """Noise with the source's long-term spectral ENVELOPE (smoothed over
    frac_oct octaves), so harmonic/pitch fine structure is absent."""
    import numpy as np
    n = len(sig)
    P = np.abs(np.fft.rfft(sig)) ** 2
    f = np.arange(len(P), dtype=float)
    f[0] = 0.5
    lf = np.log2(f)
    edges = np.arange(lf.min(), lf.max() + frac_oct, frac_oct)
    idx = np.clip(np.digitize(lf, edges) - 1, 0, len(edges) - 1)
    band = np.bincount(idx, weights=P, minlength=len(edges)) / np.maximum(
        np.bincount(idx, minlength=len(edges)), 1)
    centers = edges + frac_oct / 2
    ok = band > 0
    env = np.exp(np.interp(lf, centers[ok], np.log(band[ok] + 1e-300)))
    ph = rng.uniform(0, 2 * np.pi, len(P))
    ph[0] = 0
    return np.fft.irfft(np.sqrt(env) * np.exp(1j * ph), n=n)


def modulation_profile(sc, S1, S2, sr, e1, e2):
    """Time-mean normalized order-2 energy (dB) on a carrier-octave x rate-octave grid."""
    import numpy as np
    L1 = np.log(np.maximum(S1, 0) + e1)
    L2n = np.log(np.maximum(S2, 0) + e2) - L1[sc.path_n1]
    return L2n.mean(axis=1) * 20 / math.log(10)


# ----------------------------------------------------------------------------
# main processing
# ----------------------------------------------------------------------------
# ----------------------------------------------------------------------------
# v0.3: direct (calibrated) synthesis + optional refinement, per segment
# ----------------------------------------------------------------------------
_SC_CACHE = {}
SIGMA_MAX = 2.5     # cap on the std of the summed per-band modulation signal


def get_scattering(N, J, Q):
    key = (N, J, tuple(Q))
    if key not in _SC_CACHE:
        _SC_CACHE.clear()
        _SC_CACHE[key] = Scattering(N, J, Q)
    return _SC_CACHE[key]


def loss_parts(sc, tg, w, S0, S1, S2):
    """Same weighted log-domain loss as make_loss, forward only."""
    import numpy as np
    A0 = np.maximum(S0, 0) + tg.e0
    A1 = np.maximum(S1, 0) + tg.e1
    A2 = np.maximum(S2, 0) + tg.e2
    l0 = w[0] * np.mean((np.log(A0) - tg.L0) ** 2)
    l1 = w[1] * np.mean((np.log(A1) - tg.L1) ** 2)
    l2 = w[2] * np.mean((np.log(A2) - np.log(A1[sc.path_n1]) - tg.L2n) ** 2)
    return float(l0), float(l1), float(l2)


def _interp_plan(n_out, N, Tn, hop):
    """Linear, circular interpolation from the frame grid to n_out samples."""
    import numpy as np
    pos = ((np.arange(n_out) + 0.5) * (N / n_out)) / hop - 0.5   # in frame units
    i0 = np.floor(pos).astype(int)
    fr = pos - i0
    return np.mod(i0, Tn), np.mod(i0 + 1, Tn), fr


def direct_synthesis(sc, src_win, tg, w, rnd, rng, rounds, hist, si):
    """Build a waveform band by band from the (transformed) scattering target.

    Each first-order band = a carrier (band-filtered, phase-randomized source
    spectrum; Randomness blends toward a smoothed, pitch-free spectrum)
    times an envelope:
        a(t) * exp( sum_paths g_p(t) * m_p(t) )
    a(t) follows the order-1 target; each m_p is noise band-limited by the
    SAME second-order Morlet filter the analysis uses, and its gain g_p(t) sets
    that path's modulation depth. a and g are then calibrated in a few rounds
    by re-analysing the result (forward passes only, no gradient):
      round 0: measure the modulation plain band noise already has (baseline)
      round 1: probe - measure each path's response to a known gain
      rounds 2+: proportional corrections of a (order 1) and g (order 2)
    Finally a smooth gain pulls the order-0 envelope toward the target by w0.
    """
    import numpy as np
    N, J = sc.N, sc.J
    Tn, hop = sc.T_frames, 2 ** sc.J
    import scipy.fft as fft          # same FFT_WORKERS policy as the analysis
    fftw = {"workers": FFT_WORKERS}

    # effective order-1 target: w1 blends the full trajectory with a neutral one
    # (time-averaged, blurred over one octave -> no trajectory, no fine identity)
    lx1 = np.log2(np.maximum(sc.xi1, 1e-9))
    Wb = np.exp(-0.5 * (lx1[:, None] - lx1[None, :]) ** 2)
    Wb /= Wb.sum(axis=1, keepdims=True)
    L1_neutral = (Wb @ tg.L1.mean(axis=1))[:, None] * np.ones((1, Tn))
    L1_eff = w[1] * tg.L1 + (1 - w[1]) * L1_neutral

    # carrier spectrum: |source| (0 %) ... smoothed envelope (100 %), random phase
    X = fft.fft(src_win, **fftw)
    P = np.abs(X) ** 2
    Psm = np.abs(fft.fft(smooth_spectrum_noise(src_win, rng), **fftw)) ** 2
    mag = np.sqrt((1 - rnd) * P / max(P.mean(), 1e-30) + rnd * Psm / max(Psm.mean(), 1e-30))
    Xr = mag * np.exp(1j * rng.uniform(0, 2 * np.pi, N))

    # modulation sources per band, at a decimated rate that still covers the
    # fastest modulation filter of that band
    bands = []
    for n1, f1 in enumerate(sc.psi1):
        pidx = np.where(sc.path_n1 == n1)[0]
        xmax = max([sc.xi2[sc.path_n2[p]] + 3 * sc.psi2[sc.path_n2[p]]["sigma"] for p in pidx], default=0.0)
        kd = 0
        while (N >> (kd + 1)) >= 8 * Tn and 0.5 / 2 ** (kd + 1) > 1.25 * xmax:
            kd += 1
        Md = N >> kd
        if len(pidx):
            # draw the noise exactly as v0.3.1 did (real then imaginary, path by
            # path) so realizations are unchanged, then ONE batched IFFT per band
            spec = np.empty((len(pidx), Md), dtype=complex)
            for r, p in enumerate(pidx):
                F0 = np.asarray(sc.psi2[sc.path_n2[p]]["levels"][0])
                Fd = F0 if Md == N else np.concatenate([F0[:Md // 2], F0[N - Md // 2:]])
                spec[r] = (rng.standard_normal(Md) + 1j * rng.standard_normal(Md)) * Fd
            wv = fft.ifft(spec, axis=-1, **fftw)
            wv /= np.maximum(np.mean(np.abs(wv), axis=1, keepdims=True), 1e-30)
            WR = wv.real.astype(np.float32)
        else:
            WR = np.zeros((0, Md), dtype=np.float32)
        var = (WR.astype(np.float64) ** 2).mean(axis=1) if len(pidx) else np.zeros(0)
        bands.append({"pidx": pidx, "Md": Md, "WR": WR, "var": var,
                      "plan": _interp_plan(Md, N, Tn, hop)})
    # carriers do not change between calibration rounds: compute once.
    # Only the real part is kept (the envelope is real: Re(c*env) = Re(c)*env).
    carriers = np.empty((len(sc.psi1), N), dtype=np.float32)
    for n1, f1 in enumerate(sc.psi1):
        c = fft.ifft(Xr * f1["levels"][0], **fftw)
        carriers[n1] = c.real / max(np.sqrt(np.mean(np.abs(c) ** 2)), 1e-30)

    def lerp(vals, plan):
        i0, i1, fr = plan
        return vals[..., i0] * (1 - fr) + vals[..., i1] * fr

    def lerp32(vals, plan32):
        # single-precision gain interpolation for the modulation paths
        i0, i1, fr, one_minus = plan32
        v = vals.astype(np.float32)
        return v[:, i0] * one_minus + v[:, i1] * fr

    for b in bands:
        i0, i1, fr = b["plan"]
        f32 = fr.astype(np.float32)
        b["plan32"] = (i0, i1, f32, (1 - f32))
        b["var32"] = b["var"].astype(np.float32)[:, None]

    def synth(a, g):
        x = np.zeros(N)
        for n1, f1 in enumerate(sc.psi1):
            b = bands[n1]
            env_d = lerp(a[n1], b["plan"])
            if len(b["pidx"]):
                gt = lerp32(g[b["pidx"]], b["plan32"])
                # LINEAR modulation 1 + sum g*m, softly rectified. (v0.3 draft used
                # exp(sum g*m): a log-normal envelope whose tails produced clicks,
                # crest factor 32-36 dB against 18 dB in the source.)
                sd = np.sqrt(np.einsum("pt,pt,p->t", gt, gt, b["var32"][:, 0], optimize=False))
                cap = np.minimum(1.0, SIGMA_MAX / np.maximum(sd, 1e-12))
                z = 1.0 + cap * np.einsum("pt,pt->t", gt, b["WR"], optimize=False)
                env_d = env_d * np.logaddexp(0.0, 4.0 * z) / 4.0
            if b["Md"] < N:
                E = fft.rfft(env_d, **fftw)
                Eu = np.zeros(N // 2 + 1, dtype=complex)
                Eu[:len(E)] = E
                env = fft.irfft(Eu, n=N, **fftw) * (N / b["Md"])
            else:
                env = env_d
            x += carriers[n1] * env
        return x

    def measure(x):
        S0, S1, S2, _ = sc.forward(x)
        A1 = np.log(np.maximum(S1, 0) + tg.e1)
        R = np.exp(np.log(np.maximum(S2, 0) + tg.e2) - A1[sc.path_n1])
        hist.append((si, len(hist_local)) + loss_parts(sc, tg, w, S0, S1, S2))
        hist_local.append(1)
        return S0, A1, R

    hist_local = []
    a = np.exp(L1_eff)
    g = np.zeros((len(sc.paths), Tn))
    step = lambda A1: np.exp(np.clip(0.8 * (L1_eff - A1), -3, 3))

    x = synth(a, g)                                   # round 0: baseline
    S0, A1, R_b = measure(x)
    a *= step(A1)
    R_t = np.exp(w[2] * tg.L2n + (1 - w[2]) * np.log(R_b))
    excess_t = np.sqrt(np.maximum(R_t ** 2 - R_b ** 2, 0))

    g0 = 0.2                                           # round 1: probe
    x = synth(a, g + g0)
    S0, A1, R_p = measure(x)
    a *= step(A1)
    K = np.sqrt(np.maximum(R_p ** 2 - R_b ** 2, 1e-12).mean(axis=1)) / g0
    g = np.clip(excess_t / K[:, None], 0, 1.5)

    for _ in range(max(0, rounds - 2)):               # rounds 2+: corrections
        x = synth(a, g)
        S0, A1, R_a = measure(x)
        a *= step(A1)
        excess_a = np.sqrt(np.maximum(R_a ** 2 - R_b ** 2, 1e-12))
        g = np.where(excess_t > 0, np.clip(g * np.clip(excess_t / excess_a, 0.5, 2.0), 0, 1.5), 0.0)

    x = synth(a, g)
    S0, A1, _ = measure(x)
    # order 0: pull the envelope toward the target, strength w0
    A0 = np.log(np.maximum(S0, 0) + tg.e0)
    gain = np.exp(np.clip(w[0] * (tg.L0 - A0), -3, 3))
    x = x * lerp(gain, _interp_plan(N, N, Tn, hop))
    return x


def segment_job(job):
    """One segment, end to end. Top-level so it can run in a worker process."""
    import numpy as np
    from scipy.optimize import minimize

    def log(msg):
        with open(job["logpath"], "a", encoding="utf-8") as f:
            f.write("[seg %d/%d] %s\n" % (job["si"] + 1, job["nseg"], msg))

    global FFT_WORKERS
    if job.get("nwork", 1) > 1:
        FFT_WORKERS = 1          # N processes x all-core FFT threads = oversubscription
    t0 = time.time()
    log("started (pid %d)" % os.getpid())
    si, Nseg, J, Q, sr_w = job["si"], job["Nseg"], job["J"], job["Q"], job["sr_w"]
    sc = get_scattering(Nseg, J, Q)
    w = job["w"]
    src_win = job["src_win"]
    S0, S1, S2, _ = sc.forward(src_win)
    tg0 = Target(sc, S0, S1, S2)
    tg = tg0.copy()
    rng_tgt = np.random.default_rng([job["seed"], 7919, si])
    rng = np.random.default_rng([job["seed"], si])
    applied = []
    base_applied, t_applied = [], []
    apply_ops(tg, job["base_ops"], 1.0, sr_w, rng_tgt, base_applied)
    apply_ops(tg, job["t_ops"], job["tr"], sr_w, rng_tgt, t_applied)
    applied = ["[preset, always] " + x for x in base_applied] + ["[x Transformation] " + x for x in t_applied]

    hist = []
    x = direct_synthesis(sc, src_win, tg, w, job["rnd"], rng, job["rounds"], hist, si)
    x *= np.sqrt(np.mean(src_win ** 2)) / max(np.sqrt(np.mean(x ** 2)), 1e-12)
    Sx = sc.forward(x)[:3]
    L_direct = sum(loss_parts(sc, tg, w, *Sx))
    log("direct synthesis done in %.1f s (loss %.4f)" % (time.time() - t0, L_direct))
    loss_start = sum(hist[0][2:])
    fail = ""

    iters = job["iters"]
    if iters > 0:
        f, last = make_loss(sc, tg, w)
        best = {"x": x.copy(), "L": L_direct}
        it = [0]
        base = len(hist)
        t1 = time.time()
        Lh = []

        def fun(z):
            L, gz = f(z)
            if L < best["L"]:
                best["L"] = L
                best["x"] = z.copy()
            return L, gz

        def cb(zk):
            it[0] += 1
            hist.append((si, base + it[0], last["l0"], last["l1"], last["l2"]))
            Lh.append(best["L"])
            if it[0] % 10 == 0:
                per = (time.time() - t1) / it[0]
                log("refine %d/%d  loss %.4f  (%.2f s/iter, ~%.0f s left in this segment)"
                    % (it[0], iters, best["L"], per, per * (iters - it[0])))
            if it[0] >= 20 and (Lh[-11] - Lh[-1]) < 0.001 * Lh[-11]:
                raise StopIteration

        try:
            minimize(fun, x, jac=True, method="L-BFGS-B", callback=cb,
                     options={"maxiter": iters, "maxcor": 20, "gtol": 1e-10, "ftol": 1e-12})
        except StopIteration:
            pass
        except FloatingPointError as e:
            fail = "seg %d: refinement stopped on %s, best iterate kept" % (si + 1, e)
        x = best["x"]

    if iters > 0:
        So0, So1, So2, _ = sc.forward(x)
    else:
        So0, So1, So2 = Sx          # waveform unchanged since L_direct: no second analysis
    L_end = sum(loss_parts(sc, tg, w, So0, So1, So2))
    log("finished in %.1f s (loss %.4f)" % (time.time() - t0, L_end))

    margin, a0, b0 = job["margin"], job["a0"], job["b0"]
    db = 8.685889638
    f_lo = margin // 2 ** J
    f_hi = min(sc.T_frames, f_lo + int(math.ceil((b0 - a0) / 2 ** J)))
    o0 = [((a0 - margin + (fi + 0.5) * 2 ** J) / sr_w, tg0.L0[fi] * db, tg.L0[fi] * db,
           math.log(max(So0[fi], 0) + tg0.e0) * db) for fi in range(f_lo, f_hi)]
    return {
        "si": si, "out": x[margin:margin + (b0 - a0)], "hist": hist, "applied": applied,
        "loss_start": loss_start, "loss_direct": L_direct, "loss_end": L_end, "fail": fail,
        "o0": o0,
        "ps": tg0.L2n.mean(axis=1) * db, "pt": tg.L2n.mean(axis=1) * db,
        "po": (np.log(np.maximum(So2, 0) + tg0.e2)
               - np.log(np.maximum(So1, 0) + tg0.e1)[sc.path_n1]).mean(axis=1) * db,
        "q_s": tg0.L1.mean(axis=1) * db, "q_t": tg.L1.mean(axis=1) * db,
        "q_o": np.log(np.maximum(So1, 0) + tg0.e1).mean(axis=1) * db,
        "seconds": time.time() - t0,
    }


def run(a, rep):
    import numpy as np
    from scipy.io import wavfile
    from scipy.signal import resample_poly
    from scipy.optimize import minimize
    from fractions import Fraction

    rep.log("reading %s" % a.inp)
    sr_src, data = wavfile.read(a.inp)
    if data.dtype.kind == "i":
        data = data.astype(np.float64) / float(np.iinfo(data.dtype).max)
    elif data.dtype.kind == "u":
        data = (data.astype(np.float64) - 128) / 128.0
    else:
        data = data.astype(np.float64)
    if data.ndim > 1:
        data = data.mean(axis=1)
    n_src = len(data)
    if n_src < 2:
        raise ValueError("input is empty")
    rep.set("source_sr", sr_src)
    rep.set("source_samples", n_src)
    data = data - data.mean()
    src_rms = float(np.sqrt(np.mean(data ** 2)))
    rep.set("source_rms", src_rms)

    preset = a.preset
    wdef, base_ops, t_ops = PRESETS[preset]
    w = (np.array(wdef, float) if wdef is not None
         else np.array([a.w0, a.w1, a.w2], float)) / 100.0
    w = np.clip(w, 0, 1)
    if w.sum() <= 0:
        w = np.array([0.2, 0.5, 1.0])
        rep.set("weights_note", "all weights were 0 - fell back to 20/50/100")
    tr = float(np.clip(a.transform / 100.0, 0, 1))
    rnd = float(np.clip(a.randomness / 100.0, 0, 1))
    rep.set("preset", preset)
    rep.set("w0", w[0] * 100)
    rep.set("w1", w[1] * 100)
    rep.set("w2", w[2] * 100)
    rep.set("transform", tr * 100)
    rep.set("randomness", rnd * 100)

    seed = int(a.seed) if int(a.seed) > 0 else int.from_bytes(os.urandom(3), "little") + 1
    rep.set("seed", seed)

    if src_rms < 1e-7:
        rep.log("silent input - writing silence")
        wavfile.write(a.out, sr_src, np.zeros(n_src, dtype=np.float32))
        rep.set("silent_input", 1)
        rep.set("output_samples", n_src)
        return

    # working rate
    cap, rounds, iters, maxlog2 = QUALITY[a.quality]
    if a.iters >= 0:
        iters = a.iters
    if sr_src > cap:
        fr = Fraction(cap, int(sr_src)).limit_denominator(1000)
        sr_w = sr_src * fr.numerator / fr.denominator
        work = resample_poly(data, fr.numerator, fr.denominator)
    else:
        fr = None
        sr_w = float(sr_src)
        work = data.copy()
    rep.set("working_sr", sr_w)
    rep.set("iterations_per_segment", iters)
    rep.set("calibration_rounds", rounds)
    scale_g = float(np.sqrt(np.mean(work ** 2)))
    work = work / scale_g
    Lw = len(work)

    # scattering geometry derived from the WORKING rate
    J = int(round(math.log2(SCALE_SECONDS[a.scale] * sr_w)))
    J = max(5, J)
    # keep at least ~4 averaging frames inside the file
    while J > 5 and 2 ** J * 4 > max(Lw, 1):
        J -= 1
    Q = DETAIL_Q[a.detail]
    # context on each side of a segment: phi_J reaches ~2.5 T, and with a 1 T
    # margin the first core frame was measured 0.8 dB off (median over bands)
    # against a full-length analysis; 2 T brings that to 0.26 dB
    margin = 2 * 2 ** J
    maxlog2 = max(maxlog2, J + 3)
    rep.set("J", J)
    rep.set("Q1", Q[0])
    rep.set("Q2", Q[1])
    rep.set("T_ms", 1000.0 * 2 ** J / sr_w)
    rep.set("scale", a.scale)
    rep.set("detail", a.detail)
    rep.set("quality", a.quality)

    # segmentation
    need = Lw + 2 * margin
    if need <= 2 ** maxlog2:
        Nseg = 2 ** int(math.ceil(math.log2(max(need, 8 * 2 ** J))))
        segs = [(0, Lw)]
        O = 0
    else:
        Nseg = 2 ** maxlog2
        O = int(max(2 ** J, round(0.25 * sr_w)))
        C = Nseg - 2 * margin - O
        if C < 2 ** J:
            raise ValueError("segment too short for this Texture scale; choose Fine/Medium or High quality")
        segs = []
        s0 = 0
        while s0 < Lw:
            segs.append((s0, min(s0 + C + O, Lw)))
            if s0 + C + O >= Lw:
                break
            s0 += C
    rep.set("segments", len(segs))
    rep.set("segment_samples", Nseg)
    rep.set("overlap_ms", 1000.0 * O / sr_w)

    rep.log("building Kymatio filter bank N=%d J=%d Q=%s" % (Nseg, J, Q))
    sc = get_scattering(Nseg, J, Q)
    rep.set("n_order1", len(sc.psi1))
    rep.set("n_order2", len(sc.paths))
    used = sc.xi2[sc.path_n2] * sr_w          # rates that actually occur in valid paths
    rep.set("mod_rate_min_hz", float(used.min()))
    rep.set("mod_rate_max_hz", float(used.max()))

    jobs = [{"si": si, "nseg": len(segs), "a0": a0, "b0": b0, "margin": margin,
             "src_win": mirror_take(work, a0 - margin, Nseg), "Nseg": Nseg, "J": J, "Q": Q,
             "sr_w": sr_w, "w": w, "base_ops": base_ops, "t_ops": t_ops, "tr": tr, "rnd": rnd,
             "seed": seed, "rounds": rounds, "iters": iters, "logpath": rep.logpath}
            for si, (a0, b0) in enumerate(segs)]

    # workers: one process per segment, bounded by cores and a memory estimate
    ncpu = os.cpu_count() or 1
    per_worker = Nseg * (len(sc.psi1) * (8 * 3 + 4) + 16 * 40)  # bytes, rough (incl. cached carriers)
    nwork = a.workers if a.workers > 0 else max(1, min(ncpu, len(jobs), 8, int(3e9 // per_worker)))
    rep.set("workers", nwork)
    rep.log("%d segment(s), %d worker process(es); direct synthesis (%d calibration rounds)%s"
            % (len(jobs), nwork, rounds, "" if iters == 0 else " + up to %d refinement iterations" % iters))
    for j in jobs:
        j["nwork"] = nwork
    results = None
    if nwork > 1:
        from concurrent.futures import ProcessPoolExecutor
        for var in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS"):
            os.environ[var] = "1"            # inherited by the worker processes
        try:
            with ProcessPoolExecutor(max_workers=nwork) as ex:
                results = list(ex.map(segment_job, jobs))
        except Exception as e:              # e.g. BrokenProcessPool on a locked-down machine
            rep.log("worker processes failed (%s: %s) - falling back to one process" % (type(e).__name__, e))
            rep.set("workers", 1)
            for j in jobs:
                j["nwork"] = 1
            results = None
    if results is None:
        results = [segment_job(j) for j in jobs]
    results.sort(key=lambda r: r["si"])

    # assemble: segments are independent realizations -> equal-power crossfade
    out = np.zeros(Lw)
    for r in results:
        a0, b0 = segs[r["si"]]
        seg_out = r["out"]
        if r["si"] == 0 or O == 0:
            out[a0:b0] = seg_out
        else:
            th = np.linspace(0, np.pi / 2, O)
            out[a0:a0 + O] = out[a0:a0 + O] * np.cos(th) + seg_out[:O] * np.sin(th)
            out[a0 + O:b0] = seg_out[O:]

    hist, o0_rows, fail_msgs = [], [], []
    for r in results:
        hist.extend(r["hist"])
        for row in r["o0"]:
            if not o0_rows or row[0] > o0_rows[-1][0]:
                o0_rows.append(row)
        if r["fail"]:
            fail_msgs.append(r["fail"])
    wts = np.array([(segs[r["si"]][1] - segs[r["si"]][0]) / Lw for r in results])
    avg = lambda k: sum(wt * r[k] for wt, r in zip(wts, results))
    prof_src, prof_tgt, prof_out = avg("ps"), avg("pt"), avg("po")
    s1_src, s1_tgt, s1_out = avg("q_s"), avg("q_t"), avg("q_o")
    applied = results[0]["applied"]
    loss_start = [r["loss_start"] for r in results]
    loss_end = [r["loss_end"] for r in results]
    rep.set("loss_direct", float(np.mean([r["loss_direct"] for r in results])))
    rep.set("segment_seconds_total", float(sum(r["seconds"] for r in results)))

    for i, s in enumerate(applied):
        rep.set("op_%d" % (i + 1), s)
    rep.set("n_ops", len(applied))
    rep.set("loss_start", float(np.mean(loss_start)))
    rep.set("loss_end", float(np.mean(loss_end)))
    last_by = {}
    for (si, i, l0, l1, l2) in hist:
        last_by[si] = (l0, l1, l2)
    fin = np.mean(np.array(list(last_by.values())), axis=0)
    first = np.mean(np.array([h[2:] for h in hist if h[1] == 0]), axis=0)
    rep.set("final_l0", float(fin[0]))
    rep.set("final_l1", float(fin[1]))
    rep.set("final_l2", float(fin[2]))
    rep.set("init_l0", float(first[0]))
    rep.set("init_l1", float(first[1]))
    rep.set("init_l2", float(first[2]))
    reduction = 1 - np.mean(loss_end) / max(np.mean(loss_start), 1e-12)
    rep.set("loss_reduction_pct", 100 * float(reduction))
    warn = "; ".join(fail_msgs)
    if reduction < 0.3:
        warn = (warn + "; " if warn else "") + "weak convergence (loss fell only %.0f%%)" % (100 * reduction)
    try:
        import kymatio
        kv = str(getattr(kymatio, "__version__", "?"))
    except Exception:
        kv = "?"
    rep.set("kymatio_version", kv)
    if not kv.startswith("0.3"):
        warn = (warn + "; " if warn else "") + ("kymatio %s is untested (built against 0.3.0; "
                "the engine uses its internal filter_bank module)" % kv)
    rep.set("warning", warn if warn else "none")

    # back to the source rate, exact length, level
    y = out * scale_g
    if fr is not None:
        y = resample_poly(y, fr.denominator, fr.numerator)
        rep.set("band_limit_hz", sr_w / 2)
    else:
        rep.set("band_limit_hz", sr_src / 2)
    if len(y) < n_src:
        y = np.concatenate([y, np.zeros(n_src - len(y))])
    y = y[:n_src]
    y = y - y.mean()
    yr = float(np.sqrt(np.mean(y ** 2)))
    if yr > 0:
        y *= src_rms / yr                      # match source RMS
    pk = float(np.max(np.abs(y)))
    lim = 0.0
    if pk > 0.98:                              # attenuate only, never boost
        lim = 20 * math.log10(0.98 / pk)
        y *= 0.98 / pk
    rep.set("peak_limit_db", lim)
    rep.set("output_peak", float(np.max(np.abs(y))))
    rep.set("output_rms", float(np.sqrt(np.mean(y ** 2))))
    if not np.all(np.isfinite(y)):
        raise FloatingPointError("output contains non-finite samples")
    wavfile.write(a.out, int(sr_src), y.astype(np.float32))
    rep.set("output_samples", len(y))

    # figure data for Praat (plain whitespace matrices)
    wd = a.workdir
    n1f = sc.xi1 * sr_w
    np.savetxt(os.path.join(wd, "order1_profile.txt"),
               np.column_stack([n1f, s1_src, s1_tgt, s1_out]), fmt="%.6g")
    np.savetxt(os.path.join(wd, "order2_paths.txt"),
               np.column_stack([sc.xi1[sc.path_n1] * sr_w, sc.xi2[sc.path_n2] * sr_w,
                                prof_src, prof_tgt, prof_out]), fmt="%.6g")
    np.savetxt(os.path.join(wd, "order0_series.txt"), np.array(o0_rows), fmt="%.6g")
    # modulation-rate profile: mean normalized order 2 per rate filter (carriers >= 40 Hz)
    car_hz = sc.xi1[sc.path_n1] * sr_w
    rows = []
    for n2 in np.unique(sc.path_n2):
        m = (sc.path_n2 == n2) & (car_hz >= 40.0)
        if m.any():
            rows.append((sc.xi2[n2] * sr_w, prof_src[m].mean(), prof_tgt[m].mean(), prof_out[m].mean()))
    rows.sort()
    np.savetxt(os.path.join(wd, "order2_rate_profile.txt"), np.array(rows), fmt="%.6g")
    H = np.array(hist)
    np.savetxt(os.path.join(wd, "loss_history.txt"), H, fmt="%.6g")
    # coarse grids for the modulation map: carrier octave x rate octave
    grids = modulation_grids(sc, sr_w, prof_src, prof_tgt, prof_out)
    for name, G in grids.items():
        np.savetxt(os.path.join(wd, "mod_%s.txt" % name), np.nan_to_num(G, nan=-999.0), fmt="%.4f")
    rep.set("grid_rows", grids["src"].shape[0])
    rep.set("grid_cols", grids["src"].shape[1])


def modulation_grids(sc, sr, ps, pt, po, n_car=8, n_rate=7):
    """Average normalized order-2 dB into n_car carrier-octave rows x n_rate rate columns."""
    import numpy as np
    keep = sc.xi1[sc.path_n1] * sr >= 40.0      # carriers below 40 Hz carry no texture
    if keep.sum() < 4:
        keep[:] = True
    ps, pt, po = ps[keep], pt[keep], po[keep]
    cf = np.log2(np.maximum(sc.xi1[sc.path_n1][keep] * sr, 1e-6))
    rf = np.log2(np.maximum(sc.xi2[sc.path_n2][keep] * sr, 1e-6))
    c_lo, c_hi = cf.min(), cf.max() + 1e-9
    r_lo, r_hi = rf.min(), rf.max() + 1e-9
    ci = np.minimum(((cf - c_lo) / (c_hi - c_lo) * n_car).astype(int), n_car - 1)
    ri = np.minimum(((rf - r_lo) / (r_hi - r_lo) * n_rate).astype(int), n_rate - 1)
    out = {}
    for name, v in (("src", ps), ("tgt", pt), ("out", po)):
        G = np.full((n_car, n_rate), np.nan)
        for r in range(n_car):
            for c in range(n_rate):
                m = (ci == r) & (ri == c)
                if m.any():
                    G[r, c] = v[m].mean()
        out[name] = G
    axes = np.array([[2 ** c_lo, 2 ** c_hi, 2 ** r_lo, 2 ** r_hi]])
    out["axes"] = axes
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="inp")
    ap.add_argument("--out")
    ap.add_argument("--workdir")
    ap.add_argument("--preset", default="Custom")
    ap.add_argument("--scale", default="Medium")
    ap.add_argument("--detail", default="Medium")
    ap.add_argument("--w0", type=float, default=40)
    ap.add_argument("--w1", type=float, default=60)
    ap.add_argument("--w2", type=float, default=100)
    ap.add_argument("--transform", type=float, default=30)
    ap.add_argument("--randomness", type=float, default=50)
    ap.add_argument("--quality", default="Standard")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--iters", type=int, default=-1, help="override refinement iterations (testing)")
    ap.add_argument("--workers", type=int, default=0, help="worker processes (0 = automatic)")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--cleanup", nargs="+", default=None,
                    help="remove this run's folder, plus stale AudioTools_STG_* folders "
                         "(older than 10 min) next to it and in any extra folders given")
    a = ap.parse_args()

    if a.selftest:
        return selftest()
    if a.cleanup:
        return cleanup(a.cleanup)

    workdir = a.workdir or os.path.dirname(os.path.abspath(a.out))
    a.workdir = workdir
    rep = Report(workdir)
    missing = check_dependencies()
    if missing:
        rep.write("ERROR", "Missing Python package(s): %s. Install with: python -m pip install %s"
                  % (", ".join(missing), " ".join(missing)))
        return 2
    for key, table in (("preset", PRESETS), ("scale", SCALE_SECONDS),
                       ("detail", DETAIL_Q), ("quality", QUALITY)):
        if getattr(a, key) not in table:
            rep.write("ERROR", "unknown %s '%s'" % (key, getattr(a, key)))
            return 2
    try:
        import numpy as np
        np.seterr(all="ignore")
        run(a, rep)
        rep.log("done")
        rep.write("OK")
        return 0
    except MemoryError:
        rep.write("ERROR", "out of memory - use Preview quality or a shorter sound")
    except Exception as e:
        rep.log(traceback.format_exc())
        rep.write("ERROR", "%s: %s" % (type(e).__name__, e))
    if a.out and os.path.exists(a.out):
        try:
            os.remove(a.out)        # never leave a half-written WAV behind
        except OSError:
            pass
    return 1


def cleanup(paths):
    """Praat cannot delete folders; the frontend calls this at the end of every run."""
    import shutil
    import glob
    current = paths[0]
    shutil.rmtree(current, ignore_errors=True)
    parents = {os.path.dirname(os.path.normpath(current))} | set(paths[1:])
    now = time.time()
    for parent in parents:
        for d in glob.glob(os.path.join(parent, "AudioTools_STG_*")):
            try:
                if os.path.isdir(d) and now - os.path.getmtime(d) > 600:
                    shutil.rmtree(d, ignore_errors=True)
            except OSError:
                pass
    return 0


def selftest():
    """Forward vs Kymatio Scattering1D, and gradient vs finite differences."""
    import numpy as np
    # kymatio.numpy also imports the 3-D module, which breaks on SciPy >= 1.15
    # (scipy.special.sph_harm removed); import the 1-D frontend directly.
    from kymatio.scattering1d.frontend.numpy_frontend import ScatteringNumPy1D as Scattering1D
    rng = np.random.default_rng(0)
    J, Q, n = 6, (8, 1), 1500
    ref = Scattering1D(J=J, shape=n, Q=Q)
    x = rng.standard_normal(n)
    Sk = ref(x)
    N = ref._N_padded
    xp = np.pad(x, (ref.pad_left, ref.pad_right), mode="reflect")
    sc = Scattering(N, J, Q)
    S0, S1, S2, _ = sc.forward(xp)
    i0, i1 = ref.ind_start[J], ref.ind_end[J]
    mine = np.vstack([S1[:, i0:i1], S2[:, i0:i1]])
    theirs = Sk[1:]
    err = np.max(np.abs(mine - theirs)) / np.max(np.abs(theirs))
    print("forward orders 1+2 vs Kymatio: %d coeffs, max rel err %.2e" % (theirs.shape[0], err))
    # gradient
    sc2 = Scattering(1024, 5, (4, 1))
    x = rng.standard_normal(1024)
    tg = Target(sc2, *sc2.forward(x)[:3])
    tg.L1 += 0.3 * rng.standard_normal(tg.L1.shape)
    tg.L2n += 0.3 * rng.standard_normal(tg.L2n.shape)
    f, _ = make_loss(sc2, tg, np.array([0.4, 0.6, 1.0]))
    y = rng.standard_normal(1024)
    L, g = f(y)
    worst = 0
    for k in rng.choice(1024, 12, replace=False):
        h = 1e-6
        e = np.zeros(1024)
        e[k] = h
        fd = (f(y + e)[0] - f(y - e)[0]) / (2 * h)
        worst = max(worst, abs(fd - g[k]) / max(abs(fd), 1e-8))
    print("gradient vs finite differences: max rel err %.2e" % worst)
    return 0 if (err < 1e-6 and worst < 1e-4) else 1


if __name__ == "__main__":
    sys.exit(main())
