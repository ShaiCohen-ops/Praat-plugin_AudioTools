"""
kd_tree_timbral_counterpoint.py — Latent Timbral Counterpoint Engine

Part of Praat AudioTools plugin
Calculates N-dimensional timbral distances to generate contrapuntal layers.
"""
import sys
import csv
import random
import argparse

def check_dependencies():
    try:
        import numpy
    except ImportError:
        print("ERROR: numpy is required. 'pip install numpy'", file=sys.stderr)
        sys.exit(1)

def main():
    check_dependencies()
    import numpy as np
    
    parser = argparse.ArgumentParser()
    parser.add_argument("target_csv")
    parser.add_argument("corpus_csv")
    parser.add_argument("match_csv")
    parser.add_argument("--voices", type=int, default=4)
    parser.add_argument("--ranks", type=str, default="1,3,8,20")
    parser.add_argument("--weights", type=str, default="1,1,1,1,1")
    parser.add_argument("--randomness", type=float, default=0.2)
    parser.add_argument("--rep_penalty", type=int, default=1)
    args = parser.parse_args()
    
    try:
        from scipy.spatial import cKDTree
        has_kdtree = True
    except ImportError:
        has_kdtree = False
        
    # Load corpus
    c_data, c_features = [], []
    with open(args.corpus_csv, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            c_data.append(row)
            feats = [
                float(row['mfcc1']), float(row['mfcc2']), float(row['mfcc3']),
                float(row['mfcc4']), float(row['mfcc5']), float(row['mfcc6']),
                float(row['centroid']), float(row['pitch']), float(row['intensity']),
                float(row['hnr']), float(row['zcr'])
            ]
            c_features.append(feats)
    X_c = np.array(c_features)
    
    # Load target
    t_data, t_features = [], []
    with open(args.target_csv, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            t_data.append(row)
            feats = [
                float(row['mfcc1']), float(row['mfcc2']), float(row['mfcc3']),
                float(row['mfcc4']), float(row['mfcc5']), float(row['mfcc6']),
                float(row['centroid']), float(row['pitch']), float(row['intensity']),
                float(row['hnr']), float(row['zcr'])
            ]
            t_features.append(feats)
    X_t = np.array(t_features)
    
    # Weights: MFCC, Pitch, Centroid, Intensity, HNR/ZCR
    w_vals = [float(x) for x in args.weights.split(",")]
    w_mfcc, w_pitch, w_cent, w_int, w_hnr = w_vals
    feat_weights = np.array([
        w_mfcc, w_mfcc, w_mfcc, w_mfcc, w_mfcc, w_mfcc,
        w_cent, w_pitch, w_int, w_hnr, w_hnr
    ])
    
    # Standardize across corpus space
    means = np.mean(X_c, axis=0)
    stds = np.std(X_c, axis=0) + 1e-8
    X_c_w = ((X_c - means) / stds) * feat_weights
    X_t_w = ((X_t - means) / stds) * feat_weights
    
    if has_kdtree:
        tree = cKDTree(X_c_w)
        
    ranks = [int(x) for x in args.ranks.split(",")]
    if len(ranks) < args.voices:
        ranks += [ranks[-1]] * (args.voices - len(ranks))
        
    matches = []
    used_indices = []
    
    for t_idx, t_row in enumerate(t_data):
        for v_idx in range(args.voices):
            rank_t = ranks[v_idx]
            shift = int(rank_t * args.randomness)
            actual_rank = max(1, rank_t + random.randint(-shift, shift))
            
            k_search = min(len(X_c_w), actual_rank + (30 if args.rep_penalty else 5))
            
            if has_kdtree:
                dists, inds = tree.query(X_t_w[t_idx], k=k_search)
                if k_search == 1:
                    dists, inds = [dists], [inds]
            else:
                diff = X_c_w - X_t_w[t_idx]
                d2 = np.sum(diff**2, axis=1)
                inds = np.argsort(d2)[:k_search]
                dists = np.sqrt(d2[inds])
                
            chosen_c_idx = inds[-1]
            chosen_dist = dists[-1]
            curr_rank = 1
            
            for i, c_idx in enumerate(inds):
                # Repetition penalty over last 20 chosen grains
                if args.rep_penalty and c_idx in used_indices[-20:]:
                    continue
                if curr_rank >= actual_rank:
                    chosen_c_idx = c_idx
                    chosen_dist = dists[i]
                    break
                curr_rank += 1
                
            used_indices.append(chosen_c_idx)
            c_row = c_data[chosen_c_idx]
            
            # Voice contrapuntal separation rules
            if v_idx == 0:
                gain, pan, delay = 0.9, 0.0, 0.0
            elif v_idx == 1:
                pan_val = 0.5 if t_idx % 2 == 0 else -0.5
                gain, pan, delay = 0.65, pan_val, 20.0
            elif v_idx == 2:
                pan_val = 0.8 if t_idx % 2 != 0 else -0.8
                gain, pan, delay = 0.45, pan_val, 45.0
            else:
                gain, pan, delay = 0.30, random.uniform(-1.0, 1.0), 80.0
                
            matches.append({
                'target_grain_index': t_idx + 1,
                'target_start_time': t_row['start_time'],
                'target_end_time': t_row['end_time'],
                'voice_number': v_idx + 1,
                'neighbor_rank': actual_rank,
                'selected_corpus_file': c_row['file_path'],
                'selected_corpus_start_time': c_row['start_time'],
                'selected_corpus_end_time': c_row['end_time'],
                'distance': round(chosen_dist, 4),
                'pitch_mean': c_row['pitch'],
                'intensity_mean': c_row['intensity'],
                'spectral_centroid': c_row['centroid'],
                'hnr': c_row['hnr'],
                'mfcc_distance': 0.0,
                'final_gain': gain,
                'pan_position': round(pan, 3),
                'delay_ms': delay
            })
            
    with open(args.match_csv, 'w', newline='', encoding='utf-8') as f:
        if not matches: return
        writer = csv.DictWriter(f, fieldnames=matches[0].keys())
        writer.writeheader()
        writer.writerows(matches)

if __name__ == "__main__":
    main()