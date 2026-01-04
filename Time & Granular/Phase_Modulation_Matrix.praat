# ============================================================
# Praat AudioTools - Phase_Modulation_Matrix.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Phase Modulation Matrix - creates chorus, phaser, and vibrato
#   effects through layered sinusoidal sample displacement. Each
#   layer modulates at a different frequency with feedback,
#   creating rich, swirling textures.
#
# Changelog v0.2:
#   - Modern syntax
#   - Added bounds checking
#   - Fixed Formula interpolation
#   - Added visualization
# ============================================================

form Phase Modulation Matrix
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Default (balanced)
        option Subtle Chorus
        option Deep Phase Sweep
        option Vibrato / Whirl
        option Custom
    
    comment === Layers ===
    natural Modulation_layers 5
    
    comment === Carrier Frequency ===
    positive Carrier_freq_min 0.1
    positive Carrier_freq_max 0.5
    boolean Use_fixed_carrier 0
    positive Fixed_carrier_freq 0.3
    
    comment === Modulation Depth ===
    positive Mod_depth_base 8
    positive Mod_depth_increment 2
    
    comment === Feedback ===
    positive Feedback_base 0.7
    
    comment === Spectral Tilt ===
    positive Spectral_tilt_base 1.1
    positive Spectral_tilt_rate 0.1
    
    comment === Output ===
    positive Scale_peak 0.93
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 1
    # Default (balanced)
    modulation_layers = 5
    carrier_freq_min = 0.1
    carrier_freq_max = 0.5
    fixed_carrier_freq = 0.3
    mod_depth_base = 8
    mod_depth_increment = 2
    feedback_base = 0.7
    spectral_tilt_base = 1.1
    spectral_tilt_rate = 0.1
elsif preset = 2
    # Subtle Chorus
    modulation_layers = 3
    carrier_freq_min = 0.05
    carrier_freq_max = 0.2
    fixed_carrier_freq = 0.15
    mod_depth_base = 10
    mod_depth_increment = 1
    feedback_base = 0.4
    spectral_tilt_base = 1.05
    spectral_tilt_rate = 0.05
elsif preset = 3
    # Deep Phase Sweep
    modulation_layers = 6
    carrier_freq_min = 0.1
    carrier_freq_max = 0.4
    fixed_carrier_freq = 0.28
    mod_depth_base = 6
    mod_depth_increment = 2
    feedback_base = 0.8
    spectral_tilt_base = 1.15
    spectral_tilt_rate = 0.12
elsif preset = 4
    # Vibrato / Whirl
    modulation_layers = 7
    carrier_freq_min = 0.2
    carrier_freq_max = 0.8
    fixed_carrier_freq = 0.45
    mod_depth_base = 5
    mod_depth_increment = 3
    feedback_base = 0.9
    spectral_tilt_base = 1.2
    spectral_tilt_rate = 0.15
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

original = selected("Sound")
original_name$ = selected$("Sound")

selectObject: original
sampleRate = Get sampling frequency
duration = Get total duration
totalSamples = Get number of samples

# === Get Preset Name ===
if preset = 1
    presetName$ = "Default"
elsif preset = 2
    presetName$ = "Subtle Chorus"
elsif preset = 3
    presetName$ = "Deep Phase Sweep"
elsif preset = 4
    presetName$ = "Vibrato/Whirl"
else
    presetName$ = "Custom"
endif

# === Determine Carrier Frequency ===
if use_fixed_carrier
    carrierFreq = fixed_carrier_freq
else
    carrierFreq = randomUniform(carrier_freq_min, carrier_freq_max)
endif

# === Info ===
writeInfoLine: "=== Phase Modulation Matrix ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Layers: ", modulation_layers
appendInfoLine: "Carrier freq: ", fixed$(carrierFreq, 3), " Hz"
appendInfoLine: "Feedback: ", feedback_base
appendInfoLine: ""

# === Copy for Processing ===
selectObject: original
Copy: original_name$ + "_phasemod"
result = selected("Sound")

# === Main Modulation Processing Loop ===
appendInfoLine: "Processing layers..."

for layer from 1 to modulation_layers
    selectObject: result
    
    # Dynamic modulation depth
    modDepth = totalSamples / (mod_depth_base + layer * mod_depth_increment)
    modulatorFreq = carrierFreq * (layer + 1)
    
    # Feedback decreases with layer
    layerFeedback = feedback_base / layer
    
    # Spectral tilt compensation
    tiltFactor = spectral_tilt_base - spectral_tilt_rate * layer
    
    appendInfoLine: "  Layer ", layer, ": depth=", floor(modDepth), " freq=", fixed$(modulatorFreq, 3), " fb=", fixed$(layerFeedback, 2)
    
    # Phase modulation with feedback (with bounds checking)
    Formula: ~ if (col + round(modDepth * sin(2 * pi * modulatorFreq * col / totalSamples))) >= 1 
        ... and (col + round(modDepth * sin(2 * pi * modulatorFreq * col / totalSamples))) <= ncol 
        ... then self + self[col + round(modDepth * sin(2 * pi * modulatorFreq * col / totalSamples))] * layerFeedback 
        ... else self fi
    
    # Spectral tilt compensation
    Formula: ~ self * tiltFactor
endfor

# === Scale Peak ===
selectObject: result
Scale peak: scale_peak

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Phase Modulation: " + original_name$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 2.0
    Select inner viewport: 0.6, 7.6, 0.7, 1.9
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 2.1, 3.5
    Select inner viewport: 0.6, 7.6, 2.2, 3.4
    selectObject: result
    Colour: "{0.5, 0.3, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Phase Mod"
    Text bottom: "yes", "Time (s)"
    
    # Original spectrogram
    Select outer viewport: 0, 4, 3.7, 5.3
    Select inner viewport: 0.6, 3.8, 3.9, 5.2
    selectObject: original
    To Spectrogram: 0.03, 5000, 0.01, 20, "Gaussian"
    origSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: origSpec
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq"
    Text bottom: "yes", "Original (s)"
    
    # Result spectrogram
    Select outer viewport: 4, 8, 3.7, 5.3
    Select inner viewport: 4.4, 7.6, 3.9, 5.2
    selectObject: result
    To Spectrogram: 0.03, 5000, 0.01, 20, "Gaussian"
    resSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: resSpec
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq"
    Text bottom: "yes", "Phase Mod (s)"
    
    # Legend
    Select outer viewport: 0, 8, 5.4, 5.7
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Layers: " + string$(modulation_layers) + " | Carrier: " + fixed$(carrierFreq, 3) + " Hz | Feedback: " + fixed$(feedback_base, 2) + " | Tilt: " + fixed$(spectral_tilt_base, 2)
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
selectObject: result
finalDuration = Get total duration

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(finalDuration, 2), " s"

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result