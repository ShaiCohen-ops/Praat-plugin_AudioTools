# ============================================================
# Praat AudioTools - Gestural_Counterpoint.praat
# Gestural Counterpoint
# Cross-corpus amplitude-envelope matching for two voices
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.2 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# WHAT THIS DOES
#   Builds a two-voice stereo composition from two folders of
#   recordings. Every sounding gesture of both corpora is described by
#   ONE feature only - the shape of its amplitude envelope - and each
#   chosen gesture of Corpus A is paired with the Corpus B gesture
#   whose dynamic shape (attack, growth, fluctuation, decay) is
#   closest, whatever its pitch, timbre or origin. The pairs are then
#   placed in time as two independent lines:
#     Voice A = gestures from Corpus A
#     Voice B = their dynamic counterparts from Corpus B
#   and the two finished voices are mixed into one stereo Sound, each
#   at its own equal-power pan position (default A -65, B +65), with
#   Voice B optionally level-matched to Voice A.
#   The gestures themselves are never transformed: no time stretch,
#   pitch shift, filter, reversal or resynthesis, and no per-gesture
#   gain. They are only selected, extracted whole and repositioned.
#
# PIPELINE
#   1. Scan. Both folders are listed (top level only, sorted by name).
#      Accepted: .wav .wave .aif .aiff .aifc .flac (any letter case).
#      Hidden files (names starting with ".") are skipped. Each file is
#      read, analysed and released before the next one is read.
#   2. Gestures. Praat's To TextGrid (silences), with the threshold in
#      dB below each file's maximum intensity and a 100 Hz intensity
#      floor; every sounding interval of at least
#      Minimum_gesture_duration_s is one gesture, kept whole from its
#      onset to its decay. Boundaries are snapped to sample edges.
#      Files whose peak is below -80 dBFS are skipped as silent.
#   3. Envelope. 64 points per gesture, at equally spaced positions of
#      its OWN duration (time normalized to 0..1 for comparison only).
#      Each point is the linear RMS amplitude in a window of 1/64 of
#      the gesture, widened to at least 20 ms so low pitches do not
#      ripple. The vector is then divided by its own maximum (shape
#      only, independent of recording level).
#   4. Distance between gestures a (Corpus A) and b (Corpus B):
#        D_shape    = sqrt(mean((E_a[i] - E_b[i])^2))          0..1
#        D_duration = min(1, |ln(dur_a / dur_b)| / ln 4)        0..1
#                     (a factor-4 length difference counts as 1)
#        D_total    = (1 - w) * D_shape + w * D_duration
#      Shape Only uses w = 0. Both terms live on 0..1, so w is the share
#      of the cost given to duration (default 0.20).
#   5. Pairing. Number_of_pairs gestures of Corpus A are taken evenly
#      spread over the whole corpus, in corpus order (file name, then
#      time). For each, all Corpus B gestures are ranked and the best
#      Candidates_per_gesture are kept:
#        Best Match - the lowest cost; among candidates within 10% (at
#          least 0.01) of it, a less-used gesture is preferred, so
#          reuse is avoided only when quality is comparable;
#        Random Among Top Matches - a random choice among the least-
#          used of the top candidates.
#      A pair whose D_shape exceeds 0.15 is reported as a weak match.
#   6. Time. Pair k begins at T_k; Voice A enters at T_k, Voice B at
#      T_k + offset_k:
#        Synchronous     - offset 0;
#        Fixed Offset    - Fixed_offset_ms (positive = B later);
#        Variable Offset - uniform in +/- Maximum_offset_ms per pair.
#      Without within-voice overlap, T_k is the earliest time at which
#      neither voice overlaps its own previous gesture, plus
#      Inter_pair_gap_ms. With overlap allowed, the next pair may enter
#      once both previous gestures are half over (plus the gap). If a
#      negative offset places audio before 0, the whole timeline is
#      shifted later; nothing is cut. Both voices may overlap freely.
#   7. Assembly. Each file is read once more and only the gestures it
#      contributes are copied by sample index into the voice buffers
#      (stereo files: mean of the channels, as Convert to mono). The
#      only amplitude change is an optional raised-cosine edge fade of
#      Edge_fade_ms at each gesture boundary (0 = none). This gives two
#      complete mono voices.
#   5b. Formal organization (Formal_order; Original = unchanged order).
#      Each gesture's linear RMS over its whole sounding interval is
#      measured during step 2. Per corpus it is converted to dB and
#      scaled to 0..1 between that corpus's 10th and 90th percentile
#      (values outside are clipped; a corpus spanning less than 1 dB
#      gets 0.5 throughout), so outliers and recording level do not
#      set the scale. Pair energy = 0.5 * A + 0.5 * B: both corpora
#      weigh equally. The complete pairs (A gesture, B gesture and all
#      their matching data) are then permuted - never split, re-matched,
#      duplicated or dropped:
#        Ascending / Descending - stable sort by pair energy;
#        Arch - pairs ranked by energy are assigned to positions ranked
#          by an asymmetric target curve (Emergence - Growth - Climax at
#          70% of the PAIR SEQUENCE - Release) with a small fixed ripple
#          so that pairs of similar energy may trade places; the
#          strongest pair always takes the climax position.
#      No random numbers are drawn here, so selection and offsets are
#      unaffected. Form is defined over pair positions, not over equal
#      shares of clock time: long pairs simply take longer. Gain is
#      never used to create the form; if the selected pairs span little
#      energy, the report says that the trajectory is weakly audible.
#   8. Final mix (the only new gain stage; nothing earlier changes):
#        Level  - RMS of each voice over its ACTIVE region only: the
#                 union of the intervals its gestures occupy (overlaps
#                 counted once, the summed signal measured as it is),
#                 so timeline gaps do not bias the comparison. With
#                 Match_voice_levels, Voice B gets gain RMS_A / RMS_B
#                 (limited to +/-24 dB, reported); Voice_B_balance_dB
#                 (limited to +/-24 dB) is then applied on top. Voice A
#                 keeps gain 1. One gain per voice for its whole length.
#        Pan    - equal power, p in -100..+100:
#                 theta = (p + 100) / 200 * pi / 2,
#                 L = cos(theta), R = sin(theta) (exactly 1/0 at -100,
#                 0/1 at +100).
#        Mix    - L = gA*A*LA + gB*B*LB,  R = gA*A*RA + gB*B*RB.
#        Peak   - if the stereo peak exceeds -1 dBFS, ONE common gain
#                 brings it to -1 dBFS (never a boost; no limiting).
#      Every output sample is then checked against this formula.
#
# SAMPLING-RATE POLICY
#   The output rate is the most common rate among the usable files
#   (ties: the higher). A gesture from a file at another rate is
#   resampled to it (Praat's Resample, precision 50): duration and
#   pitch are kept; the number of such gestures is reported.
#
# GUARANTEES (checked by the script and reported)
#   - Every gesture keeps its full length (same samples, or the same
#     duration after resampling); nothing is truncated; the output ends
#     where the last gesture of either voice ends.
#   - 2 channels; every sample equals the mix formula of step 8.
#   - Amplitude changes are only: the optional edge fades, one gain for
#     Voice B (level matching and balance), the pan coefficients and
#     one common peak-ceiling gain. No per-gesture normalization, no
#     compression or limiting: dynamics within each voice are kept.
#   - Match_voice_levels 0, Voice_B_balance_dB 0, pans -100 / +100
#     reproduce v1.0's hard-panned output whenever its peak stays
#     below -1 dBFS.
#   - Source files are only read; only the stereo result remains.
#
# METHOD NOTES / LIMITS
#   - Needs Praat 6.2 or newer (folder fields, vector functions).
#   - Envelope shape only: no pitch, spectrum or timbre is measured.
#   - Matching is point-by-point on normalized time (no DTW): two
#     gestures whose events are shifted in time count as different.
#   - Gestures are as long as the silences allow: a continuously
#     sounding recording is ONE gesture.
#
# ============================================================

# Changelog v1.2 (2026):
#   - Formal_order: Original (default, = v1.1) | Arch | Ascending |
#     Descending - permutation of the complete pairs by a per-corpus
#     relative RMS energy, before scheduling. Report section FORMAL
#     ORGANIZATION; energy strip under the matching map.
# Changelog v1.1 (2026):
#   - Final mix stage: active-region RMS level matching of Voice B to
#     Voice A, manual Voice B balance, independent equal-power pan for
#     each voice, common -1 dBFS peak ceiling (replaces the 0.99
#     within-voice-overlap safety gain). Matching, scheduling and
#     placement unchanged.
# Changelog v1.0 (2026):
#   - Initial release.
#
form Gestural Counterpoint v1.2
    comment Two corpora paired by the shape of their amplitude envelopes
    folder Corpus_A_folder
    folder Corpus_B_folder
    optionmenu Matching_mode: 2
        option Shape Only
        option Shape + Duration
    real Duration_weight 0.20
    optionmenu Selection_strategy: 1
        option Best Match
        option Random Among Top Matches
    optionmenu Temporal_mode: 1
        option Synchronous
        option Fixed Offset
        option Variable Offset
    real Fixed_offset_ms 250.0
    real Maximum_offset_ms 500.0
    natural Number_of_pairs 12
    optionmenu Formal_order: 1
        option Original
        option Arch
        option Ascending
        option Descending
    boolean Match_voice_levels 1
    real Voice_B_balance_dB 0.0
    real Voice_A_pan -65.0
    real Voice_B_pan 65.0
    integer Random_seed 0
    boolean Advanced_settings 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---------------- Advanced settings (second dialog) ----------------
silence_threshold_dB = 25.0
minimum_silence_duration_s = 0.15
minimum_gesture_duration_s = 0.10
candidates_per_gesture = 5
inter_pair_gap_ms = 100.0
allow_within_voice_overlap = 0
edge_fade_ms = 5.0
if advanced_settings
    beginPause: "Gestural Counterpoint - advanced settings"
        comment: "Gesture detection"
        positive: "Silence threshold dB", silence_threshold_dB
        positive: "Minimum silence duration s", minimum_silence_duration_s
        positive: "Minimum gesture duration s", minimum_gesture_duration_s
        comment: "Pairing and scheduling"
        natural: "Candidates per gesture", candidates_per_gesture
        real: "Inter pair gap ms", inter_pair_gap_ms
        boolean: "Allow within voice overlap", allow_within_voice_overlap
        real: "Edge fade ms", edge_fade_ms
    clicked = endPause: "Cancel", "OK", 2, 1
    if clicked = 1
        exitScript: "Cancelled."
    endif
endif

# ---------------- Parameter checks ----------------
warnLines$ = ""
minPitch = 100
nEnv = 64
weakShape = 0.15
silentPeak = 0.0001
if duration_weight < 0 or duration_weight > 1
    duration_weight = max(0, min(1, duration_weight))
    warnLines$ = warnLines$ + "  ! Duration_weight limited to 0..1 -> " + fixed$(duration_weight, 2) + "." + newline$
endif
if inter_pair_gap_ms < 0
    inter_pair_gap_ms = 0
    warnLines$ = warnLines$ + "  ! Inter_pair_gap_ms < 0 -> 0." + newline$
endif
if edge_fade_ms < 0
    edge_fade_ms = 0
    warnLines$ = warnLines$ + "  ! Edge_fade_ms < 0 -> 0 (no fades)." + newline$
endif
if voice_B_balance_dB < -24 or voice_B_balance_dB > 24
    voice_B_balance_dB = max(-24, min(24, voice_B_balance_dB))
    warnLines$ = warnLines$ + "  ! Voice_B_balance_dB limited to +/-24 dB -> " + fixed$(voice_B_balance_dB, 1) + " dB." + newline$
endif
if voice_A_pan < -100 or voice_A_pan > 100
    voice_A_pan = max(-100, min(100, voice_A_pan))
    warnLines$ = warnLines$ + "  ! Voice_A_pan limited to -100..+100 -> " + fixed$(voice_A_pan, 1) + "." + newline$
endif
if voice_B_pan < -100 or voice_B_pan > 100
    voice_B_pan = max(-100, min(100, voice_B_pan))
    warnLines$ = warnLines$ + "  ! Voice_B_pan limited to -100..+100 -> " + fixed$(voice_B_pan, 1) + "." + newline$
endif
if maximum_offset_ms < 0
    maximum_offset_ms = abs(maximum_offset_ms)
endif
corpusA$ = corpus_A_folder$
corpusB$ = corpus_B_folder$
if corpusA$ = "" or corpusB$ = ""
    exitScript: "Please choose both Corpus_A_folder and Corpus_B_folder."
endif
if right$(corpusA$, 1) = "/" or right$(corpusA$, 1) = "\"
    corpusA$ = left$(corpusA$, length(corpusA$) - 1)
endif
if right$(corpusB$, 1) = "/" or right$(corpusB$, 1) = "\"
    corpusB$ = left$(corpusB$, length(corpusB$) - 1)
endif
if corpusA$ = corpusB$
    warnLines$ = warnLines$ + "  ! Both corpora are the same folder: gestures may be paired with themselves." + newline$
endif
modeName$ = if matching_mode = 1 then "Shape Only" else "Shape + Duration" fi
stratName$ = if selection_strategy = 1 then "Best Match" else "Random Among Top Matches" fi
if temporal_mode = 1
    timeName$ = "Synchronous"
elsif temporal_mode = 2
    timeName$ = "Fixed Offset " + fixed$(fixed_offset_ms, 0) + " ms"
else
    timeName$ = "Variable Offset +/-" + fixed$(maximum_offset_ms, 0) + " ms"
endif

clearinfo
appendInfoLine: "Gestural Counterpoint v1.0 - scanning corpora..."

# ============================================================
# 1. SCAN: list the supported files of both folders
# ============================================================
procedure gcLower: .s$
    .out$ = .s$
    .up$ = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    .lo$ = "abcdefghijklmnopqrstuvwxyz"
    for .i from 1 to 26
        .out$ = replace$(.out$, mid$(.up$, .i, 1), mid$(.lo$, .i, 1), 0)
    endfor
endproc

nFile = 0
for c from 1 to 2
    dir$ = if c = 1 then corpusA$ else corpusB$ fi
    nListed[c] = 0
    nOther[c] = 0
    lst = Create Strings as file list: "gc_list", dir$ + "/*"
    Sort
    nStr = Get number of strings
    for i from 1 to nStr
        selectObject: lst
        name$ = Get string: i
        if left$(name$, 1) <> "."
            dot = rindex(name$, ".")
            ext$ = ""
            if dot > 0
                @gcLower: mid$(name$, dot + 1, length(name$) - dot)
                ext$ = gcLower.out$
            endif
            if index("|wav|wave|aif|aiff|aifc|flac|", "|" + ext$ + "|") > 0 and ext$ <> ""
                nFile = nFile + 1
                nListed[c] = nListed[c] + 1
                fName$[nFile] = name$
                fPath$[nFile] = dir$ + "/" + name$
                fCorpus[nFile] = c
                fStatus$[nFile] = ""
                fNg[nFile] = 0
            else
                nOther[c] = nOther[c] + 1
            endif
        endif
    endfor
    removeObject: lst
endfor
if nListed[1] = 0 or nListed[2] = 0
    exitScript: "No supported audio files (.wav .aif .aiff .aifc .flac) in "
        ... + (if nListed[1] = 0 then "Corpus A (" + corpusA$ + ")" else "Corpus B (" + corpusB$ + ")" fi) + "."
endif

# ============================================================
# 2-3. GESTURES AND ENVELOPES, one file at a time
# ============================================================
for c from 1 to 2
    nG[c] = 0
    nShort[c] = 0
    nSilentFile[c] = 0
    nBadFile[c] = 0
