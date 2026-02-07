# ============================================================
# Praat AudioTools - Sound_to_Grain.praat v2.0 - FIXED
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.0 (2025) - Fixed stereo independence
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
# Changelog v2.0:
#   - Fixed stereo independence (was only reversing differently)
#   - Added 3 independence modes: Random, Shuffled, Offset
#   - Proper stereo input preservation
#   - Better visualization showing L vs R grains
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis 
#   Toolkit for Experimental Composition.
# ============================================================

form Sound to Grain v2.0 - FIXED
    comment === Preset ===
    optionmenu Preset: 1
        option Custom
        option Quick Texture (few grains)
        option Dense Cloud (many grains)
        option Micro Grains (short, choppy)
        option Long Segments (ambient)
        option Stereo Scatter (random positions)
        option Stereo Shuffle (different order)
    
    comment === Grains ===
    positive Number_of_grains 20
    positive Grain_length_s 0.3
    optionmenu Window_type: 1
        option Hanning
        option Rectangular
        option Triangular
    
    comment === Output Mode ===
    optionmenu Output_mode: 1
        option Mono
        option Stereo (same grains L/R)
        option Stereo (independent - random positions)
        option Stereo (independent - shuffled order)
        option Stereo (independent - time offset)
    positive Time_offset_s 0.1
    comment (For time offset mode only)
    
    comment === Reversal ===
    boolean Enable_reversal 0
    positive Left_reversal_percent 50
    positive Right_reversal_percent 50
    
    comment === Output ===
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
writeInfoLine: "=== Sound to Grain v2.0 - FIXED ==="
appendInfoLine: "Source: ", soundName$, " (", fixed$(totalDuration, 2), " s)"
appendInfoLine: "Input: ", numChannels, " channel(s)"
appendInfoLine: "Grains: ", number_of_grains, " × ", fixed$(grain_length_s * 1000, 0), " ms"
appendInfoLine: "Window: ", windowShape$

if output_mode = 1
    appendInfoLine: "Output: Mono"
elsif output_mode = 2
    appendInfoLine: "Output: Stereo (same L/R)"
elsif output_mode = 3
    appendInfoLine: "Output: Stereo (random positions)"
elsif output_mode = 4
    appendInfoLine: "Output: Stereo (shuffled order)"
else
    appendInfoLine: "Output: Stereo (time offset ", fixed$(time_offset_s, 3), "s)"
endif

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
if output_mode = 4
    # Fisher-Yates shuffle
    for i from number_of_grains to 2 by -1
        j = randomInteger(1, i)
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
            # Mode 4: SHUFFLED ORDER (extract all, use different order later)
            # For now, extract same as left - will reorder during concatenation
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

# === Visualization ===
if draw_visualization and grainCount > 0
    Erase all
    
    # Title
    Select outer viewport: 0, 10, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    
    if output_mode = 1
        modeLabel$ = "Mono"
    elsif output_mode = 2
        modeLabel$ = "Stereo (same)"
    elsif output_mode = 3
        modeLabel$ = "Stereo (random)"
    elsif output_mode = 4
        modeLabel$ = "Stereo (shuffled)"
    else
        modeLabel$ = "Stereo (offset)"
    endif
    
    Text: 0.5, "centre", 0.5, "half", "Sound to Grain v2.0: " + soundName$ + " [" + modeLabel$ + "]"
    
    # Original waveform with L grain markers
    Select outer viewport: 0, 10, 0.6, 1.8
    Select inner viewport: 0.6, 9.6, 0.7, 1.7
    selectObject: original
    Colour: "{0.7, 0.7, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    # Mark LEFT grain extraction points
    for g from 1 to grainCount
        startT = leftGrainStarts#[g]
        endT = startT + grain_length_s
        
        if leftReversed#[g] = 1
            Colour: "{0.8, 0.3, 0.3}"
        else
            Colour: "{0.3, 0.6, 0.8}"
        endif
        
        Draw line: startT, -0.5, startT, 0.5
        Draw line: endT, -0.5, endT, 0.5
        Draw line: startT, 0.5, endT, 0.5
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Source (L)"
    Text bottom: "yes", "Time (s)"
    
    # Result waveform
    Select outer viewport: 0, 10, 2.0, 3.2
    Select inner viewport: 0.6, 9.6, 2.1, 3.1
    selectObject: result
    Colour: "{0.4, 0.6, 0.4}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Result"
    Text bottom: "yes", "Time (s)"
    
    # L vs R grain positions comparison (for stereo modes)
    if output_mode >= 2
        Select outer viewport: 0, 10, 3.4, 5.2
        Select inner viewport: 0.6, 9.6, 3.6, 5.1
        
        Axes: 0, totalDuration, 0, grainCount * 2 + 1
        Paint rectangle: "{0.95, 0.95, 0.95}", 0, totalDuration, 0, grainCount * 2 + 1
        
        # Draw LEFT grains (top half)
        for g from 1 to grainCount
            startT = leftGrainStarts#[g]
            endT = startT + grain_length_s
            
            yPos = grainCount + g
            
            if leftReversed#[g] = 1
                barColor$ = "{0.9, 0.6, 0.6}"
            else
                barColor$ = "{0.6, 0.8, 0.9}"
            endif
            
            Paint rectangle: barColor$, startT, endT, yPos - 0.4, yPos + 0.4
        endfor
        
        # Draw RIGHT grains (bottom half)
        for g from 1 to grainCount
            if output_mode = 4
                # Shuffled - show actual order
                actualGrain = grainOrder#[g]
                startT = leftGrainStarts#[actualGrain]
            else
                startT = rightGrainStarts#[g]
            endif
            endT = startT + grain_length_s
            
            yPos = g
            
            if rightReversed#[g] = 1
                barColor$ = "{0.9, 0.8, 0.6}"
            else
                barColor$ = "{0.6, 0.9, 0.7}"
            endif
            
            Paint rectangle: barColor$, startT, endT, yPos - 0.4, yPos + 0.4
        endfor
        
        # Divider
        Colour: "{0.5, 0.5, 0.5}"
        Dashed line
        Draw line: 0, grainCount + 0.5, totalDuration, grainCount + 0.5
        Solid line
        
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "L / R Grains"
        Text bottom: "yes", "Source position (s)"
        
        # Labels
        Font size: 6
        Colour: "{0.4, 0.4, 0.4}"
        Text: -0.5, "right", grainCount + grainCount/2, "half", "L"
        Text: -0.5, "right", grainCount/2, "half", "R"
    else
        # Mono - single grain map
        Select outer viewport: 0, 10, 3.4, 5.2
        Select inner viewport: 0.6, 9.6, 3.6, 5.1
        
        Axes: 0, totalDuration, 0, grainCount + 1
        Paint rectangle: "{0.95, 0.95, 0.95}", 0, totalDuration, 0, grainCount + 1
        
        for g from 1 to grainCount
            startT = leftGrainStarts#[g]
            endT = startT + grain_length_s
            
            if leftReversed#[g] = 1
                barColor$ = "{0.8, 0.5, 0.5}"
            else
                barColor$ = "{0.5, 0.7, 0.9}"
            endif
            
            Paint rectangle: barColor$, startT, endT, g - 0.4, g + 0.4
        endfor
        
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Grain #"
        Text bottom: "yes", "Source position (s)"
    endif
    
    # Stats
    Select outer viewport: 0, 10, 5.4, 5.8
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    
    statsText$ = "Grains: " + string$(grainCount) + " | Length: " + fixed$(grain_length_s * 1000, 0) + "ms | Output: " + fixed$(outputDuration, 2) + "s"
    if enable_reversal
        statsText$ = statsText$ + " | Reversed L: " + string$(leftRevCount) + " R: " + string$(rightRevCount)
    endif
    Text: 0.5, "centre", 0.5, "half", statsText$
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
if grainCount > 0
    selectObject: result
    
    appendInfoLine: ""
    appendInfoLine: "=== Done ==="
    appendInfoLine: "Created: ", selected$("Sound")
    appendInfoLine: "Grains: ", grainCount
    appendInfoLine: "Duration: ", fixed$(outputDuration, 2), " s"
    if enable_reversal
        appendInfoLine: "Reversed: L=", leftRevCount, " R=", rightRevCount
    endif
    
    # === Play ===
    if play_result
        Play
    endif
    
    selectObject: original
else
    appendInfoLine: ""
    appendInfoLine: "No grains could be extracted"
endif