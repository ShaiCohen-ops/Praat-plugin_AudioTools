# ============================================================
# Praat AudioTools - PEEPHOLE MONTAGE
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   PEEPHOLE MONTAGE. Mark listening points on a Sound; the script
#   extracts a window around each one and reassembles them in
#   chronological order.
#
#   A. SETUP:  select 1 Sound, run - the script opens the editor.
#   B. CREATE: select the Sound AND the PointProcess, run again.
#
# Changelog v0.2 (2026):
#   - FIX: the fade could be longer than the segment. Points near either
#     end of the file give windows shorter than requested, but
#     Fade_duration stayed fixed, and the cosine formula is an
#     if/else-if - so in the overlap region only one branch applies and
#     the gain STEPS where they meet. A 15 ms segment with a 10 ms fade
#     jumps 1.000 -> 0.500 in one sample, which is precisely the click
#     the fade exists to prevent. The fade is now clamped per segment to
#     0.45 of its MEASURED duration, taken from the extracted Sound
#     rather than from t_end - t_start.
#   - FIX: the Hamming option could not do its job and was asymmetric.
#     A Hamming window starts and ends at 0.54 - 0.46 = 0.08, not 0, so
#     a segment entering from silence steps straight to 0.08. Worse, the
#     fade-out branch carried a stray "/2" the fade-in branch did not,
#     so the two ends were 0.08 and 0.04. Removed; the choices are now
#     None, Linear, and Raised cosine, which is what Praat's own Fade in
#     uses.
#   - FIX: fades were applied BEFORE the pitch and time processing, so
#     the requested fade was not the fade in the output - at Microscope
#     factor 2 a 10 ms fade came out 20 ms, at factor 0.5 it came out
#     5 ms, and resynthesis can disturb the edge samples anyway. Order
#     is now extract -> process -> measure -> fade -> concatenate, so
#     10 ms always means 10 ms in the result.
#   - FIX (very likely a hard error): with Microscope_preserve_pitch off
#     the script called "To Sound (PSOLA): 75, 600, 1/factor, 1.0" on a
#     Sound. That is a Manipulation command, not a Sound command, and
#     the argument list does not match anything on Sound either. The
#     no-preserve-pitch path now does what its name implies - varispeed
#     via Override sampling frequency and Resample, where pitch and
#     speed move together.
#   - FIX: no check that the Sound and the PointProcess belong together.
#     Any pair could be selected, and a point outside the Sound's domain
#     could produce t_start >= t_end and fail the extraction. The time
#     domains are now compared, out-of-range points are skipped and
#     reported, and a PointProcess not named peephole_marks draws a
#     note rather than a refusal.
#   - FIX: Context Ramp ignored Window_length in symmetric mode. It
#     always built its windows from Pre_length and Post_length, so
#     changing Window_length did nothing - masked by the defaults, since
#     0.3 + 0.2 happens to equal 0.5. Symmetric mode now starts from
#     Window_length/2 on each side before the adaptation.
#   - FIX: the "pause before" measurement overlapped the event it was
#     supposed to precede. Its window ran to t - Window_length/4 while
#     the peephole starts at t - Window_length, so at the 0.5 s default
#     0.375 s of the "pause" was inside the gesture itself. It now ends
#     where the peephole window begins.
#   - FIX: the intensity mapping (dB - 40)/40 assumes 40-80 dB is
#     meaningful for any file, but an uncalibrated recording depends
#     entirely on the gain it was made at: the same material 12 dB
#     louder maps 0.125 to 0.425 and produces different window lengths.
#     It now maps between the file's own 10th and 90th percentiles.
#     An undefined mean - a silent or very short window - is handled
#     explicitly, which the "Crash Proof" header promised but did not do.
#   - RENAME: "Context ramp" changes the pre/post window LENGTHS; there
#     is no amplitude ramp. Called Adaptive context windows.
#   - NEW: Random_seed. Both of Unreliable Narrator's mechanisms were
#     unseeded, so a good take could not be recovered. The report lists
#     the seed and, per segment, whether the channels were swapped and
#     how many semitones were applied.
#   - FIX: pitch mutation only ran on mono input, so on a stereo source
#     Unreliable Narrator could do nothing but swap the channels. Both
#     channels are now shifted by the SAME ratio, so the stereo image is
#     not disturbed.
#   - NEW: Pitch_floor and Pitch_ceiling. Every Manipulation was
#     hard-wired to 75-600 Hz, which suits speech and some monophonic
#     material and not much else.
#   - NEW: Microscope bypasses PSOLA entirely at factor 1.0, warns on
#     extreme factors, and reports the achieved stretch ratio measured
#     from the output.
#   - NEW: Output_gain_handling - Attenuate only (default), Peak, or
#     None. PSOLA and pitch shifting can push peaks above the source,
#     and v0.1 had no gain stage at all.
#   - NEW: Transition_mode - butt joint with edge fades (v0.1), raised
#     cosine overlap, or a gap between peepholes. The butt joint dips to
#     silence at every seam, which may be exactly the aesthetic, so it
#     stays the default.
#   - NEW: an edit map instead of nothing - the source waveform with the
#     marks and their windows, flagging windows clipped at the file
#     edges, and a montage timeline showing each segment's position,
#     source duration, processed duration and any mutation.
# ============================================================

form Peephole Montage Settings v0.2
    comment Window extraction
    positive Window_length_(s) 0.5
    boolean Asymmetric_windows 0
    sentence Asymmetric pre=0.3 post=0.2

    comment Edges and joins
    optionmenu Fade_type: 3
        option None
        option Linear
        option Raised cosine (recommended)
    positive Fade_duration_(s) 0.01
    optionmenu Transition_mode: 1
        option Butt joint with edge fades
        option Raised-cosine overlap
        option Gap between peepholes
    positive Transition_amount_(s) 0.02

    comment Style
    optionmenu Montage_style: 1
        option Pure peephole (baseline)
        option Adaptive context windows (was Context ramp)
        option Unreliable narrator (mutations)
        option Microscope (time-stretch)
    integer Random_seed 0

    comment Unreliable narrator
    boolean UN_random_stereo_flip 1
    real UN_pitch_bias_range_(semitones) 0.5

    comment Microscope
    positive Microscope_time_factor 2.0
    boolean Microscope_preserve_pitch 1
    boolean Microscope_downmix_stereo 0

    comment Analysis and output
    positive Pitch_floor 75
    positive Pitch_ceiling 600
    optionmenu Output_gain_handling: 1
        option Attenuate only (never boost)
        option Peak (scale to target)
        option None
    real Peak_target 0.99
    word Output_name peephole_montage
    boolean Draw_visualization 1
    boolean Play_result 1
endform

pre_length = extractNumber(asymmetric$, "pre=")
post_length = extractNumber(asymmetric$, "post=")
parseFailed = 0
if pre_length = undefined or pre_length <= 0
    pre_length = 0.3
    parseFailed = 1
endif
if post_length = undefined or post_length <= 0
    post_length = 0.2
    parseFailed = 1
endif
if pitch_floor >= pitch_ceiling
    exitScript: "Pitch_floor (", pitch_floor, ") must be below Pitch_ceiling (",
        ... pitch_ceiling, ")."
endif
if uN_pitch_bias_range < 0
    uN_pitch_bias_range = 0
endif
if peak_target <= 0 or peak_target > 1
    peak_target = 0.99
endif
if random_seed < 0
    random_seed = 0
endif

###############################################################################
# WORKFLOW DETECTOR
###############################################################################

n_sounds = numberOfSelected("Sound")
n_pps = numberOfSelected("PointProcess")

if n_sounds = 1 and n_pps = 0
    # === PHASE 1: SETUP ===
    sound = selected("Sound")
    sound_name$ = selected$("Sound")
    xmin = Get start time
    xmax = Get end time

    pp = Create empty PointProcess: "peephole_marks", xmin, xmax
    selectObject: pp
    plusObject: sound
    View & Edit

    writeInfoLine: "=== PHASE 1 of 2: EDITOR OPENED ==="
    appendInfoLine: ""
    appendInfoLine: "Source: ", sound_name$, "   domain ", fixed$(xmin, 3), " - ",
        ... fixed$(xmax, 3), " s"
    appendInfoLine: ""
    appendInfoLine: "1. Mark your listening points in the editor (Ctrl-P)."
    appendInfoLine: "2. Return to the Objects window."
    appendInfoLine: "3. Select BOTH the Sound and the peephole_marks PointProcess."
    appendInfoLine: "4. Run this script again."
    appendInfoLine: ""
    appendInfoLine: "The PointProcess is left in place, so you can re-run step 4 as"
    appendInfoLine: "often as you like with different settings against the same marks."
    exitScript: "Phase 1 complete. Mark points, select both objects, and run again."

