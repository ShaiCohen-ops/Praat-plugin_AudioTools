# ============================================================
# Praat AudioTools - AM Additive Synthesis Generator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
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
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.2:
#   - Fixed ADSR if/fi, smooth gate/stutter, random bursts, presets, spatial, viz
#
# Changelog v0.3:
#   - Fixed preset texture/envelope labels: presets set the numeric texture_type
#     and envelope_type but left texture_type$ / envelope_type$ at the form
#     default, so every preset reported "Harmonic Series / No Envelope" in the
#     info window, plot title, and footer regardless of the actual synthesis.
#     Each preset now sets both strings to match.
#   - Rebuilt the visualization in the AudioTools house style (8-inch canvas,
#     title band, waveform + spectrogram, grey summary, larger fonts, black marks).
#   - Replaced the non-ASCII en-dash.
#
# Changelog v0.4:
#   - Added a Melody_demo mode (ported from the FM Texture Generator): plays a
#     major arpeggio (root-3rd-5th-octave and back) with the selected preset
#     instead of a single sustained tone. Note generation refactored into a
#     makeAMNote procedure; the amplitude envelope is applied per note (so
#     Percussive/ADSR/etc. shape each note rather than the whole sequence).
# ============================================================

form AM Additive Synthesis Generator
    comment === Demo Mode ===
    boolean Melody_demo 0
    comment (If checked, plays a major arpeggio with the selected preset)
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
    texture_type$ = "Harmonic Series"
    envelope_type$ = "Swell"
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
    texture_type$ = "Odd Harmonics"
    envelope_type$ = "No Envelope"
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
    texture_type$ = "Golden Bells"
    envelope_type$ = "Percussive"
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
    texture_type$ = "Detuned Unison"
    envelope_type$ = "Tremolo"
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
    texture_type$ = "Harmonic Series"
    envelope_type$ = "Slow Fade"
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
    texture_type$ = "Filtered Spectrum"
    envelope_type$ = "Swell"
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
    texture_type$ = "Harmonic Decay"
    envelope_type$ = "Percussive"
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
    texture_type$ = "Rising Partials"
    envelope_type$ = "Reverse"
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

# === Generate: single note or melody arpeggio ===
if melody_demo
    appendInfoLine: "Generating melody demo (major arpeggio)..."

    @makeAMNote: fundamental_Hz * 1.0, 0.4
    n1 = selected("Sound")
    @makeAMNote: fundamental_Hz * 1.25, 0.4
    n2 = selected("Sound")
    @makeAMNote: fundamental_Hz * 1.5, 0.4
    n3 = selected("Sound")
    @makeAMNote: fundamental_Hz * 2.0, 0.6
    n4 = selected("Sound")
    @makeAMNote: fundamental_Hz * 1.5, 0.4
    n5 = selected("Sound")
    @makeAMNote: fundamental_Hz * 1.25, 0.4
    n6 = selected("Sound")
    @makeAMNote: fundamental_Hz * 1.0, 0.4
    n7 = selected("Sound")
    @makeAMNote: fundamental_Hz * 0.5, 0.8
    n8 = selected("Sound")

    selectObject: n1, n2, n3, n4, n5, n6, n7, n8
    Concatenate
    outputSound = selected("Sound")
    removeObject: n1, n2, n3, n4, n5, n6, n7, n8
else
    @makeAMNote: fundamental_Hz, duration_s
    outputSound = selected("Sound")
endif


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
# Procedure: makeAMNote - build one additive note at .freq over .dur
# (spectrum + per-note amplitude envelope + fade). Leaves the note selected.
# ==============================================================================
procedure makeAMNote: .freq, .dur

# === Create output sound ===
.note = Create Sound from formula: "amnote_" + uid$, 1, 0, .dur, sample_rate_Hz, "0"

# === Build additive spectrum based on texture type ===
appendInfoLine: "Building spectrum..."

for partial to num_partials
    
    # Compute frequency and amplitude based on texture
    if texture_type = 1
        # Harmonic Series
        freq = .freq * partial
        amp = 1 / partial
        
    elsif texture_type = 2
        # Odd Harmonics (square wave spectrum)
        harmonic = 2 * partial - 1
        freq = .freq * harmonic
        amp = 1 / harmonic
        
    elsif texture_type = 3
        # Even Harmonics
        harmonic = 2 * partial
        freq = .freq * harmonic
        amp = 1 / harmonic
        
    elsif texture_type = 4
        # Inharmonic Cluster
        freq = .freq * (partial + chaos * randomGauss(0, 0.5))
        amp = 1 / partial
        
    elsif texture_type = 5
        # Golden Bells (phi ratio)
        freq = .freq * (phi ^ (partial - 1))
        amp = 1 / (2 ^ (partial - 1))
        
    elsif texture_type = 6
        # Octave Stack
        freq = .freq * (2 ^ (partial - 1))
        amp = 1 / (2 ^ (partial - 1))
        
    elsif texture_type = 7
        # Fifth Stack (3:2 ratio)
        freq = .freq * (1.5 ^ (partial - 1))
        amp = 1 / (1.5 ^ (partial - 1))
        
    elsif texture_type = 8
        # Shepard Tone (octaves with bell-curve amplitude)
        freq = .freq * (2 ^ (partial - 1))
        octavePos = (partial - 1) / num_partials
        amp = sin(pi * octavePos)
        # Add slight glide for Shepard illusion
        glide = chaos * 0.1
        
    elsif texture_type = 9
        # Spectral Comb (evenly spaced non-harmonic)
        spacing = 2 + chaos * 3
        freq = .freq * (1 + spacing * (partial - 1))
        amp = 1 / (1 + partial * 0.2)
        
    elsif texture_type = 10
        # Random Cloud
        freq = .freq * randomUniform(0.5, 4)
        amp = randomUniform(0.3, 1) / num_partials
        
    elsif texture_type = 11
        # Detuned Unison
        freq = .freq * (1 + detune * (partial - num_partials / 2) / num_partials)
        amp = 1 / num_partials
        
    elsif texture_type = 12
        # Harmonic Decay (each partial decays at different rate)
        freq = .freq * partial
        amp = 1 / partial
        decayRate = partial * 0.5
        
    elsif texture_type = 13
        # Rising Partials (glissando up)
        freq = .freq * partial
        amp = 1 / partial
        riseRate = chaos * 0.5
        
    elsif texture_type = 14
        # Filtered Spectrum (Gaussian envelope)
        center = num_partials / 2
        freq = .freq * partial
        amp = (1 / partial) * exp(-((partial - center) ^ 2) / (2 * (chaos * 5 + 1) ^ 2))
        
    elsif texture_type = 15
        # Chaotic Swarm
        freq = .freq * partial
        amp = 1 / (partial + abs(chaos * randomGauss(0, 2)))
        fmRate = partial * 10
        fmDepth = chaos
    endif
    
    # Build formula for this partial
    selectObject: .note
    
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

selectObject: .note

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
    Formula: "self * (x / .dur)"

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
    releaseStart = .dur - release
    
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
    burstEnv = Create Sound from formula: "burst_" + uid$, 1, 0, .dur, 100, "0"
    
    # Place random bursts
    numBursts = floor(.dur * burstDensity)
    for b to numBursts
        burstTime = randomUniform(0, .dur)
        selectObject: burstEnv
        Formula: "if abs(x - burstTime) < 0.05 then self + exp(-abs(x - burstTime) * burstDecay) else self fi"
    endfor
    
    # Resample to audio rate
    selectObject: burstEnv
    burstEnvAudio = Resample: sample_rate_Hz, 50
    burstEnvName$ = selected$("Sound")
    
    # Apply to output
    selectObject: .note
    Formula: "self * Sound_'burstEnvName$'[]"
    
    removeObject: burstEnv, burstEnvAudio
endif

# === Fade in/out ===
fadeTime = 0.01
selectObject: .note
Formula: "if x < fadeTime then self * (x / fadeTime) else self fi"
Formula: "if x > .dur - fadeTime then self * ((.dur - x) / fadeTime) else self fi"

    .sound = selected("Sound")
endproc

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
    .titleSuffix$ = ""
    if melody_demo
        .titleSuffix$ = " - Melody"
    endif
    Text: 0.5, "centre", 0.5, "half", "Additive Synthesis: " + preset_name$ + " (" + texture_type$ + ")" + .titleSuffix$

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
    .maxFreqSpec = min(8000, max(2000, fundamental_Hz * num_partials * 1.5))
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
    Text: 0.5, "centre", 0.5, "half", "Fund: " + fixed$(fundamental_Hz, 0) + " Hz | Partials: " + string$(num_partials) + " | Envelope: " + envelope_type$ + " | " + .spatial$
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc