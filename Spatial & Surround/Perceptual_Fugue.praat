# ============================================================
# Praat AudioTools - Perceptual_Fugue.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.2 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Perceptual Fugue - Spatial audio composition engine.
#   A true polyphonic fugue where:
#     - Voices are PITCH-TRANSPOSED ENTRIES of the source (subject)
#     - Each voice carries a FIXED SPATIAL SIGNATURE (ITD/ILD/shadow)
#     - The subject is stated, answered, inverted, retrograded,
#       augmented, fragmented, and compressed in stretto
#
#   "A fugue where the voices are localization cues
#    and the subject is perceptual certainty."
#
#   VOICES (each has pitch identity + spatial identity):
#     V1 Dux    : original pitch, hard LEFT
#     V2 Comes  : answer interval, hard RIGHT (mirror of V1)
#     V3 Third  : octave below, center with polarity contradiction
#     V4 Fourth : answer low, diffuse reverberant field (optional)
#
#   FUGUE STRUCTURE:
#     I.   Exposition     : subject/answer/subject entries, 1 per subDur
#     II.  Episode        : head-motif fragments, transposed, passed
#     III. Middle Entries : retrograde + answer + augmented (2x)
#     IV.  Stretto        : compressed entries pile up
#     V.   Pedal/Cadence  : augmented drone, final subject, fade
#
# Changelog v2.2 (2026):
#   Speed-focused refactor. Output is the same construction —
#   placement, transposition, spatialization unchanged — just
#   considerably faster.
#
#   - SPEED: placeAt now mixes the fragment into the timeline
#     in-place via Formula (part) instead of Extract+Concat.
#     The original procedure rebuilt the entire timeline buffer
#     on every call (~20 calls per script run on multi-second
#     buffers). In-place mixing is dramatically faster.
#   - SPEED: makeDelay now writes the delayed signal into a
#     pre-allocated zero buffer via Formula (part) instead of
#     Concat+Extract. Called many times by applySpatial via
#     reverb taps and early reflections.
#   - SPEED: transposeByRatio's Resample precision is now tied
#     to a Speed_mode form parameter (Full/Balanced/Fast =
#     precision 50/20/10).
#   - FIX: Removed conflicting Scale intensity + Scale peak pair
#     at the end of the pipeline. Scale intensity was setting
#     RMS to a target dB, then Scale peak rescaled the peak —
#     making the intensity calibration meaningless. Now keeps
#     only Scale peak: 0.99 (predictable, no clipping). The
#     section_intensity_dB form field has been removed since
#     it no longer affects the output.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Category: Spatial & Immersive Audio
# ============================================================

# ============================================================
# INPUT VALIDATION
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
soundName$ = selected$("Sound")

selectObject: original
nChannels = Get number of channels
monoDur = Get total duration
monoSr = Get sampling frequency

if nChannels > 2
    exitScript: "Please select a mono or stereo Sound."
endif

if monoDur < 0.1
    exitScript: "Sound too short (minimum 0.1 s)."
endif

# ============================================================
# FORM
# ============================================================

form Perceptual Fugue v2.2
    comment === Preset ===
    optionmenu Preset: 2
        option Custom
        option Classical Fugue (3 voices, fifth)
        option Spectral Fugue (4 voices, storm)
        option Chamber Fugue (3 voices, subtle)
        option Stretto Study (4 voices, tight)
    comment === Fugue Structure ===
    optionmenu Answer_interval: 1
        option Fifth up
        option Fourth up
        option Octave up
        option Tritone
    integer Number_of_voices 3
    real Stretto_compression 0.75
    boolean Include_retrograde 1
    boolean Include_augmentation 1
    comment === Spatial Parameters ===
    positive Exposition_ITD_ms 3.0
    positive Exposition_ILD_factor 4.0
    positive Shadow_cutoff_Hz 500
    comment === Render speed (transpose resample precision) ===
    optionmenu Speed_mode: 2
        option Full Quality (precision 50)
        option Balanced (precision 20)
        option Fast (precision 10)
    comment === Output ===
    boolean Draw_visualization 1
endform

# ============================================================
# PRESETS & PARAMS
# ============================================================

if preset = 2
    presetName$ = "Classical Fugue"
    answer_interval = 1
    number_of_voices = 3
    stretto_compression = 0.75
    include_retrograde = 1
    include_augmentation = 1
    exposition_ITD_ms = 3.0
    exposition_ILD_factor = 4.0
    shadow_cutoff_Hz = 500
