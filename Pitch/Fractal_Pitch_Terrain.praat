# ============================================================
# Praat AudioTools - Fractal_Pitch_Terrain.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Fractal Pitch Terrain - creates self-similar pitch landscapes
#   using layered oscillators with multiplicative frequency scaling.
#   The generated terrain is applied as a time-varying transposition
#   of the source F0 contour, preserving the source melody/intonation.
#
# Changelog v0.5:
#   - Compacts the main form around macro musical terrain controls.
#   - Moves secondary fractal-shaping and pitch-analysis controls to an optional Advanced settings dialog.
#   - Preserves all previous defaults and DSP/analysis behavior.
# Changelog v0.4: visualization standardization only - unified typography, summary/full-page Picture framing; DSP/analysis unchanged.
# Changelog v0.4:
#   - Preserves the detected source F0 contour instead of replacing it
#     with a terrain around one median pitch.
#   - Preserves the original number of channels.
#   - Base_frequency and Drift_frequency now operate in real Hz
#     using elapsed time in seconds.
#   - Uses a fixed 100-Hz terrain control grid and includes endTime.
#   - Fractal layers above the safe control-grid bandwidth are omitted
#     rather than temporally aliasing into false low-frequency motion.
#   - Normalize_depth is based on the actually active fractal layers.
#   - Separates source pitch-analysis limits from target F0 safety limits.
#   - Stops clearly if no usable source pitch is detected.
#   - Adds parameter validation.
#   - Visualization decimation always includes the exact endpoint and
#     ignores unfilled slots in range calculations.
#   - Final peak handling is attenuation-only.
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
nChannels = Get number of channels

# === Form ===
form Fractal Pitch Terrain v0.5
    comment Select a Sound object first

    comment === Terrain ===
    optionmenu Preset 1
        option Manual (configure below)
        option Gentle Fractal
        option Complex Terrain
        option Chaotic Mountains
        option Micro Fractal
        option Rhythmic Layers
        option Evolving Landscape
        option Extreme Chaos

    natural Iterations 6
    positive Base_frequency 1.5
    positive Chaos_factor 0.3
    positive Pitch_depth 15
    positive Drift_amplitude 2
    positive Drift_frequency 0.7
    positive Time_evolution_strength 0.5

    boolean Advanced_settings 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Advanced defaults: identical to the previous main-form defaults.
amplitude_decay = 0.55
sine_mix = 0.7
square_mix = 0.3
frequency_multiplier = 2.618
phase_increment = 0.33
normalize_depth = 1
time_evolution_power = 2
time_step = 0.005
minimum_pitch = 50
maximum_pitch = 900

if advanced_settings
    beginPause: "Fractal Pitch Terrain v0.5 - Advanced settings"
        comment: "=== Fractal shaping ==="
        positive: "Amplitude_decay", "0.55"
        positive: "Sine_mix", "0.7"
        positive: "Square_mix", "0.3"
        positive: "Frequency_multiplier", "2.618"
        positive: "Phase_increment", "0.33"
        boolean: "Normalize_depth", 1
        positive: "Time_evolution_power", "2"
        comment: "=== Pitch analysis ==="
        positive: "Time_step", "0.005"
        positive: "Minimum_pitch", "50"
        positive: "Maximum_pitch", "900"
    clicked = endPause: "Continue", 1
endif

# === Apply Presets ===
if preset = 2
    # Gentle Fractal
    iterations = 4
    base_frequency = 1.2
    amplitude_decay = 0.6
    chaos_factor = 0.1
    sine_mix = 0.9
    square_mix = 0.1
    frequency_multiplier = 2.0
    pitch_depth = 8
    drift_amplitude = 1
    time_evolution_strength = 0.2
elsif preset = 3
    # Complex Terrain
    iterations = 7
    base_frequency = 1.5
    amplitude_decay = 0.55
    chaos_factor = 0.25
    sine_mix = 0.7
    square_mix = 0.3
    frequency_multiplier = 2.618
    pitch_depth = 18
    drift_amplitude = 2
    time_evolution_strength = 0.4
elsif preset = 4
    # Chaotic Mountains
    iterations = 8
    base_frequency = 2.0
    amplitude_decay = 0.45
    chaos_factor = 0.6
    sine_mix = 0.5
    square_mix = 0.5
    frequency_multiplier = 3.0
    pitch_depth = 25
    drift_amplitude = 3
    time_evolution_strength = 0.7
elsif preset = 5
    # Micro Fractal
    iterations = 5
    base_frequency = 0.8
    amplitude_decay = 0.7
    chaos_factor = 0.05
    sine_mix = 0.95
    square_mix = 0.05
    frequency_multiplier = 1.5
    pitch_depth = 4
    drift_amplitude = 0.5
    time_evolution_strength = 0.1
elsif preset = 6
    # Rhythmic Layers
    iterations = 6
    base_frequency = 3.0
    amplitude_decay = 0.5
    chaos_factor = 0.15
    sine_mix = 0.4
    square_mix = 0.6
    frequency_multiplier = 2.0
    pitch_depth = 12
    drift_amplitude = 1.5
    time_evolution_strength = 0.3
elsif preset = 7
    # Evolving Landscape
    iterations = 7
    base_frequency = 1.3
    amplitude_decay = 0.58
    chaos_factor = 0.2
    sine_mix = 0.8
    square_mix = 0.2
    frequency_multiplier = 2.3
    pitch_depth = 20
    drift_amplitude = 2.5
    time_evolution_strength = 0.8
elsif preset = 8
    # Extreme Chaos
    iterations = 10
    base_frequency = 2.5
    amplitude_decay = 0.4
    chaos_factor = 0.8
    sine_mix = 0.3
    square_mix = 0.7
    frequency_multiplier = 3.5
    pitch_depth = 35
    drift_amplitude = 4
    time_evolution_strength = 1.0
endif

# === Validate Parameters ===
if amplitude_decay <= 0 or amplitude_decay > 1
    exitScript: "Amplitude_decay must be greater than 0 and no greater than 1."
endif
if chaos_factor < 0
    exitScript: "Chaos_factor must be non-negative."
endif
if sine_mix < 0 or square_mix < 0
    exitScript: "Sine_mix and Square_mix must be non-negative."
endif
if sine_mix + square_mix + chaos_factor <= 0
    exitScript: "At least one of Sine_mix, Square_mix, or Chaos_factor must be greater than zero."
endif
if frequency_multiplier <= 0
    exitScript: "Frequency_multiplier must be greater than zero."
endif
if phase_increment < 0
    exitScript: "Phase_increment must be non-negative."
endif
if pitch_depth < 0
    exitScript: "Pitch_depth must be non-negative."
endif
if drift_amplitude < 0 or drift_frequency < 0
    exitScript: "Drift_amplitude and Drift_frequency must be non-negative."
endif
if time_evolution_power < 0 or time_evolution_strength < 0
    exitScript: "Time evolution parameters must be non-negative."
endif
if time_step <= 0
    exitScript: "Time_step must be greater than zero."
endif
if minimum_pitch >= maximum_pitch
    exitScript: "Minimum_pitch must be lower than Maximum_pitch."
endif
if maximum_pitch >= orig_sr / 2
    exitScript: "Maximum_pitch must be below Nyquist (" + fixed$(orig_sr / 2, 1) + " Hz)."
endif

# === Get Preset Name ===
if preset = 1
    presetName$ = "Manual"
elsif preset = 2
    presetName$ = "Gentle"
elsif preset = 3
    presetName$ = "Complex"
elsif preset = 4
    presetName$ = "Chaotic"
elsif preset = 5
    presetName$ = "Micro"
elsif preset = 6
    presetName$ = "Rhythmic"
elsif preset = 7
    presetName$ = "Evolving"
else
    presetName$ = "Extreme"
endif

# === Fixed Control Grid ===
controlStep = 0.01
npoints = ceiling(dur / controlStep) + 1
if npoints < 2
    npoints = 2
endif

# A 100-Hz sampled control signal can represent modulation only below 50 Hz.
# Keep a small safety margin to avoid control-rate temporal aliasing.
maxTerrainHz = 45

if base_frequency > maxTerrainHz
    exitScript: "Base_frequency is above the safe 100-Hz terrain-control bandwidth (" + string$(maxTerrainHz) + " Hz)."
endif

# === Determine Active Fractal Layers and Normalization ===
activeLayers = 0
activeAmpSum = 0
omittedLayers = 0
testFrequency = base_frequency
testAmplitude = 1

for iter from 1 to iterations
    if testFrequency <= maxTerrainHz
        activeLayers += 1
        activeAmpSum += testAmplitude
    else
        omittedLayers += 1
    endif
    testAmplitude = testAmplitude * amplitude_decay
    testFrequency = testFrequency * frequency_multiplier
endfor

if activeLayers < 1
    exitScript: "No fractal layer falls inside the safe terrain-control bandwidth."
endif

peakPerLayer = sine_mix + square_mix + chaos_factor
normFactor = peakPerLayer * activeAmpSum
if normFactor <= 0
    normFactor = 1
endif

maxTimeFactor = 1 + time_evolution_strength

# === Info ===
writeInfoLine: "=== Fractal Pitch Terrain v0.5 ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(dur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Channels preserved: ", nChannels
appendInfoLine: ""
appendInfoLine: "Requested layers: ", iterations
appendInfoLine: "Active layers: ", activeLayers
if omittedLayers > 0
    appendInfoLine: "Layers omitted above ", maxTerrainHz, " Hz control bandwidth: ", omittedLayers
endif
appendInfoLine: "Base freq: ", fixed$(base_frequency, 2), " Hz"
appendInfoLine: "Freq multiplier: ", fixed$(frequency_multiplier, 3)
appendInfoLine: "Amplitude decay: ", fixed$(amplitude_decay, 2)
appendInfoLine: "Chaos: ", fixed$(chaos_factor, 2)
appendInfoLine: "Wave mix: sin=", fixed$(sine_mix, 2), " sq=", fixed$(square_mix, 2)
appendInfoLine: ""

# === Mono Pitch Analysis Reference ===
selectObject: original
if nChannels > 1
    analysisMono = Convert to mono
else
    analysisMono = Copy: originalName$ + "_fractal_analysis"
endif

selectObject: analysisMono
analysisPitch = To Pitch: time_step, minimum_pitch, maximum_pitch

selectObject: analysisPitch
median_f0 = Get quantile: 0, 0, 0.5, "Hertz"

if median_f0 = undefined
    removeObject: analysisPitch, analysisMono
    exitScript: "No usable pitch was detected." + newline$
        ... + "Fractal Pitch Terrain requires voiced / periodic material."
endif

appendInfoLine: "Median detected pitch: ", fixed$(median_f0, 1), " Hz"
appendInfoLine: "Building fractal terrain..."

# === Create Target Pitch Tier ===
Create PitchTier: "fractal_pitch", xmin, xmax
pitchTier = selected("PitchTier")

# === Visualization Storage ===
maxVizPoints = min(npoints, 500)
vizTimes# = zero#(maxVizPoints)
vizShifts# = zero#(maxVizPoints)
vizFilled# = zero#(maxVizPoints)
numVizLayers = min(activeLayers, 6)
vizLayers## = zero##(maxVizPoints, numVizLayers)

# === Build Fractal Pitch Terrain ===
voicedPoints = 0
limitedPitchPoints = 0
targetMinHz = 20
targetMaxHz = 0.45 * orig_sr

for i from 0 to npoints - 1
    if i = npoints - 1
        t = xmax
        u = 1
    else
        t = min(xmax, xmin + i * controlStep)
        u = (t - xmin) / dur
    endif
    elapsed = t - xmin

    pitch_sum = 0
    current_amplitude = 1
    current_frequency = base_frequency
    current_phase_cycles = 0
    activeIndex = 0

    # Deterministic visualization decimation; first and last samples map
    # exactly to first and last visualization slots.
    vizIdx = floor(i * (maxVizPoints - 1) / (npoints - 1)) + 1
    if vizIdx < 1
        vizIdx = 1
    elsif vizIdx > maxVizPoints
        vizIdx = maxVizPoints
    endif

    for iter from 1 to iterations
        if current_frequency <= maxTerrainHz
            activeIndex += 1

            # Frequency is now in real Hz: cycles = frequency * elapsed seconds.
            wave_phase = 2 * pi * (current_frequency * elapsed + current_phase_cycles)
            sine_component = sin(wave_phase)

            if sine_component >= 0
                square_component = 1
            else
                square_component = -1
            endif

            combined_wave = sine_mix * sine_component + square_mix * square_component

            chaos_phase = wave_phase * 2.3
            chaos_component = chaos_factor * sin(chaos_phase) * randomUniform(0.9, 1.1)

            layer_value = current_amplitude * (combined_wave + chaos_component)
            pitch_sum += layer_value

            if activeIndex <= numVizLayers
                if vizFilled#[vizIdx] = 0 or i = npoints - 1
                    vizLayers##[vizIdx, activeIndex] = layer_value
                endif
            endif
        endif

        current_amplitude = current_amplitude * amplitude_decay
        current_frequency = current_frequency * frequency_multiplier
        current_phase_cycles = current_phase_cycles + phase_increment * iter
    endfor

    # Time evolution.
    time_factor = 1 + time_evolution_strength * (u ^ time_evolution_power)

    if normalize_depth
        pitch_st = pitch_depth * (pitch_sum / normFactor) * (time_factor / maxTimeFactor)
    else
        pitch_st = pitch_depth * pitch_sum * time_factor
    endif

    # Drift frequency is now true Hz and starts at zero contribution.
    drift = drift_amplitude * sin(2 * pi * drift_frequency * elapsed) * u * u
    pitch_st += drift

    if vizFilled#[vizIdx] = 0 or i = npoints - 1
        vizTimes#[vizIdx] = t
        vizShifts#[vizIdx] = pitch_st
        vizFilled#[vizIdx] = 1
    endif

    # Preserve source melody/intonation: apply terrain as a transposition
    # of the detected source F0 at this exact time.
    selectObject: analysisPitch
    source_f0 = Get value at time: t, "Hertz", "Linear"

    if source_f0 <> undefined and source_f0 > 0
        new_f0 = source_f0 * (2 ^ (pitch_st / 12))

        if new_f0 < targetMinHz
            new_f0 = targetMinHz
            limitedPitchPoints += 1
        elsif new_f0 > targetMaxHz
            new_f0 = targetMaxHz
            limitedPitchPoints += 1
        endif

        selectObject: pitchTier
        Add point: t, new_f0
        voicedPoints += 1
    endif
endfor

if voicedPoints = 0
    removeObject: pitchTier, analysisPitch, analysisMono
    exitScript: "Pitch analysis produced no usable terrain control points."
endif

appendInfoLine: "Pitch control points: ", voicedPoints
if limitedPitchPoints > 0
    appendInfoLine: "Sampling-safe target limits applied: ", limitedPitchPoints, " point(s)"
endif

# === Resynthesize All Original Channels ===
appendInfoLine: "Resynthesizing ", nChannels, " channel(s)..."

selectObject: original
result = Copy: originalName$ + "_fractal_" + presetName$
Formula: ~ 0

for ch from 1 to nChannels
    selectObject: original
    if nChannels = 1
        channelWork = Copy: originalName$ + "_fractal_ch1"
    else
        channelWork = Extract one channel: ch
        Rename: originalName$ + "_fractal_ch" + string$(ch)
    endif

    selectObject: channelWork
    channelManip = To Manipulation: time_step, minimum_pitch, maximum_pitch

    selectObject: pitchTier
    plusObject: channelManip
    Replace pitch tier

    selectObject: channelManip
    channelRes = Get resynthesis (overlap-add)

    selectObject: result
    Formula (part): xmin, xmax, ch, ch, "object['channelRes:0', 1, col]"

    removeObject: channelManip, channelWork, channelRes
endfor

removeObject: pitchTier, analysisPitch, analysisMono

# === Attenuation-only Peak Safety ===
selectObject: result
finalPeak = Get absolute extremum: 0, 0, "None"
if finalPeak > 0.95
    Scale peak: 0.95
    safetyApplied = 1
else
    safetyApplied = 0
endif

# === Visualization ===
if draw_visualization
    Erase all

    # --- Title ---
    Select outer viewport: 0, 8, 0, 0.33
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Fractal Pitch Terrain v0.5##"

    # --- Subtitle ---
    Select outer viewport: 0, 8, 0.33, 0.5
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", 0.5, "half", originalName$ + " | " + presetName$

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
    Colour: "{0.6, 0.7, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Fractal"
    Text bottom: "yes", "Time (s)"

    # Fractal terrain curve
    Select outer viewport: 0, 8, 2.7, 4.0
    Select inner viewport: 0.6, 7.6, 2.9, 3.9

    rangeStarted = 0
    for vp from 1 to maxVizPoints
        if vizFilled#[vp] = 1
            if rangeStarted = 0
                minShift = vizShifts#[vp]
                maxShift = vizShifts#[vp]
                rangeStarted = 1
            else
                if vizShifts#[vp] < minShift
                    minShift = vizShifts#[vp]
                endif
                if vizShifts#[vp] > maxShift
                    maxShift = vizShifts#[vp]
                endif
            endif
        endif
    endfor

    if rangeStarted = 0
        minShift = -1
        maxShift = 1
    endif

    margin = (maxShift - minShift) * 0.1
    if margin < 2
        margin = 2
    endif

    Axes: xmin, xmax, minShift - margin, maxShift + margin
    Paint rectangle: "{0.95, 0.95, 0.95}", xmin, xmax, minShift - margin, maxShift + margin

    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    Draw line: xmin, 0, xmax, 0
    Solid line

    Colour: "{0.4, 0.6, 0.5}"
    Line width: 1.5
    for vp from 2 to maxVizPoints
        if vizFilled#[vp] = 1 and vizFilled#[vp - 1] = 1
            Draw line: vizTimes#[vp - 1], vizShifts#[vp - 1], vizTimes#[vp], vizShifts#[vp]
        endif
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Pitch (st)"
    Text bottom: "yes", "Time (s)"

    # Layer decomposition
    Select outer viewport: 0, 8, 4.2, 5.5
    Select inner viewport: 0.6, 7.6, 4.4, 5.4

    layerStarted = 0
    for ly from 1 to numVizLayers
        for vp from 1 to maxVizPoints
            if vizFilled#[vp] = 1
                value = vizLayers##[vp, ly]
                if layerStarted = 0
                    layerMin = value
                    layerMax = value
                    layerStarted = 1
                else
                    if value < layerMin
                        layerMin = value
                    endif
                    if value > layerMax
                        layerMax = value
                    endif
                endif
            endif
        endfor
    endfor

    if layerStarted = 0
        layerMin = -1
        layerMax = 1
    endif

    layerMargin = (layerMax - layerMin) * 0.1
    if layerMargin < 0.2
        layerMargin = 0.2
    endif

    Axes: xmin, xmax, layerMin - layerMargin, layerMax + layerMargin
    Paint rectangle: "{0.95, 0.95, 0.95}", xmin, xmax, layerMin - layerMargin, layerMax + layerMargin

    layerColors$# = {"{0.8,0.4,0.4}", "{0.4,0.8,0.4}", "{0.4,0.4,0.8}", "{0.8,0.8,0.4}", "{0.8,0.4,0.8}", "{0.4,0.8,0.8}"}

    for ly from 1 to numVizLayers
        Colour: layerColors$#[ly]
        for vp from 2 to maxVizPoints
            if vizFilled#[vp] = 1 and vizFilled#[vp - 1] = 1
                Draw line: vizTimes#[vp - 1], vizLayers##[vp - 1, ly], vizTimes#[vp], vizLayers##[vp, ly]
            endif
        endfor
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Layers"

    Font size: 6
    for ly from 1 to numVizLayers
        Colour: layerColors$#[ly]
        xPos = xmin + (xmax - xmin) * (0.02 + (ly - 1) * 0.12)
        Text: xPos, "left", layerMax + layerMargin * 0.6, "half", "L" + string$(ly)
    endfor

    # Stats
    Select outer viewport: 0, 8, 5.6, 5.9
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    if normalize_depth
        depthLabel$ = "Depth: ±" + string$(pitch_depth) + "st"
    else
        depthLabel$ = "Depth: " + string$(pitch_depth) + "st x sum (raw)"
    endif
    Text: 0.5, "centre", 0.5, "half",
        ... "Active layers: " + string$(activeLayers) +
        ... " | Freq×" + fixed$(frequency_multiplier, 2) +
        ... " | Decay: " + fixed$(amplitude_decay, 2) +
        ... " | Chaos: " + fixed$(chaos_factor, 2) +
        ... " | " + depthLabel$

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
    Text: 0.02, "left", 0.45, "half", "Fractal control terrain • pitch trajectory • rendered output"
    Text: 0.02, "left", 0.20, "half", "Fractal Pitch Terrain • run parameters are reported in the Info window"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    pageHeight = 6.68
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Output channels: ", nChannels
appendInfoLine: "Active fractal layers: ", activeLayers
appendInfoLine: "Peak safety applied: ", safetyApplied

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result
