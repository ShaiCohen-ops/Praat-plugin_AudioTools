# ============================================================
# Praat AudioTools - AM Additive Synthesis Generator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Corrected
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Additive synthesis with multiple spectral configurations
#   and amplitude modulation envelopes.
#
# Usage:
#   Run this script (no input sound required).
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.2:
#   - Fixed nested if/fi in ADSR envelope
#   - Smooth gate/stutter transitions (no clicks)
#   - Fixed random bursts implementation
#   - Added presets
#   - Added spatial modes
#   - Added visualization
#   - Modern syntax throughout
# ============================================================

form AM Additive Synthesis Generator
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Warm Pad
        option Bright Organ
        option Bell Tone
        option Shimmer
        option Bass Drone
        option Ethereal Choir
        option Plucked String
        option Sci-Fi Sweep
    
    comment === Basic Settings ===
    positive Duration_s 3.0
    integer Sample_rate_Hz 44100
    positive Fundamental_Hz 220
    integer Num_partials 8
    
    comment === Texture Type ===
    optionmenu Texture_type 1
        option Harmonic Series
        option Odd Harmonics
        option Even Harmonics
        option Inharmonic Cluster
        option Golden Bells
        option Octave Stack
        option Fifth Stack
        option Shepard Tone
        option Spectral Comb
        option Random Cloud
        option Detuned Unison
        option Harmonic Decay
        option Rising Partials
        option Filtered Spectrum
        option Chaotic Swarm
    
    comment === Modulation ===
    real Detune 0.1
    real Chaos 0.3
    
    comment === Envelope ===
    optionmenu Envelope_type 1
        option No Envelope
        option Percussive
        option Slow Fade
        option Smooth Gate
        option Reverse
        option Tremolo
        option Swell
        option ADSR
        option Smooth Stutter
        option Random Bursts
    
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
    # Warm Pad
    duration_s = 5
    fundamental_Hz = 110
    num_partials = 6
    texture_type = 1
    detune = 0.05
    chaos = 0.1
    envelope_type = 7
    spatial_mode = 2
    preset_name$ = "WarmPad"
elsif preset = 3
    # Bright Organ
    duration_s = 3
    fundamental_Hz = 220
    num_partials = 10
    texture_type = 2
    detune = 0.02
    chaos = 0.05
    envelope_type = 1
    spatial_mode = 2
    preset_name$ = "BrightOrgan"
elsif preset = 4
    # Bell Tone
    duration_s = 4
    fundamental_Hz = 440
    num_partials = 8
    texture_type = 5
    detune = 0.08
    chaos = 0.2
    envelope_type = 2
    spatial_mode = 3
    preset_name$ = "BellTone"
elsif preset = 5
    # Shimmer
    duration_s = 5
    fundamental_Hz = 330
    num_partials = 12
    texture_type = 11
    detune = 0.15
    chaos = 0.3
    envelope_type = 6
    spatial_mode = 3
    preset_name$ = "Shimmer"
elsif preset = 6
    # Bass Drone
    duration_s = 8
    fundamental_Hz = 55
    num_partials = 6
    texture_type = 1
    detune = 0.03
    chaos = 0.1
    envelope_type = 3
    spatial_mode = 2
    preset_name$ = "BassDrone"
elsif preset = 7
    # Ethereal Choir
    duration_s = 6
    fundamental_Hz = 180
    num_partials = 8
    texture_type = 14
    detune = 0.1
    chaos = 0.4
    envelope_type = 7
    spatial_mode = 3
    preset_name$ = "EtherealChoir"
elsif preset = 8
    # Plucked String
    duration_s = 2
    fundamental_Hz = 196
    num_partials = 10
    texture_type = 12
    detune = 0.02
    chaos = 0.15
    envelope_type = 2
    spatial_mode = 1
    preset_name$ = "PluckedString"
elsif preset = 9
    # Sci-Fi Sweep
    duration_s = 4
    fundamental_Hz = 150
    num_partials = 10
    texture_type = 13
    detune = 0.1
    chaos = 0.5
    envelope_type = 5
    spatial_mode = 3
    preset_name$ = "SciFiSweep"
endif

# === Validation ===
if num_partials > 32
    num_partials = 32
endif
if num_partials < 1
    num_partials = 1
endif

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi
phi = (1 + sqrt(5)) / 2

# === Info ===
writeInfoLine: "=== AM Additive Synthesis Generator ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Duration: ", duration_s, " s"
appendInfoLine: "Fundamental: ", fundamental_Hz, " Hz"
appendInfoLine: "Partials: ", num_partials
appendInfoLine: "Texture: ", texture_type$
appendInfoLine: "Envelope: ", envelope_type$
appendInfoLine: ""

# === Create output sound ===
outputSound = Create Sound from formula: "additive_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"

# === Build additive spectrum based on texture type ===
appendInfoLine: "Building spectrum..."

for partial to num_partials
    
    # Compute frequency and amplitude based on texture
    if texture_type = 1
        # Harmonic Series
        freq = fundamental_Hz * partial
        amp = 1 / partial
        
    elsif texture_type = 2
        # Odd Harmonics (square wave spectrum)
        harmonic = 2 * partial - 1
        freq = fundamental_Hz * harmonic
        amp = 1 / harmonic
        
    elsif texture_type = 3
        # Even Harmonics
        harmonic = 2 * partial
        freq = fundamental_Hz * harmonic
        amp = 1 / harmonic
        
    elsif texture_type = 4
        # Inharmonic Cluster
        freq = fundamental_Hz * (partial + chaos * randomGauss(0, 0.5))
        amp = 1 / partial
        
    elsif texture_type = 5
        # Golden Bells (phi ratio)
        freq = fundamental_Hz * (phi ^ (partial - 1))
        amp = 1 / (2 ^ (partial - 1))
        
    elsif texture_type = 6
        # Octave Stack
        freq = fundamental_Hz * (2 ^ (partial - 1))
        amp = 1 / (2 ^ (partial - 1))
        
    elsif texture_type = 7
        # Fifth Stack (3:2 ratio)
        freq = fundamental_Hz * (1.5 ^ (partial - 1))
        amp = 1 / (1.5 ^ (partial - 1))
        
    elsif texture_type = 8
        # Shepard Tone (octaves with bell-curve amplitude)
        freq = fundamental_Hz * (2 ^ (partial - 1))
        octavePos = (partial - 1) / num_partials
        amp = sin(pi * octavePos)
        # Add slight glide for Shepard illusion
        glide = chaos * 0.1
        
    elsif texture_type = 9
        # Spectral Comb (evenly spaced non-harmonic)
        spacing = 2 + chaos * 3
        freq = fundamental_Hz * (1 + spacing * (partial - 1))
        amp = 1 / (1 + partial * 0.2)
        
    elsif texture_type = 10
        # Random Cloud
        freq = fundamental_Hz * randomUniform(0.5, 4)
        amp = randomUniform(0.3, 1) / num_partials
        
    elsif texture_type = 11
        # Detuned Unison
        freq = fundamental_Hz * (1 + detune * (partial - num_partials / 2) / num_partials)
        amp = 1 / num_partials
        
    elsif texture_type = 12
        # Harmonic Decay (each partial decays at different rate)
        freq = fundamental_Hz * partial
        amp = 1 / partial
        decayRate = partial * 0.5
        
    elsif texture_type = 13
        # Rising Partials (glissando up)
        freq = fundamental_Hz * partial
        amp = 1 / partial
        riseRate = chaos * 0.5
        
    elsif texture_type = 14
        # Filtered Spectrum (Gaussian envelope)
        center = num_partials / 2
        freq = fundamental_Hz * partial
        amp = (1 / partial) * exp(-((partial - center) ^ 2) / (2 * (chaos * 5 + 1) ^ 2))
        
    elsif texture_type = 15
        # Chaotic Swarm
        freq = fundamental_Hz * partial
        amp = 1 / (partial + abs(chaos * randomGauss(0, 2)))
        fmRate = partial * 10
        fmDepth = chaos
    endif
    
    # Build formula for this partial
    selectObject: outputSound
    
    if texture_type = 8
        # Shepard with glide
        Formula: "self + amp * sin(twoPi * freq * (1 + glide * x) * x)"
    elsif texture_type = 12
        # Harmonic Decay
        Formula: "self + amp * sin(twoPi * freq * x) * exp(-x * decayRate)"
    elsif texture_type = 13
        # Rising Partials
        Formula: "self + amp * sin(twoPi * freq * (1 + riseRate * x) * x)"
    elsif texture_type = 15
        # Chaotic Swarm with FM
        Formula: "self + amp * sin(twoPi * freq * (1 + fmDepth * sin(fmRate * x)) * x)"
    else
        # Standard additive
        Formula: "self + amp * sin(twoPi * freq * x)"
    endif
    
endfor

# === Apply Envelope ===
appendInfoLine: "Applying envelope..."

selectObject: outputSound

if envelope_type = 2
    # Percussive
    Formula: "self * exp(-x * 5)"

elsif envelope_type = 3
    # Slow Fade
    Formula: "self * exp(-x * 0.3)"

elsif envelope_type = 4
    # Smooth Gate (raised cosine, no clicks)
    gatePeriod = 0.1 + chaos * 0.3
    Formula: "self * (0.5 + 0.5 * cos(twoPi * x / gatePeriod)) * (sin(twoPi * x / gatePeriod) > 0)"

elsif envelope_type = 5
    # Reverse (fade in)
    Formula: "self * (x / duration_s)"

elsif envelope_type = 6
    # Tremolo
    tremRate = 5 + chaos * 15
    tremDepth = 0.3 + chaos * 0.5
    Formula: "self * (1 - tremDepth + tremDepth * (0.5 + 0.5 * sin(twoPi * tremRate * x)))"

elsif envelope_type = 7
    # Swell (attack then sustain)
    attackTime = 0.3 + chaos * 0.5
    Formula: "self * min(1, x / attackTime)"

elsif envelope_type = 8
    # ADSR (split into separate passes to avoid nested if/fi)
    attack = 0.01
    decay = 0.1 + chaos * 0.2
    sustain = 0.5 + chaos * 0.3
    release = 0.3
    decayEnd = attack + decay
    releaseStart = duration_s - release
    
    # Attack phase
    Formula: "if x < attack then self * (x / attack) else self fi"
    
    # Decay phase
    Formula: "if x >= attack and x < decayEnd then self * (1 - (1 - sustain) * ((x - attack) / decay)) else self fi"
    
    # Sustain phase (already at correct level from decay)
    
    # Release phase
    Formula: "if x >= releaseStart then self * sustain * (1 - (x - releaseStart) / release) else self fi"
    
    # Clamp sustain level for middle section
    Formula: "if x >= decayEnd and x < releaseStart then self * sustain else self fi"

elsif envelope_type = 9
    # Smooth Stutter (raised cosine transitions)
    stutterRate = 10 + chaos * 30
    Formula: "self * (0.5 + 0.5 * cos(twoPi * stutterRate * x))"

elsif envelope_type = 10
    # Random Bursts (pre-computed burst times)
    burstDensity = 5 + chaos * 20
    burstDecay = 50
    # Create burst envelope at control rate, then resample
    burstEnv = Create Sound from formula: "burst_" + uid$, 1, 0, duration_s, 100, "0"
    
    # Place random bursts
    numBursts = floor(duration_s * burstDensity)
    for b to numBursts
        burstTime = randomUniform(0, duration_s)
        selectObject: burstEnv
        Formula: "if abs(x - burstTime) < 0.05 then self + exp(-abs(x - burstTime) * burstDecay) else self fi"
    endfor
    
    # Resample to audio rate
    selectObject: burstEnv
    burstEnvAudio = Resample: sample_rate_Hz, 50
    burstEnvName$ = selected$("Sound")
    
    # Apply to output
    selectObject: outputSound
    Formula: "self * Sound_'burstEnvName$'[]"
    
    removeObject: burstEnv, burstEnvAudio
endif

# === Fade in/out ===
fadeTime = 0.01
selectObject: outputSound
Formula: "if x < fadeTime then self * (x / fadeTime) else self fi"
Formula: "if x > duration_s - fadeTime then self * ((duration_s - x) / fadeTime) else self fi"

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
    Rename: "additive_" + preset_name$
    
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
    Rename: "additive_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound
else
    selectObject: outputSound
    Rename: "additive_" + preset_name$
endif

# === Normalize ===
if normalize_output
    selectObject: outputSound
    Scale peak: 0.95
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
    
    .leftMargin = 0.6
    .rightMargin = 6.5
    
    # === Title ===
    Select outer viewport: 0, 7, 0, 1.5
    Font size: 12
    Colour: "Black"
    Text top: "no", "Additive Synthesis: " + preset_name$ + " (" + texture_type$ + ")"
    
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
    
    selectObject: .monoForSpec
    .maxFreqSpec = min(8000, max(2000, fundamental_Hz * num_partials * 1.5))
    
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
    Marks bottom every: 1, 0.5, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"
    
    # === Footer ===
    Select outer viewport: 0, 7, 6.4, 7
    Font size: 8
    Colour: "{0.4, 0.4, 0.4}"
    .paramText$ = "Fund: " + fixed$(fundamental_Hz, 0) + " Hz | Partials: " + string$(num_partials) + " | Envelope: " + envelope_type$
    Text top: "no", .paramText$
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc