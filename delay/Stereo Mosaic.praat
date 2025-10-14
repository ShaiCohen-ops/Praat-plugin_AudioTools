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
#   Create Stereo Mosaic from selected files
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
# - Extracts MULTIPLE non-overlapping regions from each file
# - LEFT and RIGHT channels use different regions
# - No repetition cycles—all variation comes from partitioning each file

form Create stereo composite with multiple regions per file
    comment Please select more than one Sound in the Objects list before running.
    comment Each file is divided into multiple regions for extraction

    positive regions_per_file 4
    real fade_time 0.05
    positive attenuation_divisor 1.1
    boolean play_final_sound 1

    optionmenu channel_strategy: 1
        option Alternating_regions
        option Left_first_half_Right_second_half
        option Random_split
        option Reverse_order_right
        option Inside_out
        option Spiral_pattern
    
    boolean apply_reverse_playback 0
    boolean randomize_amplitude 0
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
if regions_per_file < 1
    exitScript: "Error: regions_per_file must be at least 1."
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

for i to numberOfSelectedSounds
    selectObject: monoSounds#[i]
    soundName$ = selected$("Sound")
    total_duration = Get total duration
    
    region_duration = total_duration / regions_per_file
    
    for region to regions_per_file
        regionStart = (region - 1) * region_duration
        regionEnd = region * region_duration
        
        selectObject: monoSounds#[i]
        Extract part: regionStart, regionEnd, "rectangular", 1, "no"
        regionSeg = selected("Sound")
        
        if channel_strategy = 1
            if region mod 2 = 1
                isLeftChannel = 1
            else
                isLeftChannel = 0
            endif
        elsif channel_strategy = 2
            if region <= regions_per_file / 2
                isLeftChannel = 1
            else
                isLeftChannel = 0
            endif
        elsif channel_strategy = 3
            if randomUniform(0, 1) < 0.5
                isLeftChannel = 1
            else
                isLeftChannel = 0
            endif
        elsif channel_strategy = 4
            if region mod 2 = 1
                isLeftChannel = 0
            else
                isLeftChannel = 1
            endif
        elsif channel_strategy = 5
            midpoint = (regions_per_file + 1) / 2
            distanceFromMid = abs(region - midpoint)
            if distanceFromMid mod 2 = 0
                isLeftChannel = 1
            else
                isLeftChannel = 0
            endif
        else
            spiralValue = (i * 1.618 + region) mod 2
            if spiralValue < 1
                isLeftChannel = 1
            else
                isLeftChannel = 0
            endif
        endif
        
        selectObject: regionSeg
        
        if apply_reverse_playback = 1 and randomUniform(0, 1) < 0.3
            Reverse
        endif
        
        if randomize_amplitude = 1
            ampVariation = 0.5 + randomUniform(0, 1)
            Scale: ampVariation
        endif
        
        if region_duration > 2 * fade_time
            Formula: "self / attenuation_divisor"
            Formula: "self * min (1, x / fade_time)"
            Formula: "self * min (1, (xmax - x) / fade_time)"
        else
            Formula: "self / attenuation_divisor"
        endif
        
        if isLeftChannel = 1
            selectObject: leftID
            plusObject: regionSeg
            Concatenate
            newLeft = selected("Sound")
            selectObject: leftID
            Remove
            leftID = newLeft
            selectObject: leftID
            Rename: "temp_left"
        else
            selectObject: rightID
            plusObject: regionSeg
            Concatenate
            newRight = selected("Sound")
            selectObject: rightID
            Remove
            rightID = newRight
            selectObject: rightID
            Rename: "temp_right"
        endif
        
        selectObject: regionSeg
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

compositeName$ = "stereo_composite_" + string$(numberOfSelectedSounds) + "files_" + string$(regions_per_file) + "regions"
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