# ============================================================
# Praat AudioTools - Waveset_Distortion.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.2 (2025) - Loudness-based deletion added (CDP distort_del)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   True waveset distortion based on CDP concepts.
#   Wavesets = segments between zero-crossings.
#
#   v1.0 rewrites the pipeline:
#   - Zero-crossing detection via To PointProcess (zeroes) (C-level)
#   - Each waveset extracted via Extract part (C-level)
#   - Processing via Sound-level operations (Reverse, Formula)
#   - Assembly via batched Concatenate
#   - Zero per-sample scripting loops
#
#   v1.1 adds CDP distort_shuf behaviour:
#   - Randomize mode now supports GROUP-based shuffle (CDP DISTORTS_CYCLECNT
#     / DISTORTS_DMNCNT concept): wavesets are first partitioned into groups
#     of <group_size>, then the groups themselves are shuffled (Fisher-Yates),
#     preserving local micro-structure while scrambling macro-order.
#   - Group size 1 reproduces the original individual-waveset shuffle.
#   - Repeat decay factor is now an explicit user parameter.
#
#   v1.2 adds CDP distort_del behaviour (two new types):
#   - Keep Strongest: wavesets are grouped in windows of <group_size>;
#     within each group only the single waveset with the highest energy
#     (sum of absolute sample values — matching CDP's DISTDEL_CYCLEVAL
#     accumulation) is kept; the rest are discarded. Produces a sparse,
#     percussive thinning effect.
#   - Delete Weakest: same grouping, but only the quietest waveset is
#     removed and all others are kept. Produces subtle noise-reduction /
#     cleaning at the waveset level.
#   Both modes measure energy the same way CDP does: integrate |sample|
#   over the full waveset (Praat: Get energy, a monotone proxy).
#
# Usage:
#   Select a Sound object in Praat and run this script.
# ============================================================

form Waveset Distortion v1.2
    optionmenu Preset: 1
        option Custom
        option Waveset Repeat (stutter)
        option Waveset Skip (gaps)
        option Waveset Reverse
        option Waveset Stretch
        option Waveset Compress
        option Waveset Shuffle (individual)
        option Waveset Shuffle (groups, CDP)
        option Waveset Amplitude
        option Keep Strongest (CDP)
        option Delete Weakest (CDP)
    comment === Parameters ===
    optionmenu Type: 1
        option Repeat
        option Skip
        option Reverse
        option Stretch
        option Compress
        option Randomize
        option Amplitude
        option Keep Strongest
        option Delete Weakest
    positive Amount 2.0
    comment --- Repeat only ---
    positive Repeat_decay 0.8
    comment --- Randomize / Keep Strongest / Delete Weakest: group size ---
    positive Group_size 4
    boolean Preserve_length 0
    comment === Output ===
    positive Scale_peak 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === PRESETS ===
presetName$ = "Custom"

if preset = 2
    type = 1
    amount = 2.0
    presetName$ = "WavesetRepeat"
elsif preset = 3
    type = 2
    amount = 2.0
    presetName$ = "WavesetSkip"
elsif preset = 4
    type = 3
    amount = 1.0
    presetName$ = "WavesetReverse"
elsif preset = 5
    type = 4
    amount = 2.0
    presetName$ = "WavesetStretch"
elsif preset = 6
    type = 5
    amount = 2.0
    presetName$ = "WavesetCompress"
elsif preset = 7
    type = 6
    amount = 1.0
    group_size = 1
    presetName$ = "WavesetShuffleIndividual"
elsif preset = 8
    type = 6
    amount = 1.0
    group_size = 4
    presetName$ = "WavesetShuffleGroups"
elsif preset = 9
    type = 7
    amount = 2.0
    presetName$ = "WavesetAmplitude"
elsif preset = 10
    type = 8
    amount = 1.0
    group_size = 4
    presetName$ = "KeepStrongest"
elsif preset = 11
    type = 9
    amount = 1.0
    group_size = 4
    presetName$ = "DeleteWeakest"
endif

# === VALIDATION ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")
selectObject: sound
original_duration = Get total duration
sampling_rate = Get sampling frequency
numChannels = Get number of channels

if original_duration < 0.05
    exitScript: "Sound must be at least 50 ms."
endif

# Clamp group_size (need at least 2 for energy modes to be meaningful,
# but allow 1 for individual waveset shuffle)
groupSz = round(group_size)
if groupSz < 1
    groupSz = 1
endif
if (type = 8 or type = 9) and groupSz < 2
    groupSz = 2
endif

# Type name
if type = 1
    typeName$ = "Repeat"
elsif type = 2
    typeName$ = "Skip"
elsif type = 3
    typeName$ = "Reverse"
elsif type = 4
    typeName$ = "Stretch"
elsif type = 5
    typeName$ = "Compress"
elsif type = 6
    if groupSz > 1
        typeName$ = "Randomize (groups=" + string$(groupSz) + ")"
    else
        typeName$ = "Randomize"
    endif
elsif type = 8
    typeName$ = "Keep Strongest (group=" + string$(groupSz) + ")"
elsif type = 9
    typeName$ = "Delete Weakest (group=" + string$(groupSz) + ")"
else
    typeName$ = "Amplitude"
endif

clearinfo
writeInfoLine: "=== Waveset Distortion v1.2 ==="
appendInfoLine: "Input: ", soundName$, " (", fixed$(original_duration, 2), " s, ",
    ... sampling_rate, " Hz)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Type: ", typeName$, "  Amount: ", fixed$(amount, 1)
if type = 1
    appendInfoLine: "Repeat decay: ", fixed$(repeat_decay, 2)
endif
if type = 6 and groupSz > 1
    appendInfoLine: "Group size: ", groupSz, " wavesets per group (CDP distort_shuf)"
endif
if type = 8 or type = 9
    appendInfoLine: "Group size: ", groupSz, " wavesets per group (CDP distort_del)"
endif
appendInfoLine: ""

startTime = stopwatch

# ============================================================
# STEP 1: FIND ZERO CROSSINGS (C-level)
# ============================================================

appendInfoLine: "[1/3] Finding zero crossings..."

selectObject: sound
if numChannels > 1
    monoWork = Convert to mono
else
    monoWork = Copy: "mono_work"
endif

selectObject: monoWork
ppZeroes = To PointProcess (zeroes): 1, "yes", "no"

selectObject: ppZeroes
n_crossings = Get number of points

if n_crossings < 3
    removeObject: ppZeroes, monoWork
    exitScript: "Not enough zero crossings found."
endif

n_wavesets = n_crossings - 1
appendInfoLine: "  Crossings: ", n_crossings, " (", n_wavesets, " wavesets)"

# ============================================================
# STEP 2: MEASURE WAVESET ENERGIES (types 8 and 9 only)
# ============================================================
#
# CDP distort_del_with_loudness accumulates sum(|sample|) over both
# half-cycles of each waveset into DISTDEL_CYCLEVAL[cyclecnt].
# We use Praat's Get energy (proportional to RMS * duration) as an
# equivalent monotone proxy — sufficient for ranking loudest/quietest.

if type = 8 or type = 9
    appendInfoLine: "  Measuring waveset energies..."
    for ws from 1 to n_wavesets
        selectObject: ppZeroes
        t1 = Get time from index: ws
        t2 = Get time from index: ws + 1
        selectObject: monoWork
        Extract part: t1, t2, "rectangular", 1, "no"
        wsTmp = selected("Sound")
        wsEnergy[ws] = Get energy: 0, 0
        removeObject: wsTmp
    endfor
endif

# ============================================================
# STEP 3: BUILD PLAYBACK ORDER (shuffle types)
# ============================================================

appendInfoLine: "[2/3] Processing (", typeName$, ")..."

# Initialise sequential order (identity permutation)
for ws from 1 to n_wavesets
    wsOrder[ws] = ws
endfor

if type = 6
    if groupSz = 1
        # Individual waveset shuffle
        # Ascending Fisher-Yates (Praat can't do descending for-loops)
        for ws from 1 to n_wavesets - 1
            j = randomInteger(ws, n_wavesets)
            tmp = wsOrder[ws]
            wsOrder[ws] = wsOrder[j]
            wsOrder[j] = tmp
        endfor
    else
        # CDP group-based shuffle (distort_shuf / do_shuffle)
        n_groups = floor(n_wavesets / groupSz)
        remainder = n_wavesets - n_groups * groupSz
        for g from 1 to n_groups
            groupOrder[g] = g
        endfor
        # Ascending Fisher-Yates on group indices
        for g from 1 to n_groups - 1
            j = randomInteger(g, n_groups)
            tmp = groupOrder[g]
            groupOrder[g] = groupOrder[j]
            groupOrder[j] = tmp
        endfor
        outIdx = 0
        for g from 1 to n_groups
            srcGroup = groupOrder[g]
            for m from 1 to groupSz
                outIdx = outIdx + 1
                wsOrder[outIdx] = (srcGroup - 1) * groupSz + m
            endfor
        endfor
        # Tail remainder: append unshuffled (CDP behaviour)
        for m from 1 to remainder
            outIdx = outIdx + 1
            wsOrder[outIdx] = n_groups * groupSz + m
        endfor
    endif
endif

# ============================================================
# STEP 4: BUILD INCLUDE/EXCLUDE MAP (types 8 and 9)
# ============================================================
#
# Mirrors CDP's get_loudest_cycle / get_quietest_cycle + do_cycle_loud /
# do_cycle_quiet logic: scan each group of <groupSz> wavesets, identify
# the loudest or quietest by energy, then mark which to keep.
# Remainder wavesets (tail group) are always kept unchanged.

if type = 8 or type = 9
    # Default: include all
    for ws from 1 to n_wavesets
        wsInclude[ws] = 1
    endfor

    n_full_groups = floor(n_wavesets / groupSz)

    for g from 0 to n_full_groups - 1
        groupStart = g * groupSz + 1      
		# 1-based
        groupEnd   = groupStart + groupSz - 1

        loudestWS  = groupStart
        quietestWS = groupStart
        for ws from groupStart to groupEnd
            if wsEnergy[ws] > wsEnergy[loudestWS]
                loudestWS = ws
            endif
            if wsEnergy[ws] < wsEnergy[quietestWS]
                quietestWS = ws
            endif
        endfor

        if type = 8
            # KEEP_STRONGEST: discard all but the loudest
            for ws from groupStart to groupEnd
                if ws <> loudestWS
                    wsInclude[ws] = 0
                endif
            endfor
        elsif type = 9
            # DELETE_WEAKEST: discard only the quietest
            wsInclude[quietestWS] = 0
        endif
    endfor
endif

# ============================================================
# STEP 5: EXTRACT, PROCESS, AND BATCH-CONCATENATE WAVESETS
# ============================================================

batchSize = 100
batchCount = 0
resultParts = 0

for wsIdx from 1 to n_wavesets
    if type = 6
        ws = wsOrder[wsIdx]
    else
        ws = wsIdx
    endif

    # Skip excluded wavesets (types 8 and 9)
    if (type = 8 or type = 9) and wsInclude[ws] = 0
        goto nextWaveset
    endif

    # Get waveset boundaries
    selectObject: ppZeroes
    t1 = Get time from index: ws
    t2 = Get time from index: ws + 1

    # Extract waveset (C-level)
    selectObject: monoWork
    Extract part: t1, t2, "rectangular", 1, "no"
    wsSound = selected("Sound")

    # ---- Per-type processing ----

    if type = 1
        # REPEAT with user-controlled exponential decay
        reps = round(amount) - 1
        if reps > 0
            selectObject: wsSound
            Copy: "ws_rep"
            wsRepeated = selected("Sound")
            for r from 1 to reps
                selectObject: wsSound
                Copy: "ws_copy"
                repCopy = selected("Sound")
                decay = repeat_decay ^ r
                Formula: "self * " + fixed$(decay, 6)
                selectObject: wsRepeated
                plusObject: repCopy
                Concatenate
                newRep = selected("Sound")
                removeObject: wsRepeated, repCopy
                wsRepeated = newRep
            endfor
            removeObject: wsSound
            wsSound = wsRepeated
        endif

    elsif type = 2
        # SKIP
        if randomUniform(0, 1) < (1 / amount)
            selectObject: wsSound
            Formula: "0"
        endif

    elsif type = 3
        # REVERSE
        selectObject: wsSound
        Reverse

    elsif type = 4
        # STRETCH (SR override)
        selectObject: wsSound
        wsSR = Get sampling frequency
        newSR = max(100, round(wsSR / amount))
        Override sampling frequency: newSR
        Resample: wsSR, 50
        wsNew = selected("Sound")
        removeObject: wsSound
        selectObject: wsNew
        Override sampling frequency: wsSR
        wsSound = wsNew

    elsif type = 5
        # COMPRESS (SR override)
        selectObject: wsSound
        wsSR = Get sampling frequency
        newSR = min(96000, round(wsSR * amount))
        Override sampling frequency: newSR
        Resample: wsSR, 50
        wsNew = selected("Sound")
        removeObject: wsSound
        selectObject: wsNew
        Override sampling frequency: wsSR
        wsSound = wsNew

    elsif type = 6
        # RANDOMIZE — order already resolved in wsOrder[], nothing extra needed

    elsif type = 7
        # AMPLITUDE alternating
        selectObject: wsSound
        if wsIdx mod 2 = 1
            Formula: "self * " + fixed$(amount, 4)
        else
            Formula: "self * " + fixed$(1 / amount, 4)
        endif

    # types 8 (Keep Strongest) and 9 (Delete Weakest):
    # waveset is already selected and included as-is; no further processing.

    endif

    # Accumulate into batch
    batchCount = batchCount + 1
    batchWS[batchCount] = wsSound

    if batchCount >= batchSize or wsIdx = n_wavesets
        selectObject: batchWS[1]
        for b from 2 to batchCount
            plusObject: batchWS[b]
        endfor
        if batchCount > 1
            Concatenate
            batchResult = selected("Sound")
            for b from 1 to batchCount
                removeObject: batchWS[b]
            endfor
        else
            batchResult = batchWS[1]
        endif
        resultParts = resultParts + 1
        resultPart[resultParts] = batchResult
        batchCount = 0
    endif

    if wsIdx mod 500 = 0 or wsIdx = n_wavesets
        appendInfoLine: "  Waveset ", wsIdx, " / ", n_wavesets
    endif

    label nextWaveset
endfor

# Flush any remaining batch (if last wavesets were excluded by goto)
if batchCount > 0
    selectObject: batchWS[1]
    for b from 2 to batchCount
        plusObject: batchWS[b]
    endfor
    if batchCount > 1
        Concatenate
        batchResult = selected("Sound")
        for b from 1 to batchCount
            removeObject: batchWS[b]
        endfor
    else
        batchResult = batchWS[1]
    endif
    resultParts = resultParts + 1
    resultPart[resultParts] = batchResult
    batchCount = 0
endif

# Final concatenation of batches
if resultParts > 1
    selectObject: resultPart[1]
    for rp from 2 to resultParts
        plusObject: resultPart[rp]
    endfor
    Concatenate
    result = selected("Sound")
    for rp from 1 to resultParts
        removeObject: resultPart[rp]
    endfor
else
    result = resultPart[1]
endif

removeObject: ppZeroes, monoWork

# ============================================================
# PRESERVE LENGTH (optional)
# ============================================================

if preserve_length
    selectObject: result
    resDur = Get total duration
    if resDur > original_duration
        Extract part: 0, original_duration, "rectangular", 1, "no"
        trimmed = selected("Sound")
        removeObject: result
        result = trimmed
    elsif resDur < original_duration - 0.001
        padDur = original_duration - resDur
        Create Sound from formula: "pad", 1, 0, padDur, sampling_rate, "0"
        padSound = selected("Sound")
        selectObject: result
        plusObject: padSound
        Concatenate
        padded = selected("Sound")
        removeObject: result, padSound
        result = padded
    endif
endif

# ============================================================
# FINALIZE
# ============================================================

selectObject: result
Scale peak: scale_peak
Rename: soundName$ + "_WSD_" + presetName$
resultID = selected("Sound")
resultDur = Get total duration

processingTime = stopwatch

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: "[3/3] Drawing..."

    Erase all
    Select outer viewport: 0, 8, 0, 8

    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "##Waveset Distortion##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.25, "half",
        ... soundName$ + "  |  " + presetName$
        ... + "  |  " + typeName$ + " x" + fixed$(amount, 1)

    Select outer viewport: 0, 8, 0.52, 1.52
    Select inner viewport: 0.55, 7.65, 0.57, 1.47
    selectObject: sound
    if numChannels > 1
        Extract one channel: 1
        vizIn = selected("Sound")
    else
        Copy: "vizIn"
        vizIn = selected("Sound")
    endif
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    removeObject: vizIn
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"

    Select outer viewport: 0, 8, 1.56, 2.56
    Select inner viewport: 0.55, 7.65, 1.61, 2.51
    selectObject: resultID
    Colour: "{0.25, 0.50, 0.82}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"

    Select outer viewport: 0, 4.1, 2.64, 4.04
    Select inner viewport: 0.55, 3.85, 2.74, 3.94
    selectObject: sound
    if numChannels > 1
        Extract one channel: 1
        vizSpecIn = selected("Sound")
    else
        Copy: "vizSpecIn"
        vizSpecIn = selected("Sound")
    endif
    To Spectrogram: 0.02, 5000, 0.005, 20, "Gaussian"
    specOrig = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    removeObject: specOrig, vizSpecIn
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Original"

    Select outer viewport: 4.1, 8, 2.64, 4.04
    Select inner viewport: 4.40, 7.65, 2.74, 3.94
    selectObject: resultID
    To Spectrogram: 0.02, 5000, 0.005, 20, "Gaussian"
    specRes = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    removeObject: specRes
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Waveset distortion"

    Select outer viewport: 0, 8, 4.14, 4.84
    Select inner viewport: 0.55, 7.65, 4.20, 4.78
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.78, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.02, "left", 0.42, "half",
        ... "Type: " + typeName$
        ... + "  |  Amount: " + fixed$(amount, 1)
        ... + "  |  Wavesets: " + string$(n_wavesets)
        ... + "  |  In: " + fixed$(original_duration, 2) + "s"
        ... + "  ->  Out: " + fixed$(resultDur, 2) + "s"
        ... + "  |  Time: " + fixed$(processingTime, 1) + "s"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# ============================================================
# OUTPUT
# ============================================================

selectObject: resultID

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Wavesets: ", n_wavesets
appendInfoLine: "In: ", fixed$(original_duration, 2), "s -> Out: ", fixed$(resultDur, 2), "s"
appendInfoLine: "Time: ", fixed$(processingTime, 1), " s"
appendInfoLine: "Created: ", selected$("Sound")

if play_result
    Play
endif

selectObject: resultID
