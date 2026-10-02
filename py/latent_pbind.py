#!/usr/bin/env python3
"""
latent_pbind.py — Latent Pbind engine (Praat AudioTools, Hybrid Systems)
Version 1.0.1 (2026)
Author: Shai Cohen, Department of Music, Bar-Ilan University
License: MIT  —  https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools

v1.0.1: ended-by report names the stream that actually ended the output;
        barycentric viz table carries the targeted amplitude coefficients
        sqrt(tpow) instead of pre-power weights; wording of Decoder/Pure,
        axis orientation and KL-active diagnostic made precise.

An algorithmic latent-space composition system in which independent
Pbind-style pattern streams generate a trajectory through a learned
acoustic space.

    Pbind expression ─► event streams (one clock per key, or the shared dur)
                     ─► continuous control trajectories (frame rate)
                     ─► normalised latent coordinates  (boundary + attraction)
                     ─► Decoder / Nearest event / Barycentric rendering
                     ─► STFT-domain resynthesis ─► WAV

Pipeline
    1. STFT of the mono input; 64 log-spaced power bands.
    2. Overlapping fixed-length patches (patch_ms, every analysis_hop_ms),
       silence-gated; each patch = 64 bands x 8 time cells (log dB).
    3. numpy beta-VAE (512 -> 256 -> d -> 256 -> 512, tanh), Adam, KL warm-up.
    4. Posterior means are PCA-rotated: z1 is the axis of largest spread in
       the encoded corpus, z2 the next, ... Each axis is sign-oriented so its
       correlation with spectral centroid is >= 0 (meaningful only where that
       correlation is clearly non-zero; the values are reported) and
       robustly scaled so that the 2nd..98th percentile range maps to -1..+1.
       Users therefore compose in normalised units without knowing the raw
       latent scale; a single outlier cannot define the range.
    5. k-means++ identity clusters in the normalised space, ordered along z1
       (cluster 0 = lowest z1).
    6. The Pbind expression is parsed by a small recursive-descent parser
       (nested patterns allowed) and evaluated into event streams. Every key
       draws from its own seeded RNG (seed + key name), so adding a key does
       not change the realisation of the others.
    7. Events are interpolated (step / linear / cubic / smooth) to frame-rate
       control curves; cluster centroid + excursion * (z1..zd) gives the raw
       coordinate; posterior jitter (temp), boundary handling, and attraction
       (attract) give the final coordinate.
    8. Rendering, all in one STFT output buffer:
         Decoder      latent spectral-envelope decoder (hybrid resynthesis,
                      not a waveform decoder): z(t) -> inverse PCA -> VAE
                      decode -> 64-band x 8-cell log magnitude. "source"
                      detail adds the nearest patch's fine structure; "pure"
                      uses the decoded magnitude only. In both, phase starts
                      from the source voice mix and is refined by Griffin-Lim.
         Nearest      complex STFT frames copied from the nearest patch.
         Barycentric  K nearest patches mixed with inverse-distance weights
                      (equal-power normalised linear complex mix).
       A read pointer (time since the last retrigger: retrig key, default
       every global event) advances at `rate`. Each selected source patch
       becomes a voice that enters at patch start + min(pointer, patch end)
       and then reads forward through the source while it stays selected;
       voice changes are equal-power crossfaded (crossfade_ms). In Decoder
       mode the decoded envelope follows the pointer through the 8 patch
       cells and holds the last cell once the pointer passes the patch.
    9. ISTFT, per-sample amp envelope, peak handling, WAV + visualisation
       tables + stats for the Praat front end.

Invocation (by LatentPbind.praat):
    python latent_pbind.py params.txt
params.txt holds key=value lines (see read_params). On any failure the
engine writes "ERROR <category>: <message>" to the status file and exits 1;
on success it writes "OK".

Dependencies: numpy, scipy (scipy.io.wavfile only). CPU only, no network,
no pretrained models, no PyTorch/TensorFlow.
"""

import sys
import os
import math
import zlib
import traceback

import numpy as np

VERSION = "1.0.1"
MAX_LATENT = 8
MAX_EVENTS = 100000
N_BANDS = 64
T_CELLS = 8


# ═══════════════════════════════════════════════════════════════════════════
# Errors
# ═══════════════════════════════════════════════════════════════════════════

class LPError(Exception):
    """User-facing error with a category tag reported in the Praat Info window."""

    def __init__(self, category, message):
        super().__init__(message)
        self.category = category
        self.message = message


# ═══════════════════════════════════════════════════════════════════════════
# Parameters and I/O
# ═══════════════════════════════════════════════════════════════════════════

DEFAULTS = {
    "input_wav": "", "pbind_file": "", "output_wav": "", "status_file": "",
    "stats_file": "", "events_csv": "", "traj_csv": "", "cloud_csv": "",
    "centres_csv": "", "onsets_csv": "",
    "output_duration": "0", "seed": "1",
    "render_mode": "decoder",          # decoder | nearest | barycentric
    "interp": "smooth",                # step | linear | cubic | smooth
    "boundary": "reflect",             # clamp | reflect | wrap | attract
    "excursion": "1.0",
    "latent_dims": "4", "patch_ms": "120", "analysis_hop_ms": "20",
    "epochs": "150", "beta": "0.5", "clusters": "6",
    "neighbours": "4", "crossfade_ms": "40", "gl_iterations": "12",
    "decoder_detail": "source",        # source | pure
    "normalise": "1",
}


def read_params(path):
    p = dict(DEFAULTS)
    try:
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.rstrip("\r\n")
                if not line.strip() or line.lstrip().startswith("#"):
                    continue
                if "=" not in line:
                    continue
                k, v = line.split("=", 1)
                p[k.strip()] = v.strip()
    except OSError as e:
        raise LPError("temp-file", f"cannot read parameter file {path}: {e}")
    return p


def pf(p, key, lo=None, hi=None):
    try:
        v = float(p[key])
    except (KeyError, ValueError):
        raise LPError("parameter", f"parameter {key!r} is not a number: {p.get(key)!r}")
    if not math.isfinite(v):
        raise LPError("parameter", f"parameter {key!r} is not finite")
    if lo is not None and v < lo:
        raise LPError("parameter", f"{key} must be >= {lo} (got {v})")
    if hi is not None and v > hi:
        raise LPError("parameter", f"{key} must be <= {hi} (got {v})")
    return v


def read_wav_mono(path):
    from scipy.io import wavfile
    try:
        sr, data = wavfile.read(path)
    except Exception as e:
        raise LPError("temp-file", f"cannot read input WAV {path}: {e}")
    data = np.asarray(data)
    if data.dtype == np.int16:
        x = data.astype(np.float64) / 32768.0
    elif data.dtype == np.int32:
        x = data.astype(np.float64) / 2147483648.0
    elif data.dtype == np.uint8:
        x = (data.astype(np.float64) - 128.0) / 128.0
    else:
        x = data.astype(np.float64)
    if x.ndim > 1:
        x = x.mean(axis=1)
    if not np.all(np.isfinite(x)):
        raise LPError("input", "input audio contains NaN/Inf samples")
    return int(sr), x


def write_wav(path, x, sr):
    from scipy.io import wavfile
    try:
        wavfile.write(path, int(sr), np.asarray(x, dtype=np.float32))
    except Exception as e:
        raise LPError("temp-file", f"cannot write output WAV {path}: {e}")


def write_csv(path, header, rows, fmt="{:.6g}"):
    if not path:
        return
    try:
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(",".join(header) + "\n")
            for r in rows:
                f.write(",".join(v if isinstance(v, str) else fmt.format(v) for v in r) + "\n")
    except OSError as e:
        raise LPError("temp-file", f"cannot write {path}: {e}")


def key_rng(seed, name):
    """Independent, reproducible RNG per pattern key (seed + key name)."""
    return np.random.default_rng([int(seed) & 0x7FFFFFFF, zlib.crc32(name.encode("utf-8"))])


# ═══════════════════════════════════════════════════════════════════════════
# STFT (own implementation so analysis, Griffin-Lim and synthesis agree)
# ═══════════════════════════════════════════════════════════════════════════

