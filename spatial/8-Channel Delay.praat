# ============================================================
# Praat AudioTools - 8-Channel Delay.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Multichannel or spatialisation script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form 8-Channel Delay Processor
    comment Set delay divisors for each channel (higher = shorter delay)
    positive Channel_1_delay_divisor 2
    positive Channel_2_delay_divisor 4
    positive Channel_3_delay_divisor 8
    positive Channel_4_delay_divisor 10
    positive Channel_5_delay_divisor 12
    positive Channel_6_delay_divisor 16
    positive Channel_7_delay_divisor 20
    positive Channel_8_delay_divisor 24
    positive Peak_level 0.99
endform

# Require a selected Sound
if numberOfSelected ("Sound") = 0
    pause "Select a Sound object and run again."
endif

# Work from the selected sound
selectObject: selected ("Sound")

# Ensure mono
nch = Get number of channels
if nch > 1
    Convert to mono
endif
Rename: "soundObj"

# Base info
a = Get number of samples

# Delays per channel from form
d1 = channel_1_delay_divisor
d2 = channel_2_delay_divisor
d3 = channel_3_delay_divisor
d4 = channel_4_delay_divisor
d5 = channel_5_delay_divisor
d6 = channel_6_delay_divisor
d7 = channel_7_delay_divisor
d8 = channel_8_delay_divisor

# Build 8 delayed channels from the mono source
for i from 1 to 8
    select Sound soundObj
    Copy... Ch'i'
    n = d'i'
    b = floor (a / n)
    Formula: "if col + 'b' <= ncol then self[col + 'b'] - self[col] else -self[col] fi"
endfor

# Combine Ch1..Ch8 into stereo
select Sound Ch1
plus Sound Ch2
plus Sound Ch3
plus Sound Ch4
plus Sound Ch5
plus Sound Ch6
plus Sound Ch7
plus Sound Ch8
Combine to stereo
Rename: "StereoOut"

# Normalize & audition
select Sound StereoOut
Scale peak: peak_level
Play

# Remove intermediate objects
select Sound soundObj
plus Sound Ch1
plus Sound Ch2
plus Sound Ch3
plus Sound Ch4
plus Sound Ch5
plus Sound Ch6
plus Sound Ch7
plus Sound Ch8
Remove