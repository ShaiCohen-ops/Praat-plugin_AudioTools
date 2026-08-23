# ============================================================
# Praat AudioTools - Rhythmatist.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.4 (2026) 
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   RHYTHMATIST - Rhythmic Strata System with Spectral Identity.
#   Splits audio into segments defined by a mathematical rhythmic
#   series (uniform, compound, cumulative, or combined), then
#   reassembles the segments in shuffled order to produce new
#   rhythmic structures from source material.
#
# Series types:
#   Su  - Uniform Regular: n equal durations
#   Sc  - Regular Compound: union of two uniform grids Su_a u Su_b
#   Sy  - Irregular Cumulative: n random cumulative split times
#   Sd  - Irregular Individual: n random durations, normalised
#   SRC - Combined: all four merged and deduplicated
#
# Generic parameter mapping (Param_a..e):
#   Su:   n = a
#   Sc:   a = a, b = b
#   Sy:   n = a
#   Sd:   n = a
#   SRC:  su = a, sca = b, scb = c, sy = d, sd = e
#
# Feature gating (no separate on/off toggles):
#   BPM quantize active when Bpm_value > 0
#   Pitch transposition active when Pitch_levels > 1
#   Stereo panning active when Stereo_width > 0
#
# v2.4 changelog (visualization precision pass):
#   * VISUALIZATION ONLY: preserves the existing waveform + original/shuffled
#     segment-order concept; no redesign of the musical visualization.
#   * FIX: source names are display-sanitized so underscores do not become
#     Praat subscripts.
#   * FIX: title/subtitle/footer bands explicitly reset their 0..1 world
#     coordinates, so text placement cannot inherit stale Sound/time axes.
#   * FIX: orig/shuf row labels now live in a dedicated physical left gutter
#     instead of being drawn outside the data axes where Praat clipped them.
#   * ALIGNMENT: Source and Result side labels use the same explicit rotated
#     label gutter rather than panel-height-dependent far-text placement.
#   * READABILITY: split-marker line width and segment-number labels adapt to
#     segmentation density; narrow cells are no longer forced to contain text.
#   * AXIS: Result now has numbered time marks, matching its Time (s) label.
#   * COLOUR: retains blue=original and orange=shuffled semantics, with a
#     slightly lighter dark-orange zebra shade for better balance.
#
# v2.3 changelog:
#   * API COMPATIBILITY: the entire public form is byte-for-byte unchanged.
#   * CRITICAL FIX: extracted segments are now zero-based (Preserve times=no).
#     v2.2 preserved each segment's original time domain, but transposeByRatio
#     later trimmed every segment at 0..segmentDuration; segment 2+ therefore
#     read outside their own domains when pitch processing was active.
#   * FIX: a private zero-based processing copy is always created, so sources
#     whose Sound domain starts at a non-zero time are handled correctly.
#   * FIX: Sy now creates n-1 independent random interior splits directly.
#     v2.2 generated n random points and then dropped the largest one, biasing
#     the distribution toward the start of the file. SRC uses the same
#     corrected n-segment convention for its Sy stratum.
#   * FIX: BPM snapping never manufactures a boundary at/after the sound end
#     when the source is shorter than two grid units. Endpoints and duplicate
#     snapped boundaries are removed cleanly.
#   * HARDENING: all final boundaries are separated from neighbours/endpoints
#     by at least one sample period; tiny random intervals are merged instead
#     of being silently discarded during extraction.
#   * HARDENING: split-complexity guard prevents pathological custom values
#     from creating tens of thousands of indexed variables/objects.
#
# v2.2 changelog:
#   * Form compacted from ~40 rows to ~21 rows. Feature booleans
#     replaced by "0 = off" conventions on the numeric parameters.
#     Ten series params collapsed to five generic ones.
#   * Seed field removed (it never truly seeded Praat's RNG).
#   * Show_split_points removed; info output is always on.
#   * Trim_to_grid removed; always trim when BPM is active.
#
# v2.1 features preserved: BPM-aware grid snapping (quarter / 8th /
#   triplet 8th / 16th / triplet 16th), beat + grid lines on the
#   waveform panel, tape-speed per-segment transposition, equal-
#   power per-segment panning, auto mono-convert for stereo inputs
#   when pitch/stereo processing is requested.
# ============================================================

