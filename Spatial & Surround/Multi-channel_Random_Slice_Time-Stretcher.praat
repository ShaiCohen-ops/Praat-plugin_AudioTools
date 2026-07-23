# ============================================================
# Praat AudioTools - Multi-channel_Random_Slice_Time-Stretcher.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Multi-channel audio from random time-stretched slices.
#     1. Extract N random slices from the source (random position and
#        length).
#     2. Time-stretch each with PSOLA, aiming to preserve pitch.
#     3. Place each stretched slice centred on its original position.
#     4. Route the slices to output channels.
#
#   PSOLA preserves pitch on suitably periodic or monophonic material.
#   Polyphonic, noisy or transient-heavy sources will show artefacts.
#
# Changelog v1.1 (2026):
#   - FIX: the padding formula was inverted. duration_factor is a
#     DURATION factor inside the DurationTier, so a slice becomes
#     L * r long, but the script reserved L_max / r. The two are only
#     equal at r = 1, and the direction is backwards for every other
#     value.
#     Worth being precise about the consequence, because the obvious
#     reading overstates it. Placement is CENTRED, so only half the
#     added length extends past the source: the latest possible slice
#     end is D + L(r-1)/2, and truncation needs r^2 - r - 2 > 0, i.e.
#     r > 2. With the five shipped presets (r <= 2) nothing was
#     actually cut - r = 2 sits exactly on the boundary with zero
#     margin. What the bug DID cause was the opposite: at Fast the
#     output ran 3.3 s longer than the last slice, and at Double speed
#     4.5 s longer, all of it silence. The formula is still wrong and
#     would truncate the moment a factor above 2 appeared.
#     Both are gone: the output length is now taken from the measured
#     end of the latest slice, so nothing is cut and nothing is padded
#     for no reason.
#   - FIX: stereo input was split arbitrarily. Channel 1 came from the
#     LEFT channel of the source while every slice came from the RIGHT,
#     so with Mix_original on, the "original" and the slices were
#     different signals - undocumented, and not what the form implies.
#     Sources with more than two channels fell into the mono branch and
#     were copied whole. Input is now downmixed to mono by default, with
#     explicit Left-only and Right-only options.
#   - FIX: every slice was individually normalised to 0.99 inside the
#     PSOLA procedure, so a slice peaking at 0.01 in the source came out
#     at the same level as one peaking at 0.9 - a 99x boost that erased
#     the source dynamics and lifted noise out of quiet passages. The
#     per-slice normalisation is gone; Slice_level_mode offers Preserve
#     source level (default) or Normalise each slice for the old
#     behaviour.
#   - FIX: slices were cut with rectangular windows and dropped into
#     silence, so each one began and ended on whatever sample value it
#     happened to hit. That matters more here than in Time Polyphony,
#     because every channel is an isolated event surrounded by silence:
#     both edges are exposed. Short raised-cosine fades are now applied
#     to each slice, clamped to 10% of its own length.
#   - FIX: no random seed, so a good result could not be reproduced.
#     Random_seed 0 stays unpredictable; a positive value seeds Praat's
#     generator and is reported, so a take can be recovered later.
#   - FIX: the time domain was not normalised to 0. Slice positions were
#     drawn between 0 and the duration while Extract part worked in the
#     object's own time, so anything with preserved times mismatched.
#   - FIX: the Normal preset still ran a full PSOLA round trip at
#     r = 1.0 - a Manipulation, a DurationTier and a resynthesis that
#     cannot change the length but can alter the signal, add artefacts
#     and fail on material without stable pitch. At r = 1 the extracted
#     slice is now used directly, so Normal is a true copy of the source
#     region apart from the edge fades.
#   - FIX: pitch floor and ceiling were hard-coded at 75 and 600 Hz.
#     Both are form fields now, validated floor < ceiling.
#   - FIX: Number_of_segments was declared positive, so a fractional
#     value was accepted for something that is a count of slices and of
#     output channels. It is natural now, with a warning past 32
#     channels.
#   - CLARIFIED: a slice whose centred placement would start before
#     zero is shifted right rather than clipped, so it is no longer
#     centred on its source position. That is the right trade - the
#     whole slice survives - but it was not stated anywhere.
#   - NEW: Output_routing. N-channel stems is the v1.0 behaviour and
#     still the default; the alternatives fold the slices into fixed
#     layouts for systems that do not have N outputs.
#   - NEW: Output_normalisation - Peak, Attenuate only, or None.
#   - FIX (plot): the coloured slice regions were painted OVER the
#     waveform, so the waveform vanished inside them. The regions are
#     painted first and the waveform drawn on top.
#   - FIX (plot): the table column headed "Stretch" showed a duration in
#     seconds, not a factor. It now shows the stretched duration and the
#     achieved factor, so PSOLA can be checked against the request.
#   - FIX (plot): with more than 8 slices the table silently showed the
#     first 8. It now says so.
#   - The v1.0 header called this an "8-panel visualization"; the layout
#     is not eight fixed panels. Corrected.
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object first."
endif

form Multi-channel Random Slice Time-Stretcher v1.1
    comment === Slice Parameters ===
    natural Number_of_segments 4
    real Min_duration 0.5
    real Max_duration 2.0
    integer Random_seed 0

    comment === Time-Stretching (duration factor: >1 longer, <1 shorter) ===
    optionmenu Preset: 1
        option: "Normal (1.0, no PSOLA)"
        option: "Slow (1.5)"
        option: "Fast (0.67)"
        option: "Double speed (0.5)"
        option: "Half speed (2.0)"
        option: "Custom (use value below)"
    positive Custom_factor 1.25
    positive Pitch_floor 75
    positive Pitch_ceiling 600

    comment === Levels ===
    optionmenu Slice_level_mode: 1
        option: "Preserve source level"
        option: "Normalise each slice (the v1.0 behaviour)"
    positive Slice_edge_fade_ms 10

    comment === Output ===
    optionmenu Output_routing: 1
        option: "N-channel stems (one slice per channel)"
        option: "Stereo, alternating L/R"
        option: "Stereo, fixed random pan per slice"
        option: "Quad, cyclic routing"
        option: "8-channel, cyclic routing"
        option: "Mono sum"
    boolean Mix_original_channel_1 0
    optionmenu Input_handling: 1
        option: "Downmix to mono"
        option: "Use left channel only"
        option: "Use right channel only"
    boolean Preserve_original_timeline_length 1
    optionmenu Output_normalisation: 1
        option: "Peak (scale to target)"
        option: "Attenuate only (never boost)"
        option: "None"
    real Peak_target 0.99

    comment === Visualization ===
    boolean Draw_visualization 1
    boolean Play_after_processing 1
endform

if preset = 1
    duration_factor = 1.0
    presetName$ = "Normal"
elsif preset = 2
    duration_factor = 1.5
    presetName$ = "Slow"
elsif preset = 3
    duration_factor = 0.67
    presetName$ = "Fast"
elsif preset = 4
    duration_factor = 0.5
    presetName$ = "DoubleSpeed"
elsif preset = 5
    duration_factor = 2.0
    presetName$ = "HalfSpeed"
else
    duration_factor = custom_factor
    presetName$ = "Custom"
endif

if pitch_floor >= pitch_ceiling
    exitScript: "Pitch_floor (", pitch_floor, ") must be below Pitch_ceiling (",
        ... pitch_ceiling, ")."
endif
if min_duration <= 0 or max_duration <= 0
    exitScript: "Durations must be positive numbers."
endif
if min_duration > max_duration
    exitScript: "Minimum duration cannot be larger than maximum duration."
endif
if duration_factor <= 0
    exitScript: "Duration factor must be greater than 0."
endif
if peak_target <= 0 or peak_target > 1
    peak_target = 0.99
endif
if slice_edge_fade_ms < 0
    slice_edge_fade_ms = 0
endif
edgeFade = slice_edge_fade_ms / 1000

