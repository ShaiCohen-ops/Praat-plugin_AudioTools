# ============================================================
# Praat AudioTools - Spectral_Gesture_Forge.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Forges ONE short stereo gesture (3-7 s) by spectrally fusing up to
#   five recordings, one drawn from each source folder. Native Praat
#   only: no Python, no external programs.
#
# How it works (details in the comments of each section):
#   1. Corpus   one recording per folder, either at random or by
#               spectral complementarity (centroid, bandwidth, six band
#               energies, tonality, profile contrast), from a bounded
#               random sample of each folder (at most 12 usable ones
#               analysed, at most 40 tried). Files are opened as
#               LongSounds; only the first 30 s are read for analysis.
#   2. Material in each chosen recording a strong attack (largest 30 ms
#               intensity rise, leaving at least min(1.2 s, 60 %) of the
#               file after it) starts the region used. A source shorter
#               than the gesture is read more slowly after its first
#               0.3 s (frame time-remapping, at most x2); if it still
#               runs out, its envelopes fade where its material ends.
#   3. Fusion   short-time spectra (1024-point FFT, Hann, 75 % overlap,
#               about 23 ms) of all sources are fused frame by frame:
#                 weights    w_k(f) = sum_b env_kb(t) B_b(f): six log-
#                            spaced raised-cosine bands (centres 80 Hz
#                            ... 12 kHz, partition of unity), so five
#                            sources give 30 source-band envelopes. A
#                            source with (almost) no energy in a band in
#                            a frame is left out there (-40..-30 dB gate)
#                            - band-limited files do not empty the fusion;
#                 magnitude  per bin a weighted POWER MEAN,
#                            M = G * (sum w_k m_k^p / G)^(1/p), G = sum w_k,
#                            p = 1 - 0.85 * fusion strength (p = 1: the
#                            magnitude sum; p -> 0: the geometric mean,
#                            where only what the sources SHARE survives);
#                 phase      of the dominance-weighted complex sum
#                            Z = sum w_k^2 m_k S_k (a soft, continuous
#                            "dominant source" choice - no switching, no
#                            random phases);
#                 level      per band and frame the fused spectrum is
#                            scaled to the energy the weighted sources
#                            would have together, so the envelopes, not
#                            the fusion, set the band levels (boost at
#                            most +12 dB; low band at most 60 % of the
#                            frame energy).
#               Inverse FFT, Hann synthesis window, overlap-add. With all
#               envelopes at 1 and one source the chain reconstructs the
#               source to -149 dB (verified), apart from a 20-40 Hz
#               high-pass that removes DC and sub-bass.
#   4. ADSR     every source-band pair has its own delay, attack (with
#               curvature), decay, sustain, release and level, derived
#               from the Gesture character, Envelope sharpness, Spectral
#               variation and the source's own band energy.
#   5. Stereo   L and R are fused with different weights: every source-
#               band contribution gets equal-power gains from a global
#               trajectory plus the side of its band (alternating across
#               bands, wider for higher bands; lows stay central) and
#               the motion preset; highs spread outward on their own
#               transients. Both channels share the fused phase, except
#               a fixed inter-channel offset in the upper bands
#               (+/- width x 40 deg at most) for decorrelation - the
#               mono fold-down loses at most 1 - cos(40 deg) in the top
#               band (measured: -0.07 to -0.75 dB overall).
#   6. Finish   2 ms start fade, 5 ms end fade, peak normalisation to
#               -1 dBFS (no compression or limiting).
#   7. Reverb   optional (Reverb mode None = exactly v1.0):
#               Per-source  every chosen source gets its own reverb; its
#                           wet signal enters the fusion as an extra
#                           MEMBER with its own reverberant envelopes, so
#                           the reverb is fused with the other sources
#                           (power mean, shared phase, band levels) - not
#                           added to the finished sound.
#               Global      a stereo reverb on the finished fusion.
#               Both        per-source, then global at 60 % of the amount.
#               Reverberator: a synthetic impulse response per source
#               (sparse random-sign noise; three band decays - T60 below
#               ~600 Hz, mid and high shortened by the damping; early
#               reflections in the first ~70 ms; pre-delay; unit energy)
#               applied by FFT convolution. It is a finite response, not a
#               feedback network: it cannot become unstable and has no
#               periodic delay lines (no flutter or metallic combing), but
#               its density does not build up the way a recirculating
#               reverberator's does. Measured decays match the settings.
#               Per-source parameters: decay, pre-delay and wet level are
#               spread over the sources by seeded permutations (Reverb
#               decay diversity: 0 = alike, 100 % = decays over x0.35 ...
#               x2.8 of the average, bounded 0.15-5 s); tonal sources
#               decay 20 % shorter, sources shorter than the gesture up to
#               30 % longer, bright ones are damped more, noisy ones get a
#               denser, more diffuse response.
#               Reverberant envelope (per source and band): a decaying
#               memory of the direct envelope - it follows the direct
#               sound after the pre-delay (30 ms rise), decays at twice the
#               source's T60 once the direct sound falls (the wet signal
#               supplies its own decay) and is ducked while the direct
#               sound is strong (-60 %), so the reverb comes forward in the
#               release. The direct envelopes are unchanged.
#               Tail: Contained - the reverb fades inside the gesture;
#               Extended - it may continue after the gesture (the direct
#               sound does not), cut 50 ms after the last 10 ms window
#               within 60 dB of the peak, at most 4 s after the gesture.
#               All reverb randomness comes after every other random draw,
#               from its own seed: sources, regions and envelopes are the
#               same with or without reverb, whatever its settings.
#
# Changelog
#   1.3  Cross-platform file discovery and loading (macOS report: "No usable
#        recording"): one "*" listing with case-insensitive extensions (.Aif,
#        .aIFF, .Mp3 ... were missed), hidden and macOS "._" files skipped,
#        no case-folding de-duplication; selection-safe opening with a reason
#        for every failure; silence test on the strongest channel, and the
#        strongest channel used when a stereo mix cancels; a per-folder
#        diagnosis (files found / opened / accepted, reasons with an example,
#        empty-folder and subfolder hints) instead of the generic message.
#        Same sound as 1.2 for the same files and settings.
#   1.2  Shorter form: Comparison set, Export WAV and metadata, Output
#        folder and Output name removed (save from the Objects window).
#        The sound produced is unchanged.
#   1.1  Optional reverberation (per-source / global / both), Contained
#        or Extended tail, reverb-stage comparison A-D (level-matched),
#        reverb metadata and report; Comparison set is now a menu (None /
#        Mix and static fusion / Reverb stages / All). Reverb None gives
#        sample-identical output to 1.0. Band-level measurement uses soft
#        band edges (figure/report only).
#   1.0  First version.
#
# Output: one stereo Sound in the Objects window (save it from Praat).
# Source files are never copied or changed.
# ============================================================

form Spectral Gesture Forge
    comment === SOURCES (one recording is drawn from each folder) ===
    integer Folders_to_browse_(1-5) 1
    sentence Folder_paths_(optional;_separated_by_;)
    optionmenu Source_selection: 1
        option Random
        option Spectral complementarity
    comment === GESTURE ===
    positive Duration_(s) 4.5
    optionmenu Gesture_character: 1
        option Impact
        option Bloom
        option Reverse
        option Pulse
        option Hybrid
    real Envelope_sharpness_(%) 75
    real Spectral_variation_(%) 60
    real Spectral_fusion_strength_(%) 85
    comment === STEREO ===
    optionmenu Motion_preset: 3
        option Sweep
        option Converge
        option Expand
        option Oscillate
    real Stereo_width_(%) 70
    real Motion_amount_(%) 65
    comment === REVERBERATION ===
    optionmenu Reverb_mode: 1
        option None
        option Per-source
        option Global
        option Per-source + global
    real Reverb_amount_(%) 25
    real Average_reverb_decay_(s) 1.8
    optionmenu Tail_mode: 1
        option Contained
        option Extended
    boolean More_reverb_settings 0
    comment === OUTPUT ===
    integer Random_seed 1
    boolean Keep_result_in_Praat 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

sgfVersion$ = "1.3"
# No longer in the form (save the result from the Objects window);
# fixed here so the internal comparison and export code stays inert.
comparison_set = 1
export_WAV_and_metadata = 0
output_folder$ = ""
output_name$ = "SGF_gesture"
# reverb details (second dialog; these are its defaults)
reverb_decay_diversity = 50
pre_delay = 30
reverb_damping = 40
if more_reverb_settings
    beginPause: "Spectral Gesture Forge - reverb details"
        comment: "Per-source reverbs are drawn around the average decay (seeded)."
        real: "Reverb_decay_diversity_(%)", string$(reverb_decay_diversity)
        real: "Pre_delay_(ms)", string$(pre_delay)
        real: "Reverb_damping_(%)", string$(reverb_damping)
    clicked = endPause: "Continue", 1
endif
revName$[1] = "None"
revName$[2] = "Per-source"
revName$[3] = "Global"
revName$[4] = "Per-source + global"
tailName$[1] = "Contained"
tailName$[2] = "Extended"
stopwatch
charName$[1] = "Impact"
charName$[2] = "Bloom"
charName$[3] = "Reverse"
charName$[4] = "Pulse"
charName$[5] = "Hybrid"
motName$[1] = "Sweep"
motName$[2] = "Converge"
motName$[3] = "Expand"
motName$[4] = "Oscillate"
selName$[1] = "Random"
selName$[2] = "Spectral complementarity"

# ---- parameters ----
warnN = 0
gdur = duration
if gdur < 3 or gdur > 7
    gdur = max(3, min(7, gdur))
    warnN = warnN + 1
    warn$[warnN] = "Duration limited to " + fixed$(gdur, 1) + " s (allowed 3-7 s)."
endif
sharp = max(0, min(1, envelope_sharpness / 100))
varr = max(0, min(1, spectral_variation / 100))
fuse = max(0, min(1, spectral_fusion_strength / 100))
width = max(0, min(1, stereo_width / 100))
mAmt = max(0, min(1, motion_amount / 100))
character = gesture_character
pFuse = 1 - 0.85 * fuse
headroomDb = -1
# ---- reverberation switches ----
compMS = comparison_set = 2 or comparison_set = 4
compRV = comparison_set = 3 or comparison_set = 4
srcRev = reverb_mode = 2 or reverb_mode = 4
globRev = reverb_mode = 3 or reverb_mode = 4
wetNeeded = srcRev or compRV
globNeeded = globRev or compRV
extTail = tail_mode = 2 and (reverb_mode > 1 or compRV)
rvAmt = max(0, min(1, reverb_amount / 100))
rvAvg = max(0.2, min(5, average_reverb_decay))
if average_reverb_decay > 5 or average_reverb_decay < 0.2
    warnN = warnN + 1
    warn$[warnN] = "Average reverb decay limited to " + fixed$(rvAvg, 2) + " s (allowed 0.2-5 s)."
endif
rvDiv = max(0, min(1, reverb_decay_diversity / 100))
rvPre = max(0, min(0.2, pre_delay / 1000))
rvDamp = max(0, min(0.95, reverb_damping / 100))
# the longest per-source decay the settings allow (no randomness) fixes
# the explicit maximum tail: at most 4 s after the gesture
rvTmax = min(5, rvAvg * 2 ^ (1.5 * rvDiv) * 1.3)
tailMax = if extTail then min(4, 0.9 * rvTmax + 2 * rvPre + 0.2) else 0 fi
random_initializeWithSeedUnsafelyButPredictably (random_seed)

# objects made by this run (removed on failure / at the end)
tempN = 0
Create Sound from formula: "sgf_placeholder", 1, 0, 0.001, 1000, "0"
placeholderID = selected("Sound")
@addTemp: placeholderID

# Spectral bands: six log-spaced raised-cosine bands, centres 80 Hz to
# about 12 kHz (ratio 2.72 = 1.45 octaves). Rectangular edges (geometric
# midpoints) are used only for energy queries.
nBand = 6
for b from 1 to nBand
    bandC[b] = 80 * (12000 / 80) ^ ((b - 1) / 5)
endfor
bandW = log2(12000 / 80) / 5
for b from 1 to nBand - 1
    bandEdge[b] = sqrt(bandC[b] * bandC[b + 1])
endfor

# ============================================================
# 1. SOURCE FOLDERS
# ============================================================
writeInfoLine: "=== Spectral Gesture Forge v", sgfVersion$, " ==="
nFold = 0
@trimText: folder_paths$
pathsIn$ = trimText.out$
if pathsIn$ <> ""
    rest$ = pathsIn$ + ";"
    while index(rest$, ";") > 0 and nFold < 5
        p = index(rest$, ";")
        one$ = left$(rest$, p - 1)
        rest$ = mid$(rest$, p + 1, length(rest$) - p)
        @trimText: one$
        one$ = trimText.out$
        one$ = replace_regex$(one$, "^""|""$", "", 0)
        if one$ <> ""
            nFold = nFold + 1
            foldPath$[nFold] = one$
        endif
    endwhile
else
    nAsk = max(1, min(5, folders_to_browse))
    for f from 1 to nAsk
        one$ = chooseFolder$: "Spectral Gesture Forge: choose source folder " + string$(f) + " of " + string$(nAsk)
        if one$ <> ""
            nFold = nFold + 1
            foldPath$[nFold] = one$
        endif
    endfor
endif
if nFold = 0
    @fail: "No source folder given. Type folder paths (separated by ;) or choose folders."
endif
for f from 1 to nFold
    @absPath: foldPath$[f]
    p$ = absPath.out$
    foldPath$[f] = p$
    if folderExists(p$) = 0
        @fail: "Source folder not found: " + p$
    endif
    @baseName: p$
    foldName$[f] = baseName.out$
endfor

# ============================================================
# 2. SCAN, ANALYSE, SELECT
# ============================================================
# Each folder: list the audio files (WAV, AIFF, FLAC, MP3), take a
# seeded random order, analyse candidates until enough usable ones are
# found (Random: 1, Complementarity: 12; never more than 40 tried).
# Nothing is loaded whole: files are opened as LongSounds and only an
# analysis window (at most the first 30 s) is read.
appendInfoLine: "Scanning ", nFold, " folder(s) - selection: ", selName$[source_selection]
nAct = 0
catName$[1] = "cannot be opened"
catName$[2] = "not decodable"
catName$[3] = "shorter than 0.08 s"
catName$[4] = "silent / too quiet"
catName$[5] = "level not measurable"
for f from 1 to nFold
    @listAudio: foldPath$[f]
    nFiles = listAudio.n
    fFound[f] = nFiles
    fOpened[f] = 0
    fOK[f] = 0
    fTried[f] = 0
    for c from 1 to 5
        fCat[f, c] = 0
        fEx$[f, c] = ""
    endfor
    # what else the folder holds (for the diagnostics)
    fdEx$ = ""
    if listAudio.nOther > 0
        fdEx$ = fdEx$ + ", " + string$(listAudio.nOther) + " other file(s)"
    endif
    if listAudio.nHidden > 0
        fdEx$ = fdEx$ + ", " + string$(listAudio.nHidden) + " hidden skipped"
    endif
    if listAudio.nSub > 0
        fdEx$ = fdEx$ + ", " + string$(listAudio.nSub) + " subfolder(s) not searched"
    endif
    fExtra$[f] = fdEx$
    if nFiles = 0
        if listAudio.denied
            fHint$[f] = "Praat is NOT ALLOWED to read this folder (the listing was refused). Give Praat access "
                ... + "(macOS: System Settings > Privacy & Security > Files and Folders, or Full Disk Access) or move the recordings."
        elsif listAudio.nOther + listAudio.nHidden + listAudio.nSub = 0
            fHint$[f] = "Praat sees this folder as EMPTY. If Finder shows files in it, Praat is probably not allowed to read it "
                ... + "(macOS: System Settings > Privacy & Security > Files and Folders, or Full Disk Access, for Praat; "
                ... + "or move the recordings out of Desktop / Documents / Downloads / iCloud / external drives)."
        elsif listAudio.nSub > 0
            fHint$[f] = "No audio files directly in this folder; it has " + string$(listAudio.nSub)
                ... + " subfolder(s) - choose the folder that contains the recordings."
        else
            fHint$[f] = "No WAV, AIFF, FLAC or MP3 files here (" + string$(listAudio.nOther) + " other file(s))."
        endif
        warnN = warnN + 1
        warn$[warnN] = "Folder " + foldName$[f] + ": no audio files - skipped. " + fHint$[f]
        appendInfoLine: "  ", foldName$[f], ": no audio files", fdEx$, " - skipped"
    else
        fHint$[f] = ""
        # seeded shuffle (ascending Fisher-Yates)
        for i from 1 to nFiles
            ord[i] = i
        endfor
        for i from 1 to nFiles - 1
            j = randomInteger(i, nFiles)
            tmp = ord[i]
            ord[i] = ord[j]
            ord[j] = tmp
        endfor
        want = if source_selection = 1 then 1 else 12 fi
        nOK = 0
        nTried = 0
        nBad = 0
        while nOK < want and nTried < min(nFiles, 40)
            nTried = nTried + 1
            fp$ = listAudio.path$[ord[nTried]]
            @analyzeFile: fp$
            fOpened[f] = fOpened[f] + an.opened
            if an.ok = 0 and an.cat > 0
                fCat[f, an.cat] = fCat[f, an.cat] + 1
                if fEx$[f, an.cat] = ""
                    @baseName: fp$
                    fEx$[f, an.cat] = baseName.out$
                endif
            endif
            if an.ok
                nOK = nOK + 1
                cPath$[f, nOK] = fp$
                @baseName: fp$
                cName$[f, nOK] = baseName.out$
                cDur[f, nOK] = an.dur
                cSr[f, nOK] = an.sr
                cNch[f, nOK] = an.nch
                cNAtt[f, nOK] = an.nAtt
                for a from 1 to an.nAtt
                    cAtt[f, nOK, a] = an.att[a]
                endfor
                cCog[f, nOK] = an.cog
                cBw[f, nOK] = an.bw
                cTon[f, nOK] = an.tonal
                cPeakDb[f, nOK] = an.peakDb
                cUseCh[f, nOK] = an.useCh
                for b from 1 to nBand
                    cProf[f, nOK, b] = an.prof[b]
                endfor
            else
                nBad = nBad + 1
                @baseName: fp$
                if nBad <= 6
                    warnN = warnN + 1
                    warn$[warnN] = foldName$[f] + "/" + baseName.out$ + ": " + an.why$ + " - ignored."
                endif
            endif
        endwhile
        fTried[f] = nTried
        fOK[f] = nOK
        appendInfoLine: "  ", foldName$[f], ": ", nFiles, " audio file(s)", fExtra$[f], "; ", nTried, " tried, ",
            ... fOpened[f], " opened, ", nOK, " usable"
        for c from 1 to 5
            if fCat[f, c] > 0
                appendInfoLine: "      ", fCat[f, c], " x ", catName$[c], " (e.g. ", fEx$[f, c], ")"
            endif
        endfor
        if nOK = 0
            warnN = warnN + 1
            warn$[warnN] = "Folder " + foldName$[f] + ": no usable recording among " + string$(nTried) + " tried - skipped."
        else
            nAct = nAct + 1
            actFold[nAct] = f
            nCand[nAct] = nOK
        endif
    endif
endfor
if nAct = 0
    # say exactly what happened in every folder (also in the Info window)
    failMsg$ = "No usable recording was found. Per folder:"
    for f from 1 to nFold
        failMsg$ = failMsg$ + newline$ + newline$ + foldPath$[f] + newline$ + "  " + string$(fFound[f]) + " audio file(s)" + fExtra$[f]
        if fFound[f] > 0
            failMsg$ = failMsg$ + "; " + string$(fTried[f]) + " tried, " + string$(fOpened[f]) + " opened, 0 usable"
            for c from 1 to 5
                if fCat[f, c] > 0
                    failMsg$ = failMsg$ + newline$ + "  " + string$(fCat[f, c]) + " x " + catName$[c] + " (e.g. " + fEx$[f, c] + ")"
                endif
            endfor
            if fCat[f, 1] = fTried[f]
                failMsg$ = failMsg$ + newline$ + "  None of them could be opened by the script. If they open with Open > Read from file, "
                    ... + "Praat probably lacks permission to read this folder (macOS: System Settings > Privacy & Security > "
                    ... + "Files and Folders / Full Disk Access)."
            endif
        else
            failMsg$ = failMsg$ + newline$ + "  " + fHint$[f]
        endif
    endfor
    appendInfoLine: ""
    appendInfoLine: failMsg$
    @fail: failMsg$
endif

# ---- choose one candidate per active folder ----
for a from 1 to nAct
    selJ[a] = 1
endfor
selScore = undefined
if source_selection = 2
    # greedy coordinate ascent, 1 deterministic + 3 seeded random starts
    bestScore = -1e9
    for rs from 1 to 4
        for a from 1 to nAct
            if rs = 1
                bestE = -1
                for j from 1 to nCand[a]
                    @evenness: actFold[a], j
                    if evenness.h > bestE
                        bestE = evenness.h
                        selJ[a] = j
                    endif
                endfor
            else
                selJ[a] = randomInteger(1, nCand[a])
            endif
        endfor
        changed = 1
        sweep = 0
        while changed and sweep < 8
            changed = 0
            sweep = sweep + 1
            for a from 1 to nAct
                keepJ = selJ[a]
                bJ = keepJ
                bS = -1e9
                for j from 1 to nCand[a]
                    selJ[a] = j
                    @comboScore
                    if comboScore.s > bS + 1e-12
                        bS = comboScore.s
                        bJ = j
                    endif
                endfor
                selJ[a] = bJ
                if bJ <> keepJ
                    changed = 1
                endif
            endfor
        endwhile
        @comboScore
        if comboScore.s > bestScore + 1e-12
            bestScore = comboScore.s
            for a from 1 to nAct
                bestJ[a] = selJ[a]
            endfor
        endif
    endfor
    for a from 1 to nAct
        selJ[a] = bestJ[a]
    endfor
    @comboScore
    selScore = comboScore.s
    selContrast = comboScore.contrast
    selCoverage = comboScore.coverage
    selSpread = comboScore.spread
    selTonal = comboScore.tonal
else
    @comboScore
    selScore = comboScore.s
    selContrast = comboScore.contrast
    selCoverage = comboScore.coverage
    selSpread = comboScore.spread
    selTonal = comboScore.tonal
endif

# ============================================================
# 3. SOURCE PREPARATION
# ============================================================
nSrc = nAct
# common rate: 48 kHz if any chosen source is a 48 kHz-family recording
# at 32 kHz or more, otherwise 44.1 kHz (sources are resampled to it)
srOut = 44100
for k from 1 to nSrc
    f = actFold[k]
    j = selJ[k]
    if cSr[f, j] >= 32000 and (cSr[f, j] mod 8000) = 0
        srOut = 48000
    endif
endfor
nW = 1024
hop = nW / 4
nOut = round(gdur * srOut)
gdur = nOut / srOut
halfW = (nW / 2) / srOut
appendInfoLine: "Preparing ", nSrc, " source(s) at ", srOut, " Hz..."
for k from 1 to nSrc
    f = actFold[k]
    j = selJ[k]
    srcPath$[k] = cPath$[f, j]
    srcName$[k] = cName$[f, j]
    srcFold$[k] = foldName$[f]
    srcSrIn[k] = cSr[f, j]
    srcUseCh[k] = cUseCh[f, j]
    srcNchIn[k] = cNch[f, j]
    srcDurIn[k] = cDur[f, j]
    srcTon[k] = cTon[f, j]
    srcCog[k] = cCog[f, j]
    for b from 1 to nBand
        srcProf[k, b] = cProf[f, j, b]
    endfor
    # which attack: the strongest, or (with Spectral variation) another
    ai = 1
    if cNAtt[f, j] >= 2 and randomUniform(0, 1) < 0.5 * varr
        ai = randomInteger(2, cNAtt[f, j])
    endif
    srcAtt[k] = cAtt[f, j, ai]
    srcAttIdx[k] = ai
    @openAudio: srcPath$[k]
    if openAudio.id = 0
        @fail: "Cannot re-open " + srcPath$[k] + ": " + openAudio.why$
    endif
    t0 = srcAtt[k]
    t1 = min(srcDurIn[k], t0 + gdur + 0.6)
    selectObject: openAudio.id
    if openAudio.isLong
        Extract part: t0, t1, "no"
    else
        Extract part: t0, t1, "rectangular", 1, "no"
    endif
    part = selected("Sound")
    @addTemp: part
    removeObject: openAudio.id
    @dropTemp: openAudio.id
    selectObject: part
    nc = Get number of channels
    if nc > 1
        if srcUseCh[k] > 0 and srcUseCh[k] <= nc
            # phase-opposed channels: the strongest one, not the mix
            Extract one channel: srcUseCh[k]
        else
            Convert to mono
        endif
        mono = selected("Sound")
        @addTemp: mono
        removeObject: part
        @dropTemp: part
        part = mono
    endif
    if abs(srcSrIn[k] - srOut) > 0.5
        selectObject: part
        Resample: srOut, 50
        rs = selected("Sound")
        @addTemp: rs
        removeObject: part
        @dropTemp: part
        part = rs
    endif
    selectObject: part
    Rename: "sgf_src" + string$(k)
    # equal loudness of the sources over their first second
    lvEnd = Get total duration
    lvEnd = min(1, lvEnd)
    rmsK = Get root-mean-square: 0, lvEnd
    if rmsK = undefined or rmsK <= 0
        rmsK = 1e-9
    endif
    srcGain[k] = 0.1 / rmsK
    Formula: "self * " + string$(srcGain[k])
    srcID[k] = part
    srcN[k] = Get number of samples
    srcLen[k] = srcN[k] / srOut
    # frame time map: 1:1 for the first ta seconds (the attack), then a
    # slower read (rate >= 0.5) when the source is shorter than needed
    ta = min(0.3, 0.5 * gdur)
    usable = srcLen[k] - halfW
    srcTa[k] = ta
    srcRate[k] = 1
    srcEnd[k] = gdur
    if usable < gdur
        if usable <= ta
            srcTa[k] = max(0, usable)
            srcEnd[k] = max(0, usable)
        else
            srcRate[k] = max(0.5, min(1, (usable - ta) / (gdur - ta)))
            reach = ta + srcRate[k] * (gdur - ta)
            if reach > usable
                srcEnd[k] = ta + (usable - ta) / srcRate[k]
            endif
        endif
    endif
    # share of each band in this source (source-band weighting)
    totP = 0
    for b from 1 to nBand
        totP = totP + srcProf[k, b]
    endfor
    for b from 1 to nBand
        srcShare[k, b] = if totP > 0 then srcProf[k, b] / totP else 1 / nBand fi
    endfor
    appendInfoLine: "  ", k, ": ", srcFold$[k], "/", srcName$[k], "  attack at ", fixed$(srcAtt[k], 3), " s",
        ... "  material ", fixed$(srcLen[k], 2), " s",
        ... if srcRate[k] < 1 then "  read x" + fixed$(srcRate[k], 2) else "" fi,
        ... if srcEnd[k] < gdur then "  ends " + fixed$(srcEnd[k], 2) + " s" else "" fi
endfor

# ============================================================
# 4. ANALYSIS GRID AND BAND SHAPES
# ============================================================
nBin = nW / 2 + 1
dfBin = srOut / nW
nyq = srOut / 2
iFirst = -3
# with an extended tail the frame grid (and the output buffer) run on
# past the gesture; the direct envelopes are already zero there
nOutTot = nOut + round(tailMax * srOut)
iLast = ceiling(nOutTot / hop) + 3
nFr = iLast - iFirst + 1
for ii from 1 to nFr
    frT[ii] = (iFirst + ii - 1) * hop / srOut
endfor
# band shape matrix BM (row = band, col = FFT bin): raised cosine on a
# log2 axis, half width = one band spacing, so the six sum to 1; band 1
# is flat below its centre, band 6 flat above its centre; a 20-40 Hz
# high-pass (sine-squared ramp) removes DC and sub-bass.
bf$ = "((col - 1) * " + string$(dfBin) + ")"
hp$ = "(if " + bf$ + " < 20 then 0 else if " + bf$ + " < 40 then sin(pi / 2 * (" + bf$ + " - 20) / 20)^2 else 1 fi fi)"
for b from 1 to nBand
    sh$ = "cos(pi / 2 * log2(" + bf$ + " / " + string$(bandC[b]) + ") / " + string$(bandW) + ")^2"
    if b = 1
        bs$[b] = "(if " + bf$ + " <= " + string$(bandC[1]) + " then 1 else if " + bf$ + " < " + string$(bandC[2])
            ... + " then " + sh$ + " else 0 fi fi) * " + hp$
    elsif b = nBand
        bs$[b] = "(if " + bf$ + " >= " + string$(bandC[b]) + " then 1 else if " + bf$ + " > " + string$(bandC[b - 1])
            ... + " then " + sh$ + " else 0 fi fi)"
    else
        bs$[b] = "(if " + bf$ + " > " + string$(bandC[b - 1]) + " and " + bf$ + " < " + string$(bandC[b + 1])
            ... + " then " + sh$ + " else 0 fi)"
    endif
endfor
bm$ = bs$[nBand]
for bb from 1 to nBand - 1
    b = nBand - bb
    bm$ = "if row = " + string$(b) + " then " + bs$[b] + " else " + bm$ + " fi"
endfor
Create simple Matrix: "sgf_bands", nBand, nBin, bm$
bmID = selected("Matrix")
@addTemp: bmID
for b from 1 to nBand
    bandLo[b] = if b = 1 then 0 else bandEdge[b - 1] fi
    bandHi[b] = if b = nBand then nyq else min(nyq, bandEdge[b]) fi
endfor

# ============================================================
# 5. THE 30 SOURCE-BAND ENVELOPES
# ============================================================
# Per band b (u = 0 low ... 1 high) the character sets the shape; per
# source k the timing and level vary around it (Spectral variation) and
# the level follows the source's own energy in that band. All times
# are in seconds; sharpness s shortens attacks/decays (ts) and steepens
# the decay curves (kc). Every envelope reaches 0 at the end.
ts = 1.6 - 1.2 * sharp
kc = 1.5 + 8 * sharp
dScale = sqrt(gdur / 4.5)
# band level profile of each behaviour (low ... high band)
profTxt$[1] = "1.00 1.00 0.90 0.80 0.75 0.70"
profTxt$[2] = "0.90 1.00 1.00 0.95 0.90 0.85"
profTxt$[3] = "1.00 1.00 1.00 1.00 1.00 0.90"
profTxt$[4] = "1.00 0.95 0.90 0.90 0.85 0.80"
for c from 1 to 4
    for b from 1 to nBand
        bProfV[c, b] = extractNumber(" " + profTxt$[c], "")
        profTxt$[c] = replace_regex$(profTxt$[c], "^ *[0-9.]+ *", "", 1)
    endfor
endfor
# shared draws: Reverse peak time, Pulse pulse times and amplitudes
revTp = gdur * (0.76 + 0.06 * varr * randomUniform(-1, 1))
pulN = if randomUniform(0, 1) < 0.5 + 0.3 * varr then 3 else 2 fi
pulGap = max(0.12, min(0.45, gdur * (0.07 + 0.04 * randomUniform(0, 1))))
pulT[1] = 0
pulT[2] = pulGap
pulT[3] = pulGap * (2 + 0.25 * randomUniform(-1, 1))
pulA[1] = 1
pulA[2] = 0.75 + 0.2 * randomUniform(0, 1)
pulA[3] = 0.85 + 0.15 * randomUniform(0, 1)
# band types (Hybrid mixes the four behaviours across the bands)
for b from 1 to nBand
    bType[b] = character
endfor
if character = 5
    nDiff = 0
    while nDiff < 3
        for b from 1 to nBand
            bType[b] = randomInteger(1, 4)
        endfor
        bType[1] = randomInteger(1, 2)
        nDiff = 0
        for t from 1 to 4
            has = 0
            for b from 1 to nBand
                if bType[b] = t
                    has = 1
                endif
            endfor
            nDiff = nDiff + has
        endfor
    endwhile
endif
for b from 1 to nBand
    u = (b - 1) / (nBand - 1)
    bt = bType[b]
    bLev[b] = bProfV[bt, b]
    for k from 1 to nSrc
        kb = (k - 1) * nBand + b
        jt = exp(varr * randomGauss(0, 0.30))
        jd = varr * randomUniform(0, 0.025)
        eType[kb] = bt
        eNP[kb] = 1
        eRes[kb] = 0
        eResD[kb] = 0.3
        eSusB[kb] = 0
        if bt = 1
            # Impact: immediate, complex burst; strong low body; highs flash
            eDel[kb] = ts * 0.012 * sin(pi * u) + jd
            eAtt[kb] = max(0.001, ts * (0.002 + 0.006 * (1 - u)) * jt)
            eAc[kb] = 1
            eDec[kb] = max(0.02, ts * dScale * (0.45 * (1 - u) + 0.05 * u) * jt)
            eKd[kb] = kc
            eSus[kb] = 0.30 * (1 - u) ^ 1.5 + 0.01
            eRel0[kb] = eDel[kb] + eAtt[kb] + eDec[kb] + gdur * 0.15
            eRelD[kb] = max(0.05, gdur - eRel0[kb])
            eKr[kb] = kc * 0.6
        elsif bt = 2
            # Bloom: quick low/mid onset, highs emerge and widen, long
            # resonant decay (lows last longest)
            eDel[kb] = if u > 0.3 then gdur * 0.11 * (u - 0.3) / 0.7 * jt else 0 fi + jd
            eAtt[kb] = max(0.004, if u > 0.3 then ts * gdur * (0.05 + 0.12 * u) * jt else ts * 0.015 * jt fi)
            eAc[kb] = if u > 0.3 then 1.8 else 1 fi
            eDec[kb] = max(0.05, ts * 0.25 * jt)
            eKd[kb] = kc * 0.6
            eSus[kb] = 0.55 + 0.1 * (1 - u)
            eRel0[kb] = max(eDel[kb] + eAtt[kb] + eDec[kb], gdur * (0.40 + 0.15 * (1 - u)))
            eRelD[kb] = max(0.05, gdur - eRel0[kb])
            eKr[kb] = max(0.8, kc * 0.45)
        elsif bt = 3
            # Reverse: accelerating accumulation (lows first) to one sharp
            # peak, sudden release; a little low resonance remains
            eDel[kb] = revTp * 0.35 * u * jt + jd
            eAtt[kb] = max(0.05, revTp - eDel[kb])
            eAc[kb] = 2.2 + 2 * sharp
            eDec[kb] = 0.05
            eKd[kb] = kc
            eSus[kb] = 1
            eRel0[kb] = eDel[kb] + eAtt[kb]
            eRelD[kb] = max(0.012, ts * (0.03 + 0.05 * (1 - u)) * jt)
            eKr[kb] = kc
            eRes[kb] = 0.10 * (1 - u) ^ 2
            eResD[kb] = 0.45 * dScale
        else
            # Pulse: two or three closely related impulses, then one release
            eNP[kb] = pulN
            eDel[kb] = 0.008 * u * varr * randomUniform(0, 1) + jd * 0.3
            eAtt[kb] = max(0.001, ts * (0.002 + 0.004 * (1 - u)) * jt)
            eAc[kb] = 1
            eDec[kb] = max(0.02, ts * (0.08 + 0.15 * (1 - u)) * jt)
            eKd[kb] = kc
            eSusB[kb] = 0.08
            eSus[kb] = 0.15 * (1 - u) + 0.02
            for jj from 1 to pulN
                ePT[kb, jj] = pulT[jj] * (1 + 0.04 * varr * randomUniform(-1, 1))
                ePA[kb, jj] = pulA[jj] * (1 + 0.15 * varr * randomUniform(-1, 1))
                if jj = 2 and u > 0.25 and u < 0.75
                    ePA[kb, jj] = ePA[kb, jj] * 1.15
                endif
            endfor
            ePT[kb, 1] = 0
            lastP = ePT[kb, pulN]
            eRel0[kb] = eDel[kb] + lastP + eAtt[kb] + eDec[kb]
            eRelD[kb] = max(0.05, gdur - eRel0[kb])
            eKr[kb] = kc * 0.5
        endif
        # level: source's share of this band (complementary sources lead
        # different bands), varied, normalised below
        eLev[kb] = (srcShare[k, b] + 0.02) ^ 0.6 * exp(varr * randomGauss(0, 0.35))
    endfor
    # within a band: sum of squares = band level^2
    ss = 0
    for k from 1 to nSrc
        ss = ss + eLev[(k - 1) * nBand + b] ^ 2
    endfor
    for k from 1 to nSrc
        kb = (k - 1) * nBand + b
        eLev[kb] = bLev[b] * eLev[kb] / sqrt(max(ss, 1e-12))
    endfor
