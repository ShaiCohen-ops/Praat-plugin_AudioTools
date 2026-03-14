"""
sympathetic_resonance.py  --  Sympathetic Resonance  v1.0

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University
Email: shai.cohen@biu.ac.il

Called by SympatheticResonance.praat -- not run directly.

Usage:
    python sympathetic_resonance.py \\
        --input       input.wav \\
        --output      output.wav \\
        --stats       stats.txt \\
        --resonances  resonances.csv \\
        --character   metallic \\
        --n_strings   32 \\
        --decay_s     5.0 \\
        --coupling    0.30 \\
        --wet_dry     0.0

Architecture:
    A -- Load and normalise audio to mono float32
    B -- Compute STFT and build log-frequency (pseudo-CQT) representation
    C -- Measure spectral flatness as a global control signal
    D -- Discover latent pitch collection via spectral peak detection
         and clustering in log-pitch space
    E -- Build resonator bank: per-string pole radius r computed from
         decay_s and character bandwidth; gain shaped by brightness curve
         and spectral flatness; stiffness inharmonicity for metallic
    F -- Excite all resonators with the source signal in parallel
         using second-order IIR filters (scipy.signal.sosfilt)
    G -- Apply sympathetic coupling: Gaussian blur across the
         frequency axis of the output matrix
    H -- Character spectral shaping, soft-limit, blend, write output
    I -- Write stats.txt and resonances.csv

Physical model notes:
    Each virtual string is a second-order digital resonator:
        y[n] = 2*r*cos(omega)*y[n-1] - r^2*y[n-2] + gain*x[n]
    The pole radius r determines both resonant frequency selectivity
    and temporal decay.  For target -60 dB decay in T seconds:
        r = exp( -6.908 / (T * sr) )
    Spectral flatness (0=tonal, 1=white) drives:
        - shorter decay for noisy/breathy sources
        - wider bandwidth (lower r_bw) for noise-excited resonators
        - stronger sympathetic coupling for diffuse sources
    Coupling is implemented as Gaussian blur along the resonator
    frequency axis of the output matrix, creating the spread of
    energy between adjacent strings that characterises a real
    instrument body.

Dependencies: numpy  soundfile  scipy
"""

import argparse
import csv
import math
import sys


def check_dependencies():
    """Verify required packages are installed."""
    missing = []
    for pkg in ("numpy", "soundfile", "scipy"):
        try:
            __import__(pkg)
        except ImportError:
            missing.append(pkg)
    if missing:
        print("ERROR: Missing packages: " + ", ".join(missing), file=sys.stderr)
        print("Install with:  pip install " + " ".join(missing), file=sys.stderr)
        sys.exit(1)


check_dependencies()

import numpy as np
import soundfile as sf
from scipy.signal import sosfilt, find_peaks
from scipy.ndimage import gaussian_filter1d


# ─────────────────────────────────────────────────────────────────────────────
# Character presets
# ─────────────────────────────────────────────────────────────────────────────

CHAR_PRESETS = {
    # src_tilt_db_oct: per-octave gain boost applied to each resonator
    #   compensates for the natural ~6 dB/oct rolloff of the source signal
    #   so that high-frequency strings receive effectively equal excitation
    "metallic": {
        "decay_scale":    1.00,
        "bw_semitones":   0.06,
        "brightness":     16.0,
        "shelf_freq_hz":  600.0,
        "coupling_scale": 1.20,
        "inharmonicity":  0.00008,
        "n_harmonics":    20,
        "harm_rolloff":   0.5,
        "src_tilt_db_oct": 7.0,
    },
    "glassy": {
        "decay_scale":    1.80,
        "bw_semitones":   0.028,
        "brightness":     20.0,
        "shelf_freq_hz":  800.0,
        "coupling_scale": 0.50,
        "inharmonicity":  0.0,
        "n_harmonics":    24,
        "harm_rolloff":   0.4,
        "src_tilt_db_oct": 8.0,
    },
    "wooden": {
        "decay_scale":    0.55,
        "bw_semitones":   0.20,
        "brightness":     -3.0,
        "shelf_freq_hz":  600.0,
        "coupling_scale": 1.00,
        "inharmonicity":  0.0,
        "n_harmonics":    6,
        "harm_rolloff":   1.4,
        "src_tilt_db_oct": 3.0,
    },
    "airy": {
        "decay_scale":    0.38,
        "bw_semitones":   0.40,
        "brightness":     10.0,
        "shelf_freq_hz":  1000.0,
        "coupling_scale": 0.45,
        "inharmonicity":  0.0,
        "n_harmonics":    16,
        "harm_rolloff":   0.6,
        "src_tilt_db_oct": 6.0,
    },
}


# ─────────────────────────────────────────────────────────────────────────────
# A -- Load audio
# ─────────────────────────────────────────────────────────────────────────────

def load_audio(path):
    audio, sr = sf.read(path, always_2d=False)
    audio = audio.astype(np.float32)
    if audio.ndim == 2:
        audio = audio.mean(axis=1)
    peak = np.max(np.abs(audio))
    if peak > 1e-8:
        audio = audio / peak * 0.98
    return audio, int(sr)


# ─────────────────────────────────────────────────────────────────────────────
# B -- Log-frequency (pseudo-CQT) representation
# ─────────────────────────────────────────────────────────────────────────────

def compute_log_spectrum(audio, sr, n_fft=4096, hop=512, n_bins=120,
                         f_min=32.7, f_max=5000.0):
    """
    Log-frequency spectrum via STFT with log-spaced frequency averaging.
    Each output bin maps to the nearest linear FFT bin, giving approximately
    constant resolution in log-frequency space.
    Returns (mag [n_bins, n_frames], freqs [n_bins]).
    """
    n_fft_fb = min(n_fft, len(audio))
    n_fft_fb = max(256, 2 ** int(np.floor(np.log2(n_fft_fb))))
    win      = np.hanning(n_fft_fb).astype(np.float32)
    freqs_fb = np.fft.rfftfreq(n_fft_fb, 1.0 / sr)

    # Build STFT frames
    frames = []
    pos    = 0
    while pos + n_fft_fb <= len(audio):
        frames.append(np.abs(np.fft.rfft(audio[pos:pos + n_fft_fb] * win)))
        pos += hop
    if not frames:
        frames.append(np.zeros(n_fft_fb // 2 + 1, dtype=np.float32))
    stft_fb = np.array(frames, dtype=np.float32).T  # (freq_bins, n_frames)

    # Log-spaced target frequencies
    f_min_eff = max(f_min, freqs_fb[1])
    f_max_eff = min(f_max, freqs_fb[-1])
    log_freqs = np.logspace(np.log10(f_min_eff), np.log10(f_max_eff), n_bins)

    # Map each log-frequency bin to nearest linear STFT bin (vectorised)
    idx = np.argmin(np.abs(freqs_fb[:, None] - log_freqs[None, :]), axis=0)
    log_mag = stft_fb[idx]  # (n_bins, n_frames)

    print("    Log-spectrum: %d bins  |  %d frames  |  %.1f-%.1f Hz"
          % (n_bins, log_mag.shape[1], log_freqs[0], log_freqs[-1]))

    return log_mag.astype(np.float32), log_freqs.astype(np.float32)


# ─────────────────────────────────────────────────────────────────────────────
# C -- Spectral flatness
# ─────────────────────────────────────────────────────────────────────────────

def compute_spectral_flatness(audio, sr, n_fft=2048, hop=512):
    """
    Zwicker / Fastl spectral flatness measure (geometric/arithmetic mean).
    0 = pure tone, 1 = white noise.
    """
    n     = len(audio)
    n_fft = min(n_fft, n)
    win   = np.hanning(n_fft).astype(np.float32)
    vals  = []
    pos   = 0
    while pos + n_fft <= n:
        spec = np.abs(np.fft.rfft(audio[pos:pos + n_fft] * win)) ** 2 + 1e-12
        geo  = float(np.exp(np.mean(np.log(spec))))
        arith = float(np.mean(spec))
        vals.append(geo / arith)
        pos += hop
    return float(np.mean(vals)) if vals else 0.5


# ─────────────────────────────────────────────────────────────────────────────
# D -- Latent pitch discovery
# ─────────────────────────────────────────────────────────────────────────────

def discover_latent_pitches(log_stft, log_freqs, n_pitches):
    """
    Discovers the latent pitch collection embedded in the source.

    Steps:
    1. Time-average the log-frequency spectrum to get a salience profile
    2. Detect prominent spectral peaks
    3. Cluster nearby peaks (within a semitone) -- keep the centroid
    4. Select the N most salient pitches
    5. If fewer peaks than needed, fill with intra-cluster interpolations
       then octave extensions, staying within the original freq range

    Returns np.ndarray of frequencies in Hz, sorted ascending.
    """
    salience = np.power(log_stft, 1.5).mean(axis=1)

    min_dist  = max(1, int(n_pitches * 0.2))
    threshold = salience.std() * 0.25
    peaks, props = find_peaks(salience,
                              prominence=threshold,
                              distance=max(1, min_dist // 2))

    if len(peaks) == 0:
        peaks, _ = find_peaks(salience, distance=1)
    if len(peaks) == 0:
        return np.logspace(np.log10(log_freqs[0]),
                           np.log10(log_freqs[-1]),
                           n_pitches)

    # Sort by prominence
    if "prominences" in props:
        order     = np.argsort(props["prominences"])[::-1]
        peaks_ord = peaks[order]
    else:
        peaks_ord = peaks

    # Cluster peaks within 2 bins of each other
    clusters = []
    used     = set()
    for pk in peaks_ord:
        if pk in used:
            continue
        group = [pk]
        for pk2 in peaks_ord:
            if pk2 not in used and abs(pk2 - pk) <= 2 and pk2 != pk:
                group.append(pk2)
                used.add(pk2)
        used.add(pk)
        clusters.append(group)

    # Centroid frequency of each cluster, weighted by salience
    cluster_freqs = []
    cluster_sal   = []
    for grp in clusters:
        weights = salience[grp]
        centroid = float(np.average(log_freqs[grp], weights=weights))
        cluster_freqs.append(centroid)
        cluster_sal.append(float(weights.sum()))

    cluster_freqs = np.array(cluster_freqs)
    cluster_sal   = np.array(cluster_sal)

    # Take top-N by salience
    top_n  = min(len(cluster_freqs), n_pitches)
    top_ix = np.argsort(cluster_sal)[::-1][:top_n]
    chosen = np.sort(cluster_freqs[top_ix])

    # Fill to n_pitches if needed
    f_lo, f_hi = log_freqs[0], log_freqs[-1]
    attempts   = 0
    while len(chosen) < n_pitches and attempts < n_pitches * 4:
        attempts += 1
        # Try geometric midpoint between adjacent pairs
        gaps = np.diff(np.log(chosen)) if len(chosen) > 1 else np.array([1.0])
        widest = int(np.argmax(gaps))
        if len(chosen) > 1:
            f_new = math.sqrt(chosen[widest] * chosen[widest + 1])
        else:
            f_new = chosen[0] * 2.0
        if f_lo <= f_new <= f_hi:
            chosen = np.sort(np.append(chosen, f_new))
        else:
            # octave extension downward then upward
            candidate = chosen[0] * 0.5
            if candidate >= f_lo:
                chosen = np.sort(np.append(chosen, candidate))
            else:
                candidate = chosen[-1] * 2.0
                if candidate <= f_hi:
                    chosen = np.sort(np.append(chosen, candidate))
                else:
                    break

    return chosen[:n_pitches]


# ─────────────────────────────────────────────────────────────────────────────
# E -- Build resonator bank
# ─────────────────────────────────────────────────────────────────────────────

class Resonator:
    """Second-order IIR digital resonator."""
    __slots__ = ("freq", "r", "gain", "sos", "_omega")

    def __init__(self, freq, r, gain):
        self.freq = float(freq)
        self.r    = float(r)
        self.gain = float(gain)
        omega     = 2.0 * math.pi * freq  # divided by sr later
        self.sos  = None
        self._omega = omega

    def build_sos(self, sr):
        omega = self._omega / sr
        r     = self.r
        b0    = self.gain
        self.sos = np.array([[b0, 0.0, 0.0,
                              1.0, -2.0 * r * math.cos(omega), r * r]],
                            dtype=np.float64)


def build_resonator_bank(pitches, sr, character, decay_s, spectral_flatness,
                         n_strings):
    """
    Build a list of Resonator objects, one per discovered pitch.

    Spectral flatness modulates:
      - effective decay (noisier -> faster decay)
      - bandwidth (noisier -> wider resonators)
      - gain spread (noisier -> more uniform gain across strings)
    """
    p           = CHAR_PRESETS[character]
    flat        = float(np.clip(spectral_flatness, 0.0, 1.0))
    flat_factor = 1.0 - 0.65 * flat
    eff_decay   = max(0.05, decay_s * p["decay_scale"] * flat_factor)

    r_global    = math.exp(-6.908 / max(eff_decay * sr, 1.0))
    bw_extra    = 1.0 + flat * 2.5
    brightness  = p["brightness"] * (1.0 + 0.4 * flat)
    inharmon    = p["inharmonicity"]

    resonators = []
    n           = max(len(pitches), 1)

    for i, f0 in enumerate(pitches):
        # Optional inharmonic stretch (metallic stiffness)
        if inharmon > 0:
            freq = f0 * math.sqrt(1.0 + inharmon * (i + 1) ** 2)
        else:
            freq = f0

        freq = float(np.clip(freq, 20.0, sr * 0.48))

        bw_hz  = freq * (2.0 ** (p["bw_semitones"] * bw_extra / 12.0) - 1.0)
        bw_hz  = max(bw_hz, 0.5)
        r_bw   = 1.0 - math.pi * bw_hz / sr
        r      = float(np.clip(min(r_global, r_bw), 0.01, 0.999985))

        # Harmonic amplitude: 1/k^harm_rolloff, already baked into entries.
        # Use it directly; compensate for pole peak gain.
        harm_amp  = 1.0  # will be overridden below per-entry
        peak_gain = 1.0 / max(1.0 - r * r, 1e-8)

        # Compensate for source spectral rolloff.
        # Speech/voice has roughly -6 dB/octave tilt; without correction,
        # high-frequency resonators receive far less excitation energy and
        # the output sounds like an LPF regardless of post-EQ.
        # We boost each resonator gain by (freq / f_ref)^(tilt_db/20/log2)
        # so that doubling frequency adds src_tilt_db_oct dB of gain.
        tilt_exp  = p["src_tilt_db_oct"] / (20.0 * math.log10(2.0))
        tilt_gain = (freq / max(f0_ref, 20.0)) ** tilt_exp
        tilt_gain = float(np.clip(tilt_gain, 0.5, 40.0))

        gain = (harm_amp / n) / peak_gain * tilt_gain

        res = Resonator(freq, r, gain)
        res.build_sos(sr)
        resonators.append(res)

    return resonators


def expand_with_harmonics(base_pitches, n_harmonics, harm_rolloff,
                          inharmonicity, nyquist):
    """
    For each base pitch generate harmonic overtones up to Nyquist.
    Returns list of (freq_hz, relative_gain) tuples.
    """
    entries = []
    for f0 in base_pitches:
        for k in range(1, n_harmonics + 2):
            if inharmonicity > 0:
                freq = f0 * k * math.sqrt(1.0 + inharmonicity * k * k)
            else:
                freq = f0 * k
            if freq >= nyquist:
                break
            amp = 1.0 / (k ** harm_rolloff)
            entries.append((float(freq), float(amp)))
    return entries


def build_harmonic_resonator_bank(pitches, sr, character, decay_s,
                                  spectral_flatness, n_strings):
    """
    Expanded resonator bank including harmonic series of each discovered pitch.
    Each partial decays faster than the fundamental (realistic string physics).
    b0 compensated for IIR peak gain so amplitude is well-behaved.
    """
    p         = CHAR_PRESETS[character]
    flat      = float(np.clip(spectral_flatness, 0.0, 1.0))
    eff_decay = max(0.05, decay_s * p["decay_scale"] * (1.0 - 0.65 * flat))
    bw_extra  = 1.0 + flat * 2.5
    nyquist   = sr * 0.48

    entries = expand_with_harmonics(pitches, p["n_harmonics"],
                                    p["harm_rolloff"], p["inharmonicity"],
                                    nyquist)

    # Deduplicate within 2 cents
    entries.sort(key=lambda x: x[0])
    deduped = []
    for freq, amp in entries:
        if deduped and abs(math.log(freq / deduped[-1][0])) < 0.00116:
            if amp > deduped[-1][1]:
                deduped[-1] = (freq, amp)
        else:
            deduped.append([freq, amp])

    # Subsample uniformly in log-frequency space so upper harmonics
    # are represented. Sorting by amplitude would keep only the lowest
    # partials (k=1 has amp=1.0, k=2 has 0.5, ...) producing an LPF effect.
    if len(deduped) > n_strings:
        import numpy as _np
        log_f  = _np.log([e[0] for e in deduped])
        lo, hi = log_f[0], log_f[-1]
        targets = _np.linspace(lo, hi, n_strings)
        picked  = set()
        for t in targets:
            idx = int(_np.argmin(_np.abs(log_f - t)))
            picked.add(idx)
        deduped = [deduped[i] for i in sorted(picked)]
    deduped.sort(key=lambda x: x[0])

    n = max(len(deduped), 1)
    f0_ref = pitches[0] if len(pitches) > 0 else deduped[0][0]

    resonators = []
    for freq, harm_amp in deduped:
        freq = float(np.clip(freq, 20.0, nyquist))

        # Higher partials decay faster
        k_approx  = max(1.0, freq / f0_ref)
        eff_k     = max(0.05, eff_decay / (k_approx ** 0.35))
        r_partial = math.exp(-6.908 / max(eff_k * sr, 1.0))

        bw_hz = freq * (2.0 ** (p["bw_semitones"] * bw_extra / 12.0) - 1.0)
        bw_hz = max(bw_hz, 0.5)
        r_bw  = 1.0 - math.pi * bw_hz / sr
        r     = float(np.clip(min(r_partial, r_bw), 0.01, 0.999985))

        peak_gain = 1.0 / max(1.0 - r * r, 1e-8)

        # Compensate for source spectral rolloff.
        # Speech/voice has roughly -6 dB/octave tilt; without correction,
        # high-frequency resonators receive far less excitation energy and
        # the output sounds like an LPF regardless of post-EQ.
        # We boost each resonator gain by (freq / f_ref)^(tilt_db/20/log2)
        # so that doubling frequency adds src_tilt_db_oct dB of gain.
        tilt_exp  = p["src_tilt_db_oct"] / (20.0 * math.log10(2.0))
        tilt_gain = (freq / max(f0_ref, 20.0)) ** tilt_exp
        tilt_gain = float(np.clip(tilt_gain, 0.5, 40.0))

        gain = (harm_amp / n) / peak_gain * tilt_gain

        res = Resonator(freq, r, gain)
        res.build_sos(sr)
        resonators.append(res)

    return resonators


# ─────────────────────────────────────────────────────────────────────────────
# F -- Excite resonators
# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────────────────
# F+G+H -- FFT-domain resonator bank + coupling + stereo render
# ─────────────────────────────────────────────────────────────────────────────
#
# Speed strategy: instead of calling sosfilt N times (one per resonator),
# compute every resonator's frequency response H_i(omega) analytically,
# apply Gaussian coupling in the frequency-response domain, weight by
# L/R pan gains, and collapse to two summed frequency responses H_L / H_R.
# Then: output = IFFT( FFT(input) * H_L/R ).
# Total cost: 1 FFT + vectorised numpy across N resonators + 2 IFFTs.
# Scales in O(N_fft * n_res) instead of O(n_res * N_fft) sequential calls.

def _shelf_sos(sr, character):
    """Return high-shelf SOS coefficients as numpy array (1,6)."""
    p       = CHAR_PRESETS[character]
    gain_db = p["brightness"]
    f0      = p["shelf_freq_hz"]
    if abs(gain_db) < 0.1:
        return None
    A     = 10.0 ** (gain_db / 40.0)
    w0    = 2.0 * math.pi * f0 / sr
    cosw0 = math.cos(w0)
    sinw0 = math.sin(w0)
    sqA   = math.sqrt(A)
    alpha = sinw0 / 2.0 * math.sqrt(2.0) * sqA
    b0 =     A * ((A+1) + (A-1)*cosw0 + 2.0*sqA*alpha)
    b1 = -2.0*A * ((A-1) + (A+1)*cosw0)
    b2 =     A * ((A+1) + (A-1)*cosw0 - 2.0*sqA*alpha)
    a0 =          (A+1) - (A-1)*cosw0 + 2.0*sqA*alpha
    a1 =    2.0 * ((A-1) - (A+1)*cosw0)
    a2 =          (A+1) - (A-1)*cosw0 - 2.0*sqA*alpha
    return np.array([[b0/a0, b1/a0, b2/a0, 1.0, a1/a0, a2/a0]],
                    dtype=np.float64)


def _shelf_freq_response(sos, n_fft):
    """Evaluate shelf SOS frequency response at rfft bins, shape (n_fft//2+1,)."""
    if sos is None:
        return np.ones(n_fft // 2 + 1, dtype=np.complex128)
    k      = np.arange(n_fft // 2 + 1)
    z_inv  = np.exp(-2j * np.pi * k / n_fft)
    z_inv2 = z_inv ** 2
    b0, b1, b2, _, a1, a2 = sos[0]
    return (b0 + b1 * z_inv + b2 * z_inv2) / (1.0 + a1 * z_inv + a2 * z_inv2)


def compute_pan_gains(n_res):
    """
    Equal-power stereo pan spread with guaranteed energy balance.
    Uniform grid over [0, pi/2] guarantees sum(cos^2) == sum(sin^2).
    Sinusoidal warp breaks monotone low=left/high=right without bias.
    Final RMS rescale enforces exact channel energy equality after warping.
    """
    base  = np.linspace(0.0, np.pi / 2.0, n_res)
    warp  = (np.pi / 8.0) * np.sin(np.linspace(0.0, 2.0 * np.pi, n_res))
    angle = np.clip(base + warp, 0.0, np.pi / 2.0)
    lg    = np.cos(angle)
    rg    = np.sin(angle)
    lrms  = float(np.sqrt(np.mean(lg ** 2)))
    rrms  = float(np.sqrt(np.mean(rg ** 2)))
    if lrms > 1e-10 and rrms > 1e-10:
        mid = (lrms + rrms) / 2.0
        lg  = lg * (mid / lrms)
        rg  = rg * (mid / rrms)
    return lg.astype(np.float64), rg.astype(np.float64)


def soft_limit(signal, threshold=0.85):
    """Soft-knee limiter: tanh shaping above threshold, fully vectorised."""
    out   = signal.copy()
    sign  = np.sign(out)
    sign[sign == 0] = 1.0
    abs_s = np.abs(out)
    mask  = abs_s > threshold
    scale = 1.0 - threshold
    abs_s[mask] = threshold + scale * np.tanh((abs_s[mask] - threshold) / scale)
    return sign * abs_s


def render_fft(signal, resonators, sr, coupling, character, wet_dry):
    """
    FFT-domain stereo render. Replaces the sosfilt loop entirely.

    Steps:
    1. Pad signal to n_fft = next power of 2 >= len(signal) + max_ir_len
       (max_ir_len ~ T60 * sr for the longest-decaying resonator)
    2. Forward rfft of padded signal -> X [n_fft//2+1]
    3. Build resonator frequency responses H_i analytically [n_res, n_fft//2+1]
    4. Gaussian coupling: blur H_i across resonator axis
    5. Weight by L/R pan gains -> H_L, H_R [n_fft//2+1]
    6. Apply shelf EQ in frequency domain -> H_L *= H_shelf, same for R
    7. Multiply X * H_L, X * H_R -> irfft -> trim to output length
    8. Wet/dry blend, soft-limit, normalise
    """
    n_sig   = len(signal)
    sig64   = signal.astype(np.float64)
    n_res   = len(resonators)

    # Output length: signal + tail from longest decay
    r_max    = max(res.r for res in resonators)
    # T60 in samples = -6.908 / log(r_max)
    tail_smp = int(min(-6.908 / max(math.log(r_max), -30.0), sr * 60.0))
    n_out    = n_sig + tail_smp
    # Next power of 2 for FFT efficiency
    n_fft    = 1
    while n_fft < n_out:
        n_fft <<= 1

    print("    FFT size: %d  (signal %d + tail %d)"
          % (n_fft, n_sig, tail_smp))

    # Step 2: forward FFT
    X = np.fft.rfft(sig64, n=n_fft)           # complex128, shape (n_fft//2+1,)
    n_bins = len(X)

    # Step 3: resonator frequency responses, vectorised across all bins
    # H_i(omega_k) = b0 / (1 + a1*z^-1 + a2*z^-2)  where z = e^(j*2pi*k/n_fft)
    k       = np.arange(n_bins, dtype=np.float64)
    z_inv   = np.exp(-2j * np.pi * k / n_fft)     # (n_bins,)
    z_inv2  = z_inv * z_inv

    # Collect SOS coefficients for all resonators at once
    b0_arr = np.array([res.sos[0, 0] for res in resonators])   # (n_res,)
    a1_arr = np.array([res.sos[0, 4] for res in resonators])
    a2_arr = np.array([res.sos[0, 5] for res in resonators])

    # H shape: (n_res, n_bins)  -- outer product via broadcasting
    denom = 1.0 + a1_arr[:, None] * z_inv[None, :]                 + a2_arr[:, None] * z_inv2[None, :]
    H = b0_arr[:, None] / denom                               # (n_res, n_bins)

    # Step 4: Gaussian coupling across resonator axis
    coup_scale = CHAR_PRESETS[character]["coupling_scale"]
    eff_coup   = float(np.clip(coupling * coup_scale, 0.0, 3.0))
    if eff_coup > 0.001 and n_res >= 3:
        sigma   = max(0.5, eff_coup * 2.5)
        # Blur magnitude, keep phase from original H
        H_mag   = gaussian_filter1d(np.abs(H), sigma=sigma, axis=0)
        H_phase = np.angle(H)
        H_coupled = H_mag * np.exp(1j * H_phase) + eff_coup * gaussian_filter1d(H, sigma=sigma, axis=0).real
        H = H + eff_coup * (H_coupled - H)
    
    # Step 5: pan gains -> weighted sum to L and R
    lg, rg  = compute_pan_gains(n_res)
    H_L     = (lg[:, None] * H).sum(axis=0)   # (n_bins,)
    H_R     = (rg[:, None] * H).sum(axis=0)

    # Step 6: apply shelf EQ in frequency domain
    shelf_sos = _shelf_sos(sr, character)
    H_shelf   = _shelf_freq_response(shelf_sos, n_fft)
    H_L      *= H_shelf
    H_R      *= H_shelf

    # Step 7: multiply and IFFT
    left  = np.fft.irfft(X * H_L, n=n_fft)[:n_out]
    right = np.fft.irfft(X * H_R, n=n_fft)[:n_out]

    # Step 8: wet/dry blend
    wet_dry = float(np.clip(wet_dry, 0.0, 1.0))
    if wet_dry > 0.0:
        dry64   = np.zeros(n_out, dtype=np.float64)
        dry64[:n_sig] = sig64
        wet_rms = max(float(np.sqrt(np.mean(((left + right) / 2.0) ** 2))), 1e-10)
        dry_rms = max(float(np.sqrt(np.mean(dry64 ** 2))), 1e-10)
        scale   = dry_rms / wet_rms
        left    = (1.0 - wet_dry) * left  * scale + wet_dry * dry64
        right   = (1.0 - wet_dry) * right * scale + wet_dry * dry64

    left  = soft_limit(left)
    right = soft_limit(right)
    peak  = max(float(np.max(np.abs(left))), float(np.max(np.abs(right))))
    if peak > 1e-8:
        left  = left  / peak * 0.92
        right = right / peak * 0.92

    return np.column_stack([left, right]).astype(np.float32)


# ─────────────────────────────────────────────────────────────────────────────
# I -- Writers
# ─────────────────────────────────────────────────────────────────────────────

def write_stats(path, resonators, spectral_flatness, character, decay_s,
                coupling, wet_dry, sr, n_top=8):
    # Build comma-separated top pitch list (up to n_top)
    freqs    = sorted([r.freq for r in resonators])
    top_step = max(1, len(freqs) // n_top)
    top_hz   = freqs[::top_step][:n_top]
    pitches_str = ",".join("%.1f" % f for f in top_hz)

    with open(path, "w", encoding="utf-8") as f:
        f.write("n_strings=%d\n"         % len(resonators))
        f.write("character=%s\n"         % character)
        f.write("spectral_flatness=%.4f\n" % spectral_flatness)
        f.write("decay_s=%.3f\n"         % decay_s)
        f.write("coupling=%.4f\n"        % coupling)
        f.write("wet_dry=%.4f\n"         % wet_dry)
        f.write("sr=%d\n"                % sr)
        f.write("top_pitches=%s\n"       % pitches_str)


def write_resonances_csv(path, resonators):
    """Write freq_hz and normalised gain for Praat visualisation."""
    gains = np.array([r.gain for r in resonators], dtype=float)
    g_max = gains.max() if gains.max() > 1e-10 else 1.0
    gains_norm = gains / g_max

    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["freq_hz", "gain"])
        for res, gn in zip(resonators, gains_norm):
            writer.writerow(["%.4f" % res.freq, "%.6f" % float(gn)])


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Sympathetic Resonance -- virtual string physical model")
    parser.add_argument("--input",       required=True)
    parser.add_argument("--output",      required=True)
    parser.add_argument("--stats",       required=True)
    parser.add_argument("--resonances",  required=True)
    parser.add_argument("--character",   default="metallic",
        choices=["metallic", "glassy", "wooden", "airy"])
    parser.add_argument("--n_strings",   type=int,   default=32)
    parser.add_argument("--decay_s",     type=float, default=5.0)
    parser.add_argument("--coupling",    type=float, default=0.30)
    parser.add_argument("--wet_dry",     type=float, default=0.0,
        help="0=100%% wet resonance, 1=100%% dry original")
    args = parser.parse_args()

    args.n_strings = max(4,   min(96,   args.n_strings))
    args.decay_s   = max(0.1, min(60.0, args.decay_s))
    args.coupling  = max(0.0, min(2.0,  args.coupling))
    args.wet_dry   = max(0.0, min(1.0,  args.wet_dry))

    # ── A: Load ───────────────────────────────────────────────────────────
    print("[Py 1/6] Loading audio...")
    audio, sr = load_audio(args.input)
    print("    %d samples  |  %d Hz  |  %.2f s" % (len(audio), sr, len(audio) / sr))

    # ── B: Log-frequency spectrum ──────────────────────────────────────────
    print("[Py 2/6] Computing log-frequency spectrum...")
    log_stft, log_freqs = compute_log_spectrum(audio, sr)
    print("    Bins: %d  |  Frames: %d  |  freq range: %.1f-%.1f Hz"
          % (log_stft.shape[0], log_stft.shape[1],
             log_freqs[0], log_freqs[-1]))

    # ── C: Spectral flatness ───────────────────────────────────────────────
    print("[Py 3/6] Measuring spectral flatness...")
    spectral_flatness = compute_spectral_flatness(audio, sr)
    print("    Flatness: %.4f  (0=tonal  1=noise)" % spectral_flatness)

    # ── D: Discover latent pitches ─────────────────────────────────────────
    print("[Py 4/6] Discovering latent pitch collection...")
    pitches = discover_latent_pitches(log_stft, log_freqs, args.n_strings)
    print("    Discovered %d pitches  |  range %.1f - %.1f Hz"
          % (len(pitches), pitches[0], pitches[-1]))

    # ── E: Build resonators ────────────────────────────────────────────────
    print("[Py 5/6] Building resonator bank (%s)..." % args.character)
    resonators = build_harmonic_resonator_bank(pitches, sr, args.character,
                                              args.decay_s, spectral_flatness,
                                              args.n_strings)
    print("    Resonators: %d" % len(resonators))
    r_vals = [r.r for r in resonators]
    print("    Pole radius r:  min=%.6f  max=%.6f" % (min(r_vals), max(r_vals)))

    # ── F+G+H: Excite, couple, render ─────────────────────────────────────
    print("[Py 6/6] Exciting resonators and rendering...")
    r_vals  = [res.r for res in resonators]
    b0_vals = [res.sos[0, 0] for res in resonators]
    f_vals  = [res.freq for res in resonators]
    print("    DEBUG r:    min=%.8f  max=%.8f  mean=%.8f"
          % (min(r_vals), max(r_vals), sum(r_vals)/len(r_vals)))
    print("    DEBUG b0:   min=%.3e  max=%.3e  mean=%.3e"
          % (min(b0_vals), max(b0_vals), sum(b0_vals)/len(b0_vals)))
    print("    DEBUG freq: min=%.1f Hz  max=%.1f Hz  n=%d"
          % (min(f_vals), max(f_vals), len(f_vals)))
    print("    DEBUG input: peak=%.4f  RMS=%.6f"
          % (float(np.max(np.abs(audio))), float(np.sqrt(np.mean(audio**2)))))

    result = render_fft(audio, resonators, sr,
                         args.coupling, args.character, args.wet_dry)
    print("    Output: peak=%.4f  RMS=%.6f  shape=%s"
          % (float(np.max(np.abs(result))),
             float(np.sqrt(np.mean(result ** 2))),
             str(result.shape)))

    # Write output WAV
    sf.write(args.output, result, sr, subtype="PCM_24")

    # Write stats and resonances
    write_stats(args.stats, resonators, spectral_flatness,
                args.character, args.decay_s, args.coupling, args.wet_dry, sr)
    write_resonances_csv(args.resonances, resonators)

    print("OK: %s" % args.output)


if __name__ == "__main__":
    main()
