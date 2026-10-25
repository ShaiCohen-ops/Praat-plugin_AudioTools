# ============================================================
# Praat AudioTools - Audio_Quantizer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.4 (2026) - Learned Groove Transfer
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Onset-based elastic audio quantization for monophonic melodic
#   recordings (voice, flute and other single-line instruments).
#   Detected note onsets are moved toward a user-defined BPM grid by
#   ONE continuous, monotonic time deformation of the whole recording,
#   realised with a DurationTier and Praat's pitch-preserving PSOLA
#   (Manipulation -> overlap-add). Notes are never cut apart and
#   re-joined.
#
#   Pipeline:
#     Mono Sound -> onset analysis (intensity slope / vibrato-suppressed
#     spectral flux / hybrid, or a TextGrid point tier) -> BPM grid ->
#     collision-aware grid assignment -> strength + max-shift limits ->
#     exact chain-constraint solver (order, ratio limits, fixed ends) ->
#     piecewise DurationTier whose integral hits every onset target ->
#     numerical verification (Get target duration) -> overlap-add.
#
#   Fully native Praat. No files are read or written, no Python, no
#   shell. Only the quantized Sound (and, on request, a diagnostic
#   TextGrid) is left in the Objects list.
#
# Changelog v1.4 - Learned Groove Transfer:
#   - Grid type: Straight grid / Learned groove from a reference Sound /
#     Groove from a groove Table. A groove is a per-slot timing offset
#     (fraction of the grid interval) over a pattern of beats x units x
#     bars, so it transfers between tempi. Learned from a short reference
#     with the same detector: least-squares tempo fit, per-slot MEDIAN
#     over repetitions with spread, beat slots re-anchored to 0,
#     unobserved slots left straight, offsets limited to +-0.45 slot.
#     Groove strength (how far the grid moves toward the groove) is
#     separate from Quantization strength (how far the audio moves
#     toward the grid). Optional groove Table for reuse; click can follow
#     the groove grid or the straight grid; report lists the template and
#     the onsets' mean distance to the straight vs the groove grid.
#   - Verified (synthetic swing reference, 120 BPM, +-3 ms jitter, applied
#     at 90 BPM): learned offsets within 1.85 ms of the truth, 30/30
#     targets exactly on the groove grid, Table reuse identical (0 ms),
#     groove click within one sample of the groove grid. Straight-grid
#     results bit-identical to v1.3.
#   - Report states that Voice-safe limits apply to voiced sound (silence
#     0.25-3.0, unvoiced 0.80-1.25).
#
# Changelog v1.3 (fix release after code review):
#   - WSOLA end-of-file bug fixed: the last grain was clamped instead of
#     continuing the hop (15 ms error at the end of a neutral run). The
#     source is now zero-padded internally. Neutral WSOLA on the 68.7 s
#     sung take: max sample difference 2e-16 (exact up to rounding).
#   - WSOLA lag convention verified on noise with 9 known shifts in
#     -6..+6 ms: 0-sample error (6.4.06 and 7.0).
#   - WSOLA correlation now uses the 15 ms OVERLAP region only (the audio
#     already in the output). Measured on the take: voiced LSD 1.90 ->
#     1.84 dB, unvoiced 1.92 -> 1.73 dB, attack timing 4.3 -> 4.0 ms.
#   - Engine self-test (Advanced): runs the engine with every ratio = 1
#     and reports the sample-level difference from the input.
#   - Profile option: Voice-safe (default; ratios 0.80-1.25, attacks
#     40 ms) or Standard (0.65-1.55, 20 ms). Strength and shift stay on
#     the form. On the take: voiced LSD 1.62 vs 1.93 dB, at a cost in
#     how many onsets reach the grid exactly (43 vs 64 of 129).
#   - Measured output check: one-to-one, order-preserving matching (an
#     attack can no longer be counted for two targets).
#   - Note validation: the re-articulation rule now also applies without
#     a pitch (loud attacks only), a strong-evidence pass was added,
#     detection pitch ceiling raised to 2500 Hz (flute top octave), and
#     validation can be switched off in Advanced settings.
#
# Changelog v1.2 (prompted by audible distortion on a sung take; all
# figures below measured on that take, 68.7 s, 89 BPM):
#   - NEW DEFAULT ENGINE: native WSOLA (waveform-similarity overlap-add,
#     30 ms grains, C-level crossfades). Neutral PSOLA alone already
#     changed voiced frames by 4.5 dB log-spectral distance on this voice
#     (pitch range made no difference); WSOLA needs no pitch analysis and
#     copies untouched audio exactly. Same mapping: voiced distortion
#     5.0 dB (PSOLA) -> 1.9 dB (WSOLA). PSOLA remains selectable.
#   - WEIGHTED STRETCH: ratio(t) = 1 + k * w(t) per segment, with weights
#     silence 3 / voiced 1 / unvoiced 0.2 / attack zone 0, smoothed over
#     +-20 ms. Time changes go into rests and steady vowels first, never
#     into attacks, and only slightly into consonants and breath.
#     Exactness kept: D = S + k W (trapezoid integral), tier anchor
#     error still 0.
#   - NOTE-LEVEL VALIDATION of detected onsets (voicing onset, >= 0.8
#     semitone pitch step over one vibrato cycle, >= 9 dB
#     re-articulation, or a short unvoiced lead before voicing). On the
#     take, false onsets on vibrato and breath went 199 -> 118 onsets;
#     one sustained vibrato note 6 -> 1.
#   - GRID FIT DIAGNOSTIC: phase concentration of the onsets against the
#     grid and the beat, best-fitting offset, and a warning when the fit
#     is at chance level (the sung take: R 0.07 vs chance 0.09).
#
# Changelog v1.1:
#   - Optional Click Track: a stereo preview Sound (L = quantized audio,
#     R = metronome click) next to the mono result. Clicks follow the
#     mathematical grid only (an independent clock), never the onsets.
#     5 ms Hann-windowed tone bursts starting exactly on each grid time;
#     beats 2000 Hz, subdivisions 1500 Hz and quieter.
#   - Maximum onset shift 0 = Auto (half the grid interval, so every
#     onset can reach its nearest grid point); Auto is the new default.
#   - Measured output check: after resynthesis the same detector is run
#     on the quantized Sound and every target is matched to the attack
#     actually found there (report + green marks in the figure).
#   - Collision report distinguishes "unmoved" from "nudged by
#     neighbours"; output length difference reported in samples.
#   - Onset detector refactored into one procedure (unchanged numerics).
#
# Conventions:
#   * BPM is always the QUARTER-NOTE tempo.
#   * Report times are RELATIVE to the start of the Sound (seconds);
#     internal arithmetic uses absolute Praat times.
#   * "Onset sensitivity" s sets the adaptive threshold as
#       threshold = local mean (+-100 ms) + (3 / s) x robust spread
#     so a HIGHER value gives MORE onsets (monotonic). Note this is the
#     inverse sense of the "Sensitivity" multiplier in Tempo Curve (IOI)
#     Estimator, where a higher value raises the threshold.
#   * Local time ratio = output duration / input duration
#     (>1 expansion, <1 compression), as in Praat's DurationTier.
#
# Reference implementations studied (none is called at run time):
#   Analysis/Tempo Curve (IOI) Estimator.praat     - ODFs, MAD thresholds
#   Analysis/Multi-Band_Onset_Detector.praat       - per-band positive flux
#   Time & Granular/Rhythmatist.praat              - BPM grid arithmetic
#   Time & Granular/Constraint-Based_Duration_Control.praat
#                                                  - piecewise DurationTier
#   AI & Adaptive/Neural_Phonetic_Speed_Mapper.praat - PSOLA tail, peak guard
# ============================================================

form Audio Quantizer v1.4
    comment Musical grid (BPM = quarter-note tempo)
    positive Tempo_BPM 120
    optionmenu Grid_division 2
        option Quarter notes (1/4)
        option Eighth notes (1/8)
        option Sixteenth notes (1/16)
        option Eighth-note triplets (1/8T)
        option Sixteenth-note triplets (1/16T)
    optionmenu Grid_type 1
        option Straight grid
        option Learned groove from a reference Sound
        option Groove from a groove Table
    comment Quantization (max shift 0 = auto: half the grid interval)
    real Quantization_strength_percent 100
    real Maximum_onset_shift_ms 0
    optionmenu Grid_origin 1
        option First detected onset
        option Beginning of Sound
        option Manual offset
    real Grid_offset_ms 0
    comment Onset analysis
    optionmenu Onset_detection 3
        option Automatic - Intensity slope
        option Automatic - Spectral flux
        option Automatic - Hybrid
        option Selected TextGrid (point tier: onsets)
    positive Onset_sensitivity 1.5
    optionmenu Resynthesis 1
        option WSOLA (waveform, no pitch analysis)
        option PSOLA (Praat Manipulation)
    optionmenu Profile 1
        option Voice-safe (ratios 0.80-1.25, attacks 40 ms)
        option Standard (ratios 0.65-1.55, attacks 20 ms)
    comment Output
    optionmenu Click_track 1
        option Off
        option Quarter-note beats
        option Grid subdivision (beats accented)
    boolean Play_result 1
    boolean Keep_onset_TextGrid 0
    boolean Show_analysis_report 1
    boolean Draw_visualization 1
    boolean Advanced_settings 0
endform

# ------------------------------------------------------------
# Advanced settings (second dialog keeps the main form short).
# Variables are initialised first so every path has them.
# ------------------------------------------------------------
minimum_onset_separation_ms = 80
pitch_floor_Hz = 75
pitch_ceiling_Hz = 600
# Profile sets the engine-side limits; the Advanced dialog opens
# pre-filled with them (editing there makes them custom). Strength and
# maximum shift stay on the main form, under the user's control.
if profile = 1
    minimum_local_time_ratio = 0.80
    maximum_local_time_ratio = 1.25
    attack_protection_ms = 40
    profileLabel$ = "Voice-safe"
else
    minimum_local_time_ratio = 0.65
    maximum_local_time_ratio = 1.55
    attack_protection_ms = 20
    profileLabel$ = "Standard"
endif
click_level = 0.25
engine_self_test = 0
note_validation = 1

if advanced_settings
    beginPause: "Audio Quantizer - advanced settings"
        comment: "Onset detection"
        positive: "Minimum onset separation ms", string$(minimum_onset_separation_ms)
        comment: "PSOLA resynthesis pitch range"
        positive: "Pitch floor Hz", string$(pitch_floor_Hz)
        positive: "Pitch ceiling Hz", string$(pitch_ceiling_Hz)
        comment: "Time warping (output / input duration)"
        positive: "Minimum local time ratio", string$(minimum_local_time_ratio)
        positive: "Maximum local time ratio", string$(maximum_local_time_ratio)
        real: "Attack protection ms", string$(attack_protection_ms)
        comment: "Click track"
        positive: "Click level", string$(click_level)
        boolean: "Note validation", note_validation
        comment: "Diagnostics"
        boolean: "Engine self test", engine_self_test
    clicked = endPause: "Cancel", "Continue", 2, 1
    if clicked = 1
        exitScript: "Cancelled."
    endif
    profileLabel$ = profileLabel$ + " (advanced settings reviewed)"
endif

# ============================================================
# 1. INPUT AND PARAMETER VALIDATION  (no objects created yet)
# ============================================================
useTextGrid = (onset_detection = 4)

refSound = 0
grooveTableIn = 0
if grid_type = 2
    if numberOfSelected("Sound") <> 2
        exitScript: "Grid type = Learned groove: select exactly TWO Sounds - the target (voice / flute) and a short" + newline$ +
        ... "rhythmic reference (1-4 bars). You choose which one is the reference in the next dialog."
    endif
    snd1 = selected("Sound", 1)
    snd2 = selected("Sound", 2)
    snd1$ = selected$("Sound", 1)
    snd2$ = selected$("Sound", 2)
    selectObject: snd1
    d1 = Get total duration
    selectObject: snd2
    d2 = Get total duration
    # default: the shorter Sound is the reference
    refChoice = 2
    if d1 < d2
        refChoice = 1
    endif
    sound = snd1
    soundName$ = snd1$
else
    if numberOfSelected("Sound") <> 1
        exitScript: "Please select exactly one mono Sound."
    endif
    sound = selected("Sound")
    soundName$ = selected$("Sound")
    if grid_type = 3
        if numberOfSelected("Table") <> 1
            exitScript: "Grid type = Groove from a groove Table: select the target Sound AND one groove Table" + newline$ +
            ... "(created earlier by this script with Keep groove Table)."
        endif
        grooveTableIn = selected("Table")
    endif
endif

textGridIn = 0
if useTextGrid
    if numberOfSelected("TextGrid") <> 1
        exitScript: "Onset detection = Selected TextGrid: select exactly one Sound AND one TextGrid" + newline$ +
        ... "(the TextGrid must contain a point tier, preferably named ""onsets"")."
    endif
    textGridIn = selected("TextGrid")
endif

# ------------------------------------------------------------
# Groove dialog (grid types 2 and 3). Defaults are pre-set so a
# headless run that auto-continues the dialog still works.
# ------------------------------------------------------------
reference_tempo_BPM = tempo_BPM
reference_downbeat = 1
reference_offset_ms = 0
beats_per_bar = 4
pattern_length_bars = 1
groove_strength_percent = 100
click_follows = 1
keep_groove_Table = 0
if grid_type = 2
    reference_sound = refChoice
    beginPause: "Audio Quantizer - learned groove"
        comment: "Which selected Sound is the rhythmic REFERENCE (the other is the target)?"
        optionmenu: "Reference sound", reference_sound
            option: snd1$
            option: snd2$
        positive: "Reference tempo BPM", string$(reference_tempo_BPM)
        optionmenu: "Reference downbeat", reference_downbeat
            option: "First detected onset"
            option: "Manual offset"
        real: "Reference offset ms", string$(reference_offset_ms)
        natural: "Beats per bar", string$(beats_per_bar)
        natural: "Pattern length bars", string$(pattern_length_bars)
        real: "Groove strength percent", string$(groove_strength_percent)
        optionmenu: "Click follows", click_follows
            option: "Groove grid"
            option: "Straight grid"
        boolean: "Keep groove Table", keep_groove_Table
    clickedG = endPause: "Cancel", "Continue", 2, 1
    if clickedG = 1
        exitScript: "Cancelled."
    endif
    if reference_sound = 1
        refSound = snd1
        refName$ = snd1$
        sound = snd2
        soundName$ = snd2$
    else
        refSound = snd2
        refName$ = snd2$
        sound = snd1
        soundName$ = snd1$
    endif
elsif grid_type = 3
    beginPause: "Audio Quantizer - groove Table"
        real: "Groove strength percent", string$(groove_strength_percent)
        optionmenu: "Click follows", click_follows
            option: "Groove grid"
            option: "Straight grid"
    clickedG = endPause: "Cancel", "Continue", 2, 1
    if clickedG = 1
        exitScript: "Cancelled."
    endif
endif
if groove_strength_percent < 0 or groove_strength_percent > 100
    exitScript: "Groove strength must be between 0 and 100 %."
endif
if grid_type = 2
    selectObject: refSound
    refCh = Get number of channels
    refDur = Get total duration
    if refCh <> 1
        exitScript: "The reference Sound must be mono."
    endif
    if refDur < 0.5
        exitScript: "The reference Sound is too short (" + fixed$(refDur, 2) + " s)."
    endif
    if reference_tempo_BPM < 20 or reference_tempo_BPM > 300
        exitScript: "Reference tempo must be between 20 and 300 BPM."
    endif
    if beats_per_bar > 16 or pattern_length_bars > 8
        exitScript: "Beats per bar must be at most 16 and pattern length at most 8 bars."
    endif
endif

selectObject: sound
sTmin = Get start time
sTmax = Get end time
sDur = sTmax - sTmin
sr = Get sampling frequency
nCh = Get number of channels

if nCh <> 1
    exitScript: "The Sound has " + string$(nCh) + " channels. Audio Quantizer v1.0 needs a mono Sound" + newline$ +
    ... "(use Convert to mono or Extract one channel first)."
endif
if sDur < 0.5
    exitScript: "The Sound is too short (" + fixed$(sDur, 3) + " s). At least 0.5 s is needed."
endif
inPeak = Get absolute extremum: 0, 0, "None"
inRms = Get root-mean-square: 0, 0
if inPeak = undefined or inRms = undefined
    exitScript: "The Sound contains no valid samples."
endif
if inPeak < 1e-5 or inRms < 1e-6
    exitScript: "The Sound is silent or nearly silent (peak " + fixed$(inPeak, 7) + "). Nothing to quantize."
endif

if tempo_BPM < 20 or tempo_BPM > 300
    exitScript: "Tempo must be between 20 and 300 BPM."
endif
if quantization_strength_percent < 0 or quantization_strength_percent > 100
    exitScript: "Quantization strength must be between 0 and 100 %."
endif
if maximum_onset_shift_ms < 0
    exitScript: "Maximum onset shift cannot be negative."
endif
if pitch_floor_Hz < 30
    exitScript: "Pitch floor must be at least 30 Hz."
endif
if pitch_ceiling_Hz <= pitch_floor_Hz * 1.5
    exitScript: "Pitch ceiling must be well above the pitch floor (at least 1.5x)."
endif
if pitch_ceiling_Hz >= sr / 2
    exitScript: "Pitch ceiling must be below the Nyquist frequency (" + fixed$(sr / 2, 0) + " Hz)."
endif
if sDur < 3 / pitch_floor_Hz + 0.05
    exitScript: "The Sound is too short for PSOLA at pitch floor " + fixed$(pitch_floor_Hz, 0) + " Hz."
endif
if minimum_local_time_ratio < 0.2 or minimum_local_time_ratio > 1
    exitScript: "Minimum local time ratio must lie between 0.2 and 1."
endif
if maximum_local_time_ratio < 1 or maximum_local_time_ratio > 5
    exitScript: "Maximum local time ratio must lie between 1 and 5."
endif
if minimum_onset_separation_ms < 10
    exitScript: "Minimum onset separation must be at least 10 ms."
endif
if attack_protection_ms < 0
    attack_protection_ms = 0
endif
if click_level > 1
    click_level = 1
endif

# Grid geometry (seconds). Units per quarter note: 1, 2, 4, 3, 6.
if grid_division = 1
    unitsPerBeat = 1
    divLabel$ = "4th"
    divLong$ = "quarter notes (1/4)"
elsif grid_division = 2
    unitsPerBeat = 2
    divLabel$ = "8th"
    divLong$ = "eighth notes (1/8)"
elsif grid_division = 3
    unitsPerBeat = 4
    divLabel$ = "16th"
    divLong$ = "sixteenth notes (1/16)"
elsif grid_division = 4
    unitsPerBeat = 3
    divLabel$ = "8T"
    divLong$ = "eighth-note triplets (1/8T)"
else
    unitsPerBeat = 6
    divLabel$ = "16T"
    divLong$ = "sixteenth-note triplets (1/16T)"
endif
beatSec = 60 / tempo_BPM
gridT = 60 / (tempo_BPM * unitsPerBeat)
if gridT < 0.03
    exitScript: "Grid interval " + fixed$(gridT * 1000, 1) + " ms is too fine to quantize reliably (minimum 30 ms)."
endif

strength = quantization_strength_percent / 100
if maximum_onset_shift_ms = 0
    # Auto: the nearest grid point is at most T/2 away (+0.5 ms margin).
    maxShift = gridT / 2 + 0.0005
    shiftLabel$ = "auto " + fixed$(maxShift * 1000, 1) + " ms"
else
    maxShift = maximum_onset_shift_ms / 1000
    shiftLabel$ = fixed$(maximum_onset_shift_ms, 1) + " ms"
endif
minSep = minimum_onset_separation_ms / 1000
rMin = minimum_local_time_ratio
rMax = maximum_local_time_ratio
attackProtect = attack_protection_ms / 1000
gridOffset = grid_offset_ms / 1000
if grid_origin = 3 and (gridOffset < 0 or gridOffset >= sDur)
    exitScript: "Grid offset must lie inside the Sound (0 to " + fixed$(sDur * 1000, 0) + " ms)."
endif

# Analysis hop: 5 ms, coarsened only for very long files.
hop = 0.005
if sDur > 600
    hop = 0.010
endif

warnings$ = ""
nWarn = 0
nCandidates = 0

# ============================================================
# HELPER PROCEDURES
# ============================================================
procedure median: .v#
    .n = size(.v#)
    if .n = 0
        .result = 0
    else
        .s# = sort#(.v#)
        if .n mod 2 = 1
            .result = .s#[(.n + 1) / 2]
        else
            .result = (.s#[.n / 2] + .s#[.n / 2 + 1]) / 2
        endif
    endif
endproc

procedure percentile: .v#, .p
    .n = size(.v#)
    if .n = 0
        .result = 0
    else
        .s# = sort#(.v#)
        .k = max(1, min(.n, round(.p * .n)))
        .result = .s#[.k]
    endif
endproc

# Linear interpolation of a frame vector (first frame time t1, step dt)
# at absolute time t. Clamped at the ends.
procedure interpFrames: .v#, .t1, .dt, .t
    .n = size(.v#)
    .pos = (.t - .t1) / .dt + 1
    if .pos <= 1
        .result = .v#[1]
    elsif .pos >= .n
        .result = .v#[.n]
    else
        .i = floor(.pos)
        .f = .pos - .i
        .result = .v#[.i] * (1 - .f) + .v#[.i + 1] * .f
    endif
endproc

procedure padLeft: .s$, .w
    .result$ = .s$
    while length(.result$) < .w
        .result$ = " " + .result$
    endwhile
endproc

# Signed ms string with fixed precision; avoids "-0.0".
procedure msStr: .sec
    .v = round(.sec * 10000) / 10
    if abs(.v) < 0.05
        .result$ = "0.0"
    else
        .result$ = fixed$(.v, 1)
        if .v > 0
            .result$ = "+" + .result$
        endif
    endif
endproc

# Stretchability weight at time t inside segment j (see section 9b).
# Linear interpolation of the smoothed weights; class of nearest frame;
# zero inside the attack zones of the onsets bounding the segment.
procedure weightAt: .t, .j
    .pos = (.t - sTmin) / wDt + 1
    .k = max(1, min(nW - 1, floor(.pos)))
    .f = max(0, min(1, .pos - .k))
    .w = wFin#[.k] * (1 - .f) + wFin#[.k + 1] * .f
    .kn = max(1, min(nW, round(.pos)))
    .c = wCls#[.kn]
    .w = min(.w, .c)
    if .j > 1
        if .t <= x#[.j] + attackProtect
            .w = 0
        endif
    endif
    if .j < nSeg
        if .t >= x#[.j + 1] - 0.010
            .w = 0
        endif
    endif
endproc

# ------------------------------------------------------------
# WSOLA resynthesis (waveform-similarity overlap-add).
#   Grains of 30 ms (even sample count N), hop N/2, complementary
#   crossfades done by Praat's "Concatenate with overlap" (exact
#   reconstruction verified: 5.6e-17). For every output grain the
#   nominal source position follows the inverse of the DurationTier
#   mapping. Where it equals the natural continuation of the previous
#   grain (local ratio 1) the source is copied unchanged; elsewhere the
#   grain start is searched within +-6 ms of nominal for the best
#   cross-correlation, over the OVERLAP REGION only (15 ms), with the
#   natural continuation - i.e. with the audio already written to the
#   output - so waveforms join in phase. No pitch analysis is involved.
#   Lag convention verified on noise with 9 known shifts: 0-sample error.
# Inputs: sound, dtT#, dtV#, nDt, sTmin. Output: .result (new Sound).
# ------------------------------------------------------------
procedure wsola
    selectObject: sound
    .sr = Get sampling frequency
    .nIn = Get number of samples
    .x1 = Get start time
    .nN = 2 * round(0.015 * .sr)
    .hS = .nN / 2
    .dS = round(0.006 * .sr)
    # Zero-pad the source by two grains so the last grains continue the
    # hop exactly instead of being clamped to the end (v1.3 fix: that
    # clamp left a 15 ms error at the very end of a neutral run).
    # Concatenate joins in Objects-list order: the source copy must be
    # created BEFORE the padding.
    selectObject: sound
    .tmp = Copy: "aq_srccopy"
    Shift times to: "start time", 0
    .pad = Create Sound from formula: "aq_pad", 1, 0, 2 * .nN / .sr, .sr, "0"
    selectObject: .tmp
    plusObject: .pad
    .srcP = Concatenate
    removeObject: .tmp, .pad
    selectObject: .srcP
    .nP = Get number of samples
    # cumulative output time at each tier point
    .cum# = zero#(nDt)
    for .k from 2 to nDt
        .cum#[.k] = .cum#[.k - 1] + (dtT#[.k] - dtT#[.k - 1]) * (dtV#[.k - 1] + dtV#[.k]) / 2
    endfor
    .nG = ceiling(.nIn / .hS) + 1
    .ids# = zero#(.nG)
    .kp = 1
    .prev = 0
    .prevNom = 0
    .nSearch = 0
    .nCopy = 0
    for .g to .nG
        # output grain centre, relative to the Sound start (s)
        .tau = ((.g - 1) * .hS + .nN / 2) / .sr
        # inverse mapping: find source time whose output time is .tau
        while .kp < nDt - 1 and .cum#[.kp + 1] <= .tau
            .kp += 1
        endwhile
        .ds = dtT#[.kp + 1] - dtT#[.kp]
        .va = dtV#[.kp]
        .vb = dtV#[.kp + 1]
        .rem = .tau - .cum#[.kp]
        .qa = (.vb - .va) / (2 * .ds)
        if abs(.qa) < 1e-12
            .u = .rem / .va
        else
            .u = (- .va + sqrt(max(0, .va * .va + 4 * .qa * .rem))) / (2 * .qa)
        endif
        .src = dtT#[.kp] - sTmin + .u
        .nom = round(.src * .sr - .nN / 2)
        .nom = max(0, min(.nP - .nN, .nom))
        if .g = 1
            .p = .nom
        else
            .nat = .prev + .hS
            if abs(.nom - .nat) <= 1 or .nat + .nN > .nP
                .p = max(0, min(.nP - .nN, .nat))
                .nCopy += 1
            else
                .lo = max(0, .nom - .dS)
                .hi = min(.nP - .nN, .nom + .dS)
                selectObject: .srcP
                .ref = Extract part: .nat / .sr, (.nat + .hS) / .sr, "rectangular", 1, "no"
                selectObject: .srcP
                .reg = Extract part: .lo / .sr, (.hi + .hS) / .sr, "rectangular", 1, "no"
                selectObject: .ref
                plusObject: .reg
                .cc = Cross-correlate: "integral", "zero"
                # Prefer candidates near the nominal position (weight 1 at
                # nominal, 0.5 at +-6 ms): residual offsets shrink in pitch-
                # period steps instead of persisting into attack zones.
                .c0 = (.nom - .lo) / .sr
                .wd = .dS / .sr
                Formula: "self * (1 - 0.5 * min(1, abs(x - " + fixed$(.c0, 9) + ") / " + fixed$(.wd, 9) + "))"
                .tm = Get time of maximum: 0, (.hi - .lo) / .sr, "Parabolic"
                removeObject: .ref, .reg, .cc
                if .tm = undefined
                    .p = .nom
                else
                    .p = max(0, min(.nP - .nN, .lo + round(.tm * .sr)))
                endif
                .nSearch += 1
            endif
        endif
        selectObject: .srcP
        .ids#[.g] = Extract part: .p / .sr, (.p + .nN) / .sr, "rectangular", 1, "no"
        .prev = .p
        .prevNom = .nom
    endfor
    selectObject: .ids#[1]
    for .g from 2 to .nG
        plusObject: .ids#[.g]
    endfor
    .cat = Concatenate with overlap: .hS / .sr
    removeObject: .srcP
    for .g to .nG
        removeObject: .ids#[.g]
    endfor
    selectObject: .cat
    .result = Extract part: 0, .nIn / .sr, "rectangular", 1, "no"
    removeObject: .cat
    selectObject: .result
    Shift times to: "start time", .x1
endproc

# Grid position of grid index k (straight or groove grid):
#   q(k) = G + (k + g * offset[k mod P]) * T
procedure gridPos: .k
    .s = .k - floor(.k / grooveP) * grooveP + 1
    .result = gridG + (.k + gStr * grooveOff#[.s]) * gridT
endproc

# Index of the grid point nearest to time t (checks k0 - 1 .. k0 + 1;
# offsets stay within +-0.45 of a slot, so this is sufficient).
procedure nearestGridK: .t
    .k0 = round((.t - gridG) / gridT)
    .best = 1e9
    .result = .k0
    for .dk from -1 to 1
        @gridPos: .k0 + .dk
        if abs(gridPos.result - .t) < .best
            .best = abs(gridPos.result - .t)
            .result = .k0 + .dk
        endif
    endfor
endproc

# Status codes: 1 on target, 2 constrained, 3 collision unmoved,
# 4 already on grid, 5 collision nudged by neighbours.
procedure statusText: .code
    if .code = 1
        .result$ = "on target"
    elsif .code = 2
        .result$ = "constrained"
    elsif .code = 3
        .result$ = "collision: not quantized, unmoved"
    elsif .code = 5
        .result$ = "collision: not quantized, nudged by neighbours"
    else
        .result$ = "already on grid"
    endif
endproc

# Picture-text sanitizer: _ % # ^ are markup characters.
procedure picText: .s$
    .result$ = replace$(.s$, "\", "\bs", 0)
    .result$ = replace$(.result$, "_", "\_ ", 0)
    .result$ = replace$(.result$, "%", "\% ", 0)
    .result$ = replace$(.result$, "#", "\# ", 0)
    .result$ = replace$(.result$, "^", "\^ ", 0)
endproc

# ------------------------------------------------------------
# Automatic onset detector. Inputs (globals): detSound, detMethod
# (1 intensity, 2 flux, 3 hybrid), sTmin, sTmax, hop, minSep,
# onset_sensitivity. Outputs: onsets#, nOn, nCandidates, odf#, thr#,
# odfT1, odfDt. Called once on the input and, for the measured
# output check, once more on the quantized Sound.
# ------------------------------------------------------------
procedure detectOnsets
    nOn = 0
    nCandidates = 0
    useFlux = (detMethod = 2 or detMethod = 3)
    useInt = (detMethod = 1 or detMethod = 3)

    # Intensity is always computed: it supplies the loudness gate even
    # in spectral-flux mode. Min pitch 100 Hz -> 32 ms effective window.
    selectObject: detSound
    intensity = To Intensity: 100, hop, "no"
    intMat = Down to Matrix
    intT1 = Get x of column: 1
    intDt = Get column distance
    iv## = Get all values
    intRaw# = row#(iv##, 1)
    removeObject: intensity, intMat
    nIntF = size(intRaw#)
    for i to nIntF
        if intRaw#[i] = undefined
            intRaw#[i] = 0
        endif
    endfor

    if useFlux
        # Spectral flux with vibrato suppression (SuperFlux-style):
        # log-compressed magnitude (80 Hz bins), compared with a +-1-bin (+-80 Hz)
        # maximum-filtered frame two hops earlier, half-wave rectified
        # per bin and summed. Positive per-bin change cannot be cancelled
        # by falls elsewhere (cf. Multi-Band_Onset_Detector v1.2).
        maxF = min(8000, 0.45 * sr)
        selectObject: detSound
        spec = To Spectrogram: 0.025, maxF, hop, 80, "Gaussian"
        specMat = To Matrix
        removeObject: spec
        selectObject: specMat
        nRows = Get number of rows
        nCols = Get number of columns
        odfT1 = Get x of column: 1
        odfDt = Get column distance
        pmax = Get maximum
        if pmax <= 0
            pmax = 1
        endif
        Formula: "ln(1 + 20 * sqrt(max(0, self) / pmax))"
        # Shape normalisation: every frame scaled to unit sum, so a pure
        # level change (tremolo, crescendo) produces no flux; only changes
        # of spectral SHAPE (new pitch, noise -> tone attack) do.
        cm## = Get all values
        sumMat = Create simple Matrix: "aq_colsum", 1, nCols, "0"
        for j to nCols
            Set value: 1, j, max(1e-9, sum(col#(cm##, j)))
        endfor
        cm## = zero##(1, 1)
        selectObject: specMat
        Formula: "self / object[sumMat, 1, col]"
        removeObject: sumMat
        selectObject: specMat
        fluxMat = Copy: "flux"
        lagF = 2
        Formula: "if col <= lagF then 0 else max(0, self - max(object[specMat, max(row - 1, 1), col - lagF], max(object[specMat, row, col - lagF], object[specMat, min(row + 1, nRows), col - lagF]))) fi"
        fm## = Get all values
        removeObject: specMat, fluxMat
        nF = nCols
        # Shape novelty in 0..1 (0 = same spectral shape as before).
        flux# = zero#(nF)
        for j to nF
            flux#[j] = sum(col#(fm##, j))
        endfor
        fm## = zero##(1, 1)
    else
        odfT1 = intT1
        odfDt = intDt
        nF = nIntF
    endif

    # Intensity (dB) on the master frame grid.
    intDB# = zero#(nF)
    for j to nF
        tj = odfT1 + (j - 1) * odfDt
        @interpFrames: intRaw#, intT1, intDt, tj
        intDB#[j] = interpFrames.result
    endfor

    # Intensity-slope ODF: 5-point median smoothing, then positive
    # dB rise over two hops (cf. Tempo Curve (IOI) Estimator).
    intOdf# = zero#(nF)
    if useInt
        sm# = zero#(nF)
        for j to nF
            if j >= 3 and j <= nF - 2
                w5# = {intDB#[j - 2], intDB#[j - 1], intDB#[j], intDB#[j + 1], intDB#[j + 2]}
                w5# = sort#(w5#)
                sm#[j] = w5#[3]
            else
                sm#[j] = intDB#[j]
            endif
        endfor
        for j from 3 to nF
            intOdf#[j] = max(0, sm#[j] - sm#[j - 2])
        endfor
    endif

    # Loudness gate: frames within 40 dB of the loudest frame.
    dbMax = -1e9
    for j to nF
        if intDB#[j] > dbMax
            dbMax = intDB#[j]
        endif
    endfor
    # Noise floor = 10th percentile of frame levels; the gate sits at
    # least 12 dB above it and never more than 40 dB below the peak.
    @percentile: intDB#, 0.10
    noiseDB = percentile.result
    gateDB = max(dbMax - 40, noiseDB + 12)
    if gateDB > dbMax - 6
        gateDB = dbMax - 6
    endif
    gate# = zero#(nF)
    nGate = 0
    for j to nF
        if intDB#[j] >= gateDB
            gate#[j] = 1
            nGate += 1
        endif
    endfor
    # A rise may start below the gate: a candidate frame is accepted when
    # the level within the next 40 ms reaches the gate.
    look = max(1, round(0.040 / odfDt))
    gateAhead# = zero#(nF)
    for j to nF
        jEnd = min(nF, j + look)
        for k from j to jEnd
            if gate#[k] = 1
                gateAhead#[j] = 1
            endif
        endfor
    endfor

    # Combine on ABSOLUTE scales (never normalised by the file's own
    # maximum, which would inflate noise on material without attacks):
    #   intensity: a 6 dB rise over 10 ms = 1.0
    #   flux:      relative novelty, divided by fluxRef (= 1.0 for a
    #              typical clear note change)
    #   Hybrid = evidence fusion: max(sqrt(int x flux), int if int >= 0.5).
    #   A weak level rise (tremolo, swell) needs spectral-shape support;
    #   a strong rise (>= 3 dB per 10 ms, a real articulation) passes alone.
    fluxRef = 0.25
    odf# = zero#(nF)
    for j to nF
        fN = 0
        iN = 0
        if useFlux
            fN = flux#[j] / fluxRef
        endif
        if useInt
            iN = intOdf#[j] / 6
        endif
        if useFlux and useInt
            v = sqrt(iN * fN)
            if iN >= 0.5
                v = max(v, iN)
            endif
            odf#[j] = v
        elsif useFlux
            odf#[j] = fN
        else
            odf#[j] = iN
        endif
    endfor

    # Robust spread of the ODF inside sounding frames.
    if nGate >= 5
        gv# = zero#(nGate)
        k = 0
        for j to nF
            if gate#[j] = 1
                k += 1
                gv#[k] = odf#[j]
            endif
        endfor
        @median: gv#
        gMed = median.result
        dev# = abs#(gv# - gMed)
        @median: dev#
        spread = 1.4826 * median.result
    else
        spread = 0
    endif
    spread = max(spread, 0.04)
    delta = (3 / onset_sensitivity) * spread

    # Local mean over +-100 ms via cumulative sum.
    halfW = max(2, round(0.100 / odfDt))
    cum# = zero#(nF + 1)
    for j to nF
        cum#[j + 1] = cum#[j] + odf#[j]
    endfor
    thr# = zero#(nF)
    for j to nF
        a = max(1, j - halfW)
        b = min(nF, j + halfW)
        thr#[j] = (cum#[b + 1] - cum#[a]) / (b - a + 1) + delta
    endfor

    # Peak picking: above threshold, local maximum within +-15 ms,
    # loudness gate, boundary protection; then backtrack to the start
    # of the rise (ODF falls below 30 % of the peak, at most 30 ms).
    nbr = max(1, round(0.015 / odfDt))
    maxBack = max(1, round(0.030 / odfDt))
    backFrac = 0.5
    onsetBias = 0
    candT# = zero#(nF)
    candS# = zero#(nF)
    nCand = 0
    for j from 2 to nF - 1
        if odf#[j] > thr#[j] and gateAhead#[j] = 1
            isMax = 1
            for o from 1 to nbr
                if j - o >= 1
                    if odf#[j - o] >= odf#[j]
                        isMax = 0
                    endif
                endif
                if j + o <= nF
                    if odf#[j + o] > odf#[j]
                        isMax = 0
                    endif
                endif
            endfor
            if isMax
                kb = j
                kStop = max(1, j - maxBack)
                going = 1
                while going
                    if kb > kStop
                        if odf#[kb - 1] >= backFrac * odf#[j]
                            kb -= 1
                        else
                            going = 0
                        endif
                    else
                        going = 0
                    endif
                endwhile
                # Frame k of a two-hop difference describes the change
                # between frames k-2 and k: its rise begins one hop earlier.
                tOn = odfT1 + (kb - 1) * odfDt + onsetBias
                if tOn > sTmin + 0.005 and tOn < sTmax - 0.05
                    nCand += 1
                    candT#[nCand] = tOn
                    candS#[nCand] = odf#[j]
                endif
            endif
        endif
    endfor
    nCandidates = nCand

    # Note-level validation (melodic material). Detection functions also
    # fire on vibrato (harmonics sweeping through formants), tremolo,
    # consonants inside a syllable and breath noise. A candidate is kept
    # only if it is
    #   (a) a voicing onset: unvoiced 10-60 ms before, voiced 10-80 ms after
    #   (b) a pitch step: median f0 over ~one vibrato cycle (20-220 ms)
    #       after differs from the one before by >= 0.8 semitone
    #   (c) a re-articulation: an intensity dip >= 9 dB before the rise
    #       (without a pitch afterwards: rise to within 20 dB of the peak)
    #   (d) a short unvoiced lead (tongue / consonant) followed by
    #       voicing within 80 ms; its time is kept as the note start.
    #   (e) strong acoustic evidence: detection strength >= 1.5, whatever
    #       the pitch analysis says.
    # Rules (c) and (e) apply with or without a pitch, so attacks are not
    # rejected merely because no stable pitch was found. The pitch track
    # uses a wide 60-2500 Hz range (flute top octave included),
    # independent of the PSOLA range. Off (Advanced settings): every
    # thresholded candidate is accepted, as in v1.1.
    selectObject: detSound
    pitchDet = To Pitch: 0.01, 60, 2500
    nPf = Get number of frames
    pT1 = Get time from frame number: 1
    pDt = Get time step
    f0# = zero#(nPf)
    for k to nPf
        fv = Get value in frame: k, "Hertz"
        if fv = undefined
            f0#[k] = 0
        else
            f0#[k] = fv
        endif
    endfor
    removeObject: pitchDet
    nRejected = 0
    vT# = zero#(max(nCand, 1))
    vS# = zero#(max(nCand, 1))
    vL# = zero#(max(nCand, 1))
    nVal = 0
    for c to nCand
        tc = candT#[c]
        @voicedFraction: tc - 0.060, tc - 0.010
        vB = voicedFraction.result
        @voicedFraction: tc + 0.010, tc + 0.080
        vA = voicedFraction.result
        keep = 0
        lead = 0
        if note_validation = 0 or candS#[c] >= 1.5
            keep = 1
        elsif vA >= 0.6
            if vB <= 0.4
                keep = 1
            else
                @medianF0: tc - 0.220, tc - 0.020
                mB = medianF0.result
                nB = medianF0.n
                @medianF0: tc + 0.020, tc + 0.220
                mA = medianF0.result
                nA = medianF0.n
                if nB >= 5 and nA >= 5
                    if abs(12 * log2(mA / mB)) >= 0.8
                        keep = 1
                    endif
                endif
            endif
        else
            @voicedFraction: tc + 0.040, tc + 0.120
            if voicedFraction.result >= 0.6
                keep = 1
                lead = 1
            endif
        endif
        if keep = 0
            @dbRange: tc - 0.060, tc, "min"
            dMin = dbRange.result
            @dbRange: tc, tc + 0.100, "max"
            dMax = dbRange.result
            # Without a pitch afterwards the attack must also be loud (within
            # 20 dB of the peak): quiet breaths and consonant tails are not
            # note onsets.
            if dMax - dMin >= 9 and (vA >= 0.6 or dMax >= dbMax - 20)
                keep = 1
            endif
        endif
        if keep
            nVal += 1
            vT#[nVal] = tc
            vS#[nVal] = candS#[c]
            vL#[nVal] = lead
        else
            nRejected += 1
        endif
    endfor

    # Minimum separation: sequential; a closer, stronger candidate
    # replaces the previously accepted one, except that an accepted
    # unvoiced lead keeps its (earlier) time as the note start.
    onsets# = zero#(max(nVal, 1))
    onS# = zero#(max(nVal, 1))
    onL# = zero#(max(nVal, 1))
    for c to nVal
        if nOn = 0
            nOn = 1
            onsets#[1] = vT#[c]
            onS#[1] = vS#[c]
            onL#[1] = vL#[c]
        elsif vT#[c] - onsets#[nOn] < minSep
            if onL#[nOn] = 0 and vS#[c] > onS#[nOn]
                onsets#[nOn] = vT#[c]
                onS#[nOn] = vS#[c]
                onL#[nOn] = vL#[c]
            endif
        else
            nOn += 1
            onsets#[nOn] = vT#[c]
            onS#[nOn] = vS#[c]
            onL#[nOn] = vL#[c]
        endif
    endfor
endproc

# Fraction of voiced pitch frames in [t1, t2] (uses f0#, pT1, pDt).
procedure voicedFraction: .t1, .t2
    .k1 = max(1, ceiling((.t1 - pT1) / pDt) + 1)
    .k2 = min(size(f0#), floor((.t2 - pT1) / pDt) + 1)
    .n = 0
    .v = 0
    for .k from .k1 to .k2
        .n += 1
        if f0#[.k] > 0
            .v += 1
        endif
    endfor
    if .n = 0
        .result = 0
    else
        .result = .v / .n
    endif
endproc

# Median f0 of the voiced frames in [t1, t2]; .n = number of frames used.
procedure medianF0: .t1, .t2
    .k1 = max(1, ceiling((.t1 - pT1) / pDt) + 1)
    .k2 = min(size(f0#), floor((.t2 - pT1) / pDt) + 1)
    .n = 0
    for .k from .k1 to .k2
        if f0#[.k] > 0
            .n += 1
        endif
    endfor
    .result = 0
    if .n > 0
        .w# = zero#(.n)
        .j = 0
        for .k from .k1 to .k2
            if f0#[.k] > 0
                .j += 1
                .w#[.j] = f0#[.k]
            endif
        endfor
        @median: .w#
        .result = median.result
    endif
endproc

# Min or max of intDB# (master frame grid) over [t1, t2].
procedure dbRange: .t1, .t2, .mode$
    .k1 = max(1, ceiling((.t1 - odfT1) / odfDt) + 1)
    .k2 = min(size(intDB#), floor((.t2 - odfT1) / odfDt) + 1)
    if .mode$ = "min"
        .result = 1e9
    else
        .result = -1e9
    endif
    for .k from .k1 to .k2
        if .mode$ = "min"
            .result = min(.result, intDB#[.k])
        else
            .result = max(.result, intDB#[.k])
        endif
    endfor
endproc

# ============================================================
# 1b. GROOVE TEMPLATE  (grid types 2 and 3)
#   A groove is a per-slot timing offset, as a FRACTION of the grid
#   interval, over a pattern of P slots (beats per bar x units per beat
#   x bars). Fractions transfer between tempi: 35 ms late on a 250 ms
#   eighth at 120 BPM (+0.14) becomes +46.7 ms at 90 BPM.
#   Learning (type 2):
#     1. onsets of the reference with the same detector (and validation)
#     2. slot index k = round((t - G) / T) from the reference tempo and
#        downbeat; T and G then refined by a least-squares fit of
#        t = G + k T (two passes; accepted only within +-8 % of the
#        given tempo), so a slightly different real tempo does not
#        smear the offsets
#     3. offset of every event = (t - G) / T - k; per slot the MEDIAN
#        over all pattern repetitions, with its spread (MAD)
#     4. offsets re-anchored so the observed BEAT slots average 0: the
#        beats define the clock, the subdivisions carry the groove
#     5. unobserved slots get offset 0 (straight) - nothing is invented
#     6. |offset| <= 0.45 of a slot, so the grid stays strictly ordered
#   Applied grid:  q(k) = G + (k + g * offset[k mod P]) * T,
#   g = groove strength. Everything downstream (collisions, solver,
#   DurationTier, WSOLA) is unchanged.
# ============================================================
grooveP = 1
grooveOff# = {0}
grooveN# = {0}
grooveSpread# = {0}
gStr = 0
grooveTable = 0
nRef = 0
refFitBPM = undefined
refGivenBPM = undefined
refFitAccepted = 0
grooveSrc$ = "straight grid"
if grid_type = 2
    gStr = groove_strength_percent / 100
    refGivenBPM = reference_tempo_BPM
    saveTmin = sTmin
    saveTmax = sTmax
    saveSr = sr
    selectObject: refSound
    sTmin = Get start time
    sTmax = Get end time
    sr = Get sampling frequency
    refTmin = sTmin
    detSound = refSound
    if useTextGrid
        detMethod = 3
    else
        detMethod = onset_detection
    endif
    @detectOnsets
    nRef = nOn
    refOn# = zero#(max(nRef, 1))
    for i to nRef
        refOn#[i] = onsets#[i]
    endfor
    sTmin = saveTmin
    sTmax = saveTmax
    sr = saveSr
    nOn = 0
    if nRef < 4
        exitScript: "Only " + string$(nRef) + " onsets were found in the reference """ + refName$ + """ - at least 4 are needed to learn a groove."
    endif
    refT = 60 / (reference_tempo_BPM * unitsPerBeat)
    if reference_downbeat = 1
        refG = refOn#[1]
    else
        refG = refTmin + reference_offset_ms / 1000
    endif
    kr# = zero#(nRef)
    for pass to 2
        for i to nRef
            kr#[i] = round((refOn#[i] - refG) / refT)
        endfor
        sk = 0
        st = 0
        skk = 0
        skt = 0
        for i to nRef
            sk += kr#[i]
            st += refOn#[i]
            skk += kr#[i] ^ 2
            skt += kr#[i] * refOn#[i]
        endfor
        den = nRef * skk - sk ^ 2
        if den > 0
            tFit = (nRef * skt - sk * st) / den
            if abs(tFit / (60 / (reference_tempo_BPM * unitsPerBeat)) - 1) <= 0.08
                refT = tFit
                refG = (st - refT * sk) / nRef
                refFitAccepted = 1
            endif
        endif
    endfor
    for i to nRef
        kr#[i] = round((refOn#[i] - refG) / refT)
    endfor
    refFitBPM = 60 / (refT * unitsPerBeat)
    grooveP = beats_per_bar * unitsPerBeat * pattern_length_bars
    # collect deviations per slot (two events in one slot: keep the closer)
    devAll# = zero#(nRef)
    slotAll# = zero#(nRef)
    useAll# = zero#(nRef)
    for i to nRef
        devAll#[i] = (refOn#[i] - refG) / refT - kr#[i]
        slotAll#[i] = kr#[i] - floor(kr#[i] / grooveP) * grooveP + 1
        useAll#[i] = 1
        if i > 1
            if kr#[i] = kr#[i - 1]
                if abs(devAll#[i]) < abs(devAll#[i - 1])
                    useAll#[i - 1] = 0
                else
                    useAll#[i] = 0
                endif
            endif
        endif
    endfor
    grooveOff# = zero#(grooveP)
    grooveN# = zero#(grooveP)
    grooveSpread# = zero#(grooveP)
    for sl to grooveP
        cnt = 0
        for i to nRef
            if useAll#[i] and slotAll#[i] = sl
                cnt += 1
            endif
        endfor
        grooveN#[sl] = cnt
        if cnt > 0
            dv# = zero#(cnt)
            c2 = 0
            for i to nRef
                if useAll#[i] and slotAll#[i] = sl
                    c2 += 1
                    dv#[c2] = devAll#[i]
                endif
            endfor
            @median: dv#
            grooveOff#[sl] = median.result
            ad# = abs#(dv# - median.result)
            @median: ad#
            grooveSpread#[sl] = 1.4826 * median.result
        endif
    endfor
    # re-anchor on the observed beat slots
    sumB = 0
    nB = 0
    for sl to grooveP
        if ((sl - 1) mod unitsPerBeat) = 0 and grooveN#[sl] > 0
            sumB += grooveOff#[sl]
            nB += 1
        endif
    endfor
    if nB > 0
        anc = sumB / nB
        for sl to grooveP
            if grooveN#[sl] > 0
                grooveOff#[sl] = grooveOff#[sl] - anc
            endif
        endfor
    endif
    for sl to grooveP
        grooveOff#[sl] = max(-0.45, min(0.45, grooveOff#[sl]))
    endfor
    grooveSrc$ = "learned from """ + refName$ + """"
    if keep_groove_Table
        grooveTable = Create Table with column names: "groove_" + replace_regex$(refName$, "[^A-Za-z0-9_\-]", "_", 0), grooveP,
        ... "slot beat sub offset_frac offset_ms_ref n_obs spread_frac units_per_beat beats_per_bar ref_bpm"
        for sl to grooveP
            Set numeric value: sl, "slot", sl
            Set numeric value: sl, "beat", floor((sl - 1) / unitsPerBeat) + 1
            Set numeric value: sl, "sub", ((sl - 1) mod unitsPerBeat) + 1
            Set numeric value: sl, "offset_frac", grooveOff#[sl]
            Set numeric value: sl, "offset_ms_ref", grooveOff#[sl] * refT * 1000
            Set numeric value: sl, "n_obs", grooveN#[sl]
            Set numeric value: sl, "spread_frac", grooveSpread#[sl]
            Set numeric value: sl, "units_per_beat", unitsPerBeat
            Set numeric value: sl, "beats_per_bar", beats_per_bar
            Set numeric value: sl, "ref_bpm", refFitBPM
        endfor
    endif
elsif grid_type = 3
    gStr = groove_strength_percent / 100
    selectObject: grooveTableIn
    grooveP = Get number of rows
    cOff = Get column index: "offset_frac"
    cUpb = Get column index: "units_per_beat"
    cN = Get column index: "n_obs"
    if cOff = 0 or cUpb = 0 or grooveP < 1
        exitScript: "The selected Table is not a groove Table from Audio Quantizer (needs columns offset_frac and units_per_beat)."
    endif
    tUpb = Get value: 1, "units_per_beat"
    if tUpb <> unitsPerBeat
        exitScript: "The groove Table was learned with " + string$(tUpb) + " grid units per beat, but the chosen Grid division has " +
        ... string$(unitsPerBeat) + ". Choose the same division the groove was learned with."
    endif
    grooveOff# = zero#(grooveP)
    grooveN# = zero#(grooveP)
    grooveSpread# = zero#(grooveP)
    for sl to grooveP
        vOff = Get value: sl, "offset_frac"
        grooveOff#[sl] = max(-0.45, min(0.45, vOff))
        if cN > 0
            vN = Get value: sl, "n_obs"
            grooveN#[sl] = vN
        endif
    endfor
    tName$ = selected$("Table")
    grooveSrc$ = "Table """ + tName$ + """"
endif
if grid_type > 1 and gStr > 0
    gridLabel$ = divLabel$ + "+groove"
else
    gridLabel$ = divLabel$
endif

# ============================================================
# 2-6. ONSET ANALYSIS
# ============================================================
nOn = 0
onsets# = zero#(0)
odfShow# = zero#(0)
thrShow# = zero#(0)
odfT1 = sTmin
odfDt = hop

if useTextGrid
    # ---------------- TextGrid input ----------------
    selectObject: textGridIn
    nTiers = Get number of tiers
    tier = 0
    # Prefer a point tier called "onsets" (case-insensitive), else the first point tier.
    firstPoint = 0
    for it to nTiers
        selectObject: textGridIn
        isInterval = Is interval tier: it
        if isInterval = 0
            tierName$ = Get tier name: it
            lname$ = replace_regex$(tierName$, "([A-Z])", "\L\1", 0)
            if firstPoint = 0
                firstPoint = it
            endif
            if lname$ = "onsets" or lname$ = "onset"
                if tier = 0
                    tier = it
                endif
            endif
        endif
    endfor
    if tier = 0
        tier = firstPoint
    endif
    if tier = 0
        exitScript: "The selected TextGrid has no point tier. Add a point tier named ""onsets"" with one point per note onset."
    endif
    selectObject: textGridIn
    tgName$ = Get tier name: tier
    tgTmin = Get start time
    tgTmax = Get end time
    if tgTmax <= sTmin or tgTmin >= sTmax
        exitScript: "The TextGrid time domain (" + fixed$(tgTmin, 3) + "-" + fixed$(tgTmax, 3) +
        ... " s) does not overlap the Sound (" + fixed$(sTmin, 3) + "-" + fixed$(sTmax, 3) + " s)."
    endif
    if abs(tgTmin - sTmin) > 0.001 or abs(tgTmax - sTmax) > 0.001
        nWarn += 1
        warnings$ = warnings$ + "  - TextGrid and Sound domains differ; only points inside the Sound are used." + newline$
    endif
    nPts = Get number of points: tier
    nCandidates = nPts
    raw# = zero#(nPts)
    nRaw = 0
    nOutside = 0
    for ip to nPts
        tp = Get time of point: tier, ip
        if tp > sTmin + 0.005 and tp < sTmax - 0.02
            nRaw += 1
            raw#[nRaw] = tp
        else
            nOutside += 1
        endif
    endfor
    if nOutside > 0
        nWarn += 1
        warnings$ = warnings$ + "  - " + string$(nOutside) + " TextGrid point(s) outside the usable Sound range ignored." + newline$
    endif
    # Points of a Praat tier are already time-sorted; sort anyway, then
    # merge near-duplicates (closer than 10 ms -> keep the earlier one).
    onsets# = zero#(max(nRaw, 1))
    nMerged = 0
    if nRaw > 0
        tmp# = zero#(nRaw)
        for ip to nRaw
            tmp#[ip] = raw#[ip]
        endfor
        tmp# = sort#(tmp#)
        for ip to nRaw
            if nOn = 0
                nOn = 1
                onsets#[1] = tmp#[ip]
            elsif tmp#[ip] - onsets#[nOn] >= 0.010
                nOn += 1
                onsets#[nOn] = tmp#[ip]
            else
                nMerged += 1
            endif
        endfor
    endif
    if nMerged > 0
        nWarn += 1
        warnings$ = warnings$ + "  - " + string$(nMerged) + " near-duplicate TextGrid point(s) (< 10 ms apart) merged." + newline$
    endif
else
    # ---------------- Automatic detection ----------------
    detSound = sound
    detMethod = onset_detection
    @detectOnsets

    odfShow# = odf#
    thrShow# = thr#
endif

# Final validity pass: strictly increasing, inside the domain.
if nOn > 0
    tmp# = zero#(nOn)
    k = 0
    for i to nOn
        ti = onsets#[i]
        okT = (ti > sTmin) and (ti < sTmax)
        if okT and k > 0
            okT = (ti > tmp#[k] + 0.001)
        endif
        if okT
            k += 1
            tmp#[k] = ti
        endif
    endfor
    nOn = k
    onsets# = zero#(max(nOn, 1))
    for i to nOn
        onsets#[i] = tmp#[i]
    endfor
endif

if nOn = 0
    if useTextGrid
        exitScript: "No usable onset points were found in tier """ + tgName$ + """ of the selected TextGrid. No output was created."
    else
        exitScript: "No note onsets were detected (" + string$(nCandidates) + " candidates). No output was created." + newline$ +
        ... "Try a higher Onset sensitivity, another detection method, or a TextGrid with manual onsets."
    endif
endif

# ============================================================
# 7. RHYTHMIC GRID
#    q(t) = G + round((t - G) / T) * T   (halves round up: floor(x+0.5))
# ============================================================
if grid_origin = 1
    gridG = onsets#[1]
    originLabel$ = "first detected onset"
elsif grid_origin = 2
    gridG = sTmin
    originLabel$ = "beginning of Sound"
else
    gridG = sTmin + gridOffset
    originLabel$ = "manual offset " + fixed$(grid_offset_ms, 1) + " ms"
endif

gk# = zero#(nOn)
q# = zero#(nOn)
for i to nOn
    @nearestGridK: onsets#[i]
    gk#[i] = nearestGridK.result
    @gridPos: gk#[i]
    q#[i] = gridPos.result
endfor

# ------------------------------------------------------------
# Grid fit diagnostic: phase concentration R of the onsets against the
# grid (and against the quarter-note beat). R = 1: every onset at the
# same phase; R ~ 1/sqrt(n): no relation (chance). Also the offset at
# which the onsets fit best, for use with Grid origin = Manual offset.
# ------------------------------------------------------------
fitN = nOn
fitChance = 1 / sqrt(max(1, nOn))
cs = 0
sn = 0
for i to nOn
    ph = 2 * pi * (onsets#[i] - sTmin) / gridT
    cs += cos(ph)
    sn += sin(ph)
endfor
fitR = sqrt(cs ^ 2 + sn ^ 2) / max(1, nOn)
fitOff = arctan2(sn, cs) / (2 * pi) * gridT
if fitOff < 0
    fitOff += gridT
endif
cs = 0
sn = 0
for i to nOn
    ph = 2 * pi * (onsets#[i] - sTmin) / beatSec
    cs += cos(ph)
    sn += sin(ph)
endfor
fitRbeat = sqrt(cs ^ 2 + sn ^ 2) / max(1, nOn)
fitOffBeat = arctan2(sn, cs) / (2 * pi) * beatSec
if fitOffBeat < 0
    fitOffBeat += beatSec
endif
# Mean distance of the onsets to the nearest grid point, straight vs
# the grid actually used (differs only with a groove).
dStraight = 0
dUsed = 0
for i to nOn
    kk0 = round((onsets#[i] - gridG) / gridT)
    dStraight += abs(onsets#[i] - (gridG + kk0 * gridT))
    @nearestGridK: onsets#[i]
    @gridPos: nearestGridK.result
    dUsed += abs(onsets#[i] - gridPos.result)
endfor
dStraight = dStraight / max(1, nOn)
dUsed = dUsed / max(1, nOn)
if nOn >= 8 and fitR < 2 * fitChance and fitRbeat < 2 * fitChance and strength > 0
    nWarn += 1
    warnings$ = warnings$ + "  - The onsets show no consistent relation to this grid (R " + fixed$(fitR, 2) + ", beat R " +
    ... fixed$(fitRbeat, 2) + ", chance ~" + fixed$(fitChance, 2) + "). The take may not be at " + fixed$(tempo_BPM, 1) +
    ... " BPM, or may be rubato; notes will then be moved by up to half a grid step in arbitrary directions." + newline$
endif

# ============================================================
# 8-9a. COLLISION-AWARE GRID ASSIGNMENT
#   Consecutive onsets may not share a grid slot. For a clash, either
#   the current onset moves to the next slot (A) or the previous one to
#   the slot before (B), whichever moves less in total, provided the
#   reassigned onset stays within the maximum shift. Otherwise the onset
#   closer to the contested slot keeps it and the other is not quantized
#   (C); the solver may still nudge it to preserve order and ratios. Events are never
#   deleted or merged. With origin = first onset, onset 1 is pinned.
# ============================================================
status# = zero#(nOn)
# status codes: see procedure statusText
collision# = zero#(nOn)
lastIdx = 1
nCollisions = 0
for i from 2 to nOn
    if gk#[i] <= gk#[lastIdx]
        nCollisions += 1
        p = lastIdx
        @gridPos: gk#[p] + 1
        tA = gridPos.result
        dA = abs(tA - onsets#[i])
        costA = abs(q#[p] - onsets#[p]) + dA
        validA = (dA <= maxShift)
        kB = gk#[i] - 1
        @gridPos: kB
        tB = gridPos.result
        dB = abs(tB - onsets#[p])
        costB = dB + abs(q#[i] - onsets#[i])
        validB = (dB <= maxShift)
        if p = 1 and grid_origin = 1
            validB = 0
        endif
        # Slot before must still be free relative to the onset before p.
        prevAssigned = 0
        for z from 1 to p - 1
            if collision#[z] = 0
                prevAssigned = z
            endif
        endfor
        if prevAssigned > 0
            if kB <= gk#[prevAssigned]
                validB = 0
            endif
        endif
        if validA and (validB = 0 or costA <= costB)
            gk#[i] = gk#[p] + 1
            q#[i] = tA
            lastIdx = i
        elsif validB
            gk#[p] = kB
            q#[p] = tB
            lastIdx = i
        else
            # Neither may move to a neighbouring slot: the onset CLOSER to
            # the contested slot keeps it; the other is not quantized.
            pinnedP = (p = 1 and grid_origin = 1)
            if abs(q#[i] - onsets#[i]) < abs(q#[p] - onsets#[p]) and pinnedP = 0
                collision#[p] = 1
                q#[p] = onsets#[p]
                lastIdx = i
            else
                collision#[i] = 1
                q#[i] = onsets#[i]
            endif
        endif
    else
        lastIdx = i
    endif
endfor

# ============================================================
# 8. QUANTIZATION STRENGTH + MAXIMUM SHIFT
#    requested = t + s * (q - t), then |requested - t| <= max shift
# ============================================================
req# = zero#(nOn)
nShiftClamped = 0
for i to nOn
    if collision#[i] = 1
        req#[i] = onsets#[i]
    else
        req#[i] = onsets#[i] + strength * (q#[i] - onsets#[i])
    endif
    if abs(req#[i] - onsets#[i]) > maxShift + 1e-9
        nShiftClamped += 1
    endif
    req#[i] = max(onsets#[i] - maxShift, min(onsets#[i] + maxShift, req#[i]))
endfor

# ============================================================
# 9b. STRETCHABILITY WEIGHTS  (where the time change is allowed to go)
#   Instead of one constant ratio per segment, the local ratio is
#       ratio(t) = 1 + k(segment) * w(t)
#   with a material weight w on a 10 ms grid:
#       silence (below the loudness gate)   w = 3   (stretching is free)
#       steady voiced sound                 w = 1
#       unvoiced sound (consonant, breath)  w = 0.2 (noise stretches badly)
#       attack zone: 10 ms before an onset to "attack protection" after
#                                           w = 0   (attacks untouched)
#   The class weights are smoothed over +-20 ms and never allowed to
#   exceed their own class value, so transitions are gradual and the
#   ratio limits hold point by point. Ratio limits per class:
#       voiced [rMin, rMax], silence [0.25, 3], unvoiced [max(rMin, 0.8),
#       min(rMax, 1.25)].
# ============================================================
wDt = 0.010
nW = floor(sDur / wDt) + 1
selectObject: sound
wInt = To Intensity: 100, 0.005, "no"
selectObject: sound
wPit = To Pitch: 0.01, 60, 1500
wDB# = zero#(nW)
wV# = zero#(nW)
for k to nW
    tk = sTmin + (k - 1) * wDt
    selectObject: wInt
    dbv = Get value at time: tk, "cubic"
    if dbv = undefined
        dbv = -100
    endif
    wDB#[k] = dbv
    selectObject: wPit
    fv = Get value at time: tk, "Hertz", "linear"
    if fv <> undefined
        wV#[k] = 1
    endif
endfor
removeObject: wInt, wPit
wMax = -1e9
for k to nW
    wMax = max(wMax, wDB#[k])
endfor
@percentile: wDB#, 0.10
wGate = max(wMax - 40, percentile.result + 12)
wGate = min(wGate, wMax - 6)
wCls# = zero#(nW)
for k to nW
    if wDB#[k] < wGate
        wCls#[k] = 3
    elsif wV#[k] = 1
        wCls#[k] = 1
    else
        wCls#[k] = 0.2
    endif
endfor
wFin# = zero#(nW)
for k to nW
    a5 = max(1, k - 2)
    b5 = min(nW, k + 2)
    acc = 0
    for kk from a5 to b5
        acc += wCls#[kk]
    endfor
    wFin#[k] = min(acc / (b5 - a5 + 1), wCls#[k])
endfor
nSil = 0
nVoi = 0
nUnv = 0
for k to nW
    if wCls#[k] = 3
        nSil += 1
    elsif wCls#[k] = 1
        nVoi += 1
    else
        nUnv += 1
    endif
endfor

# ============================================================
# 9c. CHAIN-CONSTRAINT SOLVER
#   Anchors x0 = Sound start, x1..xn = onsets, x(n+1) = Sound end.
#   Targets y0 = x0 and y(n+1) = x(n+1) are fixed (duration preserved).
#   DurationTier points: every segment boundary plus the 10 ms weight
#   frames inside it. Praat interpolates linearly between points, so a
#   segment's output length is EXACTLY its trapezoid integral:
#       D = S + k * W,  W = trapezoid integral of w over the segment
#   The per-point class limits give k in [kMin, kMax], hence
#       D in [S + kMin W, S + kMax W]   (linear bounds).
#   Backward pass: feasible interval B(i) of every y(i).
#   Forward pass: y(i) = clamp(requested(i), interval allowed by y(i-1)
#   and B(i)). Because the identity mapping is feasible, every interval
#   is non-empty: order is always preserved and no event can collapse.
# ============================================================
nA = nOn + 2
x# = zero#(nA)
x#[1] = sTmin
for i to nOn
    x#[i + 1] = onsets#[i]
endfor
x#[nA] = sTmax
nSeg = nA - 1
uMin = max(rMin, 0.8)
uMax = min(rMax, 1.25)

# Global point list: first point of every segment, its interior frames,
# and finally the Sound end. ptSeg# = owning segment; ptW# = weight;
# ptC# = class weight (3 / 1 / 0.2) for the limits.
maxPts = nW + 2 * nA + 4
ptT# = zero#(maxPts)
ptW# = zero#(maxPts)
ptC# = zero#(maxPts)
ptSeg# = zero#(maxPts)
segFirst# = zero#(nSeg + 1)
nPt = 0
for j to nSeg
    xa = x#[j]
    xb = x#[j + 1]
    segFirst#[j] = nPt + 1
    # boundary point at xa
    @weightAt: xa, j
    nPt += 1
    ptT#[nPt] = xa
    ptW#[nPt] = weightAt.w
    ptC#[nPt] = weightAt.c
    ptSeg#[nPt] = j
    kf1 = floor((xa - sTmin) / wDt) + 2
    kf2 = ceiling((xb - sTmin) / wDt)
    for kf from max(1, kf1) to min(nW, kf2)
        tf = sTmin + (kf - 1) * wDt
        if tf > xa + 1e-4 and tf < xb - 1e-4
            @weightAt: tf, j
            nPt += 1
            ptT#[nPt] = tf
            ptW#[nPt] = weightAt.w
            ptC#[nPt] = weightAt.c
            ptSeg#[nPt] = j
        endif
    endfor
endfor
@weightAt: sTmax, nSeg
nPt += 1
ptT#[nPt] = sTmax
ptW#[nPt] = weightAt.w
ptC#[nPt] = weightAt.c
ptSeg#[nPt] = nSeg
segFirst#[nSeg + 1] = nPt

segW# = zero#(nSeg)
segKmin# = zero#(nSeg)
segKmax# = zero#(nSeg)
segLo# = zero#(nSeg)
segHi# = zero#(nSeg)
for j to nSeg
    sLen = x#[j + 1] - x#[j]
    pa = segFirst#[j]
    pb = segFirst#[j + 1]
    wInt = 0
    mxV = 0
    mxS = 0
    mxU = 0
    for pp from pa to pb
        if pp < pb
            wInt += (ptT#[pp + 1] - ptT#[pp]) * (ptW#[pp] + ptW#[pp + 1]) / 2
        endif
        if ptC#[pp] = 3
            mxS = max(mxS, ptW#[pp])
        elsif ptC#[pp] = 1
            mxV = max(mxV, ptW#[pp])
        else
            mxU = max(mxU, ptW#[pp])
        endif
    endfor
    kLo = -1e9
    kHi = 1e9
    if mxV > 1e-6
        kLo = max(kLo, (rMin - 1) / mxV)
        kHi = min(kHi, (rMax - 1) / mxV)
    endif
    if mxS > 1e-6
        kLo = max(kLo, (0.25 - 1) / mxS)
        kHi = min(kHi, (3 - 1) / mxS)
    endif
    if mxU > 1e-6
        kLo = max(kLo, (uMin - 1) / mxU)
        kHi = min(kHi, (uMax - 1) / mxU)
    endif
    if wInt < 1e-9 or kLo > 1e8
        kLo = 0
        kHi = 0
        wInt = 0
    endif
    segW#[j] = wInt
    segKmin#[j] = kLo
    segKmax#[j] = kHi
    segLo#[j] = sLen + kLo * wInt
    segHi#[j] = sLen + kHi * wInt
    # Minimum inter-onset duration between two onsets.
    if j > 1 and j < nSeg
        segLo#[j] = max(segLo#[j], min(sLen, 0.5 * minSep))
    endif
endfor

boxLo# = zero#(nA)
boxHi# = zero#(nA)
boxLo#[1] = sTmin
boxHi#[1] = sTmin
boxLo#[nA] = sTmax
boxHi#[nA] = sTmax
for i from 2 to nA - 1
    boxLo#[i] = max(sTmin, x#[i] - maxShift)
    boxHi#[i] = min(sTmax, x#[i] + maxShift)
endfor

bLo# = zero#(nA)
bHi# = zero#(nA)
bLo#[nA] = sTmax
bHi#[nA] = sTmax
for jj to nA - 1
    i = nA - jj
    bLo#[i] = max(boxLo#[i], bLo#[i + 1] - segHi#[i])
    bHi#[i] = min(boxHi#[i], bHi#[i + 1] - segLo#[i])
endfor

eps = 1e-9
solverOK = (bLo#[1] <= sTmin + eps) and (bHi#[1] >= sTmin - eps)
y# = zero#(nA)
y#[1] = sTmin
y#[nA] = sTmax
if solverOK
    for i from 2 to nA - 1
        lo = max(y#[i - 1] + segLo#[i - 1], bLo#[i])
        hi = min(y#[i - 1] + segHi#[i - 1], bHi#[i])
        if lo > hi + eps
            solverOK = 0
        endif
        y#[i] = max(lo, min(hi, req#[i - 1]))
    endfor
endif
if solverOK = 0
    # Should be unreachable (identity is always feasible); fail safe.
    for i to nA
        y#[i] = x#[i]
    endfor
    nWarn += 1
    warnings$ = warnings$ + "  - Constraint solver found no feasible mapping; timing left unchanged." + newline$
endif

# ------------------------------------------------------------
# Classification of every onset.
# ------------------------------------------------------------
tolC = 0.0005
nOnTarget = 0
nConstrained = 0
nUnchanged = 0
nAlready = 0
nCollKept = 0
nCollNudged = 0
sumAbs = 0
maxAbs = 0
for i to nOn
    yi = y#[i + 1]
    ti = onsets#[i]
    disp = yi - ti
    sumAbs += abs(disp)
    maxAbs = max(maxAbs, abs(disp))
    if collision#[i] = 1
        nCollKept += 1
        if abs(disp) < tolC
            status#[i] = 3
        else
            status#[i] = 5
            nCollNudged += 1
        endif
    elsif abs(req#[i] - ti) < tolC
        status#[i] = 4
        nAlready += 1
    elsif abs(yi - req#[i]) < tolC
        status#[i] = 1
        nOnTarget += 1
    else
        status#[i] = 2
        nConstrained += 1
    endif
    if abs(disp) < tolC
        nUnchanged += 1
    endif
endfor
meanAbs = sumAbs / nOn
# Fully aligned = exactly on the grid point, not just on the strength target.
nOnGrid = 0
for i to nOn
    if abs(y#[i + 1] - q#[i]) < tolC and collision#[i] = 0
        nOnGrid += 1
    endif
endfor
if nShiftClamped > 0
    nWarn += 1
    warnings$ = warnings$ + "  - " + string$(nShiftClamped) + " onset(s) were limited by the maximum onset shift (" +
    ... shiftLabel$ + ") and could not reach their grid point (0 = auto removes this limit)." + newline$
endif

# ============================================================
# 10. SEGMENT COEFFICIENTS  k = (D - S) / W  (exact, see 9c)
# ============================================================
segK# = zero#(nSeg)
anyMove = 0
for j to nSeg
    sLen = x#[j + 1] - x#[j]
    dLen = y#[j + 1] - y#[j]
    if segW#[j] > 0
        segK#[j] = (dLen - sLen) / segW#[j]
    endif
    if abs(dLen - sLen) > 1e-7
        anyMove = 1
    endif
endfor
dtT# = zero#(nPt)
dtV# = zero#(nPt)
nDt = nPt
rLow = 1e9
rHigh = -1e9
for pp to nPt
    dtT#[pp] = ptT#[pp]
    dtV#[pp] = 1 + segK#[ptSeg#[pp]] * ptW#[pp]
    rLow = min(rLow, dtV#[pp])
    rHigh = max(rHigh, dtV#[pp])
endfor

# ============================================================
# 11-13. DURATIONTIER, VERIFICATION, RESYNTHESIS
# ============================================================
predictedDur = sDur
maxMapErr = 0
resynth = 0
durTier = 0
mapErr# = zero#(nOn)

if strength > 0 and anyMove
    resynth = 1
    durTier = Create DurationTier: "aq_duration", sTmin, sTmax
    for k to nDt
        Add point: dtT#[k], dtV#[k]
    endfor
    nTierPts = Get number of points
    if nTierPts <> nDt
        nWarn += 1
        warnings$ = warnings$ + "  - " + string$(nDt - nTierPts) + " coincident DurationTier point(s) were merged by Praat." + newline$
    endif

    # Numerical verification at every onset anchor.
    predictedDur = Get target duration: sTmin, sTmax
    for i to nOn
        tgt = Get target duration: sTmin, onsets#[i]
        tgt = sTmin + tgt
        mapErr#[i] = tgt - y#[i + 1]
        maxMapErr = max(maxMapErr, abs(mapErr#[i]))
    endfor
    endErr = predictedDur - sDur
    maxMapErr = max(maxMapErr, abs(endErr))
    if maxMapErr > 0.002
        removeObject: durTier
        exitScript: "DurationTier verification failed: max anchor error " + fixed$(maxMapErr * 1000, 3) +
        ... " ms (> 2 ms). No output was created. Please report this case."
    endif

    if resynthesis = 1
        @wsola
        result = wsola.result
    else
        # Pitch-range check: PSOLA treats frames outside the floor-ceiling
        # range as unvoiced, which degrades them badly. Probe with a wider
        # range and warn if a notable share of voiced frames falls outside.
        selectObject: sound
        probe = To Pitch: 0.01, max(30, pitch_floor_Hz / 2), min(0.45 * sr, pitch_ceiling_Hz * 3)
        nPF = Get number of frames
        nVoicedP = 0
        nAboveP = 0
        nBelowP = 0
        for k to nPF
            fv = Get value in frame: k, "Hertz"
            if fv <> undefined
                nVoicedP += 1
                if fv > pitch_ceiling_Hz
                    nAboveP += 1
                elsif fv < pitch_floor_Hz
                    nBelowP += 1
                endif
            endif
        endfor
        removeObject: probe
        if nVoicedP > 0
            if nAboveP / nVoicedP > 0.05
                nWarn += 1
                warnings$ = warnings$ + "  - " + fixed$(100 * nAboveP / nVoicedP, 0) + " % of voiced frames lie ABOVE the pitch ceiling (" +
                ... fixed$(pitch_ceiling_Hz, 0) + " Hz). Raise it in Advanced settings (flute: about 2200 Hz) or expect artifacts." + newline$
            endif
            if nBelowP / nVoicedP > 0.05
                nWarn += 1
                warnings$ = warnings$ + "  - " + fixed$(100 * nBelowP / nVoicedP, 0) + " % of voiced frames lie BELOW the pitch floor (" +
                ... fixed$(pitch_floor_Hz, 0) + " Hz). Lower it in Advanced settings or expect artifacts." + newline$
            endif
        endif

        selectObject: sound
        manip = To Manipulation: 0.01, pitch_floor_Hz, pitch_ceiling_Hz
        plusObject: durTier
        Replace duration tier
        selectObject: manip
        result = Get resynthesis (overlap-add)
        removeObject: manip
    endif
else
    selectObject: sound
    result = Copy: "aq_copy"
endif

# Output geometry and peak protection (attenuate only, never boost).
selectObject: result
outTmin = Get start time
if abs(outTmin - sTmin) > 1e-9
    Shift times to: "start time", sTmin
endif
outTmax = Get end time
outDur = outTmax - sTmin
outPeak = Get absolute extremum: 0, 0, "None"
peakGuard = 0
if outPeak <> undefined
    if outPeak > 0.99
        Scale peak: 0.99
        peakGuard = 1
    endif
endif

bpm$ = fixed$(tempo_BPM, 2)
bpm$ = replace_regex$(bpm$, "\.?0+$", "", 0)
bpm$ = replace$(bpm$, ".", "p", 0)
outName$ = soundName$ + "_Quantized_" + bpm$ + "BPM_" + divLabel$
if grid_type > 1 and gStr > 0
    outName$ = outName$ + "_groove"
endif
outName$ = replace_regex$(outName$, "[^A-Za-z0-9_\-]", "_", 0)
Rename: outName$

# ============================================================
# 15. OPTIONAL DIAGNOSTIC TEXTGRID  (output time axis)
#   Quantized_Onsets : where each attack now sits in the output Sound.
#   Original_Onsets  : where the same event sat BEFORE quantization,
#                      drawn on the same clock for comparison only (not
#                      a physical position in the output Sound).
# ============================================================
tgOut = 0
if keep_onset_TextGrid
    selectObject: result
    tgOut = To TextGrid: "Quantized_Onsets Original_Onsets", "Quantized_Onsets Original_Onsets"
    Rename: outName$ + "_onsets"
    for i to nOn
        @msStr: y#[i + 1] - onsets#[i]
        @statusText: status#[i]
        st$ = statusText.result$
        tyi = y#[i + 1]
        if tyi > sTmin and tyi < outTmax
            Insert point: 1, tyi, string$(i) + " " + msStr.result$ + " ms " + st$
        endif
        if onsets#[i] > sTmin and onsets#[i] < outTmax
            Insert point: 2, onsets#[i], "src " + string$(i)
        endif
    endfor
endif

if durTier
    removeObject: durTier
endif

# Output length difference in samples (PSOLA can round the end).
selectObject: result
nOutSamp = Get number of samples
selectObject: sound
nInSamp = Get number of samples
durDiffSamp = nOutSamp - nInSamp

# ============================================================
# 13b. MEASURED OUTPUT CHECK
#   The same detector is run on the quantized Sound (hybrid when the
#   input onsets came from a TextGrid). Each target is matched to the
#   nearest attack found within +-40 ms. Comparing re-detected output
#   attacks with targets derived from detected input attacks makes
#   the detector's own timing bias largely cancel. This measures where
#   the attacks really are after PSOLA, not the DurationTier arithmetic.
# ============================================================
chkDone = 0
chkMatched = 0
chkMissed = 0
chkExtra = 0
chkMean = 0
chkMax = 0
chkGridMean = 0
chkGridMax = 0
chkGridN = 0
chkOut# = zero#(1)
nChkOut = 0
if resynth
    saveOn# = onsets#
    saveN = nOn
    saveCand = nCandidates
    saveT1 = odfT1
    saveDt = odfDt
    detSound = result
    if useTextGrid
        detMethod = 3
    else
        detMethod = onset_detection
    endif
    @detectOnsets
    chkOut# = zero#(max(nOn, 1))
    nChkOut = nOn
    for i to nOn
        chkOut#[i] = onsets#[i]
    endfor
    onsets# = saveOn#
    nOn = saveN
    nCandidates = saveCand
    odfT1 = saveT1
    odfDt = saveDt
    chkDone = 1
    # One-to-one, order-preserving matching: targets in time order, each
    # may take only an output attack later than the previously matched
    # one, and an attack can serve one target at most.
    used# = zero#(max(nChkOut, 1))
    sumC = 0
    sumG = 0
    lastJ = 0
    for i to nOn
        best = 1e9
        bestJ = 0
        for jj from lastJ + 1 to nChkOut
            dd = chkOut#[jj] - y#[i + 1]
            if abs(dd) < abs(best)
                best = dd
                bestJ = jj
            endif
        endfor
        # an attack nearer to the NEXT target is left for that target
        if bestJ > 0 and i < nOn
            if abs(chkOut#[bestJ] - y#[i + 2]) < abs(best)
                bestJ = 0
            endif
        endif
        if bestJ > 0 and abs(best) <= 0.040
            chkMatched += 1
            used#[bestJ] = 1
            lastJ = bestJ
            sumC += abs(best)
            chkMax = max(chkMax, abs(best))
            if abs(y#[i + 1] - q#[i]) < tolC and collision#[i] = 0
                gd = abs(chkOut#[bestJ] - q#[i])
                chkGridN += 1
                sumG += gd
                chkGridMax = max(chkGridMax, gd)
            endif
        else
            chkMissed += 1
        endif
    endfor
    for jj to nChkOut
        if used#[jj] = 0
            chkExtra += 1
        endif
    endfor
    if chkMatched > 0
        chkMean = sumC / chkMatched
    endif
    if chkGridN > 0
        chkGridMean = sumG / chkGridN
    endif
endif

# ============================================================
# 13d. ENGINE SELF-TEST (optional, Advanced settings)
#   Runs the selected engine with every local ratio exactly 1 (no timing
#   change at all) and compares the result with the input sample by
#   sample. This isolates the engine from the quantization: WSOLA should
#   reproduce the input exactly; PSOLA shows its intrinsic change.
# ============================================================
selfDone = 0
if engine_self_test
    saveT# = dtT#
    saveV# = dtV#
    saveN = nDt
    dtT# = {sTmin, sTmax}
    dtV# = {1, 1}
    nDt = 2
    if resynthesis = 1
        @wsola
        neutral = wsola.result
    else
        selectObject: sound
        nMan = To Manipulation: 0.01, pitch_floor_Hz, pitch_ceiling_Hz
        neutral = Get resynthesis (overlap-add)
        removeObject: nMan
    endif
    dtT# = saveT#
    dtV# = saveV#
    nDt = saveN
    selectObject: neutral
    nNeu = Get number of samples
    Formula: "self - object[sound, col]"
    selfMax = Get absolute extremum: 0, 0, "None"
    selfRms = Get root-mean-square: 0, 0
    removeObject: neutral
    selfSNR = undefined
    if selfRms > 0
        selfSNR = 20 * log10(inRms / selfRms)
    endif
    selfDone = 1
endif

# ============================================================
# 13c. OPTIONAL CLICK TRACK  (stereo preview: L audio, R click)
#   Built from a copy of the result, so sample count, rate and time
#   axis are identical by construction. The click is an independent
#   clock: grid times G + kT only, extended over the whole Sound (also
#   before the origin, as a count-in). Each click starts at its grid
#   time: tau = time since the latest grid point, burst for tau < 5 ms.
# ============================================================
clickStereo = 0
if click_track > 1
    if click_track = 2
        clickT = beatSec
    else
        clickT = gridT
    endif
    g$ = fixed$(gridG, 9)
    c$ = fixed$(clickT, 9)
    tau$ = "((x - " + g$ + ") - floor((x - " + g$ + ") / " + c$ + ") * " + c$ + ")"
    win$ = "(0.5 - 0.5 * cos(2 * pi * " + tau$ + " / 0.005))"
    aBeat$ = fixed$(click_level, 4)
    aSub$ = fixed$(click_level * 0.6, 4)
    if click_track = 3 and unitsPerBeat > 1
        kk$ = "round(((x - " + g$ + ") - " + tau$ + ") / " + c$ + ")"
        clickF$ = "if " + tau$ + " < 0.005 then " + win$ + " * (if (" + kk$ + " mod " + string$(unitsPerBeat) + ") = 0 then " +
        ... aBeat$ + " * sin(2 * pi * 2000 * " + tau$ + ") else " + aSub$ + " * sin(2 * pi * 1500 * " + tau$ + ") fi) else 0 fi"
    else
        clickF$ = "if " + tau$ + " < 0.005 then " + win$ + " * " + aBeat$ + " * sin(2 * pi * 2000 * " + tau$ + ") else 0 fi"
    endif
    selectObject: result
    clickMono = Copy: "aq_click"
    grooveClick = (grid_type > 1 and gStr > 0 and click_follows = 1)
    if grooveClick = 0
        Formula: clickF$
    else
        # Groove click: one 5 ms burst per (groove) grid position, written
        # into its own window; beats 2000 Hz, subdivisions 1500 Hz.
        Formula: "0"
        cStep = 1
        if click_track = 2
            cStep = unitsPerBeat
        endif
        kc1 = ceiling((sTmin - gridG) / gridT) - 1
        kc2 = floor((outTmax - gridG) / gridT) + 1
        for kc from kc1 to kc2
            if (kc - floor(kc / cStep) * cStep) = 0
                @gridPos: kc
                tc = gridPos.result
                if tc >= sTmin and tc + 0.005 <= outTmax
                    if (kc - floor(kc / unitsPerBeat) * unitsPerBeat) = 0
                        aC$ = aBeat$
                        fC$ = "2000"
                    else
                        aC$ = aSub$
                        fC$ = "1500"
                    endif
                    t0$ = fixed$(tc, 9)
                    Formula (part): tc, tc + 0.005, 1, 1, "(0.5 - 0.5 * cos(2 * pi * (x - " + t0$ + ") / 0.005)) * " + aC$ +
                    ... " * sin(2 * pi * " + fC$ + " * (x - " + t0$ + "))"
                endif
            endif
        endfor
    endif
    selectObject: result
    plusObject: clickMono
    clickStereo = Combine to stereo
    Rename: outName$ + "_Click"
    removeObject: clickMono
endif

# Rounded before printing: fixed$ ignores precision for tiny values.
errUs = round(maxMapErr * 1e6 * 1000) / 1000
if errUs < 0.0005
    errUs$ = "0.000"
else
    errUs$ = fixed$(errUs, 3)
endif

# ============================================================
# 13. ANALYSIS REPORT
# ============================================================
if useTextGrid
    methodLabel$ = "TextGrid tier """ + tgName$ + """"
elsif onset_detection = 1
    methodLabel$ = "intensity slope"
elsif onset_detection = 2
    methodLabel$ = "spectral flux (vibrato-suppressed)"
else
    methodLabel$ = "hybrid (intensity slope + spectral flux)"
endif

if show_analysis_report
    writeInfoLine: "=== Audio Quantizer v1.4 ==="
    appendInfoLine: ""
    appendInfoLine: "AUDIO"
    appendInfoLine: "  Input:          ", soundName$
    appendInfoLine: "  Duration:       ", fixed$(sDur, 4), " s   (domain ", fixed$(sTmin, 4), " - ", fixed$(sTmax, 4), " s)"
    appendInfoLine: "  Sampling rate:  ", fixed$(sr, 0), " Hz   Channels: ", nCh
    appendInfoLine: ""
    appendInfoLine: "SETTINGS"
    appendInfoLine: "  Tempo:          ", fixed$(tempo_BPM, 2), " BPM (quarter note = ", fixed$(beatSec * 1000, 2), " ms)"
    appendInfoLine: "  Grid:           ", divLong$, " = ", fixed$(gridT * 1000, 3), " ms"
    appendInfoLine: "  Grid origin:    ", originLabel$, " (", fixed$(gridG - sTmin, 4), " s)"
    if grid_type > 1
        appendInfoLine: "  Groove:         ", grooveSrc$, ", strength ", fixed$(groove_strength_percent, 0), " %, pattern ", grooveP, " slots"
    endif
    appendInfoLine: "  Strength:       ", fixed$(quantization_strength_percent, 1), " %   Max shift: ", shiftLabel$
    appendInfoLine: "  Profile:        ", profileLabel$, "  (ratio limits apply to voiced sound; silence 0.25-3.0, unvoiced 0.80-1.25)"
    appendInfoLine: "  Ratio limits:   ", fixed$(rMin, 3), " - ", fixed$(rMax, 3), " (voiced)   Attack protection: ", fixed$(attack_protection_ms, 1), " ms"
    appendInfoLine: "  Onset method:   ", methodLabel$
    if useTextGrid = 0
        appendInfoLine: "  Sensitivity:    ", fixed$(onset_sensitivity, 2), "  (threshold = local mean + ", fixed$(3 / onset_sensitivity, 2), " x robust spread)"
    endif
    if resynthesis = 1
        appendInfoLine: "  Resynthesis:    WSOLA (no pitch analysis)"
    else
        appendInfoLine: "  Resynthesis:    PSOLA, pitch ", fixed$(pitch_floor_Hz, 0), " - ", fixed$(pitch_ceiling_Hz, 0), " Hz"
    endif
    appendInfoLine: ""
    appendInfoLine: "DETECTION"
    if useTextGrid
        appendInfoLine: "  Points in tier: ", nCandidates
    else
        appendInfoLine: "  Candidates:     ", nCandidates, " (above threshold, before separation)"
        appendInfoLine: "  Min separation: ", fixed$(minimum_onset_separation_ms, 0), " ms"
    endif
    appendInfoLine: "  Accepted:       ", nOn
    if grid_type > 1 and gStr > 0
        appendInfoLine: "  Mean distance of the onsets to the nearest grid point: straight ", fixed$(dStraight * 1000, 1),
        ... " ms, groove grid ", fixed$(dUsed * 1000, 1), " ms"
    endif
    appendInfoLine: "  Grid fit (phase concentration): grid R ", fixed$(fitR, 2), ", beat R ", fixed$(fitRbeat, 2),
    ... "   (1 = perfect, chance ~", fixed$(fitChance, 2), ")"
    appendInfoLine: "  Best-fitting offset: grid ", fixed$(fitOff * 1000, 1), " ms, beat ", fixed$(fitOffBeat * 1000, 1), " ms (use with Grid origin = Manual offset)"
    appendInfoLine: "  Grid collisions resolved: ", nCollisions, "  (not quantized: ", nCollKept, ", of which nudged by neighbours: ", nCollNudged, ")"
    appendInfoLine: ""
    appendInfoLine: "TIME MAPPING"
    appendInfoLine: "  On requested target:       ", nOnTarget
    appendInfoLine: "  Exactly on grid point:     ", nOnGrid, " of ", nOn
    appendInfoLine: "  Constrained (partial):     ", nConstrained
    appendInfoLine: "  Already on grid / no move: ", nAlready
    appendInfoLine: "  Left unchanged (|shift| < 0.5 ms): ", nUnchanged
    appendInfoLine: "  Mean |shift|:   ", fixed$(meanAbs * 1000, 2), " ms   Max |shift|: ", fixed$(maxAbs * 1000, 2), " ms"
    appendInfoLine: "  Local ratio (tier values):  ", fixed$(rLow, 3), " - ", fixed$(rHigh, 3)
    appendInfoLine: "  Material (10 ms frames): silence ", fixed$(100 * nSil / nW, 0), " %, voiced ", fixed$(100 * nVoi / nW, 0),
    ... " %, unvoiced ", fixed$(100 * nUnv / nW, 0), " %  (stretch weights 3 / 1 / 0.2, attacks 0)"
    if resynth
        appendInfoLine: "  DurationTier points:        ", nDt
        appendInfoLine: "  Predicted output duration:  ", fixed$(predictedDur, 6), " s"
        appendInfoLine: "  Actual output duration:     ", fixed$(outDur, 6), " s   (", durDiffSamp, " samples vs input)"
        appendInfoLine: "  Max DurationTier anchor error: ", errUs$, " us (numerical mapping only)"
        if resynthesis = 1
            appendInfoLine: "  Resynthesis: WSOLA, 30 ms grains; ", wsola.nCopy + 1, " of ", wsola.nG, " grains copied as plain continuation, ", wsola.nSearch, " aligned by correlation"
        else
            appendInfoLine: "  Resynthesis: PSOLA overlap-add (pitch tier unchanged)"
        endif
    else
        appendInfoLine: "  Output duration:            ", fixed$(outDur, 6), " s"
        if strength = 0
            appendInfoLine: "  Strength 0 %: output is an unprocessed copy (no resynthesis)."
        else
            appendInfoLine: "  No onset could move under the current limits: output is an unprocessed copy."
        endif
    endif
    if peakGuard
        appendInfoLine: "  Peak guard: output peak ", fixed$(outPeak, 3), " attenuated to 0.99"
    endif
    appendInfoLine: ""
    if grid_type > 1
        appendInfoLine: "GROOVE TEMPLATE (", grooveSrc$, ")"
        if grid_type = 2
            if refFitAccepted
                appendInfoLine: "  Reference: ", nRef, " onsets; tempo given ", fixed$(refGivenBPM, 2), " BPM, fitted ", fixed$(refFitBPM, 2), " BPM (least squares)"
            else
                appendInfoLine: "  Reference: ", nRef, " onsets; tempo ", fixed$(refGivenBPM, 2), " BPM (fit rejected: more than 8 % away)"
            endif
            if reference_downbeat = 1
                appendInfoLine: "  Reference downbeat: first detected onset (assumed to be a downbeat)"
            else
                appendInfoLine: "  Reference downbeat: manual offset ", fixed$(reference_offset_ms, 1), " ms"
            endif
        endif
        appendInfoLine: "  slot  beat.sub   offset (% of slot)   at this tempo (ms)   observations   spread (% of slot)"
        nObsSlots = 0
        for sl to grooveP
            if grooveN#[sl] > 0
                nObsSlots += 1
            endif
            @padLeft: string$(sl), 6
            c1$ = padLeft.result$
            @padLeft: string$(floor((sl - 1) / unitsPerBeat) + 1) + "." + string$(((sl - 1) mod unitsPerBeat) + 1), 10
            c2$ = padLeft.result$
            if grooveN#[sl] > 0
                @padLeft: fixed$(100 * grooveOff#[sl], 1), 21
                c3$ = padLeft.result$
                @padLeft: fixed$(gStr * grooveOff#[sl] * gridT * 1000, 1), 21
                c4$ = padLeft.result$
                @padLeft: string$(grooveN#[sl]), 15
                c5$ = padLeft.result$
                @padLeft: fixed$(100 * grooveSpread#[sl], 1), 21
                c6$ = padLeft.result$
            else
                c3$ = "         not observed"
                c4$ = "       0 (straight)"
                c5$ = "              0"
                c6$ = ""
            endif
            appendInfoLine: c1$, c2$, c3$, c4$, c5$, c6$
        endfor
        appendInfoLine: "  Observed slots: ", nObsSlots, " of ", grooveP, "; unobserved slots stay on the straight grid."
        appendInfoLine: "  Only timing is transferred - not dynamics, articulation or timbre."
        if grooveTable
            appendInfoLine: "  Groove Table kept in the Objects list for reuse (Grid type = Groove from a groove Table)."
        endif
        appendInfoLine: ""
    endif
    appendInfoLine: "MEASURED OUTPUT CHECK (onsets re-detected in the quantized Sound)"
    if chkDone
        appendInfoLine: "  Targets matched within 40 ms: ", chkMatched, " of ", nOn, "   unmatched: ", chkMissed, "   extra attacks found: ", chkExtra
        if chkMatched > 0
            appendInfoLine: "  |measured attack - target|:  mean ", fixed$(chkMean * 1000, 2), " ms   max ", fixed$(chkMax * 1000, 2), " ms"
        endif
        if chkGridN > 0
            appendInfoLine: "  |measured attack - grid|:    mean ", fixed$(chkGridMean * 1000, 2), " ms   max ", fixed$(chkGridMax * 1000, 2), " ms   (", chkGridN, " events targeted at a grid point)"
        endif
        appendInfoLine: "  One-to-one, order-preserving matching. Same detector on input and output, so its"
        appendInfoLine: "  bias largely cancels; resolution 5 ms. Unmatched targets include onsets the detector"
        appendInfoLine: "  simply does not find again (borderline detections), not only timing errors."
    else
        appendInfoLine: "  Not run: no resynthesis took place (output is a copy of the input)."
    endif
    if selfDone
        appendInfoLine: ""
        appendInfoLine: "ENGINE SELF-TEST (all ratios exactly 1, no timing change)"
        appendInfoLine: "  Samples: input ", nInSamp, ", neutral output ", nNeu
        if selfMax < 1e-9
            appendInfoLine: "  Max |neutral - input| < 1e-9  ->  exact reconstruction (floating-point rounding only)"
        else
            appendInfoLine: "  Max |neutral - input|: ", fixed$(selfMax, 6), "   SNR of reconstruction: ", fixed$(selfSNR, 1), " dB"
        endif
    endif
    if clickStereo
        appendInfoLine: ""
        appendInfoLine: "CLICK TRACK"
        if click_track = 2
            appendInfoLine: "  Quarter-note beats every ", fixed$(beatSec * 1000, 2), " ms (2000 Hz, 5 ms, level ", fixed$(click_level, 2), ")"
        else
            appendInfoLine: "  Grid every ", fixed$(gridT * 1000, 2), " ms; beats 2000 Hz, subdivisions 1500 Hz at 60 % level"
        endif
        appendInfoLine: "  Clock origin = grid origin (", fixed$(gridG - sTmin, 4), " s); independent of the onsets"
        appendInfoLine: "  Stereo preview: ", outName$, "_Click  (L = quantized audio, R = click)"
    endif
    if nOn = 1
        appendInfoLine: "  Note: only one onset; with origin = first onset it is the reference and cannot move."
    endif
    if nWarn > 0
        appendInfoLine: ""
        appendInfoLine: "WARNINGS"
        appendInfo: warnings$
    endif
    appendInfoLine: ""
    appendInfoLine: "ONSETS (seconds relative to Sound start; shift in ms)"
    @padLeft: "#", 4
    h1$ = padLeft.result$
    appendInfoLine: h1$, "    source      grid   request    target    shift  status"
    nShow = min(nOn, 200)
    for i to nShow
        @padLeft: string$(i), 4
        c1$ = padLeft.result$
        @padLeft: fixed$(onsets#[i] - sTmin, 4), 10
        c2$ = padLeft.result$
        if collision#[i] = 1
            c3$ = "         -"
        else
            @padLeft: fixed$(q#[i] - sTmin, 4), 10
            c3$ = padLeft.result$
        endif
        @padLeft: fixed$(req#[i] - sTmin, 4), 10
        c4$ = padLeft.result$
        @padLeft: fixed$(y#[i + 1] - sTmin, 4), 10
        c5$ = padLeft.result$
        @msStr: y#[i + 1] - onsets#[i]
        @padLeft: msStr.result$, 8
        c6$ = padLeft.result$
        @statusText: status#[i]
        st$ = statusText.result$
        appendInfoLine: c1$, c2$, c3$, c4$, c5$, c6$, "  ", st$
    endfor
    if nOn > nShow
        appendInfoLine: "  ... ", nOn - nShow, " more onsets not listed"
    endif
    appendInfoLine: ""
    appendInfoLine: "Note: 'target' is the DurationTier mapping (exact by construction). Where the"
    appendInfoLine: "attacks really sit after PSOLA is the MEASURED OUTPUT CHECK above (5 ms frames)."
endif

# ============================================================
# 16. VISUALIZATION  (8-inch canvas, Praat AudioTools layout)
# ============================================================
if draw_visualization
    Erase all
    Line width: 1
    Solid line
    Colour: "Black"

    # Shared time axis = input domain (output duration equals it up to
    # PSOLA rounding).
    vx1 = sTmin
    vx2 = max(sTmax, outTmax)

    # Grid lines to draw (beats only when the grid would be too dense).
    gFirst = ceiling((vx1 - gridG) / gridT) - 1
    gLast = floor((vx2 - gridG) / gridT) + 1
    nGridLines = gLast - gFirst + 1
    gridStepUnits = 1
    if nGridLines > 400
        gridStepUnits = unitsPerBeat
    endif

    selectObject: sound
    pkIn = Get absolute extremum: 0, 0, "None"
    selectObject: result
    pkOut = Get absolute extremum: 0, 0, "None"
    pk = max(pkIn, pkOut) * 1.05
    if pk <= 0
        pk = 1
    endif

    span = vx2 - vx1
    tStep = 10 ^ floor(log10(span / 6))
    if span / tStep > 12
        tStep = tStep * 5
    elsif span / tStep > 6
        tStep = tStep * 2
    endif

    # ---------- Title strip ----------
    Font size: 13
    Select inner viewport: 0.6, 7.7, 0.10, 0.45
    Axes: 0, 1, 0, 1
    @picText: soundName$
    ttl$ = "##Audio Quantizer v1.4##   " + picText.result$
    Text: 0.5, "centre", 0.5, "half", ttl$
    Font size: 7
    Select inner viewport: 0.6, 7.7, 0.45, 0.70
    Axes: 0, 1, 0, 1
    sub$ = fixed$(tempo_BPM, 1) + " BPM   grid " + gridLabel$ + " (" + fixed$(gridT * 1000, 1) + " ms)   strength " +
    ... fixed$(quantization_strength_percent, 0) + "\%    max shift " + shiftLabel$ + "   origin: " + originLabel$
    Text: 0.5, "centre", 0.5, "half", sub$

    # ---------- Panel layout (inches) ----------
    # caption strip 0.25 in above each data panel.
    p1t = 1.00
    p1b = 2.40
    p2t = 2.70
    p2b = 3.90
    p3t = 4.20
    p3b = 5.60
    p4t = 5.90
    p4b = 6.90
    p5t = 7.45
    p5b = 8.45

    # ===== Panel 1: original waveform, grid, original onsets =====
    Font size: 7
    Select inner viewport: 0.6, 7.7, p1t - 0.25, p1t
    Axes: 0, 1, 0, 1
    Text: 0, "left", 0.35, "half", "##1  Original Sound## - grid lines (grey, beats darker) and detected onsets (red)"
    Select inner viewport: 0.6, 7.7, p1t, p1b
    Axes: vx1, vx2, -pk, pk
    selectObject: sound
    Colour: {0.55, 0.55, 0.55}
    Draw: vx1, vx2, -pk, pk, "no", "Curve"
    Select inner viewport: 0.6, 7.7, p1t, p1b
    Axes: vx1, vx2, -pk, pk
    for g from gFirst to gLast
        if (g mod gridStepUnits) = 0
            @gridPos: g
            tg = gridPos.result
            if (g mod unitsPerBeat) = 0
                Colour: {0.45, 0.45, 0.45}
            else
                Colour: {0.80, 0.80, 0.80}
            endif
            Dotted line
            if tg >= vx1 and tg <= vx2
                Draw line: tg, -pk, tg, pk
            endif
        endif
    endfor
    Solid line
    Colour: {0.85, 0.25, 0.20}
    Line width: 1.5
    for i to nOn
        Draw line: onsets#[i], -pk * 0.95, onsets#[i], pk * 0.95
    endfor
    Line width: 1
    Colour: "Black"
    Select inner viewport: 0.6, 7.7, p1t, p1b
    Axes: vx1, vx2, -pk, pk
    Draw inner box
    Marks bottom every: 1, tStep, "no", "yes", "no"

    # ===== Panel 2: mapping (source rail -> target rail) =====
    Select inner viewport: 0.6, 7.7, p2t - 0.25, p2t
    Axes: 0, 1, 0, 1
    Text: 0, "left", 0.35, "half", "##2  Onset mapping## - source time (top) to output time (bottom); blue on target, orange constrained, grey kept"
    Select inner viewport: 0.6, 7.7, p2t, p2b
    Axes: vx1, vx2, 0, 1
    for g from gFirst to gLast
        if (g mod gridStepUnits) = 0
            @gridPos: g
            tg = gridPos.result
            if (g mod unitsPerBeat) = 0
                Colour: {0.45, 0.45, 0.45}
            else
                Colour: {0.80, 0.80, 0.80}
            endif
            Dotted line
            if tg >= vx1 and tg <= vx2
                Draw line: tg, 0.0, tg, 0.22
            endif
        endif
    endfor
    Solid line
    Colour: {0.70, 0.70, 0.70}
    Draw line: vx1, 0.85, vx2, 0.85
    Draw line: vx1, 0.15, vx2, 0.15
    for i to nOn
        if status#[i] = 1
            Colour: {0.20, 0.40, 0.80}
        elsif status#[i] = 2
            Colour: {0.95, 0.55, 0.10}
        else
            Colour: {0.55, 0.55, 0.55}
        endif
        Line width: 1.2
        Draw line: onsets#[i], 0.85, y#[i + 1], 0.15
        Line width: 1
        Colour: {0.85, 0.25, 0.20}
        Paint circle (mm): {0.85, 0.25, 0.20}, onsets#[i], 0.85, 0.5
        Paint circle (mm): {0.20, 0.40, 0.80}, y#[i + 1], 0.15, 0.5
    endfor
    Colour: "Black"
    Select inner viewport: 0.6, 7.7, p2t, p2b
    Axes: vx1, vx2, 0, 1
    Draw inner box
    Marks bottom every: 1, tStep, "no", "yes", "no"

    # ===== Panel 3: quantized waveform, grid, target onsets =====
    Select inner viewport: 0.6, 7.7, p3t - 0.25, p3t
    Axes: 0, 1, 0, 1
    Text: 0, "left", 0.35, "half", "##3  Quantized Sound## - grid lines, mapped targets (blue), attacks re-detected in the output (green, top)"
    Select inner viewport: 0.6, 7.7, p3t, p3b
    Axes: vx1, vx2, -pk, pk
    selectObject: result
    Colour: {0.55, 0.55, 0.55}
    Draw: vx1, vx2, -pk, pk, "no", "Curve"
    Select inner viewport: 0.6, 7.7, p3t, p3b
    Axes: vx1, vx2, -pk, pk
    for g from gFirst to gLast
        if (g mod gridStepUnits) = 0
            @gridPos: g
            tg = gridPos.result
            if (g mod unitsPerBeat) = 0
                Colour: {0.45, 0.45, 0.45}
            else
                Colour: {0.80, 0.80, 0.80}
            endif
            Dotted line
            if tg >= vx1 and tg <= vx2
                Draw line: tg, -pk, tg, pk
            endif
        endif
    endfor
    Solid line
    Colour: {0.20, 0.40, 0.80}
    Line width: 1.5
    for i to nOn
        Draw line: y#[i + 1], -pk * 0.95, y#[i + 1], pk * 0.95
    endfor
    if chkDone
        for jj to nChkOut
            Paint rectangle: {0.15, 0.60, 0.25}, chkOut#[jj] - (vx2 - vx1) * 0.0015, chkOut#[jj] + (vx2 - vx1) * 0.0015, pk * 0.78, pk * 0.98
        endfor
    endif
    Line width: 1
    Colour: "Black"
    Select inner viewport: 0.6, 7.7, p3t, p3b
    Axes: vx1, vx2, -pk, pk
    Draw inner box
    Marks bottom every: 1, tStep, "no", "yes", "no"

    # ===== Panel 4: local time ratio (DurationTier) =====
    Select inner viewport: 0.6, 7.7, p4t - 0.25, p4t
    Axes: 0, 1, 0, 1
    Text: 0, "left", 0.35, "half", "##4  Local time ratio## (output / input) - weighted DurationTier (attacks 1, rests absorb most); dashed red = voiced limits"
    # Axis from the data (rests may go beyond the voiced limits);
    # Draw line does not clip, so the range must contain every value.
    yLo = min(min(rMin, 1), rLow) - 0.05
    yHi = max(max(rMax, 1), rHigh) + 0.05
    if resynth = 0
        yLo = min(rMin, 1) - 0.05
        yHi = max(rMax, 1) + 0.05
    endif
    yStep = 0.25
    if yHi - yLo > 1.6
        yStep = 0.5
    endif
    Select inner viewport: 0.6, 7.7, p4t, p4b
    Axes: vx1, vx2, yLo, yHi
    Colour: {0.85, 0.25, 0.20}
    Dashed line
    Draw line: vx1, rMin, vx2, rMin
    Draw line: vx1, rMax, vx2, rMax
    Colour: {0.60, 0.60, 0.60}
    Dotted line
    Draw line: vx1, 1, vx2, 1
    Solid line
    Colour: {0.20, 0.40, 0.80}
    Line width: 1.5
    if resynth and nDt >= 1
        Draw line: vx1, dtV#[1], dtT#[1], dtV#[1]
        for k from 2 to nDt
            Draw line: dtT#[k - 1], dtV#[k - 1], dtT#[k], dtV#[k]
        endfor
        Draw line: dtT#[nDt], dtV#[nDt], vx2, dtV#[nDt]
    else
        Draw line: vx1, 1, vx2, 1
    endif
    Line width: 1
    Colour: "Black"
    Select inner viewport: 0.6, 7.7, p4t, p4b
    Axes: vx1, vx2, yLo, yHi
    Draw inner box
    Marks bottom every: 1, tStep, "yes", "yes", "no"
    Marks left every: 1, yStep, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"

    # ===== Panel 5: summary =====
    Select inner viewport: 0.6, 7.7, p5t, p5b
    Axes: 0, 1, 0, 1
    Paint rectangle: {0.94, 0.94, 0.94}, 0, 1, 0, 1
    Colour: "Black"
    Font size: 7
    @picText: methodLabel$
    m$ = picText.result$
    Text: 0.02, "left", 0.90, "half", "##Summary##   onsets " + string$(nOn) + " accepted of " + string$(nCandidates) + " candidates   method: " + m$
    Text: 0.02, "left", 0.72, "half", "On target " + string$(nOnTarget) + "   exactly on grid " + string$(nOnGrid) +
    ... "   constrained " + string$(nConstrained) + "   collision (not quantized) " + string$(nCollKept) + "   already on grid " + string$(nAlready)
    Text: 0.02, "left", 0.54, "half", "Mean |shift| " + fixed$(meanAbs * 1000, 1) + " ms   max |shift| " + fixed$(maxAbs * 1000, 1) +
    ... " ms   ratio levels " + fixed$(rLow, 3) + " - " + fixed$(rHigh, 3) + "   limits " + fixed$(rMin, 2) + " - " + fixed$(rMax, 2)
    if resynth
        l4$ = "Duration in " + fixed$(sDur, 4) + " s   predicted " + fixed$(predictedDur, 4) + " s   actual " + fixed$(outDur, 4) +
        ... " s   max tier anchor error " + errUs$ + " us (numerical)"
    else
        l4$ = "No resynthesis: output is an unprocessed copy (" + fixed$(outDur, 4) + " s)"
    endif
    Text: 0.02, "left", 0.36, "half", l4$
    if chkDone
        l5$ = "Measured in output: " + string$(chkMatched) + "/" + string$(nOn) + " attacks found, |attack - target| mean " +
        ... fixed$(chkMean * 1000, 1) + " ms, max " + fixed$(chkMax * 1000, 1) + " ms;  extra attacks " + string$(chkExtra)
        if clickStereo
            l5$ = l5$ + ";  click preview: " + outName$ + "_Click"
        endif
        @picText: l5$
        Text: 0.02, "left", 0.18, "half", picText.result$
    endif
    Select inner viewport: 0.6, 7.7, p5t, p5b
    Axes: 0, 1, 0, 1
    Draw inner box

    Font size: 10
    Select outer viewport: 0, 8, 0, p5b + 0.15
endif

# ============================================================
# 17-18. FINAL SELECTION AND PLAYBACK
# ============================================================
# Play the stereo click preview when it exists, otherwise the mono
# result. Final selection: result (+ click preview) (+ TextGrid).
if play_result
    if clickStereo
        selectObject: clickStereo
    else
        selectObject: result
    endif
    Play
endif
selectObject: result
if clickStereo
    plusObject: clickStereo
endif
if tgOut
    plusObject: tgOut
endif
if grooveTable
    plusObject: grooveTable
endif
