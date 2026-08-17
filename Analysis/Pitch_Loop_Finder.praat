# ============================================================
# Praat AudioTools - Pitch_Loop_Finder.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.2 (2026 review)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Finds repeating pitch patterns by scanning pitch self-similarity
#   diagonals. Detects melodic loops, recurring phrases, and repeated
#   pitch/rhythm shapes. Outputs an annotated TextGrid and visualization.
#
# Review changes v0.4:
#   - Uses semitone distance instead of register-dependent Hz distance.
#   - Uses the actual Pitch frame times (x1/dx) for TextGrid boundaries.
#   - Allows short mismatches/dropouts and matched unvoiced regions.
#   - Rejects silence/static-tone false positives unless rhythmic
#     voiced/unvoiced structure is present.
#   - Rejects self-overlapping source/repeat candidates.
#   - Ranks candidates by normalized match quality, not accumulated length.
#   - Avoids an O(N^2) full SSM during detection; long files are searched
#     on an adaptive pitch-frame grid.
#   - Visualization now paints an actual decimated pitch SSM.
#   - Uses explicit waveform scaling and more diagnostic output.
#
# Patch v0.4.1:
#   - Renames local procedure variable .L to .len; Praat parses a
#     dotted identifier beginning with an uppercase letter as an object/class reference.
#
# Patch v0.4.2:
#   - Fixes Praat continuation syntax: ellipsis belongs at the start of
#     the continuation line, not at the end of the preceding line.
#   - Applies the fix to overlap logic, Info output, and Matrix creation.
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

form Pitch Loop Finder
    comment === Preset ===
    optionmenu Preset: 1
        option Custom
        option Vocal Melody
        option Instrumental Riff
        option Speech Pattern
        option Bass Line
        option Full Range
    comment === Analysis ===
    positive Time_step 0.05
    comment (0.05 = fast; smaller values = finer pitch sampling)
    positive Pitch_floor 75
    positive Pitch_ceiling 600
    positive Pitch_tolerance_semitones 0.75
    comment === Loop Timing / Robustness ===
    positive Min_loop_duration 0.4
    positive Max_loop_duration 10.0
    positive Max_break_duration 0.10
    positive Min_voiced_fraction 0.35
    positive Min_pitch_span_semitones 0.50
    comment === Output ===
    natural Num_loops_to_find 5
    boolean Show_visualization 1
    boolean Open_textgrid_editor 1
endform

# === APPLY PRESETS ===
if preset = 2
    # Vocal Melody
    pitch_floor = 100
    pitch_ceiling = 500
    pitch_tolerance_semitones = 0.80
    min_loop_duration = 0.5
    max_loop_duration = 8.0
    max_break_duration = 0.10
    min_voiced_fraction = 0.40
    min_pitch_span_semitones = 0.60
    time_step = 0.03
    presetName$ = "VocalMelody"
elsif preset = 3
    # Instrumental Riff
    pitch_floor = 60
    pitch_ceiling = 800
    pitch_tolerance_semitones = 0.60
    min_loop_duration = 0.3
    max_loop_duration = 4.0
    max_break_duration = 0.08
    min_voiced_fraction = 0.45
    min_pitch_span_semitones = 0.50
    time_step = 0.04
    presetName$ = "InstrumentalRiff"
elsif preset = 4
    # Speech Pattern
    pitch_floor = 75
    pitch_ceiling = 400
    pitch_tolerance_semitones = 1.00
    min_loop_duration = 0.2
    max_loop_duration = 3.0
    max_break_duration = 0.08
    min_voiced_fraction = 0.30
    min_pitch_span_semitones = 0.80
    time_step = 0.02
    presetName$ = "SpeechPattern"
elsif preset = 5
    # Bass Line
    pitch_floor = 30
    pitch_ceiling = 200
    pitch_tolerance_semitones = 0.50
    min_loop_duration = 0.5
    max_loop_duration = 8.0
    max_break_duration = 0.10
    min_voiced_fraction = 0.40
    min_pitch_span_semitones = 0.40
    time_step = 0.05
    presetName$ = "BassLine"
elsif preset = 6
    # Full Range
    pitch_floor = 50
    pitch_ceiling = 1000
    pitch_tolerance_semitones = 0.75
    min_loop_duration = 0.3
    max_loop_duration = 15.0
    max_break_duration = 0.10
    min_voiced_fraction = 0.35
    min_pitch_span_semitones = 0.50
    time_step = 0.04
    presetName$ = "FullRange"
else
    presetName$ = "Custom"
endif

if max_loop_duration < min_loop_duration
    exitScript: "Max loop duration must be greater than or equal to Min loop duration."
endif
if min_voiced_fraction > 1
    exitScript: "Min voiced fraction must be between 0 and 1."
endif

# ===================================================================
# 1. SETUP / PITCH EXTRACTION
# ===================================================================

selectObject: originalID
sound_tmin = Get start time
sound_tmax = Get end time
duration = Get total duration
sampleRate = Get sampling frequency

clearinfo
writeInfoLine: "=== Pitch Loop Finder v0.4.2 ==="
appendInfoLine: "Sound: ", originalName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Duration: ", fixed$(duration, 2), " s"
appendInfoLine: "Requested pitch step: ", time_step, " s"
appendInfoLine: "Pitch range: ", pitch_floor, "-", pitch_ceiling, " Hz"
appendInfoLine: "Pitch tolerance: ", pitch_tolerance_semitones, " semitones"
appendInfoLine: "Max short break: ", max_break_duration, " s"
appendInfoLine: "Min voiced fraction: ", fixed$(min_voiced_fraction, 2)
appendInfoLine: "Min pitch span: ", min_pitch_span_semitones, " semitones"
appendInfoLine: ""

selectObject: originalID
pitchID = To Pitch: time_step, pitch_floor, pitch_ceiling
num_frames = Get number of frames
pitch_dx = Get time step
pitch_x1 = Get time from frame: 1
pitch_tmin = Get start time
pitch_tmax = Get end time

pitch_hz# = zero#(num_frames)
pitch_midi# = zero#(num_frames)
voiced_frames = 0
for i from 1 to num_frames
    f0 = Get value in frame: i, "Hertz"
    if f0 = undefined
        f0 = 0
    endif
    pitch_hz#[i] = f0
    if f0 > 0
        pitch_midi#[i] = 69 + 12 * log2(f0 / 440)
        voiced_frames = voiced_frames + 1
    else
        pitch_midi#[i] = 0
    endif
endfor

appendInfoLine: "Extracted ", num_frames, " pitch frames (dx = ", fixed$(pitch_dx, 5), " s)"
appendInfoLine: "Voiced frames: ", voiced_frames, "/", num_frames

# Build an adaptive search grid. This bounds the quadratic diagonal scan
# while preserving full pitch extraction for timing and visualization.
max_search_frames = 4000
search_stride = ceiling(num_frames / max_search_frames)
if search_stride < 1
    search_stride = 1
endif
search_n = floor((num_frames - 1) / search_stride) + 1
search_dt = pitch_dx * search_stride
search_hz# = zero#(search_n)
search_midi# = zero#(search_n)

for s from 1 to search_n
    original_frame = 1 + (s - 1) * search_stride
    search_hz#[s] = pitch_hz#[original_frame]
    search_midi#[s] = pitch_midi#[original_frame]
endfor

if search_stride > 1
    appendInfoLine: "Adaptive search stride: ", search_stride, " frames (effective step ", fixed$(search_dt, 4), " s)"
else
    appendInfoLine: "Search uses every pitch frame."
endif
appendInfoLine: ""

# ===================================================================
# 2. LOOP CANDIDATE TABLE / TEXTGRID
# ===================================================================

selectObject: originalID
textgridID = To TextGrid: "Loops Repeats", ""

Create Table with column names: "candidates", 0, "start_index length_steps gap_steps score mean_similarity voiced_fraction pitch_span"
tableID = selected("Table")

min_len = ceiling(min_loop_duration / search_dt)
max_len = floor(max_loop_duration / search_dt)
if min_len < 1
    min_len = 1
endif
if max_len < min_len
    max_len = min_len
endif
max_break_frames = round(max_break_duration / search_dt)
if max_break_frames < 0
    max_break_frames = 0
endif

# A candidate must have enough actual pitch content, and a static voiced
# plateau is rejected unless it contains a meaningful voiced/unvoiced rhythm.
min_mean_similarity = 0.55

# ===================================================================
# Candidate evaluation helper.
# The diagonal scan only finds contiguous/near-contiguous matches; this
# procedure computes the musical/content checks and normalized score.
# ===================================================================
procedure addCandidate: .start, .runLength, .gap
    .len = .runLength
    if .len > max_len
        .len = max_len
    endif

    if .len >= min_len and .gap >= .len and .start >= 1 and .start + .gap + .len - 1 <= search_n
        .sumSimilarity = 0
        .voicedBoth = 0
        .minMidi = 1000000
        .maxMidi = -1000000
        .transitions = 0
        .previousVoiced = -1

        for .q from 0 to .len - 1
            .a = search_midi#[.start + .q]
            .b = search_midi#[.start + .gap + .q]
            .aVoiced = .a > 0
            .bVoiced = .b > 0
            .sim = 0

            if .aVoiced and .bVoiced
                .delta = abs(.a - .b)
                if .delta <= pitch_tolerance_semitones
                    .sim = 1 - .delta / pitch_tolerance_semitones
                endif
                .voicedBoth = .voicedBoth + 1
            elsif not .aVoiced and not .bVoiced
                # Matched rests/unvoiced frames preserve phrase continuity,
                # but count less than an actual pitch match.
                .sim = 0.65
            endif

            .sumSimilarity = .sumSimilarity + .sim

            if .aVoiced
                if .a < .minMidi
                    .minMidi = .a
                endif
                if .a > .maxMidi
                    .maxMidi = .a
                endif
            endif

            if .previousVoiced >= 0 and .aVoiced <> .previousVoiced
                .transitions = .transitions + 1
            endif
            .previousVoiced = .aVoiced
        endfor

        .voicedFraction = .voicedBoth / .len
        .meanSimilarity = .sumSimilarity / .len
        if .maxMidi > -100000
            .pitchSpan = .maxMidi - .minMidi
        else
            .pitchSpan = 0
        endif

        # Normalized 0..100 quality. Voiced content is rewarded but duration
        # itself does not inflate the score.
        .score = 100 * .meanSimilarity * (0.6 + 0.4 * .voicedFraction)

        .hasStructure = (.pitchSpan >= min_pitch_span_semitones or .transitions >= 2)
        if .voicedFraction >= min_voiced_fraction and .meanSimilarity >= min_mean_similarity and .hasStructure
            selectObject: tableID
            Append row
            .row = Get number of rows
            Set numeric value: .row, "start_index", .start
            Set numeric value: .row, "length_steps", .len
            Set numeric value: .row, "gap_steps", .gap
            Set numeric value: .row, "score", .score
            Set numeric value: .row, "mean_similarity", .meanSimilarity
            Set numeric value: .row, "voiced_fraction", .voicedFraction
            Set numeric value: .row, "pitch_span", .pitchSpan
        endif
    endif
endproc

# ===================================================================
# 3. FIND LOOPS BY SCANNING SELF-SIMILARITY DIAGONALS
# ===================================================================

appendInfo: "Scanning pitch-similarity diagonals..."

max_gap = search_n - min_len
gap_step = 1
# The adaptive grid already caps search_n; an extra small safeguard keeps
# pathological scans bounded if future settings change max_search_frames.
if search_n > 4000
    gap_step = ceiling(search_n / 4000)
endif

gap = min_len
while gap <= max_gap
    path_start = 0
    path_len = 0
    trailing_breaks = 0
    search_limit = search_n - gap

    for i from 1 to search_limit
        a = search_midi#[i]
        b = search_midi#[i + gap]
        is_match = 0

        if a > 0 and b > 0
            delta = abs(a - b)
            if delta <= pitch_tolerance_semitones
                is_match = 1
            endif
        elsif a <= 0 and b <= 0
            # Repeated silence/rest is allowed inside a phrase; content checks
            # in addCandidate prevent silence-only loops.
            is_match = 1
        endif

        if path_start = 0
            if is_match
                path_start = i
                path_len = 1
                trailing_breaks = 0
            endif
        else
            path_len = path_len + 1
            if is_match
                trailing_breaks = 0
            else
                trailing_breaks = trailing_breaks + 1
                if trailing_breaks > max_break_frames
                    effective_len = path_len - trailing_breaks
                    @addCandidate: path_start, effective_len, gap
                    path_start = 0
                    path_len = 0
                    trailing_breaks = 0
                endif
            endif
        endif
    endfor

    # Final diagonal segment; discard unmatched tail before evaluation.
    if path_start > 0
        effective_len = path_len - trailing_breaks
        @addCandidate: path_start, effective_len, gap
    endif

    gap = gap + gap_step
endwhile

appendInfoLine: " done."

# ===================================================================
# 4. FILTER, RANK & ANNOTATE
# ===================================================================

selectObject: tableID
nRows = Get number of rows

