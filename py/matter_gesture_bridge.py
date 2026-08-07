#!/usr/bin/env python3
# ============================================================
# Praat AudioTools - matter_gesture_bridge.py
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.4 (2026)
#
# Changelog v1.4 (2026) -- second-round review repairs:
#   - Gesture_amount is now a true MASTER: it scales selection
#     weights (as before) AND the pitch-motion fracture depth,
#     the formant-injection depth, and the amplitude
#     envelope+gate (gate blends open as amount -> 0). At
#     amount = 0 the render is a gesture-free Matter mosaic --
#     bit-identical across different gesture pitch/formant tracks
#     at the same seed (ablation-clean); only the DURATION still
#     comes from the gesture. Preset effective fracture/formant
#     depths shift by their amount factor.
#   - Cache key now includes the Matter file's size and mtime
#     (stale-cache bug: swapped content at the same path used to
#     replay the old render) and no longer includes the
#     continuity value (it never touched the library).
#   - "patch_sec" renamed "continuity_sec" (old key accepted):
#     a persistence SCALE, monotone but content-dependent; the
#     measured mean run is in stats.
#   - Top-level try/except: any unexpected error writes the
#     traceback to the log and "error" to the done-file
#     immediately (Praat no longer waits out its timeout).
#   - Single logging mechanism: when a log file is given,
#     messages go there only (Praat's stdout redirect was
#     double-writing every line).
#   - Stage numbering: [1/8] (one stray [1/7] remained).
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Matter Gesture Bridge — Stochastic Spectral Mosaicing
#   Python rendering engine. Called by MatterGestureBridge.praat.
#
#   What this actually is (v1.3, honest): a stochastic spectral-
#   mosaicing effect. Matter magnitude-spectrum STFT frames are
#   selected per output frame by the Gesture's RELATIVE intensity
#   contour, its TIME-VARYING spectral centroid (brightness), and
#   (when voiced) its normalized pitch; a continuity mechanism
#   walks coherent Matter runs whose average length is
#   Patch_length_sec. Selected spectra pass through spectral
#   granulation (per-cell log-normal gain), pitch-motion spectral
#   fracture (circular bin rotation driven by pitch change), and
#   CONTINUOUS formant-like resonance injection from the
#   Gesture's estimated F1-F4 trajectories. Phase is
#   reconstructed with Griffin-Lim; the Gesture's relative
#   amplitude envelope (with silence gate) is imposed last.
#   There is no diffusion model, no training, and no learned
#   prior; renders are seed-reproducible.
#
#   Pipeline:
#     1. Load audio (both sounds MONO-MIXED, resampled).
#     2. Read Praat descriptor tracks (intensity, pitch, F1-F4);
#        compute the Gesture's own STFT centroid track (same
#        frame grid as the output).
#     3. Build the Matter STFT frame library (mag, RMS, centroid).
#     4. Sequential gesture-driven frame selection with
#        continuity (memory O(M) per frame -- no all-to-all
#        matrix, long Matter files stay safe).
#     5. Spectral granulation -> pitch-motion fracture ->
#        continuous formant injection -> liminal freeze.
#     6. Griffin-Lim phase reconstruction.
#     7. Relative amplitude envelope + gate; normalize; write.
#
# Dependencies:
#   pip install numpy soundfile
#   Optional: pip install librosa, scipy (multithreaded FFT)
#
# Changelog v1.3 (2026) -- the honesty release (external review):
#   - FIX: pitch normalization min/max were REVERSED, so the
#     normalized pitch was almost always the constant 0.5 and the
#     advertised pitch->brightness frame selection never happened.
#     Now voiced-only min/max, correct order.
#   - Gesture BRIGHTNESS is now genuinely used: a time-varying
#     centroid track computed from the gesture's own STFT (same
#     mono mixdown, same frame grid) drives centroid matching;
#     voiced pitch adds a pull. Previously brightness was
#     diagnostic metadata only.
#   - Patch_length_sec is now REAL: continuity -- with
#     probability 1 - hop/patch_sec the selector continues from
#     the previous Matter frame's successor when that match is
#     acceptable, so patch length = average coherent Matter run.
#     This also replaces the all-to-all distance matrix with a
#     sequential O(M)-per-frame loop: the >1 GB memory blowup on
#     long Matter files is gone.
#   - Formant injection is CONTINUOUS (every frame, chunked
#     evaluation); the old stride touched only ~200 columns,
#     striping long outputs.
#   - "diffusion_steps" renamed gl_iterations (both keys
#     accepted): they are Griffin-Lim phase-reconstruction
#     iterations. "epochs" is gone (nothing ever trained).
#   - Stats now include warning=, sel_centroid_corr= (how well
#     selected Matter centroids track the target curve) and
#     mean_run_frames= (measured continuity).
#   - Stage numbering matches the pipeline (8 stages).
#   - RNG note: selection draws are now per-frame, so v1.3
#     renders differ from v1.2 at the same seed (still fully
#     reproducible within v1.3).
#
# Changelog v1.2:
#   - Vectorized the per-frame Python loops (the bottleneck) with identical
#     results, preserving exact RNG-stream consumption so output is reproducible:
#       * select_matter_frames : broadcast L1 distance + single argmin; jitter
#         drawn (n_frames, M) then transposed to keep the original draw order.
#       * apply_pitch_noise_schedule : one normal per active frame (same stream),
#         per-column circular shift done as a single gather.
#       * inject_formant_vectors : strided column updates vectorized.
#       * build_matter_library : batched STFT (sliding-window + one FFT).
#   - Griffin-Lim rewritten frame-major so every FFT runs on the contiguous
#     axis; overlap-add via R block-shifted adds; window normalization computed
#     once; optional scipy.fft (workers=-1) multithreads the batched FFTs.
#   - GL phasor projection (mag * S/|S|) replaces angle()->exp() per iteration
#     (the single largest cost). Differs from the original by <= 1 LSB at 16-bit;
#     set config "gl_phasor": 0 for byte-identical (slower) output.
# ============================================================

import argparse
import hashlib
import json
import os
import pickle
import sys
import traceback

import numpy as np
import soundfile as sf

try:
    import librosa
    HAS_LIBROSA = True
except ImportError:
    HAS_LIBROSA = False

try:
    import scipy.fft as _spfft
    def _rfft(x, axis=-1):
        return _spfft.rfft(x, axis=axis, workers=-1)
    def _irfft(x, n, axis=-1):
        return _spfft.irfft(x, n=n, axis=axis, workers=-1)
except ImportError:
    def _rfft(x, axis=-1):
        return np.fft.rfft(x, axis=axis)
    def _irfft(x, n, axis=-1):
        return np.fft.irfft(x, n=n, axis=axis)

N_FFT = 2048
HOP = N_FFT // 4


def check_dependencies():
    missing = []
    for pkg in ("numpy", "soundfile"):
        try:
            __import__(pkg)
        except ImportError:
            missing.append(pkg)
    if missing:
        raise RuntimeError("Missing required packages: " + ", ".join(missing))


def write_done(path, status="ok"):
    if not path:
        return
    try:
        with open(path, "w", encoding="utf-8") as f:
            f.write(status + "\n")
    except Exception:
        pass


def log(msg, path=""):
    if path:
        try:
            with open(path, "a", encoding="utf-8") as f:
                f.write(str(msg) + "\n")
            return
        except Exception:
            pass
    print(msg, flush=True)


def _resample(audio, sr_in, sr_out):
    if sr_in == sr_out:
        return audio.astype(np.float32, copy=False)
    if HAS_LIBROSA:
        return librosa.resample(audio.astype(np.float32), orig_sr=sr_in, target_sr=sr_out).astype(np.float32)
    new_len = max(1, int(round(len(audio) * sr_out / sr_in)))
    x = np.linspace(0, len(audio) - 1, new_len)
    lo = np.floor(x).astype(np.int64)
    hi = np.minimum(lo + 1, len(audio) - 1)
    frac = (x - lo).astype(np.float32)
    return (audio[lo] * (1 - frac) + audio[hi] * frac).astype(np.float32)


def load_audio(path, target_sr):
    audio, sr = sf.read(path, always_2d=True)
    mono = audio.mean(axis=1).astype(np.float32)
    return _resample(mono, int(sr), target_sr), target_sr


def load_matter_file(path, target_sr, limit_sec, log_file=""):
    audio, _ = load_audio(path, target_sr)
    limit = int(max(0.1, limit_sec) * target_sr)
    if len(audio) > limit:
        audio = audio[:limit]
        log(f"  Truncated Matter to {limit_sec:.1f}s", log_file)
    log(f"  Matter: {len(audio)/target_sr:.2f}s @ {target_sr} Hz", log_file)
    return audio


def _read_tsv(path):
    if not path or not os.path.isfile(path):
        return {}, 0
    with open(path, "r", encoding="utf-8") as f:
        lines = [ln.rstrip("\n\r") for ln in f if ln.strip()]
    if not lines:
        return {}, 0
    header = [x.strip().lower() for x in lines[0].split("\t")]
    cols = {h: [] for h in header}
    for line in lines[1:]:
        parts = line.split("\t")
        if len(parts) < len(header):
            continue
        ok = True
        vals = []
        for v in parts[:len(header)]:
            try:
                vals.append(float(v))
            except ValueError:
                ok = False
                break
        if not ok:
            continue
        for h, v in zip(header, vals):
            cols[h].append(v)
    out = {k: np.asarray(v, dtype=np.float32) for k, v in cols.items()}
    n = len(next(iter(out.values()))) if out else 0
    return out, n


def _fallback_intensity(gesture, target_sr):
    hop = max(1, target_sr // 100)
    n = max(1, len(gesture) // hop)
    x = gesture[:n * hop]
    if len(x) < n * hop:
        x = np.pad(x, (0, n * hop - len(x)))
    frames = x.reshape(n, hop)
    rms = np.sqrt(np.mean(frames * frames, axis=1) + 1e-12)
    return (20 * np.log10(rms + 1e-12)).astype(np.float32)


def extract_internal_gesture_controls(cfg, gesture, target_sr, log_file=""):
    int_tab, _ = _read_tsv(cfg.get("intensity_txt", ""))
    pitch_tab, _ = _read_tsv(cfg.get("pitch_txt", ""))
    frm_tab, nfrm = _read_tsv(cfg.get("formant_txt", ""))

    intensity = int_tab.get("intensity_db")
    if intensity is None or len(intensity) < 1:
        intensity = _fallback_intensity(gesture, target_sr)

    pitch = pitch_tab.get("pitch_hz")
    if pitch is None or len(pitch) < 1:
        pitch = np.zeros(len(intensity), dtype=np.float32)

    formants = {}
    for name in ("f1", "f2", "f3", "f4"):
        curve = frm_tab.get(name)
        if curve is None or len(curve) < 1:
            curve = np.zeros(max(1, len(intensity)), dtype=np.float32)
        formants[name] = curve.astype(np.float32)

    structural = frm_tab.get("valid")
    if structural is None or len(structural) < 1:
        structural = np.zeros(max(1, len(formants["f1"])), dtype=np.float32)
    structural = np.clip(structural, 0, 1).astype(np.float32)

    log(f"  Gesture controls: intensity={len(intensity)} pitch={len(pitch)} formant={nfrm}", log_file)
    return {
        "intensity_db": intensity,
        "pitch_hz": pitch,
        "formants": formants,
        "formant_structural_valid": structural,
        "brightness": float(cfg.get("gesture_brightness", 2000.0)),
        "mean_pitch": float(cfg.get("gesture_mean_pitch", 0.0)),
        "pitch_range": float(cfg.get("gesture_pitch_range", 0.0)),
        "int_mean": float(cfg.get("gesture_int_mean", 60.0)),
        "int_range": float(cfg.get("gesture_int_range", 20.0)),
    }


def interpolate_controls(curve, n_out):
    curve = np.asarray(curve, dtype=np.float32)
    if n_out <= 0:
        return np.zeros(0, dtype=np.float32)
    if len(curve) == 0:
        return np.zeros(n_out, dtype=np.float32)
    if len(curve) == n_out:
        return curve.copy()
    if len(curve) == 1:
        return np.full(n_out, curve[0], dtype=np.float32)
    return np.interp(np.linspace(0, 1, n_out), np.linspace(0, 1, len(curve)), curve).astype(np.float32)


def _frame_mag(audio):
    win = np.hanning(N_FFT).astype(np.float32)
    if len(audio) < N_FFT:
        chunk = np.pad(audio, (0, N_FFT - len(audio))) * win
        spec = np.abs(np.fft.rfft(chunk, n=N_FFT))[:, None]
        return spec.astype(np.float32)
    n = (len(audio) - N_FFT) // HOP + 1
    sw = np.lib.stride_tricks.sliding_window_view(audio, N_FFT)[::HOP][:n]
    return np.ascontiguousarray(np.abs(np.fft.rfft(sw * win[None, :], n=N_FFT, axis=1)).T).astype(np.float32)


def matter_hash(path, limit_sec, target_sr):
    try:
        sz = os.path.getsize(path)
        mt = int(os.path.getmtime(path))
    except OSError:
        sz, mt = -1, -1
    key = f"{path}|{sz}|{mt}|{limit_sec}|{target_sr}"
    return hashlib.md5(key.encode()).hexdigest()[:16]


def build_matter_library(matter, target_sr, log_file=""):
    mag = _frame_mag(matter)
    freqs = np.fft.rfftfreq(N_FFT, 1.0 / target_sr).astype(np.float32)
    rms = np.sqrt(np.mean(mag * mag, axis=0)) + 1e-8
    total = mag.sum(axis=0) + 1e-8
    centroid = (freqs[:, None] * mag).sum(axis=0) / total
    log(f"  Matter library: {mag.shape[1]} frames", log_file)
    return {"mag": mag, "rms": rms.astype(np.float32), "centroid": centroid.astype(np.float32), "freqs": freqs}


def load_or_build_library(matter, cfg, cache_dir, log_file=""):
    sr = int(cfg.get("target_sr", 44100))
    reuse = int(cfg.get("reuse_cache", 0))
    h = matter_hash(cfg.get("matter_wav", ""), float(cfg.get("train_limit_sec", 420)), sr)
    path = os.path.join(cache_dir, f"mgb_lib_{h}.pkl")
    if reuse and os.path.isfile(path):
        try:
            with open(path, "rb") as f:
                lib = pickle.load(f)
            lib["cache_hit"] = True
            return lib
        except Exception as exc:
            log(f"  Cache load failed: {exc}", log_file)
    lib = build_matter_library(matter, sr, log_file)
    lib["cache_hit"] = False
    try:
        os.makedirs(cache_dir, exist_ok=True)
        with open(path, "wb") as f:
            pickle.dump(lib, f)
    except Exception as exc:
        log(f"  Cache write skipped: {exc}", log_file)
    return lib


def gesture_centroid_track(gesture, target_sr, n_frames):
    mag = _frame_mag(gesture)
    freqs = np.fft.rfftfreq(N_FFT, 1.0 / target_sr).astype(np.float32)
    cen = (freqs[:, None] * mag).sum(axis=0) / (mag.sum(axis=0) + 1e-8)
    return interpolate_controls(cen, n_frames)


def build_gesture_conditioning(controls, n_frames, cfg):
    amount = float(cfg.get("gesture_amount", 0.65))
    int_db = interpolate_controls(controls["intensity_db"], n_frames)
    pitch = interpolate_controls(controls["pitch_hz"], n_frames)
    formants = {k: interpolate_controls(controls["formants"][k], n_frames) for k in ("f1", "f2", "f3", "f4")}
    structural = interpolate_controls(controls["formant_structural_valid"], n_frames)
    structural = (structural >= 0.5).astype(np.float32)
    lo, hi = float(int_db.min()), float(int_db.max())
    int_norm = (int_db - lo) / (hi - lo) if hi > lo else np.full(n_frames, 0.5, dtype=np.float32)
    int_norm = np.clip(0.5 + (int_norm - 0.5) * amount, 0, 1).astype(np.float32)
    amp = 10 ** ((int_db - float(int_db.max())) / 20.0)
    amp = np.clip(amp, 0.02, 1).astype(np.float32)
    return {
        "intensity_norm": int_norm,
        "amp_env": amp,
        "pitch_hz": pitch,
        "brightness_hz": interpolate_controls(controls.get("brightness_track", np.full(n_frames, 2000)), n_frames),
        "formant_structural_valid": structural,
        **formants,
    }


def _moving_average_freq(mag, width=9):
    width = max(3, int(width) | 1)
    pad = width // 2
    p = np.pad(mag, ((pad, pad), (0, 0)), mode="edge")
    cs = np.vstack([np.zeros((1, p.shape[1]), dtype=np.float32), np.cumsum(p, axis=0, dtype=np.float64)]).astype(np.float64)
    sm = (cs[width:] - cs[:-width]) / width
    return sm.astype(np.float32)


def compute_formant_confidence(gesture, cond, target_sr, n_frames, log_file=""):
    structural = cond["formant_structural_valid"] > 0.5
    if not np.any(structural):
        log("  Formant evidence: none structurally valid", log_file)
        return np.zeros(n_frames, np.float32), 0.0, 0.0

    mag = interpolate_spectrogram_frames(_frame_mag(gesture), n_frames)
    # Spectral flatness guards against Burg choosing plausible-looking poles
    # inside genuinely flat broadband noise. Resonant noise remains eligible.
    mag_eps = mag + 1e-12
    flatness = np.exp(np.mean(np.log(mag_eps), axis=0)) / (np.mean(mag_eps, axis=0) + 1e-12)
    flatness = np.clip(flatness, 0.0, 1.0).astype(np.float32)
    flat_score = np.clip((0.78 - flatness) / 0.18, 0.0, 1.0).astype(np.float32)
    med_flatness = float(np.median(flatness[structural])) if np.any(structural) else 1.0
    bin_hz = target_sr / N_FFT
    # Smooth by a fixed width in HERTZ, not bins: stable across sample rates
    # and wide enough to suppress individual harmonic teeth while retaining
    # broad vowel/resonance-envelope peaks.
    smooth_bins = max(3, int(round(240.0 / bin_hz)))
    if smooth_bins % 2 == 0:
        smooth_bins += 1
    env = _moving_average_freq(mag, smooth_bins)
    frame_idx = np.arange(n_frames)
    frame_mean = env.mean(axis=0) + 1e-8
    contrasts = {}
    prominence = {}
    bws = {"f1": 120.0, "f2": 200.0, "f3": 300.0, "f4": 400.0}
    nyq = target_sr / 2.0
    for name in ("f1", "f2", "f3", "f4"):
        f = cond[name]
        center = np.clip(np.rint(f / bin_hz).astype(np.int64), 0, env.shape[0] - 1)
        off = max(2, int(round(1.25 * bws[name] / bin_hz)))
        left = np.clip(center - off, 0, env.shape[0] - 1)
        right = np.clip(center + off, 0, env.shape[0] - 1)
        c = env[center, frame_idx]
        shoulder = np.sqrt((env[left, frame_idx] + 1e-8) * (env[right, frame_idx] + 1e-8))
        db = 20 * np.log10((c + 1e-8) / (shoulder + 1e-8))
        lev = 20 * np.log10((c + 1e-8) / frame_mean)
        freq_ok = (f >= 80) & (f <= nyq - 100)
        contrasts[name] = np.where(freq_ok, db, -40.0)
        prominence[name] = np.where(freq_ok, lev, -80.0)

    combined = 0.55 * contrasts["f2"] + 0.45 * contrasts["f3"]
    # A narrow tone can produce arbitrary ratios near the numerical floor.
    # Require the F2/F3 regions to carry real spectral energy as well as
    # local peak contrast. White noise passes the energy test but fails
    # contrast; a sine away from F2/F3 fails the energy test decisively.
    min_prom = np.minimum(prominence["f2"], prominence["f3"])
    contrast_score = np.clip((combined - 0.5) / 2.0, 0.0, 1.0)
    prominence_score = np.clip((min_prom + 6.0) / 6.0, 0.0, 1.0)
    local = (contrast_score * prominence_score * flat_score * structural.astype(np.float32)).astype(np.float32)
    valid_fraction = float(np.mean(local >= 0.15))
    med_contrast = float(np.median(combined[structural])) if np.any(structural) else 0.0
    med_prom = float(np.median(min_prom[structural])) if np.any(structural) else -80.0
    if valid_fraction < 0.15 or med_contrast < 0.50 or med_prom < -6.0 or med_flatness > 0.72:
        local[:] = 0
        log(f"  Formant evidence LOW: active={100*valid_fraction:.1f}% median contrast={med_contrast:.2f} dB prominence={med_prom:.2f} dB flatness={med_flatness:.3f}", log_file)
        return local, valid_fraction, med_contrast
    log(f"  Formant evidence OK: active={100*valid_fraction:.1f}% median contrast={med_contrast:.2f} dB prominence={med_prom:.2f} dB flatness={med_flatness:.3f}", log_file)
    return local, valid_fraction, med_contrast


def interpolate_spectrogram_frames(mag, n_out):
    if mag.shape[1] == n_out:
        return mag
    if mag.shape[1] == 1:
        return np.repeat(mag, n_out, axis=1)
    xin = np.linspace(0, 1, mag.shape[1])
    xout = np.linspace(0, 1, n_out)
    out = np.empty((mag.shape[0], n_out), dtype=np.float32)
    for k in range(mag.shape[0]):
        out[k] = np.interp(xout, xin, mag[k])
    return out


def select_matter_frames(lib, cond, cfg, n_frames, rng, log_file=""):
    chaos = float(cfg.get("chaos", 0.50))
    amount = float(cfg.get("gesture_amount", 0.65))
    continuity = float(cfg.get("continuity_sec", cfg.get("patch_sec", 1.5)))
    sr = int(cfg.get("target_sr", 44100))
    matter_rms, matter_cen, matter_mag = lib["rms"], lib["centroid"], lib["mag"]
    M = matter_mag.shape[1]
    int_norm = cond["intensity_norm"]
    pitch = cond["pitch_hz"]
    bright = cond["brightness_hz"]
    rmin, rmax = float(matter_rms.min()), float(matter_rms.max())
    cmin, cmax = float(matter_cen.min()), float(matter_cen.max())
    target_rms = rmin + int_norm * (rmax - rmin)
    voiced = pitch > 50
    pv = pitch[voiced]
    if len(pv) > 1 and pv.max() > pv.min():
        pnorm = np.clip((pitch - pv.min()) / (pv.max() - pv.min() + 1e-8), 0, 1)
    else:
        pnorm = np.full(n_frames, 0.5, np.float32)
    if float(bright.max()) > float(bright.min()):
        bnorm = (bright - bright.min()) / (bright.max() - bright.min())
    else:
        bnorm = np.full(n_frames, 0.5, np.float32)
    tcnorm = np.where(voiced, 0.5 * (bnorm + pnorm), bnorm)
    target_cen = cmin + tcnorm * (cmax - cmin)
    nrms = (matter_rms - rmin) / (rmax - rmin + 1e-8)
    ncen = (matter_cen - cmin) / (cmax - cmin + 1e-8)
    tr = (target_rms - rmin) / (rmax - rmin + 1e-8)
    tc = (target_cen - cmin) / (cmax - cmin + 1e-8)
    wr, wc = amount, amount * 0.5
    hop_dur = HOP / sr
    p_stay = max(0.0, 1.0 - hop_dur / max(hop_dur, continuity))
    tol = (0.15 + 0.10 * min(continuity, 4.0)) * (wr + wc) + 0.05
    best = np.zeros(n_frames, np.int64)
    prev = -1
    run_len = 0
    runs = []
    for i in range(n_frames):
        d = wr * np.abs(nrms - tr[i]) + wc * np.abs(ncen - tc[i])
        d = d + rng.uniform(0, chaos * 0.3, size=M).astype(np.float32)
        dmin = float(d.min())
        cont = prev + 1
        if prev >= 0 and cont < M and rng.uniform() < p_stay and float(d[cont]) <= dmin + tol:
            choice = cont
            run_len += 1
        else:
            choice = int(np.argmin(d))
            if run_len:
                runs.append(run_len)
            run_len = 1
        best[i] = choice
        prev = choice
    if run_len:
        runs.append(run_len)
    sel = matter_mag[:, best].astype(np.float32)
    sel_cen = matter_cen[best]
    corr = float(np.corrcoef(sel_cen, target_cen)[0, 1]) if np.std(sel_cen) > 1e-6 and np.std(target_cen) > 1e-6 else 0.0
    mean_run = float(np.mean(runs)) if runs else float(n_frames)
    log(f"  Frame selection: {n_frames} from {M}, run={mean_run:.1f}, centroid r={corr:.3f}", log_file)
    return sel, mean_run, corr


def _smooth(x, w=5):
    if w < 2 or len(x) <= w:
        return x
    return np.convolve(x, np.ones(w, np.float32) / w, mode="same")


def apply_intensity_roughness(mag, cond, cfg, rng):
    rough = float(cfg.get("intensity_roughness", 0.75))
    std = rough * cond["intensity_norm"] * 0.4
    return mag * np.exp(rng.standard_normal(mag.shape).astype(np.float32) * std[None, :])


def apply_pitch_noise_schedule(mag, cond, cfg, target_sr, rng):
    depth = float(cfg.get("pitch_noise", 0.55)) * float(cfg.get("gesture_amount", 0.65))
    p = cond["pitch_hz"]
    vel = _smooth(np.abs(np.diff(p, prepend=p[0])) / (np.mean(np.abs(p)) + 1e-6), 5)
    vel = np.clip(vel * depth, 0, 1)
    active = vel >= 0.01
    shifts = np.zeros(mag.shape[1], np.int64)
    if np.any(active):
        shifts[active] = np.rint(rng.standard_normal(int(active.sum())) * vel[active] * mag.shape[0] * 0.04).astype(np.int64)
    rows = (np.arange(mag.shape[0])[:, None] - shifts[None, :]) % mag.shape[0]
    return mag[rows, np.arange(mag.shape[1])[None, :]]


def inject_formant_vectors(mag, cond, cfg, target_sr):
    depth = float(cfg.get("formant_injection", 0.45)) * float(cfg.get("gesture_amount", 0.65))
    confidence = np.asarray(cond.get("formant_confidence", np.zeros(mag.shape[1])), dtype=np.float32)
    if depth < 1e-4 or not np.any(confidence > 0):
        return mag
    freqs = np.fft.rfftfreq(N_FFT, 1.0 / target_sr).astype(np.float32)
    bws = {"f1": 120.0, "f2": 200.0, "f3": 300.0, "f4": 400.0}
    chunk = 4096
    for name, bw in bws.items():
        fcurve = cond[name]
        freq_valid = ((fcurve >= 80) & (fcurve <= target_sr / 2 - 100)).astype(np.float32)
        weight = confidence * freq_valid
        for c0 in range(0, mag.shape[1], chunk):
            c1 = min(c0 + chunk, mag.shape[1])
            if not np.any(weight[c0:c1] > 0):
                continue
            col_mean = mag[:, c0:c1].mean(axis=0)
            boost = np.exp(-0.5 * ((freqs[:, None] - fcurve[None, c0:c1]) / bw) ** 2).astype(np.float32)
            mag[:, c0:c1] += depth * boost * col_mean[None, :] * weight[None, c0:c1]
    return mag


def apply_liminal_freeze(mag, lib, cfg, rng):
    freeze = float(cfg.get("freeze_t", 0.45))
    chaos = float(cfg.get("chaos", 0.50))
    crystal = np.repeat(lib["mag"].mean(axis=1)[:, None], mag.shape[1], axis=1).astype(np.float32)
    if freeze < 0.05:
        return crystal * 0.9 + mag * 0.1
    ghost = np.exp(rng.standard_normal(mag.shape).astype(np.float32) * freeze * chaos * 0.8)
    return np.clip(crystal * (1 - freeze) + mag * ghost * freeze, 0, None)


def apply_amplitude_envelope(audio, cond, cfg, target_sr):
    amount = float(cfg.get("gesture_amount", 0.65))
    amp = interpolate_controls(cond["amp_env"], len(audio))
    amp = _smooth(amp, max(3, target_sr // 200))
    gate = (amp > float(cfg.get("gate_threshold", 0.02))).astype(np.float32)
    fade_smp = max(2, int(target_sr * 0.005))
    fade = np.hanning(fade_smp * 2).astype(np.float32)
    gate = np.clip(np.convolve(gate, fade / fade.sum(), mode="same"), 0, 1)
    env = amp * amount + (1 - amount)
    gate_eff = gate * amount + (1 - amount)
    return (audio * env * gate_eff).astype(np.float32)


def griffin_lim(mag, n_iter, seed, log_file="", use_phasor=True):
    n_freq, n_frames = mag.shape
    win = np.hanning(N_FFT).astype(np.float64)
    R = N_FFT // HOP
    out_len = (n_frames - 1) * HOP + N_FFT
    rng = np.random.default_rng(seed + 99)
    phasor = np.exp(1j * rng.uniform(-np.pi, np.pi, (n_frames, n_freq)))
    mag_t = np.ascontiguousarray(mag.astype(np.float64).T)
    n_blocks = n_frames + R - 1
    winsq_b = (win ** 2).reshape(R, HOP)
    wblocks = np.zeros((n_blocks, HOP), np.float64)
    for b in range(R):
        wblocks[b:b+n_frames] += winsq_b[b][None, :]
    wnorm = wblocks.reshape(-1)[:out_len]
    wnorm = np.where(wnorm > 1e-10, wnorm, 1.0)

    def istft(stft):
        td = _irfft(stft, n=N_FFT, axis=1) * win[None, :]
        tdb = td.reshape(n_frames, R, HOP)
        blocks = np.zeros((n_blocks, HOP), np.float64)
        for b in range(R):
            blocks[b:b+n_frames] += tdb[:, b, :]
        return blocks.reshape(-1)[:out_len] / wnorm

    log(f"  Griffin-Lim: {n_iter} iterations", log_file)
    for _ in range(max(1, int(n_iter))):
        y = istft(mag_t * phasor)
        frames = np.lib.stride_tricks.sliding_window_view(y, N_FFT)[::HOP]
        spec = _rfft(frames * win[None, :], axis=1)
        phasor = spec / (np.abs(spec) + 1e-12) if use_phasor else np.exp(1j * np.angle(spec))
    audio = istft(mag_t * phasor).astype(np.float32)
    fl = min(N_FFT, len(audio) // 2)
    if fl > 1:
        fade = np.hanning(2 * fl).astype(np.float32)
        audio[:fl] *= fade[:fl]
        audio[-fl:] *= fade[fl:]
    return audio


def safe_normalize(audio, peak=0.92):
    p = float(np.max(np.abs(audio))) if len(audio) else 0.0
    return (audio * (peak / p)).astype(np.float32) if p > 1e-8 else audio.astype(np.float32)


def main():
    check_dependencies()
    ap = argparse.ArgumentParser(description="Matter Gesture Bridge v1.4")
    ap.add_argument("config_json")
    args = ap.parse_args()
    with open(args.config_json, "r", encoding="utf-8") as f:
        cfg = json.load(f)

    matter_wav = cfg.get("matter_wav", "")
    gesture_wav = cfg.get("gesture_wav", "")
    result_wav = cfg.get("result_wav", "")
    log_file = cfg.get("log_file", "")
    done_file = cfg.get("done_file", "")
    stats_file = cfg.get("stats_file", "")
    sr = int(cfg.get("target_sr", 44100))
    seed = int(cfg.get("seed", 1234))
    # The Praat wrapper deletes stale temp logs before launch.
    # Do not truncate here: on Windows a launcher/redirection handle can make
    # a second mode="w" open fail with PermissionError. log() appends/creates.
    for label, path in (("Matter", matter_wav), ("Gesture", gesture_wav)):
        if not path or not os.path.isfile(path):
            raise FileNotFoundError(f"{label} file not found: {path}")

    log("=== Matter Gesture Bridge v1.4 ===", log_file)
    rng = np.random.default_rng(seed)
    matter = load_matter_file(matter_wav, sr, float(cfg.get("train_limit_sec", 420)), log_file)
    gesture, _ = load_audio(gesture_wav, sr)
    controls = extract_internal_gesture_controls(cfg, gesture, sr, log_file)
    cache_dir = os.path.dirname(log_file) if log_file else os.path.dirname(result_wav)
    lib = load_or_build_library(matter, cfg, cache_dir, log_file)
    gesture_samples = len(gesture)
    n_frames = max(4, (gesture_samples - N_FFT) // HOP + 1)
    controls["brightness_track"] = gesture_centroid_track(gesture, sr, n_frames)
    cond = build_gesture_conditioning(controls, n_frames, cfg)
    confidence, valid_frac, med_contrast = compute_formant_confidence(gesture, cond, sr, n_frames, log_file)
    cond["formant_confidence"] = confidence

    mag, mean_run, cen_corr = select_matter_frames(lib, cond, cfg, n_frames, rng, log_file)
    mag = apply_intensity_roughness(mag, cond, cfg, rng)
    mag = apply_pitch_noise_schedule(mag, cond, cfg, sr, rng)
    mag = inject_formant_vectors(mag, cond, cfg, sr)
    mag = apply_liminal_freeze(mag, lib, cfg, rng)
    mag = np.clip(mag, 0, None)
    iters = int(cfg.get("gl_iterations", cfg.get("diffusion_steps", 64)))
    audio = griffin_lim(mag, iters, seed, log_file, bool(int(cfg.get("gl_phasor", 1))))
    if len(audio) > gesture_samples:
        audio = audio[:gesture_samples]
    elif len(audio) < gesture_samples:
        audio = np.pad(audio, (0, gesture_samples - len(audio)))
    audio = apply_amplitude_envelope(audio, cond, cfg, sr)
    audio = safe_normalize(audio, 0.92)
    sf.write(result_wav, audio, sr, subtype="PCM_16")

    if stats_file:
        voiced = controls["pitch_hz"][controls["pitch_hz"] > 10]
        warnings = []
        if len(voiced) == 0:
            warnings.append("no voiced pitch in gesture")
        if valid_frac < 0.15 or med_contrast < 0.50:
            warnings.append("formant injection disabled: no reliable resonance envelope")
        if lib["mag"].shape[1] < 8:
            warnings.append("very short Matter file")
        if cen_corr < 0.2:
            warnings.append("weak centroid tracking")
        with open(stats_file, "w", encoding="utf-8") as f:
            f.write(f"gesture_dur={len(gesture)/sr:.4f}\n")
            f.write(f"result_dur={len(audio)/sr:.4f}\n")
            f.write(f"n_frames={n_frames}\n")
            f.write(f"peak={np.max(np.abs(audio)):.4f}\n")
            f.write(f"rms_out={np.sqrt(np.mean(audio**2)):.4f}\n")
            f.write(f"freeze_t={float(cfg.get('freeze_t',0.45)):.4f}\n")
            f.write(f"chaos={float(cfg.get('chaos',0.50)):.4f}\n")
            f.write(f"gesture_amount={float(cfg.get('gesture_amount',0.65)):.4f}\n")
            f.write(f"seed={seed}\n")
            f.write(f"gl_iters={iters}\n")
            f.write(f"matter_file={os.path.basename(matter_wav)}\n")
            f.write(f"cache_hit={'yes' if lib.get('cache_hit') else 'no'}\n")
            ic = controls["intensity_db"]
            f.write(f"int_mean={float(ic.mean()):.2f}\n")
            f.write(f"int_range={float(ic.max()-ic.min()):.2f}\n")
            f.write(f"pitch_mean={float(voiced.mean()) if len(voiced) else 0.0:.2f}\n")
            f.write(f"pitch_range={float(voiced.max()-voiced.min()) if len(voiced)>1 else 0.0:.2f}\n")
            f.write(f"brightness={float(cfg.get('gesture_brightness',2000.0)):.1f}\n")
            f.write(f"sel_centroid_corr={cen_corr:.3f}\n")
            f.write(f"mean_run_frames={mean_run:.1f}\n")
            f.write(f"formant_valid_fraction={valid_frac:.4f}\n")
            f.write(f"formant_contrast_db={med_contrast:.3f}\n")
            f.write(f"formant_injection_active={'yes' if np.any(confidence>0) else 'no'}\n")
            f.write("warning=" + "; ".join(warnings) + "\n")
    write_done(done_file, "ok")
    log("=== Matter Gesture Bridge complete ===", log_file)


def main_guarded():
    cfg_path = sys.argv[1] if len(sys.argv) > 1 else ""
    log_file = done_file = ""
    try:
        if cfg_path and os.path.isfile(cfg_path):
            with open(cfg_path, "r", encoding="utf-8") as f:
                pre = json.load(f)
            log_file = pre.get("log_file", "")
            done_file = pre.get("done_file", "")
        main()
    except SystemExit:
        raise
    except BaseException:
        log("FATAL: unhandled exception\n" + traceback.format_exc(), log_file)
        write_done(done_file, "error")
        sys.exit(1)


if __name__ == "__main__":
    main_guarded()
