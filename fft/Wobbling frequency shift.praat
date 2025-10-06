# ============================================================
# Praat AudioTools - Wobbling frequency shift.praat
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

form Wobbling Frequency Shift with Turbulent Decay
    comment This script applies wobbling frequency shifts and turbulent decay
    comment Frequency shift wobble parameters:
    positive base_shift 1.1
    positive wobble_amount 0.05
    positive wobble_frequency 50
    comment (number of wobbles across duration)
    comment Turbulent decay parameters:
    positive decay_base 25
    comment (higher = faster decay)
    positive turbulence_center 1.0
    positive turbulence_amount 0.1
    comment (Gaussian noise added to decay)
    comment Output options:
    positive scale_peak 0.99
    boolean play_after_processing 1
endform

# Check if a Sound is selected
if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

# Copy the sound object
Copy... soundObj

# Get name and ID
name$ = selected$("Sound")
sound = selected("Sound")

# Apply wobbling frequency shift
Formula: "self[col/('base_shift' + 'wobble_amount' * sin('wobble_frequency' * (x-xmin) / (xmax-xmin)))] - self[col*('base_shift' + 'wobble_amount' * cos('wobble_frequency' * (x-xmin) / (xmax-xmin)))]"

# Apply exponential decay with turbulence (Gaussian noise)
Formula: "self * 'decay_base'^(-(x-xmin)/(xmax-xmin)) * ('turbulence_center' + 'turbulence_amount' * randomGauss(0, 1))"

# Scale to peak
Scale peak: scale_peak

# Play if requested
if play_after_processing
    Play
endif