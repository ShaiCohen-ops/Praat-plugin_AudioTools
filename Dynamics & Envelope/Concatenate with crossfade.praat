# ============================================================
# Praat AudioTools - Concatenate_with_crossfade.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Advanced concatenation with crossfade. Features include:
#   - Random/fixed chunk extraction from source sounds
#   - Multiple crossfade types (linear, equal-power, S-curve)
#   - Dynamic envelopes (crescendo, diminuendo, wave, random)
#   - Variable overlap times
#   - Comprehensive visualization
#
# Changelog v1.0:
#   - Added chunk extraction modes (whole, fixed, random)
#   - Added multiple crossfade types
#   - Added dynamic envelope options
#   - Added variable overlap time modes
#   - Added visualization
#   - Added presets
# ============================================================

form Advanced Concatenate with Crossfade v1.0
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Simple Crossfade (25%)
        option Smooth Collage (random chunks, equal-power)
        option Rhythmic Chop (short fixed chunks)
        option Cinematic Swell (crescendo-diminuendo)
        option Chaos Mix (random everything)
        option Granular Cloud (tiny random chunks)
    
    comment === Chunk Extraction ===
    optionmenu Chunk_mode 1
        option Whole file (use entire sound)
        option Fixed chunk size
        option Random chunk size
    positive Fixed_chunk_duration_s 2.0
    positive Min_chunk_duration_s 0.5
    positive Max_chunk_duration_s 3.0
    natural Chunks_per_file 1
    comment (How many chunks to extract from each file)
    
    comment === Order ===
    boolean Randomize_order 1
    boolean Allow_repeats 0
    comment (Allow same chunk to appear multiple times)
    
    comment === Crossfade Type ===
    optionmenu Crossfade_type 1
        option Linear (standard)
        option Equal-power (sqrt, no dip)
        option S-curve (cosine, smooth)
        option Exponential (fast start)
        option Logarithmic (fast end)
    
    comment === Crossfade Duration ===
    optionmenu Overlap_mode 1
        option Percentage of incoming chunk
        option Fixed duration
        option Random duration
    positive Overlap_percentage 25
    positive Fixed_overlap_s 0.5
    positive Min_overlap_s 0.1
    positive Max_overlap_s 1.0
    
    comment === Dynamics ===
    optionmenu Dynamics_mode 1
        option None (flat)
        option Crescendo (fade in)
        option Diminuendo (fade out)
        option Swell (cresc-dim)
        option Inverse swell (dim-cresc)
        option Wave (sine modulation)
        option Random per segment
        option Terraced (stepped levels)
    positive Wave_cycles 2
    positive Dynamics_depth_percent 80
    comment (How much dynamics affects amplitude, 0-100)
    
    comment === Output ===
    positive Scale_peak 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === INPUT VALIDATION ===
n = numberOfSelected("Sound")
if n < 1
    exitScript: "Please select at least 1 Sound object"
endif

# Store sound IDs and get sample rate
for i to n
    sound[i] = selected("Sound", i)
endfor

selectObject: sound[1]
sr = Get sampling frequency

# === APPLY PRESETS ===
if preset = 2
    # Simple Crossfade
    chunk_mode = 1
    chunks_per_file = 1
    randomize_order = 1
    crossfade_type = 1
    overlap_mode = 1
    overlap_percentage = 25
    dynamics_mode = 1
    presetName$ = "SimpleCrossfade"
elsif preset = 3
    # Smooth Collage
    chunk_mode = 3
    min_chunk_duration_s = 1.0
    max_chunk_duration_s = 4.0
    chunks_per_file = 2
    randomize_order = 1
    crossfade_type = 2
    overlap_mode = 1
    overlap_percentage = 30
    dynamics_mode = 1
    presetName$ = "SmoothCollage"
elsif preset = 4
    # Rhythmic Chop
    chunk_mode = 2
    fixed_chunk_duration_s = 0.5
    chunks_per_file = 3
    randomize_order = 1
    crossfade_type = 1
    overlap_mode = 2
    fixed_overlap_s = 0.05
    dynamics_mode = 1
    presetName$ = "RhythmicChop"
elsif preset = 5
    # Cinematic Swell
    chunk_mode = 1
    chunks_per_file = 1
    randomize_order = 0
    crossfade_type = 3
    overlap_mode = 1
    overlap_percentage = 20
    dynamics_mode = 4
    dynamics_depth_percent = 90
    presetName$ = "CinematicSwell"
elsif preset = 6
    # Chaos Mix
    chunk_mode = 3
    min_chunk_duration_s = 0.3
    max_chunk_duration_s = 2.5
    chunks_per_file = 3
    randomize_order = 1
    allow_repeats = 1
    crossfade_type = 3
    overlap_mode = 3
    min_overlap_s = 0.05
    max_overlap_s = 0.8
    dynamics_mode = 7
    dynamics_depth_percent = 60
    presetName$ = "ChaosMix"
elsif preset = 7
    # Granular Cloud
    chunk_mode = 3
    min_chunk_duration_s = 0.05
    max_chunk_duration_s = 0.3
    chunks_per_file = 10
    randomize_order = 1
    allow_repeats = 1
    crossfade_type = 2
    overlap_mode = 1
    overlap_percentage = 50
    dynamics_mode = 6
    wave_cycles = 3
    dynamics_depth_percent = 50
    presetName$ = "GranularCloud"
else
    presetName$ = "Custom"
endif

# === INFO HEADER ===
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  ADVANCED CONCATENATE WITH CROSSFADE v1.0"
writeInfoLine: "=============================================="
writeInfoLine: ""
writeInfoLine: "Input sounds: ", n
writeInfoLine: "Preset: ", presetName$
writeInfoLine: ""

# Get crossfade type name
if crossfade_type = 1
    crossfadeTypeName$ = "Linear"
elsif crossfade_type = 2
    crossfadeTypeName$ = "Equal-power"
elsif crossfade_type = 3
    crossfadeTypeName$ = "S-curve"
elsif crossfade_type = 4
    crossfadeTypeName$ = "Exponential"
else
    crossfadeTypeName$ = "Logarithmic"
endif

# Get dynamics mode name
if dynamics_mode = 1
    dynamicsName$ = "None"
elsif dynamics_mode = 2
    dynamicsName$ = "Crescendo"
elsif dynamics_mode = 3
    dynamicsName$ = "Diminuendo"
elsif dynamics_mode = 4
    dynamicsName$ = "Swell"
elsif dynamics_mode = 5
    dynamicsName$ = "Inverse Swell"
elsif dynamics_mode = 6
    dynamicsName$ = "Wave"
elsif dynamics_mode = 7
    dynamicsName$ = "Random"
else
    dynamicsName$ = "Terraced"
endif

writeInfoLine: "=== Settings ==="
writeInfoLine: "  Chunk mode: ", chunk_mode$
writeInfoLine: "  Chunks per file: ", chunks_per_file
writeInfoLine: "  Crossfade type: ", crossfadeTypeName$
writeInfoLine: "  Dynamics: ", dynamicsName$
writeInfoLine: ""

# ============================================================
# PROCEDURE: Extract chunk from sound
# ============================================================

procedure extractChunk: .sound, .mode, .fixedDur, .minDur, .maxDur
    selectObject: .sound
    .totalDur = Get total duration
    
    if .mode = 1
        # Whole file
        .chunkStart = 0
        .chunkEnd = .totalDur
    elsif .mode = 2
        # Fixed chunk
        .chunkDur = min(.fixedDur, .totalDur)
        .maxStart = .totalDur - .chunkDur
        if .maxStart > 0
            .chunkStart = randomUniform(0, .maxStart)
        else
            .chunkStart = 0
        endif
        .chunkEnd = .chunkStart + .chunkDur
    else
        # Random chunk
        .chunkDur = randomUniform(.minDur, .maxDur)
        .chunkDur = min(.chunkDur, .totalDur)
        .maxStart = .totalDur - .chunkDur
        if .maxStart > 0
            .chunkStart = randomUniform(0, .maxStart)
        else
            .chunkStart = 0
        endif
        .chunkEnd = .chunkStart + .chunkDur
    endif
    
    selectObject: .sound
    .chunk = Extract part: .chunkStart, .chunkEnd, "rectangular", 1, "no"
    
    extractChunk.result = .chunk
    extractChunk.duration = .chunkEnd - .chunkStart
    extractChunk.start = .chunkStart
    extractChunk.end = .chunkEnd
endproc


# ============================================================
# PROCEDURE: Apply custom crossfade
# ============================================================

