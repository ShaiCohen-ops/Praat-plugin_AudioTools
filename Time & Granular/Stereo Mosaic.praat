# ============================================================
# Praat AudioTools - Stereo_Mosaic.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Stereo Mosaic - creates stereo composites from multiple
#   selected Sound objects by partitioning each file into
#   non-overlapping regions and distributing them to L/R
#   channels based on various spatial strategies.
#
# Changelog v0.2:
#   - Fixed header
#   - Added presets
#   - Added visualization
#   - Track region assignments for display
# ============================================================

form Stereo Mosaic
    comment Select multiple Sound objects first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom
        option Ping Pong (alternating L/R)
        option Split Screen (first half L, second R)
        option Random Scatter
        option Spiral Dance (golden ratio)
        option Dense Mosaic (many regions)
    
    comment === Regions ===
    positive Regions_per_file 4
    real Fade_time_s 0.05
    positive Attenuation_divisor 1.1
    
    comment === Channel Strategy ===
    optionmenu Channel_strategy 1
        option Alternating regions
        option Left first half / Right second half
        option Random split
        option Reverse order right
        option Inside out
        option Spiral pattern
    
    comment === Variations ===
    boolean Apply_reverse_playback 0
    boolean Randomize_amplitude 0
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Ping Pong
    regions_per_file = 4
    fade_time_s = 0.05
    attenuation_divisor = 1.1
    channel_strategy = 1
    apply_reverse_playback = 0
    randomize_amplitude = 0
elsif preset = 3
    # Split Screen
    regions_per_file = 4
    fade_time_s = 0.08
    attenuation_divisor = 1.0
    channel_strategy = 2
    apply_reverse_playback = 0
    randomize_amplitude = 0
elsif preset = 4
    # Random Scatter
    regions_per_file = 6
    fade_time_s = 0.04
    attenuation_divisor = 1.2
    channel_strategy = 3
    apply_reverse_playback = 1
    randomize_amplitude = 1
elsif preset = 5
    # Spiral Dance
    regions_per_file = 5
    fade_time_s = 0.05
    attenuation_divisor = 1.1
    channel_strategy = 6
    apply_reverse_playback = 0
    randomize_amplitude = 0
elsif preset = 6
    # Dense Mosaic
    regions_per_file = 8
    fade_time_s = 0.03
    attenuation_divisor = 1.3
    channel_strategy = 1
    apply_reverse_playback = 1
    randomize_amplitude = 1
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
if regions_per_file < 1
    exitScript: "Regions per file must be at least 1."
endif

# === Get Strategy Name ===
if channel_strategy = 1
    strategyName$ = "Alternating"
elsif channel_strategy = 2
    strategyName$ = "Split"
elsif channel_strategy = 3
    strategyName$ = "Random"
elsif channel_strategy = 4
    strategyName$ = "Reverse"
elsif channel_strategy = 5
    strategyName$ = "Inside-out"
else
    strategyName$ = "Spiral"
endif

# === Info ===
writeInfoLine: "=== Stereo Mosaic ==="
appendInfoLine: "Files: ", numberOfSelectedSounds
appendInfoLine: "Regions per file: ", regions_per_file
appendInfoLine: "Strategy: ", strategyName$
appendInfoLine: ""

# === Store Original Selection ===
originalSounds# = selected#("Sound")

# === Convert All to Mono ===
monoSounds# = zero#(numberOfSelectedSounds)

for i to numberOfSelectedSounds
    selectObject: originalSounds#[i]
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

# === Create Initial Buffers ===
Create Sound from formula: "temp_left", 1, 0, 0.01, 44100, "0"
leftID = selected("Sound")

Create Sound from formula: "temp_right", 1, 0, 0.01, 44100, "0"
rightID = selected("Sound")

# === Store Region Assignments for Visualization ===
totalRegions = numberOfSelectedSounds * regions_per_file
regionFile# = zero#(totalRegions)
regionIndex# = zero#(totalRegions)
regionChannel# = zero#(totalRegions)
regionReversed# = zero#(totalRegions)
regionIdx = 0

leftCount = 0
rightCount = 0

# === Main Processing Loop ===
appendInfoLine: "Processing files..."

for i to numberOfSelectedSounds
    selectObject: monoSounds#[i]
    soundName$ = selected$("Sound")
    total_duration = Get total duration
    
    region_duration = total_duration / regions_per_file
    
    appendInfoLine: "  File ", i, ": ", regions_per_file, " regions × ", fixed$(region_duration * 1000, 0), "ms"
    
    for region to regions_per_file
        regionStart = (region - 1) * region_duration
        regionEnd = region * region_duration
        
        selectObject: monoSounds#[i]
        Extract part: regionStart, regionEnd, "rectangular", 1, "no"
        regionSeg = selected("Sound")
        
        # Determine channel based on strategy
        if channel_strategy = 1
            # Alternating
            if region mod 2 = 1
                isLeftChannel = 1
            else
                isLeftChannel = 0
            endif
        elsif channel_strategy = 2
            # Left first half, Right second half
            if region <= regions_per_file / 2
                isLeftChannel = 1
            else
                isLeftChannel = 0
            endif
        elsif channel_strategy = 3
            # Random
            if randomUniform(0, 1) < 0.5
                isLeftChannel = 1
            else
                isLeftChannel = 0
            endif
        elsif channel_strategy = 4
            # Reverse order right
            if region mod 2 = 1
                isLeftChannel = 0
            else
                isLeftChannel = 1
            endif
        elsif channel_strategy = 5
            # Inside out
            midpoint = (regions_per_file + 1) / 2
            distanceFromMid = abs(region - midpoint)
            if floor(distanceFromMid) mod 2 = 0
                isLeftChannel = 1
            else
                isLeftChannel = 0
            endif
        else
            # Spiral (golden ratio)
            spiralValue = (i * 1.618 + region) mod 2
            if spiralValue < 1
                isLeftChannel = 1
            else
                isLeftChannel = 0
            endif
        endif
        
        # Store for visualization
        regionIdx += 1
        regionFile#[regionIdx] = i
        regionIndex#[regionIdx] = region
        regionChannel#[regionIdx] = isLeftChannel
        
        # Optional reverse
        selectObject: regionSeg
        wasReversed = 0
        if apply_reverse_playback = 1 and randomUniform(0, 1) < 0.3
            Reverse
            wasReversed = 1
        endif
        regionReversed#[regionIdx] = wasReversed
        
        # Optional amplitude randomization
        if randomize_amplitude = 1
            ampVariation = 0.5 + randomUniform(0, 1)
            Scale peak: ampVariation * 0.8
        endif
        
        # Apply fades
        if region_duration > 2 * fade_time_s
            Formula: "self / attenuation_divisor"
            Formula: "self * min(1, x / fade_time_s)"
            Formula: "self * min(1, (xmax - x) / fade_time_s)"
        else
            Formula: "self / attenuation_divisor"
        endif
        
        # Add to appropriate channel
        if isLeftChannel = 1
            selectObject: leftID, regionSeg
            Concatenate
            newLeft = selected("Sound")
            removeObject: leftID
            leftID = newLeft
            Rename: "temp_left"
            leftCount += 1
        else
            selectObject: rightID, regionSeg
            Concatenate
            newRight = selected("Sound")
            removeObject: rightID
            rightID = newRight
            Rename: "temp_right"
            rightCount += 1
        endif
        
        removeObject: regionSeg
    endfor
endfor

appendInfoLine: ""
appendInfoLine: "Left channel: ", leftCount, " regions"
appendInfoLine: "Right channel: ", rightCount, " regions"

# === Equalize Channel Lengths ===
selectObject: leftID
leftDur = Get total duration

selectObject: rightID
rightDur = Get total duration

# Pad shorter channel with silence
if leftDur > rightDur
    silenceDur = leftDur - rightDur
    silence = Create Sound from formula: "pad", 1, 0, silenceDur, 44100, "0"
    selectObject: rightID, silence
    Concatenate
    newRight = selected("Sound")
    removeObject: rightID, silence
    rightID = newRight
    Rename: "temp_right"
elsif rightDur > leftDur
    silenceDur = rightDur - leftDur
    silence = Create Sound from formula: "pad", 1, 0, silenceDur, 44100, "0"
    selectObject: leftID, silence
    Concatenate
    newLeft = selected("Sound")
    removeObject: leftID, silence
    leftID = newLeft
    Rename: "temp_left"
endif

# === Finalize ===
selectObject: leftID
Scale peak: 0.99

selectObject: rightID
Scale peak: 0.99

selectObject: leftID, rightID
Combine to stereo
result = selected("Sound")

compositeName$ = "stereo_mosaic_" + string$(numberOfSelectedSounds) + "files_" + string$(regions_per_file) + "reg"
Rename: compositeName$

