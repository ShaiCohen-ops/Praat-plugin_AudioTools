"""
spat_bformat_bridge_v1_8.py — ambiX B-format -> Binaural via Spat5

TWO-STAGE pipeline (the input is ALREADY Ambisonic):

    Stage 1:  spat5.hoa.decoder~      ambiX B-format   -> virtual loudspeaker feeds
    Stage 2:  spat5.virtualspeakers~  loudspeaker feeds -> binaural stereo (SOFA/HRTF)

This bridge NEVER calls spat5.hoa.encoder~. The selected Praat Sound is an
already-encoded B-format master, so re-encoding it would be wrong.

Companion of ambiX_Bformat_to_Binaural.praat v1.8 (invoked via runSubprocess).
Installed filename: spat_bformat_bridge.py.
Sibling of spat_binaural_bridge.py (the loudspeaker-feed tool). Do NOT confuse
the two workflows:

    loudspeaker tool : speaker feeds ->                virtualspeakers -> binaural
    THIS tool        : B-format      -> HOA decoder -> virtualspeakers -> binaural

Everything is stdlib-only (no numpy). Validation of the final stereo output is
done by manually parsing the WAV header so both PCM and IEEE-float files are
handled (Praat exports 32-bit float, Spat5 may emit float too).

Argument list (all positional, passed as strings by Praat):

     1  bformat_in_wav        interleaved ambiX B-format WAV (ACN / SN3D)
     2  decoded_speakers_wav  Stage-1 output (virtual loudspeaker feeds)
     3  binaural_out_wav      Stage-2 output (2-ch binaural)
     4  log_file              text log
     5  tools_dir             folder holding the spat5.* command-line binaries
     6  decoder_preset        complete comma-separated OSC command list for -p
     7  layout                virtual loudspeaker layout token or file
     8  sofa                  SOFA/HRTF token or file
     9  itd                   ITD option (e.g. percentage as string)
    10  room                  room / direct-sound option (e.g. "none")
    11  expected_speakers     integer; number of speakers the layout expects,
                              or "0" to let the bridge look it up / skip strict check
    12  detected_order        Ambisonic order Praat detected (for cross-check / log)
    13  mode                  "preview" | "final" | "selftest"
    14  caller_version        must equal this bridge version (prevents stale-file use)
"""

import sys
import os
import math
import struct
import subprocess
import re

BRIDGE_VERSION = "1.8"
import shlex


# ----------------------------------------------------------------------------
# Ambisonic bookkeeping
# ----------------------------------------------------------------------------

# channel count -> full-3D Ambisonic order.  (order+1)^2 channels for Full 3D.
ORDER_FOR_CHANNELS = {4: 1, 9: 2, 16: 3, 25: 4, 36: 5}

# Known layout token -> number of loudspeaker positions it produces.
# Used only when Praat passes expected_speakers == 0 (unknown). These are the
# tokens this toolchain assumes; adjust to match your Spat5 install if needed.
KNOWN_LAYOUT_SPEAKERS = {
    "mono": 1, "2.0": 2, "3.0": 3, "4.0": 4, "5.0": 5, "5.1": 6,
    "6.0": 6, "7.0": 7, "7.1": 8, "7.1.2": 10, "7.1.4": 12,
    "octagon": 8, "cube": 8, "8.0": 8,
    "dodeca12": 12, "icosahedron": 12, "12.0": 12,
    "22.2": 24, "24.0": 24,
    "t-design-36": 36, "36.0": 36,
    "t-design-50": 50, "50.0": 50,
}

# Compact marker used by the Praat front-end for third-order Auto mode.
AUTO_3D24_MARKER = "AUTO_3D24_22_2_SN3D"

# Nominal Spat navigation coordinates (azimuth, elevation) for the 24-channel
# 22.2 layout. Convention: 0=front, negative=left, positive=right, +elevation=up.
# Channel order follows the established 22.2 token used by the existing
# IRCAM_Multichannel_to_Binaural tool: FL, FR, FC, LFE1, BL, BR, FLc, FRc,
# BC, LFE2, SiL, SiR, TpFL, TpFR, TpFC, TpC, TpBL, TpBR, TpSiL, TpSiR,
# TpBC, BtFC, BtFL, BtFR.
AUTO_3D24_22_2_AE = (
    (-45.0,   0.0), ( 45.0,   0.0), (  0.0,   0.0), (-45.0, -30.0),
    (-135.0,  0.0), (135.0,   0.0), (-30.0,   0.0), ( 30.0,   0.0),
    (180.0,   0.0), ( 45.0, -30.0), (-90.0,   0.0), ( 90.0,   0.0),
    (-45.0,  45.0), ( 45.0,  45.0), (  0.0,  45.0), (  0.0,  90.0),
    (-135.0, 45.0), (135.0,  45.0), (-90.0,  45.0), ( 90.0,  45.0),
    (180.0,  45.0), (  0.0, -30.0), (-45.0, -30.0), ( 45.0, -30.0),
)


def build_auto_3d24_preset():
    """Return the full decoder OSC preset matching Spat5's built-in 22.2 layout."""
    parts = [
        "/order 3", "/dimension 3", "/norm SN3D",
        "/method energy-preserving", "/speaker/number 24",
    ]
    for index, (azimuth, elevation) in enumerate(AUTO_3D24_22_2_AE, start=1):
        parts.append("/speaker/%d/ae %.6f %.6f" %
                     (index, azimuth, elevation))
    return ", ".join(parts)


def resolve_decoder_preset(value, layout, detected_order, expected_speakers):
    """Expand compact presets while keeping ordinary OSC presets unchanged."""
    if value == AUTO_3D24_MARKER:
        if detected_order != 3:
            raise ValueError("%s requires third-order input" % AUTO_3D24_MARKER)
        if expected_speakers != 24:
            raise ValueError("%s requires expected_speakers=24" % AUTO_3D24_MARKER)
        if layout != "22.2":
            raise ValueError("%s requires virtualspeakers layout 22.2" % AUTO_3D24_MARKER)
        return build_auto_3d24_preset()
    return value


def channels_for_order(order):
    """Full-3D channel count for a given order: (order+1)^2."""
    return (order + 1) ** 2


# ----------------------------------------------------------------------------
# Logging
# ----------------------------------------------------------------------------

def log(log_file, msg):
    """Append one line to the log file (created fresh by main())."""
    with open(log_file, "a") as f:
        f.write(msg + "\n")


def fail(log_file, msg, code=1):
    """Log an ERROR and exit non-zero. Never fabricates a success."""
    log(log_file, "ERROR: " + msg)
    sys.exit(code)


def cleanup_stale_temp_files(folder, keep_paths):
    """Remove only stale files created by this tool's exact temp prefixes."""
    prefixes = ("bformat_input_", "decoded_speakers_", "binaural_output_", "bformat_log_")
    keep = {os.path.abspath(path) for path in keep_paths}
    removed = []
    try:
        names = os.listdir(folder)
    except OSError:
        return removed
    for name in names:
        if not name.startswith(prefixes):
            continue
        path = os.path.abspath(os.path.join(folder, name))
        if path in keep or not os.path.isfile(path):
            continue
        try:
            os.remove(path)
            removed.append(path)
        except OSError:
            pass
    return removed


# ----------------------------------------------------------------------------
# Minimal, format-aware WAV header parser (handles PCM + IEEE float + EXTENSIBLE)
# ----------------------------------------------------------------------------

FMT_PCM = 0x0001
FMT_FLOAT = 0x0003
FMT_EXTENSIBLE = 0xFFFE


def parse_wav_header(path):
    """
    Parse a RIFF/WAVE header without the stdlib `wave` module so that both PCM
    and IEEE-float payloads are supported.

    Returns a dict:
        format_code, n_channels, sample_rate, bits, block_align,
        n_frames, data_offset, data_size
    Raises ValueError on anything that is not a readable RIFF/WAVE file.
    """
    with open(path, "rb") as f:
        riff = f.read(12)
        if len(riff) < 12 or riff[0:4] != b"RIFF" or riff[8:12] != b"WAVE":
            raise ValueError("not a RIFF/WAVE file")

        fmt = None
        data_offset = None
        data_size = None

        while True:
            hdr = f.read(8)
            if len(hdr) < 8:
                break
            chunk_id = hdr[0:4]
            chunk_size = struct.unpack("<I", hdr[4:8])[0]
            chunk_start = f.tell()

            if chunk_id == b"fmt ":
                raw = f.read(chunk_size)
                (audio_format, n_channels, sample_rate, _byte_rate,
                 block_align, bits) = struct.unpack("<HHIIHH", raw[:16])
                # WAVE_FORMAT_EXTENSIBLE: real format lives in the subformat GUID.
                if audio_format == FMT_EXTENSIBLE and len(raw) >= 40:
                    sub = struct.unpack("<H", raw[24:26])[0]
                    audio_format = sub
                fmt = dict(format_code=audio_format, n_channels=n_channels,
                           sample_rate=sample_rate, block_align=block_align,
                           bits=bits)
            elif chunk_id == b"data":
                data_offset = chunk_start
                data_size = chunk_size

            # Chunks are word-aligned; skip to the next one (+pad byte).
            f.seek(chunk_start + chunk_size + (chunk_size & 1))

        if fmt is None or data_offset is None:
            raise ValueError("missing fmt or data chunk")

        block_align = fmt["block_align"] or (fmt["n_channels"] * (fmt["bits"] // 8))
        n_frames = data_size // block_align if block_align else 0

        return dict(format_code=fmt["format_code"],
                    n_channels=fmt["n_channels"],
                    sample_rate=fmt["sample_rate"],
                    bits=fmt["bits"],
                    block_align=block_align,
                    n_frames=n_frames,
                    data_offset=data_offset,
                    data_size=data_size)


def _sample_decoder(format_code, bits):
    """
    Return (unpack_fn(frame_bytes_for_one_channel), scale, is_float) for the
    given WAV sample format. unpack_fn maps raw bytes for ONE sample to a signed
    int/float; dividing by `scale` yields a value in roughly [-1, 1].
    """
    if format_code == FMT_FLOAT and bits == 32:
        return (lambda b: struct.unpack("<f", b)[0]), 1.0, True
    if format_code == FMT_FLOAT and bits == 64:
        return (lambda b: struct.unpack("<d", b)[0]), 1.0, True
    if format_code == FMT_PCM and bits == 16:
        return (lambda b: struct.unpack("<h", b)[0]), 32768.0, False
    if format_code == FMT_PCM and bits == 24:
        def _u24(b):
            v = struct.unpack("<i", b + (b"\xff" if b[2] & 0x80 else b"\x00"))[0]
            return v
        return _u24, 8388608.0, False
    if format_code == FMT_PCM and bits == 32:
        return (lambda b: struct.unpack("<i", b)[0]), 2147483648.0, False
    raise ValueError("unsupported WAV sample format code=%d bits=%d"
                     % (format_code, bits))


def analyse_stereo_output(path, log_file):
    """
    Stream the 2-channel binaural output and compute, in one pass and with
    bounded memory:
        - peak (max |sample|, normalized)
        - per-channel RMS
        - NaN / Inf presence (float formats only)
        - zero-lag L/R correlation on a capped prefix
    Returns a dict of results. Only reads sample data (never rewrites the file).
    """
    hdr = parse_wav_header(path)
    n_ch = hdr["n_channels"]
    if n_ch != 2:
        fail(log_file, "expected 2-channel binaural output, got %d channel(s)" % n_ch)

    bytes_per_sample = hdr["bits"] // 8
    decode, scale, is_float = _sample_decoder(hdr["format_code"], hdr["bits"])
    block_align = hdr["block_align"]
    n_frames = hdr["n_frames"]

    peak = 0.0
    sumsq_l = 0.0
    sumsq_r = 0.0
    has_nan = False
    has_inf = False

    # Buffer a capped prefix for the L/R correlation (kept small & fast).
    MAX_CORR = 441000  # ~10 s @ 44.1 kHz
    corr_l = []
    corr_r = []

    FRAMES_PER_BLOCK = 65536
    with open(path, "rb") as f:
        f.seek(hdr["data_offset"])
        frames_left = n_frames
        while frames_left > 0:
            take = min(FRAMES_PER_BLOCK, frames_left)
            raw = f.read(take * block_align)
            if len(raw) < take * block_align:
                take = len(raw) // block_align
                if take == 0:
                    break
            for i in range(take):
                base = i * block_align
                lb = raw[base:base + bytes_per_sample]
                rb = raw[base + bytes_per_sample:base + 2 * bytes_per_sample]
                lv = decode(lb) / scale
                rv = decode(rb) / scale
                if is_float:
                    if lv != lv or rv != rv:           # NaN check
                        has_nan = True
                        continue
                    if math.isinf(lv) or math.isinf(rv):
                        has_inf = True
                        continue
                a = lv if lv >= 0 else -lv
                b = rv if rv >= 0 else -rv
                if a > peak:
                    peak = a
                if b > peak:
                    peak = b
                sumsq_l += lv * lv
                sumsq_r += rv * rv
                if len(corr_l) < MAX_CORR:
                    corr_l.append(lv)
                    corr_r.append(rv)
            frames_left -= take

    n = max(n_frames, 1)
    rms_l = math.sqrt(sumsq_l / n)
    rms_r = math.sqrt(sumsq_r / n)

    # Zero-lag Pearson correlation on the buffered prefix.
    correlation = None
    m = len(corr_l)
    if m > 1:
        ml = sum(corr_l) / m
        mr = sum(corr_r) / m
        num = sum((corr_l[i] - ml) * (corr_r[i] - mr) for i in range(m))
        dl = math.sqrt(sum((x - ml) ** 2 for x in corr_l))
        dr = math.sqrt(sum((x - mr) ** 2 for x in corr_r))
        if dl > 0 and dr > 0:
            correlation = num / (dl * dr)

    return dict(n_frames=n_frames, sample_rate=hdr["sample_rate"],
                bits=hdr["bits"], format_code=hdr["format_code"],
                peak=peak, rms_l=rms_l, rms_r=rms_r,
                has_nan=has_nan, has_inf=has_inf, correlation=correlation)


# ----------------------------------------------------------------------------
# Command construction (centralized so the encoder can NEVER creep in)
# ----------------------------------------------------------------------------

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


# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------

USAGE = ("Usage: spat_bformat_bridge.py <bformat_in> <decoded_speakers> "
         "<binaural_out> <log> <tools_dir> <decoder_preset> <layout> <sofa> "
         "<itd> <room> <expected_speakers> <detected_order> <mode> <caller_version>")


def main():
    if len(sys.argv) < 15:
        print("Error: Missing arguments")
        print(USAGE)
        sys.exit(1)

    bformat_in       = sys.argv[1]
    decoded_speakers = sys.argv[2]
    binaural_out     = sys.argv[3]
    log_file         = sys.argv[4]
    tools_dir        = sys.argv[5]
    decoder_preset   = sys.argv[6]
    layout           = sys.argv[7]
    sofa             = sys.argv[8]
    itd              = sys.argv[9]
    room             = sys.argv[10]
    expected_spk     = int(sys.argv[11]) if sys.argv[11].strip().isdigit() else 0
    detected_order   = int(sys.argv[12]) if sys.argv[12].strip().lstrip("-").isdigit() else -1
    mode             = sys.argv[13].strip().lower()
    caller_version   = sys.argv[14].strip()

    # Bootstrap log is created before any validation or preset expansion so a
    # Python-side startup error can never appear as "Log file not found".
    try:
        with open(log_file, "w") as f:
            f.write("=== Spat5 bridge bootstrap v%s ===\n" % BRIDGE_VERSION)
            f.write("argc=%d caller=%s\n" % (len(sys.argv), caller_version))
    except OSError:
        pass

    if caller_version != BRIDGE_VERSION:
        fail(log_file, "bridge version mismatch: caller=%s bridge=%s" %
             (caller_version, BRIDGE_VERSION), code=2)

    raw_decoder_preset = decoder_preset
    try:
        # IMPORTANT: expand compact markers BEFORE OSC validation.
        decoder_preset = resolve_decoder_preset(
            raw_decoder_preset, layout, detected_order, expected_spk)
    except ValueError as exc:
        fail(log_file, "cannot resolve decoder preset: %s" % exc)

    # --- Resolve tool paths (mirrors the loudspeaker bridge) -----------------
    tools_path    = os.path.abspath(tools_dir.strip().rstrip("/\\"))
    spat_pkg_path = os.path.dirname(os.path.dirname(tools_path))
    support_path  = os.path.join(spat_pkg_path, "support")

    decoder_exe = exe_path(tools_path, "spat5.hoa.decoder~")
    vs_exe      = exe_path(tools_path, "spat5.virtualspeakers~")
    encoder_exe = exe_path(tools_path, "spat5.hoa.encoder~")  # for the "not called" check

    work_folder = os.path.dirname(os.path.abspath(binaural_out)) or os.getcwd()
    stale_removed = cleanup_stale_temp_files(
        work_folder, (bformat_in, decoded_speakers, binaural_out, log_file))

    # --- Main log ------------------------------------------------------------
    with open(log_file, "a") as f:
        f.write("\n=== Spat5 ambiX B-format -> Binaural Bridge v%s ===\n" % BRIDGE_VERSION)
        f.write("BRIDGE_VERSION=%s\n" % BRIDGE_VERSION)
        f.write("CALLER_VERSION=%s\n" % caller_version)
        f.write("Mode:            %s\n" % mode)
        f.write("B-format in:     %s\n" % bformat_in)
        f.write("Decoded speakers:%s\n" % decoded_speakers)
        f.write("Binaural out:    %s\n" % binaural_out)
        f.write("Raw preset token: %s\n" % raw_decoder_preset)
        f.write("Decoder preset:  %s\n" % decoder_preset)
        f.write("Decoder preset source: %s\n" % ("auto-22.2-marker-expanded-before-validation" if raw_decoder_preset == AUTO_3D24_MARKER else "direct OSC"))
        f.write("Layout:          %s\n" % layout)
        f.write("SOFA:            %s\n" % sofa)
        f.write("ITD:             %s\n" % itd)
        f.write("Room:            %s\n" % room)
        f.write("Expected spk:    %s\n" % (expected_spk or "auto"))
        f.write("Detected order:  %s\n" % detected_order)
        f.write("tools_path:      %s\n" % tools_path)
        f.write("decoder:         %s\n" % decoder_exe)
        f.write("virtualspeakers: %s\n" % vs_exe)
        f.write("support:         %s\n" % support_path)
        f.write("stale temps removed: %d\n\n" % len(stale_removed))

    # --- Verify the input B-format and confirm order -------------------------
    try:
        in_hdr = parse_wav_header(bformat_in)
    except (OSError, ValueError) as e:
        fail(log_file, "cannot read B-format input WAV: %s" % e)

    in_ch = in_hdr["n_channels"]
    in_sr = in_hdr["sample_rate"]
    in_frames = in_hdr["n_frames"]
    if in_ch not in ORDER_FOR_CHANNELS:
        fail(log_file, "input has %d channels, which is not a valid Ambisonic "
                       "order (need 4, 9, 16, 25 or 36)." % in_ch)
    order = ORDER_FOR_CHANNELS[in_ch]
    if detected_order not in (-1, order):
        log(log_file, "WARNING: Praat reported order %d but channel count "
                      "implies order %d. Using %d." % (detected_order, order, order))
    log(log_file, "Input: %d ch  ->  Ambisonic order %d  (%d Hz, %d frames)\n"
        % (in_ch, order, in_sr, in_frames))
    log(log_file, "Version handshake OK: Praat %s <-> bridge %s" %
        (caller_version, BRIDGE_VERSION))

    # --- Pre-flight: required executables ------------------------------------
    if not os.path.isfile(decoder_exe):
        fail(log_file, "spat5.hoa.decoder~ not found at:\n  %s\n"
                       "Check the Tools Folder in the Praat form." % decoder_exe)
    if not os.path.isfile(vs_exe):
        fail(log_file, "spat5.virtualspeakers~ not found at:\n  %s\n"
                       "Check the Tools Folder in the Praat form." % vs_exe)

    # Confirm the invariant explicitly: the encoder is present on disk but we
    # never build a command that uses it.
    log(log_file, "Encoder binary on disk: %s  (NEVER invoked by this tool)"
        % ("yes" if os.path.isfile(encoder_exe) else "no"))

    # --- Validate decoder OSC preset before launching Spat5 -----------------
    decoder_preset, preset_order, preset_speakers = validate_decoder_preset(
        decoder_preset, order, expected_spk, log_file)
    log(log_file, "Decoder OSC preset validated: order=%d, speakers=%d"
        % (preset_order, preset_speakers))
    if order == 3 and layout == "22.2":
        log(log_file, "Third-order policy: matched Spat5 22.2 / 24-speaker 3-D layout.")
        log(log_file, "Decoder method: energy-preserving (EPAD).")

    # --- Windows: let the tools find netcdf.dll and the other support DLLs --
    custom_env = os.environ.copy()
    if sys.platform == "win32":
        if not os.path.isdir(support_path):
            fail(log_file, "Spat5 support folder not found at:\n  %s\n"
                 "The tools cannot load netcdf.dll without this folder."
                 % support_path)
        custom_env["PATH"] = support_path + os.pathsep + custom_env.get("PATH", "")
        log(log_file, "Prepended Spat5 support folder to PATH.")

    # --- Self-test mode: report intent, run for real, verify 2-ch output -----
    if mode == "selftest":
        log(log_file, "\n=== SELF-TEST ===")
        log(log_file, "[ok] channel count %d -> valid Ambisonic order %d" % (in_ch, order))
        dec_cmd = build_decoder_cmd(decoder_exe, bformat_in, decoded_speakers, decoder_preset)
        vs_cmd  = build_virtualspeakers_cmd(vs_exe, decoded_speakers, layout,
                                            binaural_out, sofa, itd, room)
        assert_no_encoder(dec_cmd, log_file)
        assert_no_encoder(vs_cmd, log_file)
        log(log_file, "[ok] decoder command contains no encoder")
        log(log_file, "[ok] virtualspeakers command contains no encoder")
        log(log_file, "[ok] decoder exe present:         %s" % decoder_exe)
        log(log_file, "[ok] virtualspeakers exe present: %s" % vs_exe)
        log(log_file, "Would run stage 1: " + format_cmd(dec_cmd))
        log(log_file, "Would run stage 2: " + format_cmd(vs_cmd))
        # fall through and actually run so we can confirm a real 2-ch output

    # ========================================================================
    # STAGE 1 — HOA DECODE:  ambiX B-format  ->  virtual loudspeaker feeds
    # ========================================================================
    decoder_cmd = build_decoder_cmd(decoder_exe, bformat_in, decoded_speakers,
                                    decoder_preset)
    run_cmd(decoder_cmd, log_file, custom_env,
            "STAGE 1: spat5.hoa.decoder~", help_on_failure=True)

    if not os.path.isfile(decoded_speakers):
        fail(log_file, "decoder did not produce the speaker-feed file:\n  %s"
             % decoded_speakers)

    # Measure how many loudspeaker feeds were actually produced.
    try:
        dec_hdr = parse_wav_header(decoded_speakers)
    except (OSError, ValueError) as e:
        fail(log_file, "cannot read decoded speaker WAV: %s" % e)
    n_feeds = dec_hdr["n_channels"]
    log(log_file, "\nDecoder produced %d loudspeaker feed(s)  (@ %d Hz)."
        % (n_feeds, dec_hdr["sample_rate"]))

    # ---- Decoder <-> layout compatibility check -----------------------------
    want = expected_spk if expected_spk > 0 else KNOWN_LAYOUT_SPEAKERS.get(layout, 0)
    if want > 0:
        log(log_file, "Layout '%s' expects %d speaker position(s)." % (layout, want))
        if n_feeds != want:
            fail(log_file, "decoder/layout mismatch: decoder made %d feed(s) but "
                           "layout '%s' expects %d. Fix the decoder preset or the "
                           "layout so they correspond, then retry." % (n_feeds, layout, want))
    else:
        log(log_file, "Layout '%s' speaker count unknown to this bridge; relying "
                      "on virtualspeakers to reject a genuine mismatch." % layout)

    # Under-determination warning (does not stop): fewer speakers than the
    # Ambisonic channel count decodes poorly.
    need = channels_for_order(order)
    if n_feeds < need:
        log(log_file, "WARNING: %d feeds for order %d (%d channels) is "
                      "under-determined; the spatial image may be degraded."
            % (n_feeds, order, need))

    # ========================================================================
    # STAGE 2 — BINAURAL:  loudspeaker feeds  ->  binaural stereo (SOFA/HRTF)
    # ========================================================================
    vs_cmd = build_virtualspeakers_cmd(vs_exe, decoded_speakers, layout,
                                       binaural_out, sofa, itd, room)
    run_cmd(vs_cmd, log_file, custom_env,
            "STAGE 2: spat5.virtualspeakers~", help_on_failure=True)

    if not os.path.isfile(binaural_out):
        fail(log_file, "virtualspeakers did not produce the binaural file:\n  %s"
             % binaural_out)

    # ---- Validate the binaural output (contents, not just existence) --------
    res = analyse_stereo_output(binaural_out, log_file)

    def to_db(x):
        return 20 * math.log10(x) if x > 0 else float("-inf")

    log(log_file, "\n=== Output check ===")
    log(log_file, "channels: 2   sr: %d Hz   frames: %d   bits: %d"
        % (res["sample_rate"], res["n_frames"], res["bits"]))
    log(log_file, "peak: %.6f (%.1f dBFS)" % (res["peak"], to_db(res["peak"])))
    log(log_file, "L RMS: %.1f dBFS   R RMS: %.1f dBFS"
        % (to_db(res["rms_l"]), to_db(res["rms_r"])))

    if res["has_nan"] or res["has_inf"]:
        fail(log_file, "binaural output contains NaN/Inf sample values.")

    if res["n_frames"] == 0:
        fail(log_file, "binaural output has no audio frames.")

    SILENCE = 1e-6
    if res["rms_l"] < SILENCE and res["rms_r"] < SILENCE:
        fail(log_file, "binaural output is silent (both channels near zero).")
    if res["rms_l"] < SILENCE:
        log(log_file, "WARNING: left channel is silent or near-silent.")
    if res["rms_r"] < SILENCE:
        log(log_file, "WARNING: right channel is silent or near-silent.")

    if res["sample_rate"] != in_sr:
        log(log_file, "WARNING: output sr %d != input sr %d."
            % (res["sample_rate"], in_sr))

    # Report the convolution tail (do NOT trim here; Praat owns that choice).
    if res["n_frames"] > in_frames:
        tail = res["n_frames"] - in_frames
        log(log_file, "Convolution tail: +%d samples (%.3f s) beyond the input."
            % (tail, tail / float(in_sr or 1)))
    elif res["n_frames"] == in_frames:
        log(log_file, "Sample count matches the input exactly (no added tail).")
    else:
        log(log_file, "NOTE: output is shorter than the input by %d samples."
            % (in_frames - res["n_frames"]))

    if res["correlation"] is not None:
        c = res["correlation"]
        log(log_file, "L/R correlation: %.4f" % c)
        if c > 0.999:
            log(log_file, "WARNING: L/R effectively identical (dual-mono). Check "
                          "decoder preset / layout correspondence and the HRTF.")
        elif c > 0.95:
            log(log_file, "NOTE: L/R highly correlated; image may sound centered.")
        else:
            log(log_file, "L/R decorrelated — stereo image looks healthy.")

    log(log_file, "\nBinaural render completed successfully.")
    # No gain restoration or final normalisation is performed by the bridge.


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as exc:
        # Best-effort crash report using positional log argument when present.
        target = sys.argv[4] if len(sys.argv) > 4 else None
        if target:
            try:
                with open(target, "a") as f:
                    f.write("\nFATAL BRIDGE EXCEPTION: %s: %s\n" %
                            (type(exc).__name__, exc))
            except OSError:
                pass
        raise
