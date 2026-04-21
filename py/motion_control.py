"""
motion_control.py — Motion-Controlled Sound Transformation Worker

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University

Usage (called by Praat — do not invoke manually during a session):
    python motion_control.py control_csv stats_txt done_marker
        [capture_sec] [control_fps] [smooth_frames] [show_preview]

Pipeline:
    Stage 1  — Open webcam and detect camera FPS
    Stage 2  — Calibration phase: build a per-pixel background noise model
               (user holds still for CAL_SEC seconds)
    Stage 3  — Capture phase: record capture_sec seconds of free motion
               (optional cv2 preview window with countdown overlay)
    Stage 4  — Feature extraction per video frame:
                 · motion energy  — frame differencing, noise-floor subtracted
                 · vertical pos   — motion-weighted centroid in Y (inverted: top=1)
                 · horizontal pos — motion-weighted centroid in X (left=0, right=1)
    Stage 5  — Resample to uniform control_fps grid
    Stage 6  — Smooth (EMA), normalize (percentile stretch),
               deadband (snap to neutral below threshold),
               hysteresis (lazy follower for musical smoothness)
    Stage 7  — Write control CSV + stats file + done marker

Output files (all paths passed as CLI arguments):
    control_csv   — CSV with header: time,motion_energy,vertical_pos,horizontal_pos
                    All values 0..1.  Times in seconds.
    stats_txt     — key=value diagnostics parseable by Praat parseStatLine
    done_marker   — written last; contains "ok" or "fallback"

If the webcam cannot be opened, a graceful fallback writes neutral (0.5)
control data and marks the done file "fallback" so Praat can proceed.

Dependencies:
    numpy          pip install numpy
    opencv-python  pip install opencv-python
"""

import sys
import os
import time as _time

# ---------------------------------------------------------------------------
# Module-level constants  (overridden by CLI args where applicable)
# ---------------------------------------------------------------------------
CAPTURE_SEC   = 10      # default video capture duration in seconds
CAL_SEC       = 2       # calibration (background modelling) duration
CONTROL_FPS   = 25      # output control frame rate  (25 fps = 40 ms steps)
SMOOTH_FRAMES = 5       # EMA half-width — larger = slower, smoother response
DEADBAND      = 0.04    # energy below this snaps positions to neutral (0.5)
HYSTERESIS    = 0.35    # lazy-follower blend alpha (higher = more inertia)
CAM_INDEX     = 0       # webcam device index
NEUTRAL_POS   = 0.5     # position fallback when motion is absent


# ---------------------------------------------------------------------------
# Dependency check
# ---------------------------------------------------------------------------

def check_dependencies():
    """Abort with a helpful message if required packages are missing."""
    missing = []
    for pkg, label in [("numpy", "numpy"), ("cv2", "opencv-python")]:
        try:
            __import__(pkg)
        except ImportError:
            missing.append(label)
    if missing:
        print("ERROR: Missing packages: " + ", ".join(missing), file=sys.stderr)
        print("Install with:  pip install " + " ".join(missing), file=sys.stderr)
        sys.exit(1)


# =============================================================================
# Stage 1 — Open camera
# =============================================================================

def open_camera(cam_index):
    """
    Open the webcam at cam_index and read its declared FPS.
    Returns (cap, fps).  Raises RuntimeError if the camera cannot be opened.
    The FPS value is clamped to a sensible range; many cameras mis-report it.
    """
    import cv2
    cap = cv2.VideoCapture(cam_index)
    if not cap.isOpened():
        raise RuntimeError(
            "Could not open camera at index %d. "
            "Check that a webcam is connected and not in use by another app."
            % cam_index
        )
    fps = cap.get(cv2.CAP_PROP_FPS)
    if fps <= 0 or fps > 300:
        fps = 30.0          # safe default when camera mis-reports
    return cap, fps


# =============================================================================
# Stage 2 — Calibration
# =============================================================================

