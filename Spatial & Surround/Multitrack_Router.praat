# ============================================================
# Praat AudioTools – Multitrack_Router.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 3.2 (2025)
# License: MIT License
#
# Description:
#   Form-driven multitrack routing and time-placement engine.
#   Select N Sound objects, assign them to virtual tracks,
#   sequence / reorder them, insert silences, apply gain +
#   fades, and render a single output Sound object:
#     Mono          – all tracks summed to 1 channel
#     Stereo        – tracks panned L/R via equal-power law
#     Multichannel  – one channel per track
#
#   ASSIGNMENT MODES:
#     1  All on track 1       2  One track per sound
#     3  Round-robin           4  Manual (Assignments)
#     5  Sequence per track   (Sequences field, | separates
#        tracks, tokens: indices + SILx silence markers)
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
#     xf:lin          crossfade shape (lin or ep)
#     sched           print schedule to Info
#     Example: "g:-3 0 -6 ch:0 2 pan:-1 1 xf:ep sched"
#
#   PRESETS:
#     1 Custom  2 Sequential Chain  3 Crossfade Montage
#     4 Stereo Spread  5 Layered Stack  6 Dialogue Assembly
#     7 Multichannel Split
#
# Requires: Praat ≥ 6.0
# Category: Routing / Mixing / Composition
# ============================================================

# ============================================================
# STEP 0 – READ ALL SELECTED SOUNDS
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
endfor

refFs = sndFs[1]
for i from 2 to nSounds
    if sndFs[i] > refFs
        refFs = sndFs[i]
    endif
endfor

# ============================================================
# STEP 1 – COMPACT FORM WITH APPLY LOOP
# ============================================================

v_preset     = 1
v_tracks     = 2
v_assign     = 1
v_sequences$ = ""
v_time       = 2
v_gap        = 0.0
v_xfade      = 0.0
v_gain       = 0.0
v_fadein     = 0.01
v_fadeout    = 0.01
v_output     = 1
v_over$      = ""
v_norm       = 1
v_draw       = 1
prevResultID = 0

# ---- Token splitter (used throughout) ----
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

repeat

    beginPause: "Multitrack Router  (" + string$(nSounds) + " sounds)"
        optionMenu: "Preset", v_preset
            option: "Custom"
            option: "Sequential Chain"
            option: "Crossfade Montage"
            option: "Stereo Spread"
            option: "Layered Stack"
            option: "Dialogue Assembly"
            option: "Multichannel Split"
        natural: "Tracks", v_tracks
        optionMenu: "Assignment", v_assign
            option: "All on track 1"
            option: "One track per sound"
            option: "Round-robin"
            option: "Manual  (→ Seq field)"
            option: "Sequence  (→ Seq field)"
        sentence: "Seq", v_sequences$
        optionMenu: "Timing", v_time
            option: "All at 0  (layer)"
            option: "Sequential"
        real: "Gap s", v_gap
        real: "Crossfade s", v_xfade
        real: "Gain dB", v_gain
        real: "Fade in s", v_fadein
        real: "Fade out s", v_fadeout
        optionMenu: "Output", v_output
            option: "Mono"
            option: "Stereo"
            option: "Multichannel"
        sentence: "Overrides", v_over$
        boolean: "Normalize", v_norm
        boolean: "Visualize", v_draw
    clicked = endPause: "Close", "Apply", 2, 1

    v_preset     = preset
    v_tracks     = tracks
    v_assign     = assignment
    v_sequences$ = seq$
    v_time       = timing
    v_gap        = gap_s
    v_xfade      = crossfade_s
    v_gain       = gain_dB
    v_fadein     = fade_in_s
    v_fadeout    = fade_out_s
    v_output     = output
    v_over$      = overrides$
    v_norm       = normalize
    v_draw       = visualize

    if clicked = 1
        exitScript: "Closed."
    endif

    # Remove previous result before building new one
    if prevResultID > 0
        removeObject: prevResultID
        prevResultID = 0
    endif

    # ========================================================
    # APPLY: PROCESS
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
    draw_visualization = visualize

    # Defaults for override-only params
    crossfade_shape   = 2
    print_schedule    = 0
    order_mode        = 1
    gains_dB$         = ""
    channel_select$   = ""
    pan_positions$    = ""
    order$            = ""

    # ---- Parse Overrides field ----
    # Tags: g: ch: pan: ord: xf: sched
    ovr$ = overrides$
    # Append space sentinel
    ovr$ = ovr$ + " "

    # g: per-sound gains
    gPos = index(ovr$, "g:")
    if gPos > 0
        gSub$ = mid$(ovr$, gPos + 2)
        gEnd = index(gSub$, ":")
        if gEnd > 0
            # walk back to find tag start
            gEnd2 = gEnd - 1
            while gEnd2 > 1 and mid$(gSub$, gEnd2, 1) <> " "
                gEnd2 = gEnd2 - 1
            endwhile
            gains_dB$ = left$(gSub$, gEnd2)
        else
            gains_dB$ = gSub$
        endif
        # Trim trailing spaces
        while length(gains_dB$) > 0 and right$(gains_dB$, 1) = " "
            gains_dB$ = left$(gains_dB$, length(gains_dB$) - 1)
        endwhile
    endif

    # ch: channel select
    chPos = index(ovr$, "ch:")
    if chPos > 0
        chSub$ = mid$(ovr$, chPos + 3)
        chEnd = index(chSub$, ":")
        if chEnd > 0
            chEnd2 = chEnd - 1
            while chEnd2 > 1 and mid$(chSub$, chEnd2, 1) <> " "
                chEnd2 = chEnd2 - 1
            endwhile
            channel_select$ = left$(chSub$, chEnd2)
        else
            channel_select$ = chSub$
        endif
        while length(channel_select$) > 0 and right$(channel_select$, 1) = " "
            channel_select$ = left$(channel_select$, length(channel_select$) - 1)
        endwhile
    endif

    # pan: positions
    pPos = index(ovr$, "pan:")
    if pPos > 0
        pSub$ = mid$(ovr$, pPos + 4)
        pEnd = index(pSub$, ":")
        if pEnd > 0
            pEnd2 = pEnd - 1
            while pEnd2 > 1 and mid$(pSub$, pEnd2, 1) <> " "
                pEnd2 = pEnd2 - 1
            endwhile
            pan_positions$ = left$(pSub$, pEnd2)
        else
            pan_positions$ = pSub$
        endif
        while length(pan_positions$) > 0 and right$(pan_positions$, 1) = " "
            pan_positions$ = left$(pan_positions$, length(pan_positions$) - 1)
        endwhile
    endif

    # ord: manual order
    oPos = index(ovr$, "ord:")
    if oPos > 0
        order_mode = 3
        oSub$ = mid$(ovr$, oPos + 4)
        oEnd = index(oSub$, ":")
        if oEnd > 0
            oEnd2 = oEnd - 1
            while oEnd2 > 1 and mid$(oSub$, oEnd2, 1) <> " "
                oEnd2 = oEnd2 - 1
            endwhile
            order$ = left$(oSub$, oEnd2)
        else
            order$ = oSub$
        endif
        while length(order$) > 0 and right$(order$, 1) = " "
            order$ = left$(order$, length(order$) - 1)
        endwhile
    endif

    # xf: crossfade shape
    xfPos = index(ovr$, "xf:")
    if xfPos > 0
        xfSub$ = mid$(ovr$, xfPos + 3, 3)
        if left$(xfSub$, 3) = "lin"
            crossfade_shape = 1
        else
            crossfade_shape = 2
        endif
    endif

    # sched flag
    scPos = index(ovr$, "sched")
    if scPos > 0
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
    assignName$[1] = "All→1"
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

    # ---- Build segment lists ----
    maxSegs = nSounds * 4 + 200
    for s from 1 to maxSegs
        segType[s]   = 0
        segSrc[s]    = 0
        segDur[s]    = 0.0
        segGainDB[s] = 0.0
        segFdIn[s]   = 0.0
        segFdOut[s]  = 0.0
        segStart[s]  = 0.0
        segTrack[s]  = 0
    endfor
    totalSegs = 0
    for t from 1 to number_of_tracks
        trkSegS[t] = 0
        trkSegN[t] = 0
    endfor

    clearinfo
    writeInfoLine:  "=================================================="
    writeInfoLine:  "  Multitrack Router v3.2  ·  ", presetName$[preset]
    writeInfoLine:  "=================================================="
    appendInfoLine: ""
    appendInfoLine: nSounds, " sounds → ", number_of_tracks, " tracks  ",
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

    # ---- MODES 1–4 ----
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

        # Sort
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
                        endif
                        if crossfade_seconds > 0
                            if segType[prev] = 1
                                segFdOut[prev] = crossfade_seconds
                            endif
                            if segType[cur] = 1
                                segFdIn[cur] = crossfade_seconds
                            endif
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
                        if fdI > 0.0001
                            selectObject: sc
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
                        endif
                        if fdO > 0.0001
                            selectObject: sc
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
                        endif
                    endif

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
                    off = s1 - 1
                    selectObject: trkID[t]
                    Formula: "if col >= " + string$(s1)
                        ... + " and col <= " + string$(s2)
                        ... + " then self + object[" + string$(sc)
                        ... + ", col - " + string$(off) + "]"
                        ... + " else self fi"
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

    # ---- Visualization ----
    if draw_visualization = 1
        Erase all

        # Title
        Select outer viewport: 0, 8, 0, 0.38
        Axes: 0, 1, 0, 1
        Font size: 10
        Colour: "Black"
        Text: 0.5, "centre", 0.7, "half", "##Multitrack Router##"
        Font size: 7
        Colour: "{0.35, 0.35, 0.45}"
        Text: 0.5, "centre", -0.1, "half",
            ... presetName$[preset] + "  |  "
            ... + string$(nSounds) + " snd → "
            ... + string$(number_of_tracks) + " trk  " + outModeName$

        # Panel 1: Track timeline
        nTrkVis = number_of_tracks
        if nTrkVis > 8
            nTrkVis = 8
        endif
        panelH = 0.25 * nTrkVis + 0.30
        if panelH < 0.80
            panelH = 0.80
        endif
        if panelH > 2.50
            panelH = 2.50
        endif
        p1top = 0.42
        p1bot = p1top + panelH

        Select outer viewport: 0, 8, p1top, p1bot
        Select inner viewport: 0.55, 7.65, p1top + 0.06, p1bot - 0.06
        yTop = nTrkVis + 1

        globalEnd = 0.001
        for s from 1 to totalSegs
            eT = segStart[s] + segDur[s]
            if eT > globalEnd
                globalEnd = eT
            endif
        endfor
        globalEnd = globalEnd * 1.02

        Axes: 0, globalEnd, 0, yTop
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, globalEnd, 0, yTop
        Colour: "{0.85, 0.85, 0.85}"
        for t from 1 to nTrkVis
            yLane = nTrkVis + 1 - t
            Draw line: 0, yLane, globalEnd, yLane
        endfor
        Font size: 6
        Colour: "{0.45, 0.45, 0.55}"
        for t from 1 to nTrkVis
            yMid = nTrkVis + 1 - t + 0.5
            Text: -globalEnd * 0.005, "right", yMid, "half", "T" + string$(t)
        endfor

        nSndM1 = nSounds - 1
        if nSndM1 < 1
            nSndM1 = 1
        endif
        for s from 1 to totalSegs
            t = segTrack[s]
            if t <= nTrkVis
                yB = nTrkVis + 1 - t + 0.08
                yT = nTrkVis + 1 - t + 0.92
                x1 = segStart[s]
                x2 = segStart[s] + segDur[s]
                if segType[s] = 1
                    srcI = segSrc[s]
                    frac = (srcI - 1) / nSndM1
                    cR = 0.28 + frac * 0.55
                    cG = 0.52 - frac * 0.18
                    cB = 0.72 - frac * 0.50
                    clr$ = "{" + fixed$(cR, 2) + "," + fixed$(cG, 2) + "," + fixed$(cB, 2) + "}"
                    Paint rectangle: clr$, x1, x2, yB, yT
                    if (x2 - x1) > globalEnd * 0.03
                        Font size: 5
                        Colour: "White"
                        Text: (x1 + x2) / 2, "centre", (yB + yT) / 2, "half", string$(srcI)
                    endif
                else
                    Paint rectangle: "{0.92, 0.90, 0.85}", x1, x2, yB, yT
                    Colour: "{0.70, 0.68, 0.60}"
                    Draw rectangle: x1, x2, yB, yT
                endif
            endif
        endfor
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text top: "no", "Track timeline"
        Text bottom: "yes", "Time (s)"

        # Panel 2: Output waveform
        p2top = p1bot + 0.08
        p2bot = p2top + 0.80
        Select outer viewport: 0, 8, p2top, p2bot
        Select inner viewport: 0.55, 7.65, p2top + 0.05, p2bot - 0.05
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
        selectObject: resultID
        Colour: "{0.20, 0.72, 0.48}"
        Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Out"
        Text top: "no", outputName$
        Text bottom: "yes", "Time (s)"

        # Panel 3: Summary bar
        p3top = p2bot + 0.06
        p3bot = p3top + 0.44
        Select outer viewport: 0, 8, p3top, p3bot
        Select inner viewport: 0.55, 7.65, p3top + 0.03, p3bot - 0.03
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
        Font size: 6
        Colour: "{0.30, 0.30, 0.40}"
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
        Text: 0.02, "left", 0.72, "half",
            ... "##" + presetName$[preset] + "##  "
            ... + assignName$[assignment_mode] + "  "
            ... + tLbl$ + "  gap=" + fixed$(gap_seconds, 3)
            ... + " xf=" + fixed$(crossfade_seconds, 3)
            ... + "(" + xLbl$ + ")"
        Text: 0.02, "left", 0.25, "half",
            ... outModeName$ + "  "
            ... + fixed$(resultDur, 3) + "s  "
            ... + "pk=" + fixed$(pkFinal, 4) + "  "
            ... + "gain=" + fixed$(default_gain_dB, 1)
            ... + " fade=" + fixed$(fade_in_seconds, 3) + "/" + fixed$(fade_out_seconds, 3)
        Colour: "Black"
        Draw rectangle: 0, 1, 0, 1

        Font size: 10
        Line width: 1
    endif

    # ---- Schedule ----
    if print_schedule = 1
        appendInfoLine: ""
        appendInfoLine: "== SCHEDULE =="
        appendInfoLine: "Seg|Trk|Type   |Src|Start   |End     |Gain|FdIn |FdOut"
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

    selectObject: resultID
    appendInfoLine: ""
    appendInfoLine: "== DONE: ", outputName$, " =="
    appendInfoLine: ""

    prevResultID = resultID

until 0
