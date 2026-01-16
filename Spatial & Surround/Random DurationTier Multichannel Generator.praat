# ============================================================
# Praat AudioTools - Random DurationTier Multichannel Generator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025) - Bug fixes and enhancements
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Random DurationTier Multichannel Generator with Presets
#   Creates time-stretched variants using random-walk DurationTiers
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.3:
#   - Fixed critical bug: single channel output was deleted during cleanup
#   - Fixed multichannel combining for 3+ channels
#   - Added visualization option
#   - Added option to keep DurationTiers
#   - Improved cleanup logic
#   - Better progress reporting
# ============================================================

# ---- Require exactly one input Sound selected ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound before running this script."
endif
orig = selected("Sound")
origName$ = selected$("Sound")

# Domain for tiers
tmin = Get start time
tmax = Get end time
totalDur = tmax - tmin

form Random DurationTier Multichannel Generator v0.3
    comment ==== Presets ====
    optionmenu Preset: 1
        option Custom
        option Subtle Variations (4ch gentle)
        option Standard Multi-texture (8ch moderate)
        option Extreme Time-stretch (8ch wild)
        option Dense Polyrhythm (12ch complex)
        option Minimal Duo (2ch subtle)
        option Chaotic Cluster (16ch maximum)
    comment ==== Channel Settings ====
    integer Number_of_channels 8
    comment ==== Duration Variation ====
    integer Control_points 10
    positive Variability 0.40
    positive Min_factor 0.50
    positive Max_factor 2.00
    comment ==== Pitch Analysis ====
    positive Pitch_floor 75
    positive Pitch_ceiling 600
    positive Time_step 0.01
    comment ==== Output Options ====
    word Name_prefix DurRand_
    word Output_stem dur8
    positive Scale_peak 0.99
    boolean Keep_duration_tiers 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Apply preset values if not Custom
if preset = 2
    # Subtle Variations
    number_of_channels = 4
    control_points = 8
    variability = 0.20
    min_factor = 0.80
    max_factor = 1.25
elsif preset = 3
    # Standard Multi-texture
    number_of_channels = 8
    control_points = 10
    variability = 0.40
    min_factor = 0.50
    max_factor = 2.00
elsif preset = 4
    # Extreme Time-stretch
    number_of_channels = 8
    control_points = 15
    variability = 0.60
    min_factor = 0.25
    max_factor = 4.00
elsif preset = 5
    # Dense Polyrhythm
    number_of_channels = 12
    control_points = 20
    variability = 0.50
    min_factor = 0.40
    max_factor = 2.50
elsif preset = 6
    # Minimal Duo
    number_of_channels = 2
    control_points = 6
    variability = 0.25
    min_factor = 0.70
    max_factor = 1.50
elsif preset = 7
    # Chaotic Cluster
    number_of_channels = 16
    control_points = 25
    variability = 0.70
    min_factor = 0.20
    max_factor = 5.00
endif

# Shorthand variables
nTiers = number_of_channels
nPts = control_points

writeInfoLine: "=== Random DurationTier Multichannel Generator v0.3 ==="
appendInfoLine: "Processing: ", origName$
appendInfoLine: "Duration: ", fixed$(totalDur, 3), " s"
appendInfoLine: "Number of channels: ", nTiers
appendInfoLine: "Control points per channel: ", nPts
appendInfoLine: "Variability: ", fixed$(variability, 2)
appendInfoLine: "Time-stretch range: ", fixed$(min_factor, 2), " to ", fixed$(max_factor, 2)
appendInfoLine: ""

# Random-walk step sigma (scaled by sqrt for proper variance)
stepSigma = variability / sqrt(nPts + 1)

# ============================================================
# CREATE DURATION TIERS
# ============================================================

appendInfoLine: "Creating ", nTiers, " duration tiers..."

# Store tier IDs
for k from 1 to nTiers
    tierName$ = name_prefix$ + string$(k)
    Create DurationTier: tierName$, tmin, tmax
    
    # Start at 1.0
    Add point: tmin, 1.0
    
    # Random walk for interior points
    state = 1.0
    for j from 1 to nPts
        time = tmin + j * (tmax - tmin) / (nPts + 1)
        step = randomGauss(0, stepSigma)
        state = state + step
        
        # Clamp to range
        if state < min_factor
            state = min_factor
        endif
        if state > max_factor
            state = max_factor
        endif
        
        Add point: time, state
    endfor
    
    # End at 1.0
    Add point: tmax, 1.0
    
    tierId_'k' = selected("DurationTier")
endfor

# ============================================================
# GENERATE TIME-STRETCHED VARIANTS
# ============================================================

appendInfoLine: "Generating ", nTiers, " time-stretched variants..."

for k from 1 to nTiers
    # Create manipulation from original
    selectObject: orig
    To Manipulation: time_step, pitch_floor, pitch_ceiling
    man = selected("Manipulation")
    
    # Replace duration tier
    thisTier = tierId_'k'
    selectObject: man
    plusObject: thisTier
    Replace duration tier
    
    # Resynthesize
    selectObject: man
    Get resynthesis (overlap-add)
    Rename: output_stem$ + "_var" + string$(k)
    resId_'k' = selected("Sound")
    
    # Remove manipulation (no longer needed)
    selectObject: man
    Remove
    
    # Progress
    if k mod 4 = 0 or k = nTiers
        appendInfoLine: "  Processed ", k, " / ", nTiers, " channels..."
    endif
endfor

# ============================================================
# COMBINE TO MULTICHANNEL
# ============================================================

appendInfoLine: ""
appendInfoLine: "Combining channels..."

if nTiers = 1
    # Single channel - just copy and rename (don't use original resId)
    selectObject: resId_1
    Copy: output_stem$ + "_1ch"
    multiChannelSound = selected("Sound")
    
elsif nTiers = 2
    # Stereo - combine two channels
    selectObject: resId_1
    plusObject: resId_2
    Combine to stereo
    Rename: output_stem$ + "_2ch"
    multiChannelSound = selected("Sound")
    
else
    # 3+ channels - iterative combining
    # Start with first two
    selectObject: resId_1
    plusObject: resId_2
    Combine to stereo
    combined = selected("Sound")
    
    # Add remaining channels one by one
    for k from 3 to nTiers
        selectObject: combined
        plusObject: resId_'k'
        Combine to stereo
        newCombined = selected("Sound")
        
        # Remove intermediate
        selectObject: combined
        Remove
        combined = newCombined
    endfor
    
    selectObject: combined
    Rename: output_stem$ + "_" + string$(nTiers) + "ch"
    multiChannelSound = selected("Sound")
endif

# Scale final result
selectObject: multiChannelSound
Scale peak: scale_peak

finalName$ = selected$("Sound")

# ============================================================
# CLEANUP
# ============================================================

# Remove variant sounds (they've been combined)
for k from 1 to nTiers
    selectObject: resId_'k'
    Remove
endfor

# Remove or keep duration tiers
if keep_duration_tiers
    appendInfoLine: "Duration tiers kept in Objects list"
else
    for k from 1 to nTiers
        selectObject: tierId_'k'
        Remove
    endfor
endif

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 7, 0, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Random DurationTier Generator: " + string$(nTiers) + " channels"
    
    # Original waveform
    Select outer viewport: 0, 7, 0.5, 1.6
    Select inner viewport: 0.6, 6.6, 0.65, 1.45
    selectObject: orig
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 7, 1.6, 2.7
    Select inner viewport: 0.6, 6.6, 1.75, 2.55
    selectObject: multiChannelSound
    Colour: "{0.3, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Result"
    Text bottom: "yes", "Time (s)"
    
    # Duration tier visualization (show up to 8 tiers)
    Select outer viewport: 0, 7, 2.9, 4.8
    Select inner viewport: 0.6, 6.6, 3.1, 4.6
    
    # Set axes
    yMin = min_factor * 0.9
    yMax = max_factor * 1.1
    Axes: tmin, tmax, yMin, yMax
    
    # Background
    Colour: "{0.97, 0.97, 0.97}"
    Paint rectangle: "{0.97, 0.97, 0.97}", tmin, tmax, yMin, yMax
    
    # Unity line
    Colour: "{0.8, 0.8, 0.8}"
    Draw line: tmin, 1.0, tmax, 1.0
    
    # Draw each tier curve (up to 8 for readability)
    numToShow = nTiers
    if numToShow > 8
        numToShow = 8
    endif
    
    for k from 1 to numToShow
        # Color gradient
        hue = (k - 1) / numToShow
        r = 0.3 + 0.5 * sin(hue * 2 * pi)
        g = 0.3 + 0.5 * sin(hue * 2 * pi + 2 * pi / 3)
        b = 0.3 + 0.5 * sin(hue * 2 * pi + 4 * pi / 3)
        Colour: "{" + fixed$(r, 2) + ", " + fixed$(g, 2) + ", " + fixed$(b, 2) + "}"
        
        if keep_duration_tiers
            # Draw from actual tier
            thisTier = tierId_'k'
            selectObject: thisTier
            nPoints = Get number of points
            
            Line width: 1.5
            for p from 2 to nPoints
                t1 = Get time from index: p - 1
                v1 = Get value at index: p - 1
                t2 = Get time from index: p
                v2 = Get value at index: p
                Draw line: t1, v1, t2, v2
            endfor
            Line width: 1
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Factor"
    Text bottom: "yes", "Time (s)"
    
    if numToShow < nTiers
        Text top: "no", "Duration Tiers (showing " + string$(numToShow) + " of " + string$(nTiers) + ")"
    else
        Text top: "no", "Duration Tiers"
    endif
    
    # Marks
    Marks left every: 1, 0.5, "yes", "yes", "no"
    
    # Parameters
    Select outer viewport: 0, 7, 4.9, 5.3
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Channels: " + string$(nTiers) + " | Points: " + string$(nPts) + " | Variability: " + fixed$(variability, 2) + " | Range: " + fixed$(min_factor, 2) + "-" + fixed$(max_factor, 2)
    
    Font size: 10
    Colour: "Black"
endif

# ============================================================
# FINAL OUTPUT
# ============================================================

selectObject: multiChannelSound

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Original: ", origName$
appendInfoLine: "Result: ", finalName$
appendInfoLine: "Channels: ", nTiers
appendInfoLine: "Peak: ", fixed$(scale_peak, 2)
if keep_duration_tiers
    appendInfoLine: "Duration tiers: kept (", nTiers, " tiers)"
endif
appendInfoLine: ""

if play_result
    selectObject: multiChannelSound
    Play
endif
