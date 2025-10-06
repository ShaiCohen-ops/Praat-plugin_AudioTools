# ============================================================
# Praat AudioTools - extract portion.praat
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

# Praat script to calculate audio length, create window, and extract portion

# Get the current sound file
sound = selected("Sound")

# Get the total duration of the sound file
total_duration = Get total duration

# Calculate window boundaries (25% from start and 25% from end)
window_start = total_duration * 0.25
window_end = total_duration * 0.75
window_duration = window_end - window_start

# Extract the window portion for separate analysis
selectObject: sound
windowed_sound = Extract part: window_start, window_end, "rectangular", 1, "no"
Rename: "windowed_portion"

# Display information in info window
clearinfo
printline Audio File Analysis
printline ===================
printline Total duration: 'fixed$(total_duration, 3)' seconds
printline Window start: 'fixed$(window_start, 3)' seconds (25%)
printline Window end: 'fixed$(window_end, 3)' seconds (75%)
printline Window duration: 'fixed$(window_duration, 3)' seconds
printline 
printline Extracted window portion saved as: windowed_portion