procedure applyCrossfade: .sound, .fadeType, .duration, .direction$
    # .direction$ = "in" or "out"
    # .fadeType: 1=linear, 2=equal-power, 3=S-curve, 4=exp, 5=log
    
    selectObject: .sound
    .totalDur = Get total duration
    .sr = Get sampling frequency
    
    if .direction$ = "in"
        .startTime = 0
        .endTime = .duration
    else
        .startTime = .totalDur - .duration
        .endTime = .totalDur
    endif
    
    # Clamp times
    if .startTime < 0
        .startTime = 0
    endif
    if .endTime > .totalDur
        .endTime = .totalDur
    endif
    
    .fadeDur = .endTime - .startTime
    if .fadeDur < 0.001
        # Skip if too short
    else
        selectObject: .sound
        
        if .fadeType = 1
            # Linear fade (Praat's built-in)
            if .direction$ = "in"
                Fade in: 0, .startTime, .fadeDur, "yes"
            else
                Fade out: 0, .startTime, .fadeDur, "yes"
            endif
            
        elsif .fadeType = 2
            # Equal-power (sqrt curve) - prevents volume dip at crossfade center
            if .direction$ = "in"
                Formula (part): .startTime, .endTime, 1, 1, ~ self * sqrt((x - .startTime) / .fadeDur)
            else
                Formula (part): .startTime, .endTime, 1, 1, ~ self * sqrt(1 - (x - .startTime) / .fadeDur)
            endif
            
        elsif .fadeType = 3
            # S-curve (cosine) - very smooth
            if .direction$ = "in"
                Formula (part): .startTime, .endTime, 1, 1, ~ self * (0.5 - 0.5 * cos(pi * (x - .startTime) / .fadeDur))
            else
                Formula (part): .startTime, .endTime, 1, 1, ~ self * (0.5 + 0.5 * cos(pi * (x - .startTime) / .fadeDur))
            endif
            
        elsif .fadeType = 4
            # Exponential (fast start for fade-in, fast end for fade-out)
            if .direction$ = "in"
                Formula (part): .startTime, .endTime, 1, 1, ~ self * (1 - exp(-4 * (x - .startTime) / .fadeDur))
            else
                Formula (part): .startTime, .endTime, 1, 1, ~ self * exp(-4 * (x - .startTime) / .fadeDur)
            endif
            
        else
            # Logarithmic (slow start for fade-in, slow end for fade-out)
            if .direction$ = "in"
                Formula (part): .startTime, .endTime, 1, 1, ~ self * (ln(1 + 9 * (x - .startTime) / .fadeDur) / ln(10))
            else
                Formula (part): .startTime, .endTime, 1, 1, ~ self * (1 - ln(1 + 9 * (x - .startTime) / .fadeDur) / ln(10))
            endif
        endif
    endif
endproc


# ============================================================
# PROCEDURE: Calculate overlap time
# ============================================================

procedure calculateOverlap: .chunkDuration, .mode, .percentage, .fixedDur, .minDur, .maxDur
    if .mode = 1
        # Percentage of incoming chunk
        calculateOverlap.time = .chunkDuration * .percentage / 100
    elsif .mode = 2
        # Fixed duration
        calculateOverlap.time = .fixedDur
    else
        # Random duration
        calculateOverlap.time = randomUniform(.minDur, .maxDur)
    endif
    
    # Ensure overlap doesn't exceed chunk duration
    if calculateOverlap.time > .chunkDuration * 0.9
        calculateOverlap.time = .chunkDuration * 0.9
    endif
    
    # Minimum overlap
    if calculateOverlap.time < 0.01
        calculateOverlap.time = 0.01
    endif
endproc


# ============================================================
# EXTRACT ALL CHUNKS
# ============================================================

appendInfoLine: "Extracting chunks..."

totalChunks = 0

for i to n
    selectObject: sound[i]
    soundName$[i] = selected$("Sound")
    soundDur[i] = Get total duration
    
    for c to chunks_per_file
        totalChunks = totalChunks + 1
        
        @extractChunk: sound[i], chunk_mode, fixed_chunk_duration_s, min_chunk_duration_s, max_chunk_duration_s
        
        chunk[totalChunks] = extractChunk.result
        chunkDur[totalChunks] = extractChunk.duration
        chunkSource[totalChunks] = i
        chunkStart[totalChunks] = extractChunk.start
        chunkEnd[totalChunks] = extractChunk.end
        
        appendInfoLine: "  Chunk ", totalChunks, ": ", soundName$[i], " [", fixed$(chunkStart[totalChunks], 2), "-", fixed$(chunkEnd[totalChunks], 2), "s] (", fixed$(chunkDur[totalChunks], 2), "s)"
    endfor
endfor

appendInfoLine: ""
appendInfoLine: "Total chunks: ", totalChunks

if totalChunks < 2
    exitScript: "Need at least 2 chunks to concatenate"
endif

# ============================================================
# RANDOMIZE ORDER
# ============================================================

# Create order array
for i to totalChunks
    chunkOrder[i] = i
endfor

if randomize_order
    appendInfoLine: "Randomizing order..."
    
    for i to totalChunks
        j = randomInteger(1, totalChunks)
        temp = chunkOrder[i]
        chunkOrder[i] = chunkOrder[j]
        chunkOrder[j] = temp
    endfor
endif

# ============================================================
# CONCATENATE WITH CROSSFADE
# ============================================================

appendInfoLine: ""
appendInfoLine: "Concatenating with crossfade..."

# Start with first chunk
firstIdx = chunkOrder[1]
selectObject: chunk[firstIdx]
result = Copy: "crossfaded_temp"

# Track segment positions for dynamics
segmentStart[1] = 0
segmentEnd[1] = chunkDur[firstIdx]
segmentDur[1] = chunkDur[firstIdx]

totalOverlapTime = 0

for i from 2 to totalChunks
    currentIdx = chunkOrder[i]
    currentDur = chunkDur[currentIdx]
    
    # Calculate overlap time
    @calculateOverlap: currentDur, overlap_mode, overlap_percentage, fixed_overlap_s, min_overlap_s, max_overlap_s
    overlapTime = calculateOverlap.time
    
    totalOverlapTime = totalOverlapTime + overlapTime
    
    # Copy incoming chunk
    selectObject: chunk[currentIdx]
    incoming = Copy: "temp_incoming"
    
    # Apply fade out to result (end of current result)
    selectObject: result
    result_duration = Get total duration
    @applyCrossfade: result, crossfade_type, overlapTime, "out"
    
    # Apply fade in to incoming (start of incoming)
    selectObject: incoming
    @applyCrossfade: incoming, crossfade_type, overlapTime, "in"
    
    # Concatenate with overlap
    selectObject: result
    plusObject: incoming
    new_result = Concatenate with overlap: overlapTime
    
    # Track segment position
    segmentStart[i] = result_duration - overlapTime
    selectObject: new_result
    segmentEnd[i] = Get total duration
    segmentDur[i] = segmentEnd[i] - segmentStart[i]
    
    # Clean up
    removeObject: result, incoming
    result = new_result
    
    appendInfoLine: "  Added chunk ", i, "/", totalChunks, " (overlap: ", fixed$(overlapTime, 3), "s)"
endfor

selectObject: result
finalDuration = Get total duration

appendInfoLine: ""
appendInfoLine: "Concatenation complete"
appendInfoLine: "  Total duration: ", fixed$(finalDuration, 2), " s"
appendInfoLine: "  Total overlap: ", fixed$(totalOverlapTime, 2), " s"

# ============================================================
# APPLY DYNAMICS ENVELOPE
# ============================================================

