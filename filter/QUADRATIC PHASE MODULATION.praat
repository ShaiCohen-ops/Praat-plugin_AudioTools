# ============================================================
# Praat AudioTools - QUADRATIC PHASE MODULATION.praat
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

# 4. QUADRATIC PHASE MODULATION
form Quadratic Phase Ring Modulation
    positive f0 150
    real phase_curve 0.5
endform
Copy... soundObj
Formula... self*(sin(2*pi*f0*x + phase_curve*x*x*x))
Play