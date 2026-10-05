# ============================================================
# Praat AudioTools - Creative_Convolution.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Creative Convolution — flexible convolution mixing for impulse
#   responses and arbitrary sound kernels. Pure Praat; the DSP core is
#   Praat's own "Sounds: Convolve". Any Sound can be the kernel: a
#   measured or synthetic IR, a noise burst, an instrumental note, a
#   Self-Oscillating FDN rendering. Convolution transfers the temporal and
#   spectral identity of the kernel onto the source.
#
#   Signal path:
#     Source -> dry path ------------------------------------+
#     Kernel -> trim -> stretch -> reverse -> fades -> (stereo |
#               pair) -> pre-delay -> Convolve -> [feedback] -> |
#               RMS match -> wet gain -> width -> pan -> wet -> mixer
#     mixer (linear or equal power) -> end fade -> normalisation
#               -> clipping protection -> output (stereo)
#   Complements IR Analysis (detailed IR preparation); this tool only
#   prepares the kernel as far as convolution needs.
#
#   Measured facts this script relies on (Praat 6.4.06):
#   - Convolve is channel-wise for stereo x stereo (L*L, R*R) and
#     broadcasts a mono input over a stereo one.
#   - Scaling "sum" returns unity for a unit impulse (a measured IR keeps
#     its own level); "integral" scales by the sample period (1/sr);
#     "normalize" and "peak 0.99" rescale the result. Default: sum.
#   - Kernel sample k (1-based) acts as a delay of k-1 samples; the wet
#     result is mixed with the dry by sample index (verified: a unit-
#     impulse kernel reproduces the dry signal sample for sample).
#
#   Kernel Stretch is RESAMPLE-LIKE scaling, not pitch-preserving: the
#   kernel's sampling frequency is reinterpreted (Override sampling
#   frequency) and resampled back to the source rate, so 200% doubles the
#   kernel's duration AND moves its spectrum down an octave; 50% halves
#   the duration and moves it up an octave.
#
#   Stereo from a mono kernel, without delays or modulation of the
#   source: complementary slow amplitude modulation of the kernel tail,
#   kL = k (1 + d m(t)), kR = k (1 - d m(t)), m = smoothed seeded noise
#   (< 40 Hz). For a MONO source, L + R is exactly twice the mono-kernel
#   response, so that case is mono-compatible by construction. With a stereo source,
#   Praat convolves channel-wise (L*L, R*R), so this exact sum identity does
#   not apply. The first 5 ms of the kernel are left untouched so the attack
#   stays centred. d = 0.5 (Stereo Wet),
#   0.9 (Wide Wet and the late part of Early Center / Late Wide).
#
# Changelog v1.0.1:
#   - Fixed Custom-dialog variable names for Pre delay and Early late split.
#   - Wet/Dry = 0% now renders at the dry source length instead of appending
#     a silent convolution tail.
#   - Final end fade is applied only when an audible wet tail extends beyond
#     the dry source.
#   - Clarified mono-compatibility note for mono versus stereo sources.
#
# Changelog v1.0:
#   - First release.
#
# Requires: Praat 6.3+. Nothing else.
# ============================================================

version$ = "1.0.1"

# ---- INPUT: exactly two Sounds ----
if numberOfSelected("Sound") <> 2
    exitScript: "Please select exactly two Sounds: the source and the kernel (IR)."
endif
sndA = selected("Sound", 1)
sndB = selected("Sound", 2)
nameA$ = selected$("Sound", 1)
nameB$ = selected$("Sound", 2)

# ============================================================
# FORM (short)
# ============================================================
form: "Creative Convolution v1.0.1"
    optionmenu: "Preset", 1
        option: "Natural Convolution"
        option: "Long Hall"
        option: "Reverse Bloom"
        option: "Spectral Imprint"
        option: "Resonant Kernel"
        option: "FDN Space"
        option: "Frozen Metal"
        option: "Short Texture"
        option: "Experimental Reverse FDN"
        option: "Custom"
    real: "Wet dry (%)", "-1"
    comment: "Wet dry: -1 = use the preset's value; 0 = dry only, 100 = wet only"
    optionmenu: "Normalization", 2
        option: "None"
        option: "Peak"
        option: "RMS (-18 dBFS)"
    real: "Target peak (dBFS)", "-1.0"
    boolean: "Show parameters", 0
    boolean: "Draw visualisation", 1
    boolean: "Play result", 1
endform

# ---- which Sound is the source? (object-list order is not click order) ----
source = 1
beginPause: "Creative Convolution — roles"
    comment: "Which of the two selected Sounds is the SOURCE (dry)? The other is the kernel."
    optionMenu: "Source", 1
        option: nameA$
        option: nameB$
endPause: "Continue", 1
sourceIsFirst = if source = 2 then 0 else 1 fi
if sourceIsFirst
    srcObj = sndA
    kerObj = sndB
    srcName$ = nameA$
    kerName$ = nameB$
else
    srcObj = sndB
    kerObj = sndA
    srcName$ = nameB$
    kerName$ = nameA$
endif

# ============================================================
# PRESETS — each sets every sound parameter
# ============================================================
kStart = 0
kEnd = 100
kStretch = 100
kReverse = 0
kFadeIn = 0
kFadeOut = 0
preDelayMs = 0
wetDry = 30
mixLaw = 2
wetGainDb = 0
rmsMatch = 1
spatialMode = 2
splitMs = 80
wetPan = 0
wetWidth = 100
protect = 1
scaling = 1
outside = 1
feedbackPct = 0
feedbackIter = 2

procedure applyPreset: .p
    # defaults shared by all presets, then the differences
    kStart = 0
    kEnd = 100
    kStretch = 100
    kReverse = 0
    kFadeIn = 0
    kFadeOut = 0
    preDelayMs = 0
    mixLaw = 2
    wetGainDb = 0
    rmsMatch = 1
    spatialMode = 2
    splitMs = 80
    wetPan = 0
    wetWidth = 100
    protect = 1
    scaling = 1
    outside = 1
    feedbackPct = 0
    feedbackIter = 2
    if .p = 1
        # Natural Convolution: kernel unchanged, modest wet, stereo
        wetDry = 30
        kFadeOut = 5
        wetWidth = 110
    elsif .p = 2
        # Long Hall: longer (stretched) kernel, pre-delay, wet-heavy, wide late field
        wetDry = 55
        kStretch = 140
        kFadeOut = 30
        preDelayMs = 25
        spatialMode = 4
        splitMs = 80
        wetWidth = 150
    elsif .p = 3
        # Reverse Bloom: reversed kernel, pre-delay, wet-dominant, wide
        wetDry = 65
        kReverse = 1
        kFadeIn = 20
        kFadeOut = 4
        preDelayMs = 40
        spatialMode = 3
        wetWidth = 140
    elsif .p = 4
        # Spectral Imprint: arbitrary sound as kernel, high wet, minimal dry
        wetDry = 90
        kFadeIn = 5
        kFadeOut = 20
        spatialMode = 2
        wetWidth = 100
    elsif .p = 5
        # Resonant Kernel: short kernel, modest stretch, strong wet, controlled width
        wetDry = 70
        kEnd = 40
        kStretch = 120
        kFadeIn = 2
        kFadeOut = 30
        spatialMode = 2
        wetWidth = 80
    elsif .p = 6
        # FDN Space: for a Self-Oscillating FDN rendering as kernel
        wetDry = 50
        kFadeOut = 200
        preDelayMs = 20
        spatialMode = 3
        wetWidth = 130
    elsif .p = 7
        # Frozen Metal: strongly stretched kernel, high wet, wide
        wetDry = 85
        kStretch = 300
        kFadeIn = 20
        kFadeOut = 300
        spatialMode = 3
        wetWidth = 150
    elsif .p = 8
        # Short Texture: trimmed short kernel, small fades, lower wet, wide
        wetDry = 35
        kEnd = 15
        kFadeIn = 3
        kFadeOut = 15
        spatialMode = 3
        wetWidth = 170
    elsif .p = 9
        # Experimental Reverse FDN: reversed + stretched, high wet, wide, feedback
        wetDry = 80
        kReverse = 1
        kStretch = 200
        kFadeIn = 30
        kFadeOut = 10
        spatialMode = 3
        wetWidth = 160
        feedbackPct = 35
        feedbackIter = 2
    endif
endproc

presetName$ = preset$
if preset < 10
    @applyPreset: preset
endif
if wet_dry >= 0
    wetDry = wet_dry
endif

# ============================================================
# DETAIL DIALOGS (pre-filled; Custom forces them open)
# ============================================================
if show_parameters or preset = 10
    beginPause: "Creative Convolution — kernel"
        real: "Kernel start (%)", string$(kStart)
        real: "Kernel end (%)", string$(kEnd)
        comment: "Stretch is resample-like: 200% = twice as long AND an octave lower"
        positive: "Kernel stretch (%)", string$(kStretch)
        boolean: "Reverse kernel", kReverse
        real: "Kernel fade in (ms)", string$(kFadeIn)
        real: "Kernel fade out (ms)", string$(kFadeOut)
        real: "Pre delay (ms)", string$(preDelayMs)
    endPause: "Continue", 1
    kStart = kernel_start
    kEnd = kernel_end
    kStretch = kernel_stretch
    kReverse = reverse_kernel
    kFadeIn = kernel_fade_in
    kFadeOut = kernel_fade_out
    preDelayMs = pre_delay
    beginPause: "Creative Convolution — mix, space, advanced"
        real: "Wet dry (%)", string$(wetDry)
        optionMenu: "Mix law", mixLaw
            option: "Linear"
            option: "Equal power"
        real: "Wet gain (dB)", string$(wetGainDb)
        boolean: "Match wet RMS to dry", rmsMatch
        optionMenu: "Spatial mode", spatialMode
            option: "Mono Wet"
            option: "Stereo Wet"
            option: "Wide Wet"
            option: "Early Center / Late Wide"
        positive: "Early late split (ms)", string$(splitMs)
        real: "Wet pan (-100..100)", string$(wetPan)
        real: "Wet width (%)", string$(wetWidth)
        boolean: "Protect against clipping", protect
        optionMenu: "Convolution scaling", scaling
            option: "Sum (IR keeps its level)"
            option: "Integral"
            option: "Normalize"
            option: "Peak 0.99"
        optionMenu: "Outside domain", outside
            option: "Zero"
            option: "Similar"
        real: "Feedback (%)", string$(feedbackPct)
        natural: "Feedback iterations", string$(feedbackIter)
    endPause: "Continue", 1
    wetDry = wet_dry
    mixLaw = mix_law
    wetGainDb = wet_gain
    rmsMatch = match_wet_RMS_to_dry
    spatialMode = spatial_mode
    splitMs = early_late_split
    wetPan = wet_pan
    wetWidth = wet_width
    protect = protect_against_clipping
    scaling = convolution_scaling
    outside = outside_domain
    feedbackPct = feedback
    feedbackIter = feedback_iterations
endif

# ============================================================
# VALIDATION
# ============================================================
if kStart < 0 or kEnd > 100 or kStart >= kEnd
    exitScript: "Kernel start/end must satisfy 0 <= start < end <= 100 (got " + fixed$(kStart, 1) + " / " + fixed$(kEnd, 1) + ")."
endif
kStretch = max(25, min(400, kStretch))
kFadeIn = max(0, kFadeIn)
kFadeOut = max(0, kFadeOut)
preDelayMs = max(0, min(500, preDelayMs))
wetDry = max(0, min(100, wetDry))
wetGainDb = max(-30, min(18, wetGainDb))
wetPan = max(-100, min(100, wetPan))
wetWidth = max(0, min(200, wetWidth))
feedbackPct = max(0, min(90, feedbackPct))
feedbackIter = max(1, min(4, feedbackIter))
scaling$ = "sum"
if scaling = 2
    scaling$ = "integral"
elsif scaling = 3
    scaling$ = "normalize"
elsif scaling = 4
    scaling$ = "peak 0.99"
endif
outside$ = "zero"
if outside = 2
    outside$ = "similar"
endif

# ============================================================
# WORKING COPIES (originals are never modified)
# ============================================================
procedure workingCopy: .obj, .name$
    selectObject: .obj
    .c = Copy: .name$
    Shift times to: "start time", 0
    .n = Get number of channels
    if .n > 2
        # topologies beyond stereo are not supported: fold to mono
        .m = Convert to mono
        removeObject: .c
        .c = .m
        Rename: .name$
        multiNote$ = multiNote$ + " " + .name$ + " folded from " + string$(.n) + " channels to mono;"
    endif
endproc
multiNote$ = ""
@workingCopy: srcObj, "cc_dry"
dry = workingCopy.c
@workingCopy: kerObj, "cc_kernel"
ker = workingCopy.c

selectObject: dry
sr = Get sampling frequency
dryDur = Get total duration
dryCh = Get number of channels
dryRms = Get root-mean-square: 0, 0
selectObject: ker
kerSrOrig = Get sampling frequency
kerDurOrig = Get total duration
kerCh = Get number of channels
resampled = 0
if kerSrOrig <> sr
    tmpR = Resample: sr, 50
    removeObject: ker
    ker = tmpR
    resampled = 1
endif

# ============================================================
# KERNEL PREPARATION
# ============================================================
# 1. trim (percent of the kernel's duration)
selectObject: ker
kd = Get total duration
tmpT = Extract part: kd * kStart / 100, kd * kEnd / 100, "rectangular", 1, "no"
Shift times to: "start time", 0
removeObject: ker
ker = tmpT

# 2. resample-like stretch (duration x s, spectrum / s)
stretchNote$ = "none"
selectObject: ker
kn = Get number of samples
if kStretch <> 100
    if kn >= 8
        Override sampling frequency: sr * 100 / kStretch
        tmpR = Resample: sr, 50
        removeObject: ker
        ker = tmpR
        stretchNote$ = fixed$(kStretch, 0) + "% (resample-like: duration x" + fixed$(kStretch / 100, 2) + ", spectrum shifted " + fixed$(12 * log2(100 / kStretch), 1) + " semitones)"
    else
        stretchNote$ = "skipped (kernel only " + string$(kn) + " samples)"
    endif
endif

# 3. reverse
if kReverse
    selectObject: ker
    Reverse
endif

# 4. fades (raised cosine), never longer than the kernel together
selectObject: ker
kd = Get total duration
fi_s = kFadeIn / 1000
fo_s = kFadeOut / 1000
if fi_s + fo_s > kd
    fadeScale = kd / (fi_s + fo_s)
    fi_s = fi_s * fadeScale
    fo_s = fo_s * fadeScale
endif
if fi_s > 0
    Formula: "if x < fi_s then self * (0.5 - 0.5 * cos (pi * x / fi_s)) else self fi"
endif
if fo_s > 0
    Formula: "if x > xmax - fo_s then self * (0.5 - 0.5 * cos (pi * (xmax - x) / fo_s)) else self fi"
endif
selectObject: ker
kerRms = Get root-mean-square: 0, 0
kerSilent = kerRms = undefined or kerRms < 1e-9
drySilent = dryRms = undefined or dryRms < 1e-9

# 5. stereo kernel pair: see procedure stereoPairSafe (complementary slow
#    modulation of a mono kernel's tail: L + R = 2 x mono kernel)

# 6. pre-delay: silence in front of the kernel (delays the wet only)
procedure preDelayPad: .k
    selectObject: .k
    .n = Get number of samples
    .ch = Get number of channels
    .p = round(preDelayMs / 1000 * sr)
    if .p > 0
        .out = Create Sound from formula: "cc_kpd", .ch, 0, (.n + .p) / sr, sr, "if col <= padN then 0 else object [kPadSrc, row, col - padN] fi"
    else
        selectObject: .k
        .out = Copy: "cc_kpd"
    endif
endproc

# convolution helper
procedure conv: .a, .b
    selectObject: .a, .b
    .r = Convolve: convScaling$, outside$
endproc

# ============================================================
# WET PATH
# ============================================================
convScaling$ = scaling$
scalingNote$ = scaling$
if spatialMode = 4 and (scaling = 3 or scaling = 4)
    # two separate convolutions must share one scale
    convScaling$ = "sum"
    scalingNote$ = scaling$ + " requested; sum used (early and late must share one scale)"
endif

# source used for the wet path (mono for Mono Wet and the early part)
selectObject: dry
if dryCh = 2
    srcMono = Convert to mono
else
    srcMono = Copy: "cc_srcmono"
endif

wetNote$ = ""
if kerSilent or drySilent
    wet = Create Sound from formula: "cc_wet", 2, 0, dryDur, sr, "0"
    wetNote$ = "source is silent: wet path is silence"
    if kerSilent
        wetNote$ = "kernel is silent: wet path is silence"
    endif
    kerShow = ker
    kpd = ker
else
    if spatialMode = 1
        # Mono Wet: mono source x mono kernel
        selectObject: ker
        if kerCh = 2
            kmono = Convert to mono
        else
            kmono = Copy: "cc_kmono"
        endif
        kPadSrc = kmono
        padN = round(preDelayMs / 1000 * sr)
        @preDelayPad: kmono
        kpd = preDelayPad.out
        @conv: srcMono, kpd
        wet = conv.r
        removeObject: kmono
        wetNote$ = "mono source x mono kernel"
    elsif spatialMode = 2 or spatialMode = 3
        pairDepth = 0.9
        if spatialMode = 2
            pairDepth = 0.5
        endif
        mr2 = 1
        @stereoPairSafe: ker, pairDepth
        kPadSrc = stereoPairSafe.pair
        padN = round(preDelayMs / 1000 * sr)
        @preDelayPad: stereoPairSafe.pair
        kpd = preDelayPad.out
        removeObject: stereoPairSafe.pair
        @conv: dry, kpd
        wet = conv.r
        if kerCh = 2
            wetNote$ = "stereo kernel used channel-wise"
        else
            wetNote$ = "mono kernel -> complementary stereo pair (depth " + fixed$(pairDepth, 1) + ")"
        endif
    else
        # Early Center / Late Wide
        selectObject: ker
        kd = Get total duration
        split_s = min(splitMs / 1000, kd * 0.9)
        if kerCh = 2
            kmono = Convert to mono
        else
            kmono = Copy: "cc_kmono"
        endif
        Formula: "if x < split_s - 0.0025 then self else if x > split_s + 0.0025 then 0 else self * (0.5 + 0.5 * cos (pi * (x - split_s + 0.0025) / 0.005)) fi fi"
        kEarly = kmono
        selectObject: ker
        kLate = Copy: "cc_klate"
        Formula: "if x < split_s - 0.0025 then 0 else if x > split_s + 0.0025 then self else self * (0.5 - 0.5 * cos (pi * (x - split_s + 0.0025) / 0.005)) fi fi"
        padN = round(preDelayMs / 1000 * sr)
        kPadSrc = kEarly
        @preDelayPad: kEarly
        kEarlyPd = preDelayPad.out
        pairDepth = 0.9
        mr2 = 1
        @stereoPairSafe: kLate, pairDepth
        kPadSrc = stereoPairSafe.pair
        @preDelayPad: stereoPairSafe.pair
        kLatePd = preDelayPad.out
        removeObject: stereoPairSafe.pair, kEarly, kLate
        @conv: srcMono, kEarlyPd
        wetE = conv.r
        @conv: dry, kLatePd
        wetL = conv.r
        # late part made wider still (M/S, side x1.5, out of place); early stays centred
        selectObject: wetL
        nL0 = Get number of samples
        wetLw = Create Sound from formula: "cc_wetLw", 2, 0, nL0 / sr, sr, "(object [wetL, 1, col] + object [wetL, 2, col]) / 2 + (if row = 1 then 1 else -1 fi) * 1.5 * (object [wetL, 1, col] - object [wetL, 2, col]) / 2"
        removeObject: wetL
        wetL = wetLw
        selectObject: wetL
        nL = Get number of samples
        selectObject: wetE
        nE = Get number of samples
        nW = max(nL, nE)
        wet = Create Sound from formula: "cc_wet", 2, 0, nW / sr, sr, "object [wetE, 1, col] + object [wetL, row, col]"
        # kernel for the figure (and feedback): early + late recombined
        selectObject: kLatePd
        kpd = Copy: "cc_kpd"
        Formula: "self + object [kEarlyPd, 1, col]"
        removeObject: wetE, wetL, kEarlyPd, kLatePd
        kpdNote = 1
        wetNote$ = "early " + fixed$(split_s * 1000, 0) + " ms centred (mono), late part as a wide complementary stereo pair"
    endif
    kerShow = kpd
endif

# stereoPair wrapper: computes its RMS normaliser before the formula uses it
procedure stereoPairSafe: .k, .depth
    selectObject: .k
    .n = Get number of channels
    if .n = 2
        .pair = Copy: "cc_kpair"
    else
        .dur = Get total duration
        random_initializeWithSeedUnsafelyButPredictably: 7
        .noise = Create Sound from formula: "cc_mod", 1, 0, .dur, sr, "randomGauss (0, 1)"
        random_initializeSafelyAndUnpredictably ()
        .smooth = Filter (pass Hann band): 0, 40, 20
        mr2 = Get root-mean-square: 0, 0
        mr2 = max(mr2, 1e-9)
        Formula: "min (max (self / mr2, -1), 1) * min (1, max (0, (x - 0.005) / 0.015))"
        removeObject: .noise
        modObj = .smooth
        srcK = .k
        .pair = Create Sound from formula: "cc_kpair", 2, 0, .dur, sr, "object [srcK, 1, col] * (1 + (if row = 1 then 1 else -1 fi) * pairDepth * object [modObj, 1, col])"
        removeObject: .smooth
    endif
endproc

# ---- optional feedback: finite, energy-controlled ----
fbNote$ = "off"
if feedbackPct > 0 and not (kerSilent or drySilent)
    selectObject: wet
    w1Rms = Get root-mean-square: 0, 0
    acc = wet
    prev = wet
    selectObject: kpd
    kpdN = Get number of channels
    fbDone = 0
    for it to feedbackIter
        g = (feedbackPct / 100) ^ it
        if g >= 0.001
            selectObject: acc
            accDur = Get total duration
            selectObject: kpd
            kDurNow = Get total duration
            if accDur + kDurNow <= 180
                @conv: prev, kpd
                nxt = conv.r
                nr = Get root-mean-square: 0, 0
                if nr > 1e-12
                    gainFb = w1Rms * g / nr
                    Formula: "self * gainFb"
                    selectObject: nxt
                    nN = Get number of samples
                    nNch = Get number of channels
                    selectObject: acc
                    nA = Get number of samples
                    nAch = Get number of channels
                    nOutCh = max(nNch, nAch)
                    sumObj = Create Sound from formula: "cc_fbsum", nOutCh, 0, max(nN, nA) / sr, sr, "object [acc, min (row, nAch), col] + object [nxt, min (row, nNch), col]"
                    if prev <> wet
                        removeObject: prev
                    endif
                    if acc <> wet
                        removeObject: acc
                    endif
                    acc = sumObj
                    prev = nxt
                    fbDone = it
                else
                    removeObject: nxt
                endif
            endif
        endif
    endfor
    if prev <> wet and prev <> acc
        removeObject: prev
    endif
    if acc <> wet
        removeObject: wet
        wet = acc
    endif
    fbNote$ = fixed$(feedbackPct, 0) + "%, " + string$(fbDone) + " of " + string$(feedbackIter) + " iteration(s) applied (each pass scaled to feedback^i x the first wet RMS)"
endif

# ---- wet as stereo; RMS match, wet gain, width, pan ----
selectObject: wet
wetCh = Get number of channels
wetRawRms = Get root-mean-square: 0, 0
if wetCh = 1
    selectObject: wet
    wdur = Get total duration
    w2 = Create Sound from formula: "cc_wet2", 2, 0, wdur, sr, "object [wet, 1, col]"
    removeObject: wet
    wet = w2
endif
matchGain = 1
matchNote$ = "off"
if rmsMatch and not (kerSilent or drySilent)
    selectObject: wet
    wdur = Get total duration
    regA = preDelayMs / 1000
    regB = min(wdur, regA + dryDur)
    wr = Get root-mean-square: regA, regB
    # below -140 dBFS RMS the wet is numerically silent: no matching at all;
    # otherwise the boost is capped at +60 dB (a kernel stored at -60 dB is
    # ordinary material and should still match)
    if wr <> undefined and wr > 1e-7
        matchGain = dryRms / wr
        capped$ = ""
        if matchGain > 1000
            matchGain = 1000
            capped$ = " (capped at +60 dB)"
        endif
        matchNote$ = "wet RMS matched to dry: " + fixed$(20 * log10(matchGain), 1) + " dB" + capped$
    else
        matchNote$ = "wet below -140 dBFS RMS (numerically silent): not matched"
    endif
endif
totalWetGain = matchGain * 10 ^ (wetGainDb / 20)
wW = wetWidth / 100
# M/S width and balance-law pan, computed OUT OF PLACE (an in-place
# Formula would read row 1 after overwriting it when computing row 2)
panTh = (wetPan / 100 + 1) * pi / 4
gPanL = sqrt(2) * cos(panTh)
gPanR = sqrt(2) * sin(panTh)
selectObject: wet
nWet0 = Get number of samples
wetP = Create Sound from formula: "cc_wetp", 2, 0, nWet0 / sr, sr, "totalWetGain * (if row = 1 then gPanL else gPanR fi) * ((object [wet, 1, col] + object [wet, 2, col]) / 2 + (if row = 1 then 1 else -1 fi) * wW * (object [wet, 1, col] - object [wet, 2, col]) / 2)"
removeObject: wet
wet = wetP

# ============================================================
# MIX (dry and wet stay separate until here)
# ============================================================
m = wetDry / 100
if mixLaw = 1
    dryG = 1 - m
    wetG = m
else
    dryG = cos(m * pi / 2)
    wetG = sin(m * pi / 2)
endif
if m >= 1
    dryG = 0
endif
if m <= 0
    wetG = 0
endif
selectObject: wet
nWet = Get number of samples
selectObject: dry
nDry = Get number of samples
# Keep a true dry-only render at the source length.  Otherwise retain the
# full convolution tail whenever the wet path is audible.
if wetG = 0
    nOut = nDry
else
    nOut = max(nWet, nDry)
endif
outName$ = srcName$ + "_" + replace_regex$(presetName$, "[^A-Za-z0-9]", "", 0)
out = Create Sound from formula: outName$, 2, 0, nOut / sr, sr, "dryG * object [dry, min (row, dryCh), col] + wetG * object [wet, row, col]"

# Fade only an actual wet tail that extends beyond the dry source.  This
# avoids altering the last 5 ms of a 0%-wet (dry-only) render.
if wetG > 0 and nWet > nDry
    Formula: "self * min (1, (xmax - x) / 0.005)"
endif

# ============================================================
# NORMALISATION + PROTECTION
# ============================================================
ceiling = 10 ^ (target_peak / 20)
ceiling = min(ceiling, 0.999)
peakRaw = Get absolute extremum: 0, 0, "None"
normNote$ = "none"
if peakRaw > 1e-9
    if normalization = 2
        Scale peak: ceiling
        normNote$ = "peak to " + fixed$(target_peak, 1) + " dBFS"
    elsif normalization = 3
        r0 = Get root-mean-square: 0, 0
        if r0 > 1e-12
            Formula: "self * (10 ^ (-18 / 20) / r0)"
            normNote$ = "RMS to -18 dBFS"
        endif
    endif
    pk = Get absolute extremum: 0, 0, "None"
    lim = ceiling
    if normalization = 1
        lim = 0.999
    endif
    if protect and pk > lim
        Formula: "self * (lim / pk)"
        normNote$ = normNote$ + "; clipping protection: " + fixed$(20 * log10(lim / pk), 1) + " dB"
    elsif pk > 1
        normNote$ = normNote$ + "; WARNING peak " + fixed$(pk, 2) + " (protection off)"
    endif
else
    normNote$ = "output silent; not normalised"
endif
selectObject: out
outDur = Get total duration
outPeak = Get absolute extremum: 0, 0, "None"
outRms = Get root-mean-square: 0, 0
selectObject: kerShow
kerDurFinal = Get total duration

# ============================================================
# REPORT
# ============================================================
spatialName$ = "Mono Wet"
if spatialMode = 2
    spatialName$ = "Stereo Wet"
elsif spatialMode = 3
    spatialName$ = "Wide Wet"
elsif spatialMode = 4
    spatialName$ = "Early Center / Late Wide"
endif
revTxt$ = "no"
if kReverse
    revTxt$ = "yes"
endif
lawTxt$ = "equal power"
if mixLaw = 1
    lawTxt$ = "linear"
endif
writeInfoLine: "=== Creative Convolution v", version$, " ==="
appendInfoLine: "Source:      ", srcName$, "  (", fixed$(dryDur, 3), " s, ", sr, " Hz, ", dryCh, " ch)"
appendInfoLine: "Kernel:      ", kerName$, "  (", fixed$(kerDurOrig, 3), " s, ", kerSrOrig, " Hz, ", kerCh, " ch)"
if resampled
    appendInfoLine: "             kernel resampled ", kerSrOrig, " -> ", sr, " Hz"
endif
if multiNote$ <> ""
    appendInfoLine: "             note:", multiNote$
endif
appendInfoLine: "Preset:      ", presetName$
appendInfoLine: "Kernel prep: ", fixed$(kStart, 1), "-", fixed$(kEnd, 1), "%, stretch ", stretchNote$, ", reverse ", revTxt$, ", fades ", fixed$(fi_s * 1000, 1), " / ", fixed$(fo_s * 1000, 1), " ms"
appendInfoLine: "             pre-delay ", fixed$(preDelayMs, 0), " ms; prepared kernel ", fixed$(kerDurFinal, 3), " s"
appendInfoLine: "Convolution: scaling ", scalingNote$, ", outside domain ", outside$
appendInfoLine: "Wet:         ", spatialName$, " - ", wetNote$
appendInfoLine: "             ", matchNote$, "; wet gain ", fixed$(wetGainDb, 1), " dB; width ", fixed$(wetWidth, 0), "%; pan ", fixed$(wetPan, 0)
appendInfoLine: "             feedback ", fbNote$
appendInfoLine: "Mix:         wet ", fixed$(wetDry, 0), "% (", lawTxt$, ": dry x", fixed$(dryG, 3), ", wet x", fixed$(wetG, 3), ")"
appendInfoLine: "Output:      ", outName$, "  ", fixed$(outDur, 3), " s stereo; ", normNote$
appendInfoLine: "             peak ", fixed$(outPeak, 3), " (", fixed$(20 * log10(max(outPeak, 1e-12)), 1), " dBFS), RMS ", fixed$(20 * log10(max(outRms, 1e-12)), 1), " dBFS"
if kerSilent or drySilent
    appendInfoLine: "WARNING: ", wetNote$
endif

if draw_visualisation
    @drawFigure
endif
removeObject: dry, ker, srcMono, wet
if kerShow <> ker
    removeObject: kerShow
endif
selectObject: out
if play_result
    Play
endif

# ============================================================
# FIGURE
# ============================================================
procedure niceStep: .span, .n
    .raw = .span / .n
    if .raw <= 0
        .raw = 1
    endif
    .p = 10 ^ floor(log10(.raw))
    .mm = .raw / .p
    if .mm < 1.5
        .step = .p
    elsif .mm < 3.5
        .step = 2 * .p
    elsif .mm < 7.5
        .step = 5 * .p
    else
        .step = 10 * .p
    endif
endproc

procedure railLabel: .y0, .y1, .name$
    Font size: 7
    Select inner viewport: 0.6, 7.7, .y0, .y1
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text special: -0.068, "centre", 0.5, "bottom", "Helvetica", 7, "90", .name$
endproc

procedure wavePanel: .obj, .y0, .y1, .tEnd, .title$, .rail$, .numbers
    # channel 1 blue, channel 2 orange on top of each other, explicit range
    selectObject: .obj
    .pk = Get absolute extremum: 0, 0, "None"
    .pk = max(.pk, 1e-9) * 1.05
    .nc = Get number of channels
    Select inner viewport: 0.6, 7.7, .y0, .y1
    Axes: 0, .tEnd, -.pk, .pk
    Paint rectangle: "{0.98, 0.98, 0.99}", 0, .tEnd, -.pk, .pk
    for zc to .nc
        selectObject: .obj
        .ch = Extract one channel: zc
        Select inner viewport: 0.6, 7.7, .y0, .y1
        .col$ = "{0.20, 0.40, 0.80}"
        if zc = 2
            .col$ = "{0.85, 0.35, 0.15}"
        endif
        Colour: .col$
        Draw: 0, .tEnd, -.pk, .pk, "no", "Curve"
        removeObject: .ch
    endfor
    Select inner viewport: 0.6, 7.7, .y0, .y1
    Axes: 0, .tEnd, -.pk, .pk
    Colour: "Black"
    Text top: "no", .title$
    Select inner viewport: 0.6, 7.7, .y0, .y1
    Axes: 0, .tEnd, -.pk, .pk
    Draw inner box
    @niceStep: .tEnd, 8
    if .numbers
        Marks bottom every: 1, niceStep.step, "yes", "yes", "no"
    else
        Marks bottom every: 1, niceStep.step, "no", "yes", "no"
    endif
    @railLabel: .y0, .y1, .rail$
endproc

procedure drawFigure
    Erase all
    Line width: 1
    Solid line
    .t0 = 0.10
    .t1 = 0.60
    Font size: 13
    Select inner viewport: 0.6, 7.7, .t0, .t1
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.72, "half", "##Creative Convolution — " + presetName$ + "##"
    Font size: 7
    Select inner viewport: 0.6, 7.7, .t0, .t1
    Axes: 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.42}"
    .sub$ = replace$(srcName$, "_", "\_ ", 0) + "  ×  " + replace$(kerName$, "_", "\_ ", 0)
    Text: 0.5, "centre", 0.18, "half", .sub$

    # all audio panels share the output time axis; the kernel has its own
    Font size: 7
    @wavePanel: dry, 0.95, 2.05, outDur, "##Source (dry)## — " + fixed$(dryDur, 2) + " s", "Source", 0
    .kt$ = "##Prepared kernel## — " + fixed$(kerDurFinal, 3) + " s after trim, stretch, reverse, fades"
    if preDelayMs > 0
        .kt$ = .kt$ + " and " + fixed$(preDelayMs, 0) + " ms pre-delay"
    endif
    .kt$ = .kt$ + " (own time axis)"
    @wavePanel: kerShow, 2.40, 3.50, kerDurFinal, .kt$, "Kernel", 1
    @wavePanel: wet, 3.95, 5.05, outDur, "##Wet convolution## — after RMS match, gain, width, pan; before the mix (blue L, orange R)", "Wet", 0
    @wavePanel: out, 5.40, 6.50, outDur, "##Output## — wet " + fixed$(wetDry, 0) + "\%  (" + lawTxt$ + "), " + normNote$, "Output", 1
    Select inner viewport: 0.6, 7.7, 5.40, 6.50
    Axes: 0, 1, 0, 1
    Text bottom: "yes", "Time (s)"

    # summary
    .s0 = 7.05
    .s1 = 8.05
    Font size: 7
    Select inner viewport: 0.6, 7.7, .s0, .s1
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Text: 0.012, "left", 0.85, "half", "##Summary##"
    Font size: 6
    Select inner viewport: 0.6, 7.7, .s0, .s1
    Axes: 0, 1, 0, 1
    Colour: "{0.25, 0.25, 0.28}"
    .l1$ = "Kernel " + fixed$(kStart, 0) + "-" + fixed$(kEnd, 0) + "\%  , stretch " + stretchNote$ + ", reverse " + revTxt$ + ", pre-delay " + fixed$(preDelayMs, 0) + " ms"
    Text: 0.012, "left", 0.64, "half", replace$(.l1$, "_", "\_ ", 0)
    .l2$ = spatialName$ + " — " + wetNote$ + "   |   width " + fixed$(wetWidth, 0) + "\%  , pan " + fixed$(wetPan, 0)
    Text: 0.012, "left", 0.45, "half", replace$(.l2$, "_", "\_ ", 0)
    .l3$ = matchNote$ + "   |   wet gain " + fixed$(wetGainDb, 1) + " dB   |   scaling " + scalingNote$ + "   |   feedback " + fbNote$
    Text: 0.012, "left", 0.26, "half", replace$(.l3$, "_", "\_ ", 0)
    .l4$ = "Output " + fixed$(outDur, 2) + " s, peak " + fixed$(20 * log10(max(outPeak, 1e-12)), 1) + " dBFS, RMS " + fixed$(20 * log10(max(outRms, 1e-12)), 1) + " dBFS"
    if resampled
        .l4$ = .l4$ + "   |   kernel resampled " + string$(kerSrOrig) + " -> " + string$(sr) + " Hz"
    endif
    Text: 0.012, "left", 0.08, "half", .l4$
    Select inner viewport: 0.6, 7.7, .s0, .s1
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 10
    Select outer viewport: 0, 8, 0, 8.15
endproc
