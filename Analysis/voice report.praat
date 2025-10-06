# ============================================================
# Praat AudioTools - voice report.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Analytical measurement or feature-extraction script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

a = selected("Sound")
b = To Pitch (raw cc): 0, 75, 600, 15, "no", 0.03, 0.45, 0.01, 0.35, 0.14
select a
plus b
c = To PointProcess (cc)
select a
plus b
plus c
Voice report: 0, 0, 75, 600, 1.3, 1.6, 0.03, 0.45
select b
plus c
Remove







