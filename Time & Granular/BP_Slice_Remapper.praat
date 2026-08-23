# ============================================================
# Praat AudioTools - BP Slice Remapper.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.2.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   BP Slicing Protocol -- Temporal Grids
#
#   Divides a Sound object into N segments (default 13) using a
#   Bohlen-Pierce-inspired geometric ratio series:
#       ratio[n] = 3 ^ ((n-1) / N)   for n = 1 ... N
#
#   This yields an asymmetric temporal grid whose slice durations form
#   a Bohlen-Pierce-inspired geometric series. The grid assigns widths
#   to source positions; the remapper then sorts the extracted slices:
#       Accelerando = long -> short
#       Decelerando = short -> long
#   so event rate genuinely accelerates or decelerates in the output.
#
#   Multiple-block presets divide the full sound into equal blocks
#   first, then apply the same independent BP grid to each block.
#   The grid itself preserves the complete source duration. Optional
#   crossfaded joins shorten the rendered output by the overlap amount.

#
# Changelog:
#   1.2.3 (2026):
#   - VIZ ONLY: moved the Output panel title away from the frame line.
#   - DSP/rendering unchanged from v1.2.
#   1.2.2 (2026):
#   - VIZ ONLY: moved the BP remap-map title into a dedicated in-panel
#     title band so it no longer collides with the panel frame.
#   - VIZ: source blocks now receive very light categorical tints that
#     match the central block colours; slice/block boundary lines are
#     neutral so colour has one semantic role: source-block identity.
#   - VIZ: increased title/legend/lane spacing in the central map.
#   - DSP/rendering unchanged from v1.2.
#   1.2.1 (2026):
#   - VIZ ONLY: aligned to the current Praat AudioTools suite:
#     Source -> BP remap map -> Output -> Summary.
#   - VIZ: central map now directly shows chronological source slices
#     and their L/R duration-sorted render orders; cell width encodes
#     slice duration and colour identifies the source block.
#   - VIZ: shared waveform scale, suite typography/panels, and safe
#     display names without Praat underscore subscripting.
#   - DSP/rendering unchanged from v1.2.
#   1.2 (2026):
#   - FIX: non-zero Sound time domains. BP grid/visualization remain
#     zero-based, while extraction uses absolute sourceStart + offset.
#   - FIX: Overlap_factor now directly means the fraction of the
#     shortest slice used as crossfade (0..0.45). v1.1 silently
#     multiplied the entered value by 0.45.
#   - FIX: optional overlap no longer claims duration preservation.
#     The exact expected output shortening is calculated and reported.
#   - FIX: removed the arbitrary 5-ms extraction threshold and 10-ms
#     average-slice safety rule. Renderability is checked from the
#     actual shortest BP slice against the sample period; accepted
#     slices are never silently dropped.
#   - FIX: safe normalization for all-zero output.
#   - PERFORMANCE: each stereo side is now assembled with one concatenate
#     after creating copies in sorted Object-list order, instead of repeatedly
#     rebuilding a growing chain slice-by-slice.
#   - VIZ: waveform copy is shifted to zero for correct overlay with
#     BP boundaries when the input time domain does not start at zero.
#   - Clarified Accelerando/Decelerando terminology: rendered order is
#     long->short / short->long respectively.
#
#   1.1 (2026):
#   - FIX (structural, output-preserving): v1.0's ordering was
#     right BY DOUBLE ACCIDENT -- the sort ran opposite to its own
#     comment, and the chain assembly PREPENDED every slice
#     (Praat's Concatenate orders by object-list creation order,
#     and the growing chain was always the newest object). Two
#     inversions canceled. v1.1 makes the assembly a true append
#     (fresh slice copies) and keeps the sort, so the audible
#     ordering is UNCHANGED while both halves of the code now do
#     what they say. Verified: Accelerando plays longest-first.
#   - FIX: stereo sources produced a 4-CHANNEL output (stereo
#     slices through Combine to stereo). Per the design statement
#     -- "both channels use the same source audio [in] different
#     orderings" -- the source is now mixed to mono for slicing;
#     the output is genuinely stereo.
#   - Overlap_factor was a dead knob (defined, clamped, never
#     read). It now does what its name promises: crossfaded
#     slice joins (fraction of the shortest slice), curing the
#     click at every joint between duration-sorted non-adjacent
#     material. Default 0 = the original butt-joins, unchanged.
#   - VIZ: title strip uses an explicit inner viewport (the
#     outer-only negative-offset form is the margin-compression
#     collision geometry).
#   1.0 (2026) -- initial release
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

origSound = selected("Sound")
origName$ = selected$("Sound")

# === Form ===
form BP Slicing Protocol - Temporal Grids v1.2
    comment === Preset (number of equal blocks) ===
    optionmenu Preset: 1
        option 1 Block
        option 2 Blocks
        option 3 Blocks
        option 4 Blocks
    comment === Grid Parameters ===
    integer Num_slices 13
    optionmenu Direction: 1
        option Accelerando
        option Decelerando
    comment === Direction per block ===
    optionmenu Block_direction: 1
        option All same
        option Alternating (A D A D)
        option Alternating (D A D A)
    real Overlap_factor 0.0
    comment === Output ===
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Preset to number of blocks ===
if preset = 1
    numBlocks = 1
elsif preset = 2
    numBlocks = 2
elsif preset = 3
    numBlocks = 3
else
    numBlocks = 4
endif

# === Clamp parameters ===
if num_slices < 2
    num_slices = 2
endif
if num_slices > 64
    num_slices = 64
endif
if overlap_factor < 0
    overlap_factor = 0
endif
if overlap_factor > 0.45
    overlap_factor = 0.45
endif

# === Direction and mode strings ===
if direction = 1
    dirStr$ = "Accelerando"
else
    dirStr$ = "Decelerando"
endif

if block_direction = 1
    blkDirStr$ = "All same"
elsif block_direction = 2
    blkDirStr$ = "Alternating A-D"
else
    blkDirStr$ = "Alternating D-A"
endif

# === Sound properties ===
selectObject: origSound
sourceStart = Get start time
sourceEnd   = Get end time
totalDur    = Get total duration
origSR      = Get sampling frequency
nChannels   = Get number of channels

if totalDur <= 0
    exitScript: "Sound duration must be greater than zero."
endif
if origSR <= 0
    exitScript: "Invalid sampling frequency."
endif

totalSlices = numBlocks * num_slices

# === Compute BP ratio series ===
# ratio[n] = 3 ^ ((n-1) / num_slices)   n = 1 ... num_slices
# n=1 gives 3^0 = 1.0  (shortest in Accelerando)
# n=num_slices gives 3^((N-1)/N)  (longest in Accelerando)
totalRatio = 0
for n from 1 to num_slices
    bpR_'n' = 3 ^ ((n - 1) * 1.0 / num_slices)
    totalRatio = totalRatio + bpR_'n'
endfor

# === Safety check from the actual shortest BP slice ===
blockDur = totalDur / numBlocks
minExpectedSlice = blockDur / totalRatio
minRenderableDur = 2 / origSR
if minExpectedSlice < minRenderableDur
    exitScript: "Sound too short for this BP grid at the current sampling rate." + newline$
        ... + "Shortest slice would be " + fixed$(minExpectedSlice * 1000, 4) + " ms; "
        ... + "minimum renderable duration is " + fixed$(minRenderableDur * 1000, 4) + " ms."
endif

# v1.2: slice a mono mixdown -- stereo slices would make the final
# Combine produce a 4-channel object. Do this only after validation so
# failed runs do not leave an extra converted object behind.
selectObject: origSound
if nChannels > 1
    sliceSource = Convert to mono
else
    sliceSource = origSound
endif

# === Build temporal grid ===
minSliceDur = totalDur
maxSliceDur = 0
globalSl    = 0

