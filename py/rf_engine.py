#!/usr/bin/env python3
# ==========================================================================
# rf_engine.py -- Random Forest Concatenative Synthesis engine
#
# Part of Praat AudioTools plugin
# Author: Shai Cohen, Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026)
# License: MIT
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# v0.5 experimental:
#   - Activity-aware selection: silence is scheduled, not accidentally preferred.
#   - Source-contiguous microphrases replace isolated per-hop jumps.
#   - Corpus-neighborhood novelty penalty and controllable feature weighting.
#   - Unspecified MFCC goals follow the RF prediction instead of corpus zero.
#   - Chronologically held-out evaluation with a leakage guard.
#   - Offline optional trajectory rendering for energy and spectral tilt.
#   - Backwards-compatible v0.4 command-line flags and output stats.
#   - New tuning flags for Python and the v0.5 experimental Praat form.
#
# v0.4:
#   - Calibrates Repeat penalty to corpus-scale pairwise distance so it remains effective with heavily overlapping grains.
#   - Applies edge fades after final length trimming so arbitrary target durations end cleanly.
#   - Uses the strongest real source channel for multichannel analysis instead of fold-down.
#   - Reports repeat-scale and immediate-repeat diagnostics.
#
# v0.3:
#   - Adds optional global RMS level matching to the source after OLA and before Safety.
#   - Caps upward RMS compensation at +12 dB and reports the applied gain.
#   - Keeps all v0.2 multichannel, feature, RF-diagnostic and performance fixes.
#
# v0.2:
#   - Preserves all source channels while analysing a cancellation-safe mono fold.
#   - Reuses one STFT for centroid, flatness and MFCC extraction.
#   - Adapts mel-band count to short FFTs to avoid empty mel filters.
#   - Serialises single-state RF prediction for speed and deterministic tie-breaking.
#   - Adds OOB skill vs persistence; raw OOB R^2 is labelled overlap-biased.
#   - Renames pitch_descent to spectral_descent (legacy alias still accepted).
#   - Removes forced 0.95 peak normalisation; adds attenuation-only safety ceiling.
#   - Dependency failures are written to the engine log for the Praat front end.
#
# Usage (normally invoked by Praat_RF_Concatenative.praat, not by hand):
#
#   python rf_engine.py --input in.wav --output out.wav
#                       --stats stats.txt --log log.txt
#                       --target-duration 10.0
#                       --frame-ms 100 --hop-ms 25
#                       --trajectory crescendo_brightening
#                       --trees 100 --max-depth 15 --lookahead 1
#                       --traj-weight 0.6 --repeat-penalty 0.5 --seed 42
#
# Architecture:
#   Stage 1 - Load source audio at native sample rate, preserve all channels,
#             and analyse the strongest-RMS real channel.
#   Stage 2 - Window into overlapping grains and extract a 17-dimensional
#             feature vector per grain:
#               [0] RMS energy
#               [1] spectral centroid
#               [2] spectral flatness
#               [3] zero-crossing rate
#               [4..16] MFCCs 1-13 (coefficient 0 dropped: it is gain)
#             Standardise the whole pool with StandardScaler.
#   Stage 3 - Train a multi-target RandomForestRegressor on transition pairs
#             X_t -> X_{t+k}. Report row-wise OOB R^2 as a diagnostic and,
#             more importantly, OOB skill relative to the persistence
#             baseline Y=X. Overlapping grains make raw OOB R^2 optimistic.
#   Stage 4 - Synthesise a target trajectory of the requested duration in
#             the SAME standardised space (units are corpus SDs).
#   Stage 5 - Walk the trajectory. At every output step the forest predicts
#             the natural continuation of the current state; that prediction
#             is blended with the target and the blend is matched against
#             the grain pool by L2 distance (scipy.spatial.distance.cdist).
#   Stage 6 - Apply the chosen grain indices to every source channel,
#             Hann-window and overlap-add, divide by the accumulated window
#             envelope, optionally match global RMS to the source, then apply
#             an attenuation-only safety ceiling and write with soundfile.
#   Stage 7 - Write a key=value stats file for the Praat front end.
#
# ASCII-only and free of apostrophes on purpose: this file is also embedded
# verbatim inside the Praat script, where a single quote would trigger
# Praat variable interpolation.
# ==========================================================================

import sys
import time
import argparse

# --------------------------------------------------------------------------
# Feature layout
# --------------------------------------------------------------------------
IDX_RMS      = 0
IDX_CENTROID = 1
IDX_FLATNESS = 2
IDX_ZCR      = 3
IDX_MFCC1    = 4          # MFCCs 1-13 occupy 4..16
N_MFCC_KEPT  = 13
FEATURE_DIM  = 4 + N_MFCC_KEPT

N_MELS         = 40       # mel bands for the MFCC front end
MAX_TRAIN_ROWS = 20000    # cap on RF training rows (10 min at 25 ms = 24k)
MAX_PLOT_PTS   = 500      # cap on per-step series handed back to Praat
MAX_RMS_MATCH_GAIN = 4.0   # +12.04 dB guard against pathological quiet selections

TRAJECTORIES = ["crescendo_brightening", "spectral_descent", "random_walk"]
ENGINE_VERSION = "0.5-experimental"


# --------------------------------------------------------------------------
# Logging -- everything printed also lands in a file Praat can read back
# --------------------------------------------------------------------------
class Log(object):
    def __init__(self, path):
        self.fh = None
        if path:
            try:
                self.fh = open(path, "w")
            except IOError:
                self.fh = None

    def __call__(self, msg):
        print(msg)
        sys.stdout.flush()
        if self.fh is not None:
            self.fh.write(msg + chr(10))
            self.fh.flush()

    def close(self):
        if self.fh is not None:
            self.fh.close()
            self.fh = None


def check_dependencies(log=None):
    missing = []
    for pkg in ["numpy", "scipy", "librosa", "sklearn", "soundfile"]:
        try:
            __import__(pkg)
        except ImportError:
            missing.append(pkg)
    if missing:
        pip = ["scikit-learn" if m == "sklearn" else m for m in missing]
        msg = "ERROR: missing packages: " + ", ".join(missing)
        install = "Install with:  pip install " + " ".join(pip)
        if log is not None:
            log(msg)
            log(install)
            log.close()
        sys.stderr.write(msg + chr(10))
        sys.stderr.write(install + chr(10))
        sys.exit(1)


# ==========================================================================
# Stage 1 -- Load
# ==========================================================================

def load_audio(path, log):
    import numpy as np
    import soundfile as sf

    data, sr = sf.read(path, dtype="float64", always_2d=True)
    if data.shape[0] == 0:
        sys.stderr.write("ERROR: input file decoded to zero samples." + chr(10))
        sys.exit(1)

    # Internal layout is channels x samples so one chosen grain index can be
    # applied to all channels without destroying the source spatial image.
    audio = np.asarray(data.T, dtype=np.float64)
    n_channels, n_samples = audio.shape

    if n_channels == 1:
        analysis_channel = 0
        analysis = audio[0].copy()
        analysis_source = "channel 1 (mono input)"
    else:
        # Analyse one real channel rather than an arithmetic fold. A fold can
        # cancel or spectrally reshape correlated multichannel material. The
        # strongest-RMS channel is a stable representative while resynthesis
        # still applies every selected grain index to every source channel.
        ch_rms = np.sqrt(np.mean(audio * audio, axis=1))
        analysis_channel = int(np.argmax(ch_rms))
        analysis = audio[analysis_channel].copy()
        analysis_source = "channel %d (strongest RMS)" % (analysis_channel + 1)

    log("    Loaded %.2f s at %d Hz, %d channel%s (%d samples/channel)"
        % (n_samples / float(sr), sr, n_channels,
           "" if n_channels == 1 else "s", n_samples))
    log("    Analysis source: %s" % analysis_source)
    return audio, analysis, sr, analysis_source, analysis_channel + 1


# ==========================================================================
# Stage 2 -- Grain features
# ==========================================================================

def extract_features(y, sr, frame_len, hop_len, log):
    # Build the STFT ONCE. In v0.1 centroid, flatness and MFCC each caused a
    # separate spectral front end. Passing the same S into the feature calls
    # is exactly equivalent while avoiding redundant FFT work.
    import numpy as np
    import librosa

    n_frames = 1 + (y.size - frame_len) // hop_len

    S = np.abs(librosa.stft(
        y, n_fft=frame_len, hop_length=hop_len, win_length=frame_len,
        window="hann", center=False))
    freqs = librosa.fft_frequencies(sr=sr, n_fft=frame_len)

    rms = librosa.feature.rms(
        y=y, frame_length=frame_len, hop_length=hop_len, center=False)[0]
    cen = librosa.feature.spectral_centroid(S=S, freq=freqs)[0]
    flt = librosa.feature.spectral_flatness(S=S)[0]
    zcr = librosa.feature.zero_crossing_rate(
        y, frame_length=frame_len, hop_length=hop_len, center=False)[0]

    n_mels_eff = min(N_MELS, 1 + frame_len // 2)
    mel = librosa.feature.melspectrogram(
        S=S ** 2, sr=sr, n_fft=frame_len, n_mels=n_mels_eff)
    mfc = librosa.feature.mfcc(
        S=librosa.power_to_db(mel), sr=sr, n_mfcc=N_MFCC_KEPT + 1)

    n = min(n_frames, rms.size, cen.size, flt.size, zcr.size, mfc.shape[1])

    F = np.zeros((n, FEATURE_DIM), dtype=np.float64)
    F[:, IDX_RMS]      = rms[:n]
    F[:, IDX_CENTROID] = cen[:n]
    F[:, IDX_FLATNESS] = flt[:n]
    F[:, IDX_ZCR]      = zcr[:n]
    F[:, IDX_MFCC1:]   = mfc[1:N_MFCC_KEPT + 1, :n].T

    F = np.nan_to_num(F, nan=0.0, posinf=0.0, neginf=0.0)
    log("    Grain pool: %d grains x %d features" % (n, FEATURE_DIM))
    return F


def scale_features(F, log):
    from sklearn.preprocessing import StandardScaler
    scaler = StandardScaler()
    Z = scaler.fit_transform(F)
    log("    Standardised (mean 0, SD 1 per dimension)")
    return Z, scaler


# ==========================================================================
# Stage 3 -- Random Forest transition model
# ==========================================================================

def train_forest(Z, lookahead, trees, max_depth, seed, log):
    import numpy as np
    from sklearn.ensemble import RandomForestRegressor

    n = Z.shape[0]
    X = Z[:n - lookahead]
    Y = Z[lookahead:]

    n_rows = X.shape[0]
    if n_rows > MAX_TRAIN_ROWS:
        step = int(np.ceil(n_rows / float(MAX_TRAIN_ROWS)))
        X = X[::step]
        Y = Y[::step]
        log("    Subsampled %d -> %d training rows (stride %d)"
            % (n_rows, X.shape[0], step))

    # OOB rows are useful diagnostics but overlapping grains are strongly
    # autocorrelated, so OOB R^2 must not be read as independent validation.
    # Skill vs persistence asks a more relevant question: does the forest beat
    # the trivial predictor that the next standardised state equals this one?
    use_oob = X.shape[0] >= 10 and trees >= 20
    rf = RandomForestRegressor(
        n_estimators=trees,
        max_depth=(None if max_depth <= 0 else max_depth),
        n_jobs=-1,
        oob_score=use_oob,
        random_state=seed,
    )
    t0 = time.time()
    rf.fit(X, Y)

    oob = float("nan")
    oob_skill = float("nan")
    if use_oob:
        oob = float(getattr(rf, "oob_score_", float("nan")))
        pred = np.asarray(getattr(rf, "oob_prediction_", np.empty((0, 0))))
        if pred.shape == Y.shape:
            mse_rf = float(np.mean((Y - pred) ** 2))
            mse_persist = float(np.mean((Y - X) ** 2))
            if mse_persist > 1e-15:
                oob_skill = 1.0 - mse_rf / mse_persist
            elif mse_rf <= 1e-15:
                oob_skill = 0.0

    log("    Fitted %d trees (depth %s) on %d rows in %.1f s"
        % (trees, "None" if max_depth <= 0 else str(max_depth),
           X.shape[0], time.time() - t0))
    if use_oob:
        log("    OOB row R^2: %.4f (optimistic with overlapping grains)" % oob)
        log("    OOB skill vs persistence: %.4f" % oob_skill)
    else:
        log("    OOB diagnostics disabled (need >=20 trees and >=10 rows)")

    # Parallel tree fitting is useful; parallel prediction on ONE state at a
    # time is much slower and can alter tie-breaking through tiny summation
    # order differences. Serial prediction is faster here and reproducible.
    rf.n_jobs = 1
    return rf, X.shape[0], oob, oob_skill


# ==========================================================================
# Stage 4 -- Target trajectory (standardised space, units = corpus SDs)
# ==========================================================================

def smoothstep(t):
    return t * t * (3.0 - 2.0 * t)


def smooth_columns(T, win):
    import numpy as np
    if win < 3:
        return T
    k = np.hanning(win)
    k = k / k.sum()
    out = np.empty_like(T)
    for d in range(T.shape[1]):
        pad = np.concatenate([
            np.full(win, T[0, d]), T[:, d], np.full(win, T[-1, d])])
        out[:, d] = np.convolve(pad, k, mode="same")[win:win + T.shape[0]]
    return out


def make_trajectory(kind, n_steps, seed, log):
    import numpy as np
    rng = np.random.RandomState(seed)
    T = np.zeros((n_steps, FEATURE_DIM), dtype=np.float64)
    u = smoothstep(np.linspace(0.0, 1.0, n_steps))

    if kind == "crescendo_brightening":
        # Quiet and dull to loud and bright. MFCC1 tracks spectral tilt and
        # falls as energy moves upward, so it is ramped the other way.
        T[:, IDX_RMS]      = -1.6 + 3.2 * u
        T[:, IDX_CENTROID] = -1.4 + 3.0 * u
        T[:, IDX_ZCR]      = -1.0 + 2.2 * u
        T[:, IDX_FLATNESS] = -0.4 + 0.8 * u
        T[:, IDX_MFCC1]    = 1.0 - 2.0 * u

    elif kind == "spectral_descent":
        # Falling spectral register/brightness: no explicit F0 feature is used.
        T[:, IDX_CENTROID] = 1.6 - 3.2 * u
        T[:, IDX_ZCR]      = 1.4 - 2.8 * u
        T[:, IDX_MFCC1]    = -1.2 + 2.4 * u
        T[:, IDX_RMS]      = 0.6 * np.sin(np.pi * u)
        T[:, IDX_FLATNESS] = 0.3 - 0.6 * u

    else:
        # Ornstein-Uhlenbeck walk on every dimension: mean-reverting, so the
        # target stays inside the region the corpus actually occupies.
        theta, sigma = 0.06, 0.35
        x = np.zeros(FEATURE_DIM)
        for t in range(n_steps):
            x = x * (1.0 - theta) + sigma * rng.randn(FEATURE_DIM)
            T[t] = x
        T = np.clip(T, -2.2, 2.2)

    T = smooth_columns(T, 9)
    log("    Trajectory %s: %d steps, range %.2f to %.2f SD"
        % (kind, n_steps, float(T.min()), float(T.max())))
    return T


# ==========================================================================
# Stage 5 -- Forest-guided walk through the grain pool
# ==========================================================================

def median_nn_distance(Z, seed, sample=800):
    import numpy as np
    from scipy.spatial.distance import cdist
    rng = np.random.RandomState(seed)
    n = Z.shape[0]
    idx = rng.choice(n, size=min(sample, n), replace=False)
    D = cdist(Z[idx], Z[idx])
    np.fill_diagonal(D, np.inf)
    return float(np.median(D.min(axis=1)))


def median_pair_distance(Z, seed, sample=400):
    # Repeat cost needs a corpus-scale distance, not nearest-neighbour distance.
    # With overlapping grains the nearest neighbour can be almost identical,
    # collapsing the old repeat penalty to nearly zero.
    import numpy as np
    from scipy.spatial.distance import cdist
    rng = np.random.RandomState(seed + 17)
    n = Z.shape[0]
    idx = rng.choice(n, size=min(sample, n), replace=False)
    D = cdist(Z[idx], Z[idx])
    tri = D[np.triu_indices(idx.size, 1)]
    tri = tri[np.isfinite(tri) & (tri > 1e-9)]
    if tri.size == 0:
        return 1.0
    return float(np.median(tri))


def estimate_activity(F):
    """Find low-energy source frames by corpus-relative RMS, without a fixed dB gate.

    A stationary, low-dynamic-range recording is treated as wholly active.
    This is a coarse activity proxy, not a phoneme / voiced-unvoiced detector.
    """
    import numpy as np
    r = np.asarray(F[:, IDX_RMS], dtype=float)
    q10, q50, q90 = np.percentile(r, [10, 50, 90])
    if q90 < 1.e-8 or q90 / max(q10, 1.e-8) < 3.5:
        return np.ones(r.size, dtype=bool), 0.0
    threshold = max(3.0 * q10, 0.08 * q90)
    threshold = min(threshold, 0.4 * q50) if q50 > 0 else threshold
    mask = r > threshold
    if mask.mean() < 0.12:
        return np.ones(r.size, dtype=bool), 0.0
    return mask, float(threshold)


def planned_activity(F, active, n_steps, target, hop_len, sr, trajectory_kind):
    """Transfer the slow source activity contour to the new time scale.

    Quantile thresholding controls the requested activity ratio. Smoothing
    avoids alternating single-grain speech and silence decisions.
    """
    import numpy as np
    from scipy.ndimage import gaussian_filter1d
    if active.all() or target >= .999:
        return np.ones(n_steps, dtype=bool)
    n = active.size
    src = np.log1p(F[:, IDX_RMS] / max(np.percentile(F[:, IDX_RMS], 90), 1.e-8))
    xold = np.linspace(0., 1., n)
    xnew = np.linspace(0., 1., n_steps)
    smooth = gaussian_filter1d(np.interp(xnew, xold, src),
                              sigma=max(1., 0.085 * sr / hop_len), mode="nearest")
    if trajectory_kind == "crescendo_brightening":
        # Gradually allocate more of the available rests to the beginning.
        # This also lets the sustained ending support the requested crescendo.
        smooth += 0.40 * (xnew - .5)
    # Stable quantile threshold: exactly the requested duty fraction except ties.
    k = int(np.clip(round((1.0 - target) * n_steps), 0, n_steps))
    schedule = np.ones(n_steps, dtype=bool)
    if k:
        schedule[np.argsort(smooth, kind="stable")[:k]] = False
    return schedule


def forward_mean(A, width):
    """Fixed-width *future* average for pool segment scoring."""
    import numpy as np
    width = max(1, min(int(width), len(A)))
    ext = np.concatenate((A, np.repeat(A[-1:, :], width, axis=0)), axis=0)
    cs = np.vstack((np.zeros((1, A.shape[1])), np.cumsum(ext, axis=0)))
    return (cs[width:width + len(A)] - cs[:len(A)]) / width


def blocked_validation(Z, lookahead, trees, max_depth, seed, frame_len, hop_len, log):
    """Hold out the final chronological block; guard against STFT overlap leakage.

    Reports skill over the persistence baseline on temporally unseen rows,
    not a promise of perceptually better music. Final forest still uses all rows.
    """
    import numpy as np
    from sklearn.ensemble import RandomForestRegressor
    n = len(Z) - lookahead
    if n < 80:
        return float("nan")
    split = int(n * .8)
    guard = max(lookahead + 1, int(np.ceil(frame_len / float(hop_len))) + lookahead)
    end = max(10, split - guard)
    test = np.arange(split, n)
    if test.size < 10:
        return float("nan")
    tr = np.arange(end)
    if tr.size > MAX_TRAIN_ROWS:
        tr = tr[::int(np.ceil(tr.size / MAX_TRAIN_ROWS))]
    test = test[::max(1, int(np.ceil(test.size / 2500.0)))]
    rf = RandomForestRegressor(n_estimators=min(100, trees),
                               max_depth=None if max_depth <= 0 else max_depth,
                               random_state=seed, n_jobs=-1)
    rf.fit(Z[tr], Z[tr + lookahead])
    pred = rf.predict(Z[test])
    baseline = np.mean((Z[test + lookahead] - Z[test]) ** 2)
    model_err = np.mean((Z[test + lookahead] - pred) ** 2)
    skill = 1.0 - model_err / baseline if baseline > 1.e-15 else float("nan")
    log("    Chronological held-out RF skill vs persistence: %.4f (%d test frames, guard %d)" %
        (skill, len(test), guard))
    return float(skill)


def walk_pool(rf, Z, T, traj_weight, repeat_penalty, seed, log,
              F=None, frame_len=None, hop_len=None, sr=None,
              activity_target=.78, min_run_ms=140., max_run_ms=420.,
              mfcc_weight=.12, trajectory_kind="crescendo_brightening"):

    """RF-guided *microphrase* walk with activity-aware, novelty-aware selection.

    Each new microphrase starts at a source index chosen by RF plus the target.
    Subsequent grains advance one source hop at a time. Segment boundaries
    or an activity transition trigger a new search. No pitch is fabricated.
    """
    import numpy as np
    from scipy.spatial.distance import cdist
    if F is None or frame_len is None or hop_len is None or sr is None:
        raise ValueError("v0.5 walk_pool needs feature and timing metadata")
    rng = np.random.RandomState(seed + 851)
    n_pool, n_steps = Z.shape[0], T.shape[0]
    nn_scale = median_nn_distance(Z, seed)
    repeat_scale = median_pair_distance(Z, seed)
    active, activity_threshold = estimate_activity(F)
    plan = planned_activity(F, active, n_steps, activity_target, hop_len, sr, trajectory_kind)

    min_run = max(1, int(round(min_run_ms * .001 * sr / hop_len)))
    max_run = max(min_run, int(round(max_run_ms * .001 * sr / hop_len)))
    # Brightness and amplitude drive the target; MFCC2-13 are timbral ties.
    weights = np.full(Z.shape[1], mfcc_weight, dtype=float)
    weights[IDX_RMS] = 2.6
    weights[IDX_CENTROID] = 1.1
    weights[IDX_FLATNESS] = .25
    weights[IDX_ZCR] = .20
    weights[IDX_MFCC1] = .60
    wroot = np.sqrt(weights)
    candidate_width = max(2, min_run // 2)
    future = forward_mean(Z, candidate_width)
    local_active = forward_mean(active[:, None].astype(float), candidate_width)[:, 0]

    recent = np.zeros(n_pool, dtype=float)
    chosen = np.empty(n_steps, dtype=int)
    dists = np.empty(n_steps, dtype=float)
    jumps = []
    last_j = -1
    remaining = 0
    target_kind = np.any(np.abs(T[:, IDX_MFCC1 + 1:]) > 1.e-7)
    # Distinct grain ban is too weak; smear novelty cost around whole phrase.
    neighborhood = max(1, int(round(.35 * sr / hop_len)))
    for t in range(n_steps):
        wants_active = bool(plan[t])
        continues = (last_j >= 0 and remaining > 0 and last_j + 1 < n_pool
                     and bool(active[last_j + 1]) == wants_active)
        if continues:
            j = last_j + 1
            remaining -= 1
        else:
            recent *= .86  # decay per phrase, not per grain
            # Predict expected transition from last actual descriptor.
            state = Z[last_j] if last_j >= 0 else Z[int(np.argmin(
                np.sum((Z[:, :5] - T[0, :5]) ** 2, axis=1)))]
            pred = rf.predict(state[None, :])[0]
            goal = pred.copy()
            goal[:IDX_MFCC1 + 1] = ((1.0 - traj_weight) * pred[:IDX_MFCC1 + 1] +
                                      traj_weight * T[t, :IDX_MFCC1 + 1])
            if target_kind:
                goal[IDX_MFCC1 + 1:] = ((1.0 - traj_weight) * pred[IDX_MFCC1 + 1:] +
                                      traj_weight * T[t, IDX_MFCC1 + 1:])

            diff = (Z - goal[None, :]) * wroot[None, :]
            future_diff = (future - goal[None, :]) * wroot[None, :]
            scores = .65 * np.sum(diff * diff, axis=1) + .35 * np.sum(future_diff * future_diff, axis=1)
            # Avoid selecting runs dominated by the wrong activity class.
            if wants_active:
                scores += 17.0 * (1.0 - local_active) ** 2
                scores[~active] += 30.0
            else:
                scores += 17.0 * local_active ** 2
                scores[active] += 30.0
            # Cost for recently visited neighborhoods of the recording.
            scores += repeat_penalty * recent
            # Do not start a phrase too close to the end of the source pool.
            scores[max(0, n_pool - candidate_width):] += 20.0
            if last_j >= 0:
                # A shallow join mismatch penalty, never stronger than timbral choice.
                scores += .10 * np.sum((Z - Z[last_j][None, :]) ** 2 * weights[None, :], axis=1)
            j = int(np.argmin(scores))
            # Variation in phrase length makes the result less grid-like.
            run_cap = max_run if wants_active else max(min_run, int(max_run * .55))
            remaining = int(rng.randint(min_run, run_cap + 1)) - 1
            jumps.append(t)
            # Neighborhood suppression includes adjacent overlapping frames.
            lo, hi = max(0, j - neighborhood), min(n_pool, j + neighborhood + 1)
            dx = (np.arange(lo, hi) - j) / float(max(1, neighborhood))
            recent[lo:hi] += (1.3 * repeat_scale) * np.exp(-3.0 * dx * dx)
        # Per-step feature mismatch, including source-contiguous steps.
        current_goal = pred.copy()
        current_goal[:IDX_MFCC1 + 1] = ((1. - traj_weight) * pred[:IDX_MFCC1 + 1] +
                                           traj_weight * T[t, :IDX_MFCC1 + 1])
        if target_kind:
            current_goal[IDX_MFCC1 + 1:] = ((1. - traj_weight) * pred[IDX_MFCC1 + 1:] +
                                               traj_weight * T[t, IDX_MFCC1 + 1:])
        dists[t] = float(np.sqrt(np.sum(weights * (Z[j] - current_goal) ** 2)))
        chosen[t] = j
        last_j = j
    immediate_repeat_pct = (100.0 * np.mean(chosen[1:] == chosen[:-1])) if n_steps > 1 else 0.0
    adjacent_pct = (100.0 * np.mean(np.diff(chosen) == 1)) if n_steps > 1 else 0.0
    selected_active_pct = 100.0 * float(np.mean(active[chosen]))
    plan_active_pct = 100.0 * float(np.mean(plan))
    mean_phrase_ms = 1000. * n_steps * hop_len / float(sr * max(1, len(jumps)))
    extra = dict(activity_threshold=activity_threshold,
                 source_active_pct=100.0 * active.mean(),
                 target_active_pct=plan_active_pct,
                 selected_active_pct=selected_active_pct,
                 source_continuation_pct=adjacent_pct,
                 n_phrases=len(jumps), mean_phrase_ms=mean_phrase_ms,
                 min_run_ms=min_run * hop_len * 1000. / sr,
                 max_run_ms=max_run * hop_len * 1000. / sr,
                 match_metric="weighted_phrase_l2")
    log("    Microphrases %d (mean %.0f ms); consecutive source hops %.1f%%" %
        (len(jumps), mean_phrase_ms, adjacent_pct))
    log("    Activity source %.1f%%, target %.1f%%, selected %.1f%% (gate %.5f RMS)" %
        (extra["source_active_pct"], plan_active_pct, selected_active_pct,
         activity_threshold))
    log("    Corpus novelty neighborhood %.0f ms; immediate repeats %.1f%%" %
        (neighborhood * hop_len * 1000. / sr, immediate_repeat_pct))
    return chosen, dists, nn_scale, repeat_scale, immediate_repeat_pct, extra


# ==========================================================================
# Stage 6 -- Overlap-add resynthesis
# ==========================================================================

def apply_trajectory_render(out, sr, kind, strength, log):
    """Conservative offline energy/spectral-tilt contour after concatenation.

    RF and microphrase selection choose source material; this final stage
    disambiguates independent amplitude and brightness goals that can be
    negatively correlated in natural speech. It can be disabled with a flag.
    """
    import numpy as np
    from scipy.signal import butter, sosfiltfilt
    strength = float(strength)
    if strength <= 0 or kind == "random_walk" or out.shape[1] < 100:
        return out
    u = smoothstep(np.linspace(0., 1., out.shape[1]))
    if kind == "crescendo_brightening":
        level_db = strength * (-4.5 + 9.0 * u)
        tilt_db = strength * (-7.0 + 14.0 * u)
    elif kind == "spectral_descent":
        level_db = np.zeros_like(u)
        tilt_db = strength * (7.0 - 14.0 * u)
    else:
        return out
    cutoff = min(1800., sr * .2)
    sos = butter(2, cutoff, btype="highpass", fs=sr, output="sos")
    high = sosfiltfilt(sos, out, axis=1)
    tilt = 10. ** (tilt_db / 20.) - 1.
    out = out + high * tilt[None, :]
    out = out * (10. ** (level_db / 20.))[None, :]
    log("    Rendered %s: level %.1f to %.1f dB, high band %.1f to %.1f dB at %.0f Hz" %
        (kind, level_db[0], level_db[-1], tilt_db[0], tilt_db[-1], cutoff))
    return out


def resynthesise(audio, chosen, frame_len, hop_len, out_samples,
                  match_input_rms, safety_peak, log, sr=None,
                  render_kind="random_walk", render_strength=1.):
    import numpy as np

    n_channels, n_source = audio.shape
    n_steps = chosen.size
    total   = (n_steps - 1) * hop_len + frame_len
    buf = np.zeros((n_channels, total), dtype=np.float64)
    env = np.zeros(total, dtype=np.float64)

    win = np.hanning(frame_len + 1)[:frame_len]   # periodic Hann

    for t in range(n_steps):
        s = int(chosen[t]) * hop_len
        g = audio[:, s:s + frame_len]
        if g.shape[1] < frame_len:
            g = np.pad(g, ((0, 0), (0, frame_len - g.shape[1])))
        p = t * hop_len
        buf[:, p:p + frame_len] += g * win[None, :]
        env[p:p + frame_len] += win

    # Weighted average of overlapping, potentially unrelated grains.
    floor = 0.05 * float(env.max()) if env.max() > 0 else 1.0
    out = buf / np.maximum(env[None, :], floor)

    if out.shape[1] >= out_samples:
        out = out[:, :out_samples]
    else:
        out = np.pad(out, ((0, 0), (0, out_samples - out.shape[1])))

    # Fade the FINAL buffer. Fading before trimming can cut off the end of the
    # fade whenever target duration is not aligned to the hop grid.
    out = apply_edge_fades(out, frame_len)
    if sr is not None:
        out = apply_trajectory_render(out, sr, render_kind, render_strength, log)

    input_rms = float(np.sqrt(np.mean(audio * audio))) if audio.size else 0.0
    rms_before_match = float(np.sqrt(np.mean(out * out))) if out.size else 0.0
    rms_gain = 1.0
    rms_limited = 0
    if match_input_rms and input_rms > 1e-15 and rms_before_match > 1e-15:
        wanted = input_rms / rms_before_match
        if wanted > MAX_RMS_MATCH_GAIN:
            wanted = MAX_RMS_MATCH_GAIN
            rms_limited = 1
        rms_gain = wanted
        out = out * rms_gain

    rms_after_match = float(np.sqrt(np.mean(out * out))) if out.size else 0.0
    peak_before = float(np.max(np.abs(out))) if out.size else 0.0
    if safety_peak > 0.0 and peak_before > safety_peak:
        out = out * (safety_peak / peak_before)
    peak_after = float(np.max(np.abs(out))) if out.size else 0.0
    output_rms = float(np.sqrt(np.mean(out * out))) if out.size else 0.0

    log("    Overlap-added %d grains -> %d samples x %d ch"
        % (n_steps, out.shape[1], n_channels))
    if match_input_rms:
        gain_db = 20.0 * np.log10(max(rms_gain, 1e-15))
        log("    RMS %.4f -> %.4f; source %.4f; level gain %+.2f dB%s"
            % (rms_before_match, rms_after_match, input_rms, gain_db,
               " (limited)" if rms_limited else ""))
    else:
        log("    RMS matching disabled; output RMS %.4f" % rms_before_match)
    log("    Peak %.4f before safety, %.4f after" % (peak_before, peak_after))

    # soundfile expects samples x channels.
    return (out.T.astype(np.float32), peak_before, peak_after, input_rms,
            rms_before_match, rms_after_match, output_rms, rms_gain, rms_limited)


def apply_edge_fades(x, frame_len):
    import numpy as np
    n = min(frame_len, x.shape[1] // 2)
    if n < 2:
        return x
    ramp = np.hanning(2 * n)[:n]
    x = x.copy()
    x[:, :n] *= ramp[None, :]
    x[:, -n:] *= ramp[::-1][None, :]
    return x


# ==========================================================================
# Stage 7 -- Stats for the Praat front end
# ==========================================================================

def subsample(a, cap):
    import numpy as np
    if a.size <= cap:
        return a
    idx = np.linspace(0, a.size - 1, cap).astype(int)
    return a[idx]


def write_stats(path, args, sr, n_source_samples, n_channels,
                analysis_source, analysis_channel, F_rows, chosen, dists, out,
                peak_before, peak_after, input_rms, rms_before_match,
                rms_after_match, output_rms, rms_gain, rms_limited,
                train_rows, oob, oob_skill, nn_scale, repeat_scale,
                immediate_repeat_pct, hop_len, frame_len, elapsed, warnings, extra=None, blocked_skill=float("nan")):
    import numpy as np

    distinct = int(np.unique(chosen).size)
    if chosen.size <= MAX_PLOT_PTS:
        plot_idx = np.arange(chosen.size, dtype=int)
    else:
        plot_idx = np.linspace(0, chosen.size - 1, MAX_PLOT_PTS).astype(int)

    src_t = chosen[plot_idx].astype(np.float64) * hop_len / float(sr)
    out_t = plot_idx.astype(np.float64) * hop_len / float(sr)
    mdist = dists[plot_idx]

    with open(path, "w") as f:
        p = lambda s: print(s, file=f)
        p("n_pool_grains=%d"     % F_rows)
        p("n_output_grains=%d"   % chosen.size)
        p("sample_rate=%d"       % sr)
        p("input_channels=%d"    % n_channels)
        p("output_channels=%d"   % (1 if out.ndim == 1 else out.shape[1]))
        p("analysis_source=%s"   % analysis_source)
        p("analysis_channel=%d"  % analysis_channel)
        p("frame_samples=%d"     % frame_len)
        p("hop_samples=%d"       % hop_len)
        p("overlap_pct=%.1f"     % (100.0 * (1.0 - hop_len / float(frame_len))))
        p("input_duration=%.3f"  % (n_source_samples / float(sr)))
        p("output_duration=%.3f" % (out.shape[0] / float(sr)))
        p("feature_dim=%d"       % FEATURE_DIM)
        p("rf_train_rows=%d"     % train_rows)
        p("rf_oob_r2=%.4f"       % oob)
        p("rf_oob_skill=%.4f"    % oob_skill)
        p("trajectory=%s"        % args.trajectory)
        p("traj_weight=%.3f"     % args.traj_weight)
        p("repeat_penalty=%.3f"  % args.repeat_penalty)
        p("distinct_grains=%d"   % distinct)
        p("distinct_pct=%.1f"    % (100.0 * distinct / max(1, chosen.size)))
        p("mean_match_dist=%.4f" % float(np.mean(dists)))
        p("median_nn_dist=%.4f"  % nn_scale)
        p("repeat_distance_scale=%.4f" % repeat_scale)
        p("immediate_repeat_pct=%.1f" % immediate_repeat_pct)
        p("match_input_rms=%d"   % int(bool(args.match_input_rms)))
        p("source_rms=%.6f"       % input_rms)
        p("rms_before_match=%.6f" % rms_before_match)
        p("rms_after_match=%.6f"  % rms_after_match)
        p("rms_match_gain=%.6f"   % rms_gain)
        p("rms_match_gain_db=%.3f" % (20.0 * np.log10(max(rms_gain, 1e-15))))
        p("rms_match_limited=%d"  % rms_limited)
        p("peak_before_safety=%.4f" % peak_before)
        p("output_peak=%.4f"      % peak_after)
        p("out_rms=%.6f"          % output_rms)
        p("elapsed_s=%.1f"       % elapsed)
        p("n_points=%d"          % src_t.size)
        p("src_times=%s"         % ",".join("%.3f" % v for v in src_t))
        p("out_times=%s"         % ",".join("%.3f" % v for v in out_t))
        p("match_dists=%s"       % ",".join("%.3f" % v for v in mdist))
        p("engine_version=%s" % ENGINE_VERSION)
        p("rf_blocked_skill=%.4f" % blocked_skill)
        if extra:
            for key, val in extra.items():
                if isinstance(val, (int, float, np.floating)):
                    p("%s=%.5f" % (key, val))
                else:
                    p("%s=%s" % (key, str(val)))
        if warnings:
            p("warning=%s" % "; ".join(warnings))


# ==========================================================================
# Main
# ==========================================================================

def build_parser():
    ap = argparse.ArgumentParser(
        description="Random Forest concatenative synthesis engine")
    ap.add_argument("--input",  required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--stats",  default="")
    ap.add_argument("--log",    default="")
    ap.add_argument("--target-duration", type=float, default=10.0)
    ap.add_argument("--frame-ms",        type=float, default=100.0)
    ap.add_argument("--hop-ms",          type=float, default=25.0)
    ap.add_argument("--trajectory",      default="crescendo_brightening")
    ap.add_argument("--trees",           type=int,   default=100)
    ap.add_argument("--max-depth",       type=int,   default=15)
    ap.add_argument("--lookahead",       type=int,   default=1)
    ap.add_argument("--traj-weight",     type=float, default=0.6)
    ap.add_argument("--repeat-penalty",  type=float, default=0.5)
    ap.add_argument("--seed",            type=int,   default=42)
    ap.add_argument("--match-input-rms", type=int,   default=1)
    ap.add_argument("--safety-peak",     type=float, default=0.99)
    # Optional v0.5 controls. All v0.4 flags retain their semantics.
    ap.add_argument("--activity-target", type=float, default=0.78,
                    help="target fraction of output grains containing active material (0.05 to 1)")
    ap.add_argument("--min-run-ms", type=float, default=140.0,
                    help="minimum length of contiguous source microphrases")
    ap.add_argument("--max-run-ms", type=float, default=420.0,
                    help="maximum length of contiguous source microphrases")
    ap.add_argument("--mfcc-weight", type=float, default=0.12,
                    help="relative matching weight for non-primary MFCC descriptors")
    ap.add_argument("--render-strength", type=float, default=1.,
                    help="0 disables energy/brightness trajectory rendering; default 1")
    return ap


def main():
    args = build_parser().parse_args()
    log = Log(args.log)
    check_dependencies(log)

    import numpy as np
    import soundfile as sf

    t_start = time.time()
    warnings = []

    # -- clamp -------------------------------------------------------------
    args.target_duration = max(0.5, min(600.0, args.target_duration))
    args.frame_ms        = max(5.0, min(2000.0, args.frame_ms))
    args.hop_ms          = max(1.0, min(args.frame_ms, args.hop_ms))
    args.trees           = max(1, min(1000, args.trees))
    args.lookahead       = max(1, min(50, args.lookahead))
    args.traj_weight     = max(0.0, min(1.0, args.traj_weight))
    args.repeat_penalty  = max(0.0, min(10.0, args.repeat_penalty))
    args.match_input_rms = 1 if args.match_input_rms else 0
    args.safety_peak     = max(0.0, min(1.0, args.safety_peak))
    args.activity_target = max(.05, min(1.0, args.activity_target))
    args.min_run_ms      = max(20., min(1500., args.min_run_ms))
    args.max_run_ms      = max(args.min_run_ms, min(3000., args.max_run_ms))
    args.mfcc_weight     = max(.0, min(3., args.mfcc_weight))
    args.render_strength = max(0., min(2., args.render_strength))
    if args.trajectory == "pitch_descent":
        warnings.append("pitch_descent is a legacy alias; using spectral_descent")
        args.trajectory = "spectral_descent"
    if args.trajectory not in TRAJECTORIES:
        warnings.append("unknown trajectory %s, using %s"
                        % (args.trajectory, TRAJECTORIES[0]))
        args.trajectory = TRAJECTORIES[0]

    log("=== rf_engine.py v0.5 EXPERIMENTAL -- Random Forest Concatenative Synthesis ===")
    log("  [Py 1/6] Loading audio...")
    audio, y, sr, analysis_source, analysis_channel = load_audio(args.input, log)
    n_channels, n_source_samples = audio.shape

    frame_len = int(round(args.frame_ms * 0.001 * sr))
    hop_len   = int(round(args.hop_ms   * 0.001 * sr))
    min_frame_for_mfcc = 2 * N_MFCC_KEPT
    if frame_len < min_frame_for_mfcc:
        warnings.append("grain length raised from %d to %d samples so 13 MFCCs "
                        "have enough FFT bins" % (frame_len, min_frame_for_mfcc))
        frame_len = min_frame_for_mfcc
    hop_len = max(1, min(frame_len, hop_len))

    if n_source_samples < frame_len * 4:
        sys.stderr.write("ERROR: input is shorter than four grains "
                         "(%d samples, grain = %d)." % (n_source_samples, frame_len) + chr(10))
        sys.exit(1)

    overlap_pct = 100.0 * (1.0 - hop_len / float(frame_len))
    log("    Grain %d samples (%.1f ms), hop %d samples (%.1f ms), overlap %.0f%%"
        % (frame_len, 1000.0 * frame_len / sr, hop_len,
           1000.0 * hop_len / sr, overlap_pct))
    if overlap_pct < 25.0:
        # Below 25 percent the summed Hann envelope dips towards zero between
        # grains; the envelope floor in resynthesise() then leaves an audible
        # discontinuity at every grain boundary.
        warnings.append("overlap is only %.0f%%; expect clicks at grain "
                        "boundaries (hop 25%% of frame is the safe default)"
                        % overlap_pct)

    log("  [Py 2/6] Extracting grain features...")
    F = extract_features(y, sr, frame_len, hop_len, log)
    if F.shape[0] <= args.lookahead + 4:
        sys.stderr.write("ERROR: only %d grains, too few to train on."
                         % F.shape[0] + chr(10))
        sys.exit(1)
    Z, _ = scale_features(F, log)

    log("  [Py 3/6] Training Random Forest (%d trees, depth %d, k=%d)..."
        % (args.trees, args.max_depth, args.lookahead))
    blocked_skill = blocked_validation(
        Z, args.lookahead, args.trees, args.max_depth, args.seed,
        frame_len, hop_len, log)
    rf, train_rows, oob, oob_skill = train_forest(
        Z, args.lookahead, args.trees, args.max_depth, args.seed, log)
    if np.isfinite(oob_skill) and oob_skill < 0.0:
        warnings.append("bootstrap OOB skill is below persistence (overlap-biased): "
                        "do not interpret OOB as independent validation")
    if np.isfinite(blocked_skill) and blocked_skill < 0.0:
        warnings.append("temporally held-out RF forecasting is below persistence; "
                        "music quality still requires listening")

    out_samples = int(round(args.target_duration * sr))
    n_steps = max(1, 1 + int(np.ceil(max(0, out_samples - frame_len) / float(hop_len))))
    if n_steps * F.shape[0] > 200000000:
        warnings.append("large search: %d output steps x %d pool grains may be slow"
                        % (n_steps, F.shape[0]))

    log("  [Py 4/6] Building target trajectory...")
    T = make_trajectory(args.trajectory, n_steps, args.seed, log)

    log("  [Py 5/6] Matching trajectory against the grain pool...")
    chosen, dists, nn_scale, repeat_scale, immediate_repeat_pct, extra = walk_pool(
        rf, Z, T, args.traj_weight, args.repeat_penalty, args.seed, log,
        F=F, frame_len=frame_len, hop_len=hop_len, sr=sr,
        activity_target=args.activity_target, min_run_ms=args.min_run_ms,
        max_run_ms=args.max_run_ms, mfcc_weight=args.mfcc_weight,
        trajectory_kind=args.trajectory)

    distinct_pct = 100.0 * np.unique(chosen).size / float(chosen.size)
    log("    Distinct grains used: %d of %d (%.1f%%)"
        % (np.unique(chosen).size, chosen.size, distinct_pct))
    if distinct_pct < 10.0:
        warnings.append("only %.0f%% of the selected grains are distinct; "
                        "consider stronger novelty or shorter microphrases" % distinct_pct)
    if args.repeat_penalty > 0 and immediate_repeat_pct > 25.0:
        warnings.append("%.0f%% immediate grain repeats remain; raise Repeat penalty "
                        "for more variation" % immediate_repeat_pct)

    log("  [Py 6/6] Overlap-add resynthesis...")
    (out, peak_before, peak_after, input_rms, rms_before_match,
     rms_after_match, output_rms, rms_gain, rms_limited) = resynthesise(
        audio, chosen, frame_len, hop_len, out_samples,
        bool(args.match_input_rms), args.safety_peak, log, sr=sr,
        render_kind=args.trajectory, render_strength=args.render_strength)
    extra["render_strength"] = args.render_strength
    if rms_limited:
        warnings.append("RMS level match hit the +12 dB gain cap; final RMS may remain below source")
    sf.write(args.output, out, sr, subtype="FLOAT")

    elapsed = time.time() - t_start
    if args.stats:
        write_stats(args.stats, args, sr, n_source_samples, n_channels,
                    analysis_source, analysis_channel, F.shape[0], chosen, dists, out,
                    peak_before, peak_after, input_rms, rms_before_match,
                    rms_after_match, output_rms, rms_gain, rms_limited,
                    train_rows, oob, oob_skill, nn_scale, repeat_scale,
                    immediate_repeat_pct, hop_len, frame_len, elapsed, warnings,
                    extra=extra, blocked_skill=blocked_skill)

    for w in warnings:
        log("    WARNING: " + w)
    log("    Output: %.2f s, %d ch, RMS %.4f, peak %.4f, %.1f s total"
        % (out.shape[0] / float(sr), n_channels, output_rms,
           float(np.max(np.abs(out))), elapsed))
    log("OK: wrote " + args.output)
    log.close()


if __name__ == "__main__":
    main()
