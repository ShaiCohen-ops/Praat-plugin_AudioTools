# ============================================================
# Praat AudioTools - Linear Fade-In.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Dynamic range or envelope control script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Fade In with Attenuation
    comment This script attenuates and applies a linear fade-in
    comment Attenuation:
    positive attenuation_divisor 1.1
    comment Fade parameters:
    comment (fade goes from 0 at start to 1 at end)
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

# Attenuate the signal
Formula: "self [col] / 'attenuation_divisor'"

# Apply linear fade-in
Formula: "self * ((x - xmin) / (xmax - xmin))"

# Scale to peak
Scale peak: scale_peak

# Play if requested
if play_after_processing
    Play
endif