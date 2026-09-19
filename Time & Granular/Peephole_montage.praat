# ============================================================
# Praat AudioTools - PEEPHOLE MONTAGE (Demo window)
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2026) - interactive companion to Peephole_montage.praat v0.3
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   PEEPHOLE MONTAGE, played live in the Demo window. Mark listening
#   points on a Sound; each one opens a window ("peephole") around it,
#   and the windows are reassembled in chronological order.
#
#   v0.3 needed two runs (open the editor, mark with Ctrl-P, reselect the
#   Sound + PointProcess, run again with a 20-row form). Here the whole
#   session happens in one Demo window: marks, every setting, previews,
#   and the final commit. The DSP is v0.3's, copied verbatim (edges,
#   pitch shift, PSOLA microscope, adaptive context windows, the three
#   join modes, gain handling), so a commit here equals a v0.3 run with
#   the same marks, settings and seed.
#
# DEMO WINDOW CONTROLS
#   Click the waveform         add a peephole; click on one to remove it
#   Shift-click a peephole     listen to that window alone (source)
#   Click the overview strip   centre the view there
#   Click a control            change a setting (steppers: - / +)
#   U undo marks   C clear marks   + / - / 0 zoom   , / . scroll
#   S play the visible range   N new seed   P preview (build + play)
#   Enter commit   Esc cancel
#   Click the Demo window once so it has keyboard focus.
#
# INPUT
#   Select 1 Sound. Optionally also select a PointProcess (e.g. the
#   peephole_marks of a v0.3 session) to start from its marks.
#
# OUTPUT (on Enter)
#   The montage Sound (Output_name), a PointProcess "peephole_marks" with
#   the final marks (so v0.3 can re-run them in batch), the v0.3 Info
#   report and, optionally, v0.3's edit map in the Picture window.
#
# HONEST LIMITS
#   - Clicks only, no drag: a mark is moved by removing and re-adding it.
#   - Previews block Praat while they render and play (scripting is
#     blocking); PSOLA styles take a moment per peephole.
#   - Undo covers the marks, not the settings (settings are one click
#     back anyway).
#   - The live timeline predicts processed lengths (Microscope: window x
#     factor) until a preview has been built; after that it shows the
#     measured lengths until something changes.
#
# Changelog v1.0:
#   - Interactive Demo-window front end for v0.3: live mark editing with
#     undo and zoom, all settings as clickable controls, live windows
#     (adaptive ones included) and montage timeline, audition of single
#     peepholes, of the view, and of the whole montage before committing.
#   - Form reduced to 5 rows (output name, PSOLA pitch range, edit map,
#     play); all other v0.3 parameters live in the Demo window with
#     v0.3's defaults.
#   - Session seed: previews and the commit use the same seed, so what
#     you preview is what you get (N draws a new one).
# ============================================================

form Peephole Montage (Demo window) v1.0
    comment Marks and all montage settings are made in the Demo window.
    word Output_name peephole_montage
    positive Pitch_floor 75
    positive Pitch_ceiling 600
    boolean Draw_edit_map_in_Picture_window 1
    boolean Play_result 1
endform

if pitch_floor >= pitch_ceiling
    exitScript: "Pitch_floor (", pitch_floor, ") must be below Pitch_ceiling (", pitch_ceiling, ")."
endif

# ---------------------------------------------------------------------------
# v0.3 PARAMETERS - same names and defaults, now set from the Demo window
# ---------------------------------------------------------------------------
window_length = 0.5
asymmetric_windows = 0
pre_length = 0.3
post_length = 0.2
fade_type = 3
fade_duration = 0.01
transition_mode = 1
transition_amount = 0.02
montage_style = 1
uN_random_stereo_flip = 1
uN_pitch_bias_range = 0.5
microscope_time_factor = 2.0
microscope_preserve_pitch = 1
microscope_downmix_stereo = 0
output_gain_handling = 1
peak_target = 0.99
draw_visualization = draw_edit_map_in_Picture_window

styleOpt$[1] = "Pure peephole"
styleOpt$[2] = "Adaptive context"
styleOpt$[3] = "Unreliable narrator"
styleOpt$[4] = "Microscope"
fadeOpt$[1] = "None"
fadeOpt$[2] = "Linear"
fadeOpt$[3] = "Raised cosine"
joinOpt$[1] = "Butt + edge fades"
joinOpt$[2] = "Raised-cos overlap"
joinOpt$[3] = "Gap"
gainOpt$[1] = "Attenuate only"
gainOpt$[2] = "Peak to target"
gainOpt$[3] = "None"

# ---------------------------------------------------------------------------
# INPUT
# ---------------------------------------------------------------------------
n_sounds = numberOfSelected ("Sound")
n_pps = numberOfSelected ("PointProcess")
if n_sounds <> 1 or n_pps > 1
    exitScript: "Select 1 Sound (optionally with 1 PointProcess of marks to start from)."
endif
sound = selected ("Sound")
sound_name$ = selected$ ("Sound")
if n_pps = 1
    ppIn = selected ("PointProcess")
else
    ppIn = 0
endif
selectObject: sound
xmin = Get start time
xmax = Get end time
sample_rate = Get sampling frequency
srcChannels = Get number of channels
srcPeak = Get absolute extremum: 0, 0, "None"
if srcPeak < 0.001
    srcPeak = 0.001
endif

# marks (sorted), optionally preloaded
nMk = 0
preSkipped = 0
if ppIn > 0
    selectObject: ppIn
    ppNp = Get number of points
    for ppI to ppNp
        selectObject: ppIn
        ppT = Get time from index: ppI
        if ppT >= xmin and ppT <= xmax
            nMk += 1
            mkT[nMk] = ppT
        else
            preSkipped += 1
        endif
    endfor
endif

# intensity percentiles for Adaptive context (v0.3 logic, computed once)
intensLo = 40
intensHi = 80
pctOk = 0
selectObject: sound
if srcChannels > 1
    ctxMono = Convert to mono
else
    ctxMono = Copy: "ctx_mono"
endif
ctxInt = To Intensity: 100, 0, "yes"
q10 = Get quantile: 0, 0, 0.10
q90 = Get quantile: 0, 0, 0.90
removeObject: ctxInt, ctxMono
if q10 <> undefined and q90 <> undefined
    if q90 > q10
        intensLo = q10
        intensHi = q90
        pctOk = 1
    endif
endif

# session seed: previews and commit share it
random_initializeSafelyAndUnpredictably ()
seedUsed = randomInteger (1, 2147483646)
random_seed = seedUsed

# ---------------------------------------------------------------------------
# DEMO LAYOUT (window units 0..100, y upward; sx/sy/flipH only for tests)
# ---------------------------------------------------------------------------
sx = 1
sy = 1
flipH = 0
vpL = 7.5
vpR = 96.25
ttlB = 92
ttlT = 99
ovB = 85.5
ovT = 88
srcB = 63
srcT = 84
tlB = 44
tlT = 55
ctlB = 13.5
ctlT = 34
sumB = 1.5
sumT = 11

cPanel$  = "{0.97, 0.97, 0.97}"
cSum$    = "{0.94, 0.94, 0.94}"
cSumTx$  = "{0.25, 0.25, 0.35}"
cSubTx$  = "{0.35, 0.35, 0.50}"
cGrid$   = "{0.80, 0.80, 0.80}"
cInput$  = "{0.55, 0.55, 0.60}"
cPrim$   = "{0.20, 0.48, 0.75}"
cSec$    = "{0.85, 0.38, 0.18}"
cWin$    = "{0.86, 0.91, 0.97}"
cClip$   = "{0.93, 0.88, 0.88}"
cBtn$    = "{0.93, 0.93, 0.95}"
cAct$    = "{0.86, 0.91, 0.97}"
cOff$    = "{0.75, 0.75, 0.78}"

viewT0 = xmin
viewT1 = xmax
minSpan = min (xmax - xmin, 0.05)
nHist = 0
windowsDirty = 1
previewValid = 0
previewSnd = 0
nSeg = 0
finalView = 0
result = 0
status$ = "Click the waveform to place peepholes."
if ppIn > 0
    status$ = "Loaded " + string$ (nMk) + " marks from the PointProcess" + if preSkipped > 0 then " (" + string$ (preSkipped) + " outside the Sound skipped)" else "" fi + "."
endif

###############################################################################
# PROCEDURES FROM v0.3 (verbatim)
###############################################################################

