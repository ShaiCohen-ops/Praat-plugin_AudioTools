# ============================================================
# Praat AudioTools - ZigZag_Effect.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   ZigZag Effect - creates zigzag time manipulation by moving
#   forward and backward through the audio timeline. Two modes:
#   Stutter (always play forward) creates rhythmic repetition,
#   Scrub (reverse when moving back) creates tape manipulation.
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

while currentPosition < totalDuration and segmentCount < maxSegments
    segmentCount += 1
    
    # === Determine Segment ===
    if direction = 1
        # FORWARD SEGMENT
        var = randomUniform(1.0 - segment_duration_variation, 1.0 + segment_duration_variation)
        currentSegDuration = segment_duration * var
        
        startTime = currentPosition
        endTime = currentPosition + currentSegDuration
        
        if endTime > totalDuration
            endTime = totalDuration
        endif
        
        # Extract
        selectObject: original
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
        var = randomUniform(1.0 - segment_duration_variation, 1.0 + segment_duration_variation)
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
        selectObject: original
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
    
    # === Amplitude Jitter ===
    selectObject: grain
    ampFactor = randomUniform(1.0 - amplitude_variation, 1.0 + amplitude_variation)
    Formula: ~ self * ampFactor
    
    # === Store grain for batched concatenation ===
    grainID[segmentCount] = grain
    
    # Progress
    if segmentCount mod 100 = 0
        perc = round((currentPosition / totalDuration) * 100)
        appendInfoLine: "  Segment ", segmentCount, " (", perc, "%)"
    endif
endwhile

# === Batched Concatenation (single pass; equivalent to pairwise) ===
if segmentCount = 1
    masterID = grainID[1]
else
    selectObject: grainID[1]
    for i from 2 to segmentCount
        plusObject: grainID[i]
    endfor
    if segment_overlap_s > 0
        masterID = Concatenate with overlap: segment_overlap_s
    else
        masterID = Concatenate
    endif
    for i from 1 to segmentCount
        removeObject: grainID[i]
    endfor
endif

# === Finalize ===
selectObject: masterID
Rename: soundName$ + "_zigzag_" + modeName$
Scale peak: scale_peak
result = selected("Sound")

selectObject: result
outputDuration = Get total duration

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "ZigZag Effect: " + soundName$ + " (" + presetName$ + ", " + modeName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 2.0
    Select inner viewport: 0.6, 7.6, 0.7, 1.9
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 2.1, 3.5
    Select inner viewport: 0.6, 7.6, 2.2, 3.4
    selectObject: result
    Colour: "{0.6, 0.5, 0.4}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "ZigZag"
    Text bottom: "yes", "Time (s)"
    
    # Segment pattern visualization
    Select outer viewport: 0, 8, 3.7, 5.3
    Select inner viewport: 0.6, 7.6, 3.9, 5.2
    
    # Limit display to first 200 segments for clarity
    displaySegs = min(segmentCount, 200)
    
    Axes: 0, totalDuration, 0, displaySegs + 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, totalDuration, 0, displaySegs + 1
    
    # Draw zigzag path
    for seg to displaySegs
        startT = segStarts#[seg]
        endT = segEnds#[seg]
        dir = segDirections#[seg]
        
        # Color: forward=blue, backward=red
        if dir = 1
            segColor$ = "{0.3, 0.5, 0.8}"
        else
            segColor$ = "{0.8, 0.4, 0.3}"
        endif
        
        # Draw segment bar
        Paint rectangle: segColor$, startT, endT, seg - 0.4, seg + 0.4
        
        # Draw connecting line to next segment
        if seg < displaySegs
            nextStart = segStarts#[seg + 1]
            Colour: "{0.5, 0.5, 0.5}"
            Draw line: (startT + endT) / 2, seg, nextStart, seg + 1
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Segment #"
    Text bottom: "yes", "Source position (s)"
    
    # Legend
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.3, 0.5, 0.8}"
    Text: 0.02, "left", 0.97, "half", "Forward"
    Colour: "{0.8, 0.4, 0.3}"
    Text: 0.20, "left", 0.97, "half", "Backward"
    
    # Stats
    Select outer viewport: 0, 8, 5.4, 5.7
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Segments: " + string$(segmentCount) + " | Changes/s: " + string$(direction_changes_per_second) + " | Duration: " + fixed$(outputDuration, 2) + "s"
    
    Font size: 10
    Colour: "Black"
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