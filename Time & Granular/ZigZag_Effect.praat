# ============================================================
# Praat AudioTools - ZigZag_Effect.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   ZigZag Effect - creates zigzag time manipulation by moving
#   forward and backward through the audio timeline. Two modes:
#   Stutter (always play forward) creates rhythmic repetition,
#   Scrub (reverse when moving back) creates tape manipulation.
#
#
# Changelog v0.5:
#   - VISUALIZATION ONLY: replaced the dense segment-bar display with a
#     continuous read-head trajectory. X = source position; Y = output order.
#     In Scrub mode backward grains visibly travel left; in Stutter mode the
#     source position steps back but each grain still reads forward.
#   - Source/output waveform panels now share one amplitude scale and use a
#     zero-based mono visualization copy, without changing multichannel DSP.
#   - Standardized title/subtitle, panel spacing, muted suite colours and
#     summary strip; display names render underscores as spaces.
#   - Fixed the final Picture viewport so full-page EPS/PNG export works.
#
# Changelog v0.4:
#   - API compatibility: public form is byte-for-byte unchanged.
#   - Fixed non-zero source xmin by processing a private zero-based copy.
#   - Preserves original mono/stereo/multichannel channel count.
#   - Hardened Segment_duration_variation so generated durations stay positive.
#   - Effective overlap is capped below the shortest generated grain length.
#   - Safe peak normalization skips digital silence.
#   - Visualization title uses explicit normalized axes.
#   - Progress display is clamped to 100%.
#
# Changelog v0.3:
#   - Stitching now batched: grains collected and concatenated in a
#     single Concatenate-with-overlap pass instead of re-concatenating a
#     growing master each iteration (O(n) vs O(n^2)). Audio-equivalent.
#   - maxSegments exposed as a form field (default 500).
#   - Viz: legend labels were placed in source-second coordinates and
#     overlapped on multi-second files; now drawn in normalized axes.
#
# Changelog v0.2:
#   - Added visualization
#   - Modern input check
#   - Track segments for display
# ============================================================

form ZigZag Time Effect
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Default (Tape Scrub)
        option Subtle Stutter
        option Aggressive Glitch
        option Tape Wobble
        option Custom
    
    comment === Mode ===
    optionmenu Playback_mode 2
        option Stutter (always play forward)
        option Scrub (reverse when moving back)
    
    comment === ZigZag Parameters ===
    positive Zigzag_time_s 0.05
    positive Forward_ratio 0.6
    positive Segment_overlap_s 0.002
    
    comment === Direction Changes ===
    natural Direction_changes_per_second 20
    positive Backward_distance_factor 0.8
    
    comment === Envelope ===
    optionmenu Window_type 1
        option Hanning
        option Hamming
        option Rectangular
    
    comment === Variation ===
    positive Segment_duration_variation 0.15
    positive Amplitude_variation 0.1
    
    comment === Output ===
    natural Max_segments 500
    positive Scale_peak 0.91
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 1
    # Default (Tape Scrub)
    playback_mode = 2
    zigzag_time_s = 0.05
    forward_ratio = 0.6
    segment_overlap_s = 0.002
    direction_changes_per_second = 20
    backward_distance_factor = 0.8
    segment_duration_variation = 0.15
    amplitude_variation = 0.1
elsif preset = 2
    # Subtle Stutter
    playback_mode = 1
    zigzag_time_s = 0.08
    forward_ratio = 0.75
    segment_overlap_s = 0.003
    direction_changes_per_second = 12
    backward_distance_factor = 0.5
    segment_duration_variation = 0.08
    amplitude_variation = 0.05
elsif preset = 3
    # Aggressive Glitch
    playback_mode = 2
    zigzag_time_s = 0.03
    forward_ratio = 0.5
    segment_overlap_s = 0.001
    direction_changes_per_second = 35
    backward_distance_factor = 1.2
    segment_duration_variation = 0.25
    amplitude_variation = 0.2
elsif preset = 4
    # Tape Wobble
    playback_mode = 2
    zigzag_time_s = 0.12
    forward_ratio = 0.65
    segment_overlap_s = 0.005
    direction_changes_per_second = 8
    backward_distance_factor = 0.6
    segment_duration_variation = 0.12
    amplitude_variation = 0.08
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
soundName$ = selected$("Sound")

selectObject: original
totalDuration = Get total duration
sampleRate = Get sampling frequency

# === Validate ===
if zigzag_time_s >= totalDuration
    exitScript: "ZigZag time must be less than sound duration."
endif

# Private zero-based processing copy; original object/time domain stay untouched.
selectObject: original
workSource = Copy: "zigzag_work"
selectObject: workSource
workStart = Get start time
if workStart <> 0
    Shift times by: -workStart
endif

# Keep every randomized grain duration strictly positive.
safeDurationVariation = segment_duration_variation
if safeDurationVariation >= 1
    safeDurationVariation = 0.99
endif

# Amplitude jitter is intended as a positive gain range around unity.
safeAmplitudeVariation = amplitude_variation
if safeAmplitudeVariation >= 1
    safeAmplitudeVariation = 0.99
endif

# === Get Preset/Mode Names ===
if preset = 1
    presetName$ = "Tape Scrub"
elsif preset = 2
    presetName$ = "Subtle Stutter"
elsif preset = 3
    presetName$ = "Aggressive Glitch"
elsif preset = 4
    presetName$ = "Tape Wobble"
else
    presetName$ = "Custom"
endif

if playback_mode = 1
    modeName$ = "Stutter"
else
    modeName$ = "Scrub"
endif

# === Base Calculations ===
segment_duration = 1.0 / direction_changes_per_second
if segment_duration > zigzag_time_s
    segment_duration = zigzag_time_s / 2
endif

# Window type string
if window_type = 1
    windowName$ = "Hanning"
elsif window_type = 2
    windowName$ = "Hamming"
else
    windowName$ = "Rectangular"
endif

# === Info ===
writeInfoLine: "=== ZigZag Effect ==="
appendInfoLine: "Source: ", soundName$, " (", fixed$(totalDuration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Mode: ", modeName$
appendInfoLine: ""
appendInfoLine: "Processing..."

# === Store Segment Info for Visualization ===
maxSegments = max_segments
segStarts# = zero#(maxSegments)
segEnds# = zero#(maxSegments)
segDirections# = zero#(maxSegments)

# === Processing Loop ===
currentPosition = 0.0
direction = 1
segmentCount = 0
minGrainDuration = totalDuration

while currentPosition < totalDuration and segmentCount < maxSegments
    segmentCount += 1
    
    # === Determine Segment ===
    if direction = 1
        # FORWARD SEGMENT
        var = randomUniform(1.0 - safeDurationVariation, 1.0 + safeDurationVariation)
        currentSegDuration = segment_duration * var
        
        startTime = currentPosition
        endTime = currentPosition + currentSegDuration
        
        if endTime > totalDuration
            endTime = totalDuration
        endif
        
        # Extract
        selectObject: workSource
        grain = Extract part: startTime, endTime, windowName$, 1, "no"
        
        # Store for visualization
        segStarts#[segmentCount] = startTime
        segEnds#[segmentCount] = endTime
        segDirections#[segmentCount] = 1
        
        # Move forward
        currentPosition += currentSegDuration * forward_ratio
        direction = -1
        
    else
        # BACKWARD SEGMENT
        var = randomUniform(1.0 - safeDurationVariation, 1.0 + safeDurationVariation)
        currentSegDuration = segment_duration * var
        
        backwardDistance = currentSegDuration * backward_distance_factor
        backStartPos = currentPosition - backwardDistance
        if backStartPos < 0
            backStartPos = 0
        endif
        
        startTime = backStartPos
        endTime = backStartPos + currentSegDuration
        
        if endTime > totalDuration
            endTime = totalDuration
            startTime = endTime - currentSegDuration
            if startTime < 0
                startTime = 0
            endif
        endif
        
        # Extract
        selectObject: workSource
        grain = Extract part: startTime, endTime, windowName$, 1, "no"
        
        # Scrub mode: reverse backward segments
        if playback_mode = 2
            Reverse
        endif
        
        # Store for visualization
        segStarts#[segmentCount] = startTime
        segEnds#[segmentCount] = endTime
        segDirections#[segmentCount] = -1
        
        # Move forward slightly
        currentPosition += currentSegDuration * forward_ratio * 0.3
        direction = 1
    endif
    
    # Track shortest actual extracted grain for safe batch overlap.
    selectObject: grain
    thisGrainDuration = Get total duration
    if thisGrainDuration < minGrainDuration
        minGrainDuration = thisGrainDuration
    endif

    # === Amplitude Jitter ===
    ampFactor = randomUniform(1.0 - safeAmplitudeVariation, 1.0 + safeAmplitudeVariation)
    Formula: ~ self * ampFactor
    
    # === Store grain for batched concatenation ===
    grainID[segmentCount] = grain
    
    # Progress
    if segmentCount mod 100 = 0
        perc = round((currentPosition / totalDuration) * 100)
        if perc > 100
            perc = 100
        endif
        appendInfoLine: "  Segment ", segmentCount, " (", perc, "%)"
    endif
endwhile

# === Batched Concatenation (single pass; equivalent to pairwise) ===
effectiveOverlap = segment_overlap_s
if minGrainDuration > 0
    maxSafeOverlap = minGrainDuration * 0.99
    if effectiveOverlap > maxSafeOverlap
        effectiveOverlap = maxSafeOverlap
        appendInfoLine: "  Overlap reduced to ", fixed$(effectiveOverlap * 1000, 3), " ms to fit shortest grain."
    endif
endif

if segmentCount = 1
    masterID = grainID[1]
else
    selectObject: grainID[1]
    for i from 2 to segmentCount
        plusObject: grainID[i]
    endfor
    if effectiveOverlap > 0
        masterID = Concatenate with overlap: effectiveOverlap
    else
        masterID = Concatenate
    endif
    for i from 1 to segmentCount
        removeObject: grainID[i]
    endfor
endif

removeObject: workSource

# === Finalize ===
selectObject: masterID
Rename: soundName$ + "_zigzag_" + modeName$
resultPeak = Get absolute extremum: 0, 0, "Sinc70"
if resultPeak > 0
    Scale peak: scale_peak
endif
result = selected("Sound")

selectObject: result
outputDuration = Get total duration

# === Visualization ===
if draw_visualization
    Erase all
    Black
    Plain line

    # Display-only mono, zero-based copies. DSP/output channel count are untouched.
    selectObject: original
    originalChannels = Get number of channels
    if originalChannels > 1
        vizOriginal = Convert to mono
    else
        vizOriginal = Copy: "zigzag_viz_original"
    endif
    selectObject: vizOriginal
    vizStart = Get start time
    if vizStart <> 0
        Shift times by: -vizStart
    endif

    selectObject: result
    resultChannels = Get number of channels
    if resultChannels > 1
        vizResult = Convert to mono
    else
        vizResult = Copy: "zigzag_viz_result"
    endif
    selectObject: vizResult
    vizResultStart = Get start time
    if vizResultStart <> 0
        Shift times by: -vizResultStart
    endif

    # One amplitude scale for honest before/after comparison.
    selectObject: vizOriginal
    originalPeak = Get absolute extremum: 0, 0, "None"
    selectObject: vizResult
    outputPeak = Get absolute extremum: 0, 0, "None"
    sharedPeak = max(originalPeak, outputPeak)
    if sharedPeak < 0.01
        sharedPeak = 0.01
    endif
    sharedAmp = sharedPeak * 1.12

    displayName$ = replace$(soundName$, "_", " ", 0)

    # ----------------------------------------------------------
    # TITLE
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.55
    Select inner viewport: 0.60, 7.70, 0.04, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.72, "half", "##ZIGZAG EFFECT##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.18, "half",
        ... displayName$ + "  |  " + presetName$ + "  |  " + modeName$
        ... + "  |  " + string$(originalChannels) + " ch -> " + string$(resultChannels) + " ch"

    # ----------------------------------------------------------
    # ORIGINAL WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.68, 1.72
    Select inner viewport: 0.60, 7.70, 0.84, 1.64
    Axes: 0, totalDuration, -sharedAmp, sharedAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, totalDuration, -sharedAmp, sharedAmp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, totalDuration, 0
    selectObject: vizOriginal
    Colour: "{0.55, 0.55, 0.55}"
    Line width: 1
    Draw: 0, totalDuration, -sharedAmp, sharedAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Amp"

    Select outer viewport: 0.60, 7.70, 0.64, 0.82
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Source"

    # ----------------------------------------------------------
    # ZIGZAG OUTPUT WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 1.92, 2.96
    Select inner viewport: 0.60, 7.70, 2.08, 2.88
    Axes: 0, outputDuration, -sharedAmp, sharedAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, outputDuration, -sharedAmp, sharedAmp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, outputDuration, 0
    selectObject: vizResult
    Colour: "{0.25, 0.45, 0.75}"
    Line width: 1
    Draw: 0, outputDuration, -sharedAmp, sharedAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Amp"

    Select outer viewport: 0.60, 7.70, 1.88, 2.06
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Zigzag output"

    # ----------------------------------------------------------
    # READ-HEAD TRAJECTORY — direct visual description of process
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 3.22, 5.52
    Select inner viewport: 0.60, 7.70, 3.40, 5.35
    Axes: 0, totalDuration, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, totalDuration, 0, 1

    # Light source-position guides.
    Colour: "{0.88, 0.88, 0.90}"
    Dotted line
    for q from 1 to 3
        gx = totalDuration * q / 4
        Draw line: gx, 0, gx, 1
    endfor
    Solid line

    # Keep the whole trajectory when feasible; for very large renders, sample
    # every Nth segment only for display. DSP still uses every segment.
    displayStep = ceiling(segmentCount / 240)
    if displayStep < 1
        displayStep = 1
    endif
    displayCount = ceiling(segmentCount / displayStep)
    shown = 0
    havePrevious = 0
    previousPlayEnd = 0
    previousY = 0

    for seg from 1 to segmentCount
        if (seg - 1) mod displayStep = 0
            shown += 1
            y0 = (shown - 1) / displayCount
            y1 = shown / displayCount
            startT = segStarts#[seg]
            endT = segEnds#[seg]
            dir = segDirections#[seg]

            # Playback direction, not merely extraction bounds.
            if dir = 1
                playStart = startT
                playEnd = endT
                stroke$ = "{0.35, 0.60, 0.40}"
            else
                if playback_mode = 2
                    # Scrub: the backward grain itself is read in reverse.
                    playStart = endT
                    playEnd = startT
                    stroke$ = "{0.78, 0.28, 0.22}"
                else
                    # Stutter: source position steps back, but the grain still reads forward.
                    playStart = startT
                    playEnd = endT
                    stroke$ = "{0.35, 0.60, 0.40}"
                endif
            endif

            # Relocation between grains. In Stutter, the actual back-step is the
            # red horizontal/diagonal jump; the grain that follows remains green.
            if havePrevious
                if playback_mode = 1 and dir = -1
                    Colour: "{0.78, 0.28, 0.22}"
                    Line width: 1.2
                else
                    Colour: "{0.68, 0.68, 0.70}"
                    Line width: 0.7
                endif
                Draw line: previousPlayEnd, previousY, playStart, y0
            endif

            Colour: stroke$
            Line width: 1.5
            Draw line: playStart, y0, playEnd, y1

            previousPlayEnd = playEnd
            previousY = y1
            havePrevious = 1
        endif
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text left: "yes", "Output order"
    Text bottom: "yes", "Source position (s)"

    # Process-panel title and compact direction key.
    Select outer viewport: 0.60, 7.70, 3.08, 3.36
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.50, "centre", 0.72, "half", "Read-head trajectory"
    Font size: 6
    Colour: "{0.35, 0.60, 0.40}"
    Text: 0.02, "left", 0.16, "half", "Forward"
    Colour: "{0.78, 0.28, 0.22}"
    if playback_mode = 2
        Text: 0.15, "left", 0.16, "half", "Reverse"
    else
        Text: 0.15, "left", 0.16, "half", "Back-step"
    endif

    # ----------------------------------------------------------
    # SUMMARY STRIP
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.73, 6.28
    Select inner viewport: 0.60, 7.70, 5.80, 6.22
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "{0.25, 0.25, 0.35}"
    Font size: 6
    Text: 0.02, "left", 0.67, "half",
        ... "##" + presetName$ + "##  |  " + modeName$
        ... + "  |  Segments: " + string$(segmentCount)
        ... + "  |  Changes/s: " + string$(direction_changes_per_second)
        ... + "  |  Forward ratio: " + fixed$(forward_ratio, 2)
    Text: 0.02, "left", 0.27, "half",
        ... "Back distance: " + fixed$(backward_distance_factor, 2)
        ... + "  |  Overlap: " + fixed$(effectiveOverlap * 1000, 2) + " ms"
        ... + "  |  In: " + fixed$(totalDuration, 2) + " s"
        ... + "  |  Out: " + fixed$(outputDuration, 2) + " s"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    removeObject: vizOriginal, vizResult

    # Full page must be active when Picture is copied/exported.
    Select outer viewport: 0, 8, 0, 6.35
    Select inner viewport: 0, 8, 0, 6.35
    Axes: 0, 8, 0, 6.35
    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Segments: ", segmentCount
appendInfoLine: "Duration: ", fixed$(outputDuration, 2), " s"

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result