# ============================================================
# Praat AudioTools - Spiral_Pitch_Dance.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spiral Pitch Dance - creates accelerating sinusoidal pitch
#   movement. The spiral speeds up over time, creating a Doppler-
#   like flyby effect. Great for transitions and buildups.
#
# Changelog v0.2:
#   - Modern syntax
#   - Fixed input check
#   - Added visualization
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
orig$ = selected$("Sound")

selectObject: original
xmin = Get start time
xmax = Get end time
dur = xmax - xmin

# === Form ===
form Spiral Pitch Dance
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Manual (configure below)
        option Gentle Spiral
        option Moderate Spiral
        option Aggressive Spiral
        option Extreme Spiral
        option Fast Rotation
        option Slow Evolution
        option Psychedelic Swirl
    
    comment === Spiral Parameters ===
    positive Spirals 2
    positive Semitone_range 24
    positive Acceleration 1.5
    
    comment === Analysis ===
    positive Time_step 0.005
    positive Floor_pitch 50
    positive Ceiling_pitch 1200
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Gentle Spiral
    spirals = 1.5
    semitone_range = 12
    acceleration = 1.3
    presetName$ = "Gentle"
elsif preset = 3
    # Moderate Spiral
    spirals = 2
    semitone_range = 24
    acceleration = 1.5
    presetName$ = "Moderate"
elsif preset = 4
    # Aggressive Spiral
    spirals = 3
    semitone_range = 36
    acceleration = 1.8
    presetName$ = "Aggressive"
elsif preset = 5
    # Extreme Spiral
    spirals = 5
    semitone_range = 48
    acceleration = 2.2
    presetName$ = "Extreme"
elsif preset = 6
    # Fast Rotation
    spirals = 4
    semitone_range = 30
    acceleration = 2.5
    presetName$ = "Fast"
elsif preset = 7
    # Slow Evolution
    spirals = 1
    semitone_range = 18
    acceleration = 1.2
    presetName$ = "Slow"
elsif preset = 8
    # Psychedelic Swirl
    spirals = 8
    semitone_range = 60
    acceleration = 3.0
    presetName$ = "Psychedelic"
else
    presetName$ = "Manual"
endif

