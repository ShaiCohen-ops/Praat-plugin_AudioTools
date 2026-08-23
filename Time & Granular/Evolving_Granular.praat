# ============================================================
# Praat AudioTools - Evolving_Granular.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5.2 (2026) - Readable grain evolution map
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Evolving Granular Synthesis - creates granular textures with
#   time-varying parameters. Three evolution modes:
#   - Density Growth: grain density increases over time
#   - Pitch Sweep: gradual pitch transposition
#   - Statistical Shift: 3 regions with different characteristics
#
# Changelog v0.5.2:
#   Visualization only. DSP, grain scheduling and audio output are unchanged.
#   - FIXED unreadable grain markers. v0.5.1 painted every grain at a fixed
#     0.52 mm radius (about 1 mm across), which is below the practical
#     resolution of the Picture window, so the evolution was invisible.
#     Marker radius is now derived from the number of drawn grains
#     (1.75 mm for sparse textures down to 0.60 mm for very dense ones),
#     so sparse and dense presets are both legible.
#   - Added a density strip along the bottom of the map: measured grains/s
#     per time bin, plus the requested initial -> final density trajectory
#     for Density growth. Density was previously encoded only as horizontal
#     dot spacing, which is not readable once grains overlap.
#   - The map y-range now reserves headroom below the lowest grain so the
#     density strip never collides with grain markers.
#   - Stronger duration colour ramp and matching key, moved to the top right
#     to keep the bottom of the map free.
#   - The map remains legible when pitch shifting is off (all grains on the
#     zero line): the density strip then carries the evolution.
#
# Changelog v0.5.1:
#   Visualization only:
#   - Aligned the Picture output with the current Praat AudioTools suite style.
#   - Replaced four separate diagnostic plots with one Grain evolution map:
#     x = output time, y = pitch shift, colour = grain duration, horizontal
#     spacing = density. This directly exposes all three evolution modes.
#   - Added shared Source / Output waveform scale, consistent title hierarchy,
#     clean Summary panel, and underscore-safe display names.
#   - DSP and evolution scheduling are unchanged from v0.5.
#
# Changelog v0.5:
#   DSP / evolution correctness:
#   - FIXED Density Growth. v0.4 generated candidates at the mean density and
#     accepted them with probability currentDensity/meanDensity. Above the mean
#     that probability saturated at 1, so e.g. 20->40 grains/s could never
#     exceed about 30 grains/s. v0.5 places grains by inverting the cumulative
#     integral of the requested linear density trajectory.
#   - Position_randomness now randomizes SOURCE position only. v0.4 also used
#     it as output-time jitter, which blurred the requested density evolution.
#   - All evolution modes schedule grains inside valid output bounds instead of
#     generating edge candidates and silently discarding them.
#   - Statistical Shift now respects Grain_duration_min/max and uses
#     Pitch_shift_semitones as its pitch-range control. ThreeRegion uses 8 st
#     to preserve the former -4/+2/+8 regional character.
#   - FIXED small pitch shifts. v0.4 skipped resampling whenever the factor was
#     within 2% of unity (~0.34 st), so the stereo detune (max ~0.06 st) never
#     happened. The threshold is now 0.005 semitones.
#   - When pitch shifting is disabled, stored/visualized pitch shift is 0 so
#     diagnostics match the rendered audio.
#   - FIXED non-zero Sound time domains: source extraction uses sourceStart.
#   - Removed the silent 500-grain cap. Requests above 5000 grains now stop
#     with an explicit message instead of silently changing the density.
#   - Added validation for densities, grain durations, randomization ranges,
#     stereo width, and safe normalization for silent output.
#
# Changelog v0.4:
#   - Stereo output: each grain is placed in the left channel as-is and in
#     the right channel with small independent per-grain jitter (detune,
#     source position, timing). Same texture, decorrelated -> natural width.
#   - New Stereo_width control (0 = identical channels/mono, 1 = wide).
#   - Grain extract/pitch/mix refactored into a placeGrain procedure.
#
# Changelog v0.3:
#   - Fixed pitch shifting. The old Lengthen (overlap-add) call is a
#     pitch-PRESERVING time-stretch, so pitch never changed (and downward
#     shifts silently no-op'd via nocheck). Now uses Override sampling
#     frequency + Resample (varispeed), so Pitch Sweep and the Rising/
#     Falling presets actually shift pitch. Grain length scales by 1/factor.
#   - Visualization: title and legend set their own Axes so they center
#     correctly (legend no longer drifts/clips with input duration);
#     'Original' label aligned with 'Granular'.
#
# Changelog v0.2:
#   - Fixed object reference bugs
#   - Added input check
#   - Added evolution visualization
# ============================================================

