"""
spat_bridge.py  v2.0 -- IRCAM Pan to Binaural, 3-stage Spat5 pipeline

    source WAV --spat5.hoa.encoder~--> HOA WAV --spat5.hoa.decoder~-->
    virtual-speaker WAV --spat5.virtualspeakers~--> binaural WAV

One render per call. Every stage output is ANALYSED: a PCM file with
samples at full scale means that stage clipped, and the Praat side then
re-renders from the source with more attenuation (clipping cannot be
repaired afterwards). Shares its WAV reader / clipping detector with
spat_binaural_bridge.py v1.4 (Multichannel to Binaural).

Called by IRCAM_Pan_to_Binaural.praat (v2.0) via runSubprocess:

    spat_bridge.py <in_wav> <hoa_wav> <spk_wav> <out_wav> <log_file>
                   <tools_dir> <enc_preset> <dec_preset> <layout>
                   <sofa> <itd> <room> <stats_file> <lfe_insert>

    lfe_insert  0  speaker WAV goes to virtualspeakers as decoded
                N  insert a silent channel at position N first (7.1.4:
                   the decoder makes 11 full-range speakers, while the
                   virtualspeakers 7.1.4 layout has the LFE at channel 4)

Exit codes: 0 = rendered and analysed (read the stats file; it may
report clipping); 1 = hard failure (missing binary, Spat5 error, no or
unreadable output).

Stats file (key=value): format, channels, frames, peak_l, peak_r,
rms_l, rms_r, fullscale_l, fullscale_r, maxrun_l, maxrun_r, over_l,
over_r, clipped (any stage), clip_stage (none|encoder|decoder|binaural),
stage_peak_hoa, stage_peak_spk, overshoot, correlation.

Changelog v2.0
  - Clipping analysis of all three stage outputs + stats file (v1.0 ran
    the three tools and checked nothing).
  - Pre-flight check that each executable exists.
  - Silent-LFE insertion for 7.1.4 (see lfe_insert).
  - Log kept on every run; the Praat side deletes it only on success.
"""

import sys
import os
import subprocess
import struct
import math
from array import array

try:
    import numpy as np
except Exception:
    np = None


def log(log_file, text):
    with open(log_file, "a") as f:
        f.write(text)


def run_cmd(cmd, log_file, env):
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


# ---------------------------------------------------------------------------
# WAV writing (for the LFE insertion) -- same format as read
# ---------------------------------------------------------------------------
def write_wav(path, fmt_name, sr, chans):
    nch = len(chans)
    n = len(chans[0])
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
            else:
                u = (q & 0xFFFFFF).astype(np.uint32)
                b = np.empty((u.size, 3), dtype=np.uint8)
                b[:, 0] = u & 0xFF
                b[:, 1] = (u >> 8) & 0xFF
                b[:, 2] = (u >> 16) & 0xFF
                data = b.tobytes()
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


def stage_check(path, label, log_file):
    """Returns (fmt, clipped, peak) for a stage output of any channel count;
    exits 1 if it is missing or unreadable."""
    if not os.path.isfile(path):
        log(log_file, f"\nERROR: {label} output was not created: {path}\n")
        sys.exit(1)
    try:
        name, nch, sr, chans = read_wav(path)
    except Exception as e:
        log(log_file, f"\nERROR: could not read the {label} output: {e}\n")
        sys.exit(1)
    peak = 0.0
    full = 0
    for c in chans:
        st = channel_stats(c, name)
        peak = max(peak, st[0])
        full += st[2]
    clipped = (not name.startswith("float")) and full > 0
    log(log_file, f"{label}: {name}, {nch} ch, peak {db(peak):.2f} dBFS, "
                  f"full-scale samples {full}" + ("  <-- CLIPPED" if clipped else "") + "\n")
    return name, clipped, peak, sr, chans


def main():
    if len(sys.argv) < 15:
        print("Usage: spat_bridge.py <in_wav> <hoa_wav> <spk_wav> <out_wav> <log_file> "
              "<tools_dir> <enc_preset> <dec_preset> <layout> <sofa> <itd> <room> "
              "<stats_file> <lfe_insert>")
        sys.exit(1)
    (in_wav, hoa_wav, spk_wav, out_wav, log_file, tools_dir, enc_preset,
     dec_preset, layout, sofa, itd, room, stats_file, lfe_insert) = sys.argv[1:15]
    lfe_insert = int(float(lfe_insert))

    tools_path = os.path.abspath(tools_dir.strip().rstrip("/\\"))
    spat_pkg_path = os.path.dirname(os.path.dirname(tools_path))
    support_path = os.path.join(spat_pkg_path, "support")
    ext = ".exe" if sys.platform == "win32" else ""
    encoder = os.path.join(tools_path, f"spat5.hoa.encoder~{ext}")
    decoder = os.path.join(tools_path, f"spat5.hoa.decoder~{ext}")
    virtualspeakers = os.path.join(tools_path, f"spat5.virtualspeakers~{ext}")

    with open(log_file, "w") as f:
        f.write("=== Spat5 Pan-to-Binaural Bridge v2.0 ===\n")
        f.write(f"encoder preset: {enc_preset}\ndecoder preset: {dec_preset}\n")
        f.write(f"layout: {layout}  sofa: {sofa}  itd: {itd}  room: {room}  lfe_insert: {lfe_insert}\n")
    for p in (stats_file, hoa_wav, spk_wav, out_wav):
        if os.path.isfile(p):
            os.remove(p)
    for exe in (encoder, decoder, virtualspeakers):
        if not os.path.isfile(exe):
            log(log_file, f"ERROR: not found: {exe}\nCheck the Tools folder in the Praat form.\n")
            sys.exit(1)

    env = os.environ.copy()
    if sys.platform == "win32":
        env["PATH"] = support_path + os.pathsep + env.get("PATH", "")

    clip_stage = "none"
    run_cmd([encoder, "-i", in_wav, "-o", hoa_wav, "-p", enc_preset], log_file, env)
    _, c1, pk_hoa, _, _ = stage_check(hoa_wav, "encoder (HOA)", log_file)
    if c1:
        clip_stage = "encoder"

    run_cmd([decoder, "-i", hoa_wav, "-o", spk_wav, "-p", dec_preset], log_file, env)
    spk_fmt, c2, pk_spk, spk_sr, spk_ch = stage_check(spk_wav, "decoder (speakers)", log_file)
    if c2 and clip_stage == "none":
        clip_stage = "decoder"

    if lfe_insert > 0:
        silent = [0.0] * len(spk_ch[0]) if np is None else np.zeros(len(spk_ch[0]))
        chans = list(spk_ch[: lfe_insert - 1]) + [silent] + list(spk_ch[lfe_insert - 1:])
        write_wav(spk_wav, spk_fmt, spk_sr, chans)
        log(log_file, f"inserted a silent LFE at channel {lfe_insert}: "
                      f"{len(spk_ch)} -> {len(chans)} channels\n")

    run_cmd([virtualspeakers, "-i", spk_wav, "-f", layout, "-o", out_wav,
             "-s", sofa, "-I", itd, "-R", room], log_file, env)
    name, c3, _, _, chans = stage_check(out_wav, "virtualspeakers (binaural)", log_file)
    if len(chans) != 2:
        log(log_file, f"ERROR: expected 2-channel binaural output, got {len(chans)}\n")
        sys.exit(1)
    if c3 and clip_stage == "none":
        clip_stage = "binaural"

    is_float = name.startswith("float")
    sl = channel_stats(chans[0], name)
    sr_ = channel_stats(chans[1], name)
    corr = correlation(chans[0], chans[1])
    clipped = int(clip_stage != "none")
    overshoot = int(is_float and max(sl[0], sr_[0]) > 1.0)
    if clipped:
        log(log_file, f"CLIPPING at the {clip_stage} stage -- re-render with more input attenuation.\n")
    else:
        log(log_file, "\nPan-to-binaural render completed successfully (no clipping at any stage).\n")
    with open(stats_file, "w") as f:
        f.write(f"format={name}\nchannels=2\nframes={len(chans[0])}\n")
        f.write(f"peak_l={sl[0]:.9g}\npeak_r={sr_[0]:.9g}\nrms_l={sl[1]:.9g}\nrms_r={sr_[1]:.9g}\n")
        f.write(f"fullscale_l={sl[2]}\nfullscale_r={sr_[2]}\nmaxrun_l={sl[3]}\nmaxrun_r={sr_[3]}\n")
        f.write(f"over_l={sl[4]}\nover_r={sr_[4]}\n")
        f.write(f"clipped={clipped}\nclip_stage={clip_stage}\n")
        f.write(f"stage_peak_hoa={pk_hoa:.9g}\nstage_peak_spk={pk_spk:.9g}\n")
        f.write(f"overshoot={overshoot}\ncorrelation={corr if corr is not None else 0:.6g}\n")


if __name__ == "__main__":
    main()
