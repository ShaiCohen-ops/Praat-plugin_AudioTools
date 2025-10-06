# ============================================================
# Praat AudioTools - 8 - Odd forward Even reversed.praat
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

# 8-Channel Delay Processor with Interactive Settings

form 8-Channel Delay Settings
    comment Base delay settings (samples):
    positive Delay_1 2 
    positive Delay_2 4 
    positive Delay_3 8 
    positive Delay_4 10 
    positive Delay_5 12 
    positive Delay_6 16 
    positive Delay_7 20 
    positive Delay_8 24 
    
    comment Output options:
    boolean Keep_intermediate_files 0
    boolean Play_result 1
    real Scale_peak 0.99
endform

# Require a selected Sound
if numberOfSelected ("Sound") = 0
    exitScript: "Please select a Sound object first."
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

# Build 8 delayed channels from the mono source
for i from 1 to 8
    select Sound soundObj
    Copy... Ch'i'
    
    # Use form variables for delays
    if i = 1
        n = delay_1
    elsif i = 2
        n = delay_2
    elsif i = 3
        n = delay_3
    elsif i = 4
        n = delay_4
    elsif i = 5
        n = delay_5
    elsif i = 6
        n = delay_6
    elsif i = 7
        n = delay_7
    else
        n = delay_8
    endif
    
    b = floor (a / n)
    Formula: "if col + 'b' <= ncol then self[col + 'b'] - self[col] else -self[col] fi"
endfor

# Reverse even-numbered channels only (2,4,6,8)
for i from 1 to 8
    if i mod 2 = 0
        select Sound Ch'i'
        Reverse
    endif
endfor

# Combine into stereo
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
Scale peak: scale_peak

if play_result
    Play
endif

# Clean up unless keep_intermediate_files is selected
if not keep_intermediate_files
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
endif