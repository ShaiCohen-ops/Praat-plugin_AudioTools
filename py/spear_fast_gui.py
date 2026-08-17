#!/usr/bin/env python3
# ============================================================
# Praat AudioTools Plugin
# Script:      spear_fast_gui.py
# Author:      Shai Cohen
# Version:     0.7.2 (2026) - Fast Python GUI engine
#   0.7.1: changed the default phase mode to 'Track-continuous' and cleared
#          stale error files before each render.
#   0.7.2: REVERTED the phase-mode default to 'Praat-compatible'. The
#          per-frame phase reset is measurably an interference artefact,
#          but it is the sound this instrument has always had, and the
#          coherent alternative was judged thinner. Both modes remain
#          selectable; nothing about the rendering maths changed, only
#          which mode is selected on startup. The 0.7.1 state migration
#          was removed along with it. The error-file fix from 0.7.1 is
#          KEPT - it concerns the Praat handshake, not the sound.
# License:     MIT License
#
# Launched by SPEAR_Fast_Resynthesis.praat via a JSON manifest.
# Praat remains the user entry/exit point; Python provides the
# interactive SPEAR-like editor and NumPy resynthesis engine.
# ============================================================

import sys
import os
import json
import math
import wave
import struct
import threading
import traceback
import time
from pathlib import Path

try:
    import numpy as np
except Exception as exc:
    print(f"NumPy is required: {exc}", file=sys.stderr)
    raise

_error_file = None


def _crash(exc):
    tb = traceback.format_exc()
    msg = f"{type(exc).__name__}: {exc}\n\n{tb}"
    if _error_file:
        try:
            Path(_error_file).parent.mkdir(parents=True, exist_ok=True)
            Path(_error_file).write_text(msg, encoding="utf-8")
        except Exception:
            pass
    print(msg, file=sys.stderr)
    sys.exit(1)


# -----------------------------------------------------------------------------
# DATA MODEL / PARSERS
# -----------------------------------------------------------------------------

TYPE_SIZES = {
    0x0004: ('f', 4), 0x0008: ('d', 8),
    0x0001: ('f', 4), 0x0020: ('f', 4),
    0x0002: ('d', 8), 0x0040: ('d', 8),
}


def _read_exact(f, n):
    b = f.read(n)
    if len(b) != n:
        raise EOFError(f"Unexpected EOF (needed {n}, got {len(b)})")
    return b


class SpectralData:
    def __init__(self, source_name, frames, sample_rate=44100, source_kind="tracks"):
        if not frames:
            raise ValueError("No spectral frames found")
        self.source_name = source_name
        self.frames = frames
        self.sample_rate = int(sample_rate)
        self.source_kind = source_kind
        self.times = np.asarray([f['time'] for f in frames], dtype=np.float64)
        dif = np.diff(self.times)
        dif = dif[np.isfinite(dif) & (dif > 0)]
        self.hop = float(np.median(dif)) if dif.size else 0.01
        self.duration = max(self.hop, float(self.times[-1] - self.times[0] + self.hop))
        all_ids = set()
        max_amp = 0.0
        max_freq = 1.0
        has_phase = False
        for fr in frames:
            all_ids.update(int(x) for x in fr['idx'])
            if len(fr['amp']):
                max_amp = max(max_amp, float(np.max(fr['amp'])))
                max_freq = max(max_freq, float(np.max(fr['freq'])))
            if fr.get('has_phase', False):
                has_phase = True
        self.track_ids = sorted(all_ids)
        self.max_amp = max(max_amp, 1e-12)
        self.max_freq = max_freq
        self.has_phase = has_phase


def parse_sdif(path):
    frames = []
    with open(path, 'rb') as f:
        if _read_exact(f, 4) != b'SDIF':
            raise ValueError('Not an SDIF file')
        _hdr_size = struct.unpack('>I', _read_exact(f, 4))[0]
        version = struct.unpack('>I', _read_exact(f, 4))[0]
        _type_version = struct.unpack('>I', _read_exact(f, 4))[0]
        if version < 2:
            raise ValueError(f'Unsupported SDIF version {version}')

        while True:
            sig = f.read(4)
            if not sig:
                break
            if len(sig) != 4:
                raise EOFError('Truncated SDIF frame signature')
            frame_size = struct.unpack('>I', _read_exact(f, 4))[0]
            body_start = f.tell()
            frame_end = body_start + frame_size
            if frame_size < 16:
                raise ValueError('Invalid SDIF frame size')
            t = struct.unpack('>d', _read_exact(f, 8))[0]
            _stream_id = struct.unpack('>i', _read_exact(f, 4))[0]
            matrix_count = struct.unpack('>I', _read_exact(f, 4))[0]
            frame_sig = sig.decode('latin1')
            rows_out = []
            frame_has_phase = False

            for _ in range(matrix_count):
                msig = _read_exact(f, 4).decode('latin1')
                dtype = struct.unpack('>I', _read_exact(f, 4))[0]
                rows = struct.unpack('>I', _read_exact(f, 4))[0]
                cols = struct.unpack('>I', _read_exact(f, 4))[0]
                nvals = rows * cols
                low_size = dtype & 0xff
                data_bytes = nvals * low_size

                if msig in ('1TRC', '1HRM') and dtype in TYPE_SIZES and cols >= 3:
                    code, size = TYPE_SIZES[dtype]
                    raw = _read_exact(f, nvals * size)
                    vals = struct.unpack('>' + code * nvals, raw) if nvals else ()
                    frame_has_phase = frame_has_phase or cols >= 4
                    for r in range(rows):
                        base = r * cols
                        idx = int(round(vals[base]))
                        freq = float(vals[base + 1])
                        amp = float(vals[base + 2])
                        phase = float(vals[base + 3]) if cols >= 4 else 0.0
                        if freq > 0 and amp >= 0:
                            rows_out.append((idx, freq, amp, phase))
                else:
                    _read_exact(f, data_bytes)
                pad = (-data_bytes) % 8
                if pad:
                    _read_exact(f, pad)
            f.seek(frame_end)

            if frame_sig in ('1TRC', '1HRM') and rows_out:
                arr = np.asarray(rows_out, dtype=np.float64)
                frames.append({
                    'time': float(t),
                    'idx': arr[:, 0].astype(np.int64),
                    'freq': arr[:, 1].astype(np.float64),
                    'amp': arr[:, 2].astype(np.float64),
                    'phase': arr[:, 3].astype(np.float64),
                    'has_phase': frame_has_phase,
                })

    return SpectralData(Path(path).stem, frames, source_kind='sdif')


def parse_spear_text(path):
    lines = Path(path).read_text(encoding='utf-8', errors='replace').splitlines()
    if len(lines) < 6 or not lines[0].strip().startswith('par-text-frame-format'):
        raise ValueError('Not a SPEAR par-text-frame-format file')
    point_line = lines[1].strip().split()
    if not point_line or point_line[0] != 'point-type':
        raise ValueError('Missing SPEAR point-type line')
    columns = point_line[1:]
    if 'frequency' not in columns or 'amplitude' not in columns:
        raise ValueError('SPEAR point-type must contain frequency and amplitude')
    nper = len(columns)
    i_idx = columns.index('index') if 'index' in columns else None
    i_freq = columns.index('frequency')
    i_amp = columns.index('amplitude')
    i_phase = columns.index('phase') if 'phase' in columns else None

    try:
        data_start = next(i for i, line in enumerate(lines) if line.strip() == 'frame-data') + 1
    except StopIteration:
        raise ValueError('Missing SPEAR frame-data marker')

    frames = []
    for line in lines[data_start:]:
        toks = line.split()
        if len(toks) < 2:
            continue
        t = float(toks[0])
        count = int(float(toks[1]))
        body = toks[2:]
        available = len(body) // max(nper, 1)
        count = min(count, available)
        rows = []
        for p in range(count):
            g = body[p * nper:(p + 1) * nper]
            idx = int(round(float(g[i_idx]))) if i_idx is not None else p
            freq = float(g[i_freq])
            amp = float(g[i_amp])
            phase = float(g[i_phase]) if i_phase is not None else 0.0
            if freq > 0 and amp >= 0:
                rows.append((idx, freq, amp, phase))
        if rows:
            arr = np.asarray(rows, dtype=np.float64)
            frames.append({
                'time': t,
                'idx': arr[:, 0].astype(np.int64),
                'freq': arr[:, 1],
                'amp': arr[:, 2],
                'phase': arr[:, 3],
                'has_phase': i_phase is not None,
            })
    return SpectralData(Path(path).stem, frames, source_kind='spear-text')


def _read_wav_numpy(path):
    with wave.open(str(path), 'rb') as w:
        nch = w.getnchannels()
        sw = w.getsampwidth()
        sr = w.getframerate()
        n = w.getnframes()
        raw = w.readframes(n)
    if sw == 2:
        x = np.frombuffer(raw, dtype='<i2').astype(np.float64) / 32768.0
    elif sw == 4:
        x = np.frombuffer(raw, dtype='<i4').astype(np.float64) / 2147483648.0
    elif sw == 1:
        x = (np.frombuffer(raw, dtype=np.uint8).astype(np.float64) - 128.0) / 128.0
    elif sw == 3:
        b = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 3)
        u = b[:, 0].astype(np.int32) | (b[:, 1].astype(np.int32) << 8) | (b[:, 2].astype(np.int32) << 16)
        u = np.where(u & 0x800000, u - 0x1000000, u)
        x = u.astype(np.float64) / 8388608.0
    else:
        raise ValueError(f'Unsupported WAV sample width: {sw}')
    if nch > 1:
        x = x.reshape(-1, nch)
        rms = np.sqrt(np.mean(x * x, axis=0))
        x = x[:, int(np.argmax(rms))]
    return x, sr


def analyse_wav(path, hop=0.01, max_freq=8000.0, threshold=0.01):
    x, sr = _read_wav_numpy(path)
    hop_samp = max(1, int(round(hop * sr)))
    win_samp = max(64, int(round(hop * 2.5 * sr)))
    nfft = 1
    while nfft < win_samp:
        nfft *= 2
    win = np.hanning(win_samp)
    nframes = max(1, 1 + max(0, len(x) - win_samp) // hop_samp)
    freqs = np.fft.rfftfreq(nfft, 1.0 / sr)
    hi = int(np.searchsorted(freqs, min(max_freq, sr / 2), side='right'))
    frames = []
    for fi in range(nframes):
        start = fi * hop_samp
        seg = x[start:start + win_samp]
        if len(seg) < win_samp:
            seg = np.pad(seg, (0, win_samp - len(seg)))
        mag = np.abs(np.fft.rfft(seg * win, nfft))
        mag = mag[:hi]
        if len(mag) < 3 or float(np.max(mag)) <= 0:
            continue
        thr = float(np.max(mag)) * max(0.0, float(threshold))
        cand = np.where((mag[1:-1] > mag[:-2]) & (mag[1:-1] >= mag[2:]) & (mag[1:-1] > thr))[0] + 1
        if cand.size == 0:
            continue
        amp = mag[cand] / max(np.sum(win) / 2.0, 1e-12)
        frq = freqs[cand]
        idx = np.arange(1, len(cand) + 1, dtype=np.int64)
        frames.append({
            'time': start / sr,
            'idx': idx,
            'freq': frq.astype(np.float64),
            'amp': amp.astype(np.float64),
            'phase': np.zeros(len(cand), dtype=np.float64),
            'has_phase': False,
        })
    if not frames:
        raise ValueError('No spectral peaks found in selected Sound')
    return SpectralData(Path(path).stem, frames, sample_rate=sr, source_kind='analysed-sound')


def load_source(path):
    ext = Path(path).suffix.lower()
    if ext == '.sdif':
        return parse_sdif(path)
    if ext in ('.txt', '.spear'):
        return parse_spear_text(path)
    raise ValueError('Choose a SPEAR .txt/.spear or SDIF .sdif file')


# -----------------------------------------------------------------------------
# FAST NUMPY RENDERER
# -----------------------------------------------------------------------------

DEFAULTS = {
    'max_partials': 64,
    'amplitude_scale': 1.0,
    'transpose_ratio': 1.0,
    'inharmonicity': 1.0,
    'frequency_shift': 0.0,
    'brightness': 0.0,
    'gate': 0.0,
    'band_low': 0.0,
    'band_high': 20000.0,
    'harmonic': 'All',
    'time_stretch': 1.0,
    'reverse': False,
    'freeze_frame': 0,
    # 'Praat-compatible' resets each partial's phase every frame, so the two
    # overlapping Hann windows carry that partial at phases offset by
    # 2*pi*f*hop and interfere. That is a measurable artefact (envelope
    # ripple 97% at 440 Hz, 153% at 1050 Hz) but it is ALSO the sound this
    # instrument has always made: the interference puts sidebands at
    # multiples of the frame rate around every partial, which is what gives
    # the output its edge. It stays the default by the composer's judgment.
    # 'Track-continuous' is the phase-coherent alternative - cleaner and
    # plainer - and remains available in the Phase mode menu.
    'phase_mode': 'Praat-compatible',
    'output_peak': 0.95,
}

PRESETS = {
    'Custom': {},
    'Faithful': dict(DEFAULTS),
    'OctaveUp': {**DEFAULTS, 'transpose_ratio': 2.0},
    'OctaveDown': {**DEFAULTS, 'transpose_ratio': 0.5},
    'GlassBells': {**DEFAULTS, 'inharmonicity': 1.3, 'brightness': 0.4},
    'HollowClarinet': {**DEFAULTS, 'gate': 0.01, 'harmonic': 'Odd'},
    'FrozenDrone': {**DEFAULTS, 'time_stretch': 2.0, 'freeze_frame': -1},
    'SlowMotion': {**DEFAULTS, 'time_stretch': 3.0},
    'Reversed': {**DEFAULTS, 'time_stretch': 1.5, 'reverse': True},
    'DarkPad': {**DEFAULTS, 'transpose_ratio': 0.5, 'brightness': -0.5, 'time_stretch': 2.0},
    'Shimmer': {**DEFAULTS, 'transpose_ratio': 2.0, 'brightness': 0.6, 'gate': 0.02},
    'Inharmonic': {**DEFAULTS, 'inharmonicity': 1.15, 'frequency_shift': 30.0},
    'LowBand': {**DEFAULTS, 'band_high': 1500.0},
}


def _top_k_by_amplitude(idx, freq, amp, phase, k):
    if len(amp) <= k:
        return idx, freq, amp, phase
    sel = np.argpartition(amp, -k)[-k:]
    order = sel[np.argsort(amp[sel])[::-1]]
    return idx[order], freq[order], amp[order], phase[order]


def render_audio(data, params, track_edits, sample_rate, max_seconds=None, progress_cb=None):
    t0 = time.perf_counter()
    sr = int(sample_rate)
    ts = max(float(params['time_stretch']), 1e-4)
    n_source = len(data.frames)
    n_out = max(1, int(round(n_source * ts)))
    hop = max(data.hop, 1.0 / sr)
    win_dur = 2.0 * hop
    nseg = max(8, int(round(win_dur * sr)))
    local_t = np.arange(nseg, dtype=np.float64) / sr
    window = 0.5 - 0.5 * np.cos(2.0 * np.pi * local_t / win_dur)
    total_dur = n_out * hop + win_dur
    if max_seconds is not None:
        total_dur = min(total_dur, float(max_seconds) + win_dur)
        n_out = min(n_out, max(1, int(math.ceil(float(max_seconds) / hop))))
    out = np.zeros(int(math.ceil(total_dur * sr)) + nseg + 2, dtype=np.float64)

    max_partials = max(1, int(params['max_partials']))
    amp_scale = float(params['amplitude_scale'])
    trans = float(params['transpose_ratio'])
    inharm = float(params['inharmonicity'])
    shift = float(params['frequency_shift'])
    bright = float(params['brightness'])
    gate_abs = max(0.0, float(params['gate'])) * data.max_amp
    band_lo = max(0.0, float(params['band_low']))
    band_hi = min(float(params['band_high']), sr / 2.0 - 1e-6)
    harmonic = params['harmonic']
    reverse = bool(params['reverse'])
    freeze = int(params['freeze_frame'])
    if freeze == -1:
        freeze = max(1, int(round(n_source * 0.5)))
    phase_mode = params['phase_mode']
    phase_state = {}

    for of in range(n_out):
        if freeze > 0:
            sf = min(n_source - 1, max(0, freeze - 1))
        else:
            sf = int(math.floor(of / ts))
            sf = min(n_source - 1, max(0, sf))
        if reverse:
            sf = n_source - 1 - sf
        fr = data.frames[sf]
        idx = fr['idx'].copy()
        freq = fr['freq'].copy() * trans
        amp = fr['amp'].copy() * amp_scale
        phase = fr['phase'].copy()

        if track_edits:
            for j, tid in enumerate(idx):
                ed = track_edits.get(int(tid))
                if ed:
                    if ed.get('mute', False):
                        amp[j] = 0.0
                    else:
                        amp[j] *= 10.0 ** (float(ed.get('gain_db', 0.0)) / 20.0)
                        freq[j] *= float(ed.get('freq_ratio', 1.0))

        pos = freq > 0
        if inharm != 1.0:
            freq[pos] = 1000.0 * np.power(freq[pos] / 1000.0, inharm)
        freq += shift
        if bright != 0.0:
            good = freq > 0
            amp[good] *= np.power(freq[good] / 1000.0, bright)

        keep = (amp >= gate_abs) & (freq >= band_lo) & (freq <= band_hi) & (freq > 0) & (freq < sr / 2.0)
        if harmonic == 'Odd':
            keep &= (idx % 2 == 1)
        elif harmonic == 'Even':
            keep &= (idx % 2 == 0)
        idx, freq, amp, phase = idx[keep], freq[keep], amp[keep], phase[keep]
        if len(amp) == 0:
            continue
        idx, freq, amp, phase = _top_k_by_amplitude(idx, freq, amp, phase, max_partials)

        if phase_mode == 'Praat-compatible':
            phase0 = np.zeros_like(freq)
        elif phase_mode == 'SDIF phase':
            phase0 = phase if fr.get('has_phase', False) else np.zeros_like(freq)
        else:  # Track-continuous
            phase0 = np.empty_like(freq)
            for j, tid in enumerate(idx):
                phase0[j] = phase_state.get(int(tid), 0.0)
                phase_state[int(tid)] = (phase0[j] + 2.0 * np.pi * freq[j] * hop) % (2.0 * np.pi)

        # One vectorized bank per frame: partials x local samples.
        angles = 2.0 * np.pi * freq[:, None] * local_t[None, :] + phase0[:, None]
        seg = np.sum(amp[:, None] * np.sin(angles), axis=0)
        seg *= window
        start = int(round(of * hop * sr))
        end = min(start + nseg, len(out))
        out[start:end] += seg[:end - start]

        if progress_cb and (of % 12 == 0 or of == n_out - 1):
            progress_cb((of + 1) / n_out)

    peak = float(np.max(np.abs(out))) if len(out) else 0.0
    target = max(0.0, min(1.0, float(params.get('output_peak', 0.95))))
    if peak > 0 and target > 0:
        out *= target / peak
    # Trim to the intended tail, retaining the final overlap window.
    last = min(len(out), int(math.ceil((n_out * hop + win_dur) * sr)))
    out = out[:last].astype(np.float32)
    return out, {'render_seconds': time.perf_counter() - t0, 'peak_before_norm': peak, 'frames': n_out}


def write_mono_wav(path, audio, sr):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    y = np.clip(np.asarray(audio, dtype=np.float64), -1.0, 1.0)
    pcm = np.round(y * 32767.0).astype('<i2')
    with wave.open(str(path), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(int(sr))
        w.writeframes(pcm.tobytes())


# -----------------------------------------------------------------------------
# GUI
# -----------------------------------------------------------------------------

BG = '#12121e'
PANEL = '#18182a'
PANEL2 = '#202038'
FG = '#d8d8ee'
MUTED = '#777799'
ACCENT = '#5b9bd5'
GREEN = '#67b77a'
RED = '#bd6666'
YELLOW = '#e1c35b'


class SpearFastApp:
    def __init__(self, manifest_path):
        import tkinter as tk
        from tkinter import ttk, filedialog, messagebox
        self.tk = tk
        self.ttk = ttk
        self.filedialog = filedialog
        self.messagebox = messagebox

        self.manifest_path = manifest_path
        self.manifest = json.loads(Path(manifest_path).read_text(encoding='utf-8'))
        self.result_file = self.manifest['result_file']
        self.done_file = self.manifest['done_file']
        self.error_file = self.manifest['error_file']
        self.report_file = self.manifest.get('report_file', '')
        self.name_file = self.manifest.get('name_file', '')
        self.state_file = self.manifest.get('state_file', '')
        self.praat_sound_file = self.manifest.get('praat_sound_file', '')
        self.praat_sound_name = self.manifest.get('praat_sound_name', '')
        self.default_sr = int(self.manifest.get('default_sample_rate', 44100))

        global _error_file
        _error_file = self.error_file

        self.data = None
        self.source_path = ''
        self.source_label = 'No source loaded'
        self.track_edits = {}
        self.selected_track = None
        self._busy = False
        self._applying_preset = False
        self._cancelled = True
        self._last_render = None
        self._load_started = 0.0

        self.root = tk.Tk()
        self.root.title('SPEAR Fast Resynthesis — Praat AudioTools')
        self.root.configure(bg=BG)
        self.root.geometry('1320x800')
        self.root.minsize(1050, 680)
        self.root.protocol('WM_DELETE_WINDOW', self._on_cancel)

        self.vars = {}
        self._build_ui()
        self._load_state()
        self._initial_source()

    # --------------------------- UI construction ---------------------------
    def _build_ui(self):
        tk = self.tk
        ttk = self.ttk

        header = tk.Frame(self.root, bg=BG, pady=6)
        header.pack(fill='x', padx=10)
        tk.Label(header, text='SPEAR Fast Resynthesis', bg=BG, fg='#ffffff',
                 font=('Helvetica', 15, 'bold')).pack(side='left')
        self.source_var = tk.StringVar(value=self.source_label)
        tk.Label(header, textvariable=self.source_var, bg=BG, fg='#8080aa',
                 font=('Courier', 9)).pack(side='left', padx=18)

        tk.Button(header, text='Open SDIF / SPEAR…', command=self._open_file,
                  bg=PANEL2, fg=FG, activebackground='#303050', relief='flat', padx=10).pack(side='right', padx=4)
        self.praat_btn = tk.Button(header, text='Use Praat Sound', command=self._use_praat_sound,
                                   bg=PANEL2, fg=FG, activebackground='#303050', relief='flat', padx=10)
        self.praat_btn.pack(side='right', padx=4)
        if not self.praat_sound_file or not os.path.isfile(self.praat_sound_file):
            self.praat_btn.config(state='disabled')

        main = tk.PanedWindow(self.root, orient='horizontal', bg=BG, sashwidth=5, sashrelief='flat')
        main.pack(fill='both', expand=True, padx=8, pady=4)

        # Left: trajectories
        left = tk.Frame(main, bg=BG)
        main.add(left, stretch='always', minsize=620)
        toolbar = tk.Frame(left, bg=BG)
        toolbar.pack(fill='x', pady=(0, 4))
        tk.Label(toolbar, text='Partial trajectories — click a track to edit', bg=BG, fg='#9090b0',
                 font=('Helvetica', 9)).pack(side='left')
        self.view_tracks_var = tk.IntVar(value=140)
        tk.Label(toolbar, text='tracks:', bg=BG, fg=MUTED).pack(side='right')
        tk.Scale(toolbar, from_=40, to=300, resolution=20, orient='horizontal', length=150,
                 variable=self.view_tracks_var, command=lambda _v: self._draw_trajectories(),
                 bg=BG, fg=MUTED, troughcolor=PANEL2, highlightthickness=0).pack(side='right')

        self.canvas = tk.Canvas(left, bg='#0b0b14', highlightthickness=1, highlightbackground='#33334c')
        self.canvas.pack(fill='both', expand=True)
        self.canvas.bind('<Configure>', lambda e: self._draw_trajectories())
        self.canvas.bind('<Button-1>', self._on_canvas_click)

        # Selected-track editor
        trackbar = tk.Frame(left, bg=PANEL, pady=6)
        trackbar.pack(fill='x', pady=(5, 0))
        self.track_label = tk.StringVar(value='Track: none selected')
        tk.Label(trackbar, textvariable=self.track_label, bg=PANEL, fg=FG,
                 font=('Courier', 9, 'bold')).pack(side='left', padx=8)
        self.track_mute_var = tk.BooleanVar(value=False)
        self.track_mute_btn = tk.Checkbutton(trackbar, text='Mute', variable=self.track_mute_var,
                                             command=self._track_edit_changed, bg=PANEL, fg=FG,
                                             selectcolor=PANEL2, activebackground=PANEL, activeforeground=FG,
                                             state='disabled')
        self.track_mute_btn.pack(side='left', padx=8)
        tk.Label(trackbar, text='Gain dB', bg=PANEL, fg=MUTED).pack(side='left')
        self.track_gain_var = tk.DoubleVar(value=0.0)
        self.track_gain_scale = tk.Scale(trackbar, from_=-60, to=24, resolution=1, orient='horizontal', length=150,
                                         variable=self.track_gain_var, command=lambda _v: self._track_edit_changed(),
                                         bg=PANEL, fg=MUTED, troughcolor=PANEL2, highlightthickness=0, state='disabled')
        self.track_gain_scale.pack(side='left')
        tk.Label(trackbar, text='Freq ×', bg=PANEL, fg=MUTED).pack(side='left')
        self.track_freq_var = tk.DoubleVar(value=1.0)
        self.track_freq_scale = tk.Scale(trackbar, from_=0.25, to=4.0, resolution=0.01, orient='horizontal', length=150,
                                         variable=self.track_freq_var, command=lambda _v: self._track_edit_changed(),
                                         bg=PANEL, fg=MUTED, troughcolor=PANEL2, highlightthickness=0, state='disabled')
        self.track_freq_scale.pack(side='left')
        self.track_reset_btn = tk.Button(trackbar, text='Reset track', command=self._reset_track,
                                         bg=PANEL2, fg=FG, relief='flat', state='disabled')
        self.track_reset_btn.pack(side='right', padx=8)

        # Right controls
        right_outer = tk.Frame(main, bg=BG, width=390)
        main.add(right_outer, stretch='never', minsize=360)
        self.ctrl_canvas = tk.Canvas(right_outer, bg=BG, highlightthickness=0, width=380)
        vscroll = ttk.Scrollbar(right_outer, orient='vertical', command=self.ctrl_canvas.yview)
        self.ctrl_canvas.configure(yscrollcommand=vscroll.set)
        vscroll.pack(side='right', fill='y')
        self.ctrl_canvas.pack(side='left', fill='both', expand=True)
        self.ctrl_frame = tk.Frame(self.ctrl_canvas, bg=BG)
        self.ctrl_window = self.ctrl_canvas.create_window((0, 0), window=self.ctrl_frame, anchor='nw')
        self.ctrl_frame.bind('<Configure>', lambda e: self.ctrl_canvas.configure(scrollregion=self.ctrl_canvas.bbox('all')))
        self.ctrl_canvas.bind('<Configure>', lambda e: self.ctrl_canvas.itemconfigure(self.ctrl_window, width=e.width))

        self._build_controls(self.ctrl_frame)

        # Bottom status/buttons
        bottom = tk.Frame(self.root, bg=BG, pady=7)
        bottom.pack(fill='x', padx=10)
        self.status_var = tk.StringVar(value='Ready.')
        tk.Label(bottom, textvariable=self.status_var, bg=BG, fg='#707098',
                 font=('Courier', 9), anchor='w').pack(side='left', fill='x', expand=True)
        self.progress = ttk.Progressbar(bottom, orient='horizontal', length=180, mode='determinate')
        self.progress.pack(side='left', padx=8)
        self.audition_btn = tk.Button(bottom, text='▶ Audition', command=self._on_audition,
                                      bg='#1a3a4e', fg='#a0d0ee', relief='flat', padx=10)
        self.audition_btn.pack(side='left', padx=4)
        tk.Button(bottom, text='■ Stop', command=self._stop_playback,
                  bg='#3a3a1a', fg='#d0d090', relief='flat', padx=10).pack(side='left', padx=4)
        tk.Button(bottom, text='Cancel', command=self._on_cancel,
                  bg='#4e2a2a', fg='#e0c0c0', relief='flat', padx=10).pack(side='left', padx=4)
        self.render_btn = tk.Button(bottom, text='▶ Render to Praat', command=self._on_render_to_praat,
                                    bg='#2a4e2a', fg='#c0e0c0', activebackground='#3a6a3a',
                                    font=('Helvetica', 10, 'bold'), relief='flat', padx=14)
        self.render_btn.pack(side='left', padx=4)

    def _section(self, parent, title):
        tk = self.tk
        box = tk.LabelFrame(parent, text=title, bg=PANEL, fg='#a8a8c8',
                            font=('Helvetica', 9, 'bold'), bd=1, relief='groove', padx=8, pady=6)
        box.pack(fill='x', padx=4, pady=4)
        return box

    def _scale_control(self, parent, key, label, from_, to, resolution, default, length=240):
        tk = self.tk
        row = tk.Frame(parent, bg=PANEL)
        row.pack(fill='x')
        tk.Label(row, text=label, bg=PANEL, fg=FG, width=17, anchor='w').pack(side='left')
        var = tk.DoubleVar(value=default)
        self.vars[key] = var
        val_lbl = tk.Label(row, text='', bg=PANEL, fg='#9999bb', width=9, anchor='e', font=('Courier', 8))
        val_lbl.pack(side='right')
        def changed(v):
            x = float(v)
            val_lbl.config(text=f'{x:.3g}')
            self._preset_custom()
        scl = tk.Scale(row, from_=from_, to=to, resolution=resolution, orient='horizontal', length=length,
                       variable=var, command=changed, bg=PANEL, fg=MUTED, troughcolor=PANEL2,
                       highlightthickness=0, showvalue=False)
        scl.pack(side='left', fill='x', expand=True)
        changed(default)
        return var

    def _build_controls(self, parent):
        tk = self.tk
        ttk = self.ttk

        box = self._section(parent, 'Preset / output')
        row = tk.Frame(box, bg=PANEL); row.pack(fill='x')
        tk.Label(row, text='Preset', bg=PANEL, fg=FG, width=17, anchor='w').pack(side='left')
        self.preset_var = tk.StringVar(value='Faithful')
        cb = ttk.Combobox(row, textvariable=self.preset_var, values=list(PRESETS.keys()), state='readonly', width=19)
        cb.pack(side='left', fill='x', expand=True)
        cb.bind('<<ComboboxSelected>>', lambda e: self._apply_preset(self.preset_var.get()))
        self.sr_var = tk.IntVar(value=self.default_sr)
        row2 = tk.Frame(box, bg=PANEL); row2.pack(fill='x', pady=(4, 0))
        tk.Label(row2, text='Output SR', bg=PANEL, fg=FG, width=17, anchor='w').pack(side='left')
        ttk.Combobox(row2, textvariable=self.sr_var, values=[44100, 48000, 88200, 96000], state='readonly', width=12).pack(side='left')
        self._scale_control(box, 'output_peak', 'Output peak', 0.1, 1.0, 0.01, 0.95)

        box = self._section(parent, 'Spectral transform')
        self._scale_control(box, 'max_partials', 'Max partials/frame', 1, 256, 1, 64)
        self._scale_control(box, 'amplitude_scale', 'Amplitude scale', 0.0, 4.0, 0.01, 1.0)
        self._scale_control(box, 'transpose_ratio', 'Transpose ratio', 0.125, 4.0, 0.005, 1.0)
        self._scale_control(box, 'inharmonicity', 'Inharmonicity', 0.4, 2.2, 0.005, 1.0)
        self._scale_control(box, 'frequency_shift', 'Frequency shift Hz', -2000, 2000, 1, 0.0)
        self._scale_control(box, 'brightness', 'Brightness tilt', -2.0, 2.0, 0.01, 0.0)
        self._scale_control(box, 'gate', 'Amplitude gate', 0.0, 0.20, 0.001, 0.0)
        self._scale_control(box, 'band_low', 'Band low Hz', 0, 12000, 10, 0.0)
        self._scale_control(box, 'band_high', 'Band high Hz', 100, 24000, 10, 20000.0)
        row = tk.Frame(box, bg=PANEL); row.pack(fill='x', pady=(4, 0))
        tk.Label(row, text='Harmonic select', bg=PANEL, fg=FG, width=17, anchor='w').pack(side='left')
        self.harmonic_var = tk.StringVar(value='All')
        self.vars['harmonic'] = self.harmonic_var
        hcb = ttk.Combobox(row, textvariable=self.harmonic_var, values=['All', 'Odd', 'Even'], state='readonly', width=12)
        hcb.pack(side='left'); hcb.bind('<<ComboboxSelected>>', lambda e: self._preset_custom())

        box = self._section(parent, 'Time / phase')
        self._scale_control(box, 'time_stretch', 'Time stretch', 0.25, 8.0, 0.01, 1.0)
        self.reverse_var = tk.BooleanVar(value=False); self.vars['reverse'] = self.reverse_var
        tk.Checkbutton(box, text='Reverse', variable=self.reverse_var, command=self._preset_custom,
                       bg=PANEL, fg=FG, selectcolor=PANEL2, activebackground=PANEL, activeforeground=FG).pack(anchor='w')
        self._scale_control(box, 'freeze_frame', 'Freeze frame (0 off)', 0, 1000, 1, 0)
        row = tk.Frame(box, bg=PANEL); row.pack(fill='x', pady=(4, 0))
        tk.Label(row, text='Phase mode', bg=PANEL, fg=FG, width=17, anchor='w').pack(side='left')
        self.phase_var = tk.StringVar(value=DEFAULTS['phase_mode']); self.vars['phase_mode'] = self.phase_var
        pcb = ttk.Combobox(row, textvariable=self.phase_var,
                           values=['Praat-compatible', 'SDIF phase', 'Track-continuous'], state='readonly', width=18)
        pcb.pack(side='left'); pcb.bind('<<ComboboxSelected>>', lambda e: self._preset_custom())

        box = self._section(parent, 'Praat Sound analysis')
        self.analysis_hop_var = tk.DoubleVar(value=0.01)
        self.analysis_max_var = tk.DoubleVar(value=8000.0)
        self.analysis_thr_var = tk.DoubleVar(value=0.01)
        for label, var, frm, to, res in [
            ('Hop s', self.analysis_hop_var, 0.002, 0.05, 0.001),
            ('Max freq Hz', self.analysis_max_var, 1000, 20000, 100),
            ('Peak threshold', self.analysis_thr_var, 0.001, 0.20, 0.001),
        ]:
            r = tk.Frame(box, bg=PANEL); r.pack(fill='x')
            tk.Label(r, text=label, bg=PANEL, fg=FG, width=17, anchor='w').pack(side='left')
            tk.Scale(r, from_=frm, to=to, resolution=res, orient='horizontal', length=220, variable=var,
                     bg=PANEL, fg=MUTED, troughcolor=PANEL2, highlightthickness=0).pack(side='left', fill='x', expand=True)
        self.reanalyse_btn = tk.Button(box, text='Re-analyse selected Praat Sound', command=self._use_praat_sound,
                                       bg=PANEL2, fg=FG, relief='flat')
        self.reanalyse_btn.pack(fill='x', pady=(5, 0))
        if not self.praat_sound_file:
            self.reanalyse_btn.config(state='disabled')

        tk.Button(parent, text='Reset ALL track edits', command=self._reset_all_tracks,
                  bg='#3a2a3a', fg='#d0b0d0', relief='flat').pack(fill='x', padx=6, pady=7)

    # ------------------------------- source --------------------------------
    def _initial_source(self):
        # A selected Praat Sound has priority; otherwise restore the last file.
        if self.praat_sound_file and os.path.isfile(self.praat_sound_file):
            self.root.after(100, self._use_praat_sound)
            return
        state_path = self._state_dict.get('last_source', '') if hasattr(self, '_state_dict') else ''
        if state_path and os.path.isfile(state_path):
            self.root.after(100, lambda: self._load_file(state_path))

    def _open_file(self):
        p = self.filedialog.askopenfilename(
            title='Open SPEAR / SDIF',
            filetypes=[('SPEAR / SDIF', '*.sdif *.txt *.spear'), ('SDIF', '*.sdif'), ('SPEAR text', '*.txt *.spear'), ('All files', '*.*')])
        if p:
            self._load_file(p)

    def _load_file(self, p):
        if self._busy:
            return
        self.status_var.set(f'Loading {Path(p).name}…')
        self.root.update_idletasks()
        try:
            t0 = time.perf_counter()
            self.data = load_source(p)
            self._load_seconds = time.perf_counter() - t0
            self.source_path = str(p)
            self.source_label = f'{Path(p).name}  |  {len(self.data.frames)} frames  |  {len(self.data.track_ids)} tracks  |  {self.data.duration:.2f}s'
            self.source_var.set(self.source_label)
            self.track_edits = {}
            self.selected_track = None
            self._sync_freeze_max()
            self._draw_trajectories()
            self.status_var.set(f'Loaded in {self._load_seconds:.3f}s. Ready.')
            self._save_state()
        except Exception as exc:
            self.messagebox.showerror('Load error', str(exc))
            self.status_var.set(f'Load error: {exc}')

    def _use_praat_sound(self):
        if not self.praat_sound_file or not os.path.isfile(self.praat_sound_file) or self._busy:
            return
        self.status_var.set('Analysing selected Praat Sound with NumPy…')
        self.root.update_idletasks()
        try:
            t0 = time.perf_counter()
            self.data = analyse_wav(self.praat_sound_file,
                                    hop=float(self.analysis_hop_var.get()),
                                    max_freq=float(self.analysis_max_var.get()),
                                    threshold=float(self.analysis_thr_var.get()))
            self._load_seconds = time.perf_counter() - t0
            self.source_path = ''
            self.source_label = f'Praat: {self.praat_sound_name or Path(self.praat_sound_file).stem}  |  {len(self.data.frames)} frames  |  {len(self.data.track_ids)} peaks  |  {self.data.duration:.2f}s'
            self.source_var.set(self.source_label)
            self.track_edits = {}
            self.selected_track = None
            self.sr_var.set(self.data.sample_rate)
            self._sync_freeze_max()
            self._draw_trajectories()
            self.status_var.set(f'Analysed in {self._load_seconds:.3f}s. Ready.')
        except Exception as exc:
            self.messagebox.showerror('Analysis error', str(exc))
            self.status_var.set(f'Analysis error: {exc}')

    def _sync_freeze_max(self):
        # Locate the Tk Scale backing freeze_frame and make its range meaningful.
        n = len(self.data.frames) if self.data else 1000
        # The control remains safe even if this traversal changes; value is clamped in renderer.
        if self.vars['freeze_frame'].get() > n:
            self.vars['freeze_frame'].set(0)

    # ------------------------------ parameters -----------------------------
    def _get_params(self):
        p = {}
        for k in ('max_partials', 'amplitude_scale', 'transpose_ratio', 'inharmonicity',
                  'frequency_shift', 'brightness', 'gate', 'band_low', 'band_high',
                  'time_stretch', 'freeze_frame', 'output_peak'):
            p[k] = float(self.vars[k].get())
        p['max_partials'] = int(round(p['max_partials']))
        p['freeze_frame'] = int(round(p['freeze_frame']))
        p['harmonic'] = self.harmonic_var.get()
        p['reverse'] = bool(self.reverse_var.get())
        p['phase_mode'] = self.phase_var.get()
        return p

    def _set_params(self, p):
        for k, v in p.items():
            if k in self.vars:
                try:
                    self.vars[k].set(v)
                except Exception:
                    pass
        if 'harmonic' in p: self.harmonic_var.set(p['harmonic'])
        if 'reverse' in p: self.reverse_var.set(bool(p['reverse']))
        if 'phase_mode' in p: self.phase_var.set(p['phase_mode'])

    def _apply_preset(self, name):
        if name == 'Custom':
            return
        p = dict(PRESETS.get(name, DEFAULTS))
        if name == 'FrozenDrone' and self.data:
            p['freeze_frame'] = max(1, int(round(len(self.data.frames) * 0.5)))
        self._applying_preset = True
        try:
            self._set_params(p)
            self.preset_var.set(name)
        finally:
            self._applying_preset = False

    def _preset_custom(self):
        if self._applying_preset:
            return
        if hasattr(self, 'preset_var') and self.preset_var.get() not in ('', 'Custom'):
            self.preset_var.set('Custom')

    # ---------------------------- trajectory view --------------------------
    def _heat_color(self, amp, max_amp):
        if max_amp <= 0: return '#244064'
        t = (math.log10(max(amp, max_amp / 1000.0)) - math.log10(max_amp / 1000.0)) / 3.0
        t = max(0.0, min(1.0, t))
        stops = [(0.08, 0.25, 0.55), (0.05, 0.65, 0.80), (0.20, 0.75, 0.35), (0.95, 0.75, 0.15), (0.90, 0.20, 0.15)]
        x = t * (len(stops) - 1)
        i = min(len(stops) - 2, int(math.floor(x)))
        f = x - i
        a, b = stops[i], stops[i + 1]
        rgb = [int(255 * (a[j] + (b[j] - a[j]) * f)) for j in range(3)]
        return '#%02x%02x%02x' % tuple(rgb)

    def _track_summary(self):
        sums = {}
        pts = {}
        for fr in self.data.frames:
            t = float(fr['time'] - self.data.times[0])
            for tid, fq, am in zip(fr['idx'], fr['freq'], fr['amp']):
                tid = int(tid)
                sums[tid] = sums.get(tid, 0.0) + float(am)
                pts.setdefault(tid, []).append((t, float(fq), float(am)))
        return sums, pts

    def _draw_trajectories(self):
        c = getattr(self, 'canvas', None)
        if not c:
            return
        c.delete('all')
        w = max(100, c.winfo_width())
        h = max(100, c.winfo_height())
        pad_l, pad_r, pad_t, pad_b = 58, 18, 24, 38
        c.create_rectangle(0, 0, w, h, fill='#0b0b14', outline='')
        if not self.data:
            c.create_text(w/2, h/2, text='Open an SDIF / SPEAR file\nor select a Praat Sound',
                          fill='#606080', font=('Helvetica', 13), justify='center')
            return
        sums, pts = self._track_summary()
        topn = max(10, int(self.view_tracks_var.get()))
        tids = sorted(sums, key=sums.get, reverse=True)[:topn]
        dur = max(self.data.duration, 1e-6)
        fmin = max(20.0, min((p[1] for tid in tids for p in pts[tid] if p[1] > 0), default=20.0))
        fmax = max(1000.0, min(self.data.max_freq * 1.05, 20000.0))
        loglo, loghi = math.log10(fmin), math.log10(fmax)
        def X(t): return pad_l + (w - pad_l - pad_r) * (t / dur)
        def Y(f):
            lf = math.log10(max(f, fmin))
            return pad_t + (h - pad_t - pad_b) * (1.0 - (lf - loglo) / max(loghi - loglo, 1e-9))

        # grid + labels
        for hz in [50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000]:
            if fmin <= hz <= fmax:
                y = Y(hz)
                c.create_line(pad_l, y, w-pad_r, y, fill='#202033')
                c.create_text(pad_l-6, y, text=(f'{hz/1000:g}k' if hz >= 1000 else str(hz)),
                              fill='#666688', font=('Courier', 8), anchor='e')
        for k in range(6):
            t = dur * k / 5
            x = X(t)
            c.create_line(x, pad_t, x, h-pad_b, fill='#171728')
            c.create_text(x, h-pad_b+10, text=f'{t:.2f}', fill='#666688', font=('Courier', 8), anchor='n')
        c.create_text(10, (pad_t+h-pad_b)/2, text='Hz', fill='#777799', font=('Courier', 8), angle=90)
        c.create_text((pad_l+w-pad_r)/2, h-8, text='Time (s)', fill='#777799', font=('Courier', 8))

        for tid in tids:
            p = pts[tid]
            if len(p) < 2:
                continue
            ed = self.track_edits.get(tid, {})
            freq_ratio = float(ed.get('freq_ratio', 1.0))
            gain_lin = 10.0 ** (float(ed.get('gain_db', 0.0)) / 20.0)
            coords = []
            for t, fq, am in p:
                fq_draw = fq * freq_ratio
                if fmin <= fq_draw <= fmax:
                    coords.extend((X(t), Y(fq_draw)))
            if len(coords) < 4:
                continue
            avg = (sums[tid] / max(len(p), 1)) * gain_lin
            col = self._heat_color(avg, self.data.max_amp)
            if ed.get('mute', False):
                col = '#333344'
            width = 3 if tid == self.selected_track else 1
            item = c.create_line(*coords, fill=col, width=width, smooth=False, tags=(f'track_{tid}', 'trajectory'))
            if tid == self.selected_track:
                c.itemconfigure(item, fill='#ffffff')

        c.create_rectangle(pad_l, pad_t, w-pad_r, h-pad_b, outline='#55556e')
        c.create_text(pad_l+5, pad_t+5,
                      text=f'{len(self.data.frames)} frames   {len(self.data.track_ids)} tracks   showing {min(topn, len(tids))}',
                      fill='#8888aa', font=('Courier', 8), anchor='nw')

    def _on_canvas_click(self, event):
        items = self.canvas.find_overlapping(event.x-3, event.y-3, event.x+3, event.y+3)
        tid = None
        for item in reversed(items):
            for tag in self.canvas.gettags(item):
                if tag.startswith('track_'):
                    try: tid = int(tag.split('_', 1)[1])
                    except Exception: pass
                    break
            if tid is not None: break
        if tid is None:
            return
        self.selected_track = tid
        ed = self.track_edits.get(tid, {'mute': False, 'gain_db': 0.0, 'freq_ratio': 1.0})
        self.track_label.set(f'Track: {tid}')
        self.track_mute_var.set(bool(ed.get('mute', False)))
        self.track_gain_var.set(float(ed.get('gain_db', 0.0)))
        self.track_freq_var.set(float(ed.get('freq_ratio', 1.0)))
        for widget in (self.track_mute_btn, self.track_gain_scale, self.track_freq_scale, self.track_reset_btn):
            widget.config(state='normal')
        self._draw_trajectories()

    def _track_edit_changed(self):
        if self.selected_track is None:
            return
        self.track_edits[self.selected_track] = {
            'mute': bool(self.track_mute_var.get()),
            'gain_db': float(self.track_gain_var.get()),
            'freq_ratio': float(self.track_freq_var.get()),
        }
        self._draw_trajectories()

    def _reset_track(self):
        if self.selected_track is None: return
        self.track_edits.pop(self.selected_track, None)
        self.track_mute_var.set(False); self.track_gain_var.set(0.0); self.track_freq_var.set(1.0)
        self._draw_trajectories()

    def _reset_all_tracks(self):
        self.track_edits = {}
        if self.selected_track is not None:
            self.track_mute_var.set(False); self.track_gain_var.set(0.0); self.track_freq_var.set(1.0)
        self._draw_trajectories()

    # ------------------------------- render --------------------------------
    def _set_busy(self, busy):
        self._busy = busy
        state = 'disabled' if busy else 'normal'
        self.render_btn.config(state=state)
        self.audition_btn.config(state=state)
        self.progress['value'] = 0 if not busy else self.progress['value']

    def _progress(self, x):
        self.root.after(0, lambda: self.progress.configure(value=max(0, min(100, 100*x))))

    def _render_worker(self, mode):
        try:
            params = self._get_params()
            sr = int(self.sr_var.get())
            preview = 12.0 if mode == 'audition' else None
            audio, metrics = render_audio(self.data, params, dict(self.track_edits), sr,
                                          max_seconds=preview, progress_cb=self._progress)
            self.root.after(0, lambda: self._render_finished(mode, audio, sr, metrics, params))
        except Exception as exc:
            tb = traceback.format_exc()
            self.root.after(0, lambda: self._render_failed(exc, tb))

    def _start_render(self, mode):
        if self._busy:
            return
        if not self.data:
            self.messagebox.showwarning('No source', 'Open an SDIF/SPEAR file or use the selected Praat Sound first.')
            return
        # Clear any error file left by an earlier failed render. The launcher
        # tests error_file BEFORE done_file, so without this a single failure
        # poisons every later success in the same session: Praat would report
        # a crash and discard a perfectly good WAV.
        if self.error_file:
            try:
                os.remove(self.error_file)
            except OSError:
                pass
        self._set_busy(True)
        self.status_var.set('Rendering preview…' if mode == 'audition' else 'Fast NumPy render…')
        threading.Thread(target=self._render_worker, args=(mode,), daemon=True).start()

    def _render_finished(self, mode, audio, sr, metrics, params):
        self._set_busy(False)
        self.progress['value'] = 100
        self._last_render = (audio, sr)
        if mode == 'audition':
            try:
                import sounddevice as sd
                sd.stop(); sd.play(audio, samplerate=sr, blocking=False)
                self.status_var.set(f'▶ Preview {len(audio)/sr:.2f}s | render {metrics["render_seconds"]:.3f}s')
            except Exception as exc:
                self.status_var.set(f'Preview rendered in {metrics["render_seconds"]:.3f}s; playback unavailable: {exc}')
            return

        write_mono_wav(self.result_file, audio, sr)
        source_name = self.data.source_name or 'spear'
        if self.name_file:
            Path(self.name_file).write_text(source_name, encoding='utf-8')
        total = getattr(self, '_load_seconds', 0.0) + metrics['render_seconds']
        if self.report_file:
            report = (
                f'Source:      {source_name}\n'
                f'Kind:        {self.data.source_kind}\n'
                f'Frames:      {len(self.data.frames)} source -> {metrics["frames"]} output\n'
                f'Tracks:      {len(self.data.track_ids)}\n'
                f'Sample rate: {sr} Hz\n'
                f'Load/parse:  {getattr(self, "_load_seconds", 0.0):.3f} s\n'
                f'Resynthesis: {metrics["render_seconds"]:.3f} s\n'
                f'Total DSP:   {total:.3f} s\n'
                f'Edits:       {len(self.track_edits)} track-specific\n'
                f'Phase mode:  {params["phase_mode"]}\n'
            )
            Path(self.report_file).write_text(report, encoding='utf-8')
        Path(self.done_file).write_text(json.dumps({
            'result': self.result_file,
            'source': source_name,
            'duration': len(audio) / sr,
            'sample_rate': sr,
            'render_seconds': metrics['render_seconds'],
        }, indent=2), encoding='utf-8')
        self._save_state()
        self._cancelled = False
        self.status_var.set(f'Done in {metrics["render_seconds"]:.3f}s — returning to Praat…')
        self.root.after(350, self.root.destroy)

    def _render_failed(self, exc, tb):
        self._set_busy(False)
        self.status_var.set(f'ERROR: {exc}')
        try:
            Path(self.error_file).write_text(tb, encoding='utf-8')
        except Exception:
            pass
        self.messagebox.showerror('Render error', str(exc))

    def _on_audition(self):
        self._start_render('audition')

    def _on_render_to_praat(self):
        self._stop_playback()
        self._start_render('praat')

    def _stop_playback(self):
        try:
            import sounddevice as sd
            sd.stop()
        except Exception:
            pass
        if hasattr(self, 'status_var'):
            self.status_var.set('Stopped.')

    def _on_cancel(self):
        if self._busy:
            return
        self._stop_playback()
        self._save_state()
        self._cancelled = True
        self.root.destroy()

    # ------------------------------- state ---------------------------------
    def _load_state(self):
        self._state_dict = {}
        if not self.state_file:
            self._apply_preset('Faithful')
            return
        try:
            if os.path.isfile(self.state_file):
                self._state_dict = json.loads(Path(self.state_file).read_text(encoding='utf-8'))
                p = self._state_dict.get('params', {})
                if p:
                    self._set_params(p)
                if 'sample_rate' in self._state_dict:
                    self.sr_var.set(int(self._state_dict['sample_rate']))
            else:
                self._apply_preset('Faithful')
        except Exception:
            self._apply_preset('Faithful')

    def _save_state(self):
        if not self.state_file:
            return
        try:
            Path(self.state_file).parent.mkdir(parents=True, exist_ok=True)
            state = {
                'last_source': self.source_path if self.source_path else self._state_dict.get('last_source', '') if hasattr(self, '_state_dict') else '',
                'params': self._get_params(),
                'sample_rate': int(self.sr_var.get()),
            }
            Path(self.state_file).write_text(json.dumps(state, indent=2), encoding='utf-8')
            self._state_dict = state
        except Exception:
            pass

    def run(self):
        self.root.mainloop()
        return not self._cancelled


# -----------------------------------------------------------------------------
# SELF TEST / ENTRY POINT
# -----------------------------------------------------------------------------

def selftest(paths):
    for p in paths:
        t0 = time.perf_counter()
        d = load_source(p)
        print(f'{Path(p).name}: {len(d.frames)} frames, {len(d.track_ids)} tracks, hop={d.hop:.6f}s, parse={time.perf_counter()-t0:.3f}s')
        y, m = render_audio(d, dict(DEFAULTS), {}, 44100, max_seconds=0.5)
        print(f'  render 0.5s -> {len(y)} samples in {m["render_seconds"]:.3f}s, peak={float(np.max(np.abs(y))):.4f}')


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == '--selftest':
        selftest(sys.argv[2:])
        return
    if len(sys.argv) < 2:
        print('Usage: spear_fast_gui.py <manifest.json> | --selftest file.sdif [file.txt]', file=sys.stderr)
        sys.exit(1)
    manifest_path = sys.argv[1]
    if not os.path.isfile(manifest_path):
        print(f'ERROR: manifest not found: {manifest_path}', file=sys.stderr)
        sys.exit(1)
    try:
        app = SpearFastApp(manifest_path)
        ok = app.run()
        sys.exit(0 if ok else 1)
    except Exception as exc:
        _crash(exc)


if __name__ == '__main__':
    main()
