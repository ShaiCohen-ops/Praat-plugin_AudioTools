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
    optionmenu Preset: 1
        option "Default (2, 4, 8, 10)"
        option "Fine (2, 3, 5, 7)"
        option "Coarse (4, 8, 12, 16)"
        option "Extreme (2, 6, 12, 24)"
        option "Custom"
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

# Apply preset if not Custom
if preset = 1
    divisor_1 = 2
    divisor_2 = 4
    divisor_3 = 8
    divisor_4 = 10
elsif preset = 2
    divisor_1 = 2
    divisor_2 = 3
    divisor_3 = 5
    divisor_4 = 7
elsif preset = 3
    divisor_1 = 4
    divisor_2 = 8
    divisor_3 = 12
    divisor_4 = 16
elsif preset = 4
    divisor_1 = 2
    divisor_2 = 6
    divisor_3 = 12
    divisor_4 = 24
endif

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
