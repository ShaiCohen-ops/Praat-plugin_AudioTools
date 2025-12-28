# ============================================================
# Praat AudioTools - Fractal Spectral Hologram
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.2 (2025)
# License: MIT License
#
# Description:
#   Creates holographic/crystalline textures by processing the
#   spectrogram as a 2D image: blur, sharpen, and fractal zoom
#   transformations are applied, then used to modulate noise.
#   Results in shimmering, frozen, or shattered sonic textures.
#
# Usage:
#   Select a Sound object in Praat and run this script.
# ============================================================

form Fractal Spectral Hologram
    comment === Presets ===
    optionmenu Preset: 1
        option Custom (use settings below)
        option Subtle Shimmer
        option Crystal Echo
        option Fractal Storm
        option Temporal Shatter
        option Holographic Freeze
        option Quantum Blur
        option Granular Collapse
    comment === Analysis ===
    real Window_length_ms 40
    real Time_step_ms 5
    comment === Texture Processing ===
    real Blur_strength 0.5
    real Sharpen_strength 0.3
    real Fractal_zoom 1.2
    comment === Output ===
    real Output_gain_dB 0
    real Dry_wet 1.0
    comment (0 = dry, 1 = wet)
    positive scale_peak 0.95
    boolean Play_output 1
endform

# --- APPLY PRESETS ---
if preset = 2
    window_length_ms = 25
    time_step_ms = 6
    blur_strength = 0.25
    sharpen_strength = 0.35
    fractal_zoom = 1.15
elsif preset = 3
    window_length_ms = 45
    time_step_ms = 4
    blur_strength = 0.4
    sharpen_strength = 0.8
    fractal_zoom = 1.5
elsif preset = 4
    window_length_ms = 80
    time_step_ms = 25
    blur_strength = 0.75
    sharpen_strength = 1.2
    fractal_zoom = 2.3
elsif preset = 5
    window_length_ms = 35
    time_step_ms = 30
    blur_strength = 0.15
    sharpen_strength = 1.5
    fractal_zoom = 2.8
elsif preset = 6
    window_length_ms = 150
    time_step_ms = 15
    blur_strength = 0.85
    sharpen_strength = 0.6
    fractal_zoom = 1.9
elsif preset = 7
    window_length_ms = 120
    time_step_ms = 40
    blur_strength = 0.95
    sharpen_strength = 0.1
    fractal_zoom = 2.6
elsif preset = 8
    window_length_ms = 15
    time_step_ms = 12
    blur_strength = 0.5
    sharpen_strength = 1.8
    fractal_zoom = 2.2
endif

# --- INPUT VALIDATION ---
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

orig_sound = selected("Sound")
orig_name$ = selected$("Sound")

selectObject: orig_sound
n_channels = Get number of channels
duration = Get total duration
sf = Get sampling frequency

writeInfoLine: "=== Fractal Spectral Hologram ==="
appendInfoLine: "Duration: ", fixed$(duration, 2), " s"
appendInfoLine: "Window: ", window_length_ms, " ms"
appendInfoLine: "Blur: ", blur_strength, " | Sharpen: ", sharpen_strength
appendInfoLine: "Zoom: ", fractal_zoom
appendInfoLine: ""

# Force mono
if n_channels > 1
    input = Convert to mono
else
    input = Copy: "mono_temp"
endif

selectObject: input
win_sec = window_length_ms / 1000
step_sec = time_step_ms / 1000

# --- STEP 1: ANALYSIS ---
appendInfoLine: "Analyzing spectrum..."

selectObject: input
spectrogram = To Spectrogram: win_sec, 5000, step_sec, 20, "Gaussian"

selectObject: spectrogram
hologram = To Matrix
Rename: "hologram"
removeObject: spectrogram

# Get dimensions
selectObject: hologram
nr = Get number of rows
nc = Get number of columns

# Logarithmic scaling (dB)
selectObject: hologram
Formula: "if self > 0.000001 then 10 * log10(self) + 100 else 0 fi"

# --- STEP 2: TEXTURE PROCESSING ---
appendInfoLine: "Processing texture..."

# 2a. Blur (with boundary protection)
selectObject: hologram
blurred = Copy: "blurred"

