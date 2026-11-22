# ============================================================
# Praat AudioTools - Stochastic_Caesura.praat
# Stochastic Caesura
# Phrase-aware silence insertion
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# Category: Time & Granular
#
# WHAT THIS DOES
#   Changes the temporal relationships between the phrases of one
#   selected Sound by INSERTING digital silence at acoustically safe
#   boundaries - existing quiet gaps between phrases - chosen at random.
#   Nothing is removed, muted, cut, faded, stretched, filtered,
#   resampled or normalized: every original sample keeps its value and
#   its order; only new zero-valued samples are added. The phrases stay
#   as they are; only the space between them grows.
#
# PIPELINE
#   1. Level analysis. RMS in 25 ms rectangular windows every 5 ms, per
#      channel, on a copy with each channel's mean (DC offset) removed;
#      in dBFS (20 log10 RMS, full scale = 1). Each frame takes the
#      LOUDEST channel, so one quiet channel never hides another one
#      that is sounding.
#   2. Adaptive threshold, from the recording itself:
#        active level = 95th percentile of the frame levels
#        floor        = 10th percentile
#        threshold    = max(active - 45 dB, floor + 8 dB)
#      If the threshold is not at least 24 dB below the active level,
#      the material has no reliable quiet gaps and nothing is inserted.
#   3. Quiet regions = uninterrupted runs of frames below the threshold,
#      at least Minimum_natural_gap_ms long (short closures inside
#      words, weak consonants and brief articulatory breaks are shorter
#      and are ignored). Regions touching the start or end of the
#      recording are not phrase boundaries and are ignored.
#   4. Boundary safety (each region gives at most ONE boundary):
#        contrast - within 600 ms before AND after the region the level
#                   must rise to at least threshold + 12 dB (600 ms lets
#                   a phrase's soft breathy tail precede the gap);
#                   otherwise it is a soft passage, not a clear gap;
#        position - the insertion point is searched in the central half
#                   of the region first, then in the region minus
#                   30 ms (or 15%) at each edge, away from the decay
#                   and the next attack;
#        click    - the point lies between two original samples that
#                   are both near zero on EVERY channel: at most -60 dBFS
#                   and at most -50 dB below the recording's peak. If no
#                   such pair exists the boundary is rejected; no fade
#                   is ever applied. (A recording with a DC offset in
#                   its pauses therefore offers no click-safe boundary.)
#   5. Stochastic choice. Each eligible boundary, in time order, is
#      selected with probability Pause_density_percent / 100, and only
#      if it lies at least Minimum_pause_separation_s after the
#      previously selected one. Each selected boundary receives a pause
#      length drawn UNIFORMLY between the minimum and maximum, rounded
#      to whole samples (the reported length is the inserted length).
#   6. Reconstruction. One output Sound is created at its final length
#      (original samples + inserted samples) and the original segments
#      are copied into it by sample index; the inserted spans stay
#      exact digital zero. The output is then checked sample by sample
#      against the original (see GUARANTEES).
#
# PAUSE MODES (duration range of each inserted pause)
#   Natural     120 - 450 ms     breathing, reflection, hesitation
#   Fragmented  400 - 1800 ms    irregular, pronounced interruptions
#   Suspended   1.5 - 5 s        extended, suspended silences
#   Custom      Minimum_added_pause_ms - Maximum_added_pause_ms
#   In every mode the user keeps Pause_density_percent,
#   Minimum_natural_gap_ms, Minimum_pause_separation_s and Random_seed;
#   the three named modes only replace the minimum / maximum pause. All
#   modes use the same conservative detector.
#
# GUARANTEES (verified at run time and reported PASS/FAIL)
#   - Output samples = original samples + inserted samples; same
#     sampling frequency and channel count; the original Sound is not
#     modified.
#   - Every original sample appears once, unchanged, in its original
#     order, at its shifted position; inserted spans are exact zeros.
#   - Same peak amplitude as the original.
#
# LIMITS
#   - Acoustic silence detection approximates phrase boundaries; it does
#     not understand language or musical syntax. Speech can contain
#     silences inside words and music can contain quiet passages inside
#     phrases. The detector is deliberately conservative: when unsure,
#     it inserts nothing. Raise Minimum_natural_gap_ms (e.g. 250 ms
#     for speech) to be more conservative still.
#   - Pause_density_percent is a probability: the realized number of
#     pauses varies, and few safe boundaries mean few pauses.
#
# ============================================================

# ---------------- Input validation ----------------
if numberOfSelected ("Sound") <> 1 or numberOfSelected () <> 1
    exitScript: "Please select exactly one Sound (and nothing else)."
endif
snd = selected ("Sound")
sndName$ = selected$ ("Sound")

# Changelog v1.0 (2026):
#   - Initial release.
#
form Stochastic Caesura v1.0
    comment Phrase-aware silence insertion: silence is added, audio is never removed
    optionmenu Pause_mode: 1
        option Natural
        option Fragmented
        option Suspended
        option Custom
    real Pause_density_percent 40
    comment Custom only: inserted pause range (ms)
    real Minimum_added_pause_ms 250
    real Maximum_added_pause_ms 1200
    real Minimum_natural_gap_ms 180
    real Minimum_pause_separation_s 0.5
    integer Random_seed 0
    boolean Show_visualization 1
    boolean Play_result 1
endform

# ---------------- Parameter checks ----------------
if pause_density_percent < 0 or pause_density_percent > 100
    exitScript: "Pause_density_percent must lie between 0 and 100 (got " + fixed$ (pause_density_percent, 2) + ")."
endif
if minimum_natural_gap_ms <= 0
    exitScript: "Minimum_natural_gap_ms must be positive (got " + fixed$ (minimum_natural_gap_ms, 1) + ")."
endif
if minimum_pause_separation_s < 0
    exitScript: "Minimum_pause_separation_s cannot be negative (got " + fixed$ (minimum_pause_separation_s, 3) + ")."
endif
if random_seed < 0
    exitScript: "Random_seed must be 0 (new realization) or a positive integer."
endif
if pause_mode = 1
    modeName$ = "Natural"
    pMinMs = 120
    pMaxMs = 450
elsif pause_mode = 2
    modeName$ = "Fragmented"
    pMinMs = 400
    pMaxMs = 1800
elsif pause_mode = 3
    modeName$ = "Suspended"
    pMinMs = 1500
    pMaxMs = 5000
else
    modeName$ = "Custom"
    pMinMs = minimum_added_pause_ms
    pMaxMs = maximum_added_pause_ms
    if pMinMs < 0 or pMaxMs < 0
        exitScript: "Pause durations cannot be negative (got " + fixed$ (pMinMs, 1) + " and " + fixed$ (pMaxMs, 1) + " ms)."
    endif
    if pMinMs > pMaxMs
        exitScript: "Minimum_added_pause_ms (" + fixed$ (pMinMs, 1) + ") is larger than Maximum_added_pause_ms ("
            ... + fixed$ (pMaxMs, 1) + ")."
    endif
    if pMaxMs = 0
        exitScript: "Maximum_added_pause_ms is 0: no silence could be inserted."
    endif
endif
if random_seed = 0
    random_initializeSafelyAndUnpredictably ()
    usedSeed = randomInteger (1, 2000000000)
    seedNote$ = string$ (usedSeed) + " (drawn; Random_seed = 0)"
else
    usedSeed = random_seed
    seedNote$ = string$ (usedSeed)
endif

# ---------------- Source ----------------
selectObject: snd
fs = Get sampling frequency
nCh = Get number of channels
nSamp = Get number of samples
xmin = Get start time
xmax = Get end time
x1 = Get time from sample number: 1
dx = 1 / fs
dur = xmax - xmin
peak = Get absolute extremum: 0, 0, "None"
for ch from 1 to nCh
    dcCh[ch] = Get mean: ch, 0, 0
endfor
srcRms = Get root-mean-square: 0, 0

clearinfo
appendInfoLine: "Stochastic Caesura v1.0 - analysing ", sndName$, "..."

# ============================================================
# 1-3. LEVEL ANALYSIS, THRESHOLD, QUIET REGIONS
# ============================================================
winS = 0.025
stepS = 0.005
hw = winS / 2
nF = 0
if dur >= winS
    nF = floor ((dur - winS) / stepS) + 1
endif
floorDb = -150
nQuiet = 0
nEdge = 0
nElig = 0
nRejClick = 0
nRejContrast = 0
status$ = ""
thr = undefined
actDb = undefined
flDb = undefined
clickTol = min (0.001, peak * 10 ^ (-50 / 20))

if peak = 0
    status$ = "The Sound is digital silence: there are no phrases and no boundaries."
elsif nF < 3
    status$ = "The Sound is shorter than the analysis needs (" + fixed$ (dur * 1000, 1) + " ms)."
else
    selectObject: snd
    ana = Copy: "sc_analysis"
    Subtract mean
    for k from 1 to nF
        lev[k] = floorDb
    endfor
    for ch from 1 to nCh
        selectObject: ana
        if nCh > 1
            chS = Extract one channel: ch
        else
            chS = ana
        endif
        for k from 1 to nF
            tc = xmin + hw + (k - 1) * stepS
            r = Get root-mean-square: tc - hw, tc + hw
            if r <> undefined and r > 0
                v = max (floorDb, 20 * log10 (r))
                if v > lev[k]
                    lev[k] = v
                endif
            endif
        endfor
        if chS <> ana
            removeObject: chS
        endif
    endfor
    removeObject: ana

    # percentiles from a 0.5 dB histogram (no sorting needed)
    nBin = 340
    for b from 1 to nBin
        hist[b] = 0
    endfor
    nAct = 0
    for k from 1 to nF
        if lev[k] > floorDb + 1
            b = max (1, min (nBin, floor ((lev[k] - floorDb) / 0.5) + 1))
            hist[b] = hist[b] + 1
            nAct = nAct + 1
        endif
    endfor
    if nAct = 0
        status$ = "Only digital silence remains after removing the DC offset: no phrases to separate."
    else
        # the 10th percentile counts the digitally silent frames too
        nAll = nF
        cum = nF - nAct
        flDb = floorDb
        actDb = floorDb
        got10 = cum >= 0.10 * nAll
        if got10
            flDb = floorDb
        endif
        cumA = 0
        got95 = 0
        for b from 1 to nBin
            cum = cum + hist[b]
            cumA = cumA + hist[b]
            if not got10 and cum >= 0.10 * nAll
                flDb = floorDb + (b - 0.5) * 0.5
                got10 = 1
            endif
            if not got95 and cumA >= 0.95 * nAct
                actDb = floorDb + (b - 0.5) * 0.5
                got95 = 1
            endif
        endfor
        thr = max (actDb - 45, flDb + 8)
        if thr > actDb - 24
            status$ = "The level never falls far enough below the active level (active " + fixed$ (actDb, 1)
                ... + " dBFS, floor " + fixed$ (flDb, 1) + " dBFS): no reliable quiet gaps."
        endif
    endif
endif

if status$ = ""
    # quiet runs
    minGapF = ceiling ((minimum_natural_gap_ms / 1000) / stepS)
    k = 1
    while k <= nF
        if lev[k] < thr
            ka = k
            while k <= nF and lev[k] < thr
                k = k + 1
            endwhile
            kb = k - 1
            if kb - ka + 1 >= minGapF
                nQuiet = nQuiet + 1
                qa[nQuiet] = ka
                qb[nQuiet] = kb
                qT1[nQuiet] = xmin + hw + (ka - 1) * stepS - stepS / 2
                qT2[nQuiet] = xmin + hw + (kb - 1) * stepS + stepS / 2
                qState$[nQuiet] = ""
            endif
        else
            k = k + 1
        endif
    endwhile

    # one safety-checked boundary per region
    lookF = round (0.600 / stepS)
    for q from 1 to nQuiet
        if qa[q] = 1 or qb[q] = nF
            qState$[q] = "edge"
            nEdge = nEdge + 1
        else
            # contrast on both sides
            mb = floorDb
            for k from max (1, qa[q] - lookF) to qa[q] - 1
                mb = max (mb, lev[k])
            endfor
            ma = floorDb
            for k from qb[q] + 1 to min (nF, qb[q] + lookF)
                ma = max (ma, lev[k])
            endfor
            qBefore[q] = mb
            qAfter[q] = ma
            mLev = 0
            qMin[q] = lev[qa[q]]
            for k from qa[q] to qb[q]
                mLev = mLev + lev[k]
                qMin[q] = min (qMin[q], lev[k])
            endfor
            qMean[q] = mLev / (qb[q] - qa[q] + 1)
            if mb < thr + 12 or ma < thr + 12
                qState$[q] = "contrast"
                nRejContrast = nRejContrast + 1
            else
                # click-safe sample pair: central half first, then the safe interior
                qd = qT2[q] - qT1[q]
                marg = max (0.030, 0.15 * qd)
                bestI = 0
                for pass from 1 to 2
                    if bestI = 0
                        if pass = 1
                            sa = qT1[q] + 0.25 * qd
                            sb = qT2[q] - 0.25 * qd
                        else
                            sa = qT1[q] + marg
                            sb = qT2[q] - marg
                        endif
                        if sb - sa > 4 * dx
                            selectObject: snd
                            part = Extract part: sa, sb, "rectangular", 1, "yes"
                            pn = Get number of samples
                            pe = Copy: "sc_pairmax"
                            pexpr$ = ""
                            for ch from 1 to nCh
                                term$ = "max (abs (object[" + string$ (part) + ", " + string$ (ch) + ", col]), abs (object["
                                    ... + string$ (part) + ", " + string$ (ch) + ", min (col + 1, " + string$ (pn) + ")]))"
                                if ch = 1
                                    pexpr$ = term$
                                else
                                    pexpr$ = "max (" + pexpr$ + ", " + term$ + ")"
                                endif
                            endfor
                            Formula: pexpr$
                            # the last column pairs with a sample outside the part: never chosen
                            for ch from 1 to nCh
                                Set value at sample number: ch, pn, 1
                            endfor
                            pmin = Get minimum: 0, 0, "None"
                            tmin = Get time of minimum: 0, 0, "None"
                            plast = Get time from sample number: pn
                            removeObject: part, pe
                            if pmin <> undefined and pmin <= clickTol and tmin < plast
                                bestI = round ((tmin - x1) / dx) + 1
                                qJump[q] = pmin
                            endif
                        endif
                    endif
                endfor
                if bestI > 0 and bestI < nSamp
                    qState$[q] = "eligible"
                    nElig = nElig + 1
                    eQ[nElig] = q
                    eI[nElig] = bestI
                    eT[nElig] = xmin + bestI * dx
                else
                    qState$[q] = "click"
                    nRejClick = nRejClick + 1
                endif
            endif
        endif
    endfor
    if nElig = 0
        status$ = "No sufficiently safe phrase boundaries were detected."
    endif
