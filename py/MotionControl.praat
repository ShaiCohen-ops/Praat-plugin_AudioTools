# ============================================================
# Praat AudioTools - MotionControl.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Motion-Controlled Sound Transformation
#
#   Launches a Python worker that opens the webcam, captures 10 seconds
#   of free-hand motion (after a 2-second background calibration), and
#   extracts three normalised control channels via frame differencing
#   and centroid tracking.  Praat reads the returned CSV and applies
#   three parallel offline transformations to the selected Sound:
#
#     motion energy       →  amplitude envelope  (AmplitudeTier)
#     vertical position   →  pitch contour        (Manipulation + PitchTier)
#     horizontal position →  spectral brightness  (HPF modulation)
#
#   The pipeline is entirely file-based — no sockets, no OSC, no
#   realtime streaming between Praat and Python.
#
#   Python dependencies:
#     numpy, opencv-python
#     Install:  pip install numpy opencv-python
#
#   Brightness method:
#     A high-pass filtered copy of the sound (above ~2 kHz) is
#     added or subtracted in proportion to the horizontal position.
#     Right hand → add HPF → brighter; Left → subtract HPF → darker;
#     Centre → no change.  This is time-varying and artifact-free.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# ============================================================

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound      = selected("Sound")
soundName$ = selected$("Sound")

# ---- OS-Specific Python Discovery ----
if macintosh
    if fileReadable("/opt/homebrew/bin/python3")
        pythonCmd$ = "/opt/homebrew/bin/python3"
    elsif fileReadable("/Library/Frameworks/Python.framework/Versions/3.14/bin/python3")
        pythonCmd$ = "/Library/Frameworks/Python.framework/Versions/3.14/bin/python3"
    elsif fileReadable("/usr/local/bin/python3")
        pythonCmd$ = "/usr/local/bin/python3"
    else
        pythonCmd$ = "python3"
    endif
elsif windows
    pythonCmd$ = "python"
else
    pythonCmd$ = "python3"
endif

# ---- PATHS ----
pluginDir$    = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/motion_control.py"

if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/motion_control.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: motion_control.py" + newline$
     ... + "Expected at: " + pluginDir$ + "py/"
     ... + newline$ + "or next to this .praat file."
endif

# ---- TEMP FILES ----
tempControl$ = temporaryDirectory$ + "/temp_motctrl_control.csv"
tempStats$   = temporaryDirectory$ + "/temp_motctrl_stats.txt"
tempDone$    = temporaryDirectory$ + "/temp_motctrl_done.ok"
tempProbe$   = temporaryDirectory$ + "/temp_motctrl_probe.ok"

# Forward-slash version of probe path for the inline Python one-liner
tempProbeJ$  = replace_regex$(tempProbe$, "\\", "/", 0)

# ---- CLEANUP PROCEDURE ----
procedure cleanUpTempFiles
    if fileReadable(tempControl$)
        deleteFile: tempControl$
    endif
    if fileReadable(tempStats$)
        deleteFile: tempStats$
    endif
    if fileReadable(tempDone$)
        deleteFile: tempDone$
    endif
    if fileReadable(tempProbe$)
        deleteFile: tempProbe$
    endif
endproc

@cleanUpTempFiles

# ===========================================================================
# FORM
# ===========================================================================
form Motion-Controlled Sound Transformation v1.0
    optionmenu Preset: 3
        option Custom
        option Subtle gesture
        option Expressive performer
        option Wild motion
        option Meditative
    real    Pitch_range_st 6.0
    real    Amplitude_min 0.20
    real    Amplitude_max 1.00
    real    Brightness_range 0.80
    integer Smooth_frames 5
    integer Control_fps 25
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---- PRESETS ----
# Each preset overrides ALL parameters for a consistent character.
if preset = 2
    # Small, refined gestures — gentle everything
    pitch_range_st   = 3.0
    amplitude_min    = 0.50
    amplitude_max    = 1.00
    brightness_range = 0.40
    smooth_frames    = 9
    control_fps      = 25
    presetName$      = "SubtleGesture"
elsif preset = 3
    # Balanced expressive range — good starting point
    pitch_range_st   = 6.0
    amplitude_min    = 0.20
    amplitude_max    = 1.00
    brightness_range = 0.80
    smooth_frames    = 5
    control_fps      = 25
    presetName$      = "ExpressivePerformer"
elsif preset = 4
    # Dramatic, wide-range, snappy response
    pitch_range_st   = 12.0
    amplitude_min    = 0.08
    amplitude_max    = 1.00
    brightness_range = 1.20
    smooth_frames    = 3
    control_fps      = 25
    presetName$      = "WildMotion"
elsif preset = 5
    # Very slow, narrow, inertia-heavy — drone and sustained-tone work
    pitch_range_st   = 2.0
    amplitude_min    = 0.55
    amplitude_max    = 0.90
    brightness_range = 0.30
    smooth_frames    = 18
    control_fps      = 15
    presetName$      = "Meditative"
else
    presetName$ = "Custom"
endif

# ---- CLAMP ----
if pitch_range_st < 0
    pitch_range_st = 0
endif
if pitch_range_st > 24
    pitch_range_st = 24
endif
if amplitude_min < 0
    amplitude_min = 0
endif
if amplitude_min > 1
    amplitude_min = 1
endif
if amplitude_max < amplitude_min
    amplitude_max = amplitude_min
endif
if amplitude_max > 2
    amplitude_max = 2
endif
if brightness_range < 0
    brightness_range = 0
endif
if brightness_range > 2
    brightness_range = 2
endif
if smooth_frames < 1
    smooth_frames = 1
endif
if smooth_frames > 50
    smooth_frames = 50
endif
if control_fps < 10
    control_fps = 10
endif
if control_fps > 100
    control_fps = 100
endif

# ---- ORIGINAL SOUND STATS ----
selectObject: sound
dur       = Get total duration
sr        = Get sampling frequency
nChannels = Get number of channels
rms_orig  = Get root-mean-square: 0, 0

# ---- INFO HEADER ----
clearinfo
writeInfoLine:  "=== Motion-Controlled Sound Transformation v1.0 ==="
appendInfoLine: "Input:   ", soundName$
appendInfoLine: "Preset:  ", presetName$
appendInfoLine: ""
appendInfoLine: "Mappings:"
appendInfoLine: "  Motion energy       ->  Amplitude  [", fixed$(amplitude_min, 2),
 ... " .. ", fixed$(amplitude_max, 2), "]"
appendInfoLine: "  Vertical position   ->  Pitch      +/-", fixed$(pitch_range_st, 1),
 ... " semitones"
appendInfoLine: "  Horizontal position ->  Brightness  range ", fixed$(brightness_range, 2)
appendInfoLine: ""
appendInfoLine: "Capture: ", fixed$(dur, 2), " s  |  Control fps: ", control_fps,
 ... "  |  Smooth frames: ", smooth_frames
appendInfoLine: ""
appendInfoLine: "Duration: ", fixed$(dur, 2), " s  |  SR: ", sr,
 ... " Hz  |  Channels: ", nChannels
appendInfoLine: ""

# ===========================================================================
# Stage 1 — Detect Python + Dependencies
# ===========================================================================
appendInfoLine: "[1/6] Checking Python dependencies..."

probeCmd$ = pythonCmd$ + " -c ""import numpy, cv2;"
 ... + " open('""" + tempProbeJ$ + """', 'w').write('ok')"""
runSystem_nocheck: probeCmd$

if not fileReadable(tempProbe$)
    @cleanUpTempFiles
    exitScript: "Python or required packages not found." + newline$
     ... + "Please install:  pip install numpy opencv-python" + newline$
     ... + "(Python tried: " + pythonCmd$ + ")"
endif
deleteFile: tempProbe$
appendInfoLine: "  OK:  ", pythonCmd$

# ===========================================================================
# Stage 2 — User Prompt + Launch Python Worker
# ===========================================================================
appendInfoLine: "[2/6] Motion capture..."
appendInfoLine: ""
appendInfoLine: "  +------------------------------------------+"
appendInfoLine: "  |        WEBCAM CAPTURE STARTING           |"
appendInfoLine: "  |                                          |"
appendInfoLine: "  |  Phase 1 (2 s)  : hold completely still |"
appendInfoLine: "  |  Phase 2 (", fixed$(dur, 0), " s) : move freely            |"
appendInfoLine: "  |                                          |"
appendInfoLine: "  |  A preview window will open if possible. |"
appendInfoLine: "  +------------------------------------------+"
appendInfoLine: ""

# Pause so the user can position themselves before capture begins
pause Position yourself in front of the webcam, then click Continue.
 ... Phase 1: hold still 2 s (calibration). Phase 2: move 'round(dur)' s (recording).

# Build Python command
# Arguments: control_csv  stats_txt  done_marker
#            capture_sec  control_fps  smooth_frames  show_preview
pythonCall$ = pythonCmd$ + " """ + pythonScript$ + """"
    ... + " """ + tempControl$ + """"
    ... + " """ + tempStats$ + """"
    ... + " """ + tempDone$ + """"
    ... + " " + string$(round(dur))
    ... + " " + string$(control_fps)
    ... + " " + string$(smooth_frames)
    ... + " 1"

appendInfoLine: "  Launching: ", pythonCall$
runSystem_nocheck: pythonCall$

# Verify completion marker
if not fileReadable(tempDone$)
    @cleanUpTempFiles
    exitScript: "Python worker did not complete." + newline$
     ... + "Check that your webcam is available and try again."
endif

doneText$ = readFile$(tempDone$)
if index(doneText$, "fallback") > 0
    appendInfoLine: "  NOTE: Webcam unavailable — neutral fallback data used."
else
    appendInfoLine: "  Motion capture complete."
endif

# ===========================================================================
# Stage 3 — Read Control CSV + Stats
# ===========================================================================
appendInfoLine: "[3/6] Reading control data..."

if not fileReadable(tempControl$)
    @cleanUpTempFiles
    exitScript: "Control file not found: " + tempControl$
endif

Read Table from comma-separated file: tempControl$
ctrlTable = selected("Table")
nCtrl = Get number of rows

if nCtrl < 2
    removeObject: ctrlTable
    @cleanUpTempFiles
    exitScript: "Control file has too few rows (" + string$(nCtrl) + ")."
endif

# Load all four columns into indexed scalar variables
# ctrl_t_i  ctrl_e_i  ctrl_v_i  ctrl_h_i  (i = 1..nCtrl)
for i from 1 to nCtrl
    selectObject: ctrlTable
    .val$ = Get value: i, "time"
    ctrl_t_'i' = number(.val$)
    .val$ = Get value: i, "motion_energy"
    ctrl_e_'i' = number(.val$)
    .val$ = Get value: i, "vertical_pos"
    ctrl_v_'i' = number(.val$)
    .val$ = Get value: i, "horizontal_pos"
    ctrl_h_'i' = number(.val$)
endfor
removeObject: ctrlTable

appendInfoLine: "  Loaded ", nCtrl, " control frames"
appendInfoLine: "  Control duration: ", fixed$(ctrl_t_'nCtrl', 2), " s"

# ---- Read stats file ----
py_dur$           = "?"
py_cam_fps$       = "?"
py_n_raw$         = "?"
py_n_ctrl$        = "?"
py_mean_motion$   = "?"
py_max_motion$    = "?"
py_tracking_conf$ = "?"
py_warnings$      = "none"

if fileReadable(tempStats$)
    statsText$ = readFile$(tempStats$)

    @parseStatLine: statsText$, "duration="
    py_dur$ = parseStatLine.result$
    @parseStatLine: statsText$, "camera_fps="
    py_cam_fps$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_raw_frames="
    py_n_raw$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_ctrl_frames="
    py_n_ctrl$ = parseStatLine.result$
    @parseStatLine: statsText$, "mean_motion="
    py_mean_motion$ = parseStatLine.result$
    @parseStatLine: statsText$, "max_motion="
    py_max_motion$ = parseStatLine.result$
    @parseStatLine: statsText$, "tracking_confidence="
    py_tracking_conf$ = parseStatLine.result$
    @parseStatLine: statsText$, "warnings="
    py_warnings$ = parseStatLine.result$
endif

appendInfoLine: "  Camera fps: ", py_cam_fps$,
 ... "  |  Raw frames: ", py_n_raw$
appendInfoLine: "  Tracking confidence: ", py_tracking_conf$
if py_warnings$ <> "?" and py_warnings$ <> "none"
    appendInfoLine: "  WARNING: ", py_warnings$
endif

# ===========================================================================
# Stage 4 — Prepare Working Copy (always mono)
# ===========================================================================
appendInfoLine: "[4/6] Applying transformations..."

selectObject: sound
if nChannels > 1
    appendInfoLine: "  (Stereo input: using channel 1)"
    Extract one channel: 1
    workSound = selected("Sound")
else
    Copy: "motctrl_work"
    workSound = selected("Sound")
endif

selectObject: workSound
workDur = Get total duration

# Determine how many control points fall within the sound duration.
# Control data is 10 s; sound may be shorter or longer.
nCtrlEff = nCtrl
for i from 1 to nCtrl
    if ctrl_t_'i' > workDur + 0.001
        if nCtrlEff = nCtrl
            nCtrlEff = i - 1
        endif
    endif
endfor
if nCtrlEff < 2
    nCtrlEff = min(nCtrl, 2)
endif

# ===========================================================================
# Stage 4a — Amplitude Envelope  (AmplitudeTier × Sound)
# ===========================================================================
# mapping: energy 0..1  ->  amplitude amplitude_min..amplitude_max  (linear)
# An AmplitudeTier stores linear scale factors; 1.0 = no change.
# ===========================================================================
appendInfoLine: "  [4a] Amplitude: motion energy -> [",
 ... fixed$(amplitude_min, 2), " .. ", fixed$(amplitude_max, 2), "]"

Create AmplitudeTier: "motctrl_amp", 0, workDur
ampTier = selected("AmplitudeTier")

# Boundary at t = 0
ampScale0 = amplitude_min + ctrl_e_1 * (amplitude_max - amplitude_min)
selectObject: ampTier
Add point: 0, ampScale0

# Interior control points (skip t=0 guard, add t <= workDur)
for i from 1 to nCtrlEff
    t = ctrl_t_'i'
    if t > 0 and t <= workDur
        ampScale = amplitude_min + ctrl_e_'i' * (amplitude_max - amplitude_min)
        selectObject: ampTier
        Add point: t, ampScale
    endif
endfor

# Boundary at sound end
ampScaleEnd = amplitude_min + ctrl_e_'nCtrlEff' * (amplitude_max - amplitude_min)
selectObject: ampTier
Add point: workDur, ampScaleEnd

# Multiply the sound by the amplitude tier
selectObject: workSound, ampTier
Multiply
ampTransformed = selected("Sound")
Rename: "motctrl_amp_result"

removeObject: ampTier, workSound

# ===========================================================================
# Stage 4b — Pitch Contour  (Manipulation + PitchTier)
# ===========================================================================
# mapping: vertical_pos 0..1 -> pitch shift   -pitch_range_st .. +pitch_range_st
#          0.5 = no shift   1.0 = +N st (high hand = high pitch)
#          Original F0 values are queried from the extracted PitchTier and
#          multiplied by 2^(semitones/12).  Unvoiced regions are unchanged.
# ===========================================================================
appendInfoLine: "  [4b] Pitch: vertical position -> +/-",
 ... fixed$(pitch_range_st, 1), " semitones"

selectObject: ampTransformed
noprogress To Manipulation: 0.01, 75, 600
manip = selected("Manipulation")

selectObject: manip
Extract pitch tier
origPitchTier = selected("PitchTier")
selectObject: origPitchTier
nOrigPitchPts = Get number of points

Create PitchTier: "motctrl_pitch_shifted", 0, workDur
shiftedPitchTier = selected("PitchTier")

# Reference F0 for unvoiced fallback (used when pitch is undefined)
refF0 = 150.0

# Boundary point at t ~ 0 (avoid exact 0 which can confuse the Manipulation)
v0         = ctrl_v_1
shift0_st  = (v0 - 0.5) * 2.0 * pitch_range_st
selectObject: origPitchTier
f0_0 = Get value at time: 0.01
if f0_0 = undefined or f0_0 < 30
    f0_0 = refF0
endif
shifted0 = f0_0 * (2 ^ (shift0_st / 12.0))
shifted0 = max(40, min(900, shifted0))
selectObject: shiftedPitchTier
Add point: 0.001, shifted0

# Main control points
for i from 1 to nCtrlEff
    t = ctrl_t_'i'
    if t >= 0.002 and t <= workDur - 0.001
        semiShift = (ctrl_v_'i' - 0.5) * 2.0 * pitch_range_st

        selectObject: origPitchTier
        origF0 = Get value at time: t
        if origF0 = undefined or origF0 < 30
            origF0 = refF0
        endif

        shiftedF0 = origF0 * (2 ^ (semiShift / 12.0))
        shiftedF0 = max(40, min(900, shiftedF0))

        selectObject: shiftedPitchTier
        Add point: t, shiftedF0
    endif
endfor

# Replace pitch tier in the Manipulation and resynthesize
selectObject: manip
plusObject: shiftedPitchTier
Replace pitch tier

selectObject: manip
noprogress Get resynthesis (overlap-add)
pitchTransformed = selected("Sound")
Rename: "motctrl_pitch_result"

removeObject: manip, origPitchTier, shiftedPitchTier, ampTransformed

# ===========================================================================
# Stage 4c — Spectral Brightness  (time-varying HPF modulation)
# ===========================================================================
# mapping: horizontal_pos 0..1 -> spectral tilt
#          0.5 = neutral (no change)
#          1.0 = add HPF * brightness_range  (brighter — right hand)
#          0.0 = subtract HPF * brightness_range  (darker  — left hand)
#
# Implementation: a single high-pass filtered copy of the sound (HPF) is
# created once, then scaled and added/subtracted time-variably using two
# AmplitudeTiers (one for the positive / bright contribution, one for the
# negative / dark contribution).  This avoids per-segment processing and
# gives clean, click-free results.
#
# HPF cutoff: max(1000 Hz,  SR / 22)  — captures presence/air range.
# ===========================================================================
if brightness_range > 0
    appendInfoLine: "  [4c] Brightness: horizontal position -> HPF modulation",
     ... " (range=", fixed$(brightness_range, 2), ")"

    nyq        = sr / 2.0
    hpfCutoff  = max(1000.0, sr / 22.0)

    # High-pass filter (Hann band-pass from hpfCutoff to Nyquist)
    selectObject: pitchTransformed
    noprogress Filter (pass Hann band): hpfCutoff, nyq - 1.0, 100.0
    hpfSound = selected("Sound")
    Rename: "motctrl_hpf"

    # Two amplitude tiers:
    #   posHpfTier  = max(0,  (h - 0.5) * 2 * brightness_range)  bright side
    #   negHpfTier  = max(0,  (0.5 - h) * 2 * brightness_range)  dark side
    Create AmplitudeTier: "motctrl_pos_hpf", 0, workDur
    posHpfTier = selected("AmplitudeTier")
    Create AmplitudeTier: "motctrl_neg_hpf", 0, workDur
    negHpfTier = selected("AmplitudeTier")

    # Boundary at t = 0
    h0    = ctrl_h_1
    posV0 = max(0, (h0 - 0.5) * 2.0 * brightness_range)
    negV0 = max(0, (0.5 - h0) * 2.0 * brightness_range)
    selectObject: posHpfTier
    Add point: 0, posV0
    selectObject: negHpfTier
    Add point: 0, negV0

    # Interior control points
    for i from 1 to nCtrlEff
        t = ctrl_t_'i'
        if t > 0 and t <= workDur
            h    = ctrl_h_'i'
            posV = max(0, (h - 0.5) * 2.0 * brightness_range)
            negV = max(0, (0.5 - h) * 2.0 * brightness_range)
            selectObject: posHpfTier
            Add point: t, posV
            selectObject: negHpfTier
            Add point: t, negV
        endif
    endfor

    # Boundary at sound end
    hEnd    = ctrl_h_'nCtrlEff'
    posVEnd = max(0, (hEnd - 0.5) * 2.0 * brightness_range)
    negVEnd = max(0, (0.5 - hEnd) * 2.0 * brightness_range)
    selectObject: posHpfTier
    Add point: workDur, posVEnd
    selectObject: negHpfTier
    Add point: workDur, negVEnd

    # Scale HPF sound by each tier separately
    selectObject: hpfSound, posHpfTier
    Multiply
    posHpfScaled = selected("Sound")
    Rename: "motctrl_hpf_bright"

    selectObject: hpfSound, negHpfTier
    Multiply
    negHpfScaled = selected("Sound")
    Rename: "motctrl_hpf_dark"

    removeObject: hpfSound, posHpfTier, negHpfTier

    # Combine:  result = pitchTransformed + posHpfScaled - negHpfScaled
    # (at h=0.5: pos=neg=0, result = pitchTransformed unchanged)
    selectObject: pitchTransformed
    Copy: soundName$ + "_motion"
    resultSound = selected("Sound")

    posId = posHpfScaled
    negId = negHpfScaled
    Formula: "self + object['posId', 1, col] - object['negId', 1, col]"

    removeObject: posHpfScaled, negHpfScaled, pitchTransformed

else
    appendInfoLine: "  [4c] Brightness: skipped (range = 0)"
    selectObject: pitchTransformed
    Rename: soundName$ + "_motion"
    resultSound = pitchTransformed
endif

# ---- Prevent clipping ----
selectObject: resultSound
peakAbs = Get absolute extremum: 0, 0, "None"
if peakAbs > 0.98
    Scale peak: 0.97
endif

appendInfoLine: "  Transformations complete."

# ===========================================================================
# Stage 5 — Result Stats
# ===========================================================================
selectObject: resultSound
rms_out = Get root-mean-square: 0, 0
dur_out = Get total duration

appendInfoLine: ""
appendInfoLine: "[5/6] Output: ", soundName$, "_motion"
appendInfoLine: "  Duration: ", fixed$(dur_out, 2), " s"
appendInfoLine: "  RMS: ", fixed$(rms_orig, 4), " -> ", fixed$(rms_out, 4)

# ===========================================================================
# Stage 6 — Visualization
# ===========================================================================
if draw_visualization
    appendInfoLine: "[6/6] Drawing visualization..."

    Erase all
    Font size: 10
    Line width: 1
    Colour: "Black"

    ctrlDur = ctrl_t_'nCtrl'

    # ========================================================================
    # Title panel
    # ========================================================================
    Select outer viewport: 0, 8, 0, 0.55
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", 0.70, "half", "##Motion-Controlled Sound Transformation##"
    Font size: 8
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -0.40, "half",
     ... soundName$ + "  |  " + presetName$
     ... + "  |  Conf: " + py_tracking_conf$
     ... + "  |  Cam fps: " + py_cam_fps$

    # ========================================================================
    # Original waveform
    # ========================================================================
    Select outer viewport: 0, 8, 0.6, 1.55
    Select inner viewport: 0.7, 7.7, 0.65, 1.50

    selectObject: sound
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text top: "no", fixed$(dur, 2) + " s  |  " + string$(sr) + " Hz  |  "
     ... + string$(nChannels) + " ch  |  RMS " + fixed$(rms_orig, 4)

    # ========================================================================
    # Transformed waveform
    # ========================================================================
    Select outer viewport: 0, 8, 1.55, 2.50
    Select inner viewport: 0.7, 7.7, 1.60, 2.45

    selectObject: resultSound
    Colour: "{0.20, 0.35, 0.78}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Transformed"
    Font size: 6
    Colour: "{0.2, 0.3, 0.6}"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "RMS " + fixed$(rms_out, 4)

    # ========================================================================
    # Control channel 1: Motion Energy  (orange-red)
    # ========================================================================
    Select outer viewport: 0, 8, 2.6, 4.2
    Select inner viewport: 0.7, 7.7, 2.68, 4.12

    Axes: 0, ctrlDur, 0, 1
    Paint rectangle: "{0.99, 0.96, 0.93}", 0, ctrlDur, 0, 1

    # Grid
    Colour: "{0.88, 0.88, 0.88}"
    Line width: 1
    Draw line: 0, 0.25, ctrlDur, 0.25
    Draw line: 0, 0.50, ctrlDur, 0.50
    Draw line: 0, 0.75, ctrlDur, 0.75

    # Curve
    Colour: "{0.82, 0.28, 0.07}"
    Line width: 2.5
    for i from 2 to nCtrlEff
        iPrev = i - 1
        Draw line: ctrl_t_'iPrev', ctrl_e_'iPrev',
         ... ctrl_t_'i', ctrl_e_'i'
    endfor

    Line width: 1
    Colour: "Black"
    Draw inner box
    Marks left every: 0.5, 1, "yes", "yes", "no"
    Marks bottom every: 2, 1, "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "Energy"
    Colour: "{0.55, 0.12, 0.02}"
    Text: ctrlDur * 0.02, "left", 0.90, "half",
     ... "Motion energy  ->  Amplitude  [" + fixed$(amplitude_min, 2)
     ... + " .. " + fixed$(amplitude_max, 2) + "]"

    # ========================================================================
    # Control channel 2: Vertical Position  (blue)
    # ========================================================================
    Select outer viewport: 0, 8, 4.2, 5.8
    Select inner viewport: 0.7, 7.7, 4.28, 5.72

    Axes: 0, ctrlDur, 0, 1
    Paint rectangle: "{0.93, 0.95, 0.99}", 0, ctrlDur, 0, 1

    # Grid
    Colour: "{0.88, 0.88, 0.88}"
    Line width: 1
    Draw line: 0, 0.25, ctrlDur, 0.25
    Draw line: 0, 0.75, ctrlDur, 0.75

    # Centre reference (no-shift line at 0.5)
    Colour: "{0.70, 0.75, 0.95}"
    Dotted line
    Draw line: 0, 0.5, ctrlDur, 0.5
    Solid line

    # Curve
    Colour: "{0.15, 0.28, 0.85}"
    Line width: 2.5
    for i from 2 to nCtrlEff
        iPrev = i - 1
        Draw line: ctrl_t_'iPrev', ctrl_v_'iPrev',
         ... ctrl_t_'i', ctrl_v_'i'
    endfor

    Line width: 1
    Colour: "Black"
    Draw inner box
    Marks left every: 0.5, 1, "yes", "yes", "no"
    Marks bottom every: 2, 1, "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "V-pos"
    Colour: "{0.08, 0.15, 0.60}"
    Text: ctrlDur * 0.02, "left", 0.90, "half",
     ... "Vertical position  ->  Pitch  +/-" + fixed$(pitch_range_st, 1)
     ... + " st  (0.5 = no shift)"

    # ========================================================================
    # Control channel 3: Horizontal Position  (green)
    # ========================================================================
    Select outer viewport: 0, 8, 5.8, 7.4
    Select inner viewport: 0.7, 7.7, 5.88, 7.32

    Axes: 0, ctrlDur, 0, 1
    Paint rectangle: "{0.93, 0.99, 0.94}", 0, ctrlDur, 0, 1

    # Grid
    Colour: "{0.88, 0.88, 0.88}"
    Line width: 1
    Draw line: 0, 0.25, ctrlDur, 0.25
    Draw line: 0, 0.75, ctrlDur, 0.75

    # Centre reference (neutral brightness at 0.5)
    Colour: "{0.72, 0.92, 0.74}"
    Dotted line
    Draw line: 0, 0.5, ctrlDur, 0.5
    Solid line

    # Curve
    Colour: "{0.10, 0.60, 0.25}"
    Line width: 2.5
    for i from 2 to nCtrlEff
        iPrev = i - 1
        Draw line: ctrl_t_'iPrev', ctrl_h_'iPrev',
         ... ctrl_t_'i', ctrl_h_'i'
    endfor

    Line width: 1
    Colour: "Black"
    Draw inner box
    Marks left every: 0.5, 1, "yes", "yes", "no"
    Marks bottom every: 2, 1, "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "H-pos"
    Text bottom: "yes", "Time (s)"
    Colour: "{0.04, 0.38, 0.12}"
    Text: ctrlDur * 0.02, "left", 0.90, "half",
     ... "Horizontal position  ->  Brightness  range " + fixed$(brightness_range, 2)
     ... + "  (0.5 = neutral)"

    # ========================================================================
    # Stats / Summary panel
    # ========================================================================
    Select outer viewport: 0, 8, 7.4, 8.0
    Select inner viewport: 0.7, 7.7, 7.44, 7.94

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1

    Font size: 8
    Colour: "Black"
    Text: 0.02, "left", 0.88, "half", "Summary:"

    Font size: 6.5
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.02, "left", 0.65, "half",
     ... "Preset: " + presetName$
     ... + "  |  Sound: " + soundName$
     ... + "  |  Duration: " + fixed$(dur, 2) + " s"
    Text: 0.02, "left", 0.45, "half",
     ... "Camera fps: " + py_cam_fps$
     ... + "  |  Raw frames: " + py_n_raw$
     ... + "  |  Ctrl frames: " + string$(nCtrl)
     ... + "  |  Tracking: " + py_tracking_conf$
    Text: 0.02, "left", 0.25, "half",
     ... "Amplitude [" + fixed$(amplitude_min, 2) + ".." + fixed$(amplitude_max, 2) + "]"
     ... + "  |  Pitch +/-" + fixed$(pitch_range_st, 1) + " st"
     ... + "  |  Brightness " + fixed$(brightness_range, 2)
     ... + "  |  Smooth " + string$(smooth_frames) + " fr"

    if py_warnings$ <> "?" and py_warnings$ <> "none"
        Colour: "{0.80, 0.18, 0.18}"
        Text: 0.02, "left", 0.05, "half", "Warning: " + py_warnings$
    endif

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
endif

# ===========================================================================
# Cleanup
# ===========================================================================
@cleanUpTempFiles

# ===========================================================================
# Final Summary
# ===========================================================================
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: ", soundName$, "_motion"
appendInfoLine: ""
appendInfoLine: "Motion capture:"
appendInfoLine: "  Camera fps:          ", py_cam_fps$
appendInfoLine: "  Raw frames:          ", py_n_raw$
appendInfoLine: "  Control frames:      ", nCtrl
appendInfoLine: "  Tracking confidence: ", py_tracking_conf$
if py_warnings$ <> "?" and py_warnings$ <> "none"
    appendInfoLine: "  WARNING: ", py_warnings$
endif
appendInfoLine: ""
appendInfoLine: "Transformations applied:"
appendInfoLine: "  Amplitude   : energy -> [", fixed$(amplitude_min, 2),
 ... " .. ", fixed$(amplitude_max, 2), "]"
appendInfoLine: "  Pitch       : vertical pos -> +/-", fixed$(pitch_range_st, 1),
 ... " semitones"
appendInfoLine: "  Brightness  : horizontal pos -> HPF modulation range ",
 ... fixed$(brightness_range, 2)
appendInfoLine: ""
appendInfoLine: "Duration : ", fixed$(dur, 2), " s"
appendInfoLine: "RMS      : ", fixed$(rms_orig, 4), " -> ", fixed$(rms_out, 4)

selectObject: resultSound

if play_result
    Play
endif

# ===========================================================================
# Procedures
# ===========================================================================

# parseStatLine: search for key$ in text$, return everything after it
# until the next newline.  Returns "?" if the key is not found.
procedure parseStatLine: .text$, .key$
    .result$ = "?"
    .pos = index(.text$, .key$)
    if .pos > 0
        .start = .pos + length(.key$)
        .rest$ = mid$(.text$, .start, length(.text$) - .start + 1)
        .nlPos = index(.rest$, newline$)
        if .nlPos > 0
            .result$ = left$(.rest$, .nlPos - 1)
        else
            .result$ = .rest$
        endif
    endif
endproc
