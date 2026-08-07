# ============================================================
# Praat AudioTools - MFCC_TRANSFORMER.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.3 (2026) - validated control mappings, timing, cleanup, house-style visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   MFCC-derived control-mapping toolkit. MFCC coefficients are used as
#   control signals for pitch, amplitude, and duration; this script does
#   not reconstruct or directly edit the MFCC spectral envelope.
# ============================================================

form MFCC Transformer v2.3
    comment ======== PRESETS ========
    optionmenu Preset 1
        option Custom
        option Direct: Subtle
        option Direct: Wide Range
        option Direct: Pitch Focus
        option Reverse: Classic
        option Reverse: Dramatic
        option Dispersion Stretch: Moderate
        option Dispersion Stretch: Extreme
        option Stable Stretch: Sparse
        option Stable Stretch: Dense
        option Control Scramble: Subtle
        option Control Scramble: Wild

    comment ======== MANUAL SETTINGS (Custom only) ========
    optionmenu Algorithm 1
        option Direct Control
        option Reverse Control
        option MFCC Dispersion Stretch
        option Stable Moment Stretch
        option MFCC Control Scramble
    
    comment Control Ranges (Direct Control only; C2 amplitude maps 0.5 to 1.0):
    real Pitch_range 0.6
    real Duration_range 0.3
    
    comment Other Algorithm Parameters:
    positive Dispersion_threshold 0.5
    positive Max_stretch_factor 2.0
    positive Stable_hold_duration_(s) 0.2
    positive Min_stable_gap_(s) 0.1
    positive Control_scramble_window_(frames) 10
    
    comment === Performance ===
    optionmenu Speed_mode: 1
        option Full Quality (original sample rate)
        option Balanced (downsample to 22 kHz)
        option Fast (downsample to 11 kHz)
    
    comment Output:
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Check Selection
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")
duration = Get total duration
samplingFrequency = Get sampling frequency
nChannels = Get number of channels
originalStart = Get start time

if duration < 0.1
    exitScript: "Sound is too short (minimum 0.1s required)."
endif

# Set target sample rate
if speed_mode = 1
    targetSR = 0
    speedStr$ = "Full Quality"
elsif speed_mode = 2
    targetSR = 22050
    speedStr$ = "Balanced"
else
    targetSR = 11025
    speedStr$ = "Fast"
endif

startTime = stopwatch

# Work on a private copy at time zero. This makes MFCC frame times and
# Manipulation/PitchTier/DurationTier times share the same domain, while
# preserving the original Sound and restoring its start time at the end.
selectObject: sound
workingSound = Copy: "mfcc_work"
if originalStart <> 0
    Shift times to: "start time", 0
endif

# Praat Manipulation/PSOLA resynthesis in this workflow is mono. Make the
# channel policy explicit instead of silently collapsing a multichannel input.
if nChannels > 1
    Convert to mono
    monoWork = selected("Sound")
    removeObject: workingSound
    workingSound = monoWork
endif

# Optional downsampling
if targetSR > 0 and samplingFrequency > targetSR
    Resample: targetSR, 50
    downsampled = selected("Sound")
    removeObject: workingSound
    workingSound = downsampled
    workingSR = targetSR
else
    workingSR = samplingFrequency
endif

# PRESET LOGIC
algo = algorithm

# Fixed MFCC parameters
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
comp_thresh = dispersion_threshold
max_stretch = max_stretch_factor
min_stretch = 0.5
freeze_dur = stable_hold_duration
min_gap = min_stable_gap
sim_thresh = 0.3
scramble_win = control_scramble_window

# Clamp parameters to domains that keep pitch and duration factors positive.
if pitch_range < 0
    pitch_range = 0
elsif pitch_range > 0.95
    pitch_range = 0.95
endif
if duration_range < 0
    duration_range = 0
elsif duration_range > 0.95
    duration_range = 0.95
endif
if comp_thresh < 0.001
    comp_thresh = 0.001
elsif comp_thresh > 0.999
    comp_thresh = 0.999
endif
if max_stretch < 1
    max_stretch = 1
endif
if scramble_win < 1
    scramble_win = 1
endif

# Recompute custom ranges after clamping.
c1_p_min = 1.0 - pitch_range
c1_p_max = 1.0 + pitch_range
c3_d_min = 1.0 - duration_range
c3_d_max = 1.0 + duration_range

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
elsif preset$ = "Dispersion Stretch: Moderate"
    algo = 3
    comp_thresh = 0.5
    max_stretch = 2.0
    min_stretch = 0.7
