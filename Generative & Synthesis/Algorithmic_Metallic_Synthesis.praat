# ============================================================
# Praat AudioTools - Algorithmic Metallic Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Metallic/bell synthesis using FM with rhythmic gating
#   and resonant filtering. Creates bell, gong, and
#   percussion-like metallic textures.
#
# Usage:
#   Run this script (no input sound required).
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.2:
#   - Fixed filters, per-sample randomization, smooth triggers, presets, viz
#
# Changelog v0.3:
#   - Fixed preset mode labels: presets set the numeric synthesis_mode but left
#     synthesis_mode$ at the form default, so every preset reported "Standard
#     Metallic" in the info window and plot title regardless of the actual mode.
#     Each preset now sets synthesis_mode$ to match.
#   - Rebuilt the visualization in the AudioTools house style (8-inch canvas,
#     title band, waveform + spectrogram, grey summary, larger fonts, black marks).
#   - Replaced non-ASCII characters (en-dash, multiplication sign).
# ============================================================

form Algorithmic Metallic Synthesis
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Temple Bell
        option Gamelan
        option Industrial Clang
        option Wind Chimes
        option Gong Wash
        option Prepared Piano
        option Steel Drum
    
    comment === Basic Settings ===
    positive Duration_s 3
    integer Sample_rate_Hz 44100
    positive Base_frequency_Hz 200
    integer Number_of_voices 5
    integer Number_of_layers 3
    
    comment === Modulation ===
    positive Modulation_rate_Hz 0.5
    real Modulation_depth 3.0
    positive Resonance_decay_s 0.1
    
    comment === Synthesis Mode ===
    optionmenu Synthesis_mode 1
        option Standard Metallic
        option Dense Shimmer
        option Sparse Bells
        option Rhythmic Clang
        option Chaotic Resonance
    
    comment === Output ===
    positive Fade_time_s 0.5
    optionmenu Spatial_mode 1
        option Mono
        option Stereo Wide
        option Rotating
    boolean Randomize_parameters 1
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
preset_name$ = "Custom"

if preset = 2
    # Temple Bell
    duration_s = 5
    base_frequency_Hz = 180
    number_of_voices = 6
    number_of_layers = 2
    modulation_rate_Hz = 0.3
    modulation_depth = 4.0
    resonance_decay_s = 0.8
    synthesis_mode = 3
    spatial_mode = 3
    fade_time_s = 1
    synthesis_mode$ = "Sparse Bells"
    preset_name$ = "TempleBell"
elsif preset = 3
    # Gamelan
    duration_s = 4
    base_frequency_Hz = 250
    number_of_voices = 8
    number_of_layers = 3
    modulation_rate_Hz = 0.8
    modulation_depth = 2.5
    resonance_decay_s = 0.3
    synthesis_mode = 2
    spatial_mode = 2
    synthesis_mode$ = "Dense Shimmer"
    preset_name$ = "Gamelan"
elsif preset = 4
    # Industrial Clang
    duration_s = 3
    base_frequency_Hz = 120
    number_of_voices = 6
    number_of_layers = 4
    modulation_rate_Hz = 2.0
    modulation_depth = 5.0
    resonance_decay_s = 0.05
    synthesis_mode = 4
    spatial_mode = 2
    synthesis_mode$ = "Rhythmic Clang"
    preset_name$ = "Industrial"
elsif preset = 5
    # Wind Chimes
    duration_s = 6
    base_frequency_Hz = 800
    number_of_voices = 10
    number_of_layers = 2
    modulation_rate_Hz = 0.2
    modulation_depth = 1.5
    resonance_decay_s = 0.4
    synthesis_mode = 3
    spatial_mode = 3
    randomize_parameters = 1
    synthesis_mode$ = "Sparse Bells"
    preset_name$ = "WindChimes"
elsif preset = 6
    # Gong Wash
    duration_s = 8
    base_frequency_Hz = 80
    number_of_voices = 4
    number_of_layers = 3
    modulation_rate_Hz = 0.1
    modulation_depth = 6.0
    resonance_decay_s = 1.5
    synthesis_mode = 1
    spatial_mode = 3
    fade_time_s = 2
    synthesis_mode$ = "Standard Metallic"
    preset_name$ = "GongWash"
elsif preset = 7
    # Prepared Piano
    duration_s = 4
    base_frequency_Hz = 150
    number_of_voices = 6
    number_of_layers = 3
    modulation_rate_Hz = 1.5
    modulation_depth = 3.5
    resonance_decay_s = 0.15
    synthesis_mode = 5
    spatial_mode = 2
    synthesis_mode$ = "Chaotic Resonance"
    preset_name$ = "PreparedPiano"
elsif preset = 8
    # Steel Drum
    duration_s = 3
    base_frequency_Hz = 300
    number_of_voices = 5
    number_of_layers = 2
    modulation_rate_Hz = 1.0
    modulation_depth = 2.0
    resonance_decay_s = 0.2
    synthesis_mode = 4
    spatial_mode = 1
    synthesis_mode$ = "Rhythmic Clang"
    preset_name$ = "SteelDrum"
endif

# === Validation ===
if number_of_voices > 12
    number_of_voices = 12
endif
if number_of_layers > 8
    number_of_layers = 8
endif
if fade_time_s > duration_s / 2
    fade_time_s = duration_s / 2
endif

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi

# === Info ===
writeInfoLine: "=== Algorithmic Metallic Synthesis ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Duration: ", duration_s, " s"
appendInfoLine: "Voices: ", number_of_voices, " x ", number_of_layers, " layers"
appendInfoLine: "Mode: ", synthesis_mode$
appendInfoLine: ""

# === Create output sound ===
outputSound = Create Sound from formula: "metallic_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"

totalVoices = 0

# === Process layers ===
for layer to number_of_layers
    appendInfoLine: "Layer ", layer, "/", number_of_layers, "..."
    
    # Layer-specific parameters
    if randomize_parameters
        layerModRate = modulation_rate_Hz * (0.7 + 0.6 * randomUniform(0, 1))
        layerDecay = resonance_decay_s * (0.8 + 0.4 * randomUniform(0, 1))
    else
        layerModRate = modulation_rate_Hz
        layerDecay = resonance_decay_s
    endif
    
    # Determine voice count based on mode
    if synthesis_mode = 2
        layerVoices = number_of_voices * 2
    elsif synthesis_mode = 3
        layerVoices = max(2, floor(number_of_voices / 2))
    else
        layerVoices = number_of_voices
    endif
    
    for voice to layerVoices
        totalVoices = totalVoices + 1
        
        # === Compute voice parameters (pre-randomized) ===
        if synthesis_mode = 1
            # Standard Metallic - inharmonic partials
            voiceFreq = (voice + 2) * base_frequency_Hz * (1 + (layer - 1) * 0.1)
            detune = 1 + (voice - 1) * 0.02
            voiceAmp = 0.4 / (number_of_layers * sqrt(layerVoices))
            modIndex = modulation_depth
            triggerRate = voice + 2
            triggerDuty = 0.2
            filterQ = 200
            
        elsif synthesis_mode = 2
            # Dense Shimmer - many close partials
            voiceFreq = (voice + 1) * base_frequency_Hz * (1.5 + (layer - 1) * 0.2)
            detune = 1 + (voice - 1) * 0.015
            voiceAmp = 0.3 / (number_of_layers * sqrt(layerVoices))
            modIndex = modulation_depth * 0.7
            triggerRate = voice + 3
            triggerDuty = 0.15
            filterQ = 300
            
        elsif synthesis_mode = 3
            # Sparse Bells - wide spacing, long decay
            voiceFreq = (voice + 3) * base_frequency_Hz * (0.8 + (layer - 1) * 0.3)
            detune = 1 + (voice - 1) * 0.01
            voiceAmp = 0.6 / (number_of_layers * sqrt(layerVoices))
            modIndex = modulation_depth * 1.3
            triggerRate = voice + 1
            triggerDuty = 0.3
            filterQ = 150
            
        elsif synthesis_mode = 4
            # Rhythmic Clang - fast triggers
            voiceFreq = voice * base_frequency_Hz * (1 + (layer - 1) * 0.15)
            detune = 1 + (voice - 1) * 0.025
            voiceAmp = 0.5 / (number_of_layers * sqrt(layerVoices))
            modIndex = modulation_depth * 0.8
            triggerRate = voice * 2
            triggerDuty = 0.1
            filterQ = 250
            
        elsif synthesis_mode = 5
            # Chaotic Resonance - randomized everything
            voiceFreq = (voice + randomUniform(0, 3)) * base_frequency_Hz * (0.7 + randomUniform(0, 0.8))
            detune = 1 + randomUniform(0, 0.05)
            voiceAmp = 0.5 / (number_of_layers * sqrt(layerVoices))
            modIndex = modulation_depth * (0.5 + randomUniform(0, 1))
            triggerRate = randomUniform(2, 8)
            triggerDuty = randomUniform(0.1, 0.3)
            filterQ = randomUniform(100, 400)
        endif
        
        # Randomize slightly if enabled
        if randomize_parameters and synthesis_mode <> 5
            voiceFreq = voiceFreq * (0.98 + 0.04 * randomUniform(0, 1))
            modIndex = modIndex * (0.9 + 0.2 * randomUniform(0, 1))
        endif
        
        # === Create FM carrier ===
        carrierSound = Create Sound from formula: "carrier_" + uid$, 1, 0, duration_s, sample_rate_Hz,
            ... "voiceAmp * sin(twoPi * voiceFreq * detune * x + modIndex * sin(twoPi * layerModRate * x))"
        
        # === Create smooth trigger envelope ===
        # Instead of hard 0/1, use raised cosine for smooth gating
        triggerSound = Create Sound from formula: "trigger_" + uid$, 1, 0, duration_s, sample_rate_Hz,
            ... "(1 + cos(twoPi * triggerRate * x)) / 2 * ((x * triggerRate) mod 1 < triggerDuty)"
        
        # Apply trigger to carrier
        selectObject: carrierSound
        triggerName$ = "trigger_" + uid$
        Formula: "self * Sound_'triggerName$'[]"
        
        # Apply resonant filter (bandpass around voice frequency)
        filterLow = voiceFreq * 0.9
        filterHigh = voiceFreq * 1.1
        if filterLow < 20
            filterLow = 20
        endif
        if filterHigh > sample_rate_Hz / 2 - 100
            filterHigh = sample_rate_Hz / 2 - 100
        endif
        
        selectObject: carrierSound
        Filter (pass Hann band): filterLow, filterHigh, filterQ
        filteredSound = selected("Sound")
        
        # Apply decay envelope
        selectObject: filteredSound
        Formula: "self * (0.3 + 0.7 * exp(-x / layerDecay))"
        
        # Add to output
        filteredName$ = selected$("Sound")
        selectObject: outputSound
        Formula: "self + Sound_'filteredName$'[]"
        
        # Cleanup
        removeObject: carrierSound, triggerSound, filteredSound
    endfor