def calibration_phase(cap, cal_sec):
    """
    Capture cal_sec seconds with the user holding still.
    Builds a per-pixel background mean and standard deviation.

    The standard deviation floor is raised to 1.0 to prevent
    excessive noise removal and division-by-zero.

    Returns:
        bg_mean  float32 (H, W) — mean background intensity
        bg_std   float32 (H, W) — std + 1.0 noise floor
    """
    import numpy as np
    import cv2

    frames  = []
    t_start = _time.time()
    while _time.time() - t_start < cal_sec:
        ret, frame = cap.read()
        if ret:
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY).astype(np.float32)
            frames.append(gray)

    if len(frames) < 2:
        # Degenerate fallback — return a flat background
        ret, frame = cap.read()
        if ret:
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY).astype(np.float32)
        else:
            gray = np.zeros((480, 640), dtype=np.float32)
        return gray, np.ones_like(gray)

    bg_mean = np.mean(frames, axis=0)
    bg_std  = np.std(frames,  axis=0) + 1.0   # floor prevents over-suppression
    return bg_mean, bg_std


# =============================================================================
# Stage 3 — Capture with optional preview window
# =============================================================================

def capture_phase(cap, capture_sec, show_preview):
    """
    Capture capture_sec seconds of video from the already-open camera.
    Optionally renders a live preview with motion-heat overlay and countdown.

    Returns a list of (elapsed_sec, gray_float32) tuples.
    Elapsed times start near 0.0 and end near capture_sec.
    """
    import numpy as np
    import cv2

    frames          = []
    prev_gray       = None
    preview_active  = False

    # Attempt to open a preview window
    if show_preview:
        try:
            win = "Motion Capture — Praat AudioTools"
            cv2.namedWindow(win, cv2.WINDOW_NORMAL)
            cv2.resizeWindow(win, 640, 480)
            preview_active = True
        except Exception:
            preview_active = False

    t_start = _time.time()

    while True:
        elapsed = _time.time() - t_start
        if elapsed >= capture_sec:
            break

        ret, frame = cap.read()
        if not ret:
            continue

        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY).astype(np.float32)
        frames.append((elapsed, gray))

        if preview_active:
            try:
                vis = frame.copy()

                # Superimpose motion heat (difference from previous frame)
                if prev_gray is not None:
                    diff     = np.abs(gray - prev_gray)
                    diff_vis = np.clip(diff / 40.0 * 255, 0, 255).astype(np.uint8)
                    heat     = cv2.applyColorMap(diff_vis, cv2.COLORMAP_JET)
                    vis      = cv2.addWeighted(vis, 0.55, heat, 0.45, 0)

                # Countdown overlay
                remaining = max(0.0, capture_sec - elapsed)
                label = "RECORDING  %.1fs remaining" % remaining
                cv2.rectangle(vis, (8, 6), (410, 50), (0, 0, 0), -1)
                cv2.putText(vis, label, (16, 38),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.9, (0, 255, 80), 2)

                cv2.imshow(win, vis)
                cv2.waitKey(1)
            except Exception:
                preview_active = False

        prev_gray = gray

    if preview_active:
        try:
            cv2.destroyAllWindows()
            cv2.waitKey(1)
        except Exception:
            pass

    return frames


# =============================================================================
# Stage 4 + 5 — Feature extraction and resampling
# =============================================================================

def extract_motion_features(frames, bg_std, control_fps):
    """
    Extract motion energy, vertical centroid, and horizontal centroid
    from the raw frame list via frame differencing.

    Per-frame positions are computed as the motion-weighted centroid of the
    noise-suppressed difference image:
      vertical_pos   0 = bottom of frame, 1 = top  (image row axis inverted)
      horizontal_pos 0 = left,            1 = right

    Features are first computed at the native capture rate and then
    linearly interpolated onto a uniform grid at control_fps.

    Returns:
        ctrl_times  ndarray (n,)  — uniform time grid, 0 .. total_dur
        ctrl_energy ndarray (n,)  — raw motion energy
        ctrl_vert   ndarray (n,)  — vertical centroid
        ctrl_horiz  ndarray (n,)  — horizontal centroid
    """
    import numpy as np

    if len(frames) < 2:
        n     = max(4, int(10.0 * control_fps))
        times = np.linspace(0.0, 10.0, n)
        return times, np.full(n, 0.2), np.full(n, 0.5), np.full(n, 0.5)

    h, w = frames[0][1].shape

    # Coordinate grids, normalised to [0, 1]
    y_grid = np.tile(np.linspace(0.0, 1.0, h, dtype=np.float32)[:, None], (1, w))
    x_grid = np.tile(np.linspace(0.0, 1.0, w, dtype=np.float32)[None, :], (h, 1))

    raw_times  = []
    raw_energy = []
    raw_vert   = []
    raw_horiz  = []

    prev_gray = frames[0][1]

    for i in range(1, len(frames)):
        t, gray = frames[i]

        # Frame differencing
        diff = np.abs(gray - prev_gray)

        # Subtract noise floor (1.5 sigma from calibration)
        diff = np.maximum(0.0, diff - bg_std * 1.5)

        energy = float(np.mean(diff))

        # Motion-weighted centroid
        total = float(np.sum(diff))
        if total > 0.5:
            vert_c  = float(np.sum(diff * y_grid)) / total
            horiz_c = float(np.sum(diff * x_grid)) / total
        else:
            vert_c  = NEUTRAL_POS
            horiz_c = NEUTRAL_POS

        # Invert vertical: image top (row 0) should correspond to "high" (1)
        vert_c = 1.0 - vert_c

        raw_times.append(t)
        raw_energy.append(energy)
        raw_vert.append(vert_c)
        raw_horiz.append(horiz_c)

        prev_gray = gray

    raw_times  = np.array(raw_times,  dtype=np.float64)
    raw_energy = np.array(raw_energy, dtype=np.float64)
    raw_vert   = np.array(raw_vert,   dtype=np.float64)
    raw_horiz  = np.array(raw_horiz,  dtype=np.float64)

    # Resample to uniform control-rate grid
    total_dur  = float(raw_times[-1])
    n_ctrl     = max(4, int(total_dur * control_fps))
    ctrl_times = np.linspace(0.0, total_dur, n_ctrl)

    ctrl_energy = np.interp(ctrl_times, raw_times, raw_energy)
    ctrl_vert   = np.interp(ctrl_times, raw_times, raw_vert)
    ctrl_horiz  = np.interp(ctrl_times, raw_times, raw_horiz)

    return ctrl_times, ctrl_energy, ctrl_vert, ctrl_horiz


# =============================================================================
# Stage 6 — Smooth, normalize, deadband, hysteresis
# =============================================================================

def smooth_normalize(ctrl_times, ctrl_energy, ctrl_vert, ctrl_horiz, smooth_frames):
    """
    Apply the musical-control signal processing chain:

      1. Exponential moving average (EMA) — reduces high-frequency jitter.
         The effective window is smooth_frames; larger = slower response.

      2. Percentile stretch (5th–95th pct) — maps the actual range to 0..1
         so sparse or weak motion still uses the full scale.

      3. Deadband + soft transition — when energy is below DEADBAND,
         positions glide to neutral (0.5) via a 3×deadband transition zone.
         This prevents jitter from driving the transforms when the user is still.

      4. Hysteresis (lazy follower) — first-order IIR on positions.
         Slows fast transitions to reduce zipper noise in the mapped sound.

      5. Final clamp to [0, 1].

    Returns:
        energy_n  (n,)  normalized motion energy
        vert_n    (n,)  processed vertical position
        horiz_n   (n,)  processed horizontal position
    """
    import numpy as np

    def ema(arr, n):
        if n <= 1:
            return arr.copy()
        alpha = 2.0 / (float(n) + 1.0)
        out   = arr.copy()
        for i in range(1, len(out)):
            out[i] = alpha * arr[i] + (1.0 - alpha) * out[i - 1]
        return out

    def pct_stretch(arr, lo_pct=5, hi_pct=95, fallback=0.3):
        lo = np.percentile(arr, lo_pct)
        hi = np.percentile(arr, hi_pct)
        if hi - lo < 1e-7:
            return np.full_like(arr, fallback)
        return np.clip((arr - lo) / (hi - lo), 0.0, 1.0)

    def lazy_follow(arr, alpha=HYSTERESIS):
        out = arr.copy()
        for i in range(1, len(out)):
            out[i] = (1.0 - alpha) * arr[i] + alpha * out[i - 1]
        return out

    # 1. Smooth
    energy_s = ema(ctrl_energy, smooth_frames)
    vert_s   = ema(ctrl_vert,   smooth_frames)
    horiz_s  = ema(ctrl_horiz,  smooth_frames)

    # 2. Normalize
    energy_n = pct_stretch(energy_s, 5,  95, fallback=0.2)
    vert_n   = pct_stretch(vert_s,   5,  95, fallback=0.5)
    horiz_n  = pct_stretch(horiz_s,  5,  95, fallback=0.5)

    # 3. Deadband — soft blend toward neutral
    dead_floor = max(DEADBAND, 1e-6)
    blend = np.clip((energy_n - DEADBAND) / (3.0 * dead_floor), 0.0, 1.0)
    vert_n  = blend * vert_n  + (1.0 - blend) * NEUTRAL_POS
    horiz_n = blend * horiz_n + (1.0 - blend) * NEUTRAL_POS

    # 4. Hysteresis on positions
    vert_n  = lazy_follow(vert_n)
    horiz_n = lazy_follow(horiz_n)

    # 5. Final clamp
    energy_n = np.clip(energy_n, 0.0, 1.0)
    vert_n   = np.clip(vert_n,   0.0, 1.0)
    horiz_n  = np.clip(horiz_n,  0.0, 1.0)

    return energy_n, vert_n, horiz_n


# =============================================================================
# Stage 7 — Write output files
# =============================================================================

def write_control_csv(path, times, energy, vert, horiz):
    """
    Write the control timeline CSV.  Praat reads this with
    'Read Table from comma-separated file' then 'Get value'.
    All data values are in 0..1 range.  Times are in seconds.
    """
    with open(path, "w") as f:
        f.write("time,motion_energy,vertical_pos,horizontal_pos\n")
        for i in range(len(times)):
            f.write("%.4f,%.4f,%.4f,%.4f\n" % (
                float(times[i]),
                float(energy[i]),
                float(vert[i]),
                float(horiz[i])))


def write_stats(path, times, energy, vert, horiz,
                cam_fps, n_raw_frames, warnings):
    """
    Write key=value stats file parseable by Praat's parseStatLine procedure.
    All keys use the exact names expected by MotionControl.praat.
    """
    import numpy as np

    dur           = float(times[-1]) if len(times) > 0 else 0.0
    n_ctrl        = int(len(times))
    tracking_conf = float(np.mean(energy > DEADBAND))

    with open(path, "w") as f:
        f.write("duration=%.3f\n"            % dur)
        f.write("camera_fps=%.2f\n"          % float(cam_fps))
        f.write("n_raw_frames=%d\n"          % int(n_raw_frames))
        f.write("n_ctrl_frames=%d\n"         % n_ctrl)
        f.write("mean_motion=%.4f\n"         % float(np.mean(energy)))
        f.write("max_motion=%.4f\n"          % float(np.max(energy)))
        f.write("mean_vert=%.4f\n"           % float(np.mean(vert)))
        f.write("mean_horiz=%.4f\n"          % float(np.mean(horiz)))
        f.write("tracking_confidence=%.3f\n" % tracking_conf)
        if warnings:
            f.write("warnings=%s\n"  % "; ".join(warnings))
        else:
            f.write("warnings=none\n")


# =============================================================================
# Fallback — neutral data when camera is unavailable
# =============================================================================

def generate_fallback_data(capture_sec, control_fps):
    """
    Return gentle, stable neutral control data when the webcam fails.
    Energy is set to 0.25 so the amplitude transformation does not
    silence the sound entirely.  Positions are centred at 0.5.
    """
    import numpy as np
    n     = max(4, int(float(capture_sec) * float(control_fps)))
    times = np.linspace(0.0, float(capture_sec), n)
    return (times,
            np.full(n, 0.25, dtype=np.float64),
            np.full(n, 0.50, dtype=np.float64),
            np.full(n, 0.50, dtype=np.float64))


# =============================================================================
# Main
# =============================================================================

def main():
    if len(sys.argv) < 4:
        print(
            "Usage: python motion_control.py "
            "control_csv stats_txt done_marker "
            "[capture_sec] [control_fps] [smooth_frames] [show_preview]",
            file=sys.stderr)
        sys.exit(1)

    check_dependencies()
    import numpy as np

    # ── Parse + clamp CLI arguments ─────────────────────────────────
    control_csv  = sys.argv[1]
    stats_txt    = sys.argv[2]
    done_marker  = sys.argv[3]
    capture_sec  = int(sys.argv[4])       if len(sys.argv) > 4 else CAPTURE_SEC
    control_fps  = int(sys.argv[5])       if len(sys.argv) > 5 else CONTROL_FPS
    smooth_frm   = int(sys.argv[6])       if len(sys.argv) > 6 else SMOOTH_FRAMES
    show_preview = (sys.argv[7] == "1")   if len(sys.argv) > 7 else True

    capture_sec = max(3,  min(60,  capture_sec))
    control_fps = max(10, min(100, control_fps))
    smooth_frm  = max(1,  min(50,  smooth_frm))

    warnings = []
    cam_fps  = 0.0
    n_raw    = 0

    # ── Stage 1–3: Open camera, calibrate, capture ──────────────────
    frames = None
    bg_std = None

    try:
        print("  [Py 1/5] Opening camera (index %d)..." % CAM_INDEX)
        cap, cam_fps = open_camera(CAM_INDEX)

        print("  [Py 2/5] Calibration (%.0fs) — hold still..." % CAL_SEC)
        bg_mean, bg_std = calibration_phase(cap, CAL_SEC)
        print("           Background model built.")

        print("  [Py 3/5] Recording %ds — MOVE NOW!" % capture_sec)
        frames = capture_phase(cap, capture_sec, show_preview)
        cap.release()
        n_raw = len(frames)
        print("    Captured %d frames (camera: %.1f fps)" % (n_raw, cam_fps))

    except Exception as exc:
        msg = str(exc)
        warnings.append("Camera error: " + msg)
        print("  WARNING: Camera unavailable (%s)" % msg, file=sys.stderr)
        print("           Writing neutral fallback data.")

        times, energy, vert, horiz = generate_fallback_data(capture_sec, control_fps)
        write_control_csv(control_csv, times, energy, vert, horiz)
        write_stats(stats_txt, times, energy, vert, horiz,
                    cam_fps, n_raw, warnings)
        with open(done_marker, "w") as f:
            f.write("fallback\n")
        print("OK: fallback data written to %s" % control_csv)
        return

    # ── Stage 4+5: Feature extraction ───────────────────────────────
    print("  [Py 4/5] Extracting motion features...")
    times, energy, vert, horiz = extract_motion_features(
        frames, bg_std, control_fps)
    print("    %d ctrl frames  |  energy range: [%.3f, %.3f]" % (
        len(times), float(np.min(energy)), float(np.max(energy))))

    if len(times) < 4:
        warnings.append("Too few control frames extracted (%d)" % len(times))
        times, energy, vert, horiz = generate_fallback_data(capture_sec, control_fps)
        print("    WARNING: Using fallback data.")

    # ── Stage 6: Smooth + normalize ─────────────────────────────────
    print("  [Py 5/5] Smoothing and normalizing (EMA window=%d)..." % smooth_frm)
    energy, vert, horiz = smooth_normalize(
        times, energy, vert, horiz, smooth_frm)

    tracking_conf = float(np.mean(energy > DEADBAND))
    print("    Tracking confidence: %.0f%%" % (tracking_conf * 100.0))
    if tracking_conf < 0.30:
        warnings.append(
            "Low tracking confidence (%.0f%%) — check lighting and movement range"
            % (tracking_conf * 100.0))

    # ── Stage 7: Write output ────────────────────────────────────────
    write_control_csv(control_csv, times, energy, vert, horiz)
    write_stats(stats_txt, times, energy, vert, horiz,
                cam_fps, n_raw, warnings)

    with open(done_marker, "w") as f:
        f.write("ok\n")

    print("OK: wrote %d control frames to %s" % (len(times), control_csv))


if __name__ == "__main__":
    main()
