# ============================================================
# Praat AudioTools - MotionControl.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Motion Control: gesture-to-sound mapping with optional live preview.
#
#   The Python worker opens the webcam, calibrates a background model, captures
#   motion, and derives normalized gesture sources: energy, vertical/horizontal
#   position, speed, stillness, radius from centre, and acceleration. Four
#   user-editable mapping slots route those sources to amplitude, pitch,
#   spectral brightness, or equal-power stereo pan.
#
#   Python uses one shared mapping graph for live preview and offline render.
#   Live source normalization is causal; offline normalization is take-relative,
#   so live audio is a responsive rehearsal monitor rather than a sample-exact
#   preview. The final pitch stage moves only original PitchTier points, so
#   unvoiced material stays unvoiced. A failed camera capture bypasses transform.
#
#   Python dependencies:
#     numpy, opencv-python
#     Optional live audio: sounddevice
#     Install:  pip install numpy opencv-python sounddevice
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

# Praat 7 introduced full-trust checks for filesystem/system access. Praat 6.x
# does not know askForTrust(), so never parse/call it there.
if praatVersion >= 7000
    askForTrust()
endif

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
tempLiveWav$ = temporaryDirectory$ + "/temp_motctrl_live.wav"

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
    if fileReadable(tempLiveWav$)
        deleteFile: tempLiveWav$
    endif
endproc

@cleanUpTempFiles

# ===========================================================================
# FORM
# ===========================================================================
form Motion Control v1.4
    optionmenu Performance_character: 2
        option Subtle
        option Expressive
        option Spatial
        option Spectral
        option Kinetic
        option Wild
        option Meditative
        option Custom
    boolean Live_audio_during_capture 1
    optionmenu Live_response: 2
        option Direct
        option Smooth
    boolean Edit_mappings 0
    boolean Edit_details 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Mapping source codes:
# 1 Energy | 2 Vertical | 3 Horizontal | 4 Speed | 5 Stillness
# 6 Radius | 7 Acceleration | 8 None
# Destination codes:
# 1 Amplitude | 2 Pitch | 3 Brightness | 4 Stereo pan | 5 None

# ---- MUSICAL DEFAULTS ----
pitch_span_st    = 12.0
brightness_span  = 1.0
brightness_cutoff_hz = 2000.0
smooth_frames    = 5
control_fps      = 25
show_preview     = 1
live_volume      = 0.80

# Default mapping = Expressive
map_source_1 = 1
map_dest_1   = 1
map_amount_1 = 0.80
map_invert_1 = 0
map_source_2 = 2
map_dest_2   = 2
map_amount_2 = 0.50
map_invert_2 = 0
map_source_3 = 3
map_dest_3   = 3
map_amount_3 = 0.80
map_invert_3 = 0
map_source_4 = 3
map_dest_4   = 4
map_amount_4 = 1.00
map_invert_4 = 0

if performance_character = 1
    map_source_1 = 1
    map_dest_1 = 1
    map_amount_1 = 0.50
    map_source_2 = 2
    map_dest_2 = 2
    map_amount_2 = 0.25
    map_source_3 = 3
    map_dest_3 = 3
    map_amount_3 = 0.40
    map_source_4 = 3
    map_dest_4 = 4
    map_amount_4 = 0.45
    smooth_frames = 9
    presetName$ = "Subtle"
elsif performance_character = 2
    presetName$ = "Expressive"
elsif performance_character = 3
    map_source_1 = 3
    map_dest_1 = 4
    map_amount_1 = 1.00
    map_source_2 = 6
    map_dest_2 = 1
    map_amount_2 = 0.45
    map_source_3 = 2
    map_dest_3 = 3
    map_amount_3 = 0.35
    map_source_4 = 4
    map_dest_4 = 2
    map_amount_4 = 0.25
    smooth_frames = 5
    presetName$ = "Spatial"
elsif performance_character = 4
    map_source_1 = 3
    map_dest_1 = 3
    map_amount_1 = 0.80
    map_source_2 = 2
    map_dest_2 = 2
    map_amount_2 = 0.35
    map_source_3 = 1
    map_dest_3 = 1
    map_amount_3 = 0.55
    map_source_4 = 6
    map_dest_4 = 3
    map_amount_4 = 0.35
    smooth_frames = 6
    presetName$ = "Spectral"
elsif performance_character = 5
    map_source_1 = 4
    map_dest_1 = 2
    map_amount_1 = 0.55
    map_source_2 = 7
    map_dest_2 = 3
    map_amount_2 = 0.90
    map_source_3 = 1
    map_dest_3 = 1
    map_amount_3 = 0.85
    map_source_4 = 3
    map_dest_4 = 4
    map_amount_4 = 0.80
    smooth_frames = 4
    presetName$ = "Kinetic"
elsif performance_character = 6
    map_source_1 = 1
    map_dest_1 = 1
    map_amount_1 = 0.92
    map_source_2 = 2
    map_dest_2 = 2
    map_amount_2 = 1.00
    map_source_3 = 3
    map_dest_3 = 3
    map_amount_3 = 1.20
    map_source_4 = 3
    map_dest_4 = 4
    map_amount_4 = 1.00
    smooth_frames = 3
    presetName$ = "Wild"
elsif performance_character = 7
    map_source_1 = 5
    map_dest_1 = 1
    map_amount_1 = 0.30
    map_source_2 = 2
    map_dest_2 = 2
    map_amount_2 = 0.15
    map_source_3 = 3
    map_dest_3 = 4
    map_amount_3 = 0.30
    map_source_4 = 6
    map_dest_4 = 3
    map_amount_4 = 0.20
    smooth_frames = 18
    control_fps = 15
    presetName$ = "Meditative"
else
    presetName$ = "Custom"
endif

# ---- MAPPING EDITOR ----
openMappings = edit_mappings
if performance_character = 8
    openMappings = 1
endif

if openMappings
    # Screen-safe editor: one mapping slot per page.  Pause fields write to
    # variables derived from their labels (source, destination, amount, invert),
    # so copy them explicitly into the persistent map_* variables after each page.

    beginPause: "Mapping 1/4 - Motion Control"
        comment: "Slot 1 | Source -> destination | amount 1.0 = full range"
        choice: "Source", map_source_1
            option: "Motion energy"
            option: "Vertical position"
            option: "Horizontal position"
            option: "Speed"
            option: "Stillness"
            option: "Radius from centre"
            option: "Acceleration"
            option: "None"
        choice: "Destination", map_dest_1
            option: "Amplitude"
            option: "Pitch"
            option: "Brightness"
            option: "Stereo pan"
            option: "None"
        real: "Amount", map_amount_1
        boolean: "Invert", map_invert_1
    clicked = endPause: "Cancel", "Next", 2
    if clicked = 1
        exitScript: "Cancelled."
    endif
    map_source_1 = source
    map_dest_1 = destination
    map_amount_1 = amount
    map_invert_1 = invert

    beginPause: "Mapping 2/4 - Motion Control"
        comment: "Slot 2 | Source -> destination"
        choice: "Source", map_source_2
            option: "Motion energy"
            option: "Vertical position"
            option: "Horizontal position"
            option: "Speed"
            option: "Stillness"
            option: "Radius from centre"
            option: "Acceleration"
            option: "None"
        choice: "Destination", map_dest_2
            option: "Amplitude"
            option: "Pitch"
            option: "Brightness"
            option: "Stereo pan"
            option: "None"
        real: "Amount", map_amount_2
        boolean: "Invert", map_invert_2
    clicked = endPause: "Cancel", "Next", 2
    if clicked = 1
        exitScript: "Cancelled."
    endif
    map_source_2 = source
    map_dest_2 = destination
    map_amount_2 = amount
    map_invert_2 = invert

    beginPause: "Mapping 3/4 - Motion Control"
        comment: "Slot 3 | Source -> destination"
        choice: "Source", map_source_3
            option: "Motion energy"
            option: "Vertical position"
            option: "Horizontal position"
            option: "Speed"
            option: "Stillness"
            option: "Radius from centre"
            option: "Acceleration"
            option: "None"
        choice: "Destination", map_dest_3
            option: "Amplitude"
            option: "Pitch"
            option: "Brightness"
            option: "Stereo pan"
            option: "None"
        real: "Amount", map_amount_3
        boolean: "Invert", map_invert_3
    clicked = endPause: "Cancel", "Next", 2
    if clicked = 1
        exitScript: "Cancelled."
    endif
    map_source_3 = source
    map_dest_3 = destination
    map_amount_3 = amount
    map_invert_3 = invert

    beginPause: "Mapping 4/4 - Motion Control"
        comment: "Slot 4 | Source -> destination | duplicate destinations combine"
        choice: "Source", map_source_4
            option: "Motion energy"
            option: "Vertical position"
            option: "Horizontal position"
            option: "Speed"
            option: "Stillness"
            option: "Radius from centre"
            option: "Acceleration"
            option: "None"
        choice: "Destination", map_dest_4
            option: "Amplitude"
            option: "Pitch"
            option: "Brightness"
            option: "Stereo pan"
            option: "None"
        real: "Amount", map_amount_4
        boolean: "Invert", map_invert_4
    clicked = endPause: "Cancel", "Continue", 2
    if clicked = 1
        exitScript: "Cancelled."
    endif
    map_source_4 = source
    map_dest_4 = destination
    map_amount_4 = amount
    map_invert_4 = invert
endif

# ---- DETAILS ----
if edit_details
    beginPause: "Details - Motion Control"
        comment: "Destination ranges"
        comment: "Amount 1.0 uses these full destination ranges."
        real: "Pitch_span_st", pitch_span_st
        real: "Brightness_span", brightness_span
        real: "Brightness cutoff hz", brightness_cutoff_hz
        comment: "Gesture response / capture"
        integer: "Smooth frames", smooth_frames
        integer: "Control fps", control_fps
        boolean: "Show preview", show_preview
        real: "Live volume", live_volume
    clicked = endPause: "Cancel", "Continue", 2
    if clicked = 1
        exitScript: "Cancelled."
    endif
endif

# ---- CLAMP ----
if pitch_span_st < 0
    pitch_span_st = 0
endif
if pitch_span_st > 24
    pitch_span_st = 24
endif
if brightness_span < 0
    brightness_span = 0
endif
if brightness_span > 2
    brightness_span = 2
endif
if brightness_cutoff_hz < 100
    brightness_cutoff_hz = 100
endif
if brightness_cutoff_hz > 12000
    brightness_cutoff_hz = 12000
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
if live_volume < 0
    live_volume = 0
endif
if live_volume > 1.5
    live_volume = 1.5
endif
for slot from 1 to 4
    if map_amount_'slot' < 0
        map_amount_'slot' = 0
    endif
    if map_amount_'slot' > 1.5
        map_amount_'slot' = 1.5
    endif
endfor

if live_response = 1
    liveResponseStr$ = "direct"
else
    liveResponseStr$ = "smooth"
endif

# ---- HUMAN-READABLE MAPPING NAMES + ACTIVE DESTINATIONS ----
ampActive = 0
pitchActive = 0
brightActive = 0
panActive = 0
for slot from 1 to 4
    srcCode = map_source_'slot'
    dstCode = map_dest_'slot'
    if srcCode = 1
        srcName$ = "Energy"
    elsif srcCode = 2
        srcName$ = "Vertical"
    elsif srcCode = 3
        srcName$ = "Horizontal"
    elsif srcCode = 4
        srcName$ = "Speed"
    elsif srcCode = 5
        srcName$ = "Stillness"
    elsif srcCode = 6
        srcName$ = "Radius"
    elsif srcCode = 7
        srcName$ = "Acceleration"
    else
        srcName$ = "None"
    endif
    if dstCode = 1
        dstName$ = "Amplitude"
        if map_amount_'slot' > 0 and srcCode <> 8
            ampActive = 1
        endif
    elsif dstCode = 2
        dstName$ = "Pitch"
        if map_amount_'slot' > 0 and srcCode <> 8
            pitchActive = 1
        endif
    elsif dstCode = 3
        dstName$ = "Brightness"
        if map_amount_'slot' > 0 and srcCode <> 8
            brightActive = 1
        endif
    elsif dstCode = 4
        dstName$ = "Pan"
        if map_amount_'slot' > 0 and srcCode <> 8
            panActive = 1
        endif
    else
        dstName$ = "None"
    endif
    mapSource_'slot'$ = srcName$
    mapDest_'slot'$ = dstName$
endfor

mapSpec$ = string$(map_source_1) + ":" + string$(map_dest_1) + ":" + fixed$(map_amount_1, 4) + ":" + string$(map_invert_1)
 ... + "," + string$(map_source_2) + ":" + string$(map_dest_2) + ":" + fixed$(map_amount_2, 4) + ":" + string$(map_invert_2)
 ... + "," + string$(map_source_3) + ":" + string$(map_dest_3) + ":" + fixed$(map_amount_3, 4) + ":" + string$(map_invert_3)
 ... + "," + string$(map_source_4) + ":" + string$(map_dest_4) + ":" + fixed$(map_amount_4, 4) + ":" + string$(map_invert_4)

# ---- ORIGINAL SOUND STATS ----
selectObject: sound
dur       = Get total duration
sr        = Get sampling frequency
nChannels = Get number of channels
rms_orig  = Get root-mean-square: 0, 0

# Webcam capture follows the Sound duration where practical. The Python worker
# supports 3..60 s; for shorter/longer sounds the captured gesture is mapped
# across the complete Sound duration below instead of truncating/freezing it.
capture_sec = dur
if capture_sec < 3
    capture_sec = 3
endif
if capture_sec > 60
    capture_sec = 60
endif

# ---- INFO HEADER ----
clearinfo
writeInfoLine:  "=== Motion Control v1.4 ==="
appendInfoLine: "Input:       ", soundName$
appendInfoLine: "Performance: ", presetName$
appendInfoLine: ""
appendInfoLine: "Mappings:"
for slot from 1 to 4
    if map_source_'slot' <> 8 and map_dest_'slot' <> 5 and map_amount_'slot' > 0
        invertMark$ = ""
        if map_invert_'slot'
            invertMark$ = " (inverted)"
        endif
        appendInfoLine: "  ", slot, ". ", mapSource_'slot'$, " -> ", mapDest_'slot'$,
         ... "  amount ", fixed$(map_amount_'slot', 2), invertMark$
    endif
endfor
appendInfoLine: ""
appendInfoLine: "Destination semantics: X/Y are bipolar; Energy/Speed/Stillness/Radius/Acceleration are unipolar."
appendInfoLine: "Pitch amount 1.0: X/Y +/-", fixed$(pitch_span_st, 1),
 ... " st | unipolar 0..+", fixed$(pitch_span_st, 1), " st"
appendInfoLine: "Brightness amount 1.0: X/Y +/-", fixed$(brightness_span, 2),
 ... " | unipolar 0..+", fixed$(brightness_span, 2), " | negative side limited to -1"
appendInfoLine: "Brightness HPF cutoff: ", fixed$(brightness_cutoff_hz, 0), " Hz | Amplitude mappings attenuate only (0..1)."
appendInfoLine: "Capture: ", fixed$(capture_sec, 2), " s mapped to ", fixed$(dur, 2), " s sound",
 ... "  |  Control fps: ", control_fps, "  |  Smooth frames: ", smooth_frames
if live_audio_during_capture
    appendInfoLine: "Live audio: ON  |  Response: ", liveResponseStr$,
     ... "  |  Volume: ", fixed$(live_volume, 2)
else
    appendInfoLine: "Live audio: OFF"
endif
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
appendInfoLine: "  |  Phase 2 (", fixed$(capture_sec, 1), " s) : move freely          |"
appendInfoLine: "  |                                          |"
appendInfoLine: "  |  A preview window will open if possible. |"
if live_audio_during_capture
    appendInfoLine: "  |  Live audio starts after calibration.    |"
endif
appendInfoLine: "  +------------------------------------------+"
appendInfoLine: ""

# Pause so the user can position themselves before capture begins
pause Position yourself in front of the webcam, then click Continue.
 ... Phase 1: hold still 2 s (calibration). Phase 2: move for the displayed capture duration.
 ... If Live audio is on, playback begins when Phase 2 starts.

# Prepare source audio for the optional live preview. This temporary WAV is
# playback-only; the final render still uses the selected Praat Sound object.
if live_audio_during_capture
    selectObject: sound
    Save as WAV file: tempLiveWav$
endif

# Build Python command. The legacy numerical positions are retained for
# compatibility; v1.3+ adds the shared mapping spec and destination ranges.
# Arguments after live_volume: mapping_spec pitch_span_st brightness_span brightness_cutoff_hz
pythonCall$ = pythonCmd$ + " """ + pythonScript$ + """"
    ... + " """ + tempControl$ + """"
    ... + " """ + tempStats$ + """"
    ... + " """ + tempDone$ + """"
    ... + " " + fixed$(capture_sec, 4)
    ... + " " + string$(control_fps)
    ... + " " + string$(smooth_frames)
    ... + " " + string$(show_preview)
    ... + " " + string$(live_audio_during_capture)
    ... + " """ + tempLiveWav$ + """"
    ... + " " + fixed$(pitch_span_st, 4)
    ... + " 0.0 1.0"
    ... + " " + fixed$(brightness_span, 4)
    ... + " " + liveResponseStr$
    ... + " " + fixed$(live_volume, 4)
    ... + " """ + mapSpec$ + """"
    ... + " " + fixed$(pitch_span_st, 4)
    ... + " " + fixed$(brightness_span, 4)
    ... + " " + fixed$(brightness_cutoff_hz, 2)

appendInfoLine: "  Launching: ", pythonCall$
runSystem_nocheck: pythonCall$

# Verify completion marker
if not fileReadable(tempDone$)
    @cleanUpTempFiles
    exitScript: "Python worker did not complete." + newline$
     ... + "Check that your webcam is available and try again."
endif

doneText$ = readFile$(tempDone$)
fallbackUsed = 0
if index(doneText$, "fallback") > 0
    fallbackUsed = 1
    appendInfoLine: "  NOTE: Webcam unavailable/capture failed — source will be copied unchanged."
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

# Load gesture sources plus mapped destination controls.
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
    .val$ = Get value: i, "speed"
    ctrl_speed_'i' = number(.val$)
    .val$ = Get value: i, "stillness"
    ctrl_still_'i' = number(.val$)
    .val$ = Get value: i, "radius"
    ctrl_radius_'i' = number(.val$)
    .val$ = Get value: i, "acceleration"
    ctrl_accel_'i' = number(.val$)
    .val$ = Get value: i, "amplitude_gain"
    ctrl_amp_'i' = number(.val$)
    .val$ = Get value: i, "pitch_shift_st"
    ctrl_pitch_'i' = number(.val$)
    .val$ = Get value: i, "brightness_control"
    ctrl_bright_'i' = max(-1, min(2, number(.val$)))
    .val$ = Get value: i, "pan"
    ctrl_pan_'i' = number(.val$)
endfor
removeObject: ctrlTable

# Map the complete captured gesture over the complete Sound duration. This is
# exactly ~1:1 for ordinary 3..60 s sounds; it also prevents short sounds from
# using only the start of a 3 s capture and long sounds from freezing after 60 s.
rawCtrlDur = ctrl_t_'nCtrl'
if rawCtrlDur > 0.000001
    ctrlTimeScale = dur / rawCtrlDur
else
    ctrlTimeScale = 1
endif
for i from 1 to nCtrl
    ctrl_t_'i' = ctrl_t_'i' * ctrlTimeScale
endfor

appendInfoLine: "  Loaded ", nCtrl, " control frames"
appendInfoLine: "  Capture timeline: ", fixed$(rawCtrlDur, 2), " s -> mapped to ", fixed$(dur, 2), " s"

# ---- Read stats file ----
py_dur$           = "?"
py_cam_fps$       = "?"
py_n_raw$         = "?"
py_n_ctrl$        = "?"
py_mean_motion$   = "?"
py_max_motion$    = "?"
py_tracking_conf$ = "?"
py_live_status$   = "off"
py_live_under$    = "0"
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
    @parseStatLine: statsText$, "live_audio_status="
    py_live_status$ = parseStatLine.result$
    @parseStatLine: statsText$, "live_audio_underflows="
    py_live_under$ = parseStatLine.result$
    @parseStatLine: statsText$, "warnings="
    py_warnings$ = parseStatLine.result$
endif

appendInfoLine: "  Camera fps: ", py_cam_fps$,
 ... "  |  Raw frames: ", py_n_raw$
appendInfoLine: "  Tracking confidence: ", py_tracking_conf$
if live_audio_during_capture
    appendInfoLine: "  Live audio:          ", py_live_status$,
     ... "  |  stream notices: ", py_live_under$
endif
if fallbackUsed
    appendInfoLine: "  Capture status:       FALLBACK / transform bypassed"
endif
if py_warnings$ <> "?" and py_warnings$ <> "none"
    appendInfoLine: "  WARNING: ", py_warnings$
endif

# ===========================================================================
# Stage 4 — Prepare Working Copy (mono processing; bypass on camera fallback)
# ===========================================================================
appendInfoLine: "[4/6] Applying transformations..."
nCtrlEff = nCtrl
workDur = dur

if fallbackUsed
    appendInfoLine: "  Bypass: no valid camera performance; source copied unchanged."
    selectObject: sound
    Copy: soundName$ + "_motion"
    resultSound = selected("Sound")
else
    selectObject: sound
    if nChannels > 1
        # Keep historical channel-1 behaviour in normal cases, but do not let a
        # nearly silent first channel erase a multichannel source. Fall back to
        # the strongest channel only when ch1 RMS is <10% of the strongest.
        Extract one channel: 1
        workSound = selected("Sound")
        selectObject: workSound
        ch1Rms = Get root-mean-square: 0, 0
        strongestRms = ch1Rms
        strongestCh = 1
        removeObject: workSound
        for ch from 2 to nChannels
            selectObject: sound
            Extract one channel: ch
            testCh = selected("Sound")
            testRms = Get root-mean-square: 0, 0
            if testRms > strongestRms
                strongestRms = testRms
                strongestCh = ch
            endif
            removeObject: testCh
        endfor
        if strongestRms > 0 and ch1Rms < 0.1 * strongestRms
            appendInfoLine: "  Multichannel: channel 1 nearly silent; using strongest channel ", strongestCh
        else
            strongestCh = 1
            appendInfoLine: "  Multichannel: using channel 1 (compatibility path)"
        endif
        selectObject: sound
        Extract one channel: strongestCh
        workSound = selected("Sound")
    else
        Copy: "motctrl_work"
        workSound = selected("Sound")
    endif

    # All control times are relative to 0; align the processing copy without
    # changing sample data so non-zero-xmin Sounds use the correct control time.
    selectObject: workSound
    Shift times to: "start time", 0
    workDur = Get total duration

# ===========================================================================
# Stage 4a — Mapped Pitch Contour (analysis sees the unmodulated source)
# ===========================================================================
# Only source PitchTier points are shifted, so unvoiced regions remain unvoiced.
# Pitch intentionally precedes amplitude: gesture ducking must not change the
# voicing decision made by To Manipulation.
if pitchActive and pitch_span_st > 0
    appendInfoLine: "  [4a] Pitch: mapped gesture control"
    selectObject: workSound
    noprogress To Manipulation: 0.01, 75, 600
    manip = selected("Manipulation")
    selectObject: manip
    Extract pitch tier
    origPitchTier = selected("PitchTier")
    selectObject: origPitchTier
    nOrigPitchPts = Get number of points

    if nOrigPitchPts < 1
        appendInfoLine: "       No voiced F0 points detected -> pitch stage bypassed."
        removeObject: manip, origPitchTier
        selectObject: workSound
        Rename: "motctrl_pitch_result"
        pitchTransformed = selected("Sound")
    else
        Create PitchTier: "motctrl_pitch_shifted", 0, workDur
        shiftedPitchTier = selected("PitchTier")
        ctrlIdx = 1
        for iPt from 1 to nOrigPitchPts
            selectObject: origPitchTier
            tPitch = Get time from index: iPt
            origF0 = Get value at index: iPt

            searchDone = 0
            while ctrlIdx < nCtrlEff and searchDone = 0
                nextCtrl = ctrlIdx + 1
                if ctrl_t_'nextCtrl' < tPitch
                    ctrlIdx = ctrlIdx + 1
                else
                    searchDone = 1
                endif
            endwhile

            if ctrlIdx < nCtrlEff
                nextCtrl = ctrlIdx + 1
                tA = ctrl_t_'ctrlIdx'
                tB = ctrl_t_'nextCtrl'
                pA = ctrl_pitch_'ctrlIdx'
                pB = ctrl_pitch_'nextCtrl'
                if tB > tA
                    frac = (tPitch - tA) / (tB - tA)
                    frac = max(0, min(1, frac))
                    semiShift = pA + frac * (pB - pA)
                else
                    semiShift = pA
                endif
            else
                semiShift = ctrl_pitch_'nCtrlEff'
            endif

            shiftedF0 = origF0 * (2 ^ (semiShift / 12.0))
            shiftedF0 = max(40, min(900, shiftedF0))
            selectObject: shiftedPitchTier
            Add point: tPitch, shiftedF0
        endfor

        selectObject: manip
        plusObject: shiftedPitchTier
        Replace pitch tier
        selectObject: manip
        noprogress Get resynthesis (overlap-add)
        pitchTransformed = selected("Sound")
        Rename: "motctrl_pitch_result"
        removeObject: manip, origPitchTier, shiftedPitchTier, workSound
    endif
else
    appendInfoLine: "  [4a] Pitch: bypassed (no mapping)"
    selectObject: workSound
    Rename: "motctrl_pitch_result"
    pitchTransformed = selected("Sound")
endif

# ===========================================================================
# Stage 4b — Mapped Amplitude Envelope (no hidden normalization)
# ===========================================================================
# Sound & AmplitudeTier: Multiply normalizes its output, so it cannot represent
# an absolute gain law. Build a low-rate envelope Sound whose sample centres
# coincide exactly with the control frames, then interpolate it in Formula.
if ampActive
    appendInfoLine: "  [4b] Amplitude: mapped gesture control (absolute gain)"
    envFs = (nCtrlEff - 1) / workDur
    envDt = 1 / envFs
    Create Sound from formula: "motctrl_amp_env", 1, -0.5 * envDt, workDur + 0.5 * envDt, envFs, "1"
    ampEnv = selected("Sound")
    for i from 1 to nCtrlEff
        selectObject: ampEnv
        Set value at sample number: 1, i, ctrl_amp_'i'
    endfor

    selectObject: pitchTransformed
    Copy: "motctrl_amp_result"
    ampTransformed = selected("Sound")
    ampEnvId = ampEnv
    Formula: "self * object(ampEnvId, x)"
    removeObject: ampEnv, pitchTransformed
else
    appendInfoLine: "  [4b] Amplitude: bypassed (no mapping)"
    selectObject: pitchTransformed
    Rename: "motctrl_amp_result"
    ampTransformed = selected("Sound")
endif

# ===========================================================================
# Stage 4c — Mapped Spectral Brightness (fixed-Hz high band)
# ===========================================================================
if brightActive and brightness_span > 0
    nyq = sr / 2.0
    hpfCutoff = min(brightness_cutoff_hz, nyq - 100.0)
    hpfCutoff = max(20.0, hpfCutoff)
    appendInfoLine: "  [4c] Brightness: mapped HPF contribution above ", fixed$(hpfCutoff, 0), " Hz"

    selectObject: ampTransformed
    noprogress Filter (pass Hann band): hpfCutoff, nyq - 1.0, 100.0
    hpfSound = selected("Sound")
    Rename: "motctrl_hpf"

    envFs = (nCtrlEff - 1) / workDur
    envDt = 1 / envFs
    Create Sound from formula: "motctrl_bright_env", 1, -0.5 * envDt, workDur + 0.5 * envDt, envFs, "0"
    brightEnv = selected("Sound")
    for i from 1 to nCtrlEff
        selectObject: brightEnv
        Set value at sample number: 1, i, max(-1, min(2, ctrl_bright_'i'))
    endfor

    selectObject: ampTransformed
    Copy: "motctrl_brightness_result"
    monoTransformed = selected("Sound")
    hpfId = hpfSound
    brightEnvId = brightEnv
    Formula: "self + object[hpfId, 1, col] * object(brightEnvId, x)"
    removeObject: hpfSound, brightEnv, ampTransformed
else
    appendInfoLine: "  [4c] Brightness: bypassed (no mapping)"
    selectObject: ampTransformed
    Rename: "motctrl_brightness_result"
    monoTransformed = selected("Sound")
endif

# ===========================================================================
# Stage 4d — Stereo Pan (equal-power, no per-channel normalization)
# ===========================================================================
if panActive
    appendInfoLine: "  [4d] Stereo pan: equal-power mapped gesture control"
    envFs = (nCtrlEff - 1) / workDur
    envDt = 1 / envFs
    Create Sound from formula: "motctrl_pan_env", 1, -0.5 * envDt, workDur + 0.5 * envDt, envFs, "0"
    panEnv = selected("Sound")
    for i from 1 to nCtrlEff
        selectObject: panEnv
        Set value at sample number: 1, i, max(-1, min(1, ctrl_pan_'i'))
    endfor

    selectObject: monoTransformed
    Copy: "motctrl_pan_left"
    panLeft = selected("Sound")
    panEnvId = panEnv
    Formula: "self * cos((object(panEnvId, x) + 1) * pi / 4)"

    selectObject: monoTransformed
    Copy: "motctrl_pan_right"
    panRight = selected("Sound")
    Formula: "self * sin((object(panEnvId, x) + 1) * pi / 4)"

    selectObject: panLeft
    plusObject: panRight
    resultSound = Combine to stereo
    Rename: soundName$ + "_motion"
    removeObject: panEnv, panLeft, panRight, monoTransformed
else
    appendInfoLine: "  [4d] Stereo pan: bypassed (no mapping)"
    selectObject: monoTransformed
    Rename: soundName$ + "_motion"
    resultSound = selected("Sound")
endif

# ---- Prevent clipping ----
selectObject: resultSound
peakAbs = Get absolute extremum: 0, 0, "None"
if peakAbs > 0.98
    Scale peak: 0.97
endif

appendInfoLine: "  Transformations complete."
endif

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

# Measured high-band proportion for brightness QC. This is level-normalized
# (HF RMS / full-band RMS), so amplitude mapping does not masquerade as brightness.
hfShapeOrig = 0
hfShapeOut = 0
if brightActive and brightness_span > 0 and not fallbackUsed
    nyq = sr / 2.0
    vizHpfCutoff = min(brightness_cutoff_hz, nyq - 100.0)
    vizHpfCutoff = max(20.0, vizHpfCutoff)
    selectObject: sound
    noprogress Filter (pass Hann band): vizHpfCutoff, nyq - 1.0, 100.0
    hfOrigSound = selected("Sound")
    hfOrigRms = Get root-mean-square: 0, 0
    removeObject: hfOrigSound
    selectObject: resultSound
    noprogress Filter (pass Hann band): vizHpfCutoff, nyq - 1.0, 100.0
    hfOutSound = selected("Sound")
    hfOutRms = Get root-mean-square: 0, 0
    removeObject: hfOutSound
    if rms_orig > 0
        hfShapeOrig = hfOrigRms / rms_orig
    endif
    if rms_out > 0
        hfShapeOut = hfOutRms / rms_out
    endif
    appendInfoLine: "  HF/full RMS shape: ", fixed$(hfShapeOrig, 3), " -> ", fixed$(hfShapeOut, 3),
     ... "  (above ", fixed$(vizHpfCutoff, 0), " Hz)"
endif

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

    # Picture-safe text: Praat markup interprets underscores and percent signs.
    soundNameViz$ = replace$(soundName$, "_", "\_ ", 0)
    warningsViz$ = replace$(py_warnings$, "%", " pct", 0)
    warningsViz$ = replace$(warningsViz$, "_", "\_ ", 0)

    # Shared relative-time waveform copies and one symmetric amplitude scale.
    selectObject: sound
    Copy: "motctrl_viz_input"
    vizInput = selected("Sound")
    Shift times to: "start time", 0
    inputPeakViz = Get absolute extremum: 0, 0, "None"
    selectObject: resultSound
    Copy: "motctrl_viz_output"
    vizOutput = selected("Sound")
    Shift times to: "start time", 0
    outputPeakViz = Get absolute extremum: 0, 0, "None"
    waveY = max(0.001, 1.05 * max(inputPeakViz, outputPeakViz))
    if waveY <= 0.25
        waveStep = 0.1
    elsif waveY <= 0.75
        waveStep = 0.25
    elsif waveY <= 1.5
        waveStep = 0.5
    else
        waveStep = 1.0
    endif
    if dur <= 5
        timeStep = 1
    elsif dur <= 20
        timeStep = 5
    elsif dur <= 60
        timeStep = 10
    else
        timeStep = 20
    endif

    # Title strip
    Select outer viewport: 0, 8, 0, 0.55
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", 0.76, "half", "##Motion Control##"
    Font size: 8
    Colour: "{0.4,0.4,0.5}"
    Text: 0.5, "centre", 0.30, "half", soundNameViz$ + " | " + presetName$ + " | gesture mapping -> sound"
    if fallbackUsed
        Font size: 7
        Colour: "{0.80,0.18,0.18}"
        Text: 0.5, "centre", 0.02, "half", "FALLBACK: source copied unchanged; control curves below were not applied"
    endif

    # Original waveform — same time and amplitude axes as output.
    Select outer viewport: 0, 8, 0.60, 1.38
    Select inner viewport: 0.6, 7.7, 0.65, 1.33
    selectObject: vizInput
    Colour: "{0.36,0.39,0.45}"
    Draw: 0, dur, -waveY, waveY, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Marks left every: 1, waveStep, "yes", "yes", "no"
    Marks bottom every: 1, timeStep, "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "Original"

    # Output waveform — shared axes make level differences visible.
    Select outer viewport: 0, 8, 1.38, 2.16
    Select inner viewport: 0.6, 7.7, 1.43, 2.11
    selectObject: vizOutput
    Colour: "{0.20,0.40,0.75}"
    Draw: 0, dur, -waveY, waveY, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Marks left every: 1, waveStep, "yes", "yes", "no"
    Marks bottom every: 1, timeStep, "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "Mapped output"
    Text bottom: "yes", "Time (s)"

    # Destination 1: amplitude gain (attenuation only, 0..1).
    Select outer viewport: 0, 8, 2.24, 3.25
    Select inner viewport: 0.6, 7.7, 2.31, 3.18
    Axes: 0, ctrlDur, 0, 1
    Paint rectangle: "{0.965,0.972,0.985}", 0, ctrlDur, 0, 1
    Colour: "{0.80,0.82,0.86}"
    Draw line: 0, 1, ctrlDur, 1
    Colour: "{0.28,0.54,0.52}"
    Line width: 2.2
    for i from 2 to nCtrlEff
        iPrev = i - 1
        Draw line: ctrl_t_'iPrev', ctrl_amp_'iPrev', ctrl_t_'i', ctrl_amp_'i'
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Marks left every: 1, 0.25, "yes", "yes", "no"
    Marks bottom every: 1, timeStep, "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "Amp gain"
    Text top: "no", "Mapped amplitude (1 = unity; attenuation only)"

    # Destination 2: pitch shift.
    maxPitchCtl = 0
    for i from 1 to nCtrlEff
        if abs(ctrl_pitch_'i') > maxPitchCtl
            maxPitchCtl = abs(ctrl_pitch_'i')
        endif
    endfor
    pitchY = max(1, maxPitchCtl * 1.15)
    if pitchY <= 3
        pitchStep = 1
    elsif pitchY <= 6
        pitchStep = 2
    elsif pitchY <= 12
        pitchStep = 4
    else
        pitchStep = 6
    endif
    Select outer viewport: 0, 8, 3.25, 4.26
    Select inner viewport: 0.6, 7.7, 3.32, 4.19
    Axes: 0, ctrlDur, -pitchY, pitchY
    Paint rectangle: "{0.955,0.968,0.988}", 0, ctrlDur, -pitchY, pitchY
    Colour: "{0.78,0.82,0.92}"
    Draw line: 0, 0, ctrlDur, 0
    Colour: "{0.20,0.40,0.75}"
    Line width: 2.2
    for i from 2 to nCtrlEff
        iPrev = i - 1
        Draw line: ctrl_t_'iPrev', ctrl_pitch_'iPrev', ctrl_t_'i', ctrl_pitch_'i'
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Marks left every: 1, pitchStep, "yes", "yes", "no"
    Marks bottom every: 1, timeStep, "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "Pitch st"
    Text top: "no", "Mapped pitch shift"

    # Destination 3: brightness control + measured spectral-shape consequence.
    maxBrightCtl = 0
    for i from 1 to nCtrlEff
        if abs(ctrl_bright_'i') > maxBrightCtl
            maxBrightCtl = abs(ctrl_bright_'i')
        endif
    endfor
    brightY = max(0.25, maxBrightCtl * 1.15)
    if brightY <= 0.5
        brightStep = 0.25
    elsif brightY <= 1
        brightStep = 0.5
    else
        brightStep = 1
    endif
    Select outer viewport: 0, 8, 4.26, 5.27
    Select inner viewport: 0.6, 7.7, 4.33, 5.20
    Axes: 0, ctrlDur, -brightY, brightY
    Paint rectangle: "{0.962,0.978,0.985}", 0, ctrlDur, -brightY, brightY
    Colour: "{0.78,0.84,0.88}"
    Draw line: 0, 0, ctrlDur, 0
    Colour: "{0.40,0.48,0.66}"
    Line width: 2.2
    for i from 2 to nCtrlEff
        iPrev = i - 1
        Draw line: ctrl_t_'iPrev', ctrl_bright_'iPrev', ctrl_t_'i', ctrl_bright_'i'
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Marks left every: 1, brightStep, "yes", "yes", "no"
    Marks bottom every: 1, timeStep, "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "Bright"
    if brightActive and not fallbackUsed
        Text top: "no", "HPF " + fixed$(brightness_cutoff_hz, 0) + " Hz | HF/full RMS " + fixed$(hfShapeOrig, 3) + " -> " + fixed$(hfShapeOut, 3)
    else
        Text top: "no", "Mapped spectral brightness (- darker / + brighter)"
    endif

    # Destination 4: stereo pan.
    Select outer viewport: 0, 8, 5.27, 6.28
    Select inner viewport: 0.6, 7.7, 5.34, 6.21
    Axes: 0, ctrlDur, -1, 1
    Paint rectangle: "{0.965,0.968,0.985}", 0, ctrlDur, -1, 1
    Colour: "{0.80,0.80,0.88}"
    Draw line: 0, 0, ctrlDur, 0
    Colour: "{0.50,0.40,0.68}"
    Line width: 2.2
    for i from 2 to nCtrlEff
        iPrev = i - 1
        Draw line: ctrl_t_'iPrev', ctrl_pan_'iPrev', ctrl_t_'i', ctrl_pan_'i'
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Marks left every: 1, 0.5, "yes", "yes", "no"
    Marks bottom every: 1, timeStep, "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "Pan"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Equal-power stereo position (-1 L / 0 C / +1 R)"

    # Mapping / QC summary.
    Select outer viewport: 0, 8, 6.38, 8.0
    Select inner viewport: 0.6, 7.7, 6.43, 7.94
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94,0.94,0.94}", 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.02, "left", 0.91, "half", "gesture sources -> mapping graph -> pitch -> amplitude -> brightness -> pan"
    Font size: 6.3
    Colour: "{0.30,0.30,0.34}"
    yMap = 0.72
    for slot from 1 to 4
        if map_source_'slot' <> 8 and map_dest_'slot' <> 5 and map_amount_'slot' > 0
            invText$ = ""
            if map_invert_'slot'
                invText$ = " inv"
            endif
            Text: 0.03, "left", yMap, "half", string$(slot) + ". " + mapSource_'slot'$ + " -> " + mapDest_'slot'$ + "  x" + fixed$(map_amount_'slot', 2) + invText$
            yMap = yMap - 0.15
        endif
    endfor
    Colour: "{0.38,0.42,0.52}"
    Text: 0.58, "left", 0.72, "half", "Tracking " + py_tracking_conf$ + " | Cam " + py_cam_fps$ + " fps | Ctrl " + string$(nCtrl)
    Text: 0.58, "left", 0.56, "half", "X/Y bipolar; dynamic sources unipolar | Bright floor -1"
    Text: 0.58, "left", 0.40, "half", "Capture " + fixed$(rawCtrlDur, 2) + " s -> sound " + fixed$(dur, 2) + " s | time scale x" + fixed$(ctrlTimeScale, 3)
    Text: 0.58, "left", 0.24, "half", "Brightness cutoff " + fixed$(brightness_cutoff_hz, 0) + " Hz | Amp 0..1"
    if live_audio_during_capture
        Text: 0.58, "left", 0.08, "half", "Live " + py_live_status$ + " | " + liveResponseStr$ + " | causal normalization"
    endif
    if py_warnings$ <> "?" and py_warnings$ <> "none"
        Colour: "{0.80,0.18,0.18}"
        Text: 0.03, "left", 0.05, "half", "Warning: " + warningsViz$
    endif
    Colour: "Black"
    # Text commands can leave the Picture state on the outer viewport.
    Select inner viewport: 0.6, 7.7, 6.43, 7.94
    Axes: 0, 1, 0, 1
    Draw inner box

    removeObject: vizInput, vizOutput
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
if live_audio_during_capture
    appendInfoLine: "  Live audio:          ", py_live_status$,
     ... "  |  response: ", liveResponseStr$,
     ... "  |  stream notices: ", py_live_under$
endif
if fallbackUsed
    appendInfoLine: "  Capture status:       FALLBACK / transform bypassed"
endif
if py_warnings$ <> "?" and py_warnings$ <> "none"
    appendInfoLine: "  WARNING: ", py_warnings$
endif
appendInfoLine: ""
appendInfoLine: "Mappings used:"
for slot from 1 to 4
    if map_source_'slot' <> 8 and map_dest_'slot' <> 5 and map_amount_'slot' > 0
        invText$ = ""
        if map_invert_'slot'
            invText$ = " (inverted)"
        endif
        appendInfoLine: "  ", slot, ". ", mapSource_'slot'$, " -> ", mapDest_'slot'$,
         ... "  amount ", fixed$(map_amount_'slot', 2), invText$
    endif
endfor
appendInfoLine: "  Pitch amount 1.0: X/Y +/-", fixed$(pitch_span_st, 1), " st; unipolar 0..+", fixed$(pitch_span_st, 1), " st"
appendInfoLine: "  Brightness amount 1.0: X/Y +/-", fixed$(brightness_span, 2), "; unipolar 0..+", fixed$(brightness_span, 2)
appendInfoLine: "  Brightness cutoff: ", fixed$(brightness_cutoff_hz, 0), " Hz; negative control limited to -1"
appendInfoLine: "  Pan law: equal-power stereo when a Pan mapping is active"
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
