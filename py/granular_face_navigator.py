"""
granular_face_navigator.py — Granular Face Navigator

Version 0.2 (2026)
Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University

A face-controlled granular instrument/render worker for Praat AudioTools.

Pipeline
--------
1. Open webcam + MediaPipe Face Landmarker.
2. Neutral-face calibration (2 s).
3. Capture a facial performance while optionally playing a live granular preview.
4. Derive musical face sources (head pose/position, jaw, smile, pucker, brow,
   proximity, expression energy, deliberate eye-hold trigger).
5. Evaluate four user mappings into granular destination controls.
6. Resample the captured controls to a uniform control-rate timeline.
7. Re-render the performance offline with the same granular engine and mapping law.
8. Write stereo WAV, control CSV, grain-level trace, stats, and completion marker.

v0.2: irregular onset scheduling, log-density mapping, corrected overlap gain law,
frame-rate-invariant expression energy, deliberate eye-hold Freeze, yaw-compensated
proximity, real MediaPipe timestamps, reflected source boundaries, grain trace output,
and callback safety.

Required Python packages:
    numpy, opencv-python, soundfile, mediapipe
Optional for live audio:
    sounddevice

The Face Landmarker model is a local .task file.  The companion Praat script can
request a one-time download into plugin_AudioTools/models/face_landmarker.task.
"""

from __future__ import annotations

import argparse
import csv
import math
import os
import sys
import time
import urllib.request
from dataclasses import dataclass

MODEL_URL = (
    "https://storage.googleapis.com/mediapipe-models/face_landmarker/"
    "face_landmarker/float16/1/face_landmarker.task"
)
CAL_SEC = 2.0
CAM_INDEX = 0

# -----------------------------------------------------------------------------
# Mapping codes — shared with GranularFaceNavigator.praat
# -----------------------------------------------------------------------------
SRC_HEAD_YAW = 1
SRC_HEAD_PITCH = 2
SRC_HEAD_ROLL = 3
SRC_HEAD_X = 4
SRC_HEAD_Y = 5
SRC_JAW = 6
SRC_SMILE = 7
SRC_PUCKER = 8
SRC_BROW = 9
SRC_PROXIMITY = 10
SRC_EXPRESSION = 11
SRC_NONE = 12

DST_POSITION = 1
DST_GRAIN_SIZE = 2
DST_DENSITY = 3
DST_PITCH = 4
DST_PITCH_SPREAD = 5
DST_SPRAY = 6
DST_STEREO_SPREAD = 7
DST_AMPLITUDE = 8
DST_TEMPORAL_JITTER = 9
DST_NONE = 10

BIPOLAR_SOURCES = {
    SRC_HEAD_YAW, SRC_HEAD_PITCH, SRC_HEAD_ROLL,
    SRC_HEAD_X, SRC_HEAD_Y,
}

DEFAULT_MAPPING_SPEC = "1:1:1.0:0,6:3:0.8:0,2:2:0.6:0,7:7:0.8:0"

CONTROL_COLUMNS = [
    "time",
    "head_yaw", "head_pitch", "head_roll", "head_x", "head_y",
    "jaw_open", "smile", "pucker", "brow_raise", "proximity",
    "expression_energy", "blink_event", "freeze",
    "position", "grain_ms", "density", "pitch_st", "pitch_spread_st",
    "spray_ms", "stereo_spread", "onset_jitter", "amplitude",
]

TRACE_COLUMNS = [
    "grain", "onset_s", "read_pos", "source_pos", "grain_ms", "density",
    "pitch_st", "spray_offset_ms", "pan", "onset_jitter", "freeze",
]


def _clip(x, lo=0.0, hi=1.0):
    return max(lo, min(hi, float(x)))


def _rms(x):
    import numpy as np
    x = np.asarray(x, dtype=np.float64)
    if x.size == 0:
        return 0.0
    return float(np.sqrt(np.mean(x * x)))


def download_model(path):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    tmp = path + ".part"
    print("Downloading MediaPipe Face Landmarker model...")
    urllib.request.urlretrieve(MODEL_URL, tmp)
    os.replace(tmp, path)
    print("OK: model saved to %s" % path)


def check_dependencies(vision=True):
    missing = []
    packages = [("numpy", "numpy"), ("soundfile", "soundfile")]
    if vision:
        packages.extend([("cv2", "opencv-python"), ("mediapipe", "mediapipe")])
    for module_name, package_name in packages:
        try:
            __import__(module_name)
        except ImportError:
            missing.append(package_name)
    if missing:
        raise RuntimeError(
            "Missing Python packages: %s. Install with: python -m pip install %s"
            % (", ".join(missing), " ".join(missing))
        )


def parse_mapping_spec(spec):
    mappings = []
    text = (spec or "").strip() or DEFAULT_MAPPING_SPEC
    for slot in text.split(","):
        parts = slot.strip().split(":")
        if len(parts) != 4:
            continue
        try:
            src = int(parts[0])
            dst = int(parts[1])
            amount = _clip(float(parts[2]), 0.0, 1.5)
            invert = int(float(parts[3])) != 0
        except (ValueError, TypeError):
            continue
        if not (SRC_HEAD_YAW <= src <= SRC_NONE):
            src = SRC_NONE
        if not (DST_POSITION <= dst <= DST_NONE):
            dst = DST_NONE
        mappings.append((src, dst, amount, invert))
    while len(mappings) < 4:
        mappings.append((SRC_NONE, DST_NONE, 0.0, False))
    return mappings[:4]


@dataclass
class GrainConfig:
    min_grain_ms: float = 20.0
    max_grain_ms: float = 300.0
    min_density: float = 4.0
    max_density: float = 45.0
    pitch_span_st: float = 12.0
    pitch_spread_max_st: float = 10.0
    max_spray_ms: float = 450.0
    scrub_rate: float = 1.0
    base_onset_jitter: float = 0.22

    def sanitize(self):
        self.min_grain_ms = _clip(self.min_grain_ms, 5.0, 1000.0)
        self.max_grain_ms = _clip(self.max_grain_ms, self.min_grain_ms, 2000.0)
        self.min_density = _clip(self.min_density, 0.5, 200.0)
        self.max_density = _clip(self.max_density, self.min_density, 300.0)
        self.pitch_span_st = _clip(self.pitch_span_st, 0.0, 36.0)
        self.pitch_spread_max_st = _clip(self.pitch_spread_max_st, 0.0, 24.0)
        self.max_spray_ms = _clip(self.max_spray_ms, 0.0, 3000.0)
        self.scrub_rate = _clip(self.scrub_rate, 0.05, 4.0)
        self.base_onset_jitter = _clip(self.base_onset_jitter, 0.0, 0.95)
        return self


# -----------------------------------------------------------------------------
# Face feature extraction and calibration
# -----------------------------------------------------------------------------

def rotation_matrix_to_euler_deg(matrix):
    """Return (yaw, pitch, roll) degrees from a 3x3/4x4 rotation matrix."""
    import numpy as np
    m = np.asarray(matrix, dtype=np.float64)
    if m.shape[0] < 3 or m.shape[1] < 3:
        return 0.0, 0.0, 0.0
    r = m[:3, :3]
    sy = math.sqrt(r[0, 0] * r[0, 0] + r[1, 0] * r[1, 0])
    singular = sy < 1e-7
    if not singular:
        pitch = math.atan2(r[2, 1], r[2, 2])
        yaw = math.atan2(-r[2, 0], sy)
        roll = math.atan2(r[1, 0], r[0, 0])
    else:
        pitch = math.atan2(-r[1, 2], r[1, 1])
        yaw = math.atan2(-r[2, 0], sy)
        roll = 0.0
    return tuple(math.degrees(v) for v in (yaw, pitch, roll))


def result_to_raw(result):
    """Convert one FaceLandmarkerResult to a compact raw feature dictionary."""
    import numpy as np
    if not result.face_landmarks:
        return None
    landmarks = result.face_landmarks[0]
    if not landmarks:
        return None
    xs = np.array([float(p.x) for p in landmarks], dtype=np.float64)
    ys = np.array([float(p.y) for p in landmarks], dtype=np.float64)
    center_x = float((xs.min() + xs.max()) * 0.5)
    center_y = float((ys.min() + ys.max()) * 0.5)
    face_width = max(1e-5, float(xs.max() - xs.min()))

    blend = {}
    if result.face_blendshapes:
        for cat in result.face_blendshapes[0]:
            name = getattr(cat, "category_name", None) or ""
            blend[name] = float(getattr(cat, "score", 0.0) or 0.0)

    def b(name, default=0.0):
        return float(blend.get(name, default))

    jaw = b("jawOpen")
    smile = 0.5 * (b("mouthSmileLeft") + b("mouthSmileRight"))
    pucker = b("mouthPucker")
    brow = (b("browInnerUp") + b("browOuterUpLeft") + b("browOuterUpRight")) / 3.0
    blink = 0.5 * (b("eyeBlinkLeft") + b("eyeBlinkRight"))

    yaw = pitch = roll = 0.0
    if result.facial_transformation_matrixes:
        yaw, pitch, roll = rotation_matrix_to_euler_deg(
            result.facial_transformation_matrixes[0]
        )

    # Outer eye-corner span is a more stable scale cue than the full face box.
    # Compensate its 2-D foreshortening by yaw so head navigation does not
    # masquerade as proximity.
    if len(landmarks) > 263:
        p_l = landmarks[33]
        p_r = landmarks[263]
        eye_span = math.hypot(float(p_l.x) - float(p_r.x), float(p_l.y) - float(p_r.y))
    else:
        eye_span = face_width * 0.45
    yaw_cos = max(0.55, abs(math.cos(math.radians(yaw))))
    face_scale = max(1e-5, eye_span / yaw_cos)

    return {
        "center_x": center_x,
        "center_y": center_y,
        "face_width": face_width,
        "face_scale": face_scale,
        "yaw_deg": yaw,
        "pitch_deg": pitch,
        "roll_deg": roll,
        "jaw": jaw,
        "smile": smile,
        "pucker": pucker,
        "brow": brow,
        "blink": blink,
        "landmarks": landmarks,
    }


class FaceNormalizer:
    """Neutral-pose calibration followed by fixed-range causal normalization."""

    HOLD_SEC = 0.34
    REFRACTORY_SEC = 0.30

    def __init__(self, response="smooth"):
        self.response = response
        self.base = None
        self.filtered = None
        self.prev_expression_vector = None
        self.prev_expression_time = None
        self.prev_filter_time = None
        self.blink_hold_start = None
        self.blink_hold_fired = False
        self.last_blink_time = -999.0
        self.freeze = 0
        self.blink_count = 0

    def calibrate(self, raw_frames):
        import numpy as np
        if len(raw_frames) < 3:
            raise RuntimeError("Not enough valid face frames during calibration")
        keys = [
            "center_x", "center_y", "face_scale", "yaw_deg", "pitch_deg", "roll_deg",
            "jaw", "smile", "pucker", "brow", "blink",
        ]
        self.base = {
            k: float(np.median([float(r[k]) for r in raw_frames])) for k in keys
        }
        self.filtered = None
        self.prev_expression_vector = None
        self.prev_expression_time = None
        self.prev_filter_time = None
        self.blink_hold_start = None
        self.blink_hold_fired = False
        self.last_blink_time = -999.0
        self.freeze = 0

    def _uni(self, raw_value, key, scale):
        base = float(self.base.get(key, 0.0))
        return _clip((float(raw_value) - base) / max(scale, 1e-6))

    def normalize(self, raw, now_sec, blink_freeze=True):
        import numpy as np
        if self.base is None:
            raise RuntimeError("FaceNormalizer used before calibration")

        f = {
            "head_yaw": _clip(0.5 + (raw["yaw_deg"] - self.base["yaw_deg"]) / 70.0),
            "head_pitch": _clip(0.5 + (raw["pitch_deg"] - self.base["pitch_deg"]) / 50.0),
            "head_roll": _clip(0.5 + (raw["roll_deg"] - self.base["roll_deg"]) / 60.0),
            "head_x": _clip(0.5 + (raw["center_x"] - self.base["center_x"]) / 0.36),
            "head_y": _clip(0.5 - (raw["center_y"] - self.base["center_y"]) / 0.30),
        }
        ratio = raw["face_scale"] / max(self.base["face_scale"], 1e-6)
        f["proximity"] = _clip((ratio - 1.0) / 0.45)

        f["jaw_open"] = self._uni(raw["jaw"], "jaw", 0.65)
        f["smile"] = self._uni(raw["smile"], "smile", 0.55)
        f["pucker"] = self._uni(raw["pucker"], "pucker", 0.55)
        f["brow_raise"] = self._uni(raw["brow"], "brow", 0.45)
        blink_level = self._uni(raw["blink"], "blink", 0.60)

        # Rate of facial change, not change-per-frame.  Division by dt makes the
        # musical control approximately invariant to camera frame rate.  The 6/s
        # reference preserves roughly the v0.1 sensitivity around 30 fps.
        expr_vec = np.array([
            f["jaw_open"], f["smile"], f["pucker"], f["brow_raise"],
            (f["head_yaw"] - 0.5) * 2.0,
            (f["head_pitch"] - 0.5) * 2.0,
        ], dtype=np.float64)
        if self.prev_expression_vector is None or self.prev_expression_time is None:
            energy = 0.0
        else:
            dt = max(1e-3, float(now_sec) - float(self.prev_expression_time))
            rate = float(np.mean(np.abs(expr_vec - self.prev_expression_vector))) / dt
            energy = min(1.0, rate / 6.0)
        self.prev_expression_vector = expr_vec
        self.prev_expression_time = float(now_sec)
        f["expression_energy"] = energy

        # Time-constant smoothing (not per-frame smoothing), so camera FPS does
        # not change the response character.  Constants reproduce the old
        # ~30-fps Direct/Smooth feel.
        if self.prev_filter_time is None:
            dt_filter = 1.0 / 30.0
        else:
            dt_filter = max(1e-3, float(now_sec) - float(self.prev_filter_time))
        self.prev_filter_time = float(now_sec)
        tau = 0.039 if self.response == "direct" else 0.110
        alpha = 1.0 - math.exp(-dt_filter / tau)
        if self.filtered is None:
            self.filtered = dict(f)
        else:
            for k, v in f.items():
                self.filtered[k] = alpha * float(v) + (1.0 - alpha) * float(self.filtered[k])
        f = {k: _clip(v) for k, v in self.filtered.items()}

        # Deliberate eye-hold trigger.  Ordinary short blinks do not toggle Freeze.
        blink_event = 0
        if blink_level >= 0.72:
            if self.blink_hold_start is None:
                self.blink_hold_start = float(now_sec)
                self.blink_hold_fired = False
            held = float(now_sec) - self.blink_hold_start
            if (not self.blink_hold_fired and held >= self.HOLD_SEC
                    and (float(now_sec) - self.last_blink_time) >= self.REFRACTORY_SEC):
                blink_event = 1
                self.blink_hold_fired = True
                self.last_blink_time = float(now_sec)
                self.blink_count += 1
                if blink_freeze:
                    self.freeze = 0 if self.freeze else 1
        elif blink_level <= 0.35:
            self.blink_hold_start = None
            self.blink_hold_fired = False

        f["blink_event"] = blink_event
        f["freeze"] = self.freeze if blink_freeze else 0
        return f


# -----------------------------------------------------------------------------
# Mapping engine
# -----------------------------------------------------------------------------

def source_value(features, code):
    keys = {
        SRC_HEAD_YAW: "head_yaw",
        SRC_HEAD_PITCH: "head_pitch",
        SRC_HEAD_ROLL: "head_roll",
        SRC_HEAD_X: "head_x",
        SRC_HEAD_Y: "head_y",
        SRC_JAW: "jaw_open",
        SRC_SMILE: "smile",
        SRC_PUCKER: "pucker",
        SRC_BROW: "brow_raise",
        SRC_PROXIMITY: "proximity",
        SRC_EXPRESSION: "expression_energy",
    }
    if code == SRC_NONE:
        return 0.5
    return _clip(features.get(keys.get(code, ""), 0.5))


def source_modulation(value, code):
    if code in BIPOLAR_SOURCES:
        return (float(value) - 0.5) * 2.0
    return float(value)


def evaluate_mappings(features, mappings, cfg):
    """Map face features to granular controls for one control frame."""
    cfg.sanitize()
    pos_u = 0.5
    grain_u = 0.42
    density_u = 0.36
    pitch_st = 0.0
    pitch_spread_u = 0.0
    spray_u = 0.0
    stereo_u = 0.30
    jitter_u = cfg.base_onset_jitter
    amp = 1.0

    for src, dst, amount, invert in mappings:
        if src == SRC_NONE or dst == DST_NONE or amount <= 0:
            continue
        value = source_value(features, src)
        if invert:
            value = 1.0 - value
        mod = source_modulation(value, src)
        intensity = abs(mod) if src in BIPOLAR_SOURCES else value

        if dst == DST_POSITION:
            pos_u += amount * (value - 0.5)
        elif dst == DST_GRAIN_SIZE:
            grain_u += amount * ((value - 0.5) if src in BIPOLAR_SOURCES else (value - 0.42))
        elif dst == DST_DENSITY:
            density_u += amount * ((value - 0.5) if src in BIPOLAR_SOURCES else (value - 0.36))
        elif dst == DST_PITCH:
            pitch_st += mod * amount * cfg.pitch_span_st
        elif dst == DST_PITCH_SPREAD:
            pitch_spread_u += amount * intensity
        elif dst == DST_SPRAY:
            spray_u += amount * intensity
        elif dst == DST_STEREO_SPREAD:
            stereo_u += amount * (intensity if src in BIPOLAR_SOURCES else (value - 0.30))
        elif dst == DST_AMPLITUDE:
            if src in BIPOLAR_SOURCES:
                amp *= max(0.0, 1.0 - amount * abs(mod))
            else:
                amp *= max(0.0, 1.0 - amount * (1.0 - value))
        elif dst == DST_TEMPORAL_JITTER:
            jitter_u += amount * intensity

    pos_u = _clip(pos_u)
    grain_u = _clip(grain_u)
    density_u = _clip(density_u)
    pitch_st = _clip(pitch_st, -36.0, 36.0)
    pitch_spread_u = _clip(pitch_spread_u)
    spray_u = _clip(spray_u)
    stereo_u = _clip(stereo_u)
    jitter_u = _clip(jitter_u, 0.0, 0.95)
    amp = _clip(amp, 0.0, 1.0)

    if cfg.max_grain_ms <= cfg.min_grain_ms:
        grain_ms = cfg.min_grain_ms
    else:
        grain_ms = cfg.min_grain_ms * ((cfg.max_grain_ms / cfg.min_grain_ms) ** grain_u)
    if cfg.max_density <= cfg.min_density:
        density = cfg.min_density
    else:
        # Density is perceptual/rate-like: log interpolation allocates useful
        # control resolution to the musically important sparse region.
        density = cfg.min_density * ((cfg.max_density / cfg.min_density) ** density_u)

    return {
        "position": pos_u,
        "grain_ms": float(grain_ms),
        "density": float(density),
        "pitch_st": float(pitch_st),
        "pitch_spread_st": float(pitch_spread_u * cfg.pitch_spread_max_st),
        "spray_ms": float(spray_u * cfg.max_spray_ms),
        "stereo_spread": float(stereo_u),
        "onset_jitter": float(jitter_u),
        "amplitude": float(amp),
    }


# -----------------------------------------------------------------------------
# Audio / granular engine
# -----------------------------------------------------------------------------

def read_representative_audio(path):
    import numpy as np
    import soundfile as sf
    audio, sr = sf.read(path, always_2d=True, dtype="float32")
    if len(audio) < 2:
        raise RuntimeError("Input sound is empty or too short")
    rms = np.sqrt(np.mean(audio.astype(np.float64) ** 2, axis=0))
    strongest = int(np.argmax(rms))
    if audio.shape[1] == 1:
        chosen = 0
    elif rms[strongest] > 0 and rms[0] < 0.1 * rms[strongest]:
        chosen = strongest
    else:
        chosen = 0
    return np.asarray(audio[:, chosen], dtype=np.float32), int(sr), chosen + 1, audio.shape[1]


def sample_mono_linear(source, positions):
    """Linear interpolation with reflected boundaries (no edge-energy dip)."""
    import numpy as np
    n = len(source)
    pos = np.asarray(positions, dtype=np.float64)
    if n <= 1:
        return np.full(pos.shape, float(source[0]) if n else 0.0, dtype=np.float32)
    period = 2.0 * (n - 1)
    folded = np.mod(pos, period)
    folded = np.where(folded > (n - 1), period - folded, folded)
    i0 = np.floor(folded).astype(np.int64)
    i1 = np.minimum(i0 + 1, n - 1)
    frac = folded - i0
    out = source[i0] * (1.0 - frac) + source[i1] * frac
    return out.astype(np.float32)


def make_grain(source, sr, source_pos_norm, grain_ms, pitch_st,
               pitch_spread_st, spray_ms, stereo_spread, amplitude, rng,
               source_duration_sec):
    import numpy as np
    grain_n = max(16, int(round(float(grain_ms) * 0.001 * sr)))
    pitch = float(pitch_st)
    if pitch_spread_st > 0:
        pitch += float(rng.uniform(-pitch_spread_st, pitch_spread_st))
    ratio = 2.0 ** (pitch / 12.0)

    spray_norm = 0.0
    if spray_ms > 0 and source_duration_sec > 1e-9:
        spray_norm = (float(spray_ms) * 0.001) / source_duration_sec
    spray_delta = float(rng.uniform(-spray_norm, spray_norm)) if spray_norm > 0 else 0.0
    center_norm = _clip(source_pos_norm + spray_delta)
    center = center_norm * (len(source) - 1)
    offsets = (np.arange(grain_n, dtype=np.float64) - (grain_n - 1) * 0.5) * ratio
    mono = sample_mono_linear(source, center + offsets)
    window = np.hanning(grain_n).astype(np.float32)
    mono *= window

    pan = float(rng.uniform(-stereo_spread, stereo_spread)) if stereo_spread > 0 else 0.0
    theta = (pan + 1.0) * math.pi * 0.25
    l_gain = math.cos(theta)
    r_gain = math.sin(theta)
    stereo = np.empty((grain_n, 2), dtype=np.float32)
    stereo[:, 0] = mono * l_gain * amplitude
    stereo[:, 1] = mono * r_gain * amplitude
    meta = {
        "source_pos": float(center_norm),
        "pitch_st": float(pitch),
        "pan": float(pan),
        "spray_offset_ms": float(spray_delta * source_duration_sec * 1000.0),
    }
    return stereo, meta


def _interval_samples(sr, density, jitter, rng):
    base = float(sr) / max(0.5, float(density))
    j = _clip(jitter, 0.0, 0.95)
    factor = 1.0 + (float(rng.uniform(-j, j)) if j > 0 else 0.0)
    return max(1, int(round(base * factor)))


def _grain_gain(amplitude, density, grain_ms):
    # Energy compensation from the TRUE temporal coverage density*duration.
    # A small floor prevents extreme gain for very sparse clouds while keeping
    # most of the playable range approximately loudness-neutral.
    coverage = max(0.25, float(density) * float(grain_ms) * 0.001)
    return _clip(amplitude) / math.sqrt(coverage)


class OfflineControlTimeline:
    def __init__(self, rows, target_duration):
        import numpy as np
        if len(rows) < 2:
            raise RuntimeError("Control timeline has too few rows")
        raw_t = np.asarray([float(r["time"]) for r in rows], dtype=np.float64)
        raw_dur = max(float(raw_t[-1]), 1e-6)
        self.t = raw_t * (float(target_duration) / raw_dur)
        self.rows = rows
        self.numeric = {}
        for key in CONTROL_COLUMNS:
            if key == "time":
                continue
            self.numeric[key] = np.asarray([float(r[key]) for r in rows], dtype=np.float64)

    def sample(self, t_sec):
        import numpy as np
        out = {}
        for key, arr in self.numeric.items():
            if key in ("blink_event", "freeze"):
                idx = int(np.searchsorted(self.t, t_sec, side="right") - 1)
                idx = max(0, min(len(arr) - 1, idx))
                out[key] = float(arr[idx])
            else:
                out[key] = float(np.interp(t_sec, self.t, arr))
        return out


def render_offline(source, sr, rows, position_mode, cfg, seed, target_duration):
    import numpy as np
    timeline = OfflineControlTimeline(rows, target_duration)
    rng = np.random.default_rng(int(seed))
    n_out = max(1, int(round(target_duration * sr)))
    out = np.zeros((n_out, 2), dtype=np.float32)
    source_dur = len(source) / float(sr)

    sample_cursor = 0
    read_pos = 0.5
    freeze_pos = 0.5
    prev_freeze = 0
    last_grain_sec = 0.0
    grain_count = 0
    sum_grain = sum_density = sum_pitch = sum_spray = sum_spread = sum_jitter = 0.0
    trace = []

    while sample_cursor < n_out:
        t_sec = sample_cursor / float(sr)
        c = timeline.sample(t_sec)
        freeze = int(c.get("freeze", 0) >= 0.5)

        if position_mode == "navigate":
            if freeze and not prev_freeze:
                freeze_pos = float(c["position"])
            read_pos = freeze_pos if freeze else float(c["position"])
        else:
            if freeze and not prev_freeze:
                freeze_pos = read_pos
            if freeze:
                read_pos = freeze_pos
            else:
                dt = max(0.0, t_sec - last_grain_sec)
                drive = (float(c["position"]) - 0.5) * 2.0
                if source_dur > 1e-9:
                    read_pos = (read_pos + drive * cfg.scrub_rate * dt / source_dur) % 1.0
        prev_freeze = freeze

        grain_ms = max(5.0, float(c["grain_ms"]))
        density = max(0.5, float(c["density"]))
        pitch_st = float(c["pitch_st"])
        pitch_spread = max(0.0, float(c["pitch_spread_st"]))
        spray_ms = max(0.0, float(c["spray_ms"]))
        stereo_spread = _clip(c["stereo_spread"])
        onset_jitter = _clip(c.get("onset_jitter", cfg.base_onset_jitter), 0.0, 0.95)
        amplitude = _clip(c["amplitude"])

        grain_amp = _grain_gain(amplitude, density, grain_ms)
        grain, gmeta = make_grain(
            source, sr, read_pos, grain_ms, pitch_st, pitch_spread,
            spray_ms, stereo_spread, grain_amp, rng, source_dur,
        )
        end = min(n_out, sample_cursor + len(grain))
        out[sample_cursor:end] += grain[:end - sample_cursor]

        grain_count += 1
        sum_grain += grain_ms
        sum_density += density
        sum_pitch += pitch_st
        sum_spray += spray_ms
        sum_spread += stereo_spread
        sum_jitter += onset_jitter
        trace.append({
            "grain": grain_count,
            "onset_s": t_sec,
            "read_pos": float(read_pos),
            "source_pos": gmeta["source_pos"],
            "grain_ms": grain_ms,
            "density": density,
            "pitch_st": gmeta["pitch_st"],
            "spray_offset_ms": gmeta["spray_offset_ms"],
            "pan": gmeta["pan"],
            "onset_jitter": onset_jitter,
            "freeze": freeze,
        })

        last_grain_sec = t_sec
        sample_cursor += _interval_samples(sr, density, onset_jitter, rng)

    fade_n = min(n_out, max(1, int(round(0.005 * sr))))
    if fade_n > 1:
        out[-fade_n:] *= np.linspace(1.0, 0.0, fade_n, dtype=np.float32)[:, None]

    pre_peak = float(np.max(np.abs(out))) if out.size else 0.0
    if pre_peak > 0.98:
        out *= (0.97 / pre_peak)
    post_peak = float(np.max(np.abs(out))) if out.size else 0.0

    denom = max(grain_count, 1)
    stats = {
        "grain_count": grain_count,
        "mean_grain_ms": sum_grain / denom,
        "mean_density": sum_density / denom,
        "mean_pitch_st": sum_pitch / denom,
        "mean_spray_ms": sum_spray / denom,
        "mean_stereo_spread": sum_spread / denom,
        "mean_onset_jitter": sum_jitter / denom,
        "pre_peak": pre_peak,
        "output_peak": post_peak,
    }
    return out, stats, trace


class LiveGranularEngine:
    """Block-based live renderer using the same grain generator and controls."""
    def __init__(self, source, sr, position_mode, cfg, seed=42, volume=0.8, blocksize=512):
        import numpy as np
        try:
            import sounddevice as sd
        except ImportError as exc:
            raise RuntimeError("sounddevice not installed (python -m pip install sounddevice)") from exc
        self.sd = sd
        self.source = source
        self.sr = int(sr)
        self.position_mode = position_mode
        self.cfg = cfg
        self.rng = np.random.default_rng(int(seed))
        self.volume = _clip(volume, 0.0, 1.5)
        self.blocksize = int(blocksize)
        self.controls = {
            "position": 0.5, "grain_ms": 90.0, "density": 18.0,
            "pitch_st": 0.0, "pitch_spread_st": 0.0,
            "spray_ms": 0.0, "stereo_spread": 0.3,
            "onset_jitter": cfg.base_onset_jitter, "amplitude": 1.0,
            "freeze": 0.0,
        }
        self.active = []
        self.global_sample = 0
        self.next_grain_sample = 0
        self.last_grain_sample = 0
        self.read_pos = 0.5
        self.freeze_pos = 0.5
        self.prev_freeze = 0
        self.underflows = 0
        self.stream = None
        self.status = "off"
        self.last_error = ""

    def update(self, controls, freeze):
        for k in ["position", "grain_ms", "density", "pitch_st", "pitch_spread_st",
                  "spray_ms", "stereo_spread", "onset_jitter", "amplitude"]:
            if k in controls:
                self.controls[k] = float(controls[k])
        self.controls["freeze"] = float(freeze)

    def _spawn(self):
        c = self.controls
        t_sec = self.global_sample / float(self.sr)
        last_sec = self.last_grain_sample / float(self.sr)
        source_dur = len(self.source) / float(self.sr)
        freeze = int(c.get("freeze", 0) >= 0.5)
        if self.position_mode == "navigate":
            if freeze and not self.prev_freeze:
                self.freeze_pos = _clip(c["position"])
            self.read_pos = self.freeze_pos if freeze else _clip(c["position"])
        else:
            if freeze and not self.prev_freeze:
                self.freeze_pos = self.read_pos
            if freeze:
                self.read_pos = self.freeze_pos
            else:
                drive = (_clip(c["position"]) - 0.5) * 2.0
                dt = max(0.0, t_sec - last_sec)
                if source_dur > 1e-9:
                    self.read_pos = (self.read_pos + drive * self.cfg.scrub_rate * dt / source_dur) % 1.0
        self.prev_freeze = freeze

        density = max(0.5, float(c["density"]))
        grain_ms = max(5.0, float(c["grain_ms"]))
        jitter = _clip(c.get("onset_jitter", self.cfg.base_onset_jitter), 0.0, 0.95)
        amp = _grain_gain(c["amplitude"], density, grain_ms)
        grain, _ = make_grain(
            self.source, self.sr, self.read_pos, grain_ms, float(c["pitch_st"]),
            max(0.0, float(c["pitch_spread_st"])), max(0.0, float(c["spray_ms"])),
            _clip(c["stereo_spread"]), amp, self.rng, source_dur,
        )
        onset_delay = max(0, int(self.next_grain_sample - self._current_block_start))
        self.active.append([grain, 0, onset_delay])
        self.last_grain_sample = self.global_sample
        self.next_grain_sample += _interval_samples(self.sr, density, jitter, self.rng)

    def _callback(self, outdata, frames, time_info, status):
        import numpy as np
        try:
            if status:
                self.underflows += 1
            block = np.zeros((frames, 2), dtype=np.float32)
            block_start = self.global_sample
            block_end = block_start + frames
            self._current_block_start = block_start

            while self.next_grain_sample < block_end:
                if self.next_grain_sample < block_start:
                    self.next_grain_sample = block_start
                self.global_sample = self.next_grain_sample
                self._spawn()

            self.global_sample = block_start
            survivors = []
            for item in self.active:
                grain, pos, delay = item
                start = max(0, int(delay))
                available = max(0, frames - start)
                take = min(available, len(grain) - pos)
                if take > 0:
                    block[start:start + take] += grain[pos:pos + take]
                    pos += take
                if pos < len(grain):
                    survivors.append([grain, pos, 0])
            self.active = survivors
            outdata[:] = np.clip(block * self.volume, -1.0, 1.0)
            self.global_sample = block_end
        except Exception as exc:
            self.status = "error"
            self.last_error = str(exc)
            outdata[:] = 0.0

    def start(self):
        self.stream = self.sd.OutputStream(
            samplerate=self.sr, channels=2, dtype="float32",
            blocksize=self.blocksize, callback=self._callback,
        )
        self.stream.start()
        self.status = "on"

    def stop(self):
        if self.stream is not None:
            try:
                self.stream.stop()
                self.stream.close()
            except Exception:
                pass
        self.stream = None
        if self.status != "error":
            self.status = "off"


# -----------------------------------------------------------------------------
# Camera / MediaPipe capture
# -----------------------------------------------------------------------------

def create_landmarker(model_path):
    import mediapipe as mp
    BaseOptions = mp.tasks.BaseOptions
    FaceLandmarker = mp.tasks.vision.FaceLandmarker
    FaceLandmarkerOptions = mp.tasks.vision.FaceLandmarkerOptions
    RunningMode = mp.tasks.vision.RunningMode
    options = FaceLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=model_path),
        running_mode=RunningMode.VIDEO,
        num_faces=1,
        min_face_detection_confidence=0.5,
        min_face_presence_confidence=0.5,
        min_tracking_confidence=0.5,
        output_face_blendshapes=True,
        output_facial_transformation_matrixes=True,
    )
    return FaceLandmarker.create_from_options(options)


def detect_frame(landmarker, frame_bgr, timestamp_ms):
    import cv2
    import mediapipe as mp
    rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
    mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
    result = landmarker.detect_for_video(mp_image, int(timestamp_ms))
    return result, result_to_raw(result)


def draw_preview(frame, raw, features, controls, remaining, phase, freeze):
    import cv2
    h, w = frame.shape[:2]
    # Mirror the performer view deliberately; mapping coordinates remain camera/world based.
    vis = cv2.flip(frame, 1)
    if raw is not None and raw.get("landmarks"):
        # Sparse landmark cloud: informative without the visual weight of full tessellation.
        for idx, p in enumerate(raw["landmarks"]):
            if idx % 5 == 0:
                x = int((1.0 - _clip(p.x)) * (w - 1))
                y = int(_clip(p.y) * (h - 1))
                cv2.circle(vis, (x, y), 1, (180, 220, 255), -1)

    cv2.rectangle(vis, (8, 6), (min(w - 8, 620), 155), (0, 0, 0), -1)
    cv2.putText(vis, "%s  %.1fs" % (phase, max(0.0, remaining)), (16, 32),
                cv2.FONT_HERSHEY_SIMPLEX, 0.72, (80, 255, 120), 2)
    if features is not None:
        cv2.putText(vis, "YAW %.2f  JAW %.2f  SMILE %.2f  EXPR %.2f" % (
            features["head_yaw"], features["jaw_open"], features["smile"],
            features["expression_energy"]), (16, 61),
            cv2.FONT_HERSHEY_SIMPLEX, 0.52, (235, 235, 235), 1)
    if controls is not None:
        cv2.putText(vis, "POS %.2f  GRAIN %.0fms  DENS %.1f/s" % (
            controls["position"], controls["grain_ms"], controls["density"]),
            (16, 88), cv2.FONT_HERSHEY_SIMPLEX, 0.52, (180, 220, 255), 1)
        cv2.putText(vis, "PITCH %+.1fst  SPRAY %.0fms  JIT %.2f" % (
            controls["pitch_st"], controls["spray_ms"], controls.get("onset_jitter", 0.0)),
            (16, 115), cv2.FONT_HERSHEY_SIMPLEX, 0.52, (180, 220, 255), 1)
    cv2.putText(vis, "FREEZE %s" % ("ON" if freeze else "off"), (16, 142),
                cv2.FONT_HERSHEY_SIMPLEX, 0.52, (120, 180, 255) if freeze else (180, 180, 180), 1)
    return vis


def resample_control_rows(rows, control_fps, capture_duration):
    import numpy as np
    if len(rows) < 2:
        return rows
    t_raw = np.asarray([r["time"] for r in rows], dtype=np.float64)
    duration = max(float(capture_duration), float(t_raw[-1]), 1e-6)
    n = max(4, int(round(duration * control_fps)) + 1)
    t_new = np.linspace(0.0, duration, n)
    out = []
    for t in t_new:
        r = {"time": float(t)}
        for key in CONTROL_COLUMNS:
            if key == "time":
                continue
            vals = np.asarray([float(x[key]) for x in rows], dtype=np.float64)
            if key in ("blink_event", "freeze"):
                idx = int(np.searchsorted(t_raw, t, side="right") - 1)
                idx = max(0, min(len(vals) - 1, idx))
                r[key] = float(vals[idx])
            else:
                r[key] = float(np.interp(t, t_raw, vals))
        out.append(r)
    return out


def fallback_rows(capture_sec, cfg):
    f = {
        "head_yaw": 0.5, "head_pitch": 0.5, "head_roll": 0.5,
        "head_x": 0.5, "head_y": 0.5, "jaw_open": 0.0, "smile": 0.0,
        "pucker": 0.0, "brow_raise": 0.0, "proximity": 0.5,
        "expression_energy": 0.0, "blink_event": 0.0, "freeze": 0.0,
    }
    c = {
        "position": 0.5, "grain_ms": math.sqrt(cfg.min_grain_ms * cfg.max_grain_ms),
        "density": cfg.min_density * ((cfg.max_density / cfg.min_density) ** 0.36) if cfg.max_density > cfg.min_density else cfg.min_density,
        "pitch_st": 0.0, "pitch_spread_st": 0.0, "spray_ms": 0.0,
        "stereo_spread": 0.3, "onset_jitter": cfg.base_onset_jitter, "amplitude": 1.0,
    }
    rows = []
    for t in [0.0, float(capture_sec)]:
        row = {"time": t}
        row.update(f)
        row.update(c)
        rows.append(row)
    return rows


def capture_face_performance(model_path, capture_sec, mappings, cfg, response,
                             control_fps, show_preview, blink_freeze,
                             live_audio, live_volume, source, sr, position_mode,
                             seed):
    import cv2

    warnings = []
    cap = None
    landmarker = None
    live = None
    raw_rows = []
    valid_perf_frames = 0
    total_perf_frames = 0
    cam_fps = 0.0
    live_status = "off" if not live_audio else "unavailable"

    try:
        cap = cv2.VideoCapture(CAM_INDEX)
        if not cap.isOpened():
            raise RuntimeError("Could not open camera index %d" % CAM_INDEX)
        cam_fps = float(cap.get(cv2.CAP_PROP_FPS))
        if cam_fps <= 0 or cam_fps > 300:
            cam_fps = 30.0

        landmarker = create_landmarker(model_path)
        normalizer = FaceNormalizer(response=response)
        mp_epoch = time.monotonic()
        last_ts_ms = -1

        def timestamp_ms():
            nonlocal last_ts_ms
            ts = int(round((time.monotonic() - mp_epoch) * 1000.0))
            ts = max(last_ts_ms + 1, ts)
            last_ts_ms = ts
            return ts

        cal_raw = []
        t0 = time.monotonic()
        while time.monotonic() - t0 < CAL_SEC:
            ok, frame = cap.read()
            if not ok:
                continue
            elapsed = time.monotonic() - t0
            result, raw = detect_frame(landmarker, frame, timestamp_ms())
            if raw is not None:
                cal_raw.append(raw)
            if show_preview:
                vis = draw_preview(frame, raw, None, None, CAL_SEC - elapsed,
                                   "NEUTRAL CALIBRATION", False)
                cv2.imshow("Granular Face Navigator — Praat AudioTools", vis)
                cv2.waitKey(1)
        normalizer.calibrate(cal_raw)

        if live_audio:
            try:
                live = LiveGranularEngine(
                    source, sr, position_mode, cfg, seed=seed,
                    volume=live_volume, blocksize=512,
                )
                live.start()
                live_status = "on"
            except Exception as exc:
                warnings.append("Live audio unavailable: %s" % str(exc))
                live = None
                live_status = "unavailable"

        t0 = time.monotonic()
        last_features = None
        last_controls = None
        while True:
            elapsed = time.monotonic() - t0
            if elapsed >= capture_sec:
                break
            ok, frame = cap.read()
            if not ok:
                continue
            total_perf_frames += 1
            result, raw = detect_frame(landmarker, frame, timestamp_ms())
            if raw is not None:
                features = normalizer.normalize(raw, elapsed, blink_freeze=blink_freeze)
                controls = evaluate_mappings(features, mappings, cfg)
                valid_perf_frames += 1
                last_features = features
                last_controls = controls
            elif last_features is not None:
                features = dict(last_features)
                features["blink_event"] = 0
                controls = dict(last_controls)
            else:
                continue

            row = {"time": float(elapsed)}
            for key in [
                "head_yaw", "head_pitch", "head_roll", "head_x", "head_y",
                "jaw_open", "smile", "pucker", "brow_raise", "proximity",
                "expression_energy", "blink_event", "freeze",
            ]:
                row[key] = float(features[key])
            row.update({k: float(v) for k, v in controls.items()})
            raw_rows.append(row)

            if live is not None:
                live.update(controls, features["freeze"])
                if live.status == "error":
                    live_status = "error"
                    if live.last_error:
                        warnings.append("Live audio stopped: %s" % live.last_error)

            if show_preview:
                vis = draw_preview(
                    frame, raw, features, controls, capture_sec - elapsed,
                    "GRANULAR PERFORMANCE", bool(features["freeze"]),
                )
                cv2.imshow("Granular Face Navigator — Praat AudioTools", vis)
                cv2.waitKey(1)

        if live is not None:
            if live.status == "on":
                live_status = "on"
            live.stop()

        if valid_perf_frames < 3 or len(raw_rows) < 3:
            raise RuntimeError("Too few valid face-tracking frames")

        rows = resample_control_rows(raw_rows, control_fps, capture_sec)
        face_ratio = valid_perf_frames / float(max(total_perf_frames, 1))
        if face_ratio < 0.60:
            warnings.append("Low face tracking coverage (%.0f%%)" % (100.0 * face_ratio))

        meta = {
            "camera_fps": cam_fps,
            "raw_frames": total_perf_frames,
            "valid_face_frames": valid_perf_frames,
            "face_tracking_ratio": face_ratio,
            "blink_count": normalizer.blink_count,
            "freeze_state": normalizer.freeze,
            "live_status": live_status,
            "live_underflows": live.underflows if live is not None else 0,
            "warnings": warnings,
        }
        return rows, meta

    finally:
        if live is not None:
            try:
                live.stop()
            except Exception:
                pass
        if landmarker is not None:
            try:
                landmarker.close()
            except Exception:
                pass
        if cap is not None:
            try:
                cap.release()
            except Exception:
                pass
        try:
            cv2.destroyAllWindows()
            cv2.waitKey(1)
        except Exception:
            pass


