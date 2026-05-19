#!/usr/bin/env python3
# ============================================================
# Praat AudioTools Plugin
# Script:      arranger.py
# Author:      Shai Cohen
# Version:     1.3 (2026) — fixes 8-bit + 24-bit WAV decoding
# License:     MIT License
#
# Changelog v1.3:
#   - FIXED: 8-bit WAV decoding produced DC offset + 2x amplitude.
#     8-bit WAV is unsigned (0-255, centered at 128); v1.2 did
#     `s * (1/128)` on raw bytes, giving values in [0, 1.99] with
#     a +1.0 DC offset. v1.3 subtracts 128 first.
#   - FIXED: 24-bit WAV (sample width = 3) was completely broken.
#     v1.2's else-branch caught both 8-bit AND 24-bit and treated
#     both as unsigned bytes. v1.3 properly unpacks 3-byte little-
#     endian signed integers and scales by 2^23.
#   - 16-bit and 32-bit decoding paths are unchanged. Since Praat
#     saves 16-bit by default, v1.3 is bit-identical to v1.2 for
#     typical AudioTools sessions. Only edge-case inputs (8-bit
#     or 24-bit source WAVs) behave differently.
#
# New in 1.2:
#   - Per-clip gain  (-24 … +24 dB)  via right-click popup
#   - Per-clip pan   (-1 L … 0 C … +1 R)  via right-click popup
#   - Fade-in / fade-out handles at clip edges (drag horizontally)
#   - Gain + pan shown as text labels inside each clip
#
# Usage (called by Praat):
#   python arranger.py <manifest.json>
# ============================================================

import sys
import os
import json
import math
import wave
import traceback
import array as _array

# ── Top-level error trap ──────────────────────────────────────────────────────
_error_file = None

def _crash(exc):
    tb  = traceback.format_exc()
    msg = f"{type(exc).__name__}: {exc}\n\n{tb}"
    if _error_file:
        try:
            with open(_error_file, 'w', encoding='utf-8') as f:
                f.write(msg)
        except Exception:
            pass
    print(msg, file=sys.stderr)
    sys.exit(1)


# ─────────────────────────────────────────────────────────────────────────────
# LAYOUT CONSTANTS
# ─────────────────────────────────────────────────────────────────────────────
N_LANES          = 4
LANE_H           = 80
RULER_H          = 28
CANVAS_H         = RULER_H + N_LANES * LANE_H   # 348 px
PAD_L            = 40
PAD_R            = 40
CLIP_MARGIN      = 4
FADE_HANDLE_W    = 10    # px half-width of fade handle hit zone
FADE_HANDLE_VIS  = 2     # px half-width of drawn fade handle line
DEFAULT_ZOOM     = 80
MIN_ZOOM         = 10
MAX_ZOOM         = 400

BG           = "#12121e"
RULER_BG     = "#0e0e18"
RULER_FG     = "#8888cc"
LANE_COLORS  = ["#1a1a2e", "#1a2a1a", "#2e1a0a", "#2a1a2e"]
LANE_SEP     = "#2a2a4a"
CLIP_PALETTE = ["#5b9bd5", "#6ab87e", "#e0a050", "#c070c8",
                "#50c0c0", "#c0c050", "#c06060", "#7080c8"]
FADE_COLOR   = "#000000"      # fade triangle fill
FADE_HANDLE  = "#ffdd44"      # fade handle line colour
LABEL_FG     = "#ffffff"
STATUS_FG    = "#606090"

SILENCE_THRESHOLD = 0.0001


