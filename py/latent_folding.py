"""
latent_folding.py — Latent Folding (Topological Manifold Navigation)

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University

Usage (called by Praat, not directly):
    python latent_folding.py input.wav events.csv output.wav stats.txt
        latent_size learning_steps manifold_type fold_density
        curvature permutation_intensity symmetry speed seed

Manifold types:
    0 = Mirror   — reflection at boundaries
    1 = Möbius   — twist/polarity inversion at boundaries
    2 = Torus    — seamless wrap (end glued to beginning)

Architecture:
    Stage 1 — Load audio + event table
    Stage 2 — Extract log-mel patches (40 mels × 32 frames)
    Stage 3 — Train on-the-fly autoencoder (numpy, manual backprop)
    Stage 4 — Encode events → latent vectors Z
    Stage 5 — Folding engine: traverse topological manifold
    Stage 6 — Topological reconstruction with symmetry
    Stage 7 — Output + stats

No external downloads. No PyTorch/TensorFlow/sklearn.
"""

import sys
import math

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
N_MELS = 40
MEL_FRAMES = 32
XFADE_SEC = 0.008

MANIFOLD_MIRROR = 0
MANIFOLD_MOBIUS = 1
MANIFOLD_TORUS = 2
MANIFOLD_NAMES = ["Mirror", "Möbius", "Torus"]


def check_dependencies():
    missing = []
    for pkg in ["numpy", "soundfile", "scipy"]:
        try:
            __import__(pkg)
        except ImportError:
            missing.append(pkg)
    if missing:
        print("ERROR: Missing packages: " + ", ".join(missing),
              file=sys.stderr)
        sys.exit(1)


# ═══════════════════════════════════════════════════════════════════════════
# Stage 1 — Load
# ═══════════════════════════════════════════════════════════════════════════

def load_event_table(csv_path):
    events = []
    with open(csv_path, "r") as f:
        header = f.readline().strip().split(",")
        header = [h.strip() for h in header]
        for line in f:
            vals = line.strip().split(",")
            if len(vals) != len(header):
                continue
            row = {}
            for h, v in zip(header, vals):
                try:
                    row[h] = float(v)
                except ValueError:
                    row[h] = v.strip()
            events.append(row)
    return events


# ═══════════════════════════════════════════════════════════════════════════
# Stage 2 — Log-Mel Patches
# ═══════════════════════════════════════════════════════════════════════════

def build_mel_filterbank(sr, n_fft, n_mels):
    import numpy as np

    def hz_to_mel(hz):
        return 2595.0 * np.log10(1.0 + hz / 700.0)

    def mel_to_hz(mel):
        return 700.0 * (10.0 ** (mel / 2595.0) - 1.0)

    n_bins = n_fft // 2 + 1
    low_mel = hz_to_mel(20)
    high_mel = hz_to_mel(sr / 2)
    mel_points = np.linspace(low_mel, high_mel, n_mels + 2)
    hz_points = mel_to_hz(mel_points)
    bin_points = np.floor((n_fft + 1) * hz_points / sr).astype(int)
    bin_points = np.clip(bin_points, 0, n_bins - 1)

    fb = np.zeros((n_mels, n_bins))
    for m in range(1, n_mels + 1):
        fl = bin_points[m - 1]
        fc = bin_points[m]
        fr = bin_points[m + 1]
        for k in range(fl, fc):
            if fc > fl:
                fb[m - 1, k] = (k - fl) / (fc - fl)
        for k in range(fc, fr):
            if fr > fc:
                fb[m - 1, k] = (fr - k) / (fr - fc)
    return fb


def extract_mel_patches(audio_mono, sr, events):
    import numpy as np

    n_fft = 1024
    hop = 256
    window = np.hanning(n_fft)
    mel_fb = build_mel_filterbank(sr, n_fft, N_MELS)
    patches = []
    n_samples = len(audio_mono)

    for ev in events:
        s = int(float(ev["start_time"]) * sr)
        e = int(float(ev["end_time"]) * sr)
        s = max(0, min(s, n_samples))
        e = max(s + 1, min(e, n_samples))
        segment = audio_mono[s:e]

        n_frames = max(1, (len(segment) - n_fft) // hop + 1)
        mel_spec = np.zeros((N_MELS, n_frames))
        for fi in range(n_frames):
            start = fi * hop
            end = start + n_fft
            if end > len(segment):
                frame = np.zeros(n_fft)
                frame[:len(segment) - start] = segment[start:]
            else:
                frame = segment[start:end]
            frame = (frame * window[:len(frame)]
                     if len(frame) == n_fft else np.zeros(n_fft))
            spec = np.abs(np.fft.rfft(frame)) ** 2
            mel_energy = mel_fb.dot(spec)
            mel_spec[:, fi] = np.log(mel_energy + 1e-10)

        if n_frames >= MEL_FRAMES:
            offset = (n_frames - MEL_FRAMES) // 2
            patch = mel_spec[:, offset:offset + MEL_FRAMES]
        else:
            patch = np.zeros((N_MELS, MEL_FRAMES))
            offset = (MEL_FRAMES - n_frames) // 2
            patch[:, offset:offset + n_frames] = mel_spec
            for pi in range(offset):
                patch[:, pi] = mel_spec[:, 0]
            for pi in range(offset + n_frames, MEL_FRAMES):
                patch[:, pi] = mel_spec[:, -1]

        patches.append(patch.flatten())
    return np.array(patches, dtype=np.float64)


# ═══════════════════════════════════════════════════════════════════════════
# Stage 3 — Numpy Autoencoder
# ═══════════════════════════════════════════════════════════════════════════

class NumpyAutoencoder(object):
    def __init__(self, input_dim, hidden_dim, latent_dim, seed=42):
        import numpy as np
        self.rng = np.random.RandomState(seed)
        self.input_dim = input_dim
        self.hidden_dim = hidden_dim
        self.latent_dim = latent_dim

        s_eh = np.sqrt(2.0 / (input_dim + hidden_dim))
        s_hl = np.sqrt(2.0 / (hidden_dim + latent_dim))
        s_lh = np.sqrt(2.0 / (latent_dim + hidden_dim))
        s_ho = np.sqrt(2.0 / (hidden_dim + input_dim))

        self.W1 = self.rng.randn(input_dim, hidden_dim) * s_eh
        self.b1 = np.zeros(hidden_dim)
        self.W2 = self.rng.randn(hidden_dim, latent_dim) * s_hl
        self.b2 = np.zeros(latent_dim)
        self.W3 = self.rng.randn(latent_dim, hidden_dim) * s_lh
        self.b3 = np.zeros(hidden_dim)
        self.W4 = self.rng.randn(hidden_dim, input_dim) * s_ho
        self.b4 = np.zeros(input_dim)

        self.t = 0
        self.params = [self.W1, self.b1, self.W2, self.b2,
                       self.W3, self.b3, self.W4, self.b4]
        self.m = [np.zeros_like(p) for p in self.params]
        self.v = [np.zeros_like(p) for p in self.params]

    def _leaky(self, x, a=0.01):
        import numpy as np
        return np.where(x > 0, x, a * x)

    def _leaky_g(self, x, a=0.01):
        import numpy as np
        return np.where(x > 0, 1.0, a)

    def encode(self, X):
        self._h1_pre = X.dot(self.W1) + self.b1
        self._h1 = self._leaky(self._h1_pre)
        return self._h1.dot(self.W2) + self.b2

    def decode(self, Z):
        self._h2_pre = Z.dot(self.W3) + self.b3
        self._h2 = self._leaky(self._h2_pre)
        return self._h2.dot(self.W4) + self.b4

    def forward(self, X):
        Z = self.encode(X)
        self._Z = Z
        return self.decode(Z)

    def train_step(self, X, lr=0.001, noise_std=0.1, l2_reg=1e-4):
        import numpy as np
        batch = X.shape[0]
        X_noisy = X + noise_std * self.rng.randn(*X.shape)
        recon = self.forward(X_noisy)
        diff = recon - X
        loss = np.mean(diff ** 2)

        d_out = 2.0 * diff / (batch * self.input_dim)
        dW4 = self._h2.T.dot(d_out)
        db4 = np.sum(d_out, axis=0)
        d_h2 = d_out.dot(self.W4.T) * self._leaky_g(self._h2_pre)
        dW3 = self._Z.T.dot(d_h2)
        db3 = np.sum(d_h2, axis=0)
        d_Z = d_h2.dot(self.W3.T)
        dW2 = self._h1.T.dot(d_Z)
        db2 = np.sum(d_Z, axis=0)
        d_h1 = d_Z.dot(self.W2.T) * self._leaky_g(self._h1_pre)
        dW1 = X_noisy.T.dot(d_h1)
        db1 = np.sum(d_h1, axis=0)

        grads = [dW1 + l2_reg * self.W1, db1,
                 dW2 + l2_reg * self.W2, db2,
                 dW3 + l2_reg * self.W3, db3,
                 dW4 + l2_reg * self.W4, db4]

        self.t += 1
        beta1, beta2, eps = 0.9, 0.999, 1e-8
        for i, (p, g) in enumerate(zip(self.params, grads)):
            self.m[i] = beta1 * self.m[i] + (1 - beta1) * g
            self.v[i] = beta2 * self.v[i] + (1 - beta2) * (g ** 2)
            m_hat = self.m[i] / (1 - beta1 ** self.t)
            v_hat = self.v[i] / (1 - beta2 ** self.t)
            p -= lr * m_hat / (np.sqrt(v_hat) + eps)
        return loss

    def reconstruction_errors(self, X):
        import numpy as np
        recon = self.forward(X)
        return np.mean((recon - X) ** 2, axis=1)


def train_autoencoder(patches, latent_size, n_steps, seed):
    import numpy as np
    n_events, input_dim = patches.shape
    hidden_dim = max(latent_size * 2,
                     min(256, int(np.sqrt(input_dim * latent_size))))
    model = NumpyAutoencoder(input_dim, hidden_dim, latent_size, seed)

    mu = np.mean(patches, axis=0)
    sigma = np.std(patches, axis=0) + 1e-8
    X = (patches - mu) / sigma

    losses = []
    lr = 0.003
    noise_std = 0.3
    for step in range(n_steps):
        cn = noise_std * (1.0 - 0.5 * step / n_steps)
        cl = lr * (1.0 - 0.3 * step / n_steps)
        loss = model.train_step(X, lr=cl, noise_std=cn, l2_reg=1e-4)
        losses.append(loss)

    model._norm_mu = mu
    model._norm_sigma = sigma
    return model, losses


# ═══════════════════════════════════════════════════════════════════════════
# Stage 4 — Encode
# ═══════════════════════════════════════════════════════════════════════════

def encode_events(model, patches):
    import numpy as np
    X = (patches - model._norm_mu) / model._norm_sigma
    Z = model.encode(X)
    recon_err = model.reconstruction_errors(X)
    return Z, recon_err


# ═══════════════════════════════════════════════════════════════════════════
# Stage 5 — The Folding Engine
# ═══════════════════════════════════════════════════════════════════════════

def compute_manifold_boundaries(Z):
    """
    Compute the bounding box + principal axes of the latent space.
    Returns: center, per-dim min/max, principal axes via PCA.
    """
    import numpy as np

    center = np.mean(Z, axis=0)
    z_min = np.min(Z, axis=0)
    z_max = np.max(Z, axis=0)
    z_range = z_max - z_min + 1e-8

    # PCA for oriented boundaries
    Z_c = Z - center
    cov = Z_c.T.dot(Z_c) / max(1, len(Z) - 1)
    eigvals, eigvecs = np.linalg.eigh(cov)
    idx = np.argsort(eigvals)[::-1]
    axes = eigvecs[:, idx]

    # Project onto principal axes
    projections = Z_c.dot(axes)
    proj_min = np.min(projections, axis=0)
    proj_max = np.max(projections, axis=0)

    return center, z_min, z_max, z_range, axes, proj_min, proj_max


def fold_mirror(z, boundaries_min, boundaries_max, fold_density):
    """
    Mirror reflection: when coordinate exceeds boundary, reflect.
    Multiple folds create a zigzag pattern across the space.
    """
    import numpy as np

    z_folded = z.copy()
    for d in range(len(z)):
        lo = boundaries_min[d]
        hi = boundaries_max[d]
        span = hi - lo
        if span < 1e-8:
            continue

        # Scale fold boundaries by density
        fold_span = span / max(1, fold_density)
        val = z_folded[d]

        # Normalize to [0, fold_span] then reflect
        rel = val - lo
        # Number of half-periods
        period = 2.0 * fold_span
        if period > 1e-8:
            phase = rel % period
            if phase > fold_span:
                z_folded[d] = lo + (period - phase)
            else:
                z_folded[d] = lo + phase
    return z_folded


def fold_mobius(z, center, axes, proj_min, proj_max, fold_density,
               polarity):
    """
    Möbius twist: crossing a boundary flips the polarity of selected
    latent dimensions. The 'twist' inverts acoustic identity —
    bright→dark, noisy→tonal, etc.

    polarity: +1 or -1, flips each time a boundary is crossed.
    Returns: folded z, new polarity.
    """
    import numpy as np

    z_folded = z.copy()
    new_polarity = polarity

    # Project onto principal axis
    z_c = z - center
    proj = z_c.dot(axes)

    for d in range(min(len(z), len(proj_min))):
        lo = proj_min[d]
        hi = proj_max[d]
        span = hi - lo
        if span < 1e-8:
            continue

        fold_span = span / max(1, fold_density)
        val = proj[d]

        # Check boundary crossings
        n_crossings = int(abs(val - lo) / fold_span) if fold_span > 1e-8 else 0

        if n_crossings % 2 == 1:
            # Odd crossing: flip polarity for this dimension
            new_polarity = -polarity

    # Apply polarity: invert coordinates relative to center
    if new_polarity < 0:
        z_folded = center + (center - z_folded)

    return z_folded, new_polarity


def fold_torus(z, boundaries_min, boundaries_max):
    """
    Torus wrap: seamless loop where exceeding a boundary wraps to
    the other side. End of acoustic space = beginning.
    """
    import numpy as np

    z_folded = z.copy()
    for d in range(len(z)):
        lo = boundaries_min[d]
        hi = boundaries_max[d]
        span = hi - lo
        if span < 1e-8:
            continue
        z_folded[d] = lo + (z_folded[d] - lo) % span
    return z_folded


def apply_curvature_blend(z_original, z_folded, curvature, center):
    """
    Curvature controls fold sharpness:
    - High (→1): sharp fold, z_folded used directly
    - Low (→0): smooth Escher-like transition, blend with pre-fold
    """
    import numpy as np

    # Curvature as sigmoid-like blend
    # Sharp curvature → weight toward folded
    # Smooth curvature → weight toward original (pre-fold)
    alpha = curvature ** 0.5  # soften the response curve
    return z_original * (1.0 - alpha) + z_folded * alpha


def generate_folding_path(Z, events, manifold_type, fold_density,
                          curvature, permutation_intensity, symmetry,
                          speed, n_output_steps, seed):
    """
    Generate a path through the folding manifold.

    The observer traverses the latent space along the principal axis.
    At fold boundaries, the manifold topology transforms the
    observer's position, causing acoustic identity inversion.

    Returns: list of event indices for the output timeline,
             fold_events (list of (step, fold_type) pairs),
             spatial_path (list of latent positions for stats).
    """
    import numpy as np

    rng = np.random.RandomState(seed)
    n_events = len(Z)

    center, z_min, z_max, z_range, axes, proj_min, proj_max = \
        compute_manifold_boundaries(Z)

    # Pairwise distances for nearest-event lookup
    from scipy.spatial.distance import cdist
    dists = cdist(Z, Z, metric="euclidean")
    np.fill_diagonal(dists, np.inf)
    median_dist = np.median(dists[dists < np.inf])

    # Generate base trajectory along principal axis
    # with permutation-driven lateral drift
    primary_axis = axes[:, 0]
    secondary_axis = axes[:, 1] if Z.shape[1] > 1 else axes[:, 0]

    # Start at one extreme of the principal projection
    start_z = center + primary_axis * proj_min[0] * 0.9

    # If symmetry mode: generate first half, then fold-invert for second
    if symmetry > 0.5:
        half_steps = n_output_steps // 2
        full_steps = half_steps  # we'll mirror to get the rest
    else:
        half_steps = n_output_steps
        full_steps = n_output_steps

    # --- Generate first half (or full) path ---
    path_positions = []
    path_events = []
    fold_log = []
    usage_count = np.zeros(n_events, dtype=int)
    last_used = np.full(n_events, -100)

    # LRU anti-loop window. The Mirror manifold reverses direction at the
    # extremes and retraces its path, so the nearest-event picks tend to form
    # a short cycle (~4 events). A look-back of only 4 cannot see a 4-step
    # cycle closing, so it never penalises it. Widening to 8 lets the penalty
    # catch the loop and forces variety. (Verified: Mirror presets go from ~4
    # to 8-10 distinct events; Mobius/Torus unaffected since they don't loop.)
    lru_window = 8

    current_z = start_z.copy()
    polarity = 1  # for Möbius
    direction = 1.0  # +1 forward, -1 backward along principal axis

    # Step size based on speed and latent scale
    proj_range = proj_max[0] - proj_min[0]
    base_step = proj_range / max(1, full_steps) * speed * 2.0

    for step in range(full_steps):
        t = step / max(1, full_steps - 1)

        # --- Move along manifold ---
        # Primary motion along principal axis
        primary_motion = primary_axis * direction * base_step

        # Lateral drift (permutation intensity controls magnitude)
        drift_phase = t * fold_density * 2.0 * np.pi
        lateral_amp = permutation_intensity * median_dist * 0.3
        lateral_motion = secondary_axis * np.sin(drift_phase) * lateral_amp

        # Advance position
        raw_z = current_z + primary_motion + lateral_motion

        # --- Apply manifold fold ---
        if manifold_type == MANIFOLD_MIRROR:
            folded_z = fold_mirror(raw_z, z_min, z_max, fold_density)
            # Detect fold event
            if np.max(np.abs(folded_z - raw_z)) > median_dist * 0.1:
                fold_log.append((step, "mirror"))

        elif manifold_type == MANIFOLD_MOBIUS:
            folded_z, new_polarity = fold_mobius(
                raw_z, center, axes, proj_min, proj_max,
                fold_density, polarity)
            if new_polarity != polarity:
                fold_log.append((step, "twist"))
                polarity = new_polarity

        else:  # TORUS
            folded_z = fold_torus(raw_z, z_min, z_max)
            # Detect wrap event
            if np.max(np.abs(folded_z - raw_z)) > median_dist * 0.1:
                fold_log.append((step, "wrap"))

        # --- Apply curvature blend ---
        final_z = apply_curvature_blend(raw_z, folded_z, curvature,
                                        center)

        # --- Select nearest event (LRU) ---
        d_to_events = np.sqrt(np.sum((Z - final_z) ** 2, axis=1))
        lru_penalty = np.zeros(n_events)
        for i in range(n_events):
            recency = step - last_used[i]
            if recency < lru_window:
                lru_penalty[i] = (lru_window - recency) * median_dist * 0.4
        scores = d_to_events + lru_penalty

        chosen = int(np.argmin(scores))
        path_events.append(chosen)
        path_positions.append(final_z.copy())
        usage_count[chosen] += 1
        last_used[chosen] = step

        current_z = final_z.copy()

        # --- Direction reversal for Mirror at extremes ---
        if manifold_type == MANIFOLD_MIRROR:
            proj_val = np.dot(current_z - center, primary_axis)
            if proj_val > proj_max[0] * 0.9:
                direction = -1.0
            elif proj_val < proj_min[0] * 0.9:
                direction = 1.0

    # --- Apply symmetry: topological inverse of first half ---
    if symmetry > 0.5:
        second_half_events = []
        second_half_positions = []

        for si in range(len(path_events) - 1, -1, -1):
            orig_z = path_positions[si]

            # Topological inversion: reflect through center
            # This is NOT time-reversal — it's identity inversion
            inverted_z = center + (center - orig_z) * symmetry

            # Blend with permutation for non-trivial symmetry
            if permutation_intensity > 0.1:
                # Rotate inverted position slightly
                angle = permutation_intensity * np.pi * 0.25
                cos_a = np.cos(angle)
                sin_a = np.sin(angle)
                z_c = inverted_z - center
                # Rotate in principal plane
                proj1 = np.dot(z_c, primary_axis)
                proj2 = np.dot(z_c, secondary_axis)
                new_proj1 = proj1 * cos_a - proj2 * sin_a
                new_proj2 = proj1 * sin_a + proj2 * cos_a
                z_c = z_c + primary_axis * (new_proj1 - proj1) \
                      + secondary_axis * (new_proj2 - proj2)
                inverted_z = center + z_c

            # Find nearest event to inverted position
            d_to_events = np.sqrt(np.sum((Z - inverted_z) ** 2, axis=1))
            lru_penalty = np.zeros(n_events)
            total_step = len(path_events) + len(second_half_events)
            for i in range(n_events):
                recency = total_step - last_used[i]
                if recency < lru_window:
                    lru_penalty[i] = (lru_window - recency) * median_dist * 0.4
            scores = d_to_events + lru_penalty

            chosen = int(np.argmin(scores))
            second_half_events.append(chosen)
            second_half_positions.append(inverted_z.copy())
            usage_count[chosen] += 1
            last_used[chosen] = total_step

        path_events.extend(second_half_events)
        path_positions.extend(second_half_positions)
        fold_log.append((len(path_events) // 2, "symmetry_pivot"))

    return path_events, fold_log, path_positions


# ═══════════════════════════════════════════════════════════════════════════
# Stage 6 — Reconstruction
# ═══════════════════════════════════════════════════════════════════════════

def extract_event_clips(audio, events, sr):
    import numpy as np
    clips = []
    n_samples = len(audio) if audio.ndim == 1 else audio.shape[0]
    for ev in events:
        s = max(0, int(float(ev["start_time"]) * sr))
        e = min(n_samples, int(float(ev["end_time"]) * sr))
        if audio.ndim == 1:
            clips.append(audio[s:e].copy())
        else:
            clips.append(audio[s:e, :].copy())
    return clips


def reconstruct(clips, path_events, path_positions, Z, sr,
                target_samples, curvature):
    """
    Build output timeline from path events.
    Curvature affects crossfade behavior at fold boundaries:
    high curvature = hard cuts, low curvature = longer crossfades.
    """
    import numpy as np

    xfade_base = max(4, int(XFADE_SEC * sr))
    # Low curvature → longer crossfades (up to 4x)
    xfade = int(xfade_base * (1.0 + (1.0 - curvature) * 3.0))

    angle = np.linspace(0, np.pi / 2, xfade, dtype=np.float32)
    fade_in = np.sin(angle)
    fade_out = np.cos(angle)

    multichannel = clips[0].ndim > 1
    n_ch = clips[0].shape[1] if multichannel else 1

    # Estimate total length
    total = sum(len(clips[idx]) for idx in path_events)
    if multichannel:
        output = np.zeros((total + xfade * 2, n_ch), dtype=np.float32)
    else:
        output = np.zeros(total + xfade * 2, dtype=np.float32)

    wp = 0
    for ci, ev_idx in enumerate(path_events):
        clip = clips[ev_idx].copy().astype(np.float32)
        cl = len(clip)

        if cl < xfade * 3:
            end = wp + cl
            if end > len(output):
                pad = end - len(output)
                if multichannel:
                    output = np.pad(output, ((0, pad), (0, 0)))
                else:
                    output = np.pad(output, (0, pad))
            output[wp:end] += clip
            wp = end
            continue

        # Smoothing for large latent jumps
        if ci > 0:
            d = np.linalg.norm(Z[path_events[ci]] - Z[path_events[ci - 1]])
            max_d = np.max(np.linalg.norm(Z - np.mean(Z, axis=0),
                                          axis=1)) + 1e-8
            d_frac = d / max_d
            if d_frac > 0.6:
                fade_len = min(cl, int(sr * 0.03 * (1 + (1 - curvature))))
                if fade_len > 2:
                    fade = np.linspace(0.2, 1.0, fade_len)
                    if multichannel:
                        for ch in range(n_ch):
                            clip[:fade_len, ch] *= fade.astype(np.float32)
                    else:
                        clip[:fade_len] *= fade.astype(np.float32)

        if ci > 0:
            if multichannel:
                for ch in range(n_ch):
                    clip[:xfade, ch] *= fade_in
            else:
                clip[:xfade] *= fade_in
        if ci < len(path_events) - 1:
            if multichannel:
                for ch in range(n_ch):
                    clip[-xfade:, ch] *= fade_out
            else:
                clip[-xfade:] *= fade_out

        end = wp + cl
        if end > len(output):
            pad = end - len(output)
            if multichannel:
                output = np.pad(output, ((0, pad), (0, 0)))
            else:
                output = np.pad(output, (0, pad))
        output[wp:end] += clip
        wp = end - xfade if ci < len(path_events) - 1 else end

    output = output[:wp]

    # Click smoothing (vectorized)
    if len(output) > 4:
        local_rms = max(0.001, np.sqrt(np.mean(output.flatten() ** 2)))
        threshold = local_rms * 4.0
        if multichannel:
            for ch in range(n_ch):
                diffs = np.abs(np.diff(output[:, ch]))
                click_idx = np.where(diffs > threshold)[0]
                for i in click_idx:
                    if 0 < i < len(output) - 1:
                        lo = max(0, i - 2)
                        hi = min(len(output), i + 3)
                        output[i, ch] = np.median(output[lo:hi, ch])
        else:
            diffs = np.abs(np.diff(output))
            click_idx = np.where(diffs > threshold)[0]
            for i in click_idx:
                if 0 < i < len(output) - 1:
                    lo = max(0, i - 2)
                    hi = min(len(output), i + 3)
                    output[i] = np.median(output[lo:hi])

    # Duration enforcement
    if target_samples > 0:
        if len(output) > target_samples:
            output = output[:target_samples]
        elif len(output) < target_samples:
            pad = target_samples - len(output)
            if multichannel:
                output = np.pad(output, ((0, pad), (0, 0)))
            else:
                output = np.pad(output, (0, pad))

    peak = np.max(np.abs(output))
    if peak > 0.95:
        output *= (0.95 / peak)

    return output


# ═══════════════════════════════════════════════════════════════════════════
# Stage 7 — Stats
# ═══════════════════════════════════════════════════════════════════════════

def write_stats(path, events, path_events, fold_log, Z,
                losses, sr, out_duration, manifold_type,
                fold_density, curvature, permutation_intensity,
                symmetry, warnings, path_positions=None):
    import numpy as np

    n_events = len(events)
    n_steps = len(path_events)
    unique = len(set(path_events))
    rep_rate = (n_steps - unique) / max(1, n_steps)

    # Usage distribution
    usage = np.zeros(n_events, dtype=int)
    for idx in path_events:
        usage[idx] += 1

    # Latent travel
    travel_dists = []
    for i in range(1, len(path_events)):
        d = np.linalg.norm(Z[path_events[i]] - Z[path_events[i - 1]])
        travel_dists.append(d)
    avg_travel = np.mean(travel_dists) if travel_dists else 0

    # Fold events
    n_folds = len([f for f in fold_log if f[1] != "symmetry_pivot"])
    n_twists = len([f for f in fold_log if f[1] == "twist"])
    n_mirrors = len([f for f in fold_log if f[1] == "mirror"])
    n_wraps = len([f for f in fold_log if f[1] == "wrap"])
    has_symmetry = any(f[1] == "symmetry_pivot" for f in fold_log)

    # Palindromic check: compare first/second half event selection
    palindromic_score = 0.0
    if has_symmetry and n_steps > 4:
        half = n_steps // 2
        first_half = set(path_events[:half])
        second_half = set(path_events[half:])
        diff = len(second_half - first_half)
        palindromic_score = diff / max(1, len(second_half))

    # ── PCA projection for visualization ──────────────────────────────
    ev_x = []
    ev_y = []
    traj_x = []
    traj_y = []
    fold_markers = []  # (x, y, type) for each fold event

    if path_positions is not None and len(path_positions) > 0:
        traj_arr = np.array(path_positions)
        all_points = np.vstack([Z, traj_arr])

        mean_pt = np.mean(all_points, axis=0)
        centered = all_points - mean_pt
        if centered.shape[1] >= 2:
            U, S, Vt = np.linalg.svd(centered, full_matrices=False)
            proj = centered.dot(Vt[:2].T)
        else:
            proj = np.column_stack([centered[:, 0], np.zeros(len(centered))])

        n_ev = len(Z)
        ev_proj = proj[:n_ev]
        traj_proj = proj[n_ev:]

        ev_x = ev_proj[:, 0].tolist()
        ev_y = ev_proj[:, 1].tolist()
        traj_x = traj_proj[:, 0].tolist()
        traj_y = traj_proj[:, 1].tolist()

        # Map fold_log steps to trajectory coordinates
        fold_step_map = {f[0]: f[1] for f in fold_log
                         if f[1] != "symmetry_pivot"}
        for step, ftype in fold_step_map.items():
            if step < len(traj_x):
                fold_markers.append((traj_x[step], traj_y[step], ftype))

    with open(path, "w") as f:
        f.write("n_events=%d\n" % n_events)
        f.write("n_output_steps=%d\n" % n_steps)
        f.write("unique_events=%d\n" % unique)
        f.write("repetition_rate=%.3f\n" % rep_rate)
        f.write("avg_latent_travel=%.4f\n" % avg_travel)
        f.write("output_duration=%.3f\n" % out_duration)
        f.write("manifold=%s\n" % MANIFOLD_NAMES[manifold_type])
        f.write("fold_density=%d\n" % fold_density)
        f.write("curvature=%.2f\n" % curvature)
        f.write("permutation=%.2f\n" % permutation_intensity)
        f.write("symmetry=%.2f\n" % symmetry)
        f.write("n_fold_events=%d\n" % n_folds)
        f.write("n_mirrors=%d\n" % n_mirrors)
        f.write("n_twists=%d\n" % n_twists)
        f.write("n_wraps=%d\n" % n_wraps)
        f.write("has_symmetry=%d\n" % int(has_symmetry))
        f.write("palindromic_score=%.3f\n" % palindromic_score)
        f.write("final_loss=%.6f\n" % (losses[-1] if losses else 0))
        f.write("initial_loss=%.6f\n" % (losses[0] if losses else 0))

        durations = [float(e["end_time"]) - float(e["start_time"])
                     for e in events]
        f.write("mean_event_dur=%.3f\n" % np.mean(durations))

        top3 = np.argsort(usage)[-3:][::-1]
        for rank, idx in enumerate(top3):
            f.write("top_event_%d=%d|%d_uses\n" % (
                rank, idx, usage[idx]))

        # ── Folding path trajectory (PCA-projected) ───────────────────
        # Event positions
        f.write("n_ev_pts=%d\n" % len(ev_x))
        for ei in range(len(ev_x)):
            f.write("fev_%d=%.4f,%.4f\n" % (ei, ev_x[ei], ev_y[ei]))

        # Trajectory (subsample to max 150 points)
        n_traj = len(traj_x)
        stride = max(1, n_traj // 150)
        sampled_idx = list(range(0, n_traj, stride))
        if n_traj - 1 not in sampled_idx:
            sampled_idx.append(n_traj - 1)
        n_out = len(sampled_idx)
        f.write("n_traj_pts=%d\n" % n_out)
        for ti, si in enumerate(sampled_idx):
            f.write("ftr_%d=%.4f,%.4f\n" % (ti, traj_x[si], traj_y[si]))

        # Fold markers
        n_fm = min(len(fold_markers), 100)
        f.write("n_fold_markers=%d\n" % n_fm)
        for fi in range(n_fm):
            fx, fy, ft = fold_markers[fi]
            f.write("fm_%d=%.4f,%.4f,%s\n" % (fi, fx, fy, ft))

        if warnings:
            f.write("warning=%s\n" % "; ".join(warnings))


# ═══════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════

def main():
    if len(sys.argv) != 14:
        print("Usage: python latent_folding.py "
              "input.wav events.csv output.wav stats.txt "
              "latent_size learning_steps manifold_type fold_density "
              "curvature permutation_intensity symmetry speed seed",
              file=sys.stderr)
        sys.exit(1)

    check_dependencies()

    import numpy as np
    import soundfile as sf

    in_wav      = sys.argv[1]
    events_csv  = sys.argv[2]
    out_wav     = sys.argv[3]
    stats_file  = sys.argv[4]
    latent_size = int(sys.argv[5])
    n_steps     = int(sys.argv[6])
    manifold    = int(sys.argv[7])
    fold_dens   = int(sys.argv[8])
    curvature   = float(sys.argv[9])
    perm_int    = float(sys.argv[10])
    symmetry    = float(sys.argv[11])
    speed       = float(sys.argv[12])
    seed        = int(sys.argv[13])

    # Clamp
    latent_size = max(2, min(32, latent_size))
    n_steps     = max(10, min(500, n_steps))
    manifold    = max(0, min(2, manifold))
    fold_dens   = max(1, min(12, fold_dens))
    curvature   = max(0.0, min(1.0, curvature))
    perm_int    = max(0.0, min(1.0, perm_int))
    symmetry    = max(0.0, min(1.0, symmetry))
    speed       = max(0.1, min(3.0, speed))

    np.random.seed(seed)
    warnings = []

    # ---- Load ----
    print("  [Py 1/7] Loading audio + event table...")
    audio, sr = sf.read(in_wav, always_2d=False)
    audio = np.asarray(audio, dtype=np.float32)
    events = load_event_table(events_csv)
    n_samples = len(audio) if audio.ndim == 1 else audio.shape[0]
    orig_dur = n_samples / sr
    target_samples = n_samples

    print("    Audio: %.2fs  SR=%d  Shape=%s" % (orig_dur, sr, audio.shape))
    print("    Events: %d" % len(events))

    if len(events) < 3:
        warnings.append("Too few events (%d)" % len(events))

    # ---- Mel patches ----
    print("  [Py 2/7] Extracting log-mel patches...")
    audio_mono = audio if audio.ndim == 1 else audio[:, 0]
    patches = extract_mel_patches(audio_mono.astype(np.float64), sr, events)

    # ---- Train AE ----
    print("  [Py 3/7] Training autoencoder (%d steps, latent=%d)..." %
          (n_steps, latent_size))
    model, losses = train_autoencoder(patches, latent_size, n_steps, seed)
    loss_ratio = losses[-1] / (losses[0] + 1e-12) if losses else 1.0
    print("    Loss: %.6f → %.6f (%.1f%% reduction)" % (
        losses[0], losses[-1], (1 - loss_ratio) * 100))

    if loss_ratio > 0.95:
        warnings.append("Autoencoder did not converge well")

    # ---- Encode ----
    print("  [Py 4/7] Encoding events → latent space...")
    Z, recon_err = encode_events(model, patches)

    # ---- Compute output event count ----
    mean_ev_dur = np.mean([float(e["end_time"]) - float(e["start_time"])
                           for e in events])
    n_output_steps = max(3, int(orig_dur / mean_ev_dur * 1.0))
    n_output_steps = min(n_output_steps, len(events) * 10)

    print("    Output steps: %d (%.2f events/s)" %
          (n_output_steps, n_output_steps / orig_dur))

    # ---- Folding engine ----
    print("  [Py 5/7] Folding manifold (%s, density=%d, "
          "curvature=%.2f)..." % (MANIFOLD_NAMES[manifold],
                                   fold_dens, curvature))

    path_events, fold_log, path_positions = generate_folding_path(
        Z, events, manifold, fold_dens, curvature, perm_int,
        symmetry, speed, n_output_steps, seed)

    n_fold_events = len([f for f in fold_log
                         if f[1] != "symmetry_pivot"])
    print("    Path: %d steps | %d/%d unique | %d fold events" %
          (len(path_events), len(set(path_events)), len(events),
           n_fold_events))

    if symmetry > 0.5:
        print("    Symmetry: palindromic structure enabled "
              "(first half ↔ inverted second half)")

    # ---- Reconstruct ----
    print("  [Py 6/7] Reconstructing timeline...")
    clips = extract_event_clips(audio, events, sr)
    output = reconstruct(clips, path_events, path_positions, Z, sr,
                         target_samples, curvature)

    sf.write(out_wav, output, sr)
    out_dur = len(output) / sr if output.ndim == 1 else output.shape[0] / sr

    # ---- Stats ----
    print("  [Py 7/7] Writing stats...")
    write_stats(stats_file, events, path_events, fold_log, Z,
                losses, sr, out_dur, manifold, fold_dens, curvature,
                perm_int, symmetry, warnings,
                path_positions=path_positions)

    print("    Output: %.2fs | Peak: %.4f" %
          (out_dur, np.max(np.abs(output))))
    print("OK: wrote %s" % out_wav)


if __name__ == "__main__":
    main()
