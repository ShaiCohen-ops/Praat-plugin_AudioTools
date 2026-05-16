# -*- coding: utf-8 -*-
"""
phase_diffusion_ai.py — Latent Spectral Diffusion Engine
Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University
Version: 6.0 (2026)

(filename `phase_diffusion_ai.py` preserved for distribution compatibility)

Called by PhaseDiffusion.praat.

═══════════════════════════════════════════════════════════════════════════════
ARCHITECTURE v6.0 — LATENT AUTOENCODER + SPECTRAL DIFFUSION
═══════════════════════════════════════════════════════════════════════════════

Shared pipeline across all three models:

  • Spectral-flux onset detection with adaptive threshold → events (0.1-2.0 s)
  • Log-Mel patch extraction (40 mel bands × 16 frames per event)
  • NumpyAutoencoder — 4-layer MLP (input → hidden → latent → hidden → output),
    leaky ReLU, Adam, denoising training, L2 regularisation. Hand-coded
    backprop + Adam in pure numpy; no PyTorch / TensorFlow.
  • K-means++ latent clustering
  • Per-event per-mel-band reconstruction error from the trained AE,
    projected through the mel filterbank to per-FFT-bin coherence weights
    (genuinely frequency-dependent — see Stage 5a note below)

The signal is segmented into short events. A small autoencoder is trained
from scratch on the log-Mel patches of those events. The trained network's
per-mel-band reconstruction error becomes the frequency-axis coherence
profile.

THREE MODELS
─────────────────────────────────────────────────────────────────────────────

  pca   — AE-Weighted (Praat label).
          Random phase + per-bin magnitude attenuation guided by AE-learned
          per-band coherence. Bands the AE reconstructed well (low band-MSE,
          interpreted as more structured/tonal) receive more attenuation in
          the diffused signal. Bands the AE reconstructed poorly (high
          band-MSE, noisy/transient) are protected. NB: no SVD/PCA happens
          anywhere in this model — the historical "PCA" name is retained
          only as the --model CLI argument for backward compatibility with
          existing wrappers. The Praat form shows "AE-Weighted".

  ar    — AR Smear (Praat label).
          AR(1) per-bin coefficient fitting from sampled frames → IIR
          magnitude decay rate. Gated by AE coherence: bins that are both
          temporally sustained (high AR coeff) AND well-reconstructed by
          the AE (low band-MSE) get the heaviest magnitude smear. Random
          phase across all bins.

  latent — Full latent-space diffusion.
          The signal's events are encoded to latent vectors Z via the
          trained autoencoder. K-means++ clusters Z into groups. Each
          event's Z is walked toward its cluster centroid via temperature-
          annealed gradient descent + Langevin-style noise, then decoded
          back to a mel patch. The decoded patch's energy profile becomes
          the magnitude envelope for that event's paulstretch-style window.
          Result: each event sounds like a blend of acoustically similar
          events from the same recording, navigated by temperature.

          diffusion_amount: mixing weight between the event's own decoded
          magnitude and the diffused-Z decoded magnitude.
          diffusion_steps:  number of gradient-descent steps per event.

STAGE 5a — v6.0 CORRECTNESS FIX
─────────────────────────────────────────────────────────────────────────────
v5.0/v5.1 documented Stage 5a as "per-bin coherence weights genuinely
learned from the signal". The implementation, however, used a SCALAR
per-event reconstruction error (mean across all 640 input dimensions),
broadcast UNIFORMLY across all 40 mel bands, then projected through the
filterbank transpose. The resulting frequency variation came from the
filterbank's overlap geometry (low-frequency bins have more triangular
bands stacking on them), NOT from anything the AE had learned about which
frequencies were structured vs noisy.

v6.0 computes the per-event per-mel-band MSE explicitly (averaging the
squared reconstruction error across the time dimension of each (40×16)
patch, leaving the band dimension intact), then time-weighted-averages
across events to get a single (40,) per-band error profile, and finally
projects that through mel_fb.T to (n_fft_bins,) per-bin weights. The
resulting weight profile now genuinely depends on which frequencies the
trained AE could reconstruct well. PCA and AR models become frequency-
discriminative in the way the v5 docs always promised.

WHAT IS AND ISN'T LEARNED
─────────────────────────────────────────────────────────────────────────────
The AE typically trains on 20-50 events with 640 input dims and ~50k-100k
parameters. That is severely underdetermined — the network essentially
memorises THIS recording rather than learning a generalisable codebook.
For the use case ("make variations of this specific recording") that is
the desired behaviour: the latent space IS a representation of THIS
signal's acoustic vocabulary, and moving in Z navigates a manifold local
to it. The PCA/AR per-band weights reflect "which bands of THIS recording
were easy/hard for a small network to compress" rather than any universal
notion of tonal-vs-noisy.

PARAMETERS
─────────────────────────────────────────────────────────────────────────────
  --model {pca, ar, latent}      (pca = AE-Weighted; ar = AR Smear)
  --diffusion-amount FLOAT       0-1 dry/wet crossfade
  --diffusion-steps  INT         latent: gradient steps per event
  --window-size      INT         paulstretch-style FFT window (samples)
  --hop-size         INT         paulstretch hop (samples)
  --mag-smear        FLOAT       AR: IIR decay scale; PCA: weight sharpness
  --latent-size      INT         autoencoder bottleneck (default 8)
  --train-steps      INT         autoencoder training iterations (default 150)
  --n-clusters       INT         k-means++ clusters (default 4)
  --temperature      FLOAT       latent diffusion temperature (default 1.0)
  --preserve-transients
  --seed INT
  --status-file PATH
  --debug

Usage:
    python phase_diffusion_ai.py input.wav output.wav
        --model {pca,ar,latent}
        --diffusion-amount FLOAT
        --diffusion-steps  INT
        --window-size INT  --hop-size INT
        --mag-smear FLOAT
        --latent-size INT  --train-steps INT
        --n-clusters INT   --temperature FLOAT
        [--preserve-transients] [--seed INT]
        [--status-file PATH] [--debug]
"""

import sys
import math
import argparse
import numpy as np

# Force UTF-8 stdout on Windows
if sys.stdout.encoding and sys.stdout.encoding.lower() not in ("utf-8", "utf8"):
    import io
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8",
                                  errors="replace")

# ═══════════════════════════════════════════════════════════════════════════
# Constants (match the suite)
# ═══════════════════════════════════════════════════════════════════════════

N_MELS      = 40
MEL_FRAMES  = 16
EVENT_MIN   = 0.10   # seconds
EVENT_MAX   = 2.00
XFADE_SEC   = 0.008

# ═══════════════════════════════════════════════════════════════════════════
# Audio I/O
# ═══════════════════════════════════════════════════════════════════════════

def load_audio(path):
    import soundfile as sf
    audio, sr = sf.read(path, always_2d=True)
    return audio.astype(np.float64), int(sr)


def save_audio(path, audio, sr):
    import soundfile as sf
    audio = np.asarray(audio, dtype=np.float64)
    peak  = float(np.max(np.abs(audio)))
    if peak > 0.99:
        audio = audio / peak * 0.99
    sf.write(path, audio, sr, subtype="PCM_24")


# ═══════════════════════════════════════════════════════════════════════════
# Stage 1 — Event Segmentation
# ═══════════════════════════════════════════════════════════════════════════

def segment_events(audio_mono, sr, event_min=EVENT_MIN, event_max=EVENT_MAX):
    """
    Segment audio into events using spectral flux onset detection.
    Returns list of dicts with 'start_time', 'end_time'.
    Falls back to fixed-length frames if signal is too short.
    """
    n         = len(audio_mono)
    hop       = int(0.010 * sr)   # 10 ms hop
    win       = int(0.025 * sr)   # 25 ms window
    min_samp  = int(event_min * sr)
    max_samp  = int(event_max * sr)

    # Spectral flux
    prev_mag  = np.zeros(win // 2 + 1)
    flux      = []
    for pos in range(0, n - win, hop):
        frame   = audio_mono[pos:pos + win] * np.hanning(win)
        mag     = np.abs(np.fft.rfft(frame))
        flux.append(np.sum(np.maximum(mag - prev_mag, 0.0)))
        prev_mag = mag

    flux = np.array(flux, dtype=np.float64)

    # Adaptive threshold: local mean + 1.0 × std in 200 ms window
    from scipy.ndimage import uniform_filter1d
    w_frames  = max(1, int(0.200 / 0.010))
    w_size    = 2 * w_frames + 1
    local_mean = uniform_filter1d(flux, size=w_size, mode="nearest")
    local_sq   = uniform_filter1d(flux ** 2, size=w_size, mode="nearest")
    local_std  = np.sqrt(np.maximum(local_sq - local_mean ** 2, 0.0))
    threshold  = local_mean + 1.0 * local_std

    # Collect onset frames
    onset_samps = [0]
    last_onset  = 0
    for i in range(1, len(flux) - 1):
        if flux[i] > threshold[i] and flux[i] > flux[i - 1]:
            samp = i * hop
            if samp - last_onset >= min_samp:
                onset_samps.append(samp)
                last_onset = samp
    onset_samps.append(n)

    # Build events — split if too long
    events = []
    for i in range(len(onset_samps) - 1):
        s = onset_samps[i]
        e = onset_samps[i + 1]
        while e - s > max_samp:
            events.append({"start_time": s / sr, "end_time": (s + max_samp) / sr})
            s += max_samp
        if e - s >= min_samp - 1:   # 1-sample tolerance for float rounding
            events.append({"start_time": s / sr, "end_time": e / sr})

    # Fallback: too few events → fixed 0.5 s frames
    if len(events) < 4:
        events = []
        step = max(min_samp, int(0.5 * sr))
        for s in range(0, n - min_samp, step):
            events.append({"start_time": s / sr,
                           "end_time":   min(n, s + step) / sr})

    return events


# ═══════════════════════════════════════════════════════════════════════════
# Stage 2 — Log-Mel Patch Extraction  (identical to rest of suite)
# ═══════════════════════════════════════════════════════════════════════════

def build_mel_filterbank(sr, n_fft, n_mels):
    def hz_to_mel(hz):
        return 2595.0 * np.log10(1.0 + hz / 700.0)
    def mel_to_hz(mel):
        return 700.0 * (10.0 ** (mel / 2595.0) - 1.0)

    n_bins   = n_fft // 2 + 1
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
    n_fft  = 1024
    hop    = 256
    window = np.hanning(n_fft)
    mel_fb = build_mel_filterbank(sr, n_fft, N_MELS)
    n_bins = n_fft // 2 + 1
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
            if len(frame) == n_fft:
                frame = frame * window
            else:
                frame = np.zeros(n_fft)
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
# Stage 3 — NumpyAutoencoder  (identical architecture to suite)
#
# MLP: input → hidden → latent → hidden → output
# Leaky ReLU  |  Denoising  |  L2 regularisation  |  Adam optimiser
# Pure numpy — no external ML framework required.
# ═══════════════════════════════════════════════════════════════════════════

class NumpyAutoencoder(object):

    def __init__(self, input_dim, hidden_dim, latent_dim, seed=42):
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
        return np.where(x > 0, x, a * x)

    def _leaky_g(self, x, a=0.01):
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
        return np.mean((self.forward(X) - X) ** 2, axis=1)


def train_autoencoder(patches, latent_size, n_steps, seed, debug=False):
    n_events, input_dim = patches.shape
    hidden_dim = max(latent_size * 2,
                     min(256, int(np.sqrt(input_dim * latent_size))))
    model = NumpyAutoencoder(input_dim, hidden_dim, latent_size, seed)

    mu    = np.mean(patches, axis=0)
    sigma = np.std(patches,  axis=0) + 1e-8
    X     = (patches - mu) / sigma

    losses = []
    for step in range(n_steps):
        frac  = step / max(1, n_steps - 1)
        cn    = 0.3  * (1.0 - 0.5 * frac)   # noise anneals down
        cl    = 0.003 * (1.0 - 0.3 * frac)   # lr anneals down
        loss  = model.train_step(X, lr=cl, noise_std=cn, l2_reg=1e-4)
        losses.append(loss)

    model._norm_mu    = mu
    model._norm_sigma = sigma

    if debug:
        ratio = losses[-1] / (losses[0] + 1e-12)
        print("  [AE]  input_dim=%d  hidden=%d  latent=%d  steps=%d"
              % (input_dim, hidden_dim, latent_size, n_steps))
        print("  [AE]  loss %.6f -> %.6f  (%.1f%% reduction)"
              % (losses[0], losses[-1], (1 - ratio) * 100))

    return model, losses


def encode_events(model, patches):
    """
    Encode patches -> latent Z, scalar reconstruction errors, and per-mel-band
    reconstruction errors.

    Returns:
        Z          : (n_events, latent_dim)  latent vectors
        event_errs : (n_events,)             per-event scalar MSE (mean across all 640 dims)
        band_errs  : (n_events, N_MELS)      per-event per-mel-band MSE
                                             (mean of squared error across the 16 time frames
                                              of each event patch, leaving the band axis intact)

    The band_errs return value is what Stage 5a now uses to build genuinely
    frequency-dependent coherence weights. v5.x used only the scalar
    event_errs broadcast uniformly across bands, which gave coherence weights
    whose frequency profile came entirely from filterbank geometry rather
    than from anything the AE had learned per-band.
    """
    X     = (patches - model._norm_mu) / model._norm_sigma
    Z     = model.encode(X)
    recon = model.decode(Z)
    sq_err = (recon - X) ** 2                         # (n_events, N_MELS * MEL_FRAMES)
    event_errs = sq_err.mean(axis=1)                   # (n_events,)
    n_events   = sq_err.shape[0]
    band_errs  = sq_err.reshape(n_events, N_MELS, MEL_FRAMES).mean(axis=2)
    return Z, event_errs, band_errs


# ═══════════════════════════════════════════════════════════════════════════
# Stage 4 — K-means++ clustering  (identical to latent_diffusion.py)
# ═══════════════════════════════════════════════════════════════════════════

def kmeans_plus_plus(Z, k, n_iter=60, seed=42):
    rng = np.random.RandomState(seed)
    n   = len(Z)
    k   = min(k, n)

    first_idx = rng.randint(n)
    centers   = [Z[first_idx].copy()]
    for _ in range(k - 1):
        d_sq   = np.min(np.array([np.sum((Z - c) ** 2, axis=1)
                                  for c in centers]), axis=0)
        probs  = d_sq / (d_sq.sum() + 1e-12)
        idx    = rng.choice(n, p=probs)
        centers.append(Z[idx].copy())
    centers = np.array(centers)

    labels = np.zeros(n, dtype=int)
    for _ in range(n_iter):
        dists_mat  = np.array([np.sum((Z - c) ** 2, axis=1) for c in centers])
        new_labels = np.argmin(dists_mat, axis=0)
        if np.all(new_labels == labels):
            break
        labels = new_labels
        for ki in range(k):
            mask = labels == ki
            if np.sum(mask) > 0:
                centers[ki] = Z[mask].mean(axis=0)

    return centers, labels


# ═══════════════════════════════════════════════════════════════════════════
# Stage 5a — AE per-band reconstruction error -> per-FFT-bin coherence weights
#
# v6.0 honest implementation:
#   1. band_errs is (n_events, N_MELS) — per-event per-mel-band MSE from the AE.
#      Each entry is the mean squared reconstruction error over the 16 time
#      frames of that event's patch, for that specific mel band.
#   2. Time-weighted average across events (weight = event duration in seconds)
#      gives a single (N_MELS,) per-band error profile for the whole recording.
#   3. Project that profile through mel_fb.T to get (n_fft_bins,) per-bin
#      weight: each FFT bin gets a weight = weighted sum of band errors from
#      the mel bands whose triangular filters overlap that bin.
#   4. Normalise to [0, 1].
#
# Interpretation: high weight at bin f means the AE struggled to reconstruct
# the mel bands covering f -> "unstructured / noisy / transient" frequency
# region of THIS recording. Low weight means the AE handled those bands
# well -> "structured / tonal" region. The PCA and AR models invert this to
# get a coherence weight (1 - ae_weight) where tonal bins get more diffusion.
#
# What changed from v5.x: v5 broadcast a single scalar across all mel bands
# before projection, so the frequency variation in the final weight vector
# came entirely from mel filterbank overlap geometry (low-freq bins are
# covered by more triangles), NOT from anything the AE had learned about
# individual bands. v6 keeps the per-band axis intact through to projection,
# so the frequency profile is now genuinely AE-derived.
# ═══════════════════════════════════════════════════════════════════════════

def ae_error_to_bin_weights(band_errs, events, mel_fb, n_fft_bins, sr,
                            n_samples, win_size):
    """
    band_errs : (n_events, N_MELS) per-event per-mel-band reconstruction MSE
    events    : list of {'start_time', 'end_time'}
    mel_fb    : (N_MELS, n_fft_bins) filterbank at win_size resolution
    Returns   : (n_fft_bins,) weight array, normalised to [0, 1]
                High weight = AE failed for that frequency region = noisy
                Low weight  = AE reconstructed well there        = structured
    """
    # Time-weighted average of per-band errors across events
    band_sum   = np.zeros(N_MELS)
    weight_sum = 0.0
    for ev, b_err in zip(events, band_errs):
        dur_w       = float(ev["end_time"]) - float(ev["start_time"])
        band_sum   += b_err * dur_w
        weight_sum += dur_w
    band_avg = band_sum / (weight_sum + 1e-12)        # (N_MELS,)

    # Project per-band error profile through mel filterbank transpose to FFT bins.
    # mel_fb is (N_MELS, n_fft_bins); .T maps from mel-band space to FFT-bin space,
    # weighting each bin by how much each band's triangular filter overlaps it.
    bin_weights = mel_fb.T.dot(band_avg)              # (n_fft_bins,)

    # Normalise to [0, 1]
    w_min, w_max = bin_weights.min(), bin_weights.max()
    if w_max > w_min:
        bin_weights = (bin_weights - w_min) / (w_max - w_min)
    else:
        bin_weights = np.zeros_like(bin_weights)

    return bin_weights


# ═══════════════════════════════════════════════════════════════════════════
# Stage 5b — Latent diffusion step  (from latent_diffusion.py)
# ═══════════════════════════════════════════════════════════════════════════

def cluster_statistics(Z, centers, labels):
    k         = len(centers)
    n         = len(Z)
    global_var = np.var(Z, axis=0) + 1e-8
    variances  = []
    weights    = []
    for ki in range(k):
        mask = labels == ki
        cnt  = int(np.sum(mask))
        var  = np.var(Z[mask], axis=0) + 1e-8 if cnt > 1 else global_var.copy()
        variances.append(var)
        weights.append(cnt / max(1, n))
    return np.array(variances), np.array(weights)


def latent_diffusion_step(z, centers, variances, temperature,
                          denoising_strength, rng, step_frac):
    """Single temperature-annealed gradient step toward cluster center."""
    ces   = np.array([0.5 * np.sum((z - mu) ** 2 / (var + 1e-10))
                      for mu, var in zip(centers, variances)])
    log_w = -ces / max(temperature, 1e-8)
    log_w -= log_w.max()
    w     = np.exp(log_w)
    w    /= w.sum() + 1e-12

    grad  = np.zeros_like(z)
    for mu, var, wi in zip(centers, variances, w):
        grad += wi * (z - mu) / (var + 1e-10)

    inv_T     = 1.0 / max(temperature, 1e-8)
    step_size = denoising_strength * inv_T / (1.0 + inv_T)
    step_size *= (1.0 - 0.4 * step_frac)

    z_new = z - step_size * grad
    noise = math.sqrt(max(temperature, 1e-8)) * (1.0 - step_frac)
    z_new = z_new + rng.randn(*z.shape) * noise * 0.4
    return z_new


def diffuse_latent_z(z_orig, centers, variances, n_steps, temperature,
                     diffusion_amount, rng):
    """
    Walk z_orig toward its cluster centroid over n_steps with annealed
    temperature, then blend with the original z by diffusion_amount.
    """
    z = z_orig.copy()
    T_start = temperature
    T_end   = max(0.05, temperature * 0.1)

    for t in range(n_steps):
        frac = t / max(1, n_steps - 1)
        T_t  = T_start * ((T_end / max(T_start, 1e-8)) ** frac)
        z    = latent_diffusion_step(z, centers, variances,
                                     T_t, 0.6, rng, frac)

    # Blend: diffusion_amount=0 -> original Z; 1 -> fully diffused Z
    return (1.0 - diffusion_amount) * z_orig + diffusion_amount * z


# ═══════════════════════════════════════════════════════════════════════════
# Stage 6 — Spectral processing helpers
# ═══════════════════════════════════════════════════════════════════════════

def hann_window(n):
    return 0.5 - 0.5 * np.cos(2.0 * np.pi * np.arange(n, dtype=np.float64)
                               / (n - 1))


def spectral_flux(mag):
    return float(np.sum(np.maximum(np.diff(mag), 0.0)))


# ─────────────────────────────────────────────────────────────────────────
# Model: AE-Weighted  (CLI name: "pca" — historical, no SVD inside)
# ─────────────────────────────────────────────────────────────────────────

def diffuse_frame_pca(magnitude, ae_weight, eff_amount, mag_smear, rng):
    """
    ae_weight[f] in [0,1]: 1 = AE failed on this band's freq = unstructured
                            0 = AE reconstructed well        = structured / tonal

    Coherence weight = 1 - ae_weight (so tonal bins get full diffusion).
    """
    n_bins      = len(magnitude)
    rand_phase  = rng.uniform(0.0, 2.0 * np.pi, n_bins)
    coherence_w = 1.0 - ae_weight                    # tonal = high coherence
    attenuation = 1.0 - eff_amount * (coherence_w ** mag_smear)
    mag_wet     = magnitude * attenuation
    return mag_wet * np.exp(1j * rand_phase)


# ─────────────────────────────────────────────────────────────────────────
# Model: AR Smear  (CLI name: "ar")
# ─────────────────────────────────────────────────────────────────────────

def fit_ar_coefficients(frames_mag):
    if len(frames_mag) < 3:
        return np.full(len(frames_mag[0]), 0.5)
    M   = np.stack(frames_mag, axis=1).astype(np.float64)
    y   = M[:, 1:]
    x   = M[:, :-1]
    num = np.sum(x * y, axis=1)
    den = np.sum(x * x, axis=1) + 1e-12
    return np.clip(num / den, 0.0, 1.0)


def diffuse_frame_ar(magnitude, ar_coeff, ae_weight, eff_amount, mag_smear,
                     smear_state, rng):
    """
    IIR magnitude smear, gated by both AR coefficient (temporal sustain)
    AND autoencoder coherence (per-band structure).

    decay[f] = ar_coeff[f] * (1 - ae_weight[f]) * eff_amount * mag_smear

    Bins that are both sustained AND well-reconstructed by the AE get
    the heaviest smear. Bands the AE failed on (high ae_weight) are
    protected. Full phase randomisation on all bins.
    """
    n_bins = len(magnitude)
    if smear_state[0] is None:
        smear_state[0] = magnitude.copy()

    coherence_w = 1.0 - ae_weight
    decay = ar_coeff * coherence_w * eff_amount * mag_smear
    decay = np.clip(decay, 0.0, 0.97)

    smear_state[0] = decay * smear_state[0] + (1.0 - decay) * magnitude
    rand_phase     = rng.uniform(0.0, 2.0 * np.pi, n_bins)
    return smear_state[0] * np.exp(1j * rand_phase)


# ─────────────────────────────────────────────────────────────────────────
# Model: Latent (decoded magnitude as paulstretch-style envelope)
# ─────────────────────────────────────────────────────────────────────────

def build_latent_mag_envelope(model, sr, win_size, z_diffused, mel_fb_win=None):
    """
    Decode a latent vector -> log-mel patch -> invert through mel filterbank
    built at win_size resolution -> linear magnitude envelope.
    """
    if mel_fb_win is None:
        mel_fb_win = build_mel_filterbank(sr, win_size, N_MELS)

    patch_norm   = model.decode(z_diffused.reshape(1, -1))[0]
    patch_logmel = patch_norm * model._norm_sigma + model._norm_mu
    patch_logmel = patch_logmel.reshape(N_MELS, MEL_FRAMES)
    mel_energy   = np.mean(patch_logmel, axis=1)
    mel_energy   = np.exp(mel_energy)
    mel_energy   = np.maximum(mel_energy, 1e-10)
    fft_envelope = mel_fb_win.T.dot(mel_energy)
    fft_envelope = np.maximum(fft_envelope, 1e-10)
    return fft_envelope


def diffuse_frame_latent(magnitude, fft_envelope, eff_amount, rng):
    """
    Blend the frame's own magnitude with the decoded latent envelope,
    then randomise all phases.
    """
    n_bins    = len(magnitude)
    rand_phase = rng.uniform(0.0, 2.0 * np.pi, n_bins)
    orig_energy   = np.mean(magnitude) + 1e-12
    latent_energy = np.mean(fft_envelope) + 1e-12
    env_scaled    = fft_envelope * (orig_energy / latent_energy)
    mag_wet       = (1.0 - eff_amount) * magnitude + eff_amount * env_scaled
    return mag_wet * np.exp(1j * rand_phase)


# ═══════════════════════════════════════════════════════════════════════════
# Stage 7 — Core paulstretch-style loop (no time stretch)
# ═══════════════════════════════════════════════════════════════════════════

def process_channel(signal, sr, model, ae_weights, events, Z,
                    centers, variances, mel_fb, n_fft_bins,
                    model_name, diffusion_amount, diffusion_steps,
                    mag_smear, preserve_transients, win_size, hop_size,
                    temperature, rng, debug, ch):

    signal    = signal.astype(np.float64)
    n_samples = len(signal)
    win       = hann_window(win_size)

    # Reflect-pad
    pad = win_size
    x   = np.pad(signal, (pad, pad), mode="reflect")

    # ── Pass 1: collect all frame magnitudes ──────────────────────────
    mag_frames      = []
    flux_frames     = []
    frame_positions = []
    pos = 0
    while pos + win_size <= len(x):
        frame = x[pos:pos + win_size] * win
        mag   = np.abs(np.fft.rfft(frame))
        mag_frames.append(mag)
        flux_frames.append(spectral_flux(mag))
        frame_positions.append(pos)
        pos += hop_size

    n_frames = len(mag_frames)
    if n_frames == 0:
        return signal

    flux_arr = np.array(flux_frames)
    flux_thr = np.percentile(flux_arr, 75)

    fit_idx = np.linspace(0, n_frames - 1, min(n_frames, 512), dtype=int)

    # ── Model-specific setup ──────────────────────────────────────────
    if model_name == "pca":
        if debug and ch == 0:
            print("  [AE-Weighted] AE weight mean=%.3f  max=%.3f"
                  % (ae_weights.mean(), ae_weights.max()))

    elif model_name == "ar":
        sampled  = [mag_frames[i] for i in fit_idx]
        ar_coeff = fit_ar_coefficients(sampled)
        smear_st = [None]
        if debug and ch == 0:
            print("  [AR Smear]  ar_coeff mean=%.3f  max=%.3f"
                  % (ar_coeff.mean(), ar_coeff.max()))
            print("  [AR Smear]  AE weight mean=%.3f  max=%.3f"
                  % (ae_weights.mean(), ae_weights.max()))

    elif model_name == "latent":
        rng_lat = np.random.RandomState(rng.randint(0, 2**31))
        mel_fb_lat = build_mel_filterbank(sr, win_size, N_MELS)
        latent_envelopes = []
        for i, ev in enumerate(events):
            z_orig    = Z[i]
            z_diff    = diffuse_latent_z(z_orig, centers, variances,
                                         diffusion_steps, temperature,
                                         diffusion_amount, rng_lat)
            env       = build_latent_mag_envelope(model, sr, win_size,
                                                     z_diff, mel_fb_lat)
            latent_envelopes.append(env)
        if debug and ch == 0:
            print("  [Latent] %d events -> diffused Z -> %d envelopes"
                  % (len(events), len(latent_envelopes)))

    # ── COLA normalisation ────────────────────────────────────────────
    cola = np.zeros(len(x))
    for pos in frame_positions:
        cola[pos:pos + win_size] += win ** 2
    cola = np.maximum(cola, 1e-12)

    # ── Pass 2: overlap-add wet signal ───────────────────────────────
    y_wet = np.zeros(len(x))

    for fi, pos in enumerate(frame_positions):
        mag = mag_frames[fi]

        eff_amount = diffusion_amount
        if preserve_transients and flux_arr[fi] > flux_thr:
            excess     = flux_arr[fi] / (flux_thr + 1e-12)
            eff_amount = diffusion_amount / max(1.0, excess)

        if model_name == "pca":
            new_spec = diffuse_frame_pca(mag, ae_weights, eff_amount,
                                         mag_smear, rng)

        elif model_name == "ar":
            new_spec = diffuse_frame_ar(mag, ar_coeff, ae_weights,
                                        eff_amount, mag_smear, smear_st, rng)

        elif model_name == "latent":
            t_frame = (pos - pad) / sr
            ev_idx  = 0
            for j, ev in enumerate(events):
                if float(ev["start_time"]) <= t_frame < float(ev["end_time"]):
                    ev_idx = j
                    break
                if t_frame < float(ev["start_time"]):
                    ev_idx = j
                    break
            ev_idx  = min(ev_idx, len(latent_envelopes) - 1)
            new_spec = diffuse_frame_latent(mag, latent_envelopes[ev_idx],
                                            eff_amount, rng)

        out_frame = np.fft.irfft(new_spec, n=win_size) * win
        y_wet[pos:pos + win_size] += out_frame

    y_wet /= cola

    # ── Dry/wet crossfade ─────────────────────────────────────────────
    y_out = (1.0 - diffusion_amount) * x + diffusion_amount * y_wet
    y_out = y_out[pad:pad + n_samples]

    if debug and ch == 0:
        sig_rms  = float(np.sqrt(np.mean(signal ** 2))) + 1e-12
        diff_rms = float(np.sqrt(np.mean((y_out - signal) ** 2)))
        print("  [ch%d] Signal diff ratio: %.4f  (0=identical  1=unrelated)"
              % (ch, diff_rms / sig_rms))

    return y_out


# ═══════════════════════════════════════════════════════════════════════════
# Entry point
# ═══════════════════════════════════════════════════════════════════════════

def main():
    parser = argparse.ArgumentParser(
        description="Latent Spectral Diffusion Engine v6.0 -- Praat AudioTools"
    )
    parser.add_argument("input_wav")
    parser.add_argument("output_wav")
    parser.add_argument("--model",              default="pca",
                        choices=["pca", "ar", "latent"])
    parser.add_argument("--diffusion-amount",   type=float, default=0.7)
    parser.add_argument("--diffusion-steps",    type=int,   default=30,
                        help="latent: gradient steps; pca/ar: reserved")
    parser.add_argument("--window-size",        type=int,   default=8192)
    parser.add_argument("--hop-size",           type=int,   default=2048)
    parser.add_argument("--mag-smear",          type=float, default=1.0)
    parser.add_argument("--latent-size",        type=int,   default=8,
                        help="Autoencoder bottleneck dimension")
    parser.add_argument("--train-steps",        type=int,   default=150,
                        help="Autoencoder training iterations")
    parser.add_argument("--n-clusters",         type=int,   default=4,
                        help="K-means++ clusters in latent space")
    parser.add_argument("--temperature",        type=float, default=1.0,
                        help="Latent diffusion temperature")
    parser.add_argument("--preserve-transients", action="store_true")
    parser.add_argument("--seed",               type=int,   default=42)
    parser.add_argument("--status-file",        default=None)
    parser.add_argument("--debug",              action="store_true")
    args = parser.parse_args()

    for pkg in ["numpy", "soundfile"]:
        try:
            __import__(pkg)
        except ImportError:
            print("ERROR: Missing package: " + pkg, file=sys.stderr)
            sys.exit(1)

    import soundfile as sf

    diffusion_amount = float(np.clip(args.diffusion_amount, 0.0, 1.0))
    diffusion_steps  = max(1,  min(200, args.diffusion_steps))
    mag_smear        = max(0.0, args.mag_smear)
    win_size         = max(256, args.window_size)
    hop_size         = max(1,   min(args.hop_size, win_size // 2))
    latent_size      = max(2,   min(32,  args.latent_size))
    train_steps      = max(10,  min(500, args.train_steps))
    n_clusters       = max(2,   min(8,   args.n_clusters))
    temperature      = max(0.05, args.temperature)

    audio, sr = sf.read(args.input_wav, always_2d=True)
    audio = audio.astype(np.float64)
    n_samples, n_channels = audio.shape

    if args.debug:
        print("  Audio: %.2fs  SR=%d  ch=%d" % (n_samples / sr, sr, n_channels))
        print("  Window: %d smp (%.1f ms)  Hop: %d smp"
              % (win_size, win_size / sr * 1000, hop_size))
        print("  Model: %s  amount=%.2f  latent=%d  train=%d  clusters=%d"
              % (args.model, diffusion_amount, latent_size, train_steps, n_clusters))

    # ── Stage 1: Segment ─────────────────────────────────────────────
    audio_mono = audio[:, 0]
    if args.debug:
        print("  [Stage 1] Segmenting audio...")
    events = segment_events(audio_mono, sr)
    if args.debug:
        print("  [Stage 1] Events: %d  (%.0f ms mean dur)"
              % (len(events),
                 1000 * np.mean([float(e["end_time"]) - float(e["start_time"])
                                 for e in events])))

    # ── Stage 2: Mel patches ─────────────────────────────────────────
    if args.debug:
        print("  [Stage 2] Extracting log-Mel patches...")
    patches = extract_mel_patches(audio_mono, sr, events)
    if args.debug:
        print("  [Stage 2] Patch matrix: %s" % str(patches.shape))

    # ── Stage 3: Train autoencoder ───────────────────────────────────
    if args.debug:
        print("  [Stage 3] Training autoencoder (%d steps, latent=%d)..."
              % (train_steps, latent_size))
    model, losses = train_autoencoder(patches, latent_size, train_steps,
                                      args.seed, debug=args.debug)

    # ── Stage 4: Encode → Z, event errs, per-band errs ──────────────
    # v6.0: encode_events now also returns per-event per-mel-band errors,
    # which Stage 5a uses to build genuinely frequency-dependent weights.
    if args.debug:
        print("  [Stage 4] Encoding events...")
    Z, event_errs, band_errs = encode_events(model, patches)
    if args.debug:
        print("  [Stage 4] Z shape: %s  mean event err: %.4f  mean band err: %.4f"
              % (str(Z.shape), float(np.mean(event_errs)), float(np.mean(band_errs))))

    # ── Stage 4b: Cluster ─────────────────────────────────────────────
    k_actual = min(n_clusters, len(events) - 1)
    if args.debug:
        print("  [Stage 4b] K-means++ (%d clusters)..." % k_actual)
    centers, labels = kmeans_plus_plus(Z, k_actual, seed=args.seed)
    variances, _    = cluster_statistics(Z, centers, labels)
    if args.debug:
        for ki in range(k_actual):
            cnt = int(np.sum(labels == ki))
            print("    Cluster %d: %d events (%.0f%%)"
                  % (ki, cnt, 100.0 * cnt / max(1, len(events))))

    # ── Stage 5: AE band-error → per-bin weights (v6.0 honest version) ──
    n_fft_bins = win_size // 2 + 1
    mel_fb_main = build_mel_filterbank(sr, 1024, N_MELS)   # same as patches
    mel_fb_win  = build_mel_filterbank(sr, win_size, N_MELS)  # for bin weights

    ae_weights = ae_error_to_bin_weights(
        band_errs, events, mel_fb_win, n_fft_bins, sr, n_samples, win_size)

    if args.debug:
        # Report frequency-axis statistics so the user can see that the
        # weights now genuinely vary across frequency in a signal-dependent
        # way (not just from filterbank geometry).
        nz = ae_weights > 0.5
        print("  [Stage 5] AE bin weights: mean=%.3f  max=%.3f  std=%.3f  "
              "high-weight bins=%d/%d (%.1f%%)"
              % (ae_weights.mean(), ae_weights.max(), ae_weights.std(),
                 int(nz.sum()), len(ae_weights),
                 100.0 * float(nz.sum()) / max(1, len(ae_weights))))

    # ── Stage 6: Process channels ─────────────────────────────────────
    output_channels = []
    for ch in range(n_channels):
        rng_ch = np.random.RandomState(args.seed + 1000 * ch)
        sig_out = process_channel(
            signal           = audio[:, ch],
            sr               = sr,
            model            = model,
            ae_weights       = ae_weights,
            events           = events,
            Z                = Z,
            centers          = centers,
            variances        = variances,
            mel_fb           = mel_fb_main,
            n_fft_bins       = n_fft_bins,
            model_name       = args.model,
            diffusion_amount = diffusion_amount,
            diffusion_steps  = diffusion_steps,
            mag_smear        = mag_smear,
            preserve_transients = args.preserve_transients,
            win_size         = win_size,
            hop_size         = hop_size,
            temperature      = temperature,
            rng              = rng_ch,
            debug            = args.debug,
            ch               = ch,
        )
        output_channels.append(sig_out)

    output = np.stack(output_channels, axis=1)

    # RMS-match, capped at 3x
    for ch in range(n_channels):
        rms_in  = float(np.sqrt(np.mean(audio[:, ch] ** 2))) + 1e-12
        rms_out = float(np.sqrt(np.mean(output[:, ch] ** 2))) + 1e-12
        gain    = np.clip(rms_in / rms_out, 0.1, 3.0)
        output[:, ch] *= gain

    save_audio(args.output_wav, output, sr)

    if args.status_file:
        with open(args.status_file, "w", encoding="utf-8") as f:
            f.write("ok")

    print("Latent Spectral Diffusion OK | v6.0 | model=%s | amount=%.3f | "
          "latent=%d | events=%d | clusters=%d | "
          "win=%d | hop=%d | sr=%d | ch=%d"
          % (args.model, diffusion_amount, latent_size, len(events),
             k_actual, win_size, hop_size, sr, n_channels))


if __name__ == "__main__":
    main()
