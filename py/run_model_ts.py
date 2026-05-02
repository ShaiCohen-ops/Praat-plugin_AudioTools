#!/usr/bin/env python3
# ============================================================
# Praat AudioTools Plugin
# Script:      run_model_ts.py
# Description:
#   Loads a TorchScript .ts model and processes an input WAV,
#   writing the result to an output WAV.
#
# Audio I/O uses stdlib wave + array (no torchaudio required).
#
# Usage (called by Praat):
#   python run_model_ts.py --input in.wav --output out.wav --model model.ts
#       [--error err.txt] [--gain 0.0] [--normalize peak|rms|none]
#       [--input_shape auto|BCT|B1T|CT] [--out_ch auto|mono|stereo]
# ============================================================

import sys
import traceback
import argparse
import wave
import array as _array
import math
from pathlib import Path

# ---- Top-level error trap -----------------------------------------------
_error_file = None

def _crash(exc):
    tb  = traceback.format_exc()
    msg = f"{type(exc).__name__}: {exc}\n\n{tb}"
    if _error_file:
        try:
            with open(_error_file, 'w', encoding='utf-8') as f:
                f.write(msg)
        except Exception:
            pass
    print(msg, file=sys.stderr)
    sys.exit(1)

# -------------------------------------------------------------------------

def parse_args():
    parser = argparse.ArgumentParser(
        description="Run a TorchScript audio model on a WAV file."
    )
    parser.add_argument("--input",       required=True,  type=Path,
                        help="Path to input WAV file.")
    parser.add_argument("--output",      required=True,  type=Path,
                        help="Path to write output WAV file.")
    parser.add_argument("--model",       required=True,  type=Path,
                        help="Path to TorchScript .ts model file.")
    parser.add_argument("--error",       required=False, type=Path,   default=None,
                        help="Path to write error traceback (read by Praat).")
    parser.add_argument("--gain",        required=False, type=float,  default=0.0,
                        help="Output gain in dB (default: 0.0).")
    parser.add_argument("--normalize",   required=False, type=str,    default="peak",
                        choices=["none", "peak", "rms"],
                        help="Output normalization mode (default: peak).")
    parser.add_argument("--input_shape", required=False, type=str,    default="auto",
                        choices=["auto", "BCT", "B1T", "CT"],
                        help="Model input tensor shape (default: auto).")
    parser.add_argument("--out_ch",      required=False, type=str,    default="auto",
                        choices=["auto", "mono", "stereo"],
                        help="Output channel count (default: auto).")
    return parser.parse_args()


# ---- Audio I/O via stdlib wave (same approach as arranger.py) -----------

def load_wav_to_tensor(path: Path):
    """
    Read a WAV file using stdlib wave.
    Returns (waveform, sample_rate) where waveform is a torch.Tensor
    of shape [channels, samples], dtype float32, range [-1, 1].
    """
    import torch

    with wave.open(str(path), 'rb') as w:
        nch = w.getnchannels()
        sw  = w.getsampwidth()
        sr  = w.getframerate()
        n   = w.getnframes()
        raw = w.readframes(n)

    if sw == 2:
        arr   = _array.array('h', raw)
        scale = 1.0 / 32768.0
    elif sw == 4:
        arr   = _array.array('i', raw)
        scale = 1.0 / 2_147_483_648.0
    elif sw == 1:
        arr   = _array.array('B', raw)
        floats = [(s - 128) / 128.0 for s in arr]
        tensor = torch.tensor(floats, dtype=torch.float32)
        if nch == 1:
            return tensor.unsqueeze(0), sr
        return torch.stack([tensor[c::nch] for c in range(nch)]), sr
    else:
        raise RuntimeError(f"Unsupported WAV sample width: {sw} bytes")

    floats = [s * scale for s in arr]

    if nch == 1:
        tensor = torch.tensor(floats, dtype=torch.float32).unsqueeze(0)
    else:
        tensor = torch.stack([
            torch.tensor(floats[c::nch], dtype=torch.float32)
            for c in range(nch)
        ])

    return tensor, sr


def save_tensor_to_wav(path: Path, waveform, sample_rate: int):
    """
    Write a [channels, samples] float32 tensor to a 16-bit PCM WAV file.
    Same approach as arranger.py _write_stereo_wav.
    """
    nch = waveform.shape[0]
    n   = waveform.shape[1]

    il = _array.array('h')
    for i in range(n):
        for c in range(nch):
            v = float(waveform[c, i])
            v = max(-1.0, min(1.0, v))
            il.append(int(v * 32767))

    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), 'wb') as w:
        w.setnchannels(nch)
        w.setsampwidth(2)
        w.setframerate(sample_rate)
        w.writeframes(il.tobytes())


# ---- Model ------------------------------------------------------------------

def load_model(path: Path):
    """Load a TorchScript model from a .ts file."""
    try:
        import torch
    except ImportError:
        raise RuntimeError(
            "torch is not installed. Install with: pip install torch"
        )
    if not path.is_file():
        raise FileNotFoundError(f"Model file not found: '{path}'")
    model = torch.jit.load(str(path), map_location="cpu")
    model.eval()
    return model


def run_model(model, waveform, input_shape: str):
    """
    Run the model on the waveform tensor.

    input_shape controls the tensor shape passed to the model:
      auto  — try BCT, then B1T, then CT
      BCT   — [1, channels, samples]
      B1T   — [1, 1, samples]  (force mono)
      CT    — [channels, samples]  (no batch dim)

    Returns the output as a [channels, samples] float32 tensor.
    """
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
        if input_shape == "BCT":
            return _unwrap(model(waveform.unsqueeze(0)))

        elif input_shape == "B1T":
            mono = waveform.mean(dim=0, keepdim=True).unsqueeze(0)
            return _unwrap(model(mono))

        elif input_shape == "CT":
            return _unwrap(model(waveform))

        else:  # auto
            last_exc = None
            for inp in [
                waveform.unsqueeze(0),                              # BCT
                waveform.mean(dim=0, keepdim=True).unsqueeze(0),   # B1T
                waveform,                                           # CT
            ]:
                try:
                    return _unwrap(model(inp))
                except Exception as e:
                    last_exc = e
            raise RuntimeError(
                f"Model forward pass failed on all input shapes.\nLast error: {last_exc}"
            ) from last_exc


# ---- Post-processing --------------------------------------------------------

def apply_gain(waveform, gain_db: float):
    """Apply gain in dB."""
    if gain_db == 0.0:
        return waveform
    factor = 10.0 ** (gain_db / 20.0)
    return waveform * factor


def normalize_output(waveform, mode: str):
    """
    Normalize output waveform.
      none  — only hard-clip
      peak  — scale so peak = 1.0 (only attenuate if > 1.0)
      rms   — scale to -20 dBFS RMS target
    """
    TARGET_RMS = 10.0 ** (-20.0 / 20.0)   # -20 dBFS

    if mode == "peak":
        peak = waveform.abs().max()
        if peak > 1.0:
            waveform = waveform / peak

    elif mode == "rms":
        rms = waveform.pow(2).mean().sqrt()
        if rms > 1e-8:
            waveform = waveform * (TARGET_RMS / rms)

    waveform = waveform.clamp(-1.0, 1.0)
    return waveform


def apply_output_channels(waveform, out_ch: str):
    """Convert waveform to the requested channel count."""
    nch = waveform.shape[0]

    if out_ch == "mono" and nch != 1:
        waveform = waveform.mean(dim=0, keepdim=True)
    elif out_ch == "stereo" and nch == 1:
        waveform = waveform.repeat(2, 1)

    return waveform


# ---- Entry point ------------------------------------------------------------

def main():
    global _error_file
    args = parse_args()

    if args.error:
        _error_file = str(args.error)

    try:
        if not args.input.is_file():
            raise FileNotFoundError(f"Input file not found: '{args.input}'")

        print(f"Loading audio:  {args.input}")
        waveform, sample_rate = load_wav_to_tensor(args.input)
        print(f"  Shape: {list(waveform.shape)}  SR: {sample_rate} Hz")

        print(f"Loading model:  {args.model}")
        model = load_model(args.model)

        print(f"Running model (input_shape={args.input_shape})...")
        output = run_model(model, waveform, args.input_shape)
        print(f"  Output shape: {list(output.shape)}")

        if args.gain != 0.0:
            print(f"Applying gain:  {args.gain:+.1f} dB")
            output = apply_gain(output, args.gain)

        print(f"Normalizing:    {args.normalize}")
        output = normalize_output(output, args.normalize)

        output = apply_output_channels(output, args.out_ch)
        print(f"Output channels: {output.shape[0]} ({args.out_ch})")

        print(f"Writing output: {args.output}")
        save_tensor_to_wav(args.output, output, sample_rate)

        print("Done.")
        sys.exit(0)

    except Exception as exc:
        _crash(exc)


if __name__ == "__main__":
    main()
