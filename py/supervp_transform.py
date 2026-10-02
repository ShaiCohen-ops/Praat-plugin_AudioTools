#!/usr/bin/env python3
# ============================================================
# Praat AudioTools - supervp_transform.py
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 3.2.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   SuperVP transform backend for IRCAM_SuperVP_Transform.praat.
#   Receives the input WAV(s) plus Praat's F0 and Intensity tracks,
#   turns them into SuperVP control BPFs, runs SuperVP, and writes a
#   manifest describing exactly what was sent (commands, control curves,
#   dropped flags) so the Praat figure can show the real process.
#
# Capability-checked flags (v3.0):
#   SuperVP's command line differs between versions, and its built-in
#   help (-h, -ha, -hp, -hi, -hf, -ho) is the authoritative list for the
#   INSTALLED build. On first use this engine reads that help, caches it,
#   and only emits a NEW (v3.0) flag if the help lists it. A quality flag
#   that is not listed is dropped and reported — the run continues with
#   the remaining flags. A MODE whose core flag is not available stops
#   with an error; nothing silently falls back to a different process.
#   Flags already used by v2.x (-S -s -A -a -Afft -afft -Z -P1 -F0 -Mauto
#   -D -transke -transenv -age -male -female -trmdle -Gcross -X -x -Y -y
#   -ggain) are assumed available, as they were before.
#
# Modes:
#   age, gender, age_gender     SuperVP built-in voice transforms
#   flatten_pitch               F0 contour scaled toward a target (-transke BPF)
#   vibrato                     sinusoidal transposition BPF, voicing-gated
#   harmoniser                  transposed copy mixed with the original
#   formant_shift               -transenv: constant, ramp, follow F0,
#                               follow intensity, wander (BPF)
#   time_stretch                -D factor or BPF (constant/voiced/unvoiced/ramp)
#   tremolo                     amplitude (-ggain BPF), spectral envelope
#                               (-transenv BPF), or constant (-trmdle)
#   breathiness                 whispered copy (voice envelope x noise via
#                               -Gcross) blended with the original
#   cross                       -Gcross, simple mix or four independent weights
#   gate                        dynamic gate: time-domain output gain BPF from
#                               intensity (-ggain); NOT spectral de-noising
#   organic_vibrato             -trmdlp randomised pitch modulation
#   freq_shift                  -Ffshift true frequency shift in Hz (BPF)
#   spectral_denoise            two-pass noise learn (-avseg/-OM1) + -Fsub
#   phase_diffusion             -rnd_* spectral phase randomisation effect
#   diagnostics                 dump SuperVP help + capability table
#
# Changelog v3.2.3:
#   - Spectral phase diffusion is now active: -rnd_force plus documented
#     -rnd_sin/-rnd_voi/-rnd_stval/-rnd_ff controls. Optional -shape 1
#     enables sinusoidal-component separation; otherwise rnd_sin is omitted.
#   - Phase diffusion skips transient-detector flags; VUF is estimated internally
#     by SuperVP when shape-invariant sinusoidal separation is requested.
#
# Changelog v3.2.2:
#   - Spectral denoise is now active: pass 1 learns an M1 SDIF noise profile
#     from a user-selected noise-only segment (-avseg/-OM1); pass 2 applies
#     -Fsub with -avbeta/-avsfac/-avrelax/-avgamma/-avdet. Both passes use
#     identical analysis/quality settings so spectral bins match.
#
# Changelog v3.2.4:
#   - Praat pause-form fix: removed the hyphen from "Non sinusoidal" so the
#     generated variable name is valid (`non_sinusoidal_randomization`).
#
# Changelog v3.2.1:
#   - Help excerpts now include "::" details blocks across blank lines
#     (the -Fsub details were cut off after their header).
#
# Changelog v3.2:
#   - Cross: the simple control is "spectral cross-coupling" (weights unchanged).
#   - Tremolo type "Native SuperVP": -gtremolo <sinus|triangle|carre|scie>
#     <time-depth BPF>, depth driven by Praat intensity.
#   - Organic vibrato: -trmdlp randomised pitch modulation.
#   - Frequency shift: -Ffshift with a Hz BPF (constant, ramp, follow /
#     inverse intensity, wander); no -P flags, no transient detector.
#   - Spectral denoise (-Fsub) and Spectral phase diffusion (-rnd_*):
#     listed, but they do NOT run yet — their parameter formats are not
#     confirmed. Each shows the matching section of the installed help.
#   - Capability detection per feature with exact-token patterns; the
#     Diagnostics report lists each feature and the relevant help sections.
#   - Formats corrected to those emitted by IRCAM's OM-SuperVP library:
#     window -M<samples> -N<fft> (was -M<seconds>s and -Np1); time-stretch
#     BPF as one token -D<file> (was "-D <file>", never exercised in v2).
#   - Manifest carries the full executed command lines (cmd_full) besides
#     the shortened ones shown in the figure; BPF times verified strictly
#     increasing; shared wander-curve helper.
#
# Changelog v3.1.1:
#   - Every command's analysis part now comes from one helper, ana(). In
#     the General/Voice profiles with voiced F0, -F0 + -Mauto now reach
#     ALL modes: Age (and the age pass of Age + gender), Gender, Cross,
#     Breathiness, -trmdle tremolo, amplitude tremolo and Dynamic gate
#     previously ran with the default window while the report said
#     "F0-adaptive". Standard profile commands are unchanged (exactly v2).
#
# Changelog v3.1 (from the SuperVP 2.104.4 help):
#   - Adaptive true envelope: in the General and Voice profiles, when Praat
#     found voiced frames, -Afft becomes "-Afft +<maxF0>Hz" with Praat's
#     95th-percentile F0, and Praat's F0 track is passed with -F0 so SuperVP
#     uses it for the envelope order. Checked against the help text;
#     reported as dropped if the syntax is not documented there.
#   - Voice profile: -envpl 1 (perceived-loudness preservation after
#     envelope modification) replaces -norm on transposing modes, if listed.
#
# Changelog v3.0.1:
#   - Reads its parameters from a key=value file (one path argument);
#     an invalid parameter is written to the log and done file instead of
#     exiting with status 2 (which aborted Praat with no explanation).
#
# Changelog v3.0:
#   - Help-based capability check; quality profiles (Standard = v2
#     behaviour, General, Voice, Percussive, Smeared) built only from
#     listed flags; dropped flags reported.
#   - De-noise renamed Dynamic gate: -ggain is an output amplitude
#     envelope, not a spectral process. Spectral de-noise is NOT
#     implemented yet: its flag syntax must first be read from the
#     installed help (Diagnostics reports whether a denoise option exists).
#   - Tremolo: intensity now drives the depth over TIME (direct, inverse,
#     exaggerated, quantised, smoothed) instead of one mean depth.
#   - Breathiness redesigned: the v2 path (-Gnoise + -ggain, and a
#     fallback that only lowered the level) produced no breath noise.
#   - Cross synthesis: four independent weights (Advanced) besides the
#     single mix; optional loop/pad of source 2 to source 1's length.
#   - Formant shift shapes (BPF to -transenv); flatten amount
#     (partial / exaggerated contours); voicing-gated vibrato with
#     onset fade-in; time-stretch shapes.
#   - Fixes: formant_shift dry run printed no command; flatten and gate
#     silently passed audio through when analysis was missing (now
#     errors); harmoniser mix could clip 16-bit output and ignored a
#     sample-rate mismatch (now float output + error on mismatch).
#   - Manifest file for the Praat visualisation.
#
# Dependencies:
#   Python 3; numpy + soundfile only for harmoniser, breathiness and
#   cross loop/pad (pip install numpy soundfile).
# ============================================================

import argparse
import math
import os
import random
import re
import subprocess
import sys

VERSION = "3.2.4"

try:
    import numpy as np
    import soundfile as sf
    HAS_NUMPY = True
except ImportError:
    HAS_NUMPY = False


class SVPError(Exception):
    pass


# =============================================================================
#  BPF I/O and helpers
# =============================================================================

def read_bpf(path):
    pts = []
    if not path or not os.path.isfile(path):
        return pts
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            parts = line.split()
            if len(parts) >= 2 and not line.lstrip().startswith("#"):
                try:
                    pts.append((float(parts[0]), float(parts[1])))
                except ValueError:
                    pass
    return pts


def write_bpf(path, pts):
    """Write a 'time value' BPF. Times must be strictly increasing (at the
    written precision); repeated times are dropped, non-finite values refused."""
    clean, last = [], None
    for t, v in pts:
        if not (math.isfinite(t) and math.isfinite(v)):
            raise SVPError(f"non-finite value in control curve {os.path.basename(path)}")
        tr = round(t, 6)
        if last is not None and tr <= last:
            continue
        clean.append((tr, v))
        last = tr
    if not clean:
        raise SVPError(f"empty control curve {os.path.basename(path)}")
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        for t, v in clean:
            fh.write(f"{t:.6f} {v:.6f}\n")


def median(vals):
    s = sorted(vals)
    if not s:
        return None
    n = len(s)
    return s[n // 2] if n % 2 else 0.5 * (s[n // 2 - 1] + s[n // 2])


def quantile(vals, q):
    s = sorted(vals)
    if not s:
        return None
    pos = q * (len(s) - 1)
    i = int(math.floor(pos))
    j = min(i + 1, len(s) - 1)
    return s[i] + (s[j] - s[i]) * (pos - i)


def interp_at(pts, t):
    """Linear interpolation in a (t, v) list; holds the ends."""
    if not pts:
        return 0.0
    if t <= pts[0][0]:
        return pts[0][1]
    if t >= pts[-1][0]:
        return pts[-1][1]
    lo, hi = 0, len(pts) - 1
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if pts[mid][0] <= t:
            lo = mid
        else:
            hi = mid
    (t0, v0), (t1, v1) = pts[lo], pts[hi]
    return v0 if t1 <= t0 else v0 + (v1 - v0) * (t - t0) / (t1 - t0)


def time_grid(duration, step):
    n = max(1, int(math.ceil(duration / step)))
    return [min(i * step, duration) for i in range(n + 1)]


def one_pole(vals, step, tau_up, tau_down=None):
    """Asymmetric one-pole smoother (time constants in s)."""
    if tau_down is None:
        tau_down = tau_up
    out, y = [], None
    for v in vals:
        if y is None:
            y = v
        else:
            tau = tau_up if v > y else tau_down
            a = 0.0 if tau <= 0 else math.exp(-step / tau)
            y = a * y + (1 - a) * v
        out.append(y)
    return out


def wander_curve(grid, dur, rate, seed):
    """Seeded smooth random path in [-1, 1] (smoothstep between random knots)."""
    rng = random.Random(seed)
    n_knots = max(2, int(dur * rate) + 2)
    knots = [rng.uniform(-1, 1) for _ in range(n_knots)]
    out = []
    for t in grid:
        u = t / dur * (n_knots - 1) if dur > 0 else 0
        i = min(int(u), n_knots - 2)
        f = u - i
        sm = f * f * (3 - 2 * f)
        out.append(knots[i] + (knots[i + 1] - knots[i]) * sm)
    return out


def constant_ctrl(duration, value):
    return [(0.0, value), (duration, value)]


# =============================================================================
#  Analysis-derived curves
# =============================================================================

def voicing_curve(f0_pts, grid):
    """1 where Praat found a voiced frame (F0 > 0), else 0, on the grid."""
    if not f0_pts:
        return [0.0 for _ in grid]
    out = []
    j = 0
    for t in grid:
        while j + 1 < len(f0_pts) and abs(f0_pts[j + 1][0] - t) <= abs(f0_pts[j][0] - t):
            j += 1
        out.append(1.0 if f0_pts[j][1] > 0 else 0.0)
    return out


def intensity_rel(int_pts, grid, range_db=30.0):
    """Intensity mapped to 0..1 over the top range_db dB below the peak."""
    if not int_pts:
        return None
    peak = max(v for _, v in int_pts)
    return [max(0.0, min(1.0, (interp_at(int_pts, t) - (peak - range_db)) / range_db)) for t in grid]


def f0_filled(f0_pts):
    """Voiced points only; unvoiced gaps are bridged by interpolation."""
    return [(t, v) for t, v in f0_pts if v > 0]


# =============================================================================
#  SuperVP help / capabilities
# =============================================================================

HELP_SWITCHES = ["-h", "-ha", "-hp", "-hi", "-hf", "-ho"]

# New v3.0 flags and the pattern that must appear in the help text.
NEW_FLAGS = {
    "-M":         r"(?<![\w-])-M",
    "-N":         r"(?<![\w-])-N",
    "-oversamp":  r"(?<![\w-])-oversamp\b",
    "-W":         r"(?<![\w-])-W",
    "-norm":      r"(?<![\w-])-norm\b",
    "-envpl":     r"(?<![\w-])-envpl\b",
    # adaptive true envelope: help documents "-Afft +<maxF0>Hz" (v3.1)
    "-Afft +F0":  r"(?i)\+\s*<\s*max\s*_?f0\s*>\s*hz|-Afft\s+\+\s*\d+\s*hz",
    "-shape":     r"(?<![\w-])-shape\b",
    "-td_thresh": r"(?<![\w-])-td_thresh\b",
    "-td_G":      r"(?<![\w-])-td_G\b",
    "-td_band":   r"(?<![\w-])-td_band\b",
    "-td_nument": r"(?<![\w-])-td_nument\b",
    "-td_minoff": r"(?<![\w-])-td_minoff\b",
    "-td_ampfac": r"(?<![\w-])-td_ampfac\b",
}
# v3.2 features: ALL patterns must match (exact tokens, no loose substrings).
FEATURES = {
    "Native tremolo":               [r"(?<![\w-])-gtremolo\b"],
    "Spectral subtraction denoise": [r"(?m)^[ \t]*sub[ \t]*:[ \t]*spectral subtraction",
                                     r"(?<![\w-])-Fsub\b", r"(?<![\w-])-avseg\b", r"(?<![\w-])-avbeta\b",
                                     r"(?<![\w-])-avsfac\b", r"(?<![\w-])-avrelax\b",
                                     r"(?<![\w-])-avgamma\b", r"(?<![\w-])-avdet\b",
                                     r"(?<![\w-])-OM1\b"],
    "Legacy denoise":               [r"(?m)^[ \t]*denois[ \t]*:"],
    "Frequency shift":              [r"(?m)(?<![\w-])-Ffshift\b|^[ \t]*fshift[ \t]*:"],
    "Phase randomization":          [r"(?<![\w-])-rnd_sin\b", r"(?<![\w-])-rnd_voi\b",
                                     r"(?<![\w-])-rnd_stval\b", r"(?<![\w-])-rnd_ff\b"],
    "Randomized pitch modulation":  [r"(?<![\w-])-trmdlp\b"],
}
# Help sections copied into the Diagnostics report (to confirm parameter formats).
EXCERPT_TOKENS = ["-gtremolo", "-trmdlp", "-Ffshift", "fshift", "sub", "denois", "-rnd_force",
                  "-rnd_sin", "-rnd_voi", "-rnd_stval", "-rnd_ff", "-rnd_vufke", "-Afft", "-M", "-Gcross"]
SCOUT_TERMS = {
    "-Gnoise": r"(?<![\w-])-Gnoise\b",
}


def read_help(exe, cache_path, log):
    key = ""
    try:
        st = os.stat(exe)
        key = f"{os.path.abspath(exe)}|{st.st_size}|{int(st.st_mtime)}"
    except OSError:
        pass
    if cache_path and os.path.isfile(cache_path):
        with open(cache_path, "r", encoding="utf-8", errors="replace") as fh:
            first = fh.readline().rstrip("\n")
            if first == "KEY " + key:
                return fh.read(), True
    chunks = []
    for sw in HELP_SWITCHES:
        try:
            r = subprocess.run([exe, sw], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               timeout=20)
            txt = r.stdout.decode("utf-8", errors="replace")
        except (OSError, subprocess.SubprocessError) as e:
            txt = f"[{sw} failed: {e}]"
        chunks.append(f"\n===== supervp {sw} =====\n{txt}")
    text = "".join(chunks)
    if cache_path:
        try:
            with open(cache_path, "w", encoding="utf-8", newline="\n") as fh:
                fh.write("KEY " + key + "\n" + text)
        except OSError:
            log("  (could not write help cache)")
    return text, False


def capabilities(help_text):
    usable = len(re.findall(r"(?<![\w-])-[A-Za-z]", help_text)) >= 30
    caps = {f: bool(usable and re.search(p, help_text)) for f, p in NEW_FLAGS.items()}
    for name, pats in FEATURES.items():
        caps[name] = bool(usable and all(re.search(p, help_text) for p in pats))
    scout = {k: bool(usable and re.search(p, help_text, re.I)) for k, p in SCOUT_TERMS.items()}
    return usable, caps, scout


def help_excerpt(help_text, token, max_lines=25, detail_lines=90):
    """Lines of the help that document `token`.

    Two kinds of entry exist in the SuperVP help:
      * a flag/list line ("  sub : spectral subtraction ... (see details)")
        -> that line plus its indented continuation lines;
      * a details block whose header ends with '::'
        ("sub, sub-det, sub-noex, sub-noex-det::") -> everything up to the
        next '::' header, INCLUDING blank lines (v3.2 stopped at the first
        blank line and returned only the header)."""
    lines = help_text.splitlines()
    pat = re.compile(r"^[ \t]*" + re.escape(token) + r"(?![\w])")
    header = re.compile(r"^[ \t]*\S.*::[ \t]*$")
    out = []
    for i, ln in enumerate(lines):
        if not pat.match(ln):
            continue
        block = [ln]
        if header.match(ln):
            for nxt in lines[i + 1:i + detail_lines]:
                if header.match(nxt) or nxt.startswith("====="):
                    break
                block.append(nxt)
            while block and not block[-1].strip():
                block.pop()
        else:
            ind = len(ln) - len(ln.lstrip())
            for nxt in lines[i + 1:i + max_lines]:
                if not nxt.strip():
                    break
                nind = len(nxt) - len(nxt.lstrip())
                if nind <= ind and re.match(r"^[ \t]*-?\w", nxt):
                    break
                block.append(nxt)
        blk = "\n".join(block)
        if blk not in out:                              # the -h* outputs overlap
            out.append(blk)
    return out


def require_feature(ctx, name, what):
    if not ctx["help_usable"]:
        raise SVPError(f"{what}: cannot confirm support — this SuperVP's help could not be read")
    if not ctx["caps"].get(name):
        raise SVPError(f"{what} is not supported by this SuperVP build (help lists no {name.lower()})")


# =============================================================================
#  Quality profiles
# =============================================================================

TRANSPOSING_MODES = {"age", "gender", "age_gender", "flatten_pitch", "vibrato", "organic_vibrato",
                     "harmoniser", "formant_shift", "breathiness", "cross"}


def is_transposing(mode, tremolo_type):
    """Envelope / pitch processes; amplitude-only processes (gate, amplitude
    tremolo) and time stretch get no -norm / -shape."""
    return mode in TRANSPOSING_MODES or (mode == "tremolo" and tremolo_type in ("envelope", "trmdle"))


SHAPE_MODES = {"gender", "age_gender", "flatten_pitch", "vibrato", "organic_vibrato",
               "harmoniser", "formant_shift"}
NO_TRANSIENT_MODES = {"freq_shift", "spectral_denoise"}       # -P flags must not accompany -Ffshift (OM-SuperVP)


def uses_afft(mode, tremolo_type):
    """Modes whose commands carry -Afft (age alone, time stretch, gate and
    amplitude tremolo analyse with plain -A, exactly as in v2)."""
    return mode not in ("age", "time_stretch", "gate", "diagnostics", "freq_shift",
                        "spectral_denoise", "phase_diffusion") and \
        not (mode == "tremolo" and tremolo_type in ("amplitude", "native"))


def win_tokens(sec, sr):
    """-M<samples> -N<fft>: integer sample counts, the format IRCAM's own
    OM-SuperVP library emits (v3.0-3.1.1 sent seconds, -M0.046s)."""
    n = max(64, int(round(sec * sr)))
    fft = 1 << int(math.ceil(math.log2(n)))
    return [f"-M{n}", f"-N{fft}"]


def quality_flags(profile, caps, mode, sr, f0_info, notes, dropped, transposing, env_used=True,
                  transients=True):
    """Return extra SuperVP flags for the profile; record dropped ones."""
    if profile == "standard":
        return [], False                                  # v2 behaviour
    out = []
    use_mauto = False

    def want(flag, tokens, why):
        if caps.get(flag):
            out.extend(tokens)
        else:
            dropped.append((flag, f"not listed in this SuperVP's help ({why})"))

    voiced_frac = f0_info.get("voiced_frac", 0.0)
    f0_min = f0_info.get("f0_min")
    if profile in ("general", "voice"):
        if f0_info.get("has_f0"):
            use_mauto = True                              # F0-adaptive window (v2-verified)
            notes.append("window: F0-adaptive (-F0 + -Mauto) from Praat's pitch track")
        else:
            win = 0.060 if profile == "voice" else 0.046
            want("-M", win_tokens(win, sr), "window length")
        want("-W", ["-Whanning"] if profile == "voice" else ["-Wblackman"], "window type")
        want("-oversamp", ["-oversamp", "8" if profile == "voice" else "4"], "frame overlap")
    elif profile == "percussive":
        want("-M", win_tokens(0.023, sr), "short window")
        want("-W", ["-Wblackman"], "window type")
        want("-oversamp", ["-oversamp", "8"], "frame overlap")
    elif profile == "smeared":
        want("-M", win_tokens(0.186, sr), "long window")
        want("-W", ["-Whanning"], "window type")
        want("-oversamp", ["-oversamp", "8"], "frame overlap")
        notes.append("smeared: long window, no transient preservation (deliberate smearing)")

    if profile in ("general", "voice", "percussive") and not transients:
        notes.append("transient detector not used: this process has no phase-synchronised resynthesis")
    if profile in ("general", "voice", "percussive") and transients:
        thresh = {"general": "1.4", "voice": "1.7", "percussive": "1.1"}[profile]
        td = [("-td_thresh", [thresh]), ("-td_G", ["2.5"]), ("-td_band", ["0," + str(int(sr / 2))]),
              ("-td_nument", ["10.0"]), ("-td_minoff", ["0.02"]), ("-td_ampfac", ["1.5"])]
        for flag, vals in td:
            want(flag, [flag] + vals, "transient detector")
    afft = ["-Afft"]
    afft_f0 = False
    if env_used and profile in ("general", "voice") and f0_info.get("has_f0") and f0_info.get("f0_max"):
        if caps.get("-Afft +F0"):
            afft = ["-Afft", f"+{f0_info['f0_max']:.0f}Hz"]
            afft_f0 = True
            notes.append(f"spectral envelope: adaptive true envelope from Praat F0 "
                         f"(-F0 + -Afft +{f0_info['f0_max']:.0f}Hz, 95th-percentile F0)")
        else:
            dropped.append(("-Afft +F0", "adaptive true-envelope syntax not found in this SuperVP's help"))
    f0_info["afft"] = afft
    f0_info["afft_f0"] = afft_f0
    if transposing and profile == "voice" and caps.get("-envpl"):
        out.extend(["-envpl", "1"])
        notes.append("loudness: perceived-loudness preservation (-envpl 1) instead of -norm")
    elif transposing and profile != "smeared":
        if profile == "voice":
            dropped.append(("-envpl", "not listed in this SuperVP's help; using -norm"))
        want("-norm", ["-norm"], "level normalisation after envelope-preserving transposition")
    if profile == "voice" and transposing and mode in SHAPE_MODES:
        if voiced_frac >= 0.5:
            want("-shape", ["-shape", "1"], "shape invariance (monophonic voice only)")
        else:
            notes.append(f"shape invariance skipped: only {voiced_frac * 100:.0f}% of frames voiced "
                         "(meant for monophonic speech/singing)")
    if f0_min:
        notes.append(f"Praat F0 range used for analysis: {f0_info['f0_min']:.0f}-{f0_info['f0_max']:.0f} Hz")
    return out, use_mauto


# =============================================================================
#  Runner
# =============================================================================

class Run:
    def __init__(self, args, log_path, manifest_path):
        self.args = args
        self.log_path = log_path
        self.manifest = []
        self.manifest_path = manifest_path
        self.commands = []
        self.full_commands = []
        self.afft = ["-Afft"]
        self.afft_f0 = False
        self.use_mauto = False
        self.f0_ok = False

    def log(self, msg):
        print(msg, flush=True)
        with open(self.log_path, "a", encoding="utf-8") as fh:
            fh.write(msg + "\n")

    def svp(self, svp_args):
        exe = self.args.supervp_exe
        cmd = [exe] + svp_args
        pre = os.path.basename(self.args.tmp_prefix)
        def shorten(x):
            if "/" not in x and "\\" not in x:
                return x
            m = re.match(r"^(-[A-Za-z0-9]+)(.+)$", x) if x.startswith("-") else None
            if m:                                       # attached flag + path, e.g. -D<file>
                return m.group(1) + os.path.basename(m.group(2)).replace(pre, "", 1)
            return os.path.basename(x).replace(pre, "", 1)
        short = [shorten(x) for x in svp_args]
        shown = " ".join(f'"{x}"' if " " in x else x for x in [os.path.basename(exe)] + short)
        full = " ".join(f'"{x}"' if " " in x else x for x in cmd)
        self.commands.append(shown)
        self.full_commands.append(full)
        self.log("CMD: " + full)
        if self.args.dry_run:
            return
        r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        out = r.stdout.decode("utf-8", errors="replace")
        if out.strip():
            self.log(out.rstrip())
        if r.returncode != 0:
            raise SVPError(f"SuperVP returned code {r.returncode} (see log)")
        if not os.path.isfile(svp_args[-1]):
            raise SVPError(f"SuperVP wrote no output file: {svp_args[-1]}")

    def ctrl(self, name, label, unit, pts):
        path = self.args.tmp_prefix + "ctrl_" + name + ".bpf"
        write_bpf(path, pts)
        self.manifest.append(f"ctrl={path}|{label}|{unit}")
        return path

    def note(self, msg):
        self.manifest.append("note=" + msg)
        self.log("  note: " + msg)

    def write_manifest(self, extra):
        with open(self.manifest_path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(f"version={VERSION}\n")
            for k, v in extra:
                fh.write(f"{k}={v}\n")
            for c in self.commands:
                fh.write("cmd=" + c + "\n")
            for c in self.full_commands:
                fh.write("cmd_full=" + c + "\n")
            for m in self.manifest:
                fh.write(m + "\n")


# =============================================================================
#  Audio helpers (numpy/soundfile)
# =============================================================================

def need_numpy(what):
    if not HAS_NUMPY:
        raise SVPError(f"{what} needs numpy and soundfile (pip install numpy soundfile)")


def read_audio(path):
    x, sr = sf.read(path, always_2d=True, dtype="float64")
    return x, sr


def write_audio(path, x, sr, run, label):
    peak = float(np.max(np.abs(x))) if x.size else 0.0
    if peak > 0.999:
        x = x * (0.999 / peak)
        run.note(f"{label}: peak {peak:.2f} attenuated to 0.999 (no clipping)")
    sf.write(path, x, sr, subtype="FLOAT")


def match_channels(a, b):
    if a.shape[1] == b.shape[1]:
        return a, b
    if b.shape[1] == 1:
        return a, np.repeat(b, a.shape[1], axis=1)
    return a, b.mean(axis=1, keepdims=True).repeat(a.shape[1], axis=1)


# =============================================================================
#  Mode handlers
# =============================================================================

def ana(run, src, envelope=True, mauto=None):
    """The ONE place that builds the analysis part of a command:
    -S src [-F0 f0 [-Mauto]] -A [-Afft [+maxF0Hz]] -Z

    envelope  True  -> spectral-envelope analysis (-Afft, adaptive true
                       envelope when the profile enabled it)
              False -> plain -A (age, gate, amplitude tremolo, time stretch,
                       exactly as in v2)
    mauto     None  -> follow the profile (General/Voice with voiced F0);
              True/False -> explicit (v2 behaviour for the Standard profile).
    -F0 is passed whenever -Mauto or the adaptive envelope needs it, so the
    command always matches what the profile reports."""
    use = run.use_mauto if mauto is None else mauto
    a = ["-S", src]
    if use and run.f0_ok:
        a += ["-F0", run.args.f0_file, "-Mauto"]
    elif envelope and run.afft_f0:
        a += ["-F0", run.args.f0_file]
    a += ["-A"] + (run.afft if envelope else []) + ["-Z"]
    return a


def base_args(run, src, q, use_mauto, f0_ok, extra_analysis=True):
    return ana(run, src, envelope=extra_analysis, mauto=bool(use_mauto and f0_ok)) + q


def gender_formant_cents(direction, amount):
    c = {1: 120, 2: 200, 3: 300, 4: 400, 5: 500}[amount]
    return -c if direction == "male" else c


def mode_age(run, ctx):
    a = run.args
    run.ctrl("age", "age (years, -age)", "years", constant_ctrl(ctx["dur"], a.age_val))
    run.svp(ana(run, a.input_wav1, envelope=False) + ctx["q"] + ["-age", str(a.age_val), a.result_wav])


def mode_gender(run, ctx, src=None, out=None):
    a = run.args
    src = src or a.input_wav1
    out = out or a.result_wav
    amount = max(1, min(5, a.gender_amount))
    flag = "-female" if a.gender_dir == "female" else "-male"
    run.ctrl("gender", f"{flag[1:]} amount (SuperVP 1-5)", "level", constant_ctrl(ctx["dur"], amount))
    if not a.gender_reinforce:
        run.svp(ana(run, src) + ctx["q"] + [flag, str(amount), out])
        return
    inter = a.tmp_prefix + "gender_inter.wav"
    run.svp(ana(run, src) + ctx["q"] + [flag, str(amount), inter])
    fc = gender_formant_cents(a.gender_dir, amount)
    run.ctrl("genderenv", "formant reinforcement (-transenv)", "cents", constant_ctrl(ctx["dur"], fc))
    run.svp(ana(run, inter if not a.dry_run else src) + ctx["q"] +
            ["-transenv", str(fc), out])
    ctx["cleanup"].append(inter)


def mode_age_gender(run, ctx):
    a = run.args
    inter = a.tmp_prefix + "age_inter.wav"
    run.ctrl("age", "age (years, -age)", "years", constant_ctrl(ctx["dur"], a.age_val))
    run.svp(ana(run, a.input_wav1, envelope=False) + ctx["q"] + ["-age", str(a.age_val), inter])
    ctx["cleanup"].append(inter)
    mode_gender(run, ctx, src=inter if not a.dry_run else a.input_wav1)


def require_f0(ctx, what):
    if not ctx["f0v"]:
        raise SVPError(f"{what} needs voiced frames, and Praat found none in the chosen pitch range "
                       f"({ctx['f0_info'].get('range_label', '?')}). Try a wider Pitch range.")


def mode_flatten_pitch(run, ctx):
    a = run.args
    require_f0(ctx, "Flatten pitch")
    med = median([v for _, v in ctx["f0v"]])
    target = a.target_f0 if a.target_f0 > 0 else med
    amt = a.flatten_amount
    pts = [(t, amt * 1200.0 * math.log2(target / f0)) for t, f0 in ctx["f0v"]]
    run.note(f"target {target:.1f} Hz ({'median' if a.target_f0 <= 0 else 'user'}), amount {amt:g} "
             "(1 = flat, 0 = unchanged, <0 = exaggerated)")
    p = run.ctrl("trans", "transposition (-transke)", "cents", pts)
    run.svp(base_args(run, a.input_wav1, ctx["q"], True, True) + ["-P1", "-transke", p, a.result_wav])


def mode_vibrato(run, ctx):
    a = run.args
    step = 0.005
    grid = time_grid(ctx["dur"], step)
    if a.vibrato_voiced_only:
        require_f0(ctx, "Voiced-only vibrato")
        gate = one_pole(voicing_curve(ctx["f0"], grid), step, max(a.vibrato_fade, 0.0), 0.03)
    else:
        gate = [1.0] * len(grid)
        if a.vibrato_fade > 0:
            gate = [min(1.0, t / a.vibrato_fade) for t in grid]
    w = 2 * math.pi * a.vibrato_freq
    pts = [(t, a.vibrato_depth * g * math.sin(w * t)) for t, g in zip(grid, gate)]
    p = run.ctrl("trans", "vibrato transposition (-transke)", "cents", pts)
    run.svp(base_args(run, a.input_wav1, ctx["q"], ctx["use_mauto"] or ctx["v2_mauto"], bool(ctx["f0v"])) +
            ["-P1", "-transke", p, a.result_wav])


def mode_harmoniser(run, ctx):
    a = run.args
    need_numpy("Harmoniser")
    harm = a.tmp_prefix + "harmony.wav"
    p = run.ctrl("trans", "harmony voice (-transke)", "cents", constant_ctrl(ctx["dur"], a.harmoniser_interval))
    run.ctrl("mix", "harmony level", "0-1", constant_ctrl(ctx["dur"], a.harmoniser_mix))
    run.svp(base_args(run, a.input_wav1, ctx["q"], ctx["use_mauto"] or ctx["v2_mauto"], bool(ctx["f0v"])) +
            ["-P1", "-transke", p, harm])
    ctx["cleanup"].append(harm)
    if a.dry_run:
        return
    x, sr = read_audio(a.input_wav1)
    h, sr2 = read_audio(harm)
    if sr != sr2:
        raise SVPError(f"harmony pass changed the sample rate ({sr} -> {sr2})")
    x, h = match_channels(x, h)
    n = min(len(x), len(h))
    m = max(0.0, min(1.0, a.harmoniser_mix))
    write_audio(a.result_wav, (1 - m) * x[:n] + m * h[:n], sr, run, "harmoniser mix")


def mode_formant_shift(run, ctx):
    a = run.args
    shape = a.formant_shape
    dur = ctx["dur"]
    if shape == "constant":
        val = int(round(a.formant_shift_cents))
        run.ctrl("env", "envelope shift (-transenv)", "cents", constant_ctrl(dur, val))
        run.svp(base_args(run, a.input_wav1, ctx["q"], ctx["use_mauto"], bool(ctx["f0v"])) +
                ["-transenv", str(val), a.result_wav])
        return
    step = 0.01
    grid = time_grid(dur, step)
    base = a.formant_shift_cents
    if shape == "ramp":
        vals = [base + (a.formant_end_cents - base) * (t / dur if dur > 0 else 0) for t in grid]
    elif shape == "follow_f0":
        require_f0(ctx, "Formants following F0")
        med = median([v for _, v in ctx["f0v"]])
        k = a.formant_depth_cents / 1200.0           # cents of envelope per octave of F0
        vals = [base + k * 1200.0 * math.log2(interp_at(ctx["f0v"], t) / med) for t in grid]
        run.note(f"envelope follows F0: {a.formant_depth_cents:g} cents per octave around {med:.1f} Hz")
    elif shape == "follow_intensity":
        rel = intensity_rel(ctx["int"], grid)
        if rel is None:
            raise SVPError("Formants following intensity needs the intensity track")
        rel = one_pole(rel, step, 0.05)
        vals = [base + a.formant_depth_cents * (2 * r - 1) for r in rel]
    elif shape == "wander":
        vals = [base + a.formant_depth_cents * v
                for v in wander_curve(grid, dur, a.formant_wander_rate, a.seed)]
        run.note(f"wander seed {a.seed}, {a.formant_wander_rate:g} turns/s")
    else:
        raise SVPError(f"unknown formant shape {shape}")
    p = run.ctrl("env", "envelope shift (-transenv BPF)", "cents", list(zip(grid, vals)))
    run.note("time-varying -transenv uses a BPF file (supported per IRCAM forum); constant shape passes a number")
    run.svp(base_args(run, a.input_wav1, ctx["q"], ctx["use_mauto"], bool(ctx["f0v"])) +
            ["-transenv", p, a.result_wav])


def mode_time_stretch(run, ctx):
    a = run.args
    if a.stretch_factor <= 0:
        raise SVPError("stretch factor must be > 0")
    dur = ctx["dur"]
    shape = a.stretch_shape
    args = ana(run, a.input_wav1, envelope=False,
               mauto=ctx["use_mauto"] or ctx["v2_mauto"]) + ctx["q"]
    if ctx["profile"] != "smeared":
        args += ["-P1"]
    if shape == "constant":
        run.ctrl("stretch", "time-stretch factor (-D)", "x", constant_ctrl(dur, a.stretch_factor))
        args += [f"-D{a.stretch_factor:.6f}"]
        ctx["expected_ratio"] = a.stretch_factor
    else:
        step = 0.01
        grid = time_grid(dur, step)
        if shape in ("voiced", "unvoiced"):
            require_f0(ctx, "Voiced/unvoiced stretch")
            v = one_pole(voicing_curve(ctx["f0"], grid), step, 0.03)
            if shape == "unvoiced":
                v = [1 - x for x in v]
            vals = [1 + (a.stretch_factor - 1) * x for x in v]
        else:                                              # ramp 1 -> factor
            vals = [1 + (a.stretch_factor - 1) * (t / dur if dur > 0 else 0) for t in grid]
        p = run.ctrl("stretch", "time-stretch factor (-D BPF)", "x", list(zip(grid, vals)))
        ctx["expected_ratio"] = sum(vals) / len(vals)
        args += ["-D" + p]                                # attached, as OM-SuperVP emits it
    run.svp(args + [a.result_wav])


def mode_tremolo(run, ctx):
    a = run.args
    step = 0.002
    dur = ctx["dur"]
    grid = time_grid(dur, step)
    mapping = a.tremolo_map
    if a.tremolo_freq <= 0 or a.tremolo_freq > 40:
        raise SVPError("tremolo rate must be in (0, 40] Hz")
    if mapping == "none":
        drive = [1.0] * len(grid)
    else:
        rel = intensity_rel(ctx["int"], grid)
        if rel is None:
            raise SVPError("intensity mapping needs the intensity track")
        rel = one_pole(rel, step, max(a.tremolo_smooth_ms, 0) / 1000.0)
        if mapping == "direct":
            drive = rel
        elif mapping == "inverse":
            drive = [1 - r for r in rel]
        elif mapping == "exaggerated":
            drive = [r * r * (3 - 2 * r) for r in rel]
            drive = [d * d * (3 - 2 * d) for d in drive]
        elif mapping == "quantised":
            drive = [round(r * 3) / 3 for r in rel]
        else:
            raise SVPError(f"unknown tremolo mapping {mapping}")
    w = 2 * math.pi * a.tremolo_freq
    if a.tremolo_type == "native":
        require_feature(ctx, "Native tremolo", "Native SuperVP tremolo (-gtremolo)")
        wave = {"sine": "sinus", "triangle": "triangle", "square": "carre", "saw": "scie"}[a.tremolo_waveform]
        depth = max(0.0, min(1.0, a.tremolo_amp_depth))
        p = run.ctrl("depth", f"tremolo depth (-gtremolo {wave})", "depth",
                     [(t, depth * d) for t, d in zip(grid[::5], drive[::5])])
        run.note(f"native SuperVP tremolo: waveform {wave}; SuperVP generates the modulation, "
                 "Praat supplies the depth over time (time depth BPF, as documented by -gtremolo). "
                 "The documented syntax has no rate argument, so the Rate field does not apply here")
        run.svp(ana(run, a.input_wav1, envelope=False) + ctx["q"] + ["-gtremolo", wave, p, a.result_wav])
        return
    if a.tremolo_type == "amplitude":
        depth = max(0.0, min(1.0, a.tremolo_amp_depth))
        run.ctrl("depth", "tremolo depth (from intensity)" if mapping != "none" else "tremolo depth",
                 "0-1", [(t, depth * d) for t, d in zip(grid[::5], drive[::5])])
        pts = [(t, 1.0 - depth * d * 0.5 * (1 - math.cos(w * t))) for t, d in zip(grid, drive)]
        p = run.ctrl("gain", "output gain (-ggain)", "gain", pts)
        run.svp(ana(run, a.input_wav1, envelope=False) + ctx["q"] + ["-ggain", p, a.result_wav])
    elif a.tremolo_type == "envelope":
        run.ctrl("depth", "envelope tremolo depth", "cents",
                 [(t, a.tremolo_env_depth * d) for t, d in zip(grid[::5], drive[::5])])
        pts = [(t, a.tremolo_env_depth * d * math.sin(w * t)) for t, d in zip(grid, drive)]
        p = run.ctrl("env", "envelope shift (-transenv BPF)", "cents", pts)
        run.svp(base_args(run, a.input_wav1, ctx["q"], ctx["use_mauto"], bool(ctx["f0v"])) +
                ["-transenv", p, a.result_wav])
    else:                                                  # trmdle: constant only
        if mapping != "none":
            raise SVPError("-trmdle takes one constant depth; choose Amplitude or Spectral envelope "
                           "tremolo for intensity-driven depth")
        run.ctrl("depth", "envelope tremolo depth (-trmdle)", "cents", constant_ctrl(dur, a.tremolo_env_depth))
        run.svp(ana(run, a.input_wav1) + ctx["q"] +
                ["-trmdle", f"{a.tremolo_freq:.2f},{a.tremolo_env_depth:.2f}", a.result_wav])


def mode_breathiness(run, ctx):
    """Whisper copy = voice spectral envelope (amplitude) x noise fine structure
    (frequency/phase) via -Gcross; then blended with the original."""
    a = run.args
    need_numpy("Breathiness")
    amt = max(0.0, min(1.0, a.breathiness_amount))
    x, sr = read_audio(a.input_wav1)
    rng = np.random.default_rng(a.seed)
    noise = rng.standard_normal(x.shape) * 0.25
    noise_wav = a.tmp_prefix + "noise.wav"
    whisper = a.tmp_prefix + "whisper.wav"
    sf.write(noise_wav, noise, sr, subtype="FLOAT")
    ctx["cleanup"] += [noise_wav, whisper]
    run.ctrl("X", "voice amplitude weight (-X)", "w", constant_ctrl(ctx["dur"], 1.0))
    run.ctrl("y", "noise frequency weight (-y)", "w", constant_ctrl(ctx["dur"], 1.0))
    run.ctrl("mix", "whisper blend", "0-1", constant_ctrl(ctx["dur"], amt))
    run.svp(["-S", a.input_wav1, "-s", noise_wav] + ana(run, a.input_wav1)[2:-1] + ["-a", "-afft", "-Z"] + ctx["q"] +
            ["-Gcross", "-X1.0000", "-x0.0000", "-Y0.0000", "-y1.0000", whisper])
    if a.dry_run:
        return
    w, sr2 = read_audio(whisper)
    if sr2 != sr:
        raise SVPError(f"whisper pass changed the sample rate ({sr} -> {sr2})")
    x, w = match_channels(x, w)
    n = min(len(x), len(w))
    rx = float(np.sqrt(np.mean(x[:n] ** 2))) + 1e-12
    rw = float(np.sqrt(np.mean(w[:n] ** 2))) + 1e-12
    w = w[:n] * (rx / rw)                                  # level-matched whisper
    run.note(f"whisper level-matched to the original (gain {rx / rw:.2f}); seed {a.seed}")
    write_audio(a.result_wav, (1 - amt) * x[:n] + amt * w, sr, run, "breathiness blend")


def mode_cross(run, ctx):
    a = run.args
    if not a.input_wav2 or not os.path.isfile(a.input_wav2):
        raise SVPError("Cross synthesis needs a second Sound (select two)")
    src2 = a.input_wav2
    if a.cross_fit in ("loop", "pad"):
        need_numpy("Fitting source 2")
        x, sr = read_audio(a.input_wav1)
        y, sr2 = read_audio(a.input_wav2)
        if sr != sr2:
            raise SVPError(f"the two Sounds have different sample rates ({sr} / {sr2})")
        n = len(x)
        if a.cross_fit == "loop":
            reps = int(math.ceil(n / max(len(y), 1)))
            y = np.tile(y, (reps, 1))[:n]
        else:
            y = np.vstack([y, np.zeros((max(0, n - len(y)), y.shape[1]))])[:n]
        src2 = a.tmp_prefix + "src2_fit.wav"
        sf.write(src2, y, sr, subtype="FLOAT")
        ctx["cleanup"].append(src2)
        run.note(f"source 2 {a.cross_fit}ed to source 1's length")
    if a.cross_control == "simple":
        # "Spectral cross-coupling" (formerly "cross mix"): NOT a linear blend of
        # the two sources. Low values: amplitude from source 1 with source 2's
        # frequency structure; high values invert the roles; 0.5 halves both.
        m = max(0.0, min(1.0, a.cross_mix))
        X, xx, Y, yy = 1 - m, m, m, 1 - m
        run.note(f"spectral cross-coupling {m:g}: amplitude {X:g}*S1 + {xx:g}*S2, "
                 f"frequency {Y:g}*S1 + {yy:g}*S2")
    else:
        X, xx, Y, yy = (max(0.0, v) for v in (a.cross_X, a.cross_x, a.cross_Y, a.cross_y))
        if X + xx <= 0 or Y + yy <= 0:
            raise SVPError("cross weights: each pair (X+x amplitude, Y+y frequency) must be > 0")
    d = ctx["dur"]
    run.ctrl("X", "amplitude from source 1 (-X)", "w", constant_ctrl(d, X))
    run.ctrl("x", "amplitude from source 2 (-x)", "w", constant_ctrl(d, xx))
    run.ctrl("Y", "frequency from source 1 (-Y)", "w", constant_ctrl(d, Y))
    run.ctrl("y", "frequency from source 2 (-y)", "w", constant_ctrl(d, yy))
    run.svp(["-S", a.input_wav1, "-s", src2] + ana(run, a.input_wav1)[2:-1] + ["-a", "-afft", "-Z"] + ctx["q"] +
            ["-Gcross", f"-X{X:.4f}", f"-x{xx:.4f}", f"-Y{Y:.4f}", f"-y{yy:.4f}", a.result_wav])


def mode_gate(run, ctx):
    a = run.args
    if not ctx["int"]:
        raise SVPError("Dynamic gate needs the intensity track")
    step = 0.005
    grid = time_grid(ctx["dur"], step)
    peak = max(v for _, v in ctx["int"])
    floor = peak - a.gate_threshold_db
    raw = []
    for t in grid:
        db = interp_at(ctx["int"], t)
        raw.append(1.0 if db >= floor else max(0.0, 10.0 ** ((db - floor) / 6.0)))
    tau = max(a.gate_smooth_ms, 0) / 1000.0
    g = one_pole(raw, step, tau * 0.25, tau)               # fast open, slower close
    p = run.ctrl("gain", "gate gain (-ggain)", "gain", list(zip(grid, g)))
    closed = sum(1 for v in g if v < 0.5) / len(g)
    run.note(f"gate floor {floor:.1f} dB ({a.gate_threshold_db:g} dB below peak); "
              f"{closed * 100:.0f}% of the time below half gain. Output amplitude envelope — "
              "it does not remove noise inside the spectrum")
    run.svp(ana(run, a.input_wav1, envelope=False) + ctx["q"] + ["-ggain", p, a.result_wav])


def mode_organic_vibrato(run, ctx):
    """SuperVP -trmdlp: randomised pitch modulation, envelope preserved as with
    -transke. Syntax (2.104.4 help): <minFreq>[-<maxFreq>],<minAmp>[-<maxAmp>][,interval]."""
    a = run.args
    require_feature(ctx, "Randomized pitch modulation", "Organic vibrato (-trmdlp)")
    r0, r1 = sorted((a.trmdlp_rate_min, a.trmdlp_rate_max))
    d0, d1 = sorted((a.trmdlp_depth_min, a.trmdlp_depth_max))
    if r0 <= 0 or d0 < 0 or a.trmdlp_interval <= 0:
        raise SVPError("organic vibrato: rates must be > 0, depths >= 0, interval > 0")
    fmt = lambda x: f"{x:g}"
    rate = fmt(r0) if r0 == r1 else f"{fmt(r0)}-{fmt(r1)}"
    dep = fmt(d0) if d0 == d1 else f"{fmt(d0)}-{fmt(d1)}"
    arg = f"{rate},{dep},{fmt(a.trmdlp_interval)}"
    d = ctx["dur"]
    run.ctrl("rmin", "modulation rate, minimum (-trmdlp)", "Hz", constant_ctrl(d, r0))
    run.ctrl("rmax", "modulation rate, maximum (-trmdlp)", "Hz", constant_ctrl(d, r1))
    run.ctrl("dmin", "modulation depth, minimum (-trmdlp)", "help units", constant_ctrl(d, d0))
    run.ctrl("dmax", "modulation depth, maximum (-trmdlp)", "help units", constant_ctrl(d, d1))
    run.note(f"randomised within these ranges by SuperVP, new values every {a.trmdlp_interval:g} s; "
             "the actual trajectory is internal to SuperVP and is not drawn")
    run.svp(ana(run, a.input_wav1) + ctx["q"] + ["-P1", "-trmdlp", arg, a.result_wav])


def mode_freq_shift(run, ctx):
    """True frequency shift in Hz (-Ffshift <file>, lines 'time shift_Hz').
    Standalone pass: never combined with time stretch or transposition, and
    no -P0/-P1 (phase synchronisation is incompatible with frequency shifting)."""
    a = run.args
    require_feature(ctx, "Frequency shift", "Frequency shift (-Ffshift)")
    dur = ctx["dur"]
    shape = a.fshift_shape
    base = a.fshift_hz
    if shape == "constant":
        pts = constant_ctrl(dur, base)
    else:
        step = 0.01
        grid = time_grid(dur, step)
        if shape == "ramp":
            vals = [base + (a.fshift_end_hz - base) * (t / dur if dur > 0 else 0) for t in grid]
        elif shape in ("follow_intensity", "inverse_intensity"):
            rel = intensity_rel(ctx["int"], grid)
            if rel is None:
                raise SVPError("frequency shift following intensity needs the intensity track")
            rel = one_pole(rel, step, 0.05)
            if shape == "inverse_intensity":
                rel = [1 - r for r in rel]
            vals = [base + a.fshift_depth_hz * r for r in rel]
        elif shape == "wander":
            vals = wander_curve(grid, dur, a.fshift_wander_rate, a.seed)
            vals = [base + a.fshift_depth_hz * v for v in vals]
            run.note(f"wander seed {a.seed}, {a.fshift_wander_rate:g} turns/s")
        else:
            raise SVPError(f"unknown frequency-shift shape {shape}")
        pts = list(zip(grid, vals))
    nyq = ctx["sr"] / 2.0
    if max(abs(v) for _, v in pts) >= nyq:
        raise SVPError(f"frequency shift reaches {max(abs(v) for _, v in pts):.0f} Hz, beyond Nyquist ({nyq:.0f} Hz)")
    p = run.ctrl("fshift", "frequency shift (-Ffshift)", "Hz", pts)
    run.note("true frequency shift: every partial moves by the same number of Hz, so harmonic "
             "spectra become inharmonic (unlike transposition in cents)")
    run.svp(ana(run, a.input_wav1, envelope=False) + ctx["q"] + ["-Ffshift", p, a.result_wav])


def pending_mode(run, ctx, feature, what, tokens):
    """Modes whose parameter format must be read from the installed help first.
    They never run a guessed command: they show the exact help section."""
    text = ctx["help_text"]
    supported = ctx["caps"].get(feature)
    found = []
    for tok in tokens:
        for blk in help_excerpt(text, tok):
            if blk not in found:
                found.append(blk)
    for blk in found:
        run.manifest.append("helpsec=" + blk.replace("\n", " || "))
    status = "listed in this SuperVP's help" if supported else "NOT listed in this SuperVP's help"
    raise SVPError(f"{what}: {status}. Its parameter format has not been confirmed, so no command "
                   f"is sent. The matching help section is shown below — paste it to complete this mode.")


def mode_spectral_denoise(run, ctx):
    """Two-pass SuperVP spectral subtraction.

    Pass 1 learns an averaged noise spectrum (M1 = mean + standard deviation)
    from a user-selected noise-only time segment using -avseg/-OM1.
    Pass 2 applies that SDIF profile with -Fsub. The analysis/quality settings
    are deliberately identical in both passes so the spectral-bin geometry of
    the learned profile matches the processing pass.
    """
    a = run.args
    require_feature(ctx, "Spectral subtraction denoise", "Spectral denoise (-Fsub)")
    start = float(a.denoise_noise_start)
    end = float(a.denoise_noise_end)
    dur = float(ctx["dur"])
    if start < 0 or end <= start or end > dur + 1e-6:
        raise SVPError(f"spectral denoise: noise segment must satisfy 0 <= start < end <= {dur:.3f} s "
                       f"(got {start:g}-{end:g} s)")
    beta = float(a.denoise_avbeta)
    sfac = float(a.denoise_avsfac)
    relax = float(a.denoise_avrelax)
    gamma = int(a.denoise_avgamma)
    det = int(bool(a.denoise_avdet))
    if beta < 0:
        raise SVPError("spectral denoise: maximum reduction (-avbeta) must be >= 0 dB")
    if relax < 0:
        raise SVPError("spectral denoise: relaxation (-avrelax) must be >= 0 ms")
    if gamma not in (1, 2):
        raise SVPError("spectral denoise: subtraction type (-avgamma) must be 1 (amplitude) or 2 (energy)")

    noise_profile = a.tmp_prefix + "noise_profile_M1.sdif"
    ctx["cleanup"].append(noise_profile)
    seg = f"{start:.6f},{end:.6f}"

    # ana(..., envelope=False) ends in -Z; remove only that resynthesis flag
    # for the analysis-only M1 pass. Keep the same -F0/-Mauto and q flags.
    learn = ana(run, a.input_wav1, envelope=False)
    if learn and learn[-1] == "-Z":
        learn = learn[:-1]
    run.note(f"spectral denoise noise-learning segment: {start:.3f}-{end:.3f} s; "
             "M1 stores mean + standard deviation per spectral bin")
    run.note(f"spectral subtraction: max reduction {beta:g} dB, std factor {sfac:g}, "
             f"relax {relax:g} ms, {'energy' if gamma == 2 else 'amplitude'} subtraction, "
             f"deterministic-noise handling {'on' if det else 'off'}")

    # Pass 1: SuperVP creates the SDIF noise model itself.
    run.svp(learn + ctx["q"] + ["-avseg", seg, "-OM1", noise_profile])

    # Pass 2: identical analysis settings, then spectral subtraction.
    run.svp(ana(run, a.input_wav1, envelope=False) + ctx["q"] +
            ["-Fsub", noise_profile,
             "-avbeta", f"{beta:g}",
             "-avsfac", f"{sfac:g}",
             "-avrelax", f"{relax:g}",
             "-avgamma", str(gamma),
             "-avdet", str(det),
             a.result_wav])


def mode_phase_diffusion(run, ctx):
    """Use SuperVP phase randomization as an effect.

    The installed 2.104.4 help documents -rnd_force for effect mode;
    -rnd_stval/-rnd_ff control randomization above the voiced/unvoiced
    frequency boundary (VUF), and -rnd_voi controls non-sinusoidal
    components below VUF. -rnd_sin only has a distinct target when
    sinusoidal detection is enabled; this mode does that explicitly with
    optional -shape 1 (intended for a single/monophonic source).
    """
    a = run.args
    require_feature(ctx, "Phase randomization", "Spectral phase diffusion (-rnd_*)")
    sin = float(a.phase_rnd_sin)
    voi = float(a.phase_rnd_voi)
    st = float(a.phase_rnd_stval)
    ff = float(a.phase_rnd_ff)
    shape = bool(a.phase_shape)
    for name, value in (("sinusoidal", sin), ("non-sinusoidal", voi), ("VUF/noise start", st)):
        if value < 0 or value > 1:
            raise SVPError(f"phase diffusion: {name} randomization must be in [0, 1] (got {value:g})")
    if ff <= 0:
        raise SVPError("phase diffusion: full-randomization frequency (-rnd_ff) must be > 0 kHz")

    args = ana(run, a.input_wav1, envelope=False) + ctx["q"]
    if shape:
        # The help states that sinusoidal detection is enabled in shape-invariant
        # mode. SuperVP can estimate the required VUF internally.
        args += ["-shape", "1", "-rnd_sin", f"{sin:g}"]
        run.note("phase diffusion: sinusoidal separation enabled with -shape 1; intended for one sound source")
    elif sin > 0:
        run.note("phase diffusion: sinusoidal randomization value ignored because sinusoidal separation (-shape 1) is off")

    args += ["-rnd_force",
             "-rnd_voi", f"{voi:g}",
             "-rnd_stval", f"{st:g}",
             "-rnd_ff", f"{ff:g}",
             a.result_wav]

    run.ctrl("rnd_voi", "phase randomization below VUF: non-sinusoidal (-rnd_voi)", "alpha*pi",
             constant_ctrl(ctx["dur"], voi))
    if shape:
        run.ctrl("rnd_sin", "phase randomization below VUF: sinusoidal (-rnd_sin)", "alpha*pi",
                 constant_ctrl(ctx["dur"], sin))
    run.ctrl("rnd_stval", "phase randomization at VUF (-rnd_stval)", "alpha*pi",
             constant_ctrl(ctx["dur"], st))
    run.ctrl("rnd_ff", "frequency of full phase randomization (-rnd_ff)", "kHz",
             constant_ctrl(ctx["dur"], ff))
    run.note(f"phase diffusion effect: non-sinusoidal {voi:g}, noise-at-VUF {st:g}, "
             f"full randomization by {ff:g} kHz" + (f", sinusoidal {sin:g}" if shape else ""))
    run.svp(args)


def mode_diagnostics(run, ctx):
    a = run.args
    text = ctx["help_text"]
    with open(a.diag_file, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(f"SuperVP Transform {VERSION} — diagnostics\nexe: {a.supervp_exe}\n")
        fh.write(f"help usable: {ctx['help_usable']}\n\nQuality flags:\n")
        for f in NEW_FLAGS:
            fh.write(f"  {f:12s} {'listed' if ctx['caps'].get(f) else 'NOT listed'}\n")
        fh.write("\nFeatures (v3.2):\n")
        for name in FEATURES:
            fh.write(f"  {name:30s} {'supported' if ctx['caps'].get(name) else 'not supported'}\n")
        fh.write("\nScouted:\n")
        for k, ok in ctx["scout"].items():
            fh.write(f"  {k:16s} {'found' if ok else 'not found'}\n")
        fh.write("\n" + text)
    for f in NEW_FLAGS:
        run.manifest.append(f"cap={f}|{'listed' if ctx['caps'].get(f) else 'NOT listed'}")
    for name in FEATURES:
        run.manifest.append(f"feature={name}|{'supported' if ctx['caps'].get(name) else 'not supported'}")
    for k, ok in ctx["scout"].items():
        run.manifest.append(f"scout={k}|{'found' if ok else 'not found'}")
    with open(a.diag_file, "a", encoding="utf-8", newline="\n") as fh:
        fh.write("\n\n===== Help sections for v3.2 features =====\n")
        for tok in EXCERPT_TOKENS:
            for blk in help_excerpt(text, tok):
                fh.write(f"\n--- {tok} ---\n{blk}\n")
    run.manifest.append(f"diag={a.diag_file}")


MODES = {
    "age": mode_age, "gender": mode_gender, "age_gender": mode_age_gender,
    "flatten_pitch": mode_flatten_pitch, "vibrato": mode_vibrato, "harmoniser": mode_harmoniser,
    "formant_shift": mode_formant_shift, "time_stretch": mode_time_stretch, "tremolo": mode_tremolo,
    "breathiness": mode_breathiness, "cross": mode_cross, "gate": mode_gate,
    "organic_vibrato": mode_organic_vibrato, "freq_shift": mode_freq_shift,
    "spectral_denoise": mode_spectral_denoise, "phase_diffusion": mode_phase_diffusion,
    "diagnostics": mode_diagnostics,
}


# =============================================================================
#  Main
# =============================================================================

POSITIONAL = ["input_wav1", "f0_file", "intensity_file", "done_file"]


def read_params_file(path):
    d = {}
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\r\n")
            if "=" in line and not line.lstrip().startswith("#"):
                k, v = line.split("=", 1)
                d[k.strip()] = v.strip()
    return d


def params_to_argv(path):
    d = read_params_file(path)
    argv = [d.pop(k, "") for k in POSITIONAL]
    for k, v in d.items():
        if v != "":                          # empty value = use the default
            argv += ["--" + k, v]
    return argv


def dict_from_argv(argv):
    d = {k: v for k, v in zip(POSITIONAL, argv[:4])}
    return d


def main():
    class _Parser(argparse.ArgumentParser):
        def error(self, message):                 # report instead of exiting with status 2
            raise SVPError("invalid parameter — " + message)

    ap = _Parser(description=f"SuperVP Transform backend v{VERSION}")
    ap.add_argument("input_wav1")
    ap.add_argument("f0_file")
    ap.add_argument("intensity_file")
    ap.add_argument("done_file")
    ap.add_argument("--supervp_exe", default="")
    ap.add_argument("--result_wav", default="")
    ap.add_argument("--tmp_prefix", default="")
    ap.add_argument("--manifest", default="")
    ap.add_argument("--diag_file", default="")
    ap.add_argument("--mode", default="age", choices=list(MODES))
    ap.add_argument("--profile", default="standard",
                    choices=["standard", "general", "voice", "percussive", "smeared"])
    ap.add_argument("--range_label", default="")
    ap.add_argument("--dry_run", action="store_true")
    ap.add_argument("--dry_run_flag", type=int, default=0)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--age_val", type=int, default=20)
    ap.add_argument("--gender_dir", default="female", choices=["female", "male"])
    ap.add_argument("--gender_amount", type=int, default=3)
    ap.add_argument("--gender_reinforce", type=int, default=1)
    ap.add_argument("--target_f0", type=float, default=0.0)
    ap.add_argument("--flatten_amount", type=float, default=1.0)
    ap.add_argument("--vibrato_freq", type=float, default=5.5)
    ap.add_argument("--vibrato_depth", type=float, default=50.0)
    ap.add_argument("--vibrato_voiced_only", type=int, default=1)
    ap.add_argument("--vibrato_fade", type=float, default=0.25)
    ap.add_argument("--harmoniser_interval", type=float, default=700.0)
    ap.add_argument("--harmoniser_mix", type=float, default=0.3)
    ap.add_argument("--formant_shape", default="constant",
                    choices=["constant", "ramp", "follow_f0", "follow_intensity", "wander"])
    ap.add_argument("--formant_shift_cents", type=float, default=200.0)
    ap.add_argument("--formant_end_cents", type=float, default=-200.0)
    ap.add_argument("--formant_depth_cents", type=float, default=300.0)
    ap.add_argument("--formant_wander_rate", type=float, default=1.0)
    ap.add_argument("--stretch_factor", type=float, default=1.5)
    ap.add_argument("--stretch_shape", default="constant",
                    choices=["constant", "voiced", "unvoiced", "ramp"])
    ap.add_argument("--tremolo_type", default="amplitude",
                    choices=["amplitude", "envelope", "trmdle", "native"])
    ap.add_argument("--tremolo_waveform", default="sine", choices=["sine", "triangle", "square", "saw"])
    ap.add_argument("--trmdlp_rate_min", type=float, default=4.5)
    ap.add_argument("--trmdlp_rate_max", type=float, default=6.5)
    ap.add_argument("--trmdlp_depth_min", type=float, default=20.0)
    ap.add_argument("--trmdlp_depth_max", type=float, default=60.0)
    ap.add_argument("--trmdlp_interval", type=float, default=0.4)
    ap.add_argument("--fshift_shape", default="constant",
                    choices=["constant", "ramp", "follow_intensity", "inverse_intensity", "wander"])
    ap.add_argument("--fshift_hz", type=float, default=-50.0)
    ap.add_argument("--fshift_end_hz", type=float, default=50.0)
    ap.add_argument("--fshift_depth_hz", type=float, default=100.0)
    ap.add_argument("--fshift_wander_rate", type=float, default=0.5)
    ap.add_argument("--tremolo_map", default="direct",
                    choices=["none", "direct", "inverse", "exaggerated", "quantised"])
    ap.add_argument("--tremolo_freq", type=float, default=5.0)
    ap.add_argument("--tremolo_amp_depth", type=float, default=0.6)
    ap.add_argument("--tremolo_env_depth", type=float, default=30.0)
    ap.add_argument("--tremolo_smooth_ms", type=float, default=50.0)
    ap.add_argument("--breathiness_amount", type=float, default=0.4)
    ap.add_argument("--cross_control", default="simple", choices=["simple", "advanced"])
    ap.add_argument("--cross_mix", type=float, default=0.5)
    ap.add_argument("--cross_X", type=float, default=1.0)
    ap.add_argument("--cross_x", type=float, default=0.0)
    ap.add_argument("--cross_Y", type=float, default=0.0)
    ap.add_argument("--cross_y", type=float, default=1.0)
    ap.add_argument("--cross_fit", default="as_is", choices=["as_is", "loop", "pad"])
    ap.add_argument("--input_wav2", default="")
    ap.add_argument("--gate_threshold_db", type=float, default=30.0)
    ap.add_argument("--gate_smooth_ms", type=float, default=40.0)
    ap.add_argument("--denoise_noise_start", type=float, default=0.0)
    ap.add_argument("--denoise_noise_end", type=float, default=0.25)
    ap.add_argument("--denoise_avbeta", type=float, default=20.0)
    ap.add_argument("--denoise_avsfac", type=float, default=1.0)
    ap.add_argument("--denoise_avrelax", type=float, default=30.0)
    ap.add_argument("--denoise_avgamma", type=int, default=1, choices=[1, 2])
    ap.add_argument("--denoise_avdet", type=int, default=0, choices=[0, 1])
    ap.add_argument("--phase_rnd_sin", type=float, default=0.0)
    ap.add_argument("--phase_rnd_voi", type=float, default=0.15)
    ap.add_argument("--phase_rnd_stval", type=float, default=0.30)
    ap.add_argument("--phase_rnd_ff", type=float, default=18.0)
    ap.add_argument("--phase_shape", type=int, default=0, choices=[0, 1])
    # Parameters arrive in a key=value file (one path argument), because a
    # command line cannot reliably carry empty values or values containing
    # spaces on Windows (Praat's runSubprocess does not quote arguments).
    argv = sys.argv[1:]
    if len(argv) == 1 and os.path.isfile(argv[0]):
        argv = params_to_argv(argv[0])
    try:
        a = ap.parse_args(argv)
    except SVPError as e:
        done = dict_from_argv(argv).get("done_file", "")
        msg = str(e)
        if done:
            with open(os.path.splitext(done)[0].replace("done", "log") + ".txt", "w",
                      encoding="utf-8") as fh:
                fh.write("ERROR: " + msg + "\n")
            with open(done, "w", encoding="utf-8") as fh:
                fh.write("error\n")
        sys.exit(0)
    a.dry_run = a.dry_run or bool(a.dry_run_flag)

    if not a.tmp_prefix:
        a.tmp_prefix = os.path.join(os.path.dirname(a.done_file), "svp_")
    log_path = a.tmp_prefix + "log.txt"
    manifest = a.manifest or a.tmp_prefix + "manifest.txt"
    if not a.diag_file:
        a.diag_file = a.tmp_prefix + "diagnostics.txt"
    open(log_path, "w").close()
    run = Run(a, log_path, manifest)
    ctx = {"cleanup": [], "profile": a.profile}

    def finish(status):
        with open(a.done_file, "w", encoding="utf-8") as fh:
            fh.write(status + "\n")

    try:
        run.log(f"=== SuperVP Transform v{VERSION} ===  mode {a.mode}  profile {a.profile}"
                + ("  [DRY RUN]" if a.dry_run else ""))
        if not a.supervp_exe or not os.path.isfile(a.supervp_exe):
            raise SVPError(f"SuperVP not found: {a.supervp_exe}")
        if a.mode != "diagnostics" and not os.path.isfile(a.input_wav1):
            raise SVPError(f"input WAV not found: {a.input_wav1}")
        cache = os.path.join(os.path.dirname(a.done_file), "supervp_help_cache.txt")
        help_text, cached = read_help(a.supervp_exe, cache, run.log)
        usable, caps, scout = capabilities(help_text)
        ctx.update(help_text=help_text, help_usable=usable, caps=caps, scout=scout)
        run.log(f"  help {'cached' if cached else 'read'}; "
                f"{'usable' if usable else 'NOT usable — new v3.0 flags disabled'}; "
                f"{sum(caps.values())}/{len(caps)} new flags listed")

        f0 = read_bpf(a.f0_file)
        it = read_bpf(a.intensity_file)
        f0v = f0_filled(f0)
        dur = max([p[0] for p in f0[-1:] + it[-1:]] or [1.0])
        sr = 44100
        if HAS_NUMPY and a.mode != "diagnostics":
            try:
                sr = sf.info(a.input_wav1).samplerate
                dur = sf.info(a.input_wav1).duration
            except RuntimeError:
                pass
        vals = [v for _, v in f0v]
        f0_info = {"has_f0": bool(f0v), "voiced_frac": len(f0v) / len(f0) if f0 else 0.0,
                   "f0_min": quantile(vals, 0.05) if vals else None,
                   "f0_max": quantile(vals, 0.95) if vals else None, "range_label": a.range_label}
        ctx.update(f0=f0, f0v=f0v, int=it, dur=dur, sr=sr, f0_info=f0_info)

        dropped, notes = [], []
        q, use_mauto = ([], False) if a.mode == "diagnostics" else \
            quality_flags(a.profile, caps if usable else {}, a.mode, sr, f0_info, notes, dropped,
                          is_transposing(a.mode, a.tremolo_type), uses_afft(a.mode, a.tremolo_type),
                          transients=a.mode not in NO_TRANSIENT_MODES)
        # v2 used -F0/-Mauto only in vibrato, harmoniser and time stretch (and
        # always in flatten); Standard reproduces exactly that.
        ctx.update(q=q, use_mauto=use_mauto, v2_mauto=(a.profile == "standard" and bool(f0v)))
        run.afft = f0_info.get("afft", ["-Afft"])
        run.afft_f0 = f0_info.get("afft_f0", False)
        run.use_mauto = bool(use_mauto)
        run.f0_ok = bool(f0v)
        for n in notes:
            run.note(n)
        for f, why in dropped:
            run.manifest.append(f"dropped={f}|{why}")
            run.log(f"  dropped {f}: {why}")

        MODES[a.mode](run, ctx)

        if not a.dry_run and a.mode != "diagnostics" and not os.path.isfile(a.result_wav):
            raise SVPError("no result file was produced")
        extra = [("mode", a.mode), ("profile", a.profile), ("help_usable", usable),
                 ("dry_run", int(a.dry_run)), ("expected_ratio", ctx.get("expected_ratio", 1.0)),
                 ("quality_flags", " ".join(q) if q else "(none)")]
        run.write_manifest(extra)
        finish("ok")
        run.log("OK")
    except SVPError as e:
        run.log("ERROR: " + str(e))
        try:
            run.write_manifest([("mode", a.mode), ("error", str(e))])
        except OSError:
            pass
        finish("error")
    except Exception:
        import traceback
        run.log("ERROR (internal):\n" + traceback.format_exc())
        finish("error")
    finally:
        for p in ctx.get("cleanup", []):
            if p and os.path.isfile(p):
                try:
                    os.remove(p)
                except OSError:
                    pass


if __name__ == "__main__":
    main()
