"""
corpus_map.py — Corpus Map / Interactive Player  v2.4

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University
Version: 2.4 (2026)
License: MIT

Changelog v2.4:
  - Performance recording. A RECORD button captures every trigger
    (click or hover) as a (time, unit, gain) event. STOP & SAVE renders
    those events to a deterministic stereo WAV mixdown -- each cue is
    resampled to 44.1 kHz, placed at its captured timestamp, gain-scaled
    and summed -- saved to <corpus>/_recordings/performance_<stamp>.wav
    (falls back to the temp dir if the corpus folder is read-only). The
    path is also written to <temp_dir>/corpusmap_last_recording.txt so
    the companion ImportPerformance.praat can load the latest take into
    Praat as a Sound object. Paired with CorpusMap.praat v2.4, which now
    passes temp_dir in the launch manifest.

Changelog v2.3.1:
  - Fixed crash on mouse hover/click over the scatter plot. pyqtgraph
    passes the hit points as a numpy array, so `if not points:` /
    `if points:` raised "truth value of an array is ambiguous" (empty
    array when hovering off all points, multi-element when over
    several). Both handlers now test len(points). This fired on every
    mouse move, so the GUI crashed as soon as it was used.

Changelog v2.3:
  - Fixed CFFI crash on playback end: the sounddevice finished_callback
    is a void callback and must return None, but the previous lambda
    returned dict.pop()'s value (the stream object), raising
    "callback with the return type 'void' must return None" whenever a
    sound finished. Replaced with a function that returns None.
  - Much faster analysis:
      * librosa.pyin -> librosa.yin for pitch (deterministic, ~1-2
        orders of magnitude faster; it was the dominant cost). pitch is
        range-filtered and taken as a median.
      * Each file is now decoded ONCE. Previously every file was decoded
        twice -- mono/30s for descriptors and again full/multichannel
        for playback. We decode the full signal once, slice a mono 30s
        analysis window from it, and reuse the full signal for playback.

Changelog v2.2:
  - Fixed playback crash on mono (1-channel) output devices: data is
    downmixed/trimmed to the device channel count before the stream
    opens (stream and callback channel counts now always agree).
  - Removes the launch JSON after reading it (temp-file hygiene).
  - Paired with CorpusMap.praat v2.2 (Windows launch-JSON escaping and
    command-line quoting fixes).
"""

import os
import sys
import json
import glob
import logging
import time
import tempfile

# ── dependency check ──────────────────────────────────────────
# Must run before any other imports so the error message is clean.
def check_dependencies():
    missing = []
    for pkg in ["numpy", "librosa", "sounddevice", "pyqtgraph", "PySide6", "sklearn"]:
        try:
            __import__("sklearn" if pkg == "sklearn" else pkg)
        except ImportError:
            missing.append(pkg)
    if missing:
        print("ERROR: Missing packages: " + ", ".join(missing), file=sys.stderr)
        print("Install:  pip install numpy librosa sounddevice scikit-learn pyqtgraph PySide6",
              file=sys.stderr)
        sys.exit(1)

check_dependencies()

import numpy as np
import librosa
import sounddevice as sd
from sklearn.decomposition import PCA
from sklearn.preprocessing import StandardScaler

import pyqtgraph as pg
from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QPushButton, QLabel, QComboBox, QSlider, QCheckBox, QLineEdit,
)

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

# ── audio file discovery ──────────────────────────────────────
AUDIO_EXTS = ("*.wav", "*.WAV", "*.aif", "*.aiff", "*.AIF", "*.AIFF", "*.flac", "*.mp3", "*.ogg")

def find_audio_files(folder: str) -> list[str]:
    """Recursively find all audio files under folder, matching CorpusMosaic behaviour."""
    files = []
    for ext in AUDIO_EXTS:
        files.extend(glob.glob(os.path.join(folder, "**", ext), recursive=True))
    return sorted(set(files))  # deduplicate in case of case-variant matches on case-insensitive FS

