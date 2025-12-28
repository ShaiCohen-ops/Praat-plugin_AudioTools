# ============================================================
# Praat AudioTools - Subtle Random Texture.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.2 (2025)
# License: MIT License
#
# Description:
#   Adds random spectral variation to create subtle texture,
#   shimmer, or noise-like qualities. Each frequency bin gets
#   a random gain multiplier.
#
# Usage:
#   Select a Sound object in Praat and run this script.
# ============================================================

form Subtle Random Texture
    optionmenu Preset: 1
        option Custom
        option Subtle Shimmer
        option Strong Texture
        option Lo-Fi Grit
        option Spectral Dust
        option Vinyl Hiss
    comment === Variation Parameters ===
    positive frequency_cutoff 10000
    comment (frequencies below this get variation)
    positive variation_center 0.8
    positive variation_depth 0.2
    comment (gain = center ± depth × random)
    comment === Output ===
    positive scale_peak 0.90
    boolean play_after_processing 1
endform

# Apply presets
if preset = 2
    # Subtle Shimmer
    variation_center = 0.9
    variation_depth = 0.1
    frequency_cutoff = 12000
elsif preset = 3
    # Strong Texture
    variation_center = 0.7
    variation_depth = 0.4
    frequency_cutoff = 10000
elsif preset = 4
    # Lo-Fi Grit
    variation_center = 0.6
    variation_depth = 0.5
    frequency_cutoff = 6000
elsif preset = 5
    # Spectral Dust
    variation_center = 0.85
    variation_depth = 0.25
    frequency_cutoff = 16000
elsif preset = 6
    # Vinyl Hiss
    variation_center = 0.95
    variation_depth = 0.15
    frequency_cutoff = 8000
endif

# Input validation
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")
selectObject: originalID
original_sr = Get sampling frequency
duration = Get total duration
n_channels = Get number of channels

writeInfoLine: "=== Subtle Random Texture ==="
appendInfoLine: "Duration: ", fixed$(duration, 2), " s"
appendInfoLine: "Cutoff: ", frequency_cutoff, " Hz"
appendInfoLine: "Variation: ", variation_center, " ± ", variation_depth
appendInfoLine: ""

# Convert to mono
selectObject: originalID
if n_channels > 1
    workingID = Convert to mono
else
    workingID = Copy: "working"
endif

# To spectrum
selectObject: workingID
spectrum = To Spectrum: "yes"

# Get bin width for Hz conversion
dx = Get bin width
cutoff_bin = round(frequency_cutoff / dx)

# Build formula
centerStr$ = fixed$(variation_center, 4)
depthStr$ = fixed$(variation_depth, 4)
cutoffStr$ = string$(cutoff_bin)

# Apply random variation
# Each bin gets: self * (center + depth * randomUniform(-1, 1))
selectObject: spectrum
Formula: "if col < " + cutoffStr$ + " then self * (" + centerStr$ + " + " + depthStr$ + " * randomUniform(-1, 1)) else self fi"

# Back to sound
selectObject: spectrum
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
Rename: originalName$ + "_texture"
Scale peak: scale_peak

# Cleanup
removeObject: workingID, spectrum

appendInfoLine: "Complete!"

selectObject: resultID
if play_after_processing
    Play
endif