elsif preset = 3
    presetName$ = "Spectral Fugue"
    answer_interval = 4
    number_of_voices = 4
    stretto_compression = 0.5
    include_retrograde = 1
    include_augmentation = 1
    exposition_ITD_ms = 4.0
    exposition_ILD_factor = 5.0
    shadow_cutoff_Hz = 400
elsif preset = 4
    presetName$ = "Chamber Fugue"
    answer_interval = 1
    number_of_voices = 3
    stretto_compression = 0.85
    include_retrograde = 1
    include_augmentation = 0
    exposition_ITD_ms = 2.0
    exposition_ILD_factor = 2.5
    shadow_cutoff_Hz = 800
elsif preset = 5
    presetName$ = "Stretto Study"
    answer_interval = 1
    number_of_voices = 4
    stretto_compression = 0.4
    include_retrograde = 1
    include_augmentation = 1
    exposition_ITD_ms = 3.5
    exposition_ILD_factor = 4.5
    shadow_cutoff_Hz = 450
else
    presetName$ = "Custom"
endif

# Clamp
if number_of_voices < 3
    number_of_voices = 3
endif
if number_of_voices > 4
    number_of_voices = 4
endif
if stretto_compression < 0.2
    stretto_compression = 0.2
endif
if stretto_compression > 1.0
    stretto_compression = 1.0
endif

# Derived parameters
itdBase_s = exposition_ITD_ms / 1000
ildBase = exposition_ILD_factor
numV = number_of_voices
comp = stretto_compression

# v2.2: Resample precision tied to speed_mode.
# transposeByRatio is called several times for entries and head-
# motif transpositions. Lower precision is acceptable here —
# the script then crossfades, filters, and adds reverb to each
# voice, which masks small aliasing artifacts from the resample.
if speed_mode = 1
    resamplePrecision = 50
    speedStr$ = "Full Quality"
elsif speed_mode = 2
    resamplePrecision = 20
    speedStr$ = "Balanced"
else
    resamplePrecision = 10
    speedStr$ = "Fast"
endif

if answer_interval = 1
    answerRatio = 2 ^ (7/12)
    intervalName$ = "fifth up"
elsif answer_interval = 2
    answerRatio = 2 ^ (5/12)
    intervalName$ = "fourth up"
elsif answer_interval = 3
    answerRatio = 2.0
    intervalName$ = "octave up"
else
    answerRatio = 2 ^ (6/12)
    intervalName$ = "tritone"
endif

v1ratio = 1.0
v2ratio = answerRatio
v3ratio = 0.5
v4ratio = answerRatio * 0.5

# ============================================================
# SETUP
# ============================================================

selectObject: original
if nChannels = 2
    mono = Convert to mono
else
    mono = Copy: "mono_src"
endif

subDur = monoDur
monoSr = Get sampling frequency

expoEnd = 3 * subDur
episodeEnd = expoEnd + subDur
middleEnd = episodeEnd + 2 * subDur
strettoDur = (numV - 1) * comp * subDur + subDur
strettoEnd = middleEnd + strettoDur
pedalDur = 2.5 * subDur
totalDur = strettoEnd + pedalDur

clearinfo
writeInfoLine: "=================================================="
writeInfoLine: " PERCEPTUAL FUGUE v2.2"
writeInfoLine: "=================================================="
appendInfoLine: ""
appendInfoLine: "Source: ", soundName$, " | ", fixed$(monoDur, 3), " s | ", monoSr, " Hz"
appendInfoLine: "Voices: ", numV, " | Answer: ", intervalName$, " (x", fixed$(answerRatio, 3), ")"
appendInfoLine: "Speed:  ", speedStr$, " (resample precision=", resamplePrecision, ")"
appendInfoLine: "Output duration: ", fixed$(totalDur, 2), " s"
appendInfoLine: ""

# ============================================================
# PROCEDURES (Optimized)
# ============================================================

procedure mixAdd: .a, .b
    selectObject: .a
    Formula: "self + object[" + string$(.b) + "]"
endproc

procedure makeDelay: .snd, .delaySec
    # v2.2: writes the delayed signal into a pre-allocated zero
    # buffer via Formula (part). Old version did Concat + Extract,
    # which is much slower for long buffers. Behavior identical:
    # silence for the first .delaySec seconds, then the input,
    # truncated to the input's original duration.
    selectObject: .snd
    .sr = Get sampling frequency
    .dur = Get total duration
    if .delaySec <= 0
        delayResult = Copy: "dly"
    else
        .nSamples = round(.delaySec * .sr)
        if .nSamples < 1
            .nSamples = 1
        endif
        .startSec = .nSamples / .sr
        .sndIdStr$ = string$(.snd)
        .offsetStr$ = string$(.nSamples)

        delayResult = Create Sound from formula: "dly", 1, 0, .dur, .sr, "0"
        selectObject: delayResult
        # Write the delayed signal: at timeline col c >= .nSamples + 1,
        # read source col (c - .nSamples). Reads outside the source
        # return 0, which is fine for the trailing silence.
        Formula (part): .startSec, .dur, 1, 1,
            ... "object[" + .sndIdStr$ + ", 1, col - " + .offsetStr$ + "]"
    endif
endproc

procedure lowPassAsym: .snd, .cutHz
    selectObject: .snd
    filtResult = Filter (pass Hann band): 0, .cutHz, 100
endproc

procedure makeEarlyRef: .snd, .rvTime
    selectObject: .snd
    .sr = Get sampling frequency
    .dur = Get total duration
    .rt = .rvTime
    if .rt > 1.2
        .rt = 1.2
    endif
    if .rt < 0.05
        .rt = 0.05
    endif
    @makeDelay: .snd, .rt * 0.20
    .e1 = delayResult
    @makeDelay: .snd, .rt * 0.40
    .e2 = delayResult
    selectObject: .e2
    Formula: "self * 0.70"
    @mixAdd: .e1, .e2
    removeObject: .e2
    selectObject: .e1
    .eDur = Get total duration
    if .eDur >= .dur
        earlyResult = Extract part: 0, .dur, "rectangular", 1, "no"
        removeObject: .e1
    else
        .eext = .dur - .eDur
        .epad = Create Sound from formula: "pad", 1, 0, .eext, .sr, "0"
        selectObject: .e1
        plusObject: .epad
        earlyResult = Concatenate
        removeObject: .e1, .epad
    endif
    @makeDelay: .snd, .rt * 1.0
    .l1 = delayResult
    selectObject: .l1
    Formula: "self * 0.35"
    selectObject: .l1
    .lsmooth = Filter (pass Hann band): 0, 3500, 400
    removeObject: .l1
    selectObject: .lsmooth
    .lDur = Get total duration
    if .lDur >= .dur
        lateResult = Extract part: 0, .dur, "rectangular", 1, "no"
        removeObject: .lsmooth
    else
        .lext = .dur - .lDur
        .lpad = Create Sound from formula: "pad", 1, 0, .lext, .sr, "0"
        selectObject: .lsmooth
        plusObject: .lpad
        lateResult = Concatenate
        removeObject: .lsmooth, .lpad
    endif
endproc

procedure makeStereo: .left, .right
    selectObject: .left
    plusObject: .right
    stereoResult = Combine to stereo
endproc

procedure trimTo: .snd, .tDur
    selectObject: .snd
    .d = Get total duration
    .sr = Get sampling frequency
    if .d >= .tDur
        trimResult = Extract part: 0, .tDur, "rectangular", 1, "no"
    else
        .ext = .tDur - .d
        .pad = Create Sound from formula: "pad", 1, 0, .ext, .sr, "0"
        selectObject: .snd
        plusObject: .pad
        trimResult = Concatenate
        removeObject: .pad
    endif
endproc

procedure transposeByRatio: .snd, .ratio
    selectObject: .snd
    .intendedDur = Get total duration
    samplingFrequency = Get sampling frequency
    .tmp = Copy: "ps_tmp"
    selectObject: .tmp
    Override sampling frequency: round(samplingFrequency * .ratio)
    .shifted = Resample: samplingFrequency, resamplePrecision
    removeObject: .tmp
    @trimTo: .shifted, .intendedDur
    removeObject: .shifted
    transposeResult = trimResult
endproc

procedure augmentByRatio: .snd, .durRatio
    selectObject: .snd
    .dur = Get total duration
    .manip = To Manipulation: 0.01, 50, 800
    selectObject: .manip
    .dt = Extract duration tier
    selectObject: .dt
    Add point: .dur * 0.5, .durRatio
    selectObject: .manip
    plusObject: .dt
    Replace duration tier
    selectObject: .manip
    augmentResult = Get resynthesis (overlap-add)
    removeObject: .manip, .dt
endproc

procedure reverseSound: .snd
    selectObject: .snd
    reverseResult = Copy: "rev"
    selectObject: reverseResult
    Reverse
endproc

procedure applyFades: .snd
    selectObject: .snd
    .dur = Get total duration
    .fadeDur = 0.005
    if .dur > 2 * .fadeDur
        .fdStr$ = string$(.fadeDur)
        .durStr$ = string$(.dur)
        Formula: "if x < " + .fdStr$ + " then self * (0.5 - 0.5 * cos(pi * x / " + .fdStr$ + ")) else if x > " + .durStr$ + " - " + .fdStr$ + " then self * (0.5 - 0.5 * cos(pi * (" + .durStr$ + " - x) / " + .fdStr$ + ")) else self fi fi"
    endif