# ── descriptor extraction ─────────────────────────────────────
def extract_descriptors_from_audio(y: np.ndarray, sr: int) -> dict | None:
    """Return a flat dict of acoustic descriptors from a mono signal,
    or None on failure. v2.3: takes pre-decoded audio so the caller can
    decode each file only once (was decoded twice: here and again for
    playback preload)."""
    try:
        if y.size < 512:
            return None

        rms        = float(np.sqrt(np.mean(y ** 2)))
        zcr        = float(np.mean(librosa.feature.zero_crossing_rate(y)))
        centroid   = float(np.mean(librosa.feature.spectral_centroid(y=y, sr=sr)))
        bandwidth  = float(np.mean(librosa.feature.spectral_bandwidth(y=y, sr=sr)))
        flatness   = float(np.mean(librosa.feature.spectral_flatness(y=y)))
        rolloff    = float(np.mean(librosa.feature.spectral_rolloff(y=y, sr=sr)))
        mfccs      = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=13)
        mfcc_means = [float(np.mean(mfccs[i])) for i in range(13)]

        # v2.3: yin (deterministic) instead of pyin (probabilistic, with a
        # Viterbi decode -- ~1-2 orders of magnitude slower and the main
        # bottleneck). pitch_median is one of 20 PCA features, so a robust
        # range-filtered median from yin is more than adequate here.
        try:
            f0  = librosa.yin(y, fmin=60, fmax=800, sr=sr)
            f0v = f0[np.isfinite(f0) & (f0 >= 60) & (f0 <= 800)]
            pitch_median = float(np.median(f0v)) if f0v.size else 0.0
        except Exception:
            pitch_median = 0.0

        duration = float(len(y) / sr)

        desc = {
            "rms": rms, "zcr": zcr, "centroid": centroid,
            "bandwidth": bandwidth, "flatness": flatness,
            "rolloff": rolloff, "pitch_median": pitch_median,
            "duration": duration,
        }
        for i, v in enumerate(mfcc_means):
            desc[f"mfcc_{i}"] = v

        return desc

    except Exception as e:
        logging.warning(f"Descriptor extraction failed: {e}")
        return None


# ── corpus model ──────────────────────────────────────────────
class CorpusModel:
    def __init__(self):
        self.paths: list[str]                    = []
        self.names: list[str]                    = []
        self.descs: list[dict]                   = []
        self.coords: list[tuple]                 = []
        self.audio:  list[np.ndarray | None]     = []
        self.rates:  list[int]                   = []

    def load(self, folder: str):
        files = find_audio_files(folder)
        if not files:
            print(f"ERROR: No audio files found in corpus {folder}", file=sys.stderr)
            sys.exit(1)

        logging.info(f"Found {len(files)} files — extracting descriptors…")
        valid_files = 0
        for path in files:
            # v2.3: decode each file ONCE (was twice -- once mono/30s for
            # analysis, once full/multichannel for playback). We decode the
            # full multichannel signal, derive a mono 30s slice for the
            # descriptors, and keep the full signal for playback.
            try:
                y_full, sr = librosa.load(path, sr=None, mono=False)
            except Exception as e:
                logging.warning(f"Skipping {path}: {e}")
                continue

            # mono analysis signal, first 30 s
            y_mono = y_full.mean(axis=0) if y_full.ndim == 2 else y_full
            y_anal = y_mono[:int(30.0 * sr)]
            desc = extract_descriptors_from_audio(y_anal, sr)
            if desc is None:
                continue

            self.paths.append(path)
            self.names.append(os.path.splitext(os.path.basename(path))[0])
            self.descs.append(desc)

            # playback audio: sounddevice wants (frames,) or (frames, ch)
            audio = y_full.T if y_full.ndim == 2 else y_full
            self.audio.append(audio.astype(np.float32))
            self.rates.append(int(sr))
            valid_files += 1

        if not self.paths:
            print("ERROR: Could not extract features from any corpus files.", file=sys.stderr)
            sys.exit(1)

        logging.info(f"Loaded {valid_files} units — projecting…")
        self._project()

    def _project(self):
        feature_keys = ["rms", "zcr", "centroid", "bandwidth",
                        "flatness", "rolloff", "pitch_median"] + \
                       [f"mfcc_{i}" for i in range(13)]
        X = np.array([[d.get(k, 0.0) for k in feature_keys] for d in self.descs])
        X = StandardScaler().fit_transform(X)
        n = min(2, X.shape[0])
        if n < 2:
            self.coords = [(0.0, 0.0)] * len(self.paths)
            return
        coords = PCA(n_components=2).fit_transform(X)
        self.coords = [(float(c[0]), float(c[1])) for c in coords]


