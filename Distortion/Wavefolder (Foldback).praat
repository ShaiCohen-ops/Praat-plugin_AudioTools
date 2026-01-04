# ============================================================
# Praat AudioTools - Foldback and Wavefolding.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Foldback and Wavefolding
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# Nonlinear distortion through signal folding - Vectorized version

form Foldback and Wavefolding
    comment === Preset Selection ===
    optionmenu Preset: 1
        option Custom
        option Soft Fold (Subtle)
        option Hard Fold (Aggressive)
        option Bipolar Fold
        option Asymmetric Fold
        option Multi-Fold (Harmonics)
        option Tape Saturation Style
        option Digital Crush
        option Oscillating Fold
    comment === Foldback Parameters ===
    real Threshold_(0-1) 0.5
    real Input_gain_(dB) 0.0
    real Fold_depth_(0-1) 1.0
    real Asymmetry_(-1_to_1) 0.0
    comment === Waveshaping ===
    integer Fold_iterations 1
    boolean Bipolar_folding 1
    real Smoothing_(0-1) 0.0
    comment === Output ===
    real Output_gain_(dB) 0.0
    boolean DC_offset_removal 1
endform

# Apply preset values
if preset = 2
    threshold = 0.7
    input_gain = 3.0
    fold_depth = 0.6
    asymmetry = 0.0
    fold_iterations = 1
    bipolar_folding = 1
    smoothing = 0.3
    output_gain = -3.0
elsif preset = 3
    threshold = 0.3
    input_gain = 12.0
    fold_depth = 1.0
    asymmetry = 0.0
    fold_iterations = 1
    bipolar_folding = 1
    smoothing = 0.0
    output_gain = -6.0
elsif preset = 4
    threshold = 0.5
    input_gain = 6.0
    fold_depth = 1.0
    asymmetry = 0.0
    fold_iterations = 2
    bipolar_folding = 1
    smoothing = 0.1
    output_gain = -4.0
elsif preset = 5
    threshold = 0.6
    input_gain = 8.0
    fold_depth = 0.85
    asymmetry = 0.6
    fold_iterations = 1
    bipolar_folding = 0
    smoothing = 0.15
    output_gain = -5.0
elsif preset = 6
    threshold = 0.4
    input_gain = 10.0
    fold_depth = 1.0
    asymmetry = 0.0
    fold_iterations = 3
    bipolar_folding = 1
    smoothing = 0.0
    output_gain = -8.0
elsif preset = 7
    threshold = 0.65
    input_gain = 4.0
    fold_depth = 0.5
    asymmetry = 0.2
    fold_iterations = 1
    bipolar_folding = 1
    smoothing = 0.5
    output_gain = -2.0
elsif preset = 8
    threshold = 0.25
    input_gain = 15.0
    fold_depth = 1.0
    asymmetry = 0.0
    fold_iterations = 2
    bipolar_folding = 0
    smoothing = 0.0
    output_gain = -10.0
elsif preset = 9
    threshold = 0.55
    input_gain = 7.0
    fold_depth = 0.9
    asymmetry = -0.3
    fold_iterations = 2
    bipolar_folding = 1
    smoothing = 0.2
    output_gain = -5.0
endif

# Get selected sound
sound = selected("Sound")
name$ = selected$("Sound")
duration = Get total duration
sampling_rate = Get sampling frequency
num_channels = Get number of channels

# Convert gains to linear
input_gain_linear = 10^(input_gain/20)
output_gain_linear = 10^(output_gain/20)

# Calculate asymmetric thresholds
if asymmetry >= 0
    threshold_pos = threshold * (1 - asymmetry)
    threshold_neg = threshold
else
    threshold_pos = threshold
    threshold_neg = threshold * (1 + asymmetry)
endif

# Copy sound for processing
selectObject: sound
Copy: name$ + "_fold"
result = selected("Sound")

# Apply input gain (vectorized)
Formula: "self * input_gain_linear"

# Apply foldback iterations
for iteration from 1 to fold_iterations
    selectObject: result
    
    if bipolar_folding
        # Bipolar folding (vectorized with Formula)
        # Positive folding
        Formula: "if self > threshold_pos then threshold_pos - (self - threshold_pos) * fold_depth else self fi"
        # Negative folding
        Formula: "if self < -threshold_neg then -threshold_neg + (abs(self) - threshold_neg) * fold_depth else self fi"
    else
        # Unipolar folding (vectorized)
        Formula: "if abs(self) > threshold then (if self > 0 then threshold - (self - threshold) * fold_depth else -threshold + (abs(self) - threshold) * fold_depth fi) else self fi"
    endif
endfor

# Apply smoothing (vectorized soft clipping)
if smoothing > 0
    selectObject: result
    smooth_amount = smoothing * 2
    Formula: "if abs(self) > (1 - smooth_amount) then self / (1 + abs(self) * smooth_amount) else self fi"
endif

# Apply output gain (vectorized)
selectObject: result
Formula: "self * output_gain_linear"

# DC offset removal
if dC_offset_removal
    Subtract mean
endif

# Final normalization check (prevent clipping)
max_amp = Get maximum: 0, 0, "Sinc70"
min_amp = Get minimum: 0, 0, "Sinc70"
peak = max(abs(max_amp), abs(min_amp))

if peak > 0.99
    Formula: "self * 0.99 / peak"
endif

# Select result
selectObject: result
Play