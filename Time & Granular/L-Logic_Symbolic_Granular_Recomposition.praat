# ============================================================
# Praat AudioTools - L-Logic Symbolic Granular Recomposition.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 4.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Llogic System — Praat implementation of the analytical and
#   compositional framework from "Logic of Sound and Silence"
#   by Rakhat-Bi Abdyssagin.
#
#   Classifies audio into the six Lsets (global sets):
#     Ø  (null)  — silence/pauses [with duration: Ø(S), Ø(M), Ø(L)]
#     ψ  (psi)   — airy set: breath, half-tone/half-noise, air noise
#     θ  (theta) — ordinary sound: tonal, pitched, harmonic
#     χ  (chi)   — percussive set: staccato, slap tongue, onsets
#     ϕ  (phi)   — vibrational set: vibrato, tremolo, bisbigliando
#     ω  (omega) — multiphonics: complex spectral, no single pitch
#
#   Acoustic classification logic:
#     Ø:  intensity < int_null
#     χ:  intensity rise >= int_chi (between consecutive frames)
#     θ:  HNR > hnr_theta AND F0 present
#     ϕ:  hnr_psi <= HNR <= hnr_theta AND F0 present
#     ω:  HNR >= hnr_psi AND F0 absent (structured but non-pitched)
#     ψ:  HNR < hnr_psi (noisy, breathy)
#
#   Outputs:
#     - Classified TextGrid with Llogic labels
#     - Resynthesized Sound from user-defined proposition
#     - Lsets string representations (per Chapter 8):
#         Lsets:          global sets without pauses
#         Lsets ∧ Ø:      with pauses and phrases in brackets
#         Lsets ∧ Ø(dur): with proportional silence durations
#     - 5-panel visualization of timbral-textural layers
#     - Category dominance analysis
#
# Changelog v4.1 (from v4.0):
#   - Fixed phi gap-bridging: now re-merges adjacent identical
#     labels after absorbing interruptions (was leaving duplicate
#     ϕ segments → one sustained region per Chapter 8 intent)
#   - Implemented the Classified TextGrid output (was documented
#     but never built) — one labelled interval per merged segment
#   - Guarded ranked-candidate selection against labels with more
#     than maxRank candidates (prevented unset-index error in
#     Random/Rotate modes; now uses top-maxRank longest)
#   - Removed dead dominance dedup checks; corrected section
#     numbering and "atoms placed" reporting
#
# Changelog v4.0 (from v3):
#   - Added ϕ (phi) vibrational set classification
#   - Added ω (omega) multiphonics classification
#   - Fixed chi detection (lookback now uses full frame step)
#   - Fixed tail coverage gap (last segment extends to duration)
#   - Added silence duration classification: Ø(S), Ø(M), Ø(L)
#   - Removed dead branch in classifier
#   - Built Lsets string representations per Chapter 8 notation
#   - Added 6-panel visualization with color-coded regions
#   - Added min_pitch parameter for low instruments
#   - Clamped win_step <= win_len to prevent gaps
#   - Updated presets to use all 6 Lsets categories
#   - Removed phantom "trans" counter
#
# Citation:
#   Abdyssagin, R.-B. (2024). Logic of Sound and Silence.
#   Cohen, S. (2025). Praat AudioTools.
#
# Category: Analysis & Feature Extraction
# ============================================================

# ── 0. INPUT VALIDATION ─────────────────────────────────────
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif
originalSound = selected("Sound")
soundName$ = selected$("Sound")

# ── 1. FORM ─────────────────────────────────────────────────
form Llogic Symbolic Granular Recomposition v4.1
    optionmenu Preset: 1
        option Custom
        option Breath to Tone
        option Tonal Phrase
        option Dissolution
        option Silence Arc
        option Dense Texture
        option Void Meditation
        option Full Llogic Arc
    sentence Proposition psi, phi, theta
    positive Win_len 0.030
    positive Win_step 0.030
    positive Min_pitch 100
    positive Hnr_psi 5.0
    positive Hnr_theta 18.0
    positive Int_null 25.0
    positive Int_chi 8.0
    positive Crossfade 0.030
    positive Cycles 3
    optionmenu Selection_mode: 2
        option Longest only
        option Rotate through candidates
        option Random each cycle
    optionmenu Arrangement: 1
        option Linear (proposition order)
        option Retrograde (reverse each cycle)
        option Palindrome (forward then back)
        option Accumulation (1, 12, 123...)
        option Stutter (each atom x3 before next)
        option Scatter (random permutation each cycle)
    optionmenu Gap_mode: 1
        option None
        option Fixed silence
        option Growing silence
        option Shrinking silence
        option Random silence
    positive Gap_base 0.300
    boolean Shape_atoms 1
    positive Fade_in 0.020
    positive Fade_out 0.040
    boolean Draw_visualization 1
endform

# ── 2. PRESETS ──────────────────────────────────────────────
# Custom (preset=1): use proposition$ from form as-is
if preset = 2
    proposition$ = "psi, phi, theta"
elsif preset = 3
    proposition$ = "theta, phi, theta"
elsif preset = 4
    proposition$ = "theta, phi, psi, null"
elsif preset = 5
    proposition$ = "null, psi, theta, psi, null"
elsif preset = 6
    proposition$ = "chi, theta, phi, theta, chi"
elsif preset = 7
    proposition$ = "null, omega, null"
elsif preset = 8
    proposition$ = "null, psi, phi, theta, chi, omega, phi, psi, null"
endif

# ── 3. CLAMP & DERIVE ──────────────────────────────────────
# Prevent gaps: step must not exceed window length
if win_step > win_len
    win_step = win_len
endif
if win_len < 0.010
    win_len = 0.010
endif
if win_step < 0.005
    win_step = 0.005
endif
if min_pitch < 30
    min_pitch = 30
endif
if min_pitch > 300
    min_pitch = 300
endif

# Silence duration thresholds (absolute, in seconds)
silShort = 0.15
silMed = 0.40

# ── 4. ANALYSIS OBJECTS ────────────────────────────────────
selectObject: originalSound
duration = Get total duration
sr = Get sampling frequency

selectObject: originalSound
intObj = To Intensity: min_pitch, win_step, "yes"

selectObject: originalSound
hnrObj = To Harmonicity (cc): win_step, min_pitch, 0.1, 1.0

selectObject: originalSound
pitchObj = To Pitch (ac): 0, min_pitch, 15, "no", 0.03, 0.45,
    ... 0.01, 0.35, 0.14, 600

# ── 5. CLASSIFY WINDOWS ────────────────────────────────────
maxSegs = 10000
for i from 1 to maxSegs
    segStart[i] = 0
    segEnd[i] = 0
    segLabel$[i] = ""
endfor
nSegs = 0

t = win_len / 2
while t <= duration - win_len / 2 + 0.0001
    tStart = t - win_len / 2
    tEnd = t + win_len / 2
    if tEnd > duration
        tEnd = duration
    endif

    # Intensity
    selectObject: intObj
    intVal = Get value at time: t, "Nearest"
    if intVal = undefined
        intVal = 0
    endif

    # HNR
    selectObject: hnrObj
    hnrVal = Get value at time: t, "Nearest"
    if hnrVal = undefined
        hnrVal = -200
    endif

    # F0
    selectObject: pitchObj
    f0Val = Get value at time: t, "Hertz", "Linear"
    hasF0 = 0
    if f0Val <> undefined
        hasF0 = 1
    endif

    # Intensity rise: compare to PREVIOUS FRAME (full step back)
    selectObject: intObj
    intPrev = Get value at time: t - win_step, "Nearest"
    if intPrev = undefined
        intPrev = intVal
    endif
    intRise = intVal - intPrev

    # ── CLASSIFY (6 Lsets categories) ──
    # Ø (null):  silence — low intensity
    # χ (chi):   percussive — sharp intensity onset
    # θ (theta): ordinary — high HNR + clear pitch
    # ϕ (phi):   vibrational — moderate HNR + pitch present
    # ω (omega): multiphonic — moderate+ HNR, no single pitch
    # ψ (psi):   airy — low HNR (noisy/breathy)

    if intVal < int_null
        label$ = "null"
    elsif intRise >= int_chi
        label$ = "chi"
    elsif hasF0 = 1 and hnrVal > hnr_theta
        label$ = "theta"
    elsif hasF0 = 1 and hnrVal >= hnr_psi
        label$ = "phi"
    elsif hasF0 = 0 and hnrVal >= hnr_psi
        label$ = "omega"
    else
        label$ = "psi"
    endif

    nSegs += 1
    if nSegs > maxSegs
        nSegs = maxSegs
    endif
    segStart[nSegs] = tStart
    segEnd[nSegs] = tEnd
    segLabel$[nSegs] = label$

    t += win_step
endwhile

# ── 6. MERGE ADJACENT IDENTICAL LABELS ─────────────────────
maxMerged = 10000
for i from 1 to maxMerged
    mStart[i] = 0
    mEnd[i] = 0
    mLabel$[i] = ""
endfor
nMerged = 0

if nSegs > 0
    nMerged = 1
    mStart[1] = segStart[1]
    mEnd[1] = segEnd[1]
    mLabel$[1] = segLabel$[1]

    for i from 2 to nSegs
        if segLabel$[i] = mLabel$[nMerged]
            mEnd[nMerged] = segEnd[i]
        else
            nMerged += 1
            mStart[nMerged] = segStart[i]
            mEnd[nMerged] = segEnd[i]
            mLabel$[nMerged] = segLabel$[i]
        endif
    endfor

    # Extend last segment to full duration (coverage gap fix)
    if mEnd[nMerged] < duration
        mEnd[nMerged] = duration
    endif
endif

# ── 6b. PHI GAP-BRIDGING ────────────────────────────────────
# Merge phi segments separated by short psi/theta interruptions
# into one sustained phi region. phiBridge = max interrupting
# segment duration to absorb (NOT gap between boundaries, which
# is always 0 after contiguous merge).
phiBridge = 0.150
nBridged = 0
for i from 1 to maxMerged
    bStart[i] = 0
    bEnd[i] = 0
    bLabel$[i] = ""
endfor

if nMerged > 0
    nBridged = 1
    bStart[1] = mStart[1]
    bEnd[1] = mEnd[1]
    bLabel$[1] = mLabel$[1]

    for i from 2 to nMerged
        prevLbl$ = bLabel$[nBridged]
        currLbl$ = mLabel$[i]
        interruptDur = mEnd[i] - mStart[i]
        if prevLbl$ = "phi" and (currLbl$ = "psi" or currLbl$ = "theta") and interruptDur <= phiBridge and i < nMerged
            nextLbl$ = mLabel$[i + 1]
            if nextLbl$ = "phi"
                bEnd[nBridged] = mEnd[i]
            else
                nBridged += 1
                bStart[nBridged] = mStart[i]
                bEnd[nBridged] = mEnd[i]
                bLabel$[nBridged] = currLbl$
            endif
        else
            nBridged += 1
            bStart[nBridged] = mStart[i]
            bEnd[nBridged] = mEnd[i]
            bLabel$[nBridged] = currLbl$
        endif
    endfor
endif

# Collapse adjacent identical labels produced by bridging
# (absorbing an interruption leaves the following same-label
# segment adjacent; a second merge pass fuses them into one).
nMerged = 0
if nBridged > 0
    nMerged = 1
    mStart[1] = bStart[1]
    mEnd[1] = bEnd[1]
    mLabel$[1] = bLabel$[1]
    for i from 2 to nBridged
        if bLabel$[i] = mLabel$[nMerged]
            mEnd[nMerged] = bEnd[i]
        else
            nMerged += 1
            mStart[nMerged] = bStart[i]
            mEnd[nMerged] = bEnd[i]
            mLabel$[nMerged] = bLabel$[i]
        endif
    endfor
endif

# ── 7. SILENCE DURATION CLASSIFICATION ─────────────────────
# Tag null segments as Ø(S), Ø(M), or Ø(L)
for i from 1 to nMerged
    mSilDur$[i] = ""
    if mLabel$[i] = "null"
        sDur = mEnd[i] - mStart[i]
        if sDur < silShort
            mSilDur$[i] = "S"
        elsif sDur < silMed
            mSilDur$[i] = "M"
        else
            mSilDur$[i] = "L"
        endif
    endif
endfor

# ── 8. CLASSIFIED TEXTGRID ─────────────────────────────────
# One labelled interval per merged segment (Llogic glyphs).
# Boundaries are placed at each segment START (strictly
# increasing), so the tier tiles [0, duration] gaplessly even
# if window overlap made segEnd values overlap.
selectObject: originalSound
classGrid = To TextGrid: "Llogic", ""
prevBt = 0
for i from 2 to nMerged
    bt = mStart[i]
    if bt > prevBt + 1e-9 and bt < duration - 1e-9
        selectObject: classGrid
        Insert boundary: 1, bt
        prevBt = bt
    endif
