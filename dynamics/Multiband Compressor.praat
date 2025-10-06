# ============================================================
# Praat AudioTools - Multiband Compressor.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Dynamic range or envelope control script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Multiband Compressor
real Low_crossover_(Hz) 200
real High_crossover_(Hz) 2000
real Low_compression_(1-10) 3
real Mid_compression_(1-10) 2
real High_compression_(1-10) 4
endform

original = selected("Sound")
name$ = selected$("Sound")
duration = Get total duration
sampleRate = Get sampling frequency

# Create frequency bands
selectObject: original
low = Filter (pass Hann band): 0, low_crossover, 100
selectObject: original
mid = Filter (pass Hann band): low_crossover, high_crossover, 100
selectObject: original
high = Filter (pass Hann band): high_crossover, 0, 100

# Compress each band
selectObject: low
Formula... self / (1 + abs(self) * low_compression * 0.2)

selectObject: mid
Formula... self / (1 + abs(self) * mid_compression * 0.2)

selectObject: high
Formula... self / (1 + abs(self) * high_compression * 0.2)

# Create empty sound as base
combined = Create Sound from formula: "multiband_compressed", 1, 0, duration, sampleRate, "0"

# Mix bands back together
selectObject: combined
Formula... self + object[low]
Formula... self + object[mid]
Formula... self + object[high]

# Scale and play
Scale peak... 0.99
Play

# Cleanup
removeObject: low, mid, high