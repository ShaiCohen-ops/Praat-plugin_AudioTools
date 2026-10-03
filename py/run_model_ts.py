#!/usr/bin/env python3
# ============================================================
# Praat AudioTools Plugin
# Script:      run_model_ts.py
# Author:      Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version:     1.5.1 (2026)
# License:     MIT License
# Repository:  https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Runs a TorchScript RAVE (.ts, nn~ export) model on a WAV file for
#   IRCAM_rave_model.praat, and reports what the model exposes.
#
#   Actions:
#     process          forward() = RAVE encode -> decode (unchanged from v1.2)
#     latent           encode() -> one latent operation -> decode() (v1.4):
#                      scale, offset, dimension gain, mute, isolate,
#                      smoothing, freeze, jitter
#     diagnose         load one model, report methods / *_params buffers /
#                      sample rate / latent size; no audio processed
#     diagnose_folder  the same for every .ts file in a folder
#
#   Model metadata (best effort, nothing assumed):
#     * method names via the TorchScript module (forward, encode, decode, ...)
#     * nn~ "<method>_params" buffers = [in_channels, in_ratio,
#       out_channels, out_ratio]; encode_params gives the latent size
#       (out_channels) and the compression ratio (out_ratio)
#     * sample rate from an attribute or buffer named sr / sampling_rate /
#       sample_rate, if the export provides one
#
# Changelog v1.5.1:
#   - Energy layer draws from its own random stream derived from the Seed
#     (default_rng([seed, tag])); with the Jitter operation and Seeded
#     energy on the same seed, the two noises were identical (correlation
#     1.0). Fresh and Seeded derive it the same way, so a Fresh seed still
#     reproduces in Seeded mode. Energy results in v1.5 seeded runs change.
#   - Mute described as "set to zero in the exported latent coordinate
#     system" (not "the latent centre").
#
# Changelog v1.5:
#   - Latent energy layer after the deterministic transform
#     (encode -> transform -> optional energy -> decode): Off (default,
#     identical every run) / Seeded / Fresh each run (seed reported);
#     Jitter or Smooth drift; amount relative to each dimension's spread in
#     the encoded input (or absolute); target all / one / high-variance
#     dimensions. New operation "none" for energy on the untouched latent.
#     The eight v1.4 operations are unchanged.
#
# Changelog v1.4:
#   - Latent transform action: Sound -> encode -> operation -> decode ->
#     Sound, for models exposing encode and decode (all eight RAVE models in
#     the nn~ help folder, per the v1.3 diagnostics). Eight deterministic
#     operations that assume nothing about what a dimension means. The
#     latent is used exactly as encode() returns it (for exports with
#     latent_pca / latent_mean this is the centred, PCA-ordered space;
#     encode/decode apply and undo that themselves).
#   - Process sound (forward) unchanged.
#
# Changelog v1.3:
#   - Diagnose actions (one model, or every .ts in the models folder).
#   - Sample rate: if the model declares its rate and the input differs,
#     the input is resampled to the model rate (windowed-sinc, rational
#     ratio) and the result back to the input rate; "as is" keeps the v1.2
#     behaviour. v1.2 sent any rate straight into the model.
#   - Output written as 32-bit float WAV (was 16-bit PCM).
#   - Normalisation done once, here; IRCAM_rave_model.praat v1.3 no longer
#     applies "Scale peak: 0.99" on top. Modes now mean what they say:
#       none = untouched model output (no scaling, no clipping)
#       peak = scaled to peak 0.99 (what v1.2 delivered in EVERY mode)
#       rms  = -20 dBFS RMS, attenuated only if the peak would exceed 0.99
#   - Gain applied AFTER normalisation (in v1.2 it was applied before and
#     then cancelled by normalisation, so it had no audible effect).
#   - True latent trajectory for the figure when the model has encode():
#     a separate encode pass, written to a CSV; the audio still comes
#     from forward() exactly as before.
#   - Fast WAV I/O with numpy when available (v1.2 looped per sample in
#     Python); the stdlib path remains as a fallback for reading.
#   - Device option (cpu / auto / cuda); default cpu as before.
#   - Parameters read from a key=value file (one path argument); the
#     v1.2 command-line flags still work. Manifest with everything done.
#
# Requires: Python 3, torch; numpy recommended (fast I/O, resampling).
# ============================================================

import sys
import os
import re
import math
import struct
import traceback
import argparse
import wave
import array as _array
from pathlib import Path

VERSION = "1.5.1"

try:
    import numpy as np
    HAS_NUMPY = True
except ImportError:
    HAS_NUMPY = False

_error_file = None


