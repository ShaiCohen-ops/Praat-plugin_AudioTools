#!/usr/bin/env python3
# ============================================================
# Praat AudioTools Plugin
# Script:      performance_launcher.py
# Author:      Shai Cohen
# Version:     1.7.3 (2026) — MIDI keyboard input + note-to-cue mapping
# License:     MIT License
#
# Description:
#   Real-time multichannel audio cue launcher for live performance.
#   Accepts a manifest JSON from PerformanceLauncher.praat, loads
#   each cue into memory, and provides a keyboard- and MIDI-triggered
#   GUI for firing cues to any output channel configuration with
#   per-cue gain, fade-in/out, output-channel offset, and progress display.
#
# Usage (called by PerformanceLauncher.praat):
#   python performance_launcher.py <manifest.json>
#
# MIDI (optional — needs: python -m pip install python-rtmidi):
#   - Pick a port in "MIDI In". Without python-rtmidi the launcher runs
#     exactly as before; the MIDI row just says how to enable it.
#   - Default map: cue 1 = C3 (note 48), then chromatic upward.
#   - Per cue: click the note button, then press a key  -> learn.
#              right-click the note button               -> clear.
#   - Layout: Chromatic (every key) or Diatonic (white keys only).
#     Switching re-lays all cues from cue 1's current key.
#   - "Map from key…": the next key pressed becomes cue 1, the rest
#     follow in the selected layout (re-lays the keyboard in one press).
#   - Stop key (red "■" button): the next layout key after the last cue
#     fades out everything playing. Follows every re-lay; click = learn,
#     right-click = clear.
#   - Note-off stops: gate mode (key release fades the cue out).
#   - Velocity: velocity scales cue gain ((v/127)^2 amplitude law).
#   - CC 120 / CC 123 (All Sound Off / All Notes Off) = Stop All.
#   Note names use middle C = C4 = 60 (some keyboards label it C3).
#
# Changelog v1.7.3:
#   - NEW: MIDI Stop key, placed on the next key after the last cue in the
#     current layout (chromatic: next semitone, diatonic: next white key);
#     moves with layout changes and "Map from key…", learnable/clearable,
#     persisted. Fades out all playing cues (same as Esc / Stop All).
#
# Changelog v1.7.2:
#   - NEW: Chromatic / Diatonic layout selector (diatonic = white keys,
#     black-key start snaps up). Drives the startup default, the layout
#     switch itself, and "Map from key…". Persisted in config.
#
# Changelog v1.7.1:
#   - FIX: keys (computer and, apparently, MIDI) seemed dead after picking
#     a MIDI port / audio device: the combobox kept keyboard focus and the
#     typing guard swallowed every key, with nothing returning focus. The
#     guard now covers only text fields; dropdown picks, clicks on buttons/
#     checkboxes/slider/background, Return and Esc hand focus back.
#   - Window raises and takes focus at launch (it often opened behind
#     Praat on Windows, so keys went to Praat).
#   - MIDI indicator shows notes dropped by the channel filter, and
#     'waiting for notes…' once a port is open, for diagnosis.
#
# Changelog v1.7:
#   - NEW: MIDI keyboard input via python-rtmidi (optional dependency).
#     Port selector + refresh, channel filter (Omni/1-16), per-cue note
#     learn/clear, "Map from key…" chromatic re-map, gate (note-off stops),
#     velocity-to-gain, CC 120/123 panic, last-note indicator.
#   - Cues fire directly on the MIDI thread (engine is lock-protected) for
#     lowest latency; Tk is touched only from the main thread via a queue.
#   - Live per-cue gain edits now preserve each instance's velocity scaling.
#   - MIDI port is restored by name (trailing OS port numbers ignored, since
#     WinMM/ALSA renumber them); an absent port is remembered, not forgotten.
#   - Esc also cancels a pending MIDI learn.
#   - Version jumps 1.5 -> 1.7 to sync with PerformanceLauncher.praat.
#
# Changelog v1.5:
#   - Fixed config persistence: config is no longer deleted at shutdown.
#   - Cue settings are matched by cue name when selection order changes,
#     preventing old cue-index settings from being applied to a new sound.
#   - Restores audio devices by name + host API before falling back to index.
#   - Keyboard cue triggers/master shortcuts are suppressed while editing GUI
#     fields, preventing accidental cue fires while typing gain/channel values.
#   - Prevents implicit modulo fold-down when a cue has more channels than the
#     open output stream; playback is blocked with a clear status message.
#   - Fade lengths are clamped to cue duration, so short cues do not start
#     pre-attenuated when fade-out exceeds file length.
#   - Natural and triggered stop fades now combine without gain jumps, reach
#     exact zero, and the final stop-fade block is mixed before removal.
#   - Gain/channel/fade spinboxes now update on typed edits as well as arrows;
#     fade-in/out are exposed in the cue row and persisted in config.
#   - Loaded WAV sample rate and channel count are validated against the project.
#   - PortAudio callback status flags are surfaced in the GUI without file I/O
#     from the real-time callback.
#
# Changelog v1.4:
#   - ASIO auto-enabled on Windows (SD_ENABLE_ASIO set before sounddevice is
#     imported). Multichannel interfaces (e.g. PreSonus Studio 68c) only expose
#     >2 outputs under ASIO; under MME/DirectSound/WASAPI/WDM-KS they fragment
#     into stereo pairs, so the device was previously unreachable for >2ch out.
#   - Device picker labels now include the host API, e.g.
#     "26: Studio USB ASIO Driver (6ch) [ASIO]", so the multichannel device is
#     unambiguous when the same hardware appears under several host APIs.
#   - Stream-open failures now name the likely cause (sample-rate mismatch --
#     ASIO does not resample -- or device already in use) in the status bar.
#   - Line endings normalized to LF (file previously had mixed CRLF/LF).
#
# Changelog v1.3:
#   - Live master gain from the keyboard: Up/Down nudge master +/-1 dB
#     (coarse), Right/Left +/-0.1 dB (fine), clamped to the slider range.
#     The on-screen Master Gain slider follows (it is bound to the same
#     var) and the value persists in config as before. Master slider
#     resolution refined 0.5 -> 0.1 dB so the fine step is representable.
#     Arrow keysyms were previously unused (DEFAULT_KEYS is digits +
#     letters), so cue triggering is unaffected.
#
# Changelog v1.2:
#   - Real-time fix: the natural (end-of-file) fade-out in the audio
#     callback was a per-sample Python `for` loop -- up to blocksize
#     iterations per cue per callback, inside the RT thread, a real
#     xrun risk under load. Replaced with a vectorized numpy ramp,
#     identical math, matching the already-vectorized triggered-stop
#     fade-out.
#   - Mono->mono gain guard: a mono cue is only duplicated to two
#     channels when the output has >= 2 channels. Previously, with a
#     1-channel output, both duplicated copies wrapped onto channel 0
#     and summed (a silent ~+6 dB bump on mono cues).
#   - Removed the dead done-file handshake: write_done_file() and its
#     call/field are gone (PerformanceLauncher.praat only ever read
#     the error file; the done file was written then deleted, never
#     consumed). Config persistence is unchanged.
#   - Version synced to 1.2 across the Praat front-end (header, info
#     log, and manifest plugin_version).
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
import time
import traceback
import threading
import tkinter as tk
from tkinter import ttk
from tkinter import messagebox

# ── Enable ASIO on Windows ────────────────────────────────────────────
# Must run before sounddevice is first imported (below). The pip wheel ships
# an ASIO-capable PortAudio DLL but loads the non-ASIO one unless
# SD_ENABLE_ASIO is set. Multichannel interfaces (e.g. PreSonus Studio 68c)
# only appear as a single >2-output device under ASIO; under MME / DirectSound
# / WASAPI / WDM-KS they fragment into stereo pairs and cannot do >2 channels.
# setdefault() lets an explicit external override stand.
if sys.platform == "win32":
    os.environ.setdefault("SD_ENABLE_ASIO", "1")

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

# MIDI is optional: the launcher must keep working without it.
try:
    import rtmidi
    _RTMIDI_ERR = ''
except Exception as e:          # ImportError, or a broken backend DLL/.so
    rtmidi = None
    _RTMIDI_ERR = str(e)

import re
import queue

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

# Master gain range (dB) — shared by the slider and the arrow-key nudges
MASTER_MIN_DB         = -40.0
MASTER_MAX_DB         =  12.0
MASTER_STEP_COARSE_DB =   1.0
MASTER_STEP_FINE_DB   =   0.1

# MIDI
MIDI_DEFAULT_BASE_NOTE = 48          # C3: cue 1 lands mid-keyboard on 25/49/61-key boards
MIDI_NONE_LABEL        = "(none)"
MIDI_CHANNEL_VALUES    = ("Omni",) + tuple(str(c) for c in range(1, 17))
MIDI_LEARN_COLOR       = "#c04060"
# Widgets where typed keys are text, not cue triggers.
TEXT_ENTRY_CLASSES = {'Entry', 'TEntry', 'Spinbox', 'TSpinbox', 'Text'}
_NOTE_NAMES = ('C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B')

def midi_note_name(n):
    """60 -> 'C4' (middle C = C4)."""
    if n is None or n < 0 or n > 127:
        return '—'
    return f"{_NOTE_NAMES[n % 12]}{n // 12 - 1}"

MIDI_LAYOUTS = ('Chromatic', 'Diatonic')
_WHITE_KEYS = {0, 2, 4, 5, 7, 9, 11}

def layout_notes(base, count, layout):
    """Notes for `count` cues from `base`. Chromatic: every key. Diatonic:
    white keys only (a black-key base snaps up to the next white key).
    Cues that run past note 127 get -1 (unmapped)."""
    notes = []
    n = int(base)
    if layout == 'Diatonic':
        while n % 12 not in _WHITE_KEYS:
            n += 1
    for _ in range(count):
        notes.append(n if 0 <= n <= 127 else -1)
        n += 1
        if layout == 'Diatonic':
            while n % 12 not in _WHITE_KEYS:
                n += 1
    return notes

def next_layout_note(after, layout):
    """First key above `after` in the layout (-1 if past 127)."""
    n = layout_notes(int(after) + 1, 1, layout)[0]
    return n

def _norm_port_name(name):
    # WinMM appends " 0", " 1"…; ALSA appends " 20:0". Both renumber across
    # reboots/replugs, so compare without them.
    return re.sub(r'\s+\d+(:\d+)?$', '', name or '').strip()

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
        self.output_offset = int(data.get('output_offset', 0))
        self.mono_to_stereo = True if self.channels == 1 else False
        # MIDI note 0-127; -1 = deliberately unmapped; None = not yet set
        # (gets the chromatic default after config restore).
        self.midi_note = None

        self.audio_data = None
        self.status = "READY"

class CueInstance:
    def __init__(self, cue, sample_rate, vel_scale=1.0):
        self.cue = cue
        self.current_frame = 0
        # vel_scale is fixed per trigger; live gain edits multiply it back in.
        self.vel_scale = float(vel_scale)
        self.gain_linear = 10.0 ** (cue.gain_db / 20.0) * self.vel_scale
        self.is_stopping = False
        # Guard against zero-frame divisions and clamp fades to cue length.
        # A fade longer than the cue should span the whole cue, not make the
        # first sample start part-way through an overlong fade.
        total_frames = cue.audio_data.shape[0] if cue.audio_data is not None else 0
        fi = max(1, int(cue.fade_in * sample_rate)) if cue.fade_in > 0 else 0
        fo = max(1, int(cue.fade_out * sample_rate)) if cue.fade_out > 0 else 0
        self.fade_in_frames = min(fi, total_frames) if total_frames > 0 else fi
        self.fade_out_frames = min(fo, total_frames) if total_frames > 0 else fo
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
        self.last_callback_status = ''
        self.callback_status_count = 0

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
        api_name = ''
        try:
            dev = sd.query_devices(device_index)
            max_out = int(dev['max_output_channels'])
            try:
                api_name = sd.query_hostapis(dev['hostapi'])['name']
            except Exception:
                api_name = ''
            if num_channels < 1:
                raise ValueError("output channel count must be >= 1")
            if num_channels > max_out:
                raise ValueError(
                    f"requested {num_channels} output channels, but device provides {max_out}")
            self.stream = sd.OutputStream(
                samplerate=self.sample_rate,
                channels=self.output_channels,
                dtype='float32',
                device=device_index,
                blocksize=512,
                callback=self._audio_callback
            )
            self.stream.start()
            self.log_event(
                f"Audio stream opened: {self.output_channels}ch @ {self.sample_rate} Hz"
                + (f" [{api_name}]" if api_name else ''))
            return True
        except Exception as e:
            if 'ASIO' in api_name.upper():
                hint = (f"check the interface is set to {self.sample_rate} Hz "
                        f"(ASIO does not resample) and is not already in use")
            else:
                hint = (f"check that the device supports {self.sample_rate} Hz / "
                        f"{num_channels} output channel(s) and is not already in use")
            err = f"Failed to open audio stream: {e}  ({hint})"
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

    def clear_playback(self):
        """Immediately clear active cues/test tones (used for device changes)."""
        with self.lock:
            for inst in self.active_cues:
                inst.cue.status = "READY"
            self.active_cues.clear()
            self.test_signals.clear()

    def _audio_callback(self, outdata, frames, time_info, status):
        outdata.fill(0)
        # Never print/write files in the real-time callback. Keep only a small
        # status snapshot for the GUI polling thread to surface later.
        if status:
            self.last_callback_status = str(status)
            self.callback_status_count += 1
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

                # Apply fade-in. Linear law is retained, but the ramp now
                # reaches unity on the final fade sample.
                if inst.fade_in_frames > 0 and inst.current_frame < inst.fade_in_frames:
                    fi_end = min(inst.current_frame + chunk_len, inst.fade_in_frames)
                    n = fi_end - inst.current_frame
                    if inst.fade_in_frames <= 1:
                        ramp = np.ones(n, dtype=np.float32)
                    else:
                        idx = np.arange(inst.current_frame, fi_end, dtype=np.float32)
                        ramp = idx / float(inst.fade_in_frames - 1)
                    chunk[:n] *= ramp[:, np.newaxis] if chunk.ndim > 1 else ramp

                # Natural end fade is always applied, including while a
                # triggered stop is in progress. This prevents a stop command
                # during the natural tail from jumping the gain back toward 1.
                if inst.fade_out_frames > 0:
                    fo_start_frame = total_frames - inst.fade_out_frames
                    abs_start = inst.current_frame
                    abs_end = inst.current_frame + chunk_len
                    if abs_end > fo_start_frame:
                        ofs = max(0, fo_start_frame - abs_start)
                        abs_idx = np.arange(abs_start + ofs, abs_end, dtype=np.float32)
                        pos = abs_idx - fo_start_frame
                        if inst.fade_out_frames <= 1:
                            ramp = np.zeros(len(pos), dtype=np.float32)
                        else:
                            ramp = 1.0 - pos / float(inst.fade_out_frames - 1)
                            ramp = np.clip(ramp, 0.0, 1.0)
                        if chunk.ndim > 1:
                            chunk[ofs:] *= ramp[:, np.newaxis]
                        else:
                            chunk[ofs:] *= ramp

                # Triggered stop fade is multiplicative with the natural fade.
                if inst.is_stopping:
                    remaining_stop = inst.fade_out_frames - inst.stop_frame_elapsed
                    fo_len = min(chunk_len, max(0, remaining_stop))
                    if fo_len > 0:
                        if inst.fade_out_frames <= 1:
                            ramp = np.zeros(fo_len, dtype=np.float32)
                        else:
                            idx = np.arange(inst.stop_frame_elapsed,
                                            inst.stop_frame_elapsed + fo_len,
                                            dtype=np.float32)
                            ramp = 1.0 - idx / float(inst.fade_out_frames - 1)
                            ramp = np.clip(ramp, 0.0, 1.0)
                        chunk[:fo_len] *= ramp[:, np.newaxis] if chunk.ndim > 1 else ramp
                    chunk[fo_len:] = 0
                    inst.stop_frame_elapsed += fo_len
                    if inst.fade_out_frames == 0 or inst.stop_frame_elapsed >= inst.fade_out_frames:
                        # Mark done, but still mix this final faded block.
                        # Continuing here would discard the whole block and turn
                        # short stop-fades into an abrupt mute.
                        inst.state = 'DONE'

                # Apply gain
                chunk *= inst.gain_linear * self.master_gain_linear

                # Mono-to-stereo expand
                # v1.2: only duplicate a mono cue to two channels when
                # there are >= 2 output channels. With a 1-channel output
                # both copies wrapped (via the modulo below) back onto
                # channel 0 and summed -> a silent 2x (≈ +6 dB) level
                # bump on mono cues. Now mono-out keeps a single channel.
                if cue.mono_to_stereo and chunk.ndim == 1 and self.output_channels >= 2:
                    chunk = np.stack([chunk, chunk], axis=1)
                elif chunk.ndim == 1:
                    chunk = chunk[:, np.newaxis]

                # Route to output channels with offset
                out_chs = chunk.shape[1]
                for c in range(out_chs):
                    dest = (cue.output_offset + c) % self.output_channels
                    outdata[:chunk_len, dest] += chunk[:, c]

                inst.current_frame += chunk_len
                if inst.state == 'DONE' or inst.current_frame >= total_frames:
                    inst.state = 'DONE'
                    finished.append(inst)

            for inst in finished:
                if inst in self.active_cues:
                    self.active_cues.remove(inst)
                    inst.cue.status = "READY"

    def play_cue(self, cue, vel_scale=1.0):
        if self.stream is None:
            msg = "Audio stream is not open; cue was not fired."
            self.log_event(f"CUE BLOCKED: [{cue.id}] {cue.name} — {msg}")
            return False, msg
        if cue.audio_data is None:
            msg = "Cue audio is not loaded."
            self.log_event(f"CUE BLOCKED: [{cue.id}] {cue.name} — {msg}")
            return False, msg

        cue_channels = 1 if cue.audio_data.ndim == 1 else cue.audio_data.shape[1]
        if cue_channels > self.output_channels:
            msg = (f"Cue needs {cue_channels} output channels, but the stream has "
                   f"{self.output_channels}. Change the output channel count/device.")
            self.log_event(f"CUE BLOCKED: [{cue.id}] {cue.name} — {msg}")
            return False, msg

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

            new_inst = CueInstance(cue, self.sample_rate, vel_scale)
            self.active_cues.append(new_inst)
            cue.status = "PLAYING"
        self.log_event(f"CUE PLAY: [{cue.id}] {cue.name}")
        return True, ''

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


# ── MIDI Input ────────────────────────────────────────────────────────
class MidiInput:
    """Thin wrapper over python-rtmidi. on_message(list[int]) is called on
    rtmidi's own thread: it may touch the (locked) engine, never Tk."""

    def __init__(self, on_message):
        self.available = rtmidi is not None
        self.port_name = ''
        self._in = None
        self._on_message = on_message

    def list_ports(self):
        if not self.available:
            return []
        try:
            probe = rtmidi.MidiIn()
            ports = list(probe.get_ports())
            del probe
            return ports
        except Exception:
            return []

    def find_port(self, wanted, ports=None):
        """Index of `wanted` in ports: exact name first, then OS-number-free."""
        ports = self.list_ports() if ports is None else ports
        if not wanted:
            return -1
        if wanted in ports:
            return ports.index(wanted)
        w = _norm_port_name(wanted)
        for i, p in enumerate(ports):
            if _norm_port_name(p) == w:
                return i
        return -1

    def open(self, wanted):
        """Open a port by name. Returns (ok, message)."""
        self.close()
        if not self.available:
            return False, "python-rtmidi is not installed"
        ports = self.list_ports()
        idx = self.find_port(wanted, ports)
        if idx < 0:
            return False, f"MIDI port not found: {wanted}"
        try:
            mi = rtmidi.MidiIn()
            mi.ignore_types(sysex=True, timing=True, active_sense=True)
            mi.open_port(idx)
            mi.set_callback(self._callback)
            self._in = mi
            self.port_name = ports[idx]
            return True, f"MIDI in: {self.port_name}"
        except Exception as e:
            self._in = None
            # On Windows (WinMM) a MIDI input can be held by only one app.
            return False, (f"Could not open MIDI port {ports[idx]}: {e}  "
                           f"(is it already open in Live/Max/another app?)")

    def _callback(self, event, _data=None):
        try:
            msg, _delta = event
            self._on_message(msg)
        except Exception:
            pass   # never let an exception kill rtmidi's thread

    def close(self):
        if self._in is not None:
            try:
                self._in.cancel_callback()
            except Exception:
                pass
            try:
                self._in.close_port()
            except Exception:
                pass
            self._in = None
        self.port_name = ''


# ── Settings / Config Persistence ─────────────────────────────────────
def load_config(path):
    try:
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except Exception:
        return {}

def save_config(path, data):
    if not path:
        return
    try:
        parent = os.path.dirname(path)
        if parent:
            os.makedirs(parent, exist_ok=True)
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

        self.config_file = manifest.get('config_file', '')

        cfg = load_config(self.config_file)
        self.config = cfg

        # Build cues from manifest clips
        self.cues = []
        clips = manifest.get('clips', [])
        for i, clip in enumerate(clips):
            cue = Cue(clip)
            if not cue.key_assignment and i < len(DEFAULT_KEYS):
                cue.key_assignment = DEFAULT_KEYS[i]
            self.cues.append(cue)

        # Restore saved cue settings. Numeric cue IDs depend on selection
        # order, so prefer an exact ID+name match and otherwise a unique name
        # match. This prevents settings for an old cue 1 being applied to a
        # different sound that happens to become cue 1 on the next run.
        saved_cues = cfg.get('cues', {})
        by_name = {}
        duplicate_names = set()
        for sc in saved_cues.values():
            name = sc.get('name', '')
            if not name:
                continue
            if name in by_name:
                duplicate_names.add(name)
            else:
                by_name[name] = sc
        for name in duplicate_names:
            by_name.pop(name, None)

        for cue in self.cues:
            key = str(cue.id)
            sc = saved_cues.get(key)
            if sc and sc.get('name') and sc.get('name') != cue.name:
                sc = None
            if sc is None:
                sc = by_name.get(cue.name)
            if sc:
                cue.key_assignment = sc.get('key_assignment', cue.key_assignment)
                cue.gain_db        = float(sc.get('gain_db', cue.gain_db))
                cue.output_offset  = int(sc.get('output_offset', cue.output_offset))
                cue.fade_in        = max(0.0, float(sc.get('fade_in', cue.fade_in)))
                cue.fade_out       = max(0.0, float(sc.get('fade_out', cue.fade_out)))
                cue.mode           = sc.get('mode', cue.mode)
                if 'midi_note' in sc:
                    try:
                        n = int(sc['midi_note'])
                        cue.midi_note = n if 0 <= n <= 127 else -1
                    except (TypeError, ValueError):
                        pass

        # Cues without a saved note get the default layout (chromatic or
        # diatonic from C3), skipping any note a restored cue already owns.
        layout = cfg.get('midi_layout', 'Chromatic')
        layout = layout if layout in MIDI_LAYOUTS else 'Chromatic'
        defaults = layout_notes(MIDI_DEFAULT_BASE_NOTE, len(self.cues), layout)
        taken = {c.midi_note for c in self.cues if c.midi_note is not None and c.midi_note >= 0}
        for i, cue in enumerate(self.cues):
            if cue.midi_note is None:
                n = defaults[i]
                cue.midi_note = n if (n >= 0 and n not in taken) else -1
                if cue.midi_note >= 0:
                    taken.add(n)

        # Stop key: saved, else the next layout key after the highest cue.
        try:
            self._stop_note = int(cfg['midi_stop_note'])
        except (KeyError, TypeError, ValueError):
            top = max(taken) if taken else MIDI_DEFAULT_BASE_NOTE - 1
            self._stop_note = next_layout_note(top, layout)
        if not (0 <= self._stop_note <= 127) or self._stop_note in taken:
            self._stop_note = -1

        self.selected_device    = tk.IntVar(value=cfg.get('device_index', -1))
        self.saved_device_name  = cfg.get('device_name', '')
        self.saved_hostapi_name = cfg.get('hostapi_name', '')
        self.output_ch_count    = tk.IntVar(value=cfg.get('output_channels', max(2, manifest.get('project_max_channels', 2))))
        self.master_gain_var    = tk.DoubleVar(value=cfg.get('master_gain_db', 0.0))
        self.exclusive_var      = tk.BooleanVar(value=cfg.get('exclusive_mode', False))

        self.cue_buttons     = {}   # cue.id -> button widget
        self.cue_pbars       = {}   # cue.id -> ttk.Progressbar
        self.cue_time_labels = {}   # cue.id -> time Label
        self.cue_gain_vars   = {}   # keep Tk variables alive + editable
        self.cue_offset_vars = {}
        self.cue_fade_in_vars = {}
        self.cue_fade_out_vars = {}
        self.key_map         = {}   # key char -> cue
        self._status_msg   = tk.StringVar(value="Ready.")
        self._seen_callback_status_count = 0

        # ── MIDI state ──
        # Plain Python attributes mirror the Tk vars so the rtmidi thread
        # never reads Tk objects. note_map is replaced wholesale (atomic).
        self.note_map          = {}     # midi note -> cue
        self.cue_midi_btns     = {}     # cue.id -> note Button
        self._midi_learn       = None   # None | cue | 'BASE'
        self._midi_queue       = queue.Queue()
        self._midi_port_wanted = cfg.get('midi_port', '')
        self.midi_channel_var  = tk.StringVar(value=str(cfg.get('midi_channel', 'Omni')))
        self.midi_gate_var     = tk.BooleanVar(value=cfg.get('midi_note_off_stops', False))
        self.midi_vel_var      = tk.BooleanVar(value=cfg.get('midi_velocity', False))
        self.midi_layout_var   = tk.StringVar(value=layout)
        self.midi_indicator    = tk.StringVar(value="")
        self._midi_channel     = 0      # 0 = omni
        self._midi_gate        = False
        self._midi_velocity    = False
        self.midi = MidiInput(self._on_midi_message)

        # Pre-load audio
        load_errors = []
        for cue in self.cues:
            try:
                data, actual_sr = sf.read(cue.filename, dtype='float32', always_2d=False)
                if int(actual_sr) != self.engine.sample_rate:
                    raise ValueError(
                        f"sample-rate mismatch: file={actual_sr} Hz, project={self.engine.sample_rate} Hz")
                actual_channels = 1 if data.ndim == 1 else int(data.shape[1])
                if actual_channels != cue.channels:
                    self.engine.log_event(
                        f"Cue [{cue.id}] channel metadata corrected: "
                        f"manifest={cue.channels}, file={actual_channels}")
                    cue.channels = actual_channels
                    cue.mono_to_stereo = (actual_channels == 1)
                cue.duration = data.shape[0] / actual_sr
                cue.audio_data = data
            except Exception as e:
                cue.status = "ERROR"
                load_errors.append(f"Cue [{cue.id}] {cue.name}: {e}")
        if load_errors:
            self.engine.log_event("Load errors:\n" + "\n".join(load_errors))

        self._build_ui()
        self._rebuild_key_map()
        self._rebuild_note_map()
        self._refresh_midi_buttons()
        self._apply_master_gain()
        self._apply_exclusive()
        self._apply_midi_options()
        self._try_open_stream()
        self._open_saved_midi_port()

        self.root.bind('<KeyPress>', self._on_keypress)
        self._install_focus_handling()
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

        tk.Label(ctrl, text="Master Gain (dB)  [↑↓ ±1  ←→ ±0.1]:", bg=BG, fg=LABEL_FG,
                 font=("Helvetica", 9)).grid(row=0, column=0, sticky='w', padx=4)
        tk.Scale(ctrl, from_=MASTER_MIN_DB, to=MASTER_MAX_DB, resolution=0.1,
                 orient='horizontal',
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
        self.output_ch_spin = tk.Spinbox(
            dev_frame, from_=1, to=32, width=4,
            textvariable=self.output_ch_count,
            command=self._on_device_changed,
            bg=BUTTON_BG, fg=TEXT_FG, insertbackground=TEXT_FG,
            buttonbackground=BUTTON_BG)
        self.output_ch_spin.pack(side='left')
        self.output_ch_spin.bind('<Return>', self._on_device_changed)
        self.output_ch_spin.bind('<FocusOut>', self._on_device_changed)

        # ── MIDI input ──
        midi_frame = tk.Frame(self.root, bg=BG)
        midi_frame.pack(fill='x', padx=8, pady=(4, 0))

        tk.Label(midi_frame, text="MIDI In:", bg=BG, fg=LABEL_FG,
                 font=("Helvetica", 9)).pack(side='left', padx=4)

        if not self.midi.available:
            tk.Label(midi_frame,
                     text="unavailable — python -m pip install python-rtmidi",
                     bg=BG, fg=STATUS_FG, font=("Helvetica", 9)
                     ).pack(side='left', padx=4)
            self.midi_combo = None
        else:
            self.midi_combo = ttk.Combobox(midi_frame, width=28, state='readonly')
            self.midi_combo.pack(side='left', padx=4)
            self.midi_combo.bind('<<ComboboxSelected>>', self._on_midi_port_changed)
            self._populate_midi_ports()

            tk.Button(midi_frame, text="⟳", bg=BUTTON_BG, fg=TEXT_FG, relief='flat',
                      width=2, command=self._populate_midi_ports
                      ).pack(side='left', padx=(0, 6))

            tk.Label(midi_frame, text="Ch:", bg=BG, fg=LABEL_FG).pack(side='left')
            tk.Spinbox(midi_frame, values=MIDI_CHANNEL_VALUES, width=5,
                       textvariable=self.midi_channel_var, wrap=True,
                       command=self._apply_midi_options,
                       bg=BUTTON_BG, fg=TEXT_FG, insertbackground=TEXT_FG,
                       buttonbackground=BUTTON_BG).pack(side='left', padx=(2, 8))
            # Spinbox(values=…) resets its var to the first value on creation;
            # re-apply the restored channel afterwards.
            self.midi_channel_var.set(self._initial_midi_channel())
            self.midi_channel_var.trace_add('write', lambda *_: self._apply_midi_options())

            for text, var in (("Note-off stops", self.midi_gate_var),
                              ("Velocity", self.midi_vel_var)):
                tk.Checkbutton(midi_frame, text=text, variable=var,
                               bg=BG, fg=LABEL_FG, selectcolor=BUTTON_BG,
                               activebackground=BG,
                               command=self._apply_midi_options).pack(side='left', padx=4)

            self.midi_layout_combo = ttk.Combobox(
                midi_frame, width=9, state='readonly', values=MIDI_LAYOUTS,
                textvariable=self.midi_layout_var)
            self.midi_layout_combo.pack(side='left', padx=(6, 0))
            self.midi_layout_combo.bind('<<ComboboxSelected>>', self._on_layout_changed)

            tk.Button(midi_frame, text="Map from key…", bg=BUTTON_BG, fg=TEXT_FG,
                      relief='flat', padx=6,
                      command=self._start_base_learn).pack(side='left', padx=6)

            # Stop key: click = learn, right-click = clear
            self.stop_midi_btn = tk.Button(
                midi_frame, text="", width=8, bg=ERROR_COLOR, fg=TEXT_FG,
                relief='flat', font=("Courier", 9, "bold"),
                command=self._toggle_stop_learn)
            self.stop_midi_btn.pack(side='left', padx=2)
            self.stop_midi_btn.bind('<Button-3>', lambda _e: self._clear_stop_note())
            self.stop_midi_btn.bind('<Button-2>', lambda _e: self._clear_stop_note())

            tk.Label(midi_frame, textvariable=self.midi_indicator, bg=BG,
                     fg=ARMED_COLOR, font=("Courier", 9), anchor='e'
                     ).pack(side='right', padx=4)

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

        # MIDI note: click = learn, right-click = clear
        if self.midi.available:
            mbtn = tk.Button(row, text=midi_note_name(cue.midi_note), width=4,
                             bg=PANEL_BG, fg=ARMED_COLOR, relief='flat',
                             font=("Courier", 9, "bold"),
                             command=lambda c=cue: self._toggle_cue_learn(c))
            mbtn.pack(side='left', padx=(0, 2), pady=4)
            mbtn.bind('<Button-3>', lambda _e, c=cue: self._clear_cue_note(c))
            mbtn.bind('<Button-2>', lambda _e, c=cue: self._clear_cue_note(c))  # macOS
            self.cue_midi_btns[cue.id] = mbtn

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
        self.cue_gain_vars[cue.id] = gain_var
        gain_var.trace_add('write', lambda *_args, c=cue, v=gain_var: self._set_cue_gain(c, v))
        tk.Label(row, text="dB:", bg=BUTTON_BG, fg=LABEL_FG,
                 font=("Helvetica", 8)).pack(side='left')
        tk.Spinbox(row, from_=-40, to=12, increment=0.5, width=5,
                   textvariable=gain_var, format="%.1f",
                   bg=PANEL_BG, fg=TEXT_FG, insertbackground=TEXT_FG,
                   buttonbackground=BUTTON_BG).pack(side='left', padx=2)

        # Channel offset (cyclic rotation when the cue fits the stream).
        tk.Label(row, text="Ch+:", bg=BUTTON_BG, fg=LABEL_FG,
                 font=("Helvetica", 8)).pack(side='left')
        off_var = tk.IntVar(value=cue.output_offset)
        self.cue_offset_vars[cue.id] = off_var
        off_var.trace_add('write', lambda *_args, c=cue, v=off_var: self._set_cue_offset(c, v))
        tk.Spinbox(row, from_=0, to=31, width=3,
                   textvariable=off_var,
                   bg=PANEL_BG, fg=TEXT_FG, insertbackground=TEXT_FG,
                   buttonbackground=BUTTON_BG).pack(side='left', padx=2)

        # Musically meaningful cue fades. Values are seconds and apply to new
        # triggers; gain edits, unlike fades, are also applied live.
        tk.Label(row, text="In:", bg=BUTTON_BG, fg=LABEL_FG,
                 font=("Helvetica", 8)).pack(side='left', padx=(4, 0))
        fi_var = tk.DoubleVar(value=cue.fade_in)
        self.cue_fade_in_vars[cue.id] = fi_var
        fi_var.trace_add('write', lambda *_args, c=cue, v=fi_var: self._set_cue_fade(c, 'in', v))
        tk.Spinbox(row, from_=0.0, to=60.0, increment=0.05, width=5,
                   textvariable=fi_var, format="%.2f",
                   bg=PANEL_BG, fg=TEXT_FG, insertbackground=TEXT_FG,
                   buttonbackground=BUTTON_BG).pack(side='left', padx=2)

        tk.Label(row, text="Out:", bg=BUTTON_BG, fg=LABEL_FG,
                 font=("Helvetica", 8)).pack(side='left')
        fo_var = tk.DoubleVar(value=cue.fade_out)
        self.cue_fade_out_vars[cue.id] = fo_var
        fo_var.trace_add('write', lambda *_args, c=cue, v=fo_var: self._set_cue_fade(c, 'out', v))
        tk.Spinbox(row, from_=0.0, to=60.0, increment=0.05, width=5,
                   textvariable=fo_var, format="%.2f",
                   bg=PANEL_BG, fg=TEXT_FG, insertbackground=TEXT_FG,
                   buttonbackground=BUTTON_BG).pack(side='left', padx=2)

        # Stop button
        tk.Button(row, text="■", bg=ERROR_COLOR, fg=TEXT_FG, relief='flat',
                  width=2, command=lambda c=cue: self.engine.stop_cue(c)
                  ).pack(side='right', padx=4)

        if cue.status == "ERROR":
            btn.configure(bg=ERROR_COLOR, text=f"✗  {cue.name}  [load error]")

    # ── Device Helpers ────────────────────────────────────────────────
    def _populate_devices(self):
        devs = sd.query_devices()
        apis = sd.query_hostapis()
        entries = []
        idx_map = []
        meta = []
        for i, d in enumerate(devs):
            if d['max_output_channels'] > 0:
                api = apis[d['hostapi']]['name']
                entries.append(f"{i}: {d['name']}  ({d['max_output_channels']}ch) [{api}]")
                idx_map.append(i)
                meta.append({
                    'index': i,
                    'name': d['name'],
                    'hostapi': api,
                    'max_output_channels': int(d['max_output_channels']),
                })
        self._device_indices = idx_map
        self._device_meta = meta
        self.device_combo['values'] = entries

        # Device indices can change after reboot/driver changes. Prefer the
        # persisted hardware identity (name + host API), then index, then default.
        chosen = -1
        if self.saved_device_name and self.saved_hostapi_name:
            for pos, m in enumerate(meta):
                if m['name'] == self.saved_device_name and m['hostapi'] == self.saved_hostapi_name:
                    chosen = pos
                    break
        saved_idx = self.selected_device.get()
        if chosen < 0 and saved_idx >= 0 and saved_idx in idx_map:
            chosen = idx_map.index(saved_idx)
        if chosen < 0 and idx_map:
            default_out = sd.default.device[1] if isinstance(sd.default.device, (list, tuple)) else sd.default.device
            if default_out in idx_map:
                chosen = idx_map.index(default_out)
            else:
                chosen = 0
        if chosen >= 0:
            self.device_combo.current(chosen)
            self.selected_device.set(idx_map[chosen])

    def _on_device_changed(self, *_):
        sel = self.device_combo.current()
        if sel < 0 or sel >= len(self._device_indices):
            return
        idx = self._device_indices[sel]
        self.selected_device.set(idx)
        # Changing stream topology while cues are active can otherwise resume
        # an old multichannel cue into a smaller new stream. Stop immediately.
        self.engine.clear_playback()
        self.engine.close_stream()
        self._try_open_stream()

    def _try_open_stream(self):
        sel = self.device_combo.current()
        if sel < 0 or not hasattr(self, '_device_indices') or sel >= len(self._device_indices):
            self._status_msg.set("No output device selected.")
            return
        dev_idx = self._device_indices[sel]
        try:
            num_chs = max(1, int(self.output_ch_count.get()))
        except (ValueError, tk.TclError):
            self._status_msg.set("Invalid output channel count.")
            return
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
        ok, msg = self.engine.play_cue(cue)
        if ok:
            self._status_msg.set(f"Playing: {cue.name}")
        else:
            self._status_msg.set(f"Cue blocked: {msg}")

    def _set_cue_gain(self, cue, var):
        try:
            cue.gain_db = float(var.get())
            new_linear = 10.0 ** (cue.gain_db / 20.0)
            # Gain edits are musically useful during long cues; update any
            # currently-active instances of this cue as well as future triggers.
            with self.engine.lock:
                for inst in self.engine.active_cues:
                    if inst.cue is cue:
                        inst.gain_linear = new_linear * inst.vel_scale
        except (ValueError, tk.TclError):
            pass

    def _set_cue_offset(self, cue, var):
        try:
            value = int(var.get())
            if value >= 0:
                cue.output_offset = value
        except (ValueError, tk.TclError):
            pass

    def _set_cue_fade(self, cue, which, var):
        try:
            value = max(0.0, float(var.get()))
            if which == 'in':
                cue.fade_in = value
            else:
                cue.fade_out = value
        except (ValueError, tk.TclError):
            pass

    def _apply_master_gain(self):
        db = self.master_gain_var.get()
        self.engine.master_gain_linear = 10.0 ** (db / 20.0)

    def _nudge_master(self, step_db):
        # Ride the master gain from the keyboard. The slider is bound to this
        # same var, so setting it moves the slider on screen; the value is
        # persisted by _save_config exactly like a manual slider move.
        new_db = self.master_gain_var.get() + step_db
        new_db = max(MASTER_MIN_DB, min(MASTER_MAX_DB, new_db))
        new_db = round(new_db, 2)
        self.master_gain_var.set(new_db)
        self._apply_master_gain()
        self._status_msg.set(f"Master gain: {new_db:+.1f} dB")

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
            self._cancel_learn()
            self.engine.stop_all()
            self._reclaim_focus()
            return

        # Do not fire cues or global master shortcuts while the performer is
        # typing/editing a control. Without this guard, typing "1" into a gain
        # Spinbox can also trigger the cue assigned to key 1.
        try:
            widget_class = event.widget.winfo_class()
        except Exception:
            widget_class = ''
        # v1.7.1: only true text-entry widgets block keys. Comboboxes and
        # the slider used to be listed too, and since nothing ever gave focus
        # back, choosing a MIDI port or audio device left every key dead.
        if widget_class in TEXT_ENTRY_CLASSES:
            return

        # Arrow keys ride the master gain: Up/Down coarse (±1 dB),
        # Right/Left fine (±0.1 dB). These keysyms are never cue triggers
        # (DEFAULT_KEYS is digits + letters), so there is no collision.
        if k in ('up', 'down', 'left', 'right'):
            step = {'up':    MASTER_STEP_COARSE_DB,
                    'down': -MASTER_STEP_COARSE_DB,
                    'right': MASTER_STEP_FINE_DB,
                    'left': -MASTER_STEP_FINE_DB}[k]
            self._nudge_master(step)
            return
        if k in self.key_map:
            self._trigger_cue(self.key_map[k])

    # ── Keyboard focus ────────────────────────────────────────────────
    def _reclaim_focus(self, *_):
        try:
            self.root.focus_set()
        except Exception:
            pass

    def _install_focus_handling(self):
        # Launched from Praat, the window often opens behind Praat (Windows
        # especially) and keys keep going to Praat. Raise and grab focus once.
        def _bring_front():
            try:
                self.root.lift()
                self.root.attributes('-topmost', True)
                self.root.after(300, lambda: self.root.attributes('-topmost', False))
                self.root.focus_force()
            except Exception:
                pass
        self.root.after(200, _bring_front)

        # After any pick from a dropdown, hand keys back to the cue triggers.
        self.root.bind_all('<<ComboboxSelected>>',
                           lambda _e: self.root.after_idle(self._reclaim_focus), add='+')

        # Clicking a button, checkbox, slider or empty space returns focus.
        # Text fields keep focus until Return / Esc / clicking elsewhere.
        def _on_release(event):
            try:
                cls = event.widget.winfo_class()
            except Exception:
                return
            if cls not in TEXT_ENTRY_CLASSES and cls != 'TCombobox':
                self.root.after_idle(self._reclaim_focus)
        self.root.bind_all('<ButtonRelease-1>', _on_release, add='+')

        def _on_return(event):
            try:
                if event.widget.winfo_class() in TEXT_ENTRY_CLASSES:
                    self.root.after_idle(self._reclaim_focus)
            except Exception:
                pass
        self.root.bind_all('<Return>', _on_return, add='+')

    # ── MIDI: ports & options (main thread) ───────────────────────────
    def _initial_midi_channel(self):
        v = str(self.config.get('midi_channel', 'Omni'))
        return v if v in MIDI_CHANNEL_VALUES else 'Omni'

    def _populate_midi_ports(self):
        if self.midi_combo is None:
            return
        ports = self.midi.list_ports()
        self._midi_ports = ports
        self.midi_combo['values'] = [MIDI_NONE_LABEL] + ports
        # Keep showing the open port (it may have been renumbered).
        current = self.midi.port_name or ''
        idx = self.midi.find_port(current, ports) if current else -1
        self.midi_combo.current(idx + 1 if idx >= 0 else 0)

    def _open_saved_midi_port(self):
        if not self.midi.available or not self._midi_port_wanted:
            return
        ok, msg = self.midi.open(self._midi_port_wanted)
        self._populate_midi_ports()
        if ok:
            self.engine.log_event(msg)
            self.midi_indicator.set("waiting for notes…")
        else:
            # Keep _midi_port_wanted so the port is reopened next time it
            # is plugged in; do not overwrite the audio status line unless
            # it is merely "Ready".
            self.engine.log_event(msg)
            self.midi_indicator.set("MIDI port missing")

    def _on_midi_port_changed(self, *_):
        sel = self.midi_combo.get()
        if sel == MIDI_NONE_LABEL or not sel:
            self.midi.close()
            self._midi_port_wanted = ''
            self.midi_indicator.set("")
            self._status_msg.set("MIDI input off.")
            return
        ok, msg = self.midi.open(sel)
        self._midi_port_wanted = sel if ok else self._midi_port_wanted
        self.engine.log_event(msg)
        self._status_msg.set(msg)
        self.midi_indicator.set("waiting for notes…" if ok else "MIDI open failed")
        if not ok:
            self._populate_midi_ports()

    def _apply_midi_options(self):
        ch = self.midi_channel_var.get()
        self._midi_channel = int(ch) if ch.isdigit() else 0
        self._midi_gate = bool(self.midi_gate_var.get())
        self._midi_velocity = bool(self.midi_vel_var.get())

    def _rebuild_note_map(self):
        nm = {}
        for cue in self.cues:
            if cue.midi_note is not None and 0 <= cue.midi_note <= 127:
                nm.setdefault(cue.midi_note, cue)
        self.note_map = nm   # atomic swap; read by the MIDI thread

    def _refresh_midi_buttons(self):
        for cue in self.cues:
            b = self.cue_midi_btns.get(cue.id)
            if b is None:
                continue
            if self._midi_learn is cue or self._midi_learn == 'BASE':
                b.configure(text="learn", bg=MIDI_LEARN_COLOR, fg=TEXT_FG)
            else:
                b.configure(text=midi_note_name(cue.midi_note),
                            bg=PANEL_BG, fg=ARMED_COLOR)
        sb = getattr(self, 'stop_midi_btn', None)
        if sb is not None:
            if self._midi_learn == 'STOP':
                sb.configure(text="learn", bg=MIDI_LEARN_COLOR)
            else:
                sb.configure(text=f"■ {midi_note_name(self._stop_note)}", bg=ERROR_COLOR)

    # ── MIDI: learn / clear (main thread) ─────────────────────────────
    def _toggle_cue_learn(self, cue):
        if not self.midi.port_name:
            self._status_msg.set("Select a MIDI input port first.")
            return
        self._midi_learn = None if self._midi_learn is cue else cue
        self._refresh_midi_buttons()
        if self._midi_learn is cue:
            self._status_msg.set(f"Press a key to assign to: {cue.name}  (Esc cancels)")
        else:
            self._status_msg.set("MIDI learn cancelled.")

    def _start_base_learn(self):
        if not self.midi.port_name:
            self._status_msg.set("Select a MIDI input port first.")
            return
        self._midi_learn = None if self._midi_learn == 'BASE' else 'BASE'
        self._refresh_midi_buttons()
        if self._midi_learn == 'BASE':
            self._status_msg.set("Press the key for cue 1 — the rest follow the layout, Stop goes after the last (Esc cancels).")
        else:
            self._status_msg.set("MIDI learn cancelled.")

    def _toggle_stop_learn(self):
        if not self.midi.port_name:
            self._status_msg.set("Select a MIDI input port first.")
            return
        self._midi_learn = None if self._midi_learn == 'STOP' else 'STOP'
        self._refresh_midi_buttons()
        if self._midi_learn == 'STOP':
            self._status_msg.set("Press the key that should stop playback (Esc cancels).")
        else:
            self._status_msg.set("MIDI learn cancelled.")

    def _clear_stop_note(self):
        self._stop_note = -1
        if self._midi_learn == 'STOP':
            self._midi_learn = None
        self._refresh_midi_buttons()
        self._status_msg.set("MIDI stop key cleared.")

    def _cancel_learn(self):
        if self._midi_learn is not None:
            self._midi_learn = None
            self._refresh_midi_buttons()
            self._status_msg.set("MIDI learn cancelled.")

    def _clear_cue_note(self, cue):
        cue.midi_note = -1
        if self._midi_learn is cue:
            self._midi_learn = None
        self._rebuild_note_map()
        self._refresh_midi_buttons()
        self._status_msg.set(f"MIDI note cleared: {cue.name}")

    def _apply_layout(self, base):
        """Re-lay every cue from `base` using the selected layout."""
        layout = self.midi_layout_var.get()
        notes = layout_notes(base, len(self.cues), layout)
        for cue, n in zip(self.cues, notes):
            cue.midi_note = n
        mapped = [n for n in notes if n >= 0]
        skipped = len(notes) - len(mapped)
        # Stop key follows the last cue in the same layout.
        self._stop_note = next_layout_note(mapped[-1], layout) if mapped else -1
        msg = f"{layout}: {len(mapped)} cue(s)"
        if mapped:
            msg += f" {midi_note_name(mapped[0])}–{midi_note_name(mapped[-1])}"
        msg += f", Stop {midi_note_name(self._stop_note)}"
        if skipped:
            msg += f"; {skipped} ran past note 127 and are unmapped"
        return msg

    def _on_layout_changed(self, *_):
        # Keep the current starting key: cue 1's note, else the lowest
        # mapped note, else C3. Diatonic snaps a black-key start up.
        if self.cues and self.cues[0].midi_note is not None and self.cues[0].midi_note >= 0:
            base = self.cues[0].midi_note
        else:
            used = [c.midi_note for c in self.cues if c.midi_note is not None and c.midi_note >= 0]
            base = min(used) if used else MIDI_DEFAULT_BASE_NOTE
        msg = self._apply_layout(base)
        self._rebuild_note_map()
        self._refresh_midi_buttons()
        self._status_msg.set(msg + "  (custom learned notes replaced)")
        self.engine.log_event("MIDI MAP: " + msg)

    def _finish_learn(self, note):
        target = self._midi_learn
        self._midi_learn = None
        if target == 'BASE':
            msg = self._apply_layout(note)
        elif target == 'STOP':
            stolen = [c for c in self.cues if c.midi_note == note]
            for c in stolen:
                c.midi_note = -1
            self._stop_note = note
            msg = f"{midi_note_name(note)} → Stop"
            if stolen:
                msg += f"  (taken from {', '.join(c.name for c in stolen)})"
        elif target is not None:
            stolen = [c for c in self.cues if c is not target and c.midi_note == note]
            for c in stolen:
                c.midi_note = -1
            target.midi_note = note
            msg = f"{midi_note_name(note)} → {target.name}"
            if stolen:
                msg += f"  (taken from {', '.join(c.name for c in stolen)})"
            if note == self._stop_note:
                self._stop_note = -1
                msg += "  (was the Stop key — Stop now unassigned)"
        else:
            return
        self._rebuild_note_map()
        self._refresh_midi_buttons()
        self._status_msg.set(msg)
        self.engine.log_event("MIDI MAP: " + msg)

    # ── MIDI: message handler (rtmidi thread — no Tk calls here) ──────
    def _on_midi_message(self, msg):
        if not msg:
            return
        status = msg[0]
        kind = status & 0xF0
        if kind not in (0x80, 0x90, 0xB0):
            return
        q = self._midi_queue
        ch = (status & 0x0F) + 1
        if self._midi_channel and ch != self._midi_channel:
            # Report it, so a wrong channel setting is visible, not silent.
            if kind == 0x90 and len(msg) >= 3 and msg[2] > 0:
                q.put(('filtered', msg[1], ch))
            return

        if kind == 0x90 and len(msg) >= 3 and msg[2] > 0:
            note, vel = msg[1], msg[2]
            if self._midi_learn is not None:
                q.put(('learn', note))
                return
            if note == self._stop_note:
                self.engine.stop_all()
                q.put(('stopkey', note))
                return
            cue = self.note_map.get(note)
            if cue is None:
                q.put(('unmapped', note, vel))
                return
            if cue.status == "ERROR":
                q.put(('blocked', note, vel, cue, "cue could not be loaded"))
                return
            vs = (vel / 127.0) ** 2 if self._midi_velocity else 1.0
            ok, m = self.engine.play_cue(cue, vs)
            q.put(('fired', note, vel, cue) if ok else ('blocked', note, vel, cue, m))

        elif kind == 0x80 or (kind == 0x90 and len(msg) >= 3 and msg[2] == 0):
            if self._midi_gate and self._midi_learn is None and len(msg) >= 2:
                cue = self.note_map.get(msg[1])
                if cue is not None:
                    self.engine.stop_cue(cue)

        elif kind == 0xB0 and len(msg) >= 3 and msg[1] in (120, 123):
            self.engine.stop_all()
            q.put(('panic',))

    def _drain_midi_queue(self):
        while True:
            try:
                ev = self._midi_queue.get_nowait()
            except queue.Empty:
                break
            kind = ev[0]
            if kind == 'learn':
                self._finish_learn(ev[1])
            elif kind == 'fired':
                _, note, vel, cue = ev
                self.midi_indicator.set(f"{midi_note_name(note)} v{vel} ▸ {cue.name[:24]}")
                self._status_msg.set(f"Playing: {cue.name}")
            elif kind == 'blocked':
                _, note, vel, cue, m = ev
                self.midi_indicator.set(f"{midi_note_name(note)} v{vel} ✗")
                self._status_msg.set(f"Cue blocked: {m}")
            elif kind == 'unmapped':
                _, note, vel = ev
                self.midi_indicator.set(f"{midi_note_name(note)} v{vel} (unmapped)")
            elif kind == 'filtered':
                _, note, ch = ev
                self.midi_indicator.set(f"{midi_note_name(note)} on ch{ch} — ignored (Ch filter)")
            elif kind == 'stopkey':
                self.midi_indicator.set(f"{midi_note_name(ev[1])} ■ stop")
                self._status_msg.set("Stop (MIDI stop key)")
            elif kind == 'panic':
                self.midi_indicator.set("MIDI: all notes off")
                self._status_msg.set("Stop All (MIDI CC 120/123)")

    # ── Status Polling ────────────────────────────────────────────────
    def _poll_status(self):
        self._drain_midi_queue()
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

        if self.engine.callback_status_count != self._seen_callback_status_count:
            self._seen_callback_status_count = self.engine.callback_status_count
            self._status_msg.set(
                f"Audio callback warning: {self.engine.last_callback_status}")

        self.root.after(100, self._poll_status)

    # ── Shutdown ──────────────────────────────────────────────────────
    def _on_close(self):
        self.midi.close()          # stop MIDI triggers before tearing down audio
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
                'name':           cue.name,
                'key_assignment': cue.key_assignment,
                'gain_db':        cue.gain_db,
                'output_offset':  cue.output_offset,
                'fade_in':        cue.fade_in,
                'fade_out':       cue.fade_out,
                'mode':           cue.mode,
                'midi_note':      cue.midi_note if cue.midi_note is not None else -1,
            }
        device_name = ''
        hostapi_name = ''
        sel = self.device_combo.current()
        if hasattr(self, '_device_meta') and 0 <= sel < len(self._device_meta):
            device_name = self._device_meta[sel]['name']
            hostapi_name = self._device_meta[sel]['hostapi']

        cfg = {
            'device_index':    self.selected_device.get(),
            'device_name':     device_name,
            'hostapi_name':    hostapi_name,
            'output_channels': self.output_ch_count.get(),
            'master_gain_db':  self.master_gain_var.get(),
            'exclusive_mode':  self.exclusive_var.get(),
            'midi_port':           self._midi_port_wanted,
            'midi_channel':        self.midi_channel_var.get(),
            'midi_note_off_stops': bool(self.midi_gate_var.get()),
            'midi_velocity':       bool(self.midi_vel_var.get()),
            'midi_layout':         self.midi_layout_var.get(),
            'midi_stop_note':      self._stop_note,
            'cues':            cue_data,
        }
        save_config(self.config_file, cfg)
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