# -----------------------------------------------------------------------------
# Writers / self-test
# -----------------------------------------------------------------------------

def write_controls(path, rows):
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=CONTROL_COLUMNS)
        writer.writeheader()
        for row in rows:
            writer.writerow({k: ("%.6f" % float(row[k])) for k in CONTROL_COLUMNS})


def read_controls(path):
    rows = []
    with open(path, "r", newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        for src in reader:
            row = {}
            for k in CONTROL_COLUMNS:
                if k not in src:
                    if k == "onset_jitter":
                        row[k] = 0.22
                        continue
                    raise RuntimeError("Saved performance missing column: %s" % k)
                row[k] = float(src[k])
            rows.append(row)
    if len(rows) < 2:
        raise RuntimeError("Saved performance has too few rows")
    return rows


def write_trace(path, trace):
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=TRACE_COLUMNS, delimiter="\t")
        writer.writeheader()
        for row in trace:
            writer.writerow({k: ("%.6f" % float(row[k])) for k in TRACE_COLUMNS})


def write_stats(path, meta, render_stats, source_channel, source_channels,
                position_mode, cfg, warnings):
    all_warnings = list(meta.get("warnings", [])) + list(warnings)
    with open(path, "w", encoding="utf-8") as f:
        f.write("camera_fps=%.3f\n" % float(meta.get("camera_fps", 0.0)))
        f.write("raw_frames=%d\n" % int(meta.get("raw_frames", 0)))
        f.write("valid_face_frames=%d\n" % int(meta.get("valid_face_frames", 0)))
        f.write("face_tracking_ratio=%.4f\n" % float(meta.get("face_tracking_ratio", 0.0)))
        f.write("blink_count=%d\n" % int(meta.get("blink_count", 0)))
        f.write("live_status=%s\n" % str(meta.get("live_status", "off")))
        f.write("live_underflows=%d\n" % int(meta.get("live_underflows", 0)))
        f.write("source_channel=%d\n" % int(source_channel))
        f.write("source_channels=%d\n" % int(source_channels))
        f.write("position_mode=%s\n" % position_mode)
        f.write("grain_count=%d\n" % int(render_stats.get("grain_count", 0)))
        f.write("mean_grain_ms=%.3f\n" % float(render_stats.get("mean_grain_ms", 0.0)))
        f.write("mean_density=%.3f\n" % float(render_stats.get("mean_density", 0.0)))
        f.write("mean_pitch_st=%.3f\n" % float(render_stats.get("mean_pitch_st", 0.0)))
        f.write("mean_spray_ms=%.3f\n" % float(render_stats.get("mean_spray_ms", 0.0)))
        f.write("mean_stereo_spread=%.4f\n" % float(render_stats.get("mean_stereo_spread", 0.0)))
        f.write("mean_onset_jitter=%.4f\n" % float(render_stats.get("mean_onset_jitter", 0.0)))
        f.write("pre_peak=%.5f\n" % float(render_stats.get("pre_peak", 0.0)))
        f.write("output_peak=%.5f\n" % float(render_stats.get("output_peak", 0.0)))
        f.write("min_grain_ms=%.3f\n" % cfg.min_grain_ms)
        f.write("max_grain_ms=%.3f\n" % cfg.max_grain_ms)
        f.write("min_density=%.3f\n" % cfg.min_density)
        f.write("max_density=%.3f\n" % cfg.max_density)
        f.write("base_onset_jitter=%.4f\n" % cfg.base_onset_jitter)
        f.write("warnings=%s\n" % ("; ".join(all_warnings) if all_warnings else "none"))


def self_test(out_dir):
    import numpy as np
    import soundfile as sf
    os.makedirs(out_dir, exist_ok=True)
    sr = 24000
    dur = 2.5
    t = np.arange(int(sr * dur), dtype=np.float64) / sr
    source = (0.34 * np.sin(2 * np.pi * 220 * t) + 0.18 * np.sin(2 * np.pi * 731 * t)).astype(np.float32)
    cfg = GrainConfig().sanitize()
    mappings = parse_mapping_spec(DEFAULT_MAPPING_SPEC)
    rows = []
    for tt in np.linspace(0, dur, 76):
        f = {
            "head_yaw": 0.5 + 0.45 * math.sin(2 * math.pi * tt / dur),
            "head_pitch": 0.5 + 0.35 * math.sin(4 * math.pi * tt / dur),
            "head_roll": 0.5, "head_x": 0.5, "head_y": 0.5,
            "jaw_open": 0.5 + 0.5 * math.sin(math.pi * tt / dur) ** 2,
            "smile": tt / dur, "pucker": 0.0, "brow_raise": 0.2,
            "proximity": 0.0, "expression_energy": 0.4,
            "blink_event": 1.0 if abs(tt - dur * 0.5) < 0.02 else 0.0,
            "freeze": 1.0 if dur * 0.5 <= tt < dur * 0.72 else 0.0,
        }
        c = evaluate_mappings(f, mappings, cfg)
        row = {"time": float(tt)}
        row.update(f)
        row.update(c)
        rows.append(row)
    out, stats, trace = render_offline(source, sr, rows, "navigate", cfg, 42, dur)
    out2, stats2, trace2 = render_offline(source, sr, rows, "navigate", cfg, 42, dur)
    assert np.array_equal(out, out2)
    assert trace == trace2
    assert out.shape == (int(round(sr * dur)), 2)
    assert np.isfinite(out).all()
    assert 0.0 < float(np.max(np.abs(out))) <= 0.98
    sf.write(os.path.join(out_dir, "granular_face_selftest.wav"), out, sr, subtype="FLOAT")
    write_controls(os.path.join(out_dir, "granular_face_selftest.csv"), rows)
    write_trace(os.path.join(out_dir, "granular_face_selftest_trace.tsv"), trace)
    onsets = np.asarray([x["onset_s"] for x in trace], dtype=np.float64)
    if len(onsets) > 3:
        intervals = np.diff(onsets)
        assert float(np.std(intervals)) > 1e-5
    print("SELF-TEST OK", stats)


def build_parser():
    p = argparse.ArgumentParser(description="Granular Face Navigator worker")
    p.add_argument("--download-model-only", default="")
    p.add_argument("--self-test", default="")
    p.add_argument("--input", default="")
    p.add_argument("--output", default="")
    p.add_argument("--controls", default="")
    p.add_argument("--trace", default="")
    p.add_argument("--render-controls", default="")
    p.add_argument("--stats", default="")
    p.add_argument("--done", default="")
    p.add_argument("--model", default="")
    p.add_argument("--capture-sec", type=float, default=10.0)
    p.add_argument("--control-fps", type=int, default=30)
    p.add_argument("--show-preview", type=int, default=1)
    p.add_argument("--live-audio", type=int, default=1)
    p.add_argument("--live-volume", type=float, default=0.8)
    p.add_argument("--response", choices=["direct", "smooth"], default="smooth")
    p.add_argument("--position-mode", choices=["navigate", "scrub"], default="navigate")
    p.add_argument("--blink-freeze", type=int, default=1)
    p.add_argument("--mapping-spec", default=DEFAULT_MAPPING_SPEC)
    p.add_argument("--min-grain-ms", type=float, default=20.0)
    p.add_argument("--max-grain-ms", type=float, default=300.0)
    p.add_argument("--min-density", type=float, default=4.0)
    p.add_argument("--max-density", type=float, default=45.0)
    p.add_argument("--pitch-span-st", type=float, default=12.0)
    p.add_argument("--pitch-spread-max-st", type=float, default=10.0)
    p.add_argument("--max-spray-ms", type=float, default=450.0)
    p.add_argument("--scrub-rate", type=float, default=1.0)
    p.add_argument("--base-onset-jitter", type=float, default=0.22)
    p.add_argument("--seed", type=int, default=42)
    return p


def main():
    args = build_parser().parse_args()

    if args.download_model_only:
        download_model(args.download_model_only)
        return
    if args.self_test:
        self_test(args.self_test)
        return

    required = [args.input, args.output, args.controls, args.trace, args.stats, args.done]
    if not all(required):
        raise SystemExit("ERROR: --input --output --controls --trace --stats --done are required")

    check_dependencies(vision=not bool(args.render_controls))
    if not args.render_controls and not os.path.isfile(args.model):
        raise RuntimeError("Face Landmarker model not found: %s" % args.model)

    import numpy as np
    import soundfile as sf

    cfg = GrainConfig(
        min_grain_ms=args.min_grain_ms,
        max_grain_ms=args.max_grain_ms,
        min_density=args.min_density,
        max_density=args.max_density,
        pitch_span_st=args.pitch_span_st,
        pitch_spread_max_st=args.pitch_spread_max_st,
        max_spray_ms=args.max_spray_ms,
        scrub_rate=args.scrub_rate,
        base_onset_jitter=args.base_onset_jitter,
    ).sanitize()
    mappings = parse_mapping_spec(args.mapping_spec)
    source, sr, source_channel, source_channels = read_representative_audio(args.input)
    source_duration = len(source) / float(sr)
    capture_sec = _clip(args.capture_sec, 3.0, 60.0)
    control_fps = int(_clip(args.control_fps, 10, 60))
    warnings = []

    try:
        if args.render_controls:
            saved = read_controls(args.render_controls)
            # Re-evaluate destinations from the SAVED FACE SOURCES, so new mappings
            # and new grain ranges genuinely recompose the same performance.
            rows = []
            for old in saved:
                features = {k: old[k] for k in [
                    "head_yaw", "head_pitch", "head_roll", "head_x", "head_y",
                    "jaw_open", "smile", "pucker", "brow_raise", "proximity",
                    "expression_energy", "blink_event", "freeze",
                ]}
                controls = evaluate_mappings(features, mappings, cfg)
                row = {"time": float(old["time"])}
                row.update(features)
                row.update(controls)
                rows.append(row)
            meta = {
                "camera_fps": 0.0, "raw_frames": len(rows), "valid_face_frames": len(rows),
                "face_tracking_ratio": 1.0, "blink_count": int(sum(r["blink_event"] for r in rows)),
                "live_status": "render-only", "live_underflows": 0,
                "warnings": ["Re-rendered from saved facial performance"],
            }
        else:
            rows, meta = capture_face_performance(
                args.model, capture_sec, mappings, cfg, args.response,
                control_fps, bool(args.show_preview), bool(args.blink_freeze),
                bool(args.live_audio), args.live_volume, source, sr,
                args.position_mode, args.seed,
            )

        output, render_stats, trace = render_offline(
            source, sr, rows, args.position_mode, cfg, args.seed, source_duration,
        )
        sf.write(args.output, output, sr, subtype="FLOAT")
        write_controls(args.controls, rows)
        write_trace(args.trace, trace)
        write_stats(args.stats, meta, render_stats, source_channel, source_channels,
                    args.position_mode, cfg, warnings)
        with open(args.done, "w", encoding="utf-8") as f:
            f.write("ok\n")
        print("OK: Granular Face Navigator rendered %d grains" % render_stats["grain_count"])

    except Exception as exc:
        msg = str(exc)
        warnings.append("Face/capture error: " + msg)
        fallback, fallback_sr = sf.read(args.input, always_2d=True, dtype="float32")
        fallback = np.asarray(fallback, dtype=np.float32)
        sf.write(args.output, fallback, int(fallback_sr), subtype="FLOAT")
        rows = fallback_rows(capture_sec, cfg)
        write_controls(args.controls, rows)
        write_trace(args.trace, [])
        meta = {
            "camera_fps": 0.0, "raw_frames": 0, "valid_face_frames": 0,
            "face_tracking_ratio": 0.0, "blink_count": 0,
            "live_status": "off", "live_underflows": 0, "warnings": warnings,
        }
        render_stats = {
            "grain_count": 0, "mean_grain_ms": 0.0, "mean_density": 0.0,
            "mean_pitch_st": 0.0, "mean_spray_ms": 0.0,
            "mean_stereo_spread": 0.0, "mean_onset_jitter": 0.0,
            "pre_peak": float(np.max(np.abs(fallback))),
            "output_peak": float(np.max(np.abs(fallback))),
        }
        write_stats(args.stats, meta, render_stats, source_channel, source_channels,
                    args.position_mode, cfg, [])
        with open(args.done, "w", encoding="utf-8") as f:
            f.write("fallback\n")
        print("WARNING: %s" % msg, file=sys.stderr)


if __name__ == "__main__":
    main()