def _hann(n):
    return 0.5 - 0.5 * np.cos(2.0 * np.pi * np.arange(n) / n)


def stft(x, n_fft, hop):
    w = _hann(n_fft)
    pad = n_fft // 2
    xp = np.concatenate([np.zeros(pad), x, np.zeros(pad + n_fft)])
    n_frames = 1 + (len(x) + hop - 1) // hop
    idx = np.arange(n_fft)[None, :] + hop * np.arange(n_frames)[:, None]
    frames = xp[idx] * w[None, :]
    return np.fft.rfft(frames, axis=1).T          # [bins, frames]


def istft(X, n_fft, hop, length):
    w = _hann(n_fft)
    n_frames = X.shape[1]
    frames = np.fft.irfft(X.T, n=n_fft, axis=1) * w[None, :]
    total = n_fft + hop * (n_frames - 1)
    y = np.zeros(total)
    wsum = np.zeros(total)
    for i in range(n_frames):
        s = i * hop
        y[s:s + n_fft] += frames[i]
        wsum[s:s + n_fft] += w * w
    good = wsum > 1e-8
    y[good] /= wsum[good]
    pad = n_fft // 2
    y = y[pad:pad + length]
    if len(y) < length:
        y = np.concatenate([y, np.zeros(length - len(y))])
    return y


# ═══════════════════════════════════════════════════════════════════════════
# Band analysis
# ═══════════════════════════════════════════════════════════════════════════

def band_setup(sr, n_fft, n_bands=N_BANDS):
    n_bins = n_fft // 2 + 1
    freqs = np.arange(n_bins) * sr / n_fft
    fmin = 40.0
    fmax = min(16000.0, 0.95 * sr / 2.0)
    edges = np.geomspace(fmin, fmax, n_bands + 2)
    centres = edges[1:-1]
    fb = np.zeros((n_bands, n_bins))
    for b in range(n_bands):
        lo, c, hi = edges[b], edges[b + 1], edges[b + 2]
        up = (freqs - lo) / (c - lo)
        down = (hi - freqs) / (hi - c)
        fb[b] = np.clip(np.minimum(up, down), 0.0, None)
        if fb[b].sum() < 1e-9:                       # narrower than a bin
            fb[b, int(np.argmin(np.abs(freqs - c)))] = 1.0
        fb[b] /= fb[b].sum()
    # band dB -> bin dB: linear interpolation in log2(frequency)
    lc = np.log2(centres)
    lf = np.log2(np.maximum(freqs, 1.0))
    up_m = np.zeros((n_bins, n_bands))
    for k in range(n_bins):
        if lf[k] <= lc[0]:
            up_m[k, 0] = 1.0
        elif lf[k] >= lc[-1]:
            up_m[k, -1] = 1.0
        else:
            j = int(np.searchsorted(lc, lf[k])) - 1
            u = (lf[k] - lc[j]) / (lc[j + 1] - lc[j])
            up_m[k, j] = 1.0 - u
            up_m[k, j + 1] = u
    return fb, up_m, centres


def band_db(power, fb, floor_db):
    return np.maximum(10.0 * np.log10(fb @ power + 1e-20), floor_db)


def resample_cols(M, n_out):
    """Resample the columns of M [rows, P] to n_out columns (cell averages)."""
    P = M.shape[1]
    if P == n_out:
        return M.copy()
    if P < n_out:
        src = np.arange(P)
        dst = np.linspace(0, P - 1, n_out)
        return np.stack([np.interp(dst, src, r) for r in M])
    edges = np.linspace(0, P, n_out + 1)
    out = np.empty((M.shape[0], n_out))
    for j in range(n_out):
        a = int(math.floor(edges[j]))
        b = max(a + 1, int(math.floor(edges[j + 1])))
        out[:, j] = M[:, a:b].mean(axis=1)
    return out


# ═══════════════════════════════════════════════════════════════════════════
# numpy beta-VAE
# ═══════════════════════════════════════════════════════════════════════════

class NumpyVAE:
    def __init__(self, D, H, d, rng):
        def xavier(a, b):
            return rng.normal(0.0, math.sqrt(2.0 / (a + b)), size=(a, b))
        self.p = {
            "W1": xavier(D, H), "b1": np.zeros(H),
            "Wm": xavier(H, d), "bm": np.zeros(d),
            "Wv": xavier(H, d) * 0.1, "bv": np.full(d, -2.0),
            "W3": xavier(d, H), "b3": np.zeros(H),
            "W4": xavier(H, D), "b4": np.zeros(D),
        }
        self.m = {k: np.zeros_like(v) for k, v in self.p.items()}
        self.v = {k: np.zeros_like(v) for k, v in self.p.items()}
        self.t = 0

    def encode(self, X):
        h1 = np.tanh(X @ self.p["W1"] + self.p["b1"])
        mu = h1 @ self.p["Wm"] + self.p["bm"]
        lv = np.clip(h1 @ self.p["Wv"] + self.p["bv"], -10.0, 6.0)
        return mu, lv, h1

    def decode(self, Z):
        h2 = np.tanh(Z @ self.p["W3"] + self.p["b3"])
        return h2 @ self.p["W4"] + self.p["b4"], h2

    def loss_and_grads(self, X, eps, beta):
        n = X.shape[0]
        P = self.p
        mu, lv, h1 = self.encode(X)
        std = np.exp(0.5 * lv)
        z = mu + std * eps
        xh, h2 = self.decode(z)
        diff = xh - X
        rec = 0.5 * np.sum(diff * diff) / n
        kl_terms = -0.5 * (1.0 + lv - mu * mu - np.exp(lv))
        kl = np.sum(kl_terms) / n
        g = {}
        dxh = diff / n
        g["W4"] = h2.T @ dxh
        g["b4"] = dxh.sum(0)
        da2 = (dxh @ P["W4"].T) * (1.0 - h2 * h2)
        g["W3"] = z.T @ da2
        g["b3"] = da2.sum(0)
        dz = da2 @ P["W3"].T
        dmu = dz + beta * mu / n
        dlv = dz * eps * 0.5 * std + beta * 0.5 * (np.exp(lv) - 1.0) / n
        g["Wm"] = h1.T @ dmu
        g["bm"] = dmu.sum(0)
        g["Wv"] = h1.T @ dlv
        g["bv"] = dlv.sum(0)
        da1 = (dmu @ P["Wm"].T + dlv @ P["Wv"].T) * (1.0 - h1 * h1)
        g["W1"] = X.T @ da1
        g["b1"] = da1.sum(0)
        return rec, kl, kl_terms.sum(0) / n, g

    def adam(self, g, lr, b1=0.9, b2=0.999, eps=1e-8, clip=5.0):
        self.t += 1
        gnorm = math.sqrt(sum(float(np.sum(v * v)) for v in g.values()))
        scale = clip / gnorm if gnorm > clip else 1.0
        c1 = lr / (1 - b1 ** self.t)
        c2 = 1.0 / (1 - b2 ** self.t)
        for k in self.p:
            gk = g[k] * scale if scale != 1.0 else g[k]
            m, v = self.m[k], self.v[k]
            m *= b1
            m += (1 - b1) * gk
            v *= b2
            v += (1 - b2) * (gk * gk)
            den = np.sqrt(v * c2)
            den += eps
            self.p[k] -= c1 * m / den


