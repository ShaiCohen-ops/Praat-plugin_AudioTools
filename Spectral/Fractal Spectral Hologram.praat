# ============================================================
# Praat AudioTools - Fractal_Spectral_Hologram.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.3 (2025) - Fixed syntax, added visualization
# License: MIT License
#
# Description:
#   Creates holographic/crystalline textures by processing the
#   spectrogram as a 2D image: blur, sharpen, and fractal zoom
#   transformations are applied, then used to modulate noise.
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

form Fractal Spectral Hologram v0.3
    optionmenu Preset: 1
        option Custom
        option Subtle Shimmer
        option Crystal Echo
        option Fractal Storm
        option Temporal Shatter
        option Holographic Freeze
        option Quantum Blur
        option Granular Collapse
    comment === Analysis ===
    positive Window_length_ms 40
    positive Time_step_ms 5
    comment === Texture Processing ===
    real Blur_strength 0.5
    real Sharpen_strength 0.3
    positive Fractal_zoom 1.2
    comment === Output ===
    real Output_gain_dB 0
    real Dry_wet 1.0
    comment (0 = dry, 1 = wet)
    positive Scale_peak 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS
# ============================================================

if preset = 2
    window_length_ms = 25
    time_step_ms = 6
    blur_strength = 0.25
    sharpen_strength = 0.35
    fractal_zoom = 1.15
    presetName$ = "SubtleShimmer"
elsif preset = 3
    window_length_ms = 45
    time_step_ms = 4
    blur_strength = 0.4
    sharpen_strength = 0.8
    fractal_zoom = 1.5
    presetName$ = "CrystalEcho"
elsif preset = 4
    window_length_ms = 80
    time_step_ms = 25
    blur_strength = 0.75
    sharpen_strength = 1.2
    fractal_zoom = 2.3
    presetName$ = "FractalStorm"
elsif preset = 5
    window_length_ms = 35
    time_step_ms = 30
    blur_strength = 0.15
    sharpen_strength = 1.5
    fractal_zoom = 2.8
    presetName$ = "TemporalShatter"
elsif preset = 6
    window_length_ms = 150
    time_step_ms = 15
    blur_strength = 0.85
    sharpen_strength = 0.6
    fractal_zoom = 1.9
    presetName$ = "HolographicFreeze"
elsif preset = 7
    window_length_ms = 120
    time_step_ms = 40
    blur_strength = 0.95
    sharpen_strength = 0.1
    fractal_zoom = 2.6
    presetName$ = "QuantumBlur"
elsif preset = 8
    window_length_ms = 15
    time_step_ms = 12
    blur_strength = 0.5
    sharpen_strength = 1.8
    fractal_zoom = 2.2
    presetName$ = "GranularCollapse"
else
    presetName$ = "Custom"
endif

# ============================================================
# SETUP
# ============================================================

selectObject: originalID
numChannels = Get number of channels
duration = Get total duration
sampleRate = Get sampling frequency

clearinfo
writeInfoLine: "=== Fractal Spectral Hologram v0.3 ==="
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Duration: ", fixed$(duration, 2), " s"
appendInfoLine: ""
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Window: ", window_length_ms, " ms"
appendInfoLine: "Blur: ", blur_strength, " | Sharpen: ", sharpen_strength
appendInfoLine: "Zoom: ", fractal_zoom
appendInfoLine: ""

# Convert to mono
if numChannels > 1
    selectObject: originalID
    inputID = Convert to mono
else
    selectObject: originalID
    inputID = Copy: "mono_temp"
endif

win_sec = window_length_ms / 1000
step_sec = time_step_ms / 1000

# ============================================================
# STEP 1: ANALYSIS
# ============================================================

appendInfo: "Analyzing spectrum..."

selectObject: inputID
spectrogramID = To Spectrogram: win_sec, 5000, step_sec, 20, "Gaussian"

selectObject: spectrogramID
hologramID = To Matrix
Rename: "hologram"
removeObject: spectrogramID

# Get dimensions
selectObject: hologramID
nr = Get number of rows
nc = Get number of columns

# Logarithmic scaling (dB)
selectObject: hologramID
Formula: "if self > 0.000001 then 10 * log10(self) + 100 else 0 endif"

appendInfoLine: " done (", nr, "x", nc, ")"

# ============================================================
# STEP 2: TEXTURE PROCESSING
# ============================================================

appendInfo: "Processing texture..."

# 2a. Blur (with boundary protection)
selectObject: hologramID
blurredID = Copy: "blurred"

blur_inv = 1 - blur_strength
blurStr$ = fixed$(blur_strength, 4)
invStr$ = fixed$(blur_inv, 4)

# Horizontal blur
selectObject: blurredID
Formula: "if col > 1 and col < ncol then self * " + blurStr$ + " + (self[row, col-1] * 0.25 + self * 0.5 + self[row, col+1] * 0.25) * " + invStr$ + " else self endif"

# Vertical blur
Formula: "if row > 1 and row < nrow then self * " + blurStr$ + " + (self[row-1, col] * 0.25 + self * 0.5 + self[row+1, col] * 0.25) * " + invStr$ + " else self endif"

# 2b. Sharpen (unsharp mask)
selectObject: hologramID
sharpenedID = Copy: "sharpened"
sharpStr$ = fixed$(sharpen_strength, 4)

selectObject: sharpenedID
Formula: "Matrix_hologram[row, col] + " + sharpStr$ + " * (Matrix_hologram[row, col] - Matrix_blurred[row, col])"

# 2c. Fractal Zoom (from center)
selectObject: sharpenedID
zoomedID = Copy: "zoomed"

cr = nr / 2
cc = nc / 2

if fractal_zoom <= 0
    fractal_zoom = 1
endif
inv_zoom = 1 / fractal_zoom

crStr$ = fixed$(cr, 2)
ccStr$ = fixed$(cc, 2)
izStr$ = fixed$(inv_zoom, 6)

# Zoom with bounds clamping
selectObject: zoomedID
Formula: "Matrix_sharpened[max(1, min(nrow, " + crStr$ + " + (row - " + crStr$ + ") * " + izStr$ + ")), max(1, min(ncol, " + ccStr$ + " + (col - " + ccStr$ + ") * " + izStr$ + "))] * 0.7 + self * 0.3"

processedID = zoomedID
removeObject: blurredID, sharpenedID

appendInfoLine: " done"

# ============================================================
# STEP 3: RECONSTRUCTION
# ============================================================

appendInfo: "Reconstructing audio..."

# Create carrier noise
noiseID = Create Sound from formula: "noise", 1, 0, duration, sampleRate, "randomGauss(0, 0.2)"
noiseSpecID = To Spectrogram: win_sec, 5000, step_sec, 20, "Gaussian"

# Get dimensions for mapping
selectObject: processedID
nr_holo = Get number of rows
nc_holo = Get number of columns

selectObject: noiseSpecID
tempMatID = To Matrix
nr_spec = Get number of rows
nc_spec = Get number of columns
removeObject: tempMatID

# Calculate mapping ratios
r_ratio = nr_holo / nr_spec
c_ratio = nc_holo / nc_spec

rrStr$ = fixed$(r_ratio, 6)
crStr2$ = fixed$(c_ratio, 6)
nrStr$ = string$(nr_holo)
ncStr$ = string$(nc_holo)

# Apply processed spectrum to noise
selectObject: noiseSpecID
Formula: "self * (10^((Matrix_zoomed[max(1, min(" + nrStr$ + ", row * " + rrStr$ + ")), max(1, min(" + ncStr$ + ", col * " + crStr2$ + "))] - 100) / 10))"

# Convert back to sound
selectObject: noiseSpecID
wetID = To Sound: sampleRate
Rename: "wet"

appendInfoLine: " done"

# ============================================================
# STEP 4: MIX
# ============================================================

appendInfo: "Mixing..."

# Trim wet to match original duration
selectObject: wetID
dur_wet = Get total duration
if dur_wet > duration
    wetTrimID = Extract part: 0, duration, "rectangular", 1, "no"
    removeObject: wetID
    wetID = wetTrimID
    selectObject: wetID
    Rename: "wet"
endif

# Scale wet
selectObject: wetID
Scale peak: 0.9

# Create dry copy
selectObject: originalID
if numChannels > 1
    dryID = Convert to mono
else
    dryID = Copy: "dry"
endif
Rename: "dry"

# Mix dry/wet
wetStr$ = fixed$(dry_wet, 4)
dryStr$ = fixed$(1 - dry_wet, 4)

selectObject: dryID
resultID = Copy: originalName$ + "_hologram_" + presetName$

# Get wet sound ID string for formula
wetIdStr$ = string$(wetID)

selectObject: resultID
Formula: "self * " + dryStr$ + " + Object_" + wetIdStr$ + "(x) * " + wetStr$

# Apply gain
gain_lin = 10^(output_gain_dB / 20)
gainStr$ = fixed$(gain_lin, 6)
Formula: "self * " + gainStr$

# Final scale
selectObject: resultID
Scale peak: scale_peak

appendInfoLine: " done"

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0, 0.5
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Fractal Spectral Hologram: " + originalName$ + " [" + presetName$ + "]"
    
    # Original waveform
    Select outer viewport: 0, 4, 0.6, 1.8
    Select inner viewport: 0.5, 3.7, 0.7, 1.7
    selectObject: originalID
    Colour: "{0.7, 0.7, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Original"
    
    # Processed waveform
    Select outer viewport: 4, 8, 0.6, 1.8
    Select inner viewport: 4.5, 7.7, 0.7, 1.7
    selectObject: resultID
    Colour: "{0.2, 0.5, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text top: "no", "Hologram"
    
    # Original spectrogram
    Select outer viewport: 0, 4, 2.0, 3.8
    selectObject: originalID
    origSpecID = To Spectrogram: 0.01, 5000, 0.002, 20, "Gaussian"
    selectObject: origSpecID
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Font size: 8
    Text top: "no", "Original Spectrogram"
    removeObject: origSpecID
    
    # Processed spectrogram
    Select outer viewport: 4, 8, 2.0, 3.8
    selectObject: resultID
    resSpecID = To Spectrogram: 0.01, 5000, 0.002, 20, "Gaussian"
    selectObject: resSpecID
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Text top: "no", "Hologram Spectrogram"
    removeObject: resSpecID
    
    # Hologram matrix visualization
    Select outer viewport: 0, 4, 4.0, 5.6
    selectObject: processedID
    Paint cells: 0, 0, 0, 0, 0, 0
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Processed Hologram Matrix"
    
    # Info panel
    Select outer viewport: 4, 8, 4.0, 5.6
    Select inner viewport: 4.4, 7.8, 4.2, 5.4
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Font size: 9
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.05, "left", 0.85, "half", "Window: " + fixed$(window_length_ms, 0) + " ms"
    Text: 0.05, "left", 0.65, "half", "Blur: " + fixed$(blur_strength, 2)
    Text: 0.05, "left", 0.45, "half", "Sharpen: " + fixed$(sharpen_strength, 2)
    Text: 0.05, "left", 0.25, "half", "Zoom: " + fixed$(fractal_zoom, 2) + "x"
    Text: 0.55, "left", 0.85, "half", "Dry/Wet: " + fixed$((1-dry_wet)*100, 0) + "/" + fixed$(dry_wet*100, 0) + "%"
    Text: 0.55, "left", 0.65, "half", "Gain: " + fixed$(output_gain_dB, 1) + " dB"
    Text: 0.55, "left", 0.45, "half", "Matrix: " + string$(nr) + "x" + string$(nc)
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
endif

# ============================================================
# CLEANUP
# ============================================================

removeObject: inputID, hologramID, processedID, noiseID, noiseSpecID, wetID, dryID

# ============================================================
# OUTPUT
# ============================================================

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: ""
appendInfoLine: "Created: ", originalName$, "_hologram_", presetName$

if play_result
    selectObject: resultID
    Play
endif