def _crash(exc):
    tb = traceback.format_exc()
    msg = f"{type(exc).__name__}: {exc}\n\n{tb}"
    if _error_file:
        try:
            with open(_error_file, "w", encoding="utf-8") as f:
                f.write(msg)
        except Exception:
            pass
    print(msg, file=sys.stderr)
    sys.exit(1)


# =============================================================================
#  Parameters
# =============================================================================

def parse_args():
    p = argparse.ArgumentParser(description=f"RAVE TorchScript runner v{VERSION}")
    p.add_argument("--input", type=Path, default=None)
    p.add_argument("--output", type=Path, default=None)
    p.add_argument("--model", type=Path, default=None)
    p.add_argument("--models_dir", type=Path, default=None)
    p.add_argument("--error", type=Path, default=None)
    p.add_argument("--manifest", type=Path, default=None)
    p.add_argument("--latent_csv", type=Path, default=None)
    p.add_argument("--action", default="process", choices=["process", "latent", "diagnose", "diagnose_folder"])
    p.add_argument("--latent_op", default="scale",
                   choices=["scale", "offset", "dim_gain", "mute", "isolate", "smooth", "freeze", "jitter",
                            "none"])
    p.add_argument("--latent_dim", type=int, default=0)        # 1-based; 0 = all (where allowed)
    p.add_argument("--latent_amount", type=float, default=1.5)
    p.add_argument("--smooth_ms", type=float, default=200.0)
    p.add_argument("--freeze_pos", type=float, default=0.5)
    p.add_argument("--freeze_dur", type=float, default=5.0)
    p.add_argument("--seed", type=int, default=1)
    p.add_argument("--latent_in_csv", type=Path, default=None)
    p.add_argument("--energy_mode", default="off", choices=["off", "seeded", "fresh"])
    p.add_argument("--energy_type", default="drift", choices=["jitter", "drift"])
    p.add_argument("--energy_amount", type=float, default=0.3)
    p.add_argument("--energy_smooth", type=float, default=0.5)
    p.add_argument("--energy_target", default="all", choices=["all", "one", "high_variance"])
    p.add_argument("--energy_dim", type=int, default=1)
    p.add_argument("--energy_scale", default="relative", choices=["relative", "absolute"])
    p.add_argument("--gain", type=float, default=0.0)
    p.add_argument("--normalize", default="peak", choices=["none", "peak", "rms"])
    p.add_argument("--input_shape", default="auto", choices=["auto", "BCT", "B1T", "CT"])
    p.add_argument("--out_ch", default="auto", choices=["auto", "mono", "stereo"])
    p.add_argument("--sr_mode", default="resample", choices=["resample", "as_is"])
    p.add_argument("--out_rate", default="input", choices=["input", "model"])
    p.add_argument("--device", default="cpu", choices=["cpu", "auto", "cuda"])
    p.add_argument("--latent_viz", type=int, default=1)
    argv = sys.argv[1:]
    if len(argv) == 1 and os.path.isfile(argv[0]):
        argv = []
        with open(sys.argv[1], "r", encoding="utf-8") as fh:
            for line in fh:
                line = line.rstrip("\r\n")
                if "=" in line and not line.lstrip().startswith("#"):
                    k, v = line.split("=", 1)
                    if v.strip() != "":
                        argv += ["--" + k.strip(), v.strip()]
    return p.parse_args(argv)


# =============================================================================
#  WAV I/O
# =============================================================================

def read_wav(path):
    """Return (data [channels, samples] float32 list-of-arrays or ndarray, sr)."""
    with wave.open(str(path), "rb") as w:
        nch, sw, sr, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = w.readframes(n)
    if HAS_NUMPY:
        if sw == 2:
            x = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
        elif sw == 4:
            x = np.frombuffer(raw, dtype="<i4").astype(np.float32) / 2147483648.0
        elif sw == 1:
            x = (np.frombuffer(raw, dtype=np.uint8).astype(np.float32) - 128.0) / 128.0
        elif sw == 3:
            b = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 3).astype(np.int32)
            v = b[:, 0] | (b[:, 1] << 8) | (b[:, 2] << 16)
            v = np.where(v >= 1 << 23, v - (1 << 24), v)
            x = v.astype(np.float32) / 8388608.0
        else:
            raise RuntimeError(f"Unsupported WAV sample width: {sw} bytes")
        return x.reshape(-1, nch).T.copy(), sr
    # stdlib fallback (v1.2 path)
    if sw == 2:
        arr, scale = _array.array("h", raw), 1.0 / 32768.0
    elif sw == 4:
        arr, scale = _array.array("i", raw), 1.0 / 2147483648.0
    else:
        raise RuntimeError(f"Unsupported WAV sample width without numpy: {sw} bytes")
    floats = [s * scale for s in arr]
    return [floats[c::nch] for c in range(nch)], sr


