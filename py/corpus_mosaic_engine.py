"""
corpus_mosaic_engine.py — Offline Corpus Mosaic Engine  v1.4.0

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University
Version: 1.4.0 (2026)
License: MIT

Signal conventions (deliberate, documented):
  - Everything is analysed and rendered in MONO. Stereo sources and corpus
    files are downmixed on load.
  - The render rate is the SOURCE file's native sample rate; corpus files are
    resampled to it. (Up to v1.2.1 everything was forced to 44.1 kHz.)
  - The "loudness" dimension is frame RMS (energy), not a psychoacoustic
    loudness model. The GUI keeps the name Loudness_weight for compatibility.

v1.4.0 (visualization data; matching and audio are unchanged):
  - The match CSV gains per-grain display columns: file_rank (1 = most used
    file), chain (1 = this grain continues the previous corpus read),
    corpus_pos (0..1 position inside its file), target/match loudness (dB),
    brightness (centroid Hz), pitch (Hz) with reliability, and 2-D map
    coordinates (tx, ty, mx, my). Existing columns are unchanged.
  - Optional --out_map CSV: a sample (<= 2500) of all corpus grains projected
    into the same 2-D map. The map is a PCA of the WEIGHTED, normalised
    feature space the matcher actually searches, so a short line on the map
    really is a close match. Axis meanings and explained variance are written
    to the stats file.
  - Stats add hop/taper lengths, the continuity ratio, mean distance and the
    usage legend (top seven files by use).

v1.3.1:
  - Corpus discovery is now case-insensitive on every OS: WAV/FlAc/AIFF and
    other case variants are accepted on Linux as well as macOS/Windows.
  - Pitch matching is reliability-aware. YIN's minimum frequency rises for
    very short grains (at least two periods per analysis frame), and pitch is
    progressively down-weighted for short/noise-like grains when Loudness or
    Timbre are also enabled. Pitch-only matching still honours the user's
    explicit choice.
  - Stats report the adaptive YIN floor and mean source pitch reliability.

v1.3.0:
  - Overlap-add is now amplitude-flat at EVERY overlap setting. Grains use a
    raised-cosine taper whose length equals the actual overlap (a Hann shape
    once overlap >= 50%), and the output is divided by the steady-state sum of
    the analysis-grid windows (floored at 1). Up to v1.2.1 a fixed Hann window
    with no normalisation gave ~8 dB of grain-rate tremolo at 25-30% overlap,
    near-silent gaps at 0%, and a 2x level at 75%. At 0% overlap grains are
    now butt-spliced with 5 ms declick fades. NOTE: at high overlap, grains
    from unrelated corpus positions can still phase-cancel on tonal material;
    that is granular interference, not a gain error.
  - The three GUI weights are now three equal CATEGORY weights. Timbre is
    described by four features, so timbre_w is divided across them; with
    1/1/1 each category now gets 1/3 of the distance (was 1/6, 2/3, 1/6).
    Negative weights are clamped to 0; all-zero falls back to equal.
  - Pure acoustic distance and selection score are now separate.
    selection_score = acoustic_distance + repetition_penalty - continuity_bonus
    and is no longer clipped at 0, so a continuity bonus on a perfect match is
    a real preference instead of a tie. The CSV "distance" column now holds
    the PURE acoustic distance; a new "selection_score" column holds the
    decision value. Randomness weighting is unchanged whenever the top-k
    scores are non-negative.
  - Pitch is compared on a log2 (octave) scale instead of in Hz, so equal
    musical intervals are equal distances in every register.
  - Reproducible randomness: --seed N (N > 0) fixes the selection sequence.
    With --seed 0 a seed is drawn and REPORTED in the stats file, so any run
    can be repeated afterwards.
  - Corpus files that fail to load, or are shorter than one grain, are now
    counted and reported instead of being skipped silently.
  - corpus_file in the CSV is the path RELATIVE to the corpus folder, and
    "Unique files utilized" counts full paths, so same-named files in
    different subfolders are no longer merged.
  - Top-k selection uses argpartition (O(n) instead of a full sort).

v1.2.1:
  - Align feature frames with the grains that are actually rendered. Librosa's
    default centered framing created padded boundary frames whose metadata was
    treated as left-aligned audio; a 1.0 s source with 100 ms / 50% overlap,
    for example, produced a phantom grain at 1.0 s and a 1.1 s output.
    Frames are now explicitly left-aligned, the final partial frame is padded
    only as needed for coverage, and the rendered mosaic is trimmed to the
    exact source duration.
"""

