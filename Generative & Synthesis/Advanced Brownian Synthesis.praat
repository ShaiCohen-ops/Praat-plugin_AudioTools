# ============================================================
# Praat AudioTools - Advanced Brownian Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025) - Optimized & Fixed
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Brownian motion-based synthesis with multiple layers and modes.
#   Generates evolving, organic textures through frequency random walks.
#
# Usage:
#   Run this script (no input sound required).
#   Select a preset or adjust custom parameters.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Advanced Brownian Synthesis
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Default Walk
        option Tight Knots
        option Loose Drift
        option Chaotic Swarm
        option Harmonic Bells
        option Deep Drone
        option Spectral Shimmer
        option Insect Swarm
    
    comment === Basic Settings ===
    positive Duration_s 10
    integer Sample_rate_Hz 44100
    positive Base_frequency_Hz 150
    integer Number_of_layers 4
    
    comment === Brownian Motion ===
    real Frequency_spread_Hz 100
    real Step_size 10
    boolean Enable_drift 1
    real Drift_force 0.1
    
    comment === Synthesis Mode ===
    optionmenu Synthesis_mode 1
        option Brownian Walk
        option Brownian Chaos
        option Brownian Harmonics
        option Pulsed Brownian
    
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
    duration_s = 10
    base_frequency_Hz = 150
    number_of_layers = 4
    frequency_spread_Hz = 100
    step_size = 10
    enable_drift = 1
    drift_force = 0.1
    fade_time_s = 2
    synthesis_mode = 1
    spatial_mode = 1
    preset_name$ = "DefaultWalk"
elsif preset = 3
    duration_s = 8
    base_frequency_Hz = 200
    number_of_layers = 6
    frequency_spread_Hz = 50
    step_size = 5
    enable_drift = 1
    drift_force = 0.2
    fade_time_s = 1
    synthesis_mode = 1
    spatial_mode = 2
    preset_name$ = "TightKnots"
elsif preset = 4
    duration_s = 15
    base_frequency_Hz = 100
    number_of_layers = 3
    frequency_spread_Hz = 200
    step_size = 20
    enable_drift = 1
    drift_force = 0.05
    fade_time_s = 3
    synthesis_mode = 1
    spatial_mode = 3
    preset_name$ = "LooseDrift"
elsif preset = 5
    duration_s = 12
    base_frequency_Hz = 180
    number_of_layers = 8
    frequency_spread_Hz = 80
    step_size = 15
    enable_drift = 1
    drift_force = 0.15
    fade_time_s = 2
    synthesis_mode = 2
    spatial_mode = 2
    preset_name$ = "ChaoticSwarm"
elsif preset = 6
    duration_s = 10
    base_frequency_Hz = 220
    number_of_layers = 5
    frequency_spread_Hz = 0
    step_size = 8
    enable_drift = 1
    drift_force = 0.1
    fade_time_s = 2
    synthesis_mode = 3
    spatial_mode = 1
    preset_name$ = "HarmonicBells"
elsif preset = 7
    duration_s = 20
    base_frequency_Hz = 55
    number_of_layers = 3
    frequency_spread_Hz = 20
    step_size = 3
    enable_drift = 1
    drift_force = 0.3
    fade_time_s = 5
    synthesis_mode = 1
    spatial_mode = 3
    preset_name$ = "DeepDrone"
elsif preset = 8
    duration_s = 12
    base_frequency_Hz = 440
    number_of_layers = 6
    frequency_spread_Hz = 50
    step_size = 25
    enable_drift = 1
    drift_force = 0.08
    fade_time_s = 2
    synthesis_mode = 3
    spatial_mode = 2
    preset_name$ = "SpectralShimmer"
elsif preset = 9
    duration_s = 8
    base_frequency_Hz = 800
    number_of_layers = 10
    frequency_spread_Hz = 400
    step_size = 50
    enable_drift = 1
    drift_force = 0.05
    fade_time_s = 1
    synthesis_mode = 2
    spatial_mode = 2
    preset_name$ = "InsectSwarm"
endif

# === Validation ===
if number_of_layers > 16
    number_of_layers = 16
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
controlRate = 200

# === Info ===
writeInfoLine: "=== Advanced Brownian Synthesis ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Duration: ", duration_s, " s"
appendInfoLine: "Layers: ", number_of_layers
appendInfoLine: "Mode: ", synthesis_mode$
appendInfoLine: ""

# === Create output sound ===
outputSound = Create Sound from formula: "brownian_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"

# === Process each layer ===
for layer to number_of_layers
    appendInfoLine: "Layer ", layer, "/", number_of_layers, "..."
    
    # Initialize layer parameters based on mode
    if synthesis_mode = 1
        voiceFreq = base_frequency_Hz + (layer - 1) * frequency_spread_Hz
        chaosFactor = step_size
        ampBase = 0.6 / number_of_layers
        targetFreq = base_frequency_Hz + (layer - 1) * frequency_spread_Hz
    elsif synthesis_mode = 2
        voiceFreq = base_frequency_Hz * (0.5 + layer * 0.3)
        chaosFactor = step_size * (1 + layer * 0.5)
        ampBase = 0.7 / number_of_layers
        targetFreq = base_frequency_Hz * 2
    elsif synthesis_mode = 3
        voiceFreq = base_frequency_Hz * layer
        chaosFactor = step_size * (0.5 + layer * 0.2)
        ampBase = (0.5 / number_of_layers) / layer
        targetFreq = base_frequency_Hz * layer
    elsif synthesis_mode = 4
        voiceFreq = base_frequency_Hz * (0.8 + layer * 0.4)
        chaosFactor = step_size
        ampBase = 0.7 / number_of_layers
        targetFreq = base_frequency_Hz
        pulseRate = 2 + layer * 1.5
    endif
    
    # --- Create control-rate sounds ---
    ampCtrl = Create Sound from formula: "ampCtrl_" + uid$, 1, 0, duration_s, controlRate, "0"
    phaseCtrl = Create Sound from formula: "phaseCtrl_" + uid$, 1, 0, duration_s, controlRate, "0"
    
    selectObject: ampCtrl
    nControlPoints = Get number of samples
    timeStep = 1 / controlRate
    
    # --- Compute trajectory with cumulative phase ---
    voicePhase = 0
    
    for cp to nControlPoints
        currentTime = (cp - 1) * timeStep
        
        # Brownian step
        if synthesis_mode = 2
            brownianStep = randomGauss(0, 1) * chaosFactor
            if randomUniform(0, 1) < 0.1
                brownianStep = brownianStep * 5
            endif
        else
            brownianStep = randomGauss(0, 1) * chaosFactor
        endif
        
        # Apply drift
        if enable_drift
            drift = (targetFreq - voiceFreq) * drift_force * timeStep
            brownianStep = brownianStep + drift
        endif
        
        # Update frequency
        voiceFreq = voiceFreq + brownianStep
        voiceFreq = max(30, min(8000, voiceFreq))
        
        # Accumulate phase
        voicePhase = voicePhase + twoPi * voiceFreq * timeStep
        
        # Calculate amplitude
        if synthesis_mode = 2
            stability = exp(-abs(brownianStep) / chaosFactor)
            voiceAmp = ampBase * stability
        elsif synthesis_mode = 4
            pulse = 0.2 + 0.8 * max(0, sin(twoPi * pulseRate * currentTime) - 0.7) / 0.3
            if pulse > 1
                pulse = 1
            endif
            voiceAmp = ampBase * pulse
        else
            voiceAmp = ampBase * (1 - (layer - 1) / number_of_layers * 0.3)
        endif
        
        # Store values
        selectObject: ampCtrl
        Set value at sample number: 1, cp, voiceAmp
        selectObject: phaseCtrl
        Set value at sample number: 1, cp, voicePhase
    endfor
    
    # --- Resample to audio rate ---
    selectObject: ampCtrl
    ampAudio = Resample: sample_rate_Hz, 50
    ampAudioName$ = "ampAudio_" + uid$
    Rename: ampAudioName$
    
    selectObject: phaseCtrl
    phaseAudio = Resample: sample_rate_Hz, 50
    phaseAudioName$ = "phaseAudio_" + uid$
    Rename: phaseAudioName$
    
    # --- Synthesize layer ---
    layerSound = Create Sound from formula: "layer_" + uid$, 1, 0, duration_s, sample_rate_Hz, "Sound_'ampAudioName$'[] * sin(Sound_'phaseAudioName$'[])"
    layerName$ = selected$("Sound")
    
    # Add to output
    selectObject: outputSound
    Formula: "self + Sound_'layerName$'[]"
    
    # Cleanup
    removeObject: ampCtrl, phaseCtrl, ampAudio, phaseAudio, layerSound
