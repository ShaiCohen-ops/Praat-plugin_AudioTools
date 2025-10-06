# ============================================================
# Praat AudioTools - Panning variations.praat
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

# Form for user input
form IntensityTier Multiplier
    optionmenu Formula_type 7
        option Sine wave
        option Fade in
        option Fade out
        option Triangle envelope
        option Constant value
        option Exponential fade
        option Linear sweep (left to right)
        option Circular rotation
        option Figure-8 pattern
        option Random walk
        option Spiral motion
        option Custom position
    positive Fadein_time 1.0
    positive Frequency_hz 2.0
    positive Amplitude 50.0
    positive Constant_value 70.0
    positive Exponent 1.0
    positive Motion_speed 1.0
    positive Random_seed 1
    positive Custom_x 0.5
    positive Custom_y 0.5
    positive Number_of_points 100
    positive Min_volume 70.0
endform

Convert to mono

# Get the selected sound
sound = selected("Sound")
soundName$ = selected$("Sound")
duration = Get total duration

# Display sound info
appendInfoLine: "Sound duration: ", duration, " seconds"
appendInfoLine: "Selected formula type: ", formula_type

# Check if sound is mono or stereo
selectObject: sound
numberOfChannels = Get number of channels

if numberOfChannels = 1
    # For mono sound, duplicate it to create left and right channels
    leftChannel = Copy: "left_" + soundName$
    rightChannel = Copy: "right_" + soundName$
else
    # For stereo sound, extract existing channels
    leftChannel = Extract one channel: 1
    rightChannel = Extract one channel: 2
endif

# Create TWO IntensityTiers for left and right channels
selectObject: sound
leftIntensityTier = Create IntensityTier: "left_" + soundName$, 0, duration
rightIntensityTier = Create IntensityTier: "right_" + soundName$, 0, duration

# Add points to both IntensityTiers
selectObject: leftIntensityTier
for i from 0 to number_of_points
    time = i * duration / number_of_points
    Add point: time, 70.0
endfor

selectObject: rightIntensityTier
for i from 0 to number_of_points
    time = i * duration / number_of_points
    Add point: time, 70.0
endfor

# Apply panning formulas to left and right channels (with minimum volume)
if formula_type = 7
    # Linear sweep (left to right) - with minimum volume
    selectObject: leftIntensityTier
    Formula: string$(min_volume) + " + " + string$(100 - min_volume) + " * (1 - (x/" + string$(duration) + "))"
    selectObject: rightIntensityTier
    Formula: string$(min_volume) + " + " + string$(100 - min_volume) + " * (x/" + string$(duration) + ")"
    
elsif formula_type = 8
    # Circular rotation - with minimum volume
    selectObject: leftIntensityTier
    Formula: string$(min_volume) + " + " + string$((100 - min_volume) / 2) + " * (1 + sin(2*pi*" + string$(motion_speed) + "*x))"
    selectObject: rightIntensityTier
    Formula: string$(min_volume) + " + " + string$((100 - min_volume) / 2) + " * (1 + cos(2*pi*" + string$(motion_speed) + "*x))"
    
elsif formula_type = 9
    # Figure-8 pattern - with minimum volume
    selectObject: leftIntensityTier
    Formula: string$(min_volume) + " + " + string$((100 - min_volume) / 2) + " * (1 + sin(4*pi*" + string$(motion_speed) + "*x))"
    selectObject: rightIntensityTier
    Formula: string$(min_volume) + " + " + string$((100 - min_volume) / 2) + " * (1 + cos(4*pi*" + string$(motion_speed) + "*x))"
    
elsif formula_type = 10
    # Random walk - with minimum volume
    selectObject: leftIntensityTier
    Formula: string$(min_volume) + " + " + string$((100 - min_volume) / 2) + " * (1 + sin(" + string$(random_seed) + " + x*" + string$(motion_speed) + "))"
    selectObject: rightIntensityTier
    Formula: string$(min_volume) + " + " + string$((100 - min_volume) / 2) + " * (1 + cos(" + string$(random_seed) + " + x*" + string$(motion_speed) + "))"
    
elsif formula_type = 11
    # Spiral motion - with minimum volume
    selectObject: leftIntensityTier
    Formula: string$(min_volume) + " + " + string$((100 - min_volume) / 2) + " * (1 + (x/" + string$(duration) + ") * sin(2*pi*" + string$(motion_speed) + "*x))"
    selectObject: rightIntensityTier
    Formula: string$(min_volume) + " + " + string$((100 - min_volume) / 2) + " * (1 + (x/" + string$(duration) + ") * cos(2*pi*" + string$(motion_speed) + "*x))"
    
elsif formula_type = 12
    # Custom position - balance control with minimum volume
    selectObject: leftIntensityTier
    Formula: string$(min_volume + (1 - custom_x) * (100 - min_volume))
    selectObject: rightIntensityTier
    Formula: string$(min_volume + custom_x * (100 - min_volume))
    
else
    # For non-spatial effects, apply same formula to both channels
    selectObject: leftIntensityTier
    if formula_type = 1
        Formula: string$(amplitude + 50) + " + " + string$(amplitude) + "*sin(2*pi*" + string$(frequency_hz) + "*x)"
    elsif formula_type = 2
        Formula: "if x < " + string$(fadein_time) + " then 100 * (x/" + string$(fadein_time) + ") else 100 endif"
    elsif formula_type = 3
        Formula: "100 * (1 - (x/" + string$(duration) + "))"
    elsif formula_type = 4
        Formula: "100 * (1 - 2*abs(x/" + string$(duration) + " - 0.5))"
    elsif formula_type = 5
        Formula: string$(constant_value)
    elsif formula_type = 6
        Formula: "100 * exp(-" + string$(exponent) + "*x)"
    endif
    # Copy same formula to right channel
    selectObject: rightIntensityTier
    if formula_type = 1
        Formula: string$(amplitude + 50) + " + " + string$(amplitude) + "*sin(2*pi*" + string$(frequency_hz) + "*x)"
    elsif formula_type = 2
        Formula: "if x < " + string$(fadein_time) + " then 100 * (x/" + string$(fadein_time) + ") else 100 endif"
    elsif formula_type = 3
        Formula: "100 * (1 - (x/" + string$(duration) + "))"
    elsif formula_type = 4
        Formula: "100 * (1 - 2*abs(x/" + string$(duration) + " - 0.5))"
    elsif formula_type = 5
        Formula: string$(constant_value)
    elsif formula_type = 6
        Formula: "100 * exp(-" + string$(exponent) + "*x)"
    endif
endif

# Multiply each channel separately with its IntensityTier
selectObject: leftChannel, leftIntensityTier
leftResult = Multiply: "yes"

selectObject: rightChannel, rightIntensityTier
rightResult = Multiply: "yes"

# Combine the processed channels back to stereo
selectObject: leftResult, rightResult
resultSound = Combine to stereo

# Clean up temporary objects
removeObject: leftChannel, rightChannel, leftResult, rightResult, leftIntensityTier, rightIntensityTier

# Select and play the result
selectObject: resultSound
Play

appendInfoLine: "Stereo panning complete!"
appendInfoLine: "Formula type: ", formula_type
appendInfoLine: "Output: Stereo sound with panning effects"