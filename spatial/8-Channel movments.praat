# ============================================================
# Praat AudioTools - 8-Channel movments.praat
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
    positive Min_volume 30.0
endform

# Get the selected sound
sound = selected("Sound")
soundName$ = selected$("Sound")
duration = Get total duration

# Display sound info
appendInfoLine: "Sound duration: ", duration, " seconds"
appendInfoLine: "Selected formula type: ", formula_type
appendInfoLine: "Creating 8-channel surround sound..."

# Create 8 mono channels from the source
selectObject: sound
channel1 = Copy: "ch1_" + soundName$
channel2 = Copy: "ch2_" + soundName$
channel3 = Copy: "ch3_" + soundName$
channel4 = Copy: "ch4_" + soundName$
channel5 = Copy: "ch5_" + soundName$
channel6 = Copy: "ch6_" + soundName$
channel7 = Copy: "ch7_" + soundName$
channel8 = Copy: "ch8_" + soundName$

# Create 8 IntensityTiers (one for each channel)
selectObject: sound
intensityTier1 = Create IntensityTier: "int1_" + soundName$, 0, duration
intensityTier2 = Create IntensityTier: "int2_" + soundName$, 0, duration
intensityTier3 = Create IntensityTier: "int3_" + soundName$, 0, duration
intensityTier4 = Create IntensityTier: "int4_" + soundName$, 0, duration
intensityTier5 = Create IntensityTier: "int5_" + soundName$, 0, duration
intensityTier6 = Create IntensityTier: "int6_" + soundName$, 0, duration
intensityTier7 = Create IntensityTier: "int7_" + soundName$, 0, duration
intensityTier8 = Create IntensityTier: "int8_" + soundName$, 0, duration

# Add initial points to all IntensityTiers
for tier from 1 to 8
    selectObject: intensityTier'tier'
    for i from 0 to number_of_points
        time = i * duration / number_of_points
        Add point: time, 70.0
    endfor
endfor

# Apply 8-channel panning formulas
if formula_type = 7
    # Linear sweep around 8 channels
    for tier from 1 to 8
        selectObject: intensityTier'tier'
        # Each channel peaks at a different time in the sweep
        peakTime = (tier - 1) / 8
        Formula: string$(min_volume) + " + " + string$(100 - min_volume) + " * exp(-10 * ((x/" + string$(duration) + ") - " + string$(peakTime) + ")^2)"
    endfor
    
elsif formula_type = 8
    # Circular rotation around 8 channels
    for tier from 1 to 8
        selectObject: intensityTier'tier'
        # Each channel offset by 45 degrees (360/8 = 45)
        angle = (tier - 1) * 45
        Formula: string$(min_volume) + " + " + string$((100 - min_volume) / 2) + " * (1 + cos(2*pi*" + string$(motion_speed) + "*x - " + string$(angle * pi / 180) + "))"
    endfor
    
elsif formula_type = 9
    # Figure-8 pattern across 8 channels
    for tier from 1 to 8
        selectObject: intensityTier'tier'
        angle = (tier - 1) * 45
        Formula: string$(min_volume) + " + " + string$((100 - min_volume) / 2) + " * (1 + sin(4*pi*" + string$(motion_speed) + "*x + " + string$(angle * pi / 180) + "))"
    endfor
    
elsif formula_type = 10
    # Random walk across 8 channels
    for tier from 1 to 8
        selectObject: intensityTier'tier'
        phase = random_seed + tier * 1.234
        Formula: string$(min_volume) + " + " + string$((100 - min_volume) / 2) + " * (1 + sin(" + string$(phase) + " + x*" + string$(motion_speed) + "))"
    endfor
    
elsif formula_type = 11
    # Spiral motion across 8 channels
    for tier from 1 to 8
        selectObject: intensityTier'tier'
        angle = (tier - 1) * 45
        Formula: string$(min_volume) + " + " + string$((100 - min_volume) / 2) + " * (1 + (x/" + string$(duration) + ") * sin(2*pi*" + string$(motion_speed) + "*x + " + string$(angle * pi / 180) + "))"
    endfor
    
elsif formula_type = 12
    # Custom position - focus on specific channels based on x,y coordinates
    for tier from 1 to 8
        selectObject: intensityTier'tier'
        # Map 8 channels to surround positions (front-left, front, front-right, right, back-right, back, back-left, left)
        if tier = 1
            # Front-left
            distance = sqrt((custom_x - 0.25)^2 + (custom_y - 0.25)^2)
        elsif tier = 2
            # Front-center
            distance = sqrt((custom_x - 0.5)^2 + (custom_y - 0.25)^2)
        elsif tier = 3
            # Front-right
            distance = sqrt((custom_x - 0.75)^2 + (custom_y - 0.25)^2)
        elsif tier = 4
            # Right
            distance = sqrt((custom_x - 0.75)^2 + (custom_y - 0.5)^2)
        elsif tier = 5
            # Back-right
            distance = sqrt((custom_x - 0.75)^2 + (custom_y - 0.75)^2)
        elsif tier = 6
            # Back-center
            distance = sqrt((custom_x - 0.5)^2 + (custom_y - 0.75)^2)
        elsif tier = 7
            # Back-left
            distance = sqrt((custom_x - 0.25)^2 + (custom_y - 0.75)^2)
        else
            # Left
            distance = sqrt((custom_x - 0.25)^2 + (custom_y - 0.5)^2)
        endif
        volume = min_volume + (100 - min_volume) * exp(-distance * 10)
        Formula: string$(volume)
    endfor
    
else
    # For non-spatial effects, apply same formula to all channels
    for tier from 1 to 8
        selectObject: intensityTier'tier'
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
    endfor
endif

# Multiply each channel with its IntensityTier
selectObject: channel1, intensityTier1
result1 = Multiply: "yes"
selectObject: channel2, intensityTier2
result2 = Multiply: "yes"
selectObject: channel3, intensityTier3
result3 = Multiply: "yes"
selectObject: channel4, intensityTier4
result4 = Multiply: "yes"
selectObject: channel5, intensityTier5
result5 = Multiply: "yes"
selectObject: channel6, intensityTier6
result6 = Multiply: "yes"
selectObject: channel7, intensityTier7
result7 = Multiply: "yes"
selectObject: channel8, intensityTier8
result8 = Multiply: "yes"

# Combine all 8 channels into one multi-channel sound
selectObject: result1, result2, result3, result4, result5, result6, result7, result8
resultSound = Combine to stereo

# Clean up temporary objects
removeObject: channel1, channel2, channel3, channel4, channel5, channel6, channel7, channel8
removeObject: intensityTier1, intensityTier2, intensityTier3, intensityTier4, intensityTier5, intensityTier6, intensityTier7, intensityTier8
removeObject: result1, result2, result3, result4, result5, result6, result7, result8

# Select and play the result
selectObject: resultSound
Play

appendInfoLine: "8-channel surround panning complete!"
appendInfoLine: "Formula type: ", formula_type
appendInfoLine: "Output: 8-channel surround sound with spatial effects"