selectObject: result
outputDuration = Get total duration

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
    Text: 0.5, "centre", 0.5, "half", "Stereo Mosaic: " + string$(numberOfSelectedSounds) + " files × " + string$(regions_per_file) + " regions (" + strategyName$ + ")"
    
    # Result waveform
    Select outer viewport: 0, 8, 0.6, 2.0
    Select inner viewport: 0.6, 7.6, 0.7, 1.9
    selectObject: result
    Colour: "{0.4, 0.6, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"
    
    # Region distribution - Left channel
    Select outer viewport: 0, 8, 2.2, 3.4
    Select inner viewport: 0.6, 7.6, 2.3, 3.3
    
    Axes: 0, totalRegions, 0, numberOfSelectedSounds + 1
    Paint rectangle: "{0.9, 0.95, 1.0}", 0, totalRegions, 0, numberOfSelectedSounds + 1
    
    # Draw left channel regions
    leftPos = 0
    for r to totalRegions
        if regionChannel#[r] = 1
            leftPos += 1
            fileIdx = regionFile#[r]
            
            # Color by file
            hue = (fileIdx - 1) / max(1, numberOfSelectedSounds - 1)
            red = 0.3 + 0.5 * sin(hue * 2 * pi)
            grn = 0.3 + 0.5 * sin(hue * 2 * pi + 2)
            blu = 0.3 + 0.5 * sin(hue * 2 * pi + 4)
            barColor$ = "{" + fixed$(red, 2) + ", " + fixed$(grn, 2) + ", " + fixed$(blu, 2) + "}"
            
            Paint rectangle: barColor$, leftPos - 0.9, leftPos - 0.1, fileIdx - 0.4, fileIdx + 0.4
            
            # Mark if reversed
            if regionReversed#[r] = 1
                Colour: "White"
                Font size: 5
                Text: leftPos - 0.5, "centre", fileIdx, "half", "R"
            endif
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "File #"
    Text: 0.5, "centre", 1.08, "bottom", "LEFT CHANNEL"
    
    # Region distribution - Right channel
    Select outer viewport: 0, 8, 3.5, 4.7
    Select inner viewport: 0.6, 7.6, 3.6, 4.6
    
    Axes: 0, totalRegions, 0, numberOfSelectedSounds + 1
    Paint rectangle: "{1.0, 0.95, 0.9}", 0, totalRegions, 0, numberOfSelectedSounds + 1
    
    # Draw right channel regions
    rightPos = 0
    for r to totalRegions
        if regionChannel#[r] = 0
            rightPos += 1
            fileIdx = regionFile#[r]
            
            # Color by file
            hue = (fileIdx - 1) / max(1, numberOfSelectedSounds - 1)
            red = 0.3 + 0.5 * sin(hue * 2 * pi)
            grn = 0.3 + 0.5 * sin(hue * 2 * pi + 2)
            blu = 0.3 + 0.5 * sin(hue * 2 * pi + 4)
            barColor$ = "{" + fixed$(red, 2) + ", " + fixed$(grn, 2) + ", " + fixed$(blu, 2) + "}"
            
            Paint rectangle: barColor$, rightPos - 0.9, rightPos - 0.1, fileIdx - 0.4, fileIdx + 0.4
            
            # Mark if reversed
            if regionReversed#[r] = 1
                Colour: "White"
                Font size: 5
                Text: rightPos - 0.5, "centre", fileIdx, "half", "R"
            endif
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "File #"
    Text: 0.5, "centre", 1.08, "bottom", "RIGHT CHANNEL"
    
    # File color legend
    Select outer viewport: 0, 8, 4.9, 5.4
    Select inner viewport: 0.6, 7.6, 5.0, 5.3
    
    Axes: 0, numberOfSelectedSounds, 0, 1
    
    for i to numberOfSelectedSounds
        hue = (i - 1) / max(1, numberOfSelectedSounds - 1)
        red = 0.3 + 0.5 * sin(hue * 2 * pi)
        grn = 0.3 + 0.5 * sin(hue * 2 * pi + 2)
        blu = 0.3 + 0.5 * sin(hue * 2 * pi + 4)
        barColor$ = "{" + fixed$(red, 2) + ", " + fixed$(grn, 2) + ", " + fixed$(blu, 2) + "}"
        
        Paint rectangle: barColor$, i - 0.9, i - 0.1, 0.2, 0.8
        
        Colour: "Black"
        Font size: 6
        Text: i - 0.5, "centre", 0.1, "bottom", "F" + string$(i)
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Files"
    
    # Stats
    Select outer viewport: 0, 8, 5.5, 5.8
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Total regions: " + string$(totalRegions) + " | L: " + string$(leftCount) + " | R: " + string$(rightCount) + " | Duration: " + fixed$(outputDuration, 2) + "s"
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", compositeName$
appendInfoLine: "Duration: ", fixed$(outputDuration, 2), " s"
appendInfoLine: "Regions: ", totalRegions, " (L:", leftCount, " R:", rightCount, ")"

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result