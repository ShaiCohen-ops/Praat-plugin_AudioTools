"""
formant_swarm_granulator.py — Formant Swarm Granulator engine  v1.1

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University

Usage (called by Praat — not directly):
    python formant_swarm_granulator.py \
        --grains      grains.csv \
        --input       input.wav \
        --output      output.wav \
        --stats       stats.txt \
        --mode        vowel_cloud \
        --density     18 \
        --attraction  1.0 \
        --temporal_repulsion 0.9 \
        --density_repulsion 0.7 \
        --pan_spread  1.0 \
        --pitch_drift 0.5 \
        --seed        1

Architecture:
    A — Load grain table + source audio
    B — Build compact resonance feature vectors
    C — Cluster grains into local resonance families
    D — Map grains into a 2D swarm field via principal projection
    E — Walk the field with attraction / repulsion rules
    F — Render overlap-add granular cloud
    G — Write stats report
"""

import argparse
import csv
import math
import os
import sys


def check_dependencies():
    missing = []
    for pkg in ["numpy", "soundfile"]:
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

XFADE_SEC = 0.008
MIN_GRAIN_SEC = 0.020
MAX_GRAIN_SEC = 0.250


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def safe_float(x, default=0.0):
    try:
        return float(x)
    except Exception:
        return default


def robust_z(col):
    med = np.median(col)
    q25 = np.percentile(col, 25)
    q75 = np.percentile(col, 75)
    scale = max(1e-6, q75 - q25)
    return (col - med) / scale


def semitones_to_ratio(st):
    return float(2.0 ** (st / 12.0))


# ─────────────────────────────────────────────────────────────────────────────
# Data model
# ─────────────────────────────────────────────────────────────────────────────

class Grain:
    __slots__ = (
        "grain_id", "start", "duration", "f1", "f2", "f3",
        "bw1", "bw2", "bw3", "pitch", "intensity", "centroid",
        "voiced", "confidence", "cluster", "x", "y"
    )

    def __init__(self, row):
        self.grain_id = int(safe_float(row.get("grain_id", 0), 0))
        self.start = max(0.0, safe_float(row.get("start_time_s", 0.0)))
        self.duration = np.clip(
            safe_float(row.get("duration_s", 0.05), 0.05),
            MIN_GRAIN_SEC, MAX_GRAIN_SEC
        )
        self.f1 = max(0.0, safe_float(row.get("f1_hz", 0.0)))
        self.f2 = max(0.0, safe_float(row.get("f2_hz", 0.0)))
        self.f3 = max(0.0, safe_float(row.get("f3_hz", 0.0)))
        self.bw1 = max(0.0, safe_float(row.get("bw1_hz", 0.0)))
        self.bw2 = max(0.0, safe_float(row.get("bw2_hz", 0.0)))
        self.bw3 = max(0.0, safe_float(row.get("bw3_hz", 0.0)))
        self.pitch = max(0.0, safe_float(row.get("pitch_hz", 0.0)))
        self.intensity = safe_float(row.get("intensity_db", 0.0))
        self.centroid = max(0.0, safe_float(row.get("centroid_hz", 0.0)))
        self.voiced = 1.0 if safe_float(row.get("voiced", 0.0)) > 0.5 else 0.0
        self.confidence = np.clip(safe_float(row.get("confidence", 0.5), 0.5), 0.0, 1.0)
        self.cluster = 0
        self.x = 0.0
        self.y = 0.0


# ─────────────────────────────────────────────────────────────────────────────
# A — Load
# ─────────────────────────────────────────────────────────────────────────────

def load_grains(csv_path):
    grains = []
    with open(csv_path, "r", newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            grains.append(Grain(row))
    if not grains:
        raise RuntimeError("No grains found in CSV")
    return grains


def load_audio(path):
    audio, sr = sf.read(path, always_2d=False)
    return audio.astype(np.float32), int(sr)


# ─────────────────────────────────────────────────────────────────────────────
# B — Feature space
# ─────────────────────────────────────────────────────────────────────────────

def build_feature_matrix(grains):
    f1 = np.array([g.f1 if g.f1 > 0 else np.nan for g in grains], dtype=np.float64)
    f2 = np.array([g.f2 if g.f2 > 0 else np.nan for g in grains], dtype=np.float64)
    f3 = np.array([g.f3 if g.f3 > 0 else np.nan for g in grains], dtype=np.float64)
    bw1 = np.array([g.bw1 for g in grains], dtype=np.float64)
    bw2 = np.array([g.bw2 for g in grains], dtype=np.float64)
    bw3 = np.array([g.bw3 for g in grains], dtype=np.float64)
    inten = np.array([g.intensity for g in grains], dtype=np.float64)
    cent = np.array([g.centroid for g in grains], dtype=np.float64)
    voi = np.array([g.voiced for g in grains], dtype=np.float64)

    for arr in [f1, f2, f3]:
        med = np.nanmedian(arr)
        if np.isnan(med):
            med = 0.0
        arr[np.isnan(arr)] = med

    X = np.column_stack([
        robust_z(f1),
        robust_z(f2),
        robust_z(f3),
        0.40 * robust_z(bw1) + 0.30 * robust_z(bw2) + 0.30 * robust_z(bw3),
        robust_z(inten),
        robust_z(cent),
        voi,
    ]).astype(np.float64)
    return X


# ─────────────────────────────────────────────────────────────────────────────
# C — Clustering / field
# ─────────────────────────────────────────────────────────────────────────────

def assign_clusters(X, k=6, seed=0):
    rng = np.random.default_rng(seed)
    n = len(X)
    k = int(max(2, min(k, n)))
    centers = X[rng.choice(n, size=k, replace=False)].copy()
    labels = np.zeros(n, dtype=np.int32)
    for _ in range(20):
        d = ((X[:, None, :] - centers[None, :, :]) ** 2).sum(axis=2)
        new_labels = np.argmin(d, axis=1)
        if np.array_equal(labels, new_labels):
            break
        labels = new_labels
        for j in range(k):
            mask = labels == j
            if np.any(mask):
                centers[j] = X[mask].mean(axis=0)
            else:
                centers[j] = X[rng.integers(0, n)]
    return labels, centers


def principal_map(X):
    Xc = X - X.mean(axis=0, keepdims=True)
    _, _, Vt = np.linalg.svd(Xc, full_matrices=False)
    Y = Xc @ Vt[:2].T
    if Y.shape[1] < 2:
        Y = np.pad(Y, ((0, 0), (0, 2 - Y.shape[1])))
    std = Y.std(axis=0)
    std[std < 1e-6] = 1.0
    return Y / std


# ─────────────────────────────────────────────────────────────────────────────
# D — Swarm walk
# ─────────────────────────────────────────────────────────────────────────────

def choose_next(i, X, starts, centers, labels, usage, recent, mode,
                attraction, temporal_repulsion, density_repulsion, rng):
    xi = X[i]
    dist = np.sqrt(((X - xi[None, :]) ** 2).sum(axis=1))
    sim = np.exp(-1.2 * dist)

    dt = np.abs(starts - starts[i])
    temporal_penalty = np.exp(-(dt / 0.35))
    crowd_bonus = 1.0 / (1.0 + usage)
    cluster_bonus = (labels == labels[i]).astype(np.float64)

    if mode == "vowel_cloud":
        score = attraction * sim + 0.22 * cluster_bonus + 0.10 * crowd_bonus
    elif mode == "resonance_turbulence":
        score = 0.75 * attraction * sim + 0.45 * rng.random(len(X)) + 0.12 * crowd_bonus
    elif mode == "migration":
        cdist = np.sqrt(((centers[labels] - centers[labels[i]]) ** 2).sum(axis=1))
        score = 0.55 * attraction * sim + 0.30 * np.exp(-cdist) + 0.10 * crowd_bonus
    elif mode == "counterpoint":
        voiced_match = (X[:, -1] == X[i, -1]).astype(np.float64)
        score = 0.70 * attraction * sim + 0.20 * voiced_match + 0.10 * crowd_bonus
    else:
        score = attraction * sim + 0.15 * crowd_bonus

    score -= temporal_repulsion * temporal_penalty
    score -= density_repulsion * usage / max(1.0, usage.mean() + 1e-9)

    if recent:
        score[np.array(recent, dtype=np.int32)] *= 0.05

    score[i] *= 0.15
    score = np.maximum(score, 1e-8)
    probs = score / score.sum()
    return int(rng.choice(len(X), p=probs))


def build_schedule(grains, X, labels, centers, density_gps, attraction,
                   temporal_repulsion, density_repulsion, seed, mode,
                   pitch_drift_st):
    rng = np.random.default_rng(seed)
    n = len(grains)
    starts = np.array([g.start for g in grains], dtype=np.float64)
    positions = principal_map(X)
    for g, pos, lab in zip(grains, positions, labels):
        g.x = float(pos[0])
        g.y = float(pos[1])
        g.cluster = int(lab)

    source_dur = max(g.start + g.duration for g in grains)
    out_dur = max(2.0, min(8.0 * 60.0, source_dur * 1.35))
    n_events = max(8, int(round(out_dur * max(1.0, density_gps))))

    usage = np.zeros(n, dtype=np.float64)
    recent = []
    i = int(rng.integers(0, n))
    t = 0.0
    schedule = []

    for _ in range(n_events):
        g = grains[i]
        local_density = np.sum(labels == labels[i]) / float(n)
        dur_scale = 1.0 + 0.18 * (g.confidence - 0.5) + 0.08 * local_density
        out_dur_i = np.clip(g.duration * dur_scale, MIN_GRAIN_SEC, MAX_GRAIN_SEC)
        gap = max(0.008, 1.0 / max(1.0, density_gps))
        gap *= 0.85 + 0.35 * rng.random()

        pan = np.tanh(0.9 * g.x + 0.15 * rng.normal())
        pitch_st = np.clip(
            pitch_drift_st * (0.65 * g.y + 0.35 * rng.normal()),
            -pitch_drift_st, pitch_drift_st
        )
        gain = np.clip(
            0.16 + 0.05 * g.voiced + 0.02 * g.confidence + 0.015 * rng.normal(),
            0.04, 0.30
        )

        schedule.append({
            "out_start": t,
            "out_dur": float(out_dur_i),
            "grain_index": i,
            "pan": float(pan),
            "pitch_st": float(pitch_st),
            "gain": float(gain),
        })
        usage[i] += 1.0
        recent.append(i)
        recent = recent[-8:]
        t += gap
        i = choose_next(
            i, X, starts, centers, labels, usage, recent, mode,
            attraction, temporal_repulsion, density_repulsion, rng
        )
    return schedule


# ─────────────────────────────────────────────────────────────────────────────
# E — Rendering
# ─────────────────────────────────────────────────────────────────────────────

def extract_grain(audio, sr, start_s, dur_s):
    n = len(audio)
    s = max(0, min(n - 1, int(round(start_s * sr))))
    e = max(s + 1, min(n, int(round((start_s + dur_s) * sr))))
    return audio[s:e].copy()


def fade_clip(x, sr):
    x = x.astype(np.float32, copy=True)
    fade = min(max(4, int(round(XFADE_SEC * sr))), max(4, len(x) // 4))
    if fade >= 2:
        ramp_in = np.linspace(0.0, 1.0, fade, dtype=np.float32)
        ramp_out = np.linspace(1.0, 0.0, fade, dtype=np.float32)
        if x.ndim == 1:
            x[:fade] *= ramp_in
            x[-fade:] *= ramp_out
        else:
            x[:fade, :] *= ramp_in[:, None]
            x[-fade:, :] *= ramp_out[:, None]
    return x


def resample_linear(x, out_len):
    if out_len <= 1:
        return x[:1].copy()
    if len(x) == out_len:
        return x.astype(np.float32, copy=True)
    t_old = np.linspace(0.0, 1.0, len(x))
    t_new = np.linspace(0.0, 1.0, out_len)
    if x.ndim == 1:
        return np.interp(t_new, t_old, x).astype(np.float32)
    y = np.zeros((out_len, x.shape[1]), dtype=np.float32)
    for ch in range(x.shape[1]):
        y[:, ch] = np.interp(t_new, t_old, x[:, ch])
    return y


def to_stereo(x):
    if x.ndim == 1:
        return np.column_stack([x, x]).astype(np.float32)
    if x.shape[1] == 1:
        return np.repeat(x, 2, axis=1).astype(np.float32)
    return x[:, :2].astype(np.float32)


def render_schedule(audio, sr, grains, schedule, pan_spread):
    stereo = to_stereo(audio)
    total_end = 0.0
    for ev in schedule:
        total_end = max(total_end, ev["out_start"] + ev["out_dur"])
    out_len = int(math.ceil((total_end + 0.25) * sr))
    out = np.zeros((out_len, 2), dtype=np.float32)

    for ev in schedule:
        g = grains[ev["grain_index"]]
        clip = extract_grain(stereo, sr, g.start, g.duration)
        pitch_ratio = semitones_to_ratio(ev["pitch_st"])
        target_len = max(8, int(round(len(clip) / max(0.5, min(2.0, pitch_ratio)))))
        clip = resample_linear(clip, target_len)
        dur_len = max(8, int(round(ev["out_dur"] * sr)))
        clip = resample_linear(clip, dur_len)
        clip = fade_clip(clip, sr)

        pan = np.clip(ev["pan"] * pan_spread, -1.0, 1.0)
        left = math.sqrt(0.5 * (1.0 - pan))
        right = math.sqrt(0.5 * (1.0 + pan))
        clip[:, 0] *= ev["gain"] * left
        clip[:, 1] *= ev["gain"] * right

        s = int(round(ev["out_start"] * sr))
        e = min(len(out), s + len(clip))
        out[s:e] += clip[:e - s]

    # ── Per-channel RMS balance ──────────────────────────────────────────
    # Granular panning causes channels to accumulate at different levels.
    # Balance them so both channels share the same RMS, then restore the
    # combined (mean-channel) RMS to match the source audio.
    rms_src_mono = float(np.sqrt(np.mean(stereo ** 2)))

    rms_ch = np.sqrt(np.mean(out ** 2, axis=0))          # [rms_L, rms_R]
    rms_ch = np.where(rms_ch < 1e-9, 1e-9, rms_ch)
    rms_mean = float(np.mean(rms_ch))

    # Scale each channel to the mean channel RMS (balance)
    for ch in range(2):
        out[:, ch] *= rms_mean / rms_ch[ch]

    # Scale combined output to match source RMS
    rms_out_now = float(np.sqrt(np.mean(out ** 2)))
    if rms_out_now > 1e-9 and rms_src_mono > 1e-9:
        out *= rms_src_mono / rms_out_now

    rms_out_final = float(np.sqrt(np.mean(out ** 2)))

    # Final peak-limit to ±1 with 0.5 dB headroom
    peak = float(np.max(np.abs(out))) if len(out) else 0.0
    if peak > 0.944:          # 0.944 ≈ -0.5 dBFS
        out *= 0.944 / peak
    return out, rms_src_mono, rms_out_final


# ─────────────────────────────────────────────────────────────────────────────
# F — Stats
# ─────────────────────────────────────────────────────────────────────────────

def write_stats(path, grains, schedule, mode, labels, rms_in=0.0, rms_out=0.0):
    with open(path, "w", encoding="utf-8") as f:
        f.write("mode=%s\n" % mode)
        f.write("grains=%d\n" % len(grains))
        f.write("scheduled_events=%d\n" % len(schedule))
        f.write("clusters=%d\n" % len(set(int(x) for x in labels)))
        voiced = sum(g.voiced for g in grains)
        f.write("voiced_ratio=%.4f\n" % (voiced / max(1, len(grains))))
        f1_vals = [g.f1 for g in grains if g.f1 > 0]
        f2_vals = [g.f2 for g in grains if g.f2 > 0]
        f3_vals = [g.f3 for g in grains if g.f3 > 0]
        f.write("mean_f1_hz=%.2f\n" % (np.mean(f1_vals) if f1_vals else 0.0))
        f.write("mean_f2_hz=%.2f\n" % (np.mean(f2_vals) if f2_vals else 0.0))
        f.write("mean_f3_hz=%.2f\n" % (np.mean(f3_vals) if f3_vals else 0.0))
        f.write("rms_in=%.6f\n" % rms_in)
        f.write("rms_out=%.6f\n" % rms_out)


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Formant Swarm Granulator — resonance-organised grain swarm"
    )
    parser.add_argument("--grains", required=True)
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--stats", required=True)
    parser.add_argument("--mode", default="vowel_cloud",
                        choices=["vowel_cloud", "resonance_turbulence", "migration", "counterpoint"])
    parser.add_argument("--density", type=float, default=18.0)
    parser.add_argument("--attraction", type=float, default=1.0)
    parser.add_argument("--temporal_repulsion", type=float, default=0.9)
    parser.add_argument("--density_repulsion", type=float, default=0.7)
    parser.add_argument("--pan_spread", type=float, default=1.0)
    parser.add_argument("--pitch_drift", type=float, default=0.5)
    parser.add_argument("--seed", type=int, default=1)
    args = parser.parse_args()

    args.density = max(1.0, args.density)
    args.attraction = max(0.0, args.attraction)
    args.temporal_repulsion = max(0.0, args.temporal_repulsion)
    args.density_repulsion = max(0.0, args.density_repulsion)
    args.pan_spread = float(np.clip(args.pan_spread, 0.0, 1.0))
    args.pitch_drift = max(0.0, args.pitch_drift)

    print("[Py 1/5] Loading grain table + audio...")
    grains = load_grains(args.grains)
    audio, sr = load_audio(args.input)
    print("    Grains: %d | SR=%d" % (len(grains), sr))

    print("[Py 2/5] Building resonance feature space...")
    X = build_feature_matrix(grains)

    print("[Py 3/5] Clustering resonance families...")
    labels, centers = assign_clusters(X, k=6, seed=args.seed)

    print("[Py 4/5] Swarm walk: %s..." % args.mode)
    schedule = build_schedule(
        grains, X, labels, centers,
        density_gps=args.density,
        attraction=args.attraction,
        temporal_repulsion=args.temporal_repulsion,
        density_repulsion=args.density_repulsion,
        seed=args.seed,
        mode=args.mode,
        pitch_drift_st=args.pitch_drift,
    )

    print("[Py 5/5] Rendering + stats...")
    out, rms_in, rms_out = render_schedule(audio, sr, grains, schedule, pan_spread=args.pan_spread)
    sf.write(args.output, out, sr)
    write_stats(args.stats, grains, schedule, args.mode, labels, rms_in=rms_in, rms_out=rms_out)
    print("OK: %s" % args.output)


if __name__ == "__main__":
    main()
