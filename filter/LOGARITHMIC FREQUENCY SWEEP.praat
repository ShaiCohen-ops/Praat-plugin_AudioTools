# ============================================================
# Praat AudioTools - LOGARITHMIC FREQUENCY SWEEP.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Filtering or timbral modification script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# 2. LOGARITHMIC FREQUENCY SWEEP  
form Logarithmic Ring Modulation
    positive f0_start 800
    positive f0_end 50
endform
Copy... soundObj
Formula... self*(sin(2*pi*f0_start*exp(-ln(f0_start/f0_end)*x/xmax)*x))
Play