endfor

appendInfoLine: ""
appendInfoLine: "Total voices: ", totalVoices

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
    Filter (pass Hann band): 0, 3000, 100
    leftFiltered = selected("Sound")
    removeObject: leftSound
    leftSound = leftFiltered
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Filter (pass Hann band): 150, 8000, 100
    rightFiltered = selected("Sound")
    removeObject: rightSound
    rightSound = rightFiltered
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "metallic_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound
    
elsif spatial_mode = 3
    appendInfoLine: "Creating rotating stereo..."
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * (0.6 + 0.4 * cos(twoPi * 0.3 * x))"
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * (0.6 + 0.4 * sin(twoPi * 0.3 * x))"
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "metallic_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound
else
    selectObject: outputSound
    Rename: "metallic_" + preset_name$
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
    Text: 0.5, "centre", 0.5, "half", "Metallic Synthesis: " + preset_name$ + " (" + synthesis_mode$ + ")"

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
    .maxFreqSpec = min(8000, max(3000, base_frequency_Hz * number_of_voices * 2))
    To Spectrogram: 0.02, .maxFreqSpec, 0.005, 20, "Gaussian"
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
    Marks bottom every: 1, 0.5, "yes", "yes", "no"
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
    Text: 0.5, "centre", 0.5, "half", "Base: " + fixed$(base_frequency_Hz, 0) + " Hz | Mod: " + fixed$(modulation_rate_Hz, 1) + " Hz | Decay: " + fixed$(resonance_decay_s, 2) + " s | Voices: " + string$(totalVoices) + " | " + .spatial$
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc