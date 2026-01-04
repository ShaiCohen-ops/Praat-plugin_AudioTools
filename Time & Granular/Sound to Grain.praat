# ============================================================
# Praat AudioTools - Sound_to_Grain.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Sound to Grain - extracts random grains from audio and
#   concatenates them. Supports mono/stereo output with
#   independent reversal probability per channel.
#
# Changelog v0.2:
#   - Merged mono/stereo versions
#   - Added presets
#   - Added visualization
#   - Modern syntax
# ============================================================

form Sound to Grain
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom
        option Quick Texture (few grains)
        option Dense Cloud (many grains)
        option Micro Grains (short, choppy)
        option Long Segments (ambient)
        option Stereo Scatter (L/R reversal)
    
    comment === Grains ===
    positive Number_of_grains 20
    positive Grain_length_s 0.3
    optionmenu Window_type 1
        option Hanning
        option Rectangular
        option Triangular
    
    comment === Output Mode ===
    optionmenu Output_mode 1
        option Mono
        option Stereo (same grains L/R)
        option Stereo (independent L/R)
    
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
    left_reversal_percent = 0
    right_reversal_percent = 0
elsif preset = 3
    # Dense Cloud
    number_of_grains = 50
    grain_length_s = 0.15
    window_type = 1
    output_mode = 1
    enable_reversal = 1
    left_reversal_percent = 30
    right_reversal_percent = 30
elsif preset = 4
    # Micro Grains
    number_of_grains = 80
    grain_length_s = 0.05
    window_type = 2
    output_mode = 1
    enable_reversal = 0
    left_reversal_percent = 0
    right_reversal_percent = 0
elsif preset = 5
    # Long Segments
    number_of_grains = 10
    grain_length_s = 0.8
    window_type = 1
    output_mode = 1
    enable_reversal = 0
    left_reversal_percent = 0
    right_reversal_percent = 0
elsif preset = 6
    # Stereo Scatter
    number_of_grains = 25
    grain_length_s = 0.25
    window_type = 1
    output_mode = 3
    enable_reversal = 1
    left_reversal_percent = 40
    right_reversal_percent = 60
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

# === Convert to Mono for Processing ===
selectObject: original
if numChannels > 1
    Convert to mono
    sourceSound = selected("Sound")
else
    Copy: "source_temp"
    sourceSound = selected("Sound")
endif

# === Info ===
writeInfoLine: "=== Sound to Grain ==="
appendInfoLine: "Source: ", soundName$, " (", fixed$(totalDuration, 2), " s)"
appendInfoLine: "Grains: ", number_of_grains, " × ", fixed$(grain_length_s * 1000, 0), " ms"
appendInfoLine: "Window: ", windowShape$
if output_mode = 1
    appendInfoLine: "Output: Mono"
elsif output_mode = 2
    appendInfoLine: "Output: Stereo (same L/R)"
else
    appendInfoLine: "Output: Stereo (independent L/R)"
endif
if enable_reversal
    appendInfoLine: "Reversal: L=", left_reversal_percent, "% R=", right_reversal_percent, "%"
endif
appendInfoLine: ""

# === Arrays ===
leftGrainIDs# = zero#(number_of_grains)
rightGrainIDs# = zero#(number_of_grains)
grainStarts# = zero#(number_of_grains)
leftReversed# = zero#(number_of_grains)
rightReversed# = zero#(number_of_grains)
grainCount = 0

# === Extract Grains ===
appendInfoLine: "Extracting grains..."

for grain from 1 to number_of_grains
    maxStart = totalDuration - grain_length_s
    
    if maxStart > 0
        startTime = randomUniform(0, maxStart)
        endTime = startTime + grain_length_s
        
        grainCount += 1
        grainStarts#[grainCount] = startTime
        
        # Extract LEFT grain
        selectObject: sourceSound
        Extract part: startTime, endTime, windowShape$, 1, "no"
        leftGrain = selected("Sound")
        
        # Reverse left?
        if enable_reversal and randomInteger(1, 100) <= left_reversal_percent
            Reverse
            leftReversed#[grainCount] = 1
        endif
        
        Rename: "L_" + string$(grainCount)
        leftGrainIDs#[grainCount] = leftGrain
        
        # Extract RIGHT grain (for stereo modes)
        if output_mode >= 2
            if output_mode = 2
                # Same grain as left
                selectObject: leftGrain
                Copy: "R_" + string$(grainCount)
                rightGrain = selected("Sound")
                rightReversed#[grainCount] = leftReversed#[grainCount]
            else
                # Independent extraction (same position, but independent reversal)
                selectObject: sourceSound
                Extract part: startTime, endTime, windowShape$, 1, "no"
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
    endif
endfor

appendInfoLine: "Extracted ", grainCount, " grains"

# === Concatenate Grains ===
if grainCount > 0
    appendInfoLine: "Concatenating..."
    
    # Left/Mono channel
    selectObject: leftGrainIDs#[1]
    for g from 2 to grainCount
        if leftGrainIDs#[g] > 0
            plusObject: leftGrainIDs#[g]
        endif
    endfor
    Concatenate
    leftChannel = selected("Sound")
    Rename: "left_channel"
    
    # Right channel (if stereo)
    if output_mode >= 2
        selectObject: rightGrainIDs#[1]
        for g from 2 to grainCount
            if rightGrainIDs#[g] > 0
                plusObject: rightGrainIDs#[g]
            endif
        endfor
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
    if output_mode = 1
        Rename: soundName$ + "_grains"
    else
        Rename: soundName$ + "_grains_stereo"
    endif
    
    # Scale
    Scale peak: 0.95
    
    # Get output duration
    outputDuration = Get total duration
endif

# === Cleanup ===
for g from 1 to grainCount
    if leftGrainIDs#[g] > 0
        removeObject: leftGrainIDs#[g]
    endif
    if output_mode >= 2 and rightGrainIDs#[g] > 0
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
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    if output_mode = 1
        modeLabel$ = "Mono"
    elsif output_mode = 2
        modeLabel$ = "Stereo (same)"
    else
        modeLabel$ = "Stereo (indep)"
    endif
    Text: 0.5, "centre", 0.5, "half", "Sound to Grain: " + soundName$ + " (" + modeLabel$ + ")"
    
    # Original waveform with grain markers
    Select outer viewport: 0, 8, 0.6, 2.2
    Select inner viewport: 0.6, 7.6, 0.7, 2.1
    selectObject: original
    Colour: "{0.7, 0.7, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    # Mark grain extraction points
    for g from 1 to grainCount
        startT = grainStarts#[g]
        endT = startT + grain_length_s
        
        # Color by reversal state
        if leftReversed#[g] = 1
            Colour: "{0.8, 0.3, 0.3}"
        else
            Colour: "{0.3, 0.6, 0.8}"
        endif
        
        Draw line: startT, -0.7, startT, 0.7
        Draw line: endT, -0.7, endT, 0.7
        Draw line: startT, 0.7, endT, 0.7
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Source"
    Text bottom: "yes", "Time (s)"
    
    # Legend
    Font size: 6
    Colour: "{0.3, 0.6, 0.8}"
    Text: 0.02, "left", 1.05, "half", "Normal"
    Colour: "{0.8, 0.3, 0.3}"
    Text: 0.15, "left", 1.05, "half", "Reversed"
    
    # Result waveform
    Select outer viewport: 0, 8, 2.4, 4.0
    Select inner viewport: 0.6, 7.6, 2.5, 3.9
    selectObject: result
    Colour: "{0.4, 0.6, 0.4}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Result"
    Text bottom: "yes", "Time (s)"
    
    # Grain position scatter plot
    Select outer viewport: 0, 8, 4.2, 5.6
    Select inner viewport: 0.6, 7.6, 4.4, 5.5
    
    Axes: 0, totalDuration, 0, grainCount + 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, totalDuration, 0, grainCount + 1
    
    # Draw grains as horizontal bars
    for g from 1 to grainCount
        startT = grainStarts#[g]
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
    
    # Stats
    Select outer viewport: 0, 8, 5.8, 6.1
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
    
    selectObject: result
else
    appendInfoLine: ""
    appendInfoLine: "No grains could be extracted"
endif