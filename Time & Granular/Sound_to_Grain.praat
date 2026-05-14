# ============================================================
# Praat AudioTools - Sound_to_Grain.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Sound to Grain - extracts random grains from audio and
#   concatenates them. Supports true stereo independence with
#   multiple modes: different positions, shuffled order, or
#   time offset between L/R channels.
#
# Features:
#   - Mono and stereo input support
#   - 5 output modes including TRUE independent L/R
#   - Random position, shuffled order, or time-offset independence
#   - Per-channel reversal control
#   - Multiple window shapes
#   - Visualization with grain maps
#
# Categories: Granular Processing, Sound Transformation, Experimental
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline
#   Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v2.1:
#   - CRITICAL FIX: Fisher-Yates shuffle for mode 4 ("Stereo
#     Shuffle"). v2.0 used `for i from number_of_grains to 2
#     by -1` — Praat does NOT support `by` clauses in for-loops
#     (always increments by 1). The shuffle silently failed
#     (either parse error or no-op), leaving grainOrder as the
#     identity ordering [1,2,...,N]. Mode 4 effectively played
#     the right channel in the SAME order as the left, with
#     only the reversal pattern differing. v2.1 uses ascending
#     Fisher-Yates which produces a genuine random permutation.
#   - Audio output is bit-identical to v2.0 for modes 1, 2, 3,
#     and 5. For mode 4, audio CHANGES (it now actually shuffles
#     the right channel order, which is the documented intent).
#   - Dropped 6 decorative form lines (5 `comment === ... ===`
#     section dividers, 1 inline parenthetical hint). Form went
#     from 18 effective rows to 12.
#   - Visualization rewritten to suite 8x8 standard (v2.0 was
#     10x5.8 with 4 panels at extra width):
#       Title bar + metadata subtitle (preset, mode, grains x
#         length, reversals)
#       Panel A (left, headline): L/R grain map (stereo) or
#         single grain map (mono) — PRESERVED v2.0 design,
#         color-coded by reversal status
#       Panel B (right, headline): parameter report with mode,
#         grain settings, reversal stats, output stats
#       Panel C: zoom overlay (first 500 ms, gray = original,
#         blue = result, SHARED y-axis)
#       Panel D: full waveform comparison (gray = original,
#         blue = result, SHARED y-axis) — fixes v2.0's
#         independent auto-scaling
#       Panel E: light-grey summary stats bar (suite standard)
#   - Final `selectObject: result` instead of v2.0's
#     `selectObject: original` — suite-consistency. The result
#     Sound is selected at script end so it's visible/playable.
# Changelog v2.0:
#   - Fixed stereo independence (was only reversing differently)
#   - Added 3 independence modes: Random, Shuffled, Offset
#   - Proper stereo input preservation
#   - Better visualization showing L vs R grains
# ============================================================

form Sound to Grain v2.1
    optionmenu Preset: 1
        option Custom
        option Quick Texture (few grains)
        option Dense Cloud (many grains)
        option Micro Grains (short, choppy)
        option Long Segments (ambient)
        option Stereo Scatter (random positions)
        option Stereo Shuffle (different order)
    positive Number_of_grains 20
    positive Grain_length_s 0.3
    optionmenu Window_type: 1
        option Hanning
        option Rectangular
        option Triangular
    optionmenu Output_mode: 1
        option Mono
        option Stereo (same grains L/R)
        option Stereo (independent - random positions)
        option Stereo (independent - shuffled order)
        option Stereo (independent - time offset)
    positive Time_offset_s 0.1
    boolean Enable_reversal 0
    positive Left_reversal_percent 50
    positive Right_reversal_percent 50
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Quick Texture
    number_of_grains = 15
    grain_length_s = 0.2
    window_type = 1
    output_mode = 1
    enable_reversal = 0
    presetName$ = "QuickTexture"
elsif preset = 3
    # Dense Cloud
    number_of_grains = 50
    grain_length_s = 0.15
    window_type = 1
    output_mode = 1
    enable_reversal = 1
    left_reversal_percent = 30
    right_reversal_percent = 30
    presetName$ = "DenseCloud"
elsif preset = 4
    # Micro Grains
    number_of_grains = 80
    grain_length_s = 0.05
    window_type = 2
    output_mode = 1
    enable_reversal = 0
    presetName$ = "MicroGrains"
elsif preset = 5
    # Long Segments
    number_of_grains = 10
    grain_length_s = 0.8
    window_type = 1
    output_mode = 1
    enable_reversal = 0
    presetName$ = "LongSegments"
elsif preset = 6
    # Stereo Scatter (random positions)
    number_of_grains = 25
    grain_length_s = 0.25
    window_type = 1
    output_mode = 3
    enable_reversal = 1
    left_reversal_percent = 40
    right_reversal_percent = 60
    presetName$ = "StereoScatter"
elsif preset = 7
    # Stereo Shuffle
    number_of_grains = 30
    grain_length_s = 0.2
    window_type = 1
    output_mode = 4
    enable_reversal = 1
    left_reversal_percent = 30
    right_reversal_percent = 70
    presetName$ = "StereoShuffle"
else
    presetName$ = "Custom"
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

original = selected("Sound")
soundName$ = selected$("Sound")

selectObject: original
totalDuration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels

# === Validate Parameters ===
if grain_length_s > totalDuration
    exitScript: "Grain length (" + fixed$(grain_length_s, 2) + "s) exceeds sound duration (" + fixed$(totalDuration, 2) + "s)"
endif

# === Get Window Shape ===
if window_type = 1
    windowShape$ = "Hanning"
elsif window_type = 2
    windowShape$ = "rectangular"
else
    windowShape$ = "triangular"
endif

# === Mode label ===
if output_mode = 1
    modeLabel$ = "Mono"
elsif output_mode = 2
    modeLabel$ = "Stereo (same L/R)"
elsif output_mode = 3
    modeLabel$ = "Stereo (random pos)"
elsif output_mode = 4
    modeLabel$ = "Stereo (shuffled)"
else
    modeLabel$ = "Stereo (offset " + fixed$(time_offset_s * 1000, 0) + " ms)"
endif

# === Prepare Source Sound ===
# For stereo input, extract L channel for processing
selectObject: original
if numChannels > 1
    Extract left channel
    sourceSound = selected("Sound")
else
    Copy: "source_temp"
    sourceSound = selected("Sound")
endif

# === Info ===
clearinfo
writeInfoLine: "=== Sound to Grain v2.1 ==="
appendInfoLine: "Source: ", soundName$, " (", fixed$(totalDuration, 2), " s)"
appendInfoLine: "Input:  ", numChannels, " channel(s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Grains: ", number_of_grains, " x ", fixed$(grain_length_s * 1000, 0), " ms"
appendInfoLine: "Window: ", windowShape$
appendInfoLine: "Output: ", modeLabel$

if enable_reversal
    appendInfoLine: "Reversal: L=", left_reversal_percent, "% R=", right_reversal_percent, "%"
endif
appendInfoLine: ""

# === Arrays ===
leftGrainIDs# = zero#(number_of_grains)
rightGrainIDs# = zero#(number_of_grains)
leftGrainStarts# = zero#(number_of_grains)
rightGrainStarts# = zero#(number_of_grains)
leftReversed# = zero#(number_of_grains)
rightReversed# = zero#(number_of_grains)
grainOrder# = zero#(number_of_grains)

# Initialize grain order
for i to number_of_grains
    grainOrder#[i] = i
endfor

# Shuffle order for mode 4
# v2.1 CRITICAL FIX: ascending Fisher-Yates (v2.0 used
# `for i from N to 2 by -1` which is invalid Praat — the loop
# silently failed and grainOrder stayed as identity, causing
# mode 4 to NOT actually shuffle).
if output_mode = 4
    for i from 1 to number_of_grains - 1
        j = randomInteger(i, number_of_grains)
        temp = grainOrder#[i]
        grainOrder#[i] = grainOrder#[j]
        grainOrder#[j] = temp
    endfor
endif

grainCount = 0
maxStart = totalDuration - grain_length_s

if maxStart <= 0
    exitScript: "Sound too short for grain length"
endif

# === Extract Grains ===
appendInfoLine: "Extracting grains..."

for grain from 1 to number_of_grains
    grainCount = grain
    
    # LEFT CHANNEL GRAIN
    leftStartTime = randomUniform(0, maxStart)
    leftEndTime = leftStartTime + grain_length_s
    leftGrainStarts#[grainCount] = leftStartTime
    
    selectObject: sourceSound
    Extract part: leftStartTime, leftEndTime, windowShape$, 1, "no"
    leftGrain = selected("Sound")
    
    # Reverse left?
    if enable_reversal and randomInteger(1, 100) <= left_reversal_percent
        Reverse
        leftReversed#[grainCount] = 1
    endif
    
    Rename: "L_" + string$(grainCount)
    leftGrainIDs#[grainCount] = leftGrain
    
    # RIGHT CHANNEL GRAIN (for stereo modes)
    if output_mode >= 2
        if output_mode = 2
            # Mode 2: Same grain as left
            selectObject: leftGrain
            Copy: "R_" + string$(grainCount)
            rightGrain = selected("Sound")
            rightReversed#[grainCount] = leftReversed#[grainCount]
            rightGrainStarts#[grainCount] = leftGrainStarts#[grainCount]
            
        elsif output_mode = 3
            # Mode 3: DIFFERENT RANDOM POSITION
            rightStartTime = randomUniform(0, maxStart)
            rightEndTime = rightStartTime + grain_length_s
            rightGrainStarts#[grainCount] = rightStartTime
            
            selectObject: sourceSound
            Extract part: rightStartTime, rightEndTime, windowShape$, 1, "no"
            rightGrain = selected("Sound")
            
            # Reverse right independently?
            if enable_reversal and randomInteger(1, 100) <= right_reversal_percent
                Reverse
                rightReversed#[grainCount] = 1
            endif
            
            Rename: "R_" + string$(grainCount)
            
        elsif output_mode = 4
            # Mode 4: SHUFFLED ORDER (extract same as left position;
            # reorder during concatenation using grainOrder)
            rightStartTime = leftStartTime
            rightGrainStarts#[grainCount] = leftStartTime
            
            selectObject: sourceSound
            Extract part: rightStartTime, leftEndTime, windowShape$, 1, "no"
            rightGrain = selected("Sound")
            
            # Reverse right independently?
            if enable_reversal and randomInteger(1, 100) <= right_reversal_percent
                Reverse
                rightReversed#[grainCount] = 1
            endif
            
            Rename: "R_" + string$(grainCount)
            
        else
            # Mode 5: TIME OFFSET
            rightStartTime = leftStartTime + time_offset_s
            
            # Wrap around if needed
            while rightStartTime > maxStart
                rightStartTime = rightStartTime - maxStart
            endwhile
            
            rightEndTime = rightStartTime + grain_length_s
            rightGrainStarts#[grainCount] = rightStartTime
            
            selectObject: sourceSound
            Extract part: rightStartTime, rightEndTime, windowShape$, 1, "no"
            rightGrain = selected("Sound")
            
            # Reverse right independently?
            if enable_reversal and randomInteger(1, 100) <= right_reversal_percent
                Reverse
                rightReversed#[grainCount] = 1
            endif
            
            Rename: "R_" + string$(grainCount)
        endif
        
        rightGrainIDs#[grainCount] = rightGrain
    endif
endfor

appendInfoLine: "Extracted ", grainCount, " grains"

# === Concatenate Grains ===
if grainCount > 0
    appendInfoLine: "Concatenating..."
    
    # Left channel - normal order
    selectObject: leftGrainIDs#[1]
    for g from 2 to grainCount
        plusObject: leftGrainIDs#[g]
    endfor
    Concatenate
    leftChannel = selected("Sound")
    Rename: "left_channel"
    
    # Right channel (if stereo)
    if output_mode >= 2
        if output_mode = 4
            # SHUFFLED ORDER - use grainOrder array
            selectObject: rightGrainIDs#[grainOrder#[1]]
            for g from 2 to grainCount
                plusObject: rightGrainIDs#[grainOrder#[g]]
            endfor
        else
            # Normal order
            selectObject: rightGrainIDs#[1]
            for g from 2 to grainCount
                plusObject: rightGrainIDs#[g]
            endfor
        endif
        
        Concatenate
        rightChannel = selected("Sound")
        Rename: "right_channel"
        
        # Combine to stereo
        selectObject: leftChannel, rightChannel
        Combine to stereo
        result = selected("Sound")
        
        removeObject: leftChannel, rightChannel
    else
        result = leftChannel
    endif
    
    # Rename result
    selectObject: result
    Rename: soundName$ + "_grains_" + presetName$
    
    # Scale
    Scale peak: 0.95
    
    # Get output duration
    outputDuration = Get total duration
    
    # Get output peak
    finalPeak = Get absolute extremum: 0, 0, "None"
endif

# === Cleanup ===
for g from 1 to grainCount
    removeObject: leftGrainIDs#[g]
    if output_mode >= 2
        removeObject: rightGrainIDs#[g]
    endif
endfor

removeObject: sourceSound

# === Count Reversals ===
leftRevCount = 0
rightRevCount = 0
for g from 1 to grainCount
    leftRevCount += leftReversed#[g]
    rightRevCount += rightReversed#[g]
endfor

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================
if draw_visualization and grainCount > 0
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    Black
    Plain line
    
    # Mono copy of original for waveform panels
    selectObject: original
    if numChannels > 1
        vizOrig = Convert to mono
    else
        vizOrig = Copy: "viz_orig"
    endif
    
    # Mono copy of result for waveform panels (result may be stereo)
    selectObject: result
    resultNumCh = Get number of channels
    if resultNumCh > 1
        vizResult = Convert to mono
    else
        vizResult = Copy: "viz_result"
    endif
    
    # Compute SHARED y-axis from BOTH original and result
    selectObject: vizOrig
    oPeak = Get absolute extremum: 0, 0, "None"
    selectObject: vizResult
    pPeak = Get absolute extremum: 0, 0, "None"
    sharedPeak = oPeak
    if pPeak > sharedPeak
        sharedPeak = pPeak
    endif
    if sharedPeak < 0.001
        sharedPeak = 0.001
    endif
    sharedAmp = sharedPeak * 1.15
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##SOUND TO GRAIN##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    
    if enable_reversal
        revStr$ = "rev L/R: " + string$(leftRevCount) + "/" + string$(rightRevCount)
    else
        revStr$ = "no reversal"
    endif
    
    Text: 0.5, "centre", -0.22, "half",
        ... soundName$
        ... + "  |  " + presetName$
        ... + "  |  " + modeLabel$
        ... + "  |  " + string$(grainCount) + " grains x " + fixed$(grain_length_s * 1000, 0) + " ms"
        ... + "  |  " + windowShape$
        ... + "  |  " + revStr$
    
    # ----------------------------------------------------------
    # PANEL A: GRAIN MAP  (left, headline)
    # PRESERVED v2.0 design: L grains top, R grains bottom for
    # stereo; single grain map for mono. Color-coded by reversal.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40
    
    if output_mode >= 2
        # Stereo: L grains top half, R grains bottom half
        Axes: 0, totalDuration, 0, grainCount * 2 + 1
        Paint rectangle: "{0.97, 0.97, 0.99}", 0, totalDuration, 0, grainCount * 2 + 1
        
        # Draw LEFT grains (top half)
        for g from 1 to grainCount
            startT = leftGrainStarts#[g]
            endT = startT + grain_length_s
            yPos = grainCount + g
            
            if leftReversed#[g] = 1
                barColor$ = "{0.85, 0.45, 0.45}"
            else
                barColor$ = "{0.45, 0.60, 0.82}"
            endif
            
            Paint rectangle: barColor$, startT, endT, yPos - 0.4, yPos + 0.4
        endfor
        
        # Draw RIGHT grains (bottom half)
        for g from 1 to grainCount
            if output_mode = 4
                # Shuffled - show actual source position from grainOrder
                actualGrain = grainOrder#[g]
                startT = leftGrainStarts#[actualGrain]
            else
                startT = rightGrainStarts#[g]
            endif
            endT = startT + grain_length_s
            yPos = g
            
            if rightReversed#[g] = 1
                barColor$ = "{0.85, 0.65, 0.40}"
            else
                barColor$ = "{0.45, 0.75, 0.55}"
            endif
            
            Paint rectangle: barColor$, startT, endT, yPos - 0.4, yPos + 0.4
        endfor
        
        # Divider
        Colour: "{0.50, 0.50, 0.55}"
        Line width: 1
        Dashed line
        Draw line: 0, grainCount + 0.5, totalDuration, grainCount + 0.5
        Solid line
        Line width: 1
        
        # Channel labels
        Font size: 6
        Colour: "{0.40, 0.40, 0.40}"
        Text: -totalDuration * 0.02, "right", grainCount + grainCount / 2 + 0.5, "half", "L"
        Text: -totalDuration * 0.02, "right", grainCount / 2 + 0.5, "half", "R"
        
        Colour: "Black"
        Line width: 1
        Draw inner box
        Font size: 6
        Text left: "yes", "L / R grains"
        Text bottom: "yes", "Source position (s)"
    else
        # Mono: single grain map
        Axes: 0, totalDuration, 0, grainCount + 1
        Paint rectangle: "{0.97, 0.97, 0.99}", 0, totalDuration, 0, grainCount + 1
        
        for g from 1 to grainCount
            startT = leftGrainStarts#[g]
            endT = startT + grain_length_s
            
            if leftReversed#[g] = 1
                barColor$ = "{0.85, 0.45, 0.45}"
            else
                barColor$ = "{0.45, 0.60, 0.82}"
            endif
            
            Paint rectangle: barColor$, startT, endT, g - 0.4, g + 0.4
        endfor
        
        Colour: "Black"
        Line width: 1
        Draw inner box
        Font size: 6
        Text left: "yes", "Grain #"
        Text bottom: "yes", "Source position (s)"
    endif
    
    # ----------------------------------------------------------
    # PANEL B: PARAMETER REPORT  (right, headline)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.55, 7.75, 0.95, 4.40
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 1
    
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.94, "half", "Algorithm:"
    
    Font size: 7
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.10, "left", 0.88, "half", "Extract random grains -> concatenate"
    Text: 0.10, "left", 0.83, "half", "(stereo modes vary by output_mode)"
    
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.75, "half", "Grains:"
    
    Font size: 10
    Colour: "{0.55, 0.35, 0.78}"
    Text: 0.10, "left", 0.68, "half", "Count:   " + string$(grainCount)
    Text: 0.10, "left", 0.62, "half", "Length:  " + fixed$(grain_length_s * 1000, 0) + " ms"
    Text: 0.10, "left", 0.56, "half", "Window:  " + windowShape$
    
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.48, "half", "Output mode:"
    
    Font size: 9
    Colour: "{0.20, 0.50, 0.82}"
    Text: 0.10, "left", 0.42, "half", modeLabel$
    
    if output_mode = 5
        Font size: 7
        Colour: "{0.30, 0.30, 0.30}"
        Text: 0.10, "left", 0.37, "half", "Offset: " + fixed$(time_offset_s * 1000, 0) + " ms (wraps)"
    endif
    
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.30, "half", "Reversal:"
    
    Font size: 9
    if enable_reversal
        Colour: "{0.85, 0.45, 0.30}"
        Text: 0.10, "left", 0.24, "half", "L: " + string$(leftRevCount) + "/" + string$(grainCount) + " (target " + string$(left_reversal_percent) + "%)"
        if output_mode >= 2
            Text: 0.10, "left", 0.18, "half", "R: " + string$(rightRevCount) + "/" + string$(grainCount) + " (target " + string$(right_reversal_percent) + "%)"
        endif
    else
        Colour: "{0.30, 0.55, 0.30}"
        Text: 0.10, "left", 0.24, "half", "Disabled"
    endif
    
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.10, "half", "Output:"
    
    Font size: 9
    Colour: "{0.30, 0.55, 0.30}"
    Text: 0.10, "left", 0.04, "half", fixed$(outputDuration, 2) + " s, peak " + fixed$(finalPeak, 3)
    
    Colour: "Black"
    Draw inner box
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    if output_mode >= 2
        Text: 2.10, "centre", 7.30, "half", "Grain extraction map (top = L, bottom = R)"
    else
        Text: 2.10, "centre", 7.30, "half", "Grain extraction map"
    endif
    Text: 6.10, "centre", 7.30, "half", "Parameter report"
    
    # ----------------------------------------------------------
    # PANEL C: ZOOM OVERLAY  (first 500 ms)
    # Gray = original, blue = result, SHARED y-axis.
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.55, 7.72, 4.75, 5.48
    
    zoomDur = 0.5
    if zoomDur > totalDuration
        zoomDur = totalDuration
    endif
    if zoomDur > outputDuration
        zoomDur = outputDuration
    endif
    
    selectObject: vizOrig
    z_peak1 = Get absolute extremum: 0, zoomDur, "None"
    selectObject: vizResult
    z_peak2 = Get absolute extremum: 0, zoomDur, "None"
    z_max = z_peak1
    if z_peak2 > z_max
        z_max = z_peak2
    endif
    if z_max < 0.001
        z_max = 0.001
    endif
    z_amp = z_max * 1.15
    
    Axes: 0, zoomDur, -z_amp, z_amp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, zoomDur, -z_amp, z_amp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, zoomDur, 0
    
    # Original behind
    selectObject: vizOrig
    Colour: "{0.65, 0.65, 0.65}"
    Line width: 1
    Draw: 0, zoomDur, -z_amp, z_amp, "no", "Curve"
    
    # Result on top
    selectObject: vizResult
    Colour: "{0.25, 0.50, 0.82}"
    Line width: 1
    Draw: 0, zoomDur, -z_amp, z_amp, "no", "Curve"
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Zoom: first " + fixed$(zoomDur * 1000, 0) + " ms  (gray = original, blue = result)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL D: FULL WAVEFORM COMPARISON  (SHARED y-axis)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 6.55
    Select inner viewport: 0.55, 7.72, 5.69, 6.48
    
    # Display range: max of input and output durations
    if outputDuration > totalDuration
        dispDur = outputDuration
    else
        dispDur = totalDuration
    endif
    
    Axes: 0, dispDur, -sharedAmp, sharedAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, dispDur, -sharedAmp, sharedAmp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, dispDur, 0
    
    # Mark where original ends if shorter than output
    if totalDuration < outputDuration
        Colour: "{0.85, 0.50, 0.20}"
        Line width: 1
        Dotted line
        Draw line: totalDuration, -sharedAmp, totalDuration, sharedAmp
        Solid line
        Font size: 5
        Text: totalDuration, "left", sharedAmp * 0.85, "half", "  end of source"
    endif
    
    # Original behind (only over its own duration)
    selectObject: vizOrig
    Colour: "{0.65, 0.65, 0.65}"
    Line width: 1
    Draw: 0, totalDuration, -sharedAmp, sharedAmp, "no", "Curve"
    
    # Result on top
    selectObject: vizResult
    Colour: "{0.25, 0.50, 0.82}"
    Line width: 1
    Draw: 0, dispDur, -sharedAmp, sharedAmp, "no", "Curve"
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Full waveform  (gray = original, blue = result, shared y-axis)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR  (suite standard — light grey)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.62, 7.30
    Select inner viewport: 0.55, 7.72, 6.68, 7.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + soundName$
        ... + "  |  " + modeLabel$
        ... + "  |  Grains: " + string$(grainCount) + " x " + fixed$(grain_length_s * 1000, 0) + " ms"
        ... + "  |  Window: " + windowShape$
    
    Text: 0.02, "left", 0.28, "half",
        ... "Reversal: " + revStr$
        ... + "  |  In: " + fixed$(totalDuration, 2) + " s (" + string$(numChannels) + " ch)"
        ... + "  |  Out: " + fixed$(outputDuration, 2) + " s, peak " + fixed$(finalPeak, 3)
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
    
    # Cleanup viz objects
    removeObject: vizOrig, vizResult
endif

# === Final Info ===
appendInfoLine: ""
appendInfoLine: "=== Done ==="

if grainCount > 0
    selectObject: result
    appendInfoLine: "Created: ", selected$("Sound")
    appendInfoLine: "Grains: ", grainCount
    appendInfoLine: "Duration: ", fixed$(outputDuration, 2), " s"
    if enable_reversal
        appendInfoLine: "Reversed: L=", leftRevCount, " R=", rightRevCount
    endif
    
    if play_result
        Play
    endif
    
    selectObject: result
else
    appendInfoLine: "No grains could be extracted"
endif
