# ============================================================
# Praat AudioTools - Perceptual_Fugue.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.0 (2025)
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
#   OUTPUT DURATION: ~11x input (3 voices) or ~12x (4 voices).
#   Recommended input: 0.5 - 5.0 seconds, voiced content for
#   best PSOLA transposition; unvoiced content passes through.
#
#   PITCH TRANSPOSITION: PSOLA via Manipulation + PitchTier.
#   AUGMENTATION: PSOLA via DurationTier.
#   RETROGRADE: Reverse.
#   SPATIAL PROCESSING: ITD/ILD/shadow/reflection/reverb/anchor.
#   MIXING: Formula-based additive (true sum, not averaging).
#
# Changelog v2.0 (from v1.1):
#   - Complete rewrite: sequential sections -> timeline voice engine
#   - Voices now overlap as in real fugue polyphony
#   - PSOLA pitch transposition for answer/entries at intervals
#   - Augmentation, retrograde, fragmentation techniques
#   - Stretto with configurable compression ratio
#   - Per-voice spatial signatures maintained throughout
#   - Pedal point with augmented drone
#   - All v1.1 fixes retained (additive mixing, baked Formulas, etc.)
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
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

form Perceptual Fugue v2.0
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
    comment === Output ===
    positive Section_intensity_dB 65
    boolean Draw_visualization 1
endform

# ============================================================
# PRESETS
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
    section_intensity_dB = 65
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
    section_intensity_dB = 67
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
    section_intensity_dB = 63
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
    section_intensity_dB = 66
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
if exposition_ITD_ms < 0.5
    exposition_ITD_ms = 0.5
endif
if exposition_ITD_ms > 4.0
    exposition_ITD_ms = 4.0
endif
if exposition_ILD_factor < 1.0
    exposition_ILD_factor = 1.0
endif
if exposition_ILD_factor > 6.0
    exposition_ILD_factor = 6.0
endif

# Derived parameters
itdBase_s = exposition_ITD_ms / 1000
ildBase = exposition_ILD_factor
numV = number_of_voices
comp = stretto_compression

# Answer interval (equal temperament)
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

# Voice pitch ratios
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

# Timeline structure
expoEnd = 3 * subDur
episodeEnd = expoEnd + subDur
middleEnd = episodeEnd + 2 * subDur
strettoDur = (numV - 1) * comp * subDur + subDur
strettoEnd = middleEnd + strettoDur
pedalDur = 2.5 * subDur
totalDur = strettoEnd + pedalDur

clearinfo
writeInfoLine: "=================================================="
writeInfoLine: "  PERCEPTUAL FUGUE v2.0"
writeInfoLine: "  Polyphonic spatial fugue engine"
writeInfoLine: "=================================================="
appendInfoLine: ""
appendInfoLine: "Source: ", soundName$, " | ", fixed$(monoDur, 3), " s | ",
    ... monoSr, " Hz"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Voices: ", numV, " | Answer: ", intervalName$,
    ... " (x", fixed$(answerRatio, 3), ")"
appendInfoLine: "Stretto compression: ", fixed$(comp, 2)
appendInfoLine: "Output duration: ", fixed$(totalDur, 2), " s (~",
    ... fixed$(totalDur / subDur, 1), "x input)"
appendInfoLine: ""
appendInfoLine: "Spatial: ITD ", fixed$(exposition_ITD_ms, 1),
    ... "ms | ILD x", fixed$(ildBase, 1),
    ... " | Shadow ", fixed$(shadow_cutoff_Hz, 0), " Hz"
appendInfoLine: ""

# ============================================================
# PROCEDURES
# ============================================================

# --- Additive mixing (no averaging) ---
procedure mixAdd: .a, .b
    selectObject: .a
    Formula: "self + object[" + string$(.b) + "]"
endproc

# --- Delay via concatenation (silence first for ID order) ---
procedure makeDelay: .snd, .delaySec
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
        .padDur = .nSamples / .sr
        .sil = Create Sound from formula: "sil", 1, 0, .padDur, .sr, "0"
        selectObject: .snd
        .copy = Copy: "dly_src"
        selectObject: .sil
        plusObject: .copy
        .cat = Concatenate
        selectObject: .cat
        delayResult = Extract part: 0, .dur, "rectangular", 1, "no"
        removeObject: .cat, .sil, .copy
    endif
endproc

# --- Filters ---
procedure lowPassAsym: .snd, .cutHz
    selectObject: .snd
    filtResult = Filter (pass Hann band): 0, .cutHz, 100
endproc

procedure highPassAsym: .snd, .cutHz
    selectObject: .snd
    .sr = Get sampling frequency
    hpFiltResult = Filter (pass Hann band): .cutHz, .sr / 2, 200
endproc

# --- Reverb (3-tap, additive) ---
procedure makeReverb: .snd, .rvTime, .wetMix
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
    @makeDelay: .snd, .rt * 0.25
    .tap1 = delayResult
    @makeDelay: .snd, .rt * 0.5
    .tap2 = delayResult
    selectObject: .tap2
    Formula: "self * 0.65"
    @makeDelay: .snd, .rt * 1.0
    .tap3 = delayResult
    selectObject: .tap3
    Formula: "self * 0.35"
    @mixAdd: .tap1, .tap2
    @mixAdd: .tap1, .tap3
    removeObject: .tap2, .tap3
    selectObject: .tap1
    .wetSmooth = Filter (pass Hann band): 0, 5000, 300
    removeObject: .tap1
    selectObject: .wetSmooth
    .wetDur = Get total duration
    if .wetDur >= .dur
        .wet = Extract part: 0, .dur, "rectangular", 1, "no"
        removeObject: .wetSmooth
    else
        .ext = .dur - .wetDur
        .pad = Create Sound from formula: "pad", 1, 0, .ext, .sr, "0"
        selectObject: .wetSmooth
        plusObject: .pad
        .wet = Concatenate
        removeObject: .wetSmooth, .pad
    endif
    selectObject: .wet
    Formula: "self * " + string$(.wetMix)
    selectObject: .snd
    .dry = Copy: "dry_rv"
    selectObject: .dry
    Formula: "self * " + string$(1 - .wetMix)
    @mixAdd: .dry, .wet
    removeObject: .wet
    selectObject: .dry
    reverbResult = Copy: "rv_out"
    removeObject: .dry
endproc

# --- Early/late reflection layers ---
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

# --- Stereo combine ---
procedure makeStereo: .left, .right
    selectObject: .left
    plusObject: .right
    stereoResult = Combine to stereo
endproc

# --- Trim or extend to exact duration ---
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

# --- Identity anchor (500-3000 Hz midband) ---
procedure addAnchor: .snd, .anchorSrc, .anchorGain
    selectObject: .snd
    .dur = Get total duration
    selectObject: .anchorSrc
    .mid = Filter (pass Hann band): 500, 3000, 200
    selectObject: .mid
    Formula: "self * " + string$(.anchorGain)
    @trimTo: .mid, .dur
    .midTrimmed = trimResult
    removeObject: .mid
    selectObject: .snd
    anchorResult = Copy: "anch_out"
    @mixAdd: anchorResult, .midTrimmed
    removeObject: .midTrimmed
endproc

# --- PSOLA pitch transposition ---
procedure transposeByRatio: .snd, .ratio
    selectObject: .snd
    .dur = Get total duration
    .manip = To Manipulation: 0.01, 50, 800
    selectObject: .manip
    .pt = Extract pitch tier
    selectObject: .pt
    .np = Get number of points
    if .np > 0
        Multiply frequencies: 0, .dur, .ratio
    endif
    selectObject: .manip
    plusObject: .pt
    Replace pitch tier
    selectObject: .manip
    transposeResult = Get resynthesis (overlap-add)
    removeObject: .manip, .pt
endproc

# --- PSOLA duration scaling ---
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

# --- Retrograde ---
procedure reverseSound: .snd
    selectObject: .snd
    reverseResult = Copy: "rev"
    selectObject: reverseResult
    Reverse
endproc

# --- Apply 5ms raised-cosine fades to prevent clicks ---
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

# --- Place fragment into timeline at offset via Formula ---
procedure placeAt: .timeline, .fragment, .startSec
    selectObject: .fragment
    .fNx = Get number of samples
    selectObject: .timeline
    .sr = Get sampling frequency
    .startSamp = round(.startSec * .sr)
    .endSamp = .startSamp + .fNx
    Formula: "if col > " + string$(.startSamp) + " and col <= " + string$(.endSamp) + " then self + object[" + string$(.fragment) + ", col - " + string$(.startSamp) + "] else self fi"
endproc

# --- Spatial processing (reads global sp_* variables) ---
# sp_itd:  signed seconds (+ = left leads)
# sp_ild:  factor (> 1 = left louder)
# sp_shSide:  1 = shadow right, -1 = shadow left, 0 = none
# sp_shCut:  shadow LP cutoff Hz
# sp_rvTime, sp_rvWet:  reverb
# sp_refGain:  early reflection gain
# sp_anchorGain:  identity anchor gain
# sp_invRight:  1 = invert right channel polarity
# Output: spatialResult (stereo)
procedure applySpatial: .monoSnd
    selectObject: .monoSnd
    .dur = Get total duration
    selectObject: .monoSnd
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

    # Polarity inversion
    if sp_invRight = 1
        selectObject: .right
        Formula: "self * -1"
    endif

    # Reverb
    if sp_rvWet > 0
        @makeReverb: .left, sp_rvTime, sp_rvWet
        .leftRv = reverbResult
        removeObject: .left
        .left = .leftRv
        @makeReverb: .right, sp_rvTime, sp_rvWet
        .rightRv = reverbResult
        removeObject: .right
        .right = .rightRv
    endif

    # Reflections (opposite the direct)
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
        @addAnchor: .left, .monoSnd, sp_anchorGain
        .leftAnch = anchorResult
        removeObject: .left
        .left = .leftAnch
        @addAnchor: .right, .monoSnd, sp_anchorGain
        .rightAnch = anchorResult
        removeObject: .right
        .right = .rightAnch
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
# CREATE SUBJECT MATERIALS
# ============================================================

appendInfoLine: "Creating subject materials..."

# Subject (original)
selectObject: mono
subject = Copy: "subject"
@applyFades: subject

# Answer (transposed by interval)
@transposeByRatio: subject, answerRatio
answer = transposeResult
@applyFades: answer

# Subject low (octave below)
@transposeByRatio: subject, 0.5
subjectLow = transposeResult
@applyFades: subjectLow

# Answer low (answer octave below, for V4)
if numV >= 4
    @transposeByRatio: subject, v4ratio
    answerLow = transposeResult
    @applyFades: answerLow
endif

# Counter-subject (retrograde)
if include_retrograde
    @reverseSound: subject
    counterSubject = reverseResult
    @applyFades: counterSubject
else
    selectObject: subject
    counterSubject = Copy: "counter_sub"
    selectObject: counterSubject
    Formula: "self * (0.3 + 0.7 * (0.5 + 0.5 * sin(2 * pi * 2 * x)))"
    @applyFades: counterSubject
endif

# Head motif (first 50% of subject)
selectObject: subject
headMotif = Extract part: 0, subDur * 0.5, "rectangular", 1, "no"
@applyFades: headMotif

# Augmented subject (2x duration, for middle entries)
if include_augmentation
    @augmentByRatio: subject, 2.0
    augSubject = augmentResult
    @applyFades: augSubject
else
    selectObject: subject
    augSubject = Copy: "aug_sub"
endif

# Retrograde (for middle entries)
if include_retrograde
    @reverseSound: subject
    retroSubject = reverseResult
    @applyFades: retroSubject
else
    selectObject: subject
    retroSubject = Copy: "retro_sub"
endif

# Augmented drone (2x, pitched low, for pedal)
@transposeByRatio: subject, 0.5
.pedSrc = transposeResult
if include_augmentation
    @augmentByRatio: .pedSrc, 2.0
    pedalDrone = augmentResult
else
    selectObject: .pedSrc
    pedalDrone = Copy: "pedal_drone"
endif
removeObject: .pedSrc
@applyFades: pedalDrone

# Transposed head motifs for episode
@transposeByRatio: headMotif, answerRatio
headMotifT1 = transposeResult
@applyFades: headMotifT1

@transposeByRatio: headMotif, answerRatio * answerRatio
headMotifT2 = transposeResult
@applyFades: headMotifT2

appendInfoLine: "  Subject: ", fixed$(subDur, 3), " s"
appendInfoLine: "  Answer: x", fixed$(answerRatio, 3),
    ... " (", intervalName$, ")"
appendInfoLine: "  Augmented: ", fixed$(subDur * 2, 3), " s"
appendInfoLine: "  Materials created."
appendInfoLine: ""

# ============================================================
# BUILD VOICE TIMELINES
#
# Each voice gets a silent mono buffer of totalDur length.
# Entries are placed via placeAt (Formula-based, additive).
# ============================================================

appendInfoLine: "Building voice timelines..."
appendInfoLine: "  Total duration: ", fixed$(totalDur, 2), " s"

# Create empty timelines
vt1 = Create Sound from formula: "vt1", 1, 0, totalDur, monoSr, "0"
vt2 = Create Sound from formula: "vt2", 1, 0, totalDur, monoSr, "0"
vt3 = Create Sound from formula: "vt3", 1, 0, totalDur, monoSr, "0"
if numV >= 4
    vt4 = Create Sound from formula: "vt4", 1, 0, totalDur, monoSr, "0"
endif

# ---- I. EXPOSITION ----
# V1: subject @ 0, counter-sub @ subDur, sustained @ 2*subDur
# V2: answer @ subDur, counter-sub @ 2*subDur
# V3: subjectLow @ 2*subDur

appendInfoLine: "  I. Exposition..."

@placeAt: vt1, subject, 0
@placeAt: vt1, counterSubject, subDur

# Sustained pad for V1 at 2*subDur (LP filtered, quiet)
@lowPassAsym: subject, 800
.v1pad = filtResult
selectObject: .v1pad
Formula: "self * 0.4"
@applyFades: .v1pad
@placeAt: vt1, .v1pad, 2 * subDur
removeObject: .v1pad

@placeAt: vt2, answer, subDur
@placeAt: vt2, counterSubject, 2 * subDur

@placeAt: vt3, subjectLow, 2 * subDur

# V4 gets a quiet sustained entry during exposition (if present)
if numV >= 4
    @lowPassAsym: subject, 600
    .v4pad = filtResult
    selectObject: .v4pad
    Formula: "self * 0.3"
    @applyFades: .v4pad
    @placeAt: vt4, .v4pad, 2 * subDur
    removeObject: .v4pad
endif

# ---- II. EPISODE ----
# Head motif fragments transposed, passed V1->V2->V1->V2
# 0.5*subDur spacing

appendInfoLine: "  II. Episode..."

epStart = expoEnd
halfSub = subDur * 0.5

@placeAt: vt1, headMotif, epStart
@placeAt: vt2, headMotifT1, epStart + halfSub * 0.5
@placeAt: vt1, headMotifT2, epStart + halfSub
@placeAt: vt2, headMotif, epStart + halfSub * 1.5

# V3: quiet sustained note during episode
@lowPassAsym: subjectLow, 500
.v3ep = filtResult
selectObject: .v3ep
Formula: "self * 0.3"
@applyFades: .v3ep
@placeAt: vt3, .v3ep, epStart
removeObject: .v3ep

# ---- III. MIDDLE ENTRIES ----
# V1: retrograde @ middleStart
# V2: answer at new transposition @ middleStart + subDur
# V3: augmented subject spanning 2*subDur @ middleStart

appendInfoLine: "  III. Middle Entries..."

midStart = episodeEnd

@placeAt: vt1, retroSubject, midStart

# Answer transposed further (answer of the answer)
@transposeByRatio: answer, answerRatio
.ansT2 = transposeResult
@applyFades: .ansT2
@placeAt: vt2, .ansT2, midStart + subDur
removeObject: .ansT2

@placeAt: vt3, augSubject, midStart

# V1: counter-subject during V3's augmentation
@placeAt: vt1, counterSubject, midStart + subDur

# V4: enters with answer during middle (if present)
if numV >= 4
    @placeAt: vt4, answerLow, midStart + subDur
endif

# ---- IV. STRETTO ----
# Entries compress: V1 starts, others follow at comp*subDur intervals

appendInfoLine: "  IV. Stretto (compression: ", fixed$(comp, 2), ")..."

strStart = middleEnd

@placeAt: vt1, subject, strStart
@placeAt: vt2, answer, strStart + comp * subDur
@placeAt: vt3, subjectLow, strStart + 2 * comp * subDur

if numV >= 4
    @placeAt: vt4, answerLow, strStart + 3 * comp * subDur
endif

# Add counter-subject overlap for thickness
@placeAt: vt1, counterSubject, strStart + comp * subDur
@placeAt: vt2, counterSubject, strStart + 2 * comp * subDur

# ---- V. PEDAL + CADENCE ----
# V3: augmented drone
# V1: final subject statement
# Exponential fade to silence

appendInfoLine: "  V. Pedal + Cadence..."

pedStart = strettoEnd

# Pedal drone in V3
@placeAt: vt3, pedalDrone, pedStart

# V2: sustained quiet answer
@lowPassAsym: answer, 600
.v2ped = filtResult
selectObject: .v2ped
Formula: "self * 0.35"
@applyFades: .v2ped
@placeAt: vt2, .v2ped, pedStart
removeObject: .v2ped

# V1: final subject statement
@placeAt: vt1, subject, pedStart + subDur

# V4: quiet drone doubling
if numV >= 4
    @lowPassAsym: answerLow, 500
    .v4ped = filtResult
    selectObject: .v4ped
    Formula: "self * 0.25"
    @applyFades: .v4ped
    @placeAt: vt4, .v4ped, pedStart
    removeObject: .v4ped
endif

# Exponential fade on all voices over last 0.5*subDur
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

# Scale voice timelines before spatial processing
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

appendInfoLine: ""
appendInfoLine: "Timeline complete. Applying spatial processing..."

# ============================================================
# SPATIAL PROCESSING
#
# Voice 1 (Dux): hard LEFT
# Voice 2 (Comes): hard RIGHT (mirror)
# Voice 3 (Third): center, polarity contradiction, moderate reverb
# Voice 4 (Fourth): diffuse, heavy reverb
# ============================================================

# --- Voice 1: hard left ---
appendInfoLine: "  V1: hard left (ITD +",
    ... fixed$(exposition_ITD_ms, 1), "ms, ILD x",
    ... fixed$(ildBase, 1), ")"

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

# --- Voice 2: hard right (mirror of V1) ---
appendInfoLine: "  V2: hard right (ITD -",
    ... fixed$(exposition_ITD_ms, 1), "ms, ILD x",
    ... fixed$(1 / ildBase, 2), ")"

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

# --- Voice 3: center, polarity contradiction ---
appendInfoLine: "  V3: center-left (polarity inv, reverb 0.35)"

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

# --- Voice 4: diffuse field (if present) ---
if numV >= 4
    appendInfoLine: "  V4: diffuse (no ITD, reverb 0.60)"

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

# Clean up mono timelines
removeObject: vt1, vt2, vt3
if numV >= 4
    removeObject: vt4
endif

# ============================================================
# MIX VOICES
# ============================================================

appendInfoLine: ""
appendInfoLine: "Mixing ", numV, " voices..."

# Extract L/R from each voice, sum, recombine
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

# Sum into V1's channels
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
Scale peak: 0.99

fugueName$ = selected$("Sound")
fugueDur = Get total duration

# Clean up materials
removeObject: subject, answer, subjectLow, counterSubject
removeObject: headMotif, augSubject, retroSubject, pedalDrone
removeObject: headMotifT1, headMotifT2, mono
if numV >= 4
    removeObject: answerLow
endif

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    selectObject: fugue
    Extract one channel: 1
    vizLeft = selected("Sound")
    selectObject: fugue
    Extract one channel: 2
    vizRight = selected("Sound")

    # Amplitude range
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

    # Section boundaries
    sb1 = expoEnd
    sb2 = episodeEnd
    sb3 = middleEnd
    sb4 = strettoEnd

    Erase all

    # === TITLE ===
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.7, "half", "##Perceptual Fugue v2.0##"
    Font size: 8
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -0.2, "half",
        ... presetName$ + " | " + soundName$ + " | "
        ... + string$(numV) + " voices | "
        ... + intervalName$ + " | "
        ... + fixed$(fugueDur, 1) + " s"

    # === PANEL 1: Left channel ===
    Select outer viewport: 0, 8, 0.55, 1.5
    Select inner viewport: 0.8, 7.6, 0.6, 1.45
    Axes: 0, fugueDur, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, fugueDur, -ampMax, ampMax
    Colour: "{0.82, 0.82, 0.82}"
    Dotted line
    Draw line: sb1, -ampMax, sb1, ampMax
    Draw line: sb2, -ampMax, sb2, ampMax
    Draw line: sb3, -ampMax, sb3, ampMax
    Draw line: sb4, -ampMax, sb4, ampMax
    Solid line
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: 0, 0, fugueDur, 0
    selectObject: vizLeft
    Colour: "{0.2, 0.45, 0.82}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Left"
    Text top: "no", "Left Channel (V1 Dux dominant)"
    # Section labels
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.55, 0.55, 0.6}"
    Text: sb1 * 0.5 / fugueDur, "centre", 0.92, "half", "Expo"
    Text: (sb1 + sb2) * 0.5 / fugueDur, "centre", 0.92, "half", "Ep"
    Text: (sb2 + sb3) * 0.5 / fugueDur, "centre", 0.92, "half", "Mid"
    Text: (sb3 + sb4) * 0.5 / fugueDur, "centre", 0.92, "half", "Str"
    Text: (sb4 + fugueDur) * 0.5 / fugueDur, "centre", 0.92, "half", "Ped"

    # === PANEL 2: Right channel ===
    Select outer viewport: 0, 8, 1.55, 2.5
    Select inner viewport: 0.8, 7.6, 1.6, 2.45
    Axes: 0, fugueDur, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, fugueDur, -ampMax, ampMax
    Colour: "{0.82, 0.82, 0.82}"
    Dotted line
    Draw line: sb1, -ampMax, sb1, ampMax
    Draw line: sb2, -ampMax, sb2, ampMax
    Draw line: sb3, -ampMax, sb3, ampMax
    Draw line: sb4, -ampMax, sb4, ampMax
    Solid line
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: 0, 0, fugueDur, 0
    selectObject: vizRight
    Colour: "{0.82, 0.3, 0.2}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Right"
    Text top: "no", "Right Channel (V2 Comes dominant)"

    # === PANEL 3: L-R difference ===
    selectObject: vizLeft
    vizDiff = Copy: "LR_diff"
    selectObject: vizDiff
    Formula: "self - object[" + string$(vizRight) + "]"

    Select outer viewport: 0, 8, 2.55, 3.5
    Select inner viewport: 0.8, 7.6, 2.6, 3.45
    Axes: 0, fugueDur, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, fugueDur, -ampMax, ampMax
    Colour: "{0.82, 0.82, 0.82}"
    Dotted line
    Draw line: sb1, -ampMax, sb1, ampMax
    Draw line: sb2, -ampMax, sb2, ampMax
    Draw line: sb3, -ampMax, sb3, ampMax
    Draw line: sb4, -ampMax, sb4, ampMax
    Solid line
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: 0, 0, fugueDur, 0
    selectObject: vizDiff
    Colour: "{0.6, 0.2, 0.6}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "L-R"
    Text top: "no", "Interaural Difference (spatial polyphony)"
    removeObject: vizDiff

    # === PANEL 4: Spectrogram ===
    Select outer viewport: 0, 8, 3.55, 4.75
    Select inner viewport: 0.8, 7.6, 3.6, 4.7
    specMaxF = 8000
    if specMaxF > monoSr / 2 - 500
        specMaxF = monoSr / 2 - 500
    endif
    selectObject: fugue
    To Spectrogram: 0.03, specMaxF, 0.002, 20, "Gaussian"
    specGram = selected("Spectrogram")
    Paint: 0, 0, 0, specMaxF, 100, "yes", 50, 6, 0, "no"
    Axes: 0, fugueDur, 0, specMaxF
    Colour: "{1, 1, 1}"
    Dotted line
    Line width: 1.5
    Draw line: sb1, 0, sb1, specMaxF
    Draw line: sb2, 0, sb2, specMaxF
    Draw line: sb3, 0, sb3, specMaxF
    Draw line: sb4, 0, sb4, specMaxF
    Solid line
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text top: "no", "Spectrogram (voice entries visible as pitch layers)"
    Text bottom: "yes", "Time (s)"
    removeObject: specGram

    # === STATS ===
    Select outer viewport: 0, 8, 4.85, 5.95
    Select inner viewport: 0.5, 7.8, 4.9, 5.9
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.92, "half", "##Fugue Score##"
    Font size: 6
    Colour: "{0.3, 0.3, 0.35}"
    # Precompute conditional strings
    if numV >= 4
        v4text$ = " | V4: ans low, diffuse"
    else
        v4text$ = ""
    endif
    if include_retrograde
        retroText$ = "retrograde | "
    else
        retroText$ = ""
    endif
    if include_augmentation
        augText$ = "augment 2x | "
    else
        augText$ = ""
    endif
    Text: 0.02, "left", 0.78, "half",
        ... "V1 Dux: orig pitch, LEFT | V2 Comes: "
        ... + intervalName$ + " (x" + fixed$(answerRatio, 2)
        ... + "), RIGHT | V3: 8vb, center+inv"
        ... + v4text$
    Text: 0.02, "left", 0.62, "half",
        ... "I. Expo (0-" + fixed$(expoEnd, 1) + "s): entries 1/sub"
        ... + " | II. Episode (" + fixed$(expoEnd, 1) + "-"
        ... + fixed$(episodeEnd, 1) + "s): fragments"
        ... + " | III. Middle (" + fixed$(episodeEnd, 1) + "-"
        ... + fixed$(middleEnd, 1) + "s): retro+aug"
    Text: 0.02, "left", 0.46, "half",
        ... "IV. Stretto (" + fixed$(middleEnd, 1) + "-"
        ... + fixed$(strettoEnd, 1) + "s): comp="
        ... + fixed$(comp, 2)
        ... + " | V. Pedal (" + fixed$(strettoEnd, 1) + "-"
        ... + fixed$(totalDur, 1) + "s): drone+final"
    Text: 0.02, "left", 0.30, "half",
        ... "Techniques: PSOLA transpose | "
        ... + retroText$ + augText$
        ... + "fragmentation | stretto compress"
    Text: 0.02, "left", 0.14, "half",
        ... "Spatial: ITD " + fixed$(exposition_ITD_ms, 1)
        ... + "ms | ILD x" + fixed$(ildBase, 1)
        ... + " | Shadow " + fixed$(shadow_cutoff_Hz, 0)
        ... + "Hz | Additive mix | Anchor 500-3kHz"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # === LEGEND ===
    Select outer viewport: 0, 8, 6.0, 6.3
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.2, 0.45, 0.82}"
    Draw line: 0.02, 0.5, 0.06, 0.5
    Colour: "Black"
    Text: 0.07, "left", 0.5, "half", "Left (V1)"
    Colour: "{0.82, 0.3, 0.2}"
    Draw line: 0.18, 0.5, 0.22, 0.5
    Colour: "Black"
    Text: 0.23, "left", 0.5, "half", "Right (V2)"
    Colour: "{0.6, 0.2, 0.6}"
    Draw line: 0.36, 0.5, 0.40, 0.5
    Colour: "Black"
    Text: 0.41, "left", 0.5, "half", "L-R diff"
    Colour: "{0.82, 0.82, 0.82}"
    Dotted line
    Draw line: 0.55, 0.5, 0.59, 0.5
    Solid line
    Colour: "Black"
    Text: 0.60, "left", 0.5, "half", "Section bounds"
    Text: 0.78, "left", 0.5, "half", presetName$
    Font size: 10
    Colour: "Black"
    Line width: 1

    removeObject: vizLeft, vizRight
    appendInfoLine: "  Visualization complete."
