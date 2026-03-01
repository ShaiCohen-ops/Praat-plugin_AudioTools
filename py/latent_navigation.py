"""
latent_navigation.py — Latent Space Navigation (Audio → Audio)

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University

Usage (called by Praat, not directly):
    python latent_navigation.py input.wav events.csv output.wav stats.txt
        learning_steps latent_size seed navigation_mode path_type
        travel_speed dwell_amount smoothing output_mode
        target_duration_mode density

Architecture:
    Stage 1 — Load audio + event table from Praat
    Stage 2 — Extract fixed-size log-mel patches per event
    Stage 3 — Train lightweight autoencoder on-the-fly (numpy only)
    Stage 4 — Encode events → latent vectors
    Stage 5 — Navigate latent space → generate new event sequence
    Stage 6 — Reconstruct new timeline from selected/morphed events
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
N_MELS = 40
MEL_FRAMES = 32
XFADE_SEC = 0.008

# Navigation modes
MODE_TRAJECTORY = 0
MODE_MIXER = 1

# Path types (trajectory mode)
PATH_THERMODRIFT = 0
PATH_ATTRACTOR = 1
PATH_CONVECTION = 2

# Output modes
OUT_SELECTOR = 0
OUT_MORPH = 1

# Duration modes
DUR_PRESERVE = 0
DUR_EXPAND = 1
DUR_COMPRESS = 2


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
    """Load Praat-exported event table."""
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
    """
    MLP autoencoder: input → hidden → latent → hidden → output.
    Leaky ReLU activations. Denoising. L2 regularization. Adam optimizer.
    Pure numpy — no external ML framework needed.
    """

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
        import numpy as np
        self._h1_pre = X.dot(self.W1) + self.b1
        self._h1 = self._leaky(self._h1_pre)
        Z = self._h1.dot(self.W2) + self.b2
        return Z

    def decode(self, Z):
        import numpy as np
        self._h2_pre = Z.dot(self.W3) + self.b3
        self._h2 = self._leaky(self._h2_pre)
        out = self._h2.dot(self.W4) + self.b4
        return out

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
    """Train autoencoder on event patches. Returns model, losses."""
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
# Stage 4 — Latent Encoding + Thermodynamic Fields
# ═══════════════════════════════════════════════════════════════════════════

def encode_events(model, patches, events):
    """
    Encode events → latent vectors.
    Compute per-event temperature (reconstruction error + kNN isolation).
    Returns: Z, temperature, recon_errors, knn_graph
    """
    import numpy as np
    from scipy.spatial.distance import cdist

    X = (patches - model._norm_mu) / model._norm_sigma
    Z = model.encode(X)
    recon_err = model.reconstruction_errors(X)

    n = len(events)

    # Pairwise latent distances
    dists = cdist(Z, Z, metric="euclidean")
    np.fill_diagonal(dists, np.inf)

    # kNN graph (k=3)
    k = min(3, n - 1)
    knn_graph = np.zeros((n, k), dtype=int)
    knn_dists_mean = np.zeros(n)
    for i in range(n):
        sorted_idx = np.argsort(dists[i])
        knn_graph[i] = sorted_idx[:k]
        knn_dists_mean[i] = np.mean(dists[i, sorted_idx[:k]])

    # Temperature: reconstruction novelty + latent isolation
    err_norm = _safe_normalize(recon_err)
    knn_norm = _safe_normalize(knn_dists_mean)
    temperature = 0.5 * err_norm + 0.5 * knn_norm
    temperature = np.clip(temperature, 0, 1)

    return Z, temperature, recon_err, dists, knn_graph


def _safe_normalize(x):
    import numpy as np
    mn, mx = np.min(x), np.max(x)
    if mx - mn < 1e-12:
        return np.zeros_like(x)
    return (x - mn) / (mx - mn)


def compute_pca_2d(Z):
    """Reduce latent vectors to 2D via PCA (for Mixer mode)."""
    import numpy as np

    Z_centered = Z - np.mean(Z, axis=0)
    cov = Z_centered.T.dot(Z_centered) / max(1, len(Z) - 1)
    eigvals, eigvecs = np.linalg.eigh(cov)
    idx = np.argsort(eigvals)[::-1]
    top2 = eigvecs[:, idx[:2]]
    Z_2d = Z_centered.dot(top2)
    return Z_2d, top2


# ═══════════════════════════════════════════════════════════════════════════
# Stage 5 — Latent Navigation Engine
# ═══════════════════════════════════════════════════════════════════════════

def navigate_trajectory(Z, temperature, dists, knn_graph, events,
                        path_type, travel_speed, dwell_amount,
                        n_output_events, seed):
    """
    Trajectory navigation: generate a latent path z(t) and select events
    along the path.

    Returns: list of (event_index, weight) pairs defining the new timeline.
    weight=1.0 for selector mode (used later), <1.0 for morph pairs.
    """
    import numpy as np

    rng = np.random.RandomState(seed)
    n = len(events)

    if path_type == PATH_THERMODRIFT:
        return _path_thermodrift(Z, temperature, dists, events,
                                 travel_speed, dwell_amount,
                                 n_output_events, rng)
    elif path_type == PATH_ATTRACTOR:
        return _path_attractor(Z, temperature, dists, events,
                               travel_speed, dwell_amount,
                               n_output_events, rng)
    else:  # PATH_CONVECTION
        return _path_convection(Z, temperature, dists, events,
                                travel_speed, dwell_amount,
                                n_output_events, rng)


def _path_thermodrift(Z, temperature, dists, events,
                      travel_speed, dwell_amount, n_steps, rng):
    """
    ThermoDrift: speed increases with temperature (latent novelty).
    Slows in stable regions, accelerates through volatile zones.
    """
    import numpy as np

    n = len(Z)
    # Start at the event with median temperature (middle of the spectrum)
    start = np.argsort(temperature)[n // 2]
    current_z = Z[start].copy()

    path = []
    usage_count = np.zeros(n, dtype=int)
    last_used = np.full(n, -100)  # step when last used

    for step in range(n_steps):
        # Find nearest event to current latent position
        d_to_events = np.sqrt(np.sum((Z - current_z) ** 2, axis=1))

        # LRU penalty: prefer less-recently-used events
        lru_penalty = np.zeros(n)
        for i in range(n):
            recency = step - last_used[i]
            if recency < 3:
                lru_penalty[i] = (3 - recency) * 0.5 * np.max(d_to_events)
        scores = d_to_events + lru_penalty

        chosen = np.argmin(scores)
        path.append(chosen)
        usage_count[chosen] += 1
        last_used[chosen] = step

        # Move through latent space
        # Temperature at current position controls step size
        local_temp = temperature[chosen]
        step_scale = travel_speed * (0.3 + 0.7 * local_temp)

        # Dwell: if low temperature, stay longer (reduce step)
        if local_temp < 0.3:
            step_scale *= (1.0 - dwell_amount * 0.6)

        # Direction: toward least-visited neighbor in kNN
        candidates = np.argsort(d_to_events)
        best_next = -1
        for c in candidates[1:min(8, n)]:
            if usage_count[c] <= np.min(usage_count) + 1:
                best_next = c
                break
        if best_next < 0:
            best_next = candidates[1] if n > 1 else 0

        direction = Z[best_next] - current_z
        d_norm = np.linalg.norm(direction)
        if d_norm > 1e-8:
            direction = direction / d_norm

        # Median inter-event distance as reference scale
        median_dist = np.median(dists[dists < np.inf])
        current_z = current_z + direction * step_scale * median_dist * 0.5

    return path


def _path_attractor(Z, temperature, dists, events,
                    travel_speed, dwell_amount, n_steps, rng):
    """
    Attractor: identify cluster centroids as attractor poles.
    Move between them with dwell at each pole.
    """
    import numpy as np

    n = len(Z)
    # Find attractor poles via simple k-means-like clustering
    n_poles = min(max(2, n // 5), 6)
    poles = _find_poles(Z, n_poles, rng)

    current_z = Z[np.argmin(temperature)].copy()  # start at coolest
    current_pole = 0

    path = []
    usage_count = np.zeros(n, dtype=int)
    last_used = np.full(n, -100)
    dwell_counter = 0
    dwell_target = max(1, int(dwell_amount * n_steps / (n_poles * 2)))

    for step in range(n_steps):
        # Find nearest event
        d_to_events = np.sqrt(np.sum((Z - current_z) ** 2, axis=1))
        lru_penalty = np.zeros(n)
        for i in range(n):
            recency = step - last_used[i]
            if recency < 3:
                lru_penalty[i] = (3 - recency) * 0.5 * np.max(d_to_events)
        scores = d_to_events + lru_penalty

        chosen = np.argmin(scores)
        path.append(chosen)
        usage_count[chosen] += 1
        last_used[chosen] = step

        # Check if we're near current pole
        d_to_pole = np.linalg.norm(current_z - poles[current_pole])
        median_dist = np.median(dists[dists < np.inf])

        if d_to_pole < median_dist * 0.3:
            # Dwelling at pole
            dwell_counter += 1
            if dwell_counter >= dwell_target:
                # Move to next pole
                current_pole = (current_pole + 1) % n_poles
                dwell_counter = 0

        # Move toward current pole
        direction = poles[current_pole] - current_z
        d_norm = np.linalg.norm(direction)
        if d_norm > 1e-8:
            direction = direction / d_norm
        current_z = current_z + direction * travel_speed * median_dist * 0.4

    return path


def _path_convection(Z, temperature, dists, events,
                     travel_speed, dwell_amount, n_steps, rng):
    """
    Convection: define flow along principal axes.
    Events "rise" (high novelty) or "sink" (low novelty).
    """
    import numpy as np

    n = len(Z)
    # PCA for flow direction
    Z_c = Z - np.mean(Z, axis=0)
    cov = Z_c.T.dot(Z_c) / max(1, n - 1)
    eigvals, eigvecs = np.linalg.eigh(cov)
    flow_axis = eigvecs[:, np.argmax(eigvals)]  # principal axis

    # Start at bottom of convection cell (lowest projection on axis)
    projections = Z.dot(flow_axis)
    current_z = Z[np.argmin(projections)].copy()
    flow_direction = 1.0  # rising

    path = []
    usage_count = np.zeros(n, dtype=int)
    last_used = np.full(n, -100)
    median_dist = np.median(dists[dists < np.inf])

    for step in range(n_steps):
        # Find nearest event
        d_to_events = np.sqrt(np.sum((Z - current_z) ** 2, axis=1))
        lru_penalty = np.zeros(n)
        for i in range(n):
            recency = step - last_used[i]
            if recency < 3:
                lru_penalty[i] = (3 - recency) * 0.5 * np.max(d_to_events)
        scores = d_to_events + lru_penalty

        chosen = np.argmin(scores)
        path.append(chosen)
        usage_count[chosen] += 1
        last_used[chosen] = step

        # Current projection on flow axis
        proj = np.dot(current_z, flow_axis)
        proj_range = np.max(projections) - np.min(projections)
        proj_frac = (proj - np.min(projections)) / (proj_range + 1e-8)

        # Reverse at extremes
        if proj_frac > 0.9:
            flow_direction = -1.0
        elif proj_frac < 0.1:
            flow_direction = 1.0

        # Temperature-modulated flow: hot events rise faster
        local_temp = temperature[chosen]
        temp_modulation = 0.5 + 0.5 * local_temp * flow_direction

        # Lateral drift (perpendicular to flow)
        lateral = Z[chosen] - current_z
        lateral = lateral - np.dot(lateral, flow_axis) * flow_axis
        lat_norm = np.linalg.norm(lateral)
        if lat_norm > 1e-8:
            lateral = lateral / lat_norm * dwell_amount * 0.3

        # Move
        step_vec = (flow_axis * flow_direction * travel_speed
                    * temp_modulation * median_dist * 0.4 + lateral)
        current_z = current_z + step_vec

    return path


def navigate_mixer(Z, temperature, dists, events,
                   travel_speed, dwell_amount, n_output_events, seed):
    """
    Latent Mixer: map events to 2D, sweep deterministic curve,
    select events by proximity.
    """
    import numpy as np

    rng = np.random.RandomState(seed)
    n = len(Z)

    Z_2d, _ = compute_pca_2d(Z)

    # Normalize 2D coordinates to [0, 1]
    z_min = np.min(Z_2d, axis=0)
    z_max = np.max(Z_2d, axis=0)
    z_range = z_max - z_min + 1e-8
    Z_norm = (Z_2d - z_min) / z_range

    # Generate deterministic spiral sweep
    path_2d = np.zeros((n_output_events, 2))
    for step in range(n_output_events):
        t = step / max(1, n_output_events - 1)
        # Expanding spiral with speed modulation
        r = 0.1 + 0.4 * t * travel_speed
        angle = t * (4 + travel_speed * 3) * np.pi
        cx, cy = 0.5, 0.5
        path_2d[step, 0] = cx + r * np.cos(angle)
        path_2d[step, 1] = cy + r * np.sin(angle)

    # Select events by proximity to path points
    path_result = []
    usage_count = np.zeros(n, dtype=int)
    last_used = np.full(n, -100)

    for step in range(n_output_events):
        d = np.sqrt(np.sum((Z_norm - path_2d[step]) ** 2, axis=1))
        lru_penalty = np.zeros(n)
        for i in range(n):
            recency = step - last_used[i]
            if recency < 3:
                lru_penalty[i] = (3 - recency) * 0.3 * np.max(d)
        scores = d + lru_penalty
        chosen = np.argmin(scores)
        path_result.append(chosen)
        usage_count[chosen] += 1
        last_used[chosen] = step

    return path_result


def _find_poles(Z, n_poles, rng):
    """Simple k-means to find cluster centroids as attractor poles."""
    import numpy as np

    n, d = Z.shape
    # Initialize: spread evenly across data range
    indices = np.linspace(0, n - 1, n_poles).astype(int)
    centers = Z[indices].copy()

    for iteration in range(20):
        # Assign
        from scipy.spatial.distance import cdist
        dists = cdist(Z, centers)
        labels = np.argmin(dists, axis=1)

        # Update
        new_centers = np.zeros_like(centers)
        for c in range(n_poles):
            mask = labels == c
            if np.sum(mask) > 0:
                new_centers[c] = np.mean(Z[mask], axis=0)
            else:
                new_centers[c] = centers[c]

        if np.max(np.abs(new_centers - centers)) < 1e-6:
            break
        centers = new_centers

    return centers


# ═══════════════════════════════════════════════════════════════════════════
# Stage 6 — Reconstruction
# ═══════════════════════════════════════════════════════════════════════════

def extract_event_clips(audio, events, sr):
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


def reconstruct_selector(clips, path, sr, target_length, Z, smoothing):
    """
    Selector mode: concatenate chosen events in navigation order.
    Uses equal-power crossfade at splice points.
    Applies smoothing to reduce jumpiness between distant events.
    """
    import numpy as np

    xfade = max(4, int(XFADE_SEC * sr))

    # Build event sequence
    sequence = [clips[idx].copy().astype(np.float32) for idx in path]

    # Smoothing: envelope to reduce abrupt level changes between
    # distant latent neighbors
    if smoothing > 0.05:
        for si in range(1, len(sequence)):
            prev_idx = path[si - 1]
            curr_idx = path[si]
            d = np.linalg.norm(Z[prev_idx] - Z[curr_idx])
            max_d = np.max(np.linalg.norm(Z - Z[0], axis=1)) + 1e-8
            d_frac = d / max_d

            if d_frac > 0.5:
                # Long latent jump → apply gentle fade-in
                fade_len = min(len(sequence[si]),
                               int(sr * 0.05 * smoothing))
                if fade_len > 2:
                    fade = np.linspace(0.3, 1.0, fade_len)
                    if sequence[si].ndim > 1:
                        for ch in range(sequence[si].shape[1]):
                            sequence[si][:fade_len, ch] *= fade
                    else:
                        sequence[si][:fade_len] *= fade

    return _concatenate_clips(sequence, xfade, target_length)


def reconstruct_morph(clips, path, sr, target_length, Z, smoothing):
    """
    Morph mode: at each step, crossfade between current event and
    next event in the path, weighted by latent distance.
    """
    import numpy as np

    xfade = max(4, int(XFADE_SEC * sr))
    sequence = []

    for si in range(len(path)):
        idx = path[si]
        clip_a = clips[idx].copy().astype(np.float32)

        if si < len(path) - 1:
            idx_b = path[si + 1]
            d = np.linalg.norm(Z[idx] - Z[idx_b])
            max_d = np.max(np.linalg.norm(
                Z - np.mean(Z, axis=0), axis=1)) + 1e-8
            morph_weight = min(0.5, d / max_d * smoothing)

            clip_b = clips[idx_b].copy().astype(np.float32)

            # Match lengths for crossfade
            min_len = min(len(clip_a), len(clip_b))
            max_len = max(len(clip_a), len(clip_b))

            # Pad shorter to match longer
            if clip_a.ndim > 1:
                if len(clip_a) < max_len:
                    pad = np.zeros((max_len - len(clip_a),
                                    clip_a.shape[1]), dtype=np.float32)
                    clip_a = np.concatenate([clip_a, pad])
                if len(clip_b) < max_len:
                    pad = np.zeros((max_len - len(clip_b),
                                    clip_b.shape[1]), dtype=np.float32)
                    clip_b = np.concatenate([clip_b, pad])
            else:
                if len(clip_a) < max_len:
                    clip_a = np.pad(clip_a, (0, max_len - len(clip_a)))
                if len(clip_b) < max_len:
                    clip_b = np.pad(clip_b, (0, max_len - len(clip_b)))

            # Blend
            morphed = ((1.0 - morph_weight) * clip_a
                       + morph_weight * clip_b)
            sequence.append(morphed)
        else:
            sequence.append(clip_a)

    return _concatenate_clips(sequence, xfade, target_length)


def _concatenate_clips(sequence, xfade, target_length):
    """Concatenate clips with equal-power crossfade + click smoothing."""
    import numpy as np

    if not sequence:
        return np.zeros(max(1, target_length), dtype=np.float32)

    multichannel = sequence[0].ndim > 1
    n_ch = sequence[0].shape[1] if multichannel else 1

    angle = np.linspace(0, np.pi / 2, xfade, dtype=np.float32)
    fade_in = np.sin(angle)
    fade_out = np.cos(angle)

    total = sum(len(c) for c in sequence)
    if multichannel:
        output = np.zeros((total + xfade * 2, n_ch), dtype=np.float32)
    else:
        output = np.zeros(total + xfade * 2, dtype=np.float32)

    wp = 0
    for ci, clip in enumerate(sequence):
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

        if ci > 0:
            if multichannel:
                for ch in range(n_ch):
                    clip[:xfade, ch] *= fade_in
            else:
                clip[:xfade] *= fade_in
        if ci < len(sequence) - 1:
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
        wp = end - xfade if ci < len(sequence) - 1 else end

    output = output[:wp]

    # Post-splice click smoothing
    smooth_r = max(4, xfade // 4)
    for i in range(1, len(output) - 1):
        if multichannel:
            for ch in range(n_ch):
                _smooth_region(output, i, smooth_r, ch)
        else:
            _smooth_region_mono(output, i, smooth_r)

    # Duration enforcement
    if target_length > 0:
        if len(output) > target_length:
            output = output[:target_length]
        elif len(output) < target_length:
            pad = target_length - len(output)
            if multichannel:
                output = np.pad(output, ((0, pad), (0, 0)))
            else:
                output = np.pad(output, (0, pad))

    peak = np.max(np.abs(output))
    if peak > 0.95:
        output *= (0.95 / peak)

    return output


def _smooth_region(output, i, r, ch):
    """Detect and smooth clicks at position i for multichannel."""
    import numpy as np
    if i < 1 or i >= len(output) - 1:
        return
    jump = abs(output[i, ch] - output[i - 1, ch])
    local_rms = max(0.001, np.sqrt(np.mean(output[max(0, i - r):i + r, ch] ** 2)))
    if jump > local_rms * 4.0:
        lo = max(0, i - 2)
        hi = min(len(output), i + 3)
        output[i, ch] = np.median(output[lo:hi, ch])


def _smooth_region_mono(output, i, r):
    """Detect and smooth clicks at position i for mono."""
    import numpy as np
    if i < 1 or i >= len(output) - 1:
        return
    jump = abs(output[i] - output[i - 1])
    local_rms = max(0.001, np.sqrt(np.mean(output[max(0, i - r):i + r] ** 2)))
    if jump > local_rms * 4.0:
        lo = max(0, i - 2)
        hi = min(len(output), i + 3)
        output[i] = np.median(output[lo:hi])


# ═══════════════════════════════════════════════════════════════════════════
# Stage 7 — Stats Output
# ═══════════════════════════════════════════════════════════════════════════

def write_stats(path, events, path_sequence, Z, temperature,
                losses, sr, out_duration, nav_mode, path_type,
                out_mode, warnings):
    """Write stats report for Praat."""
    import numpy as np

    n = len(events)
    unique_used = len(set(path_sequence))
    total_steps = len(path_sequence)

    # Repetition rate
    usage = np.zeros(n, dtype=int)
    for idx in path_sequence:
        usage[idx] += 1
    rep_rate = (total_steps - unique_used) / max(1, total_steps)

    # Latent travel distance
    travel_dists = []
    for i in range(1, len(path_sequence)):
        d = np.linalg.norm(Z[path_sequence[i]] - Z[path_sequence[i - 1]])
        travel_dists.append(d)
    avg_travel = np.mean(travel_dists) if travel_dists else 0

    # Event durations
    durations = [e["end_time"] - e["start_time"] for e in events]

    mode_names = ["Trajectory", "Mixer"]
    path_names = ["ThermoDrift", "Attractor", "Convection"]
    out_names = ["Selector", "Morph"]

    with open(path, "w") as f:
        f.write("n_events=%d\n" % n)
        f.write("n_output_steps=%d\n" % total_steps)
        f.write("unique_events_used=%d\n" % unique_used)
        f.write("repetition_rate=%.3f\n" % rep_rate)
        f.write("avg_latent_travel=%.4f\n" % avg_travel)
        f.write("mean_temperature=%.4f\n" % float(np.mean(temperature)))
        f.write("output_duration=%.3f\n" % out_duration)
        f.write("nav_mode=%s\n" % mode_names[nav_mode])
        f.write("path_type=%s\n" % path_names[path_type])
        f.write("output_mode=%s\n" % out_names[out_mode])
        f.write("final_loss=%.6f\n" % (losses[-1] if losses else 0))
        f.write("initial_loss=%.6f\n" % (losses[0] if losses else 0))
        f.write("mean_event_dur=%.3f\n" % np.mean(durations))

        # Most-used events
        top_3 = np.argsort(usage)[-3:][::-1]
        for rank, idx in enumerate(top_3):
            f.write("top_event_%d=%d|%d_uses|%.3fs\n" % (
                rank, idx, usage[idx],
                events[idx]["end_time"] - events[idx]["start_time"]))

        for w in warnings:
            f.write("warning=%s\n" % w)


# ═══════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════

def main():
    if len(sys.argv) != 16:
        print("Usage: python latent_navigation.py "
              "input.wav events.csv output.wav stats.txt "
              "learning_steps latent_size seed "
              "navigation_mode path_type travel_speed dwell_amount "
              "smoothing output_mode target_duration_mode density",
              file=sys.stderr)
        sys.exit(1)

    check_dependencies()

    import numpy as np
    import soundfile as sf

    in_wav          = sys.argv[1]
    events_csv      = sys.argv[2]
    out_wav         = sys.argv[3]
    stats_file      = sys.argv[4]
    n_steps         = int(sys.argv[5])
    latent_size     = int(sys.argv[6])
    seed            = int(sys.argv[7])
    nav_mode        = int(sys.argv[8])
    path_type       = int(sys.argv[9])
    travel_speed    = float(sys.argv[10])
    dwell_amount    = float(sys.argv[11])
    smoothing       = float(sys.argv[12])
    out_mode        = int(sys.argv[13])
    dur_mode        = int(sys.argv[14])
    density         = float(sys.argv[15])

    # Clamp
    n_steps     = max(10, min(500, n_steps))
    latent_size = max(2, min(32, latent_size))
    travel_speed = max(0.1, min(2.0, travel_speed))
    dwell_amount = max(0.0, min(1.0, dwell_amount))
    smoothing    = max(0.0, min(1.0, smoothing))
    density      = max(0.5, min(20.0, density))

    np.random.seed(seed)
    warnings = []

    # ---- Load ----
    print("  [Py 1/6] Loading audio + event table...")
    audio, sr = sf.read(in_wav, always_2d=False)
    audio = np.asarray(audio, dtype=np.float32)
    events = load_event_table(events_csv)
    n_samples = len(audio) if audio.ndim == 1 else audio.shape[0]
    orig_dur = n_samples / sr

    print("    Audio: %.2fs  SR=%d  Shape=%s" % (orig_dur, sr, audio.shape))
    print("    Events: %d" % len(events))

    if len(events) < 3:
        warnings.append("Too few events (%d) for meaningful learning" %
                         len(events))
        print("    WARNING: " + warnings[-1])

    # ---- Mel patches ----
    print("  [Py 2/6] Extracting log-mel patches...")
    audio_mono = audio if audio.ndim == 1 else audio[:, 0]
    patches = extract_mel_patches(audio_mono.astype(np.float64), sr, events)
    print("    Patch shape: %s" % str(patches.shape))

    # ---- Train AE ----
    print("  [Py 3/6] Training autoencoder (%d steps, latent=%d)..." %
          (n_steps, latent_size))
    model, losses = train_autoencoder(patches, latent_size, n_steps, seed)
    loss_ratio = losses[-1] / (losses[0] + 1e-12) if losses else 1.0
    print("    Loss: %.6f → %.6f (%.1f%% reduction)" % (
        losses[0], losses[-1], (1 - loss_ratio) * 100))

    if loss_ratio > 0.95:
        warnings.append("Autoencoder did not converge well")

    # ---- Encode ----
    print("  [Py 4/6] Encoding events → latent space...")
    Z, temperature, recon_err, dists, knn_graph = \
        encode_events(model, patches, events)
    print("    Mean temperature: %.3f" % np.mean(temperature))

    # ---- Compute output event count from density + duration ----
    mean_ev_dur = np.mean([e["end_time"] - e["start_time"] for e in events])

    if dur_mode == DUR_PRESERVE:
        target_dur = orig_dur
    elif dur_mode == DUR_EXPAND:
        target_dur = orig_dur * 1.5
    else:  # DUR_COMPRESS
        target_dur = orig_dur * 0.6

    n_output_events = max(3, int(target_dur * density))
    n_output_events = min(n_output_events, len(events) * 8)

    target_samples = int(target_dur * sr)
    print("    Target: %.2fs  (%d events at %.1f/s)" % (
        target_dur, n_output_events, density))

    # ---- Navigate ----
    print("  [Py 5/6] Navigating latent space...")
    nav_names = ["Trajectory", "Mixer"]
    path_names = ["ThermoDrift", "Attractor", "Convection"]
    print("    Mode: %s | Path: %s" % (
        nav_names[nav_mode], path_names[path_type]))

    if nav_mode == MODE_TRAJECTORY:
        path_sequence = navigate_trajectory(
            Z, temperature, dists, knn_graph, events,
            path_type, travel_speed, dwell_amount, n_output_events, seed)
    else:
        path_sequence = navigate_mixer(
            Z, temperature, dists, events,
            travel_speed, dwell_amount, n_output_events, seed)

    unique_used = len(set(path_sequence))
    print("    Path: %d steps | %d/%d unique events" % (
        len(path_sequence), unique_used, len(events)))

    # ---- Reconstruct ----
    print("  [Py 6/6] Reconstructing new timeline...")
    clips = extract_event_clips(audio, events, sr)

    if out_mode == OUT_SELECTOR:
        output = reconstruct_selector(clips, path_sequence, sr,
                                      target_samples, Z, smoothing)
    else:
        output = reconstruct_morph(clips, path_sequence, sr,
                                   target_samples, Z, smoothing)

    sf.write(out_wav, output, sr)

    out_dur = len(output) / sr if output.ndim == 1 else output.shape[0] / sr

    write_stats(stats_file, events, path_sequence, Z, temperature,
                losses, sr, out_dur, nav_mode, path_type, out_mode,
                warnings)

    print("    Output: %.2fs | Peak: %.4f" % (
        out_dur, np.max(np.abs(output))))
    print("OK: wrote %s" % out_wav)


if __name__ == "__main__":
    main()