endfor
for f from 1 to nFile
    c = fCorpus[f]
    if f mod 50 = 0
        appendInfoLine: "  analysed ", f, " of ", nFile, " files..."
    endif
    # nocheck does not return the new object: a placeholder stays
    # selected when the file cannot be read
    marker = Create Sound from formula: "gc_marker", 1, 0, 0.001, 1000, "0"
    nocheck Read from file: fPath$[f]
    readOk = selected() <> marker
    snd = 0
    if readOk
        if numberOfSelected() = 1 and numberOfSelected("Sound") = 1
            snd = selected("Sound")
        else
            # something other than one Sound came out of the file
            nSel = numberOfSelected()
            for i from 1 to nSel
                rid[i] = selected(i)
            endfor
            for i from 1 to nSel
                removeObject: rid[i]
            endfor
        endif
    endif
    removeObject: marker
    if not readOk
        fStatus$[f] = "unreadable"
        nBadFile[c] = nBadFile[c] + 1
    elsif snd = 0
        fStatus$[f] = "not a sound"
        nBadFile[c] = nBadFile[c] + 1
    else
        selectObject: snd
        fRate[f] = Get sampling frequency
        fCh[f] = Get number of channels
        fDur[f] = Get total duration
        fN = Get number of samples
        fx1 = Get time from sample number: 1
        fdx = 1 / fRate[f]
        peak = Get absolute extremum: 0, 0, "None"
        nSeg = 0
        if peak < silentPeak
            fStatus$[f] = "silent"
            nSilentFile[c] = nSilentFile[c] + 1
        elsif fDur[f] < 6.4 / minPitch
            # too short for the intensity analysis: the file is one gesture
            nSeg = 1
            segS[1] = 1
            segE[1] = fN
        else
            ichk = To Intensity: minPitch, 0, "yes"
            iMax = Get maximum: 0, 0, "Parabolic"
            iMin = Get minimum: 0, 0, "Parabolic"
            removeObject: ichk
            if iMax = undefined or iMin = undefined or iMax - iMin < silence_threshold_dB
                # no level contrast: the whole file sounds as one gesture
                nSeg = 1
                segS[1] = 1
                segE[1] = fN
            else
                selectObject: snd
                tg = To TextGrid (silences): minPitch, 0, -silence_threshold_dB,
                    ... minimum_silence_duration_s, 0.02, "silent", "sounding"
                nInt = Get number of intervals: 1
                for j from 1 to nInt
                    lab$ = Get label of interval: 1, j
                    if lab$ = "sounding"
                        t1 = Get start time of interval: 1, j
                        t2 = Get end time of interval: 1, j
                        e1 = max(0, min(fN, round((t1 - fx1) / fdx + 0.5)))
                        e2 = max(0, min(fN, round((t2 - fx1) / fdx + 0.5)))
                        if e2 > e1
                            nSeg = nSeg + 1
                            segS[nSeg] = e1 + 1
                            segE[nSeg] = e2
                        endif
                    endif
                endfor
                removeObject: tg
            endif
        endif
        for j from 1 to nSeg
            gd = (segE[j] - segS[j] + 1) * fdx
            if gd < minimum_gesture_duration_s
                nShort[c] = nShort[c] + 1
            else
                # 64-point linear RMS envelope over the gesture's own time span
                tb1 = fx1 + (segS[j] - 1.5) * fdx
                tb2 = fx1 + (segE[j] - 0.5) * fdx
                half = max(gd / (2 * nEnv), 0.010)
                selectObject: snd
                eMax = 0
                for i from 1 to nEnv
                    tc = tb1 + (i - 0.5) * gd / nEnv
                    wa = max(tb1, tc - half)
                    wb = min(tb2, tc + half)
                    v = Get root-mean-square: wa, wb
                    if v = undefined
                        v = 0
                    endif
                    tmpEnv[i] = v
                    eMax = max(eMax, v)
                endfor
                if eMax <= 1e-12
                    nShort[c] = nShort[c] + 1
                else
                    nG[c] = nG[c] + 1
                    g = nG[c]
                    gFile[c, g] = f
                    gS1[c, g] = segS[j]
                    gS2[c, g] = segE[j]
                    gDur[c, g] = gd
                    # linear RMS of the whole gesture (formal organization only)
                    selectObject: snd
                    gRms[c, g] = Get root-mean-square: tb1, tb2
                    gT1[c, g] = (segS[j] - 1) * fdx
                    gT2[c, g] = segE[j] * fdx
                    for i from 1 to nEnv
                        gEnv[c, g, i] = tmpEnv[i] / eMax
                    endfor
                    fNg[f] = fNg[f] + 1
                endif
            endif
        endfor
        if fStatus$[f] = ""
            fStatus$[f] = if fNg[f] > 0 then "ok" else "no gesture long enough" fi
        endif
        removeObject: snd
    endif
endfor
nA = nG[1]
nB = nG[2]
if nA = 0 or nB = 0
    c = if nA = 0 then 1 else 2 fi
    exitScript: "Corpus " + (if c = 1 then "A" else "B" fi) + " has no usable gesture: " + string$(nListed[c])
        ... + " audio file(s), " + string$(nSilentFile[c]) + " silent, " + string$(nBadFile[c]) + " unreadable, "
        ... + string$(nShort[c]) + " sounding region(s) shorter than " + fixed$(minimum_gesture_duration_s, 3)
        ... + " s. Lower Minimum_gesture_duration_s or Silence_threshold_dB (Advanced settings), or choose another folder."
endif

# envelope matrices (rows = gestures, 64 columns)
envA## = zero## (nA, nEnv)
envB## = zero## (nB, nEnv)
for g from 1 to nA
    for i from 1 to nEnv
        envA## [g, i] = gEnv[1, g, i]
    endfor
endfor
for g from 1 to nB
    for i from 1 to nEnv
        envB## [g, i] = gEnv[2, g, i]
    endfor
endfor

# ---------------- output sampling rate: most common usable rate ----------------
nRates = 0
for f from 1 to nFile
    if fNg[f] > 0
        found = 0
        for r from 1 to nRates
            if rateVal[r] = fRate[f]
                rateCnt[r] = rateCnt[r] + 1
                found = 1
            endif
        endfor
        if not found
            nRates = nRates + 1
            rateVal[nRates] = fRate[f]
            rateCnt[nRates] = 1
        endif
    endif
endfor
fs = rateVal[1]
bestCnt = rateCnt[1]
for r from 2 to nRates
    if rateCnt[r] > bestCnt or (rateCnt[r] = bestCnt and rateVal[r] > fs)
        fs = rateVal[r]
        bestCnt = rateCnt[r]
    endif
endfor

# ============================================================
# 4-5. MATCHING AND PAIRING
# ============================================================
needRandom = selection_strategy = 2 or temporal_mode = 3
usedSeed = 0
if needRandom
    if random_seed = 0
        random_initializeSafelyAndUnpredictably ()
        usedSeed = randomInteger(1, 2000000000)
    else
        usedSeed = abs(random_seed)
    endif
    random_initializeWithSeedUnsafelyButPredictably (usedSeed)
endif

nPair = min(number_of_pairs, nA)
if number_of_pairs > nA
    warnLines$ = warnLines$ + "  ! Number_of_pairs " + string$(number_of_pairs) + " > the " + string$(nA)
        ... + " gestures of Corpus A: " + string$(nPair) + " pairs made (A gestures are not repeated)." + newline$
endif
wEff = if matching_mode = 1 then 0 else duration_weight fi
nTop = min(candidates_per_gesture, nB)
ln4 = ln(4)
for b from 1 to nB
    useB[b] = 0
    takenStamp[b] = 0
endfor
nWeak = 0
for k from 1 to nPair
    a = 1 + floor((k - 1) * nA / nPair)
    pA[k] = a
    aV# = row# (envA##, a)
    for b from 1 to nB
        d# = row# (envB##, b) - aV#
        cS[b] = sqrt(inner(d#, d#) / nEnv)
        cD[b] = min(1, abs(ln(gDur[1, a] / gDur[2, b])) / ln4)
        cT[b] = (1 - wEff) * cS[b] + wEff * cD[b]
    endfor
    # the nTop best candidates, in rank order
    for j from 1 to nTop
        best = 0
        for b from 1 to nB
            if takenStamp[b] <> k
                if best = 0
                    best = b
                elsif cT[b] < cT[best]
                    best = b
                endif
            endif
        endfor
        top[j] = best
        takenStamp[best] = k
    endfor
    if selection_strategy = 1
        # best match; a less-used gesture only when its cost is comparable
        tol = max(0.01, 0.10 * cT[top[1]])
        pick = top[1]
        pickRank = 1
        for j from 2 to nTop
            b = top[j]
            if cT[b] <= cT[top[1]] + tol
                if useB[b] < useB[pick] or (useB[b] = useB[pick] and cT[b] < cT[pick])
                    pick = b
                    pickRank = j
                endif
            endif
        endfor
    else
        minUse = useB[top[1]]
        for j from 2 to nTop
            minUse = min(minUse, useB[top[j]])
        endfor
        nLeast = 0
        for j from 1 to nTop
            if useB[top[j]] = minUse
                nLeast = nLeast + 1
                leastIdx[nLeast] = j
            endif
        endfor
        pickRank = leastIdx[randomInteger(1, nLeast)]
        pick = top[pickRank]
    endif
    pB[k] = pick
    pRank[k] = pickRank
    pDS[k] = cS[pick]
    pDD[k] = cD[pick]
    pDT[k] = cT[pick]
    pBest[k] = cT[top[1]]
    useB[pick] = useB[pick] + 1
    pWeak[k] = cS[pick] > weakShape
    nWeak = nWeak + pWeak[k]
endfor
nUsedB = 0
maxUse = 0
for b from 1 to nB
    if useB[b] > 0
        nUsedB = nUsedB + 1
    endif
    maxUse = max(maxUse, useB[b])
endfor

# ============================================================
# 5b. FORMAL ORGANIZATION: a permutation of the complete pairs
# ============================================================
formName$ = if formal_order = 1 then "Original" else if formal_order = 2 then "Arch" else if formal_order = 3 then "Ascending" else "Descending" fi fi fi
# relative energy of every gesture inside its own corpus (dB, 10th-90th percentile)
for c from 1 to 2
    nc = nG[c]
    db# = zero# (nc)
    for g from 1 to nc
        rv = gRms[c, g]
        if rv = undefined
            rv = 0
        endif
        gDb[c, g] = 20 * log10(max(rv, 1e-9))
        db# [g] = gDb[c, g]
    endfor
    sdb# = sort# (db#)
    refLo[c] = sdb# [1 + round(0.10 * (nc - 1))]
    refHi[c] = sdb# [1 + round(0.90 * (nc - 1))]
    refFlat[c] = refHi[c] - refLo[c] < 1
    for g from 1 to nc
        if refFlat[c]
            gRelU[c, g] = 0.5
        else
            gRelU[c, g] = (gDb[c, g] - refLo[c]) / (refHi[c] - refLo[c])
        endif
        gRel[c, g] = max(0, min(1, gRelU[c, g]))
    endfor
endfor
for k from 1 to nPair
    pOrig[k] = k
    pE[k] = 0.5 * gRel[1, pA[k]] + 0.5 * gRel[2, pB[k]]
    # tie-break only: the same mean without clipping at the percentiles
    pEu[k] = 0.5 * gRelU[1, pA[k]] + 0.5 * gRelU[2, pB[k]]
endfor
# new order: ord[position] = pair index in selection order
for j from 1 to nPair
    ord[j] = j
endfor
if formal_order >= 2 and nPair >= 2
    # sort key per pair (stable insertion sort, ascending key)
    # key: clipped energy first, unclipped energy breaks ties
    sgn = if formal_order = 4 then -1 else 1 fi
    for k from 1 to nPair
        key[k] = sgn * pE[k]
        key2[k] = sgn * pEu[k]
    endfor
    for j from 2 to nPair
        i = j
        while i > 1 and (key[ord[i - 1]] > key[ord[i]] or (key[ord[i - 1]] = key[ord[i]] and key2[ord[i - 1]] > key2[ord[i]]))
            tmp = ord[i]
            ord[i] = ord[i - 1]
            ord[i - 1] = tmp
            i = i - 1
        endwhile
    endfor
    if formal_order = 2
        # target curve over positions: rise to the climax at 70%, then release
        climaxPos = max(1, min(nPair, round(1 + 0.70 * (nPair - 1))))
        for j from 1 to nPair
            x = (j - 1) / (nPair - 1)
            if x <= 0.70
                tgt[j] = 0.10 + 0.90 * (x / 0.70) ^ 1.3
            else
                tgt[j] = 1 - 0.65 * ((x - 0.70) / 0.30) ^ 0.9
            endif
            # small fixed ripple: neighbours of similar energy may trade places
            tgt[j] = tgt[j] + 0.06 * ((j mod 3) - 1)
            tgtShow[j] = tgt[j]
            posOrd[j] = j
        endfor
        tgt[climaxPos] = 2
        for j from 2 to nPair
            i = j
            while i > 1 and tgt[posOrd[i - 1]] > tgt[posOrd[i]]
                tmp = posOrd[i]
                posOrd[i] = posOrd[i - 1]
                posOrd[i - 1] = tmp
                i = i - 1
            endwhile
        endfor
        # i-th weakest pair -> i-th lowest target position
        for i from 1 to nPair
            newOrd[posOrd[i]] = ord[i]
        endfor
        for j from 1 to nPair
            ord[j] = newOrd[j]
        endfor
    endif
    # permute every per-pair array together
    for j from 1 to nPair
        k = ord[j]
        tA[j] = pA[k]
        tB[j] = pB[k]
        tRank[j] = pRank[k]
        tDS[j] = pDS[k]
        tDD[j] = pDD[k]
        tDT[j] = pDT[k]
        tBest[j] = pBest[k]
        tWeak[j] = pWeak[k]
        tE[j] = pE[k]
        tEu[j] = pEu[k]
        tOrig[j] = pOrig[k]
    endfor
    for j from 1 to nPair
        pA[j] = tA[j]
        pB[j] = tB[j]
        pRank[j] = tRank[j]
        pDS[j] = tDS[j]
        pDD[j] = tDD[j]
        pDT[j] = tDT[j]
        pBest[j] = tBest[j]
        pWeak[j] = tWeak[j]
        pE[j] = tE[j]
        pEu[j] = tEu[j]
        pOrig[j] = tOrig[j]
    endfor
endif
# how well the material carries the requested form
eMin = pE[1]
eMax = pE[1]
eSum = 0
strongPos = 1
for k from 1 to nPair
    eMin = min(eMin, pE[k])
    eMax = max(eMax, pE[k])
    eSum = eSum + pE[k]
    if pE[k] > pE[strongPos] or (pE[k] = pE[strongPos] and pEu[k] > pEu[strongPos])
        strongPos = k
    endif
endfor
eMean = eSum / nPair
eRange = eMax - eMin
formCorr = undefined
if formal_order >= 2 and nPair >= 3 and eRange > 0
    # Pearson correlation of pair energy with the requested trajectory
    for k from 1 to nPair
        x = (k - 1) / (nPair - 1)
        if formal_order = 2
            ref[k] = if x <= 0.70 then 0.10 + 0.90 * (x / 0.70) ^ 1.3 else 1 - 0.65 * ((x - 0.70) / 0.30) ^ 0.9 fi
        elsif formal_order = 3
            ref[k] = x
        else
            ref[k] = 1 - x
        endif
    endfor
    mr = 0
    for k from 1 to nPair
        mr = mr + ref[k] / nPair
    endfor
    sxy = 0
    sxx = 0
    syy = 0
    for k from 1 to nPair
        sxy = sxy + (ref[k] - mr) * (pE[k] - eMean)
        sxx = sxx + (ref[k] - mr) ^ 2
        syy = syy + (pE[k] - eMean) ^ 2
    endfor
    if sxx > 0 and syy > 0
        formCorr = sxy / sqrt(sxx * syy)
    endif
endif
if formal_order = 1
    formVerdict$ = "not applicable (selection order kept)"
elsif nPair < 3
    formVerdict$ = "not meaningful with " + string$(nPair) + " pair(s)"
elsif eRange < 0.15
    formVerdict$ = "WEAK - the selected pairs span only " + fixed$(eRange, 2) + " of the 0..1 energy scale; the order follows the "
        ... + formName$ + " shape but little dynamic contrast is available, and no gain is added to create it"
elsif formCorr <> undefined and formCorr >= 0.8
    formVerdict$ = "yes - energy follows the requested trajectory (correlation " + fixed$(formCorr, 2) + ", energy range " + fixed$(eRange, 2) + ")"
else
    formVerdict$ = "partly - correlation with the requested trajectory " + (if formCorr = undefined then "n/a" else fixed$(formCorr, 2) fi)
        ... + ", energy range " + fixed$(eRange, 2)
endif


# ============================================================
# 6. TIME: offsets and scheduling (in output samples)
# ============================================================
gapS = round(inter_pair_gap_ms / 1000 * fs)
fadeS = round(edge_fade_ms / 1000 * fs)
nResampled = 0
for k from 1 to nPair
    if temporal_mode = 1
        off = 0
    elsif temporal_mode = 2
        off = fixed_offset_ms / 1000
    else
        off = randomUniform(-maximum_offset_ms / 1000, maximum_offset_ms / 1000)
    endif
    pOffS[k] = round(off * fs)
    for v from 1 to 2
        g = if v = 1 then pA[k] else pB[k] fi
        f = gFile[v, g]
        n = gS2[v, g] - gS1[v, g] + 1
        if fRate[f] = fs
            pLen[v, k] = n
        else
            pLen[v, k] = round(n * fs / fRate[f])
            nResampled = nResampled + 1
        endif
    endfor
endfor
if needRandom
    random_initializeSafelyAndUnpredictably ()
endif
for k from 1 to nPair
    if k = 1
        tk = 0
    elsif allow_within_voice_overlap
        tk = max(pStart[1, k - 1] + ceiling(pLen[1, k - 1] / 2),
            ... pStart[2, k - 1] + ceiling(pLen[2, k - 1] / 2) - pOffS[k]) + gapS
    else
        tk = max(pStart[1, k - 1] + pLen[1, k - 1], pStart[2, k - 1] + pLen[2, k - 1] - pOffS[k]) + gapS
    endif
    pStart[1, k] = tk
    pStart[2, k] = tk + pOffS[k]
endfor
# negative offsets: shift the whole timeline later instead of cutting
minStart = 0
for k from 1 to nPair
    minStart = min(minStart, min(pStart[1, k], pStart[2, k]))
endfor
timelineShift = max(0, -minStart)
totalS = 0
nDelay = 0
nAnticip = 0
nSync = 0
for k from 1 to nPair
    for v from 1 to 2
        pStart[v, k] = pStart[v, k] + timelineShift
        totalS = max(totalS, pStart[v, k] + pLen[v, k])
    endfor
    if pOffS[k] > 0
        nDelay = nDelay + 1
    elsif pOffS[k] < 0
        nAnticip = nAnticip + 1
    else
        nSync = nSync + 1
    endif
endfor

# ============================================================
# 7. ASSEMBLY: each needed file read once, gestures copied by index
# ============================================================
appendInfoLine: "Assembling ", nPair, " pairs from ", nA + nB, " analysed gestures..."
voice[1] = Create Sound from formula: "gc_voice_A", 1, 0, totalS / fs, fs, "0"
bufN = Get number of samples
voice[2] = Create Sound from formula: "gc_voice_B", 1, 0, totalS / fs, fs, "0"
if bufN <> totalS
    removeObject: voice[1], voice[2]
    exitScript: "Internal error: output buffer has " + string$(bufN) + " samples instead of " + string$(totalS) + "."
endif
lenMismatch = 0
for f from 1 to nFile
    needed = 0
    for k from 1 to nPair
        if gFile[1, pA[k]] = f or gFile[2, pB[k]] = f
            needed = 1
        endif
    endfor
    if needed
        snd = Read from file: fPath$[f]
        for k from 1 to nPair
            for v from 1 to 2
                g = if v = 1 then pA[k] else pB[k] fi
                if gFile[v, g] = f
                    n = gS2[v, g] - gS1[v, g] + 1
                    sh = gS1[v, g] - 1
                    # exact samples by index; stereo -> mean of the channels
                    if fCh[f] = 1
                        frm$ = "object[" + string$(snd) + ", 1, col + " + string$(sh) + "]"
                    else
                        frm$ = "("
                        for ch from 1 to fCh[f]
                            frm$ = frm$ + (if ch > 1 then " + " else "" fi) + "object[" + string$(snd) + ", "
                                ... + string$(ch) + ", col + " + string$(sh) + "]"
                        endfor
                        frm$ = frm$ + ") / " + string$(fCh[f])
                    endif
                    part = Create Sound from formula: "gc_part", 1, 0, n / fRate[f], fRate[f], frm$
                    pn = Get number of samples
                    if pn <> n
                        lenMismatch = lenMismatch + 1
                    endif
                    if fRate[f] <> fs
                        part2 = Resample: fs, 50
                        removeObject: part
                        part = part2
                        pn = Get number of samples
                    endif
                    if pn <> pLen[v, k]
                        lenMismatch = lenMismatch + 1
                        pn = min(pn, pLen[v, k])
                    endif
                    st = pStart[v, k]
                    aF = min(fadeS, floor(pn / 2))
                    if aF > 0
                        gain$ = "(if col - " + string$(st) + " - 1 < " + string$(aF) + " then 0.5 - 0.5 * cos(pi * (col - "
                            ... + string$(st) + " - 1) / " + string$(aF) + ") else if col - " + string$(st) + " - 1 > "
                            ... + string$(pn - 1 - aF) + " then 0.5 - 0.5 * cos(pi * (" + string$(pn) + " - col + "
                            ... + string$(st) + ") / " + string$(aF) + ") else 1 fi fi)"
                    else
                        gain$ = "1"
                    endif
                    selectObject: voice[v]
                    Formula (part): (st + 0.25) / fs, (st + pn - 0.25) / fs, 1, 1,
                        ... "self + object[" + string$(part) + ", 1, col - " + string$(st) + "] * " + gain$
                    removeObject: part
                endif
            endfor
        endfor
        removeObject: snd
    endif
endfor

# ============================================================
# 8. FINAL MIX: level matching, equal-power panning, -1 dBFS ceiling
#    (applied to the two complete voices; nothing above changes)
# ============================================================
selectObject: voice[1]
peakA = Get absolute extremum: 0, 0, "None"
selectObject: voice[2]
peakB = Get absolute extremum: 0, 0, "None"

# active-region RMS: union of the intervals the voice's gestures occupy
for v from 1 to 2
    for k from 1 to nPair
        ordS[k] = pStart[v, k]
        ordE[k] = pStart[v, k] + pLen[v, k]
    endfor
    for k from 2 to nPair
        j = k
        while j > 1 and ordS[j - 1] > ordS[j]
            tmp = ordS[j]
            ordS[j] = ordS[j - 1]
            ordS[j - 1] = tmp
            tmp = ordE[j]
            ordE[j] = ordE[j - 1]
            ordE[j - 1] = tmp
            j = j - 1
        endwhile
    endfor
    sumSq = 0
    act = 0
    curS = ordS[1]
    curE = ordE[1]
    for k from 2 to nPair + 1
        if k <= nPair and ordS[k] <= curE
            curE = max(curE, ordE[k])
        else
            selectObject: voice[v]
            r = Get root-mean-square: (curS + 0.25) / fs, (curE - 0.25) / fs
            sumSq = sumSq + r ^ 2 * (curE - curS)
            act = act + (curE - curS)
            if k <= nPair
                curS = ordS[k]
                curE = ordE[k]
            endif
        endif
    endfor
    actS[v] = act
    rmsV[v] = sqrt(sumSq / max(1, act))
endfor
rmsFloor = 1e-6
gainLimitDb = 24
rawDiffDb = undefined
if rmsV[1] > rmsFloor and rmsV[2] > rmsFloor
    rawDiffDb = 20 * log10(rmsV[2] / rmsV[1])
endif
autoDb = 0
autoLimited = 0
autoNote$ = ""
if match_voice_levels
    if rawDiffDb = undefined
        autoNote$ = "not applied: a voice is near-silent (active RMS below -120 dBFS)"
    else
        autoDb = -rawDiffDb
        if abs(autoDb) > gainLimitDb
            autoDb = if autoDb > 0 then gainLimitDb else -gainLimitDb fi
            autoLimited = 1
            autoNote$ = "LIMITED to " + fixed$(autoDb, 1) + " dB: the voices are " + fixed$(abs(rawDiffDb), 1)
                ... + " dB apart, so they are NOT fully matched"
        endif
    endif
endif
autoGain = 10 ^ (autoDb / 20)
manualGain = 10 ^ (voice_B_balance_dB / 20)
gainA = 1
gainB = autoGain * manualGain

procedure gcPan: .p
    # equal power; exact 1/0 at the extremes
    if .p <= -100
        .l = 1
        .r = 0
    elsif .p >= 100
        .l = 0
        .r = 1
    else
        .theta = (.p + 100) / 200 * pi / 2
        .l = cos(.theta)
        .r = sin(.theta)
    endif
endproc
@gcPan: voice_A_pan
panAL = gcPan.l
panAR = gcPan.r
@gcPan: voice_B_pan
panBL = gcPan.l
panBR = gcPan.r
cAL = gainA * panAL
cAR = gainA * panAR
cBL = gainB * panBL
cBR = gainB * panBR

vA = voice[1]
vB = voice[2]
mix$ = "if row = 1 then cAL * object[vA, 1, col] + cBL * object[vB, 1, col] else cAR * object[vA, 1, col] + cBR * object[vB, 1, col] fi"
out = Create Sound from formula: "Gestural_Counterpoint", 2, 0, totalS / fs, fs, mix$
peakMix = Get absolute extremum: 0, 0, "None"
ceiling = 10 ^ (-1 / 20)
finalGain = 1
if peakMix > ceiling
    finalGain = ceiling / peakMix
    Formula: "self * finalGain"
endif
peakOut = Get absolute extremum: 0, 0, "None"
outN = Get number of samples
outCh = Get number of channels
outFs = Get sampling frequency
outDur = Get total duration
# every sample against the mix formula (including the final gain)
chk = Copy: "gc_check"
Formula: "self - finalGain * (" + mix$ + ")"
chanDiff = Get absolute extremum: 0, 0, "None"
removeObject: chk
mixTol = 1e-9
removeObject: voice[1], voice[2]
gridOk = outN = totalS and outCh = 2 and outFs = fs

# summary statistics
dMin = pDT[1]
dMax = pDT[1]
dSum = 0
for k from 1 to nPair
    dMin = min(dMin, pDT[k])
    dMax = max(dMax, pDT[k])
    dSum = dSum + pDT[k]
endfor
dMean = dSum / nPair
bestPair = 1
for k from 2 to nPair
    if pDT[k] < pDT[bestPair]
        bestPair = k
    endif
endfor

# ============================================================
# VISUALIZATION
# AudioTools 3-row layout: A envelopes of both corpora and the
# closest pair, B the matching map (pairs and distances), C the
# two-voice timeline (Voice A - Corpus A, Voice B - Corpus B).
# ============================================================
if draw_visualization
    appendInfoLine: "Drawing visualization..."
    colA$ = "{0.20,0.40,0.75}"
    colB$ = "{0.78,0.40,0.20}"
    fillA$ = "{0.86,0.90,0.97}"
    fillB$ = "{0.98,0.90,0.84}"
    weakFill$ = "{1.00,0.92,0.90}"

    procedure gcEnv: .c, .g, .xa, .xb, .y0, .yh, .stride
        # envelope of gesture .g of corpus .c mapped to x .xa..xb, y .y0..y0+yh
        .px = .xa + 0.5 / nEnv * (.xb - .xa)
        .py = .y0 + .yh * gEnv[.c, .g, 1]
        .i = 1 + .stride
        while .i <= nEnv
            .qx = .xa + (.i - 0.5) / nEnv * (.xb - .xa)
            .qy = .y0 + .yh * gEnv[.c, .g, .i]
            Draw line: .px, .py, .qx, .qy
            .px = .qx
            .py = .qy
            .i = .i + .stride
        endwhile
    endproc

    procedure gcStep: .range, .target
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

    Erase all
    Line width: 1
    Solid line

    # ---------------- Suite header ----------------
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Gestural Counterpoint v1.2##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", string$(nA) + " gestures in A | " + string$(nB) + " gestures in B | "
        ... + string$(nPair) + " pairs | " + modeName$ + " | " + stratName$ + " | form " + formName$ + " | " + timeName$

    # ========================================================
    # A  CORPUS GESTURE ANALYSIS
    # ========================================================
    Font size: 9
    Select outer viewport: 0.18, 7.82, 0.62, 0.88
    Select inner viewport: 0.18, 7.82, 0.62, 0.88
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.01, "left", 0.72, "half", "A  CORPUS GESTURE ANALYSIS - normalized amplitude envelopes (time and level scaled to 0..1)"
    Font size: 6
    Colour: "{0.34,0.38,0.48}"
    Text: 0.01, "left", 0.18, "half", "left: Corpus A | middle: Corpus B (up to 30 each, evenly sampled) | right: the closest pair - the shape is compared, not the sound"
    for box from 1 to 3
        bx1 = 0.60 + (box - 1) * 2.40
        bx2 = bx1 + 2.15
        Select outer viewport: bx1 - 0.10, bx2 + 0.10, 0.89, 2.22
        Select inner viewport: bx1, bx2, 0.96, 2.02
        Axes: 0, 1, 0, 1.15
        Paint rectangle: "White", 0, 1, 0, 1.15
        if box <= 2
            nC = if box = 1 then nA else nB fi
            step = max(1, nC / 30)
            Colour: if box = 1 then "{0.55,0.66,0.86}" else "{0.92,0.68,0.55}" fi
            gq = 1
            while gq <= nC
                @gcEnv: box, round(gq), 0, 1, 0, 1, 1
                gq = gq + step
            endwhile
            Colour: "Black"
            Font size: 6
            Text: 0.03, "left", 1.08, "half", if box = 1 then "Corpus A - " + string$(nA) + " gestures" else "Corpus B - " + string$(nB) + " gestures" fi
        else
            Line width: 2
            Colour: colA$
            @gcEnv: 1, pA[bestPair], 0, 1, 0, 1, 1
            Colour: colB$
            @gcEnv: 2, pB[bestPair], 0, 1, 0, 1, 1
            Line width: 1
            Colour: "Black"
            Font size: 6
            Text: 0.03, "left", 1.08, "half", "pair " + string$(bestPair) + ": D = " + fixed$(pDT[bestPair], 3)
                ... + " (shape " + fixed$(pDS[bestPair], 3) + ")"
        endif
        Select inner viewport: bx1, bx2, 0.96, 2.02
        Axes: 0, 1, 0, 1.15
        Colour: "Black"
        Draw inner box
        Font size: 6
        Marks bottom every: 1, 0.5, "yes", "yes", "no"
        Text bottom: "yes", "normalized time"
    endfor
    Select inner viewport: 0.60, 2.75, 0.96, 2.02
    Axes: 0, 1, 0, 1.15
    Font size: 6
    Marks left every: 1, 0.5, "yes", "yes", "no"

    # ========================================================
    # B  MATCHING MAP
    # ========================================================
    Font size: 9
    Select outer viewport: 0.18, 7.82, 2.36, 2.62
    Select inner viewport: 0.18, 7.82, 2.36, 2.62
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.01, "left", 0.72, "half", "B  MATCHING MAP - Voice A gesture (blue) and its Corpus B match (orange), per pair"
    Font size: 6
    Colour: "{0.34,0.38,0.48}"
    Text: 0.01, "left", 0.18, "half", "pairs in playback order | D = matching cost (lower = closer dynamic shape) | pink = weak match (shape distance > "
        ... + fixed$(weakShape, 2) + ")" + (if formal_order >= 2 then " | strip: relative pair energy (" + formName$ + ", red = strongest" + (if formal_order = 2 then ", dotted = target" else "" fi) + ")" else "" fi)
    # with a formal order, the map is a little shorter and an energy strip follows
    bBot = if formal_order >= 2 then 3.42 else 3.62 fi
    if nPair <= 24
        cw = 7.10 / nPair
        for k from 1 to nPair
            cx1 = 0.60 + (k - 1) * cw + 0.02
            cx2 = cx1 + cw - 0.04
            Select inner viewport: cx1, cx2, 2.72, bBot
            Axes: 0, 1, -0.45, 1.25
            Paint rectangle: if pWeak[k] then weakFill$ else "White" fi, 0, 1, -0.45, 1.25
            Colour: colA$
            @gcEnv: 1, pA[k], 0.04, 0.96, 0, 1, 2
            Colour: colB$
            @gcEnv: 2, pB[k], 0.04, 0.96, 0, 1, 2
            Colour: "Black"
            Font size: 6
            Text: 0.5, "centre", 1.13, "half", string$(k)
            Text: 0.5, "centre", -0.22, "half", fixed$(pDT[k], 3)
            Select inner viewport: cx1, cx2, 2.72, bBot
            Axes: 0, 1, -0.45, 1.25
            Draw inner box
        endfor
    else
        Select outer viewport: 0.18, 7.82, 2.63, 3.70
        Select inner viewport: 0.60, 7.70, 2.72, bBot - (if formal_order >= 2 then 0.08 else 0.07 fi)
        yTop = max(0.05, dMax * 1.15)
        Axes: 0.5, nPair + 0.5, 0, yTop
        for k from 1 to nPair
            Paint rectangle: if pWeak[k] then "{0.88,0.55,0.50}" else colB$ fi, k - 0.38, k + 0.38, 0, pDT[k]
        endfor
        Colour: "Black"
        Draw inner box
        Font size: 6
        @gcStep: yTop, 3
        Marks left every: 1, gcStep.step, "yes", "yes", "no"
        @gcStep: nPair, 10
        Marks bottom every: 1, max(1, round(gcStep.step)), "yes", "yes", "no"
        Text left: "yes", "D"
    endif
    if formal_order >= 2
        # energy strip: relative pair energy in playback order
        Select inner viewport: 0.60, 7.70, 3.50, 3.68
        Axes: 0.5, nPair + 0.5, -0.1, 1.1
        Paint rectangle: "{0.97, 0.97, 0.97}", 0.5, nPair + 0.5, -0.1, 1.1
        if formal_order = 2 and nPair >= 3
            Colour: "{0.75,0.75,0.75}"
            Dotted line
            for k from 2 to nPair
                Draw line: k - 1, ref[k - 1], k, ref[k]
            endfor
            Solid line
        endif
        Colour: "{0.30,0.30,0.30}"
        for k from 2 to nPair
            Draw line: k - 1, pE[k - 1], k, pE[k]
        endfor
        for k from 1 to nPair
            Paint circle (mm): if k = strongPos then "{0.80,0.20,0.20}" else "{0.30,0.30,0.30}" fi, k, pE[k], 0.5
        endfor
        Colour: "Black"
        Draw inner box
        Font size: 6
        Text left: "no", "energy"
    endif

    # ========================================================
    # C  TWO-VOICE TIMELINE
    # ========================================================
    tEnd = totalS / fs
    Font size: 9
    Select outer viewport: 0.18, 7.82, 3.76, 4.02
    Select inner viewport: 0.18, 7.82, 3.76, 4.02
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.01, "left", 0.72, "half", "C  TWO-VOICE TIMELINE - " + timeName$ + " (Voice A — Corpus A, Voice B — Corpus B)"
    Font size: 6
    Colour: "{0.34,0.38,0.48}"
    Text: 0.01, "left", 0.18, "half", "boxes = whole gestures at original length, with their envelope | numbers = pair | dotted = B entry relative to A | white = silence"
    Select outer viewport: 0.18, 7.82, 4.03, 5.40
    Select inner viewport: 0.60, 7.70, 4.10, 5.16
    Axes: 0, tEnd, 0, 2
    Paint rectangle: "White", 0, tEnd, 0, 2
    for k from 1 to nPair
        for v from 1 to 2
            xa = pStart[v, k] / fs
            xb = (pStart[v, k] + pLen[v, k]) / fs
            y0 = if v = 1 then 1.12 else 0.12 fi
            Paint rectangle: if v = 1 then fillA$ else fillB$ fi, xa, xb, y0, y0 + 0.76
        endfor
    endfor
    for k from 1 to nPair
        for v from 1 to 2
            g = if v = 1 then pA[k] else pB[k] fi
            xa = pStart[v, k] / fs
            xb = (pStart[v, k] + pLen[v, k]) / fs
            y0 = if v = 1 then 1.12 else 0.12 fi
            Colour: if v = 1 then colA$ else colB$ fi
            Draw rectangle: xa, xb, y0, y0 + 0.76
            @gcEnv: v, g, xa, xb, y0 + 0.04, 0.62, if nPair > 40 then 4 else 2 fi
        endfor
    endfor
    if nPair <= 60
        for k from 1 to nPair
            if pOffS[k] <> 0
                Colour: "{0.40,0.40,0.40}"
                Dotted line
                Draw line: pStart[1, k] / fs, 1.12, pStart[2, k] / fs, 0.88
                Solid line
            endif
        endfor
    endif
    labelMin = tEnd / 60
    for k from 1 to nPair
        for v from 1 to 2
            if pLen[v, k] / fs >= labelMin and nPair <= 80
                Colour: "Black"
                Font size: 6
                yl = if v = 1 then 1.80 else 0.80 fi
                Text: (pStart[v, k] + pLen[v, k] / 2) / fs, "centre", yl, "half", string$(k)
            endif
        endfor
    endfor
    Select inner viewport: 0.60, 7.70, 4.10, 5.16
    Axes: 0, tEnd, 0, 2
    Colour: "Black"
    Draw inner box
    Font size: 6
    One mark left: 1.5, "no", "no", "no", "Voice A"
    One mark left: 0.5, "no", "no", "no", "Voice B"
    @gcStep: tEnd, 8
    Marks bottom every: 1, gcStep.step, "yes", "yes", "no"
    Text bottom: "yes", "time (s)"

    # ---------------- Bottom summary ----------------
    Select outer viewport: 0.18, 7.82, 5.66, 6.17
    Select inner viewport: 0.18, 7.82, 5.66, 6.17
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text: 0.02, "left", 0.67, "half", "MATCHING " + modeName$ + (if matching_mode = 2 then " (w " + fixed$(wEff, 2) + ")" else "" fi)
        ... + "   |   D mean " + fixed$(dMean, 3) + "  min " + fixed$(dMin, 3) + "  max " + fixed$(dMax, 3)
        ... + "   |   weak " + string$(nWeak) + "/" + string$(nPair) + "   |   B gestures used " + string$(nUsedB) + "/" + string$(nB)
    Colour: "{0.34,0.38,0.48}"
    seedNote$ = if needRandom then " | seed " + string$(usedSeed) else "" fi
    Text: 0.02, "left", 0.24, "half", timeName$ + " | " + string$(nDelay) + " delayed, " + string$(nAnticip) + " anticipating, "
        ... + string$(nSync) + " synchronous | " + fixed$(outDur, 2) + " s | pan A " + (if voice_A_pan > 0 then "+" else "" fi) + fixed$(voice_A_pan, 0) + " / B "
        ... + (if voice_B_pan > 0 then "+" else "" fi) + fixed$(voice_B_pan, 0) + " | B " + (if gainB >= 1 then "+" else "" fi) + fixed$(20 * log10(gainB), 1) + " dB"
        ... + (if match_voice_levels then " (matched" + (if autoLimited then ", limited" else "" fi) + ")" else "" fi)
        ... + (if finalGain < 1 then " | ceiling " + fixed$(20 * log10(finalGain), 1) + " dB" else "" fi) + seedNote$
    pageHeight = 6.27
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# ============================================================
# REPORT
# ============================================================
appendInfoLine: ""
appendInfoLine: "=== Gestural Counterpoint: COMPLETE ==="
for c from 1 to 2
    appendInfoLine: "Corpus ", if c = 1 then "A" else "B" fi, ": ", if c = 1 then corpusA$ else corpusB$ fi
    appendInfoLine: "  files scanned: ", nListed[c], " audio (", nOther[c], " other file(s) ignored) | silent ", nSilentFile[c],
        ... " | unreadable ", nBadFile[c], " | gestures ", nG[c], " | rejected (shorter than ",
        ... fixed$(minimum_gesture_duration_s, 3), " s) ", nShort[c]
endfor
appendInfoLine: "Detection: threshold -", fixed$(silence_threshold_dB, 1), " dB re each file's max | min silence ",
    ... fixed$(minimum_silence_duration_s, 3), " s | min gesture ", fixed$(minimum_gesture_duration_s, 3), " s"
appendInfoLine: "Envelope: ", nEnv, "-point linear RMS, peak-normalized; amplitude shape is the only feature"
appendInfoLine: "Matching: ", modeName$, if matching_mode = 2 then " | duration weight " + fixed$(wEff, 2) else " (duration ignored)" fi,
    ... " | ", stratName$, " | top ", nTop, " candidates per gesture"
appendInfoLine: "Pairs: ", nPair, " | D_total mean ", fixed$(dMean, 4), " | min ", fixed$(dMin, 4), " | max ", fixed$(dMax, 4)
if nWeak > 0
    appendInfoLine: "  Weak matches: ", nWeak, " pair(s) with shape distance > ", fixed$(weakShape, 2),
        ... " - Corpus B holds no closer dynamic shape for them; they are not presented as convincing pairs."
else
    appendInfoLine: "  Weak matches: none (every shape distance <= ", fixed$(weakShape, 2), ")"
endif
appendInfoLine: "Reuse: ", nUsedB, " of ", nB, " Corpus B gestures used, at most ", maxUse, " time(s) each | unused: A ",
    ... nA - nPair, ", B ", nB - nUsedB
appendInfoLine: "Time: ", timeName$, " | gap ", fixed$(inter_pair_gap_ms, 0), " ms | within-voice overlap ",
    ... if allow_within_voice_overlap then "allowed" else "off" fi, " | B delayed ", nDelay, ", anticipating ", nAnticip,
    ... ", synchronous ", nSync
if timelineShift > 0
    appendInfoLine: "  Timeline shifted later by ", fixed$(1000 * timelineShift / fs, 1), " ms so that an anticipating gesture is not cut"
endif
if needRandom
    appendInfoLine: "Random seed used: ", usedSeed
endif
appendInfoLine: "Output: Sound Gestural_Counterpoint | ", fixed$(outDur, 4), " s | ", outN, " samples | ", outFs, " Hz | ",
    ... outCh, " channels"
appendInfoLine: "  Gesture lengths: ", if lenMismatch = 0 then "all " + string$(2 * nPair) + " gestures placed at full length" else string$(lenMismatch) + " length mismatch(es) - please report this" fi
appendInfoLine: "  Sample rate: ", fs, " Hz (most common usable rate) | gestures resampled: ", nResampled, " | edge fade ",
    ... fixed$(edge_fade_ms, 1), " ms"
appendInfoLine: ""
appendInfoLine: "FINAL MIX AND STEREO PLACEMENT"
appendInfoLine: "  Automatic level matching: ", if match_voice_levels then "ON" else "OFF" fi
appendInfoLine: "  Active-region RMS before matching: Voice A ", fixed$(rmsV[1], 5), " (", fixed$(20 * log10(max(1e-12, rmsV[1])), 1),
    ... " dBFS over ", fixed$(actS[1] / fs, 2), " s), Voice B ", fixed$(rmsV[2], 5), " (", fixed$(20 * log10(max(1e-12, rmsV[2])), 1),
    ... " dBFS over ", fixed$(actS[2] / fs, 2), " s) - timeline gaps excluded"
appendInfoLine: "  Original difference B - A: ", if rawDiffDb = undefined then "undefined (near-silent voice)" else fixed$(rawDiffDb, 2) + " dB" fi
appendInfoLine: "  Voice B gain: automatic ", fixed$(autoDb, 2), " dB", if autoNote$ <> "" then " (" + autoNote$ + ")" else "" fi,
    ... " + manual balance ", fixed$(voice_B_balance_dB, 2), " dB = ", fixed$(20 * log10(gainB), 2), " dB (x", fixed$(gainB, 4),
    ... ") | Voice A gain 0 dB"
appendInfoLine: "  Pan (equal power): Voice A ", fixed$(voice_A_pan, 1), " -> L ", fixed$(panAL, 4), " R ", fixed$(panAR, 4),
    ... " | Voice B ", fixed$(voice_B_pan, 1), " -> L ", fixed$(panBL, 4), " R ", fixed$(panBR, 4)
appendInfoLine: "  Voice peaks before mixing: A ", fixed$(peakA, 4), ", B ", fixed$(peakB, 4), " | stereo peak before the ceiling ",
    ... fixed$(peakMix, 4), " (", fixed$(20 * log10(max(1e-12, peakMix)), 2), " dBFS)"
appendInfoLine: "  Peak ceiling -1 dBFS: ", if finalGain < 1 then "common attenuation " + fixed$(20 * log10(finalGain), 2) + " dB on both channels" else "not needed (no attenuation, no boost)" fi,
    ... " | final peak ", fixed$(20 * log10(max(1e-12, peakOut)), 2), " dBFS"
appendInfoLine: "  Timing: gesture durations and positions are those of the schedule above - the mix stage only scales and pans whole voices"
if gridOk and chanDiff <= mixTol
    appendInfoLine: "  Stereo verification: every sample of L and R equals finalGain x (gain x pan) weighted sum of Voice A and Voice B",
        ... " (max difference ", fixed$(chanDiff, 12), ")"
else
    appendInfoLine: "  ! Stereo verification FAILED (grid ", if gridOk then "ok" else "differs" fi, ", max difference ",
        ... fixed$(chanDiff, 12), ") - please report this."
endif
appendInfoLine: ""
appendInfoLine: "FORMAL ORGANIZATION"
appendInfoLine: "  Formal order: ", formName$, " | ", nPair, " pairs | relative pair energy (0..1 within each corpus, not perceptual loudness): min ",
    ... fixed$(eMin, 2), ", max ", fixed$(eMax, 2), ", mean ", fixed$(eMean, 2)
for c from 1 to 2
    appendInfoLine: "  Corpus ", if c = 1 then "A" else "B" fi, " energy reference: ", fixed$(refLo[c], 1), " to ", fixed$(refHi[c], 1),
        ... " dBFS gesture RMS (10th-90th percentile)", if refFlat[c] then " - less than 1 dB apart: all its gestures count as 0.5" else "" fi
endfor
ordLine$ = ""
for k from 1 to nPair
    ordLine$ = ordLine$ + (if k > 1 then " " else "" fi) + string$(pOrig[k])
endfor
appendInfoLine: "  Playback order of the selected pairs (original indices): ", if nPair <= 60 then ordLine$ else "(" + string$(nPair) + " pairs, see list)" fi
appendInfoLine: "  Strongest pair: original ", pOrig[strongPos], " at playback position ", strongPos, " of ", nPair,
    ... " (", fixed$(100 * (strongPos - 1) / max(1, nPair - 1), 0), "% of the sequence)"
appendInfoLine: "  Trajectory represented: ", formVerdict$
appendInfoLine: "  Form is laid out over pair positions; pairs keep their natural length, so clock-time proportions follow the gestures."
appendInfoLine: ""
appendInfoLine: "Pairs: position [original index | energy] A_file / A_start / A_end / B_file / B_start / B_end / D_total (shape, duration) / offset"
nList = min(nPair, 40)
for k from 1 to nList
    a = pA[k]
    b = pB[k]
    appendInfoLine: "  ", k, ". [", pOrig[k], " | ", fixed$(pE[k], 2), "] ", fName$[gFile[1, a]], " / ", fixed$(gT1[1, a], 3), " / ", fixed$(gT2[1, a], 3), " / ",
        ... fName$[gFile[2, b]], " / ", fixed$(gT1[2, b], 3), " / ", fixed$(gT2[2, b], 3), " / ", fixed$(pDT[k], 4),
        ... " (", fixed$(pDS[k], 3), ", ", fixed$(pDD[k], 3), ") / ", fixed$(1000 * pOffS[k] / fs, 1), " ms",
        ... if pWeak[k] then "  [weak]" else "" fi
endfor
if nPair > nList
    appendInfoLine: "  ... ", nPair - nList, " more pair(s) not listed"
endif
nProblem = 0
for f from 1 to nFile
    if fStatus$[f] <> "ok"
        nProblem = nProblem + 1
    endif
endfor
if nProblem > 0
    appendInfoLine: ""
    appendInfoLine: "Files without gestures:"
    nShown = 0
    for f from 1 to nFile
        if fStatus$[f] <> "ok" and nShown < 20
            nShown = nShown + 1
            appendInfoLine: "  ", if fCorpus[f] = 1 then "A" else "B" fi, ": ", fName$[f], " - ", fStatus$[f]
        endif
    endfor
    if nProblem > nShown
        appendInfoLine: "  ... ", nProblem - nShown, " more"
    endif
endif
if warnLines$ <> ""
    appendInfoLine: ""
    appendInfoLine: "Adjustments made during processing:"
    appendInfo: warnLines$
endif

selectObject: out
if play_result
    appendInfoLine: "Playing..."
    Play
endif
