# ============================================================
# Praat AudioTools - Pitch_Correction.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Pitch Correction (Auto-Tune) - quantizes pitch to musical
#   scales. Supports major, minor, pentatonic, and modal scales.
#   Adjustable correction strength from natural to hard auto-tune.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.3:
#
#   TIER 1 (Praat polish, no audio change):
#     - Dropped 5 decorative `comment === ... ===` form rows
#       (Preset / Musical Key / Correction / Analysis / Output).
#       Kept the "Select a Sound object first" instruction.
#       Form: 13 rows -> 8 rows.
#     - Added colons to all 3 optionmenus (`Preset:`,
#       `Root_Note:`, `Scale_Type:`).
#     - Replaced unicode `->` arrow with plain `->` in the
#       title text (per the suite gotcha library, non-ASCII
#       glyphs in Praat's Text() are unpredictable across
#       platforms).
#     - Output filename: `<name>_<rootName><scaleName>` ->
#       `<name>_<rootName><scaleName>_<preset>` so multiple
#       correction passes don't silently overwrite.
#     - Consolidated duplicate string vector: v0.2 defined
#       `rootNames$#` (line 109) and `noteNames$#` (line 418)
#       with identical content. Now just one vector reused.
#     - Visualization rewritten with suite styling but a custom
#       layout that gives the pitch-correction panel (this
#       tool's signature visualization) the largest area:
#         Title bar (suite light) + metadata subtitle
#         Pitch correction with scale grid  (full width, BIG)
#         Original waveform  (left half, headline)
#         Result waveform    (right half, headline, sharing
#                             same x-axis with original)
#         Scale pattern (chromatic row showing scale highlights)
#         Light-grey 3-line summary bar (suite standard)
#       The signature pitch panel is in the headline position
#       rather than the waveforms because for this tool the
#       interesting visual change is the pitch trajectory, not
#       the envelope (PSOLA largely preserves envelope).
#
#   TIER 2 (visualization bug fixes, no audio change):
#     - FIXED: legend invisible. v0.2 lines 405-410 drew
#       "Original" and "Corrected" legend labels with Text x=0.85
#       and x=0.92 -- but the axes at that point were still
#       `0, duration, minP, maxP` from the pitch grid. So
#       0.85 meant 0.85 SECONDS (left edge of plot) and 1.05
#       meant 1.05 HZ (far below the plot, since minP is
#       typically ~75 Hz). The legend never rendered anywhere
#       visible. v0.3 embeds the legend in the pitch panel's
#       title via Text top, eliminating the broken inline
#       legend entirely.
#     - FIXED: stats text cramped on left. v0.2 lines 442-445
#       did `Select outer viewport: 0, 8, 5.7, 6.0` but never
#       set fresh `Axes:` -- so it inherited `0, 12, 0, 1` from
#       the scale pattern panel, putting `Text: 0.5, ...` at
#       x = 0.5/12 of the width (left edge) instead of centered.
#       v0.3 replaces this with the suite-standard light-grey
#       Panel E that sets `Axes: 0, 1, 0, 1` explicitly.
#
#   Audio output is bit-identical to v0.2.
#
# Changelog v0.2:
#   - Fixed comparison operators
#   - Modern syntax
#   - Added visualization with scale grid
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
name$ = selected$("Sound")

selectObject: original
duration = Get total duration
fs = Get sampling frequency

# === Form ===
form Pitch Correction v0.3
    comment Select a Sound object first
    optionmenu Preset: 1
        option Custom
        option Natural Correction
        option Hard Auto-Tune
        option Robot / Monotone
    optionmenu Root_Note: 1
        option C
        option C# / Db
        option D
        option D# / Eb
        option E
        option F
        option F# / Gb
        option G
        option G# / Ab
        option A
        option A# / Bb
        option B
    optionmenu Scale_Type: 2
        option Chromatic (All notes)
        option Major (Ionian)
        option Minor (Natural)
        option Minor (Harmonic)
        option Pentatonic Major
        option Pentatonic Minor
        option Dorian
        option Phrygian
        option Lydian
        option Mixolydian
    integer Transpose_semitones 0
    positive Strength_percent 100
    positive Pitch_time_step 0.01
    positive Min_pitch 75
    positive Max_pitch 600
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
strength = strength_percent
smooth_amount = 0

if preset = 2
    # Natural
    strength = 60
    smooth_amount = 2.0
    presetName$ = "Natural"
elsif preset = 3
    # Hard Auto-Tune
    strength = 100
    smooth_amount = 0
    presetName$ = "Hard"
elsif preset = 4
    # Robot
    strength = 100
    smooth_amount = 10.0
    presetName$ = "Robot"
else
    presetName$ = "Custom"
endif

# === Get Scale/Root Names ===
# v0.3: single vector reused for both root display and chromatic
# scale-pattern row (v0.2 had `rootNames$#` and `noteNames$#`
# defined separately with identical content).
noteNames$# = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
rootName$ = noteNames$#[root_Note]

scaleNames$# = {"Chromatic", "Major", "Minor", "Harm Min", "Pent Maj", "Pent Min", "Dorian", "Phrygian", "Lydian", "Mixolydian"}
scaleName$ = scaleNames$#[scale_Type]

# === Define Scale Patterns ===
# Patterns: semitones 0-11, "1"=allowed, "0"=skip
pat$ = "111111111111"

if scale_Type = 2
    # Major (W W H W W W H) -> 0 2 4 5 7 9 11
    pat$ = "101011010101"
elsif scale_Type = 3
    # Minor Natural -> 0 2 3 5 7 8 10
    pat$ = "101101011010"
elsif scale_Type = 4
    # Minor Harmonic -> 0 2 3 5 7 8 11
    pat$ = "101101011001"
elsif scale_Type = 5
    # Pentatonic Major -> 0 2 4 7 9
    pat$ = "101010010100"
elsif scale_Type = 6
    # Pentatonic Minor -> 0 3 5 7 10
    pat$ = "100101010010"
elsif scale_Type = 7
    # Dorian -> 0 2 3 5 7 9 10
    pat$ = "101101010110"
elsif scale_Type = 8
    # Phrygian -> 0 1 3 5 7 8 10
    pat$ = "110101011010"
elsif scale_Type = 9
    # Lydian -> 0 2 4 6 7 9 11
    pat$ = "101010110101"
elsif scale_Type = 10
    # Mixolydian -> 0 2 4 5 7 9 10
    pat$ = "101011010110"
endif

root_idx = root_Note - 1

# === Info ===
writeInfoLine: "=== Pitch Correction v0.3 ==="
appendInfoLine: "Source: ", name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Key: ", rootName$, " ", scaleName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Strength: ", strength, "%"
if smooth_amount > 0
    appendInfoLine: "Smoothing: ", smooth_amount, " Hz"
endif
if transpose_semitones <> 0
    appendInfoLine: "Transpose: ", transpose_semitones, " st"
endif
appendInfoLine: ""

# === Create Manipulation ===
appendInfoLine: "Analyzing pitch..."
selectObject: original
manipulation = To Manipulation: pitch_time_step, min_pitch, max_pitch

selectObject: manipulation
pitchTier = Extract pitch tier

# === Smoothing (for Robot effect) ===
if smooth_amount > 0
    selectObject: pitchTier
    Stylize: smooth_amount, "Hz"
endif

# === Create Corrected Pitch Tier ===
selectObject: pitchTier
correctedTier = Copy: "Corrected"

selectObject: correctedTier
n = Get number of points

# Store for visualization
maxVizPoints = min(n, 500)
vizTimes# = zero#(maxVizPoints)
vizOrigPitch# = zero#(maxVizPoints)
vizCorrPitch# = zero#(maxVizPoints)
vizStep = ceiling(n / maxVizPoints)

appendInfoLine: "Correcting ", n, " pitch points..."

corrected_count = 0

for i from 1 to n
    selectObject: pitchTier
    origVal = Get value at index: i
    time = Get time from index: i

    if origVal > 50 and origVal < 1000
        # A. Convert Hz to MIDI
        midi_float = 69 + 12 * log2(origVal / 440)
        midi_round = round(midi_float)

        # B. Get pitch class relative to root (0-11)
        pc_raw = (midi_round - root_idx) mod 12
        if pc_raw < 0
            pc_raw = pc_raw + 12
        endif

        # C. Check scale pattern
        is_allowed$ = mid$(pat$, pc_raw + 1, 1)

        if is_allowed$ = "0"
            # Note out of scale - find nearest
            corrected_count = corrected_count + 1

            # Check upper (+1)
            pc_up = (pc_raw + 1) mod 12
            allowed_up$ = mid$(pat$, pc_up + 1, 1)

            # Check lower (-1)
            pc_down = pc_raw - 1
            if pc_down < 0
                pc_down = 11
            endif
            allowed_down$ = mid$(pat$, pc_down + 1, 1)

            # Snap to nearest allowed
            if allowed_up$ = "1" and allowed_down$ = "0"
                midi_round = midi_round + 1
            elsif allowed_down$ = "1" and allowed_up$ = "0"
                midi_round = midi_round - 1
            elsif allowed_down$ = "1" and allowed_up$ = "1"
                # Both valid - snap to closer
                diff = midi_float - midi_round
                if diff > 0
                    midi_round = midi_round + 1
                else
                    midi_round = midi_round - 1
                endif
            endif
        endif

        # D. Convert target MIDI back to Hz
        target_val = 440 * (2 ^ ((midi_round - 69) / 12))

        # E. Apply transpose
        if transpose_semitones <> 0
            target_val = target_val * (2 ^ (transpose_semitones / 12))
        endif

        # F. Blend with strength
        final_val = origVal + (target_val - origVal) * (strength / 100)

        # Store for visualization
        vizIdx = ceiling(i / vizStep)
        if vizIdx >= 1 and vizIdx <= maxVizPoints
            if vizTimes#[vizIdx] = 0
                vizTimes#[vizIdx] = time
                vizOrigPitch#[vizIdx] = origVal
                vizCorrPitch#[vizIdx] = final_val
            endif
        endif

        selectObject: correctedTier
        Remove point: i
        Add point: time, final_val
    endif
endfor

appendInfoLine: "Notes corrected: ", corrected_count

# === Resynthesize ===
appendInfoLine: ""
appendInfoLine: "Resynthesizing..."

selectObject: manipulation, correctedTier
Replace pitch tier

selectObject: manipulation
result = Get resynthesis (overlap-add)
# v0.3: output filename now includes preset suffix.
compositeName$ = name$ + "_" + rootName$ + scaleName$ + "_" + presetName$
Rename: compositeName$

selectObject: result
Scale peak: 0.95
rms_out = Get root-mean-square: 0, 0

###############################################################################
# VISUALIZATION  (8 x 8 canvas — custom layout, suite styling)
# Pitch correction with grid (FULL WIDTH, signature, biggest panel)
# Original waveform   (left half)
# Result waveform     (right half)
# Scale pattern (12 cells showing chromatic row with scale highlights)
# Light-grey 3-line summary (suite standard)
###############################################################################

if draw_visualization
    Erase all
    Select outer viewport: 0, 8, 0, 8
    Black
    Plain line

    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##PITCH CORRECTION##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... name$
        ... + "  ->  " + rootName$ + " " + scaleName$
        ... + "  |  " + presetName$
        ... + "  |  Strength " + fixed$(strength, 0) + "%"
        ... + "  |  " + string$(corrected_count) + " of " + string$(n) + " notes snapped"

    # ----------------------------------------------------------
    # PANEL A: PITCH CORRECTION WITH SCALE GRID (signature, biggest)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.75, 4.40
    Select inner viewport: 0.55, 7.72, 0.95, 4.25

    # Find pitch range
    minP = 1000
    maxP = 50
    for vp from 1 to maxVizPoints
        if vizOrigPitch#[vp] > 0
            if vizOrigPitch#[vp] < minP
                minP = vizOrigPitch#[vp]
            endif
            if vizOrigPitch#[vp] > maxP
                maxP = vizOrigPitch#[vp]
            endif
        endif
        if vizCorrPitch#[vp] > 0
            if vizCorrPitch#[vp] < minP
                minP = vizCorrPitch#[vp]
            endif
            if vizCorrPitch#[vp] > maxP
                maxP = vizCorrPitch#[vp]
            endif
        endif
    endfor

    # Defensive: if no valid points were collected (e.g. fully unvoiced),
    # fall back to the form's min/max pitch range so the panel still draws.
    if minP >= maxP
        minP = min_pitch
        maxP = max_pitch
    endif

    # Expand to nearest MIDI notes (gives clean grid alignment)
    minMidi = floor(69 + 12 * log2(minP / 440)) - 1
    maxMidi = ceiling(69 + 12 * log2(maxP / 440)) + 1

    minP = 440 * (2 ^ ((minMidi - 69) / 12))
    maxP = 440 * (2 ^ ((maxMidi - 69) / 12))

    Axes: 0, duration, minP, maxP
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, minP, maxP

    # Draw scale grid lines (green for in-scale, faint grey for out)
    for midi from minMidi to maxMidi
        freq = 440 * (2 ^ ((midi - 69) / 12))
        pc = (midi - root_idx) mod 12
        if pc < 0
            pc = pc + 12
        endif

        inScale$ = mid$(pat$, pc + 1, 1)

        if inScale$ = "1"
            Colour: "{0.70, 0.85, 0.70}"
            Line width: 1.5
        else
            Colour: "{0.90, 0.90, 0.92}"
            Line width: 0.5
        endif

        Draw line: 0, freq, duration, freq
    endfor
    Line width: 1

    # Original pitch (gray, behind)
    Colour: "{0.55, 0.55, 0.60}"
    Line width: 1
    for vp from 2 to maxVizPoints
        if vizOrigPitch#[vp] > 0 and vizOrigPitch#[vp - 1] > 0
            Draw line: vizTimes#[vp - 1], vizOrigPitch#[vp - 1], vizTimes#[vp], vizOrigPitch#[vp]
        endif
    endfor

    # Corrected pitch (blue, foreground)
    Colour: "{0.25, 0.45, 0.78}"
    Line width: 1.8
    for vp from 2 to maxVizPoints
        if vizCorrPitch#[vp] > 0 and vizCorrPitch#[vp - 1] > 0
            Draw line: vizTimes#[vp - 1], vizCorrPitch#[vp - 1], vizTimes#[vp], vizCorrPitch#[vp]
        endif
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 7
    # v0.3: legend goes in the panel title (Text top) instead of broken
    # inline Text at wrong axes.
    Text top: "no", "Pitch correction:  gray = original,  blue = corrected,  green grid = in-scale notes"
    Text left: "yes", "Pitch (Hz)"

    # ----------------------------------------------------------
    # PANEL B (left): ORIGINAL WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 4.50, 5.55
    Select inner viewport: 0.55, 4.00, 4.62, 5.45

    selectObject: original
    Colour: "{0.55, 0.55, 0.60}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Original waveform"
    Font size: 6
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL C (right): RESULT WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 4.50, 5.55
    Select inner viewport: 4.55, 7.75, 4.62, 5.45

    selectObject: result
    Colour: "{0.30, 0.50, 0.70}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Corrected waveform"
    Font size: 6
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL D: SCALE PATTERN (12-cell chromatic row from root)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.65, 6.30
    Select inner viewport: 0.55, 7.72, 5.78, 6.18

    Axes: 0, 12, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 12, 0, 1

    for pc from 0 to 11
        # Rotate to show from root (pc=0 cell shows root note)
        displayPC = (pc + root_idx) mod 12
        inScale$ = mid$(pat$, pc + 1, 1)

        if inScale$ = "1"
            Paint rectangle: "{0.60, 0.82, 0.62}", pc + 0.1, pc + 0.9, 0.15, 0.85
        else
            Paint rectangle: "{0.88, 0.88, 0.90}", pc + 0.1, pc + 0.9, 0.15, 0.85
        endif

        Colour: "Black"
        Font size: 6
        Text: pc + 0.5, "centre", 0.5, "half", noteNames$#[displayPC + 1]
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Scale pattern starting from " + rootName$ + " (green = in-scale, grey = snapped to nearest)"

    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR  (suite standard light grey)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.40, 7.10
    Select inner viewport: 0.55, 7.72, 6.47, 7.05
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.82, "half",
        ... "##" + presetName$ + "##"
        ... + "  Key: " + rootName$ + " " + scaleName$
        ... + "  |  Strength: " + fixed$(strength, 0) + "%"
        ... + "  |  Smoothing: " + fixed$(smooth_amount, 1) + " Hz"
        ... + "  |  Transpose: " + string$(transpose_semitones) + " st"

    Text: 0.02, "left", 0.50, "half",
        ... "Pitch analysis: step " + fixed$(pitch_time_step * 1000, 1) + " ms"
        ... + ",  range " + fixed$(min_pitch, 0) + "-" + fixed$(max_pitch, 0) + " Hz"
        ... + "  |  Points: " + string$(n)
        ... + "  |  Corrected: " + string$(corrected_count) + "  (" + fixed$(100 * corrected_count / max(n, 1), 1) + "%)"

    Text: 0.02, "left", 0.18, "half",
        ... "Output: " + compositeName$
        ... + "  |  Duration: " + fixed$(duration, 2) + " s"
        ... + "  |  Out RMS: " + fixed$(rms_out, 4)
        ... + "  |  SR: " + fixed$(fs / 1000, 1) + " kHz"

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# === Cleanup ===
removeObject: manipulation, pitchTier, correctedTier

# === Final Info ===
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", compositeName$
appendInfoLine: "Out RMS: ", fixed$(rms_out, 6)

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result
