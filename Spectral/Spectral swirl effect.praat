# ============================================================
# Praat AudioTools - Spectral Swirl Effect.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.2 (2025)
# License: MIT License
#
# Description:
#   Sinusoidal frequency bin shifting - creates swirling,
#   liquid-like spectral movement. Frequencies are displaced
#   up and down in a wave pattern across the spectrum.
#
# Usage:
#   Select a Sound object in Praat and run this script.
# ============================================================

form Spectral Swirl Effect
    optionmenu Preset: 1
        option Custom
        option Gentle Wobble
        option Liquid Metal
        option Alien Voice
        option Underwater Warble
        option Extreme Mangle
    comment === Swirl Parameters ===
    natural number_of_cycles 4
    comment (sinusoidal cycles across spectrum)
    positive maximum_bin_shift 100
    comment (max frequency displacement in bins)
    comment === Output ===
    positive scale_peak 0.95
    boolean play_after_processing 1
endform

# Apply presets
if preset = 2
    number_of_cycles = 2
    maximum_bin_shift = 30
elsif preset = 3
    number_of_cycles = 6
    maximum_bin_shift = 80
elsif preset = 4
    number_of_cycles = 8
    maximum_bin_shift = 150
elsif preset = 5
    number_of_cycles = 3
    maximum_bin_shift = 60
elsif preset = 6
    number_of_cycles = 12
    maximum_bin_shift = 300
endif

# Input validation
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

originalID = selected("Sound")
sound$ = selected$("Sound")
selectObject: originalID
original_sr = Get sampling frequency
duration = Get total duration
n_channels = Get number of channels

writeInfoLine: "=== Spectral Swirl Effect ==="
appendInfoLine: "Duration: ", fixed$(duration, 2), " s"
appendInfoLine: "Cycles: ", number_of_cycles
appendInfoLine: "Max shift: ", maximum_bin_shift, " bins"
appendInfoLine: ""

# Convert to mono
selectObject: originalID
if n_channels > 1
    workingID = Convert to mono
else
    workingID = Copy: "working"
endif

# To spectrum
appendInfoLine: "Analyzing spectrum..."
selectObject: workingID
origSpec = To Spectrum: "no"
Rename: "src"

# Convert to Matrix for processing (Spectrum doesn't have "Get number of columns")
selectObject: origSpec
origMat = To Matrix
Rename: "srcMat"

selectObject: origMat
nrows = Get number of rows
ncols = Get number of columns

# Create output matrix
selectObject: origMat
swirlMat = Copy: "swirlMat"

# Build the swirl formula
cycStr$ = string$(number_of_cycles)
shiftStr$ = string$(maximum_bin_shift)
twoPi$ = "6.283185307"
ncolStr$ = string$(ncols)

appendInfoLine: "Applying swirl..."

# Shift bins sinusoidally, clamp to valid range
selectObject: swirlMat
Formula: "Matrix_srcMat[row, max(1, min(" + ncolStr$ + ", round(col + " + shiftStr$ + " * sin(" + twoPi$ + " * " + cycStr$ + " * col / " + ncolStr$ + "))))]"

# Back to Spectrum then Sound
selectObject: swirlMat
swirlSpec = To Spectrum
Rename: "swirlSpec"

appendInfoLine: "Reconstructing..."
selectObject: swirlSpec
resultID = To Sound

# Trim to original duration
selectObject: resultID
resultDur = Get total duration
if resultDur > duration
    trimmed = Extract part: 0, duration, "rectangular", 1, "no"
    removeObject: resultID
    resultID = trimmed
endif

selectObject: resultID
Rename: sound$ + "_swirl"
Scale peak: scale_peak

# Cleanup
removeObject: workingID, origSpec, origMat, swirlMat, swirlSpec

appendInfoLine: ""
appendInfoLine: "Complete!"

selectObject: resultID
if play_after_processing
    Play
endif