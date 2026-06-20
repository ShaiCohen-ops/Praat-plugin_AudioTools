#!/usr/bin/env python3
# ============================================================
# Praat AudioTools - neural_vocoder_engine.py
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 2.4 (2026) - Model caching + honest latent-op naming + CPU patch
#                        + torch_hub_cache relocated to Praat prefs root
# ============================================================
#
# NOTE ON THE LATENT OPERATIONS (what the parameters actually do):
#   --temp  : scales the MAGNITUDE of the HuBERT-Soft unit vectors
#             (units * temp). This is NOT sampling temperature - the
#             pipeline is deterministic. >1 pushes units brighter/off-
#             manifold; <1 pulls them toward the origin.
#   --quant : rounds the continuous SOFT units to q levels
#             (round(units*q)/q). A bitcrush on the units, NOT real
#             codebook/VQ quantization (HuBERT-Soft has no codebook).
#   --noise : adds Gaussian noise to the units (honest).
#
# The pipeline is speech-trained (HuBERT-Soft -> acoustic model ->
# HiFi-GAN) and runs at 16 kHz internally, so output is band-limited
# to 8 kHz regardless of source. On non-speech material it "speech-ifies"
# the input - often a useful creative effect, not a general vocoder.
# ============================================================

import os
import sys
import torch
import argparse
import warnings
import traceback
import numpy as np

# Suppress warnings from cluttering the Praat execution trace
warnings.filterwarnings("ignore")

# ============================================================================
# CRITICAL CPU DESERIALIZATION PATCH (Restored)
# Forces every deserialization attempt to route to CPU safely.
# ============================================================================
if not torch.cuda.is_available():
    orig_torch_load = torch.load
    def patched_torch_load(f, map_location=None, *args, **kwargs):
        return orig_torch_load(f, map_location='cpu', *args, **kwargs)
    torch.load = patched_torch_load

def main():
    # --------------------------------------------------------
    # 1. PARSE COMMAND LINE ARGUMENTS
    # --------------------------------------------------------
    parser = argparse.ArgumentParser(description="Universal 3-Stage Neural Resynthesis Engine")
    parser.add_argument('--input', type=str, required=True)
    parser.add_argument('--output', type=str, required=True)
    parser.add_argument('--temp', type=float, default=1.0)
    parser.add_argument('--quant', type=int, default=0)
    parser.add_argument('--noise', type=float, default=0.0)
    args = parser.parse_args()

    if not os.path.exists(args.input):
        sys.exit(1)

    # --------------------------------------------------------
    # 2. SETUP HARDWARE ARCHITECTURE & LOAD MODELS
    # --------------------------------------------------------
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    
    import soundfile as sf
    import torchaudio.transforms as T

    # Pin a stable torch.hub cache directory so the models download ONCE
    # and are reused on every subsequent run (instead of relying on the
    # default per-user cache, which can vary by launch environment). After
    # the first successful run the script works offline.
    #
    # Cache lives two levels above this script (py/ -> plugin_AudioTools/
    # -> Praat prefs root), e.g. C:\Users\User\Praat\torch_hub_cache,
    # so it's shared across the whole plugin rather than buried in py/.
    script_dir = os.path.dirname(os.path.abspath(__file__))
    prefs_root = os.path.dirname(os.path.dirname(script_dir))
    hub_cache = os.path.join(prefs_root, "torch_hub_cache")
    try:
        os.makedirs(hub_cache, exist_ok=True)
        torch.hub.set_dir(hub_cache)
    except Exception:
        pass  # fall back to default cache if the dir isn't writable

    # Load 3-stage models. force_reload=False uses the cached copy when
    # present (default), so only the first run needs the network. If that
    # first download fails, surface a clear, actionable message.
    try:
        hubert = torch.hub.load("bshall/hubert:main", "hubert_soft",
                                trust_repo=True, force_reload=False).to(device)
        acoustic = torch.hub.load("bshall/acoustic-model:main", "hubert_soft",
                                  trust_repo=True, force_reload=False).to(device)
        vocoder = torch.hub.load("bshall/hifigan:main", "hifigan_hubert_soft",
                                 trust_repo=True, force_reload=False).to(device)
    except Exception as e:
        sys.stderr.write(
            "Model load failed. The first run downloads the bshall hubert / "
            "acoustic-model / hifigan models from GitHub and needs internet "
            "access; after that it works from cache (" + hub_cache + ").\n"
            "Underlying error: " + repr(e) + "\n")
        sys.exit(2)

    hubert.eval()
    acoustic.eval()
    vocoder.eval()

    # Load audio using the proven SoundFile & TorchAudio method
    data, sr = sf.read(args.input)
    if len(data.shape) > 1:
        data = np.mean(data, axis=1) # Force mono
        
    waveform = torch.from_numpy(data).float().unsqueeze(0)

    # Resample to 16000Hz if needed
    TARGET_SR = 16000
    if sr != TARGET_SR:
        resampler = T.Resample(orig_freq=sr, new_freq=TARGET_SR)
        waveform = resampler(waveform)

    wav_tensor = waveform.unsqueeze(0).to(device) # Shape must be [1, 1, samples]

    # --------------------------------------------------------
    # 3. INTERCEPT AND ALTER THE LATENT UNITS VECTOR
    # --------------------------------------------------------
    with torch.no_grad():
        # A. Extract hidden representations
        units = hubert.units(wav_tensor)
        
        # --- APPLY PARAMETERS PASSED FROM THE PRAAT INTERFACE ---

        # 1. Unit-gain scaling (scales unit-vector MAGNITUDE; not sampling temp)
        if args.temp != 1.0:
            units = units * args.temp

        # 2. Gaussian noise injection on the units
        if args.noise > 0.0:
            noise = torch.randn_like(units) * args.noise
            units = units + noise

        # 3. Soft-unit rounding (bitcrush on continuous units; not VQ/codebook)
        if args.quant > 0:
            units = torch.round(units * args.quant) / args.quant

        # --------------------------------------------------------
        # 4. ACOUSTIC MAP GENERATION & WAVEFORM GENERATION
        # --------------------------------------------------------
        mel = acoustic.generate(units).transpose(1, 2)
        output_tensor = vocoder(mel)
        
        output_wav = output_tensor.squeeze().cpu().numpy()

    # --------------------------------------------------------
    # 5. WORKSPACE DISK EXPORT
    # --------------------------------------------------------
    sf.write(args.output, output_wav, TARGET_SR, subtype='PCM_16')

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        # If it ever fails again, it will write the exact reason to "crash_log.txt" 
        # so you can see exactly what line broke!
        script_dir = os.path.dirname(os.path.abspath(__file__))
        crash_path = os.path.join(script_dir, "crash_log.txt")
        with open(crash_path, "w") as f:
            f.write(traceback.format_exc())
        sys.exit(1)