"""
# ============================================================
# Praat AudioTools - internal_polyphony.py
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 2.6 (2026)
#
# Changelog v2.4:
#   - Reverts v2.3 whole-role edge fades: user listening showed they did not
#     address the click source and could make articulation worse.
#   - Correlated self-overlap guard for sparse/short sources. When Support has
#     only one harvested fragment, render it as a sequential crossfade loop
#     instead of stacking 3-5 heavily overlapping copies of the same waveform.
#   - Halo layer count is capped by the number of unique harvested fragments.
#     Halo amount still controls gain/formal emphasis, but a one-fragment Halo
#     can no longer create several phase-correlated duplicates at random offsets.
#
# Changelog v2.2:
#   - Adaptive short-source fragment rescue: if the normal dominance/minfrag
#     pass finds ZERO usable fragments across all roles, retry only then with
#     a shorter 30-80 ms minimum (scaled to source duration), a relaxed
#     dominance threshold, and gap merging. Normal successful runs are
#     unchanged sample-for-sample.
#   - Report exposes short_source_rescue and effective_minfrag for QC.
# License: MIT License
#
# Changelog v2.1:
#   - Phase-safe mono fallback for anti-phase multichannel material.
#   - Short-input STFT pads to one full FFT frame instead of crashing when
#     scipy shrinks nperseg below the requested noverlap.
#   - Robust fragment placement clips negative/oversize placements; fixes
#     Shimmer crashes when a source fragment exceeds a compressed target.
#   - Corrected DiversePool documentation: diversity discourages repeats but
#     quality can legitimately override it; the audio-selection law is unchanged.
#   - --maxoverlap retained only as hidden legacy CLI compatibility because
#     v2 role engines use their own role-specific overlap laws.
#
# Description:
#   Internal Polyphony v2
#
# Changelog v2.6:
#   - Process trace export (--trace). The JSON report only ever carried
#     end-state scalars, so the Praat figure could only draw a before/after
#     dashboard. The trace records the three stages that actually make the
#     piece -- what was HARVESTED (source intervals per role), where it was
#     PLACED (target intervals + nominal gain, with source-fragment identity
#     preserved), and how the mode STAGED it (per-role offset and gain law).
#     Written as a tab-separated Table that Praat reads directly.
#   - Audio path is unchanged: tracing is pure observation, no resynthesis
#     value is computed from it.
#
# v2.5 click-fix:
#   _place() only performs ducking crossfade for explicitly sequential
#   placement. Overlapping Body/Shimmer voices use plain overlap-add because
#   source fragments already carry edge fades. Hard-truncated role tails and
#   Counterpoint/Canon shift truncations receive a short local release.
#   Rebuilt on five structural improvements over v1:
#
#   1. EACH ROLE HAS ITS OWN VOICE ENGINE.
#      Support drones slowly with breath modulation.
#      Body breathes in phrases with natural gaps.
#      Accent punctuates with enforced separation (no overlap).
#      Halo sustains with arc envelopes, fading in mid-piece.
#      Residue seeps at low amplitude as irregular scatter.
#      Shimmer flickers rapidly as an upper counterline.
#      These are not one tiling function with different overlap fractions.
#
#   2. MODES ARE FORMAL COMPOSITIONAL LOGICS.
#      Reveal: each role emerges from silence at a different point.
#      Counterpoint: staggered independent entry times per role.
#      Canon: true canonic delay chain (support->body->halo->shimmer).
#      PedalHalo: pedal and halo foregrounded, body recedes.
#      FracturedChoir: all voices at high density with independent
#        amplitude modulation.
#
#   3. FRAGMENT SELECTION USES DIVERSITY SCORING.
#      DiversePool tracks recency per fragment. Score = quality_score
#      * diversity_bonus + jitter. Recent fragments are discouraged, while
#      strong source material can still win again before a full pool cycle.
#
#   4. ABSENCE IS PERMITTED.
#      If a role is genuinely absent from the NMF analysis, its voice
#      is silent. We do NOT fabricate fragments. A sound with only
#      3 genuine roles produces a trio, not a forced sextet.
#
#   5. METRICS ARE MUSICALLY MEANINGFUL.
#      novelty_ratio     = RMS(output - dry) / RMS(dry)  [signal distance]
#      overlap_density   = fraction of frames with >=2 simultaneous voices
#      voice_independence = mean (1 - |correlation|) across voice pairs
#
# Pipeline:
#   A  Audio I/O
#   B  STFT (full / hpss / transient analysis modes)
#   C  NMF decomposition
#   D  Component descriptors (14 acoustic features)
#   E  Rule-based role inference
#   F  Fragment harvesting with diversity-aware selection
#   G  Per-role voice engines
#   H  Mode-level compositional staging
#   I  Stereo rendering
#   J  Clean metrics + JSON/CSV report
#
# Dependencies:  pip install numpy scipy soundfile
#
# Example:
#   python internal_polyphony.py \
#     --input in.wav --output out.wav --report out.json \
#     --components 10 --mode counterpoint --density 0.65 --seed 42
# ============================================================
"""

import sys
import os
import math
import json
import csv
import argparse
import numpy as np

# ---------------------------------------------------------------------------
ROLE_NAMES = ["support", "body", "accent", "halo", "residue", "shimmer"]

ROLE_PAN = {
    "support":  0.50,
    "body":     0.42,
    "accent":   0.58,
    "halo":     0.25,
    "residue":  0.72,
    "shimmer":  0.50,
}

ROLE_VOL = {
    "support":  0.70,
    "body":     0.82,
    "accent":   0.78,
    "halo":     0.52,
    "residue":  0.42,
    "shimmer":  0.48,
}

XFADE_SEC = 0.014


# ---------------------------------------------------------------------------
# Process trace. Observation only -- nothing here feeds back into the audio.
# ---------------------------------------------------------------------------

_TRACE = {"frags": [], "places": [], "stage": [], "role": None, "idx": 0}


def _trace_reset():
    _TRACE["frags"] = []
    _TRACE["places"] = []
    _TRACE["stage"] = []
    _TRACE["role"] = None
    _TRACE["idx"] = 0


def _trace_role(role):
    _TRACE["role"] = role
    _TRACE["idx"] = 0


def _trace_harvest(role, frags, sr):
    for i, (frag, score, t0) in enumerate(frags):
        _TRACE["frags"].append((role, i, float(t0),
                                float(t0) + len(frag) / float(sr),
                                float(score)))


def _trace_place(cursor, n_samples, gain, sr):
    if _TRACE["role"] is None or n_samples <= 0:
        return
    _TRACE["places"].append((_TRACE["role"], int(_TRACE["idx"]),
                             float(cursor) / float(sr),
                             float(cursor + n_samples) / float(sr),
                             float(gain)))


def _trace_stage(role, offset_sec, gain, law, extra=0.0):
    """gain is always the MEAN level multiplier the law applies; any other
    parameter of the law (an AM rate, say) goes in extra so it can never be
    mistaken for a gain downstream."""
    _TRACE["stage"].append((role, float(offset_sec), float(gain), law,
                            float(extra)))


def write_trace(path, sr, src_dur, tgt_dur, mode):
    """Tab-separated process trace, read directly by the Praat figure."""
    with open(path, "w") as fh:
        fh.write("kind\trole\tidx\tt0\tt1\tv1\tv2\tlaw\n")
        fh.write("meta\tsource\t0\t0\t{:.6f}\t0\t0\t{}\n".format(src_dur, mode))
        fh.write("meta\ttarget\t0\t0\t{:.6f}\t0\t0\t{}\n".format(tgt_dur, mode))
        for role, i, t0, t1, sc in _TRACE["frags"]:
            fh.write("frag\t{}\t{}\t{:.6f}\t{:.6f}\t{:.6f}\t0\t-\n".format(
                role, i, t0, t1, sc))
        for role, i, t0, t1, g in _TRACE["places"]:
            fh.write("place\t{}\t{}\t{:.6f}\t{:.6f}\t{:.6f}\t0\t-\n".format(
                role, i, t0, t1, g))
        for role, off, g, law, extra in _TRACE["stage"]:
            fh.write("stage\t{}\t0\t{:.6f}\t0\t{:.6f}\t{:.6f}\t{}\n".format(
                role, off, g, extra, law))
    print("    Trace:  {}  ({} frags, {} placements)".format(
          path, len(_TRACE["frags"]), len(_TRACE["places"])))


# ===========================================================================
# A. Audio I/O
# ===========================================================================

def load_audio(path):
    import soundfile as sf
    audio, sr = sf.read(path, always_2d=True)
    audio = audio.astype(np.float32)
    print("    Loaded: {:.3f}s | SR={} | Ch={} | peak={:.4f}".format(
        audio.shape[0]/sr, sr, audio.shape[1],
        float(np.max(np.abs(audio)))))
    return audio, sr, audio.shape[1]


def save_audio(path, audio, sr, subtype=None):
    import soundfile as sf
    if subtype is None:
        # Default: FLOAT for stereo/mono, PCM_16 for multichannel.
        # Praat reads PCM WAV reliably for any channel count;
        # 32-bit float WAV can cause silent channel collapse in Praat.
        n_ch = audio.shape[1] if audio.ndim == 2 else 1
        subtype = 'PCM_16' if n_ch > 2 else 'FLOAT'
    sf.write(path, audio.astype(np.float32), sr, subtype=subtype)
    n_ch = audio.shape[1] if audio.ndim == 2 else 1
    print("    Saved:  {}  ({:.3f}s, {} ch, {})".format(
          path, audio.shape[0]/sr, n_ch, subtype))


def to_mono(audio):
    """Phase-safe mono reference.

    Preserve the historical arithmetic mean for ordinary multichannel input.
    Only when that mean nearly collapses relative to the strongest channel
    (classic anti-phase / polarity-cancellation case) use the strongest
    channel instead. This prevents analysis and harvested fragments from
    becoming silent while leaving normal stereo behavior unchanged.
    """
    a = np.asarray(audio)
    if a.ndim == 1:
        return a.astype(np.float32)
    if a.shape[1] == 1:
        return a[:, 0].astype(np.float32)

    mean = a.mean(axis=1).astype(np.float32)
    ch_rms = np.sqrt(np.mean(a.astype(np.float64) ** 2, axis=0) + 1e-20)
    strongest = int(np.argmax(ch_rms))
    strongest_rms = float(ch_rms[strongest])
    mean_rms = float(np.sqrt(np.mean(mean.astype(np.float64) ** 2) + 1e-20))
    if strongest_rms > 1e-9 and mean_rms < 0.10 * strongest_rms:
        return a[:, strongest].astype(np.float32)
    return mean


def safe_normalize(audio, headroom=0.92):
    peak = float(np.max(np.abs(audio)))
    if peak < 1e-9:
        return audio.copy(), peak
    return (audio * (headroom / peak)).astype(np.float32), peak


# ===========================================================================
# B. STFT Analysis
# ===========================================================================

def compute_stft(mono, sr, n_fft, hop):
    from scipy.signal import stft as _stft
    x = mono.astype(np.float64)
    # scipy silently shrinks nperseg when the signal is shorter than n_fft,
    # but then the requested noverlap can become illegal. Zero-padding to one
    # full analysis frame preserves the requested FFT/hop geometry and makes
    # short sounds a supported case without changing normal-length analysis.
    if len(x) < n_fft:
        x = np.pad(x, (0, n_fft - len(x)))
    freqs, _, Zxx = _stft(
        x, fs=sr,
        window="hann", nperseg=n_fft,
        noverlap=n_fft - hop, nfft=n_fft,
        boundary="zeros", padded=True,
    )
    return (np.abs(Zxx).astype(np.float32),
            np.angle(Zxx).astype(np.float32),
            freqs.astype(np.float32))


def hpss_weight(mag, kh=31, kp=31):
    from scipy.ndimage import median_filter
    harm = median_filter(mag, size=(1, kh)).astype(np.float32)
    perc = median_filter(mag, size=(kp, 1)).astype(np.float32)
    eps  = 1e-8
    h_m  = harm / (harm + perc + eps)
    p_m  = 1.0 - h_m
    print("    HPSS weight applied.")
    return (mag * (0.65*h_m + 0.25 + 0.10*p_m)).astype(np.float32)


def transient_weight(mag):
    flux     = np.diff(mag, axis=1, prepend=mag[:, :1])
    flux_pos = np.maximum(flux, 0).astype(np.float32)
    col_norm = flux_pos.sum(axis=0, keepdims=True) + 1e-8
    print("    Transient-enhanced weighting applied.")
    return (mag * (1.0 + 0.6 * flux_pos / col_norm)).astype(np.float32)


# ===========================================================================
# C. NMF
# ===========================================================================

def nmf_decompose(mag, K, n_iter=150, seed=42):
    """KL-divergence NMF. Returns W[F,K], H[K,T], rel_RMSE."""
    rng  = np.random.RandomState(seed)
    F, T = mag.shape
    eps  = 1e-9
    sc   = mag.mean() + eps
    W    = rng.rand(F, K).astype(np.float64) * sc
    H    = rng.rand(K, T).astype(np.float64) * sc
    V    = mag.astype(np.float64) + eps
    log_every = max(1, n_iter // 4)

    for it in range(n_iter):
        WH = W.dot(H) + eps
        H *= W.T.dot(V / WH) / (W.sum(axis=0, keepdims=True).T + eps)
        H  = np.maximum(H, eps)
        WH = W.dot(H) + eps
        W *= (V / WH).dot(H.T) / (H.sum(axis=1, keepdims=True).T + eps)
        W  = np.maximum(W, eps)
        if (it + 1) % log_every == 0:
            print("    NMF iter {:3d}/{} mse={:.6f}".format(
                it+1, n_iter, float(np.mean((V - WH)**2))))

    cm = W.max(axis=0) + eps
    W /= cm
    H *= cm[:, np.newaxis]
    WH = W.dot(H)
    re = float(np.sqrt(np.mean((V - WH)**2)) /
               (np.sqrt(np.mean(V**2)) + eps))
    print("    NMF done. Rel-RMSE = {:.5f}".format(re))
    return W.astype(np.float32), H.astype(np.float32), re


def effective_rank(H, thr=0.90):
    en  = np.sum(H**2, axis=1)
    tot = en.sum() + 1e-12
    cs  = np.cumsum(np.sort(en)[::-1])
    return int(min(np.searchsorted(cs, thr * tot) + 1, len(H)))


# ===========================================================================
# D. Descriptors
# ===========================================================================

def compute_descriptors(W, H, freqs, sr, hop):
    K, T = W.shape[1], H.shape[1]
    out  = []
    for k in range(K):
        w     = W[:, k].astype(np.float64)
        h     = H[k, :].astype(np.float64)
        ws    = w.sum() + 1e-12
        hmax  = h.max() + 1e-12

        centroid = float(np.dot(freqs, w) / ws)
        bw       = float(np.sqrt(np.dot((freqs - centroid)**2, w) / ws))
        wp       = np.maximum(w, 1e-12)
        flatness = float(min(np.exp(np.mean(np.log(wp))) / (np.mean(wp) + 1e-12), 1.0))

        lo_e  = float(w[freqs <  300 ].sum() / ws)
        mid_e = float(w[(freqs >= 300)  & (freqs < 2000)].sum() / ws)
        hi_e  = float(w[(freqs >= 2000) & (freqs < 6000)].sum() / ws)
        up_e  = float(w[freqs >= 6000].sum() / ws)

        sparsity   = float((h < 0.20 * hmax).mean())
        flux_pos   = np.maximum(np.diff(h, prepend=h[:1]), 0)
        onset_aff  = float(flux_pos.sum() / (h.sum() + 1e-12))
        sustain    = float((h >= 0.30 * hmax).mean())

        mod_rate   = 0.0
        recurrence = 0.0
        roughness  = 0.0
        ac         = None

        if T > 16:
            hc  = h - h.mean()
            ac  = np.correlate(hc, hc, mode="full")
            ac  = ac[len(ac)//2:]
            ac /= ac[0] + 1e-12
            limit = min(T//3, int(sr / (hop * 0.5)))
            for lag in range(2, max(3, limit)):
                if ac[lag] > ac[lag-1] and ac[lag] > ac[lag+1]:
                    mod_rate = 1.0 / (lag * hop / sr + 1e-9)
                    break
        if T > 32 and ac is not None:
            lo_l = max(1, T//20)
            hi_l = max(lo_l+1, T//5)
            recurrence = float(np.clip(ac[lo_l:hi_l].mean(), 0.0, 1.0))
        if T > 4:
            d2h       = np.diff(h, n=2)
            roughness = float(np.std(d2h) / (np.std(h) + 1e-12))

        energy = float(h.sum() / (T + 1e-12) / (hmax + 1e-12))
        out.append({
            "centroid":   centroid, "bandwidth": bw,
            "flatness":   flatness, "lo_e":      lo_e,
            "mid_e":      mid_e,    "hi_e":      hi_e,
            "up_e":       up_e,     "sparsity":  sparsity,
            "onset_aff":  onset_aff,"sustain":   sustain,
            "mod_rate":   mod_rate, "recurrence":recurrence,
            "roughness":  roughness,"energy":    energy,
        })
    return out


# ===========================================================================
# E. Role Inference
# ===========================================================================

def infer_roles(descs, sr):
    """
    Explicit rule-based role assignment from acoustic descriptors.
    No clustering. No machine learning. Rules ordered most->least specific.
    """
    from collections import Counter
    roles = []
    for d in descs:
        c, fl, sp = d["centroid"], d["flatness"], d["sparsity"]
        oa, su, lo = d["onset_aff"], d["sustain"], d["lo_e"]
        rc, rg = d["recurrence"], d["roughness"]

        if c > 5500 and su > 0.15 and rc > 0.08:
            role = "shimmer"
        elif c > 2800 and su > 0.30 and oa < 0.12:
            role = "halo"
        elif sp > 0.50 and oa > 0.08:
            role = "accent"
        elif fl > 0.28 and rg > 0.5:
            role = "residue"
        elif lo > 0.40 and su > 0.35 and sp < 0.55:
            role = "support"
        elif d["mid_e"] > 0.25 and su > 0.25:
            role = "body"
        elif c < 700:
            role = "support"
        elif c < 2500:
            role = "body"
        elif c < 5500:
            role = "halo"
        else:
            role = "shimmer"
        roles.append(role)

    print("    Roles: {}".format(dict(Counter(roles))))
    return roles


# ===========================================================================
# F. Fragment Harvesting
# ===========================================================================

def role_dominance(H, roles, T):
    dom   = {r: np.zeros(T, dtype=np.float64) for r in ROLE_NAMES}
    total = np.zeros(T, dtype=np.float64)
    for k, r in enumerate(roles):
        if r in dom:
            dom[r] += H[k, :T].astype(np.float64)
            total  += H[k, :T].astype(np.float64)
    total += 1e-10
    return {r: (dom[r]/total).astype(np.float32) for r in ROLE_NAMES}


def dom_to_intervals(dom, hop, sr, thr, min_dur, merge_gap=0.04):
    active    = dom > thr
    fsec      = hop / sr

    # Vectorized run-length encoding of active regions
    if not np.any(active):
        return []

    # Pad with False at both ends to detect edges
    padded = np.concatenate([[False], active, [False]])
    edges = np.diff(padded.astype(np.int8))
    starts = np.where(edges == 1)[0]   # rising edges
    ends   = np.where(edges == -1)[0]  # falling edges

    intervals = []
    for s, e in zip(starts, ends):
        if (e - s) * fsec >= min_dur:
            intervals.append((s * fsec, e * fsec))

    if not intervals:
        return []
    merged = [list(intervals[0])]
    for s, e in intervals[1:]:
        if s - merged[-1][1] <= merge_gap:
            merged[-1][1] = e
        else:
            merged.append([s, e])
    return [(a, b) for a, b in merged]


def extract_fragment(audio, sr, t0, t1, fi=0.010, fo=0.012):
    n  = len(audio)
    s  = max(0, int(t0 * sr))
    e  = min(n, int(t1 * sr))
    if e <= s:
        return None
    f  = audio[s:e].copy().astype(np.float32)
    fl = len(f)
    fn = max(2, min(int(fi*sr), fl//5))
    on = max(2, min(int(fo*sr), fl//5))
    fi_env = (0.5*(1.0 - np.cos(np.pi*np.arange(fn)/fn))).astype(np.float32)
    fo_env = (0.5*(1.0 + np.cos(np.pi*np.arange(on)/on))).astype(np.float32)
    if f.ndim == 2:
        f[:fn]  *= fi_env[:, np.newaxis]
        f[-on:] *= fo_env[:, np.newaxis]
    else:
        f[:fn]  *= fi_env
        f[-on:] *= fo_env
    return f


def harvest_fragments(audio, sr, hop, dom, intervals, min_frag):
    out = []
    for t0, t1 in intervals:
        if t1 - t0 < min_frag:
            continue
        f0 = max(0, int(t0 * sr / hop))
        f1 = min(len(dom), int(t1 * sr / hop) + 1)
        score = float(dom[f0:f1].mean()) if f1 > f0 else 0.0
        if score < 0.05:
            continue
        frag = extract_fragment(audio, sr, t0, t1)
        if frag is not None and len(frag) >= int(min_frag * sr * 0.5):
            out.append((frag, score, t0))
    out.sort(key=lambda x: x[1], reverse=True)
    return out


# ===========================================================================
# G. Per-Role Voice Engines
# ===========================================================================

class DiversePool:
    """
    Fragment pool with diversity-aware selection.
    Effective score = quality * diversity_bonus + jitter.
    Recent reuse is penalized but not forbidden: a very strong fragment may
    legitimately win again before every weaker fragment has been visited.
    """
    def __init__(self, frags, rng):
        self.frags    = list(frags)
        self.visits   = [0] * len(frags)
        self.last_use = [-1] * len(frags)
        self.step     = 0
        self.rng      = rng

    def pick(self, exclude=-1):
        if not self.frags:
            return None, -1
        n      = len(self.frags)
        scores = []
        for i, (_, base, _) in enumerate(self.frags):
            since   = (self.step - self.last_use[i]
                       if self.last_use[i] >= 0 else n)
            div_b   = min(since, n) / (n + 1.0)
            jitter  = self.rng.rand() * 0.08
            eff     = base * (0.5 + 0.5 * div_b) + jitter
            if i == exclude:
                eff -= 1.0
            scores.append(eff)
        idx = int(np.argmax(scores))
        _TRACE["idx"] = idx
        self.visits[idx]  += 1
        self.last_use[idx] = self.step
        self.step         += 1
        return self.frags[idx], idx

    def __len__(self):
        return len(self.frags)


def _place(stream, frag, cursor, vol=1.0, xfade=0, sequential=False):
    """Place a mono fragment into ``stream`` with safe clipping.

    Plain overlap-add is the default.  The historical ducking crossfade is
    valid only for strict sequential append, where the existing signal ends
    exactly at the crossfade boundary.  Applying it to arbitrary overlapping
    placements (Body/Shimmer) forces the underlying stream toward zero and
    then restores it in one sample at ``cursor + xfade``, creating clicks.
    """
    mono = to_mono(frag).astype(np.float32) * vol
    fl_orig = len(mono)
    cursor = int(cursor)

    # A fragment can be longer than the target (notably Shimmer when expand
    # < 1). Clip the source head if placement starts before zero instead of
    # letting negative numpy slices produce a broadcast failure.
    src0 = 0
    if cursor < 0:
        src0 = min(-cursor, len(mono))
        mono = mono[src0:]
        cursor = 0
    if cursor >= len(stream) or len(mono) == 0:
        return max(0, cursor + max(0, fl_orig - src0))

    end = min(len(stream), cursor + len(mono))
    wl  = end - cursor
    if wl <= 0:
        return cursor
    _trace_place(cursor, wl, vol, _TRACE.get("sr", 44100))
    if sequential and xfade > 2 and cursor > 0:
        xf  = min(xfade, wl, cursor)
        env = (0.5*(1.0 - np.cos(np.pi*np.arange(xf)/xf))).astype(np.float32)
        stream[cursor:cursor+xf] *= (1.0 - env)
        stream[cursor:cursor+xf] += mono[:xf] * env
        stream[cursor+xf:end]    += mono[xf:wl]
    else:
        stream[cursor:end] += mono[:wl]
    return cursor + len(mono)


def _release_tail(stream, sr, release_sec=0.012):
    """Fade only an actually hard-truncated stream tail to zero in-place."""
    if stream is None or len(stream) < 2:
        return stream
    n = min(len(stream), max(4, int(release_sec * sr)))
    env = (0.5 + 0.5 * np.cos(
        np.linspace(0.0, math.pi, n, endpoint=True))).astype(np.float32)
    stream[-n:] *= env
    return stream


def _arc(n):
    """Smooth arc envelope: rise 30% / flat 40% / fall 30%."""
    rn = int(n * 0.30); fn = int(n * 0.30); pn = n - rn - fn
    r  = 0.5*(1.0 - np.cos(np.pi*np.arange(rn)/max(1,rn)))
    p  = np.ones(pn)
    f  = 0.5*(1.0 + np.cos(np.pi*np.arange(fn)/max(1,fn)))
    return np.concatenate([r, p, f]).astype(np.float32)


def build_support(frags, target, sr, density, rng):
    """
    Drone layer. Longest fragments, very heavy overlap, breath modulation.

    Sparse-pool guard: when only ONE fragment exists (common after the
    short-source rescue), do not stack several phase-correlated copies at
    30-50% offsets. Instead repeat it sequentially with a short crossfade.
    This preserves the drone role while avoiding combing/beating from exact
    self-overlap. Multi-fragment behavior is unchanged.
    """
    stream = np.zeros(target, dtype=np.float32)
    if not frags:
        return stream

    # A one-fragment pool otherwise repeats the exact same waveform several
    # times with heavy overlap. For short sources that correlated stacking is
    # far more audible than the intended polyphony and can sound clicky.
    if len(frags) == 1:
        frag = frags[0][0]
        mono = to_mono(frag).astype(np.float32)
        fl = len(mono)
        if fl == 0:
            return stream
        xf = min(max(8, int(0.020 * sr)), max(8, fl // 4))
        _TRACE["idx"] = 0
        step = max(1, fl - xf)
        cursor = 0
        while cursor < target:
            _place(stream, mono, cursor, vol=0.90,
                   xfade=xf if cursor > 0 else 0, sequential=True)
            cursor += step
        # One slow breath envelope over the ROLE, not restarted per repeat.
        cyc = 0.5 + rng.rand() * 1.5
        ph  = rng.rand() * 2.0 * math.pi
        t_e = np.linspace(0, cyc * 2 * math.pi, target)
        env = (0.75 + 0.25 * np.sin(t_e + ph)).astype(np.float32)
        stream *= env
        # If the final repetition was truncated by target length, guarantee a
        # clean actual endpoint. This is local to the render boundary.
        fo = min(max(4, int(0.012 * sr)), max(1, target // 4))
        if fo > 1:
            out_env = (0.5 + 0.5 * np.cos(
                np.linspace(0.0, math.pi, fo, endpoint=True))).astype(np.float32)
            stream[-fo:] *= out_env
        return stream

    # Historical multi-fragment path: unchanged.
    pool   = DiversePool(sorted(frags, key=lambda x: len(x[0]), reverse=True), rng)
    cursor = 0
    last   = -1
    truncated = False
    for _ in range(int(density * 2.5) * 3 + 2):
        if cursor >= target:
            break
        (frag, score, _), idx = pool.pick(exclude=last)
        mono = to_mono(frag).astype(np.float32)
        fl   = len(mono)
        vol  = 0.80 + rng.rand() * 0.20
        # Slow sine breath envelope
        el   = min(fl, target - cursor)
        cyc  = 0.5 + rng.rand() * 1.5
        ph   = rng.rand() * 2.0 * math.pi
        t_e  = np.linspace(0, cyc * 2 * math.pi, el)
        env  = (0.75 + 0.25 * np.sin(t_e + ph)).astype(np.float32)
        mono[:el] *= env
        end = min(target, cursor + fl)
        if cursor + fl > target:
            truncated = True
        _trace_place(cursor, end - cursor, vol, sr)
        stream[cursor:end] += mono[:end-cursor] * vol
        # Very heavy overlap: advance only 30-50% of length
        cursor += max(int(fl*(0.30+rng.rand()*0.20)), int(0.10*sr))
        last = idx
    if truncated:
        _release_tail(stream, sr)
    return stream


def build_body(frags, target, sr, density, rng):
    """
    Sustained harmonic core. Phrases with natural gaps and moderate overlap.
    Not gapless like support, not sparse like accent.
    """
    stream = np.zeros(target, dtype=np.float32)
    if not frags:
        return stream
    pool     = DiversePool(frags, rng)
    n_events = max(2, int(target/sr * density * 3.0))
    last     = -1
    truncated = False
    for ev in range(n_events):
        if pool.step >= len(pool) * 4:
            break
        (frag, score, _), idx = pool.pick(exclude=last)
        fl   = len(to_mono(frag))
        vol  = 0.75 + rng.rand() * 0.25
        # Spread events across piece with jitter
        frac   = ev / max(1, n_events)
        base   = int(frac * target)
        jitter = int(rng.randint(-int(0.15*sr), int(0.15*sr)+1))
        cursor = max(0, min(target - fl, base + jitter))
        if cursor + fl > target:
            truncated = True
        _place(stream, frag, cursor, vol=vol)
        last = idx
    if truncated:
        _release_tail(stream, sr)
    return stream


def build_accent(frags, target, sr, density, prominence, rng):
    """
    Sparse transient punctuation. No overlap by design.
    Minimum separation enforced between events.
    """
    stream    = np.zeros(target, dtype=np.float32)
    if not frags:
        return stream
    pool      = DiversePool(frags, rng)
    min_sep   = int(0.25 * sr)
    n_events  = max(1, int(density * target/sr * 1.5))
    placed_at = []
    last      = -1
    for _ in range(n_events):
        if pool.step >= len(pool) * 3:
            break
        (frag, score, _), idx = pool.pick(exclude=last)
        fl = len(to_mono(frag))
        for attempt in range(20):
            cursor = rng.randint(0, max(1, target - fl))
            if all(abs(cursor - p) >= min_sep for p in placed_at):
                break
        vol = (0.70 + rng.rand()*0.30) * (0.6 + 0.4*prominence)
        _place(stream, frag, cursor, vol=vol, xfade=0)
        placed_at.append(cursor)
        last = idx
    return stream


def build_halo(frags, target, sr, density, halo_amount, rng):
    """
    Sustained glow with arc envelopes. Fragments overlap heavily and
    are shaped into smooth rise-sustain-fall arcs. Enters after body.
    """
    stream = np.zeros(target, dtype=np.float32)
    if not frags:
        return stream
    pool   = DiversePool(frags, rng)
    requested_lay = max(1, int(density * halo_amount * 2.5))
    # Do not create multiple phase-correlated copies of an identical source
    # fragment. Halo amount still changes per-layer gain and mode emphasis.
    n_lay  = min(requested_lay, len(frags))
    last   = -1
    truncated = False
    for _ in range(n_lay):
        if pool.step >= len(pool) * 4:
            break
        (frag, score, _), idx = pool.pick(exclude=last)
        mono = to_mono(frag).astype(np.float32)
        fl   = len(mono)
        vol  = (0.55 + rng.rand()*0.25) * (0.5 + 0.5*halo_amount)
        max_s = max(1, int(target*0.70) - fl)
        min_s = int(target * 0.05)
        cursor = rng.randint(min_s, max(min_s+1, max_s))
        arc_e  = _arc(fl)
        mono  *= arc_e * vol
        end    = min(target, cursor + fl)
        if cursor + fl > target:
            truncated = True
        _trace_place(cursor, end - cursor, vol, sr)
        stream[cursor:end] += mono[:end-cursor]
        last = idx
    if truncated:
        _release_tail(stream, sr)
    return stream


def build_residue(frags, target, sr, density, rng):
    """
    Noise/breath seep. Low amplitude, irregular scatter throughout.
    Texture layer, not a voice — deliberately quiet.
    """
    stream = np.zeros(target, dtype=np.float32)
    if not frags:
        return stream
    pool     = DiversePool(frags, rng)
    n_events = max(1, int(density * target/sr * 2.5))
    last     = -1
    for _ in range(n_events):
        if pool.step >= len(pool) * 5:
            break
        (frag, score, _), idx = pool.pick(exclude=last)
        fl     = len(to_mono(frag))
        cursor = rng.randint(0, max(1, target - fl))
        vol    = 0.25 + rng.rand() * 0.20
        _place(stream, frag, cursor, vol=vol, xfade=0)
        last = idx
    return stream


def build_shimmer(frags, target, sr, density, rng):
    """
    Rapid upper-register flicker. Short fragments, tiny gaps,
    creates an upper counterline above the body.
    """
    stream = np.zeros(target, dtype=np.float32)
    if not frags:
        return stream
    pool     = DiversePool(frags, rng)
    n_events = max(2, int(density * target/sr * 4.0))
    cursor   = 0
    last     = -1
    truncated = False
    for _ in range(n_events):
        if cursor >= target or pool.step >= len(pool) * 6:
            break
        (frag, score, _), idx = pool.pick(exclude=last)
        fl  = len(to_mono(frag))
        vol = 0.45 + rng.rand() * 0.25
        gap = int(rng.randint(0, max(1, int(0.04*sr))))
        cursor = max(0, min(max(0, target - fl), cursor + gap))
        if cursor + fl > target:
            truncated = True
        _place(stream, frag, cursor, vol=vol)
        cursor += max(int(fl*0.60), int(0.02*sr))
        last = idx
    if truncated:
        _release_tail(stream, sr)
    return stream


ROLE_ENGINES = {
    "support": build_support,
    "body":    build_body,
    "accent":  build_accent,
    "halo":    build_halo,
    "residue": build_residue,
    "shimmer": build_shimmer,
}


# ===========================================================================
# H. Compositional Mode Staging
# ===========================================================================

def apply_mode(streams, mode, target, sr, rng, accent_prom, halo_amt):
    """
    Apply mode-specific formal logic to voice streams.
    Modes are compositional laws, not volume presets.
    """
    out = {r: s.copy() for r, s in streams.items()}

    if mode == "reveal":
        # Each role emerges from silence at a different time.
        # The listener hears one voice at a time revealing itself.
        offsets = {"support": 0.00, "body": 0.05, "halo": 0.10,
                   "shimmer": 0.25, "accent": 0.20, "residue": 0.30}
        for r, s in out.items():
            if s.max() == 0:
                continue
            off_n   = int(offsets.get(r, 0.0) * target)
            env     = np.zeros(target, dtype=np.float32)
            rise_n  = max(1, target - off_n)
            env[off_n:] = np.linspace(0.0, 1.0, rise_n,
                                       dtype=np.float32) ** 1.5
            out[r] = s * env
            _trace_stage(r, off_n / float(sr), 1.0, "emergence-ramp")
        out["accent"]  *= (0.40 + 0.30 * accent_prom)
        out["residue"] *= 0.35
        _trace_stage("accent",  0.0, 0.40 + 0.30 * accent_prom, "gain")
        _trace_stage("residue", 0.0, 0.35, "gain")

    elif mode == "counterpoint":
        # Staggered independent entries per role.
        # Each role has a distinct entry point so they are never all
        # simultaneous — independence is built into the architecture.
        offsets = {"support": 0.00, "body": 0.08, "halo": 0.20,
                   "shimmer": 0.15, "accent": 0.05, "residue": 0.35}
        for r, s in out.items():
            if s.max() == 0:
                continue
            off_n = int(offsets.get(r, 0.0) * target)
            _trace_stage(r, off_n / float(sr), 1.0, "entry-shift")
            if off_n > 0:
                rolled = np.zeros_like(s)
                rolled[off_n:] = s[:target - off_n]
                _release_tail(rolled, sr)
                out[r] = rolled
        out["accent"] *= (0.65 + 0.35 * accent_prom)
        out["halo"]   *= (0.55 + 0.45 * halo_amt)
        _trace_stage("accent", 0.0, 0.65 + 0.35 * accent_prom, "gain")
        _trace_stage("halo",   0.0, 0.55 + 0.45 * halo_amt,    "gain")

    elif mode == "canon":
        # True canonic delay chain:
        #   support (dux) -> body (comes 1) -> halo (comes 2) -> shimmer (comes 3)
        # Accent and residue are free voices.
        bd = int(target * 0.12)
        delays = {"support": 0, "body": bd, "halo": bd*2,
                  "shimmer": bd*3, "accent": int(bd*0.5),
                  "residue": int(bd*1.5)}
        for r, s in out.items():
            if s.max() == 0:
                continue
            d = delays.get(r, 0)
            _trace_stage(r, d / float(sr),
                         max(0.50, 1.0 - d / target * 0.6) if d > 0 else 1.0,
                         "canonic-delay")
            if d > 0:
                shifted      = np.zeros_like(s)
                shifted[d:]  = s[:target - d]
                _release_tail(shifted, sr)
                out[r]       = shifted
                # Later entries slightly softer
                decay        = max(0.50, 1.0 - d/target * 0.6)
                out[r]      *= decay

    elif mode == "pedalhalo":
        # Pedal and halo are foregrounded; body recedes; accent very sparse.
        out["support"] *= 1.35
        out["halo"]    *= (1.0 + halo_amt * 0.7)
        out["body"]    *= 0.55
        out["accent"]  *= (0.20 + 0.20 * accent_prom)
        out["residue"] *= 0.25
        out["shimmer"] *= 0.40
        for r, g in (("support", 1.35), ("halo", 1.0 + halo_amt * 0.7),
                     ("body", 0.55), ("accent", 0.20 + 0.20 * accent_prom),
                     ("residue", 0.25), ("shimmer", 0.40)):
            _trace_stage(r, 0.0, g, "foreground-gain")

    elif mode == "fracturedchoir":
        # All voices at high density, each independently amplitude-modulated.
        # Creates dense overlapping texture with no single foregrounded voice.
        out["accent"] *= (0.80 + 0.20 * accent_prom)
        out["halo"]   *= (0.60 + 0.40 * halo_amt)
        for r in out:
            if out[r].max() == 0:
                continue
            rate  = 0.3 + rng.rand() * 1.2
            ph    = rng.rand() * 2 * math.pi
            t_mod = np.linspace(0, rate*2*math.pi, target, dtype=np.float32)
            out[r] *= (0.80 + 0.20 * np.sin(t_mod + ph)).astype(np.float32)
            # 0.80 + 0.20*sin has mean 0.80; the rate is not a gain.
            _trace_stage(r, 0.0, 0.80, "independent-AM", rate)

    return out


# ===========================================================================
# I. Stereo Rendering
# ===========================================================================

def pan_stereo(mono, pan):
    a = pan * (math.pi / 2.0)
    s = np.zeros((len(mono), 2), dtype=np.float32)
    s[:, 0] = mono * math.cos(a)
    s[:, 1] = mono * math.sin(a)
    return s


def ms_width(stereo, width):
    if abs(width - 1.0) < 0.01:
        return stereo
    mid  = 0.5 * (stereo[:,0] + stereo[:,1])
    side = 0.5 * (stereo[:,0] - stereo[:,1]) * width
    out  = np.zeros_like(stereo)
    out[:,0] = mid + side
    out[:,1] = mid - side
    return out


def render(voice_streams, target, dry_audio, dry_wet, width, sr):
    mix = np.zeros((target, 2), dtype=np.float32)
    for role in ROLE_NAMES:
        s = voice_streams.get(role)
        if s is None or len(s) == 0:
            continue
        fl   = min(len(s), target)
        mono = np.zeros(target, dtype=np.float32)
        mono[:fl] = s[:fl] * ROLE_VOL.get(role, 0.6)
        mix += pan_stereo(mono, ROLE_PAN.get(role, 0.5))

    if dry_wet < 1.0 and dry_audio is not None:
        ds = np.zeros((target, 2), dtype=np.float32)
        dn = min(len(dry_audio), target)
        if dry_audio.ndim == 1:
            ds[:dn,0] = dry_audio[:dn]; ds[:dn,1] = dry_audio[:dn]
        else:
            ch = min(dry_audio.shape[1], 2)
            ds[:dn,:ch] = dry_audio[:dn,:ch]
        mix = (1.0 - dry_wet)*ds + dry_wet*mix

    mix = ms_width(mix, width)
    pk  = float(np.max(np.abs(mix)))
    if pk > 0.92:
        mix *= 0.92 / pk
    elif 1e-9 < pk < 0.05:
        mix *= 0.5 / pk
    return mix.astype(np.float32)


# ===========================================================================
# J. Metrics + Reporting
# ===========================================================================

def compute_novelty(output, dry, sr):
    """RMS(output - dry) / RMS(dry) — real signal distance from source."""
    target = len(output)
    ds     = np.zeros((target, 2), dtype=np.float32)
    if dry is not None:
        dn = min(len(dry), target)
        if dry.ndim == 1:
            ds[:dn,0] = dry[:dn]; ds[:dn,1] = dry[:dn]
        else:
            ch = min(dry.shape[1], 2)
            ds[:dn,:ch] = dry[:dn,:ch]
    diff = output.astype(np.float64) - ds.astype(np.float64)
    return float(np.clip(
        np.sqrt(np.mean(diff**2)) / (np.sqrt(np.mean(ds.astype(np.float64)**2)) + 1e-9),
        0.0, 2.0))


def compute_poly_density(streams, target):
    """Fraction of frames where >= 2 voices are simultaneously active."""
    cnt = np.zeros(target, dtype=np.int32)
    for s in streams.values():
        if s is None or len(s) == 0:
            continue
        fl = min(len(s), target)
        cnt[:fl] += (np.abs(s[:fl]) > 1e-6).astype(np.int32)
    return float((cnt >= 2).mean())


def compute_independence(streams, target, sr):
    """Mean (1 - |correlation|) across all voice pairs."""
    present = {r: s for r,s in streams.items()
               if s is not None and len(s)>0 and s.max()>1e-9}
    if len(present) < 2:
        return 1.0
    n    = min(min(len(s) for s in present.values()), target)
    mats = [s[:n]-s[:n].mean() for s in present.values()]
    keys = list(present.keys())
    tot  = 0.0; pairs = 0
    for i in range(len(keys)):
        for j in range(i+1, len(keys)):
            a,b = mats[i], mats[j]
            na  = np.linalg.norm(a)+1e-12
            nb  = np.linalg.norm(b)+1e-12
            tot += 1.0 - abs(float(np.dot(a,b)/(na*nb)))
            pairs += 1
    return float(tot/pairs) if pairs>0 else 1.0


def role_stats(streams, frags_map, target, sr):
    stats = {}
    for r in ROLE_NAMES:
        s     = streams.get(r, np.zeros(1))
        frags = frags_map.get(r, [])
        act_s = float((np.abs(s)>1e-6).sum()/sr)
        n_f   = len(frags)
        afd   = float(np.mean([len(f[0])/sr for f in frags])) if frags else 0.0
        rms_v = float(np.sqrt(np.mean(s.astype(np.float64)**2)))
        act_r = float(np.clip(act_s/(target/sr+1e-9), 0.0, 1.0))
        stats[r] = {
            "duration":     round(act_s, 3),
            "fragments":    n_f,
            "avg_frag_dur": round(afd,   3),
            "rms":          round(rms_v, 5),
            "activity":     round(act_r, 4),
        }
    return stats


def write_json(path, n_comp, n_eff, decomp_err, roles, rstats,
               output, dry, streams, target, sr, mode, warns,
               short_source_rescue=False, effective_minfrag=None):
    novelty   = compute_novelty(output, dry, sr)
    poly_dens = compute_poly_density(streams, target)
    v_indep   = compute_independence(streams, target, sr)
    peak      = float(np.max(np.abs(output)))
    rms_o     = float(np.sqrt(np.mean(output.astype(np.float64)**2)))
    spread    = float(np.mean(np.abs(output[:,0] - output[:,1])))
    present   = [r for r in ROLE_NAMES if rstats[r]["fragments"] > 0]

    rep = {
        "n_components":        n_comp,
        "effective_components": n_eff,
        "decomp_error":        round(decomp_err, 6),
        "mode":                mode,
        "output_rms":          round(rms_o,    5),
        "output_peak":         round(peak,     5),
        "novelty_ratio":       round(novelty,  4),
        "overlap_density":     round(poly_dens,4),
        "stereo_spread":       round(spread,   5),
        "voice_independence":  round(v_indep,  4),
        "roles_present":       ", ".join(present),
        "n_roles_present":     len(present),
        "short_source_rescue": int(bool(short_source_rescue)),
        "effective_minfrag":   round(float(effective_minfrag), 4)
                               if effective_minfrag is not None else None,
    }
    if warns:
        rep["warning"] = "; ".join(warns)
    for r, st in rstats.items():
        for k, v in st.items():
            rep["{}_{}".format(r, k)] = v
    rep["role_assignment"] = {str(k): r for k,r in enumerate(roles)}

    with open(path, "w") as f:
        json.dump(rep, f, indent=2)
    print("    JSON: {}".format(path))


def write_csv(path, descs, roles):
    fields = ["component","role","centroid","bandwidth","flatness",
              "lo_e","mid_e","hi_e","up_e","sparsity","onset_aff",
              "sustain","mod_rate","recurrence","roughness","energy"]
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for k,(d,r) in enumerate(zip(descs, roles)):
            row = {"component":k, "role":r}
            row.update({kk: round(float(v),5) for kk,v in d.items()})
            w.writerow(row)
    print("    CSV:  {}".format(path))



# ===========================================================================
# Pipeline
# ===========================================================================

def run_pipeline(args):
    np.random.seed(args.seed)
    rng   = np.random.RandomState(args.seed)
    warns = []

    print("  [Py 1/9] Loading audio...")
    audio, sr, n_ch = load_audio(args.input)
    n_samp = len(audio)
    orig_dur = n_samp / sr
    target_dur = orig_dur * max(0.5, min(4.0, args.expand))
    target = int(round(target_dur * sr))
    audio_norm, _ = safe_normalize(audio, headroom=0.92)
    mono = to_mono(audio_norm)
    print("    Original: {:.3f}s  Target: {:.3f}s".format(orig_dur, target_dur))

    print("  [Py 2/9] STFT analysis...")
    mag, phase, freqs = compute_stft(mono, sr, args.fft, args.hop)
    print("    Shape: {}  Freq bins: {}".format(mag.shape, len(freqs)))
    if args.analysis == "hpss":
        mag_a = hpss_weight(mag)
    elif args.analysis == "transient":
        mag_a = transient_weight(mag)
    else:
        mag_a = mag.copy()

    n_comp = max(3, min(24, args.components))
    print("  [Py 3/9] NMF ({} components)...".format(n_comp))
    W, H, decomp_err = nmf_decompose(mag_a, n_comp, seed=args.seed)
    n_eff = effective_rank(H)
    print("    Effective rank: {}".format(n_eff))
    if decomp_err > 0.75:
        warns.append("High NMF error ({:.3f})".format(decomp_err))
        args.density = min(args.density, 0.45)

    print("  [Py 4/9] Computing descriptors...")
    descs = compute_descriptors(W, H, freqs, sr, args.hop)

    print("  [Py 5/9] Role inference...")
    roles = infer_roles(descs, sr)

    print("  [Py 6/9] Harvesting fragments...")
    T   = mag.shape[1]
    dom = role_dominance(H, roles, T)
    frags_map = {}
    role_thresholds = {}
    for role in ROLE_NAMES:
        d_arr = dom[role]
        if d_arr.max() < 0.04:
            frags_map[role] = []
            role_thresholds[role] = None
            print("    {:10s}: absent (max_dom={:.3f})".format(role, d_arr.max()))
            continue
        active_v  = d_arr[d_arr > 0.02]
        threshold = float(np.percentile(active_v, 35)) if len(active_v)>0 else 0.10
        threshold = max(0.08, threshold)
        role_thresholds[role] = threshold
        intervals = dom_to_intervals(d_arr, args.hop, sr, threshold, args.minfrag)
        frags     = harvest_fragments(audio_norm, sr, args.hop,
                                       d_arr, intervals, args.minfrag)
        frags_map[role] = frags
        total_dur = sum(len(f[0])/sr for f in frags)
        print("    {:10s}: {:3d} intervals -> {:3d} frags ({:.2f}s)".format(
              role, len(intervals), len(frags), total_dur))
        if len(intervals) > 0 and len(frags) == 0:
            warns.append("Role '{}' intervals found but no usable fragments".format(role))

    # Short/fragmented-source rescue. With a fixed 150 ms minimum it is
    # possible for NMF + role inference to work perfectly yet every dominance
    # run be shorter than minfrag, leaving all six voices silent. Only when the
    # NORMAL harvesting pass produced no material at all do we relax the
    # dominance threshold and minimum fragment duration. This preserves the
    # established sound sample-for-sample whenever ordinary harvesting works.
    short_source_rescue = not any(frags_map.get(r) for r in ROLE_NAMES)
    effective_minfrag = args.minfrag
    if short_source_rescue:
        effective_minfrag = min(args.minfrag,
                                max(0.030, min(0.080, orig_dur * 0.20)))
        rescued = 0
        print("    No standard fragments; adaptive rescue minfrag={:.3f}s".format(
              effective_minfrag))
        for role in ROLE_NAMES:
            d_arr = dom[role]
            threshold = role_thresholds.get(role)
            if threshold is None or d_arr.max() < 0.04:
                continue
            relaxed_threshold = max(0.04, threshold * 0.50)
            intervals = dom_to_intervals(
                d_arr, args.hop, sr, relaxed_threshold, effective_minfrag,
                merge_gap=max(0.04, effective_minfrag))
            frags = harvest_fragments(audio_norm, sr, args.hop, d_arr,
                                      intervals, effective_minfrag)
            if frags:
                frags_map[role] = frags
                rescued += len(frags)
                total_dur = sum(len(f[0])/sr for f in frags)
                print("    {:10s}: RESCUE {:3d} frags ({:.2f}s, thr={:.3f})".format(
                      role, len(frags), total_dur, relaxed_threshold))
        if rescued == 0:
            warns.append("No usable role fragments even after adaptive short-source rescue")
        else:
            print("    Adaptive short-source rescue active: {} fragments, minfrag={:.0f} ms".format(
                  rescued, effective_minfrag * 1000.0))

    _TRACE["sr"] = sr
    for role in ROLE_NAMES:
        _trace_harvest(role, frags_map.get(role, []), sr)

    print("  [Py 7/9] Building voice streams...")
    streams = {}
    for role in ROLE_NAMES:
        frags = frags_map.get(role, [])
        if not frags:
            streams[role] = np.zeros(target, dtype=np.float32)
            print("    {:10s}: silent".format(role))
            continue
        eng = ROLE_ENGINES[role]
        _trace_role(role)
        if role == "accent":
            s = eng(frags, target, sr, args.density, args.accent, rng)
        elif role == "halo":
            s = eng(frags, target, sr, args.density, args.halo, rng)
        else:
            s = eng(frags, target, sr, args.density, rng)
        streams[role] = s
        rms_v = float(np.sqrt(np.mean(s.astype(np.float64)**2)))
        print("    {:10s}: rms={:.4f}".format(role, rms_v))

    print("  [Py 8/9] Mode staging: {}...".format(args.mode))
    streams = apply_mode(streams, args.mode, target, sr, rng,
                          args.accent, args.halo)

    print("  [Py 9/9] Rendering + reporting...")
    output = render(streams, target, audio_norm, args.drywet, args.width, sr)
    save_audio(args.output, output, sr)

    rstats = role_stats(streams, frags_map, target, sr)
    write_json(args.report, n_comp, n_eff, decomp_err, roles, rstats,
               output, audio_norm, streams, target, sr, args.mode, warns,
               short_source_rescue=short_source_rescue,
               effective_minfrag=effective_minfrag)
    if args.trace:
        write_trace(args.trace, sr, orig_dur, target / float(sr), args.mode)
    if args.csv:
        write_csv(args.csv, descs, roles)

    # Summary
    novelty   = compute_novelty(output, audio_norm, sr)
    poly_dens = compute_poly_density(streams, target)
    v_indep   = compute_independence(streams, target, sr)
    n_pres    = sum(1 for r in ROLE_NAMES if frags_map.get(r))
    print()
    print("  == Internal Polyphony v2 Summary ==")
    print("  Mode:            {}".format(args.mode))
    print("  Components:      {}  (eff rank: {})".format(n_comp, n_eff))
    print("  Decomp RMSE:     {:.5f}".format(decomp_err))
    print("  Roles present:   {}/6".format(n_pres))
    print("  Poly density:    {:.3f}  (frac >= 2 voices)".format(poly_dens))
    print("  Voice indep:     {:.3f}  (1=fully indep)".format(v_indep))
    print("  Novelty:         {:.3f}  (dist from dry)".format(novelty))
    rms_out = float(np.sqrt(np.mean(output.astype(np.float64)**2)))
    pk_out  = float(np.max(np.abs(output)))
    print("  Output:          rms={:.4f}  peak={:.4f}".format(rms_out, pk_out))
    print()
    print("  {:<12} {:>5} {:>7} {:>8} {:>5} {:>8}".format(
          "Role","Frags","Dur(s)","AvgF(s)","Act","RMS"))
    print("  " + "-"*50)
    for r in ROLE_NAMES:
        st     = rstats[r]
        absent = "  [absent]" if not frags_map.get(r) else ""
        print("  {:<12} {:5d} {:7.2f} {:8.3f} {:5.2f} {:8.5f}{}".format(
              r, st["fragments"], st["duration"],
              st["avg_frag_dur"], st["activity"], st["rms"], absent))
    if warns:
        print()
        for w in warns:
            print("  WARNING: {}".format(w))
    print()
    print("OK: {}".format(args.output))


# ===========================================================================
# CLI
# ===========================================================================

def check_deps():
    missing = []
    for pkg in ["numpy", "scipy", "soundfile"]:
        try:
            m = __import__(pkg)
            print("    {} {} OK".format(pkg, getattr(m,"__version__","?")))
        except ImportError:
            missing.append(pkg)
    if missing:
        print("ERROR: missing: {}".format(", ".join(missing)), file=sys.stderr)
        print("  pip install {}".format(" ".join(missing)), file=sys.stderr)
        sys.exit(1)


def parse_args():
    p = argparse.ArgumentParser(description="Internal Polyphony v2")
    p.add_argument("--input",      required=True)
    p.add_argument("--output",     required=True)
    p.add_argument("--report",     required=True)
    p.add_argument("--csv",        default="")
    p.add_argument("--trace",      default="",
                   help="tab-separated process trace for the Praat figure")
    p.add_argument("--components", type=int,   default=10)
    p.add_argument("--fft",        type=int,   default=2048)
    p.add_argument("--hop",        type=int,   default=512)
    p.add_argument("--analysis",   default="full",
                   choices=["full","hpss","transient"])
    p.add_argument("--mode",       default="counterpoint",
                   choices=["reveal","counterpoint","canon",
                            "pedalhalo","fracturedchoir"])
    p.add_argument("--density",    type=float, default=0.65)
    p.add_argument("--minfrag",    type=float, default=0.15)
    # Legacy CLI compatibility. v2 voice engines have role-specific overlap
    # laws, so a single global max-overlap value is intentionally not applied.
    p.add_argument("--maxoverlap", type=float, default=0.75,
                   help=argparse.SUPPRESS)
    p.add_argument("--expand",     type=float, default=1.0)
    p.add_argument("--drywet",     type=float, default=0.85)
    p.add_argument("--accent",     type=float, default=0.7)
    p.add_argument("--halo",       type=float, default=0.6)
    p.add_argument("--width",      type=float, default=1.2)
    p.add_argument("--seed",       type=int,   default=42)
    return p.parse_args()


def main():
    print("=" * 56)
    print("  Internal Polyphony v2")
    print("  Hidden voice discovery and polyphonic staging")
    print("=" * 56)
    print()
    check_deps()
    print()
    _trace_reset()
    args = parse_args()
    if not os.path.isfile(args.input):
        print("ERROR: input not found: {}".format(args.input), file=sys.stderr)
        sys.exit(1)
    out_dir = os.path.dirname(args.output)
    if out_dir and not os.path.isdir(out_dir):
        os.makedirs(out_dir, exist_ok=True)
    run_pipeline(args)


if __name__ == "__main__":
    main()