def write_wav_float(path, data, sr):
    """32-bit IEEE float WAV (format tag 3). data: ndarray [channels, samples]."""
    data = np.asarray(data, dtype=np.float32)
    nch, n = data.shape
    payload = data.T.reshape(-1).astype("<f4").tobytes()
    fmt = struct.pack("<HHIIHH", 3, nch, int(sr), int(sr) * nch * 4, nch * 4, 32)
    fact = struct.pack("<I", n)
    with open(path, "wb") as fh:
        fh.write(b"RIFF" + struct.pack("<I", 4 + (8 + len(fmt)) + (8 + 4) + (8 + len(payload))) + b"WAVE")
        fh.write(b"fmt " + struct.pack("<I", len(fmt)) + fmt)
        fh.write(b"fact" + struct.pack("<I", 4) + fact)
        fh.write(b"data" + struct.pack("<I", len(payload)) + payload)


# =============================================================================
#  Resampling (windowed sinc, rational ratio; numpy)
# =============================================================================

def resample(x, old_sr, new_sr, zeros=24, rolloff=0.945):
    """x: ndarray [channels, samples]. Polyphase windowed-sinc resampler
    (Hann-squared window, cutoff at rolloff * the lower Nyquist)."""
    if old_sr == new_sr:
        return x
    g = math.gcd(int(old_sr), int(new_sr))
    up, down = int(new_sr) // g, int(old_sr) // g
    cutoff = min(up, down) * rolloff
    width = int(math.ceil(zeros * down / cutoff))
    idx = np.arange(-width, width + down, dtype=np.float64)
    kernels = np.empty((up, idx.size))
    for i in range(up):
        t = (-i / up + idx / down) * cutoff
        t = np.clip(t, -zeros, zeros)
        win = np.cos(t * math.pi / zeros / 2) ** 2
        k = np.sinc(t) * win
        kernels[i] = k / k.sum()
    n_in = x.shape[1]
    n_out = int(up * n_in / down)
    out = np.empty((x.shape[0], n_out), dtype=np.float32)
    for c in range(x.shape[0]):
        xp = np.pad(x[c].astype(np.float64), (width, width + down), mode="edge")
        n_frames = (xp.size - idx.size) // down + 1
        frames = np.lib.stride_tricks.as_strided(
            xp, shape=(n_frames, idx.size), strides=(xp.strides[0] * down, xp.strides[0]))
        y = frames @ kernels.T                     # [n_frames, up]
        out[c] = y.reshape(-1)[:n_out]
    return out


# =============================================================================
#  Model
# =============================================================================

def load_model(path, device):
    try:
        import torch
    except ImportError:
        raise RuntimeError("torch is not installed. Install with: pip install torch")
    if not Path(path).is_file():
        raise FileNotFoundError(f"Model file not found: '{path}'")
    dev = "cpu"
    if device == "cuda" or (device == "auto" and torch.cuda.is_available()):
        if not torch.cuda.is_available():
            raise RuntimeError("Device 'cuda' requested but CUDA is not available")
        dev = "cuda"
    model = torch.jit.load(str(path), map_location=dev)
    model.eval()
    return model, dev


def introspect(model):
    """Everything the TorchScript export reveals. Every probe is optional."""
    info = {"methods": [], "params": {}, "sr": None, "sr_source": "", "attributes": {},
            "buffers": [], "notes": []}
    try:
        info["methods"] = sorted(m for m in model._c._method_names() if not m.startswith("_"))
    except Exception as e:
        info["notes"].append(f"method list unavailable ({type(e).__name__})")
        info["methods"] = [m for m in ("forward", "encode", "decode") if hasattr(model, m)]
    for name in ("get_methods", "get_attributes"):
        if hasattr(model, name):
            try:
                info["attributes"][name] = str(getattr(model, name)())
            except Exception as e:
                info["notes"].append(f"{name}() failed ({type(e).__name__})")
    try:
        for bname, buf in model.named_buffers():
            info["buffers"].append(f"{bname}{list(buf.shape)}")
            m = re.match(r"^(\w+)_params$", bname)
            if m and buf.numel() == 4:
                v = [int(round(float(z))) for z in buf.flatten().tolist()]
                info["params"][m.group(1)] = {"in_ch": v[0], "in_ratio": v[1], "out_ch": v[2], "out_ratio": v[3]}
            if re.search(r"(^|[._])(sr|sampling_rate|sample_rate)$", bname) and buf.numel() == 1:
                info["sr"], info["sr_source"] = int(round(float(buf.item()))), f"buffer {bname}"
    except Exception as e:
        info["notes"].append(f"buffers unavailable ({type(e).__name__})")
    if info["sr"] is None:
        for aname in ("sr", "sampling_rate", "sample_rate"):
            if hasattr(model, aname):
                try:
                    v = getattr(model, aname)
                    v = float(v.item()) if hasattr(v, "item") else float(v)
                    if v > 0:
                        info["sr"], info["sr_source"] = int(round(v)), f"attribute {aname}"
                        break
                except Exception:
                    pass
    enc = info["params"].get("encode")
    info["latent_size"] = enc["out_ch"] if enc else None
    info["compression"] = enc["out_ratio"] if enc else None
    return info


