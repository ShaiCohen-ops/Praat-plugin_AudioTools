"""
void_mosaic_engine.py — Latent Void Mosaic Engine v1.1
Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University
Version: 1.3 (2026) - Stereo output (pan+decorrelate); vectorized feature extraction (~47x)
License: MIT
"""

import argparse
import csv
import glob
import math
import os
import sys
import time
import warnings
import numpy as np
from scipy import spatial
import soundfile as sf
import librosa

warnings.filterwarnings('ignore')

def parse_args():
    parser = argparse.ArgumentParser(description="Latent Void Mosaic Engine")
    parser.add_argument("--corpus", required=True)
    parser.add_argument("--target_dur", type=float, default=10.0, help="Target output length in seconds")
    parser.add_argument("--grain_dur", type=float, default=250.0)
    parser.add_argument("--overlap", type=float, default=50.0)
    parser.add_argument("--jitter", type=float, default=0.0, help="Grain length jitter percentage")
    parser.add_argument("--max_shift", type=float, default=24.0, help="Max semitones to stretch")
    parser.add_argument("--rest_prob", type=float, default=0.0, help="Probability (0..1) of a silent rest grain")
    parser.add_argument("--min_pitch", type=float, default=50.0, help="Minimum target F0 Hz (octave-folded)")
    parser.add_argument("--max_pitch", type=float, default=2000.0, help="Maximum target F0 Hz (octave-folded)")
    parser.add_argument("--void_spacing", type=float, default=2.0, help="Min z-space distance between selected voids")
    parser.add_argument("--reuse_penalty", type=float, default=1.0, help="0=allow repeats, 1=strongly diversify source grains")
    parser.add_argument("--stereo", type=int, default=0, help="0=mono, 1=stereo (pan + decorrelate)")
    parser.add_argument("--pan_mode", type=int, default=1, help="1=random per grain, 2=centroid->L/R, 3=alternate L/R")
    parser.add_argument("--stereo_width", type=float, default=0.8, help="0=center, 1=full width")
    parser.add_argument("--out_wav", required=True)
    parser.add_argument("--out_csv", required=True)
    parser.add_argument("--out_stats", required=True)
    parser.add_argument("--out_map", default="")
    return parser.parse_args()

def extract_6d_features(y, sr):
    rms = np.mean(librosa.feature.rms(y=y))
    centroid = np.mean(librosa.feature.spectral_centroid(y=y, sr=sr))
    flatness = np.mean(librosa.feature.spectral_flatness(y=y))
    rolloff = np.mean(librosa.feature.spectral_rolloff(y=y, sr=sr))
    zcr = np.mean(librosa.feature.zero_crossing_rate(y=y))
    
    try:
        f0_arr = librosa.yin(y, fmin=50, fmax=2000, sr=sr)
        f0 = np.nanmean(f0_arr) if not np.all(np.isnan(f0_arr)) else 0.0
    except Exception:
        f0 = 0.0
        
    return np.array([rms, centroid, flatness, rolloff, zcr, f0], dtype=np.float32)

def extract_features_grids(y, sr, n_fft=2048, hop=512):
    """Compute all 6 features for an entire file in vectorized form.

    Returns per-STFT-frame arrays (rms, centroid, flatness, rolloff, zcr, f0)
    plus the STFT hop length, so each grain can be aggregated from the frames
    that cover it. This computes ONE STFT per file (shared by the spectral
    features) and runs yin once per file, instead of 6 separate transforms
    per grain -- ~40-50x faster on a real corpus, with musically equivalent
    (not bit-identical) feature values.
    """
    S = np.abs(librosa.stft(y, n_fft=n_fft, hop_length=hop))
    centroid = librosa.feature.spectral_centroid(S=S, sr=sr)[0]
    flatness = librosa.feature.spectral_flatness(S=S)[0]
    rolloff = librosa.feature.spectral_rolloff(S=S, sr=sr)[0]
    rms = librosa.feature.rms(S=S)[0]
    zcr = librosa.feature.zero_crossing_rate(
        y, frame_length=n_fft, hop_length=hop)[0]
    try:
        f0 = librosa.yin(y, fmin=50, fmax=2000, sr=sr, hop_length=hop)
        f0 = np.nan_to_num(f0, nan=0.0)
    except Exception:
        f0 = np.zeros(S.shape[1], dtype=np.float32)
    return rms, centroid, flatness, rolloff, zcr, f0, hop

def mutate_grain(y_grain, sr, source_f0, target_f0, source_rms, target_rms, max_shift,
                 min_pitch, max_pitch):
    y_mut = y_grain.copy()
    shift_st = 0.0

    # Fold the target F0 into the chosen register (octave folding), so the
    # mosaic respects the selected vocal range instead of shifting to
    # wherever the void's raw coordinate fell.
    if target_f0 > 20:
        while target_f0 < min_pitch:
            target_f0 *= 2.0
        while target_f0 > max_pitch:
            target_f0 /= 2.0
        target_f0 = float(np.clip(target_f0, min_pitch, max_pitch))

    # 1. Pitch Mutation
    if source_f0 > 20 and target_f0 > 20:
        shift_st = 12.0 * np.log2(target_f0 / source_f0)
        shift_st = np.clip(shift_st, -max_shift, max_shift)
        if abs(shift_st) > 0.1:
            y_mut = librosa.effects.pitch_shift(y_mut, sr=sr, n_steps=shift_st)
            
    # 2. RMS Mutation
    current_rms = np.sqrt(np.mean(y_mut**2))
    if current_rms > 1e-6:
        target_rms = max(target_rms, 0.01)
        scaler = target_rms / current_rms
        scaler = np.clip(scaler, 0.1, 5.0) 
        y_mut = y_mut * scaler
        
    return y_mut, shift_st

def main():
    start_time = time.time()
    args = parse_args()
    
    target_sr = 22050
    grain_samples = int((args.grain_dur / 1000.0) * target_sr)
    hop_samples = int(grain_samples * (1.0 - (args.overlap / 100.0)))
    hop_samples = max(1, hop_samples)
    
    # ── Calculate Required Voids for Target Duration ──
    target_samples = int(args.target_dur * target_sr)
    num_voids = max(1, int(target_samples / hop_samples))
    
    # ── 1. Corpus Extraction ──
    audio_files = []
    exts = ("*.wav", "*.WAV", "*.flac", "*.FLAC", "*.aif", "*.aiff", "*.AIF")
    for ext in exts:
        audio_files.extend(glob.glob(os.path.join(args.corpus, '**', ext), recursive=True))
        
    if not audio_files:
        with open(args.out_stats, 'w') as f:
            f.write("Status: Failed\nNo target audio files identified.")
        sys.exit(0)
        
    corpus_vectors = []
    corpus_metadata = []
    corpus_audio_data = []
    
    stft_hop = 512
    for f_path in audio_files:
        try:
            y, sr = librosa.load(f_path, sr=target_sr, mono=True)
            if len(y) < grain_samples:
                continue
            
            corpus_audio_data.append(y)
            file_idx = len(corpus_audio_data) - 1
            
            # Vectorized: compute all feature grids for the whole file once.
            rms_f, cen_f, fl_f, ro_f, zc_f, f0_f, stft_hop = \
                extract_features_grids(y, target_sr, hop=stft_hop)
            n_frames = len(cen_f)
            
            num_grains = (len(y) - grain_samples) // hop_samples
            for i in range(num_grains):
                start = i * hop_samples
                # STFT frames covering this grain
                fs = start // stft_hop
                fe = max(fs + 1, (start + grain_samples) // stft_hop)
                fe = min(fe, n_frames)
                if fs >= n_frames:
                    fs = n_frames - 1
                f0_slice = f0_f[fs:fe]
                f0_pos = f0_slice[f0_slice > 0]
                f0_val = float(np.mean(f0_pos)) if f0_pos.size else 0.0
                vec = np.array([
                    float(np.mean(rms_f[fs:fe])),
                    float(np.mean(cen_f[fs:fe])),
                    float(np.mean(fl_f[fs:fe])),
                    float(np.mean(ro_f[fs:fe])),
                    float(np.mean(zc_f[fs:fe])),
                    f0_val
                ], dtype=np.float32)
                corpus_vectors.append(vec)
                corpus_metadata.append({
                    'file_idx': file_idx,
                    'file_path': os.path.basename(f_path),
                    'start_sample': start
                })
        except Exception:
            continue
            
    if not corpus_vectors:
        with open(args.out_stats, 'w') as f:
            f.write("Status: Failed\nCould not extract spatial features.")
        sys.exit(0)
        
    corpus_matrix = np.array(corpus_vectors)
    means = np.mean(corpus_matrix, axis=0)
    stds = np.std(corpus_matrix, axis=0)
    stds[stds == 0] = 1.0 
    
    corpus_z = (corpus_matrix - means) / stds
    
    # ── 2. Void Mapping ──
    min_bounds = np.min(corpus_z, axis=0) - 1.0
    max_bounds = np.max(corpus_z, axis=0) + 1.0
    
    num_probes = 40000
    probes_z = np.random.uniform(min_bounds, max_bounds, size=(num_probes, 6))
    
    distances = spatial.distance.cdist(probes_z, corpus_z, metric='euclidean')
    min_distances = np.min(distances, axis=1)
    sorted_probe_indices = np.argsort(min_distances)[::-1]
    
    selected_voids_z = []
    min_dist_between_voids = args.void_spacing
    
    for candidate_idx in sorted_probe_indices:
        candidate = probes_z[candidate_idx]
        if len(selected_voids_z) == 0:
            selected_voids_z.append(candidate)
        else:
            dist_to_selected = np.min(spatial.distance.cdist([candidate], selected_voids_z))
            if dist_to_selected > min_dist_between_voids:
                selected_voids_z.append(candidate)
        if len(selected_voids_z) >= num_voids:
            break
            
    while len(selected_voids_z) < num_voids:
        # Fallback if we need massive amounts of voids for a very long target duration
        selected_voids_z.append(probes_z[np.random.choice(sorted_probe_indices[:1000])])
        
    selected_voids_z = np.array(selected_voids_z)
    selected_voids_physical = (selected_voids_z * stds) + means

    # Map Export
    if args.out_map:
        try:
            with open(args.out_map, 'w', newline='', encoding='utf-8') as mf:
                w = csv.writer(mf)
                w.writerow(["type", "centroid", "rolloff"])
                # Log a subset of corpus to avoid massive UI hang in Praat
                subset_corpus = corpus_matrix[:2000]
                for row in subset_corpus:
                    w.writerow(["C", round(float(row[1]), 3), round(float(row[3]), 3)])
                for row in selected_voids_physical:
                    w.writerow(["V", round(float(row[1]), 3), round(float(row[3]), 3)])
        except Exception:
            pass

    # ── 3. Mutation and Synthesis ──
    # Per-grain lengths/hops (jitter varies each grain's length).
    base_samples = grain_samples
    grain_lengths = []
    hop_lengths = []
    for i in range(num_voids):
        if args.jitter > 0:
            jf = np.random.uniform(1.0 - args.jitter / 100.0, 1.0 + args.jitter / 100.0)
            g_len = int(base_samples * jf)
        else:
            g_len = base_samples
        g_len = max(64, g_len)
        h_len = max(1, int(g_len * (1.0 - args.overlap / 100.0)))
        grain_lengths.append(g_len)
        hop_lengths.append(h_len)

    total_audio_samples = sum(hop_lengths) + max(grain_lengths) + target_sr

    stereo = (args.stereo == 1)
    # Decorrelation offset (samples) for stereo width - a few ms Haas-style.
    max_offset = int(0.004 * target_sr) if stereo else 0  # ~4 ms
    pad = max_offset + 2
    total_audio_samples += pad

    if stereo:
        out_L = np.zeros(total_audio_samples, dtype=np.float32)
        out_R = np.zeros(total_audio_samples, dtype=np.float32)
        wsum_L = np.zeros(total_audio_samples, dtype=np.float32)
        wsum_R = np.zeros(total_audio_samples, dtype=np.float32)
    else:
        out_audio = np.zeros(total_audio_samples, dtype=np.float32)
        window_sum = np.zeros(total_audio_samples, dtype=np.float32)

    grain_records = []
    rests_generated = 0

    # Reuse penalty: corpus grains used recently are temporarily pushed away
    # in the nearest-grain search so the mosaic spreads across more of the
    # corpus instead of leaning on a handful of boundary grains. The penalty
    # is added (in z-distance^2 units) and decays over a short window.
    recent_window = 6
    recent_used = []
    median_corpus_d2 = float(np.median(np.sum((corpus_z - corpus_z.mean(axis=0))**2, axis=1))) + 1e-9

    # centroid range (for pan_mode 2: spectral centroid -> stereo position)
    centroid_min = float(np.min(corpus_matrix[:, 1]))
    centroid_max = float(np.max(corpus_matrix[:, 1]))

    current_sample = 0
    for i in range(num_voids):
        void_z = selected_voids_z[i]
        void_phys = selected_voids_physical[i]
        g_len = grain_lengths[i]
        h_len = hop_lengths[i]
        window = np.hanning(g_len).astype(np.float32)

        # ── Rest gate ──
        if np.random.uniform(0.0, 1.0) < args.rest_prob:
            rests_generated += 1
            grain_records.append([
                f"Rest_{i}", "(silence)",
                round(current_sample / target_sr, 3),
                0.0, 0.0, 0.0
            ])
            current_sample += h_len
            continue

        # nearest corpus grain, with a recency penalty to diversify
        dists = np.sum((corpus_z - void_z) ** 2, axis=1)
        if args.reuse_penalty > 0 and recent_used:
            for age, idx in enumerate(reversed(recent_used)):
                # most-recent gets the biggest push; decays with age
                decay = (recent_window - age) / recent_window
                dists[idx] += args.reuse_penalty * median_corpus_d2 * 2.0 * decay
        best_idx = int(np.argmin(dists))
        recent_used.append(best_idx)
        recent_used = recent_used[-recent_window:]

        meta = corpus_metadata[best_idx]
        c_phys = corpus_matrix[best_idx]

        y_full = corpus_audio_data[meta['file_idx']]
        start_samp = meta['start_sample']
        y_grain = y_full[start_samp:start_samp + g_len]

        if len(y_grain) < g_len:
            y_grain = np.pad(y_grain, (0, g_len - len(y_grain)))

        y_mutated, shift_applied = mutate_grain(
            y_grain, target_sr,
            source_f0=c_phys[5], target_f0=void_phys[5],
            source_rms=c_phys[0], target_rms=void_phys[0],
            max_shift=args.max_shift,
            min_pitch=args.min_pitch, max_pitch=args.max_pitch
        )

        # pitch_shift can change length slightly; refit to g_len
        if len(y_mutated) < g_len:
            y_mutated = np.pad(y_mutated, (0, g_len - len(y_mutated)))
        elif len(y_mutated) > g_len:
            y_mutated = y_mutated[:g_len]

        windowed = y_mutated * window

        if stereo:
            # ── pan position in [-1, 1] ──
            if args.pan_mode == 2:
                # centroid -> L/R (spectral space becomes spatial)
                c_lo, c_hi = centroid_min, centroid_max
                cval = float(np.clip(void_phys[1], c_lo, c_hi))
                pos = 2.0 * (cval - c_lo) / (c_hi - c_lo + 1e-9) - 1.0
            elif args.pan_mode == 3:
                pos = -1.0 if (i % 2 == 0) else 1.0
            else:
                pos = np.random.uniform(-1.0, 1.0)
            pos *= args.stereo_width
            # constant-power pan
            angle = (pos + 1.0) * 0.25 * np.pi  # 0..pi/2
            gL = float(np.cos(angle))
            gR = float(np.sin(angle))
            # decorrelation: shift the quieter-side channel a few samples so
            # the image has width, not just balance. Offset scales with |pos|.
            off = int(round(abs(pos) * max_offset))
            sL = current_sample + (off if pos > 0 else 0)
            sR = current_sample + (off if pos < 0 else 0)
            out_L[sL:sL + g_len] += windowed * gL
            out_R[sR:sR + g_len] += windowed * gR
            wsum_L[sL:sL + g_len] += window * gL
            wsum_R[sR:sR + g_len] += window * gR
        else:
            out_audio[current_sample:current_sample + g_len] += windowed
            window_sum[current_sample:current_sample + g_len] += window

        grain_records.append([
            f"Void_{i}",
            meta['file_path'],
            round(start_samp / target_sr, 3),
            round(shift_applied, 2),
            round(void_phys[5], 2),
            round(c_phys[5], 2)
        ])

        current_sample += h_len

    final_active_sample = current_sample - hop_lengths[-1] + grain_lengths[-1] + pad
    window_sum_floor = 1e-3

    if stereo:
        out_L = out_L[:final_active_sample]
        out_R = out_R[:final_active_sample]
        wsum_L = wsum_L[:final_active_sample]
        wsum_R = wsum_R[:final_active_sample]
        out_L = out_L * np.minimum(1.0 / np.maximum(wsum_L, window_sum_floor), 4.0)
        out_R = out_R * np.minimum(1.0 / np.maximum(wsum_R, window_sum_floor), 4.0)
        # joint peak normalize (preserve the L/R balance / image)
        peak = float(max(np.abs(out_L).max(), np.abs(out_R).max()))
        if peak > 0.001:
            scale = 0.95 / peak
            out_L *= scale
            out_R *= scale
        fade_samples = min(int(0.015 * target_sr), len(out_L) // 2)
        if fade_samples > 1:
            fin = np.linspace(0.0, 1.0, fade_samples, dtype=np.float32)
            fout = np.linspace(1.0, 0.0, fade_samples, dtype=np.float32)
            out_L[:fade_samples] *= fin
            out_R[:fade_samples] *= fin
            out_L[-fade_samples:] *= fout
            out_R[-fade_samples:] *= fout
        out_audio = np.stack([out_L, out_R], axis=1)  # (n, 2) for soundfile
    else:
        out_audio = out_audio[:final_active_sample]
        window_sum = window_sum[:final_active_sample]
        gain = np.minimum(1.0 / np.maximum(window_sum, window_sum_floor), 4.0)
        out_audio = out_audio * gain
        peak = float(np.abs(out_audio).max())
        if peak > 0.001:
            out_audio = (out_audio / peak * 0.95).astype(np.float32)
        fade_samples = min(int(0.015 * target_sr), len(out_audio) // 2)
        if fade_samples > 1:
            out_audio[:fade_samples] *= np.linspace(0.0, 1.0, fade_samples, dtype=np.float32)
            out_audio[-fade_samples:] *= np.linspace(1.0, 0.0, fade_samples, dtype=np.float32)
        
    sf.write(args.out_wav, out_audio, target_sr)
    
    with open(args.out_csv, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(["void_id", "corpus_victim", "source_time_sec", "mutation_shift_st", "target_hz", "source_hz"])
        writer.writerows(grain_records)
        
    total_time = round(time.time() - start_time, 3)
    audio_length = round(len(out_audio) / target_sr, 2)
    
    with open(args.out_stats, 'w', encoding='utf-8') as f:
        f.write(f"Status: Success\n")
        f.write(f"Total computation time: {total_time}\n")
        f.write(f"Target duration: {args.target_dur}\n")
        f.write(f"Total audio length: {audio_length}\n")
        f.write(f"Corpus files analyzed: {len(audio_files)}\n")
        f.write(f"Acoustic grains mutated: {num_voids - rests_generated}\n")
        f.write(f"Rests injected: {rests_generated}\n")
        f.write(f"Distinct source grains: {len(set(r[1] for r in grain_records if r[1] != '(silence)'))}\n")

if __name__ == '__main__':
    main()