#!/usr/bin/env python3
# ============================================================
# Praat AudioTools Plugin
# Script:      envelope_editor.py
# Author:      Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version:     2.1 (2026) - Pre-load + Apply marker (for Praat audition loop)
# License:     MIT License
# Repository:  https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Multi-lane breakpoint envelope editor GUI.
#   All DSP (pitch, intensity, pan, filter) is performed by Praat
#   after the GUI closes — this script only collects the breakpoints.
#
#   Lanes:
#     1. Pan        — stereo position  (-1 L … 0 C … +1 R)
#     2. Pitch      — semitone shift   (-12 … 0 … +12 st)
#     3. Intensity  — gain in dB       (-24 … 0 … +24 dB)
#     4. Filter     — cutoff freq (Hz) (80 … 1000 neutral … 16000)
#
# Usage (called by Praat):
#   python envelope_editor.py  <duration_seconds>  <breakpoints_out.json>
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
#   tkinter — standard Python (no pip installs required)
# ============================================================

import sys
import os
import json
import tkinter as tk
from tkinter import ttk

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

    # ── coord transforms ──────────────────────────────────────────
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

    # ── hit test ──────────────────────────────────────────────────
    def _find(self, x, y):
        for i, (t, v) in enumerate(self.points):
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

    # ── drawing ───────────────────────────────────────────────────
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
        for v, lbl in lane['y_ticks']:
            y   = self.v2y(v)
            col = "#4a4a6e" if v != lane['y_default'] else "#7a7aae"
            w   = 1         if v != lane['y_default'] else 2
            dk  = ()        if v == lane['y_default'] else (4, 4)
            self.create_line(PAD_L, y, PAD_L + PLOT_W, y,
                             fill=col, width=w, dash=dk)
            self.create_text(PAD_L - 5, y, text=lbl,
                             anchor="e", fill="#8888aa", font=("Courier", 8))

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

        def_y = self.v2y(self.lane['y_default'])
        poly  = [PAD_L, def_y]
        for t, v in pts:
            poly += [self.t2x(t), self.v2y(v)]
        poly += [PAD_L + PLOT_W, def_y]
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
        return [[t, v] for t, v in sorted(self.points, key=lambda p: p[0])]


# ─────────────────────────────────────────────
# MAIN APP
# ─────────────────────────────────────────────
class EnvelopeEditorApp:

    def __init__(self, duration, output_path):
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
            ed = BreakpointEditor(frame, self.duration, lane)
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

        visible_h = min(4 * CANVAS_H + 60, 820)
        self.scroll_canvas.configure(height=visible_h, width=CANVAS_W + 20)

        self.root.bind_all("<MouseWheel>",
            lambda e: self.scroll_canvas.yview_scroll(-1*(e.delta//120), "units"))

        # ── Status bar ────────────────────────────────────────────
        self.status_var = tk.StringVar(value="Ready.")
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

        tk.Button(btn_frame, text="  ▶  Apply  ",
                  command=self._on_apply,
                  bg="#2a4e2a", fg="#c0e0c0",
                  activebackground="#3a6a3a",
                  font=("Helvetica", 11, "bold"),
                  relief="flat", padx=14, pady=4).pack(side="left", padx=8)

    # ── Callbacks ─────────────────────────────────────────────────

    def _on_reset(self):
        for ed in self.editors.values():
            ed.reset()
        self.status_var.set("All lanes reset to defaults.")

    def _on_cancel(self):
        self.cancelled = True
        self.root.destroy()

    def _on_apply(self):
        breakpoints = {key: ed.get_breakpoints()
                       for key, ed in self.editors.items()}
        with open(self.output_path, "w", encoding="utf-8") as f:
            json.dump(breakpoints, f, indent=2)
        # Marker file: tells Praat the user pressed Apply (vs. cancelled),
        # even though the breakpoints file persists between audition passes.
        try:
            with open(self.output_path + ".applied", "w", encoding="utf-8") as f:
                f.write("ok")
        except Exception:
            pass
        self.status_var.set("Breakpoints saved — Praat will now apply DSP.")
        self.cancelled = False
        self.root.after(400, self.root.destroy)

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
    gi, gl, gr = [], [], []

    for i in range(n_samples):
        t = t_start + i / sr
        gi.append(10 ** (_interp(ibp, t) / 20.0))
        a = (_interp(pbp, t) + 1.0) / 2.0 * (math.pi / 2.0)
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

    for i in range(n_samples):
        t  = t_start + i / sr
        fc = _interp(bp, t)
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
        print("Usage: envelope_editor.py  gui <duration> <bp.json>")
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
            print("Usage: envelope_editor.py gui <duration_seconds> <breakpoints_out.json>")
            sys.exit(1)
        duration    = float(sys.argv[2])
        output_path = sys.argv[3]
        app     = EnvelopeEditorApp(duration, output_path)
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

