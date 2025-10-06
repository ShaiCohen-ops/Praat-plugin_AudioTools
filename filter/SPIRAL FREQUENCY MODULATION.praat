# ============================================================
# Praat AudioTools - SPIRAL FREQUENCY MODULATION.praat
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

# 12. SPIRAL FREQUENCY MODULATION
form Spiral Ring Modulation
    positive center_f0 250
    positive spiral_rate 0.8
    positive spiral_depth 150
endform
Copy... soundObj
Formula... self*(sin(2*pi*(center_f0 + spiral_depth*sin(spiral_rate*x)*x/xmax)*x))
Play