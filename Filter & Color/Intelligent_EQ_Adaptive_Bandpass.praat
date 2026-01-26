# ============================================================
# Praat AudioTools - Intelligent_EQ_Adaptive_Bandpass.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025) - Enhanced visualization + Octave control
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Adaptive Bandpass Filter with pitch-tracking center frequency.
#   Filter center follows detected F0 (or harmonic/subharmonic multiples).
#   Features octave/harmonic control for targeting specific partials.
#
# Usage:
#   Select a Sound object and run this script.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis 
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Category: Filter & Spectral Shaping
# ============================================================

# === INPUT VALIDATION ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

selectObject: originalID
duration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels
nyquist = sampleRate / 2

if duration < 0.05
    exitScript: "Sound too short (min 0.05s)."
endif

# === USER PARAMETERS ===
form Intelligent EQ: Adaptive Bandpass v1.0
    comment === Preset ===
    optionmenu Preset 1
        option Custom
        option Fundamental Extraction
        option 2nd Harmonic Focus
        option 3rd Harmonic Focus
        option Subharmonic (Octave Below)
        option Wide Harmonic Preserve
        option Noise Reduction
    
    comment === Pitch Tracking ===
    positive Minimum_pitch_(Hz) 75
    positive Maximum_pitch_(Hz) 500
    positive Smoothing_(Hz) 10
    
    comment === Harmonic/Octave Control ===
    real F0_multiplier 1.0
    comment (1.0=F0, 2.0=octave up, 0.5=octave down, 3.0=12th, etc.)
    real F0_offset_(Hz) 0.0
    comment (Additional Hz offset after multiplier)
    
    comment === Filter Parameters ===
    positive Bandwidth_val 100
    optionmenu Bandwidth_mode 1
        option Fixed (Hz)
        option Relative (fraction of center freq)
    positive Rolloff_smoothness 50
    
    comment === Unvoiced Handling ===
    optionmenu Unvoiced_mode 2
        option Bypass (pass original)
        option Attenuate
        option Mute
    real Unvoiced_attenuation_(dB) -18
    
    comment === Quality/Speed ===
    optionmenu Quality 2
        option Draft (60ms window)
        option Standard (40ms window)
        option High (25ms window)
    
    comment === Output ===
    boolean Show_visualization 1
    boolean Play_result 1
endform

# === APPLY PRESETS ===
if preset = 2
    # Fundamental Extraction
    f0_multiplier = 1.0
    f0_offset = 0
    bandwidth_val = 0.4
    bandwidth_mode = 2
    unvoiced_mode = 3
    smoothing = 10
    presetName$ = "Fundamental"
elsif preset = 3
    # 2nd Harmonic Focus
    f0_multiplier = 2.0
    f0_offset = 0
    bandwidth_val = 0.3
    bandwidth_mode = 2
    unvoiced_mode = 2
    smoothing = 12
    presetName$ = "2nd Harmonic"
elsif preset = 4
    # 3rd Harmonic Focus
    f0_multiplier = 3.0
    f0_offset = 0
    bandwidth_val = 0.25
    bandwidth_mode = 2
    unvoiced_mode = 2
    smoothing = 12
    presetName$ = "3rd Harmonic"
elsif preset = 5
    # Subharmonic (Octave Below)
    f0_multiplier = 0.5
    f0_offset = 0
    bandwidth_val = 0.5
    bandwidth_mode = 2
    unvoiced_mode = 2
    smoothing = 15
    presetName$ = "Subharmonic"
elsif preset = 6
    # Wide Harmonic Preserve
    f0_multiplier = 1.0
    f0_offset = 0
    bandwidth_val = 2.0
    bandwidth_mode = 2
    unvoiced_mode = 1
    smoothing = 15
    presetName$ = "WideHarmonic"
elsif preset = 7
    # Noise Reduction
    f0_multiplier = 1.0
    f0_offset = 0
    bandwidth_val = 150
    bandwidth_mode = 1
    unvoiced_mode = 2
    unvoiced_attenuation = -24
    smoothing = 10
    presetName$ = "NoiseReduction"
else
    presetName$ = "Custom"
endif

# Set window size
if quality = 1
    windowDur = 0.06
    qualityName$ = "Draft"
elsif quality = 2
    windowDur = 0.04
    qualityName$ = "Standard"
else
    windowDur = 0.025
    qualityName$ = "High"
endif

