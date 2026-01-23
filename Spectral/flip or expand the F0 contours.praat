# ============================================================
# Praat AudioTools - flip_or_expand_the_F0_contours.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2025) - Fixed axis range errors
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Manipulates F0 (pitch) contours using PSOLA resynthesis.
#   Can flip, expand/contract, or flatten pitch contours.
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

form F0 Contour Manipulation v0.5
    optionmenu Preset: 1
        option Custom
        option Flip (Mirror pitch)
        option Expand (More expressive)
        option Contract (Less expressive)
        option Flatten (Monotone)
        option Exaggerate (Strong expansion)
        option Subtle Expansion
        option High Voice Flatten
        option Low Voice Flatten
    comment === Method ===
    optionmenu Method: 1
        option Flip F0 contour
        option Expand/Contract F0
        option Flatten F0
    comment === Parameters ===
    positive Expansion_factor 1.3
    comment (>1 expand, <1 contract)
    real Flatten_target_hz 0
    comment (0 = use mean pitch)
    comment === Pitch Range ===
    positive Min_pitch 70
    positive Max_pitch 400
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS
# ============================================================

if preset = 2
    method = 1
    presetName$ = "Flip"
elsif preset = 3
    method = 2
    expansion_factor = 1.5
    presetName$ = "Expand"
elsif preset = 4
    method = 2
    expansion_factor = 0.5
    presetName$ = "Contract"
elsif preset = 5
    method = 3
    flatten_target_hz = 0
    presetName$ = "Flatten"
elsif preset = 6
    method = 2
    expansion_factor = 2.0
    presetName$ = "Exaggerate"
elsif preset = 7
    method = 2
    expansion_factor = 1.2
    presetName$ = "SubtleExpand"
elsif preset = 8
    method = 3
    flatten_target_hz = 200
    presetName$ = "HighFlatten"
elsif preset = 9
    method = 3
    flatten_target_hz = 100
    presetName$ = "LowFlatten"
else
    presetName$ = "Custom"
endif

# ============================================================
# SETUP
# ============================================================

selectObject: originalID
duration = Get total duration
sampleRate = Get sampling frequency

clearinfo
writeInfoLine: "=== F0 Contour Manipulation v0.5 ==="
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Duration: ", fixed$(duration, 2), " s"
appendInfoLine: ""
appendInfoLine: "Preset: ", presetName$
if method = 1
    appendInfoLine: "Method: Flip"
elsif method = 2
    appendInfoLine: "Method: Expand/Contract (factor: ", expansion_factor, ")"
else
    appendInfoLine: "Method: Flatten"
endif
appendInfoLine: "Pitch range: ", min_pitch, "-", max_pitch, " Hz"
appendInfoLine: ""

# ============================================================
# PROCESS
# ============================================================

appendInfo: "Creating manipulation object..."

selectObject: originalID
manipID = To Manipulation: 0.01, min_pitch, max_pitch

appendInfoLine: " done"

# Extract pitch tier
selectObject: manipID
origPitchTierID = Extract pitch tier

# Get mean pitch for reference
selectObject: origPitchTierID
meanPitch = Get mean (points): 0, 0

# Handle case where no pitch points found
if meanPitch = undefined or meanPitch <= 0
    meanPitch = (min_pitch + max_pitch) / 2
    appendInfoLine: "Warning: No pitch detected, using default mean: ", fixed$(meanPitch, 1), " Hz"
else
    appendInfoLine: "Mean pitch: ", fixed$(meanPitch, 1), " Hz"
endif

# Copy pitch tier for modification
selectObject: origPitchTierID
newPitchTierID = Copy: "modified_pitch"

# Apply manipulation
appendInfo: "Applying ", presetName$, "..."

selectObject: newPitchTierID

if method = 1
    # Flip F0 contour around the mean
    meanStr$ = fixed$(meanPitch, 6)
    Formula: "2 * " + meanStr$ + " - self"
    
elsif method = 2
    # Expand/Contract F0 contour around the mean
    meanStr$ = fixed$(meanPitch, 6)
    factorStr$ = fixed$(expansion_factor, 6)
    Formula: meanStr$ + " + (self - " + meanStr$ + ") * " + factorStr$
    
else
    # Flatten F0 contour
    if flatten_target_hz <= 0
        targetPitch = meanPitch
    else
        targetPitch = flatten_target_hz
    endif
    targetStr$ = fixed$(targetPitch, 6)
    Formula: targetStr$
endif

appendInfoLine: " done"

# Replace pitch tier in manipulation object
selectObject: manipID
plusObject: newPitchTierID
Replace pitch tier

# Resynthesize sound
appendInfo: "Resynthesizing..."

selectObject: manipID
resultID = Get resynthesis (overlap-add)
Rename: originalName$ + "_F0_" + presetName$

appendInfoLine: " done"

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    # Get pitch objects for display
    selectObject: originalID
    origPitchID = To Pitch: 0.01, min_pitch, max_pitch
    
    selectObject: resultID
    resPitchID = To Pitch: 0.01, min_pitch, max_pitch
    
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0, 0.5
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "F0 Manipulation: " + originalName$ + " [" + presetName$ + "]"
    
    # Original waveform
    Select outer viewport: 0, 4, 0.6, 1.8
    Select inner viewport: 0.5, 3.7, 0.7, 1.7
    selectObject: originalID
    Colour: "{0.7, 0.7, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Original"
    
    # Processed waveform
    Select outer viewport: 4, 8, 0.6, 1.8
    Select inner viewport: 4.5, 7.7, 0.7, 1.7
    selectObject: resultID
    Colour: "{0.2, 0.5, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text top: "no", "Modified"
    
    # Pitch contour comparison - use form's min/max (guaranteed valid)
    Select outer viewport: 0, 8, 2.0, 4.2
    Select inner viewport: 0.6, 7.6, 2.3, 4.0
    
    # Use min_pitch and max_pitch from form (always valid positive values)
    Axes: 0, duration, min_pitch, max_pitch
    
    selectObject: origPitchID
    Colour: "{0.7, 0.7, 0.7}"
    Line width: 2
    Draw: 0, 0, min_pitch, max_pitch, "no"
    
    selectObject: resPitchID
    Colour: "{0.2, 0.5, 0.8}"
    Line width: 2
    Draw: 0, 0, min_pitch, max_pitch, "no"
    
    # Draw mean line
    Colour: "{0.9, 0.4, 0.4}"
    Line width: 1
    Dotted line
    Draw line: 0, meanPitch, duration, meanPitch
    Solid line
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 9
    Text top: "no", "Pitch Contour (gray=original, blue=modified, red line=mean)"
    Text left: "yes", "F0 (Hz)"
    Text bottom: "yes", "Time (s)"
    
    # Info panel
    Select outer viewport: 0, 8, 4.4, 5.0
    Select inner viewport: 0.5, 7.7, 4.45, 4.95
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Font size: 9
    Colour: "{0.3, 0.3, 0.3}"
    
    if method = 1
        Text: 0.02, "left", 0.5, "half", "Method: Flip around mean"
    elsif method = 2
        Text: 0.02, "left", 0.5, "half", "Method: Expand/Contract (x" + fixed$(expansion_factor, 2) + ")"
    else
        Text: 0.02, "left", 0.5, "half", "Method: Flatten to " + fixed$(targetPitch, 0) + " Hz"
    endif
    
    Text: 0.45, "left", 0.5, "half", "Mean: " + fixed$(meanPitch, 1) + " Hz"
    Text: 0.7, "left", 0.5, "half", "Range: " + string$(min_pitch) + "-" + string$(max_pitch) + " Hz"
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
    
    removeObject: origPitchID, resPitchID
endif

# ============================================================
# CLEANUP
# ============================================================

removeObject: manipID, origPitchTierID, newPitchTierID

# ============================================================
# OUTPUT
# ============================================================

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: ""
appendInfoLine: "Created: ", originalName$, "_F0_", presetName$

if play_result
    selectObject: resultID
    Play
endif
