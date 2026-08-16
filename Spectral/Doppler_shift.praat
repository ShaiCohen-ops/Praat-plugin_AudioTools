# ============================================================
# Praat AudioTools - Doppler_shift.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Stylized Doppler-inspired time warp with a controllable instantaneous
#   source-read rate and a distance-like amplitude curve. This is not a
#   physical speed-of-sound trajectory solver: the musical law is specified
#   directly as a time-varying resampling rate.
#
#   rate(u) = [base + amount * u^acceleration] / k,  0 <= u <= 1
#   read position is the integral of that rate. In Free traversal mode k=1;
#   in Duration-preserving mode k is the mean raw rate, so the whole source is
#   traversed exactly once while the relative glide shape is retained.
#
# Changelog v0.4.1 -- visualization and one text fix; the DSP is unchanged:
#   - FIX: "leaves the source at 90.2% of output" printed as "90.2" and the QC
#     strip lost its percent sign too. % is italic markup in Picture text and
#     is swallowed; the escape is \%.
#   - PANEL B REBUILT around the two things a musician actually needs. First,
#     the glide is now in SEMITONES: a rate of 1.400 says nothing to the ear,
#     +5.83 st says everything, and 12*log2(rate) is the same curve in the
#     unit that matters. Second, the realized law is drawn against a physical
#     constant-velocity pass-by, scaled to the SAME semitone span so the two
#     are compared on shape and direction rather than size, with a small plan
#     view of the geometry that reference curve comes from.
#     WHAT THAT SHOWS, and it is worth knowing: every preset named for a
#     passing vehicle (Passing Car, Passing Train, Flyby, Ambulance) has a
#     positive Shift_amount, so pitch RISES throughout while the distance gain
#     FALLS. A receding source does both downward, and a real pass-by is an
#     S-curve through unity at closest approach, never a monotonic rise. The
#     Description already says this is a stylized law and not a physical
#     solver; the figure now shows exactly how it differs, and the caption
#     names the direction. Enter a negative Shift_amount for a falling glide.
#   - PANEL D: two waveforms could not show a pitch glide at all -- the whole
#     point of the effect is invisible in an envelope. Now source and output
#     spectrograms, so the harmonics are seen sweeping, and the source
#     exhaustion in Free traversal is visible as the point where the swept
#     partials simply stop. The frequency range is framed on the source's own
#     energy (90% cumulative, with headroom for the upward shift) rather than
#     a fixed 5 kHz that left the content in a strip at the bottom.
#   - Panel B and D gained the axis marks they lacked; the exhaustion marker in
#     panel A no longer collides with the source-end label; and in panel C the
#     distance curve was completely hidden beneath the effective curve, which
#     tracks it exactly except where the edge guard acts, so the effective
#     curve is now dashed and the caption says the two coincide.
#
# Changelog v0.4:
#   - FORM: Shift_amount and Decay_amount are real-valued, so custom downward
#     glides and approaching gain curves are actually enterable. Version text
#     updated consistently.
#   - ROBUSTNESS/MUSIC: positive instantaneous read rate is validated. Free
#     traversal keeps its original may-run-off-the-end character, but a short
#     cosine guard can close the source-exhaustion edge instead of dropping a
#     non-zero sample directly to zero. Final start/end guards use the same
#     control and occur before final peak scaling.
#   - STEREO INPUT: the single-source model now chooses the strongest-RMS input
#     channel instead of averaging channels and risking phase cancellation.
#   - DOCUMENTATION: object-by-time reads are linear interpolation, not an
#     anti-aliased resampler. The original bright/rough high-rate character is
#     deliberately retained rather than silently low-pass filtering it.
#   - VISUALIZATION: process-first view of source-read geometry, instantaneous
#     pitch/time rate, distance/edge gain, and measured source-vs-output audio.
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

form Doppler Shift Effect v0.4
    optionmenu Preset: 1
        option Custom
        option Passing Car
        option Passing Train
        option Flyby (fast)
        option Subtle Approach
        option Heavy Decay
        option Sci-Fi Whoosh
        option Reverse Doppler
        option Ambulance Siren
    comment === Time-Warp / Pitch ===
    positive Base_shift 1.0
    real Shift_amount 0.5
    positive Acceleration 2
    comment (free mode: rate moves from base to base+amount)
    comment === Distance Gain ===
    real Decay_amount 15
    comment (+D: 1 to 1/D; -D: 1/D to 1; 0 = flat; |D| >= 1)
    comment === Source Traversal ===
    optionmenu Rate_mode: 1
        option Free traversal (may leave source early)
        option Duration-preserving (use whole source)
    real Edge_guard_ms 5
    comment (0 = hard edges; otherwise smooth source/output boundaries)
    comment === Output ===
    positive Scale_peak 0.99
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS
# ============================================================

if preset = 2
    base_shift = 1.0
    shift_amount = 0.4
    acceleration = 2
    decay_amount = 12
    presetName$ = "PassingCar"
elsif preset = 3
    base_shift = 1.0
    shift_amount = 0.3
    acceleration = 1.5
    decay_amount = 8
    presetName$ = "PassingTrain"
elsif preset = 4
    base_shift = 1.0
    shift_amount = 0.8
    acceleration = 4
    decay_amount = 20
    presetName$ = "Flyby"
elsif preset = 5
    base_shift = 1.0
    shift_amount = 0.2
    acceleration = 1.5
    decay_amount = 5
    presetName$ = "SubtleApproach"
elsif preset = 6
    base_shift = 1.0
    shift_amount = 0.5
    acceleration = 2
    decay_amount = 30
    presetName$ = "HeavyDecay"
elsif preset = 7
    base_shift = 0.8
    shift_amount = 1.2
    acceleration = 3
    decay_amount = 25
    presetName$ = "SciFiWhoosh"
elsif preset = 8
    base_shift = 1.5
    shift_amount = -0.5
    acceleration = 2
    decay_amount = -10
    presetName$ = "ReverseDoppler"
elsif preset = 9
    base_shift = 1.0
    shift_amount = 0.35
    acceleration = 2.5
    decay_amount = 15
    presetName$ = "Ambulance"
else
    presetName$ = "Custom"
endif

# ============================================================
# SETUP + VALIDATION
# ============================================================

selectObject:  originalID
duration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels
sourceXmin = Get start time
sourceXmax = Get end time

if duration <= 0
    exitScript: "The selected Sound has no duration."
endif
if acceleration <= 0
    exitScript: "Acceleration must be greater than 0."
endif
if scale_peak <= 0 or scale_peak > 1
    exitScript: "Scale peak must be greater than 0 and no greater than 1."
endif
if edge_guard_ms < 0
    exitScript: "Edge guard must be 0 ms or greater."
endif
if decay_amount <> 0 and abs(decay_amount) < 1
    exitScript: "Decay amount must be 0, >= 1, or <= -1."
endif

rawStartRate = base_shift
rawEndRate = base_shift + shift_amount
rawMinRate = min(rawStartRate, rawEndRate)
rawMaxRate = max(rawStartRate, rawEndRate)
if rawMinRate <= 0.01
    exitScript: "Base shift and Shift amount must keep the instantaneous read rate above 0.01."
endif

rawMeanRate = base_shift + shift_amount / (acceleration + 1)
kVal = 1
if rate_mode = 2
    if rawMeanRate <= 0.01
        exitScript: "Duration-preserving mode requires a positive mean read rate."
    endif
    kVal = rawMeanRate
    rateName$ = "duration-preserving"
else
    rateName$ = "free traversal"
endif

rateStart = rawStartRate / kVal
rateEnd = rawEndRate / kVal
rateMin = min(rateStart, rateEnd)
rateMax = max(rateStart, rateEnd)
meanRate = rawMeanRate / kVal
readEndFrac = meanRate

# Distance curve: preserve the historical ratio law, but allow a true flat 0.
if decay_amount = 0
    decMag = 1
    decDir = 0
else
    decMag = abs(decay_amount)
    if decay_amount < 0
        decDir = 1
    else
        decDir = 0
    endif
endif

edgeFade = min(edge_guard_ms / 1000, duration / 4)

