"""
acoustic_dna_resonator.py — Acoustic DNA Resonator (Differentiable FDN)

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University
Version: 0.2.9 (2026)

Changelog v0.2.9 — the double-tilt fix (brightness):
  * NEW --spectral_dna (default 0.4). See the long comment in
    precompute_sparse_spectral_target. Short version: the wet signal is the
    source convolved with the resonator, so fitting the resonator's magnitude
    response to the source's spectral shape applies that shape twice and the
    output comes out much darker than the source. Measured tilt 200 Hz ->
    8 kHz on a plucked-like source: source -50.7 dB, fitted |H| -30.4 dB,
    wet output -78.2 dB. The tilts add.
  * This explains the field observation that the v0.2.5+ path sounds darker
    than the old one (spectral centroid 801 -> 461 Hz on real material) even
    though spectral_match_mae called it the BETTER fit. The metric was right
    and the objective was wrong: matching the source shape is not what makes
    a resonator sound like the source.
  * NOTE: spectral_match_mae still measures the fit to the FULL source shape,
    so it will read WORSE as spectral_dna drops. That is intended, not a
    regression — with spectral_dna < 1 the model is deliberately not trying
    to match that target.

Changelog v0.2.8 — early/late split:
  * NEW --early_ms (default 60, 0 = off). The FDN IR is faded in with a sin^2
    ramp over that window and the energy the ramp removes is handed to a
    synthetic velvet-noise early-reflection pattern. sin^2 + cos^2 = 1 and the
    energy match is exact, so the attack changes and the level does not.
  * Why: the descriptor loss constrains band decay and spectral envelope, both
    steady-state quantities. Neither says anything about the first tens of ms,
    so the attack was simply unconstrained. Measured on real material against
    the old time-domain loss: attack 68 -> 91 ms, crest 25.2 -> 18.6 dB,
    energy in the first 20 ms 4.5% -> 2.8%. This is structural, not a bug: an
    FDN cannot produce an echo before its shortest delay (8.0 ms at 44.1 kHz
    here) and is sparse until the feedback has mixed several times.
  * Prototype measurement before implementing, plucked-like source:
        no early        attack 23.4 ms
        early 40 ms     attack 13.1 ms
        early 60 ms     attack  4.6 ms
  * The early pattern is added INTO the IR, so it costs one extra vector add
    rather than a second convolution, and the QC stats measure the IR that is
    actually rendered.
  * STILL OPEN, separate problem: the new path is much darker (spectral
    centroid 801 -> 461 Hz, energy above 2 kHz 0.66% -> 0.05%) even though
    spectral_match_mae says it is the better fit. sparse_spectral_band_loss
    mean-removes both prediction and target, so it matches band SHAPE and is
    blind to how little absolute energy a band carries. The early/late split
    does not address this.

Changelog v0.2.7 — find the remaining time, don't guess at it:
  * --torch_threads (0 = auto). The descriptor loss is many tiny tensor ops;
    on a multi-core machine thread-pool sync per op can cost more than the
    arithmetic, so auto pins it to 1 thread. The legacy stft_decay loss works
    on large FFT grids and keeps the library default. Developed on a
    single-core box where this was untestable, hence the explicit flag.
  * startup_seconds is now measured and reported. Importing torch is a fixed
    multi-second cost per run on many machines and it was never counted.
  * The Praat front end now prints a full stage breakdown (engine / stats
    parsing / drawing) so the next slow run localizes itself.
  * Companion Praat fix: the stats parser was quadratic. See the .praat
    changelog — that cost was entirely outside Python and no engine timing
    could ever have shown it.

Changelog v0.2.6 — version-skew safety + reachable decays:
  * DAMPING_PARAM = "log_alpha" (new default). The damping gain used to be
    g0 = 0.05 + 0.949*sigmoid(raw), so g0 ~ 0.999 required raw ~ 8. Adam moves
    a parameter by roughly lr per step, so at the default lr=0.01 no run of a
    few hundred epochs could reach long decays at all. On a 5 s vocal-like
    source whose analyzed band decays run to several seconds, the model
    saturated at 551 ms. Parameterizing log(alpha), alpha = -ln(g0), makes a
    step a constant relative change in tau, and the same run reaches seconds.
    Measured decay_match_log_mae (lower is better), 800 epochs, lr default:
        vocal-like source : 3.04 -> 1.37   (v0.2.4 stft_decay path: 1.57)
        plucked-like      : 0.83 -> 0.51   (v0.2.4 stft_decay path: 0.96)
    The legacy stft_decay path benefits too (0.96 -> 0.46 on the second file).
    TRADE-OFF, stated plainly: spectral_match_mae gets WORSE on both test
    files (0.51 -> 0.75 and 0.57 -> 1.10). The decay term now moves much
    faster and competes with the spectral term. DESC_SPECTRAL_WEIGHT is the
    knob; a 1.0/2.0/3.0 sweep on two files was non-monotonic, so it is left
    at 1.0 rather than tuned on insufficient data. Set DAMPING_PARAM =
    "sigmoid" to revert this change exactly.

Changelog v0.2.6 — front-end/back-end version-skew safety:
  * The log file is now opened from sys.argv BEFORE argparse runs. A bad
    argument makes argparse exit(2) immediately, which previously happened
    before set_log_file() and so produced a totally silent failure: Praat saw
    no output.wav and no log, and could only say "engine failed". Any
    argument error now writes an explicit version-mismatch explanation to the
    log Praat displays.
  * Concretely: a v0.2.6 .praat sending --loss descriptor to a v0.2.4 engine
    (choices=["stft_decay"]) died exactly this way.

Changelog v0.2.5 — descriptor training (the "why is it so slow" release):
  * NEW DEFAULT --loss descriptor. The training loop no longer renders a
    time-domain impulse response at all. v0.2.4 evaluated the FDN transfer
    function on a 32768-point FFT grid (16385 complex128 bins x n lines) every
    single epoch, then threw away 20768 of the 32768 samples, in order to feed
    three losses that are all BAND-AGGREGATED descriptors. Now:
      - band decay is computed IN CLOSED FORM from the model parameters.
        For line i with delay m_i and one-pole damping H_i, the amplitude
        decay constant at frequency w is  tau_i(w) = -(m_i/sr) / ln|H_i(w)|
        (Jot's attenuation-per-delay relation). The FDN tail follows the
        slowest line, approximated by a smooth max in log-tau. No STFT, no IR.
      - the spectral-envelope loss is evaluated on a SPARSE LOG-SPACED grid
        (28 bands x 6 points = 168 frequencies). Sherman-Morrison is valid at
        any z on the unit circle, not only at FFT bins, so once no IR is
        needed the grid is free to be tiny.
    Measured per-epoch cost of the dominant solve drops ~100x. The two
    remaining terms are exactly the two quantities stats.txt already reports
    as QC (decay_match_log_mae, spectral_match_mae): we now optimize what we
    measure.
  * Training runs at NATIVE sample rate. With no time-domain IR there is no
    reason for the 8 kHz internal rate, so all 24 analysis bands are used
    (v0.2.3/0.2.4 silently dropped every band above 3.92 kHz from the decay
    term) and the separate high-frequency patch-up loss is no longer needed.
  * --loss stft_decay is retained unchanged as the legacy path for A/B.
  * Render convolution left on fftconvolve. oaconvolve was tried and measured:
    it wins ~1.7x for inputs up to ~10x the IR length but LOSES ~1.5x beyond
    that, and the render stage is 0.1-0.4 s either way. Not worth a
    size-dependent heuristic.
  * NOTE: the descriptor loss is a different objective, so initial_loss /
    final_loss in stats.txt are NOT comparable to v0.2.4 numbers. The QC
    metrics (decay_match_log_mae, spectral_match_mae) ARE comparable; they
    are computed exactly as before.

Changelog v0.2.4 — speed pass without reverting model-consistency fixes:
  * Exact final IR recursion is processed in causally safe blocks (block length <=
    shortest delay) using scipy.signal.lfilter per line. This removes the Python
    per-sample loop while remaining sample-identical to the v0.2.3 recursion.
  * Differentiable training transfer padding reduced 4x -> 2x; enough guard for
    the training window without paying for a 65536-point transfer each epoch.
  * Native broad-band spectral DNA grid reduced 4096 -> 2048 bins. The loss is
    intentionally broad-band, so this preserves its purpose at much lower cost.

Changelog v0.2.3 — model-consistency / render-accuracy pass:
  * Damping cutoff is now a PHYSICAL-HZ parameter shared by training and
    native-rate rendering. v0.2.2 remapped the same raw parameter to each
    sample rate's Nyquist, so a ~2 kHz training cutoff could become ~12 kHz
    at 48 kHz render.
  * Decay bands keep their native frequency identity during 8 kHz training;
    v0.2.2 compressed all 24 native bands into 40..3920 Hz.
  * A lightweight native-rate log-band spectral-envelope loss preserves the
    high-frequency part of the source DNA that the 8 kHz time loss cannot see.
  * Final IRs are rendered by an exact time-domain Householder FDN recursion,
    eliminating frequency-sampling/time-aliasing on long decays.
  * Robust multichannel reference: normal material uses the mean mixdown, but
    severe phase cancellation falls back to the strongest channel; RMS
    normalization references true multichannel RMS rather than mixdown RMS.
  * Decay estimation now fits post-peak tails; the old -60 dB-in-1.5 s
    regularizer (which defeated long-decay presets) is replaced by a tiny
    stability-margin penalty only near g0=0.999.
  * Output interchange WAV is 32-bit float; v0.2.2 used soundfile's default
    PCM_16 and could silently clip normalize=none / high-crest-factor output.
  * stats now include direct input-vs-trained-IR decay and spectral-shape QC.
  * Short-input STFT handling fixed; best-checkpoint loss is reported as the
    final loss; plotted loss subsampling always includes the final epoch.

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

    events.csv may be the literal string "none". In v0.2.3 event rows are
    retained as metadata only; they do not alter the sonic analysis/training.

Architecture:
    Stage 1 — Load multichannel audio, derive a robust mono analysis reference,
              optionally read event metadata
    Stage 2 — Analyze: STFT / spectral envelope / per-band decay curves /
              modal peaks (the "Acoustic DNA" of the sound)
    Stage 3 — Build a differentiable FDN (fixed prime delay lengths,
              Householder-parameterized orthogonal feedback matrix,
              one-pole shelf damping filters, trainable in/out gains)
    Stage 4 — Train with low-rate time/decay losses plus a native-rate broad
              log-band spectral-envelope loss (preserves DNA above 4 kHz)
    Stage 5 — Render: convolve the ORIGINAL input audio through the trained
              FDN's full-resolution impulse response ("self" excitation),
              dry/wet mix, optional multichannel widening
    Stage 6 — Normalize, write 32-bit float output.wav (no hidden PCM clipping)
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

Requires: numpy, scipy, soundfile, torch. No flamo/pyFDN dependency — the
FDN core is a small self-contained torch.nn.Module.
"""

import sys
import os
import csv
import math
import time
import traceback

_T_PROCESS_START = time.time()
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
TRAIN_TRANSFER_PADDING = 2       # speed/accuracy compromise for differentiable training IR
SPECTRAL_MATCH_FFT     = 2048    # broad-band loss does not require a dense native-rate grid
SPECTRAL_MATCH_BANDS   = 18      # broad log bands: robust, not comb-by-comb matching
SPECTRAL_MATCH_WEIGHT  = 0.35

# --- descriptor training (v0.2.5 default path) -----------------------------
DESC_SPECTRAL_BANDS    = 28     # log bands for the sparse spectral-shape loss
DESC_POINTS_PER_BAND   = 6      # evaluation frequencies inside each band
DESC_SPECTRAL_WEIGHT   = 1.0    # decay and spectral terms are both log-MAE
DESC_DECAY_SPAN        = 6.9    # fit horizon in units of tau (= -60 dB, as the analyzer does)
DESC_DECAY_TIME_PTS    = 64     # time points in the closed-form envelope fit

# Damping parameterization. "log_alpha" parameterizes the attenuation per
# delay in the log domain, so a uniform optimizer step is a uniform RELATIVE
# step in decay time. "sigmoid" is the pre-0.2.6 form; set it here to revert.
DAMPING_PARAM          = "log_alpha"    # "log_alpha" | "sigmoid"
LOG_ALPHA_INIT         = -3.912         # raw=0 -> alpha=0.02 -> g0 ~ 0.980

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


def robust_mono_reference(audio_mc, cancellation_ratio=0.25):
    """Return a mono analysis/render reference without catastrophic phase loss.

    For ordinary multichannel material the arithmetic mean is retained. If its
    RMS falls below `cancellation_ratio` times the strongest channel RMS, the
    strongest channel is used instead. This keeps the normal stereo behavior
    while preventing anti-phase / near-anti-phase inputs from becoming silence.
    """
    if audio_mc.ndim != 2 or audio_mc.shape[1] == 1:
        return audio_mc[:, 0].copy(), "mono"
    mix = audio_mc.mean(axis=1)
    ch_rms = np.sqrt(np.mean(audio_mc.astype(np.float64) ** 2, axis=0) + 1e-16)
    strongest = int(np.argmax(ch_rms))
    mix_rms = float(np.sqrt(np.mean(mix.astype(np.float64) ** 2) + 1e-16))
    if ch_rms[strongest] > 1e-8 and mix_rms < cancellation_ratio * ch_rms[strongest]:
        return audio_mc[:, strongest].copy(), "strongest_channel_%d" % (strongest + 1)
    return mix, "mean_mixdown"


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
    audio = np.asarray(audio, dtype=np.float64)
    if audio.size < 32:
        audio = np.pad(audio, (0, 32 - audio.size))
    n_fft = min(2048, len(audio))
    hop = max(1, n_fft // 4)
    freqs, times, Z = signal.stft(audio, fs=sr, nperseg=n_fft,
                                  noverlap=n_fft - hop)
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

        # Decay means decay: fit from the strongest band-energy frame onward,
        # not across the attack + sustain + release of the whole source. Keep
        # frames down to -60 dB from that peak when available. A flat/growing
        # tail is treated as "not measurably decayed within this recording"
        # rather than being converted into the old absurd 10,000 s tau.
        peak_i = int(np.argmax(env))
        tail_env = env[peak_i:]
        tail_times = times[peak_i:] - times[peak_i]
        peak_env = float(env[peak_i])
        keep = tail_env >= max(peak_env * 1e-3, 1e-8)
        if np.count_nonzero(keep) >= 3:
            fit_t = tail_times[keep]
            fit_log = np.log(tail_env[keep])
            if np.ptp(fit_log) > 1e-6:
                slope, _ = np.polyfit(fit_t, fit_log, 1)
            else:
                slope = 0.0
        else:
            slope = 0.0

        observed_tail = float(tail_times[-1]) if len(tail_times) else 0.0
        fallback_tau = max(observed_tail, hop / float(sr), 0.05)
        if slope < -1e-4:
            tau = -1.0 / float(slope)
        else:
            tau = fallback_tau
        # Do not infer a decay many orders of magnitude longer than the
        # observation itself. Two recording durations still allows a long
        # resonant interpretation without destabilizing the target.
        tau_cap = max(0.25, 2.0 * len(audio) / float(sr))
        band_tau[b] = min(tau, tau_cap)

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

def build_fdn_model(n, seed, native_sr=44100):
    torch.manual_seed(seed)
    cutoff_max_hz = max(500.0, min(20000.0, 0.45 * float(native_sr)))

    class DifferentiableFDN(torch.nn.Module):
        def __init__(self, n_lines, delay_seconds, cutoff_max_hz):
            super().__init__()
            self.n = n_lines
            self.delay_seconds = delay_seconds  # python list, fixed, not a Parameter
            self.cutoff_min_hz = 200.0
            self.cutoff_max_hz = float(cutoff_max_hz)

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

        def damping_params(self, sr=None):
            if DAMPING_PARAM == "log_alpha":
                # alpha = -ln(g0) is the attenuation per delay, and
                # tau is proportional to 1/alpha. Parameterizing log(alpha)
                # makes an optimizer step a constant RELATIVE change in decay.
                # The old sigmoid form needed raw ~ 8 to reach g0 ~ 0.999, and
                # Adam moves a parameter by about lr per step, so at the
                # default lr=0.01 long decays were simply out of reach within
                # a few hundred epochs — regardless of which loss was used.
                alpha = torch.exp(torch.clamp(
                    self.damping_g0_raw + LOG_ALPHA_INIT, -9.0, 1.5))
                g0 = torch.exp(-alpha)                                      # (0.011, 0.99988)
            else:
                g0 = 0.05 + 0.949 * torch.sigmoid(self.damping_g0_raw)      # (0.05, 0.999)
            # v0.2.3: cutoff is a physical-Hz parameter, NOT a fraction of the
            # current sample rate. Log mapping is perceptually sensible and
            # keeps raw=0 near ~2 kHz for common native rates. The same cutoff
            # is therefore used at TRAIN_SR and at native render rate.
            u = torch.sigmoid(self.damping_cutoff_raw)
            log_lo = math.log(self.cutoff_min_hz)
            log_hi = math.log(self.cutoff_max_hz)
            cutoff_hz = torch.exp(log_lo + (log_hi - log_lo) * u)
            return g0, cutoff_hz

        def gains(self, scale=1.2):
            # tanh soft-bound: differentiable gain clipping (stability, plan §7)
            return (scale * torch.tanh(self.input_gains_raw),
                    scale * torch.tanh(self.output_gains_raw))

        def delay_samples_at(self, sr):
            """Delay lengths quantized to the active sample rate (cached)."""
            key = int(sr)
            cache = getattr(self, "_delay_cache", None)
            if cache is None:
                cache = {}
                self._delay_cache = cache
            if key not in cache:
                cache[key] = torch.tensor(
                    [max(1, round(d * sr)) for d in self.delay_seconds],
                    device=self.householder_vec.device, dtype=torch.float64)
            return cache[key]

        def _grid_from_omega(self, key, omega, sr):
            """Cached (phase, z^-1) for an ARBITRARY set of angular
            frequencies omega (rad/sample). v0.2.5: the Sherman-Morrison
            solve is valid at any z on the unit circle, so once the training
            loop stops needing a time-domain IR the evaluation grid no longer
            has to be a uniform FFT grid — a couple of hundred log-spaced
            points replace 16385 uniform bins."""
            cache = getattr(self, "_grid_cache", None)
            if cache is None:
                cache = {}
                self._grid_cache = cache
            if key not in cache:
                device = self.householder_vec.device
                if not torch.is_tensor(omega):
                    omega = torch.tensor(np.asarray(omega, dtype=np.float64),
                                         device=device, dtype=torch.float64)
                omega = omega.to(device=device, dtype=torch.float64)
                phase = torch.exp(-1j * torch.outer(omega,
                                                    self.delay_samples_at(sr)))
                z_inv = torch.exp(-1j * omega).unsqueeze(1)
                cache[key] = (phase, z_inv)
            return cache[key]

        def _grids(self, n_fft, sr):
            """Uniform FFT grid — still used by the legacy stft_decay training
            path and by any frequency-domain rendering."""
            device = self.householder_vec.device
            k = torch.arange(0, n_fft // 2 + 1, device=device,
                             dtype=torch.float64)
            return self._grid_from_omega(("fft", int(n_fft), int(sr)),
                                         2.0 * math.pi * k / n_fft, sr)

        def line_decay_tau(self, omega, sr):
            """Closed-form amplitude decay constant per line, shape (F, n).

            One round trip through line i is a delay of m_i samples followed
            by the one-pole damping filter
                H_i(z) = g0_i (1 - a_i) / (1 - a_i z^-1),
            so the amplitude is multiplied by |H_i(w)| every m_i/sr seconds:
                tau_i(w) = -(m_i / sr) / ln|H_i(w)|.
            |H_i| < g0_i < 0.999 everywhere, so the log is always negative and
            no clamping of the model is required. This is the standard
            attenuation-per-delay relation used to design FDN reverberators;
            here it replaces an STFT slope fit on a rendered IR.
            """
            g0, cutoff_hz = self.damping_params(sr)
            a = torch.exp(-2.0 * math.pi * cutoff_hz.to(torch.float64) / sr)
            cos_w = torch.cos(omega).unsqueeze(1)                  # (F,1)
            a_r = a.unsqueeze(0)                                   # (1,n)
            denom = torch.sqrt(1.0 - 2.0 * a_r * cos_w + a_r ** 2 + 1e-16)
            mag = (g0.to(torch.float64) * (1.0 - a)).unsqueeze(0) / denom
            mag = torch.clamp(mag, min=1e-12, max=1.0 - 1e-9)
            m_sec = (self.delay_samples_at(sr) / float(sr)).unsqueeze(0)
            return -m_sec / torch.log(mag)                          # (F,n)

        def _line_spectra_grid(self, grid, sr):
            """Per-line output spectra x, shape (n_freq, n) — the FDN state
            BEFORE the output tap. Shared by training (single tap) and the
            multichannel render (many taps of the same trained lines)."""
            g0, cutoff_hz = self.damping_params(sr)
            a_pole = torch.exp(-2.0 * math.pi * cutoff_hz.to(torch.float64) / sr)
            in_g, _ = self.gains()

            phase, z_inv = grid

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

        def line_spectra(self, n_fft, sr):
            return self._line_spectra_grid(self._grids(n_fft, sr), sr)

        def transfer_at(self, key, omega, sr):
            """Transfer function evaluated on an arbitrary frequency set."""
            x = self._line_spectra_grid(self._grid_from_omega(key, omega, sr), sr)
            _, out_g = self.gains()
            return (x * out_g.to(torch.complex128).unsqueeze(0)).sum(-1)

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
            """Exact final-render IRs, block-vectorized for speed.

            This is the same causal recursion used in v0.2.3, but it processes
            blocks no longer than the shortest delay. Therefore feedback written
            by a block cannot return inside that same block: each line's one-pole
            damping recursion can be evaluated in compiled scipy.signal.lfilter,
            then the Householder feedback is applied to the whole block at once.
            No periodic-IFFT aliasing and no Python loop over individual samples.
            """
            with torch.no_grad():
                g0_t, cutoff_t = self.damping_params(sr)
                in_g_t, out_g_t = self.gains()
                v_t = self.householder_vec / (self.householder_vec.norm() + 1e-8)

            g0 = g0_t.detach().cpu().numpy().astype(np.float64)
            cutoff = cutoff_t.detach().cpu().numpy().astype(np.float64)
            in_g = in_g_t.detach().cpu().numpy().astype(np.float64)
            out_g = out_g_t.detach().cpu().numpy().astype(np.float64)
            v = v_t.detach().cpu().numpy().astype(np.float64)

            delays = np.asarray([max(1, round(d * sr)) for d in self.delay_seconds],
                                dtype=np.int64)
            a = np.exp(-2.0 * math.pi * cutoff / float(sr))
            b = g0 * (1.0 - a)

            taps_t = torch.ones(n_channels, self.n, dtype=torch.float64, device="cpu")
            if n_channels > 1:
                gen = torch.Generator(device="cpu").manual_seed(int(seed) + 9173)
                r = torch.randn(n_channels - 1, self.n, generator=gen, dtype=torch.float64)
                r = r / (r.norm(dim=1, keepdim=True) + 1e-12) * math.sqrt(self.n)
                taps_t[1:] = r
            taps = taps_t.numpy()
            weights = taps * out_g[None, :]

            max_delay = int(delays.max())
            block_len = int(delays.min())
            # Future input of each delay line. q_i[t] is consumed at t+delay_i.
            scheduled = np.zeros((self.n, ir_len_samples + max_delay), dtype=np.float64)
            # scipy lfilter's one-state zi is a*y_previous for
            # y[n] = b*x[n] + a*y[n-1].
            zi = np.zeros(self.n, dtype=np.float64)
            irs = np.zeros((n_channels, ir_len_samples), dtype=np.float32)

            for start in range(0, ir_len_samples, block_len):
                end = min(start + block_len, ir_len_samples)
                delayed = scheduled[:, start:end]
                x_block = np.empty_like(delayed)

                # Coefficients differ per line, so loop over FDN lines (4..32),
                # not over tens/hundreds of thousands of audio samples.
                for i in range(self.n):
                    y, zf = signal.lfilter([b[i]], [1.0, -a[i]], delayed[i],
                                           zi=[zi[i]])
                    x_block[i] = y
                    zi[i] = zf[0]

                irs[:, start:end] = (weights @ x_block).astype(np.float32)

                # q = A x, A = I - 2vv^T, vectorized across the whole block.
                q_block = x_block - 2.0 * v[:, None] * (v @ x_block)[None, :]
                if start == 0:
                    q_block[:, 0] += in_g

                for i in range(self.n):
                    w0 = start + int(delays[i])
                    w1 = end + int(delays[i])
                    scheduled[i, w0:w1] = q_block[i]

            return torch.from_numpy(irs)

        def render_ir(self, ir_len_samples, sr):
            # Differentiable training renderer. Extra FFT period reduces the
            # circular-tail contamination without making every epoch too costly.
            n_fft = next_pow2(ir_len_samples * TRAIN_TRANSFER_PADDING)
            spec = self.transfer(n_fft, sr)
            ir = torch.fft.irfft(spec, n=n_fft)
            return ir[:ir_len_samples].to(torch.float32)

    return DifferentiableFDN(n, choose_delays_seconds(n), cutoff_max_hz)


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

    if band_mask.shape[0] == 0:
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


def feedback_stability_margin_regularizer(model, threshold=0.998):
    """Very mild guard only near the structural stability boundary.

    The feedback matrix is orthogonal and every loop has g0 < 0.999, so the
    FDN is already stable by construction. The old tail-energy regularizer
    forced roughly -60 dB decay inside the 1.5 s training window and therefore
    contradicted long-decay presets. This term is zero for musically useful
    long decays and rises only in the last ~0.1% below the hard gain ceiling.
    """
    g0, _ = model.damping_params()
    width = max(0.999 - threshold, 1e-6)
    excess = torch.relu((g0 - threshold) / width)
    return torch.mean(excess ** 2)


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


def precompute_native_spectral_target(analysis, sr_native, device):
    """Broad log-band spectral shape of the source at native sample rate.

    The time-domain training path runs at 8 kHz and therefore cannot see source
    content above 4 kHz. This target/loss keeps that high-frequency information
    in the optimization without trying to match individual comb teeth.
    """
    n_fft = SPECTRAL_MATCH_FFT
    model_freqs_np = np.fft.rfftfreq(n_fft, d=1.0 / float(sr_native))
    edges = np.geomspace(40.0, sr_native * 0.5 * 0.98, SPECTRAL_MATCH_BANDS + 1)

    source_power = np.mean(np.asarray(analysis["stft_mag"], dtype=np.float64) ** 2, axis=1)
    source_freqs = np.asarray(analysis["stft_freqs"], dtype=np.float64)

    masks = []
    target_levels = []
    for lo, hi in zip(edges[:-1], edges[1:]):
        src_mask = (source_freqs >= lo) & (source_freqs < hi)
        mdl_mask = (model_freqs_np >= lo) & (model_freqs_np < hi)
        if not np.any(src_mask) or not np.any(mdl_mask):
            continue
        target_levels.append(math.log(math.sqrt(float(np.mean(source_power[src_mask]))) + 1e-8))
        masks.append(mdl_mask.astype(np.float32))

    if len(masks) < 3:
        return None
    band_mask = torch.tensor(np.stack(masks), dtype=torch.float32, device=device)
    band_counts = band_mask.sum(dim=1).clamp(min=1.0)
    target = torch.tensor(target_levels, dtype=torch.float32, device=device)
    target = target - target.mean()
    return n_fft, band_mask, band_counts, target


def native_spectral_band_loss(model, sr_native, target_spec):
    if target_spec is None:
        return torch.tensor(0.0, device=next(model.parameters()).device)
    n_fft, band_mask, band_counts, target_shape = target_spec
    H = model.transfer(n_fft, sr_native)
    power = torch.abs(H).to(torch.float32) ** 2
    band_rms = torch.sqrt((band_mask @ power) / band_counts + 1e-10)
    pred = torch.log(band_rms + 1e-6)
    pred = pred - pred.mean()
    return torch.mean(torch.abs(pred - target_shape))


# ---------------------------------------------------------------------------
# v0.2.5 descriptor losses — no time-domain IR, no FFT grid
# ---------------------------------------------------------------------------

def closed_form_decay_loss(model, omega, sr, target_log_tau,
                           span=DESC_DECAY_SPAN, n_t=DESC_DECAY_TIME_PTS):
    """Per-band decay match computed directly from the model parameters.

    Predicting the band decay as simply the slowest line's tau is wrong by
    1.5-3x: analyze_audio does not measure the asymptotic pole, it fits ONE
    log-slope to the band envelope, and that envelope is a sum of per-line
    exponentials whose early, steeper part dominates the fit. So the prediction
    reproduces the measurement instead of the asymptote:

      1. per-line tau_i(w) in closed form (line_decay_tau),
      2. band envelope  env(t)^2 = sum_i c_i exp(-2t/tau_i),  c_i = (in_i out_i)^2,
      3. the same least-squares log-slope fit the analyzer performs.

    The analyzer fits from the peak down to -60 dB, i.e. over a horizon
    PROPORTIONAL to the decay, so the time grid is scaled per band by a
    reference tau (detached: it selects the grid, it is not a gradient path).
    That makes the estimate scale-invariant, which the fixed-horizon version
    was not.

    Measured against decays rendered by the exact time-domain recursion
    (5 seeds x 4 damping spreads, 24 bands): median ratio 0.92, log-MAE 0.21.
    The slowest-line approximation scored 1.51 / 0.54 on the same set.
    """
    tau = model.line_decay_tau(omega, sr)                        # (B, n)
    in_g, out_g = model.gains()
    c = ((in_g * out_g).to(torch.float64)) ** 2                  # (n,)

    tau_ref = (tau.shape[-1] / (1.0 / tau).sum(-1)).detach()     # (B,)
    t = tau_ref.unsqueeze(1) * torch.linspace(
        0.0, span, n_t, dtype=torch.float64,
        device=tau.device).unsqueeze(0)                          # (B, T)

    energy = (c.view(1, 1, -1)
              * torch.exp(-2.0 * t.unsqueeze(-1) / tau.unsqueeze(1))).sum(-1)
    log_env = 0.5 * torch.log(energy + 1e-300)                   # (B, T)

    t_c = t - t.mean(-1, keepdim=True)
    slope = (((log_env - log_env.mean(-1, keepdim=True)) * t_c).sum(-1)
             / ((t_c * t_c).sum(-1) + 1e-30))
    tau_pred = -1.0 / torch.clamp(slope, max=-1e-9)
    return torch.mean(torch.abs(torch.log(tau_pred + 1e-3) - target_log_tau))


def precompute_sparse_spectral_target(analysis, sr_native, device,
                                      n_bands=DESC_SPECTRAL_BANDS,
                                      per_band=DESC_POINTS_PER_BAND,
                                      dna_amount=1.0):
    """Log-band spectral shape of the source, plus the sparse frequency set at
    which the model has to be evaluated to score it.

    v0.2.4 evaluated 1025 uniform bins to produce 18 band averages. Here each
    band is probed at `per_band` interior log-spaced points, so the grid is
    n_bands * per_band points total and maps to bands by a simple reshape —
    no (n_bands, n_freq) mask matmul either.
    """
    src_freqs = np.asarray(analysis["stft_freqs"], dtype=np.float64)
    src_power = np.mean(np.asarray(analysis["stft_mag"], dtype=np.float64) ** 2,
                        axis=1)
    edges = np.geomspace(40.0, sr_native * 0.5 * 0.98, n_bands + 1)

    freq_chunks = []
    levels = []
    for lo, hi in zip(edges[:-1], edges[1:]):
        m = (src_freqs >= lo) & (src_freqs < hi)
        if not np.any(m):
            continue
        levels.append(math.log(math.sqrt(float(np.mean(src_power[m]))) + 1e-8))
        freq_chunks.append(np.geomspace(lo, hi, per_band + 2)[1:-1])

    if len(levels) < 3:
        return None
    freqs = np.concatenate(freq_chunks)
    omega = 2.0 * math.pi * freqs / float(sr_native)
    target = torch.tensor(levels, dtype=torch.float32, device=device)
    target = target - target.mean()
    # v0.2.9 — the double-tilt fix.
    #
    # The render is  wet = source * h , so in the spectral domain the source's
    # own tilt multiplies the resonator's. Fitting |H| to the source's shape
    # therefore applies that shape TWICE. Measured on a plucked-like source,
    # tilt from 200 Hz to 8 kHz:
    #     source -50.7 dB | fitted |H| -30.4 dB | wet output -78.2 dB
    # The tilts add. The better the spectral fit, the darker the result — a
    # consequence of the "acoustic DNA" idea itself, not a bug in the loss.
    #
    # dna_amount is the exponent applied to the target shape (linear domain),
    # i.e. a plain scale in this log domain. 1.0 is the old behaviour, 0.0
    # makes the resonator spectrally flat and leaves the DNA entirely in the
    # frequency-dependent decay times, which is the stronger perceptual cue
    # anyway. Output tilt is roughly source_tilt * (1 + dna_amount).
    target = target * float(dna_amount)
    key = ("desc_spec", int(sr_native), int(n_bands), int(per_band), len(levels))
    return key, omega, per_band, target


def sparse_spectral_band_loss(model, sr_native, spec):
    if spec is None:
        return torch.tensor(0.0, device=next(model.parameters()).device)
    key, omega, per_band, target_shape = spec
    H = model.transfer_at(key, omega, sr_native)
    power = (torch.abs(H) ** 2).to(torch.float32).view(-1, per_band)
    pred = torch.log(torch.sqrt(power.mean(dim=1) + 1e-10) + 1e-6)
    pred = pred - pred.mean()
    return torch.mean(torch.abs(pred - target_shape))


def train_fdn_descriptor(model, sr_native, analysis, args, progress_file=None):
    """Descriptor-only training: two band-aggregated log-MAE terms plus the
    stability guard. Runs at native sample rate; nothing is rendered."""
    device = next(model.parameters()).device

    spec_target = precompute_sparse_spectral_target(
        analysis, sr_native, device,
        dna_amount=getattr(args, "spectral_dna", 1.0))

    edges = np.asarray(analysis["band_edges"], dtype=np.float64)
    band_tau = np.asarray(analysis["band_tau"], dtype=np.float64)
    centers = np.sqrt(edges[:-1] * edges[1:])
    omega_decay = torch.tensor(2.0 * math.pi * centers / float(sr_native),
                               dtype=torch.float64, device=device)
    target_log_tau = torch.tensor(
        [math.log((tb if tb > 1e-4 else args.ir_duration + 1e-3) + 1e-3)
         for tb in band_tau], dtype=torch.float64, device=device)

    opt = torch.optim.Adam(model.parameters(), lr=args.lr)
    losses, warnings = [], []
    best_state, best_loss, best_epoch = None, float("inf"), -1
    progress_every = max(1, args.epochs // 100)

    for epoch in range(args.epochs):
        opt.zero_grad()
        l_decay = closed_form_decay_loss(model, omega_decay, sr_native,
                                         target_log_tau)
        l_spec = sparse_spectral_band_loss(model, sr_native, spec_target)
        l_reg = feedback_stability_margin_regularizer(model)
        loss = l_decay + DESC_SPECTRAL_WEIGHT * l_spec.to(l_decay.dtype) \
            + 0.05 * l_reg.to(l_decay.dtype)

        if not torch.isfinite(loss):
            warnings.append("non-finite loss at epoch %d; reverting to best checkpoint" % epoch)
            break

        loss.backward()
        torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)
        opt.step()

        loss_val = float(loss.item())
        losses.append(loss_val)
        if loss_val < best_loss:
            best_loss, best_epoch = loss_val, epoch
            best_state = {k: v.detach().clone() for k, v in model.state_dict().items()}

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

    return losses, warnings, best_loss, best_epoch


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

    # All training constants precomputed ONCE.
    target_mags = precompute_target_mags(target_t)
    native_spec_target = precompute_native_spectral_target(analysis, sr_native, device)

    # v0.2.3: preserve NATIVE band identities. v0.2.2 rebuilt 24 log bands
    # over 40..3920 Hz and assigned native 40..~Nyquist taus by index, which
    # frequency-compressed the decay target. Bands above TRAIN_SR Nyquist are
    # simply omitted from the low-rate decay term (the native spectral term
    # still constrains the full-band transfer).
    native_edges = np.asarray(analysis["band_edges"], dtype=np.float64)
    band_tau = np.asarray(analysis["band_tau"], dtype=np.float64)
    n_fft_decay = min(1024, train_len)
    n_freq_decay = n_fft_decay // 2 + 1
    freqs = torch.linspace(0, TRAIN_SR / 2, n_freq_decay, device=device)
    train_hi = TRAIN_SR * 0.5 * 0.98
    masks = []
    tau_vals = []
    for b in range(len(band_tau)):
        lo = float(native_edges[b])
        hi = min(float(native_edges[b + 1]), train_hi)
        if lo >= train_hi or hi <= lo:
            continue
        mask = ((freqs >= lo) & (freqs < hi)).float()
        if float(mask.sum().item()) >= 1.0:
            masks.append(mask)
            tau_vals.append(float(band_tau[b]))
    if masks:
        band_mask = torch.stack(masks, dim=0)
        band_counts = band_mask.sum(dim=1).clamp(min=1.0)
    else:
        band_mask = torch.zeros((0, n_freq_decay), device=device)
        band_counts = torch.zeros((0,), device=device)
    ir_dur_train = train_len / TRAIN_SR
    target_log_tau = torch.tensor(
        [math.log((tb if tb > 1e-4 else ir_dur_train + 1e-3) + 1e-3)
         for tb in tau_vals], device=device)

    opt = torch.optim.Adam(model.parameters(), lr=args.lr)
    losses = []
    warnings = []
    best_state = None
    best_loss = float("inf")
    best_epoch = -1
    progress_every = max(1, args.epochs // 100)

    for epoch in range(args.epochs):
        opt.zero_grad()
        ir = model.render_ir(train_len, TRAIN_SR)
        l_stft = multires_stft_loss_fast(ir, target_mags)
        l_decay = band_decay_loss(ir, target_log_tau, band_mask,
                                   band_counts, TRAIN_SR)
        l_spec = native_spectral_band_loss(model, sr_native, native_spec_target)
        l_reg = feedback_stability_margin_regularizer(model)
        loss = l_stft + 0.5 * l_decay + SPECTRAL_MATCH_WEIGHT * l_spec + 0.05 * l_reg

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
            best_epoch = epoch
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

    return losses, warnings, best_loss, best_epoch


# ═══════════════════════════════════════════════════════════════════════════
# Stage 5 — Render
# ═══════════════════════════════════════════════════════════════════════════

def build_early_ir(sr, length_ms, density, tau_ms, predelay_ms, seed,
                   hf_damp=0.35):
    """Velvet-noise early-reflection IR: one +/-1 tap per grid cell, placed at
    random inside the cell, under an exponential envelope.

    Regular grid + random position inside it is what keeps velvet noise free of
    the tonal colouration a purely random tap set produces, and free of the
    slapback a too-sparse set produces. A gentle one-pole low-pass stands in
    for the HF loss real reflections accumulate.
    """
    rng = np.random.default_rng(int(seed))
    n = max(int(length_ms * 1e-3 * sr), 8)
    ir = np.zeros(n, dtype=np.float64)
    cell = max(1, int(sr / max(density, 1.0)))
    start_cell = int(predelay_ms * 1e-3 * sr) // cell
    for k in range(start_cell, n // cell):
        pos = k * cell + int(rng.integers(0, cell))
        if pos >= n:
            break
        ir[pos] = (1.0 if rng.random() < 0.5 else -1.0) \
            * math.exp(-(pos / sr) / max(tau_ms * 1e-3, 1e-4))
    if hf_damp > 0.0:
        ir = signal.lfilter([1.0 - hf_damp], [1.0, -hf_damp], ir)
    return ir


def apply_early_late_split(ir, sr, early_ms, density, tau_ms, predelay_ms, seed):
    """Replace the FDN's own first `early_ms` with a synthetic early pattern.

    The FDN is a late-field model: its first echo cannot arrive before its
    shortest delay, and until the feedback has mixed a few times its response
    is sparse and comb-like. The v0.2.5 descriptor loss makes this explicit —
    it constrains band decay and spectral envelope, both steady-state
    quantities, so nothing in the objective looks at the first tens of ms at
    all. Measured consequence on real material: 33% slower attack and 6.6 dB
    less crest factor than the old time-domain loss.

    So the FDN IR is faded in with a sin^2 ramp and the energy that ramp
    removes is given to the early pattern instead. sin^2 + cos^2 = 1 makes the
    handover energy-complementary, and matching the removed energy exactly
    means the split changes the attack WITHOUT changing the overall level.
    """
    n_cross = int(early_ms * 1e-3 * sr)
    if n_cross < 8 or n_cross >= len(ir):
        return ir
    fade = np.ones(len(ir), dtype=np.float64)
    fade[:n_cross] = np.sin(np.linspace(0.0, math.pi / 2.0, n_cross)) ** 2

    removed = float(np.sum((ir[:n_cross] ** 2) * (1.0 - fade[:n_cross] ** 2)))
    out = ir * fade
    if removed <= 0.0:
        return out

    early = build_early_ir(sr, early_ms, density, tau_ms, predelay_ms, seed)
    e_energy = float(np.sum(early ** 2))
    if e_energy <= 0.0:
        return out
    early *= math.sqrt(removed / e_energy)
    m = min(len(early), len(out))
    out[:m] += early[:m]
    return out


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
    if getattr(args, "early_ms", 0.0) > 0.0:
        irs = np.stack([
            apply_early_late_split(irs[c].astype(np.float64), sr, args.early_ms,
                                   args.early_density, args.early_tau_ms,
                                   args.early_predelay_ms,
                                   int(args.seed) + 4409 * (c + 1))
            for c in range(irs.shape[0])]).astype(np.float32)

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
                 modal_table, band_edges, band_tau, model_band_tau=None,
                 spectral_match_mae=0.0, decay_match_log_mae=0.0,
                 best_loss=None, best_epoch=-1, timings=None):
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
        final_model_loss = (best_loss if best_loss is not None and math.isfinite(best_loss)
                            else (losses[-1] if losses else 0.0))
        f.write("final_loss=%.6f\n" % final_model_loss)
        f.write("best_epoch=%d\n" % (best_epoch + 1 if best_epoch >= 0 else 0))
        f.write("decay_estimate_ms=%.1f\n" % (decay_estimate * 1000.0))
        f.write("spectral_match_mae=%.6f\n" % spectral_match_mae)
        f.write("decay_match_log_mae=%.6f\n" % decay_match_log_mae)
        f.write("stability_warning=%s\n" % ("; ".join(warnings) if warnings else "none"))
        f.write("loss_mode=%s\n" % args.loss)
        f.write("spectral_dna=%.2f\n" % getattr(args, "spectral_dna", 1.0))
        f.write("early_ms=%.1f\n" % getattr(args, "early_ms", 0.0))
        f.write("early_density=%.0f\n" % getattr(args, "early_density", 0.0))
        f.write("early_tau_ms=%.1f\n" % getattr(args, "early_tau_ms", 0.0))
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
        f.write("analysis_mix_mode=%s\n" % getattr(args, "_analysis_mix_mode", "unknown"))
        f.write("event_count=%d\n" % getattr(args, "_event_count", 0))
        f.write("seed=%d\n" % args.seed)
        f.write("startup_seconds=%.2f\n" % timings.get("startup", 0.0))
        f.write("analyze_seconds=%.2f\n" % timings.get("analyze", 0.0))
        f.write("train_seconds=%.2f\n" % timings.get("train", 0.0))
        f.write("render_seconds=%.2f\n" % timings.get("render", 0.0))

        # indexed dump: loss curve (for Praat viz panel)
        n_loss = min(len(losses), 400)
        if n_loss > 0:
            idxs = np.linspace(0, len(losses) - 1, n_loss, dtype=int)
            sampled = [losses[int(i)] for i in idxs]
        else:
            sampled = []
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
            if model_band_tau is not None and b < len(model_band_tau):
                model_ms = min(float(model_band_tau[b]) * 1000.0, decay_cap_ms)
                f.write("model_band_%d=%.1f,%.1f\n" % (b, center_hz, model_ms))


# ═══════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════

def main():
    import argparse

    check_dependencies()

    global np, signal, torch, sf
    import numpy as np_
    import scipy.signal as signal_
    import soundfile as sf
    import torch as torch_
    np = np_
    signal = signal_
    torch = torch_

    # v0.2.6: bind the log file BEFORE parse_args. argparse exits with code 2
    # on a bad argument, which used to happen before set_log_file() ran — so a
    # version-mismatched front end produced a completely silent failure with no
    # log for Praat to show. Now every exit path leaves a readable explanation.
    if "--log_file" in sys.argv:
        i = sys.argv.index("--log_file")
        if i + 1 < len(sys.argv):
            set_log_file(sys.argv[i + 1])

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
    parser.add_argument("--loss", type=str, default="descriptor",
                         choices=["descriptor", "stft_decay"])
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
    parser.add_argument("--spectral_dna", type=float, default=0.4,
                         help="how much of the source's spectral tilt the "
                              "resonator takes on (0 = flat, 1 = full = "
                              "pre-0.2.9). The source passes THROUGH the "
                              "resonator, so output tilt ~ source * (1+this).")
    parser.add_argument("--early_ms", type=float, default=40.0,
                         help="synthetic early-reflection window in ms; "
                              "0 disables the split (pure FDN, pre-0.2.8)")
    parser.add_argument("--early_density", type=float, default=1400.0,
                         help="early taps per second")
    parser.add_argument("--early_tau_ms", type=float, default=22.0,
                         help="early-pattern decay constant in ms")
    parser.add_argument("--early_predelay_ms", type=float, default=3.0)
    parser.add_argument("--torch_threads", type=int, default=0,
                         help="0 = auto (1 thread for the descriptor loss, "
                              "library default otherwise)")

    try:
        args = parser.parse_args()
    except SystemExit as exc:
        if exc.code not in (0, None):
            log("ARGUMENT ERROR: this engine does not accept one of the "
                "arguments the Praat front end sent.")
            log("Engine version: 0.2.6.  Arguments received:")
            log("  " + " ".join(sys.argv[1:]))
            log("This almost always means AcousticDNAResonator.praat and "
                "acoustic_dna_resonator.py are from different releases.")
            log("Update BOTH files to the same version.")
        raise
    if args.log_file and args.log_file.strip().lower() != "none" \
            and args.log_file != (_LOG_FILE or ""):
        set_log_file(args.log_file)
    if args.normalize_mode == "loudness":
        log("NOTE: normalize_mode=loudness is not a LUFS implementation; using RMS normalization.")
        args.normalize_mode = "rms"
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

    # Thread policy. The descriptor loss is many TINY tensor ops (the largest
    # is a few tens of thousands of elements), so on a multi-core machine the
    # thread-pool synchronisation per op can cost more than the arithmetic.
    # The legacy stft_decay loss works on large FFT grids and does want
    # threads. This was untestable on the single-core box this was developed
    # on, hence the explicit override.
    threads_default = torch.get_num_threads()
    if args.torch_threads > 0:
        torch.set_num_threads(args.torch_threads)
    elif args.loss == "descriptor":
        torch.set_num_threads(1)
    log("      torch threads: %d (library default %d)"
        % (torch.get_num_threads(), threads_default))

    if args.device == "auto":
        device = "cuda" if torch.cuda.is_available() else "cpu"
    else:
        device = args.device

    audio_mc, sr = sf.read(args.input_wav, always_2d=True)   # (N, C_in)
    audio_mc = audio_mc.astype(np.float32)
    in_channels = audio_mc.shape[1]
    # Robust mono reference for analysis/training and mismatch-channel rendering.
    # Normal stereo stays a mean mixdown; severe phase cancellation falls back
    # to the strongest channel. Normalization references actual multichannel RMS.
    audio, analysis_mix_mode = robust_mono_reference(audio_mc)
    ref_rms = float(np.sqrt(np.mean(audio_mc.astype(np.float64) ** 2)) + 1e-8)
    if analysis_mix_mode.startswith("strongest_channel_"):
        log("WARNING: mean mixdown showed severe phase cancellation; using %s for analysis."
            % analysis_mix_mode)

    events = load_event_table(args.events_csv)  # metadata only in v0.2.3
    args._event_count = len(events) if events else 0

    startup_seconds = time.time() - _T_PROCESS_START
    log("      startup + imports: %.1f s" % startup_seconds)

    log("[1/5] Analyzing input (STFT / band decay / modal peaks)...")
    t_stage = time.time()
    analysis = analyze_audio(audio, sr)
    timings = {"analyze": time.time() - t_stage, "startup": startup_seconds}

    log("[2/5] Building differentiable FDN (n=%d)..." % args.fdn_size)
    model = build_fdn_model(args.fdn_size, args.seed, native_sr=sr).to(device)

    if args.loss == "descriptor":
        log("[3/5] Training (%d epochs, descriptor loss @ native %d Hz)..."
            % (args.epochs, sr))
    else:
        log("[3/5] Training (%d epochs, stft_decay loss @ internal %d Hz)..."
            % (args.epochs, TRAIN_SR))
    t_stage = time.time()
    if args.loss == "descriptor":
        losses, warnings, best_loss, best_epoch = train_fdn_descriptor(
            model, sr, analysis, args, progress_file=progress_file)
    else:
        losses, warnings, best_loss, best_epoch = train_fdn(
            model, audio, sr, analysis, args, progress_file=progress_file)
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

    # QC: compare the exact trained IR to the same input-DNA measurements.
    ir_analysis = analyze_audio(ir_mono, sr, n_bands=len(analysis["band_tau"]))
    model_band_tau = np.asarray(ir_analysis["band_tau"], dtype=np.float64)
    target_band_tau = np.asarray(analysis["band_tau"], dtype=np.float64)
    n_qc = min(len(model_band_tau), len(target_band_tau))
    if n_qc > 0:
        decay_match_log_mae = float(np.mean(np.abs(
            np.log(model_band_tau[:n_qc] + 1e-3) -
            np.log(target_band_tau[:n_qc] + 1e-3))))
    else:
        decay_match_log_mae = 0.0
    with torch.no_grad():
        qc_spec_target = precompute_native_spectral_target(analysis, sr,
                                                           next(model.parameters()).device)
        spectral_match_mae = float(native_spectral_band_loss(
            model, sr, qc_spec_target).detach().cpu().item())

    output = normalize_output(wet_raw, ref_rms, args.normalize_mode)

    if not np.all(np.isfinite(output)):
        warnings.append("non-finite samples in render; zeroed as safety fallback")
        output = np.nan_to_num(output)

    out_flat = output if output.ndim == 1 else output.reshape(-1)
    out_rms = float(np.sqrt(np.mean(out_flat ** 2)) + 1e-8)
    out_duration = output.shape[0] / sr

    args._in_channels = in_channels
    args._per_channel = per_channel
    args._analysis_mix_mode = analysis_mix_mode

    log("[5/5] Writing output.wav and stats.txt...")
    # Temp interchange with Praat must not quantize/clip the processed signal.
    # soundfile's default WAV subtype is PCM_16, which silently clips |x| > 1.
    sf.write(args.output_wav, output, sr, subtype="FLOAT")

    delays_samples = [round(d * sr) for d in model.delay_seconds]
    decay_estimate = rt60_style_estimate(ir_mono, sr)

    write_stats(args.stats_txt, args, sr, delays_samples, losses, warnings,
                ref_rms, out_rms, out_duration, decay_estimate,
                analysis["modal_table"], analysis["band_edges"],
                analysis["band_tau"], model_band_tau, spectral_match_mae,
                decay_match_log_mae, best_loss, best_epoch, timings)

    if args.cleanup:
        for p in [args.input_wav, args.events_csv]:
            if p and p.lower() != "none" and _is_praat_temp(p) and os.path.isfile(p):
                try:
                    os.remove(p)
                except OSError:
                    pass

    total_seconds = time.time() - _T_PROCESS_START
    try:
        with open(args.stats_txt, "a") as f:
            f.write("total_seconds=%.2f\n" % total_seconds)
    except OSError:
        pass
    log("Done. Total wall clock: %.1f s (startup+imports %.1f s, train %.1f s)"
        % (total_seconds, startup_seconds, timings.get("train", 0.0)))


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
