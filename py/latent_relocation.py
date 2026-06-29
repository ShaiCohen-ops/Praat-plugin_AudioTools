"""
latent_relocation.py — Online Latent-Event Relocation
(Deep Thermodynamic Recomposition)

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University

Usage (called by Praat, not directly):
    python latent_relocation.py input.wav events.csv output.wav
        stats.txt learning_steps latent_size relocation_intensity
        stability_bias novelty_bias preserve_duration seed

Architecture:
    Stage 1 — Load audio + event table from Praat
    Stage 2 — Extract fixed-size log-mel patches per event
    Stage 3 — Train lightweight autoencoder on-the-fly (numpy only)
    Stage 4 — Encode events → latent vectors → thermodynamic fields
    Stage 5 — Regime assignment + event relocation
    Stage 6 — Time-domain reconstruction with click-free splicing
    Stage 7 — Output + report

No external model downloads. No internet. No PyTorch/TensorFlow.
Autoencoder is pure numpy with manual backprop + Adam optimizer.
"""

import sys
import os
import math

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
REGIME_CRYSTAL = 0
REGIME_FLUID = 1
REGIME_GAS = 2
REGIME_PLASMA = 3
REGIME_NAMES = ["Crystal", "Fluid", "Gas", "Plasma"]

N_MELS = 40
MEL_FRAMES = 32        # fixed temporal frames per event patch
XFADE_SEC = 0.008


def check_dependencies():
    """Verify required packages are installed."""
    missing = []
    for pkg in ["numpy", "soundfile", "scipy"]:
        try:
            __import__(pkg)
        except ImportError:
            missing.append(pkg)
    if missing:
        print("ERROR: Missing packages: " + ", ".join(missing),
              file=sys.stderr)
        print("Install with:  pip install " + " ".join(missing),
              file=sys.stderr)
        sys.exit(1)


# ═══════════════════════════════════════════════════════════════════════════
# Stage 1 — Load Event Table
# ═══════════════════════════════════════════════════════════════════════════

def load_event_table(csv_path):
    """
    Load Praat-exported event table. Expected columns:
    start_time, end_time, pitch_median, pitch_stability,
    intensity_mean, attack_slope, hnr_mean
    """
    import numpy as np

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
                    row[h] = 0.0
            events.append(row)
    return events


# ═══════════════════════════════════════════════════════════════════════════
# Stage 2 — Log-Mel Patch Extraction
# ═══════════════════════════════════════════════════════════════════════════

def build_mel_filterbank(sr, n_fft, n_mels):
    """Build a mel-scale filterbank matrix (n_mels × n_fft//2+1)."""
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

    filterbank = np.zeros((n_mels, n_bins))
    for m in range(1, n_mels + 1):
        f_left = bin_points[m - 1]
        f_center = bin_points[m]
        f_right = bin_points[m + 1]

        for k in range(f_left, f_center):
            if f_center > f_left:
                filterbank[m - 1, k] = (k - f_left) / (f_center - f_left)
        for k in range(f_center, f_right):
            if f_right > f_center:
                filterbank[m - 1, k] = (f_right - k) / (f_right - f_center)

    return filterbank


def extract_mel_patches(audio_mono, sr, events):
    """
    For each event, compute a log-mel spectrogram and resize to
    (N_MELS × MEL_FRAMES) via padding or truncation.
    Returns array of shape (n_events, N_MELS * MEL_FRAMES).
    """
    import numpy as np

    n_fft = 1024
    hop = 256
    window = np.hanning(n_fft)
    mel_fb = build_mel_filterbank(sr, n_fft, N_MELS)

    patches = []
    n_samples = len(audio_mono)

    for ev in events:
        s = int(ev["start_time"] * sr)
        e = int(ev["end_time"] * sr)
        s = max(0, min(s, n_samples))
        e = max(s + 1, min(e, n_samples))

        segment = audio_mono[s:e]

        # STFT
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
            frame = frame * window[:len(frame)] if len(frame) == n_fft else np.zeros(n_fft)
            spec = np.abs(np.fft.rfft(frame)) ** 2
            mel_energy = mel_fb.dot(spec)
            mel_spec[:, fi] = np.log(mel_energy + 1e-10)

        # Resize to fixed MEL_FRAMES
        if n_frames >= MEL_FRAMES:
            # Truncate (take center)
            offset = (n_frames - MEL_FRAMES) // 2
            patch = mel_spec[:, offset:offset + MEL_FRAMES]
        else:
            # Pad with edge values
            patch = np.zeros((N_MELS, MEL_FRAMES))
            offset = (MEL_FRAMES - n_frames) // 2
            patch[:, offset:offset + n_frames] = mel_spec
            # Mirror-pad edges
            for pi in range(offset):
                patch[:, pi] = mel_spec[:, 0]
            for pi in range(offset + n_frames, MEL_FRAMES):
                patch[:, pi] = mel_spec[:, -1]

        patches.append(patch.flatten())

    return np.array(patches, dtype=np.float64)


# ═══════════════════════════════════════════════════════════════════════════
# Stage 3 — Numpy Autoencoder (no PyTorch/TF)
# ═══════════════════════════════════════════════════════════════════════════

class NumpyAutoencoder(object):
    """
    Simple MLP autoencoder with:
    - Encoder: input → hidden → latent
    - Decoder: latent → hidden → output
    - Leaky-ReLU hidden activations; linear decoder output (for MSE)
    - Denoising: corrupt input with Gaussian noise
    - L2 regularization
    - Adam optimizer

    All pure numpy — no external ML framework needed.
    """

    def __init__(self, input_dim, hidden_dim, latent_dim, seed=42):
        import numpy as np

        self.rng = np.random.RandomState(seed)
        self.input_dim = input_dim
        self.hidden_dim = hidden_dim
        self.latent_dim = latent_dim

        # Xavier initialization
        scale_eh = np.sqrt(2.0 / (input_dim + hidden_dim))
        scale_hl = np.sqrt(2.0 / (hidden_dim + latent_dim))
        scale_lh = np.sqrt(2.0 / (latent_dim + hidden_dim))
        scale_ho = np.sqrt(2.0 / (hidden_dim + input_dim))

        # Encoder weights
        self.W1 = self.rng.randn(input_dim, hidden_dim) * scale_eh
        self.b1 = np.zeros(hidden_dim)
        self.W2 = self.rng.randn(hidden_dim, latent_dim) * scale_hl
        self.b2 = np.zeros(latent_dim)

        # Decoder weights
        self.W3 = self.rng.randn(latent_dim, hidden_dim) * scale_lh
        self.b3 = np.zeros(hidden_dim)
        self.W4 = self.rng.randn(hidden_dim, input_dim) * scale_ho
        self.b4 = np.zeros(input_dim)

        # Adam state
        self._init_adam()

    def _init_adam(self):
        """Initialize Adam optimizer moment estimates."""
        import numpy as np
        self.t = 0
        self.params = [self.W1, self.b1, self.W2, self.b2,
                       self.W3, self.b3, self.W4, self.b4]
        self.m = [np.zeros_like(p) for p in self.params]
        self.v = [np.zeros_like(p) for p in self.params]

    def _leaky_relu(self, x, alpha=0.01):
        import numpy as np
        return np.where(x > 0, x, alpha * x)

    def _leaky_relu_grad(self, x, alpha=0.01):
        import numpy as np
        return np.where(x > 0, 1.0, alpha)

    def encode(self, X):
        """Encode X → latent Z. X shape: (batch, input_dim)."""
        import numpy as np
        self._h1_pre = X.dot(self.W1) + self.b1
        self._h1 = self._leaky_relu(self._h1_pre)
        Z = self._h1.dot(self.W2) + self.b2
        return Z

    def decode(self, Z):
        """Decode Z → reconstruction. Z shape: (batch, latent_dim)."""
        import numpy as np
        self._h2_pre = Z.dot(self.W3) + self.b3
        self._h2 = self._leaky_relu(self._h2_pre)
        out = self._h2.dot(self.W4) + self.b4
        return out

    def forward(self, X):
        """Full forward pass: X → Z → reconstruction."""
        Z = self.encode(X)
        self._Z = Z
        recon = self.decode(Z)
        return recon

    def train_step(self, X, lr=0.001, noise_std=0.1, l2_reg=1e-4):
        """
        One training step with denoising + L2 regularization.
        Returns MSE loss.
        """
        import numpy as np

        batch = X.shape[0]

        # Denoising: add noise to input
        X_noisy = X + noise_std * self.rng.randn(*X.shape)

        # Forward
        recon = self.forward(X_noisy)

        # MSE loss against clean target
        diff = recon - X
        loss = np.mean(diff ** 2)

        # Backward: dL/d(recon) = 2 * diff / N
        d_out = 2.0 * diff / (batch * self.input_dim)

        # Decoder backward
        dW4 = self._h2.T.dot(d_out)
        db4 = np.sum(d_out, axis=0)

        d_h2 = d_out.dot(self.W4.T)
        d_h2 *= self._leaky_relu_grad(self._h2_pre)

        dW3 = self._Z.T.dot(d_h2)
        db3 = np.sum(d_h2, axis=0)

        d_Z = d_h2.dot(self.W3.T)

        # Encoder backward
        dW2 = self._h1.T.dot(d_Z)
        db2 = np.sum(d_Z, axis=0)

        d_h1 = d_Z.dot(self.W2.T)
        d_h1 *= self._leaky_relu_grad(self._h1_pre)

        dW1 = X_noisy.T.dot(d_h1)
        db1 = np.sum(d_h1, axis=0)

        # L2 regularization gradients
        grads = [dW1 + l2_reg * self.W1, db1,
                 dW2 + l2_reg * self.W2, db2,
                 dW3 + l2_reg * self.W3, db3,
                 dW4 + l2_reg * self.W4, db4]

        # Adam update
        self.t += 1
        beta1, beta2, eps = 0.9, 0.999, 1e-8
        new_params = []

        for i, (param, grad) in enumerate(zip(self.params, grads)):
            self.m[i] = beta1 * self.m[i] + (1 - beta1) * grad
            self.v[i] = beta2 * self.v[i] + (1 - beta2) * (grad ** 2)
            m_hat = self.m[i] / (1 - beta1 ** self.t)
            v_hat = self.v[i] / (1 - beta2 ** self.t)
            param -= lr * m_hat / (np.sqrt(v_hat) + eps)
            new_params.append(param)

        (self.W1, self.b1, self.W2, self.b2,
         self.W3, self.b3, self.W4, self.b4) = new_params
        self.params = new_params

        return loss

    def reconstruction_errors(self, X):
        """Per-sample MSE reconstruction error."""
        import numpy as np
        recon = self.forward(X)
        return np.mean((recon - X) ** 2, axis=1)


def train_autoencoder(patches, latent_size, n_steps, seed):
    """
    Train autoencoder on event patches.

    Args:
        patches: (n_events, feature_dim) normalized mel patches
        latent_size: bottleneck dimension
        n_steps: training iterations
        seed: for reproducibility

    Returns:
        model: trained NumpyAutoencoder
        losses: list of training losses
    """
    import numpy as np

    n_events, input_dim = patches.shape

    # Hidden dim: geometric mean between input and latent
    hidden_dim = max(latent_size * 2,
                     min(256, int(np.sqrt(input_dim * latent_size))))

    model = NumpyAutoencoder(input_dim, hidden_dim, latent_size, seed)

    # Normalize patches
    mu = np.mean(patches, axis=0)
    sigma = np.std(patches, axis=0) + 1e-8
    X = (patches - mu) / sigma

    # Training
    losses = []
    lr = 0.003
    noise_std = 0.3  # strong denoising to prevent identity copying

    for step in range(n_steps):
        # Decay noise and LR
        current_noise = noise_std * (1.0 - 0.5 * step / n_steps)
        current_lr = lr * (1.0 - 0.3 * step / n_steps)

        loss = model.train_step(X, lr=current_lr,
                                noise_std=current_noise, l2_reg=1e-4)
        losses.append(loss)

    # Store normalization for encoding
    model._norm_mu = mu
    model._norm_sigma = sigma

    return model, losses


# ═══════════════════════════════════════════════════════════════════════════
# Stage 4 — Latent Space → Thermodynamic Fields
# ═══════════════════════════════════════════════════════════════════════════

