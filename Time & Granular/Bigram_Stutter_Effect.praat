# ============================================================
# Praat AudioTools - Bigram_Stutter_Effect.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.4.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Bigram Stutter Effect - applies probabilistic stuttering
#   using n-gram (bigram) logic. Segments audio into windows
#   and makes Markov chain decisions: repeat current segment
#   (stutter) or advance to next segment.
#
# Changelog v1.4.1:
#   Visualization-only suite alignment:
#   - Replaced the legacy decision bars + spectrogram report with the
#     standardized Source -> Bigram transition map -> Output -> Summary view.
#   - The transition map now directly shows first-order Markov behavior:
#     diagonal motion = advance, horizontal motion = self-loop/stutter,
#     with separate L/R lanes so stereo modes remain legible.
#   - Added shared waveform scaling, suite panel styling, safe display names,
#     and compact summary reporting. DSP and timing are unchanged.
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

form Bigram Stutter Effect v1.4.1
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
writeInfoLine: "=== Bigram Stutter Effect v1.4.1 ==="
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
# VISUALIZATION  (current Praat AudioTools suite styling)
# Source -> signature Bigram transition map -> Output -> Summary.
# The central map directly embodies the first-order Markov law:
#   diagonal path = advance to the next source segment,
#   horizontal path = self-loop / stutter,
#   downward reset = cyclic source wrap.
# L and R use separate lanes so stereo behavior remains legible.
# ==================================================================

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 7.10
    Black
    Plain line

    display_name$ = replace$(sound$, "_", " ", 0)
    presetLabel$ = preset$

    # Mono, zero-based display copies.
    selectObject: soundID
    if originalChannels > 1
        vizOrig = Convert to mono
    else
        vizOrig = Copy: "viz orig"
    endif
    selectObject: vizOrig
    vizOrigStart = Get start time
    Shift times by: -vizOrigStart

    selectObject: stereoResult
    vizResult = Convert to mono
    selectObject: vizResult
    vizResultStart = Get start time
    Shift times by: -vizResultStart

    # Shared waveform amplitude scale.
    selectObject: vizOrig
    oPeak = Get absolute extremum: 0, 0, "None"
    selectObject: vizResult
    rPeak = Get absolute extremum: 0, 0, "None"
    sharedPeak = oPeak
    if rPeak > sharedPeak
        sharedPeak = rPeak
    endif
    if sharedPeak < 0.001
        sharedPeak = 0.001
    endif
    sharedAmp = sharedPeak * 1.15

    selectObject: stereoResult
    resultDur = Get total duration

    # ----------------------------------------------------------
    # TITLE / SUBTITLE
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Bigram Stutter Effect##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -1.30, "half", "Bigram Stutter Effect.praat  |  " + presetLabel$ + "  |  " + display_name$

    # ----------------------------------------------------------
    # SOURCE
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.65, 1.90
    Select inner viewport: 0.55, 7.75, 0.82, 1.78
    Axes: 0, duration, -sharedAmp, sharedAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, -sharedAmp, sharedAmp
    selectObject: vizOrig
    Colour: "{0.62, 0.62, 0.66}"
    Draw: 0, duration, -sharedAmp, sharedAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "##Source##"
    Font size: 6
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Time (s)"
    Axes: 0, duration, -sharedAmp, sharedAmp
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.01 * duration, "left", 0.82 * sharedAmp, "half", string$(numberOfSegments) + " source windows  |  window " + fixed$(window_size_ms, 1) + " ms"
    Text: 0.99 * duration, "right", 0.82 * sharedAmp, "half", "overlap " + fixed$(overlap_ms, 1) + " ms  |  hop " + fixed$(hopSize * 1000, 1) + " ms"

    # ----------------------------------------------------------
    # BIGRAM TRANSITION MAP - signature process view
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 2.05, 4.55
    Select inner viewport: 0.55, 7.75, 2.25, 4.40
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1

    # Separate channel lanes. Vertical position within each lane = source segment index.
    laneX0 = 0.10
    laneX1 = 0.96
    laneSpan = laneX1 - laneX0
    laneLowL = 0.57
    laneHighL = 0.88
    laneLowR = 0.12
    laneHighR = 0.43
    laneHL = laneHighL - laneLowL
    laneHR = laneHighR - laneLowR

    Paint rectangle: "{0.955, 0.965, 0.985}", laneX0, laneX1, laneLowL, laneHighL
    Paint rectangle: "{0.970, 0.955, 0.985}", laneX0, laneX1, laneLowR, laneHighR

    maxVizSteps = min(80, totalOutputSegments_L)
    stepDen = maxVizSteps - 1
    if stepDen < 1
        stepDen = 1
    endif
    segDen = numberOfSegments - 1
    if segDen < 1
        segDen = 1
    endif

    # Light reference lines at source-segment endpoints.
    Colour: "{0.84, 0.84, 0.86}"
    Draw line: laneX0, laneLowL, laneX1, laneLowL
    Draw line: laneX0, laneHighL, laneX1, laneHighL
    Draw line: laneX0, laneLowR, laneX1, laneLowR
    Draw line: laneX0, laneHighR, laneX1, laneHighR

    if maxVizSteps > 1
        for i to maxVizSteps - 1
            x1 = laneX0 + laneSpan * (i - 1) / stepDen
            x2 = laneX0 + laneSpan * i / stepDen

            yL1 = laneLowL + laneHL * (segmentChain_L[i] - 1) / segDen
            yL2 = laneLowL + laneHL * (segmentChain_L[i + 1] - 1) / segDen
            yR1 = laneLowR + laneHR * (segmentChain_R[i] - 1) / segDen
            yR2 = laneLowR + laneHR * (segmentChain_R[i + 1] - 1) / segDen

            # L transition: red horizontal = self-loop, blue = advance/wrap.
            if decisionType_L[i] = 0
                Colour: "{0.88, 0.28, 0.28}"
                Line width: 2.4
            else
                Colour: "{0.30, 0.53, 0.82}"
                Line width: 1.3
            endif
            Draw line: x1, yL1, x2, yL2

            # R transition: orange horizontal = self-loop, purple = advance/wrap.
            if decisionType_R[i] = 0
                Colour: "{0.95, 0.55, 0.20}"
                Line width: 2.4
            else
                Colour: "{0.48, 0.33, 0.72}"
                Line width: 1.3
            endif
            Draw line: x1, yR1, x2, yR2
        endfor
    endif
    Line width: 1

    # Lane labels and direct law legend.
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.73, "half", "L"
    Text: 0.02, "left", 0.28, "half", "R"
    Text: laneX0 - 0.01, "right", laneLowL, "half", "1"
    Text: laneX0 - 0.01, "right", laneHighL, "half", string$(numberOfSegments)
    Text: laneX0 - 0.01, "right", laneLowR, "half", "1"
    Text: laneX0 - 0.01, "right", laneHighR, "half", string$(numberOfSegments)

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "##Bigram transition map##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: laneX0, "left", 0.96, "half", "diagonal = advance  |  horizontal = self-loop / stutter  |  reset = source wrap"
    Text: laneX1, "right", 0.96, "half", "first " + string$(maxVizSteps) + " output steps"
    Text: laneX0, "left", 0.49, "half", "blue = L advance  |  red = L stutter"
    Text: laneX1, "right", 0.49, "half", "purple = R advance  |  orange = R stutter"
    Text: laneX0, "left", 0.04, "half", "source segment index ->"
    Text: laneX1, "right", 0.04, "half", stereo_mode$ + "  |  P=" + fixed$(stutter_probability, 2)

    # ----------------------------------------------------------
    # OUTPUT
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.70, 5.95
    Select inner viewport: 0.55, 7.75, 4.87, 5.83
    Axes: 0, resultDur, -sharedAmp, sharedAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, resultDur, -sharedAmp, sharedAmp
    selectObject: vizResult
    Colour: "{0.48, 0.33, 0.72}"
    Draw: 0, resultDur, -sharedAmp, sharedAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "##Output##"
    Font size: 6
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Time (s)"
    Axes: 0, resultDur, -sharedAmp, sharedAmp
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.01 * resultDur, "left", 0.82 * sharedAmp, "half", string$(totalOutputSegments_L) + " output windows  |  target " + fixed$(target_duration_s, 2) + " s"
    Text: 0.99 * resultDur, "right", 0.82 * sharedAmp, "half", "L stutters " + string$(stutterCount_L) + "  |  R stutters " + string$(stutterCount_R)

    # ----------------------------------------------------------
    # SUMMARY
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.10, 7.05
    Select inner viewport: 0.30, 7.80, 6.17, 6.98
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "{0.48, 0.48, 0.48}"
    Draw rectangle: 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.80, "half", "##Summary##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.49, "half", presetLabel$ + "  |  window " + fixed$(window_size_ms, 1) + " ms  |  overlap " + fixed$(overlap_ms, 1) + " ms  |  hop " + fixed$(hopSize * 1000, 1) + " ms  |  P=" + fixed$(stutter_probability, 2) + "  |  " + stereo_mode$
    Text: 0.02, "left", 0.18, "half", "Source " + fixed$(duration, 2) + " s / " + string$(numberOfSegments) + " windows  |  Output " + fixed$(resultDur, 2) + " s / " + string$(totalOutputSegments_L) + " steps  |  stutters L=" + string$(stutterCount_L) + ", R=" + string$(stutterCount_R)

    Font size: 10
    Colour: "Black"
    Line width: 1

    removeObject: vizOrig, vizResult
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