elsif preset$ = "Dispersion Stretch: Extreme"
    algo = 3
    comp_thresh = 0.4
    max_stretch = 4.0
    min_stretch = 0.5
elsif preset$ = "Stable Stretch: Sparse"
    algo = 4
    freeze_dur = 0.15
    sim_thresh = 0.2
    min_gap = 0.15
elsif preset$ = "Stable Stretch: Dense"
    algo = 4
    freeze_dur = 0.2
    sim_thresh = 0.4
    min_gap = 0.1
elsif preset$ = "Control Scramble: Subtle"
    algo = 5
    scramble_win = 5
    c1_p_min = 0.8
    c1_p_max = 1.2
    c3_d_min = 0.9
    c3_d_max = 1.1
elsif preset$ = "Control Scramble: Wild"
    algo = 5
    scramble_win = 30
    c1_p_min = 0.6
    c1_p_max = 1.4
    c3_d_min = 0.7
    c3_d_max = 1.3
endif

# Algorithm names
algo_name$ = ""
if algo = 1
    algo_name$ = "_DirectControl"
elsif algo = 2
    algo_name$ = "_Reversed"
elsif algo = 3
    algo_name$ = "_MFCCDispersionStretch"
elsif algo = 4
    algo_name$ = "_StableMomentStretch"
elsif algo = 5
    algo_name$ = "_MFCCControlScramble"
endif

writeInfoLine: "=== MFCC Transformer v2.3 ==="
appendInfoLine: "Processing: ", soundName$
appendInfoLine: "Speed: ", speedStr$
appendInfoLine: "Algorithm: ", algo_name$
if nChannels > 1
    appendInfoLine: "Channels: ", nChannels, " -> mono (explicit downmix for MFCC/PSOLA)"
else
    appendInfoLine: "Channels: mono"
endif
appendInfoLine: ""

# MFCC EXTRACTION
selectObject: workingSound
To MFCC: num_coeffs, win_len, t_step, first_freq, filter_dist, max_freq
mfcc = selected("MFCC")

selectObject: mfcc
To Matrix
matrix = selected("Matrix")

numFrames = Get number of columns
numCoeffs = Get number of rows

if numFrames < 3
    removeObject: mfcc, matrix
    if workingSound <> sound
        removeObject: workingSound
    endif
    exitScript: "Sound is too short - not enough MFCC frames."
endif

# Extract MFCC data
for i to numFrames
    for j to min(numCoeffs, 12)
        mfcc_data[i, j] = Get value in cell: j, i
    endfor
endfor

appendInfoLine: "MFCC frames: ", numFrames
appendInfoLine: "MFCC coefficients: ", numCoeffs
appendInfoLine: ""

# Initialize visualization flags
hasPitchTier = 0
hasDurationTier = 0
hasComplexity = 0
hasFreezeData = 0
hasAmplitudeTier = 0

# ============================================================
# ALGORITHM 1: DIRECT CONTROL
# ============================================================
if algo = 1
    appendInfoLine: "Direct Control Mode"
    appendInfoLine: "  C1 → Pitch: ", c1_p_min, " to ", c1_p_max
    appendInfoLine: "  C2 → Amplitude: ", c2_a_min, " to ", c2_a_max
    appendInfoLine: "  C3 → Duration: ", c3_d_min, " to ", c3_d_max
    
    # Normalize coefficients C1-C3
    for j to 3
        minVal = mfcc_data[1, j]
        maxVal = mfcc_data[1, j]
        for i from 2 to numFrames
            if mfcc_data[i, j] < minVal
                minVal = mfcc_data[i, j]
            endif
            if mfcc_data[i, j] > maxVal
                maxVal = mfcc_data[i, j]
            endif
        endfor
        
        for i to numFrames
            c_scaled[i, j] = (mfcc_data[i, j] - minVal) / (maxVal - minVal + 0.0001)
        endfor
    endfor
    
    # Build the advertised C2 -> amplitude control. Praat's regular
    # Sound & AmplitudeTier: Multiply command peak-normalizes the result,
    # so apply the tier explicitly in a Formula to preserve the requested
    # linear 0.5..1.0 gain mapping.
    Create AmplitudeTier: "mfcc_amp_control", 0, duration
    amplitudeTier = selected("AmplitudeTier")
    amplitudeTierName$ = "mfcc_amp_control_" + fixed$(amplitudeTier, 0)
    Rename: amplitudeTierName$
    firstAmp = c2_a_min + c_scaled[1, 2] * (c2_a_max - c2_a_min)
    lastAmp = c2_a_min + c_scaled[numFrames, 2] * (c2_a_max - c2_a_min)
    Add point: 0, firstAmp
    for i to numFrames
        time = (i - 1) * t_step + win_len/2
        if time > 0 and time < duration
            ampFactor = c2_a_min + c_scaled[i, 2] * (c2_a_max - c2_a_min)
            Add point: time, ampFactor
        endif
    endfor
    Add point: duration, lastAmp

    selectObject: workingSound
    directSource = Copy: "mfcc_direct_source"
    ampFormula$ = "self * AmplitudeTier_" + amplitudeTierName$ + "(x)"
    Formula: ampFormula$

    # Create Manipulation from the amplitude-modulated source.
    selectObject: directSource
    To Manipulation: 0.01, 75, 600
    manipulation = selected("Manipulation")
    
    selectObject: manipulation
    Extract pitch tier
    originalPitchTier = selected("PitchTier")
    
    Create PitchTier: "newPitch", 0, duration
    newPitchTier = selected("PitchTier")
    
    selectObject: manipulation
    Extract duration tier
    durationTier = selected("DurationTier")
    
    # Apply MFCC-driven modulation
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
    
    # For visualization
    visualPitchTier = newPitchTier
    visualDurationTier = durationTier
    hasPitchTier = 1
    hasDurationTier = 1
    hasAmplitudeTier = 1
    visualAmplitudeTier = amplitudeTier
    
    removeObject: manipulation, originalPitchTier, directSource

# ============================================================
# ALGORITHM 2: REVERSE CONTROL
# ============================================================
elsif algo = 2
    appendInfoLine: "Reverse Control Mode"
    appendInfoLine: "  Pitch range: ", c1_p_min, " - ", c1_p_max
    appendInfoLine: "  Duration range: ", c3_d_min, " - ", c3_d_max
    
    # Normalize C1 and C3
    for j to 3
        if j = 1 or j = 3
            minVal = mfcc_data[1, j]
            maxVal = mfcc_data[1, j]
            for i from 2 to numFrames
                if mfcc_data[i, j] < minVal
                    minVal = mfcc_data[i, j]
                endif
                if mfcc_data[i, j] > maxVal
                    maxVal = mfcc_data[i, j]
                endif
            endfor
            
            for i to numFrames
                c_scaled[i, j] = (mfcc_data[i, j] - minVal) / (maxVal - minVal + 0.0001)
            endfor
        endif
    endfor
    
    # Create Manipulation
    selectObject: workingSound
    To Manipulation: 0.01, 75, 600
    manipulation = selected("Manipulation")
    
    selectObject: manipulation
    Extract pitch tier
    originalPitchTier = selected("PitchTier")
    
    Create PitchTier: "newPitch", 0, duration
    newPitchTier = selected("PitchTier")
    
    selectObject: manipulation
    Extract duration tier
    durationTier = selected("DurationTier")
    
    # Apply REVERSED MFCC modulation
    selectObject: newPitchTier
    for i to numFrames
        time = (i - 1) * t_step + win_len/2
        reverseIndex = numFrames - i + 1
        
        if time > 0 and time < duration
            selectObject: originalPitchTier
            originalPitch = Get value at time: time
            
            if originalPitch <> undefined and originalPitch > 0
                pitchFactor = c1_p_min + (c_scaled[reverseIndex, 1] * (c1_p_max - c1_p_min))
                newPitch = originalPitch * pitchFactor
                newPitch = max(50, min(800, newPitch))
                selectObject: newPitchTier
                Add point: time, newPitch
            endif
        endif
    endfor
    
    selectObject: durationTier
    for i to numFrames
        time = (i - 1) * t_step + win_len/2
        reverseIndex = numFrames - i + 1
        
        if time > 0 and time < duration
            durationFactor = c3_d_min + (c_scaled[reverseIndex, 3] * (c3_d_max - c3_d_min))
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
    
    visualPitchTier = newPitchTier
    visualDurationTier = durationTier
    hasPitchTier = 1
    hasDurationTier = 1
    
    removeObject: manipulation, originalPitchTier

# ============================================================
# ALGORITHM 3: COMPLEXITY STRETCH
# ============================================================
elsif algo = 3
    appendInfoLine: "MFCC Dispersion Time-Stretch Mode"
    appendInfoLine: "  Threshold: ", comp_thresh
    appendInfoLine: "  Stretch range: ", min_stretch, " - ", max_stretch
    
    # Descriptor = within-frame dispersion across C1..C6. This is an
    # artistic MFCC control descriptor, not a standardized complexity metric.
    for i to numFrames
        variance = 0
        mean = 0
        
        for j to min(6, numCoeffs)
            mean += mfcc_data[i, j]
        endfor
        mean = mean / min(6, numCoeffs)
        
        for j to min(6, numCoeffs)
            diff = mfcc_data[i, j] - mean
            variance += diff * diff
        endfor
        complexity[i] = sqrt(variance)
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
    selectObject: workingSound
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
                stretchFactor = 1 + ((complexity_norm[i] - comp_thresh) / (1 - comp_thresh + 0.0001)) * (max_stretch - 1)
            else
                stretchFactor = min_stretch + (complexity_norm[i] / (comp_thresh + 0.0001)) * (1 - min_stretch)
            endif
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
    
    visualDurationTier = durationTier
    hasDurationTier = 1
    hasComplexity = 1
    
    removeObject: manipulation

# ============================================================
# ALGORITHM 4: STABLE-MOMENT TIME STRETCH
# ============================================================
elsif algo = 4
    appendInfoLine: "Stable-Moment Time-Stretch Mode"
    appendInfoLine: "  Similarity threshold: ", sim_thresh
    appendInfoLine: "  Hold/stretch region: ", freeze_dur, "s"
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
    
    # Find freeze points
    numFreezes = 0
    lastFreezeTime = -1000
    
    for i from 2 to numFrames - 1
        currentTime = (i - 1) * t_step + win_len/2
        if spectral_distance_norm[i] < sim_thresh
            if currentTime - lastFreezeTime > min_gap + freeze_dur
                numFreezes += 1
                freeze_at[numFreezes] = i
                lastFreezeTime = currentTime
            endif
        endif
    endfor
    
    appendInfoLine: "  Found ", numFreezes, " stable-region candidates"
    
    # Create Manipulation
    selectObject: workingSound
    To Manipulation: 0.01, 75, 600
    manipulation = selected("Manipulation")
    
    selectObject: manipulation
    Extract duration tier
    durationTier = selected("DurationTier")
    
    # Apply local 5x duration regions around stable MFCC moments.
    # This is a freeze-like time hold, not spectral-frame freezing.
    appliedFreezes = 0
    selectObject: durationTier
    for f to numFreezes
        frameIndex = freeze_at[f]
        freezeTime = (frameIndex - 1) * t_step + win_len/2
        
        if freezeTime > 0.02 and freezeTime < duration - freeze_dur - 0.02
            Add point: freezeTime - 0.01, 1.0
            Add point: freezeTime, 5.0
            Add point: freezeTime + freeze_dur, 5.0
            Add point: freezeTime + freeze_dur + 0.01, 1.0
            appliedFreezes += 1
            freeze_applied_at[appliedFreezes] = frameIndex
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
    
    visualDurationTier = durationTier
    hasDurationTier = 1
    hasFreezeData = 1
    
    removeObject: manipulation
    
    appendInfoLine: "  Applied ", appliedFreezes, " stable stretch regions"

# ============================================================
# ALGORITHM 5: TRAJECTORY SCRAMBLE
# ============================================================
elsif algo = 5
    appendInfoLine: "MFCC Control Scramble Mode"
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
    selectObject: workingSound
    To Manipulation: 0.01, 75, 600
    manipulation = selected("Manipulation")
    
    selectObject: manipulation
    Extract pitch tier
    originalPitchTier = selected("PitchTier")
    
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
    
    # Apply scrambled duration
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
    
    visualPitchTier = newPitchTier
    visualDurationTier = durationTier
    hasPitchTier = 1
    hasDurationTier = 1
    
    removeObject: manipulation, originalPitchTier

endif

# Upsample if needed
if targetSR > 0 and samplingFrequency > targetSR
    selectObject: result
    Resample: samplingFrequency, 50
    upsampled = selected("Sound")
    removeObject: result
    result = upsampled
endif

# Restore the original Sound time origin after all internal processing at t=0.
selectObject: result
if originalStart <> 0
    Shift times by: originalStart
endif
Rename: soundName$ + algo_name$

# The private working copy is no longer needed.
removeObject: workingSound

processingTime = stopwatch - startTime

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0, 0.5
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##MFCC TRANSFORMER v2.3##"
    
    # Original vs Processed Waveforms
    Select outer viewport: 0, 4, 0.6, 1.6
    Select inner viewport: 0.5, 3.7, 0.7, 1.5
    selectObject: sound
    Colour: "{0.50, 0.50, 0.50}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Original"
    Text left: "yes", "Amp"
    
    Select outer viewport: 4, 8, 0.6, 1.6
    Select inner viewport: 4.5, 7.7, 0.7, 1.5
    selectObject: result
    Colour: "{0.25, 0.45, 0.78}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Transformed"
    Text left: "yes", "Amp"
    
    # MFCC Coefficients C1-C3
    Select outer viewport: 0, 8, 1.8, 3.2
    Select inner viewport: 0.6, 7.6, 1.9, 3.1
    
    maxTime = duration
    maxC = -1000
    minC = 1000
    
    for i to numFrames
        for j to 3
            if mfcc_data[i, j] > maxC
                maxC = mfcc_data[i, j]
            endif
            if mfcc_data[i, j] < minC
                minC = mfcc_data[i, j]
            endif
        endfor
    endfor
    
    Axes: 0, maxTime, minC * 1.1, maxC * 1.1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, maxTime, minC * 1.1, maxC * 1.1
    
    # Draw C1, C2, C3
    colors$ [1] = "{0.25, 0.45, 0.78}"
    colors$ [2] = "{0.45, 0.40, 0.68}"
    colors$ [3] = "{0.45, 0.55, 0.72}"
    labels$ [1] = "C1"
    labels$ [2] = "C2"
    labels$ [3] = "C3"
    
    for coef to 3
        Colour: colors$ [coef]
        Line width: 1.5
        
        for i from 1 to numFrames - 1
            t1 = (i - 1) * t_step + win_len/2
            t2 = i * t_step + win_len/2
            v1 = mfcc_data[i, coef]
            v2 = mfcc_data[i + 1, coef]
            Draw line: t1, v1, t2, v2
        endfor
    endfor
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "MFCC C1-C3 source features"
    Text left: "yes", "Value"
    Text bottom: "yes", "Time (s)"
    
    # Legend
    Font size: 6
    for coef to 3
        Colour: colors$ [coef]
        xPos = 0.7 + (coef - 1) * 0.15
        Text: xPos * maxTime, "left", maxC * 0.9, "half", labels$ [coef]
    endfor
    
    # Algorithm-specific visualization
    if hasPitchTier and hasDurationTier
        # Show pitch modification
        Select outer viewport: 0, 4, 3.4, 4.6
        Select inner viewport: 0.6, 3.8, 3.5, 4.5
        
        selectObject: visualPitchTier
        numPitchPoints = Get number of points
        
        if numPitchPoints > 0
            Axes: 0, duration, 50, 400
            Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, 50, 400
            
            Colour: "{0.45, 0.40, 0.68}"
            Line width: 2
            
            for p from 1 to numPitchPoints - 1
                t1 = Get time from index: p
                v1 = Get value at index: p
                t2 = Get time from index: p + 1
                v2 = Get value at index: p + 1
                Draw line: t1, v1, t2, v2
            endfor
            
            Line width: 1
            Colour: "Black"
            Draw inner box
            Font size: 7
            Text top: "no", "Pitch Tier"
            Text left: "yes", "Hz"
            Text bottom: "yes", "Time (s)"
        else
            Axes: 0, duration, 0, 1
            Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, 0, 1
            Colour: "Black"
            Draw inner box
            Font size: 7
            Text top: "no", "Pitch Tier (empty)"
        endif
        
        # Show duration modification
        Select outer viewport: 4, 8, 3.4, 4.6
        Select inner viewport: 4.4, 7.6, 3.5, 4.5
        
        selectObject: visualDurationTier
        numDurPoints = Get number of points
        
        if numDurPoints > 0
            minDur = Get value at index: 1
            maxDur = minDur
            
            for p from 2 to numDurPoints
                val = Get value at index: p
                if val < minDur
                    minDur = val
                endif
                if val > maxDur
                    maxDur = val
                endif
            endfor
            
            Axes: 0, duration, minDur * 0.9, maxDur * 1.1
            Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, minDur * 0.9, maxDur * 1.1
            
            Colour: "{0.25, 0.45, 0.78}"
            Line width: 2
            
            for p from 1 to numDurPoints - 1
                t1 = Get time from index: p
                v1 = Get value at index: p
                t2 = Get time from index: p + 1
                v2 = Get value at index: p + 1
                Draw line: t1, v1, t2, v2
            endfor
            
            Line width: 1
            Colour: "Black"
            Draw inner box
            Font size: 7
            Text top: "no", "Duration Tier"
            Text left: "yes", "Factor"
            Text bottom: "yes", "Time (s)"
        else
            Axes: 0, duration, 0, 1
            Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, 0, 1
            Colour: "Black"
            Draw inner box
            Font size: 7
            Text top: "no", "Duration Tier (empty)"
        endif
        
    elsif hasComplexity
        # Show complexity
        Select outer viewport: 0, 8, 3.4, 4.6
        Select inner viewport: 0.6, 7.6, 3.5, 4.5
        
        Axes: 0, duration, 0, 1.1
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, 0, 1.1
        
        Colour: "{0.8, 0.8, 0.8}"
        Dotted line
        Draw line: 0, comp_thresh, duration, comp_thresh
        Solid line
        
        Colour: "{0.45, 0.40, 0.68}"
        Line width: 2
        
        for i from 1 to numFrames - 1
            t1 = (i - 1) * t_step + win_len/2
            t2 = i * t_step + win_len/2
            Draw line: t1, complexity_norm[i], t2, complexity_norm[i + 1]
        endfor
        
        Line width: 1
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text top: "no", "MFCC dispersion C1-C6 (normalized)"
        Text left: "yes", "Value"
        Text bottom: "yes", "Time (s)"
        
    elsif hasFreezeData
        # Show freeze points
        Select outer viewport: 0, 8, 3.4, 4.6
        Select inner viewport: 0.6, 7.6, 3.5, 4.5
        
        Axes: 0, duration, 0, 1.1
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, 0, 1.1
        
        Colour: "{0.8, 0.8, 0.8}"
        Dotted line
        Draw line: 0, sim_thresh, duration, sim_thresh
        Solid line
        
        Colour: "{0.5, 0.7, 0.5}"
        Line width: 2
        
        for i from 2 to numFrames - 1
            t1 = (i - 1) * t_step + win_len/2
            t2 = i * t_step + win_len/2
            Draw line: t1, spectral_distance_norm[i], t2, spectral_distance_norm[i + 1]
        endfor
        
        Colour: "{0.78, 0.76, 0.88}"
        for f to appliedFreezes
            freezeTime = (freeze_applied_at[f] - 1) * t_step + win_len/2
            Paint rectangle: "{0.78, 0.76, 0.88}", freezeTime, freezeTime + freeze_dur, 0, 1.1
        endfor
        
        Line width: 1
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text top: "no", "MFCC frame distance (shaded = stable stretch regions)"
        Text left: "yes", "Value"
        Text bottom: "yes", "Time (s)"
    endif
    
    # Info panel
    Select outer viewport: 0, 8, 4.8, 5.3
    Select inner viewport: 0.5, 7.7, 4.85, 5.25
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1
    
    Font size: 8
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.5, "half", speedStr$ + " | Time: " + fixed$(processingTime, 2) + "s | Frames: " + string$(numFrames) + " | " + preset$
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
    
endif

# Cleanup analysis and helper tiers regardless of whether visualization ran.
if hasPitchTier
    removeObject: visualPitchTier
endif
if hasDurationTier
    removeObject: visualDurationTier
endif
if hasAmplitudeTier
    removeObject: visualAmplitudeTier
endif
removeObject: mfcc, matrix

appendInfoLine: ""
appendInfoLine: "=== Complete ==="
appendInfoLine: "Processing time: ", fixed$(processingTime, 2), " seconds"
appendInfoLine: "Output: ", soundName$, algo_name$

selectObject: result

if play_result
    Play
endif

selectObject: result