def describe(info, name):
    lines = [f"Model: {name}",
             f"  methods:      {', '.join(info['methods']) or '(none found)'}"]
    for meth, p in sorted(info["params"].items()):
        lines.append(f"  {meth + '_params':16s} in {p['in_ch']} ch / ratio {p['in_ratio']}   "
                     f"out {p['out_ch']} ch / ratio {p['out_ratio']}")
    lines.append(f"  sample rate:  {info['sr']} Hz ({info['sr_source']})" if info["sr"]
                 else "  sample rate:  not declared by the export")
    if info["latent_size"]:
        lines.append(f"  latent:       {info['latent_size']} dimensions, one frame per "
                     f"{info['compression']} samples")
    for k, v in info["attributes"].items():
        lines.append(f"  {k}():  {v[:300]}")
    if info["buffers"]:
        lines.append(f"  buffers:      {', '.join(info['buffers'][:12])}"
                     + (" ..." if len(info["buffers"]) > 12 else ""))
    for n in info["notes"]:
        lines.append(f"  note: {n}")
    return lines


def _shape_candidates(waveform, input_shape):
    """Input tensors to try, in the same order as v1.2."""
    if input_shape == "BCT":
        return [waveform.unsqueeze(0)]
    if input_shape == "B1T":
        return [waveform.mean(dim=0, keepdim=True).unsqueeze(0)]
    if input_shape == "CT":
        return [waveform]
    return [waveform.unsqueeze(0), waveform.mean(dim=0, keepdim=True).unsqueeze(0), waveform]


def run_model(model, waveform, input_shape):
    """forward() — identical behaviour to v1.2 (same shape fallbacks)."""
    import torch

    def _unwrap(out):
        if isinstance(out, (tuple, list)):
            out = out[0]
        if out.dim() == 3:
            out = out.squeeze(0)
        elif out.dim() == 1:
            out = out.unsqueeze(0)
        elif out.dim() != 2:
            raise RuntimeError(f"Unexpected model output shape: {out.shape}")
        return out.float().cpu()

    with torch.no_grad():
        last_exc = None
        for inp in _shape_candidates(waveform, input_shape):
            try:
                return _unwrap(model(inp)), list(inp.shape)
            except Exception as e:
                last_exc = e
                if input_shape != "auto":
                    raise
        raise RuntimeError(f"Model forward pass failed on all input shapes.\nLast error: {last_exc}") from last_exc


def run_decode(model, z_np, device):
    """decode() of a [dims, frames] latent. Returns [channels, samples]."""
    import torch
    zt = torch.from_numpy(np.ascontiguousarray(z_np)).unsqueeze(0).to(device)
    with torch.no_grad():
        y = model.decode(zt)
    if isinstance(y, (tuple, list)):
        y = y[0]
    if y.dim() == 3:
        y = y.squeeze(0)
    elif y.dim() == 1:
        y = y.unsqueeze(0)
    return y.float().cpu().numpy()


def run_encode(model, waveform, input_shape):
    """encode() only, for the latent figure. Returns [latent, frames] or None."""
    import torch
    with torch.no_grad():
        for inp in _shape_candidates(waveform, input_shape):
            try:
                z = model.encode(inp)
                if isinstance(z, (tuple, list)):
                    z = z[0]
                if z.dim() == 3:
                    z = z[0]
                if z.dim() == 2:
                    return z.float().cpu().numpy()
            except Exception:
                continue
    return None


# =============================================================================
#  Latent transformations (numpy; z is [dims, frames] as returned by encode())
# =============================================================================

LATENT_OPS = {
    "scale":    "z' = amount * z (all dimensions)",
    "offset":   "z'[d] = z[d] + amount (d = chosen dimension, 0 = all)",
    "dim_gain": "z'[d] = amount * z[d] (one dimension)",
    "mute":     "z'[d] = 0 (one dimension set to zero in the exported latent coordinate system)",
    "isolate":  "only z[d] kept, every other dimension set to 0",
    "smooth":   "moving average along time, every dimension",
    "freeze":   "one latent frame held for a new duration",
    "jitter":   "z' = z + amount * N(0,1), independent per frame (seeded)",
    "none":     "latent unchanged (energy layer only)",
}


def latent_transform(z, op, dim, amount, smooth_ms, freeze_pos, freeze_dur, seed, frame_dt, rep):
    """Pure function of the encoded latent. Returns the transformed copy."""
    D, T = z.shape
    if op in ("dim_gain", "mute", "isolate") and not (1 <= dim <= D):
        raise ValueError(f"{op} needs a dimension between 1 and {D} (this model's latent size); got {dim}")
    if op == "offset" and not (0 <= dim <= D):
        raise ValueError(f"offset dimension must be 0 (all) or 1..{D}; got {dim}")
    zt = z.copy()
    d = dim - 1
    if op == "scale":
        zt = amount * z
        desc = f"all {D} dimensions x {amount:g}"
    elif op == "offset":
        if dim == 0:
            zt = z + amount
            desc = f"all {D} dimensions {amount:+g}"
        else:
            zt[d] = z[d] + amount
            desc = f"dimension {dim} {amount:+g}"
    elif op == "dim_gain":
        zt[d] = amount * z[d]
        desc = f"dimension {dim} x {amount:g}"
    elif op == "mute":
        zt[d] = 0.0
        desc = f"dimension {dim} set to zero (exported latent coordinates)"
    elif op == "isolate":
        zt = np.zeros_like(z)
        zt[d] = z[d]
        desc = f"only dimension {dim} kept"
    elif op == "smooth":
        k = max(1, int(round(smooth_ms / 1000.0 / frame_dt)))
        if k > 1:
            pad_l, pad_r = k // 2, k - 1 - k // 2
            zp = np.pad(z, ((0, 0), (pad_l, pad_r)), mode="edge")
            ker = np.ones(k) / k
            zt = np.stack([np.convolve(row, ker, mode="valid") for row in zp])
        desc = f"moving average over {k} frames ({k * frame_dt * 1000:.0f} ms)"
    elif op == "freeze":
        if not (0.0 <= freeze_pos <= 1.0) or freeze_dur <= 0:
            raise ValueError("freeze needs a position in 0..1 and a duration > 0")
        j = min(T - 1, int(round(freeze_pos * (T - 1))))
        n = max(1, int(round(freeze_dur / frame_dt)))
        zt = np.repeat(z[:, j:j + 1], n, axis=1)
        desc = f"frame {j} of {T} ({j * frame_dt:.3f} s) held for {n} frames ({n * frame_dt:.2f} s)"
        rep["freeze_time"] = round(j * frame_dt, 4)
    elif op == "none":
        desc = "unchanged"
    elif op == "jitter":
        rng = np.random.default_rng(seed)
        zt = z + amount * rng.standard_normal(z.shape)
        desc = f"Gaussian jitter, std {amount:g}, seed {seed}"
    else:
        raise ValueError(f"unknown latent operation {op}")
    rep["latent_op"] = op
    rep["latent_op_desc"] = desc
    rep["latent_rule"] = LATENT_OPS[op]
    rep["latent_dims"] = D
    rep["latent_frames_in"] = T
    rep["latent_frames_out"] = zt.shape[1]
    rep["frame_ms"] = round(frame_dt * 1000, 3)
    return zt.astype(np.float32)


ENERGY_STREAM = 0x45E7      # fixed tag that separates the energy stream


def energy_layer(zt, z_ref, mode, etype, amount, smooth, target, dim, scale, seed, frame_dt, rep):
    """Optional controlled instability AFTER the deterministic transform.

    off      -> nothing (identical result every run)
    seeded   -> variation from `seed` (reproducible)
    fresh    -> a new seed each run; the seed drawn is reported so the
                variation can be reproduced later in seeded mode
    jitter   -> independent noise per frame (grain / instability)
    drift    -> noise low-passed along time, correlation time
                tau = 0.05 s * 100 ** smooth (0.05 s .. 5 s), rescaled to
                unit variance so `amount` keeps its meaning
    relative -> per-dimension std measured on the ENCODED INPUT latent:
                z'[d,t] = z[d,t] + amount * std(z_in[d]) * noise[d,t]
    absolute -> z'[d,t] = z[d,t] + amount * noise[d,t]"""
    if mode == "off":
        rep["energy"] = "off (deterministic)"
        return zt
    if not (0.0 <= amount <= 1.0) or not (0.0 <= smooth <= 1.0):
        raise ValueError("energy amount and smoothness must be between 0 and 1")
    D, T = zt.shape
    if mode == "fresh":
        seed = int.from_bytes(os.urandom(4), "little") % 2147483646 + 1
    # Independent stream: the jitter OPERATION uses default_rng(seed); the
    # energy layer derives its own stream from the same user seed, so one
    # Seed field still reproduces everything while the two noises stay
    # uncorrelated. Fresh and Seeded derive it identically, so a seed reported
    # by a Fresh run reproduces that run in Seeded mode.
    rng = np.random.default_rng([seed, ENERGY_STREAM])
    noise = rng.standard_normal((D, T))
    tau = 0.0
    if etype == "drift":
        tau = 0.05 * (100.0 ** smooth)
        sigma = max(tau / frame_dt, 1e-6)                 # kernel width in frames
        half = int(math.ceil(3 * sigma))
        if half >= 1:
            k = np.exp(-0.5 * (np.arange(-half, half + 1) / sigma) ** 2)
            k /= k.sum()
            noise = np.stack([np.convolve(np.pad(row, half, mode="reflect"), k, mode="valid") for row in noise])
            sd = noise.std(axis=1, keepdims=True)
            noise = noise / np.where(sd > 1e-12, sd, 1.0)
    spread = z_ref.std(axis=1)
    floor = max(float(np.median(spread)) * 0.05, 1e-6)
    per_dim = np.maximum(spread, floor) if scale == "relative" else np.ones(D)
    mask = np.zeros(D)
    if target == "all":
        mask[:] = 1
        tdesc = "all dimensions"
    elif target == "one":
        if not (1 <= dim <= D):
            raise ValueError(f"energy dimension must be 1..{D}; got {dim}")
        mask[dim - 1] = 1
        tdesc = f"dimension {dim}"
    else:
        mask[spread >= np.median(spread)] = 1
        tdesc = "high-variance dimensions " + ",".join(str(i + 1) for i in np.flatnonzero(mask))
    added = (amount * per_dim * mask)[:, None] * noise
    rep["energy"] = (f"{mode} {etype}, amount {amount:g} "
                     f"({'x each dimension spread' if scale == 'relative' else 'latent units'}), "
                     f"{tdesc}" + (f", correlation time {tau:.2f} s" if etype == "drift" else "")
                     + f", seed {seed}")
    rep["energy_seed"] = seed
    rep["energy_mode"] = mode
    rep["energy_added_std"] = " ".join(f"{v:.3f}" for v in added.std(axis=1))
    return (zt + added).astype(np.float32)


def write_latent_csv(path, z, frame_dt, max_rows=800):
    if not path:
        return
    step = max(1, z.shape[1] // max_rows)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        for j in range(0, z.shape[1], step):
            fh.write(f"{j * frame_dt:.5f} " + " ".join(f"{v:.5f}" for v in z[:, j]) + "\n")


# =============================================================================
#  Post-processing
# =============================================================================

def normalise(y, mode, gain_db, report):
    """y: ndarray [channels, samples]. Normalisation first, then gain."""
    peak0 = float(np.max(np.abs(y))) if y.size else 0.0
    rms0 = float(np.sqrt(np.mean(y ** 2))) if y.size else 0.0
    report["raw_peak"], report["raw_rms"] = round(peak0, 6), round(rms0, 6)
    if mode == "peak" and peak0 > 1e-12:
        y = y * (0.99 / peak0)
        report["normalisation"] = f"peak -> 0.99 (x{0.99 / peak0:.4f})"
    elif mode == "rms" and rms0 > 1e-12:
        g = 0.1 / rms0                                     # -20 dBFS
        if peak0 * g > 0.99:
            report["rms_note"] = f"attenuated to keep the peak at 0.99 (RMS ends at " \
                                 f"{20 * math.log10(0.99 / peak0 * rms0):.1f} dBFS)"
            g = 0.99 / peak0
        y = y * g
        report["normalisation"] = f"rms -20 dBFS (x{g:.4f})"
    else:
        report["normalisation"] = "none (model output untouched)"
    if gain_db != 0.0:
        y = y * (10.0 ** (gain_db / 20.0))
    report["gain_db"] = gain_db
    peak = float(np.max(np.abs(y))) if y.size else 0.0
    report["peak"] = round(peak, 6)
    report["rms"] = round(float(np.sqrt(np.mean(y ** 2))) if y.size else 0.0, 6)
    if peak > 1.0:
        report["warning"] = f"peak {peak:.3f} exceeds full scale (float WAV keeps it; playback may clip)"
    return y


def channels(y, out_ch):
    if out_ch == "mono" and y.shape[0] != 1:
        return y.mean(axis=0, keepdims=True)
    if out_ch == "stereo" and y.shape[0] == 1:
        return np.repeat(y, 2, axis=0)
    return y


def write_manifest(path, items):
    if not path:
        return
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(f"version={VERSION}\n")
        for k, v in items:
            fh.write(f"{k}={v}\n")


# =============================================================================
#  Actions
# =============================================================================

def action_diagnose(args, paths):
    out_lines, items = [], []
    for p in paths:
        try:
            model, dev = load_model(p, args.device)
            info = introspect(model)
            out_lines += describe(info, Path(p).name)
            items.append(("model", f"{Path(p).name}|{','.join(info['methods'])}|{info['sr']}|"
                                   f"{info['latent_size']}|{info['compression']}"))
        except Exception as e:
            out_lines += [f"Model: {Path(p).name}", f"  FAILED TO LOAD: {type(e).__name__}: {e}"]
            items.append(("model", f"{Path(p).name}|LOAD FAILED|||"))
        out_lines.append("")
    for ln in out_lines:
        print(ln)
    items += [("report", ln) for ln in out_lines]
    write_manifest(args.manifest, items)


def action_latent(args):
    """Sound -> encode -> transform -> decode -> Sound."""
    import torch
    if not HAS_NUMPY:
        raise RuntimeError("numpy is required (pip install numpy)")
    if not args.input or not args.input.is_file():
        raise FileNotFoundError(f"Input file not found: '{args.input}'")
    x, sr_in = read_wav(args.input)
    model, dev = load_model(args.model, args.device)
    info = introspect(model)
    for ln in describe(info, args.model.name):
        print(ln)
    if "encode" not in info["methods"] or "decode" not in info["methods"]:
        raise RuntimeError(f"{args.model.name} has no encode/decode methods "
                           f"(methods: {', '.join(info['methods'])}); use Process sound instead")
    rep = {"device": dev, "input_sr": sr_in, "model_sr": info["sr"] or "unknown"}
    xm, sr_run = prepare_rate(x, sr_in, info, args, rep)
    wav_t = torch.from_numpy(np.ascontiguousarray(xm)).to(dev)
    z = run_encode(model, wav_t, args.input_shape)
    if z is None:
        raise RuntimeError("encode() failed on every input shape")
    comp = info["compression"] or max(1, int(round(xm.shape[1] / z.shape[1])))
    frame_dt = comp / sr_run
    zt = latent_transform(z, args.latent_op, args.latent_dim, args.latent_amount, args.smooth_ms,
                          args.freeze_pos, args.freeze_dur, args.seed, frame_dt, rep)
    zt = energy_layer(zt, z, args.energy_mode, args.energy_type, args.energy_amount, args.energy_smooth,
                      args.energy_target, args.energy_dim, args.energy_scale, args.seed, frame_dt, rep)
    print(f"Latent: {rep['latent_op_desc']}; energy: {rep['energy']}")
    y = run_decode(model, zt, dev)
    rep["output_raw_shape"] = list(y.shape)
    sr_out = sr_run
    if sr_run != sr_in and args.out_rate == "input":
        y = resample(y, sr_run, sr_in)
        sr_out = sr_in
        rep["sr_handling"] += f"; result resampled back to {sr_in} Hz"
    y = normalise(y, args.normalize, args.gain, rep)
    y = channels(y, args.out_ch)
    rep["output_channels"] = y.shape[0]
    rep["output_sr"] = sr_out
    rep["output_duration"] = round(y.shape[1] / sr_out, 4)
    write_wav_float(args.output, y, sr_out)
    write_latent_csv(args.latent_in_csv, z, frame_dt)
    write_latent_csv(args.latent_csv, zt, frame_dt)
    rep["latent_viz"] = f"encode() latent before (light) and after (solid) the transform: " \
                        f"{z.shape[0]} dims, {frame_dt * 1000:.1f} ms per frame"
    items = list(rep.items()) + [("methods", ",".join(info["methods"])),
                                 ("latent_size", info["latent_size"] or z.shape[0]),
                                 ("compression", comp)]
    items += [("report", ln) for ln in describe(info, args.model.name)]
    write_manifest(args.manifest, items)


def prepare_rate(x, sr_in, info, args, rep):
    sr_model = info["sr"]
    if sr_model and sr_model != sr_in:
        if args.sr_mode == "resample":
            rep["sr_handling"] = f"input resampled {sr_in} -> {sr_model} Hz (model rate)"
            return resample(x, sr_in, sr_model), sr_model
        rep["sr_handling"] = f"MISMATCH kept (v1.2 behaviour): {sr_in} Hz fed to a {sr_model} Hz model"
    elif sr_model:
        rep["sr_handling"] = "input already at the model rate"
    else:
        rep["sr_handling"] = "model rate not declared; input used as is"
    return x, sr_in


def action_process(args):
    import torch
    if not HAS_NUMPY:
        raise RuntimeError("numpy is required for v1.3 processing (pip install numpy)")
    if not args.input or not args.input.is_file():
        raise FileNotFoundError(f"Input file not found: '{args.input}'")
    x, sr_in = read_wav(args.input)
    print(f"Loading audio:  {args.input}  shape {list(x.shape)}  SR {sr_in} Hz")
    model, dev = load_model(args.model, args.device)
    info = introspect(model)
    for ln in describe(info, args.model.name):
        print(ln)
    rep = {"device": dev, "input_sr": sr_in, "model_sr": info["sr"] or "unknown"}

    sr_model = info["sr"]
    xm, sr_run = x, sr_in
    if sr_model and sr_model != sr_in:
        if args.sr_mode == "resample":
            xm, sr_run = resample(x, sr_in, sr_model), sr_model
            rep["sr_handling"] = f"input resampled {sr_in} -> {sr_model} Hz (model rate)"
        else:
            rep["sr_handling"] = f"MISMATCH kept (v1.2 behaviour): {sr_in} Hz fed to a {sr_model} Hz model"
    elif sr_model:
        rep["sr_handling"] = "input already at the model rate"
    else:
        rep["sr_handling"] = "model rate not declared; input used as is"

    wav_t = torch.from_numpy(np.ascontiguousarray(xm)).to(dev)
    print(f"Running forward (input_shape={args.input_shape})...")
    y_t, used_shape = run_model(model, wav_t, args.input_shape)
    y = y_t.numpy()
    rep["input_tensor"] = used_shape
    rep["output_raw_shape"] = list(y.shape)
    sr_out = sr_run
    if sr_run != sr_in and args.out_rate == "input":
        y = resample(y, sr_run, sr_in)
        sr_out = sr_in
        rep["sr_handling"] += f"; result resampled back to {sr_in} Hz"

    y = normalise(y, args.normalize, args.gain, rep)
    y = channels(y, args.out_ch)
    rep["output_channels"] = y.shape[0]
    rep["output_sr"] = sr_out
    rep["output_duration"] = round(y.shape[1] / sr_out, 4)
    write_wav_float(args.output, y, sr_out)
    print(f"Wrote {args.output}  ({y.shape[0]} ch, {sr_out} Hz, float32)")

    if args.latent_viz and "encode" in info["methods"] and args.latent_csv:
        z = run_encode(model, wav_t, args.input_shape)
        if z is not None:
            frame_dt = (info["compression"] / sr_run) if info["compression"] else (x.shape[1] / sr_in) / z.shape[1]
            step = max(1, z.shape[1] // 800)
            with open(args.latent_csv, "w", encoding="utf-8", newline="\n") as fh:
                for j in range(0, z.shape[1], step):
                    fh.write(f"{j * frame_dt:.5f} " + " ".join(f"{v:.5f}" for v in z[:, j]) + "\n")
            rep["latent_viz"] = f"true latent from encode(): {z.shape[0]} dims x {z.shape[1]} frames"
        else:
            rep["latent_viz"] = "encode() exists but could not be run; feature proxy shown instead"
    else:
        rep["latent_viz"] = "model has no encode(); feature proxy shown instead" \
            if "encode" not in info["methods"] else "off"
    items = list(rep.items()) + [("methods", ",".join(info["methods"])),
                                 ("latent_size", info["latent_size"] or ""),
                                 ("compression", info["compression"] or "")]
    items += [("report", ln) for ln in describe(info, args.model.name)]
    write_manifest(args.manifest, items)


def main():
    global _error_file
    args = parse_args()
    if args.error:
        _error_file = str(args.error)
    try:
        print(f"=== RAVE TorchScript runner v{VERSION} ===  action {args.action}")
        if args.action == "diagnose":
            action_diagnose(args, [args.model])
        elif args.action == "latent":
            action_latent(args)
        elif args.action == "diagnose_folder":
            folder = args.models_dir or (args.model.parent if args.model else None)
            if not folder or not Path(folder).is_dir():
                raise FileNotFoundError(f"Models folder not found: '{folder}'")
            paths = sorted(str(p) for p in Path(folder).glob("*.ts"))
            if not paths:
                raise FileNotFoundError(f"No .ts models in '{folder}'")
            action_diagnose(args, paths)
        else:
            action_process(args)
        print("Done.")
        sys.exit(0)
    except Exception as exc:
        _crash(exc)


if __name__ == "__main__":
    main()
