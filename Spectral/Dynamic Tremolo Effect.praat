# ============================================================
# Praat AudioTools - Dynamic_Tremolo_Effect.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Frequency-dependent tremolo
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

form Dynamic Tremolo Effect v1.0 (Optimized)
    optionmenu Preset: 1
        option Custom
        option Classic Tremolo
        option Deep Tremolo
        option Subtle Shimmer
        option Fast Flutter
        option Slow Pulse
        option High Cut Tremolo
        option Bass Wobble
        option Spectral Sweep
    comment === Performance ===
    optionmenu Speed_mode: 2
        option Full Quality (original sample rate)
        option Balanced (downsample to 22 kHz)
        option Fast (downsample to 11 kHz)
    comment === Tremolo Parameters ===
    positive Low_freq_cutoff 8000
    comment (Frequencies below this get tremolo)
    positive Tremolo_depth_min 0.3
    positive Tremolo_depth_max 0.7
    comment (Modulation range: min to min+max)
    positive Tremolo_rate 500
    comment (Higher = slower tremolo cycle)
    comment === High Frequency ===
    positive High_freq_gain 0.8
    comment (Gain for frequencies above cutoff)
    comment === Output ===
    positive Scale_peak 0.9
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS
# ============================================================

if preset = 2
    low_freq_cutoff = 8000
    tremolo_depth_min = 0.3
    tremolo_depth_max = 0.7
    tremolo_rate = 500
    high_freq_gain = 0.8
    presetName$ = "ClassicTremolo"
elsif preset = 3
    low_freq_cutoff = 8000
    tremolo_depth_min = 0.2
    tremolo_depth_max = 0.9
    tremolo_rate = 400
    high_freq_gain = 0.7
    presetName$ = "DeepTremolo"
elsif preset = 4
    low_freq_cutoff = 10000
    tremolo_depth_min = 0.5
    tremolo_depth_max = 0.3
    tremolo_rate = 600
    high_freq_gain = 0.9
    presetName$ = "SubtleShimmer"
elsif preset = 5
    low_freq_cutoff = 6000
    tremolo_depth_min = 0.3
    tremolo_depth_max = 0.6
    tremolo_rate = 150
    high_freq_gain = 0.8
    presetName$ = "FastFlutter"
elsif preset = 6
    low_freq_cutoff = 8000
    tremolo_depth_min = 0.2
    tremolo_depth_max = 0.8
    tremolo_rate = 1000
    high_freq_gain = 0.85
    presetName$ = "SlowPulse"
elsif preset = 7
    low_freq_cutoff = 4000
    tremolo_depth_min = 0.4
    tremolo_depth_max = 0.5
    tremolo_rate = 500
    high_freq_gain = 0.4
    presetName$ = "HighCutTremolo"
elsif preset = 8
    low_freq_cutoff = 2000
    tremolo_depth_min = 0.2
    tremolo_depth_max = 0.8
    tremolo_rate = 300
    high_freq_gain = 1.0
    presetName$ = "BassWobble"
elsif preset = 9
    low_freq_cutoff = 12000
    tremolo_depth_min = 0.1
    tremolo_depth_max = 0.9
    tremolo_rate = 800
    high_freq_gain = 0.6
    presetName$ = "SpectralSweep"
else
    presetName$ = "Custom"
endif

# Set target sample rate
if speed_mode = 1
    targetSR = 0
    speedStr$ = "Full Quality"
elsif speed_mode = 2
    targetSR = 22050
    speedStr$ = "Balanced"
else
    targetSR = 11025
    speedStr$ = "Fast"
endif

# ============================================================
# SETUP
# ============================================================

selectObject: originalID
duration = Get total duration
sampleRate = Get sampling frequency
nyquist = sampleRate / 2

# Validate cutoff
if low_freq_cutoff > nyquist
    low_freq_cutoff = nyquist * 0.9
endif

startTime = stopwatch

