# ============================================================
# Praat AudioTools - Panning filter.praat
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

form Panning filter
    comment Please select a stereo file
    positive freq 500
endform

Copy... tmp
Extract all channels
To Spectrum... yes
select Spectrum tmp_ch1
Formula...     if x <freq then self else 0 fi
To Sound
select Spectrum tmp_ch2
Formula...     if x >freq then self else 0 fi
To Sound
select Sound tmp_ch1
plus Sound tmp_ch2
Combine to stereo
Play