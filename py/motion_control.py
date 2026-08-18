"""
motion_control.py — Motion-Controlled Sound Transformation Worker

Version 1.4 (2026)

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University

Usage (called by Praat — do not invoke manually during a session):
    python motion_control.py control_csv stats_txt done_marker
        [capture_sec] [control_fps] [smooth_frames] [show_preview]
        [live_audio] [live_wav] [pitch_range_st] [amplitude_min]
        [amplitude_max] [brightness_range] [live_response] [live_volume] [mapping_spec] [pitch_span_st] [brightness_span]

Pipeline:
    Stage 1  — Open webcam and detect camera FPS
    Stage 2  — Calibration phase: build a per-pixel background noise model
               (user holds still for CAL_SEC seconds)
    Stage 3  — Capture phase: record capture_sec seconds of free motion
               (optional cv2 preview window with countdown overlay)
    Stage 4  — Feature extraction per video frame:
                 · motion energy  — frame differencing, noise-floor subtracted
                 · vertical pos   — motion-weighted centroid in Y (inverted: top=1)
                 · horizontal pos — motion-weighted centroid in X (left=0, right=1)
    Stage 5  — Resample to uniform control_fps grid
    Stage 6  — Smooth (EMA), normalize (percentile stretch),
               deadband (snap to neutral below threshold),
               hysteresis (lazy follower for musical smoothness)
    Stage 7  — Write control CSV + stats file + done marker

Output files (all paths passed as CLI arguments):
    control_csv   — CSV with gesture sources plus mapped destination controls:
                    energy/Y/X, speed, stillness, radius, acceleration,
                    amplitude gain, pitch shift, brightness, pan. Times in seconds.
    stats_txt     — key=value diagnostics parseable by Praat parseStatLine
    done_marker   — written last; contains "ok" or "fallback"

If the webcam cannot be opened (or capture yields too few frames), a graceful
fallback writes no-motion control data and marks the done file "fallback".
Praat v1.4 treats that marker as bypass and copies the source unchanged.

Optional live preview:
    When requested, the worker also plays a low-latency gestural preview during
    capture. The preview uses the same four-slot mapping graph as the offline
    render, with causal live normalization and a short granular pitch approximation
    for responsive performance. Offline normalization is take-relative, so the live
    path is a rehearsal monitor rather than a sample-exact preview. The offline
    Praat render remains the authoritative final result.

    v1.3+ adds a shared four-slot mapping engine. Gesture sources can be motion
    energy, vertical/horizontal position, speed, stillness, radius, or
    acceleration; destinations are amplitude, pitch, brightness, and stereo pan.

Dependencies:
    numpy          pip install numpy
    opencv-python  pip install opencv-python
    sounddevice    pip install sounddevice   (optional: live audio only)
"""

import sys
import os
import time as _time
import math

# ---------------------------------------------------------------------------
# Module-level constants  (overridden by CLI args where applicable)
# ---------------------------------------------------------------------------
CAPTURE_SEC   = 10      # default video capture duration in seconds
CAL_SEC       = 2       # calibration (background modelling) duration
CONTROL_FPS   = 25      # output control frame rate  (25 fps = 40 ms steps)
SMOOTH_FRAMES = 5       # EMA half-width — larger = slower, smoother response
DEADBAND      = 0.04    # energy below this snaps positions to neutral (0.5)
HYSTERESIS    = 0.35    # lazy-follower blend alpha (higher = more inertia)
CAM_INDEX     = 0       # webcam device index
NEUTRAL_POS   = 0.5     # position fallback when motion is absent


# Gesture mapping codes shared with MotionControl.praat
SRC_ENERGY = 1
SRC_VERTICAL = 2
SRC_HORIZONTAL = 3
SRC_SPEED = 4
SRC_STILLNESS = 5
SRC_RADIUS = 6
SRC_ACCELERATION = 7
SRC_NONE = 8

DST_AMPLITUDE = 1
DST_PITCH = 2
DST_BRIGHTNESS = 3
DST_PAN = 4
DST_NONE = 5

DEFAULT_MAPPING_SPEC = "1:1:0.8:0,2:2:0.5:0,3:3:0.8:0,3:4:1.0:0"


def parse_mapping_spec(spec):
    """Parse `source:destination:amount:invert` slots from Praat."""
    mappings = []
    text = (spec or "").strip()
    if not text:
        text = DEFAULT_MAPPING_SPEC
    for slot in text.split(","):
        parts = slot.strip().split(":")
        if len(parts) != 4:
            continue
        try:
            src = int(parts[0])
            dst = int(parts[1])
            amount = max(0.0, min(1.5, float(parts[2])))
            invert = int(float(parts[3])) != 0
        except (TypeError, ValueError):
            continue
        if src < SRC_ENERGY or src > SRC_NONE:
            src = SRC_NONE
        if dst < DST_AMPLITUDE or dst > DST_NONE:
            dst = DST_NONE
        mappings.append((src, dst, amount, invert))
    while len(mappings) < 4:
        mappings.append((SRC_NONE, DST_NONE, 0.0, False))
    return mappings[:4]


def _feature_scalar(features, source_code):
    if source_code == SRC_ENERGY:
        return float(features.get("energy", 0.0))
    if source_code == SRC_VERTICAL:
        return float(features.get("vertical", 0.5))
    if source_code == SRC_HORIZONTAL:
        return float(features.get("horizontal", 0.5))
    if source_code == SRC_SPEED:
        return float(features.get("speed", 0.0))
    if source_code == SRC_STILLNESS:
        return float(features.get("stillness", 1.0))
    if source_code == SRC_RADIUS:
        return float(features.get("radius", 0.0))
    if source_code == SRC_ACCELERATION:
        return float(features.get("acceleration", 0.0))
    return 0.5


def _source_modulation(value, source_code):
    """X/Y are bipolar around centre; dynamics are unipolar from neutral zero."""
    value = max(0.0, min(1.0, float(value)))
    if source_code in (SRC_VERTICAL, SRC_HORIZONTAL):
        return (value - 0.5) * 2.0
    return value


def evaluate_mapping_frame(features, mappings, pitch_span_st=12.0,
                           brightness_span=1.0):
    """Evaluate four mapping slots for one live-control frame."""
    import numpy as np
    amp = 1.0
    pitch = 0.0
    bright = 0.0
    pan = 0.0
    for src, dst, amount, invert in mappings:
        if src == SRC_NONE or dst == DST_NONE or amount <= 0:
            continue
        value = float(np.clip(_feature_scalar(features, src), 0.0, 1.0))
        if invert:
            value = 1.0 - value
        if dst == DST_AMPLITUDE:
            # Unipolar: amount=1 maps source 0..1 to gain 0..1.
            amp *= max(0.0, 1.0 - amount * (1.0 - value))
        else:
            mod = _source_modulation(value, src)
            if dst == DST_PITCH:
                pitch += mod * amount * pitch_span_st
            elif dst == DST_BRIGHTNESS:
                bright += mod * amount * brightness_span
            elif dst == DST_PAN:
                pan += mod * amount
    return (float(np.clip(amp, 0.0, 2.0)),
            float(np.clip(pitch, -24.0, 24.0)),
            float(np.clip(bright, -1.0, 2.0)),
            float(np.clip(pan, -1.0, 1.0)))


def compute_destination_controls(energy, vert, horiz, speed, stillness,
                                 radius, acceleration, mappings,
                                 pitch_span_st=12.0, brightness_span=1.0):
    """Vectorized-equivalent mapping evaluation for the saved control timeline."""
    import numpy as np
    arrays = {
        SRC_ENERGY: np.asarray(energy, dtype=np.float64),
        SRC_VERTICAL: np.asarray(vert, dtype=np.float64),
        SRC_HORIZONTAL: np.asarray(horiz, dtype=np.float64),
        SRC_SPEED: np.asarray(speed, dtype=np.float64),
        SRC_STILLNESS: np.asarray(stillness, dtype=np.float64),
        SRC_RADIUS: np.asarray(radius, dtype=np.float64),
        SRC_ACCELERATION: np.asarray(acceleration, dtype=np.float64),
    }
    n = len(arrays[SRC_ENERGY])
    amp = np.ones(n, dtype=np.float64)
    pitch = np.zeros(n, dtype=np.float64)
    bright = np.zeros(n, dtype=np.float64)
    pan = np.zeros(n, dtype=np.float64)
    for src, dst, amount, invert in mappings:
        if src == SRC_NONE or dst == DST_NONE or amount <= 0:
            continue
        values = arrays.get(src, np.full(n, 0.5, dtype=np.float64))
        values = np.clip(values, 0.0, 1.0)
        if invert:
            values = 1.0 - values
        if dst == DST_AMPLITUDE:
            amp *= np.maximum(0.0, 1.0 - amount * (1.0 - values))
        else:
            if src in (SRC_VERTICAL, SRC_HORIZONTAL):
                mod = (values - 0.5) * 2.0
            else:
                mod = values
            if dst == DST_PITCH:
                pitch += mod * amount * pitch_span_st
            elif dst == DST_BRIGHTNESS:
                bright += mod * amount * brightness_span
            elif dst == DST_PAN:
                pan += mod * amount
    return (np.clip(amp, 0.0, 2.0),
            np.clip(pitch, -24.0, 24.0),
            np.clip(bright, -1.0, 2.0),
            np.clip(pan, -1.0, 1.0))


# ---------------------------------------------------------------------------
# Dependency check
# ---------------------------------------------------------------------------

def check_dependencies():
    """Abort with a helpful message if required packages are missing."""
    missing = []
    for pkg, label in [("numpy", "numpy"), ("cv2", "opencv-python")]:
        try:
            __import__(pkg)
        except ImportError:
            missing.append(label)
    if missing:
        print("ERROR: Missing packages: " + ", ".join(missing), file=sys.stderr)
        print("Install with:  pip install " + " ".join(missing), file=sys.stderr)
        sys.exit(1)


# =============================================================================
# Stage 1 — Open camera
# =============================================================================

def open_camera(cam_index):
    """
    Open the webcam at cam_index and read its declared FPS.
    Returns (cap, fps).  Raises RuntimeError if the camera cannot be opened.
    The FPS value is clamped to a sensible range; many cameras mis-report it.
    """
    import cv2
    cap = cv2.VideoCapture(cam_index)
    if not cap.isOpened():
        raise RuntimeError(
            "Could not open camera at index %d. "
            "Check that a webcam is connected and not in use by another app."
            % cam_index
        )
    fps = cap.get(cv2.CAP_PROP_FPS)
    if fps <= 0 or fps > 300:
        fps = 30.0          # safe default when camera mis-reports
    return cap, fps


# =============================================================================
# Optional live audio preview
# =============================================================================

def _read_pcm_wav(path):
    """Read an integer PCM WAV using only the Python standard library."""
    import wave
    import numpy as np

    with wave.open(path, "rb") as wf:
        n_ch = wf.getnchannels()
        sr = wf.getframerate()
        sw = wf.getsampwidth()
        n_frames = wf.getnframes()
        raw = wf.readframes(n_frames)

    if sw == 1:
        data = (np.frombuffer(raw, dtype=np.uint8).astype(np.float32) - 128.0) / 128.0
    elif sw == 2:
        data = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
    elif sw == 3:
        b = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 3)
        vals = (b[:, 0].astype(np.int32)
                | (b[:, 1].astype(np.int32) << 8)
                | (b[:, 2].astype(np.int32) << 16))
        vals = np.where(vals & 0x800000, vals - 0x1000000, vals)
        data = vals.astype(np.float32) / 8388608.0
    elif sw == 4:
        data = np.frombuffer(raw, dtype="<i4").astype(np.float32) / 2147483648.0
    else:
        raise RuntimeError("Unsupported WAV sample width: %d bytes" % sw)

    if n_ch > 1:
        data = data.reshape(-1, n_ch)
    else:
        data = data.reshape(-1, 1)
    return data, int(sr)


def _linear_resample_audio(audio, sr_in, sr_out):
    import numpy as np
    if sr_in == sr_out or len(audio) < 2:
        return audio.astype(np.float32, copy=True)
    n_out = max(2, int(round(len(audio) * float(sr_out) / float(sr_in))))
    pos = np.linspace(0.0, len(audio) - 1.0, n_out)
    i0 = np.floor(pos).astype(np.int64)
    i1 = np.minimum(i0 + 1, len(audio) - 1)
    frac = (pos - i0).astype(np.float32)[:, None]
    out = audio[i0] * (1.0 - frac) + audio[i1] * frac
    return out.astype(np.float32)


def _prepare_live_channels(audio, max_output_channels):
    """Mirror Praat's representative-channel rule, then duplicate for live pan.

    Preserve channel 1 for compatibility unless it is nearly silent (<10% of
    the strongest channel), in which case use the strongest channel.
    """
    import numpy as np
    max_output_channels = max(1, int(max_output_channels))
    n_ch = audio.shape[1]
    if n_ch == 1:
        mono = audio[:, :1]
    else:
        rms = np.sqrt(np.mean(audio.astype(np.float64) ** 2, axis=0))
        strongest = int(np.argmax(rms))
        chosen = 0
        if rms[strongest] > 0.0 and rms[0] < 0.1 * rms[strongest]:
            chosen = strongest
        mono = audio[:, [chosen]]
    if max_output_channels >= 2:
        return np.repeat(mono, 2, axis=1)
    return mono


class LivePreviewEngine(object):
    """Low-latency gestural preview sharing the same mapping engine as offline."""

    def __init__(self, wav_path, pitch_range_st, amplitude_min, amplitude_max,
                 brightness_range, response_mode="smooth", live_volume=0.8,
                 blocksize=512, mappings=None, pitch_span_st=None,
                 brightness_span=None, brightness_cutoff_hz=2000.0):
        import numpy as np
        try:
            import sounddevice as sd
        except ImportError:
            raise RuntimeError("sounddevice not installed (pip install sounddevice)")

        self.sd = sd
        info = sd.query_devices(kind="output")
        max_out = max(1, int(info.get("max_output_channels", 2)))
        device_sr = int(round(float(info.get("default_samplerate", 48000.0))))
        if device_sr < 8000:
            device_sr = 48000

        audio, source_sr = _read_pcm_wav(wav_path)
        audio = _prepare_live_channels(audio, max_out)
        audio = _linear_resample_audio(audio, source_sr, device_sr)

        self.audio = np.asarray(audio, dtype=np.float32)
        self.sr = device_sr
        self.n_ch = self.audio.shape[1]
        self.blocksize = int(blocksize)
        self.legacy_pitch_range_st = float(pitch_range_st)
        self.legacy_amplitude_min = float(amplitude_min)
        self.legacy_amplitude_max = float(amplitude_max)
        self.legacy_brightness_range = float(brightness_range)
        self.mappings = mappings
        self.pitch_span_st = float(pitch_span_st if pitch_span_st is not None else pitch_range_st)
        self.brightness_span = float(brightness_span if brightness_span is not None else brightness_range)
        self.brightness_cutoff_hz = max(100.0, float(brightness_cutoff_hz))
        self.live_volume = max(0.0, min(1.5, float(live_volume)))
        self.response_mode = response_mode

        self.energy = 0.0
        self.vert = 0.5
        self.horiz = 0.5
        self.speed = 0.0
        self.stillness = 1.0
        self.radius = 0.0
        self.acceleration = 0.0
        self.amp_gain = 1.0
        self.pitch_shift = 0.0
        self.brightness_control = 0.0
        self.pan = 0.0
        # Applied control state is ramped block-to-block to avoid zipper steps.
        self._applied_amp = 1.0
        self._applied_bright = 0.0
        self._applied_pan = 0.0
        self.energy_ref = 12.0
        self.speed_ref = 0.8
        self.accel_ref = 3.0
        self._prev_vert = 0.5
        self._prev_horiz = 0.5
        self._prev_speed_raw = 0.0
        self._prev_update_time = None

        self.timeline_pos = 0
        self.ola_tail = np.zeros((self.blocksize, self.n_ch), dtype=np.float32)
        self.lp_state = np.zeros(self.n_ch, dtype=np.float32)
        self.window = np.hanning(self.blocksize * 2).astype(np.float32)[:, None]
        self.stream = None
        self.status = "off"
        self.underflows = 0

    def update_motion(self, raw_energy, vert, horiz):
        import numpy as np
        now = _time.monotonic()
        raw_energy = max(0.0, float(raw_energy))
        self.energy_ref = max(6.0, self.energy_ref * 0.995, raw_energy)
        e = min(1.0, raw_energy / (self.energy_ref + 1e-8))
        if e < 0.06:
            vert = 0.5
            horiz = 0.5

        alpha = 0.55 if self.response_mode == "direct" else 0.22
        new_energy = alpha * e + (1.0 - alpha) * self.energy
        new_vert = alpha * float(vert) + (1.0 - alpha) * self.vert
        new_horiz = alpha * float(horiz) + (1.0 - alpha) * self.horiz
        new_energy = float(np.clip(new_energy, 0.0, 1.0))
        new_vert = float(np.clip(new_vert, 0.0, 1.0))
        new_horiz = float(np.clip(new_horiz, 0.0, 1.0))

        if self._prev_update_time is None:
            dt = 1.0 / 30.0
        else:
            dt = max(1.0 / 120.0, min(0.2, now - self._prev_update_time))
        speed_raw = math.hypot(new_vert - self._prev_vert,
                               new_horiz - self._prev_horiz) / dt
        self.speed_ref = max(0.4, self.speed_ref * 0.995, speed_raw)
        speed_n = min(1.0, speed_raw / (self.speed_ref + 1e-8))
        accel_raw = abs(speed_raw - self._prev_speed_raw) / dt
        self.accel_ref = max(1.0, self.accel_ref * 0.995, accel_raw)
        accel_n = min(1.0, accel_raw / (self.accel_ref + 1e-8))

        self.energy = new_energy
        self.vert = new_vert
        self.horiz = new_horiz
        self.speed = alpha * speed_n + (1.0 - alpha) * self.speed
        self.acceleration = alpha * accel_n + (1.0 - alpha) * self.acceleration
        self.radius = min(1.0, math.hypot(self.vert - 0.5, self.horiz - 0.5) / math.sqrt(0.5))
        self.stillness = max(0.0, min(1.0, 1.0 - max(self.energy, self.speed)))

        self._prev_vert = self.vert
        self._prev_horiz = self.horiz
        self._prev_speed_raw = speed_raw
        self._prev_update_time = now

        if self.mappings is not None:
            features = {
                "energy": self.energy, "vertical": self.vert,
                "horizontal": self.horiz, "speed": self.speed,
                "stillness": self.stillness, "radius": self.radius,
                "acceleration": self.acceleration,
            }
            (self.amp_gain, self.pitch_shift, self.brightness_control,
             self.pan) = evaluate_mapping_frame(
                features, self.mappings, self.pitch_span_st, self.brightness_span)
        else:
            self.amp_gain = self.legacy_amplitude_min + self.energy * (
                self.legacy_amplitude_max - self.legacy_amplitude_min)
            self.pitch_shift = ((self.vert - 0.5) * 2.0 *
                                self.legacy_pitch_range_st)
            self.brightness_control = ((self.horiz - 0.5) * 2.0 *
                                       self.legacy_brightness_range)
            self.pan = 0.0

    def _sample_looped(self, positions):
        import numpy as np
        n = len(self.audio)
        if n < 2:
            return np.zeros((len(positions), self.n_ch), dtype=np.float32)
        pos = np.mod(positions, float(n))
        i0 = np.floor(pos).astype(np.int64)
        i1 = (i0 + 1) % n
        frac = (pos - i0).astype(np.float32)[:, None]
        return (self.audio[i0] * (1.0 - frac) + self.audio[i1] * frac).astype(np.float32)

    def render_block(self, frames=None):
        import numpy as np
        if frames is None:
            frames = self.blocksize
        frames = int(frames)
        if frames != self.blocksize:
            self.blocksize = frames
            self.ola_tail = np.zeros((frames, self.n_ch), dtype=np.float32)
            self.window = np.hanning(frames * 2).astype(np.float32)[:, None]

        amp_target = self.amp_gain
        semi = self.pitch_shift
        bright_target = self.brightness_control
        pan_target = self.pan

        ratio = 2.0 ** (semi / 12.0)
        grain_len = frames * 2
        center = float(self.timeline_pos + frames)
        offsets = (np.arange(grain_len, dtype=np.float64) - grain_len / 2.0) * ratio
        grain = self._sample_looped(center + offsets)
        grain *= self.window

        block = grain[:frames] + self.ola_tail
        self.ola_tail = grain[frames:].copy()
        self.timeline_pos += frames

        cutoff = min(self.brightness_cutoff_hz, self.sr * 0.45)
        alpha = 1.0 - np.exp(-2.0 * np.pi * cutoff / float(self.sr))
        hp = np.empty_like(block)
        low = self.lp_state.astype(np.float64)
        for i in range(frames):
            x = block[i].astype(np.float64)
            low = low + alpha * (x - low)
            hp[i] = (x - low).astype(np.float32)
        self.lp_state = low.astype(np.float32)

        # Ramp destination controls across the audio block. The mapping update
        # rate is camera-rate, so applying one scalar for ~10 ms blocks caused
        # audible parameter steps, especially for amplitude and pan.
        amp_ramp = np.linspace(self._applied_amp, amp_target, frames, dtype=np.float32)
        bright_ramp = np.linspace(self._applied_bright, bright_target, frames, dtype=np.float32)
        pan_ramp = np.linspace(self._applied_pan, pan_target, frames, dtype=np.float32)
        self._applied_amp = float(amp_target)
        self._applied_bright = float(bright_target)
        self._applied_pan = float(pan_target)

        block = block + hp * bright_ramp[:, None]

        if self.n_ch >= 2:
            theta = (pan_ramp + 1.0) * (np.pi / 4.0)
            block[:, 0] *= np.cos(theta)
            block[:, 1] *= np.sin(theta)

        block *= (amp_ramp[:, None] * self.live_volume)
        return np.clip(block, -0.98, 0.98).astype(np.float32)

    def _callback(self, outdata, frames, time_info, status):
        if status:
            self.underflows += 1
        try:
            outdata[:] = self.render_block(frames)
        except Exception:
            self.status = "error"
            outdata.fill(0)

    def start(self):
        self.stream = self.sd.OutputStream(
            samplerate=self.sr,
            channels=self.n_ch,
            dtype="float32",
            blocksize=self.blocksize,
            latency="low",
            callback=self._callback,
        )
        self.stream.start()
        self.status = "active"

    def stop(self):
        if self.stream is not None:
            try:
                self.stream.stop()
            except Exception:
                pass
            try:
                self.stream.close()
            except Exception:
                pass
            self.stream = None
        if self.status == "active":
            self.status = "complete"

def _frame_motion_measure(prev_gray, gray, bg_std):
    """One-frame raw motion measurement shared by live and offline paths."""
    import numpy as np
    diff = np.abs(gray - prev_gray)
    diff = np.maximum(0.0, diff - bg_std * 1.5)
    energy = float(np.mean(diff))
    total = float(np.sum(diff))
    if total > 0.5:
        h, w = diff.shape
        row_mass = np.sum(diff, axis=1, dtype=np.float64)
        col_mass = np.sum(diff, axis=0, dtype=np.float64)
        row_idx = np.arange(h, dtype=np.float64)
        col_idx = np.arange(w, dtype=np.float64)
        vert_c = 1.0 - float(np.dot(row_mass, row_idx) / total) / max(1.0, h - 1.0)
        horiz_c = float(np.dot(col_mass, col_idx) / total) / max(1.0, w - 1.0)
    else:
        vert_c = NEUTRAL_POS
        horiz_c = NEUTRAL_POS
    return energy, vert_c, horiz_c, diff


# =============================================================================
# Stage 2 — Calibration
# =============================================================================

def calibration_phase(cap, cal_sec):
    """
    Capture cal_sec seconds with the user holding still.
    Builds a per-pixel background mean and standard deviation.

    The standard deviation floor is raised to 1.0 to prevent
    excessive noise removal and division-by-zero.

    Returns:
        bg_mean  float32 (H, W) — mean background intensity
        bg_std   float32 (H, W) — std + 1.0 noise floor
    """
    import numpy as np
    import cv2

    frames  = []
    t_start = _time.time()
    while _time.time() - t_start < cal_sec:
        ret, frame = cap.read()
        if ret:
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY).astype(np.float32)
            frames.append(gray)

    if len(frames) < 2:
        # Degenerate fallback — return a flat background
        ret, frame = cap.read()
        if ret:
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY).astype(np.float32)
        else:
            gray = np.zeros((480, 640), dtype=np.float32)
        return gray, np.ones_like(gray)

    bg_mean = np.mean(frames, axis=0)
    bg_std  = np.std(frames,  axis=0) + 1.0   # floor prevents over-suppression
    return bg_mean, bg_std


# =============================================================================
# Stage 3 — Capture with optional preview window
# =============================================================================

def capture_phase(cap, capture_sec, show_preview, bg_std=None, live_engine=None):
    """
    Capture capture_sec seconds of video from the already-open camera.
    Optionally renders a live preview with motion-heat overlay and countdown.
    If live_engine is active, raw per-frame motion is also sent to the audio
    preview immediately; final control extraction still happens offline later.
    """
    import numpy as np
    import cv2

    frames          = []
    prev_gray       = None
    preview_active  = False

    if show_preview:
        try:
            win = "Motion Capture - Praat AudioTools"
            cv2.namedWindow(win, cv2.WINDOW_NORMAL)
            cv2.resizeWindow(win, 640, 480)
            preview_active = True
        except Exception:
            preview_active = False

    t_start = _time.time()

    while True:
        elapsed = _time.time() - t_start
        if elapsed >= capture_sec:
            break

        ret, frame = cap.read()
        if not ret:
            continue

        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY).astype(np.float32)
        frames.append((elapsed, gray))

        diff = None
        if prev_gray is not None:
            if bg_std is not None:
                raw_e, raw_v, raw_h, diff = _frame_motion_measure(
                    prev_gray, gray, bg_std)
                if live_engine is not None:
                    live_engine.update_motion(raw_e, raw_v, raw_h)
            else:
                diff = np.abs(gray - prev_gray)

        if preview_active:
            try:
                vis = frame.copy()
                if diff is not None:
                    diff_vis = np.clip(diff / 40.0 * 255, 0, 255).astype(np.uint8)
                    heat = cv2.applyColorMap(diff_vis, cv2.COLORMAP_JET)
                    vis = cv2.addWeighted(vis, 0.55, heat, 0.45, 0)

                remaining = max(0.0, capture_sec - elapsed)
                label = "RECORDING  %.1fs remaining" % remaining
                cv2.rectangle(vis, (8, 6), (430, 52), (0, 0, 0), -1)
                cv2.putText(vis, label, (16, 38),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.9, (0, 255, 80), 2)

                if live_engine is not None:
                    status = "LIVE  A %.2f  P %+.1f  B %+.2f  PAN %+.2f" % (
                        live_engine.amp_gain, live_engine.pitch_shift,
                        live_engine.brightness_control, live_engine.pan)
                    cv2.rectangle(vis, (8, 58), (610, 94), (0, 0, 0), -1)
                    cv2.putText(vis, status, (16, 84),
                                cv2.FONT_HERSHEY_SIMPLEX, 0.58, (255, 180, 80), 2)

                cv2.imshow(win, vis)
                cv2.waitKey(1)
            except Exception:
                preview_active = False

        prev_gray = gray

    if preview_active:
        try:
            cv2.destroyAllWindows()
            cv2.waitKey(1)
        except Exception:
            pass

    return frames


# =============================================================================
# Stage 4 + 5 — Feature extraction and resampling
# =============================================================================

def extract_motion_features(frames, bg_std, control_fps, fallback_duration=CAPTURE_SEC):
    """
    Extract motion energy, vertical centroid, and horizontal centroid
    from the raw frame list via frame differencing.

    Per-frame positions are computed as the motion-weighted centroid of the
    noise-suppressed difference image:
      vertical_pos   0 = bottom of frame, 1 = top  (image row axis inverted)
      horizontal_pos 0 = left,            1 = right

    Features are first computed at the native capture rate and then
    linearly interpolated onto a uniform grid at control_fps.

    Returns:
        ctrl_times  ndarray (n,)  — uniform time grid, 0 .. total_dur
        ctrl_energy ndarray (n,)  — raw motion energy
        ctrl_vert   ndarray (n,)  — vertical centroid
        ctrl_horiz  ndarray (n,)  — horizontal centroid
    """
    import numpy as np

    if len(frames) < 2:
        n     = max(4, int(float(fallback_duration) * control_fps))
        times = np.linspace(0.0, float(fallback_duration), n)
        return times, np.full(n, 0.0), np.full(n, 0.5), np.full(n, 0.5)

    h, w = frames[0][1].shape

    # Coordinate grids, normalised to [0, 1]
    y_grid = np.tile(np.linspace(0.0, 1.0, h, dtype=np.float32)[:, None], (1, w))
    x_grid = np.tile(np.linspace(0.0, 1.0, w, dtype=np.float32)[None, :], (h, 1))

    raw_times  = []
    raw_energy = []
    raw_vert   = []
    raw_horiz  = []

    prev_gray = frames[0][1]

    for i in range(1, len(frames)):
        t, gray = frames[i]

        # Frame differencing
        diff = np.abs(gray - prev_gray)

        # Subtract noise floor (1.5 sigma from calibration)
        diff = np.maximum(0.0, diff - bg_std * 1.5)

        energy = float(np.mean(diff))

        # Motion-weighted centroid
        total = float(np.sum(diff))
        if total > 0.5:
            vert_c  = float(np.sum(diff * y_grid)) / total
            horiz_c = float(np.sum(diff * x_grid)) / total
        else:
            vert_c  = NEUTRAL_POS
            horiz_c = NEUTRAL_POS

        # Invert vertical: image top (row 0) should correspond to "high" (1)
        vert_c = 1.0 - vert_c

        raw_times.append(t)
        raw_energy.append(energy)
        raw_vert.append(vert_c)
        raw_horiz.append(horiz_c)

        prev_gray = gray

    raw_times  = np.array(raw_times,  dtype=np.float64)
    raw_energy = np.array(raw_energy, dtype=np.float64)
    raw_vert   = np.array(raw_vert,   dtype=np.float64)
    raw_horiz  = np.array(raw_horiz,  dtype=np.float64)

    # Resample to uniform control-rate grid
    total_dur  = float(raw_times[-1])
    n_ctrl     = max(4, int(total_dur * control_fps))
    ctrl_times = np.linspace(0.0, total_dur, n_ctrl)

    ctrl_energy = np.interp(ctrl_times, raw_times, raw_energy)
    ctrl_vert   = np.interp(ctrl_times, raw_times, raw_vert)
    ctrl_horiz  = np.interp(ctrl_times, raw_times, raw_horiz)

    return ctrl_times, ctrl_energy, ctrl_vert, ctrl_horiz


# =============================================================================
# Stage 6 — Smooth, normalize, deadband, hysteresis
# =============================================================================

def smooth_normalize(ctrl_times, ctrl_energy, ctrl_vert, ctrl_horiz, smooth_frames):
    """
    Apply the musical-control signal processing chain:

      1. Exponential moving average (EMA) — reduces high-frequency jitter.
         The effective window is smooth_frames; larger = slower response.

      2. Percentile stretch (5th–95th pct) — maps the actual range to 0..1
         so sparse or weak motion still uses the full scale.

      3. Deadband + soft transition — when energy is below DEADBAND,
         positions glide to neutral (0.5) via a 3×deadband transition zone.
         This prevents jitter from driving the transforms when the user is still.

      4. Hysteresis (lazy follower) — first-order IIR on positions.
         Slows fast transitions to reduce zipper noise in the mapped sound.

      5. Final clamp to [0, 1].

    Returns:
        energy_n  (n,)  normalized motion energy
        vert_n    (n,)  processed vertical position
        horiz_n   (n,)  processed horizontal position
    """
    import numpy as np

    def ema(arr, n):
        if n <= 1:
            return arr.copy()
        alpha = 2.0 / (float(n) + 1.0)
        out   = arr.copy()
        for i in range(1, len(out)):
            out[i] = alpha * arr[i] + (1.0 - alpha) * out[i - 1]
        return out

    def pct_stretch(arr, lo_pct=5, hi_pct=95, fallback=0.3):
        lo = np.percentile(arr, lo_pct)
        hi = np.percentile(arr, hi_pct)
        if hi - lo < 1e-7:
            return np.full_like(arr, fallback)
        return np.clip((arr - lo) / (hi - lo), 0.0, 1.0)

    def lazy_follow(arr, alpha=HYSTERESIS):
        out = arr.copy()
        for i in range(1, len(out)):
            out[i] = (1.0 - alpha) * arr[i] + alpha * out[i - 1]
        return out

    # 1. Smooth
    energy_s = ema(ctrl_energy, smooth_frames)
    vert_s   = ema(ctrl_vert,   smooth_frames)
    horiz_s  = ema(ctrl_horiz,  smooth_frames)

    # 2. Normalize
    energy_n = pct_stretch(energy_s, 5,  95, fallback=0.2)
    vert_n   = pct_stretch(vert_s,   5,  95, fallback=0.5)
    horiz_n  = pct_stretch(horiz_s,  5,  95, fallback=0.5)

    # 3. Deadband — soft blend toward neutral
    dead_floor = max(DEADBAND, 1e-6)
    blend = np.clip((energy_n - DEADBAND) / (3.0 * dead_floor), 0.0, 1.0)
    vert_n  = blend * vert_n  + (1.0 - blend) * NEUTRAL_POS
    horiz_n = blend * horiz_n + (1.0 - blend) * NEUTRAL_POS

    # 4. Hysteresis on positions
    vert_n  = lazy_follow(vert_n)
    horiz_n = lazy_follow(horiz_n)

    # 5. Final clamp
    energy_n = np.clip(energy_n, 0.0, 1.0)
    vert_n   = np.clip(vert_n,   0.0, 1.0)
    horiz_n  = np.clip(horiz_n,  0.0, 1.0)

    return energy_n, vert_n, horiz_n


def derive_gesture_features(ctrl_times, energy, vert, horiz):
    """Derive speed, stillness, radius and acceleration in normalized 0..1 form."""
    import numpy as np
    times = np.asarray(ctrl_times, dtype=np.float64)
    energy = np.asarray(energy, dtype=np.float64)
    vert = np.asarray(vert, dtype=np.float64)
    horiz = np.asarray(horiz, dtype=np.float64)
    n = len(times)
    if n == 0:
        z = np.zeros(0, dtype=np.float64)
        return z, z, z, z

    dt = np.diff(times, prepend=times[0])
    if n > 1:
        fallback_dt = max(1e-4, float(np.median(np.diff(times))))
    else:
        fallback_dt = 1.0 / 25.0
    dt[dt <= 1e-6] = fallback_dt

    dv = np.diff(vert, prepend=vert[0])
    dh = np.diff(horiz, prepend=horiz[0])
    speed_raw = np.sqrt(dv * dv + dh * dh) / dt
    accel_raw = np.abs(np.diff(speed_raw, prepend=speed_raw[0])) / dt

    def ema(arr, alpha=0.35):
        out = np.asarray(arr, dtype=np.float64).copy()
        for i in range(1, len(out)):
            out[i] = alpha * out[i] + (1.0 - alpha) * out[i - 1]
        return out

    def robust01(arr, fallback=0.0):
        arr = ema(arr)
        lo = float(np.percentile(arr, 5))
        hi = float(np.percentile(arr, 95))
        if hi - lo < 1e-9:
            return np.full_like(arr, fallback)
        return np.clip((arr - lo) / (hi - lo), 0.0, 1.0)

    speed = robust01(speed_raw, 0.0)
    acceleration = robust01(accel_raw, 0.0)
    radius = np.sqrt((vert - 0.5) ** 2 + (horiz - 0.5) ** 2) / math.sqrt(0.5)
    radius = np.clip(radius, 0.0, 1.0)
    stillness = np.clip(1.0 - np.maximum(energy, speed), 0.0, 1.0)
    return speed, stillness, radius, acceleration


# =============================================================================
# Stage 7 — Write output files
# =============================================================================

def write_control_csv(path, times, energy, vert, horiz,
                      speed=None, stillness=None, radius=None, acceleration=None,
                      amplitude_gain=None, pitch_shift_st=None,
                      brightness_control=None, pan=None):
    """Write gesture sources plus mapped destination controls."""
    import numpy as np
    n = len(times)
    def arr(value, fallback):
        if value is None:
            return np.full(n, fallback, dtype=np.float64)
        return np.asarray(value, dtype=np.float64)
    speed = arr(speed, 0.0)
    stillness = arr(stillness, 1.0)
    radius = arr(radius, 0.0)
    acceleration = arr(acceleration, 0.0)
    amplitude_gain = arr(amplitude_gain, 1.0)
    pitch_shift_st = arr(pitch_shift_st, 0.0)
    brightness_control = arr(brightness_control, 0.0)
    pan = arr(pan, 0.0)
    with open(path, "w") as f:
        f.write("time,motion_energy,vertical_pos,horizontal_pos,speed,stillness,radius,acceleration,amplitude_gain,pitch_shift_st,brightness_control,pan\n")
        for i in range(n):
            f.write("%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f\n" % (
                float(times[i]), float(energy[i]), float(vert[i]), float(horiz[i]),
                float(speed[i]), float(stillness[i]), float(radius[i]), float(acceleration[i]),
                float(amplitude_gain[i]), float(pitch_shift_st[i]),
                float(brightness_control[i]), float(pan[i])))


def write_stats(path, times, energy, vert, horiz,
                cam_fps, n_raw_frames, warnings, live_status="off",
                live_underflows=0, speed=None, stillness=None, radius=None,
                acceleration=None, mapping_spec=""):

    """
    Write key=value stats file parseable by Praat's parseStatLine procedure.
    All keys use the exact names expected by MotionControl.praat.
    """
    import numpy as np

    dur           = float(times[-1]) if len(times) > 0 else 0.0
    n_ctrl        = int(len(times))
    tracking_conf = float(np.mean(energy > DEADBAND))

    with open(path, "w") as f:
        f.write("duration=%.3f\n"            % dur)
        f.write("camera_fps=%.2f\n"          % float(cam_fps))
        f.write("n_raw_frames=%d\n"          % int(n_raw_frames))
        f.write("n_ctrl_frames=%d\n"         % n_ctrl)
        f.write("mean_motion=%.4f\n"         % float(np.mean(energy)))
        f.write("max_motion=%.4f\n"          % float(np.max(energy)))
        f.write("mean_vert=%.4f\n"           % float(np.mean(vert)))
        f.write("mean_horiz=%.4f\n"          % float(np.mean(horiz)))
        f.write("tracking_confidence=%.3f\n" % tracking_conf)
        f.write("live_audio_status=%s\n" % str(live_status))
        f.write("live_audio_underflows=%d\n" % int(live_underflows))
        f.write("mapping_spec=%s\n" % str(mapping_spec))
        if speed is not None:
            f.write("mean_speed=%.4f\n" % float(np.mean(speed)))
        if stillness is not None:
            f.write("mean_stillness=%.4f\n" % float(np.mean(stillness)))
        if radius is not None:
            f.write("mean_radius=%.4f\n" % float(np.mean(radius)))
        if acceleration is not None:
            f.write("mean_acceleration=%.4f\n" % float(np.mean(acceleration)))
        if warnings:
            f.write("warnings=%s\n"  % "; ".join(warnings))
        else:
            f.write("warnings=none\n")


# =============================================================================
# Fallback — neutral data when camera is unavailable
# =============================================================================

def generate_fallback_data(capture_sec, control_fps):
    """
    Return neutral no-motion control data when the webcam fails.
    Motion energy is 0.0 and positions are centred at 0.5.  Praat v1.2
    bypasses transformation when the done marker says fallback, so these
    values are diagnostic/visualization data rather than fake performance.
    """
    import numpy as np
    n     = max(4, int(float(capture_sec) * float(control_fps)))
    times = np.linspace(0.0, float(capture_sec), n)
    return (times,
            np.full(n, 0.00, dtype=np.float64),
            np.full(n, 0.50, dtype=np.float64),
            np.full(n, 0.50, dtype=np.float64))


# =============================================================================
# Main
# =============================================================================

def main():
    if len(sys.argv) < 4:
        print(
            "Usage: python motion_control.py "
            "control_csv stats_txt done_marker "
            "[capture_sec] [control_fps] [smooth_frames] [show_preview] "
            "[live_audio] [live_wav] [pitch_range_st] [amplitude_min] "
            "[amplitude_max] [brightness_range] [live_response] [live_volume] [mapping_spec] [pitch_span_st] [brightness_span] [brightness_cutoff_hz]",
            file=sys.stderr)
        sys.exit(1)

    check_dependencies()
    import numpy as np

    # ── Parse + clamp CLI arguments ─────────────────────────────────
    control_csv  = sys.argv[1]
    stats_txt    = sys.argv[2]
    done_marker  = sys.argv[3]
    capture_sec  = float(sys.argv[4])     if len(sys.argv) > 4 else float(CAPTURE_SEC)
    control_fps  = int(sys.argv[5])       if len(sys.argv) > 5 else CONTROL_FPS
    smooth_frm   = int(sys.argv[6])       if len(sys.argv) > 6 else SMOOTH_FRAMES
    show_preview = (sys.argv[7] == "1")   if len(sys.argv) > 7 else True
    live_audio   = (sys.argv[8] == "1")   if len(sys.argv) > 8 else False
    live_wav     = sys.argv[9]             if len(sys.argv) > 9 else ""
    pitch_range  = float(sys.argv[10])     if len(sys.argv) > 10 else 6.0
    amplitude_min = float(sys.argv[11])    if len(sys.argv) > 11 else 0.20
    amplitude_max = float(sys.argv[12])    if len(sys.argv) > 12 else 1.00
    brightness_range = float(sys.argv[13]) if len(sys.argv) > 13 else 0.80
    live_response = sys.argv[14].lower()   if len(sys.argv) > 14 else "smooth"
    live_volume   = float(sys.argv[15])    if len(sys.argv) > 15 else 0.80
    mapping_spec  = sys.argv[16]           if len(sys.argv) > 16 else ""
    pitch_span_st = float(sys.argv[17])    if len(sys.argv) > 17 else 12.0
    brightness_span = float(sys.argv[18])  if len(sys.argv) > 18 else 1.0
    brightness_cutoff_hz = float(sys.argv[19]) if len(sys.argv) > 19 else 2000.0

    capture_sec = max(3.0, min(60.0, capture_sec))
    control_fps = max(10, min(100, control_fps))
    smooth_frm  = max(1,  min(50,  smooth_frm))
    pitch_range = max(0.0, min(24.0, pitch_range))
    amplitude_min = max(0.0, min(1.0, amplitude_min))
    amplitude_max = max(amplitude_min, min(2.0, amplitude_max))
    brightness_range = max(0.0, min(2.0, brightness_range))
    live_volume = max(0.0, min(1.5, live_volume))
    pitch_span_st = max(0.0, min(24.0, pitch_span_st))
    brightness_span = max(0.0, min(2.0, brightness_span))
    brightness_cutoff_hz = max(100.0, min(12000.0, brightness_cutoff_hz))
    if live_response not in ("direct", "smooth"):
        live_response = "smooth"
    mappings = parse_mapping_spec(mapping_spec) if mapping_spec else None

    warnings = []
    cam_fps  = 0.0
    n_raw    = 0
    live_status = "off"
    live_engine = None

    # ── Stage 1–3: Open camera, calibrate, capture ──────────────────
    frames = None
    bg_std = None
    cap = None

    try:
        print("  [Py 1/5] Opening camera (index %d)..." % CAM_INDEX)
        cap, cam_fps = open_camera(CAM_INDEX)

        print("  [Py 2/5] Calibration (%.0fs) — hold still..." % CAL_SEC)
        bg_mean, bg_std = calibration_phase(cap, CAL_SEC)
        print("           Background model built.")

        print("  [Py 3/5] Recording %.2fs — MOVE NOW!" % capture_sec)
        if live_audio:
            if not live_wav or not os.path.isfile(live_wav):
                live_status = "unavailable"
                warnings.append("Live audio unavailable: temporary source WAV not found")
            else:
                try:
                    live_engine = LivePreviewEngine(
                        live_wav, pitch_range, amplitude_min, amplitude_max,
                        brightness_range, response_mode=live_response,
                        live_volume=live_volume, mappings=mappings,
                        pitch_span_st=pitch_span_st,
                        brightness_span=brightness_span,
                        brightness_cutoff_hz=brightness_cutoff_hz)
                    live_engine.start()
                    live_status = "active"
                    print("           Live audio preview active (%s response)." % live_response)
                except Exception as exc:
                    live_engine = None
                    live_status = "unavailable"
                    warnings.append("Live audio unavailable: " + str(exc))
                    print("  WARNING: Live audio unavailable (%s)" % str(exc),
                          file=sys.stderr)

        frames = capture_phase(cap, capture_sec, show_preview,
                               bg_std=bg_std, live_engine=live_engine)
        n_raw = len(frames)
        print("    Captured %d frames (camera: %.1f fps)" % (n_raw, cam_fps))
        if n_raw < 2:
            raise RuntimeError("Camera capture returned fewer than 2 usable frames")

    except Exception as exc:
        msg = str(exc)
        warnings.append("Camera error: " + msg)
        print("  WARNING: Camera unavailable (%s)" % msg, file=sys.stderr)
        print("           Writing neutral fallback data.")

        times, energy, vert, horiz = generate_fallback_data(capture_sec, control_fps)
        speed, stillness, radius, acceleration = derive_gesture_features(
            times, energy, vert, horiz)
        active_mappings = mappings if mappings is not None else parse_mapping_spec("")
        amp_gain, pitch_shift, bright_ctl, pan_ctl = compute_destination_controls(
            energy, vert, horiz, speed, stillness, radius, acceleration,
            active_mappings, pitch_span_st, brightness_span)
        write_control_csv(control_csv, times, energy, vert, horiz,
                          speed, stillness, radius, acceleration,
                          amp_gain, pitch_shift, bright_ctl, pan_ctl)
        if live_engine is not None:
            live_engine.stop()
            if live_status == "active":
                live_status = live_engine.status
        write_stats(stats_txt, times, energy, vert, horiz,
                    cam_fps, n_raw, warnings, live_status=live_status,
                    live_underflows=(live_engine.underflows if live_engine is not None else 0),
                    speed=speed, stillness=stillness, radius=radius,
                    acceleration=acceleration, mapping_spec=mapping_spec)
        with open(done_marker, "w") as f:
            f.write("fallback\n")
        print("OK: fallback data written to %s" % control_csv)
        return

    finally:
        if live_engine is not None:
            live_engine.stop()
            if live_status == "active":
                live_status = live_engine.status
        if cap is not None:
            try:
                cap.release()
            except Exception:
                pass

    if live_engine is not None and live_status == "error":
        warnings.append("Live audio stream stopped because of a callback error")
    elif live_engine is not None and live_engine.underflows > 5:
        warnings.append("Live audio stream reported %d timing notices" % live_engine.underflows)

    # ── Stage 4+5: Feature extraction ───────────────────────────────
    print("  [Py 4/5] Extracting motion features...")
    times, energy, vert, horiz = extract_motion_features(
        frames, bg_std, control_fps, fallback_duration=capture_sec)
    print("    %d ctrl frames  |  energy range: [%.3f, %.3f]" % (
        len(times), float(np.min(energy)), float(np.max(energy))))

    if len(times) < 4:
        warnings.append("Too few control frames extracted (%d)" % len(times))
        times, energy, vert, horiz = generate_fallback_data(capture_sec, control_fps)
        print("    WARNING: Using fallback data.")

    # ── Stage 6: Smooth + normalize ─────────────────────────────────
    print("  [Py 5/5] Smoothing and normalizing (EMA window=%d)..." % smooth_frm)
    energy, vert, horiz = smooth_normalize(
        times, energy, vert, horiz, smooth_frm)

    tracking_conf = float(np.mean(energy > DEADBAND))
    print("    Tracking confidence: %.0f%%" % (tracking_conf * 100.0))
    if tracking_conf < 0.30:
        warnings.append(
            "Low tracking confidence (%.0f%%) — check lighting and movement range"
            % (tracking_conf * 100.0))

    # ── Stage 7: Derived gesture features + shared mapping engine ─────────
    speed, stillness, radius, acceleration = derive_gesture_features(
        times, energy, vert, horiz)
    active_mappings = mappings if mappings is not None else parse_mapping_spec("")
    amp_gain, pitch_shift, bright_ctl, pan_ctl = compute_destination_controls(
        energy, vert, horiz, speed, stillness, radius, acceleration,
        active_mappings, pitch_span_st, brightness_span)

    write_control_csv(control_csv, times, energy, vert, horiz,
                      speed, stillness, radius, acceleration,
                      amp_gain, pitch_shift, bright_ctl, pan_ctl)
    write_stats(stats_txt, times, energy, vert, horiz,
                cam_fps, n_raw, warnings, live_status=live_status,
                live_underflows=(live_engine.underflows if live_engine is not None else 0),
                speed=speed, stillness=stillness, radius=radius,
                acceleration=acceleration, mapping_spec=mapping_spec)

    with open(done_marker, "w") as f:
        f.write("ok\n")

    print("OK: wrote %d control frames to %s" % (len(times), control_csv))


if __name__ == "__main__":
    main()