def compute_latent_fields(model, patches, events, stability_bias,
                          novelty_bias):
    """
    Encode events → latent vectors, then derive thermodynamic fields:

    - latent_temperature: local instability / novelty
      (reconstruction error + distance to neighbors in latent space)
    - latent_affinity: pairwise similarity matrix
    - regimes: Crystal / Fluid / Gas / Plasma from temp + stability

    Returns:
        Z_latent: (n, latent_dim) latent vectors
        temperature: (n,) per-event temperature
        affinity: (n, n) similarity matrix
        regimes: (n,) regime labels
        recon_error: (n,) per-event reconstruction error
    """
    import numpy as np

    # Normalize and encode
    X = (patches - model._norm_mu) / model._norm_sigma
    Z_latent = model.encode(X)
    recon_error = model.reconstruction_errors(X)

    n = len(events)

    # --- Latent temperature ---
    # Component 1: reconstruction error (novelty = hard to reconstruct)
    err_norm = _safe_normalize(recon_error)

    # Component 2: distance to k nearest neighbors in latent space
    from scipy.spatial.distance import cdist
    dists = cdist(Z_latent, Z_latent, metric="euclidean")
    np.fill_diagonal(dists, np.inf)
    k = min(3, n - 1)
    knn_dists = np.zeros(n)
    if k >= 1:
        for i in range(n):
            sorted_d = np.sort(dists[i])
            knn_dists[i] = np.mean(sorted_d[:k])
    # n <= 1: no neighbors exist, so knn_dists stays zeros. (Without this
    # guard, sorted_d[:0] is empty and np.mean([]) is NaN, which would
    # poison temperature and the mean_temperature stat.)
    knn_norm = _safe_normalize(knn_dists)

    # Component 3: Praat stability metrics (inverted = instability)
    pitch_stab = np.array([ev.get("pitch_stability", 0.5) for ev in events])
    instability = 1.0 - np.clip(pitch_stab, 0, 1)

    # Weighted temperature
    # Temperature = latent novelty/isolation + a fixed pitch-instability
    # contribution. Decoupled from stability_bias (v1.4): previously
    # stability_bias re-weighted this blend, which made "more stable"
    # paradoxically route unstable events into the high-displacement
    # regimes. stability_bias now acts ONLY as an anchor in relocate_events,
    # so its relationship to the result is monotonic.
    temperature = 0.4 * err_norm + 0.4 * knn_norm + 0.2 * instability
    temperature = np.clip(temperature, 0, 1)

    # --- Affinity matrix ---
    # Gaussian kernel on latent distances
    finite_d = dists[dists < np.inf]
    sigma = (np.median(finite_d) if finite_d.size > 0 else 1.0) + 1e-6
    affinity = np.exp(-dists ** 2 / (2 * sigma ** 2))
    np.fill_diagonal(affinity, 1.0)

    # --- Regime assignment ---
    regimes = _assign_regimes(temperature, pitch_stab)

    return Z_latent, temperature, affinity, regimes, recon_error


def _safe_normalize(x):
    """Normalize to [0, 1]."""
    import numpy as np
    mn, mx = np.min(x), np.max(x)
    if mx - mn < 1e-12:
        return np.zeros_like(x)
    return (x - mn) / (mx - mn)


def _assign_regimes(temperature, pitch_stability):
    """
    Assign thermodynamic regimes from temperature + stability.
    Crystal: low temp, high stability
    Fluid: moderate temp
    Gas: high temp, some stability
    Plasma: very high temp, low stability
    """
    import numpy as np

    n = len(temperature)
    regimes = np.zeros(n, dtype=int)

    for i in range(n):
        t = temperature[i]
        s = pitch_stability[i] if i < len(pitch_stability) else 0.5

        # Combined score
        score = t * 0.7 + (1.0 - s) * 0.3

        if score < 0.25:
            regimes[i] = REGIME_CRYSTAL
        elif score < 0.50:
            regimes[i] = REGIME_FLUID
        elif score < 0.75:
            regimes[i] = REGIME_GAS
        else:
            regimes[i] = REGIME_PLASMA

    return regimes


# ═══════════════════════════════════════════════════════════════════════════
# Stage 5 — Event Relocation
# ═══════════════════════════════════════════════════════════════════════════

def relocate_events(events, Z_latent, temperature, affinity, regimes,
                    recon_error, relocation_intensity, stability_bias,
                    novelty_bias):
    """
    Latent Thermodynamic Relocation:

    For each event, compute a displacement score based on:
    - Regime-specific rules
    - Latent affinity (similar events attract)
    - Temperature (hot events scatter, cold events anchor)
    - Reconstruction error (true novelty for pivot decisions)

    Parameter semantics (v1.4 - made intuitive and monotonic):
    - relocation_intensity: smooth morph from the original order (0) to the
      fully-relocated order (1). No cliff: each event's sort position is
      interpolated between its original rank and its relocated rank.
    - stability_bias: pure anchoring. Higher -> less movement (events are
      pulled back toward their original rank). Monotonic.
    - novelty_bias: pushes the most novel events to evenly-spaced structural
      positions, with a blend that reaches full strength at 1.0.

    Returns: new ordering as list of event indices.
    """
    import numpy as np

    n = len(events)
    if n <= 1:
        return list(range(n))

    intensity = relocation_intensity
    mean_temp = float(np.mean(temperature))
    novelty = _safe_normalize(recon_error)

    # --- Step 1: full-strength relocated TARGET per event (regime character) ---
    # These are not scaled by intensity; they define WHERE each event wants to
    # go at maximum relocation. Magnitudes differ by regime so that Crystal
    # barely moves while Gas/Plasma can travel across the whole timeline.
    full = np.zeros(n)
    for i in range(n):
        regime = regimes[i]
        temp = temperature[i]
        pos = float(i)

        if regime == REGIME_CRYSTAL:
            most_similar = int(np.argmax(affinity[i]))
            full[i] = pos + (0.15 * (most_similar - i) if most_similar != i else 0.0)

        elif regime == REGIME_FLUID:
            direction = -1.0 if temp > mean_temp else 1.0
            full[i] = pos + temp * direction * (n * 0.25)

        elif regime == REGIME_GAS:
            sim_weights = affinity[i].copy()
            sim_weights[i] = 0
            if np.sum(sim_weights) > 0:
                center = np.average(np.arange(n), weights=sim_weights)
                direction = np.sign(pos - center)
                if direction == 0:
                    direction = 1.0
            else:
                direction = 1.0
            full[i] = pos + temp * direction * (n * 0.5)

        else:  # REGIME_PLASMA
            if novelty[i] > 0.7:
                # Very novel -> driven to a far structural extreme
                full[i] = (n - 1) if i < n // 2 else 0.0
            else:
                full[i] = pos + temp * (n * 0.5) * np.sin(i * 2.3 + temp * 5.7)

    # Convert full-strength targets into a relocated RANK (a permutation):
    # reloc_rank[i] = the position event i would occupy at full relocation.
    reloc_rank = np.empty(n, dtype=float)
    reloc_rank[np.argsort(full, kind="stable")] = np.arange(n)

    orig_rank = np.arange(n, dtype=float)

    # --- Step 2: smooth intensity morph (rank space, no cliff) ---
    # At intensity 0 the key is the original rank (identity order); at 1 it is
    # the relocated rank. Interpolating ranks makes crossings accumulate
    # gradually as intensity rises, instead of all at once past a threshold.
    key = (1.0 - intensity) * orig_rank + intensity * reloc_rank

    # --- Step 3: stability anchoring (monotonic: higher bias = less movement) ---
    # Pull each key back toward its original rank. Every event is anchored at
    # least a little; stable (high pitch_stability) events resist more.
    for i in range(n):
        ps = float(events[i].get("pitch_stability", 0.5))
        ps = min(1.0, max(0.0, ps))
        anchor = stability_bias * (0.4 + 0.6 * ps)
        key[i] = (1.0 - anchor) * key[i] + anchor * orig_rank[i]

    # --- Step 4: novelty pivoting (now has teeth) ---
    # Force the most novel events toward evenly-spaced structural slots. Gated
    # by intensity so that intensity = 0 always yields the original order; at
    # full intensity the strength reaches novelty_bias.
    nov_strength = novelty_bias * intensity
    if nov_strength > 0.02:
        top_k = max(1, int(round(n * 0.25)))
        top_indices = np.argsort(novelty)[-top_k:]
        structural = np.linspace(0, n - 1, top_k)
        for pi, idx in enumerate(sorted(top_indices)):
            key[idx] = (1.0 - nov_strength) * key[idx] + nov_strength * structural[pi]

    # --- Final order: sort events by their morphed key (always a permutation) ---
    order = list(np.argsort(key, kind="stable"))

    return order


# ═══════════════════════════════════════════════════════════════════════════
# Stage 6 — Reconstruction
# ═══════════════════════════════════════════════════════════════════════════

def extract_event_audio(audio, events, sr):
    """Extract audio clips for each event."""
    clips = []
    n_samples = len(audio) if audio.ndim == 1 else audio.shape[0]
    for ev in events:
        s = max(0, int(ev["start_time"] * sr))
        e = min(n_samples, int(ev["end_time"] * sr))
        if audio.ndim == 1:
            clips.append(audio[s:e].copy())
        else:
            clips.append(audio[s:e, :].copy())
    return clips


def reconstruct(clips, order, sr, original_length, preserve_duration):
    """
    Concatenate relocated events with equal-power crossfade.
    Post-splice click detection + smoothing.
    """
    import numpy as np

    xfade = max(4, int(XFADE_SEC * sr))
    multichannel = clips[0].ndim > 1
    n_ch = clips[0].shape[1] if multichannel else 1

    relocated = [clips[idx].copy().astype(np.float32) for idx in order]

    # Equal-power crossfade
    angle = np.linspace(0, np.pi / 2, xfade, dtype=np.float32)
    fade_in = np.sin(angle)
    fade_out = np.cos(angle)

    total = sum(len(c) for c in relocated) - max(0, len(relocated) - 1) * xfade
    if multichannel:
        output = np.zeros((total + xfade * 2, n_ch), dtype=np.float32)
    else:
        output = np.zeros(total + xfade * 2, dtype=np.float32)

    wp = 0
    splice_positions = []

    for ci, clip in enumerate(relocated):
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
            splice_positions.append(wp)
            wp = end
            continue

        if ci > 0:
            if multichannel:
                for ch in range(n_ch):
                    clip[:xfade, ch] *= fade_in
            else:
                clip[:xfade] *= fade_in
        if ci < len(relocated) - 1:
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
        if ci > 0:
            splice_positions.append(wp)
        wp = end - xfade if ci < len(relocated) - 1 else end

    output = output[:wp]

    # Post-splice click smoothing
    smooth_r = max(4, xfade // 4)
    for sp in splice_positions:
        rs = max(0, sp - smooth_r)
        re = min(len(output), sp + xfade + smooth_r)
        if re - rs < 4:
            continue
        if multichannel:
            for ch in range(n_ch):
                _smooth_clicks(output[rs:re, ch], smooth_r)
        else:
            _smooth_clicks(output[rs:re], smooth_r)

    # Duration preservation
    if preserve_duration:
        if len(output) > original_length:
            output = output[:original_length]
        elif len(output) < original_length:
            pad = original_length - len(output)
            if multichannel:
                output = np.pad(output, ((0, pad), (0, 0)))
            else:
                output = np.pad(output, (0, pad))

    peak = np.max(np.abs(output))
    if peak > 0.95:
        output *= (0.95 / peak)

    return output


def _smooth_clicks(seg, radius):
    """Detect and smooth sample-level clicks via median filter (vectorized)."""
    import numpy as np
    if len(seg) < 3:
        return
    local_rms = max(0.001, np.sqrt(np.mean(seg ** 2)))
    threshold = local_rms * 4.0
    diffs = np.abs(np.diff(seg))
    click_idx = np.where(diffs > threshold)[0]
    for i in click_idx:
        if 0 < i < len(seg) - 1:
            lo = max(0, i - 2)
            hi = min(len(seg), i + 3)
            seg[i] = np.median(seg[lo:hi])


# ═══════════════════════════════════════════════════════════════════════════
# Stage 7 — Output
# ═══════════════════════════════════════════════════════════════════════════

def compute_displacement_stats(events, order, sr):
    """Compute displacement statistics."""
    import numpy as np

    n = len(events)
    displacements = []

    for new_pos, orig_idx in enumerate(order):
        # Displacement in events
        d_events = abs(new_pos - orig_idx)
        # Displacement in milliseconds
        if orig_idx < n and new_pos < n:
            orig_center = (events[orig_idx]["start_time"]
                           + events[orig_idx]["end_time"]) / 2
            # Estimate new center from relocated position
            total_dur = sum(e["end_time"] - e["start_time"] for e in events)
            new_center = (total_dur * new_pos / max(1, n))
            d_ms = abs(new_center - orig_center) * 1000
            displacements.append(d_ms)

    return displacements


def write_stats_file(path, events, order, regimes, temperature,
                     losses, sr, warnings, Z_latent=None):
    """Write text report for Praat."""
    import numpy as np

    n = len(events)
    n_moved = sum(1 for i, o in enumerate(order[:n]) if o != i)
    displacements = compute_displacement_stats(events, order, sr)

    regime_counts = [int(np.sum(regimes == r)) for r in range(4)]
    regime_pcts = [100.0 * c / max(1, n) for c in regime_counts]

    # ── PCA projection for displacement visualization ─────────────────
    ev_x = []
    ev_y = []
    ev_regime = []
    reloc_x = []
    reloc_y = []

    if Z_latent is not None and len(Z_latent) > 0:
        mean_pt = np.mean(Z_latent, axis=0)
        centered = Z_latent - mean_pt
        if centered.shape[1] >= 2:
            U, S, Vt = np.linalg.svd(centered, full_matrices=False)
            proj = centered.dot(Vt[:2].T)
        else:
            proj = np.column_stack(
                [centered[:, 0], np.zeros(len(centered))])

        ev_x = proj[:, 0].tolist()
        ev_y = proj[:, 1].tolist()
        ev_regime = regimes.tolist()

        # Relocated positions: event at original index i moves to
        # position order[i] in the output. Map relocated ordering to
        # latent coordinates by looking up Z of the event at each slot.
        for new_pos in range(min(len(order), n)):
            orig_idx = order[new_pos]
            if orig_idx < n:
                reloc_x.append(proj[orig_idx, 0])
                reloc_y.append(proj[orig_idx, 1])
            else:
                reloc_x.append(0.0)
                reloc_y.append(0.0)

    with open(path, "w") as f:
        f.write("n_events=%d\n" % n)
        f.write("n_moved=%d\n" % n_moved)
        f.write("avg_displacement_ms=%.1f\n" %
                (np.mean(displacements) if displacements else 0))
        f.write("max_displacement_ms=%.1f\n" %
                (np.max(displacements) if displacements else 0))
        f.write("crystal_pct=%.1f\n" % regime_pcts[0])
        f.write("fluid_pct=%.1f\n" % regime_pcts[1])
        f.write("gas_pct=%.1f\n" % regime_pcts[2])
        f.write("plasma_pct=%.1f\n" % regime_pcts[3])
        f.write("final_loss=%.6f\n" % (losses[-1] if losses else 0))
        f.write("initial_loss=%.6f\n" % (losses[0] if losses else 0))
        f.write("mean_temperature=%.4f\n" % float(np.mean(temperature)))

        durations = [(e["end_time"] - e["start_time"]) for e in events]
        f.write("mean_event_dur=%.3f\n" % np.mean(durations))
        f.write("min_event_dur=%.3f\n" % np.min(durations))
        f.write("max_event_dur=%.3f\n" % np.max(durations))

        # ── Latent displacement map data ──────────────────────────────
        n_pts = min(len(ev_x), 100)
        f.write("n_disp_pts=%d\n" % n_pts)
        for i in range(n_pts):
            rx = reloc_x[i] if i < len(reloc_x) else ev_x[i]
            ry = reloc_y[i] if i < len(reloc_y) else ev_y[i]
            reg = int(ev_regime[i]) if i < len(ev_regime) else 0
            # Format: orig_x,orig_y,reloc_x,reloc_y,regime
            f.write("dp_%d=%.4f,%.4f,%.4f,%.4f,%d\n" % (
                i, ev_x[i], ev_y[i], rx, ry, reg))

        if warnings:
            f.write("warning=%s\n" % "; ".join(warnings))


# ═══════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════

def main():
    if len(sys.argv) != 12:
        print("Usage: python latent_relocation.py "
              "input.wav events.csv output.wav stats.txt "
              "learning_steps latent_size relocation_intensity "
              "stability_bias novelty_bias preserve_duration seed",
              file=sys.stderr)
        sys.exit(1)

    check_dependencies()

    import numpy as np
    import soundfile as sf

    in_wav       = sys.argv[1]
    events_csv   = sys.argv[2]
    out_wav      = sys.argv[3]
    stats_file   = sys.argv[4]
    n_steps      = int(sys.argv[5])
    latent_size  = int(sys.argv[6])
    reloc_int    = float(sys.argv[7])
    stab_bias    = float(sys.argv[8])
    nov_bias     = float(sys.argv[9])
    preserve_dur = int(float(sys.argv[10]))
    seed         = int(sys.argv[11])

    n_steps     = max(10, min(500, n_steps))
    latent_size = max(2, min(32, latent_size))
    reloc_int   = max(0, min(1, reloc_int))
    stab_bias   = max(0, min(1, stab_bias))
    nov_bias    = max(0, min(1, nov_bias))

    np.random.seed(seed)
    warnings = []

    if not os.path.isfile(in_wav):
        print("ERROR: input not found: %s" % in_wav, file=sys.stderr)
        sys.exit(1)
    if not os.path.isfile(events_csv):
        print("ERROR: events CSV not found: %s" % events_csv,
              file=sys.stderr)
        sys.exit(1)

    # ---- Load ----
    print("  [Py 1/6] Loading audio + event table...")
    audio, sr = sf.read(in_wav, always_2d=False)
    audio = np.asarray(audio, dtype=np.float32)
    events = load_event_table(events_csv)
    n_samples = len(audio) if audio.ndim == 1 else audio.shape[0]

    print("    Audio: %.2fs  SR=%d  Shape=%s" % (
        n_samples / sr, sr, audio.shape))
    print("    Events: %d" % len(events))

    if len(events) < 3:
        warnings.append("Too few events (%d) for meaningful learning" %
                         len(events))
        print("    WARNING: " + warnings[-1])

    # ---- Extract mel patches ----
    print("  [Py 2/6] Extracting log-mel patches...")
    audio_mono = audio if audio.ndim == 1 else audio[:, 0]
    patches = extract_mel_patches(audio_mono.astype(np.float64),
                                  sr, events)
    print("    Patch shape: %s (events x features)" % str(patches.shape))

    # ---- Train autoencoder ----
    print("  [Py 3/6] Training autoencoder (%d steps, latent=%d)..." %
          (n_steps, latent_size))
    model, losses = train_autoencoder(patches, latent_size, n_steps, seed)

    loss_ratio = losses[-1] / (losses[0] + 1e-12) if losses else 1.0
    print("    Loss: %.6f → %.6f (%.1f%% reduction)" % (
        losses[0] if losses else 0,
        losses[-1] if losses else 0,
        (1 - loss_ratio) * 100))

    if loss_ratio > 0.95:
        warnings.append("Autoencoder did not converge well (try more steps)")
        print("    WARNING: " + warnings[-1])

    # ---- Latent fields ----
    print("  [Py 4/6] Computing latent thermodynamic fields...")
    Z_latent, temperature, affinity, regimes, recon_err = \
        compute_latent_fields(model, patches, events, stab_bias, nov_bias)

    regime_counts = [int(np.sum(regimes == r)) for r in range(4)]
    print("    Regimes: Crystal=%d  Fluid=%d  Gas=%d  Plasma=%d" %
          tuple(regime_counts))
    print("    Mean temperature: %.3f" % np.mean(temperature))

    # ---- Relocation ----
    print("  [Py 5/6] Relocating events...")
    clips = extract_event_audio(audio, events, sr)
    order = relocate_events(events, Z_latent, temperature, affinity,
                            regimes, recon_err, reloc_int, stab_bias,
                            nov_bias)

    n_moved = sum(1 for i, o in enumerate(order[:len(events)]) if o != i)
    print("    Moved: %d/%d events" % (n_moved, len(events)))

    # ---- Reconstruct ----
    print("  [Py 6/6] Reconstructing...")
    output = reconstruct(clips, order, sr, n_samples, bool(preserve_dur))

    sf.write(out_wav, output, sr)
    write_stats_file(stats_file, events, order, regimes, temperature,
                     losses, sr, warnings, Z_latent=Z_latent)

    # Summary
    out_dur = len(output) / sr if output.ndim == 1 else output.shape[0] / sr
    disps = compute_displacement_stats(events, order, sr)
    avg_disp = np.mean(disps) if disps else 0
    print("    Output: %.2fs  |  Avg displacement: %.0f ms" %
          (out_dur, avg_disp))
    print("OK: wrote %s" % out_wav)


if __name__ == "__main__":
    main()
