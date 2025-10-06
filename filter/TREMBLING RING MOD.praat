# ============================================================
# Praat AudioTools - TREMBLING RING MOD.praat
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

# 7. TREMBLING RING MOD (with micro-vibrato)
form Trembling Ring Modulation
    positive f0 200
    positive vibrato_rate 15
    real vibrato_depth 0.05
endform
Copy... soundObj
Formula... self*(sin(2*pi*f0*(1 + vibrato_depth*sin(2*pi*vibrato_rate*x))*x*x/2))
Play