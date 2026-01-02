# ============================================================
# Praat AudioTools - Random_Walk_Melody.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Corrected
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Generates melodies using a bounded random walk on scale degrees.
#   Each note has a probability of stepping to a neighboring pitch,
#   creating melodic contours with natural continuity.
#
#   Supports just intonation (5-limit Ptolemaic) or equal temperament.
#
# Usage:
#   Run this script and select a preset or customize parameters.
#
# Changelog v0.2:
#   - Chunked synthesis (prevents formula explosion)
#   - Added presets and scale options
#   - Added visualization (pitch contour + spectrogram)
#   - Modern syntax
# ============================================================

form Random Walk Melody
    comment === Preset ===
    optionmenu Preset 1
        option Custom
        option Slow Wandering
        option Quick Steps
        option Wide Leaps
        option Sticky Notes
        option Pentatonic Float
        option Chromatic Drift
    
    comment === Timing ===
    positive Duration_s 15.0
    integer Sample_rate_Hz 44100
    positive Note_duration_s 0.5
    
    comment === Pitch ===
    positive Base_frequency_Hz 220
    comment Scale degrees = notes in scale
    integer Scale_degrees 7
    
    comment === Walk Behavior ===
    comment Step probability = chance of moving each note
    real Step_probability 0.7
    comment Max step size = max interval jump
    integer Max_step_size 2
    
    comment === Tuning ===
    optionmenu Tuning 1
        option Just Intonation (5-limit)
        option Equal Temperament (12-TET)
        option Pentatonic
        option Whole Tone
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
preset_name$ = "Custom"

if preset = 2
    # Slow Wandering
    duration_s = 20.0
    note_duration_s = 0.8
    base_frequency_Hz = 180
    step_probability = 0.5
    max_step_size = 1
    tuning = 1
    preset_name$ = "SlowWandering"
elsif preset = 3
    # Quick Steps
    duration_s = 12.0
    note_duration_s = 0.2
    base_frequency_Hz = 330
    step_probability = 0.9
    max_step_size = 1
    tuning = 1
    preset_name$ = "QuickSteps"
elsif preset = 4
    # Wide Leaps
    duration_s = 15.0
    note_duration_s = 0.4
    base_frequency_Hz = 220
    step_probability = 0.8
    max_step_size = 3
    tuning = 2
    preset_name$ = "WideLeaps"
elsif preset = 5
    # Sticky Notes
    duration_s = 15.0
    note_duration_s = 0.6
    base_frequency_Hz = 196
    step_probability = 0.3
    max_step_size = 1
    tuning = 1
    preset_name$ = "StickyNotes"
elsif preset = 6
    # Pentatonic Float
    duration_s = 18.0
    note_duration_s = 0.5
    base_frequency_Hz = 261.63
    step_probability = 0.7
    max_step_size = 2
    scale_degrees = 5
    tuning = 3
    preset_name$ = "PentatonicFloat"
elsif preset = 7
    # Chromatic Drift
    duration_s = 10.0
    note_duration_s = 0.25
    base_frequency_Hz = 440
    step_probability = 0.85
    max_step_size = 1
    scale_degrees = 12
    tuning = 2
    preset_name$ = "ChromaticDrift"
endif

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi
notesPerChunk = 15

# === Define Scale Ratios ===

# Just Intonation (Ptolemaic/5-limit)
jiRatio[1] = 1.0
jiRatio[2] = 9/8
jiRatio[3] = 5/4
jiRatio[4] = 4/3
jiRatio[5] = 3/2
jiRatio[6] = 5/3
jiRatio[7] = 15/8
jiRatio[8] = 2.0

# Equal Temperament (12-TET major scale)
etRatio[1] = 1.0
etRatio[2] = 2^(2/12)
etRatio[3] = 2^(4/12)
etRatio[4] = 2^(5/12)
etRatio[5] = 2^(7/12)
etRatio[6] = 2^(9/12)
etRatio[7] = 2^(11/12)
etRatio[8] = 2.0
etRatio[9] = 2^(14/12)
etRatio[10] = 2^(16/12)
etRatio[11] = 2^(17/12)
etRatio[12] = 2^(19/12)

