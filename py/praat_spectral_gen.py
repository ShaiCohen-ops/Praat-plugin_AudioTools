#!/usr/bin/env python3
# ============================================================
# Praat AudioTools - praat_spectral_gen.py
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.3 (2026)
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
#     5. Separate level-independent spectral shape from RMS dynamics
#     6. Shape independent stereo noise phases with a shared spectral trajectory
#     7. Inverse STFT / overlap-add and apply learned temporal envelope
#     8. Normalize globally and save FLOAT WAV
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
    from scipy.signal import resample_poly
    HAS_SCIPY = True
except ImportError:
    HAS_SCIPY = False


VERSION = "1.3"


def validated_chunk_size(chunk_size, hop_length):
    """
    Ensure chunk_size is a power of 2 and at least 2× hop_length.
    Raises ValueError with a clear message if not.
    """
    if hop_length < 1:
        raise ValueError("hop_length must be at least 1")
    if chunk_size < 1:
        raise ValueError("chunk_size must be positive")
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
    """Load corpus files and choose a cancellation-safe representative channel.

    Per-file peak normalisation is intentional: this generator learns timbral
    shape and normalized temporal morphology, not recording gain.
    """
    from math import gcd

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
    multichannel_files = 0
    total_duration_s = 0.0

    for path in paths:
        try:
            audio, file_sr = sf.read(path, always_2d=True, dtype="float32")
            audio = np.asarray(audio, dtype=np.float32)
            if audio.shape[1] > 1:
                multichannel_files += 1
                rms = np.sqrt(np.mean(audio.astype(np.float64) ** 2, axis=0))
                best_ch = int(np.argmax(rms))
                audio = audio[:, best_ch]
            else:
                audio = audio[:, 0]

            if len(audio) / file_sr < min_dur:
                skipped.append((os.path.basename(path), "too short"))
                continue

            if file_sr != sr and HAS_SCIPY:
                g = gcd(int(sr), int(file_sr))
                up, down = int(sr) // g, int(file_sr) // g
                audio = resample_poly(audio, up, down).astype(np.float32)
            elif file_sr != sr:
                ratio = sr / file_sr
                new_len = max(1, int(round(len(audio) * ratio)))
                indices = np.linspace(0, len(audio) - 1, new_len)
                audio = np.interp(indices, np.arange(len(audio)), audio).astype(np.float32)

            peak = float(np.max(np.abs(audio))) if len(audio) else 0.0
            if peak > 1e-6:
                audio = audio / peak * 0.95

            waveforms.append(audio.astype(np.float32))
            total_duration_s += len(audio) / float(sr)
        except Exception as exc:
            skipped.append((os.path.basename(path), str(exc)))

    stats["files_used"] = len(waveforms)
    stats["files_skipped"] = len(skipped)
    stats["multichannel_files"] = multichannel_files
    stats["corpus_duration_used_s"] = round(total_duration_s, 3)
    stats["skipped_details"] = skipped
    print(f"  Loaded: {len(waveforms)}  Skipped: {len(skipped)}", flush=True)
    if multichannel_files:
        print(f"  Multichannel files: {multichannel_files} (strongest-RMS channel analysed)", flush=True)
    return waveforms


# =============================================================================
#  STAGE 2 — ANALYSE CORPUS SPECTRA
# =============================================================================

def analyse_corpus(waveforms, sr, n_fft, hop, chunk_size):
    """Build level-independent spectral shapes + a separate RMS envelope.

    chunk_size controls the analysis window / temporal grain. n_fft controls
    the canonical spectral grid. When they differ, magnitudes are interpolated
    by *frequency in Hz*, never copied by bin index.

    Spectral profiles are RMS-normalised active frames. Temporal amplitude is
    learned separately from all frame RMS values, so dynamics are not encoded
    twice (once in profile magnitude and again in the learned envelope).
    """
    print("[2/5] Analysing corpus spectra...", flush=True)
    print(f"  chunk_size={chunk_size}  ({chunk_size/sr*1000:.1f} ms)  n_fft={n_fft}", flush=True)

    n_freq = n_fft // 2 + 1
    canonical_freq = np.fft.rfftfreq(n_fft, d=1.0 / sr)
    analysis_fft = max(int(n_fft), int(chunk_size))
    analysis_freq = np.fft.rfftfreq(analysis_fft, d=1.0 / sr)
    window = np.hanning(chunk_size).astype(np.float32)

    profile_bank = []
    envelopes = []
    silent_profiles_skipped = 0

    for audio in waveforms:
        if len(audio) <= chunk_size:
            n_frames = 1
        else:
            n_frames = int(math.ceil((len(audio) - chunk_size) / float(hop))) + 1

        file_rms = []
        file_profiles = []
        for i in range(n_frames):
            start = i * hop
            frame = audio[start:start + chunk_size]
            if len(frame) < chunk_size:
                frame = np.pad(frame, (0, chunk_size - len(frame)))

            rms = float(np.sqrt(np.mean(frame.astype(np.float64) ** 2)))
            file_rms.append(rms)

            windowed = frame * window
            mag_hi = np.abs(np.fft.rfft(windowed, n=analysis_fft)).astype(np.float64)
            if analysis_fft == n_fft:
                mag = mag_hi
            else:
                mag = np.interp(canonical_freq, analysis_freq, mag_hi)
            file_profiles.append(mag)

        if file_rms:
            file_rms_arr = np.asarray(file_rms, dtype=np.float32)
            envelopes.append(file_rms_arr)
            peak_rms = float(np.max(file_rms_arr))
            active_floor = max(1e-8, peak_rms * 1e-3)  # -60 dB relative to file peak RMS
            for rms, mag in zip(file_rms_arr, file_profiles):
                if float(rms) <= active_floor:
                    silent_profiles_skipped += 1
                    continue
                # Unit RMS in the magnitude domain = spectral shape only.
                mag_rms = float(np.sqrt(np.mean(mag ** 2)))
                if mag_rms > 1e-12:
                    profile_bank.append((mag / mag_rms).astype(np.float32))
                else:
                    silent_profiles_skipped += 1

    profile_bank = np.asarray(profile_bank, dtype=np.float32)
    if profile_bank.size == 0:
        raise ValueError("Corpus analysis produced no active spectral frames")
    mean_profile = np.mean(profile_bank.astype(np.float64), axis=0).astype(np.float32)

    env_len = 200
    env_sum = np.zeros(env_len, dtype=np.float64)
    for env in envelopes:
        resampled = np.interp(
            np.linspace(0, 1, env_len),
            np.linspace(0, 1, len(env)), env
        )
        # Per-file envelope shape, so one loud recording does not dominate.
        ep = float(np.max(resampled))
        if ep > 1e-12:
            resampled = resampled / ep
        env_sum += resampled
    mean_envelope = (env_sum / max(1, len(envelopes))).astype(np.float32)
    env_peak = float(np.max(mean_envelope)) if len(mean_envelope) else 0.0
    if env_peak > 1e-8:
        mean_envelope = mean_envelope / env_peak

    print(f"  Profile bank: {len(profile_bank)} active frames  ({n_freq} canonical bins)", flush=True)
    print(f"  Silent/near-silent profiles skipped: {silent_profiles_skipped}", flush=True)
    print(f"  Analysis FFT: {analysis_fft} samples; canonical FFT grid: {n_fft}", flush=True)
    print(f"  Mean envelope: {env_len} points", flush=True)
    return profile_bank, mean_profile, mean_envelope, canonical_freq, silent_profiles_skipped


# =============================================================================
#  STAGE 3 — GENERATE
# =============================================================================

def _profile_for_frame(profile_bank, mean_profile, std_profile, variation, rng):
    """Variation law: 0 -> corpus mean, 1 -> full corpus-frame variation."""
    v = float(np.clip(variation, 0.0, 1.0))
    if v <= 0.0 or len(profile_bank) == 0:
        return mean_profile

    idx1 = int(rng.integers(0, len(profile_bank)))
    candidate = profile_bank[idx1].astype(np.float32)
    if len(profile_bank) > 1:
        idx2 = int(rng.integers(0, len(profile_bank)))
        blend = float(rng.uniform(0.0, 1.0))
        candidate = candidate * (1.0 - blend) + profile_bank[idx2] * blend

    profile = mean_profile * (1.0 - v) + candidate * v
    jitter = std_profile * rng.normal(size=len(mean_profile)).astype(np.float32) * v * 0.30
    return np.maximum(0.0, profile + jitter).astype(np.float32)


