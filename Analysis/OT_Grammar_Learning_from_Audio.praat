# ============================================================
# Praat AudioTools - OT_Grammar_Learning_from_Audio.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2026) — reviewed learning/extraction fix
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Learns a melodic well-formedness grammar from audio using
#   error-driven constraint ranking. Two algorithms are provided:
#
#     GLA — Boersma's Gradual Learning Algorithm (Boersma 1997,
#           Boersma & Hayes 2001). Stochastic OT: each constraint
#           has a continuous ranking value; on each winner/loser
#           pair the learner promotes constraints that prefer the
#           winner and demotes constraints that prefer the loser,
#           each by a small `plasticity` step. Evaluation-time
#           noise converts ranking values into a discrete ranking
#           probabilistically. Handles variation and partial data.
#
#     RCD — Tesar & Smolensky's Recursive Constraint Demotion
#           (Tesar & Smolensky 1993, 2000). Classical OT: constraints
#           are strictly ordered into strata. Converges to a stratified
#           ranking if one exists consistent with all pairs; returns
#           the highest-stratum ranking it can reach otherwise.
#
#   GEN (candidate generator) has two modes:
#
#     Neighbor-GEN (single file):
#       The extracted melody is the winner. Losers are generated
#       by perturbing one note at a time by +-1 and +-2 semitones.
#       Learns "which constraints explain why this melody is
#       locally optimal against its neighbors." Inductive bias:
#       the winner is already locally optimal.
#
#     Pair-corpus (good/bad folders):
#       User picks a parent folder containing subfolders `good/`
#       and `bad/`. Good-vs-bad melodies become winner/loser
#       pairs (up to the pair-corpus safety cap below). This is
#       the linguistically orthodox setup and produces a real
#       stylistic grammar.
#
#   What this script does NOT claim:
#     - It does not learn from distributional statistics alone.
#     - It does not discover new constraints; the constraint set
#       is fixed (15 melodic constraints; see CONSTRAINT SET below).
#     - It does not implement MaxEnt or Harmonic Grammar weight
#       estimation. With zero evaluation noise, GLA evaluation is
#       deterministic OT ranking, not Harmonic Grammar.
#
# Usage:
#   Single-file mode:   select one Sound, run script.
#   Pair-corpus mode:   select one Sound (template for pitch
#                       settings), run script, pick folder.
#
# Citations:
#   Boersma, P. (1997). How we learn variation, optionality and
#     probability. IFA Proceedings 21: 43-58.
#   Boersma, P. & Hayes, B. (2001). Empirical tests of the Gradual
#     Learning Algorithm. Linguistic Inquiry 32: 45-86.
#   Tesar, B. & Smolensky, P. (2000). Learnability in Optimality
#     Theory. MIT Press.
#   Cohen, S. (2026). Praat AudioTools. https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

soundID    = selected("Sound")
soundName$ = selected$("Sound")

form OT Grammar Learning from Audio
    comment === Instrument ===
    optionmenu Instrument: 1
        option Violin
        option Vocal
        option Guitar
        option Flute
        option Piano
        option Other
    comment === Scale ===
    optionmenu Scale: 1
        option C major
        option G major
        option D major
        option A major
        option E major
        option F major
        option Bb major
        option Eb major
        option A minor (natural)
        option E minor (natural)
        option D minor (natural)
        option A minor (harmonic)
        option Chromatic (no quantization)
    boolean Quantize_to_scale 0
    positive Min_note_duration_ms 80
    comment === GEN (candidate generator) ===
    optionmenu GEN_mode: 1
        option Neighbor-GEN (single file)
        option Pair-corpus (good/bad folders)
    natural  Perturbation_max_semitones 2
    comment === Learning algorithm ===
    optionmenu Algorithm: 1
        option GLA (Gradual Learning Algorithm)
        option RCD (Recursive Constraint Demotion)
    natural  GLA_iterations 2000
    positive GLA_plasticity 0.5
    real     GLA_eval_noise 2.0
    positive GLA_initial_ranking_value 100
    comment === Output ===
    boolean Show_visualization 1
    boolean Create_output_table 1
endform

if gLA_eval_noise < 0
    exitScript: "GLA evaluation noise must be zero or positive."
endif

clearinfo

# ============================================================
# Instrument pitch-tracker settings
# ============================================================
if instrument = 1
    minPitch = 180
    maxPitch = 800
    timeStep = 0.005
    voicingThreshold = 0.25
    instrumentName$ = "Violin"
elsif instrument = 2
    minPitch = 75
    maxPitch = 600
    timeStep = 0.01
    voicingThreshold = 0.35
    instrumentName$ = "Vocal"
elsif instrument = 3
    minPitch = 80
    maxPitch = 500
    timeStep = 0.01
    voicingThreshold = 0.30
    instrumentName$ = "Guitar"
elsif instrument = 4
    minPitch = 200
    maxPitch = 2000
    timeStep = 0.005
    voicingThreshold = 0.40
    instrumentName$ = "Flute"
elsif instrument = 5
    minPitch = 50
    maxPitch = 2000
    timeStep = 0.01
    voicingThreshold = 0.45
    instrumentName$ = "Piano"
else
    minPitch = 75
    maxPitch = 600
    timeStep = 0.01
    voicingThreshold = 0.35
    instrumentName$ = "Other"
endif

# ============================================================
# Scale pitch-class sets — corrected from v0.3.
# Stored directly as PC arrays instead of parsing strings.
# Keyed scales provide a tonic for cadence constraints; Chromatic
# deliberately does not.
# ============================================================
scaleHasTonic = 1
if scale = 1
    scaleName$ = "C major"
    scalePC# = {0, 2, 4, 5, 7, 9, 11}
    tonicPC = 0
elsif scale = 2
    scaleName$ = "G major"
    scalePC# = {7, 9, 11, 0, 2, 4, 6}
    tonicPC = 7
elsif scale = 3
    scaleName$ = "D major"
    scalePC# = {2, 4, 6, 7, 9, 11, 1}
    tonicPC = 2
elsif scale = 4
    scaleName$ = "A major"
    scalePC# = {9, 11, 1, 2, 4, 6, 8}
    tonicPC = 9
elsif scale = 5
    scaleName$ = "E major"
    scalePC# = {4, 6, 8, 9, 11, 1, 3}
    tonicPC = 4
elsif scale = 6
    scaleName$ = "F major"
    scalePC# = {5, 7, 9, 10, 0, 2, 4}
    tonicPC = 5
elsif scale = 7
    scaleName$ = "Bb major"
    scalePC# = {10, 0, 2, 3, 5, 7, 9}
    tonicPC = 10
elsif scale = 8
    scaleName$ = "Eb major"
    scalePC# = {3, 5, 7, 8, 10, 0, 2}
    tonicPC = 3
elsif scale = 9
    scaleName$ = "A minor (natural)"
    scalePC# = {9, 11, 0, 2, 4, 5, 7}
    tonicPC = 9
elsif scale = 10
    scaleName$ = "E minor (natural)"
    scalePC# = {4, 6, 7, 9, 11, 0, 2}
    tonicPC = 4
elsif scale = 11
    scaleName$ = "D minor (natural)"
    scalePC# = {2, 4, 5, 7, 9, 10, 0}
    tonicPC = 2
elsif scale = 12
    scaleName$ = "A minor (harmonic)"
    scalePC# = {9, 11, 0, 2, 4, 5, 8}
    tonicPC = 9
else
    scaleName$ = "Chromatic"
    scalePC# = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11}
    tonicPC = 0
    scaleHasTonic = 0
    quantize_to_scale = 0
endif
numScalePCs = size(scalePC#)

# ============================================================
# CONSTRAINT SET
# 15 constraints. Each has a fixed index so ranking values and
# weights can live in parallel arrays indexed 1..nConstraints.
# Names starting with "*" are markedness (penalize); others are
# positive well-formedness conditions (counted as violations
# when NOT met).
# ============================================================
nConstraints = 15

constraintName$[1]  = "*LEAP"
constraintName$[2]  = "*TRITONE"
constraintName$[3]  = "*NONSTEP"
constraintName$[4]  = "*REPEAT"
constraintName$[5]  = "*SEMITONE"
constraintName$[6]  = "*WIDE-RANGE"
constraintName$[7]  = "*NARROW-RANGE"
constraintName$[8]  = "*NON-SCALE"
constraintName$[9]  = "CADENCE"
constraintName$[10] = "END-ON-TONIC"
constraintName$[11] = "*PEAK-EARLY"
constraintName$[12] = "*PEAK-LATE"
constraintName$[13] = "ARC-SHAPE"
constraintName$[14] = "*DIR-CHANGE"
constraintName$[15] = "*MONOTONIC"

# Constraint semantics (for reference):
#  1 *LEAP         interval > 5 semitones and != 6
#  2 *TRITONE      interval == 6
#  3 *NONSTEP      interval > 2 semitones
#  4 *REPEAT       interval == 0
#  5 *SEMITONE     interval == 1
#  6 *WIDE-RANGE   total range > 12 st
#  7 *NARROW-RANGE total range < 7 st
#  8 *NON-SCALE    note not in selected scale
#  9 CADENCE       final 2 notes form cadential approach to tonic
# 10 END-ON-TONIC  last note is the tonic
# 11 *PEAK-EARLY   highest note in first half
# 12 *PEAK-LATE    highest note in second half
# 13 ARC-SHAPE     contour is approximately single-peaked
# 14 *DIR-CHANGE   many direction changes
# 15 *MONOTONIC    nearly all motion in one direction

# Pretty short names for visualization
shortName$[1]  = "LEAP"
shortName$[2]  = "TRIT"
shortName$[3]  = "NSTEP"
shortName$[4]  = "REPEAT"
shortName$[5]  = "SEMI"
shortName$[6]  = "WIDE"
shortName$[7]  = "NARROW"
shortName$[8]  = "NSCL"
shortName$[9]  = "CAD"
shortName$[10] = "END"
shortName$[11] = "PKEAR"
shortName$[12] = "PKLAT"
shortName$[13] = "ARC"
shortName$[14] = "DIRCH"
shortName$[15] = "MONO"

# ============================================================
# Pitch extraction (shared helper, used by main + pair-corpus)
# Output globals:
#   pn_count           number of notes
#   pn_notes# [1..pn_count]  MIDI values
#   pn_times# [1..pn_count]  onset times (sec)
# ============================================================
procedure extractMelodyFromSound: .sid, .minPitch, .maxPitch, .timeStep, .voicing, .minDurMs
    selectObject: .sid
    .pid = To Pitch (ac): .timeStep, .minPitch, 15, "no", 0.03, .voicing, 0.01, 0.35, 0.14, .maxPitch
    selectObject: .pid
    .nFrames = Get number of frames

    # 1. Raw voiced-frame MIDI sequence. Keep the original frame
    # index so unvoiced gaps are not accidentally collapsed away.
    .rawMax = .nFrames + 8
    rawMidi# = zero#(.rawMax)
    rawTime# = zero#(.rawMax)
    rawFrame# = zero#(.rawMax)
    .rawCount = 0
    for .fr to .nFrames
        .f0 = Get value in frame: .fr, "Hertz"
        if .f0 <> undefined and .f0 > 0
            .midi = round(69 + 12 * ln(.f0 / 440) / ln(2))
            if quantize_to_scale
                @quantizePCtoScale: .midi
                .midi = quantizePCtoScale.out
            endif
            .rawCount += 1
            rawMidi#[.rawCount] = .midi
            rawTime#[.rawCount] = Get time from frame number: .fr
            rawFrame#[.rawCount] = .fr
        endif
    endfor
    removeObject: .pid

    # 2. Median filter (3 voiced samples) without filtering across
    # a real unvoiced gap. One missing pitch frame may be bridged;
    # longer gaps remain note boundaries.
    .medCount = .rawCount
    medMidi# = zero#(.rawMax)
    .maxGapFrames = 2
    for .i from 1 to .medCount
        .a = .i
        if .i > 1
            if rawFrame#[.i] - rawFrame#[.i - 1] <= .maxGapFrames
                .a = .i - 1
            endif
        endif
        .b = .i
        if .i < .medCount
            if rawFrame#[.i + 1] - rawFrame#[.i] <= .maxGapFrames
                .b = .i + 1
            endif
        endif

        .v1 = rawMidi#[.a]
        .v2 = rawMidi#[.i]
        .v3 = rawMidi#[.b]
        .hi = .v1
        if .v2 > .hi
            .hi = .v2
        endif
        if .v3 > .hi
            .hi = .v3
        endif
        .lo = .v1
        if .v2 < .lo
            .lo = .v2
        endif
        if .v3 < .lo
            .lo = .v3
        endif
        .med = .v1 + .v2 + .v3 - .hi - .lo
        medMidi#[.i] = .med
    endfor

    # 3. Run-length collapse with a minimum-duration gate. A long
    # unvoiced gap is a boundary even when pitch resumes on the same
    # MIDI note. The first run is NOT exempt from the duration gate.
    .noteCap = .rawMax
    pn_notes# = zero#(.noteCap)
    pn_times# = zero#(.noteCap)
    pn_ends# = zero#(.noteCap)
    pn_count = 0

    .minDurSec = .minDurMs / 1000.0
    .runStart = 1
    for .i from 2 to .medCount + 1
        .boundary = 0
        if .i > .medCount
            .boundary = 1
        elsif rawFrame#[.i] - rawFrame#[.i - 1] > .maxGapFrames
            .boundary = 1
        elsif medMidi#[.i] <> medMidi#[.runStart]
            .boundary = 1
        endif
        if .boundary = 1
            .runEnd = .i - 1
            .dur = rawTime#[.runEnd] - rawTime#[.runStart] + .timeStep
            if .dur >= .minDurSec
                pn_count += 1
                pn_notes#[pn_count] = medMidi#[.runStart]
                pn_times#[pn_count] = rawTime#[.runStart]
                pn_ends#[pn_count] = rawTime#[.runEnd] + .timeStep
            endif
            .runStart = .i
        endif
    endfor
endproc

# Quantize a MIDI number to the nearest in-scale MIDI.
procedure quantizePCtoScale: .midi
    # Quantize in absolute MIDI space, not pitch-class space. This
    # correctly handles octave boundaries (e.g. C -> B below, not B
    # almost an octave above). Exact ties are resolved downward.
    .pc = .midi mod 12
    .base = .midi - .pc
    .bestDist = 1e12
    .bestMidi = .midi
    for .j from 1 to numScalePCs
        .sp = scalePC#[.j]

        .cand = .base + .sp - 12
        .d = abs(.midi - .cand)
        if .d < .bestDist or (.d = .bestDist and .cand < .bestMidi)
            .bestDist = .d
            .bestMidi = .cand
        endif

        .cand = .base + .sp
        .d = abs(.midi - .cand)
        if .d < .bestDist or (.d = .bestDist and .cand < .bestMidi)
            .bestDist = .d
            .bestMidi = .cand
        endif

        .cand = .base + .sp + 12
        .d = abs(.midi - .cand)
        if .d < .bestDist or (.d = .bestDist and .cand < .bestMidi)
            .bestDist = .d
            .bestMidi = .cand
        endif
    endfor
    .out = .bestMidi
endproc

# ============================================================
# EVAL — compute the violation VECTOR for a melody.
# Input:  noteArr# (a vector of MIDI values), n (length)
# Output: v# — vector of length nConstraints with counts.
# For binary (threshold) constraints, the value is 0 or 1.
# For count constraints, it is the number of offending events.
# ============================================================
procedure evalMelody: .noteArr#, .n
    # Allocate result
    v# = zero#(nConstraints)

    # Guard: empty or singleton input leaves all zeros
    if .n >= 1

    # Interval counts
    .leapC = 0
    .tritC = 0
    .nstepC = 0
    .repC = 0
    .semiC = 0
    for .i from 2 to .n
        .iv = abs(.noteArr#[.i] - .noteArr#[.i - 1])
        if .iv = 0
            .repC += 1
        endif
        if .iv = 1
            .semiC += 1
        endif
        if .iv > 2
            .nstepC += 1
        endif
        if .iv = 6
            .tritC += 1
        endif
        # *LEAP excludes tritone (addresses double-counting concern).
        if .iv > 5 and .iv <> 6
            .leapC += 1
        endif
    endfor
    v#[1]  = .leapC
    v#[2]  = .tritC
    v#[3]  = .nstepC
    v#[4]  = .repC
    v#[5]  = .semiC

    # Range
    .minN = .noteArr#[1]
    .maxN = .noteArr#[1]
    for .i from 2 to .n
        if .noteArr#[.i] < .minN
            .minN = .noteArr#[.i]
        endif
        if .noteArr#[.i] > .maxN
            .maxN = .noteArr#[.i]
        endif
    endfor
    .rng = .maxN - .minN
    if .rng > 12
        v#[6] = 1
    endif
    if .rng < 7
        v#[7] = 1
    endif

    # Non-scale count
    .ns = 0
    for .i from 1 to .n
        .pc = .noteArr#[.i] mod 12
        .inSc = 0
        for .j from 1 to numScalePCs
            if .pc = scalePC#[.j]
                .inSc = 1
            endif
        endfor
        if .inSc = 0
            .ns += 1
        endif
    endfor
    v#[8] = .ns

    # Cadence and tonic-ending constraints apply only when the
    # selected scale actually defines a tonic. Chromatic mode leaves
    # both constraints neutral instead of silently treating C as tonic.
    if scaleHasTonic = 1
        if .n >= 2
            .last = .noteArr#[.n] mod 12
            .penult = .noteArr#[.n - 1] mod 12
            .lt = (tonicPC - 1 + 12) mod 12
            .sup = (tonicPC + 2) mod 12
            .dom = (tonicPC + 7) mod 12
            .hasCad = 0
            if .last = tonicPC
                if .penult = .lt or .penult = .sup or .penult = .dom
                    .hasCad = 1
                endif
            endif
            if .hasCad = 0
                v#[9] = 1
            endif
        else
            v#[9] = 1
        endif

        if (.noteArr#[.n] mod 12) <> tonicPC
            v#[10] = 1
        endif
    endif

    # Peak position
    .peakIdx = 1
    .peakVal = .noteArr#[1]
    for .i from 2 to .n
        if .noteArr#[.i] > .peakVal
            .peakVal = .noteArr#[.i]
            .peakIdx = .i
        endif
    endfor
    .mid = .n / 2
    if .peakIdx <= .mid
        v#[11] = 1
    else
        v#[12] = 1
    endif

    # Arc shape: 1 violation if NOT single-peaked within tolerance.
    # (This is the one "positive" constraint counted as a violation
    #  when the condition fails — ARC-SHAPE should hold; when it
    #  doesn't, that's a violation.)
    if .n >= 3
        .ascV = 0
        for .i from 2 to .peakIdx
            if .noteArr#[.i] < .noteArr#[.i - 1]
                .ascV += 1
            endif
        endfor
        .desV = 0
        for .i from .peakIdx + 1 to .n
            if .noteArr#[.i] > .noteArr#[.i - 1]
                .desV += 1
            endif
        endfor
        if (.ascV + .desV) > (.n / 4)
            v#[13] = 1
        endif
    endif

    # Direction changes
    if .n >= 3
        .ch = 0
        for .i from 3 to .n
            .pd = .noteArr#[.i - 1] - .noteArr#[.i - 2]
            .cd = .noteArr#[.i] - .noteArr#[.i - 1]
            if .pd > 0 and .cd < 0
                .ch += 1
            elsif .pd < 0 and .cd > 0
                .ch += 1
            endif
        endfor
        if .ch > .n / 3
            v#[14] = 1
        endif
    endif

    # Monotonic bias violation (too monotonic)
    if .n >= 2
        .asc = 0
        .desc = 0
        for .i from 2 to .n
            if .noteArr#[.i] > .noteArr#[.i - 1]
                .asc += 1
            elsif .noteArr#[.i] < .noteArr#[.i - 1]
                .desc += 1
            endif
        endfor
        .tot = .asc + .desc
        if .tot > 0
            .dom = .asc
            if .desc > .asc
                .dom = .desc
            endif
            if (.dom / .tot) > 0.85
                v#[15] = 1
            endif
        endif
    endif

    endif
endproc

# ============================================================
# Extract the target (winner) melody from the selected sound
# ============================================================
writeInfoLine: "=== OT Grammar Learning from Audio v1.1 ==="
appendInfoLine: "Source: ", soundName$
appendInfoLine: "Instrument: ", instrumentName$, "  |  Scale: ", scaleName$
if gEN_mode = 2 and quantize_to_scale
    appendInfoLine: "NOTE: scale quantization is ON in Pair-corpus mode; *NON-SCALE will be neutralized by preprocessing."
endif
appendInfoLine: ""
appendInfoLine: "[1/5] Extracting melody..."

@extractMelodyFromSound: soundID, minPitch, maxPitch, timeStep, voicingThreshold, min_note_duration_ms

if pn_count < 2
    exitScript: "Could not extract enough notes from the source. Check pitch-tracker settings or minimum note duration."
endif

# Copy winner-melody into persistent vectors.
winner# = zero#(pn_count)
winnerTimes# = zero#(pn_count)
winnerEnds# = zero#(pn_count)
for i from 1 to pn_count
    winner#[i] = pn_notes#[i]
    winnerTimes#[i] = pn_times#[i]
    winnerEnds#[i] = pn_ends#[i]
endfor
nWinner = pn_count

# Compute winner-melody MIDI range with an explicit loop (portable).
winnerMin = winner#[1]
winnerMax = winner#[1]
for i from 2 to nWinner
    if winner#[i] < winnerMin
        winnerMin = winner#[i]
    endif
    if winner#[i] > winnerMax
        winnerMax = winner#[i]
    endif
endfor

appendInfoLine: "  Notes extracted: ", nWinner,
    ... "  |  Range: MIDI ",
    ... fixed$(winnerMin, 0), "-", fixed$(winnerMax, 0)

# ============================================================
# GEN — produce the list of (winner, loser) pairs used for training.
# Winners and losers are melodies represented as vectors of MIDI values.
#
# After GEN we have:
#   nPairs                 number of pairs
#   pairWinV# [p, c]       winner violation count on constraint c
#   pairLoseV# [p, c]      loser violation count on constraint c
#
# We also keep ONE (winnerMelody, loserMelody) for tableau display.
# ============================================================
appendInfoLine: ""
appendInfoLine: "[2/5] Generating candidate pairs..."

# Neighbor-GEN now allocates enough room for every requested local
# perturbation. Pair-corpus retains a 2000-pair safety cap.
if gEN_mode = 1
    maxPairs = 2 * perturbation_max_semitones * nWinner
else
    maxPairs = 2000
endif
pairWinV# = zero#(maxPairs * nConstraints)
pairLoseV# = zero#(maxPairs * nConstraints)

nPairs = 0

if gEN_mode = 1
    # ---- Neighbor-GEN ----
    # Perturb one note at a time by +-1 .. +- perturbation_max_semitones.
    @evalMelody: winner#, nWinner
    winnerV# = zero#(nConstraints)
    for c from 1 to nConstraints
        winnerV#[c] = v#[c]
    endfor

    perturbed# = zero#(nWinner)
    for noteIdx from 1 to nWinner
        for delta from -perturbation_max_semitones to perturbation_max_semitones
            if delta <> 0 and nPairs < maxPairs
                # Copy winner, perturb one note
                for k from 1 to nWinner
                    perturbed#[k] = winner#[k]
                endfor
                perturbed#[noteIdx] = winner#[noteIdx] + delta

                @evalMelody: perturbed#, nWinner

                # Record the pair
                nPairs += 1
                for c from 1 to nConstraints
                    idxWin  = (nPairs - 1) * nConstraints + c
                    pairWinV#[idxWin] = winnerV#[c]
                    pairLoseV#[idxWin] = v#[c]
                endfor

            endif
        endfor
    endfor

    appendInfoLine: "  GEN mode: Neighbor"
    appendInfoLine: "  Pairs generated: ", nPairs

else
    # ---- Pair-corpus ----
    pairRoot$ = chooseDirectory$("Select folder containing good/ and bad/ subfolders")
    if pairRoot$ = ""
        exitScript: "Operation cancelled."
    endif
    goodDir$ = pairRoot$ + "/good"
    badDir$  = pairRoot$ + "/bad"

    # Collect good files
    goodList = Create Strings as file list: "goodList", goodDir$ + "/*.wav"
    nGood = Get number of strings
    goodV# = zero#(nGood * nConstraints)
    nGoodValid = 0

    for gi from 1 to nGood
        selectObject: goodList
        fn$ = Get string: gi
        gSound = Read from file: goodDir$ + "/" + fn$
        @extractMelodyFromSound: gSound, minPitch, maxPitch, timeStep, voicingThreshold, min_note_duration_ms
        removeObject: gSound
        if pn_count >= 2
            localNotes# = zero#(pn_count)
            for k from 1 to pn_count
                localNotes#[k] = pn_notes#[k]
            endfor
            @evalMelody: localNotes#, pn_count
            nGoodValid += 1
            for c from 1 to nConstraints
                idxG = (nGoodValid - 1) * nConstraints + c
                goodV#[idxG] = v#[c]
            endfor
        endif
    endfor
    removeObject: goodList

    badList = Create Strings as file list: "badList", badDir$ + "/*.wav"
    nBad = Get number of strings
    badV# = zero#(nBad * nConstraints)
    nBadValid = 0

    for bi from 1 to nBad
        selectObject: badList
        fn$ = Get string: bi
        bSound = Read from file: badDir$ + "/" + fn$
        @extractMelodyFromSound: bSound, minPitch, maxPitch, timeStep, voicingThreshold, min_note_duration_ms
        removeObject: bSound
        if pn_count >= 2
            localNotes# = zero#(pn_count)
            for k from 1 to pn_count
                localNotes#[k] = pn_notes#[k]
            endfor
            @evalMelody: localNotes#, pn_count
            nBadValid += 1
            for c from 1 to nConstraints
                idxB = (nBadValid - 1) * nConstraints + c
                badV#[idxB] = v#[c]
            endfor
        endif
    endfor
    removeObject: badList

    # Build good x bad pairs. If the Cartesian product exceeds the
    # safety cap, use an evenly spaced deterministic subsample instead
    # of taking the first 2000 lexicographic pairs (which would bias
    # training toward the earliest good files).
    totalCorpusPairs = nGoodValid * nBadValid
    pairsToUse = totalCorpusPairs
    if pairsToUse > maxPairs
        pairsToUse = maxPairs
    endif

    for q from 1 to pairsToUse
        if totalCorpusPairs <= maxPairs
            linearPair = q - 1
        else
            linearPair = floor((q - 0.5) * totalCorpusPairs / pairsToUse)
            if linearPair >= totalCorpusPairs
                linearPair = totalCorpusPairs - 1
            endif
        endif
        gi = floor(linearPair / nBadValid) + 1
        bi = (linearPair mod nBadValid) + 1

        nPairs += 1
        for c from 1 to nConstraints
            idxW = (nPairs - 1) * nConstraints + c
            idxG = (gi - 1) * nConstraints + c
            idxB = (bi - 1) * nConstraints + c
            pairWinV#[idxW]  = goodV#[idxG]
            pairLoseV#[idxW] = badV#[idxB]
        endfor
    endfor

    appendInfoLine: "  GEN mode: Pair-corpus"
    appendInfoLine: "  Good/Bad files: ", nGoodValid, "/", nBadValid
    appendInfoLine: "  Pairs generated: ", nPairs, " / ", totalCorpusPairs
    if totalCorpusPairs > maxPairs
        appendInfoLine: "  Pair-corpus cap active: deterministic even subsample of the full Cartesian product."
    endif
endif

if nPairs < 1
    exitScript: "No learning pairs could be generated."
endif

# Count how many pairs have a non-trivial violation difference
# (otherwise the learner has nothing to work with).
nInformative = 0
informativePair# = zero#(nPairs)
for p from 1 to nPairs
    diffFlag = 0
    for c from 1 to nConstraints
        idx = (p - 1) * nConstraints + c
        if pairWinV#[idx] <> pairLoseV#[idx]
            diffFlag = 1
        endif
    endfor
    if diffFlag = 1
        nInformative += 1
        informativePair#[nInformative] = p
    endif
endfor
appendInfoLine: "  Informative pairs: ", nInformative, " / ", nPairs

if nInformative < 1
    exitScript: "All generated winner/loser pairs have identical violation profiles; there is no learning signal for this constraint set."
endif

# ============================================================
# LEARN — run either GLA or RCD.
# Outputs:
#   finalRV# [1..nConstraints]  ranking value (GLA) or stratum (RCD)
#   history# [1..histLen]       error rate over epochs
#   histLen                     number of samples
# ============================================================
appendInfoLine: ""

# Initial ranking values (all equal for GLA; arbitrary for RCD since
# it rebuilds them deterministically).
rv# = zero#(nConstraints)
for c from 1 to nConstraints
    rv#[c] = gLA_initial_ranking_value
endfor

# Declared up-front so both branches and the summary panel can safely
# reference it even if the user flips between algorithms.
maxStratum = 0

# History buffer: we sample error rate every `hStep` iterations.
histLen = 0
histCap = 200
history# = zero#(histCap)
histStep = ceiling(gLA_iterations / histCap)
if histStep < 1
    histStep = 1
endif

if algorithm = 1
    # ─── GLA ───────────────────────────────────────────
    appendInfoLine: "[3/5] Running GLA..."
    appendInfoLine: "  iterations=", gLA_iterations,
        ... "  plasticity=", fixed$(gLA_plasticity, 3),
        ... "  noise=", fixed$(gLA_eval_noise, 2)

    for it from 1 to gLA_iterations
        # Sample only a pair that contains an actual learning signal.
        ip = randomInteger(1, nInformative)
        p = informativePair#[ip]

        # Add Gaussian noise to each ranking value to get
        # the evaluation-time ranking. (Praat's randomGauss.)
        evalRV# = zero#(nConstraints)
        for c from 1 to nConstraints
            evalRV#[c] = rv#[c] + randomGauss(0, gLA_eval_noise)
        endfor

        # Find the highest-ranked (largest evalRV) constraint on which
        # winner and loser DIFFER. Classical GLA: that constraint
        # decides the pair.
        bestC = 0
        bestRV = -1e12
        for c from 1 to nConstraints
            idx = (p - 1) * nConstraints + c
            if pairWinV#[idx] <> pairLoseV#[idx]
                if evalRV#[c] > bestRV
                    bestRV = evalRV#[c]
                    bestC = c
                endif
            endif
        endfor

        # If there IS a deciding constraint, check whether it rules
        # for the winner. If not, this is an error; update.
        if bestC > 0
            idx = (p - 1) * nConstraints + bestC
            # Fewer violations = preferred. So winner is preferred by
            # this constraint iff pairWinV < pairLoseV.
            winnerPreferred = pairWinV#[idx] < pairLoseV#[idx]
            if not winnerPreferred
                # Error. Promote constraints that prefer the winner,
                # demote constraints that prefer the loser.
                for c from 1 to nConstraints
                    idx2 = (p - 1) * nConstraints + c
                    if pairWinV#[idx2] < pairLoseV#[idx2]
                        rv#[c] += gLA_plasticity
                    elsif pairWinV#[idx2] > pairLoseV#[idx2]
                        rv#[c] -= gLA_plasticity
                    endif
                endfor
            endif
        endif

        # Sample error rate every histStep iterations
        if ((it mod histStep) = 0 or it = gLA_iterations) and histLen < histCap
            # Estimate stochastic error on informative pairs only.
            sampleSize = 50
            if sampleSize > nInformative
                sampleSize = nInformative
            endif
            errs = 0
            for s from 1 to sampleSize
                ipp = randomInteger(1, nInformative)
                pp = informativePair#[ipp]
                bC = 0
                bR = -1e12
                for c from 1 to nConstraints
                    idx3 = (pp - 1) * nConstraints + c
                    if pairWinV#[idx3] <> pairLoseV#[idx3]
                        nv = rv#[c] + randomGauss(0, gLA_eval_noise)
                        if nv > bR
                            bR = nv
                            bC = c
                        endif
                    endif
                endfor
                if bC > 0
                    idx3 = (pp - 1) * nConstraints + bC
                    if pairWinV#[idx3] >= pairLoseV#[idx3]
                        errs += 1
                    endif
                endif
            endfor
            histLen += 1
            history#[histLen] = errs / sampleSize
        endif
    endfor

    # Final ranking values
    finalRV# = zero#(nConstraints)
    for c from 1 to nConstraints
        finalRV#[c] = rv#[c]
    endfor

    appendInfoLine: "  GLA complete. Final stochastic error estimate (informative pairs): ",
        ... fixed$(history#[histLen], 3)

else
    # ─── RCD ───────────────────────────────────────────
    # Tesar & Smolensky (2000). Strict-domination OT.
    # Build strata greedily: repeatedly find constraints that prefer
    # some unresolved winner but are not preferred against by any
    # such winner; put them in the current stratum; mark resolved
    # pairs; repeat until all pairs are resolved or no constraint qualifies.
    appendInfoLine: "[3/5] Running RCD..."

    stratum# = zero#(nConstraints)
    for c from 1 to nConstraints
        stratum#[c] = 0
    endfor

    resolved# = zero#(nPairs)
    nResolved = 0
    currentStratum = 1
    maxStrata = nConstraints + 2
    stuck = 0

    while nResolved < nInformative and stuck = 0 and currentStratum <= maxStrata
        # Standard RCD placement: a still-unranked constraint can go
        # in the current stratum iff it does NOT prefer the loser in
        # any unresolved informative pair. It may be tied on all such
        # pairs; those constraints are genuinely undemoted at this stage.
        canPlace# = zero#(nConstraints)
        for c from 1 to nConstraints
            if stratum#[c] = 0
                prefersW = 0
                prefersL = 0
                for p from 1 to nPairs
                    if resolved#[p] = 0
                        idx = (p - 1) * nConstraints + c
                        if pairWinV#[idx] < pairLoseV#[idx]
                            prefersW = 1
                        elsif pairWinV#[idx] > pairLoseV#[idx]
                            prefersL = 1
                        endif
                    endif
                endfor
                if prefersL = 0
                    canPlace#[c] = 1
                endif
            endif
        endfor

        # Count placeable
        nPlaced = 0
        for c from 1 to nConstraints
            if canPlace#[c] = 1
                stratum#[c] = currentStratum
                nPlaced += 1
            endif
        endfor

        if nPlaced = 0
            stuck = 1
        else
            # Mark all pairs resolved that are decided by any newly
            # placed constraint (winner strictly preferred, loser not).
            for p from 1 to nPairs
                if resolved#[p] = 0
                    decided = 0
                    for c from 1 to nConstraints
                        if stratum#[c] = currentStratum
                            idx = (p - 1) * nConstraints + c
                            if pairWinV#[idx] < pairLoseV#[idx]
                                decided = 1
                            endif
                        endif
                    endfor
                    if decided = 1
                        resolved#[p] = 1
                        nResolved += 1
                    endif
                endif
            endfor
            currentStratum += 1
        endif
    endwhile

    # Any unplaced constraints get the bottom stratum (= currentStratum).
    for c from 1 to nConstraints
        if stratum#[c] = 0
            stratum#[c] = currentStratum
        endif
    endfor

    # Convert stratum to a ranking value (higher RV = higher-ranked).
    # Highest stratum number means lowest in the RCD sense; we invert.
    maxStratum = 0
    for c from 1 to nConstraints
        if stratum#[c] > maxStratum
            maxStratum = stratum#[c]
        endif
    endfor
    finalRV# = zero#(nConstraints)
    for c from 1 to nConstraints
        finalRV#[c] = (maxStratum - stratum#[c]) * 10.0
    endfor

    # Error rate of the learned stratified grammar on informative
    # pairs only. If a highest relevant stratum contains any
    # loser-preferring constraint, the winner is not guaranteed and
    # the pair counts as an error (important for inconsistent data).
    errs = 0
    for ip from 1 to nInformative
        p = informativePair#[ip]
        topRV = -1e12
        for c from 1 to nConstraints
            idx = (p - 1) * nConstraints + c
            if pairWinV#[idx] <> pairLoseV#[idx]
                if finalRV#[c] > topRV
                    topRV = finalRV#[c]
                endif
            endif
        endfor
        topHasLoserPreference = 0
        for c from 1 to nConstraints
            idx = (p - 1) * nConstraints + c
            if pairWinV#[idx] <> pairLoseV#[idx] and finalRV#[c] = topRV
                if pairWinV#[idx] > pairLoseV#[idx]
                    topHasLoserPreference = 1
                endif
            endif
        endfor
        if topHasLoserPreference = 1
            errs += 1
        endif
    endfor
    histLen = 1
    history#[1] = errs / nInformative

    appendInfoLine: "  RCD complete. Strata used: ", maxStratum
    appendInfoLine: "  Consistent with pairs: ", nResolved, " / ", nInformative
    if stuck = 1
        appendInfoLine: "  NOTE: RCD could not fully resolve all pairs. "
        appendInfoLine: "        Remaining constraints assigned to bottom stratum."
    endif
    appendInfoLine: "  Error rate on informative pairs: ", fixed$(history#[1], 3)
endif

# ============================================================
# Rank constraints by final ranking value (for display)
# ============================================================
appendInfoLine: ""
appendInfoLine: "[4/5] Final learned ranking"
appendInfoLine: "  (high ranking value = dominates; low = dominated)"
if algorithm = 2
    appendInfoLine: "  (RCD constraints with equal ranking values are tied in one stratum.)"
endif
appendInfoLine: ""

order# = zero#(nConstraints)
for c from 1 to nConstraints
    order#[c] = c
endfor
# Simple insertion sort on finalRV# (descending).
for i from 2 to nConstraints
    keyIdx = order#[i]
    keyVal = finalRV#[keyIdx]
    j = i - 1
    while j >= 1 and finalRV#[order#[j]] < keyVal
        order#[j + 1] = order#[j]
        j -= 1
    endwhile
    order#[j + 1] = keyIdx
endfor

appendInfoLine: "Rank  Constraint        RankingValue"
appendInfoLine: "-----------------------------------"
for r from 1 to nConstraints
    c = order#[r]
    appendInfoLine: fixed$(r, 0), "     ",
        ... constraintName$[c],
        ... "                    ",
        ... fixed$(finalRV#[c], 2)
endfor

# ============================================================
# Sample tableau: pick one pair, show winner vs loser violations
# ============================================================
appendInfoLine: ""
appendInfoLine: "Sample tableau (first informative pair):"
appendInfoLine: ""
appendInfoLine: "                      ",
    ... "winner  loser"

# Find the first informative pair
samplePair = 1
sampleFound = 0
for p from 1 to nPairs
    if sampleFound = 0
        diffFlag = 0
        for c from 1 to nConstraints
            idx = (p - 1) * nConstraints + c
            if pairWinV#[idx] <> pairLoseV#[idx]
                diffFlag = 1
            endif
        endfor
        if diffFlag = 1
            samplePair = p
            sampleFound = 1
        endif
    endif
endfor

# Print violations in ranked order
for r from 1 to nConstraints
    c = order#[r]
    idx = (samplePair - 1) * nConstraints + c
    wv = pairWinV#[idx]
    lv = pairLoseV#[idx]
    mark$ = "  "
    if wv <> lv
        if wv < lv
            mark$ = "W*"
        else
            mark$ = "L!"
        endif
    endif
    appendInfoLine: constraintName$[c],
        ... "               ",
        ... fixed$(wv, 0), "      ",
        ... fixed$(lv, 0), "   ", mark$
endfor
appendInfoLine: ""
appendInfoLine: "  (W* = winner has fewer violations here)"
appendInfoLine: "  (L! = loser has fewer violations — a learning signal)"

# ============================================================
# Visualization
# ============================================================
if show_visualization
    appendInfoLine: ""
    appendInfoLine: "[5/5] Drawing visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # ── Title ──
    Select outer viewport: 0, 8, 0, 0.50
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", 0.70, "half", "##OT Grammar Learning from Audio##"
    algName$ = "GLA"
    if algorithm = 2
        algName$ = "RCD"
    endif
    genName$ = "Neighbor-GEN"
    if gEN_mode = 2
        genName$ = "Pair-corpus"
    endif
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", -1.22, "half",
        ... soundName$
        ... + "   |   " + algName$
        ... + "   |   " + genName$
        ... + "   |   " + string$(nWinner) + " notes"
        ... + "   |   " + string$(nPairs) + " pairs"

    # ── Piano roll of extracted winner melody ──
    prTop = 0.55
    prBot = 1.85
    Select outer viewport: 0, 8, prTop, prBot
    Select inner viewport: 0.6, 7.7, prTop + 0.10, prBot - 0.05

    minN = winnerMin
    maxN = winnerMax
    if maxN = minN
        maxN = minN + 1
    endif
    selectObject: soundID
    totalDur = Get total duration
    Axes: 0, totalDur, minN - 2, maxN + 2

    # Scale-tone shading
    for n from minN - 1 to maxN + 1
        pc = n mod 12
        inSc = 0
        for j from 1 to numScalePCs
            if pc = scalePC#[j]
                inSc = 1
            endif
        endfor
        if inSc = 1
            Paint rectangle: "{0.88, 0.93, 0.88}", 0, totalDur, n - 0.4, n + 0.4
        else
            Paint rectangle: "{0.97, 0.94, 0.94}", 0, totalDur, n - 0.4, n + 0.4
        endif
    endfor

    # Notes
    Colour: "{0.20, 0.40, 0.75}"
    Line width: 2.0
    for i from 1 to nWinner
        t1 = winnerTimes#[i]
        t2 = winnerEnds#[i]
        if t2 > totalDur
            t2 = totalDur
        endif
        Draw line: t1, winner#[i], t2, winner#[i]
        if i < nWinner
            # Draw a vertical transition only when the next accepted
            # note is effectively contiguous; do not bridge silence.
            if winnerTimes#[i + 1] - t2 <= timeStep
                connectT = winnerTimes#[i + 1]
                Colour: "{0.60, 0.60, 0.60}"
                Line width: 0.6
                Draw line: connectT, winner#[i], connectT, winner#[i + 1]
                Colour: "{0.20, 0.40, 0.75}"
                Line width: 2.0
            endif
        endif
    endfor

    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "MIDI"
    Text bottom: "yes", "Time (s)"
    rollTitle$ = "Extracted winner melody (green bands = in-scale, pink = chromatic)"
    if gEN_mode = 2
        rollTitle$ = "Reference/template melody (pair-corpus training comes from folders)"
    endif
    Text top: "no", rollTitle$

    # ── Constraint ranking bar chart ──
    rkTop = 1.95
    rkBot = 4.55
    Select outer viewport: 0, 4.0, rkTop, rkBot
    Select inner viewport: 0.9, 3.8, rkTop + 0.10, rkBot - 0.10

    maxRV = finalRV#[order#[1]]
    minRV = finalRV#[order#[nConstraints]]
    rvRange = maxRV - minRV
    if rvRange < 1
        rvRange = 1
    endif

    Axes: 0, 1, 0, nConstraints
    Paint rectangle: "{0.97, 0.97, 0.99}", 0, 1, 0, nConstraints

    for r from 1 to nConstraints
        c = order#[r]
        yTop = nConstraints - (r - 1)
        yBot = nConstraints - r
        # Normalise RV to [0,1] for bar width
        w01 = (finalRV#[c] - minRV) / rvRange
        # Colour: high rank = deep blue, low rank = pale
        blue = 0.30 + 0.55 * w01
        grn  = 0.40 + 0.35 * (1 - w01)
        red  = 0.35 + 0.50 * (1 - w01)
        Paint rectangle: "{" + fixed$(red, 2) + "," + fixed$(grn, 2) + "," + fixed$(blue, 2) + "}",
            ... 0.25, 0.25 + 0.70 * w01, yBot + 0.15, yTop - 0.15
        Colour: "Black"
        Font size: 6
        Text: 0.01, "left", (yTop + yBot) / 2, "half",
            ... "##" + fixed$(r, 0) + ".##  " + shortName$[c]
        Colour: "{0.30, 0.30, 0.30}"
        Text: 0.98, "right", (yTop + yBot) / 2, "half",
            ... fixed$(finalRV#[c], 1)
    endfor
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Learned ranking (top = dominant)"

    # ── Learning curve ──
    lcTop = 1.95
    lcBot = 4.55
    Select outer viewport: 4.0, 8.0, lcTop, lcBot
    Select inner viewport: 4.3, 7.7, lcTop + 0.20, lcBot - 0.20

    if algorithm = 1 and histLen > 1
        maxErr = 0.01
        for h from 1 to histLen
            if history#[h] > maxErr
                maxErr = history#[h]
            endif
        endfor
        Axes: 0, histLen, 0, maxErr
        Paint rectangle: "{0.97, 0.97, 0.99}", 0, histLen, 0, maxErr
        Colour: "{0.80, 0.30, 0.25}"
        Line width: 1.8
        for h from 2 to histLen
            Draw line: h - 1, history#[h - 1], h, history#[h]
        endfor
        Colour: "Black"
        Line width: 1
        Draw inner box
        Font size: 7
        Text left: "yes", "Error rate"
        Text bottom: "yes", "Sample point (about every " + string$(histStep) + " iterations)"
        Text top: "no", "GLA learning curve"
    else
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.97, 0.97, 0.99}", 0, 1, 0, 1
        Font size: 10
        Colour: "{0.50, 0.50, 0.50}"
        Text: 0.5, "centre", 0.55, "half", "RCD is deterministic"
        Font size: 8
        Text: 0.5, "centre", 0.40, "half",
            ... "Error rate on training pairs: " + fixed$(history#[1], 3)
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text top: "no", "Learning result"
    endif

    # ── Tableau of sample pair ──
    tbTop = 4.65
    tbBot = 6.55
    Select outer viewport: 0, 8, tbTop, tbBot
    Select inner viewport: 0.6, 7.7, tbTop + 0.10, tbBot - 0.10
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1

    Font size: 8
    Colour: "Black"
    Text: 0.02, "left", 0.92, "half", "##Sample tableau (first informative pair)##"

    # Column header
    xRank = 0.03
    xName = 0.08
    xW    = 0.48
    xL    = 0.58
    xMark = 0.68

    Font size: 7
    Colour: "{0.30, 0.30, 0.30}"
    Text: xRank, "left", 0.82, "half", "rank"
    Text: xName, "left", 0.82, "half", "constraint"
    Text: xW,    "left", 0.82, "half", "winner"
    Text: xL,    "left", 0.82, "half", "loser"
    Text: xMark, "left", 0.82, "half", "prefers"

    # Rows — top-ranked N constraints
    rowsShown = 8
    if rowsShown > nConstraints
        rowsShown = nConstraints
    endif
    yTopRow = 0.75
    yRowH = 0.075

    Font size: 6
    for r from 1 to rowsShown
        c = order#[r]
        idx = (samplePair - 1) * nConstraints + c
        wv = pairWinV#[idx]
        lv = pairLoseV#[idx]
        yRow = yTopRow - (r - 1) * yRowH

        Colour: "Black"
        Text: xRank, "left", yRow, "half", fixed$(r, 0)
        Text: xName, "left", yRow, "half", constraintName$[c]
        Text: xW, "left", yRow, "half", fixed$(wv, 0)
        Text: xL, "left", yRow, "half", fixed$(lv, 0)
        if wv = lv
            Colour: "{0.60, 0.60, 0.60}"
            Text: xMark, "left", yRow, "half", "—"
        elsif wv < lv
            Colour: "{0.15, 0.55, 0.25}"
            Text: xMark, "left", yRow, "half", "W"
        else
            Colour: "{0.75, 0.20, 0.15}"
            Text: xMark, "left", yRow, "half", "L"
        endif
    endfor
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # ── Summary panel ──
    smTop = 6.65
    smBot = 7.75
    Select outer viewport: 0, 8, smTop, smBot
    Select inner viewport: 0.6, 7.7, smTop + 0.05, smBot - 0.05
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.88, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.02, "left", 0.66, "half",
        ... "Algorithm: " + algName$
        ... + "   |   GEN: " + genName$
        ... + "   |   Scale: " + scaleName$
        ... + "   |   Instrument: " + instrumentName$
    Text: 0.02, "left", 0.44, "half",
        ... "Notes: " + string$(nWinner)
        ... + "   |   Pairs: " + string$(nPairs)
        ... + "   |   Informative: " + string$(nInformative)
        ... + "   |   Final error rate: " + fixed$(history#[histLen], 3)
    if algorithm = 1
        Text: 0.02, "left", 0.22, "half",
            ... "Iters: " + string$(gLA_iterations)
            ... + "   |   Plasticity: " + fixed$(gLA_plasticity, 2)
            ... + "   |   Eval noise: " + fixed$(gLA_eval_noise, 2)
            ... + "   |   Min note dur: " + string$(min_note_duration_ms) + " ms"
    else
        Text: 0.02, "left", 0.22, "half",
            ... "Strata: " + string$(maxStratum)
            ... + "   |   Min note dur: " + string$(min_note_duration_ms) + " ms"
    endif
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# ============================================================
# Output Table
# ============================================================
if create_output_table
    tbl = Create Table with column names: "OT_Ranking_" + soundName$,
        ... nConstraints, "rank constraint ranking_value"
    for r from 1 to nConstraints
        c = order#[r]
        selectObject: tbl
        Set numeric value: r, "rank", r
        Set string value:  r, "constraint", constraintName$[c]
        Set numeric value: r, "ranking_value", finalRV#[c]
    endfor
    appendInfoLine: ""
    appendInfoLine: "Created Table: OT_Ranking_", soundName$
endif

selectObject: soundID

appendInfoLine: ""
appendInfoLine: "=== DONE ==="
