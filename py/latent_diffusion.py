"""
latent_diffusion.py — Latent Diffusion Resynthesis (Morph-Chain)

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University

Usage (called by Praat, not directly):
    python latent_diffusion.py input.wav events.csv output.wav stats.txt
        latent_size learning_steps n_clusters diffusion_steps
        entropy_threshold temperature_start temperature_end
        denoising_strength seed

Architecture:
    Stage 1 — Load audio + event table
    Stage 2 — Extract log-mel patches (40 mels × 32 frames)
    Stage 3 — Train on-the-fly autoencoder (numpy, manual backprop + Adam)
    Stage 4 — Encode events → latent vectors Z
    Stage 5 — Diffusion Engine:
               (a) Discover K identity clusters via k-means++ (numpy only)
               (b) Compute per-cluster Gaussian statistics
               (c) For each cluster, select seed event (most peripheral)
               (d) Corrupt seed: add calibrated Gaussian noise
               (e) Iterative refinement — for each step t:
                     · Compute cross-entropy with each cluster Gaussian
                     · Boltzmann soft-weights at temperature T_t
                     · Gradient drift toward minimum-entropy cluster
                     · Add annealed residual noise √T_t · ε
                     · Apply 1/T scaling (low T = deterministic convergence)
                     · Early-stop when min cross-entropy < threshold
    Stage 6 — Morph-Chain Reconstruction:
               Map each diffusion-step Z → nearest real event → audio clip.
               One chain per cluster, ordered noisy→clean.
               Chains concatenated with brief silence gaps.
    Stage 7 — Output + stats

No external downloads. No PyTorch / TensorFlow / sklearn.
Pure numpy + soundfile + scipy.
"""

import sys
import math

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
N_MELS     = 40
MEL_FRAMES = 32
XFADE_SEC  = 0.008
SILENCE_GAP_SEC = 0.06   # gap between morph chains


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
        print("Install with:  pip install " + " ".join(missing),
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
    low_mel  = hz_to_mel(20)
    high_mel = hz_to_mel(sr / 2)
    mel_pts  = np.linspace(low_mel, high_mel, n_mels + 2)
    hz_pts   = mel_to_hz(mel_pts)
    bin_pts  = np.floor((n_fft + 1) * hz_pts / sr).astype(int)
    bin_pts  = np.clip(bin_pts, 0, n_bins - 1)

    fb = np.zeros((n_mels, n_bins))
    for m in range(1, n_mels + 1):
        fl, fc, fr = bin_pts[m - 1], bin_pts[m], bin_pts[m + 1]
        for k in range(fl, fc):
            if fc > fl:
                fb[m - 1, k] = (k - fl) / (fc - fl)
        for k in range(fc, fr):
            if fr > fc:
                fb[m - 1, k] = (fr - k) / (fr - fc)
    return fb


def extract_mel_patches(audio_mono, sr, events):
    import numpy as np

    n_fft  = 1024
    hop    = 256
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
            end   = start + n_fft
            if end > len(segment):
                frame = np.zeros(n_fft)
                frame[:len(segment) - start] = segment[start:]
            else:
                frame = segment[start:end]
            frame = (frame * window[:len(frame)]
                     if len(frame) == n_fft else np.zeros(n_fft))
            spec = np.abs(np.fft.rfft(frame)) ** 2
            mel_spec[:, fi] = np.log(mel_fb.dot(spec) + 1e-10)

        if n_frames >= MEL_FRAMES:
            off   = (n_frames - MEL_FRAMES) // 2
            patch = mel_spec[:, off:off + MEL_FRAMES]
        else:
            patch = np.zeros((N_MELS, MEL_FRAMES))
            off   = (MEL_FRAMES - n_frames) // 2
            patch[:, off:off + n_frames] = mel_spec
            for pi in range(off):
                patch[:, pi] = mel_spec[:, 0]
            for pi in range(off + n_frames, MEL_FRAMES):
                patch[:, pi] = mel_spec[:, -1]

        patches.append(patch.flatten())
    return np.array(patches, dtype=np.float64)


# ═══════════════════════════════════════════════════════════════════════════
# Stage 3 — Numpy Autoencoder  (identical architecture to the rest of the suite)
# ═══════════════════════════════════════════════════════════════════════════

class NumpyAutoencoder(object):
    """
    MLP autoencoder: input → hidden → latent → hidden → output.
    Leaky ReLU activations. Denoising. L2 regularisation. Adam optimiser.
    Pure numpy — no external ML framework required.
    """

    def __init__(self, input_dim, hidden_dim, latent_dim, seed=42):
        import numpy as np
        self.rng        = np.random.RandomState(seed)
        self.input_dim  = input_dim
        self.hidden_dim = hidden_dim
        self.latent_dim = latent_dim

        s_eh = np.sqrt(2.0 / (input_dim  + hidden_dim))
        s_hl = np.sqrt(2.0 / (hidden_dim + latent_dim))
        s_lh = np.sqrt(2.0 / (latent_dim + hidden_dim))
        s_ho = np.sqrt(2.0 / (hidden_dim + input_dim))

        self.W1 = self.rng.randn(input_dim,  hidden_dim) * s_eh
        self.b1 = np.zeros(hidden_dim)
        self.W2 = self.rng.randn(hidden_dim, latent_dim) * s_hl
        self.b2 = np.zeros(latent_dim)
        self.W3 = self.rng.randn(latent_dim, hidden_dim) * s_lh
        self.b3 = np.zeros(hidden_dim)
        self.W4 = self.rng.randn(hidden_dim, input_dim)  * s_ho
        self.b4 = np.zeros(input_dim)

        self.t      = 0
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
        self._h1     = self._leaky(self._h1_pre)
        return self._h1.dot(self.W2) + self.b2

    def decode(self, Z):
        self._h2_pre = Z.dot(self.W3) + self.b3
        self._h2     = self._leaky(self._h2_pre)
        return self._h2.dot(self.W4) + self.b4

    def forward(self, X):
        Z       = self.encode(X)
        self._Z = Z
        return self.decode(Z)

    def train_step(self, X, lr=0.001, noise_std=0.1, l2_reg=1e-4):
        import numpy as np
        batch    = X.shape[0]
        X_noisy  = X + noise_std * self.rng.randn(*X.shape)
        recon    = self.forward(X_noisy)
        diff     = recon - X
        loss     = np.mean(diff ** 2)

        d_out = 2.0 * diff / (batch * self.input_dim)
        dW4   = self._h2.T.dot(d_out)
        db4   = np.sum(d_out, axis=0)
        d_h2  = d_out.dot(self.W4.T) * self._leaky_g(self._h2_pre)
        dW3   = self._Z.T.dot(d_h2)
        db3   = np.sum(d_h2, axis=0)
        d_Z   = d_h2.dot(self.W3.T)
        dW2   = self._h1.T.dot(d_Z)
        db2   = np.sum(d_Z, axis=0)
        d_h1  = d_Z.dot(self.W2.T) * self._leaky_g(self._h1_pre)
        dW1   = X_noisy.T.dot(d_h1)
        db1   = np.sum(d_h1, axis=0)

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
        return np.mean((self.forward(X) - X) ** 2, axis=1)


def train_autoencoder(patches, latent_size, n_steps, seed):
    import numpy as np
    n_events, input_dim = patches.shape
    hidden_dim = max(latent_size * 2,
                     min(256, int(np.sqrt(input_dim * latent_size))))
    model = NumpyAutoencoder(input_dim, hidden_dim, latent_size, seed)

    mu    = np.mean(patches, axis=0)
    sigma = np.std(patches,  axis=0) + 1e-8
    X     = (patches - mu) / sigma

    losses = []
    for step in range(n_steps):
        cn   = 0.3 * (1.0 - 0.5 * step / n_steps)
        cl   = 0.003 * (1.0 - 0.3 * step / n_steps)
        loss = model.train_step(X, lr=cl, noise_std=cn, l2_reg=1e-4)
        losses.append(loss)

    model._norm_mu    = mu
    model._norm_sigma = sigma
    return model, losses


# ═══════════════════════════════════════════════════════════════════════════
# Stage 4 — Encode
# ═══════════════════════════════════════════════════════════════════════════

def encode_events(model, patches):
    import numpy as np
    X    = (patches - model._norm_mu) / model._norm_sigma
    Z    = model.encode(X)
    errs = model.reconstruction_errors(X)
    return Z, errs


# ═══════════════════════════════════════════════════════════════════════════
# Stage 5 — Diffusion Engine
# ═══════════════════════════════════════════════════════════════════════════

# ── 5a: K-means++ clustering (pure numpy) ──────────────────────────────────

def kmeans_plus_plus(Z, k, n_iter=60, seed=42):
    """
    K-means with k-means++ initialisation.
    Returns (centers [k × d], labels [n]).
    """
    import numpy as np
    rng = np.random.RandomState(seed)
    n   = len(Z)

    # k-means++ init
    first_idx = rng.randint(n)
    centers   = [Z[first_idx].copy()]
    for _ in range(k - 1):
        # Squared distance to nearest center so far
        d_sq = np.min(
            np.array([np.sum((Z - c) ** 2, axis=1) for c in centers]),
            axis=0)
        probs  = d_sq / (d_sq.sum() + 1e-12)
        idx    = rng.choice(n, p=probs)
        centers.append(Z[idx].copy())
    centers = np.array(centers)

    labels = np.zeros(n, dtype=int)
    for it in range(n_iter):
        # Assign
        dists_mat  = np.array([np.sum((Z - c) ** 2, axis=1) for c in centers])
        new_labels = np.argmin(dists_mat, axis=0)
        if np.all(new_labels == labels):
            break
        labels = new_labels
        # Update
        for ki in range(k):
            mask = labels == ki
            if np.sum(mask) > 0:
                centers[ki] = Z[mask].mean(axis=0)

    return centers, labels


def cluster_statistics(Z, centers, labels):
    """
    Per-cluster diagonal variance (+ floor) and weight (fraction of events).
    Returns variances [k × d], weights [k].
    """
    import numpy as np
    k          = len(centers)
    n          = len(Z)
    variances  = []
    weights    = []

    global_var = np.var(Z, axis=0) + 1e-8

    for ki in range(k):
        mask = labels == ki
        cnt  = int(np.sum(mask))
        if cnt > 1:
            var = np.var(Z[mask], axis=0) + 1e-8
        else:
            var = global_var.copy()
        variances.append(var)
        weights.append(cnt / max(1, n))

    return np.array(variances), np.array(weights)


# ── 5b: Seed events ──────────────────────────────────────────────────────

def find_seed_events(Z, centers, labels):
    """
    For each cluster: the event farthest from its cluster center.
    Diffusion will start here (maximum corruption) and converge inward.
    Returns list of (event_index, z_vector) per cluster.
    """
    import numpy as np
    k     = len(centers)
    seeds = []

    for ki in range(k):
        mask = np.where(labels == ki)[0]
        if len(mask) == 0:
            # Fall back to overall event closest to this center
            dists = np.sum((Z - centers[ki]) ** 2, axis=1)
            idx   = int(np.argmin(dists))
        else:
            dists_in = np.sum((Z[mask] - centers[ki]) ** 2, axis=1)
            idx      = int(mask[np.argmax(dists_in)])
        seeds.append((idx, Z[idx].copy()))

    return seeds


# ── 5c: Cross-entropy (neg log-likelihood under cluster Gaussians) ─────────

def cluster_cross_entropies(z, centers, variances):
    """
    Returns CE_k = 0.5 * Σ_d (z_d - μ_kd)² / σ_kd²  for each cluster k.
    (Constant terms omitted — monotone in distance to cluster center.)
    """
    import numpy as np
    return np.array([
        0.5 * np.sum((z - mu) ** 2 / (var + 1e-10))
        for mu, var in zip(centers, variances)
    ])


# ── 5d: Single diffusion step ────────────────────────────────────────────

def diffusion_step(z, centers, variances, temperature,
                   denoising_strength, rng, step_frac):
    """
    One step of temperature-annealed gradient descent in latent space.

    Gradient = Σ_k  w_k · (z − μ_k) / σ_k²
    where weights w_k = softmax(−CE_k / T)  [Boltzmann distribution].

    With 1/T scaling:
      · High T  → shallow step + large residual noise  (stochastic / exploratory)
      · Low  T  → steep  step + tiny  residual noise   (deterministic convergence)

    Returns (z_new, min_ce, cluster_weights).
    """
    import numpy as np

    ces = cluster_cross_entropies(z, centers, variances)

    # ── Boltzmann weights ──────────────────────────────────────────────
    log_w  = -ces / max(temperature, 1e-8)
    log_w -= log_w.max()                    # numerical stability
    w      = np.exp(log_w)
    w     /= w.sum() + 1e-12

    # ── Cross-entropy gradient w.r.t. z ───────────────────────────────
    grad = np.zeros_like(z)
    for mu, var, wi in zip(centers, variances, w):
        grad += wi * (z - mu) / (var + 1e-10)

    # ── 1/T step scaling: sharp at low T, shallow at high T ───────────
    inv_T     = 1.0 / max(temperature, 1e-8)
    step_size = denoising_strength * inv_T / (1.0 + inv_T)   # bounded in (0, 1)
    step_size *= (1.0 - 0.4 * step_frac)                     # gentle decay

    z_denoised = z - step_size * grad

    # ── Annealed residual noise  η ~ N(0, T) ──────────────────────────
    noise_scale = math.sqrt(max(temperature, 1e-8)) * (1.0 - step_frac)
    z_new       = z_denoised + rng.randn(*z.shape) * noise_scale * 0.4

    return z_new, float(np.min(ces)), w


# ── 5e: Full diffusion chains ─────────────────────────────────────────────

def run_diffusion_chains(Z, centers, variances, seeds,
                         diffusion_steps, temperature_start, temperature_end,
                         denoising_strength, entropy_threshold, seed):
    """
    Run one morph chain per cluster seed.

    Each chain records Z at every diffusion step:
      index 0 → heavily corrupted  (pure "noise")
      index N → refined / converged (closest to cluster identity)

    Fix 3 — Latent Jitter floor:
      temperature_end is clamped to ≥ 0.05 so the residual noise term
      √T · ε in diffusion_step never fully vanishes.  Without this floor,
      a very low temperature_end (e.g. 0.001) collapses all stochasticity
      and the vector parks permanently on one event for the entire tail of
      the chain.

    The event_seq for each chain is built here — inside the chain loop —
    so that the temperature active at each diffusion step is available to
    chain_to_event_sequence.  This lets the stochastic top-K selection
    entropy track the diffusion entropy step-by-step.

    Returns list of dicts:
      {
        'chain'          : list of Z vectors (length diffusion_steps + 1),
        'event_seq'      : list of event indices (same length as chain),
        'seed_event_idx' : original event index used as seed,
        'cluster_idx'    : cluster this chain belongs to,
        'stopped_early'  : bool,
        'steps_taken'    : int,
        'final_ce'       : float,
        'temp_path'      : list of temperatures (one per diffusion step),
      }
    """
    import numpy as np

    # ── Fix 3: Latent Jitter floor ────────────────────────────────────
    # Ensure residual noise never fully disappears.
    temperature_end = max(temperature_end, 0.05)

    rng      = np.random.RandomState(seed + 31415)
    all_info = []

    # Calibrate initial noise to temperature_start × latent spread
    z_std     = np.std(Z, axis=0).mean() + 1e-8
    noise_amp = temperature_start * z_std

    for chain_idx, (ev_idx, z_seed) in enumerate(seeds):
        chain     = []
        temp_path = []
        ce_path   = []

        # ── Initialise with full corruption ───────────────────────────
        z_t = z_seed + noise_amp * rng.randn(*z_seed.shape)
        chain.append(z_t.copy())       # step 0: maximum noise
        # Temperature for step 0 is temperature_start (before any annealing)
        temp_path.append(float(temperature_start))
        # Initial CE before any denoising
        init_ces = cluster_cross_entropies(z_t, centers, variances)
        ce_path.append(float(np.min(init_ces)))

        stopped_early = False
        steps_taken   = 0
        final_ce      = float("inf")

        for t in range(diffusion_steps):
            step_frac = t / max(1, diffusion_steps - 1)

            # Exponential annealing — never below floored temperature_end
            T_t = temperature_start * (
                (temperature_end / max(temperature_start, 1e-8)) ** step_frac
            )

            z_t, min_ce, _ = diffusion_step(
                z_t, centers, variances,
                T_t, denoising_strength, rng, step_frac
            )
            chain.append(z_t.copy())
            temp_path.append(float(T_t))
            ce_path.append(float(min_ce))
            steps_taken += 1
            final_ce     = min_ce

            # Early stopping — do NOT pad with identical Z copies.
            if min_ce < entropy_threshold:
                stopped_early = True
                break

        # ── Build event sequence with anti-loop mechanisms ────────────
        event_seq = chain_to_event_sequence(
            chain, temp_path, Z, rng,
            tabu_size=4, tabu_penalty=5.0, top_k=3
        )

        all_info.append({
            "chain"          : chain,
            "event_seq"      : event_seq,
            "seed_event_idx" : ev_idx,
            "cluster_idx"    : chain_idx,
            "stopped_early"  : stopped_early,
            "steps_taken"    : steps_taken,
            "final_ce"       : final_ce,
            "temp_path"      : temp_path,
            "ce_path"        : ce_path,
        })

    return all_info


# ═══════════════════════════════════════════════════════════════════════════
# Stage 6 — Morph-Chain Reconstruction
# ═══════════════════════════════════════════════════════════════════════════

def chain_to_event_sequence(chain_z, temp_path, Z, rng,
                            tabu_size=4, tabu_penalty=3.0, top_k=3):
    """
    Map each diffusion-step Z to a real event index.

    Four anti-loop mechanisms applied at every step:

    1. Tabu penalty — if an event was used within the last `tabu_size`
       steps its squared distance is multiplied by `tabu_penalty`, making
       it a less likely choice unless dramatically closer than everything else.

    2. Stochastic top-K selection — instead of always taking the single
       nearest neighbour, we collect the `top_k` closest events and draw
       from them with Boltzmann probability  p_i ∝ exp(−d_i / T_sel).
       At high T the draw is nearly uniform across the top-K candidates;
       at low T it collapses back toward the nearest.

    3. Temperature inheritance — each step uses the temperature that was
       active during the diffusion step that produced that Z, so the
       selection entropy tracks the diffusion entropy naturally.

    4. Sparse-pool adaptation — when the event pool is small (< 12 events),
       parameters are automatically scaled up: top_k grows to cover ~50% of
       the pool, tabu_size covers ~40%, and a selection temperature floor
       T_sel_min is raised so Boltzmann weights stay diffuse even after
       diffusion has fully converged.  This prevents "parking" on a single
       event for the tail of the chain when there are few events.

    Returns list[int] of length len(chain_z).
    """
    import numpy as np

    n_events = len(Z)

    # ── Sparse-pool adaptation ─────────────────────────────────────────
    # Scale aggressiveness inversely with pool size.
    # With 9 events: top_k → 5, tabu_size → 4, T_sel_min → 0.30
    # With 30+ events: parameters stay near caller defaults.
    sparsity     = max(0.0, 1.0 - n_events / 20.0)   # 1.0 at n=0, 0.0 at n=20
    adaptive_k   = max(top_k,   int(round(n_events * (0.25 + 0.25 * sparsity))))
    adaptive_tab = max(tabu_size, int(round(n_events * (0.25 + 0.15 * sparsity))))
    # Selection temperature floor: at least 0.08 normally, up to 0.35 for tiny pools
    T_sel_min    = 0.08 + 0.27 * sparsity

    k       = min(adaptive_k, n_events)
    tab_sz  = min(adaptive_tab, n_events - 1)

    seq    = []
    recent = []   # tabu FIFO queue

    for step_idx, z in enumerate(chain_z):
        # Temperature for this step (floored)
        T_diff = float(temp_path[step_idx]) if step_idx < len(temp_path) else 0.05
        # Selection temperature is the diffusion temperature, but floored higher
        # for sparse pools so Boltzmann weights don't collapse to argmin.
        T_sel  = max(T_diff, T_sel_min)

        # Squared distances to every event
        dists = np.sum((Z - z) ** 2, axis=1).copy()

        # ── Tabu penalty ──────────────────────────────────────────────
        for recent_idx in recent:
            dists[recent_idx] *= tabu_penalty

        # ── Top-K candidates ──────────────────────────────────────────
        if k < n_events:
            top_k_idx = np.argpartition(dists, k)[:k]
        else:
            top_k_idx = np.arange(n_events)

        top_k_dists = dists[top_k_idx]

        # ── Boltzmann weights: closer → higher probability ────────────
        log_w  = -top_k_dists / (T_sel + 1e-8)
        log_w -= log_w.max()          # numerical stability
        w      = np.exp(log_w)
        w     /= w.sum() + 1e-12

        # ── Weighted sample ───────────────────────────────────────────
        local_choice = rng.choice(len(top_k_idx), p=w)
        chosen       = int(top_k_idx[local_choice])

        seq.append(chosen)

        # ── Update tabu queue ─────────────────────────────────────────
        recent.append(chosen)
        if len(recent) > tab_sz:
            recent.pop(0)

    return seq


def extract_event_clips(audio, events, sr):
    import numpy as np
    clips     = []
    n_samples = len(audio) if audio.ndim == 1 else audio.shape[0]
    for ev in events:
        s = max(0, int(float(ev["start_time"]) * sr))
        e = min(n_samples, int(float(ev["end_time"]) * sr))
        if audio.ndim == 1:
            clips.append(audio[s:e].copy())
        else:
            clips.append(audio[s:e, :].copy())
    return clips


def reconstruct_morph_chains(clips, chains_info, Z, sr, target_samples):
    """
    Build output audio from all morph chains.

    Layout:
      [Chain 0: noisy→refined] | silence | [Chain 1: noisy→refined] | …

    The event sequence for each chain is already computed and stored in
    info["event_seq"] by run_diffusion_chains, with all three anti-loop
    mechanisms (tabu penalty, stochastic top-K, jitter floor) applied.

    Within each chain, successive clips share an equal-power crossfade.
    The very first clip of each chain intentionally skips the fade-in
    to preserve the "noisy click" onset character.
    """
    import numpy as np

    xfade       = max(4, int(XFADE_SEC * sr))
    silence_gap = max(4, int(SILENCE_GAP_SEC * sr))
    multichannel = clips[0].ndim > 1
    n_ch         = clips[0].shape[1] if multichannel else 1

    # Pre-compute fade curves
    angle    = np.linspace(0, np.pi / 2, xfade, dtype=np.float32)
    fade_in  = np.sin(angle)
    fade_out = np.cos(angle)

    # Estimate output length
    total_clips   = sum(len(ci["chain"]) for ci in chains_info)
    mean_clip_len = int(np.mean([len(c) for c in clips]))
    est_len       = (total_clips * mean_clip_len
                     + len(chains_info) * silence_gap + xfade * 4)

    if multichannel:
        output = np.zeros((est_len, n_ch), dtype=np.float32)
    else:
        output = np.zeros(est_len, dtype=np.float32)

    wp = 0   # write pointer

    for chain_idx, info in enumerate(chains_info):
        seq = info["event_seq"]   # pre-built with anti-loop mechanisms

        for step_idx, ev_idx in enumerate(seq):
            clip = clips[ev_idx].copy().astype(np.float32)
            cl   = len(clip)

            if cl < xfade * 3:
                # Short clip: straight add
                end = wp + cl
                if end > len(output):
                    pad = end - len(output) + xfade * 4
                    output = (np.pad(output, ((0, pad), (0, 0)))
                              if multichannel else np.pad(output, (0, pad)))
                output[wp:end] += clip
                wp = end
                continue

            is_chain_first = (step_idx == 0)
            is_chain_last  = (step_idx == len(seq) - 1)

            # Fade-in (skip on very first step of chain to keep noisy transient)
            if not is_chain_first:
                if multichannel:
                    for ch in range(n_ch): clip[:xfade, ch] *= fade_in
                else:
                    clip[:xfade] *= fade_in

            # Fade-out
            if not is_chain_last:
                if multichannel:
                    for ch in range(n_ch): clip[-xfade:, ch] *= fade_out
                else:
                    clip[-xfade:] *= fade_out

            end = wp + cl
            if end > len(output):
                pad = end - len(output) + xfade * 4
                output = (np.pad(output, ((0, pad), (0, 0)))
                          if multichannel else np.pad(output, (0, pad)))
            output[wp:end] += clip

            # Overlap for next clip (but not at end of chain)
            if not is_chain_last:
                wp = end - xfade
            else:
                wp = end

        # Silence gap between chains
        if chain_idx < len(chains_info) - 1:
            wp += silence_gap

    output = output[:wp]

    # Post-splice click smoothing (vectorized)
    if len(output) > 4:
        local_rms = max(0.001,
                        np.sqrt(np.mean(output.flatten() ** 2)))
        threshold = local_rms * 4.5
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
            output = (np.pad(output, ((0, pad), (0, 0)))
                      if multichannel else np.pad(output, (0, pad)))

    # Peak normalisation
    peak = np.max(np.abs(output))
    if peak > 0.95:
        output *= 0.95 / peak

    return output


# ═══════════════════════════════════════════════════════════════════════════
# Stage 7 — Stats
# ═══════════════════════════════════════════════════════════════════════════

def write_stats(path, events, chains_info, Z, centers, labels,
                losses, sr, out_duration, n_clusters,
                diffusion_steps, entropy_threshold,
                temperature_start, temperature_end,
                denoising_strength, warnings):
    import numpy as np

    n_events = len(events)
    n_chains = len(chains_info)

    with open(path, "w") as f:
        f.write("n_events=%d\n"          % n_events)
        f.write("n_clusters=%d\n"        % n_clusters)
        f.write("n_chains=%d\n"          % n_chains)
        f.write("diffusion_steps=%d\n"   % diffusion_steps)
        f.write("entropy_threshold=%.4f\n" % entropy_threshold)
        f.write("temperature_start=%.4f\n" % temperature_start)
        f.write("temperature_end=%.4f\n"   % temperature_end)
        f.write("denoising_strength=%.4f\n" % denoising_strength)
        f.write("output_duration=%.3f\n" % out_duration)
        f.write("final_loss=%.6f\n"      % (losses[-1] if losses else 0))
        f.write("initial_loss=%.6f\n"    % (losses[0]  if losses else 0))

        # Per-cluster stats
        for ki in range(n_clusters):
            mask = labels == ki
            cnt  = int(np.sum(mask))
            d_to_center = np.sqrt(
                np.sum((Z[mask] - centers[ki]) ** 2, axis=1)
            ) if cnt > 0 else np.array([0])
            f.write("cluster_%d_events=%d\n"     % (ki, cnt))
            f.write("cluster_%d_pct=%.1f\n"      % (ki, 100.0 * cnt / max(1, n_events)))
            f.write("cluster_%d_radius=%.4f\n"   % (ki, float(np.mean(d_to_center))))

        # Per-chain stats + convergence CE paths
        early_stops = 0
        for info in chains_info:
            ci = info["cluster_idx"]
            f.write("chain_%d_seed_event=%d\n"   % (ci, info["seed_event_idx"]))
            f.write("chain_%d_steps_taken=%d\n"  % (ci, info["steps_taken"]))
            f.write("chain_%d_final_ce=%.4f\n"   % (ci, info["final_ce"]))
            f.write("chain_%d_stopped_early=%d\n" % (ci, int(info["stopped_early"])))
            seq = info.get("event_seq", [])
            n_distinct = len(set(seq))
            n_total    = len(seq)
            f.write("chain_%d_distinct_events=%d\n" % (ci, n_distinct))
            f.write("chain_%d_seq_length=%d\n"      % (ci, n_total))
            f.write("chain_%d_diversity_pct=%.1f\n" % (
                ci, 100.0 * n_distinct / max(1, n_total)))
            if info["stopped_early"]:
                early_stops += 1

            # Per-step CE convergence path (for Praat visualization)
            ce_path = info.get("ce_path", [])
            n_ce = min(len(ce_path), 101)  # cap at diffusion_steps+1
            f.write("chain_%d_n_ce=%d\n" % (ci, n_ce))
            # Encode as comma-separated floats in a single line
            if n_ce > 0:
                ce_str = ",".join("%.3f" % v for v in ce_path[:n_ce])
                f.write("chain_%d_ce_vals=%s\n" % (ci, ce_str))

        f.write("early_stops=%d\n"        % early_stops)

        # Latent geometry
        z_spread = float(np.mean(np.std(Z, axis=0)))
        f.write("latent_spread=%.4f\n"    % z_spread)

        durations = [float(e["end_time"]) - float(e["start_time"])
                     for e in events]
        f.write("mean_event_dur=%.3f\n"   % np.mean(durations))
        f.write("min_event_dur=%.3f\n"    % np.min(durations))
        f.write("max_event_dur=%.3f\n"    % np.max(durations))

        if warnings:
            f.write("warning=%s\n" % "; ".join(warnings))


# ═══════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════

def main():
    if len(sys.argv) != 14:
        print(
            "Usage: python latent_diffusion.py "
            "input.wav events.csv output.wav stats.txt "
            "latent_size learning_steps n_clusters diffusion_steps "
            "entropy_threshold temperature_start temperature_end "
            "denoising_strength seed",
            file=sys.stderr)
        sys.exit(1)

    check_dependencies()

    import numpy as np
    import soundfile as sf

    in_wav            = sys.argv[1]
    events_csv        = sys.argv[2]
    out_wav           = sys.argv[3]
    stats_file        = sys.argv[4]
    latent_size       = int(sys.argv[5])
    learning_steps    = int(sys.argv[6])
    n_clusters        = int(sys.argv[7])
    diffusion_steps   = int(sys.argv[8])
    entropy_threshold = float(sys.argv[9])
    temperature_start = float(sys.argv[10])
    temperature_end   = float(sys.argv[11])
    denoising_strength = float(sys.argv[12])
    seed              = int(sys.argv[13])

    # ── Clamp parameters ──────────────────────────────────────────────
    latent_size       = max(2,   min(32,  latent_size))
    learning_steps    = max(10,  min(500, learning_steps))
    n_clusters        = max(2,   min(8,   n_clusters))
    diffusion_steps   = max(5,   min(100, diffusion_steps))
    entropy_threshold = max(0.0, entropy_threshold)
    temperature_start = max(0.05, min(10.0, temperature_start))
    temperature_end   = max(0.01, min(temperature_start, temperature_end))
    denoising_strength = max(0.0, min(1.0, denoising_strength))

    np.random.seed(seed)
    warnings = []

    # ── Stage 1: Load ────────────────────────────────────────────────
    print("  [Py 1/7] Loading audio + event table...")
    audio, sr = sf.read(in_wav, always_2d=False)
    audio     = np.asarray(audio, dtype=np.float32)
    events    = load_event_table(events_csv)
    n_samples = len(audio) if audio.ndim == 1 else audio.shape[0]
    orig_dur  = n_samples / sr

    print("    Audio: %.2fs  SR=%d  Shape=%s" % (orig_dur, sr, audio.shape))
    print("    Events: %d" % len(events))

    if len(events) == 0:
        print("ERROR: Event table contains no usable events", file=sys.stderr)
        sys.exit(1)

    if len(events) < n_clusters + 1:
        warnings.append("Too few events (%d) for %d clusters" %
                        (len(events), n_clusters))
        # Preserve the original >=2-cluster behaviour whenever possible, but
        # a one-event source cannot support two clusters.  Allow one cluster
        # only for that degenerate edge case; normal inputs are unchanged.
        n_clusters = 1 if len(events) == 1 else max(2, len(events) - 1)
        print("    WARNING: reducing clusters to %d" % n_clusters)

    # ── Stage 2: Mel patches ─────────────────────────────────────────
    print("  [Py 2/7] Extracting log-mel patches...")
    audio_mono = audio if audio.ndim == 1 else audio[:, 0]
    patches    = extract_mel_patches(audio_mono.astype(np.float64),
                                     sr, events)
    print("    Patch shape: %s" % str(patches.shape))

    # ── Stage 3: Train autoencoder ───────────────────────────────────
    print("  [Py 3/7] Training autoencoder (%d steps, latent=%d)..." %
          (learning_steps, latent_size))
    model, losses = train_autoencoder(patches, latent_size,
                                      learning_steps, seed)
    loss_ratio = losses[-1] / (losses[0] + 1e-12) if losses else 1.0
    print("    Loss: %.6f → %.6f (%.1f%% reduction)" % (
        losses[0], losses[-1], (1 - loss_ratio) * 100))

    if loss_ratio > 0.95:
        warnings.append("Autoencoder did not converge well")

    # ── Stage 4: Encode ──────────────────────────────────────────────
    print("  [Py 4/7] Encoding events → latent space...")
    Z, recon_err = encode_events(model, patches)
    print("    Latent shape: %s  |  Mean recon err: %.4f" % (
        str(Z.shape), float(np.mean(recon_err))))

    # ── Stage 5a: Cluster discovery ──────────────────────────────────
    print("  [Py 5/7] Discovering %d identity clusters (k-means++)..." %
          n_clusters)
    centers, labels = kmeans_plus_plus(Z, n_clusters, seed=seed)
    variances, weights = cluster_statistics(Z, centers, labels)

    for ki in range(n_clusters):
        cnt = int(np.sum(labels == ki))
        print("    Cluster %d: %d events (%.0f%%)" % (
            ki, cnt, 100.0 * cnt / max(1, len(events))))

    # ── Stage 5b–e: Run diffusion chains ─────────────────────────────
    print("  [Py 6/7] Running diffusion chains "
          "(%d steps, T: %.2f→%.2f, strength=%.2f)..." %
          (diffusion_steps, temperature_start, temperature_end,
           denoising_strength))

    seeds = find_seed_events(Z, centers, labels)
    for ki, (ev_idx, _) in enumerate(seeds):
        print("    Cluster %d seed: event %d" % (ki, ev_idx))

    chains_info = run_diffusion_chains(
        Z, centers, variances, seeds,
        diffusion_steps, temperature_start, temperature_end,
        denoising_strength, entropy_threshold, seed
    )

    for info in chains_info:
        status = "early-stop" if info["stopped_early"] else "full"
        print("    Chain %d: %d steps | final CE=%.3f | %s" % (
            info["cluster_idx"], info["steps_taken"],
            info["final_ce"], status))

    # ── Stage 6: Reconstruct morph chain ─────────────────────────────
    print("  [Py 7/7] Reconstructing morph-chain audio...")
    clips  = extract_event_clips(audio, events, sr)
    output = reconstruct_morph_chains(clips, chains_info, Z,
                                      sr, target_samples=0)

    sf.write(out_wav, output, sr)
    out_dur = (len(output) / sr
               if output.ndim == 1 else output.shape[0] / sr)

    # ── Stage 7: Stats ────────────────────────────────────────────────
    write_stats(stats_file, events, chains_info, Z, centers, labels,
                losses, sr, out_dur, n_clusters, diffusion_steps,
                entropy_threshold, temperature_start, temperature_end,
                denoising_strength, warnings)

    print("    Output: %.2fs | Peak: %.4f" % (
        out_dur, float(np.max(np.abs(output)))))
    print("    Morph chains: %d  (noisy → refined per cluster)" %
          len(chains_info))
    print("OK: wrote %s" % out_wav)


if __name__ == "__main__":
    main()
