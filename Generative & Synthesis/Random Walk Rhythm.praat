# ============================================================
# Praat AudioTools - Random_Walk_Rhythm.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Corrected
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Generates rhythmic patterns using a random walk on frequency.
#   Unlike Random Walk Melody (discrete scale degrees), this uses
#   continuous frequency steps and percussive decay envelopes.
#
#   Features four spatial modes: mono, stereo ping-pong,
#   rotating panorama, and binaural rhythm.
#
# Usage:
#   Run this script and select a preset or customize parameters.
#
# Changelog v0.2:
#   - Chunked synthesis (prevents formula explosion)
#   - Fixed Filter object tracking
#   - Added visualization
#   - Modern syntax
# ============================================================

form Random Walk Rhythm
    comment === Preset ===
    optionmenu Preset 1
        option Custom
        option Gentle Bounce
        option Chaotic Dance
        option Steady Climb
        option Falling Steps
        option Pulsing Heart
        option Nervous Ticks
        option Ocean Waves
        option Machine Pulse
    
    comment === Timing ===
    positive Duration_s 6.0
    integer Sample_rate_Hz 44100
    positive Tempo_bpm 120
    integer Steps_per_beat 4
    
    comment === Frequency Walk ===
    positive Base_frequency_Hz 180
    positive Frequency_step_Hz 50
    
    comment === Walk Probabilities ===
    real Probability_up 0.4
    real Probability_down 0.4
    
    comment === Spatialization ===
    optionmenu Spatial_mode 1
        option Mono
        option Stereo Ping-Pong
        option Rotating Walk
        option Binaural Rhythm
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
preset_name$ = "Custom"

if preset = 2
    # Gentle Bounce
    tempo_bpm = 90
    steps_per_beat = 2
    base_frequency_Hz = 150
    frequency_step_Hz = 30
    probability_up = 0.5
    probability_down = 0.3
    preset_name$ = "GentleBounce"
elsif preset = 3
    # Chaotic Dance
    tempo_bpm = 160
    steps_per_beat = 8
    base_frequency_Hz = 200
    frequency_step_Hz = 80
    probability_up = 0.4
    probability_down = 0.4
    preset_name$ = "ChaoticDance"
elsif preset = 4
    # Steady Climb
    tempo_bpm = 100
    steps_per_beat = 4
    base_frequency_Hz = 120
    frequency_step_Hz = 40
    probability_up = 0.6
    probability_down = 0.2
    preset_name$ = "SteadyClimb"
elsif preset = 5
    # Falling Steps
    tempo_bpm = 80
    steps_per_beat = 4
    base_frequency_Hz = 200
    frequency_step_Hz = 60
    probability_up = 0.3
    probability_down = 0.5
    preset_name$ = "FallingSteps"
elsif preset = 6
    # Pulsing Heart
    tempo_bpm = 60
    steps_per_beat = 2
    base_frequency_Hz = 100
    frequency_step_Hz = 20
    probability_up = 0.4
    probability_down = 0.4
    preset_name$ = "PulsingHeart"
elsif preset = 7
    # Nervous Ticks
    tempo_bpm = 140
    steps_per_beat = 16
    base_frequency_Hz = 180
    frequency_step_Hz = 100
    probability_up = 0.45
    probability_down = 0.45
    preset_name$ = "NervousTicks"
elsif preset = 8
    # Ocean Waves
    tempo_bpm = 70
    steps_per_beat = 3
    base_frequency_Hz = 130
    frequency_step_Hz = 25
    probability_up = 0.5
    probability_down = 0.3
    preset_name$ = "OceanWaves"
elsif preset = 9
    # Machine Pulse
    tempo_bpm = 110
    steps_per_beat = 4
    base_frequency_Hz = 160
    frequency_step_Hz = 35
    probability_up = 0.4
    probability_down = 0.4
    preset_name$ = "MachinePulse"
endif

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi
stepsPerChunk = 20

# === Calculate Timing ===
beatsPerSecond = tempo_bpm / 60
beatDuration = 1 / beatsPerSecond
stepDuration = beatDuration / steps_per_beat
totalSteps = floor(duration_s / stepDuration)
eventDuration = stepDuration * 0.8

# Spatial mode names
if spatial_mode = 1
    spatial_name$ = "Mono"
elsif spatial_mode = 2
    spatial_name$ = "PingPong"
elsif spatial_mode = 3
    spatial_name$ = "Rotating"
else
    spatial_name$ = "Binaural"
endif

# === Info ===
writeInfoLine: "=== Random Walk Rhythm ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Duration: ", duration_s, " s"
appendInfoLine: "Tempo: ", tempo_bpm, " BPM"
appendInfoLine: "Steps per beat: ", steps_per_beat
appendInfoLine: "Total steps: ", totalSteps
appendInfoLine: "Base freq: ", base_frequency_Hz, " Hz"
appendInfoLine: "Freq step: ", frequency_step_Hz, " Hz"
appendInfoLine: "P(up): ", probability_up, ", P(down): ", probability_down
appendInfoLine: "Spatial: ", spatial_name$
appendInfoLine: ""

# === Generate Random Walk ===
appendInfoLine: "Generating frequency walk..."

currentFreq = base_frequency_Hz

for st to totalSteps
    stepTime[st] = (st - 1) * stepDuration
    stepFreq[st] = currentFreq
    
    # Random walk step
    r = randomUniform(0, 1)
    if r < probability_up
        currentFreq = currentFreq + frequency_step_Hz
    elsif r < probability_up + probability_down
        currentFreq = currentFreq - frequency_step_Hz
    endif
    
    # Bound frequency
    currentFreq = max(80, min(1500, currentFreq))
endfor

appendInfoLine: "Generated ", totalSteps, " steps"

# === Synthesize with Chunked Approach ===
appendInfoLine: "Synthesizing rhythm..."

monoSound = Create Sound from formula: "mono_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"

nChunks = ceiling(totalSteps / stepsPerChunk)

for chunk to nChunks
    startStep = (chunk - 1) * stepsPerChunk + 1
    endStep = min(chunk * stepsPerChunk, totalSteps)
    
    chunkFormula$ = ""
    
    for st from startStep to endStep
        t = stepTime[st]
        d = eventDuration
        if t + d > duration_s
            d = duration_s - t
        endif
        
        if d > 0.001
            t$ = fixed$(t, 6)
            d$ = fixed$(d, 6)
            f$ = fixed$(stepFreq[st], 2)
            
            # Percussive: sine with exponential decay
            term$ = "if x >= " + t$ + " and x < " + t$ + " + " + d$ + " then 0.8 * sin(twoPi * " + f$ + " * x) * exp(-15 * (x - " + t$ + ") / " + d$ + ") else 0 fi"
            
            if chunkFormula$ = ""
                chunkFormula$ = term$
            else
                chunkFormula$ = chunkFormula$ + " + " + term$
            endif
        endif
    endfor
    
    if chunkFormula$ <> ""
        selectObject: monoSound
        Formula: "self + (" + chunkFormula$ + ")"
    endif
    
    if chunk mod 5 = 0
        appendInfoLine: "  Chunk ", chunk, "/", nChunks
    endif
endfor

# === Apply Spatial Mode ===
appendInfoLine: ""
appendInfoLine: "Applying spatial mode: ", spatial_name$

if spatial_mode = 1
    # Mono - just rename
    selectObject: monoSound
    outputSound = monoSound
    Rename: "walk_rhythm_" + preset_name$

elsif spatial_mode = 2
    # Stereo Ping-Pong (different filtering per channel)
    selectObject: monoSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * 0.9"
    Filter (pass Hann band): 0, 3000, 100
    leftFiltered = selected("Sound")
    removeObject: leftSound
    leftSound = leftFiltered
    
    selectObject: monoSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * 0.9"
    Filter (pass Hann band): 200, 5000, 100
    rightFiltered = selected("Sound")
    removeObject: rightSound
    rightSound = rightFiltered
    
    selectObject: leftSound
    plusObject: rightSound
    outputSound = Combine to stereo
    Rename: "walk_rhythm_" + preset_name$ + "_pingpong"
    
    removeObject: leftSound, rightSound, monoSound

elsif spatial_mode = 3
    # Rotating Walk (amplitude panning)
    rotationRate = tempo_bpm / 120
    rotRate$ = fixed$(rotationRate, 3)
    
    selectObject: monoSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * (0.5 + 0.4 * cos(twoPi * " + rotRate$ + " * x))"
    
    selectObject: monoSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * (0.5 + 0.4 * sin(twoPi * " + rotRate$ + " * x))"
    
    selectObject: leftSound
    plusObject: rightSound
    outputSound = Combine to stereo
    Rename: "walk_rhythm_" + preset_name$ + "_rotating"
    
    removeObject: leftSound, rightSound, monoSound

else
    # Binaural Rhythm (different filtering + slow modulation)
    selectObject: monoSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Filter (pass Hann band): 80, 2500, 80
    leftFiltered = selected("Sound")
    Formula: "self * (0.8 + 0.1 * sin(twoPi * 0.3 * x))"
    removeObject: leftSound
    leftSound = leftFiltered
    
    selectObject: monoSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Filter (pass Hann band): 120, 4000, 80
    rightFiltered = selected("Sound")
    Formula: "self * (0.7 + 0.2 * cos(twoPi * 0.4 * x))"
    removeObject: rightSound
    rightSound = rightFiltered
    
    selectObject: leftSound
    plusObject: rightSound
    outputSound = Combine to stereo
    Rename: "walk_rhythm_" + preset_name$ + "_binaural"
    
    removeObject: leftSound, rightSound, monoSound
endif

# === Fade In/Out ===
selectObject: outputSound
Formula: "if x < 0.02 then self * (x / 0.02) else self fi"
Formula: "if x > duration_s - 0.05 then self * ((duration_s - x) / 0.05) else self fi"

# === Normalize ===
selectObject: outputSound
Scale peak: 0.9

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
# Procedure: drawVisualization
# ==============================================================================
procedure drawVisualization
    
    Erase all
    
    # === Title ===
    Select outer viewport: 0, 7, 0.2, 0.7
    Select inner viewport: 0, 7, 0.2, 0.7
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.7, "half", "Random Walk Rhythm — " + preset_name$
    Font size: 10
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.2, "half", string$(tempo_bpm) + " BPM | " + string$(totalSteps) + " steps | " + spatial_name$
    
    # === Frequency Walk ===
    Select outer viewport: 0, 7, 0.9, 2.8
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Select inner viewport: 0.5, 6.5, 1.0, 2.7
    
    # Find min/max freq
    .minF = stepFreq[1]
    .maxF = stepFreq[1]
    for .st from 2 to totalSteps
        if stepFreq[.st] < .minF
            .minF = stepFreq[.st]
        endif
        if stepFreq[.st] > .maxF
            .maxF = stepFreq[.st]
        endif
    endfor
    .minF = .minF - 20
    .maxF = .maxF + 20
    
    Axes: 0, duration_s, .minF, .maxF
    
    # Draw base frequency line
    Colour: "{0.8, 0.8, 0.8}"
    Dotted line
    Draw line: 0, base_frequency_Hz, duration_s, base_frequency_Hz
    Solid line
    
    # Draw frequency contour as steps
    Colour: "{0.2, 0.5, 0.8}"
    Line width: 2
    for .st to totalSteps
        .t1 = stepTime[.st]
        .t2 = .t1 + stepDuration
        if .t2 > duration_s
            .t2 = duration_s
        endif
        Draw line: .t1, stepFreq[.st], .t2, stepFreq[.st]
        if .st < totalSteps
            Draw line: .t2, stepFreq[.st], .t2, stepFreq[.st + 1]
        endif
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Marks left: 5, "yes", "yes", "no"
    Marks bottom every: 1, 1, "yes", "yes", "no"
    Text left: "yes", "Freq (Hz)"
    Text bottom: "yes", "Time (s)"
    
    # === Waveform ===
    Select outer viewport: 0, 7, 3.0, 4.2
    selectObject: outputSound
    .nCh = Get number of channels
    if .nCh > 1
        Extract one channel: 1
        .tempWave = selected("Sound")
        Draw: 0, 0, 0, 0, "yes", "curve"
        removeObject: .tempWave
    else
        Draw: 0, 0, 0, 0, "yes", "curve"
    endif
    Draw inner box
    Font size: 8
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Amp"
    
    # === Spectrogram ===
    Select outer viewport: 0, 7, 4.4, 6.0
    Colour: "{0.85, 0.85, 0.85}"
    Draw inner box
    
    Select inner viewport: 0.5, 6.5, 4.5, 5.9
    
    selectObject: outputSound
    if .nCh > 1
        Extract one channel: 1
        .tempSpec = selected("Sound")
    else
        Copy: "temp_spec"
        .tempSpec = selected("Sound")
    endif
    
    .specMax = .maxF * 2
    selectObject: .tempSpec
    To Spectrogram: 0.02, .specMax, 0.005, 20, "Gaussian"
    .spec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    
    removeObject: .tempSpec, .spec
    
    Select inner viewport: 0.5, 6.5, 4.5, 5.9
    Axes: 0, duration_s, 0, .specMax
    
    Colour: "White"
    Marks left: 4, "yes", "yes", "no"
    Marks bottom every: 1, 1, "yes", "yes", "no"
    Font size: 8
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Freq (Hz)"
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc