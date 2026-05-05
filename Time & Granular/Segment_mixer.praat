# ============================================================
# Praat AudioTools - Segment_Mixer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Segment Mixer - creates stereo composites from multiple
#   selected Sound objects. LEFT channel uses beginning segments,
#   RIGHT channel uses end/offset/random segments. Supports
#   multiple repeat cycles for longer compositions.
#
# Changelog v0.2:
#   - Fixed header
#   - Added presets
#   - Added visualization
# ============================================================

form Segment Mixer
    comment Select multiple Sound objects first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom
        option Quick Collage (short segments)
        option Slow Morph (long segments)
        option Random Scatter
        option Stereo Spread (L=start, R=end)
        option Dense Layers (many cycles)
    
    comment === Segment ===
    positive Segment_duration_s 0.25
    real Fade_time_s 0.05
    positive Attenuation_divisor 1.1
    integer Repeat_cycles 3
    
    comment === Right Channel Strategy ===
    optionmenu Right_part_strategy 1
        option End of file
        option Fixed offset
        option Random
    real Right_fixed_offset_s 0.10
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Quick Collage
    segment_duration_s = 0.15
    fade_time_s = 0.03
    attenuation_divisor = 1.2
    repeat_cycles = 4
    right_part_strategy = 3
    right_fixed_offset_s = 0.1
elsif preset = 3
    # Slow Morph
    segment_duration_s = 0.5
    fade_time_s = 0.1
    attenuation_divisor = 1.0
    repeat_cycles = 2
    right_part_strategy = 1
    right_fixed_offset_s = 0.1
elsif preset = 4
    # Random Scatter
    segment_duration_s = 0.2
    fade_time_s = 0.04
    attenuation_divisor = 1.3
    repeat_cycles = 5
    right_part_strategy = 3
    right_fixed_offset_s = 0.1
elsif preset = 5
    # Stereo Spread
    segment_duration_s = 0.3
    fade_time_s = 0.05
    attenuation_divisor = 1.1
    repeat_cycles = 3
    right_part_strategy = 1
    right_fixed_offset_s = 0.1
elsif preset = 6
    # Dense Layers
    segment_duration_s = 0.1
    fade_time_s = 0.02
    attenuation_divisor = 1.5
    repeat_cycles = 8
    right_part_strategy = 3
    right_fixed_offset_s = 0.1
endif

# === Input Validation ===
numberOfSelectedSounds = numberOfSelected("Sound")

if numberOfSelectedSounds = 0
    exitScript: "Please select some Sound objects first."
endif
if numberOfSelectedSounds < 2
    exitScript: "Please select at least two Sound objects."
endif
if fade_time_s <= 0
    exitScript: "Fade time must be positive."
endif
if fade_time_s > segment_duration_s / 2
    exitScript: "Fade time cannot exceed half the segment duration."
endif
if repeat_cycles < 1
    exitScript: "Repeat cycles must be at least 1."
endif
if right_part_strategy = 2 and right_fixed_offset_s < 0
    exitScript: "Right fixed offset must be >= 0."
endif

# === Get Strategy Name ===
if right_part_strategy = 1
    strategyName$ = "End"
elsif right_part_strategy = 2
    strategyName$ = "Offset"
else
    strategyName$ = "Random"
endif

# === Info ===
writeInfoLine: "=== Segment Mixer ==="
appendInfoLine: "Files: ", numberOfSelectedSounds
appendInfoLine: "Segment: ", fixed$(segment_duration_s, 3), " s"
appendInfoLine: "Cycles: ", repeat_cycles
appendInfoLine: "R strategy: ", strategyName$
appendInfoLine: ""

# === Store Original Selection ===
originalSounds# = selected#("Sound")

# === Convert All to Mono ===
monoSounds# = zero#(numberOfSelectedSounds)
soundNames$# = empty$#(numberOfSelectedSounds)

for i to numberOfSelectedSounds
    selectObject: originalSounds#[i]
    soundNames$#[i] = selected$("Sound")
    numChannels = Get number of channels
    
    Copy: "mono_work_" + string$(i)
    workID = selected("Sound")
    
    if numChannels > 1
        Convert to mono
        monoID = selected("Sound")
        removeObject: workID
        monoSounds#[i] = monoID
    else
        monoSounds#[i] = workID
    endif
endfor

# === Normalise Sampling Frequency ===
# Use the first sound's sampling frequency as the target for all sounds and buffers.
selectObject: monoSounds#[1]
targetSR = Get sampling frequency

for i to numberOfSelectedSounds
    selectObject: monoSounds#[i]
    sr_i = Get sampling frequency
    if sr_i <> targetSR
        Resample: targetSR, 50
        resampledID = selected("Sound")
        removeObject: monoSounds#[i]
        monoSounds#[i] = resampledID
        selectObject: monoSounds#[i]
        Rename: "mono_work_" + string$(i)
    endif
endfor

appendInfoLine: "Target sampling frequency: ", fixed$(targetSR, 0), " Hz"
appendInfoLine: "Processing files:"
for i to numberOfSelectedSounds
    selectObject: monoSounds#[i]
    dur = Get total duration
    appendInfoLine: "  ", i, ": ", soundNames$#[i], " (", fixed$(dur, 2), " s)"
endfor
appendInfoLine: ""

# === Create Initial Buffers ===
Create Sound from formula: "temp_left", 1, 0, 0.01, targetSR, "0"
leftID = selected("Sound")

Create Sound from formula: "temp_right", 1, 0, 0.01, targetSR, "0"
rightID = selected("Sound")

# === Store Segment Info for Visualization ===
maxSegments = numberOfSelectedSounds * repeat_cycles
leftStarts# = zero#(maxSegments)
leftEnds# = zero#(maxSegments)
rightStarts# = zero#(maxSegments)
rightEnds# = zero#(maxSegments)
segmentFile# = zero#(maxSegments)
segmentIdx = 0

# === Main Processing Loop ===
appendInfoLine: "Building composite..."

for cycle to repeat_cycles
    for i to numberOfSelectedSounds
        selectObject: monoSounds#[i]
        total_duration = Get total duration
        
        # Determine extract duration
        if segment_duration_s > total_duration
            extractDuration = total_duration
        else
            extractDuration = segment_duration_s
        endif
        
        # === LEFT SEGMENT (from start) ===
        leftStart = 0
        leftEnd = leftStart + extractDuration
        if leftEnd > total_duration
            leftEnd = total_duration
        endif
        
        Extract part: leftStart, leftEnd, "rectangular", 1, "no"
        leftSeg = selected("Sound")
        
        # Apply fades and attenuation
        selectObject: leftSeg
        if extractDuration > 2 * fade_time_s
            Formula: "self / attenuation_divisor"
            Formula: "self * min(1, x / fade_time_s)"
            Formula: "self * min(1, (xmax - x) / fade_time_s)"
        else
            Formula: "self / attenuation_divisor"
        endif
        
        # Concatenate to left channel
        selectObject: leftID, leftSeg
        Concatenate
        newLeft = selected("Sound")
        removeObject: leftID, leftSeg
        leftID = newLeft
        selectObject: leftID
        Rename: "temp_left"
        
        # === RIGHT SEGMENT (based on strategy) ===
        if right_part_strategy = 1
            # End of file
            rightEnd = total_duration
            rightStart = rightEnd - extractDuration
            if rightStart < 0
                rightStart = 0
            endif
        elsif right_part_strategy = 2
            # Fixed offset
            rightStart = right_fixed_offset_s
            if rightStart > total_duration - extractDuration
                rightStart = total_duration - extractDuration
            endif
            if rightStart < 0
                rightStart = 0
            endif
        else
            # Random
            usableWindow = total_duration - extractDuration
            if usableWindow <= 0
                rightStart = 0
            else
                rightStart = randomUniform(0, usableWindow)
            endif
        endif
        
        rightEnd = rightStart + extractDuration
        if rightEnd > total_duration
            rightEnd = total_duration
            rightStart = rightEnd - extractDuration
            if rightStart < 0
                rightStart = 0
            endif
        endif
        
        selectObject: monoSounds#[i]
        Extract part: rightStart, rightEnd, "rectangular", 1, "no"
        rightSeg = selected("Sound")
        
        # Apply fades and attenuation
        selectObject: rightSeg
        if extractDuration > 2 * fade_time_s
            Formula: "self / attenuation_divisor"
            Formula: "self * min(1, x / fade_time_s)"
            Formula: "self * min(1, (xmax - x) / fade_time_s)"
        else
            Formula: "self / attenuation_divisor"
        endif
        
        # Concatenate to right channel
        selectObject: rightID, rightSeg
        Concatenate
        newRight = selected("Sound")
        removeObject: rightID, rightSeg
        rightID = newRight
        selectObject: rightID
        Rename: "temp_right"
        
        # Store for visualization
        segmentIdx += 1
        leftStarts#[segmentIdx] = leftStart
        leftEnds#[segmentIdx] = leftEnd
        rightStarts#[segmentIdx] = rightStart
        rightEnds#[segmentIdx] = rightEnd
        segmentFile#[segmentIdx] = i
    endfor
    
    appendInfoLine: "  Cycle ", cycle, " complete"
