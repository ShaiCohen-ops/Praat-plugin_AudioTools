# ============================================================
# Praat AudioTools - MFCC-DRIVEN MODULATOR
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   MFCC-derived prosodic and amplitude modulation toolkit.
#   Uses spectral envelope features (MFCCs) to drive pitch,
#   duration, and amplitude modifications via Praat's 
#   Manipulation framework.
#
# Note: MFCCs encode timbral/spectral envelope information.
#   This script uses them as control signals for prosodic
#   parameters - an artistic mapping, not a reconstruction.
#
# Algorithms:
#   1. Direct Control - C1→Pitch scaling, C2→Amplitude, C3→Duration
#   2. Reverse Control - Reverses MFCC timeline for modulation
#   3. Complexity Time-Stretch - Adaptive stretching based on spectral complexity
#   4. Freeze Spectral Moments - Extends temporally stable regions
#   5. Trajectory Scramble - Local randomization of MFCC trajectories
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit 
#   for Experimental Composition.
# ============================================================

form MFCC-Driven Modulator
    comment ======== PRESETS (Choose one or use Custom) ========
    optionmenu Preset 1
        option Custom
        option Direct: Subtle
        option Direct: Wide Range
        option Direct: Pitch Focus
        option Reverse: Classic
        option Reverse: Dramatic
        option Complexity: Moderate
        option Complexity: Extreme
        option Freeze: Sparse
        option Freeze: Dense
        option Scramble: Subtle
        option Scramble: Wild

    comment ======== MANUAL SETTINGS (Custom only) ========
    optionmenu Algorithm 1
        option Direct Control
        option Reverse Control
        option Complexity Stretch
        option Freeze Moments
        option Trajectory Scramble
    
    comment Control Ranges (Direct Control only):
    real Pitch_range 0.6
    comment (±range from 1.0, e.g., 0.6 = 0.4 to 1.6)
    real Duration_range 0.3
    comment (±range from 1.0)
    
    comment Other Algorithm Parameters:
    positive Complexity_threshold 0.5
    positive Max_stretch_factor 2.0
    positive Freeze_duration_(s) 0.2
    positive Min_freeze_gap_(s) 0.1
    positive Scramble_window_(frames) 10
    
    comment Output:
    boolean Play_result 1
endform

# ============================================================
# Check Selection
# ============================================================
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")
duration = Get total duration
samplingFrequency = Get sampling frequency

# Validate minimum duration
if duration < 0.1
    exitScript: "Sound is too short (minimum 0.1s required)."
endif

# ============================================================
# PRESET LOGIC
# ============================================================
algo = algorithm

# Fixed MFCC parameters
# max_freq = 0 means auto-detect based on sampling frequency
num_coeffs = 12
win_len = 0.015
t_step = 0.005
first_freq = 100
filter_dist = 100
max_freq = 0

# Default algorithm parameters
c1_p_min = 1.0 - pitch_range
c1_p_max = 1.0 + pitch_range
c2_a_min = 0.5
c2_a_max = 1.0
c3_d_min = 1.0 - duration_range
c3_d_max = 1.0 + duration_range
comp_thresh = complexity_threshold
max_stretch = max_stretch_factor
min_stretch = 0.5
freeze_dur = freeze_duration
min_gap = min_freeze_gap
sim_thresh = 0.3
scramble_win = scramble_window

# Override with presets
if preset$ = "Direct: Subtle"
    algo = 1
    c1_p_min = 0.9
    c1_p_max = 1.1
    c2_a_min = 0.8
    c2_a_max = 1.0
    c3_d_min = 0.95
    c3_d_max = 1.05

elsif preset$ = "Direct: Wide Range"
    algo = 1
    c1_p_min = 0.5
    c1_p_max = 1.5
    c2_a_min = 0.3
    c2_a_max = 1.0
    c3_d_min = 0.7
    c3_d_max = 1.3

elsif preset$ = "Direct: Pitch Focus"
    algo = 1
    c1_p_min = 0.6
    c1_p_max = 1.6
    c2_a_min = 0.9
    c2_a_max = 1.0
    c3_d_min = 0.95
    c3_d_max = 1.05

elsif preset$ = "Reverse: Classic"
    algo = 2
    c1_p_min = 0.7
    c1_p_max = 1.3
    c3_d_min = 0.8
    c3_d_max = 1.2

elsif preset$ = "Reverse: Dramatic"
    algo = 2
    c1_p_min = 0.5
    c1_p_max = 1.5
    c3_d_min = 0.6
    c3_d_max = 1.4

elsif preset$ = "Complexity: Moderate"
    algo = 3
    comp_thresh = 0.5
    max_stretch = 2.0
    min_stretch = 0.7

elsif preset$ = "Complexity: Extreme"
    algo = 3
    comp_thresh = 0.4
    max_stretch = 4.0
    min_stretch = 0.5

elsif preset$ = "Freeze: Sparse"
    algo = 4
    freeze_dur = 0.15
    sim_thresh = 0.2
    min_gap = 0.15

elsif preset$ = "Freeze: Dense"
    algo = 4
    freeze_dur = 0.2
    sim_thresh = 0.4
    min_gap = 0.1

elsif preset$ = "Scramble: Subtle"
    algo = 5
    scramble_win = 5
    c1_p_min = 0.8
    c1_p_max = 1.2
    c3_d_min = 0.9
    c3_d_max = 1.1

elsif preset$ = "Scramble: Wild"
    algo = 5
    scramble_win = 30
    c1_p_min = 0.6
    c1_p_max = 1.4
    c3_d_min = 0.7
    c3_d_max = 1.3

endif

# ============================================================
# Initialize Info
# ============================================================
algo_name$ = ""
if algo = 1
    algo_name$ = "_DirectControl"
elsif algo = 2
    algo_name$ = "_Reversed"
elsif algo = 3
    algo_name$ = "_ComplexityStretch"
elsif algo = 4
    algo_name$ = "_FrozenMoments"
elsif algo = 5
    algo_name$ = "_Scrambled"
endif

writeInfoLine: "MFCC-Driven Modulator"
appendInfoLine: "====================="
appendInfoLine: "Processing: ", soundName$
appendInfoLine: "Algorithm: ", algo_name$
appendInfoLine: ""

# ============================================================
# SHARED MFCC EXTRACTION
# ============================================================
selectObject: sound
To MFCC: num_coeffs, win_len, t_step, first_freq, filter_dist, max_freq
mfcc = selected("MFCC")

selectObject: mfcc
To Matrix
matrix = selected("Matrix")

numFrames = Get number of columns
numCoeffs = Get number of rows

# Validate frame count
if numFrames < 3
    removeObject: mfcc, matrix
    exitScript: "Sound is too short - not enough MFCC frames extracted."
endif

# Extract MFCC data into array
for i to numFrames
    for j to min(numCoeffs, 12)
        mfcc_data[i, j] = Get value in cell: j, i
    endfor
endfor

appendInfoLine: "MFCC frames: ", numFrames
appendInfoLine: "MFCC coefficients: ", numCoeffs
appendInfoLine: ""

# ============================================================
# ALGORITHM IMPLEMENTATION
# ============================================================

# ALGORITHM 1: DIRECT CONTROL
# Maps C1→Pitch (scaling), C2→Amplitude, C3→Duration
if algo = 1
    appendInfoLine: "Direct Control Mode"
    appendInfoLine: "  Pitch range: ", c1_p_min, " - ", c1_p_max
    appendInfoLine: "  Amplitude range: ", c2_a_min, " - ", c2_a_max
    appendInfoLine: "  Duration range: ", c3_d_min, " - ", c3_d_max
    
    # Extract coefficients C1, C2, C3
    for i to numFrames
        c1[i] = mfcc_data[i, 1]
        c2[i] = mfcc_data[i, 2]
        c3[i] = mfcc_data[i, 3]
    endfor
    
    # Find min/max for normalization
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
    
    # Normalize to 0-1
    for i to numFrames
        c1_scaled[i] = (c1[i] - minC1) / (maxC1 - minC1 + 0.0001)
        c2_scaled[i] = (c2[i] - minC2) / (maxC2 - minC2 + 0.0001)
        c3_scaled[i] = (c3[i] - minC3) / (maxC3 - minC3 + 0.0001)
    endfor
    
    # Create Manipulation object
    selectObject: sound
    To Manipulation: 0.01, 75, 600
    manipulation = selected("Manipulation")
    
    # Extract original pitch tier (to preserve original pitch structure)
    selectObject: manipulation
    Extract pitch tier
    originalPitchTier = selected("PitchTier")
    
    # Create new pitch tier with scaled values
    Create PitchTier: "newPitch", 0, duration
    newPitchTier = selected("PitchTier")
    
    # Extract duration tier
    selectObject: manipulation
    Extract duration tier
    durationTier = selected("DurationTier")
    
    # Apply pitch scaling (multiply original pitch by factor)
    selectObject: newPitchTier
    for i to numFrames
        time = (i - 1) * t_step + win_len/2
        if time > 0 and time < duration
            # Get original pitch at this time
            selectObject: originalPitchTier
            originalPitch = Get value at time: time
            
            if originalPitch <> undefined and originalPitch > 0
                # Scale the original pitch
                pitchFactor = c1_p_min + (c1_scaled[i] * (c1_p_max - c1_p_min))
                newPitch = originalPitch * pitchFactor
                # Clamp to reasonable range
                newPitch = max(50, min(800, newPitch))
                selectObject: newPitchTier
                Add point: time, newPitch
            endif
        endif
    endfor
    
    # Apply duration modulation
    selectObject: durationTier
    for i to numFrames
        time = (i - 1) * t_step + win_len/2
        if time > 0 and time < duration
            durationFactor = c3_d_min + (c3_scaled[i] * (c3_d_max - c3_d_min))
            Add point: time, durationFactor
        endif
    endfor
    
    # Replace tiers in manipulation
    selectObject: manipulation
    plusObject: newPitchTier
    Replace pitch tier
    
    selectObject: manipulation
    plusObject: durationTier
    Replace duration tier
    
    # Resynthesize
    selectObject: manipulation
    Get resynthesis (overlap-add)
    result = selected("Sound")
    
    # Apply amplitude modulation BEFORE time stretching would occur
    # Store the amplitude envelope based on original time mapping
    amplitudeRange = c2_a_max - c2_a_min
    
    # Apply amplitude scaling
    selectObject: result
    resultDuration = Get total duration
    
    # Create amplitude-modulated version
    Formula: ~ self * (c2_a_min + c2_scaled[max(1, min(numFrames, round((x / resultDuration) * numFrames)))] * amplitudeRange)
    
    Rename: soundName$ + algo_name$
    removeObject: manipulation, originalPitchTier, newPitchTier, durationTier

# ALGORITHM 2: REVERSE CONTROL
# Reverses MFCC trajectory for modulation control
elsif algo = 2
    appendInfoLine: "Reverse Control Mode"
    appendInfoLine: "  Pitch range: ", c1_p_min, " - ", c1_p_max
    appendInfoLine: "  Duration range: ", c3_d_min, " - ", c3_d_max
    
    # Reverse the MFCC coefficients
    for i to numFrames
        reversedIndex = numFrames - i + 1
        for j to 3
            c_reversed[i, j] = mfcc_data[reversedIndex, j]
        endfor
    endfor
    
    # Normalize each coefficient
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
    
    # Create Manipulation
    selectObject: sound
    To Manipulation: 0.01, 75, 600
    manipulation = selected("Manipulation")
    
    # Extract original pitch tier
    selectObject: manipulation
    Extract pitch tier
    originalPitchTier = selected("PitchTier")
    
    # Create new pitch tier
    Create PitchTier: "newPitch", 0, duration
    newPitchTier = selected("PitchTier")
    
    selectObject: manipulation
    Extract duration tier
    durationTier = selected("DurationTier")
    
    # Apply reversed pitch scaling
    selectObject: newPitchTier
    for i to numFrames
        time = (i - 1) * t_step + win_len/2
        if time > 0 and time < duration
            selectObject: originalPitchTier
            originalPitch = Get value at time: time
            
            if originalPitch <> undefined and originalPitch > 0
                pitchFactor = c1_p_min + (c_scaled[i, 1] * (c1_p_max - c1_p_min))
                newPitch = originalPitch * pitchFactor
                newPitch = max(50, min(800, newPitch))
                selectObject: newPitchTier
                Add point: time, newPitch
            endif
        endif
    endfor
    
    # Apply reversed duration modulation
    selectObject: durationTier
    for i to numFrames
        time = (i - 1) * t_step + win_len/2
        if time > 0 and time < duration
            durationFactor = c3_d_min + (c_scaled[i, 3] * (c3_d_max - c3_d_min))
            Add point: time, durationFactor
        endif
    endfor
    
    # Replace tiers
    selectObject: manipulation
    plusObject: newPitchTier
    Replace pitch tier
    
    selectObject: manipulation
    plusObject: durationTier
    Replace duration tier
    
    # Resynthesize
    selectObject: manipulation
    Get resynthesis (overlap-add)
    result = selected("Sound")
    Rename: soundName$ + algo_name$
    removeObject: manipulation, originalPitchTier, newPitchTier, durationTier

