#!/usr/bin/env python3
"""NMF Granular Spatial Composer v1.1 -- unified engine (Praat AudioTools, Hybrid Systems).

Author: Shai Cohen, Department of Music, Bar-Ilan University, Israel
License: MIT -- https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools

One input sound -> NMF corpus (8 sources) -> time-local Poisson granular cloud
-> original amplitude envelope -> mono / stereo / quadraphonic compositions.

This engine CONSOLIDATES three approved experiments and reuses their code:
  [LAB]  nmf_python_lab.py            STFT + scikit-learn CD NMF, component
                                      masks, Griffin-Lim, cross-routing,
                                      spectral sculpture, spectral portrait,
                                      audition normalisation
  [ENV]  nmf_granular_envelope_poc.py local Poisson grains, envelope
                                      extraction / imposition, audition gain
  [SPA]  nmf_granular_spatial_poc.py  make_grains / render / stereo and quad
                                      gain policies / level_match / statistics
Functions copied from those files are marked with their origin tag and are
kept textually identical in their numerical statements. Two structural
changes only, both verified bit-identical by test_nmf_granular_spatial.py:
  1. The prototypes exchanged audio as files: every corpus signal (and the
     source reference) was audition-normalised, written as 16-bit PCM WAV and
     read back as float64; the spatial stage level-matched to the 16-bit mono
     file. That exact round trip is done in memory here (pcm_roundtrip), with
     the same library (libsndfile via soundfile), so no corpus files exist.
  2. Grain events are stored as their parameters and each grain is recomputed
     with the identical expressions at render time (memory: 3 min of sound
     would otherwise hold ~0.4 GB of grain arrays). Scheduling and the order
     of random draws are unchanged.

v1.1 (engine): exports drawing data for the Praat figure (viz_*.tsv): every
grain's onset, slot, length, read position and speed, and its spatial
position RECORDED DURING THE RENDER (the gain functions log the pan / angle
they used; no random draw is added or reordered); measured RMS curves of the
source, the imposed envelope and every output (per quad speaker too). Real
NMF component numbers label the three solo slots. --release turns a work
folder the user wants to keep into a kept folder that no cleanup touches.
--preset-label records the Praat preset name. Reference output unchanged
(bit-identical, see the tests).

Run `python nmf_granular_spatial_composer.py --help` for the command line.
"""
from __future__ import annotations

import argparse
import io
import json
import math
import os
import platform
import shutil
import struct
import sys
import time
import traceback
import warnings
from pathlib import Path

ENGINE_NAME = "NMF Granular Spatial Composer"
ENGINE_VERSION = "1.1.0"

# ---------------------------------------------------------------- dependencies
_MISSING = []
try:
    import numpy as np
except Exception:  # pragma: no cover
    _MISSING.append("numpy")
try:
    import scipy
    import scipy.ndimage as ndi
    from scipy.ndimage import gaussian_filter1d, uniform_filter1d
except Exception:  # pragma: no cover
    _MISSING.append("scipy")
try:
    import soundfile as sf
except Exception:  # pragma: no cover
    _MISSING.append("soundfile")
try:
    import librosa
except Exception:  # pragma: no cover
    _MISSING.append("librosa")
try:
    import sklearn
    from sklearn.decomposition import NMF
except Exception:  # pragma: no cover
    _MISSING.append("scikit-learn")


class EngineError(Exception):
    """A controlled, user-facing failure (bad input or parameters)."""


# ------------------------------------------------------------ reference mode
# The approved Hebrew experiment (K12). Analysis settings are not exposed to
# the user in v1.0; they form the documented Reference mode.
REFERENCE = {
    "sr": 16000, "n_fft": 1024, "hop": 256, "components": 12,
    "nmf_max_iter": 160, "gl_iterations": 20, "nmf_seed": 20261028,
    "grain_seed": 20261029, "density": 93.0, "grain_ms": (65.0, 140.0),
    "speed": (0.92, 1.08), "segment_s": 0.26,
    "seed_islands": 30701, "seed_orbit": 30702, "seed_quad": 30703,
}
CORPUS_NAMES = [
    "01_component_01", "01_component_06", "01_component_09",
    "02_neutral_griffinlim", "03_crossroute_originalphase",
    "04_crossroute_griffinlim", "05_spectral_sculpture", "06_spectral_portrait",
]
MIN_SECONDS = 1.0
MAX_SECONDS = 600.0
MODES = ("mono", "islands", "orbit", "quad")
QUAD_CHANNEL_ORDER = ("FL", "FR", "BL", "BR")
QUAD_CHANNEL_MASK = 0x1 | 0x2 | 0x10 | 0x20   # SPEAKER_FRONT_LEFT|RIGHT|BACK_LEFT|RIGHT
WORKDIR_PREFIX = "NMF_GSC_work_"
WORKDIR_MARKER = "NMF_GSC_WORKDIR.txt"
WORKDIR_LEDGER = "NMF_GSC_owned_files.txt"


# =================================================================== helpers
def rms(x):  # [LAB]/[ENV]/[SPA] -- identical numerics in all three
    return float(np.sqrt(np.mean(np.square(np.asarray(x, dtype=np.float64)))))


def pcm_roundtrip(x, sr, subtype="PCM_16"):
    """What the prototypes did through files, in memory: write WAV, read float64."""
    buf = io.BytesIO()
    sf.write(buf, x, sr, subtype=subtype, format="WAV")
    buf.seek(0)
    y, rate = sf.read(buf, dtype="float64")
    assert rate == sr
    return y


# ============================================================ [LAB] NMF stage
def normalize_for_audition(signal, target_rms, sr):  # [LAB]
    """Match overall level for A/B comparisons; retain dynamics and silence."""
    x = np.asarray(signal, dtype=np.float64).copy()
    x[~np.isfinite(x)] = 0.0
    if rms(x) > 1e-10:
        gain = min(target_rms / rms(x), .96 / max(float(np.max(np.abs(x))), 1e-10))
        x *= gain
    fade = min(int(sr * .025), len(x)//2)
    if fade:
        x[:fade] *= np.linspace(0, 1, fade)
        x[-fade:] *= np.linspace(1, 0, fade)
    return x.astype(np.float32)


def phase_aware_from_magnitude(S_original, target_magnitude, hop, out_len):  # [LAB]
    return librosa.istft(target_magnitude * np.exp(1j * np.angle(S_original)),
                         hop_length=hop, length=out_len)


def _gl_seed_kwargs(seed):
    """librosa <= 0.11 turned an int random_state into np.random.RandomState(seed);
    librosa 1.0 renamed the argument to rng and turns an int into
    np.random.default_rng(seed) -- a different random stream, hence different
    Griffin-Lim phases. Passing an explicit RandomState reproduces the
    reference behaviour on every version (both accept a RandomState object)."""
    import inspect
    state = np.random.RandomState(seed)
    params = inspect.signature(librosa.griffinlim).parameters
    return {"rng": state} if "rng" in params else {"random_state": state}


def phase_reconstruct(target_magnitude, hop, out_len, n_iter, seed):  # [LAB]
    return librosa.griffinlim(np.maximum(target_magnitude, 0.0),
                              n_iter=n_iter, hop_length=hop,
                              momentum=.95, init='random',
                              length=out_len, **_gl_seed_kwargs(seed))


def spectral_stretch(W, factor):  # [LAB]
    """Warp frequencies of each NMF spectral profile around DC."""
    bins = np.arange(W.shape[0])
    out = np.empty_like(W)
    for k in range(W.shape[1]):
        col = np.interp(bins / factor, bins, W[:, k], left=0.0, right=0.0)
        out[:, k] = col * (W[:, k].sum() / max(col.sum(), 1e-12))
    return out


def load_input(path, sr, seed):
    """[LAB] main(): global seed first, then librosa mono load at the analysis rate."""
    np.random.seed(seed)
    try:
        y, sr_out = librosa.load(path, sr=sr, mono=True)
    except Exception as e:
        raise EngineError(f"Could not decode the input audio ({type(e).__name__}: {e or 'unreadable file'}).")
    return y, sr_out


def nmf_decompose(y, sr, n_fft, hop, components, iterations, seed):
    """[LAB] STFT and magnitude NMF, scikit-learn CD / Frobenius / NNDSVDA."""
    S = librosa.stft(y, n_fft=n_fft, hop_length=hop, window='hann')
    M = np.abs(S)
    scale = max(float(M.max()), 1e-12)
    X = (M / scale).T   # samples=time, features=frequency
    model = NMF(n_components=components, init='nndsvda', solver='cd',
                beta_loss='frobenius', max_iter=iterations,
                random_state=seed, tol=1e-4)
    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter('always')
        A = model.fit_transform(X)  # (time, k), nonnegative activation
        B = model.components_       # (k, freq), nonnegative spectral bases
    H = A.T.astype(np.float64)      # k x time
    W = (B.T * scale).astype(np.float64)  # freq x k, original magnitude units
    predicted = W @ H
    reconstruction_error = float(np.linalg.norm(M - predicted) / max(np.linalg.norm(M), 1e-12))
    energy = np.sum(H, axis=1) * np.sum(W, axis=0)
    order = np.argsort(-energy)
    return {"S": S, "M": M, "W": W, "H": H, "predicted": predicted,
            "order": order, "k": components, "hop": hop, "n_fft": n_fft,
            "reconstruction_error": reconstruction_error,
            "nmf_iterations": int(model.n_iter_),
            "warnings": [str(w.message) for w in caught]}


def generate_corpus(y, sr, dec, gl_iterations, seed):
    """[LAB] main() from the source save onward, returning in-memory audio.

    Each 'save' is normalize_for_audition followed by the 16-bit WAV round
    trip, exactly what the granular prototypes read back from disk. Returns
    the source reference (00_source_mono) and the 8 corpus slots in the
    order the prototypes loaded them: the three strongest components in
    ASCENDING component index (the files sorted by name), then the five
    transformation sources.
    """
    S, M, W, H = dec["S"], dec["M"], dec["W"], dec["H"]
    predicted, order, k, hop = dec["predicted"], dec["order"], dec["k"], dec["hop"]
    target_rms = rms(y)
    info = {}

    def save(stem, samples):
        wav = normalize_for_audition(samples, target_rms, sr)
        info[stem] = {"rms": round(rms(wav), 6), "peak": round(float(np.max(np.abs(wav))), 6)}
        return pcm_roundtrip(wav, sr, "PCM_16")

    source_mono = save('00_source_mono', y)

    # Component solos: soft spectral masks applied to the actual complex STFT.
    power = 1.35
    component_recon = [np.maximum(W[:, i:i+1] * H[i:i+1, :], 0) ** power
                       for i in range(k)]
    denom = np.sum(component_recon, axis=0)
    comp_mags = [np.divide(c, denom, out=np.full_like(c, 1.0/k),
                           where=denom > 1e-30) for c in component_recon]
    sum_mask_error = float(np.max(np.abs(np.sum(comp_mags, axis=0) - 1.0)))
    solos = {}
    for rank in range(min(3, k)):
        idx = int(order[rank])
        solo = librosa.istft(S * comp_mags[idx], hop_length=hop, length=len(y))
        solos[idx] = save(f'01_component_{idx+1:02d}', solo)

    neutral = save('02_neutral_griffinlim', phase_reconstruct(predicted, hop, len(y), gl_iterations, seed))

    # H cross routing (verbatim)
    route = np.roll(np.arange(k), 2)
    H_route = np.empty_like(H)
    for i in range(k):
        j = int(route[i])
        H_route[i] = H[j] * (np.mean(H[i]) / max(float(np.mean(H[j])), 1e-12))
    M_route = W @ H_route
    M_route = ndi.gaussian_filter(M_route, sigma=(0.4, 1.0))
    M_route *= (M.sum() / max(M_route.sum(), 1e-12))
    xroute_op = save('03_crossroute_originalphase', phase_aware_from_magnitude(S, M_route, hop, len(y)))
    xroute_gl = save('04_crossroute_griffinlim', phase_reconstruct(M_route, hop, len(y), gl_iterations, seed+1))

    # Spectral sculpture (verbatim)
    factors = [0.75, 1.38, 0.88, 1.22, 0.64, 1.56]
    W_sculpt = W.copy()
    for i in range(k):
        factor = factors[i % len(factors)]
        W_sculpt[:, i] = spectral_stretch(W[:, i:i+1], factor)[:, 0]
    offsets_s = [0.0, .29, -.38, .61, -.22, .43]
    H_sculpt = np.zeros_like(H)
    for i in range(k):
        h = ndi.gaussian_filter1d(H_route[i], sigma=12 + i*4)
        shift = int(offsets_s[i % len(offsets_s)] * sr / hop)
        if shift > 0:
            H_sculpt[i, shift:] = h[:-shift]
        elif shift < 0:
            H_sculpt[i, :shift] = h[-shift:]
        else:
            H_sculpt[i] = h
    M_sculpt = W_sculpt @ H_sculpt
    M_sculpt *= M.sum() / max(M_sculpt.sum(), 1e-12)
    sculpture = save('05_spectral_sculpture', phase_aware_from_magnitude(S, M_sculpt, hop, len(y)))

    # Spectral portrait (verbatim)
    best = int(order[0])
    M_portrait = np.broadcast_to((W[:, best] * float(np.mean(H[best])))[:, None],
                                 M.shape).copy()
    rng = np.random.default_rng(seed + 3)
    noise_phase = rng.uniform(-np.pi, np.pi, size=M_portrait.shape)
    portrait_signal = librosa.istft(M_portrait * np.exp(1j*noise_phase),
                                    hop_length=hop, length=len(y))
    portrait = save('06_spectral_portrait', portrait_signal)

    slot_components = sorted(solos)  # ascending index = the prototypes' file order
    tracks = np.stack([solos[i] for i in slot_components]
                      + [neutral, xroute_op, xroute_gl, sculpture, portrait], axis=0)
    corpus_info = {
        "slots": [
            {"slot": s + 1, "name": CORPUS_NAMES[s],
             "nmf_component_1based": (slot_components[s] + 1) if s < 3 else None,
             "energy_rank": (int(np.where(order == slot_components[s])[0][0]) + 1) if s < 3 else None}
            for s in range(len(CORPUS_NAMES))],
        "component_energy_order_1based": [int(t) + 1 for t in order],
        "route_H_indices_1based": [int(t) + 1 for t in route],
        "portrait_component_1based": best + 1,
        "sum_component_mask_abs_error": sum_mask_error,
        "levels": info,
    }
    return source_mono, tracks, corpus_info


# ========================================================= [ENV]/[SPA] stages
def rms_curve(x, sr, window_ms=30):  # [ENV]/[SPA]
    m = max(3, int(sr * window_ms / 1000))
    return np.sqrt(np.maximum(uniform_filter1d(np.asarray(x, dtype=np.float64)**2, m, mode='constant'), 0))


def build_envelope(source, sr):  # [ENV]/[SPA] (identical in both)
    """Speech envelope with no pitch-related modulation, safe smooth gates."""
    fast = rms_curve(source, sr, 28)
    slow = rms_curve(source, sr, 140)
    fast = gaussian_filter1d(fast, sr * 0.012)
    slow = gaussian_filter1d(slow, sr * 0.045)
    p_fast = max(float(np.quantile(fast, .96)), 1e-6)
    p_slow = max(float(np.quantile(slow, .96)), 1e-6)
    fast = np.minimum(fast / p_fast, 1.25)
    slow = np.minimum(slow / p_slow, 1.25)
    e = .85 * fast + .15 * slow
    # Quiet regions really become quiet: gate is a smoothed function of energy.
    e = np.maximum((e - .022) / .978, 0) ** .84
    e = gaussian_filter1d(e, sr * .009)
    return np.minimum(e, 1.35)


def make_grains(tracks, sr, n, seed=20261029, *, density=93, grain_ms=(65, 140), speed=(.92, 1.08), segment_s=.26):
    """[SPA] make_grains: same scheduler and the same order of random draws
    (exponential, uniform, integers, uniform, uniform per grain). Events keep
    their parameters; grain_signal() rebuilds the samples identically."""
    rng = np.random.default_rng(seed)
    duration = n/sr
    power = np.sqrt(np.mean(tracks*tracks, axis=1))
    typical = np.median(power)
    gains = np.clip(typical / np.maximum(power, 1e-9), .55, 1.9)
    onset = 0.0
    events = []
    per_file = np.zeros(len(tracks), dtype=int)
    while onset < duration:
        onset += rng.exponential(1/density)
        if onset >= duration: break
        t = int(sr*onset)
        length = int(sr*rng.uniform(*grain_ms)/1000)
        length = min(length, n-t)
        if length < 16: continue
        k = int(rng.integers(len(tracks)))
        speed_rate = rng.uniform(*speed)
        needed = int(length*speed_rate)+3
        maxstart = max(0, tracks.shape[1]-needed-1)
        desired = int(sr * (onset + rng.uniform(-segment_s, segment_s)))
        st = int(np.clip(desired, 0, maxstart))
        events.append((t, k, st, length, speed_rate))
        per_file[k] += 1
    return events, per_file, gains


def grain_signal(tracks, gains, event):
    """[SPA] make_grains inner loop, verbatim expressions: (grain*win, win**2)."""
    t, k, st, length, speed_rate = event
    positions = st + np.arange(length, dtype=np.float64)*speed_rate
    ix = np.floor(positions).astype(np.int64)
    frac = positions - ix
    grain = ((1-frac)*tracks[k, ix] + frac*tracks[k, ix+1]) * gains[k]
    win = np.hanning(length)
    return grain*win, win**2


def render(events, tracks, gains, sr, n, n_channels, gainfn):
    """[SPA] render(), with grains rebuilt by grain_signal() (identical values)."""
    numer = np.zeros((n, n_channels), dtype=np.float64)
    energy = np.zeros(n, dtype=np.float64)
    for idx, ev in enumerate(events):
        t, k = ev[0], ev[1]
        grain, win2 = grain_signal(tracks, gains, ev)
        length = len(grain)
        g = np.asarray(gainfn(idx, t/sr, k), dtype=np.float64)
        if len(g) != n_channels or not np.isfinite(g).all():
            raise ValueError('Bad spatial gains')
        numer[t:t+length, :] += grain[:, None]*g[None, :]
        energy[t:t+length] += win2
    out = numer / np.sqrt(np.maximum(energy[:, None], 1e-6))
    out[energy <= 1e-6, :] = 0
    fade = min(int(sr*.040), len(out)//2)
    out[:fade, :] *= np.linspace(0, 1, fade)[:, None]
    out[-fade:, :] *= np.linspace(1, 0, fade)[:, None]
    return out


def stereo_gains(pan):  # [SPA]
    pan = float(np.clip(pan, -1, 1))
    angle = (pan+1)*np.pi/4
    return [np.cos(angle), np.sin(angle)]


ISLAND_ANCHORS = (-.95, +.95, -.58, +.58, -.33, +.33, -.79, +.79)
QUAD_ANCHORS = (315., 45., 225., 135., 0., 90., 270., 180.)


def source_stereo(seed, duration, trace=None):  # [SPA] Stereo Source Islands
    rng = np.random.default_rng(seed)
    anchors = np.array([-.95, +.95, -.58, +.58, -.33, +.33, -.79, +.79])
    phases = np.array([0, 2, 1, 3, 4, 5, 2.4, 1.1])
    def gain(idx, t, k):
        drift = .09*np.sin(2*np.pi*t/9.8+phases[k])
        pan = anchors[k]+drift+rng.normal(0, .10)
        if trace is not None:   # v1.1: record the position actually used
            trace.append(float(np.clip(pan, -1, 1)))
        return stereo_gains(pan)
    return gain


def orbit_centre(t, duration):  # [SPA] the orbit's centre, as in orbit_stereo
    return .65*np.sin(2*np.pi*t/duration*1.35-.6)


def orbit_stereo(seed, duration, trace=None):  # [SPA] Stereo Grain Orbit
    rng = np.random.default_rng(seed)
    def gain(idx, t, k):
        # An orbiting centre with independent, locally-scattered grains.
        centre = .65*np.sin(2*np.pi*t/duration*1.35-.6)
        pan = centre+rng.normal(0, .36)
        if trace is not None:
            trace.append(float(np.clip(pan, -1, 1)))
        return stereo_gains(pan)
    return gain


# Quad channels order: FL FR BL BR. Speaker azimuths: 315, 45, 225, 135 deg.
SPEAKER_DEGREES = (315., 45., 225., 135.)  # documentation; quad_gains encodes the layout


def quad_gains(degrees):  # [SPA]
    # Circular, adjacent-speaker equal-power panning, avoiding rear/front leakage.
    pos = np.mod(degrees, 360.)
    arranged = [(315., 0), (405., 1), (495., 3), (585., 2), (675., 0)]
    at = pos if pos >= 315 else pos+360
    for (angle0, ch0), (angle1, ch1) in zip(arranged[:-1], arranged[1:]):
        if angle0 <= at <= angle1:
            a = (at-angle0)/(angle1-angle0)
            g = np.zeros(4)
            g[ch0] = np.cos(a*np.pi/2)
            g[ch1] = np.sin(a*np.pi/2)
            return g
    raise RuntimeError(f'Quad angle out of range: {degrees}')


def source_quad(seed, duration, trace=None):  # [SPA] Quadraphonic Constellation
    rng = np.random.default_rng(seed)
    # Each corpus variant occupies its own sector, with small motion.
    anchors = np.array([315., 45., 225., 135., 0., 90., 270., 180.])
    def gain(idx, t, k):
        d = anchors[k]+13*np.sin(2*np.pi*t/11.5+k*1.3)+rng.normal(0, 11)
        if trace is not None:
            trace.append(float(np.mod(d, 360.)))
        return quad_gains(d)
    return gain


def apply_speech_envelope(signal, envelope):  # [SPA]
    return signal*envelope[:, None]


def level_match(audio, target, max_peak=.93, channels=None):  # [SPA]
    # Stereo: per-channel RMS ~= reference mono RMS. Quad: total energy ~= mono.
    z = np.asarray(audio, dtype=np.float64)
    if channels == 4:
        level = float(np.sqrt(np.mean(np.sum(z*z, axis=1))))
    else:
        level = rms(z)
    if level <= 1e-12:
        return z.astype(np.float32), 0.0
    gain = min(target/level, max_peak/max(np.max(np.abs(z)), 1e-10))
    return (z*gain).astype(np.float32), float(gain)


def audition_gain(x, reference, limit=.93):  # [ENV]
    x = np.nan_to_num(x).astype(np.float64)
    level = rms(x)
    if level < 1e-8:
        return x.astype(np.float32)
    factor = min(rms(reference) / level, limit / max(np.max(np.abs(x)), 1e-10))
    return (x * factor).astype(np.float32)


def corr(a, b):  # [SPA]
    if np.std(a) < 1e-15 or np.std(b) < 1e-15: return float('nan')
    return float(np.corrcoef(a, b)[0, 1])


def statistics(y, sr, source):  # [SPA]
    ch = y.shape[1]
    speech_env = gaussian_filter1d(rms_curve(source, sr, 30), sr*.070)
    z = np.sqrt(np.mean(y.astype(float)**2, axis=1))
    output_env = gaussian_filter1d(rms_curve(z, sr, 30), sr*.070)
    res = {'channels': int(ch), 'peak': float(np.max(np.abs(y))),
           'per_channel_rms': [rms(y[:, c]) for c in range(ch)],
           'envelope_correlation': corr(speech_env[::160], output_env[::160])}
    if ch == 2:
        mid = (y[:, 0]+y[:, 1])*.5
        side = (y[:, 0]-y[:, 1])*.5
        res['left_right_correlation'] = corr(y[:, 0], y[:, 1])
        res['side_mid_db'] = float(20*np.log10(max(rms(side), 1e-12)/max(rms(mid), 1e-12)))
    return res


# ============================================================= WAV writing
def wav_bytes_with_channel_mask(data, sr, subtype, mask):
    """WAVE_FORMAT_EXTENSIBLE as libsndfile writes it, with the speaker
    channel mask then set explicitly in the header. No ffmpeg needed."""
    buf = io.BytesIO()
    sf.write(buf, data, sr, subtype=subtype, format="WAVEX")
    raw = bytearray(buf.getvalue())
    pos = 12
    while pos + 8 <= len(raw):
        cid = bytes(raw[pos:pos+4])
        size = struct.unpack_from("<I", raw, pos+4)[0]
        if cid == b"fmt ":
            tag = struct.unpack_from("<H", raw, pos+8)[0]
            if tag != 0xFFFE or size < 40:
                raise RuntimeError("Expected a WAVE_FORMAT_EXTENSIBLE header for multichannel output")
            struct.pack_into("<I", raw, pos+8+20, mask)
            return bytes(raw)
        pos += 8 + size + (size & 1)
    raise RuntimeError("fmt chunk not found")


class OwnedDir:
    """Writes files only inside one work directory and records each of them
    in a ledger, so cleanup can remove exactly what this tool created."""

    def __init__(self, path: Path):
        self.path = Path(path)
        self.path.mkdir(parents=True, exist_ok=True)
        self.ledger = self.path / WORKDIR_LEDGER

    def claim(self, name):
        with open(self.ledger, "a", encoding="utf-8") as f:
            f.write(name + "\n")
        return self.path / name

    def write_wav(self, name, data, sr, subtype):
        sf.write(self.claim(name), data, sr, subtype=subtype)

    def write_bytes(self, name, data):
        self.claim(name).write_bytes(data)

    def write_text(self, name, text):
        self.claim(name).write_text(text, encoding="utf-8")


# =============================================================== pipeline
def versions():
    v = {"engine": ENGINE_VERSION, "python": platform.python_version(),
         "platform": platform.platform()}
    for mod, name in ((globals().get("np"), "numpy"), (globals().get("scipy"), "scipy"),
                      (globals().get("sklearn"), "scikit-learn"),
                      (globals().get("librosa"), "librosa"), (globals().get("sf"), "soundfile")):
        if mod is not None:
            v[name] = getattr(mod, "__version__", "?")
    if globals().get("sf") is not None:
        v["libsndfile"] = getattr(sf, "__libsndfile_version__", "?")
    return v


def validate_params(p):
    errs = []
    if not (1.0 <= p.density <= 500.0):
        errs.append(f"Density must be 1-500 grains/s (got {p.density}).")
    if not (5.0 <= p.grain_min_ms <= 1000.0) or not (5.0 <= p.grain_max_ms <= 1000.0):
        errs.append("Grain durations must be 5-1000 ms.")
    if p.grain_min_ms > p.grain_max_ms:
        errs.append(f"Minimum grain duration ({p.grain_min_ms} ms) is above the maximum ({p.grain_max_ms} ms).")
    if not (0.0 <= p.locality <= 5.0):
        errs.append(f"Locality range must be 0-5 s (got {p.locality}).")
    if not (0.25 <= p.speed_min <= 4.0) or not (0.25 <= p.speed_max <= 4.0):
        errs.append("Playback speeds must be 0.25-4.")
    if p.speed_min > p.speed_max:
        errs.append(f"Minimum playback speed ({p.speed_min}) is above the maximum ({p.speed_max}).")
    if not (0.0 <= p.envelope_strength <= 1.0):
        errs.append(f"Envelope strength must be 0-1 (got {p.envelope_strength}).")
    if p.grain_seed < 0:
        errs.append("Seed must be >= 0.")
    if errs:
        raise EngineError(" ".join(errs))


def is_reference_granular(p):
    r = REFERENCE
    return (p.grain_seed == r["grain_seed"] and p.density == r["density"]
            and (p.grain_min_ms, p.grain_max_ms) == r["grain_ms"]
            and (p.speed_min, p.speed_max) == r["speed"] and p.locality == r["segment_s"]
            and p.envelope_strength == 1.0)


def compose(p, log=print):
    """Whole pipeline in memory. Returns (results, diagnostics)."""
    r = REFERENCE
    t0 = time.time()
    validate_params(p)
    y, sr = load_input(str(p.input), r["sr"], r["nmf_seed"])
    if not np.all(np.isfinite(y)):
        raise EngineError("The input contains non-finite samples.")
    secs = len(y) / sr
    if secs < MIN_SECONDS:
        raise EngineError(f"The input is {secs:.3f} s long; at least {MIN_SECONDS:.1f} s is needed.")
    if secs > MAX_SECONDS:
        raise EngineError(f"The input is {secs:.1f} s long; v1.0 accepts at most {MAX_SECONDS/60:.0f} minutes.")
    if rms(y) <= 1e-7:
        raise EngineError("The input is silent (or below -140 dBFS RMS): there is nothing to decompose.")
    log(f"Input {secs:.3f} s at {sr} Hz")

    dec = nmf_decompose(y, sr, r["n_fft"], r["hop"], r["components"], r["nmf_max_iter"], r["nmf_seed"])
    log(f"NMF: {r['components']} components, {dec['nmf_iterations']} iterations, error {dec['reconstruction_error']:.5f}")
    source_mono, tracks, corpus_info = generate_corpus(y, sr, dec, r["gl_iterations"], r["nmf_seed"])
    log("Corpus: 8 sources; solo slots = NMF components "
        + ", ".join(str(s["nmf_component_1based"]) for s in corpus_info["slots"][:3]))
    orig = source_mono
    n = len(orig)
    duration = n / sr
    env = build_envelope(orig, sr)
    if p.envelope_strength != 1.0:
        env = (1.0 - p.envelope_strength) + p.envelope_strength * env
    events, per_file, gains = make_grains(
        tracks, sr, n, p.grain_seed, density=p.density,
        grain_ms=(p.grain_min_ms, p.grain_max_ms), speed=(p.speed_min, p.speed_max),
        segment_s=p.locality)
    log(f"Grains: {len(events)}")

    # Mono reference: [ENV] local cloud x envelope, audition gain, 16-bit.
    mono_raw = render(events, tracks, gains, sr, n, 1, lambda i, t, k: [1])[:, 0]
    mono = audition_gain(mono_raw * env, orig)
    prior = pcm_roundtrip(mono, sr, "PCM_16")   # what [SPA] read back as 'prior'
    target = rms(prior)
    results = {"mono": {"data": mono[:, None], "subtype": "PCM_16",
                        "stats": statistics(prior[:, None], sr, orig)}}

    traces = {"islands": [], "orbit": [], "quad": []}
    configs = {"islands": (2, source_stereo(r["seed_islands"], duration, traces["islands"])),
               "orbit": (2, orbit_stereo(r["seed_orbit"], duration, traces["orbit"])),
               "quad": (4, source_quad(r["seed_quad"], duration, traces["quad"]))}
    for mode in ("islands", "orbit", "quad"):
        if mode not in p.modes:
            continue
        ch, fn = configs[mode]
        raw = render(events, tracks, gains, sr, n, ch, fn)
        yv, g = level_match(apply_speech_envelope(raw, env), target, channels=ch)
        stats = statistics(yv, sr, orig)
        stats["gain"] = g
        results[mode] = {"data": yv, "subtype": "PCM_24", "stats": stats}
        if mode == "quad" and p.quad_preview:
            downmix = np.stack([yv[:, 0]+.55*yv[:, 2], yv[:, 1]+.55*yv[:, 3]], axis=1)
            preview, pg = level_match(downmix, target, channels=2)
            pst = statistics(preview, sr, orig)
            pst["gain"] = pg
            results["quad_preview"] = {"data": preview, "subtype": "PCM_24", "stats": pst}
        log(f"{mode}: {ch} channels, gain {g:.4f}")
    if "mono" not in p.modes:
        results.pop("mono")

    for s_ in corpus_info["slots"]:
        s_["label"] = slot_label(s_)
        s_["grains"] = int(per_file[s_["slot"] - 1])
        s_["gain"] = float(gains[s_["slot"] - 1])

    diagnostics = {
        "engine": ENGINE_NAME, "versions": versions(), "preset": p.preset_label,
        "input": {"file": str(p.input), "seconds": round(secs, 6), "analysis_sr": sr, "frames": n},
        "reference_mode": {k: (list(v) if isinstance(v, tuple) else v) for k, v in r.items()},
        "granular_settings": {"seed": p.grain_seed, "density": p.density,
                              "grain_ms": [p.grain_min_ms, p.grain_max_ms],
                              "speed": [p.speed_min, p.speed_max], "locality_s": p.locality,
                              "envelope_strength": p.envelope_strength,
                              "is_reference_configuration": is_reference_granular(p)},
        "nmf": {"iterations_run": dec["nmf_iterations"],
                "reconstruction_rel_mag_error": round(dec["reconstruction_error"], 5),
                "warnings": dec["warnings"]},
        "corpus": corpus_info,
        "grains": {"count": len(events), "per_source": per_file.tolist(),
                   "source_gains": [float(g) for g in gains]},
        "level_target_rms": target,
        "quad_channel_order": list(QUAD_CHANNEL_ORDER),
        "outputs": {m: v["stats"] for m, v in results.items()},
        "seconds_elapsed": round(time.time() - t0, 2),
    }
    return results, diagnostics, {"tracks": tracks, "source_mono": orig, "events": events,
                                  "gains": gains, "env": env, "sr": sr, "prior": prior,
                                  "traces": traces, "duration": duration}


SLOT_KIND_LABELS = ["solo", "solo", "solo", "Neutral GL", "X-route OP", "X-route GL",
                    "Sculpture", "Portrait"]


def slot_label(slot):
    """Display name of a corpus slot, with the REAL NMF component number for
    the three solo slots (the slot names 01/06/09 are the Hebrew run's)."""
    i = slot["slot"] - 1
    if i < 3:
        return f"C{slot['nmf_component_1based']:02d} solo"
    return SLOT_KIND_LABELS[i]


def write_viz(results, diagnostics, internals, out):
    """Drawing data for the Praat figure (tab-separated, read as Tables).
    Spatial positions are the ones logged by the gain functions during the
    render, so the figure shows what was rendered."""
    sr = internals["sr"]
    ev = internals["events"]
    tr = internals["traces"]
    cols = ["onset", "slot", "dur", "read", "speed", "pan_islands", "pan_orbit", "deg_quad"]
    rows = ["\t".join(cols)]
    for i, (t, k, st, length, speed_rate) in enumerate(ev):
        def pick(m):
            return f"{tr[m][i]:.5f}" if len(tr[m]) == len(ev) else "0"
        rows.append(f"{t/sr:.5f}\t{k+1}\t{length/sr:.5f}\t{st/sr:.5f}\t{speed_rate:.5f}\t"
                    f"{pick('islands')}\t{pick('orbit')}\t{pick('quad')}")
    out.write_text("viz_grains.tsv", "\n".join(rows) + "\n")

    # Curves on a 10 ms grid: 30 ms RMS of the source reference, the imposed
    # envelope, each output (all channels), and each quad speaker.
    hop = int(sr * 0.010)
    src = internals["source_mono"]
    n = len(src)
    idx = np.arange(0, n, hop)
    curves = {"time": idx / sr,
              "src_rms": rms_curve(src, sr, 30)[idx],
              "envelope": internals["env"][idx],
              "orbit_centre": orbit_centre(idx / sr, internals["duration"])}
    for m in ("mono", "islands", "orbit", "quad"):
        if m in results:
            d = np.asarray(results[m]["data"], dtype=np.float64)
            tot = np.sqrt(np.mean(d * d, axis=1))
            curves[f"out_{m}"] = rms_curve(tot, sr, 30)[idx]
            if m == "quad":
                for c, lab in enumerate(QUAD_CHANNEL_ORDER):
                    curves[f"quad_{lab}"] = rms_curve(d[:, c], sr, 30)[idx]
    names = list(curves)
    lines = ["\t".join(names)]
    for j in range(len(idx)):
        lines.append("\t".join(f"{curves[c][j]:.6g}" for c in names))
    out.write_text("viz_curves.tsv", "\n".join(lines) + "\n")

    slots = ["slot\tlabel\tgrains\tgain\tisland_anchor\tquad_anchor\tnmf_component"]
    for sl in diagnostics["corpus"]["slots"]:
        i = sl["slot"] - 1
        slots.append(f"{sl['slot']}\t{sl['label']}\t{sl['grains']}\t{sl['gain']:.4f}\t"
                     f"{ISLAND_ANCHORS[i]}\t{QUAD_ANCHORS[i]}\t{sl['nmf_component_1based'] or 0}")
    out.write_text("viz_slots.tsv", "\n".join(slots) + "\n")


OUTPUT_FILES = {
    "mono": "NMF_Local_Granular.wav",
    "islands": "NMF_Stereo_Islands.wav",
    "orbit": "NMF_Stereo_Orbit.wav",
    "quad": "NMF_Quad_FL_FR_BL_BR.wav",
    "quad_preview": "NMF_Quad_Preview_stereo_downmix.wav",
}


def write_outputs(results, diagnostics, internals, out: OwnedDir, p):
    sr = internals["sr"]
    written = []
    for mode, res in results.items():
        name = OUTPUT_FILES[mode]
        data = res["data"]
        if mode == "quad":
            out.write_bytes(name, wav_bytes_with_channel_mask(data, sr, "PCM_24", QUAD_CHANNEL_MASK))
            if p.stems:
                for c, lab in enumerate(QUAD_CHANNEL_ORDER):
                    out.write_wav(f"NMF_Quad_stem_{c+1}_{lab}.wav", data[:, c], sr, "PCM_24")
        else:
            out.write_wav(name, data[:, 0] if data.shape[1] == 1 else data, sr, res["subtype"])
        written.append({"kind": mode, "file": name, "channels": int(data.shape[1]),
                        "frames": int(data.shape[0]), "sr": sr})
    if p.keep_intermediates:
        for i, nm in enumerate(CORPUS_NAMES):
            out.write_wav(f"corpus_{nm}.wav", internals["tracks"][i], sr, "PCM_16")
        out.write_wav("corpus_00_source_mono.wav", internals["source_mono"], sr, "PCM_16")
    return written


def write_manifests(out: OwnedDir, status, message, written, diagnostics):
    man = {"status": status, "message": message, "outputs": written, "diagnostics": diagnostics}
    out.write_text("manifest.json", json.dumps(man, indent=2, ensure_ascii=False, default=str))
    lines = [f"STATUS\t{status}", f"MESSAGE\t{message.replace(chr(10), ' ').replace(chr(9), ' ')}"]
    for w in written:
        lines.append(f"OUTPUT\t{w['kind']}\t{w['file']}\t{w['channels']}\t{w['frames']}\t{w['sr']}")
    if diagnostics:
        g = diagnostics.get("grains", {})
        c = diagnostics.get("corpus", {})
        lines.append(f"INFO\tGrains: {g.get('count')} (per corpus slot {g.get('per_source')})")
        if c:
            lines.append("INFO\tSolo slots = NMF components " + ", ".join(
                str(s['nmf_component_1based']) for s in c['slots'][:3])
                + f" (energy ranks {', '.join(str(s['energy_rank']) for s in c['slots'][:3])}); portrait = component {c['portrait_component_1based']}")
            for s_ in c["slots"]:
                lines.append(f"SLOT\t{s_['slot']}\t{s_.get('label', s_['name'])}\t{s_.get('grains', 0)}")
        lines.append(f"PRESET\t{diagnostics.get('preset', '')}")
        gs = diagnostics.get("granular_settings", {})
        lines.append(f"GRAINCOUNT\t{g.get('count')}")
        lines.append(f"REFERENCE\t{'yes' if gs.get('is_reference_configuration') else 'no'}")
        nm = diagnostics.get("nmf", {})
        lines.append(f"INFO\tNMF: {nm.get('iterations_run')} iterations, relative magnitude error {nm.get('reconstruction_rel_mag_error')}")
        for m, st in diagnostics.get("outputs", {}).items():
            extra = f", L/R correlation {st['left_right_correlation']:.3f}" if "left_right_correlation" in st else ""
            lines.append(f"INFO\t{m}: {st['channels']} ch, peak {st['peak']:.3f}, envelope correlation {st['envelope_correlation']:.3f}{extra}")
        lines.append(f"INFO\tTime {diagnostics.get('seconds_elapsed')} s; " + ", ".join(
            f"{k} {v}" for k, v in diagnostics.get('versions', {}).items() if k != 'platform'))
    out.write_text("praat_manifest.txt", "\n".join(lines) + "\n")


# ============================================================ work folders
def _is_owned_workdir(d: Path):
    return d.is_dir() and d.name.startswith(WORKDIR_PREFIX) and (d / WORKDIR_MARKER).is_file()


def cleanup_workdir(d: Path, log=print):
    """Delete only files this tool owns (marker, the input it names, ledger
    entries), then the folder itself if it is empty. Never recursive."""
    d = Path(d)
    if not _is_owned_workdir(d):
        raise EngineError(f"Refusing to clean {d}: not an {ENGINE_NAME} work folder (name or marker missing).")
    names = set()
    marker = (d / WORKDIR_MARKER).read_text(encoding="utf-8", errors="replace").splitlines()
    for line in marker:
        if line.startswith("input="):
            names.add(line.split("=", 1)[1].strip())
    ledger = d / WORKDIR_LEDGER
    if ledger.is_file():
        names.update(l.strip() for l in ledger.read_text(encoding="utf-8").splitlines() if l.strip())
    removed, kept = [], []
    for nm in sorted(names):
        if "/" in nm or "\\" in nm or nm in ("", ".", ".."):
            continue
        f = d / nm
        if f.is_file():
            f.unlink()
            removed.append(nm)
    for f in (ledger, d / WORKDIR_MARKER):
        if f.is_file():
            f.unlink()
            removed.append(f.name)
    left = [x.name for x in d.iterdir()]
    if left:
        kept = left
        log(f"Kept {d} because it contains files this tool did not create: {left}")
        return removed, kept
    d.rmdir()
    return removed, kept


KEPT_PREFIX = "NMF_GSC_kept_"


def release_workdir(d: Path, log=print):
    """Turn a work folder the user asked to keep into a KEPT folder: remove
    the private input copy and the ownership marker, and rename the folder
    NMF_GSC_kept_..., so neither --cleanup nor --cleanup-stale will ever
    touch it again. Returns the new path."""
    d = Path(d)
    if not _is_owned_workdir(d):
        raise EngineError(f"Refusing to release {d}: not an {ENGINE_NAME} work folder.")
    marker = (d / WORKDIR_MARKER).read_text(encoding="utf-8", errors="replace").splitlines()
    for line in marker:
        if line.startswith("input="):
            nm = line.split("=", 1)[1].strip()
            if nm and "/" not in nm and "\\" not in nm and (d / nm).is_file():
                (d / nm).unlink()
    (d / WORKDIR_MARKER).unlink()
    new = d.with_name(KEPT_PREFIX + d.name[len(WORKDIR_PREFIX):])
    d.rename(new)
    log(str(new))
    return new


def cleanup_stale(root: Path, hours: float, log=print):
    root = Path(root)
    report = []
    if not root.is_dir():
        raise EngineError(f"{root} is not a folder.")
    now = time.time()
    for d in sorted(root.iterdir()):
        if not _is_owned_workdir(d):
            continue
        age_h = (now - d.stat().st_mtime) / 3600
        if age_h < hours:
            report.append({"folder": str(d), "action": "skipped (younger than limit)", "age_hours": round(age_h, 2)})
            continue
        removed, kept = cleanup_workdir(d, log)
        report.append({"folder": str(d), "action": "kept (unknown files)" if kept else "removed",
                       "files_removed": len(removed), "age_hours": round(age_h, 2)})
    return report


# ===================================================================== CLI
def build_parser():
    ap = argparse.ArgumentParser(
        prog="nmf_granular_spatial_composer.py",
        description=f"{ENGINE_NAME} v{ENGINE_VERSION}: one sound -> NMF corpus -> local granular "
                    "cloud with the original envelope -> mono / stereo / quad compositions.")
    ap.add_argument("--input", type=Path, help="input audio file (any format librosa reads)")
    ap.add_argument("--output-dir", type=Path, help="folder for results (created if needed)")
    ap.add_argument("--mode", default="all", choices=["mono", "islands", "orbit", "quad", "all"],
                    help="which composition(s) to render (default all)")
    ap.add_argument("--seed", dest="grain_seed", type=int, default=REFERENCE["grain_seed"],
                    help="granular seed (reference 20261029)")
    ap.add_argument("--density", type=float, default=REFERENCE["density"], help="grains per second (93)")
    ap.add_argument("--grain-min-ms", type=float, default=REFERENCE["grain_ms"][0], help="(65)")
    ap.add_argument("--grain-max-ms", type=float, default=REFERENCE["grain_ms"][1], help="(140)")
    ap.add_argument("--locality", type=float, default=REFERENCE["segment_s"],
                    help="max distance in s between output time and source read position (0.26)")
    ap.add_argument("--speed-min", type=float, default=REFERENCE["speed"][0], help="(0.92)")
    ap.add_argument("--speed-max", type=float, default=REFERENCE["speed"][1], help="(1.08)")
    ap.add_argument("--envelope-strength", type=float, default=1.0,
                    help="0 = no original envelope, 1 = reference (default)")
    ap.add_argument("--quad-preview", choices=["yes", "no"], default="yes",
                    help="also write the labelled stereo DOWNMIX of the quad output (default yes)")
    ap.add_argument("--stems", choices=["yes", "no"], default="yes",
                    help="also write the four synchronized mono quad stems (default yes)")
    ap.add_argument("--keep-intermediates", action="store_true",
                    help="also write the 8 corpus sources and the source reference (diagnostics)")
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("--probe", type=Path, metavar="JSON",
                    help="only check Python and the dependencies; write the result to JSON")
    ap.add_argument("--cleanup", type=Path, metavar="WORKDIR",
                    help="remove a finished work folder created for the Praat bridge")
    ap.add_argument("--cleanup-stale", type=Path, metavar="ROOT",
                    help="remove leftover work folders of this tool under ROOT")
    ap.add_argument("--older-than-hours", type=float, default=12.0,
                    help="age limit for --cleanup-stale (default 12)")
    ap.add_argument("--release", type=Path, metavar="WORKDIR",
                    help="keep a work folder permanently (renamed NMF_GSC_kept_..., never cleaned)")
    ap.add_argument("--viz", choices=["yes", "no"], default="yes",
                    help="write drawing data viz_*.tsv for the Praat figure (default yes)")
    ap.add_argument("--preset-label", default="Reference",
                    help="name of the Praat preset, recorded in the manifest")
    return ap


def main(argv=None):
    ap = build_parser()
    p = ap.parse_args(argv)
    log = (lambda *a, **k: None) if p.quiet else (lambda *a, **k: print(*a, flush=True, **k))

    if p.probe:
        res = {"ok": not _MISSING, "missing": _MISSING, "versions": versions() if "numpy" not in _MISSING else {},
               "install_hint": f'"{sys.executable}" -m pip install -r requirements.txt' if _MISSING else ""}
        Path(p.probe).write_text(json.dumps(res, indent=2), encoding="utf-8")
        return 0 if not _MISSING else 4
    if p.cleanup or p.cleanup_stale or p.release:
        try:
            if p.release:
                release_workdir(p.release, log)
            elif p.cleanup:
                removed, kept = cleanup_workdir(p.cleanup, log)
                log(f"Removed {len(removed)} files" + (f"; kept folder (unknown files {kept})" if kept else "; folder removed"))
            else:
                for row in cleanup_stale(p.cleanup_stale, p.older_than_hours, log):
                    log(json.dumps(row, ensure_ascii=False))
            return 0
        except EngineError as e:
            print(f"ERROR: {e}", file=sys.stderr)
            return 2

    if _MISSING:
        print("ERROR: missing Python packages: " + ", ".join(_MISSING)
              + f'. Install with: "{sys.executable}" -m pip install -r requirements.txt', file=sys.stderr)
        return 4
    if not p.input or not p.output_dir:
        ap.error("--input and --output-dir are required")
    p.modes = list(MODES) if p.mode == "all" else [p.mode]
    p.quad_preview = p.quad_preview == "yes" and "quad" in p.modes
    p.stems = p.stems == "yes"
    out = OwnedDir(p.output_dir)
    written, diagnostics = [], {}
    try:
        if not Path(p.input).is_file():
            raise EngineError(f"Input file not found: {p.input}")
        results, diagnostics, internals = compose(p, log)
        written = write_outputs(results, diagnostics, internals, out, p)
        if p.viz == "yes":
            write_viz(results, diagnostics, internals, out)
        write_manifests(out, "ok", "", written, diagnostics)
        log("Done: " + ", ".join(w["file"] for w in written))
        return 0
    except EngineError as e:
        write_manifests(out, "error", str(e), [], diagnostics)
        print(f"ERROR: {e}", file=sys.stderr)
        return 2
    except Exception as e:  # unexpected: keep the traceback for diagnosis
        tb = traceback.format_exc()
        diagnostics["traceback"] = tb
        write_manifests(out, "error", f"Unexpected engine failure: {type(e).__name__}: {e}", [], diagnostics)
        print(tb, file=sys.stderr)
        return 3


if __name__ == "__main__":
    sys.exit(main())
