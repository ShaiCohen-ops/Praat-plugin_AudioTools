# ============================================================
# Praat AudioTools - Exponential_Pitch_Glide.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Exponential Pitch Glide - creates smooth pitch rises or
#   falls using exponential curves. Steepness controls how
#   quickly the pitch change occurs.
#
# Changelog v0.2:
#   - Modern syntax
#   - Added glide direction (up/down)
#   - Added visualization
#   - Fixed input check
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
xmin = Get start time
xmax = Get end time
dur = xmax - xmin
fs = Get sampling frequency

# === Form ===
form Exponential Pitch Glide
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Manual (configure below)
        option Gentle Glide Up
        option Moderate Rise
        option Dramatic Sweep Up
        option Extreme Rocket
        option Slow Build
        option Quick Jump
        option Cinematic Rise
        option Gentle Glide Down
        option Dramatic Fall
        option Dive Bomb
    
    comment === Glide Parameters ===
    optionmenu Direction 1
        option Up
        option Down
    positive Semitones_change 7
    positive Curve_steepness 3
    comment (higher = faster initial change)
    
    comment === Pitch Analysis ===
    positive Time_step 0.005
    positive Minimum_pitch 50
    positive Maximum_pitch 900
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Gentle Glide Up
    direction = 1
    semitones_change = 5
    curve_steepness = 2
elsif preset = 3
    # Moderate Rise
    direction = 1
    semitones_change = 8
    curve_steepness = 3
elsif preset = 4
    # Dramatic Sweep Up
    direction = 1
    semitones_change = 12
    curve_steepness = 4
elsif preset = 5
    # Extreme Rocket
    direction = 1
    semitones_change = 24
    curve_steepness = 6
elsif preset = 6
    # Slow Build
    direction = 1
    semitones_change = 6
    curve_steepness = 1
elsif preset = 7
    # Quick Jump
    direction = 1
    semitones_change = 4
    curve_steepness = 8
elsif preset = 8
    # Cinematic Rise
    direction = 1
    semitones_change = 18
    curve_steepness = 2.5
elsif preset = 9
    # Gentle Glide Down
    direction = 2
    semitones_change = 5
    curve_steepness = 2
elsif preset = 10
    # Dramatic Fall
    direction = 2
    semitones_change = 12
    curve_steepness = 4
elsif preset = 11
    # Dive Bomb
    direction = 2
    semitones_change = 24
    curve_steepness = 6
endif

# === Get Preset Name ===
if preset = 1
    presetName$ = "Manual"
elsif preset = 2
    presetName$ = "Gentle Up"
elsif preset = 3
    presetName$ = "Moderate Rise"
elsif preset = 4
    presetName$ = "Dramatic Sweep"
elsif preset = 5
    presetName$ = "Extreme Rocket"
elsif preset = 6
    presetName$ = "Slow Build"
elsif preset = 7
    presetName$ = "Quick Jump"
elsif preset = 8
    presetName$ = "Cinematic Rise"
elsif preset = 9
    presetName$ = "Gentle Down"
elsif preset = 10
    presetName$ = "Dramatic Fall"
else
    presetName$ = "Dive Bomb"
endif

if direction = 1
    dirName$ = "Up"
    signMultiplier = 1
else
    dirName$ = "Down"
    signMultiplier = -1
endif

# === Info ===
writeInfoLine: "=== Exponential Pitch Glide ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(dur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Direction: ", dirName$
appendInfoLine: "Semitones: ", semitones_change
appendInfoLine: "Steepness: ", curve_steepness
appendInfoLine: ""

# === Calculate Number of Points ===
npoints = round(dur / 0.01)
if npoints < 200
    npoints = 200
endif
if npoints > 2000
    npoints = 2000
endif

# === Create Working Copy and Manipulation ===
selectObject: original
Copy: originalName$ + "_tmp"
tmpSound = selected("Sound")

selectObject: tmpSound
manipulation = To Manipulation: time_step, minimum_pitch, maximum_pitch

# === Get Median Pitch ===
selectObject: tmpSound
To Pitch: time_step, minimum_pitch, maximum_pitch
tmpPitch = selected("Pitch")
median_f0 = Get quantile: 0, 0, 0.5, "Hertz"

if median_f0 = undefined
    median_f0 = 200
    appendInfoLine: "No pitch detected, using default: ", median_f0, " Hz"
else
    appendInfoLine: "Median pitch: ", fixed$(median_f0, 1), " Hz"
endif

removeObject: tmpPitch

# === Create Pitch Tier ===
appendInfoLine: ""
appendInfoLine: "Building glide curve..."

Create PitchTier: "glide_pitch", xmin, xmax
pitchTier = selected("PitchTier")

# Store for visualization
maxVizPoints = min(npoints, 500)
vizTimes# = zero#(maxVizPoints)
vizShifts# = zero#(maxVizPoints)
vizStep = npoints / maxVizPoints

# === Build Exponential Glide Curve ===
for i from 0 to npoints - 1
    t = xmin + (i / (npoints - 1)) * dur
    
    # Normalized position (0 to 1)
    u = i / (npoints - 1)
    
    # Exponential curve (normalized 0 to 1)
    if curve_steepness > 0.001
        expFactor = (1 - exp(-curve_steepness * u)) / (1 - exp(-curve_steepness))
    else
        expFactor = u
    endif
    
    # Calculate semitones shift (with direction)
    semitones_shift = signMultiplier * semitones_change * expFactor
    
    # Store for visualization
    vizIdx = floor(i / vizStep) + 1
    if vizIdx <= maxVizPoints and vizIdx >= 1
        if vizTimes#[vizIdx] = 0
            vizTimes#[vizIdx] = t
            vizShifts#[vizIdx] = semitones_shift
        endif
    endif
    
    # Convert to frequency
    new_f0 = median_f0 * (2 ^ (semitones_shift / 12))
    
    # Clamp to range
    if new_f0 < minimum_pitch
        new_f0 = minimum_pitch
    elsif new_f0 > maximum_pitch
        new_f0 = maximum_pitch
    endif
    
    selectObject: pitchTier
    Add point: t, new_f0
endfor

# === Replace Pitch Tier ===
selectObject: manipulation, pitchTier
Replace pitch tier

# === Resynthesize ===
appendInfoLine: "Resynthesizing..."
selectObject: manipulation
result = Get resynthesis (overlap-add)
Rename: originalName$ + "_glide" + dirName$

selectObject: result
Scale peak: 0.95

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Exponential Pitch Glide: " + originalName$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.7
    Select inner viewport: 0.6, 7.6, 0.7, 1.6
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.8, 2.9
    Select inner viewport: 0.6, 7.6, 1.9, 2.8
    selectObject: result
    if direction = 1
        Colour: "{0.5, 0.7, 0.6}"
    else
        Colour: "{0.7, 0.5, 0.6}"
    endif
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Glide " + dirName$
    Text bottom: "yes", "Time (s)"
    
    # Glide curve
    Select outer viewport: 0, 8, 3.1, 4.7
    Select inner viewport: 0.6, 7.6, 3.3, 4.6
    
    # Determine range
    if direction = 1
        minShift = -1
        maxShift = semitones_change + 1
    else
        minShift = -semitones_change - 1
        maxShift = 1
    endif
    
    Axes: xmin, xmax, minShift, maxShift
    Paint rectangle: "{0.95, 0.95, 0.95}", xmin, xmax, minShift, maxShift
    
    # Zero line
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    Draw line: xmin, 0, xmax, 0
    Solid line
    
    # Draw glide curve
    if direction = 1
        Colour: "{0.4, 0.7, 0.5}"
    else
        Colour: "{0.7, 0.4, 0.5}"
    endif
    Line width: 2
    for vp from 2 to maxVizPoints
        if vizTimes#[vp] > 0 and vizTimes#[vp - 1] > 0
            Draw line: vizTimes#[vp - 1], vizShifts#[vp - 1], vizTimes#[vp], vizShifts#[vp]
        endif
    endfor
    Line width: 1
    
    # End point marker
    Paint circle (mm): "Black", xmax, signMultiplier * semitones_change, 1.5
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Semitones"
    Text bottom: "yes", "Time (s)"
    
    # Curve shape comparison (different steepness)
    Select outer viewport: 0, 8, 4.9, 5.3
    Select inner viewport: 0.6, 7.6, 5.0, 5.25
    
    Axes: 0, 1, 0, 1.1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1.1
    
    # Draw curves for different steepness values
    steepVals# = {1, 3, 6}
    steepColors$# = {"{0.7, 0.7, 0.7}", "{0.5, 0.5, 0.5}", "{0.3, 0.3, 0.3}"}
    
    for sv to 3
        steep = steepVals#[sv]
        Colour: steepColors$#[sv]
        
        prevX = 0
        prevY = 0
        for pt from 1 to 50
            px = (pt - 1) / 49
            if steep > 0.001
                py = (1 - exp(-steep * px)) / (1 - exp(-steep))
            else
                py = px
            endif
            
            if pt > 1
                Draw line: prevX, prevY, px, py
            endif
            prevX = px
            prevY = py
        endfor
    endfor
    
    # Mark current steepness
    Colour: "{0.8, 0.4, 0.4}"
    Line width: 2
    prevX = 0
    prevY = 0
    for pt from 1 to 50
        px = (pt - 1) / 49
        if curve_steepness > 0.001
            py = (1 - exp(-curve_steepness * px)) / (1 - exp(-curve_steepness))
        else
            py = px
        endif
        
        if pt > 1
            Draw line: prevX, prevY, px, py
        endif
        prevX = px
        prevY = py
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Shape"
    Text bottom: "yes", "Steepness: 1 (gray) → 6 (black), current=" + fixed$(curve_steepness, 1) + " (red)"
    
    Font size: 10
    Colour: "Black"
endif

# === Cleanup ===
removeObject: tmpSound, manipulation, pitchTier

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Final pitch: ", fixed$(median_f0 * (2 ^ (signMultiplier * semitones_change / 12)), 1), " Hz"

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result