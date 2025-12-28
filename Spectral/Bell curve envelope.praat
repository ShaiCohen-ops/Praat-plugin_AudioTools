# ============================================================
# Praat AudioTools - Bell curve envelope.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral analysis or frequency-domain processing script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# ============================================================
# Praat AudioTools - Bell Curve Envelope.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.2 (2025)
# License: MIT License
#
# Description:
#   Applies spectral filtering and Gaussian bell envelope
#
# Usage:
#   Select a Sound object in Praat and run this script.
# ============================================================

form Bell Curve Envelope
    optionmenu Preset: 1
        option Custom
        option Narrow Bell
        option Wide Bell
        option Low Freq Emphasis
        option High Freq Emphasis
    comment === Spectral Filtering ===
    positive low_freq_factor 1.1
    positive high_freq_factor 1.1
    comment === Bell Envelope ===
    positive bell_width_divisor 4
    comment (higher = narrower, lower = wider)
    positive bell_center_position 0.5
    comment (0 = start, 0.5 = middle, 1 = end)
    comment === Output ===
    positive scale_peak 0.99
    boolean play_after_processing 1
endform

# Apply presets
if preset = 2
    bell_width_divisor = 6
elsif preset = 3
    bell_width_divisor = 2
elsif preset = 4
    low_freq_factor = 1.5
    high_freq_factor = 1.0
elsif preset = 5
    low_freq_factor = 1.0
    high_freq_factor = 1.5
endif

# Check selection
if numberOfSelected("Sound") <> 1
    exitScript: "Please select a Sound object first."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

# Copy to work on
selectObject: originalID
workingID = Copy: originalName$ + "_bell"

# Get info for formula
selectObject: workingID
duration = Get total duration

writeInfoLine: "=== Bell Curve Envelope ==="
appendInfoLine: "Duration: ", fixed$(duration, 2), " s"
appendInfoLine: "Low factor: ", low_freq_factor
appendInfoLine: "High factor: ", high_freq_factor
appendInfoLine: "Bell width divisor: ", bell_width_divisor
appendInfoLine: "Bell center: ", bell_center_position

# Build formula strings (avoid 'variable' interpolation)
lowStr$ = fixed$(low_freq_factor, 6)
highStr$ = fixed$(high_freq_factor, 6)
centerStr$ = fixed$(bell_center_position, 6)
widthStr$ = fixed$(bell_width_divisor, 6)

# Apply spectral filtering
selectObject: workingID
Formula: "self[col/" + lowStr$ + "] - self[col*" + highStr$ + "]"

# Apply Gaussian bell envelope
selectObject: workingID
Formula: "self * exp(-((x - (xmin + (xmax-xmin) * " + centerStr$ + ")) / ((xmax-xmin) / " + widthStr$ + "))^2)"

# Scale to peak
selectObject: workingID
Scale peak: scale_peak

appendInfoLine: "Complete!"

# Play if requested
if play_after_processing
    selectObject: workingID
    Play
endif

selectObject: workingID