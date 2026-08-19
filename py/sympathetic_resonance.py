"""
sympathetic_resonance.py  --  Sympathetic Resonance  v1.2

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University
Email: shai.cohen@biu.ac.il

Called by SympatheticResonance.praat -- not run directly.

Version 1.2 (2026) — review repairs:
  * Energy-gated spectral flatness: silence no longer reads as white noise.
  * Latent pitch discovery keeps only measured peaks; N_strings is the maximum
    total resonator count, filled by measured-pitch harmonic partials rather
    than invented geometric-midpoint pitches.
  * Higher-resolution interpolated pseudo-CQT grid for more accurate pitches.
  * Strongest-RMS real channel drives analysis/excitation; stereo dry path is
    preserved (or the two strongest channels for >2ch input).
  * Blocked FFT-domain response evaluation: audio-equivalent to the v1.0 full
    response matrix, with bounded memory for long tails / large banks.
  * Wet_dry=1 is exact dry audio; mixed wet-level matching uses source-region
    multichannel RMS rather than phase-cancellable mono fold-down.
  * FLOAT output and richer QC/stats for analysis channel, base pitches, active
    resonators, effective decay and output routing.

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
    A -- Load audio; choose strongest real channel for analysis/excitation
    B -- Compute STFT and build log-frequency (pseudo-CQT) representation
    C -- Measure spectral flatness as a global control signal
    D -- Discover measured spectral peaks in log-frequency space
         (optional Cloud fill is an explicit AudioTools extension)
    E -- Build resonator bank: per-string pole radius r computed from
         decay_s and character bandwidth; gain shaped by brightness curve
         and spectral flatness; stiffness inharmonicity for metallic
    F -- Excite all resonators with the source signal in parallel
         using second-order IIR filters (scipy.signal.sosfilt)
    G -- Apply sympathetic coupling: Gaussian blur across the
         frequency axis of the output matrix
    H -- Character spectral shaping, wet/dry blend, soft-limit, write FLOAT output
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
    """Load input without level normalisation.

    Returns
    -------
    analysis : float32 mono
        Strongest-RMS *real* input channel. This avoids phase-cancelling
        fold-downs while keeping the resonator model single-excitation.
    dry_stereo : float32 (n, 2)
        Mono is duplicated; stereo is preserved exactly; >2ch uses the two
        strongest real channels (kept in source channel order).
    sr : int
    analysis_channel : int (1-based)
    dry_channels : tuple of 1-based source channel indices
    input_channels : int
    """
    audio, sr = sf.read(path, always_2d=True, dtype="float32")
    audio = np.asarray(audio, dtype=np.float32)
    if audio.shape[0] < 1:
        raise ValueError("input audio is empty")

    rms = np.sqrt(np.mean(audio.astype(np.float64) ** 2, axis=0) + 1e-30)
    analysis_idx = int(np.argmax(rms))
    analysis = audio[:, analysis_idx].copy()

    n_ch = int(audio.shape[1])
    if n_ch == 1:
        dry_stereo = np.repeat(audio, 2, axis=1)
        dry_indices = (0, 0)
    elif n_ch == 2:
        dry_stereo = audio[:, :2].copy()
        dry_indices = (0, 1)
    else:
        top2 = np.argsort(rms)[-2:]
        top2 = np.sort(top2)
        dry_stereo = audio[:, top2].copy()
        dry_indices = (int(top2[0]), int(top2[1]))

    return (analysis, dry_stereo, int(sr), analysis_idx + 1,
            tuple(i + 1 for i in dry_indices), n_ch)


# ─────────────────────────────────────────────────────────────────────────────
# B -- Log-frequency (pseudo-CQT) representation
# ─────────────────────────────────────────────────────────────────────────────

def compute_log_spectrum(audio, sr, n_fft=4096, hop=512, n_bins=480,
                         f_min=32.7, f_max=5000.0):
    """Interpolated log-frequency magnitude representation.

    v1.2 increases the grid density and linearly interpolates the linear-FFT
    magnitudes at log-spaced target frequencies. The old nearest-bin 120-bin
    grid had ~73-cent spacing and could quantise a 440-Hz tone near 431/450 Hz.
    """
    n = len(audio)
    if n < 1:
        raise ValueError("cannot analyse empty audio")
    n_fft_fb = min(n_fft, max(n, 256))
    n_fft_fb = max(256, 2 ** int(np.floor(np.log2(n_fft_fb))))
    win      = np.hanning(n_fft_fb).astype(np.float32)
    freqs_fb = np.fft.rfftfreq(n_fft_fb, 1.0 / sr)

    frames = []
    if n < n_fft_fb:
        frame = np.zeros(n_fft_fb, dtype=np.float32)
        frame[:n] = audio
        frames.append(np.abs(np.fft.rfft(frame * win)))
    else:
        pos = 0
        while pos + n_fft_fb <= n:
            frames.append(np.abs(np.fft.rfft(audio[pos:pos + n_fft_fb] * win)))
            pos += hop
    stft_fb = np.array(frames, dtype=np.float32).T

    f_min_eff = max(f_min, freqs_fb[1])
    f_max_eff = min(f_max, freqs_fb[-1])
    log_freqs = np.logspace(np.log10(f_min_eff), np.log10(f_max_eff), n_bins)

    # Vectorised linear interpolation along the linear-frequency FFT grid.
    hi = np.searchsorted(freqs_fb, log_freqs, side="left")
    hi = np.clip(hi, 1, len(freqs_fb) - 1)
    lo = hi - 1
    den = np.maximum(freqs_fb[hi] - freqs_fb[lo], 1e-12)
    frac = ((log_freqs - freqs_fb[lo]) / den).astype(np.float32)
    log_mag = ((1.0 - frac[:, None]) * stft_fb[lo, :]
               + frac[:, None] * stft_fb[hi, :])

    print("    Log-spectrum: %d bins  |  %d frames  |  %.1f-%.1f Hz"
          % (n_bins, log_mag.shape[1], log_freqs[0], log_freqs[-1]))
    return log_mag.astype(np.float32), log_freqs.astype(np.float32)


# ─────────────────────────────────────────────────────────────────────────────
# C -- Spectral flatness
# ─────────────────────────────────────────────────────────────────────────────

def compute_spectral_flatness(audio, sr, n_fft=2048, hop=512):
    """Energy-gated spectral flatness, 0=tonal and 1=white-noise-like.

    Silent Hann frames have geometric mean == arithmetic mean at the epsilon
    floor and therefore read as flatness=1. v1.2 excludes frames more than
    60 dB below the strongest frame so leading/trailing silence cannot turn a
    tonal source into a nominally noisy one.
    Returns (flatness, active_frames, total_frames).
    """
    n = len(audio)
    if n < 8:
        return 0.0, 0, 0
    n_fft = min(n_fft, n)
    win   = np.hanning(n_fft).astype(np.float32)
    vals, rms_vals = [], []
    pos = 0
    while pos + n_fft <= n:
        frame = audio[pos:pos + n_fft]
        rms = float(np.sqrt(np.mean(frame.astype(np.float64) ** 2) + 1e-30))
        spec = np.abs(np.fft.rfft(frame * win)) ** 2 + 1e-20
        geo  = float(np.exp(np.mean(np.log(spec))))
        arith = float(np.mean(spec))
        vals.append(geo / max(arith, 1e-30))
        rms_vals.append(rms)
        pos += hop
    if not vals:
        return 0.0, 0, 0
    rms_arr = np.asarray(rms_vals)
    mx = float(rms_arr.max())
    if mx <= 1e-12:
        return 0.0, 0, len(vals)
    active = rms_arr >= mx * 1e-3
    if not np.any(active):
        active[np.argmax(rms_arr)] = True
    flat = float(np.mean(np.asarray(vals)[active]))
    return float(np.clip(flat, 0.0, 1.0)), int(active.sum()), len(vals)


# ─────────────────────────────────────────────────────────────────────────────
# D -- Latent pitch discovery
# ─────────────────────────────────────────────────────────────────────────────

def discover_latent_pitches(log_stft, log_freqs, max_pitches, pitch_mode="measured"):
    """Return only spectral peaks actually supported by the source.

    v1.0 filled a short peak list to N_strings with geometric midpoints and
    octave extensions. A single 440-Hz tone could therefore become dozens of
    invented microtonal "latent pitches". v1.2 keeps measured peaks only;
    harmonic expansion is responsible for populating the resonator bank.
    """
    salience = np.power(np.maximum(log_stft, 0.0), 1.5).mean(axis=1)
    if len(salience) < 3 or float(salience.max()) <= 1e-15:
        mid = math.sqrt(float(log_freqs[0]) * float(log_freqs[-1]))
        return np.array([mid], dtype=np.float64)

    bin_cents = 1200.0 * math.log(float(log_freqs[1] / log_freqs[0]), 2.0)
    min_sep_bins = max(1, int(round(70.0 / max(bin_cents, 1e-6))))
    prominence = max(float(salience.std()) * 0.20,
                     float(salience.max()) * 0.015, 1e-15)
    peaks, props = find_peaks(salience, prominence=prominence,
                              distance=min_sep_bins)
    if len(peaks) == 0:
        peaks = np.array([int(np.argmax(salience))], dtype=int)
        prom = np.array([float(salience[peaks[0]])])
    else:
        prom = props.get("prominences", salience[peaks])

    # Refine each peak by a 3-point parabola in log-frequency coordinates.
    refined = []
    for pk, pr in zip(peaks, prom):
        pk = int(pk)
        delta = 0.0
        if 0 < pk < len(salience) - 1:
            y0 = math.log(float(salience[pk - 1]) + 1e-30)
            y1 = math.log(float(salience[pk])     + 1e-30)
            y2 = math.log(float(salience[pk + 1]) + 1e-30)
            den = y0 - 2.0 * y1 + y2
            if abs(den) > 1e-12:
                delta = float(np.clip(0.5 * (y0 - y2) / den, -0.5, 0.5))
        if pk < len(log_freqs) - 1:
            step = math.log(float(log_freqs[pk + 1] / log_freqs[pk]))
        else:
            step = math.log(float(log_freqs[pk] / log_freqs[pk - 1]))
        freq = math.exp(math.log(float(log_freqs[pk])) + delta * step)
        refined.append((freq, float(pr)))

    # Keep strongest measured peaks, capped so harmonics still participate in
    # the final n_strings-sized bank. No synthetic midpoint pitches are added.
    max_base = max(1, min(int(max_pitches), 24))
    refined.sort(key=lambda x: x[1], reverse=True)
    chosen = np.asarray(sorted(f for f, _ in refined[:max_base]), dtype=np.float64)

    if pitch_mode == "cloud":
        # Preserve the musically useful AudioTools cloud behavior, but label it
        # honestly as synthetic filling rather than measured latent pitches.
        f_lo, f_hi = float(log_freqs[0]), float(log_freqs[-1])
        attempts = 0
        while len(chosen) < max_pitches and attempts < max_pitches * 6:
            attempts += 1
            if len(chosen) > 1:
                gaps = np.diff(np.log(chosen))
                widest = int(np.argmax(gaps))
                f_new = math.sqrt(chosen[widest] * chosen[widest + 1])
            else:
                # With one measured pitch, build an octave-related scaffold
                # before subdividing it; this is more musically legible than
                # repeatedly crowding one side of the peak.
                up = chosen[-1] * 2.0
                dn = chosen[0] * 0.5
                if up <= f_hi:
                    f_new = up
                elif dn >= f_lo:
                    f_new = dn
                else:
                    break
            if not (f_lo <= f_new <= f_hi):
                break
            if np.min(np.abs(1200.0 * np.log2(chosen / f_new))) < 1.0:
                break
            chosen = np.sort(np.append(chosen, f_new))
        return chosen[:max_pitches]

    return chosen


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
    f0_ref      = pitches[0] if len(pitches) > 0 else 220.0

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


def _shelf_freq_response_bins(sos, n_fft, k):
    """Shelf response for an arbitrary rfft-bin index vector."""
    if sos is None:
        return np.ones(len(k), dtype=np.complex128)
    z_inv = np.exp(-2j * np.pi * k / n_fft)
    z2 = z_inv * z_inv
    b0, b1, b2, _, a1, a2 = sos[0]
    return (b0 + b1 * z_inv + b2 * z2) / (1.0 + a1 * z_inv + a2 * z2)


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


def render_fft(signal, dry_stereo, resonators, sr, coupling, character,
               wet_dry, response_block_bins=8192):
    """Blocked FFT-domain stereo render.

    The resonator transfer formula and v1.0 coupling law are intentionally
    preserved. Only the frequency-bin dimension is processed in blocks, so the
    result is numerically equivalent without allocating n_res x n_bins complex
    matrices for the full FFT at once.
    """
    n_sig = len(signal)
    sig64 = signal.astype(np.float64)
    dry_stereo = np.asarray(dry_stereo, dtype=np.float64)
    n_res = len(resonators)
    if n_res < 1:
        raise ValueError("resonator bank is empty")

    wet_dry = float(np.clip(wet_dry, 0.0, 1.0))
    if wet_dry >= 1.0 - 1e-12:
        # "100% dry original" means exactly that: no limiter, no normalisation,
        # no synthetic resonance tail. Mono has already been duplicated to L/R.
        return dry_stereo.astype(np.float32), {
            "fft_size": 0, "tail_samples": 0, "response_block_bins": 0,
            "wet_match_scale": 0.0,
        }

    r_max = max(res.r for res in resonators)
    tail_smp = int(min(-6.908 / max(math.log(r_max), -30.0), sr * 60.0))
    n_out = n_sig + tail_smp
    n_fft = 1
    while n_fft < n_out:
        n_fft <<= 1
    print("    FFT size: %d  (signal %d + tail %d)" % (n_fft, n_sig, tail_smp))

    X = np.fft.rfft(sig64, n=n_fft)
    n_bins = len(X)
    H_L = np.zeros(n_bins, dtype=np.complex128)
    H_R = np.zeros(n_bins, dtype=np.complex128)

    b0_arr = np.array([res.sos[0, 0] for res in resonators], dtype=np.float64)
    a1_arr = np.array([res.sos[0, 4] for res in resonators], dtype=np.float64)
    a2_arr = np.array([res.sos[0, 5] for res in resonators], dtype=np.float64)
    lg, rg = compute_pan_gains(n_res)
    shelf_sos = _shelf_sos(sr, character)

    coup_scale = CHAR_PRESETS[character]["coupling_scale"]
    eff_coup = float(np.clip(coupling * coup_scale, 0.0, 3.0))
    block = max(256, int(response_block_bins))

    for lo in range(0, n_bins, block):
        hi = min(n_bins, lo + block)
        k = np.arange(lo, hi, dtype=np.float64)
        z_inv = np.exp(-2j * np.pi * k / n_fft)
        z_inv2 = z_inv * z_inv
        denom = (1.0 + a1_arr[:, None] * z_inv[None, :]
                 + a2_arr[:, None] * z_inv2[None, :])
        H = b0_arr[:, None] / denom

        if eff_coup > 0.001 and n_res >= 3:
            sigma = max(0.5, eff_coup * 2.5)
            H_mag = gaussian_filter1d(np.abs(H), sigma=sigma, axis=0)
            H_phase = np.angle(H)
            H_coupled = (H_mag * np.exp(1j * H_phase)
                         + eff_coup * gaussian_filter1d(H, sigma=sigma,
                                                        axis=0).real)
            H = H + eff_coup * (H_coupled - H)

        shelf = _shelf_freq_response_bins(shelf_sos, n_fft, k)
        H_L[lo:hi] = (lg[:, None] * H).sum(axis=0) * shelf
        H_R[lo:hi] = (rg[:, None] * H).sum(axis=0) * shelf

    left = np.fft.irfft(X * H_L, n=n_fft)[:n_out]
    right = np.fft.irfft(X * H_R, n=n_fft)[:n_out]

    wet_match_scale = 1.0
    if wet_dry > 0.0:
        dry64 = np.zeros((n_out, 2), dtype=np.float64)
        dry64[:n_sig, :] = dry_stereo[:n_sig, :]
        # Match level over the source region, not over the long zero-padded dry
        # tail, and do not mono-fold stereo (which could phase-cancel).
        wet_rms = max(float(np.sqrt(np.mean(
            0.5 * (left[:n_sig] ** 2 + right[:n_sig] ** 2)))), 1e-10)
        dry_rms = max(float(np.sqrt(np.mean(dry_stereo[:n_sig, :] ** 2))), 1e-10)
        wet_match_scale = dry_rms / wet_rms
        left = ((1.0 - wet_dry) * left * wet_match_scale
                + wet_dry * dry64[:, 0])
        right = ((1.0 - wet_dry) * right * wet_match_scale
                 + wet_dry * dry64[:, 1])

    left = soft_limit(left)
    right = soft_limit(right)
    peak = max(float(np.max(np.abs(left))), float(np.max(np.abs(right))))
    if peak > 1e-8:
        left = left / peak * 0.92
        right = right / peak * 0.92

    return np.column_stack([left, right]).astype(np.float32), {
        "fft_size": int(n_fft),
        "tail_samples": int(tail_smp),
        "response_block_bins": int(block),
        "wet_match_scale": float(wet_match_scale),
    }


# ─────────────────────────────────────────────────────────────────────────────
# I -- Writers
# ─────────────────────────────────────────────────────────────────────────────

def write_stats(path, resonators, base_pitches, spectral_flatness, character,
                decay_s, coupling, wet_dry, sr, analysis_channel, dry_channels,
                input_channels, flat_active, flat_total, render_qc, pitch_mode, n_top=12):
    freqs = sorted([r.freq for r in resonators])
    base = sorted(float(f) for f in base_pitches)
    top_base = base[:n_top]
    pitches_str = ",".join("%.1f" % f for f in top_base)
    if resonators:
        t60s = [-6.908 / (math.log(r.r) * sr) for r in resonators]
        t60_min, t60_max = min(t60s), max(t60s)
    else:
        t60_min = t60_max = 0.0

    with open(path, "w", encoding="utf-8") as f:
        f.write("n_strings=%d\n" % len(resonators))
        f.write("base_pitch_count=%d\n" % len(base))
        f.write("character=%s\n" % character)
        f.write("pitch_mode=%s\n" % pitch_mode)
        f.write("spectral_flatness=%.4f\n" % spectral_flatness)
        f.write("flatness_active_frames=%d\n" % flat_active)
        f.write("flatness_total_frames=%d\n" % flat_total)
        f.write("decay_s=%.3f\n" % decay_s)
        f.write("effective_t60_min_s=%.3f\n" % t60_min)
        f.write("effective_t60_max_s=%.3f\n" % t60_max)
        f.write("coupling=%.4f\n" % coupling)
        f.write("wet_dry=%.4f\n" % wet_dry)
        f.write("sr=%d\n" % sr)
        f.write("input_channels=%d\n" % input_channels)
        f.write("analysis_channel=%d\n" % analysis_channel)
        f.write("dry_channels=%s\n" % ",".join(str(x) for x in dry_channels))
        f.write("top_pitches=%s\n" % pitches_str)
        f.write("fft_size=%d\n" % int(render_qc.get("fft_size", 0)))
        f.write("tail_s=%.3f\n" % (render_qc.get("tail_samples", 0) / float(sr)))
        f.write("response_block_bins=%d\n" % int(render_qc.get("response_block_bins", 0)))


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
    parser.add_argument("--pitch_mode", choices=["measured", "cloud"], default="measured",
        help="measured=only source-supported peaks; cloud=synthetic geometric fill")
    args = parser.parse_args()

    args.n_strings = max(4,   min(96,   args.n_strings))
    args.decay_s   = max(0.1, min(60.0, args.decay_s))
    args.coupling  = max(0.0, min(2.0,  args.coupling))
    args.wet_dry   = max(0.0, min(1.0,  args.wet_dry))

    # ── A: Load ───────────────────────────────────────────────────────────
    print("[Py 1/6] Loading audio...")
    audio, dry_stereo, sr, analysis_channel, dry_channels, input_channels = load_audio(args.input)
    print("    %d samples  |  %d Hz  |  %.2f s  |  input %dch  |  analysis ch%d"
          % (len(audio), sr, len(audio) / sr, input_channels, analysis_channel))
    print("    Dry routing: source channel(s) %s -> stereo"
          % (",".join(str(x) for x in dry_channels)))

    # ── B: Log-frequency spectrum ──────────────────────────────────────────
    print("[Py 2/6] Computing log-frequency spectrum...")
    log_stft, log_freqs = compute_log_spectrum(audio, sr)
    print("    Bins: %d  |  Frames: %d  |  freq range: %.1f-%.1f Hz"
          % (log_stft.shape[0], log_stft.shape[1],
             log_freqs[0], log_freqs[-1]))

    # ── C: Spectral flatness ───────────────────────────────────────────────
    print("[Py 3/6] Measuring spectral flatness...")
    spectral_flatness, flat_active, flat_total = compute_spectral_flatness(audio, sr)
    print("    Flatness: %.4f  (0=tonal  1=noise)  |  active frames %d/%d"
          % (spectral_flatness, flat_active, flat_total))

    # ── D: Discover latent pitches ─────────────────────────────────────────
    print("[Py 4/6] Discovering latent pitch collection...")
    pitches = discover_latent_pitches(log_stft, log_freqs, args.n_strings, args.pitch_mode)
    print("    Pitch basis: %s  |  base pitches: %d  |  range %.1f - %.1f Hz"
          % (args.pitch_mode, len(pitches), pitches[0], pitches[-1]))

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

    result, render_qc = render_fft(audio, dry_stereo, resonators, sr,
                                   args.coupling, args.character, args.wet_dry)
    print("    Output: peak=%.4f  RMS=%.6f  shape=%s"
          % (float(np.max(np.abs(result))),
             float(np.sqrt(np.mean(result ** 2))),
             str(result.shape)))

    # Write output WAV
    sf.write(args.output, result, sr, subtype="FLOAT")

    # Write stats and resonances
    write_stats(args.stats, resonators, pitches, spectral_flatness,
                args.character, args.decay_s, args.coupling, args.wet_dry, sr,
                analysis_channel, dry_channels, input_channels,
                flat_active, flat_total, render_qc, args.pitch_mode)
    write_resonances_csv(args.resonances, resonators)

    print("OK: %s" % args.output)


if __name__ == "__main__":
    main()