form Evolving Granular v0.5.2
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom
        option Dense Cloud
        option Sparse Texture
        option Rising Pitch Sweep
        option Falling Pitch Sweep
        option Three Region Evolution
        option Gentle Growth
        option Extreme Density Build
        option Micro Grains
    
    comment === Grain Parameters (Custom only) ===
    real Initial_density 10.0
    real Final_density 25.0
    real Grain_duration_min 0.05
    real Grain_duration_max 0.15
    
    comment === Evolution ===
    optionmenu Evolution_type 1
        option Density growth
        option Pitch sweep
        option Statistical shift
    real Pitch_shift_semitones 7.0
    
    comment === Randomization ===
    real Position_randomness 0.3
    real Pitch_randomness 2.0
    real Amplitude_randomness 0.2
    
    comment === Stereo ===
    real Stereo_width 0.3
    comment (0 = mono, ~0.3 subtle, ~0.5 stereo, 1 = wide)
    
    comment === Options ===
    boolean Enable_pitch_shifting 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    initial_density = 20.0
    final_density = 40.0
    grain_duration_min = 0.04
    grain_duration_max = 0.10
    evolution_type = 1
    pitch_shift_semitones = 3.0
    position_randomness = 0.4
    pitch_randomness = 1.5
    amplitude_randomness = 0.25
    enable_pitch_shifting = 1
    preset_name$ = "DenseCloud"
elsif preset = 3
    initial_density = 5.0
    final_density = 12.0
    grain_duration_min = 0.08
    grain_duration_max = 0.20
    evolution_type = 1
    pitch_shift_semitones = 2.0
    position_randomness = 0.2
    pitch_randomness = 1.0
    amplitude_randomness = 0.15
    enable_pitch_shifting = 1
    preset_name$ = "SparseTexture"
elsif preset = 4
    initial_density = 15.0
    final_density = 30.0
    grain_duration_min = 0.05
    grain_duration_max = 0.12
    evolution_type = 2
    pitch_shift_semitones = 12.0
    position_randomness = 0.25
    pitch_randomness = 2.0
    amplitude_randomness = 0.20
    enable_pitch_shifting = 1
    preset_name$ = "RisingPitch"
elsif preset = 5
    initial_density = 15.0
    final_density = 30.0
    grain_duration_min = 0.05
    grain_duration_max = 0.12
    evolution_type = 2
    pitch_shift_semitones = -12.0
    position_randomness = 0.25
    pitch_randomness = 2.0
    amplitude_randomness = 0.20
    enable_pitch_shifting = 1
    preset_name$ = "FallingPitch"
elsif preset = 6
    initial_density = 18.0
    final_density = 35.0
    grain_duration_min = 0.03
    grain_duration_max = 0.15
    evolution_type = 3
    pitch_shift_semitones = 8.0
    position_randomness = 0.35
    pitch_randomness = 2.5
    amplitude_randomness = 0.25
    enable_pitch_shifting = 1
    preset_name$ = "ThreeRegion"
elsif preset = 7
    initial_density = 8.0
    final_density = 20.0
    grain_duration_min = 0.06
    grain_duration_max = 0.16
    evolution_type = 1
    pitch_shift_semitones = 2.0
    position_randomness = 0.15
    pitch_randomness = 1.0
    amplitude_randomness = 0.10
    enable_pitch_shifting = 1
    preset_name$ = "GentleGrowth"
elsif preset = 8
    initial_density = 10.0
    final_density = 60.0
    grain_duration_min = 0.03
    grain_duration_max = 0.08
    evolution_type = 1
    pitch_shift_semitones = 5.0
    position_randomness = 0.5
    pitch_randomness = 3.0
    amplitude_randomness = 0.30
    enable_pitch_shifting = 1
    preset_name$ = "ExtremeDensity"
elsif preset = 9
    initial_density = 30.0
    final_density = 50.0
    grain_duration_min = 0.02
    grain_duration_max = 0.05
    evolution_type = 1
    pitch_shift_semitones = 7.0
    position_randomness = 0.3
    pitch_randomness = 4.0
    amplitude_randomness = 0.25
    enable_pitch_shifting = 0
    preset_name$ = "MicroGrains"
else
    preset_name$ = "Custom"
endif

# === Get Evolution Type Name ===
if evolution_type = 1
    evolution_name$ = "Density Growth"
elsif evolution_type = 2
    evolution_name$ = "Pitch Sweep"
else
    evolution_name$ = "Statistical Shift"
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

originalSound = selected("Sound")
sound_name$ = selected$("Sound")

selectObject: originalSound
sourceStart = Get start time
sourceEnd = Get end time
duration = Get total duration
sampling_rate = Get sampling frequency
n_channels = Get number of channels

# === Validate ===
if initial_density <= 0 or final_density <= 0
    exitScript: "Initial and final density must be > 0"
endif
if grain_duration_min <= 0 or grain_duration_max <= 0
    exitScript: "Grain durations must be > 0"
endif
if grain_duration_max < grain_duration_min
    exitScript: "Grain duration max must be >= grain duration min"
endif
if grain_duration_min > duration
    exitScript: "Input sound is shorter than the minimum grain duration"
endif
if position_randomness < 0
    exitScript: "Position randomness must be >= 0"
endif
if pitch_randomness < 0
    exitScript: "Pitch randomness must be >= 0"
endif
if amplitude_randomness < 0
    exitScript: "Amplitude randomness must be >= 0"
endif
if stereo_width < 0 or stereo_width > 1
    exitScript: "Stereo width must be between 0 and 1"
endif

effective_grain_duration_max = min(grain_duration_max, duration)

# Convert to mono if stereo (keep original for visualization)
if n_channels > 1
    selectObject: originalSound
    Convert to mono
    sourceSound = selected("Sound")
else
    sourceSound = originalSound
endif

# === Info ===
writeInfoLine: "=== Evolving Granular ==="
appendInfoLine: "Source: ", sound_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Evolution: ", evolution_name$
appendInfoLine: ""

# Calculate requested grain count from the density integral.
avg_density = (initial_density + final_density) / 2
total_grains = max(1, round(avg_density * duration))

if total_grains > 5000
    if n_channels > 1
        removeObject: sourceSound
    endif
    exitScript: "This setting requests more than 5000 grains. Reduce density or use a shorter input."
endif

appendInfoLine: "Grains: ", total_grains
if evolution_type = 1
    appendInfoLine: "Density trajectory: ", fixed$(initial_density, 1), " -> ", fixed$(final_density, 1), " /sec"
else
    appendInfoLine: "Mean scheduling density: ", fixed$(total_grains / duration, 1), " /sec"
endif
appendInfoLine: "Grain duration: ", fixed$(grain_duration_min * 1000, 1), " -> ", fixed$(effective_grain_duration_max * 1000, 1), " ms"
appendInfoLine: ""

# ===================================================================
# PRE-COMPUTE GRAIN PARAMETERS
# ===================================================================

appendInfoLine: "Generating grain parameters..."

# Initialize arrays
for grain to total_grains
    grainSourcePos[grain] = 0
    grainOutputPos[grain] = 0
    grainDur[grain] = -1
    grainPitchShift[grain] = 0
    grainAmp[grain] = 0
endfor

# Generate parameters based on evolution type
# Density Growth uses inverse-transform placement for a linear intensity
# lambda(u) = initial_density + (final_density-initial_density)*u.
# The normalized cumulative integral is inverted at evenly spaced quantiles,
# so the requested density trajectory is achieved without acceptance saturation.
density_delta = final_density - initial_density
density_integral = (initial_density + final_density) / 2
duration_span = effective_grain_duration_max - grain_duration_min

