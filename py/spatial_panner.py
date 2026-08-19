#!/usr/bin/env python3
# ============================================================
# Praat AudioTools Plugin
# Script:      spatial_panner.py
# Author:      Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version:     2.3 (2026)
# License:     MIT License
#
# Description:
#   2D circular spatial trajectory editor.
#   - Draw a moving sound source path inside a circle
#   - Convert trajectory to N-channel loudspeaker gains via DBAP
#   - Mono input → N-channel output WAV
#
# Data model:
#   trajectory : list of [time, x, y]
#     time — seconds, 0..duration
#     x, y — unit circle coordinates, -1..+1
#   Sorted by time. Always has anchors at t=0 and t=duration.
#   Interpolation: linear between consecutive points.
#
# Speaker model:
#   speakers : list of (label, angle_deg, radius)
#     Default: 8 speakers evenly around a circle of radius 1.0
#     angle 0° = top (12 o'clock), increases clockwise.
#
# DBAP (Distance-Based Amplitude Panning):
#   gain_i = (1 / d_i^k) / sqrt(sum_j (1 / d_j^k)^2)
#   k = 1 (distance rolloff exponent, adjustable)
#   Normalization: sqrt(sum gains^2) = 1  (constant gain-vector power)
#   When source is very close to a speaker, a small epsilon prevents division
#   by zero and ensures energy is smoothly concentrated.
#
# Multichannel input: use the strongest-RMS real channel as the mono source,
# avoiding phase-cancelling fold-down.
#
# Usage (called by Praat):
#   python spatial_panner.py  input.wav  output.wav
#
# Dependencies:
#   pip install numpy soundfile scipy
#   tkinter — standard Python
#   Optional audition: pip install sounddevice
#
# Changelog v2.3 (2026):
#   - Add explicit Audition output-device selector with host API and channel count
#   - Default to the current PortAudio output device, with manual Refresh
#   - Validate requested channel count/sample rate with check_output_settings()
#   - Pass the selected device explicitly to OutputStream
#   - Device changes stop an active audition so heard and displayed state stay aligned
#
# Changelog v2.2 (2026):
#   - Add non-destructive Audition/Stop in the trajectory GUI
#   - Audition plays exact N-channel DBAP when the selected device supports it
#   - Otherwise audition uses a power-normalised stereo speaker-ring monitor
#   - sounddevice is optional: Apply/render still works without it
#
# Changelog v2.1 (2026):
#   - Preserve the input sample rate; spatial panning no longer resamples to 44.1 kHz
#   - Multichannel input uses the strongest-RMS real channel instead of averaging
#   - Output safety is attenuation-only; quiet inputs are no longer boosted to 0.99
#   - PCHIP trajectories are projected back into the stage circle if interpolation escapes
#   - DBAP rolloff exponent k is exposed as a musical GUI control
#   - Stage release binding preserves the internal drag-release handler
#
# Changelog v1.1 (2026):
#   - Smooth (PCHIP) interpolation option for curved, non-jerky motion
#     (GUI toggle; shape-preserving, so the path stays in the stage)
#   - Trajectory presets: Circle, Spiral, Figure-8, with rotation count
#   - New points take the midpoint of the largest time gap, so adding
#     points spreads them across the duration (was: piled near the end)
#   - save_audio normalizes before the safety clip (was clip-then-norm)
#   - Removed dead label-position lines in speaker drawing
# ============================================================

import sys
import os
import math
import tkinter as tk
from tkinter import ttk, messagebox, simpledialog
import numpy as np
import soundfile as sf

# ─────────────────────────────────────────────────────────────
# SPEAKER LAYOUT
# ─────────────────────────────────────────────────────────────
# Each entry: (label, angle_degrees, radius)
# angle 0° = top, increases clockwise (like a clock face)
# Radius 1.0 = edge of the stage circle.
# Easy to change: replace this list with any arrangement.

def make_ring_speakers(n, radius=1.0, offset_deg=0.0):
    """N speakers equally spaced around a circle."""
    spks = []
    for i in range(n):
        angle = offset_deg + i * (360.0 / n)
        label = f"Sp{i+1}"
        spks.append((label, angle % 360.0, radius))
    return spks

# Default layout — change n here to switch between 4 / 8 / etc.
DEFAULT_SPEAKERS = make_ring_speakers(8, radius=1.0, offset_deg=0.0)

# ─────────────────────────────────────────────────────────────
# DBAP PANNING
# ─────────────────────────────────────────────────────────────
DBAP_K   = 1.0    # distance rolloff exponent
DBAP_EPS = 0.02   # prevents div-by-zero when source == speaker

def dbap_gains(sx, sy, speakers, k=DBAP_K):
    """
    Compute DBAP gain for each speaker.

    Parameters
    ----------
    sx, sy   : source position in unit-circle space
    speakers : list of (label, angle_deg, radius)

    Returns
    -------
    gains : np.ndarray, shape (n_spk,), L2/power-normalised
    """
    n = len(speakers)
    raw = np.zeros(n, dtype=np.float64)
    for i, (_, angle_deg, radius) in enumerate(speakers):
        rad = math.radians(angle_deg)
        # angle 0 = top → x=sin, y=cos
        spk_x = radius * math.sin(rad)
        spk_y = radius * math.cos(rad)
        dist  = math.sqrt((sx - spk_x)**2 + (sy - spk_y)**2)
        dist  = max(dist, DBAP_EPS)
        raw[i] = 1.0 / (dist ** float(k))

    # L2/power normalisation: sqrt(sum g^2) = 1
    denom = math.sqrt(np.sum(raw**2)) + 1e-12
    return (raw / denom).astype(np.float32)


def dbap_gains_array(sx_arr, sy_arr, speakers, k=DBAP_K):
    """
    Vectorised DBAP over an array of source positions.

    Returns
    -------
    gains : np.ndarray, shape (n_samples, n_speakers)
    """
    n_samples = len(sx_arr)
    n_spk     = len(speakers)

    # Speaker positions as arrays
    spk_x = np.array([r * math.sin(math.radians(a))
                       for _, a, r in speakers], dtype=np.float64)
    spk_y = np.array([r * math.cos(math.radians(a))
                       for _, a, r in speakers], dtype=np.float64)

    # Distances: (n_samples, n_spk)
    dx   = sx_arr[:, np.newaxis] - spk_x[np.newaxis, :]
    dy   = sy_arr[:, np.newaxis] - spk_y[np.newaxis, :]
    dist = np.sqrt(dx**2 + dy**2)
    dist = np.maximum(dist, DBAP_EPS)

    raw   = 1.0 / (dist ** float(k))                 # (n_samples, n_spk)
    denom = np.sqrt(np.sum(raw**2, axis=1, keepdims=True)) + 1e-12
    return (raw / denom).astype(np.float32)


# ─────────────────────────────────────────────────────────────
# TRAJECTORY INTERPOLATION
# ─────────────────────────────────────────────────────────────
def make_trajectory_evaluator(traj, smooth=True):
    """Create a reusable evaluator for source position at arbitrary times."""
    pts = sorted(traj, key=lambda p: p[0])
    if not pts:
        raise ValueError("trajectory must contain at least one point")

    ts = np.array([p[0] for p in pts], dtype=np.float64)
    xs = np.array([p[1] for p in pts], dtype=np.float64)
    ys = np.array([p[2] for p in pts], dtype=np.float64)

    keep = np.concatenate(([True], np.diff(ts) > 1e-9))
    ts, xs, ys = ts[keep], xs[keep], ys[keep]

    if smooth and len(ts) >= 3:
        from scipy.interpolate import PchipInterpolator
        fx = PchipInterpolator(ts, xs)
        fy = PchipInterpolator(ts, ys)

        def raw_eval(t_ax):
            return fx(t_ax), fy(t_ax)
    else:
        def raw_eval(t_ax):
            return np.interp(t_ax, ts, xs), np.interp(t_ax, ts, ys)

    def evaluate(t_ax):
        t_ax = np.asarray(t_ax, dtype=np.float64)
        if len(ts) >= 2:
            t_ax = np.clip(t_ax, ts[0], ts[-1])
        sx, sy = raw_eval(t_ax)
        sx = np.asarray(sx, dtype=np.float64)
        sy = np.asarray(sy, dtype=np.float64)

        # PCHIP is shape-preserving per coordinate, not in 2D radius.
        # Project only interpolated samples that escape the editable unit circle.
        radius = np.sqrt(sx * sx + sy * sy)
        outside = radius > 1.0
        if np.any(outside):
            sx = sx.copy(); sy = sy.copy()
            sx[outside] /= radius[outside]
            sy[outside] /= radius[outside]
        return sx.astype(np.float32), sy.astype(np.float32)

    return evaluate


def interp_trajectory(traj, n_samples, sr, smooth=True):
    """Interpolate trajectory points over audio sample times."""
    evaluate = make_trajectory_evaluator(traj, smooth=smooth)
    t_ax = np.arange(n_samples, dtype=np.float64) / float(sr)
    return evaluate(t_ax)


# ──────────────────────────────
# TRAJECTORY SHAPE PRESETS
# ──────────────────────────────
def _preset_points(duration, n, fn):
    """Build a [t,x,y] trajectory; fn(frac)->(x,y) with frac in [0,1].
    Times are evenly spaced; first/last act as the t=0 / t=dur anchors."""
    n = max(8, n)
    traj = []
    for i in range(n):
        frac = i / (n - 1)
        x, y = fn(frac)
        traj.append([frac * duration, float(x), float(y)])
    return traj


def preset_circle(duration, rotations=1, radius=0.8):
    def fn(frac):
        ang = 2.0 * math.pi * rotations * frac
        return radius * math.sin(ang), radius * math.cos(ang)
    return _preset_points(duration, 12 * rotations + 1, fn)


def preset_spiral(duration, rotations=2, radius=0.85):
    def fn(frac):
        ang = 2.0 * math.pi * rotations * frac
        r = radius * frac
        return r * math.sin(ang), r * math.cos(ang)
    return _preset_points(duration, 12 * rotations + 1, fn)


def preset_figure8(duration, rotations=1, radius=0.85):
    def fn(frac):
        ang = 2.0 * math.pi * rotations * frac
        return radius * math.sin(ang), radius * math.sin(2.0 * ang) / 2.0
    return _preset_points(duration, 16 * rotations + 1, fn)


# ─────────────────────────────────────────────────────────────
# AUDIO I/O
# ─────────────────────────────────────────────────────────────
def load_audio(path):
    audio, sr = sf.read(path, always_2d=True, dtype="float32")
    audio = np.nan_to_num(audio, nan=0.0, posinf=0.0, neginf=0.0)
    return audio.astype(np.float32, copy=False), int(sr)


def select_source_channel(audio):
    """Return one real input channel for single-source spatial rendering.

    Using a real channel rather than a fold-down avoids anti-phase cancellation.
    Returns (mono, channel_index_zero_based, per_channel_rms).
    """
    audio = np.asarray(audio, dtype=np.float32)
    if audio.ndim != 2 or audio.shape[1] < 1:
        raise ValueError("audio must have shape (samples, channels)")
    rms = np.sqrt(np.mean(audio.astype(np.float64) ** 2, axis=0))
    idx = int(np.argmax(rms))
    return audio[:, idx].astype(np.float32, copy=True), idx, rms


def save_audio(path, audio, sr, safety_peak=0.99):
    """Write float WAV with attenuation-only peak safety.

    DBAP power normalisation already prevents panning from adding gain, so quiet
    material must not be normalised upward merely because it passed the panner.
    """
    audio = np.asarray(audio, dtype=np.float32)
    audio = np.nan_to_num(audio, nan=0.0, posinf=0.0, neginf=0.0)
    peak = float(np.max(np.abs(audio))) if audio.size else 0.0
    if peak > float(safety_peak) and peak > 1e-12:
        audio = audio * (float(safety_peak) / peak)
    audio = np.clip(audio, -1.0, 1.0).astype(np.float32, copy=False)
    sf.write(path, audio, sr, subtype="FLOAT")


# ─────────────────────────────────────────────────────────────
# SPATIAL RENDER
# ─────────────────────────────────────────────────────────────
def make_stereo_monitor_matrix(speakers):
    """Project a circular loudspeaker ring to an equal-power stereo monitor.

    This is only a monitoring fallback when the default device cannot expose
    the requested N output channels. Front/back location cannot be represented
    faithfully in ordinary stereo; left/right motion and relative concentration
    are preserved as a useful audition cue.
    """
    if len(speakers) < 1:
        raise ValueError("at least one speaker is required")
    rows = []
    for _, angle_deg, radius in speakers:
        x, _ = spk_unit_pos(angle_deg, radius)
        pan = float(np.clip((x + 1.0) * 0.5, 0.0, 1.0))
        rows.append([math.cos(pan * math.pi * 0.5),
                     math.sin(pan * math.pi * 0.5)])
    return np.asarray(rows, dtype=np.float32)


def gains_to_stereo_monitor(gains, speakers):
    """Fold speaker gains to stereo and restore unit L2 power per frame."""
    gains = np.asarray(gains, dtype=np.float32)
    if gains.ndim != 2 or gains.shape[1] != len(speakers):
        raise ValueError("gains must have shape (frames, number_of_speakers)")
    matrix = make_stereo_monitor_matrix(speakers)
    stereo = gains @ matrix
    norm = np.sqrt(np.sum(stereo.astype(np.float64) ** 2, axis=1, keepdims=True))
    valid = norm[:, 0] > 1e-12
    if np.any(valid):
        stereo = stereo.copy()
        stereo[valid] /= norm[valid].astype(np.float32)
    if np.any(~valid):
        stereo = stereo.copy()
        stereo[~valid] = np.float32(1.0 / math.sqrt(2.0))
    return stereo.astype(np.float32, copy=False)


def render_audition_block(mono, sr, start, frames, evaluate, speakers,
                          k=DBAP_K, stereo_monitor=False,
                          safety_gain=1.0):
    """Render one block for real-time audition without mutating source data."""
    n = len(mono)
    stop = min(n, start + int(frames))
    actual = max(0, stop - start)
    n_out = 2 if stereo_monitor else len(speakers)
    out = np.zeros((int(frames), n_out), dtype=np.float32)
    if actual < 1:
        return out, 0
    t_ax = np.arange(start, stop, dtype=np.float64) / float(sr)
    sx, sy = evaluate(t_ax)
    gains = dbap_gains_array(sx.astype(np.float64), sy.astype(np.float64),
                             speakers, k=k)
    if stereo_monitor:
        gains = gains_to_stereo_monitor(gains, speakers)
    out[:actual] = mono[start:stop, np.newaxis] * gains * np.float32(safety_gain)
    return out, actual


def render_spatial(mono, sr, traj, speakers, k=DBAP_K):
    """
    mono     : (n_samples,) float32
    traj     : list of [time, x, y]
    speakers : list of (label, angle_deg, radius)

    Returns  : (n_samples, n_spk) float32
    """
    n     = len(mono)
    n_spk = len(speakers)

    sx, sy = interp_trajectory(traj, n, sr)
    gains  = dbap_gains_array(sx.astype(np.float64),
                               sy.astype(np.float64), speakers, k=k)  # (n, n_spk)
    out = mono[:, np.newaxis] * gains                             # (n, n_spk)
    return out.astype(np.float32)


def render_spatial_to_file(mono, sr, traj, speakers, path, k=DBAP_K,
                           smooth=True, block_samples=65536,
                           safety_peak=0.99, progress_cb=None):
    """Stream DBAP rendering to a FLOAT WAV without full samples×speakers RAM.

    Returns a dictionary with peak_before_safety, applied_gain and blocks.
    The first pass writes the mathematically exact DBAP output. If its peak is
    above safety_peak, a second streaming pass applies one global attenuation.
    """
    mono = np.asarray(mono, dtype=np.float32).reshape(-1)
    n = len(mono)
    n_spk = len(speakers)
    if n_spk < 1:
        raise ValueError("at least one speaker is required")
    if block_samples < 1024:
        block_samples = 1024

    evaluate = make_trajectory_evaluator(traj, smooth=smooth)
    tmp_path = path + ".rendering.tmp.wav"
    if os.path.exists(tmp_path):
        os.remove(tmp_path)

    peak = 0.0
    blocks = max(1, (n + block_samples - 1) // block_samples)
    try:
        with sf.SoundFile(tmp_path, mode="w", samplerate=int(sr),
                          channels=n_spk, format="WAV", subtype="FLOAT") as out_f:
            for bi, start in enumerate(range(0, n, block_samples)):
                stop = min(n, start + block_samples)
                t_ax = np.arange(start, stop, dtype=np.float64) / float(sr)
                sx, sy = evaluate(t_ax)
                gains = dbap_gains_array(sx.astype(np.float64),
                                         sy.astype(np.float64), speakers, k=k)
                block = mono[start:stop, np.newaxis] * gains
                if block.size:
                    peak = max(peak, float(np.max(np.abs(block))))
                out_f.write(block.astype(np.float32, copy=False))
                if progress_cb is not None:
                    progress_cb((bi + 1) / blocks)

        scale = 1.0
        if peak > float(safety_peak) and peak > 1e-12:
            scale = float(safety_peak) / peak
            with sf.SoundFile(tmp_path, mode="r") as in_f, \
                 sf.SoundFile(path, mode="w", samplerate=int(sr), channels=n_spk,
                              format="WAV", subtype="FLOAT") as out_f:
                while True:
                    block = in_f.read(block_samples, dtype="float32", always_2d=True)
                    if len(block) == 0:
                        break
                    out_f.write((block * scale).astype(np.float32, copy=False))
            os.remove(tmp_path)
        else:
            os.replace(tmp_path, path)

        return {
            "peak_before_safety": peak,
            "applied_gain": scale,
            "blocks": blocks,
        }
    except Exception:
        try:
            if os.path.exists(tmp_path):
                os.remove(tmp_path)
        except Exception:
            pass
        raise


# ─────────────────────────────────────────────────────────────
# STAGE CANVAS — 2D circular editor
# ─────────────────────────────────────────────────────────────
STAGE_SIZE  = 420          # canvas pixel size (square)
STAGE_PAD   = 30           # margin around circle
STAGE_R     = (STAGE_SIZE - 2 * STAGE_PAD) // 2    # circle radius in pixels
STAGE_CX    = STAGE_SIZE // 2
STAGE_CY    = STAGE_SIZE // 2
POINT_R     = 7            # radius of trajectory points
SPK_R       = 9            # radius of speaker markers
TRAJ_COLOR  = "#7ec8e3"
ANCHOR_COL  = "#ffaa44"
POINT_COL   = "#7ec8e3"
SPK_COL     = "#e07ec8"
CENTER_COL  = "#404060"


def stage_to_unit(px, py):
    """Canvas pixel → unit circle coords (-1..+1)."""
    x = (px - STAGE_CX) / STAGE_R
    y = -(py - STAGE_CY) / STAGE_R          # y-axis flipped (up = positive)
    return x, y


def unit_to_stage(x, y):
    """Unit circle coords → canvas pixels."""
    px = STAGE_CX + x * STAGE_R
    py = STAGE_CY - y * STAGE_R
    return px, py


def spk_unit_pos(angle_deg, radius):
    """Speaker unit position from angle (0=top, CW) and radius."""
    rad = math.radians(angle_deg)
    return radius * math.sin(rad), radius * math.cos(rad)


class StageCanvas(tk.Canvas):
    """
    Interactive 2D circular stage.

    Stores trajectory as list of [time, x, y].
    Always has two anchor points: t=0 and t=duration.

    Left-click empty area  → add point (time assigned sequentially)
    Left-click+drag point  → move point
    Right-click point      → delete (anchors protected)
    Double-click point     → edit time value
    """

    def __init__(self, parent, duration, speakers, **kwargs):
        super().__init__(parent,
                         width=STAGE_SIZE, height=STAGE_SIZE,
                         bg="#0e0e1a", highlightthickness=0, **kwargs)
        self.duration  = duration
        self.speakers  = speakers
        self.smooth    = True

        # Default trajectory: centre at t=0, centre at t=duration
        self.traj = [
            [0.0, 0.0, 0.0],
            [duration, 0.0, 0.0],
        ]

        self._drag_idx = None

        self.bind("<ButtonPress-1>",   self._on_press)
        self.bind("<B1-Motion>",       self._on_drag)
        self.bind("<ButtonRelease-1>", self._on_release)
        self.bind("<ButtonPress-3>",   self._on_right)
        self.bind("<Double-Button-1>", self._on_double)

        self.draw()

    # ── helpers ───────────────────────────────────────────────

    def _hit(self, px, py):
        """Return index of trajectory point near (px,py), or None."""
        for i, (t, x, y) in enumerate(self.traj):
            spx, spy = unit_to_stage(x, y)
            if (px - spx)**2 + (py - spy)**2 <= (POINT_R * 2.2)**2:
                return i
        return None

    def _inside_stage(self, px, py):
        return (px - STAGE_CX)**2 + (py - STAGE_CY)**2 <= STAGE_R**2

    def _clamp_to_circle(self, px, py):
        """Clamp pixel position to be within the stage circle."""
        dx, dy = px - STAGE_CX, py - STAGE_CY
        d = math.sqrt(dx**2 + dy**2)
        if d > STAGE_R:
            scale = STAGE_R / d
            px = STAGE_CX + dx * scale
            py = STAGE_CY + dy * scale
        return px, py

    # ── mouse handlers ─────────────────────────────────────────

    def _on_press(self, e):
        idx = self._hit(e.x, e.y)
        if idx is not None:
            self._drag_idx = idx
            return
        if self._inside_stage(e.x, e.y):
            x, y = stage_to_unit(e.x, e.y)
            # Place the new point at the midpoint of the largest time
            # gap, so adding points spreads them across the whole
            # duration instead of piling up near the end.
            pts = sorted(self.traj, key=lambda p: p[0])
            best_gap = -1.0
            t_new = self.duration / 2.0
            for k in range(len(pts) - 1):
                gap = pts[k + 1][0] - pts[k][0]
                if gap > best_gap:
                    best_gap = gap
                    t_new = (pts[k][0] + pts[k + 1][0]) / 2.0
            new_pt = [t_new, x, y]
            self.traj.append(new_pt)
            self.traj.sort(key=lambda p: p[0])
            self._drag_idx = next(i for i, p in enumerate(self.traj)
                                  if p is new_pt)
            self.draw()

    def _on_drag(self, e):
        if self._drag_idx is None:
            return
        px, py = self._clamp_to_circle(e.x, e.y)
        x, y   = stage_to_unit(px, py)
        self.traj[self._drag_idx][1] = x
        self.traj[self._drag_idx][2] = y
        self.draw()

    def _on_release(self, e):
        self._drag_idx = None

    def _on_right(self, e):
        idx = self._hit(e.x, e.y)
        n   = len(self.traj)
        if idx is None or idx == 0 or idx == n - 1:
            return                      # protect anchors
        self.traj.pop(idx)
        self.draw()

    def _on_double(self, e):
        idx = self._hit(e.x, e.y)
        if idx is None:
            return
        pt    = self.traj[idx]
        t_min = 0.0 if idx == 0 else self.traj[idx - 1][0] + 0.001
        t_max = self.duration if idx == len(self.traj) - 1 \
                else self.traj[idx + 1][0] - 0.001
        new_t = simpledialog.askfloat(
            "Edit time",
            f"Time for point {idx}  (range {t_min:.3f} – {t_max:.3f} s):",
            initialvalue=round(pt[0], 3),
            minvalue=t_min,
            maxvalue=t_max,
            parent=self,
        )
        if new_t is not None:
            self.traj[idx][0] = new_t
            self.traj.sort(key=lambda p: p[0])
            self.draw()

    # ── drawing ───────────────────────────────────────────────

    def draw(self):
        self.delete("all")
        self._draw_background()
        self._draw_speakers()
        self._draw_trajectory()
        self._draw_points()

    def _draw_background(self):
        # Outer stage circle
        self.create_oval(
            STAGE_CX - STAGE_R, STAGE_CY - STAGE_R,
            STAGE_CX + STAGE_R, STAGE_CY + STAGE_R,
            outline="#2a2a5a", fill="#0a0a18", width=2,
        )
        # Concentric guide rings
        for frac in (0.33, 0.66, 1.0):
            r = int(STAGE_R * frac)
            self.create_oval(
                STAGE_CX - r, STAGE_CY - r,
                STAGE_CX + r, STAGE_CY + r,
                outline="#1e1e40", width=1,
            )
        # Cross-hairs
        self.create_line(STAGE_CX - STAGE_R, STAGE_CY,
                         STAGE_CX + STAGE_R, STAGE_CY,
                         fill="#1e1e40", dash=(3, 6))
        self.create_line(STAGE_CX, STAGE_CY - STAGE_R,
                         STAGE_CX, STAGE_CY + STAGE_R,
                         fill="#1e1e40", dash=(3, 6))
        # Centre dot
        cr = 4
        self.create_oval(STAGE_CX - cr, STAGE_CY - cr,
                         STAGE_CX + cr, STAGE_CY + cr,
                         fill=CENTER_COL, outline="")
        # Cardinal labels (outside circle)
        off = STAGE_R + 16
        for txt, dx, dy in [("F", 0, -off), ("B", 0, off),
                             ("L", -off, 0), ("R", off, 0)]:
            self.create_text(STAGE_CX + dx, STAGE_CY + dy,
                             text=txt, fill="#404070",
                             font=("Helvetica", 9, "bold"))

    def _draw_speakers(self):
        for label, angle_deg, radius in self.speakers:
            ux, uy = spk_unit_pos(angle_deg, radius)
            px, py = unit_to_stage(ux, uy)
            r = SPK_R
            self.create_oval(px - r, py - r, px + r, py + r,
                             fill="#2a1a3a", outline=SPK_COL, width=2)
            # Label just outside the speaker dot, in pixel space
            nx, ny = ux / max(abs(ux), abs(uy), 0.01), uy / max(abs(ux), abs(uy), 0.01)
            lx2 = px + nx * (SPK_R + 10)
            ly2 = py - ny * (SPK_R + 10)
            self.create_text(lx2, ly2, text=label,
                             fill=SPK_COL, font=("Courier", 8, "bold"))

    def _draw_trajectory(self):
        if len(self.traj) < 2:
            return
        # Draw the path exactly as it will be rendered (linear or PCHIP)
        # so the canvas is WYSIWYG with the motion.
        n_draw  = 160
        sr_draw = n_draw / max(self.duration, 1e-6)
        sx, sy  = interp_trajectory(self.traj, n_draw, sr_draw,
                                    smooth=self.smooth)
        coords = []
        for i in range(n_draw):
            px, py = unit_to_stage(sx[i], sy[i])
            coords += [px, py]
        self.create_line(*coords, fill=TRAJ_COLOR, width=2,
                         smooth=False, arrow=tk.LAST,
                         arrowshape=(10, 12, 4))

    def _draw_points(self):
        n = len(self.traj)
        show_labels = n <= 10
        for i, (t, x, y) in enumerate(self.traj):
            px, py = unit_to_stage(x, y)
            is_anchor = (i == 0 or i == n - 1)
            col = ANCHOR_COL if is_anchor else POINT_COL
            r   = POINT_R + (2 if is_anchor else 0)
            self.create_oval(px - r, py - r, px + r, py + r,
                             fill=col, outline="#ffffff", width=1)
            if show_labels or is_anchor:
                self.create_text(px, py - r - 6,
                                 text=f"{t:.2f}s",
                                 fill="#ccccee", font=("Courier", 7))

    # ── public API ────────────────────────────────────────────

    def reset(self):
        self.traj = [
            [0.0, 0.0, 0.0],
            [self.duration, 0.0, 0.0],
        ]
        self.draw()

    def get_trajectory(self):
        return [list(p) for p in sorted(self.traj, key=lambda p: p[0])]


# ─────────────────────────────────────────────────────────────
# TIME RULER — shows trajectory time-points on a horizontal bar
# ─────────────────────────────────────────────────────────────
RULER_W  = STAGE_SIZE
RULER_H  = 48
RULER_PL = 10
RULER_PR = 10
RULER_PW = RULER_W - RULER_PL - RULER_PR


class TimeRuler(tk.Canvas):
    """
    Read-only horizontal ruler that mirrors time positions of
    trajectory points, so the user can see the temporal spread.
    """
    def __init__(self, parent, duration, **kwargs):
        super().__init__(parent, width=RULER_W, height=RULER_H,
                         bg="#0e0e1a", highlightthickness=0, **kwargs)
        self.duration = duration
        self.traj_ref = None

    def update_from_traj(self, traj):
        self.traj_ref = traj
        self.draw()

    def _t2x(self, t):
        return RULER_PL + (t / self.duration) * RULER_PW

    def draw(self):
        self.delete("all")
        # Axis line
        y = RULER_H // 2
        self.create_line(RULER_PL, y, RULER_PL + RULER_PW, y,
                         fill="#2a2a5a", width=2)
        # Time ticks
        n_ticks = min(10, max(4, int(self.duration)))
        step    = self.duration / n_ticks
        t = 0.0
        while t <= self.duration + 0.001:
            x = self._t2x(t)
            self.create_line(x, y - 6, x, y + 6, fill="#404060")
            self.create_text(x, y + 14,
                             text=f"{t:.1f}",
                             fill="#505080", font=("Courier", 7))
            t += step
        # Trajectory points
        if self.traj_ref:
            n = len(self.traj_ref)
            for i, (t, _, _) in enumerate(self.traj_ref):
                x   = self._t2x(t)
                col = ANCHOR_COL if (i == 0 or i == n - 1) else TRAJ_COLOR
                self.create_line(x, y - 10, x, y + 10, fill=col, width=2)
                self.create_text(x, y - 14,
                                 text=f"{t:.2f}",
                                 fill=col, font=("Courier", 7))


# ─────────────────────────────────────────────────────────────
# MAIN APP
# ─────────────────────────────────────────────────────────────
class SpatialPannerApp:

    def __init__(self, input_path, output_path):
        self.input_path  = input_path
        self.output_path = output_path
        self.cancelled   = True
        self.speakers    = list(DEFAULT_SPEAKERS)

        self.audio, self.sr = load_audio(input_path)
        self.duration       = self.audio.shape[0] / self.sr
        n_ch                = self.audio.shape[1]
        ch_label            = "mono" if n_ch == 1 else f"{n_ch}-ch"

        # Spatial Panner is a single-source renderer. For multichannel inputs,
        # use the strongest real channel rather than a phase-cancelling average.
        self.mono, self.source_channel, self.channel_rms = select_source_channel(self.audio)

        # ── Window ────────────────────────────────────────────
        self.root = tk.Tk()
        self.root.title("Spatial Panner — Praat AudioTools")
        self.root.resizable(False, False)
        self.root.configure(bg="#12121e")
        self.root.protocol("WM_DELETE_WINDOW", self._on_cancel)
        self.smooth_var = tk.BooleanVar(value=True)
        self.rot_var    = tk.StringVar(value="1")
        self.dbap_k_var = tk.StringVar(value=str(DBAP_K))
        self.audio_device_var = tk.StringVar(value="")
        self.audio_device_info_var = tk.StringVar(value="Audition device: not scanned")
        self._audio_devices = []
        self._audio_device_map = {}
        self._audition_stream = None
        self._audition_pos = 0
        self._audition_sd = None
        self._audition_mode = ""
        self.dbap_k_var.trace_add("write", self._on_dbap_k_changed)

        # ── Header ────────────────────────────────────────────
        hdr = tk.Frame(self.root, bg="#12121e", pady=6)
        hdr.pack(fill="x", padx=12)
        fname = os.path.basename(input_path)
        tk.Label(hdr,
                 text=f"  {fname}   {self.duration:.2f}s   "
                      f"{self.sr}Hz   {ch_label}   "
                      f"→ {len(self.speakers)}-ch output",
                 bg="#12121e", fg="#9090c0",
                 font=("Courier", 10)).pack(side="left")
        tk.Label(hdr,
                 text="L-click: add/drag   R-click: delete   "
                      "Double-click: edit time",
                 bg="#12121e", fg="#505070",
                 font=("Helvetica", 9)).pack(side="right")

        # ── Main body: stage + info panel ─────────────────────
        body = tk.Frame(self.root, bg="#12121e")
        body.pack(padx=10, pady=4)

        # Stage canvas
        stage_frame = tk.Frame(body, bg="#1a1a2e",
                                bd=1, relief="sunken")
        stage_frame.pack(side="left", padx=(0, 8))
        self.stage = StageCanvas(stage_frame, self.duration,
                                 self.speakers)
        self.stage.pack()
        self.stage.bind("<ButtonRelease-1>", self._on_stage_change, add="+")
        self.stage.bind("<ButtonRelease-3>", self._on_stage_change)

        # Time ruler below stage
        self.ruler = TimeRuler(stage_frame, self.duration)
        self.ruler.pack(pady=(2, 0))
        self.ruler.update_from_traj(self.stage.get_trajectory())

        # Right info panel
        info_frame = tk.Frame(body, bg="#12121e", width=300)
        info_frame.pack(side="left", fill="y")
        info_frame.pack_propagate(False)

        tk.Label(info_frame, text="Speaker Layout",
                 bg="#12121e", fg=SPK_COL,
                 font=("Helvetica", 10, "bold")).pack(anchor="w", pady=(0, 4))

        self.spk_listbox = tk.Listbox(
            info_frame,
            bg="#0e0e1a", fg=SPK_COL,
            selectbackground="#2a1a3a",
            font=("Courier", 9),
            height=min(len(self.speakers), 10),
            width=22,
            highlightthickness=0,
            bd=0,
        )
        self.spk_listbox.pack(fill="x")
        self._refresh_spk_list()

        spk_btn = tk.Frame(info_frame, bg="#12121e")
        spk_btn.pack(fill="x", pady=4)
        for lbl, n in [("4 spk", 4), ("6 spk", 6), ("8 spk", 8)]:
            tk.Button(spk_btn, text=lbl,
                      command=lambda n_=n: self._set_speakers(n_),
                      bg="#2a1a3a", fg="#c0a0e0",
                      font=("Helvetica", 8), relief="flat",
                      padx=4, pady=2).pack(side="left", padx=2)

        # ── Audition output device ────────────────────────────
        tk.Label(info_frame, text="Audition Output",
                 bg="#12121e", fg="#9ab7d8",
                 font=("Helvetica", 10, "bold")).pack(anchor="w",
                                                       pady=(10, 4))
        dev_row = tk.Frame(info_frame, bg="#12121e")
        dev_row.pack(fill="x")
        self.audio_device_combo = ttk.Combobox(
            dev_row, textvariable=self.audio_device_var,
            state="readonly", width=32, font=("Courier", 8))
        self.audio_device_combo.pack(side="left", fill="x", expand=True)
        self.audio_device_combo.bind("<<ComboboxSelected>>",
                                     self._on_audio_device_changed)
        tk.Button(dev_row, text="Refresh",
                  command=self._refresh_audio_devices,
                  bg="#24384d", fg="#b8d0e8",
                  activebackground="#31506d",
                  font=("Helvetica", 8), relief="flat",
                  padx=5, pady=2).pack(side="left", padx=(4, 0))
        tk.Label(info_frame, textvariable=self.audio_device_info_var,
                 bg="#12121e", fg="#607b98",
                 justify="left", anchor="w", wraplength=285,
                 font=("Courier", 7)).pack(fill="x", anchor="w", pady=(3, 0))

        # ── Trajectory shape presets ────────────────────
        tk.Label(info_frame, text="Shape Presets",
                 bg="#12121e", fg="#c0a0e0",
                 font=("Helvetica", 10, "bold")).pack(anchor="w",
                                                       pady=(12, 4))
        rot_frame = tk.Frame(info_frame, bg="#12121e")
        rot_frame.pack(fill="x")
        tk.Label(rot_frame, text="Rotations:",
                 bg="#12121e", fg="#9090c0",
                 font=("Courier", 9)).pack(side="left")
        tk.Entry(rot_frame, textvariable=self.rot_var, width=4,
                 bg="#0e0e1a", fg="#c0c0e0", relief="flat",
                 highlightthickness=1, highlightbackground="#2a2a5a",
                 font=("Courier", 9)).pack(side="left", padx=4)
        shape_btn = tk.Frame(info_frame, bg="#12121e")
        shape_btn.pack(fill="x", pady=4)
        for lbl, kind in [("Circle", "circle"),
                          ("Spiral", "spiral"),
                          ("Fig-8", "figure8")]:
            tk.Button(shape_btn, text=lbl,
                      command=lambda k_=kind: self._apply_preset(k_),
                      bg="#2a1a3a", fg="#c0a0e0",
                      font=("Helvetica", 8), relief="flat",
                      padx=4, pady=2).pack(side="left", padx=2)

        tk.Checkbutton(info_frame, text="Smooth motion (PCHIP)",
                       variable=self.smooth_var,
                       command=self._on_smooth_toggle,
                       bg="#12121e", fg="#9090c0", selectcolor="#0e0e1a",
                       activebackground="#12121e",
                       activeforeground="#c0c0e0",
                       font=("Helvetica", 9)).pack(anchor="w", pady=(6, 0))

        tk.Label(info_frame, text="Trajectory Points",
                 bg="#12121e", fg=TRAJ_COLOR,
                 font=("Helvetica", 10, "bold")).pack(anchor="w",
                                                       pady=(12, 4))
        self.traj_info = tk.Text(
            info_frame,
            bg="#0e0e1a", fg=TRAJ_COLOR,
            font=("Courier", 8),
            height=12, width=22,
            highlightthickness=0, bd=0,
            state="disabled",
        )
        self.traj_info.pack(fill="x")
        self._refresh_traj_info()

        dbap_frame = tk.Frame(info_frame, bg="#12121e")
        dbap_frame.pack(fill="x", pady=(8, 0))
        tk.Label(dbap_frame, text="DBAP rolloff k:",
                 bg="#12121e", fg="#7070a0",
                 font=("Courier", 8)).pack(side="left")
        tk.Entry(dbap_frame, textvariable=self.dbap_k_var, width=5,
                 bg="#0e0e1a", fg="#c0c0e0", relief="flat",
                 highlightthickness=1, highlightbackground="#2a2a5a",
                 font=("Courier", 8)).pack(side="left", padx=4)
        tk.Label(info_frame,
                 text=f"ε={DBAP_EPS}  power norm",
                 bg="#12121e", fg="#505080",
                 font=("Courier", 8)).pack(anchor="w")
        if n_ch > 1:
            tk.Label(info_frame,
                     text=f"source: input ch {self.source_channel + 1}/{n_ch}",
                     bg="#12121e", fg="#505080",
                     font=("Courier", 8)).pack(anchor="w")

        # ── Status + progress ─────────────────────────────────
        self.status_var = tk.StringVar(value="Ready.")
        tk.Label(self.root, textvariable=self.status_var,
                 bg="#12121e", fg="#606090",
                 font=("Courier", 9), anchor="w").pack(
                     fill="x", padx=14, pady=2)

        self.progress = ttk.Progressbar(self.root, mode="determinate",
                                         length=STAGE_SIZE + 220)
        self.progress.pack(padx=10, pady=(0, 2))

        # ── Buttons ───────────────────────────────────────────
        btn_frame = tk.Frame(self.root, bg="#12121e", pady=7)
        btn_frame.pack()

        style_btn = dict(relief="flat", padx=10, pady=4,
                         font=("Helvetica", 10))
        tk.Button(btn_frame, text=" Reset ",
                  command=self._on_reset,
                  bg="#2a2a4e", fg="#c0c0e0",
                  activebackground="#3a3a6a",
                  **style_btn).pack(side="left", padx=8)
        tk.Button(btn_frame, text=" Cancel ",
                  command=self._on_cancel,
                  bg="#4e2a2a", fg="#e0c0c0",
                  activebackground="#6a3a3a",
                  **style_btn).pack(side="left", padx=8)
        self.audition_button = tk.Button(
                  btn_frame, text="  ▶  Audition  ",
                  command=self._on_audition,
                  bg="#2a3f5e", fg="#c0d8f0",
                  activebackground="#34577d",
                  font=("Helvetica", 10, "bold"),
                  relief="flat", padx=11, pady=4)
        self.audition_button.pack(side="left", padx=8)
        tk.Button(btn_frame, text="  ✓  Apply  ",
                  command=self._on_apply,
                  bg="#2a4e2a", fg="#c0e0c0",
                  activebackground="#3a6a3a",
                  font=("Helvetica", 11, "bold"),
                  relief="flat", padx=14, pady=4).pack(side="left", padx=8)

        # Populate the optional playback-device list after all widgets exist.
        self.root.after(20, self._refresh_audio_devices)

    # ── event handlers ────────────────────────────────────────

    def _on_stage_change(self, e=None):
        if self._audition_stream is not None:
            self._stop_audition(status="Audition stopped: trajectory changed.")
        traj = self.stage.get_trajectory()
        self.ruler.update_from_traj(traj)
        self._refresh_traj_info()

    def _refresh_spk_list(self):
        self.spk_listbox.delete(0, "end")
        for label, angle, radius in self.speakers:
            self.spk_listbox.insert(
                "end", f"{label:>4}  {angle:>5.1f}°  r={radius:.2f}"
            )

    def _refresh_traj_info(self):
        traj = self.stage.get_trajectory()
        self.traj_info.configure(state="normal")
        self.traj_info.delete("1.0", "end")
        for i, (t, x, y) in enumerate(traj):
            marker = "⚓" if (i == 0 or i == len(traj) - 1) else " •"
            self.traj_info.insert(
                "end",
                f"{marker} {t:5.2f}s  ({x:+.2f},{y:+.2f})\n"
            )
        self.traj_info.configure(state="disabled")

    def _set_speakers(self, n):
        if self._audition_stream is not None:
            self._stop_audition(status="Audition stopped: speaker layout changed.")
        self.speakers = make_ring_speakers(n)
        self.stage.speakers = self.speakers
        self.stage.draw()
        self._refresh_spk_list()
        # Update header
        self.status_var.set(
            f"Speaker layout changed to {n} speakers."
        )

    def _on_smooth_toggle(self):
        if self._audition_stream is not None:
            self._stop_audition(status="Audition stopped: interpolation changed.")
        self.stage.smooth = self.smooth_var.get()
        self.stage.draw()
        self._on_stage_change()

    def _apply_preset(self, kind):
        if self._audition_stream is not None:
            self._stop_audition(status="Audition stopped: preset changed.")
        try:
            rot = int(float(self.rot_var.get()))
        except (TypeError, ValueError):
            rot = 1
        rot = max(1, min(8, rot))
        if kind == "circle":
            traj = preset_circle(self.duration, rot)
        elif kind == "spiral":
            traj = preset_spiral(self.duration, rot)
        else:
            traj = preset_figure8(self.duration, rot)
        self.stage.traj = traj
        self.stage.draw()
        self._on_stage_change()
        self.status_var.set(
            f"{kind.title()} preset — {rot} rotation(s), "
            f"{len(traj)} points."
        )

    def _on_reset(self):
        if self._audition_stream is not None:
            self._stop_audition(status="Audition stopped: trajectory reset.")
        self.stage.reset()
        self._on_stage_change()
        self.status_var.set("Trajectory reset.")

    def _on_dbap_k_changed(self, *args):
        if self._audition_stream is not None:
            self._stop_audition(status="Audition stopped: DBAP k changed.")

    def _parse_dbap_k(self):
        try:
            value = float(self.dbap_k_var.get())
        except (TypeError, ValueError):
            raise ValueError("DBAP rolloff k must be a number")
        if not np.isfinite(value) or value < 0.25 or value > 4.0:
            raise ValueError("DBAP rolloff k must be between 0.25 and 4.0")
        return value

    def _load_sounddevice(self):
        if self._audition_sd is not None:
            return self._audition_sd
        try:
            import sounddevice as sd
        except Exception:
            return None
        self._audition_sd = sd
        return sd

    def _refresh_audio_devices(self):
        if self._audition_stream is not None:
            self._stop_audition(status="Audition stopped: audio device list refreshed.")

        sd = self._load_sounddevice()
        if sd is None:
            self._audio_devices = []
            self._audio_device_map = {}
            if hasattr(self, "audio_device_combo"):
                self.audio_device_combo["values"] = []
            self.audio_device_var.set("")
            self.audio_device_info_var.set(
                "Audition unavailable: install sounddevice (Apply still works).")
            return

        try:
            devices = sd.query_devices()
            hostapis = sd.query_hostapis()
            entries = []
            mapping = {}
            for idx, dev in enumerate(devices):
                max_out = int(dev.get("max_output_channels", 0))
                if max_out < 1:
                    continue
                host_idx = int(dev.get("hostapi", -1))
                if 0 <= host_idx < len(hostapis):
                    host_name = str(hostapis[host_idx].get("name", "Host API"))
                else:
                    host_name = "Host API"
                name = str(dev.get("name", f"Device {idx}"))
                label = f"[{idx}] {name} | {host_name} | {max_out} out"
                entries.append(label)
                mapping[label] = {
                    "index": idx, "name": name, "hostapi": host_name,
                    "max_output_channels": max_out,
                    "default_samplerate": float(dev.get("default_samplerate", 0.0) or 0.0),
                }

            self._audio_devices = entries
            self._audio_device_map = mapping
            self.audio_device_combo["values"] = entries

            if not entries:
                self.audio_device_var.set("")
                self.audio_device_info_var.set("No output devices reported by PortAudio.")
                return

            # Prefer the current PortAudio default output device.
            default_out = None
            try:
                default_pair = sd.default.device
                if isinstance(default_pair, (list, tuple)) and len(default_pair) >= 2:
                    default_out = default_pair[1]
                else:
                    default_out = default_pair
                if default_out is not None:
                    default_out = int(default_out)
            except Exception:
                default_out = None

            chosen = None
            if default_out is not None:
                for label, meta in mapping.items():
                    if meta["index"] == default_out:
                        chosen = label
                        break
            if chosen is None:
                chosen = entries[0]

            self.audio_device_var.set(chosen)
            self._update_audio_device_info()
        except Exception as e:
            self._audio_devices = []
            self._audio_device_map = {}
            self.audio_device_combo["values"] = []
            self.audio_device_var.set("")
            self.audio_device_info_var.set(f"Device scan failed: {e}")

    def _update_audio_device_info(self):
        meta = self._audio_device_map.get(self.audio_device_var.get())
        if not meta:
            return
        sr_txt = ""
        if meta["default_samplerate"] > 0:
            sr_txt = f" | default {meta['default_samplerate']:.0f} Hz"
        self.audio_device_info_var.set(
            f"{meta['hostapi']} | {meta['max_output_channels']} outputs{sr_txt}")

    def _on_audio_device_changed(self, event=None):
        if self._audition_stream is not None:
            self._stop_audition(status="Audition stopped: output device changed.")
        self._update_audio_device_info()

    def _get_selected_audio_device(self):
        meta = self._audio_device_map.get(self.audio_device_var.get())
        if not meta:
            raise RuntimeError(
                "No Audition output device is selected. Click Refresh and choose a device.")
        return int(meta["index"]), meta

    def _stop_audition(self, status="Audition stopped."):
        stream = self._audition_stream
        self._audition_stream = None
        if stream is not None:
            try:
                stream.abort()
            except Exception:
                try:
                    stream.close()
                except Exception:
                    pass
        self._audition_pos = 0
        self._audition_mode = ""
        if hasattr(self, "audition_button"):
            self.audition_button.configure(text="  ▶  Audition  ")
        if status:
            self.status_var.set(status)

    def _poll_audition(self):
        stream = self._audition_stream
        if stream is None:
            return
        try:
            active = bool(stream.active)
        except Exception:
            active = False
        if not active:
            try:
                stream.close()
            except Exception:
                pass
            self._audition_stream = None
            self._audition_pos = 0
            self._audition_mode = ""
            self.audition_button.configure(text="  ▶  Audition  ")
            self.status_var.set("Audition finished.")
            return
        self.root.after(100, self._poll_audition)

    def _on_audition(self):
        if self._audition_stream is not None:
            self._stop_audition()
            return

        sd = self._load_sounddevice()
        if sd is None:
            messagebox.showinfo(
                "Audition requires sounddevice",
                "Audition is optional and does not affect Apply.\n\n"
                "Install it for real-time monitoring with:\n"
                "pip install sounddevice",
                parent=self.root,
            )
            self.status_var.set("Audition unavailable: install sounddevice.")
            return

        try:
            dbap_k = self._parse_dbap_k()
            speakers = list(self.speakers)
            n_spk = len(speakers)
            device_index, device_meta = self._get_selected_audio_device()
            max_out = int(device_meta["max_output_channels"])

            exact_error = None
            if max_out >= n_spk:
                try:
                    sd.check_output_settings(
                        device=device_index, channels=n_spk,
                        dtype="float32", samplerate=self.sr)
                    n_out = n_spk
                    stereo_monitor = False
                    mode = f"exact {n_spk}-channel"
                except Exception as e:
                    exact_error = e
                    n_out = 0
            else:
                n_out = 0

            if n_out == 0:
                if max_out < 2:
                    raise RuntimeError(
                        f"Selected device has only {max_out} output channel(s).")
                try:
                    sd.check_output_settings(
                        device=device_index, channels=2,
                        dtype="float32", samplerate=self.sr)
                except Exception as stereo_error:
                    detail = f"\nExact multichannel check: {exact_error}" if exact_error else ""
                    raise RuntimeError(
                        f"Selected device cannot play {self.sr} Hz stereo monitor: "
                        f"{stereo_error}{detail}")
                n_out = 2
                stereo_monitor = True
                if max_out >= n_spk and exact_error is not None:
                    mode = f"stereo monitor (device rejected {n_spk}-ch at {self.sr} Hz)"
                else:
                    mode = "stereo monitor (front/back approximate)"

            traj = self.stage.get_trajectory()
            evaluate = make_trajectory_evaluator(traj, smooth=self.stage.smooth)
            source_peak = float(np.max(np.abs(self.mono))) if len(self.mono) else 0.0
            safety_gain = 1.0
            if source_peak > 0.99 and source_peak > 1e-12:
                safety_gain = 0.99 / source_peak

            self._audition_pos = 0
            self._audition_sd = sd
            self._audition_mode = mode

            def callback(outdata, frames, time_info, status):
                start = self._audition_pos
                block, actual = render_audition_block(
                    self.mono, self.sr, start, frames, evaluate, speakers,
                    k=dbap_k, stereo_monitor=stereo_monitor,
                    safety_gain=safety_gain,
                )
                outdata[:] = block
                self._audition_pos += actual
                if actual < frames or self._audition_pos >= len(self.mono):
                    raise sd.CallbackStop()

            stream = sd.OutputStream(
                samplerate=self.sr,
                channels=n_out,
                dtype="float32",
                blocksize=0,
                latency="high",
                device=device_index,
                callback=callback,
            )
            self._audition_stream = stream
            stream.start()
            self.audition_button.configure(text="  ■  Stop  ")
            self.status_var.set(f"Audition: {mode} on {device_meta['name']}.  Click Stop to end.")
            self.root.after(100, self._poll_audition)
        except Exception as e:
            self._stop_audition(status="")
            messagebox.showerror("Audition Error", str(e), parent=self.root)
            self.status_var.set(f"Audition error: {e}")

    def _on_cancel(self):
        self._stop_audition(status="")
        self.cancelled = True
        self.root.destroy()

    def _set_status(self, msg, pct=None):
        self.status_var.set(msg)
        if pct is not None:
            self.progress["value"] = pct
        self.root.update()

    def _on_apply(self):
        self._stop_audition(status="")
        self._set_status("Rendering spatial audio…", 10)

        dbg_path = self.output_path.replace(".wav", "_spatial_debug.txt")

        def dbg(msg):
            print(msg, flush=True)
            with open(dbg_path, "a", encoding="utf-8") as f:
                f.write(msg + "\n")

        if os.path.exists(dbg_path):
            os.remove(dbg_path)

        try:
            traj     = self.stage.get_trajectory()
            mono     = self.mono
            sr       = self.sr
            speakers = self.speakers
            n        = len(mono)
            dbap_k = self._parse_dbap_k()

            dbg("=== Spatial Panner Debug ===")
            dbg(f"Input: {n} samples, {sr}Hz, {n/sr:.3f}s")
            dbg(f"Input RMS: {np.sqrt(np.mean(mono**2)):.6f}")
            dbg(f"Source input channel: {self.source_channel + 1}/{self.audio.shape[1]}")
            dbg(f"DBAP k: {dbap_k:.3f}")
            dbg(f"Speakers:  {len(speakers)}")
            dbg(f"Trajectory: {len(traj)} points")
            for pt in traj:
                dbg(f"  t={pt[0]:.3f}s  x={pt[1]:+.3f}  y={pt[2]:+.3f}")

            # Lightweight trajectory QC for the debug log.
            eval_traj = make_trajectory_evaluator(traj, smooth=self.stage.smooth)
            qc_times = np.linspace(0.0, n / sr, min(1024, max(2, n)), endpoint=False)
            sx_qc, sy_qc = eval_traj(qc_times)
            dbg(f"sx range: {sx_qc.min():.3f} .. {sx_qc.max():.3f}")
            dbg(f"sy range: {sy_qc.min():.3f} .. {sy_qc.max():.3f}")
            dbg(f"max trajectory radius: {np.max(np.sqrt(sx_qc*sx_qc + sy_qc*sy_qc)):.4f}")

            self._set_status("Streaming DBAP render…", 30)
            def render_progress(frac):
                self._set_status("Streaming DBAP render…", 30 + 58 * frac)

            render_stats = render_spatial_to_file(
                mono, sr, traj, speakers, self.output_path,
                k=dbap_k, smooth=self.stage.smooth,
                block_samples=65536, safety_peak=0.99,
                progress_cb=render_progress,
            )
            dbg(f"Peak before safety: {render_stats['peak_before_safety']:.6f}")
            dbg(f"Safety gain: {render_stats['applied_gain']:.6f}")
            dbg(f"Render blocks: {render_stats['blocks']}")

            # Spot-check the DBAP invariant on the same QC positions.
            gains_qc = dbap_gains_array(sx_qc.astype(np.float64),
                                        sy_qc.astype(np.float64), speakers, k=dbap_k)
            norm_qc = np.sqrt(np.sum(gains_qc**2, axis=1))
            dbg(f"Per-frame power norm QC: mean={norm_qc.mean():.6f} "
                f"std={norm_qc.std():.8f}")

            self._set_status("Saving…", 90)
            dbg(f"Saved: {self.output_path}  "
                f"size={os.path.getsize(self.output_path)} bytes")

            self._set_status(
                f"Done.  {len(traj)} trajectory points  "
                f"→ {len(speakers)}-ch output  ({n/sr:.2f}s)",
                100,
            )
            self.cancelled = False

            # Clean up debug on success
            try:
                if os.path.exists(dbg_path):
                    os.remove(dbg_path)
            except Exception:
                pass

        except Exception as e:
            import traceback
            err = traceback.format_exc()
            try:
                dbg(f"EXCEPTION:\n{err}")
            except Exception:
                pass
            messagebox.showerror(
                "Processing Error",
                f"{e}\n\nSee debug log:\n{dbg_path}",
            )
            self._set_status(f"Error: {e}", 0)
            return

        self.root.after(800, self.root.destroy)

    def run(self):
        self.root.mainloop()
        return not self.cancelled


# ─────────────────────────────────────────────────────────────
# ENTRY POINT
# ─────────────────────────────────────────────────────────────
def main():
    if len(sys.argv) < 3:
        print("Usage: spatial_panner.py  input.wav  output.wav")
        sys.exit(1)

    input_path  = sys.argv[1]
    output_path = sys.argv[2]

    if not os.path.isfile(input_path):
        print(f"Error: input file not found: {input_path}")
        sys.exit(1)

    app     = SpatialPannerApp(input_path, output_path)
    success = app.run()

    if success:
        print(f"Output written: {output_path}")
        sys.exit(0)
    else:
        print("Cancelled.")
        sys.exit(0)    # exit 0 — Praat checks for file, not exit code


if __name__ == "__main__":
    main()