endif

# ============================================================
# 5. STOCHASTIC CHOICE (in time order)
# ============================================================
random_initializeWithSeedUnsafelyButPredictably (usedSeed)
nSel = 0
nSkipSep = 0
lastSelT = -1e30
for ei from 1 to nElig
    u = randomUniform (0, 1)
    eSel[ei] = 0
    if u < pause_density_percent / 100
        if eT[ei] - lastSelT >= minimum_pause_separation_s
            nSel = nSel + 1
            eSel[ei] = 1
            sI[nSel] = eI[ei]
            sT[nSel] = eT[ei]
            dMs = randomUniform (pMinMs, pMaxMs)
            sN[nSel] = max (1, round (dMs / 1000 * fs))
            lastSelT = eT[ei]
        else
            nSkipSep = nSkipSep + 1
        endif
    endif
endfor
random_initializeSafelyAndUnpredictably ()
if status$ = "" and nSel = 0
    status$ = "No boundary was selected (density " + fixed$ (pause_density_percent, 1) + "%): nothing to insert."
endif

# ============================================================
# 6. RECONSTRUCTION (one output, copied by sample index)
# ============================================================
out = 0
addN = 0
for j from 1 to nSel
    addN = addN + sN[j]
endfor
outN = nSamp + addN
outName$ = ""
if nSel > 0
    # collision-safe name
    select all
    nObj = numberOfSelected ()
    for i from 1 to nObj
        objName$[i] = selected$ (i)
    endfor
    outName$ = "Stochastic_Caesura"
    kName = 1
    clash = 1
    while clash
        clash = 0
        for i from 1 to nObj
            if objName$[i] = "Sound " + outName$
                clash = 1
            endif
        endfor
        if clash
            kName = kName + 1
            outName$ = "Stochastic_Caesura_" + string$ (kName)
        endif
    endwhile
    out = Create Sound from formula: outName$, nCh, xmin, xmin + outN * dx, fs, "0"
    gotN = Get number of samples
    if gotN <> outN
        removeObject: out
        exitScript: "Internal error: output has " + string$ (gotN) + " samples instead of " + string$ (outN) + "."
    endif
    # segment j runs from sample segA to segB of the original, shifted by segSh
    sh = 0
    a = 1
    for j from 1 to nSel + 1
        if j <= nSel
            b = sI[j]
        else
            b = nSamp
        endif
        segA[j] = a
        segB[j] = b
        segSh[j] = sh
        c1 = a + sh
        c2 = b + sh
        Formula (part): xmin + (c1 - 0.75) * dx, xmin + (c2 - 0.25) * dx, 1, nCh,
            ... "object[" + string$ (snd) + ", row, col - " + string$ (sh) + "]"
        if j <= nSel
            insStart[j] = b + sh + 1
            sh = sh + sN[j]
            a = b + 1
        endif
    endfor

    # ---------------- verification ----------------
    selectObject: out
    vN = Get number of samples
    vFs = Get sampling frequency
    vCh = Get number of channels
    vPeak = Get absolute extremum: 0, 0, "None"
    chk = Copy: "sc_check"
    for j from 1 to nSel + 1
        c1 = segA[j] + segSh[j]
        c2 = segB[j] + segSh[j]
        Formula (part): xmin + (c1 - 0.75) * dx, xmin + (c2 - 0.25) * dx, 1, nCh,
            ... "self - object[" + string$ (snd) + ", row, col - " + string$ (segSh[j]) + "]"
    endfor
    # after subtracting every mapped original sample, the whole check
    # Sound must be zero: original values, order and positions are
    # right AND the inserted spans are exact zeros
    vDiff = Get absolute extremum: 0, 0, "None"
    zeroMax = 0
    for j from 1 to nSel
        zx = Get absolute extremum: xmin + (insStart[j] - 0.75) * dx, xmin + (insStart[j] + sN[j] - 1.25) * dx, "None"
        if zx <> undefined
            zeroMax = max (zeroMax, abs (zx))
        endif
    endfor
    removeObject: chk
    # largest step into or out of an inserted silence
    jumpMax = 0
    selectObject: snd
    for j from 1 to nSel
        for ch from 1 to nCh
            va = Get value at sample number: ch, sI[j]
            vb = Get value at sample number: ch, sI[j] + 1
            jumpMax = max (jumpMax, max (abs (va), abs (vb)))
        endfor
    endfor
    passCount = vN = outN
    passRate = vFs = fs
    passCh = vCh = nCh
    passSamples = vDiff = 0
    passZero = zeroMax = 0
    passPeak = vPeak = peak
    selectObject: snd
    peakAfter = Get absolute extremum: 0, 0, "None"
    rmsAfter = Get root-mean-square: 0, 0
    nAfter = Get number of samples
    passOrig = peakAfter = peak and rmsAfter = srcRms and nAfter = nSamp
endif

# realized statistics
pMin = 0
pMax = 0
pSum = 0
for j from 1 to nSel
    pd = sN[j] / fs
    if j = 1
        pMin = pd
        pMax = pd
    endif
    pMin = min (pMin, pd)
    pMax = max (pMax, pd)
    pSum = pSum + pd
endfor
addS = addN * dx
finalDur = dur + addS

# ============================================================
# VISUALIZATION (from the actual analysis and schedule)
# ============================================================
if show_visualization
    appendInfoLine: "Drawing visualization..."
    colBlue$ = "{0.20,0.40,0.75}"
    colOr$ = "{0.90,0.50,0.10}"
    colQuiet$ = "{0.88,0.88,0.90}"
    colIns$ = "{0.99,0.89,0.76}"
    colWave$ = "{0.25,0.25,0.30}"

    procedure scStep: .range, .target
        .raw = .range / .target
        .mag = 10 ^ floor (log10 (max (1e-12, .raw)))
        .n = .raw / .mag
        if .n < 1.5
            .step = .mag
        elsif .n < 3.5
            .step = 2 * .mag
        elsif .n < 7.5
            .step = 5 * .mag
        else
            .step = 10 * .mag
        endif
    endproc

    Erase all
    Line width: 1
    Solid line
    yr = max (peak, 1e-6) * 1.08

    # ---------------- Suite header ----------------
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Stochastic Caesura v1.0##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    nameShow$ = replace$ (sndName$, "_", "\_ ", 0)
    Text: 0.5, "centre", 0.22, "half", nameShow$ + " | " + modeName$ + " " + fixed$ (pMinMs, 0) + "-" + fixed$ (pMaxMs, 0)
        ... + " ms | density " + fixed$ (pause_density_percent, 0) + "\% | " + string$ (nElig) + " eligible, "
        ... + string$ (nSel) + " selected"

    # display copies (channel mean, display only)
    selectObject: snd
    if nCh > 1
        dispIn = Convert to mono
    else
        dispIn = Copy: "sc_display"
    endif

    # ========================================================
    # A  ORIGINAL SOUND AND DETECTED BOUNDARIES
    # ========================================================
    Font size: 9
    Select outer viewport: 0.18, 7.82, 0.62, 0.88
    Select inner viewport: 0.18, 7.82, 0.62, 0.88
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.01, "left", 0.72, "half", "A  ORIGINAL SOUND AND DETECTED BOUNDARIES"
    Font size: 6
    Colour: "{0.34,0.38,0.48}"
    Text: 0.01, "left", 0.18, "half", "grey = quiet regions | blue ticks = eligible boundaries | orange = selected insertions"
        ... + " | dotted = rejected (contrast or click risk) | strip: frame level (dBFS, loudest channel) and threshold"
    Select outer viewport: 0.18, 7.82, 0.89, 2.45
    Select inner viewport: 0.60, 7.70, 1.00, 1.90
    Axes: xmin, xmax, -yr, yr
    for q from 1 to nQuiet
        Paint rectangle: colQuiet$, qT1[q], qT2[q], -yr, yr
    endfor
    selectObject: dispIn
    Colour: colWave$
    Draw: xmin, xmax, -yr, yr, "no", "Curve"
    Select inner viewport: 0.60, 7.70, 1.00, 1.90
    Axes: xmin, xmax, -yr, yr
    for q from 1 to nQuiet
        if qState$[q] = "contrast" or qState$[q] = "click"
            Colour: "{0.55,0.55,0.60}"
            Dotted line
            Draw line: (qT1[q] + qT2[q]) / 2, -yr, (qT1[q] + qT2[q]) / 2, yr
            Solid line
        endif
    endfor
    mw = if nElig > 80 then 1 else 2 fi
    for ei from 1 to nElig
        Colour: colBlue$
        Line width: mw
        Draw line: eT[ei], 0.78 * yr, eT[ei], yr
        Draw line: eT[ei], -yr, eT[ei], -0.78 * yr
        Line width: 1
        if eSel[ei]
            Colour: colOr$
            Line width: mw
            Draw line: eT[ei], -0.78 * yr, eT[ei], 0.78 * yr
            Line width: 1
        endif
    endfor
    Colour: "Black"
    Draw inner box
    Font size: 6
    @scStep: yr, 2
    Marks left every: 1, scStep.step, "yes", "yes", "no"
    # level strip
    Select inner viewport: 0.60, 7.70, 1.98, 2.36
    if nF >= 3 and actDb <> undefined
        lTop = actDb + 6
        lBot = max (floorDb, min (flDb, thr) - 10)
        Axes: xmin, xmax, lBot, lTop
        Paint rectangle: "{0.97,0.97,0.97}", xmin, xmax, lBot, lTop
        bucket = max (1, ceiling (nF / 1500))
        Colour: "{0.35,0.35,0.42}"
        prevX = undefined
        k = 1
        while k <= nF
            mx = floorDb
            for kk from k to min (nF, k + bucket - 1)
                mx = max (mx, lev[kk])
            endfor
            px = xmin + hw + (k - 1 + (bucket - 1) / 2) * stepS
            py = max (lBot, min (lTop, mx))
            if prevX <> undefined
                Draw line: prevX, prevY, px, py
            endif
            prevX = px
            prevY = py
            k = k + bucket
        endwhile
        Colour: "{0.80,0.25,0.20}"
        Dashed line
        Draw line: xmin, thr, xmax, thr
        Solid line
        Colour: "Black"
        Draw inner box
        Font size: 6
        Text left: "no", "dBFS"
        One mark right: thr, "no", "yes", "no", "thr " + fixed$ (thr, 0)
    else
        Axes: 0, 1, 0, 1
        Colour: "Black"
        Draw inner box
        Font size: 6
        Text: 0.5, "centre", 0.5, "half", "no level analysis (silent or too short)"
    endif

    # ========================================================
    # B  STOCHASTIC PAUSE MAP
    # ========================================================
    Font size: 9
    Select outer viewport: 0.18, 7.82, 2.56, 2.82
    Select inner viewport: 0.18, 7.82, 2.56, 2.82
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.01, "left", 0.72, "half", "B  STOCHASTIC PAUSE MAP - added silence per selected boundary (original time axis)"
    Font size: 6
    Colour: "{0.34,0.38,0.48}"
    Text: 0.01, "left", 0.18, "half", "bar height = inserted pause (s) | blue dots = eligible but not chosen | "
        ... + string$ (nSel) + " pause(s), " + modeName$
    Select outer viewport: 0.18, 7.82, 2.83, 3.80
    Select inner viewport: 0.60, 7.70, 2.90, 3.62
    bTop = max (pMaxMs / 1000, pMax) * 1.15
    Axes: xmin, xmax, 0, bTop
    Paint rectangle: "White", xmin, xmax, 0, bTop
    bw = max (dur / 400, dx)
    for j from 1 to nSel
        Paint rectangle: colOr$, sT[j] - bw, sT[j] + bw, 0, sN[j] / fs
    endfor
    for ei from 1 to nElig
        if not eSel[ei]
            Paint circle (mm): colBlue$, eT[ei], bTop * 0.04, 0.6
        endif
    endfor
    Colour: "{0.55,0.55,0.60}"
    Dotted line
    Draw line: xmin, pMinMs / 1000, xmax, pMinMs / 1000
    Draw line: xmin, pMaxMs / 1000, xmax, pMaxMs / 1000
    Solid line
    if nSel = 0
        Colour: "{0.45,0.45,0.55}"
        Font size: 8
        Text: (xmin + xmax) / 2, "centre", bTop / 2, "half", if nElig = 0 then "no safe boundary - nothing inserted" else "no boundary selected - nothing inserted" fi
    endif
    Colour: "Black"
    Draw inner box
    Font size: 6
    @scStep: bTop, 3
    Marks left every: 1, scStep.step, "yes", "yes", "no"
    Text left: "yes", "added (s)"

    # ========================================================
    # C  RECONSTRUCTED TEMPORAL FORM
    # ========================================================
    Font size: 9
    Select outer viewport: 0.18, 7.82, 3.84, 4.10
    Select inner viewport: 0.18, 7.82, 3.84, 4.10
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.01, "left", 0.72, "half", "C  RECONSTRUCTED TEMPORAL FORM - original " + fixed$ (dur, 2) + " s -> final "
        ... + fixed$ (finalDur, 2) + " s (+" + fixed$ (addS, 2) + " s of silence)"
    Font size: 6
    Colour: "{0.34,0.38,0.48}"
    Text: 0.01, "left", 0.18, "half", "the output Sound on its new time axis | orange = inserted digital silence | strip: original segments (blue) and added gaps (orange)"
    Select outer viewport: 0.18, 7.82, 4.11, 5.62
    Select inner viewport: 0.60, 7.70, 4.22, 5.06
    fEnd = xmin + finalDur
    Axes: xmin, fEnd, -yr, yr
    for j from 1 to nSel
        Paint rectangle: colIns$, xmin + (insStart[j] - 1) * dx, xmin + (insStart[j] - 1 + sN[j]) * dx, -yr, yr
    endfor
    if out > 0
        selectObject: out
        if nCh > 1
            dispOut = Convert to mono
        else
            dispOut = Copy: "sc_display_out"
        endif
        Colour: colWave$
        Draw: xmin, fEnd, -yr, yr, "no", "Curve"
        removeObject: dispOut
    else
        selectObject: dispIn
        Colour: colWave$
        Draw: xmin, fEnd, -yr, yr, "no", "Curve"
    endif
    Select inner viewport: 0.60, 7.70, 4.22, 5.06
    Axes: xmin, fEnd, -yr, yr
    Colour: "Black"
    Draw inner box
    Font size: 6
    @scStep: yr, 2
    Marks left every: 1, scStep.step, "yes", "yes", "no"
    Select inner viewport: 0.60, 7.70, 5.12, 5.28
    Axes: xmin, fEnd, 0, 1
    if out > 0
        for j from 1 to nSel + 1
            Paint rectangle: if j mod 2 = 1 then colBlue$ else "{0.42,0.60,0.86}" fi, xmin + (segA[j] + segSh[j] - 1) * dx,
                ... xmin + (segB[j] + segSh[j]) * dx, 0, 1
            if j <= nSel
                Paint rectangle: colOr$, xmin + (insStart[j] - 1) * dx, xmin + (insStart[j] - 1 + sN[j]) * dx, 0, 1
            endif
        endfor
    else
        Paint rectangle: colBlue$, xmin, fEnd, 0, 1
    endif
    Colour: "Black"
    Draw inner box
    Font size: 6
    @scStep: finalDur, 10
    Marks bottom every: 1, scStep.step, "yes", "yes", "no"
    Text bottom: "yes", "time in the result (s)"
    removeObject: dispIn

    # ---------------- Bottom summary ----------------
    Select outer viewport: 0.18, 7.82, 5.86, 6.37
    Select inner viewport: 0.18, 7.82, 5.86, 6.37
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text: 0.02, "left", 0.67, "half", "ORIGINAL " + fixed$ (dur, 3) + " s   ->   FINAL " + fixed$ (finalDur, 3) + " s   |   added "
        ... + fixed$ (addS, 3) + " s in " + string$ (nSel) + " pause(s)   |   " + string$ (nElig) + " eligible boundaries of "
        ... + string$ (nQuiet) + " quiet regions"
    Colour: "{0.34,0.38,0.48}"
    Text: 0.02, "left", 0.24, "half", modeName$ + " | density " + fixed$ (pause_density_percent, 0) + "\%  | min gap "
        ... + fixed$ (minimum_natural_gap_ms, 0) + " ms | separation " + fixed$ (minimum_pause_separation_s, 2) + " s | seed "
        ... + string$ (usedSeed) + (if thr <> undefined then " | threshold " + fixed$ (thr, 1) + " dBFS" else "" fi)
    Select outer viewport: 0, 8, 0, 6.47
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# ============================================================
# REPORT
# ============================================================
appendInfoLine: ""
appendInfoLine: "=== STOCHASTIC CAESURA — PHRASE-AWARE SILENCE INSERTION ==="
appendInfoLine: ""
appendInfoLine: "SOURCE"
appendInfoLine: "  Sound ", sndName$, " | ", fixed$ (dur, 4), " s | ", nSamp, " samples | ", fs, " Hz | ", nCh,
    ... " channel(s) | peak ", fixed$ (peak, 6), if peak > 0 then " (" + fixed$ (20 * log10 (peak), 2) + " dBFS)" else "" fi
dcMax = 0
for ch from 1 to nCh
    dcMax = max (dcMax, abs (dcCh[ch]))
endfor
if dcMax > 0.001
    appendInfoLine: "  DC offset up to ", fixed$ (dcMax, 4), " (removed for the level analysis only; it also means the pauses",
        ... " contain no near-zero samples, so a jump to digital zero there would click)"
endif
appendInfoLine: ""
appendInfoLine: "BOUNDARY ANALYSIS"
appendInfoLine: "  RMS frames: 25 ms window, 5 ms step, per channel (loudest channel counts), DC removed, in dBFS"
if thr <> undefined
    appendInfoLine: "  Active level (95th pct) ", fixed$ (actDb, 1), " dBFS | floor (10th pct) ", fixed$ (flDb, 1),
        ... " dBFS | threshold ", fixed$ (thr, 1), " dBFS"
endif
appendInfoLine: "  Minimum natural gap ", fixed$ (minimum_natural_gap_ms, 0), " ms | click tolerance ",
    ... if clickTol > 0 then fixed$ (20 * log10 (clickTol), 1) + " dBFS" else "n/a" fi, " (both neighbours of the insertion point, every channel)"
appendInfoLine: "  Quiet regions: ", nQuiet, " (", nEdge, " at the start/end, ignored) | eligible boundaries: ", nElig,
    ... " | rejected: ", nRejContrast + nRejClick, " (", nRejContrast, " weak contrast, ", nRejClick, " no click-safe sample)"