def generate_stereo(profile_bank, mean_profile, mean_envelope, canonical_freq,
                    sr, n_fft, hop, duration, seed, variation, chunk_size):
    """Generate coherent stereo shaped noise.

    Both channels share the same corpus-magnitude trajectory per frame, while
    using independent noise phases.  This keeps the learned timbral motion
    coherent and produces width without unrelated left/right profile flicker.
    """
    print("[3/5] Generating stereo from noise...", flush=True)
    print(f"  chunk_size={chunk_size}  ({chunk_size/sr*1000:.1f} ms)  variation={variation:.2f}", flush=True)

    base_seed = None if seed is None else int(seed)
    rng_profile = np.random.default_rng(base_seed)
    rng_l = np.random.default_rng(None if base_seed is None else base_seed + 1009)
    rng_r = np.random.default_rng(None if base_seed is None else base_seed + 2017)

    n_samples = max(1, int(round(duration * sr)))
    window = np.hanning(chunk_size).astype(np.float64)
    std_profile = np.std(profile_bank.astype(np.float64), axis=0).astype(np.float32)
    synth_freq = np.fft.rfftfreq(chunk_size, d=1.0 / sr)

    pad = chunk_size
    total_samples = n_samples + 2 * pad
    n_out_frames = max(1, (total_samples - chunk_size) // hop + 1)
    noise_l = rng_l.standard_normal(total_samples + chunk_size).astype(np.float32)
    noise_r = rng_r.standard_normal(total_samples + chunk_size).astype(np.float32)

    output = np.zeros((total_samples + chunk_size, 2), dtype=np.float64)
    win_sum = np.zeros(total_samples + chunk_size, dtype=np.float64)

    for i in range(n_out_frames):
        start = i * hop
        profile = _profile_for_frame(profile_bank, mean_profile, std_profile,
                                     variation, rng_profile)
        # Hz-aware mapping from canonical n_fft grid to synthesis chunk bins.
        profile_synth = np.interp(synth_freq, canonical_freq, profile).astype(np.float64)

        for ch, noise in enumerate((noise_l, noise_r)):
            noise_frame = noise[start:start + chunk_size] * window
            noise_phase = np.angle(np.fft.rfft(noise_frame, n=chunk_size))
            shaped_spec = profile_synth * np.exp(1j * noise_phase)
            shaped_frame = np.fft.irfft(shaped_spec, n=chunk_size)
            output[start:start + chunk_size, ch] += shaped_frame * window
        win_sum[start:start + chunk_size] += window ** 2

    threshold = 0.075
    safe = win_sum > threshold
    output[safe, :] /= win_sum[safe, None]
    output[~safe, :] = 0.0
    output = output[pad:pad + n_samples, :].astype(np.float32)

    env_time = np.linspace(0, 1, n_samples)
    env_curve = np.interp(env_time, np.linspace(0, 1, len(mean_envelope)),
                          mean_envelope).astype(np.float32)
    smooth_n = max(1, int(0.02 * sr))
    if smooth_n > 1 and n_samples > 2:
        # O(N) centred moving average with edge padding.
        left = smooth_n // 2
        right = smooth_n - 1 - left
        padded = np.pad(env_curve.astype(np.float64), (left, right), mode="edge")
        cs = np.concatenate(([0.0], np.cumsum(padded)))
        env_curve = ((cs[smooth_n:] - cs[:-smooth_n]) / smooth_n).astype(np.float32)
    output *= env_curve[:, None]

    fade_samples = min(int(0.010 * sr), n_samples // 4)
    if fade_samples > 0:
        fade_in = np.linspace(0.0, 1.0, fade_samples, dtype=np.float32)
        fade_out = np.linspace(1.0, 0.0, fade_samples, dtype=np.float32)
        output[:fade_samples, :] *= fade_in[:, None]
        output[-fade_samples:, :] *= fade_out[:, None]

    # Generator-level target: one global scalar keeps stereo balance intact.
    peak = float(np.max(np.abs(output))) if output.size else 0.0
    if peak > 1e-6:
        output *= np.float32(0.90 / peak)

    print(f"  Generated: {n_samples} samples ({duration:.2f}s)  peak={np.max(np.abs(output)):.4f}", flush=True)
    return output


def _mean_mag_profile(audio, sr, canonical_freq, frame_size=2048, hop=512):
    """Mean magnitude on canonical_freq for QC/visualisation."""
    if audio.ndim > 1:
        rms = np.sqrt(np.mean(audio.astype(np.float64) ** 2, axis=0))
        audio = audio[:, int(np.argmax(rms))]
    audio = np.asarray(audio, dtype=np.float32)
    frame_size = min(frame_size, max(64, len(audio)))
    if frame_size < 2:
        return np.zeros_like(canonical_freq, dtype=np.float32)
    window = np.hanning(frame_size)
    mags = []
    nframes = max(1, int(math.ceil(max(0, len(audio)-frame_size) / float(hop))) + 1)
    fsrc = np.fft.rfftfreq(frame_size, d=1.0/sr)
    for i in range(nframes):
        fr = audio[i*hop:i*hop+frame_size]
        if len(fr) < frame_size:
            fr = np.pad(fr, (0, frame_size-len(fr)))
        mag = np.abs(np.fft.rfft(fr*window))
        mags.append(np.interp(canonical_freq, fsrc, mag))
    return np.mean(np.asarray(mags), axis=0).astype(np.float32)


def _rms_envelope(audio, n_points=200):
    if audio.ndim > 1:
        audio = audio[:, 0]
    audio = np.asarray(audio, dtype=np.float64)
    if len(audio) == 0:
        return np.zeros(n_points, dtype=np.float32)
    edges = np.linspace(0, len(audio), n_points + 1).astype(int)
    vals = np.zeros(n_points, dtype=np.float64)
    for i in range(n_points):
        seg = audio[edges[i]:edges[i+1]]
        if len(seg):
            vals[i] = np.sqrt(np.mean(seg**2))
    pk = vals.max() if len(vals) else 0.0
    if pk > 1e-12:
        vals /= pk
    return vals.astype(np.float32)


def write_analysis_csv(profile_path, envelope_path, canonical_freq, mean_profile,
                       mean_envelope, output, sr):
    out_profile = _mean_mag_profile(output, sr, canonical_freq,
                                    frame_size=min(2048, max(64, len(output))), hop=512)
    cp = mean_profile.astype(np.float64)
    op = out_profile.astype(np.float64)
    cp /= max(float(cp.max()), 1e-12)
    op /= max(float(op.max()), 1e-12)
    with open(profile_path, "w", encoding="utf-8") as f:
        f.write("frequency_hz,corpus_mean,output_mean\n")
        for hz, a, b in zip(canonical_freq, cp, op):
            f.write(f"{hz:.9g},{a:.9g},{b:.9g}\n")

    out_env = _rms_envelope(output, len(mean_envelope))
    with open(envelope_path, "w", encoding="utf-8") as f:
        f.write("time_norm,learned_envelope,output_rms\n")
        for i, (a, b) in enumerate(zip(mean_envelope, out_env)):
            x = i / max(1, len(mean_envelope)-1)
            f.write(f"{x:.9g},{float(a):.9g},{float(b):.9g}\n")

    # QC metrics
    denom = np.linalg.norm(cp) * np.linalg.norm(op)
    spectral_cos = float(np.dot(cp, op) / denom) if denom > 1e-12 else 0.0
    env_a = mean_envelope.astype(np.float64)
    env_b = out_env.astype(np.float64)
    env_corr = float(np.corrcoef(env_a, env_b)[0,1]) if np.std(env_a)>1e-9 and np.std(env_b)>1e-9 else 0.0
    return spectral_cos, env_corr


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
                    help="0 = corpus mean profile, 1 = full corpus-frame variation")
    ap.add_argument("--profile_csv", type=str, default=None)
    ap.add_argument("--envelope_csv", type=str, default=None)
    args = ap.parse_args()

    # chunk_size defaults to n_fft; validate before doing any work
    chunk_size = args.chunk_size if args.chunk_size is not None else args.n_fft
    try:
        chunk_size = validated_chunk_size(chunk_size, args.hop_length)
        if args.n_fft < 64:
            raise ValueError("n_fft must be at least 64")
        if args.sr < 8000:
            raise ValueError("sample rate must be at least 8000 Hz")
        if args.duration <= 0:
            raise ValueError("duration must be > 0")
    except ValueError as exc:
        print(f"ERROR: {exc}", flush=True)
        sys.exit(1)

    args.variation = float(np.clip(args.variation, 0.0, 1.0))

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

        profile_bank, mean_profile, mean_envelope, canonical_freq, silent_profiles_skipped = analyse_corpus(
            waveforms, args.sr, args.n_fft, args.hop_length, chunk_size
        )
        stats["profile_bank_size"] = len(profile_bank)
        stats["silent_profiles_skipped"] = silent_profiles_skipped
        stats["analysis_fft_size"] = max(args.n_fft, chunk_size)

        audio = generate_stereo(
            profile_bank, mean_profile, mean_envelope, canonical_freq,
            args.sr, args.n_fft, args.hop_length,
            args.duration, args.seed, args.variation, chunk_size
        )

        print("[4/5] Writing output...", flush=True)
        sf.write(args.output_wav, audio, args.sr, subtype="FLOAT")

        elapsed = time.time() - t0
        stats["channels"] = 2
        stats["stereo_profile_trajectory"] = "shared"
        stats["stereo_noise_phase"] = "independent"
        stats["output_duration"] = round(audio.shape[0] / args.sr, 3)
        stats["output_peak"] = round(float(np.max(np.abs(audio))), 4)
        if args.profile_csv and args.envelope_csv:
            spectral_cos, env_corr = write_analysis_csv(
                args.profile_csv, args.envelope_csv, canonical_freq, mean_profile,
                mean_envelope, audio, args.sr
            )
            stats["spectral_profile_cosine"] = round(spectral_cos, 6)
            stats["envelope_correlation"] = round(env_corr, 6)
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
