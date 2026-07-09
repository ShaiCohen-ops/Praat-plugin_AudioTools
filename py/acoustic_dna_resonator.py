"""
acoustic_dna_resonator.py — Acoustic DNA Resonator (Differentiable FDN)

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University
Version: 0.2.2 (2026)

Changelog v0.2 — the "Praat freezes forever" release:
  * transfer() no longer builds (n_freq, n, n) complex tensors and batch-
    LU-solves them. The feedback matrix is a Householder reflector, so
    I - D(z)A = (I - D) + 2 D v v^T is DIAGONAL PLUS RANK-1 and the exact
    solve is Sherman-Morrison: O(n) per frequency bin instead of O(n^3),
    all elementwise. Verified identical to torch.linalg.solve to 1e-15
    relative. The final render previously materialized ~0.5 GB (n=16) to
    ~2.4 GB (n=24) of complex128 per tensor — the machine-thrashing part
    of the freeze. Now it is (n_freq, n): a few tens of MB.
  * Constant per-(n_fft, sr) grids (delay phases, z^-1) are cached on the
    module instead of being rebuilt every epoch.
  * The target's multi-resolution STFT magnitudes are computed ONCE, not
    once per epoch (they never change).
  * band_decay_loss vectorized: one (n_bands, n_freq) mask matmul and a
    closed-form vectorized slope, replacing the 24-iteration Python loop
    of small autograd ops per epoch.
  * Progress file (--progress_file): "epoch=I/N loss=..." overwritten
    during training so the Praat side (and the user) can see liveness.
  * Log file (--log_file): all prints mirrored; on any exception the
    traceback lands there so Praat can show it (showPyLog pattern).
  * Device safety: target tensors moved to the model device; the decay
    regularizer allocates on ir.device (CUDA runs crashed before).
  * Per-stage wall times reported in stats.txt (analyze/train/render).
  * v0.2.2: multichannel inputs fully processed. The old front-end
    exported CHANNEL 1 ONLY (channels 2..N discarded). Now the full
    file arrives; analysis/training use the mixdown, and when
    out channels == in channels each output channel is excited by its
    own input channel (dry image preserved per channel too).
  * v0.2.1: true multichannel output (up to 8 channels). Channel 0 is
    the exact trained tap; further channels read the same trained delay
    lines through seeded unit-norm tap vectors — properly decorrelated
    taps of one resonator. The old path rolled a single IR by 3*c
    samples (~0.07 ms), i.e. near-identical copies.

Usage (called by Praat, not directly):
    python acoustic_dna_resonator.py input.wav events.csv output.wav stats.txt
        --fdn_size 16 --ir_duration 4.0 --epochs 800 --loss stft_decay
        --excitation_mode self [options]

    events.csv may be the literal string "none" if no TextGrid was selected —
    the whole file is then treated as a single analysis segment.

Architecture:
    Stage 1 — Load audio (mono), optional event table
    Stage 2 — Analyze: STFT / spectral envelope / per-band decay curves /
              modal peaks (the "Acoustic DNA" of the sound)
    Stage 3 — Build a differentiable FDN (fixed prime delay lengths,
              Householder-parameterized orthogonal feedback matrix,
              one-pole shelf damping filters, trainable in/out gains)
    Stage 4 — Train the FDN (at a low internal sample rate for speed) so its
              rendered impulse response matches the analyzed STFT + per-band
              decay of the input
    Stage 5 — Render: convolve the ORIGINAL input audio through the trained
              FDN's full-resolution impulse response ("self" excitation),
              dry/wet mix, optional multichannel widening
    Stage 6 — Normalize, write output.wav
    Stage 7 — Write stats.txt (scalars + indexed dumps for Praat viz panels)
    Stage 8 — Optional cleanup of Praat-created temp files

v0.1 scope (see AcousticDNAResonator_ImplementationPlan.md §9):
    - feedback_param: householder only
    - damping_mode:   one-pole shelf only
    - excitation_mode: self only
    - loss:           stft_decay only (multi-res STFT + per-band decay rate)
    - delay_set:      prime only

Model parameters are physically scaled (delays in seconds, damping cutoffs in
Hz), so training can run at a cheap internal sample rate (TRAIN_SR) while the
final render happens at the input file's native sample rate using the exact
same trained weights — no resampling of the model itself is needed.

Requires: numpy, scipy, soundfile, torch (torch>=1.10 for batched complex
`torch.linalg.solve`). No flamo/pyFDN dependency in v0.1 — the FDN core is a
small self-contained torch.nn.Module (see plan doc for how to swap in flamo).
"""

import sys
import os
import csv
import math
import time
import traceback

_LOG_FILE = None


def set_log_file(path):
    global _LOG_FILE
    if path and path.strip().lower() != "none":
        _LOG_FILE = path
        try:
            open(_LOG_FILE, "w").close()
        except OSError:
            _LOG_FILE = None


def log(msg):
    print(msg)
    sys.stdout.flush()
    if _LOG_FILE:
        try:
            with open(_LOG_FILE, "a") as f:
                f.write(msg + "\n")
        except OSError:
            pass

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
TRAIN_SR            = 8000     # internal sample rate used only for training loss
TRAIN_IR_SECONDS_CAP = 1.5     # cap on IR length used during training (speed)
N_BANDS_DEFAULT      = 24      # log-spaced bands for decay-curve analysis
N_MODES_DEFAULT      = 12      # informational modal peaks reported in stats
STFT_FFT_SIZES       = [512, 1024, 2048]   # multi-resolution STFT loss

# Prefix used by Praat for all temp files it creates.
# Python only deletes files that start with this prefix.
PRAAT_TEMP_PREFIX = "temp_dnares_"


# ═══════════════════════════════════════════════════════════════════════════
# Utilities
# ═══════════════════════════════════════════════════════════════════════════

def check_dependencies():
    missing = []
    for pkg in ["numpy", "soundfile", "scipy", "torch"]:
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


def next_pow2(n):
    n = max(int(n), 1)
    return 1 if n <= 1 else 2 ** int(math.ceil(math.log2(n)))


def load_event_table(csv_path):
    """Optional. Returns a list of (start, end) tuples, or None if absent."""
    if csv_path is None or csv_path.strip().lower() == "none":
        return None
    if not os.path.isfile(csv_path):
        return None
    events = []
    with open(csv_path, newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                s = float(row.get("start_time", row.get("tmin", 0.0)))
                e = float(row.get("end_time",   row.get("tmax", 0.0)))
                if e > s:
                    events.append((s, e))
            except (TypeError, ValueError):
                continue
    return events if events else None


# ═══════════════════════════════════════════════════════════════════════════
# Stage 2 — Analysis ("Acoustic DNA" extraction)
# ═══════════════════════════════════════════════════════════════════════════

def choose_delays_seconds(n):
    """
    Fixed (non-trainable) delay lengths, expressed in SECONDS so they can be
    re-quantized to samples at whatever sample rate is active (TRAIN_SR at
    train time, native sr at render time) without changing the model.

    v0.1 delay_set: prime only. Primes chosen in a range that gives delays
    roughly between ~8ms and ~55ms at a nominal 44100 Hz reference, spread to
    minimize small common factors.
    """
    primes = [353, 401, 457, 509, 571, 631, 701, 761, 823, 887,
              953, 1019, 1087, 1153, 1229, 1301, 1373, 1451, 1523, 1601,
              1679, 1759, 1847, 1931, 2017, 2099, 2179, 2267, 2351, 2437]
    ref_sr = 44100.0
    chosen = primes[:n] if n <= len(primes) else (primes * (n // len(primes) + 1))[:n]
    return [p / ref_sr for p in chosen]


def band_edges_hz(sr, n_bands, fmin=40.0):
    fmax = sr / 2.0 * 0.98
    edges = np.geomspace(fmin, fmax, n_bands + 1)
    return edges


def analyze_audio(audio, sr, n_bands=N_BANDS_DEFAULT, n_modes=N_MODES_DEFAULT):
    """
    Returns a dict with:
        stft_mag        : (n_freq, n_time) magnitude STFT (linear)
        stft_freqs       : (n_freq,) Hz
        band_edges       : (n_bands+1,) Hz
        band_energy_env  : (n_bands, n_time) per-band energy envelope
        band_tau         : (n_bands,) estimated decay time constant (sec)
        band_times       : (n_time,) sec, time axis of band_energy_env
        modal_table      : list of dicts {freq, amplitude, decay_rate, bandwidth}
    """
    n_fft = 2048
    hop = 512
    freqs, times, Z = signal.stft(audio, fs=sr, nperseg=n_fft, noverlap=n_fft - hop)
    mag = np.abs(Z)

    edges = band_edges_hz(sr, n_bands)
    band_energy_env = np.zeros((n_bands, mag.shape[1]))
    band_tau = np.zeros(n_bands)
    for b in range(n_bands):
        lo, hi = edges[b], edges[b + 1]
        band_mask = (freqs >= lo) & (freqs < hi)
        if not np.any(band_mask):
            continue
        env = np.sqrt(np.mean(mag[band_mask, :] ** 2, axis=0)) + 1e-8
        band_energy_env[b, :] = env
        # fit log-linear decay: log(env) ~ slope * t + const
        log_env = np.log(env)
        if len(times) >= 2 and np.ptp(log_env) > 1e-6:
            slope, _ = np.polyfit(times, log_env, 1)
            slope = min(slope, -1e-4)  # guard against non-decaying / growing fits
            band_tau[b] = -1.0 / slope
        else:
            band_tau[b] = times[-1] if len(times) else 0.5

    # informational modal peaks from the time-averaged spectrum
    mean_mag_db = 20 * np.log10(np.mean(mag, axis=1) + 1e-8)
    peak_idx, props = signal.find_peaks(mean_mag_db, prominence=3.0, distance=3)
    order = np.argsort(mean_mag_db[peak_idx])[::-1][:n_modes]
    modal_table = []
    for i in order:
        pidx = peak_idx[i]
        f0 = freqs[pidx]
        amp = mean_mag_db[pidx]
        # -3dB half-width around the peak, in bins -> Hz
        half = amp - 3.0
        lo_i, hi_i = pidx, pidx
        while lo_i > 0 and mean_mag_db[lo_i] > half:
            lo_i -= 1
        while hi_i < len(mean_mag_db) - 1 and mean_mag_db[hi_i] > half:
            hi_i += 1
        bw = max(freqs[hi_i] - freqs[lo_i], sr / n_fft)
        band_i = min(int(np.searchsorted(edges, f0) - 1), n_bands - 1)
        band_i = max(band_i, 0)
        modal_table.append({
            "freq": float(f0), "amplitude": float(amp),
            "decay_rate": float(1.0 / max(band_tau[band_i], 1e-3)),
            "bandwidth": float(bw),
        })

    return {
        "stft_mag": mag, "stft_freqs": freqs,
        "band_edges": edges, "band_energy_env": band_energy_env,
        "band_tau": band_tau, "band_times": times,
        "modal_table": modal_table,
    }


# ═══════════════════════════════════════════════════════════════════════════
# Stage 3 — Differentiable FDN
# ═══════════════════════════════════════════════════════════════════════════

def build_fdn_model(n, seed):
    torch.manual_seed(seed)

    class DifferentiableFDN(torch.nn.Module):
        def __init__(self, n_lines, delay_seconds):
            super().__init__()
            self.n = n_lines
            self.delay_seconds = delay_seconds  # python list, fixed, not a Parameter

            self.householder_vec = torch.nn.Parameter(torch.randn(n_lines))

            # damping: g0 in (0.05, 0.999) per round-trip; cutoff in (200, ~nyquist) Hz
            self.damping_g0_raw     = torch.nn.Parameter(torch.zeros(n_lines))
            self.damping_cutoff_raw = torch.nn.Parameter(torch.zeros(n_lines))

            self.input_gains_raw  = torch.nn.Parameter(torch.randn(n_lines) * 0.5)
            self.output_gains_raw = torch.nn.Parameter(torch.randn(n_lines) * 0.5)

        def feedback_matrix(self):
            v = self.householder_vec / (self.householder_vec.norm() + 1e-8)
            eye = torch.eye(self.n, dtype=v.dtype, device=v.device)
            return eye - 2.0 * torch.outer(v, v)   # orthogonal by construction

        def damping_params(self, sr, nyquist_guard=0.98):
            g0 = 0.05 + 0.949 * torch.sigmoid(self.damping_g0_raw)          # (0.05, 0.999)
            fmax = sr * 0.5 * nyquist_guard
            cutoff_hz = 200.0 + (fmax - 200.0) * torch.sigmoid(self.damping_cutoff_raw)
            return g0, cutoff_hz

        def gains(self, scale=1.2):
            # tanh soft-bound: differentiable gain clipping (stability, plan §7)
            return (scale * torch.tanh(self.input_gains_raw),
                    scale * torch.tanh(self.output_gains_raw))

        def _grids(self, n_fft, sr):
            """Constant per-(n_fft, sr) tensors, cached across epochs:
            delay phase factors and z^-1 grid. These never change during
            training (delays are fixed), so rebuilding them every epoch
            was pure waste."""
            key = (int(n_fft), int(sr))
            cache = getattr(self, "_grid_cache", None)
            if cache is None:
                cache = {}
                self._grid_cache = cache
            if key not in cache:
                device = self.householder_vec.device
                k = torch.arange(0, n_fft // 2 + 1, device=device,
                                 dtype=torch.float64)
                two_pi_k_over_n = 2.0 * math.pi * k / n_fft
                delay_samples = torch.tensor(
                    [round(d * sr) for d in self.delay_seconds],
                    device=device, dtype=torch.float64)
                phase = torch.exp(-1j * torch.outer(two_pi_k_over_n,
                                                    delay_samples))
                z_inv = torch.exp(-1j * two_pi_k_over_n).unsqueeze(1)
                cache[key] = (phase, z_inv)
            return cache[key]

        def line_spectra(self, n_fft, sr):
            """Per-line output spectra x, shape (n_freq, n) — the FDN state
            BEFORE the output tap. Shared by training (single tap) and the
            multichannel render (many taps of the same trained lines)."""
            g0, cutoff_hz = self.damping_params(sr)
            a_pole = torch.exp(-2.0 * math.pi * cutoff_hz.to(torch.float64) / sr)
            in_g, _ = self.gains()

            phase, z_inv = self._grids(n_fft, sr)

            a_pole_c = a_pole.to(torch.complex128).unsqueeze(0)                # (1,n)
            g0_c = g0.to(torch.complex128).unsqueeze(0)                        # (1,n)
            lp = (1.0 - a_pole_c) / (1.0 - a_pole_c * z_inv)                   # (n_freq,n)
            d = phase * (g0_c * lp)                                            # (n_freq,n) = D(z) diagonal

            v = self.householder_vec / (self.householder_vec.norm() + 1e-8)
            v_c = v.to(torch.complex128).unsqueeze(0)                          # (1,n)
            in_c = in_g.to(torch.complex128).unsqueeze(0)                      # (1,n)

            b = 1.0 - d                                                        # diagonal of B = I - D
            binv_r = (d * in_c) / b                                            # B^-1 rhs
            binv_u = (2.0 * d * v_c) / b                                       # B^-1 u,  u = 2 D v
            denom = 1.0 + (binv_u * v_c).sum(-1, keepdim=True)                 # 1 + v^T B^-1 u
            x = binv_r - binv_u * ((binv_r * v_c).sum(-1, keepdim=True) / denom)
            return x                                                           # (n_freq, n)

        def transfer(self, n_fft, sr):
            """Complex frequency response, shape (n_fft//2 + 1,).

            v0.2: the feedback matrix is a Householder reflector
            A = I - 2vv^T, so the per-bin system
                (I - D(z) A) x = D(z) g_in
            has I - D A = (I - D) + 2 D v v^T: DIAGONAL + RANK-1.
            Sherman-Morrison gives the exact inverse with elementwise
            ops only — O(n) per bin instead of a batched O(n^3) LU,
            and no (n_freq, n, n) tensor is ever materialized (the old
            path allocated ~0.5-2.4 GB at render time). Verified equal
            to torch.linalg.solve to ~1e-15 relative error.
            """
            x = self.line_spectra(n_fft, sr)
            _, out_g = self.gains()
            return (x * out_g.to(torch.complex128).unsqueeze(0)).sum(-1)

        def render_irs_multi(self, ir_len_samples, sr, n_channels, seed):
            """v0.2.1: true multichannel IRs. Channel 0 is the exact
            trained output tap; channels 1..C-1 read the SAME trained
            delay lines through different seeded unit-norm tap vectors
            (scaled to sqrt(n) so expected energy matches the all-ones
            tap). Decorrelated by construction — unlike the old
            np.roll(ir, 3*c), which produced near-identical copies
            0.07 ms apart."""
            n_fft = next_pow2(ir_len_samples)
            x = self.line_spectra(n_fft, sr)                          # (n_freq, n)
            _, out_g = self.gains()
            g = out_g.to(torch.float64)

            taps = torch.ones(n_channels, self.n, dtype=torch.float64,
                              device=x.device)
            if n_channels > 1:
                gen = torch.Generator(device="cpu").manual_seed(int(seed) + 9173)
                r = torch.randn(n_channels - 1, self.n, generator=gen,
                                dtype=torch.float64)
                r = r / (r.norm(dim=1, keepdim=True) + 1e-12) * math.sqrt(self.n)
                taps[1:] = r.to(x.device)

            weights = (taps * g.unsqueeze(0)).to(torch.complex128)    # (C, n)
            specs = torch.einsum("fn,cn->cf", x, weights)             # (C, n_freq)
            irs = torch.fft.irfft(specs, n=n_fft, dim=-1)             # (C, n_fft)
            return irs[:, :ir_len_samples].to(torch.float32)

        def render_ir(self, ir_len_samples, sr):
            n_fft = next_pow2(ir_len_samples)
            spec = self.transfer(n_fft, sr)
            ir = torch.fft.irfft(spec, n=n_fft)
            return ir[:ir_len_samples].to(torch.float32)

    return DifferentiableFDN(n, choose_delays_seconds(n))


# ═══════════════════════════════════════════════════════════════════════════
# Stage 4 — Loss + Training
# ═══════════════════════════════════════════════════════════════════════════

def band_decay_loss(ir, target_log_tau, band_mask, band_counts, sr):
    """Compare per-band decay time constants of the rendered IR vs. target.

    v0.2: fully vectorized. `band_mask` is a constant (n_bands, n_freq)
    0/1 matrix and `target_log_tau` a constant (n_bands,) tensor, both
    precomputed once in train_fdn — the old version rebuilt masks and
    looped over 24 bands of small autograd ops every epoch.
    """
    n_fft = min(1024, len(ir))
    hop = n_fft // 4
    win = torch.hann_window(n_fft, device=ir.device)
    S = torch.stft(ir, n_fft=n_fft, hop_length=hop, window=win,
                    return_complex=True, center=True)
    mag2 = torch.abs(S) ** 2                                   # (n_freq, n_time)
    times = torch.arange(mag2.shape[1], device=ir.device,
                         dtype=torch.float32) * hop / sr
    if mag2.shape[1] < 2:
        return torch.tensor(0.0, device=ir.device)

    env = torch.sqrt(band_mask @ mag2 / band_counts.unsqueeze(1)) + 1e-6
    log_env = torch.log(env)                                   # (n_bands, n_time)

    t = times - times.mean()
    slope = (log_env - log_env.mean(dim=1, keepdim=True)) @ t
    slope = slope / (torch.sum(t * t) + 1e-8)                  # (n_bands,)
    slope = torch.clamp(slope, max=-1e-4)
    tau_pred = -1.0 / slope
    valid = band_counts > 0
    diffs = torch.abs(torch.log(tau_pred + 1e-3) - target_log_tau)
    return diffs[valid].mean() if valid.any() else torch.tensor(0.0, device=ir.device)


def energy_decay_regularizer(ir, sr, floor_db=-60.0, tail_frac=0.15):
    """Penalize IR energy that hasn't decayed enough by the end of the window
    (plan §7 stability regularizer — discourages near-undamped solutions)."""
    n = len(ir)
    tail = ir[int(n * (1 - tail_frac)):]
    if len(tail) < 8:
        return torch.tensor(0.0, device=ir.device)
    head_rms = torch.sqrt(torch.mean(ir[:max(n // 20, 8)] ** 2) + 1e-10)
    tail_rms = torch.sqrt(torch.mean(tail ** 2) + 1e-10)
    tail_db = 20.0 * torch.log10(tail_rms / (head_rms + 1e-10) + 1e-10)
    return torch.relu(tail_db - floor_db)


def precompute_target_mags(target_t):
    """v0.2: the target's multi-resolution log-magnitudes never change,
    so compute them once instead of once per epoch."""
    mags = {}
    for n_fft in STFT_FFT_SIZES:
        nf = min(n_fft, len(target_t))
        if nf < 32:
            continue
        hop = nf // 4
        win = torch.hann_window(nf, device=target_t.device)
        S = torch.stft(target_t, n_fft=nf, hop_length=hop, window=win,
                       return_complex=True, center=True)
        mags[n_fft] = torch.log(torch.abs(S) + 1e-5)
    return mags


def multires_stft_loss_fast(ir, target_mags):
    loss = 0.0
    for n_fft, mag_tg in target_mags.items():
        nf = min(n_fft, len(ir))
        if nf < 32:
            continue
        hop = nf // 4
        win = torch.hann_window(nf, device=ir.device)
        S_ir = torch.stft(ir, n_fft=nf, hop_length=hop, window=win,
                           return_complex=True, center=True)
        mag_ir = torch.log(torch.abs(S_ir) + 1e-5)
        m = min(mag_ir.shape[-1], mag_tg.shape[-1])
        loss = loss + torch.mean(torch.abs(mag_ir[..., :m] - mag_tg[..., :m]))
    return loss


def train_fdn(model, target_audio, sr_native, analysis, args,
              progress_file=None):
    device = next(model.parameters()).device
    resampled = signal.resample_poly(target_audio, TRAIN_SR, sr_native)
    train_len = int(min(args.ir_duration, TRAIN_IR_SECONDS_CAP) * TRAIN_SR)
    train_len = max(train_len, 512)
    if len(resampled) < train_len:
        resampled = np.pad(resampled, (0, train_len - len(resampled)))
    target_t = torch.tensor(resampled[:train_len], dtype=torch.float32,
                            device=device)

    # v0.2: all training constants precomputed ONCE
    target_mags = precompute_target_mags(target_t)

    edges = band_edges_hz(TRAIN_SR, len(analysis["band_tau"]))
    band_tau = analysis["band_tau"]
    n_fft_decay = min(1024, train_len)
    n_freq_decay = n_fft_decay // 2 + 1
    freqs = torch.linspace(0, TRAIN_SR / 2, n_freq_decay, device=device)
    n_bands = len(band_tau)
    band_mask = torch.zeros(n_bands, n_freq_decay, device=device)
    for b in range(n_bands):
        band_mask[b] = ((freqs >= float(edges[b])) &
                        (freqs < float(edges[b + 1]))).float()
    band_counts = band_mask.sum(dim=1).clamp(min=1)
    ir_dur_train = train_len / TRAIN_SR
    target_log_tau = torch.tensor(
        [math.log((float(tb) if tb > 1e-4 else ir_dur_train + 1e-3) + 1e-3)
         for tb in band_tau], device=device)

    opt = torch.optim.Adam(model.parameters(), lr=args.lr)
    losses = []
    warnings = []
    best_state = None
    best_loss = float("inf")
    progress_every = max(1, args.epochs // 100)

    for epoch in range(args.epochs):
        opt.zero_grad()
        ir = model.render_ir(train_len, TRAIN_SR)
        l_stft = multires_stft_loss_fast(ir, target_mags)
        l_decay = band_decay_loss(ir, target_log_tau, band_mask,
                                   band_counts, TRAIN_SR)
        l_reg = energy_decay_regularizer(ir, TRAIN_SR)
        loss = l_stft + 0.5 * l_decay + 0.1 * l_reg

        if not torch.isfinite(loss):
            warnings.append("non-finite loss at epoch %d; reverting to best checkpoint" % epoch)
            break

        loss.backward()
        torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)
        opt.step()

        loss_val = float(loss.item())
        losses.append(loss_val)
        if loss_val < best_loss:
            best_loss = loss_val
            best_state = {k: v.detach().clone() for k, v in model.state_dict().items()}

        # v0.2: liveness signal for the Praat side / anxious composer
        if progress_file and (epoch % progress_every == 0
                              or epoch == args.epochs - 1):
            try:
                with open(progress_file, "w") as pf:
                    pf.write("epoch=%d/%d loss=%.5f best=%.5f\n"
                             % (epoch + 1, args.epochs, loss_val, best_loss))
            except OSError:
                pass

    if best_state is not None:
        model.load_state_dict(best_state)
    else:
        warnings.append("training produced no finite loss; using initial (untrained) weights")

    return losses, warnings


# ═══════════════════════════════════════════════════════════════════════════
# Stage 5 — Render
# ═══════════════════════════════════════════════════════════════════════════

def render_output(model, input_mono, input_mc, sr, args, out_channels):
    """v0.2.2: when the output channel count matches the input channel
    count (> 1), each output channel is excited by its OWN input
    channel through its own decorrelated tap, and the per-channel dry
    signal is that same input channel -- all inputs processed, spatial
    image preserved. Otherwise every channel is excited by the mono
    mixdown (previous behaviour; also the mono-input case)."""
    ir_len = int(args.ir_duration * sr)
    ir_len = max(ir_len, 256)
    with torch.no_grad():
        irs = model.render_irs_multi(ir_len, sr, out_channels,
                                     args.seed).cpu().numpy()   # (C, L)
    ir_mono = irs[0]

    # safety net (plan §7): pathological blow-up guard — one shared
    # factor so inter-channel balance is preserved
    peak = np.max(np.abs(irs)) + 1e-8
    if peak > 4.0:
        irs = irs / peak * 4.0
        ir_mono = irs[0]

    in_channels = input_mc.shape[1]
    per_channel = (in_channels == out_channels and out_channels > 1)

    n_in = input_mc.shape[0]
    max_len = n_in + ir_len - 1
    dw = np.clip(args.dry_wet, 0.0, 1.0)
    dry_gain = math.cos(dw * math.pi / 2.0)
    wet_gain = math.sin(dw * math.pi / 2.0)

    out_channels_arr = []
    for c in range(out_channels):
        exc = input_mc[:, c] if per_channel else input_mono
        wet = signal.fftconvolve(exc, irs[c])[:max_len]
        w = np.zeros(max_len)
        w[:len(wet)] = wet
        dry = np.zeros(max_len)
        dry[:n_in] = exc
        out_channels_arr.append(dry_gain * dry + wet_gain * w)

    output = np.stack(out_channels_arr, axis=-1) if out_channels > 1 else out_channels_arr[0]
    return output, ir_mono, per_channel


def normalize_output(output, ref_rms, mode):
    if mode == "none":
        return output
    flat = output if output.ndim == 1 else output.reshape(-1)
    if mode == "peak":
        peak = np.max(np.abs(flat)) + 1e-8
        target_peak = 0.98
        return output * (target_peak / peak)
    if mode in ("rms", "loudness"):
        cur_rms = np.sqrt(np.mean(flat ** 2)) + 1e-8
        gain = ref_rms / cur_rms
        gain = min(gain, 10.0)  # guard against extreme boosts on near-silent IRs
        return output * gain
    return output


# ═══════════════════════════════════════════════════════════════════════════
# Stage 7 — stats.txt
# ═══════════════════════════════════════════════════════════════════════════

def rt60_style_estimate(ir, sr, floor_db=-60.0):
    energy = ir ** 2
    cum = np.cumsum(energy[::-1])[::-1]
    cum = cum / (cum[0] + 1e-12)
    db = 10 * np.log10(cum + 1e-12)
    below = np.where(db < floor_db)[0]
    if len(below) == 0:
        return len(ir) / sr
    return below[0] / sr


def write_stats(path, args, sr, delays_samples, losses, warnings,
                 ref_rms, out_rms, out_duration, decay_estimate,
                 modal_table, band_edges, band_tau, timings=None):
    timings = timings or {}
    with open(path, "w") as f:
        f.write("input_file=%s\n" % os.path.basename(args.input_wav))
        f.write("fdn_size=%d\n" % args.fdn_size)
        f.write("delay_lengths=%s\n" % ",".join(str(int(d)) for d in delays_samples))
        f.write("delay_set=%s\n" % args.delay_set)
        f.write("feedback_param=%s\n" % args.feedback_param)
        f.write("damping_mode=%s\n" % args.damping_mode)
        f.write("epochs=%d\n" % args.epochs)
        f.write("initial_loss=%.6f\n" % (losses[0] if losses else 0.0))
        f.write("final_loss=%.6f\n" % (losses[-1] if losses else 0.0))
        f.write("decay_estimate_ms=%.1f\n" % (decay_estimate * 1000.0))
        f.write("stability_warning=%s\n" % ("; ".join(warnings) if warnings else "none"))
        f.write("excitation_mode=%s\n" % args.excitation_mode)
        f.write("dry_wet=%.3f\n" % args.dry_wet)
        f.write("normalize_mode=%s\n" % args.normalize_mode)
        f.write("rms_input=%.6f\n" % ref_rms)
        f.write("rms_output=%.6f\n" % out_rms)
        f.write("output_duration=%.3f\n" % out_duration)
        f.write("out_channels=%d\n" % args.out_channels)
        f.write("in_channels=%d\n" % getattr(args, "_in_channels", 1))
        f.write("per_channel_excitation=%s\n"
                % ("yes" if getattr(args, "_per_channel", False) else "no"))
        f.write("seed=%d\n" % args.seed)
        f.write("analyze_seconds=%.2f\n" % timings.get("analyze", 0.0))
        f.write("train_seconds=%.2f\n" % timings.get("train", 0.0))
        f.write("render_seconds=%.2f\n" % timings.get("render", 0.0))

        # indexed dump: loss curve (for Praat viz panel)
        n_loss = min(len(losses), 400)
        stride = max(1, len(losses) // n_loss) if losses else 1
        sampled = losses[::stride][:n_loss]
        f.write("n_loss_pts=%d\n" % len(sampled))
        for i, lv in enumerate(sampled):
            f.write("loss_%d=%.6f\n" % (i, lv))

        # indexed dump: modal peaks (informational, not loss-matched in v0.1)
        f.write("n_modes_pts=%d\n" % len(modal_table))
        for i, m in enumerate(modal_table):
            f.write("mode_%d=%.2f,%.2f,%.4f,%.2f\n" %
                    (i, m["freq"], m["amplitude"], m["decay_rate"], m["bandwidth"]))

        # indexed dump: per-band decay (for bar-chart panel)
        # Bands with near-zero energy fit a near-flat (clamped) slope, which
        # would otherwise print an absurd decay time — cap for readability.
        n_bands = len(band_tau)
        decay_cap_ms = max(args.ir_duration * 3000.0, 3000.0)
        f.write("n_band_decay_pts=%d\n" % n_bands)
        for b in range(n_bands):
            center_hz = math.sqrt(band_edges[b] * band_edges[b + 1])
            ms = min(band_tau[b] * 1000.0, decay_cap_ms)
            f.write("band_%d=%.1f,%.1f\n" % (b, center_hz, ms))


# ═══════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════

def main():
    import argparse

    check_dependencies()

    global np, signal, torch
    import numpy as np_
    import scipy.signal as signal_
    import soundfile as sf
    import torch as torch_
    np = np_
    signal = signal_
    torch = torch_

    parser = argparse.ArgumentParser(
        description="Acoustic DNA Resonator — Differentiable FDN")
    parser.add_argument("input_wav")
    parser.add_argument("events_csv")
    parser.add_argument("output_wav")
    parser.add_argument("stats_txt")

    parser.add_argument("--fdn_size", type=int, default=16)
    parser.add_argument("--ir_duration", type=float, default=4.0)
    parser.add_argument("--epochs", type=int, default=800)
    parser.add_argument("--lr", type=float, default=0.01)
    parser.add_argument("--loss", type=str, default="stft_decay",
                         choices=["stft_decay"])
    parser.add_argument("--excitation_mode", type=str, default="self",
                         choices=["self", "impulse", "noise_burst"])
    parser.add_argument("--delay_set", type=str, default="prime",
                         choices=["prime", "coprime_random", "golden_ratio"])
    parser.add_argument("--feedback_param", type=str, default="householder",
                         choices=["householder", "orthogonal_cayley", "random_orthogonal"])
    parser.add_argument("--damping_mode", type=str, default="shelf",
                         choices=["shelf", "per_band"])
    parser.add_argument("--dry_wet", type=float, default=0.35)
    parser.add_argument("--normalize_mode", type=str, default="rms",
                         choices=["none", "peak", "rms", "loudness"])
    parser.add_argument("--out_channels", type=int, default=2)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--device", type=str, default="auto")
    parser.add_argument("--cleanup", action="store_true")
    parser.add_argument("--log_file", type=str, default="none")
    parser.add_argument("--progress_file", type=str, default="none")

    args = parser.parse_args()
    set_log_file(args.log_file)
    progress_file = (args.progress_file
                     if args.progress_file.strip().lower() != "none" else None)

    if args.excitation_mode != "self":
        print("NOTE: v0.1 implements excitation_mode=self only; falling back.",
              file=sys.stderr)
        args.excitation_mode = "self"
    if args.feedback_param != "householder":
        print("NOTE: v0.1 implements feedback_param=householder only; falling back.",
              file=sys.stderr)
        args.feedback_param = "householder"
    if args.damping_mode != "shelf":
        print("NOTE: v0.1 implements damping_mode=shelf only; falling back.",
              file=sys.stderr)
        args.damping_mode = "shelf"
    if args.delay_set != "prime":
        print("NOTE: v0.1 implements delay_set=prime only; falling back.",
              file=sys.stderr)
        args.delay_set = "prime"

    args.fdn_size = int(np.clip(args.fdn_size, 4, 32))
    args.out_channels = int(np.clip(args.out_channels, 1, 8))

    if args.device == "auto":
        device = "cuda" if torch.cuda.is_available() else "cpu"
    else:
        device = args.device

    audio_mc, sr = sf.read(args.input_wav, always_2d=True)   # (N, C_in)
    audio_mc = audio_mc.astype(np.float32)
    in_channels = audio_mc.shape[1]
    # mono mixdown: analysis, training target, and reference level
    audio = audio_mc.mean(axis=1)
    ref_rms = float(np.sqrt(np.mean(audio ** 2)) + 1e-8)

    events = load_event_table(args.events_csv)  # optional; not required in v0.1 loss

    log("[1/5] Analyzing input (STFT / band decay / modal peaks)...")
    t_stage = time.time()
    analysis = analyze_audio(audio, sr)
    timings = {"analyze": time.time() - t_stage}

    log("[2/5] Building differentiable FDN (n=%d)..." % args.fdn_size)
    model = build_fdn_model(args.fdn_size, args.seed).to(device)

    log("[3/5] Training (%d epochs @ internal %d Hz)..." % (args.epochs, TRAIN_SR))
    t_stage = time.time()
    losses, warnings = train_fdn(model, audio, sr, analysis, args,
                                 progress_file=progress_file)
    timings["train"] = time.time() - t_stage
    log("      training took %.1f s (%.1f ms/epoch)"
        % (timings["train"],
           1000.0 * timings["train"] / max(len(losses), 1)))

    log("[4/5] Rendering output (excitation=self, ir_duration=%.2fs)..." % args.ir_duration)
    t_stage = time.time()
    wet_raw, ir_mono, per_channel = render_output(
        model, audio, audio_mc, sr, args, args.out_channels)
    log("      per-channel excitation: %s (in=%d ch, out=%d ch)"
        % ("yes" if per_channel else "no (mixdown excitation)",
           in_channels, args.out_channels))
    timings["render"] = time.time() - t_stage
    log("      render took %.1f s" % timings["render"])
    output = normalize_output(wet_raw, ref_rms, args.normalize_mode)

    if not np.all(np.isfinite(output)):
        warnings.append("non-finite samples in render; zeroed as safety fallback")
        output = np.nan_to_num(output)

    out_flat = output if output.ndim == 1 else output.reshape(-1)
    out_rms = float(np.sqrt(np.mean(out_flat ** 2)) + 1e-8)
    out_duration = output.shape[0] / sr

    args._in_channels = in_channels
    args._per_channel = per_channel

    log("[5/5] Writing output.wav and stats.txt...")
    sf.write(args.output_wav, output, sr)

    delays_samples = [round(d * sr) for d in model.delay_seconds]
    decay_estimate = rt60_style_estimate(ir_mono, sr)

    write_stats(args.stats_txt, args, sr, delays_samples, losses, warnings,
                ref_rms, out_rms, out_duration, decay_estimate,
                analysis["modal_table"], analysis["band_edges"],
                analysis["band_tau"], timings)

    if args.cleanup:
        for p in [args.input_wav, args.events_csv]:
            if p and p.lower() != "none" and _is_praat_temp(p) and os.path.isfile(p):
                try:
                    os.remove(p)
                except OSError:
                    pass

    log("Done.")


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        # showPyLog pattern: land the traceback where Praat can find it
        tb = traceback.format_exc()
        print(tb, file=sys.stderr)
        if _LOG_FILE:
            try:
                with open(_LOG_FILE, "a") as f:
                    f.write("\nFATAL ERROR:\n" + tb)
            except OSError:
                pass
        sys.exit(1)