endif

# ============================================================
# OUTPUT
# ============================================================

selectObject: fugue
Play

appendInfoLine: ""
appendInfoLine: "=================================================="
appendInfoLine: "  DONE"
appendInfoLine: "=================================================="
appendInfoLine: ""
appendInfoLine: "Output:   ", fugueName$
appendInfoLine: "Duration: ", fixed$(fugueDur, 2), " s (~",
    ... fixed$(fugueDur / subDur, 1), "x input)"
appendInfoLine: ""
appendInfoLine: "FUGUE SCORE:"
appendInfoLine: "  Voices:"
appendInfoLine: "    V1 Dux   : pitch x1.0, LEFT  (ITD +",
    ... fixed$(exposition_ITD_ms, 1), "ms)"
appendInfoLine: "    V2 Comes : pitch x", fixed$(answerRatio, 3),
    ... " (", intervalName$, "), RIGHT"
appendInfoLine: "    V3 Third : pitch x0.5 (8vb), center + polarity inv"
if numV >= 4
    appendInfoLine: "    V4 Fourth: pitch x", fixed$(v4ratio, 3),
        ... ", diffuse field"
endif
appendInfoLine: ""
appendInfoLine: "  Structure:"
appendInfoLine: "    I.   EXPOSITION     S -> A -> S(low)  [overlapping]"
appendInfoLine: "    II.  EPISODE        head motif x3 transpositions"
appendInfoLine: "    III. MIDDLE ENTRIES retrograde + answer^2 + augmented"
appendInfoLine: "    IV.  STRETTO        ",
    ... numV, " entries at ", fixed$(comp, 2), "x compression"
appendInfoLine: "    V.   PEDAL+CADENCE  drone + final subject -> fade"
appendInfoLine: ""
appendInfoLine: "Listen on headphones."
appendInfoLine: "The subject was perceptual certainty."
appendInfoLine: "It did not survive. But you heard it die."
