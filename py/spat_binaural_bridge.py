"""
spat_binaural_bridge.py — Multichannel-to-Binaural via Spat5

Single-stage pipeline: takes a multichannel WAV with a speaker layout
descriptor and renders binaural via spat5.virtualspeakers~.

Called by Multichannel_to_Binaural.praat via runSubprocess.
"""

import sys
import os
import subprocess
import struct
import math
import wave


def run_cmd(cmd, log_file, env):
    """Runs a command and appends output to the log file."""
    with open(log_file, "a") as f:
        f.write(f"\nRunning: {' '.join(cmd)}\n")
        result = subprocess.run(cmd, stdout=f, stderr=subprocess.STDOUT, env=env)
        if result.returncode != 0:
            f.write(f"\nFAILED with exit code {result.returncode}\n")
            sys.exit(1)


def assert_stereo_wav(path, log_file):
    """
    Verifies the output WAV exists, is 2-channel stereo, and has
    meaningfully different L and R channels.

    Checks (all using stdlib only -- no numpy required):
      1. File exists
      2. Opens as a valid WAV
      3. Exactly 2 channels
      4. Non-empty (frames > 0)
      5. Per-channel RMS -- both channels carry signal
      6. L/R cross-correlation -- warns if channels are effectively dual-mono

    Exits with code 1 on hard failures (1-4).
    Logs a WARNING for soft issues (5-6) but does not exit, so the caller
    can still import the file and inspect it in Praat.
    """
    if not os.path.isfile(path):
        with open(log_file, "a") as f:
            f.write(f"\nERROR: Output file was not created: {path}\n")
        sys.exit(1)

    try:
        with wave.open(path, "rb") as w:
            n_channels = w.getnchannels()
            frame_rate = w.getframerate()
            n_frames   = w.getnframes()
            samp_width = w.getsampwidth()   # bytes per sample
            raw        = w.readframes(n_frames)
    except wave.Error as e:
        with open(log_file, "a") as f:
            f.write(f"\nERROR: Could not open output WAV: {e}\n")
        sys.exit(1)

    with open(log_file, "a") as f:
        f.write(f"\nOutput check -- channels: {n_channels}, "
                f"sr: {frame_rate} Hz, frames: {n_frames}, "
                f"bit depth: {samp_width * 8}\n")

    if n_channels != 2:
        with open(log_file, "a") as f:
            f.write(f"ERROR: Expected 2-channel stereo, got {n_channels} channel(s).\n")
        sys.exit(1)

    if n_frames == 0:
        with open(log_file, "a") as f:
            f.write("ERROR: Output file contains no audio frames.\n")
        sys.exit(1)

    # --- Decode interleaved samples into L and R lists ---
    # Supports 16-bit (most common) and 24-bit; falls back gracefully.
    left, right = [], []
    if samp_width == 2:
        # 16-bit signed, little-endian
        fmt = f"<{n_frames * 2}h"
        samples = struct.unpack(fmt, raw)
        left  = samples[0::2]
        right = samples[1::2]
        scale = 32768.0
    elif samp_width == 3:
        # 24-bit: no direct struct format, unpack manually
        for i in range(n_frames):
            base   = i * 6
            l_bytes = raw[base:base + 3]
            r_bytes = raw[base + 3:base + 6]
            # Sign-extend 24-bit to 32-bit
            lv = struct.unpack("<i", l_bytes + (b'\xff' if l_bytes[2] & 0x80 else b'\x00'))[0]
            rv = struct.unpack("<i", r_bytes + (b'\xff' if r_bytes[2] & 0x80 else b'\x00'))[0]
            left.append(lv)
            right.append(rv)
        scale = 8388608.0
    else:
        # 32-bit float or other -- skip correlation check
        with open(log_file, "a") as f:
            f.write(f"NOTE: Skipping L/R analysis for {samp_width*8}-bit WAV "
                    f"(only 16/24-bit supported without numpy).\n")
        return

    n = len(left)

    # --- Per-channel RMS ---
    rms_l = math.sqrt(sum(x * x for x in left)  / n) / scale
    rms_r = math.sqrt(sum(x * x for x in right) / n) / scale

    def to_db(rms):
        return 20 * math.log10(rms) if rms > 0 else float("-inf")

    with open(log_file, "a") as f:
        f.write(f"L RMS: {to_db(rms_l):.1f} dBFS    "
                f"R RMS: {to_db(rms_r):.1f} dBFS\n")

    SILENCE_THRESHOLD = 1e-6   # ~-120 dBFS
    if rms_l < SILENCE_THRESHOLD:
        with open(log_file, "a") as f:
            f.write("WARNING: Left channel is silent or near-silent.\n")
    if rms_r < SILENCE_THRESHOLD:
        with open(log_file, "a") as f:
            f.write("WARNING: Right channel is silent or near-silent.\n")

    # --- L/R cross-correlation at zero lag (Pearson r) ---
    # Cap sample count so this stays fast for long files.
    MAX_SAMPLES = 441000   # ~10 s at 44.1 kHz
    n_check = min(n, MAX_SAMPLES)
    lc = list(left[:n_check])
    rc = list(right[:n_check])

    mean_l = sum(lc) / n_check
    mean_r = sum(rc) / n_check
    lc = [x - mean_l for x in lc]
    rc = [x - mean_r for x in rc]

    num   = sum(a * b for a, b in zip(lc, rc))
    den_l = math.sqrt(sum(x * x for x in lc))
    den_r = math.sqrt(sum(x * x for x in rc))
    denom = den_l * den_r

    if denom == 0:
        with open(log_file, "a") as f:
            f.write("WARNING: Cannot compute L/R correlation (zero-energy channel).\n")
        return

    correlation = num / denom

    label = ('first ' + str(n_check) + ' samples') if n_check < n else 'full file'
    with open(log_file, "a") as f:
        f.write(f"L/R correlation: {correlation:.4f}  ({label})\n")

        if correlation > 0.999:
            f.write(
                "WARNING: L and R are effectively identical (dual-mono). "
                "Likely causes: wrong layout token, mono/fully-correlated source, "
                "or Spat5 rendering with no meaningful angular spread.\n"
            )
        elif correlation > 0.95:
            f.write(
                "NOTE: L/R are highly correlated. Output may sound centered. "
                "Check layout token and source channel assignments.\n"
            )
        else:
            f.write("L/R channels are decorrelated -- stereo image looks healthy.\n")


def main():
    if len(sys.argv) < 8:
        print("Error: Missing arguments")
        print("Usage: spat_binaural_bridge.py <in_wav> <out_wav> <log_file> "
              "<tools_dir> <layout> <sofa> <itd> [room]")
        sys.exit(1)

    in_wav    = sys.argv[1]
    out_wav   = sys.argv[2]
    log_file  = sys.argv[3]
    tools_dir = sys.argv[4]
    layout    = sys.argv[5]
    sofa      = sys.argv[6]
    itd       = sys.argv[7]
    room      = sys.argv[8] if len(sys.argv) > 8 else "none"

    # Normalise tools_dir: strip trailing whitespace and slashes, then
    # resolve to an absolute path with OS-native separators.
    tools_path    = os.path.abspath(tools_dir.strip().rstrip("/\\"))
    spat_pkg_path = os.path.dirname(os.path.dirname(tools_path))
    support_path  = os.path.join(spat_pkg_path, "support")

    ext = ".exe" if sys.platform == "win32" else ""
    virtualspeakers = os.path.join(tools_path, f"spat5.virtualspeakers~{ext}")

    # Open the log first so every subsequent check can write to it.
    with open(log_file, "w") as f:
        f.write("=== Spat5 Binaural Bridge ===\n")
        f.write(f"Input:        {in_wav}\n")
        f.write(f"Output:       {out_wav}\n")
        f.write(f"Layout:       {layout}\n")
        f.write(f"SOFA:         {sofa}\n")
        f.write(f"ITD:          {itd}\n")
        f.write(f"Room:         {room}\n")
        f.write(f"tools_dir raw:{tools_dir!r}\n")
        f.write(f"tools_path:   {tools_path}\n")
        f.write(f"binary:       {virtualspeakers}\n")
        f.write(f"support:      {support_path}\n\n")

    # Pre-flight: make sure the binary actually exists before trying to
    # launch it -- gives a clear error instead of a cryptic WinError 2.
    if not os.path.isfile(virtualspeakers):
        with open(log_file, "a") as f:
            f.write(f"ERROR: spat5.virtualspeakers~ not found at:\n"
                    f"  {virtualspeakers}\n\n"
                    f"Check that the Tools Folder in the Praat form points to\n"
                    f"the directory that contains spat5.virtualspeakers~{ext}.\n")
        sys.exit(1)

    custom_env = os.environ.copy()
    if sys.platform == "win32":
        custom_env["PATH"] = support_path + os.pathsep + custom_env.get("PATH", "")

    # Single stage: multichannel -> binaural via virtual speakers
    run_cmd([virtualspeakers,
             "-i", in_wav,
             "-f", layout,
             "-o", out_wav,
             "-s", sofa,
             "-I", itd,
             "-R", room],
            log_file, custom_env)

    # Verify the output is valid 2-channel stereo with real L/R content
    assert_stereo_wav(out_wav, log_file)

    with open(log_file, "a") as f:
        f.write("\nBinaural render completed successfully.\n")


if __name__ == "__main__":
    main()
