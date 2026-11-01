#!/usr/bin/env python3
# ============================================================
# Praat AudioTools - praat_spectral_gen.py
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.5.1 (2026)
# License: MIT License
#
# Description:
#   Spectral noise shaping generator (random-phase spectral
#   resynthesis). Analyses a corpus of audio files, learns a bank of
#   level-independent spectral shapes IN THEIR ORIGINAL ORDER, plus
#   their temporal envelopes, then generates new audio by giving
#   white-noise phases the learned magnitudes and overlap-adding.
#
#   Generation modes (how the learned bank becomes musical time):
#     1 random     - v1.4 behaviour: random blend of two frames per hop
#                    (+ optional spectral inertia via --continuity)
#     2 walk       - Markov-style spectral walk: a first-order stochastic
#                    walk over the corpus's observed frame-to-frame
#                    transitions plus similarity jumps (no full
#                    transition matrix is estimated)
#     3 replay     - morphological replay: ordered traversal of a source
#                    file, time-stretched, rebuilt from noise
#     4 migration  - path through the bank ordered by centroid or
#                    flatness (rising / falling / arch / valley)
#     5 counterpoint - independent L/R walks with adjustable coupling
#
#   v1.5.1 fixes: replay walks each file's full timeline (silences keep
#     their length and place; stride/padding-correct speed; single-frame
#     files no longer crash); max_profiles is a hard cap (per-file budgets,
#     explicit error when files > cap); counterpoint measured per channel
#     + L/R centroid correlation; *_valid flags in the summary CSV;
#     --log_file for shell-free invocation.
#
#   v1.5.0 changes (see Praat script header for the full changelog):
#     - QC spectrum measured with the SAME window/FFT pipeline as the
#       corpus analysis (fixes the chunk-size bias of the 1.4 metric)
#     - new "temporal structure" metric (frame-to-frame spectral
#       continuity, corpus vs output) + intended-vs-realised
#       centroid trajectory export
#     - files streamed one at a time; profile bank capped by
#       --max_profiles with order-preserving per-file decimation
#     - multichannel sources: per-channel magnitudes power-averaged
#       (no channel discarded, no phase cancellation)
#     - --weighting equal|duration (equal = each file counts once)
#     - --done_file written only after every stage succeeded
#
# Dependencies:
#   pip install numpy scipy soundfile
# ============================================================

import argparse
import math
import os
import sys
import time
import traceback

import numpy as np
import soundfile as sf
try:
    from scipy.signal import resample_poly
    HAS_SCIPY = True
except ImportError:
    HAS_SCIPY = False


VERSION = "1.5.1"
MODES = ("random", "walk", "replay", "migration", "counterpoint")
ENV_LEN = 200
N_BANDS = 32          # log-spaced bands for similarity / continuity


def validated_chunk_size(chunk_size, hop_length):
    if hop_length < 1:
        raise ValueError("hop_length must be at least 1")
    if chunk_size < 1:
        raise ValueError("chunk_size must be positive")
    if chunk_size < 2 * hop_length:
        raise ValueError(
            f"chunk_size ({chunk_size}) must be at least 2 x hop_length "
            f"({2 * hop_length}); otherwise the overlap-add has gaps.")
    if chunk_size & (chunk_size - 1) != 0:
        next_pow2 = 1 << (chunk_size - 1).bit_length()
        raise ValueError(
            f"chunk_size ({chunk_size}) must be a power of 2. "
            f"Nearest valid value: {next_pow2}.")
    return chunk_size


# =============================================================================
#  STAGE 1 - SCAN CORPUS (no audio held in memory)
# =============================================================================

def scan_corpus(folder, sr, min_dur, stats):
    print("[1/5] Scanning corpus...", flush=True)
    paths = []
    for root, _, files in os.walk(folder):
        for f in files:
            if f.lower().endswith((".wav", ".aif", ".aiff", ".flac")):
                paths.append(os.path.join(root, f))
    paths.sort()
    stats["files_found"] = len(paths)

    entries, skipped = [], []
    for p in paths:
        try:
            info = sf.info(p)
            dur = info.frames / float(info.samplerate)
            if dur < min_dur:
                skipped.append((os.path.basename(p), "too short"))
                continue
            entries.append({"path": p, "sr": info.samplerate,
                            "channels": info.channels,
                            "n_out": int(round(info.frames * sr / float(info.samplerate)))})
        except Exception as exc:
            skipped.append((os.path.basename(p), str(exc)))
    stats["skipped_details"] = skipped
    print(f"  Usable: {len(entries)}  Skipped: {len(skipped)}", flush=True)
    return entries, skipped