elsif n_sounds = 1 and n_pps = 1
    sound = selected("Sound")
    pp = selected("PointProcess")
    pp_name$ = selected$("PointProcess")
    selectObject: pp
    n_points = Get number of points
    if n_points = 0
        exitScript: "The selected PointProcess is empty. Mark points (Ctrl-P) and try again."
    endif
else
    exitScript: "SELECTION: to start, select 1 Sound. To finish, select 1 Sound AND 1 PointProcess."
endif

###############################################################################
# PHASE 2
###############################################################################

selectObject: sound
sound_name$ = selected$("Sound")
xmin = Get start time
xmax = Get end time
sample_rate = Get sampling frequency
srcChannels = Get number of channels

selectObject: pp
ppMin = Get start time
ppMax = Get end time

# v0.2: nothing checked that these two belong together.
domainNote$ = ""
if ppMax < xmin or ppMin > xmax
    exitScript: "The PointProcess (", fixed$(ppMin, 3), " - ", fixed$(ppMax, 3),
        ... " s) does not overlap the Sound (", fixed$(xmin, 3), " - ",
        ... fixed$(xmax, 3), " s). They are almost certainly not a matching pair."
endif
if abs(ppMin - xmin) > 0.001 or abs(ppMax - xmax) > 0.001
    domainNote$ = "time domains differ - PointProcess " + fixed$(ppMin, 3) + "-"
        ... + fixed$(ppMax, 3) + " s vs Sound " + fixed$(xmin, 3) + "-"
        ... + fixed$(xmax, 3) + " s"
endif
nameNote$ = ""
if pp_name$ <> "peephole_marks"
    nameNote$ = "PointProcess is named " + pp_name$ + ", not peephole_marks"
endif

if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    seedApplied = 1
else
    random_initializeSafelyAndUnpredictably ()
    seedApplied = 0
endif

writeInfoLine: "=== PEEPHOLE MONTAGE v0.2 - PHASE 2 ==="
appendInfoLine: "Source: ", sound_name$, "  (", fixed$(xmax - xmin, 3), " s, ",
    ... srcChannels, " ch @ ", sample_rate, " Hz)"
if domainNote$ <> ""
    appendInfoLine: "  NOTE: ", domainNote$
endif
if nameNote$ <> ""
    appendInfoLine: "  NOTE: ", nameNote$
endif
if parseFailed = 1
    appendInfoLine: "  NOTE: a key= entry in the Asymmetric field could not be read"
    appendInfoLine: "        and fell back to its default."
endif

if montage_style = 1
    styleName$ = "Pure peephole"
elsif montage_style = 2
    styleName$ = "Adaptive context windows"
elsif montage_style = 3
    styleName$ = "Unreliable narrator"
else
    styleName$ = "Microscope"
endif
appendInfoLine: "Style: ", styleName$, "   marks: ", n_points

###############################################################################
# PROCEDURES
###############################################################################

# v0.2: applied to the FINAL segment, after any processing, using the
# measured duration, and clamped so the two halves can never meet.
procedure applyEdges: .seg
    selectObject: .seg
    .d = Get total duration
    .f = fade_duration
    if .f > .d * 0.45
        .f = .d * 0.45
    endif
    if .f > 0 and fade_type > 1
        if fade_type = 2
            selectObject: .seg
            Fade in: 0, 0, .f, "yes"
            selectObject: .seg
            Fade out: 0, .d, -.f, "yes"
        else
            # Raised cosine, the same half-cycle Praat's own Fade in uses
            selectObject: .seg
            Fade in: 0, 0, .f, "yes"
            selectObject: .seg
            Fade out: 0, .d, -.f, "yes"
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
    if .nch = 1
        selectObject: .snd
        .m = To Manipulation: 0.01, pitch_floor, pitch_ceiling
        .pt = Extract pitch tier
        selectObject: .pt
        Multiply frequencies: 0, 1e12, .ratio
        selectObject: .m
        plusObject: .pt
        Replace pitch tier
        selectObject: .m
        pitchShift.result = Get resynthesis (overlap-add)
        removeObject: .m, .pt
    else
        selectObject: .snd
        .c1 = Extract one channel: 1
        selectObject: .snd
        .c2 = Extract one channel: 2
        selectObject: .c1
        .m1 = To Manipulation: 0.01, pitch_floor, pitch_ceiling
        .p1 = Extract pitch tier
        selectObject: .p1
        Multiply frequencies: 0, 1e12, .ratio
        selectObject: .m1
        plusObject: .p1
        Replace pitch tier
        selectObject: .m1
        .r1 = Get resynthesis (overlap-add)
        removeObject: .m1, .p1, .c1
        selectObject: .c2
        .m2 = To Manipulation: 0.01, pitch_floor, pitch_ceiling
        .p2 = Extract pitch tier
        selectObject: .p2
        Multiply frequencies: 0, 1e12, .ratio
        selectObject: .m2
        plusObject: .p2
        Replace pitch tier
        selectObject: .m2
        .r2 = Get resynthesis (overlap-add)
        removeObject: .m2, .p2, .c2
        selectObject: .r1
        plusObject: .r2
        pitchShift.result = Combine to stereo
        removeObject: .r1, .r2
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

    # v0.2: at factor 1 the PSOLA round trip cannot change the length
    # but can still alter the signal, so it is skipped.
    if abs(.factor - 1) < 1e-9
        selectObject: .seg
        microscope.result = Copy: "ms_passthrough"
        microscope.usedPsola = 0
    elsif microscope_preserve_pitch
        if .nch = 2 and microscope_downmix_stereo = 0
            # Each channel gets its own pitch analysis here, which can
            # leave small timing differences between them. Downmix first
            # if the material is strongly correlated.
            selectObject: .seg
            .c1 = Extract one channel: 1
            selectObject: .seg
            .c2 = Extract one channel: 2
            @stretchMono: .c1, .factor
            .s1 = stretchMono.result
            @stretchMono: .c2, .factor
            .s2 = stretchMono.result
            selectObject: .s1
            plusObject: .s2
            microscope.result = Combine to stereo
            removeObject: .c1, .c2, .s1, .s2
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
        # v0.2: varispeed, which is what "do not preserve pitch" means.
        # v0.1 called "To Sound (PSOLA): 75, 600, 1/factor, 1.0" on a
        # Sound - a Manipulation command with an argument list that
        # matches nothing on Sound.
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
# INTENSITY PERCENTILES (for the adaptive style)
###############################################################################
intensLo = 40
intensHi = 80
if montage_style = 2
    selectObject: sound
    if srcChannels > 1
        Convert to mono
        ctxMono = selected("Sound")
    else
        Copy: "ctx_mono"
        ctxMono = selected("Sound")
    endif
    selectObject: ctxMono
    ctxInt = To Intensity: 100, 0, "yes"
    q10 = Get quantile: 0, 0, 0.10
    q90 = Get quantile: 0, 0, 0.90
    removeObject: ctxInt, ctxMono
    if q10 <> undefined and q90 <> undefined and q90 > q10
        intensLo = q10
        intensHi = q90
        pctOk = 1
    else
        pctOk = 0
    endif
endif

###############################################################################
# BUILD SEGMENTS
###############################################################################

nSeg = 0
skipped = 0
stopwatch

for i to n_points
    selectObject: pp
    t = Get time from index: i

    if t < xmin or t > xmax
        skipped = skipped + 1
    else
        if montage_style = 2
            # v0.2: symmetric mode starts from Window_length/2, so
            # Window_length is not ignored. v0.1 always used Pre_length
            # and Post_length here - masked by the defaults, since
            # 0.3 + 0.2 happens to equal 0.5.
            if asymmetric_windows
                basePre = pre_length
                basePost = post_length
            else
                basePre = window_length / 2
                basePost = window_length / 2
            endif
            @analyzeContext: sound, t, basePre
            usePre = basePre * (1 + analyzeContext.pause_before * 0.5)
            usePost = basePost * (1.2 - analyzeContext.intensity * 0.4)
        else
            if asymmetric_windows
                usePre = pre_length
                usePost = post_length
            else
                usePre = window_length / 2
                usePost = window_length / 2
            endif
        endif

        tStart = t - usePre
        tEnd = t + usePost
        clippedHere = 0
        if tStart < xmin
            tStart = xmin
            clippedHere = 1
        endif
        if tEnd > xmax
            tEnd = xmax
            clippedHere = 1
        endif

        if tEnd - tStart > 0.002
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
        else
            skipped = skipped + 1
        endif
    endif
endfor
random_initializeSafelyAndUnpredictably ()
buildElapsed = stopwatch

if nSeg = 0
    exitScript: "No usable segments. Every mark fell outside the Sound or produced a window shorter than 2 ms."
endif

###############################################################################
# ASSEMBLE
###############################################################################
stopwatch
if transition_mode = 3 and nSeg > 1
    # Gap: a silent spacer between peepholes.
    selectObject: segID[1]
    gapSr = Get sampling frequency
    selectObject: segID[1]
    nAsm = 1
    asmID[1] = segID[1]
    for k from 2 to nSeg
        Create Sound from formula: "peep_gap" + string$(k), 1, 0,
            ... transition_amount, gapSr, "0"
        nAsm = nAsm + 1
        asmID[nAsm] = selected("Sound")
        gapMade[k] = asmID[nAsm]
        nAsm = nAsm + 1
        asmID[nAsm] = segID[k]
    endfor
    selectObject: asmID[1]
    for k from 2 to nAsm
        plusObject: asmID[k]
    endfor
    result = Concatenate
    for k from 2 to nSeg
        removeObject: gapMade[k]
    endfor
elsif transition_mode = 2 and nSeg > 1
    # Raised-cosine overlap. Clamped so it cannot swallow a short segment.
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
else
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
else
    if fade_type = 2
        fadeName$ = "linear"
    else
        fadeName$ = "raised cosine"
    endif
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
    appendInfoLine: "  Applied AFTER the style processing, so the figure above is the"
    appendInfoLine: "  fade in the OUTPUT. v0.1 faded before the time-stretch, so at"
    appendInfoLine: "  Microscope factor ", fixed$(microscope_time_factor, 2),
        ... " a ", fixed$(fade_duration * 1000, 0), " ms fade came out ",
        ... fixed$(fade_duration * 1000 * microscope_time_factor, 0), " ms."
    appendInfoLine: "  The Hamming option is gone: it started at 0.54-0.46 = 0.08 rather"
    appendInfoLine: "  than 0, and its fade-out branch carried a stray /2, so the two"
    appendInfoLine: "  ends were 0.08 and 0.04 - it could not prevent a click."
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
    if seedApplied = 1
        appendInfoLine: "  Seed ", random_seed, " - this take is reproducible."
    else
        appendInfoLine: "  Seed 0 - unpredictable, this take cannot be recovered."
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
        if srcChannels = 2 and microscope_downmix_stereo = 0
            appendInfoLine: "  Stereo: each channel is analysed separately, which can leave"
            appendInfoLine: "  small timing differences between them. Downmix first if the"
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

###############################################################################
# VISUALIZATION - THE EDIT MAP
###############################################################################
# v0.2: the useful picture for this tool is not a spectrogram, it is
# where the marks are, how wide their windows are, which windows hit a
# file edge, and how the pieces line up in the montage.

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
        ... + "  |  seed " + string$(random_seed)

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
# CLEANUP
###############################################################################
# The PointProcess is deliberately left alive so the montage can be
# re-run with different settings against the same marks.
for k from 1 to nSeg
    removeObject: segID[k]
endfor

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", resultName$
appendInfoLine: "The PointProcess is still there - change settings and run again."

if play_result
    selectObject: result
    Play
endif

selectObject: result
