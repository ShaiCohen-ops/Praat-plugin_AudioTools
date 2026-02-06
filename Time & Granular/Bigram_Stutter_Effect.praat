# ============================================================
# Praat AudioTools - Bigram_Stutter_Effect.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Bigram Stutter Effect - applies probabilistic stuttering
#   using n-gram (bigram) logic. Segments audio into windows
#   and makes Markov chain decisions: repeat current segment
#   (stutter) or advance to next segment. Includes true stereo
#   processing modes with independent channel patterns.
#
# Bigram Model:
#   - State = current audio segment
#   - P(repeat | current) = stutter_probability
#   - P(advance | current) = 1 - stutter_probability
#   Creates natural-sounding glitch effects through
#   probabilistic decision chains.
#
# Changelog v1.0:
#   - Initial release
#   - Bigram stutter logic
#   - True stereo processing (6 modes)
#   - Visualization with decision chain
#   - Presets for common effects
# ============================================================

form Bigram Stutter Effect
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom
        option Subtle Stutter (light glitchy effect)
        option Medium Stutter (noticeable repeats)
        option Heavy Stutter (intense stutter)
        option Glitch Hop (rhythmic, musical)
        option Broken Record (very short, frequent stutters)
        option Tape Malfunction (longer segments, rare stutters)
    
    comment === Window Settings ===
    positive Window_size_ms 50
    real Stutter_probability_0_to_1 0.3
    positive Overlap_ms 5
    
    comment === Stereo Processing Mode ===
    optionmenu Stereo_mode 1
        option Mono to Stereo (same processing both channels)
        option Independent (completely different patterns L/R)
        option Complementary (when L stutters, R advances)
        option Offset (R delayed by 1 segment from L)
        option Asymmetric (L more stutter, R less stutter)
        option Ping-Pong (stutters alternate L/R)
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Subtle Stutter
    window_size_ms = 80
    stutter_probability_0_to_1 = 0.2
    overlap_ms = 10
elsif preset = 3
    # Medium Stutter
    window_size_ms = 60
    stutter_probability_0_to_1 = 0.35
    overlap_ms = 8
elsif preset = 4
    # Heavy Stutter
    window_size_ms = 40
    stutter_probability_0_to_1 = 0.55
    overlap_ms = 5
elsif preset = 5
    # Glitch Hop
    window_size_ms = 100
    stutter_probability_0_to_1 = 0.4
    overlap_ms = 15
elsif preset = 6
    # Broken Record
    window_size_ms = 25
    stutter_probability_0_to_1 = 0.6
    overlap_ms = 3
elsif preset = 7
    # Tape Malfunction
    window_size_ms = 150
    stutter_probability_0_to_1 = 0.15
    overlap_ms = 20
endif

# === Validate Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

if stutter_probability_0_to_1 < 0 or stutter_probability_0_to_1 > 1
    exitScript: "Stutter probability must be between 0 and 1"
endif

if overlap_ms > window_size_ms
    exitScript: "Overlap cannot be greater than window size"
endif

# === Get Input ===
soundID = selected("Sound")
sound$ = selected$("Sound")

selectObject: soundID
duration = Get total duration
originalChannels = Get number of channels
samplingFrequency = Get sampling frequency

# === Convert to seconds ===
windowSize = window_size_ms / 1000
overlapSize = overlap_ms / 1000
stutter_probability = stutter_probability_0_to_1

# === Calculate segments ===
numberOfSegments = floor(duration / windowSize)

if numberOfSegments < 2
    exitScript: "Sound is too short for the given window size. Please use a smaller window size."
endif

# === Initialize Report ===
writeInfoLine: "=== Bigram Stutter Effect ==="
appendInfoLine: "Source: ", sound$, " (", fixed$(duration, 2), " s)"
appendInfoLine: ""
if preset > 1
    appendInfoLine: "Preset: ", preset$
endif
appendInfoLine: "Window size: ", window_size_ms, " ms"
appendInfoLine: "Stutter probability: ", stutter_probability
appendInfoLine: "Overlap: ", overlap_ms, " ms"
appendInfoLine: "Stereo mode: ", stereo_mode$
appendInfoLine: "Original channels: ", originalChannels
appendInfoLine: "Segments: ", numberOfSegments
appendInfoLine: ""

# ==================================================================
# EXTRACT LEFT AND RIGHT CHANNELS (or duplicate if mono)
# ==================================================================

appendInfoLine: "Preparing channels for stereo processing..."

selectObject: soundID

if originalChannels = 1
    appendInfoLine: "Source is mono - creating stereo from mono source."
    leftChannel = Copy: "left_temp"
    selectObject: soundID
    rightChannel = Copy: "right_temp"
else
    appendInfoLine: "Source is stereo - extracting separate channels."
    leftChannel = Extract one channel: 1
    Rename: "left_temp"
    selectObject: soundID
    rightChannel = Extract one channel: 2
    Rename: "right_temp"
endif

# ==================================================================
# BIGRAM LOGIC FOR LEFT CHANNEL
# ==================================================================
appendInfoLine: ""
appendInfoLine: "Building LEFT channel stutter pattern (Bigram logic)..."

currentSegmentIndex_L = 1
outputPosition_L = 1
maxOutputSegments = numberOfSegments * 10

# Build the LEFT channel segment chain using bigram decisions
while currentSegmentIndex_L <= numberOfSegments and outputPosition_L <= maxOutputSegments
    segmentChain_L[outputPosition_L] = currentSegmentIndex_L
    randomValue = randomUniform(0, 1)
    
    if randomValue < stutter_probability
        # STUTTER: Self-loop transition
        decisionType_L[outputPosition_L] = 0
    else
        # ADVANCE: Forward transition
        currentSegmentIndex_L += 1
        decisionType_L[outputPosition_L] = 1
    endif
    outputPosition_L += 1
endwhile

totalOutputSegments_L = outputPosition_L - 1

# ==================================================================
# BIGRAM LOGIC FOR RIGHT CHANNEL (MODE-DEPENDENT)
# ==================================================================
appendInfoLine: "Building RIGHT channel stutter pattern..."

# Set probability for right channel based on stereo mode
if stereo_mode = 5
    # Asymmetric mode: Right channel has less stutter
    stutter_probability_R = stutter_probability * 0.5
    appendInfoLine: "  Asymmetric mode: R probability = ", fixed$(stutter_probability_R, 2)
else
    stutter_probability_R = stutter_probability
endif

currentSegmentIndex_R = 1
outputPosition_R = 1

# Build RIGHT channel chain based on stereo mode
if stereo_mode = 1
    # Mono to Stereo - same pattern for both channels
    appendInfoLine: "  Mode: Mono to Stereo (identical patterns)"
    for i to totalOutputSegments_L
        segmentChain_R[i] = segmentChain_L[i]
        decisionType_R[i] = decisionType_L[i]
    endfor
    totalOutputSegments_R = totalOutputSegments_L
    
elsif stereo_mode = 2
    # Independent - completely different random pattern
    appendInfoLine: "  Mode: Independent (different random patterns)"
    while currentSegmentIndex_R <= numberOfSegments and outputPosition_R <= maxOutputSegments
        segmentChain_R[outputPosition_R] = currentSegmentIndex_R
        randomValue = randomUniform(0, 1)
        
        if randomValue < stutter_probability_R
            decisionType_R[outputPosition_R] = 0
        else
            currentSegmentIndex_R += 1
            decisionType_R[outputPosition_R] = 1
        endif
        outputPosition_R += 1
    endwhile
    totalOutputSegments_R = outputPosition_R - 1
    
elsif stereo_mode = 3
    # Complementary - when L stutters, R advances and vice versa
    appendInfoLine: "  Mode: Complementary (opposite behaviors)"
    currentSegmentIndex_R = 1
    for i to totalOutputSegments_L
        if currentSegmentIndex_R <= numberOfSegments
            segmentChain_R[i] = currentSegmentIndex_R
            
            if i < totalOutputSegments_L
                if segmentChain_L[i] = segmentChain_L[i + 1]
                    # L stuttered, R advances
                    if currentSegmentIndex_R < numberOfSegments
                        currentSegmentIndex_R += 1
                        decisionType_R[i] = 1
                    else
                        decisionType_R[i] = 0
                    endif
                else
                    # L advanced, R stutters
                    decisionType_R[i] = 0
                endif
            endif
        else
            segmentChain_R[i] = numberOfSegments
            decisionType_R[i] = 0
        endif
    endfor
    totalOutputSegments_R = totalOutputSegments_L
    
elsif stereo_mode = 4
    # Offset - same pattern but R is delayed by 1 segment
    appendInfoLine: "  Mode: Offset (R delayed by 1 segment)"
    segmentChain_R[1] = 1
    decisionType_R[1] = 0
    for i from 2 to totalOutputSegments_L
        segmentChain_R[i] = segmentChain_L[i - 1]
        decisionType_R[i] = decisionType_L[i - 1]
    endfor
    totalOutputSegments_R = totalOutputSegments_L
    
elsif stereo_mode = 5
    # Asymmetric - R has lower stutter probability
    appendInfoLine: "  Mode: Asymmetric (R stutters less)"
    while currentSegmentIndex_R <= numberOfSegments and outputPosition_R <= maxOutputSegments
        segmentChain_R[outputPosition_R] = currentSegmentIndex_R
        randomValue = randomUniform(0, 1)
        
        if randomValue < stutter_probability_R
            decisionType_R[outputPosition_R] = 0
        else
            currentSegmentIndex_R += 1
            decisionType_R[outputPosition_R] = 1
        endif
        outputPosition_R += 1
    endwhile
    totalOutputSegments_R = outputPosition_R - 1
    
elsif stereo_mode = 6
    # Ping-Pong - stutters alternate between channels
    appendInfoLine: "  Mode: Ping-Pong (alternating stutters)"
    currentSegmentIndex_R = 1
    lastChannelThatStuttered = 0
    
    for i to totalOutputSegments_L
        if currentSegmentIndex_R <= numberOfSegments
            segmentChain_R[i] = currentSegmentIndex_R
            
            l_stuttered = 0
            if i < totalOutputSegments_L
                if segmentChain_L[i] = segmentChain_L[i + 1]
                    l_stuttered = 1
                endif
            endif
            
            if l_stuttered = 1
                if currentSegmentIndex_R < numberOfSegments
                    currentSegmentIndex_R += 1
                    decisionType_R[i] = 1
                    lastChannelThatStuttered = 1
                else
                    decisionType_R[i] = 0
                endif
            else
                if lastChannelThatStuttered = 1
                    decisionType_R[i] = 0
                    lastChannelThatStuttered = 2
                else
                    if currentSegmentIndex_R < numberOfSegments
                        currentSegmentIndex_R += 1
                        decisionType_R[i] = 1
                    else
                        decisionType_R[i] = 0
                    endif
                endif
            endif
        else
            segmentChain_R[i] = numberOfSegments
            decisionType_R[i] = 0
        endif
    endfor
    totalOutputSegments_R = totalOutputSegments_L
endif

# Count stutters
stutterCount_L = totalOutputSegments_L - numberOfSegments
stutterCount_R = totalOutputSegments_R - numberOfSegments

appendInfoLine: ""
appendInfoLine: "Left channel: ", totalOutputSegments_L, " segments (", stutterCount_L, " stutters)"
appendInfoLine: "Right channel: ", totalOutputSegments_R, " segments (", stutterCount_R, " stutters)"

# ==================================================================
# PROCESS LEFT CHANNEL
# ==================================================================
appendInfoLine: ""
appendInfoLine: "Processing LEFT channel segments..."

selectObject: leftChannel

# Extract and process L segments
for i to numberOfSegments
    startTime = (i - 1) * windowSize
    endTime = min(i * windowSize, duration)
    
    selectObject: leftChannel
    segment_L[i] = Extract part: startTime, endTime, "rectangular", 1.0, "no"
    
    selectObject: segment_L[i]
    segDuration = Get total duration
    fadeInDuration = min(overlapSize, segDuration / 2)
    fadeOutDuration = min(overlapSize, segDuration / 2)
    
    Fade in: 0, 0, fadeInDuration, "yes"
    Fade out: 0, segDuration, -fadeOutDuration, "yes"
endfor

# Build L channel output
firstSegmentIndex = segmentChain_L[1]
selectObject: segment_L[firstSegmentIndex]
result_L = Copy: "result_L_temp"

for i from 2 to totalOutputSegments_L
    segmentIndex = segmentChain_L[i]
    
    if segmentIndex <= numberOfSegments
        segmentToConcatenate = segment_L[segmentIndex]
        
        selectObject: result_L, segmentToConcatenate
        newResult = Concatenate with overlap: overlapSize
        
        removeObject: result_L
        result_L = newResult
    endif
endfor

# Clean up L segments
for i to numberOfSegments
    removeObject: segment_L[i]
endfor

# ==================================================================
# PROCESS RIGHT CHANNEL
# ==================================================================
appendInfoLine: "Processing RIGHT channel segments..."

selectObject: rightChannel

# Extract and process R segments
for i to numberOfSegments
    startTime = (i - 1) * windowSize
    endTime = min(i * windowSize, duration)
    
    selectObject: rightChannel
    segment_R[i] = Extract part: startTime, endTime, "rectangular", 1.0, "no"
    
    selectObject: segment_R[i]
    segDuration = Get total duration
    fadeInDuration = min(overlapSize, segDuration / 2)
    fadeOutDuration = min(overlapSize, segDuration / 2)
    
    Fade in: 0, 0, fadeInDuration, "yes"
    Fade out: 0, segDuration, -fadeOutDuration, "yes"
endfor

# Build R channel output
firstSegmentIndex = segmentChain_R[1]
selectObject: segment_R[firstSegmentIndex]
result_R = Copy: "result_R_temp"

for i from 2 to totalOutputSegments_R
    segmentIndex = segmentChain_R[i]
    
    if segmentIndex <= numberOfSegments
        segmentToConcatenate = segment_R[segmentIndex]
        
        selectObject: result_R, segmentToConcatenate
        newResult = Concatenate with overlap: overlapSize
        
        removeObject: result_R
        result_R = newResult
    endif
endfor

# Clean up R segments
for i to numberOfSegments
    removeObject: segment_R[i]
endfor

# ==================================================================
# COMBINE L AND R INTO STEREO
# ==================================================================
appendInfoLine: ""
appendInfoLine: "Combining channels into stereo output..."

selectObject: result_L
duration_L = Get total duration
selectObject: result_R
duration_R = Get total duration

minDuration = min(duration_L, duration_R)

# Trim both to the shorter duration
if duration_L > minDuration
    selectObject: result_L
    trimmed_L = Extract part: 0, minDuration, "rectangular", 1.0, "no"
    removeObject: result_L
    result_L = trimmed_L
endif

if duration_R > minDuration
    selectObject: result_R
    trimmed_R = Extract part: 0, minDuration, "rectangular", 1.0, "no"
    removeObject: result_R
    result_R = trimmed_R
endif

# Combine into stereo
selectObject: result_L, result_R
stereoResult = Combine to stereo

# Clean up mono channels
removeObject: leftChannel, rightChannel, result_L, result_R

# Rename final result
selectObject: stereoResult
finalName$ = sound$ + "_stuttered"
Rename: finalName$

finalDuration = Get total duration

# ==================================================================
# VISUALIZATION
# ==================================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 1, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Bigram Stutter Effect: " + sound$
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.6
    Select inner viewport: 0.6, 7.6, 0.7, 1.5
    selectObject: soundID
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Select outer viewport: 0.1, 8, 0.5, 1.6
    Text left: "yes", "Original"
    
    # Result waveform (stereo)
    Select outer viewport: 0, 8, 1.7, 2.7
    Select inner viewport: 0.6, 7.6, 1.8, 2.6
    selectObject: stereoResult
    Colour: "{0.2, 0.5, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Result (Stereo)"
    Text bottom: "yes", "Time (s)"
    
    # Bigram Decision Chain - LEFT Channel
    Select outer viewport: 0, 4, 2.9, 4.2
    Select inner viewport: 0.6, 3.6, 3.0, 4.1
    
    # Calculate max positions to display
    maxDisplayPos_L = min(totalOutputSegments_L, 100)
    
    Axes: 0, maxDisplayPos_L, -0.5, 1.5
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, maxDisplayPos_L, -0.5, 1.5
    
    # Draw decision chain
    for i to maxDisplayPos_L
        if decisionType_L[i] = 0
            # Stutter (red)
            Paint circle (mm): "{0.9, 0.3, 0.3}", i - 0.5, 0.5, 1.2
        else
            # Advance (green)
            Paint circle (mm): "{0.3, 0.8, 0.3}", i - 0.5, 1.0, 1.2
        endif
    endfor
    
    # Reference lines
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    Draw line: 0, 0.5, maxDisplayPos_L, 0.5
    Draw line: 0, 1.0, maxDisplayPos_L, 1.0
    Solid line
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "L Decision"
    Text bottom: "yes", "Segment Position"
    
    # Bigram Decision Chain - RIGHT Channel
    Select outer viewport: 4, 8, 2.9, 4.2
    Select inner viewport: 4.6, 7.6, 3.0, 4.1
    
    maxDisplayPos_R = min(totalOutputSegments_R, 100)
    
    Axes: 0, maxDisplayPos_R, -0.5, 1.5
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, maxDisplayPos_R, -0.5, 1.5
    
    for i to maxDisplayPos_R
        if decisionType_R[i] = 0
            Paint circle (mm): "{0.9, 0.3, 0.3}", i - 0.5, 0.5, 1.2
        else
            Paint circle (mm): "{0.3, 0.8, 0.3}", i - 0.5, 1.0, 1.2
        endif
    endfor
    
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    Draw line: 0, 0.5, maxDisplayPos_R, 0.5
    Draw line: 0, 1.0, maxDisplayPos_R, 1.0
    Solid line
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "R Decision"
    Text bottom: "yes", "Segment Position"
    
    # Legend
    Select outer viewport: 0, 8, 4.3, 4.9
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 1.0, "left", 0.3, "half", "Red = Stutter (repeat) | Green = Advance (next)"
    Text: 1.0, "left", -2.7, "half", "Window: " + string$(window_size_ms) + "ms | Prob: " + fixed$(stutter_probability, 2) + " | Mode: " + stereo_mode$ + " | L stutters: " + string$(stutterCount_L) + " | R stutters: " + string$(stutterCount_R)
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", finalName$
appendInfoLine: "Channels: Stereo (true independent processing)"
appendInfoLine: "Duration: ", fixed$(finalDuration, 2), " seconds"
appendInfoLine: "Stereo mode: ", stereo_mode$

# === Play ===
if play_result
    appendInfoLine: ""
    appendInfoLine: "Playing result..."
    selectObject: stereoResult
    Play
endif

selectObject: stereoResult