def load_file(entry, sr):
    """Load one file as (n, ch) float32 at sr, peak-normalised to 0.95."""
    from math import gcd
    audio, file_sr = sf.read(entry["path"], always_2d=True, dtype="float32")
    if file_sr != sr:
        if HAS_SCIPY:
            g = gcd(int(sr), int(file_sr))
            audio = resample_poly(audio, int(sr) // g, int(file_sr) // g, axis=0)
        else:
            new_len = max(1, int(round(audio.shape[0] * sr / file_sr)))
            idx = np.linspace(0, audio.shape[0] - 1, new_len)
            audio = np.stack([np.interp(idx, np.arange(audio.shape[0]), audio[:, c])
                              for c in range(audio.shape[1])], axis=1)
    audio = np.asarray(audio, dtype=np.float32)
    peak = float(np.max(np.abs(audio))) if audio.size else 0.0
    if peak > 1e-6:
        audio = audio / peak * 0.95
    return audio


def _n_frames(n, chunk, hop):
    return 1 if n <= chunk else int(math.ceil((n - chunk) / float(hop))) + 1


def _band_matrix(freq, sr, n_bands=N_BANDS, fmin=50.0):
    """Rectangular log-band pooling matrix (n_bands, n_freq)."""
    fmax = min(20000.0, sr / 2.0)
    edges = np.geomspace(fmin, fmax, n_bands + 1)
    m = np.zeros((n_bands, len(freq)), dtype=np.float32)
    for b in range(n_bands):
        sel = (freq >= edges[b]) & (freq < edges[b + 1])
        if not np.any(sel):
            sel = np.zeros(len(freq), bool)
            sel[int(np.argmin(np.abs(freq - math.sqrt(edges[b] * edges[b + 1]))))] = True
        m[b, sel] = 1.0 / sel.sum()
    return m


def _band_vec(mag, bm):
    """Log-band, unit-norm feature vector for similarity / continuity."""
    v = np.log1p(10.0 * (bm @ np.asarray(mag, np.float64)))
    v = v - v.mean()
    n = np.linalg.norm(v)
    return (v / n).astype(np.float32) if n > 1e-12 else v.astype(np.float32)


# =============================================================================
#  STAGE 2 - ANALYSE (ordered bank)
# =============================================================================

class Bank:
    pass


def _movement(seqs):
    """Mean squared distance of block-mean features from each sequence's mean.

    Measures slow-scale spectral movement (does the timbre go somewhere?),
    which frame-to-frame similarity cannot: with 75% window overlap adjacent
    frames are similar even when the profile is redrawn at random each hop.
    """
    d = []
    for f, blk in seqs:
        n = (len(f) // blk) * blk
        if n < 2 * blk:
            continue
        blocks = f[:n].reshape(-1, blk, f.shape[1]).mean(axis=1)
        d.extend(np.sum((blocks - blocks.mean(axis=0)) ** 2, axis=1))
    return float(np.mean(d)) if d else float("nan")


def analyse_corpus(entries, sr, n_fft, hop, chunk_size, max_profiles, stats):
    """Ordered, level-independent spectral bank + per-file metadata.

    Profiles are unit-RMS magnitude shapes on the canonical n_fft grid,
    kept in file/time order. succ[i] = index of the next kept frame of
    the same file (-1 if none), which is what the walk/replay modes use.
    max_profiles is a HARD cap: when the corpus has more frames, each file
    gets a frame budget proportional to its length (at least one frame,
    and the budgets sum to <= max_profiles) and is decimated by its own
    stride, so order survives inside every file. A corpus with more files
    than max_profiles is refused with a clear message rather than
    silently overrunning the cap.

    Every file also keeps a full TIMELINE (one slot per kept frame,
    silent frames included, with their RMS). Replay walks this timeline,
    so silences keep their length and position.
    """
    print("[2/5] Analysing corpus spectra...", flush=True)
    canonical_freq = np.fft.rfftfreq(n_fft, d=1.0 / sr)
    analysis_fft = max(int(n_fft), int(chunk_size))
    analysis_freq = np.fft.rfftfreq(analysis_fft, d=1.0 / sr)
    window = np.hanning(chunk_size).astype(np.float32)
    bm = _band_matrix(canonical_freq, sr)

    est_frames = [_n_frames(e["n_out"], chunk_size, hop) for e in entries]
    total_frames = sum(est_frames)
    n_ent = len(entries)
    if n_ent > max_profiles:
        raise ValueError(
            f"The corpus has {n_ent} files but Max profiles is {max_profiles}; "
            f"every file needs at least one frame. Raise Max profiles to at "
            f"least {n_ent} (Advanced dialog) or use fewer files.")
    decimate = total_frames > max_profiles
    if decimate:
        spare = max_profiles - n_ent
        budgets = [1 + int(math.floor(spare * nf_e / float(total_frames))) for nf_e in est_frames]
    else:
        budgets = [None] * n_ent
    stats["analysis_frames_total"] = total_frames
    strides_used = []
    if decimate:
        print(f"  {total_frames} frames > cap {max_profiles}: per-file budgets", flush=True)

    profiles, feats, p_file, p_pos, p_rms, succ = [], [], [], [], [], []
    envelopes, file_means, file_durs, file_ranges = [], [], [], []
    timelines, move_seqs = [], []
    silent, multich, used_files, total_dur = 0, 0, [], 0.0

    for e, budget in zip(entries, budgets):
        try:
            audio = load_file(e, sr)
        except Exception as exc:
            stats["skipped_details"].append((os.path.basename(e["path"]), str(exc)))
            continue
        if audio.shape[1] > 1:
            multich += 1
        n = audio.shape[0]
        nf = _n_frames(n, chunk_size, hop)
        # stride from the ACTUAL frame count, so the budget can never be exceeded
        stride = 1 if budget is None else max(1, int(math.ceil(nf / float(budget))))
        strides_used.append(stride)
        rms_all = np.zeros(nf, np.float64)
        frame_mags = {}
        for i in range(nf):
            fr = audio[i * hop:i * hop + chunk_size, :]
            if fr.shape[0] < chunk_size:
                fr = np.pad(fr, ((0, chunk_size - fr.shape[0]), (0, 0)))
            rms_all[i] = math.sqrt(float(np.mean(fr.astype(np.float64) ** 2)))
            if i % stride:
                continue
            # power-average channel magnitudes: no channel lost, no cancellation
            spec = np.abs(np.fft.rfft(fr * window[:, None], n=analysis_fft, axis=0))
            mag_hi = np.sqrt(np.mean(spec.astype(np.float64) ** 2, axis=1))
            frame_mags[i] = (mag_hi if analysis_fft == n_fft
                             else np.interp(canonical_freq, analysis_freq, mag_hi))

        fidx = len(used_files)
        used_files.append(os.path.basename(e["path"]))
        dur = n / float(sr)
        total_dur += dur
        file_durs.append(dur)
        envelopes.append(rms_all.astype(np.float32))
        floor = max(1e-8, float(rms_all.max()) * 1e-3)   # -60 dB re file peak RMS
        start_idx = len(profiles)
        prev_kept = -1
        fsum, fcount = None, 0
        peak_rms = max(float(rms_all.max()), 1e-12)
        slot_prof, slot_rms = [], []
        for i in sorted(frame_mags):
            mag = frame_mags[i]
            mr = math.sqrt(float(np.mean(mag ** 2)))
            slot_rms.append(rms_all[i] / peak_rms)
            if rms_all[i] <= floor or mr <= 1e-12:
                silent += 1
                slot_prof.append(-1)
                if prev_kept >= 0:
                    succ[prev_kept] = -1      # silence breaks the chain
                prev_kept = -1
                continue
            slot_prof.append(len(profiles))
            shape = (mag / mr).astype(np.float32)
            k = len(profiles)
            profiles.append(shape)
            feats.append(_band_vec(shape, bm))
            p_file.append(fidx)
            p_pos.append(i / float(max(1, nf - 1)))
            p_rms.append(rms_all[i] / max(float(rms_all.max()), 1e-12))
            succ.append(-1)
            if prev_kept >= 0:
                succ[prev_kept] = k
            prev_kept = k
            fsum = shape.astype(np.float64) if fsum is None else fsum + shape
            fcount += 1
        file_ranges.append((start_idx, len(profiles)))
        file_means.append(None if fcount == 0 else (fsum / fcount))
        # timeline: silent slots hold the nearest active spectrum (their level
        # comes from slot_rms, so they render as silence on the trajectory envelope)
        sp = np.asarray(slot_prof, np.int64)
        if fcount > 0:
            act = np.where(sp >= 0)[0]
            near = act[np.clip(np.searchsorted(act, np.arange(len(sp))), 0, len(act) - 1)]
            prev_act = act[np.clip(np.searchsorted(act, np.arange(len(sp))) - 1, 0, len(act) - 1)]
            pick = np.where(np.abs(np.arange(len(sp)) - prev_act) <= np.abs(near - np.arange(len(sp))),
                            prev_act, near)
            sp = np.where(sp >= 0, sp, sp[pick])
        timelines.append({"prof": sp, "rms": np.asarray(slot_rms, np.float32),
                          "stride": stride, "n_samples": n, "nf": nf})
        blk = max(1, int(round(0.25 * sr / float(hop * stride))))
        if len(profiles) - start_idx >= 2 * blk:
            move_seqs.append((np.asarray(feats[start_idx:len(profiles)], np.float32), blk))
        del audio, frame_mags

    if not profiles:
        raise ValueError("Corpus analysis produced no active spectral frames")

    b = Bank()
    b.profiles = np.asarray(profiles, np.float32)
    b.feats = np.asarray(feats, np.float32)
    b.file = np.asarray(p_file, np.int32)
    b.pos = np.asarray(p_pos, np.float32)
    b.rms = np.asarray(p_rms, np.float32)
    b.succ = np.asarray(succ, np.int64)
    b.file_ranges = file_ranges
    b.timelines = timelines
    b.file_durs = np.asarray(file_durs)
    b.n_files = len(used_files)
    b.canonical_freq = canonical_freq
    b.analysis_fft = analysis_fft
    b.bm = bm
    b.std = np.std(b.profiles.astype(np.float64), axis=0).astype(np.float32)
    b.mean_by_frames = np.mean(b.profiles.astype(np.float64), axis=0).astype(np.float32)
    valid = [m for m in file_means if m is not None]
    b.mean_by_file = np.mean(np.asarray(valid), axis=0).astype(np.float32)
    b.active_files = np.array([i for i, (s, t) in enumerate(file_ranges) if t > s])

    # spectral features for migration
    f = canonical_freq
    P = b.profiles.astype(np.float64)
    b.centroid = (P @ f) / np.maximum(P.sum(axis=1), 1e-12)
    pw = np.maximum(P ** 2, 1e-20)
    b.flatness = np.exp(np.mean(np.log(pw), axis=1)) / np.mean(pw, axis=1)

    # corpus continuity: mean cosine between successive kept frames
    pairs = [(i, j) for i, j in enumerate(b.succ) if j >= 0]
    b.corpus_motion = (float(np.mean([float(b.feats[i] @ b.feats[j]) for i, j in pairs]))
                       if pairs else float("nan"))
    # corpus movement: how far 0.25 s block means wander from their file's mean
    b.corpus_movement = _movement(move_seqs)

    env_sum = np.zeros(ENV_LEN)
    for env in envelopes:
        r = np.interp(np.linspace(0, 1, ENV_LEN), np.linspace(0, 1, len(env)), env)
        if r.max() > 1e-12:
            r = r / r.max()
        env_sum += r
    me = env_sum / max(1, len(envelopes))
    b.mean_envelope = (me / me.max() if me.max() > 1e-8 else me).astype(np.float32)

    stats["files_used"] = b.n_files
    stats["files_skipped"] = len(stats["skipped_details"])
    stats["multichannel_files"] = multich
    stats["corpus_duration_used_s"] = round(total_dur, 3)
    stats["profile_bank_size"] = len(b.profiles)
    stats["max_profiles"] = max_profiles
    stats["profile_stride"] = max(strides_used) if strides_used else 1
    if len(b.profiles) > max_profiles:      # cannot happen; guard the guarantee
        raise RuntimeError("profile cap violated")
    stats["silent_profiles_skipped"] = silent
    stats["analysis_fft_size"] = analysis_fft
    print(f"  Bank: {len(b.profiles)} ordered frames from {b.n_files} files "
          f"(max stride {stats['profile_stride']}, {silent} silent skipped)", flush=True)
    if multich:
        print(f"  Multichannel files: {multich} (channel magnitudes power-averaged)", flush=True)
    return b


# =============================================================================
#  STAGE 3 - BUILD A SPECTRAL PATH (one state per output frame)
# =============================================================================

class Neighbours:
    """On-demand k-nearest neighbours in log-band space (cached)."""
    def __init__(self, feats, k=8):
        self.f, self.k, self.cache = feats, k, {}

    def __call__(self, i):
        if i not in self.cache:
            sims = self.f @ self.f[i]
            sims[i] = -np.inf
            k = min(self.k, len(sims) - 1)
            if k <= 0:
                self.cache[i] = np.array([i])
            else:
                idx = np.argpartition(-sims, k - 1)[:k]
                self.cache[i] = idx[np.argsort(-sims[idx])]
        return self.cache[i]


def _pick_file(bank, weighting, rng):
    af = bank.active_files
    if weighting == "duration":
        w = bank.file_durs[af]
        return int(rng.choice(af, p=w / w.sum()))
    return int(rng.choice(af))


def _random_state(bank, weighting, rng):
    if weighting == "duration":
        return int(rng.integers(0, len(bank.profiles)))
    s, t = bank.file_ranges[_pick_file(bank, weighting, rng)]
    return int(rng.integers(s, t))


def _walk(bank, n_frames, continuity, weighting, rng, nbr):
    """First-order stochastic walk over OBSERVED transitions (Markov-style).

    No full transition-probability matrix is estimated: the learned
    transition of a state is the frame that actually followed it in the
    corpus. Returns integer state per frame.

    Each step: with probability c follow the corpus's own next frame
    (learned transition); otherwise jump to a spectrally similar frame
    near that successor (new path, statistically continuous), and with
    a small probability (1-c)^2 * 0.5 make an unrestricted jump.
    """
    c = float(np.clip(continuity, 0.0, 1.0))
    p_surprise = 0.5 * (1.0 - c) ** 2
    path = np.empty(n_frames, np.int64)
    cur = _random_state(bank, weighting, rng)
    jumps = 0
    for t in range(n_frames):
        path[t] = cur
        nxt = int(bank.succ[cur])
        u = rng.random()
        if nxt >= 0 and u < c:
            cur = nxt
            continue
        jumps += 1
        if rng.random() < p_surprise:
            cur = _random_state(bank, weighting, rng)
        else:
            base = nxt if nxt >= 0 else cur
            cur = int(rng.choice(nbr(base)))
    return path, jumps


def _replay(bank, n_frames, stretch, weighting, rng, hop, chunk, pad, n_samples):
    """Morphological replay on each file's full timeline (silences included).

    Output time is mapped to source time: an output frame centred at sample t
    reads the source at (t - t0) / stretch, where t0 is where the current
    file started in the output. That position is converted to the file's
    analysis-frame index and then to its timeline slot (slot = frame / stride),
    so the speed is exact whatever the per-file decimation, and the padding
    frames before t = 0 read the first slot instead of eating into the source.
    Returns slot profile indices (a, b), interpolation fraction, slot RMS,
    the stretch used and the number of source files visited.
    """
    f = _pick_file(bank, weighting, rng)
    tl = bank.timelines[f]
    if stretch <= 0:    # auto: fit this file (silences included) to the output
        stretch = max(1e-3, n_samples / float(max(1, tl["n_samples"])))
    a = np.empty(n_frames, np.int64)
    b = np.empty(n_frames, np.int64)
    fr = np.empty(n_frames, np.float32)
    rms = np.empty(n_frames, np.float32)
    t0 = 0.0
    files_visited = 1
    for k in range(n_frames):
        t = k * hop + chunk / 2.0 - pad            # output sample of this frame centre
        ft = (t - t0) / stretch
        while ft > tl["n_samples"]:                # file finished: continue with the next
            t0 += tl["n_samples"] * stretch
            f = _pick_file(bank, weighting, rng)
            tl = bank.timelines[f]
            files_visited += 1
            ft = (t - t0) / stretch
        pos = (ft - chunk / 2.0) / hop             # analysis frame index (fractional)
        pos = min(max(pos, 0.0), tl["nf"] - 1.0)
        ns = len(tl["prof"])
        sp = min(max(pos / tl["stride"], 0.0), ns - 1.0)
        s0 = int(math.floor(sp))
        s1 = min(s0 + 1, ns - 1)
        w = float(sp - s0) if s1 != s0 else 0.0
        a[k], b[k], fr[k] = tl["prof"][s0], tl["prof"][s1], w
        rms[k] = tl["rms"][s0] * (1.0 - w) + tl["rms"][s1] * w
    return a, b, fr, rms, stretch, files_visited


def _migration(bank, n_frames, continuity, feature, direction, rng):
    vals = bank.centroid if feature == "centroid" else np.log10(bank.flatness + 1e-12)
    order = np.argsort(vals, kind="stable")
    rank = np.empty(len(order), np.int64)
    rank[order] = np.arange(len(order))
    N = len(order)
    c = float(np.clip(continuity, 0.0, 1.0))
    half = max(1, int(round(N * (0.01 + 0.10 * (1.0 - c)))))
    t = np.linspace(0.0, 1.0, n_frames)
    q = {"rising": t, "falling": 1 - t,
         "arch": np.sin(np.pi * t), "valley": 1 - np.sin(np.pi * t)}[direction]
    path = np.empty(n_frames, np.int64)
    cur = -1
    for k in range(n_frames):
        target = int(round(q[k] * (N - 1)))
        lo, hi = max(0, target - half), min(N - 1, target + half)
        nxt = int(bank.succ[cur]) if cur >= 0 else -1
        if nxt >= 0 and lo <= rank[nxt] <= hi and rng.random() < c:
            cur = nxt
        else:
            cur = int(order[int(rng.integers(lo, hi + 1))])
        path[k] = cur
    return path, q


# =============================================================================
#  STAGE 4 - SYNTHESIS
# =============================================================================

def _smooth_curve(x, n):
    if n <= 1 or len(x) <= 2:
        return x
    left, right = n // 2, n - 1 - n // 2
    p = np.pad(x.astype(np.float64), (left, right), mode="edge")
    cs = np.concatenate(([0.0], np.cumsum(p)))
    return ((cs[n:] - cs[:-n]) / n).astype(np.float32)


def generate(bank, cfg, stats):
    sr, hop, chunk = cfg.sr, cfg.hop_length, cfg.chunk_size
    mode, v, c = cfg.mode, cfg.variation, cfg.continuity
    print(f"[3/5] Generating ({mode})...", flush=True)

    base_seed = None if cfg.seed is None else int(cfg.seed)
    rng_profile = np.random.default_rng(base_seed)
    rng_l = np.random.default_rng(None if base_seed is None else base_seed + 1009)
    rng_r = np.random.default_rng(None if base_seed is None else base_seed + 2017)
    rng_path_r = np.random.default_rng(None if base_seed is None else base_seed + 3011)

    n_samples = max(1, int(round(cfg.duration * sr)))
    window = np.hanning(chunk).astype(np.float64)
    synth_freq = np.fft.rfftfreq(chunk, d=1.0 / sr)
    pad = chunk
    total = n_samples + 2 * pad
    n_frames = max(1, (total - chunk) // hop + 1)
    noise_l = rng_l.standard_normal(total + chunk).astype(np.float32)
    noise_r = rng_r.standard_normal(total + chunk).astype(np.float32)

    mean_p = bank.mean_by_file if cfg.weighting == "equal" else bank.mean_by_frames
    nbr = Neighbours(bank.feats)
    P = bank.profiles

    # ---- spectral trajectory: profile per frame per channel ----
    traj_l, traj_r = None, None   # functions k -> profile
    frame_rms = np.ones(n_frames, np.float32)
    intended_centroid = np.zeros(n_frames)
    info = {}

    if mode == "random":
        prev = None
        profs = np.empty((n_frames, P.shape[1]), np.float32)
        for k in range(n_frames):
            if v <= 0.0:
                p = mean_p
            else:
                i1 = int(rng_profile.integers(0, len(P))) if cfg.weighting == "duration" \
                    else _random_state(bank, "equal", rng_profile)
                cand = P[i1]
                if len(P) > 1:
                    i2 = int(rng_profile.integers(0, len(P))) if cfg.weighting == "duration" \
                        else _random_state(bank, "equal", rng_profile)
                    bl = float(rng_profile.uniform(0.0, 1.0))
                    cand = cand * (1.0 - bl) + P[i2] * bl
                p = mean_p * (1.0 - v) + cand * v
                jit = bank.std * rng_profile.normal(size=len(mean_p)).astype(np.float32) * v * 0.30
                p = np.maximum(0.0, p + jit)
            if prev is not None and c > 0:          # spectral inertia
                p = c * prev + (1.0 - c) * p
            profs[k] = p
            prev = p
        traj_l = traj_r = (lambda k: profs[k])
        info["jumps"] = "n/a"
    elif mode in ("walk", "counterpoint", "migration"):
        if mode == "migration":
            path, q = _migration(bank, n_frames, c, cfg.migration_feature,
                                 cfg.migration_direction, rng_profile)
            info["jumps"] = "n/a"
        else:
            path, jumps = _walk(bank, n_frames, c, cfg.weighting, rng_profile, nbr)
            info["jumps"] = jumps
        pl = mean_p[None, :] * (1 - v) + P[path] * v
        frame_rms = bank.rms[path].copy()
        if mode == "counterpoint":
            path_r, jr = _walk(bank, n_frames, c, cfg.weighting, rng_path_r, nbr)
            k_ = float(np.clip(cfg.coupling, 0.0, 1.0))
            pr_raw = P[path_r] * (1 - k_) + P[path] * k_
            pr = mean_p[None, :] * (1 - v) + pr_raw * v
            frame_rms = 0.5 * (bank.rms[path] + (1 - k_) * bank.rms[path_r] + k_ * bank.rms[path])
            info["jumps"] = f"L {info['jumps']} / R {jr}"
            info["lr_similarity"] = float(np.mean(np.sum(bank.feats[path] * bank.feats[path_r], axis=1)))
            traj_r = (lambda k: pr[k])
        else:
            traj_r = (lambda k: pl[k])
        traj_l = (lambda k: pl[k])
    elif mode == "replay":
        a, bb, fr, slot_rms, stretch, visited = _replay(
            bank, n_frames, cfg.replay_stretch, cfg.weighting, rng_profile,
            hop, chunk, pad, n_samples)
        raw = P[a] * (1 - fr[:, None]) + P[bb] * fr[:, None]
        if c > 0:                           # optional smoothing
            for k in range(1, n_frames):
                raw[k] = c * 0.5 * raw[k - 1] + (1 - c * 0.5) * raw[k]
        pl = mean_p[None, :] * (1 - v) + raw * v
        frame_rms = slot_rms
        traj_l = traj_r = (lambda k: pl[k])
        info["replay_stretch"] = round(stretch, 3)
        info["replay_files_visited"] = visited
        info["jumps"] = "n/a"

    f = bank.canonical_freq
    intended_centroid_r = np.zeros(n_frames)
    for k in range(n_frames):
        p = np.asarray(traj_l(k), np.float64)
        intended_centroid[k] = float(p @ f / max(p.sum(), 1e-12))
        q = np.asarray(traj_r(k), np.float64)
        intended_centroid_r[k] = float(q @ f / max(q.sum(), 1e-12))

    # ---- overlap-add ----
    out = np.zeros((total + chunk, 2), np.float64)
    wsum = np.zeros(total + chunk, np.float64)
    for k in range(n_frames):
        st = k * hop
        pls = np.interp(synth_freq, f, traj_l(k))
        prs = pls if traj_r is traj_l else np.interp(synth_freq, f, traj_r(k))
        for ch, (noise, prof) in enumerate(((noise_l, pls), (noise_r, prs))):
            ph = np.angle(np.fft.rfft(noise[st:st + chunk] * window, n=chunk))
            out[st:st + chunk, ch] += np.fft.irfft(prof * np.exp(1j * ph), n=chunk) * window
        wsum[st:st + chunk] += window ** 2
    safe = wsum > 0.075
    out[safe, :] /= wsum[safe, None]
    out[~safe, :] = 0.0
    out = out[pad:pad + n_samples, :].astype(np.float32)

    # ---- envelope ----
    env_mode = cfg.envelope
    if env_mode == "auto":
        env_mode = "trajectory" if mode == "replay" else "learned"
    if env_mode == "learned":
        env_target = bank.mean_envelope
        env_curve = np.interp(np.linspace(0, 1, n_samples),
                              np.linspace(0, 1, ENV_LEN), env_target).astype(np.float32)
    elif env_mode == "trajectory":
        centres = (np.arange(n_frames) * hop + chunk / 2.0 - pad)
        env_curve = np.interp(np.arange(n_samples), centres, frame_rms).astype(np.float32)
        pk = float(env_curve.max())
        env_curve = env_curve / pk if pk > 1e-12 else env_curve
        env_target = np.interp(np.linspace(0, n_samples - 1, ENV_LEN),
                               np.arange(n_samples), env_curve).astype(np.float32)
    else:  # flat
        env_curve = np.ones(n_samples, np.float32)
        env_target = np.ones(ENV_LEN, np.float32)
    env_curve = _smooth_curve(env_curve, max(1, int(0.02 * sr)))
    out *= env_curve[:, None]

    fade = min(int(0.010 * sr), n_samples // 4)
    if fade > 0:
        out[:fade] *= np.linspace(0, 1, fade, dtype=np.float32)[:, None]
        out[-fade:] *= np.linspace(1, 0, fade, dtype=np.float32)[:, None]
    peak = float(np.max(np.abs(out))) if out.size else 0.0
    if peak > 1e-6:
        out *= np.float32(0.90 / peak)

    stats["envelope_mode"] = env_mode
    stats.update({k: (round(val, 4) if isinstance(val, float) else val) for k, val in info.items()})
    # intended trajectory on output-time axis (frame centres, seconds)
    centres_s = (np.arange(n_frames) * hop + chunk / 2.0 - pad) / sr
    print(f"  Generated {n_samples} samples, peak {np.max(np.abs(out)):.3f}", flush=True)
    return out, env_target, centres_s, intended_centroid, intended_centroid_r, mean_p


# =============================================================================
#  STAGE 5 - QC (same pipeline as the analysis)
# =============================================================================

def measure_output(audio, bank, sr, chunk, hop):
    """Per-frame shapes of the rendered audio, using the analysis pipeline."""
    window = np.hanning(chunk).astype(np.float32)
    afreq = np.fft.rfftfreq(bank.analysis_fft, d=1.0 / sr)
    n = audio.shape[0]
    nf = _n_frames(n, chunk, hop)
    shapes, feats, times, rms = [], [], [], []
    for i in range(nf):
        fr = audio[i * hop:i * hop + chunk, :]
        if fr.shape[0] < chunk:
            fr = np.pad(fr, ((0, chunk - fr.shape[0]), (0, 0)))
        r = math.sqrt(float(np.mean(fr.astype(np.float64) ** 2)))
        spec = np.abs(np.fft.rfft(fr * window[:, None], n=bank.analysis_fft, axis=0))
        mag = np.sqrt(np.mean(spec.astype(np.float64) ** 2, axis=1))
        if bank.analysis_fft != len(bank.canonical_freq) * 2 - 2:
            mag = np.interp(bank.canonical_freq, afreq, mag)
        rms.append(r)
        times.append((i * hop + chunk / 2.0) / sr)
        mr = math.sqrt(float(np.mean(mag ** 2)))
        shapes.append(mag / mr if mr > 1e-12 else mag)
        feats.append(_band_vec(shapes[-1], bank.bm))
    rms = np.asarray(rms)
    active = rms > max(1e-8, rms.max() * 1e-3)
    return (np.asarray(shapes), np.asarray(feats), np.asarray(times), active)


def _cos(a, b):
    a, b = np.asarray(a, np.float64), np.asarray(b, np.float64)
    d = np.linalg.norm(a) * np.linalg.norm(b)
    return float(a @ b / d) if d > 1e-12 else 0.0


def _rms_envelope(audio, n_points=ENV_LEN):
    a = np.asarray(audio, np.float64)
    edges = np.linspace(0, a.shape[0], n_points + 1).astype(int)
    vals = np.array([math.sqrt(float(np.mean(a[edges[i]:edges[i + 1]] ** 2)))
                     if edges[i + 1] > edges[i] else 0.0 for i in range(n_points)])
    return vals / vals.max() if vals.max() > 1e-12 else vals


def _corr(a, b):
    """Correlation of two centroid tracks, or NaN when the first (reference)
    track is too static for a correlation to mean anything (std < 1 % of its
    mean, e.g. low Variation): then any r is just measurement noise."""
    if (len(a) > 3 and np.std(a) > max(1.0, 0.01 * abs(np.mean(a)))
            and np.std(b) > 1.0):
        return float(np.corrcoef(a, b)[0, 1])
    return float("nan")


def write_qc(cfg, bank, audio, env_target, centres_s, intended_centroid,
             intended_centroid_r, mean_p, stats):
    sr, chunk, hop = cfg.sr, cfg.chunk_size, cfg.hop_length
    shapes, feats, times, active = measure_output(audio, bank, sr, chunk, hop)
    f = bank.canonical_freq

    op = shapes[active].mean(axis=0) if active.any() else shapes.mean(axis=0)
    cp = mean_p.astype(np.float64)
    cpn, opn = cp / max(cp.max(), 1e-12), op / max(op.max(), 1e-12)
    spectral = _cos(cpn, opn)
    c_cent = float(f @ cp / max(cp.sum(), 1e-12))
    o_cent = float(f @ op / max(op.sum(), 1e-12))

    out_env = _rms_envelope(audio)
    env_sim = _cos(env_target, out_env)

    idx = np.where(active[:-1] & active[1:])[0]
    out_motion = float(np.mean(np.sum(feats[idx] * feats[idx + 1], axis=1))) if len(idx) else float("nan")
    corp_motion = bank.corpus_motion
    # 0.25 s blocks in SOURCE time: in Replay one source second lasts
    # `stretch` output seconds, so the block grows with the stretch
    # (otherwise a 2x replay reports twice the corpus movement).
    time_scale = float(stats.get("replay_stretch", 1.0)) if cfg.mode == "replay" else 1.0
    blk = max(1, int(round(0.25 * time_scale * sr / float(hop))))
    out_mov = _movement([(feats[active], blk)])
    cm = bank.corpus_movement
    # A nearly static corpus (sustained tones, ~0.0-0.015) leaves the ratio
    # dominated by the random-phase measurement floor; moving material sits
    # around 0.1-0.6. Below the floor the metric is reported as undefined.
    STATIC_FLOOR = 0.02
    temporal = (min(2.0, out_mov / cm)
                if np.isfinite(out_mov) and np.isfinite(cm) and cm >= STATIC_FLOOR
                else float("nan"))
    if np.isfinite(cm) and cm < STATIC_FLOOR:
        stats["temporal_structure_note"] = "corpus nearly static: movement ratio not meaningful"
    stats["corpus_movement"] = round(cm, 6) if np.isfinite(cm) else "undefined"
    stats["output_movement"] = round(out_mov, 6) if np.isfinite(out_mov) else "undefined"

    # realised centroid per output frame vs intended path. In counterpoint the
    # channels follow different paths, so each is measured on its own channel.
    intended_on_out = np.interp(times, centres_s, intended_centroid)
    intended_r_on_out = np.interp(times, centres_s, intended_centroid_r)
    if cfg.mode == "counterpoint":
        sh_l = measure_output(audio[:, :1], bank, sr, chunk, hop)[0]
        sh_r = measure_output(audio[:, 1:2], bank, sr, chunk, hop)[0]
        real_cent = (sh_l @ f) / np.maximum(sh_l.sum(axis=1), 1e-12)
        real_cent_r = (sh_r @ f) / np.maximum(sh_r.sum(axis=1), 1e-12)
        path_r = _corr(intended_on_out[active], real_cent[active])
        path_r_r = _corr(intended_r_on_out[active], real_cent_r[active])
        # only meaningful if at least one intended path actually moves
        lr_corr = (_corr(real_cent[active], real_cent_r[active])
                   if np.isfinite(path_r) or np.isfinite(path_r_r) else float("nan"))
    else:
        real_cent = (shapes @ f) / np.maximum(shapes.sum(axis=1), 1e-12)
        real_cent_r = real_cent
        path_r = _corr(intended_on_out[active], real_cent[active])
        path_r_r = path_r
        lr_corr = float("nan")

    with open(cfg.profile_csv, "w", encoding="utf-8") as fh:
        fh.write("frequency_hz,corpus_mean,output_mean\n")
        for hz, a, b in zip(f, cpn, opn):
            fh.write(f"{hz:.9g},{a:.9g},{b:.9g}\n")
    with open(cfg.envelope_csv, "w", encoding="utf-8") as fh:
        fh.write("time_norm,target_envelope,output_rms\n")
        for i, (a, b) in enumerate(zip(env_target, out_env)):
            fh.write(f"{i / (ENV_LEN - 1):.9g},{float(a):.9g},{float(b):.9g}\n")
    if cfg.trajectory_csv:
        with open(cfg.trajectory_csv, "w", encoding="utf-8") as fh:
            fh.write("time_s,intended_centroid_hz,output_centroid_hz,"
                     "intended_r_hz,output_r_hz,active\n")
            for t, a, b, ar, br, ac in zip(times, intended_on_out, real_cent,
                                           intended_r_on_out, real_cent_r, active):
                if t <= audio.shape[0] / sr:
                    fh.write(f"{t:.6f},{a:.3f},{b:.3f},{ar:.3f},{br:.3f},{int(ac)}\n")

    stats["spectral_similarity"] = round(spectral, 6)
    stats["envelope_similarity"] = round(env_sim, 6)
    stats["corpus_motion"] = round(corp_motion, 6) if np.isfinite(corp_motion) else "undefined"
    stats["output_motion"] = round(out_motion, 6) if np.isfinite(out_motion) else "undefined"
    stats["temporal_structure"] = round(temporal, 6) if np.isfinite(temporal) else "undefined"
    stats["path_fidelity_r"] = round(path_r, 6) if np.isfinite(path_r) else "undefined"
    if cfg.mode == "counterpoint":
        stats["path_fidelity_r_right"] = round(path_r_r, 6) if np.isfinite(path_r_r) else "undefined"
        stats["lr_centroid_correlation"] = round(lr_corr, 6) if np.isfinite(lr_corr) else "undefined"
    stats["corpus_spectral_centroid_hz"] = round(c_cent, 2)
    stats["output_spectral_centroid_hz"] = round(o_cent, 2)


def write_summary_csv(path, stats):
    """One row for the Praat figure. Every optional metric has a *_valid
    column (1/0) so that a real value of -1 (e.g. a perfectly negative
    correlation) is never confused with 'not measurable'."""
    cols = [("files_used", "files_used"), ("files_skipped", "files_skipped"),
            ("corpus_duration_s", "corpus_duration_used_s"),
            ("profile_bank_size", "profile_bank_size"), ("max_profiles", "max_profiles"),
            ("profile_stride", "profile_stride"),
            ("corpus_centroid_hz", "corpus_spectral_centroid_hz"),
            ("output_centroid_hz", "output_spectral_centroid_hz"),
            ("spectral_similarity", "spectral_similarity"),
            ("envelope_similarity", "envelope_similarity"),
            ("temporal_structure", "temporal_structure"),
            ("path_fidelity_r", "path_fidelity_r"),
            ("path_fidelity_r_right", "path_fidelity_r_right"),
            ("lr_centroid_correlation", "lr_centroid_correlation"),
            ("replay_stretch", "replay_stretch")]
    names, vals = [], []
    for name, key in cols:
        v = stats.get(key, None)
        try:
            v = float(v)
            ok = int(np.isfinite(v))
        except (TypeError, ValueError):
            v, ok = 0.0, 0
        names += [name, name + "_valid"]
        vals += [f"{(v if ok else 0.0):.9g}", str(ok)]
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(",".join(names) + "\n")
        fh.write(",".join(vals) + "\n")


def write_stats(path, stats):
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(f"=== Spectral Noise Shaping v{VERSION} - Stats ===\n\n")
        for key, val in stats.items():
            if key == "skipped_details":
                fh.write("skipped_files:\n")
                for name, reason in (val or []):
                    fh.write(f"  {name}: {reason}\n")
            else:
                fh.write(f"{key}: {val}\n")


# =============================================================================
#  MAIN
# =============================================================================

def main():
    ap = argparse.ArgumentParser(description=f"Spectral noise shaping v{VERSION}")
    ap.add_argument("input_folder")
    ap.add_argument("output_wav")
    ap.add_argument("stats_txt")
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("--duration", type=float, default=3.0)
    ap.add_argument("--sr", type=int, default=44100)
    ap.add_argument("--n_fft", type=int, default=2048)
    ap.add_argument("--hop_length", type=int, default=512)
    ap.add_argument("--chunk_size", type=int, default=None)
    ap.add_argument("--mode", choices=MODES, default="walk")
    ap.add_argument("--variation", type=float, default=0.7,
                    help="0 = corpus mean, 1 = full learned frame identity")
    ap.add_argument("--continuity", type=float, default=0.75,
                    help="dependence of each frame on the previous one")
    ap.add_argument("--envelope", choices=("auto", "learned", "trajectory", "flat"), default="auto")
    ap.add_argument("--weighting", choices=("equal", "duration"), default="equal")
    ap.add_argument("--max_profiles", type=int, default=20000)
    ap.add_argument("--replay_stretch", type=float, default=0.0,
                    help="replay time stretch; 0 = fit one source file to the duration")
    ap.add_argument("--migration_feature", choices=("centroid", "flatness"), default="centroid")
    ap.add_argument("--migration_direction", choices=("rising", "falling", "arch", "valley"),
                    default="rising")
    ap.add_argument("--coupling", type=float, default=0.3, help="counterpoint L/R coupling")
    ap.add_argument("--profile_csv")
    ap.add_argument("--envelope_csv")
    ap.add_argument("--trajectory_csv")
    ap.add_argument("--summary_csv")
    ap.add_argument("--done_file")
    ap.add_argument("--log_file", help="redirect stderr here (lets Praat call "
                    "Python via runSubprocess, without a shell redirect)")
    cfg = ap.parse_args()
    if cfg.log_file:
        try:
            sys.stderr = open(cfg.log_file, "w", encoding="utf-8")
        except OSError:
            pass

    cfg.chunk_size = cfg.chunk_size if cfg.chunk_size is not None else cfg.n_fft
    try:
        validated_chunk_size(cfg.chunk_size, cfg.hop_length)
        if cfg.n_fft < 64:
            raise ValueError("n_fft must be at least 64")
        if cfg.sr < 8000:
            raise ValueError("sample rate must be at least 8000 Hz")
        if cfg.duration <= 0:
            raise ValueError("duration must be > 0")
        if cfg.max_profiles < 100:
            raise ValueError("max_profiles must be at least 100")
    except ValueError as exc:
        print(f"ERROR: {exc}", flush=True)
        write_stats(cfg.stats_txt, {"error": str(exc)})
        sys.exit(1)
    if cfg.seed is not None and cfg.seed <= 0:   # Praat convention: 0 = random
        cfg.seed = None
    cfg.variation = float(np.clip(cfg.variation, 0.0, 1.0))
    cfg.continuity = float(np.clip(cfg.continuity, 0.0, 1.0))
    if cfg.done_file and os.path.exists(cfg.done_file):
        os.remove(cfg.done_file)

    print(f"=== Spectral Noise Shaping v{VERSION} ===", flush=True)
    stats = {"version": VERSION, "mode": cfg.mode, "sample_rate": cfg.sr,
             "duration": cfg.duration, "n_fft": cfg.n_fft, "hop_length": cfg.hop_length,
             "chunk_size": cfg.chunk_size, "variation": cfg.variation,
             "continuity": cfg.continuity, "weighting": cfg.weighting,
             "seed": cfg.seed if cfg.seed is not None else "random"}
    try:
        t0 = time.time()
        entries, _ = scan_corpus(cfg.input_folder, cfg.sr, 0.2, stats)
        if not entries:
            raise ValueError("No usable audio files in the corpus folder")
        bank = analyse_corpus(entries, cfg.sr, cfg.n_fft, cfg.hop_length,
                              cfg.chunk_size, cfg.max_profiles, stats)
        audio, env_target, centres_s, intended, intended_r, mean_p = generate(bank, cfg, stats)
        print("[4/5] Writing output...", flush=True)
        sf.write(cfg.output_wav, audio, cfg.sr, subtype="FLOAT")
        stats["output_duration"] = round(audio.shape[0] / cfg.sr, 3)
        stats["output_peak"] = round(float(np.max(np.abs(audio))), 4)
        print("[5/5] Measuring result...", flush=True)
        if cfg.profile_csv and cfg.envelope_csv:
            write_qc(cfg, bank, audio, env_target, centres_s, intended, intended_r, mean_p, stats)
        if cfg.summary_csv:
            write_summary_csv(cfg.summary_csv, stats)
        stats["total_time_s"] = round(time.time() - t0, 2)
        stats["status"] = "ok"
        write_stats(cfg.stats_txt, stats)
        if cfg.done_file:
            with open(cfg.done_file, "w", encoding="utf-8") as fh:
                fh.write("ok\n")
        print(f"Done in {stats['total_time_s']}s", flush=True)
    except ValueError as exc:            # user-facing problem: plain message
        print(f"ERROR: {exc}", flush=True)
        stats["status"] = "failed"
        stats["error"] = str(exc)
        write_stats(cfg.stats_txt, stats)
        sys.exit(1)
    except Exception:
        msg = traceback.format_exc()
        print(f"ERROR:\n{msg}", flush=True)
        stats["status"] = "failed"
        stats["error"] = msg
        write_stats(cfg.stats_txt, stats)
        sys.exit(1)


if __name__ == "__main__":
    main()
