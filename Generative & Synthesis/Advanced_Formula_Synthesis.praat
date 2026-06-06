# ============================================================
# Praat AudioTools - Advanced Formula Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Comprehensive formula-based synthesis with multiple algorithms:
#   - Simple FM
#   - Competing Oscillators (phi, e ratios)
#   - Nested FM (pseudo-chaotic)
#   - Harmonic Series
#   - Fibonacci Ratios
#   - Evolutionary Formula
#
# Usage:
#   Run this script (no input sound required).
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.2:
#   - Fixed filter object handling
#   - Fixed double fade issue
#   - Modern syntax throughout
#   - Added presets
#   - Dynamic Fibonacci computation
#   - Removed misleading formant analysis, added unique object naming
#
# Changelog v0.3:
#   - Fixed preset mode labels: presets set the numeric synthesis_mode but left
#     synthesis_mode$ at the form default, so every preset reported "Simple FM"
#     in the info window and plot title regardless of the actual mode. Each
#     preset now sets synthesis_mode$ to match.
#   - Rebuilt the visualization in the AudioTools house style (8-inch canvas,
#     title band, waveform + spectrogram, grey summary, larger fonts, black marks).
#   - Replaced non-ASCII characters (golden-ratio phi in comments, en-dash).
# ============================================================

form Advanced Formula Synthesis
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Gentle Waves
        option Golden Ratio Drone
        option Nested Complexity
        option Pure Harmonics
        option Fibonacci Bells
        option Slow Evolution
        option Dense Texture
    
    comment === Basic Settings ===
    positive Duration_s 8.0
    integer Sample_rate_Hz 44100
    positive Base_frequency_Hz 100
    integer Number_of_layers 4
    
    comment === Modulation ===
    real Modulation_depth 0.6
    real Complexity_factor 1.0
    real Evolution_speed 1.0
    boolean Randomize_parameters 1
    
    comment === Synthesis Mode ===
    optionmenu Synthesis_mode 1
        option Simple FM
        option Competing Oscillators
        option Nested FM
        option Harmonic Series
        option Fibonacci Ratios
        option Evolutionary Formula
    
    comment === Output ===
    positive Fade_time_s 2
    optionmenu Spatial_mode 1
        option Mono
        option Stereo Wide
        option Rotating
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
preset_name$ = "Custom"

if preset = 2
    # Gentle Waves
    duration_s = 10
    base_frequency_Hz = 150
    number_of_layers = 3
    modulation_depth = 0.3
    complexity_factor = 0.5
    synthesis_mode = 1
    spatial_mode = 1
    synthesis_mode$ = "Simple FM"
    preset_name$ = "GentleWaves"
elsif preset = 3
    # Golden Ratio Drone
    duration_s = 15
    base_frequency_Hz = 80
    number_of_layers = 4
    modulation_depth = 0.4
    complexity_factor = 1.0
    synthesis_mode = 2
    spatial_mode = 3
    synthesis_mode$ = "Competing Oscillators"
    preset_name$ = "GoldenRatioDrone"
elsif preset = 4
    # Nested Complexity
    duration_s = 12
    base_frequency_Hz = 120
    number_of_layers = 5
    modulation_depth = 0.7
    complexity_factor = 1.5
    synthesis_mode = 3
    spatial_mode = 2
    synthesis_mode$ = "Nested FM"
    preset_name$ = "NestedComplexity"
elsif preset = 5
    # Pure Harmonics
    duration_s = 8
    base_frequency_Hz = 110
    number_of_layers = 6
    modulation_depth = 0.2
    complexity_factor = 0.8
    synthesis_mode = 4
    spatial_mode = 1
    synthesis_mode$ = "Harmonic Series"
    preset_name$ = "PureHarmonics"
elsif preset = 6
    # Fibonacci Bells
    duration_s = 10
    base_frequency_Hz = 220
    number_of_layers = 6
    modulation_depth = 0.3
    complexity_factor = 1.0
    synthesis_mode = 5
    spatial_mode = 2
    fade_time_s = 3
    synthesis_mode$ = "Fibonacci Ratios"
    preset_name$ = "FibonacciBells"
elsif preset = 7
    # Slow Evolution
    duration_s = 20
    base_frequency_Hz = 60
    number_of_layers = 3
    modulation_depth = 0.5
    evolution_speed = 0.3
    synthesis_mode = 6
    spatial_mode = 3
    fade_time_s = 4
    synthesis_mode$ = "Evolutionary Formula"
    preset_name$ = "SlowEvolution"
elsif preset = 8
    # Dense Texture
    duration_s = 8
    base_frequency_Hz = 200
    number_of_layers = 8
    modulation_depth = 0.8
    complexity_factor = 2.0
    evolution_speed = 1.5
    synthesis_mode = 6
    spatial_mode = 2
    synthesis_mode$ = "Evolutionary Formula"
    preset_name$ = "DenseTexture"
endif

# === Validation ===
if number_of_layers > 8
    number_of_layers = 8
endif
if number_of_layers < 1
    number_of_layers = 1
endif
if fade_time_s > duration_s / 2
    fade_time_s = duration_s / 2
endif

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi
phi = (1 + sqrt(5)) / 2
euler = exp(1)

# === Compute Fibonacci ratios dynamically ===
fib1 = 1
fib2 = 1
fibRatio_1 = 1
for f from 2 to 8
    fibNew = fib1 + fib2
    fib1 = fib2
    fib2 = fibNew
    fibRatio_'f' = fib2 / fib1
endfor

# === Info ===
writeInfoLine: "=== Advanced Formula Synthesis ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Duration: ", duration_s, " s"
appendInfoLine: "Layers: ", number_of_layers
appendInfoLine: "Mode: ", synthesis_mode$
appendInfoLine: ""

# === Create output sound ===
outputSound = Create Sound from formula: "formula_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"

# === Synthesize layers ===
for layer to number_of_layers
    appendInfoLine: "Layer ", layer, "/", number_of_layers, "..."
    
    # Layer-specific randomization
    if randomize_parameters
        baseFreq = base_frequency_Hz * (0.8 + 0.4 * randomUniform(0, 1))
        modDepth = modulation_depth * (0.7 + 0.6 * randomUniform(0, 1))
        evoSpeed = evolution_speed * (0.5 + randomUniform(0, 1))
        phaseOffset = randomUniform(0, twoPi)
    else
        baseFreq = base_frequency_Hz
        modDepth = modulation_depth
        evoSpeed = evolution_speed
        phaseOffset = 0
    endif
    
    # === Mode 1: Simple FM ===
    if synthesis_mode = 1
        layerAmp = 0.6 / number_of_layers
        
        layerSound = Create Sound from formula: "layer_" + uid$, 1, 0, duration_s, sample_rate_Hz,
            ... "layerAmp * sin(twoPi * baseFreq * x * (1 + modDepth * 0.3 * sin(twoPi * 2 * x))) * (0.7 + 0.3 * sin(twoPi * 0.1 * x))"
    
    # === Mode 2: Competing Oscillators (phi, e ratios) ===
    elsif synthesis_mode = 2
        layerAmp = 0.5 / number_of_layers
        
        layerSound = Create Sound from formula: "layer_" + uid$, 1, 0, duration_s, sample_rate_Hz,
            ... "layerAmp * (sin(twoPi * baseFreq * x * (1 + 0.2 * sin(twoPi * 1.5 * x))) + 0.5 * sin(twoPi * baseFreq * phi * x * (1 + 0.3 * sin(twoPi * 2.5 * x))) + 0.3 * sin(twoPi * baseFreq * euler * x * (1 + 0.4 * sin(twoPi * 0.7 * x)))) * (0.6 + 0.4 * sin(twoPi * 0.05 * x))"
    
    # === Mode 3: Nested FM ===
    elsif synthesis_mode = 3
        layerAmp = 0.55 / number_of_layers
        complexity = complexity_factor
        
        layerSound = Create Sound from formula: "layer_" + uid$, 1, 0, duration_s, sample_rate_Hz,
            ... "layerAmp * (sin(twoPi * baseFreq * x * (1 + modDepth * 0.4 * sin(twoPi * 1.2 * complexity * x + 1.5 * sin(twoPi * 0.3 * complexity * x)))) + 0.7 * sin(twoPi * baseFreq * 1.5 * x * (1 + modDepth * 0.3 * sin(twoPi * 2.1 * complexity * x + 0.8 * sin(twoPi * 0.5 * complexity * x)))) + 0.4 * sin(twoPi * baseFreq * 2.2 * x * (1 + modDepth * 0.5 * sin(twoPi * 0.9 * complexity * x + 1.2 * sin(twoPi * 0.2 * complexity * x))))) * (0.5 + 0.5 * sin(twoPi * 0.08 * x)) * exp(-0.3 * x / duration_s)"
    
    # === Mode 4: Harmonic Series ===
    elsif synthesis_mode = 4
        harmonic = layer
        layerFreq = base_frequency_Hz * harmonic
        layerAmp = 0.7 / (number_of_layers * harmonic)
        complexity = complexity_factor
        
        layerSound = Create Sound from formula: "layer_" + uid$, 1, 0, duration_s, sample_rate_Hz,
            ... "layerAmp * sin(twoPi * layerFreq * x + phaseOffset) * (0.8 + 0.2 * sin(twoPi * complexity * 0.15 * x)) * (1 - 0.3 * sin(twoPi * complexity * 0.08 * x))"
    
    # === Mode 5: Fibonacci Ratios ===
    elsif synthesis_mode = 5
        # Get cumulative Fibonacci ratio for this layer
        fibCum = 1
        for f from 2 to layer
            fibCum = fibCum * fibRatio_'f'
        endfor
        
        layerFreq = base_frequency_Hz * fibCum
        layerAmp = 0.65 / (number_of_layers * sqrt(fibCum))
        
        if randomize_parameters
            modRate = 0.5 + randomUniform(0, 1.5)
        else
            modRate = 1.0
        endif
        
        complexity = complexity_factor
        
        layerSound = Create Sound from formula: "layer_" + uid$, 1, 0, duration_s, sample_rate_Hz,
            ... "layerAmp * sin(twoPi * layerFreq * x * (1 + modDepth * 0.2 * sin(twoPi * modRate * x))) * (0.6 + 0.4 * sin(twoPi * complexity * 0.1 * x))"
    
    # === Mode 6: Evolutionary Formula ===
    elsif synthesis_mode = 6
        layerAmp = 0.8 / number_of_layers
        complexity = complexity_factor
        
        layerSound = Create Sound from formula: "layer_" + uid$, 1, 0, duration_s, sample_rate_Hz,
            ... "layerAmp * (sin(twoPi * baseFreq * x * (1 + modDepth * 0.5 * sin(twoPi * 0.3 * evoSpeed * x) + modDepth * 0.3 * sin(twoPi * 2 * evoSpeed * x))) * (0.7 + 0.3 * sin(twoPi * 0.1 * evoSpeed * x)) + 0.8 * sin(twoPi * baseFreq * 1.333 * x * (1 + modDepth * 0.4 * sin(twoPi * 0.5 * evoSpeed * x + 0.7 * sin(twoPi * 1.2 * evoSpeed * x)))) * (0.6 + 0.4 * sin(twoPi * 0.07 * evoSpeed * x)) + 0.6 * sin(twoPi * baseFreq * 1.667 * x * (1 + modDepth * 0.6 * sin(twoPi * 0.8 * evoSpeed * x + 1.2 * sin(twoPi * 0.4 * evoSpeed * x)))) * (0.5 + 0.5 * sin(twoPi * 0.12 * evoSpeed * x)) + 0.4 * sin(twoPi * baseFreq * 2.0 * x * (1 + modDepth * 0.7 * sin(twoPi * 1.1 * evoSpeed * x + 1.5 * sin(twoPi * 0.6 * evoSpeed * x)))) * (0.4 + 0.6 * sin(twoPi * 0.15 * evoSpeed * x))) * (0.8 + 0.2 * sin(twoPi * 0.02 * evoSpeed * x)) * (1 - complexity * 0.3 * x / duration_s)"
    endif
    
    # Add layer to output
    selectObject: layerSound
    layerName$ = selected$("Sound")
    
    selectObject: outputSound
    Formula: "self + Sound_'layerName$'[]"
    
    removeObject: layerSound
endfor

# === Apply Fade (single pass) ===
appendInfoLine: "Applying envelope..."
selectObject: outputSound
Formula: "if x < fade_time_s then self * (x / fade_time_s) else self fi"
fadeOutStart = duration_s - fade_time_s
Formula: "if x > fadeOutStart then self * ((duration_s - x) / fade_time_s) else self fi"

# === Spatial Processing ===
if spatial_mode = 2
    appendInfoLine: "Creating stereo width..."
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * 0.8"
    Filter (pass Hann band): 0, 4000, 100
    leftFiltered = selected("Sound")
    removeObject: leftSound
    leftSound = leftFiltered
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * 0.8"
    Filter (pass Hann band): 200, 8000, 100
    rightFiltered = selected("Sound")
    removeObject: rightSound
    rightSound = rightFiltered
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "formula_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound
    
elsif spatial_mode = 3
    appendInfoLine: "Creating rotating stereo..."
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * (0.6 + 0.4 * cos(twoPi * 0.2 * x))"
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * (0.6 + 0.4 * sin(twoPi * 0.2 * x))"
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "formula_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound
else
    selectObject: outputSound
    Rename: "formula_" + preset_name$
endif

# === Normalize ===
if normalize_output
    selectObject: outputSound
    Scale peak: 0.9
endif

# === Visualization ===
if draw_visualization
    appendInfoLine: "Drawing visualization..."
    @drawSpectrogram: duration_s
endif

# === Play ===
if play_result
    selectObject: outputSound
    Play
endif

# === Final Selection ===
selectObject: outputSound

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# ==============================================================================
# Procedure: drawSpectrogram
# ==============================================================================
procedure drawSpectrogram: .duration

    Erase all

    # --- Title (own clear band) ---
    Select outer viewport: 0, 8, 0.1, 0.7
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Formula Synthesis: " + preset_name$ + " (" + synthesis_mode$ + ")"

    # --- Mono display copy ---
    if spatial_mode > 1
        selectObject: outputSound
        Extract one channel: 1
        .disp = selected("Sound")
    else
        selectObject: outputSound
        Copy: "disp_" + uid$
        .disp = selected("Sound")
    endif

    # --- Panel 1: Waveform ---
    Select outer viewport: 0, 8, 0.9, 2.4
    Select inner viewport: 0.75, 7.6, 1.05, 2.3
    selectObject: .disp
    Colour: "{0.20, 0.45, 0.65}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 10
    Text left: "yes", "Output"

    # --- Panel 2: Spectrogram ---
    Select outer viewport: 0, 8, 2.6, 4.9
    Select inner viewport: 0.75, 7.6, 2.75, 4.8
    selectObject: .disp
    .maxFreqSpec = min(6000, max(2000, base_frequency_Hz * number_of_layers * 3))
    To Spectrogram: 0.03, .maxFreqSpec, 0.005, 20, "Gaussian"
    .spec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: .spec
    removeObject: .disp

    Select inner viewport: 0.75, 7.6, 2.75, 4.8
    Axes: 0, .duration, 0, .maxFreqSpec
    Colour: "Black"
    Draw inner box
    Font size: 9
    Marks left: 5, "yes", "yes", "no"
    Marks bottom every: 1, 1, "yes", "yes", "no"
    Font size: 10
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Frequency (Hz)"

    # --- Summary panel (grey) ---
    if spatial_mode = 2
        .spatial$ = "Stereo Wide"
    elsif spatial_mode = 3
        .spatial$ = "Rotating"
    else
        .spatial$ = "Mono"
    endif
    Select outer viewport: 0, 8, 5.0, 5.4
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 8
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.5, "centre", 0.5, "half", "Base: " + fixed$(base_frequency_Hz, 0) + " Hz | Mod: " + fixed$(modulation_depth, 2) + " | Complexity: " + fixed$(complexity_factor, 1) + " | Layers: " + string$(number_of_layers) + " | " + .spatial$
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc