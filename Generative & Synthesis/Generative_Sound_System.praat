# ============================================================
# Praat AudioTools - Generative_Sound_System.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Multi-mode generative sound system combining several synthesis
#   techniques: Harmonic Drift, Granular Cloud, FM Chaos, 
#   Spectral Morph, Rhythmic Pulse, and Subtractive Noise.
#
# Usage:
#   Run this script (no input sound required).
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis Toolkit 
#   for Experimental Composition.
#
# Changelog v0.2:
#   - Fixed filters, envelope if/fi, granular cloud, added viz
#
# Changelog v0.3:
#   - Fixed Stereo Wide: the in-place self[col-50]*1.05 delay was a recursive
#     comb with gain > 1 that blew up (~1e107) and silenced the left channel
#     after normalization. Now a feedforward delay reading the unmodified
#     source by ID.
#   - Fixed Binaural: the in-place self[col-delay] (else 0) cascaded zeros and
#     silenced the right channel. Now feedforward from the unmodified source.
#   - Rebuilt the visualization in the AudioTools house style (8-inch canvas,
#     title band, output waveform + spectrogram, grey summary, larger fonts).
#   - Replaced non-ASCII dashes with ASCII.
# ============================================================

form Generative Sound System
    comment === Synthesis Mode ===
    optionmenu Synthesis_mode 1
        option Harmonic Drift
        option Granular Cloud
        option FM Chaos
        option Spectral Morph
        option Rhythmic Pulse
        option Subtractive Noise
    
    comment === Basic Settings ===
    positive Duration_s 10
    integer Sample_rate_Hz 44100
    positive Base_frequency_Hz 110
    
    comment === Layer Settings ===
    integer Number_of_layers 4
    real Evolution_rate 0.5
    
    comment === Envelope ===
    positive Fade_time_s 2.0
    
    comment === Output ===
    optionmenu Spatial_mode 1
        option Mono
        option Stereo Wide
        option Rotating
        option Binaural
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Validation ===
if number_of_layers > 16
    number_of_layers = 16
endif
if number_of_layers < 1
    number_of_layers = 1
endif

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi

# Mode names
if synthesis_mode = 1
    mode_name$ = "HarmonicDrift"
elsif synthesis_mode = 2
    mode_name$ = "GranularCloud"
elsif synthesis_mode = 3
    mode_name$ = "FMChaos"
elsif synthesis_mode = 4
    mode_name$ = "SpectralMorph"
elsif synthesis_mode = 5
    mode_name$ = "RhythmicPulse"
elsif synthesis_mode = 6
    mode_name$ = "SubtractiveNoise"
endif

# === Info ===
writeInfoLine: "=== Generative Sound System ==="
appendInfoLine: "Mode: ", mode_name$
appendInfoLine: "Duration: ", duration_s, " s"
appendInfoLine: "Layers: ", number_of_layers
appendInfoLine: "Base frequency: ", base_frequency_Hz, " Hz"
appendInfoLine: "Evolution rate: ", evolution_rate
appendInfoLine: ""

# === Create output buffer ===
outputSound = Create Sound from formula: "gen_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"

# === MODE 1: HARMONIC DRIFT ===
if synthesis_mode = 1
    appendInfoLine: "Synthesizing Harmonic Drift..."
    
    for layer to number_of_layers
        harmonic = layer
        freq = base_frequency_Hz * harmonic
        driftRate = evolution_rate * (0.3 + layer * 0.1)
        detune = 1 + sin(layer * 1.7) * 0.02
        amp = 1 / (layer + 1)
        
        layerSound = Create Sound from formula: "layer_" + uid$ + "_" + string$(layer), 1, 0, duration_s, sample_rate_Hz,
            ... "sin(twoPi * " + fixed$(freq * detune, 2) + " * x + sin(twoPi * " + fixed$(driftRate, 3) + " * x) * 2) * " + fixed$(amp, 4) + " * (0.6 + sin(twoPi * " + fixed$(driftRate * 0.5, 3) + " * x) * 0.4)"
        
        @applyFadeEnvelope: layerSound
        @addToOutput: layerSound, layer
        
        appendInfoLine: "  Layer ", layer, ": ", fixed$(freq, 1), " Hz"
    endfor

# === MODE 2: GRANULAR CLOUD ===
elsif synthesis_mode = 2
    appendInfoLine: "Synthesizing Granular Cloud..."
    
    for layer to number_of_layers
        grainFreq = base_frequency_Hz * (1 + layer * 0.3)
        grainRate = 20 + layer * 15
        amp = 0.4 / number_of_layers
        
        # Amplitude-modulated grains (not per-sample noise)
        layerSound = Create Sound from formula: "layer_" + uid$ + "_" + string$(layer), 1, 0, duration_s, sample_rate_Hz,
            ... "sin(twoPi * " + fixed$(grainFreq, 2) + " * x) * " + fixed$(amp, 4) + " * (0.5 + 0.5 * sin(twoPi * " + fixed$(grainRate, 1) + " * x)) * (0.5 + 0.5 * sin(twoPi * " + fixed$(evolution_rate, 3) + " * x))"
        
        @applyFadeEnvelope: layerSound
        @addToOutput: layerSound, layer
        
        appendInfoLine: "  Layer ", layer, ": ", fixed$(grainFreq, 1), " Hz @ ", fixed$(grainRate, 1), " grains/s"
    endfor

# === MODE 3: FM CHAOS ===
elsif synthesis_mode = 3
    appendInfoLine: "Synthesizing FM Chaos..."
    
    for layer to number_of_layers
        carrier = base_frequency_Hz * (1 + layer * 0.25)
        modFreq = carrier * (1.5 + layer * 0.3)
        modIndex = 3 + sin(layer * 2.3) * 2
        chaosRate = evolution_rate * (0.5 + layer * 0.2)
        amp = 0.5 / number_of_layers
        
        layerSound = Create Sound from formula: "layer_" + uid$ + "_" + string$(layer), 1, 0, duration_s, sample_rate_Hz,
            ... "sin(twoPi * " + fixed$(carrier, 2) + " * x + " + fixed$(modIndex, 2) + " * sin(twoPi * " + fixed$(modFreq, 2) + " * x * (1 + sin(twoPi * " + fixed$(chaosRate, 3) + " * x) * 0.5))) * " + fixed$(amp, 4)
        
        @applyFadeEnvelope: layerSound
        @addToOutput: layerSound, layer
        
        appendInfoLine: "  Layer ", layer, ": C=", fixed$(carrier, 1), " M=", fixed$(modFreq, 1), " I=", fixed$(modIndex, 2)
    endfor

# === MODE 4: SPECTRAL MORPH ===
elsif synthesis_mode = 4
    appendInfoLine: "Synthesizing Spectral Morph..."
    
    noiseBase = Create Sound from formula: "noise_" + uid$, 1, 0, duration_s, sample_rate_Hz, "randomGauss(0, 0.3)"
    
    for layer to number_of_layers
        selectObject: noiseBase
        Copy: "layer_" + uid$ + "_" + string$(layer)
        layerSound = selected("Sound")
        
        centerFreq = base_frequency_Hz * (1 + layer * 2)
        sweepRange = centerFreq * 0.5
        sweepRate = evolution_rate * (0.2 + layer * 0.1)
        
        # Modulate and filter
        Formula: "self * (1 + sin(twoPi * " + fixed$(sweepRate, 3) + " * x) * 0.3)"
        
        Filter (pass Hann band): centerFreq * 0.7, centerFreq * 1.5, 100
        filteredSound = selected("Sound")
        removeObject: layerSound
        layerSound = filteredSound
        
        @applyFadeEnvelope: layerSound
        @addToOutput: layerSound, layer
        
        appendInfoLine: "  Layer ", layer, ": center=", fixed$(centerFreq, 1), " Hz"
    endfor
    
    removeObject: noiseBase

# === MODE 5: RHYTHMIC PULSE ===
elsif synthesis_mode = 5
    appendInfoLine: "Synthesizing Rhythmic Pulse..."
    
    for layer to number_of_layers
        pulseFreq = base_frequency_Hz * (1 + layer * 0.5)
        rhythmRate = evolution_rate * (1 + layer * 0.5)
        amp = 0.4 / sqrt(layer)
        
        # Pulse wave with rhythmic modulation
        layerSound = Create Sound from formula: "layer_" + uid$ + "_" + string$(layer), 1, 0, duration_s, sample_rate_Hz,
            ... "sin(twoPi * " + fixed$(pulseFreq, 2) + " * x) * " + fixed$(amp, 4) + " * max(0, sin(twoPi * " + fixed$(rhythmRate, 3) + " * x))"
        
        @applyFadeEnvelope: layerSound
        @addToOutput: layerSound, layer
        
        appendInfoLine: "  Layer ", layer, ": ", fixed$(pulseFreq, 1), " Hz @ ", fixed$(rhythmRate, 2), " Hz rhythm"
    endfor

# === MODE 6: SUBTRACTIVE NOISE ===
elsif synthesis_mode = 6
    appendInfoLine: "Synthesizing Subtractive Noise..."
    
    noiseBase = Create Sound from formula: "noise_" + uid$, 1, 0, duration_s, sample_rate_Hz, "randomGauss(0, 0.5)"
    
    for layer to number_of_layers
        selectObject: noiseBase
        Copy: "layer_" + uid$ + "_" + string$(layer)
        layerSound = selected("Sound")
        
        filterFreq = base_frequency_Hz * (2 ^ layer)
        resonance = 50 + layer * 30
        sweepRate = evolution_rate * 0.3
        
        # Modulate and filter
        Formula: "self * (1 + sin(twoPi * " + fixed$(sweepRate, 3) + " * x) * 0.3)"
        
        Filter (pass Hann band): filterFreq * 0.8, filterFreq * 1.2, resonance
        filteredSound = selected("Sound")
        removeObject: layerSound
        layerSound = filteredSound
        
        @applyFadeEnvelope: layerSound
        @addToOutput: layerSound, layer
        
        appendInfoLine: "  Layer ", layer, ": filter=", fixed$(filterFreq, 1), " Hz, Q=", fixed$(resonance, 0)
    endfor
    
    removeObject: noiseBase
