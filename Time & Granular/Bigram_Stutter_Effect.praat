# ============================================================
# Praat AudioTools - Bigram_Stutter_Effect.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Bigram Stutter Effect - applies probabilistic stuttering
#   using n-gram (bigram) logic. Segments audio into windows
#   and makes Markov chain decisions: repeat current segment
#   (stutter) or advance to next segment.
#
# Changelog v1.4:
#   DSP / timing / correctness:
#   - FIXED target-duration planning for high overlap. Chain length is now
#     derived from the actual concatenate hop (window-overlap), so output
#     always reaches the requested target before final trimming.
#   - Overlap must be strictly smaller than the window; zero overlap is now
#     allowed and uses plain Concatenate.
#   - Removed manual per-segment Fade in/out. Praat's Concatenate with
#     overlap already performs its own raised-cosine crossfade; v1.3 was
#     therefore windowing every join twice and unnecessarily dulling/pumping
#     the result.
#   - FIXED non-zero Sound time domains: extraction uses absolute source time.
#   - Output steps are extracted directly in chain order, avoiding creation
#     of a full source-segment pool when only a shorter target is requested.
#   - Ping-Pong now truly alternates stutter events L/R while preserving the
#     requested global stutter-event probability.
#   - Offset decision visualization now reflects the actual delayed R chain.
#   - Added mono/stereo validation, sample-rate guards, output complexity
#     guard, safe normalization for silent output, and Nyquist-safe viz.
#   - Final output is renamed after trimming so the requested name is stable.
#
# Changelog v1.3:
#   - Batched the L/R output build: was incremental Concatenate-with-
#     overlap on a growing result (O(n^2)); now copies each chain step
#     and concatenates once per channel (O(n)). Audio-equivalent.
#   - Viz: subtitle was drawn at y=-1.2 (below the title band, over the
#     original waveform); moved into the title band.
#
# BUGFIX v1.2:
#   - Fixed "No sound selected" error at line 665
#   - Ensured stereoResult is properly selected after trimming
# ============================================================

form Bigram Stutter Effect v1.4
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
    
    comment === Output ===
    positive Target_duration_s 8.0
    comment (Script will loop input to fill target duration)
    
    comment === Window Settings ===
    positive Window_size_ms 50
    real Stutter_probability_0_to_1 0.3
    real Overlap_ms 5
    
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
    window_size_ms = 80
    stutter_probability_0_to_1 = 0.2
    overlap_ms = 10
elsif preset = 3
    window_size_ms = 60
    stutter_probability_0_to_1 = 0.35
    overlap_ms = 8
elsif preset = 4
    window_size_ms = 40
    stutter_probability_0_to_1 = 0.55
    overlap_ms = 5
elsif preset = 5
    window_size_ms = 100
    stutter_probability_0_to_1 = 0.4
    overlap_ms = 15
elsif preset = 6
    window_size_ms = 25
    stutter_probability_0_to_1 = 0.6
    overlap_ms = 3
elsif preset = 7
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
if overlap_ms < 0
    exitScript: "Overlap must be >= 0 ms"
endif
if overlap_ms >= window_size_ms
    exitScript: "Overlap must be smaller than window size"
endif

# === Get Input ===
soundID = selected("Sound")
sound$ = selected$("Sound")

selectObject: soundID
sourceStart = Get start time
sourceEnd = Get end time
duration = Get total duration
originalChannels = Get number of channels
samplingFrequency = Get sampling frequency

if originalChannels > 2
    exitScript: "Bigram Stutter supports mono or stereo Sounds only"
endif

# === Convert to seconds ===
windowSize = window_size_ms / 1000
overlapSize = overlap_ms / 1000
hopSize = windowSize - overlapSize
stutter_probability = stutter_probability_0_to_1

minRenderable = 2 / samplingFrequency
if windowSize < minRenderable
    exitScript: "Window size is shorter than two samples at this sampling rate"
endif
if target_duration_s < minRenderable
    exitScript: "Target duration is shorter than two samples at this sampling rate"
endif

# === Calculate source and output segments ===
# Only complete source windows participate in the Markov chain.
numberOfSegments = floor(duration / windowSize + 0.000000000001)
if numberOfSegments < 2
    exitScript: "Sound is too short for the given window size. Please use a smaller window size."
endif

# N windows concatenated with overlap O have duration:
#   windowSize + (N-1) * hopSize
# Add one safety step at exact boundaries, then trim to the requested target.
if target_duration_s <= windowSize
    targetOutputSegments = 1
else
    targetOutputSegments = floor((target_duration_s - windowSize) / hopSize + 0.000000000001) + 2
endif

if targetOutputSegments > 20000
    exitScript: "This setting requires more than 20000 output segments. Reduce target duration or overlap."
endif
plannedDuration = windowSize + (targetOutputSegments - 1) * hopSize

# === Initialize Report ===
writeInfoLine: "=== Bigram Stutter Effect v1.4 ==="
appendInfoLine: "Source: ", sound$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Target duration: ", target_duration_s, " s"
appendInfoLine: ""
if preset > 1
    appendInfoLine: "Preset: ", preset$
endif
appendInfoLine: "Window size: ", window_size_ms, " ms"
appendInfoLine: "Stutter probability: ", stutter_probability
appendInfoLine: "Overlap: ", overlap_ms, " ms"
appendInfoLine: "Stereo mode: ", stereo_mode$
appendInfoLine: "Original channels: ", originalChannels
appendInfoLine: "Input segments: ", numberOfSegments
appendInfoLine: "Output steps: ", targetOutputSegments, " (planned ", fixed$(plannedDuration, 3), " s before trim)"
appendInfoLine: ""

# ==================================================================
# EXTRACT LEFT AND RIGHT CHANNELS
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
# BIGRAM / FIRST-ORDER MARKOV CHAINS
# decisionType_[i] describes the transition AFTER output position i:
#   0 = self-loop (stutter), 1 = advance.
# ==================================================================
appendInfoLine: ""
appendInfoLine: "Building LEFT channel stutter pattern (Bigram logic)..."

currentSegmentIndex_L = 1
for i to targetOutputSegments
    actualSegment = ((currentSegmentIndex_L - 1) mod numberOfSegments) + 1
    segmentChain_L[i] = actualSegment

    if i < targetOutputSegments
        randomValue = randomUniform(0, 1)
        if randomValue < stutter_probability
            decisionType_L[i] = 0
        else
            currentSegmentIndex_L += 1
            decisionType_L[i] = 1
        endif
    else
        decisionType_L[i] = 1
    endif
endfor
totalOutputSegments_L = targetOutputSegments

appendInfoLine: "Building RIGHT channel stutter pattern..."

# Right probability for asymmetric mode.
if stereo_mode = 5
    stutter_probability_R = stutter_probability * 0.5
    appendInfoLine: "  Asymmetric mode: R probability = ", fixed$(stutter_probability_R, 2)
else
    stutter_probability_R = stutter_probability
endif

if stereo_mode = 1
    # Same Markov decisions; source channel content can still differ in stereo input.
    appendInfoLine: "  Mode: Mono to Stereo (identical patterns)"
    for i to targetOutputSegments
        segmentChain_R[i] = segmentChain_L[i]
        decisionType_R[i] = decisionType_L[i]
    endfor

elsif stereo_mode = 2
    appendInfoLine: "  Mode: Independent (different random patterns)"
    currentSegmentIndex_R = 1
    for i to targetOutputSegments
        actualSegment = ((currentSegmentIndex_R - 1) mod numberOfSegments) + 1
        segmentChain_R[i] = actualSegment
        if i < targetOutputSegments
            randomValue = randomUniform(0, 1)
            if randomValue < stutter_probability_R
                decisionType_R[i] = 0
            else
                currentSegmentIndex_R += 1
                decisionType_R[i] = 1
            endif
        else
            decisionType_R[i] = 1
        endif
    endfor

elsif stereo_mode = 3
    appendInfoLine: "  Mode: Complementary (opposite behaviors)"
    currentSegmentIndex_R = 1
    for i to targetOutputSegments
        actualSegment = ((currentSegmentIndex_R - 1) mod numberOfSegments) + 1
        segmentChain_R[i] = actualSegment
        if i < targetOutputSegments
            if decisionType_L[i] = 0
                currentSegmentIndex_R += 1
                decisionType_R[i] = 1
            else
                decisionType_R[i] = 0
            endif
        else
            decisionType_R[i] = 1
        endif
    endfor

elsif stereo_mode = 4
    appendInfoLine: "  Mode: Offset (R delayed by 1 segment)"
    segmentChain_R[1] = segmentChain_L[1]
    if targetOutputSegments > 1
        for i from 2 to targetOutputSegments
            segmentChain_R[i] = segmentChain_L[i - 1]
        endfor
    endif
    for i to targetOutputSegments
        if i < targetOutputSegments
            if segmentChain_R[i + 1] = segmentChain_R[i]
                decisionType_R[i] = 0
            else
                decisionType_R[i] = 1
            endif
        else
            decisionType_R[i] = 1
        endif
    endfor

elsif stereo_mode = 5
    appendInfoLine: "  Mode: Asymmetric (R less stutter)"
    currentSegmentIndex_R = 1
    for i to targetOutputSegments
        actualSegment = ((currentSegmentIndex_R - 1) mod numberOfSegments) + 1
        segmentChain_R[i] = actualSegment
        if i < targetOutputSegments
            randomValue = randomUniform(0, 1)
            if randomValue < stutter_probability_R
                decisionType_R[i] = 0
            else
                currentSegmentIndex_R += 1
                decisionType_R[i] = 1
            endif
        else
            decisionType_R[i] = 1
        endif
    endfor

elsif stereo_mode = 6
    # Use the initial L random decisions as stutter-event opportunities,
    # then assign each event alternately to L and R.
    appendInfoLine: "  Mode: Ping-Pong (true alternating stutter events)"
    for i to targetOutputSegments
        eventMask[i] = decisionType_L[i]
    endfor

    currentSegmentIndex_L = 1
    currentSegmentIndex_R = 1
    nextStutterChannel = 1
    for i to targetOutputSegments
        segmentChain_L[i] = ((currentSegmentIndex_L - 1) mod numberOfSegments) + 1
        segmentChain_R[i] = ((currentSegmentIndex_R - 1) mod numberOfSegments) + 1

        if i < targetOutputSegments
            if eventMask[i] = 0
                if nextStutterChannel = 1
                    decisionType_L[i] = 0
                    currentSegmentIndex_R += 1
                    decisionType_R[i] = 1
                    nextStutterChannel = 2
                else
                    currentSegmentIndex_L += 1
                    decisionType_L[i] = 1
                    decisionType_R[i] = 0
                    nextStutterChannel = 1
                endif
            else
                currentSegmentIndex_L += 1
                currentSegmentIndex_R += 1
                decisionType_L[i] = 1
                decisionType_R[i] = 1
            endif
        else
            decisionType_L[i] = 1
            decisionType_R[i] = 1
        endif
    endfor
endif

totalOutputSegments_R = targetOutputSegments

# Count stutters
uniqueSegments_L = 0
for i to totalOutputSegments_L
    if i = 1 or segmentChain_L[i] <> segmentChain_L[i-1]
        uniqueSegments_L += 1
    endif
endfor
stutterCount_L = totalOutputSegments_L - uniqueSegments_L

uniqueSegments_R = 0
for i to totalOutputSegments_R
    if i = 1 or segmentChain_R[i] <> segmentChain_R[i-1]
        uniqueSegments_R += 1
    endif
endfor
stutterCount_R = totalOutputSegments_R - uniqueSegments_R

appendInfoLine: ""
appendInfoLine: "Left channel: ", totalOutputSegments_L, " segments (", stutterCount_L, " stutters)"
appendInfoLine: "Right channel: ", totalOutputSegments_R, " segments (", stutterCount_R, " stutters)"

# ==================================================================
# PROCESS LEFT CHANNEL
# ==================================================================
appendInfoLine: ""
appendInfoLine: "Processing LEFT channel output steps..."

# Extract directly in chain order. Do not pre-fade: Concatenate with overlap
# performs the crossfade itself. Object creation order equals playback order.
for i to totalOutputSegments_L
    segmentIndex = segmentChain_L[i]
    startTime = sourceStart + (segmentIndex - 1) * windowSize
    endTime = startTime + windowSize
    selectObject: leftChannel
    seqL[i] = Extract part: startTime, endTime, "rectangular", 1.0, "no"
endfor

selectObject: seqL[1]
if totalOutputSegments_L > 1
    for i from 2 to totalOutputSegments_L
        plusObject: seqL[i]
    endfor
endif
if overlapSize > 0
    result_L = Concatenate with overlap: overlapSize
else
    result_L = Concatenate
endif
Rename: "result_L_temp"
for i to totalOutputSegments_L
    removeObject: seqL[i]
endfor

# ==================================================================
# PROCESS RIGHT CHANNEL
# ==================================================================
appendInfoLine: "Processing RIGHT channel output steps..."

for i to totalOutputSegments_R
    segmentIndex = segmentChain_R[i]
    startTime = sourceStart + (segmentIndex - 1) * windowSize
    endTime = startTime + windowSize
    selectObject: rightChannel
    seqR[i] = Extract part: startTime, endTime, "rectangular", 1.0, "no"
endfor

selectObject: seqR[1]
if totalOutputSegments_R > 1
    for i from 2 to totalOutputSegments_R
        plusObject: seqR[i]
    endfor
endif
if overlapSize > 0
    result_R = Concatenate with overlap: overlapSize
else
    result_R = Concatenate
endif
Rename: "result_R_temp"
for i to totalOutputSegments_R
    removeObject: seqR[i]
endfor

# ==================================================================
# COMBINE TO STEREO
# ==================================================================
appendInfoLine: ""
appendInfoLine: "Combining to stereo output..."

selectObject: result_L, result_R
stereoResult = Combine to stereo

# Trim to the requested target duration and normalize time domain to 0.
selectObject: stereoResult
actualDuration = Get total duration
resultStart = Get start time
if actualDuration > target_duration_s
    trimmedResult = Extract part: resultStart, resultStart + target_duration_s, "rectangular", 1, "no"
    removeObject: stereoResult
    stereoResult = trimmedResult
endif

selectObject: stereoResult
Shift times to: "start time", 0
Rename: sound$ + "_BigramStutter"
resultPeak = Get absolute extremum: 0, 0, "Sinc70"
if resultPeak > 0
    Scale peak: 0.95
endif

# Clean up temporary channels
removeObject: leftChannel, rightChannel, result_L, result_R

# ==================================================================
# VISUALIZATION
# ==================================================================

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    
    # Title (its own band)
    Select outer viewport: 0, 8, 0, 0.33
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Bigram Stutter Effect v1.4##"
    
    # Subtitle (separate band so it can't collide with the title)
    Select outer viewport: 0, 8, 0.33, 0.5
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", 0.5, "half", sound$ + " | " + stereo_mode$ + " | P=" + fixed$(stutter_probability, 2)
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.6, 7.7, 0.7, 1.35
    selectObject: soundID
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    Text top: "no", fixed$(duration, 2) + " s"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.4, 2.2
    Select inner viewport: 0.6, 7.7, 1.5, 2.15
    selectObject: stereoResult
    Colour: "{0.3, 0.6, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Stuttered"
    Text bottom: "yes", "Time (s)"
    
    selectObject: stereoResult
    resultDur = Get total duration
    Text top: "no", fixed$(resultDur, 2) + " s (target: " + fixed$(target_duration_s, 1) + "s)"
    
    # Decision chain visualization (first 100 segments)
    Select outer viewport: 0, 8, 2.3, 4.8
    Select inner viewport: 0.6, 7.7, 2.4, 4.75
    
    maxVizSegments = min(100, totalOutputSegments_L)
    Axes: 0, maxVizSegments + 1, -0.5, 1.5
    Paint rectangle: "{0.97, 0.98, 0.97}", 0, maxVizSegments + 1, -0.5, 1.5
    
    # Draw decision chain for L channel
    for i to maxVizSegments
        if decisionType_L[i] = 0
            # Stutter (self-loop)
            Colour: "{0.9, 0.3, 0.3}"
            Paint rectangle: "{0.9, 0.3, 0.3}", i - 0.4, i + 0.4, 0.6, 1.4
        else
            # Advance
            Colour: "{0.3, 0.7, 0.5}"
            Paint rectangle: "{0.3, 0.7, 0.5}", i - 0.4, i + 0.4, 0.6, 1.4
        endif
    endfor
    
    # Draw decision chain for R channel
    for i to min(maxVizSegments, totalOutputSegments_R)
        if decisionType_R[i] = 0
            # Stutter
            Colour: "{0.9, 0.5, 0.5}"
            Paint rectangle: "{0.9, 0.5, 0.5}", i - 0.4, i + 0.4, -0.4, 0.4
        else
            # Advance
            Colour: "{0.5, 0.8, 0.6}"
            Paint rectangle: "{0.5, 0.8, 0.6}", i - 0.4, i + 0.4, -0.4, 0.4
        endif
    endfor
    
    # Labels
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "L / R"
    Text bottom: "yes", "Segment Index (first " + string$(maxVizSegments) + ")"
    Text top: "no", "Decision Chain (Red=Stutter, Green=Advance)"
    
    # Legend
    Font size: 6
    Colour: "{0.9, 0.3, 0.3}"
    Text: maxVizSegments * 0.98, "right", 1.0, "half", "L Stutter"
    Colour: "{0.3, 0.7, 0.5}"
    Text: maxVizSegments * 0.98, "right", 1.3, "half", "L Advance"
    Colour: "{0.9, 0.5, 0.5}"
    Text: maxVizSegments * 0.98, "right", 0.0, "half", "R Stutter"
    Colour: "{0.5, 0.8, 0.6}"
    Text: maxVizSegments * 0.98, "right", 0.3, "half", "R Advance"
    
    # Spectrograms
    vizMaxFreq = min(5000, 0.95 * samplingFrequency / 2)
    Select outer viewport: 0, 4, 4.9, 6.4
    Select inner viewport: 0.6, 3.7, 5.0, 6.35
    
    selectObject: soundID
    if originalChannels > 1
        Extract one channel: 1
        tmpOrig = selected("Sound")
    else
        Copy: "tmpOrig"
        tmpOrig = selected("Sound")
    endif
    
    To Spectrogram: 0.005, vizMaxFreq, 0.002, 20, "Gaussian"
    origSpec = selected("Spectrogram")
    Paint: 0, 0, 0, vizMaxFreq, 100, "yes", 50, 6, 0, "no"
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq (Hz)"
    Text top: "no", "Original"
    
    removeObject: origSpec, tmpOrig
    
    Select outer viewport: 4, 8, 4.9, 6.4
    Select inner viewport: 4.4, 7.7, 5.0, 6.35
    
    selectObject: stereoResult
    Extract one channel: 1
    tmpResult = selected("Sound")
    
    To Spectrogram: 0.005, vizMaxFreq, 0.002, 20, "Gaussian"
    resultSpec = selected("Spectrogram")
    Paint: 0, 0, 0, vizMaxFreq, 100, "yes", 50, 6, 0, "no"
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq (Hz)"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Stuttered (L)"
    
    removeObject: resultSpec, tmpResult
    
    # Info panel
    Select outer viewport: 0, 8, 6.5, 7.5
    Select inner viewport: 0.6, 7.7, 6.6, 7.45
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Font size: 7
    Colour: "Black"
    
    Text: 0.05, "left", 0.75, "half", "Processing Details:"
    Font size: 6
    Text: 0.05, "left", 0.55, "half", "Window: " + string$(window_size_ms) + " ms | Overlap: " + string$(overlap_ms) + " ms"
    Text: 0.05, "left", 0.35, "half", "Stutter Probability: " + fixed$(stutter_probability, 2)
    Text: 0.05, "left", 0.15, "half", "L: " + string$(totalOutputSegments_L) + " segs (" + string$(stutterCount_L) + " stutters)"
    
    Font size: 7
    
    # Get the actual final duration before using it
    selectObject: stereoResult
    resultDur = Get total duration
    
    Text: 0.55, "left", 0.75, "half", "Output:"
    Font size: 6
    Text: 0.55, "left", 0.55, "half", "Target: " + fixed$(target_duration_s, 1) + " s | Actual: " + fixed$(resultDur, 2) + " s"
    Text: 0.55, "left", 0.35, "half", "Stereo Mode: " + stereo_mode$
    Text: 0.55, "left", 0.15, "half", "R: " + string$(totalOutputSegments_R) + " segs (" + string$(stutterCount_R) + " stutters)"
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
endif

# ==================================================================
# FINAL OUTPUT
# ==================================================================

appendInfoLine: ""
appendInfoLine: "=== Complete ==="

# Ensure stereoResult is selected before getting its name
selectObject: stereoResult
appendInfoLine: "Output: ", selected$("Sound")

selectObject: stereoResult
finalDur = Get total duration
appendInfoLine: "Final duration: ", fixed$(finalDur, 2), " s"

if play_result
    appendInfoLine: ""
    appendInfoLine: "Playing result..."
    selectObject: stereoResult
    Play
endif