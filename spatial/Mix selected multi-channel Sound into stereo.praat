# ============================================================
# Praat AudioTools - Mix selected multi-channel Sound into stereo.praat
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

# Mix selected multi-channel Sound into stereo (adaptive version)
# Automatically detects channel count and splits into left/right halves
# Left  = average of first half of channels
# Right = average of second half of channels

soundId = selected("Sound")
if soundId = 0
    exit Please select a Sound object in Praat's Objects window, then run this script.
endif

# Get channel count
selectObject: soundId
nchan = Get number of channels

# Check minimum requirements
if nchan < 2
    exit Selected Sound has only 'nchan' channel(s); need at least 2 channels for stereo output.
endif

# Calculate channel splits
leftChannels = floor(nchan / 2)
rightChannels = nchan - leftChannels

writeInfoLine: "Processing ", nchan, " channels into stereo:"
appendInfoLine: "Left: channels 1-", leftChannels, " (", leftChannels, " channels)"
appendInfoLine: "Right: channels ", leftChannels+1, "-", nchan, " (", rightChannels, " channels)"

# --- Left channels (first half) ---
selectObject: soundId
if leftChannels = 1
    Extract channels... 1
    Rename... __Left
else
    # Create channel list for first half
    leftChannelList$ = ""
    for i from 1 to leftChannels
        leftChannelList$ = leftChannelList$ + string$(i)
        if i < leftChannels
            leftChannelList$ = leftChannelList$ + " "
        endif
    endfor
    Extract channels... 'leftChannelList$'
    Convert to mono
    Rename... __Left
endif

# --- Right channels (second half) ---
selectObject: soundId
if rightChannels = 1
    Extract channels... 'nchan'
    Rename... __Right
else
    # Create channel list for second half
    rightChannelList$ = ""
    for i from leftChannels+1 to nchan
        rightChannelList$ = rightChannelList$ + string$(i)
        if i < nchan
            rightChannelList$ = rightChannelList$ + " "
        endif
    endfor
    Extract channels... 'rightChannelList$'
    Convert to mono
    Rename... __Right
endif

# --- Combine to stereo (Left first, then Right) ---
selectObject: "Sound __Left"
plusObject: "Sound __Right"
Combine to stereo
originalName$ = selected$("Sound")
selectObject: soundId
soundName$ = selected$("Sound")
selectObject: "Sound " + originalName$
Rename... 'soundName$'_Stereo
Play
# Clean up temporary mono objects
selectObject: "Sound __Left"
plusObject: "Sound __Right"
Remove

