# ============================================================
# Praat AudioTools - Fast Spectral Swirl Multi-Channel.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
# v0.4.1 (2026): SPATIAL VISUALIZATION STANDARDIZATION ONLY - label rails, compact summary, typography; DSP unchanged.
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
#
# Changelog v0.4.1 (2026):
#   - FIX: Wet/dry mix Formula used "Object_<id>[col, row]" with two
#     bugs: (a) Object_<numeric> resolves by name and crashes on
#     numeric IDs, and (b) the index order [col, row] is reversed —
#     Praat's object[] syntax takes (id, row, col). Replaced with
#     correct "object[<id>, row, col]".
#   - CHANGE: Removed per-channel "Scale peak: 0.99" calls. They
#     normalized each channel independently, destroying inter-
#     channel level relationships and reducing spatial coherence.
#     Final post-combine "Scale peak: 0.99" handles overall level.
#   - VIZ: Replaced single-channel waveform panel with 2x4 small-
#     multiples grid showing all 8 channel waveforms, color-coded
#     to match the swirl-pattern panel's gradient.
#   - VIZ: Added output spectrogram panel (Channel 4) so the
#     spectral effect is directly visible.
# ============================================================

# ============================================================
# FORM
# ============================================================

form Spectral Swirl Multi-Channel v0.4.1
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
writeInfoLine: "Fast Spectral Swirl Multi-Channel v0.4.1"
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
    # v0.4: removed per-channel "Scale peak: 0.99" — it normalized
    # each channel independently and destroyed inter-channel level
    # relationships. The final post-combine Scale peak handles
    # overall level appropriately.

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
    # v0.4: was "Object_<id>[col, row]" which has two bugs:
    # (a) Object_<numeric_id> resolves by name, not numeric ID; and
    # (b) the index order is wrong — Praat's object[] takes
    # (id, row, col), not (id, col, row).
    wetStr$ = fixed$(wet_level, 6)
    dryStr$ = fixed$(dry_level, 6)
    dryIdStr$ = fixed$(dryCombined, 0)

    selectObject: combined
    Formula: "self * " + wetStr$
        ... + " + object[" + dryIdStr$ + ", row, col] * " + dryStr$
    
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
    Select outer viewport: 0, 8, 0, 8

    # ===========================================
    # Title (full width, top)
    # ===========================================
    Select outer viewport: 0, 8, 0.00, 0.28
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half",
        ... "##Spectral Swirl 8-Channel v0.4.1##"
    Select outer viewport: 0, 8, 0.28, 0.50
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.5, "half",
        ... originalName$ + "  |  preset: " + presetName$
        ... + "  |  base depth: " + string$(base_depth)
        ... + "  |  cycles: " + fixed$(base_cycle, 1)
        ... + "-" + fixed$(channelCycle[8], 1)
        ... + "  |  wet: " + string$(wet_dry_percent) + "%"

    # ===========================================
    # Input waveform
    # ===========================================
    Select outer viewport: 0, 8, 0.55, 1.30
    Select inner viewport: 0.6, 7.6, 0.60, 1.25
    selectObject: original
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.08, 0.52, 0.55, 1.3
    Select inner viewport: 0.08, 0.52, 0.57, 1.28
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Input"
    Select outer viewport: 0, 8, 0.55, 1.3
    Select inner viewport: 0.6, 7.6, 0.6, 1.25
    Text top: "no", "Source: " + originalName$

    # ===========================================
    # 2x4 small-multiples — all 8 channels of output
    # Layout: 4 columns x 2 rows over y = 1.35..2.85
    # Each cell is ~1.85" wide, ~0.7" tall
    # Color matches the swirl-pattern panel's blue->red gradient.
    # ===========================================
    smGridY1 = 1.35
    smGridY2 = 2.85
    smRowH = (smGridY2 - smGridY1) / 2
    smGridX1 = 0.6
    smGridX2 = 7.6
    smColW = (smGridX2 - smGridX1) / 4

    for ch from 1 to 8
        if ch <= 4
            smRow = 0
            smCol = ch - 1
        else
            smRow = 1
            smCol = ch - 5
        endif
        smX1 = smGridX1 + smCol * smColW
        smX2 = smX1 + smColW
        smY1 = smGridY1 + smRow * smRowH
        smY2 = smY1 + smRowH

        Select outer viewport: smX1, smX2, smY1, smY2
        Select inner viewport: smX1 + 0.05, smX2 - 0.05,
            ... smY1 + 0.07, smY2 - 0.07

        selectObject: result
        chExtract = Extract one channel: ch

        # Channel color (matches swirl-pattern panel)
        chR = (ch - 1) / 7
        chG = 0.3
        chB = 1 - (ch - 1) / 7
        Colour: "{" + fixed$(chR, 2) + ", " + fixed$(chG, 2)
            ... + ", " + fixed$(chB, 2) + "}"

        selectObject: chExtract
        Draw: 0, 0, 0, 0, "no", "Curve"
        Colour: "Black"
        Draw inner box
        Font size: 6
        Text top: "no", "Ch " + string$(ch)
            ... + "  cyc=" + fixed$(channelCycle[ch], 1)
            ... + "  d=" + fixed$(channelDepth[ch], 0)
        removeObject: chExtract
    endfor

    # ===========================================
    # Swirl pattern panel — design parameters
    # (the displacement curves, one per channel)
    # ===========================================
    Select outer viewport: 0, 8, 2.90, 4.10
    Select inner viewport: 0.6, 7.6, 3.00, 4.05

    maxDepth = channelDepth[8] * 1.2
    Axes: 0, 1, -maxDepth, maxDepth
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, -maxDepth, maxDepth

    # Zero line
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: 0, 0, 1, 0

    for ch from 1 to 8
        cycle = channelCycle[ch]
        depthVal = channelDepth[ch]
        r = (ch - 1) / 7
        g = 0.3
        b = 1 - (ch - 1) / 7
        Colour: "{" + fixed$(r, 2) + ", " + fixed$(g, 2)
            ... + ", " + fixed$(b, 2) + "}"

        prevX = 0
        prevY = 0
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
    Font size: 7
    Select outer viewport: 0.08, 0.52, 2.9, 4.1
    Select inner viewport: 0.08, 0.52, 2.92, 4.08
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Bin shift"
    Select outer viewport: 0, 8, 2.9, 4.1
    Select inner viewport: 0.6, 7.6, 3, 4.05
    Axes: 0, 1, -maxDepth, maxDepth
    Text bottom: "yes", "Normalized frequency"
    Text top: "no", "Swirl displacement curves (per channel)"

    # ===========================================
    # Output spectrogram panel — Channel 4
    # ===========================================
    Select outer viewport: 0, 8, 4.35, 5.85
    Select inner viewport: 0.6, 7.6, 4.45, 5.75

    selectObject: result
    chForSpec = Extract one channel: 4
    selectObject: chForSpec
    To Spectrogram: 0.02, 5000, 0.005, 20, "Gaussian"
    specOut = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    removeObject: specOut, chForSpec

    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.08, 0.52, 4.35, 5.85
    Select inner viewport: 0.08, 0.52, 4.37, 5.83
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Hz"
    Select outer viewport: 0, 8, 4.35, 5.85
    Select inner viewport: 0.6, 7.6, 4.45, 5.75
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Output spectrogram (Channel 4 — mid-range parameters)"

    # ===========================================
    # Channel legend strip
    # ===========================================
    Select outer viewport: 0, 8, 6.05, 6.40
    Select inner viewport: 0.6, 7.6, 6.07, 6.38
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1

    Font size: 6
    for ch from 1 to 8
        xPos = 0.04 + (ch - 1) * 0.115
        r = (ch - 1) / 7
        b = 1 - (ch - 1) / 7
        Colour: "{" + fixed$(r, 2) + ", 0.3, " + fixed$(b, 2) + "}"
        Text: xPos, "left", 0.5, "half",
            ... "Ch" + string$(ch)
            ... + " (" + fixed$(channelCycle[ch], 1)
            ... + "x, " + fixed$(channelDepth[ch], 0) + ")"
    endfor

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # ===========================================
    # Parameters summary strip
    # ===========================================
    Select outer viewport: 0, 8, 6.50, 6.95
    Select inner viewport: 0.6, 7.6, 6.53, 6.92
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.02, "left", 0.64, "half",
        ... "##Parameters##  base depth=" + string$(base_depth)
        ... + "  depth increment=" + string$(depth_increment)
        ... + "  base cycle=" + fixed$(base_cycle, 1)
        ... + "  cycle increment=" + fixed$(cycle_increment, 2)
    Text: 0.02, "left", 0.28, "half",
        ... "##Output##  channels=" + string$(finalChannels)
        ... + "  duration=" + fixed$(finalDur, 2) + " s"
        ... + "  sample rate=" + string$(sr) + " Hz"
        ... + "  wet/dry=" + string$(wet_dry_percent) + "%"
        ... + "  fade=" + fixed$(fade_duration, 3) + " s"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Select outer viewport: 0, 8, 0, 7.05
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
    Font size: 10
    Colour: "Black"
    Line width: 1
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
