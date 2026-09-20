"""
spat_bformat_bridge.py  v2.4.1 -- ambiX B-format -> Binaural via Spat5

TWO-STAGE pipeline (the input is ALREADY Ambisonic, so it is never encoded):

    Stage 1:  spat5.hoa.decoder~      ambiX B-format -> FULL-RANGE virtual speakers
    (LFE)     7.1.4: silent LFE inserted at its standard slot.
              22.2: decoder produces 22 directional feeds; two silent LFE
              channels are appended at positions 23/24 for Spat5.
    Stage 2:  spat5.virtualspeakers~  loudspeaker feeds -> binaural (SOFA/HRTF)

HOA carries no LFE. v1.8 decoded full-band speakers INTO the LFE slots of
7.1 (channel 4) and 22.2 (channels 4 and 10); for 22.2 those two slots even
had the same directions as BtFL and BtFR, i.e. two duplicated speaker
directions. v2.0 decoded only full-range speakers and inserted silent LFE channels.
A direct 24-channel channel-walk showed that spat5.virtualspeakers~ -f 22.2
maps its first 22 inputs to the directional HRTFs. A subsequent direct render
confirmed that the executable still requires 24 input channels. v2.4.1 therefore
passes 22 directional feeds followed by two silent LFE channels at positions
23/24.

Every stage output is ANALYSED (peak, full-scale samples, flat-top runs):
a PCM file with samples at full scale means that stage clipped; the Praat
side re-renders from the source with more attenuation. A binaural output
SHORTER than the input (beyond 2 samples) is a failure, not a note.

Arguments (positional, from Praat runSubprocess):
     1 bformat_in_wav      2 decoded_speakers_wav   3 binaural_out_wav
     4 log_file            5 tools_dir              6 decoder_preset (OSC list
       or the marker AUTO_22_2_FULLRANGE)           7 layout token
     8 sofa                9 itd                   10 room
    11 expected_speakers   full-range speakers the decoder must produce
    12 detected_order     13 mode (preview|final|selftest)
    14 caller_version     15 stats_file            16 lfe_positions ("0",
       "4": optional 1-based LFE slot for layouts such as 7.1.4; 22.2 passes "0")
    FLBR diagnostic is requested by adding the suffix "_diag" to the existing
       mode argument (for example preview_diag), keeping the v2.2 CLI signature.

Exit 0 = rendered and analysed (read the stats file: it may report
clipping); nonzero = hard failure, reason in the log.

Stats file (key=value): format, frames, in_frames, peak_l, peak_r, rms_l,
rms_r, fullscale_l, fullscale_r, maxrun_l, maxrun_r, over_l, over_r,
clipped, clip_stage (none|decoder|binaural), stage_peak_spk, overshoot,
short_frames, correlation.

Changelog v2.4.1
  - FIX: Spat5 -f 22.2 requires 24 input channels. The decoder's 22 directional
    feeds are now followed by two silent LFE channels at positions 23/24.
    This preserves the empirically verified directional mapping without
    producing the invalid 22-channel file used in v2.4.0.

Changelog v2.4.0
  - Established empirically that the first 22 Spat5 inputs are the 22
    directional HRTF feeds; superseded by v2.4.1 for final 24ch packaging.

Changelog v2.3.3
  - FLBR pre-HRTF diagnostic now has a machine-readable geometric verdict.
    Expected Spat azimuths are Front 0, Left -90, Back 180, Right +90 deg.
    PASS requires maximum wrapped azimuth error <= 20 deg and energy-vector
    magnitude >= 0.10 for every burst. This verdict tests coordinate/decoder
    orientation before HRTF rendering; it is not a binaural localisation score.

Changelog v2.3.1
  - Restored the stable v2.2 command-line signature. FLBR diagnostic is
    encoded in the existing mode argument, avoiding an extra runSubprocess
    positional argument on Praat/Windows.

Changelog v2.3
  - Optional FLBR pre-HRTF diagnostic computes a loudspeaker-energy vector
    for each 0.05-0.85 s burst window, plus the two strongest speaker feeds.
    This isolates HOA decoding from virtualspeakers/HRTF perception.

Changelog v2.2
  - FIX: NaN/Inf are checked on every sample of every stage output. v2.1
    tested the combined peak, but max(0.0, nan) is 0.0 in Python (every
    comparison with NaN is false), so a NaN in the decoded speakers passed.

Changelog v2.1
  - Decoded speakers are validated before virtualspeakers: sample rate
    equal to the input's, no shortening (a later HRTF tail could otherwise
    hide a decoder that dropped samples), no NaN/Inf.

Changelog v2.0
  - Silent LFE insertion (7.1.4: slot 4; 22.2: slots 4 and 10); 22.2 is
    decoded to its 22 full-range speakers (no duplicated directions).
  - Clipping analysis of the decoded speakers AND the binaural output
    (v1.8 checked neither for clipping: a file with 78 % of its samples at
    full scale passed).
  - Output shorter than the input is a failure.
  - L/R correlation is descriptive only (no "looks healthy").
  - Kept from v1.8: version handshake, decoder-preset validation, never-
    encode guard, -p as one argument, help probe on failure.
"""

import sys
import os
import math
import struct
import subprocess
import re
import shlex
from array import array

try:
    import numpy as np
except Exception:
    np = None

BRIDGE_VERSION = "2.4.1"
ORDER_FOR_CHANNELS = {4: 1, 9: 2, 16: 3, 25: 4, 36: 5}
AUTO_22_2_MARKER = "AUTO_22_2_FULLRANGE"

# The 22 FULL-RANGE loudspeakers of 22.2, in token order with the two LFE
# slots (4 = LFE1, 10 = LFE2) removed. Nominal Spat navigation coordinates
# (azimuth, elevation); 0 = front, negative = left, positive = right.
# Order: FL FR FC BL BR FLc FRc BC SiL SiR TpFL TpFR TpFC TpC TpBL TpBR
#        TpSiL TpSiR TpBC BtFC BtFL BtFR
FULLRANGE_22_2_AE = (
    (-45.0,   0.0), ( 45.0,   0.0), (  0.0,   0.0),
    (-135.0,  0.0), (135.0,   0.0), (-30.0,   0.0), ( 30.0,   0.0),
    (180.0,   0.0), (-90.0,   0.0), ( 90.0,   0.0),
    (-45.0,  45.0), ( 45.0,  45.0), (  0.0,  45.0), (  0.0,  90.0),
    (-135.0, 45.0), (135.0,  45.0), (-90.0,  45.0), ( 90.0,  45.0),
    (180.0,  45.0), (  0.0, -30.0), (-45.0, -30.0), ( 45.0, -30.0),
)


def build_22_2_preset(order):
    parts = ["/order %d" % order, "/dimension 3", "/norm SN3D",
             "/method energy-preserving", "/speaker/number 22"]
    for i, (az, el) in enumerate(FULLRANGE_22_2_AE, start=1):
        parts.append("/speaker/%d/ae %.6f %.6f" % (i, az, el))
    return ", ".join(parts)


def channels_for_order(order):
    return (order + 1) ** 2


def log(log_file, msg):
    with open(log_file, "a") as f:
        f.write(msg + "\n")


def fail(log_file, msg, code=1):
    log(log_file, "\nERROR: " + msg)
    sys.exit(code)


def exe_path(tools_path, name):
    """Full path to a spat5 command-line binary, with .exe on Windows."""
    ext = ".exe" if sys.platform == "win32" else ""
    return os.path.join(tools_path, name + ext)


def _osc_int(preset, address):
    """Return the first integer following an OSC address, or None."""
    match = re.search(r"(?:^|[,\s])" + re.escape(address) + r"\s+(-?\d+)(?=$|[,\s])",
                      preset or "")
    return int(match.group(1)) if match else None


def validate_decoder_preset(preset, detected_order, expected_speakers, log_file):
    """
    Validate the OSC command list passed as the decoder's single ``-p`` value.

    Spat5's command-line wrapper does not expect a symbolic name such as
    ``hoa1_cube`` here.  The working Praat/Spat5 pipeline passes one quoted OSC
    command list, for example::

        /order 1, /dimension 3, /norm SN3D,
        /speaker/number 4, /speaker/1/ae -30 0, ...

    The entire string must remain one argv item.  This function catches the
    common failure modes before Spat5 is launched and gives a useful log entry.
    """
    preset = (preset or "").strip()
    if not preset:
        fail(log_file, "decoder preset is empty. Expected one OSC command list "
             "containing /order, /dimension, /norm, /speaker/number and "
             "/speaker/<index>/ae messages.")

    required = ("/order", "/dimension", "/norm", "/speaker/number")
    missing = [address for address in required if address not in preset]
    if missing:
        fail(log_file, "decoder preset is not a complete OSC command list; "
             "missing: %s. Do not enter a symbolic preset name."
             % ", ".join(missing))

    preset_order = _osc_int(preset, "/order")
    if preset_order is None:
        fail(log_file, "decoder preset contains /order but not an integer value.")
    if detected_order >= 0 and preset_order != detected_order:
        fail(log_file, "decoder preset order %d does not match the %d-channel "
             "input (order %d)." %
             (preset_order, channels_for_order(detected_order), detected_order))

    dimension = _osc_int(preset, "/dimension")
    if dimension != 3:
        fail(log_file, "this bridge expects Full-3D Ambisonics; decoder preset "
             "must contain '/dimension 3'.")

    preset_speakers = _osc_int(preset, "/speaker/number")
    if preset_speakers is None or preset_speakers <= 0:
        fail(log_file, "decoder preset must contain a positive /speaker/number.")
    if expected_speakers > 0 and preset_speakers != expected_speakers:
        fail(log_file, "decoder preset declares %d speakers, but layout expects %d."
             % (preset_speakers, expected_speakers))

    for index in range(1, preset_speakers + 1):
        address = "/speaker/%d/ae" % index
        if address not in preset:
            fail(log_file, "decoder preset declares %d speakers but is missing %s."
                 % (preset_speakers, address))

    return preset, preset_order, preset_speakers


def build_decoder_cmd(decoder_exe, in_bformat, out_speakers, preset):
    """
    Stage 1: ``spat5.hoa.decoder~`` — B-format to loudspeaker feeds.

    ``-p`` receives ONE OSC command-list argument.  ``/order`` belongs inside
    that argument; it must not be appended as a separate command-line token.
    This is the same argument shape used by the established three-stage
    Praat/Spat5 bridge.
    """
    return [decoder_exe,
            "-i", in_bformat,
            "-o", out_speakers,
            "-p", preset]

def build_virtualspeakers_cmd(vs_exe, in_speakers, layout, out_binaural,
                              sofa, itd, room):
    """
    Stage 2: spat5.virtualspeakers~  loudspeaker feeds -> binaural.
    Argument shape is identical to the loudspeaker-feed bridge.
    """
    return [vs_exe,
            "-i", in_speakers,
            "-f", layout,
            "-o", out_binaural,
            "-s", sofa,
            "-I", itd,
            "-R", room]


def assert_no_encoder(cmd, log_file):
    """
    Hard guard for the core invariant: this tool must never invoke the HOA
    encoder. The input is already Ambisonic.
    """
    joined = " ".join(cmd).lower()
    if "hoa.encoder" in joined or "encoder~" in joined:
        fail(log_file, "refusing to run: command contains the HOA encoder, "
                       "but this tool must only DECODE an existing B-format.")


def format_cmd(cmd):
    """Human-readable command line for logs; execution still uses argv directly."""
    if sys.platform == "win32":
        return subprocess.list2cmdline(cmd)
    return shlex.join(cmd)


def append_help_probe(executable, log_file, env):
    """Append best-effort command-line help after a failed Spat5 launch."""
    log(log_file, "\n--- Automatic help probe ---")
    for flag in ("--help", "-help", "-h"):
        try:
            result = subprocess.run([executable, flag], stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, env=env,
                                    text=True, errors="replace", timeout=8)
        except subprocess.TimeoutExpired:
            log(log_file, "%s timed out." % flag)
            continue
        except OSError as exc:
            log(log_file, "%s could not be launched: %s" % (flag, exc))
            return
        output = (result.stdout or "").strip()
        log(log_file, "Probe %s (exit %d):" % (flag, result.returncode))
        if output:
            log(log_file, output)
            return
        log(log_file, "(no output)")


def run_cmd(cmd, log_file, env, stage, help_on_failure=False):
    """Run one Spat5 stage, logging the exact argv, output and exit code."""
    assert_no_encoder(cmd, log_file)
    with open(log_file, "a") as f:
        f.write("\n--- %s ---\n" % stage)
        f.write("Running: " + format_cmd(cmd) + "\n")
        f.flush()
        try:
            result = subprocess.run(cmd, stdout=f, stderr=subprocess.STDOUT,
                                    env=env)
        except OSError as exc:
            f.write("Launch error: %s\n" % exc)
            if help_on_failure:
                append_help_probe(cmd[0], log_file, env)
            fail(log_file, "%s could not be launched: %s" % (stage, exc))
        f.write("Exit code: %d\n" % result.returncode)
    if result.returncode != 0:
        if help_on_failure:
            append_help_probe(cmd[0], log_file, env)
        fail(log_file, "%s failed with exit code %d (see log above)."
             % (stage, result.returncode), code=result.returncode or 1)


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


def speaker_geometry_from_preset(preset, lfe_slots):
    """Return final virtualspeakers channel geometry as (az, el) or None for LFE.
    Azimuth follows the Spat navigation convention used in the OSC preset:
    0=front, negative=left, positive=right."""
    n = _osc_int(preset, "/speaker/number") or 0
    num = r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[Ee][-+]?\d+)?"
    coords = []
    for index in range(1, n + 1):
        address = "/speaker/%d/ae" % index
        m = re.search(re.escape(address) + r"\s+(" + num + r")\s+(" + num + r")", preset)
        if not m:
            return None
        coords.append((float(m.group(1)), float(m.group(2))))
    for slot in sorted(lfe_slots):
        coords.insert(slot - 1, None)
    return coords


def flbr_speaker_feed_diagnostic(path, geometry, log_file):
    """Analyse the actual pre-HRTF speaker-feed WAV for the 4 s FLBR test."""
    if not geometry:
        log(log_file, "FLBR diagnostic unavailable: speaker geometry could not be parsed.")
        return []
    try:
        _fmt, nch, sr, chans = read_wav(path)
    except Exception as exc:
        log(log_file, "FLBR diagnostic unavailable: cannot read speaker feeds: %s" % exc)
        return []
    if nch != len(geometry) or not chans:
        log(log_file, "FLBR diagnostic unavailable: geometry/feed channel mismatch (%d vs %d)."
            % (len(geometry), nch))
        return []
    need = int(round(4.0 * sr))
    if min(len(c) for c in chans) < need:
        log(log_file, "FLBR diagnostic unavailable: decoded feed is shorter than 4.0 s.")
        return []

    out = []
    for burst in range(4):
        a = int(round((burst + 0.05) * sr))
        b = int(round((burst + 0.85) * sr))
        powers = []
        for c in chans:
            if np is not None:
                seg = np.asarray(c[a:b], dtype=np.float64)
                power = float(np.mean(seg * seg)) if seg.size else 0.0
            else:
                seg = c[a:b]
                power = (sum(v * v for v in seg) / len(seg)) if seg else 0.0
            powers.append(power)

        sx = sy = sz = total = 0.0
        ranked = []
        for idx, (power, coord) in enumerate(zip(powers, geometry), start=1):
            if coord is None:
                continue
            az, el = coord
            ar = math.radians(az)
            er = math.radians(el)
            ce = math.cos(er)
            sx += power * ce * math.cos(ar)
            sy += power * ce * math.sin(ar)
            sz += power * math.sin(er)
            total += power
            ranked.append((power, idx))
        if total <= 0:
            out.append(dict(az=0.0, el=0.0, mag=0.0, top1=0, top2=0))
            continue
        az = math.degrees(math.atan2(sy, sx))
        el = math.degrees(math.atan2(sz, math.sqrt(sx * sx + sy * sy)))
        mag = math.sqrt(sx * sx + sy * sy + sz * sz) / total
        ranked.sort(reverse=True)
        top1 = ranked[0][1] if ranked else 0
        top2 = ranked[1][1] if len(ranked) > 1 else 0
        out.append(dict(az=az, el=el, mag=mag, top1=top1, top2=top2))

    labels = ("FRONT", "LEFT", "BACK", "RIGHT")
    expected_az = (0.0, -90.0, 180.0, 90.0)
    max_error_allowed = 20.0
    min_magnitude_allowed = 0.10
    errors = []
    for d, expected in zip(out, expected_az):
        err = abs((d["az"] - expected + 180.0) % 360.0 - 180.0)
        d["expected_az"] = expected
        d["az_error"] = err
        errors.append(err)
    max_error = max(errors) if errors else float("inf")
    min_magnitude = min(d["mag"] for d in out) if out else 0.0
    orientation_pass = bool(out) and max_error <= max_error_allowed and min_magnitude >= min_magnitude_allowed

    log(log_file, "\n=== FLBR SPEAKER-FEED DIAGNOSTIC (pre-HRTF) ===")
    log(log_file, "Spat azimuth convention: negative=left, positive=right.")
    for label, d in zip(labels, out):
        log(log_file, "%s: az=%+.2f expected=%+.1f err=%.2f el=%+.2f mag=%.4f top=ch%d/ch%d"
            % (label, d["az"], d["expected_az"], d["az_error"], d["el"],
               d["mag"], d["top1"], d["top2"]))
    log(log_file, "SPEAKER-FEED ORIENTATION: %s (max az error %.2f deg; min magnitude %.3f; limits %.1f deg / %.2f)"
        % ("PASS" if orientation_pass else "FAIL", max_error, min_magnitude,
           max_error_allowed, min_magnitude_allowed))
    return out


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


def db(v):
    return 20 * math.log10(v) if v > 0 else float("-inf")


def stage_peak_clip(path, label, log_file):
    try:
        name, nch, sr, chans = read_wav(path)
    except Exception as e:
        fail(log_file, "cannot read the %s output: %s" % (label, e))
    for c in chans:
        if np is not None:
            finite = bool(np.all(np.isfinite(np.asarray(c))))
        else:
            finite = all(math.isfinite(v) for v in c)
        if not finite:
            fail(log_file, "%s output contains NaN/Inf sample values." % label)
    peak = 0.0
    full = 0
    for c in chans:
        st = channel_stats(c, name)
        peak = max(peak, st[0])
        full += st[2]
    clipped = (not name.startswith("float")) and full > 0
    log(log_file, "%s: %s, %d ch, peak %.2f dBFS, full-scale samples %d%s"
        % (label, name, nch, db(peak), full, "  <-- CLIPPED" if clipped else ""))
    return name, nch, sr, chans, peak, clipped


USAGE = ("Usage: spat_bformat_bridge.py <bformat_in> <decoded_speakers> <binaural_out> "
         "<log> <tools_dir> <decoder_preset> <layout> <sofa> <itd> <room> "
         "<expected_speakers> <detected_order> <mode> <caller_version> <stats_file> "
         "<lfe_positions>")


def main():
    if len(sys.argv) < 17:
        print(USAGE)
        sys.exit(1)
    (bformat_in, decoded_speakers, binaural_out, log_file, tools_dir, decoder_preset,
     layout, sofa, itd, room, expected_spk, detected_order, mode, caller_version,
     stats_file, lfe_arg) = sys.argv[1:17]
    expected_spk = int(expected_spk) if expected_spk.strip().isdigit() else 0
    detected_order = int(detected_order) if detected_order.strip().lstrip("-").isdigit() else -1
    mode = mode.strip().lower()
    diag_flbr = mode.endswith("_diag")
    if diag_flbr:
        mode = mode[:-5]
    lfe_slots = sorted(int(x) for x in lfe_arg.replace(" ", "").split(",") if x not in ("", "0"))

    with open(log_file, "w") as f:
        f.write("=== Spat5 B-format Bridge v%s ===\n" % BRIDGE_VERSION)
        f.write("argc=%d caller=%s\n" % (len(sys.argv), caller_version))
    for p in (stats_file, decoded_speakers, binaural_out):
        if os.path.isfile(p):
            os.remove(p)
    if caller_version.strip() != BRIDGE_VERSION:
        fail(log_file, "bridge version mismatch: caller=%s bridge=%s" %
             (caller_version, BRIDGE_VERSION), code=2)

    tools_path = os.path.abspath(tools_dir.strip().rstrip("/\\"))
    support_path = os.path.join(os.path.dirname(os.path.dirname(tools_path)), "support")
    decoder_exe = exe_path(tools_path, "spat5.hoa.decoder~")
    vs_exe = exe_path(tools_path, "spat5.virtualspeakers~")
    for exe in (decoder_exe, vs_exe):
        if not os.path.isfile(exe):
            fail(log_file, "not found: %s\nCheck the Tools folder in the Praat form." % exe)

    try:
        in_name, in_ch, in_sr, in_chans = read_wav(bformat_in)
    except Exception as e:
        fail(log_file, "cannot read B-format input WAV: %s" % e)
    if in_ch not in ORDER_FOR_CHANNELS:
        fail(log_file, "input has %d channels; need 4, 9, 16, 25 or 36." % in_ch)
    order = ORDER_FOR_CHANNELS[in_ch]
    in_frames = len(in_chans[0])
    log(log_file, "Input: %d ch -> Ambisonic order %d (%d Hz, %d frames, %s)"
        % (in_ch, order, in_sr, in_frames, in_name))

    if decoder_preset.strip() == AUTO_22_2_MARKER:
        decoder_preset = build_22_2_preset(order)
    decoder_preset, preset_order, preset_speakers = validate_decoder_preset(
        decoder_preset, order, expected_spk, log_file)
    log(log_file, "Decoder preset validated: order %d, %d full-range speakers; LFE slots %s"
        % (preset_order, preset_speakers, lfe_slots if lfe_slots else "none"))

    env = os.environ.copy()
    if sys.platform == "win32":
        env["PATH"] = support_path + os.pathsep + env.get("PATH", "")

    # STAGE 1 -- decode (never encode)
    run_cmd(build_decoder_cmd(decoder_exe, bformat_in, decoded_speakers, decoder_preset),
            log_file, env, "STAGE 1: spat5.hoa.decoder~", help_on_failure=True)
    if not os.path.isfile(decoded_speakers):
        fail(log_file, "decoder did not produce %s" % decoded_speakers)
    spk_fmt, n_feeds, spk_sr, spk_ch, pk_spk, clip_dec = stage_peak_clip(
        decoded_speakers, "decoder (speakers)", log_file)
    if spk_sr != in_sr:
        fail(log_file, "decoder output sample rate %d differs from the input's %d." % (spk_sr, in_sr))
    if len(spk_ch[0]) < in_frames - 2:
        fail(log_file, "decoder output is %d samples SHORTER than the input (matrix decoding "
                       "must not lose samples)." % (in_frames - len(spk_ch[0])))
    if math.isnan(pk_spk) or math.isinf(pk_spk):
        fail(log_file, "decoded speaker feeds contain NaN/Inf values.")
    if n_feeds != preset_speakers:
        fail(log_file, "decoder made %d feeds, preset declares %d." % (n_feeds, preset_speakers))
    if n_feeds < channels_for_order(order):
        log(log_file, "WARNING: %d speakers for order %d (%d components) is under-determined."
            % (n_feeds, order, channels_for_order(order)))

    # LFE adaptation for virtualspeakers.
    # Diagnose the decoder output BEFORE delivery-only LFE packaging.
    effective_lfe_slots = list(lfe_slots)
    if layout.strip() == "22.2":
        # External NHK/AES uses LFE at 4 and 10, but the measured Spat5 HRTF
        # mapping places the 22 directional feeds first. Spat5 still requires
        # 24 channels, so append two silent LFE channels at 23/24.
        effective_lfe_slots = []

    diag_results = []
    if diag_flbr:
        diag_geometry = speaker_geometry_from_preset(decoder_preset, effective_lfe_slots)
        diag_results = flbr_speaker_feed_diagnostic(decoded_speakers, diag_geometry, log_file)

    chans = list(spk_ch)
    n = len(chans[0])
    if layout.strip() == "22.2":
        silent1 = np.zeros(n) if np is not None else [0.0] * n
        silent2 = np.zeros(n) if np is not None else [0.0] * n
        chans.extend([silent1, silent2])
        write_wav(decoded_speakers, spk_fmt, spk_sr, chans)
        log(log_file, "22.2 delivery adapter: appended silent LFE1/LFE2 at channels 23/24: 22 -> 24 channels")
    elif effective_lfe_slots:
        for slot in effective_lfe_slots:
            silent = np.zeros(n) if np is not None else [0.0] * n
            chans.insert(slot - 1, silent)
        write_wav(decoded_speakers, spk_fmt, spk_sr, chans)
        log(log_file, "Inserted silent LFE at slot(s) %s: %d -> %d channels"
            % (",".join(str(s) for s in effective_lfe_slots), n_feeds, len(chans)))

    # STAGE 2 -- binaural
    run_cmd(build_virtualspeakers_cmd(vs_exe, decoded_speakers, layout, binaural_out,
                                      sofa, itd, room),
            log_file, env, "STAGE 2: spat5.virtualspeakers~", help_on_failure=True)
    if not os.path.isfile(binaural_out):
        fail(log_file, "virtualspeakers did not produce %s" % binaural_out)
    name, nch, osr, chans, _, clip_bin = stage_peak_clip(binaural_out, "virtualspeakers (binaural)", log_file)
    if nch != 2:
        fail(log_file, "expected 2-channel binaural output, got %d." % nch)
    frames = len(chans[0])
    if frames == 0:
        fail(log_file, "binaural output has no frames.")
    if osr != in_sr:
        fail(log_file, "binaural output sample rate %d differs from the input's %d." % (osr, in_sr))
    short = max(0, in_frames - frames)
    if short > 2:
        log(log_file, "FAILURE: the binaural output is %d samples SHORTER than the input." % short)

    sl = channel_stats(chans[0], name)
    sr_ = channel_stats(chans[1], name)
    for side, st in (("L", sl), ("R", sr_)):
        bad = any(math.isnan(v) or math.isinf(v) for v in (st[0], st[1]))
        if bad:
            fail(log_file, "binaural output contains NaN/Inf values.")
    if max(sl[1], sr_[1]) < 1e-6:
        fail(log_file, "binaural output is silent.")
    corr = correlation(chans[0], chans[1])
    clip_stage = "decoder" if clip_dec else ("binaural" if clip_bin else "none")
    clipped = int(clip_stage != "none")
    overshoot = int(name.startswith("float") and max(sl[0], sr_[0]) > 1.0)
    if corr is not None:
        log(log_file, "L/R correlation %.3f (descriptive only)" % corr)
    if clipped:
        log(log_file, "CLIPPING at the %s stage -- re-render with more input attenuation." % clip_stage)
    elif short <= 2:
        log(log_file, "\nBinaural render completed successfully (no clipping at any stage).")
    with open(stats_file, "w") as f:
        f.write("format=%s\nframes=%d\nin_frames=%d\n" % (name, frames, in_frames))
        f.write("peak_l=%.9g\npeak_r=%.9g\nrms_l=%.9g\nrms_r=%.9g\n" % (sl[0], sr_[0], sl[1], sr_[1]))
        f.write("fullscale_l=%d\nfullscale_r=%d\nmaxrun_l=%d\nmaxrun_r=%d\n" % (sl[2], sr_[2], sl[3], sr_[3]))
        f.write("over_l=%d\nover_r=%d\n" % (sl[4], sr_[4]))
        f.write("clipped=%d\nclip_stage=%s\nstage_peak_spk=%.9g\n" % (clipped, clip_stage, pk_spk))
        f.write("overshoot=%d\nshort_frames=%d\n" % (overshoot, short))
        f.write("correlation=%.6g\n" % (corr if corr is not None else 0))
        diag_valid = len(diag_results) == 4
        f.write("diag_valid=%d\n" % (1 if diag_valid else 0))
        if diag_valid:
            diag_max_err = max(d.get("az_error", 999.0) for d in diag_results)
            diag_min_mag = min(d.get("mag", 0.0) for d in diag_results)
            diag_pass = diag_max_err <= 20.0 and diag_min_mag >= 0.10
            f.write("diag_pass=%d\n" % (1 if diag_pass else 0))
            f.write("diag_max_az_error=%.9g\n" % diag_max_err)
            f.write("diag_min_magnitude=%.9g\n" % diag_min_mag)
        else:
            f.write("diag_pass=0\ndiag_max_az_error=nan\ndiag_min_magnitude=nan\n")
        for i, d in enumerate(diag_results, start=1):
            f.write("diag_b%d_az=%.9g\n" % (i, d["az"]))
            f.write("diag_b%d_expected_az=%.9g\n" % (i, d.get("expected_az", 0.0)))
            f.write("diag_b%d_az_error=%.9g\n" % (i, d.get("az_error", 999.0)))
            f.write("diag_b%d_el=%.9g\n" % (i, d["el"]))
            f.write("diag_b%d_mag=%.9g\n" % (i, d["mag"]))
            f.write("diag_b%d_top1=%d\n" % (i, d["top1"]))
            f.write("diag_b%d_top2=%d\n" % (i, d["top2"]))


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as exc:
        target = sys.argv[4] if len(sys.argv) > 4 else None
        if target:
            try:
                with open(target, "a") as f:
                    f.write("\nFATAL BRIDGE EXCEPTION: %s: %s\n" % (type(exc).__name__, exc))
            except OSError:
                pass
        raise
