# ============================================================
# Praat AudioTools - Dynamic_Tremolo_Effect.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Fixed syntax, added visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Frequency-dependent tremolo - applies spectral modulation
#   with different rates/depths across the frequency spectrum.
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

form Dynamic Tremolo Effect v0.2
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
    # Classic Tremolo
    low_freq_cutoff = 8000
    tremolo_depth_min = 0.3
    tremolo_depth_max = 0.7
    tremolo_rate = 500
    high_freq_gain = 0.8
    presetName$ = "ClassicTremolo"
elsif preset = 3
    # Deep Tremolo
    low_freq_cutoff = 8000
    tremolo_depth_min = 0.2
    tremolo_depth_max = 0.9
    tremolo_rate = 400
    high_freq_gain = 0.7
    presetName$ = "DeepTremolo"
elsif preset = 4
    # Subtle Shimmer
    low_freq_cutoff = 10000
    tremolo_depth_min = 0.5
    tremolo_depth_max = 0.3
    tremolo_rate = 600
    high_freq_gain = 0.9
    presetName$ = "SubtleShimmer"
elsif preset = 5
    # Fast Flutter
    low_freq_cutoff = 6000
    tremolo_depth_min = 0.3
    tremolo_depth_max = 0.6
    tremolo_rate = 150
    high_freq_gain = 0.8
    presetName$ = "FastFlutter"
elsif preset = 6
    # Slow Pulse
    low_freq_cutoff = 8000
    tremolo_depth_min = 0.2
    tremolo_depth_max = 0.8
    tremolo_rate = 1000
    high_freq_gain = 0.85
    presetName$ = "SlowPulse"
elsif preset = 7
    # High Cut Tremolo
    low_freq_cutoff = 4000
    tremolo_depth_min = 0.4
    tremolo_depth_max = 0.5
    tremolo_rate = 500
    high_freq_gain = 0.4
    presetName$ = "HighCutTremolo"
elsif preset = 8
    # Bass Wobble
    low_freq_cutoff = 2000
    tremolo_depth_min = 0.2
    tremolo_depth_max = 0.8
    tremolo_rate = 300
    high_freq_gain = 1.0
    presetName$ = "BassWobble"
elsif preset = 9
    # Spectral Sweep
    low_freq_cutoff = 12000
    tremolo_depth_min = 0.1
    tremolo_depth_max = 0.9
    tremolo_rate = 800
    high_freq_gain = 0.6
    presetName$ = "SpectralSweep"
else
    presetName$ = "Custom"
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

clearinfo
writeInfoLine: "=== Dynamic Tremolo Effect v0.2 ==="
appendInfoLine: "Input: ", originalName$
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

appendInfo: "Processing..."

# Convert to spectrum
selectObject: originalID
spectrumID = To Spectrum: "yes"

# Build formula strings
cutoffStr$ = string$(low_freq_cutoff)
minStr$ = fixed$(tremolo_depth_min, 6)
maxStr$ = fixed$(tremolo_depth_max, 6)
rateStr$ = fixed$(tremolo_rate, 6)
highStr$ = fixed$(high_freq_gain, 6)

# Apply dynamic tremolo in frequency domain
# Below cutoff: modulate with cos^2 function
# Above cutoff: apply flat gain
selectObject: spectrumID
Formula: "if col < " + cutoffStr$ + " then self[1, col] * (" + minStr$ + " + " + maxStr$ + " * cos(col / " + rateStr$ + ")^2) else self[1, col] * " + highStr$ + " endif"

# Convert back to sound
selectObject: spectrumID
resultID = To Sound

# Rename and scale
selectObject: resultID
Rename: originalName$ + "_tremolo_" + presetName$
Scale peak: scale_peak

appendInfoLine: " done"

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    # Get spectra for comparison
    selectObject: originalID
    origSpecID = To Spectrum: "yes"
    
    selectObject: resultID
    resSpecID = To Spectrum: "yes"
    
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0, 0.5
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
    
    # Tremolo modulation curve
    Select outer viewport: 0, 8, 4.2, 5.8
    Select inner viewport: 0.6, 7.6, 4.4, 5.6
    
    maxFreq = low_freq_cutoff * 1.2
    Axes: 0, maxFreq, 0, 1.2
    
    # Draw tremolo curve (below cutoff)
    Colour: "{0.9, 0.5, 0.2}"
    Line width: 2
    
    numPoints = 500
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
    Text: 0.22, "left", 0.5, "half", "Depth: " + fixed$(tremolo_depth_min, 2) + "-" + fixed$(tremolo_depth_min + tremolo_depth_max, 2)
    Text: 0.48, "left", 0.5, "half", "Rate: " + fixed$(tremolo_rate, 0)
    Text: 0.68, "left", 0.5, "half", "High gain: " + fixed$(high_freq_gain, 2)
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    
    removeObject: origSpecID, resSpecID
endif

# ============================================================
# CLEANUP
# ============================================================

removeObject: spectrumID

# ============================================================
# OUTPUT
# ============================================================

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: ""
appendInfoLine: "Created: ", originalName$, "_tremolo_", presetName$

if play_result
    selectObject: resultID
    Play
endif

selectObject: originalID
plusObject: resultID