# === Info ===
writeInfoLine: "=== Spiral Pitch Dance ==="
appendInfoLine: "Source: ", orig$, " (", fixed$(dur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Spirals: ", spirals
appendInfoLine: "Semitone range: ±", semitone_range
appendInfoLine: "Acceleration: ", acceleration
appendInfoLine: ""

# === Create Working Copy ===
selectObject: original
Copy: "temp"
tmpSound = selected("Sound")

selectObject: tmpSound
manipulation = To Manipulation: time_step, floor_pitch, ceiling_pitch

# === Get Median Pitch ===
selectObject: tmpSound
To Pitch: time_step, floor_pitch, ceiling_pitch
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
appendInfoLine: "Building spiral pitch curve..."

Create PitchTier: "spiral_pitch", xmin, xmax
pitchTier = selected("PitchTier")

# Dense point sampling
npoints = round(dur / 0.01)
if npoints < 200
    npoints = 200
endif
if npoints > 2000
    npoints = 2000
endif

# Store for visualization
maxVizPoints = min(npoints, 500)
vizTimes# = zero#(maxVizPoints)
vizShifts# = zero#(maxVizPoints)
vizPhases# = zero#(maxVizPoints)
vizStep = npoints / maxVizPoints

# === Build Spiral Pitch Curve ===
for i from 0 to npoints - 1
    t = xmin + (i / (npoints - 1)) * dur
    
    # Normalized position (0 to 1)
    pos = i / (npoints - 1)
    
    # Accelerating phase
    phase = spirals * 2 * pi * (pos ^ acceleration)
    
    # Spiral oscillation
    spiral_value = sin(phase)
    
    # Calculate pitch shift in semitones
    pitch_shift_st = semitone_range * spiral_value
    
    # Store for visualization
    vizIdx = floor(i / vizStep) + 1
    if vizIdx >= 1 and vizIdx <= maxVizPoints
        if vizTimes#[vizIdx] = 0
            vizTimes#[vizIdx] = t
            vizShifts#[vizIdx] = pitch_shift_st
            vizPhases#[vizIdx] = phase
        endif
    endif
    
    # Convert to frequency ratio
    ratio = 2 ^ (pitch_shift_st / 12)
    
    # Apply ratio to median frequency
    new_f0 = median_f0 * ratio
    
    # Clamp to range
    if new_f0 < floor_pitch
        new_f0 = floor_pitch
    elsif new_f0 > ceiling_pitch
        new_f0 = ceiling_pitch
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
Rename: orig$ + "_spiral_" + presetName$

selectObject: result
Scale peak: 0.95

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Spiral Pitch Dance: " + orig$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.6, 7.6, 0.7, 1.3
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.5, 2.3
    Select inner viewport: 0.6, 7.6, 1.6, 2.2
    selectObject: result
    Colour: "{0.6, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Spiral"
    Text bottom: "yes", "Time (s)"
    
    # Pitch shift curve (spiral)
    Select outer viewport: 0, 8, 2.5, 4.0
    Select inner viewport: 0.6, 7.6, 2.7, 3.9
    
    sMargin = semitone_range * 0.15
    
    Axes: xmin, xmax, -semitone_range - sMargin, semitone_range + sMargin
    Paint rectangle: "{0.95, 0.95, 0.95}", xmin, xmax, -semitone_range - sMargin, semitone_range + sMargin
    
    # Zero line
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    Draw line: xmin, 0, xmax, 0
    Solid line
    
    # Range lines
    Colour: "{0.85, 0.85, 0.85}"
    Dotted line
    Draw line: xmin, semitone_range, xmax, semitone_range
    Draw line: xmin, -semitone_range, xmax, -semitone_range
    Solid line
    
    # Draw spiral curve
    Colour: "{0.5, 0.4, 0.7}"
    Line width: 1.5
    for vp from 2 to maxVizPoints
        if vizTimes#[vp] > 0 and vizTimes#[vp - 1] > 0
            Draw line: vizTimes#[vp - 1], vizShifts#[vp - 1], vizTimes#[vp], vizShifts#[vp]
        endif
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Shift (st)"
    Text bottom: "yes", "Time (s)"
    
    # Phase/frequency indicator
    Select outer viewport: 0, 8, 4.2, 5.0
    Select inner viewport: 0.6, 7.6, 4.3, 4.9
    
    # Calculate instantaneous frequency at each point
    maxFreqViz = 0
    for vp from 2 to maxVizPoints
        if vizTimes#[vp] > vizTimes#[vp - 1]
            instFreq = (vizPhases#[vp] - vizPhases#[vp - 1]) / (2 * pi * (vizTimes#[vp] - vizTimes#[vp - 1]))
            if instFreq > maxFreqViz
                maxFreqViz = instFreq
            endif
        endif
    endfor
    
    if maxFreqViz < 1
        maxFreqViz = spirals * acceleration
    endif
    
    Axes: xmin, xmax, 0, maxFreqViz * 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", xmin, xmax, 0, maxFreqViz * 1.2
    
    # Draw frequency curve
    Colour: "{0.7, 0.5, 0.5}"
    for vp from 2 to maxVizPoints
        if vizTimes#[vp] > vizTimes#[vp - 1]
            instFreq = (vizPhases#[vp] - vizPhases#[vp - 1]) / (2 * pi * (vizTimes#[vp] - vizTimes#[vp - 1]))
            prevFreq = 0
            if vp > 2 and vizTimes#[vp - 1] > vizTimes#[vp - 2]
                prevFreq = (vizPhases#[vp - 1] - vizPhases#[vp - 2]) / (2 * pi * (vizTimes#[vp - 1] - vizTimes#[vp - 2]))
            else
                prevFreq = instFreq
            endif
            Draw line: vizTimes#[vp - 1], prevFreq, vizTimes#[vp], instFreq
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Spiral freq"
    Text bottom: "yes", "Time (s)"
    
    # Stats
    Select outer viewport: 0, 8, 5.1, 5.4
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Spirals: " + fixed$(spirals, 1) + " | Range: ±" + string$(semitone_range) + " st | Acceleration: " + fixed$(acceleration, 2)
    
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

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result