endfor

# envelope table on the frame grid
for ii from 1 to nFr
    for kb from 1 to nSrc * nBand
        @envAt: kb, frT[ii]
        envT[kb, ii] = envAt.v
    endfor
endfor
# first peak of each band (for the transient spread) and the planned
# band curve (for the figure)
for b from 1 to nBand
    bandPk[b] = 0
    mx = -1
    for ii from 1 to nFr
        s = 0
        for k from 1 to nSrc
            s = s + envT[(k - 1) * nBand + b, ii] ^ 2
        endfor
        planEnv[b, ii] = sqrt(s)
        if planEnv[b, ii] > mx * 1.0001 and frT[ii] < gdur * 0.95
            mx = planEnv[b, ii]
            bandPk[b] = frT[ii]
        endif
    endfor
endfor

# ============================================================
# 6. STEREO TRAJECTORIES
# ============================================================
# position p in [-1, 1] of every source-band contribution per frame:
#   p = global(t) + width * sigma_b * delta_kb * spread(t) * (1 + 0.6 u f_b(t))
# sigma_b = 0.15 + 0.85 u^0.7: low band 0.15 ... high band 1 - lows stay central;
# delta_kb: side of band b (alternating across bands) +/- 0.3 per source;
# f_b(t): 1 while band b attacks, then exp(-(t - peak)/0.12) - highs
#         spread outward on their own transient;
# global/spread follow the Motion preset, scaled by Motion amount.
motDir = if randomUniform(0, 1) < 0.5 then -1 else 1 fi
oscCyc = 1.25 * (1 + 0.3 * varr * randomUniform(-1, 1))
oscPh = randomUniform(0, 2 * pi)
# each band has its own side (alternating, first side drawn), and the
# sources of a band sit slightly around it - so spectral regions, not
# sources, occupy the stereo field
bandSide1 = if randomUniform(0, 1) < 0.5 then -1 else 1 fi
for b from 1 to nBand
    deltaB[b] = bandSide1 * (if (b mod 2) = 0 then 1 else -1 fi) * (0.7 + 0.3 * randomUniform(0, 1))
endfor
for k from 1 to nSrc
    for b from 1 to nBand
        kb = (k - 1) * nBand + b
        delta[kb] = deltaB[b] + 0.3 * randomUniform(-1, 1)
    endfor
endfor
for ii from 1 to nFr
    tt = max(0, min(1, frT[ii] / gdur))
    # motion curve by character: fast early (Impact, Pulse), smooth
    # (Bloom, Hybrid), late (Reverse)
    if character = 1 or character = 4
        shp = 1 - (1 - tt) ^ 2.2
    elsif character = 3
        shp = tt ^ 2
    else
        shp = tt * tt * (3 - 2 * tt)
    endif
    gpos = 0
    spr = 1
    osc = 0
    if motion_preset = 1
        gpos = motDir * mAmt * (-0.8 + 1.6 * shp)
        spr = 0.6
    elsif motion_preset = 2
        spr = 1 - mAmt * shp
    elsif motion_preset = 3
        spr = (1 - mAmt) + mAmt * shp
    else
        gpos = mAmt * 0.75 * sin(2 * pi * oscCyc * shp + oscPh) * (1 - 0.3 * tt)
        spr = 0.6
        osc = 1
    endif
    gPos[ii] = gpos
    for b from 1 to nBand
        u = (b - 1) / (nBand - 1)
        sig = 0.15 + 0.85 * u ^ 0.7
        if frT[ii] <= bandPk[b]
            fr = 1
        else
            fr = exp(-(frT[ii] - bandPk[b]) / 0.12)
        endif
        for k from 1 to nSrc
            kb = (k - 1) * nBand + b
            pp = gpos + width * sig * delta[kb] * spr * (1 + 0.6 * u * fr)
            if osc
                pp = pp + 0.25 * mAmt * width * sig * sin(2 * pi * oscCyc * shp + oscPh + 0.8 * b)
            endif
            pp = max(-1, min(1, pp))
            posT[kb, ii] = pp
        endfor
    endfor
endfor

# ============================================================
# 6b. REVERBERATION (only when used)
# ============================================================
# Runs after every random draw above, from its own seed, so the source
# choice, regions, envelopes and trajectories are the same with or
# without reverb, whatever its settings.
nMemAll = nSrc
if wetNeeded or globNeeded
    @reverbSetup
endif

# ============================================================
# 7. RENDERING
# ============================================================
# persistent scratch objects (re-used every frame); "members" are the
# sources (dry) and, with per-source reverb, their wet signals
for k from 1 to nMemAll
    Create Sound from formula: "sgf_frame" + string$(k), 1, 0, nW / srOut, srOut, "0"
    frID[k] = selected("Sound")
    @addTemp: frID[k]
endfor
Create simple Matrix: "sgf_mag", nMemAll, nBin, "0"
magID = selected("Matrix")
@addTemp: magID
Create simple Matrix: "sgf_w0", nMemAll, nBin, "0"
w0ID = selected("Matrix")
@addTemp: w0ID
Create simple Matrix: "sgf_wl", nMemAll, nBin, "0"
wlID = selected("Matrix")
@addTemp: wlID
Create simple Matrix: "sgf_wr", nMemAll, nBin, "0"
wrID = selected("Matrix")
@addTemp: wrID
# inter-channel phase offset phi(f) = width * 80 deg * u(f), u = 0 in
# the low band ... 1 in the high band (smooth over the band shapes);
# L gets +phi/2, R -phi/2. Lows keep one phase (mono-safe bass), highs
# gain decorrelation; worst mono fold-down of a band is cos(phi/2).
rotPhiMax = width * 80 * pi / 180
rotU$ = "(0"
for b from 2 to nBand
    rotU$ = rotU$ + " + " + string$((b - 1) / (nBand - 1)) + " * object[" + string$(bmID) + ", " + string$(b) + ", col]"
endfor
rotU$ = rotU$ + ")"
Create simple Matrix: "sgf_rot", 2, nBin, "if row = 1 then cos(" + string$(rotPhiMax / 2) + " * " + rotU$ + ") else sin(" + string$(rotPhiMax / 2) + " * " + rotU$ + ") fi"
rotID = selected("Matrix")
@addTemp: rotID
Create simple Matrix: "sgf_ph", 1, nBin, "0"
phID = selected("Matrix")
@addTemp: phID
selectObject: frID[1]
To Spectrum: "yes"
zsID = selected("Spectrum")
Rename: "sgf_zs"
@addTemp: zsID
Copy: "sgf_ref"
refID = selected("Spectrum")
@addTemp: refID
Copy: "sgf_out"
outSpID = selected("Spectrum")
@addTemp: outSpID

objBase$ = "SGF_" + charName$[character] + "_seed" + string$(random_seed)
for ii from 1 to nFr
    for b from 1 to nBand
        tgtE[b, ii] = 0
    endfor
endfor
cmpSuf$[1] = "A_dry"
cmpSuf$[2] = "B_source"
cmpSuf$[3] = "C_global"
cmpSuf$[4] = "D_both"
tRender = 0
nMainMem = if srcRev then nMemAll else nSrc fi
nMainOut = if extTail and reverb_mode > 1 then nOutTot else nOut fi
@renderFusion: 1, nMainMem, 1, nMainOut
fullID = renderFusion.id
capFull = renderFusion.capped
lowFull = renderFusion.lowGuarded
wetGateCut = renderFusion.wetCut
# keep the fusion before the global reverb for the A-D comparison
preMainID = 0
if compRV
    selectObject: fullID
    Copy: "sgf_premain"
    preMainID = selected("Sound")
    @addTemp: preMainID
endif
if globRev
    appendInfoLine: "Global reverb on the stereo fusion..."
    @applyGlobal: fullID, if srcRev then 0.6 * rvAmt else rvAmt fi
    removeObject: fullID
    fullID = applyGlobal.id
endif
if extTail and reverb_mode > 1
    @trimTail: fullID
    removeObject: fullID
    fullID = trimTail.id
endif
selectObject: fullID
Rename: objBase$
selectObject: fullID
outDurMain = Get total duration
nOutMain = Get number of samples
tRender = stopwatch
staticID = 0
mixID = 0
for q from 1 to 4
    cmpID[q] = 0
endfor
if compRV
    @renderComparisonsRV
endif
if compMS
    appendInfoLine: "Comparison: static fusion (same envelopes, no stereo motion)..."
    @renderFusion: 2, nSrc, 0, nOut
    staticID = renderFusion.id
    selectObject: staticID
    Rename: objBase$ + "_static"
    appendInfoLine: "Comparison: conventional mix (same regions, broadband envelopes)..."
    @renderMix
    mixID = renderMix.id
    selectObject: mixID
    Rename: objBase$ + "_mix"
endif
for k from 1 to nMemAll
    removeObject: frID[k]
    @dropTemp: frID[k]
endfor

# ============================================================
# 8. NORMALISATION AND MEASUREMENT
# ============================================================
@finishOutput: fullID
fullGainDb = finishOutput.gainDb
if compMS
    @finishOutput: staticID
    staticGainDb = finishOutput.gainDb
    @finishOutput: mixID
    mixGainDb = finishOutput.gainDb
endif
@measureStereo: fullID
mPeakDb = measureStereo.peakDb
mRmsDb = measureStereo.rmsDb
mMonoLoss = measureStereo.monoLoss
mCorr = measureStereo.corr
mPosMin = measureStereo.posMin
mPosMax = measureStereo.posMax
mWidthMin = measureStereo.widthMin
mWidthMax = measureStereo.widthMax
mWidthHiMin = measureStereo.widthHiMin
mWidthHiMax = measureStereo.widthHiMax
mWidthHiMean = measureStereo.widthHiMean
mDurOK = measureStereo.nSamp = nOutMain
for w from 1 to measureStereo.nWin
    figPos[w] = mwPos[w]
    figWid[w] = mwWid[w]
    figT[w] = mwT[w]
endfor
figNWin = measureStereo.nWin
@measureBands: fullID
envCorrMean = measureBands.corrMean
envCorrMin = measureBands.corrMin
if compRV
    for q from 1 to 4
        @measureStereo: cmpID[q]
        cmpPeak[q] = measureStereo.peakDb
        cmpRms[q] = measureStereo.rmsDb
        cmpMono[q] = measureStereo.monoLoss
        cmpWid[q] = measureStereo.widthHiMean
        cmpDur[q] = measureStereo.nSamp / srOut
        cmpPosR[q] = measureStereo.posMax - measureStereo.posMin
    endfor
endif
if compMS
    @measureStereo: staticID
    sMonoLoss = measureStereo.monoLoss
    sCorr = measureStereo.corr
    sWidthMax = measureStereo.widthMax
    sWidthHiMean = measureStereo.widthHiMean
    @measureStereo: mixID
    xMonoLoss = measureStereo.monoLoss
    xCorr = measureStereo.corr
    xWidthHiMean = measureStereo.widthHiMean
endif
tAll = tRender + stopwatch

# ============================================================
# 9. EXPORT (only when asked)
# ============================================================
nSaved = 0
if export_WAV_and_metadata
    @trimText: output_folder$
    outDir$ = trimText.out$
    if outDir$ = ""
        outDir$ = chooseFolder$: "Spectral Gesture Forge: folder for the WAV and metadata"
    endif
    @trimText: outDir$
    outDir$ = trimText.out$
    if outDir$ <> ""
        @absPath: outDir$
        outDir$ = absPath.out$
    endif
    if outDir$ = ""
        warnN = warnN + 1
        warn$[warnN] = "No output folder chosen - nothing was saved."
    elsif folderExists(outDir$) = 0
        warnN = warnN + 1
        warn$[warnN] = "Output folder not found (" + outDir$ + ") - nothing was saved."
    else
        isSrc = 0
        for f from 1 to nFold
            if foldPath$[f] = outDir$
                isSrc = 1
            endif
        endfor
        if isSrc
            warnN = warnN + 1
            warn$[warnN] = "The output folder is a source folder - nothing was saved (saved files would become sources)."
        else
            if praatVersion >= 7000
                if askForTrust() = 0
                    @fail: "Saving files needs your permission in Praat 7 (nothing was written)."
                endif
            endif
            @trimText: output_name$
            nm$ = replace_regex$(trimText.out$, "[\\/:*?""<>|]", "_", 0)
            if nm$ = ""
                nm$ = "SGF_gesture"
            endif
            # never overwrite: the first free name of name, name_2, ...
            base$ = outDir$ + "/" + nm$
            sfx = 1
            @nameFree: base$
            while nameFree.ok = 0 and sfx < 999
                sfx = sfx + 1
                base$ = outDir$ + "/" + nm$ + "_" + string$(sfx)
                @nameFree: base$
            endwhile
            @saveWav: fullID, base$ + ".wav"
            if compMS
                @saveWav: staticID, base$ + "_static.wav"
                @saveWav: mixID, base$ + "_mix.wav"
            endif
            if compRV
                for q from 1 to 4
                    @saveWav: cmpID[q], base$ + "_" + cmpSuf$[q] + ".wav"
                endfor
            endif
            @writeMetadata: base$ + "_metadata.txt"
        endif
    endif
endif

# ============================================================
# 10. FIGURE
# ============================================================
if draw_visualization
    @drawFigure
endif

# ============================================================
# 11. REPORT
# ============================================================
@report

# ---- clean up: only the results stay ----
for k from 1 to tempN
    if tempID[k] > 0
        nocheck removeObject: tempID[k]
    endif
endfor
if play_result
    selectObject: fullID
    Play
endif
if keep_result_in_Praat = 0
    removeObject: fullID
    if staticID > 0
        removeObject: staticID
    endif
    if mixID > 0
        removeObject: mixID
    endif
    for q from 1 to 4
        if cmpID[q] > 0
            removeObject: cmpID[q]
        endif
    endfor
else
    selectObject: fullID
    if staticID > 0
        plusObject: staticID
    endif
    if mixID > 0
        plusObject: mixID
    endif
    for q from 1 to 4
        if cmpID[q] > 0
            plusObject: cmpID[q]
        endif
    endfor
endif

# ============================================================
# PROCEDURES
# ============================================================

procedure addTemp: .id
    tempN = tempN + 1
    tempID[tempN] = .id
endproc

procedure dropTemp: .id
    for .i from 1 to tempN
        if tempID[.i] = .id
            tempID[.i] = 0
        endif
    endfor
endproc

procedure fail: .msg$
    for .i from 1 to tempN
        if tempID[.i] > 0
            nocheck removeObject: tempID[.i]
        endif
    endfor
    exitScript: .msg$
endproc

procedure trimText: .s$
    .s$ = replace_regex$(.s$, "^[ \t]+", "", 0)
    trimText.out$ = replace_regex$(.s$, "[ \t]+$", "", 0)
endproc

# absolute path with forward slashes and no trailing slash, so folders
# can be compared (a source folder is never used for output) and the
# metadata stays valid from any working directory
procedure absPath: .p$
    .p$ = replace$(.p$, "\", "/", 0)
    if left$(.p$, 1) <> "/" and mid$(.p$, 2, 1) <> ":"
        .p$ = replace$(defaultDirectory$, "\", "/", 0) + "/" + .p$
    endif
    .p$ = replace$(.p$, "/./", "/", 0)
    while right$(.p$, 1) = "/" and length(.p$) > 1
        .p$ = left$(.p$, length(.p$) - 1)
    endwhile
    absPath.out$ = .p$
endproc

procedure baseName: .p$
    .p$ = replace$(.p$, "\", "/", 0)
    baseName.out$ = replace_regex$(.p$, "^.*/", "", 0)
endproc

# All audio files of a folder (not its subfolders), sorted. v1.3: one
# listing of every file ("*", which Praat returns without folders),
# then the extension is compared case-insensitively in the script -
# .wav .WAV .Aif .aIFF ... all count, the file name itself is never
# changed. Hidden files (names starting with ".") are skipped, among
# them the "._name.wav" companions macOS writes on USB drives, which
# match *.wav but are not audio. Also counted for the diagnostics:
# other files and subfolders.
procedure listAudio: .dir$
    listAudio.n = 0
    listAudio.nOther = 0
    listAudio.nHidden = 0
    listAudio.nSub = 0
    listAudio.denied = 0
    # a folder Praat may not read makes the listing itself fail: caught
    selectObject: placeholderID
    nocheck Create Strings as file list: "sgf_list", .dir$ + "/*"
    @takeNew: "Strings"
    .sl = takeNew.id
    if .sl = 0
        listAudio.denied = 1
        Create Strings as tokens: "", " "
        .sl = selected("Strings")
    endif
    selectObject: .sl
    .ns = Get number of strings
    .nk = 0
    for .i from 1 to .ns
        .s$ = Get string: .i
        if left$(.s$, 1) = "."
            listAudio.nHidden = listAudio.nHidden + 1
        else
            .dot = rindex(.s$, ".")
            .ext$ = ""
            if .dot > 0
                .ext$ = right$(.s$, length(.s$) - .dot)
                .ext$ = replace_regex$(.ext$, "([A-Z])", "\L\1", 0)
            endif
            if .ext$ = "wav" or .ext$ = "aif" or .ext$ = "aiff" or .ext$ = "aifc" or .ext$ = "flac" or .ext$ = "mp3"
                .nk = .nk + 1
                .all$[.nk] = .s$
            else
                listAudio.nOther = listAudio.nOther + 1
            endif
        endif
    endfor
    removeObject: .sl
    selectObject: placeholderID
    nocheck Create Strings as directory list: "sgf_dirs", .dir$ + "/*"
    @takeNew: "Strings"
    .sd = takeNew.id
    if .sd = 0
        Create Strings as tokens: "", " "
        .sd = selected("Strings")
    endif
    selectObject: .sd
    .nd = Get number of strings
    for .i from 1 to .nd
        .s$ = Get string: .i
        if left$(.s$, 1) <> "."
            listAudio.nSub = listAudio.nSub + 1
        endif
    endfor
    removeObject: .sd
    if .nk > 0
        # sort via a Strings object (platform-independent order)
        Create Strings as tokens: "x", " "
        .so = selected("Strings")
        for .i from 1 to .nk
            if .i = 1
                Set string: 1, .all$[1]
            else
                Insert string: 0, .all$[.i]
            endif
        endfor
        Sort
        for .i from 1 to .nk
            .s$ = Get string: .i
            listAudio.n = listAudio.n + 1
            listAudio.path$[listAudio.n] = .dir$ + "/" + .s$
        endfor
        removeObject: .so
    endif
endproc

# Open a file without loading it: LongSound, or (formats a LongSound
# cannot stream) a Sound. openAudio.id = 0 if it cannot be opened, with
# the reason in openAudio.why$. v1.3: the new object is identified by
# type after every nocheck command (nothing else is assumed about the
# selection), and any stray object a failed command left is removed.
procedure openAudio: .path$
    openAudio.id = 0
    openAudio.isLong = 1
    openAudio.why$ = ""
    if fileReadable(.path$) = 0
        openAudio.why$ = "listed but cannot be read (no permission, or the file has gone)"
    else
        selectObject: placeholderID
        nocheck Open long sound file: .path$
        @takeNew: "LongSound"
        if takeNew.id > 0
            openAudio.id = takeNew.id
        else
            selectObject: placeholderID
            nocheck Read from file: .path$
            @takeNew: "Sound"
            if takeNew.id > 0
                openAudio.id = takeNew.id
                openAudio.isLong = 0
            else
                openAudio.why$ = "found, but Praat could not open it (not a supported audio format?)"
            endif
        endif
    endif
    if openAudio.id > 0
        @addTemp: openAudio.id
    endif
endproc

# After a nocheck command run with only the placeholder selected: the
# first new selected object of type .type$ (0 if none). Every other new
# object is removed; the selection is left on the result or the
# placeholder - never empty.
procedure takeNew: .type$
    takeNew.id = 0
    .n = numberOfSelected()
    for .i from 1 to .n
        .sel[.i] = selected(.i)
    endfor
    for .i from 1 to .n
        .obj = .sel[.i]
        if .obj <> placeholderID
            selectObject: .obj
            .t$ = extractWord$(selected$(), "")
            if .t$ = .type$ and takeNew.id = 0
                takeNew.id = .obj
            else
                removeObject: .obj
            endif
        endif
    endfor
    if takeNew.id > 0
        selectObject: takeNew.id
    else
        selectObject: placeholderID
    endif
endproc

# Analysis of one candidate (at most its first 30 s): attacks, spectral
# centroid and bandwidth, energy in the six bands, tonality.
#   v1.3: every rejection has a category (an.cat) for the diagnostics:
#   1 not readable / not openable, 2 opened but not decodable,
#   3 too short, 4 too quiet, 5 level not measurable. The level test
#   uses the strongest channel; when the mono mix of a multichannel file
#   loses more than 12 dB (phase-opposed channels) that channel is also
#   used as the source (an.useCh), not the cancelled mix.
procedure analyzeFile: .path$
    an.ok = 0
    an.why$ = ""
    an.cat = 0
    an.opened = 0
    an.nAtt = 0
    an.useCh = 0
    @openAudio: .path$
    if openAudio.id = 0
        an.why$ = openAudio.why$
        an.cat = 1
    else
        an.opened = 1
        .oid = openAudio.id
        selectObject: .oid
        an.dur = Get total duration
        if an.dur = undefined or an.dur < 0.08
            an.why$ = "shorter than 0.08 s"
            an.cat = 3
        else
            .aEnd = min(an.dur, 30)
            selectObject: .oid
            if openAudio.isLong
                nocheck Extract part: 0, .aEnd, "no"
            else
                nocheck Extract part: 0, .aEnd, "rectangular", 1, "no"
            endif
            .snd = 0
            if numberOfSelected("Sound") = 1
                if selected("Sound") <> .oid
                    .snd = selected("Sound")
                endif
            endif
            if .snd = 0
                an.why$ = "opened, but its samples could not be read"
                an.cat = 2
            endif
        endif
        if an.cat = 0
            @addTemp: .snd
            selectObject: .snd
            # (a LongSound has no rate or channel query: read them here)
            an.sr = Get sampling frequency
            an.nch = Get number of channels
            # the strongest channel decides whether the file is silent
            .pk = Get absolute extremum: 0, 0, "None"
            if an.nch > 1
                Convert to mono
                .m = selected("Sound")
                @addTemp: .m
                .pkm = Get absolute extremum: 0, 0, "None"
                if .pk <> undefined and .pkm <> undefined and .pkm < 0.25 * .pk
                    # channels cancel in the mix: use the strongest one
                    removeObject: .m
                    @dropTemp: .m
                    .best = 0
                    for .c from 1 to an.nch
                        selectObject: .snd
                        Extract one channel: .c
                        .ch = selected("Sound")
                        .pc = Get absolute extremum: 0, 0, "None"
                        removeObject: .ch
                        if .pc <> undefined and .pc > .best
                            .best = .pc
                            an.useCh = .c
                        endif
                    endfor
                    selectObject: .snd
                    Extract one channel: an.useCh
                    .m = selected("Sound")
                    @addTemp: .m
                endif
                removeObject: .snd
                @dropTemp: .snd
                .snd = .m
            endif
            selectObject: .snd
            if .pk = undefined
                an.why$ = "its level could not be measured"
                an.cat = 5
                an.peakDb = undefined
            else
                an.peakDb = 20 * log10(max(.pk, 1e-12))
            endif
            if an.cat = 0 and .pk < 0.001
                an.why$ = "silent or nearly silent (peak " + fixed$(an.peakDb, 0) + " dBFS)"
                an.cat = 4
            elsif an.cat = 0
                # attacks: largest 30 ms intensity rises within 25 dB of
                # the maximum, at least 0.25 s apart (up to three)
                if .aEnd >= 0.1
                    To Intensity: 100, 0.01, "yes"
                    .int = selected("Intensity")
                    .nf = Get number of frames
                    .imax = -300
                    for .i from 1 to .nf
                        .v = Get value in frame: .i
                        if .v = undefined
                            .v = -300
                        endif
                        .iv[.i] = .v
                        .it[.i] = Get time from frame number: .i
                        .imax = max(.imax, .v)
                    endfor
                    removeObject: .int
                    .nc = 0
                    # an attack must leave material after it: at least
                    # min(1.2 s, 60 % of the file); later ones rank last
                    .needAfter = min(1.2, 0.6 * an.dur)
                    for .i from 4 to .nf
                        .rise = .iv[.i] - .iv[.i - 3]
                        .okL = 1
                        if .i < .nf
                            if .iv[.i + 1] - .iv[.i - 2] > .rise
                                .okL = 0
                            endif
                        endif
                        if .iv[.i] - .iv[.i - 1] < 0
                            .okL = 0
                        endif
                        if .okL and .rise >= 6 and .iv[.i] >= .imax - 25
                            .nc = .nc + 1
                            .cs[.nc] = .rise + 0.3 * (.iv[.i] - .imax + 25)
                            .ct[.nc] = max(0, .it[.i - 3] - 0.015)
                            if an.dur - .ct[.nc] < .needAfter
                                .cs[.nc] = .cs[.nc] - 1000
                            endif
                        endif
                    endfor
                    # pick the best three, 0.25 s apart
                    for .pick from 1 to 3
                        .bi = 0
                        .bs = -1e9
                        for .c from 1 to .nc
                            if .cs[.c] > .bs
                                .far = 1
                                for .q from 1 to an.nAtt
                                    if abs(.ct[.c] - an.att[.q]) < 0.25
                                        .far = 0
                                    endif
                                endfor
                                if .far
                                    .bs = .cs[.c]
                                    .bi = .c
                                endif
                            endif
                        endfor
                        if .bi > 0
                            an.nAtt = an.nAtt + 1
                            an.att[an.nAtt] = .ct[.bi]
                            .cs[.bi] = -1e9
                        endif
                    endfor
                    if an.nAtt = 0
                        # no clear rise: start where the sound first gets
                        # within 20 dB of its maximum
                        .t0 = 0
                        .found = 0
                        for .i from 1 to .nf
                            if .found = 0 and .iv[.i] >= .imax - 20
                                .found = 1
                                .t0 = max(0, .it[.i] - 0.03)
                            endif
                        endfor
                        an.nAtt = 1
                        an.att[1] = .t0
                    endif
                else
                    an.nAtt = 1
                    an.att[1] = 0
                endif
                # spectral features of the region after the main attack
                .r0 = an.att[1]
                .r1 = min(.aEnd, .r0 + 1.5)
                if .r1 - .r0 < 0.05
                    .r0 = 0
                    .r1 = .aEnd
                endif
                selectObject: .snd
                Extract part: .r0, .r1, "rectangular", 1, "no"
                .reg = selected("Sound")
                To Spectrum: "yes"
                .spc = selected("Spectrum")
                an.cog = Get centre of gravity: 2
                an.bw = Get standard deviation: 2
                .ny = an.sr / 2
                .tot = 0
                for .b from 1 to nBand
                    .lo = if .b = 1 then 0 else bandEdge[.b - 1] fi
                    .hi = if .b = nBand then .ny else min(.ny, bandEdge[.b]) fi
                    if .hi > .lo + 1
                        .eb = Get band energy: .lo, .hi
                    else
                        .eb = 0
                    endif
                    an.prof[.b] = .eb
                    .tot = .tot + .eb
                endfor
                for .b from 1 to nBand
                    an.prof[.b] = if .tot > 0 then an.prof[.b] / .tot else 1 / nBand fi
                endfor
                removeObject: .spc
                # tonality from cross-correlation harmonicity; frames below
                # -60 dB (Praat writes -200 for unvoiced/silent) are skipped
                an.tonal = 0
                selectObject: .reg
                .rd = Get total duration
                if .rd >= 0.12
                    To Harmonicity (cc): 0.01, 75, 0.1, 1.0
                    .hh = selected("Harmonicity")
                    .nh = Get number of frames
                    .hs = 0
                    .hn = 0
                    for .i from 1 to .nh
                        .v = Get value in frame: .i
                        if .v <> undefined
                            if .v > -60
                                .hs = .hs + .v
                                .hn = .hn + 1
                            endif
                        endif
                    endfor
                    removeObject: .hh
                    if .hn >= 3
                        an.tonal = max(0, min(1, (.hs / .hn + 5) / 25))
                    endif
                endif
                removeObject: .reg
                an.ok = 1
            endif
            removeObject: .snd
            @dropTemp: .snd
        endif
        removeObject: .oid
        @dropTemp: .oid
    endif
endproc

# evenness of one candidate's band profile (0..1)
procedure evenness: .f, .j
    .h = 0
    for .b from 1 to nBand
        .p = cProf[.f, .j, .b]
        if .p > 0
            .h = .h - .p * ln(.p)
        endif
    endfor
    evenness.h = .h / ln(nBand)
endproc

# Complementarity of the current choice selJ[]:
#   0.40 profile contrast (1 - Bhattacharyya coefficient, mean of pairs)
#   0.30 coverage (evenness of the per-band maximum over the sources)
#   0.20 centroid spread (sd of log2 centroid / 2)
#   0.10 tonal / noisy diversity (2 x sd of tonality)
# One source: its own band evenness.
procedure comboScore
    if nAct = 1
        @evenness: actFold[1], selJ[1]
        comboScore.s = evenness.h
        comboScore.contrast = 0
        comboScore.coverage = evenness.h
        comboScore.spread = 0
        comboScore.tonal = 0
    else
        .c = 0
        .np = 0
        for .a from 1 to nAct - 1
            for .a2 from .a + 1 to nAct
                .bc = 0
                for .b from 1 to nBand
                    .bc = .bc + sqrt(cProf[actFold[.a], selJ[.a], .b] * cProf[actFold[.a2], selJ[.a2], .b])
                endfor
                .c = .c + (1 - .bc)
                .np = .np + 1
            endfor
        endfor
        .contrast = .c / .np
        .sm = 0
        for .b from 1 to nBand
            .mx[.b] = 0
            for .a from 1 to nAct
                .mx[.b] = max(.mx[.b], cProf[actFold[.a], selJ[.a], .b])
            endfor
            .sm = .sm + .mx[.b]
        endfor
        .h = 0
        for .b from 1 to nBand
            .p = .mx[.b] / .sm
            if .p > 0
                .h = .h - .p * ln(.p)
            endif
        endfor
        .coverage = .h / ln(nBand)
        .m1 = 0
        .t1 = 0
        for .a from 1 to nAct
            .m1 = .m1 + log2(max(20, cCog[actFold[.a], selJ[.a]]))
            .t1 = .t1 + cTon[actFold[.a], selJ[.a]]
        endfor
        .m1 = .m1 / nAct
        .t1 = .t1 / nAct
        .v1 = 0
        .v2 = 0
        for .a from 1 to nAct
            .v1 = .v1 + (log2(max(20, cCog[actFold[.a], selJ[.a]])) - .m1) ^ 2
            .v2 = .v2 + (cTon[actFold[.a], selJ[.a]] - .t1) ^ 2
        endfor
        .spread = min(1, sqrt(.v1 / nAct) / 2)
        .tonal = min(1, 2 * sqrt(.v2 / nAct))
        comboScore.contrast = .contrast
        comboScore.coverage = .coverage
        comboScore.spread = .spread
        comboScore.tonal = .tonal
        comboScore.s = 0.40 * .contrast + 0.30 * .coverage + 0.20 * .spread + 0.10 * .tonal
    endif
endproc

# One ADSR segment chain (no release): delay .d0, peak .amp, sustain .sus
procedure adsr: .kb, .t, .d0, .amp, .sus
    .tt = .t - .d0
    if .tt <= 0
        adsr.v = 0
    elsif .tt < eAtt[.kb]
        adsr.v = .amp * (.tt / eAtt[.kb]) ^ eAc[.kb]
    elsif .tt < eAtt[.kb] + eDec[.kb]
        .y = (.tt - eAtt[.kb]) / eDec[.kb]
        .k = eKd[.kb]
        adsr.v = .amp * (.sus + (1 - .sus) * (exp(-.k * .y) - exp(-.k)) / (1 - exp(-.k)))
    else
        adsr.v = .amp * .sus
    endif
endproc

# Envelope of source-band .kb at time .t
procedure envAt: .kb, .t
    if eNP[.kb] <= 1
        @adsr: .kb, .t, eDel[.kb], 1, eSus[.kb]
        .v = adsr.v
    else
        .v = 0
        for .j from 1 to eNP[.kb]
            .su = if .j < eNP[.kb] then eSusB[.kb] else eSus[.kb] fi
            @adsr: .kb, .t, eDel[.kb] + ePT[.kb, .j], ePA[.kb, .j], .su
            .v = max(.v, adsr.v)
        endfor
    endif
    if .t > eRel0[.kb]
        .y = (.t - eRel0[.kb]) / eRelD[.kb]
        .kr = eKr[.kb]
        .r = if .y >= 1 then 0 else (exp(-.kr * .y) - exp(-.kr)) / (1 - exp(-.kr)) fi
        .v = .v * .r
        if eRes[.kb] > 0
            .yr = (.t - eRel0[.kb]) / eResD[.kb]
            .res = if .yr < 1 then eRes[.kb] * (1 - .yr) ^ 2 else 0 fi
            .v = max(.v, .res)
        endif
    endif
    # click-safe end: every envelope reaches zero at the gesture's end
    if .t > gdur - 0.03
        .v = .v * sin(pi / 2 * max(0, gdur - .t) / 0.03) ^ 2
    endif
    # a source that runs out of material fades over 60 ms before it ends
    .k = (.kb - 1) div nBand + 1
    if srcEnd[.k] < gdur
        if .t >= srcEnd[.k]
            .v = 0
        elsif .t > srcEnd[.k] - 0.06
            .v = .v * ((srcEnd[.k] - .t) / 0.06) ^ 2
        endif
    endif
    if .t < 0
        .v = 0
    endif
    envAt.v = .v * eLev[.kb]
endproc

# Source read position (seconds into the prepared region) for output
# time .t: 1:1 during the attack, then at srcRate.
procedure srcPos: .k, .t
    if .t <= srcTa[.k]
        srcPos.tau = .t
    else
        srcPos.tau = srcTa[.k] + srcRate[.k] * (.t - srcTa[.k])
    endif
endproc

# The spectral fusion (see the header). .mode 1 = full stereo motion,
# 2 = static (every contribution centred, L = R).
#   .nM     members fused (nSrc = the dry sources; 2 nSrc adds their
#           per-source reverbs, see @reverbSetup)
#   .track  1 = keep the band targets (tgtE) for the figure and checks
#   .nO     output length in samples (nOut, or longer with a tail)
procedure renderFusion: .mode, .nM, .track, .nO
    .lab$ = if .mode = 1 then "spectral fusion" else "static fusion" fi
    .lab$ = .lab$ + if .nM > nSrc then " with per-source reverb" else "" fi
    .nF = min(nFr, ceiling(.nO / hop) + 3 - iFirst + 1)
    appendInfoLine: "Rendering ", .lab$, ": ", .nF, " frames of ", nW, " samples, hop ", hop, "..."
    Create Sound from formula: "sgf_buffer", 2, 0, (.nO + 2 * nW) / srOut, srOut, "0"
    .buf = selected("Sound")
    @addTemp: .buf
    .p$ = fixed$(pFuse, 6)
    .ip$ = fixed$(1 / pFuse, 6)
    .win$ = "sin(pi * (col - 0.5) / " + string$(nW) + ")^2"
    renderFusion.capped = 0
    renderFusion.lowGuarded = 0
    .wetAll = 0
    .wetGone = 0
    .nCh = if .mode = 1 then 2 else 1 fi
    .pct = 0
    for .ii from 1 to .nF
        .i = iFirst + .ii - 1
        .c = frT[.ii]
        if 10 * .ii / .nF >= .pct + 1
            .pct = floor(10 * .ii / .nF)
            appendInfoLine: "  ", .pct * 10, " %"
        endif
        # which sources sound in this frame
        .any = 0
        for .k from 1 to .nM
            .on[.k] = 0
            for .b from 1 to nBand
                if envT[(.k - 1) * nBand + .b, .ii] > 1e-6
                    .on[.k] = 1
                endif
            endfor
            .any = .any + .on[.k]
        endfor
        if .track
            for .b from 1 to nBand
                tgtE[.b, .ii] = 0
            endfor
        endif
        if .any > 0
            # 1. analysis frames (Hann) and their spectra
            for .k from 1 to .nM
                if .on[.k]
                    @srcPos: .k, .c
                    .off = round(srcPos.tau * srOut) - nW / 2
                    selectObject: frID[.k]
                    Formula: "if col + " + string$(.off) + " >= 1 and col + " + string$(.off) + " <= " + string$(srcN[.k])
                        ... + " then object[" + string$(srcID[.k]) + ", 1, col + " + string$(.off) + "] * " + .win$ + " else 0 fi"
                    To Spectrum: "yes"
                    .sp[.k] = selected("Spectrum")
                endif
            endfor
            # material gate: a source with (almost) no energy in a band in
            # this frame does not take part there - otherwise the power
            # mean would vote that band to silence (e.g. an 11 kHz file
            # above 5.5 kHz). Ramp from -40 to -30 dB re the strongest.
            for .b from 1 to nBand
                .emx = 0
                for .k from 1 to .nM
                    .eb[.k, .b] = 0
                    if .on[.k]
                        selectObject: .sp[.k]
                        .eb[.k, .b] = Get band energy: bandLo[.b], bandHi[.b]
                        .emx = max(.emx, .eb[.k, .b])
                    endif
                endfor
                for .k from 1 to .nM
                    if .emx > 0 and .eb[.k, .b] > 0
                        .gt[.k, .b] = max(0, min(1, (10 * log10(.eb[.k, .b] / .emx) + 40) / 10))
                    else
                        .gt[.k, .b] = 0
                    endif
                endfor
            endfor
            # 2. magnitudes and weights (rows = sources)
            .mag$ = "0"
            .w0$ = "0"
            .wl$ = "0"
            .wr$ = "0"
            for .kk from 1 to .nM
                .k = .nM - .kk + 1
                if .on[.k]
                    .s$ = string$(.sp[.k])
                    .mag$ = "if row = " + string$(.k) + " then sqrt(object[" + .s$ + ", 1, col]^2 + object[" + .s$ + ", 2, col]^2) else " + .mag$ + " fi"
                    .t0$ = ""
                    .tl$ = ""
                    .tr$ = ""
                    for .b from 1 to nBand
                        .kb = (.k - 1) * nBand + .b
                        .ev = envT[.kb, .ii] * .gt[.k, .b]
                        if .track and .k > nSrc
                            # how much reverberant weight the material gate removes
                            .wetAll = .wetAll + envT[.kb, .ii]
                            .wetGone = .wetGone + envT[.kb, .ii] - .ev
                        endif
                        if .ev > 1e-9
                            if .mode = 1
                                .th = (posT[.kb, .ii] + 1) * pi / 4
                                .el = .ev * cos(.th)
                                .er = .ev * sin(.th)
                            else
                                .el = .ev * sqrt(0.5)
                                .er = .el
                            endif
                            .bm$ = " * object[" + string$(bmID) + ", " + string$(.b) + ", col]"
                            .t0$ = .t0$ + " + " + string$(.ev) + .bm$
                            .tl$ = .tl$ + " + " + string$(.el) + .bm$
                            .tr$ = .tr$ + " + " + string$(.er) + .bm$
                        endif
                    endfor
                    if .t0$ <> ""
                        .w0$ = "if row = " + string$(.k) + " then (0" + .t0$ + ") else " + .w0$ + " fi"
                        .wl$ = "if row = " + string$(.k) + " then (0" + .tl$ + ") else " + .wl$ + " fi"
                        .wr$ = "if row = " + string$(.k) + " then (0" + .tr$ + ") else " + .wr$ + " fi"
                    endif
                endif
            endfor
            selectObject: magID
            Formula: .mag$
            selectObject: w0ID
            Formula: .w0$
            selectObject: wlID
            Formula: .wl$
            if .mode = 1
                selectObject: wrID
                Formula: .wr$
            endif
            # 3. shared phase: Z = sum w^2 m S (soft dominant source)
            .z$ = "0"
            for .k from 1 to .nM
                if .on[.k]
                    .z$ = .z$ + " + object[" + string$(w0ID) + ", " + string$(.k) + ", col]^2 * object[" + string$(magID) + ", "
                        ... + string$(.k) + ", col] * object[" + string$(.sp[.k]) + ", row, col]"
                endif
            endfor
            selectObject: zsID
            Formula: .z$
            selectObject: phID
            Formula: "sqrt(object[" + string$(zsID) + ", 1, col]^2 + object[" + string$(zsID) + ", 2, col]^2)"
            # 4. per channel: fused magnitude with the shared phase, then
            # per-band energy matched to the weighted sources
            for .ch from 1 to .nCh
                .wc = if .ch = 1 then wlID else wrID fi
                .g$ = "(0"
                .pm$ = "(0"
                .rf$ = "(0"
                for .k from 1 to .nM
                    if .on[.k]
                        .wk$ = "object[" + string$(.wc) + ", " + string$(.k) + ", col]"
                        .mk$ = "object[" + string$(magID) + ", " + string$(.k) + ", col]"
                        .g$ = .g$ + " + " + .wk$
                        .pm$ = .pm$ + " + " + .wk$ + " * " + .mk$ + "^" + .p$
                        .rf$ = .rf$ + " + (" + .wk$ + " * " + .mk$ + ")^2"
                    endif
                endfor
                .g$ = .g$ + ")"
                .pm$ = .pm$ + ")"
                .rf$ = .rf$ + ")"
                selectObject: refID
                Formula: "if row = 1 then sqrt" + .rf$ + " else 0 fi"
                # shared phase, rotated by +/- phi(f)/2 for L/R in the upper
                # bands (static mode: no rotation)
                .zr$ = "object[" + string$(zsID) + ", 1, col]"
                .zi$ = "object[" + string$(zsID) + ", 2, col]"
                .cr$ = "object[" + string$(rotID) + ", 1, col]"
                .sr$ = "object[" + string$(rotID) + ", 2, col]"
                .sg$ = if .ch = 1 then "" else "-" fi
                if .mode = 1
                    .ph$ = "(if row = 1 then " + .zr$ + " * " + .cr$ + " - " + .sg$ + "(" + .zi$ + " * " + .sr$ + ") else "
                        ... + .sg$ + "(" + .zr$ + " * " + .sr$ + ") + " + .zi$ + " * " + .cr$ + " fi)"
                else
                    .ph$ = "object[" + string$(zsID) + ", row, col]"
                endif
                selectObject: outSpID
                Formula: "if " + .g$ + " > 1e-12 and object[" + string$(phID) + ", 1, col] > 1e-30 then "
                    ... + .g$ + " * (" + .pm$ + " / " + .g$ + ")^" + .ip$ + " * " + .ph$ + " / object["
                    ... + string$(phID) + ", 1, col] else 0 fi"
                .sumR = 0
                for .b from 1 to nBand
                    selectObject: refID
                    .r[.b] = Get band energy: bandLo[.b], bandHi[.b]
                    selectObject: outSpID
                    .o[.b] = Get band energy: bandLo[.b], bandHi[.b]
                    if .b > 1
                        .sumR = .sumR + .r[.b]
                    endif
                endfor
                # low-frequency guard: band 1 at most 60 % of the frame
                if .r[1] > 1.5 * .sumR and .sumR > 0
                    .r[1] = 1.5 * .sumR
                    renderFusion.lowGuarded = renderFusion.lowGuarded + 1
                endif
                .gn$ = "0"
                .rMax = 0
                for .b from 1 to nBand
                    .rMax = max(.rMax, .r[.b])
                endfor
                for .b from 1 to nBand
                    if .o[.b] > 1e-20 and .r[.b] > 0
                        .gb = sqrt(.r[.b] / .o[.b])
                        if .gb > 4
                            .gb = 4
                            # counted only where the band matters (within
                            # 30 dB of the frame's strongest band)
                            if .r[.b] > .rMax * 0.001
                                renderFusion.capped = renderFusion.capped + 1
                            endif
                        endif
                    else
                        .gb = 0
                    endif
                    if .track
                        tgtE[.b, .ii] = tgtE[.b, .ii] + .r[.b]
                    endif
                    .gn$ = .gn$ + " + " + string$(.gb) + " * object[" + string$(bmID) + ", " + string$(.b) + ", col]"
                endfor
                Formula: "self * (" + .gn$ + ")"
                # 5. inverse FFT, synthesis Hann, overlap-add (sum of
                # Hann^2 at 75 % overlap = 1.5)
                To Sound
                .fs = selected("Sound")
                .o2 = .i * hop - nW / 2 + nW
                .c1 = if .mode = 1 then .ch else 1 fi
                .c2 = if .mode = 1 then .ch else 2 fi
                selectObject: .buf
                Formula (part): .o2 / srOut, (.o2 + nW) / srOut, .c1, .c2,
                    ... "self + object[" + string$(.fs) + ", 1, col - " + string$(.o2) + "] * sin(pi * (col - "
                    ... + string$(.o2) + " - 0.5) / " + string$(nW) + ")^2 / 1.5"
                removeObject: .fs
            endfor
            for .k from 1 to .nM
                if .on[.k]
                    removeObject: .sp[.k]
                endif
            endfor
        endif
    endfor
    selectObject: .buf
    Extract part: nW / srOut, (nW + .nO) / srOut, "rectangular", 1, "no"
    renderFusion.id = selected("Sound")
    renderFusion.wetCut = if .wetAll > 0 then .wetGone / .wetAll else undefined fi
    removeObject: .buf
    @dropTemp: .buf
endproc

# Comparison: the conventional mix - the same source regions (read 1:1,
# not remapped), each with ONE broadband envelope (its band envelopes
# combined, weighted by its own band energy), all centred.
procedure renderMix
    .expr$ = "0"
    for .k from 1 to nSrc
        .xmin = (iFirst - 0.5) * hop / srOut
        Create Sound from formula: "sgf_env" + string$(.k), 1, .xmin, .xmin + nFr * hop / srOut, srOut / hop, "0"
        .env[.k] = selected("Sound")
        @addTemp: .env[.k]
        for .ii from 1 to nFr
            .s = 0
            for .b from 1 to nBand
                .s = .s + envT[(.k - 1) * nBand + .b, .ii] ^ 2 * srcShare[.k, .b]
            endfor
            Set value at sample number: 1, .ii, sqrt(.s)
        endfor
        .expr$ = .expr$ + " + object(" + string$(srcID[.k]) + ", x) * object(" + string$(.env[.k]) + ", x)"
    endfor
    Create Sound from formula: "sgf_mix", 2, 0, nOut / srOut, srOut, .expr$
    renderMix.id = selected("Sound")
    for .k from 1 to nSrc
        removeObject: .env[.k]
        @dropTemp: .env[.k]
    endfor
endproc

# ---- REVERBERATION ----
# Per-source reverbs: each chosen source gets its own impulse response;
# its wet signal becomes an extra fusion MEMBER with its own
# (reverberant) envelopes, so the reverb takes part in the power-mean
# fusion instead of being added afterwards. Parameters are spread over
# the sources by seeded permutations (Reverb decay diversity) and nudged
# by the source analysis: tonal sources (strong resonant peaks) decay
# 20 % shorter, sources shorter than the gesture up to 30 % longer,
# bright sources are damped more, noisy sources get a denser, more
# diffuse tail. Global reverb: a stereo pair of responses built from the
# same settings (different noise, different reflection times).
procedure reverbSetup
    random_initializeWithSeedUnsafelyButPredictably (random_seed + 104729)
    appendInfoLine: "Reverberation: building impulse responses..."
    if wetNeeded
        # three seeded permutations spread decay, pre-delay and wet level
        # evenly from -1 to +1 over the sources (plus a little jitter)
        for .q from 1 to 3
            for .k from 1 to nSrc
                .ord[.k] = .k
            endfor
            for .i from 1 to nSrc - 1
                .j = randomInteger(.i, nSrc)
                .tm = .ord[.i]
                .ord[.i] = .ord[.j]
                .ord[.j] = .tm
            endfor
            for .i from 1 to nSrc
                .z = if nSrc > 1 then -1 + 2 * (.i - 1) / (nSrc - 1) else 0 fi
                rvZ[.q, .ord[.i]] = max(-1, min(1, .z + 0.15 * randomUniform(-1, 1)))
            endfor
        endfor
        .tH = nOutTot / srOut
        for .k from 1 to nSrc
            .short = 1 - min(1, srcLen[.k] / gdur)
            rvT[.k] = rvAvg * 2 ^ (1.5 * rvDiv * rvZ[1, .k]) * (1 - 0.2 * srcTon[.k]) * (1 + 0.3 * .short)
            rvT[.k] = max(0.15, min(5, rvT[.k]))
            rvP[.k] = max(0, min(0.25, rvPre * 2 ^ (rvDiv * rvZ[2, .k])))
            rvW[.k] = max(0, min(1.5, rvAmt * 2 ^ (0.6 * rvDiv * rvZ[3, .k])))
            .br = max(-1, min(1, log2(max(50, srcCog[.k]) / 1500) / 2))
            rvD[.k] = max(0, min(0.95, rvDamp + 0.25 * rvDiv * .br + 0.15 * rvDiv * randomUniform(-1, 1)))
            rvF[.k] = max(0, min(1, 0.5 + 0.35 * (1 - srcTon[.k]) + 0.3 * rvDiv * randomUniform(-1, 1)))
            rvDens[.k] = 800 + 3200 * rvF[.k]
            rvNER[.k] = round(6 + 8 * rvF[.k])
            rvER[.k] = 0.45 - 0.25 * rvF[.k]
            @makeIR: "sgf_ir" + string$(.k), rvT[.k], rvD[.k], rvP[.k], rvDens[.k], rvNER[.k], rvER[.k]
            .ir = makeIR.id
            selectObject: srcID[.k], .ir
            Convolve: "sum", "zero"
            .wet = selected("Sound")
            Rename: "sgf_wet" + string$(.k)
            @addTemp: .wet
            removeObject: .ir
            @dropTemp: .ir
            # the wet member reads its material through the source's own
            # time map; it is longer by the response, so it runs out later
            .m = nSrc + .k
            srcID[.m] = .wet
            selectObject: .wet
            srcN[.m] = Get number of samples
            srcLen[.m] = srcN[.m] / srOut
            srcTa[.m] = srcTa[.k]
            srcRate[.m] = srcRate[.k]
            srcName$[.m] = srcName$[.k] + " (rev)"
            .us = srcLen[.m] - halfW
            .tau = if .tH <= srcTa[.m] then .tH else srcTa[.m] + srcRate[.m] * (.tH - srcTa[.m]) fi
            if .tau <= .us
                srcEnd[.m] = .tH
            elsif .us <= srcTa[.m]
                srcEnd[.m] = max(0, .us)
            else
                srcEnd[.m] = srcTa[.m] + (.us - srcTa[.m]) / srcRate[.m]
            endif
        endfor
        nMemAll = 2 * nSrc
        # Reverberant envelopes. For every source-band pair the wet weight
        # is a decaying MEMORY of the direct envelope: it follows the
        # direct envelope (delayed by the pre-delay, 30 ms rise) and, once
        # the direct sound falls, decays at twice the source's T60 (the
        # wet signal brings its own decay); it is ducked while the direct
        # sound is strong (-60 % at full level), so it comes forward in
        # the release. Contained: it fades out over the last
        # min(0.6 s, 20 %) of the gesture; Extended: it runs on into the
        # tail and fades over the tail's last 40 %.
        .hopT = hop / srOut
        .aR = 1 - exp(-.hopT / 0.03)
        for .k from 1 to nSrc
            .m = nSrc + .k
            .dec = exp(-6.91 * .hopT / (2 * rvT[.k]))
            .pd = round(rvP[.k] / .hopT)
            for .b from 1 to nBand
                .kb = (.k - 1) * nBand + .b
                .km = (.m - 1) * nBand + .b
                .lev = max(eLev[.kb], 1e-12)
                .u = (.b - 1) / (nBand - 1)
                .side = if (.k mod 2) = 0 then 1 else -1 fi
                .h = 0
                for .ii from 1 to nFr
                    .t = frT[.ii]
                    .si = .ii - .pd
                    .dn = if .si >= 1 then min(1, envT[.kb, .si] / .lev) else 0 fi
                    if .dn > .h
                        .h = .h + (.dn - .h) * .aR
                    else
                        .h = .h * .dec
                    endif
                    .duck = 1 - 0.6 * min(1, envT[.kb, .ii] / .lev)
                    if extTail
                        .tE = gdur + tailMax
                        .fl = 0.4 * tailMax
                        .ef = if .t >= .tE then 0 else if .t > .tE - .fl then sin(pi / 2 * (.tE - .t) / .fl) ^ 2 else 1 fi fi
                    else
                        .fc = min(0.6, 0.2 * gdur)
                        .ef = if .t >= gdur then 0 else if .t > gdur - .fc then sin(pi / 2 * (gdur - .t) / .fc) ^ 2 else 1 fi fi
                    endif
                    .ex = 1
                    if srcEnd[.m] < .tH
                        if .t >= srcEnd[.m]
                            .ex = 0
                        elsif .t > srcEnd[.m] - 0.06
                            .ex = ((srcEnd[.m] - .t) / 0.06) ^ 2
                        endif
                    endif
                    envT[.km, .ii] = if .t < 0 then 0 else rvW[.k] * eLev[.kb] * .h * .duck * .ef * .ex fi
                    # the reverb of a contribution sits on the other side,
                    # narrower (a reflected image), plus a per-source offset
                    posT[.km, .ii] = max(-1, min(1, -0.6 * posT[.kb, .ii] + 0.3 * width * (0.15 + 0.85 * .u ^ 0.7) * .side))
                endfor
                eLev[.km] = rvW[.k] * eLev[.kb]
            endfor
        endfor
    endif
    if globNeeded
        rvGT = max(0.3, min(4, rvAvg))
        rvGP = max(0.01, rvPre)
        @makeIR: "sgf_girL", rvGT, rvDamp, rvGP, 2600, 10, 0.3
        gIRL = makeIR.id
        @addTemp: gIRL
        @makeIR: "sgf_girR", rvGT, rvDamp, rvGP, 2600, 10, 0.3
        gIRR = makeIR.id
        @addTemp: gIRR
    endif
endproc

# A reverberation impulse response with unit energy (sum of squares 1),
# no direct sound: .pre s of silence, sparse random-sign noise (.dens
# impulses per second) shaped by three band decays (below ~600 Hz the
# full T60; mid and high shortened by the damping), a 12 ms onset ramp,
# and .nER early reflections in the first ~70 ms carrying .erShare of
# the energy. A finite response (to about -72 dB) applied by FFT
# convolution: no feedback, so it cannot become unstable, and no
# periodic delay lines, so no flutter or metallic combing - but also no
# recirculating density build-up as in a feedback reverberator.
procedure makeIR: .name$, .t60, .damp, .pre, .dens, .nER, .erShare
    .len = .pre + min(6, 1.2 * .t60) + 0.01
    .ps$ = string$(.pre)
    Create Sound from formula: .name$, 1, 0, .len, srOut, "if x < " + .ps$ + " then 0 else (if randomUniform(0, 1) < "
        ... + string$(.dens / srOut) + " then (if randomUniform(0, 1) < 0.5 then -1 else 1 fi) else 0 fi) fi"
    .nz = selected("Sound")
    .tb[1] = .t60
    .tb[2] = max(0.08, .t60 * (1 - 0.35 * .damp))
    .tb[3] = max(0.06, .t60 * (1 - 0.75 * .damp))
    .sh$[1] = "(if x <= 400 then 1 else if x < 800 then cos(pi / 2 * log2(x / 400))^2 else 0 fi fi)"
    .sh$[3] = "(if x >= 5000 then 1 else if x > 2500 then sin(pi / 2 * log2(x / 2500))^2 else 0 fi fi)"
    .sh$[2] = "(1 - " + .sh$[1] + " - " + .sh$[3] + ")"
    for .q from 1 to 3
        selectObject: .nz
        Filter (formula): "self * " + .sh$[.q]
        .bd[.q] = selected("Sound")
        Formula: "if x < " + .ps$ + " then 0 else self * 10^(-3 * (x - " + .ps$ + ") / " + string$(.tb[.q])
            ... + ") * (1 - exp(-(x - " + .ps$ + ") / 0.012)) fi"
    endfor
    selectObject: .bd[1]
    Formula: "self + object[" + string$(.bd[2]) + ", 1, col] + object[" + string$(.bd[3]) + ", 1, col]"
    .ir = .bd[1]
    removeObject: .nz, .bd[2], .bd[3]
    selectObject: .ir
    .eLate = Get energy: 0, 0
    .erE = 0
    for .i from 1 to .nER
        .ti[.i] = .pre + 0.003 + 0.07 * (.i / .nER) ^ 1.3 * (0.8 + 0.4 * randomUniform(0, 1))
        .gi[.i] = (0.9 - 0.5 * .i / .nER) * (if randomUniform(0, 1) < 0.5 then -1 else 1 fi)
        .erE = .erE + .gi[.i] ^ 2
    endfor
    .sc = sqrt(.erShare / (1 - .erShare) * .eLate * srOut / .erE)
    for .i from 1 to .nER
        .n = round(.ti[.i] * srOut) + 1
        .v = Get value at sample number: 1, .n
        Set value at sample number: 1, .n, .v + .sc * .gi[.i]
    endfor
    .e = Get energy: 0, 0
    Formula: "self / " + string$(sqrt(.e * srOut))
    Rename: .name$
    makeIR.id = .ir
endproc

# Global reverb on a finished stereo fusion: L feeds the left response
# 80/20 with R, R the right one 20/80 (the image keeps its sides, the
# two tails are decorrelated), wet added at .amt. Contained: the wet
# part fades out over the last min(0.6 s, 20 %) of the gesture;
# Extended: over the last 40 % of the tail room.
procedure applyGlobal: .id, .amt
    selectObject: .id
    .ns = Get number of samples
    Extract one channel: 1
    .l = selected("Sound")
    selectObject: .id
    Extract one channel: 2
    .r = selected("Sound")
    selectObject: .l
    Copy: "sgf_gin_l"
    .il = selected("Sound")
    Formula: "0.8 * self + 0.2 * object[" + string$(.r) + ", 1, col]"
    selectObject: .r
    Copy: "sgf_gin_r"
    .ir = selected("Sound")
    Formula: "0.8 * self + 0.2 * object[" + string$(.l) + ", 1, col]"
    selectObject: .il, gIRL
    Convolve: "sum", "zero"
    .wl = selected("Sound")
    selectObject: .ir, gIRR
    Convolve: "sum", "zero"
    .wr = selected("Sound")
    selectObject: .wl, .wr
    Combine to stereo
    .w = selected("Sound")
    .du = .ns / srOut
    if extTail and .ns > nOut
        .fl = 0.4 * tailMax
        .te = .du
    else
        .fl = min(0.6, 0.2 * gdur)
        .te = gdur
    endif
    Formula: "if x >= " + string$(.te) + " then 0 else if x > " + string$(.te - .fl) + " then self * sin(pi / 2 * ("
        ... + string$(.te) + " - x) / " + string$(.fl) + ")^2 else self fi fi"
    selectObject: .id
    Copy: "sgf_glob"
    applyGlobal.id = selected("Sound")
    Formula: "self + " + string$(.amt) + " * object[" + string$(.w) + ", row, col]"
    removeObject: .l, .r, .il, .ir, .wl, .wr, .w
endproc

# Extended tail: keep the output up to 50 ms after the last 10 ms
# window within 60 dB of the peak (never shorter than the gesture,
# never longer than the tail room), with a fade over the added part.
procedure trimTail: .id
    selectObject: .id
    .pk = Get absolute extremum: 0, 0, "None"
    .du = Get total duration
    .thr = .pk * 10 ^ (-60 / 20)
    .tEnd = gdur
    .t = gdur
    while .t + 0.01 <= .du
        .rr = Get root-mean-square: .t, .t + 0.01
        if .rr > .thr
            .tEnd = .t + 0.01
        endif
        .t = .t + 0.01
    endwhile
    if .tEnd + 0.05 > .du - 0.005 and .du > gdur + 0.06
        warnN = warnN + 1
        warn$[warnN] = "A reverberant tail was still within 60 dB of the peak at the tail limit (" + fixed$(.du, 2)
            ... + " s) and was faded there."
    endif
    # nothing above the threshold after the gesture: end exactly there
    if .tEnd > gdur
        .tEnd = min(.du, .tEnd + 0.05)
    endif
    .nE = max(nOut, round(.tEnd * srOut))
    Extract part: 0, .nE / srOut, "rectangular", 1, "no"
    trimTail.id = selected("Sound")
    if .nE > nOut
        .te = .nE / srOut
        .fl = min(0.1, max(0.005, (.te - gdur) / 2))
        Formula (part): .te - .fl, .te, 1, 2, "self * sin(pi / 2 * max(0, " + string$(.te) + " - x) / " + string$(.fl) + ")^2"
    endif
endproc

# Comparison of the reverb stages - same sources, regions, envelopes,
# trajectories and seed; the four results are level-matched (equal RMS
# over the gesture, the loudest-crest one at -1 dBFS peak):
#   A dry fusion, B per-source reverb + fusion, C fusion + global,
#   D per-source + global (global at 60 % when both, as in the main mode)
procedure renderComparisonsRV
    .nC = if extTail then nOutTot else nOut fi
    selectObject: preMainID
    .npm = Get number of samples
    for .v from 1 to 2
        .useMain = (.v = 1 and srcRev = 0) or (.v = 2 and srcRev = 1)
        if .useMain and .npm = .nC
            selectObject: preMainID
            Copy: "sgf_cmp"
            .pre[.v] = selected("Sound")
        else
            appendInfoLine: "Comparison ", if .v = 1 then "A (dry fusion)" else "B (per-source reverb)" fi, "..."
            @renderFusion: 1, if .v = 1 then nSrc else nMemAll fi, 0, .nC
            .pre[.v] = renderFusion.id
        endif
    endfor
    appendInfoLine: "Comparison C, D (global reverb)..."
    @applyGlobal: .pre[1], rvAmt
    .pre[3] = applyGlobal.id
    @applyGlobal: .pre[2], 0.6 * rvAmt
    .pre[4] = applyGlobal.id
    for .q from 1 to 4
        if extTail
            @trimTail: .pre[.q]
            removeObject: .pre[.q]
            .pre[.q] = trimTail.id
        endif
        cmpID[.q] = .pre[.q]
        selectObject: cmpID[.q]
        Rename: objBase$ + "_" + cmpSuf$[.q]
        .ns = Get number of samples
        .te = .ns / srOut
        Formula (part): 0, 0.002, 1, 2, "self * sin(pi / 2 * x / 0.002)^2"
        Formula (part): .te - 0.005, .te, 1, 2, "self * sin(pi / 2 * max(0, " + string$(.te) + " - x) / 0.005)^2"
        .rm[.q] = Get root-mean-square: 0, gdur
        .pk[.q] = Get absolute extremum: 0, 0, "None"
    endfor
    .rt = 1e9
    for .q from 1 to 4
        if .rm[.q] > 0 and .pk[.q] > 0
            .rt = min(.rt, .rm[.q] * 10 ^ (headroomDb / 20) / .pk[.q])
        endif
    endfor
    for .q from 1 to 4
        selectObject: cmpID[.q]
        if .rm[.q] > 0
            Formula: "self * " + string$(.rt / .rm[.q])
        endif
        cmpGainDb[.q] = 20 * log10(.rt / max(.rm[.q], 1e-12))
    endfor
endproc

# Peak normalisation to the headroom target; a 2 ms start fade (the
# first analysis frame already overlaps t = 0, so the result could
# otherwise start on a non-zero sample - short enough to keep the
# attack) and a 5 ms end fade as click guards.
procedure finishOutput: .id
    selectObject: .id
    # end time: the gesture end, or the end of a reverberant tail
    .ns = Get number of samples
    .te = if .ns = nOut then gdur else .ns / srOut fi
    Formula (part): 0, 0.002, 1, 2, "self * sin(pi / 2 * x / 0.002)^2"
    Formula (part): .te - 0.005, .te, 1, 2, "self * sin(pi / 2 * max(0, " + string$(.te) + " - x) / 0.005)^2"
    .pk = Get absolute extremum: 0, 0, "None"
    finishOutput.gainDb = 0
    if .pk > 0
        .tg = 10 ^ (headroomDb / 20)
        Scale peak: .tg
        finishOutput.gainDb = 20 * log10(.tg / .pk)
    else
        warnN = warnN + 1
        warn$[warnN] = "A rendered output is silent."
    endif
endproc

# Stereo measurements over 50 ms windows: position (equal-power
# balance), width (1 - L/R correlation), and the mono fold-down loss.
procedure measureStereo: .id
    selectObject: .id
    measureStereo.nSamp = Get number of samples
    .pk = Get absolute extremum: 0, 0, "None"
    measureStereo.peakDb = 20 * log10(max(.pk, 1e-12))
    .rms = Get root-mean-square: 0, 0
    measureStereo.rmsDb = 20 * log10(max(.rms, 1e-12))
    Extract one channel: 1
    .l = selected("Sound")
    selectObject: .id
    Extract one channel: 2
    .r = selected("Sound")
    Copy: "sgf_lr"
    .lr = selected("Sound")
    Formula: "self * object[" + string$(.l) + ", 1, col]"
    selectObject: .id
    Convert to mono
    .mo = selected("Sound")
    selectObject: .l
    .el = Get energy: 0, 0
    selectObject: .r
    .er = Get energy: 0, 0
    selectObject: .mo
    .em = Get energy: 0, 0
    measureStereo.monoLoss = if .el + .er > 0 then 10 * log10(max(1e-12, .em / ((.el + .er) / 2))) else 0 fi
    selectObject: .lr
    .lrm = Get mean: 0, 0, 0
    .du = if measureStereo.nSamp = nOut then gdur else measureStereo.nSamp / srOut fi
    measureStereo.corr = if .el > 0 and .er > 0 then .lrm * .du / sqrt(.el * .er) else 1 fi
    .nw = floor(.du / 0.05)
    measureStereo.nWin = 0
    measureStereo.posMin = 1
    measureStereo.posMax = -1
    measureStereo.widthMin = 2
    measureStereo.widthMax = -1
    for .w from 1 to .nw
        .a = (.w - 1) * 0.05
        .b = .w * 0.05
        selectObject: .l
        .rl = Get root-mean-square: .a, .b
        selectObject: .r
        .rr = Get root-mean-square: .a, .b
        selectObject: .lr
        .m = Get mean: 0, .a, .b
        if .rl + .rr > 1e-4
            measureStereo.nWin = measureStereo.nWin + 1
            .q = measureStereo.nWin
            mwT[.q] = (.a + .b) / 2
            mwPos[.q] = 4 / pi * arctan2(.rr, .rl) - 1
            .cc = .m / max(1e-12, .rl * .rr)
            mwWid[.q] = max(0, min(2, 1 - .cc))
            measureStereo.posMin = min(measureStereo.posMin, mwPos[.q])
            measureStereo.posMax = max(measureStereo.posMax, mwPos[.q])
            measureStereo.widthMin = min(measureStereo.widthMin, mwWid[.q])
            measureStereo.widthMax = max(measureStereo.widthMax, mwWid[.q])
        endif
    endfor
    removeObject: .l, .r, .lr, .mo
    # the same width measure on the spectrum above 1 kHz, where the
    # stereo motion lives (lows are kept central on purpose)
    selectObject: .id
    Filter (pass Hann band): 1000, 0, 100
    .hp = selected("Sound")
    Extract one channel: 1
    .hl = selected("Sound")
    selectObject: .hp
    Extract one channel: 2
    .hr = selected("Sound")
    Copy: "sgf_hlr"
    .hlr = selected("Sound")
    Formula: "self * object[" + string$(.hl) + ", 1, col]"
    .s = 0
    .n = 0
    measureStereo.widthHiMin = 2
    measureStereo.widthHiMax = -1
    .hmx = 0
    for .w from 1 to .nw
        selectObject: .hl
        .hq1[.w] = Get root-mean-square: (.w - 1) * 0.05, .w * 0.05
        selectObject: .hr
        .hq2[.w] = Get root-mean-square: (.w - 1) * 0.05, .w * 0.05
        selectObject: .hlr
        .hm[.w] = Get mean: 0, (.w - 1) * 0.05, .w * 0.05
        .hmx = max(.hmx, .hq1[.w] + .hq2[.w])
    endfor
    for .w from 1 to .nw
        if .hmx > 0 and .hq1[.w] + .hq2[.w] > .hmx * 10 ^ (-30 / 20)
            .wd = max(0, min(2, 1 - .hm[.w] / max(1e-12, .hq1[.w] * .hq2[.w])))
            .s = .s + .wd
            .n = .n + 1
            measureStereo.widthHiMin = min(measureStereo.widthHiMin, .wd)
            measureStereo.widthHiMax = max(measureStereo.widthHiMax, .wd)
        endif
    endfor
    measureStereo.widthHiMean = if .n > 0 then .s / .n else undefined fi
    removeObject: .hp, .hl, .hr, .hlr
endproc

# Measured level of each band over time (mono sum, band-filtered with
# the same band shapes) against the planned band curves: correlation of
# the dB curves where the plan is within 40 dB of its maximum.
procedure measureBands: .id
    selectObject: .id
    .ns = Get number of samples
    .du = if .ns = nOut then gdur else .ns / srOut fi
    Convert to mono
    .mo = selected("Sound")
    selectObject: .id
    Extract one channel: 1
    .chL = selected("Sound")
    selectObject: .id
    Extract one channel: 2
    .chR = selected("Sound")
    .npw = floor(.du / 0.05)
    # bands that carry almost none of the intended energy (e.g. above the
    # Nyquist frequency of every source) are not scored
    .btMax = 0
    for .b from 1 to nBand
        .bt[.b] = 0
        for .ii from 1 to nFr
            .bt[.b] = .bt[.b] + tgtE[.b, .ii]
        endfor
        .btMax = max(.btMax, .bt[.b])
    endfor
    .nw = floor(.du / 0.02)
    .cs = 0
    .cn = 0
    measureBands.corrMin = 1
    for .b from 1 to nBand
        selectObject: .mo
        # the same regions the intended energies use, with 15 % sine-
        # squared edges (a brick-wall FFT filter leaks over the whole
        # sound in time and would show energy before the onset)
        .lo = max(20, bandLo[.b])
        .hi = bandHi[.b]
        .sh$ = "(if x < " + string$(.lo / 1.15) + " then 0 else if x < " + string$(.lo * 1.15) + " then sin(pi / 4 * (1 + ln(x / "
            ... + string$(.lo) + ") / ln(1.15)))^2 else 1 fi fi)"
        if .b < nBand
            .sh$ = .sh$ + " * (if x > " + string$(.hi * 1.15) + " then 0 else if x > " + string$(.hi / 1.15) + " then cos(pi / 4 * (1 + ln(x / "
                ... + string$(.hi) + ") / ln(1.15)))^2 else 1 fi fi)"
        endif
        Filter (formula): "self * (" + .sh$ + ")"
        .fb = selected("Sound")
        # measured position of this band (equal-power balance of the
        # band-filtered L and R, 50 ms windows within 30 dB of its peak)
        selectObject: .chL
        Filter (formula): "self * (" + .sh$ + ")"
        .fl = selected("Sound")
        selectObject: .chR
        Filter (formula): "self * (" + .sh$ + ")"
        .fr = selected("Sound")
        .rmx = 0
        for .w from 1 to .npw
            selectObject: .fl
            .ql[.w] = Get root-mean-square: (.w - 1) * 0.05, .w * 0.05
            selectObject: .fr
            .qr[.w] = Get root-mean-square: (.w - 1) * 0.05, .w * 0.05
            .rmx = max(.rmx, .ql[.w] + .qr[.w])
        endfor
        bandPosMin[.b] = undefined
        bandPosMax[.b] = undefined
        for .w from 1 to .npw
            bandPosT[.w] = (.w - 0.5) * 0.05
            if .rmx > 0 and .ql[.w] + .qr[.w] > .rmx * 10 ^ (-30 / 20)
                bandPos[.b, .w] = 4 / pi * arctan2(.qr[.w], .ql[.w]) - 1
                if bandPosMin[.b] = undefined
                    bandPosMin[.b] = bandPos[.b, .w]
                    bandPosMax[.b] = bandPos[.b, .w]
                else
                    bandPosMin[.b] = min(bandPosMin[.b], bandPos[.b, .w])
                    bandPosMax[.b] = max(bandPosMax[.b], bandPos[.b, .w])
                endif
            else
                bandPos[.b, .w] = undefined
            endif
        endfor
        removeObject: .fl, .fr
        selectObject: .fb
        .pmax = 0
        for .ii from 1 to nFr
            .pmax = max(.pmax, sqrt(tgtE[.b, .ii]))
        endfor
        .n = 0
        for .w from 1 to .nw
            .a = (.w - 1) * 0.02
            .tm = .a + 0.01
            .v = Get root-mean-square: .a, .a + 0.02
            measLev[.b, .w] = 20 * log10(max(.v, 1e-9))
            measT[.w] = .tm
            # planned level at this time (frame grid, nearest)
            .ii = round(.tm * srOut / hop) - iFirst + 1
            .ii = max(1, min(nFr, .ii))
            .pv = sqrt(tgtE[.b, .ii])
            if .pmax > 0 and .pv > .pmax * 0.01
                .n = .n + 1
                .xa[.n] = 20 * log10(.pv)
                .xb[.n] = measLev[.b, .w]
            endif
        endfor
        removeObject: .fb
        bandCorr[.b] = undefined
        bandMinor[.b] = .bt[.b] < 1e-4 * .btMax
        if .n >= 8 and bandMinor[.b] = 0
            .ma = 0
            .mb = 0
            for .q from 1 to .n
                .ma = .ma + .xa[.q]
                .mb = .mb + .xb[.q]
            endfor
            .ma = .ma / .n
            .mb = .mb / .n
            .sab = 0
            .saa = 0
            .sbb = 0
            for .q from 1 to .n
                .sab = .sab + (.xa[.q] - .ma) * (.xb[.q] - .mb)
                .saa = .saa + (.xa[.q] - .ma) ^ 2
                .sbb = .sbb + (.xb[.q] - .mb) ^ 2
            endfor
            if .saa > 0 and .sbb > 0
                bandCorr[.b] = .sab / sqrt(.saa * .sbb)
                .cs = .cs + bandCorr[.b]
                .cn = .cn + 1
                measureBands.corrMin = min(measureBands.corrMin, bandCorr[.b])
            endif
        endif
    endfor
    measNWin = .nw
    bandPosN = .npw
    measureBands.corrMean = if .cn > 0 then .cs / .cn else undefined fi
    removeObject: .mo, .chL, .chR
endproc

procedure nameFree: .b$
    nameFree.ok = 1
    if fileReadable(.b$ + ".wav") or fileReadable(.b$ + "_metadata.txt")
        nameFree.ok = 0
    endif
    if fileReadable(.b$ + "_mix.wav") or fileReadable(.b$ + "_static.wav")
        nameFree.ok = 0
    endif
endproc

procedure saveWav: .id, .path$
    selectObject: .id
    nocheck Save as 24-bit WAV file: .path$
    if fileReadable(.path$) = 0
        @fail: "Could not write " + .path$ + " (disk full or no permission?)."
    endif
    nSaved = nSaved + 1
    saved$[nSaved] = .path$
endproc

procedure writeMetadata: .path$
    .t$ = "Spectral Gesture Forge v" + sgfVersion$ + " - metadata" + newline$
    .t$ = .t$ + "praat_version" + tab$ + praatVersion$ + newline$
    .t$ = .t$ + "output_wav" + tab$ + saved$[1] + newline$
    .t$ = .t$ + "duration_s" + tab$ + fixed$(gdur, 6) + newline$
    .t$ = .t$ + "rendered_duration_s" + tab$ + fixed$(outDurMain, 6) + newline$
    .t$ = .t$ + "samples" + tab$ + string$(nOut) + newline$
    .t$ = .t$ + "sample_rate" + tab$ + string$(srOut) + newline$
    .t$ = .t$ + "gesture_character" + tab$ + charName$[character] + newline$
    .t$ = .t$ + "random_seed" + tab$ + string$(random_seed) + newline$
    .t$ = .t$ + "source_selection" + tab$ + selName$[source_selection] + newline$
    .t$ = .t$ + "envelope_sharpness_pct" + tab$ + string$(envelope_sharpness) + newline$
    .t$ = .t$ + "spectral_variation_pct" + tab$ + string$(spectral_variation) + newline$
    .t$ = .t$ + "spectral_fusion_strength_pct" + tab$ + string$(spectral_fusion_strength) + newline$
    .t$ = .t$ + "power_mean_exponent_p" + tab$ + fixed$(pFuse, 4) + newline$
    .t$ = .t$ + "motion_preset" + tab$ + motName$[motion_preset] + newline$
    .t$ = .t$ + "stereo_width_pct" + tab$ + string$(stereo_width) + newline$
    .t$ = .t$ + "motion_amount_pct" + tab$ + string$(motion_amount) + newline$
    .t$ = .t$ + "fft_size" + tab$ + string$(nW) + newline$
    .t$ = .t$ + "hop" + tab$ + string$(hop) + newline$
    .t$ = .t$ + "headroom_dbfs" + tab$ + string$(headroomDb) + newline$
    .t$ = .t$ + "reverb_mode" + tab$ + revName$[reverb_mode] + newline$
    .t$ = .t$ + "reverb_amount_pct" + tab$ + string$(reverb_amount) + newline$
    .t$ = .t$ + "reverb_average_decay_s" + tab$ + fixed$(rvAvg, 3) + newline$
    .t$ = .t$ + "reverb_decay_diversity_pct" + tab$ + string$(reverb_decay_diversity) + newline$
    .t$ = .t$ + "reverb_pre_delay_ms" + tab$ + string$(pre_delay) + newline$
    .t$ = .t$ + "reverb_damping_pct" + tab$ + string$(reverb_damping) + newline$
    .t$ = .t$ + "tail_mode" + tab$ + tailName$[tail_mode] + newline$
    .t$ = .t$ + "tail_room_max_s" + tab$ + fixed$(tailMax, 3) + newline$
    if globNeeded
        .t$ = .t$ + "global_reverb_t60_s" + tab$ + fixed$(rvGT, 3) + newline$
        .t$ = .t$ + "global_reverb_pre_delay_ms" + tab$ + fixed$(rvGP * 1000, 1) + newline$
        .t$ = .t$ + "global_reverb_wet" + tab$ + fixed$(if srcRev then 0.6 * rvAmt else rvAmt fi, 3) + newline$
    endif
    .t$ = .t$ + "normalisation_gain_db" + tab$ + fixed$(fullGainDb, 3) + newline$
    .t$ = .t$ + "folders" + tab$ + string$(nFold) + newline$
    for .f from 1 to nFold
        .t$ = .t$ + "folder_" + string$(.f) + tab$ + foldPath$[.f] + newline$
    endfor
    .t$ = .t$ + "sources" + tab$ + string$(nSrc) + newline$
    for .k from 1 to nSrc
        .s$ = "source_" + string$(.k)
        .t$ = .t$ + .s$ + "_path" + tab$ + srcPath$[.k] + newline$
        .t$ = .t$ + .s$ + "_region_start_s" + tab$ + fixed$(srcAtt[.k], 6) + newline$
        .t$ = .t$ + .s$ + "_attack_rank" + tab$ + string$(srcAttIdx[.k]) + newline$
        .t$ = .t$ + .s$ + "_read_rate" + tab$ + fixed$(srcRate[.k], 4) + newline$
        .t$ = .t$ + .s$ + "_input_rate_channels" + tab$ + string$(srcSrIn[.k]) + " Hz, " + string$(srcNchIn[.k]) + " ch" + newline$
        if wetNeeded
            .t$ = .t$ + .s$ + "_reverb_t60_s" + tab$ + fixed$(rvT[.k], 3) + newline$
            .t$ = .t$ + .s$ + "_reverb_pre_delay_ms" + tab$ + fixed$(rvP[.k] * 1000, 1) + newline$
            .t$ = .t$ + .s$ + "_reverb_wet" + tab$ + fixed$(rvW[.k], 3) + newline$
            .t$ = .t$ + .s$ + "_reverb_damping" + tab$ + fixed$(rvD[.k], 3) + newline$
            .t$ = .t$ + .s$ + "_reverb_diffusion" + tab$ + fixed$(rvF[.k], 3) + " (" + fixed$(rvDens[.k], 0) + " /s, " + string$(rvNER[.k]) + " early reflections)" + newline$
        endif
    endfor
    for .q from 2 to nSaved
        .t$ = .t$ + "comparison_file" + tab$ + saved$[.q] + newline$
    endfor
    .t$ = .t$ + "note" + tab$ + "Re-running the script with these settings, folders and seed reproduces the gesture while the folder contents are unchanged." + newline$
    nocheck writeFile: .path$, .t$
    if fileReadable(.path$) = 0
        @fail: "Could not write " + .path$
    endif
    nSaved = nSaved + 1
    saved$[nSaved] = .path$
endproc

# Text for the Picture window: escape Praat's markup characters
procedure pic: .s$
    .s$ = replace$(.s$, "\", "\bs", 0)
    .s$ = replace$(.s$, "_", "\_ ", 0)
    .s$ = replace$(.s$, "%", "\% ", 0)
    .s$ = replace$(.s$, "#", "\# ", 0)
    .s$ = replace$(.s$, "^", "\^ ", 0)
    pic.out$ = .s$
endproc

procedure bandColour: .b
    if .b = 1
        bandColour.c$ = "{0.55, 0.15, 0.10}"
    elsif .b = 2
        bandColour.c$ = "{0.85, 0.40, 0.10}"
    elsif .b = 3
        bandColour.c$ = "{0.80, 0.70, 0.10}"
    elsif .b = 4
        bandColour.c$ = "{0.20, 0.60, 0.30}"
    elsif .b = 5
        bandColour.c$ = "{0.15, 0.45, 0.80}"
    else
        bandColour.c$ = "{0.50, 0.25, 0.75}"
    endif
endproc

# fixed$ with true rounding (fixed$ prints tiny values with extra digits)
procedure fx: .v, .d
    if .v = undefined
        fx.s$ = "--"
    else
        .r = round(.v * 10 ^ .d) / 10 ^ .d
        fx.s$ = if .r = 0 then fixed$(0, .d) else fixed$(.r, .d) fi
        if .r = 0 and .d > 0
            fx.s$ = "0." + left$("000000", .d)
        endif
    endif
endproc

procedure niceStep: .span, .n
    .raw = .span / .n
    .p = 10 ^ floor(log10(.raw))
    .m = .raw / .p
    if .m < 1.5
        niceStep.s = .p
    elsif .m < 3.5
        niceStep.s = 2 * .p
    elsif .m < 7.5
        niceStep.s = 5 * .p
    else
        niceStep.s = 10 * .p
    endif
endproc

procedure drawFigure
    .fd = outDurMain
    Erase all
    # ---- title ----
    Font size: 14
    Select inner viewport: 0.6, 7.7, 0.05, 0.55
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "##SPECTRAL GESTURE FORGE v" + sgfVersion$ + "##"
    Font size: 7
    Select inner viewport: 0.6, 7.7, 0.05, 0.55
    Axes: 0, 1, 0, 1
    .s$ = charName$[character] + "  |  " + fixed$(gdur, 2) + " s" + if nOutMain > nOut then " + tail " + fixed$(outDurMain - gdur, 2) + " s" else "" fi + "  |  " + string$(nSrc) + " source(s), "
        ... + selName$[source_selection] + "  |  fusion " + fixed$(spectral_fusion_strength, 0) + " %  (p = "
        ... + fixed$(pFuse, 2) + ")  |  sharpness " + fixed$(envelope_sharpness, 0) + " %  |  " + motName$[motion_preset]
        ... + ", width " + fixed$(stereo_width, 0) + " %  |  seed " + string$(random_seed)
    @pic: .s$
    Colour: "{0.30, 0.30, 0.45}"
    Text: 0.5, "centre", 0.15, "half", pic.out$

    # ---- A: spectrogram of the result (mono sum) ----
    selectObject: fullID
    Convert to mono
    .mo = selected("Sound")
    .fTop = min(nyq, 16000)
    To Spectrogram: 0.01, .fTop, 0.002, 20, "Gaussian"
    .sg = selected("Spectrogram")
    Font size: 7
    Select inner viewport: 0.6, 7.7, 0.95, 2.75
    Paint: 0, 0, 0, 0, 100, "yes", 60, 6, 0, "no"
    Font size: 7
    Select inner viewport: 0.6, 7.7, 0.95, 2.75
    Axes: 0, .fd, 0, .fTop
    Colour: "{0.20, 0.40, 0.80}"
    Dotted line
    for .b from 1 to nBand - 1
        if bandEdge[.b] < .fTop
            Draw line: 0, bandEdge[.b], .fd, bandEdge[.b]
        endif
    endfor
    Solid line
    if nOutMain > nOut
        Colour: "{0.80, 0.20, 0.20}"
        Dashed line
        Draw line: gdur, 0, gdur, .fTop
        Solid line
    endif
    Colour: "Black"
    Select inner viewport: 0.6, 7.7, 0.95, 2.75
    Axes: 0, .fd, 0, .fTop
    Draw inner box
    @niceStep: .fTop, 4
    .fm = 0
    while .fm <= .fTop + 1
        One mark left: .fm, "no", "yes", "no", if .fm = 0 then "0" else fixed$(.fm / 1000, 0) fi
        .fm = .fm + niceStep.s
    endwhile
    Text left: "yes", "kHz"
    Text top: "no", "##A##  Result (mono sum) - dotted lines: the six fusion bands"
    removeObject: .sg

    # ---- B: planned band envelopes (lines) and measured band levels ----
    .yTop = 0
    .yBot = -48
    Font size: 7
    Select inner viewport: 0.6, 7.7, 3.35, 5.0
    Axes: 0, .fd, .yBot, .yTop
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, .fd, .yBot, .yTop
    .pmax = 1e-12
    for .b from 1 to nBand
        for .ii from 1 to nFr
            .pmax = max(.pmax, sqrt(tgtE[.b, .ii]))
        endfor
    endfor
    .mmax = -300
    for .b from 1 to nBand
        for .w from 1 to measNWin
            .mmax = max(.mmax, measLev[.b, .w])
        endfor
    endfor
    Line width: 1.5
    for .b from 1 to nBand
        @bandColour: .b
        Colour: bandColour.c$
        for .ii from 2 to nFr
            if frT[.ii] > 0 and frT[.ii] <= .fd
                .y1 = max(.yBot, 20 * log10(max(sqrt(tgtE[.b, .ii - 1]), 1e-12) / .pmax))
                .y2 = max(.yBot, 20 * log10(max(sqrt(tgtE[.b, .ii]), 1e-12) / .pmax))
                Draw line: max(0, frT[.ii - 1]), .y1, frT[.ii], .y2
            endif
        endfor
    endfor
    Line width: 1
    Dotted line
    for .b from 1 to nBand
        @bandColour: .b
        Colour: bandColour.c$
        for .w from 2 to measNWin
            .y1 = max(.yBot, min(.yTop, measLev[.b, .w - 1] - .mmax))
            .y2 = max(.yBot, min(.yTop, measLev[.b, .w] - .mmax))
            Draw line: measT[.w - 1], .y1, measT[.w], .y2
        endfor
    endfor
    Solid line
    if nOutMain > nOut
        Colour: "{0.80, 0.20, 0.20}"
        Dashed line
        Draw line: gdur, .yBot, gdur, .yTop
        Solid line
    endif
    Colour: "Black"
    Select inner viewport: 0.6, 7.7, 3.35, 5.0
    Axes: 0, .fd, .yBot, .yTop
    Draw inner box
    Marks left every: 1, 12, "yes", "yes", "no"
    Text left: "yes", "dB"
    Text top: "no", "##B##  Band levels: intended by the fusion (solid), measured in the result (dotted)" + if globRev then " - global reverb adds to the measured" else "" fi
    # band legend
    Font size: 6
    Select inner viewport: 0.6, 7.7, 3.35, 5.0
    Axes: 0, 1, 0, 1
    for .b from 1 to nBand
        @bandColour: .b
        Colour: bandColour.c$
        .lb$ = if bandC[.b] >= 1000 then fixed$(bandC[.b] / 1000, 1) + " kHz" else fixed$(bandC[.b], 0) + " Hz" fi
        Text: 0.985, "right", 0.95 - 0.075 * (.b - 1), "half", .lb$
    endfor
    Colour: "Black"

    # ---- C: source x band levels ----
    Font size: 7
    .nR = nMainMem
    Select inner viewport: 1.3, 3.9, 5.6, 7.15
    Axes: 0, nBand, .nR, 0
    .lmax = 1e-9
    for .kb from 1 to .nR * nBand
        .lmax = max(.lmax, eLev[.kb])
    endfor
    for .k from 1 to .nR
        for .b from 1 to nBand
            .kb = (.k - 1) * nBand + .b
            .g = 1 - 0.85 * eLev[.kb] / .lmax
            Paint rectangle: "{" + fixed$(.g, 3) + ", " + fixed$(.g, 3) + ", " + fixed$(min(1, .g + 0.08), 3) + "}", .b - 1, .b, .k - 1, .k
        endfor
    endfor
    Select inner viewport: 1.3, 3.9, 5.6, 7.15
    Axes: 0, nBand, .nR, 0
    Colour: "White"
    for .b from 1 to nBand - 1
        Draw line: .b, 0, .b, .nR
    endfor
    for .k from 1 to .nR - 1
        Draw line: 0, .k, nBand, .k
    endfor
    Colour: "Black"
    Select inner viewport: 1.3, 3.9, 5.6, 7.15
    Axes: 0, nBand, .nR, 0
    Draw inner box
    for .b from 1 to nBand
        .lb$ = if bandC[.b] >= 1000 then fixed$(bandC[.b] / 1000, 1) + "k" else fixed$(bandC[.b], 0) fi
        One mark bottom: .b - 0.5, "no", "no", "no", .lb$
    endfor
    Text bottom: "yes", "band centre (Hz)"
    Text top: "no", "##C##  " + if .nR > nSrc then "Direct and reverberant (rev) level per band" else "Source level per band (darker = louder)" fi
    Font size: 6
    Select inner viewport: 1.3, 3.9, 5.6, 7.15
    Axes: 0, 1, .nR, 0
    for .k from 1 to .nR
        @pic: left$(srcName$[.k], 22)
        Text: -0.02, "right", .k - 0.5, "half", pic.out$
    endfor

    # ---- D: measured position of each band ----
    Font size: 7
    Select inner viewport: 4.55, 7.7, 5.6, 7.15
    Axes: 0, .fd, -1.1, 1.1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, .fd, -1.1, 1.1
    Colour: "{0.75, 0.75, 0.75}"
    Dotted line
    Draw line: 0, 0, .fd, 0
    Solid line
    Line width: 1.5
    for .b from 1 to nBand
        @bandColour: .b
        Colour: bandColour.c$
        for .w from 2 to bandPosN
            if bandPos[.b, .w - 1] <> undefined and bandPos[.b, .w] <> undefined
                Draw line: bandPosT[.w - 1], bandPos[.b, .w - 1], bandPosT[.w], bandPos[.b, .w]
            endif
        endfor
    endfor
    Line width: 1
    Colour: "Black"
    Select inner viewport: 4.55, 7.7, 5.6, 7.15
    Axes: 0, .fd, -1.1, 1.1
    Draw inner box
    One mark left: -1, "no", "yes", "no", "L"
    One mark left: 0, "no", "yes", "no", "C"
    One mark left: 1, "no", "yes", "no", "R"
    @niceStep: .fd, 4
    Marks bottom every: 1, niceStep.s, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "##D##  Measured position of each band in the result"

    # ---- E: waveform ----
    selectObject: fullID
    Font size: 7
    Select inner viewport: 0.6, 7.7, 7.75, 8.75
    Draw: 0, 0, -1, 1, "no", "Curve"
    Select inner viewport: 0.6, 7.7, 7.75, 8.75
    Axes: 0, .fd, -1, 1
    Draw inner box
    @niceStep: .fd, 8
    Marks bottom every: 1, niceStep.s, "yes", "yes", "no"
    if nOutMain > nOut
        Select inner viewport: 0.6, 7.7, 7.75, 8.75
        Axes: 0, .fd, -1, 1
        Colour: "{0.80, 0.20, 0.20}"
        Dashed line
        Draw line: gdur, -1, gdur, 1
        Solid line
        Colour: "Black"
    endif
    Text top: "no", "##E##  Waveform (L above, R below), peak " + fixed$(mPeakDb, 1) + " dBFS" + if nOutMain > nOut then " - dashed: end of the gesture, then the reverberant tail" else "" fi
    removeObject: .mo

    # ---- summary ----
    Font size: 6
    Select inner viewport: 0.6, 7.7, 9.25, 10.15
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "{0.28, 0.28, 0.28}"
    .l1$ = "Sources: "
    for .k from 1 to nSrc
        .l1$ = .l1$ + srcName$[.k] + if .k < nSrc then ", " else "" fi
    endfor
    @pic: .l1$
    Text: 0.015, "left", 0.80, "half", pic.out$
    .l2$ = "Band levels intended vs measured (dB correlation): mean " + fixed$(envCorrMean, 2)
        ... + ", lowest " + fixed$(envCorrMin, 2) + "  |  width above 1 kHz (1 - L/R corr.) " + fixed$(mWidthHiMin, 2) + " to "
        ... + fixed$(mWidthHiMax, 2) + ", overall L/R corr. " + fixed$(mCorr, 2)
    @pic: .l2$
    Text: 0.015, "left", 0.50, "half", pic.out$
    .l3$ = "Mono fold-down " + fixed$(mMonoLoss, 2) + " dB  |  peak " + fixed$(mPeakDb, 1) + " dBFS, RMS " + fixed$(mRmsDb, 1)
        ... + " dBFS  |  " + string$(nFr) + " frames of " + string$(nW) + " at " + string$(srOut) + " Hz  |  render "
        ... + fixed$(tRender, 1) + " s" + if reverb_mode > 1 then "  |  reverb: " + revName$[reverb_mode] + ", " + tailName$[tail_mode] else "" fi
    @pic: .l3$
    Text: 0.015, "left", 0.20, "half", pic.out$
    Colour: "Black"
    Select inner viewport: 0.6, 7.7, 9.25, 10.15
    Axes: 0, 1, 0, 1
    Draw inner box
    Select outer viewport: 0, 8, 0, 10.3
endproc

procedure report
    appendInfoLine: ""
    appendInfoLine: "Gesture: ", charName$[character], ", ", fixed$(gdur, 3), " s (", nOut, " samples at ", srOut, " Hz)",
        ... if nOutMain > nOut then ", with reverberant tail " + fixed$(outDurMain, 3) + " s" else "" fi
    appendInfoLine: "  Envelope sharpness ", envelope_sharpness, " %, spectral variation ", spectral_variation,
        ... " %, fusion strength ", spectral_fusion_strength, " % (power-mean exponent p = ", fixed$(pFuse, 3), ")"
    if character = 5
        .bt$ = ""
        for .b from 1 to nBand
            .bt$ = .bt$ + charName$[bType[.b]] + if .b < nBand then ", " else "" fi
        endfor
        appendInfoLine: "  Hybrid band behaviours (low to high): ", .bt$
    endif
    if character = 4
        appendInfoLine: "  Pulses: ", pulN, " at ", fixed$(pulT[1], 3), ", ", fixed$(pulT[2], 3), if pulN = 3 then ", " + fixed$(pulT[3], 3) else "" fi, " s"
    endif
    if character = 3
        appendInfoLine: "  Reverse peak at ", fixed$(revTp, 3), " s"
    endif
    appendInfoLine: "Sources (", selName$[source_selection], "):"
    for .k from 1 to nSrc
        .lv$ = ""
        for .b from 1 to nBand
            .lv$ = .lv$ + fixed$(eLev[(.k - 1) * nBand + .b], 2) + if .b < nBand then " " else "" fi
        endfor
        appendInfoLine: "  ", .k, " ", srcFold$[.k], "/", srcName$[.k], " (", srcSrIn[.k], " Hz, ", srcNchIn[.k], " ch)",
            ... "  region from ", fixed$(srcAtt[.k], 3), " s (attack ", srcAttIdx[.k], ")",
            ... "  read rate ", fixed$(srcRate[.k], 2), if srcEnd[.k] < gdur then ", material ends at " + fixed$(srcEnd[.k], 2) + " s" else "" fi
        appendInfoLine: "      tonality ", fixed$(srcTon[.k], 2), ", centroid ", fixed$(srcCog[.k], 0), " Hz, band levels (low-high) ", .lv$
    endfor
    if source_selection = 2
        appendInfoLine: "  complementarity score ", fixed$(selScore, 3), " (contrast ", fixed$(selContrast, 2), ", coverage ",
            ... fixed$(selCoverage, 2), ", centroid spread ", fixed$(selSpread, 2), ", tonal diversity ", fixed$(selTonal, 2), ")"
    endif
    appendInfoLine: "Stereo: ", motName$[motion_preset], ", width ", stereo_width, " %, motion ", motion_amount, " %"
    appendInfoLine: "  measured balance ", fixed$(mPosMin, 2), " to ", fixed$(mPosMax, 2), " (L -1 ... R +1), width (1 - L/R correlation, 50 ms) ",
        ... fixed$(mWidthMin, 2), " to ", fixed$(mWidthMax, 2), ", overall L/R correlation ", fixed$(mCorr, 3)
    appendInfoLine: "  above 1 kHz: width ", fixed$(mWidthHiMin, 2), " to ", fixed$(mWidthHiMax, 2), " (mean ", fixed$(mWidthHiMean, 2), ")"
    .bp$ = ""
    for .b from 1 to nBand
        .bp$ = .bp$ + if bandPosMin[.b] = undefined then "-" else fixed$(bandPosMin[.b], 2) + ".." + fixed$(bandPosMax[.b], 2) fi + if .b < nBand then "  " else "" fi
    endfor
    appendInfoLine: "  measured position range per band (low-high): ", .bp$
    @fx: mMonoLoss, 2
    appendInfoLine: "  mono fold-down: ", fx.s$, " dB (0 = none; lows share one phase, highs differ by at most +/-",
        ... fixed$(rotPhiMax * 90 / pi, 0), " deg)"
    appendInfoLine: "Checks:"
    appendInfoLine: "  duration ", if mDurOK then "exact (" + string$(nOutMain) + " samples)" else "WRONG" fi, ", peak ", fixed$(mPeakDb, 2),
        ... " dBFS (normalised, gain ", fixed$(fullGainDb, 1), " dB), RMS ", fixed$(mRmsDb, 1), " dBFS"
    .bc$ = ""
    for .b from 1 to nBand
        .bc$ = .bc$ + if bandMinor[.b] then "n/a" else if bandCorr[.b] = undefined then "-" else fixed$(bandCorr[.b], 2) fi fi + if .b < nBand then " " else "" fi
    endfor
    appendInfoLine: "  band levels, intended vs measured in the result (correlation of dB curves, low-high): ", .bc$
    appendInfoLine: "    (n/a = the band carries under -40 dB of the intended energy, e.g. above every source's Nyquist frequency)"
    appendInfoLine: "  band-frames needing more than +12 dB (capped, bands within 30 dB of the frame's strongest): ", capFull, ", low-band guard active: ", lowFull, " (of ", nFr * 2, " channel frames)"
    if reverb_mode > 1 or compRV
        appendInfoLine: "Reverberation: ", revName$[reverb_mode], if compRV and reverb_mode = 1 then " (built only for the comparison)" else "" fi,
            ... ", amount ", reverb_amount, " %, average decay ", fixed$(rvAvg, 2), " s, diversity ", reverb_decay_diversity,
            ... " %, pre-delay ", pre_delay, " ms, damping ", reverb_damping, " %, tail ", tailName$[tail_mode]
        if wetNeeded
            appendInfoLine: "  per-source reverbs (T60 below 600 Hz, s / pre-delay ms / wet / damping / diffusion; mid and high decay shorten with damping):"
            for .k from 1 to nSrc
                appendInfoLine: "    ", srcName$[.k], ": ", fixed$(rvT[.k], 2), " / ", fixed$(rvP[.k] * 1000, 0), " / ", fixed$(rvW[.k], 2),
                    ... " / ", fixed$(rvD[.k], 2), " / ", fixed$(rvF[.k], 2)
            endfor
            if srcRev
                @fx: wetGateCut * 100, 1
                appendInfoLine: "  reverberant weight removed by the material gate: ", fx.s$, " % (quiet reverb kept unless 30-40 dB below the strongest member in its band)"
            endif
        endif
        if globNeeded
            appendInfoLine: "  global reverb: T60 ", fixed$(rvGT, 2), " s, pre-delay ", fixed$(rvGP * 1000, 0), " ms, wet ",
                ... fixed$(if srcRev then 0.6 * rvAmt else rvAmt fi, 2), if srcRev then " (60 % of the amount: per-source reverb already present)" else "" fi
        endif
        appendInfoLine: "  durations: gesture ", fixed$(gdur, 3), " s, rendered ", fixed$(outDurMain, 3), " s",
            ... if extTail then " (tail room at most " + fixed$(tailMax, 2) + " s, cut 50 ms after the last window within 60 dB of the peak)" else "" fi
    endif
    if compRV
        appendInfoLine: "Reverb comparison (level-matched: equal RMS over the gesture, loudest crest at ", headroomDb, " dBFS):"
        for .q from 1 to 4
            @fx: cmpWid[.q], 2
            .w$ = fx.s$
            @fx: cmpMono[.q], 2
            appendInfoLine: "  ", objBase$, "_", cmpSuf$[.q], ": ", fixed$(cmpDur[.q], 2), " s, peak ", fixed$(cmpPeak[.q], 1), " dBFS, RMS ",
                ... fixed$(cmpRms[.q], 1), " dBFS, width >1 kHz ", .w$, ", balance range ", fixed$(cmpPosR[.q], 2), ", mono fold-down ", fx.s$, " dB"
        endfor
    endif
    if compMS
        appendInfoLine: "Comparison set (each normalised to ", headroomDb, " dBFS):"
        @fx: xWidthHiMean, 2
        .a$ = fx.s$
        @fx: xMonoLoss, 2
        appendInfoLine: "  1 conventional mix   ", objBase$, "_mix     L/R corr. ", fixed$(xCorr, 3), ", width >1 kHz ", .a$, ", mono fold-down ", fx.s$, " dB"
        @fx: sWidthHiMean, 2
        .a$ = fx.s$
        @fx: sMonoLoss, 2
        appendInfoLine: "  2 static fusion      ", objBase$, "_static  L/R corr. ", fixed$(sCorr, 3), ", width >1 kHz ", .a$, ", mono fold-down ", fx.s$, " dB"
        @fx: mWidthHiMean, 2
        .a$ = fx.s$
        @fx: mMonoLoss, 2
        appendInfoLine: "  3 full fusion        ", objBase$, "         L/R corr. ", fixed$(mCorr, 3), ", width >1 kHz ", .a$, ", mono fold-down ", fx.s$, " dB"
        appendInfoLine: "  All three use the same sources, regions and band envelopes; band LEVELS are matched by design,"
        appendInfoLine: "  so the difference lies in the spectral fine structure (fusion) and in the stereo motion."
        appendInfoLine: "  Whether the fusion sounds like one new event rather than a layered mix is a listening judgement."
    endif
    if nSaved > 0
        appendInfoLine: "Files written:"
        for .k from 1 to nSaved
            appendInfoLine: "  ", saved$[.k]
        endfor
    else
        appendInfoLine: "Files written: none"
    endif
    if warnN > 0
        appendInfoLine: "Notes:"
        for .k from 1 to warnN
            appendInfoLine: "  - ", warn$[.k]
        endfor
    endif
    appendInfoLine: "Time: rendering ", fixed$(tRender, 1), " s, total ", fixed$(tAll, 1), " s"
endproc
