# ============================================================
# Praat AudioTools - Fractal_Convolution_Swarm.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Modulation or vibrato-based processing script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Fractal Convolution Swarm
    comment This script applies multi-scale fractal convolution processing
    comment Fractal parameters:
    natural fractal_depth 5
    comment (number of recursive depth levels)
    natural convolution_width 3
    comment (kernel half-width: processes from -width to +width)
    comment Scaling parameters:
    positive kernel_size_divisor 10
    comment (controls kernel size at each depth)
    positive depth_offset 2
    comment (offset for weight calculation)
    positive amplitude_decay_rate 0.15
    comment (amplitude reduction per depth level)
    comment Output options:
    positive scale_peak 0.90
    boolean play_after_processing 1
endform

# Check if a Sound is selected
if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

# Get original sound name
originalName$ = selected$("Sound")

# Work on a copy
Copy: originalName$ + "_fractal_swarm"

# Get number of samples
a = Get number of samples

# Apply fractal convolution processing
for depth from 1 to fractal_depth
    # Scale factor increases exponentially
    scaleFactor = 2 ^ depth
    kernelSize = round(a / (kernel_size_divisor * scaleFactor))
    
    # Apply convolution kernel
    for kernel from -convolution_width to convolution_width
        kernelWeight = 1 / (1 + abs(kernel))
        kernelShift = kernel * kernelSize
        
        # Add weighted delayed/advanced versions
        Formula: "self + self[max(1, min(ncol, col + 'kernelShift'))] * 'kernelWeight' / ('depth' + 'depth_offset')"
    endfor
    
    # Apply amplitude scaling for this depth
    Formula: "self * (1 - 'depth' * 'amplitude_decay_rate')"
endfor

# Scale to peak
Scale peak: scale_peak

# Rename result
Rename: originalName$ + "_fractal_convolution_swarm"

# Play if requested
if play_after_processing
    Play
endif