# ── audio engine ──────────────────────────────────────────────
class AudioEngine:
    def __init__(self):
        self.gain        = 0.8
        self.exclusive   = False
        self.device_idx: int | None = None
        self._streams: dict[int, sd.OutputStream] = {}

    def devices(self) -> list[dict]:
        out = []
        for i, d in enumerate(sd.query_devices()):
            if d["max_output_channels"] > 0:
                out.append({"index": i, "name": d["name"],
                            "channels": d["max_output_channels"]})
        return out

    def set_device(self, idx: int):
        self.device_idx = idx

    def play(self, unit_id: int, audio: np.ndarray, sr: int):
        if audio is None or self.device_idx is None:
            return
        if self.exclusive:
            self.panic()

        # v2.2: resolve the device's output capacity first, then make the
        # data's channel count match what we will open the stream with.
        # Previously the stream was opened with out_ch = min(ch, max_out)
        # but the callback still wrote ch-channel data, so a stereo file
        # on a mono device assigned an (N, 2) chunk into an (N, 1) buffer
        # and raised a shape-mismatch error in the callback (no playback).
        try:
            info = sd.query_devices(self.device_idx)
            max_out = int(info["max_output_channels"])
        except Exception as e:
            logging.error(f"Device query error: {e}")
            return
        if max_out < 1:
            logging.error("Selected device has no output channels.")
            return

        data = (audio * self.gain).astype(np.float32)
        src_ch = 1 if data.ndim == 1 else data.shape[1]
        out_ch = min(src_ch, max_out)

        # Downmix (to mono) or trim (to the first out_ch channels) so the
        # data and the stream agree on channel count.
        if data.ndim == 2 and out_ch < src_ch:
            if out_ch == 1:
                data = data.mean(axis=1).astype(np.float32)   # stereo+ -> mono
            else:
                data = data[:, :out_ch].copy()

        ch  = 1 if data.ndim == 1 else data.shape[1]
        ptr = [0]

        def cb(outdata, frames, _t, _st):
            end = ptr[0] + frames
            chunk = data[ptr[0]:end]
            outdata[:len(chunk)] = chunk.reshape(-1, 1) if ch == 1 else chunk
            if len(chunk) < frames:
                outdata[len(chunk):] = 0
                raise sd.CallbackStop
            ptr[0] = end

        try:
            # v2.5: if this unit already has a stream, close it first so we
            # don't leak the portaudio handle (the dict entry would be
            # silently overwritten otherwise, orphaning the old stream).
            existing = self._streams.pop(unit_id, None)
            if existing is not None:
                try: existing.stop(); existing.close()
                except Exception: pass

            # v2.5: hard cap — close the oldest stream when pool is full,
            # preventing portaudio handle exhaustion on sustained hover.
            MAX_STREAMS = 16
            while len(self._streams) >= MAX_STREAMS:
                oldest = next(iter(self._streams))
                s = self._streams.pop(oldest)
                try: s.stop(); s.close()
                except Exception: pass

            # v2.3: finished_callback is a void C callback and MUST return
            # None. The previous lambda returned dict.pop()'s value (the
            # stream object when the key existed), which raised the CFFI
            # "callback with the return type 'void' must return None" error
            # the moment a stream finished. A def returns None implicitly.
            def _on_finished(uid=unit_id):
                self._streams.pop(uid, None)
            stream = sd.OutputStream(device=self.device_idx, samplerate=sr,
                                     channels=ch, callback=cb,
                                     finished_callback=_on_finished)
            stream.start()
            self._streams[unit_id] = stream
        except Exception as e:
            logging.error(f"Playback error: {e}")

    def panic(self):
        for s in list(self._streams.values()):
            try: s.stop(); s.close()
            except Exception: pass
        self._streams.clear()


# ── main window ───────────────────────────────────────────────
PALETTE = [
    (230, 57,  70),  (241, 250, 238), (168, 218, 220),
    (69,  123, 157), (244, 162,  97), (231, 111,  81),
    (42,  157, 143), (255, 209,  26),
]

