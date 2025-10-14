# ============================================================
# Praat AudioTools - Sound to Grain.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Create stereo composite from selected files
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# PRAAT Script: Create stereo composite from selected files
# - LEFT and RIGHT channels use different parts of each file
# - Repeats the pass over selected files N times

form Create stereo composite from selected files
    comment Please select more than one Sound in the Objects list before running.
    comment Extract 0.25 seconds per file and build a stereo composite
    comment LEFT uses one part; RIGHT uses a different part of each file

    positive segment_duration 0.25
    real fade_time 0.05
    positive attenuation_divisor 1.1
    integer repeat_cycles 3
    boolean play_final_sound 1

    optionmenu right_part_strategy: 1
        option End_of_file
        option Fixed_offset
        option Random
    real right_fixed_offset 0.10
endform

numberOfSelectedSounds = numberOfSelected("Sound")
if numberOfSelectedSounds = 0
    exitScript: "Please select some Sound objects first."
endif
if numberOfSelectedSounds < 2
    exitScript: "Please select at least two Sound objects."
endif
if fade_time <= 0
    exitScript: "Error: Fade time must be positive."
endif
if fade_time > segment_duration / 2
    exitScript: "Error: Fade time cannot be longer than half the segment duration."
endif
if repeat_cycles < 1
    exitScript: "Error: repeat_cycles must be at least 1."
endif
if right_part_strategy = 2 and right_fixed_offset < 0
    exitScript: "Error: right_fixed_offset must be >= 0."
endif

originalSounds# = selected#("Sound")

monoSounds# = zero#(numberOfSelectedSounds)
for i to numberOfSelectedSounds
    selectObject: originalSounds#[i]
    numChannels = Get number of channels
    Copy: "mono_work_" + string$(i)
    workID = selected("Sound")
    if numChannels > 1
        Convert to mono
        monoID = selected("Sound")
        selectObject: workID
        Remove
        monoSounds#[i] = monoID
    else
        monoSounds#[i] = workID
    endif
endfor

Create Sound from formula: "temp_left", 1, 0, 0.01, 44100, "0"
leftID = selected("Sound")
Create Sound from formula: "temp_right", 1, 0, 0.01, 44100, "0"
rightID = selected("Sound")

for cycle to repeat_cycles
    for i to numberOfSelectedSounds
        selectObject: monoSounds#[i]
        soundName$ = selected$("Sound")
        total_duration = Get total duration

        if segment_duration > total_duration
            extractDuration = total_duration
        else
            extractDuration = segment_duration
        endif

        leftStart = 0
        leftEnd = leftStart + extractDuration
        if leftEnd > total_duration
            leftEnd = total_duration
        endif

        Extract part: leftStart, leftEnd, "rectangular", 1, "no"
        leftSeg = selected("Sound")

        selectObject: leftSeg
        if extractDuration > 2 * fade_time
            Formula: "self / attenuation_divisor"
            Formula: "self * min (1, x / fade_time)"
            Formula: "self * min (1, (xmax - x) / fade_time)"
        else
            Formula: "self / attenuation_divisor"
        endif

        selectObject: leftID
        plusObject: leftSeg
        Concatenate
        newLeft = selected("Sound")
        selectObject: leftID
        Remove
        leftID = newLeft
        selectObject: leftID
        Rename: "temp_left"
        selectObject: leftSeg
        Remove

        if right_part_strategy = 1
            rightEnd = total_duration
            rightStart = rightEnd - extractDuration
            if rightStart < 0
                rightStart = 0
            endif
        elsif right_part_strategy = 2
            rightStart = right_fixed_offset
            if rightStart > total_duration - extractDuration
                rightStart = total_duration - extractDuration
            endif
            if rightStart < 0
                rightStart = 0
            endif
        else
            usableWindow = total_duration - extractDuration
            if usableWindow <= 0
                rightStart = 0
            else
                rightStart = randomUniform (0, usableWindow)
            endif
        endif

        rightEnd = rightStart + extractDuration
        if rightEnd > total_duration
            rightEnd = total_duration
            rightStart = rightEnd - extractDuration
            if rightStart < 0
                rightStart = 0
            endif
        endif

        selectObject: monoSounds#[i]
        Extract part: rightStart, rightEnd, "rectangular", 1, "no"
        rightSeg = selected("Sound")

        selectObject: rightSeg
        if extractDuration > 2 * fade_time
            Formula: "self / attenuation_divisor"
            Formula: "self * min (1, x / fade_time)"
            Formula: "self * min (1, (xmax - x) / fade_time)"
        else
            Formula: "self / attenuation_divisor"
        endif

        selectObject: rightID
        plusObject: rightSeg
        Concatenate
        newRight = selected("Sound")
        selectObject: rightID
        Remove
        rightID = newRight
        selectObject: rightID
        Rename: "temp_right"
        selectObject: rightSeg
        Remove
    endfor
endfor

selectObject: leftID
Scale peak: 0.99
selectObject: rightID
Scale peak: 0.99

selectObject: leftID
plusObject: rightID
Combine to stereo
stereoID = selected("Sound")

compositeName$ = "stereo_composite_" + string$(numberOfSelectedSounds) + "files_" + string$(repeat_cycles) + "x"
Rename: compositeName$
finalID = selected("Sound")

selectObject: leftID
Remove
selectObject: rightID
Remove

for i to numberOfSelectedSounds
    if monoSounds#[i] > 0
        selectObject: monoSounds#[i]
        Remove
    endif
endfor

selectObject: finalID
if play_final_sound
    Play
endif