import argparse
import csv
import math
import os
import sys
import time
import warnings

warnings.filterwarnings('ignore')

def check_dependencies():
    missing = []
    for pkg in ["numpy", "soundfile", "scipy", "librosa"]:
        try:
            __import__(pkg)
        except ImportError:
            missing.append(pkg)
    if missing:
        print("ERROR: Missing packages: " + ", ".join(missing), file=sys.stderr)
        print("Install:  pip install " + " ".join(missing), file=sys.stderr)
        sys.exit(1)

check_dependencies()

import numpy as np
import soundfile as sf
import librosa


def parse_args():
    parser = argparse.ArgumentParser(description="Corpus Mosaic Engine")
    parser.add_argument("--source", required=True)
    parser.add_argument("--corpus", required=True)
    parser.add_argument("--out_wav", required=True)
    parser.add_argument("--out_csv", required=True)
    parser.add_argument("--out_stats", required=True)
    parser.add_argument("--out_map", default="",
                        help="optional CSV of corpus grains in the 2-D match map")
    
    parser.add_argument("--grain_ms", type=float, default=100.0)
    parser.add_argument("--overlap", type=float, default=0.5)
    
    parser.add_argument("--pitch_w", type=float, default=1.0)
    parser.add_argument("--timbre_w", type=float, default=1.0)
    parser.add_argument("--loudness_w", type=float, default=1.0)
    
    parser.add_argument("--top_k", type=int, default=5)
    parser.add_argument("--randomness", type=float, default=0.5)
    parser.add_argument("--continuity", type=float, default=0.3)
    parser.add_argument("--penalty", type=float, default=1.5)
    parser.add_argument("--normalize", action="store_true")
    parser.add_argument("--seed", type=int, default=0,
                        help="RNG seed; 0 = draw one and report it")
    
    # NEW: Gate threshold in dB relative to the peak volume of the source
    parser.add_argument("--gate_db", type=float, default=-40.0)
    
    args = parser.parse_args()
    
    # --- Robust Parameter Clamping ---
    args.grain_ms = max(10.0, args.grain_ms)
    args.overlap = float(np.clip(args.overlap, 0.0, 0.99))
    args.top_k = max(1, args.top_k)
    args.randomness = float(np.clip(args.randomness, 0.0, 1.0))
    args.continuity = max(0.0, args.continuity)
    args.penalty = max(0.0, args.penalty)
    args.gate_db = min(-10.0, args.gate_db) # Keep sensible limits
    args.pitch_w = max(0.0, args.pitch_w)
    args.timbre_w = max(0.0, args.timbre_w)
    args.loudness_w = max(0.0, args.loudness_w)
    args.seed = max(0, args.seed)
    
    return args


def _pad_for_left_aligned_frames(y, win_length, hop_length):
    """Pad only the tail needed for a final left-aligned analysis frame.

    The returned length is exactly ``(n_frames - 1) * hop + win``.  This keeps
    feature row i tied to audio starting at ``i * hop`` while still covering
    the end of a signal that is not an exact hop-grid length.
    """
    n = len(y)
    if n <= win_length:
        target = win_length
    else:
        n_frames = int(math.ceil((n - win_length) / hop_length)) + 1
        target = (n_frames - 1) * hop_length + win_length
    if target <= n:
        return y
    return np.pad(y, (0, target - n))


def taper_window(win_length, taper_length):
    """Flat-top grain window with raised-cosine (sin^2) edges.

    Adjacent fade-out/fade-in pairs of equal length sum to exactly 1, so with
    taper_length == overlap the grains cross-fade at constant gain. With
    taper_length == win_length // 2 this is a Hann shape.
    """
    w = np.ones(win_length, dtype=np.float64)
    T = int(taper_length)
    if T > 0:
        n = np.arange(T, dtype=np.float64)
        fade = np.sin(0.5 * np.pi * (n + 0.5) / T) ** 2
        w[:T] = fade
        w[win_length - T:] = fade[::-1]
    return w


def ola_normaliser(window, hop_length, out_length):
    """Steady-state overlap-add gain of the full analysis grid.

    The grid is extended past both ends so the file edges are NOT boosted
    (the first fade-in / last fade-out stay as real fades). The sum is
    floored at 1: where windows genuinely overlap it is >= 1 and dividing
    makes the result flat; where they do not (declick fades at ~0% overlap)
    nothing is amplified.
    """
    win_length = len(window)
    ext = int(math.ceil(win_length / hop_length)) + 1
    n_positions = int(math.ceil(out_length / hop_length)) + 2 * ext + 1
    wsum = np.zeros((n_positions - 1) * hop_length + win_length, dtype=np.float64)
    for k in range(n_positions):
        a = k * hop_length
        wsum[a:a + win_length] += window
    off = ext * hop_length
    return np.maximum(wsum[off:off + out_length], 1.0)


def extract_features(y, sr, win_length, hop_length):
    # Explicit center=False is essential here: corpus_metadata and synthesis
    # both interpret feature row i as the grain beginning at i * hop_length.
    rms = librosa.feature.rms(y=y, frame_length=win_length, hop_length=hop_length, center=False)[0]
    cent = librosa.feature.spectral_centroid(y=y, sr=sr, n_fft=win_length, hop_length=hop_length, center=False)[0]
    flat = librosa.feature.spectral_flatness(y=y, n_fft=win_length, hop_length=hop_length, center=False)[0]
    roll = librosa.feature.spectral_rolloff(y=y, sr=sr, n_fft=win_length, hop_length=hop_length, center=False)[0]
    zcr = librosa.feature.zero_crossing_rate(y=y, frame_length=win_length, hop_length=hop_length, center=False)[0]

    # A fixed 50 Hz floor is not meaningful for very short grains: a 10 ms
    # frame does not even contain one 50 Hz period. Require at least two
    # periods inside the analysis frame, while keeping the historical 50 Hz
    # floor for normal (>=40 ms) grains.
    frame_seconds = win_length / float(sr)
    fmax = min(2000.0, 0.45 * sr)
    adaptive_fmin = max(50.0, 2.0 / max(frame_seconds, 1e-9))
    if adaptive_fmin >= fmax:
        adaptive_fmin = max(20.0, 0.5 * fmax)

    f0 = librosa.yin(
        y, fmin=adaptive_fmin, fmax=fmax, sr=sr,
        frame_length=win_length, hop_length=hop_length, center=False
    )
    f0[~np.isfinite(f0)] = adaptive_fmin
    # Compare pitch on an octave scale: equal intervals = equal distances.
    f0 = np.log2(np.maximum(f0, 1.0))

    min_len = min(len(rms), len(cent), len(flat), len(roll), len(zcr), len(f0))

    features = np.vstack([
        rms[:min_len],
        cent[:min_len],
        flat[:min_len],
        roll[:min_len],
        zcr[:min_len],
        f0[:min_len]
    ]).T

    # Reliability is deliberately conservative and cheap: short frames have
    # less pitch evidence, and spectrally flat/noise-like frames are less
    # plausibly periodic. This value is NOT another matching feature; it only
    # controls how much the pitch category participates in a mixed distance.
    duration_conf = min(1.0, frame_seconds / 0.050)
    tonality_conf = 1.0 - np.sqrt(np.clip(flat[:min_len], 0.0, 1.0))
    pitch_conf = np.clip(duration_conf * tonality_conf, 0.0, 1.0)

    return features, pitch_conf, adaptive_fmin


FEATURE_WORDS = ["louder", "brighter", "noisier", "brighter", "noisier", "higher pitch"]


def match_map(corpus_norm, source_norm, dim_w):
    """2-D PCA of the weighted matching space, fitted on the corpus.

    Returns projected corpus/source points, explained-variance percentage and
    a short plain-language label for each axis.
    """
    sw = np.sqrt(np.maximum(dim_w, 0.0))
    cw = corpus_norm * sw
    sw_src = source_norm * sw
    centre = cw.mean(axis=0)
    cov = np.cov((cw - centre).T) if len(cw) > 1 else np.eye(cw.shape[1])
    cov = np.atleast_2d(cov)
    vals, vecs = np.linalg.eigh(cov)
    order = np.argsort(vals)[::-1]
    vals = np.maximum(vals[order], 0.0)
    vecs = vecs[:, order]
    labels = []
    for a in range(2):
        v = vecs[:, a]
        if v[np.argmax(np.abs(v))] < 0:
            v = -v
            vecs[:, a] = v
        mx = np.max(np.abs(v))
        words = []
        for j in np.argsort(-np.abs(v)):
            if abs(v[j]) >= 0.5 * mx and v[j] > 0 and dim_w[j] > 0:
                if FEATURE_WORDS[j] not in words:
                    words.append(FEATURE_WORDS[j])
        labels.append(", ".join(words[:2]) if words else "mixed")
    total = float(vals.sum())
    explained = 100.0 * float(vals[:2].sum()) / total if total > 0 else 100.0
    pc = vecs[:, :2]
    return (cw - centre) @ pc, (sw_src - centre) @ pc, explained, labels


def robust_z_score(features, eps=1e-8):
    mean = np.mean(features, axis=0)
    std = np.std(features, axis=0)
    norm = (features - mean) / (std + eps)
    return norm, mean, std


