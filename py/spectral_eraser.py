"""
spectral_eraser.py  –  Interactive spectral eraser with tkinter GUI

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University

Draws a spectrogram from a WAV file.  The user can paint over
time-frequency regions to silence them.  Uses numpy STFT/iSTFT
(no scipy required).

Usage:
    python spectral_eraser.py input.wav output.wav done_file fft_size

    fft_size:  FFT window in samples (512 / 1024 / 2048 / 4096)

The GUI writes output.wav on Apply, and always writes done_file
("OK" or "CANCEL") so the calling Praat script knows what happened.
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
    """tkinter GUI: spectrogram canvas with draw-to-erase."""

    CANVAS_H = 400          # pixels (frequency axis)
    MAX_CANVAS_W = 2000     # cap width for very long sounds

    def __init__(self, audio, sr, win_size, out_wav, done_file):
        import numpy as np
        import tkinter as tk

        self.np = np
        self.tk = tk
        self.sr = sr
        self.win_size = win_size
        self.hop = win_size // 4
        self.out_wav = out_wav
        self.done_file = done_file
        self.audio = audio
        self.cancelled = True     # default until Apply

        # ── STFT ──
        self.S = stft(audio, win_size, self.hop)
        self.n_freq, self.n_frames = self.S.shape

        # ── Erasure mask  (1 = keep, 0 = erase) ──
        self.mask = np.ones((self.n_freq, self.n_frames), dtype=np.float32)

        # ── Magnitude spectrogram for display ──
        mag = np.abs(self.S)
        self.mag_db = 20.0 * np.log10(mag + 1e-10)
        self.db_floor = float(np.percentile(self.mag_db, 5))
        self.db_ceil = float(np.percentile(self.mag_db, 99))

        # ── Canvas dimensions ──
        self.cw = min(self.n_frames, self.MAX_CANVAS_W)
        self.ch = self.CANVAS_H
        self.sx = self.cw / self.n_frames   # pixels per frame
        self.sy = self.ch / self.n_freq     # pixels per freq bin

        # ── Colormap ──
        self.cmap = build_colormap()

        # ── Build window ──
        self.root = tk.Tk()
        self.root.title("Spectral Eraser — AudioTools")
        self.root.protocol("WM_DELETE_WINDOW", self._on_cancel)
        self.brush = 8
        self.rect_ids = []
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

        tk.Button(top, text="Clear All", command=self._clear_all
                  ).pack(side="left", padx=12)

        dur = len(self.audio) / self.sr
        tk.Label(top, text=(f"SR {self.sr} Hz  |  {dur:.2f} s  |  "
                            f"FFT {self.win_size}  |  "
                            f"{self.n_frames} frames  ×  "
                            f"{self.n_freq} bins"),
                 fg="#555").pack(side="left", padx=12)

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
        self.canvas.bind("<Motion>", self._on_motion)

        # ── Bottom buttons ──
        bot = tk.Frame(self.root)
        bot.pack(fill="x", padx=6, pady=5)

        tk.Button(bot, text="Apply", command=self._on_apply,
                  bg="#4CAF50", fg="white", width=12,
                  font=("Helvetica", 10, "bold")).pack(side="right", padx=5)
        tk.Button(bot, text="Cancel", command=self._on_cancel,
                  width=12).pack(side="right", padx=5)

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
        frame_idx = np.clip(
            (np.arange(w) * self.n_frames / w).astype(int),
            0, self.n_frames - 1)

        disp = self.mag_db[np.ix_(freq_idx, frame_idx)]

        # Normalise to 0-255
        rng = max(1e-6, self.db_ceil - self.db_floor)
        idx = np.clip(((disp - self.db_floor) / rng * 255).astype(int),
                       0, 255)

        # Apply colormap  → (h, w, 3)
        img = self.cmap[idx]

        # Write PPM (binary P6)
        ppm_path = os.path.join(os.path.dirname(self.out_wav),
                                "_spec_display.ppm")
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
        t_lo = int(x1 / self.cw * self.n_frames)
        t_hi = int(x2 / self.cw * self.n_frames)

        f_lo = max(0, min(f_lo, self.n_freq - 1))
        f_hi = max(0, min(f_hi, self.n_freq - 1))
        t_lo = max(0, min(t_lo, self.n_frames - 1))
        t_hi = max(0, min(t_hi, self.n_frames - 1))

        self.mask[f_lo:f_hi + 1, t_lo:t_hi + 1] = 0

    def _on_press(self, event):
        cx, cy = self._canvas_xy(event)
        self._erase_at(cx, cy)

    def _on_drag(self, event):
        cx, cy = self._canvas_xy(event)
        self._erase_at(cx, cy)

    def _on_motion(self, event):
        """Update status bar with frequency / time under cursor."""
        cx, cy = self._canvas_xy(event)
        nyq = self.sr / 2
        freq = (self.ch - cy) / self.ch * nyq
        time = cx / self.cw * len(self.audio) / self.sr
        erased = int((1.0 - self.mask.mean()) * 100)
        self.status.set(
            f"Time: {time:.3f} s  |  Freq: {freq:.0f} Hz  |  "
            f"Erased: {erased}%")

    def _clear_all(self):
        """Reset mask and remove overlay rectangles."""
        self.mask[:] = 1
        for rid in self.rect_ids:
            self.canvas.delete(rid)
        self.rect_ids.clear()
        self.status.set("Cleared — draw again to erase")

    # ────────────────── Apply / Cancel ──────────────────

    def _on_apply(self):
        """Apply mask, iSTFT, save output, write done file."""
        import soundfile as sf

        self.status.set("Applying spectral mask and reconstructing...")
        self.root.update()

        S_mod = self.S * self.mask
        y = istft(S_mod, self.win_size, self.hop, len(self.audio))

        # Normalise
        peak = max(abs(y.max()), abs(y.min()))
        if peak > 0:
            y = y / peak * 0.95

        sf.write(self.out_wav, y, self.sr)

        with open(self.done_file, "w") as f:
            f.write("OK")

        erased_pct = (1.0 - self.mask.mean()) * 100
        print(f"OK: wrote {self.out_wav}  "
              f"({erased_pct:.1f}% of spectrum erased)")

        self.cancelled = False
        self.root.destroy()

    def _on_cancel(self):
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
              "input.wav output.wav done_file [fft_size]")
        sys.exit(1)

    check_dependencies()

    import numpy as np
    import soundfile as sf
    import tkinter as tk     # noqa: F401  (also validates tkinter)

    in_wav = sys.argv[1]
    out_wav = sys.argv[2]
    done_file = sys.argv[3]
    fft_size = int(sys.argv[4]) if len(sys.argv) > 4 else 2048

    if not os.path.isfile(in_wav):
        print(f"ERROR: input not found: {in_wav}", file=sys.stderr)
        sys.exit(1)

    audio, sr = sf.read(in_wav, dtype="float32", always_2d=False)

    # Convert to mono if needed
    if audio.ndim > 1:
        audio = audio.mean(axis=1).astype(np.float32)

    dur = len(audio) / sr
    print(f"  Input: {in_wav}  ({dur:.2f}s  SR={sr}  FFT={fft_size})")

    gui = SpectralEraserGUI(audio, sr, fft_size, out_wav, done_file)
    gui.run()


if __name__ == "__main__":
    main()
