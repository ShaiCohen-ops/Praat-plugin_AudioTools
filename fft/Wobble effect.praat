# ============================================================
# Praat AudioTools - Wobble effect.praat
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

form Wobble Effect with Tremolo
    comment This script applies frequency modulation wobble and tremolo decay
    comment Frequency wobble parameters:
    positive base_shift 1.1
    positive wobble_depth 0.3
    positive wobble_frequency 50
    comment (number of wobbles across duration)
    comment Decay parameters:
    positive decay_base 10
    comment (higher = faster decay)
    comment Tremolo parameters:
    positive tremolo_center 1.0
    positive tremolo_depth 0.5
    positive tremolo_frequency 20
    comment (number of tremolo cycles across duration)
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

# Apply wobbling frequency modulation
Formula: "self[col/('base_shift' + 'wobble_depth' * sin('wobble_frequency' * (x-xmin) / (xmax-xmin)))] - self[col*('base_shift' + 'wobble_depth' * cos('wobble_frequency' * (x-xmin) / (xmax-xmin)))]"

# Apply exponential decay with tremolo modulation
Formula: "self * 'decay_base'^(-(x-xmin)/(xmax-xmin)) * ('tremolo_center' + 'tremolo_depth' * sin('tremolo_frequency' * (x-xmin) / (xmax-xmin)))"

# Scale to peak
Scale peak: scale_peak

# Play if requested
if play_after_processing
    Play
endif