# ALGORITHM 3: COMPLEXITY TIME-STRETCH
# Stretches complex regions, compresses simple ones
elsif algo = 3
    appendInfoLine: "Complexity Time-Stretch Mode"
    appendInfoLine: "  Threshold: ", comp_thresh
    appendInfoLine: "  Stretch range: ", min_stretch, " - ", max_stretch
    
    # Calculate spectral complexity (RMS of coefficients 2-6)
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
    
    # Create Manipulation
    selectObject: sound
    To Manipulation: 0.01, 75, 600
    manipulation = selected("Manipulation")
    
    selectObject: manipulation
    Extract duration tier
    durationTier = selected("DurationTier")
    
    # Apply complexity-based stretching
    selectObject: durationTier
    for i to numFrames
        time = (i - 1) * t_step + win_len/2
        if time > 0 and time < duration
            if complexity_norm[i] > comp_thresh
                # Complex region: stretch
                stretchFactor = 1 + ((complexity_norm[i] - comp_thresh) / (1 - comp_thresh + 0.0001)) * (max_stretch - 1)
            else
                # Simple region: compress
                stretchFactor = min_stretch + (complexity_norm[i] / (comp_thresh + 0.0001)) * (1 - min_stretch)
            endif
            # Clamp stretch factor
            stretchFactor = max(min_stretch, min(max_stretch, stretchFactor))
            Add point: time, stretchFactor
        endif
    endfor
    
    # Replace duration tier
    selectObject: manipulation
    plusObject: durationTier
    Replace duration tier
    
    # Resynthesize
    selectObject: manipulation
    Get resynthesis (overlap-add)
    result = selected("Sound")
    Rename: soundName$ + algo_name$
    removeObject: manipulation, durationTier

# ALGORITHM 4: FREEZE SPECTRAL MOMENTS
# Extends temporally stable spectral regions
elsif algo = 4
    appendInfoLine: "Freeze Spectral Moments Mode"
    appendInfoLine: "  Similarity threshold: ", sim_thresh
    appendInfoLine: "  Freeze duration: ", freeze_dur, "s"
    appendInfoLine: "  Minimum gap: ", min_gap, "s"
    
    # Calculate frame-to-frame spectral distance
    spectral_distance[1] = 0
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
    
    # Find freeze points (stable regions) with minimum gap enforcement
    numFreezes = 0
    lastFreezeTime = -1000
    
    for i from 2 to numFrames - 1
        currentTime = (i - 1) * t_step + win_len/2
        if spectral_distance_norm[i] < sim_thresh
            # Check minimum gap from last freeze
            if currentTime - lastFreezeTime > min_gap + freeze_dur
                numFreezes += 1
                freeze_at[numFreezes] = i
                lastFreezeTime = currentTime
            endif
        endif
    endfor
    
    appendInfoLine: "  Found ", numFreezes, " freeze candidates"
    
    # Create Manipulation
    selectObject: sound
    To Manipulation: 0.01, 75, 600
    manipulation = selected("Manipulation")
    
    selectObject: manipulation
    Extract duration tier
    durationTier = selected("DurationTier")
    
    # Apply freeze points with safe boundaries
    selectObject: durationTier
    for f to numFreezes
        frameIndex = freeze_at[f]
        freezeTime = (frameIndex - 1) * t_step + win_len/2
        
        # Ensure we're not too close to start or end
        if freezeTime > 0.02 and freezeTime < duration - freeze_dur - 0.02
            # Ramp into freeze
            Add point: freezeTime - 0.01, 1.0
            # Hold (high duration factor = slow = freeze effect)
            Add point: freezeTime, 5.0
            Add point: freezeTime + freeze_dur, 5.0
            # Ramp out of freeze
            Add point: freezeTime + freeze_dur + 0.01, 1.0
        endif
    endfor
    
    # Replace duration tier
    selectObject: manipulation
    plusObject: durationTier
    Replace duration tier
    
    # Resynthesize
    selectObject: manipulation
    Get resynthesis (overlap-add)
    result = selected("Sound")
    Rename: soundName$ + algo_name$
    removeObject: manipulation, durationTier
    
    appendInfoLine: "  Applied ", numFreezes, " freeze points"

# ALGORITHM 5: TRAJECTORY SCRAMBLE
# Locally randomizes MFCC trajectories for modulation
elsif algo = 5
    appendInfoLine: "Trajectory Scramble Mode"
    appendInfoLine: "  Window size: ", scramble_win, " frames"
    appendInfoLine: "  Pitch range: ", c1_p_min, " - ", c1_p_max
    appendInfoLine: "  Duration range: ", c3_d_min, " - ", c3_d_max
    
    # Scramble within local windows
    for i to numFrames
        windowStart = max(1, round(i - scramble_win / 2))
        windowEnd = min(numFrames, round(i + scramble_win / 2))
        
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
    
    # Create Manipulation
    selectObject: sound
    To Manipulation: 0.01, 75, 600
    manipulation = selected("Manipulation")
    
    # Extract original pitch tier
    selectObject: manipulation
    Extract pitch tier
    originalPitchTier = selected("PitchTier")
    
    # Create new pitch tier
    Create PitchTier: "newPitch", 0, duration
    newPitchTier = selected("PitchTier")
    
    selectObject: manipulation
    Extract duration tier
    durationTier = selected("DurationTier")
    
    # Apply scrambled pitch scaling
    selectObject: newPitchTier
    for i to numFrames
        time = (i - 1) * t_step + win_len/2
        if time > 0 and time < duration
            selectObject: originalPitchTier
            originalPitch = Get value at time: time
            
            if originalPitch <> undefined and originalPitch > 0
                pitchFactor = c1_p_min + (c_scaled[i, 1] * (c1_p_max - c1_p_min))
                newPitch = originalPitch * pitchFactor
                newPitch = max(50, min(800, newPitch))
                selectObject: newPitchTier
                Add point: time, newPitch
            endif
        endif
    endfor
    
    # Apply scrambled duration (using C2 for variety)
    selectObject: durationTier
    for i to numFrames
        time = (i - 1) * t_step + win_len/2
        if time > 0 and time < duration
            durationFactor = c3_d_min + (c_scaled[i, 2] * (c3_d_max - c3_d_min))
            Add point: time, durationFactor
        endif
    endfor
    
    # Replace tiers
    selectObject: manipulation
    plusObject: newPitchTier
    Replace pitch tier
    
    selectObject: manipulation
    plusObject: durationTier
    Replace duration tier
    
    # Resynthesize
    selectObject: manipulation
    Get resynthesis (overlap-add)
    result = selected("Sound")
    Rename: soundName$ + algo_name$
    removeObject: manipulation, originalPitchTier, newPitchTier, durationTier

endif

# ============================================================
# Cleanup & Finalize
# ============================================================
removeObject: mfcc, matrix

appendInfoLine: ""
appendInfoLine: "Complete!"
appendInfoLine: "Output: ", soundName$, algo_name$

selectObject: result

if play_result
    Play
endif