def main():
    start_time = time.time()
    args = parse_args()
    
    if not os.path.exists(args.source):
        print(f"ERROR: Source file {args.source} not found.", file=sys.stderr)
        sys.exit(1)
        
    try:
        target_sr = int(sf.info(args.source).samplerate)
    except Exception:
        target_sr = 44100
    win_length = int(target_sr * (args.grain_ms / 1000.0))
    hop_length = max(1, int(win_length * (1.0 - args.overlap)))
    overlap_length = win_length - hop_length
    declick_length = min(int(0.005 * target_sr), win_length // 2)
    taper_length = min(max(overlap_length, declick_length), win_length // 2)

    seed = args.seed
    if seed == 0:
        seed = int(np.random.SeedSequence().entropy % (2 ** 31 - 1)) + 1
    rng = np.random.default_rng(seed)

    # ── 1. Source Processing ──────────────────────────────────────────────────
    print(f"[Py 1/5] Loading source audio & extracting features...")
    y_source, _ = librosa.load(args.source, sr=target_sr, mono=True)
    
    if len(y_source) < win_length:
        print("ERROR: Source audio is shorter than a single grain.", file=sys.stderr)
        sys.exit(1)

    source_for_features = _pad_for_left_aligned_frames(y_source, win_length, hop_length)
    source_features, source_pitch_conf, pitch_fmin = extract_features(
        source_for_features, target_sr, win_length, hop_length
    )
    num_source_grains = len(source_features)
    print(f"    Source grains: {num_source_grains}")

    # --- NEW: Calculate Silence Gate Threshold ---
    # Feature column 0 is raw RMS. We find the peak RMS, and calculate the linear floor.
    source_rms_raw = source_features[:, 0]
    peak_rms = np.max(source_rms_raw)
    gate_thresh = max(1e-7, peak_rms * (10 ** (args.gate_db / 20.0)))

    # ── 2. Corpus Scanning ────────────────────────────────────────────────────
    print(f"[Py 2/5] Scanning corpus folder...")
    audio_exts = {'.wav', '.flac', '.aiff', '.aif'}
    corpus_files = []
    for root, dirs, names in os.walk(args.corpus):
        dirs.sort(key=str.lower)
        for name in sorted(names, key=str.lower):
            if os.path.splitext(name)[1].lower() in audio_exts:
                corpus_files.append(os.path.normpath(os.path.join(root, name)))

    # Stable de-duplication also protects against unusual alias/symlink layouts.
    corpus_files = sorted(set(corpus_files), key=lambda p: p.lower())

    if not corpus_files:
        print(f"ERROR: No audio files found in corpus {args.corpus}", file=sys.stderr)
        sys.exit(1)

    # ── 3. Corpus Extraction ──────────────────────────────────────────────────
    print(f"[Py 3/5] Extracting corpus features ({len(corpus_files)} files)...")
    
    corpus_features_list = []
    corpus_pitch_conf_list = []
    corpus_metadata = []
    corpus_audio_data = []
    
    corpus_root = os.path.abspath(args.corpus)
    valid_files_used = 0
    skipped_short = []
    skipped_error = []
    for fpath in corpus_files:
        try:
            y_corp, _ = librosa.load(fpath, sr=target_sr, mono=True)
            if len(y_corp) < win_length:
                skipped_short.append(fpath)
                continue
                
            y_corp_for_features = _pad_for_left_aligned_frames(y_corp, win_length, hop_length)
            feats, pitch_conf, _ = extract_features(
                y_corp_for_features, target_sr, win_length, hop_length
            )
            corpus_features_list.append(feats)
            corpus_pitch_conf_list.append(pitch_conf)
            corpus_audio_data.append(y_corp)
            
            file_idx = len(corpus_audio_data) - 1
            rel_path = os.path.relpath(os.path.abspath(fpath), corpus_root).replace(os.sep, '/')
            for grain_i in range(len(feats)):
                corpus_metadata.append({
                    'file_idx': file_idx,
                    'file_path': fpath,
                    'rel_path': rel_path,
                    'start_sample': grain_i * hop_length
                })
            valid_files_used += 1
        except Exception as e:
            skipped_error.append((fpath, f"{type(e).__name__}: {e}"))

    if skipped_short:
        print(f"    Skipped {len(skipped_short)} file(s) shorter than one grain.")
    for fpath, msg in skipped_error:
        print(f"WARNING: could not read corpus file {fpath} ({msg})", file=sys.stderr)

    if len(corpus_features_list) == 0:
        print("ERROR: Could not extract features from any corpus files.", file=sys.stderr)
        sys.exit(1)

    corpus_features = np.vstack(corpus_features_list)
    corpus_pitch_conf = np.concatenate(corpus_pitch_conf_list)
    num_corpus_grains = len(corpus_features)
    print(f"    Built database: {num_corpus_grains} grains from {valid_files_used} valid files.")

    # ── 4. Normalisation & Weighting ──────────────────────────────────────────
    print("[Py 4/5] Computing feature distances and matching...")
    # The corpus defines the centre of the feature space. The scale of each
    # dimension is the corpus spread, floored at the spread of corpus+source
    # together: a (near-)constant corpus column (one sustained pitch, a
    # steady tone) would otherwise divide by ~1e-8, blow distances up to
    # ~1e16 and make the repetition/continuity terms irrelevant.
    c_mean = np.mean(corpus_features, axis=0)
    c_std = np.std(corpus_features, axis=0)
    active = source_features[source_features[:, 0] >= gate_thresh]
    if len(active) == 0:
        active = source_features
    pooled_std = np.std(np.vstack([corpus_features, active]), axis=0)
    scale = np.maximum(np.maximum(c_std, pooled_std), 1e-9)
    corpus_norm = (corpus_features - c_mean) / scale
    source_norm = (source_features - c_mean) / scale
    
    # Three CATEGORY weights. Timbre is the mean squared distance across its
    # four descriptors, so 1/1/1 still means one third per category. Pitch is
    # reliability-aware only when another category is available to take over.
    cat_w = np.array([args.loudness_w, args.timbre_w, args.pitch_w], dtype=np.float64)
    if cat_w.sum() <= 0:
        cat_w = np.ones(3)
    cat_w = cat_w / cat_w.sum()
    
    # Per-dimension weights used only for the 2-D display map. Pitch uses the
    # mean corpus reliability, mirroring its average share in mixed matching.
    if cat_w[0] + cat_w[1] <= 1e-12:
        map_w = np.array([0, 0, 0, 0, 0, 1.0])
    else:
        rel = float(np.mean(corpus_pitch_conf))
        map_w = np.array([cat_w[0]] + [cat_w[1] / 4.0] * 4 + [cat_w[2] * rel])
    corpus_xy, source_xy, map_explained, map_labels = match_map(corpus_norm, source_norm, map_w)

    out_length = (num_source_grains - 1) * hop_length + win_length
    out_audio = np.zeros(out_length, dtype=np.float64)
    window = taper_window(win_length, taper_length)
    
    matches_record = []
    recent_choices = []
    penalty_memory = max(1, int(target_sr / hop_length * 2)) 
    prev_corpus_idx = -1
    
    max_dist_estimate = float(np.max(np.var(corpus_norm, axis=0)) * 10)
    if max_dist_estimate <= 1e-9:
        max_dist_estimate = 10.0
    
    silent_grains_count = 0
    used_paths = set()
    corpus_lengths = [len(a) for a in corpus_audio_data]
    display = []      # per-record display columns, filled in the loop
    chosen_list = []  # chosen corpus index per record (-1 = silence)
    prev_was_active = False

    def disp(feat_row):
        return (20.0 * math.log10(max(float(feat_row[0]), 1e-9)),
                float(feat_row[1]), float(2.0 ** feat_row[5]))

    for i in range(num_source_grains):
        
        # --- NEW: Silence Gate Check ---
        if source_rms_raw[i] < gate_thresh:
            prev_corpus_idx = -1  # Break continuity chain
            prev_was_active = False
            silent_grains_count += 1
            tl, tb, tp = disp(source_features[i])
            chosen_list.append(-1)
            display.append([0, tl, 0.0, tb, 0.0, tp, 0.0,
                            float(source_pitch_conf[i]), 0.0,
                            float(source_xy[i, 0]), float(source_xy[i, 1]),
                            float(source_xy[i, 0]), float(source_xy[i, 1])])
            matches_record.append([
                i, 
                round(i * hop_length / target_sr, 6), 
                "__SILENCE__", 
                0.0, 
                0.0,
                0.0
            ])
            continue # Skip rendering this grain entirely!

        s_vec = source_norm[i]
        
        # Pure acoustic distance: what the match actually sounds like.
        # Timbre is one category (mean of four descriptors). In mixed-weight
        # modes, unreliable pitch evidence hands its share back to the other
        # enabled categories instead of forcing arbitrary YIN estimates.
        loud_sq = (corpus_norm[:, 0] - s_vec[0]) ** 2
        timbre_sq = np.mean((corpus_norm[:, 1:5] - s_vec[1:5]) ** 2, axis=1)
        pitch_sq = (corpus_norm[:, 5] - s_vec[5]) ** 2

        if cat_w[0] + cat_w[1] <= 1e-12:
            # Explicit pitch-only mode: honour the user's choice.
            acoustic = pitch_sq
        else:
            pair_pitch_conf = np.minimum(source_pitch_conf[i], corpus_pitch_conf)
            effective_pitch_w = cat_w[2] * pair_pitch_conf
            denom = cat_w[0] + cat_w[1] + effective_pitch_w
            acoustic = (
                cat_w[0] * loud_sq
                + cat_w[1] * timbre_sq
                + effective_pitch_w * pitch_sq
            ) / np.maximum(denom, 1e-12)

        # Decision value: acoustic distance plus the behavioural terms.
        # Deliberately NOT clipped at 0, so a continuity bonus on an exact
        # match still outranks every other exact match.
        score = acoustic.copy()
        for rc in recent_choices:
            score[rc] += args.penalty * max_dist_estimate
                
        if prev_corpus_idx != -1 and prev_corpus_idx + 1 < num_corpus_grains:
            if corpus_metadata[prev_corpus_idx]['file_idx'] == corpus_metadata[prev_corpus_idx + 1]['file_idx']:
                score[prev_corpus_idx + 1] -= args.continuity * max_dist_estimate

        k = min(args.top_k, num_corpus_grains)
        if k < num_corpus_grains:
            top_k_indices = np.argpartition(score, k - 1)[:k]
        else:
            top_k_indices = np.arange(num_corpus_grains)
        top_k_indices = top_k_indices[np.argsort(score[top_k_indices], kind='stable')]
        
        if args.randomness > 0:
            top_scores = score[top_k_indices]
            # Inverse-score weighting needs non-negative values. When the best
            # score is >= 0 this shift cancels and the weighting is identical
            # to v1.2.1; when a bonus pushed it below 0 the best candidate
            # sits at 0 and is strongly preferred, as an exact match was.
            m = float(top_scores[0])
            top_dists = top_scores - m + max(m, 0.0)
            inv_dists = 1.0 / (top_dists + 1e-9)
            
            uniform_dist = np.ones_like(inv_dists) / len(inv_dists)
            probs_raw = (1.0 - args.randomness) * (inv_dists / np.sum(inv_dists)) + (args.randomness * uniform_dist)
            
            probs = np.maximum(probs_raw, 0.0)
            prob_sum = np.sum(probs)
            if prob_sum > 1e-9:
                probs = probs / prob_sum
            else:
                probs = np.ones(len(top_k_indices), dtype=np.float64) / len(top_k_indices)
                
            chosen_idx = int(rng.choice(top_k_indices, p=probs))
        else:
            chosen_idx = int(top_k_indices[0])
            
        is_chain = int(prev_was_active and prev_corpus_idx != -1
                       and chosen_idx == prev_corpus_idx + 1
                       and corpus_metadata[prev_corpus_idx]['file_idx']
                       == corpus_metadata[chosen_idx]['file_idx'])
        prev_was_active = True
        prev_corpus_idx = chosen_idx
        recent_choices.append(chosen_idx)
        if len(recent_choices) > penalty_memory:
            recent_choices.pop(0)
            
        meta = corpus_metadata[chosen_idx]
        c_audio_ref = corpus_audio_data[meta['file_idx']]
        start_samp = meta['start_sample']
        
        actual_len = min(win_length, len(c_audio_ref) - start_samp)
        segment = c_audio_ref[start_samp:start_samp+actual_len]
        
        if actual_len < win_length:
            padded = np.zeros(win_length, dtype=np.float64)
            padded[:actual_len] = segment
            segment = padded
            
        out_start = i * hop_length
        out_audio[out_start:out_start+win_length] += segment * window
        
        matches_record.append([
            i, 
            round(i * hop_length / target_sr, 6), 
            meta['rel_path'], 
            round(start_samp / target_sr, 6), 
            round(float(acoustic[chosen_idx]), 6),
            round(float(score[chosen_idx]), 6)
        ])
        used_paths.add(meta['file_path'])
        tl, tb, tp = disp(source_features[i])
        ml, mb, mp = disp(corpus_features[chosen_idx])
        span = max(1, corpus_lengths[meta['file_idx']] - win_length)
        chosen_list.append(chosen_idx)
        display.append([is_chain, tl, ml, tb, mb, tp, mp,
                        float(source_pitch_conf[i]), float(corpus_pitch_conf[chosen_idx]),
                        float(source_xy[i, 0]), float(source_xy[i, 1]),
                        float(corpus_xy[chosen_idx, 0]), float(corpus_xy[chosen_idx, 1]),
                        min(1.0, start_samp / span)])

    # ── 5. Output Finalisation ────────────────────────────────────────────────
    print("[Py 5/5] Finalising output and saving files...")

    # The analysis tail may be zero-padded to cover a final partial hop, but
    # the musical result must retain the source Sound's exact duration.
    out_audio = out_audio / ola_normaliser(window, hop_length, out_length)
    out_audio = out_audio[:len(y_source)]
    
    if args.normalize:
        peak = float(np.abs(out_audio).max())
        if peak > 0.01:
            out_audio = out_audio / peak * 0.95

    peak_out = float(np.abs(out_audio).max()) if len(out_audio) else 0.0
    if peak_out > 1.0:
        print(f"    WARNING: output peak {peak_out:.3f} exceeds full scale "
              f"(enable normalisation to avoid clipping).")
        
    sf.write(args.out_wav, out_audio.astype(np.float32), target_sr)
    
    # Rank files by how many grains they supplied (ties: first use).
    use_count = {}
    first_use = {}
    for n, rec in enumerate(matches_record):
        if rec[2] != "__SILENCE__":
            use_count[rec[2]] = use_count.get(rec[2], 0) + 1
            first_use.setdefault(rec[2], n)
    ranked = sorted(use_count, key=lambda k: (-use_count[k], first_use[k]))
    rank_of = {name: r + 1 for r, name in enumerate(ranked)}

    with open(args.out_csv, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(["source_grain", "source_time_sec", "corpus_file", "corpus_time_sec",
                         "distance", "selection_score",
                         "file_rank", "chain", "corpus_pos",
                         "t_loud_db", "m_loud_db", "t_bright_hz", "m_bright_hz",
                         "t_pitch_hz", "m_pitch_hz", "t_pitch_rel", "m_pitch_rel",
                         "tx", "ty", "mx", "my"])
        for rec, d in zip(matches_record, display):
            silent = rec[2] == "__SILENCE__"
            pos = 0.0 if silent else d[13]
            writer.writerow(rec + [0 if silent else rank_of[rec[2]], d[0], round(pos, 4)]
                            + [round(v, 4) for v in d[1:13]])

    if args.out_map:
        sample_rng = np.random.default_rng(12345)  # independent of the match RNG
        n_show = min(2500, num_corpus_grains)
        pick = np.sort(sample_rng.choice(num_corpus_grains, n_show, replace=False))
        with open(args.out_map, 'w', newline='', encoding='utf-8') as f:
            writer = csv.writer(f)
            writer.writerow(["x", "y"])
            for j in pick:
                writer.writerow([round(float(corpus_xy[j, 0]), 4), round(float(corpus_xy[j, 1]), 4)])

    active_records = [d for rec, d in zip(matches_record, display) if rec[2] != "__SILENCE__"]
    chain_pct = 100.0 * sum(d[0] for d in active_records) / max(1, len(active_records) - 1)
    mean_dist = float(np.mean([rec[4] for rec in matches_record if rec[2] != "__SILENCE__"])) \
        if active_records else 0.0
        
    unique_files = len(used_paths)
    duration = time.time() - start_time
    
    active_pitch_conf = source_pitch_conf[source_rms_raw >= gate_thresh]
    if len(active_pitch_conf) == 0:
        active_pitch_conf = source_pitch_conf
    mean_pitch_reliability = 100.0 * float(np.mean(active_pitch_conf))

    with open(args.out_stats, 'w', encoding='utf-8') as f:
        f.write(f"Source grains: {num_source_grains}\n")
        f.write(f"Silenced grains (Gated): {silent_grains_count}\n")
        f.write(f"Corpus files analyzed: {valid_files_used}\n")
        f.write(f"Corpus grains available: {num_corpus_grains}\n")
        f.write(f"Unique files utilized: {unique_files}\n")
        f.write(f"Corpus files skipped: {len(skipped_short) + len(skipped_error)}"
                f" ({len(skipped_short)} too short, {len(skipped_error)} unreadable)\n")
        f.write(f"Random seed: {seed}\n")
        f.write(f"Sample rate: {target_sr}\n")
        f.write(f"Effective weights (L/T/P): {100*cat_w[0]:.0f}/{100*cat_w[1]:.0f}/{100*cat_w[2]:.0f}\n")
        f.write(f"Pitch reliability (source active mean): {mean_pitch_reliability:.0f}%\n")
        f.write(f"Adaptive YIN fmin: {pitch_fmin:.1f} Hz\n")
        f.write(f"Output peak: {peak_out:.3f}\n")
        f.write(f"Hop ms: {1000.0 * hop_length / target_sr:.2f}\n")
        f.write(f"Grain ms exact: {1000.0 * win_length / target_sr:.2f}\n")
        f.write(f"Taper ms: {1000.0 * taper_length / target_sr:.2f}\n")
        f.write(f"Continuity ratio: {chain_pct:.0f}\n")
        f.write(f"Mean distance: {mean_dist:.3f}\n")
        f.write(f"Map variance: {map_explained:.0f}\n")
        f.write(f"Map axis 1: {map_labels[0]}\n")
        f.write(f"Map axis 2: {map_labels[1]}\n")
        f.write(f"Legend count: {min(7, len(ranked))}\n")
        for r, name in enumerate(ranked[:7]):
            f.write(f"Legend {r + 1}: {use_count[name]}|{name}\n")
        other = ranked[7:]
        f.write(f"Legend other: {sum(use_count[n] for n in other)}|{len(other)}\n")
        for fpath, msg in skipped_error[:20]:
            f.write(f"Unreadable: {os.path.relpath(os.path.abspath(fpath), corpus_root)} ({msg})\n")
        f.write(f"Render time: {duration:.2f}s\n")

    print("[Py] Success. Exiting cleanly.")

if __name__ == "__main__":
    main()