for b from 1 to numBlocks
    bkStart  = (b - 1) * blockDur
    cumTime  = bkStart

    # Per-block direction: All same / Alternating A-D / Alternating D-A
    if block_direction = 1
        blockIsAccel = (direction = 1)
    elsif block_direction = 2
        blockIsAccel = (b mod 2 = 1)
    else
        blockIsAccel = (b mod 2 = 0)
    endif

    for n from 1 to num_slices
        if blockIsAccel = 1
            thisRatio = bpR_'n'
        else
            revN      = num_slices + 1 - n
            thisRatio = bpR_'revN'
        endif

        thisDur  = blockDur * thisRatio / totalRatio
        globalSl = globalSl + 1

        gStart_'globalSl' = cumTime
        gDur_'globalSl'   = thisDur
        gRatio_'globalSl' = thisRatio
        gBlock_'globalSl' = b

        cumTime = cumTime + thisDur
    endfor

    # Force last slice of this block to end exactly at the block boundary
    lastSl = b * num_slices
    gDur_'lastSl' = bkStart + blockDur - gStart_'lastSl'
endfor

# === Compute end times and range ===
for g from 1 to totalSlices
    gEnd_'g' = gStart_'g' + gDur_'g'
    if gDur_'g' < minSliceDur
        minSliceDur = gDur_'g'
    endif
    if gDur_'g' > maxSliceDur
        maxSliceDur = gDur_'g'
    endif
endfor

# === Info window ===
clearinfo
writeInfoLine:  "=== BP Slicing Protocol -- Temporal Grids ==="
appendInfoLine: "Source:         ", origName$
appendInfoLine: "Duration:       ", fixed$(totalDur, 6), " s"
appendInfoLine: "Sample rate:    ", origSR, " Hz"
appendInfoLine: "Blocks:         ", numBlocks
appendInfoLine: "Slices / block: ", num_slices
appendInfoLine: "Total slices:   ", totalSlices
appendInfoLine: "Direction:      ", dirStr$
appendInfoLine: "Block dir:      ", blkDirStr$
appendInfoLine: "BP ratio sum:   ", fixed$(totalRatio, 6)
appendInfoLine: ""
appendInfoLine: "  sl   blk   BP-ratio   start(s)   end(s)     dur(s)     dur(ms)"
appendInfoLine: "  ---  ---   --------   --------   --------   --------   -------"

for g from 1 to totalSlices
    appendInfoLine: "  " + string$(g)
        ... + "    " + string$(gBlock_'g')
        ... + "    " + fixed$(gRatio_'g', 5)
        ... + "    " + fixed$(gStart_'g', 5)
        ... + "    " + fixed$(gEnd_'g', 5)
        ... + "    " + fixed$(gDur_'g', 5)
        ... + "    " + fixed$(gDur_'g' * 1000, 2)
endfor

appendInfoLine: ""
appendInfoLine: "Shortest slice: ", fixed$(minSliceDur * 1000, 3), " ms"
appendInfoLine: "Longest slice:  ", fixed$(maxSliceDur * 1000, 3), " ms"
appendInfoLine: "Ratio (max/min): ", fixed$(maxSliceDur / minSliceDur, 4)
appendInfoLine: "Total dur check: ", fixed$(gEnd_'totalSlices', 6), " s  (should equal ", fixed$(totalDur, 6), " s)"
appendInfoLine: ""

# === Extract slices ===
# The BP series is monotonically increasing within each block.
# Forward order (1..N) = original chronological order = input sound.
# To actually transform the audio we SORT all slices by duration
# using a bubble sort, then assemble in sorted order:
#   Accelerando: descending sort (longest first -> shortest last)
#   Decelerando: ascending sort  (shortest first -> longest last)
# Across multiple blocks this interleaves slices of similar duration
# from different positions in the file, creating a genuinely new sound.

# === Extract slices -- stereo with opposite directions ===
# Left channel:  sorted by Direction chosen in form (Accelerando or Decelerando)
# Right channel: always the opposite direction
# Both channels use the same source audio but different playback orderings,
# creating a stereo image where L and R diverge rhythmically.

appendInfoLine: "[Extracting slices...]"
appendInfoLine: "  L channel: ", dirStr$
if direction = 1
    appendInfoLine: "  R channel: Decelerando"
else
    appendInfoLine: "  R channel: Accelerando"
endif

