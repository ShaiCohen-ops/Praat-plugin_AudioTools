# ============================================================
# Praat AudioTools - Rhythmic_LFO_Wah_Wah.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Rhythmic LFO Wah-Wah - tempo-synced bandpass filter sweep.
#   Calculates BPM from selection duration or uses manual input.
#   LFO rate syncs to musical note values (whole, half, quarter,
#   eighth, etc.) with dotted and triplet feel options.
#
# Changelog v0.2:
#   - Added input check
#   - Added presets
#   - Added visualization
#   - Added play option
#   - Use pi constant
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
name$ = selected$("Sound")

selectObject: original
duration = Get total duration
sr = Get sampling frequency

# === Form ===
form Rhythmic LFO Wah-Wah
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Funky Quarter (120 BPM)
        option Slow Half (80 BPM)
        option Fast Eighth (140 BPM)
        option Triplet Groove (100 BPM)
        option Dotted Eighth (110 BPM)
        option Auto-Detect 4 Beats
    
    comment === BPM Calculation ===
    comment Beats in selection (0 = use manual BPM):
    real Beats_in_selection 0
    positive Manual_BPM 120
    
    comment === Rhythm Settings ===
    optionmenu Note_value: 3
        option 1/1 (Whole Note)
        option 1/2 (Half Note)
        option 1/4 (Quarter Note)
        option 1/8 (Eighth Note)
        option 1/16 (Sixteenth Note)
        option 1/32 (Thirty-second Note)
    optionmenu Feel: 1
        option Straight
        option Dotted (1.5x slower)
        option Triplet (33% faster)
        
    comment === Wah Tone ===
    positive Min_cutoff_Hz 400
    positive Max_cutoff_Hz 2500
    positive Bandwidth_Hz 150
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Funky Quarter
    beats_in_selection = 0
    manual_BPM = 120
    note_value = 3
    feel = 1
    min_cutoff_Hz = 400
    max_cutoff_Hz = 2500
    presetName$ = "FunkyQtr"
elsif preset = 3
    # Slow Half
    beats_in_selection = 0
    manual_BPM = 80
    note_value = 2
    feel = 1
    min_cutoff_Hz = 300
    max_cutoff_Hz = 2000
    presetName$ = "SlowHalf"
elsif preset = 4
    # Fast Eighth
    beats_in_selection = 0
    manual_BPM = 140
    note_value = 4
    feel = 1
    min_cutoff_Hz = 500
    max_cutoff_Hz = 3000
    presetName$ = "FastEighth"
elsif preset = 5
    # Triplet Groove
    beats_in_selection = 0
    manual_BPM = 100
    note_value = 3
    feel = 3
    min_cutoff_Hz = 400
    max_cutoff_Hz = 2200
    presetName$ = "Triplet"
elsif preset = 6
    # Dotted Eighth
    beats_in_selection = 0
    manual_BPM = 110
    note_value = 4
    feel = 2
    min_cutoff_Hz = 350
    max_cutoff_Hz = 2800
    presetName$ = "DottedEighth"
elsif preset = 7
    # Auto-Detect 4 Beats
    beats_in_selection = 4
    note_value = 3
    feel = 1
    min_cutoff_Hz = 400
    max_cutoff_Hz = 2500
    presetName$ = "Auto4"
else
    presetName$ = "Custom"
endif

# === Calculate BPM ===
if beats_in_selection > 0
    bpm = (beats_in_selection / duration) * 60
    bpmSource$ = "detected"
else
    bpm = manual_BPM
    bpmSource$ = "manual"
endif

# === Calculate LFO Speed ===
if note_value = 1
    beat_fraction = 4
    noteLabel$ = "1/1"
elsif note_value = 2
    beat_fraction = 2
    noteLabel$ = "1/2"
elsif note_value = 3
    beat_fraction = 1
    noteLabel$ = "1/4"
elsif note_value = 4
    beat_fraction = 0.5
    noteLabel$ = "1/8"
elsif note_value = 5
    beat_fraction = 0.25
    noteLabel$ = "1/16"
elsif note_value = 6
    beat_fraction = 0.125
    noteLabel$ = "1/32"
endif

# Apply feel modifier
if feel = 1
    feelLabel$ = "straight"
elsif feel = 2
    beat_fraction = beat_fraction * 1.5
    feelLabel$ = "dotted"
elsif feel = 3
    beat_fraction = beat_fraction * (2/3)
    feelLabel$ = "triplet"
endif

# Duration of one cycle
cycle_dur = (60 / bpm) * beat_fraction
lfo_freq = 1 / cycle_dur

# === Info ===
writeInfoLine: "=== Rhythmic LFO Wah-Wah ==="
appendInfoLine: "Source: ", name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "BPM: ", fixed$(bpm, 1), " (", bpmSource$, ")"
appendInfoLine: "Note value: ", noteLabel$, " ", feelLabel$
appendInfoLine: "LFO rate: ", fixed$(lfo_freq, 2), " Hz"
appendInfoLine: "Cycle duration: ", fixed$(cycle_dur * 1000, 1), " ms"
appendInfoLine: ""
appendInfoLine: "Filter range: ", min_cutoff_Hz, " - ", max_cutoff_Hz, " Hz"
appendInfoLine: "Bandwidth: ", bandwidth_Hz, " Hz"
appendInfoLine: ""

# === Create FormantGrid ===
appendInfoLine: "Creating LFO wah curve..."

Create FormantGrid: name$ + "_lfo", 0, duration, 1, 550, 600, 50, 50
gridID = selected("FormantGrid")

# Remove default points
Remove formant points between: 1, 0, duration
Remove bandwidth points between: 1, 0, duration

# Generate sine wave curve
time_step = 0.005
n_steps = floor(duration / time_step)

# Store for visualization
maxVizPoints = min(n_steps, 300)
vizTimes# = zero#(maxVizPoints)
vizFreqs# = zero#(maxVizPoints)

for i to n_steps
    t = i * time_step
    
    # LFO oscillator
    oscillator = sin(2 * pi * lfo_freq * t)
    
    # Normalize to 0-1
    norm_val = (1 + oscillator) / 2
    
    # Map to frequency range
    target_freq = min_cutoff_Hz + ((max_cutoff_Hz - min_cutoff_Hz) * norm_val)
    
    # Apply to grid
    selectObject: gridID
    Add formant point: 1, t, target_freq
    Add bandwidth point: 1, t, bandwidth_Hz
    
    # Store for visualization
    vizIdx = floor((i - 1) / n_steps * maxVizPoints) + 1
    if vizIdx >= 1 and vizIdx <= maxVizPoints
        vizTimes#[vizIdx] = t
        vizFreqs#[vizIdx] = target_freq
    endif
endfor

# === Apply Filter ===
appendInfoLine: "Applying wah filter..."

selectObject: original, gridID
result = Filter
Rename: name$ + "_wah_" + presetName$

# Cleanup grid
removeObject: gridID

# Scale
selectObject: result
Scale peak: 0.95

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Rhythmic LFO Wah: " + name$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.6, 7.6, 0.7, 1.4
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.6, 2.5
    Select inner viewport: 0.6, 7.6, 1.7, 2.4
    selectObject: result
    Colour: "{0.7, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Wah"
    Text bottom: "yes", "Time (s)"
    
    # LFO / Filter frequency curve
    Select outer viewport: 0, 8, 2.7, 4.0
    Select inner viewport: 0.6, 7.6, 2.8, 3.9
    
    freqMargin = (max_cutoff_Hz - min_cutoff_Hz) * 0.1
    Axes: 0, duration, min_cutoff_Hz - freqMargin, max_cutoff_Hz + freqMargin
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, duration, min_cutoff_Hz - freqMargin, max_cutoff_Hz + freqMargin
    
    # Draw beat grid
    Colour: "{0.85, 0.85, 0.85}"
    beatDur = 60 / bpm
    beatNum = 0
    t = 0
    while t < duration
        Dotted line
        Draw line: t, min_cutoff_Hz - freqMargin, t, max_cutoff_Hz + freqMargin
        beatNum = beatNum + 1
        t = beatNum * beatDur
    endwhile
    Solid line
    
    # Center line
    centerFreq = (min_cutoff_Hz + max_cutoff_Hz) / 2
    Colour: "{0.8, 0.8, 0.8}"
    Dotted line
    Draw line: 0, centerFreq, duration, centerFreq
    Solid line
    
    # Draw LFO curve
    Colour: "{0.7, 0.5, 0.5}"
    Line width: 1.5
    for v from 2 to maxVizPoints
        if vizTimes#[v] > 0 and vizTimes#[v - 1] > 0
            Draw line: vizTimes#[v - 1], vizFreqs#[v - 1], vizTimes#[v], vizFreqs#[v]
        endif
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Filter (Hz)"
    Text bottom: "yes", "Time (s) - beat grid shown"
    
    # Rhythm info box
    Select outer viewport: 0, 8, 4.2, 5.0
    Select inner viewport: 0.6, 7.6, 4.3, 4.9
    
    Axes: 0, 8, 0, 2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 8, 0, 2
    
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    
    # Note value visual
    if note_value = 1
        noteSymbol$ = "O (whole)"
    elsif note_value = 2
        noteSymbol$ = "d (half)"
    elsif note_value = 3
        noteSymbol$ = "q (quarter)"
    elsif note_value = 4
        noteSymbol$ = "e (eighth)"
    elsif note_value = 5
        noteSymbol$ = "s (16th)"
    else
        noteSymbol$ = "t (32nd)"
    endif
    
    Text: 1, "centre", 1.5, "half", "BPM: " + fixed$(bpm, 0)
    Text: 3, "centre", 1.5, "half", "Note: " + noteLabel$
    Text: 5, "centre", 1.5, "half", "Feel: " + feelLabel$
    Text: 7, "centre", 1.5, "half", "LFO: " + fixed$(lfo_freq, 2) + " Hz"
    
    Text: 2, "centre", 0.5, "half", "(" + bpmSource$ + ")"
    Text: 4, "centre", 0.5, "half", noteSymbol$
    Text: 6, "centre", 0.5, "half", "Cycle: " + fixed$(cycle_dur * 1000, 0) + " ms"
    
    Colour: "Black"
    Draw inner box
    
    # Stats
    Select outer viewport: 0, 8, 5.1, 5.4
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Range: " + fixed$(min_cutoff_Hz, 0) + "-" + fixed$(max_cutoff_Hz, 0) + " Hz | BW: " + fixed$(bandwidth_Hz, 0) + " Hz | Beats in file: ~" + fixed$(duration / beatDur, 1)
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result