# Strict OLA: 50% hop for Hanning
hopDur = windowDur * 0.5

# === SETUP ===
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  INTELLIGENT EQ v1.0"
writeInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Duration: ", fixed$(duration, 2), " s"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "F0 Multiplier: ", fixed$(f0_multiplier, 2), "x"
if f0_offset <> 0
    appendInfoLine: "F0 Offset: ", fixed$(f0_offset, 1), " Hz"
endif
appendInfoLine: ""

# ============================================================
# STEP 1: PREPARE SOURCE (mono)
# ============================================================

selectObject: originalID
if numChannels > 1
    monoSource = Convert to mono
    appendInfoLine: "(Converted stereo to mono)"
else
    monoSource = Copy: "source"
endif

# ============================================================
# STEP 2: PITCH ANALYSIS & SMOOTHING
# ============================================================

appendInfoLine: "Step 1: Pitch Analysis..."

selectObject: monoSource
pitchRaw = To Pitch: hopDur/2, minimum_pitch, maximum_pitch

selectObject: pitchRaw
pitch = Smooth: smoothing
Rename: "smoothed_pitch"
removeObject: pitchRaw

selectObject: pitch
meanPitch = Get mean: 0, 0, "Hertz"
minPitch = Get minimum: 0, 0, "Hertz", "Parabolic"
maxPitchDetected = Get maximum: 0, 0, "Hertz", "Parabolic"

# Count voiced frames
numPitchFrames = Get number of frames
voicedCount = 0
for i from 1 to numPitchFrames
    selectObject: pitch
    pVal = Get value in frame: i, "Hertz"
    if pVal <> undefined
        voicedCount += 1
    endif
endfor
voicedPercent = voicedCount / numPitchFrames * 100

if meanPitch = undefined
    meanPitch = (minimum_pitch + maximum_pitch) / 2
    minPitch = minimum_pitch
    maxPitchDetected = maximum_pitch
endif

# Calculate target frequency stats
meanTarget = meanPitch * f0_multiplier + f0_offset
minTarget = minPitch * f0_multiplier + f0_offset
maxTarget = maxPitchDetected * f0_multiplier + f0_offset

appendInfoLine: "  Mean F0: ", fixed$(meanPitch, 1), " Hz"
appendInfoLine: "  Target center: ", fixed$(meanTarget, 1), " Hz (", fixed$(f0_multiplier, 2), "x + ", fixed$(f0_offset, 0), ")"
appendInfoLine: "  Voiced: ", fixed$(voicedPercent, 1), "%"
appendInfoLine: ""

# ============================================================
# STEP 3: PROCESS (STRICT OLA)
# ============================================================

appendInfoLine: "Step 2: Adaptive Filtering..."

# Create output sound
outputSound = Create Sound from formula: "output", 1, 0, duration, sampleRate, "0"

# Attenuation factor
attenFactor = 10 ^ (unvoiced_attenuation / 20)

# Calculate number of frames
numFrames = floor((duration - windowDur) / hopDur) + 1

appendInfoLine: "  Frames: ", numFrames, " (", qualityName$, ")"

for i from 1 to numFrames
    # Strict OLA Timing
    frameStart = (i - 1) * hopDur
    frameEnd = frameStart + windowDur
    frameMid = (frameStart + frameEnd) / 2
    
    # Get pitch
    selectObject: pitch
    currentPitch = Get value at time: frameMid, "Hertz", "linear"
    isVoiced = (currentPitch <> undefined and currentPitch > 0)
    
    # Extract with Hanning window
    selectObject: monoSource
    frameSound = Extract part: frameStart, frameEnd, "Hanning", 1, "no"
    
    if isVoiced
        # === VOICED ===
        
        # Apply F0 multiplier and offset
        targetFreq = currentPitch * f0_multiplier + f0_offset
        
        # Clamp to valid range
        targetFreq = max(20, min(nyquist - 100, targetFreq))
        
        # Bandwidth calculation
        if bandwidth_mode = 2
            # Relative to target frequency
            effectiveBW = targetFreq * bandwidth_val
        else
            # Fixed Hz
            effectiveBW = bandwidth_val
        endif
        
        effectiveBW = max(20, effectiveBW)
        
        lowBound = max(20, targetFreq - effectiveBW / 2)
        highBound = min(nyquist - 50, targetFreq + effectiveBW / 2)
        
        if highBound <= lowBound
            highBound = lowBound + 50
        endif
        
        selectObject: frameSound
        filtered = Filter (pass Hann band): lowBound, highBound, rolloff_smoothness
        
    else
        # === UNVOICED ===
        if unvoiced_mode = 1
            # Bypass
            selectObject: frameSound
            filtered = Copy: "temp"
        elsif unvoiced_mode = 2
            # Attenuate
            selectObject: frameSound
            filtered = Copy: "temp"
            Formula: "self * " + string$(attenFactor)
        else
            # Mute
            selectObject: frameSound
            filtered = Copy: "temp"
            Formula: "0"
        endif
    endif
    
    # Add to output
    selectObject: filtered
    Rename: "seg"
    
    startStr$ = fixed$(frameStart, 6)
    
    selectObject: outputSound
    Formula (part): frameStart, frameEnd, 1, 1, "self + Sound_seg(x - " + startStr$ + ")"
    
    removeObject: frameSound, filtered
    
    if (i mod 50) = 0
        appendInfo: "."
    endif
