"""
ssm_morph_engine.py — SSM Morph Composer Engine

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University

Called by SSMComposer.praat — not run directly.

Version 1.4 (2026) — feature/SSM reliability + navigation repairs:
  * Multichannel feature extraction uses the strongest RMS channel instead of
    averaging channels (anti-phase stereo no longer becomes silence).
  * Spectral flatness and flux are amplitude-invariant; RMS remains the explicit
    level feature. Cosine preprocessing drops numerically constant dimensions
    and floors tiny IQR scales relative to typical feature magnitude, preventing
    skewed corpora from saturating the SSM.
  * Teleports obey tabu constraints and update tabu history exactly like normal
    transitions (previously a teleport could jump into a taboo event and skipped
    history update).
  * Added normalized_path_entropy and effective_feature_dims diagnostics.

Version 1.3 (2026) — third-round review repairs:
  * motif_boost = 0 is EXACTLY identity, and the transform is
    continuous in boost: detection still runs on the off-diagonal-
    normalized matrix (contrast-invariant), but the output is
    built from the ORIGINAL matrix as SSM * (1 + boost*field),
    renormalized by the off-diagonal max only when it exceeds 1.
    (v1.2 returned the rescaled detection matrix even at boost 0:
    measured 0.57 relative change as a side effect.)
  * Fewer than 2 events is a fatal error; fewer than 4 warns
    (navigation needs somewhere to go).
  * "output_duration" renamed "planned_event_duration": the Praat
    side crossfades with overlap, so the audio is shorter by
    ~(transitions * crossfade); Praat now reports the measured
    duration and shows this one as "planned".
  * Usage/docs updated (Original mode, per-mode parameters,
    --transform_seed).

Version 1.2 (2026) — external-review repairs:
  * MotifAmplify is real motif detection: ALL diagonals scanned,
    per-diagonal smoothing, banded cells above an adaptive
    threshold boosted symmetrically (was: +/-5 offsets only —
    local continuity mislabeled as motif detection).
  * Metric-correct preprocessing: euclidean keeps median/IQR;
    cosine scales by IQR WITHOUT centering (median-centering made
    identical events into zero vectors: similarity 0.5 instead of
    1.0). Near-zero-variance features dropped; zero-norm (silent)
    rows handled explicitly.
  * "Original" identity mode + --transform_amount blending
    (SSM_final = (1-a)*orig + a*transformed): graded A/B.
  * StructureWarp uses --transform_seed (default = --seed); the
    hardcoded seed=42 is gone. Per-mode parameters exposed
    (--blur_sigma, --sharpen_gamma, --diffusion_alpha/steps,
    --motif_boost, --warp_amplitude).
  * Real matrices exported for the Praat display
    (--ssm_orig_txt / --ssm_mod_txt, whitespace matrix text) —
    Praat no longer rebuilds a different MFCC-based SSM and no
    longer labels an unmodified copy "after transform".
  * Unreadable patches are a FATAL error listing the files
    (silent np.zeros(5) corrupted the SSM); too-short patches
    warn and count as silence.
  * Metrics: frobenius_change, offdiag_mean_orig/mod,
    diag_energy for BOTH matrices, path_sim_orig/mod,
    mean_chrono_jump, coverage, teleport_rate, mean_run_length.
  * tabu_length >= 0 (0 = baseline); teleport/visit validated.
  * Sharpen documented honestly: a monotone contrast reshaping —
    with visit penalty off it is largely redundant with low
    temperature (confirmed by same-path tests); kept as a
    convenience preset of that behavior.

Usage:
    python ssm_morph_engine.py events.csv plan.csv stats.txt
        --patch_dir  <dir>
        --mode       <Blur|Sharpen|Diffusion|MotifAmplify|StructureWarp|Original>
        --transform_amount <0..1>   --transform_seed <int|-1>
        --blur_sigma --sharpen_gamma --diffusion_alpha --diffusion_steps
        --motif_boost --warp_amplitude
        --metric     <cosine|euclidean>
        --output_events <int>
        --temperature   <float>
        --tabu_length   <int>
        --seed          <int>
        --draw_ssm      <0|1>
        --ssm_orig_png  <path>
        --ssm_mod_png   <path>

Pipeline:
    Stage 1 — Load events.csv + extract features from audio patches
    Stage 2 — Build Self-Similarity Matrix (SSM)
    Stage 3 — Apply SSM transformation (mode-dependent)
    Stage 4 — Navigate new event path through modified SSM
    Stage 5 — Write plan.csv and stats.txt

SSM transformation modes:
    Blur         — Gaussian smoothing: reduces sharp boundaries (ambient)
    Sharpen      — Similarity contrast SSM^gamma (largely overlaps
                   low temperature when visit penalty is off)
    Diffusion    — Iterative diffusion: spreads similarity (evolving)
    MotifAmplify — Detect repetition bands on ALL diagonals and
                   lift them; non-band structure preserved
                   (uniformly rescaled only if the lift tops 1)
    StructureWarp — Smooth nonlinear coordinate warp of SSM (folded time)

No sklearn. No PyTorch.
Dependencies: numpy, scipy, soundfile.
"""

import sys
import os
import csv
import math
import argparse

import numpy as np
from scipy.ndimage import gaussian_filter


# ═══════════════════════════════════════════════════════════════════════════
# Stage 1 — Feature extraction
# ═══════════════════════════════════════════════════════════════════════════

def extract_features(patch_path):
    """
    Extract a 5-dim feature vector from one event audio patch.

    Features:
        spectral centroid (normalised)
        spectral flatness (amplitude-invariant)
        spectral entropy
        spectral flux of L1-normalised spectral shape (0..1-ish)
        RMS energy

    v1.4: for multichannel patches, analyse the strongest RMS channel rather
    than averaging channels; averaging can completely cancel anti-phase audio.
    """
    try:
        import soundfile as sf
        audio, sr = sf.read(patch_path, always_2d=False)
        audio = np.asarray(audio, dtype=np.float64)
        if audio.ndim == 2:
            ch_rms = np.sqrt(np.mean(audio ** 2, axis=0) + 1e-30)
            audio = audio[:, int(np.argmax(ch_rms))]
    except Exception as e:
        raise IOError("cannot read patch %s (%s)" % (patch_path, e))

    N = len(audio)
    if N < 8:
        print("    WARNING: patch too short, treated as silence: %s" % patch_path)
        return np.zeros(5)

    n_fft = min(1024, N)
    hop   = max(1, n_fft // 2)
    freqs = np.fft.rfftfreq(n_fft, d=1.0 / sr)

    # No synthetic zero-padding frames in the feature statistics: patch
    # boundaries are already real event boundaries from Praat.
    from scipy.signal import stft as scipy_stft
    _, _, Zxx = scipy_stft(audio, fs=sr, window="hann",
                           nperseg=n_fft, noverlap=n_fft - hop,
                           nfft=n_fft, boundary=None, padded=False)
    mag = np.abs(Zxx)
    pow_ = mag ** 2

    mag_sum = mag.sum(axis=0)
    active = mag_sum > 1e-12
    if not np.any(active):
        return np.zeros(5)

    # Centroid: average active frames only.
    centroids = np.zeros(mag.shape[1], dtype=np.float64)
    centroids[active] = np.dot(freqs, mag[:, active]) / mag_sum[active]

    # Flatness with a floor relative to each frame's own maximum power, so a
    # pure gain change does not change the feature. Silent frames -> 0.
    pmax = np.max(pow_, axis=0)
    floor = np.maximum(pmax * 1e-12, 1e-30)
    pow_safe = np.maximum(pow_, floor[None, :])
    log_mean = np.mean(np.log(pow_safe), axis=0)
    arith = np.mean(pow_, axis=0)
    flatnesses = np.zeros_like(arith)
    ok = arith > 1e-20
    flatnesses[ok] = np.exp(log_mean[ok]) / arith[ok]

    # Spectral entropy, active frames only.
    n_bins = pow_.shape[0]
    p_norm = pow_ / (pow_.sum(axis=0, keepdims=True) + 1e-30)
    h_raw = -np.sum(p_norm * np.log(p_norm + 1e-30), axis=0)
    entropies = h_raw / max(math.log(n_bins), 1e-12)

    # Spectral-shape flux rather than absolute-magnitude flux. RMS below is the
    # one explicit level feature; otherwise loudness was counted twice.
    shape = mag / (mag_sum[None, :] + 1e-30)
    if shape.shape[1] > 1:
        flux = float(np.mean(0.5 * np.sum(np.abs(np.diff(shape, axis=1)), axis=0)))
    else:
        flux = 0.0

    rms = float(math.sqrt(np.mean(audio ** 2) + 1e-30))

    return np.array([
        float(np.mean(centroids[active])) / (sr / 2 + 1e-12),
        float(np.mean(flatnesses[active])),
        float(np.mean(entropies[active])),
        flux,
        rms,
    ], dtype=np.float64)


def load_features(events, patch_dir, patch_prefix="patch_"):
    """Build feature matrix X (N x 5) from audio patches.
    v1.2: any unreadable patch aborts the run with the file list —
    silently substituting zeros corrupted the SSM."""
    feats, bad = [], []
    for ev in events:
        idx        = int(ev["event_index"])
        patch_path = os.path.join(patch_dir, "%s%d.wav" % (patch_prefix, idx))
        try:
            feats.append(extract_features(patch_path))
        except IOError as e:
            bad.append(str(e))
    if bad:
        for b in bad:
            print("    ERROR: %s" % b)
        print("FATAL: %d unreadable patch file(s) — aborting." % len(bad))
        sys.exit(1)
    return np.array(feats, dtype=np.float64)


def robust_normalize(X, metric="euclidean", return_keep=False):
    """
    Robust feature scaling with numerically-constant dimensions removed.

    Euclidean uses median/IQR standardisation. Cosine stays uncentred, but its
    scale has a robust floor tied to each feature's typical magnitude. This
    prevents a tiny IQR in a nearly-constant dimension from exploding that
    coordinate and saturating all cosine similarities near 1.
    """
    X = np.asarray(X, dtype=np.float64)
    q75 = np.percentile(X, 75, axis=0)
    q25 = np.percentile(X, 25, axis=0)
    iqr = q75 - q25
    typical = np.median(np.abs(X), axis=0)
    full_span = np.ptp(X, axis=0)
    min_spread = np.maximum(1e-8, 1e-4 * np.maximum(typical, 1e-4))
    keep = full_span > min_spread

    if not np.any(keep):
        # Degenerate corpus: retain the original geometry; all identical
        # non-zero rows remain identical and silent zero rows remain zero.
        keep = np.ones(X.shape[1], dtype=bool)
        Xk = X.copy()
        scales = np.ones(X.shape[1], dtype=np.float64)
    else:
        Xk = X[:, keep]
        # The 0.25*typical floor matters only for strongly skewed corpora in
        # which the IQR collapses around a common value while a minority of
        # events still differs meaningfully. On diverse corpora it is inactive.
        scales = np.maximum(iqr[keep], 0.25 * np.maximum(typical[keep], 1e-6))
        scales = np.maximum(scales, 1e-8)

    if metric == "cosine":
        out = Xk / scales
    else:
        med = np.median(Xk, axis=0)
        out = (Xk - med) / scales
    if return_keep:
        return out, keep
    return out


# ═══════════════════════════════════════════════════════════════════════════
# Stage 2 — Build SSM
# ═══════════════════════════════════════════════════════════════════════════

def build_ssm(X, metric="cosine"):
    """
    Build Self-Similarity Matrix from feature matrix X.
    Returns SSM normalised to [0, 1].
    """
    N = X.shape[0]

    if metric == "cosine":
        raw_norms = np.linalg.norm(X, axis=1)
        zero_rows = raw_norms < 1e-10          # silent / featureless events
        norms = raw_norms[:, None] + 1e-12
        Xn    = X / norms
        SSM   = Xn.dot(Xn.T)
        # Features are non-negative and cosine therefore lives in [0,1].
        # v1.4 keeps cosine uncentred, but robust_normalize prevents tiny
        # feature scales from numerically dominating the angle.
        SSM   = np.clip(SSM, 0.0, 1.0)
        if np.any(zero_rows):
            # a silent event is similar to other silent events (1)
            # and to nothing else (0)
            SSM[zero_rows, :] = 0.0
            SSM[:, zero_rows] = 0.0
            zr = np.where(zero_rows)[0]
            SSM[np.ix_(zr, zr)] = 1.0
    else:
        diff  = X[:, None, :] - X[None, :, :]
        dist  = np.sqrt(np.sum(diff ** 2, axis=2))
        d_max = dist.max() + 1e-12
        SSM   = 1.0 - dist / d_max    # 0=far, 1=near

    np.fill_diagonal(SSM, 1.0)
    return SSM.astype(np.float64)


# ═══════════════════════════════════════════════════════════════════════════
# Stage 3 — SSM transformations
# ═══════════════════════════════════════════════════════════════════════════

def _renorm(S):
    """
    Re-normalise to [0,1] and restore diagonal.
    v1.3: a near-constant similarity field is LEFT constant. The
    old (S-min)/(max-min+eps) stretched floating-point noise
    (spans ~1e-11) across the full [0,1] range, turning a uniform
    matrix into fake compositional structure (all-ones -> zeros
    off-diagonal after Blur/Diffusion/StructureWarp). Also
    symmetrizes, since the stretch could otherwise amplify tiny
    S[i,j] vs S[j,i] asymmetries.
    """
    S = np.asarray(S, dtype=np.float64)
    S = 0.5 * (S + S.T)
    mn = float(S.min())
    mx = float(S.max())
    span = mx - mn
    if span < 1e-9:
        out = np.clip(S.copy(), 0.0, 1.0)
        np.fill_diagonal(out, 1.0)
        return out
    out = (S - mn) / span
    out = 0.5 * (out + out.T)
    np.fill_diagonal(out, 1.0)
    return out


def transform_blur(SSM, sigma=2.5):
    """Gaussian smoothing — reduces sharp structural boundaries."""
    if sigma <= 1e-12:
        return SSM.copy()
    return _renorm(gaussian_filter(SSM, sigma=sigma))


def transform_sharpen(SSM, gamma=3.0):
    """
    Power mapping SSM^gamma — reinforces strong similarities.
    Exaggerates motifs and repetitive patterns.
    """
    S = np.power(np.clip(SSM, 0.0, 1.0), gamma)
    np.fill_diagonal(S, 1.0)
    return S


def transform_diffusion(SSM, alpha=0.85, n_steps=4):
    """
    Iterative matrix diffusion:
        SSM_{t+1} = alpha * SSM_t + (1-alpha) * (SSM_t @ SSM_t)
    Spreads similarity across structure — creates evolving motif families.
    """
    if n_steps <= 0 or alpha >= 1.0 - 1e-12:
        return SSM.copy()
    S = SSM.copy()
    for _ in range(n_steps):
        S2    = S.dot(S)
        S2   /= S2.max() + 1e-12
        S     = alpha * S + (1.0 - alpha) * S2
        S     = _renorm(S)
    return S


def transform_motif_amplify(SSM, boost=2.0, min_run=3):
    """
    v1.2: REAL motif detection. A repetition of a phrase at lag k
    appears as a bright BAND along diagonal offset k. Every
    diagonal (all lags 1..N-1) is scanned; each is smoothed along
    its length (run coherence), and cells whose smoothed value
    exceeds an adaptive threshold (off-diagonal mean + 0.5 std)
    over runs of at least min_run cells are boosted, with the
    symmetric reflection applied. (The old version summed only
    offsets within +/-5 of the MAIN diagonal — local temporal
    continuity, not motif structure; a motif at distance 12 was
    invisible to it.)
    """
    from scipy.ndimage import uniform_filter1d
    N = SSM.shape[0]
    S = SSM.copy()

    # v1.2.1: detection is CONTRAST-INVARIANT. Cosine on positive
    # feature vectors saturates (off-diagonal values may all sit
    # in 0.97..1.0), so an absolute mean+std threshold can float
    # above even perfect-repetition bands. Detect on the
    # off-diagonal-normalized matrix instead.
    off_mask = ~np.eye(N, dtype=bool)
    off_vals = SSM[off_mask]
    o_min, o_max = float(off_vals.min()), float(off_vals.max())
    if o_max - o_min < 1e-9:
        return S          # featureless similarity field: nothing to detect
    Sn = np.clip((SSM - o_min) / (o_max - o_min), 0.0, 1.0)
    thr = max(0.6, float(Sn[off_mask].mean()) + 0.5 * float(Sn[off_mask].std()))

    boost_field = np.zeros_like(S)
    for k in range(1, N):
        d = np.diag(Sn, k)
        L = len(d)
        if L < min_run:
            continue
        sm  = uniform_filter1d(d, size=min(max(min_run, 3), L))
        hot = sm > thr
        if not np.any(hot):
            continue
        # keep only runs of >= min_run consecutive hot cells
        run = np.zeros(L, dtype=bool)
        i = 0
        while i < L:
            if hot[i]:
                j = i
                while j < L and hot[j]:
                    j += 1
                if j - i >= min_run:
                    run[i:j] = True
                i = j
            else:
                i += 1
        if not np.any(run):
            continue
        rows = np.arange(0, L)[run]
        cols = rows + k
        boost_field[rows, cols] = sm[run]
        boost_field[cols, rows] = sm[run]      # symmetric reflection

    mx = boost_field.max()
    if mx < 1e-12 or boost <= 0.0:
        return S                       # nothing detected / no boost
    boost_field /= mx
    # v1.3: detection runs on Sn (contrast-invariant), but the
    # OUTPUT is built from the ORIGINAL matrix: boost = 0 is
    # exactly identity and the transform is continuous in boost.
    # Detected bands are lifted multiplicatively; if the lift
    # exceeds 1, the off-diagonal is uniformly rescaled -- bands
    # win at the ceiling by everything else receding, while the
    # relative structure among non-band cells is preserved
    # exactly.
    W    = 1.0 + boost * boost_field
    Sout = S * W
    ovm  = Sout[off_mask].max()
    if ovm > 1.0:
        Sout = Sout / ovm
    Sout = np.clip(Sout, 0.0, 1.0)
    np.fill_diagonal(Sout, 1.0)
    return Sout


def transform_structure_warp(SSM, warp_amplitude=0.15, seed=1234):
    """
    Apply smooth nonlinear coordinate warp to SSM.
        SSM_warp(i, j) = SSM(i + f(i), j + f(j))
    where f is a seeded smooth perturbation field.
    Creates time symmetry distortions and phrase stretching.
    """
    if abs(warp_amplitude) <= 1e-12:
        return SSM.copy()

    from scipy.ndimage import map_coordinates

    N   = SSM.shape[0]
    rng = np.random.RandomState(seed)

    # Displacement field: superposition of low-frequency sines
    idx = np.arange(N, dtype=np.float64)
    f   = np.zeros(N)
    for k in range(1, 4):
        phase = rng.uniform(0, 2 * math.pi)
        amp   = warp_amplitude * N / (k * 2.0)
        f    += amp * np.sin(2 * math.pi * k * idx / N + phase)

    # Build warped coordinate grids
    ii, jj = np.meshgrid(idx, idx, indexing="ij")
    wi = np.clip(ii + f[ii.astype(int)], 0.0, N - 1.001)
    wj = np.clip(jj + f[jj.astype(int)], 0.0, N - 1.001)

    # Vectorized bilinear lookup via map_coordinates
    S = map_coordinates(SSM, [wi.ravel(), wj.ravel()],
                        order=1, mode="nearest").reshape(N, N)
    return _renorm(S)


def apply_ssm_transform(SSM, mode, args):
    if mode == "Blur":
        T = transform_blur(SSM, sigma=args.blur_sigma)
    elif mode == "Sharpen":
        T = transform_sharpen(SSM, gamma=args.sharpen_gamma)
    elif mode == "Diffusion":
        T = transform_diffusion(SSM, alpha=args.diffusion_alpha,
                                n_steps=args.diffusion_steps)
    elif mode == "MotifAmplify":
        T = transform_motif_amplify(SSM, boost=args.motif_boost)
    elif mode == "StructureWarp":
        T = transform_structure_warp(SSM,
                                     warp_amplitude=args.warp_amplitude,
                                     seed=args.transform_seed)
    else:
        # "Original": identity — the untransformed baseline
        T = SSM.copy()
    # v1.2: graded application
    a = float(np.clip(args.transform_amount, 0.0, 1.0))
    S = (1.0 - a) * SSM + a * T
    np.fill_diagonal(S, 1.0)
    return S


# ═══════════════════════════════════════════════════════════════════════════
# Stage 4 — Path navigation
# ═══════════════════════════════════════════════════════════════════════════

def navigate_path(SSM_mod, output_length, temperature, tabu_length, seed,
                  teleport_prob=0.02, visit_lambda=0.3):
    """
    Walk through events using modified SSM as a transition probability matrix.

    temperature:   0 → greedy (always most similar)
                   1 → fully stochastic (proportional sampling)

    tabu_length:    number of recent events to exclude from next-step choices.

    teleport_prob:  probability (0–1) of jumping to a random low-visited event
                    each step — prevents clique-locking, creates section changes.

    visit_lambda:   visit-penalty strength. Down-weights over-visited events:
                    w'(i) = w(i) / (1 + lambda * count(i))
                    Turns the walk into a structural dramaturgy engine.

    Returns list of event indices (0-based).
    """
    rng    = np.random.RandomState(seed)
    N      = SSM_mod.shape[0]
    output_length = min(output_length, 10000)

    path         = []
    tabu         = []
    visit_counts = np.zeros(N)
    n_teleports  = 0
    current      = int(rng.randint(0, N))

    for step in range(output_length):
        path.append(current)
        visit_counts[current] += 1
        if step == output_length - 1:
            break  # no inaudible transition after the final planned event

        # Teleport: jump to a low-visited event, but obey the same tabu
        # contract as an ordinary transition. v1.3 could teleport into a
        # taboo event and then skipped updating tabu history entirely.
        if teleport_prob > 0 and rng.random() < teleport_prob:
            candidates = [i for i in range(N) if i != current and i not in tabu]
            if not candidates:
                candidates = [i for i in range(N) if i != current]
            if not candidates:
                candidates = [current]
            inv_visits = np.zeros(N, dtype=np.float64)
            inv_visits[candidates] = 1.0 / (visit_counts[candidates] + 1.0)
            iv_sum = inv_visits.sum()
            if iv_sum > 0:
                inv_visits /= iv_sum
                next_ev = int(rng.choice(N, p=inv_visits))
                n_teleports += 1
                tabu.append(current)
                while len(tabu) > tabu_length:
                    tabu.pop(0)
                current = next_ev
                continue

        weights           = SSM_mod[current].copy()
        weights[current]  = 0.0
        for t in tabu:
            weights[t] = 0.0

        # Visit-penalty: down-weight over-visited events
        if visit_lambda > 0:
            weights = weights / (1.0 + visit_lambda * visit_counts)
            weights[current] = 0.0

        w_sum = weights.sum()
        if w_sum < 1e-12:
            candidates = [i for i in range(N) if i not in tabu and i != current]
            if not candidates:
                candidates = list(range(N))
            next_ev = int(rng.choice(candidates))
        else:
            weights /= w_sum
            if temperature < 1e-4:
                next_ev = int(np.argmax(weights))
            else:
                # Power temperature: p(i) ∝ w(i)^(1/T)
                # Musically intuitive: small T = peaky, large T = flat
                # Avoids log underflow and behaves smoothly near zero
                p = np.power(weights, 1.0 / max(temperature, 1e-6))
                p_sum = p.sum()
                if p_sum < 1e-12:
                    p = np.ones(N) / N
                else:
                    p /= p_sum
                next_ev = int(rng.choice(N, p=p))

        tabu.append(current)
        while len(tabu) > tabu_length:
            tabu.pop(0)
        current = next_ev

    return path, n_teleports


# ═══════════════════════════════════════════════════════════════════════════
# Optional SSM visualization (matplotlib — soft dependency)
# ═══════════════════════════════════════════════════════════════════════════

def save_ssm_pngs(SSM_orig, SSM_mod, mode, orig_path, mod_path):
    """Save original and modified SSM as two fixed-scale PNGs (optional)."""
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt

        for S, title, path in [
            (SSM_orig, "SSM — Original", orig_path),
            (SSM_mod, "SSM — %s" % mode, mod_path),
        ]:
            fig, ax = plt.subplots(figsize=(5, 4))
            ax.imshow(S, origin="lower", aspect="auto", cmap="inferno",
                      vmin=0, vmax=1)
            ax.set_title(title, fontsize=10)
            ax.set_xlabel("Event index")
            ax.set_ylabel("Event index")
            plt.tight_layout()
            plt.savefig(path, dpi=120)
            plt.close(fig)
        print("    SSM PNGs saved.")
    except ImportError:
        print("    matplotlib not available — SSM PNGs skipped.")


# ═══════════════════════════════════════════════════════════════════════════
# Metrics
# ═══════════════════════════════════════════════════════════════════════════

def compute_metrics(path, events, SSM_orig, SSM_mod, n_teleports):
    """v1.2: matrix-change and path-quality diagnostics."""
    N = SSM_orig.shape[0]

    off = ~np.eye(N, dtype=bool)
    fro = float(np.linalg.norm(SSM_mod - SSM_orig) /
                (np.linalg.norm(SSM_orig) + 1e-12))
    offdiag_orig = float(SSM_orig[off].mean())
    offdiag_mod  = float(SSM_mod[off].mean())

    trans = list(zip(path[:-1], path[1:])) if len(path) > 1 else []
    if trans:
        ps_orig = float(np.mean([SSM_orig[a, b] for a, b in trans]))
        ps_mod  = float(np.mean([SSM_mod[a, b] for a, b in trans]))
        chrono  = float(np.mean([abs(b - a) for a, b in trans]))
    else:
        ps_orig = ps_mod = chrono = 0.0

    # chronological run lengths (consecutive +1 steps)
    runs, cur = [], 1
    for a, b in trans:
        if b == a + 1:
            cur += 1
        else:
            runs.append(cur)
            cur = 1
    runs.append(cur)
    mean_run = float(np.mean(runs)) if runs else 1.0

    # Path entropy: distribution over events
    counts = np.zeros(N)
    for idx in path:
        counts[idx] += 1
    probs        = counts / (len(path) + 1e-12)
    path_entropy = float(-np.sum(probs * np.log(probs + 1e-12)))
    max_entropy = math.log(max(1, min(N, len(path))))
    norm_path_entropy = path_entropy / max_entropy if max_entropy > 1e-12 else 0.0

    # Diagonal energy — motif strength indicator, BOTH matrices
    def _diag_energy(S):
        s, c = 0.0, 0
        for offset in range(1, min(N, 20)):
            d = np.diag(S, offset)
            s += float(d.sum())
            c += len(d)
        return s / (c + 1e-12)
    diag_energy     = _diag_energy(SSM_orig)
    diag_energy_mod = _diag_energy(SSM_mod)

    # Peak coherent diagonal away from the immediate main diagonal: a simple
    # all-lag motif diagnostic that matches MotifAmplify better than the legacy
    # first-19-diagonals average alone.
    def _motif_band_peak(S):
        vals = []
        for offset in range(3, N):
            d = np.diag(S, offset)
            if len(d) >= 3:
                vals.append(float(np.mean(d)))
        return max(vals) if vals else 0.0
    motif_peak_orig = _motif_band_peak(SSM_orig)
    motif_peak_mod  = _motif_band_peak(SSM_mod)
    motif_contrast_orig = motif_peak_orig / (offdiag_orig + 1e-12)
    motif_contrast_mod  = motif_peak_mod  / (offdiag_mod  + 1e-12)

    # Estimated output duration
    out_dur = sum(
        float(events[min(idx, len(events) - 1)].get("duration", 0.25))
        for idx in path
    )

    unique_events   = int(np.sum(counts > 0))
    repetition_rate = round(1.0 - unique_events / (len(path) + 1e-12), 4)

    return {
        "plan_length":       len(path),
        "unique_events":     unique_events,
        "repetition_rate":   repetition_rate,
        "coverage":          round(unique_events / (N + 1e-12), 4),
        "path_entropy":      round(path_entropy, 4),
        "normalized_path_entropy": round(norm_path_entropy, 4),
        "diag_energy":       round(diag_energy, 4),
        "diag_energy_mod":   round(diag_energy_mod, 4),
        "motif_band_peak_orig": round(motif_peak_orig, 4),
        "motif_band_peak_mod":  round(motif_peak_mod, 4),
        "motif_band_contrast_orig": round(motif_contrast_orig, 4),
        "motif_band_contrast_mod":  round(motif_contrast_mod, 4),
        "frobenius_change":  round(fro, 4),
        "offdiag_mean_orig": round(offdiag_orig, 4),
        "offdiag_mean_mod":  round(offdiag_mod, 4),
        "path_sim_orig":     round(ps_orig, 4),
        "path_sim_mod":      round(ps_mod, 4),
        "mean_chrono_jump":  round(chrono, 2),
        "mean_run_length":   round(mean_run, 2),
        "teleport_rate":     round(n_teleports / (len(path) + 1e-12), 4),
        "planned_event_duration": round(out_dur, 3),
    }


# ═══════════════════════════════════════════════════════════════════════════
# Output writers
# ═══════════════════════════════════════════════════════════════════════════

def write_plan(path_out, event_path):
    with open(path_out, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["step", "event_index"])
        for step, idx in enumerate(event_path):
            writer.writerow([step, idx])


def write_stats(path_out, events, mode, metric, temperature,
                tabu_length, seed, metrics, args=None):
    with open(path_out, "w") as f:
        f.write("n_events=%d\n"      % len(events))
        f.write("mode=%s\n"          % mode)
        f.write("metric=%s\n"        % metric)
        f.write("temperature=%.4f\n" % temperature)
        f.write("tabu_length=%d\n"   % tabu_length)
        f.write("seed=%d\n"          % seed)
        if args is not None:
            # v1.3: full reproducibility record -- two very
            # different runs used to yield near-identical stats
            f.write("transform_amount=%.4f\n" % args.transform_amount)
            f.write("transform_seed=%d\n"     % args.transform_seed)
            f.write("blur_sigma=%.4f\n"       % args.blur_sigma)
            f.write("sharpen_gamma=%.4f\n"    % args.sharpen_gamma)
            f.write("diffusion_alpha=%.4f\n"  % args.diffusion_alpha)
            f.write("diffusion_steps=%d\n"    % args.diffusion_steps)
            f.write("motif_boost=%.4f\n"      % args.motif_boost)
            f.write("warp_amplitude=%.4f\n"   % args.warp_amplitude)
            f.write("teleport_prob=%.4f\n"    % args.teleport_prob)
            f.write("visit_lambda=%.4f\n"     % args.visit_lambda)
        for k, v in sorted(metrics.items()):
            f.write("%s=%s\n"        % (k, v))


# ═══════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════

def main():
    parser = argparse.ArgumentParser(
        description="SSM Morph Composer Engine")

    # I/O
    parser.add_argument("events_csv", help="Input: event table from Praat")
    parser.add_argument("plan_csv",   help="Output: new event order plan")
    parser.add_argument("stats_txt",  help="Output: run statistics")

    # Audio patches
    parser.add_argument("--patch_dir", default="",
        help="Directory containing mono event audio patches")
    parser.add_argument("--patch_prefix", default="patch_",
        help="Patch filename prefix (unique per run)")

    # SSM mode
    parser.add_argument("--mode",
        choices=["Blur", "Sharpen", "Diffusion", "MotifAmplify",
                 "StructureWarp", "Original"],
        default="Blur")
    parser.add_argument("--transform_amount", type=float, default=1.0,
        help="0 = original SSM, 1 = fully transformed (graded blend)")
    parser.add_argument("--transform_seed", type=int, default=-1,
        help="Seed for the StructureWarp field (-1 = use --seed)")
    parser.add_argument("--blur_sigma",      type=float, default=2.5)
    parser.add_argument("--sharpen_gamma",   type=float, default=3.0,
        help="Sharpen = monotone similarity-contrast reshaping; with "
             "visit penalty off it is largely redundant with low temperature")
    parser.add_argument("--diffusion_alpha", type=float, default=0.85)
    parser.add_argument("--diffusion_steps", type=int,   default=4)
    parser.add_argument("--motif_boost",     type=float, default=2.0)
    parser.add_argument("--warp_amplitude",  type=float, default=0.15)
    parser.add_argument("--metric",
        choices=["cosine", "euclidean"],
        default="cosine")

    # Path navigation
    parser.add_argument("--output_events", type=int,   default=300)
    parser.add_argument("--temperature",   type=float, default=0.3)
    parser.add_argument("--tabu_length",   type=int,   default=10)
    parser.add_argument("--seed",          type=int,   default=1234)
    parser.add_argument("--teleport_prob", type=float, default=0.02,
        help="Probability of teleporting to a low-visited event (default 0.02)")
    parser.add_argument("--visit_lambda",  type=float, default=0.3,
        help="Visit-penalty strength (default 0.3, 0=off)")

    # Optional SSM PNG export
    parser.add_argument("--draw_ssm",     type=int,   default=0)
    parser.add_argument("--ssm_orig_png", default="ssm_original.png")
    parser.add_argument("--ssm_mod_png",  default="ssm_modified.png")
    parser.add_argument("--ssm_orig_txt", default="",
        help="If set, write the REAL original SSM as matrix text (Praat display)")
    parser.add_argument("--ssm_mod_txt",  default="",
        help="If set, write the REAL transformed SSM as matrix text")

    args = parser.parse_args()

    # Clamp / validate (v1.2: tabu 0 allowed as the no-tabu baseline)
    args.output_events    = max(4,   min(10000, args.output_events))
    args.temperature      = max(0.0, min(1.0,   args.temperature))
    args.tabu_length      = max(0,   min(500,   args.tabu_length))
    args.teleport_prob    = max(0.0, min(1.0,   args.teleport_prob))
    args.visit_lambda     = max(0.0, args.visit_lambda)
    args.transform_amount = max(0.0, min(1.0,   args.transform_amount))
    args.blur_sigma        = max(0.0, args.blur_sigma)
    args.sharpen_gamma     = max(1e-6, args.sharpen_gamma)
    args.diffusion_alpha   = max(0.0, min(1.0, args.diffusion_alpha))
    args.diffusion_steps   = max(0, min(100, args.diffusion_steps))
    args.motif_boost       = max(0.0, args.motif_boost)
    args.warp_amplitude    = max(0.0, args.warp_amplitude)
    if args.transform_seed < 0:
        args.transform_seed = args.seed

    np.random.seed(args.seed)

    # ── Stage 1: Load events + extract features ───────────────────────────
    print("  [SSM 1/5] Loading events + extracting features...")

    events = []
    with open(args.events_csv, "r") as f:
        header = [h.strip() for h in f.readline().strip().split(",")]
        for line in f:
            line = line.strip()
            if not line:
                continue
            vals = line.split(",")
            row  = {}
            for h, v in zip(header, vals):
                v = v.strip()
                try:
                    row[h] = float(v)
                except ValueError:
                    row[h] = v
            events.append(row)

    N = len(events)
    print("    Events: %d" % N)
    if N < 2:
        print("FATAL: at least 2 events are required (got %d)." % N)
        sys.exit(1)
    if N < 4:
        print("    WARNING: only %d events — navigation will be trivial." % N)

    patch_dir = args.patch_dir if args.patch_dir else os.path.dirname(args.events_csv)
    X         = load_features(events, patch_dir, args.patch_prefix)
    print("    Feature matrix: %s" % str(X.shape))
    X, feature_keep = robust_normalize(X, metric=args.metric, return_keep=True)
    effective_feature_dims = int(np.sum(feature_keep))
    print("    Effective feature dimensions: %d/5" % effective_feature_dims)

    # ── Stage 2: Build SSM ────────────────────────────────────────────────
    print("  [SSM 2/5] Building SSM (%s, N=%d)..." % (args.metric, N))
    SSM_orig = build_ssm(X, metric=args.metric)
    print("    SSM range: [%.3f, %.3f]" % (SSM_orig.min(), SSM_orig.max()))
    _off = ~np.eye(SSM_orig.shape[0], dtype=bool)
    ssm_offdiag_std = float(SSM_orig[_off].std())
    if args.metric == "cosine" and ssm_offdiag_std < 0.05:
        print("    WARNING: cosine SSM nearly saturated "
              "(off-diag std %.4f) — events barely discriminated; "
              "consider --metric euclidean" % ssm_offdiag_std)

    # ── Stage 3: Apply transformation ────────────────────────────────────
    print("  [SSM 3/5] Applying transformation: %s..." % args.mode)
    SSM_mod = apply_ssm_transform(SSM_orig, args.mode, args)
    if args.transform_amount < 1.0:
        print("    Transform amount: %.2f (graded blend)" % args.transform_amount)

    # v1.2: export the REAL matrices for the Praat-side display
    if args.ssm_orig_txt:
        np.savetxt(args.ssm_orig_txt, SSM_orig, fmt="%.5f")
    if args.ssm_mod_txt:
        np.savetxt(args.ssm_mod_txt, SSM_mod, fmt="%.5f")
    print("    Modified SSM range: [%.3f, %.3f]" % (SSM_mod.min(), SSM_mod.max()))

    # Optional PNG export
    if args.draw_ssm:
        save_ssm_pngs(SSM_orig, SSM_mod, args.mode,
                      args.ssm_orig_png, args.ssm_mod_png)

    # ── Stage 4: Navigate path ────────────────────────────────────────────
    print("  [SSM 4/5] Navigating path (length=%d, temp=%.2f, tabu=%d)..." %
          (args.output_events, args.temperature, args.tabu_length))
    event_path, n_teleports = navigate_path(
        SSM_mod,
        output_length=args.output_events,
        temperature=args.temperature,
        tabu_length=args.tabu_length,
        seed=args.seed,
        teleport_prob=args.teleport_prob,
        visit_lambda=args.visit_lambda,
    )
    print("    Path: %d steps" % len(event_path))

    # ── Stage 5: Write outputs ────────────────────────────────────────────
    print("  [SSM 5/5] Writing outputs...")
    metrics = compute_metrics(event_path, events, SSM_orig, SSM_mod, n_teleports)
    metrics["ssm_offdiag_std"] = round(ssm_offdiag_std, 4)
    metrics["effective_feature_dims"] = effective_feature_dims
    write_plan(args.plan_csv, event_path)
    write_stats(args.stats_txt, events, args.mode, args.metric,
                args.temperature, args.tabu_length, args.seed, metrics, args)

    print("OK: %s" % args.plan_csv)
    print("    Planned events:  %.2f s (audio is shorter by the overlaps)" % metrics["planned_event_duration"])
    print("    Path entropy:    %.4f"   % metrics["path_entropy"])
    print("    Diagonal energy: %.4f"   % metrics["diag_energy"])


if __name__ == "__main__":
    main()
