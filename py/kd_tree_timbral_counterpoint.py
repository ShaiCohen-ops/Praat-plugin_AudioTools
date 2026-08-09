"""
kd_tree_timbral_counterpoint.py — Latent Timbral Counterpoint Engine

Part of Praat AudioTools plugin.
Calculates N-dimensional timbral distances to generate contrapuntal layers.
"""

import argparse
import csv
import math
import os
import random
import sys


FEATURE_COLUMNS = [
    "mfcc1", "mfcc2", "mfcc3", "mfcc4", "mfcc5", "mfcc6",
    "centroid", "pitch", "intensity", "hnr", "zcr",
]


def fail(message):
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def check_dependencies():
    try:
        import numpy  # noqa: F401
    except ImportError:
        fail("numpy is required. Install it with: pip install numpy")


def parse_int_list(text, label):
    try:
        values = [int(item.strip()) for item in text.split(",") if item.strip()]
    except ValueError as exc:
        fail(f"{label} must be a comma-separated list of integers ({exc}).")
    if not values:
        fail(f"{label} must contain at least one integer.")
    return values


def parse_float_list(text, label, expected_count=None):
    try:
        values = [float(item.strip()) for item in text.split(",") if item.strip()]
    except ValueError as exc:
        fail(f"{label} must be a comma-separated list of numbers ({exc}).")
    if not values:
        fail(f"{label} must contain at least one number.")
    if expected_count is not None and len(values) != expected_count:
        fail(f"{label} must contain exactly {expected_count} values; got {len(values)}.")
    if any(not math.isfinite(value) for value in values):
        fail(f"{label} contains a non-finite value.")
    return values


def load_feature_csv(path, label):
    if not os.path.isfile(path):
        fail(f"{label} CSV not found: {path}")

    rows = []
    features = []
    try:
        with open(path, "r", encoding="utf-8", newline="") as handle:
            reader = csv.DictReader(handle)
            if reader.fieldnames is None:
                fail(f"{label} CSV has no header: {path}")

            missing = [name for name in FEATURE_COLUMNS if name not in reader.fieldnames]
            if missing:
                fail(f"{label} CSV is missing columns: {', '.join(missing)}")

            for line_number, row in enumerate(reader, start=2):
                try:
                    vector = [float(row[name]) for name in FEATURE_COLUMNS]
                except (TypeError, ValueError) as exc:
                    fail(f"Invalid numeric feature in {label} CSV at line {line_number}: {exc}")

                if any(not math.isfinite(value) for value in vector):
                    fail(f"Non-finite feature in {label} CSV at line {line_number}.")

                rows.append(row)
                features.append(vector)
    except OSError as exc:
        fail(f"Could not read {label} CSV '{path}': {exc}")

    if not rows:
        fail(f"{label} CSV contains no feature rows: {path}")

    return rows, features


def main():
    check_dependencies()
    import numpy as np

    parser = argparse.ArgumentParser()
    parser.add_argument("target_csv")
    parser.add_argument("corpus_csv")
    parser.add_argument("match_csv")
    parser.add_argument("--voices", type=int, default=4)
    parser.add_argument("--ranks", type=str, default="1,3,8,20")
    parser.add_argument("--weights", type=str, default="1,1,1,1,1")
    parser.add_argument("--randomness", type=float, default=0.2)
    parser.add_argument("--rep_penalty", type=int, default=1)
    args = parser.parse_args()

    if args.voices < 1:
        fail("--voices must be at least 1.")
    if not math.isfinite(args.randomness) or not 0.0 <= args.randomness <= 1.0:
        fail("--randomness must be between 0 and 1.")
    if args.rep_penalty not in (0, 1):
        fail("--rep_penalty must be 0 or 1.")

    ranks = parse_int_list(args.ranks, "--ranks")
    if any(rank < 1 for rank in ranks):
        fail("All --ranks values must be positive integers.")
    if len(ranks) < args.voices:
        ranks += [ranks[-1]] * (args.voices - len(ranks))

    weights = parse_float_list(args.weights, "--weights", expected_count=5)
    if any(weight < 0 for weight in weights):
        fail("All --weights values must be non-negative.")
    if all(weight == 0 for weight in weights):
        fail("At least one feature weight must be greater than zero.")

    c_data, c_features = load_feature_csv(args.corpus_csv, "Corpus")
    t_data, t_features = load_feature_csv(args.target_csv, "Target")

    X_c = np.asarray(c_features, dtype=float)
    X_t = np.asarray(t_features, dtype=float)

    w_mfcc, w_pitch, w_cent, w_int, w_hnr = weights
    feat_weights = np.asarray([
        w_mfcc, w_mfcc, w_mfcc, w_mfcc, w_mfcc, w_mfcc,
        w_cent, w_pitch, w_int, w_hnr, w_hnr,
    ], dtype=float)

    # Standardize in corpus space. Constant dimensions receive unit scale so
    # they contribute zero distance without creating infinities/NaNs.
    means = np.mean(X_c, axis=0)
    stds = np.std(X_c, axis=0)
    stds = np.where(stds < 1e-8, 1.0, stds)
    X_c_w = ((X_c - means) / stds) * feat_weights
    X_t_w = ((X_t - means) / stds) * feat_weights

    try:
        from scipy.spatial import cKDTree
        tree = cKDTree(X_c_w)
    except ImportError:
        tree = None

    matches = []
    used_indices = []

    for t_idx, t_row in enumerate(t_data):
        for v_idx in range(args.voices):
            rank_t = ranks[v_idx]
            shift = int(rank_t * args.randomness)
            actual_rank = max(1, rank_t + random.randint(-shift, shift))

            # Search beyond the desired rank when repetition avoidance is on,
            # but never request more neighbours than the corpus contains.
            extra = 30 if args.rep_penalty else 5
            k_search = min(len(X_c_w), max(1, actual_rank + extra))

            if tree is not None:
                dists, inds = tree.query(X_t_w[t_idx], k=k_search)
                if k_search == 1:
                    dists, inds = [float(dists)], [int(inds)]
            else:
                diff = X_c_w - X_t_w[t_idx]
                d2 = np.sum(diff ** 2, axis=1)
                inds = np.argsort(d2)[:k_search]
                dists = np.sqrt(d2[inds])

            # Fallback to the farthest candidate in the search window if
            # repetition filtering removes every earlier candidate.
            chosen_c_idx = int(inds[-1])
            chosen_dist = float(dists[-1])
            curr_rank = 1

            for i, raw_c_idx in enumerate(inds):
                c_idx = int(raw_c_idx)
                if args.rep_penalty and c_idx in used_indices[-20:]:
                    continue
                if curr_rank >= actual_rank:
                    chosen_c_idx = c_idx
                    chosen_dist = float(dists[i])
                    break
                curr_rank += 1

            used_indices.append(chosen_c_idx)
            c_row = c_data[chosen_c_idx]

            if v_idx == 0:
                gain, pan, delay = 0.9, 0.0, 0.0
            elif v_idx == 1:
                pan_val = 0.5 if t_idx % 2 == 0 else -0.5
                gain, pan, delay = 0.65, pan_val, 20.0
            elif v_idx == 2:
                pan_val = 0.8 if t_idx % 2 != 0 else -0.8
                gain, pan, delay = 0.45, pan_val, 45.0
            else:
                gain, pan, delay = 0.30, random.uniform(-1.0, 1.0), 80.0

            mfcc_distance = float(np.linalg.norm(
                X_c_w[chosen_c_idx, :6] - X_t_w[t_idx, :6]
            ))

            matches.append({
                "target_grain_index": t_idx + 1,
                "target_start_time": t_row["start_time"],
                "target_end_time": t_row["end_time"],
                "voice_number": v_idx + 1,
                "neighbor_rank": actual_rank,
                "selected_corpus_file": c_row["file_path"],
                "selected_corpus_start_time": c_row["start_time"],
                "selected_corpus_end_time": c_row["end_time"],
                "distance": round(chosen_dist, 4),
                "pitch_mean": c_row["pitch"],
                "intensity_mean": c_row["intensity"],
                "spectral_centroid": c_row["centroid"],
                "hnr": c_row["hnr"],
                "mfcc_distance": round(mfcc_distance, 4),
                "final_gain": gain,
                "pan_position": round(pan, 3),
                "delay_ms": delay,
            })

    if not matches:
        fail("No matches were generated.")

    try:
        with open(args.match_csv, "w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=matches[0].keys())
            writer.writeheader()
            writer.writerows(matches)
    except OSError as exc:
        fail(f"Could not write match CSV '{args.match_csv}': {exc}")


if __name__ == "__main__":
    main()
