# ============================================================
# Praat AudioTools - Full_Wave_Rectifier.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Full-Wave Rectifier - converts all negative values to positive
#   using absolute value function. This classic analog effect
#   doubles the fundamental frequency and adds strong even harmonics,
#   creating buzzy, aggressive distortion.
#
# Changelog v0.2:
#   - Fixed input check
#   - Added visualization
#   - Added info output
# ============================================================

form Full-Wave Rectifier
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Default (0.95 peak)
        option Soft (0.8 peak)
        option Maximum (1.0 peak)
        option Custom (use setting below)
    
    comment === Output ===
    positive Scale_peak 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
duration = Get total duration
sr = Get sampling frequency

# === Apply Presets ===
if preset = 1
    scale_peak = 0.95
    presetName$ = "Default"
elsif preset = 2
    scale_peak = 0.8
    presetName$ = "Soft"
elsif preset = 3
    scale_peak = 1.0
    presetName$ = "Maximum"
else
    presetName$ = "Custom"
endif

# === Info ===
writeInfoLine: "=== Full-Wave Rectifier ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Effect: abs(x) - flips negative to positive"
appendInfoLine: "Result: Frequency doubling, even harmonics"
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

appendInfoLine: "Applying rectification..."

selectObject: original
Copy: originalName$ + "_rectified"
result = selected("Sound")

# Apply full-wave rectification (absolute value)
Formula: ~ abs(self)

# Scale to peak
Scale peak: scale_peak

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Full-Wave Rectifier: " + originalName$
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.6
    Select inner viewport: 0.6, 7.6, 0.7, 1.5
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.7, 2.7
    Select inner viewport: 0.6, 7.6, 1.8, 2.6
    selectObject: result
    Colour: "{0.6, 0.7, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Rectified"
    Text bottom: "yes", "Time (s)"
    
    # Zoomed comparison (show rectification clearly)
    zoomDur = min(0.02, duration)
    
    Select outer viewport: 0, 4, 2.9, 4.0
    Select inner viewport: 0.6, 3.8, 3.0, 3.9
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, zoomDur, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Orig (zoom)"
    
    Select outer viewport: 4, 8, 2.9, 4.0
    Select inner viewport: 4.4, 7.6, 3.0, 3.9
    selectObject: result
    Colour: "{0.6, 0.7, 0.5}"
    Draw: 0, zoomDur, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Rect (zoom)"
    Text bottom: "yes", "Time (s)"
    
    # Transfer function
    Select outer viewport: 0, 4, 4.2, 5.5
    Select inner viewport: 0.6, 3.8, 4.3, 5.4
    
    Axes: -1.2, 1.2, -0.2, 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", -1.2, 1.2, -0.2, 1.2
    
    # Grid
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: -1.2, 0, 1.2, 0
    Draw line: 0, -0.2, 0, 1.2
    
    # Linear reference (dotted)
    Dotted line
    Draw line: 0, 0, 1, 1
    Draw line: -1, 1, 0, 0
    Solid line
    
    # Draw abs() transfer function
    Colour: "{0.6, 0.7, 0.5}"
    Line width: 2
    # Negative side (flipped)
    Draw line: -1, 1, 0, 0
    # Positive side (unchanged)
    Draw line: 0, 0, 1, 1
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 5
    Text left: "yes", "Output"
    Text bottom: "yes", "Input"
    Text: 0, "centre", 1.35, "half", "y = |x|"
    
    # Spectral comparison
    Select outer viewport: 4, 8, 4.2, 5.5
    Select inner viewport: 4.4, 7.6, 4.3, 5.4
    
    # Get spectra
    selectObject: original
    specOrig = To Spectrum: "yes"
    selectObject: result
    specRect = To Spectrum: "yes"
    
    maxFreq = min(sr / 2, 5000)
    
    Axes: 0, maxFreq, 0, 80
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, maxFreq, 0, 80
    
    # Original spectrum (gray)
    selectObject: specOrig
    Colour: "{0.7, 0.7, 0.7}"
    Draw: 0, maxFreq, 0, 80, "no"
    
    # Rectified spectrum (green) - shows added harmonics
    selectObject: specRect
    Colour: "{0.6, 0.7, 0.5}"
    Line width: 1.5
    Draw: 0, maxFreq, 0, 80, "no"
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 5
    Text left: "yes", "Power (dB)"
    Text bottom: "yes", "Frequency (Hz)"
    Text: maxFreq/2, "centre", 75, "half", "Gray=Orig, Green=Rect (×2 freq)"
    
    removeObject: specOrig, specRect
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result