clearinfo
writeInfoLine: "╔══════════════════════════════════════════════════════════════╗"
writeInfoLine: "║        DYNAMIC TREMOLO v1.0 (Optimized)                     ║"
writeInfoLine: "╚══════════════════════════════════════════════════════════════╝"
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Speed: ", speedStr$
appendInfoLine: "Duration: ", fixed$(duration, 3), " s"
appendInfoLine: "Sample rate: ", sampleRate, " Hz"
appendInfoLine: ""
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Cutoff: ", low_freq_cutoff, " Hz"
appendInfoLine: "Depth: ", tremolo_depth_min, " to ", tremolo_depth_min + tremolo_depth_max
appendInfoLine: "Rate: ", tremolo_rate
appendInfoLine: "High freq gain: ", high_freq_gain
appendInfoLine: ""

# ============================================================
# PROCESS
# ============================================================

# Copy for processing
selectObject: originalID
Copy: "working"
workingID = selected("Sound")

# === OPTIONAL DOWNSAMPLING ===
if targetSR > 0 and sampleRate > targetSR
    appendInfoLine: "[SPEED] Downsampling to ", targetSR, " Hz..."
    selectObject: workingID
    Resample: targetSR, 50
    resampledID = selected("Sound")
    removeObject: workingID
    workingID = resampledID
    workingSR = targetSR
    workingNyquist = workingSR / 2
    
    # Adjust cutoff if needed
    if low_freq_cutoff > workingNyquist
        low_freq_cutoff = workingNyquist * 0.9
    endif
else
    workingSR = sampleRate
endif

appendInfo: "Processing tremolo..."

# Convert to spectrum
selectObject: workingID
To Spectrum: "yes"
spectrumID = selected("Spectrum")

# Build formula strings
cutoffStr$ = string$(low_freq_cutoff)
minStr$ = fixed$(tremolo_depth_min, 6)
maxStr$ = fixed$(tremolo_depth_max, 6)
rateStr$ = fixed$(tremolo_rate, 6)
highStr$ = fixed$(high_freq_gain, 6)

# Apply dynamic tremolo
selectObject: spectrumID
Formula: "if col < " + cutoffStr$ + " then self[1, col] * (" + minStr$ + " + " + maxStr$ + " * cos(col / " + rateStr$ + ")^2) else self[1, col] * " + highStr$ + " endif"

# Convert back to sound
selectObject: spectrumID
To Sound
resultID = selected("Sound")

# === UPSAMPLE IF NEEDED ===
if targetSR > 0 and sampleRate > targetSR
    appendInfoLine: " upsampling..."
    selectObject: resultID
    Resample: sampleRate, 50
    upsampledID = selected("Sound")
    removeObject: resultID
    resultID = upsampledID
endif

# Rename and scale
selectObject: resultID
Rename: originalName$ + "_tremolo_" + presetName$
Scale peak: scale_peak

appendInfoLine: " done"

processingTime = stopwatch - startTime

# ============================================================
# VISUALIZATION (OPTIMIZED)
# ============================================================

if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    # Get spectra for comparison
    selectObject: originalID
    To Spectrum: "yes"
    origSpecID = selected("Spectrum")
    
    selectObject: resultID
    To Spectrum: "yes"
    resSpecID = selected("Spectrum")
    
    Erase all
    
    # Title
    Select outer viewport: 1, 8, 0, 0.5
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Dynamic Tremolo: " + originalName$ + " [" + presetName$ + "]"
    
    # Original waveform
    Select outer viewport: 0, 4, 0.6, 2.0
    Select inner viewport: 0.5, 3.7, 0.75, 1.85
    
    selectObject: originalID
    Colour: "{0.7, 0.7, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Select outer viewport: 0.1, 8, 1.5, 1.8
    Text top: "no", "Original"
    Text left: "yes", "Amp"
    
    # Processed waveform
    Select outer viewport: 4, 8, 0.6, 2.0
    Select inner viewport: 4.5, 7.7, 0.75, 1.85
    
    selectObject: resultID
    Colour: "{0.2, 0.5, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text top: "no", "With Tremolo"
    Text left: "yes", "Amp"
    
    # Spectrum comparison
    Select outer viewport: 0, 8, 2.2, 4.0
    Select inner viewport: 0.6, 7.6, 2.4, 3.8
    
    selectObject: origSpecID
    Colour: "{0.7, 0.7, 0.7}"
    Line width: 1
    Draw: 0, 10000, 0, 80, "no"
    
    selectObject: resSpecID
    Colour: "{0.2, 0.5, 0.8}"
    Line width: 2
    Draw: 0, 10000, 0, 80, "no"
    
    # Mark cutoff
    Axes: 0, 10000, 0, 80
    Colour: "{0.9, 0.3, 0.3}"
    Line width: 1
    Dotted line
    Draw line: low_freq_cutoff, 0, low_freq_cutoff, 80
    Solid line
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 9
    Text top: "no", "Spectrum (gray=original, blue=tremolo)"
    Text left: "yes", "dB"
    Text bottom: "yes", "Frequency (Hz)"
    
    # Tremolo modulation curve (OPTIMIZED: 200 points instead of 500)
    Select outer viewport: 0, 8, 4.2, 5.8
    Select inner viewport: 0.6, 7.6, 4.4, 5.6
    
    maxFreq = low_freq_cutoff * 1.2
    Axes: 0, maxFreq, 0, 1.2
    
    # Draw tremolo curve
    Colour: "{0.9, 0.5, 0.2}"
    Line width: 2
    
    numPoints = 200
    for i from 0 to numPoints - 1
        f1 = maxFreq * i / numPoints
        f2 = maxFreq * (i + 1) / numPoints
        
        if f1 < low_freq_cutoff
            gain1 = tremolo_depth_min + tremolo_depth_max * cos(f1 / tremolo_rate)^2
        else
            gain1 = high_freq_gain
        endif
        
        if f2 < low_freq_cutoff
            gain2 = tremolo_depth_min + tremolo_depth_max * cos(f2 / tremolo_rate)^2
        else
            gain2 = high_freq_gain
        endif
        
        Draw line: f1, gain1, f2, gain2
    endfor
    
    # Mark cutoff on tremolo curve
    Colour: "{0.9, 0.3, 0.3}"
    Line width: 1
    Dotted line
    Draw line: low_freq_cutoff, 0, low_freq_cutoff, 1.2
    Solid line
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Frequency-Dependent Gain (tremolo modulation)"
    Text left: "yes", "Gain"
    Text bottom: "yes", "Frequency (Hz)"
    
    # Legend
    Font size: 7
    Colour: "{0.9, 0.3, 0.3}"
    Text: low_freq_cutoff, "centre", 1.15, "half", "cutoff"
    
    # Info panel
    Select outer viewport: 0, 8, 5.9, 6.4
    Select inner viewport: 0.5, 7.7, 5.95, 6.35
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Font size: 9
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.5, "half", "Cutoff: " + string$(low_freq_cutoff) + " Hz"
    Text: 0.25, "left", 0.5, "half", "Depth: " + fixed$(tremolo_depth_min, 2) + "-" + fixed$(tremolo_depth_min + tremolo_depth_max, 2)
    Text: 0.48, "left", 0.5, "half", "Rate: " + fixed$(tremolo_rate, 0)
    Text: 0.65, "left", 0.5, "half", speedStr$
    Text: 0.82, "left", 0.5, "half", "Time: " + fixed$(processingTime, 2) + "s"
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    
    removeObject: origSpecID, resSpecID
endif

# ============================================================
# CLEANUP
# ============================================================

removeObject: spectrumID, workingID

# ============================================================
# OUTPUT
# ============================================================

appendInfoLine: ""
appendInfoLine: "╔══════════════════════════════════════════════════════════════╗"
appendInfoLine: "║                      COMPLETE                                ║"
appendInfoLine: "╚══════════════════════════════════════════════════════════════╝"
appendInfoLine: "Processing time: ", fixed$(processingTime, 2), " seconds"
appendInfoLine: "Output: ", originalName$, "_tremolo_", presetName$

if play_result
    selectObject: resultID
    Play
endif

selectObject: resultID
 