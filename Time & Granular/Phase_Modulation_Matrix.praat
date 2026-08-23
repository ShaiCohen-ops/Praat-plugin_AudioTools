# ============================================================
# Praat AudioTools - Phase_Modulation_Matrix.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Phase Modulation Matrix - creates chorus, phaser, and vibrato
#   effects through layered sinusoidal sample displacement. Each
#   layer modulates at a different frequency with feedback,
#   creating rich, swirling textures.
#
# Changelog v0.5:
#   - VIS: replaced the text-only footer emphasis with a central phase-displacement
#     field that directly shows each modulation layer as a sinusoidally shifted
#     read path around its unshifted reference line. Curve rate follows the real
#     per-layer modulator frequency; curve excursion follows the real modulation
#     depth relative to the deepest layer.
#   - VIS: Input and Output waveforms now share one amplitude scale.
#   - VIS: title/subtitle, panel greys, typography and summary strip aligned to
#     the Praat AudioTools library visual standard.
#   - VIS: final full-page viewport is re-selected so Picture export saves the
#     complete figure rather than the final strip only.
#   - No DSP changes.
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
writeInfoLine: "=== Phase Modulation Matrix v0.5 ==="
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
    Select outer viewport: 0, 8, 0, 7.05

    # Display-safe source name.
    vizName$ = replace$(original_name$, "_", "\_ ", 0)

    # Zero-based visualization copies so time axes stay musical even when
    # the source Sound has a non-zero xmin.
    selectObject: original
    vizInput = Copy: "pm_viz_input"
    Shift times to: "start time", 0
    selectObject: result
    vizOutput = Copy: "pm_viz_output"
    Shift times to: "start time", 0

    # Shared waveform scale.
    selectObject: vizInput
    inPeak = Get absolute extremum: 0, 0, "None"
    selectObject: vizOutput
    outPeak = Get absolute extremum: 0, 0, "None"
    sharedPeak = max(inPeak, outPeak)
    if sharedPeak < 0.01
        sharedPeak = 0.01
    endif
    sharedAmp = sharedPeak * 1.10

    # Title block.
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Phase Modulation Matrix v0.5##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half",
        ... vizName$ + " | " + presetName$
        ... + " | " + string$(modulation_layers) + " layers"
        ... + " | carrier " + fixed$(carrierFreq, 3) + " Hz"

    # Input waveform.
    Select outer viewport: 0, 8, 0.62, 1.42
    Select inner viewport: 0.60, 7.70, 0.68, 1.37
    Axes: 0, duration, -sharedAmp, sharedAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, -sharedAmp, sharedAmp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, duration, 0
    selectObject: vizInput
    Colour: "{0.55, 0.55, 0.55}"
    Line width: 1
    Draw: 0, 0, -sharedAmp, sharedAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"

    # Output waveform.
    Select outer viewport: 0, 8, 1.50, 2.30
    Select inner viewport: 0.60, 7.70, 1.56, 2.25
    Axes: 0, duration, -sharedAmp, sharedAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, -sharedAmp, sharedAmp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, duration, 0
    selectObject: vizOutput
    Colour: "{0.25, 0.45, 0.75}"
    Line width: 1
    Draw: 0, 0, -sharedAmp, sharedAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"

    # ----------------------------------------------------------
    # PHASE-DISPLACEMENT FIELD
    # Each lane is one real processing layer. The grey line is the
    # unshifted read position; the amber curve is the displaced read path.
    # Frequency and relative depth come directly from the DSP parameters.
    # ----------------------------------------------------------
    maxShownLayers = 8
    shownLayers = min(modulation_layers, maxShownLayers)

    # Find the largest displayed depth so lane excursions preserve the
    # actual relative depth relationship between layers.
    maxVizDepth = 0
    for vi to shownLayers
        if modulation_layers <= maxShownLayers
            actualLayer = vi
        else
            actualLayer = round(1 + (vi - 1) * (modulation_layers - 1) / (shownLayers - 1))
        endif
        if use_fixed_ms_depth
            vizDepth = fixed_depth_ms / 1000
        else
            vizDepth = duration / (mod_depth_base + actualLayer * mod_depth_increment)
        endif
        if vizDepth > maxVizDepth
            maxVizDepth = vizDepth
        endif
    endfor
    if maxVizDepth <= 0
        maxVizDepth = 1
    endif

    Select outer viewport: 0, 8, 2.43, 4.22
    Select inner viewport: 0.60, 7.70, 2.58, 4.12
    Axes: 0, duration, 0.35, shownLayers + 0.65
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, 0.35, shownLayers + 0.65

    # Draw from top layer downward so layer 1 is visually first.
    for vi to shownLayers
        if modulation_layers <= maxShownLayers
            actualLayer = vi
        else
            actualLayer = round(1 + (vi - 1) * (modulation_layers - 1) / (shownLayers - 1))
        endif

        laneY = shownLayers - vi + 1
        if use_fixed_ms_depth
            vizDepth = fixed_depth_ms / 1000
        else
            vizDepth = duration / (mod_depth_base + actualLayer * mod_depth_increment)
        endif
        vizFreq = carrierFreq * (actualLayer + 1)
        vizAmp = 0.27 * vizDepth / maxVizDepth

        Colour: "{0.82, 0.82, 0.82}"
        Line width: 1
        Draw line: 0, laneY, duration, laneY

        Colour: "{0.80, 0.60, 0.20}"
        Line width: 1.5
        nViz = 180
        prevT = 0
        prevY = laneY + vizAmp * sin(0)
        for k from 1 to nViz
            tViz = duration * k / nViz
            yViz = laneY + vizAmp * sin(2 * pi * vizFreq * tViz)
            Draw line: prevT, prevY, tViz, yViz
            prevT = tViz
            prevY = yViz
        endfor

        Font size: 6
        Colour: "{0.35, 0.35, 0.50}"
        Text: duration * 0.01, "left", laneY + 0.22, "half", "L" + string$(actualLayer)
    endfor

    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Phase-displacement field"
    Text bottom: "yes", "Time (s)"

    # Input spectrogram.
    Select outer viewport: 0, 4, 4.40, 6.18
    Select inner viewport: 0.60, 3.85, 4.58, 6.07
    selectObject: vizInput
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
    Text top: "no", "Input spectrum"

    # Output spectrogram.
    Select outer viewport: 4, 8, 4.40, 6.18
    Select inner viewport: 4.45, 7.70, 4.58, 6.07
    selectObject: vizOutput
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
    Text top: "no", "Output spectrum"

    # Compact summary strip.
    Select outer viewport: 0, 8, 6.32, 6.92
    Select inner viewport: 0.60, 7.70, 6.38, 6.86
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    if use_fixed_ms_depth
        depthSummary$ = fixed$(fixed_depth_ms, 1) + " ms fixed"
    else
        depthSummary$ = "duration-relative"
    endif
    Text: 0.02, "left", 0.67, "half",
        ... "##" + presetName$ + "##  |  layers " + string$(modulation_layers)
        ... + "  |  carrier " + fixed$(carrierFreq, 3) + " Hz"
        ... + "  |  depth " + depthSummary$
    Text: 0.02, "left", 0.25, "half",
        ... "feedback " + fixed$(feedback_base, 2)
        ... + "  |  layer gain " + fixed$(layer_gain_base, 2)
        ... + " - " + fixed$(layer_gain_rate, 2) + " / layer"
        ... + "  |  peak " + fixed$(scale_peak, 2)
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1

    removeObject: vizInput, vizOutput

    # Ensure full-page export, not the last selected strip.
    Select outer viewport: 0, 8, 0, 7.05
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