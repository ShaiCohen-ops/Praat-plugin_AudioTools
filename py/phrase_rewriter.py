"""
phrase_rewriter.py — Phrase Rewriter Engine

Part of Praat AudioTools plugin
Author: OpenAI (for Shai Cohen workflow adaptation)

Usage (called by Praat, not directly):
    python phrase_rewriter.py input.wav features.csv output.wav stats.txt \
        mode preserve_source rewrite_intensity duration_policy variation seed hop_sec [--cleanup]

Architecture:
    Stage 1 — Load audio + Praat-exported feature table
    Stage 2 — Build phrase curve summaries + event segmentation
    Stage 3 — Generate rewrite plan from compositional archetype
    Stage 4 — Render recomposed output from source events
    Stage 5 — Normalize, write output.wav + stats.txt
    Stage 6 — Optional cleanup of Praat-created temp files

No internet. No external model downloads. Python is the hidden planning engine;
Praat remains the front-end and final user environment.
"""

import sys
import os
import csv
import math

PRAAT_TEMP_PREFIX = "temp_phraserw_"
XFADE_SEC = 0.010
EVENT_MIN_DUR = 0.040
EVENT_MAX_DUR = 1.500


def check_dependencies():
    missing = []
    for pkg in ["numpy", "soundfile", "scipy"]:
        try:
            __import__(pkg)
        except ImportError:
            missing.append(pkg)
    if missing:
        print("ERROR: Missing Python packages: " + ", ".join(missing), file=sys.stderr)
        print("Install with: pip install " + " ".join(missing), file=sys.stderr)
        sys.exit(1)


def _is_praat_temp(path):
    return os.path.basename(path).startswith(PRAAT_TEMP_PREFIX)


def load_praat_features(csv_path):
    data = {}
    with open(csv_path, "r", newline="") as f:
        reader = csv.DictReader(f)
        cols = {}
        for row in reader:
            for k, v in row.items():
                cols.setdefault(k, [])
                try:
                    cols[k].append(float(v))
                except Exception:
                    cols[k].append(0.0)
    return cols


def smooth(x, sigma_frames=2.0):
    import numpy as np
    from scipy.ndimage import gaussian_filter1d
    x = np.asarray(x, dtype=np.float64)
    if len(x) < 3:
        return x
    return gaussian_filter1d(x, sigma=max(0.5, sigma_frames), mode="nearest")


def robust01(x):
    import numpy as np
    x = np.asarray(x, dtype=np.float64)
    lo = np.percentile(x, 5)
    hi = np.percentile(x, 95)
    if hi - lo < 1e-9:
        return np.zeros_like(x)
    y = (x - lo) / (hi - lo)
    return np.clip(y, 0.0, 1.0)


def build_phrase_features(feats):
    import numpy as np
    time = np.asarray(feats.get("time", []), dtype=np.float64)
    pitch = np.asarray(feats.get("pitch", []), dtype=np.float64)
    hnr = np.asarray(feats.get("hnr", []), dtype=np.float64)
    intensity = np.asarray(feats.get("intensity", []), dtype=np.float64)
    f1 = np.asarray(feats.get("f1", np.zeros_like(intensity)), dtype=np.float64)
    f2 = np.asarray(feats.get("f2", np.zeros_like(intensity)), dtype=np.float64)
    voiced = np.asarray(feats.get("voiced", np.ones_like(intensity)), dtype=np.float64)

    intensity_s = smooth(intensity, 2.0)
    pitch_s = smooth(pitch, 2.0)
    hnr_s = smooth(hnr, 2.0)
    bright = smooth(0.6 * f2 + 0.4 * f1, 2.0)

    dint = np.zeros_like(intensity_s)
    if len(intensity_s) > 1:
        dint[1:] = np.diff(intensity_s)
    dint_abs = np.abs(dint)

    activity = robust01(dint_abs) * 0.5 + robust01(intensity_s) * 0.3 + robust01(np.maximum(0.0, pitch_s)) * 0.2
    tension = 0.4 * robust01(intensity_s) + 0.3 * robust01(bright) + 0.3 * (1.0 - robust01(hnr_s))
    onsets = robust01(np.maximum(0.0, dint))

    return {
        "time": time,
        "pitch": pitch_s,
        "hnr": hnr_s,
        "intensity": intensity_s,
        "bright": bright,
        "voiced": voiced,
        "activity": activity,
        "tension": tension,
        "onsets": onsets,
    }


def segment_events(audio, sr, pf, hop_sec):
    import numpy as np
    times = pf["time"]
    n = len(times)
    if n < 4:
        return [{"start_time": 0.0, "end_time": len(audio) / sr, "strength": 1.0, "label": "whole"}]

    onset = pf["onsets"]
    activity = pf["activity"]
    tension = pf["tension"]
    novelty = 0.5 * onset + 0.3 * np.abs(np.gradient(activity)) + 0.2 * np.abs(np.gradient(tension))
    novelty = smooth(novelty, 1.0)
    thr = float(np.mean(novelty) + 0.35 * np.std(novelty))

    min_frames = max(2, int(EVENT_MIN_DUR / hop_sec))

    from scipy.signal import find_peaks as _find_peaks
    peak_idx, _ = _find_peaks(novelty, height=thr, distance=min_frames)
    candidates = sorted(set([0] + list(peak_idx) + [n - 1]))

    # split long events
    max_frames = max(min_frames + 1, int(EVENT_MAX_DUR / hop_sec))
    final_bounds = [candidates[0]]
    for a, b in zip(candidates[:-1], candidates[1:]):
        span = b - a
        if span <= max_frames:
            final_bounds.append(b)
        else:
            nsplit = int(math.ceil(span / max_frames))
            for s in range(1, nsplit + 1):
                final_bounds.append(min(b, a + int(round(span * s / nsplit))))
    final_bounds = sorted(set(final_bounds))

    events = []
    for a, b in zip(final_bounds[:-1], final_bounds[1:]):
        if b <= a:
            continue
        st = float(times[a])
        en = float(times[b])
        if en - st < EVENT_MIN_DUR * 0.6:
            continue
        sl = slice(a, max(a + 1, b))
        strength = float(np.mean(pf["activity"][sl]) + 0.5 * np.mean(pf["tension"][sl]))
        events.append({
            "start_time": st,
            "end_time": en,
            "strength": strength,
            "intensity": float(np.mean(pf["intensity"][sl])),
            "bright": float(np.mean(pf["bright"][sl])),
            "hnr": float(np.mean(pf["hnr"][sl])),
            "pitch": float(np.mean(pf["pitch"][sl][pf["pitch"][sl] > 0])) if np.any(pf["pitch"][sl] > 0) else 0.0,
            "activity": float(np.mean(pf["activity"][sl])),
            "tension": float(np.mean(pf["tension"][sl])),
        })
    if not events:
        events.append({"start_time": 0.0, "end_time": len(audio) / sr, "strength": 1.0,
                       "intensity": 0.0, "bright": 0.0, "hnr": 0.0, "pitch": 0.0,
                       "activity": 0.0, "tension": 0.0})
    return events


def extract_clips(audio, sr, events):
    clips = []
    n_samples = len(audio)
    for ev in events:
        s = max(0, min(int(round(ev["start_time"] * sr)), n_samples))
        e = max(s + 1, min(int(round(ev["end_time"] * sr)), n_samples))
        clips.append(audio[s:e].copy())
    return clips


def _fade_clip(clip, sr):
    import numpy as np
    clip = clip.astype(np.float32, copy=True)
    fade = min(max(4, int(XFADE_SEC * sr)), len(clip) // 4)
    if fade >= 2:
        ramp_in = np.linspace(0.0, 1.0, fade, dtype=np.float32)
        ramp_out = np.linspace(1.0, 0.0, fade, dtype=np.float32)
        if clip.ndim == 1:
            clip[:fade] *= ramp_in
            clip[-fade:] *= ramp_out
        else:
            clip[:fade, :] *= ramp_in[:, None]
            clip[-fade:, :] *= ramp_out[:, None]
    return clip


def _resample_linear(clip, target_len):
    import numpy as np
    if len(clip) == target_len:
        return clip.astype(np.float32, copy=True)
    if clip.ndim == 1:
        x = np.arange(len(clip))
        t = np.linspace(0, len(clip) - 1, target_len)
        return np.interp(t, x, clip).astype(np.float32)
    out = np.zeros((target_len, clip.shape[1]), dtype=np.float32)
    x = np.arange(len(clip))
    t = np.linspace(0, len(clip) - 1, target_len)
    for ch in range(clip.shape[1]):
        out[:, ch] = np.interp(t, x, clip[:, ch]).astype(np.float32)
    return out


def _spectral_blur(clip, amt):
    from scipy.signal import stft, istft
    import numpy as np
    
    if amt <= 0.001:
        return clip.astype(np.float32, copy=True)
        
    mono = clip if clip.ndim == 1 else np.mean(clip, axis=1)
    
    # FIX: Dynamically scale FFT size for very short audio clips
    n_fft = min(1024, len(mono))
    
    # If the clip is impossibly short, skip blurring to prevent math errors
    if n_fft < 4:
        return clip.astype(np.float32, copy=True)
        
    hop = max(1, n_fft // 4)
    
    _, _, Z = stft(mono, window="hann", nperseg=n_fft, noverlap=n_fft-hop)
    mag = np.abs(Z)
    ph = np.angle(Z)
    
    k = max(1, int(round(1 + 8 * amt)))
    kernel = np.ones(k) / k
    from scipy.ndimage import convolve1d
    mag2 = convolve1d(mag, kernel, axis=1, mode="nearest")
    
    _, y = istft(mag2 * np.exp(1j * ph), window="hann", nperseg=n_fft, noverlap=n_fft-hop)
    
    y = y[:len(mono)].astype(np.float32)
    
    if clip.ndim == 1:
        return y
    return np.column_stack([y for _ in range(clip.shape[1])]).astype(np.float32)


def _resonance_emphasis(clip, amt, sr):
    from scipy.signal import butter, sosfilt
    import numpy as np
    if amt <= 0.001:
        return clip.astype(np.float32, copy=True)
    mono = clip if clip.ndim == 1 else np.mean(clip, axis=1)
    # Simple resonant body emphasis via low-mid band layering
    sos = butter(4, [250 / (sr / 2.0), 2800 / (sr / 2.0)], btype="band", output="sos")
    band = sosfilt(sos, mono).astype(np.float32)
    y = mono.astype(np.float32) * (1.0 - 0.25 * amt) + band * (0.65 * amt)
    if clip.ndim == 1:
        return y
    return np.column_stack([y for _ in range(clip.shape[1])]).astype(np.float32)


def _pitch_shift_clip(clip, sr, semitones):
    """Varispeed pitch shift via resampling.
    Shifts pitch by *semitones* (positive = up, negative = down).
    Duration changes proportionally — intentional for Constellation grain processing:
    the dur_scale in the plan absorbs the length difference transparently.
    No new dependencies required.
    """
    if abs(semitones) < 0.05:
        return clip.astype(np.float32, copy=True)
    ratio = 2.0 ** (semitones / 12.0)           # speed-up ratio: >1 = higher pitch
    shifted_len = max(1, int(round(len(clip) / ratio)))
    return _resample_linear(clip, shifted_len)   # resamples to new speed → changed pitch


def generate_plan(events, mode, preserve, intensity, duration_policy, variation, seed,
                  fragment_length_scale=1.0):
    import numpy as np
    rng = np.random.RandomState(seed)
    n = len(events)
    if n == 0:
        return []

    strengths = np.array([ev["strength"] for ev in events], dtype=np.float64)
    order = np.argsort(-strengths)
    mean_len = np.mean([ev["end_time"] - ev["start_time"] for ev in events])
    target = []

    def choose_salient(frac):
        k = max(1, min(n, int(round(frac * n))))
        idx = sorted(order[:k].tolist())
        return idx

    if mode == "Constellation":
        # ------------------------------------------------------------------ #
        # CONSTELLATION — Phrase Crystallization (redesigned)                 #
        #                                                                      #
        # Redistributes the phrase into a field of short, articulate point-   #
        # like fragments (stars, satellites, echoes, shadows) distributed     #
        # across the phrase span while preserving a latent phrase contour.    #
        # Silence is compositional spacing, not random padding.               #
        # ------------------------------------------------------------------ #

        t_phrase_start = events[0]["start_time"]
        t_phrase_end   = events[-1]["end_time"]
        phrase_span    = max(t_phrase_end - t_phrase_start, 1e-6)
        orig_dur       = phrase_span

        durations  = np.array([ev["end_time"] - ev["start_time"] for ev in events], dtype=np.float64)
        tensions   = np.array([ev["tension"]   for ev in events], dtype=np.float64)
        phrase_pos = np.array(
            [(ev["start_time"] - t_phrase_start) / phrase_span for ev in events],
            dtype=np.float64,
        )
        tens_n = robust01(tensions)

        # ── A. Seed selection: 35–70 % of source events ──────────────────
        # Higher preserve_source → more seeds; variation adds mild dither.
        density = float(np.clip(
            0.35 + 0.35 * preserve + rng.uniform(-0.04, 0.04) * variation,
            0.30, 0.72,
        ))
        k_seed    = max(4, min(n, int(round(density * n))))

        # When fragment_length_scale > 1, blend duration into the selection
        # score so that longer events are preferentially selected — otherwise
        # fragment_length has no effect when the most salient events are short.
        _fls_sel = float(np.clip(fragment_length_scale, 0.10, 4.0))
        _dur_weight = float(np.clip((_fls_sel - 1.0) / 3.0, 0.0, 1.0))  # 0 at 1x, 1.0 at 4x
        dur_n = robust01(durations)
        sel_score = strengths * (0.55 + 0.45 * tens_n) * (
            1.0 - _dur_weight * 0.50 + _dur_weight * 0.50 * dur_n
        )
        sel_ord   = np.argsort(-sel_score).tolist()

        # Guarantee at least one seed per phrase quarter → contour coverage
        quarters = [[], [], [], []]
        for _qi in range(n):
            _q = min(3, int(phrase_pos[_qi] * 4))
            quarters[_q].append(_qi)
        mandatory = {max(ql, key=lambda _i: sel_score[_i]) for ql in quarters if ql}

        selected = list(mandatory)
        for _idx in sel_ord:
            if len(selected) >= k_seed:
                break
            if _idx not in mandatory:
                selected.append(_idx)
        selected.sort()   # restore phrase order

        # ── B. Fragment crystallization ───────────────────────────────────
        # Each seed is broken into 1–3 short point-fragments.
        # dur_scale trims playback to onset/attack character; target 40–190 ms.
        # Higher intensity  → shorter fragments, more sub-event splits.
        # Higher preserve   → slightly longer fragments, fewer splits.
        frag_pool = []

        for ev_idx in selected:
            ev_dur = float(durations[ev_idx])
            ppos   = float(phrase_pos[ev_idx])
            ev_sco = float(sel_score[ev_idx])

            # tgt_sec: base onset-bite window at fragment_length_scale=1.0.
            # fragment_length_scale multiplies this directly — longer scale = longer
            # bite taken from the source clip. dur_scale stays near 1.0 so there
            # is NO varispeed pitch change from fragment_length. pitch_shift works
            # fully independently with no interaction.
            tgt_sec = float(np.clip(
                0.090 + 0.110 * (0.25 + 0.60 * preserve) * (1.0 - 0.35 * intensity),
                0.070, 0.200,
            )) * float(np.clip(fragment_length_scale, 0.10, 4.0))

            # n_frags scales inversely with fragment_length_scale
            _fls = float(np.clip(fragment_length_scale, 0.10, 4.0))
            if _fls >= 2.0:
                n_frags = 1
            elif ev_dur < 0.12:
                n_frags = 1
            elif ev_dur < 0.40:
                n_frags = 1 if (preserve > 0.65 or _fls > 1.2 or rng.rand() < 0.45 + 0.30 * preserve) else 2
            else:
                _split_prob = max(0.0, 0.45 - 0.25 * (_fls - 1.0))
                n_frags = 2 + (1 if intensity > 0.50 and rng.rand() < _split_prob else 0)
                if _fls > 1.2:
                    n_frags = max(1, n_frags - 1)

            for _fi in range(n_frags):
                trim_jitter = 1.0 + rng.uniform(-0.12, 0.25) * (1.0 + variation)
                onset_trim_sec = float(np.clip(tgt_sec * trim_jitter, 0.060, ev_dur))
                _frag_offset_sec = 0.0
                if n_frags > 1 and ev_dur > onset_trim_sec:
                    _max_offset = ev_dur - onset_trim_sec
                    _frag_offset_sec = float(np.clip(
                        (_fi / n_frags) * _max_offset * (0.7 + 0.3 * rng.rand()),
                        0.0, _max_offset,
                    ))
                # dur_scale: gentle ±20% only — no varispeed pitch change
                ds_v = float(np.clip(
                    (0.88 + 0.24 * rng.rand()) * (1.0 + rng.uniform(-0.10, 0.10) * variation),
                    0.70, 1.30,
                ))
                frag_pool.append({
                    "src":              ev_idx,
                    "ds_raw":           ds_v,
                    "onset_trim_sec":   onset_trim_sec,
                    "frag_offset_sec":  _frag_offset_sec,
                    "phrase_pos":       ppos + _fi * 0.004,
                    "score":            ev_sco * (1.0 - 0.10 * _fi),
                    "ev_dur":           ev_dur,
                    "ev_ten":           float(tensions[ev_idx]),
                })

        if not frag_pool:
            # Fallback: passthrough at reduced scale
            _t = 0.0
            for _i in range(n):
                target.append({"src": _i, "start": _t, "dur_scale": 0.8, "gain": 0.8,
                               "blur": 0.0, "res": 0.0, "_min_render_sec": 0.030})
                _t += durations[_i]
        else:
            nf        = len(frag_pool)
            score_max = max(f["score"] for f in frag_pool) or 1e-6
            sbs       = sorted(range(nf), key=lambda _i: -frag_pool[_i]["score"])

            # ── C. Role assignment by score tier ──────────────────────────
            # stars: strongest phrase anchors  (≈ 18–25 %)
            # satellites: articulate neighbors  (≈ 35–50 %)
            # echoes: faint after-images         (≈ 15–25 %)
            # shadows: brief residual flickers   (≈ 10–20 %)
            n_stars   = max(1, int(round(nf * (0.18 + 0.07 * preserve))))
            n_echoes  = max(1, int(round(nf * (0.17 + 0.08 * variation))))
            n_shadows = max(1, int(round(nf * (0.11 + 0.07 * (1.0 - preserve)))))
            n_stars   = min(n_stars,  nf)
            n_echoes  = min(n_echoes, nf - n_stars)
            n_shadows = min(n_shadows, max(0, nf - n_stars - n_echoes))

            _roles = ["satellite"] * nf
            for _i in range(n_stars):
                _roles[sbs[_i]] = "star"
            for _i in range(n_echoes):
                _roles[sbs[nf - 1 - _i]] = "echo"
            for _i in range(n_shadows):
                _j = sbs[nf - 1 - n_echoes - _i]
                if _roles[_j] == "satellite":
                    _roles[_j] = "shadow"
            for _i, _f in enumerate(frag_pool):
                _f["role"] = _roles[_i]

            # ── D. Sort by phrase position to preserve contour ────────────
            frag_pool.sort(key=lambda _f: _f["phrase_pos"])

            # ── E. Role-based spacing grammar ─────────────────────────────
            # Stars open wider space; satellites cluster; echoes trail stars;
            # shadows flicker briefly.  High-tension zones → denser clustering.
            _role_gap = {
                "star":      0.55 + 0.35 * intensity,
                "satellite": 0.28 + 0.18 * intensity,
                "echo":      0.14 + 0.10 * intensity,
                "shadow":    0.10 + 0.15 * variation,
            }
            _role_gain = {
                "star":      (0.75, 0.95),
                "satellite": (0.44, 0.64),
                "echo":      (0.20, 0.37),
                "shadow":    (0.07, 0.17),
            }
            # dur_scale multiplier per role: now applied to the already-trimmed clip.
            # Since clips are pre-trimmed to ~tgt_sec, these are gentle adjustments
            # around 1.0 — no compression-ratio chirps possible.
            _role_ds = {
                "star":      float(np.clip(1.15 + 0.15 * preserve, 1.00, 1.40)),
                "satellite": 1.00,
                "echo":      float(np.clip(0.85 - 0.10 * intensity, 0.70, 0.90)),
                "shadow":    float(np.clip(0.70 - 0.08 * intensity, 0.58, 0.80)),
            }
            # onset_trim_sec multiplier per role: stars get a slightly longer window,
            # shadows get a shorter bite from the onset.
            _role_trim = {
                "star":      1.30,
                "satellite": 1.00,
                "echo":      0.80,
                "shadow":    0.60,
            }

            _ten_max  = float(max(tensions.max(), 1e-6))
            _mean_gap = orig_dur / max(nf, 1) * (0.35 + 0.20 * intensity)
            _MIN_GAP  = 0.008

            plan_entries = []
            t_cursor  = 0.0
            prev_role = None

            for _frag in frag_pool:
                _role   = _frag["role"]
                _ev_idx = _frag["src"]
                _ev_dur = _frag["ev_dur"]

                if not plan_entries:
                    t_pt = 0.0
                else:
                    _gm  = _role_gap[_role]
                    # Denser near climactic/high-tension phrase zones
                    _td  = 1.0 - 0.30 * float(np.clip(tensions[_ev_idx] / _ten_max, 0.0, 1.0))
                    _gap = _mean_gap * _gm * _td * (
                        1.0 + rng.uniform(-0.22, 0.22) * variation
                    )
                    # Echo immediately trailing a star: very tight gap
                    if _role == "echo" and prev_role in ("star", "satellite"):
                        _gap = _mean_gap * 0.12 * (1.0 + rng.uniform(-0.10, 0.10))
                    t_pt = t_cursor + max(_MIN_GAP, _gap)

                # Trim window for this role (clamped to actual event duration)
                _trim_sec = float(np.clip(
                    _frag["onset_trim_sec"] * _role_trim[_role],
                    0.060, _ev_dur,
                ))
                _ds      = float(np.clip(_frag["ds_raw"] * _role_ds[_role], 0.60, 1.50))
                _g_lo, _g_hi = _role_gain[_role]
                _ns      = float(np.clip(_frag["score"] / score_max, 0.0, 1.0))
                _gain    = _g_lo + (_g_hi - _g_lo) * (0.35 + 0.65 * _ns)
                _gain    = float(np.clip(
                    _gain * (1.0 + rng.uniform(-0.05, 0.05) * variation),
                    _g_lo * 0.70, _g_hi * 1.10,
                ))
                _blur    = (0.08 + 0.12 * intensity) if _role == "echo" else \
                           (0.12 + 0.18 * intensity) if _role == "shadow" else 0.0

                plan_entries.append({
                    "src":              _ev_idx,
                    "start":            t_pt,
                    "dur_scale":        _ds,
                    "gain":             _gain,
                    "blur":             _blur,
                    "res":              0.0,
                    "_onset_trim_sec":  _trim_sec,  # renderer trims clip before resampling
                    "_frag_offset_sec": _frag["frag_offset_sec"],
                    "_min_render_sec":  0.060,
                    "_role":            _role,
                })
                # Advance cursor by rendered fragment duration (trim × scale)
                t_cursor  = t_pt + _trim_sec * _ds
                prev_role = _role

            # ── F. Micro-pair companions for ~35 % of stars ───────────────
            # Some stars spawn an echo or shadow companion — creates genuine
            # "constellation" feel rather than isolated spikes.
            _companions = []
            for _e in plan_entries:
                if _e["_role"] != "star":
                    continue
                if rng.rand() > 0.35 + 0.20 * variation:
                    continue
                _ed = float(durations[_e["src"]])
                _rs = _ed * _e["dur_scale"]
                if rng.rand() < 0.60:   # echo companion
                    _c_start = _e["start"] + (_e.get("_onset_trim_sec", 0.12) * _e["dur_scale"]) * (0.50 + 0.30 * rng.rand())
                    _c_trim  = float(np.clip(_e.get("_onset_trim_sec", 0.12) * (0.55 + 0.20 * rng.rand()), 0.060, 0.30))
                    _companions.append({
                        "src":              _e["src"],
                        "start":            max(_e["start"] + 0.020, _c_start),
                        "dur_scale":        float(np.clip(0.85 + 0.20 * rng.rand(), 0.70, 1.10)),
                        "gain":             float(np.clip(_e["gain"] * (0.18 + 0.10 * preserve), 0.03, 0.28)),
                        "blur":             0.10 + 0.15 * intensity,
                        "res":              0.0,
                        "_onset_trim_sec":  _c_trim,
                        "_min_render_sec":  0.060,
                        "_role":            "echo",
                    })
                else:                   # shadow companion
                    _c_start = _e["start"] + (_e.get("_onset_trim_sec", 0.12) * _e["dur_scale"]) * (0.78 + 0.15 * rng.rand())
                    _c_trim  = float(np.clip(_e.get("_onset_trim_sec", 0.12) * (0.35 + 0.10 * rng.rand()), 0.060, 0.20))
                    _companions.append({
                        "src":              _e["src"],
                        "start":            max(_e["start"] + 0.020, _c_start),
                        "dur_scale":        float(np.clip(0.80 + 0.15 * rng.rand(), 0.70, 1.00)),
                        "gain":             float(np.clip(_e["gain"] * (0.07 + 0.05 * variation), 0.015, 0.13)),
                        "blur":             0.18,
                        "res":              0.0,
                        "_onset_trim_sec":  _c_trim,
                        "_min_render_sec":  0.060,
                        "_role":            "shadow",
                    })
            plan_entries.extend(_companions)

            # Strip internal keys before handing off to the renderer
            for _e in plan_entries:
                _e.pop("_role", None)

            target = plan_entries

    elif mode == "Cloud":
        reps = max(n, int(round(n * (1.5 + 1.0 * intensity))))
        base = np.linspace(0, n - 1, reps)
        overlap_frac = 0.45 + 0.35 * intensity
        step = max(mean_len * 0.10, mean_len * (1.0 - overlap_frac))
        t = 0.0
        dur_scale_base = 0.70 + 0.40 * preserve
        gain_base = 0.40 + 0.25 * preserve
        last_idx = -1
        repeat_count = 0
        max_repeats = max(2, int(round(3 - 2 * variation)))
        for j in range(reps):
            idx = int(round(base[j] + rng.uniform(-0.75, 0.75) * variation * (n / 4.0)))
            idx = max(0, min(n - 1, idx))
            if idx == last_idx:
                repeat_count += 1
                if repeat_count >= max_repeats:
                    nudge = 1 if rng.rand() > 0.5 else -1
                    idx = max(0, min(n - 1, idx + nudge))
                    repeat_count = 0
            else:
                repeat_count = 0
            last_idx = idx
            jitter = mean_len * 0.15 * variation * rng.randn()
            dur_scale = dur_scale_base * (0.85 + 0.30 * events[idx]["activity"]) * (1.0 + rng.uniform(-0.20, 0.20) * variation)
            dur_scale = max(0.30, min(0.99, dur_scale))
            gain = gain_base * (0.85 + 0.30 * events[idx]["activity"])
            target.append({"src": idx, "start": max(0.0, t + jitter),
                           "dur_scale": dur_scale, "gain": gain,
                           "blur": 0.20 + 0.50 * intensity, "res": 0.0})
            t += max(step * 0.5, step * (1.0 + rng.uniform(-0.15, 0.15) * variation))

    elif mode == "Resonance":
        k_res = max(2, int(round(n * (0.25 + 0.15 * preserve))))
        sel = order[:k_res].tolist()
        dur_scale_base = 1.0 + 1.5 * intensity
        t = 0.0
        for idx in sel:
            ev = events[idx]
            ev_dur = ev["end_time"] - ev["start_time"]
            dur_scale = dur_scale_base * (1.0 + rng.uniform(-0.10, 0.10) * variation)
            gain = 0.65 + 0.25 * preserve
            target.append({"src": idx, "start": t, "dur_scale": dur_scale,
                           "gain": gain, "blur": 0.05 + 0.20 * intensity,
                           "res": 0.40 + 0.55 * intensity})
            if rng.rand() < 0.50 + 0.30 * variation:
                echo_frac = 0.45 + 0.20 * preserve + rng.uniform(-0.10, 0.10) * variation
                echo_frac = max(0.25, min(0.85, echo_frac))
                echo_scale = dur_scale * (0.65 + 0.35 * rng.rand())
                target.append({"src": idx, "start": t,
                               "echo_frac": echo_frac,
                               "dur_scale": echo_scale, "gain": gain * 0.45,
                               "blur": 0.25, "res": 0.85})
            step = ev_dur * dur_scale + mean_len * (0.55 + 0.45 * (1.0 - preserve))
            t += max(mean_len * 0.3, step)

    elif mode == "Center":
        center_idx = int(order[0])
        reps = max(3, int(round(3 + 6 * intensity)))
        t = 0.0
        for j in range(reps):
            frac = j / max(1, reps - 1)
            arch = math.sin(math.pi * frac)
            dur_scale = (0.85 + 0.45 * preserve) * (1.0 + 0.20 * rng.rand() * variation)
            gain = 0.40 + 0.55 * arch + 0.15 * rng.rand() * variation
            target.append({"src": center_idx, "start": t, "dur_scale": dur_scale,
                           "gain": gain, "blur": 0.0,
                           "res": 0.10 + 0.30 * intensity})
            ev_dur = events[center_idx]["end_time"] - events[center_idx]["start_time"]
            t += ev_dur * dur_scale * (0.60 + 0.25 * rng.rand())
        if n > 2:
            n_sats = min(n - 1, max(2, int(round(2 + 3 * preserve))))
            sats = order[1:1 + n_sats].tolist()
            rng.shuffle(sats)
            total_so_far = t
            for sat_idx in sats:
                sat_start = rng.uniform(0.0, max(0.1, total_so_far))
                ev_dur = events[sat_idx]["end_time"] - events[sat_idx]["start_time"]
                target.append({"src": sat_idx, "start": sat_start,
                               "dur_scale": 0.40 + 0.30 * preserve,
                               "gain": 0.25 + 0.20 * events[sat_idx]["activity"],
                               "blur": 0.0, "res": 0.0})

    elif mode == "Becoming":
        t = 0.0
        step = mean_len * (0.45 + 0.10 * preserve)
        for idx in range(n):
            frac = idx / max(1, n - 1)
            dur_scale = (0.50 + 0.80 * frac * intensity) * (1.0 + rng.uniform(-0.05, 0.05) * variation)
            gain = 0.30 + 0.65 * frac
            blur = 0.0 + 0.25 * frac
            res  = 0.0 + 0.55 * frac * intensity
            target.append({"src": idx, "start": t, "dur_scale": max(0.2, dur_scale),
                           "gain": gain, "blur": blur, "res": res})
            t += max(mean_len * 0.15, step * (1.0 + rng.uniform(-0.08, 0.08) * variation))

    elif mode == "Distance":
        k_dist = max(2, int(round(n * (0.25 + 0.15 * preserve))))
        keep = order[:k_dist].tolist()
        t = 0.0
        gap_base = mean_len * (1.8 + 2.2 * intensity)
        for idx in keep:
            ev = events[idx]
            ev_dur = ev["end_time"] - ev["start_time"]
            dur_scale = (0.65 + 0.35 * preserve + 0.15 * ev["activity"]) * (1.0 + rng.uniform(-0.15, 0.15) * variation)
            dur_scale = max(0.25, min(1.40, dur_scale))
            gain = (0.55 + 0.30 * preserve + 0.20 * ev["activity"]) * (1.0 + rng.uniform(-0.10, 0.10) * variation)
            gap = gap_base * (1.0 + rng.uniform(-0.20, 0.20) * variation)
            target.append({"src": idx, "start": t, "dur_scale": dur_scale,
                           "gain": gain, "blur": 0.05, "res": 0.10})
            if variation > 0.05 and rng.rand() < 0.45 + 0.25 * variation:
                echo_t = t + ev_dur * dur_scale + gap * (0.55 + 0.25 * rng.rand())
                target.append({"src": idx, "start": echo_t,
                               "dur_scale": 0.30, "gain": gain * 0.22,
                               "blur": 0.20, "res": 0.30})
            t += ev_dur * dur_scale + gap

    elif mode == "Mass":
        reps = max(10, int(round(10 + 14 * intensity)))
        orig_dur = max(ev["end_time"] for ev in events)
        center = orig_dur * 0.30
        spread_base = mean_len * (0.30 + 1.20 * (1.0 - intensity))
        act_weights = np.array([ev["activity"] + 0.1 for ev in events])
        act_weights /= act_weights.sum()
        for j in range(reps):
            idx = int(rng.choice(n, p=act_weights))
            ev = events[idx]
            spread = spread_base * (1.2 - 0.5 * ev["activity"])
            start = max(0.0, center + rng.randn() * spread)
            dur_scale = 0.50 + 0.45 * rng.rand() * (0.6 + 0.4 * preserve)
            gain = 0.38 + 0.32 * ev["activity"] + 0.15 * rng.rand()
            target.append({"src": idx, "start": start, "dur_scale": dur_scale,
                           "gain": gain, "blur": 0.10 + 0.30 * intensity, "res": 0.0})

    elif mode == "Multiplication":
        t = 0.0
        step = mean_len * (0.50 + 0.25 * preserve)
        for idx, ev in enumerate(events):
            ev_dur = ev["end_time"] - ev["start_time"]
            copies = 1 + int(round(1.0 + 3.0 * intensity * (0.5 + 0.5 * ev["activity"])))
            dur_scale_base = 0.55 + 0.45 * preserve
            for c in range(copies):
                offset = ev_dur * dur_scale_base * (0.55 * c) + \
                         mean_len * 0.04 * c + \
                         rng.uniform(-0.03, 0.03) * mean_len * variation
                gain = (0.70 + 0.20 * ev["activity"]) * (0.65 ** c)
                blur = 0.0 + 0.12 * c * intensity
                target.append({"src": idx, "start": max(0.0, t + offset),
                               "dur_scale": dur_scale_base * max(0.5, 1.0 - 0.10 * c),
                               "gain": gain, "blur": min(0.8, blur), "res": 0.0})
            t += max(mean_len * 0.20, step * (1.0 + rng.uniform(-0.06, 0.06) * variation))

    else:
        t = 0.0
        for idx, ev in enumerate(events):
            target.append({"src": idx, "start": t, "dur_scale": 0.8, "gain": 0.8, "blur": 0.0, "res": 0.0})
            t += ev["end_time"] - ev["start_time"]

    # FIX: Bypass duration stretching for 'Mass' so it remains a tight cluster
    if mode == "Mass":
        return sorted(target, key=lambda r: r["start"])

    # duration policy
    if not target:
        return target
    starts = [row["start"] for row in target]
    ends = []
    for row in target:
        ev = events[row["src"]]
        # For Constellation rows that carry _onset_trim_sec, use trim × scale
        # as the actual rendered length rather than full event × scale.
        _trim = row.get("_onset_trim_sec", None)
        if _trim is not None:
            _frag_dur = float(_trim) * row["dur_scale"]
        else:
            _frag_dur = (ev["end_time"] - ev["start_time"]) * row["dur_scale"]
        ends.append(row["start"] + _frag_dur)
    total = max(ends)
    orig = max(ev["end_time"] for ev in events)
    if duration_policy == "keep":
        scale = orig / max(total, 1e-6)
    elif duration_policy == "shorter":
        target_len = orig * (0.65 + 0.2 * preserve)
        scale = target_len / max(total, 1e-6)
    else:  # longer
        target_len = orig * (1.20 + 1.3 * intensity)
        scale = target_len / max(total, 1e-6)
    for row in target:
        row["start"] *= scale
    return sorted(target, key=lambda r: r["start"])


def render_plan(audio, sr, clips, events, plan):
    import numpy as np
    if audio.ndim == 1:
        n_channels = 1
    else:
        n_channels = audio.shape[1]
    if not plan:
        return audio.astype(np.float32, copy=True)

    ends = []
    for row in plan:
        ev = events[row["src"]]
        dur = (ev["end_time"] - ev["start_time"]) * row["dur_scale"]
        ends.append(row["start"] + dur)
    n_out = max(1, int(round(max(ends) * sr)) + int(0.05 * sr))
    output = np.zeros((n_out, n_channels), dtype=np.float32) if n_channels > 1 else np.zeros(n_out, dtype=np.float32)

    main_end_by_src = {}
    resolved_plan = []
    for row in sorted(plan, key=lambda r: r["start"]):
        if "echo_frac" not in row:
            ev = events[row["src"]]
            rendered_samples = max(int(0.250 * sr), int(round(len(clips[row["src"]]) * row["dur_scale"])))
            main_end_by_src[row["src"]] = (row["start"], rendered_samples)
            resolved_plan.append(dict(row))
        else:
            if row["src"] in main_end_by_src:
                m_start, m_len = main_end_by_src[row["src"]]
                echo_offset_sec = (m_len * row["echo_frac"]) / sr
                resolved_row = dict(row)
                resolved_row["start"] = m_start + echo_offset_sec
                del resolved_row["echo_frac"]
                resolved_plan.append(resolved_row)
            else:
                pass

    _default_min_render_sec = 0.250  # perceptual floor — prevents sub-click bursts
    for row in resolved_plan:
        # Per-row override lets Constellation emit short point-fragments.
        # All other modes leave this key absent and get the 250 ms default.
        _row_floor = int(row.pop("_min_render_sec", _default_min_render_sec) * sr)
        # Constellation onset trim: pre-truncate the clip to a short window so
        # dur_scale stays near 1.0 and there is no compression-ratio chirp.
        _onset_trim = row.pop("_onset_trim_sec", None)
        _frag_offset = row.pop("_frag_offset_sec", 0.0)
        clip = clips[row["src"]]
        if _frag_offset and _frag_offset > 0.0:
            _off_samps = min(len(clip) - 1, int(round(_frag_offset * sr)))
            clip = clip[_off_samps:]
        if _onset_trim is not None:
            _trim_samps = max(int(_row_floor), min(len(clip), int(round(_onset_trim * sr))))
            clip = clip[:_trim_samps]
        target_len = max(_row_floor, int(round(len(clip) * row["dur_scale"])))
        proc = _resample_linear(clip, target_len)
        if row["blur"] > 0.001:
            proc = _spectral_blur(proc, row["blur"])
        if row["res"] > 0.001:
            proc = _resonance_emphasis(proc, row["res"], sr)
        proc = _fade_clip(proc, sr)
        proc *= np.float32(row["gain"])
        s = max(0, int(round(row["start"] * sr)))
        e = min(n_out, s + len(proc))
        if proc.ndim == 1 and output.ndim == 1:
            output[s:e] += proc[:e - s]
        elif proc.ndim == 1 and output.ndim > 1:
            for ch in range(output.shape[1]):
                output[s:e, ch] += proc[:e - s]
        elif proc.ndim > 1 and output.ndim == 1:
            output[s:e] += np.mean(proc[:e - s], axis=1)
        else:
            output[s:e, :] += proc[:e - s, :]
    return output


def normalize_audio(x, ref_rms=None):
    import numpy as np
    x = x.astype(np.float32, copy=True)
    if x.size == 0:
        return x
    if ref_rms is not None and ref_rms > 1e-9:
        floor = float(ref_rms) * 0.01
        active_mask = np.abs(x) > floor
        if np.any(active_mask):
            active_rms = float(np.sqrt(np.mean(x[active_mask].astype(np.float64) ** 2)))
        else:
            active_rms = float(np.sqrt(np.mean(x.astype(np.float64) ** 2)))
        if active_rms > 1e-9:
            x *= float(ref_rms) / active_rms
    peak = float(np.max(np.abs(x)))
    if peak > 0.99:
        x *= 0.99 / peak
    return x


def write_stats(path, mode, preserve, intensity, duration_policy, variation, events, plan, in_dur, out_dur, rms_in=None, rms_out=None):
    with open(path, "w") as f:
        f.write("mode=%s\n" % mode)
        f.write("preserve_source=%.3f\n" % preserve)
        f.write("rewrite_intensity=%.3f\n" % intensity)
        f.write("duration_policy=%s\n" % duration_policy)
        f.write("variation=%.3f\n" % variation)
        f.write("n_events=%d\n" % len(events))
        f.write("n_plan_steps=%d\n" % len(plan))
        f.write("input_duration=%.4f\n" % in_dur)
        f.write("output_duration=%.4f\n" % out_dur)
        if rms_in is not None:
            f.write("rms_in=%.6f\n" % rms_in)
        if rms_out is not None:
            f.write("rms_out=%.6f\n" % rms_out)
        for i, ev in enumerate(events[:128]):
            f.write("ev_%d=%.4f,%.4f,%.4f\n" % (i, ev["start_time"], ev["end_time"], ev["strength"]))
        for i, row in enumerate(plan[:256]):
            f.write("pl_%d=%d,%.4f,%.4f,%.4f\n" % (i, row["src"], row["start"], row["dur_scale"], row["gain"]))


def cleanup(paths):
    for path in paths:
        if path and _is_praat_temp(path) and os.path.exists(path):
            try:
                os.remove(path)
            except OSError:
                pass


def main():
    import argparse
    import numpy as np
    import soundfile as sf

    parser = argparse.ArgumentParser(description="Phrase Rewriter engine")
    parser.add_argument("input_wav")
    parser.add_argument("features_csv")
    parser.add_argument("output_wav")
    parser.add_argument("stats_txt")
    parser.add_argument("mode")
    parser.add_argument("preserve_source", type=float)
    parser.add_argument("rewrite_intensity", type=float)
    parser.add_argument("duration_policy", choices=["keep", "shorter", "longer"])
    parser.add_argument("variation", type=float)
    parser.add_argument("seed", type=int)
    parser.add_argument("hop_sec", type=float)
    parser.add_argument("--cleanup", action="store_true")
    # Constellation-specific optional controls (neutral defaults; ignored by all other modes)
    parser.add_argument("--pitch_shift", type=float, default=0.0,
                        metavar="SEMITONES",
                        help="Pitch-shift Constellation fragments in semitones "
                             "(positive=up, negative=down; 0=off). "
                             "Uses varispeed resampling — duration scales proportionally.")
    parser.add_argument("--fragment_length", type=float, default=1.0,
                        metavar="SCALE",
                        help="Multiply Constellation fragment target duration "
                             "(1.0=default; 0.5=half as long; 2.0=twice as long).")
    args = parser.parse_args()

    check_dependencies()

    mode_map = {
        "constellation": "Constellation",
        "cloud": "Cloud",
        "resonance": "Resonance",
        "center": "Center",
        "becoming": "Becoming",
        "distance": "Distance",
        "mass": "Mass",
        "multiplication": "Multiplication",
    }
    mode = mode_map.get(args.mode.strip().lower(), "Constellation")
    preserve = max(0.0, min(1.0, args.preserve_source))
    intensity = max(0.0, min(1.0, args.rewrite_intensity))
    variation = max(0.0, min(1.0, args.variation))

    print("[Py 1/6] Loading audio + feature table...")
    audio, sr = sf.read(args.input_wav)
    if audio.ndim > 1 and audio.shape[1] == 1:
        audio = audio[:, 0]
    feats = load_praat_features(args.features_csv)

    print("[Py 2/6] Building phrase skeleton...")
    pf = build_phrase_features(feats)
    events = segment_events(audio if audio.ndim == 1 else np.mean(audio, axis=1), sr, pf, args.hop_sec)
    clips = extract_clips(audio, sr, events)

    print("[Py 3/6] Generating rewrite plan for mode: %s" % mode)

    # Constellation-only pre-processing: pitch-shift raw clips before planning/rendering.
    # Other modes receive the original clips unchanged.
    if mode == "Constellation" and abs(args.pitch_shift) >= 0.01:
        print("         pitch_shift=%.2f semitones (varispeed; <3st is subtle on speech)" % args.pitch_shift)
        clips = [_pitch_shift_clip(c, sr, args.pitch_shift) for c in clips]

    plan = generate_plan(events, mode, preserve, intensity, args.duration_policy, variation,
                         args.seed,
                         fragment_length_scale=args.fragment_length if mode == "Constellation" else 1.0)

    print("[Py 4/6] Rendering rewritten phrase...")
    output = render_plan(audio, sr, clips, events, plan)

    print("[Py 5/6] Normalizing + writing output...")
    # Use active-region RMS of the input as the normalization target.
    # Whole-buffer RMS is deflated by silence, which makes sparse outputs
    # (Constellation, Distance) end up quieter than the source.
    if audio.size:
        _whole_rms = float(np.sqrt(np.mean(audio.astype(np.float64) ** 2)))
        _floor = _whole_rms * 0.01
        _active_mask = np.abs(audio) > _floor
        if np.any(_active_mask):
            ref_rms = float(np.sqrt(np.mean(audio[_active_mask].astype(np.float64) ** 2)))
        else:
            ref_rms = _whole_rms
    else:
        ref_rms = None
    output = normalize_audio(output, ref_rms=ref_rms)
    sf.write(args.output_wav, output, sr)

    print("[Py 6/6] Writing stats...")
    def _active_rms(x, ref):
        floor = float(ref) * 0.01 if ref and ref > 1e-9 else 1e-5
        mask = np.abs(x) > floor
        return float(np.sqrt(np.mean(x[mask].astype(np.float64) ** 2))) if np.any(mask) else float(np.sqrt(np.mean(x.astype(np.float64) ** 2)))
    in_ref = float(np.sqrt(np.mean(audio.astype(np.float64) ** 2)))
    rms_in_val  = _active_rms(audio, in_ref)
    rms_out_val = _active_rms(output, in_ref)
    write_stats(args.stats_txt, mode, preserve, intensity, args.duration_policy, variation,
                events, plan, len(audio) / sr, len(output) / sr,
                rms_in=rms_in_val, rms_out=rms_out_val)

    if args.cleanup:
        cleanup([args.input_wav, args.features_csv])


if __name__ == "__main__":
    main()