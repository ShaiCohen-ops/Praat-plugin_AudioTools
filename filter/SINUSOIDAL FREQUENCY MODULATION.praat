# ============================================================
# Praat AudioTools - SINUSOIDAL FREQUENCY MODULATION.praat
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

# 3. SINUSOIDAL FREQUENCY MODULATION
form Sinusoidal FM Ring Modulation
    positive carrier_f0 300
    positive mod_rate 2
    positive mod_depth 100
endform
Copy... soundObj
Formula... self*(sin(2*pi*(carrier_f0 + mod_depth*sin(2*pi*mod_rate*x))*x))
Play