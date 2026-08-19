# ============================================================
# Praat AudioTools - GranularFaceNavigator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Granular Face Navigator
# Facial gesture control of granular time, density and space.
#
# Architecture:
#   webcam -> MediaPipe Face Landmarker -> neutral calibration -> face sources
#   -> four mapping slots -> granular destination controls -> Python grain engine
#   -> live stereo preview + deterministic offline stereo render.
#
# Face sources:
#   Head yaw / pitch / roll / X / Y, jaw open, smile, pucker, brow raise,
#   proximity, expression energy. A deliberate eye hold is a discrete Freeze trigger.
#
# Granular destinations:
#   Position, grain size, density, pitch, pitch spread, spray,
#   stereo spread, amplitude, temporal onset jitter.
#
# Python dependencies:
#   numpy, opencv-python, soundfile, mediapipe
#   Optional live audio: sounddevice
#
# The MediaPipe Face Landmarker model is stored locally after a one-time
# user-approved download to the configured modelPath$ (user-local in this build).
# ============================================================

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif
sound = selected("Sound")
soundName$ = selected$("Sound")

# Praat 7 full-trust guard; Praat 6.x must never call/parse askForTrust().
if praatVersion >= 7000
    askForTrust()
endif

# ---- PYTHON DISCOVERY ----
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
pluginDir$ = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/granular_face_navigator.py"
modelPath$ = "C:/Users/User/face_landmarker.task"
usingPlugin = 1
if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/granular_face_navigator.py"
    modelPath$ = defaultDirectory$ + "/face_landmarker.task"
    usingPlugin = 0
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find granular_face_navigator.py" + newline$
     ... + "Expected in " + pluginDir$ + "py/ or next to this Praat script."
endif

# ---- TEMP FILES ----
tempInput$ = temporaryDirectory$ + "/temp_granface_input.wav"
tempOutput$ = temporaryDirectory$ + "/temp_granface_output.wav"
tempControl$ = temporaryDirectory$ + "/temp_granface_controls.csv"
tempTrace$ = temporaryDirectory$ + "/temp_granface_trace.tsv"
tempStats$ = temporaryDirectory$ + "/temp_granface_stats.txt"
tempDone$ = temporaryDirectory$ + "/temp_granface_done.ok"
tempProbe$ = temporaryDirectory$ + "/temp_granface_probe.ok"
tempProbeJ$ = replace_regex$(tempProbe$, "\\", "/", 0)

procedure cleanUpGranFaceTemp
    if fileReadable(tempInput$)
        deleteFile: tempInput$
    endif
    if fileReadable(tempOutput$)
        deleteFile: tempOutput$
    endif
    if fileReadable(tempControl$)
        deleteFile: tempControl$
    endif
    if fileReadable(tempTrace$)
        deleteFile: tempTrace$
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
@cleanUpGranFaceTemp

# ==========================================================================
# MAIN FORM
# ==========================================================================
form Granular Face Navigator v0.2
    optionmenu Performance_character: 1
        option Explore
        option Cloud
        option Vocal
        option Fragmented
        option Spatial
        option Wild
        option Custom
    optionmenu Position_behavior: 1
        option Navigate
        option Scrub
    optionmenu Response: 2
        option Direct
        option Smooth
    boolean Live_audio_during_capture 1
    boolean Render_saved_performance 0
    boolean Eye_hold_freeze 1
    boolean Edit_mappings 0
    boolean Edit_details 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Source codes:
# 1 Head yaw | 2 Head pitch | 3 Head roll | 4 Head X | 5 Head Y
# 6 Jaw | 7 Smile | 8 Pucker | 9 Brow | 10 Proximity | 11 Expression energy | 12 None
# Destination codes:
# 1 Position | 2 Grain size | 3 Density | 4 Pitch | 5 Pitch spread
# 6 Spray | 7 Stereo spread | 8 Amplitude | 9 Temporal jitter | 10 None

# ---- GRANULAR DEFAULTS ----
min_grain_ms = 20
max_grain_ms = 300
min_density = 4
max_density = 45
pitch_span_st = 12
pitch_spread_max_st = 10
max_spray_ms = 450
scrub_rate = 1.0
control_fps = 30
show_preview = 1
live_volume = 0.80
base_onset_jitter = 0.22
save_performance_csv = 0
performance_file$ = defaultDirectory$ + "/GranularFacePerformance.csv"
seed = 42

# Explore preset
map_source_1 = 1
map_dest_1 = 1
map_amount_1 = 1.00
map_invert_1 = 0
map_source_2 = 6
map_dest_2 = 3
map_amount_2 = 0.80
map_invert_2 = 0
map_source_3 = 2
map_dest_3 = 2
map_amount_3 = 0.60
map_invert_3 = 0
map_source_4 = 7
map_dest_4 = 7
map_amount_4 = 0.80
map_invert_4 = 0
presetName$ = "Explore"

if performance_character = 2
    # Cloud: navigation + expression-driven diffusion in time/space.
    map_source_1 = 1
    map_dest_1 = 1
    map_amount_1 = 0.90
    map_source_2 = 6
    map_dest_2 = 3
    map_amount_2 = 0.55
    map_source_3 = 11
    map_dest_3 = 6
    map_amount_3 = 0.95
    map_source_4 = 7
    map_dest_4 = 7
    map_amount_4 = 0.95
    presetName$ = "Cloud"
elsif performance_character = 3
    # Vocal: mouth shape controls time/pitch dimensions.
    map_source_1 = 8
    map_dest_1 = 4
    map_amount_1 = 0.80
    map_source_2 = 6
    map_dest_2 = 2
    map_amount_2 = 0.80
    map_source_3 = 9
    map_dest_3 = 5
    map_amount_3 = 0.65
    map_source_4 = 1
    map_dest_4 = 1
    map_amount_4 = 0.75
    presetName$ = "Vocal"
elsif performance_character = 4
    # Fragmented: more expression -> shorter grains; blink freeze is especially useful.
    map_source_1 = 1
    map_dest_1 = 1
    map_amount_1 = 1.00
    map_source_2 = 6
    map_dest_2 = 3
    map_amount_2 = 1.00
    map_source_3 = 11
    map_dest_3 = 2
    map_amount_3 = 1.00
    map_invert_3 = 1
    map_source_4 = 2
    map_dest_4 = 6
    map_amount_4 = 0.65
    presetName$ = "Fragmented"
elsif performance_character = 5
    # Spatial: head and smile organize spectral/time cloud in stereo.
    map_source_1 = 1
    map_dest_1 = 1
    map_amount_1 = 0.75
    map_source_2 = 7
    map_dest_2 = 7
    map_amount_2 = 1.00
    map_source_3 = 2
    map_dest_3 = 4
    map_amount_3 = 0.40
    map_source_4 = 10
    map_dest_4 = 6
    map_amount_4 = 0.65
    presetName$ = "Spatial"
elsif performance_character = 6
    map_source_1 = 1
    map_dest_1 = 1
    map_amount_1 = 1.00
    map_source_2 = 6
    map_dest_2 = 3
    map_amount_2 = 1.20
    map_source_3 = 8
    map_dest_3 = 4
    map_amount_3 = 1.00
    map_source_4 = 11
    map_dest_4 = 5
    map_amount_4 = 1.20
    presetName$ = "Wild"
elsif performance_character = 7
    presetName$ = "Custom"
endif

# ---- SCREEN-SAFE MAPPING EDITOR ----
openMappings = edit_mappings
if performance_character = 7
    openMappings = 1
endif
if openMappings
    mappingEditorDone = 0
    while mappingEditorDone = 0
        beginPause: "Edit mappings - Granular Face"
            comment: "Choose one slot to edit. Finish keeps the current four-slot graph."
            choice: "Slot to edit", 1
                option: "Slot 1"
                option: "Slot 2"
                option: "Slot 3"
                option: "Slot 4"
                option: "Finish"
        clicked = endPause: "Cancel", "Continue", 2
        if clicked = 1
            exitScript: "Cancelled."
        endif
        if slot_to_edit = 5
            mappingEditorDone = 1
        else
            slot = slot_to_edit
            currentSource = map_source_'slot'
            currentDest = map_dest_'slot'
            currentAmount = map_amount_'slot'
            currentInvert = map_invert_'slot'

            beginPause: "Source - Mapping " + string$(slot)
                comment: "Head pose/position sources are bipolar around calibrated neutral."
                comment: "Expressions + proximity are unipolar: neutral 0 -> expressive/close 1."
                choice: "Source", currentSource
                    option: "Head yaw"
                    option: "Head pitch"
                    option: "Head roll"
                    option: "Head X position"
                    option: "Head Y position"
                    option: "Jaw open"
                    option: "Smile"
                    option: "Mouth pucker"
                    option: "Brow raise"
                    option: "Face proximity"
                    option: "Expression energy"
                    option: "None"
            clicked = endPause: "Cancel", "Next", 2
            if clicked = 1
                exitScript: "Cancelled."
            endif
            map_source_'slot' = source

            beginPause: "Destination - Mapping " + string$(slot)
                choice: "Destination", currentDest
                    option: "Source position"
                    option: "Grain size"
                    option: "Density"
                    option: "Pitch"
                    option: "Pitch spread"
                    option: "Spray"
                    option: "Stereo spread"
                    option: "Amplitude"
                    option: "Temporal jitter"
                    option: "None"
                real: "Amount", currentAmount
                boolean: "Invert", currentInvert
            clicked = endPause: "Cancel", "Apply", 2
            if clicked = 1
                exitScript: "Cancelled."
            endif
            map_dest_'slot' = destination
            map_amount_'slot' = amount
            map_invert_'slot' = invert
        endif
    endwhile
endif

# ---- DETAILS: two short pages ----
if edit_details
    beginPause: "Granular ranges 1/2 - Granular Face"
        positive: "Min grain ms", min_grain_ms
        positive: "Max grain ms", max_grain_ms
        positive: "Min density", min_density
        positive: "Max density", max_density
        real: "Pitch span st", pitch_span_st
        real: "Pitch spread max st", pitch_spread_max_st
        real: "Max spray ms", max_spray_ms
    clicked = endPause: "Cancel", "Next", 2
    if clicked = 1
        exitScript: "Cancelled."
    endif

    beginPause: "Performance 2/2 - Granular Face"
        real: "Scrub rate", scrub_rate
        integer: "Control fps", control_fps
        boolean: "Show preview", show_preview
        real: "Live volume", live_volume
        real: "Base onset jitter", base_onset_jitter
        boolean: "Save performance CSV", save_performance_csv
        sentence: "Performance save file", performance_file$
        integer: "Seed", seed
    clicked = endPause: "Cancel", "Continue", 2
    if clicked = 1
        exitScript: "Cancelled."
    endif
endif

if render_saved_performance
    beginPause: "Re-render saved facial performance"
        comment: "Use a Granular Face performance CSV saved from an earlier take."
        sentence: "Saved performance file", performance_file$
    clicked = endPause: "Cancel", "Continue", 2
    if clicked = 1
        exitScript: "Cancelled."
    endif
    performance_file$ = saved_performance_file$
    if not fileReadable(performance_file$)
        exitScript: "Cannot read saved performance CSV: " + performance_file$
    endif
endif

# ---- CLAMP DETAILS / MAPPING AMOUNTS ----
min_grain_ms = max(5, min(1000, min_grain_ms))
max_grain_ms = max(min_grain_ms, min(2000, max_grain_ms))
min_density = max(0.5, min(200, min_density))
max_density = max(min_density, min(300, max_density))
pitch_span_st = max(0, min(36, pitch_span_st))
pitch_spread_max_st = max(0, min(24, pitch_spread_max_st))
max_spray_ms = max(0, min(3000, max_spray_ms))
scrub_rate = max(0.05, min(4, scrub_rate))
control_fps = max(10, min(60, control_fps))
live_volume = max(0, min(1.5, live_volume))
base_onset_jitter = max(0, min(0.95, base_onset_jitter))
for slot from 1 to 4
    map_amount_'slot' = max(0, min(1.5, map_amount_'slot'))
endfor

if position_behavior = 1
    positionMode$ = "navigate"
    positionLabel$ = "Navigate (absolute read position)"
else
    positionMode$ = "scrub"
    positionLabel$ = "Scrub (head control becomes read velocity)"
endif
if response = 1
    responseStr$ = "direct"
else
    responseStr$ = "smooth"
endif

# ---- HUMAN-READABLE MAPPING NAMES ----
for slot from 1 to 4
    srcCode = map_source_'slot'
    dstCode = map_dest_'slot'
    if srcCode = 1
        srcName$ = "Head yaw"
    elsif srcCode = 2
        srcName$ = "Head pitch"
    elsif srcCode = 3
        srcName$ = "Head roll"
    elsif srcCode = 4
        srcName$ = "Head X"
    elsif srcCode = 5
        srcName$ = "Head Y"
    elsif srcCode = 6
        srcName$ = "Jaw"
    elsif srcCode = 7
        srcName$ = "Smile"
    elsif srcCode = 8
        srcName$ = "Pucker"
    elsif srcCode = 9
        srcName$ = "Brow"
    elsif srcCode = 10
        srcName$ = "Proximity"
    elsif srcCode = 11
        srcName$ = "Expression energy"
    else
        srcName$ = "None"
    endif

    if dstCode = 1
        dstName$ = "Position"
    elsif dstCode = 2
        dstName$ = "Grain size"
    elsif dstCode = 3
        dstName$ = "Density"
    elsif dstCode = 4
        dstName$ = "Pitch"
    elsif dstCode = 5
        dstName$ = "Pitch spread"
    elsif dstCode = 6
        dstName$ = "Spray"
    elsif dstCode = 7
        dstName$ = "Stereo spread"
    elsif dstCode = 8
        dstName$ = "Amplitude"
    elsif dstCode = 9
        dstName$ = "Temporal jitter"
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

# ---- INPUT SOUND ----
selectObject: sound
dur = Get total duration
sr = Get sampling frequency
nChannels = Get number of channels
rms_orig = Get root-mean-square: 0, 0
capture_sec = max(3, min(60, dur))

# ---- INFO ----
clearinfo
writeInfoLine: "=== Granular Face Navigator v0.2 ==="
appendInfoLine: "Input:       ", soundName$
appendInfoLine: "Character:   ", presetName$
appendInfoLine: "Position:    ", positionLabel$
if eye_hold_freeze
    blinkText$ = "ON"
else
    blinkText$ = "off"
endif
appendInfoLine: "Eye-hold freeze: ", blinkText$ + " (hold eyes closed ~0.34 s)"
appendInfoLine: ""
appendInfoLine: "Mappings:"
for slot from 1 to 4
    if map_source_'slot' <> 12 and map_dest_'slot' <> 10 and map_amount_'slot' > 0
        invText$ = ""
        if map_invert_'slot'
            invText$ = " (inverted)"
        endif
        appendInfoLine: "  ", slot, ". ", mapSource_'slot'$, " -> ", mapDest_'slot'$,
         ... "  amount ", fixed$(map_amount_'slot', 2), invText$
    endif
endfor
appendInfoLine: ""
appendInfoLine: "Head pose/position are bipolar around calibration; expressions and proximity are unipolar."
appendInfoLine: "Grain range: ", fixed$(min_grain_ms, 0), "..", fixed$(max_grain_ms, 0), " ms",
 ... " | Density: ", fixed$(min_density, 1), "..", fixed$(max_density, 1), " grains/s"
appendInfoLine: "Pitch span +/-", fixed$(pitch_span_st, 1), " st | Pitch spread max +/-",
 ... fixed$(pitch_spread_max_st, 1), " st | Spray max ", fixed$(max_spray_ms, 0), " ms"
appendInfoLine: "Base temporal jitter: ", fixed$(base_onset_jitter, 2), " of grain interval | Density mapping: logarithmic"
if render_saved_performance
    appendInfoLine: "Mode: re-render saved facial performance -> ", performance_file$
else
    appendInfoLine: "Capture: ", fixed$(capture_sec, 2), " s -> render duration ", fixed$(dur, 2), " s"
endif
appendInfoLine: ""

# ==========================================================================
# DEPENDENCIES + FIRST-RUN MODEL
# ==========================================================================
appendInfoLine: "[1/5] Checking Python / MediaPipe..."
if render_saved_performance
    probeCmd$ = pythonCmd$ + " -c ""import numpy,soundfile;open('""" + tempProbeJ$ + """','w').write('ok')"""
else
    probeCmd$ = pythonCmd$ + " -c ""import numpy,cv2,soundfile,mediapipe;open('""" + tempProbeJ$ + """','w').write('ok')"""
endif
runSystem_nocheck: probeCmd$
if not fileReadable(tempProbe$)
    @cleanUpGranFaceTemp
    if render_saved_performance
        exitScript: "Re-render requires Python packages numpy and soundfile."
    else
        exitScript: "Granular Face Navigator requires Python packages:" + newline$
         ... + "numpy opencv-python soundfile mediapipe" + newline$
         ... + "Install with:" + newline$
         ... + "python -m pip install numpy opencv-python soundfile mediapipe" + newline$
         ... + "Optional live audio: python -m pip install sounddevice"
    endif
endif
deleteFile: tempProbe$
appendInfoLine: "  Python + required packages: OK"

if not render_saved_performance and not fileReadable(modelPath$)
    beginPause: "First run - Granular Face Navigator"
        comment: "The MediaPipe Face Landmarker model is not installed locally."
        comment: "Download it once from Google's MediaPipe model storage?"
        comment: "It will be stored at:"
        comment: modelPath$
    clicked = endPause: "Cancel", "Download model", 2
    if clicked = 1
        @cleanUpGranFaceTemp
        exitScript: "Face model download cancelled."
    endif
    downloadCmd$ = pythonCmd$ + " """ + pythonScript$ + """ --download-model-only """ + modelPath$ + """"
    runSystem_nocheck: downloadCmd$
    if not fileReadable(modelPath$)
        @cleanUpGranFaceTemp
        exitScript: "Could not download Face Landmarker model." + newline$
         ... + "Check internet access and try again."
    endif
endif
if render_saved_performance
    appendInfoLine: "  Vision model: not needed for saved-performance re-render"
else
    appendInfoLine: "  Face model: ", modelPath$
endif

# ==========================================================================
# CAPTURE + RENDER
# ==========================================================================
appendInfoLine: "[2/5] Preparing source + face performance..."
selectObject: sound
Save as WAV file: tempInput$

if not render_saved_performance
    pause Position yourself in front of the webcam, then click Continue.
     ... First hold a neutral face for 2 seconds. Then perform with the face.
     ... Hold the eyes closed for about 0.34 s to toggle Freeze.
     ... If Live audio is enabled, the granular preview starts after calibration.
else
    appendInfoLine: "  Re-rendering saved face performance; camera is not opened."
endif

pythonCall$ = pythonCmd$ + " """ + pythonScript$ + """"
 ... + " --input """ + tempInput$ + """"
 ... + " --output """ + tempOutput$ + """"
 ... + " --controls """ + tempControl$ + """"
 ... + " --trace """ + tempTrace$ + """"
if render_saved_performance
    pythonCall$ = pythonCall$ + " --render-controls """ + performance_file$ + """"
endif
pythonCall$ = pythonCall$ + " --stats """ + tempStats$ + """"
 ... + " --done """ + tempDone$ + """"
 ... + " --model """ + modelPath$ + """"
 ... + " --capture-sec " + fixed$(capture_sec, 4)
 ... + " --control-fps " + string$(control_fps)
 ... + " --show-preview " + string$(show_preview)
 ... + " --live-audio " + string$(live_audio_during_capture)
 ... + " --live-volume " + fixed$(live_volume, 4)
 ... + " --response " + responseStr$
 ... + " --position-mode " + positionMode$
 ... + " --blink-freeze " + string$(eye_hold_freeze)
 ... + " --mapping-spec """ + mapSpec$ + """"
 ... + " --min-grain-ms " + fixed$(min_grain_ms, 3)
 ... + " --max-grain-ms " + fixed$(max_grain_ms, 3)
 ... + " --min-density " + fixed$(min_density, 3)
 ... + " --max-density " + fixed$(max_density, 3)
 ... + " --pitch-span-st " + fixed$(pitch_span_st, 3)
 ... + " --pitch-spread-max-st " + fixed$(pitch_spread_max_st, 3)
 ... + " --max-spray-ms " + fixed$(max_spray_ms, 3)
 ... + " --scrub-rate " + fixed$(scrub_rate, 4)
 ... + " --base-onset-jitter " + fixed$(base_onset_jitter, 4)
 ... + " --seed " + string$(seed)

runSystem_nocheck: pythonCall$
if not fileReadable(tempDone$)
    @cleanUpGranFaceTemp
    exitScript: "Granular Face worker did not complete."
endif
if not fileReadable(tempOutput$)
    @cleanUpGranFaceTemp
    exitScript: "Granular Face output WAV was not created."
endif

doneText$ = readFile$(tempDone$)
fallbackUsed = 0
if index(doneText$, "fallback") > 0
    fallbackUsed = 1
    appendInfoLine: "  FALLBACK: face tracking failed; source copied unchanged."
else
    appendInfoLine: "  Face performance captured and granular render complete."
endif

# Read the rendered stereo output.
Read from file: tempOutput$
resultSound = selected("Sound")
Rename: soundName$ + "_granface"
rms_out = Get root-mean-square: 0, 0

# ==========================================================================
# CONTROL CSV
# ==========================================================================
appendInfoLine: "[3/5] Reading granular control timeline..."
if not fileReadable(tempControl$)
    removeObject: resultSound
    @cleanUpGranFaceTemp
    exitScript: "Control CSV was not created."
endif
Read Table from comma-separated file: tempControl$
ctrlTable = selected("Table")
nCtrl = Get number of rows
if nCtrl < 2
    removeObject: ctrlTable, resultSound
    @cleanUpGranFaceTemp
    exitScript: "Control timeline has too few rows."
endif
for i from 1 to nCtrl
    selectObject: ctrlTable
    .v$ = Get value: i, "time"
    ctrl_t_'i' = number(.v$)
    .v$ = Get value: i, "position"
    ctrl_pos_'i' = number(.v$)
    .v$ = Get value: i, "grain_ms"
    ctrl_grain_'i' = number(.v$)
    .v$ = Get value: i, "density"
    ctrl_density_'i' = number(.v$)
    .v$ = Get value: i, "pitch_st"
    ctrl_pitch_'i' = number(.v$)
    .v$ = Get value: i, "pitch_spread_st"
    ctrl_pspread_'i' = number(.v$)
    .v$ = Get value: i, "spray_ms"
    ctrl_spray_'i' = number(.v$)
    .v$ = Get value: i, "stereo_spread"
    ctrl_stereo_'i' = number(.v$)
    .v$ = Get value: i, "onset_jitter"
    ctrl_jitter_'i' = number(.v$)
    .v$ = Get value: i, "amplitude"
    ctrl_amp_'i' = number(.v$)
    .v$ = Get value: i, "freeze"
    ctrl_freeze_'i' = number(.v$)
endfor
removeObject: ctrlTable
rawCtrlDur = ctrl_t_'nCtrl'
if rawCtrlDur > 0.000001
    ctrlTimeScale = dur / rawCtrlDur
else
    ctrlTimeScale = 1
endif
for i from 1 to nCtrl
    ctrl_t_'i' = ctrl_t_'i' * ctrlTimeScale
endfor
nCtrlEff = nCtrl
appendInfoLine: "  Control frames: ", nCtrl, " | timeline ", fixed$(rawCtrlDur, 2),
 ... " s -> ", fixed$(dur, 2), " s"
if save_performance_csv and not render_saved_performance
    performanceText$ = readFile$(tempControl$)
    writeFile: performance_file$, performanceText$
    appendInfoLine: "  Saved facial performance: ", performance_file$
endif

# ==========================================================================
# GRAIN TRACE — actual scheduler/read-head, not the position control
# ==========================================================================
nTrace = 0
if not fallbackUsed and fileReadable(tempTrace$)
    Read Table from tab-separated file: tempTrace$
    traceTable = selected("Table")
    nTrace = Get number of rows
    for i from 1 to nTrace
        selectObject: traceTable
        .v$ = Get value: i, "onset_s"
        tr_t_'i' = number(.v$)
        .v$ = Get value: i, "read_pos"
        tr_read_'i' = number(.v$)
        .v$ = Get value: i, "source_pos"
        tr_source_'i' = number(.v$)
        .v$ = Get value: i, "grain_ms"
        tr_grain_'i' = number(.v$)
        .v$ = Get value: i, "freeze"
        tr_freeze_'i' = number(.v$)
    endfor
    removeObject: traceTable
endif
appendInfoLine: "  Grain trace rows: ", nTrace

# ==========================================================================
# STATS
# ==========================================================================
appendInfoLine: "[4/5] Reading performance/QC stats..."
py_cam_fps$ = "?"
py_raw_frames$ = "?"
py_valid_frames$ = "?"
py_face_ratio$ = "?"
py_blinks$ = "?"
py_live_status$ = "?"
py_live_under$ = "?"
py_source_channel$ = "?"
py_grain_count$ = "?"
py_mean_grain$ = "?"
py_mean_density$ = "?"
py_mean_pitch$ = "?"
py_mean_spray$ = "?"
py_mean_stereo$ = "?"
py_mean_jitter$ = "?"
py_output_peak$ = "?"
py_warnings$ = "none"
if fileReadable(tempStats$)
    statsText$ = readFile$(tempStats$)
    @parseStatLine: statsText$, "camera_fps="
    py_cam_fps$ = parseStatLine.result$
    @parseStatLine: statsText$, "raw_frames="
    py_raw_frames$ = parseStatLine.result$
    @parseStatLine: statsText$, "valid_face_frames="
    py_valid_frames$ = parseStatLine.result$
    @parseStatLine: statsText$, "face_tracking_ratio="
    py_face_ratio$ = parseStatLine.result$
    @parseStatLine: statsText$, "blink_count="
    py_blinks$ = parseStatLine.result$
    @parseStatLine: statsText$, "live_status="
    py_live_status$ = parseStatLine.result$
    @parseStatLine: statsText$, "live_underflows="
    py_live_under$ = parseStatLine.result$
    @parseStatLine: statsText$, "source_channel="
    py_source_channel$ = parseStatLine.result$
    @parseStatLine: statsText$, "grain_count="
    py_grain_count$ = parseStatLine.result$
    @parseStatLine: statsText$, "mean_grain_ms="
    py_mean_grain$ = parseStatLine.result$
    @parseStatLine: statsText$, "mean_density="
    py_mean_density$ = parseStatLine.result$
    @parseStatLine: statsText$, "mean_pitch_st="
    py_mean_pitch$ = parseStatLine.result$
    @parseStatLine: statsText$, "mean_spray_ms="
    py_mean_spray$ = parseStatLine.result$
    @parseStatLine: statsText$, "mean_stereo_spread="
    py_mean_stereo$ = parseStatLine.result$
    @parseStatLine: statsText$, "mean_onset_jitter="
    py_mean_jitter$ = parseStatLine.result$
    @parseStatLine: statsText$, "output_peak="
    py_output_peak$ = parseStatLine.result$
    @parseStatLine: statsText$, "warnings="
    py_warnings$ = parseStatLine.result$
endif
appendInfoLine: "  Face coverage: ", py_face_ratio$, " | Blinks: ", py_blinks$,
 ... " | Grains: ", py_grain_count$
if live_audio_during_capture
    appendInfoLine: "  Live audio: ", py_live_status$, " | stream notices: ", py_live_under$
endif
if py_warnings$ <> "?" and py_warnings$ <> "none"
    appendInfoLine: "  WARNING: ", py_warnings$
endif

# ==========================================================================
# VISUALIZATION
# ==========================================================================
if draw_visualization
    appendInfoLine: "[5/5] Drawing mechanism visualization..."
    Erase all
    Font size: 10
    Line width: 1
    Colour: "Black"

    soundNameViz$ = replace$(soundName$, "_", "\_ ", 0)
    warningsViz$ = replace$(py_warnings$, "%", " pct", 0)
    warningsViz$ = replace$(warningsViz$, "_", "\_ ", 0)

    # Shared waveform axes / relative time.
    selectObject: sound
    Copy: "granface_viz_in"
    vizInput = selected("Sound")
    Shift times to: "start time", 0
    inPeak = Get absolute extremum: 0, 0, "None"
    selectObject: resultSound
    Copy: "granface_viz_out"
    vizOutput = selected("Sound")
    Shift times to: "start time", 0
    outPeak = Get absolute extremum: 0, 0, "None"
    waveY = max(0.001, 1.05 * max(inPeak, outPeak))
    if waveY <= 0.25
        waveStep = 0.1
    elsif waveY <= 0.75
        waveStep = 0.25
    elsif waveY <= 1.5
        waveStep = 0.5
    else
        waveStep = 1
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
    Text: 0.5, "centre", 0.76, "half", "##Granular Face Navigator##"
    Font size: 8
    Colour: "{0.4,0.4,0.5}"
    Text: 0.5, "centre", -1.28, "half", soundNameViz$ + " | " + presetName$ + " | " + positionLabel$
    if fallbackUsed
        Font size: 7
        Colour: "{0.80,0.18,0.18}"
        Text: 0.5, "centre", 0.02, "half", "FALLBACK: face tracking failed; source copied unchanged"
    endif

    # Waveforms
    Select outer viewport: 0, 8, 0.60, 1.34
    Select inner viewport: 0.6, 7.7, 0.65, 1.29
    selectObject: vizInput
    Colour: "{0.36,0.39,0.45}"
    Draw: 0, dur, -waveY, waveY, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Marks left every: 1, waveStep, "yes", "yes", "no"
    Marks bottom every: 1, timeStep, "no", "yes", "no"
    Font size: 7
    Text left: "yes", "Original"

    Select outer viewport: 0, 8, 1.34, 2.08
    Select inner viewport: 0.6, 7.7, 1.39, 2.03
    selectObject: vizOutput
    Colour: "{0.20,0.40,0.75}"
    Draw: 0, dur, -waveY, waveY, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Marks left every: 1, waveStep, "yes", "yes", "no"
    Marks bottom every: 1, timeStep, "no", "yes", "no"
    Font size: 7
    Text left: "yes", "Granular output"

    if not fallbackUsed
        # Actual grain scheduler trace: each horizontal mark is one grain.
        Select outer viewport: 0, 8, 2.16, 3.17
        Select inner viewport: 0.6, 7.7, 2.23, 3.10
        Axes: 0, dur, 0, 1
        Paint rectangle: "{0.955,0.968,0.988}", 0, dur, 0, 1
        # Freeze spans are shaded behind the actual read trace.
        Colour: "{0.96,0.88,0.88}"
        for i from 2 to nCtrlEff
            ip = i - 1
            if ctrl_freeze_'ip' > 0.5
                Paint rectangle: "{0.96,0.88,0.88}", ctrl_t_'ip', ctrl_t_'i', 0.02, 0.98
            endif
        endfor
        # Actual read-head before spray.
        Colour: "{0.20,0.40,0.75}"
        Line width: 1.4
        if nTrace > 1
            for i from 2 to nTrace
                ip = i - 1
                Draw line: tr_t_'ip', tr_read_'ip', tr_t_'i', tr_read_'i'
            endfor
        endif
        # Grain marks: y = realized source position after spray, horizontal length = grain duration.
        Colour: "{0.28,0.54,0.52}"
        Line width: 1.6
        for i from 1 to nTrace
            trEnd = min(dur, tr_t_'i' + tr_grain_'i' / 1000)
            Draw line: tr_t_'i', tr_source_'i', trEnd, tr_source_'i'
        endfor
        Line width: 1
        Colour: "Black"
        Draw inner box
        Marks left every: 1, 0.25, "yes", "yes", "no"
        Marks bottom every: 1, timeStep, "no", "yes", "no"
        Font size: 7
        Text left: "yes", "Source pos"
        Text top: "no", "Actual grain field: blue read-head | teal grains | pale red Freeze"

        # Grain size
        grainYmax = max_grain_ms
        Select outer viewport: 0, 8, 3.17, 4.18
        Select inner viewport: 0.6, 7.7, 3.24, 4.11
        Axes: 0, dur, 0, grainYmax
        Paint rectangle: "{0.965,0.972,0.985}", 0, dur, 0, grainYmax
        Colour: "{0.28,0.54,0.52}"
        Line width: 2.2
        for i from 2 to nCtrlEff
            ip = i - 1
            Draw line: ctrl_t_'ip', ctrl_grain_'ip', ctrl_t_'i', ctrl_grain_'i'
        endfor
        Line width: 1
        Colour: "Black"
        Draw inner box
        grainStep = max(10, round(grainYmax / 4))
        Marks left every: 1, grainStep, "yes", "yes", "no"
        Marks bottom every: 1, timeStep, "no", "yes", "no"
        Font size: 7
        Text left: "yes", "Grain ms"
        Text top: "no", "Grain duration"

        # Density
        Select outer viewport: 0, 8, 4.18, 5.19
        Select inner viewport: 0.6, 7.7, 4.25, 5.12
        Axes: 0, dur, 0, max_density
        Paint rectangle: "{0.962,0.978,0.985}", 0, dur, 0, max_density
        Colour: "{0.40,0.48,0.66}"
        Line width: 2.2
        for i from 2 to nCtrlEff
            ip = i - 1
            Draw line: ctrl_t_'ip', ctrl_density_'ip', ctrl_t_'i', ctrl_density_'i'
        endfor
        Line width: 1
        Colour: "Black"
        Draw inner box
        densityStep = max(1, round(max_density / 5))
        Marks left every: 1, densityStep, "yes", "yes", "no"
        Marks bottom every: 1, timeStep, "no", "yes", "no"
        Font size: 7
        Text left: "yes", "Grains/s"
        Text top: "no", "Granular density (log-mapped control)"

        # Pitch centre + random spread envelope; axis derived from actual data.
        pitchActualMax = 1
        for i from 1 to nCtrlEff
            pitchActualMax = max(pitchActualMax, abs(ctrl_pitch_'i' + ctrl_pspread_'i'))
            pitchActualMax = max(pitchActualMax, abs(ctrl_pitch_'i' - ctrl_pspread_'i'))
        endfor
        pitchY = 1.08 * pitchActualMax
        Select outer viewport: 0, 8, 5.19, 6.25
        Select inner viewport: 0.6, 7.7, 5.26, 6.18
        Axes: 0, dur, -pitchY, pitchY
        Paint rectangle: "{0.955,0.968,0.988}", 0, dur, -pitchY, pitchY
        Colour: "{0.78,0.82,0.92}"
        Draw line: 0, 0, dur, 0
        Colour: "{0.50,0.55,0.72}"
        Line width: 1
        for i from 2 to nCtrlEff
            ip = i - 1
            Draw line: ctrl_t_'ip', ctrl_pitch_'ip' + ctrl_pspread_'ip', ctrl_t_'i', ctrl_pitch_'i' + ctrl_pspread_'i'
            Draw line: ctrl_t_'ip', ctrl_pitch_'ip' - ctrl_pspread_'ip', ctrl_t_'i', ctrl_pitch_'i' - ctrl_pspread_'i'
        endfor
        Colour: "{0.20,0.40,0.75}"
        Line width: 2.2
        for i from 2 to nCtrlEff
            ip = i - 1
            Draw line: ctrl_t_'ip', ctrl_pitch_'ip', ctrl_t_'i', ctrl_pitch_'i'
        endfor
        Line width: 1
        Colour: "Black"
        Draw inner box
        if pitchY <= 6
            pitchStep = 2
        elsif pitchY <= 12
            pitchStep = 4
        else
            pitchStep = 6
        endif
        Marks left every: 1, pitchStep, "yes", "yes", "no"
        Marks bottom every: 1, timeStep, "no", "yes", "no"
        Font size: 7
        Text left: "yes", "Pitch st"
        Text top: "no", "Pitch centre + random spread envelope"

        # Four compact destination panels: spray | stereo | temporal jitter | amplitude
        Select outer viewport: 0, 2.0, 6.34, 7.26
        Select inner viewport: 0.55, 1.88, 6.42, 7.18
        sprayY = max(10, max_spray_ms)
        Axes: 0, dur, 0, sprayY
        Paint rectangle: "{0.965,0.972,0.985}", 0, dur, 0, sprayY
        Colour: "{0.46,0.50,0.68}"
        for i from 2 to nCtrlEff
            ip = i - 1
            Draw line: ctrl_t_'ip', ctrl_spray_'ip', ctrl_t_'i', ctrl_spray_'i'
        endfor
        Colour: "Black"
        Draw inner box
        Marks left every: 1, max(10, round(sprayY / 3)), "yes", "yes", "no"
        Font size: 6.2
        Text top: "no", "Spray ms"

        Select outer viewport: 2.0, 4.0, 6.34, 7.26
        Select inner viewport: 2.16, 3.88, 6.42, 7.18
        Axes: 0, dur, 0, 1
        Paint rectangle: "{0.962,0.978,0.985}", 0, dur, 0, 1
        Colour: "{0.50,0.40,0.68}"
        for i from 2 to nCtrlEff
            ip = i - 1
            Draw line: ctrl_t_'ip', ctrl_stereo_'ip', ctrl_t_'i', ctrl_stereo_'i'
        endfor
        Colour: "Black"
        Draw inner box
        Marks left every: 1, 0.5, "yes", "yes", "no"
        Font size: 6.2
        Text top: "no", "Stereo spread"

        Select outer viewport: 4.0, 6.0, 6.34, 7.26
        Select inner viewport: 4.16, 5.88, 6.42, 7.18
        Axes: 0, dur, 0, 1
        Paint rectangle: "{0.965,0.972,0.985}", 0, dur, 0, 1
        Colour: "{0.40,0.48,0.66}"
        for i from 2 to nCtrlEff
            ip = i - 1
            Draw line: ctrl_t_'ip', ctrl_jitter_'ip', ctrl_t_'i', ctrl_jitter_'i'
        endfor
        Colour: "Black"
        Draw inner box
        Marks left every: 1, 0.5, "yes", "yes", "no"
        Font size: 6.2
        Text top: "no", "Onset jitter"

        Select outer viewport: 6.0, 8.0, 6.34, 7.26
        Select inner viewport: 6.16, 7.70, 6.42, 7.18
        Axes: 0, dur, 0, 1
        Paint rectangle: "{0.965,0.968,0.985}", 0, dur, 0, 1
        Colour: "{0.28,0.54,0.52}"
        for i from 2 to nCtrlEff
            ip = i - 1
            Draw line: ctrl_t_'ip', ctrl_amp_'ip', ctrl_t_'i', ctrl_amp_'i'
        endfor
        Colour: "Black"
        Draw inner box
        Marks left every: 1, 0.5, "yes", "yes", "no"
        Font size: 6.2
        Text top: "no", "Amplitude"

        # One shared time axis for the stacked control figure.
        Select outer viewport: 0, 8, 7.25, 7.53
        Select inner viewport: 0.6, 7.7, 7.26, 7.45
        Axes: 0, dur, 0, 1
        Colour: "Black"
        Draw line: 0, 0.78, dur, 0.78
        Marks bottom every: 1, timeStep, "yes", "yes", "no"
        Font size: 6.5
        Text bottom: "no", "Time (s)"
    else
        # Fallback means NO granular processing happened: do not draw fake control curves.
        Select outer viewport: 0, 8, 2.16, 7.53
        Select inner viewport: 0.6, 7.7, 2.24, 7.44
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.94,0.94,0.94}", 0, 1, 0, 1
        Colour: "{0.55,0.55,0.58}"
        Font size: 10
        Text: 0.5, "centre", 0.55, "half", "No granular trace: face/capture failed"
        Font size: 8
        Text: 0.5, "centre", 0.45, "half", "The source was copied unchanged; control panels are intentionally suppressed."
        Colour: "Black"
        Draw inner box
    endif

    # Summary / process diagram
    Select outer viewport: 0, 8, 7.60, 8.86
    Select inner viewport: 0.6, 7.7, 7.65, 8.79
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94,0.94,0.94}", 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.02, "left", 0.90, "half", "face -> calibrated sources -> mapping graph -> irregular granular scheduler -> stereo cloud"
    Font size: 6.3
    Colour: "{0.30,0.30,0.34}"
    yMap = 0.70
    for slot from 1 to 4
        if map_source_'slot' <> 12 and map_dest_'slot' <> 10 and map_amount_'slot' > 0
            inv$ = ""
            if map_invert_'slot'
                inv$ = " inv"
            endif
            Text: 0.03, "left", yMap, "half", string$(slot) + ". " + mapSource_'slot'$ + " -> " + mapDest_'slot'$ + "  x" + fixed$(map_amount_'slot', 2) + inv$
            yMap = yMap - 0.14
        endif
    endfor
    Colour: "{0.38,0.42,0.52}"
    Text: 0.58, "left", 0.70, "half", "Face coverage " + py_face_ratio$ + " | Cam " + py_cam_fps$ + " fps | Blinks " + py_blinks$
    Text: 0.58, "left", 0.53, "half", "Grains " + py_grain_count$ + " | mean " + py_mean_grain$ + " ms | " + py_mean_density$ + "/s | jitter " + py_mean_jitter$
    Text: 0.58, "left", 0.36, "half", "Capture " + fixed$(rawCtrlDur, 2) + " s -> sound " + fixed$(dur, 2) + " s | scale x" + fixed$(ctrlTimeScale, 3)
    Text: 0.58, "left", 0.19, "half", "Live " + py_live_status$ + " | source channel " + py_source_channel$ + " | output peak " + py_output_peak$
    if py_warnings$ <> "?" and py_warnings$ <> "none"
        Colour: "{0.80,0.18,0.18}"
        Text: 0.03, "left", 0.04, "half", "Warning: " + warningsViz$
    endif
    Colour: "Black"
    Select inner viewport: 0.6, 7.7, 7.65, 8.79
    Axes: 0, 1, 0, 1
    Draw inner box

    removeObject: vizInput, vizOutput
endif

# ---- FINAL SUMMARY ----
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: ", soundName$, "_granface"
appendInfoLine: "RMS: ", fixed$(rms_orig, 4), " -> ", fixed$(rms_out, 4)
appendInfoLine: "Grains rendered: ", py_grain_count$
appendInfoLine: "Mean grain: ", py_mean_grain$, " ms | Mean density: ", py_mean_density$, "/s"
appendInfoLine: "Mean pitch centre: ", py_mean_pitch$, " st | Mean spray: ", py_mean_spray$, " ms"
appendInfoLine: "Mean stereo spread: ", py_mean_stereo$, " | Mean onset jitter: ", py_mean_jitter$
if fallbackUsed
    appendInfoLine: "Status: FALLBACK / source copied unchanged"
endif

@cleanUpGranFaceTemp
selectObject: resultSound
if play_result
    Play
endif

# ==========================================================================
# PROCEDURES
# ==========================================================================
procedure parseStatLine: .text$, .key$
    .result$ = "?"
    .pos = index(.text$, .key$)
    if .pos > 0
        .start = .pos + length(.key$)
        .rest$ = mid$(.text$, .start, length(.text$) - .start + 1)
        .nl = index(.rest$, newline$)
        if .nl > 0
            .result$ = left$(.rest$, .nl - 1)
        else
            .result$ = .rest$
        endif
    endif
endproc
