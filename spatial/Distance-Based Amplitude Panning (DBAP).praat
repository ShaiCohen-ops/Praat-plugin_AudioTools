# ============================================================
# Praat AudioTools - 8-channel speed deviations.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Distance-Based Amplitude Panning (DBAP) for a selected multichannel Sound
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================
# Distance-Based Amplitude Panning (DBAP) for a selected multichannel Sound

clearinfo

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

sound = selected("Sound")
sound_name$ = selected$("Sound")

form Distance-Based Amplitude Panning Control
    optionmenu preset: 1
        option Default Midpoint (2 speakers)
        option Close to Speaker 1 (2 speakers)
        option Triangle Setup (3 speakers)
        option Outside Triangle (3 speakers)
        option Quad Setup (4 speakers)
        option Surround 5.1 (6 speakers)
        option Hexagon Array (6 speakers)
        option Custom Coordinates
        option Hard Left (2 speakers)
        option Hard Right (2 speakers)
        option Medium Left (2 speakers)
        option Medium Right (2 speakers)
        option Ultra Wide (2 speakers)
        option Nearfield Center (2 speakers)

    boolean normalize_gains: 1
    real distance_exponent: 1.0
    real minimum_distance: 0.01
    boolean show_gain_values: 0

    real source_x: 0.5
    real source_y: 0.5
    natural number_of_speakers: 2
    real speaker_1_x: 0
    real speaker_1_y: 0
    real speaker_2_x: 1
    real speaker_2_y: 0
    real speaker_3_x: 0.5
    real speaker_3_y: 1
    real speaker_4_x: 1
    real speaker_4_y: 1
    real speaker_5_x: 0
    real speaker_5_y: 1
    real speaker_6_x: 0.5
    real speaker_6_y: 0.5
endform

if preset = 1
    number_of_speakers = 2
    source_x = 0.5
    source_y = 0.5
    speaker_1_x = 0
    speaker_1_y = 0
    speaker_2_x = 1
    speaker_2_y = 0
elsif preset = 2
    number_of_speakers = 2
    source_x = 0.1
    source_y = 0.05
    speaker_1_x = 0
    speaker_1_y = 0
    speaker_2_x = 2
    speaker_2_y = 0
elsif preset = 3
    number_of_speakers = 3
    source_x = 0.5
    source_y = 0.3
    speaker_1_x = 0
    speaker_1_y = 0
    speaker_2_x = 1
    speaker_2_y = 0
    speaker_3_x = 0.5
    speaker_3_y = 1
elsif preset = 4
    number_of_speakers = 3
    source_x = 1.5
    source_y = 1.5
    speaker_1_x = 0
    speaker_1_y = 0
    speaker_2_x = 1
    speaker_2_y = 0
    speaker_3_x = 0.5
    speaker_3_y = 1
elsif preset = 5
    number_of_speakers = 4
    source_x = 0.5
    source_y = 0.5
    speaker_1_x = 0
    speaker_1_y = 0
    speaker_2_x = 1
    speaker_2_y = 0
    speaker_3_x = 0
    speaker_3_y = 1
    speaker_4_x = 1
    speaker_4_y = 1
elsif preset = 6
    number_of_speakers = 6
    source_x = 0.5
    source_y = 0.3
    speaker_1_x = 0.1
    speaker_1_y = 0
    speaker_2_x = 0.9
    speaker_2_y = 0
    speaker_3_x = 0.5
    speaker_3_y = 0.1
    speaker_4_x = 0.1
    speaker_4_y = 1
    speaker_5_x = 0.9
    speaker_5_y = 1
    speaker_6_x = 0.5
    speaker_6_y = 0.5
elsif preset = 7
    number_of_speakers = 6
    source_x = 0.5
    source_y = 0.5
    speaker_1_x = 0.5
    speaker_1_y = 1
    speaker_2_x = 0.87
    speaker_2_y = 0.75
    speaker_3_x = 0.87
    speaker_3_y = 0.25
    speaker_4_x = 0.5
    speaker_4_y = 0
    speaker_5_x = 0.13
    speaker_5_y = 0.25
    speaker_6_x = 0.13
    speaker_6_y = 0.75
elsif preset = 8
elsif preset = 9
    number_of_speakers = 2
    source_x = 0.05
    source_y = 0.0
    speaker_1_x = 0
    speaker_1_y = 0
    speaker_2_x = 1
    speaker_2_y = 0
elsif preset = 10
    number_of_speakers = 2
    source_x = 0.95
    source_y = 0.0
    speaker_1_x = 0
    speaker_1_y = 0
    speaker_2_x = 1
    speaker_2_y = 0
elsif preset = 11
    number_of_speakers = 2
    source_x = 0.35
    source_y = 0.0
    speaker_1_x = 0
    speaker_1_y = 0
    speaker_2_x = 1
    speaker_2_y = 0
elsif preset = 12
    number_of_speakers = 2
    source_x = 0.65
    source_y = 0.0
    speaker_1_x = 0
    speaker_1_y = 0
    speaker_2_x = 1
    speaker_2_y = 0
elsif preset = 13
    number_of_speakers = 2
    source_x = 0.5
    source_y = 0.0
    speaker_1_x = -0.75
    speaker_1_y = 0
    speaker_2_x = 1.75
    speaker_2_y = 0
elsif preset = 14
    number_of_speakers = 2
    source_x = 0.5
    source_y = 0.2
    speaker_1_x = 0
    speaker_1_y = -0.5
    speaker_2_x = 1
    speaker_2_y = -0.5
endif

for i from 1 to number_of_speakers
    speakerX[i] = 0
    speakerY[i] = 0
    gain[i] = 0
endfor

speakerX[1] = speaker_1_x
speakerY[1] = speaker_1_y
speakerX[2] = speaker_2_x
speakerY[2] = speaker_2_y
if number_of_speakers >= 3
    speakerX[3] = speaker_3_x
    speakerY[3] = speaker_3_y
endif
if number_of_speakers >= 4
    speakerX[4] = speaker_4_x
    speakerY[4] = speaker_4_y
endif
if number_of_speakers >= 5
    speakerX[5] = speaker_5_x
    speakerY[5] = speaker_5_y
endif
if number_of_speakers >= 6
    speakerX[6] = speaker_6_x
    speakerY[6] = speaker_6_y
endif

totalPower = 0
for i from 1 to number_of_speakers
    dx = source_x - speakerX[i]
    dy = source_y - speakerY[i]
    distance = sqrt(dx*dx + dy*dy)
    if distance < minimum_distance
        effective_distance = minimum_distance
    else
        effective_distance = distance
    endif
    if effective_distance = 0
        effective_distance = 1e-9
    endif
    gain[i] = 1 / (effective_distance ^ distance_exponent)
    totalPower = totalPower + gain[i]^2
endfor

if normalize_gains
    normalizationFactor = sqrt(totalPower)
    for i from 1 to number_of_speakers
        gain[i] = gain[i] / normalizationFactor
    endfor
endif

if show_gain_values
    appendInfoLine: "Distance-Based Amplitude Panning Gains:"
    appendInfoLine: "Source position: (", source_x, ", ", source_y, ")"
    appendInfoLine: "Number of speakers: ", number_of_speakers
    appendInfoLine: ""
    appendInfoLine: "Speaker gains:"
    total_gain = 0
    for i from 1 to number_of_speakers
        appendInfoLine: "Speaker ", i, " (", fixed$(speakerX[i], 2), ", ", fixed$(speakerY[i], 2), "): ", fixed$(gain[i], 4)
        total_gain = total_gain + gain[i]
    endfor
    appendInfoLine: "Total gain (sum): ", fixed$(total_gain, 4)
    appendInfoLine: ""
endif

selectObject: sound
numChannels = Get number of channels
if numChannels <> number_of_speakers
    exitScript: "Number of channels in Sound (" + string$(numChannels) + ") must equal number of speakers in preset (" + string$(number_of_speakers) + ")"
endif

for i from 1 to numChannels
    selectObject: sound
    monoSound = Extract one channel: i
    selectObject: monoSound
    Formula: "self * " + string$(gain[i])
    if i = 1
        tempSound1 = monoSound
    elsif i = 2
        tempSound2 = monoSound
    elsif i = 3
        tempSound3 = monoSound
    elsif i = 4
        tempSound4 = monoSound
    elsif i = 5
        tempSound5 = monoSound
    elsif i = 6
        tempSound6 = monoSound
    endif
endfor

if numChannels = 1
    selectObject: tempSound1
    combinedSound = Copy: "temp_combined"
elsif numChannels = 2
    selectObject: tempSound1
    plusObject: tempSound2
    combinedSound = Combine to stereo
elsif numChannels = 3
    selectObject: tempSound1
    plusObject: tempSound2
    plusObject: tempSound3
    combinedSound = Combine to stereo
elsif numChannels = 4
    selectObject: tempSound1
    plusObject: tempSound2
    plusObject: tempSound3
    plusObject: tempSound4
    combinedSound = Combine to stereo
elsif numChannels = 5
    selectObject: tempSound1
    plusObject: tempSound2
    plusObject: tempSound3
    plusObject: tempSound4
    plusObject: tempSound5
    combinedSound = Combine to stereo
elsif numChannels = 6
    selectObject: tempSound1
    plusObject: tempSound2
    plusObject: tempSound3
    plusObject: tempSound4
    plusObject: tempSound5
    plusObject: tempSound6
    combinedSound = Combine to stereo
endif

preset_name_1$ = "Default_Midpoint"
preset_name_2$ = "Close_to_Speaker_1"
preset_name_3$ = "Triangle_Setup"
preset_name_4$ = "Outside_Triangle"
preset_name_5$ = "Quad_Setup"
preset_name_6$ = "Surround_5.1"
preset_name_7$ = "Hexagon_Array"
preset_name_8$ = "Custom"
preset_name_9$ = "Hard_Left"
preset_name_10$ = "Hard_Right"
preset_name_11$ = "Medium_Left"
preset_name_12$ = "Medium_Right"
preset_name_13$ = "Ultra_Wide"
preset_name_14$ = "Nearfield_Center"

if preset = 1
    new_name$ = sound_name$ + "_DBAP_" + preset_name_1$
elsif preset = 2
    new_name$ = sound_name$ + "_DBAP_" + preset_name_2$
elsif preset = 3
    new_name$ = sound_name$ + "_DBAP_" + preset_name_3$
elsif preset = 4
    new_name$ = sound_name$ + "_DBAP_" + preset_name_4$
elsif preset = 5
    new_name$ = sound_name$ + "_DBAP_" + preset_name_5$
elsif preset = 6
    new_name$ = sound_name$ + "_DBAP_" + preset_name_6$
elsif preset = 7
    new_name$ = sound_name$ + "_DBAP_" + preset_name_7$
elsif preset = 8
    new_name$ = sound_name$ + "_DBAP_" + preset_name_8$
elsif preset = 9
    new_name$ = sound_name$ + "_DBAP_" + preset_name_9$
elsif preset = 10
    new_name$ = sound_name$ + "_DBAP_" + preset_name_10$
elsif preset = 11
    new_name$ = sound_name$ + "_DBAP_" + preset_name_11$
elsif preset = 12
    new_name$ = sound_name$ + "_DBAP_" + preset_name_12$
elsif preset = 13
    new_name$ = sound_name$ + "_DBAP_" + preset_name_13$
elsif preset = 14
    new_name$ = sound_name$ + "_DBAP_" + preset_name_14$
endif

selectObject: combinedSound
Rename: new_name$

appendInfoLine: "Distance-Based Amplitude Panning complete!"
appendInfoLine: "Created: ", new_name$

Play
