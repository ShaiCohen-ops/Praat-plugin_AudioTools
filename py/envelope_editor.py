#!/usr/bin/env python3
# ============================================================
# Praat AudioTools Plugin
# Script:      envelope_editor.py
# Author:      Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version:     2.3 (2026) - waveform display + shared zoom
# License:     MIT License
# Repository:  https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v2.3:
#   - NEW: time-domain waveform strip above the lanes (min/max band display,
#     switches to a sample-level line when zoomed in far enough), with a
#     full-length overview row showing the current view window.
#   - NEW: faint "ghost" waveform behind every envelope lane so breakpoints
#     can be placed against the audio (toggle: "Wave in lanes").
#   - NEW: shared zoom across the strip and all four lanes:
#       Ctrl+wheel (Cmd+wheel on macOS) = zoom at cursor, Shift+wheel = scroll,
#       drag on the waveform = select, then "Zoom sel" / key Z,
#       click/drag in the overview = move the view,
#       keys + / - / 0 / Left / Right, and toolbar buttons.
#   - Lanes clip the envelope at the view edges (interpolated), draw only
#     visible breakpoints, and use 1-2-5 "nice" time ticks at any zoom.
#   - Dragging a breakpoint now redraws only the envelope layer, not the
#     whole canvas (keeps drag responsive with the waveform underneath).
#   - Waveform file is an OPTIONAL 4th gui argument; without it the editor
#     behaves as before (zoom still works). numpy is used if present,
#     otherwise a pure-Python path - tkinter stays the only hard dependency.
#   - Scroll area for lanes reduced 820 -> 680 px so the window height is
#     unchanged despite the new strip.
#
# Description:
#   Multi-lane breakpoint envelope editor GUI.
#   All DSP (pitch, intensity, pan, filter) is performed by Praat
#   after the GUI closes. The GUI supports explicit full-fidelity Audition:
#   it saves the current curves, asks Praat to render/play them, then reopens
#   with the same curves for further editing.
#
#   Lanes:
#     1. Pan        — stereo position  (-1 L … 0 C … +1 R)
#     2. Pitch      — semitone shift   (-12 … 0 … +12 st)
#     3. Intensity  — gain in dB       (-24 … 0 … +24 dB)
#     4. Filter     — spectral-morph coordinate on an Hz-like scale
#                    (<=300 -> LP endpoint, 1000 dry, >=3000 -> HP endpoint)
#
# Usage (called by Praat):
#   python envelope_editor.py gui <duration_seconds> <breakpoints_out.json> [wave.wav]
#
# Output JSON format:
#   {
#     "pan":       [[t, v], ...],
#     "pitch":     [[t, v], ...],
#     "intensity": [[t, v], ...],
#     "filter":    [[t, v], ...]
#   }
#   All times are in seconds. Values are in the lane's native unit.
#   If the user cancels, the output file is NOT written (exit code 1).
#
# Dependencies:
#   tkinter — standard Python (numpy optional, only speeds up the waveform)
# ============================================================

import sys
import os
import json
import math
import wave
import array as _array
import tkinter as tk
from tkinter import ttk

try:
    import numpy as _np
except Exception:
    _np = None

# ─────────────────────────────────────────────
# LANE DEFINITIONS
# ─────────────────────────────────────────────
LANES = [
    dict(
        key       = "pan",
        label     = "Pan",
        unit      = "",
        y_min     = -1.0,
        y_max     =  1.0,
        y_default =  0.0,
        y_ticks   = [(-1.0,"L -1"),(-0.5,"-0.5"),(0.0,"C  0"),(0.5,"+0.5"),(1.0,"R +1")],
        color     = "#7ec8e3",
        fill      = "#1a3a4a",
        log_scale = False,
    ),
    dict(
        key       = "pitch",
        label     = "Pitch",
        unit      = "st",
        y_min     = -12.0,
        y_max     =  12.0,
        y_default =   0.0,
        y_ticks   = [(-12,"-12"),(-6,"-6"),(0,"  0"),(6,"+6"),(12,"+12")],
        color     = "#b8e07e",
        fill      = "#1a3a1a",
        log_scale = False,
    ),
    dict(
        key       = "intensity",
        label     = "Intensity",
        unit      = "dB",
        y_min     = -24.0,
        y_max     =  24.0,
        y_default =   0.0,
        y_ticks   = [(-24,"-24"),(-12,"-12"),(0,"  0"),(12,"+12"),(24,"+24")],
        color     = "#e0b87e",
        fill      = "#3a2a1a",
        log_scale = False,
    ),
    dict(
        key       = "filter",
        label     = "Filter",
        unit      = "Hz",
        y_min     =   80.0,
        y_max     = 16000.0,
        y_default =  1000.0,
        y_ticks   = [(80,"80"),(200,"200"),(500,"500"),(1000,"1k"),
                     (2000,"2k"),(4000,"4k"),(8000,"8k"),(16000,"16k")],
        color     = "#e07ec8",
        fill      = "#3a1a3a",
        log_scale = True,
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

# Waveform strip (same horizontal geometry as the lanes so x lines up)
WAVE_H   = 150
OV_T     = 6                      # overview row
OV_H     = 22
MAIN_T   = OV_T + OV_H + 8        # main waveform
MAIN_H   = WAVE_H - MAIN_T - 26

WAVE_COLOR  = "#9aa4d8"
OV_COLOR    = "#4a4a78"
GHOST_COLOR = "#33334f"
SEL_FILL    = "#24244a"
VIEW_COLOR  = "#ffaa44"

IS_MAC = sys.platform == "darwin"


# ─────────────────────────────────────────────
# TIME-AXIS HELPERS
# ─────────────────────────────────────────────
def _nice_step(span, target=8):
    """1-2-5 tick step giving roughly `target` ticks over `span` seconds."""
    if span <= 0:
        return 1.0
    raw = span / target
    mag = 10.0 ** math.floor(math.log10(raw))
    for m in (1.0, 2.0, 5.0, 10.0):
        if m * mag >= raw - 1e-15:
            return m * mag
    return 10.0 * mag


def _fmt_time(t, step):
    dec = max(0, -int(math.floor(math.log10(step) + 1e-9)))
    return f"{t:.{dec}f}"


def _time_ticks(t0, t1, target=8):
    step = _nice_step(t1 - t0, target)
    k0 = int(math.ceil(t0 / step - 1e-9))
    k1 = int(math.floor(t1 / step + 1e-9))
    return [(k * step, _fmt_time(k * step, step)) for k in range(k0, k1 + 1)]


# ─────────────────────────────────────────────
# SHARED VIEW STATE  (zoom window, selection, ghost toggle)
# ─────────────────────────────────────────────
class ViewState:
    def __init__(self, duration, sr=None):
        self.duration = duration
        self.t0       = 0.0
        self.t1       = duration
        # Deepest zoom: ~64 samples across the plot, never below 1 ms
        floor_span    = max(0.001, 64.0 / sr) if sr else 0.001
        self.min_span = min(duration, floor_span)
        self.sel      = None          # (a, b) in seconds, or None
        self.ghost    = True          # waveform behind lanes
        self.listeners = []

    @property
    def span(self):
        return self.t1 - self.t0

    def _notify(self):
        for f in self.listeners:
            f()

    def set(self, t0, t1):
        span = max(self.min_span, min(self.duration, t1 - t0))
        t0 = max(0.0, t0)
        t1 = t0 + span
        if t1 > self.duration:
            t1 = self.duration
            t0 = max(0.0, t1 - span)
        if abs(t0 - self.t0) > 1e-12 or abs(t1 - self.t1) > 1e-12:
            self.t0, self.t1 = t0, t1
            self._notify()

    def zoom(self, factor, center=None):
        if center is None:
            center = 0.5 * (self.t0 + self.t1)
        rel  = (center - self.t0) / self.span if self.span > 0 else 0.5
        new  = max(self.min_span, min(self.duration, self.span / factor))
        t0   = center - rel * new
        self.set(t0, t0 + new)

    def pan(self, dt):
        self.set(self.t0 + dt, self.t1 + dt)

    def fit(self):
        self.set(0.0, self.duration)

    def set_selection(self, a, b=None):
        if a is None:
            if self.sel is not None:
                self.sel = None
                self._notify()
            return
        a, b = sorted((max(0.0, min(self.duration, a)),
                       max(0.0, min(self.duration, b))))
        self.sel = (a, b)
        self._notify()


# ─────────────────────────────────────────────
# WAVEFORM DATA  (display only; the audio itself never leaves Praat)
# ─────────────────────────────────────────────
class WaveData:
    BLOCK = 256     # min/max pyramid block, used when a pixel covers many samples

    def __init__(self, path):
        self.ok     = False
        self.msg    = "no waveform supplied"
        self.sr     = None
        self.n      = 0
        self._cache = {}
        if not path:
            return
        try:
            with wave.open(path, "rb") as w:
                nch = w.getnchannels()
                sw  = w.getsampwidth()
                sr  = w.getframerate()
                raw = w.readframes(w.getnframes())
            if sw != 2:
                raise ValueError(f"unsupported sample width {sw}")
            B = self.BLOCK
            if _np is not None:
                x = _np.frombuffer(raw, dtype="<i2")
                if nch > 1:
                    x = x.reshape(-1, nch).mean(axis=1)
                x = x.astype(_np.float32) / 32768.0
                n = len(x)
                m = (n // B) * B
                if m:
                    bl   = x[:m].reshape(-1, B)
                    bmin = bl.min(axis=1)
                    bmax = bl.max(axis=1)
                else:
                    bmin = _np.zeros(0, _np.float32)
                    bmax = _np.zeros(0, _np.float32)
                if n > m:
                    bmin = _np.append(bmin, x[m:].min())
                    bmax = _np.append(bmax, x[m:].max())
                self.scale = 1.0
            else:
                a = _array.array("h")
                a.frombytes(raw)
                if sys.byteorder == "big":
                    a.byteswap()
                if nch > 1:
                    a = a[::nch]          # Praat sends mono; this is a fallback
                x = a
                n = len(x)
                bmin = [min(x[i:i + B]) for i in range(0, n, B)]
                bmax = [max(x[i:i + B]) for i in range(0, n, B)]
                self.scale = 1.0 / 32768.0
            if n < 2:
                raise ValueError("waveform is empty")
            self.x, self.bmin, self.bmax = x, bmin, bmax
            self.n, self.sr = n, float(sr)
            self.ok  = True
            self.msg = ""
        except Exception as ex:
            self.ok  = False
            self.msg = f"waveform unavailable ({ex})"

    def columns(self, t0, t1, ncols):
        """('band', mins, maxs) per pixel column, or ('line', [(t, v), ...])
        when zoomed in so far that there are fewer than ~1.5 samples/pixel."""
        key = (round(t0, 9), round(t1, 9), int(ncols))
        hit = self._cache.get(key)
        if hit is not None:
            return hit
        n, sr, sc, x = self.n, self.sr, self.scale, self.x
        s0, s1 = t0 * sr, t1 * sr
        spc = (s1 - s0) / max(1, ncols)
        if spc < 1.5:
            i0 = max(0, int(math.floor(s0)))
            i1 = min(n - 1, int(math.ceil(s1)))
            res = ("line", [(i / sr, float(x[i]) * sc) for i in range(i0, i1 + 1)])
        else:
            B = self.BLOCK
            use_blocks = spc >= 4 * B
            nb = len(self.bmin)
            mins, maxs = [], []
            for c in range(ncols):
                a = int(s0 + c * spc)
                b = int(s0 + (c + 1) * spc)
                if b <= a:
                    b = a + 1
                if a >= n or a < 0:
                    mins.append(0.0); maxs.append(0.0)
                    continue
                b = min(b, n)
                if use_blocks:
                    ba = a // B
                    bb = min(nb, max(ba + 1, b // B))
                    lo, hi = self.bmin[ba:bb], self.bmax[ba:bb]
                else:
                    lo = hi = x[a:b]
                if _np is not None and not isinstance(lo, (list, _array.array)):
                    mn, mx = float(lo.min()), float(hi.max())
                else:
                    mn, mx = min(lo), max(hi)
                mins.append(mn * sc); maxs.append(mx * sc)
            res = ("band", mins, maxs)
        if len(self._cache) > 12:
            self._cache.clear()
        self._cache[key] = res
        return res


def draw_wave(canvas, wd, t0, t1, x0, width, cy, half_h, color, tags, t2x):
    """Draw wd between t0..t1 into [x0, x0+width] as one canvas item."""
    if wd is None or not wd.ok or t1 <= t0:
        return
    res = wd.columns(t0, t1, int(width))
    if res[0] == "line":
        pts = res[1]
        if len(pts) >= 2:
            coords = []
            for t, v in pts:
                coords += [t2x(t), cy - v * half_h]
            canvas.create_line(*coords, fill=color, tags=tags)
    else:
        _, mins, maxs = res
        poly = []
        for c, mx in enumerate(maxs):
            poly += [x0 + c + 0.5, cy - mx * half_h]
        for c in range(len(mins) - 1, -1, -1):
            poly += [x0 + c + 0.5, cy - mins[c] * half_h]
        # outline in the same colour keeps silent (min == max) stretches visible
        canvas.create_polygon(*poly, fill=color, outline=color, tags=tags)


# ─────────────────────────────────────────────
# WAVEFORM STRIP  (overview + main waveform, selection)
# ─────────────────────────────────────────────
class WaveformStrip(tk.Canvas):
    def __init__(self, parent, view, wave_data, **kwargs):
        super().__init__(parent, width=CANVAS_W, height=WAVE_H,
                         bg="#12121e", highlightthickness=0, **kwargs)
        self.view    = view
        self.wd      = wave_data
        self._mode   = None
        self._anchor = None
        self._px     = 0
        self.bind("<ButtonPress-1>",   self._on_press)
        self.bind("<B1-Motion>",       self._on_drag)
        self.bind("<ButtonRelease-1>", self._on_release)
        self.draw()

    # coordinate transforms
    def t2x(self, t):
        v = self.view
        return PAD_L + (t - v.t0) / v.span * PLOT_W

    def time_at_x(self, x):
        v = self.view
        t = v.t0 + (x - PAD_L) / PLOT_W * v.span
        return max(v.t0, min(v.t1, t))

    def ov_t2x(self, t):
        return PAD_L + t / self.view.duration * PLOT_W

    def ov_x2t(self, x):
        return max(0.0, min(self.view.duration,
                            (x - PAD_L) / PLOT_W * self.view.duration))

    # mouse
    def _on_press(self, e):
        if OV_T - 2 <= e.y <= OV_T + OV_H + 2:
            self._mode = "ov"
            self._center_at(e.x)
        elif e.y >= MAIN_T - 4:
            self._mode   = "sel"
            self._anchor = self.time_at_x(e.x)
            self._px     = e.x

    def _on_drag(self, e):
        if self._mode == "ov":
            self._center_at(e.x)
        elif self._mode == "sel" and abs(e.x - self._px) >= 3:
            self.view.set_selection(self._anchor, self.time_at_x(e.x))

    def _on_release(self, e):
        if self._mode == "sel" and abs(e.x - self._px) < 3:
            self.view.set_selection(None)       # plain click clears
        self._mode = None

    def _center_at(self, x):
        t    = self.ov_x2t(x)
        half = 0.5 * self.view.span
        self.view.set(t - half, t + half)

    # drawing
    def draw(self):
        v = self.view
        self.delete("all")

        # overview row: whole file + current view window
        self.create_rectangle(PAD_L, OV_T, PAD_L + PLOT_W, OV_T + OV_H,
                              fill="#0e0e1a", outline="#2a2a4a")
        draw_wave(self, self.wd, 0.0, v.duration, PAD_L, PLOT_W,
                  OV_T + OV_H / 2, OV_H / 2 * 0.9, OV_COLOR, ("ov",), self.ov_t2x)
        if v.sel:
            self.create_rectangle(self.ov_t2x(v.sel[0]), OV_T,
                                  self.ov_t2x(v.sel[1]), OV_T + OV_H,
                                  outline="#6a6aa0", dash=(2, 2))
        xa, xb = self.ov_t2x(v.t0), self.ov_t2x(v.t1)
        if xb - xa < 3:
            xa, xb = xa - 1.5, xb + 1.5
        self.create_rectangle(xa, OV_T, xb, OV_T + OV_H,
                              outline=VIEW_COLOR, width=2)
        self.create_text(PAD_L - 5, OV_T + OV_H / 2, text="all",
                         anchor="e", fill="#6666aa", font=("Courier", 8))

        # main waveform
        cy = MAIN_T + MAIN_H / 2
        self.create_rectangle(PAD_L, MAIN_T, PAD_L + PLOT_W, MAIN_T + MAIN_H,
                              fill="#0e0e1a", outline="#2a2a4a")
        if v.sel:
            a, b = max(v.sel[0], v.t0), min(v.sel[1], v.t1)
            if b > a:
                self.create_rectangle(self.t2x(a), MAIN_T, self.t2x(b),
                                      MAIN_T + MAIN_H, fill=SEL_FILL, outline="")
            for edge in v.sel:
                if v.t0 <= edge <= v.t1:
                    x = self.t2x(edge)
                    self.create_line(x, MAIN_T, x, MAIN_T + MAIN_H,
                                     fill=VIEW_COLOR, dash=(3, 3))
        for t, lbl in _time_ticks(v.t0, v.t1):
            x = self.t2x(t)
            self.create_line(x, MAIN_T, x, MAIN_T + MAIN_H,
                             fill="#2a2a4a", dash=(3, 5))
            self.create_text(x, MAIN_T + MAIN_H + 6, text=lbl,
                             anchor="n", fill="#6666aa", font=("Courier", 8))
        self.create_line(PAD_L, cy, PAD_L + PLOT_W, cy, fill="#3a3a5e")
        draw_wave(self, self.wd, v.t0, v.t1, PAD_L, PLOT_W,
                  cy, MAIN_H / 2 * 0.95, WAVE_COLOR, ("wave",), self.t2x)
        for amp, lbl in ((1.0, "+1"), (0.0, "0"), (-1.0, "-1")):
            self.create_text(PAD_L - 5, cy - amp * MAIN_H / 2 * 0.95, text=lbl,
                             anchor="e", fill="#8888aa", font=("Courier", 8))
        self.create_text(8, cy, text="Wave", anchor="center",
                         fill=WAVE_COLOR, font=("Helvetica", 9, "bold"), angle=90)
        if not self.wd.ok:
            self.create_text(PAD_L + PLOT_W / 2, cy,
                             text=self.wd.msg + "  —  zoom still works",
                             fill="#606090", font=("Courier", 9))


# ─────────────────────────────────────────────
# BREAKPOINT EDITOR CANVAS
# ─────────────────────────────────────────────
class BreakpointEditor(tk.Canvas):
    def __init__(self, parent, duration, lane, view, wave_data=None, **kwargs):
        super().__init__(parent,
                         width=CANVAS_W, height=CANVAS_H,
                         bg="#12121e", highlightthickness=0, **kwargs)
        self.duration  = duration
        self.lane      = lane
        self.view      = view
        self.wd        = wave_data
        self.points    = [[0.0, lane['y_default']],
                          [duration, lane['y_default']]]
        self._drag_idx = None
        self.bind("<ButtonPress-1>",   self._on_press)
        self.bind("<B1-Motion>",       self._on_drag)
        self.bind("<ButtonRelease-1>", self._on_release)
        self.bind("<ButtonPress-3>",   self._on_right)
        if IS_MAC:
            # macOS Tk reports the right button as Button-2 (and Ctrl-click)
            self.bind("<ButtonPress-2>",         self._on_right)
            self.bind("<Control-ButtonPress-1>", self._on_right)
        self.draw()

    # ── coord transforms (through the shared view window) ─────────
    def t2x(self, t):
        v = self.view
        return PAD_L + (t - v.t0) / v.span * PLOT_W

    def x2t(self, x):
        v = self.view
        t = v.t0 + (x - PAD_L) / PLOT_W * v.span
        return max(v.t0, min(v.t1, max(0.0, min(self.duration, t))))

    time_at_x = x2t

    def _visible(self, t):
        return self.view.t0 - 1e-12 <= t <= self.view.t1 + 1e-12

    def v2y(self, v):
        lo, hi = self.lane['y_min'], self.lane['y_max']
        if self.lane.get('log_scale'):
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
            log_lo = math.log10(lo)
            log_hi = math.log10(hi)
            v = 10.0 ** (log_lo + norm * (log_hi - log_lo))
        else:
            v = lo + norm * (hi - lo)
        return max(lo, min(hi, v))

    # ── hit test (visible points only) ────────────────────────────
    def _find(self, x, y):
        for i, (t, v) in enumerate(self.points):
            if not self._visible(t):
                continue
            if (x - self.t2x(t))**2 + (y - self.v2y(v))**2 <= (POINT_R * 2)**2:
                return i
        return None

    # ── mouse ─────────────────────────────────────────────────────
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
            self._draw_env()

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
        self._draw_env()

    def _on_release(self, e):
        self._drag_idx = None

    def _on_right(self, e):
        idx = self._find(e.x, e.y)
        if idx not in (None, 0, len(self.points) - 1):
            self.points.pop(idx)
            self._draw_env()

    # ── drawing ───────────────────────────────────────────────────
    def draw(self):
        """Full redraw (view changed). Point edits use _draw_env()."""
        self.delete("all")
        self._bg()
        self._selection()
        self._grid()
        if self.view.ghost:
            draw_wave(self, self.wd, self.view.t0, self.view.t1, PAD_L, PLOT_W,
                      PAD_T + PLOT_H / 2, PLOT_H / 2 * 0.92,
                      GHOST_COLOR, ("wave",), self.t2x)
        self._draw_env()

    def _draw_env(self):
        self.delete("env")
        self._envelope()
        self._points()

    def _bg(self):
        self.create_rectangle(PAD_L, PAD_T,
                               PAD_L + PLOT_W, PAD_T + PLOT_H,
                               fill="#0e0e1a", outline="#2a2a4a")

    def _selection(self):
        v = self.view
        if not v.sel:
            return
        a, b = max(v.sel[0], v.t0), min(v.sel[1], v.t1)
        if b > a:
            self.create_rectangle(self.t2x(a), PAD_T, self.t2x(b), PAD_T + PLOT_H,
                                  fill="#191930", outline="")

    def _grid(self):
        lane = self.lane
        for v, lbl in lane['y_ticks']:
            y   = self.v2y(v)
            col = "#4a4a6e" if v != lane['y_default'] else "#7a7aae"
            w   = 1         if v != lane['y_default'] else 2
            dk  = ()        if v == lane['y_default'] else (4, 4)
            self.create_line(PAD_L, y, PAD_L + PLOT_W, y,
                             fill=col, width=w, dash=dk)
            self.create_text(PAD_L - 5, y, text=lbl,
                             anchor="e", fill="#8888aa", font=("Courier", 8))

        for t, lbl in _time_ticks(self.view.t0, self.view.t1):
            x = self.t2x(t)
            self.create_line(x, PAD_T, x, PAD_T + PLOT_H,
                             fill="#2a2a4a", dash=(3, 5))
            self.create_text(x, PAD_T + PLOT_H + 14, text=lbl,
                             anchor="n", fill="#6666aa", font=("Courier", 8))

        unit = f" ({lane['unit']})" if lane['unit'] else ""
        self.create_text(8, PAD_T + PLOT_H // 2,
                         text=lane['label'] + unit,
                         anchor="center", fill=lane['color'],
                         font=("Helvetica", 9, "bold"), angle=90)

    def _visible_polyline(self):
        """Envelope clipped to the view: interpolated edges + inner points."""
        pts = sorted(self.points, key=lambda p: p[0])
        t0, t1 = self.view.t0, self.view.t1
        vis = [[t0, _interp(pts, t0)]]
        vis += [p for p in pts if t0 < p[0] < t1]
        vis.append([t1, _interp(pts, t1)])
        return vis

    def _envelope(self):
        if len(self.points) < 2:
            return
        vis = self._visible_polyline()
        coords = []
        for t, v in vis:
            coords += [self.t2x(t), self.v2y(v)]

        def_y = self.v2y(self.lane['y_default'])
        poly  = [PAD_L, def_y] + coords + [PAD_L + PLOT_W, def_y]
        self.create_polygon(*poly, fill=self.lane['fill'],
                            outline="", stipple="gray25",
                            tags=("env", "envfill"))
        # keep the ghost waveform visible above the fill (macOS ignores stipple)
        if self.find_withtag("wave"):
            self.tag_lower("envfill", "wave")
        self.create_line(*coords, fill=self.lane['color'], width=2, tags="env")

    def _points(self):
        n = len(self.points)
        for i, (t, v) in enumerate(self.points):
            if not self._visible(t):
                continue
            x   = self.t2x(t)
            y   = self.v2y(v)
            col = "#ffaa44" if i in (0, n-1) else self.lane['color']
            self.create_oval(x-POINT_R, y-POINT_R, x+POINT_R, y+POINT_R,
                             fill=col, outline="#ffffff", width=1, tags="env")
            unit = self.lane['unit']
            lbl  = f"{v:+.2f}{unit}" if unit else f"{v:+.2f}"
            self.create_text(x, y - POINT_R - 5, text=lbl,
                             anchor="s", fill="#ddddff", font=("Courier", 8),
                             tags="env")

    def reset(self):
        self.points = [[0.0, self.lane['y_default']],
                       [self.duration, self.lane['y_default']]]
        self._draw_env()

    def get_breakpoints(self):
        return [[t, v] for t, v in sorted(self.points, key=lambda p: p[0])]


# ─────────────────────────────────────────────
# MAIN APP
# ─────────────────────────────────────────────
class EnvelopeEditorApp:

    def __init__(self, duration, output_path, wave_path=None):
        self.duration    = duration
        self.output_path = output_path
        self.cancelled   = True

        # Pre-load previously-applied curves if the breakpoints file already
        # exists. Praat's render-and-iterate audition loop relaunches this GUI
        # with the same output path so each pass continues from the last edit.
        self._preset = None
        try:
            if os.path.exists(output_path):
                with open(output_path, 'r', encoding='utf-8') as f:
                    self._preset = json.load(f)
        except Exception:
            self._preset = None

        # ── Waveform + shared view ────────────────────────────────
        self.wave = WaveData(wave_path)
        self.view = ViewState(duration, self.wave.sr if self.wave.ok else None)
        self.view.listeners.append(self._on_view_change)

        # ── Window ────────────────────────────────────────────────
        self.root = tk.Tk()
        self.root.title("Envelope Editor — Praat AudioTools")
        self.root.resizable(False, False)
        self.root.configure(bg="#12121e")
        self.root.protocol("WM_DELETE_WINDOW", self._on_cancel)

        # ── Header ────────────────────────────────────────────────
        hdr = tk.Frame(self.root, bg="#12121e", pady=5)
        hdr.pack(fill="x", padx=10)
        tk.Label(hdr,
                 text=f"  Duration: {duration:.3f}s   "
                      f"(DSP applied by Praat after closing)",
                 bg="#12121e", fg="#9090c0",
                 font=("Courier", 10)).pack(side="left")
        tk.Label(hdr,
                 text="Left-click: add/drag   Right-click: delete",
                 bg="#12121e", fg="#505070",
                 font=("Helvetica", 9)).pack(side="right")

        # ── Waveform strip (fixed, not scrolled) ──────────────────
        wf = tk.Frame(self.root, bg="#1a1a2e", pady=2)
        wf.pack(fill="x", padx=10, pady=(0, 2))
        self.strip = WaveformStrip(wf, self.view, self.wave)
        self.strip.pack()

        # ── Zoom toolbar ──────────────────────────────────────────
        tb = tk.Frame(self.root, bg="#12121e")
        tb.pack(fill="x", padx=10, pady=(0, 2))
        tbtn = dict(relief="flat", padx=6, pady=1, font=("Helvetica", 9),
                    bg="#22223a", fg="#c0c0e0", activebackground="#33335a")
        for txt, cmd in (("Zoom in",  lambda: self.view.zoom(2.0)),
                         ("Zoom out", lambda: self.view.zoom(0.5)),
                         ("Zoom sel", self._zoom_sel),
                         ("Show all", self.view.fit),
                         ("◀",        lambda: self.view.pan(-0.25 * self.view.span)),
                         ("▶",        lambda: self.view.pan(0.25 * self.view.span))):
            tk.Button(tb, text=txt, command=cmd, **tbtn).pack(side="left", padx=2)
        self.ghost_var = tk.BooleanVar(value=True)
        tk.Checkbutton(tb, text="Wave in lanes", variable=self.ghost_var,
                       command=self._toggle_ghost,
                       bg="#12121e", fg="#9090c0", selectcolor="#22223a",
                       activebackground="#12121e", activeforeground="#c0c0e0",
                       font=("Helvetica", 9)).pack(side="left", padx=8)
        self.view_var = tk.StringVar()
        tk.Label(tb, textvariable=self.view_var, bg="#12121e", fg="#6666aa",
                 font=("Courier", 9)).pack(side="right")
        mod = "Cmd" if IS_MAC else "Ctrl"
        tk.Label(self.root,
                 text=f"{mod}+wheel: zoom   Shift+wheel: scroll   "
                      f"drag waveform: select (Z = zoom to it)   "
                      f"+ / - / 0   \u2190 \u2192",
                 bg="#12121e", fg="#505070",
                 font=("Helvetica", 8)).pack(fill="x", padx=14)

        # ── Scrollable canvas area ─────────────────────────────────
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

        # ── Lane editors ──────────────────────────────────────────
        self.editors = {}
        for lane in LANES:
            frame = tk.Frame(self.inner, bg="#1a1a2e", pady=2)
            frame.pack(fill="x", padx=4, pady=3)
            ed = BreakpointEditor(frame, self.duration, lane, self.view, self.wave)
            if self._preset and isinstance(self._preset.get(lane['key']), list):
                try:
                    pts = [[max(0.0, min(self.duration, float(t))), float(v)]
                           for t, v in self._preset[lane['key']]]
                    if len(pts) >= 2:
                        pts.sort(key=lambda p: p[0])
                        pts[0][0]  = 0.0
                        pts[-1][0] = self.duration
                        ed.points  = pts
                        ed.draw()
                except Exception:
                    pass
            ed.pack()
            self.editors[lane['key']] = ed

        # v2.3: 820 -> 680 so the new waveform strip doesn't grow the window
        visible_h = min(4 * CANVAS_H + 60, 680)
        self.scroll_canvas.configure(height=visible_h, width=CANVAS_W + 20)

        # ── Wheel + keyboard ──────────────────────────────────────
        self.root.bind_all("<MouseWheel>", self._on_wheel)
        self.root.bind_all("<Button-4>", lambda e: self._on_wheel(e, +1))
        self.root.bind_all("<Button-5>", lambda e: self._on_wheel(e, -1))
        for seq in ("<Key-plus>", "<Key-equal>", "<Key-KP_Add>"):
            self.root.bind(seq, lambda e: self.view.zoom(2.0))
        for seq in ("<Key-minus>", "<Key-KP_Subtract>"):
            self.root.bind(seq, lambda e: self.view.zoom(0.5))
        self.root.bind("<Key-0>", lambda e: self.view.fit())
        self.root.bind("<Key-z>", lambda e: self._zoom_sel())
        self.root.bind("<Key-Left>",  lambda e: self.view.pan(-0.25 * self.view.span))
        self.root.bind("<Key-Right>", lambda e: self.view.pan(0.25 * self.view.span))

        # ── Status bar ────────────────────────────────────────────
        self.status_var = tk.StringVar(value="Ready." if self.wave.ok
                                       else f"Ready ({self.wave.msg}).")
        tk.Label(self.root, textvariable=self.status_var,
                 bg="#12121e", fg="#606090",
                 font=("Courier", 9), anchor="w").pack(fill="x", padx=14, pady=2)

        # ── Buttons ───────────────────────────────────────────────
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

        tk.Button(btn_frame, text="  ▶  Audition  ",
                  command=self._on_audition,
                  bg="#4e4220", fg="#fff0b0",
                  activebackground="#6a5a2a",
                  font=("Helvetica", 11, "bold"),
                  relief="flat", padx=14, pady=4).pack(side="left", padx=8)

        tk.Button(btn_frame, text="  ✓  Apply  ",
                  command=self._on_apply,
                  bg="#2a4e2a", fg="#c0e0c0",
                  activebackground="#3a6a3a",
                  font=("Helvetica", 11, "bold"),
                  relief="flat", padx=14, pady=4).pack(side="left", padx=8)

        self._update_view_label()

    # ── View / zoom ───────────────────────────────────────────────

    def _on_view_change(self):
        self.strip.draw()
        for ed in self.editors.values():
            ed.draw()
        self._update_view_label()

    def _update_view_label(self):
        v = self.view
        z = v.duration / v.span if v.span > 0 else 1.0
        txt = f"view {v.t0:.3f}–{v.t1:.3f}s  ×{z:.1f}"
        if v.sel:
            txt += f"   sel {v.sel[1] - v.sel[0]:.3f}s"
        self.view_var.set(txt)

    def _zoom_sel(self):
        if self.view.sel and self.view.sel[1] > self.view.sel[0]:
            self.view.set(*self.view.sel)
        else:
            self.status_var.set("No selection — drag across the waveform first.")

    def _toggle_ghost(self):
        self.view.ghost = bool(self.ghost_var.get())
        for ed in self.editors.values():
            ed.draw()

    def _wheel_time(self, e):
        w = e.widget
        if isinstance(w, (BreakpointEditor, WaveformStrip)):
            return w.time_at_x(e.x)
        return None

    def _on_wheel(self, e, direction=None):
        if direction is None:
            d = getattr(e, "delta", 0)
            direction = 1 if d > 0 else (-1 if d < 0 else 0)
        if direction == 0:
            return
        zoom_mask = 0x0004 | (0x0008 if IS_MAC else 0)   # Ctrl (+Cmd on macOS)
        if e.state & zoom_mask:
            self.view.zoom(1.25 if direction > 0 else 0.8, self._wheel_time(e))
        elif e.state & 0x0001:                             # Shift
            self.view.pan(-direction * 0.1 * self.view.span)
        else:
            self.scroll_canvas.yview_scroll(-direction, "units")

    # ── Callbacks ─────────────────────────────────────────────────

    def _on_reset(self):
        for ed in self.editors.values():
            ed.reset()
        self.status_var.set("All lanes reset to defaults.")

    def _on_cancel(self):
        self.cancelled = True
        self.root.destroy()

    def _save_breakpoints(self, marker_suffix):
        breakpoints = {key: ed.get_breakpoints()
                       for key, ed in self.editors.items()}
        with open(self.output_path, "w", encoding="utf-8") as f:
            json.dump(breakpoints, f, indent=2)
        # Marker files tell Praat which GUI action closed the editor.  The JSON
        # itself deliberately persists so the next Audition/Tweak pass can
        # preload exactly the curves the user just heard.
        for suffix in (".applied", ".audition"):
            try:
                path = self.output_path + suffix
                if os.path.exists(path):
                    os.remove(path)
            except OSError:
                pass
        with open(self.output_path + marker_suffix, "w", encoding="utf-8") as f:
            f.write("ok")
        self.cancelled = False

    def _on_audition(self):
        self._save_breakpoints(".audition")
        self.status_var.set("Audition requested — Praat will render/play, then reopen the editor.")
        self.root.after(180, self.root.destroy)

    def _on_apply(self):
        self._save_breakpoints(".applied")
        self.status_var.set("Breakpoints saved — Praat will now apply DSP.")
        self.root.after(180, self.root.destroy)

    def run(self):
        self.root.mainloop()
        return not self.cancelled


# ─────────────────────────────────────────────
# DSP HELPERS  (no GUI imports needed)
# ─────────────────────────────────────────────
import math
import wave
import array as _array

FILTER_NEUTRAL = 1000.0
FILTER_LO      =  300.0
FILTER_HI      = 3000.0


def _interp(bp, t):
    """Linear interpolation over [[time, value], ...] breakpoints."""
    if t <= bp[0][0]:
        return bp[0][1]
    if t >= bp[-1][0]:
        return bp[-1][1]
    for i in range(len(bp) - 1):
        t0, v0 = bp[i]
        t1, v1 = bp[i + 1]
        if t0 <= t <= t1:
            return v0 + (t - t0) / (t1 - t0) * (v1 - v0) if t1 > t0 else v0
    return bp[-1][1]


def _interp_series(bp, n_samples, sr):
    """Evaluate sorted breakpoints at relative sample times in O(N+B).

    This is numerically equivalent to repeated _interp(bp, i/sr), but avoids
    rescanning every breakpoint for every audio sample.  Breakpoint times are
    intentionally RELATIVE to the selected Sound (0..duration), independent of
    the Sound object's xmin.
    """
    bp = sorted([[float(t), float(v)] for t, v in bp], key=lambda p: p[0])
    if not bp:
        return [0.0] * n_samples
    out = [0.0] * n_samples
    seg = 0
    last = len(bp) - 1
    for i in range(n_samples):
        t = i / float(sr)
        while seg < last - 1 and t > bp[seg + 1][0]:
            seg += 1
        if t <= bp[0][0]:
            v = bp[0][1]
        elif t >= bp[-1][0]:
            v = bp[-1][1]
        else:
            t0, v0 = bp[seg]
            t1, v1 = bp[seg + 1]
            v = v0 + (t - t0) / (t1 - t0) * (v1 - v0) if t1 > t0 else v0
        out[i] = v
    return out


def _write_wav(path, data, sr):
    """Write float list as 16-bit mono WAV + .peak sidecar for Praat rescaling."""
    peak = max(abs(x) for x in data) or 1.0
    scaled = [max(-32767, min(32767, int(x / peak * 32767))) for x in data]
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(_array.array('h', scaled).tobytes())
    with open(path + '.peak', 'w') as f:
        f.write(str(peak))


def _mode_envelopes(args):
    """
    Interpolate intensity + pan envelopes and write gain WAVs.
    Usage: envelope_editor.py envelopes <bp.json> <n_samples> <sr> <t_start>
                              <gain_intens.wav> <gain_panL.wav> <gain_panR.wav>
                              <pitch.txt> <filter.txt>
    """
    bp_path     = args[0]
    n_samples   = int(args[1])
    sr          = int(args[2])
    t_start     = float(args[3])
    path_intens = args[4]
    path_panL   = args[5]
    path_panR   = args[6]
    path_pitch  = args[7]
    path_filter = args[8]

    with open(bp_path, 'r', encoding='utf-8') as f:
        d = json.load(f)

    ibp = d['intensity']
    pbp = d['pan']

    # Breakpoints are defined in editor-relative time (0..duration).  The old
    # code added Sound.xmin here, which shifted every envelope on Sounds whose
    # time domain did not start at zero.  Keep t_start only for CLI compatibility.
    _ = t_start
    intens_db = _interp_series(ibp, n_samples, sr)
    pan_pos   = _interp_series(pbp, n_samples, sr)
    gi = [10 ** (v / 20.0) for v in intens_db]
    gl, gr = [], []
    for p in pan_pos:
        a = (p + 1.0) / 2.0 * (math.pi / 2.0)
        gl.append(math.cos(a))
        gr.append(math.sin(a))

    _write_wav(path_intens, gi, sr)
    _write_wav(path_panL,   gl, sr)
    _write_wav(path_panR,   gr, sr)

    with open(path_pitch, 'w') as f:
        f.write('\n'.join(f"{t} {v}" for t, v in d['pitch']))
    with open(path_filter, 'w') as f:
        f.write('\n'.join(f"{t} {v}" for t, v in d['filter']))

    print("envelope_editor [envelopes]: done.")


def _mode_filter(args):
    """
    Compute 3-way filter blend weights and write gain WAVs.
    Usage: envelope_editor.py filter <filter.txt> <sr> <n_samples> <t_start>
                              <wLP.wav> <wHP.wav> <wDry.wav>
    """
    filter_txt = args[0]
    sr         = int(args[1])
    n_samples  = int(args[2])
    t_start    = float(args[3])
    path_lp    = args[4]
    path_hp    = args[5]
    path_dry   = args[6]

    rows = [line.split() for line in open(filter_txt).read().strip().splitlines()]
    bp   = [[float(r[0]), float(r[1])] for r in rows]

    wlp, whp, wdr = [], [], []

    # Same relative-time convention as the other lanes.  `t_start` remains in
    # the CLI for backward compatibility but must not offset editor time.
    _ = t_start
    fc_series = _interp_series(bp, n_samples, sr)
    for fc in fc_series:
        if fc < FILTER_NEUTRAL:
            w = min((FILTER_NEUTRAL - fc) / (FILTER_NEUTRAL - FILTER_LO), 1.0)
            wlp.append(w);  whp.append(0.0); wdr.append(1.0 - w)
        else:
            w = min((fc - FILTER_NEUTRAL) / (FILTER_HI - FILTER_NEUTRAL), 1.0)
            wlp.append(0.0); whp.append(w);  wdr.append(1.0 - w)

    _write_wav(path_lp,  wlp, sr)
    _write_wav(path_hp,  whp, sr)
    _write_wav(path_dry, wdr, sr)

    print("envelope_editor [filter]: done.")


# ─────────────────────────────────────────────
# ENTRY POINT
# ─────────────────────────────────────────────
def main():
    if len(sys.argv) < 2:
        print("Usage: envelope_editor.py  gui <duration> <bp.json> [wave.wav]")
        print("       envelope_editor.py  envelopes <bp.json> <n> <sr> <t0> ...")
        print("       envelope_editor.py  filter <filter.txt> <sr> <n> <t0> ...")
        sys.exit(1)

    mode = sys.argv[1]

    if mode == 'envelopes':
        _mode_envelopes(sys.argv[2:])

    elif mode == 'filter':
        _mode_filter(sys.argv[2:])

    elif mode == 'gui':
        if len(sys.argv) < 4:
            print("Usage: envelope_editor.py gui <duration_seconds> <breakpoints_out.json> [wave.wav]")
            sys.exit(1)
        duration    = float(sys.argv[2])
        output_path = sys.argv[3]
        wave_path   = sys.argv[4] if len(sys.argv) > 4 else None
        app     = EnvelopeEditorApp(duration, output_path, wave_path)
        success = app.run()
        if success:
            print(f"Breakpoints written: {output_path}")
            sys.exit(0)
        else:
            print("Cancelled.")
            sys.exit(1)

    else:
        # Legacy: no mode keyword — treat first arg as duration (old GUI call)
        try:
            duration    = float(sys.argv[1])
            output_path = sys.argv[2]
            app     = EnvelopeEditorApp(duration, output_path)
            success = app.run()
            sys.exit(0 if success else 1)
        except (ValueError, IndexError):
            print(f"Unknown mode: {mode}")
            sys.exit(1)


if __name__ == "__main__":
    main()

