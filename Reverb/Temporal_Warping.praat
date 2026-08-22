# ============================================================
# Praat AudioTools - Temporal_Warping.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.3.1 reviewed (2026)
# v1.3.1 (2026): Shared left panel-label rails and user-approved Summary geometry; DSP/analysis unchanged.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Progressive temporal warping through a parallel field of bounded,
#   monotonic time-remapping trajectories. Each trajectory reads the
#   original Sound at a smoothly delayed time; trajectories span from
#   mild to maximum displacement and are mixed into a warped wet field.
#   Warp_strength is the direct dry/warped-field mix, so the control is
#   perceptually meaningful and the effect remains clearly audible.
#
# Review changes v1.2:
#   - Replaced the over-conservative cascaded crossfade architecture
#     with a parallel bank of independent warped trajectories.
#   - Warp_strength now directly mixes dry and warped fields.
#   - Later/more-displaced trajectories receive progressively higher
#     weights, making the temporal deformation audible at medium values.
#   - Presets retuned for clearly differentiated audible results.
#   - Each trajectory remains monotonic and reads the immutable original.
#   - Wet tail is faded before dry/wet mixing.
#   - Maximum displacement remains bounded by source duration and the
#     requested displacement factor; no time folding or look-ahead.
#   - Stereo sources preserve their original dry L/R channels; mono
#     sources create two independently curved warped fields.
#   - One common down-only peak safeguard remains after stereo combine.
#   - Visualization reports actual path endpoint delays and curvature.
# ============================================================

form Temporal Warping
    comment Select exactly one Sound object first

    comment === Preset ===
    optionmenu Preset 1
        option Custom
        option Subtle Warp
        option Medium Warp
        option Heavy Warp
        option Extreme Warp
        option Dense Smear
        option Time Stretch Feel

    comment === Warp Parameters ===
    positive Tail_duration_s 3.0
    natural Number_of_warp_stages 6
    real Max_displacement_factor 0.1
    comment (maximum delayed path as a fraction of source duration)
    real Warp_strength 0.3
    comment (0 = dry/original, 1 = fully warped field)

    comment === Output ===
    positive Fadeout_duration_s 1.2
    boolean Show_visualization 1
    boolean Play_result 1
endform

# ============================================================
# INPUT AND PRESET SETUP
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalSound = selected("Sound")
originalName$ = selected$("Sound")

selectObject: originalSound
originalDuration = Get total duration
originalStart = Get start time
samplingRate = Get sampling frequency
channels = Get number of channels

if channels <> 1 and channels <> 2
    exitScript: "Temporal Warping currently supports mono or stereo Sound objects only."
endif

if originalDuration <= 0
    exitScript: "The selected Sound has zero duration."
endif

if samplingRate < 1000
    exitScript: "Sampling frequency is too low for Temporal Warping."
endif

# === Apply preset values ===
if preset = 2
    tail_duration_s = 2.0
    number_of_warp_stages = 4
    max_displacement_factor = 0.05
    warp_strength = 0.25
    fadeout_duration_s = 1.0
    presetName$ = "Subtle"
elsif preset = 3
    tail_duration_s = 3.0
    number_of_warp_stages = 6
    max_displacement_factor = 0.12
    warp_strength = 0.55
    fadeout_duration_s = 1.2
    presetName$ = "Medium"
elsif preset = 4
    tail_duration_s = 4.0
    number_of_warp_stages = 8
    max_displacement_factor = 0.25
    warp_strength = 0.75
    fadeout_duration_s = 1.5
    presetName$ = "Heavy"
elsif preset = 5
    tail_duration_s = 5.0
    number_of_warp_stages = 12
    max_displacement_factor = 0.45
    warp_strength = 0.90
    fadeout_duration_s = 2.0
    presetName$ = "Extreme"
elsif preset = 6
    tail_duration_s = 4.0
    number_of_warp_stages = 16
    max_displacement_factor = 0.20
    warp_strength = 0.80
    fadeout_duration_s = 2.0
    presetName$ = "Dense Smear"
elsif preset = 7
    tail_duration_s = 6.0
    number_of_warp_stages = 10
    max_displacement_factor = 0.35
    warp_strength = 0.90
    fadeout_duration_s = 2.5
    presetName$ = "Time Stretch Feel"
else
    presetName$ = "Custom"
endif

# === Validate / derive parameters ===
if number_of_warp_stages < 1
    exitScript: "Number of warp stages must be at least 1."
endif

if number_of_warp_stages > 64
    exitScript: "Number of warp stages is limited to 64 for performance and stability."
endif

effectiveFactor = max_displacement_factor
if effectiveFactor < 0
    effectiveFactor = 0
endif

# For the warp curve used below, a factor <= 0.60 keeps a one-stage
# custom setting safely monotonic even at the maximum curvature.
if effectiveFactor > 0.60
    effectiveFactor = 0.60
endif

effectiveStrength = warp_strength
if effectiveStrength < 0
    effectiveStrength = 0
elsif effectiveStrength > 1
    effectiveStrength = 1
endif

maxDisplacement = effectiveFactor * originalDuration

effectiveTail = tail_duration_s
if effectiveTail < maxDisplacement
    effectiveTail = maxDisplacement
endif

totalDuration = originalDuration + effectiveTail
fadeDuration = min(fadeout_duration_s, effectiveTail)
fadeStart = totalDuration - fadeDuration

# Warp_strength is used directly as the dry/warped-field mix.
dryGain = 1 - effectiveStrength
wetGain = effectiveStrength

# ============================================================
# GENERATE ACTUAL STAGE PARAMETERS ONCE
# ============================================================

# Positive sine weights avoid the old zero-displacement final stage.
# Independent bounded random factors are normalized so both channels
# have exactly maxDisplacement as their maximum cumulative path delay.
rawSumL = 0
rawSumR = 0
for stage from 1 to number_of_warp_stages
    shapeWeight = sin(pi * stage / (number_of_warp_stages + 1))

    rawL[stage] = shapeWeight * randomUniform(0.80, 1.20)
    rawR[stage] = shapeWeight * randomUniform(0.80, 1.20)
    rawSumL = rawSumL + rawL[stage]
    rawSumR = rawSumR + rawR[stage]

    # Bend modifies the local speed while keeping the normalized
    # curve monotonic: curve'(u) = 1 + bend*cos(2*pi*u), |bend| < 1.
    bendL[stage] = randomUniform(-0.35, 0.35)
    bendR[stage] = randomUniform(-0.35, 0.35)
endfor

cumulativeL = 0
cumulativeR = 0
for stage from 1 to number_of_warp_stages
    if maxDisplacement > 0
        stageDelayL[stage] = maxDisplacement * rawL[stage] / rawSumL
        stageDelayR[stage] = maxDisplacement * rawR[stage] / rawSumR
    else
        stageDelayL[stage] = 0
        stageDelayR[stage] = 0
    endif

    cumulativeL = cumulativeL + stageDelayL[stage]
    cumulativeR = cumulativeR + stageDelayR[stage]
    cumulativeDelayL[stage] = cumulativeL
    cumulativeDelayR[stage] = cumulativeR
endfor

# ============================================================
# INFO
# ============================================================

writeInfoLine: "=== Temporal Warping ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDuration, 3), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Sample rate: ", fixed$(samplingRate, 0), " Hz"
appendInfoLine: "Input channels: ", channels
appendInfoLine: "Warp stages: ", number_of_warp_stages
appendInfoLine: "Requested displacement factor: ", fixed$(max_displacement_factor, 3)
appendInfoLine: "Effective displacement factor: ", fixed$(effectiveFactor, 3)
appendInfoLine: "Maximum warped-path delay: ", fixed$(maxDisplacement * 1000, 1), " ms"
appendInfoLine: "Warp strength: ", fixed$(effectiveStrength, 3)
appendInfoLine: "Dry/Warp mix: ", fixed$(dryGain, 3), " / ", fixed$(wetGain, 3)
appendInfoLine: "Requested tail: ", fixed$(tail_duration_s, 3), " s"
appendInfoLine: "Effective tail: ", fixed$(effectiveTail, 3), " s"
appendInfoLine: "Fade: ", fixed$(fadeDuration, 3), " s"
appendInfoLine: ""
appendInfoLine: "Stage parameters:"
for stage from 1 to number_of_warp_stages
    appendInfoLine: "  ", stage, ": endpoint L=", fixed$(cumulativeDelayL[stage] * 1000, 2), " ms, R=", fixed$(cumulativeDelayR[stage] * 1000, 2), " ms, bend L/R=", fixed$(bendL[stage], 3), "/", fixed$(bendR[stage], 3)
endfor
appendInfoLine: ""
appendInfoLine: "Processing..."

# ============================================================
# BUILD PARALLEL WARP FIELD
# ============================================================

orig_id_str$ = string$(originalSound)
orig_start_str$ = string$(originalStart)
orig_dur_str$ = string$(originalDuration)
wet_gain_str$ = string$(wetGain)
dry_gain_str$ = string$(dryGain)

if effectiveStrength = 0
    # True unchanged fast path.
    selectObject: originalSound
    Copy: originalName$ + "_temporal_warp_" + presetName$
    resultSound = selected("Sound")

else
    # Accumulate independent warped trajectories. Their weights sum to 1.
    Create Sound from formula: "warp_wet_left", 1, 0, totalDuration, samplingRate, "0"
    wetLeft = selected("Sound")

    Create Sound from formula: "warp_wet_right", 1, 0, totalDuration, samplingRate, "0"
    wetRight = selected("Sound")

    weightDenom = number_of_warp_stages * (number_of_warp_stages + 1)

    for stage from 1 to number_of_warp_stages
        # Later trajectories receive more weight because they carry more of
        # the audible deformation. Sum(2*stage/(N*(N+1))) = 1.
        pathWeight = 2 * stage / weightDenom
        weight_str$ = string$(pathWeight)

        # u follows output time through the original source interval and
        # then remains at 1 in the tail. curve'(u) stays positive because
        # |bend| <= 0.35, so every time map is monotonic.
        u_expr$ = "min(1,max(0,x/" + orig_dur_str$ + "))"

        # ---- LEFT trajectory ----
        endpointL_str$ = string$(cumulativeDelayL[stage])
        bendL_str$ = string$(bendL[stage])
        curveL$ = "(" + u_expr$ + "+(" + bendL_str$ + ")*sin(2*pi*" + u_expr$ + ")/(2*pi))"

        if channels = 2
            sourceExprL$ = "object(" + orig_id_str$ + ",x-((" + endpointL_str$ + ")*" + curveL$ + ")+" + orig_start_str$ + ",1)"
        else
            sourceExprL$ = "object(" + orig_id_str$ + ",x-((" + endpointL_str$ + ")*" + curveL$ + ")+" + orig_start_str$ + ",1)"
        endif

        wet_left_id_str$ = string$(wetLeft)
        Create Sound from formula: "warp_wet_left_next", 1, 0, totalDuration, samplingRate, "object(" + wet_left_id_str$ + ",x,1)+(" + weight_str$ + ")*(" + sourceExprL$ + ")"
        nextWetLeft = selected("Sound")
        removeObject: wetLeft
        wetLeft = nextWetLeft

        # ---- RIGHT trajectory ----
        endpointR_str$ = string$(cumulativeDelayR[stage])
        bendR_str$ = string$(bendR[stage])
        curveR$ = "(" + u_expr$ + "+(" + bendR_str$ + ")*sin(2*pi*" + u_expr$ + ")/(2*pi))"

        if channels = 2
            sourceExprR$ = "object(" + orig_id_str$ + ",x-((" + endpointR_str$ + ")*" + curveR$ + ")+" + orig_start_str$ + ",2)"
        else
            sourceExprR$ = "object(" + orig_id_str$ + ",x-((" + endpointR_str$ + ")*" + curveR$ + ")+" + orig_start_str$ + ",1)"
        endif

        wet_right_id_str$ = string$(wetRight)
        Create Sound from formula: "warp_wet_right_next", 1, 0, totalDuration, samplingRate, "object(" + wet_right_id_str$ + ",x,1)+(" + weight_str$ + ")*(" + sourceExprR$ + ")"
        nextWetRight = selected("Sound")
        removeObject: wetRight
        wetRight = nextWetRight
    endfor

    # Fade WET tail only.
    if fadeDuration > 0
        fade_start_str$ = string$(fadeStart)
        fade_dur_str$ = string$(fadeDuration)

        selectObject: wetLeft
        Formula: "if x > " + fade_start_str$ + " then self * (0.5 + 0.5*cos(pi*(x-" + fade_start_str$ + ")/" + fade_dur_str$ + ")) else self fi"

        selectObject: wetRight
        Formula: "if x > " + fade_start_str$ + " then self * (0.5 + 0.5*cos(pi*(x-" + fade_start_str$ + ")/" + fade_dur_str$ + ")) else self fi"
    endif

    # Direct strength control: dry/original vs parallel warped field.
    wet_left_id_str$ = string$(wetLeft)
    wet_right_id_str$ = string$(wetRight)

    if channels = 2
        dryExprL$ = "object(" + orig_id_str$ + ",x+" + orig_start_str$ + ",1)"
        dryExprR$ = "object(" + orig_id_str$ + ",x+" + orig_start_str$ + ",2)"
    else
        dryExprL$ = "object(" + orig_id_str$ + ",x+" + orig_start_str$ + ",1)"
        dryExprR$ = "object(" + orig_id_str$ + ",x+" + orig_start_str$ + ",1)"
    endif

    Create Sound from formula: "warp_out_left", 1, 0, totalDuration, samplingRate, "(" + dry_gain_str$ + ")*(" + dryExprL$ + ")+(" + wet_gain_str$ + ")*object(" + wet_left_id_str$ + ",x,1)"
    outLeft = selected("Sound")

    Create Sound from formula: "warp_out_right", 1, 0, totalDuration, samplingRate, "(" + dry_gain_str$ + ")*(" + dryExprR$ + ")+(" + wet_gain_str$ + ")*object(" + wet_right_id_str$ + ",x,1)"
    outRight = selected("Sound")

    selectObject: outLeft, outRight
    Combine to stereo
    resultSound = selected("Sound")
    Rename: originalName$ + "_temporal_warp_" + presetName$

    # One common down-only safeguard; no quiet-signal normalization.
    selectObject: resultSound
    resultPeak = Get absolute extremum: 0, 0, "none"
    if resultPeak > 1
        Scale peak: 0.98
    endif

    removeObject: wetLeft, wetRight, outLeft, outRight
endif

selectObject: resultSound
resultDuration = Get total duration

# ============================================================
# VISUALIZATION - PRAAT AUDIOTOOLS HOUSE STYLE
# ============================================================

if show_visualization
    Erase all

    # Shared left panel-label rail.
    labelX = -0.035
    labelFont = 7


    # Main title.
    Select outer viewport: 0, 8, 0.05, 0.38
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.58, "half", "Temporal Warping | " + presetName$ + " | v1.3.1"

    # Metadata line.
    Select outer viewport: 0, 8, 0.36, 0.58
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.35, 0.35, 0.35}"
    Text: 0.5, "centre", 0.5, "half", originalName$ + " | " + string$(number_of_warp_stages) + " paths | Strength " + fixed$(effectiveStrength, 2) + " | Max delay " + fixed$(maxDisplacement * 1000, 0) + " ms"

    # Dry waveform on the full output time axis.
    Select outer viewport: 0, 8, 0.65, 1.35
    Select inner viewport: 0.60, 7.70, 0.72, 1.28
    selectObject: originalSound
    Colour: "{0.65, 0.65, 0.65}"
    Draw: originalStart, originalStart + resultDuration, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Select inner viewport: 0.20, 0.48, 0.72, 1.28
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Dry"
    Select inner viewport: 0.60, 7.70, 0.72, 1.28
    Axes: 0, 1, 0, 1

    # Warped output waveform.
    Select outer viewport: 0, 8, 1.42, 2.12
    Select inner viewport: 0.60, 7.70, 1.49, 2.05
    selectObject: resultSound
    Colour: "{0.48, 0.64, 0.52}"
    Draw: 0, resultDuration, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Select inner viewport: 0.20, 0.48, 1.49, 2.05
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Output"
    Select inner viewport: 0.60, 7.70, 1.49, 2.05
    Axes: 0, 1, 0, 1
    Text bottom: "yes", "Time (s)"

    # ---- Left analysis panel: actual per-stage displacement ----
    Select outer viewport: 0.15, 3.95, 2.35, 3.88
    Select inner viewport: 0.60, 3.85, 2.62, 3.68

    maxStageDelay = 0
    for stage from 1 to number_of_warp_stages
        maxStageDelay = max(maxStageDelay, cumulativeDelayL[stage], cumulativeDelayR[stage])
    endfor
    if maxStageDelay <= 0
        maxStageDelay = 0.001
    endif

    Axes: 0.5, number_of_warp_stages + 0.5, 0, maxStageDelay * 1150
    Paint rectangle: "{0.96, 0.96, 0.96}", 0.5, number_of_warp_stages + 0.5, 0, maxStageDelay * 1150

    Colour: "{0.42, 0.58, 0.76}"
    Line width: 1.5
    for stage from 1 to number_of_warp_stages
        Draw line: stage, 0, stage, cumulativeDelayL[stage] * 1000
        Paint circle (mm): "{0.42, 0.58, 0.76}", stage, cumulativeDelayL[stage] * 1000, 1.1
    endfor

    Colour: "{0.78, 0.48, 0.42}"
    for stage from 1 to number_of_warp_stages
        Paint circle (mm): "{0.78, 0.48, 0.42}", stage, cumulativeDelayR[stage] * 1000, 1.1
    endfor

    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Select inner viewport: 0.20, 0.48, 2.62, 3.68
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Delay (ms)"
    Select inner viewport: 0.60, 3.85, 2.62, 3.68
    Axes: 0.5, number_of_warp_stages + 0.5, 0, maxStageDelay * 1150
    Text bottom: "yes", "Warp path"

    Select outer viewport: 0.15, 3.95, 2.24, 2.48
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Warp-path endpoint delay"

    # ---- Right analysis panel: actual curvature parameters ----
    Select outer viewport: 4.05, 7.85, 2.35, 3.88
    Select inner viewport: 4.45, 7.70, 2.62, 3.68
    Axes: 0.5, number_of_warp_stages + 0.5, -0.40, 0.40
    Paint rectangle: "{0.96, 0.96, 0.96}", 0.5, number_of_warp_stages + 0.5, -0.40, 0.40

    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0.5, 0, number_of_warp_stages + 0.5, 0

    Colour: "{0.42, 0.58, 0.76}"
    for stage from 1 to number_of_warp_stages
        Paint circle (mm): "{0.42, 0.58, 0.76}", stage, bendL[stage], 1.1
    endfor

    Colour: "{0.78, 0.48, 0.42}"
    for stage from 1 to number_of_warp_stages
        Paint circle (mm): "{0.78, 0.48, 0.42}", stage, bendR[stage], 1.1
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 6
    Select inner viewport: 4.05, 4.33, 2.62, 3.68
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Bend"
    Select inner viewport: 4.45, 7.70, 2.62, 3.68
    Axes: 0.5, number_of_warp_stages + 0.5, -0.40, 0.40
    Text bottom: "yes", "Warp path"

    Select outer viewport: 4.05, 7.85, 2.24, 2.48
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Stereo path curvature"

    # Small legend between analysis panels and summary.
    Select outer viewport: 0, 8, 3.86, 4.02
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.42, 0.58, 0.76}"
    Text: 0.46, "right", 0.5, "half", "LEFT"
    Colour: "{0.78, 0.48, 0.42}"
    Text: 0.54, "left", 0.5, "half", "RIGHT"

    # Summary panel.
    Select outer viewport: 0, 8, 4.12, 5.12
    Select inner viewport: 0.60, 7.70, 4.19, 5.05
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.35}"
    Font size: 6
    Font size: 7
    Colour: "Black"
    Font size: 7
    Text: 0.02, "left", 0.72, "half", "##Summary##"
    Font size: 6
    Text: 0.02, "left", 0.48, "half", "Factor " + fixed$(effectiveFactor, 3) + " | Max path delay " + fixed$(maxDisplacement * 1000, 0) + " ms | Dry/Warp " + fixed$(dryGain, 2) + "/" + fixed$(wetGain, 2)
    Font size: 6
    Text: 0.02, "left", 0.24, "half", "Tail " + fixed$(effectiveTail, 2) + " s | Fade " + fixed$(fadeDuration, 2) + " s | Output " + fixed$(resultDuration, 2) + " s"

    Select inner viewport: 0.60, 7.70, 4.19, 5.05
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box

    Font size: 10
    Line width: 1
    Colour: "Black"

    # Restore full-page viewport before leaving visualization.
    Select outer viewport: 0, 8, 0, 5.22
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# ============================================================
# FINAL INFO / PLAY
# ============================================================

selectObject: resultSound
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Output duration: ", fixed$(resultDuration, 3), " s"

if play_result
    Play
endif

selectObject: resultSound
