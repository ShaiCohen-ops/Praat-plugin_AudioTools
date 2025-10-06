# ============================================================
# Praat AudioTools - delay_array.praat
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

form Process Sound Object
    comment Enter the divisor values for processing:
    positive divisor_1 2
    positive divisor_2 4
    positive divisor_3 8
    positive divisor_4 10
    comment Scaling options:
    positive scale_peak 0.99
    comment Number of iterations:
    natural number_of_iterations 4
endform

# Copy the sound object
Copy... soundObj

# Get the number of samples
a = Get number of samples

# Store divisors in an array-like structure
d1 = divisor_1
d2 = divisor_2
d3 = divisor_3
d4 = divisor_4

# Loop through the iterations
for k to number_of_iterations
    # Get the current divisor
    n = d'k'
    
    # Calculate b
    b = a/n
    
    # Apply the formula
    Formula: "self [col+b] - self [col]"
endfor

# Scale to peak
Scale peak: scale_peak
Play