class CorpusMapWindow(QMainWindow):
    def __init__(self, model: CorpusModel, corpus_dir: str = "", temp_dir: str = ""):
        super().__init__()
        self.model  = model
        self.engine = AudioEngine()
        self.corpus_dir = corpus_dir
        self.temp_dir   = temp_dir or tempfile.gettempdir()
        self.hover_active   = False
        self.last_hover_t   = 0.0
        self.hover_debounce = 0.15   # seconds

        # Performance recording: capture (time, unit, gain) per trigger,
        # then render an offline mixdown when stopped.
        self.recording    = False
        self.record_start = 0.0
        self.record_events: list[tuple] = []

        self._build_ui()
        self._populate_plot()

    # ── UI ────────────────────────────────────────────────────
    def _build_ui(self):
        self.setWindowTitle("Corpus Map — AudioTools")
        self.setMinimumSize(1100, 700)
        self.setStyleSheet("""
            QMainWindow, QWidget { background: #111; }
            QLabel      { color: #ddd; font-family: 'Courier New'; font-size: 11px; }
            QPushButton { background: #1e1e1e; color: #ddd; border: 1px solid #333;
                          padding: 6px; font-weight: bold; }
            QPushButton:hover { background: #2a2a2a; }
            QComboBox   { background: #1e1e1e; color: #ddd; border: 1px solid #333; }
            QLineEdit   { background: #1e1e1e; color: #ddd; border: 1px solid #333; padding: 3px; }
        """)

        root = QWidget(); self.setCentralWidget(root)
        layout = QHBoxLayout(root)

        # ── left sidebar ──────────────────────────────────────
        sidebar = QVBoxLayout()
        sidebar.setContentsMargins(10, 10, 10, 10)

        title = QLabel("■ Corpus Map  v2.4")
        title.setStyleSheet("font-size: 15px; color: #00ff88; font-weight: bold;")
        sidebar.addWidget(title)

        sidebar.addWidget(QLabel(f"\n{len(self.model.paths)} units loaded"))

        sidebar.addWidget(QLabel("\n[Audio output]"))
        self.dev_combo = QComboBox()
        for d in self.engine.devices():
            self.dev_combo.addItem(f"{d['name']}  ({d['channels']} ch)", d["index"])
        self.dev_combo.currentIndexChanged.connect(self._on_device)
        sidebar.addWidget(self.dev_combo)

        sidebar.addWidget(QLabel("\n[Gain]"))
        self.gain_slider = QSlider(Qt.Horizontal)
        self.gain_slider.setRange(0, 100); self.gain_slider.setValue(80)
        self.gain_slider.valueChanged.connect(lambda v: setattr(self.engine, "gain", v / 100))
        sidebar.addWidget(self.gain_slider)

        self.excl_check = QCheckBox("Exclusive (one voice)")
        self.excl_check.setStyleSheet("color: #ddd;")
        self.excl_check.stateChanged.connect(lambda s: setattr(self.engine, "exclusive", bool(s)))
        sidebar.addWidget(self.excl_check)

        self.hover_check = QCheckBox("Trigger on hover")
        self.hover_check.setStyleSheet("color: #ddd;")
        self.hover_check.stateChanged.connect(lambda s: setattr(self, "hover_active", bool(s)))
        sidebar.addWidget(self.hover_check)

        sidebar.addWidget(QLabel("\n[Filter by name]"))
        self.filter_box = QLineEdit()
        self.filter_box.setPlaceholderText("type to filter…")
        self.filter_box.textChanged.connect(self._populate_plot)
        sidebar.addWidget(self.filter_box)

        sidebar.addWidget(QLabel("\n[Last triggered]"))
        self.meta_label = QLabel("—")
        self.meta_label.setWordWrap(True)
        self.meta_label.setStyleSheet(
            "background: #1a1a1a; border: 1px dashed #333; padding: 6px; color: #00ff88;")
        sidebar.addWidget(self.meta_label)

        sidebar.addStretch()

        # ── performance recorder ──────────────────────────────
        sidebar.addWidget(QLabel("\n[Record performance]"))
        self.record_btn = QPushButton("●  RECORD")
        self.record_btn.setStyleSheet(
            "background:#1e1e1e; color:#ff5555; font-size:13px; "
            "min-height:36px; font-weight:bold;")
        self.record_btn.clicked.connect(self._toggle_record)
        sidebar.addWidget(self.record_btn)

        self.record_status = QLabel("idle")
        self.record_status.setWordWrap(True)
        self.record_status.setStyleSheet(
            "background:#1a1a1a; border:1px dashed #333; padding:5px; color:#ff9966;")
        sidebar.addWidget(self.record_status)

        panic = QPushButton("■  PANIC  (Esc)")
        panic.setStyleSheet(
            "background: #880000; color: white; font-size: 13px; min-height: 40px;")
        panic.clicked.connect(self.engine.panic)
        sidebar.addWidget(panic)

        # ── scatter plot ──────────────────────────────────────
        self.plot = pg.PlotWidget()
        self.plot.setBackground("#0a0a0a")
        self.plot.showGrid(x=True, y=True, alpha=0.12)
        self.plot.getViewBox().setMouseMode(pg.ViewBox.PanMode)

        self.scatter = pg.ScatterPlotItem(size=11, pen=pg.mkPen(None), hoverable=True)
        self.scatter.sigClicked.connect(self._on_click)
        self.scatter.sigHovered.connect(self._on_hover)
        self.plot.addItem(self.scatter)

        layout.addLayout(sidebar, stretch=1)
        layout.addWidget(self.plot, stretch=4)

        # pick first device
        if self.dev_combo.count():
            self._on_device(0)

    def _populate_plot(self):
        filt = self.filter_box.text().lower()
        spots = []
        for i, name in enumerate(self.model.names):
            if filt and filt not in name.lower():
                continue
            color = PALETTE[i % len(PALETTE)]
            dur   = self.model.descs[i].get("duration", 0.1)
            spots.append({
                "pos":   self.model.coords[i],
                "size":  max(7, min(22, int(dur * 30))),
                "brush": pg.mkBrush(*color, 210),
                "data":  i,
            })
        self.scatter.setData(spots)

    # ── interactions ──────────────────────────────────────────
    def _on_click(self, _item, points):
        # v2.3.1: pyqtgraph passes `points` as a numpy array of SpotItems.
        # `if points:` raised "truth value of an array is ambiguous" for
        # 0 or >1 hits; len() is unambiguous on arrays and lists alike.
        if len(points) > 0:
            self._trigger(points[0].data())

    def _on_hover(self, _item, points):
        # v2.3.1: was `if not points:` -> ambiguous truth value on the
        # numpy array (empty when hovering off all points, multi-element
        # when over several). This fired on every mouse move and crashed
        # the hover handler. Use len().
        if len(points) == 0:
            return
        idx = points[0].data()
        d   = self.model.descs[idx]
        self.meta_label.setText(
            f"{self.model.names[idx]}\n"
            f"dur: {d.get('duration', 0):.2f}s  "
            f"rms: {d.get('rms', 0):.4f}\n"
            f"centroid: {d.get('centroid', 0):.0f} Hz  "
            f"pitch: {d.get('pitch_median', 0):.0f} Hz"
        )
        if self.hover_active:
            now = time.time()
            if now - self.last_hover_t > self.hover_debounce:
                self._trigger(idx)
                self.last_hover_t = now

    def _trigger(self, idx: int):
        self.engine.play(idx, self.model.audio[idx], self.model.rates[idx])
        # Capture the event for offline performance rendering.
        if self.recording:
            self.record_events.append(
                (time.time() - self.record_start, idx, float(self.engine.gain)))
        self.meta_label.setText(
            f"▶ {self.model.names[idx]}\n"
            f"dur: {self.model.descs[idx].get('duration', 0):.2f}s  "
            f"rms: {self.model.descs[idx].get('rms', 0):.4f}\n"
            f"centroid: {self.model.descs[idx].get('centroid', 0):.0f} Hz  "
            f"pitch: {self.model.descs[idx].get('pitch_median', 0):.0f} Hz"
        )

    def _on_device(self, combo_idx: int):
        dev_idx = self.dev_combo.itemData(combo_idx)
        if dev_idx is not None:
            self.engine.set_device(dev_idx)

    # ── performance recording ─────────────────────────────────
    def _toggle_record(self):
        if not self.recording:
            self.recording    = True
            self.record_start = time.time()
            self.record_events = []
            self.record_btn.setText("■  STOP & SAVE")
            self.record_btn.setStyleSheet(
                "background:#aa0000; color:white; font-size:13px; "
                "min-height:36px; font-weight:bold;")
            self.record_status.setText("● recording…")
            return

        # stop + render
        self.recording = False
        self.record_btn.setText("●  RECORD")
        self.record_btn.setStyleSheet(
            "background:#1e1e1e; color:#ff5555; font-size:13px; "
            "min-height:36px; font-weight:bold;")
        n = len(self.record_events)
        if n == 0:
            self.record_status.setText("nothing recorded")
            return
        self.record_status.setText(f"rendering {n} events…")
        QApplication.processEvents()
        try:
            path = self._render_and_save()
        except Exception as e:
            logging.error(f"Render failed: {e}")
            self.record_status.setText(f"render error:\n{e}")
            return
        if path:
            self.record_status.setText(
                "saved:\n" + os.path.basename(path) +
                "\n\n→ run ImportPerformance.praat\n   in Praat to load it")
        else:
            self.record_status.setText("nothing to render")

    @staticmethod
    def _to_stereo(a: np.ndarray) -> np.ndarray:
        a = np.asarray(a, dtype=np.float32)
        if a.ndim == 1:
            return np.column_stack([a, a])
        if a.shape[1] == 1:
            return np.column_stack([a[:, 0], a[:, 0]])
        return np.ascontiguousarray(a[:, :2])

    def _render_and_save(self):
        """Offline-render the captured trigger events to a stereo WAV.

        Each event places its (resampled, stereo, gain-scaled) cue at its
        captured timestamp in a summed buffer. The result is a clean,
        deterministic mixdown of what was performed."""
        import soundfile as sf
        target_sr = 44100
        events = list(self.record_events)

        # total length = latest (start + cue duration), + 1 s tail
        max_end = 0.0
        for (t, idx, _g) in events:
            a = self.model.audio[idx]
            if a is None:
                continue
            max_end = max(max_end, t + a.shape[0] / self.model.rates[idx])
        if max_end <= 0:
            return None

        total = int(max_end * target_sr) + target_sr
        mix = np.zeros((total, 2), dtype=np.float32)

        for (t, idx, g) in events:
            a = self.model.audio[idx]
            if a is None:
                continue
            sr = self.model.rates[idx]
            if sr != target_sr:
                a = librosa.resample(np.asarray(a, dtype=np.float32),
                                     orig_sr=sr, target_sr=target_sr, axis=0)
            seg = self._to_stereo(a) * float(g)
            start = max(0, int(round(t * target_sr)))
            end = start + seg.shape[0]
            if end > mix.shape[0]:
                seg = seg[:mix.shape[0] - start]
                end = mix.shape[0]
            mix[start:end] += seg

        # prevent clipping; preserve relative level otherwise
        peak = float(np.max(np.abs(mix))) if mix.size else 0.0
        if peak > 1.0:
            mix = (mix / peak) * 0.97

        # trim trailing silence beyond the last non-zero sample (+0.25 s)
        nz = np.where(np.any(np.abs(mix) > 1e-5, axis=1))[0]
        if nz.size:
            last = min(mix.shape[0], int(nz[-1]) + int(0.25 * target_sr))
            mix = mix[:last]

        rec_dir = os.path.join(self.corpus_dir, "_recordings")
        try:
            os.makedirs(rec_dir, exist_ok=True)
        except OSError:
            rec_dir = self.temp_dir   # fallback if corpus dir is read-only

        stamp = time.strftime("%Y%m%d_%H%M%S")
        wav_path = os.path.join(rec_dir, f"performance_{stamp}.wav")
        sf.write(wav_path, mix, target_sr, subtype="PCM_16")

        # pointer file for ImportPerformance.praat (forward slashes, no newline)
        pointer = os.path.join(self.temp_dir, "corpusmap_last_recording.txt")
        try:
            with open(pointer, "w", encoding="utf-8") as f:
                f.write(wav_path.replace("\\", "/"))
        except OSError as e:
            logging.warning(f"Could not write recording pointer: {e}")

        logging.info(f"Performance saved: {wav_path}")
        return wav_path

    def keyPressEvent(self, event):
        if event.key() == Qt.Key_Escape:
            self.engine.panic()
        else:
            super().keyPressEvent(event)

    def closeEvent(self, event):
        self.engine.panic()
        event.accept()


# ── entry point ───────────────────────────────────────────────
if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("ERROR: Usage: python corpus_map.py <launch.json>", file=sys.stderr)
        sys.exit(1)

    launch_path = sys.argv[1]
    with open(launch_path) as f:
        cfg = json.load(f)

    # v2.2: the launch JSON is a one-shot handoff; remove it once read so
    # it does not linger in the temp directory.
    try:
        os.remove(launch_path)
    except OSError:
        pass

    corpus_dir = cfg.get("corpus_dir", "")
    if not corpus_dir or not os.path.isdir(corpus_dir):
        print(f"ERROR: corpus_dir not found: {corpus_dir}", file=sys.stderr)
        sys.exit(1)

    temp_dir = cfg.get("temp_dir", "") or tempfile.gettempdir()

    model = CorpusModel()
    model.load(corpus_dir)

    app = QApplication(sys.argv)
    win = CorpusMapWindow(model, corpus_dir, temp_dir)
    win.show()
    print("[Py] Success. GUI launched.")
    sys.exit(app.exec())