endif

# === Spatial Processing ===
if spatial_mode = 2
    # Stereo Wide
    appendInfoLine: ""
    appendInfoLine: "Creating stereo width..."
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * 0.95"
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    # Slight feedforward delay for width (reads the unmodified source by ID,
    # not in-place: in-place self[col-50] is a recursive comb and blows up)
    Formula: "if col > 50 then object[" + string$(outputSound) + ", 1, col - 50] * 1.05 else self fi"
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "gen_" + mode_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound

elsif spatial_mode = 3
    # Rotating
    appendInfoLine: ""
    appendInfoLine: "Creating rotating stereo..."
    
    rotationRate = 0.25
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * (0.5 + 0.5 * cos(twoPi * " + fixed$(rotationRate, 3) + " * x))"
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * (0.5 + 0.5 * sin(twoPi * " + fixed$(rotationRate, 3) + " * x))"
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "gen_" + mode_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound

elsif spatial_mode = 4
    # Binaural
    appendInfoLine: ""
    appendInfoLine: "Creating binaural processing..."
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Filter (pass Hann band): 0, base_frequency_Hz * 8, 100
    leftFiltered = selected("Sound")
    removeObject: leftSound
    leftSound = leftFiltered
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    # Delay + high-pass for right ear
    delaySamples = 100
    Formula: "if col > " + string$(delaySamples) + " then object[" + string$(outputSound) + ", 1, col - " + string$(delaySamples) + "] else 0 fi"
    Filter (pass Hann band): base_frequency_Hz * 2, sample_rate_Hz / 2, 100
    rightFiltered = selected("Sound")
    removeObject: rightSound
    rightSound = rightFiltered
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "gen_" + mode_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound
else
    selectObject: outputSound
    Rename: "gen_" + mode_name$
endif

# === Normalize ===
if normalize_output
    selectObject: outputSound
    Scale peak: 0.9
endif

# === Visualization ===
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."
    @drawVisualization
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
# Procedure: applyFadeEnvelope
# ==============================================================================
procedure applyFadeEnvelope: .soundID
    selectObject: .soundID
    
    if fade_time_s > 0
        .fadeSamples = fade_time_s * sample_rate_Hz
        .totalSamples = duration_s * sample_rate_Hz
        .releaseStart = .totalSamples - .fadeSamples
        
        # Fade in
        Formula: "if col < .fadeSamples then self * (col / .fadeSamples) else self fi"
        # Fade out
        Formula: "if col > .releaseStart then self * ((.totalSamples - col) / .fadeSamples) else self fi"
    endif
endproc

# ==============================================================================
# Procedure: addToOutput
# ==============================================================================
procedure addToOutput: .layerID, .layerNum
    # First, make sure layer has the correct name for Formula reference
    selectObject: .layerID
    Rename: "layer_" + uid$ + "_" + string$(.layerNum)
    
    # Now add to output
    selectObject: outputSound
    Formula: "self + Sound_layer_" + uid$ + "_" + string$(.layerNum) + "[] / number_of_layers"
    
    removeObject: .layerID
endproc

# ==============================================================================
# Procedure: drawVisualization
# ==============================================================================
procedure drawVisualization

    Erase all

    # --- Title (own clear band) ---
    Select outer viewport: 0, 8, 0.1, 0.7
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Generative Sound System: " + mode_name$

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

    # --- Panel 1: Output waveform ---
    Select outer viewport: 0, 8, 0.9, 2.5
    Select inner viewport: 0.75, 7.6, 1.05, 2.4
    selectObject: .disp
    Colour: "{0.20, 0.45, 0.65}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 10
    Text left: "yes", "Output"

    # --- Panel 2: Spectrogram ---
    Select outer viewport: 0, 8, 2.8, 5.1
    Select inner viewport: 0.75, 7.6, 2.95, 5.0
    selectObject: .disp
    .maxFreqSpec = min(8000, base_frequency_Hz * number_of_layers * 3)
    To Spectrogram: 0.03, .maxFreqSpec, 0.005, 20, "Gaussian"
    .spec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: .spec
    removeObject: .disp

    Select inner viewport: 0.75, 7.6, 2.95, 5.0
    Axes: 0, duration_s, 0, .maxFreqSpec
    Colour: "Black"
    Draw inner box
    Font size: 9
    Marks left: 5, "yes", "yes", "no"
    Marks bottom every: 1, 2, "yes", "yes", "no"
    Font size: 10
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Frequency (Hz)"

    # --- Summary panel (grey) ---
    Select outer viewport: 0, 8, 5.3, 5.7
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 8
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.5, "centre", 0.5, "half", string$(number_of_layers) + " layers | Base: " + fixed$(base_frequency_Hz, 0) + " Hz | Evolution: " + fixed$(evolution_rate, 2) + " | Fade: " + fixed$(fade_time_s, 1) + " s | " + spatial_mode$
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc