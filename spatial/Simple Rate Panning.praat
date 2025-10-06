# ============================================================
# Praat AudioTools - Simple Rate Panning.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Multichannel or spatialisation script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# Simple Rate Panning 

form Panning
    real pan_rate 1.0
endform

# Select sound object
sound = selected("Sound")
selectObject: sound

# Check channels
num_channels = Get number of channels
if num_channels != 2
    exitScript: "Need stereo sound"
endif

# Create copy
selectObject: sound
Copy: "panned_result"

# Apply panning using separate Formulas for each channel
selectObject: "Sound panned_result"

# Better panning law using constant power panning
# Left channel - cosine pan law
Formula: "if col = 1 then self * cos(0.5 * pi * (0.5 + 0.5 * sin(2*pi*pan_rate*x))) else self fi"

# Right channel - sine pan law  
Formula: "if col = 2 then self * sin(0.5 * pi * (0.5 + 0.5 * sin(2*pi*pan_rate*x))) else self fi"

# Alternative simpler version (uncomment to use):
# Formula: "if col = 1 then self * (0.5 + 0.5 * sin(2*pi*pan_rate*x)) else self fi"
# Formula: "if col = 2 then self * (0.5 - 0.5 * sin(2*pi*pan_rate*x)) else self fi"

# Play result
selectObject: "Sound panned_result"
Play