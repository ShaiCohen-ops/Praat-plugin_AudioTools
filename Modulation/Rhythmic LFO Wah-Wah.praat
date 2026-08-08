# ============================================================
# Praat AudioTools - Rhythmic_LFO_Wah_Wah.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Tempo-synchronised resonant wah based on a time-varying
#   FormantGrid. The resonant centre follows a sine LFO whose cycle
#   is derived from BPM, musical note value, and straight/dotted/
#   triplet feel. BPM can be entered manually or inferred from a
#   user-declared number of beats spanning the whole selected Sound.
#
#   Filtering uses Sound & FormantGrid: Filter (no scale), so source
#   level relationships are not normalised away. Dry/Wet = 0 is an
#   exact bypass. Safety_peak only attenuates when necessary.
#
# v0.3 changes:
#   - Uses Filter (no scale) instead of the auto-scaling Filter command.
#   - Removes unconditional Scale peak normalization.
#   - Adds exact Dry/Wet bypass and attenuation-only Safety_peak.
#   - Preserves arbitrary channels, sample rate, duration, and start time.
#   - Builds the FormantGrid in the Sound's absolute time domain while
#     calculating LFO phase in local time, making output start-time invariant.
#   - Adds an exact t=0 control point and adaptive LFO control resolution.
#   - Renames misleading Auto-Detect preset to Fit 4 Beats to Sound.
#   - Clarifies dotted/triplet timing and validates frequency limits.
#   - Updates visualization to the AudioTools house text layout.
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Error: Please select exactly one Sound object."
endif

original = selected("Sound")
name$ = selected$("Sound")

selectObject: original
duration = Get total duration
sr = Get sampling frequency
sound_xmin = Get start time
sound_xmax = Get end time
numChannels = Get number of channels

form Rhythmic LFO Wah-Wah
    optionmenu Preset: 1
        option Custom (use settings below)
        option Funky Quarter (120 BPM)
        option Slow Half (80 BPM)
        option Fast Eighth (140 BPM)
        option Triplet Groove (100 BPM)
        option Dotted Eighth (110 BPM)
        option Fit 4 Beats to Sound

    comment --- Tempo ---
    real Beats_in_sound: 0
    comment 0 = use Manual_BPM; positive = beats spanning the whole Sound
    positive Manual_BPM: 120

    comment --- Rhythm ---
    optionmenu Note_value: 3
        option 1/1 (Whole Note)
        option 1/2 (Half Note)
        option 1/4 (Quarter Note)
        option 1/8 (Eighth Note)
        option 1/16 (Sixteenth Note)
        option 1/32 (Thirty-second Note)
    optionmenu Feel: 1
        option Straight
        option Dotted (duration x1.5)
        option Triplet (duration x2/3)

    comment --- Wah tone ---
    positive Min_cutoff_Hz: 400
    positive Max_cutoff_Hz: 2500
    positive Bandwidth_Hz: 150

    comment --- Output ---
    real Dry_wet_percent: 100
    real Safety_peak: 0.99
    boolean Draw_visualization: 1
    boolean Play_result: 1
endform

# ============================================================
# PRESET OVERRIDES
# ============================================================
if preset = 2
    beats_in_sound = 0
    manual_BPM = 120
    note_value = 3
    feel = 1
    min_cutoff_Hz = 400
    max_cutoff_Hz = 2500
    bandwidth_Hz = 150
    presetName$ = "Funky Quarter"
elsif preset = 3
    beats_in_sound = 0
    manual_BPM = 80
    note_value = 2
    feel = 1
    min_cutoff_Hz = 300
    max_cutoff_Hz = 2000
    bandwidth_Hz = 150
    presetName$ = "Slow Half"
elsif preset = 4
    beats_in_sound = 0
    manual_BPM = 140
    note_value = 4
    feel = 1
    min_cutoff_Hz = 500
    max_cutoff_Hz = 3000
    bandwidth_Hz = 150
    presetName$ = "Fast Eighth"
elsif preset = 5
    beats_in_sound = 0
    manual_BPM = 100
    note_value = 3
    feel = 3
    min_cutoff_Hz = 400
    max_cutoff_Hz = 2200
    bandwidth_Hz = 150
    presetName$ = "Triplet Groove"
elsif preset = 6
    beats_in_sound = 0
    manual_BPM = 110
    note_value = 4
    feel = 2
    min_cutoff_Hz = 350
    max_cutoff_Hz = 2800
    bandwidth_Hz = 150
    presetName$ = "Dotted Eighth"
elsif preset = 7
    beats_in_sound = 4
    note_value = 3
    feel = 1
    min_cutoff_Hz = 400
    max_cutoff_Hz = 2500
    bandwidth_Hz = 150
    presetName$ = "Fit 4 Beats"
else
    presetName$ = "Custom"
endif

# ============================================================
# VALIDATION / TEMPO
# ============================================================
if duration <= 0
    exitScript: "Error: Sound has zero duration."
endif

if beats_in_sound > 0
    bpm = 60 * beats_in_sound / duration
    bpmSource$ = "fit " + fixed$(beats_in_sound, 2) + " beats / Sound"