# ─────────────────────────────────────────────────────────────────────────────
# CLIP DATA MODEL
# ─────────────────────────────────────────────────────────────────────────────
class Clip:
    def __init__(self, data):
        self.id        = data['id']
        self.name      = data['name']
        self.filename  = data['filename']
        self.duration  = float(data['duration'])
        self.channels  = int(data['channels'])
        self.sr        = int(data['sample_rate'])
        self.lane      = int(data['default_track']) % N_LANES
        self.start     = float(data['default_start'])
        self.color     = CLIP_PALETTE[self.id % len(CLIP_PALETTE)]
        # New per-clip parameters
        self.gain      = 0.0    # dB  –24 … +24
        self.pan       = 0.0    # –1 (L) … 0 (C) … +1 (R)
        self.fade_in   = 0.0    # seconds
        self.fade_out  = 0.0    # seconds
        # Canvas item IDs
        self.rect_id   = None
        self.label_id  = None
        self.time_id   = None

    def reset(self, index):
        self.start    = 0.0
        self.lane     = index % N_LANES
        self.gain     = 0.0
        self.pan      = 0.0
        self.fade_in  = 0.0
        self.fade_out = 0.0


# ─────────────────────────────────────────────────────────────────────────────
# ARRANGER APPLICATION
# ─────────────────────────────────────────────────────────────────────────────
class ArrangerApp:

    def __init__(self, manifest_path):
        import tkinter as tk
        from tkinter import ttk
        self._tk  = tk
        self._ttk = ttk

        with open(manifest_path, 'r', encoding='utf-8') as f:
            manifest = json.load(f)

        self.project_dur = float(manifest['project_duration'])
        self.sample_rate = int(manifest['sample_rate'])
        self.result_file = manifest['result_file']
        self.done_file   = manifest['done_file']
        self.error_file  = manifest.get('error_file', '')
        self.clips       = [Clip(c) for c in manifest['clips']]

        global _error_file
        _error_file = self.error_file

        self.zoom      = DEFAULT_ZOOM
        self.cancelled = True
        self._drag     = None      # active drag state dict
        self._popup    = None      # currently open clip popup

        self._build_ui()

    # ─────────────────────────────────────────────────────────
    # UI CONSTRUCTION
    # ─────────────────────────────────────────────────────────
    def _build_ui(self):
        tk  = self._tk
        ttk = self._ttk

        self.root = tk.Tk()
        self.root.title("Arranger — Praat AudioTools")
        self.root.configure(bg=BG)
        self.root.resizable(True, True)
        self.root.protocol("WM_DELETE_WINDOW", self._on_cancel)

        # Header
        hdr = tk.Frame(self.root, bg=BG, pady=5)
        hdr.pack(fill='x', padx=10)
        tk.Label(hdr,
                 text=f"  {len(self.clips)} clips  |  "
                      f"project: {self.project_dur:.2f} s  |  "
                      f"{self.sample_rate} Hz",
                 bg=BG, fg='#9090c0',
                 font=('Courier', 10)).pack(side='left')
        tk.Label(hdr,
                 text="Left-drag: move   Drag yellow edge: fade   Right-click: gain/pan    ",
                 bg=BG, fg='#505070',
                 font=('Helvetica', 9)).pack(side='right')

        # Zoom row
        zoom_row = tk.Frame(self.root, bg=BG)
        zoom_row.pack(fill='x', padx=10, pady=2)
        tk.Label(zoom_row, text='Zoom:', bg=BG, fg='#8888aa',
                 font=('Helvetica', 9)).pack(side='left')
        self.zoom_var = tk.IntVar(value=DEFAULT_ZOOM)
        tk.Scale(zoom_row,
                 from_=MIN_ZOOM, to=MAX_ZOOM,
                 orient='horizontal',
                 variable=self.zoom_var,
                 command=self._on_zoom,
                 bg=BG, fg='#8888aa',
                 troughcolor='#2a2a4a',
                 highlightthickness=0,
                 length=220,
                 showvalue=True).pack(side='left', padx=8)

        # Canvas + horizontal scrollbar
        c_frame = tk.Frame(self.root, bg=BG)
        c_frame.pack(fill='both', expand=True, padx=6, pady=4)

        self.hscroll = ttk.Scrollbar(c_frame, orient='horizontal')
        self.hscroll.pack(side='bottom', fill='x')

        vis_w = min(960, self._total_canvas_width())
        self.canvas = tk.Canvas(
            c_frame,
            bg=BG,
            width=vis_w,
            height=CANVAS_H,
            scrollregion=(0, 0, self._total_canvas_width(), CANVAS_H),
            xscrollcommand=self.hscroll.set,
            highlightthickness=0)
        self.canvas.pack(side='left', fill='both', expand=True)
        self.hscroll.config(command=self.canvas.xview)

        # Mouse bindings
        self.canvas.bind('<ButtonPress-1>',   self._on_press)
        self.canvas.bind('<B1-Motion>',       self._on_move)
        self.canvas.bind('<ButtonRelease-1>', self._on_release)
        self.canvas.bind('<ButtonPress-3>',   self._on_right_click)
        self.canvas.bind('<MouseWheel>',
            lambda e: self.canvas.xview_scroll(-1*(e.delta//120), 'units'))

        # Status bar
        self.status_var = tk.StringVar(value='Ready.')
        tk.Label(self.root,
                 textvariable=self.status_var,
                 bg=BG, fg=STATUS_FG,
                 font=('Courier', 9),
                 anchor='w').pack(fill='x', padx=14, pady=2)

        # Buttons
        btn_frame = tk.Frame(self.root, bg=BG, pady=7)
        btn_frame.pack()
        btn_style = dict(relief='flat', padx=10, pady=4, font=('Helvetica', 10))

        tk.Button(btn_frame, text=' Reset All ',
                  command=self._on_reset,
                  bg='#2a2a4e', fg='#c0c0e0',
                  activebackground='#3a3a6a',
                  **btn_style).pack(side='left', padx=8)

        tk.Button(btn_frame, text=' Cancel ',
                  command=self._on_cancel,
                  bg='#4e2a2a', fg='#e0c0c0',
                  activebackground='#6a3a3a',
                  **btn_style).pack(side='left', padx=8)

        tk.Button(btn_frame, text='  ▶  Render  ',
                  command=self._on_render,
                  bg='#2a4e2a', fg='#c0e0c0',
                  activebackground='#3a6a3a',
                  font=('Helvetica', 11, 'bold'),
                  relief='flat', padx=14, pady=4).pack(side='left', padx=8)

        self._redraw()

    # ─────────────────────────────────────────────────────────
    # COORDINATE HELPERS
    # ─────────────────────────────────────────────────────────
    def _total_canvas_width(self):
        return max(960, int(self.project_dur * self.zoom) + PAD_L + PAD_R + 120)

    def _t2x(self, t):
        return PAD_L + t * self.zoom

    def _x2t(self, cx):
        return max(0.0, (cx - PAD_L) / self.zoom)

    def _lane2y_top(self, lane):
        return RULER_H + lane * LANE_H

    def _y2lane(self, cy):
        return max(0, min(N_LANES - 1, int((cy - RULER_H) / LANE_H)))

    def _canvas_x(self, event):
        return self.canvas.canvasx(event.x)

    def _canvas_y(self, event):
        return self.canvas.canvasy(event.y)

    # ─────────────────────────────────────────────────────────
    # DRAWING
    # ─────────────────────────────────────────────────────────
    def _redraw(self):
        self.canvas.delete('all')
        self.canvas.configure(
            scrollregion=(0, 0, self._total_canvas_width(), CANVAS_H))
        self._draw_lanes()
        self._draw_ruler()
        for clip in self.clips:
            self._draw_clip(clip)

    def _draw_lanes(self):
        w = self._total_canvas_width()
        for i in range(N_LANES):
            y0 = self._lane2y_top(i)
            y1 = y0 + LANE_H
            self.canvas.create_rectangle(0, y0, w, y1,
                fill=LANE_COLORS[i % len(LANE_COLORS)], outline='')
            self.canvas.create_text(4, y0 + LANE_H // 2,
                text=f'T{i+1}', anchor='w',
                fill='#3a3a60', font=('Courier', 9, 'bold'))
            self.canvas.create_line(0, y1, w, y1, fill=LANE_SEP, width=1)

    def _draw_ruler(self):
        w = self._total_canvas_width()
        self.canvas.create_rectangle(0, 0, w, RULER_H, fill=RULER_BG, outline='')
        step = (0.5 if self.zoom >= 200 else
                1.0 if self.zoom >= 60  else
                2.0 if self.zoom >= 20  else 5.0)
        t = 0.0
        while t <= self.project_dur + 20:
            x = self._t2x(t)
            self.canvas.create_line(x, RULER_H - 8, x, RULER_H, fill=RULER_FG)
            self.canvas.create_text(x, 4, text=f'{t:.1f}', anchor='n',
                fill=RULER_FG, font=('Courier', 7))
            t = round(t + step, 6)

    def _draw_clip(self, clip):
        x0 = self._t2x(clip.start)
        x1 = self._t2x(clip.start + clip.duration)
        y0 = self._lane2y_top(clip.lane) + CLIP_MARGIN
        y1 = self._lane2y_top(clip.lane) + LANE_H - CLIP_MARGIN
        cx = (x0 + x1) / 2
        cy = (y0 + y1) / 2

        # ── Base rectangle ────────────────────────────────────
        self.canvas.create_rectangle(
            x0, y0, x1, y1, fill=clip.color, outline='#ffffff', width=1)

        # ── Fade-in shading (dark triangle at left) ───────────
        if clip.fade_in > 0:
            x_fi = self._t2x(clip.start + clip.fade_in)
            x_fi = min(x_fi, x1)
            self.canvas.create_polygon(
                x0, y0,  x_fi, y0,  x0, y1,
                fill=FADE_COLOR, outline='', stipple='gray50')
            # Handle line
            self.canvas.create_line(
                x_fi, y0, x_fi, y1,
                fill=FADE_HANDLE, width=FADE_HANDLE_VIS * 2, dash=(4, 3))

        # Fade-in handle at left edge even when fade_in=0 (thin yellow tick)
        else:
            self.canvas.create_line(
                x0 + 1, y0, x0 + 1, y1,
                fill=FADE_HANDLE, width=2)

        # ── Fade-out shading (dark triangle at right) ──────────
        if clip.fade_out > 0:
            x_fo = self._t2x(clip.start + clip.duration - clip.fade_out)
            x_fo = max(x_fo, x0)
            self.canvas.create_polygon(
                x_fo, y0,  x1, y0,  x1, y1,
                fill=FADE_COLOR, outline='', stipple='gray50')
            # Handle line
            self.canvas.create_line(
                x_fo, y0, x_fo, y1,
                fill=FADE_HANDLE, width=FADE_HANDLE_VIS * 2, dash=(4, 3))
        else:
            self.canvas.create_line(
                x1 - 1, y0, x1 - 1, y1,
                fill=FADE_HANDLE, width=2)

        # ── Clip name ─────────────────────────────────────────
        name = clip.name if len(clip.name) <= 16 else clip.name[:14] + '…'
        self.canvas.create_text(
            cx, cy - 8, text=name, fill=LABEL_FG,
            font=('Helvetica', 8, 'bold'), anchor='center')

        # ── Start-time stamp ──────────────────────────────────
        self.canvas.create_text(
            x0 + 4, y0 + 4, text=f'{clip.start:.2f}s',
            anchor='nw', fill='#ddddee', font=('Courier', 7))

        # ── Gain label (shown when non-zero) ──────────────────
        gain_txt = f'G {clip.gain:+.1f}dB' if clip.gain != 0.0 else ''

        # ── Pan indicator bar ─────────────────────────────────
        bar_y   = y1 - 10
        bar_x0  = x0 + 6
        bar_x1  = x1 - 6
        bar_mid = (bar_x0 + bar_x1) / 2
        bar_w   = max(bar_x1 - bar_x0, 2)

        if bar_w > 8:
            self.canvas.create_line(bar_x0, bar_y, bar_x1, bar_y,
                fill='#333355', width=2)
            dot_x = bar_mid + clip.pan * (bar_w / 2)
            dot_x = max(bar_x0, min(bar_x1, dot_x))
            self.canvas.create_oval(
                dot_x - 4, bar_y - 4, dot_x + 4, bar_y + 4,
                fill='#ffaa44', outline='')
            pan_txt = (f'L{abs(clip.pan):.2f}' if clip.pan < -0.01 else
                       f'R{clip.pan:.2f}'       if clip.pan > 0.01  else 'C')
        else:
            pan_txt = ''

        # ── Gain + pan text row ───────────────────────────────
        info_parts = [p for p in [gain_txt, pan_txt] if p]
        info_line  = '  '.join(info_parts)
        if info_line:
            self.canvas.create_text(
                cx, cy + 6, text=info_line,
                fill='#ddddaa', font=('Courier', 7), anchor='center')

    # ─────────────────────────────────────────────────────────
    # HIT TESTING
    # ─────────────────────────────────────────────────────────
    def _find_clip(self, cx, cy):
        """Topmost clip body under (cx, cy), or None."""
        for clip in reversed(self.clips):
            x0 = self._t2x(clip.start)
            x1 = self._t2x(clip.start + clip.duration)
            y0 = self._lane2y_top(clip.lane) + CLIP_MARGIN
            y1 = self._lane2y_top(clip.lane) + LANE_H - CLIP_MARGIN
            if x0 <= cx <= x1 and y0 <= cy <= y1:
                return clip
        return None

    def _find_fade_handle(self, cx, cy):
        """Return (clip, 'fade_in'|'fade_out') for the handle nearest cx,cy.
           Fade-in handle  = vertical line at x = t2x(start + fade_in)
                             (or at x = t2x(start) when fade_in=0)
           Fade-out handle = vertical line at x = t2x(start + dur - fade_out)
                             (or at x = t2x(start+dur) when fade_out=0)
        """
        for clip in reversed(self.clips):
            y0 = self._lane2y_top(clip.lane) + CLIP_MARGIN
            y1 = self._lane2y_top(clip.lane) + LANE_H - CLIP_MARGIN
            if not (y0 <= cy <= y1):
                continue

            x_fi = self._t2x(clip.start + clip.fade_in)
            x_fo = self._t2x(clip.start + clip.duration - clip.fade_out)

            # Prioritise fade-out if both handles happen to overlap
            if abs(cx - x_fo) <= FADE_HANDLE_W:
                return clip, 'fade_out'
            if abs(cx - x_fi) <= FADE_HANDLE_W:
                return clip, 'fade_in'

        return None, None

    # ─────────────────────────────────────────────────────────
    # MOUSE HANDLERS
    # ─────────────────────────────────────────────────────────
    def _on_press(self, event):
        cx, cy = self._canvas_x(event), self._canvas_y(event)

        # Fade handles take priority over body drag
        clip, handle = self._find_fade_handle(cx, cy)
        if clip:
            self._drag = {
                'type':          handle,
                'clip':          clip,
                'press_cx':      cx,
                'orig_fade_in':  clip.fade_in,
                'orig_fade_out': clip.fade_out,
            }
            return

        clip = self._find_clip(cx, cy)
        if clip:
            self._drag = {
                'type':       'move',
                'clip':       clip,
                'press_cx':   cx,
                'press_cy':   cy,
                'orig_start': clip.start,
                'orig_lane':  clip.lane,
            }

    def _on_move(self, event):
        if not self._drag:
            return
        cx, cy = self._canvas_x(event), self._canvas_y(event)
        d      = self._drag
        clip   = d['clip']

        if d['type'] == 'move':
            dt        = (cx - d['press_cx']) / self.zoom
            clip.start = max(0.0, d['orig_start'] + dt)
            clip.lane  = self._y2lane(cy)
            self._redraw()
            self.status_var.set(
                f'{clip.name}   start = {clip.start:.3f} s   lane = {clip.lane + 1}')

        elif d['type'] == 'fade_in':
            dt         = (cx - d['press_cx']) / self.zoom
            max_fi     = clip.duration - clip.fade_out - 0.01
            clip.fade_in = max(0.0, min(max_fi, d['orig_fade_in'] + dt))
            self._redraw()
            self.status_var.set(f'{clip.name}   fade-in = {clip.fade_in:.3f} s')

        elif d['type'] == 'fade_out':
            # Drag left → more fade out;  drag right → less
            dt          = (cx - d['press_cx']) / self.zoom
            max_fo      = clip.duration - clip.fade_in - 0.01
            clip.fade_out = max(0.0, min(max_fo, d['orig_fade_out'] - dt))
            self._redraw()
            self.status_var.set(f'{clip.name}   fade-out = {clip.fade_out:.3f} s')

    def _on_release(self, event):
        self._drag = None
        self.status_var.set('Ready.')

    def _on_right_click(self, event):
        cx, cy = self._canvas_x(event), self._canvas_y(event)
        clip   = self._find_clip(cx, cy)
        if clip:
            self._show_clip_popup(clip, event.x_root, event.y_root)

    # ─────────────────────────────────────────────────────────
    # CLIP POPUP  (gain + pan)
    # ─────────────────────────────────────────────────────────
    def _show_clip_popup(self, clip, x_root, y_root):
        tk = self._tk

        # Only one popup at a time
        if self._popup and self._popup.winfo_exists():
            self._popup.destroy()

        pop = tk.Toplevel(self.root)
        pop.title(f'  {clip.name}  ')
        pop.configure(bg=BG)
        pop.resizable(False, False)
        pop.geometry(f'+{x_root + 12}+{y_root}')
        self._popup = pop

        lbl_style = dict(bg=BG, fg='#9090c0', font=('Helvetica', 9))
        scl_style = dict(bg=BG, fg='#c0c0e0', troughcolor='#2a2a4a',
                         highlightthickness=0, orient='horizontal',
                         length=200, relief='flat')

        # ── Gain ──────────────────────────────────────────────
        tk.Label(pop, text='Gain (dB)', **lbl_style).pack(
            anchor='w', padx=12, pady=(10, 0))

        gain_var = tk.DoubleVar(value=clip.gain)
        gain_lbl = tk.Label(pop, text=f'{clip.gain:+.1f} dB', **lbl_style)
        gain_lbl.pack(anchor='e', padx=12)

        def on_gain(val):
            clip.gain = round(float(val) * 2) / 2   # 0.5 dB steps
            gain_var.set(clip.gain)
            gain_lbl.config(text=f'{clip.gain:+.1f} dB')
            self._redraw()

        tk.Scale(pop, from_=-24, to=24, resolution=0.5,
                 variable=gain_var, command=on_gain,
                 **scl_style).pack(padx=12)

        # ── Pan ───────────────────────────────────────────────
        tk.Label(pop, text='Pan', **lbl_style).pack(
            anchor='w', padx=12, pady=(10, 0))

        pan_var = tk.DoubleVar(value=clip.pan)

        def pan_label(p):
            if   p < -0.01: return f'L  {abs(p):.2f}'
            elif p >  0.01: return f'R  {p:.2f}'
            else:           return 'Center'

        pan_lbl = tk.Label(pop, text=pan_label(clip.pan), **lbl_style)
        pan_lbl.pack(anchor='e', padx=12)

        def on_pan(val):
            clip.pan = round(float(val) * 20) / 20   # 0.05 steps
            pan_var.set(clip.pan)
            pan_lbl.config(text=pan_label(clip.pan))
            self._redraw()

        tk.Scale(pop, from_=-1.0, to=1.0, resolution=0.05,
                 variable=pan_var, command=on_pan,
                 **scl_style).pack(padx=12)

        # ── Fade info (read-only display) ──────────────────────
        tk.Frame(pop, bg='#2a2a4a', height=1).pack(fill='x', padx=12, pady=8)
        tk.Label(pop,
                 text=f'Fade in:  {clip.fade_in:.3f} s\n'
                      f'Fade out: {clip.fade_out:.3f} s\n'
                      f'(drag yellow handles on clip)',
                 bg=BG, fg='#505070',
                 font=('Courier', 8),
                 justify='left').pack(anchor='w', padx=12, pady=(0, 4))

        # ── Close ─────────────────────────────────────────────
        tk.Button(pop, text='Close',
                  command=pop.destroy,
                  bg='#2a2a4e', fg='#c0c0e0',
                  relief='flat', padx=10, pady=4,
                  font=('Helvetica', 9)).pack(pady=(4, 10))

    # ─────────────────────────────────────────────────────────
    # BUTTON CALLBACKS
    # ─────────────────────────────────────────────────────────
    def _on_zoom(self, val):
        self.zoom = int(val)
        self._redraw()

    def _on_reset(self):
        for i, clip in enumerate(self.clips):
            clip.reset(i)
        if self._popup and self._popup.winfo_exists():
            self._popup.destroy()
        self._redraw()
        self.status_var.set('All clips reset to default positions.')

    def _on_cancel(self):
        self.cancelled = True
        self.root.destroy()

    def _on_render(self):
        self.status_var.set('Rendering mix…')
        self.root.update()
        try:
            self._render_mix()
            self.cancelled = False
            self.status_var.set('Done — closing.')
            self.root.after(400, self.root.destroy)
        except Exception as exc:
            self.status_var.set(f'ERROR: {exc}')
            try:
                with open(self.error_file, 'w', encoding='utf-8') as f:
                    f.write(traceback.format_exc())
            except Exception:
                pass
            self.cancelled = True

    # ─────────────────────────────────────────────────────────
    # RENDERER
    # ─────────────────────────────────────────────────────────
    def _render_mix(self):
        sr = self.sample_rate
        if self.clips:
            max_end = max(c.start + c.duration for c in self.clips)
        else:
            max_end = 1.0
        n_out = int(math.ceil(max_end * sr)) + sr // 2

        buf_L = [0.0] * n_out
        buf_R = [0.0] * n_out

        for clip in self.clips:
            offset           = int(round(clip.start * sr))
            clip_L, clip_R   = self._load_wav_stereo(clip.filename)
            n_clip           = min(len(clip_L), len(clip_R))
            end_idx          = min(offset + n_clip, n_out)
            n_write          = end_idx - offset

            # Pre-compute per-clip scalars
            gain_linear  = 10.0 ** (clip.gain / 20.0)
            pan_angle    = (clip.pan + 1.0) / 2.0 * (math.pi / 2.0)
            pan_l        = math.cos(pan_angle) * gain_linear
            pan_r        = math.sin(pan_angle) * gain_linear

            fi_samps     = clip.fade_in  * sr   # float samples
            fo_samps     = clip.fade_out * sr

            for i in range(n_write):
                # ── Fade envelope ──────────────────────────────
                fi_gain = (i / fi_samps)         if (fi_samps > 0 and i < fi_samps) else 1.0
                fo_pos  = n_clip - 1 - i
                fo_gain = (fo_pos / fo_samps)    if (fo_samps > 0 and fo_pos < fo_samps) else 1.0
                env     = fi_gain * fo_gain

                # ── Mix into buffer ────────────────────────────
                buf_L[offset + i] += clip_L[i] * pan_l * env
                buf_R[offset + i] += clip_R[i] * pan_r * env

        # Trim trailing silence
        trim = n_out
        while trim > 0 and (abs(buf_L[trim-1]) < SILENCE_THRESHOLD
                            and abs(buf_R[trim-1]) < SILENCE_THRESHOLD):
            trim -= 1
        trim  = max(trim, sr // 10)
        buf_L = buf_L[:trim]
        buf_R = buf_R[:trim]

        # Soft normalize (only attenuate if clipping)
        peak = max(
            max((abs(x) for x in buf_L), default=0.0),
            max((abs(x) for x in buf_R), default=0.0),
            1e-12)
        if peak > 1.0:
            buf_L = [x / peak for x in buf_L]
            buf_R = [x / peak for x in buf_R]

        self._write_stereo_wav(self.result_file, buf_L, buf_R, sr)

        done = {'result':   self.result_file,
                'duration': trim / sr,
                'channels': 2,
                'clips':    len(self.clips)}
        with open(self.done_file, 'w', encoding='utf-8') as f:
            json.dump(done, f, indent=2)

    # ─────────────────────────────────────────────────────────
    # AUDIO I/O
    # ─────────────────────────────────────────────────────────
    def _load_wav_stereo(self, path):
        with wave.open(path, 'rb') as w:
            nch = w.getnchannels()
            sw  = w.getsampwidth()
            n   = w.getnframes()
            raw = w.readframes(n)

        # v1.3: explicit branches for each supported sample width,
        # with proper handling of 8-bit (unsigned, centered at 128)
        # and 24-bit (packed little-endian signed, 3 bytes/sample).
        if sw == 2:
            # 16-bit signed (Praat default)
            arr    = _array.array('h', raw)
            floats = [s * (1.0 / 32768.0) for s in arr]
        elif sw == 4:
            # 32-bit signed integer
            arr    = _array.array('i', raw)
            floats = [s * (1.0 / 2_147_483_648.0) for s in arr]
        elif sw == 3:
            # 24-bit packed little-endian signed. _array doesn't have
            # a typecode for this width, so unpack 3 bytes per sample
            # by hand and sign-extend.
            n_samples = len(raw) // 3
            floats    = [0.0] * n_samples
            scale     = 1.0 / 8388608.0   # 1 / 2^23
            for i in range(n_samples):
                b0 = raw[i * 3]
                b1 = raw[i * 3 + 1]
                b2 = raw[i * 3 + 2]
                u24 = b0 | (b1 << 8) | (b2 << 16)
                # Sign-extend: if top bit set, this is negative
                if u24 & 0x800000:
                    s24 = u24 - 0x1000000
                else:
                    s24 = u24
                floats[i] = s24 * scale
        elif sw == 1:
            # 8-bit UNSIGNED (WAV convention: 0-255, centered at 128).
            # v1.2 forgot to subtract 128 and produced DC offset + 2x
            # amplitude; v1.3 centers first.
            arr    = _array.array('B', raw)
            floats = [(s - 128) * (1.0 / 128.0) for s in arr]
        else:
            raise ValueError(f"Unsupported WAV sample width: {sw} bytes")

        if nch == 1:
            return floats, list(floats)
        return floats[0::2], floats[1::2]

    def _write_stereo_wav(self, path, L, R, sr):
        n  = min(len(L), len(R))
        il = _array.array('h')
        for i in range(n):
            il.append(int(max(-1.0, min(1.0, L[i])) * 32767))
            il.append(int(max(-1.0, min(1.0, R[i])) * 32767))
        with wave.open(path, 'wb') as w:
            w.setnchannels(2); w.setsampwidth(2)
            w.setframerate(sr); w.writeframes(il.tobytes())

    # ─────────────────────────────────────────────────────────
    # RUN
    # ─────────────────────────────────────────────────────────
    def run(self):
        self.root.mainloop()
        return not self.cancelled


# ─────────────────────────────────────────────────────────────────────────────
# ENTRY POINT
# ─────────────────────────────────────────────────────────────────────────────
def main():
    if len(sys.argv) < 2:
        print("Usage: arranger.py <manifest.json>")
        sys.exit(1)

    manifest_path = sys.argv[1]
    if not os.path.isfile(manifest_path):
        print(f"ERROR: manifest not found: {manifest_path}", file=sys.stderr)
        sys.exit(1)

    try:
        app     = ArrangerApp(manifest_path)
        success = app.run()
        sys.exit(0 if success else 1)
    except Exception as exc:
        _crash(exc)


if __name__ == '__main__':
    main()