endfor
for i from 1 to nMerged
    lab$ = mLabel$[i]
    if lab$ = "null"
        gk$ = "Ø(" + mSilDur$[i] + ")"
    elsif lab$ = "psi"
        gk$ = "ψ"
    elsif lab$ = "theta"
        gk$ = "θ"
    elsif lab$ = "chi"
        gk$ = "χ"
    elsif lab$ = "phi"
        gk$ = "ϕ"
    elsif lab$ = "omega"
        gk$ = "ω"
    else
        gk$ = lab$
    endif
    # Probe just inside the interval's start edge (robust to overlap)
    probeT = mStart[i] + 1e-6
    if probeT >= duration
        probeT = duration - 1e-6
    endif
    selectObject: classGrid
    iv = Get interval at time: 1, probeT
    Set interval text: 1, iv, gk$
endfor
selectObject: classGrid
Rename: soundName$ + "_Llogic_grid"

# ── 9. BUILD CANDIDATE POOL (direct from merged segments) ───
maxCand = 5000
for i from 1 to maxCand
    candLabel$[i] = ""
    candStart[i] = 0
    candEnd[i] = 0
endfor
nCand = 0

for i from 1 to nMerged
    lbl$ = mLabel$[i]
    iStart = mStart[i]
    iEnd = mEnd[i]
    iDur = iEnd - iStart
    # Per-label minimum duration:
    # chi and omega are naturally short — use step size as floor.
    # psi, phi, theta need to be substantial.
    if lbl$ = "chi" or lbl$ = "omega"
        minDur = win_step
    elsif lbl$ = "null"
        minDur = 0.050
    else
        minDur = 0.100
    endif
    if iDur >= minDur and lbl$ <> ""
        nCand += 1
        candLabel$[nCand] = lbl$
        candStart[nCand] = iStart
        candEnd[nCand] = iEnd
    endif
endfor

# ── 10. BUILD LSETS REPRESENTATIONS ────────────────────────
# Map labels to Lsets Greek symbols for display
# (Praat Info window supports UTF-8)

lsetsNoP$ = ""
lsetsWithP$ = ""
lsetsDur$ = ""
inPhrase = 0

for i from 1 to nMerged
    lab$ = mLabel$[i]
    # Map to Greek
    if lab$ = "null"
        gk$ = "Ø"
    elsif lab$ = "psi"
        gk$ = "ψ"
    elsif lab$ = "theta"
        gk$ = "θ"
    elsif lab$ = "chi"
        gk$ = "χ"
    elsif lab$ = "phi"
        gk$ = "ϕ"
    elsif lab$ = "omega"
        gk$ = "ω"
    else
        gk$ = lab$
    endif

    if lab$ <> "null"
        # Lsets (no pauses): just accumulate
        if lsetsNoP$ = ""
            lsetsNoP$ = gk$
        else
            lsetsNoP$ = lsetsNoP$ + " " + gk$
        endif

        # Lsets with pauses: open phrase if needed
        if inPhrase = 0
            lsetsWithP$ = lsetsWithP$ + "("
            lsetsDur$ = lsetsDur$ + "("
            inPhrase = 1
            lsetsWithP$ = lsetsWithP$ + gk$
            lsetsDur$ = lsetsDur$ + gk$
        else
            lsetsWithP$ = lsetsWithP$ + " " + gk$
            lsetsDur$ = lsetsDur$ + " " + gk$
        endif
    else
        # Close phrase if open
        if inPhrase = 1
            lsetsWithP$ = lsetsWithP$ + ")"
            lsetsDur$ = lsetsDur$ + ")"
            inPhrase = 0
        endif
        # Add silence marker
        lsetsWithP$ = lsetsWithP$ + " Ø "
        lsetsDur$ = lsetsDur$ + " Ø(" + mSilDur$[i] + ") "
    endif
endfor

# Close final phrase if still open
if inPhrase = 1
    lsetsWithP$ = lsetsWithP$ + ")"
    lsetsDur$ = lsetsDur$ + ")"
endif

# ── 11. PARSE PROPOSITION ──────────────────────────────────
nSymbols = 0
maxSym = 50
for i from 1 to maxSym
    symbol$[i] = ""
endfor

remain$ = proposition$
while index(remain$, ",") > 0
    pos = index(remain$, ",")
    tok$ = left$(remain$, pos - 1)
    while left$(tok$, 1) = " "
        tok$ = right$(tok$, length(tok$) - 1)
    endwhile
    while right$(tok$, 1) = " "
        tok$ = left$(tok$, length(tok$) - 1)
    endwhile
    if length(tok$) > 0
        nSymbols += 1
        symbol$[nSymbols] = tok$
    endif
    remain$ = right$(remain$, length(remain$) - pos)
endwhile
# Last token
tok$ = remain$
while length(tok$) > 0 and left$(tok$, 1) = " "
    tok$ = right$(tok$, length(tok$) - 1)
endwhile
while length(tok$) > 0 and right$(tok$, 1) = " "
    tok$ = left$(tok$, length(tok$) - 1)
endwhile
if length(tok$) > 0
    nSymbols += 1
    symbol$[nSymbols] = tok$
endif

if nSymbols = 0
    exitScript: "No valid symbols in proposition."
endif

# ── 12. BUILD RANKED CANDIDATE LISTS PER LABEL ─────────────
# For each label, collect all candidates sorted longest-first.
# rankCand[label][rank] = index into candLabel$/candStart/candEnd

maxAtoms = 50
maxRank = 50
for s from 1 to nSymbols
    req$ = symbol$[s]
    # Gather all matching candidates
    nMatch = 0
    for c from 1 to nCand
        if candLabel$[c] = req$
            nMatch += 1
            matchIdx[nMatch] = c
        endif
    endfor
    rankCount[s] = nMatch

    # Sort by duration descending (simple insertion sort)
    for a from 1 to nMatch
        for b from a + 1 to nMatch
            durA = candEnd[matchIdx[a]] - candStart[matchIdx[a]]
            durB = candEnd[matchIdx[b]] - candStart[matchIdx[b]]
            if durB > durA
                tmp = matchIdx[a]
                matchIdx[a] = matchIdx[b]
                matchIdx[b] = tmp
            endif
        endfor
    endfor

    # Store ranked indices (up to maxRank) — linearized as rankIdx[s*100 + r]
    for r from 1 to min(nMatch, maxRank)
        rankIdx[s * 100 + r] = matchIdx[r]
    endfor

    if nMatch = 0
        appendInfoLine: "WARNING: No candidate for '", req$, "'"
    endif
endfor

# ── 13. EXTRACT ATOMS (one per symbol per cycle, mono) ──────
maxTotalAtoms = maxAtoms * 20
for i from 1 to maxTotalAtoms
    cycleAtomId[i] = 0
endfor
nTotalAtoms = 0

# Store one extracted Sound per symbol per cycle in atomBank[cyc, s]
# Linearized: atomBank[cyc * 100 + s]
for cyc from 1 to cycles
    for s from 1 to nSymbols
        req$ = symbol$[s]
        nRanked = rankCount[s]
        # Cap to the ranks actually stored (top maxRank longest);
        # otherwise Random/Rotate could index an unset rankIdx.
        if nRanked > maxRank
            nRanked = maxRank
        endif
        if nRanked > 0
            if selection_mode = 1
                chosenRank = 1
            elsif selection_mode = 2
                chosenRank = ((cyc - 1) mod nRanked) + 1
            else
                chosenRank = randomInteger(1, nRanked)
            endif
            cIdx = rankIdx[s * 100 + chosenRank]

            selectObject: originalSound
            atomSnd = Extract part: candStart[cIdx], candEnd[cIdx],
                ... "rectangular", 1, "no"
            selectObject: atomSnd
            nch = Get number of channels
            if nch > 1
                atomMono = Convert to mono
                removeObject: atomSnd
                atomSnd = atomMono
            endif
            Rename: req$ + "_c" + string$(cyc) + "_r" + string$(chosenRank)
            atomBank[cyc * 100 + s] = atomSnd
        else
            atomBank[cyc * 100 + s] = 0
        endif
    endfor
endfor

# ── 14. ARRANGE ATOMS ───────────────────────────────────────
# Build the playback sequence according to the arrangement mode.
# seq[] holds (cyc, s) pairs that define the final order.
maxSeq = 5000
nSeq = 0
for i from 1 to maxSeq
    seqCyc[i] = 0
    seqSym[i] = 0
endfor

for cyc from 1 to cycles

    # Build base order for this cycle (1..nSymbols)
    for s from 1 to nSymbols
        baseOrder[s] = s
    endfor

    if arrangement = 1
        # Linear: 1 2 3 ... nSymbols
        for s from 1 to nSymbols
            nSeq += 1
            seqCyc[nSeq] = cyc
            seqSym[nSeq] = baseOrder[s]
        endfor

    elsif arrangement = 2
        # Retrograde: nSymbols ... 2 1
        s = nSymbols
        while s >= 1
            nSeq += 1
            seqCyc[nSeq] = cyc
            seqSym[nSeq] = baseOrder[s]
            s -= 1
        endwhile

    elsif arrangement = 3
        # Palindrome: forward then back (skip repeated middle)
        for s from 1 to nSymbols
            nSeq += 1
            seqCyc[nSeq] = cyc
            seqSym[nSeq] = baseOrder[s]
        endfor
        nSymbolsMinus1 = nSymbols - 1
        s = nSymbolsMinus1
        while s >= 1
            nSeq += 1
            seqCyc[nSeq] = cyc
            seqSym[nSeq] = baseOrder[s]
            s -= 1
        endwhile

    elsif arrangement = 4
        # Accumulation: [1], [1,2], [1,2,3] ...
        for acc from 1 to nSymbols
            for s from 1 to acc
                nSeq += 1
                seqCyc[nSeq] = cyc
                seqSym[nSeq] = baseOrder[s]
            endfor
        endfor

    elsif arrangement = 5
        # Stutter: each atom repeated 3 times before moving on
        for s from 1 to nSymbols
            for rep from 1 to 3
                nSeq += 1
                seqCyc[nSeq] = cyc
                seqSym[nSeq] = baseOrder[s]
            endfor
        endfor

    elsif arrangement = 6
        # Scatter: random permutation of symbols each cycle
        # Fisher-Yates shuffle of baseOrder
        s = nSymbols
        while s >= 2
            r = randomInteger(1, s)
            tmp = baseOrder[s]
            baseOrder[s] = baseOrder[r]
            baseOrder[r] = tmp
            s -= 1
        endwhile
        for s from 1 to nSymbols
            nSeq += 1
            seqCyc[nSeq] = cyc
            seqSym[nSeq] = baseOrder[s]
        endfor
    endif

endfor

# ── 15. ASSEMBLE WITH GAPS & ENVELOPES ─────────────────────
if nSeq = 0
    removeObject: pitchObj, hnrObj, intObj
    exitScript: "No sequence built."
endif

# Collect sequence positions, skip missing symbols
nTotalAtoms = 0
for i from 1 to nSeq
    aId = atomBank[seqCyc[i] * 100 + seqSym[i]]
    if aId > 0
        nTotalAtoms += 1
        cycleAtomId[nTotalAtoms] = aId
        cycleSymId[nTotalAtoms] = seqSym[i]
    endif
endfor

if nTotalAtoms = 0
    removeObject: pitchObj, hnrObj, intObj
    exitScript: "No atoms to concatenate."
endif

# Get sample rate from first atom
selectObject: cycleAtomId[1]
sr = Get sampling frequency

# Build final sequence: for each position make a fresh copy so
# repeated references (Stutter, Palindrome etc.) are distinct objects
maxAssemble = nTotalAtoms * 2 + 1
nAssemble = 0
for i from 1 to maxAssemble
    assembleId[i] = 0
    assembleLabel$[i] = ""
    assembleDur[i] = 0
endfor

for i from 1 to nTotalAtoms
    # Always copy so repeated atom IDs become separate objects
    selectObject: cycleAtomId[i]
    atomCopy = Copy: "atom_seq_" + string$(i)

    # --- Envelope shaping ---
    if shape_atoms = 1
        selectObject: atomCopy
        aDur = Get total duration
        fadeIn = fade_in
        fadeOut = fade_out
        if fadeIn + fadeOut > aDur * 0.9
            fadeIn = aDur * 0.4
            fadeOut = aDur * 0.4
        endif
        Fade in: 0, 0, fadeIn, "yes"
        Fade out: 0, aDur - fadeOut, fadeOut, "yes"
    endif

    selectObject: atomCopy
    aDur = Get total duration
    nAssemble += 1
    assembleId[nAssemble] = atomCopy
    assembleLabel$[nAssemble] = symbol$[cycleSymId[i]]
    assembleDur[nAssemble] = aDur

    # --- Gap after each atom except the last ---
    if i < nTotalAtoms and gap_mode > 1
        if gap_mode = 2
            gapDur = gap_base
        elsif gap_mode = 3
            gapDur = gap_base * (1 + (i - 1) * 0.3)
        elsif gap_mode = 4
            denom = 1 + (i - 1) * 0.3
            gapDur = gap_base / denom
        else
            gapDur = gap_base * (0.5 + randomUniform(0, 1))
        endif
        if gapDur < 0.010
            gapDur = 0.010
        endif
        silSnd = Create Sound from formula: "gap", 1, 0, gapDur, sr, "0"
        nAssemble += 1
        assembleId[nAssemble] = silSnd
        assembleLabel$[nAssemble] = "gap"
        assembleDur[nAssemble] = gapDur
    endif
endfor

# Concatenate all pieces (atoms + gaps)
selectObject: assembleId[1]
for i from 2 to nAssemble
    plusObject: assembleId[i]
endfor
if nAssemble > 1
    Concatenate with overlap: crossfade
else
    Copy: "result"
endif
resynthSound = selected("Sound")
Rename: soundName$ + "_Llogic_result"

# Clean all assembled pieces (copies + gaps) and atom bank
for i from 1 to nAssemble
    removeObject: assembleId[i]
endfor
for cyc from 1 to cycles
    for s from 1 to nSymbols
        aId = atomBank[cyc * 100 + s]
        if aId > 0
            removeObject: aId
        endif
    endfor
endfor

# ── 16. COUNT CATEGORIES ───────────────────────────────────
psiCount = 0
thetaCount = 0
nullCount = 0
chiCount = 0
phiCount = 0
omegaCount = 0
psiDur = 0
thetaDur = 0
nullDur = 0
chiDur = 0
phiDur = 0
omegaDur = 0

for i from 1 to nMerged
    sDur = mEnd[i] - mStart[i]
    if mLabel$[i] = "psi"
        psiCount += 1
        psiDur += sDur
    elsif mLabel$[i] = "theta"
        thetaCount += 1
        thetaDur += sDur
    elsif mLabel$[i] = "null"
        nullCount += 1
        nullDur += sDur
    elsif mLabel$[i] = "chi"
        chiCount += 1
        chiDur += sDur
    elsif mLabel$[i] = "phi"
        phiCount += 1
        phiDur += sDur
    elsif mLabel$[i] = "omega"
        omegaCount += 1
        omegaDur += sDur
    endif
endfor

totalCatDur = psiDur + thetaDur + nullDur + chiDur + phiDur + omegaDur
if totalCatDur < 0.0001
    totalCatDur = duration
endif

# Build dominance string (sorted by count, descending)
# Simple: list present categories by count
domStr$ = ""
domCounts = 0

# Find max 6 iterations for sorting. A category is "used up"
# by setting its count to -1, so it cannot be picked again.
for rank from 1 to 6
    bestLab$ = ""
    bestN = -1
    if psiCount > bestN
        bestLab$ = "ψ"
        bestN = psiCount
    endif
    if thetaCount > bestN
        bestLab$ = "θ"
        bestN = thetaCount
    endif
    if chiCount > bestN
        bestLab$ = "χ"
        bestN = chiCount
    endif
    if phiCount > bestN
        bestLab$ = "ϕ"
        bestN = phiCount
    endif
    if omegaCount > bestN
        bestLab$ = "ω"
        bestN = omegaCount
    endif
    if nullCount > bestN
        bestLab$ = "Ø"
        bestN = nullCount
    endif
    if bestN > 0
        if domStr$ = ""
            domStr$ = bestLab$
        else
            domStr$ = domStr$ + " > " + bestLab$
        endif
    endif
    # Mark the selected category as used
    if bestLab$ = "ψ"
        psiCount = -1
    elsif bestLab$ = "θ"
        thetaCount = -1
    elsif bestLab$ = "χ"
        chiCount = -1
    elsif bestLab$ = "ϕ"
        phiCount = -1
    elsif bestLab$ = "ω"
        omegaCount = -1
    elsif bestLab$ = "Ø"
        nullCount = -1
    endif
endfor

# Restore counts for display
psiCount = 0
thetaCount = 0
nullCount = 0
chiCount = 0
phiCount = 0
omegaCount = 0
for i from 1 to nMerged
    if mLabel$[i] = "psi"
        psiCount += 1
    elsif mLabel$[i] = "theta"
        thetaCount += 1
    elsif mLabel$[i] = "null"
        nullCount += 1
    elsif mLabel$[i] = "chi"
        chiCount += 1
    elsif mLabel$[i] = "phi"
        phiCount += 1
    elsif mLabel$[i] = "omega"
        omegaCount += 1
    endif
endfor

# Build LPC representation (which categories are present)
lpcStr$ = ""
lpcSnd$ = ""
if nullCount > 0
    lpcStr$ = "Ø"
endif
if psiCount > 0
    if lpcSnd$ <> ""
        lpcSnd$ = lpcSnd$ + " ∨ "
    endif
    lpcSnd$ = lpcSnd$ + "ψ"
endif
if thetaCount > 0
    if lpcSnd$ <> ""
        lpcSnd$ = lpcSnd$ + " ∨ "
    endif
    lpcSnd$ = lpcSnd$ + "θ"
endif
if phiCount > 0
    if lpcSnd$ <> ""
        lpcSnd$ = lpcSnd$ + " ∨ "
    endif
    lpcSnd$ = lpcSnd$ + "ϕ"
endif
if chiCount > 0
    if lpcSnd$ <> ""
        lpcSnd$ = lpcSnd$ + " ∨ "
    endif
    lpcSnd$ = lpcSnd$ + "χ"
endif
if omegaCount > 0
    if lpcSnd$ <> ""
        lpcSnd$ = lpcSnd$ + " ∨ "
    endif
    lpcSnd$ = lpcSnd$ + "ω"
endif

if lpcStr$ <> "" and lpcSnd$ <> ""
    lpcStr$ = lpcStr$ + " ∨ (" + lpcSnd$ + ")"
elsif lpcSnd$ <> ""
    lpcStr$ = lpcSnd$
endif

# ── 17. VISUALIZATION ──────────────────────────────────────
if draw_visualization

    # Get waveform amplitude range
    selectObject: originalSound
    nCh = Get number of channels
    if nCh > 1
        vizMono = Convert to mono
    else
        vizMono = Copy: "viz_mono"
    endif
    selectObject: vizMono
    wMax = Get maximum: 0, 0, "Sinc70"
    wMin = Get minimum: 0, 0, "Sinc70"
    if wMax < 0
        wMax = -wMax
    endif
    if wMin < 0
        wMin = -wMin
    endif
    if wMin > wMax
        wMax = wMin
    endif
    ampMax = wMax * 1.1
    if ampMax < 0.001
        ampMax = 0.001
    endif

    Erase all

    # === TITLE ===
    Select outer viewport: 0, 8, 0, 0.45
    Axes: 0, 1, 0, 1
    Font size: 11
    Colour: "Black"
    Text: 0.5, "centre", 0.75, "half",
        ... "##Llogic System v4.1##"
    Font size: 7
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", 0.05, "half",
        ... soundName$ + " | " + fixed$(duration, 2) + " s | "
        ... + string$(nMerged) + " segments | "
        ... + string$(nCand) + " candidates"

    # === PANEL 1: Waveform with color-coded Llogic regions ===
    Select outer viewport: 0, 8, 0.5, 2.3
    Select inner viewport: 0.7, 7.6, 0.6, 2.2
    Axes: 0, duration, -ampMax, ampMax

    # Paint colored regions for each merged segment
    for i from 1 to nMerged
        lab$ = mLabel$[i]
        if lab$ = "null"
            regColour$ = "{0.90, 0.90, 0.90}"
        elsif lab$ = "psi"
            regColour$ = "{0.75, 0.88, 0.98}"
        elsif lab$ = "theta"
            regColour$ = "{0.75, 0.95, 0.78}"
        elsif lab$ = "chi"
            regColour$ = "{0.98, 0.78, 0.75}"
        elsif lab$ = "phi"
            regColour$ = "{0.88, 0.78, 0.98}"
        elsif lab$ = "omega"
            regColour$ = "{0.98, 0.93, 0.70}"
        else
            regColour$ = "{0.95, 0.95, 0.95}"
        endif
        Paint rectangle: regColour$, mStart[i], mEnd[i], -ampMax, ampMax
    endfor

    # Draw waveform on top
    selectObject: vizMono
    Colour: "{0.15, 0.15, 0.2}"
    Line width: 1
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"

    # Zero line
    Colour: "{0.6, 0.6, 0.6}"
    Dotted line
    Draw line: 0, 0, duration, 0
    Solid line

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Amp"
    Text top: "no", "Waveform — Llogic timbral-textural regions"

    # === PANEL 2: HNR contour with thresholds ===
    Select outer viewport: 0, 8, 2.35, 3.6
    Select inner viewport: 0.7, 7.6, 2.45, 3.5
    hnrFloor = -10
    hnrCeil = 40

    Axes: 0, duration, hnrFloor, hnrCeil
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, hnrFloor, hnrCeil

    # Threshold zones
    Paint rectangle: "{0.88, 0.94, 1.0}",
        ... 0, duration, hnrFloor, hnr_psi
    Paint rectangle: "{0.93, 0.87, 1.0}",
        ... 0, duration, hnr_psi, hnr_theta
    Paint rectangle: "{0.88, 0.97, 0.88}",
        ... 0, duration, hnr_theta, hnrCeil

    # Threshold lines
    Colour: "{0.3, 0.6, 0.9}"
    Dotted line
    Draw line: 0, hnr_psi, duration, hnr_psi
    Colour: "{0.2, 0.7, 0.3}"
    Draw line: 0, hnr_theta, duration, hnr_theta
    Solid line

    # Draw HNR contour
    selectObject: hnrObj
    Colour: "{0.4, 0.2, 0.5}"
    Line width: 1.5
    Draw: 0, 0, hnrFloor, hnrCeil
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "HNR"
    Text top: "no", "Harmonicity — ψ(<" + fixed$(hnr_psi, 0)
        ... + ") | ϕ/ω(" + fixed$(hnr_psi, 0) + "-"
        ... + fixed$(hnr_theta, 0) + ") | θ(>"
        ... + fixed$(hnr_theta, 0) + ")"

    # Zone labels (right margin)
    Axes: 0, 1, hnrFloor, hnrCeil
    Font size: 5
    Colour: "{0.3, 0.6, 0.9}"
    Text: 0.98, "right", (hnrFloor + hnr_psi) / 2, "half", "ψ"
    Colour: "{0.6, 0.2, 0.8}"
    Text: 0.98, "right", (hnr_psi + hnr_theta) / 2, "half", "ϕ/ω"
    Colour: "{0.2, 0.7, 0.3}"
    Text: 0.98, "right", (hnr_theta + hnrCeil) / 2, "half", "θ"

    # === PANEL 3: Intensity contour with null threshold ===
    Select outer viewport: 0, 8, 3.65, 4.9
    Select inner viewport: 0.7, 7.6, 3.75, 4.8
    intFloor = 0
    intCeil = 90

    Axes: 0, duration, intFloor, intCeil
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, intFloor, intCeil

    # Null zone
    Paint rectangle: "{0.93, 0.93, 0.93}",
        ... 0, duration, intFloor, int_null

    # Null threshold line
    Colour: "{0.6, 0.6, 0.6}"
    Dotted line
    Draw line: 0, int_null, duration, int_null
    Solid line

    selectObject: intObj
    Colour: "{0.8, 0.35, 0.2}"
    Line width: 1.5
    Draw: 0, 0, intFloor, intCeil, "no"
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "dB"
    Text top: "no", "Intensity — Ø(<"
        ... + fixed$(int_null, 0) + " dB) | χ(rise≥"
        ... + fixed$(int_chi, 0) + " dB)"
    Text bottom: "yes", "Time (s)"

    # === PANEL 4: Lsets distribution bar ===
    Select outer viewport: 0, 8, 5.0, 5.55
    Select inner viewport: 0.7, 7.6, 5.05, 5.5
    Axes: 0, totalCatDur, 0, 1

    # Draw proportional bar
    barX = 0
    # null
    if nullDur > 0
        Paint rectangle: "{0.85, 0.85, 0.85}", barX, barX + nullDur, 0.1, 0.9
        Font size: 5
        Colour: "{0.4, 0.4, 0.4}"
        if nullDur / totalCatDur > 0.05
            Text: barX + nullDur / 2, "centre", 0.5, "half",
                ... "Ø " + fixed$(nullDur / totalCatDur * 100, 0) + "%"
        endif
        barX += nullDur
    endif
    # psi
    if psiDur > 0
        Paint rectangle: "{0.72, 0.87, 0.98}", barX, barX + psiDur, 0.1, 0.9
        Font size: 5
        Colour: "{0.2, 0.5, 0.85}"
        if psiDur / totalCatDur > 0.05
            Text: barX + psiDur / 2, "centre", 0.5, "half",
                ... "ψ " + fixed$(psiDur / totalCatDur * 100, 0) + "%"
        endif
        barX += psiDur
    endif
    # phi
    if phiDur > 0
        Paint rectangle: "{0.85, 0.75, 0.98}", barX, barX + phiDur, 0.1, 0.9
        Font size: 5
        Colour: "{0.55, 0.2, 0.8}"
        if phiDur / totalCatDur > 0.05
            Text: barX + phiDur / 2, "centre", 0.5, "half",
                ... "ϕ " + fixed$(phiDur / totalCatDur * 100, 0) + "%"
        endif
        barX += phiDur
    endif
    # theta
    if thetaDur > 0
        Paint rectangle: "{0.72, 0.95, 0.75}", barX, barX + thetaDur, 0.1, 0.9
        Font size: 5
        Colour: "{0.2, 0.6, 0.25}"
        if thetaDur / totalCatDur > 0.05
            Text: barX + thetaDur / 2, "centre", 0.5, "half",
                ... "θ " + fixed$(thetaDur / totalCatDur * 100, 0) + "%"
        endif
        barX += thetaDur
    endif
    # chi
    if chiDur > 0
        Paint rectangle: "{0.98, 0.75, 0.72}", barX, barX + chiDur, 0.1, 0.9
        Font size: 5
        Colour: "{0.8, 0.2, 0.15}"
        if chiDur / totalCatDur > 0.05
            Text: barX + chiDur / 2, "centre", 0.5, "half",
                ... "χ " + fixed$(chiDur / totalCatDur * 100, 0) + "%"
        endif
        barX += chiDur
    endif
    # omega
    if omegaDur > 0
        Paint rectangle: "{0.98, 0.92, 0.68}", barX, barX + omegaDur, 0.1, 0.9
        Font size: 5
        Colour: "{0.7, 0.6, 0.1}"
        if omegaDur / totalCatDur > 0.05
            Text: barX + omegaDur / 2, "centre", 0.5, "half",
                ... "ω " + fixed$(omegaDur / totalCatDur * 100, 0) + "%"
        endif
    endif

    Colour: "Black"
    Draw rectangle: 0, totalCatDur, 0.1, 0.9
    Font size: 7
    Axes: 0, 1, 0, 1
    Text: 0.5, "centre", 1.15, "half", "Lsets distribution (% of duration)"

    # === PANEL 5: Stats ===
    Select outer viewport: 0, 8, 5.6, 7.1
    Select inner viewport: 0.4, 7.8, 5.65, 7.05
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.95, "half", "##Llogic Analysis##"
    Font size: 5.5
    Colour: "{0.25, 0.25, 0.3}"

    # Lsets string (truncate if too long for display)
    lsNoPdisp$ = lsetsNoP$
    if length(lsNoPdisp$) > 100
        lsNoPdisp$ = left$(lsNoPdisp$, 97) + "..."
    endif
    Text: 0.02, "left", 0.84, "half",
        ... "Lsets:  " + lsNoPdisp$

    lsWPdisp$ = lsetsWithP$
    if length(lsWPdisp$) > 100
        lsWPdisp$ = left$(lsWPdisp$, 97) + "..."
    endif
    Text: 0.02, "left", 0.72, "half",
        ... "Lsets∧Ø:  " + lsWPdisp$

    lsDdisp$ = lsetsDur$
    if length(lsDdisp$) > 100
        lsDdisp$ = left$(lsDdisp$, 97) + "..."
    endif
    Text: 0.02, "left", 0.60, "half",
        ... "Lsets∧Ø(dur):  " + lsDdisp$

    # Counts
    Text: 0.02, "left", 0.46, "half",
        ... "Segments:  Ø:" + string$(nullCount)
        ... + "  ψ:" + string$(psiCount)
        ... + "  ϕ:" + string$(phiCount)
        ... + "  θ:" + string$(thetaCount)
        ... + "  χ:" + string$(chiCount)
        ... + "  ω:" + string$(omegaCount)
        ... + "  (total: " + string$(nMerged) + ")"

    # Dominance
    Text: 0.02, "left", 0.34, "half",
        ... "Dominance:  " + domStr$

    # LPC
    Text: 0.02, "left", 0.22, "half",
        ... "LPC:  " + lpcStr$

    # Proposition
    Text: 0.02, "left", 0.10, "half",
        ... "Proposition:  " + proposition$
        ... + "  →  " + string$(nTotalAtoms)
        ... + " atoms placed"

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # === LEGEND ===
    Select outer viewport: 0, 8, 7.15, 7.45
    Select inner viewport: 0.4, 7.8, 7.15, 7.45
    Axes: 0, 1, 0, 1
    Font size: 5.5
    # null
    Paint rectangle: "{0.85, 0.85, 0.85}", 0.00, 0.03, 0.2, 0.8
    Colour: "Black"
    Text: 0.04, "left", 0.5, "half", "Ø null"
    # psi
    Paint rectangle: "{0.72, 0.87, 0.98}", 0.14, 0.17, 0.2, 0.8
    Colour: "Black"
    Text: 0.18, "left", 0.5, "half", "ψ airy"
    # phi
    Paint rectangle: "{0.85, 0.75, 0.98}", 0.29, 0.32, 0.2, 0.8
    Colour: "Black"
    Text: 0.33, "left", 0.5, "half", "ϕ vibr"
    # theta
    Paint rectangle: "{0.72, 0.95, 0.75}", 0.44, 0.47, 0.2, 0.8
    Colour: "Black"
    Text: 0.48, "left", 0.5, "half", "θ tone"
    # chi
    Paint rectangle: "{0.98, 0.75, 0.72}", 0.59, 0.62, 0.2, 0.8
    Colour: "Black"
    Text: 0.63, "left", 0.5, "half", "χ perc"
    # omega
    Paint rectangle: "{0.98, 0.92, 0.68}", 0.74, 0.77, 0.2, 0.8
    Colour: "Black"
    Text: 0.78, "left", 0.5, "half", "ω multi"

    Font size: 10
    Colour: "Black"
    Line width: 1

    removeObject: vizMono
endif

# ── 18. CLEANUP ────────────────────────────────────────────
removeObject: pitchObj, hnrObj, intObj

# ── 19. INFO OUTPUT ────────────────────────────────────────
selectObject: resynthSound

clearinfo
writeInfoLine: "=================================================="
writeInfoLine: "  LLOGIC SYSTEM v4.1"
writeInfoLine: "  Based on: Logic of Sound and Silence"
writeInfoLine: "  (Rakhat-Bi Abdyssagin)"
writeInfoLine: "=================================================="
appendInfoLine: ""
appendInfoLine: "Source:    ", soundName$
appendInfoLine: "Duration:  ", fixed$(duration, 3), " s"
appendInfoLine: "Segments:  ", nMerged, " merged from ", nSegs, " windows"
appendInfoLine: "Win/Step:  ", fixed$(win_len, 3), " / ",
    ... fixed$(win_step, 3), " s"
appendInfoLine: "Min pitch: ", fixed$(min_pitch, 0), " Hz"
appendInfoLine: ""
appendInfoLine: "── CLASSIFICATION THRESHOLDS ──"
appendInfoLine: "  Ø (null):  intensity < ", fixed$(int_null, 1), " dB"
appendInfoLine: "  χ (chi):   intensity rise ≥ ", fixed$(int_chi, 1), " dB"
appendInfoLine: "  θ (theta): HNR > ", fixed$(hnr_theta, 1),
    ... " AND F0 present"
appendInfoLine: "  ϕ (phi):   ", fixed$(hnr_psi, 1), " ≤ HNR ≤ ",
    ... fixed$(hnr_theta, 1), " AND F0 present"
appendInfoLine: "  ω (omega): HNR ≥ ", fixed$(hnr_psi, 1),
    ... " AND F0 absent"
appendInfoLine: "  ψ (psi):   HNR < ", fixed$(hnr_psi, 1)
appendInfoLine: ""
appendInfoLine: "── LSETS REPRESENTATIONS ──"
appendInfoLine: ""
appendInfoLine: "Lsets (no pauses):"
appendInfoLine: "  ", lsetsNoP$
appendInfoLine: ""
appendInfoLine: "Lsets ∧ Ø (with pauses, phrases in brackets):"
appendInfoLine: "  ", lsetsWithP$
appendInfoLine: ""
appendInfoLine: "Lsets ∧ Ø (with duration classes):"
appendInfoLine: "  ", lsetsDur$
appendInfoLine: ""
appendInfoLine: "── CATEGORY TALLY ──"
appendInfoLine: "  Ø  (null):  ", nullCount,
    ... " segments, ", fixed$(nullDur, 3), " s (",
    ... fixed$(nullDur / totalCatDur * 100, 1), "%)"
appendInfoLine: "  ψ  (psi):   ", psiCount,
    ... " segments, ", fixed$(psiDur, 3), " s (",
    ... fixed$(psiDur / totalCatDur * 100, 1), "%)"
appendInfoLine: "  ϕ  (phi):   ", phiCount,
    ... " segments, ", fixed$(phiDur, 3), " s (",
    ... fixed$(phiDur / totalCatDur * 100, 1), "%)"
appendInfoLine: "  θ  (theta): ", thetaCount,
    ... " segments, ", fixed$(thetaDur, 3), " s (",
    ... fixed$(thetaDur / totalCatDur * 100, 1), "%)"
appendInfoLine: "  χ  (chi):   ", chiCount,
    ... " segments, ", fixed$(chiDur, 3), " s (",
    ... fixed$(chiDur / totalCatDur * 100, 1), "%)"
appendInfoLine: "  ω  (omega): ", omegaCount,
    ... " segments, ", fixed$(omegaDur, 3), " s (",
    ... fixed$(omegaDur / totalCatDur * 100, 1), "%)"
appendInfoLine: ""
appendInfoLine: "── DOMINANCE ──"
appendInfoLine: "  ", domStr$
appendInfoLine: ""
appendInfoLine: "── LPC ──"
appendInfoLine: "  ", lpcStr$
appendInfoLine: ""
appendInfoLine: "── PROPOSITION ──"
appendInfoLine: "  Requested: ", proposition$
appendInfoLine: "  Cycles: ", cycles
appendInfoLine: "  Atoms placed: ", nTotalAtoms, " (", nSymbols, " symbols × ", cycles, " cycles, expanded by arrangement)"
for s from 1 to nSymbols
    req$ = symbol$[s]
    nRanked = rankCount[s]
    if nRanked > 0
        appendInfoLine: "    ", req$, " → ", nRanked, " candidates available"
    else
        appendInfoLine: "    ", req$, " → MISSING"
    endif
endfor
appendInfoLine: ""
appendInfoLine: "── CANDIDATE POOL ──"
appendInfoLine: "  Total: ", nCand, " segments"
# Count per category in pool
poolPsi = 0
poolTheta = 0
poolNull = 0
poolChi = 0
poolPhi = 0
poolOmega = 0
for i from 1 to nCand
    if candLabel$[i] = "psi"
        poolPsi += 1
    elsif candLabel$[i] = "theta"
        poolTheta += 1
    elsif candLabel$[i] = "null"
        poolNull += 1
    elsif candLabel$[i] = "chi"
        poolChi += 1
    elsif candLabel$[i] = "phi"
        poolPhi += 1
    elsif candLabel$[i] = "omega"
        poolOmega += 1
    endif
endfor
appendInfoLine: "  Ø:", poolNull, "  ψ:", poolPsi,
    ... "  ϕ:", poolPhi, "  θ:", poolTheta,
    ... "  χ:", poolChi, "  ω:", poolOmega
appendInfoLine: ""
appendInfoLine: "── ARRANGEMENT ──"
if arrangement = 1
    arrName$ = "Linear"
elsif arrangement = 2
    arrName$ = "Retrograde"
elsif arrangement = 3
    arrName$ = "Palindrome"
elsif arrangement = 4
    arrName$ = "Accumulation"
elsif arrangement = 5
    arrName$ = "Stutter"
elsif arrangement = 6
    arrName$ = "Scatter"
endif
appendInfoLine: "  Mode: ", arrName$
appendInfoLine: "  Cycles: ", cycles
appendInfoLine: "  Total atoms in sequence: ", nSeq
appendInfoLine: ""
appendInfoLine: "Output: ", soundName$ + "_Llogic_result"
appendInfoLine: ""
appendInfoLine: "=================================================="

# ── PLAY RESULT ─────────────────────────────────────────────
selectObject: resynthSound
Play
