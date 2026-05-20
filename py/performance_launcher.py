#!/usr/bin/env python3
# ============================================================
# Praat AudioTools Plugin
# Script:      performance_launcher.py
# Author:      Shai Cohen
# Version:     1.1 (2026) — Cross-platform scroll + header sync
# License:     MIT License
#
# Description:
#   Real-time multichannel audio cue launcher for live performance.
#   Accepts a manifest JSON from PerformanceLauncher.praat, loads
#   each cue into memory, and provides a keyboard-triggered GUI
#   for firing cues to any output channel configuration with
#   per-cue gain, fade-in/out, pan offset, and progress display.
#
# Usage (called by PerformanceLauncher.praat):
#   python performance_launcher.py <manifest.json>
#
# Changelog v1.1:
#   - Cross-platform cue-list scroll: Linux Button-4/Button-5
#     events added alongside Windows/macOS MouseWheel, so the
#     cue list scrolls with the mouse wheel on all platforms.
#   - Header updated to match plugin standard format.
#
# Changelog v1.0.1:
#   - Progress bar and countdown timer added to each cue row.
#   - Temp file cleanup on window close.
#   - AudioEngine.get_cue_progress() for thread-safe position
#     snapshots driving the per-cue UI indicators.
#
# Changelog v1.0:
#   - Initial release. Multichannel OutputStream via sounddevice,
#     real-time mixing with fade-in/out and gain, keyboard cue
#     triggering, device selector, config persistence.
# ============================================================

import sys
import os
import json
import math
import time
import traceback
import threading
import tkinter as tk
from tkinter import ttk
from tkinter import messagebox

# ── Early Dependency Check & Crash Trap ───────────────────────────────
_error_file = None

def _early_crash(msg):
    if _error_file:
        try:
            with open(_error_file, 'w', encoding='utf-8') as f:
                f.write(msg)
        except Exception:
            pass
    print(msg, file=sys.stderr)
    try:
        root = tk.Tk()
        root.withdraw()
        messagebox.showerror("Dependency Error", msg)
    except Exception:
        pass
    sys.exit(1)

if len(sys.argv) >= 2:
    try:
        with open(sys.argv[1], 'r', encoding='utf-8') as f:
            m = json.load(f)
            _error_file = m.get('error_file', '')
    except Exception:
        pass

try:
    import numpy as np
    import sounddevice as sd
    import soundfile as sf
except ImportError as e:
    _early_crash(
        f"Missing Python dependency: {e}\n\n"
        f"Please install performance modules using:\n"
        f"python -m pip install sounddevice soundfile numpy"
    )

# ── Style Palette Constants ──────────────────────────────────────────
BG = "#12121e"
PANEL_BG = "#0e0e18"
BUTTON_BG = "#2a2a4a"
TEXT_FG = "#ffffff"
LABEL_FG = "#9090c0"
ARMED_COLOR = "#ffaa44"
PLAYING_COLOR = "#2a4e2a"
ERROR_COLOR = "#4e2a2a"
STATUS_FG = "#606090"

DEFAULT_KEYS = [
    '1', '2', '3', '4', '5', '6', '7', '8', '9', '0',
    'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p',
    'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l',
    'z', 'x', 'c', 'v', 'b', 'n', 'm'
]

# ── Data Model Classes ────────────────────────────────────────────────
class Cue:
    def __init__(self, data):
        self.id = int(data['id'])
        self.name = data['name']
        self.filename = data['filename']
        self.duration = float(data['duration'])
        self.channels = int(data['channels'])
        self.sample_rate = int(data['sample_rate'])
        
        # Runtime editable settings
        self.gain_db = float(data.get('gain_db', 0.0))
        self.fade_in = float(data.get('fade_in', 0.0))
        self.fade_out = float(data.get('fade_out', 0.1))
        self.key_assignment = data.get('default_key', '')
        self.mode = data.get('playback_mode', 'restart') 
        self.output_offset = 0
        self.mono_to_stereo = True if self.channels == 1 else False
        
        self.audio_data = None 
        self.status = "READY"

class CueInstance:
    def __init__(self, cue, sample_rate):
        self.cue = cue
        self.current_frame = 0
        self.gain_linear = 10.0 ** (cue.gain_db / 20.0)
        self.is_stopping = False
        # Guard against zero-frame divisions on near-zero fades
        self.fade_in_frames = max(1, int(cue.fade_in * sample_rate)) if cue.fade_in > 0 else 0
        self.fade_out_frames = max(1, int(cue.fade_out * sample_rate)) if cue.fade_out > 0 else 0
        self.stop_frame_elapsed = 0
        self.state = 'PLAYING'

# ── Realtime Multi-channel Audio Mixing Engine ────────────────────────
class AudioEngine:
    def __init__(self, manifest):
        # Robust key fallback to support both 'project_sample_rate' and 'sample_rate' manifest definitions
        self.sample_rate = int(manifest.get('project_sample_rate', manifest.get('sample_rate', 44100)))
        self.log_file_path = manifest.get('log_file', '')
        self.config_file_path = manifest.get('config_file', '')
        
        self.active_cues = []
        self.test_signals = []
        self.lock = threading.Lock()
        
        self.stream = None
        self.output_channels = 0
        self.master_gain_linear = 1.0
        self.exclusive_mode = False
        self.audio_status_errs = []

    def log_event(self, text):
        t_stamp = time.strftime("%Y-%m-%d %H:%M:%S")
        msg = f"[{t_stamp}] {text}\n"
        print(msg, end='')
        if self.log_file_path:
            try:
                with open(self.log_file_path, 'a', encoding='utf-8') as f:
                    f.write(msg)
            except Exception:
                pass

    def open_stream(self, device_index, num_channels):
        self.output_channels = num_channels
        try:
            self.stream = sd.OutputStream(
                samplerate=self.sample_rate,
                channels=self.output_channels,
                dtype='float32',
                device=device_index,
                blocksize=512,
                callback=self._audio_callback
            )
            self.stream.start()
            self.log_event(f"Audio stream opened: {self.output_channels}ch @ {self.sample_rate} Hz")
            return True
        except Exception as e:
            err = f"Failed to open audio stream: {e}"
            self.audio_status_errs.append(err)
            self.log_event(err)
            return False

    def close_stream(self):
        if self.stream:
            try:
                self.stream.stop()
                self.stream.close()
            except Exception:
                pass
            self.stream = None
        self.log_event("Audio stream closed.")

    def _audio_callback(self, outdata, frames, time_info, status):
        outdata.fill(0)
        with self.lock:
            finished = []

            # Mix test tones
            for sig in self.test_signals:
                t = np.arange(sig['frame'], sig['frame'] + frames) / self.sample_rate
                tone = (np.sin(2 * np.pi * sig['freq'] * t) * 0.3).astype(np.float32)
                ch = min(sig['channel'], self.output_channels - 1)
                outdata[:, ch] += tone
                sig['frame'] += frames
                if sig['frame'] >= sig['total_frames']:
                    finished.append(('test', sig))

            for s in finished:
                if s[0] == 'test':
                    self.test_signals.remove(s[1])
            finished = []

            # Mix active cues
            for inst in self.active_cues:
                if inst.state == 'DONE':
                    finished.append(inst)
                    continue

                cue = inst.cue
                audio = cue.audio_data
                if audio is None:
                    finished.append(inst)
                    continue

                total_frames = audio.shape[0]
                remaining = total_frames - inst.current_frame

                if remaining <= 0:
                    inst.state = 'DONE'
                    finished.append(inst)
                    continue

                chunk_len = min(frames, remaining)
                chunk = audio[inst.current_frame: inst.current_frame + chunk_len].copy()

                # Apply fade-in
                if inst.fade_in_frames > 0 and inst.current_frame < inst.fade_in_frames:
                    fi_start = inst.current_frame
                    fi_end   = min(inst.current_frame + chunk_len, inst.fade_in_frames)
                    ramp = np.linspace(fi_start / inst.fade_in_frames,
                                       fi_end   / inst.fade_in_frames,
                                       fi_end - fi_start, endpoint=False)
                    chunk[:fi_end - fi_start] *= ramp[:, np.newaxis] if chunk.ndim > 1 else ramp

                # Apply fade-out (either triggered stop or natural end)
                if inst.is_stopping:
                    fo_len = min(chunk_len, inst.fade_out_frames - inst.stop_frame_elapsed)
                    if fo_len > 0:
                        ramp = np.linspace(1.0 - inst.stop_frame_elapsed / inst.fade_out_frames,
                                           1.0 - (inst.stop_frame_elapsed + fo_len) / inst.fade_out_frames,
                                           fo_len, endpoint=False)
                        chunk[:fo_len] *= ramp[:, np.newaxis] if chunk.ndim > 1 else ramp
                        chunk[fo_len:] = 0
                    inst.stop_frame_elapsed += fo_len
                    if inst.stop_frame_elapsed >= inst.fade_out_frames:
                        inst.state = 'DONE'
                        finished.append(inst)
                        continue
                elif inst.fade_out_frames > 0:
                    fo_start_frame = total_frames - inst.fade_out_frames
                    abs_start = inst.current_frame
                    abs_end   = inst.current_frame + chunk_len
                    if abs_end > fo_start_frame:
                        ofs = max(0, fo_start_frame - abs_start)
                        for k in range(ofs, chunk_len):
                            pos_in_fade = (abs_start + k) - fo_start_frame
                            chunk[k] *= max(0.0, 1.0 - pos_in_fade / inst.fade_out_frames)

                # Apply gain
                chunk *= inst.gain_linear * self.master_gain_linear

                # Mono-to-stereo expand
                if cue.mono_to_stereo and chunk.ndim == 1:
                    chunk = np.stack([chunk, chunk], axis=1)
                elif chunk.ndim == 1:
                    chunk = chunk[:, np.newaxis]

                # Route to output channels with offset
                out_chs = chunk.shape[1]
                for c in range(out_chs):
                    dest = (cue.output_offset + c) % self.output_channels
                    outdata[:chunk_len, dest] += chunk[:, c]

                inst.current_frame += chunk_len
                if inst.current_frame >= total_frames:
                    inst.state = 'DONE'
                    finished.append(inst)

            for inst in finished:
                if inst in self.active_cues:
                    self.active_cues.remove(inst)
                    inst.cue.status = "READY"

    def play_cue(self, cue):
        with self.lock:
            if self.exclusive_mode:
                # Stop everything else with fade-out
                for inst in self.active_cues:
                    inst.is_stopping = True
                    inst.stop_frame_elapsed = 0

            if cue.mode == 'restart':
                for inst in list(self.active_cues):
                    if inst.cue is cue:
                        inst.is_stopping = True
                        inst.stop_frame_elapsed = 0

            new_inst = CueInstance(cue, self.sample_rate)
            self.active_cues.append(new_inst)
            cue.status = "PLAYING"
        self.log_event(f"CUE PLAY: [{cue.id}] {cue.name}")

    def stop_cue(self, cue):
        with self.lock:
            for inst in self.active_cues:
                if inst.cue is cue and not inst.is_stopping:
                    inst.is_stopping = True
                    inst.stop_frame_elapsed = 0
        self.log_event(f"CUE STOP: [{cue.id}] {cue.name}")

    def stop_all(self):
        with self.lock:
            for inst in self.active_cues:
                inst.is_stopping = True
                inst.stop_frame_elapsed = 0
        self.log_event("STOP ALL")

    def get_cue_progress(self):
        """Return {cue_id: (elapsed_sec, remaining_sec, fraction 0..1)} for every active instance."""
        result = {}
        with self.lock:
            for inst in self.active_cues:
                cue = inst.cue
                total = cue.audio_data.shape[0] if cue.audio_data is not None else 1
                frame = min(inst.current_frame, total)
                elapsed   = frame / self.sample_rate
                remaining = max(0.0, (total - frame) / self.sample_rate)
                fraction  = frame / total if total > 0 else 0.0
                # If multiple instances of same cue (e.g. overlap mode), keep the furthest-along one
                if cue.id not in result or fraction > result[cue.id][2]:
                    result[cue.id] = (elapsed, remaining, fraction)
        return result

    def play_test_tone(self, channel, freq=1000, duration=1.0):
        with self.lock:
            self.test_signals.append({
                'channel': channel,
                'freq': freq,
                'frame': 0,
                'total_frames': int(duration * self.sample_rate)
            })

    def write_done_file(self, done_path, config):
        try:
            with open(done_path, 'w', encoding='utf-8') as f:
                json.dump(config, f, indent=2)
        except Exception:
            pass


