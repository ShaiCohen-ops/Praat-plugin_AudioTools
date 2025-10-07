# ============================================================
# Praat AudioTools - MFCC-based Sound Controller.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   MFCC-based Sound Controller script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# MFCC-based Sound Controller
# Extracts C1, C2, C3 from MFCC and uses them to manipulate the original sound

form MFCC Sound Controller
    comment MFCC Parameters
    positive Number_of_coefficients 12
    positive Window_length_(s) 0.015
    positive Time_step_(s) 0.005
    positive First_filter_frequency_(Hz) 100
    positive Distance_between_filters_(Hz) 100
    real Maximum_frequency_(Hz) 0
    comment Control Mapping Ranges
    comment C1 controls Pitch
    positive C1_pitch_min 0.7
    positive C1_pitch_max 1.3
    comment C2 controls Amplitude
    positive C2_amplitude_min 0.5
    positive C2_amplitude_max 1.0
    comment C3 controls Duration
    positive C3_duration_min 0.8
    positive C3_duration_max 1.2
    comment Cleanup Options
    boolean Keep_intermediate_objects 0
endform

# Get the selected Sound object
sound = selected("Sound")
soundName$ = selected$("Sound")
duration = Get total duration
samplingFrequency = Get sampling frequency

# Convert to MFCC
selectObject: sound
To MFCC: number_of_coefficients, window_length, time_step, first_filter_frequency, distance_between_filters, maximum_frequency

# Get the MFCC object
mfcc = selected("MFCC")

# Convert MFCC to Matrix
selectObject: mfcc
To Matrix

# Get the Matrix object
matrix = selected("Matrix")

# Extract dimensions
numFrames = Get number of columns
numCoeffs = Get number of rows

# Create arrays to store C1, C2, C3 values
for i to numFrames
    c1[i] = Get value in cell: 1, i
    c2[i] = Get value in cell: 2, i
    c3[i] = Get value in cell: 3, i
endfor

# Normalize coefficients to 0-1 range for control
# Find min and max for each coefficient
minC1 = c1[1]
maxC1 = c1[1]
minC2 = c2[1]
maxC2 = c2[1]
minC3 = c3[1]
maxC3 = c3[1]

for i from 2 to numFrames
    if c1[i] < minC1
        minC1 = c1[i]
    endif
    if c1[i] > maxC1
        maxC1 = c1[i]
    endif
    if c2[i] < minC2
        minC2 = c2[i]
    endif
    if c2[i] > maxC2
        maxC2 = c2[i]
    endif
    if c3[i] < minC3
        minC3 = c3[i]
    endif
    if c3[i] > maxC3
        maxC3 = c3[i]
    endif
endfor

# Scale coefficients
for i to numFrames
    c1_scaled[i] = (c1[i] - minC1) / (maxC1 - minC1)
    c2_scaled[i] = (c2[i] - minC2) / (maxC2 - minC2)
    c3_scaled[i] = (c3[i] - minC3) / (maxC3 - minC3)
endfor

# Calculate frame parameters
frameTime = time_step

# Manipulate the original sound using MFCC coefficients as controllers
selectObject: sound

# Create manipulation object
To Manipulation: 0.01, 75, 600

manipulation = selected("Manipulation")

# Extract pitch tier for manipulation
selectObject: manipulation
Extract pitch tier
pitchTier = selected("PitchTier")

# Extract duration tier
selectObject: manipulation
Extract duration tier
durationTier = selected("DurationTier")

# Use C1 for pitch scaling
# Use C2 for intensity/amplitude modulation
# Use C3 for duration/speed variation

# Modify pitch using C1
selectObject: pitchTier
for i to numFrames
    time = (i - 1) * time_step + window_length/2
    if time <= duration
        # C1 controls pitch using user-defined range
        pitchFactor = c1_pitch_min + (c1_scaled[i] * (c1_pitch_max - c1_pitch_min))
        Add point: time, 100 * pitchFactor
    endif
endfor

# Modify duration using C3
selectObject: durationTier
for i to numFrames
    time = (i - 1) * time_step + window_length/2
    if time <= duration
        # C3 controls duration using user-defined range
        durationFactor = c3_duration_min + (c3_scaled[i] * (c3_duration_max - c3_duration_min))
        Add point: time, durationFactor
    endif
endfor

# Replace tiers in manipulation
selectObject: manipulation
plus pitchTier
Replace pitch tier

selectObject: manipulation
plus durationTier
Replace duration tier

# Create manipulated sound
selectObject: manipulation
Get resynthesis (overlap-add)

manipulatedSound = selected("Sound")

# Apply amplitude modulation based on C2 using user-defined range
selectObject: manipulatedSound
amplitudeRange = c2_amplitude_max - c2_amplitude_min
Formula: "self * (c2_amplitude_min + c2_scaled[max(1, min(numFrames, round((x / duration) * numFrames)))] * amplitudeRange)"

Rename: soundName$ + "_MFCC_controlled"

# Print summary
writeInfoLine: "MFCC Sound Manipulation Complete"
appendInfoLine: "=================================="
appendInfoLine: ""
appendInfoLine: "Original sound: ", soundName$
appendInfoLine: "Duration: ", fixed$(duration, 3), " seconds"
appendInfoLine: "Sampling frequency: ", samplingFrequency, " Hz"
appendInfoLine: ""
appendInfoLine: "MFCC Parameters:"
appendInfoLine: "  Coefficients: ", number_of_coefficients
appendInfoLine: "  Window length: ", fixed$(window_length, 3), " s"
appendInfoLine: "  Time step: ", fixed$(time_step, 3), " s"
appendInfoLine: "  Number of frames: ", numFrames
appendInfoLine: ""
appendInfoLine: "Coefficient ranges:"
appendInfoLine: "  C1: ", fixed$(minC1, 3), " to ", fixed$(maxC1, 3)
appendInfoLine: "      → Pitch control: ", fixed$(c1_pitch_min, 2), "x to ", fixed$(c1_pitch_max, 2), "x"
appendInfoLine: "  C2: ", fixed$(minC2, 3), " to ", fixed$(maxC2, 3)
appendInfoLine: "      → Amplitude control: ", fixed$(c2_amplitude_min, 2), "x to ", fixed$(c2_amplitude_max, 2), "x"
appendInfoLine: "  C3: ", fixed$(minC3, 3), " to ", fixed$(maxC3, 3)
appendInfoLine: "      → Duration control: ", fixed$(c3_duration_min, 2), "x to ", fixed$(c3_duration_max, 2), "x"
appendInfoLine: ""
appendInfoLine: "Output: ", soundName$, "_MFCC_controlled"

# Clean up intermediate objects
if keep_intermediate_objects = 0
    removeObject: mfcc, matrix, manipulation, pitchTier, durationTier
    appendInfoLine: ""
    appendInfoLine: "Intermediate objects removed."
else
    appendInfoLine: ""
    appendInfoLine: "Intermediate objects kept in object list."
endif
Play

# Select the new sound for listening
selectObject: manipulatedSound