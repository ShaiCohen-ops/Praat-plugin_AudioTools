"""
latent_barycentric.py — Latent Barycentric Mutation Engine

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University

Usage (called by Praat, not directly):
    python latent_barycentric.py input.wav events.csv nav_plan.csv
        output.wav stats.txt [options]

    # Load plan from CSV (original / backward-compatible):
        --plan_source external_csv

    # Generate plan internally:
        --plan_source auto_generate
        --plan_steps 60
        --plan_mode_preset cycle
        --plan_step_size 0.35
        --plan_temperature 0.40
        --plan_k 4
        --plan_return_strength 0.65
        --plan_return_anchor_strategy periodic
        --plan_anchor_period 15
        --plan_dur_scale 1.0
        --plan_dur_jitter 0.05
        --plan_eng_scale 1.0
        --plan_eng_jitter 0.05
        --plan_cleanup_policy python_cleanup

Architecture:
    Stage 1 — Load audio, event table; load or generate navigation plan
    Stage 2 — Extract fixed-size log-mel patches per event
    Stage 3 — Train lightweight VAE on-the-fly (numpy only)
    Stage 4 — Encode events → latent means μᵢ
    Stage 5 — Execute navigation plan:
              For each step:
                * determine latent target position (drift/mutate/return/settle)
                * find K nearest neighbors in latent space
                * compute barycentric weights from inverse distances
                * mix K event waveforms with those weights
                * crossfade / smooth
    Stage 6 — Normalize and write output.wav
    Stage 7 — Write stats.txt
    Stage 8 — Optional cleanup of Praat-created temp files

Navigation plan modes:
    drift   — small coherent steps from current latent position
    mutate  — larger steps with temperature noise injection
    return  — pull position toward an earlier anchor step
    settle  — shrinking steps, low noise, converge

No external model downloads. No internet. No PyTorch/TensorFlow/sklearn.
"""

import sys
import os
import csv
import math

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
N_MELS     = 40
MEL_FRAMES = 32
XFADE_SEC  = 0.012     # crossfade between mixed segments (seconds)

# Prefix used by Praat for all temp files it creates.
# Python only deletes files that start with this prefix.
PRAAT_TEMP_PREFIX = "temp_latbary_"


# ═══════════════════════════════════════════════════════════════════════════
# Utilities
# ═══════════════════════════════════════════════════════════════════════════

def check_dependencies():
    missing = []
    for pkg in ["numpy", "soundfile", "scipy"]:
        try:
            __import__(pkg)
        except ImportError:
            missing.append(pkg)
    if missing:
        print("ERROR: Missing packages: " + ", ".join(missing), file=sys.stderr)
        print("Install with:  pip install " + " ".join(missing), file=sys.stderr)
        sys.exit(1)


def _is_praat_temp(path):
    """Return True only for files that were created by Praat for this run."""
    return os.path.basename(path).startswith(PRAAT_TEMP_PREFIX)


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


def load_nav_plan(csv_path):
    """Load navigation plan CSV produced by the AI planner (original schema)."""
    plan = []
    with open(csv_path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            plan.append({
                'step_index':             int(row['step_index']),
                'relative_time':          float(row['relative_time']),
                'mode':                   row['mode'].strip(),
                'step_size':              float(row['step_size']),
                'temperature':            float(row['temperature']),
                'k_neighbors':            int(row['k_neighbors']),
                'return_anchor':          int(row['return_anchor']),
                'return_strength':        float(row['return_strength']),
                'segment_duration_scale': float(row['segment_duration_scale']),
                'segment_energy_scale':   float(row['segment_energy_scale']),
                'cleanup_policy':         row['cleanup_policy'].strip(),
            })
    return plan


# ═══════════════════════════════════════════════════════════════════════════
# Plan Generator
# ═══════════════════════════════════════════════════════════════════════════

def generate_nav_plan(
    n_steps,
    mode_preset,
    step_size,
    temperature,
    k_neighbors,
    return_strength,
    return_anchor_strategy,
    anchor_period,
    dur_scale,
    dur_jitter,
    eng_scale,
    eng_jitter,
    cleanup_policy,
    seed=42,
):
    """
    Generate a navigation plan in memory, returning a list of step-dicts
    with exactly the same schema as load_nav_plan().

    mode_preset values:
        "drift"  — all steps are mode=drift
        "mutate" — all steps are mode=mutate
        "return" — all steps are mode=return
        "cycle"  — first 1/3 drift, second 1/3 mutate, final 1/3 return

    return_anchor_strategy values:
        "center"   — return_anchor=-1 (Python interprets as latent center)
        "step0"    — return_anchor=0
        "last"     — return_anchor=i-1 (previous step)
        "periodic" — return_anchor = last multiple of anchor_period before i

    Jitter (if > 0) adds per-step uniform random perturbation around the
    base scale values, clamped to safe ranges.
    """
    import random
    rng = random.Random(seed)

    # Clamp inputs to safe ranges
    n_steps        = max(4, min(500, n_steps))
    step_size      = max(0.0, min(1.0, step_size))
    temperature    = max(0.0, min(1.0, temperature))
    k_neighbors    = max(2, min(8, k_neighbors))
    return_strength = max(0.0, min(1.0, return_strength))
    anchor_period  = max(1, anchor_period)
    dur_scale      = max(0.25, min(4.0, dur_scale))
    eng_scale      = max(0.10, min(3.0, eng_scale))
    dur_jitter     = max(0.0, dur_jitter)
    eng_jitter     = max(0.0, eng_jitter)

    valid_presets = {"drift", "mutate", "return", "cycle"}
    if mode_preset not in valid_presets:
        mode_preset = "drift"

    valid_anchor_strats = {"center", "step0", "last", "periodic"}
    if return_anchor_strategy not in valid_anchor_strats:
        return_anchor_strategy = "center"

    plan = []

    # Pre-scan to find settle phase boundaries (for progressive decay)
    settle_start_idx = None
    settle_end_idx   = None
    for i in range(n_steps):
        frac = i / max(1, n_steps - 1)
        is_settle = False
        if mode_preset == "cycle" and frac >= 0.917:
            is_settle = True
        if is_settle:
            if settle_start_idx is None:
                settle_start_idx = i
            settle_end_idx = i

    for i in range(n_steps):
        # ── Determine mode ──────────────────────────────────────────────────
        if mode_preset == "drift":
            mode = "drift"
        elif mode_preset == "mutate":
            mode = "mutate"
        elif mode_preset == "return":
            mode = "return"
        else:  # "cycle": drift 1/3 | mutate 1/3 | return 1/4 | settle 1/12
            frac = i / max(1, n_steps - 1)   # 0.0 … 1.0
            if frac < 0.333:
                mode = "drift"
            elif frac < 0.667:
                mode = "mutate"
            elif frac < 0.917:
                mode = "return"
            else:
                mode = "settle"

        # ── Per-step step_size and temperature ─────────────────────────────
        # Settle mode progressively decays both toward near-zero so the
        # trajectory actually converges rather than drifting at constant rate.
        if mode == "settle" and settle_start_idx is not None:
            settle_span = max(1, settle_end_idx - settle_start_idx)
            decay = 1.0 - (i - settle_start_idx) / settle_span  # 1.0 → 0.0
            decay = max(0.02, decay)  # floor so last step isn't exactly zero
            step_step_size   = step_size * decay
            step_temperature = temperature * decay * decay  # faster cooldown
        else:
            step_step_size   = step_size
            step_temperature = temperature

        # ── Determine return_anchor ─────────────────────────────────────────
        if mode == "return":
            if return_anchor_strategy == "center":
                anchor = -1          # execute_nav_plan treats -1 as center
            elif return_anchor_strategy == "step0":
                anchor = 0
            elif return_anchor_strategy == "last":
                anchor = max(0, i - 1)
            else:  # "periodic"
                # Last completed multiple of anchor_period before step i
                if i == 0:
                    anchor = -1
                else:
                    last_multiple = (i // anchor_period) * anchor_period
                    anchor = last_multiple if last_multiple < i else max(0, last_multiple - anchor_period)
            r_strength = return_strength
        else:
            anchor     = -1
            r_strength = 0.0

        # ── Apply jitter to duration/energy scales ──────────────────────────
        if dur_jitter > 0.0:
            jd = 1.0 + rng.uniform(-dur_jitter, dur_jitter)
            step_dur_scale = max(0.25, min(4.0, dur_scale * jd))
        else:
            step_dur_scale = dur_scale

        if eng_jitter > 0.0:
            je = 1.0 + rng.uniform(-eng_jitter, eng_jitter)
            step_eng_scale = max(0.10, min(3.0, eng_scale * je))
        else:
            step_eng_scale = eng_scale

        # ── Assign cleanup_policy (only last step carries it) ───────────────
        step_cleanup = cleanup_policy if i == n_steps - 1 else "none"

        plan.append({
            'step_index':             i,
            'relative_time':          round(i / max(1, n_steps - 1), 6),
            'mode':                   mode,
            'step_size':              round(step_step_size, 6),
            'temperature':            round(step_temperature, 6),
            'k_neighbors':            k_neighbors,
            'return_anchor':          anchor,
            'return_strength':        round(r_strength, 4),
            'segment_duration_scale': round(step_dur_scale, 4),
            'segment_energy_scale':   round(step_eng_scale, 4),
            'cleanup_policy':         step_cleanup,
        })

    # Fix first and last relative_time to be exactly 0.0 / 1.0
    if plan:
        plan[0]['relative_time']  = 0.0
        plan[-1]['relative_time'] = 1.0

    return plan


# ═══════════════════════════════════════════════════════════════════════════
# Stage 2 — Log-Mel Patch Extraction
# ═══════════════════════════════════════════════════════════════════════════

def build_mel_filterbank(sr, n_fft, n_mels):
    import numpy as np

    def hz_to_mel(hz):
        return 2595.0 * np.log10(1.0 + hz / 700.0)

    def mel_to_hz(mel):
        return 700.0 * (10.0 ** (mel / 2595.0) - 1.0)

    n_bins    = n_fft // 2 + 1
    low_mel   = hz_to_mel(20)
    high_mel  = hz_to_mel(sr / 2)
    mel_points = np.linspace(low_mel, high_mel, n_mels + 2)
    hz_points  = mel_to_hz(mel_points)
    bin_points = np.floor((n_fft + 1) * hz_points / sr).astype(int)
    bin_points = np.clip(bin_points, 0, n_bins - 1)

    filterbank = np.zeros((n_mels, n_bins))
    for m in range(1, n_mels + 1):
        f_left   = bin_points[m - 1]
        f_center = bin_points[m]
        f_right  = bin_points[m + 1]
        for k in range(f_left, f_center):
            if f_center > f_left:
                filterbank[m - 1, k] = (k - f_left) / (f_center - f_left)
        for k in range(f_center, f_right):
            if f_right > f_center:
                filterbank[m - 1, k] = (f_right - k) / (f_right - f_center)
    return filterbank


def extract_mel_patches(audio_mono, sr, events):
    import numpy as np

    n_fft  = 1024
    hop    = 256
    window = np.hanning(n_fft)
    mel_fb = build_mel_filterbank(sr, n_fft, N_MELS)
    patches   = []
    n_samples = len(audio_mono)

    for ev in events:
        s = int(float(ev["start_time"]) * sr)
        e = int(float(ev["end_time"])   * sr)
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
            spec       = np.abs(np.fft.rfft(frame)) ** 2
            mel_energy = mel_fb.dot(spec)
            mel_spec[:, fi] = np.log(mel_energy + 1e-10)

        if n_frames >= MEL_FRAMES:
            offset = (n_frames - MEL_FRAMES) // 2
            patch  = mel_spec[:, offset:offset + MEL_FRAMES]
        else:
            patch  = np.zeros((N_MELS, MEL_FRAMES))
            offset = (MEL_FRAMES - n_frames) // 2
            patch[:, offset:offset + n_frames] = mel_spec
            for pi in range(offset):
                patch[:, pi] = mel_spec[:, 0]
            for pi in range(offset + n_frames, MEL_FRAMES):
                patch[:, pi] = mel_spec[:, -1]

        patches.append(patch.flatten())
    return np.array(patches, dtype=np.float64)


# ═══════════════════════════════════════════════════════════════════════════
# Stage 3 — Numpy VAE (lightweight)
# ═══════════════════════════════════════════════════════════════════════════

class NumpyVAE:
    """
    Simple VAE: input → encoder → (μ, log σ²) → reparameterize → decoder → output.
    We use only μ for latent navigation (no sampling at inference).
    """

    def __init__(self, input_dim, hidden_dim, latent_dim, seed=42):
        import numpy as np
        self.rng        = np.random.RandomState(seed)
        self.input_dim  = input_dim
        self.hidden_dim = hidden_dim
        self.latent_dim = latent_dim

        def he(a, b):
            return self.rng.randn(a, b) * np.sqrt(2.0 / (a + b))

        # Encoder
        self.We1 = he(input_dim,  hidden_dim)
        self.be1 = np.zeros(hidden_dim)
        self.Wmu = he(hidden_dim, latent_dim)
        self.bmu = np.zeros(latent_dim)
        self.Wlv = he(hidden_dim, latent_dim)
        self.blv = np.zeros(latent_dim)

        # Decoder
        self.Wd1 = he(latent_dim, hidden_dim)
        self.bd1 = np.zeros(hidden_dim)
        self.Wd2 = he(hidden_dim, input_dim)
        self.bd2 = np.zeros(input_dim)

        self.params = [self.We1, self.be1, self.Wmu, self.bmu,
                       self.Wlv, self.blv, self.Wd1, self.bd1,
                       self.Wd2, self.bd2]
        self.t = 0
        self.m = [np.zeros_like(p) for p in self.params]
        self.v = [np.zeros_like(p) for p in self.params]

    def _relu(self, x):
        import numpy as np
        return np.maximum(0, x)

    def _relu_g(self, x):
        import numpy as np
        return (x > 0).astype(np.float64)

    def encode(self, X):
        self._h1_pre = X.dot(self.We1) + self.be1
        self._h1     = self._relu(self._h1_pre)
        mu = self._h1.dot(self.Wmu) + self.bmu
        lv = self._h1.dot(self.Wlv) + self.blv
        return mu, lv

    def decode(self, Z):
        self._hd_pre = Z.dot(self.Wd1) + self.bd1
        self._hd     = self._relu(self._hd_pre)
        return self._hd.dot(self.Wd2) + self.bd2

    def forward(self, X):
        import numpy as np
        mu, lv = self.encode(X)
        std   = np.exp(0.5 * np.clip(lv, -4, 4))
        eps   = self.rng.randn(*std.shape)
        Z     = mu + std * eps
        recon = self.decode(Z)
        return recon, mu, lv, Z

    def train_step(self, X, lr=0.001, beta_kl=0.05, noise_std=0.15, l2=1e-4):
        import numpy as np
        batch   = X.shape[0]
        X_noisy = X + noise_std * self.rng.randn(*X.shape)
        recon, mu, lv, Z = self.forward(X_noisy)

        # Reconstruction loss
        diff       = recon - X
        recon_loss = np.mean(diff ** 2)

        # KL divergence: 0.5 * mean(μ² + σ² - log σ² - 1)
        kl_loss = 0.5 * np.mean(mu ** 2 + np.exp(lv) - lv - 1.0)

        loss = recon_loss + beta_kl * kl_loss

        # ---- Backward ----
        d_out = 2.0 * diff / (batch * self.input_dim)
        dWd2  = self._hd.T.dot(d_out)
        dbd2  = np.sum(d_out, axis=0)
        d_hd  = d_out.dot(self.Wd2.T) * self._relu_g(self._hd_pre)
        dWd1  = Z.T.dot(d_hd)
        dbd1  = np.sum(d_hd, axis=0)
        d_Z   = d_hd.dot(self.Wd1.T)

        # Reparameterization gradients
        std        = np.exp(0.5 * np.clip(lv, -4, 4))
        dmu_recon  = d_Z.copy()
        dlv_recon  = d_Z * std * 0.5
        dmu_kl     = beta_kl * mu / batch
        dlv_kl     = beta_kl * 0.5 * (np.exp(lv) - 1.0) / batch
        dmu = dmu_recon + dmu_kl
        dlv = dlv_recon + dlv_kl

        dWmu = self._h1.T.dot(dmu)
        dbmu = np.sum(dmu, axis=0)
        dWlv = self._h1.T.dot(dlv)
        dblv = np.sum(dlv, axis=0)
        d_h1 = (dmu.dot(self.Wmu.T) + dlv.dot(self.Wlv.T)) * self._relu_g(self._h1_pre)
        dWe1 = X_noisy.T.dot(d_h1)
        dbe1 = np.sum(d_h1, axis=0)

        grads = [dWe1 + l2 * self.We1, dbe1,
                 dWmu + l2 * self.Wmu,  dbmu,
                 dWlv + l2 * self.Wlv,  dblv,
                 dWd1 + l2 * self.Wd1,  dbd1,
                 dWd2 + l2 * self.Wd2,  dbd2]

        self.t += 1
        b1, b2, eps_adam = 0.9, 0.999, 1e-8
        for i, (p, g) in enumerate(zip(self.params, grads)):
            self.m[i] = b1 * self.m[i] + (1 - b1) * g
            self.v[i] = b2 * self.v[i] + (1 - b2) * (g ** 2)
            mh = self.m[i] / (1 - b1 ** self.t)
            vh = self.v[i] / (1 - b2 ** self.t)
            p -= lr * mh / (np.sqrt(vh) + eps_adam)

        return loss


def train_vae(patches, latent_size, n_steps, seed):
    import numpy as np
    n_events, input_dim = patches.shape
    hidden_dim = max(latent_size * 2, min(256, int(np.sqrt(input_dim * latent_size))))
    model = NumpyVAE(input_dim, hidden_dim, latent_size, seed)

    mu_norm  = np.mean(patches, axis=0)
    sig_norm = np.std(patches, axis=0) + 1e-8
    X = (patches - mu_norm) / sig_norm

    losses = []
    lr = 0.003
    for step in range(n_steps):
        cl   = lr * (1.0 - 0.4 * step / n_steps)
        loss = model.train_step(X, lr=cl, beta_kl=0.05, noise_std=0.3, l2=1e-4)
        losses.append(loss)

    model._norm_mu  = mu_norm
    model._norm_sig = sig_norm
    return model, losses


def encode_events(model, patches):
    import numpy as np
    X = (patches - model._norm_mu) / model._norm_sig
    mu, lv = model.encode(X)
    return mu   # shape (n_events, latent_dim)


# ═══════════════════════════════════════════════════════════════════════════
# Stage 5 — Latent Navigation + Barycentric Mixing
# ═══════════════════════════════════════════════════════════════════════════

def barycentric_weights(query_pos, neighbor_positions):
    """
    Inverse-distance barycentric weights for K neighbors.
    query_pos:          (latent_dim,)
    neighbor_positions: (K, latent_dim)
    Returns:            (K,) weights summing to 1.
    """
    import numpy as np
    dists = np.sqrt(np.sum((neighbor_positions - query_pos) ** 2, axis=1))
    dists = np.maximum(dists, 1e-8)
    inv   = 1.0 / dists
    return inv / np.sum(inv)


# ═══════════════════════════════════════════════════════════════════════════
# Pitch preservation helpers
# ═══════════════════════════════════════════════════════════════════════════

def _pad_or_trim(clip, target_len):
    """
    Bring a 1-D float32 clip to exactly target_len samples by
    zero-padding at the tail or hard-trimming — no resampling, no
    pitch shift.  A short raised-cosine fade-out is applied before
    the trim/pad point to avoid clicks.
    """
    import numpy as np
    clip = np.asarray(clip, dtype=np.float32)
    n = len(clip)
    if n == target_len:
        return clip.copy()

    fade_len = min(64, n // 4, target_len // 4)

    if n > target_len:
        # Fade out near the trim point
        out = clip[:target_len].copy()
        if fade_len > 0:
            fade = 0.5 * (1.0 + np.cos(np.linspace(0, np.pi, fade_len)))
            out[target_len - fade_len:target_len] *= fade.astype(np.float32)
        return out
    else:
        # Fade out near the end of the clip, then zero-pad
        out = np.zeros(target_len, dtype=np.float32)
        if fade_len > 0:
            fade = 0.5 * (1.0 + np.cos(np.linspace(0, np.pi, fade_len)))
            clip = clip.copy()
            clip[n - fade_len:n] *= fade.astype(np.float32)
        out[:n] = clip
        return out


def _phase_vocoder_stretch(clip, target_len):
    """
    Time-stretch `clip` to `target_len` samples using a phase vocoder.
    Preserves spectral envelope (formants) and pitch.

    Design choices that prevent clicks:
    - n_fft=2048, hop=n_fft//4=512  →  75% overlap.
      A Hann window OLA-summed at 75% overlap produces a flat envelope
      (sum ≈ n_fft/2 per sample), so the OLA normalisation never goes
      near zero except at the very edges of the buffer.
    - n_frames_out is computed to fully cover target_len, not just reach
      (target_len - n_fft) // hop_out.
    - OLA normalisation floor = max(win_sq) * 0.1, not 1e-8, so edge
      artefacts from undersampled boundary frames are suppressed without
      numerical spikes.
    - No final fade-in/fade-out: fades were masking the real click sources
      (bad floor, undercounting frames) rather than fixing them.

    Falls back to _pad_or_trim if clip is shorter than n_fft.

    Returns float32 array of length target_len.
    """
    import numpy as np

    n_fft   = 2048
    hop_out = n_fft // 4          # 512 — 75% overlap for Hann window

    clip = np.asarray(clip, dtype=np.float32)
    n    = len(clip)

    if n < n_fft or target_len < 4:
        return _pad_or_trim(clip, target_len)
    if n == target_len:
        return clip.copy()

    ratio   = target_len / n       # >1 = slower / stretched, <1 = faster
    hop_in  = hop_out / ratio      # fractional analysis hop

    # ── Hann window and its squared sum (used for OLA normalisation) ───────
    win     = np.hanning(n_fft).astype(np.float64)
    win_sq  = win ** 2
    # At 75% overlap the Hann OLA sum is constant ≈ sum(win_sq)/hop_out
    # per sample.  Use that value as the normalisation floor.
    ola_floor = float(np.sum(win_sq) / hop_out) * 0.1

    # ── Forward STFT of the input ──────────────────────────────────────────
    hop_an       = hop_out                        # analysis hop (integer)
    n_frames_in  = max(2, (n - n_fft) // hop_an + 2)   # +2 for tail padding

    n_bins = n_fft // 2 + 1
    stft   = np.zeros((n_bins, n_frames_in), dtype=np.complex128)
    for fi in range(n_frames_in):
        start = fi * hop_an
        end   = start + n_fft
        if end <= n:
            frame = clip[start:end].astype(np.float64)
        else:
            frame = np.zeros(n_fft, dtype=np.float64)
            avail = max(0, n - start)
            if avail > 0:
                frame[:avail] = clip[start:start + avail]
        stft[:, fi] = np.fft.rfft(frame * win)

    mag_in   = np.abs(stft)
    phase_in = np.angle(stft)

    # Expected phase advance per analysis hop (bin-centre frequencies)
    omega = 2.0 * np.pi * np.arange(n_bins) / n_fft  # radians/sample

    # Precompute instantaneous frequency for each analysis frame transition
    # inst_freq[:, fi] = frequency to use when going from frame fi to fi+1
    inst_freq = np.zeros((n_bins, n_frames_in), dtype=np.float64)
    for fi in range(n_frames_in - 1):
        dp = phase_in[:, fi + 1] - phase_in[:, fi] - omega * hop_an
        dp = dp - 2.0 * np.pi * np.round(dp / (2.0 * np.pi))   # wrap to [-π,π]
        inst_freq[:, fi] = omega + dp / hop_an
    inst_freq[:, -1] = omega   # last frame: no successor, use bin frequency

    # ── How many output frames do we need to cover target_len? ────────────
    # Last frame starts at fo*hop_out and spans n_fft samples, so we need
    # fo*hop_out + n_fft >= target_len  →  fo >= (target_len - n_fft) / hop_out
    n_frames_out = max(1, int(np.ceil((target_len - n_fft) / hop_out)) + 2)

    # ── Phase-vocoder synthesis ────────────────────────────────────────────
    buf_len  = n_frames_out * hop_out + n_fft
    out_buf  = np.zeros(buf_len, dtype=np.float64)
    norm_buf = np.zeros(buf_len, dtype=np.float64)

    phase_acc = phase_in[:, 0].copy()   # seed from first input frame

    for fo in range(n_frames_out):
        # Which analysis frame does this synthesis frame correspond to?
        fi_exact = fo * hop_in / hop_an   # = fo / ratio
        fi_lo    = min(int(fi_exact), n_frames_in - 1)
        fi_hi    = min(fi_lo + 1,     n_frames_in - 1)
        alpha    = max(0.0, min(1.0, fi_exact - fi_lo))

        # Interpolate magnitude
        mag = (1.0 - alpha) * mag_in[:, fi_lo] + alpha * mag_in[:, fi_hi]

        # Synthesise frame from accumulated phase
        frame_spec = mag * np.exp(1j * phase_acc)
        frame_out  = np.fft.irfft(frame_spec).real[:n_fft] * win

        start = fo * hop_out
        out_buf[start:start + n_fft]  += frame_out
        norm_buf[start:start + n_fft] += win_sq

        # Advance phase for next synthesis frame using the instantaneous
        # frequency at the current (fractional) analysis position
        ifreq = (1.0 - alpha) * inst_freq[:, fi_lo] + alpha * inst_freq[:, fi_hi]
        phase_acc = phase_acc + ifreq * hop_out

    # ── OLA normalisation and trim ─────────────────────────────────────────
    norm_buf = np.maximum(norm_buf, ola_floor)
    result   = (out_buf / norm_buf)[:target_len].astype(np.float32)

    return result


def prepare_clip_for_mixing(clip, target_len, pitch_mode):
    """
    Bring a raw event clip to `target_len` samples using the chosen
    pitch preservation strategy.

    pitch_mode:
        "off"                    — linear resample (original behaviour,
                                   may shift pitch if clip lengths differ)
        "preserve_f0"            — pad / trim without resampling
                                   (duration changes, pitch is unchanged)
        "preserve_spectral_envelope" — phase-vocoder time-stretch
                                   (duration matches target_len exactly,
                                    spectral envelope and pitch preserved)
    """
    import numpy as np
    clip = np.asarray(clip, dtype=np.float32)
    n    = len(clip)

    if n == target_len:
        return clip.copy()

    if pitch_mode == "preserve_f0":
        return _pad_or_trim(clip, target_len)

    elif pitch_mode == "preserve_spectral_envelope":
        return _phase_vocoder_stretch(clip, target_len)

    else:  # "off" — original linear-interpolation resample
        t_src = np.linspace(0, n - 1, target_len)
        return np.interp(t_src, np.arange(n), clip).astype(np.float32)


def execute_nav_plan(plan, Z, clips, audio, sr, target_samples, seed,
                     pitch_mode="off"):
    """
    Walk through ALL steps in the navigation plan (every step is always
    rendered regardless of accumulated duration).  After all steps have
    been rendered the concatenated mono stream is time-normalized via
    linear resampling to exactly target_samples, then converted to stereo.
    This guarantees:
        len(step_stats) == len(plan)   (reported as "Used: N / N")
        output duration == requested duration

    return_anchor=-1 is a first-class sentinel meaning "use the latent
    centroid as the anchor" (center of all encoded events).

    pitch_mode: "off" | "preserve_f0" | "preserve_spectral_envelope"
        Controls how clips are brought to target_len before barycentric
        mixing.  See prepare_clip_for_mixing() for details.

    Returns: (stereo_array, step_stats, anchor_positions, stop_reason)
        stop_reason: "all_steps_rendered"
    """
    import numpy as np

    rng = np.random.RandomState(seed)
    n_events, latent_dim = Z.shape

    xfade    = max(4, int(XFADE_SEC * sr))
    angle_xf = np.linspace(0, np.pi / 2, xfade, dtype=np.float32)
    fade_in  = np.sin(angle_xf)
    fade_out = np.cos(angle_xf)

    # Latent centroid — used when return_anchor == -1
    center      = np.mean(Z, axis=0)
    current_pos = center.copy()
    velocity    = np.zeros(latent_dim)

    # Record anchor positions per step (step_index → latent position)
    anchor_positions = {}

    # Pre-allocate a generous buffer; we grow it as needed.
    # We no longer hard-stop at target_samples during the loop.
    mean_clip_len = int(np.mean([len(c) for c in clips]))
    buf_size  = mean_clip_len * (len(plan) + 4)
    output    = np.zeros(buf_size, dtype=np.float32)
    write_ptr = 0
    step_stats = []

    for si, step in enumerate(plan):
        mode          = step['mode']
        step_size     = step['step_size']
        temperature   = step['temperature']
        K             = min(step['k_neighbors'], n_events)
        return_anchor = step['return_anchor']
        return_str    = step['return_strength']
        dur_scale     = step['segment_duration_scale']
        eng_scale     = step['segment_energy_scale']

        # ── 1. Compute latent displacement ─────────────────────────────────
        if mode in ('drift', 'settle'):
            noise      = rng.randn(latent_dim) * temperature
            target_dir = velocity / (np.linalg.norm(velocity) + 1e-8)
            new_pos    = current_pos + target_dir * step_size + noise * step_size

        elif mode == 'mutate':
            noise = rng.randn(latent_dim)
            noise = noise / (np.linalg.norm(noise) + 1e-8)
            jitter  = rng.randn(latent_dim) * temperature
            new_pos = current_pos + noise * step_size + jitter

        elif mode == 'return':
            # return_anchor == -1  →  pull toward latent centroid
            if return_anchor == -1:
                anchor_pos = center
            elif return_anchor in anchor_positions:
                anchor_pos = anchor_positions[return_anchor]
            else:
                # Requested anchor not yet recorded; fall back to center
                anchor_pos = center

            pull    = anchor_pos - current_pos
            noise   = rng.randn(latent_dim) * temperature * step_size
            new_pos = current_pos + return_str * pull * step_size + noise

        else:
            # Unknown mode → treat as drift
            noise   = rng.randn(latent_dim) * temperature * step_size
            new_pos = current_pos + noise

        # Record position for potential future return references
        anchor_positions[si] = new_pos.copy()

        # Update smoothed velocity
        velocity    = 0.7 * velocity + 0.3 * (new_pos - current_pos)
        current_pos = new_pos

        # ── 2. K nearest neighbors ─────────────────────────────────────────
        dists_to_events = np.sqrt(np.sum((Z - current_pos) ** 2, axis=1))
        nn_indices   = np.argsort(dists_to_events)[:K]
        nn_positions = Z[nn_indices]

        # ── 3. Barycentric weights ─────────────────────────────────────────
        weights = barycentric_weights(current_pos, nn_positions)

        # ── 4. Mix K clips ─────────────────────────────────────────────────
        target_len = int(np.round(
            sum(w * len(clips[idx]) for w, idx in zip(weights, nn_indices))
        ))
        target_len = max(4, target_len)

        mixed = np.zeros(target_len, dtype=np.float32)
        for w, ev_idx in zip(weights, nn_indices):
            clip_raw       = clips[ev_idx].astype(np.float32)
            clip_resampled = prepare_clip_for_mixing(clip_raw, target_len, pitch_mode)
            mixed += w * clip_resampled

        # ── 5. Duration scaling ────────────────────────────────────────────
        if abs(dur_scale - 1.0) > 0.01:
            new_len = max(4, int(round(len(mixed) * dur_scale)))
            t_src   = np.linspace(0, len(mixed) - 1, new_len)
            mixed   = np.interp(t_src, np.arange(len(mixed)), mixed).astype(np.float32)

        # Energy scaling
        mixed *= eng_scale

        # ── 6. Crossfade and append ────────────────────────────────────────
        cl = len(mixed)
        do_xfade = write_ptr >= xfade and cl >= xfade * 3
        if do_xfade:
            # Fade out the tail of the already-written buffer
            output[write_ptr - xfade : write_ptr] *= fade_out
            # Fade in the head of the incoming segment
            mixed[:xfade] *= fade_in
        end = write_ptr + cl
        if end > len(output):
            output = np.pad(output, (0, end - len(output) + mean_clip_len))
        output[write_ptr:end] += mixed
        write_ptr = (write_ptr + cl - xfade if do_xfade
                     else write_ptr + cl)

        # ── Always record this step (append before any loop end) ──────────
        step_stats.append({
            'step':       si,
            'mode':       mode,
            'nn_indices': nn_indices.tolist(),
            'weights':    [round(float(w), 4) for w in weights],
            'mixed_len':  cl,
        })

    # ── Time-normalize to exactly target_samples ──────────────────────────
    # Duration is enforced here — after all plan steps are rendered —
    # so every step is always scored regardless of segment lengths.
    #
    # pitch_mode determines HOW the full raw stream is brought to length:
    #
    #   "off"                        — np.interp resample (fast, shifts pitch
    #                                   if raw_len != target_samples)
    #   "preserve_f0"                — phase-vocoder stretch on the full stream
    #                                   (preserves pitch end-to-end; also used
    #                                   for per-clip pad/trim above, but the
    #                                   global normalisation is what matters)
    #   "preserve_spectral_envelope" — also phase-vocoder (per-clip stretch
    #                                   already happened; if durations happen
    #                                   to match raw_len == target_samples this
    #                                   is a no-op; otherwise same treatment)
    raw_len = max(1, write_ptr)
    raw     = output[:raw_len]

    if raw_len == target_samples:
        mono = raw.copy().astype(np.float32)
    elif pitch_mode in ("preserve_f0", "preserve_spectral_envelope"):
        # Phase-vocoder stretch of the complete output stream.
        # This is the dominant pitch-preservation step for preserve_f0:
        # per-clip pad/trim kept individual clip pitches intact, but the
        # final stream may still be the wrong length.  A single global
        # phase-vocoder pass is far less artefact-prone than per-clip
        # stretching of many short clips.
        mono = _phase_vocoder_stretch(raw, target_samples)
    else:
        # "off" — original linear resample (may shift pitch)
        t_src = np.linspace(0, raw_len - 1, target_samples)
        mono  = np.interp(t_src, np.arange(raw_len), raw).astype(np.float32)

    # ── Stereo render ─────────────────────────────────────────────────────
    delay  = max(1, int(sr * 0.0003))   # ~0.3 ms Haas width
    stereo = np.zeros((target_samples, 2), dtype=np.float32)
    stereo[:, 0] = mono
    stereo[delay:, 1] = mono[:target_samples - delay]

    # Peak safety ceiling (normalization happens in apply_loudness_compensation)
    peak = np.max(np.abs(stereo))
    if peak > 0.99:
        stereo *= (0.99 / peak)

    return stereo, step_stats, anchor_positions, "all_steps_rendered"


# ═══════════════════════════════════════════════════════════════════════════
# Loudness compensation
# ═══════════════════════════════════════════════════════════════════════════

def apply_loudness_compensation(stereo, ref_rms, mode="rms"):
    """
    Scale stereo output so its level matches the reference.

    mode:
        "none"     — no change (pass through)
        "peak"     — scale so peak == -1 dBFS (0.891)
        "rms"      — scale output RMS to match ref_rms, then hard-limit
                     to peak ≤ -1 dBFS.  This is the IRCAM-style default.
        "loudness" — alias for "rms" (full loudness metering needs a
                     library; RMS is a good offline proxy)

    Returns the scaled stereo array (same shape, float32).
    Safety ceiling: peak is always limited to ≤ -1 dBFS (0.891) so the
    output is safe for any downstream limiter or codec.
    """
    import numpy as np

    PEAK_CEILING = 0.891   # -1 dBFS

    if mode == "none":
        return stereo

    out = stereo.astype(np.float32)
    peak = np.max(np.abs(out))
    if peak < 1e-9:
        return out   # silent — nothing to scale

    if mode == "peak":
        out *= PEAK_CEILING / peak
        return out

    # mode == "rms" or "loudness"
    out_rms = float(np.sqrt(np.mean(out ** 2)))
    if out_rms < 1e-9:
        return out

    if ref_rms > 1e-9:
        gain = ref_rms / out_rms
        out *= gain

    # Hard limiter: clip peak to ceiling
    peak_after = np.max(np.abs(out))
    if peak_after > PEAK_CEILING:
        out *= PEAK_CEILING / peak_after

    return out


# ═══════════════════════════════════════════════════════════════════════════
# Event clip extraction
# ═══════════════════════════════════════════════════════════════════════════

def extract_clips(audio, events, sr):
    """Extract mono clips per event."""
    import numpy as np
    clips     = []
    n_samples = len(audio) if audio.ndim == 1 else audio.shape[0]
    for ev in events:
        s = max(0, int(float(ev["start_time"]) * sr))
        e = min(n_samples, int(float(ev["end_time"]) * sr))
        if audio.ndim == 1:
            clips.append(audio[s:e].copy())
        else:
            clips.append(np.mean(audio[s:e], axis=1))
    return clips


# ═══════════════════════════════════════════════════════════════════════════
# Stats writer
# ═══════════════════════════════════════════════════════════════════════════

def write_stats(path, events, plan, losses, step_stats,
                sr, out_duration, plan_source, normalize_mode,
                ref_rms, out_rms, pitch_mode, warnings,
                Z=None, anchor_positions=None):
    import numpy as np

    n_steps_plan = len(plan)

    # Count modes from the PLAN (what was requested)
    plan_mode_counts = {}
    for row in plan:
        plan_mode_counts[row['mode']] = plan_mode_counts.get(row['mode'], 0) + 1

    # Count modes from step_stats (what was actually rendered)
    exec_mode_counts = {}
    for s in step_stats:
        exec_mode_counts[s['mode']] = exec_mode_counts.get(s['mode'], 0) + 1

    # ── PCA projection of events + trajectory to 2D ──────────────────────
    # Used by Praat to draw the latent trajectory panel.
    ev_x = []
    ev_y = []
    traj_x = []
    traj_y = []
    traj_modes = []

    if Z is not None and len(Z) > 0 and anchor_positions is not None:
        # Collect all points (events + trajectory) for joint PCA
        traj_indices = sorted(anchor_positions.keys())
        traj_points = np.array([anchor_positions[k] for k in traj_indices])

        all_points = np.vstack([Z, traj_points]) if len(traj_points) > 0 else Z

        # Simple 2-component PCA via SVD
        mean_pt = np.mean(all_points, axis=0)
        centered = all_points - mean_pt
        # Limit to 2 components
        if centered.shape[1] >= 2:
            U, S, Vt = np.linalg.svd(centered, full_matrices=False)
            proj = centered.dot(Vt[:2].T)  # (N, 2)
        else:
            proj = centered[:, :2] if centered.shape[1] >= 2 else np.column_stack(
                [centered[:, 0], np.zeros(len(centered))])

        n_ev = len(Z)
        ev_proj = proj[:n_ev]
        traj_proj = proj[n_ev:]

        ev_x = ev_proj[:, 0].tolist()
        ev_y = ev_proj[:, 1].tolist()
        traj_x = traj_proj[:, 0].tolist()
        traj_y = traj_proj[:, 1].tolist()

        # Get mode labels for each trajectory step
        mode_lookup = {s['step']: s['mode'] for s in step_stats}
        traj_modes = [mode_lookup.get(k, "drift") for k in traj_indices]

    with open(path, "w") as f:
        f.write("n_events=%d\n"           % len(events))
        f.write("n_plan_steps=%d\n"       % n_steps_plan)
        f.write("n_executed_steps=%d\n"   % len(step_stats))
        f.write("plan_source=%s\n"        % plan_source)
        f.write("output_duration=%.3f\n"  % out_duration)
        f.write("normalize_mode=%s\n"     % normalize_mode)
        f.write("pitch_mode=%s\n"         % pitch_mode)
        f.write("rms_input=%.6f\n"        % ref_rms)
        f.write("rms_output=%.6f\n"       % out_rms)
        f.write("final_loss=%.6f\n"       % (losses[-1] if losses else 0))
        f.write("initial_loss=%.6f\n"     % (losses[0]  if losses else 0))
        # Executed mode counts — used by Praat visualization
        for mode, cnt in sorted(exec_mode_counts.items()):
            f.write("mode_%s_steps=%d\n"  % (mode, cnt))
        mean_ev_dur = float(np.mean([
            float(e["end_time"]) - float(e["start_time"]) for e in events
        ]))
        f.write("mean_event_dur=%.3f\n"   % mean_ev_dur)

        # ── Latent trajectory data ────────────────────────────────────────
        # Event positions (PCA-projected)
        f.write("n_ev_pts=%d\n" % len(ev_x))
        for ei in range(len(ev_x)):
            f.write("ev_%d=%.4f,%.4f\n" % (ei, ev_x[ei], ev_y[ei]))

        # Navigation trajectory (PCA-projected, with mode labels)
        n_traj = min(len(traj_x), 200)  # cap for stats file size
        f.write("n_traj_pts=%d\n" % n_traj)
        for ti in range(n_traj):
            m = traj_modes[ti] if ti < len(traj_modes) else "drift"
            f.write("tr_%d=%.4f,%.4f,%s\n" % (ti, traj_x[ti], traj_y[ti], m))

        if warnings:
            f.write("warning=%s\n" % "; ".join(warnings))


# ═══════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════

def main():
    import argparse
    import numpy as np
    import soundfile as sf

    parser = argparse.ArgumentParser(
        description="Latent barycentric mutation engine"
    )

    # ── Positional args (unchanged) ────────────────────────────────────────
    parser.add_argument("input_wav")
    parser.add_argument("events_csv")
    parser.add_argument("nav_plan_csv",
        help="Path to nav plan CSV (used when --plan_source=external_csv). "
             "Pass any placeholder string when using auto_generate.")
    parser.add_argument("output_wav")
    parser.add_argument("stats_txt")

    # ── Original options (unchanged) ──────────────────────────────────────
    parser.add_argument("--latent_size", type=int,   default=8)
    parser.add_argument("--seed",        type=int,   default=42)
    parser.add_argument("--duration",    type=float, default=0.0,
        help="Target output duration in seconds (0 = match input)")
    parser.add_argument("--cleanup", action="store_true",
        help="Delete Praat-created temp files after writing output")
    parser.add_argument("--normalize_mode",
        choices=["none", "peak", "rms", "loudness"],
        default="rms",
        help="Loudness compensation: none | peak | rms (default) | loudness")
    parser.add_argument("--pitch_mode",
        choices=["off", "preserve_f0", "preserve_spectral_envelope"],
        default="off",
        help=(
            "Pitch preservation strategy applied before barycentric mixing:\n"
            "  off                        — linear resample (original, may pitch-shift)\n"
            "  preserve_f0                — pad/trim without resampling (no pitch shift,\n"
            "                               duration adjusts to weighted-average clip length)\n"
            "  preserve_spectral_envelope — phase-vocoder time-stretch (preserves pitch\n"
            "                               and formants; duration matches target exactly)"
        ))

    # ── Plan-source selector ───────────────────────────────────────────────
    parser.add_argument("--plan_source",
        choices=["external_csv", "auto_generate"],
        default="external_csv",
        help="Load plan from CSV or generate it internally")

    # ── Generator controls (used when plan_source=auto_generate) ──────────
    parser.add_argument("--plan_steps",        type=int,   default=60)
    parser.add_argument("--plan_mode_preset",
        choices=["drift", "mutate", "return", "cycle"],
        default="cycle")
    parser.add_argument("--plan_step_size",    type=float, default=0.35)
    parser.add_argument("--plan_temperature",  type=float, default=0.40)
    parser.add_argument("--plan_k",            type=int,   default=4)
    parser.add_argument("--plan_return_strength",  type=float, default=0.65)
    parser.add_argument("--plan_return_anchor_strategy",
        choices=["center", "step0", "last", "periodic"],
        default="center")
    parser.add_argument("--plan_anchor_period",    type=int,   default=15)
    parser.add_argument("--plan_dur_scale",        type=float, default=1.0)
    parser.add_argument("--plan_dur_jitter",       type=float, default=0.0)
    parser.add_argument("--plan_eng_scale",        type=float, default=1.0)
    parser.add_argument("--plan_eng_jitter",       type=float, default=0.0)
    parser.add_argument("--plan_cleanup_policy",   type=str,
        default="python_cleanup")

    args = parser.parse_args()

    check_dependencies()

    np.random.seed(args.seed)
    warnings_list = []

    # ── Stage 1: Load audio + events; load or generate plan ───────────────
    plan_source_label = args.plan_source

    if args.plan_source == "auto_generate":
        print("  [Py 1/7] Loading audio + events; generating nav plan...")
    else:
        print("  [Py 1/7] Loading audio, events, nav plan...")

    audio, sr = sf.read(args.input_wav, always_2d=False)
    audio = np.asarray(audio, dtype=np.float32)
    events = load_event_table(args.events_csv)

    n_samples = len(audio) if audio.ndim == 1 else audio.shape[0]
    orig_dur  = n_samples / sr

    target_dur     = args.duration if args.duration > 0 else orig_dur
    target_samples = int(target_dur * sr)

    # Load or generate the navigation plan
    temp_plan_csv = None   # track any Python-created temp plan file

    if args.plan_source == "external_csv":
        plan = load_nav_plan(args.nav_plan_csv)
    else:
        # Clamp k to actual event count up front so generator is aware
        max_k = min(args.plan_k, max(2, len(events)))
        plan = generate_nav_plan(
            n_steps                 = args.plan_steps,
            mode_preset             = args.plan_mode_preset,
            step_size               = args.plan_step_size,
            temperature             = args.plan_temperature,
            k_neighbors             = max_k,
            return_strength         = args.plan_return_strength,
            return_anchor_strategy  = args.plan_return_anchor_strategy,
            anchor_period           = args.plan_anchor_period,
            dur_scale               = args.plan_dur_scale,
            dur_jitter              = args.plan_dur_jitter,
            eng_scale               = args.plan_eng_scale,
            eng_jitter              = args.plan_eng_jitter,
            cleanup_policy          = args.plan_cleanup_policy,
            seed                    = args.seed,
        )

    print("    Audio: %.2fs  SR=%d  Events=%d  Plan steps=%d" %
          (orig_dur, sr, len(events), len(plan)))

    if len(events) < 3:
        warnings_list.append("Too few events (%d)" % len(events))

    # Compute input RMS for loudness compensation reference
    audio_for_rms = audio if audio.ndim == 1 else audio.mean(axis=1)
    input_rms = float(np.sqrt(np.mean(audio_for_rms.astype(np.float64) ** 2)))

    # ── Stage 2: Mel patches ───────────────────────────────────────────────
    print("  [Py 2/7] Extracting log-mel patches...")
    audio_mono = audio if audio.ndim == 1 else audio[:, 0]
    patches = extract_mel_patches(audio_mono.astype(np.float64), sr, events)
    print("    Patch shape: %s" % str(patches.shape))

    # ── Stage 3: Train VAE ─────────────────────────────────────────────────
    latent_size    = max(2, min(32, args.latent_size))
    learning_steps = max(60, min(300, 80 + len(events) * 3))
    print("  [Py 3/7] Training VAE (%d steps, latent=%d)..." %
          (learning_steps, latent_size))
    model, losses = train_vae(patches, latent_size, learning_steps, args.seed)
    lr_ratio = losses[-1] / (losses[0] + 1e-12) if losses else 1.0
    print("    Loss: %.6f → %.6f (%.1f%% reduction)" % (
        losses[0], losses[-1], (1 - lr_ratio) * 100))

    if lr_ratio > 0.95:
        warnings_list.append("VAE did not converge well")

    # ── Stage 4: Encode ────────────────────────────────────────────────────
    print("  [Py 4/7] Encoding events → latent means μ...")
    Z = encode_events(model, patches)
    print("    Z shape: %s  |  Latent range: [%.3f, %.3f]" %
          (str(Z.shape), Z.min(), Z.max()))

    # Clamp k_neighbors in the plan to actual event count (safety)
    n_ev = len(events)
    for row in plan:
        row['k_neighbors'] = min(row['k_neighbors'], n_ev)

    # ── Stage 5: Extract clips ─────────────────────────────────────────────
    print("  [Py 5/7] Extracting event clips...")
    clips = extract_clips(audio, events, sr)
    print("    %d clips, mean len %.0f samples" %
          (len(clips), np.mean([len(c) for c in clips])))

    # ── Stage 6: Execute navigation plan ──────────────────────────────────
    print("  [Py 6/7] Executing latent navigation plan (%d steps)..." % len(plan))
    print("    Pitch mode: %s" % args.pitch_mode)
    output, step_stats, anchor_positions, stop_reason = execute_nav_plan(
        plan, Z, clips, audio, sr, target_samples, args.seed,
        pitch_mode=args.pitch_mode,
    )
    print("    Used %d / %d steps | Output: %.2fs stereo | Peak: %.4f" % (
        len(step_stats), len(plan), output.shape[0] / sr, np.max(np.abs(output))))

    # ── Loudness compensation ──────────────────────────────────────────────
    pre_rms  = float(np.sqrt(np.mean(output.astype(np.float64) ** 2)))
    output   = apply_loudness_compensation(output, input_rms, args.normalize_mode)
    post_rms = float(np.sqrt(np.mean(output.astype(np.float64) ** 2)))
    print("    Normalize: %s | RMS %.4f → %.4f (input ref: %.4f)" % (
        args.normalize_mode, pre_rms, post_rms, input_rms))

    # ── Stage 7: Write output + stats ──────────────────────────────────────
    print("  [Py 7/7] Writing output + stats...")
    sf.write(args.output_wav, output, sr)
    out_dur = output.shape[0] / sr
    write_stats(args.stats_txt, events, plan, losses,
                step_stats, sr, out_dur, plan_source_label,
                args.normalize_mode, input_rms, post_rms,
                args.pitch_mode, warnings_list,
                Z=Z, anchor_positions=anchor_positions)

    # ── Stage 8: Cleanup ───────────────────────────────────────────────────
    # Only delete files that were created by Praat (have the known temp prefix).
    # Never delete user-owned files (e.g. an external nav plan CSV the user
    # placed themselves).
    if args.cleanup:
        # Praat-created temp files passed as positional arguments
        for path in [args.input_wav, args.events_csv]:
            if _is_praat_temp(path) and os.path.exists(path):
                os.remove(path)
                print("    Deleted: %s" % path)

        # nav_plan_csv: only delete if it was Praat-created temp, not
        # an external user file, and not the bundled ai-plan CSV.
        if (args.plan_source == "external_csv"
                and _is_praat_temp(args.nav_plan_csv)
                and os.path.exists(args.nav_plan_csv)):
            os.remove(args.nav_plan_csv)
            print("    Deleted: %s" % args.nav_plan_csv)

        # Any Python-generated temp plan CSV
        if temp_plan_csv and os.path.exists(temp_plan_csv):
            os.remove(temp_plan_csv)
            print("    Deleted: %s" % temp_plan_csv)

    print("OK: wrote %s" % args.output_wav)


if __name__ == "__main__":
    main()