if status$ <> ""
    appendInfoLine: "  ", status$
endif
appendInfoLine: "  Detection is acoustic: it approximates phrase boundaries and does not understand language or musical syntax."
appendInfoLine: ""
appendInfoLine: "STOCHASTIC PROCESS"
appendInfoLine: "  Mode ", modeName$, " (", fixed$ (pMinMs, 0), "-", fixed$ (pMaxMs, 0), " ms, uniform) | density ",
    ... fixed$ (pause_density_percent, 1), "% | separation ", fixed$ (minimum_pause_separation_s, 3), " s | seed ", seedNote$
appendInfoLine: "  Pauses inserted: ", nSel, " of ", nElig, " eligible", if nSkipSep > 0 then " (" + string$ (nSkipSep) + " drawn but too close to the previous pause)" else "" fi
if nSel > 0
    appendInfoLine: "  Pause length: min ", fixed$ (pMin * 1000, 1), " ms | max ", fixed$ (pMax * 1000, 1), " ms | mean ",
        ... fixed$ (pSum / nSel * 1000, 1), " ms"
endif
appendInfoLine: ""
appendInfoLine: "TEMPORAL RECONSTRUCTION"
appendInfoLine: "  Original ", fixed$ (dur, 4), " s + silence ", fixed$ (addS, 4), " s = final ", fixed$ (finalDur, 4),
    ... " s | expansion x", fixed$ (finalDur / dur, 4)
if out > 0
    appendInfoLine: "  Output: Sound ", outName$, " (", outN, " samples = ", nSamp, " + ", addN, ")"
    appendInfoLine: ""
    appendInfoLine: "VERIFICATION (measured on the result)"
    appendInfoLine: "  Original samples preserved (each value at its mapped position): ", if passSamples then "PASS" else "FAIL" fi,
        ... " (max difference ", fixed$ (vDiff, 12), ")"
    appendInfoLine: "  Original order preserved (segments in order, none lost or duplicated): ", if passSamples and passCount then "PASS" else "FAIL" fi
    appendInfoLine: "  Inserted spans are exact digital zero: ", if passZero then "PASS" else "FAIL" fi
    appendInfoLine: "  Channel count preserved: ", if passCh then "PASS" else "FAIL" fi
    appendInfoLine: "  Sample rate preserved: ", if passRate then "PASS" else "FAIL" fi
    appendInfoLine: "  Expected output sample count: ", if passCount then "PASS" else "FAIL" fi
    appendInfoLine: "  Peak preservation: ", if passPeak then "PASS" else "FAIL" fi, " (", fixed$ (vPeak, 6), ")"
    appendInfoLine: "  Original Sound unchanged: ", if passOrig then "PASS" else "FAIL" fi
    appendInfoLine: "  Largest step into or out of an inserted silence: ", fixed$ (jumpMax, 6),
        ... if jumpMax > 0 then " (" + fixed$ (20 * log10 (jumpMax), 1) + " dBFS)" else " (exact zero)" fi
    appendInfoLine: ""
    appendInfoLine: "INSERTIONS: index / original time / added silence / new position of the silence"
    nList = min (nSel, 60)
    for j from 1 to nList
        appendInfoLine: "  ", j, " / ", fixed$ (sT[j], 4), " s / ", fixed$ (sN[j] / fs * 1000, 1), " ms / ",
            ... fixed$ (xmin + (insStart[j] - 1) * dx, 4), " s"
    endfor
    if nSel > nList
        appendInfoLine: "  ... ", nSel - nList, " more"
    endif
else
    appendInfoLine: "  No output created: the original Sound is left as it is."
endif

if out > 0
    selectObject: out
    if play_result
        Play
    endif
else
    selectObject: snd
endif
