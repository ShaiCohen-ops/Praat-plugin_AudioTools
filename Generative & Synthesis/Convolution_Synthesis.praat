# ============================================================
# Praat AudioTools - Convolution Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Physical modeling via convolution: source x impulse response.
#   Creates percussion, bells, and resonant sounds.
#
# Usage:
#   Run this script (no input sound required).
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.2:
#   - Fixed filters, reverse envelope, ADSR if/fi, smooth transitions, viz
#
# Changelog v0.3:
#   - Fixed preset source label: presets set the numeric source_type but left
#     source_type$ at the form default, so the plot footer reported "Impulse"
#     for every preset regardless of the actual source. Each preset now sets
#     source_type$ to match.
#   - Rebuilt the visualization in the AudioTools house style (8-inch canvas,
#     title band, waveform + spectrogram, grey summary, larger fonts, black marks).
#   - Replaced non-ASCII characters (multiplication sign, en-dash).
# ============================================================

form Convolution Synthesis
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Metallic Bell
        option Deep Gong
        option Glass Harmonica
        option Snare Drum
        option Kick Drum
        option Water Drop
        option Bubble Pop
        option Wind Chime
        option Crystal Shatter
        option Sci-Fi Laser
        option Thunder
    
    comment === Basic Settings ===
    positive Duration_s 1.0
    integer Sample_rate_Hz 44100
    
    comment === Frequencies ===
    positive Frequency_1_Hz 800
    positive Frequency_2_Hz 1200
    positive Decay_rate 20
    positive Modulation_rate 2
    
    comment === Source Type ===
    optionmenu Source_type 1
        option Impulse
        option Short Burst
        option Noise Burst
        option Tone Burst
    
    comment === Envelope ===
    optionmenu Envelope_type 1
        option No Envelope
        option Percussive
        option Slow Decay
        option Reverse
        option Tremolo
        option Swell
        option ADSR
    
    comment === Output ===
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
    # Metallic Bell
    frequency_1_Hz = 800
    frequency_2_Hz = 1200
    decay_rate = 15
    modulation_rate = 3
    source_type = 3
    envelope_type = 1
    source_type$ = "Noise Burst"
    preset_name$ = "MetallicBell"
elsif preset = 3
    # Deep Gong
    duration_s = 3.0
    frequency_1_Hz = 120
    frequency_2_Hz = 200
    decay_rate = 5
    modulation_rate = 1
    source_type = 3
    envelope_type = 1
    source_type$ = "Noise Burst"
    preset_name$ = "DeepGong"
elsif preset = 4
    # Glass Harmonica
    frequency_1_Hz = 1200
    frequency_2_Hz = 1800
    decay_rate = 25
    modulation_rate = 5
    source_type = 3
    envelope_type = 1
    source_type$ = "Noise Burst"
    preset_name$ = "GlassHarmonica"
elsif preset = 5
    # Snare Drum
    duration_s = 0.5
    frequency_1_Hz = 180
    frequency_2_Hz = 4000
    decay_rate = 60
    modulation_rate = 8
    source_type = 3
    envelope_type = 2
    source_type$ = "Noise Burst"
    preset_name$ = "SnareDrum"
elsif preset = 6
    # Kick Drum
    duration_s = 0.5
    frequency_1_Hz = 60
    frequency_2_Hz = 120
    decay_rate = 40
    modulation_rate = 2
    source_type = 1
    envelope_type = 2
    source_type$ = "Impulse"
    preset_name$ = "KickDrum"
elsif preset = 7
    # Water Drop
    duration_s = 0.5
    frequency_1_Hz = 800
    frequency_2_Hz = 1600
    decay_rate = 50
    modulation_rate = 20
    source_type = 1
    envelope_type = 1
    source_type$ = "Impulse"
    preset_name$ = "WaterDrop"
elsif preset = 8
    # Bubble Pop
    duration_s = 0.3
    frequency_1_Hz = 500
    frequency_2_Hz = 1000
    decay_rate = 80
    modulation_rate = 30
    source_type = 1
    envelope_type = 2
    source_type$ = "Impulse"
    preset_name$ = "BubblePop"
elsif preset = 9
    # Wind Chime
    frequency_1_Hz = 1000
    frequency_2_Hz = 1500
    decay_rate = 18
    modulation_rate = 4
    source_type = 2
    envelope_type = 1
    spatial_mode = 3
    source_type$ = "Short Burst"
    preset_name$ = "WindChime"
elsif preset = 10
    # Crystal Shatter
    duration_s = 0.8
    frequency_1_Hz = 2000
    frequency_2_Hz = 4000
    decay_rate = 100
    modulation_rate = 25
    source_type = 3
    envelope_type = 2
    spatial_mode = 2
    source_type$ = "Noise Burst"
    preset_name$ = "CrystalShatter"
elsif preset = 11
    # Sci-Fi Laser
    duration_s = 0.5
    frequency_1_Hz = 400
    frequency_2_Hz = 2000
    decay_rate = 50
    modulation_rate = 40
    source_type = 4
    envelope_type = 4
    source_type$ = "Tone Burst"
    preset_name$ = "SciFiLaser"
elsif preset = 12
    # Thunder
    duration_s = 3.0
    frequency_1_Hz = 60
    frequency_2_Hz = 150
    decay_rate = 3
    modulation_rate = 0.5
    source_type = 3
    envelope_type = 3
    spatial_mode = 2
    source_type$ = "Noise Burst"
    preset_name$ = "Thunder"
endif

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi

# === Info ===
writeInfoLine: "=== Convolution Synthesis ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Duration: ", duration_s, " s"
appendInfoLine: "Frequencies: ", frequency_1_Hz, " / ", frequency_2_Hz, " Hz"
appendInfoLine: "Decay: ", decay_rate
appendInfoLine: ""

# === Create source sound ===
appendInfoLine: "Creating source..."

if source_type = 1
    # Impulse
    sourceSound = Create Sound from formula: "source_" + uid$, 1, 0, duration_s, sample_rate_Hz,
        ... "if x < 0.001 then 1 else 0 fi"
elsif source_type = 2
    # Short Burst
    sourceSound = Create Sound from formula: "source_" + uid$, 1, 0, duration_s, sample_rate_Hz,
        ... "if x < 0.01 then sin(twoPi * 1000 * x) * (1 - x / 0.01) else 0 fi"
elsif source_type = 3
    # Noise Burst
    sourceSound = Create Sound from formula: "source_" + uid$, 1, 0, duration_s, sample_rate_Hz,
        ... "if x < 0.02 then randomGauss(0, 0.5) * (1 - x / 0.02) else 0 fi"
elsif source_type = 4
    # Tone Burst
    sourceSound = Create Sound from formula: "source_" + uid$, 1, 0, duration_s, sample_rate_Hz,
        ... "if x < 0.05 then sin(twoPi * frequency_1_Hz * x) * (1 - x / 0.05) else 0 fi"
endif

# === Create impulse response (filter) ===
appendInfoLine: "Creating impulse response..."

irDuration = min(duration_s, 1.0)

irSound = Create Sound from formula: "ir_" + uid$, 1, 0, irDuration, sample_rate_Hz,
    ... "sin(twoPi * frequency_1_Hz * x) * exp(-decay_rate * x) + 0.7 * sin(twoPi * frequency_2_Hz * x) * exp(-decay_rate * 1.5 * x) + 0.4 * sin(twoPi * frequency_1_Hz * 1.5 * x) * exp(-decay_rate * 2 * x) * sin(twoPi * modulation_rate * x)"

# === Convolve ===
appendInfoLine: "Convolving..."

selectObject: sourceSound
plusObject: irSound
outputSound = Convolve: "sum", "zero"
Rename: "conv_" + uid$

# Trim to original duration
selectObject: outputSound
convDur = Get total duration
if convDur > duration_s
    Extract part: 0, duration_s, "rectangular", 1, "no"
    trimmedSound = selected("Sound")
    removeObject: outputSound
    outputSound = trimmedSound
    Rename: "conv_" + uid$
endif

# Cleanup source and IR
removeObject: sourceSound, irSound

# === Apply Envelope ===
appendInfoLine: "Applying envelope..."
selectObject: outputSound

if envelope_type = 2
    # Percussive
    Formula: "self * exp(-x * 8)"
elsif envelope_type = 3
    # Slow Decay
    Formula: "self * exp(-x * 1.5)"
elsif envelope_type = 4
    # Reverse (use Praat's Reverse command)
    Reverse
elsif envelope_type = 5
    # Tremolo
    tremRate = 8
    tremDepth = 0.4
    Formula: "self * (1 - tremDepth + tremDepth * (0.5 + 0.5 * sin(twoPi * tremRate * x)))"
elsif envelope_type = 6
    # Swell
    attackTime = duration_s * 0.3
    Formula: "self * min(1, x / attackTime)"
elsif envelope_type = 7
    # ADSR (split into separate passes)
    attack = 0.01
    decay = 0.1
    sustain = 0.6
    releaseStart = duration_s - 0.2
    
    Formula: "if x < attack then self * (x / attack) else self fi"
    Formula: "if x >= attack and x < attack + decay then self * (1 - (1 - sustain) * ((x - attack) / decay)) else self fi"
    Formula: "if x >= attack + decay and x < releaseStart then self * sustain else self fi"
    Formula: "if x >= releaseStart then self * sustain * (1 - (x - releaseStart) / (duration_s - releaseStart)) else self fi"
endif

# === Fade in/out ===
selectObject: outputSound
Formula: "if x < 0.005 then self * (x / 0.005) else self fi"
actualDur = Get total duration
Formula: "if x > actualDur - 0.005 then self * ((actualDur - x) / 0.005) else self fi"

# === Spatial Processing ===
if spatial_mode = 2
    appendInfoLine: "Creating stereo width..."
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Filter (pass Hann band): 0, 4000, 100
    leftFiltered = selected("Sound")
    removeObject: leftSound
    leftSound = leftFiltered
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Filter (pass Hann band): 200, 8000, 100
    rightFiltered = selected("Sound")
    removeObject: rightSound
    rightSound = rightFiltered
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "conv_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound

elsif spatial_mode = 3
    appendInfoLine: "Creating rotating stereo..."
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * (0.5 + 0.5 * cos(twoPi * 0.5 * x))"
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * (0.5 + 0.5 * sin(twoPi * 0.5 * x))"
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "conv_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound
else
    selectObject: outputSound
    Rename: "conv_" + preset_name$
endif

# === Normalize ===
if normalize_output
    selectObject: outputSound
    Scale peak: 0.9
endif

# === Visualization ===
if draw_visualization
    appendInfoLine: "Drawing visualization..."
    @drawSpectrogram
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
procedure drawSpectrogram

    Erase all

    # --- Title (own clear band) ---
    Select outer viewport: 0, 8, 0.1, 0.7
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Convolution Synthesis: " + preset_name$

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
    selectObject: .disp
    .dur = Get total duration

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
    .maxFreqSpec = min(8000, max(3000, frequency_2_Hz * 2))
    To Spectrogram: 0.01, .maxFreqSpec, 0.002, 20, "Gaussian"
    .spec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: .spec
    removeObject: .disp

    Select inner viewport: 0.75, 7.6, 2.75, 4.8
    Axes: 0, .dur, 0, .maxFreqSpec
    Colour: "Black"
    Draw inner box
    Font size: 9
    Marks left: 5, "yes", "yes", "no"
    Marks bottom every: 1, 0.2, "yes", "yes", "no"
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
    Text: 0.5, "centre", 0.5, "half", "F1: " + fixed$(frequency_1_Hz, 0) + " Hz | F2: " + fixed$(frequency_2_Hz, 0) + " Hz | Decay: " + fixed$(decay_rate, 1) + " | Source: " + source_type$ + " | " + .spatial$
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc