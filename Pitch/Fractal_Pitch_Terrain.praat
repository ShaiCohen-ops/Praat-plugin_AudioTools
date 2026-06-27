# ============================================================
# Praat AudioTools - Fractal_Pitch_Terrain.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Fractal Pitch Terrain - creates self-similar pitch landscapes
#   using layered oscillators with golden ratio frequency scaling.
#   Each layer adds finer detail, like Perlin noise for pitch.
#   Combines sine and square waves with chaos components.
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
originalName$ = selected$("Sound")

selectObject: original
orig_sr = Get sampling frequency
xmin = Get start time
xmax = Get end time
dur = xmax - xmin

# === Form ===
form Fractal Pitch Terrain
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Manual (configure below)
        option Gentle Fractal
        option Complex Terrain
        option Chaotic Mountains
        option Micro Fractal
        option Rhythmic Layers
        option Evolving Landscape
        option Extreme Chaos
    
    comment === Fractal Parameters ===
    natural Iterations 6
    positive Base_frequency 1.5
    positive Amplitude_decay 0.55
    positive Chaos_factor 0.3
    
    comment === Wave Mixing ===
    positive Sine_mix 0.7
    positive Square_mix 0.3
    
    comment === Frequency Progression ===
    positive Frequency_multiplier 2.618
    comment (golden ratio squared)
    positive Phase_increment 0.33
    
    comment === Pitch Scaling ===
    positive Pitch_depth 15
    positive Drift_amplitude 2
    positive Drift_frequency 0.7
    boolean Normalize_depth 1
    
    comment === Time Evolution ===
    positive Time_evolution_power 2
    positive Time_evolution_strength 0.5
    
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

# === Info ===
writeInfoLine: "=== Fractal Pitch Terrain ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(dur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Iterations: ", iterations
appendInfoLine: "Base freq: ", fixed$(base_frequency, 2), " Hz"
appendInfoLine: "Freq multiplier: ", fixed$(frequency_multiplier, 3), " (φ²≈2.618)"
appendInfoLine: "Amplitude decay: ", fixed$(amplitude_decay, 2)
appendInfoLine: "Chaos: ", fixed$(chaos_factor, 2)
appendInfoLine: "Wave mix: sin=", fixed$(sine_mix, 2), " sq=", fixed$(square_mix, 2)
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
Copy: originalName$ + "_fractal_tmp"
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
appendInfoLine: "Building fractal terrain (", iterations, " layers)..."

Create PitchTier: "fractal_pitch", xmin, xmax
pitchTier = selected("PitchTier")

# Store for visualization
maxVizPoints = min(npoints, 500)
vizTimes# = zero#(maxVizPoints)
vizShifts# = zero#(maxVizPoints)
vizFilled# = zero#(maxVizPoints)
vizLayers## = zero##(maxVizPoints, min(iterations, 6))
vizStep = npoints / maxVizPoints

# === Normalization factor ===
# The raw layer sum overshoots ±1 (it's a sum of decaying layers), so
# without normalising, pitch_depth does NOT equal the real semitone
# excursion and the pitch rails against the min/max clamp. Dividing by
# (peak-per-layer x sum-of-amplitudes) brings the sum into ~±1 so that
# pitch_depth becomes the true depth in semitones.
if amplitude_decay = 1
    ampSum = iterations
else
    ampSum = (1 - amplitude_decay ^ iterations) / (1 - amplitude_decay)
endif
peakPerLayer = sine_mix + square_mix + chaos_factor
normFactor = peakPerLayer * ampSum
if normFactor <= 0
    normFactor = 1
endif
maxTimeFactor = 1 + time_evolution_strength

# === Build Fractal Pitch Terrain ===
for i from 0 to npoints - 1
    t = xmin + (i / (npoints - 1)) * dur
    u = (t - xmin) / dur
    
    pitch_sum = 0
    current_amplitude = 1
    current_frequency = base_frequency
    current_phase = 0
    
    # Store current viz index
    vizIdx = floor(i / vizStep) + 1
    if vizIdx > maxVizPoints
        vizIdx = maxVizPoints
    endif
    
    # Fractal iteration layers
    for iter from 1 to iterations
        wave_phase = (u + current_phase) * current_frequency * 2 * pi
        sine_component = sin(wave_phase)
        
        # Square wave component
        if sin(wave_phase) > 0
            square_component = 1
        else
            square_component = -1
        endif
        
        # Wave mixing
        combined_wave = sine_mix * sine_component + square_mix * square_component
        
        # Chaos component
        chaos_phase = wave_phase * 2.3
        chaos_component = chaos_factor * sin(chaos_phase) * randomUniform(0.9, 1.1)
        
        layer_value = current_amplitude * (combined_wave + chaos_component)
        pitch_sum = pitch_sum + layer_value
        
        # Store layer for visualization
        if vizIdx >= 1 and vizIdx <= maxVizPoints and iter <= 6
            if vizFilled#[vizIdx] = 0
                vizLayers##[vizIdx, iter] = layer_value
            endif
        endif
        
        # Update fractal parameters for next layer
        current_amplitude = current_amplitude * amplitude_decay
        current_frequency = current_frequency * frequency_multiplier
        current_phase = current_phase + phase_increment * iter
    endfor
    
    # Time evolution envelope
    time_factor = 1 + time_evolution_strength * u ^ time_evolution_power

    # Scale the layer sum into semitones. When normalising, the sum is
    # divided to ~±1 and time_factor is referenced to its own maximum, so
    # pitch_depth is the true peak depth and the terrain stays in range.
    # (Toggle off to keep the original clamp-railing "extreme" character.)
    if normalize_depth
        pitch_st = pitch_depth * (pitch_sum / normFactor) * (time_factor / maxTimeFactor)
    else
        pitch_st = pitch_depth * pitch_sum * time_factor
    endif
    
    # Low-frequency drift
    drift = drift_amplitude * sin(u * drift_frequency * pi) * u * u
    pitch_st = pitch_st + drift
    
    # Store for visualization
    if vizIdx >= 1 and vizIdx <= maxVizPoints
        if vizFilled#[vizIdx] = 0
            vizTimes#[vizIdx] = t
            vizShifts#[vizIdx] = pitch_st
            vizFilled#[vizIdx] = 1
        endif
    endif
    
    # Convert semitones to frequency
    new_f0 = median_f0 * (2 ^ (pitch_st / 12))
    
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
Rename: originalName$ + "_fractal_" + presetName$

selectObject: result
Scale peak: 0.95

# === Visualization ===
if draw_visualization
    Erase all
    
    # --- Title ---
    Select outer viewport: 0, 8, 0, 0.33
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Fractal Pitch Terrain##"
    
    # --- Subtitle ---
    Select outer viewport: 0, 8, 0.33, 0.5
    Axes: 0, 1, 0, 1
    Font size: 9
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
    Font size: 8
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
    
    # Fractal terrain curve (combined pitch shift)
    Select outer viewport: 0, 8, 2.7, 4.0
    Select inner viewport: 0.6, 7.6, 2.9, 3.9
    
    # Find range
    minShift = vizShifts#[1]
    maxShift = vizShifts#[1]
    for vp from 2 to maxVizPoints
        if vizShifts#[vp] < minShift
            minShift = vizShifts#[vp]
        endif
        if vizShifts#[vp] > maxShift
            maxShift = vizShifts#[vp]
        endif
    endfor
    
    margin = (maxShift - minShift) * 0.1
    if margin < 2
        margin = 2
    endif
    
    Axes: xmin, xmax, minShift - margin, maxShift + margin
    Paint rectangle: "{0.95, 0.95, 0.95}", xmin, xmax, minShift - margin, maxShift + margin
    
    # Zero line
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    Draw line: xmin, 0, xmax, 0
    Solid line
    
    # Draw terrain
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
    
    # Find layer range
    layerMin = 0
    layerMax = 0
    numLayers = min(iterations, 6)
    for ly from 1 to numLayers
        for vp from 1 to maxVizPoints
            if vizLayers##[vp, ly] < layerMin
                layerMin = vizLayers##[vp, ly]
            endif
            if vizLayers##[vp, ly] > layerMax
                layerMax = vizLayers##[vp, ly]
            endif
        endfor
    endfor
    
    layerMargin = (layerMax - layerMin) * 0.1
    if layerMargin < 0.2
        layerMargin = 0.2
    endif
    
    Axes: xmin, xmax, layerMin - layerMargin, layerMax + layerMargin
    Paint rectangle: "{0.95, 0.95, 0.95}", xmin, xmax, layerMin - layerMargin, layerMax + layerMargin
    
    # Draw each layer with different color
    layerColors$# = {"{0.8,0.4,0.4}", "{0.4,0.8,0.4}", "{0.4,0.4,0.8}", "{0.8,0.8,0.4}", "{0.8,0.4,0.8}", "{0.4,0.8,0.8}"}
    
    for ly from 1 to numLayers
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
    
    # Layer legend
    Font size: 5
    for ly from 1 to numLayers
        Colour: layerColors$#[ly]
        xPos = 0.02 + (ly - 1) * 0.12
        Text: xPos, "left", 1.08, "half", "L" + string$(ly)
    endfor
    
    # Stats
    Select outer viewport: 0, 8, 5.6, 5.9
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    if normalize_depth
        depthLabel$ = "Depth: ±" + string$(pitch_depth) + "st"
    else
        depthLabel$ = "Depth: " + string$(pitch_depth) + "st x sum (raw)"
    endif
    Text: 0.5, "centre", 0.5, "half", "Layers: " + string$(iterations) + " | Freq×" + fixed$(frequency_multiplier, 2) + " | Decay: " + fixed$(amplitude_decay, 2) + " | Chaos: " + fixed$(chaos_factor, 2) + " | " + depthLabel$
    
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