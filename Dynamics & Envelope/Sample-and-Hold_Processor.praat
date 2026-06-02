# ============================================================
# Praat AudioTools - Sample-and-Hold_Processor.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Sample-and-hold processor with multiple control modes
#   including binary gating, intensity-based, AM, pitch-gated,
#   custom patterns, and spectral centroid gating.
#
# Changelog v1.0:
#   - Added presets, smoothing, play, improved info output
#
# Changelog v1.1:
#   - Smoothing_ms now actually controls the smoothing: the gate is
#     applied as a gain envelope that is low-passed by Smoothing_ms, so
#     each transition crossfades over the requested time (previously a
#     fixed 3-point average that ignored the ms value and dulled the audio).
#   - Fixed the info header (was erased by repeated writeInfoLine calls).
#   - Fixed visualization title + parameter centring (0..1 axis).
# ============================================================

form Sample-and-Hold Processor v1.0
    optionmenu Preset 1
        option Custom
        option Rhythmic Chop (binary)
        option Dynamics Gate (intensity)
        option Tremolo (AM slow)
        option Flutter (AM fast)
        option Voiced Only (pitch-gate)
        option Bright Only (centroid)
        option Morse Code (pattern)
    optionmenu Control_mode 1
        option Binary (alternating)
        option Intensity-based
        option Amplitude Modulation
        option Pitch-gated
        option Custom Pattern
        option Spectral Centroid Gate
    comment === Timing ===
    positive Sample_period_s 0.02
    real Gate_threshold 0.5
    comment === Mode Parameters ===
    real Intensity_threshold_dB 0
    comment (0 = auto from median)
    real AM_frequency_Hz 4
    real AM_depth 1.0
    real Pitch_threshold_Hz 100
    real Centroid_threshold_Hz 1000
    sentence Pattern 1 0 1 1 0 1 0 1
    comment === Gate Character ===
    real Mute_level 0.0
    positive Smoothing_ms 2
    comment (smoothing prevents clicks)
    comment === Output ===
    boolean Visualize 1
    boolean Play 1
endform

# === INPUT VALIDATION ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
sound_name$ = selected$("Sound")

selectObject: sound
dur = Get total duration
sr = Get sampling frequency
nChannels = Get number of channels

# === USE WORKING VARIABLES (so presets can override) ===
workingMode = control_mode
workingPeriod = sample_period_s
workingIntensityThresh = intensity_threshold_dB
workingAMFreq = aM_frequency_Hz
workingAMDepth = aM_depth
workingPitchThresh = pitch_threshold_Hz
workingCentroidThresh = centroid_threshold_Hz
workingPattern$ = pattern$

# === APPLY PRESETS ===
if preset = 2
    # Rhythmic Chop
    workingMode = 1
    workingPeriod = 0.05
    presetName$ = "RhythmicChop"
elsif preset = 3
    # Dynamics Gate
    workingMode = 2
    workingIntensityThresh = 0
    workingPeriod = 0.02
    presetName$ = "DynamicsGate"
elsif preset = 4
    # Tremolo (slow AM)
    workingMode = 3
    workingAMFreq = 4
    workingAMDepth = 0.8
    workingPeriod = 0.01
    presetName$ = "Tremolo"
elsif preset = 5
    # Flutter (fast AM)
    workingMode = 3
    workingAMFreq = 12
    workingAMDepth = 1.0
    workingPeriod = 0.005
    presetName$ = "Flutter"
elsif preset = 6
    # Voiced Only
    workingMode = 4
    workingPitchThresh = 80
    workingPeriod = 0.02
    presetName$ = "VoicedOnly"
elsif preset = 7
    # Bright Only
    workingMode = 6
    workingCentroidThresh = 2000
    workingPeriod = 0.03
    presetName$ = "BrightOnly"
elsif preset = 8
    # Morse Code
    workingMode = 5
    workingPattern$ = "1 1 1 0 1 0 1 0 0"
    workingPeriod = 0.1
    presetName$ = "MorseCode"
else
    presetName$ = "Custom"
endif

numIntervals = ceiling(dur / workingPeriod)

# === GET MODE NAME ===
if workingMode = 1
    modeName$ = "Binary"
elsif workingMode = 2
    modeName$ = "Intensity"
elsif workingMode = 3
    modeName$ = "AM"
elsif workingMode = 4
    modeName$ = "Pitch-Gate"
elsif workingMode = 5
    modeName$ = "Pattern"
else
    modeName$ = "Centroid"
endif

# === INFO HEADER ===
clearinfo
appendInfoLine: "=============================================="
appendInfoLine: "  SAMPLE-AND-HOLD PROCESSOR v1.1"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Input: ", sound_name$, " (", fixed$(dur, 2), "s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Mode: ", modeName$
appendInfoLine: "Sample period: ", fixed$(workingPeriod * 1000, 1), " ms (", numIntervals, " intervals)"
appendInfoLine: ""

# === PARSE CUSTOM PATTERN ===
patternLength = 0
if workingMode = 5
    workingPattern$ = replace_regex$(workingPattern$, "^[ \t]+|[ \t]+$", "", 0)
    if length(workingPattern$) = 0
        exitScript: "Custom pattern is empty."
    endif
    workingPattern$ = workingPattern$ + " "
    @countPatternValues: workingPattern$
    patternLength = countPatternValues.count
    if patternLength = 0
        exitScript: "No valid pattern values found."
    endif
    appendInfoLine: "Pattern length: ", patternLength, " steps"
endif

# === PRE-ANALYSIS ===

# Intensity: auto-threshold via median
if workingMode = 2 and workingIntensityThresh = 0
    appendInfoLine: "Calculating auto-threshold..."
    
    selectObject: sound
    Create TableOfReal: "int_vals", numIntervals, 1
    table_id = selected("TableOfReal")
    
    for i from 1 to numIntervals
        t_start = (i - 1) * workingPeriod
        t_end = min(t_start + workingPeriod, dur)
        selectObject: sound
        Extract part: t_start, t_end, "rectangular", 1, "no"
        temp_seg = selected("Sound")
        int_val = Get intensity (dB)
        if int_val = undefined
            int_val = -100
        endif
        selectObject: table_id
        Set value: i, 1, int_val
        removeObject: temp_seg
    endfor
    
    selectObject: table_id
    Sort by column: 1, 0
    median_idx = max(1, floor(numIntervals / 2))
    workingIntensityThresh = Get value: median_idx, 1
    
    appendInfoLine: "  Auto threshold: ", fixed$(workingIntensityThresh, 1), " dB (median)"
    removeObject: table_id
endif

# Pitch: analyze full sound once
if workingMode = 4
    appendInfoLine: "Analyzing pitch..."
    selectObject: sound
    To Pitch: 0.01, 75, 600
    pitch_object = selected("Pitch")
    appendInfoLine: "  Threshold: ", workingPitchThresh, " Hz"
endif

# === CREATE OUTPUT ===
selectObject: sound
result = Copy: sound_name$ + "_SH"

# === STORAGE FOR VISUALIZATION ===
for i from 0 to numIntervals - 1
    controlVal[i] = 0
endfor

passCount = 0
muteCount = 0
gainMin = 1e9
gainMax = -1e9

# === MAIN PROCESSING LOOP ===
appendInfoLine: ""
appendInfoLine: "Processing ", numIntervals, " intervals..."

for i from 0 to numIntervals - 1
    t_start = i * workingPeriod
    t_end = min(t_start + workingPeriod, dur)
    t_mid = (t_start + t_end) / 2
    
    selectObject: sound
    
    if workingMode = 1
        # Binary alternating
        if i mod 2 = 0
            ctrl = 1
        else
            ctrl = 0
        endif
        
    elsif workingMode = 2
        # Intensity-based
        Extract part: t_start, t_end, "rectangular", 1, "no"
        temp_seg = selected("Sound")
        int_val = Get intensity (dB)
        if int_val = undefined
            int_val = -100
        endif
        if int_val > workingIntensityThresh
            ctrl = 1
        else
            ctrl = 0
        endif
        removeObject: temp_seg
        
    elsif workingMode = 3
        # Amplitude modulation
        phase = 2 * pi * workingAMFreq * t_start
        sineVal = (sin(phase) + 1) / 2
        ctrl = 1 - (workingAMDepth * (1 - sineVal))
        
    elsif workingMode = 4
        # Pitch-gated
        selectObject: pitch_object
        pitchVal = Get value at time: t_mid, "Hertz", "linear"
        if pitchVal <> undefined and pitchVal > workingPitchThresh
            ctrl = 1
        else
            ctrl = 0
        endif
        
    elsif workingMode = 5
        # Custom pattern
        patIdx = (i mod patternLength) + 1
        @getPatternValue: workingPattern$, patIdx
        ctrl = getPatternValue.value
        
    elsif workingMode = 6
        # Spectral centroid
        Extract part: t_start, t_end, "rectangular", 1, "no"
        temp_seg = selected("Sound")
        To Spectrum: "yes"
        spectrum = selected("Spectrum")
        centroid = Get centre of gravity: 2
        if centroid <> undefined and centroid > workingCentroidThresh
            ctrl = 1
        else
            ctrl = 0
        endif
        removeObject: spectrum, temp_seg
    endif
    
    controlVal[i] = ctrl
    
    # Statistics (skip for continuous AM)
    if workingMode <> 3
        if ctrl >= gate_threshold
            passCount = passCount + 1
        else
            muteCount = muteCount + 1
        endif
    endif
    
    # Determine amplitude multiplier (stored; applied after the loop via a
    # smoothed gain envelope so transitions can be crossfaded)
    if workingMode = 3
        ampMult = ctrl
    else
        if ctrl >= gate_threshold
            ampMult = 1
        else
            ampMult = mute_level
        endif
    endif
    gainArr[i] = ampMult
    if ampMult < gainMin
        gainMin = ampMult
    endif
    if ampMult > gainMax
        gainMax = ampMult
    endif
endfor

# === BUILD GAIN ENVELOPE, SMOOTH, AND APPLY ===
# One held value per interval at the audio rate. Low-passing it by
# Smoothing_ms crossfades the gate transitions (anti-click) without
# dulling the audio itself.
Create Sound from formula: "gain_env", 1, 0, dur, sr, "0"
gainEnv = selected("Sound")
for i from 0 to numIntervals - 1
    t_start = i * workingPeriod
    t_end = min(t_start + workingPeriod, dur)
    selectObject: gainEnv
    Formula (part): t_start, t_end, 1, 1, string$(gainArr[i])
endfor

smoothCutoff = 1000 / (2 * pi * smoothing_ms)
if smoothing_ms > 0 and smoothCutoff < sr / 2
    appendInfoLine: "Smoothing gate transitions (", fixed$(smoothing_ms, 1), " ms)..."
    selectObject: gainEnv
    smoothed = Filter (pass Hann band): 0, smoothCutoff, smoothCutoff * 0.5
    removeObject: gainEnv
    gainEnv = smoothed
    # clamp away filter overshoot, back into the real gain range
    selectObject: gainEnv
    Formula: "min(max(self, " + string$(gainMin) + "), " + string$(gainMax) + ")"
endif

gainEnv_str$ = string$(gainEnv)
selectObject: result
Formula: "self * object(" + gainEnv_str$ + ", x)"
removeObject: gainEnv

# === CLEANUP PRE-ANALYSIS ===
if workingMode = 4
    removeObject: pitch_object
endif

# === NORMALIZE ===
selectObject: result
Scale peak: 0.95

# === STATISTICS ===
if workingMode <> 3
    appendInfoLine: ""
    appendInfoLine: "Results:"
    appendInfoLine: "  Passed: ", passCount, " (", fixed$(100 * passCount / numIntervals, 1), "%)"
    appendInfoLine: "  Muted: ", muteCount, " (", fixed$(100 * muteCount / numIntervals, 1), "%)"
    
    if passCount = numIntervals
        appendInfoLine: "  WARNING: All segments passed"
    elsif muteCount = numIntervals
        appendInfoLine: "  WARNING: All segments muted"
    endif
endif

# === VISUALIZATION ===
if visualize
    appendInfoLine: ""
    appendInfoLine: "Creating visualization..."
    
    Erase all
    
    # === TITLE ===
    Select outer viewport: 1, 8, 0, 0.4
    Axes: 0, 1, 0, 1
    Font size: 11
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Sample-and-Hold## | " + presetName$ + " | " + modeName$
    
    # === ORIGINAL ===
    Select outer viewport: 0, 8, 0.5, 2.0
    Select inner viewport: 0.8, 7.6, 0.6, 1.8
    
    selectObject: sound
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.15, 8, 0.5, 2.0
    Text left: "yes", "Input"
    
    # === GATE SIGNAL ===
    Select outer viewport: 0, 8, 2.1, 3.4
    Select inner viewport: 0.8, 7.6, 2.2, 3.2
    
    # Create gate display
    Create Sound from formula: "gate_display", 1, 0, dur, 1000, "0"
    gate_display = selected("Sound")
    
    for i from 0 to numIntervals - 1
        t_start = i * workingPeriod
        t_end = min(t_start + workingPeriod, dur)
        if workingMode = 3
            gateVal = controlVal[i]
        else
            if controlVal[i] >= gate_threshold
                gateVal = 1
            else
                gateVal = 0
            endif
        endif
        selectObject: gate_display
        Formula (part): t_start, t_end, 1, 1, string$(gateVal)
    endfor
    
    # Background
    Axes: 0, dur, -0.1, 1.1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, dur, -0.1, 1.1
    
    # Gate curve
    selectObject: gate_display
    Colour: "{0.8, 0.4, 0.3}"
    Line width: 2
    Draw: 0, dur, -0.1, 1.1, "no", "Curve"
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.15, 8, 2.1, 3.4
    Text left: "yes", "Gate"
    
    removeObject: gate_display
    
    # === OUTPUT ===
    Select outer viewport: 0, 8, 3.5, 5.0
    Select inner viewport: 0.8, 7.6, 3.6, 4.8
    
    selectObject: result
    Colour: "{0.3, 0.6, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.15, 8, 3.5, 5.0
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"
    
    # === PARAMETERS ===
    Select outer viewport: 0, 8, 5.1, 5.5
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    
    if workingMode = 2
        paramText$ = "Threshold: " + fixed$(workingIntensityThresh, 0) + " dB"
    elsif workingMode = 3
        paramText$ = "Freq: " + fixed$(workingAMFreq, 1) + " Hz | Depth: " + fixed$(workingAMDepth, 2)
    elsif workingMode = 4
        paramText$ = "Pitch threshold: " + fixed$(workingPitchThresh, 0) + " Hz"
    elsif workingMode = 6
        paramText$ = "Centroid threshold: " + fixed$(workingCentroidThresh, 0) + " Hz"
    else
        paramText$ = "Period: " + fixed$(workingPeriod * 1000, 1) + " ms"
    endif
    
    Text: 0.5, "centre", 0.5, "half", paramText$ + " | Smoothing: " + fixed$(smoothing_ms, 0) + " ms"
    
    Font size: 10
    Colour: "Black"
endif

# === OUTPUT ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE: ", selected$("Sound")
appendInfoLine: "=============================================="

if play
    appendInfoLine: ""
    appendInfoLine: "Playing..."
    Play
endif

selectObject: result

# ============================================================
# PROCEDURES
# ============================================================

procedure countPatternValues: .pattern$
    .count = 0
    .temp$ = .pattern$
    repeat
        .space_pos = index_regex(.temp$, "[ \t]+")
        if .space_pos > 0
            .count = .count + 1
            .temp$ = right$(.temp$, length(.temp$) - .space_pos)
            .temp$ = replace_regex$(.temp$, "^[ \t]+", "", 0)
        endif
    until .space_pos = 0 or length(.temp$) = 0
endproc

procedure getPatternValue: .pattern$, .index
    .current = 0
    .temp$ = .pattern$
    repeat
        .space_pos = index_regex(.temp$, "[ \t]+")
        if .space_pos > 0
            .current = .current + 1
            .val_str$ = left$(.temp$, .space_pos - 1)
            if .current = .index
                .value = number(.val_str$)
                goto FOUND
            endif
            .temp$ = right$(.temp$, length(.temp$) - .space_pos)
            .temp$ = replace_regex$(.temp$, "^[ \t]+", "", 0)
        endif
    until .space_pos = 0
    .value = 0
    label FOUND
endproc