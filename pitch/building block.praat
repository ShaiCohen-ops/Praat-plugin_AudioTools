# ============================================================
# Praat AudioTools - building block.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Pitch-based transformation script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# --- pitch up 7 semitones via samplerate trick ---
semitones = 7
ratio = exp((ln(2)/12) * semitones)

orig_sr = Get sampling frequency

# reinterpret sound as faster/slower
Override sampling frequency... (orig_sr * ratio)

# bring back to normal time base
Resample... orig_sr 50
Play
