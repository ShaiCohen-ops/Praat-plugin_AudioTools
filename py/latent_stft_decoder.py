"""
latent_stft_decoder.py — VAE STFT Decoder (numpy-only, fast)

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University

No PyTorch / TensorFlow / sklearn. No internet. No model downloads.

Speed design:
    The VAE operates on a *downsampled* patch (vae_freq x vae_frames,
    default 32x16 = 512 dims) rather than the full STFT patch.
    Full-res complex STFTs are kept separately for phase borrowing.
    This keeps VAE weight matrices small and numpy fast.

Usage (called by Praat):
    python latent_stft_decoder.py
        input.wav events.csv output.wav stats.txt
        --latent_size 8
        --beta 0.5
        --epochs 30
        --n_fft 512
        --hop_length 128
        --patch_frames 32
        --vae_freq 32
        --vae_frames 16
        --duration 0.0
        --phase_mode borrow
        --normalize_mode rms
        --seed 42
        --nav_mode interpolate
        --nav_steps 30
        --step_size 0.15
        --temperature 0.20
        --cleanup
"""

import sys
import os
import math
import numpy as np

PRAAT_TEMP_PREFIX = "temp_stftdec_"


# ═══════════════════════════════════════════════════════════════════════════
# Utilities
# ═══════════════════════════════════════════════════════════════════════════

def check_dependencies():
    missing = []
    for pkg in ["numpy", "scipy", "soundfile"]:
        try:
            __import__(pkg)
        except ImportError:
            missing.append(pkg)
    if missing:
        print("ERROR: Missing packages: " + ", ".join(missing), file=sys.stderr)
        print("Install with:  pip install " + " ".join(missing), file=sys.stderr)
        sys.exit(1)


def _is_praat_temp(path):
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


# ═══════════════════════════════════════════════════════════════════════════
# Stage 2 — STFT Patch Extraction
# ═══════════════════════════════════════════════════════════════════════════

def extract_stft_patches(audio_mono, sr, events, n_fft, hop_length, patch_frames):
    """
    Extract log-magnitude patches [N, F, T] and complex STFTs per event.
    Full-res patches are kept for phase borrowing; VAE gets downsampled copies.

    Returns
    -------
    patches       : np.ndarray [N, F, T]  float32  log-magnitude
    complex_stfts : list of [F, T] complex128
    freq_bins     : int  (n_fft // 2 + 1)
    """
    from scipy.signal import stft as scipy_stft

    freq_bins = n_fft // 2 + 1
    noverlap  = n_fft - hop_length
    n_samples = len(audio_mono)
    patches       = []
    complex_stfts = []

    for ev in events:
        s = max(0, int(float(ev["start_time"]) * sr))
        e = min(n_samples, int(float(ev["end_time"]) * sr))
        if e <= s:
            e = min(n_samples, s + n_fft * 2)
        segment = audio_mono[s:e].astype(np.float64)
        if len(segment) < n_fft:
            segment = np.pad(segment, (0, n_fft - len(segment)))

        _, _, Zxx = scipy_stft(
            segment, fs=sr, window="hann",
            nperseg=n_fft, noverlap=noverlap, nfft=n_fft,
            boundary="zeros", padded=True,
        )
        log_mag  = np.log(np.abs(Zxx) + 1e-8).astype(np.float32)
        T_actual = log_mag.shape[1]

        if T_actual >= patch_frames:
            offset   = (T_actual - patch_frames) // 2
            patch    = log_mag[:, offset: offset + patch_frames].copy()
            zxx_crop = Zxx[:, offset: offset + patch_frames].copy()
        else:
            patch    = np.zeros((freq_bins, patch_frames), dtype=np.float32)
            zxx_crop = np.zeros((freq_bins, patch_frames), dtype=np.complex128)
            offset   = (patch_frames - T_actual) // 2
            patch[:, offset: offset + T_actual]    = log_mag
            zxx_crop[:, offset: offset + T_actual] = Zxx

        patches.append(patch)
        complex_stfts.append(zxx_crop)

    return np.array(patches, dtype=np.float32), complex_stfts, freq_bins


def _block_avg(patches, out_f, out_t):
    """
    Block-average [N, F, T] -> [N, out_f, out_t].
    Pure numpy, no scipy needed.
    """
    N, F, T = patches.shape
    vf = min(out_f, F)
    vt = min(out_t, T)

    tmp = np.zeros((N, vf, T), dtype=np.float32)
    for i in range(vf):
        f0 = int(round(i * F / vf))
        f1 = max(f0 + 1, int(round((i + 1) * F / vf)))
        tmp[:, i, :] = patches[:, f0:f1, :].mean(axis=1)

    out = np.zeros((N, vf, vt), dtype=np.float32)
    for j in range(vt):
        t0 = int(round(j * T / vt))
        t1 = max(t0 + 1, int(round((j + 1) * T / vt)))
        out[:, :, j] = tmp[:, :, t0:t1].mean(axis=2)

    return out


def normalize_patches(patches):
    mu    = float(patches.mean())
    sigma = float(patches.std()) + 1e-8
    return (patches - mu) / sigma, mu, sigma


# ═══════════════════════════════════════════════════════════════════════════
# Stage 4 — Numpy MLP Beta-VAE  (operates on small downsampled patches)
# ═══════════════════════════════════════════════════════════════════════════

class NumpySTFTVAE:
    """
    Single-hidden-layer MLP VAE trained with Adam.
    Input  : flattened downsampled patch  (vae_freq * vae_frames, typically 512)
    Latent : (latent_dim,)
    """

    def __init__(self, input_dim, latent_dim, seed=42):
        rng = np.random.RandomState(seed)
        self.rng        = rng
        self.input_dim  = input_dim
        self.latent_dim = latent_dim

        # Hidden size: generous but capped at 256 for speed
        h = max(latent_dim * 2, min(256, input_dim // 2))
        self.h = h

        def he(a, b):
            return rng.randn(a, b).astype(np.float64) * math.sqrt(2.0 / (a + b))

        # Encoder
        self.We1 = he(input_dim, h);  self.be1 = np.zeros(h)
        self.Wmu = he(h, latent_dim); self.bmu = np.zeros(latent_dim)
        self.Wlv = he(h, latent_dim); self.blv = np.zeros(latent_dim)

        # Decoder
        self.Wd1 = he(latent_dim, h); self.bd1 = np.zeros(h)
        self.Wd2 = he(h, input_dim);  self.bd2 = np.zeros(input_dim)

        self.params = [
            self.We1, self.be1,
            self.Wmu, self.bmu,
            self.Wlv, self.blv,
            self.Wd1, self.bd1,
            self.Wd2, self.bd2,
        ]
        self.t = 0
        self.m = [np.zeros_like(p) for p in self.params]
        self.v = [np.zeros_like(p) for p in self.params]

    @staticmethod
    def _relu(x):  return np.maximum(0.0, x)
    @staticmethod
    def _relug(x): return (x > 0.0).astype(np.float64)

    def encode(self, X):
        self._h1p = X.dot(self.We1) + self.be1
        self._h1  = self._relu(self._h1p)
        return (self._h1.dot(self.Wmu) + self.bmu,
                self._h1.dot(self.Wlv) + self.blv)

    def decode(self, Z):
        self._dp1 = Z.dot(self.Wd1) + self.bd1
        self._dh1 = self._relu(self._dp1)
        return self._dh1.dot(self.Wd2) + self.bd2

    def forward(self, X):
        mu, lv = self.encode(X)
        std    = np.exp(0.5 * np.clip(lv, -6, 6))
        Z      = mu + std * self.rng.randn(*std.shape)
        return self.decode(Z), mu, lv, Z

    def train_step(self, X, lr, beta_kl, noise_std=0.10, l2=1e-5):
        batch  = X.shape[0]
        Xn     = X + noise_std * self.rng.randn(*X.shape)
        recon, mu, lv, Z = self.forward(Xn)

        diff    = recon - X
        rc_loss = float(np.mean(diff ** 2))
        kl_loss = float(max(0.0, 0.5 * np.mean(mu**2 + np.exp(lv) - lv - 1.0)))

        # decoder gradients
        sc   = 2.0 / (batch * self.input_dim)
        dOut = diff * sc
        dWd2 = self._dh1.T.dot(dOut);     dbd2 = dOut.sum(0)
        d1   = dOut.dot(self.Wd2.T) * self._relug(self._dp1)
        dWd1 = Z.T.dot(d1);               dbd1 = d1.sum(0)
        dZ   = d1.dot(self.Wd1.T)

        # encoder gradients
        std  = np.exp(0.5 * np.clip(lv, -6, 6))
        dmu  = dZ + beta_kl * mu / batch
        dlv  = dZ * std * 0.5 + beta_kl * 0.5 * (np.exp(lv) - 1.0) / batch
        dWmu = self._h1.T.dot(dmu);  dbmu = dmu.sum(0)
        dWlv = self._h1.T.dot(dlv);  dblv = dlv.sum(0)
        dh1  = (dmu.dot(self.Wmu.T) + dlv.dot(self.Wlv.T)) * self._relug(self._h1p)
        dWe1 = Xn.T.dot(dh1);        dbe1 = dh1.sum(0)

        grads = [
            dWe1+l2*self.We1, dbe1,
            dWmu+l2*self.Wmu, dbmu,
            dWlv+l2*self.Wlv, dblv,
            dWd1+l2*self.Wd1, dbd1,
            dWd2+l2*self.Wd2, dbd2,
        ]
        self.t += 1
        b1, b2, ep = 0.9, 0.999, 1e-8
        for i, (p, g) in enumerate(zip(self.params, grads)):
            self.m[i] = b1*self.m[i] + (1-b1)*g
            self.v[i] = b2*self.v[i] + (1-b2)*(g**2)
            mh = self.m[i] / (1-b1**self.t)
            vh = self.v[i] / (1-b2**self.t)
            p -= lr * mh / (np.sqrt(vh) + ep)

        return rc_loss + beta_kl * kl_loss, rc_loss, kl_loss


def train_vae(vae_patches, latent_dim, beta, epochs, batch_size, seed):
    """
    vae_patches: [N, vae_freq, vae_frames] already normalized, downsampled.
    """
    N, VF, VT = vae_patches.shape
    flat_dim  = VF * VT
    X = vae_patches.reshape(N, flat_dim).astype(np.float64)
    while len(X) < max(batch_size, 4):
        X = np.vstack([X, X])

    model    = NumpySTFTVAE(flat_dim, latent_dim, seed=seed)
    losses   = []
    lr_max, lr_min = 3e-4, 5e-5

    for epoch in range(epochs):
        frac = epoch / max(1, epochs - 1)
        lr   = lr_min + 0.5*(lr_max-lr_min)*(1.0 + math.cos(math.pi*frac))
        perm = np.random.permutation(len(X))
        X    = X[perm]
        e_l = e_rc = e_kl = nb = 0

        for i in range(0, len(X), batch_size):
            b = X[i: i+batch_size]
            if len(b) < 2: continue
            l, rc, kl = model.train_step(b, lr=lr, beta_kl=beta)
            e_l += l; e_rc += rc; e_kl += kl; nb += 1

        avg_l  = e_l  / max(1, nb)
        avg_rc = e_rc / max(1, nb)
        avg_kl = e_kl / max(1, nb)
        losses.append(avg_l)

        rep = max(1, epochs // 5)
        if (epoch+1) % rep == 0 or epoch == 0:
            print("  Epoch %d/%d: recon=%.4f  kl=%.4f  total=%.4f"
                  % (epoch+1, epochs, avg_rc, avg_kl, avg_l))

    return model, losses


def encode_events(model, vae_patches):
    """vae_patches: [N, VF, VT] -> Z: [N, latent_dim] float32"""
    N, VF, VT = vae_patches.shape
    X = vae_patches.reshape(N, VF*VT).astype(np.float64)
    mu, _ = model.encode(X)
    return mu.astype(np.float32)


def decode_latents(model, Z, vae_shape, patch_mu, patch_sigma):
    """
    Z: [n_steps, latent_dim]  ->  unnormalized log-mag VAE patches [n_steps, VF, VT]
    """
    VF, VT = vae_shape
    recon  = model.decode(Z.astype(np.float64)).reshape(-1, VF, VT).astype(np.float32)
    recon  = recon * patch_sigma + patch_mu
    return np.clip(recon, math.log(1e-8), 40.0)


# ═══════════════════════════════════════════════════════════════════════════
# Stage 5 — Latent Trajectory
# ═══════════════════════════════════════════════════════════════════════════

def _latent_scale(Z):
    """
    Compute step-size scale = 50th-percentile nearest-neighbour distance.
    Using the median (not mean) avoids over-compression when many events
    cluster tightly together.  Falls back to 1.0 for single-event inputs.
    """
    n = Z.shape[0]
    if n < 2:
        return 1.0
    diff    = Z[:, np.newaxis, :] - Z[np.newaxis, :, :]   # [N,N,D]
    pdist   = np.sqrt((diff**2).sum(axis=2))               # [N,N]
    np.fill_diagonal(pdist, np.inf)
    nn_dist = pdist.min(axis=1)                            # [N]
    scale   = float(np.percentile(nn_dist, 50)) + 1e-8
    print("    Latent scale (median NN dist): %.4f  "
          "[p10=%.4f p50=%.4f p90=%.4f]"
          % (scale,
             float(np.percentile(nn_dist, 10)),
             float(np.percentile(nn_dist, 50)),
             float(np.percentile(nn_dist, 90))))
    return scale


def generate_trajectory(Z, n_steps, nav_mode, seed,
                        step_size=0.25, temperature=0.2, p_jump=0.05):
    """
    Generate a latent trajectory of length n_steps.

    Fixes for repetition:
    - Scale by median NN distance (not mean) — better for clustered spaces.
    - Start from a random event, not the mean, to land inside the cloud.
    - Teleport (p_jump) every ~1/p_jump steps to break out of dense regions.
    - Temperature boosts step magnitude so random_walk/drift actually explore.
    """
    rng        = np.random.RandomState(seed)
    latent_dim = Z.shape[1]
    n_events   = Z.shape[0]
    scale      = _latent_scale(Z)

    if nav_mode == "interpolate":
        steps_per = max(1, n_steps // max(1, n_events))
        traj = []
        for i in range(n_events):
            z0, z1 = Z[i], Z[(i+1) % n_events]
            for t in range(steps_per):
                a = t / max(1, steps_per-1) if steps_per > 1 else 0.0
                traj.append((1.0-a)*z0 + a*z1)
        while len(traj) < n_steps: traj.append(traj[-1].copy())
        return np.array(traj[:n_steps], dtype=np.float32)

    elif nav_mode == "random_walk":
        # Start from a random event (not the mean) to seed inside the cloud
        pos  = Z[rng.randint(n_events)].copy() if n_events > 0 else Z.mean(axis=0).copy()
        traj = [pos.copy()]
        for _ in range(n_steps - 1):
            # Occasional teleport to break out of stuck neighbourhoods
            if p_jump > 0 and rng.rand() < p_jump:
                pos = Z[rng.randint(n_events)].copy()
                traj.append(pos.copy())
                continue
            step  = rng.randn(latent_dim)
            step  = step / (np.linalg.norm(step) + 1e-8) * scale * step_size * (1.0 + temperature)
            step += rng.randn(latent_dim) * scale * temperature * 0.3
            pos   = pos + step
            traj.append(pos.copy())
        return np.array(traj, dtype=np.float32)

    else:  # drift — coherent direction with momentum + teleport
        pos = Z[rng.randint(n_events)].copy() if n_events > 0 else Z.mean(axis=0).copy()
        vel = rng.randn(latent_dim); vel /= np.linalg.norm(vel) + 1e-8
        traj = [pos.copy()]
        for _ in range(n_steps - 1):
            if p_jump > 0 and rng.rand() < p_jump:
                pos = Z[rng.randint(n_events)].copy()
                traj.append(pos.copy())
                continue
            noise   = rng.randn(latent_dim) * scale * temperature * step_size
            new_pos = pos + vel * scale * step_size * (1.0 + temperature * 0.5) + noise
            delta   = new_pos - pos
            vel     = 0.8*vel + 0.2*(delta / (np.linalg.norm(delta) + 1e-8))
            vel    /= np.linalg.norm(vel) + 1e-8
            pos     = new_pos
            traj.append(pos.copy())
        return np.array(traj, dtype=np.float32)


# ═══════════════════════════════════════════════════════════════════════════
# Stage 6 — Waveform Reconstruction
# ═══════════════════════════════════════════════════════════════════════════

# ═══════════════════════════════════════════════════════════════════════════
# Stage 6 — Waveform Reconstruction
# ═══════════════════════════════════════════════════════════════════════════

def _do_istft(Zxx, n_fft, hop_length, sr):
    from scipy.signal import istft
    _, audio = istft(Zxx, fs=sr, window="hann",
                     nperseg=n_fft, noverlap=n_fft-hop_length, nfft=n_fft,
                     boundary=True)
    return audio.astype(np.float32)


def _barycentric_weights(dists, k):
    """Inverse-distance weights for k nearest neighbours."""
    dists = np.maximum(dists[:k], 1e-8)
    w     = 1.0 / dists
    return w / w.sum()


def _upsample_vae_mag(vae_log_mag, F, T):
    """Nearest-neighbour upsample (VF,VT) -> (F,T) linear magnitude."""
    VF, VT  = vae_log_mag.shape
    lin_vae = np.maximum(np.exp(vae_log_mag), 0.0)
    f_idx   = np.clip((np.arange(F) * VF / F).astype(int), 0, VF-1)
    t_idx   = np.clip((np.arange(T) * VT / T).astype(int), 0, VT-1)
    return lin_vae[np.ix_(f_idx, t_idx)]   # (F, T)


def _adjust_dists_for_visits(dists, visit_scores, visit_weight=2.0):
    """
    Penalise recently-used events by inflating their effective distance.
    visit_scores: [N] float, higher = used more recently.
    visit_weight: how strongly to penalise (2.0 = doubles distance at score=1).
    """
    return dists * (1.0 + visit_weight * visit_scores)


def reconstruct_bary(vae_log_mag, Z_events, z_query, complex_stfts,
                     n_fft, hop_length, sr,
                     k=3, visit_scores=None, visit_weight=2.0,
                     prev_primary=None, phase_mode="borrow",
                     gl_n_iter=16, gl_seed=0):
    """
    Unified reconstruction: K-nearest barycentric complex-STFT mix,
    with visit-penalty and primary-index anti-repeat guard.

    Returns (audio_segment [float32], primary_event_index [int])

    visit_scores : [N] float array — inflates distances for recently used events.
    prev_primary : int or None — if the top NN equals this, rotate nn_idx to
                   avoid an immediate identical-source repeat.
    phase_mode   : "borrow" (use mixed complex phase) | "griffinlim"
    """
    raw_dists = np.linalg.norm(Z_events - z_query, axis=1)

    # Apply visit penalty
    if visit_scores is not None:
        adj_dists = _adjust_dists_for_visits(raw_dists, visit_scores, visit_weight)
    else:
        adj_dists = raw_dists

    k_use  = min(k, len(Z_events))
    nn_idx = np.argsort(adj_dists)[:k_use]

    # Anti-repeat guard: if top candidate is same as previous primary, rotate
    if prev_primary is not None and len(nn_idx) > 1 and nn_idx[0] == prev_primary:
        nn_idx = np.concatenate([nn_idx[1:], nn_idx[:1]])

    primary = int(nn_idx[0])
    weights = _barycentric_weights(raw_dists[nn_idx], k_use)

    F, T = complex_stfts[nn_idx[0]].shape

    if phase_mode == "borrow":
        # Weighted complex STFT mix
        Zxx_mixed = np.zeros((F, T), dtype=np.complex128)
        for w, idx in zip(weights, nn_idx):
            Zxx_mixed += w * complex_stfts[idx]

        lin_vae  = _upsample_vae_mag(vae_log_mag, F, T)
        mag_mix  = np.abs(Zxx_mixed)
        ref_mean = float(mag_mix.mean()) + 1e-8
        vae_mean = float(lin_vae.mean()) + 1e-8
        mag_out  = mag_mix * (lin_vae / vae_mean * ref_mean)
        Zxx_out  = mag_out * np.exp(1j * np.angle(Zxx_mixed))
        audio    = _do_istft(Zxx_out, n_fft, hop_length, sr)

    else:  # griffinlim
        from scipy.signal import stft as scipy_stft, istft as scipy_istft

        mag_mixed = np.zeros((F, T), dtype=np.float64)
        for w, idx in zip(weights, nn_idx):
            mag_mixed += w * np.abs(complex_stfts[idx])

        lin_vae  = _upsample_vae_mag(vae_log_mag, F, T).astype(np.float64)
        ref_mean = float(mag_mixed.mean()) + 1e-8
        vae_mean = float(lin_vae.mean())   + 1e-8
        lin_mag  = mag_mixed * (lin_vae / vae_mean * ref_mean)

        rng      = np.random.RandomState(gl_seed)
        noverlap = n_fft - hop_length
        phase    = rng.uniform(0, 2*np.pi, (F, T))
        cspec    = lin_mag * np.exp(1j * phase)
        for _ in range(gl_n_iter):
            _, aud = scipy_istft(cspec, fs=sr, window="hann",
                                 nperseg=n_fft, noverlap=noverlap, nfft=n_fft,
                                 boundary=True)
            _, _, re = scipy_stft(aud, fs=sr, window="hann",
                                  nperseg=n_fft, noverlap=noverlap, nfft=n_fft,
                                  boundary="zeros", padded=True)
            if re.shape[1] < T: re = np.pad(re, ((0,0),(0,T-re.shape[1])))
            cspec = lin_mag * np.exp(1j * np.angle(re[:F, :T]))
        _, aud = scipy_istft(cspec, fs=sr, window="hann",
                             nperseg=n_fft, noverlap=noverlap, nfft=n_fft,
                             boundary=True)
        audio = aud.astype(np.float32)

    return audio, primary


# Keep old names as thin wrappers so nothing else breaks
def reconstruct_phase_borrow(vae_log_mag, full_patches, Z_events, z_query,
                              complex_stfts, n_fft, hop_length, sr, k=3):
    audio, _ = reconstruct_bary(vae_log_mag, Z_events, z_query, complex_stfts,
                                 n_fft, hop_length, sr, k=k, phase_mode="borrow")
    return audio


def reconstruct_griffin_lim(vae_log_mag, full_patches, Z_events, z_query,
                             complex_stfts, n_fft, hop_length, sr,
                             n_iter=16, seed=0, k=3):
    audio, _ = reconstruct_bary(vae_log_mag, Z_events, z_query, complex_stfts,
                                 n_fft, hop_length, sr, k=k, phase_mode="griffinlim",
                                 gl_n_iter=n_iter, gl_seed=seed)
    return audio


# ═══════════════════════════════════════════════════════════════════════════
# Stage 7 — Assemble Output
# ═══════════════════════════════════════════════════════════════════════════

def assemble_output(segments, sr, target_samples, xfade_sec=0.010):
    if not segments:
        return np.zeros(target_samples, dtype=np.float32)
    xfade  = max(4, int(xfade_sec * sr))
    result = np.asarray(segments[0], dtype=np.float32).copy()
    for seg in segments[1:]:
        seg = np.asarray(seg, dtype=np.float32).copy()
        xf  = min(xfade, len(result)//2, len(seg)//2)
        if xf < 2:
            result = np.concatenate([result, seg]); continue
        fade              = np.linspace(0.0, 1.0, xf, dtype=np.float32)
        result[-xf:]     *= (1.0 - fade)
        seg[:xf]         *= fade
        merged            = np.zeros(len(result)+len(seg)-xf, dtype=np.float32)
        merged[:len(result)]       = result
        merged[len(result)-xf:]   += seg
        result = merged
    if len(result) == 0:
        return np.zeros(target_samples, dtype=np.float32)
    if len(result) == target_samples:
        return result.copy()
    from scipy.signal import resample
    return resample(result, target_samples).astype(np.float32)


def apply_normalization(audio, ref_rms, mode):
    CEIL = 0.891
    out  = audio.astype(np.float32)
    peak = float(np.max(np.abs(out)))
    if peak < 1e-9: return out
    if mode == "peak":
        out *= CEIL / peak
    elif mode in ("rms", "loudness"):
        rms = float(np.sqrt(np.mean(out.astype(np.float64)**2)))
        if rms > 1e-9 and ref_rms > 1e-9: out *= ref_rms / rms
        pk2 = float(np.max(np.abs(out)))
        if pk2 > CEIL: out *= CEIL / pk2
    return out


# ═══════════════════════════════════════════════════════════════════════════
# Stats
# ═══════════════════════════════════════════════════════════════════════════

def write_stats(path, n_events, n_steps, nav_mode, phase_mode,
                latent_size, beta, epochs, n_fft, hop_length, patch_frames,
                vae_freq, vae_frames, freq_bins, losses, sr, out_dur,
                normalize_mode, ref_rms, out_rms, warnings_list):
    with open(path, "w") as f:
        f.write("n_events=%d\n"          % n_events)
        f.write("n_steps=%d\n"           % n_steps)
        f.write("nav_mode=%s\n"          % nav_mode)
        f.write("phase_mode=%s\n"        % phase_mode)
        f.write("latent_size=%d\n"       % latent_size)
        f.write("beta=%.4f\n"            % beta)
        f.write("epochs=%d\n"            % epochs)
        f.write("n_fft=%d\n"             % n_fft)
        f.write("hop_length=%d\n"        % hop_length)
        f.write("patch_frames=%d\n"      % patch_frames)
        f.write("vae_freq=%d\n"          % vae_freq)
        f.write("vae_frames=%d\n"        % vae_frames)
        f.write("freq_bins=%d\n"         % freq_bins)
        f.write("output_duration=%.3f\n" % out_dur)
        f.write("normalize_mode=%s\n"    % normalize_mode)
        f.write("rms_input=%.6f\n"       % ref_rms)
        f.write("rms_output=%.6f\n"      % out_rms)
        f.write("initial_loss=%.6f\n"    % (losses[0]  if losses else 0.0))
        f.write("final_loss=%.6f\n"      % (losses[-1] if losses else 0.0))
        for w in warnings_list:
            f.write("warning=%s\n" % w)


# ═══════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════

def main():
    import argparse
    import soundfile as sf

    parser = argparse.ArgumentParser(description="Latent STFT Decoder VAE (numpy-only, fast)")
    parser.add_argument("input_wav")
    parser.add_argument("events_csv")
    parser.add_argument("output_wav")
    parser.add_argument("stats_txt")
    # VAE
    parser.add_argument("--latent_size",  type=int,   default=8)
    parser.add_argument("--beta",         type=float, default=0.5)
    parser.add_argument("--epochs",       type=int,   default=30)
    # STFT
    parser.add_argument("--n_fft",        type=int,   default=512)
    parser.add_argument("--hop_length",   type=int,   default=128)
    parser.add_argument("--patch_frames", type=int,   default=32)
    # VAE downsampled grid (key speed control)
    parser.add_argument("--vae_freq",     type=int,   default=32,
        help="Freq bins fed to VAE after downsampling (default 32)")
    parser.add_argument("--vae_frames",   type=int,   default=16,
        help="Time frames fed to VAE after downsampling (default 16)")
    # Output
    parser.add_argument("--duration",     type=float, default=0.0)
    parser.add_argument("--phase_mode",
        choices=["borrow","griffinlim"], default="borrow")
    parser.add_argument("--normalize_mode",
        choices=["none","peak","rms"], default="rms")
    parser.add_argument("--seed",         type=int,   default=42)
    # Navigation
    parser.add_argument("--nav_mode",
        choices=["interpolate","random_walk","drift"], default="interpolate")
    parser.add_argument("--nav_steps",    type=int,   default=30)
    parser.add_argument("--k_neighbors",  type=int,   default=4,
        help="K nearest events to mix per step (default 4)")
    parser.add_argument("--p_jump",       type=float, default=0.05,
        help="Probability of teleport to random event per step (default 0.05)")
    parser.add_argument("--visit_weight", type=float, default=2.0,
        help="Visit-penalty strength for recently-used events (default 2.0)")
    parser.add_argument("--visit_decay",  type=float, default=0.92,
        help="Per-step decay of visit scores (default 0.92)")
    parser.add_argument("--step_size",    type=float, default=0.30)
    parser.add_argument("--temperature",  type=float, default=0.25)
    parser.add_argument("--cleanup",      action="store_true")
    args = parser.parse_args()

    check_dependencies()
    np.random.seed(args.seed)
    warnings_list = []

    # ── Stage 1 ────────────────────────────────────────────────────────────
    print("  [Py 1/9] Loading audio + events...")
    audio, sr = sf.read(args.input_wav, always_2d=False)
    audio     = np.asarray(audio, dtype=np.float32)
    events    = load_event_table(args.events_csv)

    n_samples      = len(audio) if audio.ndim == 1 else audio.shape[0]
    orig_dur       = n_samples / sr
    target_dur     = args.duration if args.duration > 0 else orig_dur
    target_samples = int(round(target_dur * sr))

    seg_samples = max(1, args.patch_frames * args.hop_length)
    nav_steps   = (max(4, int(math.ceil(target_samples / seg_samples)))
                   if args.duration > 0 else max(4, args.nav_steps))

    print("    Audio: %.2fs  SR=%d  Events=%d  Nav steps=%d"
          % (orig_dur, sr, len(events), nav_steps))
    if len(events) < 2:
        warnings_list.append("Too few events (%d)" % len(events))

    audio_mono = audio if audio.ndim == 1 else audio.mean(axis=1)
    ref_rms    = float(np.sqrt(np.mean(audio_mono.astype(np.float64)**2)))

    # ── Stage 2 ────────────────────────────────────────────────────────────
    print("  [Py 2/9] Extracting STFT patches (n_fft=%d hop=%d frames=%d)..."
          % (args.n_fft, args.hop_length, args.patch_frames))
    patches, complex_stfts, freq_bins = extract_stft_patches(
        audio_mono, sr, events, args.n_fft, args.hop_length, args.patch_frames)
    print("    Full patches: %s   freq_bins: %d" % (str(patches.shape), freq_bins))

    # ── Stage 3 ────────────────────────────────────────────────────────────
    print("  [Py 3/9] Downsampling + normalizing patches for VAE...")
    vae_freq   = max(4, min(args.vae_freq,   freq_bins))
    vae_frames = max(4, min(args.vae_frames, args.patch_frames))
    vae_patches = _block_avg(patches, vae_freq, vae_frames)
    print("    VAE input: %s  (flat_dim=%d)"
          % (str(vae_patches.shape), vae_freq * vae_frames))
    vae_norm, patch_mu, patch_sigma = normalize_patches(vae_patches)

    # ── Stage 4 ────────────────────────────────────────────────────────────
    latent_size = max(2, min(32, args.latent_size))
    batch_size  = max(2, min(16, len(events)))
    print("  [Py 4/9] Training VAE (epochs=%d latent=%d beta=%.2f "
          "vae_dim=%dx%d)..."
          % (args.epochs, latent_size, args.beta, vae_freq, vae_frames))
    model, losses = train_vae(vae_norm, latent_size, args.beta,
                              args.epochs, batch_size, args.seed)
    if len(losses) >= 2:
        pct = 100.0 * max(0.0, 1.0 - losses[-1]/(losses[0]+1e-12))
        print("    Loss: %.6f -> %.6f  (%.1f%% reduction)"
              % (losses[0], losses[-1], pct))
    if len(losses) > 1 and losses[-1]/(losses[0]+1e-12) > 0.95:
        warnings_list.append("VAE may not have converged — consider more epochs")

    # ── Stage 5 ────────────────────────────────────────────────────────────
    print("  [Py 5/9] Encoding events -> latent means Z...")
    Z = encode_events(model, vae_norm)
    print("    Z: %s  range [%.3f, %.3f]"
          % (str(Z.shape), float(Z.min()), float(Z.max())))

    # ── Stage 6 ────────────────────────────────────────────────────────────
    print("  [Py 6/9] Generating latent trajectory (%s, %d steps)..."
          % (args.nav_mode, nav_steps))
    trajectory = generate_trajectory(Z, nav_steps, args.nav_mode,
                                     args.seed, args.step_size, args.temperature,
                                     p_jump=args.p_jump)

    # ── Stage 7 ────────────────────────────────────────────────────────────
    print("  [Py 7/9] Decoding VAE patches...")
    vae_log_mags = decode_latents(model, trajectory,
                                  (vae_freq, vae_frames), patch_mu, patch_sigma)
    print("    Decoded: %s" % str(vae_log_mags.shape))

    # ── Stage 8 ────────────────────────────────────────────────────────────
    print("  [Py 8/9] Reconstructing waveforms (phase_mode=%s, k=%d, "
          "visit_weight=%.1f, visit_decay=%.2f)..."
          % (args.phase_mode, args.k_neighbors, args.visit_weight, args.visit_decay))

    visit_scores = np.zeros(len(events), dtype=np.float64)
    prev_primary = None
    segments     = []

    for i in range(nav_steps):
        audio, primary = reconstruct_bary(
            vae_log_mags[i], Z, trajectory[i], complex_stfts,
            args.n_fft, args.hop_length, sr,
            k            = args.k_neighbors,
            visit_scores = visit_scores,
            visit_weight = args.visit_weight,
            prev_primary = prev_primary,
            phase_mode   = args.phase_mode,
            gl_n_iter    = 16,
            gl_seed      = args.seed + i,
        )
        # Update visit penalty
        visit_scores *= args.visit_decay
        visit_scores[primary] += 1.0
        prev_primary = primary
        segments.append(audio)

    output = assemble_output(segments, sr, target_samples)
    if args.normalize_mode != "none":
        output = apply_normalization(output, ref_rms, args.normalize_mode)

    out_rms = float(np.sqrt(np.mean(output.astype(np.float64)**2)))
    out_dur = len(output) / sr

    delay  = max(1, int(sr * 0.0003))
    stereo = np.zeros((len(output), 2), dtype=np.float32)
    stereo[:, 0]      = output
    stereo[delay:, 1] = output[:len(output)-delay]

    # ── Stage 9 ────────────────────────────────────────────────────────────
    print("  [Py 9/9] Writing output + stats...")
    sf.write(args.output_wav, stereo, sr)
    print("    Output: %.2fs stereo  peak=%.4f  rms=%.4f"
          % (out_dur, float(np.max(np.abs(stereo))), out_rms))

    write_stats(args.stats_txt, len(events), nav_steps, args.nav_mode,
                args.phase_mode, latent_size, args.beta, args.epochs,
                args.n_fft, args.hop_length, args.patch_frames,
                vae_freq, vae_frames, freq_bins, losses, sr, out_dur,
                args.normalize_mode, ref_rms, out_rms, warnings_list)

    if args.cleanup:
        for path in [args.input_wav, args.events_csv]:
            if _is_praat_temp(path) and os.path.exists(path):
                os.remove(path)
                print("    Deleted: %s" % path)

    print("OK: wrote %s" % args.output_wav)


if __name__ == "__main__":
    main()
