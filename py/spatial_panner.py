#!/usr/bin/env python3
# ============================================================
# Praat AudioTools Plugin
# Script:      spatial_panner.py
# Author:      Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version:     1.0 (2025)
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
#   Normalization: sqrt(sum gains^2) = 1  (equal loudness at all positions)
#   When source is very close to a speaker, a small epsilon prevents division
#   by zero and ensures energy is smoothly concentrated.
#
# Stereo input: downmix to mono before spatial rendering.
#
# Usage (called by Praat):
#   python spatial_panner.py  input.wav  output.wav
#
# Dependencies:
#   pip install numpy soundfile scipy
#   tkinter — standard Python
# ============================================================

import sys
import os
import math
import tkinter as tk
from tkinter import ttk, messagebox, simpledialog
import numpy as np
import soundfile as sf
from scipy.signal import resample_poly
from math import gcd

# ─────────────────────────────────────────────────────────────
# AUDIO CONSTANTS
# ─────────────────────────────────────────────────────────────
TARGET_SR = 44100

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

def dbap_gains(sx, sy, speakers):
    """
    Compute DBAP gain for each speaker.

    Parameters
    ----------
    sx, sy   : source position in unit-circle space
    speakers : list of (label, angle_deg, radius)

    Returns
    -------
    gains : np.ndarray, shape (n_spk,), RMS-normalised
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
        raw[i] = 1.0 / (dist ** DBAP_K)

    # RMS normalisation: sqrt(sum g^2) = 1
    denom = math.sqrt(np.sum(raw**2)) + 1e-12
    return (raw / denom).astype(np.float32)


def dbap_gains_array(sx_arr, sy_arr, speakers):
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

    raw   = 1.0 / (dist ** DBAP_K)                   # (n_samples, n_spk)
    denom = np.sqrt(np.sum(raw**2, axis=1, keepdims=True)) + 1e-12
    return (raw / denom).astype(np.float32)


# ─────────────────────────────────────────────────────────────
# TRAJECTORY INTERPOLATION
# ─────────────────────────────────────────────────────────────
def interp_trajectory(traj, n_samples, sr):
    """
    Linear interpolation of trajectory points over time.

    traj : list of [time, x, y], sorted by time
    Returns sx_arr, sy_arr each shape (n_samples,)
    """
    pts  = sorted(traj, key=lambda p: p[0])
    ts   = np.array([p[0] for p in pts], dtype=np.float64)
    xs   = np.array([p[1] for p in pts], dtype=np.float64)
    ys   = np.array([p[2] for p in pts], dtype=np.float64)
    t_ax = np.arange(n_samples, dtype=np.float64) / sr
    sx   = np.interp(t_ax, ts, xs).astype(np.float32)
    sy   = np.interp(t_ax, ts, ys).astype(np.float32)
    return sx, sy


# ─────────────────────────────────────────────────────────────
# AUDIO I/O
# ─────────────────────────────────────────────────────────────
def load_audio(path):
    audio, sr = sf.read(path, always_2d=True)
    if sr != TARGET_SR:
        g  = gcd(TARGET_SR, sr)
        up, dn = TARGET_SR // g, sr // g
        audio = np.stack(
            [resample_poly(audio[:, c], up, dn) for c in range(audio.shape[1])],
            axis=1
        )
        sr = TARGET_SR
    return audio.astype(np.float32), sr


def save_audio(path, audio, sr):
    audio = np.clip(audio, -1.0, 1.0).astype(np.float32)
    peak  = np.max(np.abs(audio))
    if peak > 1e-8:
        audio = audio / peak * 0.99
    sf.write(path, audio, sr, subtype="FLOAT")


# ─────────────────────────────────────────────────────────────
# SPATIAL RENDER
# ─────────────────────────────────────────────────────────────
def render_spatial(mono, sr, traj, speakers):
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
                               sy.astype(np.float64), speakers)  # (n, n_spk)
    out = mono[:, np.newaxis] * gains                             # (n, n_spk)
    return out.astype(np.float32)


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
            # Assign time between last interior point and duration anchor
            pts = self.traj
            # Insert before the end anchor, suggest midpoint time
            t_last = pts[-2][0] if len(pts) >= 2 else 0.0
            t_end  = pts[-1][0]
            t_new  = (t_last + t_end) / 2.0
            self.traj.insert(len(pts) - 1, [t_new, x, y])
            self._drag_idx = len(self.traj) - 2
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
            # Label outside
            lx = STAGE_CX + (ux * (STAGE_R + 14) / 1.0 * (STAGE_R / STAGE_R))
            ly = STAGE_CY - (uy * (STAGE_R + 14) / 1.0 * (STAGE_R / STAGE_R))
            # Simple label offset in pixel space
            nx, ny = ux / max(abs(ux), abs(uy), 0.01), uy / max(abs(ux), abs(uy), 0.01)
            lx2 = px + nx * (SPK_R + 10)
            ly2 = py - ny * (SPK_R + 10)
            self.create_text(lx2, ly2, text=label,
                             fill=SPK_COL, font=("Courier", 8, "bold"))

    def _draw_trajectory(self):
        if len(self.traj) < 2:
            return
        pts_sorted = sorted(self.traj, key=lambda p: p[0])
        coords = []
        for t, x, y in pts_sorted:
            px, py = unit_to_stage(x, y)
            coords += [px, py]
        self.create_line(*coords, fill=TRAJ_COLOR, width=2,
                         smooth=False, arrow=tk.LAST,
                         arrowshape=(10, 12, 4))

    def _draw_points(self):
        n = len(self.traj)
        for i, (t, x, y) in enumerate(self.traj):
            px, py = unit_to_stage(x, y)
            is_anchor = (i == 0 or i == n - 1)
            col = ANCHOR_COL if is_anchor else POINT_COL
            r   = POINT_R + (2 if is_anchor else 0)
            self.create_oval(px - r, py - r, px + r, py + r,
                             fill=col, outline="#ffffff", width=1)
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
        ch_label            = "mono" if n_ch == 1 else "stereo"

        # Downmix to mono for spatial rendering
        self.mono = self.audio.mean(axis=1).astype(np.float32)

        # ── Window ────────────────────────────────────────────
        self.root = tk.Tk()
        self.root.title("Spatial Panner — Praat AudioTools")
        self.root.resizable(False, False)
        self.root.configure(bg="#12121e")
        self.root.protocol("WM_DELETE_WINDOW", self._on_cancel)

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
        self.stage.bind("<ButtonRelease-1>", self._on_stage_change)
        self.stage.bind("<ButtonRelease-3>", self._on_stage_change)

        # Time ruler below stage
        self.ruler = TimeRuler(stage_frame, self.duration)
        self.ruler.pack(pady=(2, 0))
        self.ruler.update_from_traj(self.stage.get_trajectory())

        # Right info panel
        info_frame = tk.Frame(body, bg="#12121e", width=200)
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

        tk.Label(info_frame,
                 text="DBAP  k=" + str(DBAP_K),
                 bg="#12121e", fg="#505080",
                 font=("Courier", 8)).pack(anchor="w", pady=(8, 0))
        tk.Label(info_frame,
                 text=f"ε={DBAP_EPS}  norm=RMS",
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
        tk.Button(btn_frame, text="  ▶  Apply  ",
                  command=self._on_apply,
                  bg="#2a4e2a", fg="#c0e0c0",
                  activebackground="#3a6a3a",
                  font=("Helvetica", 11, "bold"),
                  relief="flat", padx=14, pady=4).pack(side="left", padx=8)

    # ── event handlers ────────────────────────────────────────

    def _on_stage_change(self, e=None):
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
        self.speakers = make_ring_speakers(n)
        self.stage.speakers = self.speakers
        self.stage.draw()
        self._refresh_spk_list()
        # Update header
        self.status_var.set(
            f"Speaker layout changed to {n} speakers."
        )

    def _on_reset(self):
        self.stage.reset()
        self._on_stage_change()
        self.status_var.set("Trajectory reset.")

    def _on_cancel(self):
        self.cancelled = True
        self.root.destroy()

    def _set_status(self, msg, pct=None):
        self.status_var.set(msg)
        if pct is not None:
            self.progress["value"] = pct
        self.root.update()

    def _on_apply(self):
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

            dbg("=== Spatial Panner Debug ===")
            dbg(f"Input: {n} samples, {sr}Hz, {n/sr:.3f}s")
            dbg(f"Input RMS: {np.sqrt(np.mean(mono**2)):.6f}")
            dbg(f"Speakers:  {len(speakers)}")
            dbg(f"Trajectory: {len(traj)} points")
            for pt in traj:
                dbg(f"  t={pt[0]:.3f}s  x={pt[1]:+.3f}  y={pt[2]:+.3f}")

            self._set_status("Interpolating trajectory…", 30)
            sx, sy = interp_trajectory(traj, n, sr)
            dbg(f"sx range: {sx.min():.3f} .. {sx.max():.3f}")
            dbg(f"sy range: {sy.min():.3f} .. {sy.max():.3f}")

            self._set_status("Computing DBAP gains…", 50)
            gains = dbap_gains_array(sx.astype(np.float64),
                                     sy.astype(np.float64), speakers)
            dbg(f"Gains shape: {gains.shape}  "
                f"min={gains.min():.4f}  max={gains.max():.4f}")

            # Verify RMS normalisation per frame (should be ~1.0)
            rms_check = np.sqrt(np.sum(gains**2, axis=1))
            dbg(f"Per-frame RMS of gains: "
                f"mean={rms_check.mean():.4f}  "
                f"std={rms_check.std():.6f}")

            self._set_status("Mixing to output channels…", 70)
            out = mono[:, np.newaxis] * gains           # (n, n_spk)
            dbg(f"Output shape: {out.shape}  "
                f"peak={np.max(np.abs(out)):.4f}  "
                f"RMS={np.sqrt(np.mean(out**2)):.6f}")

            self._set_status("Saving…", 90)
            save_audio(self.output_path, out, sr)
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
