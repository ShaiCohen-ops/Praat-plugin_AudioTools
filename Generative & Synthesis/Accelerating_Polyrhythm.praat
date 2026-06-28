# ============================================================
# Praat AudioTools - Accelerating Polyrhythm.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025) - With Presets
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Accelerating Polyrhythm Generator
#   Creates evolving polyrhythmic patterns with acceleration
#
# Usage:
#   Run this script (no input sound required).
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.3:
#   - Added presets for common polyrhythmic patterns
#   - Simplified visualization (removed waveform panel)
# ============================================================

form Accelerating Polyrhythm Generator
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option 3:2 Hemiola (gentle)
        option 4:3 Cross-rhythm
        option 5:4 Quintuplet feel
        option 7:4 Progressive rock
        option 5:3 African bell pattern
        option 8:5 Golden ratio approx
        option 3:2:4 Triple layer
        option Nancarrow Study 21
        option Reich Piano Phase
        option Ligeti Etude feel

    comment === Duration  (Target overrides Base if > 0) ===
    real Base_duration_s 2.0
    real Target_total_duration_s 0
    integer Total_cycles 8

    comment === Patterns  (beats / Hz) ===
    integer Pattern1_beats 3
    real Pattern1_frequency_Hz 300
    integer Pattern2_beats 4
    real Pattern2_frequency_Hz 500

    comment === Acceleration ===
    real Acceleration_factor 2.0
    boolean Exponential_acceleration 1

    comment === Morphing ===
    optionmenu Morph_type 1
        option None
        option Frequency morph
        option Amplitude morph
        option Rhythm morph
        option Pan morph
        option Random evolution

    comment === Tone Shape ===
    real Max_tone_duration_ms 100
    real Attack_ms 5
    real Decay_ms 30
    optionmenu Waveform 1
        option Sine
        option Triangle
        option Square (soft)
        option Pluck (decaying harmonics)

    comment === Output ===
    boolean Play_result 1
    boolean Draw_visualization 1
endform

# --- Apply Presets ---
if preset = 2
    # 3:2 Hemiola (gentle)
    pattern1_beats = 3
    pattern2_beats = 2
    pattern1_frequency_Hz = 440
    pattern2_frequency_Hz = 554.37
    base_duration_s = 2.0
    total_cycles = 6
    acceleration_factor = 1.5
    exponential_acceleration = 1
    morph_type = 1
    waveform = 1
elsif preset = 3
    # 4:3 Cross-rhythm
    pattern1_beats = 4
    pattern2_beats = 3
    pattern1_frequency_Hz = 330
    pattern2_frequency_Hz = 440
    base_duration_s = 2.0
    total_cycles = 8
    acceleration_factor = 2.0
    exponential_acceleration = 1
    morph_type = 1
    waveform = 1
elsif preset = 4
    # 5:4 Quintuplet feel
    pattern1_beats = 5
    pattern2_beats = 4
    pattern1_frequency_Hz = 392
    pattern2_frequency_Hz = 523.25
    base_duration_s = 2.5
    total_cycles = 8
    acceleration_factor = 2.0
    exponential_acceleration = 1
    morph_type = 2
    waveform = 1
elsif preset = 5
    # 7:4 Progressive rock
    pattern1_beats = 7
    pattern2_beats = 4
    pattern1_frequency_Hz = 220
    pattern2_frequency_Hz = 440
    base_duration_s = 2.8
    total_cycles = 6
    acceleration_factor = 1.8
    exponential_acceleration = 1
    morph_type = 1
    waveform = 3
elsif preset = 6
    # 5:3 African bell pattern
    pattern1_beats = 5
    pattern2_beats = 3
    pattern1_frequency_Hz = 800
    pattern2_frequency_Hz = 1200
    base_duration_s = 1.5
    total_cycles = 10
    acceleration_factor = 2.5
    exponential_acceleration = 1
    morph_type = 5
    waveform = 4
    max_tone_duration_ms = 60
    attack_ms = 2
    decay_ms = 50
elsif preset = 7
    # 8:5 Golden ratio approx
    pattern1_beats = 8
    pattern2_beats = 5
    pattern1_frequency_Hz = 261.63
    pattern2_frequency_Hz = 392
    base_duration_s = 3.0
    total_cycles = 8
    acceleration_factor = 1.618
    exponential_acceleration = 1
    morph_type = 2
    waveform = 1
elsif preset = 8
    # 3:2:4 Triple layer (uses random evolution for third voice feel)
    pattern1_beats = 3
    pattern2_beats = 4
    pattern1_frequency_Hz = 262
    pattern2_frequency_Hz = 392
    base_duration_s = 2.0
    total_cycles = 12
    acceleration_factor = 2.0
    exponential_acceleration = 1
    morph_type = 6
    waveform = 1
elsif preset = 9
    # Nancarrow Study 21 inspired
    pattern1_beats = 17
    pattern2_beats = 18
    pattern1_frequency_Hz = 220
    pattern2_frequency_Hz = 233.08
    base_duration_s = 4.0
    total_cycles = 6
    acceleration_factor = 1.06
    exponential_acceleration = 1
    morph_type = 1
    waveform = 4
    max_tone_duration_ms = 80
elsif preset = 10
    # Reich Piano Phase inspired
    pattern1_beats = 12
    pattern2_beats = 12
    pattern1_frequency_Hz = 330
    pattern2_frequency_Hz = 440
    base_duration_s = 3.0
    total_cycles = 12
    acceleration_factor = 1.02
    exponential_acceleration = 0
    morph_type = 1
    waveform = 1
elsif preset = 11
    # Ligeti Etude feel
    pattern1_beats = 5
    pattern2_beats = 7
    pattern1_frequency_Hz = 440
    pattern2_frequency_Hz = 554.37
    base_duration_s = 2.0
    total_cycles = 10
    acceleration_factor = 2.2
    exponential_acceleration = 1
    morph_type = 4
    waveform = 1
    attack_ms = 3
    decay_ms = 40
endif

# --- Guard acceleration factor (avoid zero/negative cycle durations) ---
# Exponential mode needs accel > 0; linear mode needs the per-cycle factor
# 1 + (cycle-1)*(accel-1) to stay positive across all cycles.
if acceleration_factor < 0.01
    acceleration_factor = 0.01
endif
if exponential_acceleration = 0
    minAccelLin = 1 - 0.9 / max(total_cycles - 1, 1)
    if acceleration_factor < minAccelLin
        acceleration_factor = minAccelLin
    endif
endif

# --- Defaults for fields removed from form ---
sample_rate_Hz = 44100
pattern1_amplitude = 0.4
pattern1_pan = -0.5
pattern2_amplitude = 0.4
pattern2_pan = 0.5

# --- If target duration is set, back-calculate base_duration_s ---
if target_total_duration_s > 0
    durationSum = 0
    for cycle to total_cycles
        if exponential_acceleration
            durationSum += 1 / (acceleration_factor ^ (cycle - 1))
        else
            durationSum += 1 / (1 + (cycle - 1) * (acceleration_factor - 1))
        endif
    endfor
    if durationSum > 0
        base_duration_s = target_total_duration_s / durationSum
    endif
endif

# --- Constants ---
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi

# --- Calculate total duration ---
totalDuration = 0
for cycle to total_cycles
    if exponential_acceleration
        totalDuration += base_duration_s / (acceleration_factor ^ (cycle - 1))
    else
        totalDuration += base_duration_s / (1 + (cycle - 1) * (acceleration_factor - 1))
    endif
endfor

# --- Info ---
writeInfoLine: "=== Accelerating Polyrhythm Generator ==="
if preset > 1
    appendInfoLine: "Preset: ", preset$
endif
appendInfoLine: "Pattern: ", pattern1_beats, " against ", pattern2_beats
appendInfoLine: "Cycles: ", total_cycles
appendInfoLine: "Total duration: ", fixed$(totalDuration, 2), " s"
appendInfoLine: "Morph type: ", morph_type$
appendInfoLine: ""

# --- Pre-calculate all events ---
maxEvents = total_cycles * (pattern1_beats + pattern2_beats + 20)
eventTime# = zero#(maxEvents)
eventFreq# = zero#(maxEvents)
eventAmp# = zero#(maxEvents)
eventPan# = zero#(maxEvents)
eventDur# = zero#(maxEvents)
eventPattern# = zero#(maxEvents)
nEvents = 0

currentTime = 0

for cycle to total_cycles
    # Calculate duration for this cycle
    if exponential_acceleration
        cycleDuration = base_duration_s / (acceleration_factor ^ (cycle - 1))
    else
        cycleDuration = base_duration_s / (1 + (cycle - 1) * (acceleration_factor - 1))
    endif
    
    # Initialize parameters for this cycle
    freq1 = pattern1_frequency_Hz
    freq2 = pattern2_frequency_Hz
    amp1 = pattern1_amplitude
    amp2 = pattern2_amplitude
    pan1 = pattern1_pan
    pan2 = pattern2_pan
    beats1 = pattern1_beats
    beats2 = pattern2_beats
    
    # Progress through morph (0 to 1)
    morphProgress = (cycle - 1) / max(total_cycles - 1, 1)
    
    # Apply morphing
    if morph_type = 2
        # Frequency morph - voices converge
        freq1 = pattern1_frequency_Hz * (1 + 0.5 * morphProgress)
        freq2 = pattern2_frequency_Hz * (1 - 0.25 * morphProgress)
    elsif morph_type = 3
        # Amplitude morph - crossfade
        amp1 = pattern1_amplitude * (1 - 0.5 * morphProgress)
        amp2 = pattern2_amplitude * (0.5 + 0.5 * morphProgress)
    elsif morph_type = 4
        # Rhythm morph - pattern 1 gains beats
        beats1 = pattern1_beats + round(morphProgress * 4)
    elsif morph_type = 5
        # Pan morph - voices swap sides
        pan1 = pattern1_pan + (pattern2_pan - pattern1_pan) * morphProgress
        pan2 = pattern2_pan + (pattern1_pan - pattern2_pan) * morphProgress
    elsif morph_type = 6
        # Random evolution
        freq1 = pattern1_frequency_Hz * (0.8 + randomUniform(0, 0.4))
        freq2 = pattern2_frequency_Hz * (0.8 + randomUniform(0, 0.4))
        amp1 = pattern1_amplitude * (0.6 + randomUniform(0, 0.4))
        amp2 = pattern2_amplitude * (0.6 + randomUniform(0, 0.4))
        pan1 = pattern1_pan + randomUniform(-0.3, 0.3)
        pan2 = pattern2_pan + randomUniform(-0.3, 0.3)
    endif
    
    # Calculate beat spacing
    spacing1 = cycleDuration / beats1
    spacing2 = cycleDuration / beats2
    
    # Limit tone duration to 80% of smallest spacing
    maxToneThisCycle = 0.8 * min(spacing1, spacing2)
    toneDur = min(max_tone_duration_ms / 1000, maxToneThisCycle)
    
    # Add pattern 1 events
    for idx to beats1
        nEvents += 1
        eventTime#[nEvents] = currentTime + (idx - 1) * spacing1
        eventFreq#[nEvents] = freq1
        eventAmp#[nEvents] = amp1
        eventPan#[nEvents] = pan1
        eventDur#[nEvents] = toneDur
        eventPattern#[nEvents] = 1
    endfor
    
    # Add pattern 2 events
    for idx to beats2
        nEvents += 1
        eventTime#[nEvents] = currentTime + (idx - 1) * spacing2
        eventFreq#[nEvents] = freq2
        eventAmp#[nEvents] = amp2
        eventPan#[nEvents] = pan2
        eventDur#[nEvents] = toneDur
        eventPattern#[nEvents] = 2
    endfor
    
    currentTime += cycleDuration
endfor

appendInfoLine: "Generated ", nEvents, " events"

# --- Create stereo output sound ---
soundL = Create Sound from formula: "poly_L_" + uid$, 1, 0, totalDuration, sample_rate_Hz, "0"
soundR = Create Sound from formula: "poly_R_" + uid$, 1, 0, totalDuration, sample_rate_Hz, "0"

# --- Envelope times in seconds ---
attackTime = attack_ms / 1000
decayTime = decay_ms / 1000

appendInfoLine: "Rendering audio..."

# --- Generate all tones ---
for evt to nEvents
    tStart = eventTime#[evt]
    freq = eventFreq#[evt]
    amp = eventAmp#[evt]
    pan = eventPan#[evt]
    dur = eventDur#[evt]
    
    # Calculate L/R amplitudes (constant power panning)
    panAngle = (pan + 1) / 2 * (pi / 2)
    ampL = amp * cos(panAngle)
    ampR = amp * sin(panAngle)
    
    # Adjust envelope times if tone is short
    actualAttack = min(attackTime, dur / 3)
    actualDecay = min(decayTime, dur / 2)
    sustainEnd = dur - actualDecay
    
    # Create tone sound
    toneSound = Create Sound from formula: "tone_" + uid$, 1, 0, dur, sample_rate_Hz, "0"
    
    # Generate waveform
    if waveform = 1
        Formula: "sin(twoPi * freq * x)"
    elsif waveform = 2
        Formula: "2 * abs(2 * ((x * freq) mod 1) - 1) - 1"
    elsif waveform = 3
        Formula: "tanh(3 * sin(twoPi * freq * x))"
    elsif waveform = 4
        Formula: "sin(twoPi * freq * x) + 0.5 * sin(twoPi * 2 * freq * x) * exp(-x * 10) + 0.25 * sin(twoPi * 3 * freq * x) * exp(-x * 20)"
    endif
    
    # Apply envelope
    selectObject: toneSound
    Formula: "if x < actualAttack then self * (x / actualAttack) else self fi"
    Formula: "if x > sustainEnd then self * ((dur - x) / actualDecay) else self fi"
    Formula: "self * amp"
    
    # Get tone name
    selectObject: toneSound
    toneName$ = selected$("Sound")
    
    # Mix into channels
    selectObject: soundL
    Formula: "if x >= tStart and x < tStart + dur then self + (ampL / amp) * Sound_'toneName$'(x - tStart) else self fi"
    
    selectObject: soundR
    Formula: "if x >= tStart and x < tStart + dur then self + (ampR / amp) * Sound_'toneName$'(x - tStart) else self fi"
    
    removeObject: toneSound
    
    if evt mod 20 = 0
        appendInfoLine: "  ", evt, " / ", nEvents, " events..."
    endif
endfor

# --- Combine to stereo ---
selectObject: soundL
plusObject: soundR
stereoSound = Combine to stereo
Rename: "AccelPoly_" + string$(pattern1_beats) + "v" + string$(pattern2_beats)

removeObject: soundL, soundR

# --- Normalize ---
selectObject: stereoSound
Scale peak: 0.9

# --- Visualization ---
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."
    @drawRhythmVisualization: nEvents, totalDuration
endif

# --- Play ---
if play_result
    selectObject: stereoSound
    Play
endif

# --- Final selection ---
selectObject: stereoSound

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# ==============================================================================
# Procedure: drawRhythmVisualization (simplified - 2 panels)
# ==============================================================================
procedure drawRhythmVisualization: .nEvents, .totalDur
    
    Erase all
    
    # Colors
    .col1$ = "{0.2, 0.4, 0.8}"
    .col2$ = "{0.8, 0.3, 0.2}"
    .colGrid$ = "{0.85, 0.85, 0.85}"
    .colCycle$ = "{0.7, 0.7, 0.7}"
    
    # Layout
    .leftMargin = 0.6
    .rightMargin = 7.7
    
    # === Title ===
    Select outer viewport: 0, 8, 0, 0.33
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Accelerating Polyrhythm##"
    
    # === Subtitle ===
    Select outer viewport: 0, 8, 0.33, 0.5
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    if preset > 1
        .subText$ = preset$ + " | " + string$(pattern1_beats) + " against " + string$(pattern2_beats) + " | " + string$(total_cycles) + " cycles"
    else
        .subText$ = string$(pattern1_beats) + " against " + string$(pattern2_beats) + " | " + string$(total_cycles) + " cycles | accel " + fixed$(acceleration_factor, 2)
    endif
    Text: 0.5, "centre", 0.5, "half", .subText$
    
    # === Panel 1: Event timeline ===
    Select outer viewport: 0, 8, 0.6, 3.0
    Colour: .colGrid$
    Draw inner box
    
    Select inner viewport: .leftMargin, .rightMargin, 0.7, 2.9
    Axes: 0, .totalDur, 0, 3
    
    # Draw cycle boundaries
    .cycleTime = 0
    Colour: .colCycle$
    for .cycle to total_cycles
        if exponential_acceleration
            .cycDur = base_duration_s / (acceleration_factor ^ (.cycle - 1))
        else
            .cycDur = base_duration_s / (1 + (.cycle - 1) * (acceleration_factor - 1))
        endif
        
        if .cycle > 1
            Line width: 1
            Dotted line
            Draw line: .cycleTime, 0, .cycleTime, 3
        endif
        .cycleTime += .cycDur
    endfor
    Solid line
    
    # Draw events
    Line width: 2
    for .evt to .nEvents
        .t = eventTime#[.evt]
        .pat = eventPattern#[.evt]
        .amp = eventAmp#[.evt]
        .dur = eventDur#[.evt]
        
        if .pat = 1
            Colour: .col1$
            .y = 2.2
        else
            Colour: .col2$
            .y = 0.8
        endif
        
        .h = .amp * 0.8
        if .pat = 1
            Paint rectangle: .col1$, .t, .t + .dur, .y - .h/2, .y + .h/2
        else
            Paint rectangle: .col2$, .t, .t + .dur, .y - .h/2, .y + .h/2
        endif
    endfor
    
    # Labels
    Select outer viewport: 0, .leftMargin, 0.6, 1.8
    Colour: .col1$
    Font size: 9
    Text: 0.5, "centre", 0.5, "half", "P1"
    
    Select outer viewport: 0, .leftMargin, 1.8, 3.0
    Colour: .col2$
    Text: 0.5, "centre", 0.5, "half", "P2"
    
    # Time axis
    Select inner viewport: .leftMargin, .rightMargin, 0.7, 2.9
    Axes: 0, .totalDur, 0, 3
    Colour: "Black"
    Marks bottom every: 1, 0.5, "yes", "yes", "no"
    
    # === Panel 2: IOI curve ===
    Select outer viewport: 0, 8, 3.2, 5.0
    Colour: .colGrid$
    Draw inner box
    
    Select inner viewport: .leftMargin, .rightMargin, 3.3, 4.9
    
    # Calculate IOI bounds
    .maxIOI = base_duration_s / min(pattern1_beats, pattern2_beats)
    .minIOI = 0
    .cycleTime = 0
    
    for .cycle to total_cycles
        if exponential_acceleration
            .cycDur = base_duration_s / (acceleration_factor ^ (.cycle - 1))
        else
            .cycDur = base_duration_s / (1 + (.cycle - 1) * (acceleration_factor - 1))
        endif
        .ioi = .cycDur / max(pattern1_beats, pattern2_beats)
        if .ioi < .minIOI or .minIOI = 0
            .minIOI = .ioi
        endif
        .cycleTime += .cycDur
    endfor
    
    Axes: 0, .totalDur, 0, .maxIOI * 1.1
    
    # Draw IOI curves
    .cycleTime = 0
    Line width: 2
    
    for .cycle to total_cycles
        if exponential_acceleration
            .cycDur = base_duration_s / (acceleration_factor ^ (.cycle - 1))
        else
            .cycDur = base_duration_s / (1 + (.cycle - 1) * (acceleration_factor - 1))
        endif
        
        .ioi1 = .cycDur / pattern1_beats
        .ioi2 = .cycDur / pattern2_beats
        
        Colour: .col1$
        Draw line: .cycleTime, .ioi1, .cycleTime + .cycDur, .ioi1
        
        Colour: .col2$
        Draw line: .cycleTime, .ioi2, .cycleTime + .cycDur, .ioi2
        
        .cycleTime += .cycDur
    endfor
    
    Select outer viewport: 0, .leftMargin, 3.2, 5.0
    Colour: "Black"
    Font size: 9
    Text: 0.5, "centre", 0.5, "half", "IOI (s)"
    
    Select inner viewport: .leftMargin, .rightMargin, 3.3, 4.9
    Axes: 0, .totalDur, 0, .maxIOI * 1.1
    Colour: "Black"
    Marks left: 3, "yes", "yes", "no"
    Marks bottom every: 1, 0.5, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"
    
    # === Footer (summary panel) ===
    if exponential_acceleration
        .accelType$ = "(exp)"
    else
        .accelType$ = "(lin)"
    endif
    .paramText$ = "Accel: " + fixed$(acceleration_factor, 2) + "x " + .accelType$ + " | Morph: " + morph_type$ + " | Waveform: " + waveform$
    Select outer viewport: 0, 8, 6.4, 7
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Draw inner box
    Font size: 8
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", .paramText$
    
    # Reset
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc