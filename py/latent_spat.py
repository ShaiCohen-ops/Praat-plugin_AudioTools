"""
latent_spat.py — Latent Spat (Agent-Based Spatialization)

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University

Usage (called by Praat, not directly):
    python latent_spat.py input.wav events.csv output.wav stats.txt
        num_agents latent_size counterpoint_rigidity speed duration
        spatial_format distance_model reverb_amount seed

Spatial formats:
    0 = Stereo (2ch)
    1 = Quad (4ch): FL FR RL RR
    2 = 5.1 (6ch): L R C LFE LS RS
    3 = Octophonic (8ch): evenly spaced at 0° 45° 90° ... 315°

Distance models:
    0 = Amplitude only (1/d law)
    1 = Amplitude + Low-pass (proximity effect)
    2 = Amplitude + Low-pass + Reverb tail

Architecture:
    Stages 1–5: identical to latent_counterpoint.py
    (load, mel patches, train AE, encode, physics engine)

    Stage 6 — Spatial Mapping:
    - PCA-reduce each agent's latent trajectory to 2D
    - X → azimuth (panning angle around listener)
    - Y → distance (amplitude + filtering + reverb)
    - Per-step spatial position updates (smoothed)

    Stage 7 — Spatial Reconstruction:
    - VBAP (Vector Base Amplitude Panning) to N speakers
    - Distance-dependent amplitude attenuation
    - Distance-dependent low-pass filtering (proximity effect)
    - Optional distance-dependent reverb tail
    - Independent per-agent spatial rendering
    - N-channel output file

No external model downloads. No internet. No PyTorch/TensorFlow/sklearn.
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

# Agent profiles (same as counterpoint)
AGENT_CANTUS = 0
AGENT_FLORID = 1
AGENT_SHADOW = 2
AGENT_NAMES = ["Cantus", "Florid", "Shadow"]

# Spatial formats
SPAT_STEREO = 0
SPAT_QUAD = 1
SPAT_51 = 2
SPAT_OCTO = 3
SPAT_NAMES = ["Stereo", "Quad", "5.1", "Octophonic"]

# Speaker layouts (azimuth in degrees, 0=front, clockwise)
SPEAKER_LAYOUTS = {
    SPAT_STEREO: [330, 30],                          # L R
    SPAT_QUAD:   [315, 45, 225, 135],                # FL FR RL RR
    SPAT_51:     [330, 30, 0, 0, 240, 120],          # L R C LFE LS RS
    SPAT_OCTO:   [0, 45, 90, 135, 180, 225, 270, 315],
}

SPEAKER_LABELS = {
    SPAT_STEREO: ["L", "R"],
    SPAT_QUAD:   ["FL", "FR", "RL", "RR"],
    SPAT_51:     ["L", "R", "C", "LFE", "LS", "RS"],
    SPAT_OCTO:   ["F", "FR", "R", "RR", "B", "RL", "L", "FL"],
}

# Distance models
DIST_AMP = 0
DIST_AMP_LP = 1
DIST_AMP_LP_REVERB = 2
DIST_NAMES = ["Amplitude", "Amp+LowPass", "Amp+LP+Reverb"]


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
# Stages 1–4: Reused from counterpoint (load, mel, AE, encode)
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
        Z = self._h1.dot(self.W2) + self.b2
        return Z

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


def encode_events(model, patches):
    import numpy as np
    X = (patches - model._norm_mu) / model._norm_sigma
    Z = model.encode(X)
    recon_err = model.reconstruction_errors(X)
    return Z, recon_err


def compute_latent_geometry(Z):
    import numpy as np
    from scipy.spatial.distance import cdist
    center = np.mean(Z, axis=0)
    dist_from_center = np.sqrt(np.sum((Z - center) ** 2, axis=1))
    periphery = dist_from_center / (np.max(dist_from_center) + 1e-8)
    dists = cdist(Z, Z, metric="euclidean")
    np.fill_diagonal(dists, np.inf)
    median_dist = np.median(dists[dists < np.inf])
    return center, periphery, dists, median_dist


# ═══════════════════════════════════════════════════════════════════════════
# Stage 5 — Physics Engine (reused from counterpoint)
# ═══════════════════════════════════════════════════════════════════════════

class Agent(object):
    def __init__(self, agent_id, profile, latent_dim, seed):
        import numpy as np
        self.agent_id = agent_id
        self.profile = profile
        self.rng = np.random.RandomState(seed + agent_id * 137)
        self.latent_dim = latent_dim

        self.position = np.zeros(latent_dim)
        self.velocity = np.zeros(latent_dim)
        self.history = []
        self.position_history = []  # NEW: track latent positions per step
        self.recent_memory = []
        self.memory_size = 5

        if profile == AGENT_CANTUS:
            self.mass = 3.0
            self.max_speed = 0.3
            self.jitter_scale = 0.05
            self.attraction_weight = 1.0
        elif profile == AGENT_FLORID:
            self.mass = 0.5
            self.max_speed = 1.5
            self.jitter_scale = 0.2
            self.attraction_weight = 0.6
        elif profile == AGENT_SHADOW:
            self.mass = 2.0
            self.max_speed = 0.4
            self.jitter_scale = 0.08
            self.attraction_weight = 0.3
            self.lag_buffer = []
            self.lag_steps = 3

    def init_position(self, Z, center, periphery):
        import numpy as np
        if self.profile == AGENT_CANTUS:
            self.position = center.copy()
        elif self.profile == AGENT_FLORID:
            self.position = Z[np.argmax(periphery)].copy()
        elif self.profile == AGENT_SHADOW:
            self.position = 2.0 * center - Z[np.argmax(periphery)].copy()


def build_agents(num_agents, latent_dim, Z, center, periphery, seed):
    agents = []
    profiles = [AGENT_CANTUS, AGENT_FLORID, AGENT_SHADOW]
    for i in range(num_agents):
        profile = profiles[i % len(profiles)]
        agent = Agent(i, profile, latent_dim, seed)
        agent.init_position(Z, center, periphery)
        agents.append(agent)
    return agents


def run_physics(agents, Z, center, periphery, dists, median_dist,
                n_steps, speed, counterpoint_rigidity, seed):
    """Run multi-agent physics. Now also records position_history."""
    import numpy as np

    n_events = len(Z)
    rng = np.random.RandomState(seed + 999)

    cantus_agent = None
    for a in agents:
        if a.profile == AGENT_CANTUS:
            cantus_agent = a
            break

    for step in range(n_steps):
        forces = []
        for a in agents:
            force = np.zeros(a.latent_dim)

            d_to_events = np.sqrt(np.sum((Z - a.position) ** 2, axis=1))

            if a.profile == AGENT_CANTUS:
                center_pull = center - a.position
                d_center = np.linalg.norm(center_pull)
                if d_center > 1e-8:
                    force += (center_pull / d_center
                              * a.attraction_weight * speed * 0.5)
                nearest = np.argmin(d_to_events)
                pull = Z[nearest] - a.position
                d_pull = np.linalg.norm(pull)
                if d_pull > 1e-8:
                    force += pull / d_pull * a.attraction_weight * speed * 0.3

            elif a.profile == AGENT_FLORID:
                weighted_d = d_to_events / (periphery + 0.1)
                nearest = np.argmin(weighted_d)
                pull = Z[nearest] - a.position
                d_pull = np.linalg.norm(pull)
                if d_pull > 1e-8:
                    force += (pull / d_pull
                              * a.attraction_weight * speed * 0.8)

            elif a.profile == AGENT_SHADOW:
                if cantus_agent is not None:
                    a.lag_buffer.append(cantus_agent.position.copy())
                    if len(a.lag_buffer) > a.lag_steps:
                        lagged_pos = a.lag_buffer[-a.lag_steps]
                        mirror_target = 2.0 * center - lagged_pos
                        pull = mirror_target - a.position
                        d_pull = np.linalg.norm(pull)
                        if d_pull > 1e-8:
                            force += (pull / d_pull
                                      * a.attraction_weight * speed * 0.6)
                    else:
                        pull = center - a.position
                        d_pull = np.linalg.norm(pull)
                        if d_pull > 1e-8:
                            force += pull / d_pull * 0.2
                nearest = np.argmin(d_to_events)
                pull = Z[nearest] - a.position
                d_pull = np.linalg.norm(pull)
                if d_pull > 1e-8:
                    force += pull / d_pull * a.attraction_weight * speed * 0.2

            for other in agents:
                if other.agent_id == a.agent_id:
                    continue
                diff = a.position - other.position
                d_between = np.linalg.norm(diff)
                if d_between < 1e-8:
                    diff = rng.randn(a.latent_dim) * 0.01
                    d_between = np.linalg.norm(diff) + 1e-8
                repulsion_strength = (counterpoint_rigidity
                                      * median_dist ** 2
                                      / (d_between ** 2 + 1e-6))
                repulsion_strength = min(repulsion_strength, speed * 3.0)
                force += (diff / d_between) * repulsion_strength

            jitter = rng.randn(a.latent_dim) * a.jitter_scale * speed
            force += jitter
            forces.append(force)

        for ai, a in enumerate(agents):
            acceleration = forces[ai] / a.mass
            a.velocity = 0.85 * a.velocity + acceleration
            spd = np.linalg.norm(a.velocity)
            max_v = a.max_speed * speed * median_dist
            if spd > max_v:
                a.velocity = a.velocity * (max_v / spd)
            a.position = a.position + a.velocity

            # Record position for spatial mapping
            a.position_history.append(a.position.copy())

            d_to_events = np.sqrt(np.sum((Z - a.position) ** 2, axis=1))
            penalties = np.zeros(n_events)
            for mem_idx, ev_idx in enumerate(reversed(a.recent_memory)):
                recency = mem_idx + 1
                penalties[ev_idx] += ((a.memory_size - recency + 1)
                                      * median_dist * 0.3)
            scores = d_to_events + penalties
            chosen = int(np.argmin(scores))
            a.history.append(chosen)
            a.recent_memory.append(chosen)
            if len(a.recent_memory) > a.memory_size:
                a.recent_memory.pop(0)

    return [a.history for a in agents]


# ═══════════════════════════════════════════════════════════════════════════
# Stage 6 — Spatial Mapping
# ═══════════════════════════════════════════════════════════════════════════

def compute_spatial_trajectories(agents, Z):
    """
    Project each agent's latent trajectory to 2D via PCA.
    Map X → azimuth (0°–360°), Y → distance (0–1).

    Returns per-agent list of (azimuth_deg, distance) per step.
    """
    import numpy as np

    # PCA on all event latents for a stable projection basis
    Z_c = Z - np.mean(Z, axis=0)
    cov = Z_c.T.dot(Z_c) / max(1, len(Z) - 1)
    eigvals, eigvecs = np.linalg.eigh(cov)
    idx = np.argsort(eigvals)[::-1]
    top2 = eigvecs[:, idx[:2]]

    # Gather all agent positions for normalization
    all_pos_2d = []
    for a in agents:
        for pos in a.position_history:
            p2d = (pos - np.mean(Z, axis=0)).dot(top2)
            all_pos_2d.append(p2d)
    all_pos_2d = np.array(all_pos_2d)

    # Normalize range
    if len(all_pos_2d) > 1:
        x_min, x_max = np.min(all_pos_2d[:, 0]), np.max(all_pos_2d[:, 0])
        y_min, y_max = np.min(all_pos_2d[:, 1]), np.max(all_pos_2d[:, 1])
    else:
        x_min, x_max = -1, 1
        y_min, y_max = -1, 1

    x_range = max(x_max - x_min, 1e-8)
    y_range = max(y_max - y_min, 1e-8)

    spatial_trajectories = []

    for a in agents:
        traj = []
        for pos in a.position_history:
            p2d = (pos - np.mean(Z, axis=0)).dot(top2)

            # X → azimuth: normalize to [0, 360]
            x_norm = (p2d[0] - x_min) / x_range
            azimuth = x_norm * 360.0

            # Y → distance: normalize to [0.1, 1.0]
            # (0.1 = close/loud, 1.0 = far/quiet)
            y_norm = (p2d[1] - y_min) / y_range
            distance = 0.1 + 0.9 * y_norm

            traj.append((azimuth, distance))
        spatial_trajectories.append(traj)

    return spatial_trajectories, top2


# ═══════════════════════════════════════════════════════════════════════════
# Stage 7 — Spatial Reconstruction
# ═══════════════════════════════════════════════════════════════════════════

def vbap_gains(azimuth_deg, speaker_azimuths_deg):
    """
    Vector Base Amplitude Panning for 2D circular speaker array.
    Returns gain per speaker (sums to ~1 in energy).
    """
    import numpy as np

    n_spk = len(speaker_azimuths_deg)
    gains = np.zeros(n_spk)

    # Find the two speakers that bracket the azimuth
    az = azimuth_deg % 360
    spk_az = np.array(speaker_azimuths_deg) % 360

    # Sort speakers by angle
    sorted_idx = np.argsort(spk_az)
    sorted_az = spk_az[sorted_idx]

    # Find bracketing pair
    left_idx = -1
    right_idx = -1
    for i in range(n_spk):
        j = (i + 1) % n_spk
        a1 = sorted_az[i]
        a2 = sorted_az[j]

        # Handle wrap-around
        if a2 < a1:
            a2 += 360
        check_az = az if az >= a1 else az + 360

        if a1 <= check_az <= a2:
            left_idx = sorted_idx[i]
            right_idx = sorted_idx[j]
            # Compute angular fractions
            span = a2 - a1
            if span < 0.1:
                span = 0.1
            frac = (check_az - a1) / span
            break

    if left_idx < 0:
        # Fallback: nearest speaker
        diffs = np.abs(spk_az - az)
        diffs = np.minimum(diffs, 360 - diffs)
        nearest = np.argmin(diffs)
        gains[nearest] = 1.0
        return gains

    # Equal-power panning between bracketing speakers
    angle = frac * (np.pi / 2)
    gains[left_idx] = np.cos(angle)
    gains[right_idx] = np.sin(angle)

    return gains


def distance_attenuation(distance):
    """
    Amplitude attenuation based on distance.
    distance: 0.1 (close) to 1.0 (far)
    Returns gain in [0.15, 1.0].
    """
    # Inverse distance law with minimum floor
    gain = 1.0 / (1.0 + 3.0 * (distance - 0.1))
    return max(0.15, min(1.0, gain))


def distance_lowpass(signal, distance, sr):
    """
    Simple first-order IIR low-pass filter.
    Cutoff frequency decreases with distance (proximity effect inverted:
    far = more muffled).
    """
    import numpy as np

    # Cutoff: close=20kHz (no filtering), far=2kHz
    cutoff = 20000.0 * (1.0 - 0.9 * distance)
    cutoff = max(500, min(20000, cutoff))

    # IIR coefficient
    rc = 1.0 / (2.0 * np.pi * cutoff)
    dt = 1.0 / sr
    alpha = dt / (rc + dt)

    # Apply filter
    out = np.zeros_like(signal)
    out[0] = signal[0]
    for i in range(1, len(signal)):
        out[i] = out[i - 1] + alpha * (signal[i] - out[i - 1])

    return out


def distance_reverb(signal, distance, sr, reverb_amount):
    """
    Simple distance-dependent reverb tail using comb filter.
    More reverb for distant sources.
    """
    import numpy as np

    if reverb_amount < 0.01:
        return signal

    # Reverb strength scales with distance and user control
    strength = distance * reverb_amount * 0.4
    strength = min(0.5, strength)

    if strength < 0.01:
        return signal

    # Short comb filter (simulates early reflections)
    delay_ms = 30 + 40 * distance  # 30-70 ms
    delay_samples = int(delay_ms * sr / 1000)

    out = signal.copy()
    for i in range(delay_samples, len(out)):
        out[i] += strength * out[i - delay_samples]

    # Second tap for density
    delay2 = int(delay_samples * 1.37)
    if delay2 < len(out):
        for i in range(delay2, len(out)):
            out[i] += strength * 0.5 * out[i - delay2]

    return out


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
            clips.append(np.mean(audio[s:e], axis=1).copy())
    return clips


def reconstruct_spatial(clips, agent_histories, agents,
                        spatial_trajectories, sr, target_samples,
                        spatial_format, distance_model, reverb_amount):
    """
    Render each agent into an N-channel spatial field.

    For each agent and each simulation step:
    1. Get the event audio clip
    2. Map latent position → azimuth + distance
    3. Apply VBAP gains to route audio to speakers
    4. Apply distance attenuation + filtering + reverb

    Returns: (target_samples, n_channels) output array
    """
    import numpy as np

    speaker_azimuths = SPEAKER_LAYOUTS[spatial_format]
    n_channels = len(speaker_azimuths)
    xfade = max(4, int(XFADE_SEC * sr))

    output = np.zeros((target_samples, n_channels), dtype=np.float32)

    # Volume scaling per agent profile
    agent_volumes = []
    for a in agents:
        if a.profile == AGENT_CANTUS:
            agent_volumes.append(0.55)
        elif a.profile == AGENT_FLORID:
            agent_volumes.append(0.40)
        elif a.profile == AGENT_SHADOW:
            agent_volumes.append(0.35)
        else:
            agent_volumes.append(0.40)

    # Crossfade templates
    angle_xf = np.linspace(0, np.pi / 2, xfade, dtype=np.float32)
    fade_in = np.sin(angle_xf)
    fade_out = np.cos(angle_xf)

    for ai, (history, agent) in enumerate(zip(agent_histories, agents)):
        spat_traj = spatial_trajectories[ai]
        vol = agent_volumes[ai]
        wp = 0  # write pointer for this agent

        for si, ev_idx in enumerate(history):
            clip = clips[ev_idx].copy().astype(np.float32)
            cl = len(clip)

            if cl < 4:
                continue

            # Get spatial position for this step
            if si < len(spat_traj):
                azimuth, distance = spat_traj[si]
            else:
                azimuth, distance = spat_traj[-1]

            # Smooth spatial transition from previous step
            if si > 0 and si - 1 < len(spat_traj):
                prev_az, prev_dist = spat_traj[si - 1]
                # Interpolate first 20% of clip from prev to current
                blend_len = min(cl // 5, int(sr * 0.05))
                if blend_len > 2:
                    blend_frac = np.linspace(0, 1, blend_len)
                else:
                    blend_frac = None
            else:
                blend_frac = None

            # Apply distance processing to mono clip
            dist_gain = distance_attenuation(distance)
            processed = clip * vol * dist_gain

            if distance_model >= DIST_AMP_LP:
                processed = distance_lowpass(processed, distance, sr)

            if distance_model >= DIST_AMP_LP_REVERB:
                processed = distance_reverb(processed, distance,
                                            sr, reverb_amount)

            # Apply crossfade at boundaries
            if si > 0 and cl >= xfade * 3:
                processed[:xfade] *= fade_in
            if si < len(history) - 1 and cl >= xfade * 3:
                processed[-xfade:] *= fade_out

            # VBAP gains for this position
            gains = vbap_gains(azimuth, speaker_azimuths)

            # Special case for 5.1: route low frequencies to LFE
            if spatial_format == SPAT_51:
                # LFE channel (index 3) gets a low-passed version
                lfe_signal = distance_lowpass(processed, 0.95, sr)
                lfe_gain = 0.15 * vol  # subtle LFE presence

            # Write to output channels
            end = wp + cl
            if end > target_samples:
                cl = target_samples - wp
                if cl <= 0:
                    break
                processed = processed[:cl]
                if spatial_format == SPAT_51:
                    lfe_signal = lfe_signal[:cl]

            # Handle spatial blending for smooth transitions
            for ch in range(n_channels):
                if spatial_format == SPAT_51 and ch == 3:
                    # LFE channel
                    output[wp:wp + cl, ch] += lfe_signal * lfe_gain
                    continue

                ch_signal = processed * gains[ch]

                # Smooth spatial blend for first portion
                if blend_frac is not None and len(blend_frac) <= cl:
                    prev_gains = vbap_gains(prev_az, speaker_azimuths)
                    bl = len(blend_frac)
                    ch_signal[:bl] = (
                        processed[:bl] * (
                            prev_gains[ch] * (1 - blend_frac)
                            + gains[ch] * blend_frac
                        )
                    )

                output[wp:wp + cl, ch] += ch_signal

            wp = end - xfade if (si < len(history) - 1
                                 and cl >= xfade * 3) else end

    # Normalize
    peak = np.max(np.abs(output))
    if peak > 0.95:
        output *= (0.95 / peak)
    elif 0 < peak < 0.1:
        output *= (0.5 / peak)

    return output


# ═══════════════════════════════════════════════════════════════════════════
# Stats
# ═══════════════════════════════════════════════════════════════════════════

def write_stats(path, events, agents, agent_histories,
                spatial_trajectories, Z, center, periphery,
                losses, sr, out_duration, spatial_format,
                distance_model, reverb_amount, n_channels, warnings):
    import numpy as np

    n_events = len(events)
    n_agents = len(agents)

    with open(path, "w") as f:
        f.write("n_events=%d\n" % n_events)
        f.write("n_agents=%d\n" % n_agents)
        f.write("n_channels=%d\n" % n_channels)
        f.write("spatial_format=%s\n" % SPAT_NAMES[spatial_format])
        f.write("distance_model=%s\n" % DIST_NAMES[distance_model])
        f.write("reverb_amount=%.2f\n" % reverb_amount)
        f.write("output_duration=%.3f\n" % out_duration)
        f.write("final_loss=%.6f\n" % (losses[-1] if losses else 0))
        f.write("initial_loss=%.6f\n" % (losses[0] if losses else 0))

        all_used = set()
        for ai, (hist, agent) in enumerate(zip(agent_histories, agents)):
            profile_name = AGENT_NAMES[agent.profile]
            unique = set(hist)
            all_used.update(unique)
            n_steps = len(hist)
            rep_rate = (n_steps - len(unique)) / max(1, n_steps)

            # Spatial stats
            traj = spatial_trajectories[ai]
            azimuths = [t[0] for t in traj]
            distances = [t[1] for t in traj]
            az_range = max(azimuths) - min(azimuths) if azimuths else 0
            mean_dist = np.mean(distances) if distances else 0

            # Spatial travel (total azimuth movement)
            az_travel = sum(abs(azimuths[i] - azimuths[i - 1])
                           for i in range(1, len(azimuths)))

            f.write("agent_%d_profile=%s\n" % (ai, profile_name))
            f.write("agent_%d_steps=%d\n" % (ai, n_steps))
            f.write("agent_%d_unique=%d\n" % (ai, len(unique)))
            f.write("agent_%d_rep_rate=%.3f\n" % (ai, rep_rate))
            f.write("agent_%d_az_range=%.1f\n" % (ai, az_range))
            f.write("agent_%d_az_travel=%.1f\n" % (ai, az_travel))
            f.write("agent_%d_mean_dist=%.3f\n" % (ai, mean_dist))

        f.write("total_unique_events=%d\n" % len(all_used))

        # Unison rates
        for ai in range(n_agents):
            for bi in range(ai + 1, n_agents):
                same = sum(1 for s in range(min(len(agent_histories[ai]),
                                                len(agent_histories[bi])))
                           if agent_histories[ai][s]
                           == agent_histories[bi][s])
                total = min(len(agent_histories[ai]),
                            len(agent_histories[bi]))
                f.write("unison_rate_%d_%d=%.3f\n" %
                        (ai, bi, same / max(1, total)))

        # Spatial separation: mean angular distance between agent pairs
        for ai in range(n_agents):
            for bi in range(ai + 1, n_agents):
                traj_a = spatial_trajectories[ai]
                traj_b = spatial_trajectories[bi]
                min_len = min(len(traj_a), len(traj_b))
                if min_len > 0:
                    ang_diffs = []
                    for s in range(min_len):
                        d = abs(traj_a[s][0] - traj_b[s][0])
                        d = min(d, 360 - d)
                        ang_diffs.append(d)
                    f.write("spatial_sep_%d_%d=%.1f\n" %
                            (ai, bi, np.mean(ang_diffs)))

        durations = [float(e["end_time"]) - float(e["start_time"])
                     for e in events]
        f.write("mean_event_dur=%.3f\n" % np.mean(durations))

        # Speaker labels
        labels = SPEAKER_LABELS[spatial_format]
        f.write("speaker_labels=%s\n" % "|".join(labels))

        for w in warnings:
            f.write("warning=%s\n" % w)


# ═══════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════

def main():
    if len(sys.argv) != 13:
        print("Usage: python latent_spat.py "
              "input.wav events.csv output.wav stats.txt "
              "num_agents latent_size counterpoint_rigidity speed "
              "duration spatial_format distance_model reverb_amount",
              file=sys.stderr)
        sys.exit(1)

    check_dependencies()

    import numpy as np
    import soundfile as sf

    in_wav       = sys.argv[1]
    events_csv   = sys.argv[2]
    out_wav      = sys.argv[3]
    stats_file   = sys.argv[4]
    num_agents   = int(sys.argv[5])
    latent_size  = int(sys.argv[6])
    cp_rigidity  = float(sys.argv[7])
    speed        = float(sys.argv[8])
    target_dur   = float(sys.argv[9])
    spat_format  = int(sys.argv[10])
    dist_model   = int(sys.argv[11])
    reverb_amt   = float(sys.argv[12])

    # Clamp
    num_agents   = max(2, min(6, num_agents))
    latent_size  = max(2, min(32, latent_size))
    cp_rigidity  = max(0.0, min(2.0, cp_rigidity))
    speed        = max(0.1, min(3.0, speed))
    spat_format  = max(0, min(3, spat_format))
    dist_model   = max(0, min(2, dist_model))
    reverb_amt   = max(0.0, min(1.0, reverb_amt))

    learning_steps = max(50, min(300, 80 + num_agents * 20))
    seed = 42

    np.random.seed(seed)
    warnings = []

    n_channels = len(SPEAKER_LAYOUTS[spat_format])

    # ---- Load ----
    print("  [Py 1/8] Loading audio + event table...")
    audio, sr = sf.read(in_wav, always_2d=False)
    audio = np.asarray(audio, dtype=np.float32)
    events = load_event_table(events_csv)
    n_samples = len(audio) if audio.ndim == 1 else audio.shape[0]
    orig_dur = n_samples / sr

    if target_dur <= 0:
        target_dur = orig_dur
    target_samples = int(target_dur * sr)

    print("    Audio: %.2fs  SR=%d  Events=%d  Agents=%d" %
          (orig_dur, sr, len(events), num_agents))
    print("    Spatial: %s (%dch) | Distance: %s | Reverb=%.2f" %
          (SPAT_NAMES[spat_format], n_channels,
           DIST_NAMES[dist_model], reverb_amt))

    if len(events) < 3:
        warnings.append("Too few events (%d)" % len(events))

    # ---- Mel patches ----
    print("  [Py 2/8] Extracting log-mel patches...")
    audio_mono = audio if audio.ndim == 1 else audio[:, 0]
    patches = extract_mel_patches(audio_mono.astype(np.float64), sr, events)

    # ---- Train AE ----
    print("  [Py 3/8] Training autoencoder (%d steps, latent=%d)..." %
          (learning_steps, latent_size))
    model, losses = train_autoencoder(patches, latent_size,
                                      learning_steps, seed)
    loss_ratio = losses[-1] / (losses[0] + 1e-12) if losses else 1.0
    print("    Loss: %.6f → %.6f (%.1f%% reduction)" % (
        losses[0], losses[-1], (1 - loss_ratio) * 100))

    # ---- Encode ----
    print("  [Py 4/8] Encoding events → latent space...")
    Z, recon_err = encode_events(model, patches)
    center, periphery, dists, median_dist = compute_latent_geometry(Z)

    # ---- Build agents ----
    print("  [Py 5/8] Initializing %d agents..." % num_agents)
    agents = build_agents(num_agents, latent_size, Z, center,
                          periphery, seed)
    for a in agents:
        print("    Agent %d: %s" % (a.agent_id, AGENT_NAMES[a.profile]))

    # ---- Physics ----
    mean_ev_dur = np.mean([float(e["end_time"]) - float(e["start_time"])
                           for e in events])
    n_sim_steps = max(5, int(target_dur / mean_ev_dur))
    n_sim_steps = min(n_sim_steps, len(events) * 12)

    print("  [Py 6/8] Running physics (%d steps)..." % n_sim_steps)
    agent_histories = run_physics(agents, Z, center, periphery, dists,
                                  median_dist, n_sim_steps, speed,
                                  cp_rigidity, seed)

    # ---- Spatial mapping ----
    print("  [Py 7/8] Computing spatial trajectories...")
    spatial_trajectories, pca_basis = \
        compute_spatial_trajectories(agents, Z)

    for ai, (agent, traj) in enumerate(zip(agents, spatial_trajectories)):
        azimuths = [t[0] for t in traj]
        distances = [t[1] for t in traj]
        print("    Agent %d: az=[%.0f°..%.0f°] dist=[%.2f..%.2f]" %
              (ai, min(azimuths), max(azimuths),
               min(distances), max(distances)))

    # ---- Spatial reconstruction ----
    print("  [Py 8/8] Rendering %d-channel spatial output..." % n_channels)
    clips = extract_event_clips(audio, events, sr)
    output = reconstruct_spatial(clips, agent_histories, agents,
                                 spatial_trajectories, sr, target_samples,
                                 spat_format, dist_model, reverb_amt)

    sf.write(out_wav, output, sr)

    out_dur = output.shape[0] / sr
    write_stats(stats_file, events, agents, agent_histories,
                spatial_trajectories, Z, center, periphery,
                losses, sr, out_dur, spat_format, dist_model,
                reverb_amt, n_channels, warnings)

    print("    Output: %.2fs × %dch | Peak: %.4f" %
          (out_dur, n_channels, np.max(np.abs(output))))

    # Spatial separation summary
    for ai in range(num_agents):
        for bi in range(ai + 1, num_agents):
            traj_a = spatial_trajectories[ai]
            traj_b = spatial_trajectories[bi]
            ml = min(len(traj_a), len(traj_b))
            if ml > 0:
                sep = np.mean([min(abs(traj_a[s][0] - traj_b[s][0]),
                                   360 - abs(traj_a[s][0] - traj_b[s][0]))
                               for s in range(ml)])
                print("    Spatial sep %d↔%d: %.0f°" % (ai, bi, sep))

    print("OK: wrote %s" % out_wav)


if __name__ == "__main__":
    main()