blur_inv = 1 - blur_strength
blurStr$ = fixed$(blur_strength, 4)
invStr$ = fixed$(blur_inv, 4)

# Horizontal blur (protect col boundaries)
selectObject: blurred
Formula: "if col > 1 and col < ncol then self * " + blurStr$ + " + (self[row, col-1] * 0.25 + self * 0.5 + self[row, col+1] * 0.25) * " + invStr$ + " else self fi"

# Vertical blur (protect row boundaries)
Formula: "if row > 1 and row < nrow then self * " + blurStr$ + " + (self[row-1, col] * 0.25 + self * 0.5 + self[row+1, col] * 0.25) * " + invStr$ + " else self fi"

# 2b. Sharpen (unsharp mask)
selectObject: hologram
sharpened = Copy: "sharpened"
sharpStr$ = fixed$(sharpen_strength, 4)

selectObject: sharpened
Formula: "Matrix_hologram[row, col] + " + sharpStr$ + " * (Matrix_hologram[row, col] - Matrix_blurred[row, col])"

# 2c. Fractal Zoom (from center)
selectObject: sharpened
zoomed = Copy: "zoomed"

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
selectObject: zoomed
Formula: "Matrix_sharpened[max(1, min(nrow, " + crStr$ + " + (row - " + crStr$ + ") * " + izStr$ + ")), max(1, min(ncol, " + ccStr$ + " + (col - " + ccStr$ + ") * " + izStr$ + "))] * 0.7 + self * 0.3"

processed = zoomed
removeObject: blurred, sharpened

# --- STEP 3: RECONSTRUCTION ---
appendInfoLine: "Reconstructing audio..."

# Create carrier noise
noise = Create Sound from formula: "noise", 1, 0, duration, sf, "randomGauss(0, 0.2)"
noise_spec = To Spectrogram: win_sec, 5000, step_sec, 20, "Gaussian"

# Get dimensions for mapping
selectObject: processed
nr_holo = Get number of rows
nc_holo = Get number of columns

selectObject: noise_spec
temp_mat = To Matrix
nr_spec = Get number of rows
nc_spec = Get number of columns
removeObject: temp_mat

# Calculate mapping ratios
r_ratio = nr_holo / nr_spec
c_ratio = nc_holo / nc_spec

rrStr$ = fixed$(r_ratio, 6)
crStr$ = fixed$(c_ratio, 6)

# Apply processed spectrum to noise
selectObject: noise_spec
Formula: "self * (10^((Matrix_zoomed[max(1, min(" + string$(nr_holo) + ", row * " + rrStr$ + ")), max(1, min(" + string$(nc_holo) + ", col * " + crStr$ + "))] - 100) / 10))"

# Convert back to sound
selectObject: noise_spec
wet_sound = To Sound: sf
Rename: "wet"

# --- STEP 4: MIX ---
appendInfoLine: "Mixing..."

# Trim wet to match original duration
selectObject: wet_sound
dur_wet = Get total duration
if dur_wet > duration
    wet_trim = Extract part: 0, duration, "rectangular", 1, "no"
    removeObject: wet_sound
    wet_sound = wet_trim
    selectObject: wet_sound
    Rename: "wet"
endif

# Scale wet
selectObject: wet_sound
Scale peak: 0.9

# Create dry copy
selectObject: orig_sound
if n_channels > 1
    dry_sound = Convert to mono
else
    dry_sound = Copy: "dry"
endif
Rename: "dry"

# Mix
wetStr$ = fixed$(dry_wet, 4)
dryStr$ = fixed$(1 - dry_wet, 4)

selectObject: dry_sound
final = Copy: orig_name$ + "_hologram"

selectObject: final
Formula: "self * " + dryStr$ + " + Sound_wet[] * " + wetStr$

# Apply gain
gain_lin = 10^(output_gain_dB / 20)
gainStr$ = fixed$(gain_lin, 6)
Formula: "self * " + gainStr$

# Final scale
selectObject: final
Scale peak: scale_peak

# --- CLEANUP ---
removeObject: input, hologram, processed, noise, noise_spec, wet_sound, dry_sound

appendInfoLine: ""
appendInfoLine: "Complete!"

selectObject: final
if play_output
    Play
endif