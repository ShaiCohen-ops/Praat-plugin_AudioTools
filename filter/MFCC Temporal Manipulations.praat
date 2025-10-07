# ============================================================
# Praat AudioTools - MFCC Temporal Manipulations.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   MFCC Temporal Manipulations script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# MFCC Temporal Manipulations
# Various time-based transformations using MFCC analysis

form MFCC Temporal Manipulations
    comment Select manipulation type:
    optionmenu Manipulation_type 1
        option Reverse MFCC control
        option Spectral complexity time-stretch
        option Freeze spectral moments
        option MFCC trajectory scramble
    comment MFCC Parameters
    positive Number_of_coefficients 12
    positive Window_length_(s) 0.015
    positive Time_step_(s) 0.005
    positive First_filter_frequency_(Hz) 100
    positive Distance_between_filters_(Hz) 100
    real Maximum_frequency_(Hz) 0
    comment Manipulation-specific parameters
    comment For Spectral Complexity Time-stretch:
    positive Complexity_threshold 0.5
    positive Max_stretch_factor 2.0
    positive Min_stretch_factor 0.5
    comment For Freeze Spectral Moments:
    positive Freeze_duration_(s) 0.2
    positive Similarity_threshold 0.3
    comment For MFCC Trajectory Scramble:
    positive Scramble_window_(frames) 10
    comment Cleanup
    boolean Keep_intermediate_objects 0
endform

# Get the selected Sound object
sound = selected("Sound")
soundName$ = selected$("Sound")
duration = Get total duration
samplingFrequency = Get sampling frequency

writeInfoLine: "MFCC Temporal Manipulation"
appendInfoLine: "=========================="
appendInfoLine: "Processing: ", soundName$
appendInfoLine: "Type: ", manipulation_type$
appendInfoLine: ""

# Convert to MFCC
selectObject: sound
To MFCC: number_of_coefficients, window_length, time_step, first_filter_frequency, distance_between_filters, maximum_frequency
mfcc = selected("MFCC")

# Convert MFCC to Matrix
selectObject: mfcc
To Matrix
matrix = selected("Matrix")

# Extract dimensions
numFrames = Get number of columns
numCoeffs = Get number of rows

# Extract all MFCC coefficients
for i to numFrames
    for j to numCoeffs
        mfcc_data[i, j] = Get value in cell: j, i
    endfor
endfor

appendInfoLine: "MFCC frames extracted: ", numFrames
appendInfoLine: ""

# ========================================
# MANIPULATION 1: Reverse MFCC Control
# ========================================
if manipulation_type = 1
    appendInfoLine: "Applying Reverse MFCC Control..."
    
    # Reverse the MFCC timeline
    for i to numFrames
        reversedIndex = numFrames - i + 1
        for j to 3
            c_reversed[i, j] = mfcc_data[reversedIndex, j]
        endfor
    endfor
    
    # Normalize reversed coefficients
    for j to 3
        minVal = c_reversed[1, j]
        maxVal = c_reversed[1, j]
        for i from 2 to numFrames
            if c_reversed[i, j] < minVal
                minVal = c_reversed[i, j]
            endif
            if c_reversed[i, j] > maxVal
                maxVal = c_reversed[i, j]
            endif
        endfor
        
        for i to numFrames
            c_scaled[i, j] = (c_reversed[i, j] - minVal) / (maxVal - minVal + 0.0001)
        endfor
    endfor
    
    # Apply reversed control to sound
    selectObject: sound
    To Manipulation: 0.01, 75, 600
    manipulation = selected("Manipulation")
    
    selectObject: manipulation
    Extract pitch tier
    pitchTier = selected("PitchTier")
    
    selectObject: manipulation
    Extract duration tier
    durationTier = selected("DurationTier")
    
    # Apply reversed C1 to pitch
    selectObject: pitchTier
    for i to numFrames
        time = (i - 1) * time_step + window_length/2
        if time <= duration
            pitchFactor = 0.7 + (c_scaled[i, 1] * 0.6)
            Add point: time, 100 * pitchFactor
        endif
    endfor
    
    # Apply reversed C3 to duration
    selectObject: durationTier
    for i to numFrames
        time = (i - 1) * time_step + window_length/2
        if time <= duration
            durationFactor = 0.8 + (c_scaled[i, 3] * 0.4)
            Add point: time, durationFactor
        endif
    endfor
    
    selectObject: manipulation
    plus pitchTier
    Replace pitch tier
    
    selectObject: manipulation
    plus durationTier
    Replace duration tier
    
    selectObject: manipulation
    Get resynthesis (overlap-add)
    result = selected("Sound")
    Rename: soundName$ + "_reversed_MFCC"
    
    appendInfoLine: "Result: MFCC timeline reversed and applied"

