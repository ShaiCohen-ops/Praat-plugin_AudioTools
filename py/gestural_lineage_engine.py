"""
gestural_lineage_engine.py — Gestural Lineage Composer engine

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University

Called by Gestural_Lineage_Composer.praat — not run directly.

Version 1.0.2 (2026) - sound change after the third external review:
    * Trend strength and trend confidence are separate. The trend is named
      from its strength alone; its p (exact, adjusted for the number of
      features tested) labels it confirmed or tentative. v1.0.1 required
      p <= 0.05, which 4 generations can never reach (smallest p 0.083).
    * 'Most drift' (Gradual Evolution) with Strict off chooses among ALL
      lineages of 4+ generations by sound change, not only those beyond
      chance; the status still reports the lineage's own chance test.
    * Exact trend test vectorised with cached orderings (one matrix product
      per feature instead of up to 40320 Python loops).
    * kind 'evolution' renamed 'structural evolution' (change of contour);
      the sound change is reported separately as acoustic evolution.

Version 1.0.1 (2026) - chance-test repairs after external review:
    * Few shuffles: when the Sound has few block orders, every distinct order
      is tested once (exact); if even that cannot reach p <= alpha the result
      is "insufficient data", not "weak" (v1.0 drew 99 random orders of e.g. 2
      blocks, half of them identical to the original).
    * Shuffled pairs now count (v1.0 ignored them: pairs, and chains compared
      with them, got too-small p values).
    * Every chain is scored and tested before the distinct lineages are
      chosen (v1.0 chose by length first).
    * Results: significant / exploratory / insufficient data.

Version 1.0 (2026)

What it does
    A Sound's feature trajectory (spectral centroid, loudness or spectral
    flatness on a common time grid) is cut into every overlapping window of
    a fixed duration. STUMPY's matrix profile finds, for every window, its
    nearest neighbour among EARLIER windows (left) and among LATER windows
    (right). A time series chain (Matrix Profile VII, Zhu et al. 2017) is a
    sequence of windows in which each consecutive pair is mutually linked:
    the right neighbour of A is B AND the left neighbour of B is A. Chains are
    therefore chronological by construction, and the definition is checked
    for every link this engine reports.

    A chain is a lineage: gestures that recur in time, each most like the one
    before and the one after. Its first and last members can be very
    different (drift) while every step is small.

    Chains also occur by chance. Every lineage is tested against the same
    material with its time order destroyed (block-shuffled surrogates, block
    = two windows). Each chain gets one score (its length, plus one per
    halving of its worst link below a typical nearest-neighbour distance);
    p = the fraction of shuffled versions whose BEST chain scores at least as
    high. Comparing with the best chain of each shuffled version makes p
    family-wise over all lineages of the run (max-statistic test); measured
    false-positive rate on lineage-free corpora: 1 run in 40 at p <= 0.05.
    Only lineages with p <= alpha are used unless --allow_weak is set.

Distance
    shape    z-normalized Euclidean distance (default): transposition and
             gesture size are ignored, only the shape of the trajectory
             counts. Reported as shape correlation r = 1 - d^2 / (2m).
    absolute raw Euclidean distance: register and range count too.

Modes
    lineage    the chosen lineage's gestures in chain order (or reversed)
    montage    several lineages interleaved generation by generation
    branching  lineages whose first gestures resemble the chosen lineage's
               first gesture, one after another (measured root distance)
    guided     the lineage that passes through the window nearest an anchor
               time (ancestors + descendants)

Outputs (prefix P)
    P_plan.tsv      reconstruction plan (source intervals, in output order)
    P_traj.tsv      feature trajectory (display copy, <= 4000 points)
    P_mp.tsv        matrix profile (display copy, <= 4000 points)
    P_lineages.tsv  every distinct lineage of length >= 3, with statistics
    P_members.tsv   members of the lineages used in the plan
    P_stats.txt     key=value run record

Dependencies: numpy, scipy, soundfile, stumpy
"""

import os
import sys
import math
import json
import argparse
import platform

VERSION = "2.1.2"


# ------------------------------------------------------------ numba cache
def _cache_root():
    if platform.system() == "Windows":
        base = os.environ.get("LOCALAPPDATA") or os.path.expanduser("~\\AppData\\Local")
    elif platform.system() == "Darwin":
        base = os.path.expanduser("~/Library/Caches")
    else:
        base = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return os.path.join(base, "PraatAudioTools", "GesturalLineageComposer", "numba-cache")


try:
    _cd = _cache_root()
    os.makedirs(_cd, exist_ok=True)
    os.environ.setdefault("NUMBA_CACHE_DIR", _cd)
except OSError:
    pass

import numpy as np
import warnings


def _enable_stumpy_cache():
    """STUMPY's kernels are numba functions compiled on first use (~10-15 s).
    numba's own on-disk cache makes later runs start in about a second. If the
    cache cannot be written or read, numba simply compiles again; results do
    not depend on it."""
    try:
        import importlib
        import stumpy.cache as sc
        for mod, fn in sc.get_njit_funcs():
            try:
                getattr(importlib.import_module("stumpy." + mod), fn).enable_caching()
            except Exception:
                pass
    except Exception:
        pass


FEATURES = ("centroid", "loudness", "flatness")
FLAT_STD = {"centroid": 0.03, "loudness": 0.5, "flatness": 0.03}


# ================================================================ features
def strongest_channel(Y):
    if Y.ndim == 1:
        return Y, 1
    r = np.sqrt(np.mean(Y ** 2, axis=0))
    c = int(np.argmax(r))
    return Y[:, c], c + 1


def frame_features(y, sr, hop_s=0.02, silence_db=-60.0, rel_silence_db=50.0, gap_fill_s=0.10):
    """Grid cell k = source time [k*hop, (k+1)*hop), measured with a 2*hop Hann
    window centred on the cell. Centroid in log2 Hz and flatness in log10 are
    UNDEFINED (NaN) in silence; loudness (dB) is defined everywhere (silence
    = the silence floor). Undefined gaps up to gap_fill_s are interpolated
    (articulation inside a gesture); longer ones stay undefined and no window
    containing them is analysed."""
    hop = max(1, int(round(hop_s * sr)))
    n = len(y) // hop
    if n < 8:
        raise ValueError("sound too short: %.3f s gives %d grid cells of %.3f s"
                         % (len(y) / sr, n, hop / sr))
    win = 2 * hop
    nfft = 1 << int(math.ceil(math.log2(max(win, 64))))
    pad = np.concatenate([np.zeros(hop // 2), y, np.zeros(win)])
    w = np.hanning(win)
    freqs = np.fft.rfftfreq(nfft, 1.0 / sr)
    band = (freqs >= 30.0) & (freqs <= min(sr / 2.0, 16000.0))
    fb = freqs[band]
    # vectorised framing
    idx = np.arange(n)[:, None] * hop + np.arange(win)[None, :]
    frames = pad[idx]
    loud = 10 * np.log10(np.mean(frames ** 2, axis=1) + 1e-24)
    spec = np.abs(np.fft.rfft(frames * w[None, :], nfft, axis=1)) ** 2
    p = spec[:, band]
    ps = p.sum(axis=1)
    cent = np.full(n, np.nan)
    flat = np.full(n, np.nan)
    ok = ps > 1e-20
    cent[ok] = np.log2((p[ok] @ fb) / ps[ok])
    pf = np.maximum(p[ok], ps[ok, None] * 1e-12)
    flat[ok] = np.log10(np.exp(np.mean(np.log(pf), axis=1)) / np.mean(pf, axis=1) + 1e-12)
    # spectral flux (phrase segmentation): half-wave rectified change of the
    # log-magnitude spectrum between adjacent cells, mean over the band
    lm = np.log1p(1e3 * np.sqrt(p / max(float(p.max()), 1e-30)))
    flux = np.zeros(n)
    flux[1:] = np.maximum(lm[1:] - lm[:-1], 0.0).mean(axis=1)
    top = float(np.percentile(loud, 99))
    thr = max(silence_db, top - rel_silence_db)
    silent = loud < thr
    loud_c = np.maximum(loud, thr)
    cent[silent] = np.nan
    flat[silent] = np.nan
    gmax = int(round(gap_fill_s / (hop / sr)))
    filled = 0
    for arr in (cent, flat):
        bad = np.isnan(arr)
        i = 0
        while i < n:
            if bad[i]:
                j = i
                while j < n and bad[j]:
                    j += 1
                if i > 0 and j < n and (j - i) <= gmax:
                    arr[i:j] = np.linspace(arr[i - 1], arr[j], j - i + 2)[1:-1]
                    if arr is cent:
                        filled += j - i
                i = j
            else:
                i += 1
    return {"hop_s": hop / sr, "n": n, "centroid": cent, "loudness": loud_c, "flatness": flat,
            "silent": silent, "silence_threshold_db": thr, "gap_filled_cells": filled,
            "flux": flux, "loudness_raw": loud,
            "peak_loudness_db": top}


# ================================================================ profile
def matrix_profile(T, m, normalize=True, flat_std=0.03):
    """Left/right matrix profile, exclusion zone = m (two windows in one
    relation never share source audio). Undefined windows are excluded by
    STUMPY (infinite distance).

    Shape (z-normalized): near-constant windows (std < flat_std) carry no
    gesture (z-normalisation would turn their noise into shape): they may
    neither link nor be linked.
    Absolute: only exactly constant windows (silence floor, digital constant)
    are excluded; a sustained sound is a valid neighbour there.

    v1.0.1: a window whose nearest left or right neighbour is an excluded
    window gets its nearest VALID neighbour on that side, recomputed exactly
    with stumpy.mass (v1.0 dropped the link instead of looking further)."""
    import stumpy
    from numpy.lib.stride_tricks import sliding_window_view
    T = np.asarray(T, dtype=np.float64)
    n_sub = len(T) - m + 1
    if n_sub < 2 * m + 1:
        raise ValueError("a %d-cell window leaves %d windows; at least %d are needed "
                         "(the recording is too short for this window)" % (m, n_sub, 2 * m + 1))
    W = sliding_window_view(T, m)
    valid = ~np.isnan(W).any(axis=1)
    sd = np.zeros(n_sub)
    sd[valid] = W[valid].std(axis=1)
    flat = valid & (sd < (flat_std if normalize else 1e-9))
    if not np.any(valid):
        raise ValueError("every %d-cell window contains an undefined stretch (silence longer than "
                         "0.1 s, where centroid and flatness do not exist): use a shorter window, "
                         "or the Loudness feature, which is defined in silence" % m)
    if not np.any(valid & ~flat):
        raise ValueError("no window carries a gesture: the feature is constant in every window "
                         "(a stable sound or silence)")
    old = stumpy.config.STUMPY_EXCL_ZONE_DENOM
    stumpy.config.STUMPY_EXCL_ZONE_DENOM = 1
    try:
        import warnings
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            if normalize:
                mp = stumpy.stump(T, m, T_A_subseq_isconstant=flat)
            else:
                mp = stumpy.stump(T, m, normalize=False)
    finally:
        stumpy.config.STUMPY_EXCL_ZONE_DENOM = old
    P = mp[:, 0].astype(float)
    I = mp[:, 1].astype(np.int64)
    IL = mp[:, 2].astype(np.int64)
    IR = mp[:, 3].astype(np.int64)
    bad_self = ~valid | flat
    good = ~bad_self
    tgt = lambda a: np.clip(a, 0, n_sub - 1)
    affected = np.where(good & (((IL >= 0) & bad_self[tgt(IL)]) | ((IR >= 0) & bad_self[tgt(IR)]) |
                                ((I >= 0) & bad_self[tgt(I)])))[0]
    repaired = 0
    if len(affected):
        idx = np.arange(n_sub)
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            for i in affected:
                if normalize:
                    D = stumpy.mass(T[i:i + m], T, normalize=True, T_subseq_isconstant=flat)
                else:
                    D = stumpy.mass(T[i:i + m], T, normalize=False)
                D = np.asarray(D, dtype=float).copy()
                D[bad_self | (np.abs(idx - i) <= m)] = np.inf      # STUMPY excludes |j - i| <= m
                left, right = D[:i], D[i + 1:]
                jl = int(np.argmin(left)) if len(left) and np.isfinite(left.min()) else -1
                jr = (i + 1 + int(np.argmin(right))) if len(right) and np.isfinite(right.min()) else -1
                IL[i], IR[i] = jl, jr
                dl = D[jl] if jl >= 0 else np.inf
                dr = D[jr] if jr >= 0 else np.inf
                P[i] = min(dl, dr)
                I[i] = jl if dl <= dr else jr
                repaired += 1
    P[bad_self] = np.inf
    for arr in (I, IL, IR):
        arr[(arr >= 0) & bad_self[tgt(arr)]] = -1
        arr[bad_self] = -1
    return {"P": P, "I": I, "IL": IL, "IR": IR, "flat": flat, "valid": valid, "m": m,
            "normalize": normalize, "T": T, "repaired_links": repaired}


def subseq_dist(T, i, j, m, normalize=True):
    a, b = T[i:i + m], T[j:j + m]
    if normalize:
        sa, sb = a.std(), b.std()
        if sa < 1e-12 or sb < 1e-12:
            return 0.0 if (sa < 1e-12 and sb < 1e-12) else math.sqrt(m)
        a = (a - a.mean()) / sa
        b = (b - b.mean()) / sb
    return float(np.sqrt(np.sum((a - b) ** 2)))


def median_P(prof):
    if "_median" not in prof:
        f = prof["P"][np.isfinite(prof["P"])]
        prof["_median"] = float(np.median(f)) if len(f) else float("nan")
    return prof["_median"]


def all_chains(prof):
    import stumpy
    S, _ = stumpy.allc(prof["IL"], prof["IR"])
    IL, IR = prof["IL"], prof["IR"]
    out = []
    for s in S:
        s = [int(x) for x in s]
        for a, b in zip(s[:-1], s[1:]):
            if not (IR[a] == b and IL[b] == a):
                raise AssertionError("chain link %d->%d is not reciprocal" % (a, b))
        out.append(s)
    return out


def lineage_through(prof, j):
    import stumpy
    IL, IR = prof["IL"], prof["IR"]
    desc = [int(x) for x in stumpy.atsc(IL, IR, int(j))]
    anc, k = [], int(j)
    for _ in range(len(IL)):
        p = IL[k]
        if p < 0 or IR[p] != k:
            break
        anc.append(int(p))
        k = int(p)
    ch = anc[::-1] + desc
    for a, b in zip(ch[:-1], ch[1:]):
        if not (IR[a] == b and IL[b] == a):
            raise AssertionError("chain link %d->%d is not reciprocal" % (a, b))
    return ch


def link_ratios(chain, prof):
    med = median_P(prof)
    m, nz, T = prof["m"], prof["normalize"], prof["T"]
    if not (med > 0):
        return [0.0] * (len(chain) - 1)
    return [subseq_dist(T, a, b, m, nz) / med for a, b in zip(chain[:-1], chain[1:])]


MAX_OVERLAP = 1.0 / 3.0   # a lineage may share source audio in at most a third of its gestures


def distinct_lineages(stats, m):
    """v1.0.1: chains are scored and tested FIRST; then the distinct set is
    taken best-evidence-first (lowest p, then longer, then tighter worst link)
    and a chain is kept only if it shares no source audio with one already
    kept. (v1.0 chose by length before testing, so a long, loose chain could
    eliminate a shorter, better one.)"""
    order = sorted(stats, key=lambda s: (s["p"] if s["p"] == s["p"] else 1.0, -s["length"],
                                         s["worst_link_ratio"], s["members"][0]))
    kept, used = [], []
    for st in order:
        # v1.0.1: measured overlap instead of a blanket ban. A gesture
        # "overlaps" if it shares source audio with a gesture already kept;
        # parallel copies (every gesture overlapping) are still rejected, a
        # lineage that touches another in one place (a shared origin) is kept.
        n_ov = sum(1 for a in st["members"] if any(abs(a - b) < m for b in used))
        frac = n_ov / len(st["members"])
        if frac > MAX_OVERLAP + 1e-12:
            continue
        st["overlap_fraction"] = frac
        kept.append(st)
        used.extend(st["members"])
    return kept


def block_reorder(T, block, order):
    nb = len(T) // block
    blocks = [T[i * block:(i + 1) * block] for i in range(nb)]
    return np.concatenate([blocks[o] for o in order] + [T[nb * block:]])


def block_surrogate(T, block, rng):
    return block_reorder(T, block, rng.permutation(len(T) // block))


SCORE_FLOOR = 0.01   # measured: 1/40 false-positive runs, 20/30 detections; 0.25 gave 2/40 and 16/30


def chain_score(L, worst):
    """One number per chain: its length, plus one generation for every halving
    of its worst link below a typical nearest-neighbour distance (at most
    log2(1/SCORE_FLOOR) generations). Longer and tighter both count."""
    return L + math.log2(1.0 / max(worst, SCORE_FLOOR))


BLOCK_FACTOR = 2      # block = 2 windows: measured 1/34 false-positive runs on null corpora (1 x: 4/34)


def shuffle_plan(n_cells, m, n_surr, seed):
    """Which block orders to test. Few blocks -> every distinct non-identity
    order, once (an exact permutation test); many -> n_surr random orders.
    Also returns the smallest p the test can possibly give: if that is above
    alpha, the test cannot decide (insufficient data), whatever the music."""
    import itertools
    block = max(1, int(round(BLOCK_FACTOR * m)))
    nb = n_cells // block
    n_orders = math.factorial(nb) if nb < 20 else float("inf")
    if n_orders - 1 <= n_surr:
        ident = tuple(range(nb))
        orders = [list(o) for o in itertools.permutations(range(nb)) if o != ident]
        exact = True
    else:
        rng = np.random.default_rng(seed)
        orders = [rng.permutation(nb) for _ in range(n_surr)]
        exact = False
    min_p = 1.0 / (1 + len(orders)) if orders else 1.0
    return {"block": block, "n_blocks": nb, "n_orders": n_orders, "orders": orders,
            "exact": exact, "min_p": min_p}


def surrogate_tables(T, m, normalize, flat_std, n_surr, seed, plan=None):
    plan = plan or shuffle_plan(len(T), m, n_surr, seed)
    tabs = []
    for order in plan["orders"]:
        Ts = block_reorder(T, plan["block"], order)
        try:
            pr = matrix_profile(Ts, m, normalize, flat_std)
        except ValueError:
            tabs.append([])
            continue
        rows = []
        for c in all_chains(pr):
            if len(c) >= 2:
                r = link_ratios(c, pr)
                rows.append((len(c), max(r)))
        tabs.append(rows)
    return tabs


def chain_p(L, worst, tabs):
    """Max-statistic test (family-wise over every lineage of the run): the
    fraction of shuffled versions whose BEST chain scores at least as high.
    (1 + hits) / (1 + n): never 0, smallest possible value 1/(n+1)."""
    if not tabs:
        return float("nan")
    sc = chain_score(L, worst)
    # v1.0.1: every chain of 2 or more counts, as on the data side (v1.0 ignored
    # surrogate pairs, which made pairs, and chains scored against them, look
    # better than they were)
    hits = sum(1 for rows in tabs if any(chain_score(l, w) >= sc - 1e-12 for l, w in rows if l >= 2))
    return (1 + hits) / (1 + len(tabs))


ACOUSTIC = (("centroid", "centroid", "oct", 0.5, ("brighter", "darker")),
            ("loudness", "loudness", "dB", 3.0, ("louder", "softer")),
            ("flatness", "flatness", "log10", 0.25, ("noisier", "more tonal")))


_PERM_CACHE = {}


def _perm_index(n):
    """All orderings of n items (n <= 8, at most 40320 rows), or 20000 random
    orderings (fixed seed) above; built once per n and reused."""
    if n not in _PERM_CACHE:
        if n <= 8:
            import itertools
            _PERM_CACHE[n] = (np.array(list(itertools.permutations(range(n))), dtype=np.int8), True)
        else:
            rng = np.random.default_rng(0)
            _PERM_CACHE[n] = (np.argsort(rng.random((20000, n)), axis=1).astype(np.int16), False)
    return _PERM_CACHE[n]


def trend_p(v):
    """Two-sided p of the rank correlation between a lineage's member values
    and generation order: exact over all orderings up to 8 members, 20000
    random orderings above. Vectorised; the ordering table is cached per
    length, so each call costs one matrix product."""
    from scipy.stats import rankdata
    r = rankdata(v)
    n = len(r)
    g = np.arange(n, dtype=float)
    gc = g - g.mean()
    rc = r - r.mean()
    den = math.sqrt((gc * gc).sum() * (rc * rc).sum())
    if den == 0:
        return 1.0
    obs = abs(float(gc @ rc)) / den
    idx, exact = _perm_index(n)
    vals = np.abs(rc[idx] @ gc) / den
    hits = int((vals >= obs - 1e-12).sum())
    return hits / len(idx) if exact else (1 + hits) / (1 + len(idx))


def min_trend_p(n):
    """Smallest two-sided exact p a perfect trend can reach with n members."""
    return 2.0 / math.factorial(n) if n <= 8 else 1.0 / 20001


def acoustic_trend(c, feats, m):
    """How the ABSOLUTE sound changes along a lineage (links are found by
    shape; this measures what shape matching ignores). For each feature: the
    mean of every member window, its rank correlation with generation (rho)
    and the total change (last member minus first).

    v1.0.2: STRENGTH and CONFIDENCE are separate.
      score  = |rho| x min(1, |change| / reference), references 0.5 octave,
               3 dB, 0.25 log10 (each a clearly audible change). The trend is
               named when score >= 0.5, whatever its p.
      confidence: exact permutation p of rho, multiplied by the number of
               features tested (Bonferroni: the strongest of up to three is
               reported). 'confirmed' if the adjusted p <= 0.05, otherwise
               'tentative' (with 4 generations even a perfect trend has
               p = 0.083, so 4-generation trends are always tentative)."""
    out = {"acoustic_drift_score": 0.0, "acoustic_trend": "stable", "acoustic_confidence": "-",
           "acoustic_p_adj": float("nan"), "acoustic_detail": "", "member_means": {}}
    if feats is None:
        return out
    if len(c) < 4:
        # with 3 generations a rank correlation is +-1 far too easily
        out.update({"acoustic_trend": "n/a", "acoustic_detail": "fewer than 4 generations: no trend measured"})
        return out
    means, found = {}, []
    for key, name, unit, ref, words in ACOUSTIC:
        T = feats.get(key)
        if T is None:
            continue
        v = np.array([np.nanmean(T[j:j + m]) if np.isfinite(T[j:j + m]).any() else np.nan for j in c])
        means[key] = v
        ok = np.isfinite(v)
        if ok.sum() < 4 or np.nanstd(v[ok]) == 0:
            continue
        from scipy.stats import spearmanr
        rho = spearmanr(np.arange(len(c))[ok], v[ok]).correlation
        if not np.isfinite(rho):
            continue
        change = float(v[ok][-1] - v[ok][0])
        pt = trend_p(v[ok])
        sc = abs(rho) * min(1.0, abs(change) / ref)
        out[key + "_rho"] = float(rho)
        out[key + "_trend_p"] = pt
        out[key + "_change"] = change
        found.append((sc, key, name, unit, words, rho, change, pt, int(ok.sum())))
    k = len(found)
    out["member_means"] = means
    if not k:
        out["acoustic_detail"] = "no feature defined in enough members"
        return out
    parts = []
    for sc, key, name, unit, words, rho, change, pt, n in sorted(found, key=lambda x: -x[0]):
        padj = min(1.0, pt * k)
        if sc >= 0.3:
            parts.append("%s %s %.2f %s (rho %+.2f, p %s, adjusted for %d features %s)" % (
                name, "rises" if change > 0 else "falls", abs(change), unit, rho,
                "< 0.001" if pt < 0.001 else "%.3f" % pt, k, "< 0.001" if padj < 0.001 else "%.3f" % padj))
    sc, key, name, unit, words, rho, change, pt, n = max(found, key=lambda x: (x[0], -x[7]))
    padj = min(1.0, pt * k)
    out["acoustic_drift_score"] = float(sc)
    out["acoustic_p_adj"] = padj
    if sc >= 0.5:
        out["acoustic_trend"] = words[0] if change > 0 else words[1]
        out["acoustic_confidence"] = "confirmed" if padj <= 0.05 + 1e-12 else "tentative"
        if padj > 0.05 and min_trend_p(n) * k > 0.05:
            parts.append("%d generations cannot confirm a trend (smallest possible adjusted p %.3f)"
                         % (n, min(1.0, min_trend_p(n) * k)))
    out["acoustic_detail"] = "; ".join(parts) if parts else \
        "no clear change (every feature changes less than its audible reference or not steadily)"
    return out


def chain_stats(c, prof, hop_s, xmin):
    m, nz, T = prof["m"], prof["normalize"], prof["T"]
    links = [subseq_dist(T, a, b, m, nz) for a, b in zip(c[:-1], c[1:])]
    end = subseq_dist(T, c[0], c[-1], m, nz) if len(c) > 1 else 0.0
    dmax = 2 * math.sqrt(m)
    mean_link = float(np.mean(links)) if links else 0.0
    ff = [subseq_dist(T, c[0], x, m, nz) for x in c]
    mono = 0.0
    if len(c) >= 3 and np.std(ff) > 0:
        mono = float(np.corrcoef(np.arange(len(c)), ff)[0, 1])
    r = link_ratios(c, prof)
    st = {
        "length": len(c), "members": c,
        "start_times": [xmin + x * hop_s for x in c],
        "link_dist": links,
        "link_ratio": r,
        "worst_link_ratio": max(r) if r else 0.0,
        "mean_link_norm": mean_link / dmax if nz else mean_link / math.sqrt(m),
        "end_to_end_norm": end / dmax if nz else end / math.sqrt(m),
        "drift_ratio": end / mean_link if mean_link > 1e-12 else 0.0,
        "drift_monotonicity": mono,
        "span_s": (c[-1] - c[0]) * hop_s,
    }
    # shape correlation of each link (z-normalized only): r = 1 - d^2 / 2m
    st["link_corr"] = [1 - d * d / (2 * m) for d in links] if nz else [float("nan")] * len(links)
    st["end_corr"] = (1 - end * end / (2 * m)) if nz else float("nan")
    st.update(acoustic_trend(c, prof.get("feats"), m))
    if st["end_to_end_norm"] < 0.02 or st["drift_ratio"] < 1.5:
        st["kind"] = "recurrence"
    elif st["drift_ratio"] >= 2.0 and mono >= 0.8 and len(c) >= 4:
        st["kind"] = "structural evolution"
    else:
        st["kind"] = "relation"
    return st


def analyse(T, m, hop_s, normalize, flat_std, xmin, n_surr, seed, alpha=0.05, min_len=3, feats=None):
    prof = matrix_profile(T, m, normalize, flat_std)
    prof["feats"] = feats
    raw = all_chains(prof)
    plan = shuffle_plan(len(T), m, n_surr, seed) if n_surr > 0 else None
    tabs = surrogate_tables(T, m, normalize, flat_std, n_surr, seed, plan) if plan else []
    scored = []
    for c in raw:
        if len(c) >= min_len:
            st = chain_stats(c, prof, hop_s, xmin)
            st["p"] = chain_p(len(c), st["worst_link_ratio"], tabs)
            scored.append(st)
    stats = distinct_lineages(scored, m)
    prof["shuffle"] = {k: v for k, v in plan.items() if k != "orders"} if plan else None
    prof["test_possible"] = bool(plan) and plan["min_p"] <= alpha + 1e-12
    if tabs and stats:
        # chain_p is already family-wise (max statistic): no further correction
        for st in stats:
            st["p_fwer"] = st["p"]
            st["significant"] = st["p"] <= alpha
    else:
        for st in stats:
            st["p_fwer"] = float("nan")
            st["significant"] = False
    stats.sort(key=lambda s: (s["p_fwer"] if s["p_fwer"] == s["p_fwer"] else 1.0,
                              -s["length"], s["worst_link_ratio"], s["members"][0]))
    for k, st in enumerate(stats):
        st["id"] = k + 1
    null_longest = [max((l for l, _ in rows), default=0) for rows in tabs]
    return prof, stats, raw, tabs, null_longest


# ================================================================ choice
SELECT = ("strongest", "tightest", "drift", "span")


def choose(cands, how):
    if not cands:
        return None
    if how == "tightest":
        return min(cands, key=lambda s: (s["kind"] != "recurrence", s["worst_link_ratio"], s["p_fwer"]))
    if how == "drift":
        # v1.0.1: the ACOUSTIC change along the lineage (brighter/darker, louder/
        # softer, noisier/more tonal) decides; shape drift breaks ties
        # v1.0.2: then a confirmed trend, then a lineage beyond chance
        return max(cands, key=lambda s: (round(s.get("acoustic_drift_score", 0.0), 2),
                                         s.get("acoustic_confidence") == "confirmed", bool(s["significant"]),
                                         s["drift_ratio"] * max(0.0, s["drift_monotonicity"]), -s["p_fwer"]))
    if how == "span":
        return max(cands, key=lambda s: (s["span_s"], -s["p_fwer"]))
    return cands[0]                        # strongest: already sorted by p, length, tightness


# ================================================================ plan
def plan_rows(seq, win_s, order, gap_mode, gap_scale, max_out):
    """seq: list of (lineage stats, member position). Output rows in order."""
    rows, out_t, prev = [], 0.0, None
    for st, k in seq:
        t0 = st["start_times"][k]
        dur = st["durations"][k] if "durations" in st else win_s      # phrases: their own duration
        sil = 0.0
        if gap_mode == "proportional" and prev is not None and prev[0] is st:
            # silence = original time between the two units, scaled
            # (fixed windows: |t0 - t0'| - window, as before)
            gap = max(t0, prev[1]) - min(t0 + dur, prev[1] + prev[2])
            sil = max(0.0, gap) * gap_scale
        if max_out > 0 and out_t + sil + dur > max_out + 1e-9 and rows:
            break
        lr = st["link_ratio"][k - 1] if 0 < k else float("nan")
        lc = st["link_corr"][k - 1] if 0 < k else float("nan")
        if order == "backward" and k < len(st["start_times"]) - 1:
            lr = st["link_ratio"][k]
            lc = st["link_corr"][k]
        rows.append({"src_start": t0, "src_end": t0 + dur, "lineage": st["id"], "generation": k + 1,
                     "silence_before": sil, "link_ratio": lr, "link_corr": lc})
        out_t += sil + dur
        prev = (st, t0, dur)
    return rows


def build_plan(mode, stats, cands, args, prof, hop_s, xmin, win_s, tabs, root_pool=None):
    info = {}
    order = args.order
    if mode == "guided":
        n_sub = len(prof["P"])
        j0 = int(round((args.anchor_time - xmin) / hop_s))
        j0 = min(max(j0, 0), n_sub - 1)
        best = None
        m = prof["m"]
        for d in range(0, m + 1):          # search outward from the anchor, up to one window
            for j in ((j0 - d, j0 + d) if d else (j0,)):
                if 0 <= j < n_sub:
                    ch = lineage_through(prof, j)
                    if len(ch) >= 3 and (best is None or len(ch) > len(best[1])):
                        best = (j, ch)
            if best is not None:
                break
        if best is None:                   # a pair is still a (two-generation) lineage
            for d in range(0, m + 1):
                for j in ((j0 - d, j0 + d) if d else (j0,)):
                    if 0 <= j < n_sub:
                        ch = lineage_through(prof, j)
                        if len(ch) >= 2 and (best is None or len(ch) > len(best[1])):
                            best = (j, ch)
                if best is not None:
                    break
        if best is None and stats:         # nothing near the anchor: the lineage nearest to it
            near = min(((abs(mem - j0), mem) for s_ in stats for mem in s_["members"]))
            best = (near[1], lineage_through(prof, near[1]))
            info["note"] = ("no lineage passes within one window of the anchor; the nearest one, "
                            "%.2f s away, is used" % (abs(near[1] - j0) * hop_s))
        if best is None:
            info["reason"] = "no two windows of this recording are mutually nearest neighbours"
            return [], info, []
        j, ch = best
        st = chain_stats(ch, prof, hop_s, xmin)
        st["p"] = chain_p(len(ch), st["worst_link_ratio"], tabs)
        st["p_fwer"] = st["p"]              # one pre-specified test: no family correction
        st["significant"] = (st["p"] <= args.alpha) if tabs else False
        st["id"] = 1
        info["anchor_window_start"] = xmin + j * hop_s
        info["anchor_shift_s"] = (j - j0) * hop_s
        info["anchor_position"] = ch.index(j) + 1
        if not st["significant"] and not args.allow_weak:
            info["reason"] = ("the lineage through the anchor (%d gestures) is not beyond chance "
                              "(p = %.3f); untick 'Strict' to hear it anyway" % (len(ch), st["p"]))
            return [], info, [st]
        idx = list(range(len(ch)))
        if order == "backward":
            idx = idx[::-1]
        return plan_rows([(st, k) for k in idx], win_s, order, args.gap_mode, args.gap_scale,
                         args.max_output), info, [st]
    if not cands:
        return [], info, []
    root = choose(root_pool or cands, args.select)
    used = [root]
    if mode == "lineage":
        seq = [(root, k) for k in range(root["length"])]
    elif mode == "montage":
        others = [s for s in cands if s is not root][: max(0, args.n_lineages - 1)]
        used = [root] + others
        seq = []
        for g in range(max(s["length"] for s in used)):
            for s in used:
                if g < s["length"]:
                    seq.append((s, g))
        info["montage_lineages"] = len(used)
    elif mode == "branching":
        m, nz, T = prof["m"], prof["normalize"], prof["T"]
        med = median_P(prof)
        # Chains cannot fork (a window has at most one reciprocal successor),
        # so a shared origin is claimed by ONE lineage. A branch is another
        # lineage whose first gesture is close to some generation of the root
        # lineage (the fork point) and that starts after it.
        br = []
        for s in cands:
            if s is root:
                continue
            best = None
            for k, j in enumerate(root["members"]):
                if j >= s["members"][0]:
                    break
                # the two chains may sample their gestures at different phases:
                # allow up to half a window of shift around the root generation
                lo, hi = max(0, j - m // 2), min(len(prof["P"]) - 1, j + m // 2)
                d = min(subseq_dist(T, jj, s["members"][0], m, nz) for jj in range(lo, hi + 1)
                        if prof["valid"][jj] and not prof["flat"][jj]) if any(
                    prof["valid"][jj] and not prof["flat"][jj] for jj in range(lo, hi + 1)) else float("inf")
                # scale: the larger worst link of the two lineages (how far one
                # generation may be from the next inside them)
                scale = max(max(root["link_dist"] or [0.0]), max(s["link_dist"] or [0.0]))
                ratio = d / scale if scale > 0 else float("inf")
                if best is None or ratio < best[0]:
                    best = (ratio, k)
            if best is not None and best[0] <= args.branch_ratio:
                br.append((best[0], best[1], s))
        br.sort(key=lambda x: x[0])
        br = br[: max(0, args.n_lineages - 1)]
        used = [root] + [s for _, _, s in br]
        info["branch_root_ratios"] = [round(r, 4) for r, _, _ in br]
        info["branch_fork_generations"] = [k + 1 for _, k, _ in br]
        if not br:
            info["note"] = ("no other lineage starts within %.2f x the lineages' own largest step "
                            "of any generation of this one: a single lineage, not branches"
                            % args.branch_ratio)
        # the root lineage, then for each branch: its fork gesture, then the branch
        seq = [(root, k) for k in range(root["length"])]
        for _, k, s in br:
            seq.append((root, k))
            seq += [(s, g) for g in range(s["length"])]
    else:
        raise ValueError(mode)
    if order == "backward":
        if mode == "montage":
            seq = seq[::-1]
        else:
            seq2 = []
            for s in used:
                seq2 += [(s, k) for k in range(s["length"] - 1, -1, -1)]
            seq = seq2
    return plan_rows(seq, win_s, order, args.gap_mode, args.gap_scale, args.max_output), info, used


# ================================================================ export
def decimate(t, v, max_points=4000):
    """Display copy: mean per bin, a bin with any undefined value stays
    undefined (gaps are kept visible)."""
    n = len(v)
    if n <= max_points:
        return t, v
    k = int(math.ceil(n / max_points))
    nb = n // k
    tt = t[:nb * k].reshape(nb, k).mean(axis=1)
    vv = v[:nb * k].reshape(nb, k)
    out = np.where(np.isfinite(vv).all(axis=1), np.where(np.isfinite(vv), vv, 0).mean(axis=1), np.nan)
    return tt, out


def fmt(x, nd=6):
    if x is None or (isinstance(x, float) and not math.isfinite(x)):
        return "?"
    return ("%." + str(nd) + "f") % x


# ================================================================ v2.0: evolution paths
# The fourth review: strict reciprocal chains rarely form in real recordings
# (each gesture must be the OTHER's single nearest neighbour), and matching on
# one feature misses a gesture's identity. The evolution-path engine keeps
# the relations (trajectory distances in time order) but composes with the
# best PATH through them instead of requiring a complete chain:
#   * windows on a stride grid (1/8 window), at least 80% sounding; centroid
#     and flatness are bridged across pauses for matching only
#   * distance: RMS over the matched features of the z-normalised (Shape) or
#     reference-scaled (Absolute) Euclidean distance; exact full matrix
#   * links: mutual k-nearest neighbours in time order (K = 1 is exactly a
#     chain link), within tol x the typical nearest-neighbour distance
#   * path: exact dynamic programming over the time-ordered windows; each step
#     earns 1 - c/tol (c = distance / typical) plus, for a direction, up to 1
#     for progress (capped at half an audible reference per step); a step
#     audibly against the direction is not allowed
#   * order evidence: the same search on block-shuffled versions (all features
#     and the silence mask shuffled together, blocks of 2 windows)
# Calibration (path_sweep.py, path_null.py): see the technical report, s13.
PATH_REF = {"centroid": 0.5, "loudness": 3.0, "flatness": 0.25}
PATH_FEATS = ("centroid", "loudness", "flatness")
DIRECTIONS = {
    "brighter": ("centroid", +1), "darker": ("centroid", -1),
    "louder": ("loudness", +1), "softer": ("loudness", -1),
    "noisier": ("flatness", +1), "more_tonal": ("flatness", -1),
    "continuity": (None, 0),
}
AUTO_DIRECTIONS = ("brighter", "darker", "louder", "softer", "noisier", "more_tonal")
DIRECTION_WORD = {"brighter": "brighter", "darker": "darker", "louder": "louder", "softer": "softer",
                  "noisier": "noisier", "more_tonal": "more tonal", "continuity": "continuity"}
PATH_K, PATH_TOL, PATH_CAP, PATH_BACK, PATH_SOUNDING = 3, 2.0, 0.5, 0.1, 0.8


def fill_gaps(feats):
    """Centroid and flatness are undefined in silence. For MATCHING, undefined
    cells are bridged by linear interpolation (held at the ends), so a pause is
    part of a gesture's contour; member means still use sounding cells only."""
    out = dict(feats)
    for f in ("centroid", "flatness"):
        v = np.asarray(feats[f], float)
        ok = np.isfinite(v)
        if ok.any() and not ok.all():
            x = np.arange(len(v))
            v = np.interp(x, x[ok], v[ok])
        out[f + "_filled"] = v
    out["loudness_filled"] = np.asarray(feats["loudness"], float)
    return out


def path_windows(feats, use, m, stride, min_sounding=PATH_SOUNDING):
    """Start cells of candidate windows: every `stride` cells, at least half
    sounding, and not flat in ALL used features (that carries no gesture)."""
    n = len(feats["loudness"])
    starts = np.arange(0, n - m + 1, stride)
    snd = (~np.asarray(feats["silent"], bool)).astype(float)
    cs = np.concatenate([[0.0], np.cumsum(snd)])
    keep = []
    for s in starts:
        if (cs[s + m] - cs[s]) < min_sounding * m:
            continue
        if not np.isfinite(feats["centroid_filled"][s:s + m]).all():
            continue
        if all(np.std(feats[f + "_filled"][s:s + m]) < FLAT_STD[f] for f in use):
            continue
        keep.append(s)
    return np.array(keep, dtype=int)


def distance_matrix(feats, use, starts, m, shape=True):
    """RMS over the used features of the per-feature window distance, in the
    STUMPY convention for Shape: z-normalised Euclidean; a flat window counts
    as all-zero (two flat windows: 0; flat vs moving: sqrt(m))."""
    N = len(starts)
    D2 = np.zeros((N, N))
    idx = starts[:, None] + np.arange(m)[None, :]
    for f in use:
        X = feats[f + "_filled"][idx].astype(float)
        if shape:
            mu = X.mean(axis=1, keepdims=True)
            sd = X.std(axis=1, keepdims=True)
            Z = np.where(sd >= FLAT_STD[f], (X - mu) / np.where(sd > 0, sd, 1), 0.0)
        else:
            Z = X / PATH_REF[f]
        nn = (Z * Z).sum(axis=1)
        G = Z @ Z.T
        D2 += np.maximum(nn[:, None] + nn[None, :] - 2 * G, 0.0)
    return np.sqrt(D2 / len(use))


def sounding_only(feats):
    """Feature copies with silent cells undefined: a gesture's mean (and its
    sound change) must not depend on how much pause its window includes
    (loudness would otherwise count the silence floor)."""
    sil = np.asarray(feats["silent"], bool)
    return {f: np.where(sil, np.nan, np.asarray(feats[f], float)) for f in PATH_FEATS}


def member_means(feats, starts, m):
    idx = starts[:, None] + np.arange(m)[None, :]
    snd = sounding_only(feats)
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", RuntimeWarning)
        return {f: np.nanmean(snd[f][idx], axis=1) / PATH_REF[f] for f in PATH_FEATS}


def build_links(D, starts, m, K=PATH_K, tol=PATH_TOL, distinct=False):
    """Mutual k-nearest-neighbour links in time order: i -> j (j later, no
    overlap) if j is among the K nearest LATER windows of i AND i is among the
    K nearest EARLIER windows of j, and the distance is within tol x typical.
    K = 1 is exactly the reciprocal left/right link of a time series chain;
    larger K relaxes it (a gesture may have a closer relative elsewhere).
    typical = median over windows of the nearest non-overlapping distance."""
    N = len(starts)
    sep = np.abs(starts[:, None] - starts[None, :]) >= m
    Dm = np.where(sep, D, np.inf)
    nearest = Dm.min(axis=1)
    typ = float(np.median(nearest[np.isfinite(nearest)])) if np.isfinite(nearest).any() else float("nan")
    links = [[] for _ in range(N)]
    if not np.isfinite(typ):
        return links, typ, nearest
    if typ <= 1e-6:                    # distances are of order 1: below 1e-6 is rounding of an exact 0
        # v2.1.1: identical repetitions (distance 0) are a valid relation, not
        # an absence of one; scale by the typical NON-zero distance, or 1 if
        # every unit is identical (all links then cost 0)
        nz = nearest[np.isfinite(nearest) & (nearest > 1e-6)]
        typ = float(np.median(nz)) if len(nz) else 1.0
    later = starts[None, :] >= starts[:, None] + m          # later[i, j]: j after i
    DL = np.where(later, D, np.inf)                         # row i: later windows
    DE = np.where(later.T, D, np.inf)                       # row j: earlier windows
    # distinct=True (branch search): K counts DISTINCT gestures - windows a
    # stride apart are near-copies of one gesture, so a candidate within half
    # a window of an already chosen one is skipped. The main path uses the
    # plain K nearest windows (measured better: path_sweep.py, report s13).
    half = max(1, m // 2)
    pool = min(N, K * (2 * (m // max(1, int(np.min(np.diff(starts))) if N > 1 else 1)) + 2))
    pool = max(pool, min(N, K))

    def knn(Drow):
        if pool < N:
            cand = np.argpartition(Drow, pool - 1)[:pool]
        else:
            cand = np.arange(N)
        cand = cand[np.argsort(Drow[cand], kind="stable")]
        out = []
        for c in cand:
            if not np.isfinite(Drow[c]):
                break
            if all(abs(int(starts[c]) - int(starts[o])) >= half for o in out):
                out.append(int(c))
                if len(out) == K:
                    break
        return out

    def knn_plain(Drow):
        kk = min(K, N)
        cand = np.argpartition(Drow, kk - 1)[:kk]
        return [int(c) for c in cand if np.isfinite(Drow[c])]

    pick = knn if distinct else knn_plain
    later_k = [pick(DL[i]) for i in range(N)]
    early_sets = [set(pick(DE[j])) for j in range(N)]
    for i in range(N):
        for j in later_k[i]:
            if D[i, j] <= tol * typ + 1e-6 and i in early_sets[j]:
                links[i].append((j, float(D[i, j] / typ)))
        links[i].sort()
    return links, typ, nearest


def step_gain(mu, direction, i, j, c, tol=PATH_TOL, cap=PATH_CAP, back=PATH_BACK):
    """Reward of the step i -> j (link cost c = distance / typical), or None if
    the step goes audibly against the direction."""
    feat, sign = DIRECTIONS[direction]
    g = 1.0 - c / tol
    if feat is None:
        return g
    d = sign * (mu[feat][j] - mu[feat][i])
    if d < -back:
        return None
    return g + min(d, cap) / cap


def best_path(links, mu, direction, tol=PATH_TOL, cap=PATH_CAP, back=PATH_BACK, banned=None, through=None,
              start=None):
    """Exact best path by dynamic programming (windows are in time order, links
    only go forward, so the link graph is acyclic).
      free (default): the best path anywhere
      through=a:      the best path containing window a (guided mode)
      start=a:        the best path beginning at window a (branches)
    banned: windows that may not be used. Returns (score, [window indices])."""
    N = len(links)
    banned = banned or set()

    def forward():
        f = np.zeros(N)
        prev = -np.ones(N, dtype=int)
        for i in banned:
            f[i] = -np.inf
        for i in range(N):
            if not np.isfinite(f[i]):
                continue
            for j, c in links[i]:
                if j in banned:
                    continue
                g = step_gain(mu, direction, i, j, c, tol, cap, back)
                if g is not None and f[i] + g > f[j]:
                    f[j] = f[i] + g
                    prev[j] = i
        return f, prev

    def backward():
        b = np.zeros(N)
        nxt = -np.ones(N, dtype=int)
        for i in range(N - 1, -1, -1):
            if i in banned:
                b[i] = -np.inf
                continue
            for j, c in links[i]:
                if j in banned or not np.isfinite(b[j]):
                    continue
                g = step_gain(mu, direction, i, j, c, tol, cap, back)
                if g is not None and g + b[j] > b[i]:
                    b[i] = g + b[j]
                    nxt[i] = j
        return b, nxt

    def walk_back(prev, k):
        p = [k]
        while prev[p[-1]] >= 0:
            p.append(int(prev[p[-1]]))
        return p[::-1]

    def walk_on(nxt, k):
        p = []
        while nxt[k] >= 0:
            k = int(nxt[k])
            p.append(k)
        return p

    if N == 0:
        return 0.0, []
    if start is not None:
        b, nxt = backward()
        return float(b[start]), [start] + walk_on(nxt, start)
    if through is not None:
        f, prev = forward()
        b, nxt = backward()
        return float(f[through] + b[through]), walk_back(prev, through) + walk_on(nxt, through)
    f, prev = forward()
    end = int(np.argmax(f))
    return float(f[end]), walk_back(prev, end)


def path_analysis(feats, use, m, shape=True, K=PATH_K, tol=PATH_TOL, min_sounding=PATH_SOUNDING):
    """Candidate windows, distance matrix, links, member means (None if fewer
    than two candidate windows)."""
    ff = fill_gaps(feats)
    n = len(ff["loudness"])
    stride = max(1, m // 8)
    while (n - m) / stride > 3000:             # keep the matrix tractable (<= ~3000 windows)
        stride += 1
    starts = path_windows(ff, use, m, stride, min_sounding)
    if len(starts) < 2:
        return None
    D = distance_matrix(ff, use, starts, m, shape)
    links, typ, nearest = build_links(D, starts, m, K, tol)
    mu = member_means(feats, starts, m)
    return {"starts": starts, "D": D, "typ": typ, "links": links, "nearest": nearest, "mu": mu,
            "stride": stride, "n_positions": len(range(0, n - m + 1, stride)), "m": m}


def path_best(A, directions, tol=PATH_TOL, banned=None, through=None, start=None):
    """Best (score, direction, path) over the given directions."""
    best = (-np.inf, None, [])
    for d in directions:
        sc, p = best_path(A["links"], A["mu"], d, tol, banned=banned, through=through, start=start)
        if sc > best[0] + 1e-12:
            best = (sc, d, p)
    return best


def path_evidence(feats, use, m, shape, directions, observed, plan, K, tol, min_sounding):
    """Order evidence: p = (1 + #shuffled versions whose best path scores at
    least as high) / (1 + #versions), max over the same directions."""
    best_scores, best_lens = [], []
    for order in plan["orders"]:
        fs = {f: block_reorder(np.asarray(feats[f], float), plan["block"], order) for f in PATH_FEATS}
        fs["silent"] = block_reorder(np.asarray(feats["silent"], bool), plan["block"], order)
        A = path_analysis(fs, use, m, shape, K, tol, min_sounding)
        if A is None:
            best_scores.append(0.0)
            best_lens.append(0)
            continue
        sc, d, p = path_best(A, directions, tol)
        best_scores.append(sc)
        best_lens.append(len(p))
    if not best_scores:
        return float("nan"), [], []
    hits = sum(1 for b in best_scores if b >= observed - 1e-12)
    return (1 + hits) / (1 + len(best_scores)), best_scores, best_lens


def path_stats(path, direction, A, feats, m, hop, xmin, shape, p, alpha, sid):
    """A path in the same form as a v1 lineage (so plans, tables and the Praat
    display work unchanged)."""
    D, typ, starts = A["D"], A["typ"], A["starts"]
    mem = [int(starts[k]) for k in path]
    links = [float(D[a, b]) for a, b in zip(path[:-1], path[1:])]
    end = float(D[path[0], path[-1]]) if len(path) > 1 else 0.0
    mean_link = float(np.mean(links)) if links else 0.0
    ff = [float(D[path[0], k]) for k in path]
    mono = float(np.corrcoef(np.arange(len(path)), ff)[0, 1]) if len(path) >= 3 and np.std(ff) > 0 else 0.0
    dmax = 2 * math.sqrt(m)
    st = {
        "id": sid, "length": len(path), "members": mem, "windows": list(path),
        "start_times": [xmin + x * hop for x in mem],
        "link_dist": links, "link_ratio": [d / typ for d in links],
        "worst_link_ratio": max([d / typ for d in links]) if links else 0.0,
        "end_to_end_norm": end / dmax if shape else end / math.sqrt(m),
        "drift_ratio": end / mean_link if mean_link > 1e-12 else 0.0,
        "drift_monotonicity": mono, "span_s": (mem[-1] - mem[0]) * hop,
        # RMS of per-feature z-distances: 1 - d^2/2m = mean shape correlation over the features
        "link_corr": [1 - d * d / (2 * m) for d in links] if shape else [float("nan")] * len(links),
        "end_corr": (1 - end * end / (2 * m)) if shape else float("nan"),
        "p": p, "p_fwer": p, "significant": bool(p == p and p <= alpha), "overlap_fraction": 0.0,
        "direction": direction,
    }
    st.update(acoustic_trend(mem, sounding_only(feats), m))
    feat, sign = DIRECTIONS[direction]
    if feat is not None:
        # the path was SEARCHED for this change: its rank test is not valid
        # evidence (selection); the order evidence p is the test
        ch = st.get(feat + "_change")
        rho = st.get(feat + "_rho")
        unit = {"centroid": "oct", "loudness": "dB", "flatness": "log10"}[feat]
        strength = abs(rho) * min(1.0, abs(ch) / PATH_REF[feat]) if (ch is not None and rho is not None) else 0.0
        if ch is not None and sign * ch > 0 and strength < 0.5:
            # the same threshold as everywhere: too small or unsteady to name
            st["acoustic_trend"] = "stable"
            st["acoustic_detail"] = ("target %s: %s changes only %.2f %s over %d generations (rho %+.2f), below "
                                     "the audible reference; reported as stable"
                                     % (DIRECTION_WORD[direction], feat, abs(ch), unit, len(path),
                                        rho if rho is not None else float("nan")))
        elif ch is not None and sign * ch > 0:
            st["acoustic_trend"] = DIRECTION_WORD[direction]
            st["acoustic_detail"] = ("target %s: %s %s %.2f %s over %d generations (rho %+.2f); the path was "
                                     "searched for this change, so its strength is by design - the order "
                                     "evidence p is the test" % (DIRECTION_WORD[direction], feat,
                                                                 "rises" if ch > 0 else "falls", abs(ch), unit,
                                                                 len(path), rho if rho is not None else float("nan")))
        st["acoustic_confidence"] = "target"
        st["acoustic_p_adj"] = float("nan")
    if st["end_to_end_norm"] < 0.02 or st["drift_ratio"] < 1.5:
        st["kind"] = "recurrence"
    elif st["drift_ratio"] >= 2.0 and mono >= 0.8 and len(path) >= 4:
        st["kind"] = "structural evolution"
    else:
        st["kind"] = "relation"
    return st


def run_path(args, F, hop, st_out, finish, unchanged, plan_header, P):
    """The v2.0 evolution-path engine (args.engine == 'path')."""
    use = list(PATH_FEATS) if args.match == "all" else [args.feature]
    shape = args.similarity == "shape"
    directions = list(AUTO_DIRECTIONS) if args.direction == "auto" else [args.direction]
    win, adapt = args.window_s, []
    A = None
    for _ in range(6):
        m = int(round(win / hop))
        if F["n"] >= m + 1:
            A = path_analysis(F, use, m, shape, args.k_links, args.tolerance)
            if A is not None and any(A["links"]):
                break
        if win / 2 < 0.1 - 1e-9:
            break
        adapt.append("fewer than two linked %.2f s windows: window halved" % win)
        win /= 2
    if A is None or not any(A["links"]):
        unchanged("no two sounding windows of this recording can be linked (too short, or silent)")
        return
    m = A["m"]
    win_s = m * hop
    disp = args.feature if args.match != "all" else None
    st_out.update({"engine": "path", "match": args.match, "matched_features": "+".join(use),
                   "direction_requested": args.direction, "k_links": args.k_links, "tolerance": args.tolerance,
                   "window_cells": m, "window_s": win_s, "adapted": " | ".join(adapt),
                   "stride_cells": A["stride"], "typical_link_distance": A["typ"]})
    # ---- the path(s) ----
    sc0, d0, p0 = path_best(A, directions, args.tolerance)
    plan = shuffle_plan(F["n"], m, args.surrogates, args.seed) if args.surrogates > 0 else None
    if plan and plan["orders"]:
        pval, nb_sc, nb_len = path_evidence(F, use, m, shape, directions, sc0, plan, args.k_links,
                                            args.tolerance, PATH_SOUNDING)
    else:
        pval, nb_sc, nb_len = float("nan"), [], []
    test_possible = bool(plan) and plan["min_p"] <= args.alpha + 1e-12
    info, used, seq = {}, [], []
    starts = A["starts"]
    n_win = len(starts)

    def overlapping(ws):
        """Windows sharing source audio with any of the windows ws."""
        out = set()
        for w in ws:
            lo = np.searchsorted(starts, starts[w] - m + 1)
            hi = np.searchsorted(starts, starts[w] + m - 1, side="right")
            out.update(range(lo, hi))
        return out

    if args.mode == "guided":
        j0 = int(round((args.anchor_time - args.xmin) / hop - m / 2.0))
        a = int(np.argmin(np.abs(starts - j0)))
        shift = (starts[a] - j0) * hop
        sc, d, path = path_best(A, directions, args.tolerance, through=a)
        if abs(shift) > win_s:
            info["note"] = ("no candidate window within one window of the anchor; the nearest one, %.2f s "
                            "away, is used" % abs(shift))
        info["anchor_window_start"] = args.xmin + starts[a] * hop
        info["anchor_shift_s"] = shift
        info["anchor_position"] = path.index(a) + 1
        # the anchored path against the shuffled versions' best FREE paths
        # (conservative: an anchored path never scores above the free best)
        pg = (1 + sum(1 for b in nb_sc if b >= sc - 1e-12)) / (1 + len(nb_sc)) if nb_sc else float("nan")
        root = path_stats(path, d, A, F, m, hop, args.xmin, shape, pg, args.alpha, 1)
        used = [root]
        seq = [(root, k) for k in range(root["length"])]
    else:
        root = path_stats(p0, d0, A, F, m, hop, args.xmin, shape, pval, args.alpha, 1)
        used = [root]
        if args.mode == "lineage":
            seq = [(root, k) for k in range(root["length"])]
        elif args.mode == "montage":
            banned = overlapping(p0)
            while len(used) < args.n_lineages:
                sc, d, path = path_best(A, directions, args.tolerance, banned=banned)
                if len(path) < 2:
                    break
                used.append(path_stats(path, d, A, F, m, hop, args.xmin, shape, float("nan"), args.alpha,
                                       len(used) + 1))
                banned |= overlapping(path)
            for g in range(max(s["length"] for s in used)):
                for s in used:
                    if g < s["length"]:
                        seq.append((s, g))
            info["montage_lineages"] = len(used)
            if len(used) < args.n_lineages:
                info["note"] = "only %d separate path(s) in this recording" % len(used)
        elif args.mode == "branching":
            # a branch leaves the root path at one of its gestures (the fork)
            # and continues through gestures the root does not use
            # branch search on distinct-gesture links: otherwise a fork's K
            # nearest later windows are copies of the root's next gesture
            Ab = dict(A)
            Ab["links"], _t, _n = build_links(A["D"], A["starts"], m, args.k_links, args.tolerance, distinct=True)
            banned_root = overlapping(p0)
            forks = []
            taken = set()
            for _ in range(args.n_lineages - 1):
                best = None
                for k, w in enumerate(p0[:-1]):
                    ban = (banned_root | taken) - {w}
                    sc, d, path = path_best(Ab, directions, args.tolerance, banned=ban, start=w)
                    if len(path) >= 3 and (best is None or sc > best[0]):     # 2+ gestures past the fork
                        best = (sc, d, path, k)
                if best is None:
                    break
                sc, d, path, k = best
                tail = path[1:]
                br = path_stats(tail, d, A, F, m, hop, args.xmin, shape, float("nan"), args.alpha,
                                len(used) + 1) if len(tail) >= 1 else None
                if br is None:
                    break
                c_fork = float(A["D"][path[0], path[1]] / A["typ"])
                forks.append((c_fork, k, br))
                used.append(br)
                taken |= overlapping(tail)
            info["branch_root_ratios"] = [round(c, 4) for c, _, _ in forks]
            info["branch_fork_generations"] = [k + 1 for _, k, _ in forks]
            if not forks:
                info["note"] = "no path leaves this one through gestures it does not use: a single path"
            seq = [(root, k) for k in range(root["length"])]
            for _, k, br in forks:
                seq.append((root, k))
                seq += [(br, g) for g in range(br["length"])]
        else:
            raise ValueError(args.mode)
    if args.order == "backward":
        if args.mode == "montage":
            seq = seq[::-1]
        else:
            seq2 = []
            for s in used:
                seq2 += [(s, k) for k in range(s["length"] - 1, -1, -1)]
            seq = seq2
    rows = plan_rows(seq, win_s, args.order, args.gap_mode, args.gap_scale, args.max_output)
    # ---- display feature: the matched one, or (all three) the target's / most changing one ----
    if disp is None:
        tf = DIRECTIONS[root["direction"]][0]
        if tf is None:
            sc_f = {f: abs(root.get(f + "_change", 0.0) or 0.0) / PATH_REF[f] for f in PATH_FEATS}
            tf = max(sc_f, key=sc_f.get)
        disp = tf
    st_out["feature_used"] = disp
    tgrid = args.xmin + (np.arange(F["n"]) + 0.5) * hop
    tt, vv = decimate(tgrid, F[disp])
    with open(P + "_traj.tsv", "w") as f:
        f.write("time\tvalue\n")
        for a_, b_ in zip(tt, vv):
            f.write("%s\t%s\n" % (fmt(a_), fmt(b_)))
    near = np.where(np.isfinite(A["nearest"]), A["nearest"], np.nan)
    # every stride position, undefined where no candidate window (gaps stay visible)
    pos = np.arange(0, F["n"] - m + 1, A["stride"])
    full = np.full(len(pos), np.nan)
    full[np.searchsorted(pos, starts)] = near
    tt, pp = decimate(args.xmin + (pos + m / 2.0) * hop, full)
    with open(P + "_mp.tsv", "w") as f:
        f.write("time\tP\n")
        for a_, b_ in zip(tt, pp):
            f.write("%s\t%s\n" % (fmt(a_), fmt(b_)))
    with open(P + "_lineages.tsv", "w") as f:
        f.write("id\tlength\tkind\tdirection\tp\tsignificant\tworst_link_ratio\tmean_link_corr\tend_corr\t"
                "drift_ratio\tmonotonicity\tspan_s\tfirst_start\tlast_start\tacoustic_trend\tacoustic_detail\n")
        for s_ in used:
            mc = float(np.mean(s_["link_corr"])) if s_["link_corr"] else float("nan")
            f.write("\t".join([str(s_["id"]), str(s_["length"]), s_["kind"], s_["direction"], fmt(s_["p"], 4),
                               "1" if s_["significant"] else "0", fmt(s_["worst_link_ratio"], 4), fmt(mc, 4),
                               fmt(s_["end_corr"], 4), fmt(s_["drift_ratio"], 4), fmt(s_["drift_monotonicity"], 4),
                               fmt(s_["span_s"], 4), fmt(s_["start_times"][0], 4), fmt(s_["start_times"][-1], 4),
                               s_.get("acoustic_trend", "-"), s_.get("acoustic_detail", "") or "-"]) + "\n")
    with open(P + "_members.tsv", "w") as f:
        f.write("lineage\tgeneration\tstart\tend\tP\n")
        for s_ in used:
            for k, (t0, w) in enumerate(zip(s_["start_times"], s_["windows"])):
                f.write("%d\t%d\t%s\t%s\t%s\n" % (s_["id"], k + 1, fmt(t0), fmt(t0 + win_s), fmt(near[w])))
    with open(P + "_plan.tsv", "w") as f:
        f.write(plan_header)
        for r in rows:
            f.write("\t".join([fmt(r["src_start"]), fmt(r["src_end"]), str(r["lineage"]), str(r["generation"]),
                               fmt(r["silence_before"]), fmt(r["link_ratio"], 4), fmt(r["link_corr"], 4)]) + "\n")
    for k, v in info.items():
        st_out[k] = v
    s_ = used[0]
    sh = plan or {}
    st_out.update({
        "n_windows": A["n_positions"], "n_gesture_windows": n_win, "n_flat_windows": 0,
        "n_undefined_windows": A["n_positions"] - n_win, "mp_median": A["typ"], "mp_max_possible": 2 * math.sqrt(m),
        "n_lineages": len(used), "n_pairs": 0, "n_significant": int(bool(s_["significant"])),
        "shuffle_blocks": sh.get("n_blocks", 0), "shuffle_exact": int(bool(sh.get("exact"))),
        "shuffle_versions": len(nb_sc), "min_possible_p": sh.get("min_p", float("nan")),
        "test_possible": int(test_possible),
        "null_longest_median": float(np.median(nb_len)) if nb_len else float("nan"),
        "null_longest_max": max(nb_len) if nb_len else 0,
        "null_score_median": float(np.median(nb_sc)) if nb_sc else float("nan"),
        "path_score": sc0, "best_p_fwer": pval,
        "sel_id": 1, "sel_length": s_["length"], "sel_kind": s_["kind"], "sel_direction": s_["direction"],
        "sel_p": s_["p"], "sel_p_fwer": s_["p"], "sel_significant": int(bool(s_["significant"])),
        "sel_worst_link_ratio": s_["worst_link_ratio"],
        "sel_mean_link_corr": float(np.mean(s_["link_corr"])) if s_["link_corr"] else float("nan"),
        "sel_min_link_corr": float(np.min(s_["link_corr"])) if s_["link_corr"] else float("nan"),
        "sel_end_corr": s_["end_corr"], "sel_drift_ratio": s_["drift_ratio"],
        "sel_monotonicity": s_["drift_monotonicity"], "sel_span_s": s_["span_s"],
        "sel_first_start": s_["start_times"][0], "sel_last_start": s_["start_times"][-1],
        "used_lineages": len(used),
        "sel_acoustic_trend": s_.get("acoustic_trend", "stable"),
        "sel_acoustic_detail": s_.get("acoustic_detail", ""),
        "sel_acoustic_score": s_.get("acoustic_drift_score", 0.0),
        "sel_acoustic_confidence": s_.get("acoustic_confidence", "-"),
        "sel_overlap_fraction": 0.0,
        "sel_mean_link_dist": float(np.mean(s_["link_dist"])) if s_["link_dist"] else float("nan"),
        "plan_rows": len(rows),
        "planned_duration": sum(r["silence_before"] + (r["src_end"] - r["src_start"]) for r in rows),
    })
    notes = [x for x in (st_out.get("phrase_fallback", ""), " | ".join(adapt), info.get("note", "")) if x]
    if not args.allow_weak and not s_["significant"]:
        # Strict: no Sound unless the path's order is beyond chance
        for name in ("_plan.tsv",):
            with open(P + name, "w") as f:
                f.write(plan_header)
        if not test_possible:
            finish("insufficient", "INSUFFICIENT DATA: the order evidence cannot reach p <= %.2f here (Strict: "
                   "no Sound)" % args.alpha)
        else:
            finish("no_lineage", "the best path's order is not beyond chance (p = %.3f); untick 'Strict' to "
                   "hear it anyway" % s_["p"])
        return
    if not rows:
        unchanged("no path could be built")
        return
    if s_["significant"]:
        finish("ok", " | ".join(notes))
    elif not test_possible:
        msg = ("INSUFFICIENT DATA: this Sound allows only %d reordering(s) at %.2f s windows, so the order "
               "evidence cannot reach p <= %.2f; the path is built anyway" % (len(nb_sc), win_s, args.alpha)
               if nb_sc else ("NOT TESTED: Surrogates = 0, so the order test was not run; the path is built"
                              if args.surrogates <= 0 else
                              "INSUFFICIENT DATA: too few blocks to shuffle; the path is built anyway"))
        finish("insufficient", " | ".join([msg] + notes))
    else:
        finish("exploratory", " | ".join(["EXPLORATORY: path built; its order is not beyond chance "
                                          "(p = %.3f); %d gestures" % (s_["p"], s_["length"])] + notes))


# ================================================================ phrases (v2.1)
# Phrase-aware analysis: variable-duration phrases instead of fixed windows.
#
# SEGMENTATION adapts Sonic Syntax v2.2.1 (silence-based boundaries) and adds
# acoustic-change boundaries for continuous material:
#   pause threshold   Sonic Syntax TUNING 2 (loudness quantiles q10/q25/q95,
#                     three dynamic-range classes), clamped to
#                     [floor + 3 dB, q95 - 10 dB] (on digital silence q25 can
#                     sit at the floor, so 'q25 - 5' found no pause at all)
#   pauses            runs below the threshold >= 0.05 s; sounding islands
#                     shorter than min(0.12, max(0.05, 0.25 x min phrase))
#                     are merged into the pause (Sonic Syntax PHASE 1)
#   pause evidence    2 sqrt(depthN x lenN) + edge x lenN (Sonic Syntax PHASE 2:
#                     depthN = clip((drop - 3) / 15), edge = clip(min(drop
#                     before, drop after) / 12); drops over 0.15 s each side).
#                     MODIFIED: lenN = clip((dur - articulation) / 0.5) with
#                     articulation = 2 x the median of the recording's gaps
#                     under min(0.25 s, half the longest pause) (3+ of them),
#                     at most 0.35 s, else 0, and
#                     edge weighted by lenN - Sonic Syntax's
#                     absolute lenN and additive edge made every articulation
#                     gap a boundary (measured: precision 0.38 on phrases
#                     with internal pauses). Pause threshold also <= median
#                     level - 6 dB, never below the silence floor + 3 dB
#   change evidence   NEW. Foote-style novelty of TEXTURE statistics over
#                     0.6 s (mean and spread of loudness, mean centroid and
#                     flatness over sounding cells, mean spectral flux, the
#                     sounding share), kernel half-width = half the minimum
#                     phrase; normalised per recording by median and MAD;
#                     evidence = clip((z - 2) / 4) x 2; the cut is
#                     snapped to the loudness minimum in the 80 ms before the
#                     peak so it does not split an attack
#   selection         Sonic Syntax PHASE 3 dynamic programming (score =
#                     evidence - 0.75 + (bias - 50) / 60, minimum spacing)
#                     plus a soft MAXIMUM phrase duration (penalty
#                     (gap - max) / max), with virtual start and end nodes
#                     at the first and last sounding cell (silence at the
#                     ends never counts toward a phrase's duration),
#                     so 'no boundary' remains a valid answer
#   phrase interval   a pause boundary ends the phrase where the pause BEGINS
#                     and starts the next where it ENDS (Sonic Syntax cuts at
#                     the pause midpoint); leading/trailing silence is trimmed,
#                     with 20 ms kept before the first sounding cell; pauses
#                     not chosen as boundaries stay inside their phrase
# Pitch motion (Sonic Syntax component 1) is not used: the engine has no
# pitch tracker and the evidence is optional for this material.
PHRASE_SELECTION_COST = 0.75
PHRASE_PAD_S = 0.02


def _runs(mask):
    """(start, end) index pairs of True runs, end exclusive."""
    out, i, n = [], 0, len(mask)
    while i < n:
        if mask[i]:
            j = i
            while j < n and mask[j]:
                j += 1
            out.append((i, j))
            i = j
        else:
            i += 1
    return out


def _robust_z(x):
    x = np.asarray(x, float)
    ok = np.isfinite(x)
    if not ok.any():
        return np.zeros_like(x)
    med = float(np.median(x[ok]))
    mad = float(np.median(np.abs(x[ok] - med))) * 1.4826
    if mad < 1e-12:
        sd = float(np.std(x[ok]))
        mad = sd if sd > 1e-12 else 1.0
    return np.where(ok, (x - med) / mad, 0.0)


def pause_threshold(loud, floor_db):
    """Sonic Syntax TUNING 2 on the engine's loudness (dBFS), clamped."""
    q10, q25, q95 = (float(np.percentile(loud, q)) for q in (10, 25, 95))
    rng = q95 - q10
    if rng > 30:
        thr, kind = q25 - 5, "high dynamic range"
    elif rng > 15:
        thr, kind = (q10 + q25) / 2, "moderate dynamic range"
    else:
        thr, kind = q10 + 0.3 * rng, "compressed"
    q50 = float(np.percentile(loud, 50))
    # a pause lies clearly below the typical level (continuous textures:
    # tremolo dips and grain gaps are not pauses)
    # v2.1.1: the floor clamp comes LAST - when silence dominates, the median
    # level is the floor and 'median - 6' put the threshold below it
    thr = max(min(thr, q95 - 10.0, q50 - 6.0), floor_db + 3.0)
    return thr, kind, rng


def _moving_mean(v, k, valid=None):
    """Centred moving mean over k cells, ignoring invalid cells (NaN where a
    window holds no valid cell)."""
    v = np.asarray(v, float)
    ok = np.isfinite(v) if valid is None else (valid & np.isfinite(v))
    x = np.where(ok, v, 0.0)
    ker = np.ones(k)
    num = np.convolve(x, ker, mode="same")
    den = np.convolve(ok.astype(float), ker, mode="same")
    with np.errstate(invalid="ignore", divide="ignore"):
        return np.where(den > 0, num / np.maximum(den, 1e-12), np.nan)


def texture_features(F, w_s):
    """Local texture statistics over w_s seconds (centred): mean level and
    level spread (graininess / articulation), mean centroid and flatness over
    the sounding cells, mean spectral flux (activity) and the sounding share.
    Phrase boundaries in continuous material are changes of texture, not of
    single events."""
    hop = F["hop_s"]
    k = max(3, int(round(w_s / hop)))
    snd = ~np.asarray(F["silent"], bool)
    L = np.asarray(F["loudness"], float)
    lm = _moving_mean(L, k)
    lsd = np.sqrt(np.maximum(_moving_mean(L * L, k) - lm * lm, 0.0))
    cols = [lm, lsd, _moving_mean(F["centroid"], k, snd), _moving_mean(F["flatness"], k, snd),
            _moving_mean(F["flux"], k), _moving_mean(snd.astype(float), k)]
    out = []
    for c in cols:
        c = c.copy()
        ok = np.isfinite(c)
        if ok.sum() >= 2:
            x = np.arange(len(c))
            c = np.interp(x, x[ok], c[ok])
        else:
            c = np.zeros(len(c))
        out.append(c)
    return np.stack(out, axis=1)


def novelty_curve(F, h, w_s=0.3):
    """Foote-style novelty of the texture features: distance between the mean
    (robust-standardised) texture vector of the h cells before and the h cells
    after each cell."""
    n = F["n"]
    T = texture_features(F, w_s)
    X = np.stack([_robust_z(T[:, j]) for j in range(T.shape[1])], axis=1)
    X = np.clip(X, -6, 6)
    nov = np.zeros(n)
    if n < 2 * h + 2:
        return nov
    cs = np.concatenate([np.zeros((1, X.shape[1])), np.cumsum(X, axis=0)])
    i = np.arange(h, n - h)
    a = (cs[i] - cs[i - h]) / h
    b = (cs[i + h] - cs[i]) / h
    nov[h:n - h] = np.sqrt(np.mean((a - b) ** 2, axis=1))
    return nov


def segment_phrases(F, xmin, min_phrase=0.0, max_phrase=0.0, evidence="both", bias=50.0,
                    kernel_factor=0.5, texture_s=0.6, z0=2.0, art_factor=2.0, max_default=12.0):
    """Automatic phrase boundaries. Returns (phrases, report).
    phrases: list of dicts with cells [c0, c1) and times; report: settings,
    candidates (with evidence, chosen or not) and notes."""
    hop = F["hop_s"]
    n = F["n"]
    loud = np.asarray(F["loudness"], float)
    snd_mask = ~np.asarray(F["silent"], bool)
    notes = []
    # ---- adaptive minimum / maximum phrase duration ----
    if min_phrase <= 0:
        # Sonic Syntax TUNING 4 (spacing of intensity peaks), scaled from a
        # gesture spacing to a phrase spacing: 2.5 x the median peak interval
        pk = []
        lv = loud
        for i in range(1, n - 1):
            if lv[i] > lv[i - 1] and lv[i] >= lv[i + 1]:
                lo = max(0, i - int(round(1.0 / hop)))
                if lv[i] - lv[lo:i + 1].min() >= (6.0 if lv.max() - lv.min() > 20 else 3.0):
                    if not pk or (i - pk[-1]) * hop >= 0.15:
                        pk.append(i)
        med = float(np.median(np.diff(pk)) * hop) if len(pk) > 2 else 0.5
        min_phrase = float(min(3.0, max(0.8, 2.5 * med)))
        notes.append("minimum phrase %.2f s (adaptive: 2.5 x median intensity-peak spacing %.2f s)" % (min_phrase, med))
    if max_phrase <= 0:
        max_phrase = float(max(4 * min_phrase, max_default))
    max_phrase = max(max_phrase, 2 * min_phrase)
    total = n * hop
    cands = []                      # dict: cell, kind, evidence, (pause start/end cells)
    # ---- A. pauses ----
    thr, dyn, rng = pause_threshold(loud, F["silence_threshold_db"])
    if evidence in ("both", "silence"):
        quiet = loud < thr
        island = max(1, int(round(min(0.12, max(0.05, 0.25 * min_phrase)) / hop)))
        for a, b in _runs(~quiet):                                  # merge short sounding islands
            if (b - a) < island and a > 0 and b < n:
                quiet[a:b] = True
        mins = max(1, int(round(0.05 / hop)))
        w15 = max(1, int(round(0.15 / hop)))
        pr = [(a, b) for a, b in _runs(quiet) if b - a >= mins and a > 0 and b < n]
        # relative pause length: most pauses of a recording are articulations;
        # a structural pause is long compared with them (Sonic Syntax used an
        # absolute 0.5 s, which counts every articulation gap as evidence)
        durs = np.array([(b - a) * hop for a, b in pr])
        # v2.1.1: the articulation reference comes from the SHORT gaps only
        # (under 0.25 s and under half the longest pause, at least 3 of them): 2 x their median, at most 0.35 s.
        # Without such gaps every pause may be structural and Sonic Syntax's
        # absolute length rule applies (art = 0). v2.1 used the median of ALL
        # pauses, so 7 equal structural pauses scored zero (fifth review).
        # a gap is short only next to longer ones: equal pauses cannot be told
        # apart by length, so none of them is articulation
        short = durs[durs < min(0.25, 0.5 * float(durs.max()))] if len(durs) else durs
        art = min(art_factor * float(np.median(short)), 0.35) if len(short) >= 3 else 0.0
        for a, b in pr:
            lin = 10 ** (loud[a:b] / 10)
            at = 10 * np.log10(lin.mean())
            pre = 10 * np.log10(np.mean(10 ** (loud[max(0, a - w15):a] / 10))) if a > 0 else None
            post = 10 * np.log10(np.mean(10 ** (loud[b:min(n, b + w15)] / 10))) if b < n else None
            dpre = max(0.0, pre - at) if pre is not None else 0.0
            dpost = max(0.0, post - at) if post is not None else 0.0
            depth = (dpre + dpost) / 2
            depth_n = min(max((depth - 3.0) / 15.0, 0.0), 1.0)
            len_n = min(max(((b - a) * hop - art) / 0.5, 0.0), 1.0)
            # edge contrast weighted by the relative length: an articulation
            # gap is bracketed by sound too, but is no boundary
            ev = 2.0 * math.sqrt(depth_n * len_n) + min(min(dpre, dpost) / 12.0, 1.0) * len_n
            cands.append({"cell": (a + b) // 2, "kind": "pause", "evidence": ev, "a": a, "b": b,
                          "pause_s": (b - a) * hop, "depth_db": depth, "articulation_s": art})
    # ---- B. acoustic change ----
    nov = None
    if evidence in ("both", "change"):
        h = max(2, int(round(kernel_factor * min_phrase / hop)))
        nov = novelty_curve(F, h, texture_s)
        z = _robust_z(nov)
        sidx = np.where(snd_mask)[0]
        first_s, last_s = (int(sidx[0]), int(sidx[-1])) if len(sidx) else (0, n)
        for i in range(h, n - h):
            if i < first_s + h or i > last_s - h:        # the recording starting / ending is no boundary
                continue
            if z[i] < z0 or z[i] < z[max(0, i - h):i + h + 1].max():
                continue
            if not snd_mask[max(0, i - h):i + h].any():
                continue
            ev = 2.0 * min(max((z[i] - z0) / 4.0, 0.0), 1.0)
            lo = max(0, i - int(round(0.08 / hop)))
            c = lo + int(np.argmin(loud[lo:i + 1]))                 # do not cut through the attack
            # a change inside (or within 0.1 s of) a STRUCTURAL pause is that
            # pause; articulation gaps (no pause evidence) do not absorb it
            near = [k for k, q in enumerate(cands) if q["kind"] == "pause" and q["evidence"] > 0
                    and q["a"] - int(0.1 / hop) <= c <= q["b"] + int(0.1 / hop)]
            if near:
                q = cands[near[0]]
                q["evidence"] = max(q["evidence"], ev)
                q["also_change"] = True
                continue
            cands.append({"cell": c, "kind": "change", "evidence": ev, "a": c, "b": c, "z": float(z[i])})
    # articulation gaps carry no evidence: they stay inside phrases unless a
    # phrase would exceed the maximum duration (then the DP may use the
    # weakest-cost gap rather than none)
    cands.sort(key=lambda q: q["cell"])
    # ---- C. selection by dynamic programming ----
    bias_term = (min(max(bias, 0.0), 100.0) - 50.0) / 60.0
    # v2.1.2: the virtual start and end nodes sit at the first and last
    # SOUNDING cell, so leading or trailing silence never counts toward a
    # phrase's duration (v2.1.1 measured the last phrase to the file's end:
    # 10 s of trailing silence made a zero-evidence cut pay off - sixth review)
    sidx = np.where(snd_mask)[0]
    padc = int(round(PHRASE_PAD_S / hop))           # keep the 20 ms margin before the first / after the last sound
    s_first, s_end = (max(0, int(sidx[0]) - padc), min(n, int(sidx[-1]) + 1 + padc)) if len(sidx) else (0, n)
    nodes = [{"cell": s_first, "a": s_first, "b": s_first, "score": 0.0}] + \
            [dict(q, score=q["evidence"] - PHRASE_SELECTION_COST + bias_term) for q in cands
             if s_first < q["cell"] < s_end] + \
            [{"cell": s_end, "a": s_end, "b": s_end, "score": 0.0}]
    N = len(nodes)
    best = np.full(N, -np.inf)
    prev = -np.ones(N, dtype=int)
    best[0] = 0.0
    for v in range(1, N):
        for u in range(v):
            if not np.isfinite(best[u]):
                continue
            # phrase = from the END of boundary u (pause end) to the START of v
            span = (nodes[v]["a"] - nodes[u]["b"]) * hop
            if span < min_phrase - 1e-9 and not (u == 0 and v == N - 1):
                continue
            pen = (span - max_phrase) / max_phrase if span > max_phrase else 0.0
            sc = best[u] + nodes[v]["score"] - pen
            if sc > best[v]:
                best[v] = sc
                prev[v] = u
    chain, k = [], N - 1
    while k > 0:
        chain.append(k)
        k = prev[k]
    chain = [0] + chain[::-1]
    chosen = set(chain[1:-1])
    for i, q in enumerate(nodes[1:-1], start=1):
        q["chosen"] = i in chosen
    # ---- D. phrase intervals ----
    phrases = []
    for u, v in zip(chain[:-1], chain[1:]):
        c0, c1 = nodes[u]["b"], nodes[v]["a"]
        s = np.where(snd_mask[c0:c1])[0]
        if len(s) == 0:
            continue
        pad = int(round(PHRASE_PAD_S / hop))
        a = max(c0, c0 + int(s[0]) - pad)
        b = min(c1, c0 + int(s[-1]) + 1 + pad)
        phrases.append({"c0": a, "c1": b, "t0": xmin + a * hop, "t1": xmin + b * hop,
                        "boundary_before": nodes[u].get("kind", "start"),
                        "evidence_before": nodes[u].get("evidence", float("nan")),
                        "boundary_after": nodes[v].get("kind", "end"),
                        "evidence_after": nodes[v].get("evidence", float("nan"))})
    if len(chain) == 2:
        notes.append("no credible boundary: the recording is one phrase (%d candidate(s) rejected)" % len(cands))
    long_ = [p for p in phrases if (p["c1"] - p["c0"]) * hop > max_phrase]
    if long_:
        notes.append("%d phrase(s) longer than the maximum %.1f s: no credible boundary inside them"
                     % (len(long_), max_phrase))
    rep = {"min_phrase": min_phrase, "max_phrase": max_phrase, "pause_threshold_db": thr,
           "dynamics": dyn, "dynamic_range_db": rng, "evidence": evidence, "bias": bias,
           "candidates": [q for q in nodes[1:-1]], "novelty": nov, "notes": notes,
           "n_pause_candidates": sum(1 for q in cands if q["kind"] == "pause"),
           "n_change_candidates": sum(1 for q in cands if q["kind"] == "change")}
    return phrases, rep


# ---------------------------------------------------------------- phrase units
# Representation of variable-duration phrases (analysis only: the audio is
# never stretched or resampled). Each phrase keeps its source interval,
# duration, sounding share and internal pauses; its three feature
# trajectories are resampled to a shared grid of PHRASE_GRID points over the
# phrase's own time span. Centroid and flatness are bridged across internal
# pauses (they do not exist in silence); loudness keeps the pauses, so the
# articulation stays visible in the contour.
PHRASE_GRID = 48
PHRASE_K = 5                 # mutual K nearest links between phrases (gesture windows: PATH_K = 3)
PHRASE_W_DURATION = 0.5      # distance added per doubling of duration
PHRASE_W_ARTICULATION = 1.0  # distance added per 0.5 difference of silent share


def phrase_units(F, phrases):
    hop = F["hop_s"]
    ff = fill_gaps(F)
    snd = ~np.asarray(F["silent"], bool)
    units = []
    for p in phrases:
        c0, c1 = int(p["c0"]), int(p["c1"])
        if c1 - c0 < 3:
            continue
        u = dict(p)
        u["dur"] = (c1 - c0) * hop
        u["sounding_share"] = float(snd[c0:c1].mean())
        u["internal_pauses"] = sum(1 for a, b in _runs(~snd[c0:c1]) if a > 0 and b < c1 - c0 and (b - a) * hop >= 0.05)
        x = np.linspace(0.0, c1 - c0 - 1, PHRASE_GRID)
        for f in PATH_FEATS:
            v = np.asarray(ff[f + "_filled"][c0:c1], float)
            if not np.isfinite(v).all():
                ok = np.isfinite(v)
                v = np.interp(np.arange(len(v)), np.where(ok)[0], v[ok]) if ok.any() else np.zeros(len(v))
            u["traj_" + f] = np.interp(x, np.arange(c1 - c0), v)
            sv = np.asarray(F[f], float)[c0:c1][snd[c0:c1]]
            sv = sv[np.isfinite(sv)]
            u["mean_" + f] = float(sv.mean()) if len(sv) else float("nan")
        u["activity"] = float(np.mean(F["flux"][c0:c1]))
        units.append(u)
    return units


def phrase_distance(units, use, shape=True, w_dur=PHRASE_W_DURATION, w_art=PHRASE_W_ARTICULATION):
    """Distance matrix between phrases and its parts.
    main: RMS over the used features of the per-point trajectory distance -
      Shape: z-normalised contours (0 = same contour, ~1.4 = unrelated,
      2 = opposite; a flat contour counts as all-zero); Absolute: raw
      trajectories in audible reference units (0.5 oct, 3 dB, 0.25 log10).
    duration: |log2(d_i / d_j)|; articulation: |silent share difference|.
    D = sqrt(main^2 + (w_dur x duration)^2 + (w_art x articulation / 0.5)^2):
    normalising the time axis never erases duration or articulation."""
    P = len(units)
    D2 = np.zeros((P, P))
    for f in use:
        X = np.stack([u["traj_" + f] for u in units])
        if shape:
            mu = X.mean(axis=1, keepdims=True)
            sd = X.std(axis=1, keepdims=True)
            Z = np.where(sd >= FLAT_STD[f], (X - mu) / np.where(sd > 0, sd, 1), 0.0)
        else:
            Z = X / PATH_REF[f]
        nn = (Z * Z).sum(axis=1)
        D2 += np.maximum(nn[:, None] + nn[None, :] - 2 * Z @ Z.T, 0.0) / PHRASE_GRID
    main = np.sqrt(D2 / len(use))
    dur = np.array([u["dur"] for u in units])
    sil = np.array([1 - u["sounding_share"] for u in units])
    ddur = np.abs(np.log2(dur[:, None] / dur[None, :]))
    dart = np.abs(sil[:, None] - sil[None, :])
    D = np.sqrt(main ** 2 + (w_dur * ddur) ** 2 + (w_art * dart / 0.5) ** 2)
    np.fill_diagonal(D, 0.0)
    return D, {"main": main, "duration": ddur, "articulation": dart}


# ---------------------------------------------------------------- phrase paths
# The Evolution Path engine on phrases: the same links (mutual K nearest in
# time order, within tol x typical), the same exact dynamic programming and
# directions, on the phrase-by-phrase distance matrix.
# NULL MODEL (phrase level): the order of the SAME phrases is permuted (all
# permutations when few, else random ones) and the full search (links, path,
# best direction) is repeated; p = (1 + #orders scoring >= the recording's) /
# (1 + #orders). It asks whether the recording's phrase ORDER holds more
# continuous, directed development than random orders of its own phrases.
# The cell-block shuffle of the window engine is not used: it would cut
# phrases apart. Calibration: technical report s14.


def read_phrase_tsv(path, F, xmin, labelled_only=True):
    """Intervals from a TextGrid tier (written by the Praat script: start,
    end, label). Returns (phrases, notes). Intervals are clipped to the Sound,
    sorted; unlabelled intervals are skipped unless none is labelled;
    intervals shorter than 0.1 s, less than 20% sounding, or overlapping an
    earlier one are skipped - each case is counted and reported."""
    hop, n = F["hop_s"], F["n"]
    snd = ~np.asarray(F["silent"], bool)
    rows = []
    with open(path, encoding="utf-8") as f:
        f.readline()
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 2:
                continue
            t0, t1 = float(parts[0]), float(parts[1])
            lab = parts[2].strip() if len(parts) > 2 else ""
            rows.append((t0, t1, lab))
    notes = []
    lab_rows = [r for r in rows if r[2]]
    if labelled_only and lab_rows:
        if len(lab_rows) < len(rows):
            notes.append("%d unlabelled interval(s) skipped (pauses between phrases)" % (len(rows) - len(lab_rows)))
        rows = lab_rows
    elif labelled_only:
        notes.append("no interval is labelled: all %d intervals are used" % len(rows))
    rows.sort()
    out, short, silent, over, clipped = [], 0, 0, 0, 0
    end_prev = -np.inf
    for t0, t1, lab in rows:
        a0, a1 = max(t0, xmin), min(t1, xmin + n * hop)
        if (a0, a1) != (t0, t1):
            clipped += 1
        if a1 - a0 < 0.1:
            short += 1
            continue
        if a0 < end_prev - 1e-9:
            over += 1
            continue
        c0, c1 = int(round((a0 - xmin) / hop)), int(round((a1 - xmin) / hop))
        if c1 <= c0 or snd[c0:c1].mean() < 0.2:        # (mostly) silent: a pause, not a phrase
            silent += 1
            continue
        out.append({"c0": c0, "c1": c1, "t0": xmin + c0 * hop, "t1": xmin + c1 * hop, "label": lab,
                    "boundary_before": "textgrid", "boundary_after": "textgrid",
                    "evidence_before": float("nan"), "evidence_after": float("nan")})
        end_prev = a1
    for k, msg in ((clipped, "clipped to the Sound"), (short, "shorter than 0.1 s, skipped"),
                   (silent, "silent (under 20% sounding), skipped"), (over, "overlapping an earlier interval, skipped")):
        if k:
            notes.append("%d interval(s) %s" % (k, msg))
    return out, notes


def phrase_links(D, K, tol):
    """Mutual K nearest links in time order between phrases (index order)."""
    P = len(D)
    idx = np.arange(P)
    return build_links(D, idx, 1, K, tol)


def phrase_analysis(units, use, shape, K, tol):
    D, parts = phrase_distance(units, use, shape)
    links, typ, nearest = phrase_links(D, K, tol)
    mu = {f: np.array([u["mean_" + f] for u in units]) / PATH_REF[f] for f in PATH_FEATS}
    for f in PATH_FEATS:                       # undefined mean (no sounding cell) -> no progress either way
        bad = ~np.isfinite(mu[f])
        if bad.any():
            mu[f][bad] = np.nanmedian(mu[f]) if np.isfinite(mu[f]).any() else 0.0
    return {"D": D, "parts": parts, "links": links, "typ": typ, "nearest": nearest, "mu": mu,
            "starts": np.arange(len(units))}


def phrase_null(A, directions, observed, n_surr, seed, K, tol):
    """Phrase-order permutation test. Returns (p, scores, lengths, exact,
    number of orders, smallest possible p)."""
    P = len(A["D"])
    total = math.factorial(P) if P <= 12 else None
    rng = np.random.default_rng(seed)
    if total is not None and total - 1 <= n_surr:
        import itertools
        orders = [np.array(o) for o in itertools.permutations(range(P))][1:]
        exact = True
    else:
        orders = []
        seen = set()
        while len(orders) < n_surr:
            o = rng.permutation(P)
            key = tuple(o)
            if key in seen or key == tuple(range(P)):
                continue
            seen.add(key)
            orders.append(o)
        exact = False
    scores, lens = [], []
    for o in orders:
        Dp = A["D"][np.ix_(o, o)]
        links, _t, _n = phrase_links(Dp, K, tol)
        mu = {f: A["mu"][f][o] for f in PATH_FEATS}
        sc, d, p = path_best({"links": links, "mu": mu}, directions, tol)
        scores.append(sc)
        lens.append(len(p))
    if not scores:
        return float("nan"), [], [], exact, 0, float("nan")
    hits = sum(1 for b in scores if b >= observed - 1e-12)
    return (1 + hits) / (1 + len(scores)), scores, lens, exact, len(scores), 1.0 / (1 + len(scores))


def phrase_stats(path, direction, A, units, p, alpha, sid):
    D, typ = A["D"], A["typ"]
    links = [float(D[a, b]) for a, b in zip(path[:-1], path[1:])]
    main = A["parts"]["main"]
    end = float(D[path[0], path[-1]]) if len(path) > 1 else 0.0
    mean_link = float(np.mean(links)) if links else 0.0
    ff = [float(D[path[0], k]) for k in path]
    mono = float(np.corrcoef(np.arange(len(path)), ff)[0, 1]) if len(path) >= 3 and np.std(ff) > 0 else 0.0
    st = {
        "id": sid, "length": len(path), "windows": list(path), "members": [int(units[k]["c0"]) for k in path],
        "start_times": [units[k]["t0"] for k in path], "durations": [units[k]["dur"] for k in path],
        "link_dist": links, "link_ratio": [d / typ for d in links],
        "worst_link_ratio": max([d / typ for d in links]) if links else 0.0,
        "end_to_end_norm": end / 2.0, "drift_ratio": end / mean_link if mean_link > 1e-12 else 0.0,
        "drift_monotonicity": mono,
        "span_s": units[path[-1]]["t0"] - units[path[0]]["t0"],
        # mean shape correlation over the features = 1 - main^2 / 2 (per-point z distance)
        "link_corr": [1 - float(main[a, b]) ** 2 / 2 for a, b in zip(path[:-1], path[1:])],
        "end_corr": 1 - float(main[path[0], path[-1]]) ** 2 / 2,
        "p": p, "p_fwer": p, "significant": bool(p == p and p <= alpha), "overlap_fraction": 0.0,
        "direction": direction,
        "duration_ratio_max": max(units[k]["dur"] for k in path) / min(units[k]["dur"] for k in path),
    }
    # sound change of the path: phrase means (sounding cells), per generation
    for f in PATH_FEATS:
        v = np.array([units[k]["mean_" + f] for k in path], float)
        ok = np.isfinite(v)
        if ok.sum() >= 2:
            st[f + "_change"] = float(v[ok][-1] - v[ok][0])
            st[f + "_rho"] = float(spearmanr_safe(np.arange(len(v))[ok], v[ok]))
    feat, sign = DIRECTIONS[direction]
    st["acoustic_trend"], st["acoustic_confidence"], st["acoustic_drift_score"] = "stable", "-", 0.0
    unit_of = {"centroid": "oct", "loudness": "dB", "flatness": "log10"}
    if feat is not None and st.get(feat + "_change") is not None:
        ch, rho = st[feat + "_change"], st.get(feat + "_rho", 0.0)
        strength = abs(rho) * min(1.0, abs(ch) / PATH_REF[feat])
        st["acoustic_drift_score"] = strength
        if sign * ch > 0 and strength >= 0.5:
            st["acoustic_trend"] = DIRECTION_WORD[direction]
            st["acoustic_confidence"] = "target"
        st["acoustic_detail"] = ("target %s: %s %s %.2f %s over %d phrases (rho %+.2f)%s" % (
            DIRECTION_WORD[direction], feat, "rises" if ch > 0 else "falls", abs(ch), unit_of[feat], len(path), rho,
            "" if st["acoustic_trend"] != "stable" else "; below the audible reference: reported as stable"))
    else:
        parts = []
        for f in PATH_FEATS:
            if st.get(f + "_change") is not None:
                sc = abs(st.get(f + "_rho", 0)) * min(1.0, abs(st[f + "_change"]) / PATH_REF[f])
                parts.append((sc, f))
        if parts:
            sc, f = max(parts)
            st["acoustic_drift_score"] = sc
            if sc >= 0.5:
                words = {"centroid": ("brighter", "darker"), "loudness": ("louder", "softer"),
                         "flatness": ("noisier", "more tonal")}[f]
                st["acoustic_trend"] = words[0] if st[f + "_change"] > 0 else words[1]
                st["acoustic_confidence"] = "measured"
            st["acoustic_detail"] = "strongest change: %s %+.2f %s (rho %+.2f)" % (
                f, st[f + "_change"], unit_of[f], st.get(f + "_rho", 0.0))
    if st["end_to_end_norm"] < 0.02 or st["drift_ratio"] < 1.5:
        st["kind"] = "recurrence"
    elif st["drift_ratio"] >= 2.0 and mono >= 0.8 and len(path) >= 4:
        st["kind"] = "structural evolution"
    else:
        st["kind"] = "relation"
    return st


def spearmanr_safe(x, y):
    from scipy.stats import spearmanr
    if len(x) < 2 or np.std(y) == 0:
        return 0.0
    r = spearmanr(x, y).correlation
    return float(r) if np.isfinite(r) else 0.0


def run_phrase(args, F, hop, st_out, finish, unchanged, plan_header, P):
    """Phrase-level Evolution Path (args.unit = phrase_auto / phrase_textgrid).
    Returns False when it fell back to the gesture engine (caller runs it)."""
    use = list(PATH_FEATS) if args.match == "all" else [args.feature]
    shape = args.similarity == "shape"
    directions = list(AUTO_DIRECTIONS) if args.direction == "auto" else [args.direction]
    notes = []
    if args.unit == "phrase_textgrid":
        phrases, tnotes = read_phrase_tsv(args.phrases_tsv, F, args.xmin)
        notes += tnotes
        seg = {"method": "TextGrid tier", "notes": tnotes, "candidates": [], "min_phrase": float("nan"),
               "max_phrase": float("nan")}
    else:
        phrases, seg = segment_phrases(F, args.xmin, args.min_phrase, args.max_phrase, args.boundaries,
                                       args.phrase_detail)
        seg["method"] = "automatic (%s)" % {"both": "pauses + acoustic change", "silence": "pauses only",
                                            "change": "acoustic change only"}[args.boundaries]
        notes += seg["notes"]
    units = phrase_units(F, phrases)
    st_out.update({"unit": args.unit, "segmentation": seg["method"], "n_phrases": len(units),
                   "min_phrase_s": seg.get("min_phrase", float("nan")),
                   "max_phrase_s": seg.get("max_phrase", float("nan")),
                   "pause_threshold_db": seg.get("pause_threshold_db", float("nan"))})
    # all phrases, for the picture and the optional TextGrid
    with open(P + "_phrases.tsv", "w") as f:
        f.write("id\tstart\tend\tduration\tboundary_after\tevidence_after\tlabel\n")
        for k, u in enumerate(units):
            f.write("%d\t%s\t%s\t%s\t%s\t%s\t%s\n" % (k + 1, fmt(u["t0"]), fmt(u["t1"]), fmt(u["dur"], 4),
                                                    u.get("boundary_after", "-"),
                                                    fmt(u.get("evidence_after", float("nan")), 3),
                                                    (u.get("label") or "P%d" % (k + 1)).replace("\t", " ")))
    if len(units) < 2:
        if args.unit == "phrase_textgrid":
            finish("error", "the TextGrid tier gives %d usable phrase(s); at least 2 are needed | %s"
                   % (len(units), " | ".join(notes)))
            return True
        st_out["phrase_fallback"] = ("automatic segmentation found %d usable phrase(s): gesture windows were "
                                     "analysed instead" % len(units))
        st_out["unit_used"] = "gesture (fallback)"
        return False
    st_out["unit_used"] = "phrase"
    A = phrase_analysis(units, use, shape, args.k_links, args.tolerance)
    st_out.update({"engine": "path", "match": args.match, "matched_features": "+".join(use),
                   "direction_requested": args.direction, "k_links": args.k_links, "tolerance": args.tolerance,
                   "typical_link_distance": A["typ"], "window_s": float(np.median([u["dur"] for u in units])),
                   "adapted": "", "window_cells": 0})
    sc0, d0, p0 = path_best(A, directions, args.tolerance)
    pval, nb_sc, nb_len, exact, n_orders, min_p = (phrase_null(A, directions, sc0, args.surrogates, args.seed,
                                                               args.k_links, args.tolerance)
                                                   if args.surrogates > 0 else
                                                   (float("nan"), [], [], False, 0, float("nan")))
    test_possible = n_orders > 0 and min_p <= args.alpha + 1e-12
    info, used, seq = {}, [], []
    Pn = len(units)
    if args.mode == "guided":
        a = int(np.argmin([abs((u["t0"] + u["t1"]) / 2 - args.anchor_time) for u in units]))
        sc, d, path = path_best(A, directions, args.tolerance, through=a)
        if not (units[a]["t0"] <= args.anchor_time <= units[a]["t1"]):
            info["note"] = "the anchor lies in no phrase; the nearest phrase (%.2f-%.2f s) is used" % (
                units[a]["t0"], units[a]["t1"])
        info["anchor_window_start"] = units[a]["t0"]
        info["anchor_shift_s"] = 0.0
        info["anchor_position"] = path.index(a) + 1
        pg = (1 + sum(1 for b in nb_sc if b >= sc - 1e-12)) / (1 + len(nb_sc)) if nb_sc else float("nan")
        root = phrase_stats(path, d, A, units, pg, args.alpha, 1)
        used = [root]
        seq = [(root, k) for k in range(root["length"])]
    else:
        root = phrase_stats(p0, d0, A, units, pval, args.alpha, 1)
        used = [root]
        if args.mode == "lineage":
            seq = [(root, k) for k in range(root["length"])]
        elif args.mode == "montage":
            banned = set(p0)
            while len(used) < args.n_lineages:
                sc, d, path = path_best(A, directions, args.tolerance, banned=banned)
                if len(path) < 2:
                    break
                used.append(phrase_stats(path, d, A, units, float("nan"), args.alpha, len(used) + 1))
                banned |= set(path)
            for g in range(max(s["length"] for s in used)):
                for s in used:
                    if g < s["length"]:
                        seq.append((s, g))
            info["montage_lineages"] = len(used)
            if len(used) < args.n_lineages:
                info["note"] = "only %d separate phrase path(s) in this recording" % len(used)
        elif args.mode == "branching":
            forks, taken = [], set()
            for _ in range(args.n_lineages - 1):
                best = None
                for k, w in enumerate(p0[:-1]):
                    ban = (set(p0) | taken) - {w}
                    sc, d, path = path_best(A, directions, args.tolerance, banned=ban, start=w)
                    if len(path) >= 3 and (best is None or sc > best[0]):
                        best = (sc, d, path, k)
                if best is None:
                    break
                sc, d, path, k = best
                br = phrase_stats(path[1:], d, A, units, float("nan"), args.alpha, len(used) + 1)
                forks.append((float(A["D"][path[0], path[1]] / A["typ"]), k, br))
                used.append(br)
                taken |= set(path[1:])
            info["branch_root_ratios"] = [round(c, 4) for c, _, _ in forks]
            info["branch_fork_generations"] = [k + 1 for _, k, _ in forks]
            if not forks:
                info["note"] = "no path of 2+ phrases leaves this one through other phrases: a single path"
            seq = [(root, k) for k in range(root["length"])]
            for _, k, br in forks:
                seq.append((root, k))
                seq += [(br, g) for g in range(br["length"])]
        else:
            raise ValueError(args.mode)
    if args.order == "backward":
        if args.mode == "montage":
            seq = seq[::-1]
        else:
            seq2 = []
            for s in used:
                seq2 += [(s, k) for k in range(s["length"] - 1, -1, -1)]
            seq = seq2
    if root["length"] < 2:
        # v2.1.1: one phrase is not an evolution path
        st_out.update({"sel_length": root["length"], "n_lineages": 0})
        with open(P + "_plan.tsv", "w") as f:
            f.write(plan_header)
        finish("no_relation", "no two of the %d phrases are related within the link settings (mutual %d nearest, "
               "%.1f x typical distance); no path, no Sound - raise Links per unit or Link tolerance" %
               (Pn, args.k_links, args.tolerance))
        return True
    rows = plan_rows(seq, 0.0, args.order, args.gap_mode, args.gap_scale, args.max_output)
    # ---- tables ----
    disp = args.feature if args.match != "all" else (DIRECTIONS[root["direction"]][0] or "centroid")
    st_out["feature_used"] = disp
    tgrid = args.xmin + (np.arange(F["n"]) + 0.5) * hop
    tt, vv = decimate(tgrid, F[disp])
    with open(P + "_traj.tsv", "w") as f:
        f.write("time\tvalue\n")
        for a_, b_ in zip(tt, vv):
            f.write("%s\t%s\n" % (fmt(a_), fmt(b_)))
    near = A["nearest"]
    with open(P + "_mp.tsv", "w") as f:
        f.write("time\tP\n")
        for u, v in zip(units, near):
            f.write("%s\t%s\n" % (fmt((u["t0"] + u["t1"]) / 2), fmt(v)))
    # the relation graph the path search used: mutual K nearest links in
    # time order within tol x typical; path links carry their path's id
    on_path = {}
    for s_ in used:
        for a_, b_ in zip(s_["windows"][:-1], s_["windows"][1:]):
            on_path.setdefault((a_, b_), s_["id"])
    with open(P + "_phrase_links.tsv", "w") as f:
        f.write("i\tj\tt_i\tt_j\tratio\tpath\n")
        for i in range(Pn):
            for j, c in A["links"][i]:
                f.write("%d\t%d\t%s\t%s\t%s\t%d\n" % (i + 1, j + 1, fmt((units[i]["t0"] + units[i]["t1"]) / 2),
                                                      fmt((units[j]["t0"] + units[j]["t1"]) / 2), fmt(c, 4),
                                                      on_path.get((i, j), 0)))
        for (a_, b_), sid in on_path.items():          # path links that are not graph links (branch forks)
            if all(j != b_ for j, c in A["links"][a_]):
                f.write("%d\t%d\t%s\t%s\t%s\t%d\n" % (a_ + 1, b_ + 1, fmt((units[a_]["t0"] + units[a_]["t1"]) / 2),
                                                      fmt((units[b_]["t0"] + units[b_]["t1"]) / 2),
                                                      fmt(A["D"][a_, b_] / A["typ"], 4), sid))
    with open(P + "_lineages.tsv", "w") as f:
        f.write("id\tlength\tkind\tdirection\tp\tsignificant\tworst_link_ratio\tmean_link_corr\tend_corr\t"
                "drift_ratio\tmonotonicity\tspan_s\tfirst_start\tlast_start\tacoustic_trend\tacoustic_detail\t"
                "phrases\n")
        for s_ in used:
            mc = float(np.mean(s_["link_corr"])) if s_["link_corr"] else float("nan")
            f.write("\t".join([str(s_["id"]), str(s_["length"]), s_["kind"], s_["direction"], fmt(s_["p"], 4),
                               "1" if s_["significant"] else "0", fmt(s_["worst_link_ratio"], 4), fmt(mc, 4),
                               fmt(s_["end_corr"], 4), fmt(s_["drift_ratio"], 4), fmt(s_["drift_monotonicity"], 4),
                               fmt(s_["span_s"], 4), fmt(s_["start_times"][0], 4), fmt(s_["start_times"][-1], 4),
                               s_.get("acoustic_trend", "-"), s_.get("acoustic_detail", "") or "-",
                               " ".join(str(k + 1) for k in s_["windows"])]) + "\n")
    with open(P + "_members.tsv", "w") as f:
        f.write("lineage\tgeneration\tstart\tend\tP\n")
        for s_ in used:
            for k, w in enumerate(s_["windows"]):
                f.write("%d\t%d\t%s\t%s\t%s\n" % (s_["id"], k + 1, fmt(units[w]["t0"]), fmt(units[w]["t1"]),
                                                    fmt(near[w])))
    with open(P + "_plan.tsv", "w") as f:
        f.write(plan_header)
        for r in rows:
            f.write("\t".join([fmt(r["src_start"]), fmt(r["src_end"]), str(r["lineage"]), str(r["generation"]),
                               fmt(r["silence_before"]), fmt(r["link_ratio"], 4), fmt(r["link_corr"], 4)]) + "\n")
    for k, v in info.items():
        st_out[k] = v
    s_ = used[0]
    durs = [u["dur"] for u in units]
    st_out.update({
        "n_windows": Pn, "n_gesture_windows": Pn, "n_flat_windows": 0, "n_undefined_windows": 0,
        "mp_median": A["typ"], "mp_max_possible": 2.0, "n_lineages": len(used), "n_pairs": 0,
        "n_significant": int(bool(s_["significant"])), "shuffle_blocks": Pn, "shuffle_exact": int(exact),
        "shuffle_versions": n_orders, "min_possible_p": min_p, "test_possible": int(test_possible),
        "null_model": "phrase-order permutation",
        "null_longest_median": float(np.median(nb_len)) if nb_len else float("nan"),
        "null_longest_max": max(nb_len) if nb_len else 0,
        "path_score": sc0, "best_p_fwer": pval,
        "phrase_dur_min": min(durs), "phrase_dur_max": max(durs), "phrase_dur_median": float(np.median(durs)),
        "sel_id": 1, "sel_length": s_["length"], "sel_kind": s_["kind"], "sel_direction": s_["direction"],
        "sel_p": s_["p"], "sel_p_fwer": s_["p"], "sel_significant": int(bool(s_["significant"])),
        "sel_worst_link_ratio": s_["worst_link_ratio"],
        "sel_mean_link_corr": float(np.mean(s_["link_corr"])) if s_["link_corr"] else float("nan"),
        "sel_min_link_corr": float(np.min(s_["link_corr"])) if s_["link_corr"] else float("nan"),
        "sel_end_corr": s_["end_corr"], "sel_drift_ratio": s_["drift_ratio"],
        "sel_monotonicity": s_["drift_monotonicity"], "sel_span_s": s_["span_s"],
        "sel_first_start": s_["start_times"][0], "sel_last_start": s_["start_times"][-1],
        "sel_duration_ratio": s_["duration_ratio_max"], "sel_phrases": " ".join(str(k + 1) for k in s_["windows"]),
        "used_lineages": len(used),
        "sel_acoustic_trend": s_.get("acoustic_trend", "stable"),
        "sel_acoustic_detail": s_.get("acoustic_detail", ""),
        "sel_acoustic_score": s_.get("acoustic_drift_score", 0.0),
        "sel_acoustic_confidence": s_.get("acoustic_confidence", "-"),
        "sel_overlap_fraction": 0.0,
        "sel_mean_link_dist": float(np.mean(s_["link_dist"])) if s_["link_dist"] else float("nan"),
        "plan_rows": len(rows),
        "planned_duration": sum(r["silence_before"] + (r["src_end"] - r["src_start"]) for r in rows),
    })
    if not args.allow_weak and not s_["significant"]:
        with open(P + "_plan.tsv", "w") as f:
            f.write(plan_header)
        if not test_possible:
            finish("insufficient", ("NOT TESTED: Surrogates = 0 (Strict: no Sound)" if args.surrogates <= 0 else
                                    "INSUFFICIENT DATA: %d phrases allow only %d other order(s), so the order test "
                                    "cannot reach p <= %.2f (Strict: no Sound)" % (Pn, n_orders, args.alpha)))
        else:
            finish("no_lineage", "the phrase path's order is not beyond chance (p = %.3f); untick 'Strict' to hear "
                   "it anyway" % s_["p"])
        return True
    note = " | ".join(x for x in notes + [info.get("note", "")] if x)
    if s_["significant"]:
        finish("ok", note)
    elif not test_possible:
        msg = ("NOT TESTED: Surrogates = 0, so the order test was not run; the path is built" if args.surrogates <= 0
               else "INSUFFICIENT DATA: %d phrases allow only %d other order(s), so the order test cannot reach "
                    "p <= %.2f; the path is built anyway" % (Pn, n_orders, args.alpha))
        finish("insufficient", " | ".join(x for x in [msg, note] if x))
    else:
        finish("exploratory", " | ".join(x for x in ["EXPLORATORY: phrase path built; its order is not beyond "
                                                       "chance (p = %.3f); %d phrases" % (s_["p"], s_["length"]),
                                                       note] if x))
    return True


def main():
    ap = argparse.ArgumentParser(description="Gestural Lineage Composer engine")
    ap.add_argument("--wav", required=True)
    ap.add_argument("--out_prefix", required=True)
    ap.add_argument("--xmin", type=float, default=0.0, help="time of the Sound's first sample in Praat")
    ap.add_argument("--feature", choices=FEATURES, default="centroid")
    ap.add_argument("--window_s", type=float, default=1.0)
    ap.add_argument("--hop_s", type=float, default=0.02)
    ap.add_argument("--similarity", choices=("shape", "absolute"), default="shape")
    ap.add_argument("--mode", choices=("lineage", "montage", "branching", "guided"), default="lineage")
    ap.add_argument("--select", choices=SELECT, default="strongest")
    ap.add_argument("--order", choices=("forward", "backward"), default="forward")
    ap.add_argument("--gap_mode", choices=("none", "proportional"), default="none")
    ap.add_argument("--gap_scale", type=float, default=0.25)
    ap.add_argument("--n_lineages", type=int, default=3)
    ap.add_argument("--branch_ratio", type=float, default=3.0,
                    help="fork tolerance: a branch's first gesture must be within this many times "
                         "the two lineages' largest generation-to-generation step of a root generation")
    ap.add_argument("--anchor_time", type=float, default=0.0)
    ap.add_argument("--max_output", type=float, default=0.0)
    ap.add_argument("--surrogates", type=int, default=99)
    ap.add_argument("--alpha", type=float, default=0.05)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--allow_weak", type=int, default=1,
                    help="1 (default): if no lineage is beyond chance, use the best weak one (labelled); 0 = strict")
    ap.add_argument("--silence_db", type=float, default=-60.0)
    ap.add_argument("--engine", choices=("path", "chain"), default="path",
                    help="path (v2.0): best evolution path through mutual k-nearest links; "
                         "chain: strict STUMPY time series chains (v1)")
    ap.add_argument("--match", choices=("all", "feature"), default="all",
                    help="path engine: match on all three features, or on --feature only")
    ap.add_argument("--direction", choices=("auto",) + tuple(DIRECTIONS), default="auto")
    ap.add_argument("--unit", choices=("gesture", "phrase_auto", "phrase_textgrid"), default="gesture",
                    help="analysis unit: fixed gesture windows (v2.0), automatic phrases, or TextGrid phrases")
    ap.add_argument("--phrases_tsv", default="", help="phrase_textgrid: start/end/label intervals (tab separated)")
    ap.add_argument("--min_phrase", type=float, default=0.0, help="automatic phrases: minimum duration (0 = adaptive)")
    ap.add_argument("--max_phrase", type=float, default=0.0, help="automatic phrases: maximum duration (0 = adaptive)")
    ap.add_argument("--boundaries", choices=("both", "silence", "change"), default="both")
    ap.add_argument("--phrase_detail", type=float, default=50.0,
                    help="boundary bias 0-100 (50 neutral; higher = more phrases)")
    ap.add_argument("--k_links", type=int, default=0,
                    help="mutual K nearest links; 0 = automatic (3 for gesture windows, 5 for phrases)")
    ap.add_argument("--tolerance", type=float, default=PATH_TOL)
    args = ap.parse_args()
    if args.k_links <= 0:
        # phrases are few and often near-identical: with K = 3 the next generation
        # can drop out of the list (measured: coverage 0.77 vs 1.00 at K = 5)
        args.k_links = PHRASE_K if args.unit != "gesture" else PATH_K
    args.k_links = max(1, min(20, args.k_links))
    args.tolerance = max(0.1, args.tolerance)
    args.window_s = max(0.1, args.window_s)
    args.hop_s = min(max(0.005, args.hop_s), args.window_s / 5)
    args.surrogates = max(0, min(999, args.surrogates))
    args.n_lineages = max(1, min(12, args.n_lineages))
    args.gap_scale = max(0.0, args.gap_scale)
    P = args.out_prefix
    st_out = {"engine_version": VERSION, "feature": args.feature, "similarity": args.similarity,
              "mode": args.mode, "select": args.select, "order": args.order,
              "window_s_requested": args.window_s, "surrogates": args.surrogates,
              "seed": args.seed, "alpha": args.alpha, "allow_weak": args.allow_weak,
              "gap_mode": args.gap_mode, "gap_scale": args.gap_scale}

    def finish(status, reason=""):
        # Praat cannot read a header-only table: a table without rows is not left behind
        for name in ("_plan.tsv", "_traj.tsv", "_mp.tsv", "_lineages.tsv", "_members.tsv", "_phrases.tsv",
                     "_phrase_links.tsv"):
            fp = P + name
            try:
                with open(fp) as f:
                    n = sum(1 for line in f if line.strip())
                if n < 2:
                    os.remove(fp)
            except OSError:
                pass
        st_out["status"] = status
        st_out["reason"] = reason
        with open(P + "_stats.txt", "w", encoding="utf-8") as f:
            for k, v in st_out.items():
                if isinstance(v, float):
                    v = fmt(v, 6)
                elif isinstance(v, (list, tuple)):
                    v = " ".join(fmt(x, 4) if isinstance(x, float) else str(x) for x in v)
                f.write("%s=%s\n" % (k, str(v).replace("\n", " ")))
        print("STATUS: %s %s" % (status, reason))

    import soundfile as sf
    try:
        Y, sr = sf.read(args.wav, always_2d=False)
    except Exception as e:
        finish("error", "cannot read the exported Sound (%s)" % e)
        sys.exit(1)
    Y = np.asarray(Y, dtype=np.float64)
    y, ch = strongest_channel(Y)
    st_out["analysis_channel"] = ch
    st_out["channels"] = 1 if Y.ndim == 1 else Y.shape[1]
    st_out["source_duration"] = len(y) / sr
    plan_header = "src_start\tsrc_end\tlineage\tgeneration\tsilence_before\tlink_ratio\tlink_corr\n"

    def unchanged(reason):
        """Nothing in the recording can be related (no movement at all): the
        result is the source itself, and the report says exactly why."""
        finish("unchanged", reason)

    try:
        F = frame_features(y, sr, args.hop_s, args.silence_db)
    except ValueError as e:
        unchanged(str(e))
        return
    hop = F["hop_s"]
    st_out.update({"hop_s": hop, "grid_cells": F["n"],
                   "silent_cells": int(F["silent"].sum()), "gap_filled_cells": F["gap_filled_cells"],
                   "silence_threshold_db": F["silence_threshold_db"]})
    if args.unit != "gesture" and args.engine == "chain":
        # phrase analysis composes evolution paths; strict chains stay a gesture-window method
        st_out["engine_note"] = "phrase analysis uses the evolution-path engine (strict chains are gesture-level)"
        args.engine = "path"
    if args.engine == "path":
        st_out["engine"] = "path"
        if args.unit in ("phrase_auto", "phrase_textgrid"):
            if run_phrase(args, F, hop, st_out, finish, unchanged, plan_header, P):
                return
        else:
            st_out["unit_used"] = "gesture"
        run_path(args, F, hop, st_out, finish, unchanged, plan_header, P)
        return
    st_out["engine"] = "chain"
    _enable_stumpy_cache()

    # ---- adapt the settings until the analysis can run (every change is reported) ----
    feature, win = args.feature, args.window_s
    adapt, tried = [], {feature}
    result = None
    for _ in range(12):
        T = F[feature]
        m = int(round(win / hop))
        try:
            result = analyse(T, m, hop, args.similarity == "shape", FLAT_STD[feature], args.xmin,
                             args.surrogates, args.seed, args.alpha, min_len=2,
                             feats=sounding_only(F))   # v2.0: means over sounding cells only
            break
        except ValueError as e:
            msg = str(e)
            if "too short" in msg and win > 0.1 + 1e-9:
                nw = max(0.1, win / 2)          # halve, last try at the 0.1 s minimum
                adapt.append("window %.2f s is too long for this Sound: %.2f s used" % (win, nw))
                win = nw
            elif "undefined stretch" in msg and feature != "loudness":
                adapt.append("%s is undefined in every %.2f s window (pauses): loudness used" % (feature, win))
                feature = "loudness"
                tried.add(feature)
            elif "constant" in msg or "undefined" in msg:
                rest = [f for f in ("flatness", "loudness", "centroid") if f not in tried]
                if not rest:
                    unchanged("no feature moves in any window: " + msg)
                    return
                adapt.append("%s is constant in every window: %s used" % (feature, rest[0]))
                feature = rest[0]
                tried.add(feature)
            else:
                unchanged(msg)
                return
    if result is None:
        unchanged("the analysis could not be set up for this Sound")
        return
    prof, stats, raw, tabs, null_longest = result
    win_s = m * hop
    st_out.update({"feature_used": feature, "window_cells": m, "window_s": win_s,
                   "adapted": " | ".join(adapt)})
    # trajectory export (display copy) of the feature actually analysed
    tgrid = args.xmin + (np.arange(F["n"]) + 0.5) * hop
    tt, vv = decimate(tgrid, F[feature])
    with open(P + "_traj.tsv", "w") as f:
        f.write("time\tvalue\n")
        for a_, b_ in zip(tt, vv):
            f.write("%s\t%s\n" % (fmt(a_), fmt(b_)))
    Pv = prof["P"].copy()
    dmax = 2 * math.sqrt(m) if prof["normalize"] else float("nan")
    tm = args.xmin + (np.arange(len(Pv)) + m / 2.0) * hop      # window centre
    tt, pp = decimate(tm, np.where(np.isfinite(Pv), Pv, np.nan))
    with open(P + "_mp.tsv", "w") as f:
        f.write("time\tP\n")
        for a_, b_ in zip(tt, pp):
            f.write("%s\t%s\n" % (fmt(a_), fmt(b_)))
    ge3 = [s_ for s_ in stats if s_["length"] >= 3]
    sig = [s_ for s_ in ge3 if s_["significant"]]
    sh = prof.get("shuffle") or {}
    test_possible = bool(prof.get("test_possible"))
    st_out.update({"shuffle_blocks": sh.get("n_blocks", 0), "shuffle_exact": int(bool(sh.get("exact"))),
                   "shuffle_versions": len(tabs), "min_possible_p": sh.get("min_p", float("nan")),
                   "test_possible": int(test_possible)})
    weak = False
    if sig:
        cands = sig
    elif args.allow_weak:
        # nothing beyond chance: the best weak lineage (3+ gestures if any, else a pair)
        cands = ge3 if ge3 else stats
        weak = bool(cands)
    else:
        cands = []
    st_out.update({
        "n_windows": len(Pv), "n_gesture_windows": int((prof["valid"] & ~prof["flat"]).sum()),
        "n_flat_windows": int(prof["flat"].sum()), "n_undefined_windows": int((~prof["valid"]).sum()),
        "mp_median": median_P(prof), "mp_max_possible": dmax,
        "n_raw_chains": len(raw), "n_raw_chains_ge3": sum(1 for c in raw if len(c) >= 3),
        "n_lineages": len(ge3), "n_pairs": len(stats) - len(ge3), "n_significant": len(sig),
        "null_longest_median": float(np.median(null_longest)) if null_longest else float("nan"),
        "null_longest_max": max(null_longest) if null_longest else 0,
        "best_p_fwer": (ge3[0]["p_fwer"] if ge3 else (stats[0]["p_fwer"] if stats else float("nan"))),
    })
    with open(P + "_lineages.tsv", "w") as f:
        f.write("id\tlength\tkind\tp\tp_fwer\tsignificant\tworst_link_ratio\tmean_link_corr\t"
                "end_corr\tdrift_ratio\tmonotonicity\tspan_s\tfirst_start\tlast_start\t"
                "acoustic_trend\tacoustic_drift_score\tacoustic_confidence\tacoustic_p_adj\tacoustic_detail\toverlap_fraction\n")
        for s_ in stats:
            mc = float(np.mean(s_["link_corr"])) if s_["link_corr"] else float("nan")
            f.write("\t".join([str(s_["id"]), str(s_["length"]), s_["kind"], fmt(s_["p"], 4), fmt(s_["p_fwer"], 4),
                               "1" if s_["significant"] else "0", fmt(s_["worst_link_ratio"], 4), fmt(mc, 4),
                               fmt(s_["end_corr"], 4), fmt(s_["drift_ratio"], 4), fmt(s_["drift_monotonicity"], 4),
                               fmt(s_["span_s"], 4), fmt(s_["start_times"][0], 4), fmt(s_["start_times"][-1], 4),
                               s_.get("acoustic_trend", "stable"), fmt(s_.get("acoustic_drift_score", 0.0), 4),
                               s_.get("acoustic_confidence", "-"), fmt(s_.get("acoustic_p_adj", float("nan")), 4),
                               s_.get("acoustic_detail", "") or "-", fmt(s_.get("overlap_fraction", 0.0), 3)]) + "\n")
    # v1.0.2: 'Most drift' (Gradual Evolution) with Strict off may choose ANY
    # lineage of 4+ generations by its sound change, even one the chance test
    # does not confirm; the lineage's own p still decides the status label.
    root_pool = None
    if args.select == "drift" and args.allow_weak and args.mode in ("lineage", "montage", "branching"):
        pool = [s_ for s_ in ge3 if s_["length"] >= 4]
        if pool and max(s_.get("acoustic_drift_score", 0.0) for s_ in pool) >= 0.5:
            root_pool = pool
    rows, info, used = build_plan(args.mode, stats, cands, args, prof, hop, args.xmin, win_s, tabs, root_pool)
    with open(P + "_members.tsv", "w") as f:
        f.write("lineage\tgeneration\tstart\tend\tP\n")
        for s_ in used:
            for k, (t0, j) in enumerate(zip(s_["start_times"], s_["members"])):
                f.write("%d\t%d\t%s\t%s\t%s\n" % (s_["id"], k + 1, fmt(t0), fmt(t0 + win_s),
                                                    fmt(Pv[j] if np.isfinite(Pv[j]) else float("nan"))))
    with open(P + "_plan.tsv", "w") as f:
        f.write(plan_header)
        for r in rows:
            f.write("\t".join([fmt(r["src_start"]), fmt(r["src_end"]), str(r["lineage"]), str(r["generation"]),
                               fmt(r["silence_before"]), fmt(r["link_ratio"], 4), fmt(r["link_corr"], 4)]) + "\n")
    for k, v in info.items():
        st_out[k] = v
    if used:
        s_ = used[0]
        weak = not bool(s_["significant"])
        st_out.update({
            "sel_id": s_["id"], "sel_length": s_["length"], "sel_kind": s_["kind"],
            "sel_p": s_["p"], "sel_p_fwer": s_["p_fwer"], "sel_significant": int(bool(s_["significant"])),
            "sel_worst_link_ratio": s_["worst_link_ratio"],
            "sel_mean_link_corr": float(np.mean(s_["link_corr"])) if s_["link_corr"] else float("nan"),
            "sel_min_link_corr": float(np.min(s_["link_corr"])) if s_["link_corr"] else float("nan"),
            "sel_end_corr": s_["end_corr"], "sel_drift_ratio": s_["drift_ratio"],
            "sel_monotonicity": s_["drift_monotonicity"], "sel_span_s": s_["span_s"],
            "sel_first_start": s_["start_times"][0], "sel_last_start": s_["start_times"][-1],
            "used_lineages": len(used),
            "sel_acoustic_trend": s_.get("acoustic_trend", "stable"),
            "sel_acoustic_detail": s_.get("acoustic_detail", ""),
            "sel_acoustic_score": s_.get("acoustic_drift_score", 0.0),
            "sel_acoustic_confidence": s_.get("acoustic_confidence", "-"),
            "sel_acoustic_p_adj": s_.get("acoustic_p_adj", float("nan")),
            "sel_chosen_by_sound": int(bool(root_pool) and s_ is used[0] and not s_["significant"]),
            "sel_overlap_fraction": s_.get("overlap_fraction", 0.0),
            "sel_mean_link_dist": float(np.mean(s_["link_dist"])) if s_["link_dist"] else float("nan"),
        })
    st_out["plan_rows"] = len(rows)
    st_out["planned_duration"] = sum(r["silence_before"] + (r["src_end"] - r["src_start"]) for r in rows)
    notes = [x for x in (" | ".join(adapt), info.get("note", "")) if x]
    insufficient_msg = ("INSUFFICIENT DATA: this Sound allows only %d reordering(s) at %.2f s windows, "
                        "so the chance test cannot reach p <= %.2f (smallest possible p = %.3f); "
                        "use a shorter window or a longer recording"
                        % (len(tabs), win_s, args.alpha, sh.get("min_p", 1.0))) if tabs else \
        ("INSUFFICIENT DATA: at %.2f s windows this Sound is a single shuffle block, so it cannot be "
         "reordered at all; use a shorter window or a longer recording" % win_s
         if args.surrogates > 0 else "INSUFFICIENT DATA: no chance test was run (0 surrogates)")
    if rows and not weak:
        finish("ok", " | ".join(notes))
    elif rows and not test_possible:
        finish("insufficient", " | ".join([insufficient_msg] + notes))
    elif rows:
        s_ = used[0]
        why = ("; chosen for its sound change (%s, %s), not for the chance test"
               % (s_.get("acoustic_trend", "-"), s_.get("acoustic_confidence", "-"))) \
            if st_out.get("sel_chosen_by_sound") else ""
        finish("exploratory", " | ".join(["EXPLORATORY: not beyond chance (p = %.3f); %d-gesture %s%s"
                                           % (s_["p"], s_["length"],
                                              "pair" if s_["length"] == 2 else "lineage", why)] + notes))
    elif "reason" in info:
        finish("no_lineage", info["reason"])
    elif not stats:
        unchanged("no two windows of this recording are mutually nearest neighbours")
    elif not test_possible:
        finish("insufficient", insufficient_msg + "; Strict is on, so no Sound")
    else:
        finish("no_lineage", "%d lineage(s), none beyond chance (best p = %.3f); Strict is on"
               % (len(ge3), st_out["best_p_fwer"]))


if __name__ == "__main__":
    main()
