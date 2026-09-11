"""
ddsp_neural_drawing_engine.py - DDSP Neural Drawing Synthesizer engine
Version: 0.1.1 (2026)

Part of Praat AudioTools plugin.
Author: Shai Cohen, Department of Music, Bar-Ilan University.
License: MIT.

Called by DDSPNeuralDrawingSynthesizer.praat - not run directly.

What it does
------------
Turns a gesture drawn in Praat (a pitch curve and a loudness curve, stored as
breakpoints in a plain-text gesture file) into the two conditioning signals of
a pretrained Magenta DDSP solo-instrument model - f0_hz and loudness_db - and
renders them. There is no source audio and CREPE is never run: the curves ARE
the features.

Pipeline
--------
  gesture file (breakpoints)                      GESTURE (drawing)
    -> gesture transforms (transpose, invert,     TRANSFORMATION (symbolic)
       retrograde, contour)
    -> frames at the model's feature rate         CONTROL REPRESENTATION
    -> voicing, smoothing, pitch quantization,
       glide, vibrato / perturbation, unvoiced
       pitch holding, edge tapers
    -> pretrained DDSP Autoencoder                DDSP
    -> silence gate, level, resample, WAV         SOUND

Two modes:
  --mode controls : numpy only (no TensorFlow). Writes the processed control
                    curves for display and an additive SKETCH preview WAV.
                    Fast; this is what Praat's Preview button uses. The sketch
                    is a plain harmonic tone, NOT the neural model.
  --mode synth    : full DDSP render. Model download/cache, dependency check
                    and model inference are reused from
                    ddsp_neural_revoicing_engine.py (must sit in the same
                    folder), so there is exactly one copy of that code.

Changelog
---------
  0.1.1  Preview sketch: an all-silent gesture (every loudness point below the
         silence threshold) played at full level, because the sketch envelope
         was normalised to the loudest voiced frame and with nothing voiced
         that reference was the -120 dB floor itself. The envelope is now also
         multiplied by the voicing taper, so gaps and all-silent gestures are
         exact digital silence. DDSP synthesis was not affected (the silence
         gate already zeroed it). Reported by Shai.
  0.1    Initial release.

Honest limitations
------------------
  * The models were trained on real solo recordings. Pitch or loudness drawn
    far outside an instrument's training range still renders, but the timbre
    degrades; the stats report the model's mean training pitch when the
    checkpoint ships dataset statistics.
  * The model's trainable reverb is cropped at the gesture's end (the output
    length equals the drawn duration exactly), so end the loudness curve a
    little before the end of the canvas if you want the tail.
  * The synthesis rate is 16 kHz. Resampling to 44.1/48 kHz adds no content
    above ~8 kHz.
"""

import argparse
import math
import os
import sys
import time
import traceback
import wave

VERSION = "0.1.1"
GESTURE_MAGIC = "ddsp_drawing_gesture"
GESTURE_FORMAT_VERSION = 1

MODELS = ["Violin", "Flute", "Flute2", "Trumpet", "Tenor_Saxophone"]
PITCH_MODES = ["continuous", "chromatic", "major", "minor", "pentatonic"]
SCALES = {
    "chromatic": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
    "major": [0, 2, 4, 5, 7, 9, 11],
    "minor": [0, 2, 3, 5, 7, 8, 10],        # natural minor
    "pentatonic": [0, 2, 4, 7, 9],           # major pentatonic
}
NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
_NOTE_BASE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}

# Used when no model is loaded (controls mode). Synth mode reads the real
# values from the checkpoint's gin config and from ddsp.spectral_ops.
DEFAULT_FRAME_RATE = 250          # DDSP solo models: 64000 samples / 1000 steps
DEFAULT_SAMPLE_RATE = 16000
DEFAULT_LD_RANGE = 120.0          # ddsp 1.6.5 spectral_ops.LD_RANGE

F0_MIN_HZ = 20.0
F0_MAX_HZ = 7000.0
SKETCH_RATE = 22050
MAX_DISPLAY_ROWS = 800

_LOG_PATH = None


def log(msg):
    """User-facing text goes to stderr and is teed to --log (runSubprocess has
    no shell, so Praat cannot redirect stderr itself)."""
    line = str(msg) + "\n"
    sys.stderr.write(line)
    sys.stderr.flush()
    if _LOG_PATH:
        try:
            with open(_LOG_PATH, "a", encoding="utf-8") as f:
                f.write(line)
        except Exception:
            pass


# ===========================================================================
# 1. GESTURE - the drawn control representation (breakpoints, not frames)
# ===========================================================================
class Curve(object):
    """Breakpoints (t, value, brk). brk[i] = 1 means the pen was lifted between
    point i-1 and point i: no line joins them. For loudness that gap is silence;
    for pitch it is a leap (the previous pitch is held, then jumps)."""

    def __init__(self, t=None, v=None, brk=None):
        self.t = list(t or [])
        self.v = list(v or [])
        self.brk = list(brk or [0] * len(self.t))
        self.normalize()

    def __len__(self):
        return len(self.t)

    def copy(self):
        return Curve(self.t, self.v, self.brk)

    def normalize(self):
        """Sort by time (stable) and collapse duplicate times, last one wins -
        the same rule the Praat canvas uses when a click replaces a point."""
        rows = sorted(zip(self.t, self.v, self.brk, range(len(self.t))),
                      key=lambda r: (r[0], r[3]))
        out = []
        for t, v, b, _ in rows:
            if out and abs(out[-1][0] - t) < 1e-9:
                out[-1] = (t, v, b)
            else:
                out.append((t, v, b))
        self.t = [r[0] for r in out]
        self.v = [r[1] for r in out]
        self.brk = [int(r[2]) for r in out]
        if self.brk:
            self.brk[0] = 1


class Gesture(object):
    def __init__(self, duration, pitch=None, loudness=None, meta=None):
        self.duration = float(duration)
        self.pitch = pitch if pitch is not None else Curve()        # Hz
        self.loudness = loudness if loudness is not None else Curve()  # dB
        self.meta = dict(meta or {})

    def copy(self):
        return Gesture(self.duration, self.pitch.copy(), self.loudness.copy(),
                       self.meta)


def _parse_numbers(line):
    parts = line.replace(",", " ").replace("\t", " ").split()
    return [float(p) for p in parts]


def read_gesture(path):
    """Read the human-readable gesture format written by the Praat canvas:

        format ddsp_drawing_gesture 1
        duration 5.0
        [PITCH]
        0.000 220.0 0        <- time_s  value  [break]
        [LOUDNESS]
        0.000 -60 0

    Also accepts two-column rows, comma separators and '#' comments, so hand
    written or externally generated gestures load too."""
    duration = None
    meta = {}
    section = None
    curves = {"pitch": ([], [], []), "loudness": ([], [], [])}
    with open(path, "r", encoding="utf-8-sig") as f:
        for lineno, raw in enumerate(f, 1):
            line = raw.split("#", 1)[0].strip()
            if not line:
                continue
            up = line.upper()
            if up in ("[PITCH]", "[LOUDNESS]"):
                section = up[1:-1].lower()
                continue
            if section is None:
                key, _, rest = line.partition(" ")
                key = key.lower()
                if key == "duration":
                    duration = float(rest.split()[0])
                elif key:
                    meta[key] = rest.strip()
                continue
            try:
                nums = _parse_numbers(line)
            except ValueError:
                raise ValueError("gesture file line %d is not numeric: %r"
                                 % (lineno, raw.strip()))
            if len(nums) < 2:
                raise ValueError("gesture file line %d needs time and value"
                                 % lineno)
            t, v = nums[0], nums[1]
            b = int(round(nums[2])) if len(nums) > 2 else 0
            if not (math.isfinite(t) and math.isfinite(v)):
                raise ValueError("gesture file line %d is not finite" % lineno)
            if section == "pitch" and v <= 0:
                raise ValueError("gesture file line %d: pitch must be > 0 Hz"
                                 % lineno)
            ts, vs, bs = curves[section]
            ts.append(t)
            vs.append(v)
            bs.append(1 if b else 0)
    if duration is None:
        allt = curves["pitch"][0] + curves["loudness"][0]
        duration = max(allt) if allt else 0.0
    if duration <= 0:
        raise ValueError("gesture has no duration")
    g = Gesture(duration, Curve(*curves["pitch"]), Curve(*curves["loudness"]),
                meta)
    # Points outside the canvas are dropped rather than silently extending it.
    for c in (g.pitch, g.loudness):
        keep = [i for i, t in enumerate(c.t) if -1e-9 <= t <= duration + 1e-9]
        c.t = [min(max(c.t[i], 0.0), duration) for i in keep]
        c.v = [c.v[i] for i in keep]
        c.brk = [c.brk[i] for i in keep]
        c.normalize()
    return g


def write_gesture(g, path):
    lines = ["# DDSP Neural Drawing Synthesizer - gesture file",
             "# rows: time_s value break   (break=1: pen lifted before point)",
             "format %s %d" % (GESTURE_MAGIC, GESTURE_FORMAT_VERSION),
             "duration %.6f" % g.duration]
    for k, v in sorted(g.meta.items()):
        if k not in ("format", "duration"):
            lines.append("%s %s" % (k, v))
    for name, c, fmt in (("PITCH", g.pitch, "%.6f %.4f %d"),
                         ("LOUDNESS", g.loudness, "%.6f %.3f %d")):
        lines.append("[%s]" % name)
        for t, v, b in zip(c.t, c.v, c.brk):
            lines.append(fmt % (t, v, b))
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


# ===========================================================================
# 2. TRANSFORMATIONS
#    Gesture-level transforms act on breakpoints (symbolic, before rendering);
#    frame-level transforms act on the rendered pitch curve. New transforms are
#    one function plus one registry entry each.
# ===========================================================================
def hz_to_st(hz):
    return 69.0 + 12.0 * math.log(hz / 440.0, 2.0)


def st_to_hz(st):
    return 440.0 * 2.0 ** ((st - 69.0) / 12.0)


def _median(xs):
    s = sorted(xs)
    n = len(s)
    if n == 0:
        return 0.0
    return s[n // 2] if n % 2 else 0.5 * (s[n // 2 - 1] + s[n // 2])


def gx_transpose(g, semitones=0.0):
    f = 2.0 ** (float(semitones) / 12.0)
    g.pitch.v = [v * f for v in g.pitch.v]
    return g


def gx_invert(g, axis_hz=None):
    """Mirror the pitch contour. Default axis = centre of the drawn range, so
    the gesture keeps its register."""
    if not g.pitch.v:
        return g
    st = [hz_to_st(v) for v in g.pitch.v]
    c = hz_to_st(float(axis_hz)) if axis_hz else 0.5 * (min(st) + max(st))
    g.pitch.v = [st_to_hz(2.0 * c - s) for s in st]
    return g


def gx_retrograde(g):
    for c in (g.pitch, g.loudness):
        n = len(c)
        if n == 0:
            continue
        t = [g.duration - c.t[n - 1 - j] for j in range(n)]
        v = [c.v[n - 1 - j] for j in range(n)]
        # brk[j] describes the segment (j-1, j); reversed, that segment was the
        # old segment (n-1-j, n-j), whose flag lives on old point n-j.
        b = [1] + [c.brk[n - j] for j in range(1, n)]
        c.t, c.v, c.brk = t, v, b
        c.normalize()
    return g


def gx_contour(g, factor=1.0):
    """Compress (<1) or expand (>1) every interval around the median pitch."""
    if not g.pitch.v:
        return g
    st = [hz_to_st(v) for v in g.pitch.v]
    c = _median(st)
    g.pitch.v = [st_to_hz(c + float(factor) * (s - c)) for s in st]
    return g


GESTURE_TRANSFORMS = {
    "transpose": gx_transpose,
    "invert": gx_invert,
    "retrograde": gx_retrograde,
    "contour": gx_contour,
}


def fx_vibrato(ctx, rate_hz=5.5, depth_cents=25.0, delay_ms=250.0):
    """Sinusoidal vibrato that fades in after each note onset."""
    import numpy as np
    fr = ctx["frame_rate"]
    voiced = ctx["voiced"]
    since = _frames_since_onset(voiced) / fr
    ramp = np.clip((since - float(delay_ms) / 1000.0) / 0.2, 0.0, 1.0)
    phase = 2.0 * np.pi * float(rate_hz) * ctx["times"]
    ctx["st"] = ctx["st"] + ramp * (float(depth_cents) / 100.0) * np.sin(phase)


def fx_perturb(ctx, depth_cents=20.0, seed=1, speed_hz=3.0):
    """Seeded stochastic pitch drift: Gaussian noise low-passed to ~speed_hz,
    scaled to depth_cents standard deviation."""
    import numpy as np
    fr = ctx["frame_rate"]
    rng = np.random.default_rng(int(seed))
    n = ctx["st"].size
    noise = rng.standard_normal(n)
    sigma = fr / (2.0 * np.pi * max(float(speed_hz), 0.1))
    noise = _gauss_smooth(noise, sigma)
    sd = float(np.std(noise))
    if sd > 1e-12:
        ctx["st"] = ctx["st"] + (float(depth_cents) / 100.0) * noise / sd


FRAME_TRANSFORMS = {
    "vibrato": fx_vibrato,
    "perturb": fx_perturb,
}


def parse_transforms(spec):
    """'transpose 12; vibrato 5.5 30; retrograde' -> [(name, [args])].
    Unknown names are reported, not fatal."""
    out, warnings = [], []
    if not spec or spec.strip().lower() in ("", "none", "-"):
        return out, warnings
    for item in spec.split(";"):
        parts = item.replace(",", " ").replace("=", " ").split()
        if not parts:
            continue
        name = parts[0].lower()
        args = []
        for p in parts[1:]:
            try:
                args.append(float(p))
            except ValueError:
                pass   # tolerate keyword labels like "depth 30"
        if name in GESTURE_TRANSFORMS or name in FRAME_TRANSFORMS:
            out.append((name, args))
        else:
            warnings.append("unknown_transform:%s" % name)
    return out, warnings


# ===========================================================================
# 3. CONTROL RENDERING - breakpoints -> DDSP frames
# ===========================================================================
def _gauss_smooth(x, sigma_frames):
    import numpy as np
    x = np.asarray(x, dtype="float64")
    if sigma_frames < 0.5 or x.size < 3:
        return x.copy()
    r = int(math.ceil(3.0 * sigma_frames))
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / float(sigma_frames)) ** 2)
    k /= k.sum()
    xp = np.pad(x, r, mode="edge")
    return np.convolve(xp, k, mode="valid")


def _boxcar(x, width):
    import numpy as np
    w = int(width)
    if w < 2 or x.size < 3:
        return x.copy()
    xp = np.pad(x, w, mode="edge")
    return np.convolve(xp, np.ones(w) / w, mode="same")[w:-w]


def _runs(mask):
    """[(start, end_exclusive), ...] of True runs."""
    import numpy as np
    m = np.asarray(mask, dtype=bool)
    if m.size == 0:
        return []
    d = np.diff(np.concatenate(([0], m.astype(np.int8), [0])))
    return list(zip(np.flatnonzero(d == 1), np.flatnonzero(d == -1)))


def _frames_since_onset(voiced):
    import numpy as np
    out = np.zeros(voiced.size)
    for a, b in _runs(voiced):
        out[a:b] = np.arange(b - a)
    return out


def _fill_from_mask(x, mask):
    """Replace values outside mask with the nearest value inside it."""
    import numpy as np
    x = np.asarray(x, dtype="float64").copy()
    idx = np.flatnonzero(mask)
    if idx.size == 0:
        return x
    pos = np.arange(x.size)
    nearest = idx[np.clip(np.searchsorted(idx, pos), 0, idx.size - 1)]
    left = idx[np.clip(np.searchsorted(idx, pos) - 1, 0, idx.size - 1)]
    pick = np.where(np.abs(pos - left) <= np.abs(nearest - pos), left, nearest)
    return x[pick]


def curve_to_frames(curve, times, to_domain=None):
    """Linear interpolation within strokes. Returns (values, on) where `on`
    marks frames inside a connected stroke. Outside strokes the value is held
    (previous point; first point before the curve starts)."""
    import numpy as np
    n = len(curve)
    if n == 0:
        return None, np.zeros(times.size, dtype=bool)
    pt = np.asarray(curve.t, dtype="float64")
    pv = np.asarray([to_domain(v) if to_domain else v for v in curve.v],
                    dtype="float64")
    pb = np.asarray(curve.brk, dtype=np.int8)
    i = np.searchsorted(pt, times, side="right")        # 0..n
    vals = np.empty(times.size)
    on = np.zeros(times.size, dtype=bool)
    before = i == 0
    vals[before] = pv[0]
    after = i == n
    vals[after] = pv[-1]
    on[after] = np.abs(times[after] - pt[-1]) < 1e-9
    mid = ~(before | after)
    j = i[mid]
    conn = pb[j] == 0
    t0, t1 = pt[j - 1], pt[j]
    frac = np.clip((times[mid] - t0) / np.maximum(t1 - t0, 1e-12), 0.0, 1.0)
    lin = pv[j - 1] + frac * (pv[j] - pv[j - 1])
    vals[mid] = np.where(conn, lin, pv[j - 1])
    on[mid] = conn
    return vals, on


def _onsets_take_next_pitch(curve, times, st, voiced):
    import numpy as np
    pt = np.asarray(curve.t, dtype="float64")
    for i in range(1, len(curve)):
        if not curve.brk[i]:
            continue
        ga = int(np.searchsorted(times, pt[i - 1], side="right"))
        gb = int(np.searchsorted(times, pt[i], side="left"))
        if gb <= ga:
            continue
        nxt = hz_to_st(curve.v[i])
        runs = _runs(voiced)
        for k, (a, b) in enumerate(runs):
            if ga <= a <= gb:
                # Jump midway through the silence before this onset, so
                # smoothing and glide settle there - not in the previous
                # note's tail, nor in this note's attack.
                prev_end = runs[k - 1][1] if k > 0 else 0
                start = max(ga, prev_end)
                st[(start + a) // 2:gb] = nxt
                break


def _quantize(st, mode, root_pc, hysteresis=0.15):
    """Snap to the scale with hysteresis so a line hovering on a boundary does
    not chatter between two notes."""
    import numpy as np
    pcs = sorted(set((root_pc + p) % 12 for p in SCALES[mode]))
    lo, hi = int(math.floor(np.min(st))) - 12, int(math.ceil(np.max(st))) + 12
    grid = np.array([m for m in range(lo, hi + 1) if m % 12 in pcs],
                    dtype="float64")
    out = np.empty_like(st)
    cur = None
    for k, s in enumerate(st):
        near = grid[int(np.argmin(np.abs(grid - s)))]
        if cur is None or (near != cur and
                           abs(s - cur) - abs(s - near) > hysteresis):
            cur = near
        out[k] = cur
    return out


def parse_root(name):
    s = (name or "C").strip()
    if not s:
        return 0
    base = _NOTE_BASE.get(s[0].upper())
    if base is None:
        raise ValueError("scale root must be a note name like C, F#, Bb")
    for ch in s[1:]:
        if ch in ("#", "s"):
            base += 1
        elif ch in ("b", "B"):
            base -= 1
    return base % 12


def _raised_cosine_taper(mask, edge_frames):
    """0..1 weight that ramps up at each run start and down at each run end,
    INSIDE the run (so nothing sounds before a drawn onset)."""
    import numpy as np
    w = np.zeros(mask.size)
    e = max(int(edge_frames), 1)
    for a, b in _runs(mask):
        k = np.arange(b - a, dtype="float64")
        d = np.minimum(k + 1.0, (b - a) - k)
        w[a:b] = 0.5 - 0.5 * np.cos(np.pi * np.clip(d / e, 0.0, 1.0))
    return w


def render_controls(gesture, settings, frame_rate, ld_range):
    """The core of the tool: GESTURE -> CONTROL REPRESENTATION.
    Returns a dict of frame arrays plus diagnostics."""
    import numpy as np
    warnings = []
    g = gesture.copy()
    fr = float(frame_rate)
    floor_db = -float(ld_range)

    transforms, tw = parse_transforms(settings["transforms"])
    warnings += tw
    for name, args in transforms:
        if name in GESTURE_TRANSFORMS:
            GESTURE_TRANSFORMS[name](g, *args)

    if len(g.pitch) == 0:
        raise ValueError("no pitch curve drawn - draw at least two points in "
                         "the PITCH panel")

    n = int(math.ceil(g.duration * fr - 1e-9))
    n = max(n, 2)
    times = np.arange(n) / fr

    st_raw, p_on = curve_to_frames(g.pitch, times, hz_to_st)
    gesture_mode = settings["draw_mode"] == "gesture"

    # ---- voicing ----------------------------------------------------------
    if gesture_mode:
        voiced = p_on.copy()
        ld_raw = None
    else:
        ld_raw, l_on = curve_to_frames(g.loudness, times)
        if ld_raw is None:
            default_db = min(settings["loudness_max"] - 10.0, -20.0)
            warnings.append("no_loudness_drawn:flat_%.0fdB_under_pitch"
                            % default_db)
            ld_raw = np.full(n, default_db)
            l_on = p_on.copy()
        voiced = l_on & (ld_raw >= settings["silence_threshold"])
    for a, b in _runs(voiced):                 # drop sub-12 ms fragments
        if b - a < 3:
            voiced[a:b] = False

    # A note whose onset falls inside a pitch gap (pen lifted between two
    # pitch strokes) starts on the NEXT stroke's pitch, not on the held end
    # of the previous one - otherwise it would begin on a stale note and leap.
    _onsets_take_next_pitch(g.pitch, times, st_raw, voiced)

    # ---- pitch: smoothing -> (gesture loudness) -> quantize -> glide --------
    sigma_p = settings["pitch_smoothing"] / 100.0 * 0.25 * fr
    st = _gauss_smooth(st_raw, sigma_p)

    if gesture_mode:
        vel = np.abs(np.gradient(st)) * fr               # semitones per second
        run_edges = np.zeros(n, dtype=bool)
        for a, b in _runs(voiced):
            run_edges[a] = True
            run_edges[b - 1] = True
        vel[~voiced | run_edges] = 0.0
        vel = _gauss_smooth(vel, 0.05 * fr)
        ref = float(np.percentile(vel[voiced], 95)) if voiced.any() else 0.0
        m = np.clip(vel / ref, 0.0, 1.0) if ref > 1e-6 else np.zeros(n)
        ld_raw = settings["loudness_max"] - settings["motion_depth"] * (1.0 - m)

    mode = settings["pitch_mode"]
    if mode != "continuous":
        st = _quantize(st, mode, settings["root_pc"])
        glide = settings["glide_ms"] / 1000.0 * fr
        if glide >= 2:
            half = max(int(round(glide / 2.0)), 1)
            st = _boxcar(_boxcar(st, half), half)

    ctx = {"st": st, "times": times, "voiced": voiced, "frame_rate": fr}
    for name, args in transforms:
        if name in FRAME_TRANSFORMS:
            FRAME_TRANSFORMS[name](ctx, *args)
    st = ctx["st"]

    # ---- unvoiced pitch: hold the previous note, switch just before the next
    # onset, so no phantom glide is rendered through a gap.
    edge = max(int(round(settings["edge_ms"] / 1000.0 * fr)), 1)
    vruns = _runs(voiced)
    if vruns:
        prev_end = 0
        first = True
        for a, b in vruns:
            if a > prev_end:
                if first:
                    st[prev_end:a] = st[a]
                else:
                    sw = max(prev_end, a - edge - 2)
                    st[prev_end:sw] = st[prev_end - 1]
                    st[sw:a] = st[a]
            first = False
            prev_end = b
        if prev_end < n:
            st[prev_end:] = st[prev_end - 1]
    else:
        warnings.append("nothing_voiced")

    f0 = np.clip(440.0 * 2.0 ** ((st - 69.0) / 12.0), F0_MIN_HZ, F0_MAX_HZ)
    if np.any(f0[voiced] >= F0_MAX_HZ - 1e-6) or np.any(f0[voiced] <= F0_MIN_HZ + 1e-6):
        warnings.append("pitch_clamped_to_%d-%dHz" % (F0_MIN_HZ, F0_MAX_HZ))

    # ---- loudness: hold into gaps, smooth, taper at voicing edges ----------
    ld = _fill_from_mask(ld_raw, voiced) if voiced.any() else ld_raw.copy()
    sigma_l = settings["loudness_smoothing"] / 100.0 * 0.25 * fr
    ld = _gauss_smooth(ld, sigma_l)
    ld = np.clip(ld, floor_db, 0.0)
    w = _raised_cosine_taper(voiced, edge)
    ld = floor_db + w * (ld - floor_db)

    vf = f0[voiced]
    return {
        "times": times, "f0_hz": f0.astype("float32"),
        "loudness_db": ld.astype("float32"), "voiced": voiced, "taper": w,
        "frame_rate": fr, "floor_db": floor_db, "n_frames": n,
        "duration": g.duration, "warnings": warnings,
        "n_notes": len(vruns),
        "voiced_fraction": float(voiced.mean()),
        "f0_min": float(vf.min()) if vf.size else 0.0,
        "f0_max": float(vf.max()) if vf.size else 0.0,
        "f0_median": float(np.median(vf)) if vf.size else 0.0,
        "loudness_max": float(ld[voiced].max()) if voiced.any() else floor_db,
    }


def gate_curve(voiced, frame_rate, release_ms, fade_ms=40.0):
    """Frame-rate gain for the post-synthesis silence gate: 1 while voiced and
    for release_ms after each note (so the model's reverb tail survives), then
    a raised-cosine fade to true digital silence. Opens fade_ms BEFORE onsets
    so the gate never shaves an attack. release_ms <= 0 disables it."""
    import numpy as np
    n = voiced.size
    if release_ms <= 0:
        return np.ones(n)
    rel = int(round(release_ms / 1000.0 * frame_rate))
    fade = max(int(round(fade_ms / 1000.0 * frame_rate)), 1)
    open_ = np.zeros(n, dtype=bool)
    for a, b in _runs(voiced):
        open_[max(0, a - fade):min(n, b + rel + fade)] = True
    return _raised_cosine_taper(open_, fade)


def frames_to_samples(x, frame_rate, sr, n_samples):
    import numpy as np
    t_frames = np.arange(x.size) / float(frame_rate)
    t_samp = np.arange(n_samples) / float(sr)
    return np.interp(t_samp, t_frames, x)


# ===========================================================================
# 4. OUTPUT HELPERS
# ===========================================================================
def write_controls_table(ctl, path):
    """Tab-separated, decimated to <= MAX_DISPLAY_ROWS for the Praat overlay.
    Voicing transitions are always kept so gaps are drawn where they are."""
    import numpy as np
    n = ctl["n_frames"]
    step = max(1, int(math.ceil(n / float(MAX_DISPLAY_ROWS))))
    keep = np.zeros(n, dtype=bool)
    keep[::step] = True
    keep[-1] = True
    v = ctl["voiced"]
    trans = np.flatnonzero(np.diff(v.astype(np.int8)) != 0)
    keep[trans] = True
    keep[np.minimum(trans + 1, n - 1)] = True
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("time\tf0_hz\tloudness_db\tvoiced\n")
        for k in np.flatnonzero(keep):
            f.write("%.5f\t%.3f\t%.3f\t%d\n" % (ctl["times"][k], ctl["f0_hz"][k],
                                               ctl["loudness_db"][k], int(v[k])))


def _write_wav16(path, audio, sr):
    import numpy as np
    a = np.clip(np.asarray(audio, dtype="float64"), -1.0, 1.0)
    pcm = (a * 32767.0).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(int(sr))
        w.writeframes(pcm.tobytes())


def render_sketch(ctl, path, sr=SKETCH_RATE):
    """Plain additive harmonic tone following the processed curves. It is an
    audition of the GESTURE (pitch, loudness, articulation), not of the model."""
    import numpy as np
    fr = ctl["frame_rate"]
    n_s = int(round(ctl["duration"] * sr))
    f0 = frames_to_samples(ctl["f0_hz"].astype("float64"), fr, sr, n_s)
    ld = ctl["loudness_db"].astype("float64")
    ref = ctl["loudness_max"]
    amp_f = 10.0 ** ((ld - ref) / 20.0)
    amp = frames_to_samples(amp_f, fr, sr, n_s)
    # amp_f is relative to the loudest VOICED frame; when nothing is voiced
    # that reference is the floor itself and silence would come out at full
    # level. The voicing taper makes gaps - and an all-silent gesture - exact 0.
    amp *= frames_to_samples(ctl["taper"].astype("float64"), fr, sr, n_s)
    if not ctl["voiced"].any():
        _write_wav16(path, np.zeros(n_s), sr)
        return
    phase = 2.0 * np.pi * np.cumsum(f0) / sr
    nyq = 0.45 * sr
    out = np.zeros(n_s)
    fmin = max(float(np.min(f0)), F0_MIN_HZ)
    for k in range(1, int(min(40, nyq // fmin)) + 1):
        lim = np.clip((nyq - k * f0) / (0.05 * nyq), 0.0, 1.0)
        out += lim * np.sin(k * phase) / (k ** 1.3)
    out *= amp
    peak = float(np.max(np.abs(out))) if out.size else 0.0
    if peak > 1e-9:
        out *= 0.7 / peak
    _apply_end_fades(out, sr)
    _write_wav16(path, out, sr)


def _apply_end_fades(a, sr, start_ms=2.0, end_ms=10.0):
    import numpy as np
    for ms, sl in ((start_ms, "start"), (end_ms, "end")):
        m = min(int(sr * ms / 1000.0), a.size // 2)
        if m < 2:
            continue
        ramp = 0.5 - 0.5 * np.cos(np.pi * np.arange(m) / m)
        if sl == "start":
            a[:m] *= ramp
        else:
            a[-m:] *= ramp[::-1]


STATS_KEYS = [
    "status", "version", "mode", "model", "draw_mode", "pitch_mode",
    "duration_s", "output_duration_s", "frame_rate", "time_steps", "hop_size",
    "synthesis_rate", "output_sample_rate", "loudness_floor_db",
    "n_notes", "voiced_fraction", "f0_min_hz", "f0_max_hz", "f0_median_hz",
    "loudness_max_db", "model_mean_pitch_hz", "transforms",
    "output_level_mode", "level_gain_db", "peak_limited_db",
    "output_rms", "output_peak", "gate_release_ms",
    "model_source", "model_cache_path",
    "timing_dependencies_s", "timing_model_prepare_s", "timing_controls_s",
    "timing_inference_s", "timing_total_s", "warnings",
]


def write_stats(path, d):
    if not path:
        return
    try:
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            for k in STATS_KEYS:
                v = d.get(k, "")
                f.write("%s=%s\n" % (k, "" if v is None else v))
    except Exception as e:
        log("WARNING: could not write stats file: %s" % e)


# ===========================================================================
# 5. MODEL (reused from the revoicing engine)
# ===========================================================================
def import_revoicing_engine():
    here = os.path.dirname(os.path.abspath(__file__))
    if here not in sys.path:
        sys.path.insert(0, here)
    try:
        import ddsp_neural_revoicing_engine as rev
    except ImportError as e:
        raise RuntimeError(
            "ddsp_neural_revoicing_engine.py was not found next to this "
            "engine (%s). The drawing synthesizer reuses its model download, "
            "cache and inference code. (%s)" % (here, e))
    rev._LOG_PATH = _LOG_PATH
    return rev


def model_geometry(model_dir, rev):
    """Feature frame rate, hop and sample rate as the checkpoint was trained,
    read from its operative gin config - not assumed."""
    import gin
    import ddsp.training  # noqa: F401  (registers the gin configurables)
    geo = {"warnings": []}
    with gin.unlock_config():
        gin.parse_config_file(rev._find_gin(model_dir), skip_unknown=True)
    try:
        steps = int(gin.query_parameter("F0LoudnessPreprocessor.time_steps"))
        n_samp = int(gin.query_parameter("Harmonic.n_samples"))
    except Exception:
        steps, n_samp = 1000, 64000
        geo["warnings"].append("gin_geometry_fallback_1000x64000")
    try:
        sr = int(gin.query_parameter("Harmonic.sample_rate"))
    except Exception:
        sr = DEFAULT_SAMPLE_RATE
    if n_samp % steps:
        raise RuntimeError("checkpoint hop is not an integer (%d samples / %d "
                           "steps)" % (n_samp, steps))
    hop = n_samp // steps
    geo.update(sample_rate=sr, hop=hop, frame_rate=sr / float(hop))
    try:
        enc = gin.query_parameter("Autoencoder.encoder")
        if enc is not None:
            geo["warnings"].append("model_has_audio_encoder:silent_reference_used")
    except Exception:
        pass
    return geo


def model_mean_pitch_hz(model_dir):
    """Mean MIDI pitch of the training data, if the checkpoint ships
    dataset_statistics.pkl and it can be unpickled here. 0 if unavailable."""
    p = os.path.join(model_dir, "dataset_statistics.pkl")
    if not os.path.isfile(p):
        return 0.0
    try:
        import pickle
        with open(p, "rb") as f:
            st = pickle.load(f)
        mp = float(st["mean_pitch"])
        return st_to_hz(mp) if mp < 200 else mp
    except Exception:
        return 0.0


def match_drawn_loudness(audio, ctl, sr):
    """Gain (dB) that makes the rendered sound's DDSP loudness match the drawn
    loudness over the sustained parts of the notes. Returns None if it cannot
    be measured."""
    import numpy as np
    import ddsp.spectral_ops as so
    meas = np.asarray(so.compute_loudness(audio, sample_rate=sr,
                                          frame_rate=int(ctl["frame_rate"])))
    meas = meas.reshape(-1)
    m = min(meas.size, ctl["n_frames"])
    target = ctl["loudness_db"][:m].astype("float64")
    sel = (ctl["taper"][:m] > 0.95) & (target > ctl["floor_db"] + 20.0)
    if sel.sum() < 5:
        return None
    return float(np.clip(np.median(target[sel] - meas[:m][sel]), -60.0, 60.0))


# ===========================================================================
# 6. MAIN
# ===========================================================================
def parse_args(argv=None):
    p = argparse.ArgumentParser(
        description="DDSP Neural Drawing Synthesizer engine (Praat AudioTools).")
    p.add_argument("--mode", choices=["controls", "synth"], default="synth")
    p.add_argument("--gesture", required=True)
    p.add_argument("--model", default="Violin", choices=MODELS)
    p.add_argument("--draw_mode", choices=["curves", "gesture"], default="curves")
    p.add_argument("--pitch_mode", choices=PITCH_MODES, default="continuous")
    p.add_argument("--scale_root", default="C")
    p.add_argument("--pitch_smoothing", type=float, default=10.0)
    p.add_argument("--loudness_smoothing", type=float, default=10.0)
    p.add_argument("--silence_threshold", type=float, default=-70.0)
    p.add_argument("--loudness_max", type=float, default=-15.0)
    p.add_argument("--motion_depth", type=float, default=25.0)
    p.add_argument("--glide_ms", type=float, default=30.0)
    p.add_argument("--edge_ms", type=float, default=15.0)
    p.add_argument("--release_ms", type=float, default=1200.0)
    p.add_argument("--transforms", default="none")
    p.add_argument("--output_level", choices=["match", "peak", "raw"],
                   default="match")
    p.add_argument("--output_rate", type=int, default=44100)
    p.add_argument("--controls_out", default="")
    p.add_argument("--preview_wav", default="")
    p.add_argument("--output", default="")
    p.add_argument("--stats", default="")
    p.add_argument("--cache_dir", default="")
    p.add_argument("--log", default="")
    return p.parse_args(argv)


def settings_from_args(a):
    return {
        "draw_mode": a.draw_mode,
        "pitch_mode": a.pitch_mode,
        "root_pc": parse_root(a.scale_root),
        "pitch_smoothing": min(max(a.pitch_smoothing, 0.0), 100.0),
        "loudness_smoothing": min(max(a.loudness_smoothing, 0.0), 100.0),
        "silence_threshold": a.silence_threshold,
        "loudness_max": a.loudness_max,
        "motion_depth": max(a.motion_depth, 0.0),
        "glide_ms": max(a.glide_ms, 0.0),
        "edge_ms": max(a.edge_ms, 1.0),
        "transforms": a.transforms,
    }


def main(argv=None):
    global _LOG_PATH
    t_total = time.perf_counter()
    a = parse_args(argv)
    if a.log:
        _LOG_PATH = a.log
    stats = {"status": "FAILURE", "version": VERSION, "mode": a.mode,
             "model": a.model, "draw_mode": a.draw_mode,
             "pitch_mode": a.pitch_mode, "transforms": a.transforms,
             "gate_release_ms": a.release_ms}
    warnings = []
    try:
        try:
            import numpy as np
        except ImportError:
            raise RuntimeError("numpy is not installed in this Python")
        settings = settings_from_args(a)
        gesture = read_gesture(a.gesture)
        stats["duration_s"] = round(gesture.duration, 4)

        if a.mode == "controls":
            t = time.perf_counter()
            ctl = render_controls(gesture, settings, DEFAULT_FRAME_RATE,
                                  DEFAULT_LD_RANGE)
            warnings += ctl["warnings"]
            _fill_control_stats(stats, ctl)
            if a.controls_out:
                write_controls_table(ctl, a.controls_out)
            if a.preview_wav:
                render_sketch(ctl, a.preview_wav)
            stats["timing_controls_s"] = round(time.perf_counter() - t, 3)
            stats["status"] = "SUCCESS"
            return _finish(stats, warnings, t_total, a.stats, 0)

        # ---------------- synth ----------------
        if not a.output:
            raise RuntimeError("--output is required in synth mode")
        rev = import_revoicing_engine()
        t = time.perf_counter()
        missing = rev.check_dependencies()
        stats["timing_dependencies_s"] = round(time.perf_counter() - t, 3)
        if missing:
            log("ERROR: Missing Python packages (install into the SAME venv "
                "Praat uses):\n  - " + "\n  - ".join(missing))
            warnings.append("missing_dependencies: " + " ; ".join(missing))
            return _finish(stats, warnings, t_total, a.stats, 2)

        cache_dir = rev.resolve_cache_dir(a.cache_dir)
        t = time.perf_counter()
        model_dir, source = rev.ensure_model(a.model, cache_dir)
        stats["timing_model_prepare_s"] = round(time.perf_counter() - t, 3)
        stats["model_source"] = source
        stats["model_cache_path"] = model_dir
        log("Model ready (%s): %s" % (source, model_dir))

        geo = model_geometry(model_dir, rev)
        warnings += geo["warnings"]
        try:
            import ddsp.spectral_ops as so
            ld_range = float(getattr(so, "LD_RANGE", DEFAULT_LD_RANGE))
        except Exception:
            ld_range = DEFAULT_LD_RANGE
        sr, hop, fr = geo["sample_rate"], geo["hop"], geo["frame_rate"]
        stats.update(frame_rate=round(fr, 4), hop_size=hop, synthesis_rate=sr)

        t = time.perf_counter()
        ctl = render_controls(gesture, settings, fr, ld_range)
        warnings += ctl["warnings"]
        _fill_control_stats(stats, ctl)
        if a.controls_out:
            write_controls_table(ctl, a.controls_out)
        stats["timing_controls_s"] = round(time.perf_counter() - t, 3)

        mean_hz = model_mean_pitch_hz(model_dir)
        if mean_hz > 0:
            stats["model_mean_pitch_hz"] = round(mean_hz, 1)
            if ctl["f0_median"] > 0 and abs(12 * math.log(ctl["f0_median"] / mean_hz, 2)) > 12:
                warnings.append("drawn_register_over_an_octave_from_model_mean")

        n = ctl["n_frames"]
        feats = {
            "f0_hz": ctl["f0_hz"],
            "loudness_db": ctl["loudness_db"],
            "f0_confidence": np.ones(n, dtype="float32"),
            "audio": np.zeros((1, n * hop), dtype="float32"),
        }
        stats["time_steps"] = n
        t = time.perf_counter()
        log("Running pretrained DDSP model '%s' on %d control frames..."
            % (a.model, n))
        audio = rev.run_model(model_dir, feats).astype("float64")
        stats["timing_inference_s"] = round(time.perf_counter() - t, 3)

        n_out = int(round(gesture.duration * sr))
        if audio.size < n_out:
            audio = np.pad(audio, (0, n_out - audio.size))
        audio = audio[:n_out]

        audio *= frames_to_samples(gate_curve(ctl["voiced"], fr, a.release_ms),
                                   fr, sr, n_out)

        gain_db = 0.0
        mode = a.output_level
        if mode == "match":
            try:
                g_db = match_drawn_loudness(audio.astype("float32"), ctl, sr)
            except Exception as e:
                log("WARNING: loudness match failed (%s); using peak." % e); log(traceback.format_exc())
                g_db = None
            if g_db is None:
                warnings.append("match_unmeasurable:peak_used")
                mode = "peak"
            else:
                gain_db = g_db
                audio *= 10.0 ** (gain_db / 20.0)

        out_rate = sr
        if a.output_rate and int(a.output_rate) != sr:
            audio = rev._resample_to_rate(audio, sr, int(a.output_rate)).astype("float64")
            out_rate = int(a.output_rate)

        peak = float(np.max(np.abs(audio))) if audio.size else 0.0
        limited = 0.0
        if mode == "peak" and peak > 1e-9:
            gain_db += 20.0 * math.log10(0.95 / peak)
            audio *= 0.95 / peak
        elif peak > 0.99:
            limited = 20.0 * math.log10(peak / 0.99)
            audio *= 0.99 / peak
            gain_db -= limited
            if mode == "match" and limited > 1.0:
                warnings.append("match_peak_limited_by_%.1fdB" % limited)
        _apply_end_fades(audio, out_rate)

        import soundfile as sf
        sf.write(a.output, audio.astype("float32"), out_rate)
        stats.update(output_level_mode=mode, level_gain_db=round(gain_db, 2),
                     peak_limited_db=round(limited, 2),
                     output_sample_rate=out_rate,
                     output_duration_s=round(audio.size / float(out_rate), 4),
                     output_rms=round(float(np.sqrt(np.mean(audio ** 2))), 5),
                     output_peak=round(float(np.max(np.abs(audio))), 5))
        stats["status"] = "SUCCESS"
        log("Done -> %s (%.2f s @ %d Hz; synthesized at %d Hz, %d frames @ %.1f fps)"
            % (a.output, audio.size / float(out_rate), out_rate, sr, n, fr))
        return _finish(stats, warnings, t_total, a.stats, 0)

    except Exception as e:
        log("ERROR:\n" + traceback.format_exc())
        warnings.append(str(e).replace("\n", " | "))
        return _finish(stats, warnings, t_total, a.stats, 1)


def _fill_control_stats(stats, ctl):
    stats.update(
        frame_rate=stats.get("frame_rate") or ctl["frame_rate"],
        time_steps=ctl["n_frames"], loudness_floor_db=ctl["floor_db"],
        n_notes=ctl["n_notes"],
        voiced_fraction=round(ctl["voiced_fraction"], 4),
        f0_min_hz=round(ctl["f0_min"], 2), f0_max_hz=round(ctl["f0_max"], 2),
        f0_median_hz=round(ctl["f0_median"], 2),
        loudness_max_db=round(ctl["loudness_max"], 2))


def _finish(stats, warnings, t_total, stats_path, code):
    stats["warnings"] = ";".join(w for w in warnings if w)
    stats["timing_total_s"] = round(time.perf_counter() - t_total, 3)
    write_stats(stats_path, stats)
    return code


if __name__ == "__main__":
    sys.exit(main())
