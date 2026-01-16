# ============================================================
# Praat AudioTools - Fast Spectral Swirl Multi-Channel.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Optimized
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Creates 8-channel output with spectral swirl effect.
#   Each channel receives different swirl parameters creating
#   spatial variation through spectral bin displacement.
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.2:
#   - Safe object handling (no global cleanup)
#   - Modern selectObject: syntax throughout
#   - Added preset system
#   - Dynamic naming based on input sound
#   - Robust formula string building
#   - Added wet/dry mix control
#   - Added visualization option
#   - Added play_result option
# ============================================================

# ============================================================
# FORM
# ============================================================

form Spectral Swirl Multi-Channel
    optionmenu Preset: 1
        option Custom
        option Subtle Shimmer
        option Medium Swirl
        option Deep Swirl
        option Extreme Chaos
        option Gentle Spatial
        option Tight Cluster
    comment ─────────────────────────────────────────
    positive Base_depth 50
    positive Depth_increment 25
    positive Base_cycle 2
    real Cycle_increment 1.0
    comment ─────────────────────────────────────────
    positive Fade_duration_(s) 0.01
    integer Wet_dry_percent 100
    comment ─────────────────────────────────────────
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESET SYSTEM
# ============================================================

if preset = 2
    # Subtle Shimmer - gentle variation
    base_depth = 20
    depth_increment = 10
    base_cycle = 2
    cycle_increment = 0.5
    presetName$ = "subtle"
elsif preset = 3
    # Medium Swirl - balanced
    base_depth = 50
    depth_increment = 25
    base_cycle = 2
    cycle_increment = 1.0
    presetName$ = "medium"
elsif preset = 4
    # Deep Swirl - strong effect
    base_depth = 100
    depth_increment = 40
    base_cycle = 3
    cycle_increment = 1.5
    presetName$ = "deep"
elsif preset = 5
    # Extreme Chaos - maximum displacement
    base_depth = 200
    depth_increment = 60
    base_cycle = 5
    cycle_increment = 2.0
    presetName$ = "extreme"
elsif preset = 6
    # Gentle Spatial - subtle spatial spread
    base_depth = 15
    depth_increment = 5
    base_cycle = 1
    cycle_increment = 0.25
    presetName$ = "gentle"
elsif preset = 7
    # Tight Cluster - similar channels
    base_depth = 40
    depth_increment = 5
    base_cycle = 3
    cycle_increment = 0.2
    presetName$ = "tight"
else
    # Custom
    presetName$ = "custom"
endif

# ============================================================
# VALIDATION
# ============================================================

if numberOfSelected("Sound") = 0
    exitScript: "Please select a Sound object first."
endif

original = selected("Sound")
originalName$ = selected$("Sound")
selectObject: original
originalDur = Get total duration
sr = Get sampling frequency
nChannels_orig = Get number of channels

# Convert to mono if stereo input
if nChannels_orig > 1
    selectObject: original
    workSound = Convert to mono
else
    selectObject: original
    workSound = Copy: "work_temp"
endif

# Wet/dry validation
if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif

wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

# ============================================================
# INFO
# ============================================================

writeInfoLine: "============================================"
writeInfoLine: "Fast Spectral Swirl Multi-Channel v0.2"
writeInfoLine: "============================================"
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Duration: ", fixed$(originalDur, 3), " s"
appendInfoLine: "Sample rate: ", sr, " Hz"
appendInfoLine: "Original channels: ", nChannels_orig
appendInfoLine: "--------------------------------------------"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Base depth: ", base_depth
appendInfoLine: "Depth increment: ", depth_increment
appendInfoLine: "Base cycle: ", base_cycle
appendInfoLine: "Cycle increment: ", cycle_increment
appendInfoLine: "Wet/Dry: ", wet_dry_percent, "%"
appendInfoLine: "Fade: ", fade_duration, " s"
appendInfoLine: "--------------------------------------------"
appendInfoLine: "Creating 8-channel output..."
appendInfoLine: ""

