# ============================================================
# Praat AudioTools - Pitch_Morphing_Between_Targets.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Pitch Morphing Between Targets - interpolates between
#   user-defined pitch waypoints with elastic curves, overshoot,
#   tension, and vibrato. Creates expressive pitch sequences.
#
# Changelog v0.4.1: compact Summary typography/spacing; collision-safe gap after bottom-axis labels; DSP/analysis unchanged.
# Changelog v0.4: visualization standardization only - unified typography, summary/full-page Picture framing; DSP/analysis unchanged.
# Changelog v0.4:
#   - Robust target parser: requires at least 2 finite numeric targets.
#   - Overshoot, tension, and vibrato amount can be set to 0.
#   - Tension is now a bounded semitone offset, not a multiplier.
#   - Vibrato frequency is now true Hz, based on absolute time.
#   - Overshoot is a bounded spring-like semitone deviation.
#   - Analysis range is separated from synthesis safety limits.
#   - Stops cleanly when no usable voiced pitch is detected.
#   - Preserves the original channel count by applying one shared
#     morph PitchTier independently to every source channel.
#   - Supports arbitrary source xmin/xmax consistently.
#   - Peak protection is attenuation-only.
#   - Visualization layout/style is preserved; only coordinate bugs fixed.
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
n_channels = Get number of channels

# === Form ===
form Pitch Morphing Between Targets v0.4.1
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
    real Overshoot_factor 0.4
    
    comment === Dynamics ===
    real Tension_strength 0.1
    real Vibrato_amount 0.3
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

# === Validation ===
if dur <= 0
    exitScript: "The selected Sound has no positive duration."
endif
if morph_smoothness <= 0
    exitScript: "Morph_smoothness must be greater than zero."
endif
if overshoot_factor < 0
    exitScript: "Overshoot_factor must be zero or greater."
endif
if tension_strength < 0
    exitScript: "Tension_strength must be zero or greater."
endif
if vibrato_amount < 0
    exitScript: "Vibrato_amount must be zero or greater."
endif
if vibrato_frequency <= 0
    exitScript: "Vibrato_frequency must be greater than zero."
endif
if time_step <= 0
    exitScript: "Time_step must be greater than zero."
endif
if minimum_pitch <= 0 or maximum_pitch <= minimum_pitch
    exitScript: "Minimum_pitch / Maximum_pitch are invalid."
endif
if maximum_pitch >= 0.45 * orig_sr
    exitScript: "Maximum_pitch must be below 45% of the source sampling frequency."
endif

# === Parse Target Pitches ===
# Count underscore-separated tokens.
n_targets = 1
for ci from 1 to length(target_pitches$)
    if mid$(target_pitches$, ci, 1) = "_"
        n_targets += 1
    endif
endfor

if n_targets < 2
    exitScript: "Target_pitches must contain at least two underscore-separated values."
endif

targetNum# = zero#(n_targets)
targets$ = target_pitches$ + "_"

for tIdx from 1 to n_targets
    sep = index(targets$, "_")
    if sep <= 1
        exitScript: "Target_pitches contains an empty or malformed value."
    endif

    thisVal$ = left$(targets$, sep - 1)
    thisVal = number(thisVal$)

    if thisVal = undefined
        exitScript: "Target_pitches contains a non-numeric value: " + thisVal$
    endif
    if abs(thisVal) > 120
        exitScript: "Target pitch values must stay between -120 and +120 semitones."
    endif

    targetNum#[tIdx] = thisVal
    targets$ = right$(targets$, length(targets$) - sep)
endfor

# === Info ===
writeInfoLine: "=== Pitch Morphing Between Targets v0.4.1 ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(dur, 2), " s, ", n_channels, " ch)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Targets (", n_targets, "): ", target_pitches$
appendInfoLine: "Smoothness: ", morph_smoothness
appendInfoLine: "Overshoot: ", overshoot_factor
appendInfoLine: "Tension: ", tension_strength
appendInfoLine: "Vibrato: ", vibrato_amount, " st @ ", vibrato_frequency, " Hz"
appendInfoLine: ""

# === Number of Curve Points ===
npoints = round(dur / 0.01)
if npoints < 200
    npoints = 200
endif
if npoints > 2000
    npoints = 2000
endif

# === Mono analysis reference ===
selectObject: original
if n_channels > 1
    analysisMono = Convert to mono
else
    analysisMono = Copy: "PMBT_analysis"
endif

selectObject: analysisMono
tmpPitch = To Pitch: time_step, minimum_pitch, maximum_pitch
selectObject: tmpPitch
voiced_frames = Count voiced frames
median_f0 = Get quantile: 0, 0, 0.5, "Hertz"

if voiced_frames < 1 or median_f0 = undefined or median_f0 <= 0
    removeObject: tmpPitch, analysisMono
    exitScript: "No usable voiced pitch was detected in the selected analysis range."
endif

appendInfoLine: "Median pitch: ", fixed$(median_f0, 1), " Hz"
removeObject: tmpPitch, analysisMono

# === Create Pitch Tier ===
appendInfoLine: ""
appendInfoLine: "Building morph curve..."

Create PitchTier: "morph_pitch", xmin, xmax
pitchTier = selected("PitchTier")

# Store for visualization
maxVizPoints = min(npoints, 500)
if maxVizPoints < 1
    maxVizPoints = 1
endif
vizTimes# = zero#(maxVizPoints)
vizPitch# = zero#(maxVizPoints)
vizFilled# = zero#(maxVizPoints)
vizStep = npoints / maxVizPoints

# Synthesis safety is independent from analysis range.
synth_floor = 20
synth_ceil = 0.45 * orig_sr
limited_points = 0

# === Build Morphing Pitch Curve ===
for i from 0 to npoints - 1
    t = xmin + (i / (npoints - 1)) * dur
    rel_t = t - xmin
    u = (rel_t / dur) * (n_targets - 1)

    target_low = floor(u) + 1
    target_high = target_low + 1

    if target_high > n_targets
        target_high = n_targets
        target_low = n_targets
    endif

    fraction = u - floor(u)
    if target_low = n_targets
        fraction = 0
    endif

    # Elastic interpolation curve.
    if fraction > 0 and fraction < 1
        a = fraction ^ morph_smoothness
        b = (1 - fraction) ^ morph_smoothness
        elastic_curve = a / (a + b)
    elsif fraction <= 0
        elastic_curve = 0
    else
        elastic_curve = 1
    endif

    pitch_low = targetNum#[target_low]
    pitch_high = targetNum#[target_high]
    pitch_distance = abs(pitch_high - pitch_low)

    # Base interpolated semitone path.
    base_pitch_st = pitch_low + elastic_curve * (pitch_high - pitch_low)

    # Spring-like overshoot: bounded in semitones and zero at both ends.
    overshoot_st = overshoot_factor * pitch_distance
        ... * sin(2 * pi * fraction) * sin(pi * fraction)

    # Tension: bounded semitone deviation around the path, never a multiplier.
    tension_st = tension_strength * pitch_distance
        ... * sin(3 * pi * fraction) * sin(pi * fraction)

    # True-Hz vibrato, strongest in the middle of each transition.
    transition_env = 1 - abs(2 * fraction - 1)
    if target_low = n_targets
        transition_env = 0
    endif
    vibrato_st = vibrato_amount
        ... * sin(2 * pi * vibrato_frequency * rel_t) * transition_env

    final_pitch_st = base_pitch_st + overshoot_st + tension_st + vibrato_st

    # Convert semitones to frequency.
    new_f0 = median_f0 * (2 ^ (final_pitch_st / 12))

    if new_f0 < synth_floor
        new_f0 = synth_floor
        limited_points += 1
    elsif new_f0 > synth_ceil
        new_f0 = synth_ceil
        limited_points += 1
    endif

    selectObject: pitchTier
    Add point: t, new_f0

    # Visualization stores the actual semitone curve and works for any xmin.
    vizIdx = floor(i / vizStep) + 1
    if vizIdx >= 1 and vizIdx <= maxVizPoints
        if vizFilled#[vizIdx] = 0
            vizTimes#[vizIdx] = t
            vizPitch#[vizIdx] = final_pitch_st
            vizFilled#[vizIdx] = 1
        endif
    endif
endfor

if limited_points > 0
    appendInfoLine: "Sampling-safe limits applied: ", limited_points, " curve point(s)"
endif

# === Resynthesize each original channel with the shared PitchTier ===
appendInfoLine: "Resynthesizing ", n_channels, " channel(s)..."
channelResults# = zero#(n_channels)

for ch from 1 to n_channels
    selectObject: original
    if n_channels = 1
        channelWork = Copy: "PMBT_ch1"
    else
        channelWork = Extract one channel: ch
        Rename: "PMBT_ch" + string$(ch)
    endif

    selectObject: channelWork
    manipulation = To Manipulation: time_step, minimum_pitch, maximum_pitch

    selectObject: manipulation
    plusObject: pitchTier
    Replace pitch tier

    selectObject: manipulation
    channelResult = Get resynthesis (overlap-add)
    Rename: "PMBT_result_ch" + string$(ch)
    channelResults#[ch] = channelResult

    removeObject: manipulation, channelWork
endfor

# Rebuild exact original channel count.
Create Sound from formula: "PMBT_result_build", n_channels,
    ... xmin, xmax, orig_sr, "0"
result = selected("Sound")

for ch from 1 to n_channels
    selectObject: result
    Formula (part): xmin, xmax, ch, ch,
        ... "object[" + string$(channelResults#[ch]) + ", 1, col]"
    removeObject: channelResults#[ch]
endfor

selectObject: result
Rename: originalName$ + "_morph_" + presetName$

# Attenuation-only peak protection.
result_peak = Get absolute extremum: 0, 0, "None"
if result_peak > 0.95
    Scale peak: 0.95
    safetyApplied = 1
else
    safetyApplied = 0
endif

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Pitch Morphing Between Targets v0.4.1: " + originalName$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.6, 7.6, 0.7, 1.4
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
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
    firstViz = 0
    for vp from 1 to maxVizPoints
        if vizFilled#[vp] = 1
            if firstViz = 0
                minP = vizPitch#[vp]
                maxP = vizPitch#[vp]
                firstViz = 1
            else
                if vizPitch#[vp] < minP
                    minP = vizPitch#[vp]
                endif
                if vizPitch#[vp] > maxP
                    maxP = vizPitch#[vp]
                endif
            endif
        endif
    endfor

    if firstViz = 0
        minP = -3
        maxP = 3
    endif
    
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
        if vizFilled#[vp] = 1 and vizFilled#[vp - 1] = 1
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
    legendX = xmin + 0.03 * dur
    legendY = maxP + 0.55 * pMargin
    Colour: "{0.8, 0.5, 0.5}"
    Text: legendX, "left", legendY, "half", "Targets"
    Colour: "{0.5, 0.4, 0.7}"
    Text: legendX + 0.16 * dur, "left", legendY, "half", "Morph"
    
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
        Font size: 6
        Text: tgt, "centre", textY, "half", fixed$(tgtPitch, 1)
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Targets"
    
    # Stats
    Select outer viewport: 0, 8, 5.4, 5.7
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Targets: " + string$(n_targets) + " | Smooth: " + fixed$(morph_smoothness, 1) + " | Overshoot: " + fixed$(overshoot_factor, 2) + " | Vibrato: " + fixed$(vibrato_amount, 2)
    
    Font size: 10
    Colour: "Black"

    # ----------------------------------------------------------
    # Summary strip
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.82, 6.38
    Select inner viewport: 0.60, 7.70, 5.82 + 0.04, 6.38 - 0.04
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.72, "half", "##Summary##"
    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.02, "left", 0.45, "half", "Target interpolation • morph trajectory • resynthesized output"
    Text: 0.02, "left", 0.20, "half", "Pitch Morphing Between Targets • run parameters are reported in the Info window"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    pageHeight = 6.48
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# === Cleanup ===
removeObject: pitchTier

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Channels preserved: ", n_channels
appendInfoLine: "Peak safety applied: ", safetyApplied

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result
