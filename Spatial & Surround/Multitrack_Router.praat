# ============================================================
# Praat AudioTools – Multitrack_Router.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 2.0 (2025)
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
#   ASSIGNMENT MODES (how sounds map to tracks):
#     1  All on track 1       2  One track per sound
#     3  Round-robin           4  Manual  (Assignments field)
#     5  Sequence per track   (Sequences field, | separates tracks,
#        tokens: sound indices + SILx silence markers)
#
#   ORDER MODES (within each track, modes 1-4):
#     1  Selection order   2  Alphabetical   3  Manual
#
#   TIMING:
#     All-at-0   – layered from t=0
#     Sequential – butt-join / gap / overlap with crossfade
#       Gap > 0 → silence;  Gap = 0 → butt;  Gap < 0 → overlap
#
#   PER-SOUND OVERRIDES:
#     Gains, fades, order, pan — space-separated in sentence
#     fields.  Blank = use default.
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
# STEP 1 – COMPACT FORM
# ============================================================

beginPause: "Multitrack Router v2.0  (" + string$(nSounds) + " sounds)"

    comment: "── ROUTING ──"
    natural: "Number of tracks", 2
    optionMenu: "Assignment mode", 1
        option: "All on track 1"
        option: "One track per sound"
        option: "Round-robin"
        option: "Manual  (→ Assignments)"
        option: "Sequence per track  (→ Sequences)"
    sentence: "Assignments", ""
    sentence: "Sequences", ""
    comment: "  Seq: indices + SILx, tracks separated by |"

    comment: "── ORDER  (modes 1-4) ──"
    optionMenu: "Order mode", 1
        option: "Selection order"
        option: "Alphabetical"
        option: "Manual  (→ Order field)"
    sentence: "Order", ""

    comment: "── TIMING ──"
    optionMenu: "Time mode", 2
        option: "All start at 0"
        option: "Sequential"
    real: "Gap seconds", 0.0
    real: "Crossfade seconds", 0.0
    optionMenu: "Crossfade shape", 1
        option: "Linear"
        option: "Equal power"

    comment: "── GAIN & FADES ──  (per-sound: space-sep, blank=default)"
    real: "Default gain dB", 0.0
    sentence: "Gains dB", ""
    real: "Fade in seconds", 0.01
    real: "Fade out seconds", 0.01
    sentence: "Fades in", ""
    sentence: "Fades out", ""

    comment: "── OUTPUT ──"
    optionMenu: "Output channels", 1
        option: "Mono  (sum all tracks)"
        option: "Stereo  (pan per track)"
        option: "Multichannel  (track per channel)"
    sentence: "Pan positions", ""
    comment: "  Pan: -1=L  0=center  1=R  (space-sep per track)"
    boolean: "Normalize output", 1
    boolean: "Print schedule", 1

clicked = endPause: "Cancel", "Run", 2, 1
if clicked = 1
    exitScript: "Cancelled."
endif

# ============================================================
# STEP 2 – PARSE & VALIDATE
# ============================================================

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

# Hardcoded thresholds
minDurForFade = 0.03

# --- Token splitter procedure ---

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

# --- Per-sound gains ---
for i from 1 to nSounds
    sndGain[i] = default_gain_dB
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

# --- Per-sound fades ---
for i from 1 to nSounds
    sndFadeIn[i]  = fade_in_seconds
    sndFadeOut[i] = fade_out_seconds
endfor
if fades_in$ <> ""
    @splitTokens: fades_in$
    nP = splitTokens.n
    if nP > nSounds
        nP = nSounds
    endif
    for i from 1 to nP
        sndFadeIn[i] = number(splitTokens.tok$[i])
        if sndFadeIn[i] < 0
            sndFadeIn[i] = 0
        endif
    endfor
endif
if fades_out$ <> ""
    @splitTokens: fades_out$
    nP = splitTokens.n
    if nP > nSounds
        nP = nSounds
    endif
    for i from 1 to nP
        sndFadeOut[i] = number(splitTokens.tok$[i])
        if sndFadeOut[i] < 0
            sndFadeOut[i] = 0
        endif
    endfor
endif

# --- Manual assignments (mode 4) ---
for i from 1 to nSounds
    sndTrackAssign[i] = 1
endfor
if assignment_mode = 4
    if assignments$ = ""
        exitScript: "Manual assignment mode requires the Assignments field "
            ... + "(space-separated track numbers, one per sound)."
    endif
    @splitTokens: assignments$
    if splitTokens.n < nSounds
        exitScript: "Assignments has " + string$(splitTokens.n)
            ... + " values, need " + string$(nSounds) + "."
    endif
    for i from 1 to nSounds
        sndTrackAssign[i] = number(splitTokens.tok$[i])
        if sndTrackAssign[i] < 1 or sndTrackAssign[i] > number_of_tracks
            exitScript: "Assignment for sound " + string$(i) + " = "
                ... + string$(sndTrackAssign[i])
                ... + "; must be 1.." + string$(number_of_tracks) + "."
        endif
    endfor
endif

# --- Manual order (order mode 3) ---
for i from 1 to nSounds
    sndOrderPos[i] = i
endfor
if order_mode = 3
    if order$ = ""
        exitScript: "Manual order mode requires the Order field "
            ... + "(space-separated position numbers)."
    endif
    @splitTokens: order$
    if splitTokens.n < nSounds
        exitScript: "Order has " + string$(splitTokens.n)
            ... + " values, need " + string$(nSounds) + "."
    endif
    for i from 1 to nSounds
        sndOrderPos[i] = number(splitTokens.tok$[i])
    endfor
endif

# --- Pan positions (for stereo output) ---
for t from 1 to 128
    trkPan[t] = 0.0
endfor
if output_channels = 2
    if pan_positions$ <> ""
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
    else
        # Auto-spread: if >1 track, spread L to R evenly
        if number_of_tracks > 1
            for t from 1 to number_of_tracks
                trkPan[t] = -1.0 + 2.0 * (t - 1) / (number_of_tracks - 1)
            endfor
        endif
    endif
endif

# ============================================================
# STEP 3 – BUILD SEGMENT LISTS PER TRACK
# ============================================================

maxSegs = nSounds * 4 + 200
for s from 1 to maxSegs
    segType[s]    = 0
    segSrc[s]     = 0
    segDur[s]     = 0.0
    segGainDB[s]  = 0.0
    segFdIn[s]    = 0.0
    segFdOut[s]   = 0.0
    segStart[s]   = 0.0
    segTrack[s]   = 0
endfor
totalSegs = 0

for t from 1 to number_of_tracks
    trkSegS[t] = 0
    trkSegN[t] = 0
endfor

clearinfo
writeInfoLine:  "=================================================="
writeInfoLine:  "  Multitrack Router v2.0"
writeInfoLine:  "=================================================="
appendInfoLine: ""
appendInfoLine: "Sounds : ", nSounds, "   Tracks : ", number_of_tracks,
    ... "   Fs : ", refFs, " Hz"
appendInfoLine: ""

# ............................................................
# MODE 5: Sequence per track  (pipe-separated token lists)
# ............................................................

if assignment_mode = 5

    # Split Sequences field by | into per-track strings
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
        # Trim
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
                        exitScript: "Bad silence token '" + token$
                            ... + "' on track " + string$(t) + "."
                    endif
                    segType[totalSegs]   = 0
                    segDur[totalSegs]    = sd
                    segGainDB[totalSegs] = 0
                    segFdIn[totalSegs]   = 0
                    segFdOut[totalSegs]  = 0
                else
                    ix = number(token$)
                    if ix = undefined or ix < 1 or ix > nSounds
                        exitScript: "Bad index '" + token$ + "' on track "
                            ... + string$(t) + ". Need 1.." + string$(nSounds) + "."
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

# ............................................................
# MODES 1–4
# ............................................................

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

    # Sort within each track
    for t from 1 to number_of_tracks
        n = trkN[t]
        if n > 1
            if order_mode = 2
                for pass from 1 to n - 1
                    for j from 1 to n - pass
                        if sndName$[trkSnd[t, j]] > sndName$[trkSnd[t, j + 1]]
                            swp = trkSnd[t, j]
                            trkSnd[t, j] = trkSnd[t, j + 1]
                            trkSnd[t, j + 1] = swp
                        endif
                    endfor
                endfor
            elsif order_mode = 3
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

# ============================================================
# STEP 4 – COMPUTE TIMING
# ============================================================

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
                    # Set crossfade envelopes at overlap boundary
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

# ============================================================
# STEP 5 – RENDER MONO TRACK STEMS
# ============================================================

appendInfoLine: "[2/3] Rendering..."
appendInfoLine: ""

for t from 1 to number_of_tracks
    s0 = trkSegS[t]
    nS = trkSegN[t]

    if nS = 0
        trkDur[t] = 0.001
        trkID[t] = Create Sound from formula: "mrt_trk_" + string$(t),
            ... 1, 0, 0.001, refFs, "0"
    else
        # Track total duration
        trkDur[t] = 0.0
        for j from 0 to nS - 1
            eT = segStart[s0 + j] + segDur[s0 + j]
            if eT > trkDur[t]
                trkDur[t] = eT
            endif
        endfor
        trkDur[t] = trkDur[t] + 0.0005

        appendInfoLine: "  Track ", t, ": ", nS, " segs  ",
            ... fixed$(trkDur[t], 3), " s"

        trkID[t] = Create Sound from formula: "mrt_trk_" + string$(t),
            ... 1, 0, trkDur[t], refFs, "0"

        for j from 0 to nS - 1
            sIdx = s0 + j
            if segType[sIdx] = 1
                srcI = segSrc[sIdx]

                # Copy + force mono + resample
                selectObject: sndID[srcI]
                sc = Copy: "mrt_sc"
                selectObject: sc
                nCh = Get number of channels
                if nCh > 1
                    scM = Extract one channel: 1
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

                # Gain
                gdb = segGainDB[sIdx]
                if gdb <> 0
                    selectObject: sc
                    glin = 10.0 ^ (gdb / 20.0)
                    Formula: "self * " + fixed$(glin, 8)
                endif

                # Fades (skip if segment too short)
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
                        foS$  = fixed$(fdO, 8)
                        dS$   = fixed$(sDur, 8)
                        foB$  = fixed$(sDur - fdO, 8)
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

                # Overlay onto track canvas
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
                    ... + " then self + Object_" + string$(sc)
                    ... + "[col - " + string$(off) + "]"
                    ... + " else self fi"

                removeObject: sc
            endif
        endfor
    endif
endfor

# ============================================================
# STEP 6 – COMBINE INTO SINGLE OUTPUT OBJECT
# ============================================================

appendInfoLine: ""
appendInfoLine: "[3/3] Building output..."

# Master duration = longest track
masterDur = 0.0
for t from 1 to number_of_tracks
    if trkDur[t] > masterDur
        masterDur = trkDur[t]
    endif
endfor

# --- OUTPUT MODE 1: MONO ---

if output_channels = 1
    outID = Create Sound from formula: "Routed_mono",
        ... 1, 0, masterDur, refFs, "0"
    for t from 1 to number_of_tracks
        selectObject: trkID[t]
        tNS = Get number of samples
        selectObject: outID
        Formula: "if col <= " + string$(tNS)
            ... + " then self + Object_" + string$(trkID[t]) + "[col]"
            ... + " else self fi"
    endfor
    appendInfoLine: "  Mono output: ", fixed$(masterDur, 3), " s"

# --- OUTPUT MODE 2: STEREO (equal-power pan) ---

elsif output_channels = 2
    outID = Create Sound from formula: "Routed_stereo",
        ... 2, 0, masterDur, refFs, "0"
    for t from 1 to number_of_tracks
        # Equal-power pan:  angle = (pan+1)/2 * pi/2
        # Left gain  = cos(angle)
        # Right gain = sin(angle)
        panAngle = (trkPan[t] + 1.0) / 2.0 * (pi / 2.0)
        gainL = cos(panAngle)
        gainR = sin(panAngle)
        gainL$ = fixed$(gainL, 8)
        gainR$ = fixed$(gainR, 8)

        selectObject: trkID[t]
        tNS = Get number of samples

        # Left channel (row = 1)
        selectObject: outID
        Formula: "if row = 1 and col <= " + string$(tNS)
            ... + " then self + " + gainL$
            ... + " * Object_" + string$(trkID[t]) + "[col]"
            ... + " else self fi"
        # Right channel (row = 2)
        selectObject: outID
        Formula: "if row = 2 and col <= " + string$(tNS)
            ... + " then self + " + gainR$
            ... + " * Object_" + string$(trkID[t]) + "[col]"
            ... + " else self fi"
    endfor
    appendInfoLine: "  Stereo output: ", fixed$(masterDur, 3), " s"
    for t from 1 to number_of_tracks
        appendInfoLine: "    Track ", t, "  pan=",
            ... fixed$(trkPan[t], 2), "  (L=",
            ... fixed$(cos((trkPan[t]+1)/2*(pi/2)), 3), " R=",
            ... fixed$(sin((trkPan[t]+1)/2*(pi/2)), 3), ")"
    endfor

# --- OUTPUT MODE 3: MULTICHANNEL (one channel per track) ---

else
    outID = Create Sound from formula: "Routed_multi",
        ... number_of_tracks, 0, masterDur, refFs, "0"
    for t from 1 to number_of_tracks
        selectObject: trkID[t]
        tNS = Get number of samples
        selectObject: outID
        Formula: "if row = " + string$(t) + " and col <= " + string$(tNS)
            ... + " then self + Object_" + string$(trkID[t]) + "[col]"
            ... + " else self fi"
    endfor
    appendInfoLine: "  Multichannel output: ", number_of_tracks,
        ... " ch, ", fixed$(masterDur, 3), " s"
endif

# --- Normalize ---
if normalize_output = 1
    selectObject: outID
    pk = Get absolute extremum: 0, 0, "None"
    if pk > 0.001
        Scale peak: 0.99
    endif
    appendInfoLine: "  Normalized (peak was ", fixed$(pk, 4), ")"
endif

# --- Clipping report ---
selectObject: outID
pkFinal = Get absolute extremum: 0, 0, "None"
appendInfoLine: "  Final peak: ", fixed$(pkFinal, 4)

# ============================================================
# STEP 7 – CLEANUP TRACK STEMS
# ============================================================

for t from 1 to number_of_tracks
    removeObject: trkID[t]
endfor

# ============================================================
# STEP 8 – SCHEDULE
# ============================================================

if print_schedule = 1
    appendInfoLine: ""
    appendInfoLine: "=================================================="
    appendInfoLine: "  SCHEDULE"
    appendInfoLine: "=================================================="
    appendInfoLine: ""
    appendInfoLine: "Seg | Trk | Type    | Src | Start     | End       | Gain  | FdIn   | FdOut"
    appendInfoLine: "--- | --- | ------- | --- | --------- | --------- | ----- | ------ | ------"
    for s from 1 to totalSegs
        eT = segStart[s] + segDur[s]
        if segType[s] = 1
            tp$ = "AUDIO  "
            sr$ = left$(string$(segSrc[s]) + "   ", 3)
            nm$ = "  (" + sndName$[segSrc[s]] + ")"
        else
            tp$ = "SILENCE"
            sr$ = " - "
            nm$ = ""
        endif
        appendInfoLine:
            ... left$(string$(s) + "   ", 3),
            ... " | ",
            ... left$(string$(segTrack[s]) + "   ", 3),
            ... " | ", tp$,
            ... " | ", sr$,
            ... " | ", left$(fixed$(segStart[s], 4) + "         ", 9),
            ... " | ", left$(fixed$(eT, 4) + "         ", 9),
            ... " | ", left$(fixed$(segGainDB[s], 1) + "     ", 5),
            ... " | ", left$(fixed$(segFdIn[s], 3) + "      ", 6),
            ... " | ", fixed$(segFdOut[s], 3),
            ... nm$
    endfor
endif

# ============================================================
# SELECT OUTPUT & DONE
# ============================================================

selectObject: outID

appendInfoLine: ""
appendInfoLine: "=================================================="
appendInfoLine: "  COMPLETE"
appendInfoLine: "=================================================="
selectObject: outID
outName$ = selected$("Sound")
appendInfoLine: "Output: ", outName$
appendInfoLine: ""