# ============================================================
# STORE CHANNEL PARAMETERS FOR VISUALIZATION
# ============================================================

for i from 1 to 8
    channelCycle[i] = base_cycle + cycle_increment * (i - 1)
    channelDepth[i] = base_depth + depth_increment * (i - 1)
endfor

# ============================================================
# PROCESS: CREATE 8 SWIRLED VARIATIONS
# ============================================================

for i from 1 to 8
    appendInfoLine: "Processing channel ", i, "/8..."
    
    # Get parameters for this channel
    cycle = channelCycle[i]
    depthVal = channelDepth[i]
    
    appendInfoLine: "  Cycle: ", fixed$(cycle, 2), ", Depth: ", fixed$(depthVal, 1)
    
    # Create spectrum from work sound
    selectObject: workSound
    spec = To Spectrum: "yes"
    
    # Build formula string for spectral swirl
    # Formula shifts spectral bins sinusoidally
    # newCol = col + depth * sin(2*pi*cycle*col/ncol)
    cycleStr$ = fixed$(cycle, 6)
    depthStr$ = fixed$(depthVal, 6)
    
    selectObject: spec
    Formula: "if row = 1 then self[1, min(max(round(col + " + depthStr$ + " * sin(2 * pi * " + cycleStr$ + " * col / ncol)), 1), ncol)] else self[2, min(max(round(col + " + depthStr$ + " * sin(2 * pi * " + cycleStr$ + " * col / ncol)), 1), ncol)] fi"
    
    # Convert back to sound
    selectObject: spec
    swirled = To Sound
    Scale peak: 0.99
    
    # Store the swirled sound ID
    swirlSound[i] = swirled
    
    # Clean up spectrum
    removeObject: spec
endfor

appendInfoLine: ""
appendInfoLine: "Combining 8 channels..."

# ============================================================
# COMBINE INTO 8-CHANNEL SOUND
# ============================================================

# Select all 8 swirled sounds
selectObject: swirlSound[1]
for i from 2 to 8
    plusObject: swirlSound[i]
endfor

# Combine to multi-channel
combined = Combine to stereo

# Verify channel count
selectObject: combined
finalChannels = Get number of channels
finalDur = Get total duration

appendInfoLine: "Combined: ", finalChannels, " channels"

# Clean up individual swirled sounds
for i from 1 to 8
    removeObject: swirlSound[i]
endfor

# ============================================================
# APPLY FADES
# ============================================================

if fade_duration > 0 and fade_duration < finalDur / 2
    appendInfoLine: "Applying fades (", fade_duration, " s)..."
    
    fadeStr$ = fixed$(fade_duration, 6)
    durStr$ = fixed$(finalDur, 6)
    
    selectObject: combined
    Formula: "self * if x < " + fadeStr$ + " then x / " + fadeStr$ + " else if x > " + durStr$ + " - " + fadeStr$ + " then (" + durStr$ + " - x) / " + fadeStr$ + " else 1 fi fi"
endif

# ============================================================
# WET/DRY MIX
# ============================================================

if dry_level > 0
    appendInfoLine: "Applying wet/dry mix..."
    
    # Create 8-channel version of dry signal
    selectObject: workSound
    dryChannels[1] = Copy: "dry_1"
    for i from 2 to 8
        selectObject: workSound
        dryChannels[i] = Copy: "dry_" + string$(i)
    endfor
    
    # Combine dry channels
    selectObject: dryChannels[1]
    for i from 2 to 8
        plusObject: dryChannels[i]
    endfor
    dryCombined = Combine to stereo
    
    # Clean up individual dry copies
    for i from 1 to 8
        removeObject: dryChannels[i]
    endfor
    
    # Apply wet/dry formula
    wetStr$ = fixed$(wet_level, 6)
    dryStr$ = fixed$(dry_level, 6)
    dryIdStr$ = string$(dryCombined)
    
    selectObject: combined
    Formula: "self * " + wetStr$ + " + Object_" + dryIdStr$ + "[col, row] * " + dryStr$
    
    # Clean up dry combined
    removeObject: dryCombined
endif

# Final scaling
selectObject: combined
Scale peak: 0.99

# Rename with original name
selectObject: combined
Rename: originalName$ + "_swirl8ch_" + presetName$
result = combined

# Clean up work sound
removeObject: workSound

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # === Title ===
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Spectral Swirl 8-Channel: " + originalName$ + " (" + presetName$ + ")"
    
    # === Original waveform ===
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.6, 7.6, 0.7, 1.4
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Input"
    
    # === Result waveform (show first channel) ===
    Select outer viewport: 0, 8, 1.6, 2.5
    Select inner viewport: 0.6, 7.6, 1.7, 2.4
    selectObject: result
    extracted = Extract one channel: 1
    selectObject: extracted
    Colour: "{0.4, 0.6, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Ch.1"
    removeObject: extracted
    
    # === Swirl pattern visualization ===
    Select outer viewport: 0, 8, 2.7, 4.5
    Select inner viewport: 0.6, 7.6, 2.9, 4.4
    
    # Axes: x = normalized frequency (0-1), y = displacement
    maxDepth = channelDepth[8] * 1.2
    Axes: 0, 1, -maxDepth, maxDepth
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, -maxDepth, maxDepth
    
    # Zero line
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: 0, 0, 1, 0
    
    # Draw swirl curves for each channel
    for ch from 1 to 8
        cycle = channelCycle[ch]
        depthVal = channelDepth[ch]
        
        # Color gradient from blue to red across channels
        r = (ch - 1) / 7
        g = 0.3
        b = 1 - (ch - 1) / 7
        Colour: "{" + fixed$(r, 2) + ", " + fixed$(g, 2) + ", " + fixed$(b, 2) + "}"
        
        # Draw sine curve showing displacement pattern
        prevX = 0
        prevY = depthVal * sin(0)
        nPoints = 200
        for p from 1 to nPoints
            x = p / nPoints
            y = depthVal * sin(2 * pi * cycle * x)
            Draw line: prevX, prevY, x, y
            prevX = x
            prevY = y
        endfor
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Bin shift"
    Text bottom: "yes", "Normalized frequency"
    
    # === Legend ===
    Select outer viewport: 0, 8, 4.5, 5.0
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    
    # Draw channel legend
    for ch from 1 to 8
        xPos = 0.05 + (ch - 1) * 0.12
        r = (ch - 1) / 7
        b = 1 - (ch - 1) / 7
        Colour: "{" + fixed$(r, 2) + ", 0.3, " + fixed$(b, 2) + "}"
        Text: xPos, "left", 0.7, "half", "Ch" + string$(ch)
    endfor
    
    # === Parameters ===
    Select outer viewport: 0, 8, 5.0, 5.4
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Base depth: " + string$(base_depth) + " | Increment: " + string$(depth_increment) + " | Cycles: " + fixed$(base_cycle, 1) + "-" + fixed$(channelCycle[8], 1) + " | Wet: " + string$(wet_dry_percent) + "%"
    
    Font size: 10
    Colour: "Black"
endif

# ============================================================
# FINAL OUTPUT
# ============================================================

selectObject: result

appendInfoLine: ""
appendInfoLine: "============================================"
appendInfoLine: "PROCESSING COMPLETE"
appendInfoLine: "============================================"
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Channels: ", finalChannels
appendInfoLine: "Duration: ", fixed$(finalDur, 3), " s"
appendInfoLine: "Sample rate: ", sr, " Hz"
appendInfoLine: ""
appendInfoLine: "Channel parameters:"
for i from 1 to 8
    appendInfoLine: "  Ch ", i, ": cycle=", fixed$(channelCycle[i], 2), ", depth=", fixed$(channelDepth[i], 1)
endfor
appendInfoLine: ""
appendInfoLine: "Original preserved: ", originalName$

# ============================================================
# PLAY RESULT
# ============================================================

if play_result
    selectObject: result
    Play
endif

selectObject: result