for grain to total_grains
    if total_grains = 1
        quantile = 0.5
    else
        quantile = (grain - 0.5) / total_grains
    endif

    if evolution_type = 1
        # Density Growth: deterministic quantiles of the linear density law.
        if abs(density_delta) < 0.000000001
            u = quantile
        else
            targetIntegral = quantile * density_integral
            discriminant = initial_density^2 + 2 * density_delta * targetIntegral
            u = (-initial_density + sqrt(max(0, discriminant))) / density_delta
        endif
        u = min(1, max(0, u))

        gDur = grain_duration_min + duration_span * randomUniform(0, 1)
        maxStart = max(0, duration - gDur)
        grain_start = u * maxStart

        source_pos = grain_start + position_randomness * randomGauss(0, 0.5)
        source_pos = max(0, min(duration - gDur, source_pos))
        pShift = pitch_randomness * randomGauss(0, 1)
        amp_factor = 1 + amplitude_randomness * randomGauss(0, 1)
        amp_factor = max(0.3, min(1.5, amp_factor))

    elsif evolution_type = 2
        # Pitch Sweep: uniform stochastic time placement; pitch follows actual
        # output position from 0 to Pitch_shift_semitones.
        gDur = grain_duration_min + duration_span * randomUniform(0, 1)
        event_center = randomUniform(0, duration)
        maxStart = max(0, duration - gDur)
        grain_start = min(maxStart, max(0, event_center - gDur / 2))
        normalized_time = (grain_start + gDur / 2) / duration

        current_pitch_shift = pitch_shift_semitones * normalized_time
        pShift = current_pitch_shift + pitch_randomness * randomGauss(0, 1)
        source_pos = grain_start + position_randomness * randomGauss(0, 0.3)
        source_pos = max(0, min(duration - gDur, source_pos))
        amp_factor = (1.2 - normalized_time * 0.4) + amplitude_randomness * randomGauss(0, 1)
        amp_factor = max(0.3, min(1.5, amp_factor))

    else
        # Statistical Shift: three regions. Duration ranges are derived from
        # the user's min/max controls; pitch regions scale with Pitch shift.
        event_center = randomUniform(0, duration)
        normalized_time = event_center / duration

        if normalized_time < 0.33
            regionLow = grain_duration_min + 0.55 * duration_span
            regionHigh = effective_grain_duration_max
            gDur = regionLow + (regionHigh - regionLow) * randomUniform(0, 1)
            baseShift = -0.5 * pitch_shift_semitones
            pShift = baseShift + pitch_randomness * randomGauss(0, 1)
            amp_factor = 0.9 + amplitude_randomness * randomGauss(0, 1)
        elsif normalized_time < 0.66
            regionLow = grain_duration_min + 0.25 * duration_span
            regionHigh = grain_duration_min + 0.65 * duration_span
            gDur = regionLow + (regionHigh - regionLow) * randomUniform(0, 1)
            baseShift = 0.25 * pitch_shift_semitones
            pShift = baseShift + pitch_randomness * 1.5 * randomGauss(0, 1)
            amp_factor = 0.7 + amplitude_randomness * randomGauss(0, 1)
        else
            regionLow = grain_duration_min
            regionHigh = grain_duration_min + 0.35 * duration_span
            gDur = regionLow + (regionHigh - regionLow) * randomUniform(0, 1)
            baseShift = pitch_shift_semitones
            pShift = baseShift + pitch_randomness * 2 * randomGauss(0, 1)
            amp_factor = 0.5 + amplitude_randomness * randomGauss(0, 1)
        endif

        maxStart = max(0, duration - gDur)
        grain_start = min(maxStart, max(0, event_center - gDur / 2))
        source_pos = grain_start + position_randomness * randomGauss(0, 0.5)
        source_pos = max(0, min(duration - gDur, source_pos))
        amp_factor = max(0.2, min(1.3, amp_factor))
    endif

    # If pitch processing is disabled, diagnostics must match rendered audio.
    if not enable_pitch_shifting
        pShift = 0
    endif

    grainSourcePos[grain] = source_pos
    grainOutputPos[grain] = grain_start
    grainDur[grain] = gDur
    grainPitchShift[grain] = pShift
    grainAmp[grain] = amp_factor
endfor

# Per-channel stereo decorrelation amounts (small differences)
stereo_detune_st = stereo_width * 0.06
stereo_pos_jit_s = stereo_width * 0.002
stereo_time_jit_s = stereo_width * 0.0005

appendInfoLine: "Synthesizing grains..."

# ===================================================================
# GRAIN SYNTHESIS
# ===================================================================

# Stereo output: two channels from the same grain plan, with small independent
# per-grain differences (detune / source-position / timing) so the sides are the
# same texture but decorrelated. Stereo_width scales it (0 = identical = mono).
Create Sound from formula: sound_name$ + "_granular", 2, 0, duration, sampling_rate, "0"
outputSound = selected("Sound")

valid_grains = 0
progressStep = max(1, floor(total_grains / 10))

for grain to total_grains
    gDur = grainDur[grain]
    
    # Skip invalid grains (marked with negative duration)
    if gDur > 0
        source_pos = grainSourcePos[grain]
        grain_start = grainOutputPos[grain]
        pShift = grainPitchShift[grain]
        amp_factor = grainAmp[grain]
        
        # Left channel: base grain
        @placeGrain: 1, source_pos, grain_start, pShift, amp_factor, gDur
        
        # Right channel: same grain, small independent differences
        srcR = source_pos + stereo_pos_jit_s * randomGauss(0, 1)
        srcR = max(0, min(duration - gDur, srcR))
        startR = grain_start + stereo_time_jit_s * randomGauss(0, 1)
        if startR < 0
            startR = 0
        endif
        pShiftR = pShift + stereo_detune_st * randomGauss(0, 1)
        @placeGrain: 2, srcR, startR, pShiftR, amp_factor, gDur
        
        valid_grains += 1
    endif
    
    if grain mod progressStep = 0
        appendInfoLine: "  ", floor(grain / total_grains * 100), "%"
    endif
endfor

# ===================================================================
# FINALIZE
# ===================================================================

selectObject: outputSound
outputPeak = Get absolute extremum: 0, 0, "Sinc70"
if outputPeak > 0
    Scale peak: 0.95
endif
Rename: sound_name$ + "_" + preset_name$

