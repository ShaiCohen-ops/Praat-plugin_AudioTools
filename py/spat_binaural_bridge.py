"""
spat_binaural_bridge.py  v1.5.1 -- Multichannel-to-Binaural via Spat5

One render per call: multichannel WAV + speaker-layout token ->
spat5.virtualspeakers~ -> binaural WAV, followed by an output ANALYSIS
that the Praat side uses to decide whether to accept the render or to
re-render with more input attenuation.

Called by IRCAM_Multichannel_to_Binaural.praat (v1.5.1) via runSubprocess:

    spat_binaural_bridge.py <in_wav> <out_wav> <log_file> <tools_dir>
                            <layout> <sofa> <itd> <room> <stats_file>

Exit codes
    0  render ran and the output could be analysed (clipped or not --
       read the stats file)
    1  hard failure (binary missing, Spat5 error, no/invalid output)

Stats file (key=value, one per line), e.g.
    format=pcm16          pcm16 | pcm24 | pcm32 | float32 | float64
    channels=2
    frames=441000
    peak_l=0.912  peak_r=0.874           (linear, 1.0 = full scale)
    rms_l=...  rms_r=...
    fullscale_l=0 fullscale_r=0          samples at/above full scale
    maxrun_l=0  maxrun_r=0               longest run of consecutive ones
    over_l=0    over_r=0                 float only: samples with |x| > 1
    clipped=0                            1 = hard (PCM) clipping, re-render
    overshoot=0                          1 = float peak > 1: NOT clipped,
                                             recoverable by scaling down
    correlation=0.43

Changelog v1.5.1
  - FIX: Spat5 virtualspeakers -f 22.2 requires 24 input channels. External
    NHK/AES 24ch is therefore REORDERED, not reduced: the 22 directional
    channels are placed first, followed by LFE1 and LFE2 at channels 23/24.
    The empirical channel walk showed that inputs 1..22 map to the 22 HRTF
    directions while inputs 23/24 are the non-directional LFE positions.

Changelog v1.5.0
  - Superseded adapter experiment: removed LFE slots 4 and 10, producing
    22 channels. Spat5 rejects that file for -f 22.2; v1.5.1 corrects this.

Changelog v1.4
  - NEW: peak / full-scale / flat-top-run / crest analysis. v1.3 checked
    only RMS and L/R correlation, so a file with 78 % of its samples at
    full scale was reported as "stereo image looks healthy".
  - NEW: machine-readable stats file for the Praat safe-render loop.
  - NEW: own RIFF reader: PCM 16/24/32 and IEEE float 32/64, including
    WAVE_FORMAT_EXTENSIBLE (Python's wave module rejects float WAV).
  - Correlation is reported as a descriptive number only. A frontal
    source renders highly correlated and a diffuse scene less so; it is
    not a measure of a "healthy" binaural image.
  - "completed successfully" is written only when no clipping was found.
"""

import sys
import os
import subprocess
import struct
import math
from array import array

try:
    import numpy as np  # optional: speeds up analysis of long files
except Exception:       # pragma: no cover
    np = None


def log(log_file, text):
    with open(log_file, "a") as f:
        f.write(text)


def run_cmd(cmd, log_file, env):
    """Runs a command, appends its output to the log; exits 1 on failure."""
    log(log_file, f"\nRunning: {' '.join(cmd)}\n")
    with open(log_file, "a") as f:
        result = subprocess.run(cmd, stdout=f, stderr=subprocess.STDOUT, env=env)
    if result.returncode != 0:
        log(log_file, f"\nFAILED with exit code {result.returncode}\n")
        sys.exit(1)


# ---------------------------------------------------------------------------
# WAV reading (stdlib only; numpy used when available)
# ---------------------------------------------------------------------------
def read_wav(path):
    """Returns (fmt_name, n_channels, sample_rate, channels) where channels
    is a list of per-channel sequences of floats scaled so that 1.0 is
    full scale (PCM) or the stored value (float)."""
    with open(path, "rb") as f:
        data = f.read()
    if len(data) < 12 or data[0:4] not in (b"RIFF", b"RF64") or data[8:12] != b"WAVE":
        raise ValueError("not a RIFF/WAVE file")
    pos = 12
    fmt = None
    pcm = None
    while pos + 8 <= len(data):
        cid = data[pos:pos + 4]
        size = struct.unpack("<I", data[pos + 4:pos + 8])[0]
        body = data[pos + 8:pos + 8 + size]
        if cid == b"fmt ":
            tag, nch, sr, _br, _ba, bits = struct.unpack("<HHIIHH", body[:16])
            if tag == 0xFFFE and len(body) >= 26:
                tag = struct.unpack("<H", body[24:26])[0]   # sub-format GUID
            fmt = (tag, nch, sr, bits)
        elif cid == b"data":
            pcm = body
        pos += 8 + size + (size & 1)
    if fmt is None or pcm is None:
        raise ValueError("missing fmt or data chunk")
    tag, nch, sr, bits = fmt
    width = bits // 8
    n = len(pcm) // (width * nch)
    pcm = pcm[: n * width * nch]

    if tag == 1 and bits == 16:
        name, scale = "pcm16", 32768.0
        if np is not None:
            flat = np.frombuffer(pcm, dtype="<i2").astype(np.float64)
        else:
            flat = array("h"); flat.frombytes(pcm)
            if sys.byteorder == "big":
                flat.byteswap()
    elif tag == 1 and bits == 24:
        name, scale = "pcm24", 8388608.0
        if np is not None:
            b = np.frombuffer(pcm, dtype=np.uint8).reshape(-1, 3).astype(np.int32)
            v = b[:, 0] | (b[:, 1] << 8) | (b[:, 2] << 16)
            flat = np.where(v >= 0x800000, v - 0x1000000, v).astype(np.float64)
        else:
            flat = [int.from_bytes(pcm[i:i + 3], "little", signed=True)
                    for i in range(0, len(pcm), 3)]
    elif tag == 1 and bits == 32:
        name, scale = "pcm32", 2147483648.0
        if np is not None:
            flat = np.frombuffer(pcm, dtype="<i4").astype(np.float64)
        else:
            flat = array("i"); flat.frombytes(pcm)
            if sys.byteorder == "big":
                flat.byteswap()
    elif tag == 3 and bits in (32, 64):
        name, scale = ("float32", 1.0) if bits == 32 else ("float64", 1.0)
        code = "<f4" if bits == 32 else "<f8"
        if np is not None:
            flat = np.frombuffer(pcm, dtype=code).astype(np.float64)
        else:
            flat = array("f" if bits == 32 else "d"); flat.frombytes(pcm)
            if sys.byteorder == "big":
                flat.byteswap()
    else:
        raise ValueError(f"unsupported WAV format tag {tag}, {bits} bit")

    chans = []
    for c in range(nch):
        if np is not None:
            chans.append(np.asarray(flat[c::nch]) / scale)
        else:
            chans.append([x / scale for x in flat[c::nch]])
    return name, nch, sr, chans


def write_wav(path, fmt_name, sr, chans):
    """Write channels using the input WAV's numeric format."""
    nch = len(chans)
    n = len(chans[0]) if nch else 0
    if fmt_name.startswith("float"):
        tag, bits = 3, (32 if fmt_name == "float32" else 64)
    else:
        tag, bits = 1, int(fmt_name[3:])
    width = bits // 8
    if np is not None:
        inter = np.vstack([np.asarray(c, dtype=np.float64) for c in chans]).T.reshape(-1)
        if tag == 3:
            data = inter.astype("<f4" if bits == 32 else "<f8").tobytes()
        else:
            full = float(2 ** (bits - 1))
            q = np.clip(np.round(inter * full), -full, full - 1).astype(np.int64)
            if bits == 16:
                data = q.astype("<i2").tobytes()
            elif bits == 32:
                data = q.astype("<i4").tobytes()
            elif bits == 24:
                u = (q & 0xFFFFFF).astype(np.uint32)
                b = np.empty((u.size, 3), dtype=np.uint8)
                b[:, 0] = u & 0xFF
                b[:, 1] = (u >> 8) & 0xFF
                b[:, 2] = (u >> 16) & 0xFF
                data = b.tobytes()
            else:
                raise ValueError("unsupported PCM bit depth %d" % bits)
    else:
        parts = []
        full = float(2 ** (bits - 1))
        for i in range(n):
            for c in range(nch):
                v = chans[c][i]
                if tag == 3:
                    parts.append(struct.pack("<f" if bits == 32 else "<d", v))
                else:
                    q = int(max(-full, min(full - 1, round(v * full))))
                    parts.append(q.to_bytes(width, "little", signed=True))
        data = b"".join(parts)
    ba = nch * width
    hdr = (b"RIFF" + struct.pack("<I", 36 + len(data)) + b"WAVE" + b"fmt "
           + struct.pack("<IHHIIHH", 16, tag, nch, sr, sr * ba, ba, bits)
           + b"data" + struct.pack("<I", len(data)))
    with open(path, "wb") as f:
        f.write(hdr + data)


def prepare_virtualspeaker_input(in_wav, out_wav, layout, log_file):
    """Adapt external channel order to the 24-channel order expected by Spat5."""
    if layout.strip() != "22.2":
        return in_wav, None
    fmt, nch, sr, chans = read_wav(in_wav)
    if nch != 24:
        raise ValueError("Spat5 layout 22.2 requires 24 input channels; got %d" % nch)
    # External NHK/AES order:
    #   1 FL, 2 FR, 3 FC, 4 LFE1, 5 BL, 6 BR, 7 FLc, 8 FRc,
    #   9 BC, 10 LFE2, 11 SiL, 12 SiR, 13..24 remaining directional feeds.
    # Empirical Spat5 order:
    #   22 directional feeds contiguously, then LFE1, LFE2 at positions 23,24.
    order = [0, 1, 2, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 16, 17,
             18, 19, 20, 21, 22, 23, 3, 9]
    temp = os.path.splitext(out_wav)[0] + "_22spat_input.wav"
    if os.path.isfile(temp):
        os.remove(temp)
    write_wav(temp, fmt, sr, [chans[i] for i in order])
    log(log_file, "22.2 adapter: NHK/AES 24ch -> Spat 24ch; reordered to 22 directional feeds + LFE1/LFE2 at channels 23/24.\n")
    return temp, temp


FULL_SCALE = {  # the top positive code of each PCM format, as a fraction
    "pcm16": 32767 / 32768,
    "pcm24": 8388607 / 8388608,
    "pcm32": 2147483647 / 2147483648,
}


def channel_stats(x, fmt_name):
    """peak, rms, full-scale count, longest full-scale run, count |x|>1.
    A PCM sample counts as full scale at the top positive code or the
    bottom code (a clipped render sits exactly there); tiny tolerance for
    the float conversion."""
    is_float = fmt_name.startswith("float")
    fs = 1.0 if is_float else FULL_SCALE[fmt_name] - 1e-12
    if np is not None:
        a = np.abs(np.asarray(x))
        n = a.size
        peak = float(a.max()) if n else 0.0
        rms = float(np.sqrt(np.mean(np.asarray(x) ** 2))) if n else 0.0
        hit = a >= fs
        full = int(hit.sum())
        over = int((a > 1.0).sum())
        maxrun = 0
        if full:
            d = np.diff(np.concatenate(([0], hit.astype(np.int8), [0])))
            starts = np.where(d == 1)[0]
            ends = np.where(d == -1)[0]
            maxrun = int((ends - starts).max())
        return peak, rms, full, maxrun, over
    peak = 0.0
    ss = 0.0
    full = over = run = maxrun = 0
    for v in x:
        a = v if v >= 0 else -v
        if a > peak:
            peak = a
        ss += v * v
        if a >= fs:
            full += 1
            run += 1
            if run > maxrun:
                maxrun = run
        else:
            run = 0
        if a > 1.0:
            over += 1
    n = len(x)
    return peak, (math.sqrt(ss / n) if n else 0.0), full, maxrun, over


def correlation(l, r, cap=441000):
    n = min(len(l), len(r), cap)
    if n < 2:
        return None
    if np is not None:
        a = np.asarray(l[:n]); b = np.asarray(r[:n])
        a = a - a.mean(); b = b - b.mean()
        den = math.sqrt(float((a * a).sum()) * float((b * b).sum()))
        return float((a * b).sum()) / den if den > 0 else None
    ml = sum(l[:n]) / n
    mr = sum(r[:n]) / n
    num = dl = dr = 0.0
    for i in range(n):
        x = l[i] - ml
        y = r[i] - mr
        num += x * y
        dl += x * x
        dr += y * y
    den = math.sqrt(dl * dr)
    return num / den if den > 0 else None


def db(v):
    return 20 * math.log10(v) if v > 0 else float("-inf")


def analyse_output(path, log_file, stats_file):
    """Validates the render and writes the stats file. Exits 1 only on
    hard failures (missing / unreadable / not stereo / empty)."""
    if not os.path.isfile(path):
        log(log_file, f"\nERROR: Output file was not created: {path}\n")
        sys.exit(1)
    try:
        name, nch, sr, chans = read_wav(path)
    except Exception as e:
        log(log_file, f"\nERROR: Could not read output WAV: {e}\n")
        sys.exit(1)
    frames = len(chans[0]) if chans else 0
    log(log_file, f"\nOutput: {name}, {nch} ch, {sr} Hz, {frames} frames\n")
    if nch != 2:
        log(log_file, f"ERROR: Expected 2-channel binaural output, got {nch}.\n")
        sys.exit(1)
    if frames == 0:
        log(log_file, "ERROR: Output file contains no audio frames.\n")
        sys.exit(1)

    is_float = name.startswith("float")
    sl = channel_stats(chans[0], name)
    sr_ = channel_stats(chans[1], name)
    corr = correlation(chans[0], chans[1])

    clipped = int((not is_float) and (sl[2] > 0 or sr_[2] > 0))
    overshoot = int(is_float and max(sl[0], sr_[0]) > 1.0)

    for side, st in (("L", sl), ("R", sr_)):
        peak, rms, full, maxrun, over = st
        crest = db(peak / rms) if rms > 0 and peak > 0 else float("nan")
        log(log_file,
            f"{side}: peak {db(peak):6.2f} dBFS  RMS {db(rms):6.2f} dBFS  "
            f"crest {crest:5.1f} dB  full-scale samples {full} "
            f"({100.0 * full / frames:.3f} %), longest run {maxrun}"
            + (f", |x|>1: {over}" if is_float else "") + "\n")
    if corr is not None:
        log(log_file, f"L/R correlation {corr:.3f} (descriptive only: frontal "
                      f"sources correlate highly, diffuse scenes less)\n")
    if clipped:
        log(log_file, "CLIPPING: full-scale samples in a PCM output -- the render "
                      "clipped. Re-render with more input attenuation.\n")
    elif overshoot:
        log(log_file, "OVERSHOOT: float output peaks above 1.0. Not clipped (float "
                      "keeps the values); scale down in Praat.\n")
    else:
        log(log_file, "\nBinaural render completed successfully (no clipping).\n")

    with open(stats_file, "w") as f:
        f.write(f"format={name}\nchannels={nch}\nframes={frames}\nrate={sr}\n")
        f.write(f"peak_l={sl[0]:.9g}\npeak_r={sr_[0]:.9g}\n")
        f.write(f"rms_l={sl[1]:.9g}\nrms_r={sr_[1]:.9g}\n")
        f.write(f"fullscale_l={sl[2]}\nfullscale_r={sr_[2]}\n")
        f.write(f"maxrun_l={sl[3]}\nmaxrun_r={sr_[3]}\n")
        f.write(f"over_l={sl[4]}\nover_r={sr_[4]}\n")
        f.write(f"clipped={clipped}\novershoot={overshoot}\n")
        f.write(f"correlation={corr if corr is not None else 0:.6g}\n")


def main():
    if len(sys.argv) < 10:
        print("Usage: spat_binaural_bridge.py <in_wav> <out_wav> <log_file> "
              "<tools_dir> <layout> <sofa> <itd> <room> <stats_file>")
        sys.exit(1)
    in_wav, out_wav, log_file, tools_dir, layout, sofa, itd, room, stats_file = sys.argv[1:10]

    tools_path = os.path.abspath(tools_dir.strip().rstrip("/\\"))
    spat_pkg_path = os.path.dirname(os.path.dirname(tools_path))
    support_path = os.path.join(spat_pkg_path, "support")
    ext = ".exe" if sys.platform == "win32" else ""
    virtualspeakers = os.path.join(tools_path, f"spat5.virtualspeakers~{ext}")

    with open(log_file, "w") as f:
        f.write("=== Spat5 Binaural Bridge v1.5.0 ===\n")
        f.write(f"Input:   {in_wav}\nOutput:  {out_wav}\nLayout:  {layout}\n")
        f.write(f"SOFA:    {sofa}\nITD:     {itd}\nRoom:    {room}\n")
        f.write(f"binary:  {virtualspeakers}\nsupport: {support_path}\n")
    if os.path.isfile(stats_file):
        os.remove(stats_file)
    if os.path.isfile(out_wav):
        os.remove(out_wav)

    if not os.path.isfile(virtualspeakers):
        log(log_file, f"ERROR: spat5.virtualspeakers~ not found at:\n  {virtualspeakers}\n"
                      f"Check the Tools folder in the Praat form.\n")
        sys.exit(1)

    env = os.environ.copy()
    if sys.platform == "win32":
        env["PATH"] = support_path + os.pathsep + env.get("PATH", "")

    adapted_input = in_wav
    temp_input = None
    try:
        adapted_input, temp_input = prepare_virtualspeaker_input(in_wav, out_wav, layout, log_file)
        run_cmd([virtualspeakers, "-i", adapted_input, "-f", layout, "-o", out_wav,
                 "-s", sofa, "-I", itd, "-R", room], log_file, env)
        analyse_output(out_wav, log_file, stats_file)
    finally:
        if temp_input and os.path.isfile(temp_input):
            os.remove(temp_input)


if __name__ == "__main__":
    main()