nExtracted = 0
for g from 1 to totalSlices
    tS = max(0, gStart_'g')
    tE = min(totalDur, gEnd_'g')
    segDur = tE - tS
    if segDur < minRenderableDur
        exitScript: "Internal BP slice became shorter than two samples."
    endif
    selectObject: sliceSource
    tmpSnd = Extract part: sourceStart + tS, sourceStart + tE, "rectangular", 1, "yes"
    nExtracted = nExtracted + 1
    extracted_'nExtracted' = tmpSnd
    exDur_'nExtracted'     = segDur
    sortIdxL_'nExtracted'  = nExtracted
    sortIdxR_'nExtracted'  = nExtracted
endfor

appendInfoLine: "  Slices extracted: ", nExtracted

# v1.2: Overlap_factor is the direct fraction of the shortest slice.
# Praat's Concatenate with overlap shortens a chain by one overlap per
# join, so report the exact expected output duration rather than claiming
# that optional crossfades preserve duration.
minExDur = 1e9
sumExDur = 0
for i from 1 to nExtracted
    sumExDur = sumExDur + exDur_'i'
    if exDur_'i' < minExDur
        minExDur = exDur_'i'
    endif
endfor
xfadeDur = overlap_factor * minExDur
expectedOutDur = sumExDur - max(0, nExtracted - 1) * xfadeDur
if xfadeDur > 0
    appendInfoLine: "  Slice crossfades: ", fixed$(xfadeDur * 1000, 2), " ms/join"
    appendInfoLine: "  Expected output: ", fixed$(expectedOutDur, 4), " s (crossfades shorten by ", fixed$((sumExDur - expectedOutDur) * 1000, 2), " ms)"
else
    appendInfoLine: "  Expected output: ", fixed$(sumExDur, 4), " s (duration preserved; no overlap)"
endif

# Bubble sort L (Direction from form)
if nExtracted > 1
    for i from 1 to nExtracted - 1
        for j from i + 1 to nExtracted
            si = sortIdxL_'i'
            sj = sortIdxL_'j'
            di = exDur_'si'
            dj = exDur_'sj'
            # v1.1: descending comparison (longest first for
            # Accelerando) paired with a true APPENDING chain below.
            # v1.0 had the double-inverted twin: ascending sort +
            # prepending assembly (Concatenate object-list order) --
            # same audible ordering, by accident. Net output is
            # unchanged; both halves now do what they say.
            if direction = 1
                doSwap = (dj > di)
            else
                doSwap = (dj < di)
            endif
            if doSwap
                sortIdxL_'i' = sj
                sortIdxL_'j' = si
            endif
        endfor
    endfor
endif

# Bubble sort R (opposite direction)
if nExtracted > 1
    for i from 1 to nExtracted - 1
        for j from i + 1 to nExtracted
            si = sortIdxR_'i'
            sj = sortIdxR_'j'
            di = exDur_'si'
            dj = exDur_'sj'
            if direction = 1
                doSwap = (dj < di)
            else
                doSwap = (dj > di)
            endif
            if doSwap
                sortIdxR_'i' = sj
                sortIdxR_'j' = si
            endif
        endfor
    endfor
endif

# Build mono Left channel efficiently.
# Praat concatenates selected Sounds in Object-list order, not selection order.
# Therefore create fresh slice copies IN the desired sorted order, then perform
# one concatenate. This is equivalent to v1.1's iterative append but avoids
# repeatedly copying an ever-growing chain.
for k from 1 to nExtracted
    pk = sortIdxL_'k'
    selectObject: extracted_'pk'
    freshL_'k' = Copy: "BP_L_part"
endfor
selectObject: freshL_1
for k from 2 to nExtracted
    plusObject: freshL_'k'
endfor
if xfadeDur > 0
    monoL = Concatenate with overlap: xfadeDur
else
    monoL = Concatenate
endif
for k from 1 to nExtracted
    removeObject: freshL_'k'
endfor
selectObject: monoL
Rename: "BP_L"

# Build mono Right channel in the opposite sorted order.
for k from 1 to nExtracted
    pk = sortIdxR_'k'
    selectObject: extracted_'pk'
    freshR_'k' = Copy: "BP_R_part"