# In free traversal, find when the monotonic read map reaches the source end.
# This is used only for a click-safe source-exhaustion guard and visualization.
sourceExitNorm = 1
sourceExitsEarly = 0
if readEndFrac > 1.0000001
    lo = 0
    hi = 1
    for iter to 50
        mid = (lo + hi) / 2
        midReadFrac = (base_shift * mid + shift_amount * mid ^ (acceleration + 1) / (acceleration + 1)) / kVal
        if midReadFrac < 1
            lo = mid
        else
            hi = mid
        endif
    endfor
    sourceExitNorm = (lo + hi) / 2
    sourceExitsEarly = 1
endif
sourceExitTime = sourceXmin + sourceExitNorm * duration

# ============================================================
# PREPARE SINGLE-SOURCE INPUT
# ============================================================

bestChannel = 1
bestRms = 0
if numChannels > 1
    bestRms = -1
    for ch to numChannels
        selectObject:  originalID
        probeCh = Extract one channel: ch
        selectObject:  probeCh
        probeRms = Get root-mean-square: 0, 0
        if probeRms > bestRms
            bestRms = probeRms
            bestChannel = ch
        endif
        removeObject: probeCh
    endfor
    selectObject:  originalID
    srcID = Extract one channel: bestChannel
    Rename: "dopsrc"
else
    selectObject:  originalID
    srcID = Copy: "dopsrc"
    selectObject:  srcID
    bestRms = Get root-mean-square: 0, 0
endif

# Result buffer with same time domain/sample rate as the selected source.
selectObject:  srcID
workingID = Copy: originalName$ + "_doppler_" + presetName$

clearinfo
writeInfoLine: "=== Doppler Shift Effect v0.4 ==="
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Duration: ", fixed$(duration, 3), " s | SR: ", fixed$(sampleRate, 0), " Hz"
if numChannels > 1
    appendInfoLine: "Single-source input: strongest RMS channel ", bestChannel, " of ", numChannels
endif
appendInfoLine: "Preset: ", presetName$, " | traversal: ", rateName$
appendInfoLine: "Rate: ", fixed$(rateStart, 3), " -> ", fixed$(rateEnd, 3), " | mean ", fixed$(meanRate, 3)
appendInfoLine: "Distance amount: ", decay_amount, " | edge guard: ", fixed$(edgeFade*1000, 1), " ms"
if sourceExitsEarly
    appendInfoLine: "Free traversal reaches source end at ", fixed$(sourceExitNorm*100, 1), "% of output duration."
endif
if rateMax > 1
    appendInfoLine: "Note: rates above 1 use the script's original linear-interpolation time warp; no anti-alias low-pass is imposed."
endif
appendInfoLine: ""
appendInfo: "Processing..."

# ============================================================
# PROCESS
# ============================================================

# Integrated time warp. Sound_dopsrc(time) is a linearly interpolated object
# read; the derivative of this read-position law is the rate shown above.
selectObject:  workingID
Formula: ~ Sound_dopsrc(sourceXmin + (base_shift * (x - xmin) + shift_amount * (xmax - xmin) * (((x - xmin) / (xmax - xmin)) ^ (acceleration + 1)) / (acceleration + 1)) / kVal)

# Distance-like relative gain.
selectObject:  workingID
if decMag > 1
    if decDir = 0
        Formula: ~ self * decMag ^ (-(x - xmin) / (xmax - xmin))
    else
        Formula: ~ self * decMag ^ (-(1 - (x - xmin) / (xmax - xmin)))
    endif
endif

# If free traversal leaves the source before output end, close that transition
# musically instead of allowing a non-zero interpolated sample to drop to zero.
if sourceExitsEarly and edgeFade > 0
    exitFade = min(edgeFade, sourceExitTime - sourceXmin)
    fadeStart = sourceExitTime - exitFade
    if exitFade > 0
        selectObject:  workingID
        Formula: ~ if x >= sourceExitTime then 0 else if x > fadeStart then self * (0.5 + 0.5*cos(pi*(x-fadeStart)/exitFade)) else self fi fi
    endif
endif

# General click guard at the file boundaries. 0 ms restores the hard-edge path.
if edgeFade > 0
    selectObject:  workingID
    Fade in: 0, sourceXmin, edgeFade, "yes"
    Fade out: 0, sourceXmax - edgeFade, edgeFade, "yes"
endif

# Final peak scaling, guarded for silence.
selectObject:  workingID
peakBeforeScale = Get absolute extremum: 0, 0, "None"
if peakBeforeScale > 1e-12
    Scale peak: scale_peak
endif

appendInfoLine: " done"

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: "Drawing process visualization..."

    selectObject:  srcID
    srcPeak = Get absolute extremum: 0, 0, "None"
    srcRms = Get root-mean-square: 0, 0
    selectObject:  workingID
    outPeak = Get absolute extremum: 0, 0, "None"
    outRms = Get root-mean-square: 0, 0
    vizPeak = 1.05 * max(srcPeak, outPeak)
    if vizPeak < 1e-9
        vizPeak = 1
    endif

    Erase all

    # Header
    procedure dopStep: .range, .target
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

    Select outer viewport:  0, 8, 0, 0.36
    Select inner viewport:  0, 8, 0, 0.36
    Axes:  0, 1, 0, 1
    Font size:  12
    Colour:  "Black"
    Text:  0.5, "centre", 0.62, "half", "Doppler-Inspired Time Warp - " + presetName$

    Select outer viewport:  0, 8, 0.38, 0.68
    Select inner viewport:  0, 8, 0.38, 0.68
    Axes:  0, 1, 0, 1
    Font size:  6
    Colour:  "{0.35,0.35,0.42}"
    Text:  0.5, "centre", 0.5, "half", "source -> integrated read-position warp -> distance gain -> edge guard -> final peak scale"

    # ---------------- A: read geometry ----------------
    Select outer viewport:  0, 8, 0.76, 0.96
    Select inner viewport:  0, 8, 0.76, 0.96
    Axes:  0, 1, 0, 1
    Font size:  9
    Colour:  "Black"
    Text:  0.02, "left", 0.5, "half", "A  Source-read geometry: output time -> source position"

    readYMax = max(duration * 1.05, duration * readEndFrac * 1.05)
    Select outer viewport:  0, 8, 0.98, 2.22
    Select inner viewport:  0.70, 7.72, 1.05, 2.04
    Axes:  0, duration, 0, readYMax
    Paint rectangle:  "{0.975,0.975,0.978}", 0, duration, 0, readYMax
    if readYMax > duration
        Paint rectangle:  "{0.985,0.93,0.93}", 0, duration, duration, readYMax
    endif
    # Identity reference
    Colour:  "{0.65,0.65,0.68}"
    Dashed line
    Draw line:  0, 0, duration, duration
    # Actual read curve
    Solid line
    Colour:  "{0.28,0.50,0.82}"
    Line width:  2
    nDraw = 240
    for q from 1 to nDraw
        u0 = (q-1)/nDraw
        u1 = q/nDraw
        t0 = duration*u0
        t1 = duration*u1
        r0 = duration * (base_shift*u0 + shift_amount*u0^(acceleration+1)/(acceleration+1)) / kVal
        r1 = duration * (base_shift*u1 + shift_amount*u1^(acceleration+1)/(acceleration+1)) / kVal
        Draw line:  t0, r0, t1, r1
    endfor
    Line width:  1
    # Source-end boundary and label before any dot marker.
    Dashed line
    Colour:  "{0.72,0.28,0.24}"
    Draw line:  0, duration, duration, duration
    Solid line
    Font size:  5
    Text:  0.985*duration, "right", min(readYMax*0.95, duration + 0.06*readYMax), "half", "source end"
    if sourceExitsEarly
        Text:  sourceExitNorm*duration, "centre", 0.82*duration, "half",
            ... "exhausted " + fixed$(sourceExitNorm*duration,2) + " s"
        Paint circle (mm): "{0.72,0.28,0.24}", sourceExitNorm*duration, duration, 0.7
    endif
    Select inner viewport:  0.70, 7.72, 1.05, 2.04
    Axes:  0, duration, 0, readYMax
    Colour:  "Black"
    Draw inner box
    Font size:  5
    Marks left every:  1, max(0.1, duration/4), "yes", "yes", "no"
    Marks bottom every:  1, max(0.1, duration/5), "yes", "yes", "no"
    Font size:  6
    Text left:  "yes", "source s"

    Select outer viewport:  0, 8, 2.22, 2.40
    Select inner viewport:  0, 8, 2.22, 2.40
    Axes:  0, 1, 0, 1
    Font size:  6
    Colour:  "{0.35,0.35,0.42}"
    if sourceExitsEarly
        aNote$ = "read(T)=" + fixed$(readEndFrac,3) + "*source duration; free traversal leaves the source at " + fixed$(sourceExitNorm*100,1) + "\%  of output"
    else
        aNote$ = "read(T)=" + fixed$(readEndFrac,3) + "*source duration; blue = actual map, gray dashed = identity"
    endif
    Text:  0.5, "centre", 0.5, "half", aNote$

    # ---------------- B: rate law ----------------
    Select outer viewport:  0, 8, 2.48, 2.68
    Select inner viewport:  0, 8, 2.48, 2.68
    Axes:  0, 1, 0, 1
    Font size:  9
    Colour:  "Black"
    Text:  0.02, "left", 0.5, "half",
        ... "B  Pitch of the glide, in semitones, against a physical pass-by"

    # A ratio of 1.400 tells a musician nothing; +5.85 semitones tells them
    # everything. 12*log2(rate) is the same curve in the unit the ear uses.
    stStart = 12 * log2(rateStart)
    stEnd = 12 * log2(rateEnd)
    stMin = min(stStart, stEnd)
    stMax = max(stStart, stEnd)
    for q from 0 to 60
        uu = q / 60
        rr = (base_shift + shift_amount * uu^acceleration) / kVal
        if rr > 0
            ss = 12 * log2(rr)
            stMin = min(stMin, ss)
            stMax = max(stMax, ss)
        endif
    endfor

    # Reference: a constant-velocity source passing a listener at closest
    # distance d, speed v. Radial velocity gives ratio = 1/(1 + vr/c), which
    # is the S-curve every real flyby follows: high while approaching, through
    # unity at closest approach, low while receding. v is chosen so the
    # reference spans the same number of semitones as the realized law, so the
    # two are compared on SHAPE and DIRECTION, not on size.
    stSpan = max(0.5, stMax - stMin)
    vOverC = (2^(stSpan/12) - 1) / (2^(stSpan/12) + 1)
    if vOverC > 0.85
        vOverC = 0.85
    endif
    for q from 0 to 120
        uu = q / 120
        xr = (uu - 0.5) * 8
        rr = sqrt(1 + xr * xr)
        vrel = vOverC * xr / rr
        refRatio[q] = 1 / (1 + vrel)
        refSt[q] = 12 * log2(refRatio[q])
        stMin = min(stMin, refSt[q])
        stMax = max(stMax, refSt[q])
    endfor

    stPad = max(0.4, 0.12 * (stMax - stMin))
    stLo = stMin - stPad
    stHi = stMax + stPad

    Select outer viewport:  0, 8, 2.70, 3.72
    Select inner viewport:  2.05, 7.72, 2.77, 3.50
    Axes:  0, duration, stLo, stHi
    Paint rectangle:  "{0.975,0.975,0.978}", 0, duration, stLo, stHi

    Select inner viewport:  2.05, 7.72, 2.77, 3.50
    Axes:  0, duration, stLo, stHi
    Font size: 5
    Colour:  "{0.88,0.42,0.24}"
    Text: 0.02*duration, "left", stLo + 0.32*(stHi-stLo), "half", "this effect"
    Colour:  "{0.35,0.55,0.40}"
    Text: 0.02*duration, "left", stLo + 0.21*(stHi-stLo), "half",
        ... "a real pass-by, same span"

    Select inner viewport:  2.05, 7.72, 2.77, 3.50
    Axes:  0, duration, stLo, stHi
    Colour:  "{0.62,0.62,0.65}"
    Dashed line
    Line width: 1
    if stLo < 0 and stHi > 0
        Draw line:  0, 0, duration, 0
    endif

    # physical reference
    Colour:  "{0.35,0.55,0.40}"
    Line width: 1
    for q from 1 to 120
        Draw line: duration*(q-1)/120, refSt[q-1], duration*q/120, refSt[q]
    endfor
    Solid line

    # the realized law
    Colour:  "{0.88,0.42,0.24}"
    Line width:  2
    for q from 1 to nDraw
        u0=(q-1)/nDraw
        u1=q/nDraw
        rr0=(base_shift + shift_amount*u0^acceleration)/kVal
        rr1=(base_shift + shift_amount*u1^acceleration)/kVal
        if rr0 > 0 and rr1 > 0
            Draw line:  duration*u0, 12*log2(rr0), duration*u1, 12*log2(rr1)
        endif
    endfor
    Line width:  1

    Select inner viewport:  2.05, 7.72, 2.77, 3.50
    Axes:  0, duration, stLo, stHi
    Select inner viewport:  2.05, 7.72, 2.77, 3.50
    Axes:  0, duration, stLo, stHi
    Colour:  "Black"
    Line width: 1
    Draw inner box
    Font size:  5
    @dopStep: stHi - stLo, 5
    Marks left every: 1, dopStep.step, "yes", "yes", "no"
    Marks bottom every:  1, max(0.1,duration/5), "yes", "yes", "no"
    Font size: 6
    Text left:  "yes", "semitones"

    # Plan view: what the reference curve is a picture OF.
    Select inner viewport: 0.72, 1.85, 2.77, 3.50
    Axes: -4.4, 4.4, -1.1, 3.2
    Paint rectangle: "{0.975,0.975,0.978}", -4.4, 4.4, -1.1, 3.2

    Select inner viewport: 0.72, 1.85, 2.77, 3.50
    Axes: -4.4, 4.4, -1.1, 3.2
    Colour: "{0.35,0.55,0.40}"
    Line width: 1
    Draw line: -4.0, 1.0, 4.0, 1.0
    Draw line: 4.0, 1.0, 3.5, 1.25
    Draw line: 4.0, 1.0, 3.5, 0.75
    Colour: "{0.62,0.62,0.65}"
    Dashed line
    Draw line: 0, 0, 0, 1.0
    Solid line
    Paint circle (mm): "{0.25,0.35,0.55}", 0, 0, 0.9
    Paint circle (mm): "{0.35,0.55,0.40}", -2.2, 1.0, 0.8

    Select inner viewport: 0.72, 1.85, 2.77, 3.50
    Axes: -4.4, 4.4, -1.1, 3.2
    Font size: 4
    Colour: "{0.35,0.35,0.42}"
    Text: 0, "centre", -0.55, "half", "listener"
    Text: -2.2, "centre", 1.75, "half", "source"
    Text: 0.22, "left", 0.5, "half", "d"
    Font size: 5
    Colour: "Black"
    Line width: 1
    Draw inner box

    Select outer viewport:  0, 8, 3.56, 3.74
    Select inner viewport:  0, 8, 3.56, 3.74
    Axes:  0, 1, 0, 1
    Font size:  6
    Colour:  "{0.35,0.35,0.42}"
    if stEnd > stStart + 0.05
        dirNote$ = "this law rises throughout; a receding source falls"
    elsif stEnd < stStart - 0.05
        dirNote$ = "this law falls throughout; a real pass falls only after closest approach"
    else
        dirNote$ = "flat"
    endif
    Text:  0.5, "centre", 0.5, "half",
        ... "rate " + fixed$(rateStart,3) + " -> " + fixed$(rateEnd,3)
        ... + "  =  " + fixed$(stStart,2) + " -> " + fixed$(stEnd,2) + " st  ("
        ... + fixed$(stEnd-stStart,2) + " st glide)  |  " + dirNote$

    # ---------------- C: gain law ----------------
    Select outer viewport:  0, 8, 3.98, 4.18
    Select inner viewport:  0, 8, 3.98, 4.18
    Axes:  0, 1, 0, 1
    Font size:  9
    Colour:  "Black"
    Text:  0.02, "left", 0.5, "half", "C  Relative gain: distance law and effective edge guard"

    Select outer viewport:  0, 8, 4.20, 5.18
    Select inner viewport:  0.70, 7.72, 4.27, 5.02
    Axes:  0, duration, 0, 1.05
    Paint rectangle:  "{0.975,0.975,0.978}",0,duration,0,1.05
    # Distance curve in green; effective distance*edge curve in dark blue.
    prevDist=0
    prevEff=0
    for q from 0 to nDraw
        u=q/nDraw
        t=duration*u
        if decMag <= 1
            dg=1
        elsif decDir=0
            dg=decMag^(-u)
        else
            dg=decMag^(-(1-u))
        endif
        eg=1
        if edgeFade > 0
            if t < edgeFade
                eg=eg*(0.5-0.5*cos(pi*t/edgeFade))
            endif
            if duration-t < edgeFade
                eg=eg*(0.5-0.5*cos(pi*(duration-t)/edgeFade))
            endif
            if sourceExitsEarly
                exitFade=min(edgeFade,sourceExitNorm*duration)
                fadeStartRel=sourceExitNorm*duration-exitFade
                if t >= sourceExitNorm*duration
                    eg=0
                elsif t > fadeStartRel and exitFade > 0
                    eg=eg*(0.5+0.5*cos(pi*(t-fadeStartRel)/exitFade))
                endif
            endif
        elsif sourceExitsEarly and t >= sourceExitNorm*duration
            eg=0
        endif
        eff=dg*eg
        if q>0
            tPrev=duration*(q-1)/nDraw
            Colour:  "{0.28,0.65,0.40}"
            Line width:  2
            Solid line
            Draw line:  tPrev,prevDist,t,dg
            Colour:  "{0.24,0.42,0.72}"
            Line width:  1.5
            Dashed line
            Draw line:  tPrev,prevEff,t,eff
            Solid line
        endif
        prevDist=dg
        prevEff=eff
    endfor
    Line width: 1
    Select inner viewport:  0.70,7.72,4.27,5.02
    Axes: 0,duration,0,1.05
    Font size: 5
    Colour: "{0.28,0.65,0.40}"
    Text: 0.02*duration,"left",0.94,"half","green distance"
    Colour: "{0.24,0.42,0.72}"
    Text: 0.25*duration,"left",0.94,"half","blue dashed = effective (the two coincide except where the guard acts)"
    Colour: "Black"
    Draw inner box
    Marks left every: 1,0.25,"yes","yes","no"
    Marks bottom every: 1,max(0.1,duration/5),"yes","yes","no"

    Select outer viewport: 0,8,5.18,5.36
    Select inner viewport: 0,8,5.18,5.36
    Axes: 0,1,0,1
    Font size: 6
    Colour: "{0.35,0.35,0.42}"
    if decay_amount=0
        gainLaw$="distance gain flat at 1"
    elsif decDir=0
        gainLaw$="distance: 1 -> 1/"+fixed$(decMag,1)
    else
        gainLaw$="distance: 1/"+fixed$(decMag,1)+" -> 1"
    endif
    Text: 0.5,"centre",0.5,"half",gainLaw$+" | edge guard="+fixed$(edgeFade*1000,1)+" ms"

    # ---------------- D: measured audio ----------------
    Select outer viewport: 0,8,5.44,5.64
    Select inner viewport: 0,8,5.44,5.64
    Axes: 0,1,0,1
    Font size: 9
    Colour: "Black"
    Text: 0.02,"left",0.5,"half","D  Measured source and output spectra: the glide made visible"

    # Two waveforms cannot show a pitch glide at all: the whole point of this
    # effect is invisible in an envelope. Spectrograms show the harmonics
    # sweeping, with the source panel as the flat reference to sweep from.
    selectObject: srcID
    srcRateD = Get sampling frequency
    nyqD = srcRateD / 2
    srcSpecScan = To Spectrum: "yes"
    totE = Get band energy: 0, nyqD
    f90 = nyqD
    if totE > 0
        cumE = 0
        for q from 1 to 60
            fA = nyqD * (q - 1) / 60
            fB = nyqD * q / 60
            bandE = Get band energy: fA, fB
            cumE = cumE + bandE
            if cumE / totE >= 0.90 and f90 = nyqD
                f90 = fB
            endif
        endfor
    endif
    removeObject: srcSpecScan
    # headroom so content shifted UP by the glide stays in frame
    shiftHead = max(1, max(rateStart, rateEnd))
    specTop = min(0.92 * nyqD, max(600, 1.7 * f90 * shiftHead))
    specStepD = max(0.002, duration / 900)

    Select outer viewport: 0,8,5.66,6.20
    Select inner viewport: 0.70,7.72,5.69,6.15
    selectObject: srcID
    srcSpecD = To Spectrogram: 0.02, specTop, specStepD, 20, "Gaussian"
    Select inner viewport: 0.70,7.72,5.69,6.15
    selectObject: srcSpecD
    Paint: 0, 0, 0, specTop, 100, 1, 45, 6, 0, 0
    removeObject: srcSpecD
    Select inner viewport: 0.70,7.72,5.69,6.15
    Axes: sourceXmin,sourceXmax,0,specTop
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 5
    @dopStep: specTop, 3
    Marks left every: 1, dopStep.step, "yes", "yes", "no"
    Font size: 6
    Text left: "yes","source Hz"

    Select outer viewport: 0,8,6.20,6.76
    Select inner viewport: 0.70,7.72,6.23,6.69
    selectObject: workingID
    outSpecD = To Spectrogram: 0.02, specTop, specStepD, 20, "Gaussian"
    Select inner viewport: 0.70,7.72,6.23,6.69
    selectObject: outSpecD
    Paint: 0, 0, 0, specTop, 100, 1, 45, 6, 0, 0
    removeObject: outSpecD
    Select inner viewport: 0.70,7.72,6.23,6.69
    Axes: sourceXmin,sourceXmax,0,specTop
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 5
    @dopStep: specTop, 3
    Marks left every: 1, dopStep.step, "yes", "yes", "no"
    Marks bottom every: 1,max(0.1,duration/5),"yes","yes","no"
    Font size: 6
    Text left: "yes","output Hz"

    Select outer viewport: 0,8,6.76,6.96
    Select inner viewport: 0,8,6.76,6.96
    Axes: 0,1,0,1
    Font size: 6
    Colour: "{0.35,0.35,0.42}"
    Text: 0.5,"centre",0.5,"half","time in seconds | 0.." + fixed$(specTop,0) + " Hz, framed on the source's own energy | the harmonics sweep by the glide in B | peak src/out " + fixed$(srcPeak,3) + "/" + fixed$(outPeak,3) + " | RMS " + fixed$(srcRms,3) + "/" + fixed$(outRms,3)

    # QC strip
    Select outer viewport: 0,8,7.04,7.56
    Select inner viewport: 0.15,7.85,7.07,7.53
    Axes: 0,3,0,1
    Paint rectangle: "{0.965,0.965,0.97}",0,3,0,1
    Colour: "{0.82,0.82,0.84}"
    Draw line: 1,0,1,1
    Draw line: 2,0,2,1
    Colour: "Black"
    Draw rectangle: 0,3,0,1
    Font size: 5.5
    Text: 0.05,"left",0.5,"half","rate " + fixed$(rateStart,2) + "->" + fixed$(rateEnd,2) + " | mean " + fixed$(meanRate,2)
    if sourceExitsEarly
        exitQC$="source end @ " + fixed$(sourceExitNorm*100,1) + "\% "
    else
        exitQC$="source read end " + fixed$(readEndFrac*100,1) + "\% "
    endif
    Text: 1.05,"left",0.5,"half",exitQC$ + " | " + rateName$
    Text: 2.05,"left",0.5,"half","peak " + fixed$(outPeak,3) + " | SR " + fixed$(sampleRate,0) + " | ch " + string$(bestChannel)
endif

# ============================================================
# CLEANUP + OUTPUT
# ============================================================

removeObject: srcID
selectObject:  workingID

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Created: ", originalName$, "_doppler_", presetName$

if play_result
    Play
endif

selectObject:  workingID