endfor

appendInfoLine: ""

# ============================================================
# STEP 4: NORMALIZE
# ============================================================

appendInfoLine: "Step 3: Normalizing..."

selectObject: outputSound
Rename: originalName$ + "_adaptive_EQ"
Scale peak: 0.95

# ============================================================
# STEP 5: COMPREHENSIVE VISUALIZATION
# ============================================================

if show_visualization
    appendInfoLine: "Step 4: Creating visualization..."
    
    Erase all
    
    vizDuration = min(duration, 12)
    maxFreqDisplay = min(nyquist, max(4000, maxTarget * 1.5))
    
# === TITLE ===
    Select outer viewport: 0, 9, 0, 0.8
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.9, "half", "##Intelligent EQ: Adaptive Bandpass## | " + originalName$
    
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    
    if bandwidth_mode = 2
        bwText$ = fixed$(bandwidth_val, 2) + "×f"
    else
        bwText$ = fixed$(bandwidth_val, 0) + " Hz"
    endif
    Text: 0.5, "centre", 0.01, "half", presetName$ + " | F0×" + fixed$(f0_multiplier, 2) + " | BW: " + bwText$
    
    # === PANEL 1: Original Spectrogram ===
    Select outer viewport: 0, 8, 0.7, 2.5
    Select inner viewport: 0.8, 7.7, 0.8, 2.4
    
    selectObject: monoSource
    To Spectrogram: 0.03, maxFreqDisplay, 0.002, 20, "Gaussian"
    specOrig = selected("Spectrogram")
    Paint: 0, vizDuration, 0, maxFreqDisplay, 100, "yes", 50, 6, 0, "no"
    
    # Overlay pitch contour (green)
    selectObject: pitch
    Colour: "{0.2, 0.9, 0.3}"
    Line width: 2
    Draw: 0, vizDuration, 0, maxFreqDisplay, "no"
    
    # Overlay target frequency (yellow dashed)
    Colour: "{1.0, 0.8, 0.2}"
    Line width: 2
    Dotted line
    
    step = vizDuration / 150
    prevT = 0
    prevTarget = undefined
    
    selectObject: pitch
    prevP = Get value at time: 0, "Hertz", "linear"
    if prevP <> undefined
        prevTarget = prevP * f0_multiplier + f0_offset
    endif
    
    t = step
    while t <= vizDuration
        selectObject: pitch
        currP = Get value at time: t, "Hertz", "linear"
        
        if currP <> undefined
            currTarget = currP * f0_multiplier + f0_offset
            
            if prevTarget <> undefined
                Select inner viewport: 0.8, 7.7, 0.8, 2.4
                Axes: 0, vizDuration, 0, maxFreqDisplay
                Draw line: prevT, prevTarget, t, currTarget
            endif
            
            prevTarget = currTarget
        else
            prevTarget = undefined
        endif
        
        prevP = currP
        prevT = t
        t = t + step
    endwhile
    
    Solid line
    
    Colour: "Black"
    Line width: 0.5
    Draw inner box
    
    Font size: 7
    Select outer viewport: 0, 0.8, 0.7, 2.5
    Axes: 0, 1, 0, 1
    Colour: "{0.3, 0.4, 0.6}"
    Text: 0.95, "right", 0.5, "half", "Original"
    
    removeObject: specOrig
    
    # === PANEL 2: Filtered Spectrogram ===
    Select outer viewport: 0, 8, 2.6, 4.4
    Select inner viewport: 0.8, 7.7, 2.7, 4.3
    
    selectObject: outputSound
    To Spectrogram: 0.03, maxFreqDisplay, 0.002, 20, "Gaussian"
    specFilt = selected("Spectrogram")
    Paint: 0, vizDuration, 0, maxFreqDisplay, 100, "yes", 50, 6, 0, "no"
    
    # Overlay target frequency
    Colour: "{0.2, 1.0, 0.4}"
    Line width: 2
    
    prevT = 0
    prevTarget = undefined
    
    selectObject: pitch
    prevP = Get value at time: 0, "Hertz", "linear"
    if prevP <> undefined
        prevTarget = prevP * f0_multiplier + f0_offset
    endif
    
    t = step
    while t <= vizDuration
        selectObject: pitch
        currP = Get value at time: t, "Hertz", "linear"
        
        if currP <> undefined
            currTarget = currP * f0_multiplier + f0_offset
            
            if prevTarget <> undefined
                Select inner viewport: 0.8, 7.7, 2.7, 4.3
                Axes: 0, vizDuration, 0, maxFreqDisplay
                Draw line: prevT, prevTarget, t, currTarget
            endif
            
            prevTarget = currTarget
        else
            prevTarget = undefined
        endif
        
        prevP = currP
        prevT = t
        t = t + step
    endwhile
    
    Colour: "Black"
    Line width: 0.5
    Draw inner box
    
    Font size: 7
    Select outer viewport: 0, 0.8, 2.6, 4.4
    Axes: 0, 1, 0, 1
    Colour: "{0.4, 0.6, 0.4}"
    Text: 0.95, "right", 0.5, "half", "Filtered"
    
    removeObject: specFilt
    
    # === PANEL 3: Pitch + Target Frequency ===
    Select outer viewport: 0, 8, 4.5, 5.7
    Select inner viewport: 0.8, 7.7, 4.6, 5.6
    
    pitchMin = max(50, minPitch * 0.8)
    pitchMax = min(nyquist, maxTarget * 1.3)
    
    # Safety check for undefined pitch range
    if pitchMin = undefined or pitchMin < 20
        pitchMin = 50
    endif
    if pitchMax = undefined or pitchMax < pitchMin + 50
        pitchMax = pitchMin + 500
    endif
    
    Axes: 0, vizDuration, pitchMin, pitchMax
    Paint rectangle: "{0.97, 0.98, 1.0}", 0, vizDuration, pitchMin, pitchMax
    
    # Draw F0
    selectObject: pitch
    Colour: "{0.3, 0.6, 0.9}"
    Line width: 2
    Draw: 0, vizDuration, pitchMin, pitchMax, "no"
    
    # Draw Target frequency
    Colour: "{0.9, 0.5, 0.2}"
    Line width: 2
    
    prevT = 0
    prevTarget = undefined
    
    selectObject: pitch
    prevP = Get value at time: 0, "Hertz", "linear"
    if prevP <> undefined
        prevTarget = prevP * f0_multiplier + f0_offset
    endif
    
    t = step
    while t <= vizDuration
        selectObject: pitch
        currP = Get value at time: t, "Hertz", "linear"
        
        if currP <> undefined
            currTarget = currP * f0_multiplier + f0_offset
            
            if prevTarget <> undefined
                Select inner viewport: 0.8, 7.7, 4.6, 5.6
                Axes: 0, vizDuration, pitchMin, pitchMax
                Draw line: prevT, prevTarget, t, currTarget
            endif
            
            prevTarget = currTarget
        else
            prevTarget = undefined
        endif
        
        prevP = currP
        prevT = t
        t = t + step
    endwhile
    
    Colour: "Black"
    Line width: 0.5
    Draw inner box
    Marks left: 4, "yes", "yes", "no"
    
    Font size: 7
    Select outer viewport: 0, 0.8, 4.5, 5.7
    Axes: 0, 1, 0, 1
    Colour: "{0.3, 0.5, 0.8}"
    Text: 0.95, "right", 0.65, "half", "F0"
    Colour: "{0.8, 0.4, 0.2}"
    Text: 0.95, "right", 0.35, "half", "Target"
    
    # === PANEL 4: Waveform Comparison ===
    Select outer viewport: 0, 4, 5.8, 6.6
    Select inner viewport: 0.5, 3.8, 5.9, 6.5
    
    selectObject: monoSource
    Colour: "{0.5, 0.5, 0.7}"
    Draw: 0, vizDuration, 0, 0, "no", "Curve"
    Colour: "Black"
    Line width: 0.5
    Draw inner box
    
    Font size: 6
    Select outer viewport: 0, 0.5, 5.8, 6.6
    Axes: 0, 1, 0, 1
    Colour: "{0.4, 0.4, 0.6}"
    Text: 0.9, "right", 0.5, "half", "Orig"
    
    Select outer viewport: 4, 8, 5.8, 6.6
    Select inner viewport: 4.4, 7.7, 5.9, 6.5
    
    selectObject: outputSound
    Colour: "{0.5, 0.7, 0.5}"
    Draw: 0, vizDuration, 0, 0, "no", "Curve"
    Colour: "Black"
    Line width: 0.5
    Draw inner box
    
    Font size: 6
    Select outer viewport: 4, 4.4, 5.8, 6.6
    Axes: 0, 1, 0, 1
    Colour: "{0.4, 0.6, 0.4}"
    Text: 0.9, "right", 0.5, "half", "Filt"
    
    # === PANEL 5: Legend & Stats ===
    Select outer viewport: 0, 8, 6.7, 7.4
    Axes: 0, 1, 0, 1
    
    Font size: 6
    
    # Legend
    Colour: "{0.3, 0.6, 0.9}"
    Paint rectangle: "{0.3, 0.6, 0.9}", 0.02, 0.05, 0.6, 0.8
    Colour: "Black"
    Text: 0.06, "left", 0.7, "half", "F0 (detected)"
    
    Colour: "{0.9, 0.5, 0.2}"
    Paint rectangle: "{0.9, 0.5, 0.2}", 0.18, 0.21, 0.6, 0.8
    Colour: "Black"
    Text: 0.22, "left", 0.7, "half", "Target (F0×" + fixed$(f0_multiplier, 2) + ")"
    
    Colour: "{0.2, 0.9, 0.3}"
    Paint rectangle: "{0.2, 0.9, 0.3}", 0.40, 0.43, 0.6, 0.8
    Colour: "Black"
    Text: 0.44, "left", 0.7, "half", "Pitch overlay"
    
    # Stats
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.02, "left", 0.25, "half", "Mean F0: " + fixed$(meanPitch, 1) + " Hz"
    Text: 0.18, "left", 0.25, "half", "Target: " + fixed$(meanTarget, 1) + " Hz"
    Text: 0.36, "left", 0.25, "half", "Voiced: " + fixed$(voicedPercent, 0) + "%"
    Text: 0.50, "left", 0.25, "half", "Frames: " + string$(numFrames)
    Text: 0.64, "left", 0.25, "half", "Quality: " + qualityName$
    
    # === TIME AXIS ===
    Select outer viewport: 0, 8, 7.4, 7.7
    Select inner viewport: 0.8, 7.7, 7.45, 7.65
    
    Axes: 0, vizDuration, 0, 1
    Colour: "{0.3, 0.3, 0.4}"
    Line width: 1
    Draw line: 0, 0.7, vizDuration, 0.7
    
    Font size: 5
    if vizDuration > 6
        tickStep = 2
    elsif vizDuration > 3
        tickStep = 1
    else
        tickStep = 0.5
    endif
    
    t = 0
    while t <= vizDuration
        Draw line: t, 0.7, t, 0.3
        Text: t, "centre", 0.1, "half", fixed$(t, 1)
        t = t + tickStep
    endwhile
    
    Font size: 6
    Text: vizDuration / 2, "centre", -0.6, "half", "Time (s)"
    
    Font size: 10
    Line width: 1
    Colour: "Black"
    
    appendInfoLine: "  Visualization complete"
endif

# ============================================================
# CLEANUP
# ============================================================

removeObject: monoSource, pitch

# ============================================================
# OUTPUT
# ============================================================

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Output: ", originalName$, "_adaptive_EQ"
appendInfoLine: ""
appendInfoLine: "F0 Multiplier: ", fixed$(f0_multiplier, 2), "x"
appendInfoLine: "Mean F0: ", fixed$(meanPitch, 1), " Hz"
appendInfoLine: "Mean Target: ", fixed$(meanTarget, 1), " Hz"
appendInfoLine: ""

selectObject: outputSound

if play_result
    Play
endif

appendInfoLine: "Done!"