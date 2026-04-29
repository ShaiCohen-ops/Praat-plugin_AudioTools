# ============================================================
# Praat AudioTools - Multitrack_Router.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 3.3.2 (2025)
# License: MIT License
#
# Description:
#   Form-driven multitrack routing and time-placement engine.
#   Select N Sound objects, assign them to virtual tracks,
#   sequence/reorder them, insert silences, apply gain + fades,
#   and render a single output Sound object:
#     Mono          – all tracks summed to 1 channel
#     Stereo        – tracks panned L/R via equal-power law
#     Multichannel  – one channel per track
#
#   ASSIGNMENT MODES:
#     1  All on track 1       2  One track per sound
#     3  Round-robin           4  Manual (Seq field)
#     5  Sequence per track   (Seq field, | separates tracks,
#        tokens: indices + SILx silence markers)
#
#   TIMING:
#     All-at-0   – layered from t=0
#     Sequential – butt-join / gap / overlap with crossfade
#
#   OVERRIDES FIELD (tag syntax, space-separated values):
#     g:-3 0 -6       per-sound gain dB
#     ch:0 2 1        channel select (0=mono 1=L 2=R)
#     pan:-1 0 1      pan position per track (-1..+1)
#     ord:3 1 2       manual order per sound
#     xf:lin          crossfade shape: lin (3 dB dip) or ep
#                     (3 dB bump if signals correlated)
#     sched           print schedule (now on by default)
#     Example: "g:-3 0 -6 ch:0 2 pan:-1 1 xf:ep"
#
#   CROSSFADE SHAPE NOTES:
#     `lin`  = linear envelopes. Sum of envelopes = 1 at midpoint
#              (correct for correlated signals; uncorrelated
#              signals dip ~3 dB at seam).
#     `ep`   = equal-power (sin/cos). Sum of POWERS = 1 at midpoint
#              (correct for uncorrelated signals; correlated signals
#              bump ~3 dB at seam).
#     Use `lin` when stitching two parts of the same recording;
#     use `ep` when stitching unrelated material.
#
#   PRESETS:
#     1 Custom  2 Sequential Chain  3 Crossfade Montage
#     4 Stereo Spread  5 Layered Stack  6 Dialogue Assembly
#     7 Multichannel Split
#
# Requires: Praat ≥ 6.0
# Category: Routing / Mixing / Composition
#
# Changelog v3.3.2:
#   - Form converted from Apply-loop (beginPause/endPause + repeat…
#     until 0) to a single-stage form…endform. The dialog now
#     appears once; the script runs and exits. Removed: v_ persistence
#     variables, clicked/Close button logic, prevResultID plumbing.
# Changelog v3.3.1 (regression fixes):
#   - Fix: restore removeObject: prevResultID before each Apply.
#     v3.3 dropped this block entirely, leaking one Sound object
#     into the object list on every Apply press.
#   - Fix: mix-down combine step reverted from Formula (part) back
#     to the v3.2 conditional Formula with col <= tNS guard.
#     Formula (part) uses output-relative col indices, so referencing
#     object[trkID[t], col] on a shorter track read past its end.
#   - Fix: loop variable 'fi' renamed to 'fIdx' in the fade-in
#     envelope drawing loop. 'fi' is parsed as the closing keyword
#     of an if-block by Praat, causing "Symbol misplaced fi" error.
# Changelog v3.3:
#   - Fix (correctness): fade-vs-crossfade precedence. v3.2's
#     overlap-with-crossfade branch overwrote per-segment
#     segFdOut[prev] and segFdIn[cur] with crossfade_seconds
#     unconditionally. Users who set per-sound fade-in/out
#     and used a crossfade had their fades silently replaced.
#     Now uses max() so the longer fade wins.
#   - Fix (correctness): re-clamp prev's fade-out length when
#     cur's start time is clamped to 0. v3.2 left fade-out
#     longer than the actual overlap, eating into prev's body.
#   - Fix (safety): segment-array size now sized from actual
#     token count after parsing (was nSounds*4+200, an
#     unbounded user-input flowing into a fixed-size array).
#   - Refactor: 4 near-duplicate override-parser blocks
#     collapsed into one extractTag procedure. ~60 lines saved.
#   - Speed: per-segment full-track Formula in stem assembly
#     replaced with Formula (part), scanning only the affected
#     sample range. On 30-segment tracks this is ~30x less work.
#   - Speed: default-shape fade-in/fade-out now uses Praat's
#     built-in Fade in / Fade out commands (Hanning curve)
#     instead of per-sample Formula. Custom xf:lin and xf:ep
#     shapes still use Formula since the built-ins don't
#     expose shape choice. Most segments use the default, so
#     this is a real win on typical material.
#   - Schedule prints by default whenever segments exist.
#     The sched tag is preserved as a no-op for backwards
#     compatibility.
#   - Visualization: timeline panel rewritten as the headline.
#     Block height now encodes RMS. Fade-in / fade-out
#     envelopes drawn on top of each block. Crossfade overlap
#     regions hatched diagonally. Pan indicator drawn on the
#     left edge of each lane when output is stereo. Time grid
#     every 1 s. Tracks with no segments are visually muted.
#   - Form variable name unified: 'visualize' (form) ->
#     'draw_visualization' (working) renamed to a single
#     consistent name throughout.
# Changelog v3.2:
#   - Apply-loop pattern, override tag mini-language.
# ============================================================

# ============================================================
# STEP 0 - READ ALL SELECTED SOUNDS
# ============================================================

nSounds = numberOfSelected("Sound")
if nSounds < 1
    exitScript: "Select at least one Sound object."
endif

for i from 1 to nSounds
    sndID[i]    = selected("Sound", i)
    sndName$[i] = selected$("Sound", i)
endfor
for i from 1 to nSounds
    selectObject: sndID[i]
    sndDur[i] = Get total duration
    sndFs[i]  = Get sampling frequency
    # Pre-compute RMS for visualization (cached, used per-segment)
    sndRMS[i] = Get root-mean-square: 0, 0
endfor

refFs = sndFs[1]
for i from 2 to nSounds
    if sndFs[i] > refFs
        refFs = sndFs[i]
    endif
endfor

