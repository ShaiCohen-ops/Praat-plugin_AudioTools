#!/usr/bin/env python3
# ============================================================
# Praat AudioTools Plugin
# Script:      envelope_editor.py
# Author:      Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version:     1.0 (2025)
# License:     MIT License
# Repository:  https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Multi-lane breakpoint envelope editor for:
#     1. Pan        — stereo position  (-1 L … 0 C … +1 R)
#     2. Pitch      — semitone shift   (-12 … 0 … +12 st)
#     3. Intensity  — gain in dB       (-24 … 0 … +24 dB)
#     4. Formant    — formant shift     (0.5x … 1.0x … 2.0x)
#
#   Each lane has an independent breakpoint editor scaled to
#   the exact duration of the input sound.
#
# DSP pipeline (Apply):
#   1. Pitch shift  — phase vocoder via STFT (preserves duration)
#   2. Formant shift — LPC resynthesis with shifted filter poles
#   3. Intensity    — per-sample dB gain envelope
#   4. Pan          — equal-power stereo panning
#
# Usage (called by Praat):
#   python envelope_editor.py  input.wav  output.wav
#
# Dependencies:
#   pip install numpy soundfile scipy
#   tkinter — standard Python
# ============================================================

import sys
import os
import tkinter as tk
from tkinter import ttk, messagebox
import numpy as np
import soundfile as sf
from scipy.signal import resample_poly
from math import gcd

# ─────────────────────────────────────────────
# AUDIO CONSTANTS
# ─────────────────────────────────────────────
TARGET_SR  = 44100
STFT_N     = 2048
STFT_HOP   = 512

# ─────────────────────────────────────────────
# LANE DEFINITIONS
# ─────────────────────────────────────────────
LANES = [
    dict(
        key        = "pan",
        label      = "Pan",
        unit       = "",
        y_min      = -1.0,
        y_max      =  1.0,
        y_default  =  0.0,
        y_ticks    = [(-1.0,"L -1"),(-0.5,"-0.5"),(0.0,"C  0"),(0.5,"+0.5"),(1.0,"R +1")],
        color      = "#7ec8e3",
        fill       = "#1a3a4a",
        log_scale  = False,
    ),
    dict(
        key        = "pitch",
        label      = "Pitch",
        unit       = "st",
        y_min      = -12.0,
        y_max      =  12.0,
        y_default  =   0.0,
        y_ticks    = [(-12,"-12"),(-6,"-6"),(0,"  0"),(6,"+6"),(12,"+12")],
        color      = "#b8e07e",
        fill       = "#1a3a1a",
        log_scale  = False,
    ),
    dict(
        key        = "intensity",
        label      = "Intensity",
        unit       = "dB",
        y_min      = -24.0,
        y_max      =  24.0,
        y_default  =   0.0,
        y_ticks    = [(-24,"-24"),(-12,"-12"),(0,"  0"),(12,"+12"),(24,"+24")],
        color      = "#e0b87e",
        fill       = "#3a2a1a",
        log_scale  = False,
    ),
    dict(
        key        = "filter",
        label      = "Filter",
        unit       = "Hz",
        y_min      =   80.0,
        y_max      = 16000.0,
        y_default  =  1000.0,
        y_ticks    = [(80,"80"),(200,"200"),(500,"500"),(1000,"1k"),
                      (2000,"2k"),(4000,"4k"),(8000,"8k"),(16000,"16k")],
        color      = "#e07ec8",
        fill       = "#3a1a3a",
        log_scale  = True,
    ),
]

# ─────────────────────────────────────────────
# CANVAS GEOMETRY
# ─────────────────────────────────────────────
CANVAS_W = 860
CANVAS_H = 190
PAD_L    = 58
PAD_R    = 16
PAD_T    = 14
PAD_B    = 36
PLOT_W   = CANVAS_W - PAD_L - PAD_R
PLOT_H   = CANVAS_H - PAD_T  - PAD_B
POINT_R  = 6

# ─────────────────────────────────────────────
# AUDIO I/O
# ─────────────────────────────────────────────
def load_audio(path):
    audio, sr = sf.read(path, always_2d=True)
    if sr != TARGET_SR:
        g = gcd(TARGET_SR, sr)
        up, dn = TARGET_SR // g, sr // g
        audio  = np.stack(
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
    # Write 32-bit float WAV — Praat reads this format reliably
    sf.write(path, audio, sr, subtype="FLOAT")

# ─────────────────────────────────────────────
# ENVELOPE INTERPOLATION
# ─────────────────────────────────────────────
def interp_envelope(breakpoints, n_samples, sr):
    bp   = sorted(breakpoints, key=lambda p: p[0])
    ts   = np.array([p[0] for p in bp])
    vs   = np.array([p[1] for p in bp])
    t_ax = np.arange(n_samples) / sr
    return np.interp(t_ax, ts, vs).astype(np.float32)

# ─────────────────────────────────────────────
# DSP: PITCH SHIFT (resample_poly method)
# ─────────────────────────────────────────────
def apply_pitch_shift(mono, shift_env, sr):
    """
    Pitch shift via segmented resample_poly + OLA.

    For each hop-sized segment:
      1. resample_poly by ratio p/q  (changes pitch AND duration)
      2. trim or zero-pad back to seg_len  (restores duration)
      3. overlap-add with Hann window

    resample_poly uses a proper polyphase anti-aliasing filter,
    so it actually moves spectral content — unlike plain np.interp.

    shift_env : per-sample semitone values (float32 array, len=n)
    """
    from math import gcd as _gcd

    n       = len(mono)
    seg_len = 4096          # larger window = better pitch resolution
    hop     = seg_len // 4  # 75% overlap for smooth transitions
    window  = np.hanning(seg_len).astype(np.float64)
    out     = np.zeros(n + seg_len, dtype=np.float64)
    norm    = np.zeros(n + seg_len, dtype=np.float64)

    for start in range(0, n - seg_len + 1, hop):
        st  = float(np.mean(shift_env[start: start + seg_len]))
        seg = mono[start: start + seg_len].astype(np.float64) * window

        if abs(st) < 0.05:
            out[start: start + seg_len]  += seg
            norm[start: start + seg_len] += window
            continue

        # Convert semitones to rational up/down for resample_poly
        # Approximate ratio with small integers (max denominator 100)
        ratio = 2.0 ** (st / 12.0)

        # Find best p/q approximation
        best_p, best_q, best_err = 1, 1, 1e9
        for q in range(1, 80):
            p = round(ratio * q)
            if p < 1:
                continue
            err = abs(p / q - ratio)
            if err < best_err:
                best_p, best_q, best_err = p, q, err

        p, q = best_p, best_q
        g    = _gcd(p, q)
        p, q = p // g, q // g

        # resample: up by p, down by q  -> length changes to seg_len*p//q
        resampled = resample_poly(seg, p, q)

        # Trim or zero-pad back to seg_len
        r_len = len(resampled)
        if r_len >= seg_len:
            frame_out = resampled[:seg_len]
        else:
            frame_out = np.zeros(seg_len)
            frame_out[:r_len] = resampled

        # Match frame energy to input segment before accumulating
        # (resample_poly can scale energy when p/q ratio is far from 1)
        rms_seg = np.sqrt(np.mean(seg**2)) + 1e-8
        rms_out = np.sqrt(np.mean(frame_out**2)) + 1e-8
        frame_out = frame_out * (rms_seg / rms_out)

        out[start: start + seg_len]  += frame_out
        norm[start: start + seg_len] += window

    norm   = np.maximum(norm, 1e-8)
    result = (out / norm)[:n]

    # Preserve input RMS
    rms_in  = np.sqrt(np.mean(mono.astype(np.float64)**2)) + 1e-8
    rms_out = np.sqrt(np.mean(result**2)) + 1e-8
    result  = result * (rms_in / rms_out)
    return result.astype(np.float32)

# ─────────────────────────────────────────────
# DSP: FILTER (time-varying shelf filter)
# ─────────────────────────────────────────────
def apply_filter(audio, freq_env, sr):
    """
    Time-varying filter. freq_env controls cutoff frequency in Hz.
    Neutral = 1000 Hz (passthrough).
    Below 1000 Hz  -> 2nd-order lowpass shelf (gentle darkening).
    Above 1000 Hz  -> 2nd-order highpass shelf (gentle brightening).

    Uses a dry/wet blend proportional to distance from neutral,
    so movement near 1000 Hz is barely audible and only extreme
    positions give a strong colour change.
    """
    from scipy.signal import butter, sosfilt

    n_ch    = audio.shape[1]
    n       = audio.shape[0]
    seg_len = 2048
    hop     = seg_len // 2
    out     = np.zeros_like(audio)
    norm    = np.zeros(n, dtype=np.float32)
    window  = np.hanning(seg_len).astype(np.float32)
    nyq     = sr / 2.0
    neutral = 1000.0

    for start in range(0, n - seg_len + 1, hop):
        fc  = float(np.mean(freq_env[start: start + seg_len]))
        fc  = np.clip(fc, 80.0, nyq - 100.0)

        # Dry/wet: 0 at neutral, 1 at extremes (80 Hz or 16 kHz)
        dist  = abs(fc - neutral)
        wet   = np.clip(dist / 900.0, 0.0, 1.0)   # full wet at ±900 Hz from neutral

        for ch in range(n_ch):
            seg = audio[start: start + seg_len, ch]

            if wet < 0.02:
                frame_out = seg
            else:
                fc_clamped = np.clip(fc, 120.0, nyq - 200.0)
                if fc < neutral:
                    sos = butter(2, fc_clamped / nyq, btype='low',  output='sos')
                else:
                    sos = butter(2, fc_clamped / nyq, btype='high', output='sos')

                filtered  = sosfilt(sos, seg).astype(np.float32)
                frame_out = (1.0 - wet) * seg + wet * filtered

            out[start: start + seg_len, ch] += frame_out * window

        norm[start: start + seg_len] += window

    norm = np.maximum(norm, 1e-8)
    for ch in range(n_ch):
        out[:, ch] /= norm

    # RMS match per channel
    for ch in range(n_ch):
        rms_in  = np.sqrt(np.mean(audio[:, ch]**2)) + 1e-8
        rms_out = np.sqrt(np.mean(out[:, ch]**2))   + 1e-8
        out[:, ch] *= rms_in / rms_out

    return out.astype(np.float32)

# ─────────────────────────────────────────────
# DSP: INTENSITY
# ─────────────────────────────────────────────
def apply_intensity(audio, db_env):
    """Per-sample dB gain. db_env shape (n_samples,)."""
    gain = 10.0 ** (db_env / 20.0)
    return (audio * gain[:, np.newaxis]).astype(np.float32)

# ─────────────────────────────────────────────
# DSP: PAN
# ─────────────────────────────────────────────
def apply_pan(audio, pan_env):
    """Equal-power pan. Returns stereo (n_samples, 2)."""
    n_ch   = audio.shape[1]
    angle  = (pan_env + 1.0) / 2.0 * (np.pi / 2.0)
    gain_l = np.cos(angle)
    gain_r = np.sin(angle)

    if n_ch == 1:
        mono  = audio[:, 0]
        left  = mono * gain_l
        right = mono * gain_r
    else:
        mid   = (audio[:, 0] + audio[:, 1]) * 0.5
        side  = (audio[:, 0] - audio[:, 1]) * 0.5
        left  = mid * gain_l + side
        right = mid * gain_r - side

    return np.stack([left, right], axis=1).astype(np.float32)

# ─────────────────────────────────────────────
# BREAKPOINT EDITOR CANVAS
# ─────────────────────────────────────────────
class BreakpointEditor(tk.Canvas):
    def __init__(self, parent, duration, lane, **kwargs):
        super().__init__(parent,
                         width=CANVAS_W, height=CANVAS_H,
                         bg="#12121e", highlightthickness=0, **kwargs)
        self.duration  = duration
        self.lane      = lane
        self.points    = [[0.0, lane['y_default']],
                          [duration, lane['y_default']]]
        self._drag_idx = None
        self.bind("<ButtonPress-1>",   self._on_press)
        self.bind("<B1-Motion>",       self._on_drag)
        self.bind("<ButtonRelease-1>", self._on_release)
        self.bind("<ButtonPress-3>",   self._on_right)
        self.draw()

    # ── coord transforms ───────────────────────────────────────────
    def t2x(self, t):
        return PAD_L + (t / self.duration) * PLOT_W

    def x2t(self, x):
        return max(0.0, min(self.duration, (x - PAD_L) / PLOT_W * self.duration))

    def v2y(self, v):
        lo, hi = self.lane['y_min'], self.lane['y_max']
        if self.lane.get('log_scale'):
            import math
            log_lo = math.log10(lo)
            log_hi = math.log10(hi)
            norm   = (math.log10(max(v, lo)) - log_lo) / (log_hi - log_lo)
        else:
            norm = (v - lo) / (hi - lo)
        return PAD_T + (1.0 - norm) * PLOT_H

    def y2v(self, y):
        lo, hi = self.lane['y_min'], self.lane['y_max']
        norm = 1.0 - (y - PAD_T) / PLOT_H
        norm = max(0.0, min(1.0, norm))
        if self.lane.get('log_scale'):
            import math
            log_lo = math.log10(lo)
            log_hi = math.log10(hi)
            v = 10.0 ** (log_lo + norm * (log_hi - log_lo))
        else:
            v = lo + norm * (hi - lo)
        return max(lo, min(hi, v))

    # ── hit test ───────────────────────────────────────────────────
    def _find(self, x, y):
        for i, (t, v) in enumerate(self.points):
            if (x - self.t2x(t))**2 + (y - self.v2y(v))**2 <= (POINT_R * 2)**2:
                return i
        return None

    # ── mouse ──────────────────────────────────────────────────────
    def _on_press(self, e):
        idx = self._find(e.x, e.y)
        if idx is not None:
            self._drag_idx = idx
        elif PAD_L <= e.x <= PAD_L + PLOT_W and PAD_T <= e.y <= PAD_T + PLOT_H:
            t = self.x2t(e.x)
            v = self.y2v(e.y)
            self.points.append([t, v])
            self.points.sort(key=lambda p: p[0])
            self._drag_idx = next(
                i for i, p in enumerate(self.points) if p[0] == t and p[1] == v
            )
            self.draw()

    def _on_drag(self, e):
        if self._drag_idx is None:
            return
        idx = self._drag_idx
        t   = self.x2t(e.x)
        v   = self.y2v(e.y)
        if idx == 0:
            t = 0.0
        elif idx == len(self.points) - 1:
            t = self.duration
        else:
            t = max(self.points[idx-1][0] + 0.001,
                    min(self.points[idx+1][0] - 0.001, t))
        self.points[idx] = [t, v]
        self.draw()

    def _on_release(self, e):
        self._drag_idx = None

    def _on_right(self, e):
        idx = self._find(e.x, e.y)
        if idx not in (None, 0, len(self.points) - 1):
            self.points.pop(idx)
            self.draw()

    # ── drawing ────────────────────────────────────────────────────
    def draw(self):
        self.delete("all")
        self._bg()
        self._grid()
        self._envelope()
        self._points()

    def _bg(self):
        self.create_rectangle(PAD_L, PAD_T,
                               PAD_L + PLOT_W, PAD_T + PLOT_H,
                               fill="#0e0e1a", outline="#2a2a4a")

    def _grid(self):
        lane = self.lane
        # Horizontal guides
        for v, lbl in lane['y_ticks']:
            y   = self.v2y(v)
            col = "#4a4a6e" if v != lane['y_default'] else "#7a7aae"
            w   = 1         if v != lane['y_default'] else 2
            dk  = () if v == lane['y_default'] else (4, 4)
            self.create_line(PAD_L, y, PAD_L + PLOT_W, y,
                             fill=col, width=w, dash=dk)
            self.create_text(PAD_L - 5, y, text=lbl,
                             anchor="e", fill="#8888aa", font=("Courier", 8))

        # Vertical guides + x labels (only bottom lane shows labels)
        n_ticks = min(10, max(4, int(self.duration)))
        step    = self.duration / n_ticks
        t = 0.0
        while t <= self.duration + 0.001:
            x = self.t2x(t)
            self.create_line(x, PAD_T, x, PAD_T + PLOT_H,
                             fill="#2a2a4a", dash=(3, 5))
            self.create_text(x, PAD_T + PLOT_H + 14, text=f"{t:.1f}",
                             anchor="n", fill="#6666aa", font=("Courier", 8))
            t += step

        # Lane label (left side)
        unit = f" ({lane['unit']})" if lane['unit'] else ""
        self.create_text(8, PAD_T + PLOT_H // 2,
                         text=lane['label'] + unit,
                         anchor="center", fill=lane['color'],
                         font=("Helvetica", 9, "bold"), angle=90)

    def _envelope(self):
        pts = sorted(self.points, key=lambda p: p[0])
        if len(pts) < 2:
            return
        coords = []
        for t, v in pts:
            coords += [self.t2x(t), self.v2y(v)]
        self.create_line(*coords, fill=self.lane['color'], width=2)

        # Fill under/over default line
        def_y  = self.v2y(self.lane['y_default'])
        poly   = [PAD_L, def_y]
        for t, v in pts:
            poly += [self.t2x(t), self.v2y(v)]
        poly  += [PAD_L + PLOT_W, def_y]
        self.create_polygon(*poly, fill=self.lane['fill'],
                            outline="", stipple="gray25")

    def _points(self):
        n = len(self.points)
        for i, (t, v) in enumerate(self.points):
            x   = self.t2x(t)
            y   = self.v2y(v)
            col = "#ffaa44" if i in (0, n-1) else self.lane['color']
            self.create_oval(x-POINT_R, y-POINT_R, x+POINT_R, y+POINT_R,
                             fill=col, outline="#ffffff", width=1)
            unit = self.lane['unit']
            lbl  = f"{v:+.2f}{unit}" if unit else f"{v:+.2f}"
            self.create_text(x, y - POINT_R - 5, text=lbl,
                             anchor="s", fill="#ddddff", font=("Courier", 8))

    def reset(self):
        self.points = [[0.0, self.lane['y_default']],
                       [self.duration, self.lane['y_default']]]
        self.draw()

    def get_breakpoints(self):
        return [(t, v) for t, v in sorted(self.points, key=lambda p: p[0])]


# ─────────────────────────────────────────────
# MAIN APP
# ─────────────────────────────────────────────
class EnvelopeEditorApp:

    def __init__(self, input_path, output_path):
        self.input_path  = input_path
        self.output_path = output_path
        self.cancelled   = True

        self.audio, self.sr = load_audio(input_path)
        self.duration       = self.audio.shape[0] / self.sr
        n_ch                = self.audio.shape[1]
        ch_label            = "mono" if n_ch == 1 else "stereo"

        # ── Window ─────────────────────────────────────────────────
        self.root = tk.Tk()
        self.root.title("Envelope Editor — Praat AudioTools")
        self.root.resizable(False, False)
        self.root.configure(bg="#12121e")
        self.root.protocol("WM_DELETE_WINDOW", self._on_cancel)

        # ── Header ─────────────────────────────────────────────────
        hdr = tk.Frame(self.root, bg="#12121e", pady=5)
        hdr.pack(fill="x", padx=10)
        fname = os.path.basename(input_path)
        tk.Label(hdr,
                 text=f"  {fname}   {self.duration:.2f}s   {self.sr}Hz   {ch_label}",
                 bg="#12121e", fg="#9090c0",
                 font=("Courier", 10)).pack(side="left")
        tk.Label(hdr,
                 text="Left-click: add/drag   Right-click: delete",
                 bg="#12121e", fg="#505070",
                 font=("Helvetica", 9)).pack(side="right")

        # ── Scrollable canvas area ──────────────────────────────────
        outer = tk.Frame(self.root, bg="#12121e")
        outer.pack(fill="both", expand=True, padx=6)

        self.scroll_canvas = tk.Canvas(outer, bg="#12121e",
                                       highlightthickness=0)
        vsb = ttk.Scrollbar(outer, orient="vertical",
                             command=self.scroll_canvas.yview)
        self.scroll_canvas.configure(yscrollcommand=vsb.set)
        vsb.pack(side="right", fill="y")
        self.scroll_canvas.pack(side="left", fill="both", expand=True)

        self.inner = tk.Frame(self.scroll_canvas, bg="#12121e")
        self.scroll_canvas.create_window((0, 0), window=self.inner, anchor="nw")
        self.inner.bind("<Configure>",
                        lambda e: self.scroll_canvas.configure(
                            scrollregion=self.scroll_canvas.bbox("all")
                        ))

        # ── Lane editors ───────────────────────────────────────────
        self.editors = {}
        for lane in LANES:
            frame = tk.Frame(self.inner, bg="#1a1a2e", pady=2)
            frame.pack(fill="x", padx=4, pady=3)
            ed = BreakpointEditor(frame, self.duration, lane)
            ed.pack()
            self.editors[lane['key']] = ed

        # Fixed visible height: 4 lanes × CANVAS_H + padding
        visible_h = min(4 * CANVAS_H + 60, 820)
        self.scroll_canvas.configure(height=visible_h, width=CANVAS_W + 20)

        # Mousewheel scroll
        self.root.bind_all("<MouseWheel>",
            lambda e: self.scroll_canvas.yview_scroll(-1*(e.delta//120), "units"))

        # ── Status bar ─────────────────────────────────────────────
        self.status_var = tk.StringVar(value="Ready.")
        tk.Label(self.root, textvariable=self.status_var,
                 bg="#12121e", fg="#606090",
                 font=("Courier", 9), anchor="w").pack(fill="x", padx=14, pady=2)

        # ── Progress bar ───────────────────────────────────────────
        self.progress = ttk.Progressbar(self.root, mode="determinate",
                                         length=CANVAS_W + 20)
        self.progress.pack(padx=10, pady=(0, 2))

        # ── Buttons ────────────────────────────────────────────────
        btn_frame = tk.Frame(self.root, bg="#12121e", pady=7)
        btn_frame.pack()

        style_btn = dict(relief="flat", padx=10, pady=4,
                         font=("Helvetica", 10))
        tk.Button(btn_frame, text=" Reset All ",
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

    # ── Callbacks ──────────────────────────────────────────────────

    def _on_reset(self):
        for ed in self.editors.values():
            ed.reset()
        self.status_var.set("All lanes reset to defaults.")

    def _on_cancel(self):
        self.cancelled = True
        self.root.destroy()

    def _set_status(self, msg, pct=None):
        self.status_var.set(msg)
        if pct is not None:
            self.progress["value"] = pct
        self.root.update()

    def _on_apply(self):
        self._set_status("Starting processing…", 0)

        # Debug log file next to output
        dbg_path = self.output_path.replace('.wav', '_debug.txt')
        def dbg(msg):
            print(msg, flush=True)
            with open(dbg_path, 'a', encoding='utf-8') as f:
                f.write(msg + '\n')

        if os.path.exists(dbg_path):
            os.remove(dbg_path)

        try:
            audio = self.audio.copy()
            n     = audio.shape[0]
            sr    = self.sr

            dbg(f"=== Envelope Editor Debug ===")
            dbg(f"Input: {n} samples, {audio.shape[1]}ch, {sr}Hz, {n/sr:.2f}s")
            dbg(f"Input RMS: {np.sqrt(np.mean(audio**2)):.6f}")
            dbg(f"Input peak: {np.max(np.abs(audio)):.6f}")

            # ── 1. Pitch shift ──────────────────────────────────────
            self._set_status("Applying pitch shift…", 10)
            pitch_bp  = self.editors['pitch'].get_breakpoints()
            pitch_env = interp_envelope(pitch_bp, n, sr)
            dbg(f"Pitch env: min={pitch_env.min():.3f} max={pitch_env.max():.3f} "
                f"mean={pitch_env.mean():.3f}")

            if np.max(np.abs(pitch_env)) > 0.05:
                dbg("  >> pitch shift active")
                mono_mix = audio.mean(axis=1)
                shifted  = apply_pitch_shift(mono_mix, pitch_env, sr)
                dbg(f"  shifted RMS={np.sqrt(np.mean(shifted**2)):.6f} "
                    f"peak={np.max(np.abs(shifted)):.6f}")
                # Clip before normalization to prevent NaN/Inf propagating
                shifted = np.clip(shifted, -1.0, 1.0)
                rms_in  = np.sqrt(np.mean(mono_mix**2)) + 1e-8
                rms_sh  = np.sqrt(np.mean(shifted**2))  + 1e-8
                scale   = min(rms_in / rms_sh, 4.0)   # cap scale to prevent blow-up
                shifted = shifted * scale
                shifted = np.clip(shifted, -1.0, 1.0)
                dbg(f"  after clip+norm: RMS={np.sqrt(np.mean(shifted**2)):.6f} "
                    f"peak={np.max(np.abs(shifted)):.6f}")
                for ch in range(audio.shape[1]):
                    audio[:, ch] = shifted
            else:
                dbg("  >> pitch shift skipped (all zero)")
            dbg(f"After pitch: RMS={np.sqrt(np.mean(audio**2)):.6f} "
                f"peak={np.max(np.abs(audio)):.6f}")

            # ── 2. Filter ───────────────────────────────────────────
            self._set_status("Applying filter envelope...", 35)
            filt_bp  = self.editors['filter'].get_breakpoints()
            filt_env = interp_envelope(filt_bp, n, sr)
            dbg(f"Filter env: min={filt_env.min():.1f} max={filt_env.max():.1f} Hz")

            if np.any(np.abs(filt_env - 1000.0) > 30.0):
                dbg("  >> filter active")
                audio = apply_filter(audio, filt_env, sr)
            else:
                dbg("  >> filter skipped (all neutral ~1000Hz)")
            dbg(f"After filter: RMS={np.sqrt(np.mean(audio**2)):.6f} "
                f"peak={np.max(np.abs(audio)):.6f}")

            # ── 3. Intensity ────────────────────────────────────────
            self._set_status("Applying intensity envelope…", 65)
            int_bp  = self.editors['intensity'].get_breakpoints()
            int_env = interp_envelope(int_bp, n, sr)
            dbg(f"Intensity env: min={int_env.min():.3f} max={int_env.max():.3f} "
                f"(dB) >> gain: {10**(int_env.min()/20):.4f}-{10**(int_env.max()/20):.4f}x")
            audio   = apply_intensity(audio, int_env)
            dbg(f"After intensity: shape={audio.shape} RMS={np.sqrt(np.mean(audio**2)):.6f} "
                f"peak={np.max(np.abs(audio)):.6f}")

            # ── 4. Pan ──────────────────────────────────────────────
            self._set_status("Applying pan envelope…", 80)
            pan_bp  = self.editors['pan'].get_breakpoints()
            pan_env = interp_envelope(pan_bp, n, sr)
            dbg(f"Pan env: min={pan_env.min():.3f} max={pan_env.max():.3f}")
            audio   = apply_pan(audio, pan_env)
            dbg(f"After pan: shape={audio.shape} RMS={np.sqrt(np.mean(audio**2)):.6f} "
                f"peak={np.max(np.abs(audio)):.6f}")

            # ── Save ────────────────────────────────────────────────
            self._set_status("Saving...", 95)
            dbg(f"Pre-save audio: shape={audio.shape} dtype={audio.dtype}")
            dbg(f"Pre-save: min={audio.min():.6f} max={audio.max():.6f} "
                f"mean={audio.mean():.6f} RMS={np.sqrt(np.mean(audio**2)):.6f}")
            dbg(f"First 5 samples ch0: {audio[:5,0].tolist()}")
            dbg(f"First 5 samples ch1: {audio[:5,1].tolist()}")
            dbg(f"Any NaN: {np.any(np.isnan(audio))}  Any Inf: {np.any(np.isinf(audio))}")
            dbg(f"Saving to: {self.output_path}")
            save_audio(self.output_path, audio, sr)
            dbg(f"Saved OK. File size: {os.path.getsize(self.output_path)} bytes")

            n_pts = {k: len(self.editors[k].get_breakpoints())
                     for k in self.editors}
            self._set_status(
                f"Done.  Pan:{n_pts['pan']}pt  "
                f"Pitch:{n_pts['pitch']}pt  "
                f"Intensity:{n_pts['intensity']}pt  "
                f"Filter:{n_pts['filter']}pt",
                100
            )
            self.cancelled = False

            # Clean up debug log on success
            try:
                if os.path.exists(dbg_path):
                    os.remove(dbg_path)
            except Exception:
                pass

        except Exception as e:
            import traceback
            err = traceback.format_exc()
            try:
                dbg(f"EXCEPTION: {err}")
            except Exception:
                pass
            messagebox.showerror("Processing Error", f"{e}\n\nSee debug log:\n{dbg_path}")
            self._set_status(f"Error: {e}", 0)
            return

        self.root.after(800, self.root.destroy)

    def run(self):
        self.root.mainloop()
        return not self.cancelled


# ─────────────────────────────────────────────
# ENTRY POINT
# ─────────────────────────────────────────────
def main():
    if len(sys.argv) < 3:
        print("Usage: envelope_editor.py  input.wav  output.wav")
        sys.exit(1)

    input_path  = sys.argv[1]
    output_path = sys.argv[2]

    if not os.path.isfile(input_path):
        print(f"Error: input file not found: {input_path}")
        sys.exit(1)

    app     = EnvelopeEditorApp(input_path, output_path)
    success = app.run()

    if success:
        print(f"Output written: {output_path}")
        sys.exit(0)
    else:
        print("Cancelled.")
        sys.exit(0)   # exit 0 — Praat checks for file, not exit code


if __name__ == "__main__":
    main()
