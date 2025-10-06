# ============================================================
# Praat AudioTools - Spectral Filter with Exponential Fade.praat
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

form Spectral Filter with Exponential Fade
    comment This script applies spectral filtering and exponential fade-out
    comment Spectral filtering parameters:
    positive low_freq_factor 1.1
    positive high_freq_factor 1.1
    comment Exponential fade parameters:
    positive fade_base 20
    comment (higher = faster fade-out)
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

# Apply spectral filtering (emphasize mids, reduce extremes)
Formula: "self[col/'low_freq_factor'] - self[col*'high_freq_factor']"

# Apply exponential fade-out
Formula: "self * 'fade_base'^(-(x-xmin)/(xmax-xmin))"

# Scale to peak
Scale peak: scale_peak

# Play if requested
if play_after_processing
    Play
endif