# v0.2: applied to the FINAL segment, after any processing, using the
# measured duration, and clamped so the two halves can never meet.
procedure applyEdges: .seg
    selectObject: .seg
    .d = Get total duration
    .t0 = Get start time
    .t1 = Get end time
    .f = fade_duration
    if .f > .d * 0.45
        .f = .d * 0.45
    endif

    # Concatenate with overlap already applies raised-cosine fades at every
    # internal joint. Do not double-fade individual segments in that mode.
    if transition_mode = 2
        .f = 0
    elsif .f > 0 and fade_type > 1
        if fade_type = 2
            # True linear ramps.
            .inEnd = .t0 + .f
            .outStart = .t1 - .f
            selectObject: .seg
            Formula: "if x < " + fixed$(.inEnd, 12) + " then self * (x - " + fixed$(.t0, 12) + ") / " + fixed$(.f, 12) + " else if x > " + fixed$(.outStart, 12) + " then self * (" + fixed$(.t1, 12) + " - x) / " + fixed$(.f, 12) + " else self fi fi"
        else
            # Praat Fade in/out uses a raised-cosine half-cycle.
            selectObject: .seg
            Fade in: 0, .t0, .f, "yes"
            selectObject: .seg
            Fade out: 0, .t1, -.f, "yes"
        endif
    endif
    applyEdges.used = .f
endproc

# v0.2: shifts BOTH channels by the same ratio, so the stereo image is
# not disturbed. v0.1 skipped stereo entirely.
procedure pitchShift: .snd, .semitones
    .ratio = 2 ^ (.semitones / 12)
    selectObject: .snd
    .nch = Get number of channels

    # Process each channel independently but with the SAME pitch ratio.
    # Fresh channel results are created in channel order and then combined.
    for .ch from 1 to .nch
        selectObject: .snd
        .c[.ch] = Extract one channel: .ch
        selectObject: .c[.ch]
        .m[.ch] = To Manipulation: 0.01, pitch_floor, pitch_ceiling
        .pt[.ch] = Extract pitch tier
        selectObject: .pt[.ch]
        Multiply frequencies: 0, 1e12, .ratio
        selectObject: .m[.ch]
        plusObject: .pt[.ch]
        Replace pitch tier
        selectObject: .m[.ch]
        .r[.ch] = Get resynthesis (overlap-add)
        removeObject: .m[.ch], .pt[.ch], .c[.ch]
    endfor

    if .nch = 1
        pitchShift.result = .r[1]
    else
        selectObject: .r[1]
        for .ch from 2 to .nch
            plusObject: .r[.ch]
        endfor
        pitchShift.result = Combine to stereo
        for .ch from 1 to .nch
            removeObject: .r[.ch]
        endfor
    endif
endproc

procedure stretchMono: .snd, .factor
    selectObject: .snd
    .d = Get total duration
    .m = To Manipulation: 0.01, pitch_floor, pitch_ceiling
    .dt = Extract duration tier
    selectObject: .dt
    Add point: .d / 2, .factor
    selectObject: .m
    plusObject: .dt
    Replace duration tier
    selectObject: .m
    stretchMono.result = Get resynthesis (overlap-add)
    removeObject: .m, .dt
endproc

procedure microscope: .seg, .factor
    selectObject: .seg
    .nch = Get number of channels

    # At factor 1 the PSOLA round trip cannot improve anything and may alter
    # the signal, so bypass it.
    if abs(.factor - 1) < 1e-9
        selectObject: .seg
        microscope.result = Copy: "ms_passthrough"
        microscope.usedPsola = 0
    elsif microscope_preserve_pitch
        if .nch > 1 and microscope_downmix_stereo = 0
            # Preserve arbitrary channel counts. Each channel is analysed
            # independently, as v0.2 already did for stereo.
            for .ch from 1 to .nch
                selectObject: .seg
                .c[.ch] = Extract one channel: .ch
                @stretchMono: .c[.ch], .factor
                .s[.ch] = stretchMono.result
                removeObject: .c[.ch]
            endfor

            selectObject: .s[1]
            for .ch from 2 to .nch
                plusObject: .s[.ch]
            endfor
            microscope.result = Combine to stereo
            for .ch from 1 to .nch
                removeObject: .s[.ch]
            endfor
        else
            .use = .seg
            .made = 0
            if .nch > 1
                selectObject: .seg
                .use = Convert to mono
                .made = 1
            endif
            @stretchMono: .use, .factor
            microscope.result = stretchMono.result
            if .made = 1
                removeObject: .use
            endif
        endif
        microscope.usedPsola = 1
    else
        # Varispeed: pitch and speed move together, all channels preserved.
        selectObject: .seg
        .sr = Get sampling frequency
        .tmp = Copy: "ms_vari"
        selectObject: .tmp
        Override sampling frequency: .sr / .factor
        microscope.result = Resample: .sr, 50
        removeObject: .tmp
        microscope.usedPsola = 0
    endif
endproc

# v0.2: percentile-based, so it does not depend on the recording gain,
# and undefined means are handled rather than propagated.
procedure analyzeContext: .snd, .time, .basePre
    selectObject: .snd
    .wStart = max(xmin, .time - .basePre)
    .wEnd = min(xmax, .time + .basePre)
    analyzeContext.intensity = 0.5
    analyzeContext.pause_before = 0
    if .wEnd - .wStart > 0.01
        selectObject: .snd
        .w = Extract part: .wStart, .wEnd, "rectangular", 1, "no"
        .it = To Intensity: 100, 0, "yes"
        .mn = Get mean: 0, 0, "dB"
        removeObject: .w, .it
        if .mn <> undefined and intensHi > intensLo
            analyzeContext.intensity = (.mn - intensLo) / (intensHi - intensLo)
            if analyzeContext.intensity < 0
                analyzeContext.intensity = 0
            endif
            if analyzeContext.intensity > 1
                analyzeContext.intensity = 1
            endif
            .meanHere = .mn
        else
            .meanHere = undefined
        endif

        # v0.2: the pause window ends where the peephole BEGINS. v0.1
        # ran it to t - window/4 while the peephole started at
        # t - window, so 0.375 s of the 0.5 s default measurement sat
        # inside the very gesture it was meant to precede.
        .pStart = max(xmin, .time - .basePre * 3)
        .pEnd = .wStart
        if .pEnd - .pStart > 0.01 and .meanHere <> undefined
            selectObject: .snd
            .pw = Extract part: .pStart, .pEnd, "rectangular", 1, "no"
            .pi = To Intensity: 100, 0, "yes"
            .pm = Get mean: 0, 0, "dB"
            removeObject: .pw, .pi
            if .pm <> undefined and .pm < .meanHere - 10
                analyzeContext.pause_before = 1
            endif
        endif
    endif
endproc


###############################################################################
# WINDOWS (v0.3 logic, per mark; recomputed only when marks/settings change)
###############################################################################
procedure computeWindows
    if windowsDirty
        for .i to nMk
            .t = mkT[.i]
            if montage_style = 2
                if asymmetric_windows
                    .basePre = pre_length
                    .basePost = post_length
                else
                    .basePre = window_length / 2
                    .basePost = window_length / 2
                endif
                @analyzeContext: sound, .t, .basePre
                .usePre = .basePre * (1 + analyzeContext.pause_before * 0.5)
                .usePost = .basePost * (1.2 - analyzeContext.intensity * 0.4)
            else
                if asymmetric_windows
                    .usePre = pre_length
                    .usePost = post_length
                else
                    .usePre = window_length / 2
                    .usePost = window_length / 2
                endif
            endif
            .s = .t - .usePre
            .e = .t + .usePost
            winClip[.i] = 0
            if .s < xmin
                .s = xmin
                winClip[.i] = 1
            endif
            if .e > xmax
                .e = xmax
                winClip[.i] = 1
            endif
            winS[.i] = .s
            winE[.i] = .e
            winOK[.i] = .e - .s > 0.002
        endfor
        windowsDirty = 0
    endif
endproc

###############################################################################
# BUILD + ASSEMBLE (v0.3 code, verbatim inside; marks come from the arrays)
###############################################################################
procedure buildMontage: .name$
    @computeWindows
    random_initializeWithSeedUnsafelyButPredictably (seedUsed)
    n_points = nMk
    nSeg = 0
    skipped = 0
    stopwatch
    for i to nMk
        t = mkT[i]
        if winOK[i] = 0
            skipped = skipped + 1
        else
            tStart = winS[i]
            tEnd = winE[i]
            clippedHere = winClip[i]
            nSeg = nSeg + 1
            segPoint[nSeg] = t
            segStart[nSeg] = tStart
            segEnd[nSeg] = tEnd
            segClipped[nSeg] = clippedHere
            segFlip[nSeg] = 0
            segSemis[nSeg] = 0

            selectObject: sound
            seg = Extract part: tStart, tEnd, "rectangular", 1, "no"
            selectObject: seg
            srcDur = Get total duration
            segSrcDur[nSeg] = srcDur

            # --- style processing, BEFORE the fades ---
            if montage_style = 3
                selectObject: seg
                segCh = Get number of channels
                if segCh = 2 and uN_random_stereo_flip
                    if randomInteger(1, 2) = 1
                        selectObject: seg
                        c1 = Extract one channel: 1
                        selectObject: seg
                        c2 = Extract one channel: 2
                        selectObject: c2
                        plusObject: c1
                        sw = Combine to stereo
                        removeObject: c1, c2, seg
                        seg = sw
                        segFlip[nSeg] = 1
                    endif
                endif
                if uN_pitch_bias_range > 0
                    biasRange = (i / n_points) * uN_pitch_bias_range
                    semis = randomUniform(-biasRange, biasRange)
                    if abs(semis) > 0.01
                        @pitchShift: seg, semis
                        removeObject: seg
                        seg = pitchShift.result
                        segSemis[nSeg] = semis
                    endif
                endif
            elsif montage_style = 4
                @microscope: seg, microscope_time_factor
                removeObject: seg
                seg = microscope.result
            endif

            # --- fades LAST, on the measured final duration ---
            @applyEdges: seg
            segFade[nSeg] = applyEdges.used

            selectObject: seg
            segOutDur[nSeg] = Get total duration
            if segSrcDur[nSeg] > 0
                segRatio[nSeg] = segOutDur[nSeg] / segSrcDur[nSeg]
            else
                segRatio[nSeg] = 1
            endif
            selectObject: seg
            Rename: "peep_seg" + string$(nSeg)
            segID[nSeg] = seg
        endif
    endfor
    random_initializeSafelyAndUnpredictably ()
    buildElapsed = stopwatch

    if nSeg > 0
stopwatch
ovlUsed = 0

if transition_mode = 3 and nSeg > 1
    # Gap mode. Build NEW assembly objects in the exact desired object-list
    # order: segment1, gap, segment2, gap, ... . Selection order alone does
    # not determine Concatenate order in Praat.
    selectObject: segID[1]
    gapSr = Get sampling frequency
    gapNch = Get number of channels

    nAsm = 0
    for k from 1 to nSeg
        selectObject: segID[k]
        nAsm = nAsm + 1
        asmID[nAsm] = Copy: "asm_seg" + string$(k)

        if k < nSeg
            Create Sound from formula: "peep_gap" + string$(k), gapNch, 0,
                ... transition_amount, gapSr, "0"
            nAsm = nAsm + 1
            asmID[nAsm] = selected("Sound")
        endif
    endfor

    selectObject: asmID[1]
    for k from 2 to nAsm
        plusObject: asmID[k]
    endfor
    result = Concatenate

    for k from 1 to nAsm
        removeObject: asmID[k]
    endfor

elsif transition_mode = 2 and nSeg > 1
    # Raised-cosine overlap. Clamp so no short segment is swallowed.
    ovl = transition_amount
    minSeg = segOutDur[1]
    for k from 2 to nSeg
        if segOutDur[k] < minSeg
            minSeg = segOutDur[k]
        endif
    endfor
    if ovl > minSeg * 0.4
        ovl = minSeg * 0.4
    endif

    selectObject: segID[1]
    for k from 2 to nSeg
        plusObject: segID[k]
    endfor
    Concatenate with overlap: ovl
    result = selected("Sound")
    ovlUsed = ovl

    # Internal joins are already raised-cosine crossfades. Apply the user's
    # selected edge fade only to the OUTSIDE edges of the finished montage.
    if fade_type > 1 and fade_duration > 0
        selectObject: result
        .fd = Get total duration
        .ft0 = Get start time
        .ft1 = Get end time
        .ff = min(fade_duration, .fd * 0.45)
        if .ff > 0
            if fade_type = 2
                .finEnd = .ft0 + .ff
                .foutStart = .ft1 - .ff
                Formula: "if x < " + fixed$(.finEnd, 12) + " then self * (x - " + fixed$(.ft0, 12) + ") / " + fixed$(.ff, 12) + " else if x > " + fixed$(.foutStart, 12) + " then self * (" + fixed$(.ft1, 12) + " - x) / " + fixed$(.ff, 12) + " else self fi fi"
            else
                Fade in: 0, .ft0, .ff, "yes"
                Fade out: 0, .ft1, -.ff, "yes"
            endif
        endif
    endif

else
    # Butt joint (or a single segment): segment objects were created in
    # chronological order already.
    selectObject: segID[1]
    for k from 2 to nSeg
        plusObject: segID[k]
    endfor
    result = Concatenate
endif

selectObject: result
Rename: output_name$
prePeak = Get absolute extremum: 0, 0, "None"
normGain = 1
if output_gain_handling = 1
    if prePeak > peak_target and prePeak > 0
        normGain = peak_target / prePeak
    endif
    normMode$ = "attenuate only"
elsif output_gain_handling = 2
    if prePeak > 0
        normGain = peak_target / prePeak
    endif
    normMode$ = "peak (scaled to target)"
else
    normMode$ = "none"
endif
if normGain <> 1
    selectObject: result
    Formula: "self * " + fixed$(normGain, 10)
endif
selectObject: result
finalPeak = Get absolute extremum: 0, 0, "None"
finalDur = Get total duration
resultName$ = selected$("Sound")
asmElapsed = stopwatch

        selectObject: result
        Rename: .name$
        for k from 1 to nSeg
            removeObject: segID[k]
        endfor
    else
        result = 0
    endif
    buildMontage.result = result
endproc

###############################################################################
# MARK EDITING (sorted array, snapshot undo)
###############################################################################
procedure pushHistory
    nHist += 1
    hN[nHist] = nMk
    for .j to nMk
        hT[nHist, .j] = mkT[.j]
    endfor
endproc

procedure undoMarks
    if nHist = 0
        status$ = "Nothing to undo."
    else
        nMk = hN[nHist]
        for .j to nMk
            mkT[.j] = hT[nHist, .j]
        endfor
        nHist -= 1
        windowsDirty = 1
        previewValid = 0
        status$ = "Undone: " + string$ (nMk) + " marks."
    endif
endproc

procedure toggleMark: .t
    .tol = (viewT1 - viewT0) * 0.008
    .hit = 0
    for .i to nMk
        if .hit = 0 and abs (mkT[.i] - .t) <= .tol
            .hit = .i
        endif
    endfor
    @pushHistory
    if .hit > 0
        for .i from .hit to nMk - 1
            .j = .i + 1
            mkT[.i] = mkT[.j]
        endfor
        nMk -= 1
        status$ = "Removed the peephole at " + fixed$ (.t, 3) + " s."
    else
        .pos = nMk + 1
        for .i to nMk
            if .pos = nMk + 1 and mkT[.i] > .t
                .pos = .i
            endif
        endfor
        for .m to nMk - .pos + 1
            .j = nMk - .m + 1
            .jn = .j + 1
            mkT[.jn] = mkT[.j]
        endfor
        mkT[.pos] = .t
        nMk += 1
        status$ = "Peephole " + string$ (.pos) + " at " + fixed$ (.t, 3) + " s."
    endif
    windowsDirty = 1
    previewValid = 0
endproc

procedure listenMark: .t
    .tol = (viewT1 - viewT0) * 0.008
    .hit = 0
    for .i to nMk
        if .hit = 0 and abs (mkT[.i] - .t) <= .tol
            .hit = .i
        endif
    endfor
    if .hit = 0
        status$ = "Shift-click ON a peephole to listen to it."
    else
        @computeWindows
        selectObject: sound
        .w = Extract part: winS[.hit], winE[.hit], "rectangular", 1, "no"
        Play
        removeObject: .w
        status$ = "Played peephole " + string$ (.hit) + " (source window, " + fixed$ (winE[.hit] - winS[.hit], 3) + " s)."
    endif
endproc

###############################################################################
# VIEW (zoom / scroll)
###############################################################################
procedure setView: .t0, .t1
    .span = max (minSpan, min (xmax - xmin, .t1 - .t0))
    .t0 = max (xmin, .t0)
    .t1 = .t0 + .span
    if .t1 > xmax
        .t1 = xmax
        .t0 = max (xmin, .t1 - .span)
    endif
    viewT0 = .t0
    viewT1 = .t1
endproc

procedure zoomView: .factor
    .c = (viewT0 + viewT1) / 2
    .half = (viewT1 - viewT0) / (2 * .factor)
    @setView: .c - .half, .c + .half
endproc

###############################################################################
# CONTROLS - clickable widgets registered while drawing
###############################################################################
procedure addBtn: .x1, .x2, .y1, .y2, .act$
    nBtn += 1
    bX1[nBtn] = .x1
    bX2[nBtn] = .x2
    bY1[nBtn] = .y1
    bY2[nBtn] = .y2
    bAct$[nBtn] = .act$
endproc

# kind 1 = cycle / toggle (whole cell), 2 = stepper (- / + boxes), 3 = action
procedure widget: .col, .row, .ncol, .kind, .label$, .value$, .act$, .enabled
    .gapX = 1.2
    .w = (vpR - vpL - (.ncol - 1) * .gapX) / .ncol
    .x1 = vpL + (.col - 1) * (.w + .gapX)
    .x2 = .x1 + .w
    .rowH = (ctlT - ctlB) / 5
    .y2 = ctlT - (.row - 1) * .rowH - 0.4
    .y1 = .y2 - .rowH + 0.8
    if .kind = 3
        demo Paint rectangle: cAct$, .x1, .x2, .y1, .y2
    else
        demo Paint rectangle: cBtn$, .x1, .x2, .y1, .y2
    endif
    if .enabled
        demo Colour: cSumTx$
    else
        demo Colour: cOff$
    endif
    .ym = (.y1 + .y2) / 2
    if .kind = 3
        demo Text: (.x1 + .x2) / 2, "centre", .ym, "half", "##" + .label$ + "##"
    else
        demo Text: .x1 + 0.8, "left", .ym, "half", .label$ + ":  ##" + .value$ + "##"
    endif
    if .kind = 2 and .enabled
        .bw = 3.2
        demo Paint rectangle: "{0.82, 0.82, 0.86}", .x2 - 2 * .bw - 0.6, .x2 - .bw - 0.6, .y1 + 0.4, .y2 - 0.4
        demo Paint rectangle: "{0.82, 0.82, 0.86}", .x2 - .bw - 0.3, .x2 - 0.3, .y1 + 0.4, .y2 - 0.4
        demo Colour: "Black"
        demo Text: .x2 - 1.5 * .bw - 0.6, "centre", .ym, "half", "##-##"
        demo Text: .x2 - 0.5 * .bw - 0.3, "centre", .ym, "half", "##+##"
        @addBtn: .x2 - 2 * .bw - 0.6, .x2 - .bw - 0.6, .y1, .y2, .act$ + "-"
        @addBtn: .x2 - .bw - 0.3, .x2 - 0.3, .y1, .y2, .act$ + "+"
    elsif .enabled
        @addBtn: .x1, .x2, .y1, .y2, .act$
    endif
    demo Colour: "{0.70, 0.70, 0.75}"
    demo Draw rectangle: .x1, .x2, .y1, .y2
endproc

procedure doAction: .a$
    .changed = 1
    if .a$ = "style"
        montage_style = (montage_style mod 4) + 1
        .msg$ = "Style: " + styleOpt$[montage_style]
    elsif .a$ = "win-" or .a$ = "win+"
        window_length = max (0.02, min (10, window_length + if .a$ = "win+" then 0.05 else -0.05 fi))
        .msg$ = "Window " + fixed$ (window_length, 2) + " s"
    elsif .a$ = "asym"
        asymmetric_windows = 1 - asymmetric_windows
        .msg$ = if asymmetric_windows then "Asymmetric windows" else "Symmetric windows" fi
    elsif .a$ = "pre-" or .a$ = "pre+"
        pre_length = max (0.01, min (5, pre_length + if .a$ = "pre+" then 0.05 else -0.05 fi))
        .msg$ = "Pre " + fixed$ (pre_length, 2) + " s"
    elsif .a$ = "post-" or .a$ = "post+"
        post_length = max (0.01, min (5, post_length + if .a$ = "post+" then 0.05 else -0.05 fi))
        .msg$ = "Post " + fixed$ (post_length, 2) + " s"
    elsif .a$ = "fade"
        fade_type = (fade_type mod 3) + 1
        .msg$ = "Fade: " + fadeOpt$[fade_type]
    elsif .a$ = "fms-" or .a$ = "fms+"
        fade_duration = max (0.001, min (0.2, fade_duration + if .a$ = "fms+" then 0.002 else -0.002 fi))
        .msg$ = "Fade " + fixed$ (fade_duration * 1000, 0) + " ms"
    elsif .a$ = "join"
        transition_mode = (transition_mode mod 3) + 1
        .msg$ = "Joins: " + joinOpt$[transition_mode]
    elsif .a$ = "amt-" or .a$ = "amt+"
        transition_amount = max (0.001, min (1, transition_amount + if .a$ = "amt+" then 0.005 else -0.005 fi))
        .msg$ = "Transition " + fixed$ (transition_amount * 1000, 0) + " ms"
    elsif .a$ = "msf-" or .a$ = "msf+"
        microscope_time_factor = max (0.1, min (10, microscope_time_factor * if .a$ = "msf+" then 1.25 else 0.8 fi))
        .msg$ = "Microscope x" + fixed$ (microscope_time_factor, 2)
    elsif .a$ = "mspp"
        microscope_preserve_pitch = 1 - microscope_preserve_pitch
        .msg$ = if microscope_preserve_pitch then "Microscope: pitch preserved (PSOLA)" else "Microscope: varispeed" fi
    elsif .a$ = "msdm"
        microscope_downmix_stereo = 1 - microscope_downmix_stereo
        .msg$ = if microscope_downmix_stereo then "Microscope: downmix" else "Microscope: per channel" fi
    elsif .a$ = "unr-" or .a$ = "unr+"
        uN_pitch_bias_range = max (0, min (12, uN_pitch_bias_range + if .a$ = "unr+" then 0.25 else -0.25 fi))
        .msg$ = "Pitch bias range " + fixed$ (uN_pitch_bias_range, 2) + " st"
    elsif .a$ = "unflip"
        uN_random_stereo_flip = 1 - uN_random_stereo_flip
        .msg$ = if uN_random_stereo_flip then "Random stereo flip on" else "Random stereo flip off" fi
    elsif .a$ = "gain"
        output_gain_handling = (output_gain_handling mod 3) + 1
        .msg$ = "Gain: " + gainOpt$[output_gain_handling]
    elsif .a$ = "pk-" or .a$ = "pk+"
        peak_target = max (0.1, min (1, peak_target + if .a$ = "pk+" then 0.01 else -0.01 fi))
        .msg$ = "Peak target " + fixed$ (peak_target, 2)
    elsif .a$ = "seed"
        seedUsed = randomInteger (1, 2147483646)
        random_seed = seedUsed
        .msg$ = "New seed " + string$ (seedUsed)
    else
        .changed = 0
        if .a$ = "preview"
            @preview
        elsif .a$ = "commit"
            action$ = "commit"
        elsif .a$ = "playview"
            @playView
        endif
    endif
    if .changed
        windowsDirty = 1
        previewValid = 0
        status$ = .msg$ + "."
    endif
endproc

procedure preview
    if nMk = 0
        status$ = "Place at least one peephole first."
    else
        status$ = "Building the preview..."
        @drawAll
        if previewSnd > 0
            removeObject: previewSnd
            previewSnd = 0
        endif
        @buildMontage: "peephole_preview"
        previewSnd = buildMontage.result
        if previewSnd > 0
            previewValid = 1
            selectObject: previewSnd
            .d = Get total duration
            Play
            status$ = "Preview: " + string$ (nSeg) + " peepholes, " + fixed$ (.d, 2) + " s (seed " + string$ (seedUsed) + "). Enter commits exactly this."
        else
            status$ = "No usable peephole (every window shorter than 2 ms)."
        endif
    endif
endproc

procedure playView
    selectObject: sound
    .w = Extract part: viewT0, viewT1, "rectangular", 1, "no"
    Play
    removeObject: .w
    status$ = "Played " + fixed$ (viewT0, 2) + "-" + fixed$ (viewT1, 2) + " s."
endproc

procedure routeClick: .x, .y
    .done = 0
    for .b to nBtn
        if .done = 0 and .x >= bX1[.b] and .x <= bX2[.b] and .y >= bY1[.b] and .y <= bY2[.b]
            @doAction: bAct$[.b]
            .done = 1
        endif
    endfor
    if .done = 0
        .u = (.x - vpL) / (vpR - vpL)
        if .u >= 0 and .u <= 1 and .y >= srcB and .y <= srcT
            .t = viewT0 + .u * (viewT1 - viewT0)
            if demoShiftKeyPressed ()
                @listenMark: .t
            else
                @toggleMark: .t
            endif
        elsif .u >= 0 and .u <= 1 and .y >= ovB - 0.5 and .y <= ovT + 0.5
            .c = xmin + .u * (xmax - xmin)
            .half = (viewT1 - viewT0) / 2
            @setView: .c - .half, .c + .half
            status$ = "View " + fixed$ (viewT0, 2) + "-" + fixed$ (viewT1, 2) + " s."
        elsif .done = 0
            status$ = "Click the waveform, the overview strip or a control."
        endif
    endif
endproc

###############################################################################
# DRAWING
###############################################################################
procedure vp: .x1, .x2, .y1, .y2
    if flipH > 0
        demo Select inner viewport: .x1 * sx, .x2 * sx, flipH - .y2 * sy, flipH - .y1 * sy
    else
        demo Select inner viewport: .x1 * sx, .x2 * sx, .y1 * sy, .y2 * sy
    endif
endproc

procedure full
    @vp: 0, 100, 0, 100
    demo Axes: 0, 100, 0, 100
endproc

procedure caption: .yT, .text$
    demo Font size: 8
    @vp: vpL, vpR, .yT, .yT + 3
    demo Axes: 0, 1, 0, 1
    demo Colour: "Black"
    demo Text: 0, "left", 0.2, "half", .text$
endproc

procedure niceStep: .span, .target
    .raw = .span / .target
    .mag = 10 ^ floor (log10 (.raw))
    .result = 10 * .mag
    if 5 * .mag >= .raw
        .result = 5 * .mag
    endif
    if 2 * .mag >= .raw
        .result = 2 * .mag
    endif
    if .mag >= .raw
        .result = .mag
    endif
endproc

procedure safe: .s$
    .s$ = replace$ (.s$, "\", "\bs", 0)
    .s$ = replace$ (.s$, "_", "\_ ", 0)
    .s$ = replace$ (.s$, "%", "\% ", 0)
    .s$ = replace$ (.s$, "#", "\# ", 0)
    .s$ = replace$ (.s$, "^", "\^ ", 0)
    .result$ = .s$
endproc

procedure drawTitle: .title$
    demo Font size: 12
    @vp: vpL, vpR, ttlB, ttlT
    demo Axes: 0, 1, 0, 1
    demo Colour: "Black"
    demo Text: 0.5, "centre", 0.72, "half", "##" + .title$ + "##"
    @safe: sound_name$
    demo Font size: 7
    @vp: vpL, vpR, ttlB, ttlT
    demo Axes: 0, 1, 0, 1
    demo Colour: cSubTx$
    demo Text: 0.5, "centre", 0.12, "half", safe.result$ + "   |   " + fixed$ (xmax - xmin, 2) + " s, " + string$ (srcChannels)
        ... + " ch   |   " + styleOpt$[montage_style] + "   |   " + string$ (nMk) + " peepholes   |   seed " + string$ (seedUsed)
endproc

# ---- overview strip: the whole file, windows, and the view box --------------
procedure drawOverview
    @vp: vpL, vpR, ovB, ovT
    demo Axes: xmin, xmax, -srcPeak, srcPeak
    demo Paint rectangle: cPanel$, xmin, xmax, -srcPeak, srcPeak
    for .i to nMk
        demo Paint rectangle: if winClip[.i] then cClip$ else cWin$ fi, winS[.i], winE[.i], -srcPeak, srcPeak
    endfor
    selectObject: sound
    demo Colour: cInput$
    demo Draw: 0, 0, -srcPeak, srcPeak, "no", "Curve"
    @vp: vpL, vpR, ovB, ovT
    demo Axes: xmin, xmax, -srcPeak, srcPeak
    demo Colour: cSec$
    demo Line width: 1.5
    demo Draw rectangle: viewT0, viewT1, -srcPeak, srcPeak
    demo Line width: 1
endproc

# ---- A: the source view with peepholes -------------------------------------
procedure drawSource
    .aMax = srcPeak * 1.18
    demo Font size: 7
    @vp: vpL, vpR, srcB, srcT
    demo Axes: viewT0, viewT1, -.aMax, .aMax
    demo Paint rectangle: cPanel$, viewT0, viewT1, -.aMax, .aMax
    for .i to nMk
        .a = max (viewT0, winS[.i])
        .b = min (viewT1, winE[.i])
        if .b > .a
            demo Paint rectangle: if winClip[.i] then cClip$ else cWin$ fi, .a, .b, -.aMax, .aMax
        endif
    endfor
    demo Colour: cGrid$
    demo Draw line: viewT0, 0, viewT1, 0
    selectObject: sound
    demo Colour: "{0.22, 0.22, 0.26}"
    demo Draw: viewT0, viewT1, -.aMax, .aMax, "no", "Curve"
    @vp: vpL, vpR, srcB, srcT
    demo Axes: viewT0, viewT1, -.aMax, .aMax
    for .i to nMk
        if mkT[.i] >= viewT0 and mkT[.i] <= viewT1
            demo Colour: cPrim$
            demo Line width: 2
            demo Draw line: mkT[.i], -.aMax * 0.92, mkT[.i], .aMax * 0.86
            demo Line width: 1
        endif
    endfor
    demo Font size: 6
    @vp: vpL, vpR, srcB, srcT
    demo Axes: viewT0, viewT1, -.aMax, .aMax
    for .i to nMk
        if mkT[.i] >= viewT0 and mkT[.i] <= viewT1
            demo Colour: cPrim$
            demo Text: mkT[.i], "centre", .aMax * 0.88, "bottom", "##" + string$ (.i) + "##"
        endif
    endfor
    demo Font size: 7
    @vp: vpL, vpR, srcB, srcT
    demo Axes: viewT0, viewT1, -.aMax, .aMax
    demo Colour: "Black"
    demo Draw inner box
    @niceStep: viewT1 - viewT0, 8
    demo Marks bottom every: 1, niceStep.result, "yes", "yes", "no"
    demo Text left: "yes", "Source"
    if viewT0 > xmin or viewT1 < xmax
        .zoom$ = "   view " + fixed$ (viewT0, 2) + "\--" + fixed$ (viewT1, 2) + " s (strip above = whole file)"
    else
        .zoom$ = ""
    endif
    @caption: ovT + 0.6, "##A   Source and peepholes##   blue = window, red = clipped at a file edge" + .zoom$
endproc

# ---- B: montage timeline (predicted, or measured after a preview) ----------
procedure drawTimeline
    @computeWindows
    # durations
    .n = 0
    for .i to nMk
        if winOK[.i]
            .n += 1
            tlSrc[.n] = winE[.i] - winS[.i]
            tlClip[.n] = winClip[.i]
            if previewValid and .n <= nSeg
                tlOut[.n] = segOutDur[.n]
            elsif montage_style = 4
                tlOut[.n] = tlSrc[.n] * microscope_time_factor
            else
                tlOut[.n] = tlSrc[.n]
            endif
        endif
    endfor
    .total = 0
    if .n > 0
        .ovl = 0
        if transition_mode = 2 and .n > 1
            .minSeg = tlOut[1]
            for .k from 2 to .n
                .minSeg = min (.minSeg, tlOut[.k])
            endfor
            .ovl = min (transition_amount, .minSeg * 0.4)
        endif
        for .k to .n
            tlStart[.k] = .total
            .total += tlOut[.k]
            if .k < .n
                if transition_mode = 2
                    .total -= .ovl
                elsif transition_mode = 3
                    .total += transition_amount
                endif
            endif
        endfor
    endif
    tlTotal = .total
    .tMax = max (.total, 0.1)
    .rows = max (.n, 1)
    demo Font size: 7
    @vp: vpL, vpR, tlB, tlT
    demo Axes: 0, .tMax, 0.3, .rows + 0.7
    demo Paint rectangle: cPanel$, 0, .tMax, 0.3, .rows + 0.7
    for .k to .n
        .yy = .rows + 1 - .k
        .h = min (0.34, 0.34 * 12 / .rows)
        demo Paint rectangle: if tlClip[.k] then cSec$ else cPrim$ fi, tlStart[.k], tlStart[.k] + tlOut[.k], .yy - .h, .yy + .h
        demo Colour: cInput$
        demo Draw rectangle: tlStart[.k], tlStart[.k] + tlSrc[.k], .yy - .h * 0.5, .yy + .h * 0.5
    endfor
    demo Colour: "Black"
    demo Draw inner box
    @niceStep: .tMax, 8
    demo Marks bottom every: 1, niceStep.result, "yes", "yes", "no"
    demo Text left: "yes", "Order"
    if previewValid
        .kind$ = "measured (preview)"
    elsif montage_style = 4
        .kind$ = "predicted: window x factor"
    else
        .kind$ = "predicted"
    endif
    .pct = 0
    if xmax > xmin
        .sum = 0
        for .k to .n
            .sum += tlSrc[.k]
        endfor
        .pct = 100 * .sum / (xmax - xmin)
    endif
    @caption: tlT + 1, "##B   Montage timeline##   " + .kind$ + ": " + fixed$ (tlTotal, 2) + " s from " + fixed$ (.pct, 1) + " \%  of the source; red = clipped window, outline = source length"
endproc

# ---- C: controls -----------------------------------------------------------
procedure drawControls
    demo Font size: 7
    @full
    demo Paint rectangle: cPanel$, vpL, vpR, ctlB, ctlT
    @widget: 1, 1, 3, 1, "Style", styleOpt$[montage_style], "style", 1
    @widget: 2, 1, 3, 2, "Window", fixed$ (window_length, 2) + " s", "win", asymmetric_windows = 0
    @widget: 3, 1, 3, 1, "Windows", if asymmetric_windows then "asymmetric" else "symmetric" fi, "asym", 1
    @widget: 1, 2, 3, 2, "Pre", fixed$ (pre_length, 2) + " s", "pre", asymmetric_windows
    @widget: 2, 2, 3, 2, "Post", fixed$ (post_length, 2) + " s", "post", asymmetric_windows
    @widget: 3, 2, 3, 1, "Fade", fadeOpt$[fade_type], "fade", 1
    @widget: 1, 3, 3, 2, "Fade", fixed$ (fade_duration * 1000, 0) + " ms", "fms", fade_type > 1
    @widget: 2, 3, 3, 1, "Joins", joinOpt$[transition_mode], "join", 1
    @widget: 3, 3, 3, 2, if transition_mode = 3 then "Gap" else "Overlap" fi, fixed$ (transition_amount * 1000, 0) + " ms", "amt", transition_mode > 1
    if montage_style = 4
        @widget: 1, 4, 3, 2, "Microscope", "x" + fixed$ (microscope_time_factor, 2), "msf", 1
        @widget: 2, 4, 3, 1, "Pitch", if microscope_preserve_pitch then "preserved (PSOLA)" else "varispeed" fi, "mspp", 1
        @widget: 3, 4, 3, 1, "Channels", if microscope_downmix_stereo then "downmix" else "each" fi, "msdm", microscope_preserve_pitch and srcChannels > 1
    elsif montage_style = 3
        @widget: 1, 4, 3, 2, "Pitch bias", fixed$ (uN_pitch_bias_range, 2) + " st", "unr", 1
        @widget: 2, 4, 3, 1, "Stereo flip", if uN_random_stereo_flip then "on" else "off" fi, "unflip", srcChannels = 2
        @widget: 3, 4, 3, 3, "New seed (N)", "", "seed", 1
    else
        @widget: 1, 4, 3, 1, "Gain", gainOpt$[output_gain_handling], "gain", 1
        @widget: 2, 4, 3, 2, "Peak target", fixed$ (peak_target, 2), "pk", output_gain_handling < 3
        @widget: 3, 4, 3, 3, "New seed (N)", "", "seed", 1
    endif
    @widget: 1, 5, 4, 3, "Preview + play (P)", "", "preview", 1
    @widget: 2, 5, 4, 3, "Play view (S)", "", "playview", 1
    if montage_style = 3 or montage_style = 4
        @widget: 3, 5, 4, 1, "Gain", gainOpt$[output_gain_handling], "gain", 1
    else
        @widget: 3, 5, 4, 1, "Style note", if montage_style = 2 then "lengths follow context" else "fixed windows" fi, "none", 0
    endif
    @widget: 4, 5, 4, 3, "Commit (Enter)", "", "commit", 1
    @caption: ctlT + 1, "##C   Settings##   click a value to cycle it, - / + to step it (v0.3 parameters)"
endproc

# ---- result view: output waveform replaces the controls -------------------
procedure drawOutput
    selectObject: result
    .d = Get total duration
    .pk = Get absolute extremum: 0, 0, "None"
    .pk = max (.pk, 0.001) * 1.15
    demo Font size: 7
    @vp: vpL, vpR, ctlB, ctlT
    demo Axes: 0, .d, -.pk, .pk
    demo Paint rectangle: cPanel$, 0, .d, -.pk, .pk
    demo Colour: cGrid$
    demo Draw line: 0, 0, .d, 0
    selectObject: result
    demo Colour: cPrim$
    demo Draw: 0, 0, -.pk, .pk, "no", "Curve"
    @vp: vpL, vpR, ctlB, ctlT
    demo Axes: 0, .d, -.pk, .pk
    demo Colour: "Black"
    demo Draw inner box
    @niceStep: .d, 8
    demo Marks bottom every: 1, niceStep.result, "yes", "yes", "no"
    demo Text left: "yes", "Output"
    @caption: ctlT + 1, "##C   Montage##   montage time (s), " + fixed$ (.d, 2) + " s, " + normMode$ + ", peak " + fixed$ (finalPeak, 3)
endproc

procedure drawSummary
    demo Font size: 7
    @vp: vpL, vpR, sumB, sumT
    demo Axes: 0, 1, 0, 1
    demo Paint rectangle: cSum$, 0, 1, 0, 1
    demo Colour: cSumTx$
    if finalView
        demo Text: 0.01, "left", 0.78, "half", "##Done.## The montage and a peephole\_ marks PointProcess are in the Objects window; the report is in the Info window."
    else
        demo Text: 0.01, "left", 0.78, "half", "##Click## add / remove   ##Shift-click## listen   ##U## undo   ##C## clear   ##+ - 0## zoom   ##, .## scroll   ##S## play view   ##P## preview   ##Enter## commit   ##Esc## cancel"
    endif
    demo Text: 0.01, "left", 0.46, "half", "##" + string$ (nMk) + " peepholes##   " + styleOpt$[montage_style] + ",  " + fadeOpt$[fade_type] + " edges,  " + joinOpt$[transition_mode] + ",  seed " + string$ (seedUsed)
    demo Text: 0.01, "left", 0.16, "half", "##Status:## " + status$
    @vp: vpL, vpR, sumB, sumT
    demo Axes: 0, 1, 0, 1
    demo Colour: "Black"
    demo Draw inner box
endproc

procedure drawAll
    nBtn = 0
    @computeWindows
    demo Erase all
    if finalView
        @drawTitle: "PEEPHOLE MONTAGE \--  RESULT"
    else
        @drawTitle: "PEEPHOLE MONTAGE"
    endif
    @drawOverview
    @drawSource
    @drawTimeline
    if finalView
        @drawOutput
    else
        @drawControls
    endif
    @drawSummary
    # leave the frame on window coordinates for demoX / demoY
    demo Font size: 7
    @full
endproc

###############################################################################
# INTERACTIVE SESSION
###############################################################################
@drawAll

# >>> INPUT LOOP
action$ = ""
while action$ = ""
    demoWaitForInput ()
    if demoClicked ()
        @routeClick: demoX (), demoY ()
        @drawAll
    elsif demoKeyPressed ()
        key$ = demoKey$ ()
        if key$ = newline$ or key$ = unicode$ (13) or key$ = unicode$ (65293)
            action$ = "commit"
        elsif key$ = unicode$ (27) or key$ = unicode$ (65307)
            action$ = "cancel"
        elsif key$ = "u" or key$ = "U"
            @undoMarks
            @drawAll
        elsif key$ = "c" or key$ = "C"
            @pushHistory
            nMk = 0
            windowsDirty = 1
            previewValid = 0
            status$ = "All peepholes cleared (U restores them)."
            @drawAll
        elsif key$ = "+" or key$ = "="
            @zoomView: 2
            @drawAll
        elsif key$ = "-"
            @zoomView: 0.5
            @drawAll
        elsif key$ = "0"
            @setView: xmin, xmax
            @drawAll
        elsif key$ = ","
            @setView: viewT0 - (viewT1 - viewT0) / 2, viewT1 - (viewT1 - viewT0) / 2
            @drawAll
        elsif key$ = "."
            @setView: viewT0 + (viewT1 - viewT0) / 2, viewT1 + (viewT1 - viewT0) / 2
            @drawAll
        elsif key$ = "s" or key$ = "S"
            @playView
            @drawAll
        elsif key$ = "n" or key$ = "N"
            @doAction: "seed"
            @drawAll
        elsif key$ = "p" or key$ = "P"
            @preview
            @drawAll
        endif
    endif
    if action$ = "commit" and nMk = 0
        action$ = ""
        status$ = "Place at least one peephole before committing."
        @drawAll
    endif
endwhile
# <<< INPUT LOOP

if previewSnd > 0
    removeObject: previewSnd
    previewSnd = 0
endif
if action$ = "cancel"
    status$ = "Cancelled - nothing was created."
    @drawAll
    exitScript: "Peephole Montage cancelled."
endif

###############################################################################
# COMMIT - build with the session seed, v0.3 report, marks, edit map, play
###############################################################################
status$ = "Building the montage..."
@drawAll
@buildMontage: output_name$
result = buildMontage.result
if result = 0
    exitScript: "No usable segments: every window came out shorter than 2 ms."
endif

marks = Create empty PointProcess: "peephole_marks", xmin, xmax
for i to nMk
    Add point: mkT[i]
endfor

writeInfoLine: "=== PEEPHOLE MONTAGE (Demo) v1.0 ==="
appendInfoLine: "Source: ", sound_name$, "  (", fixed$ (xmax - xmin, 3), " s, ", srcChannels, " ch @ ", sample_rate, " Hz)"
appendInfoLine: "Style: ", styleOpt$[montage_style], "   marks: ", nMk
styleName$ = styleOpt$[montage_style]

###############################################################################
# REPORT
###############################################################################
appendInfoLine: ""
appendInfoLine: "Segments: ", nSeg, " of ", n_points, " marks"
if skipped > 0
    appendInfoLine: "  ", skipped, " mark(s) skipped: outside the Sound's domain, or the"
    appendInfoLine: "  window came out shorter than 2 ms. v0.1 would have attempted the"
    appendInfoLine: "  extraction anyway."
endif
clippedCount = 0
for k from 1 to nSeg
    if segClipped[k] = 1
        clippedCount = clippedCount + 1
    endif
endfor
if clippedCount > 0
    appendInfoLine: "  ", clippedCount, " window(s) clipped at a file edge, so they are"
    appendInfoLine: "  shorter than requested. Their fades were shortened to match."
endif
appendInfoLine: ""

appendInfoLine: "Windows: ", fixed$(window_length, 3), " s"
if asymmetric_windows
    appendInfoLine: "  asymmetric, pre ", fixed$(pre_length, 3), " s, post ",
        ... fixed$(post_length, 3), " s"
else
    appendInfoLine: "  symmetric, ", fixed$(window_length / 2, 3), " s each side"
endif
if montage_style = 2
    appendInfoLine: "  Adaptive: the pre/post LENGTHS vary with context - there is no"
    appendInfoLine: "  amplitude ramp, which is why this is no longer called Context ramp."
    if pctOk = 1
        appendInfoLine: "  Intensity mapped between this file's 10th and 90th percentiles,"
        appendInfoLine: "  ", fixed$(intensLo, 1), " to ", fixed$(intensHi, 1),
            ... " dB, so it does not depend on the recording gain."
        appendInfoLine: "  v0.1 used a fixed 40-80 dB: the same material 12 dB louder"
        appendInfoLine: "  mapped 0.125 to 0.425 and produced different window lengths."
    else
        appendInfoLine: "  Percentiles were undefined; fell back to a fixed 40-80 dB."
    endif
endif
appendInfoLine: ""

if fade_type = 1
    appendInfoLine: "Edges: none"
    minFade = 0
    maxFade = 0
else
    if fade_type = 2
        fadeName$ = "linear"
    else
        fadeName$ = "raised cosine"
    endif

    if transition_mode = 2
        minFade = min(fade_duration, finalDur * 0.45)
        maxFade = minFade
        appendInfoLine: "Edges: ", fadeName$, ", requested ",
            ... fixed$(fade_duration * 1000, 1), " ms"
        appendInfoLine: "  overlap mode: applied only at the OUTSIDE montage edges;"
        appendInfoLine: "  internal joins use Concatenate with overlap's raised-cosine crossfade."
    else
        minFade = segFade[1]
        maxFade = segFade[1]
        for k from 2 to nSeg
            if segFade[k] < minFade
                minFade = segFade[k]
            endif
            if segFade[k] > maxFade
                maxFade = segFade[k]
            endif
        endfor
        appendInfoLine: "Edges: ", fadeName$, ", requested ",
            ... fixed$(fade_duration * 1000, 1), " ms"
        appendInfoLine: "  applied ", fixed$(minFade * 1000, 2), " to ",
            ... fixed$(maxFade * 1000, 2), " ms, clamped to 0.45 of each segment"
    endif
    appendInfoLine: "  Applied AFTER the style processing, so the requested duration is"
    appendInfoLine: "  measured in the output rather than before Microscope stretching."
endif
if transition_mode = 1
    appendInfoLine: "Joins: butt, each peephole fading to silence and the next rising"
    appendInfoLine: "  from it. That dips at every seam, which may be the point."
elsif transition_mode = 2
    appendInfoLine: "Joins: raised-cosine overlap of ", fixed$(ovlUsed * 1000, 1), " ms"
else
    appendInfoLine: "Joins: ", fixed$(transition_amount * 1000, 1), " ms of silence between peepholes"
endif
appendInfoLine: ""

if montage_style = 3
    appendInfoLine: "Unreliable narrator:"
    appendInfoLine: "  Seed ", seedUsed, " - this take is reproducible."
    if random_seed = 0
        appendInfoLine: "  (Random_seed was 0; copy the seed above into the form to reproduce it.)"
    endif
    flips = 0
    for k from 1 to nSeg
        if segFlip[k] = 1
            flips = flips + 1
        endif
    endfor
    appendInfoLine: "  Channels swapped on ", flips, " of ", nSeg, " segments"
    if srcChannels = 1 and uN_random_stereo_flip
        appendInfoLine: "  (the source is mono, so no swap is possible)"
    endif
    appendInfoLine: "  Pitch bias, semitones per segment:"
    for k from 1 to nSeg
        if segFlip[k] = 1
            flipTag$ = "  flipped"
        else
            flipTag$ = ""
        endif
        appendInfoLine: "    ", k, ": ", fixed$(segSemis[k], 3), flipTag$
    endfor
    appendInfoLine: "  Both channels take the SAME ratio, so the stereo image is not"
    appendInfoLine: "  disturbed. v0.1 skipped pitch mutation on stereo entirely."
elsif montage_style = 4
    appendInfoLine: "Microscope: factor ", fixed$(microscope_time_factor, 3)
    if abs(microscope_time_factor - 1) < 1e-9
        appendInfoLine: "  Factor 1.0: PSOLA skipped entirely, so the segments are exact"
        appendInfoLine: "  copies apart from the edge fades."
    elsif microscope_preserve_pitch
        appendInfoLine: "  Pitch-preserving PSOLA, ", fixed$(pitch_floor, 0), "-",
            ... fixed$(pitch_ceiling, 0), " Hz. Suited to periodic or monophonic"
        appendInfoLine: "  material; polyphonic or noisy sources will show artefacts."
        if srcChannels > 1 and microscope_downmix_stereo = 0
            appendInfoLine: "  Multichannel: each channel is analysed separately, which can leave"
            appendInfoLine: "  small timing differences between channels. Downmix first if the"
            appendInfoLine: "  material is strongly correlated."
        endif
    else
        appendInfoLine: "  Varispeed: pitch and speed move together."
        appendInfoLine: "  v0.1 called To Sound (PSOLA) here - a Manipulation command,"
        appendInfoLine: "  with an argument list matching nothing on Sound."
    endif
    if microscope_time_factor < 0.25 or microscope_time_factor > 4
        appendInfoLine: "  WARNING: an extreme factor. It runs, but quality falls off."
    endif
    minR = segRatio[1]
    maxR = segRatio[1]
    for k from 2 to nSeg
        if segRatio[k] < minR
            minR = segRatio[k]
        endif
        if segRatio[k] > maxR
            maxR = segRatio[k]
        endif
    endfor
    appendInfoLine: "  Achieved stretch, measured: ", fixed$(minR, 4), " to ",
        ... fixed$(maxR, 4)
endif
appendInfoLine: ""

appendInfoLine: "Segments (source window -> output):"
totalSrc = 0
for k from 1 to nSeg
    totalSrc = totalSrc + segSrcDur[k]
    if segClipped[k] = 1
        clipTag$ = "  [clipped at file edge]"
    else
        clipTag$ = ""
    endif
    appendInfoLine: "  ", k, ": mark ", fixed$(segPoint[k], 3), " s   window ",
        ... fixed$(segStart[k], 3), "-", fixed$(segEnd[k], 3), " s (",
        ... fixed$(segSrcDur[k], 3), " s)  ->  ", fixed$(segOutDur[k], 3), " s",
        ... clipTag$
endfor
appendInfoLine: "  Total source sampled ", fixed$(totalSrc, 3), " s of ",
    ... fixed$(xmax - xmin, 3), " s = ", fixed$(totalSrc / (xmax - xmin) * 100, 1), "%"
appendInfoLine: ""

appendInfoLine: "Output: ", resultName$, "  (", fixed$(finalDur, 3), " s)"
appendInfoLine: "  Gain: ", normMode$, "   peak ", fixed$(prePeak, 4), " -> ",
    ... fixed$(finalPeak, 4), " (x", fixed$(normGain, 4), ")"
appendInfoLine: "(build ", fixed$(buildElapsed, 2), " s   assemble ",
    ... fixed$(asmElapsed, 2), " s)"


if draw_visualization
    Erase all

    for k from 1 to nSeg
        hue = (k - 1) / max(1, nSeg)
        cR[k] = 0.26 + hue * 0.58
        cG[k] = 0.52 - hue * 0.20
        cB[k] = 0.80 - hue * 0.52
    endfor

    # ----------------------------------------------------------
    # TITLE
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "##PEEPHOLE MONTAGE##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.25, "half",
        ... sound_name$
        ... + "  |  " + styleName$
        ... + "  |  " + string$(nSeg) + " peepholes"
        ... + "  |  source " + fixed$(xmax - xmin, 2) + " s"
        ... + "  ->  montage " + fixed$(finalDur, 2) + " s"

    # ----------------------------------------------------------
    # PANEL A: SOURCE WITH MARKS AND WINDOWS
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.72, 2.70
    Select inner viewport: 0.55, 7.75, 0.80, 2.62

    selectObject: sound
    srcPeak = Get absolute extremum: 0, 0, "None"
    if srcPeak < 0.001
        srcPeak = 0.001
    endif
    aMax = srcPeak * 1.18

    Axes: xmin, xmax, -aMax, aMax
    Paint rectangle: "{0.97, 0.97, 0.97}", xmin, xmax, -aMax, aMax

    # Windows painted behind the waveform
    for k from 1 to nSeg
        if segClipped[k] = 1
            wCol$ = "{0.95, 0.86, 0.80}"
        else
            wCol$ = "{0.86, 0.90, 0.95}"
        endif
        Paint rectangle: wCol$, segStart[k], segEnd[k], -aMax, aMax
    endfor

    Colour: "{0.82, 0.82, 0.82}"
    Draw line: xmin, 0, xmax, 0

    selectObject: sound
    Colour: "{0.22, 0.22, 0.26}"
    Line width: 1
    Draw: 0, 0, -aMax, aMax, "no", "Curve"

    for k from 1 to nSeg
        segCol$ = "{" + fixed$(cR[k], 2) + ", " + fixed$(cG[k], 2) + ", " + fixed$(cB[k], 2) + "}"
        Colour: segCol$
        Line width: 1.6
        Draw line: segPoint[k], -aMax * 0.92, segPoint[k], aMax * 0.92
        Font size: 5
        Text: segPoint[k], "centre", aMax * 0.80, "half", string$(k)
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Source"
    Text top: "no", "Marks and their windows  (blue = full window, red = clipped at a file edge)"
    Text bottom: "yes", "Source time (s)"

    # ----------------------------------------------------------
    # PANEL B: MONTAGE TIMELINE
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 2.78, 4.70
    Select inner viewport: 0.55, 7.75, 2.86, 4.62

    Axes: 0, finalDur, 0.3, nSeg + 0.7
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, finalDur, 0.3, nSeg + 0.7

    runT = 0
    for k from 1 to nSeg
        yy = nSeg + 1 - k
        blockCol$ = "{" + fixed$(cR[k], 2) + ", " + fixed$(cG[k], 2) + ", " + fixed$(cB[k], 2) + "}"
        # Source extent, faint, for comparison with the processed length
        Colour: "{0.86, 0.86, 0.86}"
        Draw rectangle: runT, runT + segSrcDur[k], yy - 0.16, yy + 0.16
        Paint rectangle: blockCol$, runT, runT + segOutDur[k], yy - 0.32, yy + 0.32
        Colour: "{0.30, 0.30, 0.30}"
        Draw rectangle: runT, runT + segOutDur[k], yy - 0.32, yy + 0.32

        Font size: 4
        Colour: "White"
        mutTag$ = ""
        if segFlip[k] = 1
            mutTag$ = "flip "
        endif
        if abs(segSemis[k]) > 0.01
            mutTag$ = mutTag$ + fixed$(segSemis[k], 2) + "st"
        endif
        if montage_style = 4 and abs(segRatio[k] - 1) > 0.01
            mutTag$ = "x" + fixed$(segRatio[k], 2)
        endif
        if mutTag$ <> "" and segOutDur[k] > finalDur * 0.05
            Text: runT + segOutDur[k] / 2, "centre", yy, "half", mutTag$
        endif
        Font size: 5
        Colour: "{0.35, 0.35, 0.35}"
        Text: -finalDur * 0.012, "right", yy, "half", string$(k)

        if transition_mode = 2
            runT = runT + segOutDur[k] - ovlUsed
        elsif transition_mode = 3
            runT = runT + segOutDur[k] + transition_amount
        else
            runT = runT + segOutDur[k]
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Peephole"
    Text top: "no", "Montage order  (grey = source length, bar = length after processing)"
    Text bottom: "yes", "Montage time (s)"

    # ----------------------------------------------------------
    # PANEL C: OUTPUT WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.78, 5.85
    Select inner viewport: 0.55, 7.75, 4.84, 5.78

    selectObject: result
    resPeak = Get absolute extremum: 0, 0, "None"
    if resPeak < 0.001
        resPeak = 0.001
    endif
    oMax = resPeak * 1.15
    Axes: 0, finalDur, -oMax, oMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, finalDur, -oMax, oMax
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, finalDur, 0

    selectObject: result
    Colour: "{0.25, 0.45, 0.78}"
    Line width: 1
    Draw: 0, 0, -oMax, oMax, "no", "Curve"

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text top: "no", "Montage"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL D: SUMMARY
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.93, 7.00
    Select inner viewport: 0.55, 7.75, 5.99, 6.94
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.80, "half",
        ... "##" + styleName$ + "##"
        ... + "  " + sound_name$
        ... + "  |  " + string$(nSeg) + " of " + string$(n_points) + " marks used"
        ... + "  |  source " + fixed$(xmax - xmin, 2) + " s"
        ... + "  |  montage " + fixed$(finalDur, 2) + " s"
        ... + "  |  sampled " + fixed$(totalSrc / (xmax - xmin) * 100, 1) + "%"

    if transition_mode = 1
        joinTag$ = "butt joint"
    elsif transition_mode = 2
        joinTag$ = "overlap " + fixed$(ovlUsed * 1000, 0) + " ms"
    else
        joinTag$ = "gap " + fixed$(transition_amount * 1000, 0) + " ms"
    endif
    if fade_type = 1
        fadeTag$ = "no edge fade"
    else
        fadeTag$ = "fade " + fixed$(minFade * 1000, 1) + "-" + fixed$(maxFade * 1000, 1) + " ms"
    endif
    Text: 0.02, "left", 0.50, "half",
        ... fadeTag$
        ... + "  |  " + joinTag$
        ... + "  |  " + string$(clippedCount) + " clipped window(s)"
        ... + "  |  " + string$(skipped) + " mark(s) skipped"
        ... + "  |  seed " + string$(seedUsed)

    Text: 0.02, "left", 0.20, "half",
        ... "Gain: " + normMode$
        ... + "  |  peak " + fixed$(prePeak, 3) + " -> " + fixed$(finalPeak, 3)
        ... + "  |  PSOLA " + fixed$(pitch_floor, 0) + "-" + fixed$(pitch_ceiling, 0) + " Hz"
        ... + "  |  PointProcess kept for re-runs"

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endif


###############################################################################
# FINISH - result view in the Demo window, play
###############################################################################
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", resultName$, "  and  PointProcess peephole_marks (", nMk, " marks)"
appendInfoLine: "Re-run in batch with Peephole_montage.praat v0.3: select the Sound + peephole_marks."
finalView = 1
status$ = "Done: " + fixed$ (finalDur, 2) + " s."
@drawAll
if play_result
    selectObject: result
    Play
endif
selectObject: result