# ── Settings / Config Persistence ─────────────────────────────────────
def load_config(path):
    try:
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except Exception:
        return {}

def save_config(path, data):
    try:
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2)
    except Exception:
        pass


# ── Main GUI Application ──────────────────────────────────────────────
class PerformanceLauncherApp:
    def __init__(self, root, manifest):
        self.root = root
        self.manifest = manifest
        self.engine = AudioEngine(manifest)

        self.done_file   = manifest.get('done_file', '')
        self.config_file = manifest.get('config_file', '')

        cfg = load_config(self.config_file)

        # Build cues from manifest clips
        self.cues = []
        clips = manifest.get('clips', [])
        for i, clip in enumerate(clips):
            cue = Cue(clip)
            if not cue.key_assignment and i < len(DEFAULT_KEYS):
                cue.key_assignment = DEFAULT_KEYS[i]
            self.cues.append(cue)

        # Restore saved key assignments / gain from config
        saved_cues = cfg.get('cues', {})
        for cue in self.cues:
            key = str(cue.id)
            if key in saved_cues:
                sc = saved_cues[key]
                cue.key_assignment = sc.get('key_assignment', cue.key_assignment)
                cue.gain_db        = float(sc.get('gain_db', cue.gain_db))
                cue.output_offset  = int(sc.get('output_offset', cue.output_offset))
                cue.mode           = sc.get('mode', cue.mode)

        self.selected_device    = tk.IntVar(value=cfg.get('device_index', -1))
        self.output_ch_count    = tk.IntVar(value=cfg.get('output_channels', max(2, manifest.get('project_max_channels', 2))))
        self.master_gain_var    = tk.DoubleVar(value=cfg.get('master_gain_db', 0.0))
        self.exclusive_var      = tk.BooleanVar(value=cfg.get('exclusive_mode', False))

        self.cue_buttons     = {}   # cue.id -> button widget
        self.cue_pbars       = {}   # cue.id -> ttk.Progressbar
        self.cue_time_labels = {}   # cue.id -> time Label
        self.key_map         = {}   # key char -> cue
        self._status_msg   = tk.StringVar(value="Ready.")

        # Pre-load audio
        load_errors = []
        for cue in self.cues:
            try:
                data, _ = sf.read(cue.filename, dtype='float32', always_2d=False)
                cue.audio_data = data
            except Exception as e:
                cue.status = "ERROR"
                load_errors.append(f"Cue [{cue.id}] {cue.name}: {e}")
        if load_errors:
            self.engine.log_event("Load errors:\n" + "\n".join(load_errors))

        self._build_ui()
        self._rebuild_key_map()
        self._apply_master_gain()
        self._apply_exclusive()
        self._try_open_stream()

        self.root.bind('<KeyPress>', self._on_keypress)
        self.root.protocol("WM_DELETE_WINDOW", self._on_close)
        self._poll_status()

    # ── UI Construction ───────────────────────────────────────────────
    def _build_ui(self):
        self.root.title("Performance Launcher")
        self.root.configure(bg=BG)
        self.root.resizable(True, True)

        # ── Top bar ──
        top = tk.Frame(self.root, bg=PANEL_BG, pady=4)
        top.pack(fill='x', padx=6, pady=(6, 0))

        tk.Label(top, text="PERFORMANCE LAUNCHER", bg=PANEL_BG,
                 fg=TEXT_FG, font=("Helvetica", 11, "bold")).pack(side='left', padx=8)

        tk.Button(top, text="⏹ Stop All", bg=BUTTON_BG, fg=TEXT_FG,
                  relief='flat', padx=8,
                  command=self.engine.stop_all).pack(side='right', padx=4)

        # ── Master gain ──
        ctrl = tk.Frame(self.root, bg=BG)
        ctrl.pack(fill='x', padx=8, pady=4)

        tk.Label(ctrl, text="Master Gain (dB):", bg=BG, fg=LABEL_FG,
                 font=("Helvetica", 9)).grid(row=0, column=0, sticky='w', padx=4)
        tk.Scale(ctrl, from_=-40, to=12, resolution=0.5, orient='horizontal',
                 variable=self.master_gain_var, bg=BG, fg=TEXT_FG,
                 troughcolor=BUTTON_BG, highlightthickness=0, length=200,
                 command=lambda _: self._apply_master_gain()
                 ).grid(row=0, column=1, sticky='ew', padx=4)

        tk.Checkbutton(ctrl, text="Exclusive (stop others on play)",
                       variable=self.exclusive_var, bg=BG, fg=LABEL_FG,
                       selectcolor=BUTTON_BG, activebackground=BG,
                       command=self._apply_exclusive).grid(row=0, column=2, padx=12)
        ctrl.columnconfigure(1, weight=1)

        # ── Device selector ──
        dev_frame = tk.Frame(self.root, bg=BG)
        dev_frame.pack(fill='x', padx=8)

        tk.Label(dev_frame, text="Output Device:", bg=BG, fg=LABEL_FG,
                 font=("Helvetica", 9)).pack(side='left', padx=4)

        self.device_combo = ttk.Combobox(dev_frame, width=40, state='readonly')
        self.device_combo.pack(side='left', padx=4)
        self._populate_devices()
        self.device_combo.bind('<<ComboboxSelected>>', self._on_device_changed)

        tk.Label(dev_frame, text="Channels:", bg=BG, fg=LABEL_FG).pack(side='left', padx=(12, 2))
        tk.Spinbox(dev_frame, from_=1, to=32, width=4,
                   textvariable=self.output_ch_count,
                   command=self._on_device_changed,
                   bg=BUTTON_BG, fg=TEXT_FG, insertbackground=TEXT_FG,
                   buttonbackground=BUTTON_BG).pack(side='left')

        # ── Cue grid ──
        grid_outer = tk.Frame(self.root, bg=BG)
        grid_outer.pack(fill='both', expand=True, padx=8, pady=8)

        canvas = tk.Canvas(grid_outer, bg=BG, highlightthickness=0)
        scroll = ttk.Scrollbar(grid_outer, orient='vertical', command=canvas.yview)
        canvas.configure(yscrollcommand=scroll.set)
        scroll.pack(side='right', fill='y')
        canvas.pack(side='left', fill='both', expand=True)

        self.cue_frame = tk.Frame(canvas, bg=BG)
        canvas_win = canvas.create_window((0, 0), window=self.cue_frame, anchor='nw')

        def _on_frame_configure(e):
            canvas.configure(scrollregion=canvas.bbox('all'))
        def _on_canvas_configure(e):
            canvas.itemconfig(canvas_win, width=e.width)

        self.cue_frame.bind('<Configure>', _on_frame_configure)
        canvas.bind('<Configure>', _on_canvas_configure)

        # Cross-platform vertical scroll:
        #   Windows / macOS  → <MouseWheel>  (delta in multiples of 120)
        #   Linux (X11)      → <Button-4> / <Button-5>  (no delta field)
        canvas.bind('<MouseWheel>',
            lambda e: canvas.yview_scroll(-1 * (e.delta // 120), 'units'))
        canvas.bind('<Button-4>',
            lambda e: canvas.yview_scroll(-1, 'units'))
        canvas.bind('<Button-5>',
            lambda e: canvas.yview_scroll(1, 'units'))

        for cue in self.cues:
            self._add_cue_row(cue)

        # ── Status bar ──
        tk.Label(self.root, textvariable=self._status_msg,
                 bg=PANEL_BG, fg=STATUS_FG, anchor='w',
                 font=("Helvetica", 8)).pack(fill='x', side='bottom')

    def _add_cue_row(self, cue):
        row = tk.Frame(self.cue_frame, bg=BUTTON_BG, pady=2)
        row.pack(fill='x', pady=2, padx=2)

        # Key badge
        key_lbl = tk.Label(row, text=f"[{cue.key_assignment.upper() if cue.key_assignment else '—'}]",
                           bg=ARMED_COLOR, fg="#000", width=4,
                           font=("Courier", 9, "bold"))
        key_lbl.pack(side='left', padx=(4, 2), pady=4)

        # Play button
        btn = tk.Button(row, text=f"▶  {cue.name}",
                        bg=BUTTON_BG, fg=TEXT_FG, relief='flat',
                        anchor='w', padx=8,
                        font=("Helvetica", 10),
                        command=lambda c=cue: self._trigger_cue(c))
        btn.pack(side='left', fill='x', expand=True, pady=2)
        self.cue_buttons[cue.id] = btn

        # Duration label
        tk.Label(row, text=f"{cue.duration:.1f}s",
                 bg=BUTTON_BG, fg=LABEL_FG,
                 font=("Helvetica", 8)).pack(side='left', padx=4)

        # ── Progress bar + time remaining ──
        prog_frame = tk.Frame(row, bg=BUTTON_BG)
        prog_frame.pack(side='left', padx=(0, 6))

        style_name = f"Cue{cue.id}.Horizontal.TProgressbar"
        style = ttk.Style()
        style.theme_use('default')
        style.configure(style_name,
                        troughcolor=PANEL_BG,
                        background="#4a9a6a",
                        thickness=8,
                        borderwidth=0)

        pbar = ttk.Progressbar(prog_frame, style=style_name,
                               orient='horizontal', length=120,
                               mode='determinate', maximum=1000)
        pbar.pack(side='top', fill='x', pady=(2, 0))

        time_lbl = tk.Label(prog_frame, text="",
                            bg=BUTTON_BG, fg=LABEL_FG,
                            font=("Courier", 7), width=12, anchor='center')
        time_lbl.pack(side='top')

        self.cue_pbars[cue.id]      = pbar
        self.cue_time_labels[cue.id] = time_lbl

        # Gain spinbox
        gain_var = tk.DoubleVar(value=cue.gain_db)
        tk.Label(row, text="dB:", bg=BUTTON_BG, fg=LABEL_FG,
                 font=("Helvetica", 8)).pack(side='left')
        sp = tk.Spinbox(row, from_=-40, to=12, increment=0.5, width=5,
                        textvariable=gain_var, format="%.1f",
                        bg=PANEL_BG, fg=TEXT_FG, insertbackground=TEXT_FG,
                        buttonbackground=BUTTON_BG,
                        command=lambda c=cue, v=gain_var: self._set_cue_gain(c, v))
        sp.pack(side='left', padx=2)

        # Channel offset
        tk.Label(row, text="Ch+:", bg=BUTTON_BG, fg=LABEL_FG,
                 font=("Helvetica", 8)).pack(side='left')
        off_var = tk.IntVar(value=cue.output_offset)
        tk.Spinbox(row, from_=0, to=31, width=3,
                   textvariable=off_var,
                   bg=PANEL_BG, fg=TEXT_FG, insertbackground=TEXT_FG,
                   buttonbackground=BUTTON_BG,
                   command=lambda c=cue, v=off_var: setattr(c, 'output_offset', v.get())
                   ).pack(side='left', padx=2)

        # Stop button
        tk.Button(row, text="■", bg=ERROR_COLOR, fg=TEXT_FG, relief='flat',
                  width=2, command=lambda c=cue: self.engine.stop_cue(c)
                  ).pack(side='right', padx=4)

        if cue.status == "ERROR":
            btn.configure(bg=ERROR_COLOR, text=f"✗  {cue.name}  [load error]")

    # ── Device Helpers ────────────────────────────────────────────────
    def _populate_devices(self):
        devs = sd.query_devices()
        entries = []
        idx_map = []
        for i, d in enumerate(devs):
            if d['max_output_channels'] > 0:
                entries.append(f"{i}: {d['name']}  ({d['max_output_channels']}ch)")
                idx_map.append(i)
        self._device_indices = idx_map
        self.device_combo['values'] = entries
        # Select saved or default
        saved_idx = self.selected_device.get()
        if saved_idx >= 0 and saved_idx in idx_map:
            self.device_combo.current(idx_map.index(saved_idx))
        elif idx_map:
            default_out = sd.default.device[1] if isinstance(sd.default.device, (list, tuple)) else sd.default.device
            if default_out in idx_map:
                self.device_combo.current(idx_map.index(default_out))
            else:
                self.device_combo.current(0)

    def _on_device_changed(self, *_):
        sel = self.device_combo.current()
        if sel < 0 or sel >= len(self._device_indices):
            return
        idx = self._device_indices[sel]
        self.selected_device.set(idx)
        self.engine.close_stream()
        self._try_open_stream()

    def _try_open_stream(self):
        sel = self.device_combo.current()
        if sel < 0 or not hasattr(self, '_device_indices') or sel >= len(self._device_indices):
            self._status_msg.set("No output device selected.")
            return
        dev_idx  = self._device_indices[sel]
        num_chs  = max(1, self.output_ch_count.get())
        ok = self.engine.open_stream(dev_idx, num_chs)
        if ok:
            self._status_msg.set(f"Stream open: device {dev_idx}, {num_chs}ch @ {self.engine.sample_rate} Hz")
        else:
            err = self.engine.audio_status_errs[-1] if self.engine.audio_status_errs else "Unknown error"
            self._status_msg.set(f"Stream error: {err}")

    # ── Cue Actions ───────────────────────────────────────────────────
    def _trigger_cue(self, cue):
        if cue.status == "ERROR":
            self._status_msg.set(f"Cue [{cue.id}] could not be loaded — skipping.")
            return
        self.engine.play_cue(cue)
        self._status_msg.set(f"Playing: {cue.name}")

    def _set_cue_gain(self, cue, var):
        try:
            cue.gain_db = float(var.get())
        except ValueError:
            pass

    def _apply_master_gain(self):
        db = self.master_gain_var.get()
        self.engine.master_gain_linear = 10.0 ** (db / 20.0)

    def _apply_exclusive(self):
        self.engine.exclusive_mode = self.exclusive_var.get()

    def _rebuild_key_map(self):
        self.key_map.clear()
        for cue in self.cues:
            if cue.key_assignment:
                self.key_map[cue.key_assignment.lower()] = cue

    def _on_keypress(self, event):
        k = event.keysym.lower()
        if k == 'escape':
            self.engine.stop_all()
            return
        if k in self.key_map:
            self._trigger_cue(self.key_map[k])

    # ── Status Polling ────────────────────────────────────────────────
    def _poll_status(self):
        progress = self.engine.get_cue_progress()

        for cue in self.cues:
            btn   = self.cue_buttons.get(cue.id)
            pbar  = self.cue_pbars.get(cue.id)
            tlbl  = self.cue_time_labels.get(cue.id)

            if cue.id in progress:
                elapsed, remaining, fraction = progress[cue.id]
                cue.status = "PLAYING"

                if btn:
                    btn.configure(bg=PLAYING_COLOR)
                if pbar:
                    pbar['value'] = fraction * 1000
                if tlbl:
                    # Show  -0:00  countdown (or elapsed if >total)
                    rem_int = int(remaining)
                    rem_frac = remaining - rem_int
                    mins = rem_int // 60
                    secs = rem_int % 60
                    tenths = int(rem_frac * 10)
                    tlbl.configure(text=f"-{mins}:{secs:02d}.{tenths}")
            else:
                if cue.status == "PLAYING":
                    cue.status = "READY"
                if btn:
                    if cue.status == "ERROR":
                        btn.configure(bg=ERROR_COLOR)
                    else:
                        btn.configure(bg=BUTTON_BG)
                if pbar:
                    pbar['value'] = 0
                if tlbl:
                    tlbl.configure(text="")

        self.root.after(100, self._poll_status)

    # ── Shutdown ──────────────────────────────────────────────────────
    def _on_close(self):
        self.engine.stop_all()
        time.sleep(0.15)
        self.engine.close_stream()
        self._save_config()
        self._cleanup_temp_files()
        self.root.destroy()

    def _cleanup_temp_files(self):
        """Delete the per-cue WAV exports and the manifest written by Praat."""
        removed, failed = [], []
        targets = [cue.filename for cue in self.cues]
        targets.append(self.manifest.get('_manifest_path', ''))
        targets.append(self.manifest.get('log_file', ''))
        targets.append(self.manifest.get('config_file', ''))
        targets.append(self.manifest.get('done_file', ''))
        targets.append(self.manifest.get('error_file', ''))   # set in main()
        for path in targets:
            if not path:
                continue
            try:
                if os.path.isfile(path):
                    os.remove(path)
                    removed.append(path)
            except OSError as e:
                failed.append(f"{path}: {e}")
        if removed:
            self.engine.log_event(f"Cleaned up {len(removed)} temp file(s).")
        if failed:
            self.engine.log_event(f"Could not remove: {'; '.join(failed)}")

    def _save_config(self):
        cue_data = {}
        for cue in self.cues:
            cue_data[str(cue.id)] = {
                'key_assignment': cue.key_assignment,
                'gain_db':        cue.gain_db,
                'output_offset':  cue.output_offset,
                'mode':           cue.mode,
            }
        cfg = {
            'device_index':    self.selected_device.get(),
            'output_channels': self.output_ch_count.get(),
            'master_gain_db':  self.master_gain_var.get(),
            'exclusive_mode':  self.exclusive_var.get(),
            'cues':            cue_data,
        }
        save_config(self.config_file, cfg)
        self.engine.write_done_file(self.done_file, cfg)
        self.engine.log_event("Config saved. Launcher exiting.")


# ── Entry Point ───────────────────────────────────────────────────────
def main():
    if len(sys.argv) < 2:
        print("Usage: performance_launcher.py <manifest.json>", file=sys.stderr)
        sys.exit(1)

    manifest_path = sys.argv[1]
    try:
        with open(manifest_path, 'r', encoding='utf-8') as f:
            manifest = json.load(f)
    except Exception as e:
        _early_crash(f"Could not read manifest: {e}\nPath: {manifest_path}")

    manifest['_manifest_path'] = manifest_path

    root = tk.Tk()
    try:
        app = PerformanceLauncherApp(root, manifest)
        root.mainloop()
    except Exception:
        tb = traceback.format_exc()
        err_path = manifest.get('error_file', '')
        if err_path:
            try:
                with open(err_path, 'w', encoding='utf-8') as f:
                    f.write(tb)
            except Exception:
                pass
        raise

if __name__ == '__main__':
    main()
