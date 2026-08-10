# ============================================================
# Praat AudioTools - Phase_Modulation_Matrix.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Phase Modulation Matrix - creates chorus, phaser, and vibrato
#   effects through layered sinusoidal sample displacement. Each
#   layer modulates at a different frequency with feedback,
#   creating rich, swirling textures.
#
# Changelog v0.4:
#   - API COMPATIBILITY: the public form is byte-for-byte unchanged.
#   - CRITICAL FIX: Carrier_freq is now truly interpreted in Hz. v0.3 used
#     sin(2*pi*f*col/totalSamples), which produces f cycles across the entire
#     file (actual rate = f/duration), not f cycles per second.
#   - Smooth displacement: displaced reads now use continuous Sound-time
#     interpolation object(id,time,channel) instead of rounded sample indices,
#     removing sample-quantized staircase modulation.
#   - Duration-relative depth keeps its historical fraction-of-duration
#     meaning but is computed directly in seconds; fixed-ms depth is unchanged.
#   - Layer_gain_base/rate now scale the displaced layer contribution.
#     In v0.3 the gain multiplied the entire linear result, then final peak
#     normalization cancelled that scalar, making the controls effectively
#     inaudible. Public parameter names/defaults are unchanged.
#   - Layer gain is clamped at zero internally so high custom layer counts
#     cannot introduce unintended polarity inversion.
#   - Added guards for carrier ranges and layer count; silent output is
#     normalization-safe.
#   - Visualization frequency range is capped at Nyquist.
#
# Changelog v0.3:
#   - Feedback now feed-forward (FIR): displaced reads taken from a
#     per-layer snapshot of the layer input, not from samples already
#     modified in the same in-place pass. Inter-layer feedback retained.
#     This changes the sound of every preset.
#   - Added optional fixed-ms modulation depth (off by default). When off,
#     depth stays the original fraction-of-duration behaviour.
#   - Relabelled "Spectral tilt" -> "Layer gain": the operation is a
#     per-layer broadband scalar gain, not a frequency-dependent tilt.
#     (Form fields renamed too for coherence; no audio change.)
#   - Viz: spectrograms now computed on a mono fold (fixes stereo crash).
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
    boolean Use_fixed_ms_depth 0
    positive Fixed_depth_ms 20
    
    comment === Feedback ===
    positive Feedback_base 0.7
    
    comment === Layer Gain ===
    positive Layer_gain_base 1.1
    positive Layer_gain_rate 0.1
    
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
    layer_gain_base = 1.1
    layer_gain_rate = 0.1
elsif preset = 2
    # Subtle Chorus
    modulation_layers = 3
    carrier_freq_min = 0.05
    carrier_freq_max = 0.2
    fixed_carrier_freq = 0.15
    mod_depth_base = 10
    mod_depth_increment = 1
    feedback_base = 0.4
    layer_gain_base = 1.05
    layer_gain_rate = 0.05
elsif preset = 3
    # Deep Phase Sweep
    modulation_layers = 6
    carrier_freq_min = 0.1
    carrier_freq_max = 0.4
    fixed_carrier_freq = 0.28
    mod_depth_base = 6
    mod_depth_increment = 2
    feedback_base = 0.8
    layer_gain_base = 1.15
    layer_gain_rate = 0.12
elsif preset = 4
    # Vibrato / Whirl
    modulation_layers = 7
    carrier_freq_min = 0.2
    carrier_freq_max = 0.8
    fixed_carrier_freq = 0.45
    mod_depth_base = 5
    mod_depth_increment = 3
    feedback_base = 0.9
    layer_gain_base = 1.2
    layer_gain_rate = 0.15
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
channels = Get number of channels
nyquist = sampleRate / 2
vizMaxHz = min(5000, nyquist)

# === Guards (v0.4; public parameters unchanged) ===
if modulation_layers < 1
    exitScript: "Modulation layers must be at least 1"
endif
if modulation_layers > 128
    exitScript: "Modulation layers must not exceed 128"
endif
if carrier_freq_min <= 0 or carrier_freq_max <= 0
    exitScript: "Carrier frequencies must be > 0"
endif
if carrier_freq_min > carrier_freq_max
    exitScript: "Carrier_freq_min must be <= Carrier_freq_max"
endif
if fixed_carrier_freq <= 0
    exitScript: "Fixed carrier frequency must be > 0"
endif
if mod_depth_base <= 0 or mod_depth_increment <= 0
    exitScript: "Modulation depth base/increment must be > 0"
endif
if fixed_depth_ms <= 0
    exitScript: "Fixed depth must be > 0 ms"
endif
if feedback_base <= 0
    exitScript: "Feedback base must be > 0"
endif
if layer_gain_base <= 0 or layer_gain_rate <= 0
    exitScript: "Layer gain base/rate must be > 0"
endif
if scale_peak <= 0 or scale_peak > 1
    exitScript: "Scale peak must be > 0 and <= 1"
endif

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
if use_fixed_ms_depth
    appendInfoLine: "Depth: fixed ", fixed_depth_ms, " ms"
else
    appendInfoLine: "Depth: duration-relative (1/", mod_depth_base, "..)"
endif
appendInfoLine: ""

# === Copy for Processing ===
selectObject: original
Copy: original_name$ + "_phasemod"
result = selected("Sound")

# === Main Modulation Processing Loop ===
appendInfoLine: "Processing layers..."

for layer from 1 to modulation_layers
    selectObject: result

    # Dynamic modulation depth, expressed in seconds.
    if use_fixed_ms_depth
        modDepthSeconds = fixed_depth_ms / 1000
    else
        # Historical fraction-of-duration behaviour, explicit in seconds.
        modDepthSeconds = duration / (mod_depth_base + layer * mod_depth_increment)
    endif

    # Keep v0.3's layer-frequency structure (2x, 3x, 4x ... carrier), but
    # interpret every value in actual cycles per second.
    modulatorFreq = carrierFreq * (layer + 1)

    # Historical "Feedback" field is a feed-forward displaced-tap gain.
    layerFeedback = feedback_base / layer

    # Make Layer_gain audible: scale only the displaced contribution.
    layerGain = layer_gain_base - layer_gain_rate * layer
    if layerGain < 0
        layerGain = 0
    endif
    wetGain = layerFeedback * layerGain

    appendInfoLine: "  Layer ", layer, ": depth=", fixed$(modDepthSeconds * 1000, 2),
        ... " ms freq=", fixed$(modulatorFreq, 3), " Hz fb=", fixed$(layerFeedback, 2),
        ... " layerGain=", fixed$(layerGain, 3)

    # Snapshot this layer's input so displaced reads are feed-forward.
    selectObject: result
    Copy: "pm_snapshot"
    snapshot = selected("Sound")

    # True time-domain modulation:
    # delay(t) = depth * sin(2*pi*f*t)
    # object(snapshot,time,row) linearly interpolates between Sound samples.
    # Preserve the historical edge behaviour: if the displaced read leaves
    # the domain, retain only the current dry sample.
    selectObject: result
    Formula: ~ if x + modDepthSeconds * sin(2 * pi * modulatorFreq * (x - xmin)) >= xmin
        ... and x + modDepthSeconds * sin(2 * pi * modulatorFreq * (x - xmin)) <= xmax
        ... then self + object(snapshot,
        ... x + modDepthSeconds * sin(2 * pi * modulatorFreq * (x - xmin)), row) * wetGain
        ... else self fi

    removeObject: snapshot
endfor

# === Scale Peak ===
selectObject: result
resultPeak = Get absolute extremum: 0, 0, "Sinc70"
if resultPeak > 0
    Scale peak: scale_peak
endif

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
    nch = Get number of channels
    if nch > 1
        origMono = Convert to mono
    else
        origMono = Copy: "origMono"
    endif
    To Spectrogram: 0.03, vizMaxHz, 0.01, 20, "Gaussian"
    origSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: origSpec, origMono
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq"
    Text bottom: "yes", "Original (s)"
    
    # Result spectrogram
    Select outer viewport: 4, 8, 3.7, 5.3
    Select inner viewport: 4.4, 7.6, 3.9, 5.2
    selectObject: result
    nch = Get number of channels
    if nch > 1
        resMono = Convert to mono
    else
        resMono = Copy: "resMono"
    endif
    To Spectrogram: 0.03, vizMaxHz, 0.01, 20, "Gaussian"
    resSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: resSpec, resMono
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq"
    Text bottom: "yes", "Phase Mod (s)"
    
    # Legend
    Select outer viewport: 0, 8, 5.4, 5.7
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Layers: " + string$(modulation_layers) + " | Carrier: " + fixed$(carrierFreq, 3) + " Hz | Feedback: " + fixed$(feedback_base, 2) + " | Gain: " + fixed$(layer_gain_base, 2)
    
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