else
    bpm = manual_BPM
    bpmSource$ = "manual"
endif

if bpm <= 0 or bpm > 1200
    exitScript: "Error: Resulting BPM must be > 0 and <= 1200."
endif

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
else
    beat_fraction = 0.125
    noteLabel$ = "1/32"
endif

if feel = 1
    feelLabel$ = "straight"
elsif feel = 2
    beat_fraction = beat_fraction * 1.5
    feelLabel$ = "dotted"
else
    beat_fraction = beat_fraction * (2/3)
    feelLabel$ = "triplet"
endif

cycle_dur = (60 / bpm) * beat_fraction
lfo_freq = 1 / cycle_dur

# Defensible filter bounds. A margin below Nyquist avoids a resonant centre
# whose upper skirt is mostly outside the sampled band.
nyquist = sr / 2
maxAllowedCutoff = 0.45 * sr
min_cutoff_Hz = max(20, min(min_cutoff_Hz, maxAllowedCutoff))
max_cutoff_Hz = max(20, min(max_cutoff_Hz, maxAllowedCutoff))
if min_cutoff_Hz > max_cutoff_Hz
    swap = min_cutoff_Hz
    min_cutoff_Hz = max_cutoff_Hz
    max_cutoff_Hz = swap
endif
bandwidth_Hz = max(1, min(bandwidth_Hz, 0.45 * sr))
dry_wet_percent = min(100, max(0, dry_wet_percent))
safety_peak = min(1, max(0, safety_peak))

writeInfoLine: "=== Rhythmic LFO Wah-Wah v0.3 ==="
appendInfoLine: "Source: ", name$, " (", fixed$(duration, 3), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Channels: ", numChannels, " | Sample rate: ", fixed$(sr, 0), " Hz"
appendInfoLine: "BPM: ", fixed$(bpm, 3), " (", bpmSource$, ")"
appendInfoLine: "Rhythm: ", noteLabel$, " ", feelLabel$, " | LFO: ", fixed$(lfo_freq, 4), " Hz"
appendInfoLine: "Cycle: ", fixed$(1000 * cycle_dur, 3), " ms"
appendInfoLine: "Resonance range: ", fixed$(min_cutoff_Hz, 1), " - ", fixed$(max_cutoff_Hz, 1), " Hz | BW: ", fixed$(bandwidth_Hz, 1), " Hz"
appendInfoLine: "Dry/Wet: ", fixed$(dry_wet_percent, 1), "%"

# ============================================================
# PROCESSING
# ============================================================
if dry_wet_percent <= 0
    selectObject: original
    result = Copy: name$ + "_wah_" + presetName$
    controlPoints = 0
else
    # At least 32 control points per LFO cycle, while retaining the original
    # 5 ms ceiling at slower rates. This prevents coarse high-rate staircasing.
    controlStep = min(0.005, cycle_dur / 32)
    controlStep = max(1 / sr, controlStep)
    n_steps = ceiling(duration / controlStep)
    controlPoints = n_steps + 1

    centerFreq = 0.5 * (min_cutoff_Hz + max_cutoff_Hz)
    selectObject: original
    Create FormantGrid: name$ + "_lfo", sound_xmin, sound_xmax, 1, centerFreq, 600, bandwidth_Hz, 50
    gridID = selected("FormantGrid")
    Remove formant points between: 1, sound_xmin, sound_xmax
    Remove bandwidth points between: 1, sound_xmin, sound_xmax

    for i from 0 to n_steps
        localT = min(duration, i * controlStep)
        absT = sound_xmin + localT
        oscillator = sin(2 * pi * lfo_freq * localT)
        target_freq = min_cutoff_Hz + (max_cutoff_Hz - min_cutoff_Hz) * 0.5 * (1 + oscillator)
        selectObject: gridID
        Add formant point: 1, absT, target_freq
        Add bandwidth point: 1, absT, bandwidth_Hz
    endfor

    selectObject: original, gridID
    result = Filter (no scale)
    Rename: name$ + "_wah_" + presetName$
    removeObject: gridID

    # Praat's one-formant recursion is an all-pole resonator whose raw centre
    # gain can be hundreds of times unity. Apply the exact steady-state
    # centre-frequency normalization of that resonator, time-varying with the
    # same LFO. This is filter calibration, not peak normalization.
    resonanceR = exp(-pi * bandwidth_Hz / sr)
    globalResR = resonanceR
    globalMinF = min_cutoff_Hz
    globalRangeF = max_cutoff_Hz - min_cutoff_Hz
    globalLfoF = lfo_freq
    globalSr = sr
    globalXmin = sound_xmin

    selectObject: original
    Extract one channel: 1
    gainControl = selected("Sound")
    Rename: "wah_center_gain"
    Formula: "(1-'globalResR') * sqrt(1 - 2*'globalResR'*cos(4*pi*('globalMinF' + 0.5*'globalRangeF'*(1+sin(2*pi*'globalLfoF'*(x-'globalXmin'))))/'globalSr') + 'globalResR'^2)"

    globalGainControl = gainControl
    selectObject: result
    Formula: "self * object ['globalGainControl', 1, col]"
    removeObject: gainControl

    if dry_wet_percent < 100
        wet = dry_wet_percent / 100
        dry = 1 - wet
        globalOriginal = original
        selectObject: result
        Formula: "'wet' * self + 'dry' * object ['globalOriginal', row, col]"
    endif
endif

# Attenuation-only safety. Exact dry bypass is never changed by Safety_peak.
selectObject: result
peakBeforeSafety = Get absolute extremum: 0, 0, "None"
if dry_wet_percent > 0 and safety_peak > 0 and peakBeforeSafety > safety_peak
    Scale peak: safety_peak
endif
outputPeak = Get absolute extremum: 0, 0, "None"

appendInfoLine: "Control points: ", controlPoints
appendInfoLine: "Peak before safety: ", fixed$(peakBeforeSafety, 6)
appendInfoLine: "Output peak: ", fixed$(outputPeak, 6)
if safety_peak > 0
    appendInfoLine: "Safety ceiling: ", fixed$(safety_peak, 3)
else
    appendInfoLine: "Safety: disabled"
endif
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# ============================================================
# VISUALIZATION - AudioTools house text layout
# ============================================================
if draw_visualization
    if safety_peak > 0
        safeStr$ = fixed$(safety_peak, 2)
    else
        safeStr$ = "off"
    endif

    Erase all
    Select outer viewport: 0, 8, 0, 8
    Black
    Plain line

    # ---- TITLE ----
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Rhythmic LFO Wah-Wah##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half", name$ + "  |  " + presetName$ + "  |  " + noteLabel$ + " " + feelLabel$

    # ---- INPUT ----
    Select outer viewport: 0, 4.2, 0.75, 2.30
    Select inner viewport: 0.55, 4.00, 0.95, 2.18
    selectObject: original
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Input"
    Font size: 6
    Text left: "yes", "Amp"

    # ---- OUTPUT ----
    Select outer viewport: 4.2, 8, 0.75, 2.30
    Select inner viewport: 4.55, 7.75, 0.95, 2.18
    selectObject: result
    Colour: "{0.25, 0.45, 0.80}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Output"
    Font size: 6
    Text left: "yes", "Amp"

    # ---- LFO / RESONANCE TRAJECTORY ----
    Select outer viewport: 0, 8, 2.40, 4.55
    Select inner viewport: 0.55, 7.75, 2.62, 4.38
    freqRange = max_cutoff_Hz - min_cutoff_Hz
    freqMargin = max(10, 0.08 * max(1, freqRange))
    Axes: 0, duration, min_cutoff_Hz - freqMargin, max_cutoff_Hz + freqMargin
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, min_cutoff_Hz - freqMargin, max_cutoff_Hz + freqMargin

    # Beat grid, limited to avoid extremely dense graphics.
    beatDur = 60 / bpm
    if duration / beatDur <= 80
        Colour: "{0.86, 0.86, 0.86}"
        Dotted line
        beatIndex = 0
        beatT = 0
        while beatT <= duration
            Draw line: beatT, min_cutoff_Hz - freqMargin, beatT, max_cutoff_Hz + freqMargin
            beatIndex = beatIndex + 1
            beatT = beatIndex * beatDur
        endwhile
        Solid line
    endif

    Colour: "{0.48, 0.36, 0.72}"
    Line width: 1.5
    vizPoints = 400
    for v from 2 to vizPoints
        t1 = (v - 2) / (vizPoints - 1) * duration
        t2 = (v - 1) / (vizPoints - 1) * duration
        f1 = min_cutoff_Hz + freqRange * 0.5 * (1 + sin(2*pi*lfo_freq*t1))
        f2 = min_cutoff_Hz + freqRange * 0.5 * (1 + sin(2*pi*lfo_freq*t2))
        Draw line: t1, f1, t2, f2
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Resonance trajectory"
    Font size: 6
    Text left: "yes", "Hz"
    Text bottom: "yes", "Local time (s)"

    # ---- SUMMARY ----
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.55, 7.75, 4.75, 5.48
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 7
    Text: 0.02, "left", 0.78, "half", "##Summary##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.48, "half", "BPM: " + fixed$(bpm, 2) + " (" + bpmSource$ + ")  |  note: " + noteLabel$ + " " + feelLabel$ + "  |  LFO: " + fixed$(lfo_freq, 3) + " Hz  |  cycle: " + fixed$(1000*cycle_dur, 1) + " ms"
    Text: 0.02, "left", 0.20, "half", "Range: " + fixed$(min_cutoff_Hz, 0) + "-" + fixed$(max_cutoff_Hz, 0) + " Hz  |  BW: " + fixed$(bandwidth_Hz, 0) + " Hz  |  Wet: " + fixed$(dry_wet_percent, 0) + "%  |  safety: " + safeStr$ + "  |  " + fixed$(duration, 2) + " s / " + fixed$(sr, 0) + " Hz / " + string$(numChannels) + " ch"

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

selectObject: result
if play_result
    Play
endif
selectObject: result