# v1.1: seed the generator so a good take can be recovered.
if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    seedApplied = 1
else
    random_initializeSafelyAndUnpredictably ()
    seedApplied = 0
endif

orig_id = selected("Sound")
orig_name$ = selected$("Sound")
selectObject: orig_id
fs = Get sampling frequency
nchan = Get number of channels
srcT0 = Get start time
srcT1 = Get end time

# ============================================================
# WORKING SOURCE: one mono signal, starting at t = 0
# ============================================================
# v1.1: v1.0 took the original channel from the LEFT and every slice
# from the RIGHT, and copied a >2-channel object whole into the mono
# branch. One source now feeds both.
if nchan = 1
    selectObject: orig_id
    Copy: "rs_src"
    src_id = selected("Sound")
    inputNote$ = "mono source"
elsif input_handling = 2
    selectObject: orig_id
    Extract one channel: 1
    src_id = selected("Sound")
    inputNote$ = "left channel of a " + string$(nchan) + "-channel source"
elsif input_handling = 3
    selectObject: orig_id
    Extract one channel: 2
    src_id = selected("Sound")
    inputNote$ = "right channel of a " + string$(nchan) + "-channel source"
else
    selectObject: orig_id
    Convert to mono
    src_id = selected("Sound")
    inputNote$ = "downmix of a " + string$(nchan) + "-channel source"
endif

selectObject: src_id
workT0 = Get start time
if workT0 <> 0
    selectObject: src_id
    shifted_id = Extract part: workT0, srcT1, "rectangular", 1.0, "no"
    removeObject: src_id
    src_id = shifted_id
endif
selectObject: src_id
Rename: "rs_src"
total_duration = Get total duration

if total_duration <= 0
    removeObject: src_id
    exitScript: "Source has zero duration."
endif
if max_duration > total_duration
    max_duration = total_duration
    if min_duration > max_duration
        min_duration = max_duration
    endif
    durClamped = 1
else
    durClamped = 0
endif

# ============================================================
# SLICE GENERATION
# ============================================================
# v1.1: no Scale peak inside the procedure - that erased the source
# dynamics - and no PSOLA at all when the factor is exactly 1, where
# the round trip cannot change the length but can change the signal.

procedure stretchSlice: .inID, .factor
    selectObject: .inID
    .dur = Get total duration
    if abs(.factor - 1) < 1e-9
        selectObject: .inID
        Copy: "rs_stretched"
        .outID = selected("Sound")
        .usedPsola = 0
    else
        selectObject: .inID
        .manip = To Manipulation: 0.01, pitch_floor, pitch_ceiling
        .dtier = Create DurationTier: "rs_dur", 0, .dur
        Add point: 0, .factor
        Add point: .dur, .factor
        selectObject: .manip, .dtier
        Replace duration tier
        selectObject: .manip
        .outID = Get resynthesis (overlap-add)
        Rename: "rs_stretched"
        removeObject: .dtier, .manip
        .usedPsola = 1
    endif

    if slice_level_mode = 2
        selectObject: .outID
        Scale peak: 0.99
    endif

    # v1.1: raised-cosine edges. Every channel here is an isolated
    # event surrounded by silence, so both ends are exposed.
    selectObject: .outID
    .odur = Get total duration
    .f = edgeFade
    if .f > .odur * 0.1
        .f = .odur * 0.1
    endif
    if .f > 0
        selectObject: .outID
        Fade in: 0, 0, .f, "yes"
        selectObject: .outID
        Fade out: 0, .odur, -.f, "yes"
    endif
endproc

nSeg = number_of_segments
slice_source_start# = zero#(nSeg)
slice_source_end# = zero#(nSeg)
slice_original_dur# = zero#(nSeg)
slice_stretched_dur# = zero#(nSeg)
slice_target_start# = zero#(nSeg)
slice_target_end# = zero#(nSeg)
slice_achieved# = zero#(nSeg)
slice_shifted# = zero#(nSeg)
slice_pan# = zero#(nSeg)

stopwatch
psolaCount = 0
shiftedCount = 0
latestEnd = 0

for i to nSeg
    seg_len = randomUniform(min_duration, max_duration)
    max_start = total_duration - seg_len
    if max_start < 0
        max_start = 0
    endif
    win_start = randomUniform(0, max_start)
    win_end = win_start + seg_len
    if win_end > total_duration
        win_end = total_duration
    endif

    slice_source_start#[i] = win_start
    slice_source_end#[i] = win_end
    slice_original_dur#[i] = win_end - win_start

    selectObject: src_id
    seg_id = Extract part: win_start, win_end, "rectangular", 1, "no"

    @stretchSlice: seg_id, duration_factor
    stretched_id = stretchSlice.outID
    psolaCount = psolaCount + stretchSlice.usedPsola

    selectObject: stretched_id
    stretched_dur = Get total duration
    slice_stretched_dur#[i] = stretched_dur
    if slice_original_dur#[i] > 0
        slice_achieved#[i] = stretched_dur / slice_original_dur#[i]
    else
        slice_achieved#[i] = duration_factor
    endif

    # Centred on the source position where possible. If that would
    # start before zero the slice is shifted right instead of being
    # clipped, so the whole slice survives but is no longer centred.
    original_center = win_start + (win_end - win_start) / 2
    target_start = original_center - stretched_dur / 2
    if target_start < 0
        target_start = 0
        slice_shifted#[i] = 1
        shiftedCount = shiftedCount + 1
    endif

    slice_target_start#[i] = target_start
    slice_target_end#[i] = target_start + stretched_dur
    if slice_target_end#[i] > latestEnd
        latestEnd = slice_target_end#[i]
    endif

    slice_pan#[i] = randomUniform(0, 1)
    sliceID[i] = stretched_id
    removeObject: seg_id
endfor
sliceElapsed = stopwatch

# ============================================================
# OUTPUT LENGTH
# ============================================================
# v1.1: measured from where the slices actually end, not from an
# inverted padding formula.
outDur = latestEnd
if preserve_original_timeline_length or mix_original_channel_1
    if total_duration > outDur
        outDur = total_duration
    endif
endif
if outDur < 0.01
    outDur = 0.01
endif
v10Dur = total_duration + max_duration / duration_factor

# ============================================================
# ROUTING
# ============================================================
if output_routing = 1
    nOut = nSeg
    routeName$ = "N-channel stems"
elsif output_routing = 2
    nOut = 2
    routeName$ = "stereo, alternating L/R"
elsif output_routing = 3
    nOut = 2
    routeName$ = "stereo, fixed random pan per slice"
elsif output_routing = 4
    nOut = 4
    routeName$ = "quad, cyclic"
elsif output_routing = 5
    nOut = 8
    routeName$ = "8-channel, cyclic"
else
    nOut = 1
    routeName$ = "mono sum"
endif

origChannel = 0
if mix_original_channel_1
    origChannel = 1
    nOut = nOut + 1
endif

for o from 1 to nOut
    Create Sound from formula: "rs_out" + string$(o), 1, 0, outDur, fs, "0"
    outCh[o] = selected("Sound")
endfor

# Channel 1 carries the original when requested - now the SAME mono
# signal the slices came from, not the other stereo channel.
if mix_original_channel_1
    selectObject: outCh[1]
    Formula (part): 0, min(total_duration, outDur), 1, 1, "Sound_rs_src(x)"
endif

stopwatch
for i to nSeg
    tStr$ = fixed$(slice_target_start#[i], 9)
    selectObject: sliceID[i]
    Rename: "rs_slice"

    if output_routing = 1
        gA = 1
        gB = 0
        chA = origChannel + i
        chB = 0
    elsif output_routing = 2
        gA = 1
        gB = 0
        if i mod 2 = 1
            chA = origChannel + 1
        else
            chA = origChannel + 2
        endif
        chB = 0
    elsif output_routing = 3
        pp = slice_pan#[i]
        gA = sqrt(1 - pp)
        gB = sqrt(pp)
        chA = origChannel + 1
        chB = origChannel + 2
    elsif output_routing = 4
        gA = 1
        gB = 0
        chA = origChannel + ((i - 1) mod 4) + 1
        chB = 0
    elsif output_routing = 5
        gA = 1
        gB = 0
        chA = origChannel + ((i - 1) mod 8) + 1
        chB = 0
    else
        gA = 1
        gB = 0
        chA = origChannel + 1
        chB = 0
    endif

    endWrite = slice_target_end#[i]
    if endWrite > outDur
        endWrite = outDur
    endif

    selectObject: outCh[chA]
    fmlA$ = "self + " + fixed$(gA, 8) + " * Sound_rs_slice(x - " + tStr$ + ")"
    Formula (part): slice_target_start#[i], endWrite, 1, 1, fmlA$
    if chB > 0 and gB > 1e-9
        selectObject: outCh[chB]
        fmlB$ = "self + " + fixed$(gB, 8) + " * Sound_rs_slice(x - " + tStr$ + ")"
        Formula (part): slice_target_start#[i], endWrite, 1, 1, fmlB$
    endif

    removeObject: sliceID[i]
endfor
placeElapsed = stopwatch

# ============================================================
# COMBINE AND NORMALISE
# ============================================================
if nOut = 1
    selectObject: outCh[1]
    Copy: "rs_result"
    master_id = selected("Sound")
else
    selectObject: outCh[1]
    for o from 2 to nOut
        plusObject: outCh[o]
    endfor
    Combine to stereo
    master_id = selected("Sound")
endif

selectObject: master_id
Rename: orig_name$ + "_MultiSlice_" + presetName$ + "_" + string$(nOut) + "ch"
# v1.1: capture the name here, while the object is selected. Reading it
# after the cleanup would find nothing selected.
resultName$ = selected$("Sound")
prePeak = Get absolute extremum: 0, 0, "None"
normGain = 1
if output_normalisation = 1
    if prePeak > 0
        normGain = peak_target / prePeak
    endif
    normMode$ = "peak (scaled to target)"
elsif output_normalisation = 2
    if prePeak > peak_target and prePeak > 0
        normGain = peak_target / prePeak
    endif
    normMode$ = "attenuate only"
else
    normMode$ = "none"
endif
if normGain <> 1
    selectObject: master_id
    Formula: "self * " + fixed$(normGain, 10)
endif
selectObject: master_id
finalPeak = Get absolute extremum: 0, 0, "None"
final_output_id = master_id

for o from 1 to nOut
    removeObject: outCh[o]
endfor

# ============================================================
# REPORT
# ============================================================
writeInfoLine: "=== Multi-channel Random Slice Time-Stretcher v1.1 ==="
appendInfoLine: "Input: ", orig_name$, "  (", fixed$(total_duration, 3), " s @ ", fs, " Hz)"
appendInfoLine: "Source used: ", inputNote$
if nchan > 1
    appendInfoLine: "  v1.0 took the original channel from LEFT and every slice from"
    appendInfoLine: "  RIGHT, so the two were different signals. One source now feeds both."
endif
if durClamped = 1
    appendInfoLine: "  NOTE: Max_duration exceeded the source and was clamped to ",
        ... fixed$(max_duration, 3), " s."
endif
appendInfoLine: ""

appendInfoLine: "Preset: ", presetName$, "   duration factor ",
    ... fixed$(duration_factor, 3)
appendInfoLine: "  A DURATION factor: >1 makes a slice longer, <1 shorter."
if preset = 1
    appendInfoLine: "  At exactly 1.0 the PSOLA round trip is skipped, so this is a"
    appendInfoLine: "  true copy of the source region apart from the edge fades."
else
    appendInfoLine: "  PSOLA ", pitch_floor, "-", pitch_ceiling,
        ... " Hz, used on ", psolaCount, " of ", nSeg, " slices."
    appendInfoLine: "  Pitch is preserved on suitably periodic or monophonic material;"
    appendInfoLine: "  polyphonic, noisy or transient-heavy sources will show artefacts."
endif
if seedApplied = 1
    appendInfoLine: "Random seed ", random_seed, " - this take is reproducible."
else
    appendInfoLine: "Random seed 0 - unpredictable, this take cannot be recovered."
endif
appendInfoLine: ""

appendInfoLine: "Slices (", nSeg, "):"
for i to nSeg
    if slice_shifted#[i] = 1
        shiftTag$ = "  [shifted right off 0]"
    else
        shiftTag$ = ""
    endif
    appendInfoLine: "  ", i, ": source ", fixed$(slice_source_start#[i], 3), "-",
        ... fixed$(slice_source_end#[i], 3), " s (", fixed$(slice_original_dur#[i], 3),
        ... " s)  ->  ", fixed$(slice_stretched_dur#[i], 3), " s at ",
        ... fixed$(slice_target_start#[i], 3), "-", fixed$(slice_target_end#[i], 3),
        ... " s   achieved x", fixed$(slice_achieved#[i], 3), shiftTag$
endfor
if shiftedCount > 0
    appendInfoLine: "  ", shiftedCount, " slice(s) would have started before zero and were"
    appendInfoLine: "  shifted right rather than clipped, so those are NOT centred on"
    appendInfoLine: "  their source position. The whole slice survives, which is the"
    appendInfoLine: "  point, but the placement rule differs for them."
endif
appendInfoLine: ""

appendInfoLine: "Levels: ", normMode$
if slice_level_mode = 1
    appendInfoLine: "  Slices keep their source level."
    appendInfoLine: "  v1.0 normalised every slice to 0.99 inside the PSOLA step, so a"
    appendInfoLine: "  slice peaking at 0.01 was boosted 99x to match one peaking at 0.9."
else
    appendInfoLine: "  Each slice normalised to 0.99 individually (the v1.0 behaviour):"
    appendInfoLine: "  this equalises the slices and removes the source dynamics."
endif
appendInfoLine: "  Edge fades ", fixed$(slice_edge_fade_ms, 1),
    ... " ms, clamped to 10% of a slice."
appendInfoLine: "  Peak ", fixed$(prePeak, 4), " -> ", fixed$(finalPeak, 4),
    ... "  (gain x", fixed$(normGain, 4), ")"
appendInfoLine: ""

appendInfoLine: "Output: ", routeName$, ", ", nOut, " channel(s), ",
    ... fixed$(outDur, 3), " s"
appendInfoLine: "  Latest slice ends at ", fixed$(latestEnd, 3), " s."
appendInfoLine: "  v1.0 would have produced ", fixed$(v10Dur, 3), " s here, from"
appendInfoLine: "  duration + max_duration / factor - the factor inverted. That is ",
    ... fixed$(v10Dur - outDur, 3), " s"
appendInfoLine: "  of difference. The formula truncates once the factor exceeds 2;"
appendInfoLine: "  below that it merely pads with silence."
if nOut > 32
    appendInfoLine: "  WARNING: ", nOut, " channels. Most file formats and audio"
    appendInfoLine: "  interfaces will not handle this; consider a routing option."
endif
appendInfoLine: ""
appendInfoLine: "(slices ", fixed$(sliceElapsed, 2), " s   placement ",
    ... fixed$(placeElapsed, 2), " s)"

# ============================================================
# VISUALIZATION
# ============================================================
if draw_visualization
    Erase all

    maxShow = nSeg
    if maxShow > 8
        maxShow = 8
    endif

    for i to nSeg
        hue = (i - 1) / max(1, nSeg)
        cR[i] = 0.30 + 0.55 * hue
        cG[i] = 0.60 - 0.25 * hue
        cB[i] = 0.90 - 0.55 * hue
    endfor

    # ----------------------------------------------------------
    # TITLE
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##MULTI-CHANNEL RANDOM SLICE TIME-STRETCHER##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... orig_name$
        ... + "  |  " + string$(nSeg) + " slices"
        ... + "  |  " + presetName$ + " x" + fixed$(duration_factor, 2)
        ... + "  |  " + routeName$
        ... + "  |  seed " + string$(random_seed)

    # ----------------------------------------------------------
    # PANEL A: SOURCE WITH SLICE REGIONS
    # ----------------------------------------------------------
    # v1.1: regions painted FIRST, waveform drawn on top. v1.0 painted
    # over the waveform, so it disappeared inside every region.
    Select outer viewport: 0, 8, 0.72, 2.30
    Select inner viewport: 0.55, 7.75, 0.80, 2.22

    selectObject: src_id
    srcPeak = Get absolute extremum: 0, 0, "None"
    if srcPeak < 0.001
        srcPeak = 0.001
    endif
    aMax = srcPeak * 1.15

    Axes: 0, total_duration, -aMax, aMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, total_duration, -aMax, aMax

    for i to nSeg
        regCol$ = "{" + fixed$(0.55 + cR[i] * 0.40, 2) + ", " + fixed$(0.60 + cG[i] * 0.35, 2) + ", " + fixed$(0.60 + cB[i] * 0.35, 2) + "}"
        Paint rectangle: regCol$, slice_source_start#[i], slice_source_end#[i], -aMax, aMax
    endfor

    Colour: "{0.80, 0.80, 0.80}"
    Draw line: 0, 0, total_duration, 0

    selectObject: src_id
    Colour: "{0.20, 0.20, 0.25}"
    Line width: 1
    Draw: 0, 0, -aMax, aMax, "no", "Curve"

    for i to nSeg
        edgeCol$ = "{" + fixed$(cR[i], 2) + ", " + fixed$(cG[i], 2) + ", " + fixed$(cB[i], 2) + "}"
        Colour: edgeCol$
        Line width: 1.5
        Draw line: slice_source_start#[i], -aMax * 0.95, slice_source_start#[i], aMax * 0.95
        Draw line: slice_source_end#[i], -aMax * 0.95, slice_source_end#[i], aMax * 0.95
        Font size: 5
        Text: (slice_source_start#[i] + slice_source_end#[i]) / 2, "centre",
            ... aMax * 0.82, "half", string$(i)
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Source"
    Text top: "no", "Source with the sampled regions (regions behind the waveform)"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL B: PLACEMENT TIMELINE
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 2.38, 4.30
    Select inner viewport: 0.55, 7.75, 2.46, 4.22

    Axes: 0, outDur, 0.3, nSeg + 0.7
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, outDur, 0.3, nSeg + 0.7

    Colour: "{0.82, 0.82, 0.86}"
    Draw line: total_duration, 0.3, total_duration, nSeg + 0.7
    Font size: 5
    Colour: "{0.55, 0.55, 0.60}"
    Text: total_duration, "left", nSeg + 0.55, "half", " source end"

    for i to nSeg
        y = nSeg + 1 - i
        # Source extent, faint, for comparison with the placement
        Colour: "{0.86, 0.86, 0.86}"
        Draw rectangle: slice_source_start#[i], slice_source_end#[i], y - 0.16, y + 0.16
        barCol$ = "{" + fixed$(cR[i], 2) + ", " + fixed$(cG[i], 2) + ", " + fixed$(cB[i], 2) + "}"
        Paint rectangle: barCol$, slice_target_start#[i], slice_target_end#[i], y - 0.30, y + 0.30
        Colour: "{0.30, 0.30, 0.30}"
        Draw rectangle: slice_target_start#[i], slice_target_end#[i], y - 0.30, y + 0.30
        # Centre marker
        Colour: "{0.15, 0.15, 0.15}"
        cx = (slice_source_start#[i] + slice_source_end#[i]) / 2
        Draw line: cx, y - 0.36, cx, y + 0.36
        Font size: 5
        Colour: "{0.35, 0.35, 0.35}"
        Text: -outDur * 0.012, "right", y, "half", string$(i)
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Slice"
    Text top: "no", "Placement: grey = source extent, bar = stretched slice, tick = source centre"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL C: SLICE TABLE
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.38, 6.00
    Select inner viewport: 0.55, 7.75, 4.44, 5.94
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1

    Font size: 6
    Colour: "Black"
    Text: 0.02, "left", 0.93, "half", "##Slice##"
    Text: 0.14, "left", 0.93, "half", "##Source (s)##"
    Text: 0.34, "left", 0.93, "half", "##Orig dur##"
    Text: 0.48, "left", 0.93, "half", "##Stretched dur##"
    Text: 0.66, "left", 0.93, "half", "##Achieved##"
    Text: 0.80, "left", 0.93, "half", "##Placed at##"

    Colour: "{0.70, 0.70, 0.70}"
    Draw line: 0.02, 0.87, 0.98, 0.87

    for i to maxShow
        yy = 0.79 - (i - 1) * 0.093
        rowCol$ = "{" + fixed$(cR[i], 2) + ", " + fixed$(cG[i], 2) + ", " + fixed$(cB[i], 2) + "}"
        Colour: rowCol$
        Paint rectangle: rowCol$, 0.025, 0.055, yy - 0.022, yy + 0.022
        Font size: 5
        Colour: "{0.20, 0.20, 0.20}"
        Text: 0.075, "left", yy, "half", string$(i)
        srcTxt$ = fixed$(slice_source_start#[i], 2) + " - " + fixed$(slice_source_end#[i], 2)
        Text: 0.14, "left", yy, "half", srcTxt$
        Text: 0.34, "left", yy, "half", fixed$(slice_original_dur#[i], 3)
        Text: 0.48, "left", yy, "half", fixed$(slice_stretched_dur#[i], 3)
        Text: 0.66, "left", yy, "half", "x" + fixed$(slice_achieved#[i], 3)
        Text: 0.80, "left", yy, "half", fixed$(slice_target_start#[i], 3)
    endfor

    Font size: 5
    Colour: "{0.45, 0.45, 0.45}"
    if nSeg > maxShow
        noteTxt$ = "Showing the first " + string$(maxShow) + " of " + string$(nSeg) + " slices.  Achieved = stretched / original, so PSOLA can be checked against the requested x" + fixed$(duration_factor, 2) + "."
        Text: 0.02, "left", 0.05, "half", noteTxt$
    else
        noteTxt$ = "Achieved = stretched / original, so PSOLA can be checked against the requested x" + fixed$(duration_factor, 2) + "."
        Text: 0.02, "left", 0.05, "half", noteTxt$
    endif

    Colour: "Black"
    Draw inner box

    # ----------------------------------------------------------
    # PANEL D: SUMMARY
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.08, 7.10
    Select inner viewport: 0.55, 7.75, 6.14, 7.04
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.80, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + orig_name$
        ... + "  |  Source " + fixed$(total_duration, 2) + " s"
        ... + "  |  Output " + fixed$(outDur, 2) + " s"
        ... + "  |  Latest slice ends " + fixed$(latestEnd, 2) + " s"
        ... + "  |  v1.0 would give " + fixed$(v10Dur, 2) + " s"

    if slice_level_mode = 1
        lvl$ = "slices keep source level"
    else
        lvl$ = "each slice normalised"
    endif
    Text: 0.02, "left", 0.50, "half",
        ... inputNote$
        ... + "  |  " + lvl$
        ... + "  |  fades " + fixed$(slice_edge_fade_ms, 0) + " ms"
        ... + "  |  PSOLA " + string$(psolaCount) + "/" + string$(nSeg)
        ... + "  |  seed " + string$(random_seed)

    Text: 0.02, "left", 0.20, "half",
        ... "Routing: " + routeName$
        ... + "  |  " + string$(nOut) + " ch"
        ... + "  |  Norm: " + normMode$
        ... + "  |  Peak " + fixed$(prePeak, 3) + " -> " + fixed$(finalPeak, 3)

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# ============================================================
# CLEANUP
# ============================================================
removeObject: src_id

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Output: ", resultName$

if play_after_processing
    selectObject: final_output_id
    Play
endif

selectObject: final_output_id
