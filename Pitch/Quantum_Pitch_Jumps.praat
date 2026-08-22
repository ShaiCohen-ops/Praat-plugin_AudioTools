# ============================================================
# Praat AudioTools - Quantum_Pitch_Jumps.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Quantum Pitch Jumps - stochastic pitch transformation using
#   harmonic ratios. Pitch "tunnels" between quantum levels with
#   configurable probability, glitch events, and uncertainty.
#
# Changelog v0.4.1: compact Summary typography/spacing; collision-safe gap after bottom-axis labels; DSP/analysis unchanged.
# Changelog v0.4: visualization standardization only - unified typography, summary/full-page Picture framing; DSP/analysis unchanged.
# Changelog v0.4:
#   - Jump/Glitch probabilities are now time-consistent: each value is
#     interpreted as the event probability per 100 ms, independent of file length.
#   - Jump_probability and Glitch_probability can be 0 and are validated 0..1.
#   - Quantum levels are unique and symmetric around unison, using harmonic
#     ratios plus octave/inverse mapping instead of repeating the same 13 ratios.
#   - Energy now scales the size of the quantum interval (ratio exponent)
#     instead of acting as an unrelated direct frequency multiplier.
#   - Uncertainty is correlated/sample-and-hold rather than independent jitter
#     at every curve point.
#   - Analysis range is separated from synthesis safety (20 Hz .. 0.45*SR).
#   - Robust validation for ranges and maximum number of quantum levels.
#   - Stops cleanly when no usable voiced pitch is detected.
#   - Preserves the original channel count by applying one shared PitchTier
#     independently to every source channel.
#   - Peak protection is attenuation-only.
#   - Visualization layout/style preserved; title/legend/stats coordinates fixed,
#     and jump/glitch events are accumulated into visualization bins.
#
# Changelog v0.2:
#   - Modern syntax
#   - Fixed input check
#   - Fixed resample result tracking
#   - Added visualization
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
form Quantum Pitch Jumps v0.4.1
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Manual (configure below)
        option Gentle Quantum
        option Moderate Quantum
        option Aggressive Quantum
        option Extreme Quantum
        option Glitchy Micro
        option Harmonic Leaps
        option Chaotic Quantum
    
    comment === Quantum Parameters ===
    natural Quantum_levels 12
    real Jump_probability 0.4
    real Glitch_probability 0.15
    
    comment === Energy ===
    positive Energy_min 0.5
    positive Energy_max 2.0
    
    comment === Glitch Range ===
    real Glitch_min_semitones -2
    real Glitch_max_semitones 3
    
    comment === Uncertainty ===
    positive Uncertainty_min 0.98
    positive Uncertainty_max 1.02
    
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
    # Gentle Quantum
    quantum_levels = 8
    jump_probability = 0.2
    glitch_probability = 0.05
    energy_min = 0.8
    energy_max = 1.5
    glitch_min_semitones = -1
    glitch_max_semitones = 1.5
    uncertainty_min = 0.99
    uncertainty_max = 1.01
    presetName$ = "Gentle"
elsif preset = 3
    # Moderate Quantum
    quantum_levels = 12
    jump_probability = 0.3
    glitch_probability = 0.1
    energy_min = 0.7
    energy_max = 1.8
    glitch_min_semitones = -1.5
    glitch_max_semitones = 2
    uncertainty_min = 0.98
    uncertainty_max = 1.02
    presetName$ = "Moderate"
elsif preset = 4
    # Aggressive Quantum
    quantum_levels = 16
    jump_probability = 0.5
    glitch_probability = 0.2
    energy_min = 0.5
    energy_max = 2.2
    glitch_min_semitones = -3
    glitch_max_semitones = 4
    uncertainty_min = 0.95
    uncertainty_max = 1.05
    presetName$ = "Aggressive"
elsif preset = 5
    # Extreme Quantum
    quantum_levels = 24
    jump_probability = 0.7
    glitch_probability = 0.3
    energy_min = 0.3
    energy_max = 3.0
    glitch_min_semitones = -5
    glitch_max_semitones = 6
    uncertainty_min = 0.9
    uncertainty_max = 1.1
    presetName$ = "Extreme"
elsif preset = 6
    # Glitchy Micro
    quantum_levels = 5
    jump_probability = 0.6
    glitch_probability = 0.4
    energy_min = 0.9
    energy_max = 1.2
    glitch_min_semitones = -0.5
    glitch_max_semitones = 1
    uncertainty_min = 0.995
    uncertainty_max = 1.005
    presetName$ = "Glitchy"
elsif preset = 7
    # Harmonic Leaps
    quantum_levels = 7
    jump_probability = 0.4
    glitch_probability = 0.05
    energy_min = 0.6
    energy_max = 1.8
    glitch_min_semitones = -1
    glitch_max_semitones = 1
    uncertainty_min = 0.98
    uncertainty_max = 1.02
    presetName$ = "Harmonic"
elsif preset = 8
    # Chaotic Quantum
    quantum_levels = 32
    jump_probability = 0.8
    glitch_probability = 0.5
    energy_min = 0.2
    energy_max = 4.0
    glitch_min_semitones = -8
    glitch_max_semitones = 10
    uncertainty_min = 0.8
    uncertainty_max = 1.2
    presetName$ = "Chaotic"
else
    presetName$ = "Manual"
endif

# === Validation ===
if dur <= 0
    exitScript: "The selected Sound has no positive duration."
endif
if quantum_levels < 1 or quantum_levels > 64
    exitScript: "Quantum_levels must be between 1 and 64."
endif
if jump_probability < 0 or jump_probability > 1
    exitScript: "Jump_probability must be between 0 and 1."
endif
if glitch_probability < 0 or glitch_probability > 1
    exitScript: "Glitch_probability must be between 0 and 1."
endif
if energy_min <= 0 or energy_max <= 0 or energy_max < energy_min
    exitScript: "Energy_min / Energy_max must be positive and Energy_max >= Energy_min."
endif
if glitch_max_semitones < glitch_min_semitones
    exitScript: "Glitch_max_semitones must be >= Glitch_min_semitones."
endif
if uncertainty_min <= 0 or uncertainty_max <= 0 or uncertainty_max < uncertainty_min
    exitScript: "Uncertainty range must be positive and ordered."
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

# === Harmonic Ratio Basis ===
# Twelve unique steps below the octave. Larger levels add octave bands;
# negative level offsets use the inverse ratio, so the state space is
# symmetric around unison rather than repeating the same ratios.
ratios# = {1, 16/15, 9/8, 6/5, 5/4, 4/3, 7/5, 3/2, 8/5, 5/3, 16/9, 15/8}
nRatios = size(ratios#)

# === Info ===
writeInfoLine: "=== Quantum Pitch Jumps v0.4.1 ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(dur, 2), " s, ", n_channels, " ch)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Quantum levels: ", quantum_levels
appendInfoLine: "Jump probability / 100 ms: ", jump_probability
appendInfoLine: "Glitch probability / 100 ms: ", glitch_probability
appendInfoLine: "Energy interval scaling: ", energy_min, " - ", energy_max
appendInfoLine: "Uncertainty: ", uncertainty_min, " - ", uncertainty_max
appendInfoLine: ""

# === Calculate Number of Points ===
npoints = round(dur / 0.01)
if npoints < 200
    npoints = 200
endif
if npoints > 2000
    npoints = 2000
endif

curve_dt = dur / (npoints - 1)

# Convert probability-per-100ms into a per-curve-step probability.
reference_window = 0.1
if jump_probability = 0
    jump_p_step = 0
else
    jump_p_step = 1 - (1 - jump_probability) ^ (curve_dt / reference_window)
endif
if glitch_probability = 0
    glitch_p_step = 0
else
    glitch_p_step = 1 - (1 - glitch_probability) ^ (curve_dt / reference_window)
endif

# === Mono Pitch Analysis ===
selectObject: original
if n_channels > 1
    analysisMono = Convert to mono
else
    analysisMono = Copy: "QPJ_analysis"
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
appendInfoLine: "Building quantum pitch curve..."

Create PitchTier: "quantum_pitch", xmin, xmax
pitchTier = selected("PitchTier")

# Store for visualization
maxVizPoints = min(npoints, 500)
if maxVizPoints < 1
    maxVizPoints = 1
endif
vizTimes# = zero#(maxVizPoints)
vizPitch# = zero#(maxVizPoints)
vizLevels# = zero#(maxVizPoints)
vizJumps# = zero#(maxVizPoints)
vizGlitches# = zero#(maxVizPoints)
vizFilled# = zero#(maxVizPoints)
vizStep = npoints / maxVizPoints

# Initialize quantum state
centre_level = ceiling(quantum_levels / 2)
current_level = centre_level
energy_level = 1
jump_count = 0
glitch_count = 0
limited_points = 0

# Correlated uncertainty: new target about every 50 ms, with smoothing.
uncertainty_state = randomUniform(uncertainty_min, uncertainty_max)
uncertainty_target = uncertainty_state
uncertainty_update_steps = round(0.05 / curve_dt)
if uncertainty_update_steps < 1
    uncertainty_update_steps = 1
endif
uncertainty_slew = min(1, curve_dt / 0.02)

synth_floor = 20
synth_ceil = 0.45 * orig_sr

# === Build Quantum Pitch Curve ===
for i from 0 to npoints - 1
    t = xmin + (i / (npoints - 1)) * dur

    # Quantum tunnel events with time-consistent probability.
    jumped = 0
    if randomUniform(0, 1) < jump_p_step
        current_level = randomInteger(1, quantum_levels)
        energy_level = randomUniform(energy_min, energy_max)
        jumped = 1
        jump_count += 1
    endif

    # Glitch events.
    glitch_factor = 0
    glitched = 0
    if randomUniform(0, 1) < glitch_p_step
        glitch_factor = randomUniform(glitch_min_semitones, glitch_max_semitones)
        glitched = 1
        glitch_count += 1
    endif

    # Map the current level to a UNIQUE harmonic ratio around unison.
    signed_step = current_level - centre_level
    abs_step = abs(signed_step)

    if abs_step = 0
        base_ratio = 1
    else
        octave_band = floor(abs_step / nRatios)
        ratio_pos = (abs_step mod nRatios) + 1
        if ratio_pos = 1 and abs_step > 0
            harmonic_mag = 2 ^ octave_band
        else
            harmonic_mag = ratios#[ratio_pos] * (2 ^ octave_band)
        endif

        if signed_step < 0
            base_ratio = 1 / harmonic_mag
        else
            base_ratio = harmonic_mag
        endif
    endif

    # Energy controls how strongly the interval departs from unison.
    energized_ratio = base_ratio ^ energy_level

    # Semitone glitch multiplier.
    glitch_multiplier = 2 ^ (glitch_factor / 12)

    # Correlated uncertainty.
    if (i mod uncertainty_update_steps) = 0
        uncertainty_target = randomUniform(uncertainty_min, uncertainty_max)
    endif
    uncertainty_state = uncertainty_state +
        ... (uncertainty_target - uncertainty_state) * uncertainty_slew

    final_ratio = energized_ratio * glitch_multiplier * uncertainty_state
    new_f0 = median_f0 * final_ratio

    # Synthesis safety, independent of the analysis range.
    if new_f0 < synth_floor
        new_f0 = synth_floor
        limited_points += 1
    elsif new_f0 > synth_ceil
        new_f0 = synth_ceil
        limited_points += 1
    endif

    selectObject: pitchTier
    Add point: t, new_f0

    # Visualization: sample the curve, but ACCUMULATE events into each bin.
    vizIdx = floor(i / vizStep) + 1
    if vizIdx < 1
        vizIdx = 1
    elsif vizIdx > maxVizPoints
        vizIdx = maxVizPoints
    endif

    if vizFilled#[vizIdx] = 0
        vizTimes#[vizIdx] = t
        vizPitch#[vizIdx] = new_f0
        vizLevels#[vizIdx] = current_level
        vizFilled#[vizIdx] = 1
    endif
    if jumped
        vizJumps#[vizIdx] = 1
    endif
    if glitched
        vizGlitches#[vizIdx] = 1
    endif
endfor

appendInfoLine: "Jumps: ", jump_count, " | Glitches: ", glitch_count
if limited_points > 0
    appendInfoLine: "Sampling-safe pitch limits applied: ", limited_points, " point(s)"
endif

# === Resynthesize every original channel with the shared PitchTier ===
appendInfoLine: ""
appendInfoLine: "Resynthesizing ", n_channels, " channel(s)..."

channelResults# = zero#(n_channels)

for ch from 1 to n_channels
    selectObject: original
    if n_channels = 1
        channelWork = Copy: "QPJ_ch1"
    else
        channelWork = Extract one channel: ch
        Rename: "QPJ_ch" + string$(ch)
    endif

    selectObject: channelWork
    manipulation = To Manipulation: time_step, minimum_pitch, maximum_pitch

    selectObject: manipulation
    plusObject: pitchTier
    Replace pitch tier

    selectObject: manipulation
    channelResult = Get resynthesis (overlap-add)
    Rename: "QPJ_result_ch" + string$(ch)
    channelResults#[ch] = channelResult

    removeObject: manipulation, channelWork
endfor

# Rebuild exact original channel count and time domain.
Create Sound from formula: "QPJ_result_build", n_channels,
    ... xmin, xmax, orig_sr, "0"
result = selected("Sound")

for ch from 1 to n_channels
    selectObject: result
    Formula (part): xmin, xmax, ch, ch,
        ... "object[" + string$(channelResults#[ch]) + ", 1, col]"
    removeObject: channelResults#[ch]
endfor

selectObject: result
Rename: originalName$ + "_quantum_" + presetName$

# Attenuation-only peak safety.
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
    Text: 0.5, "centre", 0.5, "half", "Quantum Pitch Jumps v0.4.1: " + originalName$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.6, 7.6, 0.7, 1.3
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.5, 2.3
    Select inner viewport: 0.6, 7.6, 1.6, 2.2
    selectObject: result
    Colour: "{0.5, 0.6, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Quantum"
    Text bottom: "yes", "Time (s)"
    
    # Quantum pitch curve
    Select outer viewport: 0, 8, 2.5, 3.8
    Select inner viewport: 0.6, 7.6, 2.7, 3.7
    
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
        minP = minimum_pitch
        maxP = maximum_pitch
    endif
    
    pMargin = (maxP - minP) * 0.1
    if pMargin < 20
        pMargin = 20
    endif
    
    Axes: xmin, xmax, minP - pMargin, maxP + pMargin
    Paint rectangle: "{0.95, 0.95, 0.95}", xmin, xmax, minP - pMargin, maxP + pMargin
    
    # Draw median line
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    Draw line: xmin, median_f0, xmax, median_f0
    Solid line
    
    # Mark jumps and glitches
    for vp from 1 to maxVizPoints
        if vizFilled#[vp] = 1 and vizJumps#[vp] = 1
            Colour: "{0.8, 0.5, 0.5}"
            Draw line: vizTimes#[vp], minP - pMargin * 0.5, vizTimes#[vp], maxP + pMargin * 0.5
        endif
        if vizFilled#[vp] = 1 and vizGlitches#[vp] = 1
            Colour: "{0.5, 0.8, 0.5}"
            Paint circle (mm): "{0.5, 0.8, 0.5}", vizTimes#[vp], vizPitch#[vp], 1
        endif
    endfor
    
    # Draw pitch curve
    Colour: "{0.4, 0.5, 0.7}"
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
    Text left: "yes", "Pitch (Hz)"
    Text bottom: "yes", "Time (s)"
    
    # Legend
    Font size: 6
    legendX = xmin + 0.03 * dur
    legendY = maxP + 0.55 * pMargin
    Colour: "{0.8, 0.5, 0.5}"
    Text: legendX, "left", legendY, "half", "Jump"
    Colour: "{0.5, 0.8, 0.5}"
    Text: legendX + 0.12 * dur, "left", legendY, "half", "Glitch"
    
    # Quantum level display
    Select outer viewport: 0, 8, 4.0, 4.8
    Select inner viewport: 0.6, 7.6, 4.1, 4.7
    
    Axes: xmin, xmax, 0, quantum_levels + 1
    Paint rectangle: "{0.95, 0.95, 0.95}", xmin, xmax, 0, quantum_levels + 1
    
    # Draw level changes
    Colour: "{0.6, 0.5, 0.7}"
    for vp from 2 to maxVizPoints
        if vizFilled#[vp] = 1 and vizFilled#[vp - 1] = 1
            Draw line: vizTimes#[vp - 1], vizLevels#[vp - 1], vizTimes#[vp], vizLevels#[vp]
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Level"
    
    # Harmonic ratios display
    Select outer viewport: 0, 8, 5.0, 5.5
    Select inner viewport: 0.6, 7.6, 5.1, 5.4
    
    nRatios = size(ratios#)
    Axes: 0, nRatios + 1, 0, 2.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, nRatios + 1, 0, 2.2
    
    # Draw ratio bars
    for r from 1 to nRatios
        barHeight = ratios#[r]
        Colour: "{0.6, 0.7, 0.8}"
        Paint rectangle: "{0.6, 0.7, 0.8}", r - 0.35, r + 0.35, 0, barHeight
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Ratios"
    
    # Stats
    Select outer viewport: 0, 8, 5.6, 5.9
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Levels: " + string$(quantum_levels) + " | Jumps: " + string$(jump_count) + " | Glitches: " + string$(glitch_count) + " | P100ms jump: " + fixed$(jump_probability, 2) + " | glitch: " + fixed$(glitch_probability, 2)
    
    Font size: 10
    Colour: "Black"

    # ----------------------------------------------------------
    # Summary strip
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.02, 6.58
    Select inner viewport: 0.60, 7.70, 6.02 + 0.04, 6.58 - 0.04
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.72, "half", "##Summary##"
    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.02, "left", 0.45, "half", "Quantized pitch states • jump sequence • rendered output"
    Text: 0.02, "left", 0.20, "half", "Quantum Pitch Jumps • run parameters are reported in the Info window"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    pageHeight = 6.68
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
