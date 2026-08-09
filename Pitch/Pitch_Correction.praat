# ============================================================
# Praat AudioTools - Pitch_Correction.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4a (2026)
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
# Changelog v0.4a:
#   - FIX: removed unsupported PitchTier `Get quantile` call in Robot mode.
#   - Robot reference pitch is now computed directly as the geometric mean
#     of the original PitchTier points, using commands available for PitchTier.
#
# Changelog v0.4:
#   - Allows Strength_percent = 0 and validates the effective range 0..100.
#   - Adds validation for pitch analysis settings and source duration.
#   - Analysis is performed on a mono reference while the output preserves
#     the original channel count.
#   - Keeps the original source PitchTier intact for visualization; Natural
#     stylization no longer changes the curve labelled "Original".
#   - Robot / Monotone now creates a true flat quantized target rather than
#     relying on PitchTier Stylize.
#   - Adds synthesis-safe pitch limiting after correction / transpose.
#   - Handles non-zero source xmin correctly in the pitch visualization.
#   - Separates out-of-scale points from actually changed pitch points.
#   - Attenuation-only peak safety; quiet outputs are not normalized upward.
#   - Visualization layout and styling are preserved.
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
source_xmin = Get start time
source_xmax = Get end time
duration = source_xmax - source_xmin
fs = Get sampling frequency
n_channels = Get number of channels

# === Form ===
form Pitch Correction v0.4a
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
    real Strength_percent 100
    positive Pitch_time_step 0.01
    positive Min_pitch 75
    positive Max_pitch 600
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
strength = strength_percent
smooth_amount = 0
robot_mode = 0

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
    # Robot / Monotone
    strength = 100
    smooth_amount = 0
    robot_mode = 1
    presetName$ = "Robot"
else
    presetName$ = "Custom"
endif

# === Validation ===
if duration <= 0
    exitScript: "The selected Sound has no positive duration."
endif
if strength < 0 or strength > 100
    exitScript: "Strength_percent must be between 0 and 100."
endif
if pitch_time_step <= 0
    exitScript: "Pitch_time_step must be greater than zero."
endif
if min_pitch <= 0 or max_pitch <= min_pitch
    exitScript: "Min_pitch / Max_pitch are invalid."
endif
if max_pitch >= 0.45 * fs
    exitScript: "Max_pitch must be below 45% of the sampling frequency."
endif

# === Get Scale/Root Names ===
noteNames$# = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
rootName$ = noteNames$#[root_Note]

scaleNames$# = {"Chromatic", "Major", "Minor", "Harm Min", "Pent Maj", "Pent Min", "Dorian", "Phrygian", "Lydian", "Mixolydian"}
scaleName$ = scaleNames$#[scale_Type]

# === Define Scale Patterns ===
pat$ = "111111111111"

if scale_Type = 2
    pat$ = "101011010101"
elsif scale_Type = 3
    pat$ = "101101011010"
elsif scale_Type = 4
    pat$ = "101101011001"
elsif scale_Type = 5
    pat$ = "101010010100"
elsif scale_Type = 6
    pat$ = "100101010010"
elsif scale_Type = 7
    pat$ = "101101010110"
elsif scale_Type = 8
    pat$ = "110101011010"
elsif scale_Type = 9
    pat$ = "101010110101"
elsif scale_Type = 10
    pat$ = "101011010110"
endif

root_idx = root_Note - 1

# === Info ===
writeInfoLine: "=== Pitch Correction v0.4a ==="
appendInfoLine: "Source: ", name$, " (", fixed$(duration, 2), " s, ", n_channels, " ch)"
appendInfoLine: "Key: ", rootName$, " ", scaleName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Strength: ", strength, "%"
if smooth_amount > 0
    appendInfoLine: "Natural stylization: ", smooth_amount, " Hz"
endif
if robot_mode
    appendInfoLine: "Robot mode: flat quantized pitch"
endif
if transpose_semitones <> 0
    appendInfoLine: "Transpose: ", transpose_semitones, " st"
endif
appendInfoLine: ""

# === Mono analysis reference ===
selectObject: original
if n_channels > 1
    analysis_mono = Convert to mono
else
    analysis_mono = Copy: "PC_analysis"
endif

# === Create Manipulation / original PitchTier ===
appendInfoLine: "Analyzing pitch..."
selectObject: analysis_mono
analysis_manip = To Manipulation: pitch_time_step, min_pitch, max_pitch

selectObject: analysis_manip
pitchTierOriginal = Extract pitch tier

selectObject: pitchTierOriginal
n = Get number of points

if n < 1
    removeObject: analysis_manip, pitchTierOriginal, analysis_mono
    exitScript: "No usable voiced pitch was detected in the selected analysis range."
endif

# Working tier begins as a copy; keep pitchTierOriginal untouched for display.
selectObject: pitchTierOriginal
pitchTierWork = Copy: "PC_work_tier"

# Natural preset: gentle tier stylization before quantization.
if smooth_amount > 0
    selectObject: pitchTierWork
    Stylize: smooth_amount, "Hz"
endif

# Corrected tier is rebuilt from scratch to avoid remove/add index-order effects.
Create PitchTier: "Corrected", source_xmin, source_xmax
correctedTier = selected("PitchTier")

# Visualization arrays
maxVizPoints = min(n, 500)
if maxVizPoints < 1
    maxVizPoints = 1
endif
vizTimes# = zero#(maxVizPoints)
vizOrigPitch# = zero#(maxVizPoints)
vizCorrPitch# = zero#(maxVizPoints)
vizStep = ceiling(n / maxVizPoints)
if vizStep < 1
    vizStep = 1
endif

appendInfoLine: "Correcting ", n, " pitch points..."

out_of_scale_count = 0
changed_points = 0
limited_points = 0

# Robot target: quantize the source median pitch once, then hold it flat.
robot_target = 0
if robot_mode
    # PitchTier has no `Get quantile` command in current Praat.
    # Compute a stable central pitch directly from the tier points.
    robot_log_sum = 0
    robot_valid_n = 0

    for ri from 1 to n
        selectObject: pitchTierOriginal
        robot_val = Get value at index: ri
        if robot_val <> undefined and robot_val > 0
            robot_log_sum += log2(robot_val)
            robot_valid_n += 1
        endif
    endfor

    if robot_valid_n < 1
        removeObject: analysis_manip, pitchTierOriginal, pitchTierWork, correctedTier, analysis_mono
        exitScript: "Robot mode could not determine a valid source pitch."
    endif

    robot_source = 2 ^ (robot_log_sum / robot_valid_n)

    midi_float_robot = 69 + 12 * log2(robot_source / 440)
    midi_round_robot = round(midi_float_robot)

    best_midi = midi_round_robot
    best_dist = 1000
    for delta from -6 to 6
        cand = midi_round_robot + delta
        cand_pc = (cand - root_idx) mod 12
        if cand_pc < 0
            cand_pc += 12
        endif
        if mid$(pat$, cand_pc + 1, 1) = "1"
            dist = abs(cand - midi_float_robot)
            if dist < best_dist
                best_dist = dist
                best_midi = cand
            endif
        endif
    endfor

    robot_target = 440 * (2 ^ ((best_midi - 69) / 12))
    if transpose_semitones <> 0
        robot_target *= 2 ^ (transpose_semitones / 12)
    endif
endif

# Synthesis safety: independent from analysis range.
synth_floor = 20
synth_ceil = 0.45 * fs

