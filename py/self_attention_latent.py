"""
self_attention_latent.py — Self-Attention Latent Navigation Engine

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University
Version: 1.6 (2026)

Called by SelfAttentionLatent.praat — not run directly.

Usage:
    python self_attention_latent.py input.wav events.csv output.wav [options]

Pipeline:
    Stage 1 — Load audio + events; encode events → latent μᵢ (VAE, NumPy only)
    Stage 2 — Build self-attention matrix A ∈ ℝᴺˣᴺ (multi-head, NumPy only)
    Stage 3 — Generate navigation plan in memory (list of dicts, no CSV)
    Stage 4 — Execute plan:
               for each step:
                 • compute latent target (drift/mutate/return/settle)
                 • select K nearest neighbors
                 • mixing weight: w_j ∝ (1/dist_j^p) * (A[i,j]^q)
                 • mix waveforms → crossfade → append
    Stage 5 — Time-normalize, loudness-compensate, write output.wav
              Delete events.csv and any temp files
              Only output.wav remains

No PyTorch. No TensorFlow. No sklearn. No external plan file.
Dependencies: numpy, soundfile (scipy optional, unused here)

Changelog v1.6 (dual-trajectory attentional counterpoint):
    - --nav_mode linked (default; execute_plan unchanged, bit-identical to
      v1.5.1) | independent | competitive | divergence_convergence: two latent
      trajectories over one phase plan (own position, velocity, RNG, context,
      candidates, anchors, render), written as a two-voice stereo file.
    - --divergence, --competition, --dual_routing per_channel|reference,
      --viz_tsv <prefix> (steps / timeline / events TSV), @argsfile.
    - Dual timeline: no whole-file resize; slots sum exactly to the target.
      Competitive and D/C share one set of slot boundaries (step i of both
      voices sounds at the same time); Independent keeps a free rhythm per
      voice. Inter-voice statistics (overlap, same dominant, separation,
      trend, convergence) are time-weighted over the sounding timeline.
    - Stats: every v1.5.1 key unchanged and first; dual keys appended.
    - Review round 2: a step whose mix is more than 2x too long for its slot
      reads a moving window (one read cursor per voice and dominant event)
      instead of always its opening; read_coverage_* reports how much of the
      dominant events was played (and *_start_only what round 1 would have).

Changelog v1.5 (review round 1, engine side):
    - --time_offset: event times are on the Praat Sound's timeline, the WAV
      starts at 0. Events outside the audio now abort with a message instead
      of producing silence. (Praat must pass the Sound's start time.)
    - Phase-aware mixing (_mix_aligned): neighbours are aligned to the
      dominant clip by lag (+-10 ms) and polarity when correlated, and each
      step's mix is level-matched to sum(w_j * rms_j). --mix_align off gives
      the v1.4 plain sum.
    - _pvoc_stretch rewritten: centred frames (no head attenuation), phase
      reset on the first frame, adaptive window so clips < 2048 samples are
      really stretched, channel-coherent phase, +-1-bin phase locking.
Changelog v1.5.1 (review round 2: attacks):
    - _pvoc_stretch carries the length change on a piecewise-linear time map.
      Every detected attack keeps a slope-1, phase-reset zone covering all
      frames that see it, and is anchored at round(onset * target/n), so it
      is reproduced as a copy of the source at its proportionally scaled time
      (v1.5 lost an impulse at 98 % of a clip by up to 52.7 dB, and shifted
      internal attacks by tens of ms). Near a clip edge the zone runs to the
      edge and the edge moves instead (quiet lead-in padded/trimmed; tail
      padded with silence or trimmed under a 32-sample fade).
    - Clip end: slope 1 without phase reset, so the last samples keep their
      level without a phase discontinuity in sustained sound.
    - Window ~46 ms at the clip's sample rate (was a fixed 2048 samples, i.e.
      128 ms at 16 kHz), at most half the input and output length, halved
      (to 256 min) when attacks are closer together than a window.
    - Attack detector: peak over 3 blocks vs RMS of the 15 before; the clip's
      own start is not an attack; onset refined to 20 % of the attack peak.
    - _resize / _pvoc_stretch take the sample rate; execute_plan passes it.
    - Crossfade law follows the tail/head correlation (equal-power when
      uncorrelated, equal-gain when coherent): no +3 dB bump on coherent joins.
    - Stats: aligned clips, polarity flips, mix gain, crossfade correlation,
      raw render length and the final resize ratio.

Changelog v1.4:
    - Corrected VAE reparameterisation / KL gradients and latent-size scaling.
    - Replaced independent random Q/K projections with a shared orthogonal
      projection so attention is driven by latent similarity, not arbitrary
      random bilinear geometry.
    - Attention is now indexed by the current latent context event, and return
      anchors are selected at execution time from attention-related drift states.
    - Fixed overlap crossfade: the old tail and new head are now actually mixed.
    - Varispeed now uses FFT resampling at every ratio; pitch-preserve always uses
      the phase vocoder. Legacy preserve_f0/preserve_spectral_envelope aliases map
      to preserve_pitch.
    - Preserves source channel count; analysis uses strongest-RMS source channel.
    - Writes FLOAT WAV, reports effective head count and attention QC metrics.

Changelog v1.3:
    Wired three exposed knobs that had no audible effect (audio change):
      - pitch_mode: was plumbed through but never used in execution (off /
        preserve_f0 / preserve_spectral_envelope produced identical audio).
        Now gates the length-change resampler via _resize(): 'off' = varispeed
        _resample (pitch tracks speed); 'preserve_*' = _pvoc_stretch (pitch
        preserved). The two preserve_* modes currently coincide (both pvoc,
        which preserves pitch and envelope in this time-stretch-only path).
      - Duration_scale: a uniform per-segment scale was cancelled by the final
        time-normalize. Now scales the render TARGET, so it sets output length
        (pitch-preserved when pitch_mode != off); per-segment jitter is kept
        for internal rhythm.
      - Energy_scale: was applied per-segment then normalized away. Now applied
        as a post-normalization master gain (peak-guarded); per-segment jitter
        kept for internal dynamics.

Changelog v1.2:
    Cosmetic-only change for AudioTools v1.2 release.
    - _rms_compensate: removed unreachable "loudness" alias. The
      Praat front-end only ever passes "none", "peak", or "rms"
      (the only three options exposed in its optionmenu), so the
      `elif mode in ("rms", "loudness")` branch's "loudness" arm
      was dead code. Simplified to `elif mode == "rms"`.
      Behavior and output are bit-identical.
"""

import sys
import os
import csv
import math

# ─────────────────────────────────────────────────────────────────────────────
# Constants
# ─────────────────────────────────────────────────────────────────────────────
N_MELS      = 64
MEL_FRAMES  = 32
XFADE_SEC   = 0.012   # crossfade length between segments (seconds)
TEMP_PREFIX = "temp_sal_"   # prefix Praat uses for temp files it creates


# ═══════════════════════════════════════════════════════════════════════════
# Utilities
# ═══════════════════════════════════════════════════════════════════════════

def check_deps():
    missing = []
    for pkg in ["numpy", "soundfile"]:
        try:
            __import__(pkg)
        except ImportError:
            missing.append(pkg)
    if missing:
        print("ERROR: missing packages: " + ", ".join(missing), file=sys.stderr)
        print("pip install " + " ".join(missing), file=sys.stderr)
        sys.exit(1)


def load_events(path):
    events = []
    with open(path, "r") as f:
        header = [h.strip() for h in f.readline().strip().split(",")]
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
# Stage 1a — Log-Mel Patch Extraction
# ═══════════════════════════════════════════════════════════════════════════

def _mel_filterbank(sr, n_fft, n_mels):
    import numpy as np
    def hz2mel(h): return 2595.0 * np.log10(1.0 + h / 700.0)
    def mel2hz(m): return 700.0 * (10.0 ** (m / 2595.0) - 1.0)
    n_bins = n_fft // 2 + 1
    pts    = mel2hz(np.linspace(hz2mel(20), hz2mel(sr / 2), n_mels + 2))
    bins   = np.clip(np.floor((n_fft + 1) * pts / sr).astype(int), 0, n_bins - 1)
    fb     = np.zeros((n_mels, n_bins))
    k_all  = np.arange(n_bins)
    for m in range(1, n_mels + 1):
        lo, ctr, hi = bins[m-1], bins[m], bins[m+1]
        if ctr > lo:
            mask = (k_all >= lo) & (k_all < ctr)
            fb[m-1, mask] = (k_all[mask] - lo) / (ctr - lo)
        if hi > ctr:
            mask = (k_all >= ctr) & (k_all < hi)
            fb[m-1, mask] = (hi - k_all[mask]) / (hi - ctr)
    return fb


def extract_patches(audio_mono, sr, events):
    import numpy as np
    n_fft  = 2048
    hop    = 512
    win    = np.hanning(n_fft)
    fb     = _mel_filterbank(sr, n_fft, N_MELS)
    N      = len(audio_mono)
    out    = []
    for ev in events:
        s = max(0, min(int(float(ev["start_time"]) * sr), N))
        e = max(s + 1, min(int(float(ev["end_time"]) * sr), N))
        seg     = audio_mono[s:e]
        n_fr    = max(1, (len(seg) - n_fft) // hop + 1)
        mel     = np.zeros((N_MELS, n_fr))
        for fi in range(n_fr):
            st = fi * hop
            fr = seg[st:st + n_fft]
            if len(fr) < n_fft:
                fr = np.pad(fr, (0, n_fft - len(fr)))
            mel[:, fi] = np.log(fb.dot(np.abs(np.fft.rfft(fr * win)) ** 2) + 1e-10)
        if n_fr >= MEL_FRAMES:
            off   = (n_fr - MEL_FRAMES) // 2
            patch = mel[:, off:off + MEL_FRAMES]
        else:
            patch = np.zeros((N_MELS, MEL_FRAMES))
            off   = (MEL_FRAMES - n_fr) // 2
            patch[:, off:off + n_fr] = mel
            for pi in range(off):           patch[:, pi]  = mel[:, 0]
            for pi in range(off + n_fr, MEL_FRAMES): patch[:, pi] = mel[:, -1]
        out.append(patch.flatten())
    return np.array(out, dtype=np.float64)


# ═══════════════════════════════════════════════════════════════════════════
# Stage 1b — Lightweight VAE (pure NumPy)
# ═══════════════════════════════════════════════════════════════════════════

class _VAE:
    def __init__(self, in_dim, h_dim, z_dim, seed):
        import numpy as np
        rng = np.random.RandomState(seed)
        def he(a, b): return rng.randn(a, b) * np.sqrt(2.0 / (a + b))
        self.We = he(in_dim, h_dim);  self.be = np.zeros(h_dim)
        self.Wm = he(h_dim,  z_dim);  self.bm = np.zeros(z_dim)
        self.Wv = he(h_dim,  z_dim);  self.bv = np.zeros(z_dim)
        self.Wd = he(z_dim,  h_dim);  self.bd = np.zeros(h_dim)
        self.Wo = he(h_dim,  in_dim); self.bo = np.zeros(in_dim)
        self.params = [self.We, self.be, self.Wm, self.bm,
                       self.Wv, self.bv, self.Wd, self.bd,
                       self.Wo, self.bo]
        self.t = 0
        self.m = [np.zeros_like(p) for p in self.params]
        self.v = [np.zeros_like(p) for p in self.params]
        self.rng = rng
        self.in_dim = in_dim

    def _relu(self, x):
        import numpy as np; return np.maximum(0, x)

    def encode(self, X):
        self._h = self._relu(X.dot(self.We) + self.be)
        mu = self._h.dot(self.Wm) + self.bm
        lv = self._h.dot(self.Wv) + self.bv
        return mu, lv

    def step(self, X, lr, beta):
        import numpy as np
        B = X.shape[0]
        Xn = X + 0.3 * self.rng.randn(*X.shape)
        mu, lv = self.encode(Xn)
        zdim = max(1, mu.shape[1])

        # Stable reparameterisation.  The same clipped log-variance is used in
        # sampling and KL so the forward objective and backward pass agree.
        lv_c = np.clip(lv, -8.0, 8.0)
        lv_mask = ((lv >= -8.0) & (lv <= 8.0)).astype(np.float64)
        exp_lv = np.exp(lv_c)
        std = np.sqrt(exp_lv)
        eps_z = self.rng.randn(*std.shape)
        Z = mu + std * eps_z

        h2  = self._relu(Z.dot(self.Wd) + self.bd)
        rec = h2.dot(self.Wo) + self.bo
        diff = rec - X
        rl = np.mean(diff ** 2)
        kl = 0.5 * np.mean(mu**2 + exp_lv - lv_c - 1.0)
        loss = rl + beta * kl

        # backward
        dout = 2 * diff / (B * self.in_dim)
        dWo  = h2.T.dot(dout);             dbo = np.sum(dout, 0)
        dh2  = dout.dot(self.Wo.T) * (h2 > 0)
        dWd  = Z.T.dot(dh2);               dbd = np.sum(dh2, 0)
        dZ   = dh2.dot(self.Wd.T)

        # KL is a mean over batch AND latent dimensions.  Reparameterisation
        # derivative dZ/dlv = 0.5 * std * eps_z.
        dmu = dZ + beta * mu / (B * zdim)
        dlv = (dZ * std * eps_z * 0.5 +
               beta * 0.5 * (exp_lv - 1.0) / (B * zdim)) * lv_mask

        dWm  = self._h.T.dot(dmu);         dbm = np.sum(dmu, 0)
        dWv  = self._h.T.dot(dlv);         dbv = np.sum(dlv, 0)
        dh1  = (dmu.dot(self.Wm.T) + dlv.dot(self.Wv.T)) * (self._h > 0)
        dWe  = Xn.T.dot(dh1);              dbe = np.sum(dh1, 0)
        grads = [dWe, dbe, dWm, dbm, dWv, dbv, dWd, dbd, dWo, dbo]

        self.t += 1
        b1, b2, eps = 0.9, 0.999, 1e-8
        for i, (p, g) in enumerate(zip(self.params, grads)):
            self.m[i] = b1*self.m[i] + (1-b1)*g
            self.v[i] = b2*self.v[i] + (1-b2)*g**2
            mh = self.m[i] / (1 - b1**self.t)
            vh = self.v[i] / (1 - b2**self.t)
            p -= lr * mh / (np.sqrt(vh) + eps)
        return loss





def train_vae(patches, z_dim, n_iter, seed):
    import numpy as np
    N, D   = patches.shape
    h_dim  = max(z_dim * 2, min(256, int(np.sqrt(D * z_dim))))
    mu_n   = patches.mean(0); sig_n = patches.std(0) + 1e-8
    X      = (patches - mu_n) / sig_n
    model  = _VAE(D, h_dim, z_dim, seed)
    lr0    = 0.003
    losses = []
    for i in range(n_iter):
        lr   = lr0 * (1.0 - 0.4 * i / n_iter)
        loss = model.step(X, lr, 0.05)
        losses.append(float(loss))
    model._mu_n  = mu_n
    model._sig_n = sig_n
    return model, losses


def encode(model, patches):
    import numpy as np
    X      = (patches - model._mu_n) / model._sig_n
    mu, _  = model.encode(X)
    return mu   # (N, z_dim)


# ═══════════════════════════════════════════════════════════════════════════
# Stage 2 — Self-Attention Matrix (pure NumPy)
# ═══════════════════════════════════════════════════════════════════════════

def effective_head_count(d, requested):
    """Clamp requested heads to the largest <= requested that divides d."""
    h = max(1, min(int(requested), int(d)))
    while d % h != 0 and h > 1:
        h -= 1
    return h


def build_attention(Z, n_heads=4, seed=42):
    """
    Parameter-free multi-head self-attention over latent vectors.

    A shared seeded orthogonal projection is used for Q and K.  Sharing the
    projection is crucial: attention then measures latent similarity rather
    than an arbitrary bilinear relation produced by independent random Wq/Wk.
    The orthogonal rotation keeps the full-space inner-product geometry while
    the head split provides multiple latent subspace views.

    Returns (A, mean_entropy_nats, effective_heads).
    """
    import numpy as np
    N, d = Z.shape
    n_heads = effective_head_count(d, n_heads)
    dh = d // n_heads

    mu_z  = Z.mean(0, keepdims=True)
    sig_z = Z.std(0, keepdims=True) + 1e-8
    Zn = (Z - mu_z) / sig_z
    Zr = Zn + Z / (np.max(np.abs(Z)) + 1e-8)

    # Shared orthogonal projection: Q == K in the rotated latent space.
    rng = np.random.RandomState(seed)
    R = rng.randn(d, d)
    W, _ = np.linalg.qr(R)
    P = Zr.dot(W)

    A_sum = np.zeros((N, N), dtype=np.float64)
    inv = 1.0 / np.sqrt(dh)
    for h in range(n_heads):
        s, e = h * dh, (h + 1) * dh
        H = P[:, s:e]
        scores = H.dot(H.T) * inv
        scores -= scores.max(1, keepdims=True)
        exp_s = np.exp(scores)
        A_sum += exp_s / (exp_s.sum(1, keepdims=True) + 1e-12)

    A = A_sum / n_heads
    A = A / (A.sum(1, keepdims=True) + 1e-12)
    entropy = float(-np.sum(A * np.log(A + 1e-12), axis=1).mean())
    return A, entropy, n_heads





# ═══════════════════════════════════════════════════════════════════════════
# Stage 3 — Navigation Plan (in memory only, no CSV)
# ═══════════════════════════════════════════════════════════════════════════

def generate_plan(Z, A, n_steps=72, seed=42,
                  dur_scale=1.0, dur_jitter=0.0,
                  eng_scale=1.0, eng_jitter=0.0):
    """
    Deterministic latent navigation plan as List[Dict].
    No file is written — plan lives in memory only.

    Phase layout  (spec minimums in parentheses):
        drift  33%  (≥15%)  — geometry dominant, α=0.90
        mutate 33%  (≥15%)  — attention grows, α ramps 0.70→0.30
        return 25%  (≥10%)  — attention dominant, anchor via A cosine
        settle  9%  (≥10%)  — geometry re-dominant, α=0.90

    Smoothness constraints enforced every step:
        |Δ step_size|   ≤ 0.15
        |Δ temperature| ≤ 0.20
        |Δ k_neighbors| ≤ 2

    Mixing weight formula (used in Stage 4):
        w_j ∝ (1/dist_j^p) * (A[i,j]^q)
    α stored per step as '_alpha'; p/q computed from α at execution time.
    """
    import numpy as np, random
    rng = random.Random(seed)
    N   = Z.shape[0]
    n_steps = max(8, min(500, n_steps))

    DRIFT_END  = 0.333
    MUTATE_END = 0.667
    RETURN_END = 0.917

    def lerp(a, b, t):
        return a + (b - a) * float(np.clip(t, 0, 1))

    drift_idxs = [i for i in range(n_steps)
                  if i / max(1, n_steps - 1) < DRIFT_END]

    plan   = []
    p_sz   = 0.05
    p_tmp  = 0.05
    p_k    = 2

    for i in range(n_steps):
        frac = i / max(1, n_steps - 1)

        # ── Phase parameters ────────────────────────────────────────────────
        if frac < DRIFT_END:
            ph = "drift"
            t  = frac / DRIFT_END
            tsz, ttmp, tk = lerp(0.05,0.25,t), lerp(0.05,0.20,t), int(round(lerp(2,4,t)))
            alpha, r_str, anchor = 0.90, 0.0, -1

        elif frac < MUTATE_END:
            ph = "mutate"
            t  = (frac - DRIFT_END) / (MUTATE_END - DRIFT_END)
            tsz, ttmp, tk = lerp(0.30,0.70,t), lerp(0.40,0.80,t), int(round(lerp(4,8,t)))
            alpha, r_str, anchor = lerp(0.70,0.30,t), 0.0, -1

        elif frac < RETURN_END:
            ph = "return"
            t  = (frac - MUTATE_END) / (RETURN_END - MUTATE_END)
            tsz, ttmp, tk = lerp(0.30,0.10,t), lerp(0.20,0.10,t), int(round(lerp(4,2,t)))
            alpha  = lerp(0.20, 0.35, t)
            r_str  = lerp(0.50, 0.80, t)
            # Runtime attention anchor: execution selects the previously visited
            # drift state most related to the CURRENT latent context.
            anchor = -2

        else:
            ph = "settle"
            t  = (frac - RETURN_END) / max(1e-9, 1.0 - RETURN_END)
            tsz, ttmp, tk = lerp(0.20,0.05,t), lerp(0.15,0.05,t), int(round(lerp(3,2,t)))
            alpha, r_str, anchor = 0.90, 0.0, -1

        # ── Smoothness clamp ────────────────────────────────────────────────
        sz  = float(np.clip(tsz,  p_sz  - 0.15, p_sz  + 0.15))
        tmp = float(np.clip(ttmp, p_tmp - 0.20, p_tmp + 0.20))
        k   = int(np.clip(tk, p_k - 2, p_k + 2))
        k   = max(2, min(8, min(k, N)))
        p_sz, p_tmp, p_k = sz, tmp, k

        # ── Per-step jitter ─────────────────────────────────────────────────
        sdur = float(np.clip(dur_scale * (1 + rng.uniform(-dur_jitter, dur_jitter)
                                          if dur_jitter > 0 else 1), 0.50, 1.50))
        seng = float(np.clip(eng_scale * (1 + rng.uniform(-eng_jitter, eng_jitter)
                                          if eng_jitter > 0 else 1), 0.50, 1.50))

        plan.append({
            "step_index":             i,
            "relative_time":          round(i / max(1, n_steps - 1), 6),
            "mode":                   ph,
            "step_size":              round(sz,  4),
            "temperature":            round(tmp, 4),
            "k_neighbors":            k,
            "return_anchor_step":     anchor,
            "return_strength":        round(float(r_str), 4),
            "segment_duration_scale": round(sdur, 4),
            "segment_energy_scale":   round(seng, 4),
            "_alpha":                 round(float(alpha), 4),
        })

    if plan:
        plan[0]["relative_time"]  = 0.0
        plan[-1]["relative_time"] = 1.0
    return plan


# ═══════════════════════════════════════════════════════════════════════════
# Stage 4 — Execution
# ═══════════════════════════════════════════════════════════════════════════

def _extract_clips(audio, events, sr):
    """Return list of float32 arrays (samples,) or (samples, ch), one per event.
    Preserves original channel count so mixing does not lose stereo information."""
    import numpy as np
    N = audio.shape[0] if audio.ndim == 2 else len(audio)
    clips = []
    for ev in events:
        s = max(0, min(int(float(ev["start_time"]) * sr), N - 1))
        e = max(s + 1, min(int(float(ev["end_time"]) * sr), N))
        clips.append(audio[s:e].astype(np.float32))
    return clips


def _sinc_resample(clip, target_len):
    """
    Fast high-quality resampling using FFT-based sinc interpolation.
    Preserves high frequencies far better than np.interp.
    Used for ratio changes within 0.7–1.4x where pvoc is overkill.
    """
    import numpy as np
    n = len(clip)
    if n == target_len:
        return clip.copy().astype(np.float32)
    # FFT resample: zero-pad or truncate spectrum, then IFFT
    X = np.fft.rfft(clip.astype(np.float64))
    if target_len > n:
        # upsample — pad spectrum with zeros
        X_new = np.zeros(target_len // 2 + 1, dtype=np.complex128)
        X_new[:len(X)] = X
    else:
        # downsample — truncate spectrum (anti-alias built in)
        X_new = X[:target_len // 2 + 1]
    out = np.fft.irfft(X_new, n=target_len)
    # scale to preserve amplitude
    out *= target_len / n
    return out.astype(np.float32)


def _resample(clip, target_len):
    """True varispeed resampling at every ratio (pitch follows speed)."""
    if len(clip) == target_len:
        return clip.copy().astype("float32")
    return _sinc_resample(clip, target_len)





def _clip_attacks(x, sr_blocks=32, rise_db=15.0, min_gap=480):
    """Sharp attacks inside a clip (x: (n, C)), independent of pitch.

    On a 32-sample block grid: peak |x| over the next ~3 blocks against the
    RMS of the ~15 blocks before (1 block gap). An attack needs a rise of
    >= 15 dB, a peak of at least half the local maximum (so beating and swells
    do not qualify) and a level within 50 dB of the clip peak. The position
    is refined to the first sample reaching 20 % of the attack's peak.
    Returns (positions, rise_dB), keeping the stronger of two attacks closer
    than min_gap."""
    import numpy as np
    n, C = x.shape
    h = sr_blocks
    nb = n // h
    if nb < 8:
        return np.zeros(0, dtype=np.int64), np.zeros(0)
    ax = np.max(np.abs(x[:nb * h]), axis=1).reshape(nb, h)
    bmax = ax.max(axis=1)
    be = np.mean(x[:nb * h].reshape(nb, h, C) ** 2, axis=(1, 2))
    gmax = float(bmax.max()) + 1e-20
    ka, kb, kg, kl = 3, 15, 1, 50
    Pa = bmax.copy()
    for j in range(1, ka):
        Pa[:-j] = np.maximum(Pa[:-j], bmax[j:])
    cs = np.concatenate([[0.0], np.cumsum(be)])
    i = np.arange(nb)
    hi = np.clip(i - kg, 0, nb)
    lo = np.clip(i - kg - kb, 0, nb)
    Rb = np.sqrt((cs[hi] - cs[lo]) / np.maximum(hi - lo, 1)) + gmax * 1e-6
    rise = 20 * np.log10(Pa / Rb + 1e-30)
    loc = np.array([Pa[max(0, k - kl):k + kl + 1].max() for k in range(nb)])
    ok = (rise >= rise_db) & (Pa >= 0.5 * loc) & (Pa >= gmax * 10 ** (-50 / 20.0))
    # The clip's own start is not an attack: its first frames are copied
    # unmodified anyway, and counting it would swallow a real attack within
    # min_gap of it (the stronger of two close candidates is kept).
    ok[:3] = False
    rise[:3] = -np.inf                  # ...and must not outrank a nearby real attack below
    env = np.max(np.abs(x), axis=1)
    pos, rs = [], []
    for k in np.nonzero(ok)[0]:
        if rise[k] < rise[max(0, k - 3):k + 4].max():
            continue
        s0 = k * h
        s1 = min(n, s0 + (ka + 1) * h)
        pk = float(env[s0:s1].max())
        lo_ = max(0, s0 - h)
        above = np.nonzero(env[lo_:s1] >= 0.2 * pk)[0]
        p_ = lo_ + int(above[0]) if above.size else s0
        if pos and p_ - pos[-1] < min_gap:
            if rise[k] > rs[-1]:
                pos[-1], rs[-1] = p_, float(rise[k])
            continue
        pos.append(p_)
        rs.append(float(rise[k]))
    return np.asarray(pos, dtype=np.int64), np.asarray(rs)


def _stretch_map(n, target, zones, rmin=0.05, rmax=12.0):
    """Piecewise-linear map (integer knots) from input [0, n] to output.
    zones: list of (a, b, ya, reset) - input span [a, b) kept at slope 1 and
    placed at output ya. Free parts between zones absorb the rest (local
    ratio within [rmin, rmax]). A zone that starts at input 0 may place the
    clip start off output 0 (lead-in silence inserted / quiet lead-in
    trimmed); a zone that ends at input n may place the clip end off the
    target (tail padded with silence / trimmed). Returns (X, Y) or None."""
    import numpy as np
    if zones and zones[0][0] == 0:
        X, Y = [], []
    else:
        X, Y = [0], [0]
    for a, b, ya, _ in zones:
        if X and a > X[-1]:
            fa, Fa = a - X[-1], ya - Y[-1]
            if Fa < 1 or not (rmin <= Fa / float(fa) <= rmax):
                return None
            X.append(a); Y.append(ya)
        elif X and (a < X[-1] or ya != Y[-1]):
            return None
        elif not X:
            X.append(a); Y.append(ya)
        X.append(b); Y.append(ya + (b - a))
    if X[-1] < n:
        fa, Fa = n - X[-1], target - Y[-1]
        if Fa < 1 or not (rmin <= Fa / float(fa) <= rmax):
            return None
        X.append(n); Y.append(target)
    X, Y = np.asarray(X, dtype=np.int64), np.asarray(Y, dtype=np.int64)
    if X[0] != 0 or X[-1] != n or np.any(np.diff(X) <= 0) or np.any(np.diff(Y) <= 0):
        return None
    if Y[-1] < 1 or Y[0] > target - 1:
        return None
    return X, Y


def _pvoc_stretch(clip, target_len, sr=None):
    """Pitch-preserving, attack-preserving time stretch of one clip,
    (n,) or (n, C).

    v1.5.1. The length change is carried by a piecewise-linear time map:
      - every sharp attack in the clip keeps its original speed from half a
        window before it to three quarters of a window after it, and the
        frames there are phase-reset (copied unmodified), so the attack comes
        out sample-exact at its mapped position - also at the very end of the
        clip (v1.5 lost an impulse at 98 % of the clip by up to 52 dB because
        its analysis frames were not allowed to reach the clip end);
      - the clip END keeps its original speed for half a window plus a hop,
        phase-reset too, so the final samples arrive intact and there is no
        level sag; the clip START is the unmodified first frames;
      - the free parts absorb the whole length change (local ratio limited
        to 0.125-8x; if the zones do not fit, the weakest attacks are
        dropped first, then the end zone);
      - elsewhere: phase advance from a second analysis frame exactly one
        hop earlier (exact modulo 2 pi at any ratio), +-1-bin identity phase
        locking, ONE phase rotation per bin shared by all channels.
    Window: ~46 ms at the clip's sample rate (2048 if unknown), at most half
    the input and half the output length, halved (down to 256) when attacks
    are closer together in the output than a window."""
    import numpy as np
    x = np.asarray(clip, dtype=np.float64)
    mono = x.ndim == 1
    if mono:
        x = x[:, None]
    n, C = x.shape
    target_len = int(target_len)
    if n == target_len:
        y = x.copy()
        return (y[:, 0] if mono else y).astype(np.float32)
    if n < 64 or target_len < 4:
        y = np.zeros((target_len, C))
        m = min(n, target_len)
        y[:m] = x[:m]
        fl = min(16, m // 4)
        if fl > 0:
            y[m - fl:m] *= np.cos(np.linspace(0, np.pi / 2, fl))[:, None]
        return (y[:, 0] if mono else y).astype(np.float32)

    # ~46 ms window at the clip's sample rate (2048 @ 44.1/48 kHz, 1024 @
    # 16-22 kHz); 2048 when the rate is unknown. Never more than n/2.
    N = 2048 if not sr else int(2 ** round(np.log2(max(64.0, 0.0464 * sr))))
    while N > 64 and (N > n // 2 or N > target_len // 2):
        N //= 2                      # at most half the clip, input AND output
    att, rise = _clip_attacks(x)
    ratio = target_len / float(n)
    if att.size > 1:
        # attacks closer together in the OUTPUT than a window + hop cannot all
        # keep their slope-1 zones: use a shorter window (down to 256)
        gap_out = float(np.min(np.diff(np.sort(att)))) * min(1.0, ratio)
        while N > 256 and gap_out < N + N // 4:
            N //= 2
    Hs = N // 4
    K = N // 2 + 1
    win = np.hanning(N + 1)[:-1]

    # ---- time map with protected zones ---------------------------------
    # Attack zones: slope 1 from `pre` before to `post` after the attack,
    # frames phase-reset, the attack ANCHORED at its proportionally scaled
    # time round(o * ratio), so the clip's internal rhythm scales exactly.
    # A zone always covers every frame that sees the attack (>= N/2 each
    # side), so attacks are reproduced exactly; if such a zone cannot be
    # anchored proportionally (attack within about N/2 of a clip edge, or the
    # head/tail could not absorb the length change), the attack is anchored
    # to the nearer clip EDGE instead: still exact, displaced by at most
    # (ratio - 1) x its distance from that edge. Overlapping zones keep the
    # stronger attack. End zone: the last N/2 + hop at slope 1 WITHOUT
    # phase reset (at slope 1 consecutive frames stay consistent, so frames
    # reading past the end reconstruct correctly and the final level does not
    # sag; no reset means no phase discontinuity in sustained material). It
    # is omitted when an attack zone already reaches into it.
    pre_full, post_full = N // 2 + Hs // 2, N // 2 + N // 4
    end_a = max(0, n - (N // 2 + Hs))

    def attack_zone(o):
        """Largest zone that still covers every frame seeing the attack
        (>= N/2 each side, so the attack is reproduced exactly), with the
        attack anchored at round(o * ratio). Head and tail must be able to
        absorb the rest of the length change; a zone that would cross a clip
        edge is clipped to it and the edge moves instead (lead-in or tail
        padded with silence or trimmed - the detector guarantees the lead-in
        is >= 15 dB below the attack)."""
        yo = int(round(o * ratio))
        sizes = [(pre_full, post_full), (N // 2, N // 2 + Hs // 2), (N // 2, N // 2)]
        # last resort: run the zone to the clip edge(s) and move the edge
        sizes += [(pre_full, n), (o, post_full), (o, n)]
        for pre, post in sizes:
            a_, b_ = max(0, o - pre), min(n, o + post)
            ya, yb = yo - (o - a_), yo + (b_ - o)
            if a_ > 0:
                if ya < 1 or not (0.05 <= ya / float(a_) <= 12.0):
                    continue
            if b_ < n:
                if yb > target_len - 1 or not (0.05 <= (target_len - yb) / float(n - b_) <= 12.0):
                    continue
            if yb < 1 or ya > target_len - 1:
                continue
            return (a_, b_, ya, True)
        return None

    cands = []
    start_reset_to = 0          # attacks too close to the start: start-anchored zone
    end_reset_from = n          # attacks too close to the end: end-anchored, reset
    for j in (np.argsort(-rise) if rise.size else []):
        o = int(att[j])
        z = attack_zone(o)
        if z is None:
            # edge-anchored, still exact: the zone covers the attack's frames
            if o < n // 2:
                start_reset_to = max(start_reset_to, min(n, o + N // 2 + Hs // 2))
            else:
                end_reset_from = min(end_reset_from, max(0, o - (N // 2 + Hs // 2)))
            continue
        if any(not (z[1] <= c[0] or z[0] >= c[1]) for c in cands):
            continue                              # overlaps a stronger attack
        cands.append(z)
    if start_reset_to > 0:
        cands = [c for c in cands if c[0] >= start_reset_to]
        cands.append((0, start_reset_to, 0, True))
    end_reset = end_reset_from < n
    end_start = min(end_a, end_reset_from)
    if end_reset:
        cands = [c for c in cands if c[1] <= end_start]
    cands.sort()
    XY = None
    while XY is None:
        zones = list(cands)
        if not zones or zones[-1][1] < end_start:
            zones.append((end_start, n, target_len - (n - end_start), end_reset))
        XY = _stretch_map(n, target_len, zones)
        if XY is None:
            XY = _stretch_map(n, target_len, list(cands))
            if XY is not None:
                zones = list(cands)
        if XY is None:
            if cands:
                weakest = min(range(len(cands)), key=lambda i: cands[i][1] - cands[i][0])
                cands.pop(weakest)
            elif end_reset:
                end_reset = False
                end_start = end_a
            else:
                XY = (np.array([0, n]), np.array([0, target_len]))
                zones = []
    X, Y = XY
    zones_out = [(-np.inf if a == 0 else ya, np.inf if b == n else ya + (b - a))
                 for a, b, ya, rs in zones if rs]
    y_first, y_last = int(Y[0]), int(Y[-1])

    def inv(t):
        t = np.asarray(t, dtype=np.float64)
        r = np.interp(t, Y.astype(float), X.astype(float))
        r = np.where(t < y_first, X[0] + (t - y_first), r)
        return np.where(t > y_last, n + (t - y_last), r)

    pad = 2 * N + Hs
    xp = np.zeros((n + 2 * pad, C))
    xp[pad:pad + n] = x
    k0 = -int(np.ceil((N / 2.0 + Hs) / Hs))
    k1 = int(np.ceil((target_len + N / 2.0 + Hs) / Hs))
    centres_out = np.arange(k0, k1 + 1) * Hs
    centres_in = np.rint(inv(centres_out)).astype(np.int64)
    centres_in = np.clip(centres_in, Hs - pad + N // 2, n + pad - N // 2 - 1)
    # phase reset: frames at/before the clip start, and inside attack zones
    reset = centres_out <= 0
    for a, b in zones_out:
        reset |= (centres_out >= a) & (centres_out <= b)
    ar = np.arange(N)
    k_idx = np.arange(K)
    opad = 2 * N
    out = np.zeros((target_len + 2 * opad, C))
    wsum = np.zeros(target_len + 2 * opad)
    Yprev = None
    for f, (co, ci) in enumerate(zip(centres_out, centres_in)):
        idx = ci - N // 2 + pad + ar
        Xc = np.fft.rfft(xp[idx] * win[:, None], axis=0)
        if Yprev is None or reset[f]:
            Yf = Xc
        else:
            Xp = np.fft.rfft(xp[idx - Hs] * win[:, None], axis=0)
            dphi = np.angle(np.sum(Yprev * np.conj(Xp), axis=1))
            P = np.sum(np.abs(Xc) ** 2, axis=1)
            if K > 4:
                core = P[2:-2]
                pk = np.nonzero((core > P[1:-3]) & (core >= P[3:-1]) &
                                (core > P[:-4]) & (core >= P[4:]) &
                                (core > 1e-8 * (P.max() + 1e-30)))[0] + 2
                if pk.size:
                    mids = (pk[:-1] + pk[1:]) * 0.5
                    owner = pk[np.searchsorted(mids, k_idx)]
                    lock = np.abs(k_idx - owner) <= 1
                    dphi = np.where(lock, dphi[owner], dphi)
            Yf = Xc * np.exp(1j * dphi)[:, None]
        Yprev = Yf
        fr = np.fft.irfft(Yf, n=N, axis=0) * win[:, None]
        st = co - N // 2 + opad
        out[st:st + N] += fr
        wsum[st:st + N] += win ** 2
    good = wsum > 1e-3 * wsum.max()
    out[good] /= wsum[good][:, None]
    out[~good] = 0.0
    y = out[opad:opad + target_len]
    if y_last > target_len:            # tail trimmed: short fade on the cut
        fl = min(32, target_len // 4)
        if fl > 0:
            y[-fl:] *= np.cos(np.linspace(0, np.pi / 2, fl))[:, None]
    return (y[:, 0] if mono else y).astype(np.float32)


def _resize(clip, target_len, pitch_mode, sr=None):
    """Length-change dispatcher.

    varispeed / legacy off -> FFT resampling (pitch follows speed)
    preserve_pitch / legacy preserve_f0 / preserve_spectral_envelope
        -> phase-vocoder time stretch (pitch preserved)
    """
    import numpy as np
    if pitch_mode in ("off", "varispeed"):
        if np.ndim(clip) == 2:
            return np.stack([_resample(clip[:, ch], target_len)
                             for ch in range(clip.shape[1])], axis=1)
        return _resample(clip, target_len)
    return _pvoc_stretch(clip, target_len, sr)      # (n,) or (n, C), channel-coherent





def _mix_weights(query, neighbor_positions, attn_row, alpha, p=2.0, q=1.0):
    """Return (weights, attention_reweight_TV).

    attention_reweight_TV is total-variation distance between the final
    weights and the geometry-only weights with the same geometry exponent.
    It is 0 when attention has no effect and approaches 1 for strong reweighting.
    """
    import numpy as np
    dists = np.sqrt(np.sum((neighbor_positions - query) ** 2, axis=1))
    dists = np.maximum(dists, 1e-8)
    p_eff = p * max(alpha, 1e-3)
    q_eff = q * max(1.0 - alpha, 1e-3)
    geom = 1.0 / (dists ** p_eff)
    geom_n = geom / (geom.sum() + 1e-12)
    attn = np.maximum(np.asarray(attn_row, dtype=np.float64), 0.0) ** q_eff
    w = geom * attn
    s = w.sum()
    if s < 1e-12:
        return geom_n, 0.0
    w = w / s
    tv = 0.5 * float(np.sum(np.abs(w - geom_n)))
    return w, tv





def _mix_aligned(comps, sr, align=True, max_lag_s=0.010, min_rho=0.3):
    """Weighted mix of equal-length clips, phase-aware.

    v1.4 summed w_j * clip_j directly. Clips that are similar in their
    log-mel features (and therefore neighbours in latent space) can still be
    out of phase, and then cancel: eight 440 Hz events of alternating polarity
    mixed to RMS 0.041 from 0.200.
      1. Each clip is aligned to the highest-weight clip by the lag (within
         +-10 ms) and polarity that maximise their cross-correlation (summed
         over channels, so all channels move together), but only when that
         correlation is meaningful (|rho| >= 0.3); unrelated material is left
         as it is.
      2. The mix is then scaled so its RMS equals sum_j w_j * rms_j, the level
         the weights ask for (gain limited to 0.25 - 4), which also restores
         the level lost when uncorrelated clips are summed.
    align=False reproduces the v1.4 plain weighted sum."""
    import numpy as np
    ws = np.array([w for w, _ in comps], dtype=np.float64)
    cs = [np.asarray(c, dtype=np.float64) for _, c in comps]
    L = cs[0].shape[0]
    info = {"aligned": 0, "flipped": 0, "gain": 1.0}
    if not align:
        mix = sum(w * c for w, c in zip(ws, cs))
        return mix, info
    ref_i = int(np.argmax(ws))
    ref = cs[ref_i] if cs[ref_i].ndim == 2 else cs[ref_i][:, None]
    max_lag = int(min(max_lag_s * sr, L // 4))
    nfft = 1
    while nfft < 2 * L:
        nfft *= 2
    Rf = np.fft.rfft(ref, nfft, axis=0)
    e_ref = float(np.sum(ref ** 2))
    out = []
    for j, c in enumerate(cs):
        c2 = c if c.ndim == 2 else c[:, None]
        if j != ref_i and max_lag >= 1 and e_ref > 1e-20:
            e_c = float(np.sum(c2 ** 2))
            if e_c > 1e-20:
                xc = np.fft.irfft(np.sum(Rf * np.conj(np.fft.rfft(c2, nfft, axis=0)), axis=1), nfft)
                lags = np.concatenate([np.arange(0, max_lag + 1), np.arange(-max_lag, 0)])
                vals = np.concatenate([xc[:max_lag + 1], xc[-max_lag:]])
                bi = int(np.argmax(np.abs(vals)))
                rho = vals[bi] / np.sqrt(e_ref * e_c)
                if abs(rho) >= min_rho:
                    lag = int(lags[bi])           # ref[n] ~ c[n - lag]
                    if lag != 0:
                        sh = np.zeros_like(c2)
                        if lag > 0:
                            sh[lag:] = c2[:-lag]
                        else:
                            sh[:lag] = c2[-lag:]
                        c2 = sh
                    if rho < 0:
                        c2 = -c2
                        info["flipped"] += 1
                    info["aligned"] += 1
        out.append(c2)
    mix = sum(w * c for w, c in zip(ws, out))
    target = float(sum(w * np.sqrt(np.mean(c ** 2)) for w, c in zip(ws, out)))
    have = float(np.sqrt(np.mean(mix ** 2)))
    if have > 1e-12 and target > 1e-12:
        g = float(np.clip(target / have, 0.25, 4.0))
        mix = mix * g
        info["gain"] = g
    if cs[0].ndim == 1:
        mix = mix[:, 0]
    return mix, info


def execute_plan(plan, Z, A, clips, sr, target_samples, seed,
                 pitch_mode="varispeed", mix_align=True):
    """Execute latent navigation with context-indexed self-attention."""
    import numpy as np

    rng = np.random.RandomState(seed)
    N_ev, d = Z.shape
    xfade = max(4, int(XFADE_SEC * sr))
    angle = np.linspace(0, np.pi / 2, xfade, dtype=np.float32)
    fade_in = np.sin(angle)
    fade_out = np.cos(angle)
    lin_in = np.linspace(0.0, 1.0, xfade, dtype=np.float32)
    lin_out = 1.0 - lin_in
    xfade_rhos = []

    center = Z.mean(0)
    pos = center.copy()
    vel = np.zeros(d)
    drift_anchors = []   # (step_index, position, context_event)

    n_ch = clips[0].shape[1] if clips[0].ndim == 2 else 1
    mean_cl = max(4, int(np.mean([c.shape[0] for c in clips])))
    buf_shape = ((mean_cl * (len(plan) + 4), n_ch)
                 if n_ch > 1 else (mean_cl * (len(plan) + 4),))
    buf = np.zeros(buf_shape, dtype=np.float32)
    ptr = 0
    stats = []

    for si, step in enumerate(plan):
        mode  = step["mode"]
        sz    = step["step_size"]
        tmp   = step["temperature"]
        K     = min(step["k_neighbors"], N_ev)
        rstr  = step["return_strength"]
        dsca  = step["segment_duration_scale"]
        esca  = step["segment_energy_scale"]
        alpha = float(step.get("_alpha", 1.0))

        prev_pos = pos.copy()
        pre_d = np.sqrt(np.sum((Z - pos) ** 2, axis=1))
        pre_context = int(np.argmin(pre_d))
        used_anchor = -1

        # 1. Latent displacement
        if mode in ("drift", "settle"):
            td = vel / (np.linalg.norm(vel) + 1e-8)
            pos = pos + td * sz + rng.randn(d) * tmp * sz

        elif mode == "mutate":
            noise = rng.randn(d)
            noise /= (np.linalg.norm(noise) + 1e-8)
            pos = pos + noise * sz + rng.randn(d) * tmp

        elif mode == "return":
            if drift_anchors:
                # Choose the earlier drift state whose CONTEXT EVENT receives
                # the strongest attention from the current context event.
                rel = np.array([A[pre_context, ctx] for _, _, ctx in drift_anchors])
                ai = int(np.argmax(rel))
                used_anchor, ap, _ = drift_anchors[ai]
            else:
                ap = center
            pull = ap - pos
            pos = pos + rstr * pull * sz + rng.randn(d) * tmp * sz
        else:
            pos = pos + rng.randn(d) * tmp * sz

        delta = pos - prev_pos
        vel = 0.7 * vel + 0.3 * delta

        # 2. K nearest neighbors and the current latent context
        dists_all = np.sqrt(np.sum((Z - pos) ** 2, axis=1))
        context_idx = int(np.argmin(dists_all))
        nn_idx = np.argsort(dists_all)[:K]
        nn_pos = Z[nn_idx]
        if mode == "drift":
            drift_anchors.append((si, pos.copy(), context_idx))

        # 3. Attention is indexed by the CURRENT context event, not step modulo N.
        attn_row = A[context_idx][nn_idx]
        weights, attn_tv = _mix_weights(pos, nn_pos, attn_row, alpha)

        # 4. Mix clips
        tgt_len = max(4, int(round(sum(
            w * clips[i].shape[0] for w, i in zip(weights, nn_idx)))))
        comps = []
        for w, ev_idx in zip(weights, nn_idx):
            c = clips[ev_idx].astype(np.float32)
            if c.shape[0] != tgt_len:
                c = _resize(c, tgt_len, pitch_mode, sr)
            comps.append((float(w), c))
        mixed, mix_info = _mix_aligned(comps, sr, mix_align)
        mixed = mixed.astype(np.float32)

        if abs(dsca - 1.0) > 0.01:
            nl = max(4, int(round(mixed.shape[0] * dsca)))
            mixed = _resize(mixed, nl, pitch_mode, sr)
        mixed = (mixed * esca).astype(np.float32)

        # 5. True overlap crossfade: old tail + new head are summed.
        cl = mixed.shape[0]
        do_xfade = ptr >= xfade and cl >= xfade * 3
        if do_xfade:
            ov0 = ptr - xfade
            # Fade law follows the correlation of the two overlapping signals:
            # equal-power (sin/cos) for uncorrelated material, equal-gain
            # (linear) as they become identical. v1.4 always used sin/cos, which
            # peaks at sqrt(2) (+3 dB) when tail and head are coherent.
            ta = buf[ov0:ptr].astype(np.float64)
            hb = mixed[:xfade].astype(np.float64)
            den = np.sqrt(np.sum(ta * ta) * np.sum(hb * hb))
            rho = float(np.clip(np.sum(ta * hb) / den, 0.0, 1.0)) if den > 1e-20 else 0.0
            f_in = ((1.0 - rho) * fade_in + rho * lin_in).astype(np.float32)
            f_out = ((1.0 - rho) * fade_out + rho * lin_out).astype(np.float32)
            xfade_rhos.append(rho)
            if n_ch > 1:
                old_tail = (buf[ov0:ptr].T * f_out).T
                new_head = (mixed[:xfade].T * f_in).T
            else:
                old_tail = buf[ov0:ptr] * f_out
                new_head = mixed[:xfade] * f_in
            buf[ov0:ptr] = old_tail + new_head
            rest = mixed[xfade:]
            end = ptr + rest.shape[0]
            if end > buf.shape[0]:
                pad_shape = ((end - buf.shape[0] + mean_cl, n_ch)
                             if n_ch > 1 else (end - buf.shape[0] + mean_cl,))
                buf = np.concatenate([buf, np.zeros(pad_shape, dtype=np.float32)])
            buf[ptr:end] = rest
            ptr = end
        else:
            end = ptr + cl
            if end > buf.shape[0]:
                pad_shape = ((end - buf.shape[0] + mean_cl, n_ch)
                             if n_ch > 1 else (end - buf.shape[0] + mean_cl,))
                buf = np.concatenate([buf, np.zeros(pad_shape, dtype=np.float32)])
            buf[ptr:end] = mixed
            ptr = end

        dom = int(nn_idx[int(np.argmax(weights))])
        stats.append({"step": si, "mode": mode, "k": K,
                      "context": context_idx, "dominant": dom,
                      "anchor": used_anchor,
                      "attn_tv": float(attn_tv),
                      "max_weight": float(np.max(weights)),
                      "nn": nn_idx.tolist(),
                      "w": [round(float(x), 4) for x in weights],
                      "aligned": mix_info["aligned"], "flipped": mix_info["flipped"],
                      "mix_gain": mix_info["gain"]})

    # Time-normalize to target_samples
    raw = buf[:max(1, ptr)]
    if raw.shape[0] != target_samples:
        rendered = _resize(raw, target_samples, pitch_mode, sr)
    else:
        rendered = raw.copy().astype(np.float32)

    peak = float(np.max(np.abs(rendered))) if rendered.size else 0.0
    if peak > 0.99:
        rendered *= 0.99 / peak
    if stats:
        stats[0]["xfade_rho_mean"] = float(np.mean(xfade_rhos)) if xfade_rhos else 0.0
        stats[0]["raw_samples"] = int(raw.shape[0])
    return rendered, stats





# ═══════════════════════════════════════════════════════════════════════════
# Stage 4b — Dual-trajectory attentional counterpoint (v1.6)
#   Linked never enters this code: it runs execute_plan() above, unchanged.
# ═══════════════════════════════════════════════════════════════════════════

NAV_MODES        = ("linked", "independent", "competitive", "divergence_convergence")
DUAL_POOL_ALL    = 64      # N <= this: every event is a candidate
COMP_LAMBDA_MAX  = 6.0     # lambda = COMP_LAMBDA_MAX * Competition_strength
COMP_EMA_DECAY   = 0.6     # memory of the other voice's recent weights
DC_PEAK_FRAC     = 0.667   # D/C: maximal separation at the end of mutate
DC_CONV_FRAC     = 0.917   # D/C: converged at the end of return
DC_FLOOR         = 0.10    # D/C: separation kept at start / after converging
DC_PEAK_SCALE    = 2.0     # D/C peak separation = 2 * divergence * latent scale
SEP_ETA          = 0.6     # separation correction gain per step
FIT_MIN, FIT_MAX = 0.5, 2.0  # per-segment length change limits (dual modes)


def latent_pca2(Z):
    """Deterministic 2-D PCA of the latent means (NumPy SVD).
    Sign convention: the largest-magnitude loading of each component is
    positive (first index on ties). Degenerate data (one event, or all latents
    identical, or rank 1) gives zero components instead of noise.
    Returns (mean, components (d, 2), explained-variance fractions (2,))."""
    import numpy as np
    Z = np.asarray(Z, dtype=np.float64)
    N, d = Z.shape
    mu = Z.mean(0)
    comps = np.zeros((d, 2))
    evr = np.zeros(2)
    if N < 2:
        return mu, comps, evr
    _, S, Vt = np.linalg.svd(Z - mu, full_matrices=False)
    tot = float(np.sum(S ** 2))
    if tot < 1e-24:
        return mu, comps, evr
    for k in range(min(2, len(S))):
        if S[k] ** 2 / tot < 1e-12:
            continue
        v = Vt[k].copy()
        j = int(np.argmax(np.abs(v)))
        if v[j] < 0:
            v = -v
        comps[:, k] = v
        evr[k] = S[k] ** 2 / tot
    return mu, comps, evr


def _latent_scale(Z):
    """Median pairwise latent distance: the unit of 'separation'.
    Deterministic stride subsample above 2000 events."""
    import numpy as np
    Z = np.asarray(Z, dtype=np.float64)
    if Z.shape[0] > 2000:
        Z = Z[np.linspace(0, Z.shape[0] - 1, 2000).astype(int)]
    N = Z.shape[0]
    if N < 2:
        return 1.0
    G = Z @ Z.T
    sq = np.diag(G)
    D2 = np.maximum(sq[:, None] + sq[None, :] - 2 * G, 0.0)
    iu = np.triu_indices(N, 1)
    s = float(np.median(np.sqrt(D2[iu])))
    return s if s > 1e-9 else 1.0


def _dc_arc(f):
    """Divergence/convergence envelope, 0..1, over relative plan time f:
    close -> (sin) diverge -> peak at the end of mutate -> (cos) converge by
    the end of return -> stay close through settle."""
    import numpy as np
    if f < DC_PEAK_FRAC:
        return DC_FLOOR + (1 - DC_FLOOR) * float(np.sin(0.5 * np.pi * f / DC_PEAK_FRAC))
    if f < DC_CONV_FRAC:
        t = (f - DC_PEAK_FRAC) / (DC_CONV_FRAC - DC_PEAK_FRAC)
        return DC_FLOOR + (1 - DC_FLOOR) * float(np.cos(0.5 * np.pi * t))
    return DC_FLOOR


def _voice_move(v, step, Z, A, center):
    """One latent displacement of one voice. Same dynamics as execute_plan
    (drift / mutate / return / settle) but on the voice's own state and RNG."""
    import numpy as np
    d = Z.shape[1]
    rng = v["rng"]
    mode, sz, tmp = step["mode"], step["step_size"], step["temperature"]
    rstr = step["return_strength"]
    pos = v["pos"]
    pre_context = int(np.argmin(np.sqrt(np.sum((Z - pos) ** 2, axis=1))))
    used_anchor = -1
    if mode in ("drift", "settle"):
        td = v["vel"] / (np.linalg.norm(v["vel"]) + 1e-8)
        pos = pos + td * sz + rng.standard_normal(d) * tmp * sz
    elif mode == "mutate":
        noise = rng.standard_normal(d)
        noise /= (np.linalg.norm(noise) + 1e-8)
        pos = pos + noise * sz + rng.standard_normal(d) * tmp
    elif mode == "return":
        if v["anchors"]:
            rel = np.array([A[pre_context, ctx] for _, _, ctx in v["anchors"]])
            ai = int(np.argmax(rel))
            used_anchor, ap, _ = v["anchors"][ai]
        else:
            ap = center
        pos = pos + rstr * (ap - pos) * sz + rng.standard_normal(d) * tmp * sz
    else:
        pos = pos + rng.standard_normal(d) * tmp * sz
    v["pos"] = pos
    return used_anchor


def _score_candidates(pos, Z, A, K, alpha, p=2.0, q=1.0):
    """Attention-aware candidate scores over a broad pool.
    pool: all events when N <= DUAL_POOL_ALL, else the nearest max(4K, 16).
    raw_j ~ dist_j^-p_eff * A[context, j]^q_eff (same exponents as Linked),
    normalised over the pool. Returns (context, raw (N,), geom (N,))."""
    import numpy as np
    N = Z.shape[0]
    dists = np.sqrt(np.sum((Z - pos) ** 2, axis=1))
    ctx = int(np.argmin(dists))
    if N <= DUAL_POOL_ALL:
        pool = np.arange(N)
    else:
        pool = np.argsort(dists, kind="stable")[:max(4 * K, 16)]
    dd = np.maximum(dists[pool], 1e-8)
    p_eff = p * max(alpha, 1e-3)
    q_eff = q * max(1.0 - alpha, 1e-3)
    lg = -p_eff * np.log(dd)
    geom = np.exp(lg - lg.max())
    attn = np.maximum(A[ctx, pool].astype(np.float64), 0.0) ** q_eff
    raw = geom * attn
    if raw.sum() < 1e-300:
        raw = geom.copy()
    raw_full = np.zeros(N)
    geom_full = np.zeros(N)
    raw_full[pool] = raw / raw.sum()
    geom_full[pool] = geom / geom.sum()
    return ctx, raw_full, geom_full


def _top_k(score, K):
    import numpy as np
    idx = np.argsort(-score, kind="stable")[:K]
    idx = idx[score[idx] > 0]
    if idx.size == 0:
        idx = np.argsort(-score, kind="stable")[:1]
    return idx


def _norm_w(full, idx):
    import numpy as np
    w = full[idx].astype(np.float64)
    s = w.sum()
    return w / s if s > 0 else np.full(len(idx), 1.0 / len(idx))


def _render_mix(idx, w, clips, sr, pitch_mode, mix_align):
    """Phase-aware weighted mix at its natural (weighted-mean) length —
    identical construction to execute_plan step 4."""
    import numpy as np
    tgt_len = max(4, int(round(sum(wj * clips[i].shape[0] for wj, i in zip(w, idx)))))
    comps = []
    for wj, i in zip(w, idx):
        c = clips[i].astype(np.float32)
        if c.shape[0] != tgt_len:
            c = _resize(c, tgt_len, pitch_mode, sr)
        comps.append((float(wj), c))
    mixed, info = _mix_aligned(comps, sr, mix_align)
    return mixed.astype(np.float32), info


def _fit_segment(mixed, need, pitch_mode, sr, cursor=0.0, slot=None):
    """Fit one step's mix to its scheduled length 'need' (slot + outgoing
    crossfade). Length changes stay within FIT_MIN..FIT_MAX of the natural
    length (pitch_mode decides varispeed / pitch-preserving).

    Longer than that (round 2): the mix is compressed by FIT_MIN and a
    WINDOW of it is read, starting at 'cursor' (a fraction of the mix). The
    caller keeps one cursor per voice and dominant event and advances it by
    the slot, so consecutive steps on the same event continue through it
    instead of repeating its opening (round 1 always read from the start
    and lost the rest). A window that would run past the end restarts at 0.
    Shorter than FIT_MAX allows: ends early with a 3 ms fade and silence.
    Returns (y, ratio, cap, heard_from, heard_to), heard_* = the fraction of
    the (compressed) mix this slot plays."""
    import numpy as np
    L = mixed.shape[0]
    r = need / float(max(1, L))
    cap = ""
    slot = need if slot is None else slot
    h0, h1 = 0.0, 1.0
    if L == need:
        y = mixed.copy()
    elif r < FIT_MIN:
        yf = np.asarray(_resize(mixed, max(4, int(round(L * FIT_MIN))), pitch_mode, sr), dtype=np.float32)
        Ly = yf.shape[0]
        o = int(round(cursor * Ly))
        if o + need > Ly:
            o = 0
        y = yf[o:o + need]
        h0, h1 = o / float(Ly), min(1.0, (o + slot) / float(Ly))
        cap = "window"
    elif r > FIT_MAX:
        y = _resize(mixed, max(4, int(round(L * FIT_MAX))), pitch_mode, sr)
        cap = "pad"
    else:
        y = _resize(mixed, need, pitch_mode, sr)
    y = np.asarray(y, dtype=np.float32)
    if y.shape[0] > need:
        y = y[:need]
    elif y.shape[0] < need:
        fl = min(y.shape[0], max(1, int(0.003 * sr)))
        fade = np.cos(np.linspace(0, np.pi / 2, fl)).astype(np.float32)
        y[-fl:] *= fade
        y = np.concatenate([y, np.zeros(need - y.shape[0], dtype=np.float32)])
    return y, r, cap, h0, h1


def _assemble(segs, bounds, xb, T, sr):
    """Place fitted segments on the shared timeline: segment i starts at
    bounds[i]; at each boundary the previous tail and the new head overlap
    for xb[i] samples with the correlation-aware fade law of execute_plan.
    Output has exactly T samples."""
    import numpy as np
    out = np.zeros(T, dtype=np.float32)
    rhos = []
    for i, y in enumerate(segs):
        b = bounds[i]
        x = xb[i] if i > 0 else 0
        if x > 0:
            ang = np.linspace(0, np.pi / 2, x, dtype=np.float32)
            fi, fo = np.sin(ang), np.cos(ang)
            li = np.linspace(0.0, 1.0, x, dtype=np.float32)
            ta = out[b:b + x].astype(np.float64)
            hb = y[:x].astype(np.float64)
            den = np.sqrt(np.sum(ta * ta) * np.sum(hb * hb))
            rho = float(np.clip(np.sum(ta * hb) / den, 0.0, 1.0)) if den > 1e-20 else 0.0
            rhos.append(rho)
            f_in = ((1 - rho) * fi + rho * li).astype(np.float32)
            f_out = ((1 - rho) * fo + rho * (1 - li)).astype(np.float32)
            out[b:b + x] = out[b:b + x] * f_out + y[:x] * f_in
        end = min(T, b + y.shape[0])
        out[b + x:end] = y[x:end - b]
    fl = min(T, max(1, int(0.005 * sr)))
    out[-fl:] *= np.cos(np.linspace(0, np.pi / 2, fl)).astype(np.float32)
    return out, rhos


def execute_dual(plan, Z, A, clips_LR, sr, target_samples, seed, nav_mode,
                 divergence=0.5, competition=0.5, pitch_mode="varispeed",
                 mix_align=True, dur_jitter=0.0, eng_jitter=0.0):
    """Two latent trajectories over one shared phase plan.

    Each voice has its own position, velocity, RNG (navigation and timing
    streams spawned independently from the seed), context, candidates,
    weights, drift anchors and render, reading its own clip pool
    (clips_LR[0] / clips_LR[1]).
      independent  - no coupling; Trajectory_divergence sets the starting
                     offset along PC1 and a one-sided minimum-separation
                     floor (voices pushed apart only when closer than it).
      competitive  - as independent, plus symmetric, simultaneous soft
                     competition: s_j^L ~ raw_j^L * exp(-lambda * C_j^R),
                     C^R = normalised 0.5*raw^R(now) + 0.5*EMA(w^R). Never
                     looks at a voice's own history (no anti-repetition).
      divergence_convergence - target separation follows _dc_arc(); both
                     voices are moved symmetrically toward it while keeping
                     their own noise; competition is not used.
    Timeline: both voices share T = target_samples; each voice's slot
    lengths follow its own natural mix lengths x its own duration jitter and
    sum exactly to T. No whole-file resize.
    Returns (stereo (T, 2) float32, records, info)."""
    import numpy as np
    N, d = Z.shape
    n = len(plan)
    T = int(target_samples)
    lam = COMP_LAMBDA_MAX * float(competition) if nav_mode == "competitive" else 0.0
    div = float(divergence)

    ss = np.random.SeedSequence([int(seed) & 0xFFFFFFFF, 0x5A1D7])
    kids = ss.spawn(5)        # nav L, nav R, timing L, timing R, shared timing
    nav_rng = [np.random.default_rng(kids[0]), np.random.default_rng(kids[1])]
    tim_rng = [np.random.default_rng(kids[2]), np.random.default_rng(kids[3])]
    shared_rng = np.random.default_rng(kids[4])
    # Competitive and D/C relate the two voices step by step, so step i must
    # sound at the same time in both: one set of slot boundaries. Independent
    # keeps a free rhythm per voice.
    shared_time = nav_mode != "independent"

    mu, comps2, evr = latent_pca2(Z)
    sref = _latent_scale(Z)
    e1 = comps2[:, 0].copy()
    if np.linalg.norm(e1) < 1e-9:
        e1 = np.zeros(d)
        e1[0] = 1.0
    center = Z.mean(0).astype(np.float64)
    if nav_mode == "divergence_convergence":
        off0 = 0.5 * DC_PEAK_SCALE * div * sref * _dc_arc(0.0)
    else:
        off0 = 0.5 * div * sref
    voices = []
    for k, sgn in enumerate((+1.0, -1.0)):
        voices.append({"rng": nav_rng[k], "pos": center + sgn * off0 * e1,
                       "vel": np.zeros(d), "anchors": [],
                       "ema": np.zeros(N)})

    recs = [[], []]
    for si, step in enumerate(plan):
        K = min(step["k_neighbors"], N)
        alpha = float(step.get("_alpha", 1.0))
        f = float(step["relative_time"])
        prev = [v["pos"].copy() for v in voices]
        anchors_used = [_voice_move(v, step, Z, A, center) for v in voices]

        # ---- separation shaping (symmetric; never copies one voice) ----
        u = voices[0]["pos"] - voices[1]["pos"]
        s = float(np.linalg.norm(u))
        uh = u / s if s > 1e-9 else e1
        if nav_mode == "divergence_convergence":
            S = DC_PEAK_SCALE * div * sref * _dc_arc(f)
            delta = SEP_ETA * (S - s)
        else:
            S = 0.5 * div * sref
            delta = SEP_ETA * max(0.0, S - s)
        if delta != 0.0:
            voices[0]["pos"] = voices[0]["pos"] + 0.5 * delta * uh
            voices[1]["pos"] = voices[1]["pos"] - 0.5 * delta * uh
        for k, v in enumerate(voices):
            v["vel"] = 0.7 * v["vel"] + 0.3 * (v["pos"] - prev[k])

        # ---- candidate scores (pre-competition), simultaneously ----
        sc = [_score_candidates(v["pos"], Z, A, K, alpha) for v in voices]
        for k, v in enumerate(voices):
            if step["mode"] == "drift":
                v["anchors"].append((si, v["pos"].copy(), sc[k][0]))

        sel = []
        for k in range(2):
            ctx, raw, geom = sc[k]
            o = 1 - k
            if lam > 0:
                C = 0.5 * sc[o][1] + 0.5 * voices[o]["ema"]
                cm = C.max()
                C = C / cm if cm > 0 else C
                score = raw * np.exp(-lam * C)
            else:
                score = raw
            idx = _top_k(score, K)
            w = _norm_w(score, idx)
            idx0 = _top_k(raw, K)
            w0 = _norm_w(raw, idx0)
            wf = np.zeros(N); wf[idx] = w
            w0f = np.zeros(N); w0f[idx0] = w0
            comp_tv = 0.5 * float(np.abs(wf - w0f).sum())
            wpre = _norm_w(raw, idx)
            gsel = _norm_w(geom, idx)
            attn_tv = 0.5 * float(np.abs(wpre - gsel).sum())
            sel.append((ctx, idx, w, wf, comp_tv, attn_tv))
        for k in range(2):     # EMA update after both selections (symmetric)
            voices[k]["ema"] = COMP_EMA_DECAY * voices[k]["ema"] + (1 - COMP_EMA_DECAY) * sel[k][3]
        overlap = float(np.minimum(sel[0][3], sel[1][3]).sum())
        sep = float(np.linalg.norm(voices[0]["pos"] - voices[1]["pos"]))
        for k in range(2):
            ctx, idx, w, wf, comp_tv, attn_tv = sel[k]
            pos = voices[k]["pos"]
            xy = (pos - mu) @ comps2
            recs[k].append({"step": si, "phase": step["mode"], "k": int(len(idx)),
                            "context": ctx, "dominant": int(idx[int(np.argmax(w))]),
                            "dom_w": float(np.max(w)), "nn": idx.tolist(),
                            "w": [float(x) for x in w], "attn_tv": attn_tv,
                            "comp_tv": comp_tv, "overlap": overlap,
                            "sep_norm": sep / sref, "target_sep_norm": S / sref,
                            "anchor": anchors_used[k], "x": float(xy[0]),
                            "y": float(xy[1]), "pos": pos.copy(),
                            "rel": f})

    # ---- render each voice on the shared timeline ----
    xf = max(4, int(XFADE_SEC * sr))
    chans, info = [], {"xfade_rhos": [], "fit_ratios": [], "capped": 0,
                       "aligned": 0, "flipped": 0, "gains": []}
    def jit(rng, amount):
        return np.array([float(np.clip(1 + rng.uniform(-amount, amount), 0.5, 1.5))
                         if amount > 0 else 1.0 for _ in range(n)])

    def schedule(wts):
        cum = np.concatenate([[0.0], np.cumsum(wts)])
        b = np.round(T * cum / cum[-1]).astype(int)
        b[0], b[-1] = 0, T
        return b

    mixes, nat = [[], []], [[], []]
    for k in range(2):
        for r in recs[k]:
            m, mi = _render_mix(r["nn"], r["w"], clips_LR[k], sr, pitch_mode, mix_align)
            mixes[k].append(m)
            nat[k].append(m.shape[0])
            r["aligned"], r["flipped"], r["mix_gain"] = mi["aligned"], mi["flipped"], mi["gain"]
            info["aligned"] += mi["aligned"]; info["flipped"] += mi["flipped"]
            info["gains"].append(mi["gain"])
    if shared_time:
        # one compositional step = one time slot for both voices, sized by
        # the mean natural length of the two mixes x a shared duration jitter
        jd = jit(shared_rng, dur_jitter)
        sb = schedule(0.5 * (np.asarray(nat[0], float) + np.asarray(nat[1], float)) * jd)
        bounds_k = [sb, sb]
        je_k = [jit(tim_rng[0], eng_jitter), jit(tim_rng[1], eng_jitter)]
    else:
        bounds_k, je_k = [], []
        for k in range(2):
            jd = jit(tim_rng[k], dur_jitter)
            je_k.append(jit(tim_rng[k], eng_jitter))
            bounds_k.append(schedule(np.asarray(nat[k], dtype=np.float64) * jd))
    for k in range(2):
        bounds, je = bounds_k[k], je_k[k]
        slots = np.diff(bounds)
        xb = np.zeros(n + 1, dtype=int)
        for i in range(1, n):
            xb[i] = int(max(0, min(xf, slots[i - 1] // 2, slots[i] // 2)))
        segs = []
        cursor = {}       # dominant event -> read position in its mix (fraction)
        heard = {}        # dominant event -> list of (from, to) fractions heard
        for i in range(n):
            need = int(slots[i] + xb[i + 1])
            r = recs[k][i]
            r["b0"], r["b1"] = int(bounds[i]), int(bounds[i + 1])
            r["t0"], r["t1"] = bounds[i] / float(sr), bounds[i + 1] / float(sr)
            mixed_i = mixes[k][i]
            if need <= 0:
                segs.append(np.zeros(0, dtype=np.float32))
                r["fit"], r["cap"] = 0.0, "empty"
                continue
            dom = r["dominant"]
            y, ratio, cap, h0, h1 = _fit_segment(mixed_i, need, pitch_mode, sr,
                                                 cursor.get(dom, 0.0), int(slots[i]))
            cursor[dom] = h1 if (cap == "window" and h1 < 0.98) else 0.0
            heard.setdefault(dom, []).append((h0, h1))
            y = (y * je[i]).astype(np.float32)
            segs.append(y)
            r["fit"], r["cap"], r["read_from"], r["read_to"] = ratio, cap, h0, h1
            info["fit_ratios"].append(ratio)
            info["capped"] += 1 if cap else 0
        # coverage: share of each dominant event's mix actually played,
        # and what reading only the opening (round 1) would have played
        cov, cov0 = [], []
        for dom, iv in heard.items():
            iv = sorted(iv)
            tot, a, b = 0.0, iv[0][0], iv[0][1]
            for c0, c1 in iv[1:]:
                if c0 > b:
                    tot += b - a
                    a, b = c0, c1
                else:
                    b = max(b, c1)
            tot += b - a
            cov.append(min(1.0, tot))
            cov0.append(max(c1 - c0 for c0, c1 in iv))
        info.setdefault("coverage", []).append(float(np.mean(cov)) if cov else 1.0)
        info.setdefault("coverage_start_only", []).append(float(np.mean(cov0)) if cov0 else 1.0)
        info.setdefault("windowed", []).append(sum(1 for rr in recs[k] if rr.get("cap") == "window"))
        out, rhos = _assemble(segs, bounds, xb, T, sr)
        info["xfade_rhos"] += rhos
        chans.append(out)
    stereo = np.stack(chans, axis=1).astype(np.float32)
    peak = float(np.max(np.abs(stereo))) if stereo.size else 0.0
    if peak > 0.99:
        stereo *= 0.99 / peak
    info.update({"sref": sref, "lambda": lam, "nav_mode": nav_mode, "pca_mu": mu, "pca_comps": comps2,
                 "pca_evr": evr, "shared_time": shared_time, "T": T, "sr": sr})
    info["timeline"] = dual_timeline(recs, info)
    return stereo, recs, info


def dual_timeline(recs, info):
    """The two voices as they actually sound together.

    The output is cut at every slot boundary of either voice; inside each
    interval one step of L and one step of R are sounding. Per interval:
    which steps, their dominant events, whether the dominant is the same,
    the selection overlap sum_j min(wL_j, wR_j) of the two sounding mixes,
    and the latent separation of the two sounding positions. All inter-voice
    statistics and the map's relation panels are computed from this, not by
    pairing step numbers (which only coincide in time when the timeline is
    shared). Trend: D/C = sign of the change of the applied target; other
    modes = sign of the slope of the executed separation smoothed over T/24
    (threshold 0.2 % of its maximum per 1/400 of T). conv = 1 on the first
    interval of each run with separation <= CONV_SEP."""
    import numpy as np
    T, sr, sref = info["T"], info["sr"], info["sref"]
    mu, comps2 = info["pca_mu"], info["pca_comps"]
    cuts = sorted(set([r["b0"] for v in recs for r in v] + [T]))
    rows = []
    iL = iR = 0
    for a, b in zip(cuts[:-1], cuts[1:]):
        if b <= a:
            continue
        while recs[0][iL]["b1"] <= a:
            iL += 1
        while recs[1][iR]["b1"] <= a:
            iR += 1
        rl, rr = recs[0][iL], recs[1][iR]
        wl = dict(zip(rl["nn"], rl["w"]))
        wr = dict(zip(rr["nn"], rr["w"]))
        ov = float(sum(min(w, wr[j]) for j, w in wl.items() if j in wr))
        sep = float(np.linalg.norm(rl["pos"] - rr["pos"])) / sref
        xl, yl = (rl["pos"] - mu) @ comps2
        xr, yr = (rr["pos"] - mu) @ comps2
        rows.append({"t0": a / float(sr), "t1": b / float(sr), "stepL": rl["step"], "stepR": rr["step"],
                     "domL": rl["dominant"], "domR": rr["dominant"],
                     "shared": int(rl["dominant"] == rr["dominant"]), "overlap": ov, "sep": sep,
                     "target": rl["target_sep_norm"] if info["nav_mode"] == "divergence_convergence" else float("nan"),
                     "xL": float(xl), "yL": float(yl), "xR": float(xr), "yR": float(yr)})
    n = len(rows)
    if info["nav_mode"] == "divergence_convergence":
        tg = np.array([r["target"] for r in rows])
        g = np.gradient(tg) if n > 1 else np.zeros(n)
        lab = ["diverge" if v > 1e-6 else "converge" if v < -1e-6 else "hold" for v in g]
    else:
        G = 400
        tc = (np.arange(G) + 0.5) * T / G / float(sr)
        t0 = np.array([r["t0"] for r in rows])
        sg = np.array([r["sep"] for r in rows])[np.searchsorted(t0, tc, side="right") - 1]
        w = max(1, G // 48)
        pad = np.concatenate([np.full(w, sg[0]), sg, np.full(w, sg[-1])])
        sm = np.convolve(pad, np.ones(2 * w + 1) / (2 * w + 1), "same")[w:w + G]
        gg = np.gradient(sm)
        thr = 0.002 * max(1e-9, float(sm.max()))
        lab = []
        for r in rows:
            gi = min(G - 1, int(0.5 * (r["t0"] + r["t1"]) * float(sr) / T * G))
            lab.append("diverge" if gg[gi] > thr else "converge" if gg[gi] < -thr else "hold")
    prev = False
    for r, l in zip(rows, lab):
        r["trend"] = l
        c = r["sep"] <= CONV_SEP
        r["conv"] = int(c and not prev)
        prev = c
    return rows


CONV_SEP = 0.25   # normalised separation at or below which the voices count as converged


def write_dual_tsv(path_prefix, recs, events, Z, info, sr):
    """<prefix>steps.tsv   : one row per executed step and voice.
       <prefix>timeline.tsv: the two voices as they sound together (one row
                             per interval between consecutive slot
                             boundaries of either voice), see dual_timeline.
       <prefix>events.tsv  : projected source events (times relative to WAV).
    overlap_step / shared_step pair step i of L with step i of R; they equal
    the sounding relation only when the timeline is shared (Competitive,
    D/C). Only executed values are written; nothing is interpolated."""
    import numpy as np
    mu, comps2 = info["pca_mu"], info["pca_comps"]
    with open(path_prefix + "steps.tsv", "w", newline="\n") as f:
        f.write("voice\tstep\tt0\tt1\tphase\tx\ty\tcontext\tdominant\tdom_w\tk"
                "\tselected\tweights\tattn_tv\tcomp_tv\tsep_step\ttarget_sep\toverlap_step"
                "\tshared_step\tfit\tcap\tread_from\tread_to\tanchor\tz\n")
        for k, lab in enumerate(("L", "R")):
            for i, r in enumerate(recs[k]):
                shared = 1 if recs[0][i]["dominant"] == recs[1][i]["dominant"] else 0
                f.write("%s\t%d\t%.6f\t%.6f\t%s\t%.6f\t%.6f\t%d\t%d\t%.4f\t%d\t%s\t%s"
                        "\t%.4f\t%.4f\t%.4f\t%.4f\t%.4f\t%d\t%.4f\t%s\t%.4f\t%.4f\t%d\t%s\n" % (
                    lab, r["step"], r["t0"], r["t1"], r["phase"], r["x"], r["y"],
                    r["context"], r["dominant"], r["dom_w"], r["k"],
                    ";".join(str(j) for j in r["nn"]),
                    ";".join("%.4f" % w for w in r["w"]),
                    r["attn_tv"], r["comp_tv"], r["sep_norm"], r["target_sep_norm"],
                    r["overlap"], shared, r.get("fit", 0.0), r.get("cap", "") or "-",
                    r.get("read_from", 0.0), r.get("read_to", 1.0), r["anchor"], ";".join("%.4f" % v for v in r["pos"])))
    with open(path_prefix + "timeline.tsv", "w", newline="\n") as f:
        f.write("t0\tt1\tstepL\tstepR\tdomL\tdomR\tshared\toverlap\tsep\ttarget"
                "\ttrend\tconv\txL\tyL\txR\tyR\n")
        for r in info["timeline"]:
            tg = r["target"]
            f.write("%.6f\t%.6f\t%d\t%d\t%d\t%d\t%d\t%.4f\t%.4f\t%s\t%s\t%d\t%.6f\t%.6f\t%.6f\t%.6f\n" % (
                r["t0"], r["t1"], r["stepL"], r["stepR"], r["domL"], r["domR"], r["shared"],
                r["overlap"], r["sep"], ("%.4f" % tg) if tg == tg else "-1", r["trend"], r["conv"],
                r["xL"], r["yL"], r["xR"], r["yR"]))
    P = (np.asarray(Z, dtype=np.float64) - mu) @ comps2
    with open(path_prefix + "events.tsv", "w", newline="\n") as f:
        f.write("event\tx\ty\tstart\tend\n")
        for j, ev in enumerate(events):
            f.write("%d\t%.6f\t%.6f\t%.6f\t%.6f\n" % (
                j, P[j, 0], P[j, 1], float(ev["start_time"]), float(ev["end_time"])))


def dual_summary(recs, info, sr):
    """Inter-trajectory statistics. The main ones are time-weighted over the
    sounding timeline (what is heard together); the *_step ones pair step
    numbers. Separation windows by output time: begin = first sixth, mid =
    middle sixth, peak region = 0.567-0.687 of T (D/C peak at 0.667 of the
    plan), end = last sixth."""
    import numpy as np
    tl = info["timeline"]
    T = info["T"] / float(sr)
    t0 = np.array([r["t0"] for r in tl])
    t1 = np.array([r["t1"] for r in tl])
    d = t1 - t0

    def tw(key, lo=0.0, hi=1.0):
        a = np.clip(t0, lo * T, hi * T)
        b = np.clip(t1, lo * T, hi * T)
        w = np.maximum(0.0, b - a)
        v = np.array([float(r[key]) for r in tl])
        return float(np.sum(w * v) / np.sum(w)) if np.sum(w) > 0 else 0.0

    dL = [r["dominant"] for r in recs[0]]
    dR = [r["dominant"] for r in recs[1]]
    starts = np.array([abs(a["t0"] - b["t0"]) for a, b in zip(recs[0], recs[1])])
    return {
        "unique_L": len(set(dL)), "unique_R": len(set(dR)),
        "unique_union": len(set(dL) | set(dR)),
        "shared_dom_frac": tw("shared"),
        "overlap_mean": tw("overlap"),
        "sep_mean": tw("sep"),
        "sep_begin": tw("sep", 0.0, 1 / 6.0),
        "sep_mid": tw("sep", 5 / 12.0, 7 / 12.0),
        "sep_peak_region": tw("sep", 0.567, 0.687),
        "sep_end": tw("sep", 5 / 6.0, 1.0),
        "overlap_step_mean": float(np.mean([r["overlap"] for r in recs[0]])),
        "shared_step_frac": float(np.mean([a == b for a, b in zip(dL, dR)])),
        "step_start_offset_median": float(np.median(starts)),
        "step_start_offset_max": float(np.max(starts)),
        "timeline": "shared" if info["shared_time"] else "per_voice",
        "comp_tv_mean": float(np.mean([r["comp_tv"] for v in recs for r in v])),
        "attn_tv_mean": float(np.mean([r["attn_tv"] for v in recs for r in v])),
        "max_w_mean": float(np.mean([r["dom_w"] for v in recs for r in v])),
    }


# ═══════════════════════════════════════════════════════════════════════════
# Stage 5 — Output, compensation, cleanup
# ═══════════════════════════════════════════════════════════════════════════

def _rms_compensate(audio_out, ref_rms, mode):
    """
    mode: none | peak | rms
    Safety ceiling: -1 dBFS (0.891)
    """
    import numpy as np
    CEIL = 0.891
    out  = audio_out.astype(np.float32)
    peak = np.max(np.abs(out))
    if peak < 1e-9:
        return out
    if mode == "peak":
        out *= CEIL / peak
    elif mode == "rms":
        # v1.2: dropped the unreachable "loudness" alias here -- the
        # Praat front-end never sends it (only "none" / "peak" / "rms").
        rms = float(np.sqrt(np.mean(out.astype(np.float64) ** 2)))
        if rms > 1e-9 and ref_rms > 1e-9:
            out *= ref_rms / rms
        pk2 = np.max(np.abs(out))
        if pk2 > CEIL:
            out *= CEIL / pk2
    return out


def write_stats(path, events, plan, losses, stats,
                sr, out_dur, attn_heads, attn_entropy,
                pitch_mode, norm_mode, ref_rms, out_rms, warnings,
                analysis_channel, input_channels, output_channels, dual=None):
    import numpy as np
    mode_counts = {}
    for st in stats:
        mode_counts[st["mode"]] = mode_counts.get(st["mode"], 0) + 1
    H_norm = (attn_entropy / np.log(max(2, len(events)))) if len(events) > 1 else 0.0
    unique_dom = len(set(st.get("dominant", -1) for st in stats)) if stats else 0
    mean_attn_tv = float(np.mean([st.get("attn_tv", 0.0) for st in stats])) if stats else 0.0
    mean_max_w = float(np.mean([st.get("max_weight", 0.0) for st in stats])) if stats else 0.0
    if dual is not None:      # both voices, not just the one used for phase counts
        unique_dom = dual["unique_union"]
        mean_attn_tv = dual["attn_tv_mean"]
        mean_max_w = dual["max_w_mean"]

    with open(path, "w") as f:
        f.write("n_events=%d\n"          % len(events))
        f.write("n_plan_steps=%d\n"      % len(plan))
        f.write("n_executed=%d\n"        % len(stats))
        f.write("output_duration=%.3f\n" % out_dur)
        f.write("attn_heads=%d\n"        % attn_heads)
        f.write("attn_entropy=%.4f\n"    % attn_entropy)
        f.write("attn_entropy_norm=%.4f\n" % H_norm)
        f.write("mean_attention_reweight=%.4f\n" % mean_attn_tv)
        f.write("mean_max_mix_weight=%.4f\n" % mean_max_w)
        f.write("unique_dominant_events=%d\n" % unique_dom)
        f.write("analysis_channel=%d\n"  % analysis_channel)
        f.write("input_channels=%d\n"    % input_channels)
        f.write("output_channels=%d\n"   % output_channels)
        f.write("pitch_mode=%s\n"        % pitch_mode)
        f.write("normalize_mode=%s\n"    % norm_mode)
        f.write("rms_input=%.6f\n"       % ref_rms)
        f.write("rms_output=%.6f\n"      % out_rms)
        f.write("vae_loss_initial=%.6f\n" % (losses[0] if losses else 0))
        f.write("vae_loss_final=%.6f\n"   % (losses[-1] if losses else 0))
        for md, c in sorted(mode_counts.items()):
            f.write("mode_%s=%d\n" % (md, c))
        dur_arr = [float(e["end_time"]) - float(e["start_time"]) for e in events]
        f.write("mean_event_dur=%.3f\n" % float(np.mean(dur_arr)))
        if stats:
            f.write("mix_aligned_clips=%d\n" % sum(st.get("aligned", 0) for st in stats))
            f.write("mix_polarity_flips=%d\n" % sum(st.get("flipped", 0) for st in stats))
            f.write("mix_gain_mean=%.4f\n" % float(np.mean([st.get("mix_gain", 1.0) for st in stats])))
            f.write("crossfade_rho_mean=%.4f\n" % stats[0].get("xfade_rho_mean", 0.0))
            raw = stats[0].get("raw_samples", 0)
            f.write("raw_render_duration=%.3f\n" % (raw / float(sr)))
            f.write("final_resize_ratio=%.4f\n" % (raw / max(1.0, out_dur * sr)))
        if dual is None:
            f.write("nav_mode=linked\n")
        else:
            for key, fmt in DUAL_STAT_KEYS:
                f.write(("%s=" + fmt + "\n") % (key, dual[key]))
        for w in warnings:
            f.write("warning=%s\n" % w)


# Appended after every v1.5.1 key (Praat's parser matches the first
# occurrence of a key, so the old keys keep their meaning and position).
DUAL_STAT_KEYS = [
    ("nav_mode", "%s"), ("trajectory_divergence", "%.4f"),
    ("competition_strength", "%.4f"), ("competition_lambda", "%.4f"),
    ("ignored_parameters", "%s"), ("dual_routing", "%s"),
    ("voice_L_source", "%s"), ("voice_R_source", "%s"),
    ("unique_dominant_L", "%d"), ("unique_dominant_R", "%d"),
    ("dual_timeline", "%s"),
    ("shared_dominant_fraction", "%.4f"), ("selection_overlap_mean", "%.4f"),
    ("shared_dominant_step_fraction", "%.4f"), ("selection_overlap_step_mean", "%.4f"),
    ("step_start_offset_median", "%.4f"), ("step_start_offset_max", "%.4f"),
    ("separation_mean", "%.4f"), ("separation_begin", "%.4f"),
    ("separation_mid", "%.4f"), ("separation_peak_region", "%.4f"),
    ("separation_end", "%.4f"), ("competition_adjust_mean", "%.4f"),
    ("latent_scale", "%.6f"), ("pca_explained_1", "%.4f"), ("pca_explained_2", "%.4f"),
    ("segment_fit_ratio_min", "%.4f"), ("segment_fit_ratio_median", "%.4f"),
    ("segment_fit_ratio_max", "%.4f"), ("segments_capped", "%d"),
    ("segments_windowed", "%d"), ("read_coverage_L", "%.4f"), ("read_coverage_R", "%.4f"),
    ("read_coverage_start_only_L", "%.4f"), ("read_coverage_start_only_R", "%.4f"),
    ("peak_L", "%.4f"), ("peak_R", "%.4f"), ("rms_L", "%.6f"), ("rms_R", "%.6f"),
    ("lr_correlation", "%.4f"), ("samples_L", "%d"), ("samples_R", "%d"),
]


# ═══════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════

def _read_args_file(path):
    """One argument per line. Praat writes UTF-8, or UTF-16 when the text
    contains non-ASCII characters (e.g. a user name in a temp path)."""
    raw = open(path, "rb").read()
    if raw[:2] in (b"\xff\xfe", b"\xfe\xff"):
        txt = raw.decode("utf-16")
    elif raw[:3] == b"\xef\xbb\xbf":
        txt = raw[3:].decode("utf-8")
    else:
        try:
            txt = raw.decode("utf-8")
        except UnicodeDecodeError:
            txt = raw.decode("latin-1")
    return [ln.rstrip("\r") for ln in txt.split("\n") if ln.strip() != ""]


def main():
    import argparse
    import numpy as np
    import soundfile as sf

    parser = argparse.ArgumentParser(
        description="Self-Attention Latent navigation engine")

    # Positional — Praat passes exactly these
    parser.add_argument("input_wav")
    parser.add_argument("events_csv")
    parser.add_argument("output_wav")
    parser.add_argument("stats_txt")

    # Core
    parser.add_argument("--latent_size",  type=int,   default=8)
    parser.add_argument("--seed",         type=int,   default=42)
    parser.add_argument("--duration",     type=float, default=0.0,
        help="Target duration in seconds (0 = match input)")

    # Attention
    parser.add_argument("--attn_heads",   type=int,   default=4)

    # Plan
    parser.add_argument("--plan_steps",   type=int,   default=72)
    parser.add_argument("--plan_dur_scale",  type=float, default=1.0)
    parser.add_argument("--plan_dur_jitter", type=float, default=0.0)
    parser.add_argument("--plan_eng_scale",  type=float, default=1.0)
    parser.add_argument("--plan_eng_jitter", type=float, default=0.0)

    # Audio
    parser.add_argument("--pitch_mode",
        choices=["varispeed", "preserve_pitch", "off", "preserve_f0", "preserve_spectral_envelope"],
        default="varispeed")
    parser.add_argument("--normalize_mode",
        choices=["none", "peak", "rms"],
        default="rms")

    # Cleanup
    parser.add_argument("--time_offset", type=float, default=0.0,
        help="Start time of the Praat Sound: event times are given on the Sound's "
             "own timeline, the WAV starts at 0")
    parser.add_argument("--mix_align", choices=["on", "off"], default="on",
        help="phase-aware mixing (v1.5); off = v1.4 plain weighted sum")
    parser.add_argument("--cleanup", action="store_true",
        help="Delete Praat-created temp files after run")

    # v1.6 dual-trajectory navigation
    parser.add_argument("--nav_mode", choices=list(NAV_MODES), default="linked")
    parser.add_argument("--divergence", type=float, default=0.5)
    parser.add_argument("--competition", type=float, default=0.5)
    parser.add_argument("--dual_routing", choices=["per_channel", "reference"],
        default="per_channel",
        help="stereo source in dual modes: per_channel = L voice reads the left "
             "channel, R voice the right; reference = both read the analysis channel")
    parser.add_argument("--viz_tsv", default="",
        help="dual modes: write <prefix>steps.tsv and <prefix>events.tsv")

    argv = sys.argv[1:]
    args_file = ""
    if len(argv) == 1 and argv[0].startswith("@"):
        args_file = argv[0][1:]
        argv = _read_args_file(args_file)
    args = parser.parse_args(argv)
    check_deps()

    # Canonicalise legacy pitch-mode aliases and clamp direct-CLI values.
    if args.pitch_mode == "off":
        args.pitch_mode = "varispeed"
    elif args.pitch_mode in ("preserve_f0", "preserve_spectral_envelope"):
        args.pitch_mode = "preserve_pitch"
    args.plan_steps = max(8, min(500, args.plan_steps))
    args.plan_dur_scale = max(0.25, min(4.0, args.plan_dur_scale))
    args.plan_eng_scale = max(0.0, min(4.0, args.plan_eng_scale))
    args.plan_dur_jitter = max(0.0, min(0.50, args.plan_dur_jitter))
    args.plan_eng_jitter = max(0.0, min(0.50, args.plan_eng_jitter))

    np.random.seed(args.seed)
    warnings_list = []

    # ── Stage 1: Load ──────────────────────────────────────────────────────
    print("  [SAL 1/5] Loading audio + events...")
    audio, sr = sf.read(args.input_wav, always_2d=False)
    audio     = np.asarray(audio, dtype=np.float32)
    events    = load_events(args.events_csv)

    n_samp   = len(audio) if audio.ndim == 1 else audio.shape[0]
    orig_dur = n_samp / sr
    tgt_dur  = args.duration if args.duration > 0 else orig_dur
    tgt_samp = int(tgt_dur * sr)

    # Event times arrive on the Praat Sound's timeline; the exported WAV starts
    # at 0. Shift them, then refuse events that do not lie in the audio rather
    # than silently cutting the wrong (or empty) regions (v1.4 returned
    # complete silence for a Sound starting at 7.5 s with Silences segmentation).
    if args.time_offset != 0.0:
        for ev in events:
            # rounded to 1 ns so that e.g. 7.75 - 7.5 cannot land a hair under
            # 0.25 and truncate to the previous sample
            ev["start_time"] = round(float(ev["start_time"]) - args.time_offset, 9)
            ev["end_time"] = round(float(ev["end_time"]) - args.time_offset, 9)
    tol = 2.0 / sr
    bad = [i for i, ev in enumerate(events)
           if float(ev["start_time"]) < -tol or float(ev["end_time"]) > orig_dur + tol
           or float(ev["end_time"]) <= float(ev["start_time"])]
    if bad:
        ev = events[bad[0]]
        print("ERROR: %d event(s) lie outside the audio (first: %.3f-%.3f s, audio is "
              "0-%.3f s). The events and the WAV are on different timelines; pass the "
              "Sound's start time with --time_offset." % (
                  len(bad), float(ev["start_time"]), float(ev["end_time"]), orig_dur),
              file=sys.stderr)
        sys.exit(1)
    print("    Audio: %.2fs  SR=%d  Events=%d" % (orig_dur, sr, len(events)))
    if len(events) < 2:
        print("ERROR: at least two events are required for latent navigation.", file=sys.stderr)
        sys.exit(1)
    if len(events) < 3:
        warnings_list.append("too_few_events_%d" % len(events))

    # Input level uses all channels without phase-cancelling fold-down.  Latent
    # analysis uses one real, representative channel: the strongest-RMS channel.
    if audio.ndim == 1:
        input_channels = 1
        analysis_idx = 0
        audio_mono = audio
    else:
        input_channels = audio.shape[1]
        ch_rms = np.sqrt(np.mean(audio.astype(np.float64) ** 2, axis=0))
        analysis_idx = int(np.argmax(ch_rms))
        audio_mono = audio[:, analysis_idx]
    analysis_channel = analysis_idx + 1
    ref_rms = float(np.sqrt(np.mean(audio.astype(np.float64) ** 2)))
    print("    Analysis channel: %d/%d (strongest RMS)" % (analysis_channel, input_channels))

    # Mel patches
    patches = extract_patches(audio_mono.astype(np.float64), sr, events)
    print("    Patches: %s" % str(patches.shape))

    # VAE
    z_dim    = max(2, min(32, args.latent_size))
    n_iter   = max(60, min(300, 80 + len(events) * 3))
    print("  [SAL 1/5] Training VAE (%d iters, z=%d)..." % (n_iter, z_dim))
    model, losses = train_vae(patches, z_dim, n_iter, args.seed)
    lr = losses[-1] / (losses[0] + 1e-12) if losses else 1.0
    print("    Loss: %.6f -> %.6f (%.1f%% reduction)" % (
        losses[0], losses[-1], (1 - lr) * 100))
    if lr > 0.95:
        warnings_list.append("vae_did_not_converge")

    Z = encode(model, patches)
    print("    Z: %s  range [%.3f, %.3f]" % (str(Z.shape), Z.min(), Z.max()))

    # ── Stage 2: Self-attention ────────────────────────────────────────────
    heads_req = max(1, min(args.attn_heads, z_dim))
    A, H_mean, heads = build_attention(Z, n_heads=heads_req, seed=args.seed)
    print("  [SAL 2/5] Building attention matrix (%d heads%s)..." %
          (heads, " (requested %d)" % heads_req if heads != heads_req else ""))
    print("    A: %s  entropy=%.4f nats (norm %.3f)" %
          (str(A.shape), H_mean, H_mean / np.log(max(2, len(events)))))

    # ── Stage 3: Plan generation ───────────────────────────────────────────
    print("  [SAL 3/5] Generating navigation plan (%d steps)..." % args.plan_steps)
    # Per-segment scales carry only the JITTER here (internal rhythm/dynamics).
    # The GLOBAL Duration_scale is applied to the render target (below) so it
    # sets output length instead of being cancelled by the final time-
    # normalize; the GLOBAL Energy_scale is applied as a post-normalize master
    # gain so it isn't undone by loudness normalization.
    plan = generate_plan(Z, A,
                         n_steps    = args.plan_steps,
                         seed       = args.seed,
                         dur_scale  = 1.0,
                         dur_jitter = args.plan_dur_jitter,
                         eng_scale  = 1.0,
                         eng_jitter = args.plan_eng_jitter)
    # Clamp k to event count
    for row in plan:
        row["k_neighbors"] = min(row["k_neighbors"], len(events))
    modes = {}
    for s in plan:
        modes[s["mode"]] = modes.get(s["mode"], 0) + 1
    print("    Plan: %s" % "  ".join("%s=%d" % kv for kv in sorted(modes.items())))

    # ── Stage 4: Execute ───────────────────────────────────────────────────
    print("  [SAL 4/5] Extracting clips + executing plan...")
    clips  = _extract_clips(audio, events, sr)
    # Global Duration_scale sets the output length (pitch-preserved when
    # pitch_mode != off, since the final time-normalize goes through _resize).
    render_samples = max(1, int(round(tgt_samp * args.plan_dur_scale)))
    dual = None
    if args.nav_mode == "linked":
        output, step_stats = execute_plan(
            plan, Z, A, clips, sr, render_samples, args.seed,
            pitch_mode=args.pitch_mode, mix_align=(args.mix_align == "on"))
    else:
        div = max(0.0, min(1.0, args.divergence))
        comp = max(0.0, min(1.0, args.competition))
        if input_channels == 1:
            routing, srcL, srcR = "mono_shared", "mono", "mono"
            pools = [clips, clips]
        elif input_channels == 2 and args.dual_routing == "per_channel":
            routing, srcL, srcR = "per_channel", "ch1", "ch2"
            pools = [_extract_clips(audio[:, 0], events, sr),
                     _extract_clips(audio[:, 1], events, sr)]
        elif args.dual_routing == "reference":
            routing = "reference"
            srcL = srcR = "ch%d" % analysis_channel
            ref_clips = _extract_clips(audio[:, analysis_idx], events, sr)
            pools = [ref_clips, ref_clips]
        else:
            print("ERROR: %s navigation renders two voices (L/R). The source has %d "
                  "channels; refusing to drop channels silently. Use Navigation_mode "
                  "= Linked (keeps all channels), convert the Sound to stereo, or "
                  "pass --dual_routing reference to read only the analysis channel "
                  "(%d)." % (args.nav_mode, input_channels, analysis_channel),
                  file=sys.stderr)
            sys.exit(1)
        ignored = []
        if args.nav_mode != "competitive":
            ignored.append("competition_strength")
        output, recs, dinfo = execute_dual(
            plan, Z, A, pools, sr, render_samples, args.seed, args.nav_mode,
            divergence=div, competition=comp, pitch_mode=args.pitch_mode,
            mix_align=(args.mix_align == "on"),
            dur_jitter=args.plan_dur_jitter, eng_jitter=args.plan_eng_jitter)
        dual = dual_summary(recs, dinfo, sr)
        fr = np.array(dinfo["fit_ratios"]) if dinfo["fit_ratios"] else np.ones(1)
        dual.update({
            "nav_mode": args.nav_mode, "trajectory_divergence": div,
            "competition_strength": comp, "competition_lambda": dinfo["lambda"],
            "ignored_parameters": ",".join(ignored) if ignored else "none",
            "dual_routing": routing, "voice_L_source": srcL, "voice_R_source": srcR,
            "unique_dominant_L": dual["unique_L"], "unique_dominant_R": dual["unique_R"],
            "dual_timeline": dual["timeline"],
            "shared_dominant_step_fraction": dual["shared_step_frac"],
            "selection_overlap_step_mean": dual["overlap_step_mean"],
            "shared_dominant_fraction": dual["shared_dom_frac"],
            "selection_overlap_mean": dual["overlap_mean"],
            "separation_mean": dual["sep_mean"], "separation_begin": dual["sep_begin"],
            "separation_mid": dual["sep_mid"],
            "separation_peak_region": dual["sep_peak_region"],
            "separation_end": dual["sep_end"],
            "competition_adjust_mean": dual["comp_tv_mean"],
            "latent_scale": dinfo["sref"],
            "pca_explained_1": float(dinfo["pca_evr"][0]),
            "pca_explained_2": float(dinfo["pca_evr"][1]),
            "segment_fit_ratio_min": float(fr.min()),
            "segment_fit_ratio_median": float(np.median(fr)),
            "segment_fit_ratio_max": float(fr.max()),
            "segments_capped": dinfo["capped"],
            "segments_windowed": int(sum(dinfo["windowed"])),
            "read_coverage_L": dinfo["coverage"][0], "read_coverage_R": dinfo["coverage"][1],
            "read_coverage_start_only_L": dinfo["coverage_start_only"][0],
            "read_coverage_start_only_R": dinfo["coverage_start_only"][1]})
        # step_stats in the v1.5.1 shape (voice L carries the shared phase
        # counts; mixing statistics cover both voices)
        step_stats = [{"mode": r["phase"], "dominant": r["dominant"],
                       "attn_tv": r["attn_tv"], "max_weight": r["dom_w"],
                       "aligned": rl["aligned"] + r["aligned"],
                       "flipped": rl["flipped"] + r["flipped"],
                       "mix_gain": 0.5 * (rl["mix_gain"] + r["mix_gain"])}
                      for r, rl in zip(recs[0], recs[1])]
        step_stats[0]["xfade_rho_mean"] = (float(np.mean(dinfo["xfade_rhos"]))
                                           if dinfo["xfade_rhos"] else 0.0)
        step_stats[0]["raw_samples"] = int(output.shape[0])   # no global resize
        if args.viz_tsv:
            write_dual_tsv(args.viz_tsv, recs, events, Z, dinfo, sr)
    print("    Used %d/%d steps | %.2fs | peak=%.4f" % (
        len(step_stats), len(plan),
        output.shape[0] / sr, np.max(np.abs(output))))

    # ── Stage 5: Output ────────────────────────────────────────────────────
    print("  [SAL 5/5] Loudness compensation + writing output...")
    pre_rms = float(np.sqrt(np.mean(output.astype(np.float64) ** 2)))
    output  = _rms_compensate(output, ref_rms, args.normalize_mode)
    # Global Energy_scale as a master gain AFTER loudness normalization, so it
    # is not cancelled by it. Peak-guarded to avoid hard clipping on boosts.
    if abs(args.plan_eng_scale - 1.0) > 1e-6:
        output = output * float(args.plan_eng_scale)
        peak = float(np.max(np.abs(output))) if output.size else 0.0
        if peak > 0.99:
            output = output * (0.99 / peak)
    out_rms = float(np.sqrt(np.mean(output.astype(np.float64) ** 2)))
    output_channels = 1 if output.ndim == 1 else output.shape[1]
    if dual is not None:
        o64 = output.astype(np.float64)
        dual["peak_L"], dual["peak_R"] = float(np.max(np.abs(o64[:, 0]))), float(np.max(np.abs(o64[:, 1])))
        dual["rms_L"] = float(np.sqrt(np.mean(o64[:, 0] ** 2)))
        dual["rms_R"] = float(np.sqrt(np.mean(o64[:, 1] ** 2)))
        den = np.sqrt(np.sum(o64[:, 0] ** 2) * np.sum(o64[:, 1] ** 2))
        dual["lr_correlation"] = float(np.sum(o64[:, 0] * o64[:, 1]) / den) if den > 1e-20 else 0.0
        dual["samples_L"] = dual["samples_R"] = int(output.shape[0])
    print("    %s: RMS %.4f -> %.4f (ref %.4f)  eng_scale=%.2f  ch=%d" % (
        args.normalize_mode, pre_rms, out_rms, ref_rms, args.plan_eng_scale, output_channels))

    # FLOAT avoids a second PCM16 quantisation on the Python -> Praat bridge.
    sf.write(args.output_wav, output, sr, subtype="FLOAT")
    write_stats(args.stats_txt, events, plan, losses, step_stats,
                sr, output.shape[0] / sr,
                heads, H_mean, args.pitch_mode, args.normalize_mode,
                ref_rms, out_rms, warnings_list,
                analysis_channel, input_channels, output_channels, dual=dual)

    # Cleanup: delete Praat-created temp files only
    if args.cleanup:
        for path in [args.input_wav, args.events_csv] + ([args_file] if args_file else []):
            if os.path.basename(path).startswith(TEMP_PREFIX) and os.path.exists(path):
                os.remove(path)
                print("    Deleted: %s" % path)

    print("OK: %s" % args.output_wav)


if __name__ == "__main__":
    main()
