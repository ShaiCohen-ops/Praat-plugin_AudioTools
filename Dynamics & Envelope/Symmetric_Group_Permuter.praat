# ============================================================
# Praat AudioTools - Symmetric_Group_Permuter.praat
# Symmetric Group Permuter
# Segment permutation and iteration in S(n)
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# WHAT THIS DOES
#   Cuts the selected Sound into n segments - equal-duration
#   slices, safe-cut equal slices, silence/intensity events,
#   energy-change points, or intervals lifted from a paired
#   TextGrid - reorders those
#   segments according to a permutation sigma of Sn (the symmetric
#   group on {1..n}), raises sigma to the k-th power, and
#   reassembles the reordered segments into a single new Sound
#   using "Concatenate with overlap...", so no boundary lands as
#   a hard, clicking edit.
#
#   sigma can be typed directly in cycle notation, or generated
#   from a small library of named group elements (Preset, below),
#   which is the more usual way to explore Sn without having to
#   hand-write cycles. Whichever way sigma is obtained, the script
#   also computes and reports its actual group-theoretic profile -
#   cycle type, order, parity, and transposition count - for both
#   sigma itself and sigma^k, and can draw that structure.
#
# PERMUTATION CONVENTION (read this before typing cycles)
#   sigma(i) is read as "segment i MOVES TO output position
#   sigma(i)". So (1 3 2) means: segment 1 -> position 3, segment
#   3 -> position 2, segment 2 -> position 1; any segment not
#   named (e.g. segment 4 when n=4) stays a fixed point. This is
#   the ordinary "where does element i go" reading of cycle
#   notation, not its inverse ("what fills slot i"). Both readings
#   are legitimate conventions and differ only by sigma vs
#   sigma^-1, so the choice is stated explicitly here rather than
#   left to guesswork. sigma^k is sigma composed with itself k
#   times; k = 0 gives the untouched (identity) order and a
#   negative k applies the inverse permutation |k| times. All
#   presets below are built directly as sigma in this same
#   convention, so Iterations_k applies identically to them.
#
# GROUP-THEORETIC PRESETS
#   Preset picks a named element of Sn and overrides
#   Permutation_cycles entirely (that field, and its parser, are
#   only consulted when Preset = Custom):
#     Identity              - sigma(i) = i for all i. Order 1.
#     Reverse                - sigma(i) = n - i + 1. The
#       order-reversing involution; order 2 for n > 1 (order 1
#       only for n = 1). For odd n, the middle segment is a fixed
#       point but the remaining pairs are still transpositions.
#     Adjacent Transposition - swaps segments 1 and 2, identity
#       elsewhere. The simplest odd permutation, a single
#       transposition; needs n >= 2.
#     Pairwise Swap           - (1 2)(3 4)...; a local order-2
#       involution. For odd n the final segment remains fixed.
#     Cyclic Shift            - sigma(i) = ((i - 1 + s) mod n) + 1,
#       s = Shift_amount reduced mod n. An n-cycle whenever
#       gcd(s, n) = 1; otherwise it decomposes into gcd(s, n)
#       disjoint cycles of equal length n / gcd(s, n).
#     Random Permutation      - a uniform-random element of Sn,
#       Fisher-Yates shuffled under Random_seed (0 draws a
#       clock-derived seed, reported in the output).
#     Random Involution       - random maximal set of disjoint
#       transpositions; order 2, with one fixed point only when n
#       is odd.
#     Random Long Cycle       - a uniformly random single n-cycle;
#       all segments belong to one orbit and order = n (n > 1).
#     Derangement              - a uniform-random element of Sn
#       with NO fixed points, found by rejection sampling of the
#       above shuffle (bounded tries; n = 1 has no derangement and
#       falls back to the identity with a warning).
#
# GROUP-THEORETIC DIAGNOSTICS (computed, not asked for)
#   For both sigma and sigma^k the script decomposes the
#   permutation into disjoint cycles and reports:
#     cycle type    - the partition of n given by the cycle
#                      lengths, longest first (e.g. "3+2+1").
#     order           - lcm of the cycle lengths; the smallest
#                      m > 0 with (sigma^k)^m = identity.
#     parity          - "even"/"odd", i.e. the sign of the
#                      permutation, from the parity of
#                      sum(length - 1) over all cycles.
#     transpositions - that same sum(length - 1): the minimum
#                      number of transpositions the permutation
#                      decomposes into.
#     fixed points    - segments that do not move at all (the
#                      1-cycles).
#
# METHOD NOTES / DELIBERATE ADDITIONS
#   - "Concatenate with overlap..." concatenates whichever Sound
#     objects are selected in LIST order (creation order), not in
#     the order they were selected. This script therefore extracts
#     every segment directly into its final sequence position, so
#     the objects list order already IS the permuted order; nothing
#     needs to be re-sorted before concatenation.
#   - The crossfade is capped at half of the shortest of the n
#     segments so a fade can never overrun into a segment's own far
#     boundary.
#   - Equal Durations + Safe Cut keeps the equal temporal grid but
#     moves each interior cut by at most 20 ms (or 20% of one
#     nominal segment) to a local Intensity minimum.
#   - Acoustic Change Points (energy) searches around each nominal
#     boundary for the strongest local Intensity change. It is an
#     energy-change detector intended for legato material, not a
#     full spectral-flux segmentation claim.
#   - Silence/Intensity mode cannot promise exactly n boundaries on
#     arbitrary material. It detects silent/sounding transitions,
#     then either thins them (evenly, if there are more than
#     needed) or pads them (by bisecting the largest remaining gap,
#     if there are fewer than needed) until exactly n-1 interior
#     boundaries exist. Both adjustments are reported.
#   - TextGrid mode reads a single interval tier of a TextGrid that
#     must already be selected together with the Sound. It requires
#     at least n intervals and does not invent boundaries if there
#     are fewer; it exits with a clear message instead.
#   - Added form fields beyond the bare spec: Silence_threshold_dB
#     and Minimum_pitch_for_silence_Hz (Silence/Intensity mode
#     needs both and they should not be hardcoded), TextGrid_tier
#     (a TextGrid can have more than one tier), and Play_result.
#   - Iterations_k accepts 0 and negative integers, not just
#     positive powers, since sigma^0 and sigma^-1 are both
#     well-defined and useful.
# ============================================================

# === Input Validation ===
nSelectedSounds = numberOfSelected("Sound")
if nSelectedSounds <> 1
    exitScript: "Please select exactly one Sound object."
endif

snd = selected("Sound")
sndName$ = selected$("Sound")

# Grab this now: any later "selectObject: snd" (needed just to query
# duration, extract segments, etc.) silently deselects everything
# else, including a TextGrid the user paired with the Sound. Capture
# its ID up front so "Use Selected TextGrid" mode still has it later.
nSelectedTextGridsAtStart = numberOfSelected("TextGrid")
if nSelectedTextGridsAtStart = 1
    pairedTextGrid = selected("TextGrid")
else
    pairedTextGrid = -1
endif

# Changelog v2.3 (2026):
#   - VISUALIZATION / UI STANDARDIZATION ONLY. Audio analysis,
#     DSP, scheduling and rendering are unchanged from the
#     previous version.
#   - Adopted the Praat AudioTools 8-inch visualization header,
#     suite typography, neutral panel backgrounds, summary-style
#     reporting and full-page Picture export restoration.
#   - Preserved the script-specific diagnostic / transformation
#     views rather than replacing them with generic plots.
#
form Symmetric Group Permuter v2.3
    comment Segment permutation and iteration in S(n)
    optionmenu Preset: 1
        option Custom (use Permutation_cycles below)
        option Identity
        option Reverse
        option Adjacent Transposition
        option Pairwise Swap
        option Cyclic Shift
        option Random Permutation
        option Random Involution
        option Random Long Cycle
        option Derangement
    choice Segmentation_mode: 1
        option Equal Durations
        option Equal Durations + Safe Cut
        option Silence/Intensity Threshold
        option Acoustic Change Points (energy)
        option Use Selected TextGrid
    natural Group_degree_n 4
    sentence Permutation_cycles (1 3 2)
    natural Shift_amount 1
    integer Random_seed 0
    positive Crossfade_duration_ms 5.0
    integer Iterations_k 1
    positive Silence_threshold_dB 25.0
    positive Minimum_pitch_for_silence_Hz 100.0
    natural TextGrid_tier 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

warnLines$ = ""
usedSeed = 0

# ============================================================
# BASIC SOUND GEOMETRY
# ============================================================
selectObject: snd
sndXmin = Get start time
sndXmax = Get end time
dur = sndXmax - sndXmin
fs = Get sampling frequency

if dur <= 0
    exitScript: "Selected Sound has zero or negative duration."
endif

nSegs = group_degree_n

if segmentation_mode = 5 and nSegs < 1
    exitScript: "Group_degree_n must be at least 1."
endif

if dur / nSegs * fs < 4
    warnLines$ = warnLines$ + "  ! Average segment length is under 4 samples at this n; boundaries may collapse." + newline$
endif

# ============================================================
# sigma -> EITHER PARSED FROM Permutation_cycles (Preset = Custom)
# OR GENERATED FROM A NAMED GROUP-THEORETIC PRESET
# ============================================================
sigma# = zero#(nSegs)
for i from 1 to nSegs
    sigma#[i] = i
endfor

if preset = 1
    presetName$ = "Custom"

    # ------------------------------------------------------
    # CYCLE STRING PARSER -> sigma#
    # ------------------------------------------------------
    seenElements# = zero#(nSegs)
    nCyclesParsed = 0

    procedure applyCycle: .inner$
        .len = length(.inner$)
        .token$ = ""
        .nums# = zero#(max(.len, 1))
        .cnt = 0
        for .c from 1 to .len
            .ch$ = mid$(.inner$, .c, 1)
            if .ch$ = " " or .ch$ = tab$
                if length(.token$) > 0
                    .cnt = .cnt + 1
                    .nums#[.cnt] = number(.token$)
                    .token$ = ""
                endif
            else
                .token$ = .token$ + .ch$
            endif
        endfor
        if length(.token$) > 0
            .cnt = .cnt + 1
            .nums#[.cnt] = number(.token$)
        endif

        if .cnt = 1
            warnLines$ = warnLines$ + "  ! Single-element cycle (" + .inner$ + ") ignored (fixed point already)." + newline$
        elsif .cnt >= 2
            for .j from 1 to .cnt
                .a = .nums#[.j]
                if .j < .cnt
                    .b = .nums#[.j + 1]
                else
                    .b = .nums#[1]
                endif
                if .a < 1 or .a > nSegs or .b < 1 or .b > nSegs
                    exitScript: "Cycle element out of range 1.." + string$(nSegs) + " in Permutation_cycles."
                endif
                if seenElements#[.a] = 1
                    warnLines$ = warnLines$ + "  ! Element " + string$(.a) + " appears in more than one cycle; the later assignment wins." + newline$
                endif
                seenElements#[.a] = 1
                sigma#[.a] = .b
            endfor
            nCyclesParsed = nCyclesParsed + 1
        endif
    endproc

    cyclesClean$ = replace_regex$ (permutation_cycles$, "[^0-9() ,]", "", 0)
    cyclesClean$ = replace_regex$ (cyclesClean$, ",", " ", 0)
    remaining$ = cyclesClean$

    while index(remaining$, "(") > 0
        openIdx = index(remaining$, "(")
        closeIdx = index(remaining$, ")")
        if closeIdx = 0 or closeIdx < openIdx
            exitScript: "Malformed Permutation_cycles: unmatched '(' in """ + permutation_cycles$ + """."
        endif
        innerLen = closeIdx - openIdx - 1
        if innerLen > 0
            inner$ = mid$(remaining$, openIdx + 1, innerLen)
        else
            inner$ = ""
        endif
        @applyCycle: inner$
        tailStart = closeIdx + 1
        tailLen = length(remaining$) - closeIdx
        if tailLen > 0
            remaining$ = mid$(remaining$, tailStart, tailLen)
        else
            remaining$ = ""
        endif
    endwhile

    if nCyclesParsed = 0
        warnLines$ = warnLines$ + "  ! No valid cycles parsed; using the identity permutation (sigma(i) = i for all i)." + newline$
    endif

else
    # ------------------------------------------------------
    # NAMED GROUP-THEORETIC PRESET -> sigma# directly
    # ------------------------------------------------------
    if preset = 2
        presetName$ = "Identity"
        # sigma# is already the identity from the initialization above.

    elsif preset = 3
        presetName$ = "Reverse"
        for i from 1 to nSegs
            sigma#[i] = nSegs - i + 1
        endfor

    elsif preset = 4
        presetName$ = "AdjacentTransposition"
        if nSegs >= 2
            sigma#[1] = 2
            sigma#[2] = 1
        else
            warnLines$ = warnLines$ + "  ! Adjacent Transposition needs Group_degree_n >= 2; using the identity instead." + newline$
        endif

    elsif preset = 5
        presetName$ = "PairwiseSwap"
        i = 1
        while i + 1 <= nSegs
            sigma#[i] = i + 1
            sigma#[i + 1] = i
            i = i + 2
        endwhile
        # For odd n the final segment remains a fixed point.

    elsif preset = 6
        presetName$ = "CyclicShift"
        shiftEff = shift_amount mod nSegs
        if shiftEff < 0
            shiftEff = shiftEff + nSegs
        endif
        for i from 1 to nSegs
            sigma#[i] = ((i - 1 + shiftEff) mod nSegs) + 1
        endfor
        if shiftEff <> shift_amount
            warnLines$ = warnLines$ + "  ! Shift_amount reduced modulo n to " + string$(shiftEff) + "." + newline$
        endif

    elsif preset >= 7 and preset <= 10
        if preset = 7
            presetName$ = "RandomPermutation"
        elsif preset = 8
            presetName$ = "RandomInvolution"
        elsif preset = 9
            presetName$ = "RandomLongCycle"
        else
            presetName$ = "Derangement"
        endif

        if random_seed = 0
            now# = date_utc#()
            usedSeed = round(now#[3] * 86400 + now#[4] * 3600 + now#[5] * 60 + now#[6]) + 1
            if usedSeed < 1
                usedSeed = 1
            endif
        else
            usedSeed = abs(random_seed)
        endif
        random_initializeWithSeedUnsafelyButPredictably (usedSeed)

        if preset = 10 and nSegs = 1
            warnLines$ = warnLines$ + "  ! A derangement is impossible for Group_degree_n = 1; using the identity instead." + newline$

        elsif preset = 8
            # Random maximal involution: shuffle the elements, then pair
            # adjacent shuffled entries into disjoint transpositions.
            # For odd n exactly one shuffled element remains fixed.
            pool# = zero#(nSegs)
            for i from 1 to nSegs
                pool#[i] = i
            endfor
            i = nSegs
            while i >= 2
                j = randomInteger(1, i)
                tmp = pool#[i]
                pool#[i] = pool#[j]
                pool#[j] = tmp
                i = i - 1
            endwhile
            i = 1
            while i + 1 <= nSegs
                a = pool#[i]
                b = pool#[i + 1]
                sigma#[a] = b
                sigma#[b] = a
                i = i + 2
            endwhile

        elsif preset = 9
            # Uniform random n-cycle: a Fisher-Yates shuffled ordering of
            # all elements is interpreted as one cycle.  For n=1 this is
            # simply the identity.
            pool# = zero#(nSegs)
            for i from 1 to nSegs
                pool#[i] = i
            endfor
            i = nSegs
            while i >= 2
                j = randomInteger(1, i)
                tmp = pool#[i]
                pool#[i] = pool#[j]
                pool#[j] = tmp
                i = i - 1
            endwhile
            if nSegs > 1
                for i from 1 to nSegs - 1
                    sigma#[pool#[i]] = pool#[i + 1]
                endfor
                sigma#[pool#[nSegs]] = pool#[1]
            endif

        else
            # Random Permutation and Derangement retain the original
            # Fisher-Yates/rejection-sampling law.
            maxTries = 500
            tries = 0
            found = 0
            while found = 0 and tries < maxTries
                tries = tries + 1
                pool# = zero#(nSegs)
                for i from 1 to nSegs
                    pool#[i] = i
                endfor
                i = nSegs
                while i >= 2
                    j = randomInteger(1, i)
                    tmp = pool#[i]
                    pool#[i] = pool#[j]
                    pool#[j] = tmp
                    i = i - 1
                endwhile
                if preset = 7
                    found = 1
                else
                    hasFixed = 0
                    for i from 1 to nSegs
                        if pool#[i] = i
                            hasFixed = 1
                        endif
                    endfor
                    if hasFixed = 0
                        found = 1
                    endif
                endif
            endwhile

            if found = 1
                for i from 1 to nSegs
                    sigma#[i] = pool#[i]
                endfor
            else
                # A cyclic shift by one is a guaranteed derangement for every n > 1.
                warnLines$ = warnLines$ + "  ! Could not find a derangement in " + string$(maxTries) + " random draws; using the guaranteed cyclic derangement i->i+1 (mod n)." + newline$
                for i from 1 to nSegs
                    sigma#[i] = (i mod nSegs) + 1
                endfor
            endif
        endif
    endif
endif

# sigma# must be a genuine bijection on {1..nSegs}, or the inverse
# used below is not well-defined.
checkCount# = zero#(nSegs)
for i from 1 to nSegs
    v = sigma#[i]
    checkCount#[v] = checkCount#[v] + 1
endfor
badPermutation = 0
for i from 1 to nSegs
    if checkCount#[i] <> 1
        badPermutation = 1
    endif
endfor
if badPermutation = 1
    exitScript: "The resulting sigma does not describe a valid bijection on {1.." + string$(nSegs) + "}: an element is missing from or repeated across the cycles."
endif

# ============================================================
# EXPONENTIATION -> sigma^k
# ============================================================
if iterations_k >= 0
    kAbs = iterations_k
    baseSigma# = sigma#
else
    kAbs = -iterations_k
    baseSigma# = zero#(nSegs)
    for i from 1 to nSegs
        baseSigma#[sigma#[i]] = i
    endfor
    warnLines$ = warnLines$ + "  ! Iterations_k is negative: applying the inverse permutation " + string$(kAbs) + " time(s)." + newline$
endif

sigmaK# = zero#(nSegs)
for i from 1 to nSegs
    sigmaK#[i] = i
endfor
for step from 1 to kAbs
    nextSigmaK# = zero#(nSegs)
    for i from 1 to nSegs
        nextSigmaK#[i] = baseSigma#[sigmaK#[i]]
    endfor
    sigmaK# = nextSigmaK#
endfor

# inv#[p] = the source segment that sigma^k sends to output
# position p, i.e. the inverse of sigmaK#.
inv# = zero#(nSegs)
for i from 1 to nSegs
    inv#[sigmaK#[i]] = i
endfor

# ============================================================
# GROUP-THEORETIC ANALYSIS
# Cycle decomposition of both sigma and sigma^k: cycle type,
# order (lcm of cycle lengths), parity, transposition count,
# fixed-point count.
# ============================================================
procedure pgcd: .a, .b
    .x = .a
    .y = .b
    while .y <> 0
        .t = .y
        .y = .x mod .y
        .x = .t
    endwhile
    .result = .x
endproc

procedure analyzePermutation
    # Reads global permWork# (length nSegs). Leaves results in its
    # own dot-fields, copied out by the caller right after @-ing it.
    .visited# = zero#(nSegs)
    .nCycles = 0
    .fixedPoints = 0
    .order = 1
    .sumLenMinus1 = 0
    .cycleIdOf# = zero#(nSegs)
    .cycleLenList# = zero#(nSegs)
    for .i from 1 to nSegs
        if .visited#[.i] = 0
            .nCycles = .nCycles + 1
            .len = 0
            .j = .i
            while .visited#[.j] = 0
                .visited#[.j] = 1
                .cycleIdOf#[.j] = .nCycles
                .len = .len + 1
                .j = permWork#[.j]
            endwhile
            .cycleLenList#[.nCycles] = .len
            if .len = 1
                .fixedPoints = .fixedPoints + 1
            endif
            .sumLenMinus1 = .sumLenMinus1 + (.len - 1)
            @pgcd: .order, .len
            .order = .order * .len / pgcd.result
        endif
    endfor
    .transpositions = .sumLenMinus1
    if (.sumLenMinus1 mod 2) = 0
        .parity$ = "even"
    else
        .parity$ = "odd"
    endif

    .sortedLen# = zero#(.nCycles)
    for .c from 1 to .nCycles
        .sortedLen#[.c] = .cycleLenList#[.c]
    endfor
    for .a from 1 to .nCycles - 1
        for .b from 1 to .nCycles - .a
            if .sortedLen#[.b] < .sortedLen#[.b + 1]
                .tmp = .sortedLen#[.b]
                .sortedLen#[.b] = .sortedLen#[.b + 1]
                .sortedLen#[.b + 1] = .tmp
            endif
        endfor
    endfor
    .cycleType$ = ""
    for .c from 1 to .nCycles
        .cycleType$ = .cycleType$ + string$(.sortedLen#[.c])
        if .c < .nCycles
            .cycleType$ = .cycleType$ + "+"
        endif
    endfor
endproc

permWork# = sigma#
@analyzePermutation
sBase_nCycles = analyzePermutation.nCycles
sBase_order = analyzePermutation.order
sBase_parity$ = analyzePermutation.parity$
sBase_fixedPoints = analyzePermutation.fixedPoints
sBase_transpositions = analyzePermutation.transpositions
sBase_cycleType$ = analyzePermutation.cycleType$
sBase_cycleIdOf# = analyzePermutation.cycleIdOf#
sBase_cycleLenList# = analyzePermutation.cycleLenList#

permWork# = sigmaK#
@analyzePermutation
sK_nCycles = analyzePermutation.nCycles
sK_order = analyzePermutation.order
sK_parity$ = analyzePermutation.parity$
sK_fixedPoints = analyzePermutation.fixedPoints
sK_transpositions = analyzePermutation.transpositions
sK_cycleType$ = analyzePermutation.cycleType$
sK_cycleIdOf# = analyzePermutation.cycleIdOf#
sK_cycleLenList# = analyzePermutation.cycleLenList#

# ============================================================
# TIME BOUNDARY EXTRACTION -> times# (length nSegs + 1)
# ============================================================
times# = zero#(nSegs + 1)
times#[1] = sndXmin
times#[nSegs + 1] = sndXmax

if segmentation_mode = 1
    # --- Equal Durations ---
    segMethodName$ = "equal durations"
    for j from 2 to nSegs
        times#[j] = sndXmin + (j - 1) * dur / nSegs
    endfor

elsif segmentation_mode = 2
    # --- Equal Durations + Safe Cut ---
    # Preserve the equal-duration formal grid, but permit each interior
    # boundary to move by at most +/-20 ms (and at most 20% of one nominal
    # segment) toward the quietest local Intensity sample.  This reduces
    # arbitrary cuts through a sustained waveform without changing the
    # large-scale temporal design.
    segMethodName$ = "equal durations + safe cut"
    nominalSeg = dur / nSegs
    safeWindow = min(0.020, nominalSeg * 0.20)
    safeStep = min(0.002, max(0.0005, safeWindow / 20))
    selectObject: snd
    intSafe = To Intensity: minimum_pitch_for_silence_Hz, 0.005, "yes"
    for j from 2 to nSegs
        targetT = sndXmin + (j - 1) * nominalSeg
        loT = max(sndXmin, targetT - safeWindow)
        hiT = min(sndXmax, targetT + safeWindow)
        bestT = targetT
        selectObject: intSafe
        bestVal = Get value at time: targetT, "Cubic"
        if bestVal = undefined
            bestVal = 1e30
        endif
        t = loT
        while t <= hiT + safeStep * 0.25
            selectObject: intSafe
            val = Get value at time: t, "Cubic"
            if val <> undefined and val < bestVal
                bestVal = val
                bestT = t
            endif
            t = t + safeStep
        endwhile
        times#[j] = bestT
    endfor
    removeObject: intSafe

elsif segmentation_mode = 3
    # --- Silence/Intensity Threshold ---
    segMethodName$ = "silence/intensity threshold"
    selectObject: snd
    tgSil = To TextGrid (silences): minimum_pitch_for_silence_Hz, 0.0,
        ...-silence_threshold_dB, 0.05, 0.05, "silent", "sounding"
    nIntSil = Get number of intervals: 1
    candCount = nIntSil - 1
    needed = nSegs - 1

    if needed = 0
        # nothing to place: nSegs = 1
    elsif candCount <= 0
        warnLines$ = warnLines$ + "  ! No silence/sounding transitions detected; falling back to equal durations." + newline$
        for j from 2 to nSegs
            times#[j] = sndXmin + (j - 1) * dur / nSegs
        endfor
    else
        selectObject: tgSil
        candTimes# = zero#(candCount)
        for j from 1 to candCount
            candTimes#[j] = Get end time of interval: 1, j
        endfor

        chosen# = zero#(needed)
        if candCount >= needed
            if needed = 1
                chosen#[1] = candTimes#[round((candCount + 1) / 2)]
            else
                for j from 1 to needed
                    idx = round(1 + (j - 1) * (candCount - 1) / (needed - 1))
                    if idx < 1
                        idx = 1
                    endif
                    if idx > candCount
                        idx = candCount
                    endif
                    chosen#[j] = candTimes#[idx]
                endfor
            endif
        else
            # Fewer transitions than needed boundaries: use them all,
            # then bisect the largest remaining gap(s) until there
            # are exactly "needed" interior boundaries.
            segStart# = zero#(candCount + 2)
            segStart#[1] = sndXmin
            for j from 1 to candCount
                segStart#[j + 1] = candTimes#[j]
            endfor
            segStart#[candCount + 2] = sndXmax
            nSegCur = candCount + 1
            padNeeded = needed - candCount
            for p from 1 to padNeeded
                biggest = 0
                biggestIdx = 1
                for s from 1 to nSegCur
                    gap = segStart#[s + 1] - segStart#[s]
                    if gap > biggest
                        biggest = gap
                        biggestIdx = s
                    endif
                endfor
                mid = (segStart#[biggestIdx] + segStart#[biggestIdx + 1]) / 2
                newSegStart# = zero#(nSegCur + 2)
                for s from 1 to biggestIdx
                    newSegStart#[s] = segStart#[s]
                endfor
                newSegStart#[biggestIdx + 1] = mid
                for s from biggestIdx + 1 to nSegCur + 1
                    newSegStart#[s + 1] = segStart#[s]
                endfor
                segStart# = newSegStart#
                nSegCur = nSegCur + 1
            endfor
            for j from 1 to needed
                chosen#[j] = segStart#[j + 1]
            endfor
            warnLines$ = warnLines$ + "  ! Detected only " + string$(candCount) + " transition(s) for " + string$(needed) + " needed boundaries; " + string$(padNeeded) + " were filled by bisecting the largest remaining gap(s)." + newline$
        endif

        for j from 1 to needed
            times#[j + 1] = chosen#[j]
        endfor
    endif

    removeObject: tgSil

elsif segmentation_mode = 4
    # --- Acoustic Change Points (energy) ---
    # For each nominal interior boundary, search the middle 80% of the
    # neighbouring nominal segment span for the strongest local change in
    # Intensity.  This is deliberately an energy-change detector, not a
    # claim of full spectral-flux analysis.  It is useful for legato input
    # where silence boundaries do not exist but phrase/note energy changes do.
    segMethodName$ = "acoustic change points (energy)"
    nominalSeg = dur / nSegs
    searchHalf = nominalSeg * 0.40
    changeLag = min(0.015, max(0.003, nominalSeg * 0.05))
    changeStep = min(0.005, max(0.001, nominalSeg / 80))
    selectObject: snd
    intChange = To Intensity: minimum_pitch_for_silence_Hz, 0.005, "yes"
    for j from 2 to nSegs
        targetT = sndXmin + (j - 1) * nominalSeg
        loT = max(sndXmin + changeLag, targetT - searchHalf)
        hiT = min(sndXmax - changeLag, targetT + searchHalf)
        bestT = targetT
        bestScore = -1
        t = loT
        while t <= hiT + changeStep * 0.25
            selectObject: intChange
            v0 = Get value at time: t - changeLag, "Cubic"
            v1 = Get value at time: t + changeLag, "Cubic"
            if v0 <> undefined and v1 <> undefined
                score = abs(v1 - v0)
                if score > bestScore
                    bestScore = score
                    bestT = t
                endif
            endif
            t = t + changeStep
        endwhile
        times#[j] = bestT
    endfor
    removeObject: intChange

elsif segmentation_mode = 5
    # --- Use Selected TextGrid ---
    if pairedTextGrid = -1
        exitScript: "Use Selected TextGrid mode requires exactly one TextGrid, paired with the Sound, to be selected together before running this script."
    endif
    tg = pairedTextGrid
    selectObject: tg
    nTiers = Get number of tiers
    if textGrid_tier < 1 or textGrid_tier > nTiers
        exitScript: "TextGrid_tier " + string$(textGrid_tier) + " does not exist (the TextGrid has " + string$(nTiers) + " tier(s))."
    endif
    nInt = Get number of intervals: textGrid_tier
    if nInt < nSegs
        exitScript: "TextGrid tier " + string$(textGrid_tier) + " has only " + string$(nInt) + " interval(s); Group_degree_n = " + string$(nSegs) + " needs at least that many."
    endif
    for j from 1 to nSegs
        times#[j] = Get start time of interval: textGrid_tier, j
    endfor
    segMethodName$ = "selected TextGrid, tier " + string$(textGrid_tier)
    if nInt > nSegs
        warnLines$ = warnLines$ + "  ! TextGrid tier has " + string$(nInt) + " intervals; only the first " + string$(nSegs) + " boundaries are used and the final segment absorbs everything up to the end of the file." + newline$
    endif
endif
# Every boundary must lie inside the selected Sound's actual time domain.
# This preserves zero-xmin behaviour exactly while making shifted Sounds safe.
for j from 1 to nSegs + 1
    if times#[j] < sndXmin - 1e-10 or times#[j] > sndXmax + 1e-10
        exitScript: "Computed boundary " + string$(j) + " lies outside the Sound domain [" + fixed$(sndXmin, 6) + ", " + fixed$(sndXmax, 6) + "]. Check the selected TextGrid/segmentation settings."
    endif
endfor

for j from 1 to nSegs
    if times#[j + 1] <= times#[j]
        exitScript: "Computed a non-positive-duration segment at position " + string$(j) + "; check Group_degree_n and the segmentation settings."
    endif
endfor

# ============================================================
# CROSSFADE LENGTH, CAPPED TO HALF THE SHORTEST SEGMENT
# ============================================================
segDur# = zero#(nSegs)
minSegDur = times#[2] - times#[1]
for j from 1 to nSegs
    segDur#[j] = times#[j + 1] - times#[j]
    if segDur#[j] < minSegDur
        minSegDur = segDur#[j]
    endif
endfor

fadeSec = crossfade_duration_ms / 1000
if nSegs > 1 and fadeSec > minSegDur / 2
    fadeSec = minSegDur / 2
    warnLines$ = warnLines$ + "  ! Crossfade (" + fixed$(crossfade_duration_ms,2) + " ms) exceeds half of the shortest segment -> capped to " + fixed$(1000 * fadeSec,2) + " ms." + newline$
endif
if fadeSec < 0
    fadeSec = 0
endif

# ============================================================
# SLICING & ASSEMBLY
# Segments are extracted directly INTO their permuted sequence
# position, so objects-list order already equals output order -
# required because "Concatenate with overlap..." concatenates in
# list order, not selection order.
# ============================================================
tempIDs# = zero#(nSegs)
for p from 1 to nSegs
    srcIdx = inv#[p]
    selectObject: snd
    seg = Extract part: times#[srcIdx], times#[srcIdx + 1], "rectangular", 1, "no"
    Rename: "sgp_seg_pos" + string$(p) + "_src" + string$(srcIdx)
    tempIDs#[p] = seg
endfor

if nSegs = 1
    outSnd = tempIDs#[1]
else
    selectObject: tempIDs#
    outSnd = Concatenate with overlap: fadeSec
endif

outName$ = sndName$ + "_S" + string$(nSegs) + "_permuted"
selectObject: outSnd
Rename: outName$

# ============================================================
# CLEANUP
# ============================================================
if nSegs > 1
    removeObject: tempIDs#
endif
# Note: a user-supplied TextGrid (segmentation_mode = 5) is never
# removed. Temporary Intensity/TextGrid analysis objects from modes 2-4
# are removed immediately after their boundaries are computed.

selectObject: outSnd
outDur = Get total duration

# ============================================================
# VISUALIZATION
# AudioTools 2x2 layout: A permutation matrix, B cycle diagram,
# C reorder slopegraph, D source/output waveform. All measured
# from sigma^k and the actual assembled audio, not from settings.
# ============================================================
if draw_visualization
    appendInfoLine: "Drawing group-theoretic visualization..."

    procedure sgpStep: .range, .target
        .raw = .range / .target
        .mag = 10 ^ floor(log10(max(1e-12, .raw)))
        .n = .raw / .mag
        if .n < 1.5
            .step = 1 * .mag
        elsif .n < 3.5
            .step = 2 * .mag
        elsif .n < 7.5
            .step = 5 * .mag
        else
            .step = 10 * .mag
        endif
    endproc

    procedure sgpColor: .cycleId, .cycLen
        # AudioTools house palette: primary blue with restrained
        # blue/teal/slate/violet accents. Fixed points stay neutral grey.
        if .cycLen = 1
            .col$ = "{0.58,0.60,0.64}"
        else
            .m = ((.cycleId - 1) mod 7) + 1
            if .m = 1
                .col$ = "{0.20,0.40,0.75}"
            elsif .m = 2
                .col$ = "{0.20,0.58,0.70}"
            elsif .m = 3
                .col$ = "{0.28,0.54,0.52}"
            elsif .m = 4
                .col$ = "{0.40,0.48,0.66}"
            elsif .m = 5
                .col$ = "{0.50,0.40,0.68}"
            elsif .m = 6
                .col$ = "{0.32,0.56,0.72}"
            else
                .col$ = "{0.68,0.55,0.28}"
            endif
        endif
    endproc

    selectObject: snd
    srcPeak = Get absolute extremum: 0, 0, "None"
    selectObject: outSnd
    outPeak = Get absolute extremum: 0, 0, "None"
    srcYr = 1.08 * max(1e-6, max(srcPeak, outPeak))

    # Marker geometry is expressed explicitly in each panel's world axes.
    # Do not use Paint circle here: its radius semantics can produce giant
    # discs when the world ranges differ strongly between panels.
    matrixHalf = 0.16
    cycleHalf = 0.085
    slopeXHalf = 0.025
    slopeYHalf = 0.16

    Erase all

    # ---------------- Suite header ----------------
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Symmetric Group Permuter v2.3##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", presetName$ + " | S" + string$(nSegs) + " | source i -> position sigma^" + string$(iterations_k) + "(i) | cycle type " + sK_cycleType$ + " | " + segMethodName$

    # ========================================================
    # A  PERMUTATION MATRIX
    # ========================================================
    Select outer viewport: 0.18, 3.92, 0.84, 1.10
    Select inner viewport: 0.18, 3.92, 0.84, 1.10
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.01, "left", 0.72, "half", "A  PERMUTATION MATRIX - source i -> position sigma^k(i)"
    Font size: 6
    Colour: "{0.34,0.38,0.48}"
    Text: 0.01, "left", 0.18, "half", "identity reference in pale blue-grey | cycle membership in AudioTools colours"

    Select outer viewport: 0.18, 3.92, 1.11, 3.12
    Select inner viewport: 0.62, 3.78, 1.22, 2.94
    Axes: 0.5, nSegs + 0.5, nSegs + 0.5, 0.5
    Paint rectangle: "{0.965,0.972,0.985}", 0.5, nSegs + 0.5, 0.5, nSegs + 0.5

    Colour: "{0.76,0.80,0.88}"
    Draw line: 0.5, 0.5, nSegs + 0.5, nSegs + 0.5

    for i from 1 to nSegs
        Select inner viewport: 0.62, 3.78, 1.22, 2.94
        Axes: 0.5, nSegs + 0.5, nSegs + 0.5, 0.5
        @sgpColor: sK_cycleIdOf#[i], sK_cycleLenList#[sK_cycleIdOf#[i]]
        Paint rectangle: sgpColor.col$, i - matrixHalf, i + matrixHalf, sigmaK#[i] - matrixHalf, sigmaK#[i] + matrixHalf
    endfor

    Select inner viewport: 0.62, 3.78, 1.22, 2.94
    Axes: 0.5, nSegs + 0.5, nSegs + 0.5, 0.5
    Colour: "Black"
    Draw inner box
    Font size: 6
    @sgpStep: nSegs, 5
    Marks bottom every: 1, sgpStep.step, "yes", "yes", "no"
    Marks left every: 1, sgpStep.step, "yes", "yes", "no"
    Font size: 6
    Text bottom: "yes", "source segment i"
    Text left: "yes", "output position"

    # ========================================================
    # B  CYCLE DIAGRAM
    # ========================================================
    Select outer viewport: 4.08, 7.82, 0.84, 1.10
    Select inner viewport: 4.08, 7.82, 0.84, 1.10
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.01, "left", 0.72, "half", "B  CYCLE DIAGRAM - sigma^k as a directed graph"
    Font size: 6
    Colour: "{0.34,0.38,0.48}"
    Text: 0.01, "left", 0.18, "half", "order " + string$(sK_order) + " | parity " + sK_parity$ + " | " + string$(sK_transpositions) + " transposition(s)"

    Select outer viewport: 4.08, 7.82, 1.11, 3.12
    Select inner viewport: 5.10, 6.80, 1.27, 2.97
    Axes: -1.15, 1.15, -1.15, 1.15
    Paint rectangle: "{0.965,0.972,0.985}", -1.15, 1.15, -1.15, 1.15

    nodeX# = zero#(nSegs)
    nodeY# = zero#(nSegs)
    for i from 1 to nSegs
        ang = pi / 2 - 2 * pi * (i - 1) / nSegs
        nodeX#[i] = 0.85 * cos(ang)
        nodeY#[i] = 0.85 * sin(ang)
    endfor

    # Edges first, then compact nodes on top.
    for i from 1 to nSegs
        Select inner viewport: 5.10, 6.80, 1.27, 2.97
        Axes: -1.15, 1.15, -1.15, 1.15
        dest = sigmaK#[i]
        if dest <> i
            @sgpColor: sK_cycleIdOf#[i], sK_cycleLenList#[sK_cycleIdOf#[i]]
            Colour: sgpColor.col$
            Draw line: nodeX#[i], nodeY#[i], nodeX#[dest], nodeY#[dest]
            # World-coordinate arrowhead near the destination.
            dx = nodeX#[dest] - nodeX#[i]
            dy = nodeY#[dest] - nodeY#[i]
            edgeLen = sqrt(dx * dx + dy * dy)
            if edgeLen > 1e-8
                ux = dx / edgeLen
                uy = dy / edgeLen
                px = -uy
                py = ux
                tipX = nodeX#[i] + 0.78 * dx
                tipY = nodeY#[i] + 0.78 * dy
                backX = tipX - 0.10 * ux
                backY = tipY - 0.10 * uy
                Draw line: tipX, tipY, backX + 0.055 * px, backY + 0.055 * py
                Draw line: tipX, tipY, backX - 0.055 * px, backY - 0.055 * py
            endif
        endif
    endfor

    for i from 1 to nSegs
        Select inner viewport: 5.10, 6.80, 1.27, 2.97
        Axes: -1.15, 1.15, -1.15, 1.15
        @sgpColor: sK_cycleIdOf#[i], sK_cycleLenList#[sK_cycleIdOf#[i]]
        Paint rectangle: sgpColor.col$, nodeX#[i] - cycleHalf, nodeX#[i] + cycleHalf, nodeY#[i] - cycleHalf, nodeY#[i] + cycleHalf
        Select inner viewport: 5.10, 6.80, 1.27, 2.97
        Axes: -1.15, 1.15, -1.15, 1.15
        Colour: "White"
        Font size: 6
        Text: nodeX#[i], "centre", nodeY#[i], "half", string$(i)
    endfor

    # ========================================================
    # C  REORDER SLOPEGRAPH
    # ========================================================
    Select outer viewport: 0.18, 3.92, 3.30, 3.56
    Select inner viewport: 0.18, 3.92, 3.30, 3.56
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.01, "left", 0.72, "half", "C  REORDER MAP - segment 1..n before / after"
    Font size: 6
    Colour: "{0.34,0.38,0.48}"
    Text: 0.01, "left", 0.18, "half", "left = source order | right = output order | fixed points in grey"

    Select outer viewport: 0.18, 3.92, 3.57, 5.48
    Select inner viewport: 0.62, 3.78, 3.68, 5.30
    Axes: -0.2, 1.2, nSegs + 0.6, 0.4
    Paint rectangle: "{0.965,0.972,0.985}", -0.2, 1.2, 0.4, nSegs + 0.6

    for i from 1 to nSegs
        @sgpColor: sK_cycleIdOf#[i], sK_cycleLenList#[sK_cycleIdOf#[i]]
        Colour: sgpColor.col$
        Draw line: 0, i, 1, sigmaK#[i]
    endfor
    for i from 1 to nSegs
        Select inner viewport: 0.62, 3.78, 3.68, 5.30
        Axes: -0.2, 1.2, nSegs + 0.6, 0.4
        @sgpColor: sK_cycleIdOf#[i], sK_cycleLenList#[sK_cycleIdOf#[i]]
        Paint rectangle: sgpColor.col$, -slopeXHalf, slopeXHalf, i - slopeYHalf, i + slopeYHalf
        Select inner viewport: 0.62, 3.78, 3.68, 5.30
        Axes: -0.2, 1.2, nSegs + 0.6, 0.4
        Paint rectangle: sgpColor.col$, 1 - slopeXHalf, 1 + slopeXHalf, sigmaK#[i] - slopeYHalf, sigmaK#[i] + slopeYHalf
    endfor
    Select inner viewport: 0.62, 3.78, 3.68, 5.30
    Axes: -0.2, 1.2, nSegs + 0.6, 0.4
    Colour: "Black"
    Font size: 6
    Text: -0.06, "right", 0.4, "bottom", "src"
    Text: 1.06, "left", 0.4, "bottom", "out"

    # ========================================================
    # D  WAVEFORM - SOURCE vs PERMUTED OUTPUT
    # ========================================================
    Select outer viewport: 4.08, 7.82, 3.30, 3.56
    Select inner viewport: 4.08, 7.82, 3.30, 3.56
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.01, "left", 0.72, "half", "D  WAVEFORM - source (top) vs permuted output (bottom)"
    Font size: 6
    Colour: "{0.34,0.38,0.48}"
    Text: 0.01, "left", 0.18, "half", "dotted lines = splice boundaries | labels use the same cycle colours as A/B/C"

    Select outer viewport: 4.08, 7.82, 3.57, 4.52
    Select inner viewport: 4.50, 7.62, 3.65, 4.48
    Axes: sndXmin, sndXmax, -srcYr, srcYr
    Paint rectangle: "{0.965,0.972,0.985}", sndXmin, sndXmax, -srcYr, srcYr
    selectObject: snd
    Colour: "{0.32,0.34,0.38}"
    Draw: sndXmin, sndXmax, -srcYr, srcYr, "no", "Curve"
    Select inner viewport: 4.50, 7.62, 3.65, 4.48
    Axes: sndXmin, sndXmax, -srcYr, srcYr
    Dotted line
    for j from 2 to nSegs
        Colour: "{0.70,0.74,0.82}"
        Draw line: times#[j], -srcYr, times#[j], srcYr
    endfor
    Solid line
    for i from 1 to nSegs
        @sgpColor: sK_cycleIdOf#[i], sK_cycleLenList#[sK_cycleIdOf#[i]]
        Colour: sgpColor.col$
        Text: (times#[i] + times#[i + 1]) / 2, "centre", 0.92 * srcYr, "half", string$(i)
    endfor
    Select inner viewport: 4.50, 7.62, 3.65, 4.48
    Axes: sndXmin, sndXmax, -srcYr, srcYr
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "src"

    # Actual segment start positions in the overlapped output. Each join
    # advances by segment duration minus the effective overlap; the final
    # endpoint is the measured output duration.
    outBoundaries# = zero#(nSegs + 1)
    outBoundaries#[1] = 0
    if nSegs > 1
        for p from 1 to nSegs - 1
            outBoundaries#[p + 1] = outBoundaries#[p] + segDur#[inv#[p]] - fadeSec
        endfor
    endif
    outBoundaries#[nSegs + 1] = outDur

    Select outer viewport: 4.08, 7.82, 4.53, 5.48
    Select inner viewport: 4.50, 7.62, 4.61, 5.44
    Axes: 0, outDur, -srcYr, srcYr
    Paint rectangle: "{0.965,0.972,0.985}", 0, outDur, -srcYr, srcYr
    selectObject: outSnd
    Colour: "{0.20,0.40,0.75}"
    Draw: 0, outDur, -srcYr, srcYr, "no", "Curve"
    Select inner viewport: 4.50, 7.62, 4.61, 5.44
    Axes: 0, outDur, -srcYr, srcYr
    Dotted line
    for p from 2 to nSegs
        Colour: "{0.70,0.74,0.82}"
        Draw line: outBoundaries#[p], -srcYr, outBoundaries#[p], srcYr
    endfor
    Solid line
    for p from 1 to nSegs
        @sgpColor: sK_cycleIdOf#[inv#[p]], sK_cycleLenList#[sK_cycleIdOf#[inv#[p]]]
        Colour: sgpColor.col$
        Text: (outBoundaries#[p] + outBoundaries#[p + 1]) / 2, "centre", 0.92 * srcYr, "half", string$(inv#[p])
    endfor
    Select inner viewport: 4.50, 7.62, 4.61, 5.44
    Axes: 0, outDur, -srcYr, srcYr
    Colour: "Black"
    Draw inner box
    Font size: 6
    @sgpStep: outDur, 5
    Marks bottom every: 1, sgpStep.step, "yes", "yes", "no"
    Font size: 6
    Text bottom: "yes", "time (s)"
    Text left: "yes", "out"

    # ---------------- Bottom summary ----------------
    Select outer viewport: 0.18, 7.82, 5.67, 6.18
    Select inner viewport: 0.18, 7.82, 5.67, 6.18
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text: 0.02, "left", 0.67, "half", "PRESET " + presetName$ + "   |   n " + string$(nSegs) + "   |   sigma " + sBase_cycleType$ + "  order " + string$(sBase_order) + "  " + sBase_parity$ + "   |   sigma^" + string$(iterations_k) + " " + sK_cycleType$ + "  order " + string$(sK_order) + "  " + sK_parity$
    Font size: 7
    Colour: "{0.34,0.38,0.48}"
    seedNote$ = ""
    if preset >= 7 and preset <= 10
        seedNote$ = " | seed " + string$(usedSeed)
    endif
    Text: 0.02, "left", 0.24, "half", "fixed points " + string$(sK_fixedPoints) + "/" + string$(nSegs) + " | transpositions " + string$(sK_transpositions) + " | segmentation " + segMethodName$ + " | crossfade " + fixed$(1000 * fadeSec, 2) + " ms" + seedNote$
    # Restore complete page for Picture export / clipboard.
    pageHeight = 6.33
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line

endif

# ============================================================
# REPORT
# ============================================================
sigmaStr$ = ""
sigmaKStr$ = ""
for i from 1 to nSegs
    sigmaStr$ = sigmaStr$ + string$(i) + "->" + string$(sigma#[i])
    sigmaKStr$ = sigmaKStr$ + string$(i) + "->" + string$(sigmaK#[i])
    if i < nSegs
        sigmaStr$ = sigmaStr$ + ", "
        sigmaKStr$ = sigmaKStr$ + ", "
    endif
endfor

orderStr$ = ""
for p from 1 to nSegs
    orderStr$ = orderStr$ + string$(inv#[p])
    if p < nSegs
        orderStr$ = orderStr$ + " "
    endif
endfor

appendInfoLine: ""
appendInfoLine: "=== Symmetric Group Permuter: COMPLETE ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Segments: ", nSegs, " (", segMethodName$, ")"
appendInfoLine: "sigma:     ", sigmaStr$
appendInfoLine: "  cycle type ", sBase_cycleType$, " | order ", sBase_order, " | ", sBase_parity$, " | ", sBase_transpositions, " transposition(s) | ", sBase_fixedPoints, " fixed point(s)"
appendInfoLine: "sigma^", iterations_k, ":  ", sigmaKStr$
appendInfoLine: "  cycle type ", sK_cycleType$, " | order ", sK_order, " | ", sK_parity$, " | ", sK_transpositions, " transposition(s) | ", sK_fixedPoints, " fixed point(s)"
appendInfoLine: "Output sequence (source segment at each output position 1..", nSegs, "): ", orderStr$
if preset >= 7 and preset <= 10
    appendInfoLine: "Random seed used: ", usedSeed
endif
appendInfoLine: "Crossfade: ", fixed$(1000 * fadeSec, 2), " ms effective (", fixed$(crossfade_duration_ms, 2), " ms requested)"
appendInfoLine: "Output duration: ", fixed$(outDur, 3), " s (source ", fixed$(dur, 3), " s)"
appendInfoLine: "New object: Sound ", outName$
if warnLines$ <> ""
    appendInfoLine: ""
    appendInfoLine: "Adjustments made during processing:"
    appendInfo: warnLines$
endif

selectObject: outSnd

if play_result
    appendInfoLine: "Playing..."
    Play
endif
