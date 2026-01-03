# ============================================================
# Praat AudioTools - FM_Texture_Generator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Corrected
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   FM (Frequency Modulation) Synthesis texture generator.
#   Classic Chowning/DX7-style FM sounds with various timbres.
#
#   FM equation: sin(2π × fc × t + I × sin(2π × fm × t))
#   where fc = carrier, fm = modulator, I = modulation index
#
# Usage:
#   Run this script (no input sound required).
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit 
#   for Experimental Composition.
#
# Changelog v0.2:
#   - Fixed ADSR nested if/fi
#   - Fixed per-sample randomization
#   - Smooth gate/stutter transitions
#   - Added visualization
#   - Added spatial modes
# ============================================================

form FM Texture Generator
    comment === Texture Type ===
    optionmenu Texture_type 1
        option Classic FM Bell
        option Brass Stack
        option Electric Piano
        option Organ Cluster
        option Glass Harmonica
        option Metallic Sweep
        option Wobble Bass
        option Alien Choir
        option Harmonic Bells
        option Inharmonic Stack
        option Feedback Scream
        option Sidebanded Drone
    
    comment === Basic Settings ===
    positive Duration_s 3.0
    integer Sample_rate_Hz 44100
    positive Carrier_freq_Hz 440
    
    comment === FM Parameters ===
    positive Modulator_ratio 2.0
    positive Modulation_index 5.0
    real Chaos_amount 0.3
    
    comment === Envelope ===
    optionmenu Envelope_type 1
        option No Envelope
        option Percussive
        option Slow Fade
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

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi
modFreq = carrier_freq_Hz * modulator_ratio

# === Apply texture-specific defaults ===
if texture_type = 1
    preset_name$ = "FMBell"
elsif texture_type = 2
    preset_name$ = "Brass"
elsif texture_type = 3
    preset_name$ = "EPiano"
elsif texture_type = 4
    preset_name$ = "Organ"
elsif texture_type = 5
    preset_name$ = "GlassHarmonica"
elsif texture_type = 6
    preset_name$ = "MetallicSweep"
elsif texture_type = 7
    preset_name$ = "WobbleBass"
elsif texture_type = 8
    preset_name$ = "AlienChoir"
elsif texture_type = 9
    preset_name$ = "HarmonicBells"
elsif texture_type = 10
    preset_name$ = "InharmonicStack"
elsif texture_type = 11
    preset_name$ = "FeedbackScream"
elsif texture_type = 12
    preset_name$ = "SidebandedDrone"
endif

# === Info ===
writeInfoLine: "=== FM Texture Generator ==="
appendInfoLine: "Texture: ", preset_name$
appendInfoLine: "Carrier: ", carrier_freq_Hz, " Hz"
appendInfoLine: "Modulator: ", modFreq, " Hz (ratio ", modulator_ratio, ")"
appendInfoLine: "Index: ", modulation_index
appendInfoLine: ""

# === Generate FM texture ===
appendInfoLine: "Synthesizing..."

if texture_type = 1
    # Classic FM Bell - decaying index
    outputSound = Create Sound from formula: "fm_" + uid$, 1, 0, duration_s, sample_rate_Hz,
        ... "0.5 * sin(twoPi * carrier_freq_Hz * x + modulation_index * exp(-x * 3) * sin(twoPi * modFreq * x)) * exp(-x * 2)"

elsif texture_type = 2
    # Brass Stack - rising index (attack brightness)
    outputSound = Create Sound from formula: "fm_" + uid$, 1, 0, duration_s, sample_rate_Hz,
        ... "0.4 * sin(twoPi * carrier_freq_Hz * x + modulation_index * (1 - exp(-x * 8)) * sin(twoPi * modFreq * x)) * (1 - exp(-x * 10)) * exp(-x * 0.3)"

elsif texture_type = 3
    # Electric Piano - fast decay of index
    outputSound = Create Sound from formula: "fm_" + uid$, 1, 0, duration_s, sample_rate_Hz,
        ... "0.4 * sin(twoPi * carrier_freq_Hz * x + modulation_index * exp(-x * 5) * sin(twoPi * modFreq * x)) * exp(-x * 1.5)"

elsif texture_type = 4
    # Organ Cluster - additive + FM
    outputSound = Create Sound from formula: "fm_" + uid$, 1, 0, duration_s, sample_rate_Hz,
        ... "0.25 * (sin(twoPi * carrier_freq_Hz * x + modulation_index * 0.5 * sin(twoPi * modFreq * x)) + 0.6 * sin(twoPi * carrier_freq_Hz * 2 * x) + 0.4 * sin(twoPi * carrier_freq_Hz * 3 * x) + 0.2 * sin(twoPi * carrier_freq_Hz * 4 * x))"

elsif texture_type = 5
    # Glass Harmonica - cascaded FM (FM of FM)
    outputSound = Create Sound from formula: "fm_" + uid$, 1, 0, duration_s, sample_rate_Hz,
        ... "0.4 * sin(twoPi * carrier_freq_Hz * x + modulation_index * sin(twoPi * modFreq * x + modulation_index * 0.5 * sin(twoPi * modFreq * 2 * x))) * exp(-x * 0.8)"

elsif texture_type = 6
    # Metallic Sweep - time-varying ratio
    outputSound = Create Sound from formula: "fm_" + uid$, 1, 0, duration_s, sample_rate_Hz,
        ... "0.4 * sin(twoPi * carrier_freq_Hz * x + (modulation_index + chaos_amount * 3 * x) * sin(twoPi * modFreq * (1 + chaos_amount * 0.5 * x) * x)) * exp(-x * 0.4)"

elsif texture_type = 7
    # Wobble Bass - LFO on index
    wobbleRate = 5 + chaos_amount * 10
    outputSound = Create Sound from formula: "fm_" + uid$, 1, 0, duration_s, sample_rate_Hz,
        ... "0.5 * sin(twoPi * carrier_freq_Hz * x + modulation_index * (1 + 0.5 * sin(twoPi * wobbleRate * x)) * sin(twoPi * modFreq * x))"

elsif texture_type = 8
    # Alien Choir - slow modulation of FM
    outputSound = Create Sound from formula: "fm_" + uid$, 1, 0, duration_s, sample_rate_Hz,
        ... "0.35 * sin(twoPi * carrier_freq_Hz * x + modulation_index * sin(twoPi * modFreq * x + chaos_amount * 2 * sin(twoPi * 0.5 * x))) * (1 + 0.2 * sin(twoPi * 3 * x))"

elsif texture_type = 9
    # Harmonic Bells - multiple FM operators
    outputSound = Create Sound from formula: "fm_" + uid$, 1, 0, duration_s, sample_rate_Hz,
        ... "0.25 * sin(twoPi * carrier_freq_Hz * x + modulation_index * sin(twoPi * modFreq * x)) * exp(-x * 2) + 0.2 * sin(twoPi * carrier_freq_Hz * 2.76 * x + modulation_index * 0.7 * sin(twoPi * modFreq * 3.5 * x)) * exp(-x * 3) + 0.15 * sin(twoPi * carrier_freq_Hz * 5.4 * x) * exp(-x * 4)"

elsif texture_type = 10
    # Inharmonic Stack - golden ratio
    phi = 1.618033989
    outputSound = Create Sound from formula: "fm_" + uid$, 1, 0, duration_s, sample_rate_Hz,
        ... "0.35 * sin(twoPi * carrier_freq_Hz * x + modulation_index * sin(twoPi * carrier_freq_Hz * phi * x)) * exp(-x * 1.2) + 0.25 * sin(twoPi * carrier_freq_Hz * phi * phi * x + modulation_index * 0.5 * sin(twoPi * carrier_freq_Hz * phi * x)) * exp(-x * 1.8)"

elsif texture_type = 11
    # Feedback Scream - deep FM cascade
    outputSound = Create Sound from formula: "fm_" + uid$, 1, 0, duration_s, sample_rate_Hz,
        ... "0.35 * sin(twoPi * carrier_freq_Hz * x + modulation_index * sin(twoPi * modFreq * x + modulation_index * 0.7 * sin(twoPi * modFreq * x + modulation_index * 0.3 * sin(twoPi * modFreq * x)))) * (1 + 0.3 * sin(twoPi * 1 * x))"

elsif texture_type = 12
    # Sidebanded Drone - explicit sidebands
    outputSound = Create Sound from formula: "fm_" + uid$, 1, 0, duration_s, sample_rate_Hz,
        ... "0.25 * (sin(twoPi * carrier_freq_Hz * x) + 0.6 * sin(twoPi * (carrier_freq_Hz + modFreq) * x) + 0.6 * sin(twoPi * (carrier_freq_Hz - modFreq) * x) + 0.3 * sin(twoPi * (carrier_freq_Hz + 2 * modFreq) * x) + 0.3 * sin(twoPi * (carrier_freq_Hz - 2 * modFreq) * x))"
endif

# === Apply Envelope ===
appendInfoLine: "Applying envelope..."
selectObject: outputSound

if envelope_type = 2
    # Percussive
    Formula: "self * exp(-x * 5)"
    
elsif envelope_type = 3
    # Slow Fade
    Formula: "self * exp(-x * 0.5)"
    
elsif envelope_type = 4
    # Tremolo (smooth)
    tremRate = 5 + chaos_amount * 15
    tremDepth = 0.3 + chaos_amount * 0.4
    Formula: "self * (1 - tremDepth + tremDepth * (0.5 + 0.5 * sin(twoPi * tremRate * x)))"
    
elsif envelope_type = 5
    # Swell
    attackTime = 0.3 + chaos_amount * 0.5
    Formula: "self * min(1, x / attackTime)"
    
elsif envelope_type = 6
    # ADSR (split into separate passes)
    attack = 0.02
    decay = 0.1 + chaos_amount * 0.2
    sustain = 0.5 + chaos_amount * 0.3
    releaseStart = duration_s - 0.3
    
    Formula: "if x < attack then self * (x / attack) else self fi"
    Formula: "if x >= attack and x < attack + decay then self * (1 - (1 - sustain) * ((x - attack) / decay)) else self fi"
    Formula: "if x >= attack + decay and x < releaseStart then self * sustain else self fi"
    Formula: "if x >= releaseStart then self * sustain * (1 - (x - releaseStart) / (duration_s - releaseStart)) else self fi"
endif

# === Fade in/out ===
selectObject: outputSound
Formula: "if x < 0.01 then self * (x / 0.01) else self fi"
Formula: "if x > duration_s - 0.01 then self * ((duration_s - x) / 0.01) else self fi"

# === Spatial Processing ===
if spatial_mode = 2
    # Stereo Wide
    appendInfoLine: "Creating stereo width..."
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Filter (pass Hann band): 0, carrier_freq_Hz * 3, 100
    leftFiltered = selected("Sound")
    removeObject: leftSound
    leftSound = leftFiltered
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Filter (pass Hann band): carrier_freq_Hz * 0.5, carrier_freq_Hz * 6, 100
    rightFiltered = selected("Sound")
    removeObject: rightSound
    rightSound = rightFiltered
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "fm_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound

elsif spatial_mode = 3
    # Rotating
    appendInfoLine: "Creating rotating stereo..."
    
    rotRate = 0.2 + chaos_amount * 0.3
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * (0.5 + 0.5 * cos(twoPi * rotRate * x))"
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * (0.5 + 0.5 * sin(twoPi * rotRate * x))"
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "fm_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound
else
    selectObject: outputSound
    Rename: "fm_" + preset_name$
endif

# === Normalize ===
if normalize_output
    selectObject: outputSound
    Scale peak: 0.9
endif

# === Visualization ===
if draw_visualization
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
# Procedure: drawVisualization
# ==============================================================================
procedure drawVisualization
    
    Erase all
    
    .leftMargin = 0.6
    .rightMargin = 6.5
    
    # === Title ===
    Select outer viewport: 0, 7, 0.5, 1.2
    Select inner viewport: 0, 7, 0.5, 1.2
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.8, "half", "FM Texture: " + preset_name$
    Font size: 10
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.2, "half", "Carrier: " + fixed$(carrier_freq_Hz, 0) + " Hz | Mod: " + fixed$(modFreq, 0) + " Hz | Index: " + fixed$(modulation_index, 1)
    
    # === Spectrogram ===
    Select outer viewport: 0, 7, 1.3, 4.8
    Colour: "{0.85, 0.85, 0.85}"
    Draw inner box
    
    Select inner viewport: .leftMargin, .rightMargin, 1.4, 4.7
    
    if spatial_mode > 1
        selectObject: outputSound
        Extract one channel: 1
        .monoSpec = selected("Sound")
    else
        selectObject: outputSound
        Copy: "temp_spec"
        .monoSpec = selected("Sound")
    endif
    
    selectObject: .monoSpec
    # Max frequency based on FM sidebands
    .maxFreqSpec = min(8000, carrier_freq_Hz * (1 + modulation_index) * 1.5)
    
    To Spectrogram: 0.02, .maxFreqSpec, 0.005, 20, "Gaussian"
    .spec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    
    removeObject: .monoSpec, .spec
    
    Select inner viewport: .leftMargin, .rightMargin, 1.4, 4.7
    Axes: 0, duration_s, 0, .maxFreqSpec
    Colour: "White"
    Marks left: 5, "yes", "yes", "no"
    Marks bottom every: 1, 0.5, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Frequency (Hz)"
    
    # === Footer ===
    Select outer viewport: 0, 7, 4.9, 5.4
    Select inner viewport: 0, 7, 4.9, 5.4
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "{0.4, 0.4, 0.4}"
    .paramText$ = "Ratio: " + fixed$(modulator_ratio, 2) + " | Chaos: " + fixed$(chaos_amount, 2) + " | " + envelope_type$
    Text: 0.5, "centre", 0.5, "half", .paramText$
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc