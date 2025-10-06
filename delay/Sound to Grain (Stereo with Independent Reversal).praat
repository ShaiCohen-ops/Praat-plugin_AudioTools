# ============================================================
# Praat AudioTools - Sound to Grain (Stereo with Independent Reversal).praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Delay or temporal structure script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Sound to Grain (Stereo with Independent Reversal)
    positive Number_of_grains 20
    positive Grain_length 0.3
    boolean Preview_result 0
    positive Left_reversal_probability 50
    positive Right_reversal_probability 50
    optionmenu Overlap_method: 1
        option Hanning
        option Rectangular
        option Triangular
    comment Extract grains from selected sound object
endform

# Check if a sound object is selected
if !selected("Sound")
    exitScript: "Please select a Sound object first."
endif

# Get selected sound info
soundID = selected("Sound")
soundName$ = selected$("Sound")
totalDuration = Get total duration

# Validate parameters
if grain_length > totalDuration
    exitScript: "Grain length cannot exceed sound duration (" + string$(totalDuration) + " s)."
endif

# Arrays to store grain IDs and reversal flags
leftGrainIDs# = zero#(number_of_grains)
rightGrainIDs# = zero#(number_of_grains)
leftReversalFlags# = zero#(number_of_grains)
rightReversalFlags# = zero#(number_of_grains)

for grain from 1 to number_of_grains
    # Calculate random start position within valid range
    maxStart = totalDuration - grain_length
    if maxStart > 0
        startTime = randomUniform(0, maxStart)
        endTime = startTime + grain_length
        
        # Extract grain for left channel
        selectObject: soundID
        if overlap_method = 1
            leftGrainID = Extract part: startTime, endTime, "Hanning", 1, "no"
        elif overlap_method = 2
            leftGrainID = Extract part: startTime, endTime, "Rectangular", 1, "no"
        else
            leftGrainID = Extract part: startTime, endTime, "Triangular", 1, "no"
        endif
        
        # Reverse left channel with independent probability
        reverseLeft = randomInteger(1, 100) <= left_reversal_probability
        if reverseLeft
            Reverse
            leftGrainID = selected("Sound")
        endif
        
        leftReversalFlags#[grain] = reverseLeft
        Rename: soundName$ + "_left_grain_" + string$(grain) + if reverseLeft then "_rev" else "" fi
        leftGrainIDs#[grain] = leftGrainID
        
        # Extract grain for right channel
        selectObject: soundID
        if overlap_method = 1
            rightGrainID = Extract part: startTime, endTime, "Hanning", 1, "no"
        elif overlap_method = 2
            rightGrainID = Extract part: startTime, endTime, "Rectangular", 1, "no"
        else
            rightGrainID = Extract part: startTime, endTime, "Triangular", 1, "no"
        endif
        
        # Reverse right channel with independent probability
        reverseRight = randomInteger(1, 100) <= right_reversal_probability
        if reverseRight
            Reverse
            rightGrainID = selected("Sound")
        endif
        
        rightReversalFlags#[grain] = reverseRight
        Rename: soundName$ + "_right_grain_" + string$(grain) + if reverseRight then "_rev" else "" fi
        rightGrainIDs#[grain] = rightGrainID
        
        if preview_result
            selectObject: leftGrainID
            Play
            sleep(0.1)
        endif
    endif
endfor

# Create and combine stereo sound (same as above)
if number_of_grains > 0
    # Left channel
    selectObject: leftGrainIDs#[1]
    for grain from 2 to number_of_grains
        if leftGrainIDs#[grain] != 0
            plusObject: leftGrainIDs#[grain]
        endif
    endfor
    leftChannelID = Concatenate
    Rename: soundName$ + "_left_channel"
    
    # Right channel
    selectObject: rightGrainIDs#[1]
    for grain from 2 to number_of_grains
        if rightGrainIDs#[grain] != 0
            plusObject: rightGrainIDs#[grain]
        endif
    endfor
    rightChannelID = Concatenate
    Rename: soundName$ + "_right_channel"
    
    # Combine to stereo
    selectObject: leftChannelID, rightChannelID
    stereoID = Combine to stereo
    stereoName$ = soundName$ + "_stereo_grains"
    Rename: stereoName$
endif

# Clean up
if number_of_grains > 0
    for grain from 1 to number_of_grains
        if leftGrainIDs#[grain] != 0
            removeObject: leftGrainIDs#[grain]
        endif
        if rightGrainIDs#[grain] != 0
            removeObject: rightGrainIDs#[grain]
        endif
    endfor
    removeObject: leftChannelID, rightChannelID
endif

# Final selection and stats
selectObject: soundID
plusObject: stereoID

leftReversedCount = 0
rightReversedCount = 0
for grain from 1 to number_of_grains
    if leftReversalFlags#[grain] != 0
        leftReversedCount += 1
    endif
    if rightReversalFlags#[grain] != 0
        rightReversedCount += 1
    endif
endfor

appendInfoLine: "=== Stereo Grain Extraction Complete ==="
appendInfoLine: "Left channel reversed: ", leftReversedCount, " of ", number_of_grains, " (", fixed$(100 * leftReversedCount/number_of_grains, 1), "%)"
appendInfoLine: "Right channel reversed: ", rightReversedCount, " of ", number_of_grains, " (", fixed$(100 * rightReversedCount/number_of_grains, 1), "%)"
appendInfoLine: "Final objects: '", soundName$, "' and '", stereoName$, "'"