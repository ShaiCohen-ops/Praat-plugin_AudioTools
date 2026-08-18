"""
latent_counterpoint.py — The Latent Counterpoint

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University
Version: 1.4 (2026)

Changelog v1.4:
    - Adaptive local equal-power splicing replaces global click smoothing;
      genuine transients are no longer median-filtered as false clicks.
    - Safe release at the rendered layer end prevents hard target truncation.
    - Phase-safe multichannel fold-down falls back to the strongest channel
      only when channel averaging nearly cancels.
    - One/degenerate-event latent geometry now has a finite scale fallback.
    - Polyphonic timeline stats mirror the actual adaptive splice positions.
    - Output WAV is 32-bit FLOAT.

Usage (called by Praat, not directly):
    python latent_counterpoint.py input.wav events.csv output.wav stats.txt
        num_agents latent_size counterpoint_rigidity speed duration seed

Architecture:
    Stage 1 — Load audio + event table from Praat
    Stage 2 — Extract fixed-size log-mel patches per event
    Stage 3 — Train lightweight autoencoder on-the-fly (numpy only)
    Stage 4 — Encode events → latent vectors Z
    Stage 5 — Physics engine: K agents navigate latent space with
              inertia, attraction, repulsion (counterpoint), jitter
    Stage 6 — Polyphonic reconstruction: sum agent outputs with
              independent crossfading and volume scaling
    Stage 7 — Output + report

Agent profiles:
    A (Cantus):  High mass, slow, gravitates to latent center of gravity
    B (Florid):  Low mass, fast, attracted to latent periphery (rare sounds)
    C (Shadow):  Mirrors Cantus with temporal lag + inverted coordinates

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

# Agent profile types
AGENT_CANTUS = 0   # heavy, central
AGENT_FLORID = 1   # light, peripheral
AGENT_SHADOW = 2   # mirrors cantus with lag + inversion

AGENT_NAMES = ["Cantus", "Florid", "Shadow"]


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
    Load Praat-exported event table.
    Accepts any CSV with at least start_time and end_time columns.
    Additional columns (label, pitch_stability, etc.) used if present.
    """
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
    """
    MLP autoencoder: input → hidden → latent → hidden → output.
    Leaky ReLU activations. Denoising. L2 regularization. Adam optimizer.
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
# Stage 4 — Latent Encoding
# ═══════════════════════════════════════════════════════════════════════════

def encode_events(model, patches):
    """Encode all events → latent vectors Z. Returns Z, recon_errors."""
    import numpy as np

    X = (patches - model._norm_mu) / model._norm_sigma
    Z = model.encode(X)
    recon_err = model.reconstruction_errors(X)
    return Z, recon_err


def compute_latent_geometry(Z):
    """
    Compute latent space geometry used by the physics engine:
    - center of gravity
    - per-event distance from center (periphery score)
    - pairwise distance matrix
    - median inter-event distance (scale reference)
    """
    import numpy as np
    from scipy.spatial.distance import cdist

    center = np.mean(Z, axis=0)
    dist_from_center = np.sqrt(np.sum((Z - center) ** 2, axis=1))
    periphery = dist_from_center / (np.max(dist_from_center) + 1e-8)

    dists = cdist(Z, Z, metric="euclidean")
    np.fill_diagonal(dists, np.inf)
    finite = dists[np.isfinite(dists) & (dists > 1e-9)]
    # Praat can legitimately fall back to a single event on short/simple
    # sources.  In that case there is no inter-event distance to measure;
    # use a finite unit scale so the physics remains deterministic instead
    # of propagating NaNs.  The selected event is still the real event.
    median_dist = float(np.median(finite)) if finite.size else 1.0

    return center, periphery, dists, median_dist


# ═══════════════════════════════════════════════════════════════════════════
# Stage 5 — Physics Engine: Multi-Agent Counterpoint
# ═══════════════════════════════════════════════════════════════════════════

class Agent(object):
    """
    A voice in the latent counterpoint.

    Each agent has:
    - position: current latent coordinate
    - velocity: current movement vector
    - mass: inertia (high = slow to change direction)
    - profile: behavioral type (Cantus/Florid/Shadow)
    - memory: recently used event indices (LRU)
    - history: sequence of chosen event indices
    """

    def __init__(self, agent_id, profile, latent_dim, seed):
        import numpy as np
        self.agent_id = agent_id
        self.profile = profile
        self.rng = np.random.RandomState(seed + agent_id * 137)
        self.latent_dim = latent_dim

        self.position = np.zeros(latent_dim)
        self.velocity = np.zeros(latent_dim)
        self.history = []
        self.recent_memory = []  # LRU queue
        self.memory_size = 15    # how many recent events to avoid

        # Profile-specific parameters
        if profile == AGENT_CANTUS:
            self.mass = 1.2         # REDUCED: Allows more movement
            self.max_speed = 0.8    # INCREASED: Faster exploration
            self.jitter_scale = 0.25 # INCREASED: Breaks local loops
            self.attraction_weight = 1.0
        elif profile == AGENT_FLORID:
            self.mass = 0.5         
            self.max_speed = 1.5    
            self.jitter_scale = 0.50 # INCREASED: Maximizes variety
            self.attraction_weight = 0.6
        elif profile == AGENT_SHADOW:
            self.mass = 1.5         # REDUCED: More responsive
            self.max_speed = 0.6    # INCREASED: Matches new Cantus speed
            self.jitter_scale = 0.30 # INCREASED: Randomizes the lag path
            self.attraction_weight = 0.3
            self.lag_buffer = []    
            self.lag_steps = 20     # INCREASED: Forces Shadow away from Cantus

    def init_position(self, Z, center, periphery):
        """Initialize agent position based on profile."""
        import numpy as np

        if self.profile == AGENT_CANTUS:
            # Start at center of gravity
            self.position = center.copy()

        elif self.profile == AGENT_FLORID:
            # Start at most peripheral event
            most_peripheral = np.argmax(periphery)
            self.position = Z[most_peripheral].copy()

        elif self.profile == AGENT_SHADOW:
            # Start at inverse of center (reflected through centroid)
            self.position = 2.0 * center - Z[np.argmax(periphery)].copy()


def build_agents(num_agents, latent_dim, Z, center, periphery, seed):
    """
    Create K agents with assigned profiles.
    Profile assignment order: Cantus, Florid, Shadow, then cycle.
    """
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
    """
    Run the multi-agent physics simulation.

    At each timestep, for each agent:
    1. Compute attraction force (toward nearest interesting event)
    2. Compute repulsion force (away from other agents)
    3. Compute profile-specific force (center/periphery/shadow)
    4. Add jitter
    5. Update velocity with inertia
    6. Clamp speed
    7. Update position
    8. Select nearest unused event (LRU)

    Returns: per-agent event sequences (list of lists of event indices)
    """
    import numpy as np

    n_events = len(Z)
    rng = np.random.RandomState(seed + 999)

    # Find cantus agent for shadow mirroring
    cantus_agent = None
    for a in agents:
        if a.profile == AGENT_CANTUS:
            cantus_agent = a
            break

    for step in range(n_steps):
        # --- Compute forces for all agents ---
        forces = []
        for a in agents:
            force = np.zeros(a.latent_dim)

            # 1. Attraction: pull toward nearest event in latent space
            d_to_events = np.sqrt(np.sum((Z - a.position) ** 2, axis=1))

            if a.profile == AGENT_CANTUS:
                # Cantus: attracted to center of gravity
                center_pull = center - a.position
                d_center = np.linalg.norm(center_pull)
                if d_center > 1e-8:
                    force += (center_pull / d_center
                              * a.attraction_weight * speed * 0.5)
                # Also mild pull toward nearest event
                nearest = np.argmin(d_to_events)
                pull = Z[nearest] - a.position
                d_pull = np.linalg.norm(pull)
                if d_pull > 1e-8:
                    force += pull / d_pull * a.attraction_weight * speed * 0.3

            elif a.profile == AGENT_FLORID:
                # Florid: attracted to peripheral (rare) events
                # Weight events by periphery score
                weighted_d = d_to_events / (periphery + 0.1)
                nearest = np.argmin(weighted_d)
                pull = Z[nearest] - a.position
                d_pull = np.linalg.norm(pull)
                if d_pull > 1e-8:
                    force += (pull / d_pull
                              * a.attraction_weight * speed * 0.8)

            elif a.profile == AGENT_SHADOW:
                # Shadow: mirrors cantus with lag + inversion
                if cantus_agent is not None:
                    # Record cantus position in lag buffer
                    a.lag_buffer.append(cantus_agent.position.copy())

                    if len(a.lag_buffer) > a.lag_steps:
                        # Use lagged cantus position
                        lagged_pos = a.lag_buffer[-a.lag_steps]
                        # Invert through center
                        mirror_target = 2.0 * center - lagged_pos
                        pull = mirror_target - a.position
                        d_pull = np.linalg.norm(pull)
                        if d_pull > 1e-8:
                            force += (pull / d_pull
                                      * a.attraction_weight * speed * 0.6)
                    else:
                        # Not enough lag yet — mild center pull
                        pull = center - a.position
                        d_pull = np.linalg.norm(pull)
                        if d_pull > 1e-8:
                            force += pull / d_pull * 0.2

                # Also mild attraction to nearest event
                nearest = np.argmin(d_to_events)
                pull = Z[nearest] - a.position
                d_pull = np.linalg.norm(pull)
                if d_pull > 1e-8:
                    force += pull / d_pull * a.attraction_weight * speed * 0.2

            # 2. Repulsion from other agents (counterpoint force)
            for other in agents:
                if other.agent_id == a.agent_id:
                    continue
                diff = a.position - other.position
                d_between = np.linalg.norm(diff)
                if d_between < 1e-8:
                    # Nudge apart deterministically
                    diff = rng.randn(a.latent_dim) * 0.01
                    d_between = np.linalg.norm(diff) + 1e-8

                # Inverse-square repulsion, scaled by rigidity
                repulsion_strength = (counterpoint_rigidity
                                      * median_dist ** 2
                                      / (d_between ** 2 + 1e-6))
                # Cap repulsion to prevent explosion
                repulsion_strength = min(repulsion_strength,
                                         speed * 3.0)
                force += (diff / d_between) * repulsion_strength

            # 3. Jitter (deterministic pseudo-random)
            jitter = rng.randn(a.latent_dim) * a.jitter_scale * speed
            force += jitter

            forces.append(force)

        # --- Update agents ---
        chosen_pos_this_step = []
        for ai, a in enumerate(agents):
            # Inertia: F = ma → a = F/m
            acceleration = forces[ai] / a.mass

            # Update velocity with damping
            damping = 0.985
            a.velocity = damping * a.velocity + acceleration

            # Clamp speed
            spd = np.linalg.norm(a.velocity)
            max_v = a.max_speed * speed * median_dist
            if spd > max_v:
                a.velocity = a.velocity * (max_v / spd)

            # Update position
            a.position = a.position + a.velocity

            # --- Select nearest event with LRU ---
            d_to_events = np.sqrt(np.sum((Z - a.position) ** 2, axis=1))

            # LRU penalty: recently used events get distance penalty
            penalties = np.zeros(n_events)
            for mem_idx, ev_idx in enumerate(reversed(a.recent_memory)):
                recency = mem_idx + 1
                penalties[ev_idx] += (a.memory_size - recency + 1
                                      ) * median_dist * 5.0

            scores = d_to_events + penalties

            # Counterpoint separation (rigidity): push this voice away from
            # events lying near the events the OTHER voices have already
            # selected this step. The spatial repulsion force alone is too
            # weak (it is capped at speed*3 and the velocity is clamped) to
            # give rigidity an audible, monotonic effect - voice separation
            # barely changed across the whole 0..2 range. The counterpoint
            # constraint is therefore also applied directly at selection time
            # as a graded Gaussian proximity penalty: higher rigidity makes
            # each voice pick more contrasting (latent-distant) events.
            # Verified monotonic on the live engine.
            for _zp in chosen_pos_this_step:
                _prox = np.exp(-np.sum((Z - _zp) ** 2, axis=1)
                               / (median_dist ** 2 + 1e-9))
                scores = scores + counterpoint_rigidity * median_dist * _prox

            chosen = int(np.argmin(scores))
            chosen_pos_this_step.append(Z[chosen])

            a.history.append(chosen)

            # Update LRU memory
            a.recent_memory.append(chosen)
            if len(a.recent_memory) > a.memory_size:
                a.recent_memory.pop(0)

    return [a.history for a in agents]


# ═══════════════════════════════════════════════════════════════════════════
# Stage 6 — Polyphonic Reconstruction
# ═══════════════════════════════════════════════════════════════════════════

def extract_event_clips(audio, events, sr):
    """Extract audio clips for each event."""
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


def _phase_safe_mono_clip(clip):
    """Fold a clip to mono without destroying strongly anti-phase stereo."""
    import numpy as np
    clip = np.asarray(clip, dtype=np.float32)
    if clip.ndim == 1:
        return clip.copy(), False
    if clip.shape[1] == 1:
        return clip[:, 0].copy(), False

    mean = np.mean(clip, axis=1).astype(np.float32)
    mean_rms = float(np.sqrt(np.mean(mean.astype(np.float64) ** 2)))
    ch_rms = np.sqrt(np.mean(clip.astype(np.float64) ** 2, axis=0))
    strongest = int(np.argmax(ch_rms))
    max_rms = float(ch_rms[strongest])
    if max_rms > 1e-9 and mean_rms < 0.10 * max_rms:
        return clip[:, strongest].copy().astype(np.float32), True
    return mean, False


def _splice_xfade_len(prev_len, cur_len, xfade):
    """Adaptive crossfade length; long clips retain the legacy 8 ms splice."""
    if prev_len <= 1 or cur_len <= 1:
        return 0
    return max(1, min(xfade, prev_len // 4, cur_len // 4))


def reconstruct_polyphonic(clips, agent_histories, agents, sr,
                           target_samples, Z):
    """
    Sum the audio outputs of all agents into a stereo mix.

    Each agent:
    - Concatenates its event sequence with local equal-power crossfades
    - Gets independent volume scaling (based on profile)
    - Gets stereo panning (Cantus center, Florid right, Shadow left)

    Final mix is summed and normalized.
    """
    import numpy as np

    n_agents = len(agents)
    xfade = max(4, int(XFADE_SEC * sr))

    # Convert each event once. Ordinary multichannel material keeps the
    # historical channel mean; only near-cancelling folds use a strong channel.
    mono_clips = []
    phase_safe_events = 0
    for clip in clips:
        mono, used_fallback = _phase_safe_mono_clip(clip)
        mono_clips.append(mono)
        phase_safe_events += int(used_fallback)

    # Always produce stereo output
    output = np.zeros((target_samples, 2), dtype=np.float32)

    # Per-agent volume and pan
    agent_configs = []
    for a in agents:
        if a.profile == AGENT_CANTUS:
            vol = 0.6
            pan = 0.5
        elif a.profile == AGENT_FLORID:
            vol = 0.4
            pan = 0.75
        elif a.profile == AGENT_SHADOW:
            vol = 0.35
            pan = 0.25
        else:
            vol = 0.4
            pan = 0.5
        agent_configs.append((vol, pan))

    agent_layers = []

    for ai, (history, agent) in enumerate(zip(agent_histories, agents)):
        vol, pan = agent_configs[ai]
        sequence = [mono_clips[ev_idx] for ev_idx in history]

        # Concatenate with adaptive local crossfades.  No global click detector:
        # transient peaks are musical data, not errors.
        layer = _concatenate_mono(sequence, xfade, target_samples)
        layer *= vol

        # Equal-power panning
        angle = pan * (np.pi / 2)
        gain_L = np.cos(angle)
        gain_R = np.sin(angle)

        layer_stereo = np.zeros((len(layer), 2), dtype=np.float32)
        layer_stereo[:, 0] = layer * gain_L
        layer_stereo[:, 1] = layer * gain_R

        fit_len = min(len(layer_stereo), target_samples)
        output[:fit_len] += layer_stereo[:fit_len]
        agent_layers.append(layer)

    # Normalize only for safety / legacy quiet-output behavior
    peak = np.max(np.abs(output))
    if peak > 0.95:
        output *= (0.95 / peak)
    elif peak > 0 and peak < 0.1:
        output *= (0.5 / peak)

    return output, agent_layers, phase_safe_events


def _concatenate_mono(sequence, xfade, target_length):
    """Sequential equal-power OLA with adaptive crossfade for short clips."""
    import numpy as np

    if not sequence:
        return np.zeros(max(1, target_length), dtype=np.float32)

    total = sum(len(c) for c in sequence)
    output = np.zeros(total + max(4, xfade) * 2, dtype=np.float32)
    wp = 0
    prev_len = 0

    for ci, src in enumerate(sequence):
        clip = np.asarray(src, dtype=np.float32).copy()
        cl = len(clip)
        if cl <= 0:
            continue

        xf = 0 if ci == 0 else _splice_xfade_len(prev_len, cl, xfade)
        start = max(0, wp - xf)
        end = start + cl
        if end > len(output):
            output = np.pad(output, (0, end - len(output) + max(4, xfade)))

        if xf > 0:
            angle = np.linspace(0, np.pi / 2, xf, dtype=np.float32)
            output[start:wp] *= np.cos(angle)
            clip[:xf] *= np.sin(angle)

        output[start:end] += clip
        wp = end
        prev_len = cl

    raw = output[:wp].copy()

    # Enforce duration, but never hard-cut a non-zero waveform edge.  A short
    # local release affects only the final few milliseconds, not internal attacks.
    if target_length > 0:
        if len(raw) >= target_length:
            out = raw[:target_length].copy()
        else:
            out = np.zeros(target_length, dtype=np.float32)
            out[:len(raw)] = raw

        signal_end = min(len(raw), target_length)
        if signal_end > 1:
            rel = min(max(4, xfade // 2), signal_end // 4)
            if rel > 1:
                release = np.cos(np.linspace(0, np.pi / 2, rel,
                                             dtype=np.float32))
                out[signal_end - rel:signal_end] *= release
        return out

    return raw


# ═══════════════════════════════════════════════════════════════════════════
# Stage 7 — Stats Output
# ═══════════════════════════════════════════════════════════════════════════

def write_stats(path, events, agents, agent_histories, Z, center,
                periphery, losses, sr, out_duration, warnings,
                clips=None, median_dist=1.0, phase_safe_events=0):
    """Write detailed stats report for Praat."""
    import numpy as np

    n_events = len(events)
    n_agents = len(agents)

    with open(path, "w") as f:
        f.write("n_events=%d\n" % n_events)
        f.write("n_agents=%d\n" % n_agents)
        f.write("output_duration=%.3f\n" % out_duration)
        f.write("final_loss=%.6f\n" % (losses[-1] if losses else 0))
        f.write("initial_loss=%.6f\n" % (losses[0] if losses else 0))
        f.write("phase_safe_events=%d\n" % int(phase_safe_events))
        f.write("splice_mode=adaptive_equal_power\n")

        # Mean simultaneous latent separation, normalized by corpus scale.
        sep_vals = []
        max_steps = max([len(h) for h in agent_histories]) if agent_histories else 0
        for st in range(max_steps):
            chosen = [Z[h[st]] for h in agent_histories if st < len(h)]
            for ia in range(len(chosen)):
                for ib in range(ia + 1, len(chosen)):
                    sep_vals.append(float(np.linalg.norm(chosen[ia] - chosen[ib])))
        mean_sep_ratio = (float(np.mean(sep_vals)) / max(float(median_dist), 1e-9)
                          if sep_vals else 0.0)
        f.write("mean_separation_ratio=%.4f\n" % mean_sep_ratio)

        # Per-agent stats
        all_used = set()
        for ai, (hist, agent) in enumerate(zip(agent_histories, agents)):
            profile_name = AGENT_NAMES[agent.profile]
            unique = set(hist)
            all_used.update(unique)
            n_steps = len(hist)

            # Repetition rate
            rep_rate = (n_steps - len(unique)) / max(1, n_steps)

            # Latent travel distance
            travel_dists = []
            for i in range(1, len(hist)):
                d = np.linalg.norm(Z[hist[i]] - Z[hist[i - 1]])
                travel_dists.append(d)
            avg_travel = np.mean(travel_dists) if travel_dists else 0

            # Mean periphery of chosen events
            chosen_periphery = np.mean([periphery[idx] for idx in hist])

            # Usage distribution
            usage = np.zeros(n_events, dtype=int)
            for idx in hist:
                usage[idx] += 1
            top_ev = np.argmax(usage)

            f.write("agent_%d_profile=%s\n" % (ai, profile_name))
            f.write("agent_%d_steps=%d\n" % (ai, n_steps))
            f.write("agent_%d_unique=%d\n" % (ai, len(unique)))
            f.write("agent_%d_rep_rate=%.3f\n" % (ai, rep_rate))
            f.write("agent_%d_avg_travel=%.4f\n" % (ai, avg_travel))
            f.write("agent_%d_mean_periphery=%.3f\n" % (
                ai, chosen_periphery))
            f.write("agent_%d_top_event=%d|%d_uses\n" % (
                ai, top_ev, usage[top_ev]))

        # Global stats
        f.write("total_unique_events=%d\n" % len(all_used))

        # Inter-agent distances (counterpoint effectiveness)
        for ai in range(n_agents):
            for bi in range(ai + 1, n_agents):
                same_count = 0
                min_len = min(len(agent_histories[ai]),
                              len(agent_histories[bi]))
                for step in range(min_len):
                    if agent_histories[ai][step] == agent_histories[bi][step]:
                        same_count += 1
                unison_rate = same_count / max(1, min_len)
                f.write("unison_rate_%d_%d=%.3f\n" % (ai, bi, unison_rate))

        # Mean event duration
        durations = [float(e["end_time"]) - float(e["start_time"])
                     for e in events]
        f.write("mean_event_dur=%.3f\n" % np.mean(durations))

        # ── Per-agent polyphonic timeline ─────────────────────────────
        # Compute cumulative time positions per agent from clip lengths.
        # Each agent independently concatenates clips with crossfade
        # overlap, so their timelines are independent.
        xfade_sec = XFADE_SEC
        if clips is not None:
            for ai, hist in enumerate(agent_histories):
                blocks = []
                wp_samp = 0
                prev_len = 0
                target_samp = int(round(out_duration * sr)) if sr > 0 else 0
                xfade_samp = max(4, int(XFADE_SEC * sr))
                for si, ev_idx in enumerate(hist):
                    clip = clips[ev_idx]
                    clip_len = len(clip) if hasattr(clip, '__len__') else 0
                    if clip_len <= 0:
                        continue
                    xf = 0 if si == 0 else _splice_xfade_len(prev_len, clip_len, xfade_samp)
                    start_samp = max(0, wp_samp - xf)
                    end_samp = start_samp + clip_len
                    if target_samp > 0 and start_samp >= target_samp:
                        break
                    draw_end = min(end_samp, target_samp) if target_samp > 0 else end_samp
                    blocks.append((ev_idx, start_samp / sr, draw_end / sr))
                    wp_samp = end_samp
                    prev_len = clip_len

                # Run-length compress consecutive same-event blocks
                compressed = []
                for ev_idx, bs, be in blocks:
                    if compressed and compressed[-1][0] == ev_idx:
                        # Extend the previous block
                        compressed[-1] = (ev_idx, compressed[-1][1], be)
                    else:
                        compressed.append((ev_idx, bs, be))

                # Cap at 150 blocks per agent for file size
                n_bl = min(len(compressed), 150)
                f.write("ag_%d_n_blocks=%d\n" % (ai, n_bl))
                for bi in range(n_bl):
                    ev_idx, bs, be = compressed[bi]
                    f.write("ag_%d_bl_%d=%d,%.4f,%.4f\n" % (
                        ai, bi, ev_idx, bs, be))

        if warnings:
            f.write("warning=%s\n" % "; ".join(warnings))


# ═══════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════

def main():
    if len(sys.argv) != 11:
        print("Usage: python latent_counterpoint.py "
              "input.wav events.csv output.wav stats.txt "
              "num_agents latent_size counterpoint_rigidity speed duration seed",
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
    seed         = int(sys.argv[10])

    # Clamp
    num_agents   = max(2, min(6, num_agents))
    latent_size  = max(2, min(32, latent_size))
    cp_rigidity  = max(0.0, min(2.0, cp_rigidity))
    speed        = max(0.1, min(3.0, speed))

    learning_steps = max(50, min(300, 80 + num_agents * 20))

    np.random.seed(seed)
    warnings = []

    # ---- Load ----
    print("  [Py 1/7] Loading audio + event table...")
    audio, sr = sf.read(in_wav, always_2d=False)
    audio = np.asarray(audio, dtype=np.float32)
    events = load_event_table(events_csv)
    n_samples = len(audio) if audio.ndim == 1 else audio.shape[0]
    orig_dur = n_samples / sr

    if target_dur <= 0:
        target_dur = orig_dur
    target_samples = int(target_dur * sr)

    print("    Audio: %.2fs  SR=%d  Shape=%s" % (orig_dur, sr, audio.shape))
    print("    Events: %d  |  Agents: %d" % (len(events), num_agents))

    if len(events) < 3:
        warnings.append("Too few events (%d) for meaningful counterpoint"
                         % len(events))
        print("    WARNING: " + warnings[-1])

    # ---- Mel patches ----
    print("  [Py 2/7] Extracting log-mel patches...")
    audio_mono = audio if audio.ndim == 1 else audio[:, 0]
    patches = extract_mel_patches(audio_mono.astype(np.float64), sr, events)
    print("    Patch shape: %s" % str(patches.shape))

    # ---- Train AE ----
    print("  [Py 3/7] Training autoencoder (%d steps, latent=%d)..." %
          (learning_steps, latent_size))
    model, losses = train_autoencoder(patches, latent_size,
                                      learning_steps, seed)
    loss_ratio = losses[-1] / (losses[0] + 1e-12) if losses else 1.0
    print("    Loss: %.6f → %.6f (%.1f%% reduction)" % (
        losses[0], losses[-1], (1 - loss_ratio) * 100))

    if loss_ratio > 0.95:
        warnings.append("Autoencoder did not converge well")

    # ---- Encode ----
    print("  [Py 4/7] Encoding events → latent space...")
    Z, recon_err = encode_events(model, patches)
    center, periphery, dists, median_dist = compute_latent_geometry(Z)
    print("    Latent center norm: %.3f  |  Median dist: %.3f" %
          (np.linalg.norm(center), median_dist))

    # ---- Build agents ----
    print("  [Py 5/7] Initializing %d agents..." % num_agents)
    agents = build_agents(num_agents, latent_size, Z, center,
                          periphery, seed)
    for a in agents:
        print("    Agent %d: %s (mass=%.1f, max_speed=%.1f)" %
              (a.agent_id, AGENT_NAMES[a.profile], a.mass, a.max_speed))

    # ---- Physics simulation ----
    mean_ev_dur = np.mean([float(e["end_time"]) - float(e["start_time"])
                           for e in events])
    # Each step selects one event per agent; compute steps from
    # target duration / mean event duration
    n_sim_steps = max(5, int(target_dur / mean_ev_dur))
    n_sim_steps = min(n_sim_steps, len(events) * 12)

    print("  [Py 6/7] Running physics (%d steps, rigidity=%.2f, "
          "speed=%.2f)..." % (n_sim_steps, cp_rigidity, speed))
    agent_histories = run_physics(agents, Z, center, periphery, dists,
                                  median_dist, n_sim_steps, speed,
                                  cp_rigidity, seed)

    for ai, (hist, agent) in enumerate(zip(agent_histories, agents)):
        unique = len(set(hist))
        print("    Agent %d (%s): %d steps, %d/%d unique" %
              (ai, AGENT_NAMES[agent.profile],
               len(hist), unique, len(events)))

    # ---- Reconstruct ----
    print("  [Py 7/7] Reconstructing polyphonic output...")
    clips = extract_event_clips(audio, events, sr)
    output, agent_layers, phase_safe_events = reconstruct_polyphonic(
        clips, agent_histories, agents, sr, target_samples, Z)

    sf.write(out_wav, output, sr, subtype="FLOAT")

    out_dur = output.shape[0] / sr
    write_stats(stats_file, events, agents, agent_histories, Z,
                center, periphery, losses, sr, out_dur, warnings,
                clips=clips, median_dist=median_dist,
                phase_safe_events=phase_safe_events)

    # Check unison rates
    for ai in range(num_agents):
        for bi in range(ai + 1, num_agents):
            same = sum(1 for s in range(min(len(agent_histories[ai]),
                                            len(agent_histories[bi])))
                       if agent_histories[ai][s] == agent_histories[bi][s])
            total = min(len(agent_histories[ai]), len(agent_histories[bi]))
            rate = same / max(1, total)
            print("    Unison %d↔%d: %.1f%%" % (ai, bi, rate * 100))

    print("    Output: %.2fs stereo | Peak: %.4f" % (
        out_dur, np.max(np.abs(output))))
    print("OK: wrote %s" % out_wav)


if __name__ == "__main__":
    main()