endproc

procedure placeAt: .timeline, .fragment, .startSec
    # v2.2: mixes the fragment into the timeline IN-PLACE via
    # Formula (part). Old version extracted before/middle/after
    # slices, mixed into middle, and concatenated — rebuilding
    # the full timeline buffer on every call. With ~20 placeAt
    # calls per script run on multi-second buffers, this was the
    # dominant runtime cost.
    #
    # Behavior identical to v2.1: the fragment is added to the
    # timeline starting at .startSec, clipped at the timeline
    # end. Returns placeAt_result = .timeline (same ID; the
    # caller's "vt1 = placeAt_result" is now a no-op rebind that
    # keeps existing call sites working unchanged).
    selectObject: .timeline
    .tDur = Get total duration
    .tSr = Get sampling frequency

    selectObject: .fragment
    .fDur = Get total duration
    .fNs = Get number of samples

    .endSec = .startSec + .fDur
    if .endSec > .tDur
        .endSec = .tDur
    endif
    if .startSec < 0
        .startSec = 0
    endif

    if .endSec > .startSec
        # Sample-index offset such that timeline col (offset+1)
        # reads fragment col 1. With Formula (part) starting at
        # .startSec, the first written col is round(.startSec *
        # sr) + 1, and we want fragment col 1 there, so offset =
        # round(.startSec * sr).
        .offsetCol = round(.startSec * .tSr)
        .offsetStr$ = string$(.offsetCol)
        .fragIdStr$ = string$(.fragment)

        selectObject: .timeline
        Formula (part): .startSec, .endSec, 1, 1,
            ... "self + object[" + .fragIdStr$ + ", 1, col - "
            ... + .offsetStr$ + "]"
    endif

    placeAt_result = .timeline
endproc

procedure applySpatial: .monoSnd
    selectObject: .monoSnd
    .dur = Get total duration
    .left = Copy: "sp_left"
    selectObject: .monoSnd
    .right = Copy: "sp_right"

    # ITD
    if sp_itd > 0
        @makeDelay: .right, sp_itd
        .rightDel = delayResult
        removeObject: .right
        .right = .rightDel
    elsif sp_itd < 0
        .absItd = abs(sp_itd)
        @makeDelay: .left, .absItd
        .leftDel = delayResult
        removeObject: .left
        .left = .leftDel
    endif

    # ILD
    if sp_ild > 1
        selectObject: .left
        Formula: "self * " + string$(sp_ild)
    elsif sp_ild < 1 and sp_ild > 0
        .rightBoost = 1 / sp_ild
        selectObject: .right
        Formula: "self * " + string$(.rightBoost)
    endif

    # Spectral shadow
    if sp_shSide = 1
        @lowPassAsym: .right, sp_shCut
        .rightFilt = filtResult
        removeObject: .right
        .right = .rightFilt
    elsif sp_shSide = -1
        @lowPassAsym: .left, sp_shCut
        .leftFilt = filtResult
        removeObject: .left
        .left = .leftFilt
    endif

    if sp_invRight = 1
        selectObject: .right
        Formula: "self * -1"
    endif

    # Reverb 
    if sp_rvWet > 0
        .rt = sp_rvTime
        if .rt > 1.2
            .rt = 1.2
        endif
        if .rt < 0.05
            .rt = 0.05
        endif
        @makeDelay: .monoSnd, .rt * 0.25
        .tap1 = delayResult
        @makeDelay: .monoSnd, .rt * 0.5
        .tap2 = delayResult
        selectObject: .tap2
        Formula: "self * 0.65"
        @makeDelay: .monoSnd, .rt * 1.0
        .tap3 = delayResult
        selectObject: .tap3
        Formula: "self * 0.35"
        @mixAdd: .tap1, .tap2
        @mixAdd: .tap1, .tap3
        removeObject: .tap2, .tap3
        selectObject: .tap1
        .wetSmooth = Filter (pass Hann band): 0, 5000, 300
        removeObject: .tap1
        @trimTo: .wetSmooth, .dur
        .wet = trimResult
        removeObject: .wetSmooth
        selectObject: .wet
        Formula: "self * " + string$(sp_rvWet)
        selectObject: .left
        Formula: "self * " + string$(1 - sp_rvWet)
        selectObject: .right
        Formula: "self * " + string$(1 - sp_rvWet)
        @mixAdd: .left, .wet
        @mixAdd: .right, .wet
        removeObject: .wet
    endif

    # Reflections
    if sp_refGain > 0
        @makeEarlyRef: .monoSnd, sp_rvTime
        .early = earlyResult
        .late = lateResult
        selectObject: .early
        Formula: "self * " + string$(sp_refGain)
        selectObject: .late
        Formula: "self * " + string$(sp_refGain * 0.6)
        @trimTo: .early, .dur
        .earlyT = trimResult
        removeObject: .early
        @trimTo: .late, .dur
        .lateT = trimResult
        removeObject: .late
        if sp_itd >= 0
            @mixAdd: .right, .earlyT
            @mixAdd: .left, .lateT
        else
            @mixAdd: .left, .earlyT
            @mixAdd: .right, .lateT
        endif
        removeObject: .earlyT, .lateT
    endif

    # Identity anchor 
    if sp_anchorGain > 0
        selectObject: .monoSnd
        .mid = Filter (pass Hann band): 500, 3000, 200
        selectObject: .mid
        Formula: "self * " + string$(sp_anchorGain)
        @trimTo: .mid, .dur
        .midTrimmed = trimResult
        removeObject: .mid
        @mixAdd: .left, .midTrimmed
        @mixAdd: .right, .midTrimmed
        removeObject: .midTrimmed
    endif

    @trimTo: .left, .dur
    .leftFinal = trimResult
    removeObject: .left
    @trimTo: .right, .dur
    .rightFinal = trimResult
    removeObject: .right
    @makeStereo: .leftFinal, .rightFinal
    spatialResult = stereoResult
    removeObject: .leftFinal, .rightFinal
endproc

# ============================================================
# CREATE SUBJECT MATERIALS (DRY)
# ============================================================

appendInfoLine: "Creating subject materials..."

selectObject: mono
subject = Copy: "subject"
@applyFades: subject

@transposeByRatio: subject, answerRatio
answer = transposeResult
@applyFades: answer

@transposeByRatio: subject, 0.5
subjectLow = transposeResult
@applyFades: subjectLow

if numV >= 4
    @transposeByRatio: subject, v4ratio
    answerLow = transposeResult
    @applyFades: answerLow
endif

if include_retrograde
    @reverseSound: subject
    counterSubject = reverseResult
    @applyFades: counterSubject
    selectObject: counterSubject
    retroSubject = Copy: "retro_sub"
else
    selectObject: subject
    counterSubject = Copy: "counter_sub"
    selectObject: counterSubject
    Formula: "self * (0.3 + 0.7 * (0.5 + 0.5 * sin(2 * pi * 2 * x)))"
    @applyFades: counterSubject
    selectObject: subject
    retroSubject = Copy: "retro_sub"
endif

selectObject: subject
headMotif = Extract part: 0, subDur * 0.5, "rectangular", 1, "no"
@applyFades: headMotif

if include_augmentation
    @augmentByRatio: subject, 2.0
    augSubject = augmentResult
    @applyFades: augSubject
else
    selectObject: subject
    augSubject = Copy: "aug_sub"
endif

if include_augmentation
    @augmentByRatio: subjectLow, 2.0
    pedalDrone = augmentResult
else
    selectObject: subjectLow
    pedalDrone = Copy: "pedal_drone"
endif
@applyFades: pedalDrone

@transposeByRatio: headMotif, answerRatio
headMotifT1 = transposeResult
@applyFades: headMotifT1

@transposeByRatio: headMotif, answerRatio * answerRatio
headMotifT2 = transposeResult
@applyFades: headMotifT2

# ============================================================
# BUILD VOICE TIMELINES
# ============================================================

appendInfoLine: "Building voice timelines..."
vt1 = Create Sound from formula: "vt1", 1, 0, totalDur, monoSr, "0"
vt2 = Create Sound from formula: "vt2", 1, 0, totalDur, monoSr, "0"
vt3 = Create Sound from formula: "vt3", 1, 0, totalDur, monoSr, "0"
if numV >= 4
    vt4 = Create Sound from formula: "vt4", 1, 0, totalDur, monoSr, "0"
endif

# ---- I. EXPOSITION ----
@placeAt: vt1, subject, 0
vt1 = placeAt_result
@placeAt: vt1, counterSubject, subDur
vt1 = placeAt_result

@lowPassAsym: subject, 800
.v1pad = filtResult
selectObject: .v1pad
Formula: "self * 0.4"
@applyFades: .v1pad
@placeAt: vt1, .v1pad, 2 * subDur
vt1 = placeAt_result
removeObject: .v1pad

@placeAt: vt2, answer, subDur
vt2 = placeAt_result
@placeAt: vt2, counterSubject, 2 * subDur
vt2 = placeAt_result

@placeAt: vt3, subjectLow, 2 * subDur
vt3 = placeAt_result

if numV >= 4
    @lowPassAsym: subject, 600
    .v4pad = filtResult
    selectObject: .v4pad
    Formula: "self * 0.3"
    @applyFades: .v4pad
    @placeAt: vt4, .v4pad, 2 * subDur
    vt4 = placeAt_result
    removeObject: .v4pad
endif

# ---- II. EPISODE ----
epStart = expoEnd
halfSub = subDur * 0.5

@placeAt: vt1, headMotif, epStart
vt1 = placeAt_result
@placeAt: vt2, headMotifT1, epStart + halfSub * 0.5
vt2 = placeAt_result
@placeAt: vt1, headMotifT2, epStart + halfSub
vt1 = placeAt_result
@placeAt: vt2, headMotif, epStart + halfSub * 1.5
vt2 = placeAt_result

@lowPassAsym: subjectLow, 500
.v3ep = filtResult
selectObject: .v3ep
Formula: "self * 0.3"
@applyFades: .v3ep
@placeAt: vt3, .v3ep, epStart
vt3 = placeAt_result
removeObject: .v3ep

# ---- III. MIDDLE ENTRIES ----
midStart = episodeEnd

@placeAt: vt1, retroSubject, midStart
vt1 = placeAt_result

@transposeByRatio: answer, answerRatio
.ansT2 = transposeResult
@applyFades: .ansT2
@placeAt: vt2, .ansT2, midStart + subDur
vt2 = placeAt_result
removeObject: .ansT2

@placeAt: vt3, augSubject, midStart
vt3 = placeAt_result

@placeAt: vt1, counterSubject, midStart + subDur
vt1 = placeAt_result

if numV >= 4
    @placeAt: vt4, answerLow, midStart + subDur
    vt4 = placeAt_result
endif

# ---- IV. STRETTO ----
strStart = middleEnd

@placeAt: vt1, subject, strStart
vt1 = placeAt_result
@placeAt: vt2, answer, strStart + comp * subDur
vt2 = placeAt_result
@placeAt: vt3, subjectLow, strStart + 2 * comp * subDur
vt3 = placeAt_result

if numV >= 4
    @placeAt: vt4, answerLow, strStart + 3 * comp * subDur
    vt4 = placeAt_result
endif

@placeAt: vt1, counterSubject, strStart + comp * subDur
vt1 = placeAt_result
@placeAt: vt2, counterSubject, strStart + 2 * comp * subDur
vt2 = placeAt_result

# ---- V. PEDAL + CADENCE ----
pedStart = strettoEnd

@placeAt: vt3, pedalDrone, pedStart
vt3 = placeAt_result

@lowPassAsym: answer, 600
.v2ped = filtResult
selectObject: .v2ped
Formula: "self * 0.35"
@applyFades: .v2ped
@placeAt: vt2, .v2ped, pedStart
vt2 = placeAt_result
removeObject: .v2ped

@placeAt: vt1, subject, pedStart + subDur
vt1 = placeAt_result

if numV >= 4
    @lowPassAsym: answerLow, 500
    .v4ped = filtResult
    selectObject: .v4ped
    Formula: "self * 0.25"
    @applyFades: .v4ped
    @placeAt: vt4, .v4ped, pedStart
    vt4 = placeAt_result
    removeObject: .v4ped
endif

fadeStart = totalDur - 0.5 * subDur
fadeStartStr$ = string$(fadeStart)
fadeLenStr$ = string$(0.5 * subDur)

selectObject: vt1
Formula: "if x > " + fadeStartStr$ + " then self * exp(-5 * (x - " + fadeStartStr$ + ") / " + fadeLenStr$ + ") else self fi"
selectObject: vt2
Formula: "if x > " + fadeStartStr$ + " then self * exp(-5 * (x - " + fadeStartStr$ + ") / " + fadeLenStr$ + ") else self fi"
selectObject: vt3
Formula: "if x > " + fadeStartStr$ + " then self * exp(-5 * (x - " + fadeStartStr$ + ") / " + fadeLenStr$ + ") else self fi"
if numV >= 4
    selectObject: vt4
    Formula: "if x > " + fadeStartStr$ + " then self * exp(-5 * (x - " + fadeStartStr$ + ") / " + fadeLenStr$ + ") else self fi"
endif

voiceGain = 1 / numV
selectObject: vt1
Formula: "self * " + string$(voiceGain)
selectObject: vt2
Formula: "self * " + string$(voiceGain)
selectObject: vt3
Formula: "self * " + string$(voiceGain)
if numV >= 4
    selectObject: vt4
    Formula: "self * " + string$(voiceGain)
endif

appendInfoLine: "Applying spatial processing..."

# ============================================================
# SPATIAL PROCESSING
# ============================================================

sp_itd = itdBase_s
sp_ild = ildBase
sp_shSide = 1
sp_shCut = shadow_cutoff_Hz
sp_rvTime = 0.35
sp_rvWet = 0.12
sp_refGain = 0.20
sp_anchorGain = 0.08
sp_invRight = 0

@applySpatial: vt1
stereoV1 = spatialResult

sp_itd = -itdBase_s
sp_ild = 1 / ildBase
sp_shSide = -1
sp_shCut = shadow_cutoff_Hz
sp_rvTime = 0.35
sp_rvWet = 0.12
sp_refGain = 0.20
sp_anchorGain = 0.08
sp_invRight = 0

@applySpatial: vt2
stereoV2 = spatialResult

sp_itd = itdBase_s * 0.33
sp_ild = 1.3
sp_shSide = 0
sp_shCut = shadow_cutoff_Hz
sp_rvTime = 0.5
sp_rvWet = 0.35
sp_refGain = 0.15
sp_anchorGain = 0.10
sp_invRight = 1

@applySpatial: vt3
stereoV3 = spatialResult

if numV >= 4
    sp_itd = 0
    sp_ild = 1.0
    sp_shSide = 0
    sp_shCut = shadow_cutoff_Hz
    sp_rvTime = 0.8
    sp_rvWet = 0.60
    sp_refGain = 0.10
    sp_anchorGain = 0.12
    sp_invRight = 0

    @applySpatial: vt4
    stereoV4 = spatialResult
endif

removeObject: vt1, vt2, vt3
if numV >= 4
    removeObject: vt4
endif

# ============================================================
# MIX VOICES
# ============================================================

selectObject: stereoV1
v1L = Extract one channel: 1
selectObject: stereoV1
v1R = Extract one channel: 2
removeObject: stereoV1

selectObject: stereoV2
v2L = Extract one channel: 1
selectObject: stereoV2
v2R = Extract one channel: 2
removeObject: stereoV2

selectObject: stereoV3
v3L = Extract one channel: 1
selectObject: stereoV3
v3R = Extract one channel: 2
removeObject: stereoV3

@mixAdd: v1L, v2L
@mixAdd: v1L, v3L
@mixAdd: v1R, v2R
@mixAdd: v1R, v3R
removeObject: v2L, v2R, v3L, v3R

if numV >= 4
    selectObject: stereoV4
    v4L = Extract one channel: 1
    selectObject: stereoV4
    v4R = Extract one channel: 2
    removeObject: stereoV4

    @mixAdd: v1L, v4L
    @mixAdd: v1R, v4R
    removeObject: v4L, v4R
endif

@makeStereo: v1L, v1R
fugue = stereoResult
removeObject: v1L, v1R

selectObject: fugue
Rename: soundName$ + "_perceptual_fugue"

# v2.2: Removed conflicting "Scale intensity: section_intensity_dB"
# that preceded "Scale peak: 0.99". The peak normalization
# would always overwrite the intensity setting, making the
# section_intensity_dB form parameter cosmetic. Now keeps only
# Scale peak — predictable, no clipping.
Scale peak: 0.99

fugueName$ = selected$("Sound")
fugueDur = Get total duration

removeObject: subject, answer, subjectLow, counterSubject
removeObject: headMotif, augSubject, retroSubject, pedalDrone
removeObject: headMotifT1, headMotifT2, mono
if numV >= 4
    removeObject: answerLow
endif

# ============================================================
# VISUALIZATION & OUTPUT
# ============================================================

if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    selectObject: fugue
    Extract one channel: 1
    vizLeft = selected("Sound")
    selectObject: fugue
    Extract one channel: 2
    vizRight = selected("Sound")
    selectObject: fugue
    vizSpec = To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"

    selectObject: vizLeft
    lMax = Get maximum: 0, 0, "Sinc70"
    lMin = Get minimum: 0, 0, "Sinc70"
    if lMax < 0
        lMax = -lMax
    endif
    if lMin < 0
        lMin = -lMin
    endif
    if lMin > lMax
        lMax = lMin
    endif

    selectObject: vizRight
    rMax = Get maximum: 0, 0, "Sinc70"
    rMin = Get minimum: 0, 0, "Sinc70"
    if rMax < 0
        rMax = -rMax
    endif
    if rMin < 0
        rMin = -rMin
    endif
    if rMin > rMax
        rMax = rMin
    endif

    if lMax > rMax
        ampMax = lMax * 1.1
    else
        ampMax = rMax * 1.1
    endif
    if ampMax < 0.001
        ampMax = 0.001
    endif

    sb1 = expoEnd
    sb2 = episodeEnd
    sb3 = middleEnd
    sb4 = strettoEnd

    Erase all
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.7, "half", "##Perceptual Fugue v2.2##"
    Font size: 8
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -0.2, "half", presetName$ + " | " + soundName$ + " | " + string$(numV) + " voices | " + intervalName$ + " | " + fixed$(fugueDur, 1) + " s"

    Select outer viewport: 0, 8, 0.55, 1.5
    Select inner viewport: 0.8, 7.6, 0.6, 1.45
    Axes: 0, fugueDur, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, fugueDur, -ampMax, ampMax
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: sb1, -ampMax, sb1, ampMax
    Draw line: sb2, -ampMax, sb2, ampMax
    Draw line: sb3, -ampMax, sb3, ampMax
    Draw line: sb4, -ampMax, sb4, ampMax
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: 0, 0, fugueDur, 0
    selectObject: vizLeft
    Colour: "{0.2, 0.45, 0.82}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Left"

    Select outer viewport: 0, 8, 1.6, 2.55
    Select inner viewport: 0.8, 7.6, 1.65, 2.5
    Axes: 0, fugueDur, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, fugueDur, -ampMax, ampMax
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: sb1, -ampMax, sb1, ampMax
    Draw line: sb2, -ampMax, sb2, ampMax
    Draw line: sb3, -ampMax, sb3, ampMax
    Draw line: sb4, -ampMax, sb4, ampMax
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: 0, 0, fugueDur, 0
    selectObject: vizRight
    Colour: "{0.82, 0.3, 0.2}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Right"

    Select outer viewport: 0, 8, 2.65, 4.0
    Select inner viewport: 0.8, 7.6, 2.7, 3.9
    Axes: 0, fugueDur, 0, 5000
    selectObject: vizSpec
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "yes"
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: sb1, 0, sb1, 5000
    Draw line: sb2, 0, sb2, 5000
    Draw line: sb3, 0, sb3, 5000
    Draw line: sb4, 0, sb4, 5000
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Freq (Hz)"
    Text bottom: "yes", "Time (s)"

    Font size: 8
    Colour: "Black"
    Text: sb1 / 2, "centre", 5500, "half", "EXPOSITION"
    Text: sb1 + (sb2 - sb1) / 2, "centre", 5500, "half", "EPISODE"
    Text: sb2 + (sb3 - sb2) / 2, "centre", 5500, "half", "MIDDLE ENTRIES"
    Text: sb3 + (sb4 - sb3) / 2, "centre", 5500, "half", "STRETTO"
    Text: sb4 + (fugueDur - sb4) / 2, "centre", 5500, "half", "PEDAL"

    removeObject: vizLeft, vizRight, vizSpec
endif

selectObject: fugue
Play

appendInfoLine: ""
appendInfoLine: "=================================================="
appendInfoLine: "  DONE"
appendInfoLine: "=================================================="
appendInfoLine: ""
appendInfoLine: "Output:   ", fugueName$
appendInfoLine: "Duration: ", fixed$(fugueDur, 2), " s (~", fixed$(fugueDur / subDur, 1), "x input)"
appendInfoLine: ""
appendInfoLine: "FUGUE SCORE:"
appendInfoLine: "  Voices:"
appendInfoLine: "    V1 Dux   : pitch x1.0, LEFT  (ITD +", fixed$(exposition_ITD_ms, 1), "ms)"
appendInfoLine: "    V2 Comes : pitch x", fixed$(answerRatio, 3), " (", intervalName$, "), RIGHT"
appendInfoLine: "    V3 Third : pitch x0.5 (8vb), center + polarity inv"
if numV >= 4
    appendInfoLine: "    V4 Fourth: pitch x", fixed$(v4ratio, 3), ", diffuse field"
endif
appendInfoLine: ""
appendInfoLine: "  Structure:"
appendInfoLine: "    I.   EXPOSITION     S -> A -> S(low)  [overlapping]"
appendInfoLine: "    II.  EPISODE        head motif x3 transpositions"
appendInfoLine: "    III. MIDDLE ENTRIES retrograde + answer^2 + augmented"
appendInfoLine: "    IV.  STRETTO        ", numV, " entries at ", fixed$(comp * 100, 0), "% compression"
appendInfoLine: "    V.   PEDAL          augmented drone cadence"
appendInfoLine: "=================================================="
