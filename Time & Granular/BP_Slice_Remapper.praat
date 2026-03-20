# ============================================================
# Praat AudioTools - BP Slice Remapper.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2026)
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
#   This yields an asymmetric temporal grid where each segment is
#   geometrically wider than its predecessor.  In Accelerando mode
#   early slices are shortest and later slices are longest.  In
#   Decelerando mode the ordering is reversed.  The total duration
#   is always preserved exactly.
#
#   Multiple-block presets divide the full sound into equal blocks
#   first, then apply the same independent BP grid to each block.
#
#   Modes:
#     Extract slices -- cut the source Sound at every BP boundary

#
# Changelog:
#   1.0 (2026) -- initial release
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

origSound = selected("Sound")
origName$ = selected$("Sound")

# === Form ===
form BP Slicing Protocol - Temporal Grids
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
if overlap_factor > 0.95
    overlap_factor = 0.95
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
totalDur  = Get total duration
origSR    = Get sampling frequency
nChannels = Get number of channels

# === Safety check ===
totalSlices    = numBlocks * num_slices
minViableDur   = 0.010 * totalSlices
if totalDur < minViableDur
    exitScript: "Sound too short for " + string$(totalSlices) + " slices." + newline$
        ... + "Minimum required: " + fixed$(minViableDur, 3) + " s"
endif

# === Compute BP ratio series ===
# ratio[n] = 3 ^ ((n-1) / num_slices)   n = 1 ... num_slices
# n=1 gives 3^0 = 1.0  (shortest in Accelerando)
# n=num_slices gives 3^((N-1)/N)  (longest in Accelerando)
totalRatio = 0
for n from 1 to num_slices
    bpR_'n' = 3 ^ ((n - 1) * 1.0 / num_slices)
    totalRatio = totalRatio + bpR_'n'
endfor

# === Build temporal grid ===
blockDur    = totalDur / numBlocks
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
    tS = gStart_'g'
    tE = gEnd_'g'
    if tS < 0
        tS = 0
    endif
    if tE > totalDur
        tE = totalDur
    endif
    segDur = tE - tS
    if segDur >= 0.005
        selectObject: origSound
        tmpSnd = Extract part: tS, tE, "rectangular", 1, "yes"
        nExtracted = nExtracted + 1
        extracted_'nExtracted' = tmpSnd
        exDur_'nExtracted'     = segDur
        sortIdxL_'nExtracted'  = nExtracted
        sortIdxR_'nExtracted'  = nExtracted
    endif
endfor

appendInfoLine: "  Slices extracted: ", nExtracted

# Bubble sort L (Direction from form)
if nExtracted > 1
    for i from 1 to nExtracted - 1
        for j from i + 1 to nExtracted
            si = sortIdxL_'i'
            sj = sortIdxL_'j'
            di = exDur_'si'
            dj = exDur_'sj'
            if direction = 1
                doSwap = (dj < di)
            else
                doSwap = (dj > di)
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
                doSwap = (dj > di)
            else
                doSwap = (dj < di)
            endif
            if doSwap
                sortIdxR_'i' = sj
                sortIdxR_'j' = si
            endif
        endfor
    endfor
endif

# Build mono Left channel (sequential — Praat concatenates by object list order,
# not selection order, so sorted output requires two-at-a-time approach)
if nExtracted = 1
    selectObject: extracted_1
    monoL = Copy: "BP_L"
elsif nExtracted > 1
    p1 = sortIdxL_1
    selectObject: extracted_'p1'
    monoL = Copy: "BP_L"
    for k from 2 to nExtracted
        pk       = sortIdxL_'k'
        oldChain = monoL
        selectObject: monoL
        plusObject: extracted_'pk'
        monoL = Concatenate
        removeObject: oldChain
    endfor
    Rename: "BP_L"
endif

# Build mono Right channel
if nExtracted = 1
    selectObject: extracted_1
    monoR = Copy: "BP_R"
elsif nExtracted > 1
    p1 = sortIdxR_1
    selectObject: extracted_'p1'
    monoR = Copy: "BP_R"
    for k from 2 to nExtracted
        pk       = sortIdxR_'k'
        oldChain = monoR
        selectObject: monoR
        plusObject: extracted_'pk'
        monoR = Concatenate
        removeObject: oldChain
    endfor
    Rename: "BP_R"
endif

# Remove source slices
for i from 1 to nExtracted
    removeObject: extracted_'i'
endfor

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
    Scale peak: 0.99
endif

selectObject: resultSound
outDur = Get total duration
appendInfoLine: "  Output duration: ", fixed$(outDur, 3), " s"
appendInfoLine: "  Output object:   BP_" + origName$ + "  (stereo L/R opposite BP directions)"

# === Visualization ===
if draw_visualization = 1
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 7.5

    # ---- Title ----
    Select outer viewport: 0, 8, 0, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.62, "half", "##BP Slicing Protocol -- Temporal Grids##"
    Font size: 8
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -1.15, "half",
        ... origName$ + "  |  " + string$(numBlocks) + " block(s)"
        ... + "  |  " + string$(num_slices) + " slices/block"
        ... + "  |  " + dirStr$
        ... + "  |  ratio = 3^((n-1)/" + string$(num_slices) + ")"

    # ---- Timeline: colored rectangles per BP slice ----
    Select outer viewport: 0, 8, 0.55, 1.90
    Select inner viewport: 0.6, 7.7, 0.62, 1.83
    Axes: 0, totalDur, 0, 1
    Paint rectangle: "{0.96, 0.96, 0.98}", 0, totalDur, 0, 1

    for g from 1 to totalSlices
        blk = gBlock_'g'
        if blk = 1
            colStr$ = "{0.18, 0.62, 0.68}"
        elsif blk = 2
            colStr$ = "{0.78, 0.50, 0.10}"
        elsif blk = 3
            colStr$ = "{0.52, 0.20, 0.70}"
        else
            colStr$ = "{0.70, 0.18, 0.26}"
        endif
        Paint rectangle: colStr$, gStart_'g', gEnd_'g', 0.06, 0.94
    endfor

    # Block dividers
    Colour: "{0.10, 0.10, 0.10}"
    Line width: 2
    for b from 1 to numBlocks - 1
        divT = b * blockDur
        Draw line: divT, 0, divT, 1
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Blocks"
    Text bottom: "yes", "Time (s)"
    Text top: "no", string$(totalSlices) + " slices -- BP geometric grid"

    # ---- Slice duration bar chart ----
    Select outer viewport: 0, 8, 2.00, 3.50
    Select inner viewport: 0.6, 7.7, 2.08, 3.42

    barTop = maxSliceDur * 1000
    if barTop < 1
        barTop = 1
    endif
    Axes: 0.5, totalSlices + 0.5, 0, barTop
    Paint rectangle: "{0.97, 0.97, 0.97}", 0.5, totalSlices + 0.5, 0, barTop

    for g from 1 to totalSlices
        blk = gBlock_'g'
        if blk = 1
            bColStr$ = "{0.18, 0.62, 0.68}"
        elsif blk = 2
            bColStr$ = "{0.78, 0.50, 0.10}"
        elsif blk = 3
            bColStr$ = "{0.52, 0.20, 0.70}"
        else
            bColStr$ = "{0.70, 0.18, 0.26}"
        endif
        dms = gDur_'g' * 1000
        Paint rectangle: bColStr$, g - 0.44, g + 0.44, 0, dms
    endfor

    # Waveform of original sound above bar chart (grey)
    Colour: "{0.50, 0.50, 0.50}"
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Dur (ms)"
    Text bottom: "yes", "Slice index"
    Text top: "no", "Slice durations  (block colour-coded)"

    # ---- Waveform of original ----
    Select outer viewport: 0, 8, 3.60, 4.70
    Select inner viewport: 0.6, 7.7, 3.68, 4.62
    selectObject: origSound
    if nChannels > 1
        Extract one channel: 1
        tmpOrigViz = selected("Sound")
    else
        Copy: "tmpOrigViz"
        tmpOrigViz = selected("Sound")
    endif
    selectObject: tmpOrigViz
    Colour: "{0.50, 0.50, 0.50}"
    Draw: 0, 0, 0, 0, "no", "Curve"

    # Overlay slice boundaries as vertical lines
    Colour: "{0.18, 0.62, 0.68}"
    Line width: 1
    selectObject: tmpOrigViz
    mn = Get minimum: 0, 0, "Sinc70"
    mx = Get maximum: 0, 0, "Sinc70"
    if mx - mn < 0.001
        mx =  0.5
        mn = -0.5
    endif
    Axes: 0, totalDur, mn, mx
    for g from 1 to totalSlices
        Draw line: gStart_'g', mn, gStart_'g', mx
    endfor
    Line width: 1
    removeObject: tmpOrigViz

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Waveform with BP slice boundaries"

    # ---- Summary panel ----
    Select outer viewport: 0, 8, 4.80, 5.90
    Select inner viewport: 0.6, 7.7, 4.88, 5.82
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.93, 0.93, 0.93}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.87, "half", "##Summary##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.66, "half",
        ... "Source: " + origName$
        ... + "  |  Duration: " + fixed$(totalDur, 3) + " s"
        ... + "  |  SR: " + string$(origSR) + " Hz"
    Text: 0.02, "left", 0.45, "half",
        ... "Blocks: " + string$(numBlocks)
        ... + "  |  Slices/block: " + string$(num_slices)
        ... + "  |  Total slices: " + string$(totalSlices)
        ... + "  |  Direction: " + dirStr$
    Text: 0.02, "left", 0.24, "half",
        ... "Shortest: " + fixed$(minSliceDur * 1000, 2) + " ms"
        ... + "  |  Longest: " + fixed$(maxSliceDur * 1000, 2) + " ms"
        ... + "  |  Max/min ratio: " + fixed$(maxSliceDur / minSliceDur, 3)
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
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