# ========================================
# MANIPULATION 2: Spectral Complexity Time-Stretch
# ========================================
elsif manipulation_type = 2
    appendInfoLine: "Calculating spectral complexity..."
    
    # Calculate spectral complexity (variance across coefficients)
    for i to numFrames
        sum = 0
        for j from 2 to min(6, numCoeffs)
            sum += mfcc_data[i, j] * mfcc_data[i, j]
        endfor
        complexity[i] = sqrt(sum)
    endfor
    
    # Normalize complexity
    minComp = complexity[1]
    maxComp = complexity[1]
    for i from 2 to numFrames
        if complexity[i] < minComp
            minComp = complexity[i]
        endif
        if complexity[i] > maxComp
            maxComp = complexity[i]
        endif
    endfor
    
    for i to numFrames
        complexity_norm[i] = (complexity[i] - minComp) / (maxComp - minComp + 0.0001)
    endfor
    
    # Create duration tier based on complexity
    selectObject: sound
    To Manipulation: 0.01, 75, 600
    manipulation = selected("Manipulation")
    
    selectObject: manipulation
    Extract duration tier
    durationTier = selected("DurationTier")
    
    selectObject: durationTier
    for i to numFrames
        time = (i - 1) * time_step + window_length/2
        if time <= duration
            # High complexity = more stretch, low complexity = less stretch
            if complexity_norm[i] > complexity_threshold
                stretchFactor = 1 + ((complexity_norm[i] - complexity_threshold) / (1 - complexity_threshold)) * (max_stretch_factor - 1)
            else
                stretchFactor = min_stretch_factor + (complexity_norm[i] / complexity_threshold) * (1 - min_stretch_factor)
            endif
            Add point: time, stretchFactor
        endif
    endfor
    
    selectObject: manipulation
    plus durationTier
    Replace duration tier
    
    selectObject: manipulation
    Get resynthesis (overlap-add)
    result = selected("Sound")
    Rename: soundName$ + "_complexity_stretched"
    
    appendInfoLine: "Result: Time-stretched based on spectral complexity"
    appendInfoLine: "  Complex moments stretched up to ", fixed$(max_stretch_factor, 2), "x"

# ========================================
# MANIPULATION 3: Freeze Spectral Moments
# ========================================
elsif manipulation_type = 3
    appendInfoLine: "Finding spectral moments to freeze..."
    
    # Calculate spectral distance between consecutive frames
    for i from 2 to numFrames
        distance = 0
        for j to min(6, numCoeffs)
            diff = mfcc_data[i, j] - mfcc_data[i-1, j]
            distance += diff * diff
        endfor
        spectral_distance[i] = sqrt(distance)
    endfor
    
    # Normalize distances
    maxDist = spectral_distance[2]
    for i from 3 to numFrames
        if spectral_distance[i] > maxDist
            maxDist = spectral_distance[i]
        endif
    endfor
    
    for i from 2 to numFrames
        spectral_distance_norm[i] = spectral_distance[i] / (maxDist + 0.0001)
    endfor
    
    # Find moments with low spectral change (stable moments)
    numFreezes = 0
    for i from 2 to numFrames - 1
        if spectral_distance_norm[i] < similarity_threshold
            freeze_at[numFreezes + 1] = i
            numFreezes += 1
        endif
    endfor
    
    appendInfoLine: "Found ", numFreezes, " moments to freeze"
    
    # Apply freezing using duration manipulation
    selectObject: sound
    To Manipulation: 0.01, 75, 600
    manipulation = selected("Manipulation")
    
    selectObject: manipulation
    Extract duration tier
    durationTier = selected("DurationTier")
    
    # Add extreme slowdown at freeze points
    selectObject: durationTier
    for f to numFreezes
        frameIndex = freeze_at[f]
        freezeTime = (frameIndex - 1) * time_step + window_length/2
        
        if freezeTime > 0.01 and freezeTime < duration - 0.01
            # Create a freeze by extreme time stretching
            Add point: freezeTime - 0.01, 1.0
            Add point: freezeTime, 5.0
            Add point: freezeTime + freeze_duration, 5.0
            Add point: freezeTime + freeze_duration + 0.01, 1.0
        endif
    endfor
    
    selectObject: manipulation
    plus durationTier
    Replace duration tier
    
    selectObject: manipulation
    Get resynthesis (overlap-add)
    result = selected("Sound")
    Rename: soundName$ + "_frozen_moments"
    
    appendInfoLine: "Result: Spectral moments frozen (", numFreezes, " locations)"

# ========================================
# MANIPULATION 4: MFCC Trajectory Scramble
# ========================================
elsif manipulation_type = 4
    appendInfoLine: "Scrambling MFCC trajectory..."
    
    # Scramble MFCC values within windows
    for i to numFrames
        windowStart = max(1, round(i - scramble_window / 2))
        windowEnd = min(numFrames, round(i + scramble_window / 2))
        
        # Pick a random frame within the window
        windowSize = windowEnd - windowStart + 1
        if windowSize > 1
            randomOffset = randomInteger(0, windowSize - 1)
            sourceFrame = windowStart + randomOffset
        else
            sourceFrame = i
        endif
        
        for j to 3
            c_scrambled[i, j] = mfcc_data[sourceFrame, j]
        endfor
    endfor
    
    # Normalize scrambled coefficients
    for j to 3
        minVal = c_scrambled[1, j]
        maxVal = c_scrambled[1, j]
        for i from 2 to numFrames
            if c_scrambled[i, j] < minVal
                minVal = c_scrambled[i, j]
            endif
            if c_scrambled[i, j] > maxVal
                maxVal = c_scrambled[i, j]
            endif
        endfor
        
        for i to numFrames
            c_scaled[i, j] = (c_scrambled[i, j] - minVal) / (maxVal - minVal + 0.0001)
        endfor
    endfor
    
    # Apply scrambled control
    selectObject: sound
    To Manipulation: 0.01, 75, 600
    manipulation = selected("Manipulation")
    
    selectObject: manipulation
    Extract pitch tier
    pitchTier = selected("PitchTier")
    
    selectObject: manipulation
    Extract duration tier
    durationTier = selected("DurationTier")
    
    # Apply scrambled C1 to pitch
    selectObject: pitchTier
    for i to numFrames
        time = (i - 1) * time_step + window_length/2
        if time <= duration
            pitchFactor = 0.7 + (c_scaled[i, 1] * 0.6)
            Add point: time, 100 * pitchFactor
        endif
    endfor
    
    # Apply scrambled C2 to duration
    selectObject: durationTier
    for i to numFrames
        time = (i - 1) * time_step + window_length/2
        if time <= duration
            durationFactor = 0.8 + (c_scaled[i, 2] * 0.4)
            Add point: time, durationFactor
        endif
    endfor
    
    selectObject: manipulation
    plus pitchTier
    Replace pitch tier
    
    selectObject: manipulation
    plus durationTier
    Replace duration tier
    
    selectObject: manipulation
    Get resynthesis (overlap-add)
    result = selected("Sound")
    Rename: soundName$ + "_scrambled_MFCC"
    
    appendInfoLine: "Result: MFCC trajectory scrambled within ", scramble_window, "-frame windows"
endif

# Cleanup
if keep_intermediate_objects = 0
    removeObject: mfcc
    removeObject: matrix
    if manipulation_type = 1
        removeObject: manipulation
        removeObject: pitchTier
        removeObject: durationTier
    elsif manipulation_type = 2
        removeObject: manipulation
        removeObject: durationTier
    elsif manipulation_type = 3
        removeObject: manipulation
        removeObject: durationTier
    elsif manipulation_type = 4
        removeObject: manipulation
        removeObject: pitchTier
        removeObject: durationTier
    endif
    appendInfoLine: ""
    appendInfoLine: "Intermediate objects removed"
endif
Play

appendInfoLine: ""
appendInfoLine: "Processing complete!"
selectObject: result