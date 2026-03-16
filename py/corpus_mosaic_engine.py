"""
corpus_mosaic_engine.py — Offline Corpus Mosaic Engine  v1.2 (With Silence Gate)

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University
Version: 1.2 (2026)
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

warnings.filterwarnings('ignore')

def check_dependencies():
    missing = []
    for pkg in ["numpy", "soundfile", "scipy", "librosa"]:
        try:
            __import__(pkg)
        except ImportError:
            missing.append(pkg)
    if missing:
        print("ERROR: Missing packages: " + ", ".join(missing), file=sys.stderr)
        print("Install:  pip install " + " ".join(missing), file=sys.stderr)
        sys.exit(1)

check_dependencies()

import numpy as np
import soundfile as sf
import librosa


def parse_args():
    parser = argparse.ArgumentParser(description="Corpus Mosaic Engine")
    parser.add_argument("--source", required=True)
    parser.add_argument("--corpus", required=True)
    parser.add_argument("--out_wav", required=True)
    parser.add_argument("--out_csv", required=True)
    parser.add_argument("--out_stats", required=True)
    
    parser.add_argument("--grain_ms", type=float, default=100.0)
    parser.add_argument("--overlap", type=float, default=0.5)
    
    parser.add_argument("--pitch_w", type=float, default=1.0)
    parser.add_argument("--timbre_w", type=float, default=1.0)
    parser.add_argument("--loudness_w", type=float, default=1.0)
    
    parser.add_argument("--top_k", type=int, default=5)
    parser.add_argument("--randomness", type=float, default=0.5)
    parser.add_argument("--continuity", type=float, default=0.3)
    parser.add_argument("--penalty", type=float, default=1.5)
    parser.add_argument("--normalize", action="store_true")
    
    # NEW: Gate threshold in dB relative to the peak volume of the source
    parser.add_argument("--gate_db", type=float, default=-40.0)
    
    args = parser.parse_args()
    
    # --- Robust Parameter Clamping ---
    args.grain_ms = max(10.0, args.grain_ms)
    args.overlap = float(np.clip(args.overlap, 0.0, 0.99))
    args.top_k = max(1, args.top_k)
    args.randomness = float(np.clip(args.randomness, 0.0, 1.0))
    args.continuity = max(0.0, args.continuity)
    args.penalty = max(0.0, args.penalty)
    args.gate_db = min(-10.0, args.gate_db) # Keep sensible limits
    
    return args


def extract_features(y, sr, win_length, hop_length):
    rms = librosa.feature.rms(y=y, frame_length=win_length, hop_length=hop_length)[0]
    cent = librosa.feature.spectral_centroid(y=y, sr=sr, n_fft=win_length, hop_length=hop_length)[0]
    flat = librosa.feature.spectral_flatness(y=y, n_fft=win_length, hop_length=hop_length)[0]
    roll = librosa.feature.spectral_rolloff(y=y, sr=sr, n_fft=win_length, hop_length=hop_length)[0]
    zcr = librosa.feature.zero_crossing_rate(y=y, frame_length=win_length, hop_length=hop_length)[0]
    
    f0 = librosa.yin(y, fmin=50, fmax=2000, sr=sr, frame_length=win_length, hop_length=hop_length)
    f0[np.isnan(f0)] = 0.0
    
    min_len = min(len(rms), len(cent), len(flat), len(roll), len(zcr), len(f0))
    
    features = np.vstack([
        rms[:min_len], 
        cent[:min_len], 
        flat[:min_len], 
        roll[:min_len], 
        zcr[:min_len], 
        f0[:min_len]
    ]).T
    
    return features


def robust_z_score(features, eps=1e-8):
    mean = np.mean(features, axis=0)
    std = np.std(features, axis=0)
    norm = (features - mean) / (std + eps)
    return norm, mean, std


def main():
    start_time = time.time()
    args = parse_args()
    
    if not os.path.exists(args.source):
        print(f"ERROR: Source file {args.source} not found.", file=sys.stderr)
        sys.exit(1)
        
    target_sr = 44100 
    win_length = int(target_sr * (args.grain_ms / 1000.0))
    hop_length = int(win_length * (1.0 - args.overlap))

    # ── 1. Source Processing ──────────────────────────────────────────────────
    print(f"[Py 1/5] Loading source audio & extracting features...")
    y_source, _ = librosa.load(args.source, sr=target_sr, mono=True)
    
    if len(y_source) < win_length:
        print("ERROR: Source audio is shorter than a single grain.", file=sys.stderr)
        sys.exit(1)

    source_features = extract_features(y_source, target_sr, win_length, hop_length)
    num_source_grains = len(source_features)
    print(f"    Source grains: {num_source_grains}")

    # --- NEW: Calculate Silence Gate Threshold ---
    # Feature column 0 is raw RMS. We find the peak RMS, and calculate the linear floor.
    source_rms_raw = source_features[:, 0]
    peak_rms = np.max(source_rms_raw)
    gate_thresh = max(1e-7, peak_rms * (10 ** (args.gate_db / 20.0)))

    # ── 2. Corpus Scanning ────────────────────────────────────────────────────
    print(f"[Py 2/5] Scanning corpus folder...")
    exts = ('*.wav', '*.flac', '*.aiff', '*.aif')
    corpus_files = []
    for ext in exts:
        corpus_files.extend(glob.glob(os.path.join(args.corpus, '**', ext), recursive=True))
        
    if not corpus_files:
        print(f"ERROR: No audio files found in corpus {args.corpus}", file=sys.stderr)
        sys.exit(1)

    # ── 3. Corpus Extraction ──────────────────────────────────────────────────
    print(f"[Py 3/5] Extracting corpus features ({len(corpus_files)} files)...")
    
    corpus_features_list = []
    corpus_metadata = [] 
    corpus_audio_data = []
    
    valid_files_used = 0
    for fpath in corpus_files:
        try:
            y_corp, _ = librosa.load(fpath, sr=target_sr, mono=True)
            if len(y_corp) < win_length:
                continue 
                
            feats = extract_features(y_corp, target_sr, win_length, hop_length)
            corpus_features_list.append(feats)
            corpus_audio_data.append(y_corp)
            
            file_idx = len(corpus_audio_data) - 1
            for grain_i in range(len(feats)):
                corpus_metadata.append({
                    'file_idx': file_idx,
                    'file_path': fpath,
                    'start_sample': grain_i * hop_length
                })
            valid_files_used += 1
        except Exception as e:
            pass

    if len(corpus_features_list) == 0:
        print("ERROR: Could not extract features from any corpus files.", file=sys.stderr)
        sys.exit(1)

    corpus_features = np.vstack(corpus_features_list)
    num_corpus_grains = len(corpus_features)
    print(f"    Built database: {num_corpus_grains} grains from {valid_files_used} valid files.")

    # ── 4. Normalisation & Weighting ──────────────────────────────────────────
    print("[Py 4/5] Computing feature distances and matching...")
    corpus_norm, c_mean, c_std = robust_z_score(corpus_features)
    source_norm = (source_features - c_mean) / (c_std + 1e-8)
    
    weights = np.array([
        args.loudness_w,  # RMS
        args.timbre_w,    # Centroid
        args.timbre_w,    # Flatness
        args.timbre_w,    # Rolloff
        args.timbre_w,    # ZCR
        args.pitch_w      # F0
    ], dtype=np.float32)
    weights = weights / (np.sum(weights) + 1e-9)
    
    out_length = (num_source_grains - 1) * hop_length + win_length
    out_audio = np.zeros(out_length, dtype=np.float32)
    window = np.hanning(win_length).astype(np.float32)
    
    matches_record = []
    recent_choices = []
    penalty_memory = max(1, int(target_sr / hop_length * 2)) 
    prev_corpus_idx = -1
    
    max_dist_estimate = float(np.max(np.var(corpus_norm, axis=0)) * 10)
    
    silent_grains_count = 0

    for i in range(num_source_grains):
        
        # --- NEW: Silence Gate Check ---
        if source_rms_raw[i] < gate_thresh:
            prev_corpus_idx = -1  # Break continuity chain
            silent_grains_count += 1
            matches_record.append([
                i, 
                i * (hop_length / target_sr), 
                "__SILENCE__", 
                0.0, 
                0.0
            ])
            continue # Skip rendering this grain entirely!

        s_vec = source_norm[i]
        
        dists = np.sum(weights * (corpus_norm - s_vec)**2, axis=1)
        
        for rc in recent_choices:
            if rc < len(dists):
                dists[rc] += args.penalty * max_dist_estimate
                
        if prev_corpus_idx != -1 and prev_corpus_idx + 1 < num_corpus_grains:
            if corpus_metadata[prev_corpus_idx]['file_idx'] == corpus_metadata[prev_corpus_idx + 1]['file_idx']:
                dists[prev_corpus_idx + 1] -= args.continuity * max_dist_estimate
                
        dists = np.maximum(dists, 0.0)
                
        top_k_indices = np.argsort(dists)[:args.top_k]
        
        if args.randomness > 0:
            top_dists = dists[top_k_indices]
            inv_dists = 1.0 / (top_dists + 1e-9)
            
            uniform_dist = np.ones_like(inv_dists) / len(inv_dists)
            probs_raw = (1.0 - args.randomness) * (inv_dists / np.sum(inv_dists)) + (args.randomness * uniform_dist)
            
            probs = np.maximum(probs_raw, 0.0)
            prob_sum = np.sum(probs)
            if prob_sum > 1e-9:
                probs = probs / prob_sum
            else:
                probs = np.ones(len(top_k_indices), dtype=np.float32) / len(top_k_indices)
                
            chosen_idx = np.random.choice(top_k_indices, p=probs)
        else:
            chosen_idx = top_k_indices[0]
            
        prev_corpus_idx = chosen_idx
        recent_choices.append(chosen_idx)
        if len(recent_choices) > penalty_memory:
            recent_choices.pop(0)
            
        meta = corpus_metadata[chosen_idx]
        c_audio_ref = corpus_audio_data[meta['file_idx']]
        start_samp = meta['start_sample']
        
        actual_len = min(win_length, len(c_audio_ref) - start_samp)
        segment = c_audio_ref[start_samp:start_samp+actual_len]
        
        if actual_len < win_length:
            padded = np.zeros(win_length, dtype=np.float32)
            padded[:actual_len] = segment
            segment = padded
            
        out_start = i * hop_length
        out_audio[out_start:out_start+win_length] += segment * window
        
        matches_record.append([
            i, 
            i * (hop_length / target_sr), 
            os.path.basename(meta['file_path']), 
            start_samp / target_sr, 
            dists[chosen_idx]
        ])

    # ── 5. Output Finalisation ────────────────────────────────────────────────
    print("[Py 5/5] Finalising output and saving files...")
    
    if args.normalize:
        peak = float(np.abs(out_audio).max())
        if peak > 0.01:
            out_audio = (out_audio / peak * 0.95).astype(np.float32)
        
    sf.write(args.out_wav, out_audio, target_sr)
    
    with open(args.out_csv, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(["source_grain", "source_time_sec", "corpus_file", "corpus_time_sec", "distance"])
        writer.writerows(matches_record)
        
    unique_files = len(set([m[2] for m in matches_record if m[2] != "__SILENCE__"]))
    duration = time.time() - start_time
    
    with open(args.out_stats, 'w', encoding='utf-8') as f:
        f.write(f"Source grains: {num_source_grains}\n")
        f.write(f"Silenced grains (Gated): {silent_grains_count}\n")
        f.write(f"Corpus files analyzed: {valid_files_used}\n")
        f.write(f"Corpus grains available: {num_corpus_grains}\n")
        f.write(f"Unique files utilized: {unique_files}\n")
        f.write(f"Render time: {duration:.2f}s\n")

    print("[Py] Success. Exiting cleanly.")

if __name__ == "__main__":
    main()