# Pentatonic (major pentatonic)
pentRatio[1] = 1.0
pentRatio[2] = 9/8
pentRatio[3] = 5/4
pentRatio[4] = 3/2
pentRatio[5] = 5/3
pentRatio[6] = 2.0

# Whole Tone
wtRatio[1] = 1.0
wtRatio[2] = 2^(2/12)
wtRatio[3] = 2^(4/12)
wtRatio[4] = 2^(6/12)
wtRatio[5] = 2^(8/12)
wtRatio[6] = 2^(10/12)
wtRatio[7] = 2.0

# Select tuning
tuning_name$ = "JustIntonation"
if tuning = 2
    tuning_name$ = "EqualTemperament"
elsif tuning = 3
    tuning_name$ = "Pentatonic"
    if scale_degrees > 5
        scale_degrees = 5
    endif
elsif tuning = 4
    tuning_name$ = "WholeTone"
    if scale_degrees > 6
        scale_degrees = 6
    endif
endif

# === Info ===
writeInfoLine: "=== Random Walk Melody ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Duration: ", duration_s, " s"
appendInfoLine: "Note duration: ", note_duration_s, " s"
appendInfoLine: "Base frequency: ", base_frequency_Hz, " Hz"
appendInfoLine: "Scale degrees: ", scale_degrees
appendInfoLine: "Step probability: ", step_probability
appendInfoLine: "Max step: +/-", max_step_size
appendInfoLine: "Tuning: ", tuning_name$
appendInfoLine: ""

# === Generate Random Walk ===
appendInfoLine: "Generating random walk..."

totalNotes = floor(duration_s / note_duration_s)
currentDegree = ceiling(scale_degrees / 2)

for n to totalNotes
    noteTime[n] = (n - 1) * note_duration_s
    noteDegree[n] = currentDegree
    
    # Get frequency ratio based on tuning
    if tuning = 1
        noteRatio = jiRatio[currentDegree]
    elsif tuning = 2
        noteRatio = etRatio[currentDegree]
    elsif tuning = 3
        noteRatio = pentRatio[currentDegree]
    else
        noteRatio = wtRatio[currentDegree]
    endif
    
    noteFreq[n] = base_frequency_Hz * noteRatio
    
    # Random walk step
    if randomUniform(0, 1) < step_probability
        step = randomInteger(-max_step_size, max_step_size)
        currentDegree = currentDegree + step
        # Bound to scale
        if currentDegree < 1
            currentDegree = 1
        endif
        if currentDegree > scale_degrees
            currentDegree = scale_degrees
        endif
    endif
endfor

appendInfoLine: "Generated ", totalNotes, " notes"

# === Synthesize with Chunked Approach ===
appendInfoLine: "Synthesizing melody..."

outputSound = Create Sound from formula: "walk_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"

nChunks = ceiling(totalNotes / notesPerChunk)

for chunk to nChunks
    startNote = (chunk - 1) * notesPerChunk + 1
    endNote = min(chunk * notesPerChunk, totalNotes)
    
    chunkFormula$ = ""
    
    for n from startNote to endNote
        t = noteTime[n]
        d = note_duration_s
        if t + d > duration_s
            d = duration_s - t
        endif
        
        if d > 0.01
            t$ = fixed$(t, 6)
            d$ = fixed$(d, 6)
            f$ = fixed$(noteFreq[n], 2)
            
            # Sine with Hann envelope
            term$ = "if x >= " + t$ + " and x < " + t$ + " + " + d$ + " then 0.7 * sin(twoPi * " + f$ + " * x) * (1 - cos(twoPi * (x - " + t$ + ") / " + d$ + ")) / 2 else 0 fi"
            
            if chunkFormula$ = ""
                chunkFormula$ = term$
            else
                chunkFormula$ = chunkFormula$ + " + " + term$
            endif
        endif
    endfor
    
    if chunkFormula$ <> ""
        selectObject: outputSound
        Formula: "self + (" + chunkFormula$ + ")"
    endif
    
    if chunk mod 5 = 0
        appendInfoLine: "  Chunk ", chunk, "/", nChunks
    endif
endfor

# === Fade In/Out ===
selectObject: outputSound
Formula: "if x < 0.05 then self * (x / 0.05) else self fi"
Formula: "if x > duration_s - 0.1 then self * ((duration_s - x) / 0.1) else self fi"

# === Normalize ===
selectObject: outputSound
Scale peak: 0.9
Rename: "random_walk_" + preset_name$

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
    Text: 0.5, "centre", 0.7, "half", "Random Walk Melody — " + preset_name$
    Font size: 10
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.2, "half", tuning_name$ + " | " + string$(totalNotes) + " notes | Step prob: " + fixed$(step_probability, 1)
    
    # === Pitch Contour (Scale Degrees) ===
    Select outer viewport: 0, 7, 0.9, 2.8
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Select inner viewport: 0.5, 6.5, 1.0, 2.7
    Axes: 0, duration_s, 0, scale_degrees + 1
    
    # Draw scale degree lines
    Colour: "{0.85, 0.85, 0.85}"
    for .d to scale_degrees
        Draw line: 0, .d, duration_s, .d
    endfor
    
    # Draw pitch contour
    Colour: "{0.2, 0.5, 0.8}"
    Line width: 2
    for .n from 2 to totalNotes
        Draw line: noteTime[.n - 1], noteDegree[.n - 1], noteTime[.n], noteDegree[.n]
    endfor
    Line width: 1
    
    # Draw note points
    for .n to totalNotes
        Paint circle (mm): "{0.2, 0.5, 0.8}", noteTime[.n], noteDegree[.n], 1.5
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Marks left: scale_degrees, "yes", "yes", "no"
    Marks bottom every: 1, 2, "yes", "yes", "no"
    Text left: "yes", "Scale Degree"
    Text bottom: "yes", "Time (s)"
    
    # === Frequency Contour ===
    Select outer viewport: 0, 7, 3.0, 4.3
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Select inner viewport: 0.5, 6.5, 3.1, 4.2
    
    # Find min/max freq
    .minF = noteFreq[1]
    .maxF = noteFreq[1]
    for .n from 2 to totalNotes
        if noteFreq[.n] < .minF
            .minF = noteFreq[.n]
        endif
        if noteFreq[.n] > .maxF
            .maxF = noteFreq[.n]
        endif
    endfor
    .minF = .minF * 0.9
    .maxF = .maxF * 1.1
    
    Axes: 0, duration_s, .minF, .maxF
    
    Colour: "{0.8, 0.4, 0.2}"
    Line width: 2
    for .n from 2 to totalNotes
        Draw line: noteTime[.n - 1], noteFreq[.n - 1], noteTime[.n], noteFreq[.n]
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Marks left: 4, "yes", "yes", "no"
    Marks bottom every: 1, 2, "yes", "yes", "no"
    Text left: "yes", "Freq (Hz)"
    Text bottom: "yes", "Time (s)"
    
    # === Spectrogram ===
    Select outer viewport: 0, 7, 4.5, 6.0
    Colour: "{0.85, 0.85, 0.85}"
    Draw inner box
    
    Select inner viewport: 0.5, 6.5, 4.6, 5.9
    
    selectObject: outputSound
    Copy: "temp_spec"
    .tempSound = selected("Sound")
    
    .specMax = .maxF * 1.5
    To Spectrogram: 0.03, .specMax, 0.01, 20, "Gaussian"
    .spec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    
    removeObject: .tempSound, .spec
    
    Select inner viewport: 0.5, 6.5, 4.6, 5.9
    Axes: 0, duration_s, 0, .specMax
    
    Colour: "White"
    Marks left: 4, "yes", "yes", "no"
    Marks bottom every: 1, 2, "yes", "yes", "no"
    Font size: 8
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Freq (Hz)"
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc