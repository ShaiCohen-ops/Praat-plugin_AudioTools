"""
formant_swarm_granulator.py - Formant Swarm Granulator engine v1.2 (2026)
Validity-aware resonance feature engine for Praat AudioTools.

Key change from v1.1:
- Invalid / structurally implausible formant measurements are never filled with
  a median vowel and presented to the swarm as real resonances.
- Formant dimensions are built from reliable grains only. Invalid grains sit at
  the neutral centre of those dimensions and carry an explicit low-weight
  validity feature.
- If reliable formants are too sparse, formant dimensions are disabled and the
  swarm falls back to intensity / centroid / voiced organisation.
"""

import argparse
import csv
import math
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
        print("Install: pip install " + " ".join(missing), file=sys.stderr)
        sys.exit(1)


check_dependencies()
import numpy as np
import soundfile as sf

XFADE_SEC = 0.008
MIN_GRAIN_SEC = 0.020
MAX_GRAIN_SEC = 0.250
MIN_RELIABLE_RATIO = 0.15
MIN_RELIABLE_GRAINS = 5
MIN_RESONANCE_CONTRAST_DB = 0.8


def safe_float(x, default=0.0):
    try:
        return float(x)
    except Exception:
        return default


def robust_z(col):
    col = np.asarray(col, dtype=np.float64)
    med = float(np.median(col))
    q25 = float(np.percentile(col, 25))
    q75 = float(np.percentile(col, 75))
    scale = max(1e-6, q75 - q25)
    return (col - med) / scale


def robust_z_valid(values, valid_mask):
    """Robust z-score from valid measurements only; invalid rows map to 0."""
    values = np.asarray(values, dtype=np.float64)
    valid_mask = np.asarray(valid_mask, dtype=bool)
    out = np.zeros_like(values, dtype=np.float64)
    vv = values[valid_mask]
    if len(vv) < 2:
        return out
    med = float(np.median(vv))
    q25 = float(np.percentile(vv, 25))
    q75 = float(np.percentile(vv, 75))
    scale = max(1e-6, q75 - q25)
    out[valid_mask] = (values[valid_mask] - med) / scale
    return np.clip(out, -5.0, 5.0)


def semitones_to_ratio(st):
    return float(2.0 ** (st / 12.0))


class Grain:
    __slots__ = (
        "grain_id", "start", "duration", "f1", "f2", "f3",
        "bw1", "bw2", "bw3", "pitch", "intensity", "centroid",
        "voiced", "confidence", "formant_valid", "formant_span", "resonance_contrast",
        "cluster", "x", "y"
    )

    def __init__(self, row):
        self.grain_id = int(safe_float(row.get("grain_id", 0), 0))
        self.start = max(0.0, safe_float(row.get("start_time_s", 0.0)))
        self.duration = float(np.clip(
            safe_float(row.get("duration_s", 0.05), 0.05),
            MIN_GRAIN_SEC, MAX_GRAIN_SEC
        ))
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
        self.confidence = float(np.clip(safe_float(row.get("confidence", 0.0), 0.0), 0.0, 1.0))
        explicit_valid = safe_float(row.get("formant_valid", -1.0), -1.0)
        if explicit_valid >= 0:
            self.formant_valid = 1.0 if explicit_valid > 0.5 else 0.0
        else:
            # Backward-compatible conservative fallback for old CSVs.
            self.formant_valid = 1.0 if (
                self.f1 > 0 and self.f2 > self.f1 + 100 and self.f3 > self.f2 + 120
                and (self.f3 - self.f1) >= max(350.0, 1.25 * self.pitch if self.pitch > 0 else 350.0)
            ) else 0.0
        self.formant_span = max(0.0, safe_float(row.get("formant_span_hz", self.f3 - self.f1), 0.0))
        self.resonance_contrast = safe_float(row.get("resonance_contrast_db", 0.0), 0.0)
        if not self.formant_valid:
            self.confidence = min(self.confidence, 0.20)
        self.cluster = 0
        self.x = 0.0
        self.y = 0.0


def load_grains(csv_path):
    grains = []
    with open(csv_path, "r", newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            grains.append(Grain(row))
    if not grains:
        raise RuntimeError("No grains found in CSV")
    return grains


def load_audio(path):
    audio, sr = sf.read(path, always_2d=False)
    return audio.astype(np.float32), int(sr)


def build_feature_matrix(grains, min_reliable_ratio=MIN_RELIABLE_RATIO, min_resonance_contrast=MIN_RESONANCE_CONTRAST_DB):
    n = len(grains)
    valid = np.array([g.formant_valid > 0.5 for g in grains], dtype=bool)
    conf = np.array([g.confidence for g in grains], dtype=np.float64)
    reliable_count = int(valid.sum())
    reliable_ratio = reliable_count / float(max(1, n))
    contrast = np.array([g.resonance_contrast for g in grains], dtype=np.float64)
    median_contrast = float(np.median(contrast[valid])) if reliable_count else 0.0
    formant_active = (
        reliable_count >= MIN_RELIABLE_GRAINS
        and reliable_ratio >= min_reliable_ratio
        and median_contrast >= min_resonance_contrast
    )

    inten = np.array([g.intensity for g in grains], dtype=np.float64)
    cent = np.array([g.centroid for g in grains], dtype=np.float64)
    voi = np.array([g.voiced for g in grains], dtype=np.float64)

    columns = []
    names = []

    if formant_active:
        f1 = np.array([g.f1 for g in grains], dtype=np.float64)
        f2 = np.array([g.f2 for g in grains], dtype=np.float64)
        f3 = np.array([g.f3 for g in grains], dtype=np.float64)
        bw1 = np.array([g.bw1 for g in grains], dtype=np.float64)
        bw2 = np.array([g.bw2 for g in grains], dtype=np.float64)
        bw3 = np.array([g.bw3 for g in grains], dtype=np.float64)
        span = np.array([g.formant_span for g in grains], dtype=np.float64)

        # Only reliable grains define the coordinate system. Invalid grains are
        # neutral in formant space instead of becoming a median/canonical vowel.
        contrast_weight = np.clip((contrast + 0.5) / 3.0, 0.15, 1.0)
        reliability = np.where(valid, (0.35 + 0.65 * conf) * contrast_weight, 0.0)
        zf1 = robust_z_valid(f1, valid) * reliability
        zf2 = robust_z_valid(f2, valid) * reliability
        zf3 = robust_z_valid(f3, valid) * reliability
        zbw = (
            0.40 * robust_z_valid(bw1, valid)
            + 0.30 * robust_z_valid(bw2, valid)
            + 0.30 * robust_z_valid(bw3, valid)
        ) * reliability
        zspan = robust_z_valid(span, valid) * reliability

        columns += [zf1, zf2, zf3, 0.55 * zbw, 0.35 * zspan]
        names += ["F1", "F2", "F3", "bandwidth", "span"]
        # Mild validity cue prevents an invalid grain from looking exactly like
        # a median valid vowel, without letting validity dominate clustering.
        columns.append(0.25 * (valid.astype(np.float64) - reliable_ratio))
        names.append("formant_valid")

    columns += [robust_z(inten), robust_z(cent), voi]
    names += ["intensity", "centroid", "voiced"]

    X = np.column_stack(columns).astype(np.float64)
    # Remove numerically constant columns; they carry no similarity information.
    keep = np.std(X, axis=0) > 1e-9
    # Always retain voiced as final column because counterpoint mode addresses it.
    keep[-1] = True
    X = X[:, keep]
    names = [name for name, use in zip(names, keep) if use]
    return X, {
        "formant_active": bool(formant_active),
        "reliable_count": reliable_count,
        "reliable_ratio": reliable_ratio,
        "mean_confidence": float(np.mean(conf[valid])) if reliable_count else 0.0,
        "median_resonance_contrast_db": median_contrast,
        "feature_names": names,
    }


def assign_clusters(X, k=6, seed=0):
    rng = np.random.default_rng(seed)
    n = len(X)
    if n == 1:
        return np.zeros(1, dtype=np.int32), X.copy()
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
    if len(X) <= 1:
        return np.zeros((len(X), 2), dtype=np.float64)
    Xc = X - X.mean(axis=0, keepdims=True)
    _, _, vt = np.linalg.svd(Xc, full_matrices=False)
    dims = min(2, vt.shape[0])
    y = Xc @ vt[:dims].T
    if y.shape[1] < 2:
        y = np.pad(y, ((0, 0), (0, 2 - y.shape[1])))
    std = y.std(axis=0)
    std[std < 1e-6] = 1.0
    return y / std


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
    return int(rng.choice(len(X), p=score / score.sum()))


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
        dur_scale = 1.0 + 0.14 * (g.confidence - 0.5) + 0.08 * local_density
        out_dur_i = float(np.clip(g.duration * dur_scale, MIN_GRAIN_SEC, MAX_GRAIN_SEC))
        gap = max(0.008, 1.0 / max(1.0, density_gps))
        gap *= 0.85 + 0.35 * rng.random()
        pan = np.tanh(0.9 * g.x + 0.15 * rng.normal())
        pitch_st = float(np.clip(
            pitch_drift_st * (0.65 * g.y + 0.35 * rng.normal()),
            -pitch_drift_st, pitch_drift_st
        ))
        # Invalid formants do not mute a grain; they simply do not receive the
        # small confidence bonus that reliable resonance descriptors do.
        gain = float(np.clip(
            0.16 + 0.05 * g.voiced + 0.018 * g.confidence + 0.015 * rng.normal(),
            0.04, 0.30
        ))
        schedule.append({
            "out_start": t,
            "out_dur": out_dur_i,
            "grain_index": i,
            "pan": float(pan),
            "pitch_st": pitch_st,
            "gain": gain,
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
    if x.shape[1] == 2:
        return x.astype(np.float32, copy=True)

    # Preserve every input channel when collapsing multichannel material to the
    # stereo swarm field. Channels are placed at fixed equal-power pan
    # positions from left to right instead of silently dropping channels 3+.
    n_ch = x.shape[1]
    out = np.zeros((len(x), 2), dtype=np.float32)
    pans = np.linspace(-1.0, 1.0, n_ch)
    norm = math.sqrt(max(1.0, n_ch / 2.0))
    for ch, pan in enumerate(pans):
        left = math.sqrt(0.5 * (1.0 - float(pan)))
        right = math.sqrt(0.5 * (1.0 + float(pan)))
        out[:, 0] += x[:, ch] * (left / norm)
        out[:, 1] += x[:, ch] * (right / norm)
    return out


def render_schedule(audio, sr, grains, schedule, pan_spread):
    stereo = to_stereo(audio)
    total_end = max((ev["out_start"] + ev["out_dur"] for ev in schedule), default=0.0)
    out_len = int(math.ceil((total_end + 0.25) * sr))
    out = np.zeros((out_len, 2), dtype=np.float32)

    for ev in schedule:
        g = grains[ev["grain_index"]]
        clip = extract_grain(stereo, sr, g.start, g.duration)
        pitch_ratio = semitones_to_ratio(ev["pitch_st"])
        target_len = max(8, int(round(len(clip) / max(0.5, min(2.0, pitch_ratio)))))
        clip = resample_linear(clip, target_len)
        clip = resample_linear(clip, max(8, int(round(ev["out_dur"] * sr))))
        clip = fade_clip(clip, sr)
        pan = float(np.clip(ev["pan"] * pan_spread, -1.0, 1.0))
        left = math.sqrt(0.5 * (1.0 - pan))
        right = math.sqrt(0.5 * (1.0 + pan))
        clip[:, 0] *= ev["gain"] * left
        clip[:, 1] *= ev["gain"] * right
        s = int(round(ev["out_start"] * sr))
        e = min(len(out), s + len(clip))
        out[s:e] += clip[:e - s]

    rms_src = float(np.sqrt(np.mean(stereo ** 2)))
    rms_ch = np.sqrt(np.mean(out ** 2, axis=0)) if len(out) else np.ones(2)
    rms_ch = np.where(rms_ch < 1e-9, 1e-9, rms_ch)
    rms_mean = float(np.mean(rms_ch))
    for ch in range(2):
        out[:, ch] *= rms_mean / rms_ch[ch]
    rms_out_now = float(np.sqrt(np.mean(out ** 2))) if len(out) else 0.0
    if rms_out_now > 1e-9 and rms_src > 1e-9:
        out *= rms_src / rms_out_now
    rms_out_final = float(np.sqrt(np.mean(out ** 2))) if len(out) else 0.0
    peak = float(np.max(np.abs(out))) if len(out) else 0.0
    if peak > 0.944:
        out *= 0.944 / peak
        rms_out_final = float(np.sqrt(np.mean(out ** 2)))
    return out, rms_src, rms_out_final


def write_stats(path, grains, schedule, mode, labels, feature_meta, rms_in=0.0, rms_out=0.0):
    valid = [g for g in grains if g.formant_valid > 0.5] if feature_meta["formant_active"] else []
    with open(path, "w", encoding="utf-8") as f:
        f.write("mode=%s\n" % mode)
        f.write("grains=%d\n" % len(grains))
        f.write("scheduled_events=%d\n" % len(schedule))
        f.write("clusters=%d\n" % len(set(int(x) for x in labels)))
        f.write("voiced_ratio=%.4f\n" % (sum(g.voiced for g in grains) / max(1, len(grains))))
        f.write("formant_features_active=%d\n" % (1 if feature_meta["formant_active"] else 0))
        f.write("formant_valid_grains=%d\n" % feature_meta["reliable_count"])
        f.write("formant_valid_ratio=%.4f\n" % feature_meta["reliable_ratio"])
        f.write("mean_formant_confidence=%.4f\n" % feature_meta["mean_confidence"])
        f.write("median_resonance_contrast_db=%.4f\n" % feature_meta["median_resonance_contrast_db"])
        f.write("feature_dimensions=%s\n" % ",".join(feature_meta["feature_names"]))
        f.write("mean_f1_hz=%.2f\n" % (np.mean([g.f1 for g in valid]) if valid else 0.0))
        f.write("mean_f2_hz=%.2f\n" % (np.mean([g.f2 for g in valid]) if valid else 0.0))
        f.write("mean_f3_hz=%.2f\n" % (np.mean([g.f3 for g in valid]) if valid else 0.0))
        f.write("rms_in=%.6f\n" % rms_in)
        f.write("rms_out=%.6f\n" % rms_out)


def main():
    parser = argparse.ArgumentParser(description="Formant Swarm Granulator - validity-aware resonance swarm")
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
    parser.add_argument("--min_formant_ratio", type=float, default=MIN_RELIABLE_RATIO)
    parser.add_argument("--min_resonance_contrast", type=float, default=MIN_RESONANCE_CONTRAST_DB)
    args = parser.parse_args()

    args.density = max(1.0, args.density)
    args.attraction = max(0.0, args.attraction)
    args.temporal_repulsion = max(0.0, args.temporal_repulsion)
    args.density_repulsion = max(0.0, args.density_repulsion)
    args.pan_spread = float(np.clip(args.pan_spread, 0.0, 1.0))
    args.pitch_drift = max(0.0, args.pitch_drift)
    args.min_formant_ratio = float(np.clip(args.min_formant_ratio, 0.0, 1.0))
    args.min_resonance_contrast = max(-20.0, args.min_resonance_contrast)

    print("[Py 1/5] Loading grain table + audio...")
    grains = load_grains(args.grains)
    audio, sr = load_audio(args.input)
    print("    Grains: %d | SR=%d" % (len(grains), sr))

    print("[Py 2/5] Building validity-aware feature space...")
    X, feature_meta = build_feature_matrix(grains, min_reliable_ratio=args.min_formant_ratio, min_resonance_contrast=args.min_resonance_contrast)
    if feature_meta["formant_active"]:
        print("    Formants ACTIVE: %d/%d reliable (%.1f%%), mean confidence %.3f" % (
            feature_meta["reliable_count"], len(grains), 100.0 * feature_meta["reliable_ratio"],
            feature_meta["mean_confidence"]))
        print("    Median F2/F3 resonance contrast: %.3f dB" % feature_meta["median_resonance_contrast_db"])
    else:
        print("    Formants DISABLED: %d/%d reliable (%.1f%%); spectral/dynamic fallback" % (
            feature_meta["reliable_count"], len(grains), 100.0 * feature_meta["reliable_ratio"]))
        print("    Median F2/F3 resonance contrast: %.3f dB" % feature_meta["median_resonance_contrast_db"])
    print("    Features: " + ", ".join(feature_meta["feature_names"]))

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
    write_stats(args.stats, grains, schedule, args.mode, labels, feature_meta, rms_in=rms_in, rms_out=rms_out)
    print("OK: %s" % args.output)


if __name__ == "__main__":
    main()