endfor

# === Apply Fade ===
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
    Rename: "brownian_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound
    
elsif spatial_mode = 3
    appendInfoLine: "Creating rotating stereo..."
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * (0.6 + 0.4 * cos(twoPi * 0.15 * x))"
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * (0.6 + 0.4 * sin(twoPi * 0.15 * x))"
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "brownian_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound
else
    selectObject: outputSound
    Rename: "brownian_" + preset_name$
endif

# === Normalize ===
if normalize_output
    selectObject: outputSound
    Scale peak: 0.9
endif

# === Visualization (Spectrogram Only) ===
if draw_visualization
    appendInfoLine: "Drawing spectrogram..."
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
    
    .leftMargin = 0.6
    .rightMargin = 6.5
    
    # === Title ===
    Select outer viewport: 0, 7, 0, 1.5
    Font size: 12
    Colour: "Black"
    Text top: "no", "Brownian Synthesis: " + preset_name$ + " (" + synthesis_mode$ + ")"
    
    # === Spectrogram ===
    Select outer viewport: 0, 7, 0.6, 4.5
    Colour: "{0.85, 0.85, 0.85}"
    Draw inner box
    
    Select inner viewport: .leftMargin, .rightMargin, 0.7, 4.4
    
    # Get mono version for spectrogram
    if spatial_mode > 1
        selectObject: outputSound
        Extract one channel: 1
        .monoForSpec = selected("Sound")
    else
        selectObject: outputSound
        Copy: "temp_for_spec"
        .monoForSpec = selected("Sound")
    endif
    
    # Calculate frequency range based on content
    selectObject: .monoForSpec
    .maxFreqSpec = min(6000, max(2000, base_frequency_Hz * number_of_layers * 2))
    
    To Spectrogram: 0.03, .maxFreqSpec, 0.005, 20, "Gaussian"
    .spec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    
    removeObject: .monoForSpec, .spec
    
    # Axis labels
    Select outer viewport: 0, .leftMargin, 0.6, 4.5
    Colour: "Black"
    Font size: 10
    Text: 0.5, "centre", 0.5, "half", "Hz"
    
    Select inner viewport: .leftMargin, .rightMargin, 0.7, 4.4
    Axes: 0, .duration, 0, .maxFreqSpec
    Colour: "White"
    Marks left: 5, "yes", "yes", "no"
    Marks bottom every: 1, 1, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"
    
    # === Footer ===
    Select outer viewport: 0, 7, 6.4, 7
    Font size: 8
    Colour: "{0.4, 0.4, 0.4}"
    .paramText$ = "Base: " + fixed$(base_frequency_Hz, 0) + " Hz | Step: " + fixed$(step_size, 1) + " | Drift: " + fixed$(drift_force, 2) + " | Layers: " + string$(number_of_layers) + " | Spatial: " + spatial_mode$
    Text top: "no", .paramText$
    
    # Reset
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc