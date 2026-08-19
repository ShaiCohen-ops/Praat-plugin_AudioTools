"""
spectral_eraser.py  –  Interactive spectral eraser with tkinter GUI
(v2.1 — multichannel-safe, level-preserving, QC-aware)

Part of Praat AudioTools plugin
Version: 2.2 (2026)
Author: Shai Cohen, Department of Music, Bar-Ilan University

Draws a spectrogram from a WAV file. The user can paint over
time-frequency regions to silence them, or type text to erase
words directly out of the audio spectrum.
Uses numpy STFT/iSTFT and optional PIL for text-stencil mapping.
The edit mask is learned from one representative source channel and applied
identically to every input channel, preserving multichannel structure.
"""

import sys
import os
import math

# ────────────────────────────────────────────────────────────────
# Dependency check
# ────────────────────────────────────────────────────────────────

def check_dependencies():
    missing = []
    try:
        import numpy          # noqa: F401
    except ImportError:
        missing.append("numpy")
    try:
        import soundfile      # noqa: F401
    except ImportError:
        missing.append("soundfile")
        
    if missing:
        print("ERROR: Missing packages: " + ", ".join(missing),
              file=sys.stderr)
        print("Install with:  pip install " + " ".join(missing),
              file=sys.stderr)
        sys.exit(1)


# ────────────────────────────────────────────────────────────────
# STFT / iSTFT  (pure numpy, Hann window, COLA hop = win/4)
# ────────────────────────────────────────────────────────────────

def hann_window(n):
    import numpy as np
    return (0.5 - 0.5 * np.cos(
        2.0 * np.pi * np.arange(n, dtype=np.float64) / n
    )).astype(np.float64)


def stft(x, win_size, hop):
    """Forward STFT.  Returns complex matrix (n_freq, n_frames).
    Pads both sides with win_size zeros for boundary COLA."""
    import numpy as np
    win = hann_window(win_size)
    pad = win_size
    xp = np.concatenate([np.zeros(pad, dtype=x.dtype), x,
                         np.zeros(pad, dtype=x.dtype)])
    n_frames = max(1, (len(xp) - win_size) // hop + 1)
    n_freq = win_size // 2 + 1
    S = np.zeros((n_freq, n_frames), dtype=np.complex128)
    for i in range(n_frames):
        s = i * hop
        S[:, i] = np.fft.rfft(xp[s:s + win_size] * win)
    return S


def istft(S, win_size, hop, target_len):
    """Inverse STFT with overlap-add + COLA normalisation.
    Strips the win_size padding added by stft()."""
    import numpy as np
    win = hann_window(win_size)
    n_frames = S.shape[1]
    out_len = (n_frames - 1) * hop + win_size
    y = np.zeros(out_len, dtype=np.float64)
    w2 = np.zeros(out_len, dtype=np.float64)
    for i in range(n_frames):
        frame = np.fft.irfft(S[:, i], n=win_size)
        s = i * hop
        y[s:s + win_size] += frame * win
        w2[s:s + win_size] += win ** 2
    nz = w2 > 1e-8
    y[nz] /= w2[nz]
    pad = win_size
    return y[pad:pad + target_len].astype(np.float32)


def apply_mask_multichannel(audio, win_size, hop, mask, analysis_channel=0, analysis_stft=None):
    """Apply one STFT mask identically to every source channel.

    Returns (out_2d, metrics).  No level increase is performed; a safety gain
    is applied only if reconstruction exceeds 0.99 peak.
    """
    import numpy as np
    a = np.asarray(audio, dtype=np.float32)
    if a.ndim == 1:
        a = a[:, np.newaxis]
    if a.ndim != 2 or a.shape[0] < 1 or a.shape[1] < 1:
        raise ValueError("audio must contain at least one sample and one channel")
    n_samples, n_channels = a.shape
    analysis_channel = int(max(0, min(analysis_channel, n_channels - 1)))
    mask = np.asarray(mask, dtype=np.float32)

    out = np.empty_like(a, dtype=np.float32)
    S_ref = analysis_stft
    if S_ref is None:
        S_ref = stft(a[:, analysis_channel], win_size, hop)
    if S_ref.shape != mask.shape:
        raise ValueError(f"mask shape {mask.shape} does not match STFT {S_ref.shape}")

    for ch in range(n_channels):
        S_ch = S_ref if ch == analysis_channel else stft(a[:, ch], win_size, hop)
        if S_ch.shape != mask.shape:
            raise ValueError("channel STFT shapes are inconsistent")
        out[:, ch] = istft(S_ch * mask, win_size, hop, n_samples)

    source_peak = float(np.max(np.abs(a)))
    raw_peak = float(np.max(np.abs(out)))
    safety_gain = 1.0
    if raw_peak > 0.99:
        safety_gain = 0.99 / raw_peak
        out *= safety_gain
    output_peak = float(np.max(np.abs(out)))

    coverage_pct = float((1.0 - mask.mean()) * 100.0)
    e0 = float(np.sum(np.abs(S_ref) ** 2))
    e1 = float(np.sum(np.abs(S_ref * mask) ** 2))
    energy_removed_pct = 0.0 if e0 <= 1e-30 else max(
        0.0, min(100.0, (1.0 - e1 / e0) * 100.0))
    metrics = {
        "analysis_channel": analysis_channel + 1,
        "input_channels": n_channels,
        "mask_coverage_pct": coverage_pct,
        "spectral_energy_removed_pct": energy_removed_pct,
        "source_peak": source_peak,
        "raw_output_peak": raw_peak,
        "safety_gain": safety_gain,
        "output_peak": output_peak,
    }
    return out, metrics


# ────────────────────────────────────────────────────────────────
# Warm colormap  (256-entry LUT: black → purple → red → yellow)
# ────────────────────────────────────────────────────────────────

def build_colormap():
    import numpy as np
    cmap = np.zeros((256, 3), dtype=np.uint8)
    pts = [(0, 0, 0, 4),
           (51, 32, 0, 82),
           (102, 165, 20, 20),
           (178, 232, 145, 8),
           (255, 255, 255, 225)]
    for k in range(len(pts) - 1):
        i0, r0, g0, b0 = pts[k]
        i1, r1, g1, b1 = pts[k + 1]
        span = max(1, i1 - i0)
        for j in range(i0, i1 + 1):
            t = (j - i0) / span
            cmap[j] = (int(r0 + t * (r1 - r0)),
                       int(g0 + t * (g1 - g0)),
                       int(b0 + t * (b1 - b0)))
    return cmap


# ────────────────────────────────────────────────────────────────
# GUI
# ────────────────────────────────────────────────────────────────

class SpectralEraserGUI:
    """tkinter GUI: spectrogram canvas with draw-to-erase and text filter."""

    CANVAS_H = 400          # pixels (frequency axis)
    MAX_CANVAS_W = 2000     # cap width for very long sounds

    def __init__(self, audio, sr, win_size, out_wav, done_file, analysis_channel=0, stats_file=""):
        import numpy as np
        import tkinter as tk

        self.np = np
        self.tk = tk
        self.sr = sr
        self.win_size = win_size
        self.hop = win_size // 4
        self.out_wav = out_wav
        self.done_file = done_file
        self.stats_file = stats_file
        # Internal audio is always (samples, channels).
        if audio.ndim == 1:
            audio = audio[:, np.newaxis]
        self.audio = np.asarray(audio, dtype=np.float32)
        self.n_channels = self.audio.shape[1]
        self.analysis_channel = int(max(0, min(analysis_channel, self.n_channels - 1)))
        self.analysis_audio = self.audio[:, self.analysis_channel]
        self.cancelled = True     # default until Apply
        self.preview_stream = None
        self.preview_audio = None
        self.preview_pos = 0

        # ── STFT of the representative channel used for display/mask design ──
        self.S = stft(self.analysis_audio, win_size, self.hop)
        self.n_freq, self.n_frames = self.S.shape

        # ── Erasure mask  (1 = keep, 0 = erase) ──
        self.mask = np.ones((self.n_freq, self.n_frames), dtype=np.float32)

        # ── Magnitude spectrogram for display ──
        mag = np.abs(self.S)
        self.mag_db = 20.0 * np.log10(mag + 1e-10)

        # ── Display-frame mapping ──
        # STFT includes padded boundary frames for transparent OLA.  Do not map
        # those negative/post-roll frames onto the audible 0..duration axis.
        centres = np.arange(self.n_frames, dtype=np.float64) * self.hop \
            - self.win_size / 2.0
        valid = np.flatnonzero((centres >= 0.0) &
                               (centres <= max(0, len(self.analysis_audio) - 1)))
        if valid.size:
            self.frame_first = int(valid[0])
            self.frame_last = int(valid[-1])
        else:
            self.frame_first = 0
            self.frame_last = self.n_frames - 1
        self.display_n_frames = self.frame_last - self.frame_first + 1

        # Display contrast is estimated only from audible frames. Padding is
        # intentionally silent and would otherwise crush the percentile range.
        display_db = self.mag_db[:, self.frame_first:self.frame_last + 1]
        self.db_floor = float(np.percentile(display_db, 5))
        self.db_ceil = float(np.percentile(display_db, 99))

        # ── Canvas dimensions ──
        self.cw = min(self.display_n_frames, self.MAX_CANVAS_W)
        self.ch = self.CANVAS_H
        self.sx = self.cw / max(1, self.display_n_frames)
        self.sy = self.ch / self.n_freq     # pixels per freq bin

        # ── Colormap ──
        self.cmap = build_colormap()

        # ── Build window ──
        self.root = tk.Tk()
        self.root.title("Spectral Eraser — AudioTools")
        self.root.protocol("WM_DELETE_WINDOW", self._on_cancel)
        self.brush = 8
        self.rect_ids = []
        self._last_draw_xy = None
        self._build_gui()
        self._render_spectrogram()
        self._add_freq_labels()

    # ────────────────── GUI layout ──────────────────

    def _build_gui(self):
        tk = self.tk

        # ── Top controls ──
        top = tk.Frame(self.root)
        top.pack(fill="x", padx=6, pady=4)

        tk.Label(top, text="Brush:").pack(side="left")
        self.brush_sl = tk.Scale(top, from_=2, to=60, orient="horizontal",
                                 length=140, command=self._brush_cb)
        self.brush_sl.set(self.brush)
        self.brush_sl.pack(side="left", padx=4)

        # TEXT FILTER ADDITION
        tk.Label(top, text="Text Stencil:").pack(side="left", padx=(15, 2))
        self.text_entry = tk.Entry(top, width=12)
        self.text_entry.pack(side="left")
        self.text_entry.bind('<Return>', lambda e: self._erase_text())
        tk.Button(top, text="Erase Text Shape", command=self._erase_text).pack(side="left", padx=(4, 0))

        tk.Button(top, text="Clear All", command=self._clear_all
                  ).pack(side="left", padx=15)

        dur = len(self.audio) / self.sr
        tk.Label(top, text=(f"SR {self.sr} Hz  |  {dur:.2f} s  |  "
                           f"{self.n_channels} ch  |  analysis ch {self.analysis_channel + 1}"),
                 fg="#555").pack(side="right", padx=12)

        # ── Scrollable canvas ──
        cf = tk.Frame(self.root)
        cf.pack(fill="both", expand=True, padx=6)

        hscroll = tk.Scrollbar(cf, orient="horizontal")
        hscroll.pack(side="bottom", fill="x")

        self.canvas = tk.Canvas(
            cf, height=self.ch,
            scrollregion=(0, 0, self.cw, self.ch),
            xscrollcommand=hscroll.set, bg="black")
        self.canvas.pack(fill="both", expand=True)
        hscroll.config(command=self.canvas.xview)

        self.canvas.bind("<Button-1>", self._on_press)
        self.canvas.bind("<B1-Motion>", self._on_drag)
        self.canvas.bind("<ButtonRelease-1>", self._on_release)
        self.canvas.bind("<Motion>", self._on_motion)

        # ── Bottom buttons ──
        bot = tk.Frame(self.root)
        bot.pack(fill="x", padx=6, pady=5)

        tk.Button(bot, text="Apply", command=self._on_apply,
                  bg="#4CAF50", fg="white", width=12,
                  font=("Helvetica", 10, "bold")).pack(side="right", padx=5)
        tk.Button(bot, text="Cancel", command=self._on_cancel,
                  width=12).pack(side="right", padx=5)
        self.preview_btn = tk.Button(bot, text="Preview", command=self._toggle_preview,
                                     bg="#3a4f7a", fg="white", width=12)
        self.preview_btn.pack(side="right", padx=5)

        self.status = tk.StringVar(
            value="Draw on the spectrogram to erase frequency-time regions")
        tk.Label(self.root, textvariable=self.status, anchor="w",
                 fg="#666").pack(fill="x", padx=6, pady=(0, 4))

    # ────────────────── Spectrogram image ──────────────────

    def _render_spectrogram(self):
        """Render STFT magnitudes to a PPM file → PhotoImage."""
        np = self.np
        h, w = self.ch, self.cw

        # Map canvas pixels → STFT indices (vectorised)
        freq_idx = np.clip(
            ((h - 1 - np.arange(h)) * self.n_freq / h).astype(int),
            0, self.n_freq - 1)
        if w <= 1 or self.display_n_frames <= 1:
            frame_idx = np.full(w, self.frame_first, dtype=int)
        else:
            frame_idx = self.frame_first + np.rint(
                np.linspace(0, self.display_n_frames - 1, w)).astype(int)

        disp = self.mag_db[np.ix_(freq_idx, frame_idx)]

        # Normalise to 0-255
        rng = max(1e-6, self.db_ceil - self.db_floor)
        idx = np.clip(((disp - self.db_floor) / rng * 255).astype(int),
                       0, 255)

        # Apply colormap  → (h, w, 3)
        img = self.cmap[idx]

        # Write PPM (binary P6)
        ppm_path = self.out_wav + ".display.ppm"
        with open(ppm_path, "wb") as f:
            f.write(f"P6\n{w} {h}\n255\n".encode("ascii"))
            f.write(img.astype(np.uint8).tobytes())

        self.spec_img = self.tk.PhotoImage(file=ppm_path)
        self.canvas.create_image(0, 0, anchor="nw",
                                 image=self.spec_img, tags="bg")

        try:
            os.remove(ppm_path)
        except OSError:
            pass

    def _add_freq_labels(self):
        """Draw frequency reference labels on the left edge."""
        nyq = self.sr / 2
        for f_hz in [100, 250, 500, 1000, 2000, 4000, 8000, 16000]:
            if f_hz >= nyq:
                break
            py = self.ch - int(f_hz / nyq * self.ch)
            if 10 < py < self.ch - 10:
                self.canvas.create_text(
                    3, py, anchor="w", fill="#aaaaaa",
                    font=("Helvetica", 7),
                    text=f"{f_hz}" if f_hz < 1000
                         else f"{f_hz // 1000}k",
                    tags="label")

    # ────────────────── Drawing / erasing ──────────────────

    def _brush_cb(self, val):
        self.brush = int(val)

    def _canvas_xy(self, event):
        """Convert widget event coords to canvas (scroll-aware) coords."""
        return (self.canvas.canvasx(event.x),
                self.canvas.canvasy(event.y))

    def _erase_at(self, cx, cy):
        """Erase a brush-sized rectangle centred at canvas (cx, cy)."""
        self._stop_preview()
        np = self.np
        half = self.brush // 2

        # Canvas rectangle
        x1 = max(0, cx - half)
        y1 = max(0, cy - half)
        x2 = min(self.cw, cx + half)
        y2 = min(self.ch, cy + half)

        rid = self.canvas.create_rectangle(
            x1, y1, x2, y2,
            fill="#cc2222", outline="", stipple="gray50", tags="erased")
        self.rect_ids.append(rid)

        # Map to STFT bins and zero the mask
        f_lo = int((self.ch - y2) / self.ch * self.n_freq)
        f_hi = int((self.ch - y1) / self.ch * self.n_freq)
        if self.cw <= 1 or self.display_n_frames <= 1:
            t_lo = t_hi = self.frame_first
        else:
            frame_scale = (self.display_n_frames - 1) / (self.cw - 1)
            t_lo = self.frame_first + int(round(x1 * frame_scale))
            t_hi = self.frame_first + int(round(x2 * frame_scale))

        f_lo = max(0, min(f_lo, self.n_freq - 1))
        f_hi = max(0, min(f_hi, self.n_freq - 1))
        t_lo = max(0, min(t_lo, self.n_frames - 1))
        t_hi = max(0, min(t_hi, self.n_frames - 1))

        self.mask[f_lo:f_hi + 1, t_lo:t_hi + 1] = 0

    def _erase_text(self):
        """Render typed text as a spectral erasure mask across the visible area."""
        self._stop_preview()
        text = self.text_entry.get().strip()
        if not text:
            return

        try:
            from PIL import Image, ImageDraw, ImageFont
        except ImportError:
            self.status.set("Text filter requires: pip install pillow")
            return

        import numpy as np

        # 1. Current visible canvas region
        x_view = self.canvas.xview()
        vis_x0 = int(x_view[0] * self.cw)
        vis_x1 = int(x_view[1] * self.cw)
        vis_w = max(50, vis_x1 - vis_x0)

        # 2. Find a TrueType font, fall back to default
        font = None
        target_h = int(self.ch * 0.35)
        for font_name in ["arial.ttf", "Arial.ttf", "DejaVuSans.ttf",
                          "LiberationSans-Regular.ttf",
                          "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
                          "/System/Library/Fonts/Helvetica.ttc"]:
            try:
                font = ImageFont.truetype(font_name, target_h)
                break
            except (IOError, OSError):
                continue

        if font is None:
            # Scale up the default bitmap font via a large temp image
            font = ImageFont.load_default()

        # 3. Measure text, render at native size
        temp_img = Image.new('L', (1, 1), 0)
        temp_draw = ImageDraw.Draw(temp_img)
        bbox = temp_draw.textbbox((0, 0), text, font=font)
        tw = bbox[2] - bbox[0]
        th = bbox[3] - bbox[1]
        if tw < 1 or th < 1:
            return

        # Render text
        text_img = Image.new('L', (tw + 4, th + 4), 0)
        draw = ImageDraw.Draw(text_img)
        draw.text((-bbox[0] + 2, -bbox[1] + 2), text, fill=255, font=font)

        # 4. Scale to fill 80% of visible width, 35% of canvas height
        target_w = int(vis_w * 0.8)
        target_h_final = int(self.ch * 0.35)
        scale = min(target_w / float(tw + 4), target_h_final / float(th + 4))
        new_w = max(1, int((tw + 4) * scale))
        new_h = max(1, int((th + 4) * scale))

        scaled_text = text_img.resize((new_w, new_h), Image.LANCZOS)

        # 5. Place in full-canvas mask at bottom of visible area (low frequencies)
        mask_img = Image.new('L', (self.cw, self.ch), 0)
        offset_x = vis_x0 + (vis_w - new_w) // 2
        offset_y = self.ch - new_h - 5
        mask_img.paste(scaled_text, (offset_x, offset_y))

        # 6. Map to the audible STFT-frame span only.  Boundary-padding
        # frames are reconstruction support and must not steal time from the text.
        stft_mask = mask_img.resize((self.display_n_frames, self.n_freq),
                                    Image.NEAREST)
        stft_arr = np.array(stft_mask)

        # Canvas Y=0 = top = high freq; STFT index 0 = DC = low freq → flip
        stft_arr = stft_arr[::-1, :]

        # Apply: erase where text pixels are bright
        audible_mask = self.mask[:, self.frame_first:self.frame_last + 1]
        audible_mask[stft_arr > 64] = 0

        # 7. Visual feedback — red rectangle + text overlay on canvas
        rid = self.canvas.create_rectangle(
            offset_x, offset_y, offset_x + new_w, offset_y + new_h,
            fill="white", outline="", stipple="gray50", tags="erased")
        self.rect_ids.append(rid)

        # Overlay text label
        center_x = offset_x + new_w // 2
        center_y = offset_y + new_h // 2
        disp_font_size = max(10, int(new_h * 0.6))
        rid2 = self.canvas.create_text(
            center_x, center_y,
            text=text, font=("Helvetica", disp_font_size, "bold"),
            fill="#ff6666", tags="erased")
        self.rect_ids.append(rid2)

        erased_pct = float((1.0 - self.mask.mean()) * 100)
        self.status.set(f"Erased text '{text}'  |  Total erased: {erased_pct:.1f}%")

    def _on_press(self, event):
        cx, cy = self._canvas_xy(event)
        self._last_draw_xy = (cx, cy)
        self._erase_at(cx, cy)

    def _on_drag(self, event):
        cx, cy = self._canvas_xy(event)
        if self._last_draw_xy is None:
            self._last_draw_xy = (cx, cy)
            self._erase_at(cx, cy)
            return
        x0, y0 = self._last_draw_xy
        dist = math.hypot(cx - x0, cy - y0)
        # Interpolate mouse events so a fast stroke cannot leave holes.
        step = max(1.0, self.brush * 0.35)
        n_steps = max(1, int(math.ceil(dist / step)))
        for k in range(1, n_steps + 1):
            a = k / n_steps
            self._erase_at(x0 + a * (cx - x0), y0 + a * (cy - y0))
        self._last_draw_xy = (cx, cy)

    def _on_release(self, event=None):
        self._last_draw_xy = None

    def _on_motion(self, event):
        """Update status bar with frequency / time under cursor."""
        cx, cy = self._canvas_xy(event)
        nyq = self.sr / 2
        freq = (self.ch - cy) / self.ch * nyq
        time = cx / self.cw * len(self.analysis_audio) / self.sr
        erased = int((1.0 - self.mask.mean()) * 100)
        self.status.set(
            f"Time: {time:.3f} s  |  Freq: {freq:.0f} Hz  |  "
            f"Erased: {erased}%")

    def _clear_all(self):
        """Reset mask and remove overlay rectangles/text."""
        self._stop_preview()
        self.mask[:] = 1
        for rid in self.rect_ids:
            self.canvas.delete(rid)
        self.rect_ids.clear()
        self.status.set("Cleared — draw again to erase")

    # ────────────────── Preview / audition ──────────────────

    def _preview_finished(self):
        stream = self.preview_stream
        self.preview_stream = None
        self.preview_audio = None
        self.preview_pos = 0
        if stream is not None:
            try:
                stream.close()
            except Exception:
                pass
        try:
            self.preview_btn.configure(text="Preview")
        except Exception:
            pass

    def _stop_preview(self):
        """Stop an active audition without changing the mask."""
        stream = self.preview_stream
        self.preview_stream = None
        self.preview_audio = None
        self.preview_pos = 0
        if stream is not None:
            try:
                stream.abort()
            except Exception:
                try:
                    stream.stop()
                except Exception:
                    pass
            try:
                stream.close()
            except Exception:
                pass
        if hasattr(self, "preview_btn"):
            try:
                self.preview_btn.configure(text="Preview")
            except Exception:
                pass

    def _preview_time_range(self, max_seconds=12.0):
        """Return the currently visible time range, capped for responsive audition."""
        duration = len(self.analysis_audio) / float(self.sr)
        try:
            x0, x1 = self.canvas.xview()
        except Exception:
            x0, x1 = 0.0, 1.0
        t0 = max(0.0, min(duration, float(x0) * duration))
        t1 = max(t0, min(duration, float(x1) * duration))
        if t1 - t0 < 0.05:
            t0, t1 = 0.0, min(duration, max_seconds)
        if t1 - t0 > max_seconds:
            mid = 0.5 * (t0 + t1)
            t0 = max(0.0, mid - max_seconds / 2.0)
            t1 = min(duration, t0 + max_seconds)
            t0 = max(0.0, t1 - max_seconds)
        return t0, t1

    def _route_preview_for_device(self, audio, sd):
        """Prefer native channel count; otherwise preserve real source channels."""
        if audio.ndim == 1:
            audio = audio[:, self.np.newaxis]
        n_ch = audio.shape[1]

        # Exact multichannel/mono/stereo audition when the default device accepts it.
        try:
            sd.check_output_settings(channels=n_ch, samplerate=self.sr,
                                     dtype="float32")
            return audio.astype(self.np.float32, copy=False), f"{n_ch}-channel"
        except Exception:
            pass

        # Stereo fallback: choose the two strongest REAL source channels rather
        # than folding them together, avoiding phase cancellation.
        if n_ch >= 2:
            rms = self.np.sqrt(self.np.mean(audio.astype(self.np.float64) ** 2,
                                           axis=0) + 1e-30)
            idx = self.np.argsort(rms)[-2:]
            idx = self.np.sort(idx)
            stereo = audio[:, idx].astype(self.np.float32, copy=False)
            try:
                sd.check_output_settings(channels=2, samplerate=self.sr,
                                         dtype="float32")
                return stereo, f"stereo monitor (source ch {idx[0]+1}+{idx[1]+1})"
            except Exception:
                pass

        # Last-resort mono uses the strongest real source channel.
        rms = self.np.sqrt(self.np.mean(audio.astype(self.np.float64) ** 2,
                                       axis=0) + 1e-30)
        best = int(self.np.argmax(rms))
        mono = audio[:, best:best + 1].astype(self.np.float32, copy=False)
        sd.check_output_settings(channels=1, samplerate=self.sr, dtype="float32")
        return mono, f"mono monitor (source ch {best+1})"

    def _toggle_preview(self):
        if self.preview_stream is not None:
            self._stop_preview()
            self.status.set("Preview stopped.")
            return

        try:
            import sounddevice as sd
        except ImportError:
            self.status.set("Preview requires optional package: pip install sounddevice")
            return

        self.status.set("Rendering current mask for preview...")
        self.root.update()
        try:
            out, _ = apply_mask_multichannel(
                self.audio, self.win_size, self.hop, self.mask,
                analysis_channel=self.analysis_channel,
                analysis_stft=self.S)
            t0, t1 = self._preview_time_range(max_seconds=12.0)
            i0 = max(0, int(round(t0 * self.sr)))
            i1 = min(len(out), max(i0 + 1, int(round(t1 * self.sr))))
            clip = out[i0:i1]
            play, route = self._route_preview_for_device(clip, sd)

            self.preview_audio = self.np.ascontiguousarray(play, dtype=self.np.float32)
            self.preview_pos = 0

            def callback(outdata, frames, time_info, status):
                start = self.preview_pos
                stop = min(start + frames, len(self.preview_audio))
                n = max(0, stop - start)
                outdata.fill(0)
                if n:
                    outdata[:n, :] = self.preview_audio[start:stop, :]
                    self.preview_pos = stop
                if stop >= len(self.preview_audio):
                    raise sd.CallbackStop()

            def finished():
                try:
                    self.root.after(0, self._preview_finished)
                except Exception:
                    pass

            self.preview_stream = sd.OutputStream(
                samplerate=self.sr,
                channels=self.preview_audio.shape[1],
                dtype="float32",
                callback=callback,
                finished_callback=finished,
                blocksize=0,
            )
            self.preview_stream.start()
            self.preview_btn.configure(text="Stop")
            self.status.set(
                f"Preview {t0:.2f}-{t1:.2f} s | {route} | current mask")
        except Exception as exc:
            self._stop_preview()
            self.status.set(f"Preview unavailable: {exc}")

    # ────────────────── Apply / Cancel ──────────────────

    def _on_apply(self):
        """Apply one shared spectral mask to every source channel."""
        self._stop_preview()
        import soundfile as sf

        self.status.set("Applying spectral mask and reconstructing...")
        self.root.update()

        out, metrics = apply_mask_multichannel(
            self.audio, self.win_size, self.hop, self.mask,
            analysis_channel=self.analysis_channel,
            analysis_stft=self.S)
        source_peak = metrics["source_peak"]
        raw_peak = metrics["raw_output_peak"]
        safety_gain = metrics["safety_gain"]
        output_peak = metrics["output_peak"]
        coverage_pct = metrics["mask_coverage_pct"]
        energy_removed_pct = metrics["spectral_energy_removed_pct"]

        to_write = out[:, 0] if self.n_channels == 1 else out
        sf.write(self.out_wav, to_write, self.sr, subtype="FLOAT")

        if self.stats_file:
            with open(self.stats_file, "w", encoding="utf-8") as f:
                f.write(f"analysis_channel={self.analysis_channel + 1}\n")
                f.write(f"input_channels={self.n_channels}\n")
                f.write(f"mask_coverage_pct={coverage_pct:.6f}\n")
                f.write(f"spectral_energy_removed_pct={energy_removed_pct:.6f}\n")
                f.write(f"source_peak={source_peak:.9f}\n")
                f.write(f"raw_output_peak={raw_peak:.9f}\n")
                f.write(f"safety_gain={safety_gain:.9f}\n")
                f.write(f"output_peak={output_peak:.9f}\n")

        with open(self.done_file, "w", encoding="utf-8") as f:
            f.write("OK")

        print(f"OK: wrote {self.out_wav}  "
              f"({coverage_pct:.1f}% bins masked; "
              f"{energy_removed_pct:.1f}% analysis-channel spectral energy removed; "
              f"{self.n_channels} ch preserved)")

        self.cancelled = False
        self.root.destroy()

    def _on_cancel(self):
        self._stop_preview()
        with open(self.done_file, "w") as f:
            f.write("CANCEL")
        print("Cancelled by user")
        self.root.destroy()

    def run(self):
        self.root.mainloop()


# ────────────────────────────────────────────────────────────────
# Main
# ────────────────────────────────────────────────────────────────

def main():
    if len(sys.argv) < 4:
        print("Usage: python spectral_eraser.py "
              "input.wav output.wav done_file [fft_size] [analysis_channel_1based] [stats_file]")
        sys.exit(1)

    check_dependencies()

    import numpy as np
    import soundfile as sf
    import tkinter as tk     # noqa: F401  (also validates tkinter)

    in_wav = sys.argv[1]
    out_wav = sys.argv[2]
    done_file = sys.argv[3]
    fft_size = int(sys.argv[4]) if len(sys.argv) > 4 else 2048
    analysis_channel_1based = int(sys.argv[5]) if len(sys.argv) > 5 else 0
    stats_file = sys.argv[6] if len(sys.argv) > 6 else ""

    if not os.path.isfile(in_wav):
        print(f"ERROR: input not found: {in_wav}", file=sys.stderr)
        sys.exit(1)

    audio, sr = sf.read(in_wav, dtype="float32", always_2d=True)
    n_channels = audio.shape[1]
    if analysis_channel_1based > 0:
        analysis_channel = max(0, min(analysis_channel_1based - 1, n_channels - 1))
    else:
        rms = np.sqrt(np.mean(audio.astype(np.float64) ** 2, axis=0))
        analysis_channel = int(np.argmax(rms))

    dur = len(audio) / sr
    print(f"  Input: {in_wav}  ({dur:.2f}s  SR={sr}  FFT={fft_size}, "
          f"channels={n_channels}, analysis_channel={analysis_channel + 1})")

    gui = SpectralEraserGUI(audio, sr, fft_size, out_wav, done_file,
                            analysis_channel=analysis_channel,
                            stats_file=stats_file)
    gui.run()


if __name__ == "__main__":
    main()