# ============================================================
# UTILITY PROCEDURES
# ============================================================

# Token splitter — splits .str$ on whitespace into .tok$[1..n]
procedure splitTokens: .str$
    .n = 0
    .rem$ = .str$
    .go = 1
    while .go = 1
        while length(.rem$) > 0 and (left$(.rem$, 1) = " " or left$(.rem$, 1) = tab$)
            .rem$ = mid$(.rem$, 2)
        endwhile
        if length(.rem$) = 0
            .go = 0
        else
            .sp = index(.rem$, " ")
            .tb = index(.rem$, tab$)
            if .tb > 0 and (.tb < .sp or .sp = 0)
                .sp = .tb
            endif
            .n += 1
            if .sp = 0
                .tok$[.n] = .rem$
                .rem$ = ""
            else
                .tok$[.n] = left$(.rem$, .sp - 1)
                .rem$ = mid$(.rem$, .sp + 1)
            endif
        endif
    endwhile
endproc

# Tag extractor — finds .tag$ inside .ovr$ and returns the
# whitespace-trimmed value substring up to the next tag boundary
# (next ":" anywhere, walked back to the preceding space). Returns
# .found = 1 if the tag was present.
# Replaces 4 × 18-line copy-paste blocks from v3.2.
procedure extractTag: .ovr$, .tag$
    .found = 0
    .val$ = ""
    .pos = index(.ovr$, .tag$)
    if .pos > 0
        .found = 1
        .skip = length(.tag$)
        .sub$ = mid$(.ovr$, .pos + .skip)
        .end = index(.sub$, ":")
        if .end > 0
            # Walk back to the space before the next tag
            .end2 = .end - 1
            while .end2 > 1 and mid$(.sub$, .end2, 1) <> " "
                .end2 = .end2 - 1
            endwhile
            .val$ = left$(.sub$, .end2)
        else
            .val$ = .sub$
        endif
        # Trim trailing whitespace
        while length(.val$) > 0 and right$(.val$, 1) = " "
            .val$ = left$(.val$, length(.val$) - 1)
        endwhile
        # Trim leading whitespace
        while length(.val$) > 0 and left$(.val$, 1) = " "
            .val$ = mid$(.val$, 2)
        endwhile
    endif
endproc

# ============================================================
# STEP 1 - FORM WITH APPLY LOOP
# ============================================================

form Multitrack Router
    optionmenu Preset: 1
        option Custom
        option Sequential Chain
        option Crossfade Montage
        option Stereo Spread
        option Layered Stack
        option Dialogue Assembly
        option Multichannel Split
    natural Tracks 2
    optionmenu Assignment: 1
        option All on track 1
        option One track per sound
        option Round-robin
        option Manual  (-> Seq field)
        option Sequence  (-> Seq field)
    sentence Seq 
    optionmenu Timing: 2
        option All at 0  (layer)
        option Sequential
    real Gap_s 0.0
    real Crossfade_s 0.0
    real Gain_dB 0.0
    real Fade_in_s 0.01
    real Fade_out_s 0.01
    optionmenu Output: 1
        option Mono
        option Stereo
        option Multichannel
    sentence Overrides 
    boolean Normalize 1
    boolean Draw_visualization 1
endform

    # ========================================================
    # PROCESS
    # ========================================================

    # --- Map form names to internal names ---
    number_of_tracks  = tracks
    assignment_mode   = assignment
    sequences$        = seq$
    time_mode         = timing
    gap_seconds       = gap_s
    crossfade_seconds = crossfade_s
    default_gain_dB   = gain_dB
    fade_in_seconds   = fade_in_s
    fade_out_seconds  = fade_out_s
    output_channels   = output
    normalize_output  = normalize
    do_visualization  = draw_visualization


    # Defaults for override-only params
    crossfade_shape   = 2
    print_schedule    = 1
    order_mode        = 1
    gains_dB$         = ""
    channel_select$   = ""
    pan_positions$    = ""
    order$            = ""

    # ---- Parse Overrides field via shared procedure ----
    ovr$ = overrides$ + " "
    
    @extractTag: ovr$, "g:"
    if extractTag.found = 1
        gains_dB$ = extractTag.val$
    endif
    
    @extractTag: ovr$, "ch:"
    if extractTag.found = 1
        channel_select$ = extractTag.val$
    endif
    
    @extractTag: ovr$, "pan:"
    if extractTag.found = 1
        pan_positions$ = extractTag.val$
    endif
    
    @extractTag: ovr$, "ord:"
    if extractTag.found = 1
        order_mode = 3
        order$ = extractTag.val$
    endif
    
    @extractTag: ovr$, "xf:"
    if extractTag.found = 1
        if left$(extractTag.val$, 3) = "lin"
            crossfade_shape = 1
        else
            crossfade_shape = 2
        endif
    endif
    
    # sched flag is a no-op now (schedule prints by default)
    # but the tag is still parsed for backward compatibility
    if index(ovr$, "sched") > 0
        print_schedule = 1
    endif

    # ---- Preset overrides ----
    if preset = 2
        number_of_tracks = 1
        assignment_mode  = 1
        time_mode        = 2
        gap_seconds      = 0.0
        crossfade_seconds = 0.0
        fade_in_seconds  = 0.005
        fade_out_seconds = 0.005
        output_channels  = 1
    elsif preset = 3
        number_of_tracks = 1
        assignment_mode  = 1
        time_mode        = 2
        gap_seconds      = -0.05
        crossfade_seconds = 0.05
        crossfade_shape  = 2
        fade_in_seconds  = 0.0
        fade_out_seconds = 0.0
        output_channels  = 1
    elsif preset = 4
        number_of_tracks = 2
        assignment_mode  = 3
        time_mode        = 2
        gap_seconds      = 0.0
        crossfade_seconds = 0.0
        fade_in_seconds  = 0.01
        fade_out_seconds = 0.01
        output_channels  = 2
    elsif preset = 5
        number_of_tracks = nSounds
        assignment_mode  = 2
        time_mode        = 1
        gap_seconds      = 0.0
        crossfade_seconds = 0.0
        fade_in_seconds  = 0.02
        fade_out_seconds = 0.02
        output_channels  = 1
    elsif preset = 6
        number_of_tracks = 1
        assignment_mode  = 1
        time_mode        = 2
        gap_seconds      = 0.3
        crossfade_seconds = 0.0
        fade_in_seconds  = 0.01
        fade_out_seconds = 0.01
        output_channels  = 1
    elsif preset = 7
        number_of_tracks = nSounds
        assignment_mode  = 2
        time_mode        = 2
        gap_seconds      = 0.0
        crossfade_seconds = 0.0
        fade_in_seconds  = 0.005
        fade_out_seconds = 0.005
        output_channels  = 3
    endif

    # ---- Validate & clamp ----
    if number_of_tracks < 1
        number_of_tracks = 1
    endif
    if assignment_mode = 2
        number_of_tracks = nSounds
    endif
    if number_of_tracks > nSounds and assignment_mode <> 5
        number_of_tracks = nSounds
    endif
    if crossfade_seconds < 0
        crossfade_seconds = 0
    endif
    if fade_in_seconds < 0
        fade_in_seconds = 0
    endif
    if fade_out_seconds < 0
        fade_out_seconds = 0
    endif
    minDurForFade = 0.03

    # Labels
    presetName$[1] = "Custom"
    presetName$[2] = "Sequential Chain"
    presetName$[3] = "Crossfade Montage"
    presetName$[4] = "Stereo Spread"
    presetName$[5] = "Layered Stack"
    presetName$[6] = "Dialogue Assembly"
    presetName$[7] = "Multichannel Split"
    assignName$[1] = "All->1"
    assignName$[2] = "1/snd"
    assignName$[3] = "RndRbn"
    assignName$[4] = "Manual"
    assignName$[5] = "Seq"
    if output_channels = 1
        outModeName$ = "Mono"
    elsif output_channels = 2
        outModeName$ = "Stereo"
    else
        outModeName$ = "Multi(" + string$(number_of_tracks) + "ch)"
    endif

    # ---- Per-sound parameters ----
    for i from 1 to nSounds
        sndGain[i]    = default_gain_dB
        sndFadeIn[i]  = fade_in_seconds
        sndFadeOut[i] = fade_out_seconds
        sndChSel[i]   = 0
    endfor

    if gains_dB$ <> ""
        @splitTokens: gains_dB$
        nP = splitTokens.n
        if nP > nSounds
            nP = nSounds
        endif
        for i from 1 to nP
            sndGain[i] = number(splitTokens.tok$[i])
        endfor
    endif

    if channel_select$ <> ""
        @splitTokens: channel_select$
        nP = splitTokens.n
        if nP > nSounds
            nP = nSounds
        endif
        for i from 1 to nP
            sndChSel[i] = number(splitTokens.tok$[i])
            if sndChSel[i] < 0 or sndChSel[i] > 2
                sndChSel[i] = 0
            endif
        endfor
    endif

    # Manual assignments (mode 4) — read from Seq field
    for i from 1 to nSounds
        sndTrackAssign[i] = 1
    endfor
    if assignment_mode = 4
        if seq$ = ""
            exitScript: "Manual assignment: put track numbers in Seq field."
        endif
        @splitTokens: seq$
        if splitTokens.n < nSounds
            exitScript: "Seq: need " + string$(nSounds) + " track numbers."
        endif
        for i from 1 to nSounds
            sndTrackAssign[i] = number(splitTokens.tok$[i])
            if sndTrackAssign[i] < 1 or sndTrackAssign[i] > number_of_tracks
                exitScript: "Seq value " + string$(i) + " out of range."
            endif
        endfor
    endif

    # Manual order
    for i from 1 to nSounds
        sndOrderPos[i] = i
    endfor
    if order_mode = 3
        if order$ = ""
            exitScript: "ord: tag needs " + string$(nSounds) + " values."
        endif
        @splitTokens: order$
        if splitTokens.n < nSounds
            exitScript: "ord: need " + string$(nSounds) + " values."
        endif
        for i from 1 to nSounds
            sndOrderPos[i] = number(splitTokens.tok$[i])
        endfor
    endif

    # Pan (manual parse; auto-spread deferred)
    for t from 1 to 128
        trkPan[t] = 0.0
    endfor
    panIsManual = 0
    if output_channels = 2
        if pan_positions$ <> ""
            panIsManual = 1
            @splitTokens: pan_positions$
            nP = splitTokens.n
            if nP > number_of_tracks
                nP = number_of_tracks
            endif
            for i from 1 to nP
                trkPan[i] = number(splitTokens.tok$[i])
                if trkPan[i] < -1
                    trkPan[i] = -1
                endif
                if trkPan[i] > 1
                    trkPan[i] = 1
                endif
            endfor
        endif
    endif

    # ---- Compute segment array size from actual usage ----
    # v3.2 used a fixed nSounds*4 + 200, which could be exceeded
    # by sequence-mode tracks packing many SIL markers + reuse.
    # Now we count tokens up front for the sequence-mode case and
    # size the array accordingly.
    if assignment_mode = 5 and sequences$ <> ""
        # Count all tokens across all track sub-sequences
        seqCountTmp$ = sequences$
        # Replace pipes with spaces so splitTokens counts everything
        countTokens = 0
        countRem$ = sequences$
        while length(countRem$) > 0
            pipePosTmp = index(countRem$, "|")
            if pipePosTmp > 0
                segPart$ = left$(countRem$, pipePosTmp - 1)
                countRem$ = mid$(countRem$, pipePosTmp + 1)
            else
                segPart$ = countRem$
                countRem$ = ""
            endif
            if segPart$ <> ""
                @splitTokens: segPart$
                countTokens = countTokens + splitTokens.n
            endif
        endwhile
        maxSegs = countTokens + number_of_tracks + 50
    else
        maxSegs = nSounds + number_of_tracks + 50
    endif
    if maxSegs < 100
        maxSegs = 100
    endif

    # ---- Build segment lists ----
    for s from 1 to maxSegs
        segType[s]   = 0
        segSrc[s]    = 0
        segDur[s]    = 0.0
        segGainDB[s] = 0.0
        segFdIn[s]   = 0.0
        segFdOut[s]  = 0.0
        segStart[s]  = 0.0
        segTrack[s]  = 0
        segXfWith[s] = 0
    endfor
    totalSegs = 0
    for t from 1 to number_of_tracks
        trkSegS[t] = 0
        trkSegN[t] = 0
    endfor

    clearinfo
    appendInfoLine: "=================================================="
    appendInfoLine: "  Multitrack Router v3.3.1  ·  ", presetName$[preset]
    appendInfoLine: "=================================================="
    appendInfoLine: ""
    appendInfoLine: nSounds, " sounds -> ", number_of_tracks, " tracks  ",
        ... refFs, " Hz  ", outModeName$
    appendInfoLine: ""

    # ---- MODE 5: Sequence per track ----
    if assignment_mode = 5
        if sequences$ = ""
            sequences$ = ""
            for t from 1 to number_of_tracks
                trkAuto$[t] = ""
            endfor
            for i from 1 to nSounds
                t = ((i - 1) mod number_of_tracks) + 1
                if trkAuto$[t] <> ""
                    trkAuto$[t] = trkAuto$[t] + " "
                endif
                trkAuto$[t] = trkAuto$[t] + string$(i)
            endfor
            for t from 1 to number_of_tracks
                if t > 1
                    sequences$ = sequences$ + " | "
                endif
                sequences$ = sequences$ + trkAuto$[t]
            endfor
            appendInfoLine: "  (auto: ", sequences$, ")"
            appendInfoLine: ""
        endif

        seqFull$ = sequences$
        for t from 1 to number_of_tracks
            pipePos = index(seqFull$, "|")
            if pipePos > 0
                trkSeq$[t] = left$(seqFull$, pipePos - 1)
                seqFull$ = mid$(seqFull$, pipePos + 1)
            else
                trkSeq$[t] = seqFull$
                seqFull$ = ""
            endif
        endfor

        for t from 1 to number_of_tracks
            trkSegS[t] = totalSegs + 1
            trkSegN[t] = 0
            while length(trkSeq$[t]) > 0 and left$(trkSeq$[t], 1) = " "
                trkSeq$[t] = mid$(trkSeq$[t], 2)
            endwhile
            if trkSeq$[t] <> ""
                @splitTokens: trkSeq$[t]
                for tok from 1 to splitTokens.n
                    token$ = splitTokens.tok$[tok]
                    isSil = 0
                    if length(token$) > 3
                        pfx$ = left$(token$, 3)
                        if pfx$ = "SIL" or pfx$ = "sil" or pfx$ = "Sil"
                            isSil = 1
                        endif
                    endif
                    totalSegs += 1
                    trkSegN[t] += 1
                    segTrack[totalSegs] = t
                    if isSil = 1
                        sd = number(mid$(token$, 4))
                        if sd = undefined or sd <= 0
                            exitScript: "Bad SIL '" + token$ + "' trk " + string$(t)
                        endif
                        segType[totalSegs] = 0
                        segDur[totalSegs]  = sd
                    else
                        ix = number(token$)
                        if ix = undefined or ix < 1 or ix > nSounds
                            exitScript: "Bad '" + token$ + "' trk "
                                ... + string$(t) + " (1.." + string$(nSounds) + ")"
                        endif
                        ix = round(ix)
                        segType[totalSegs]   = 1
                        segSrc[totalSegs]    = ix
                        segDur[totalSegs]    = sndDur[ix]
                        segGainDB[totalSegs] = sndGain[ix]
                        segFdIn[totalSegs]   = sndFadeIn[ix]
                        segFdOut[totalSegs]  = sndFadeOut[ix]
                    endif
                endfor
            endif
        endfor

    # ---- MODES 1-4 ----
    else
        for i from 1 to nSounds
            if assignment_mode = 1
                sndTrack[i] = 1
            elsif assignment_mode = 2
                sndTrack[i] = i
            elsif assignment_mode = 3
                sndTrack[i] = ((i - 1) mod number_of_tracks) + 1
            else
                sndTrack[i] = sndTrackAssign[i]
            endif
        endfor

        for t from 1 to number_of_tracks
            trkN[t] = 0
        endfor
        for i from 1 to nSounds
            t = sndTrack[i]
            trkN[t] += 1
            trkSnd[t, trkN[t]] = i
        endfor

        # Sort by manual order if requested
        for t from 1 to number_of_tracks
            n = trkN[t]
            if n > 1 and order_mode = 3
                for pass from 1 to n - 1
                    for j from 1 to n - pass
                        if sndOrderPos[trkSnd[t, j]] > sndOrderPos[trkSnd[t, j + 1]]
                            swp = trkSnd[t, j]
                            trkSnd[t, j] = trkSnd[t, j + 1]
                            trkSnd[t, j + 1] = swp
                        endif
                    endfor
                endfor
            endif
        endfor

        for t from 1 to number_of_tracks
            trkSegS[t] = totalSegs + 1
            trkSegN[t] = trkN[t]
            for j from 1 to trkN[t]
                ix = trkSnd[t, j]
                totalSegs += 1
                segType[totalSegs]   = 1
                segSrc[totalSegs]    = ix
                segDur[totalSegs]    = sndDur[ix]
                segGainDB[totalSegs] = sndGain[ix]
                segFdIn[totalSegs]   = sndFadeIn[ix]
                segFdOut[totalSegs]  = sndFadeOut[ix]
                segTrack[totalSegs]  = t
            endfor
        endfor
    endif

    appendInfoLine: "Segments: ", totalSegs

    # ---- Auto-pan (deferred) ----
    if output_channels = 2 and panIsManual = 0
        nActive = 0
        for t from 1 to number_of_tracks
            if trkSegN[t] > 0
                nActive += 1
            endif
        endfor
        if nActive <= 1
            for t from 1 to number_of_tracks
                trkPan[t] = 0.0
            endfor
        else
            aIdx = 0
            for t from 1 to number_of_tracks
                if trkSegN[t] > 0
                    aIdx += 1
                    trkPan[t] = -1.0 + 2.0 * (aIdx - 1) / (nActive - 1)
                else
                    trkPan[t] = 0.0
                endif
            endfor
        endif
    endif

    # ---- Compute timing ----
    appendInfoLine: "[1/3] Timing..."
    for t from 1 to number_of_tracks
        s0 = trkSegS[t]
        nS = trkSegN[t]
        if nS > 0
            if time_mode = 1
                for j from 0 to nS - 1
                    segStart[s0 + j] = 0.0
                endfor
            else
                segStart[s0] = 0.0
                for j from 1 to nS - 1
                    cur  = s0 + j
                    prev = s0 + j - 1
                    pEnd = segStart[prev] + segDur[prev]
                    prop = pEnd + gap_seconds
                    if gap_seconds < 0
                        ovl = abs(gap_seconds)
                        if crossfade_seconds > 0
                            ovl = crossfade_seconds
                        endif
                        prop = pEnd - ovl
                        if prop < 0
                            prop = 0
                            # FIX (Bug C v3.3): re-clamp the actual overlap
                            # length when start was clamped to 0.
                            ovl = pEnd
                        endif
                        if crossfade_seconds > 0
                            # FIX (Bug A v3.3): use max() instead of
                            # overwriting per-segment fades. The longer
                            # fade wins; user-supplied fade-out / fade-in
                            # is preserved if it exceeds crossfade_seconds.
                            cfLen = ovl
                            if cfLen > crossfade_seconds
                                cfLen = crossfade_seconds
                            endif
                            if segType[prev] = 1
                                if segFdOut[prev] < cfLen
                                    segFdOut[prev] = cfLen
                                endif
                            endif
                            if segType[cur] = 1
                                if segFdIn[cur] < cfLen
                                    segFdIn[cur] = cfLen
                                endif
                            endif
                            # Mark the crossfade pair for visualization
                            segXfWith[prev] = cur
                        endif
                    endif
                    segStart[cur] = prop
                endfor
            endif
        endif
    endfor

    # ---- Render mono track stems ----
    appendInfoLine: "[2/3] Rendering..."
    for t from 1 to number_of_tracks
        s0 = trkSegS[t]
        nS = trkSegN[t]
        if nS = 0
            trkDur[t] = 0.001
            trkID[t] = Create Sound from formula: "mrt_trk_" + string$(t),
                ... 1, 0, 0.001, refFs, "0"
        else
            trkDur[t] = 0.0
            for j from 0 to nS - 1
                eT = segStart[s0 + j] + segDur[s0 + j]
                if eT > trkDur[t]
                    trkDur[t] = eT
                endif
            endfor
            trkDur[t] = trkDur[t] + 0.0005

            trkID[t] = Create Sound from formula: "mrt_trk_" + string$(t),
                ... 1, 0, trkDur[t], refFs, "0"

            for j from 0 to nS - 1
                sIdx = s0 + j
                if segType[sIdx] = 1
                    srcI = segSrc[sIdx]
                    selectObject: sndID[srcI]
                    sc = Copy: "mrt_sc"

                    selectObject: sc
                    nCh = Get number of channels
                    if nCh > 1
                        chSel = sndChSel[srcI]
                        if chSel = 1
                            scM = Extract one channel: 1
                        elsif chSel = 2
                            if nCh >= 2
                                scM = Extract one channel: 2
                            else
                                scM = Extract one channel: 1
                            endif
                        else
                            selectObject: sc
                            scM = Convert to mono
                        endif
                        removeObject: sc
                        sc = scM
                    endif

                    selectObject: sc
                    scFs = Get sampling frequency
                    if scFs <> refFs
                        scR = Resample: refFs, 50
                        removeObject: sc
                        sc = scR
                    endif

                    gdb = segGainDB[sIdx]
                    if gdb <> 0
                        selectObject: sc
                        glin = 10.0 ^ (gdb / 20.0)
                        Formula: "self * " + fixed$(glin, 8)
                    endif

                    # ---- Apply fades ----
                    # v3.3: built-in Fade in / Fade out for the default
                    # Hanning shape (faster), Formula path only when
                    # crossfade_shape selects an explicit lin/ep curve
                    # AND the segment is part of a crossfade pair.
                    selectObject: sc
                    sDur = Get total duration
                    if sDur >= minDurForFade
                        fdI = segFdIn[sIdx]
                        fdO = segFdOut[sIdx]
                        if fdI > sDur * 0.45
                            fdI = sDur * 0.45
                        endif
                        if fdO > sDur * 0.45
                            fdO = sDur * 0.45
                        endif
                        
                        # Use Praat built-ins (Hanning) for the default
                        # case. Switch to Formula for crossfade segments
                        # where shape was explicitly chosen.
                        useExplicit = 0
                        if segXfWith[sIdx] > 0 or (sIdx > s0 and segXfWith[sIdx - 1] = sIdx)
                            useExplicit = 1
                        endif
                        
                        if fdI > 0.0001
                            if useExplicit = 1
                                fiS$ = fixed$(fdI, 8)
                                if crossfade_shape = 1
                                    Formula: "if x < " + fiS$
                                        ... + " then self * (x / " + fiS$ + ")"
                                        ... + " else self fi"
                                else
                                    Formula: "if x < " + fiS$
                                        ... + " then self * sin(pi/2 * x / " + fiS$ + ")"
                                        ... + " else self fi"
                                endif
                            else
                                Fade in: 0, 0, fdI, "yes"
                            endif
                        endif
                        if fdO > 0.0001
                            if useExplicit = 1
                                foS$ = fixed$(fdO, 8)
                                dS$  = fixed$(sDur, 8)
                                foB$ = fixed$(sDur - fdO, 8)
                                if crossfade_shape = 1
                                    Formula: "if x > " + foB$
                                        ... + " then self * ((" + dS$ + " - x) / " + foS$ + ")"
                                        ... + " else self fi"
                                else
                                    Formula: "if x > " + foB$
                                        ... + " then self * cos(pi/2 * (x - " + foB$
                                        ... + ") / " + foS$ + ")"
                                        ... + " else self fi"
                                endif
                            else
                                Fade out: 0, sDur - fdO, fdO, "yes"
                            endif
                        endif
                    endif

                    # ---- Overlay onto track stem via Formula (part) ----
                    # v3.3: Formula (part) instead of full-track Formula.
                    # On a 30-segment track, full-track Formula scans the
                    # entire track buffer 30 times; Formula (part) scans
                    # only each segment's actual sample range.
                    selectObject: sc
                    scNS = Get number of samples
                    selectObject: trkID[t]
                    s1 = Get sample number from time: segStart[sIdx]
                    if s1 < 1
                        s1 = 1
                    endif
                    s2 = s1 + scNS - 1
                    tNS = Get number of samples
                    if s2 > tNS
                        s2 = tNS
                    endif
                    
                    if s2 >= s1
                        off = s1 - 1
                        # Convert sample range to time range for Formula (part) bounds
                        t_lo = (s1 - 1) / refFs
                        t_hi = s2 / refFs
                        
                        selectObject: trkID[t]
                        Formula (part): t_lo, t_hi, 1, 1,
                            ... "self + object[" + string$(sc)
                            ... + ", col - " + string$(off) + "]"
                    endif
                    
                    removeObject: sc
                endif
            endfor
        endif
    endfor

    # ---- Combine into single output ----
    appendInfoLine: "[3/3] Mixing..."
    masterDur = 0.0
    for t from 1 to number_of_tracks
        if trkDur[t] > masterDur
            masterDur = trkDur[t]
        endif
    endfor

    if output_channels = 1
        outID = Create Sound from formula: "Routed_mono",
            ... 1, 0, masterDur, refFs, "0"
        for t from 1 to number_of_tracks
            selectObject: trkID[t]
            tNS = Get number of samples
            selectObject: outID
            Formula: "if col <= " + string$(tNS)
                ... + " then self + object[" + string$(trkID[t]) + ", col]"
                ... + " else self fi"
        endfor

    elsif output_channels = 2
        outID = Create Sound from formula: "Routed_stereo",
            ... 2, 0, masterDur, refFs, "0"
        for t from 1 to number_of_tracks
            panAngle = (trkPan[t] + 1.0) / 2.0 * (pi / 2.0)
            gainL$ = fixed$(cos(panAngle), 8)
            gainR$ = fixed$(sin(panAngle), 8)
            selectObject: trkID[t]
            tNS = Get number of samples
            selectObject: outID
            Formula: "if row = 1 and col <= " + string$(tNS)
                ... + " then self + " + gainL$
                ... + " * object[" + string$(trkID[t]) + ", col]"
                ... + " else self fi"
            selectObject: outID
            Formula: "if row = 2 and col <= " + string$(tNS)
                ... + " then self + " + gainR$
                ... + " * object[" + string$(trkID[t]) + ", col]"
                ... + " else self fi"
        endfor

    else
        outID = Create Sound from formula: "Routed_multi",
            ... number_of_tracks, 0, masterDur, refFs, "0"
        for t from 1 to number_of_tracks
            selectObject: trkID[t]
            tNS = Get number of samples
            selectObject: outID
            Formula: "if row = " + string$(t) + " and col <= " + string$(tNS)
                ... + " then self + object[" + string$(trkID[t]) + ", col]"
                ... + " else self fi"
        endfor
    endif

    if normalize_output = 1
        selectObject: outID
        pk = Get absolute extremum: 0, 0, "None"
        if pk > 0.001
            Scale peak: 0.99
        endif
        appendInfoLine: "  Normalized (peak was ", fixed$(pk, 4), ")"
    endif
    selectObject: outID
    pkFinal = Get absolute extremum: 0, 0, "None"
    appendInfoLine: "  Peak: ", fixed$(pkFinal, 4),
        ... "  Dur: ", fixed$(masterDur, 3), " s"

    resultID  = outID
    selectObject: resultID
    resultDur = Get total duration
    outputName$ = selected$("Sound")

    for t from 1 to number_of_tracks
        removeObject: trkID[t]
    endfor

    # ============================================================
    # SCHEDULE  (printed by default in v3.3)
    # ============================================================
    if print_schedule = 1 and totalSegs > 0
        appendInfoLine: ""
        appendInfoLine: "== SCHEDULE =="
        appendInfoLine: "Seg|Trk|Type   |Src|Start   |End     |Gain|FdIn |FdOut|Name"
        for s from 1 to totalSegs
            eT = segStart[s] + segDur[s]
            if segType[s] = 1
                tp$ = "AUDIO  "
                sr$ = left$(string$(segSrc[s]) + "  ", 3)
                nm$ = " " + sndName$[segSrc[s]]
            else
                tp$ = "SILENCE"
                sr$ = " - "
                nm$ = ""
            endif
            appendInfoLine:
                ... left$(string$(s) + "  ", 3),
                ... "|", left$(string$(segTrack[s]) + "  ", 3),
                ... "|", tp$,
                ... "|", sr$,
                ... "|", left$(fixed$(segStart[s], 3) + "       ", 8),
                ... "|", left$(fixed$(eT, 3) + "       ", 8),
                ... "|", left$(fixed$(segGainDB[s], 1) + "   ", 4),
                ... "|", left$(fixed$(segFdIn[s], 3) + "    ", 5),
                ... "|", fixed$(segFdOut[s], 3),
                ... nm$
        endfor
    endif

    # ============================================================
    # VISUALIZATION  (8 x 8 canvas, suite-standard)
    # Headline panel = enriched timeline
    # ============================================================
    if do_visualization = 1
        Erase all
        
        # --- Title ---
        Select outer viewport: 0, 8, 0, 0.55
        Axes: 0, 1, 0, 1
        Font size: 12
        Colour: "Black"
        Text: 0.5, "centre", 0.65, "half", "##MULTITRACK ROUTER##"
        Font size: 7
        Colour: "{0.35, 0.35, 0.45}"
        Text: 0.5, "centre", -0.20, "half",
            ... presetName$[preset]
            ... + "  |  " + string$(nSounds) + " snd -> "
            ... + string$(number_of_tracks) + " trk"
            ... + "  |  " + outModeName$
            ... + "  |  " + assignName$[assignment_mode]
            ... + "  |  " + fixed$(resultDur, 2) + " s"
            ... + "  |  pk=" + fixed$(pkFinal, 3)
        
        # --- Panel 1 (HEADLINE): enriched track timeline ---
        # Sized adaptively to track count; capped at 8 visible tracks.
        nTrkVis = number_of_tracks
        if nTrkVis > 8
            nTrkVis = 8
        endif
        
        # Allocate 0.65–4.40 of the canvas for this panel.
        p1top = 0.65
        p1bot = 4.40
        
        Select outer viewport: 0, 8, p1top, p1bot
        Select inner viewport: 0.65, 7.55, p1top + 0.10, p1bot - 0.20
        
        # Find global timeline end
        globalEnd = 0.001
        for s from 1 to totalSegs
            eT = segStart[s] + segDur[s]
            if eT > globalEnd
                globalEnd = eT
            endif
        endfor
        if resultDur > globalEnd
            globalEnd = resultDur
        endif
        globalEnd = globalEnd * 1.02
        
        Axes: 0, globalEnd, 0, nTrkVis + 1
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, globalEnd, 0, nTrkVis + 1
        
        # Time grid every 1 s
        Colour: "{0.90, 0.90, 0.93}"
        Line width: 1
        gx = 1
        while gx <= globalEnd
            Draw line: gx, 0, gx, nTrkVis + 1
            gx = gx + 1
        endwhile
        
        # Lane separators (between tracks)
        Colour: "{0.78, 0.78, 0.82}"
        for t from 1 to nTrkVis + 1
            yLane = nTrkVis + 1 - t
            Draw line: 0, yLane, globalEnd, yLane
        endfor
        
        # --- Track labels and pan indicators (left edge) ---
        Font size: 6
        Colour: "{0.45, 0.45, 0.55}"
        for t from 1 to nTrkVis
            yMid = nTrkVis + 1 - t + 0.5
            
            # Mute the label if track has no segments
            if trkSegN[t] = 0
                Colour: "{0.75, 0.75, 0.78}"
            else
                Colour: "{0.30, 0.30, 0.40}"
            endif
            Text: -globalEnd * 0.005, "right", yMid, "half", "T" + string$(t)
            
            # Pan indicator for stereo output
            if output_channels = 2
                pn = trkPan[t]
                # Mini bar showing pan: -1 -> left edge, +1 -> right edge.
                # Positioned just left of the track label area.
                Font size: 5
                if pn < -0.05
                    Colour: "{0.30, 0.50, 0.78}"
                    Text: -globalEnd * 0.040, "right", yMid, "half", "L" + fixed$(abs(pn), 2)
                elsif pn > 0.05
                    Colour: "{0.78, 0.45, 0.30}"
                    Text: -globalEnd * 0.040, "right", yMid, "half", "R" + fixed$(pn, 2)
                else
                    Colour: "{0.55, 0.55, 0.55}"
                    Text: -globalEnd * 0.040, "right", yMid, "half", "C"
                endif
            endif
        endfor
        
        # --- Find max RMS for block-height scaling ---
        maxRMSfound = 0
        for s from 1 to totalSegs
            if segType[s] = 1
                if sndRMS[segSrc[s]] > maxRMSfound
                    maxRMSfound = sndRMS[segSrc[s]]
                endif
            endif
        endfor
        if maxRMSfound < 0.0001
            maxRMSfound = 0.0001
        endif
        
        # --- Identify crossfade overlap regions ---
        # For sequential mode with overlaps, mark the [start_of_cur, end_of_prev]
        # interval per pair. We draw these as light hatching first, so segment
        # blocks render on top.
        if time_mode = 2
            for s from 1 to totalSegs
                if segXfWith[s] > 0
                    other = segXfWith[s]
                    if other >= 1 and other <= totalSegs
                        xfStart = segStart[other]
                        xfEnd = segStart[s] + segDur[s]
                        if xfStart < xfEnd
                            t = segTrack[s]
                            if t <= nTrkVis
                                yB = nTrkVis + 1 - t + 0.05
                                yT = nTrkVis + 1 - t + 0.95
                                # Diagonal hatching: 6 thin diagonal lines
                                Colour: "{0.85, 0.78, 0.55}"
                                Line width: 1
                                hatchN = 6
                                for h from 0 to hatchN
                                    hxa = xfStart + (xfEnd - xfStart) * h / hatchN
                                    hxb = xfStart + (xfEnd - xfStart) * (h + 1) / hatchN
                                    if hxb > xfEnd
                                        hxb = xfEnd
                                    endif
                                    Draw line: hxa, yB, hxb, yT
                                endfor
                            endif
                        endif
                    endif
                endif
            endfor
        endif
        
        # --- Draw segment blocks ---
        nSndM1 = nSounds - 1
        if nSndM1 < 1
            nSndM1 = 1
        endif
        for s from 1 to totalSegs
            t = segTrack[s]
            if t <= nTrkVis
                yLaneBase = nTrkVis + 1 - t
                bx1 = segStart[s]
                bx2 = segStart[s] + segDur[s]
                
                if segType[s] = 1
                    srcI = segSrc[s]
                    
                    # Block height encodes RMS
                    rmsRel = sndRMS[srcI] / maxRMSfound
                    if rmsRel < 0.15
                        rmsRel = 0.15
                    endif
                    if rmsRel > 1.0
                        rmsRel = 1.0
                    endif
                    blockH = 0.10 + rmsRel * 0.75
                    yB = yLaneBase + 0.08
                    yT = yLaneBase + 0.08 + blockH
                    
                    # Source-index colour (warm spread)
                    frac = (srcI - 1) / nSndM1
                    cR = 0.28 + frac * 0.55
                    cG = 0.52 - frac * 0.18
                    cB = 0.72 - frac * 0.50
                    if cG < 0
                        cG = 0
                    endif
                    if cB < 0
                        cB = 0
                    endif
                    clr$ = "{" + fixed$(cR, 2) + "," + fixed$(cG, 2) + "," + fixed$(cB, 2) + "}"
                    Paint rectangle: clr$, bx1, bx2, yB, yT
                    
                    # Block outline
                    Colour: "{0.30, 0.30, 0.30}"
                    Line width: 1
                    Draw rectangle: bx1, bx2, yB, yT
                    
                    # --- Fade-in / fade-out envelopes drawn ON the block ---
                    # Black line traces the envelope from yB->yT for fade-in
                    # and yT->yB for fade-out.
                    fdI = segFdIn[s]
                    fdO = segFdOut[s]
                    Colour: "{0.10, 0.10, 0.10}"
                    Line width: 1.2
                    if fdI > 0.0001 and fdI < segDur[s]
                        # Linear approximation suffices for visual; sample 6 points
                        nFi = 6
                        for fIdx from 0 to nFi - 1
                            fiRatio = fIdx / nFi
                            fi1Ratio = (fIdx + 1) / nFi
                            ax = bx1 + fdI * fiRatio
                            bx = bx1 + fdI * fi1Ratio
                            ay = yB + (yT - yB) * fiRatio
                            by = yB + (yT - yB) * fi1Ratio
                            Draw line: ax, ay, bx, by
                        endfor
                    endif
                    if fdO > 0.0001 and fdO < segDur[s]
                        nFo = 6
                        foStart = bx2 - fdO
                        for fo from 0 to nFo - 1
                            foRatio = fo / nFo
                            fo1Ratio = (fo + 1) / nFo
                            ax = foStart + fdO * foRatio
                            bx = foStart + fdO * fo1Ratio
                            ay = yT - (yT - yB) * foRatio
                            by = yT - (yT - yB) * fo1Ratio
                            Draw line: ax, ay, bx, by
                        endfor
                    endif
                    Line width: 1
                    
                    # Source index label inside block (only if wide enough)
                    if (bx2 - bx1) > globalEnd * 0.025
                        Font size: 5
                        Colour: "White"
                        Text: (bx1 + bx2) / 2, "centre", (yB + yT) / 2, "half", string$(srcI)
                    endif
                else
                    # SILENCE: low neutral block, dashed outline
                    yB = yLaneBase + 0.30
                    yT = yLaneBase + 0.50
                    Paint rectangle: "{0.92, 0.90, 0.85}", bx1, bx2, yB, yT
                    Colour: "{0.65, 0.62, 0.55}"
                    Dotted line
                    Line width: 1
                    Draw rectangle: bx1, bx2, yB, yT
                    Solid line
                    if (bx2 - bx1) > globalEnd * 0.04
                        Font size: 5
                        Colour: "{0.55, 0.50, 0.40}"
                        Text: (bx1 + bx2) / 2, "centre", (yB + yT) / 2, "half", "sil"
                    endif
                endif
            endif
        endfor
        
        Colour: "Black"
        Line width: 1
        Draw inner box
        Font size: 7
        Text top: "no", "Track timeline  (height = RMS, lines = fades, hatched = crossfade)"
        Text bottom: "yes", "Time (s)"
        
        # --- Panel 2: Output waveform ---
        Select outer viewport: 0, 8, 4.55, 5.85
        Select inner viewport: 0.55, 7.65, 4.65, 5.78
        
        selectObject: resultID
        resPeak = Get absolute extremum: 0, 0, "None"
        if resPeak < 0.001
            resPeak = 0.001
        endif
        ampMax = resPeak * 1.15
        Axes: 0, resultDur, -ampMax, ampMax
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, resultDur, -ampMax, ampMax
        Colour: "{0.80, 0.80, 0.80}"
        Draw line: 0, 0, resultDur, 0
        
        # Use channel colours for stereo, single colour otherwise
        selectObject: resultID
        nResultCh = Get number of channels
        if nResultCh = 1
            Colour: "{0.20, 0.55, 0.50}"
            Line width: 1
            Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
        elsif nResultCh = 2
            Extract one channel: 1
            vCh1 = selected("Sound")
            Colour: "{0.25, 0.50, 0.82}"
            Line width: 1
            Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
            removeObject: vCh1
            
            selectObject: resultID
            Extract one channel: 2
            vCh2 = selected("Sound")
            Colour: "{0.82, 0.45, 0.25}"
            Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
            removeObject: vCh2
        else
            # Multichannel — just show channel 1 as a representative
            Extract one channel: 1
            vCh1 = selected("Sound")
            Colour: "{0.25, 0.50, 0.82}"
            Line width: 1
            Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
            removeObject: vCh1
        endif
        
        Colour: "Black"
        Line width: 1
        Draw inner box
        Font size: 7
        if nResultCh = 2
            Text top: "no", "Output  (blue = L, orange = R)"
        elsif nResultCh > 2
            Text top: "no", "Output  (Ch1 shown of " + string$(nResultCh) + ")"
        else
            Text top: "no", "Output"
        endif
        Text left: "yes", "Amp"
        Text bottom: "yes", "Time (s)"
        
        # --- Panel 3: Summary stats bar ---
        Select outer viewport: 0, 8, 5.95, 6.65
        Select inner viewport: 0.55, 7.65, 6.00, 6.60
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
        
        if time_mode = 1
            tLbl$ = "Layer"
        else
            tLbl$ = "Seq"
        endif
        if crossfade_shape = 1
            xLbl$ = "lin"
        else
            xLbl$ = "ep"
        endif
        
        Font size: 6
        Colour: "{0.28, 0.28, 0.28}"
        Text: 0.02, "left", 0.75, "half",
            ... "##" + presetName$[preset] + "##"
            ... + "  " + assignName$[assignment_mode]
            ... + "  |  " + tLbl$
            ... + "  |  gap=" + fixed$(gap_seconds, 3) + " s"
            ... + "  |  xfade=" + fixed$(crossfade_seconds, 3) + " s (" + xLbl$ + ")"
            ... + "  |  default fade in/out: " + fixed$(fade_in_seconds, 3) + " / " + fixed$(fade_out_seconds, 3) + " s"
        
        Text: 0.02, "left", 0.28, "half",
            ... "Output: " + outModeName$
            ... + "  |  " + fixed$(resultDur, 3) + " s"
            ... + "  |  peak=" + fixed$(pkFinal, 4)
            ... + "  |  default gain=" + fixed$(default_gain_dB, 1) + " dB"
            ... + "  |  segments: " + string$(totalSegs)
            ... + "  |  norm=" + string$(normalize_output)
        
        Colour: "Black"
        Draw rectangle: 0, 1, 0, 1
        
        Font size: 10
        Line width: 1
    endif

    selectObject: resultID
    Play
    appendInfoLine: ""
    appendInfoLine: "== DONE: ", outputName$, " =="
    appendInfoLine: ""