form Rhythmatist v2.4
    optionmenu Preset 1
        option Custom
        option Simple Pulse   (Su n=8)
        option Binary Grid    (Sc 2+4)
        option Golden Split   (Sc 3+5)
        option Cloud          (Sy n=12)
        option Fragmented     (Sd n=16)
        option Dense Strata   (SRC)
    optionmenu Series_type 1
        option Su  - Uniform Regular
        option Sc  - Regular Compound (a + b)
        option Sy  - Irregular Cumulative
        option Sd  - Irregular Individual
        option SRC - Combined (Su+Sc+Sy+Sd)
    comment Params: Su/Sy/Sd use [a]; Sc uses [a,b]; SRC uses [a,b,c,d,e]
    natural Param_a 8
    natural Param_b 4
    natural Param_c 5
    natural Param_d 4
    natural Param_e 3
    comment BPM (0 = off); grid snaps splits to the pulse
    real Bpm_value 0
    optionmenu Grid_division 4
        option Quarter notes
        option Eighth notes
        option Triplet eighths
        option Sixteenth notes
        option Triplet sixteenths
    comment Pitch (levels=1 = off); step in semitones
    natural Pitch_levels 4
    real Pitch_step_semitones 7.0
    optionmenu Pitch_assign 1
        option Cycle
        option Alternating
        option Random
    comment Stereo (width=0 = off); equal-power panning
    real Stereo_width 0.8
    optionmenu Stereo_mode 1
        option Alternating L-R
        option Sweep L to R
        option Cycle 4-positions
        option Random
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# APPLY PRESETS (overrides series_type + params)
# ============================================================

if preset = 2
    series_type = 1
    param_a = 8
elsif preset = 3
    series_type = 2
    param_a = 2
    param_b = 4
elsif preset = 4
    series_type = 2
    param_a = 3
    param_b = 5
elsif preset = 5
    series_type = 3
    param_a = 12
elsif preset = 6
    series_type = 4
    param_a = 16
elsif preset = 7
    series_type = 5
    param_a = 3
    param_b = 2
    param_c = 5
    param_d = 4
    param_e = 3
endif

# ============================================================
# DERIVE FEATURE FLAGS from numeric "off" conventions
# ============================================================

bpm_quantize = (bpm_value > 0)
apply_pitch  = (pitch_levels > 1)
apply_stereo = (stereo_width > 0)

# ============================================================
# ALIAS PARAMS TO ORIGINAL SERIES NAMES
# (keeps the body logic readable and unchanged from v2.1)
# ============================================================

if series_type = 1
    su_n = param_a
elsif series_type = 2
    sc_a = param_a
    sc_b = param_b
elsif series_type = 3
    sy_n = param_a
elsif series_type = 4
    sd_n = param_a
else
    src_su  = param_a
    src_sca = param_b
    src_scb = param_c
    src_sy  = param_d
    src_sd  = param_e
endif

# ============================================================
# INPUT VALIDATION
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

sound      = selected("Sound")
soundName$ = selected$("Sound")
displayName$ = replace$(soundName$, "_", " ", 0)

selectObject: sound
nCh        = Get number of channels
sampleRate = Get sampling frequency
sourceStart = Get start time
t_total    = Get total duration
samplePeriod = 1 / sampleRate

if stereo_width > 1.0
    stereo_width = 1.0
endif
if pitch_levels < 1
    pitch_levels = 1
endif
if stereo_width < 0
    stereo_width = 0
endif
if pitch_step_semitones < -96 or pitch_step_semitones > 96
    exitScript: "Pitch step must be between -96 and +96 semitones"
endif

# ============================================================
# BPM / GRID SETUP
# ============================================================

if grid_division = 1
    units_per_beat = 1
    grid_label$    = "quarter"
elsif grid_division = 2
    units_per_beat = 2
    grid_label$    = "8th"
elsif grid_division = 3
    units_per_beat = 3
    grid_label$    = "triplet 8th"
elsif grid_division = 4
    units_per_beat = 4
    grid_label$    = "16th"
else
    units_per_beat = 6
    grid_label$    = "triplet 16th"
endif

if bpm_quantize
    beat_s          = 60 / bpm_value
    grid_interval_s = beat_s / units_per_beat
else
    beat_s          = 0
    grid_interval_s = 0
endif

# ============================================================
# TRIM TO GRID (always applied when BPM is active)
# A private zero-based processing copy is ALWAYS created. This makes every
# downstream boundary/segment calculation independent of the source xmin.
# ============================================================

createdTrim = 0
if bpm_quantize
    n_grid_units = floor(t_total / grid_interval_s)
    target_dur   = n_grid_units * grid_interval_s
    if target_dur > 0 and target_dur < t_total - 1e-6
        t_total = target_dur
        createdTrim = 1
    endif
else
    n_grid_units = 0
endif

selectObject: sound
processingSound = Extract part: sourceStart, sourceStart + t_total, "rectangular", 1, "no"
if createdTrim
    Rename: soundName$ + "_gridtrim"
else
    Rename: soundName$ + "_rhythmatist_work"
endif

# ============================================================
# MONO WORKING COPY (only when pitch or stereo is requested)
# ============================================================

createdMono = 0
if apply_pitch or apply_stereo
    if nCh > 1
        selectObject: processingSound
        workingSound = Convert to mono
        createdMono = 1
    else
        workingSound = processingSound
    endif
else
    workingSound = processingSound
endif

# ============================================================
# SERIES LABEL
# ============================================================

if series_type = 1
    seriesLabel$ = "Su_" + string$(su_n)
elsif series_type = 2
    seriesLabel$ = "Sc_(" + string$(sc_a) + "+" + string$(sc_b) + ")"
elsif series_type = 3
    seriesLabel$ = "Sy_" + string$(sy_n)
elsif series_type = 4
    seriesLabel$ = "Sd_" + string$(sd_n)
else
    seriesLabel$ = "SRC"
endif
seriesDisplay$ = replace$(seriesLabel$, "_", " ", 0)

# ============================================================
# INFO HEADER
# ============================================================

writeInfoLine:  "=== RHYTHMATIST v2.4 ==="
appendInfoLine: "Source:  ", soundName$, "  (", fixed$(t_total, 3), " s)"
appendInfoLine: "Series:  ", seriesLabel$
if bpm_quantize
    appendInfoLine: "BPM:     ", fixed$(bpm_value, 1), "   grid=", grid_label$,
    ...             "   (beat=", fixed$(beat_s, 4), " s   unit=", fixed$(grid_interval_s, 4), " s)"
    if createdTrim
        appendInfoLine: "Trim:    source trimmed to ", n_grid_units, " x ", grid_label$, " (", fixed$(t_total, 4), " s)"
    endif
endif
if apply_pitch
    appendInfoLine: "Pitch:   ", pitch_levels, " levels   step=", fixed$(pitch_step_semitones, 1), " st   assign=", pitch_assign$
endif
if apply_stereo
    appendInfoLine: "Stereo:  mode=", stereo_mode$, "   width=", fixed$(stereo_width, 2)
endif
appendInfoLine: ""

# ============================================================
# BUILD NORMALISED SPLIT-POINT ARRAY
# ============================================================

# Upper bound on interior split points before de-duplication.
if series_type = 1
    expectedPts = su_n - 1
elsif series_type = 2
    expectedPts = sc_a + sc_b - 2
elsif series_type = 3
    expectedPts = sy_n - 1
elsif series_type = 4
    expectedPts = sd_n - 1
else
    expectedPts = (src_su - 1) + (src_sca - 1) + (src_scb - 1) + (src_sy - 1) + (src_sd - 1)
endif
if expectedPts > 5000
    exitScript: "Too many requested split points (maximum 5000 before de-duplication)"
endif

maxPts = max(1, expectedPts + 2)
for i from 1 to maxPts
    tk[i] = -1
endfor
nPts = 0

procedure insertSorted: .v
    .pos = nPts + 1
    .i   = 1
    while .i <= nPts
        if tk[.i] >= .v
            .pos = .i
            .i   = nPts + 1
        else
            .i = .i + 1
        endif
    endwhile
    .j = nPts
    while .j >= .pos
        tk[.j + 1] = tk[.j]
        .j = .j - 1
    endwhile
    tk[.pos] = .v
    nPts = nPts + 1
endproc

procedure deduplicate
    prev = -1
    newN = 0
    for i from 1 to nPts
        if abs(tk[i] - prev) > 1e-9
            newN += 1
            tk2[newN] = tk[i]
            prev = tk[i]
        endif
    endfor
    nPts = newN
    for i from 1 to nPts
        tk[i] = tk2[i]
    endfor
endproc

# ============================================================
# COMPUTE SPLIT POINTS (normalised 0..1)
# ============================================================

if series_type = 1
    for k from 1 to su_n - 1
        nPts += 1
        tk[nPts] = k / su_n
    endfor

elsif series_type = 2
    for k from 1 to sc_a - 1
        @insertSorted: k / sc_a
    endfor
    for k from 1 to sc_b - 1
        @insertSorted: k / sc_b
    endfor
    @deduplicate

elsif series_type = 3
    if sy_n > 1
        for k from 1 to sy_n - 1
            v = randomUniform(0, 1)
            @insertSorted: v
        endfor
    endif

elsif series_type = 4
    t_d = 0
    for k from 1 to sd_n
        dd[k] = randomUniform(0, 1)
        t_d += dd[k]
    endfor
    cumT = 0
    for k from 1 to sd_n - 1
        cumT += dd[k] / t_d
        nPts += 1
        tk[nPts] = cumT
    endfor

elsif series_type = 5
    for k from 1 to src_su - 1
        @insertSorted: k / src_su
    endfor
    for k from 1 to src_sca - 1
        @insertSorted: k / src_sca
    endfor
    for k from 1 to src_scb - 1
        @insertSorted: k / src_scb
    endfor
    if src_sy > 1
        for k from 1 to src_sy - 1
            v = randomUniform(0, 1)
            @insertSorted: v
        endfor
    endif
    t_d = 0
    for k from 1 to src_sd
        dd[k] = randomUniform(0, 1)
        t_d += dd[k]
    endfor
    cumT = 0
    for k from 1 to src_sd - 1
        cumT += dd[k] / t_d
        @insertSorted: cumT
    endfor
    @deduplicate
    newN = 0
    for i from 1 to nPts
        if tk[i] > 1e-9 and tk[i] < 1.0 - 1e-9
            newN += 1
            tk2[newN] = tk[i]
        endif
    endfor
    nPts = newN
    for i from 1 to nPts
        tk[i] = tk2[i]
    endfor
endif

# === Convert to absolute seconds ===
nSegments = nPts + 1
for i from 1 to nPts
    boundary[i] = tk[i] * t_total
endfor

# ============================================================
# GRID SNAPPING
# ============================================================

if bpm_quantize
    # If there are fewer than two grid units, no interior grid boundary exists.
    if n_grid_units < 2
        nPts = 0
    else
        newN = 0
        prev_b = -1
        for i from 1 to nPts
            snapped = round(boundary[i] / grid_interval_s) * grid_interval_s
            # Keep only true interior points. Rounding is monotonic because the
            # incoming boundaries are sorted, so one pass can also de-duplicate.
            if snapped > samplePeriod * 0.5 and snapped < t_total - samplePeriod * 0.5
                if newN = 0 or abs(snapped - prev_b) > samplePeriod * 0.5
                    newN += 1
                    boundary_tmp[newN] = snapped
                    prev_b = snapped
                endif
            endif
        endfor
        nPts = newN
        for i from 1 to nPts
            boundary[i] = boundary_tmp[i]
            tk[i] = boundary[i] / t_total
        endfor
    endif
endif

# Final one-sample boundary sanitation for ALL series. This merges accidental
# sub-sample random intervals instead of silently dropping their audio later.
newN = 0
prev_b = 0
for i from 1 to nPts
    b = boundary[i]
    if b - prev_b >= samplePeriod and t_total - b >= samplePeriod
        newN += 1
        boundary_tmp[newN] = b
        prev_b = b
    endif
endfor
nPts = newN
for i from 1 to nPts
    boundary[i] = boundary_tmp[i]
    tk[i] = boundary[i] / t_total
endfor
nSegments = nPts + 1

# === Report split points ===
appendInfoLine: "--- Split points ---"
prev_t  = 0
prev_tk = 0
for i from 1 to nPts
    d_s  = boundary[i] - prev_t
    d_tk = tk[i] - prev_tk
    if bpm_quantize
        beat_pos = boundary[i] / beat_s
        unit_idx = round(boundary[i] / grid_interval_s)
        appendInfoLine: "k=", i, "   t=", fixed$(boundary[i], 4), " s",
        ...             "   beat=", fixed$(beat_pos, 3),
        ...             "   unit=", unit_idx,
        ...             "   D=", fixed$(d_s, 4), " s"
    else
        appendInfoLine: "k=", i, "   T_k=", fixed$(tk[i], 6),
        ...             "   t=", fixed$(boundary[i], 6), " s",
        ...             "   D_k=", fixed$(d_tk, 6)
    endif
    prev_t  = boundary[i]
    prev_tk = tk[i]
endfor
appendInfoLine: "Total segments: ", nSegments
appendInfoLine: ""

# ============================================================
# PROCEDURES
# ============================================================

procedure trimTo: .snd, .tDur
    selectObject: .snd
    .d  = Get total duration
    .sr = Get sampling frequency
    .nc = Get number of channels
    if .d >= .tDur
        trimResult = Extract part: 0, .tDur, "rectangular", 1, "no"
    else
        .ext = .tDur - .d
        .pad = Create Sound from formula: "pad", .nc, 0, .ext, .sr, "0"
        selectObject: .snd
        plusObject: .pad
        trimResult = Concatenate
        removeObject: .pad
    endif
endproc

procedure transposeByRatio: .snd, .ratio
    if abs(.ratio - 1.0) < 1e-6
        selectObject: .snd
        transposeResult = Copy: "rhy_ps_noop"
    else
        selectObject: .snd
        .intendedDur = Get total duration
        .sr = Get sampling frequency
        .tmp = Copy: "rhy_ps_tmp"
        selectObject: .tmp
        Override sampling frequency: round(.sr * .ratio)
        .shifted = Resample: .sr, 50
        removeObject: .tmp
        @trimTo: .shifted, .intendedDur
        removeObject: .shifted
        transposeResult = trimResult
    endif
endproc

procedure makeStereo: .left, .right
    selectObject: .left
    plusObject: .right
    stereoResult = Combine to stereo
endproc

procedure panMono: .snd, .pan
    .theta  = (.pan + 1) / 2 * pi / 2
    .lGain  = cos(.theta)
    .rGain  = sin(.theta)
    selectObject: .snd
    .left  = Copy: "pan_L"
    selectObject: .snd
    .right = Copy: "pan_R"
    selectObject: .left
    Formula: "self * " + string$(.lGain)
    selectObject: .right
    Formula: "self * " + string$(.rGain)
    @makeStereo: .left, .right
    removeObject: .left, .right
    panResult = stereoResult
endproc

# ============================================================
# EXTRACT SEGMENTS
# ============================================================

segStart = 0
nCreated = 0
for seg from 1 to nSegments
    if seg <= nPts
        segEnd = boundary[seg]
    else
        segEnd = t_total
    endif

    if segEnd - segStart >= samplePeriod * 0.5
        selectObject: workingSound
        # Internal processing segments must start at zero because pitch/trim
        # procedures address them as 0..segmentDuration.
        Extract part: segStart, segEnd, "rectangular", 1, "no"
        nCreated += 1
        partId[nCreated]   = selected("Sound")
        segIndex[nCreated] = seg
    endif

    segStart = segEnd
endfor

appendInfoLine: "Extracted ", nCreated, " segments"

# ============================================================
# FISHER-YATES SHUFFLE
# Praat Concatenate follows ascending object-ID order, so we
# concatenate iteratively (end->start) to enforce shuffled order.
# ============================================================

i = nCreated
while i >= 2
    j = randomInteger(1, i)
    swapTmp     = partId[i]
    partId[i]   = partId[j]
    partId[j]   = swapTmp
    swapIdx     = segIndex[i]
    segIndex[i] = segIndex[j]
    segIndex[j] = swapIdx
    i -= 1
endwhile

appendInfoLine: "--- Shuffled order ---"
for i from 1 to nCreated
    appendInfoLine: "  pos ", i, "  <-  original segment ", segIndex[i]
endfor
appendInfoLine: ""

# ============================================================
# PER-SEGMENT PITCH TRANSPOSITION AND STEREO SPATIALIZATION
# ============================================================

if apply_pitch or apply_stereo
    appendInfoLine: "--- Per-segment pitch / stereo ---"
    appendInfoLine: "  seg   pitchLv   semitones   ratio     pan"

    for i from 1 to nCreated
        origSeg = segIndex[i]

        # ------ PITCH ------
        if apply_pitch
            if pitch_assign = 1
                pitchLevel = (origSeg - 1) mod pitch_levels
            elsif pitch_assign = 2
                pitchLevel = (origSeg - 1) mod 2
            else
                pitchLevel = randomInteger(0, pitch_levels - 1)
            endif

            semitones  = pitchLevel * pitch_step_semitones
            pitchRatio = 2 ^ (semitones / 12)

            @transposeByRatio: partId[i], pitchRatio
            removeObject: partId[i]
            partId[i] = transposeResult
        else
            pitchLevel = 0
            semitones  = 0
            pitchRatio = 1.0
        endif

        # ------ STEREO ------
        if apply_stereo
            if stereo_mode = 1
                if origSeg mod 2 = 1
                    panVal = -stereo_width
                else
                    panVal = stereo_width
                endif
            elsif stereo_mode = 2
                if nSegments > 1
                    panVal = ((origSeg - 1) / (nSegments - 1) * 2 - 1) * stereo_width
                else
                    panVal = 0
                endif
            elsif stereo_mode = 3
                posIdx = (origSeg - 1) mod 4
                if posIdx = 0
                    panVal = -1.00 * stereo_width
                elsif posIdx = 1
                    panVal = -0.33 * stereo_width
                elsif posIdx = 2
                    panVal =  0.33 * stereo_width
                else
                    panVal =  1.00 * stereo_width
                endif
            else
                panVal = randomUniform(-1, 1) * stereo_width
            endif

            @panMono: partId[i], panVal
            removeObject: partId[i]
            partId[i] = panResult
        else
            panVal = 0
        endif

        appendInfoLine: "  ", origSeg, "   lv=", pitchLevel,
        ...             "   ", fixed$(semitones, 1), " st",
        ...             "   x", fixed$(pitchRatio, 3),
        ...             "   pan=", fixed$(panVal, 2)
    endfor

    appendInfoLine: ""
endif

# ============================================================
# CONCATENATE IN SHUFFLED ORDER (end->start walk)
# ============================================================

if nCreated > 1
    selectObject: partId[nCreated]
    Copy: "rhythmatist_build"
    buildId = selected("Sound")

    i = nCreated - 1
    while i >= 1
        selectObject: partId[i]
        plusObject: buildId
        Concatenate
        newBuild = selected("Sound")
        removeObject: buildId
        buildId = newBuild
        i -= 1
    endwhile

    selectObject: buildId
    Rename: soundName$ + "_rhythmatist"
    result = selected("Sound")

elsif nCreated = 1
    selectObject: partId[1]
    Copy: soundName$ + "_rhythmatist"
    result = selected("Sound")

else
    exitScript: "No segments created - audio may be too short."
endif

# ============================================================
# CLEANUP
# ============================================================

for i from 1 to nCreated
    removeObject: partId[i]
endfor

if createdMono = 1
    removeObject: workingSound
endif

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all

    # Title
    Select outer viewport: 1, 8, 0.2, 0.7
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "RHYTHMATIST v2.4: " + displayName$

    # Subtitle
    Select outer viewport: 1, 8, 0.6, 1.0
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "{0.4, 0.4, 0.4}"
    pitchSub$ = ""
    if apply_pitch
        pitchSub$ = "   pitch: " + string$(pitch_levels) + "x" + fixed$(pitch_step_semitones, 0) + "st"
    endif
    stereoSub$ = ""
    if apply_stereo
        stereoSub$ = "   stereo: " + stereo_mode$
    endif
    bpmSub$ = ""
    if bpm_quantize
        bpmSub$ = "   " + fixed$(bpm_value, 0) + " BPM " + grid_label$
    endif
    Text: 0.5, "centre", 0.5, "half",
    ... "Series: " + seriesDisplay$
    ... + "   |   " + string$(nSegments) + " segs"
    ... + "   |   T=" + fixed$(t_total, 3) + " s"
    ... + bpmSub$ + pitchSub$ + stereoSub$

    # Original waveform with (optionally) beat + grid + split markers
    Select outer viewport: 0, 8, 1.0, 2.5
    Select inner viewport: 0.6, 7.6, 1.1, 2.4
    selectObject: processingSound
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Axes: 0, t_total, -1, 1

    if bpm_quantize
        Colour: "{0.85, 0.85, 0.65}"
        Line width: 1
        Dotted line
        grid_t = grid_interval_s
        while grid_t < t_total - 1e-6
            Draw line: grid_t, -1, grid_t, 1
            grid_t = grid_t + grid_interval_s
        endwhile
        Solid line

        Colour: "{0.65, 0.65, 0.35}"
        Line width: 1
        beat_t = beat_s
        while beat_t < t_total - 1e-6
            Draw line: beat_t, -1, beat_t, 1
            beat_t = beat_t + beat_s
        endwhile
    endif

    Colour: "{1, 0.3, 0.3}"
    if nPts > 40
        Line width: 1
    else
        Line width: 2
    endif
    for i from 1 to nPts
        Draw line: boundary[i], -1, boundary[i], 1
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box

    # Explicit left label gutter: same physical x anchor as Result below.
    Select outer viewport: 0.05, 0.55, 1.1, 2.4
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.50, "centre", 0.50, "half", "Times", 7, "90", "Source"

    # Segment-order diagram
    Select outer viewport: 0, 8, 2.6, 3.8
    Select inner viewport: 0.6, 7.6, 2.65, 3.75
    Axes: 0, t_total, 0, 2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, t_total, 0, 2

    prevT = 0
    for seg from 1 to nSegments
        if seg <= nPts
            segEndV = boundary[seg]
        else
            segEndV = t_total
        endif
        if seg mod 2 = 1
            Paint rectangle: "{0.55, 0.75, 0.9}", prevT + 0.001, segEndV - 0.001, 1.05, 1.95
        else
            Paint rectangle: "{0.25, 0.55, 0.75}", prevT + 0.001, segEndV - 0.001, 1.05, 1.95
        endif
        if (segEndV - prevT) >= 0.035 * t_total
            Font size: 6
            Colour: "White"
            Text: (prevT + segEndV) / 2, "centre", 1.5, "half", string$(seg)
        endif
        prevT = segEndV
    endfor

    drawPos = 0
    for i from 1 to nCreated
        origSeg = segIndex[i]
        if origSeg = 1
            segStartOrig = 0
        else
            segStartOrig = boundary[origSeg - 1]
        endif
        if origSeg <= nPts
            segEndOrig = boundary[origSeg]
        else
            segEndOrig = t_total
        endif
        segDurI = segEndOrig - segStartOrig

        if origSeg mod 2 = 1
            Paint rectangle: "{0.85, 0.6, 0.25}", drawPos + 0.001, drawPos + segDurI - 0.001, 0.05, 0.95
        else
            Paint rectangle: "{0.78, 0.45, 0.16}",  drawPos + 0.001, drawPos + segDurI - 0.001, 0.05, 0.95
        endif
        if segDurI >= 0.035 * t_total
            Font size: 6
            Colour: "White"
            Text: drawPos + segDurI / 2, "centre", 0.5, "half", string$(origSeg)
        endif

        drawPos += segDurI
    endfor

    Colour: "{0.7, 0.7, 0.7}"
    Draw line: 0, 1, t_total, 1
    Colour: "Black"
    Draw inner box

    # Dedicated row-label gutter (never clipped by the data axes).
    Select outer viewport: 0.05, 0.55, 2.65, 3.75
    Axes: 0, 1, 0, 2
    Font size: 7
    Colour: "{0.25, 0.55, 0.75}"
    Text: 0.95, "right", 1.5, "half", "orig"
    Colour: "{0.78, 0.45, 0.16}"
    Text: 0.95, "right", 0.5, "half", "shuf"

    # Result waveform
    Select outer viewport: 0, 8, 3.9, 5.4
    Select inner viewport: 0.6, 7.6, 4.0, 5.3
    selectObject: result
    resultNch = Get number of channels
    if resultNch > 1
        vizL = Extract one channel: 1
        selectObject: result
        vizR = Extract one channel: 2
        selectObject: vizL
        Colour: "{0.2, 0.5, 0.7}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        selectObject: vizR
        Colour: "{0.75, 0.25, 0.15}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        removeObject: vizL, vizR
    else
        selectObject: result
        Colour: "{0.2, 0.5, 0.7}"
        Draw: 0, 0, 0, 0, "no", "Curve"
    endif
    Axes: 0, t_total, -1, 1
    Colour: "Black"
    Draw inner box
    Font size: 8
    Marks bottom: 7, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"

    # Explicit result label gutter, aligned with Source above.
    Select outer viewport: 0.05, 0.55, 4.0, 5.3
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    if resultNch > 1
        Text special: 0.50, "centre", 0.50, "half", "Times", 7, "90", "Result L/R"
    else
        Text special: 0.50, "centre", 0.50, "half", "Times", 7, "90", "Result"
    endif

    # Legend
    Select outer viewport: 1, 8, 5.5, 5.9
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half",
    ... seriesDisplay$
    ... + "   |   " + string$(nCreated) + " segments shuffled"
    ... + bpmSub$ + pitchSub$ + stereoSub$

    Font size: 10
    Colour: "Black"
endif

# ============================================================
# FINAL INFO
# ============================================================

selectObject: result
resultDuration = Get total duration

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Original:  ", fixed$(t_total, 3), " s"
appendInfoLine: "Result:    ", fixed$(resultDuration, 3), " s"
appendInfoLine: "Created:   ", selected$("Sound")

# ============================================================
# CLEANUP TRIMMED SOURCE
# ============================================================

removeObject: processingSound

# ============================================================
# PLAY
# ============================================================

if play_result
    selectObject: result
    Play
endif

selectObject: result