if nRows = 0
    removeObject: tableID, pitchID
    appendInfoLine: ""
    appendInfoLine: "No loops found. Try a larger pitch tolerance, shorter minimum duration,"
    appendInfoLine: "or lower the minimum voiced fraction / pitch span."
    selectObject: originalID
    plusObject: textgridID
    exitScript: "No loops found."
endif

appendInfoLine: "Found ", nRows, " musically valid candidates; selecting up to ", num_loops_to_find

selectObject: tableID
Sort rows: "score"

loops_found = 0
row_index = nRows

while loops_found < num_loops_to_find and row_index > 0
    selectObject: tableID
    start_s = Get value: row_index, "start_index"
    len_s = Get value: row_index, "length_steps"
    gap_s = Get value: row_index, "gap_steps"
    candidate_score = Get value: row_index, "score"
    candidate_mean = Get value: row_index, "mean_similarity"
    candidate_voiced = Get value: row_index, "voiced_fraction"
    candidate_span = Get value: row_index, "pitch_span"

    # Search index 1 is centred at pitch_x1. Convert frame-centred estimates
    # to interval boundaries with half an effective search step of padding.
    t1 = pitch_x1 + (start_s - 1) * search_dt - 0.5 * search_dt
    t2 = pitch_x1 + (start_s + len_s - 2) * search_dt + 0.5 * search_dt
    r_t1 = pitch_x1 + (start_s + gap_s - 1) * search_dt - 0.5 * search_dt
    r_t2 = pitch_x1 + (start_s + gap_s + len_s - 2) * search_dt + 0.5 * search_dt

    if t1 < sound_tmin
        t1 = sound_tmin
    endif
    if t2 > sound_tmax
        t2 = sound_tmax
    endif
    if r_t1 < sound_tmin
        r_t1 = sound_tmin
    endif
    if r_t2 > sound_tmax
        r_t2 = sound_tmax
    endif

    # Select distinct source/repeat pairs. A new candidate may not overlap
    # either member of an already selected pair; this suppresses chains such
    # as A->B followed immediately by B->C from dominating the output.
    is_overlap = 0
    for k from 1 to loops_found
        if (t1 < loop_t2[k] and t2 > loop_t1[k]) or
           ... (t1 < rep_t2[k] and t2 > rep_t1[k]) or
           ... (r_t1 < loop_t2[k] and r_t2 > loop_t1[k]) or
           ... (r_t1 < rep_t2[k] and r_t2 > rep_t1[k])
            is_overlap = 1
        endif
    endfor

    if not is_overlap and t2 > t1 and r_t2 > r_t1 and r_t1 >= t2
        loops_found = loops_found + 1
        loop_t1[loops_found] = t1
        loop_t2[loops_found] = t2
        rep_t1[loops_found] = r_t1
        rep_t2[loops_found] = r_t2
        loop_score[loops_found] = candidate_score
        loop_mean[loops_found] = candidate_mean
        loop_voiced[loops_found] = candidate_voiced
        loop_span[loops_found] = candidate_span

        selectObject: textgridID
        nocheck Insert boundary: 1, t1
        nocheck Insert boundary: 1, t2
        int_idx = Get interval at time: 1, (t1 + t2) / 2
        Set interval text: 1, int_idx, "Loop " + string$(loops_found)

        nocheck Insert boundary: 2, r_t1
        nocheck Insert boundary: 2, r_t2
        int_idx = Get interval at time: 2, (r_t1 + r_t2) / 2
        Set interval text: 2, int_idx, "Repeat " + string$(loops_found)

        appendInfoLine: "Loop ", loops_found, ": ", fixed$(t1, 2), "-", fixed$(t2, 2),
            ... " s -> ", fixed$(r_t1, 2), "-", fixed$(r_t2, 2),
            ... " s | score ", fixed$(candidate_score, 1), "/100 | voiced ", fixed$(candidate_voiced, 2),
            ... " | span ", fixed$(candidate_span, 2), " st"
    endif

    row_index = row_index - 1
endwhile

# ===================================================================
# 5. VISUALIZATION
# ===================================================================

vizDataID = 0
ssmViewID = 0

if show_visualization
    Erase all

    # --- Title strip ---
    Select outer viewport: 0, 8, 0.0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.55, "half", "Pitch Loop Finder: " + originalName$ + " [" + presetName$ + "]"

    # --- Waveform with source/repeat regions ---
    Select outer viewport: 0, 8, 0.55, 1.85
    Select inner viewport: 0.55, 7.65, 0.68, 1.72

    selectObject: originalID
    ampMax = Get maximum: sound_tmin, sound_tmax, "Sinc70"
    ampMin = Get minimum: sound_tmin, sound_tmax, "Sinc70"
    ampAbs = max(abs(ampMin), abs(ampMax))
    if ampAbs <= 0
        ampAbs = 1
    endif
    Axes: sound_tmin, sound_tmax, -ampAbs, ampAbs

    for k from 1 to loops_found
        if k = 1
            col$ = "{0.20, 0.45, 0.72}"
            col2$ = "{0.68, 0.82, 0.94}"
        elsif k = 2
            col$ = "{0.78, 0.42, 0.20}"
            col2$ = "{0.94, 0.73, 0.57}"
        elsif k = 3
            col$ = "{0.28, 0.62, 0.35}"
            col2$ = "{0.68, 0.86, 0.70}"
        elsif k = 4
            col$ = "{0.58, 0.36, 0.66}"
            col2$ = "{0.82, 0.70, 0.86}"
        else
            col$ = "{0.45, 0.45, 0.45}"
            col2$ = "{0.75, 0.75, 0.75}"
        endif
        Paint rectangle: col$, loop_t1[k], loop_t2[k], -ampAbs, ampAbs
        Paint rectangle: col2$, rep_t1[k], rep_t2[k], -ampAbs, ampAbs
    endfor

    selectObject: originalID
    Colour: "{0.20, 0.20, 0.20}"
    Line width: 1
    Draw: sound_tmin, sound_tmax, -ampAbs, ampAbs, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Waveform"

    # --- Pitch contour ---
    Select outer viewport: 0, 8, 1.95, 3.10
    Select inner viewport: 0.55, 7.65, 2.08, 2.95

    selectObject: pitchID
    minF0 = Get minimum: pitch_tmin, pitch_tmax, "Hertz", "Parabolic"
    maxF0 = Get maximum: pitch_tmin, pitch_tmax, "Hertz", "Parabolic"
    if minF0 = undefined or maxF0 = undefined or maxF0 <= minF0
        minF0 = pitch_floor
        maxF0 = pitch_ceiling
    endif
    pitchYmin = max(1, minF0 * 0.90)
    pitchYmax = maxF0 * 1.10
    Axes: pitch_tmin, pitch_tmax, pitchYmin, pitchYmax
    Colour: "{0.96, 0.96, 0.96}"
    Paint rectangle: "{0.96, 0.96, 0.96}", pitch_tmin, pitch_tmax, pitchYmin, pitchYmax
    Colour: "{0.18, 0.52, 0.32}"
    Line width: 1.5
    Draw: pitch_tmin, pitch_tmax, pitchYmin, pitchYmax, "no"
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "F0 (Hz)"
    Text bottom: "yes", "Time (s)"

    # --- Actual decimated pitch SSM ---
    # Build at most 300x300 cells for drawing; detection itself did not need
    # an N^2 matrix.
    max_viz_frames = 300
    viz_stride = ceiling(num_frames / max_viz_frames)
    if viz_stride < 1
        viz_stride = 1
    endif
    viz_n = floor((num_frames - 1) / viz_stride) + 1
    viz_dx = pitch_dx * viz_stride

    Create simple Matrix: "PLF_VizPitchData", viz_n, 1, "0"
    vizDataID = selected("Matrix")
    for v from 1 to viz_n
        original_frame = 1 + (v - 1) * viz_stride
        selectObject: vizDataID
        Set value: v, 1, pitch_midi#[original_frame]
    endfor

    Create Matrix: "PLF_SSM_View", pitch_tmin, pitch_tmax, viz_n, viz_dx, pitch_x1,
        ... pitch_tmin, pitch_tmax, viz_n, viz_dx, pitch_x1, "0"
    ssmViewID = selected("Matrix")
    tol$ = string$(pitch_tolerance_semitones)
    Formula: "if Matrix_PLF_VizPitchData[row,1] <= 0 and Matrix_PLF_VizPitchData[col,1] <= 0 then 0.65 else if Matrix_PLF_VizPitchData[row,1] > 0 and Matrix_PLF_VizPitchData[col,1] > 0 then max(0, 1 - abs(Matrix_PLF_VizPitchData[row,1] - Matrix_PLF_VizPitchData[col,1]) / " + tol$ + ") else 0 endif endif"

    Select outer viewport: 0, 4.15, 3.25, 5.70
    Select inner viewport: 0.55, 3.90, 3.45, 5.50
    selectObject: ssmViewID
    Paint cells: pitch_tmin, pitch_tmax, pitch_tmin, pitch_tmax, 0, 1
    Axes: pitch_tmin, pitch_tmax, pitch_tmin, pitch_tmax

    Colour: "{0.55, 0.55, 0.55}"
    Line width: 1
    Dotted line
    Draw line: pitch_tmin, pitch_tmin, pitch_tmax, pitch_tmax
    Solid line

    Line width: 2
    for k from 1 to loops_found
        if k = 1
            Colour: "{0.10, 0.35, 0.80}"
        elsif k = 2
            Colour: "{0.85, 0.30, 0.10}"
        elsif k = 3
            Colour: "{0.10, 0.60, 0.25}"
        elsif k = 4
            Colour: "{0.60, 0.20, 0.70}"
        else
            Colour: "{0.80, 0.10, 0.10}"
        endif
        Draw line: loop_t1[k], rep_t1[k], loop_t2[k], rep_t2[k]
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Repeat time (s)"
    Text bottom: "yes", "Source time (s)"

    # SSM title strip kept outside the data viewport.
    Select outer viewport: 0.55, 3.90, 3.20, 3.43
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Actual pitch self-similarity (dark = stronger match)"

    # --- Loop diagnostics / legend ---
    Select outer viewport: 4.20, 8, 3.25, 5.70
    Select inner viewport: 4.50, 7.75, 3.45, 5.50
    legend_n = min(loops_found, 6)
    Axes: 0, 1, 0, legend_n + 0.7
    Colour: "{0.97, 0.97, 0.97}"
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, legend_n + 0.7

    Font size: 7
    for k from 1 to legend_n
        y = legend_n - k + 0.55
        if k = 1
            col$ = "{0.20, 0.45, 0.72}"
        elsif k = 2
            col$ = "{0.78, 0.42, 0.20}"
        elsif k = 3
            col$ = "{0.28, 0.62, 0.35}"
        elsif k = 4
            col$ = "{0.58, 0.36, 0.66}"
        else
            col$ = "{0.45, 0.45, 0.45}"
        endif
        Paint rectangle: col$, 0.02, 0.05, y - 0.18, y + 0.18
        Colour: "Black"
        Text: 0.08, "left", y + 0.12, "half", "Loop " + string$(k) + ": " + fixed$(loop_t1[k], 2) + "-" + fixed$(loop_t2[k], 2) + " -> " + fixed$(rep_t1[k], 2) + "-" + fixed$(rep_t2[k], 2) + " s"
        Text: 0.08, "left", y - 0.14, "half", "score " + fixed$(loop_score[k], 1) + "/100 | voiced " + fixed$(loop_voiced[k], 2) + " | span " + fixed$(loop_span[k], 2) + " st"
    endfor
    Colour: "Black"
    Draw inner box

    Select outer viewport: 4.50, 7.75, 3.20, 3.43
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    if loops_found > legend_n
        Text: 0.5, "centre", 0.5, "half", "Detected loop pairs (showing first " + string$(legend_n) + ")"
    else
        Text: 0.5, "centre", 0.5, "half", "Detected loop pairs"
    endif

    # --- Summary bar ---
    Select outer viewport: 0, 8, 5.78, 6.18
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.5, "centre", 0.55, "half", "tol " + fixed$(pitch_tolerance_semitones, 2) + " st | break <= " + fixed$(max_break_duration, 2) + " s | voiced >= " + fixed$(min_voiced_fraction, 2) + " | search step " + fixed$(search_dt, 3) + " s | candidates " + string$(nRows) + " | selected " + string$(loops_found)

    Font size: 10
    Colour: "Black"
endif

# ===================================================================
# 6. CLEANUP & OUTPUT
# ===================================================================

if ssmViewID > 0
    removeObject: ssmViewID
endif
if vizDataID > 0
    removeObject: vizDataID
endif
removeObject: tableID, pitchID

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Selected ", loops_found, " loop pair(s)"
appendInfoLine: ""
appendInfoLine: "TextGrid shows:"
appendInfoLine: "  Tier 1 (Loops): source loop regions"
appendInfoLine: "  Tier 2 (Repeats): matched repeat regions"

selectObject: originalID
plusObject: textgridID

if open_textgrid_editor
    View & Edit
endif
