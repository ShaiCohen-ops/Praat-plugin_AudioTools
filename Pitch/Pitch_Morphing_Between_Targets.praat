# ============================================================
# Praat AudioTools - Pitch_Morphing_Between_Targets.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Pitch Morphing Between Targets - interpolates between
#   user-defined pitch waypoints with elastic curves, overshoot,
#   tension, and vibrato. Creates expressive pitch sequences.
#
# Changelog v0.2:
#   - Modern syntax
#   - Fixed input check
#   - Added visualization
#   - Fixed array handling (no indexed string variables)
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
orig_sr = Get sampling frequency
xmin = Get start time
xmax = Get end time
dur = xmax - xmin

# === Form ===
form Pitch Morphing Between Targets
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Manual (configure below)
        option Gentle Waves
        option Emotional Arcs
        option Dramatic Leaps
        option Chromatic Walk
        option Microtonal Glide
        option Tension Build
        option Chaotic Dance
    
    comment === Target Pitches ===
    sentence Target_pitches 0_12_-8_15_-12_20_5_-5
    comment (underscore-separated semitone values)
    
    comment === Morphing Behavior ===
    positive Morph_smoothness 1.5
    positive Overshoot_factor 0.4
    
    comment === Dynamics ===
    positive Tension_strength 0.1
    positive Vibrato_amount 0.3
    positive Vibrato_frequency 25
    
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
    # Gentle Waves
    target_pitches$ = "0_3_-2_5_-1_2_0"
    morph_smoothness = 2.0
    overshoot_factor = 0.2
    tension_strength = 0.05
    vibrato_amount = 0.2
    presetName$ = "Gentle"
elsif preset = 3
    # Emotional Arcs
    target_pitches$ = "0_7_-5_12_-8_15_-12"
    morph_smoothness = 1.8
    overshoot_factor = 0.3
    tension_strength = 0.15
    vibrato_amount = 0.4
    presetName$ = "Emotional"
elsif preset = 4
    # Dramatic Leaps
    target_pitches$ = "0_12_-12_24_-24_12_0"
    morph_smoothness = 1.2
    overshoot_factor = 0.6
    tension_strength = 0.25
    vibrato_amount = 0.5
    presetName$ = "Dramatic"
elsif preset = 5
    # Chromatic Walk
    target_pitches$ = "0_2_4_5_7_9_11_12_11_9_7_5_4_2_0"
    morph_smoothness = 1.5
    overshoot_factor = 0.1
    tension_strength = 0.08
    vibrato_amount = 0.15
    presetName$ = "Chromatic"
elsif preset = 6
    # Microtonal Glide
    target_pitches$ = "0_1.5_-1_2.5_-0.5_1_-1.5_0.5"
    morph_smoothness = 2.5
    overshoot_factor = 0.15
    tension_strength = 0.03
    vibrato_amount = 0.1
    presetName$ = "Microtonal"
elsif preset = 7
    # Tension Build
    target_pitches$ = "0_3_1_6_2_9_4_12_5"
    morph_smoothness = 1.3
    overshoot_factor = 0.4
    tension_strength = 0.3
    vibrato_amount = 0.25
    presetName$ = "Tension"
elsif preset = 8
    # Chaotic Dance
    target_pitches$ = "0_7_-3_15_-8_5_12_-5_20_-12"
    morph_smoothness = 0.8
    overshoot_factor = 0.8
    tension_strength = 0.4
    vibrato_amount = 0.6
    presetName$ = "Chaotic"
else
    presetName$ = "Manual"
endif

# === Parse Target Pitches ===
# First pass: count targets
tempTargets$ = target_pitches$ + "_"
tempTargets$ = replace$(tempTargets$, "_", " ", 0)
n_targets = 0

repeat
    space_pos = index(tempTargets$, " ")
    if space_pos > 1
        n_targets = n_targets + 1
        tempTargets$ = right$(tempTargets$, length(tempTargets$) - space_pos)
    endif
until space_pos <= 1

# Create array with known size
targetNum# = zero#(n_targets)

# Second pass: parse and store directly into numeric array
targets$ = target_pitches$ + "_"
targets$ = replace$(targets$, "_", " ", 0)
tIdx = 0

repeat
    space_pos = index(targets$, " ")
    if space_pos > 1
        tIdx = tIdx + 1
        thisVal$ = left$(targets$, space_pos - 1)
        targetNum#[tIdx] = number(thisVal$)
        targets$ = right$(targets$, length(targets$) - space_pos)
    endif
until space_pos <= 1

# === Info ===
writeInfoLine: "=== Pitch Morphing Between Targets ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(dur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Targets (", n_targets, "): ", target_pitches$
appendInfoLine: "Smoothness: ", morph_smoothness
appendInfoLine: "Overshoot: ", overshoot_factor
appendInfoLine: "Tension: ", tension_strength
appendInfoLine: "Vibrato: ", vibrato_amount, " @ ", vibrato_frequency, " Hz"
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
Copy: originalName$ + "_morph_tmp"
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
appendInfoLine: "Building morph curve..."

Create PitchTier: "morph_pitch", xmin, xmax
pitchTier = selected("PitchTier")

# Store for visualization
maxVizPoints = min(npoints, 500)
vizTimes# = zero#(maxVizPoints)
vizPitch# = zero#(maxVizPoints)
vizStep = npoints / maxVizPoints

# === Build Morphing Pitch Curve ===
for i from 0 to npoints - 1
    t = xmin + (i / (npoints - 1)) * dur
    u = (t - xmin) / dur * (n_targets - 1)
    
    target_low = floor(u) + 1
    target_high = target_low + 1
    
    if target_high > n_targets
        target_high = n_targets
        target_low = n_targets
    endif
    
    fraction = u - floor(u)
    
    # Elastic interpolation curve
    if fraction > 0 and fraction < 1
        elastic_curve = fraction ^ morph_smoothness / (fraction ^ morph_smoothness + (1 - fraction) ^ morph_smoothness)
    elsif fraction <= 0
        elastic_curve = 0
    else
        elastic_curve = 1
    endif
    
    # Overshoot (spring bounce)
    overshoot = overshoot_factor * sin(fraction * pi) * (1 - fraction) * fraction
    smooth_fraction = elastic_curve + overshoot
    
    pitch_low = targetNum#[target_low]
    pitch_high = targetNum#[target_high]
    
    # Tension effect based on pitch distance
    pitch_distance = abs(pitch_high - pitch_low)
    tension = 1 + tension_strength * pitch_distance * sin(fraction * 3 * pi)
    
    # Interpolated pitch
    interpolated_pitch = pitch_low + smooth_fraction * (pitch_high - pitch_low)
    
    # Vibrato (strongest in middle of transition)
    vibrato = vibrato_amount * sin(fraction * vibrato_frequency * pi) * (1 - abs(2 * fraction - 1))
    
    # Final pitch in semitones
    final_pitch_st = interpolated_pitch * tension + vibrato
    
    # Store for visualization
    vizIdx = floor(i / vizStep) + 1
    if vizIdx >= 1 and vizIdx <= maxVizPoints
        if vizTimes#[vizIdx] = 0
            vizTimes#[vizIdx] = t
            vizPitch#[vizIdx] = final_pitch_st
        endif
    endif
    
    # Convert semitones to frequency
    new_f0 = median_f0 * (2 ^ (final_pitch_st / 12))
    
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
Rename: originalName$ + "_morph_" + presetName$

selectObject: result
Scale peak: 0.95

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Pitch Morphing: " + originalName$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.6, 7.6, 0.7, 1.4
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.6, 2.5
    Select inner viewport: 0.6, 7.6, 1.7, 2.4
    selectObject: result
    Colour: "{0.6, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Morphed"
    Text bottom: "yes", "Time (s)"
    
    # Morph curve
    Select outer viewport: 0, 8, 2.7, 4.5
    Select inner viewport: 0.6, 7.6, 2.9, 4.4
    
    # Find range
    minP = vizPitch#[1]
    maxP = vizPitch#[1]
    for vp from 2 to maxVizPoints
        if vizPitch#[vp] < minP
            minP = vizPitch#[vp]
        endif
        if vizPitch#[vp] > maxP
            maxP = vizPitch#[vp]
        endif
    endfor
    
    pMargin = (maxP - minP) * 0.15
    if pMargin < 3
        pMargin = 3
    endif
    
    Axes: xmin, xmax, minP - pMargin, maxP + pMargin
    Paint rectangle: "{0.95, 0.95, 0.95}", xmin, xmax, minP - pMargin, maxP + pMargin
    
    # Zero line
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    Draw line: xmin, 0, xmax, 0
    Solid line
    
    # Draw target points
    for tgt from 1 to n_targets
        tgtTime = xmin + ((tgt - 1) / (n_targets - 1)) * dur
        tgtPitch = targetNum#[tgt]
        
        Colour: "{0.8, 0.5, 0.5}"
        Paint circle (mm): "{0.8, 0.5, 0.5}", tgtTime, tgtPitch, 2
    endfor
    
    # Draw morph curve
    Colour: "{0.5, 0.4, 0.7}"
    Line width: 1.5
    for vp from 2 to maxVizPoints
        if vizTimes#[vp] > 0 and vizTimes#[vp - 1] > 0
            Draw line: vizTimes#[vp - 1], vizPitch#[vp - 1], vizTimes#[vp], vizPitch#[vp]
        endif
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Semitones"
    Text bottom: "yes", "Time (s)"
    
    # Legend
    Font size: 6
    Colour: "{0.8, 0.5, 0.5}"
    Text: 0.02, "left", 1.05, "half", "● Targets"
    Colour: "{0.5, 0.4, 0.7}"
    Text: 0.12, "left", 1.05, "half", "— Morph"
    
    # Target sequence display
    Select outer viewport: 0, 8, 4.7, 5.3
    Select inner viewport: 0.6, 7.6, 4.8, 5.2
    
    Axes: 0, n_targets + 1, minP - pMargin, maxP + pMargin
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, n_targets + 1, minP - pMargin, maxP + pMargin
    
    # Zero line
    Colour: "{0.8, 0.8, 0.8}"
    Dotted line
    Draw line: 0, 0, n_targets + 1, 0
    Solid line
    
    # Draw targets as bars
    for tgt from 1 to n_targets
        tgtPitch = targetNum#[tgt]
        if tgtPitch >= 0
            Colour: "{0.5, 0.7, 0.6}"
            Paint rectangle: "{0.5, 0.7, 0.6}", tgt - 0.3, tgt + 0.3, 0, tgtPitch
            textY = tgtPitch + pMargin * 0.3
        else
            Colour: "{0.7, 0.5, 0.6}"
            Paint rectangle: "{0.7, 0.5, 0.6}", tgt - 0.3, tgt + 0.3, tgtPitch, 0
            textY = tgtPitch - pMargin * 0.3
        endif
        
        Colour: "Black"
        Font size: 5
        Text: tgt, "centre", textY, "half", fixed$(tgtPitch, 1)
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Targets"
    
    # Stats
    Select outer viewport: 0, 8, 5.4, 5.7
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Targets: " + string$(n_targets) + " | Smooth: " + fixed$(morph_smoothness, 1) + " | Overshoot: " + fixed$(overshoot_factor, 2) + " | Vibrato: " + fixed$(vibrato_amount, 2)
    
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