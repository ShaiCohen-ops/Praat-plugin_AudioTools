# ============================================================
# Praat AudioTools - L-Logic Symbolic Granular Recomposition.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 4.3 (2026)
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
#     χ:  intensity rise rate >= chi_rise_dB_per_s
#     θ:  HNR > hnr_theta AND F0 present
#     ϕ:  hnr_psi <= HNR <= hnr_theta AND F0 present
#     ω:  HNR >= hnr_psi AND F0 absent (heuristic structured/non-single-pitch candidate)
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
# Changelog v4.3 (visualization only; DSP/classification unchanged):
#   - Rebuilt title/subtitle geometry to the AudioTools library standard.
#   - Fixed Picture export by re-selecting the full page at the end.
#   - Kept the six Llogic category colours as semantic encoding, while
#     moving analytical traces to a neutral slate so colour means category.
#   - Replaced the large text-report panel with a symbolic recomposition map
#     showing the actual atom/gap sequence on the rendered output timeline.
#   - Regularized panel geometry, typography, spacing and the summary strip.
#
# Changelog v4.2 (from v4.1):
#   - FIXED non-zero Sound time domains: analysis/rendering now work from a
#     zero-based source copy, while the user's original Sound remains untouched.
#   - MULTICHANNEL PRESERVATION: atoms are extracted from the original-channel
#     source; silence gaps use the same channel count. v4.1 forced every atom
#     to mono and therefore collapsed stereo/multichannel output.
#   - TRUE SEGMENT PARTITION: after phi bridging, adjacent categories are
#     canonicalized to non-overlapping intervals whose boundary is the midpoint
#     between the last frame-centre of the left label and the first frame-centre
#     of the right label. Category durations now sum exactly to source duration,
#     and candidate atoms no longer contain audio already assigned to a neighbour.
#   - Modernized pitch analysis to To Pitch (raw autocorrelation) and exposed
#     Max_pitch_Hz; high-F0 material is no longer silently forced unvoiced by a
#     hard-coded 600-Hz ceiling.
#   - Chi onset detection is step-invariant: threshold is now dB/s rather than
#     dB per analysis frame, so changing Win_step does not change its meaning.
#   - Proposition parser accepts English names AND Llogic glyphs (Ø ψ θ χ ϕ/φ ω),
#     normalizes them to canonical internal labels, and rejects unknown symbols.
#   - Crossfade may be zero and is capped safely to < half the shortest atom.
#     When gaps are requested, their created duration compensates for the two
#     overlap joins so Gap_base remains the actual atom-to-atom separation.
#   - Dominance is ranked by occupied duration rather than raw segment count.
#   - Added guards for analysis thresholds, cycles, proposition length, and
#     candidate/sequence limits; no more silent truncation at 10,000 frames.
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
form Llogic Symbolic Granular Recomposition v4.3
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
    positive Max_pitch_Hz 1200
    positive Hnr_psi 5.0
    positive Hnr_theta 18.0
    positive Int_null 25.0
    positive Chi_rise_dB_per_s 267
    real Crossfade 0.030
    natural Cycles 3
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

# ── 3. VALIDATE & DERIVE ───────────────────────────────────
if win_len <= 0 or win_step <= 0
    exitScript: "Win_len and Win_step must be > 0."
endif
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
if max_pitch_Hz <= min_pitch
    exitScript: "Max_pitch_Hz must be greater than Min_pitch."
endif
if hnr_theta <= hnr_psi
    exitScript: "Hnr_theta must be greater than Hnr_psi."
endif
if chi_rise_dB_per_s <= 0
    exitScript: "Chi rise threshold must be > 0 dB/s."
endif
if crossfade < 0
    exitScript: "Crossfade must be >= 0."
endif
if cycles < 1 or cycles > 100
    exitScript: "Cycles must be between 1 and 100."
endif
if fade_in < 0 or fade_out < 0
    exitScript: "Fade durations must be >= 0."
endif

# Silence duration thresholds (absolute, in seconds)
silShort = 0.15
silMed = 0.40

# ── 4. ANALYSIS OBJECTS ────────────────────────────────────
selectObject: originalSound
duration = Get total duration
sr = Get sampling frequency
sourceStart = Get start time
sourceChannels = Get number of channels

if duration < win_len
    exitScript: "Audio is shorter than Win_len."
endif
if max_pitch_Hz >= sr / 2
    max_pitch_Hz = 0.45 * sr
endif
if max_pitch_Hz <= min_pitch
    exitScript: "Pitch range is invalid for this sampling rate."
endif

# Work in a zero-based time domain so all structural offsets are 0..duration.
# Keep all channels for rendering; the original user object is untouched.
selectObject: originalSound
sourceZero = Copy: "Llogic_source"
Shift times to: "start time", 0

# Praat's intensity calculation supports multichannel energy. Pitch/HNR are
# analysed on a mono fold, but rendering never uses this analysis copy.
selectObject: sourceZero
intObj = To Intensity: min_pitch, win_step, "yes"

selectObject: sourceZero
if sourceChannels > 1
    analysisMono = Convert to mono
else
    analysisMono = Copy: "Llogic_analysis"
endif

selectObject: analysisMono
hnrObj = To Harmonicity (cc): win_step, min_pitch, 0.1, 1.0

selectObject: analysisMono
pitchObj = To Pitch (raw autocorrelation): 0, min_pitch, max_pitch_Hz,
    ... 15, "no", 0.03, 0.45, 0.01, 0.35, 0.14

# ── 5. CLASSIFY WINDOWS ────────────────────────────────────
maxSegs = 100000
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
    intRiseRate = intRise / win_step

    # ── CLASSIFY (6 Lsets categories) ──
    # Ø (null):  silence — low intensity
    # χ (chi):   percussive — sharp intensity onset
    # θ (theta): ordinary — high HNR + clear pitch
    # ϕ (phi):   vibrational — moderate HNR + pitch present
    # ω (omega): multiphonic — moderate+ HNR, no single pitch
    # ψ (psi):   airy — low HNR (noisy/breathy)

    if intVal < int_null
        label$ = "null"
    elsif intRiseRate >= chi_rise_dB_per_s
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
        removeObject: pitchObj, hnrObj, intObj, analysisMono, sourceZero
        exitScript: "Too many analysis frames (>100000). Increase Win_step or shorten the source."
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

# ── 6c. CANONICAL NON-OVERLAPPING PARTITION ─────────────────
# When Win_step < Win_len, analysis windows overlap. The merged raw extents then
# overlap too. Convert them to a true partition: each label-change boundary is
# halfway between the last frame centre on the left and the first frame centre
# on the right, which equals (leftRawEnd + rightRawStart)/2 for equal windows.
if nMerged > 0
    for i from 1 to nMerged
        rawStart[i] = mStart[i]
        rawEnd[i] = mEnd[i]
    endfor
    mStart[1] = 0
    for i from 1 to nMerged - 1
        boundary = 0.5 * (rawEnd[i] + rawStart[i + 1])
        if boundary < mStart[i]
            boundary = mStart[i]
        endif
        if boundary > duration
            boundary = duration
        endif
        mEnd[i] = boundary
        mStart[i + 1] = boundary
    endfor
    mEnd[nMerged] = duration
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
selectObject: sourceZero
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
        if nCand > maxCand
            removeObject: pitchObj, hnrObj, intObj, analysisMono, sourceZero
            exitScript: "Too many candidate segments (>5000)."
        endif
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
if nSymbols > maxSym
    exitScript: "Proposition contains more than 50 symbols."
endif

# Accept both English names and actual Llogic glyphs; canonicalize internally.
for s from 1 to nSymbols
    tok$ = symbol$[s]
    if tok$ = "Ø" or tok$ = "ø" or tok$ = "null" or tok$ = "NULL"
        symbol$[s] = "null"
    elsif tok$ = "ψ" or tok$ = "psi" or tok$ = "PSI"
        symbol$[s] = "psi"
    elsif tok$ = "θ" or tok$ = "theta" or tok$ = "THETA"
        symbol$[s] = "theta"
    elsif tok$ = "χ" or tok$ = "chi" or tok$ = "CHI"
        symbol$[s] = "chi"
    elsif tok$ = "ϕ" or tok$ = "φ" or tok$ = "phi" or tok$ = "PHI"
        symbol$[s] = "phi"
    elsif tok$ = "ω" or tok$ = "omega" or tok$ = "OMEGA"
        symbol$[s] = "omega"
    else
        exitScript: "Unknown Llogic proposition symbol: " + tok$
    endif
endfor

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

            selectObject: sourceZero
            atomSnd = Extract part: candStart[cIdx], candEnd[cIdx],
                ... "rectangular", 1, "no"
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
    removeObject: pitchObj, hnrObj, intObj, analysisMono, sourceZero
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
    removeObject: pitchObj, hnrObj, intObj, analysisMono, sourceZero
    exitScript: "No atoms to concatenate."
endif

# Get sample rate from first atom
selectObject: cycleAtomId[1]
sr = Get sampling frequency

# Global safe overlap: Concatenate with overlap uses one overlap value at
# every join, so cap it against the shortest atom to avoid invalid joins.
minAtomDur = 1e30
for i from 1 to nTotalAtoms
    selectObject: cycleAtomId[i]
    d = Get total duration
    if d < minAtomDur
        minAtomDur = d
    endif
endfor
safeCrossfade = min(crossfade, 0.45 * minAtomDur)

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
        if gapDur < 0
            gapDur = 0
        endif
        # The gap participates in two overlap joins. Add 2*x so the next atom
        # still begins exactly gapDur seconds after the previous atom's end.
        renderedGapDur = gapDur + 2 * safeCrossfade
        silSnd = Create Sound from formula: "gap", sourceChannels, 0, renderedGapDur, sr, "0"
        nAssemble += 1
        assembleId[nAssemble] = silSnd
        assembleLabel$[nAssemble] = "gap"
        assembleDur[nAssemble] = renderedGapDur
    endif
endfor

# Concatenate all pieces (atoms + gaps)
selectObject: assembleId[1]
for i from 2 to nAssemble
    plusObject: assembleId[i]
endfor
if nAssemble > 1
    if safeCrossfade > 0
        Concatenate with overlap: safeCrossfade
    else
        Concatenate
    endif
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

# Build dominance string (sorted by occupied duration, descending).
# Duration is a more faithful meaning of category dominance than the number of
# merged segments (many tiny onsets should not outrank one long sustained set).
domStr$ = ""
workPsiDur = psiDur
workThetaDur = thetaDur
workNullDur = nullDur
workChiDur = chiDur
workPhiDur = phiDur
workOmegaDur = omegaDur
for rank from 1 to 6
    bestLab$ = ""
    bestDur = -1
    if psiDur >= 0 and workPsiDur > bestDur
        bestLab$ = "ψ"
        bestDur = workPsiDur
    endif
    if workThetaDur > bestDur
        bestLab$ = "θ"
        bestDur = workThetaDur
    endif
    if workChiDur > bestDur
        bestLab$ = "χ"
        bestDur = workChiDur
    endif
    if workPhiDur > bestDur
        bestLab$ = "ϕ"
        bestDur = workPhiDur
    endif
    if workOmegaDur > bestDur
        bestLab$ = "ω"
        bestDur = workOmegaDur
    endif
    if workNullDur > bestDur
        bestLab$ = "Ø"
        bestDur = workNullDur
    endif
    if bestDur > 0
        if domStr$ = ""
            domStr$ = bestLab$
        else
            domStr$ = domStr$ + " > " + bestLab$
        endif
    endif
    if bestLab$ = "ψ"
        workPsiDur = -1
    elsif bestLab$ = "θ"
        workThetaDur = -1
    elsif bestLab$ = "χ"
        workChiDur = -1
    elsif bestLab$ = "ϕ"
        workPhiDur = -1
    elsif bestLab$ = "ω"
        workOmegaDur = -1
    elsif bestLab$ = "Ø"
        workNullDur = -1
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

    # Display source follows the same mono decision as analysis, but remains
    # un-normalized. Category colours carry the semantic meaning; waveforms
    # and analysis traces stay neutral.
    selectObject: sourceZero
    nCh = Get number of channels
    if nCh > 1
        vizMono = Convert to mono
    else
        vizMono = Copy: "viz_mono"
    endif
    selectObject: vizMono
    wMax = Get absolute extremum: 0, 0, "None"
    ampMax = wMax * 1.10
    if ampMax < 0.001
        ampMax = 0.001
    endif

    selectObject: resynthSound
    outputDuration = Get total duration
    outputChannels = Get number of channels

    vizName$ = replace$(soundName$, "_", "\_ ", 0)

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
    else
        arrName$ = "Scatter"
    endif

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # === TITLE ===
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Llogic Symbolic Granular Recomposition v4.3##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half",
        ... vizName$ + " | " + fixed$(duration, 2) + " s | "
        ... + string$(nMerged) + " regions | proposition: " + proposition$

    # === PANEL 1: CLASSIFIED SOURCE ===
    Select outer viewport: 0, 8, 0.65, 2.12
    Select inner viewport: 0.60, 7.70, 0.77, 2.02
    Axes: 0, duration, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, -ampMax, ampMax

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

    Colour: "{0.70, 0.70, 0.74}"
    Dotted line
    Draw line: 0, 0, duration, 0
    Solid line

    selectObject: vizMono
    Colour: "{0.38, 0.38, 0.46}"
    Line width: 1
    Draw: 0, duration, -ampMax, ampMax, "no", "Curve"

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Amp"
    Text top: "no", "Source classified into Llogic regions"

    # === PANEL 2: HARMONICITY CUE ===
    Select outer viewport: 0, 8, 2.28, 3.43
    Select inner viewport: 0.60, 7.70, 2.40, 3.33
    hnrFloor = -10
    hnrCeil = 40
    Axes: 0, duration, hnrFloor, hnrCeil
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, hnrFloor, hnrCeil

    Paint rectangle: "{0.88, 0.94, 1.00}", 0, duration, hnrFloor, hnr_psi
    Paint rectangle: "{0.93, 0.87, 1.00}", 0, duration, hnr_psi, hnr_theta
    Paint rectangle: "{0.88, 0.97, 0.88}", 0, duration, hnr_theta, hnrCeil

    Colour: "{0.55, 0.55, 0.65}"
    Dotted line
    Draw line: 0, hnr_psi, duration, hnr_psi
    Draw line: 0, hnr_theta, duration, hnr_theta
    Solid line

    selectObject: hnrObj
    Colour: "{0.35, 0.35, 0.50}"
    Line width: 1.5
    Draw: 0, 0, hnrFloor, hnrCeil
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "HNR"
    Text top: "no", "Harmonicity – one cue separating airy, vibrational/complex and tonal regions"

    Axes: 0, 1, hnrFloor, hnrCeil
    Font size: 6
    Colour: "{0.25, 0.45, 0.75}"
    Text: 0.985, "right", (hnrFloor + hnr_psi) / 2, "half", "ψ"
    Colour: "{0.55, 0.35, 0.70}"
    Text: 0.985, "right", (hnr_psi + hnr_theta) / 2, "half", "ϕ / ω"
    Colour: "{0.35, 0.60, 0.40}"
    Text: 0.985, "right", (hnr_theta + hnrCeil) / 2, "half", "θ"

    # === PANEL 3: INTENSITY / ONSET CUE ===
    Select outer viewport: 0, 8, 3.59, 4.74
    Select inner viewport: 0.60, 7.70, 3.71, 4.64
    intFloor = 0
    intCeil = 90
    Axes: 0, duration, intFloor, intCeil
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, intFloor, intCeil
    Paint rectangle: "{0.93, 0.93, 0.93}", 0, duration, intFloor, int_null

    Colour: "{0.65, 0.65, 0.68}"
    Dotted line
    Draw line: 0, int_null, duration, int_null
    Solid line

    selectObject: intObj
    Colour: "{0.35, 0.35, 0.50}"
    Line width: 1.5
    Draw: 0, 0, intFloor, intCeil, "no"
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "dB"
    Text top: "no", "Intensity – below " + fixed$(int_null, 0)
        ... + " dB becomes Ø; fast rises can become χ"
    Text bottom: "yes", "Time (s)"

    # === PANEL 4: LSETS DISTRIBUTION ===
    Select outer viewport: 0, 8, 4.98, 5.48
    Select inner viewport: 0.60, 7.70, 5.04, 5.43
    Axes: 0, totalCatDur, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, totalCatDur, 0, 1

    barX = 0
    if nullDur > 0
        Paint rectangle: "{0.85, 0.85, 0.85}", barX, barX + nullDur, 0.12, 0.88
        Font size: 6
        Colour: "{0.40, 0.40, 0.45}"
        if nullDur / totalCatDur > 0.05
            Text: barX + nullDur / 2, "centre", 0.5, "half", "Ø " + fixed$(nullDur / totalCatDur * 100, 0) + "%"
        endif
        barX += nullDur
    endif
    if psiDur > 0
        Paint rectangle: "{0.72, 0.87, 0.98}", barX, barX + psiDur, 0.12, 0.88
        Font size: 6
        Colour: "{0.25, 0.45, 0.75}"
        if psiDur / totalCatDur > 0.05
            Text: barX + psiDur / 2, "centre", 0.5, "half", "ψ " + fixed$(psiDur / totalCatDur * 100, 0) + "%"
        endif
        barX += psiDur
    endif
    if phiDur > 0
        Paint rectangle: "{0.85, 0.75, 0.98}", barX, barX + phiDur, 0.12, 0.88
        Font size: 6
        Colour: "{0.55, 0.35, 0.70}"
        if phiDur / totalCatDur > 0.05
            Text: barX + phiDur / 2, "centre", 0.5, "half", "ϕ " + fixed$(phiDur / totalCatDur * 100, 0) + "%"
        endif
        barX += phiDur
    endif
    if thetaDur > 0
        Paint rectangle: "{0.72, 0.95, 0.75}", barX, barX + thetaDur, 0.12, 0.88
        Font size: 6
        Colour: "{0.35, 0.60, 0.40}"
        if thetaDur / totalCatDur > 0.05
            Text: barX + thetaDur / 2, "centre", 0.5, "half", "θ " + fixed$(thetaDur / totalCatDur * 100, 0) + "%"
        endif
        barX += thetaDur
    endif
    if chiDur > 0
        Paint rectangle: "{0.98, 0.75, 0.72}", barX, barX + chiDur, 0.12, 0.88
        Font size: 6
        Colour: "{0.78, 0.28, 0.22}"
        if chiDur / totalCatDur > 0.05
            Text: barX + chiDur / 2, "centre", 0.5, "half", "χ " + fixed$(chiDur / totalCatDur * 100, 0) + "%"
        endif
        barX += chiDur
    endif
    if omegaDur > 0
        Paint rectangle: "{0.98, 0.92, 0.68}", barX, barX + omegaDur, 0.12, 0.88
        Font size: 6
        Colour: "{0.80, 0.60, 0.20}"
        if omegaDur / totalCatDur > 0.05
            Text: barX + omegaDur / 2, "centre", 0.5, "half", "ω " + fixed$(omegaDur / totalCatDur * 100, 0) + "%"
        endif
    endif
    Colour: "Black"
    Draw rectangle: 0, totalCatDur, 0.12, 0.88
    Font size: 7
    Axes: 0, 1, 0, 1
    Text: 0.5, "centre", 1.16, "half", "Lsets distribution – share of source duration"

    # === PANEL 5: SYMBOLIC RECOMPOSITION MAP ===
    Select outer viewport: 0, 8, 5.68, 6.72
    Select inner viewport: 0.60, 7.70, 5.80, 6.62
    Axes: 0, outputDuration, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, outputDuration, 0, 1

    mapPos = 0
    for i from 1 to nAssemble
        pStart = mapPos
        pEnd = pStart + assembleDur[i]
        if pEnd > outputDuration
            pEnd = outputDuration
        endif
        lab$ = assembleLabel$[i]
        if lab$ = "gap"
            # Inserted compositional gaps are not the Ø category: leave them
            # almost unfilled and use a dotted outline so semantic null stays grey.
            fill$ = "{0.97, 0.97, 0.97}"
            edge$ = "{0.60, 0.60, 0.65}"
            gk$ = "gap"
        elsif lab$ = "null"
            fill$ = "{0.85, 0.85, 0.85}"
            edge$ = "{0.45, 0.45, 0.48}"
            gk$ = "Ø"
        elsif lab$ = "psi"
            fill$ = "{0.72, 0.87, 0.98}"
            edge$ = "{0.25, 0.45, 0.75}"
            gk$ = "ψ"
        elsif lab$ = "phi"
            fill$ = "{0.85, 0.75, 0.98}"
            edge$ = "{0.55, 0.35, 0.70}"
            gk$ = "ϕ"
        elsif lab$ = "theta"
            fill$ = "{0.72, 0.95, 0.75}"
            edge$ = "{0.35, 0.60, 0.40}"
            gk$ = "θ"
        elsif lab$ = "chi"
            fill$ = "{0.98, 0.75, 0.72}"
            edge$ = "{0.78, 0.28, 0.22}"
            gk$ = "χ"
        elsif lab$ = "omega"
            fill$ = "{0.98, 0.92, 0.68}"
            edge$ = "{0.80, 0.60, 0.20}"
            gk$ = "ω"
        else
            fill$ = "{0.92, 0.92, 0.92}"
            edge$ = "{0.55, 0.55, 0.60}"
            gk$ = lab$
        endif
        if pEnd > pStart
            Paint rectangle: fill$, pStart, pEnd, 0.18, 0.82
            Colour: edge$
            if lab$ = "gap"
                Dotted line
            endif
            Draw rectangle: pStart, pEnd, 0.18, 0.82
            Solid line
            if (pEnd - pStart) / outputDuration > 0.055
                Font size: 7
                Text: (pStart + pEnd) / 2, "centre", 0.50, "half", gk$
            endif
        endif
        if i < nAssemble
            mapPos = pEnd - safeCrossfade
            if mapPos < 0
                mapPos = 0
            endif
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Symbolic recomposition – selected atoms assembled as " + arrName$
    Text bottom: "yes", "Output time (s)"

    # === SUMMARY STRIP ===
    Select outer viewport: 0, 8, 6.90, 7.48
    Select inner viewport: 0.60, 7.70, 6.96, 7.42
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"

    lsDisp$ = lsetsNoP$
    if length(lsDisp$) > 86
        lsDisp$ = left$(lsDisp$, 83) + "..."
    endif
    Text: 0.02, "left", 0.72, "half",
        ... "##Detected##  " + lsDisp$ + "   |   Dominance: " + domStr$
    Text: 0.02, "left", 0.28, "half",
        ... "##Recomposition##  " + proposition$ + "  →  " + string$(nTotalAtoms)
        ... + " atoms rendered   |   " + arrName$ + "   |   out " + fixed$(outputDuration, 2)
        ... + " s / " + string$(outputChannels) + " ch"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # === CATEGORY LEGEND ===
    Select outer viewport: 0, 8, 7.58, 7.92
    Select inner viewport: 0.60, 7.70, 7.60, 7.90
    Axes: 0, 1, 0, 1
    Font size: 6

    Paint rectangle: "{0.85, 0.85, 0.85}", 0.00, 0.035, 0.20, 0.80
    Colour: "Black"
    Text: 0.045, "left", 0.5, "half", "Ø null"
    Paint rectangle: "{0.72, 0.87, 0.98}", 0.16, 0.195, 0.20, 0.80
    Text: 0.205, "left", 0.5, "half", "ψ airy"
    Paint rectangle: "{0.85, 0.75, 0.98}", 0.32, 0.355, 0.20, 0.80
    Text: 0.365, "left", 0.5, "half", "ϕ vibrational"
    Paint rectangle: "{0.72, 0.95, 0.75}", 0.51, 0.545, 0.20, 0.80
    Text: 0.555, "left", 0.5, "half", "θ tonal"
    Paint rectangle: "{0.98, 0.75, 0.72}", 0.67, 0.705, 0.20, 0.80
    Text: 0.715, "left", 0.5, "half", "χ percussive"
    Paint rectangle: "{0.98, 0.92, 0.68}", 0.84, 0.875, 0.20, 0.80
    Text: 0.885, "left", 0.5, "half", "ω complex"

    Font size: 10
    Colour: "Black"
    Line width: 1
    removeObject: vizMono

    # Export/Copy must see the entire figure, not only the final legend band.
    Select outer viewport: 0, 8, 0, 8
endif

# ── 18. CLEANUP ────────────────────────────────────────────
removeObject: pitchObj, hnrObj, intObj, analysisMono, sourceZero

# ── 19. INFO OUTPUT ────────────────────────────────────────
selectObject: resynthSound

clearinfo
writeInfoLine: "=================================================="
writeInfoLine: "  LLOGIC SYSTEM v4.3"
writeInfoLine: "  Based on: Logic of Sound and Silence"
writeInfoLine: "  (Rakhat-Bi Abdyssagin)"
writeInfoLine: "=================================================="
appendInfoLine: ""
appendInfoLine: "Source:    ", soundName$
appendInfoLine: "Duration:  ", fixed$(duration, 3), " s"
appendInfoLine: "Segments:  ", nMerged, " merged from ", nSegs, " windows"
appendInfoLine: "Win/Step:  ", fixed$(win_len, 3), " / ",
    ... fixed$(win_step, 3), " s"
appendInfoLine: "Pitch range: ", fixed$(min_pitch, 0), "-", fixed$(max_pitch_Hz, 0), " Hz"
appendInfoLine: ""
appendInfoLine: "── CLASSIFICATION THRESHOLDS ──"
appendInfoLine: "  Ø (null):  intensity < ", fixed$(int_null, 1), " dB"
appendInfoLine: "  χ (chi):   intensity rise rate ≥ ", fixed$(chi_rise_dB_per_s, 1), " dB/s"
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
appendInfoLine: "── DOMINANCE BY DURATION ──"
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
appendInfoLine: "  Output channels: ", sourceChannels
appendInfoLine: "  Requested/effective crossfade: ", fixed$(crossfade, 4), " / ", fixed$(safeCrossfade, 4), " s"
appendInfoLine: ""
appendInfoLine: "Output: ", soundName$ + "_Llogic_result"
appendInfoLine: ""
appendInfoLine: "=================================================="

# ── PLAY RESULT ─────────────────────────────────────────────
selectObject: resynthSound
Play