if dynamics_mode > 1
    appendInfoLine: ""
    appendInfoLine: "Applying dynamics: ", dynamicsName$, "..."
    
    selectObject: result
    depth = dynamics_depth_percent / 100
    minAmp = 1 - depth
    
    if dynamics_mode = 2
        # Crescendo (fade in over entire duration)
        Formula: ~ self * (minAmp + (1 - minAmp) * x / finalDuration)
        
    elsif dynamics_mode = 3
        # Diminuendo (fade out over entire duration)
        Formula: ~ self * (1 - (1 - minAmp) * x / finalDuration)
        
    elsif dynamics_mode = 4
        # Swell (crescendo to middle, then diminuendo)
        Formula: ~ self * (minAmp + (1 - minAmp) * (1 - abs(2 * x / finalDuration - 1)))
        
    elsif dynamics_mode = 5
        # Inverse swell (diminuendo to middle, then crescendo)
        Formula: ~ self * (1 - (1 - minAmp) * (1 - abs(2 * x / finalDuration - 1)))
        
    elsif dynamics_mode = 6
        # Wave (sine modulation)
        Formula: ~ self * (minAmp + (1 - minAmp) * (0.5 + 0.5 * sin(2 * pi * wave_cycles * x / finalDuration - pi/2)))
        
    elsif dynamics_mode = 7
        # Random per segment
        for seg to totalChunks
            segAmp[seg] = randomUniform(minAmp, 1)
        endfor
        
        # Apply per-segment amplitude with small crossfade between segments
        for seg to totalChunks
            sStart = segmentStart[seg]
            sEnd = segmentEnd[seg]
            amp = segAmp[seg]
            
            if seg < totalChunks
                # Fade to next segment's amplitude
                nextAmp = segAmp[seg + 1]
                fadeZone = min(0.1, (sEnd - sStart) * 0.2)
                
                selectObject: result
                # Main segment
                if sEnd - fadeZone > sStart
                    Formula (part): sStart, sEnd - fadeZone, 1, 1, ~ self * amp
                endif
                # Transition zone
                Formula (part): sEnd - fadeZone, sEnd, 1, 1, ~ self * (amp + (nextAmp - amp) * (x - (sEnd - fadeZone)) / fadeZone)
            else
                selectObject: result
                Formula (part): sStart, sEnd, 1, 1, ~ self * amp
            endif
        endfor
        
    elsif dynamics_mode = 8
        # Terraced (stepped levels)
        numSteps = min(totalChunks, 5)
        for seg to totalChunks
            stepNum = ((seg - 1) mod numSteps) + 1
            segAmp[seg] = minAmp + (1 - minAmp) * (stepNum - 1) / (numSteps - 1)
        endfor
        
        for seg to totalChunks
            sStart = segmentStart[seg]
            sEnd = segmentEnd[seg]
            amp = segAmp[seg]
            
            selectObject: result
            Formula (part): sStart, sEnd, 1, 1, ~ self * amp
        endfor
    endif
    
    appendInfoLine: "  Dynamics applied (depth: ", fixed$(dynamics_depth_percent, 0), "%)"
endif

# ============================================================
# FINAL PROCESSING
# ============================================================

selectObject: result
Scale peak: scale_peak
Rename: "concat_crossfade_" + presetName$

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Creating visualization..."
    
    Erase all
    
    # === TITLE ===
    Select outer viewport: 0, 10, 0, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Concatenate with Crossfade v1.0## | " + presetName$ + " | " + string$(totalChunks) + " chunks"
    
    # === RESULT WAVEFORM ===
    Select outer viewport: 0, 10, 0.6, 2.5
    Select inner viewport: 0.6, 9.6, 0.8, 2.3
    
    selectObject: result
    Colour: "{0.3, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    # Draw segment boundaries
    Colour: "{0.8, 0.3, 0.3}"
    Line width: 1
    Dashed line
    for seg from 2 to totalChunks
        xPos = segmentStart[seg]
        Draw line: xPos, -1, xPos, 1
    endfor
    Solid line
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    
    Font size: 8
    Text left: "yes", "Result"
    Text bottom: "yes", "Time (s)"
    
    # === SEGMENT MAP ===
    Select outer viewport: 0, 10, 2.6, 3.8
    Select inner viewport: 0.6, 9.6, 2.8, 3.6
    
    Axes: 0, finalDuration, 0, 1
    
    # Draw each segment as colored bar
    for seg to totalChunks
        sStart = segmentStart[seg]
        sEnd = segmentEnd[seg]
        sourceIdx = chunkSource[chunkOrder[seg]]
        
        # Color based on source file
        hue = (sourceIdx - 1) / n
        r = 0.4 + 0.5 * sin(2 * pi * hue)
        g = 0.4 + 0.5 * sin(2 * pi * hue + 2 * pi / 3)
        b = 0.4 + 0.5 * sin(2 * pi * hue + 4 * pi / 3)
        
        colour$ = "{" + fixed$(r, 2) + "," + fixed$(g, 2) + "," + fixed$(b, 2) + "}"
        Paint rectangle: colour$, sStart, sEnd, 0.1, 0.9
        
        # Segment number
        Colour: "White"
        Font size: 6
        midX = (sStart + sEnd) / 2
        if sEnd - sStart > finalDuration * 0.03
            Text: midX, "centre", 0.5, "half", string$(seg)
        endif
    endfor
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    
    Font size: 8
    Text left: "yes", "Segments"
    
    # === DYNAMICS ENVELOPE ===
    if dynamics_mode > 1
        Select outer viewport: 0, 10, 3.9, 5.0
        Select inner viewport: 0.6, 9.6, 4.1, 4.8
        
        Axes: 0, finalDuration, 0, 1.2
        
        # Background
        Paint rectangle: "{0.95, 0.95, 0.95}", 0, finalDuration, 0, 1.2
        
        # Draw envelope
        Colour: "{0.8, 0.4, 0.2}"
        Line width: 2
        
        minAmp = 1 - dynamics_depth_percent / 100
        numPoints = 200
        step = finalDuration / numPoints
        
        prevX = 0
        
        if dynamics_mode = 2
            prevY = minAmp
        elsif dynamics_mode = 3
            prevY = 1
        elsif dynamics_mode = 4
            prevY = minAmp
        elsif dynamics_mode = 5
            prevY = 1
        elsif dynamics_mode = 6
            prevY = minAmp
        elsif dynamics_mode = 7 or dynamics_mode = 8
            prevY = segAmp[1]
        else
            prevY = 1
        endif
        
        for pt from 1 to numPoints
            x = pt * step
            
            if dynamics_mode = 2
                y = minAmp + (1 - minAmp) * x / finalDuration
            elsif dynamics_mode = 3
                y = 1 - (1 - minAmp) * x / finalDuration
            elsif dynamics_mode = 4
                y = minAmp + (1 - minAmp) * (1 - abs(2 * x / finalDuration - 1))
            elsif dynamics_mode = 5
                y = 1 - (1 - minAmp) * (1 - abs(2 * x / finalDuration - 1))
            elsif dynamics_mode = 6
                y = minAmp + (1 - minAmp) * (0.5 + 0.5 * sin(2 * pi * wave_cycles * x / finalDuration - pi/2))
            elsif dynamics_mode = 7 or dynamics_mode = 8
                # Find current segment
                for seg to totalChunks
                    if x >= segmentStart[seg] and x <= segmentEnd[seg]
                        y = segAmp[seg]
                    endif
                endfor
            else
                y = 1
            endif
            
            Draw line: prevX, prevY, x, y
            prevX = x
            prevY = y
        endfor
        
        # Unity reference
        Colour: "{0.6, 0.6, 0.6}"
        Line width: 1
        Dashed line
        Draw line: 0, 1, finalDuration, 1
        Solid line
        
        Colour: "Black"
        Line width: 1
        Draw inner box
        
        Font size: 8
        Text left: "yes", "Dynamics"
    endif
    
    # === LEGEND / INFO ===
    Select outer viewport: 0, 10, 5.1, 5.8
    Axes: 0, 1, 0, 1
    
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    
    # Source file legend
    for i to min(n, 6)
        hue = (i - 1) / n
        r = 0.4 + 0.5 * sin(2 * pi * hue)
        g = 0.4 + 0.5 * sin(2 * pi * hue + 2 * pi / 3)
        b = 0.4 + 0.5 * sin(2 * pi * hue + 4 * pi / 3)
        colour$ = "{" + fixed$(r, 2) + "," + fixed$(g, 2) + "," + fixed$(b, 2) + "}"
        
        xPos = 0.02 + (i - 1) * 0.16
        Paint rectangle: colour$, xPos, xPos + 0.02, 0.6, 0.9
        
        Colour: "{0.3, 0.3, 0.3}"
        # Truncate name if too long
        dispName$ = left$(soundName$[i], 12)
        Text: xPos + 0.025, "left", 0.75, "half", dispName$
    endfor
    
    # Parameters
    Colour: "{0.5, 0.5, 0.5}"
    Text: 0.02, "left", 0.25, "half", "Crossfade: " + crossfadeTypeName$ + " | Dynamics: " + dynamicsName$ + " | Chunks: " + string$(totalChunks) + " | Duration: " + fixed$(finalDuration, 1) + "s"
    
    Font size: 10
    Colour: "Black"
endif

# ============================================================
# CLEANUP
# ============================================================

for i to totalChunks
    removeObject: chunk[i]
endfor

selectObject: result

# ============================================================
# OUTPUT
# ============================================================

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(finalDuration, 2), " s"
appendInfoLine: "Chunks: ", totalChunks
appendInfoLine: "Crossfade type: ", crossfadeTypeName$
appendInfoLine: "Dynamics: ", dynamicsName$
appendInfoLine: ""

if play_result
    appendInfoLine: "Playing..."
    Play
endif

selectObject: result