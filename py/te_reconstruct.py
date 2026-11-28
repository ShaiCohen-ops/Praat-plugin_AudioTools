"""
te_reconstruct.py - Temporal Elasticity acoustic reconstruction engine v1.0

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University

Called by TemporalElasticity.praat (v1.4+) - not normally run directly.

Usage:
    python te_reconstruct.py source.wav durations.csv out.wav report.txt
        [--method pv|varispeed|placement] [--time_offset T] [--input_gain G]

Role
----
latent_time_warp.py DECIDES the event durations. This module IMPLEMENTS them
on the whole source signal. Segmentation is used only to build the time map;
the audio is never cut into independently processed pieces.

Pipeline
--------
1. Time map. Event boundaries become knots of a continuous, strictly
   monotonic, piecewise-linear map from input samples to output samples.
   Every region outside an event (leading/trailing silence, gaps) keeps
   slope 1, so silence is preserved sample-for-sample. Knots are integer
   samples; each event lands within +-1 sample of its requested duration,
   with no accumulated drift. The planned length is reported to Praat.

2. Islands and window size (pv only). Runs of changed events separated by
   unchanged time long enough to be exact in every render form "islands".
   Each island uses a ~46 ms window (2048 @ 44.1/48 kHz) unless a large
   energy share of its prominent partials lies closer than 3.2 bins of that
   window (semitone clusters, close chords, very low harmonic tones); those
   islands use a window of at least ~93 ms (4096 @ 44.1 kHz, 6144 @ 48 kHz,
   12288 @ 96 kHz). Pitch is never estimated. Islands rendered
   with different windows are joined only inside spans where both renders
   are bit-identical to the source, so a seam is sample-exact.

3. Transient protection (pv only). Sharp attacks are detected from the
   signal itself (peak over 3 ms vs RMS of the preceding 15 ms, all
   channels; beating and swells rejected). Event starts that follow
   unchanged time are added at the lowest priority. Around each, the map
   gets slope 1 from N/2 (+hop/2) before to 3N/4 after; the rest of the event
   absorbs the difference, so its duration is unchanged. If the remaining
   ratio would leave [0.125, 4.5], zones are narrowed, then the weakest
   attacks are dropped (reported).

4. Reconstruction, one of:
   pv         Pitch-preserving phase vocoder with a time-varying analysis
              hop driven by the inverse map. The phase advance is measured
              from a second analysis frame exactly one synthesis hop earlier,
              so it is exact modulo 2 pi for any local ratio (no unwrapping).
              ONE phase rotation per bin is shared by all channels and
              estimated from all of them (angle of sum_c Yprev * conj(X)),
              so inter-channel phase and delay are preserved exactly,
              anti-phase stays anti-phase, nothing is folded to mono.
              Identity phase locking on tonal peaks with an adaptive radius:
              the whole region of a well-separated peak, +-1 bin between
              crowded peaks (so unresolved neighbours are not dragged onto
              one phase advance). Non-tonal bins propagate per bin.
              Slope-1 regions are phase-reset: gradually (8 frames, inside
              the region where no drift occurs) in silences/unchanged spans,
              abruptly at attack zones (classic transient phase reset).
              A per-band energy correction (1/4 octave, ~93 ms) restores the
              analysis energy in vocoded frames (incoherent overlap-add of
              noise otherwise loses ~3 dB). Wherever every overlapping frame
              was reset, the ORIGINAL samples are written back, so unchanged
              material is never resynthesised.
   varispeed  Band-limited (Kaiser-windowed sinc, anti-aliased) variable-
              rate reading of the source. Changes PITCH with duration -
              tape-speed effect, not time stretching. Slope-1 regions exact.
   placement  No stretching: each region's original samples are placed at
              their mapped output position, truncated (5 ms raised-cosine
              fade) or followed by silence. Unchanged regions exact.

Identity: if every knot has slope 1 the source samples are written back
unchanged (no analysis, no resynthesis). TemporalElasticity.praat bypasses
this module entirely in that case and returns a Copy.

Dependencies: numpy, soundfile. No scipy, no internet.
"""

import sys
import os
import csv
import math

VERSION = "1.0"

for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(errors="replace")
    except (AttributeError, ValueError):
        pass

try:
    import numpy as np
    import soundfile as sf
except ImportError as _e:  # pragma: no cover - reported to Praat log
    print("ERROR: missing package (%s). pip install numpy soundfile" % _e, file=sys.stderr)
    sys.exit(1)


# Safe local-ratio range for the free (unprotected) part of an event after
# transient zones have been carved out. Outside it, protection is narrowed.
RATIO_MIN = 0.125
RATIO_MAX = 4.5
RESET_RAMP_FRAMES = 8
TONAL_DB = 12.0         # peak must exceed local log-spectral mean by this much
MIN_FREE_SAMPLES = 16
LOCK_RADIUS = "adaptive"  # bins around a tonal peak that inherit its phase
LOCK_MARGIN = 1         # adaptive: stop this many bins short of the midpoint to the next peak
CLOSE_BINS = 3.2        # partials closer than this many small-window bins need the long window
CLOSE_FRACTION = 0.25   # energy share of such partials that switches an island to the long window


# ===========================================================================
# Window geometry
# ===========================================================================

_FFT_SIZES = sorted(set([2 ** k for k in range(8, 17)] + [3 * 2 ** k for k in range(7, 16)]))


def pv_geometry(sr):
    """Short analysis window ~46 ms (2048 @ 44.1/48 kHz, 4096 @ 96 kHz),
    hop = N/4. Sizes are 2^k or 1.5*2^k."""
    target = max(0.0464 * sr, 256.0)
    n = min((v for v in _FFT_SIZES if v % 4 == 0), key=lambda v: abs(math.log(v / target)))
    return n, n // 4


def pv_geometry_long(sr):
    """Long window for closely spaced partials: the smallest size of at least
    ~2 x 46 ms, so its frequency resolution does not depend on the sample
    rate (4096 @ 44.1 kHz, 6144 @ 48 kHz, 12288 @ 96 kHz)."""
    target = 0.98 * 2 * 0.0464 * sr
    n = min(v for v in _FFT_SIZES if v >= target)
    return n, n // 4


# ===========================================================================
# Events -> time map
# ===========================================================================

def read_durations_csv(path):
    """Return list of (start_time, original_duration, new_duration)."""
    rows = []
    with open(path, "r", newline="") as f:
        reader = csv.DictReader(f)
        for r in reader:
            try:
                st = float(r["start_time"])
                od = float(r["original_duration"])
                nd = float(r["new_duration"])
            except (KeyError, ValueError, TypeError):
                continue
            if od > 0 and nd > 0 and math.isfinite(st):
                rows.append((st, od, nd))
    rows.sort(key=lambda t: t[0])
    return rows


def build_time_map(events, sr, n_in, time_offset=0.0):
    """Integer knots (X input samples, Y output samples).

    Boundaries are sample boundaries: knot k sits between sample k-1 and k.
    Gaps between events keep their exact sample count; each event's output
    length is its requested length rounded (error <= 1 sample, no drift).
    """
    X = [0]
    Y = [0]
    shift = 0.0            # cumulative output-minus-input, in samples (float)
    for st, od, nd in events:
        a = int(round((st - time_offset) * sr))
        b = int(round((st + od - time_offset) * sr))
        a = max(a, X[-1])
        b = min(b, n_in)
        if b - a < 1:
            continue
        ya = int(round(a + shift))
        if a > X[-1]:
            X.append(a)
            Y.append(ya)
        shift += nd * sr - (b - a)
        yb = int(round(b + shift))
        yb = max(yb, Y[-1] + 1)
        X.append(b)
        Y.append(yb)
    if X[-1] < n_in:
        X.append(n_in)
        Y.append(int(round(n_in + shift)))
    X = np.asarray(X, dtype=np.int64)
    Y = np.asarray(Y, dtype=np.int64)
    if np.any(np.diff(X) <= 0) or np.any(np.diff(Y) <= 0):
        raise ValueError("time map is not strictly monotonic")
    return X, Y


def is_identity_map(X, Y):
    return bool(np.all((Y - X) == 0))


def inv_map(X, Y, t_out):
    """Output position -> input position (boundary coordinates), slope-1
    extrapolation beyond both ends."""
    t_out = np.asarray(t_out, dtype=np.float64)
    r = np.interp(t_out, Y.astype(np.float64), X.astype(np.float64))
    lo = t_out < Y[0]
    hi = t_out > Y[-1]
    r[lo] = X[0] + (t_out[lo] - Y[0])
    r[hi] = X[-1] + (t_out[hi] - Y[-1])
    return r


def inv_center(X, Y, n):
    """Output sample index -> input sample index (sample-centre coordinates)."""
    return inv_map(X, Y, np.asarray(n, dtype=np.float64) + 0.5) - 0.5


def unit_regions(X, Y):
    """Merged slope-1 regions: list of dicts with x0,x1,y0,y1,off and
    open_left/open_right flags (region touches the signal start/end, where the
    slope-1 extrapolation continues it)."""
    regs = []
    for i in range(len(X) - 1):
        if (X[i + 1] - X[i]) == (Y[i + 1] - Y[i]):
            off = int(Y[i] - X[i])
            if regs and regs[-1]["x1"] == X[i] and regs[-1]["off"] == off:
                regs[-1]["x1"] = int(X[i + 1])
                regs[-1]["y1"] = int(Y[i + 1])
            else:
                regs.append({"x0": int(X[i]), "x1": int(X[i + 1]),
                             "y0": int(Y[i]), "y1": int(Y[i + 1]), "off": off})
    for r in regs:
        r["open_left"] = (r["x0"] == X[0])
        r["open_right"] = (r["x1"] == X[-1])
    return regs


# ===========================================================================
# Transient detection and protection
# ===========================================================================

def detect_onsets(x, sr, rise_db=15.0, min_gap_s=0.03):
    """Sharp-attack detector, independent of pitch and of spectral content.

    On a 32-sample block grid (all channels together):
      Pa   = peak |x| over the next ~3 ms
      Rb   = RMS over the ~15 ms ending 1 ms before
      rise = 20 log10(Pa / Rb)
    An attack needs rise >= rise_db, Pa >= half the local peak (+-50 ms, so
    beating minima and slow swells do not qualify) and Pa within 50 dB of the
    file peak. Steady tones (crest 3 dB) and steady noise (~8-10 dB) do not
    qualify. Returns attack-start sample positions and their rise (dB).
    """
    n, C = x.shape
    h = 32
    nb = n // h
    if nb < 64:
        return np.zeros(0, dtype=np.int64), np.zeros(0)
    ax = np.max(np.abs(x[:nb * h]), axis=1).reshape(nb, h)
    bmax = ax.max(axis=1)
    benergy = np.mean(x[:nb * h].reshape(nb, h, C) ** 2, axis=(1, 2))
    ka = max(1, int(round(0.003 * sr / h)))
    kb = max(2, int(round(0.015 * sr / h)))
    kg = max(1, int(round(0.001 * sr / h)))
    kl = max(2, int(round(0.05 * sr / h)))
    gmax = float(bmax.max()) + 1e-20
    # forward peak over ka blocks
    Pa = np.copy(bmax)
    for j in range(1, ka):
        Pa[:-j] = np.maximum(Pa[:-j], bmax[j:])
    cs = np.concatenate([[0.0], np.cumsum(benergy)])
    idx = np.arange(nb)
    hi = np.clip(idx - kg, 0, nb)
    lo = np.clip(idx - kg - kb, 0, nb)
    cnt = np.maximum(hi - lo, 1)
    Rb = np.sqrt((cs[hi] - cs[lo]) / cnt) + gmax * 1e-6
    rise = 20 * np.log10(Pa / Rb + 1e-30)
    # local peak level (+-kl blocks) via a running max
    loc = np.copy(Pa)
    step = 1
    while step <= kl:
        loc = np.maximum(loc, np.concatenate([loc[step:], np.full(step, 0.0)]))
        loc = np.maximum(loc, np.concatenate([np.full(step, 0.0), loc[:-step]]))
        step *= 2
    ok = (rise >= rise_db) & (Pa >= 0.5 * loc) & (Pa >= gmax * 10 ** (-50 / 20.0))
    ok[:kb + kg] &= (np.arange(min(nb, kb + kg)) >= 0)
    cand = np.nonzero(ok)[0]
    out_pos, out_rise = [], []
    min_gap = int(min_gap_s * sr)
    w = max(1, int(round(0.01 * sr / h)))
    env = np.max(np.abs(x), axis=1)
    for bi in cand:
        if rise[bi] < rise[max(0, bi - w):bi + w + 1].max():
            continue
        s0 = bi * h
        s1 = min(n, s0 + (ka + 1) * h)
        pk = float(env[s0:s1].max())
        above = np.nonzero(env[max(0, s0 - h):s1] >= 0.5 * pk)[0]
        pos = max(0, s0 - h) + int(above[0]) if above.size else s0
        r = float(rise[bi])
        if out_pos and pos - out_pos[-1] < min_gap:
            if r > out_rise[-1]:
                out_pos[-1], out_rise[-1] = pos, r
            continue
        out_pos.append(pos)
        out_rise.append(r)
    return np.asarray(out_pos, dtype=np.int64), np.asarray(out_rise)


def _merge(intervals):
    intervals = sorted(intervals)
    out = []
    for a, b in intervals:
        if out and a <= out[-1][1] + MIN_FREE_SAMPLES:
            out[-1][1] = max(out[-1][1], b)
        else:
            out.append([a, b])
    return out


def protect_onsets(X, Y, onsets, pre, post, strength=None):
    """Insert slope-1 zones around attacks inside every non-unit segment while
    keeping each segment's endpoints (i.e. each event's duration) fixed.

    If a segment cannot host all its zones with the remaining ratio inside
    [RATIO_MIN, RATIO_MAX], zones are narrowed (x0.75, x0.5); if that is not
    enough, the weakest attack is dropped and the attempt repeated.
    Returns the new knots, stats, and the list of protected onsets."""
    onsets = np.asarray(onsets, dtype=np.int64)
    if strength is None:
        strength = np.ones(len(onsets))
    pre = np.broadcast_to(np.asarray(pre, dtype=np.float64), onsets.shape)
    post = np.broadcast_to(np.asarray(post, dtype=np.float64), onsets.shape)
    nX, nY = [int(X[0])], [int(Y[0])]
    stats = {"zones": 0, "narrowed": 0, "skipped": 0}
    kept = []
    for i in range(len(X) - 1):
        x0, x1, y0, y1 = int(X[i]), int(X[i + 1]), int(Y[i]), int(Y[i + 1])
        Li, Lo = x1 - x0, y1 - y0
        sel = [j for j in range(len(onsets)) if onsets[j] + post[j] > x0 and onsets[j] - pre[j] < x1]
        if Li == Lo or not sel:
            nX.append(x1); nY.append(y1)
            continue
        sel.sort(key=lambda j: -strength[j])
        accepted = None
        while sel and accepted is None:
            for s in (1.0, 0.75, 0.5):
                zones = []
                for j in sel:
                    o = int(onsets[j])
                    a = max(x0, int(round(o - s * pre[j])))
                    b = min(x1, int(round(o + s * post[j])))
                    if b > a:
                        zones.append((a, b))
                zones = _merge(zones)
                if zones and zones[0][0] - x0 < MIN_FREE_SAMPLES:
                    zones[0][0] = x0
                if zones and x1 - zones[-1][1] < MIN_FREE_SAMPLES:
                    zones[-1][1] = x1
                p = sum(b - a for a, b in zones)
                f, F = Li - p, Lo - p
                if f >= MIN_FREE_SAMPLES and F >= MIN_FREE_SAMPLES and RATIO_MIN <= F / f <= RATIO_MAX:
                    accepted = (s, zones, p, f, F, list(sel))
                    break
            if accepted is None:
                sel.pop()               # drop the weakest remaining attack
                stats["skipped"] += 1
        if accepted is None:
            nX.append(x1); nY.append(y1)
            continue
        s, zones, p, f, F, used = accepted
        stats["zones"] += len(used)
        if s < 1.0:
            stats["narrowed"] += len(used)
        kept.extend(int(onsets[j]) for j in used)
        pieces = []
        cur = x0
        for a, b in zones:
            if a > cur:
                pieces.append((cur, a, False))
            pieces.append((a, b, True))
            cur = b
        if cur < x1:
            pieces.append((cur, x1, False))
        cum_p = cum_f = 0
        for a, b, prot in pieces:
            if prot:
                cum_p += b - a
            else:
                cum_f += b - a
            ye = y0 + cum_p + int(round(F * cum_f / float(f)))
            if b == x1:
                ye = y1
            if b > nX[-1]:
                nX.append(b); nY.append(max(ye, nY[-1] + 1))
    X2 = np.asarray(nX, dtype=np.int64)
    Y2 = np.asarray(nY, dtype=np.int64)
    if np.any(np.diff(X2) <= 0) or np.any(np.diff(Y2) <= 0):
        raise ValueError("protected time map is not strictly monotonic")
    return X2, Y2, stats, sorted(set(kept))


def assign_ramps(regions, onsets, N, Hs):
    """Phase-reset ramp length (frames) per slope-1 region: up to
    RESET_RAMP_FRAMES, but short enough that the reset is complete before the
    first frame that sees a protected attack (o - N/2). A region that starts
    right at an attack zone therefore gets an abrupt (1-frame) reset, which is
    the classic transient phase reset; its phase blur stays before the
    attack."""
    on = np.asarray(onsets, dtype=np.int64)
    for r in regions:
        r["ramp"] = RESET_RAMP_FRAMES
        if r["open_left"] or on.size == 0:
            continue
        inside = on[(on >= r["x0"]) & (on < r["x1"])]
        if inside.size:
            first_out = int(inside.min()) + r["off"]
            room = (first_out - N // 2) - r["y0"]
            r["ramp"] = int(max(1, min(RESET_RAMP_FRAMES, room // Hs)))
    return regions


# ===========================================================================
# Window selection per island
# ===========================================================================

def close_partial_fraction(seg, sr, n_small):
    """Energy share of prominent spectral peaks whose nearest neighbour is
    closer than CLOSE_BINS bins of the small analysis window. Measured with an
    8192-point (at 44.1 kHz) analysis, 40 Hz - 6 kHz, peaks >= 15 dB above the
    local log-spectral mean. Pitch is never estimated."""
    n, C = seg.shape
    M = int(2 ** round(math.log2(0.186 * sr)))
    if n < M:
        return 0.0
    hop = M // 4
    win = np.hanning(M + 1)[:-1]
    f = np.arange(M // 2 + 1) * sr / float(M)
    band = (f >= 40.0) & (f <= 6000.0)
    lim = CLOSE_BINS * sr / float(n_small)
    num = den = 0.0
    for st in range(0, n - M + 1, hop):
        P = np.zeros(M // 2 + 1)
        for c in range(C):
            P += np.abs(np.fft.rfft(seg[st:st + M, c] * win)) ** 2
        L = 10 * np.log10(P + 1e-30)
        core = L[2:-2]
        pk = np.nonzero((core > L[1:-3]) & (core >= L[3:-1]) & (core > L[:-4]) & (core >= L[4:]))[0] + 2
        if pk.size < 1:
            continue
        cs = np.concatenate([[0.0], np.cumsum(L)])
        lo = np.clip(pk - 32, 0, len(L))
        hi = np.clip(pk + 33, 0, len(L))
        prom = (L[pk] - (cs[hi] - cs[lo]) / (hi - lo) >= 15.0) & (L[pk] >= L.max() - 50.0) & band[pk]
        pk = pk[prom]
        if pk.size == 0:
            continue
        fp = f[pk]
        nn = np.full(pk.size, np.inf)
        if pk.size > 1:
            d = np.diff(fp)
            nn[:-1] = np.minimum(nn[:-1], d)
            nn[1:] = np.minimum(nn[1:], d)
        w = P[pk]
        num += float(w[nn < lim].sum())
        den += float(w.sum())
    return num / den if den > 0 else 0.0


def plan_islands(x, sr, X, Y):
    """Split the base map into islands: maximal input spans containing changed
    events, separated by unchanged spans long enough to be exact in renders of
    BOTH window sizes. Each island gets the small window unless its material
    has a large share of closely spaced partials."""
    Ns, Hss = pv_geometry(sr)
    Nb, Hsb = pv_geometry_long(sr)
    need = RESET_RAMP_FRAMES * Hsb + Nb + 256
    regs = unit_regions(X, Y)
    seps = [r for r in regs if r["open_left"] or r["open_right"] or (r["x1"] - r["x0"]) >= need]
    bounds = [(r["x0"], r["x1"]) for r in seps]
    islands = []
    cur = int(X[0])
    for a, b in bounds + [(int(X[-1]), int(X[-1]))]:
        if a > cur:
            islands.append([cur, a])
        cur = max(cur, b)
    for isl in islands:
        frac = close_partial_fraction(x[isl[0]:isl[1]], sr, Ns)
        isl.append(Nb if frac >= CLOSE_FRACTION else Ns)
        isl.append(round(frac, 3))
    return islands, (Ns, Hss), (Nb, Hsb)


# ===========================================================================
# Phase vocoder
# ===========================================================================

def _reset_weights(centres, regions, Hs):
    """Per-frame phase-reset weight w (Delta_k = (1 - w) * Delta_propagated).

    0 outside slope-1 regions (normal vocoding, phase locking on). Inside a
    region the hop equals the synthesis hop, so propagated phase offsets stay
    constant; the reset is spread linearly over the first RESET_RAMP_FRAMES
    frames (w = 1/(R-m)), giving equal steps of at most pi/R per frame.
    Regions touching the signal start are fully reset from the first frame.
    """
    w = np.zeros(len(centres))
    for r in regions:
        R = int(r.get("ramp", RESET_RAMP_FRAMES))
        hi = np.inf if r["open_right"] else r["y1"]
        if r["open_left"]:
            w[centres <= hi] = 1.0
            continue
        inside = (centres >= r["y0"]) & (centres <= hi)
        m = np.floor((centres[inside] - r["y0"]) / Hs)
        w[inside] = np.where(m >= R - 1, 1.0, 1.0 / (R - np.minimum(m, R - 1)))
    return w


def _peaks_and_owner(P, L, smooth_half=16):
    """Local maxima of power P (+-2 bins), tonal flag per peak, owner peak for
    every bin (nearest peak, midpoint boundaries)."""
    K = P.shape[0]
    core = P[2:-2]
    is_pk = ((core > P[1:-3]) & (core >= P[3:-1]) &
             (core > P[0:-4]) & (core >= P[4:]))
    pk = np.nonzero(is_pk)[0] + 2
    if pk.size == 0:
        return pk, np.zeros(0, bool), None
    cs = np.concatenate([[0.0], np.cumsum(L)])
    lo = np.clip(pk - smooth_half, 0, K)
    hi = np.clip(pk + smooth_half + 1, 0, K)
    local_mean = (cs[hi] - cs[lo]) / (hi - lo)
    tonal = (L[pk] - local_mean >= TONAL_DB) & (L[pk] >= L.max() - 100.0)
    if pk.size == 1:
        owner = np.zeros(K, dtype=np.int64)
    else:
        mids = (pk[:-1] + pk[1:]) * 0.5
        owner = np.searchsorted(mids, np.arange(K))
    return pk, tonal, owner


def pv_render(x, X, Y, n_out, N, Hs, regions, chunk=256, sr_hint=44100, energy_correction=True):
    n_in, C = x.shape
    K = N // 2 + 1
    win = np.hanning(N + 1)[:-1]
    pad = 2 * N + Hs
    xp = np.zeros((n_in + 2 * pad, C))
    xp[pad:pad + n_in] = x

    k0 = -int(math.ceil((N / 2.0 + Hs) / Hs))
    k1 = int(math.ceil((n_out + N / 2.0 + Hs) / Hs))
    centres = np.arange(k0, k1 + 1, dtype=np.int64) * Hs
    a_cent = np.rint(inv_center(X, Y, centres)).astype(np.int64)
    a_cent = np.clip(a_cent, -pad + N // 2 + Hs, n_in + pad - N // 2 - 1)
    wreset = _reset_weights(centres.astype(np.float64), regions, Hs)

    opad = 2 * N + 2 * Hs
    out = np.zeros((n_out + 2 * opad + N, C))
    wsum = np.zeros(n_out + 2 * opad + N)
    ar = np.arange(N)
    Yprev = np.zeros((K, C), dtype=np.complex128)
    nfr = len(centres)
    band, nb = _bands(N, sr_hint)
    target = np.zeros((nfr, nb))
    for s0 in range(0, nfr, chunk):
        s1 = min(nfr, s0 + chunk)
        ac = a_cent[s0:s1]
        ic = (ac - N // 2 + pad)[:, None] + ar[None, :]
        ip = ic - Hs
        Xc = np.fft.rfft(xp[ic] * win[None, :, None], axis=1)      # (B,K,C)
        Xp = np.fft.rfft(xp[ip] * win[None, :, None], axis=1)
        pw = np.sum(Xc.real ** 2 + Xc.imag ** 2, axis=2)           # (B,K)
        for bb in range(nb):
            target[s0:s1, bb] = pw[:, band == bb].sum(axis=1)
        Yb = np.empty_like(Xc)
        for b in range(s1 - s0):
            wr = wreset[s0 + b]
            Xcb = Xc[b]
            if wr >= 1.0:
                Yb[b] = Xcb
                Yprev = Xcb
                continue
            # One rotation per bin, estimated coherently from all channels:
            # angle(sum_c Yprev_c * conj(X_c(t_in - Hs))).
            z = np.sum(Yprev * np.conj(Xp[b]), axis=1)
            dphi = np.angle(z)
            if wr == 0.0:
                # identity phase locking around tonal peaks (summed power)
                P = np.sum(Xcb.real ** 2 + Xcb.imag ** 2, axis=1)
                L = 10.0 * np.log10(P + 1e-30)
                pk, tonal, owner = _peaks_and_owner(P, L)
                if pk.size and tonal.any():
                    lock = tonal[owner]
                    dist = np.abs(np.arange(K) - pk[owner])
                    if LOCK_RADIUS == "adaptive":
                        # whole region for well-separated peaks; near the
                        # midpoint between crowded peaks fall back to +-1 bin
                        tp = pk[tonal]
                        sp = np.full(pk.size, np.inf)
                        if tp.size > 1:
                            pos = np.searchsorted(tp, pk)
                            left = np.where(pos > 0, pk - tp[np.clip(pos - 1, 0, tp.size - 1)], np.inf)
                            right = np.where(pos < tp.size, tp[np.clip(pos, 0, tp.size - 1)] - pk, np.inf)
                            right = np.where(right == 0, np.inf, right)
                            # nearest OTHER tonal peak
                            pos2 = np.clip(pos + 1, 0, tp.size - 1)
                            right2 = np.where((pos + 1) < tp.size, tp[pos2] - pk, np.inf)
                            right = np.where(tp[np.clip(pos, 0, tp.size - 1)] == pk, right2, right)
                            sp = np.minimum(left, right)
                        margin = np.where(sp < 6, LOCK_MARGIN, 0)
                        rad = np.maximum(1.0, np.floor(sp / 2.0) - margin)
                        lock &= dist <= rad[owner]
                    elif LOCK_RADIUS is not None:
                        lock &= dist <= LOCK_RADIUS
                    dphi = np.where(lock, dphi[pk[owner]], dphi)
            else:
                dphi = (1.0 - wr) * dphi
            Yc = Xcb * np.exp(1j * dphi)[:, None]
            Yb[b] = Yc
            Yprev = Yc
        frames = np.fft.irfft(Yb, n=N, axis=1) * win[None, :, None]
        starts = centres[s0:s1] - N // 2 + opad
        for b in range(s1 - s0):
            st = starts[b]
            out[st:st + N] += frames[b]
            wsum[st:st + N] += win ** 2
    good = wsum > 1e-6
    out[good] /= wsum[good][:, None]
    out[~good] = 0.0
    if energy_correction and np.any(wreset == 0.0):
        out = _energy_correct(out, centres + opad, wreset, target, band, nb, N, Hs, win)
    return out[opad:opad + n_out]


def _bands(N, sr):
    """Bin -> band index: one band below 100 Hz, then 1/4-octave bands."""
    K = N // 2 + 1
    f = np.arange(K) * sr / float(N)
    edges = [0.0, 100.0]
    while edges[-1] < sr / 2:
        edges.append(edges[-1] * 2 ** 0.25)
    band = np.clip(np.searchsorted(edges, f, side="right") - 1, 0, None)
    # merge bands with fewer than 3 bins into their upper neighbour
    uniq = []
    for b in range(band.max() + 1):
        if (band == b).sum() == 0:
            continue
        uniq.append(b)
    remap = {}
    cur = 0
    count = 0
    for b in uniq:
        remap[b] = cur
        count += (band == b).sum()
        if count >= 3:
            cur += 1
            count = 0
    band = np.array([remap[b] for b in band])
    return band, int(band.max() + 1)


def _energy_correct(out, starts_c, wreset, target, band, nb, N, Hs, win, smooth_s_frames=8,
                    gmin=0.5, gmax=2.0):
    """Restore the analysis energy in vocoded (stretched) frames.

    Overlap-add of frames whose phases are not mutually coherent (noise,
    unresolved partials) loses up to 3.1 dB with a Hann/4 geometry; coherent
    sinusoids lose nothing. The loss is measured, not assumed: the output is
    re-analysed on the same frames, and each 1/4-octave band of each vocoded
    frame gets gain sqrt(sum target / sum output) over +-8 frames (~93 ms at
    44.1 kHz). Phase-reset frames (exact regions, attack zones) keep gain 1."""
    nfr = len(starts_c)
    C = out.shape[1]
    ar = np.arange(N)
    obs = np.zeros((nfr, nb))
    chunk = 256
    for s0 in range(0, nfr, chunk):
        s1 = min(nfr, s0 + chunk)
        ic = (starts_c[s0:s1] - N // 2)[:, None] + ar[None, :]
        Of = np.fft.rfft(out[ic] * win[None, :, None], axis=1)
        pw = np.sum(Of.real ** 2 + Of.imag ** 2, axis=2)
        for bb in range(nb):
            obs[s0:s1, bb] = pw[:, band == bb].sum(axis=1)
    voc = (wreset == 0.0)[:, None]
    tg = np.where(voc, target, 0.0)
    ob = np.where(voc, obs, 0.0)
    ct = np.cumsum(np.vstack([np.zeros((1, nb)), tg]), axis=0)
    co = np.cumsum(np.vstack([np.zeros((1, nb)), ob]), axis=0)
    i = np.arange(nfr)
    lo = np.clip(i - smooth_s_frames, 0, nfr)
    hi = np.clip(i + smooth_s_frames + 1, 0, nfr)
    st = ct[hi] - ct[lo]
    so = co[hi] - co[lo]
    floor = max(float(target.max()), 1e-30) * 1e-8
    g = np.sqrt((st + floor) / (so + floor))
    g = np.clip(g, gmin, gmax)
    g[~voc[:, 0]] = 1.0
    gb = g[:, band]                                             # (nfr, K)
    if np.allclose(gb, 1.0, atol=1e-3):
        return out
    res = np.zeros_like(out)
    wsum = np.zeros(out.shape[0])
    for s0 in range(0, nfr, chunk):
        s1 = min(nfr, s0 + chunk)
        ic = (starts_c[s0:s1] - N // 2)[:, None] + ar[None, :]
        Of = np.fft.rfft(out[ic] * win[None, :, None], axis=1) * gb[s0:s1, :, None]
        fr = np.fft.irfft(Of, n=N, axis=1) * win[None, :, None]
        for b in range(s1 - s0):
            st0 = starts_c[s0 + b] - N // 2
            res[st0:st0 + N] += fr[b]
            wsum[st0:st0 + N] += win ** 2
    good = wsum > 1e-6
    res[good] /= wsum[good][:, None]
    res[~good] = out[~good]
    return res


def splice_unit_regions(out, x, regions, N, Hs, fade=64):
    """Replace vocoder output by the exact source inside every slope-1 region
    wherever all overlapping frames were phase-reset. Returns the list of
    output intervals that are now bit-identical to the source."""
    n_out = out.shape[0]
    n_in = x.shape[0]
    exact = []
    half = N // 2
    for r in regions:
        a = 0 if r["open_left"] else r["y0"] + int(r.get("ramp", RESET_RAMP_FRAMES)) * Hs + half
        b = n_out if r["open_right"] else r["y1"] - half
        a = max(0, a)
        b = min(n_out, b, n_in + r["off"])
        if b - a < 1:
            continue
        src = x[a - r["off"]:b - r["off"]]
        seg = src.copy()
        L = b - a
        fl = 0 if r["open_left"] else min(fade, L // 2)
        fr = 0 if r["open_right"] else min(fade, L // 2)
        if fl:
            g = ((np.arange(fl) + 0.5) / fl)[:, None]
            seg[:fl] = (1 - g) * out[a:a + fl] + g * src[:fl]
        if fr:
            g = ((np.arange(fr) + 0.5) / fr)[::-1][:, None]
            seg[L - fr:] = (1 - g) * out[b - fr:b] + g * src[L - fr:]
        out[a:b] = seg
        exact.append((a + fl, b - fr))
    return exact


# ===========================================================================
# Varispeed and placement
# ===========================================================================

def varispeed_render(x, X, Y, n_out, half_taps=16, beta=8.6, chunk=8192):
    """Band-limited variable-rate read. Pitch follows speed (tape effect)."""
    n_in, C = x.shape
    out = np.zeros((n_out, C))
    for i in range(len(X) - 1):
        y0, y1 = int(Y[i]), int(Y[i + 1])
        speed = (X[i + 1] - X[i]) / float(y1 - y0)
        fc = min(1.0, 1.0 / speed)
        hw = half_taps / fc
        K = int(math.ceil(hw))
        i0b = np.i0(beta)
        for c0 in range(y0, y1, chunk):
            c1 = min(y1, c0 + chunk)
            n = np.arange(c0, c1)
            p = inv_center(X, Y, n)
            base = np.floor(p).astype(np.int64)
            taps = base[:, None] + np.arange(-K + 1, K + 1)[None, :]
            d = p[:, None] - taps
            u = np.clip(d / hw, -1.0, 1.0)
            h = fc * np.sinc(fc * d) * np.i0(beta * np.sqrt(1.0 - u * u)) / i0b
            h[np.abs(d) >= hw] = 0.0
            hs = h.sum(axis=1, keepdims=True)
            h = h / np.where(np.abs(hs) > 1e-12, hs, 1.0)
            valid = (taps >= 0) & (taps < n_in)
            tc = np.clip(taps, 0, n_in - 1)
            hv = np.where(valid, h, 0.0)
            for c in range(C):
                out[c0:c1, c] = np.sum(hv * x[tc, c], axis=1)
    # exact copy in slope-1 regions away from knots (kernel reach)
    reach = int(math.ceil(half_taps / 0.2)) + 2
    copied = 0
    for r in unit_regions(X, Y):
        a = r["y0"] if r["open_left"] else r["y0"] + reach
        b = r["y1"] if r["open_right"] else r["y1"] - reach
        a, b = max(0, a), min(n_out, b)
        if b > a:
            out[a:b] = x[a - r["off"]:b - r["off"]]
            copied += b - a
    return out, copied


def placement_render(x, X, Y, n_out, sr, fade_s=0.005):
    n_in, C = x.shape
    out = np.zeros((n_out, C))
    F = max(1, int(round(fade_s * sr)))
    disc_next = False
    copied_exact = 0
    for i in range(len(X) - 1):
        x0, x1, y0, y1 = int(X[i]), int(X[i + 1]), int(Y[i]), int(Y[i + 1])
        Li, Lo = x1 - x0, y1 - y0
        m = min(Li, Lo)
        seg = x[x0:x0 + m].copy()
        f = min(F, m // 4) if m >= 4 else 0
        if disc_next and f:
            g = 0.5 - 0.5 * np.cos(np.pi * (np.arange(f) + 0.5) / f)
            seg[:f] *= g[:, None]
        disc_after = m < Li or m < Lo
        if disc_after and f and x0 + m < n_in:
            g = 0.5 + 0.5 * np.cos(np.pi * (np.arange(f) + 0.5) / f)
            seg[m - f:] *= g[:, None]
        if not disc_next and not disc_after:
            copied_exact += m
        out[y0:y0 + m] = seg
        disc_next = disc_after
    return out, copied_exact


# ===========================================================================
# Driver
# ===========================================================================

def _compose(renders, islands, X, Y, n_out, Ns):
    """Assemble per-island renders. Seams are placed only where BOTH renders
    are bit-identical to the source, so a seam is sample-exact."""
    keys = sorted(renders)
    common = np.ones(n_out, dtype=bool)
    for k in keys:
        common &= renders[k][1]
    out = renders[Ns][0].copy()
    mask = renders[Ns][1].copy()
    ymap = lambda v: int(np.interp(v, X.astype(float), Y.astype(float)))
    cuts = [0]
    for i in range(len(islands) - 1):
        ya, yb = ymap(islands[i][1]), ymap(islands[i + 1][0])
        seg = np.nonzero(common[ya:yb])[0]
        if seg.size == 0:
            return None, None
        cuts.append(ya + int(seg[seg.size // 2]))
    cuts.append(n_out)
    for i, isl in enumerate(islands):
        a, b = cuts[i], cuts[i + 1]
        o, m = renders[isl[2]]
        out[a:b] = o[a:b]
        mask[a:b] = m[a:b]
    return out, mask


def reconstruct(x, sr, events, method="pv", time_offset=0.0, transients=True):
    """Core entry point (also used by the test-suite). x: (n, C) float64."""
    x = np.asarray(x, dtype=np.float64)
    if x.ndim == 1:
        x = x[:, None]
    n_in, C = x.shape
    info = {"engine_version": VERSION, "method": method, "channels": C,
            "sr": sr, "in_samples": n_in}
    X, Y = build_time_map(events, sr, n_in, time_offset)
    info["planned_out_samples"] = int(Y[-1])
    info["events_mapped"] = int(sum(1 for i in range(len(X) - 1)
                                     if (X[i + 1] - X[i]) != (Y[i + 1] - Y[i])))
    N, Hs = pv_geometry(sr)
    info["window"] = N
    info["hop"] = Hs
    info.update({"onsets_detected": 0, "onsets_protected": 0,
                 "onsets_narrowed": 0, "onsets_unprotected": 0})
    if is_identity_map(X, Y):
        info["identity"] = 1
        info["exact_fraction"] = 1.0
        info["out_samples"] = n_in
        info["knots"] = int(len(X))
        info["map_X"] = X
        info["map_Y"] = Y
        return x.copy(), info
    info["identity"] = 0
    n_out = int(Y[-1])
    if method == "pv":
        islands, (Ns, Hss), (Nb, Hsb) = plan_islands(x, sr, X, Y)
        info["islands"] = len(islands)
        info["islands_long_window"] = int(sum(1 for i in islands if i[2] == Nb))
        kept = []
        if transients:
            ons, rise = detect_onsets(x, sr)
            info["onsets_detected"] = int(len(ons))
            # Event starts that follow unchanged time (usually silence) are
            # protected too, at the lowest priority: the analysis window there
            # would otherwise smear the event's first N/2 into the silence
            # (vocoder pre-echo) even when the attack is soft.
            starts = []
            for k in range(1, len(X) - 1):
                prev_unit = (X[k] - X[k - 1]) == (Y[k] - Y[k - 1])
                next_unit = (X[k + 1] - X[k]) == (Y[k + 1] - Y[k])
                if prev_unit and not next_unit:
                    if ons.size == 0 or np.min(np.abs(ons - X[k])) > int(0.03 * sr):
                        starts.append(int(X[k]))
            info["event_starts_added"] = len(starts)
            if starts:
                ons = np.concatenate([ons, np.asarray(starts, dtype=np.int64)])
                rise = np.concatenate([rise, np.zeros(len(starts))])
                order = np.argsort(ons, kind="stable")
                ons, rise = ons[order], rise[order]
            Nfor = np.full(len(ons), Ns)
            for a_, b_, n_, _ in islands:
                Nfor[(ons >= a_) & (ons < b_)] = n_
            pre = Nfor // 2 + (Nfor // 4) // 2
            post = Nfor // 2 + Nfor // 4
            X, Y, st, kept = protect_onsets(X, Y, ons, pre=pre, post=post, strength=rise)
            info["onsets_protected"] = st["zones"]
            info["onsets_narrowed"] = st["narrowed"]
            info["onsets_unprotected"] = st["skipped"]
        used = sorted(set(i[2] for i in islands)) or [Ns]
        renders = {}
        for Nw in used:
            Hw = Nw // 4
            regions = assign_ramps(unit_regions(X, Y), kept, Nw, Hw)
            o = pv_render(x, X, Y, n_out, Nw, Hw, regions, sr_hint=sr)
            ex = splice_unit_regions(o, x, regions, Nw, Hw)
            m = np.zeros(n_out, dtype=bool)
            for a_, b_ in ex:
                m[a_:b_] = True
            renders[Nw] = (o, m)
        if len(used) == 1:
            out, mask = renders[used[0]]
        else:
            out, mask = _compose(renders, islands, X, Y, n_out, Ns)
            if out is None:       # no exact seam available: single long window
                info["islands_long_window"] = len(islands)
                out, mask = renders[Nb]
        info["window"] = int(used[-1]) if len(used) == 1 else "%d/%d" % (Ns, Nb)
        info["hop"] = int(used[-1] // 4) if len(used) == 1 else "%d/%d" % (Hss, Hsb)
        copied = int(mask.sum())
    elif method == "varispeed":
        out, copied = varispeed_render(x, X, Y, n_out)
    elif method == "placement":
        out, copied = placement_render(x, X, Y, n_out, sr)
    else:
        raise ValueError("unknown method: %s" % method)
    if not np.all(np.isfinite(out)):
        raise FloatingPointError("non-finite samples in reconstruction")
    info["out_samples"] = int(out.shape[0])
    info["exact_fraction"] = round(copied / float(max(1, n_out)), 4)
    info["knots"] = int(len(X))
    info["map_X"] = X
    info["map_Y"] = Y
    return out, info


def read_args_file(path):
    """One argument per line. Praat may write UTF-8, Latin-1 or UTF-16 (BOM)
    depending on its text-writing preference and the characters in a path."""
    raw = open(path, "rb").read()
    if raw.startswith(b"\xff\xfe") or raw.startswith(b"\xfe\xff"):
        txt = raw.decode("utf-16")
    else:
        try:
            txt = raw.decode("utf-8-sig")
        except UnicodeDecodeError:
            txt = raw.decode("latin-1")
    return [ln.rstrip("\r") for ln in txt.split("\n") if ln.strip() != ""]


def main():
    import argparse
    ap = argparse.ArgumentParser(description="Temporal Elasticity reconstruction engine")
    ap.add_argument("source_wav")
    ap.add_argument("durations_csv")
    ap.add_argument("out_wav")
    ap.add_argument("report_txt")
    ap.add_argument("--method", choices=["pv", "varispeed", "placement"], default="pv")
    ap.add_argument("--time_offset", type=float, default=0.0,
                    help="Start time of the Praat Sound (xmin)")
    ap.add_argument("--input_gain", type=float, default=1.0,
                    help="Multiply source by this (power of two, undoes the "
                         "exact pre-export attenuation of hot sources)")
    ap.add_argument("--no_transients", action="store_true")
    argv = sys.argv[1:]
    if len(argv) == 1 and argv[0].startswith("@"):
        argv = read_args_file(argv[0][1:])
    a = ap.parse_args(argv)

    print("  [TR] Temporal Elasticity reconstruction v%s (%s)" % (VERSION, a.method))
    x, sr = sf.read(a.source_wav, always_2d=True, dtype="float64")
    if a.input_gain != 1.0:
        x = x * a.input_gain
    events = read_durations_csv(a.durations_csv)
    if not events:
        print("FATAL: no usable rows in %s" % a.durations_csv, file=sys.stderr)
        sys.exit(2)
    out, info = reconstruct(x, sr, events, a.method, a.time_offset,
                            transients=not a.no_transients)
    info["peak_in"] = round(float(np.max(np.abs(x))) if x.size else 0.0, 6)
    info["peak_out"] = round(float(np.max(np.abs(out))) if out.size else 0.0, 6)
    tmp = a.out_wav + ".part.wav"
    sf.write(tmp, out, sr, subtype="DOUBLE")
    os.replace(tmp, a.out_wav)
    with open(a.report_txt, "w") as f:
        f.write("te_reconstruct_report\n")
        for k in ("engine_version", "method", "identity", "channels", "sr",
                  "in_samples", "planned_out_samples", "out_samples",
                  "events_mapped", "window", "hop", "islands", "islands_long_window",
                  "onsets_detected",
                  "onsets_protected", "onsets_narrowed", "onsets_unprotected",
                  "exact_fraction", "peak_in", "peak_out"):
            if k in info:
                f.write("%s=%s\n" % (k, info[k]))
    print("    out: %d samples x %d ch (planned %d), exact %.1f%%" % (
        info["out_samples"], info["channels"], info["planned_out_samples"],
        100 * info["exact_fraction"]))
    print("OK: %s" % a.out_wav)


if __name__ == "__main__":
    main()