# ===================================================================
# VISUALIZATION  (current Praat AudioTools suite styling)
# Source -> Grain evolution map -> Output -> Summary.
# One grain = one event in the central map:
#   x = output time, y = pitch shift,
#   colour = grain duration, horizontal spacing = density.
# Colour is reserved for duration only; guides and boundaries are neutral.
# ===================================================================

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 7.10
    Black
    Plain line

    displayName$ = replace$(sound_name$, "_", " ", 0)

    # Zero-based mono source display copy.
    selectObject: originalSound
    vizOrig = Convert to mono
    selectObject: vizOrig
    vizOrigStart = Get start time
    Shift times by: -vizOrigStart

    # Output duration and shared source/output amplitude scale.
    selectObject: outputSound
    outputDuration = Get total duration
    outputPeakViz = Get absolute extremum: 0, 0, "None"
    selectObject: vizOrig
    origPeakViz = Get absolute extremum: 0, 0, "None"
    sharedPeak = max(origPeakViz, outputPeakViz)
    if sharedPeak < 0.001
        sharedPeak = 0.001
    endif
    sharedAmp = 1.15 * sharedPeak

    # Pitch and duration ranges for the central map.
    minPitchRaw = 0
    maxPitchRaw = 0
    minDurRaw = effective_grain_duration_max
    maxDurRaw = 0
    firstValid = 1
    for grain to total_grains
        if grainDur[grain] > 0
            if firstValid
                minPitchRaw = grainPitchShift[grain]
                maxPitchRaw = grainPitchShift[grain]
                minDurRaw = grainDur[grain]
                maxDurRaw = grainDur[grain]
                firstValid = 0
            else
                if grainPitchShift[grain] < minPitchRaw
                    minPitchRaw = grainPitchShift[grain]
                endif
                if grainPitchShift[grain] > maxPitchRaw
                    maxPitchRaw = grainPitchShift[grain]
                endif
                if grainDur[grain] < minDurRaw
                    minDurRaw = grainDur[grain]
                endif
                if grainDur[grain] > maxDurRaw
                    maxDurRaw = grainDur[grain]
                endif
            endif
        endif
    endfor

    if firstValid
        minPitchRaw = -1
        maxPitchRaw = 1
        minDurRaw = grain_duration_min
        maxDurRaw = effective_grain_duration_max
    endif

    pitchSpan = maxPitchRaw - minPitchRaw
    if pitchSpan < 1
        pitchSpan = 1
    endif
    # Extra headroom at the bottom: the density strip lives there and must not
    # collide with the lowest grain markers.
    mapPitchMin = min(minPitchRaw, 0) - 0.34 * pitchSpan
    mapPitchMax = max(maxPitchRaw, 0) + 0.18 * pitchSpan
    if mapPitchMax - mapPitchMin < 1.6
        mapPitchPad = (1.6 - (mapPitchMax - mapPitchMin)) / 2
        mapPitchMin = mapPitchMin - mapPitchPad
        mapPitchMax = mapPitchMax + mapPitchPad
    endif
    mapPitchSpan = mapPitchMax - mapPitchMin

    durSpan = maxDurRaw - minDurRaw
    if durSpan < 0.000001
        durSpan = 0.000001
    endif

    # ----------------------------------------------------------
    # Marker size. A fixed radius is unreadable across the preset range
    # (Sparse Texture draws tens of grains, Extreme Density thousands),
    # so the radius follows the drawn grain count.
    # ----------------------------------------------------------
    drawnGrains = valid_grains
    if drawnGrains < 1
        drawnGrains = 1
    endif
    markerRadius = 2.35 - 0.52 * log10(max(10, drawnGrains))
    if markerRadius > 1.75
        markerRadius = 1.75
    endif
    if markerRadius < 0.60
        markerRadius = 0.60
    endif

    # ----------------------------------------------------------
    # Measured grain density per time bin, for the density strip.
    # ----------------------------------------------------------
    densBins = round(drawnGrains / 10)
    if densBins < 10
        densBins = 10
    endif
    if densBins > 48
        densBins = 48
    endif
    densBinWidth = outputDuration / densBins
    if densBinWidth < 0.000001
        densBinWidth = 0.000001
    endif

    for b to densBins
        densCount[b] = 0
    endfor
    for grain to total_grains
        if grainDur[grain] > 0
            b = floor(grainOutputPos[grain] / densBinWidth) + 1
            if b < 1
                b = 1
            endif
            if b > densBins
                b = densBins
            endif
            densCount[b] = densCount[b] + 1
        endif
    endfor

    densMax = 0
    for b to densBins
        densRate[b] = densCount[b] / densBinWidth
        if densRate[b] > densMax
            densMax = densRate[b]
        endif
    endfor
    # The requested trajectory must stay inside the strip as well.
    densScale = max(densMax, max(initial_density, final_density))
    if densScale < 0.000001
        densScale = 1
    endif
    densScale = 1.10 * densScale

    stripBottom = mapPitchMin
    stripTop = mapPitchMin + 0.20 * mapPitchSpan

    appendInfoLine: "  map: ", drawnGrains, " grains, marker radius ", fixed$(markerRadius, 2), " mm, peak density ", fixed$(densMax, 1), " grains/s"

    # ----------------------------------------------------------
    # TITLE / SUBTITLE
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Evolving Granular##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -1.30, "half", "Evolving Granular.praat  |  " + displayName$ + "  |  " + preset_name$ + "  |  " + evolution_name$

    # ----------------------------------------------------------
    # SOURCE
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.65, 1.90
    Select inner viewport: 0.55, 7.75, 0.82, 1.78
    Axes: 0, duration, -sharedAmp, sharedAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, -sharedAmp, sharedAmp
    selectObject: vizOrig
    Colour: "{0.58, 0.58, 0.62}"
    Draw: 0, duration, -sharedAmp, sharedAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "##Source##"
    Font size: 6
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Time (s)"
    Axes: 0, duration, -sharedAmp, sharedAmp
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.01 * duration, "left", 0.82 * sharedAmp, "half", "grain " + fixed$(grain_duration_min * 1000, 0) + "-" + fixed$(effective_grain_duration_max * 1000, 0) + " ms  |  source-position randomness " + fixed$(position_randomness, 2)

    # ----------------------------------------------------------
    # GRAIN EVOLUTION MAP
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 2.05, 4.55
    Select inner viewport: 0.55, 7.75, 2.22, 4.40
    Axes: 0, outputDuration, mapPitchMin, mapPitchMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, outputDuration, mapPitchMin, mapPitchMax

    # Neutral zero-pitch reference.
    Colour: "{0.72, 0.72, 0.75}"
    Dotted line
    Draw line: 0, 0, outputDuration, 0
    Solid line

    # Statistical-shift region boundaries are structural, therefore neutral.
    if evolution_type = 3
        Colour: "{0.70, 0.70, 0.73}"
        Dotted line
        Draw line: outputDuration * 0.33, mapPitchMin, outputDuration * 0.33, mapPitchMax
        Draw line: outputDuration * 0.66, mapPitchMin, outputDuration * 0.66, mapPitchMax
        Solid line
    endif

    # Requested pitch-sweep trajectory.
    if evolution_type = 2 and enable_pitch_shifting
        Colour: "{0.55, 0.55, 0.58}"
        Line width: 1.3
        Draw line: 0, 0, outputDuration, pitch_shift_semitones
        Line width: 1
    endif

    # ------------------------------------------------------
    # Density strip (measured grains/s per time bin).
    # Drawn before the grains so the markers stay on top.
    # ------------------------------------------------------
    Paint rectangle: "{0.93, 0.94, 0.96}", 0, outputDuration, stripBottom, stripTop
    for b to densBins
        binX1 = (b - 1) * densBinWidth
        binX2 = b * densBinWidth
        binH = densRate[b] / densScale
        if binH > 1
            binH = 1
        endif
        if binH > 0
            Paint rectangle: "{0.72, 0.78, 0.87}", binX1, binX2, stripBottom, stripBottom + binH * (stripTop - stripBottom)
        endif
    endfor

    # Requested density trajectory, for comparison with what was placed.
    if evolution_type = 1
        Colour: "{0.35, 0.42, 0.55}"
        Line width: 1.3
        Dashed line
        Draw line: 0, stripBottom + (initial_density / densScale) * (stripTop - stripBottom), outputDuration, stripBottom + (final_density / densScale) * (stripTop - stripBottom)
        Solid line
        Line width: 1
    endif

    Colour: "{0.55, 0.58, 0.65}"
    Draw line: 0, stripTop, outputDuration, stripTop

    # ------------------------------------------------------
    # Grain events. Colour has one meaning only: grain duration.
    # Marker radius is adaptive - see markerRadius above.
    # ------------------------------------------------------
    for grain to total_grains
        if grainDur[grain] > 0
            gTime = grainOutputPos[grain]
            gPitch = grainPitchShift[grain]
            durNorm = (grainDur[grain] - minDurRaw) / durSpan
            if durNorm < 0
                durNorm = 0
            endif
            if durNorm > 1
                durNorm = 1
            endif
            rVal = 0.22 + 0.46 * durNorm
            gVal = 0.66 - 0.44 * durNorm
            bVal = 0.38 + 0.36 * durNorm
            dotColor$ = "{" + fixed$(rVal, 2) + ", " + fixed$(gVal, 2) + ", " + fixed$(bVal, 2) + "}"
            Paint circle (mm): dotColor$, gTime, gPitch, markerRadius
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "##Grain evolution map##"
    Font size: 6
    Text left: "yes", "Pitch shift (st)"
    Text bottom: "yes", "Output time (s)"
    Axes: 0, outputDuration, mapPitchMin, mapPitchMax
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.01 * outputDuration, "left", mapPitchMax - 0.06 * mapPitchSpan, "half", "colour = grain duration  |  bottom strip = density, 0-" + fixed$(densScale, 0) + "/s"

    # Compact duration key, top right so the density strip stays clear.
    keyY = mapPitchMax - 0.06 * mapPitchSpan
    keyX1 = 0.66 * outputDuration
    keyX2 = 0.80 * outputDuration
    Paint circle (mm): "{0.22, 0.66, 0.38}", keyX1, keyY, 0.85
    Paint circle (mm): "{0.68, 0.22, 0.74}", keyX2, keyY, 0.85
    Colour: "{0.36, 0.36, 0.36}"
    Text: keyX1 + 0.020 * outputDuration, "left", keyY, "half", fixed$(minDurRaw * 1000, 0) + " ms"
    Text: keyX2 + 0.020 * outputDuration, "left", keyY, "half", fixed$(maxDurRaw * 1000, 0) + " ms"

    # ----------------------------------------------------------
    # OUTPUT
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.70, 5.95
    Select inner viewport: 0.55, 7.75, 4.87, 5.83
    Axes: 0, outputDuration, -sharedAmp, sharedAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, outputDuration, -sharedAmp, sharedAmp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, outputDuration, 0

    selectObject: outputSound
    Extract one channel: 1
    vizOutL = selected("Sound")
    Colour: "{0.25, 0.50, 0.82}"
    Draw: 0, outputDuration, -sharedAmp, sharedAmp, "no", "Curve"
    removeObject: vizOutL

    selectObject: outputSound
    Extract one channel: 2
    vizOutR = selected("Sound")
    Colour: "{0.82, 0.45, 0.25}"
    Draw: 0, outputDuration, -sharedAmp, sharedAmp, "no", "Curve"
    removeObject: vizOutR

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "yes", "##Output##"
    Font size: 6
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Time (s)"
    Axes: 0, outputDuration, -sharedAmp, sharedAmp
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.01 * outputDuration, "left", 0.82 * sharedAmp, "half", "blue = L  |  orange = R  |  stereo width " + fixed$(stereo_width, 2)

    # ----------------------------------------------------------
    # SUMMARY
    # ----------------------------------------------------------
    if enable_pitch_shifting
        pitchState$ = "pitch on"
    else
        pitchState$ = "pitch off"
    endif

    Select outer viewport: 0, 8, 6.10, 7.05
    Select inner viewport: 0.30, 7.80, 6.17, 6.98
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "{0.48, 0.48, 0.48}"
    Draw rectangle: 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.80, "half", "##Summary##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.49, "half", preset_name$ + "  |  " + evolution_name$ + "  |  " + string$(valid_grains) + "/" + string$(total_grains) + " grains  |  density " + fixed$(initial_density, 1) + " -> " + fixed$(final_density, 1) + "/s  |  grain " + fixed$(grain_duration_min * 1000, 0) + "-" + fixed$(effective_grain_duration_max * 1000, 0) + " ms"
    Text: 0.02, "left", 0.18, "half", pitchState$ + "  |  pitch randomness " + fixed$(pitch_randomness, 1) + " st  |  amp randomness " + fixed$(amplitude_randomness, 2) + "  |  position randomness " + fixed$(position_randomness, 2) + "  |  stereo " + fixed$(stereo_width, 2) + "  |  output " + fixed$(outputDuration, 2) + " s"

    Font size: 10
    Colour: "Black"
    Line width: 1

    removeObject: vizOrig
endif

# Clean up mono conversion if created
if n_channels > 1
    removeObject: sourceSound
endif

# === Final Info ===
selectObject: outputSound

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Valid grains: ", valid_grains, "/", total_grains
appendInfoLine: "Created: ", selected$("Sound")

# === Play ===
if play_result
    selectObject: outputSound
    Play
endif

selectObject: outputSound


# ===================================================================
# GRAIN PLACEMENT (one grain -> one output channel)
# ===================================================================
procedure placeGrain: .chan, .srcPos, .gStart, .pShift, .amp, .gDur
    selectObject: sourceSound
    .absSrcStart = sourceStart + .srcPos
    Extract part: .absSrcStart, .absSrcStart + .gDur, "Hanning", 1, "no"
    .gx = selected("Sound")

    .pf = 2 ^ (.pShift / 12)
    if enable_pitch_shifting and abs(.pShift) > 0.005
        selectObject: .gx
        Override sampling frequency: sampling_rate * .pf
        Resample: sampling_rate, 50
        .gs = selected("Sound")
        removeObject: .gx
        .gx = .gs
    endif

    selectObject: .gx
    Formula: "self * " + string$(.amp)
    .actualDur = Get total duration
    .gEnd = min(duration, .gStart + .actualDur)

    if .gStart < duration and .gEnd > .gStart
        .gxID$ = string$(.gx)
        .gStart$ = fixed$(.gStart, 8)
        selectObject: outputSound
        Formula (part): .gStart, .gEnd, .chan, .chan, "self + object(" + .gxID$ + ", x - " + .gStart$ + ")"
    endif
    removeObject: .gx
endproc
