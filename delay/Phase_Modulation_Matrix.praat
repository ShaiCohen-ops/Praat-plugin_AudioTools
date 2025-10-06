# ============================================================
# Praat AudioTools - Phase_Modulation_Matrix.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Delay or temporal structure script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Phase Modulation Processing
    comment Modulation layer parameters:
    natural modulation_layers 5
    comment Carrier frequency range (for randomization):
    positive carrier_freq_min 0.1
    positive carrier_freq_max 0.5
    comment Or use a fixed carrier frequency:
    boolean use_fixed_carrier 0
    positive fixed_carrier_freq 0.3
    comment Modulation depth parameters:
    positive mod_depth_base 8
    positive mod_depth_increment 2
    comment Phase modulation feedback:
    positive feedback_base 0.7
    comment Spectral tilt compensation:
    positive spectral_tilt_base 1.1
    positive spectral_tilt_rate 0.1
    comment Output options:
    positive scale_peak 0.93
    boolean play_after_processing 1
endform

# Copy the sound object
Copy... soundObj

# Get the number of samples
a = Get number of samples

# Determine carrier frequency
if use_fixed_carrier
    carrierFreq = fixed_carrier_freq
else
    carrierFreq = randomUniform(carrier_freq_min, carrier_freq_max)
endif

# Main modulation processing loop
for layer from 1 to modulation_layers
    # Dynamic modulation depth
    modDepth = a / (mod_depth_base + layer * mod_depth_increment)
    modulatorFreq = carrierFreq * (layer + 1)
    
    # Phase modulation with feedback
    Formula: "self + self[col + round(modDepth * sin(2 * pi * modulatorFreq * col / a))] * ('feedback_base' / layer)"
    
    # Spectral tilt compensation
    Formula: "self * ('spectral_tilt_base' - 'spectral_tilt_rate' * layer)"
endfor

# Scale to peak
Scale peak: scale_peak

# Play if requested
if play_after_processing
    Play
endif