endfor
selectObject: freshR_1
for k from 2 to nExtracted
    plusObject: freshR_'k'
endfor
if xfadeDur > 0
    monoR = Concatenate with overlap: xfadeDur
else
    monoR = Concatenate
endif
for k from 1 to nExtracted
    removeObject: freshR_'k'
endfor
selectObject: monoR
Rename: "BP_R"

# Remove source slices
for i from 1 to nExtracted
    removeObject: extracted_'i'
endfor
if sliceSource <> origSound
    removeObject: sliceSource
endif

# Match durations: pad shorter channel with silence at end
selectObject: monoL
durL = Get total duration
selectObject: monoR
durR = Get total duration

if durL > durR
    padNeeded = durL - durR
    silPad = Create Sound from formula: "silPad", 1, 0, padNeeded, origSR, "0"
    oldR   = monoR
    selectObject: monoR
    plusObject: silPad
    monoR = Concatenate
    removeObject: oldR, silPad
    Rename: "BP_R"
elsif durR > durL
    padNeeded = durR - durL
    silPad = Create Sound from formula: "silPad", 1, 0, padNeeded, origSR, "0"
    oldL   = monoL
    selectObject: monoL
    plusObject: silPad
    monoL = Concatenate
    removeObject: oldL, silPad
    Rename: "BP_L"
endif

# Combine into stereo: Left + Right -> stereo Sound
selectObject: monoL
plusObject: monoR
resultSound = Combine to stereo
removeObject: monoL, monoR
Rename: "BP_" + origName$

if normalize_output = 1
    selectObject: resultSound
    resultPeak = Get absolute extremum: 0, 0, "Sinc70"
    if resultPeak > 0
        Scale peak: 0.99
    endif
endif

selectObject: resultSound
outDur = Get total duration
appendInfoLine: "  Output duration: ", fixed$(outDur, 3), " s"
appendInfoLine: "  Output object:   BP_" + origName$ + "  (stereo L/R opposite BP directions)"

# ============================================================
# VISUALIZATION  (current Praat AudioTools suite styling)
# Source -> signature BP remap map -> Output -> Summary.
# The central map directly shows the temporal law:
#   source row = chronological BP grid,
#   L row      = source slices sorted by the chosen direction,
#   R row      = the opposite ordering.
# Cell width is proportional to slice duration; colour identifies
# the source block. Thus long->short / short->long is visible directly.
# ============================================================
if draw_visualization = 1
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 7.10
    Black
    Plain line

    displayName$ = replace$(origName$, "_", " ", 0)

    # Mono, zero-based display copies.
    selectObject: origSound
    if nChannels > 1
        vizOrig = Convert to mono
    else
        vizOrig = Copy: "viz orig"
    endif
    selectObject: vizOrig
    vizOrigStart = Get start time
    Shift times by: -vizOrigStart

    selectObject: resultSound
    resultChannels = Get number of channels
    if resultChannels > 1
        vizResult = Convert to mono
    else
        vizResult = Copy: "viz result"
    endif
    selectObject: vizResult
    vizResultStart = Get start time
    Shift times by: -vizResultStart

    # Shared waveform amplitude scale.
    selectObject: vizOrig
    origPeak = Get absolute extremum: 0, 0, "None"
    selectObject: vizResult
    outPeak = Get absolute extremum: 0, 0, "None"
    sharedPeak = origPeak
    if outPeak > sharedPeak
        sharedPeak = outPeak
    endif
    if sharedPeak < 0.001
        sharedPeak = 0.001
    endif
    sharedAmp = 1.15 * sharedPeak

    if direction = 1
        rightDirStr$ = "Decelerando"
    else
        rightDirStr$ = "Accelerando"
    endif

    # ----------------------------------------------------------
    # TITLE / SUBTITLE
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##BP Slice Remapper##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -1.30, "half", "BP Slice Remapper.praat  |  " + displayName$ + "  |  Bohlen-Pierce temporal grid"

    # ----------------------------------------------------------
    # SOURCE
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.65, 1.90
    Select inner viewport: 0.55, 7.75, 0.82, 1.78
    Axes: 0, totalDur, -sharedAmp, sharedAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, totalDur, -sharedAmp, sharedAmp

    # Very light block tints connect source regions to the categorical
    # colours used in the remap map. Colour therefore has one role only:
    # source-block identity. Boundaries themselves stay neutral.
    for b from 1 to numBlocks
        if b = 1
            tintCol$ = "{0.94, 0.97, 1.00}"
        elsif b = 2
            tintCol$ = "{1.00, 0.96, 0.91}"
        elsif b = 3
            tintCol$ = "{0.97, 0.94, 1.00}"
        else
            tintCol$ = "{0.93, 0.98, 0.96}"
        endif
        bx0 = (b - 1) * blockDur
        bx1 = b * blockDur
        Paint rectangle: tintCol$, bx0, bx1, -sharedAmp, sharedAmp
    endfor

    selectObject: vizOrig
    Colour: "{0.58, 0.58, 0.62}"
    Draw: 0, totalDur, -sharedAmp, sharedAmp, "no", "Curve"

    # BP boundaries over the source waveform: thin = slice, heavy = block.
    Colour: "{0.74, 0.76, 0.80}"
    Line width: 0.7
    for g from 2 to totalSlices
        Draw line: gStart_'g', -sharedAmp, gStart_'g', sharedAmp
    endfor
    Colour: "{0.34, 0.34, 0.38}"
    Line width: 1.5
    for b from 1 to numBlocks - 1
        bt = b * blockDur
        Draw line: bt, -sharedAmp, bt, sharedAmp
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "##Source##"
    Font size: 6
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Time (s)"
    Axes: 0, totalDur, -sharedAmp, sharedAmp
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.01 * totalDur, "left", 0.82 * sharedAmp, "half", string$(numBlocks) + " block(s)  |  " + string$(num_slices) + " slices/block  |  thin = slice boundary  |  heavy = block boundary"

    # ----------------------------------------------------------
    # BP REMAP MAP - signature process view
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 2.05, 4.55
    Select inner viewport: 0.55, 7.75, 2.25, 4.40
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1

    x0 = 0.12
    xSpan = 0.84

    # Dedicated in-panel title band: never sits on the frame.
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.965, "half", "##BP remap map##"

    # Lane labels.
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half", "source grid"
    Text: 0.02, "left", 0.47, "half", "L  " + dirStr$
    Text: 0.02, "left", 0.19, "half", "R  " + rightDirStr$

    # SOURCE GRID: chronological positions, width proportional to duration.
    for g from 1 to totalSlices
        blk = gBlock_'g'
        if blk = 1
            cellCol$ = "{0.30, 0.53, 0.82}"
        elsif blk = 2
            cellCol$ = "{0.95, 0.55, 0.20}"
        elsif blk = 3
            cellCol$ = "{0.48, 0.33, 0.72}"
        else
            cellCol$ = "{0.34, 0.66, 0.55}"
        endif
        sx0 = x0 + xSpan * gStart_'g' / totalDur
        sx1 = x0 + xSpan * gEnd_'g' / totalDur
        Paint rectangle: cellCol$, sx0 + 0.001, sx1 - 0.001, 0.66, 0.82
    endfor

    # LEFT RENDER ORDER: widths preserve each slice duration, order follows sortIdxL.
    cursor = x0
    for k from 1 to totalSlices
        pk = sortIdxL_'k'
        blk = gBlock_'pk'
        if blk = 1
            cellCol$ = "{0.30, 0.53, 0.82}"
        elsif blk = 2
            cellCol$ = "{0.95, 0.55, 0.20}"
        elsif blk = 3
            cellCol$ = "{0.48, 0.33, 0.72}"
        else
            cellCol$ = "{0.34, 0.66, 0.55}"
        endif
        w = xSpan * exDur_'pk' / sumExDur
        Paint rectangle: cellCol$, cursor + 0.001, cursor + w - 0.001, 0.38, 0.54
        cursor = cursor + w
    endfor

    # RIGHT RENDER ORDER: the exact opposite duration sort.
    cursor = x0
    for k from 1 to totalSlices
        pk = sortIdxR_'k'
        blk = gBlock_'pk'
        if blk = 1
            cellCol$ = "{0.30, 0.53, 0.82}"
        elsif blk = 2
            cellCol$ = "{0.95, 0.55, 0.20}"
        elsif blk = 3
            cellCol$ = "{0.48, 0.33, 0.72}"
        else
            cellCol$ = "{0.34, 0.66, 0.55}"
        endif
        w = xSpan * exDur_'pk' / sumExDur
        Paint rectangle: cellCol$, cursor + 0.001, cursor + w - 0.001, 0.10, 0.26
        cursor = cursor + w
    endfor

    # Block colour legend and process note.
    Font size: 5
    Colour: "{0.28, 0.28, 0.28}"
    Text: x0, "left", 0.885, "half", "cell width = slice duration  |  colour = source block"
    Text: 0.97, "right", 0.885, "half", "BP ratio 3^((n-1)/" + string$(num_slices) + ")"
    if direction = 1
        orderNote$ = "L long -> short  |  R short -> long"
    else
        orderNote$ = "L short -> long  |  R long -> short"
    endif
    Text: x0, "left", 0.035, "half", orderNote$ + "  |  " + blkDirStr$
    if xfadeDur > 0
        Text: 0.97, "right", 0.035, "half", "xfade " + fixed$(xfadeDur * 1000, 2) + " ms/join"
    else
        Text: 0.97, "right", 0.035, "half", "butt joins"
    endif

    Colour: "Black"
    Draw inner box

    # ----------------------------------------------------------
    # OUTPUT
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.70, 5.95
    Select inner viewport: 0.55, 7.75, 4.87, 5.83
    Axes: 0, outDur, -sharedAmp, sharedAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, outDur, -sharedAmp, sharedAmp
    selectObject: vizResult
    Colour: "{0.48, 0.33, 0.72}"
    Draw: 0, outDur, -sharedAmp, sharedAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "yes", "##Output##"
    Font size: 6
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Time (s)"
    Axes: 0, outDur, -sharedAmp, sharedAmp
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.01 * outDur, "left", 0.82 * sharedAmp, "half", "stereo: L = " + dirStr$ + "  |  R = " + rightDirStr$ + "  |  opposite duration orderings"

    # ----------------------------------------------------------
    # SUMMARY
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.10, 7.05
    Select inner viewport: 0.30, 7.80, 6.17, 6.98
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "{0.48, 0.48, 0.48}"
    Draw rectangle: 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.80, "half", "##Summary##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.49, "half", string$(numBlocks) + " block(s)  |  " + string$(num_slices) + " slices/block  |  total " + string$(totalSlices) + "  |  L " + dirStr$ + "  |  R " + rightDirStr$ + "  |  " + blkDirStr$
    Text: 0.02, "left", 0.18, "half", "Slice range " + fixed$(minSliceDur * 1000, 2) + "-" + fixed$(maxSliceDur * 1000, 2) + " ms  |  max/min " + fixed$(maxSliceDur / minSliceDur, 3) + "  |  xfade " + fixed$(xfadeDur * 1000, 2) + " ms  |  duration " + fixed$(totalDur, 3) + " -> " + fixed$(outDur, 3) + " s"

    Font size: 10
    Colour: "Black"
    Line width: 1

    removeObject: vizOrig, vizResult
endif

# === Final summary + playback ===
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Source:       ", origName$
appendInfoLine: "Total slices: ", totalSlices
appendInfoLine: "Direction:    ", dirStr$
appendInfoLine: "Shortest:     ", fixed$(minSliceDur * 1000, 3), " ms"
appendInfoLine: "Longest:      ", fixed$(maxSliceDur * 1000, 3), " ms"

if resultSound > 0
    appendInfoLine: "Output:       BP_" + origName$ + "  (stereo)"
    appendInfoLine: "Input kept:   " + origName$ + " (unchanged)"
    selectObject: resultSound
    if play_result = 1
        Play
    endif
else
    selectObject: origSound
    if play_result = 1
        Play
    endif
endif