endfor

totalSegments = segmentIdx

# === Finalize ===
selectObject: leftID
Scale peak: 0.99

selectObject: rightID
Scale peak: 0.99

selectObject: leftID, rightID
Combine to stereo
result = selected("Sound")

compositeName$ = "stereo_mix_" + string$(numberOfSelectedSounds) + "files_" + string$(repeat_cycles) + "x"
Rename: compositeName$

selectObject: result
finalDuration = Get total duration

# === Cleanup ===
removeObject: leftID, rightID

for i to numberOfSelectedSounds
    if monoSounds#[i] > 0
        removeObject: monoSounds#[i]
    endif
endfor

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 1, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Segment Mixer: " + string$(numberOfSelectedSounds) + " files × " + string$(repeat_cycles) + " cycles"
    
    # Result waveform (stereo)
    Select outer viewport: 0, 8, 0.6, 2.2
    Select inner viewport: 0.6, 7.6, 0.7, 2.1
    selectObject: result
    Colour: "{0.3, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"
    
    # Segment map - Left channel
    Select outer viewport: 0, 8, 2.4, 3.6
    Select inner viewport: 0.6, 7.6, 2.5, 3.5
    
    Axes: 0, totalSegments, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, totalSegments, 0, 1
    
    # Draw left segments
    for s to totalSegments
        fileIdx = segmentFile#[s]
        
        # Safety check
        if fileIdx >= 1 and fileIdx <= numberOfSelectedSounds
            # Color by file index
            hue = (fileIdx - 1) / max(1, numberOfSelectedSounds - 1)
            r = 0.3 + 0.5 * sin(hue * 2 * pi)
            g = 0.3 + 0.5 * sin(hue * 2 * pi + 2)
            b = 0.3 + 0.5 * sin(hue * 2 * pi + 4)
            barColor$ = "{" + fixed$(r, 2) + ", " + fixed$(g, 2) + ", " + fixed$(b, 2) + "}"
            
            # Draw bar
            Paint rectangle: barColor$, s - 0.9, s - 0.1, 0.1, 0.9
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "L (start)"
    
    # Segment map - Right channel
    Select outer viewport: 0, 8, 3.7, 4.9
    Select inner viewport: 0.6, 7.6, 3.8, 4.8
    
    Axes: 0, totalSegments, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, totalSegments, 0, 1
    
    # Draw right segments
    for s to totalSegments
        fileIdx = segmentFile#[s]
        
        # Safety check
        if fileIdx >= 1 and fileIdx <= numberOfSelectedSounds
            # Color by file index
            hue = (fileIdx - 1) / max(1, numberOfSelectedSounds - 1)
            r = 0.3 + 0.5 * sin(hue * 2 * pi)
            g = 0.3 + 0.5 * sin(hue * 2 * pi + 2)
            b = 0.3 + 0.5 * sin(hue * 2 * pi + 4)
            barColor$ = "{" + fixed$(r, 2) + ", " + fixed$(g, 2) + ", " + fixed$(b, 2) + "}"
            
            Paint rectangle: barColor$, s - 0.9, s - 0.1, 0.1, 0.9
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "R (" + strategyName$ + ")"
    Text bottom: "yes", "Segment #"
    
    # File legend
    Select outer viewport: 0, 8, 5.1, 5.8
    Select inner viewport: 0.6, 7.6, 5.2, 5.7
    
    Axes: 0, numberOfSelectedSounds, 0, 1
    
    for i to numberOfSelectedSounds
        hue = (i - 1) / max(1, numberOfSelectedSounds - 1)
        r = 0.3 + 0.5 * sin(hue * 2 * pi)
        g = 0.3 + 0.5 * sin(hue * 2 * pi + 2)
        b = 0.3 + 0.5 * sin(hue * 2 * pi + 4)
        barColor$ = "{" + fixed$(r, 2) + ", " + fixed$(g, 2) + ", " + fixed$(b, 2) + "}"
        
        Paint rectangle: barColor$, i - 0.9, i - 0.1, 0.2, 0.8
        
        # File number label only (names were removed with objects)
        Colour: "Black"
        Font size: 6
        Text: i - 0.5, "centre", 0.1, "bottom", "File " + string$(i)
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Files"
    
    # Stats
    Select outer viewport: 0, 8, 5.9, 6.2
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Segments: " + string$(totalSegments) + " | Duration: " + fixed$(finalDuration, 2) + "s | Fade: " + fixed$(fade_time_s * 1000, 0) + "ms"
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", compositeName$
appendInfoLine: "Duration: ", fixed$(finalDuration, 2), " s"
appendInfoLine: "Segments: ", totalSegments

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result