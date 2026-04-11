#!/usr/bin/env python3
# ============================================================
# Praat AudioTools - praat_spectral_gen.py
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.0 (2026)
# License: MIT License
#
# Description:
#   Spectral noise shaping generator. Analyses a corpus of audio
#   files, learns their spectral profile and temporal envelope,
#   then generates new audio by shaping white noise to match.
#
#   How it works:
#     1. Load corpus, compute STFT of every file
#     2. Build a bank of spectral profiles (per-frame magnitudes)
#     3. Compute the mean temporal envelope (RMS over time)
#     4. Generate white noise of target duration
#     5. STFT the noise, replace each frame's magnitude with a
#        randomly-sampled corpus profile (keeping noise phase)
#     6. Inverse STFT → shaped noise
#     7. Apply learned temporal envelope
#     8. Normalize and save
#
#   The output genuinely starts from noise but inherits the
#   spectral character of the corpus. No neural networks,
#   no training, finishes in seconds.
#
# Dependencies:
#   pip install numpy scipy soundfile
# ============================================================

import argparse
import math
import os
import sys
import time
import traceback

import numpy as np
import soundfile as sf
try:
    from scipy.signal import resample as scipy_resample
    HAS_SCIPY = True
except ImportError:
    HAS_SCIPY = False


VERSION = "1.1"


def validated_chunk_size(chunk_size, hop_length):
    """
    Ensure chunk_size is a power of 2 and at least 2× hop_length.
    Raises ValueError with a clear message if not.
    """
    if chunk_size < 2 * hop_length:
        raise ValueError(
            f"chunk_size ({chunk_size}) must be at least 2 × hop_length "
            f"({hop_length} × 2 = {2 * hop_length}). "
            f"Otherwise there are gaps in the overlap-add and output is silence."
        )
    if chunk_size & (chunk_size - 1) != 0:
        next_pow2 = 1 << (chunk_size - 1).bit_length()
        raise ValueError(
            f"chunk_size ({chunk_size}) must be a power of 2 "
            f"(e.g. 512, 1024, 2048, 4096, 8192). "
            f"Nearest valid value: {next_pow2}."
        )
    return chunk_size



def load_corpus(folder, sr, min_dur, stats):
    print("[1/5] Loading corpus...", flush=True)

    paths = []
    for root, _, files in os.walk(folder):
        for f in files:
            if f.lower().endswith((".wav", ".aif", ".aiff", ".flac")):
                paths.append(os.path.join(root, f))
    paths.sort()
    stats["files_found"] = len(paths)

    waveforms = []
    skipped = []

    for path in paths:
        try:
            audio, file_sr = sf.read(path, always_2d=True)
            audio = np.asarray(audio, dtype=np.float32)
            if audio.ndim > 1 and audio.shape[1] > 1:
                audio = audio.mean(axis=1)
            else:
                audio = audio.flatten()

            if len(audio) / file_sr < min_dur:
                skipped.append((os.path.basename(path), "too short"))
                continue

            # Resample
            if file_sr != sr and HAS_SCIPY:
                new_len = int(len(audio) * sr / file_sr)
                audio = scipy_resample(audio, new_len).astype(np.float32)
            elif file_sr != sr:
                # Linear interp fallback
                ratio = sr / file_sr
                new_len = int(len(audio) * ratio)
                indices = np.linspace(0, len(audio) - 1, new_len)
                audio = np.interp(indices, np.arange(len(audio)), audio).astype(np.float32)

            # Normalize
            peak = np.max(np.abs(audio))
            if peak > 1e-6:
                audio = audio / peak * 0.95

            waveforms.append(audio)
        except Exception as exc:
            skipped.append((os.path.basename(path), str(exc)))

    stats["files_used"] = len(waveforms)
    stats["files_skipped"] = len(skipped)
    stats["skipped_details"] = skipped
    print(f"  Loaded: {len(waveforms)}  Skipped: {len(skipped)}", flush=True)
    return waveforms


# =============================================================================
#  STAGE 2 — ANALYSE CORPUS SPECTRA
# =============================================================================

def analyse_corpus(waveforms, sr, n_fft, hop, chunk_size):
    """
    Compute spectral profile bank + temporal envelope from corpus.

    n_fft       — FFT size used for analysis (controls frequency resolution)
    chunk_size  — frame size in samples (controls temporal resolution / grain).
                  Profiles are built from chunk_size-wide frames; n_fft is used
                  only for zero-padding when chunk_size < n_fft (rare).
                  Typically chunk_size == n_fft; user can set them independently.

    Returns:
      profile_bank: list of magnitude vectors (n_freq,) — one per
                    corpus frame across all files
      envelope:     mean RMS envelope (normalised time 0..1)
      n_freq:       number of frequency bins
    """
    print("[2/5] Analysing corpus spectra...", flush=True)
    print(f"  chunk_size={chunk_size}  ({chunk_size/sr*1000:.1f} ms)  "
          f"n_fft={n_fft}", flush=True)

    n_freq = n_fft // 2 + 1
    window = np.hanning(chunk_size)

    profile_bank = []
    envelopes = []

    for audio in waveforms:
        n_frames = max(1, (len(audio) - chunk_size) // hop + 1)

        file_mags = []
        file_rms = []

        for i in range(n_frames):
            start = i * hop
            frame = audio[start:start + chunk_size]
            if len(frame) < chunk_size:
                frame = np.pad(frame, (0, chunk_size - len(frame)))

            windowed = frame * window
            # Zero-pad to n_fft for FFT if chunk_size < n_fft,
            # or truncate window output to n_fft if chunk_size > n_fft.
            fft_input = np.zeros(n_fft, dtype=np.float32)
            copy_len = min(chunk_size, n_fft)
            fft_input[:copy_len] = windowed[:copy_len]
            spectrum = np.fft.rfft(fft_input)
            mag = np.abs(spectrum)
            file_mags.append(mag)

            rms = np.sqrt(np.mean(windowed ** 2))
            file_rms.append(rms)

        profile_bank.extend(file_mags)

        # Normalise envelope to [0, 1] time axis
        if file_rms:
            envelopes.append(np.array(file_rms, dtype=np.float32))

    profile_bank = np.array(profile_bank, dtype=np.float32)

    # Build mean envelope (resample all to common length, average)
    env_len = 200  # normalised envelope resolution
    env_sum = np.zeros(env_len, dtype=np.float64)
    for env in envelopes:
        resampled = np.interp(
            np.linspace(0, 1, env_len),
            np.linspace(0, 1, len(env)),
            env
        )
        env_sum += resampled
    mean_envelope = (env_sum / max(1, len(envelopes))).astype(np.float32)

    # Normalize envelope peak to 1
    env_peak = np.max(mean_envelope)
    if env_peak > 1e-8:
        mean_envelope = mean_envelope / env_peak

    print(f"  Profile bank: {len(profile_bank)} frames  ({n_freq} bins)", flush=True)
    print(f"  Mean envelope: {env_len} points", flush=True)

    return profile_bank, mean_envelope, n_freq


# =============================================================================
#  STAGE 3 — GENERATE
# =============================================================================

def generate(profile_bank, mean_envelope, n_freq, sr, n_fft, hop,
             duration, seed, variation, chunk_size):
    """
    Generate audio by shaping noise with corpus spectral profiles.

    chunk_size controls the synthesis grain size (temporal resolution).
    n_fft controls the frequency resolution (must match analysis n_fft).

    For each output STFT frame:
      1. Pick a random spectral profile from the bank
      2. Blend it with a second random profile (for variation)
      3. Keep the noise frame's phase (random phase = noise character)
      4. Inverse FFT + overlap-add using chunk_size-wide windows
    Then apply the learned temporal envelope.
    """
    print("[3/5] Generating from noise...", flush=True)
    print(f"  chunk_size={chunk_size}  ({chunk_size/sr*1000:.1f} ms)", flush=True)

    if seed is not None:
        np.random.seed(seed)

    n_samples = int(duration * sr)
    window = np.hanning(chunk_size)

    # Compute std of profile bank for jitter
    std_profile = np.std(profile_bank, axis=0)
    n_bank = len(profile_bank)

    # Pre-roll / post-roll: one full chunk_size of headroom on each side so
    # that the Hann window is fully summed before the first output sample,
    # eliminating the near-zero win_sum that causes boundary clicks.
    pad = chunk_size
    total_samples = n_samples + 2 * pad
    n_out_frames = max(1, (total_samples - chunk_size) // hop + 1)

    # Generate white noise for the padded length
    noise = np.random.randn(total_samples + chunk_size).astype(np.float32)

    # Output buffer for overlap-add (padded)
    output  = np.zeros(total_samples + chunk_size, dtype=np.float64)
    win_sum = np.zeros(total_samples + chunk_size, dtype=np.float64)

    for i in range(n_out_frames):
        start = i * hop

        # Window the noise frame at chunk_size, then zero-pad / truncate to
        # n_fft so the FFT bin layout matches the profile bank exactly.
        noise_frame = noise[start:start + chunk_size] * window
        fft_input = np.zeros(n_fft, dtype=np.float32)
        copy_len = min(chunk_size, n_fft)
        fft_input[:copy_len] = noise_frame[:copy_len]
        noise_spec = np.fft.rfft(fft_input)
        noise_phase = np.angle(noise_spec)

        # Pick a random corpus profile
        idx1 = np.random.randint(0, n_bank)
        profile = profile_bank[idx1].copy()

        # Blend with a second profile for variety
        if variation > 0 and n_bank > 1:
            idx2 = np.random.randint(0, n_bank)
            blend = np.random.uniform(0, variation)
            profile = profile * (1 - blend) + profile_bank[idx2] * blend

        # Add controlled randomness based on corpus variance
        if variation > 0:
            jitter = (std_profile
                      * np.random.randn(n_freq).astype(np.float32)
                      * variation * 0.3)
            profile = np.maximum(0, profile + jitter)

        # Reconstruct: corpus magnitude × noise phase → IFFT at chunk_size.
        # The profile has n_freq = n_fft//2+1 bins. The IFFT target is
        # chunk_size samples, which needs chunk_size//2+1 bins.
        # • chunk_size <= n_fft: crop spectrum to chunk_size//2+1 bins.
        # • chunk_size >  n_fft: zero-pad spectrum up to chunk_size//2+1 bins
        #   (high-frequency bins are 0 — equivalent to low-pass filtering,
        #   which is fine; the corpus spectral shape is preserved in the
        #   low-frequency part).
        n_out_bins = chunk_size // 2 + 1
        shaped_spec_full = profile * np.exp(1j * noise_phase)   # n_freq bins
        if n_out_bins <= n_freq:
            shaped_spec_cs = shaped_spec_full[:n_out_bins]
        else:
            shaped_spec_cs = np.zeros(n_out_bins, dtype=np.complex64)
            shaped_spec_cs[:n_freq] = shaped_spec_full
        shaped_frame = np.fft.irfft(shaped_spec_cs, n=chunk_size)

        # Overlap-add
        output [start:start + chunk_size] += shaped_frame * window
        win_sum[start:start + chunk_size] += window ** 2

    # Normalise overlap-add.
    # The Hann window with 75% overlap (hop = chunk_size/4) sums to ~1.5 at
    # steady state. Any sample whose win_sum is below 5% of that is in the
    # pre-roll/post-roll headroom and should be silent rather than amplified.
    threshold = 0.075   # 5% of ~1.5 steady-state win_sum
    safe_mask = win_sum > threshold
    output[safe_mask]  /= win_sum[safe_mask]
    output[~safe_mask]  = 0.0

    # Slice out the pre-roll and the exact requested length
    output = output[pad:pad + n_samples].astype(np.float32)

    # Apply temporal envelope
    env_time = np.linspace(0, 1, n_samples)
    env_curve = np.interp(env_time, np.linspace(0, 1, len(mean_envelope)),
                          mean_envelope).astype(np.float32)

    # Smooth the envelope to avoid artifacts
    smooth_n = max(1, int(0.02 * sr))
    kernel = np.ones(smooth_n) / smooth_n
    env_curve = np.convolve(env_curve, kernel, mode="same").astype(np.float32)

    output = output * env_curve

    # Short fade-in / fade-out (10 ms) as a safety net against any residual
    # discontinuity at the file boundaries.
    fade_samples = min(int(0.010 * sr), n_samples // 4)
    fade_in  = np.linspace(0.0, 1.0, fade_samples, dtype=np.float32)
    fade_out = np.linspace(1.0, 0.0, fade_samples, dtype=np.float32)
    output[:fade_samples]  *= fade_in
    output[-fade_samples:] *= fade_out

    # Final normalize
    peak = np.max(np.abs(output))
    if peak > 1e-6:
        output = output / peak * 0.9

    print(f"  Generated: {n_samples} samples ({duration:.2f}s)  "
          f"peak={np.max(np.abs(output)):.4f}", flush=True)

    return output


# =============================================================================
#  MAIN
# =============================================================================

def write_stats(path, stats):
    with open(path, "w", encoding="utf-8") as f:
        f.write("=== Spectral Noise Shaping — Stats ===\n\n")
        for key, val in stats.items():
            if key == "skipped_details":
                f.write("skipped_files:\n")
                for name, reason in (val or []):
                    f.write(f"  {name}: {reason}\n")
            else:
                f.write(f"{key}: {val}\n")


def main():
    ap = argparse.ArgumentParser(description=f"Spectral noise shaping v{VERSION}")
    ap.add_argument("input_folder", type=str)
    ap.add_argument("output_wav", type=str)
    ap.add_argument("stats_txt", type=str)
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("--duration", type=float, default=3.0)
    ap.add_argument("--sr", type=int, default=44100)
    ap.add_argument("--n_fft", type=int, default=2048)
    ap.add_argument("--hop_length", type=int, default=512)
    ap.add_argument("--chunk_size", type=int, default=None,
                    help="Analysis/synthesis frame size in samples (power of 2, "
                         ">= 2 × hop_length). Controls temporal grain: smaller = "
                         "more fluttery, larger = smoother. Defaults to n_fft.")
    ap.add_argument("--variation", type=float, default=0.5,
                    help="0 = pure mean spectrum, 1 = max variation between profiles")
    args = ap.parse_args()

    # chunk_size defaults to n_fft; validate before doing any work
    chunk_size = args.chunk_size if args.chunk_size is not None else args.n_fft
    try:
        chunk_size = validated_chunk_size(chunk_size, args.hop_length)
    except ValueError as exc:
        print(f"ERROR: {exc}", flush=True)
        sys.exit(1)

    print(f"=== Spectral Noise Shaping v{VERSION} ===", flush=True)
    print(f"Folder: {args.input_folder}", flush=True)

    stats = {
        "sample_rate": args.sr, "duration": args.duration,
        "n_fft": args.n_fft, "hop_length": args.hop_length,
        "chunk_size": chunk_size,
        "variation": args.variation,
        "seed": args.seed if args.seed is not None else "random",
    }

    try:
        t0 = time.time()

        waveforms = load_corpus(args.input_folder, args.sr, 0.2, stats)
        if not waveforms:
            stats["error"] = "No usable audio files"
            write_stats(args.stats_txt, stats)
            sys.exit(1)

        profile_bank, mean_envelope, n_freq = analyse_corpus(
            waveforms, args.sr, args.n_fft, args.hop_length, chunk_size
        )
        stats["profile_bank_size"] = len(profile_bank)

        # Generate LEFT channel
        print("[3a/5] Generating LEFT channel...", flush=True)
        seed_L = args.seed                              # user seed (or None)
        seed_R = (args.seed + 1) if args.seed is not None else None  # always different
        audio_L = generate(
            profile_bank, mean_envelope, n_freq,
            args.sr, args.n_fft, args.hop_length,
            args.duration, seed_L, args.variation, chunk_size
        )

        # Generate RIGHT channel — different seed guarantees different phase
        print("[3b/5] Generating RIGHT channel...", flush=True)
        audio_R = generate(
            profile_bank, mean_envelope, n_freq,
            args.sr, args.n_fft, args.hop_length,
            args.duration, seed_R, args.variation, chunk_size
        )

        # Interleave into stereo array (n_samples, 2)
        audio = np.stack([audio_L, audio_R], axis=1)

        print("[4/5] Writing output...", flush=True)
        sf.write(args.output_wav, audio, args.sr)

        elapsed = time.time() - t0
        stats["channels"] = 2
        stats["seed_L"] = seed_L if seed_L is not None else "random"
        stats["seed_R"] = seed_R if seed_R is not None else "random"
        stats["output_duration"] = round(audio.shape[0] / args.sr, 3)
        stats["output_peak"] = round(float(np.max(np.abs(audio))), 4)
        stats["total_time_s"] = round(elapsed, 2)

        print(f"[5/5] Done in {elapsed:.1f}s", flush=True)
        write_stats(args.stats_txt, stats)

    except Exception:
        msg = traceback.format_exc()
        print(f"ERROR:\n{msg}", flush=True)
        stats["error"] = msg
        write_stats(args.stats_txt, stats)
        sys.exit(1)


if __name__ == "__main__":
    main()