def train_vae(X, d, epochs, beta, rng, log):
    N, D = X.shape
    model = NumpyVAE(D, 256, d, rng)
    batch = min(64, N)
    warm = max(1, int(0.3 * epochs))
    hist = []
    rec = kl = 0.0
    kl_dim = np.zeros(d)
    for ep in range(epochs):
        b_eff = beta * min(1.0, (ep + 1) / warm)
        perm = rng.permutation(N)
        er = ek = 0.0
        ekd = np.zeros(d)
        nb = 0
        for s in range(0, N, batch):
            idx = perm[s:s + batch]
            eps = rng.standard_normal((len(idx), d))
            rec, kl, kld, g = model.loss_and_grads(X[idx], eps, b_eff)
            if not (math.isfinite(rec) and math.isfinite(kl)):
                raise LPError("training", f"VAE loss became non-finite at epoch {ep + 1}")
            model.adam(g, 1e-3)
            er += rec
            ek += kl
            ekd += kld
            nb += 1
        hist.append((er / nb, ek / nb))
        kl_dim = ekd / nb
        if (ep + 1) % max(1, epochs // 5) == 0:
            log(f"    epoch {ep + 1:4d}/{epochs}  rec/dim {er / nb / D:.4f}  KL {ek / nb:.3f}")
    return model, hist, kl_dim


# ═══════════════════════════════════════════════════════════════════════════
# k-means++
# ═══════════════════════════════════════════════════════════════════════════

def kmeans(C, k, rng, iters=60):
    N = C.shape[0]
    cent = [C[rng.integers(N)]]
    for _ in range(1, k):
        d2 = np.min(((C[:, None, :] - np.array(cent)[None]) ** 2).sum(-1), axis=1)
        tot = d2.sum()
        cent.append(C[rng.integers(N)] if tot <= 0 else C[rng.choice(N, p=d2 / tot)])
    cent = np.array(cent)
    lab = np.zeros(N, dtype=int)
    for _ in range(iters):
        lab = np.argmin(((C[:, None, :] - cent[None]) ** 2).sum(-1), axis=1)
        new = np.array([C[lab == j].mean(0) if np.any(lab == j) else cent[j] for j in range(k)])
        if np.allclose(new, cent):
            break
        cent = new
    order = np.argsort(cent[:, 0])                 # cluster 0 = lowest z1
    remap = np.empty(k, dtype=int)
    remap[order] = np.arange(k)
    return cent[order], remap[lab]


# ═══════════════════════════════════════════════════════════════════════════
# Pattern language — tokenizer and recursive-descent parser
# ═══════════════════════════════════════════════════════════════════════════

EXAMPLE = "Pbind(dur=Pseq([0.25,0.5,0.25,1],inf), z1=Pwhite(-1,1,inf), z2=Pwalk([-1,-0.5,0,0.5,1],1), interp=smooth)"

PATTERN_HELP = ("Pseq Pser Prand Pxrand Pshuf Pwrand Pwhite Pexprand Pbrown Pwalk "
                "Pseries Pgeom Pstutter Pn Plag Phold Pimpulse Plogistic")

INTERP_NAMES = ("step", "linear", "cubic", "smooth")


class Tok:
    def __init__(self, kind, val, pos):
        self.kind, self.val, self.pos = kind, val, pos


def tokenize(src):
    toks = []
    i, n = 0, len(src)
    while i < n:
        ch = src[i]
        if ch.isspace():
            i += 1
            continue
        if ch == "#":                                # comment to end of line
            while i < n and src[i] != "\n":
                i += 1
            continue
        if ch in "()[],=":
            toks.append(Tok(ch, ch, i))
            i += 1
            continue
        if ch == "\\":
            j = i + 1
            while j < n and (src[j].isalnum() or src[j] == "_"):
                j += 1
            if j == i + 1:
                raise LPError("syntax", f"lone backslash at position {i}")
            toks.append(Tok("sym", src[i + 1:j], i))
            i = j
            continue
        if ch.isdigit() or ch == "." or (ch in "+-" and i + 1 < n and (src[i + 1].isdigit() or src[i + 1] == ".")):
            j = i + 1
            while j < n and (src[j].isdigit() or src[j] in ".eE" or
                             (src[j] in "+-" and src[j - 1] in "eE")):
                j += 1
            try:
                toks.append(Tok("num", float(src[i:j]), i))
            except ValueError:
                raise LPError("syntax", f"bad number {src[i:j]!r} at position {i}")
            i = j
            continue
        if ch.isalpha() or ch == "_":
            j = i + 1
            while j < n and (src[j].isalnum() or src[j] == "_"):
                j += 1
            word = src[i:j]
            toks.append(Tok("num", math.inf, i) if word == "inf" else Tok("id", word, i))
            i = j
            continue
        raise LPError("syntax", f"unexpected character {ch!r} at position {i}")
    toks.append(Tok("end", None, n))
    return toks


class Parser:
    def __init__(self, src):
        self.toks = tokenize(src)
        self.i = 0

    def peek(self):
        return self.toks[self.i]

    def take(self, kind=None):
        t = self.toks[self.i]
        if kind is not None and t.kind != kind:
            want = {"(": "'('", ")": "')'", "]": "']'", ",": "','", "=": "'='",
                    "id": "a name", "num": "a number"}.get(kind, kind)
            got = t.val if t.kind != "end" else "end of expression"
            raise LPError("syntax", f"expected {want} at position {t.pos}, found {got!r}")
        self.i += 1
        return t

    def expr(self):
        t = self.peek()
        if t.kind == "num":
            self.take()
            return ("num", t.val)
        if t.kind == "sym":
            self.take()
            return ("sym", t.val)
        if t.kind == "[":
            self.take()
            items = []
            if self.peek().kind != "]":
                items.append(self.expr())
                while self.peek().kind == ",":
                    self.take()
                    items.append(self.expr())
            self.take("]")
            return ("list", items)
        if t.kind == "id":
            self.take()
            if self.peek().kind == "(":
                self.take()
                args = []
                if self.peek().kind != ")":
                    args.append(self.expr())
                    while self.peek().kind == ",":
                        self.take()
                        args.append(self.expr())
                self.take(")")
                return ("call", t.val, args, t.pos)
            return ("sym", t.val)                     # bare word, e.g. cubic
        got = t.val if t.kind != "end" else "end of expression"
        raise LPError("syntax", f"expected a value or pattern at position {t.pos}, found {got!r}")

    def pbind(self):
        head = self.take("id")
        if head.val != "Pbind":
            raise LPError("syntax", f"expression must start with Pbind(, found {head.val!r}.\nExample: {EXAMPLE}")
        self.take("(")
        pairs = []
        if self.peek().kind == "sym":                 # SuperCollider style: \key, value, ...
            while True:
                k = self.take("sym").val
                self.take(",")
                pairs.append((k, self.expr()))
                if self.peek().kind == ",":
                    self.take()
                    if self.peek().kind == ")":
                        break
                    continue
                break
        else:                                         # keyword style: key=value, ...
            while self.peek().kind != ")":
                k = self.take("id").val
                self.take("=")
                pairs.append((k, self.expr()))
                if self.peek().kind == ",":
                    self.take()
                else:
                    break
        self.take(")")
        if self.peek().kind != "end":
            raise LPError("syntax", f"unexpected text after Pbind(...) at position {self.peek().pos}")
        return pairs


# ═══════════════════════════════════════════════════════════════════════════
# Pattern streams
# ═══════════════════════════════════════════════════════════════════════════

def _count(node, what):
    if node[0] != "num":
        raise LPError("syntax", f"{what} must be a number or inf")
    v = node[1]
    if v == math.inf:
        return math.inf
    if v < 0 or v != int(v):
        raise LPError("syntax", f"{what} must be a non-negative integer or inf (got {v})")
    return int(v)


def _expect_list(node, name):
    if node[0] != "list":
        raise LPError("syntax", f"{name}: first argument must be a list [...]")
    if not node[1]:
        raise LPError("syntax", f"{name}: list must not be empty")
    return node[1]


def _arity(name, args, lo, hi):
    if not (lo <= len(args) <= hi):
        rng = f"{lo}" if lo == hi else f"{lo}-{hi}"
        raise LPError("syntax", f"{name} takes {rng} arguments, got {len(args)}")


class _Exhausted(Exception):
    """A nested stream ran out (PEP 479 forbids letting StopIteration escape a generator)."""


def _pull(it):
    try:
        return next(it)
    except StopIteration:
        raise _Exhausted()


def _guarded(gen):
    try:
        yield from gen
    except _Exhausted:
        return


def _val_source(node, rng):
    """A numeric argument: constant, or a pattern sampled once per use."""
    if node[0] == "num":
        v = node[1]
        return lambda: v
    if node[0] in ("call", "list"):
        it = stream(node, rng)
        return lambda: _pull(it)
    raise LPError("syntax", f"symbol \\{node[1]} cannot be used as a number")


def _embed(item, rng):
    """List element: a number yields once, a pattern embeds its whole stream."""
    if item[0] == "num":
        yield item[1]
    elif item[0] in ("call", "list"):
        yield from stream(item, rng)
    else:
        raise LPError("syntax", f"symbol \\{item[1]} cannot appear in a value list")


def _repeat(n):
    k = 0
    while k < n:
        yield k
        k += 1


def stream(node, rng):
    return _guarded(_stream(node, rng))


def _stream(node, rng):
    kind = node[0]
    if kind == "num":
        v = node[1]

        def const():
            while True:
                yield v
        return const()
    if kind == "list":                                 # bare list = Pseq(list, 1)
        return stream(("call", "Pseq", [node, ("num", 1.0)], 0), rng)
    if kind == "sym":
        raise LPError("syntax", f"symbol \\{node[1]} is not a pattern")
    _, name, args, pos = node

    if name == "Pseq":
        _arity(name, args, 1, 3)
        items = _expect_list(args[0], name)
        reps = _count(args[1], "Pseq repeats") if len(args) > 1 else 1
        off = int(args[2][1]) if len(args) > 2 and args[2][0] == "num" else 0

        def g():
            for _ in _repeat(reps):
                for j in range(len(items)):
                    yield from _embed(items[(j + off) % len(items)], rng)
        return g()

    if name == "Pser":
        _arity(name, args, 2, 2)
        items = _expect_list(args[0], name)
        cnt = _count(args[1], "Pser count")

        def g():
            j = 0
            for _ in _repeat(cnt):
                yield _pull(_embed(items[j % len(items)], rng))
                j += 1
        return g()

    if name in ("Prand", "Pxrand"):
        _arity(name, args, 1, 2)
        items = _expect_list(args[0], name)
        cnt = _count(args[1], f"{name} count") if len(args) > 1 else 1

        def g():
            last = -1
            for _ in _repeat(cnt):
                if name == "Pxrand" and len(items) > 1:
                    j = int(rng.integers(len(items) - 1))
                    if j >= last >= 0:
                        j += 1
                else:
                    j = int(rng.integers(len(items)))
                last = j
                yield from _embed(items[j], rng)
        return g()

    if name == "Pshuf":
        _arity(name, args, 1, 2)
        items = _expect_list(args[0], name)
        reps = _count(args[1], "Pshuf repeats") if len(args) > 1 else 1
        order = list(rng.permutation(len(items)))     # shuffled once, then repeated

        def g():
            for _ in _repeat(reps):
                for j in order:
                    yield from _embed(items[j], rng)
        return g()

    if name == "Pwrand":
        _arity(name, args, 2, 3)
        items = _expect_list(args[0], name)
        if args[1][0] != "list" or any(w[0] != "num" for w in args[1][1]):
            raise LPError("syntax", "Pwrand: second argument must be a list of numeric weights")
        w = np.array([x[1] for x in args[1][1]], dtype=float)
        if len(w) != len(items):
            raise LPError("syntax", f"Pwrand: {len(items)} values but {len(w)} weights")
        if np.any(w < 0) or w.sum() <= 0:
            raise LPError("syntax", "Pwrand: weights must be >= 0 and sum to > 0")
        w = w / w.sum()
        cnt = _count(args[2], "Pwrand count") if len(args) > 2 else 1

        def g():
            for _ in _repeat(cnt):
                yield from _embed(items[int(rng.choice(len(items), p=w))], rng)
        return g()

    if name in ("Pwhite", "Pexprand"):
        _arity(name, args, 0, 3)
        lo = _val_source(args[0], rng) if len(args) > 0 else (lambda: 0.0 if name == "Pwhite" else 0.01)
        hi = _val_source(args[1], rng) if len(args) > 1 else (lambda: 1.0)
        cnt = _count(args[2], f"{name} count") if len(args) > 2 else math.inf

        def g():
            for _ in _repeat(cnt):
                a, b = lo(), hi()
                if name == "Pwhite":
                    yield a + (b - a) * rng.random()
                else:
                    if a <= 0 or b <= 0:
                        raise LPError("pattern", f"Pexprand bounds must be > 0 (got {a}, {b})")
                    yield math.exp(math.log(a) + (math.log(b) - math.log(a)) * rng.random())
        return g()

    if name == "Pbrown":
        _arity(name, args, 3, 4)
        lo, hi, st = (_val_source(a, rng) for a in args[:3])
        cnt = _count(args[3], "Pbrown count") if len(args) > 3 else math.inf

        def g():
            a, b = lo(), hi()
            cur = a + (b - a) * rng.random()
            first = True
            for _ in _repeat(cnt):
                a, b, s = lo(), hi(), st()
                if not first:
                    cur += s * (2.0 * rng.random() - 1.0)
                first = False
                span = b - a
                if span > 0:                           # reflect into [a, b]
                    x = (cur - a) % (2 * span)
                    cur = a + (x if x <= span else 2 * span - x)
                else:
                    cur = a
                yield cur
        return g()

    if name == "Pwalk":
        _arity(name, args, 2, 4)
        items = _expect_list(args[0], name)
        if any(it[0] != "num" for it in items):
            raise LPError("syntax", "Pwalk: list elements must be numbers")
        vals = [it[1] for it in items]
        step = _val_source(args[1], rng)
        dirn = _val_source(args[2], rng) if len(args) > 2 else (lambda: 1.0)
        start = int(args[3][1]) if len(args) > 3 and args[3][0] == "num" else 0

        def g():
            n = len(vals)
            j = start % n
            sign = 1
            while True:
                yield vals[j]
                nj = j + sign * int(round(step()))
                if dirn() < 0:                         # bounce at the ends
                    while nj < 0 or nj >= n:
                        sign = -sign
                        nj = -nj if nj < 0 else 2 * (n - 1) - nj
                    j = max(0, min(n - 1, nj))
                else:                                  # wrap around
                    j = nj % n
        return g()

    if name in ("Pseries", "Pgeom"):
        _arity(name, args, 2, 3)
        start = _val_source(args[0], rng)
        inc = _val_source(args[1], rng)
        cnt = _count(args[2], f"{name} length") if len(args) > 2 else math.inf

        def g():
            cur = start()
            for _ in _repeat(cnt):
                yield cur
                cur = cur + inc() if name == "Pseries" else cur * inc()
        return g()

    if name == "Pstutter":
        _arity(name, args, 2, 2)
        # library order Pstutter(pattern, n); SC order Pstutter(n, pattern) also accepted
        if args[0][0] == "num" and args[1][0] in ("call", "list"):
            nsrc, inner = _val_source(args[0], rng), args[1]
        else:
            inner, nsrc = args[0], _val_source(args[1], rng)
        it = stream(inner, rng)

        def g():
            for v in it:
                k = int(round(nsrc()))
                if k < 0:
                    raise LPError("pattern", "Pstutter count must be >= 0")
                for _ in range(k):
                    yield v
        return g()

    if name == "Pn":
        _arity(name, args, 1, 2)
        reps = _count(args[1], "Pn repeats") if len(args) > 1 else math.inf

        def g():
            for _ in _repeat(reps):
                got = False
                for v in stream(args[0], rng):
                    got = True
                    yield v
                if not got:
                    return
        return g()

    if name == "Plag":
        _arity(name, args, 2, 2)
        it = stream(args[0], rng)
        coef = _val_source(args[1], rng)

        def g():
            y = None
            for v in it:
                c = min(max(coef(), 0.0), 0.999)
                y = v if y is None else c * y + (1.0 - c) * v
                yield y
        return g()

    if name == "Phold":
        _arity(name, args, 2, 2)
        it = stream(args[0], rng)
        prob = _val_source(args[1], rng)

        def g():
            cur = _pull(it)
            yield cur
            while True:
                if rng.random() < prob():
                    cur = _pull(it)
                yield cur
        return g()

    if name == "Pimpulse":
        _arity(name, args, 1, 4)
        prob = _val_source(args[0], rng)
        lo = _val_source(args[1], rng) if len(args) > 1 else (lambda: -1.0)
        hi = _val_source(args[2], rng) if len(args) > 2 else (lambda: 1.0)
        rest = _val_source(args[3], rng) if len(args) > 3 else (lambda: 0.0)

        def g():
            while True:
                a, b = lo(), hi()
                yield a + (b - a) * rng.random() if rng.random() < prob() else rest()
        return g()

    if name == "Plogistic":
        _arity(name, args, 1, 4)
        r = _val_source(args[0], rng)
        x0 = args[1][1] if len(args) > 1 and args[1][0] == "num" else 0.3
        lo = _val_source(args[2], rng) if len(args) > 2 else (lambda: -1.0)
        hi = _val_source(args[3], rng) if len(args) > 3 else (lambda: 1.0)

        def g():
            x = min(max(x0, 1e-6), 1 - 1e-6)
            while True:
                a, b = lo(), hi()
                yield a + (b - a) * x
                x = min(max(r(), 0.0), 4.0) * x * (1.0 - x)
                if x <= 0.0 or x >= 1.0:
                    x = 0.5 + 1e-3 * rng.standard_normal()
        return g()

    raise LPError("pattern", f"unsupported pattern {name!r} at position {pos}.\nSupported: {PATTERN_HELP}")


# ═══════════════════════════════════════════════════════════════════════════
# Pbind -> event streams
# ═══════════════════════════════════════════════════════════════════════════

AUX_KEYS = {"amp": 1.0, "temp": 0.0, "attract": 0.0, "rate": 1.0, "retrig": 1.0}


def analyse_pbind(text, latent_dims, default_interp):
    pairs = Parser(text).pbind()
    pats, durs, interps = {}, {}, {}
    g_interp = default_interp
    seen = set()
    for k, node in pairs:
        if k in seen:
            raise LPError("syntax", f"key {k!r} is given twice")
        seen.add(k)
        if k == "interp" or k.startswith("interp_"):
            if node[0] != "sym" or node[1] not in INTERP_NAMES:
                raise LPError("syntax", f"{k} must be one of {', '.join(INTERP_NAMES)}")
            if k == "interp":
                g_interp = node[1]
            else:
                interps[k[7:]] = node[1]
            continue
        if node[0] == "sym":
            raise LPError("syntax", f"key {k!r}: symbol \\{node[1]} is not a pattern")
        if k == "dur":
            pats["dur"] = node
        elif k.startswith("dur_"):
            durs[k[4:]] = node
        else:
            pats[k] = node
    if "dur" not in pats:
        raise LPError("syntax", "Pbind needs a dur key (the event clock).\nExample: " + EXAMPLE)
    valid = {f"z{i}" for i in range(1, 17)} | set(AUX_KEYS) | {"cluster"}
    for k in list(pats) + list(durs) + list(interps):
        if k == "dur":
            continue
        if k not in valid:
            raise LPError("syntax", f"unknown key {k!r}. Keys: dur, z1..z{latent_dims}, cluster, "
                                    "amp, temp, attract, rate, retrig, interp, dur_<key>, interp_<key>")
        if k[0] == "z" and k[1:].isdigit() and int(k[1:]) > latent_dims:
            raise LPError("dimension", f"{k} addresses a latent dimension the model does not have "
                                       f"(Latent dimensions = {latent_dims})")
    def validate(node, where):
        if node[0] == "list":
            for it in node[1]:
                validate(it, where)
        elif node[0] == "call":
            try:
                g = stream(node, np.random.default_rng(0))
                next(g, None)
            except LPError as e:
                raise LPError(e.category, f"in {where}: {e.message}")
            for a in node[2]:
                validate(a, where)
    for k, node in list(pats.items()) + [("dur_" + k, v) for k, v in durs.items()]:
        validate(node, k)
    for k in list(durs) + list(interps):
        if k not in pats:
            raise LPError("syntax", f"dur_{k} / interp_{k} given but no pattern for {k}")
    if not any(k.startswith("z") or k == "cluster" for k in pats):
        raise LPError("syntax", "Pbind needs at least one latent key (z1.. or cluster)")
    return pats, durs, interps, g_interp


def run_clock(dur_node, rng, t_end, label):
    """Event onsets from a duration pattern. Returns onsets, ended_early, end_time."""
    it = stream(dur_node, rng)
    on = []
    t = 0.0
    while t < t_end:
        try:
            d = float(next(it))
        except StopIteration:
            return np.array(on), True, t
        if not math.isfinite(d) or d <= 0:
            raise LPError("pattern", f"{label} produced a non-positive or non-finite duration ({d})")
        on.append(t)
        t += d
        if len(on) > MAX_EVENTS:
            raise LPError("pattern", f"{label} produced more than {MAX_EVENTS} events — durations too short")
    return np.array(on), False, t


def draw_values(node, rng, n):
    it = stream(node, rng)
    vals = []
    for _ in range(n):
        try:
            v = float(next(it))
        except StopIteration:
            break
        if not math.isfinite(v):
            raise LPError("pattern", "a pattern produced a non-finite value")
        vals.append(v)
    return np.array(vals)


def interpolate(on, vals, t, mode):
    """Event values (at onsets) -> curve sampled at t. Holds after the last event."""
    if len(vals) == 0:
        return np.zeros_like(t)
    if len(vals) == 1:
        return np.full_like(t, vals[0])
    i = np.clip(np.searchsorted(on, t, side="right") - 1, 0, len(on) - 1)
    if mode == "step":
        return vals[i]
    j = np.minimum(i + 1, len(on) - 1)
    span = np.where(j > i, on[j] - on[i], 1.0)
    u = np.clip((t - on[i]) / span, 0.0, 1.0)
    u = np.where(j > i, u, 0.0)
    v0, v1 = vals[i], vals[j]
    if mode == "linear":
        return v0 + (v1 - v0) * u
    if mode == "smooth":
        s = u * u * (3.0 - 2.0 * u)
        return v0 + (v1 - v0) * s
    # cubic Hermite with non-uniform finite-difference tangents (curves, may overshoot)
    sl = np.diff(vals) / np.maximum(np.diff(on), 1e-9)
    m = np.empty(len(vals))
    m[0], m[-1] = sl[0], sl[-1]
    m[1:-1] = 0.5 * (sl[:-1] + sl[1:])
    h = span
    u2, u3 = u * u, u * u * u
    return ((2 * u3 - 3 * u2 + 1) * v0 + (u3 - 2 * u2 + u) * h * m[i] +
            (-2 * u3 + 3 * u2) * v1 + (u3 - u2) * h * m[j])


# ═══════════════════════════════════════════════════════════════════════════
# Boundary handling (normalised coordinates, data box = [-1, +1])
# ═══════════════════════════════════════════════════════════════════════════

def apply_box(C, mode):
    if mode == "clamp":
        return np.clip(C, -1.0, 1.0)
    if mode == "reflect":
        x = np.mod(C + 1.0, 4.0)
        return np.where(x <= 2.0, x, 4.0 - x) - 1.0
    if mode == "wrap":
        return np.mod(C + 1.0, 2.0) - 1.0
    return C


def nearest(Cq, Cd, k=1, chunk=2048):
    """k nearest data rows for each query row. Returns (idx [n,k], dist [n,k])."""
    n = Cq.shape[0]
    idx = np.zeros((n, k), dtype=int)
    dist = np.zeros((n, k))
    dd = (Cd * Cd).sum(1)
    for s in range(0, n, chunk):
        q = Cq[s:s + chunk]
        d2 = np.maximum((q * q).sum(1)[:, None] - 2 * q @ Cd.T + dd[None], 0.0)
        if k == 1:
            j = np.argmin(d2, 1)[:, None]
        else:
            j = np.argpartition(d2, k - 1, axis=1)[:, :k]
            o = np.argsort(np.take_along_axis(d2, j, 1), axis=1)
            j = np.take_along_axis(j, o, 1)
        idx[s:s + chunk] = j
        dist[s:s + chunk] = np.sqrt(np.take_along_axis(d2, j, 1))
    return idx, dist


# ═══════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════

def run(p, log):
    seed_req = int(round(pf(p, "seed")))
    seed = seed_req if seed_req != 0 else int(np.random.SeedSequence().entropy % 2147483646) + 1
    render = p["render_mode"]
    if render not in ("decoder", "nearest", "barycentric"):
        raise LPError("parameter", f"unknown render_mode {render!r}")
    boundary = p["boundary"]
    if boundary not in ("clamp", "reflect", "wrap", "attract"):
        raise LPError("parameter", f"unknown boundary {boundary!r}")
    if p["interp"] not in INTERP_NAMES:
        raise LPError("parameter", f"unknown interp {p['interp']!r}")
    d = int(pf(p, "latent_dims", 2, MAX_LATENT))
    patch_ms = pf(p, "patch_ms", 30, 1000)
    ahop_ms = pf(p, "analysis_hop_ms", 5, 1000)
    epochs = int(pf(p, "epochs", 10, 2000))
    beta = pf(p, "beta", 0.0, 50.0)
    n_clusters = int(pf(p, "clusters", 2, 32))
    K = int(pf(p, "neighbours", 2, 16))
    xfade_ms = pf(p, "crossfade_ms", 0, 2000)
    n_gl = int(pf(p, "gl_iterations", 0, 200))
    excursion = pf(p, "excursion", 0.0, 10.0)
    out_dur_req = pf(p, "output_duration", 0.0, 3600.0)
    detail = p["decoder_detail"] if p["decoder_detail"] in ("source", "pure") else "source"
    normalise = p["normalise"] not in ("0", "no", "false")

    # ---- Pbind (parsed first: syntax errors should not cost a training run) ----
    try:
        with open(p["pbind_file"], "r", encoding="utf-8") as f:
            pb_text = f.read()
    except OSError as e:
        raise LPError("temp-file", f"cannot read Pbind file: {e}")
    if not pb_text.strip():
        raise LPError("syntax", "the Pbind expression is empty")
    pats, durs, interps, g_interp = analyse_pbind(pb_text, d, p["interp"])
    log(f"  Pbind keys: {', '.join(sorted(pats))}  (interp {g_interp})")

    # ---- audio ----
    sr, x = read_wav_mono(p["input_wav"])
    dur_in = len(x) / sr
    rms_in = float(np.sqrt(np.mean(x * x))) if len(x) else 0.0
    if rms_in < 1e-5:
        raise LPError("input", f"input is silent (RMS {rms_in:.2e})")
    n_fft = 2048 if sr >= 32000 else (1024 if sr >= 16000 else 512)
    hop = n_fft // 4
    frame_dt = hop / sr
    P = max(4, int(round(patch_ms / 1000.0 / frame_dt)))
    ahop = max(1, int(round(ahop_ms / 1000.0 / frame_dt)))
    if dur_in < 3 * P * frame_dt:
        raise LPError("input", f"input too short ({dur_in:.2f} s) for patch length {patch_ms:.0f} ms "
                               f"(needs >= {3 * P * frame_dt:.2f} s)")

    log("  [1] STFT + band analysis")
    X = stft(x, n_fft, hop)
    F_src = X.shape[1]
    pw = np.abs(X) ** 2
    fb, up_m, centres = band_setup(sr, n_fft)
    raw = 10 * np.log10(fb @ pw + 1e-20)
    top = float(raw.max())
    floor_db = top - 90.0
    Bsrc = np.maximum(raw, floor_db)                    # [bands, frames]
    env_src_bins = up_m @ Bsrc                          # smooth source envelope per frame
    mag_src_db = 20 * np.log10(np.abs(X) + 1e-10)

    # ---- patches ----
    starts = np.arange(0, F_src - P + 1, ahop)
    lin = 10 ** (Bsrc / 10.0)
    p_energy = np.array([10 * np.log10(lin[:, s:s + P].mean() + 1e-20) for s in starts])
    keep = p_energy > p_energy.max() - 60.0
    starts = starts[keep]
    N = len(starts)
    if N < 12:
        raise LPError("input", f"only {N} non-silent patches — input too short or too quiet "
                               f"(lower Patch length or Analysis hop)")
    feats = np.stack([resample_cols(Bsrc[:, s:s + P], T_CELLS).ravel() for s in starts])
    f_mean = feats.mean(0)
    f_scale = float(feats.std()) + 1e-6
    Xn = (feats - f_mean) / f_scale
    log(f"  [2] {N} patches of {P} frames ({P * frame_dt * 1000:.0f} ms), hop {ahop * frame_dt * 1000:.0f} ms")

    # ---- VAE ----
    log(f"  [3] training beta-VAE  d={d}  beta={beta}  epochs={epochs}")
    trng = np.random.default_rng(seed)
    model, hist, kl_dim = train_vae(Xn, d, epochs, beta, trng, log)
    mu, lv, _ = model.encode(Xn)
    if not np.all(np.isfinite(mu)):
        raise LPError("latent", "encoder produced NaN latent values")
    recon, _ = model.decode(mu)
    rec_err_db = float(np.sqrt(np.mean((recon - Xn) ** 2)) * f_scale)
    # Level calibration: a regression decoder in the dB domain under-predicts
    # loud cells (regression to the mean), so decoded patches play quieter than
    # their sources. Measure the mean energy offset on the training set and
    # remove it. Per-band ceilings/floors and a total-power ceiling (both taken
    # from the corpus) stop extrapolated latents from producing spectra louder
    # than anything the corpus contains.
    def _energy_db(cells_db):
        return 10 * np.log10(np.mean(10 ** (cells_db / 10.0), axis=1) + 1e-20)
    dec_db = recon * f_scale + f_mean
    level_cal = float(np.mean(_energy_db(feats) - _energy_db(dec_db)))
    band_cells = feats.reshape(N, N_BANDS, T_CELLS)
    band_hi = np.percentile(band_cells, 99.5, axis=(0, 2)) + 3.0
    band_lo = np.percentile(band_cells, 0.5, axis=(0, 2)) - 6.0
    energy_ceiling = float(_energy_db(feats).max()) + 1.0
    active = int(np.sum(kl_dim > 0.05))

    # ---- rotation, orientation, robust scaling ----
    z_mean = mu.mean(0)
    _, svals, Vt = np.linalg.svd(mu - z_mean, full_matrices=False)
    V = Vt.T                                            # latent -> rotated
    Zr = (mu - z_mean) @ V
    band_idx = np.arange(N_BANDS)
    patch_bands = feats.reshape(N, N_BANDS, T_CELLS).mean(2)
    plin = 10 ** (patch_bands / 10.0)
    centroid = (plin * band_idx).sum(1) / plin.sum(1)
    level = p_energy[keep]
    corr_c, corr_l = np.zeros(d), np.zeros(d)
    for j in range(d):
        cc = np.corrcoef(Zr[:, j], centroid)[0, 1] if Zr[:, j].std() > 0 else 0.0
        if cc < 0:
            V[:, j] *= -1
            Zr[:, j] *= -1
            cc = -cc
        corr_c[j] = cc
        corr_l[j] = np.corrcoef(Zr[:, j], level)[0, 1] if Zr[:, j].std() > 0 else 0.0
    med = np.median(Zr, 0)
    half = np.maximum((np.percentile(Zr, 98, 0) - np.percentile(Zr, 2, 0)) / 2.0, 1e-6)
    Cd = (Zr - med) / half                              # normalised data coordinates
    var_share = svals ** 2 / max(float(np.sum(svals ** 2)), 1e-12)
    post_sd = np.sqrt(np.mean(np.exp(lv), 0))           # per raw latent dim
    sd_norm = np.sqrt((V ** 2).T @ (post_sd ** 2)) / half

    nn_self, nn_d = nearest(Cd, Cd, k=2)
    r_ref = float(np.percentile(nn_d[:, 1], 90)) + 1e-9  # cloud "thickness"

    k_cl = max(2, min(n_clusters, N // 4))
    cent, lab = kmeans(Cd, k_cl, np.random.default_rng([seed, 7]))
    log(f"  [4] latent: {active}/{d} dims active, r_ref {r_ref:.3f}, {k_cl} clusters")

    # ---- event streams ----
    t_target = out_dur_req if out_dur_req > 0 else dur_in
    g_on, g_ended, g_end_t = run_clock(pats["dur"], key_rng(seed, "dur"), t_target, "dur")
    if len(g_on) == 0:
        raise LPError("pattern", "the dur pattern produced no events")
    t_out = min(t_target, g_end_t) if g_ended else t_target
    ended_reason = "finite dur pattern exhausted" if g_ended and g_end_t < t_target else "target duration"
    clocks = {"dur": g_on}
    values = {}
    for k in sorted(pats):
        if k == "dur":
            continue
        if k in durs:
            on, _, _ = run_clock(durs[k], key_rng(seed, "dur_" + k), t_out, "dur_" + k)
        else:
            on = g_on
        v = draw_values(pats[k], key_rng(seed, k), len(on))
        if len(v) == 0:
            raise LPError("pattern", f"pattern for {k} produced no values")
        if len(v) < len(on):
            if k in durs:
                on = on[:len(v)]                        # independent voice ends, holds last value
            else:                                       # shared clock: SC semantics, Pbind ends
                cand_end = float(g_on[len(v)])
                if cand_end < t_out:                    # report only the stream that actually ends it
                    t_out = cand_end
                    ended_reason = f"finite pattern {k} exhausted"
        clocks[k] = on
        values[k] = v
    if t_out < 0.1:
        raise LPError("pattern", f"pattern stream ends after {t_out:.3f} s — nothing to render")
    for k in clocks:
        m = clocks[k] < t_out
        clocks[k] = clocks[k][m]
        if k in values:
            values[k] = values[k][:len(clocks[k])]
    n_glob = len(clocks["dur"])
    log(f"  [5] {n_glob} global events, output {t_out:.2f} s ({ended_reason})")

    # ---- control trajectories at frame rate ----
    n_out = int(round(t_out * sr))
    F_out = 1 + (n_out + hop - 1) // hop
    tf = np.arange(F_out) * frame_dt
    mode_of = lambda k: interps.get(k, g_interp)
    ctrl = np.zeros((F_out, d))
    zkeys = [f"z{j + 1}" for j in range(d) if f"z{j + 1}" in values]
    for j in range(d):
        k = f"z{j + 1}"
        if k in values:
            ctrl[:, j] = interpolate(clocks[k], values[k], tf, mode_of(k))
    base = np.zeros((F_out, d))
    if "cluster" in values:
        ci = np.mod(np.round(values["cluster"]).astype(int), k_cl)
        values["cluster"] = ci.astype(float)
        for j in range(d):
            base[:, j] = interpolate(clocks["cluster"], cent[ci, j], tf, mode_of("cluster"))
    aux = {}
    for k, dflt in AUX_KEYS.items():
        aux[k] = interpolate(clocks[k], values[k], tf, mode_of(k)) if k in values else np.full(F_out, dflt)
    amp_c = np.maximum(aux["amp"], 0.0)
    rate_c = np.clip(aux["rate"], 0.0, 4.0)
    att_c = np.clip(aux["attract"], 0.0, 1.0)
    temp_c = np.maximum(aux["temp"], 0.0)

    C_raw = base + excursion * ctrl
    if np.any(temp_c > 0):                              # posterior jitter, one draw per global event
        jr = key_rng(seed, "jitter")
        eps = jr.standard_normal((n_glob, d)) * sd_norm[None]
        for j in range(d):
            C_raw[:, j] += temp_c * interpolate(clocks["dur"], eps[:, j], tf, g_interp)
    if not np.all(np.isfinite(C_raw)):
        raise LPError("dimension", "trajectory contains non-finite coordinates")

    C = apply_box(C_raw, boundary)
    nn_i, nn_dist = nearest(C, Cd, k=1)
    if boundary == "attract":                           # soft knee towards the data cloud
        dn = nn_dist[:, 0]
        over = dn > r_ref
        if np.any(over):
            ex = dn[over] - r_ref
            newd = r_ref + ex / (1.0 + ex / r_ref)
            anchor = Cd[nn_i[over, 0]]
            C[over] = anchor + (C[over] - anchor) * (newd / dn[over])[:, None]
    if np.any(att_c > 0):
        nn_i, nn_dist = nearest(C, Cd, k=1)
        C = C + att_c[:, None] * (Cd[nn_i[:, 0]] - C)
    n_bound = int(np.sum(np.any(np.abs(C_raw) > 1.0, axis=1)))
    Kb = min(K, N)
    nn_i, nn_dist = nearest(C, Cd, k=Kb if render == "barycentric" else 1)
    dist_ratio = nn_dist[:, 0] / r_ref

    # ---- read pointer (time since the last retrigger, in frames, advanced by rate) ----
    retrig_on = clocks.get("retrig", clocks["dur"])
    if "retrig" in values:
        retrig_on = retrig_on[values["retrig"] > 0.5]
    rf = set(np.clip(np.round(retrig_on / frame_dt).astype(int), 0, F_out - 1).tolist())
    ptr = np.zeros(F_out)
    epoch = np.zeros(F_out, dtype=int)
    p_cur, e_cur = 0.0, 0
    for f in range(F_out):
        if f in rf and f > 0:
            p_cur, e_cur = 0.0, e_cur + 1
        ptr[f] = p_cur
        epoch[f] = e_cur
        p_cur += rate_c[f]

    # ---- rendering ----
    # Source voices: a voice is (patch, retrigger epoch) with its own read
    # cursor into the source STFT. It enters at patch start + min(ptr, P-1)
    # (the attack if the event has just started, the patch's later frames
    # otherwise) and then keeps reading FORWARD through the source at `rate`
    # for as long as it is selected — dwelling on a latent point lets that
    # point's source material continue rather than looping a short patch.
    # Voices fade in/out in the power domain over crossfade_ms.
    log(f"  [6] rendering ({render})")
    starts_f = starts.astype(float)
    xf_step = 1.0 / max(1.0, xfade_ms / 1000.0 / frame_dt)
    Kv = Kb if render == "barycentric" else 1
    if render == "barycentric":
        w = 1.0 / (nn_dist ** 2 + (0.05 * r_ref) ** 2)
        w /= w.sum(1, keepdims=True)
        tpow = (w * w) / (w * w).sum(1, keepdims=True)  # equal-power targets
    else:
        w = np.ones((F_out, 1))
        tpow = w
    donor_time = np.zeros(F_out)
    n_limited = 0
    n_bins = X.shape[0]
    Y = np.zeros((n_bins, F_out), dtype=complex)
    need_env = render == "decoder"
    if need_env:
        Zrot = C * half + med
        Zlat = Zrot @ V.T + z_mean
        out_cells = np.empty((F_out, N_BANDS, T_CELLS))
        for s in range(0, F_out, 1024):
            xh, _ = model.decode(Zlat[s:s + 1024])
            out_cells[s:s + 1024] = (xh * f_scale + f_mean).reshape(-1, N_BANDS, T_CELLS)
        if not np.all(np.isfinite(out_cells)):
            raise LPError("decoder", "decoder produced non-finite output")
        out_cells += level_cal
        out_cells = np.clip(out_cells, band_lo[None, :, None], band_hi[None, :, None])
        e_cells = 10 * np.log10(np.mean(10 ** (out_cells / 10.0), axis=(1, 2)) + 1e-20)
        excess = np.maximum(e_cells - energy_ceiling, 0.0)
        out_cells -= excess[:, None, None]
        n_limited = int(np.sum(excess > 0))
        mags = np.zeros((n_bins, F_out))

    voices = {}                                         # (patch, epoch) -> [patch, cursor, power]
    n_voice_starts = 0
    max_voices = 0
    for f in range(F_out):
        targets = {}
        for k in range(Kv):
            key = (int(nn_i[f, k]), int(epoch[f]))
            targets[key] = targets.get(key, 0.0) + float(tpow[f, k])
        for key in targets:
            if key not in voices:
                voices[key] = [key[0], starts_f[key[0]] + min(ptr[f], P - 1.0), 0.0]
                n_voice_starts += 1
        lone = len(voices) == len(targets) and all(v[2] == 0.0 for v in voices.values())
        for key, v in voices.items():
            tp = targets.get(key, 0.0)
            if lone or xf_step >= 1.0:
                v[2] = tp
            elif v[2] < tp:
                v[2] = min(tp, v[2] + xf_step)
            else:
                v[2] = max(tp, v[2] - xf_step)
        for key in [kk for kk, v in voices.items() if v[2] <= 1e-5 and kk not in targets]:
            del voices[key]
        tot = sum(v[2] for v in voices.values())
        max_voices = max(max_voices, len(voices))
        acc = np.zeros(n_bins, dtype=complex)
        pow_acc = np.zeros(n_bins)
        best, best_p = None, -1.0
        if need_env:
            q = min(ptr[f], P - 1.0) / max(P - 1.0, 1.0) * (T_CELLS - 1)
            q0 = int(math.floor(q))
            q1 = min(q0 + 1, T_CELLS - 1)
            wq = q - q0
            env = up_m @ ((1 - wq) * out_cells[f, :, q0] + wq * out_cells[f, :, q1])
        for v in voices.values():
            pn = v[2] / tot if tot > 0 else 0.0           # renormalise to unit power
            s_idx = int(min(max(round(v[1]), 0), F_src - 1))
            acc += math.sqrt(pn) * X[:, s_idx]
            if need_env:
                e = env + (mag_src_db[:, s_idx] - env_src_bins[:, s_idx]) if detail == "source" else env
                m = 10 ** (e / 20.0)
                pow_acc += pn * m * m
            if v[2] > best_p:
                best, best_p = v, v[2]
        donor_time[f] = best[1] * frame_dt if best is not None else 0.0
        for v in voices.values():
            v[1] = min(v[1] + rate_c[f], F_src - 1.0)
        if need_env:
            mags[:, f] = np.sqrt(pow_acc)
            Y[:, f] = mags[:, f] * np.exp(1j * np.angle(acc))
        else:
            Y[:, f] = acc
    if need_env and n_gl > 0:
        log(f"      Griffin-Lim refinement ({n_gl} iterations)")
        for _ in range(n_gl):
            yt = istft(Y, n_fft, hop, n_out)
            Yt = stft(yt, n_fft, hop)[:, :F_out]
            Y = mags * np.exp(1j * np.angle(Yt))

    y = istft(Y, n_fft, hop, n_out)
    t_s = np.arange(n_out) / sr
    y *= np.interp(t_s, tf, amp_c)
    if not np.all(np.isfinite(y)):
        raise LPError("decoder", "rendered audio contains NaN/Inf")
    peak = float(np.max(np.abs(y))) if n_out else 0.0
    gain = 1.0
    if peak < 1e-9:
        raise LPError("render", "rendered audio is silent (check amp pattern)")
    if normalise:
        gain = 0.891 / peak
    elif peak > 0.999:
        gain = 0.999 / peak
    y *= gain
    rms_out = float(np.sqrt(np.mean(y * y)))
    write_wav(p["output_wav"], y, sr)

    # ---- visualisation tables ----
    key_order = ["dur"] + [k for k in [f"z{j}" for j in range(1, 17)] + ["cluster"] + list(AUX_KEYS)
                           if k in values]
    ev_rows = []
    for lane, k in enumerate(key_order):
        on = clocks[k]
        if k == "dur":
            v = np.diff(np.append(on, t_out))
        else:
            v = values[k]
        lo, hi = (float(v.min()), float(v.max())) if len(v) else (0.0, 1.0)
        for tt, vv in zip(on, v):
            vn = 0.5 if hi - lo < 1e-12 else (vv - lo) / (hi - lo)
            ev_rows.append([str(lane + 1), k, float(tt), float(vv), float(vn)])
    write_csv(p["events_csv"], ["lane", "key", "time", "value", "vnorm"], ev_rows)

    stride = max(1, F_out // 700)
    tr_idx = np.arange(0, F_out, stride)
    head = ["time"] + [f"z{j + 1}" for j in range(d)] + ["dist", "donor"]
    if render == "barycentric":
        head += [f"n{k + 1}" for k in range(Kb)] + [f"w{k + 1}" for k in range(Kb)]
    rows = []
    for f in tr_idx:
        r = [tf[f]] + list(C[f]) + [dist_ratio[f], donor_time[f]]
        if render == "barycentric":
            off = min(ptr[f], P - 1.0)
            r += [(starts_f[nn_i[f, k]] + off) * frame_dt for k in range(Kb)] + list(np.sqrt(tpow[f]))
        rows.append(r)
    write_csv(p["traj_csv"], head, rows)

    cs = max(1, N // 1500)
    zh = [f"z{j + 1}" for j in range(d)]
    write_csv(p["cloud_csv"], zh + ["cluster", "time"],
              [list(Cd[i]) + [float(lab[i]), (starts[i] + P / 2) * frame_dt] for i in range(0, N, cs)])
    write_csv(p["centres_csv"], ["idx"] + zh, [[float(j)] + list(cent[j]) for j in range(k_cl)])
    gi = np.clip(np.round(clocks["dur"] / frame_dt).astype(int), 0, F_out - 1)
    write_csv(p["onsets_csv"], ["time"] + zh, [[tf[f]] + list(C[f]) for f in gi])

    lanes = ";".join(key_order)
    stats = {
        "version": VERSION, "seed": seed, "seed_requested": seed_req,
        "sr": sr, "n_fft": n_fft, "hop_ms": round(frame_dt * 1000, 3),
        "input_dur": round(dur_in, 4), "output_dur": round(t_out, 4), "ended": ended_reason,
        "patches": N, "patch_frames": P, "patch_ms_eff": round(P * frame_dt * 1000, 1),
        "latent_dims": d, "active_dims": active, "beta": beta, "epochs": epochs,
        "rec_db": round(rec_err_db, 2), "level_cal": round(level_cal, 2),
        "limited_pct": round(100.0 * n_limited / F_out, 1), "kl": round(hist[-1][1], 3),
        "var_share": " ".join(f"{v:.2f}" for v in var_share),
        "corr_centroid": " ".join(f"{v:+.2f}" for v in corr_c),
        "corr_level": " ".join(f"{v:+.2f}" for v in corr_l),
        "clusters": k_cl, "r_ref": round(r_ref, 4),
        "render": render, "detail": detail if render == "decoder" else "n/a",
        "gl": n_gl if render == "decoder" else 0, "neighbours": Kb if render == "barycentric" else 0,
        "interp": g_interp, "boundary": boundary, "excursion": excursion,
        "global_events": n_glob, "lanes": lanes, "n_lanes": len(key_order),
        "zkeys": " ".join(zkeys),
        "plot_dims": " ".join(str(j + 1) for j in range(d)
                              if f"z{j + 1}" in values or np.ptp(C[:, j]) > 1e-6), "frames_outside_box": n_bound,
        "outside_pct": round(100.0 * n_bound / F_out, 1),
        "dist_mean": round(float(dist_ratio.mean()), 3), "dist_max": round(float(dist_ratio.max()), 3),
        "far_pct": round(100.0 * float(np.mean(dist_ratio > 1.0)), 1),
        "distinct_donors": int(len(np.unique(nn_i[:, 0]))), "voice_starts": n_voice_starts,
        "max_voices": max_voices,
        "retriggers": len(rf), "peak_raw": round(peak, 5), "gain": round(gain, 5),
        "rms_in": round(rms_in, 6), "rms_out": round(rms_out, 6),
    }
    for kk in values:
        stats["n_" + kk] = len(values[kk])
    try:
        with open(p["stats_file"], "w", encoding="utf-8", newline="\n") as f:
            for k, v in stats.items():
                f.write(f"{k}={v}\n")
    except OSError as e:
        raise LPError("temp-file", f"cannot write stats: {e}")
    log("  done")


def main():
    if len(sys.argv) != 2:
        print("usage: latent_pbind.py params.txt", file=sys.stderr)
        sys.exit(2)
    p = read_params(sys.argv[1])
    status = p.get("status_file", "")
    verbose = os.environ.get("LATENT_PBIND_QUIET") is None

    def log(msg):
        if verbose:
            print(msg, flush=True)

    def put_status(text):
        if status:
            try:
                with open(status, "w", encoding="utf-8", newline="\n") as f:
                    f.write(text + "\n")
            except OSError:
                pass
    try:
        log(f"latent_pbind.py {VERSION}")
        run(p, log)
        put_status("OK")
    except LPError as e:
        put_status(f"ERROR {e.category}: {e.message}")
        print(f"ERROR {e.category}: {e.message}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:                            # unexpected — report, never fall back silently
        put_status(f"ERROR internal: {type(e).__name__}: {e}")
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
