# ============================================================
# Praat AudioTools - Limiter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Fast peak limiter with soft knee and multiple algorithms.
#   Uses vectorized operations for speed.
#
# Changelog v1.0:
#   - Fast vectorized processing (no sample loops)
#   - Multiple limiting algorithms
#   - Ceiling control
#   - Visualization
#   - Presets
# ============================================================

form Limiter v1.0
    optionmenu Preset 1
        option Custom
        option Transparent Master (-1 dBTP)
        option Loud Master (-0.3 dBTP)
        option Broadcast Safe (-2 dBTP)
        option Streaming (-1 dBTP)
        option Aggressive (maximize)
        option Soft Clip (saturation)
        option Brick Wall
    comment === Threshold & Ceiling ===
    real Threshold_dB -1.0
    real Ceiling_dBTP -1.0
    comment === Character ===
    optionmenu Algorithm 1
        option Hard clip (fast)
        option Soft clip (warm)
        option Tanh (smooth)
        option Cubic (gentle)
    real Knee_dB 3.0
    comment (0 = hard knee, higher = softer)
    comment === Output ===
    boolean Auto_makeup 1
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
sr = Get sampling frequency
dur = Get total duration
nChannels = Get number of channels

# === APPLY PRESETS ===
if preset = 2
    threshold_dB = -1.0
    ceiling_dBTP = -1.0
    algorithm = 3
    knee_dB = 3.0
    presetName$ = "Transparent"
elsif preset = 3
    threshold_dB = -0.3
    ceiling_dBTP = -0.3
    algorithm = 1
    knee_dB = 1.0
    presetName$ = "Loud"
elsif preset = 4
    threshold_dB = -2.0
    ceiling_dBTP = -2.0
    algorithm = 3
    knee_dB = 4.0
    presetName$ = "Broadcast"
elsif preset = 5
    threshold_dB = -1.0
    ceiling_dBTP = -1.0
    algorithm = 4
    knee_dB = 6.0
    presetName$ = "Streaming"
elsif preset = 6
    threshold_dB = -0.1
    ceiling_dBTP = -0.1
    algorithm = 1
    knee_dB = 0
    presetName$ = "Aggressive"
elsif preset = 7
    threshold_dB = -3.0
    ceiling_dBTP = -0.5
    algorithm = 2
    knee_dB = 6.0
    presetName$ = "SoftClip"
elsif preset = 8
    threshold_dB = -0.5
    ceiling_dBTP = -0.5
    algorithm = 1
    knee_dB = 0
    presetName$ = "BrickWall"
else
    presetName$ = "Custom"
endif

# Convert to linear
threshold = 10 ^ (threshold_dB / 20)
ceiling = 10 ^ (ceiling_dBTP / 20)

# === INFO HEADER ===
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  LIMITER v1.0 (Fast)"
writeInfoLine: "=============================================="
writeInfoLine: ""
writeInfoLine: "Input: ", sound_name$, " (", fixed$(dur, 2), "s)"
writeInfoLine: "Preset: ", presetName$
writeInfoLine: "Threshold: ", fixed$(threshold_dB, 1), " dB"
writeInfoLine: "Ceiling: ", fixed$(ceiling_dBTP, 1), " dBTP"
writeInfoLine: ""

# === INPUT ANALYSIS ===
selectObject: sound
inPeak = Get maximum: 0, 0, "Sinc70"
inPeakNeg = Get minimum: 0, 0, "Sinc70"
inPeakAbs = max(abs(inPeak), abs(inPeakNeg))
inPeak_dB = 20 * log10(inPeakAbs + 1e-10)

appendInfoLine: "Input Peak: ", fixed$(inPeak_dB, 1), " dBFS"

# ============================================================
# FAST LIMITING (vectorized)
# ============================================================

appendInfoLine: ""
appendInfoLine: "Processing..."

selectObject: sound
result = Copy: sound_name$ + "_limited"

# Apply limiting based on algorithm (all use fast Formula)
if algorithm = 1
    # Hard clip
    selectObject: result
    Formula: ~ if self > threshold then threshold else if self < -threshold then -threshold else self fi fi

elsif algorithm = 2
    # Soft clip (polynomial)
    selectObject: result
    if knee_dB > 0
        knee = 10 ^ (knee_dB / 20) * threshold
        Formula: ~ if abs(self) < threshold then self else if abs(self) < threshold + knee then self - (((abs(self) - threshold) ^ 2) / (4 * knee)) * (self / (abs(self) + 1e-10)) else (threshold + knee/2) * (self / (abs(self) + 1e-10)) fi fi
    else
        Formula: ~ if self > threshold then threshold else if self < -threshold then -threshold else self fi fi
    endif

elsif algorithm = 3
    # Tanh (smooth saturation)
    selectObject: result
    # Scale so threshold maps to ~0.76 (tanh(1))
    Formula: ~ threshold * tanh(self / threshold)

else
    # Cubic soft clip
    selectObject: result
    Formula: ~ if abs(self) < threshold then self else if abs(self) < threshold * 2 then self - ((abs(self) - threshold) ^ 3 / (3 * threshold ^ 2)) * (self / (abs(self) + 1e-10)) else threshold * 1.33 * (self / (abs(self) + 1e-10)) fi fi
endif

# === AUTO MAKEUP ===
if auto_makeup
    selectObject: result
    currentPeak = Get maximum: 0, 0, "Sinc70"
    currentPeakNeg = Get minimum: 0, 0, "Sinc70"
    currentPeakAbs = max(abs(currentPeak), abs(currentPeakNeg))
    
    if currentPeakAbs > 0.001 and currentPeakAbs < ceiling
        makeupRatio = ceiling / currentPeakAbs
        Formula: ~ self * makeupRatio
        makeupGain_dB = 20 * log10(makeupRatio)
        appendInfoLine: "  Auto makeup: +", fixed$(makeupGain_dB, 1), " dB"
    endif
endif

# === FINAL CEILING ===
selectObject: result
Scale peak: ceiling

# === OUTPUT ANALYSIS ===
selectObject: result
outPeak = Get maximum: 0, 0, "Sinc70"
outPeakNeg = Get minimum: 0, 0, "Sinc70"
outPeakAbs = max(abs(outPeak), abs(outPeakNeg))
outPeak_dB = 20 * log10(outPeakAbs + 1e-10)

outRMS = Get root-mean-square: 0, 0
outRMS_dB = 20 * log10(outRMS + 1e-10)

appendInfoLine: ""
appendInfoLine: "Output Peak: ", fixed$(outPeak_dB, 1), " dBFS"

# ============================================================
# VISUALIZATION
# ============================================================

if visualize
    appendInfoLine: ""
    appendInfoLine: "Creating visualization..."
    
    Erase all
    
    # === TITLE ===
    Select outer viewport: 1, 8, 0, 0.4
    Font size: 11
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Limiter## | " + presetName$ + " | Ceiling: " + fixed$(ceiling_dBTP, 1) + " dBTP"
    
    # === INPUT WAVEFORM ===
    Select outer viewport: 0, 8, 0.5, 2.3
    Select inner viewport: 0.8, 7.6, 0.7, 2.1
    
    selectObject: sound
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    # Threshold lines
    Axes: 0, dur, -1, 1
    Colour: "{0.9, 0.3, 0.3}"
    Dashed line
    Draw line: 0, threshold, dur, threshold
    Draw line: 0, -threshold, dur, -threshold
    Solid line
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.15, 8, 0.5, 2.3
    Text left: "yes", "Input"
    
    # === OUTPUT WAVEFORM ===
    Select outer viewport: 0, 8, 2.4, 4.2
    Select inner viewport: 0.8, 7.6, 2.6, 4.0
    
    selectObject: result
    Colour: "{0.3, 0.6, 0.4}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    # Ceiling lines
    Axes: 0, dur, -1, 1
    Colour: "{0.3, 0.3, 0.8}"
    Dashed line
    Draw line: 0, ceiling, dur, ceiling
    Draw line: 0, -ceiling, dur, -ceiling
    Solid line
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.15, 8, 2.4, 4.2
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"
    
    # === TRANSFER CURVE ===
    Select outer viewport: 0, 4, 4.3, 6.0
    Select inner viewport: 0.6, 3.6, 4.5, 5.8
    
    Axes: -1, 1, -1, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", -1, 1, -1, 1
    
    # Grid
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: -1, 0, 1, 0
    Draw line: 0, -1, 0, 1
    
    # Unity line
    Colour: "{0.7, 0.7, 0.7}"
    Dashed line
    Draw line: -1, -1, 1, 1
    Solid line
    
    # Threshold box
    Colour: "{0.9, 0.9, 0.95}"
    Paint rectangle: "{0.9, 0.9, 0.95}", -threshold, threshold, -1, 1
    
    # Transfer curve
    Colour: "{0.8, 0.3, 0.3}"
    Line width: 2
    
    prevY = 0
    step = 0.02
    x = -1
    while x <= 1
        if algorithm = 1
            if x > threshold
                y = threshold
            elsif x < -threshold
                y = -threshold
            else
                y = x
            endif
        elsif algorithm = 3
            y = threshold * tanh(x / threshold)
        else
            if abs(x) < threshold
                y = x
            else
                y = threshold * (x / (abs(x) + 0.001))
            endif
        endif
        
        if x > -1
            Draw line: x - step, prevY, x, y
        endif
        prevY = y
        x = x + step
    endwhile
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text bottom: "yes", "Input"
    Text left: "yes", "Output"
    
    # === STATS ===
    Select outer viewport: 4, 8, 4.3, 6.0
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "{0.3, 0.3, 0.3}"
    
    Text: 0.5, "centre", 0.85, "half", "##Statistics##"
    Font size: 7
    Text: 0.2, "left", 0.65, "half", "Input Peak:"
    Text: 0.7, "left", 0.65, "half", fixed$(inPeak_dB, 1) + " dB"
    Text: 0.2, "left", 0.45, "half", "Output Peak:"
    Text: 0.7, "left", 0.45, "half", fixed$(outPeak_dB, 1) + " dB"
    Text: 0.2, "left", 0.25, "half", "Reduction:"
    Text: 0.7, "left", 0.25, "half", fixed$(inPeak_dB - outPeak_dB, 1) + " dB"
    
    Font size: 10
    Colour: "Black"
endif

# ============================================================
# OUTPUT
# ============================================================

selectObject: result

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE: ", selected$("Sound")
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "  Peak reduction: ", fixed$(inPeak_dB - outPeak_dB, 1), " dB"

if play
    appendInfoLine: ""
    appendInfoLine: "Playing..."
    Play
endif

selectObject: result