for i from 1 to n
    selectObject: pitchTierOriginal
    origVal = Get value at index: i
    time = Get time from index: i

    # Use stylized value for Natural quantization; otherwise original.
    selectObject: pitchTierWork
    workVal = Get value at time: time

    if workVal = undefined or workVal <= 0
        workVal = origVal
    endif

    if robot_mode
        target_val = robot_target
    else
        midi_float = 69 + 12 * log2(workVal / 440)
        midi_round = round(midi_float)

        pc_raw = (midi_round - root_idx) mod 12
        if pc_raw < 0
            pc_raw += 12
        endif

        if mid$(pat$, pc_raw + 1, 1) = "0"
            out_of_scale_count += 1
        endif

        # Search the nearest allowed scale tone robustly.
        best_midi = midi_round
        best_dist = 1000
        for delta from -6 to 6
            cand = midi_round + delta
            cand_pc = (cand - root_idx) mod 12
            if cand_pc < 0
                cand_pc += 12
            endif
            if mid$(pat$, cand_pc + 1, 1) = "1"
                dist = abs(cand - midi_float)
                if dist < best_dist
                    best_dist = dist
                    best_midi = cand
                endif
            endif
        endfor

        target_val = 440 * (2 ^ ((best_midi - 69) / 12))

        if transpose_semitones <> 0
            target_val *= 2 ^ (transpose_semitones / 12)
        endif
    endif

    # Strength is applied in log-frequency space for musically uniform interpolation.
    if target_val > 0 and origVal > 0
        orig_c = 1200 * log2(origVal)
        targ_c = 1200 * log2(target_val)
        final_c = orig_c + (targ_c - orig_c) * (strength / 100)
        final_val = 2 ^ (final_c / 1200)
    else
        final_val = origVal
    endif

    if final_val < synth_floor
        final_val = synth_floor
        limited_points += 1
    elsif final_val > synth_ceil
        final_val = synth_ceil
        limited_points += 1
    endif

    if abs(1200 * log2(final_val / origVal)) > 0.01
        changed_points += 1
    endif

    selectObject: correctedTier
    Add point: time, final_val

    vizIdx = ceiling(i / vizStep)
    if vizIdx >= 1 and vizIdx <= maxVizPoints
        if vizTimes#[vizIdx] = 0
            vizTimes#[vizIdx] = time - source_xmin
            vizOrigPitch#[vizIdx] = origVal
            vizCorrPitch#[vizIdx] = final_val
        endif
    endif
endfor

appendInfoLine: "Out-of-scale points: ", out_of_scale_count
appendInfoLine: "Pitch points changed: ", changed_points
if limited_points > 0
    appendInfoLine: "Sampling-safe pitch limits applied: ", limited_points, " point(s)"
endif

# === Resynthesize all original channels ===
appendInfoLine: ""
appendInfoLine: "Resynthesizing ", n_channels, " channel(s)..."

channel_results# = zero#(n_channels)

for ch from 1 to n_channels
    selectObject: original
    if n_channels = 1
        channel_work = Copy: "PC_ch1"
    else
        channel_work = Extract one channel: ch
        Rename: "PC_ch" + string$(ch)
    endif

    selectObject: channel_work
    channel_manip = To Manipulation: pitch_time_step, min_pitch, max_pitch

    selectObject: channel_manip
    plusObject: correctedTier
    Replace pitch tier

    selectObject: channel_manip
    channel_result = Get resynthesis (overlap-add)
    Rename: "PC_result_ch" + string$(ch)
    channel_results#[ch] = channel_result

    removeObject: channel_manip, channel_work
endfor

# Rebuild exact channel count using numeric object IDs.
Create Sound from formula: "PC_result_build", n_channels,
    ... source_xmin, source_xmax, fs, "0"
result = selected("Sound")

for ch from 1 to n_channels
    selectObject: result
    Formula (part): source_xmin, source_xmax, ch, ch,
        ... "object[" + string$(channel_results#[ch]) + ", 1, col]"
    removeObject: channel_results#[ch]
endfor

compositeName$ = name$ + "_" + rootName$ + scaleName$ + "_" + presetName$
selectObject: result
Rename: compositeName$

# Attenuation-only peak safety.
peak_out = Get absolute extremum: 0, 0, "None"
if peak_out > 0.95
    Scale peak: 0.95
    safetyApplied = 1
else
    safetyApplied = 0
endif
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
        ... + "  |  " + string$(changed_points) + " of " + string$(n) + " pitch points changed"

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
        ... + "  |  Changed: " + string$(changed_points) + "  (" + fixed$(100 * changed_points / max(n, 1), 1) + "%)"

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
removeObject: analysis_manip, pitchTierOriginal, pitchTierWork, correctedTier, analysis_mono

# === Final Info ===
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", compositeName$
appendInfoLine: "Channels preserved: ", n_channels
appendInfoLine: "Pitch points changed: ", changed_points
appendInfoLine: "Peak safety applied: ", safetyApplied
appendInfoLine: "Out RMS: ", fixed$(rms_out, 6)

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result
