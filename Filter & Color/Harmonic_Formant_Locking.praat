# ============================================================
# Praat AudioTools - Harmonic_Formant_Locking.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 3.1 (2026) - Suite-standard visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Harmonic Formant Locking v3.0
#
# Architecture:
#   - Pitch and FormantPath are ANALYSIS ONLY.
#   - Formants are robust spectral-envelope LANDMARKS, not resonator poles.
#   - The source landmark region is broadly attenuated while the matching
#     harmonic region is broadly enhanced in the ORIGINAL complex spectrum.
#   - Real and imaginary bins receive the same gain => phase is preserved.
#   - Dynamic mode uses integer-sample Hann/Hann^2 WOLA.
#   - Stable-note mode is time invariant and therefore uses one FFT/channel.
#
# v3.0 replaces the remaining fragile parts of v2.0:
#   - No frame-by-frame formant trajectory drives the audio. FormantPath is
#     reduced to robust static medians/IQRs; only F0 may move dynamically.
#   - Harmonic targets are ALWAYS integer n * F0. There is no frequency
#     averaging between old/new targets, so an intermediate non-harmonic
#     target cannot be created.
#   - No blind max_harmonic = 20 clamp. The allowed harmonic range is derived
#     from F0 and Nyquist for every grain, with a generous safety cap of 64.
#   - Octave mode stays on powers of two when constrained by Nyquist.
#   - Dynamic grain times are computed directly from integer sample indices;
#     there is no Formant-frame offset/look-ahead mapping.
#   - Preserve_frame_energy now means exact frame-energy compensation rather
#     than a hidden +/-3 dB approximation.
#   - Dry/Wet = 0 and Lock = 0 are true full bypasses before analysis.
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
originalName$ = selected$("Sound")

form Harmonic Formant Locking v3.1
    optionmenu Preset: 2
        option Custom
        option Safe Start (20%)
        option Subtle Shimmer (35%)
        option Moderate Bell (60%)
        option Strong Metal (85%)
        option Extreme Synth (100%)
    real Lock_strength_(%) 35
    real Max_shape_dB 9
    optionmenu Tracking_mode: 1
        option Dynamic F0 / stable formant landmarks
        option Stable note (one fixed curve)
    optionmenu Snap_mode: 1
        option Nearest harmonic
        option Upward harmonic
        option Downward harmonic
        option Octave harmonic (powers of 2)
    boolean Preserve_frame_energy 1
    boolean Stabilize_F0 1
    boolean Gate_weak_unvoiced 1
    real Min_intensity_dB -25
    real Dry_wet_mix 1.0
    optionmenu Output_level_mode: 2
        option Natural level
        option Safety ceiling (attenuate only)
        option Match input RMS + safety ceiling
        option Peak normalize
    positive Ceiling_peak 0.95
    boolean Show_diagnostics 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# ADVANCED SETTINGS
# ============================================================
max_formants = 5
formant_time_step_s = 0.010
formant_window_s = 0.030
pre_emphasis = 35

# Broad envelope-region widths. These are not LPC bandwidths or filter Q.
region_floor_1 = 180
region_floor_2 = 260
region_floor_3 = 360
region_floor_4 = 450
region_floor_5 = 550
region_fraction = 0.22
spread_factor = 1.5
region_cap_hz = 900

# Dynamic spectral engine.
dynamic_update_hz = 50
min_grain_ms = 40
max_grain_ms = 80

# Harmonic assignment.
min_harmonic = 2
harmonic_safety_cap = 64
harmonic_hysteresis = 0.22
f0_median_half_window = 2

# Per-landmark musical weights.
formant_weight_1 = 0.60
formant_weight_2 = 1.00
formant_weight_3 = 1.00
formant_weight_4 = 0.80
formant_weight_5 = 0.60
formant_weights# = {formant_weight_1, formant_weight_2, formant_weight_3,
    ... formant_weight_4, formant_weight_5}

# ============================================================
# PRESETS
# ============================================================
if preset = 2
    lock_strength = 20
    max_shape_dB = 6
    presetName$ = "SafeStart"
elsif preset = 3
    lock_strength = 35
    max_shape_dB = 9
    presetName$ = "SubtleShimmer"
elsif preset = 4
    lock_strength = 60
    max_shape_dB = 12
    presetName$ = "ModerateBell"
elsif preset = 5
    lock_strength = 85
    max_shape_dB = 15
    presetName$ = "StrongMetal"
elsif preset = 6
    lock_strength = 100
    max_shape_dB = 18
    snap_mode = 4
    presetName$ = "ExtremeSynth"
else
    presetName$ = "Custom"
endif

lock_strength_norm = lock_strength / 100

# ============================================================
# INPUT / VALIDATION / TRUE BYPASS
# ============================================================
selectObject: sound
duration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels
originalXmin = Get start time
nyquist = sampleRate / 2
inputPeak = Get absolute extremum: 0, 0, "None"
inputRms = Get root-mean-square: 0, 0

if lock_strength < 0 or lock_strength > 100
    exitScript: "Lock_strength must be between 0 and 100."
endif
if max_shape_dB <= 0 or max_shape_dB > 36
    exitScript: "Max_shape_dB must be greater than 0 and at most 36."
endif
if dry_wet_mix < 0 or dry_wet_mix > 1
    exitScript: "Dry_wet_mix must be between 0 and 1."
endif
if ceiling_peak <= 0 or ceiling_peak > 1
    exitScript: "Ceiling_peak must be greater than 0 and at most 1."
endif

clearinfo
writeInfoLine: "=== Harmonic Formant Locking v3.1 ==="
appendInfoLine: "Spectral-envelope landmarks -> exact harmonic targets (n x F0)."
appendInfoLine: "No LPC resynthesis, no FormantGrid filtering, original complex phase preserved."
appendInfoLine: ""
appendInfoLine: "Input: ", originalName$, " (", fixed$(duration, 3), " s, ", numChannels,
    ... " ch, ", sampleRate, " Hz)"
appendInfoLine: "Preset: ", presetName$, " | Lock ", fixed$(lock_strength, 0),
    ... "% | Shape +/-", fixed$(max_shape_dB, 1), " dB"

if lock_strength = 0 or dry_wet_mix = 0
    if lock_strength = 0
        appendInfoLine: "Lock strength is 0: full bypass."
    else
        appendInfoLine: "Dry/Wet is 0: full bypass."
    endif
    selectObject: sound
    finalOutput = Copy: originalName$ + "_HarmonicLock_Bypass"
    selectObject: finalOutput
    if play_result
        Play
    endif
    exitScript: ""
endif

if inputRms = undefined or inputRms < 0.0000001
    exitScript: "The input is silent or near-silent; there is no reliable pitch/formant structure to lock."
endif
if duration < 0.12
    exitScript: "Sound is too short: use at least 120 ms for pitch and formant analysis."
endif

# FormantPath searches ceilings above the supplied value; leave Nyquist margin.
maxFormantHz = min(5500, (nyquist - 80) / 1.22)
if maxFormantHz < 1200
    exitScript: "Sample rate is too low for reliable multi-formant analysis."
endif

# ============================================================
# WORK COPY AT TIME ZERO + ANALYSIS SOURCE
# ============================================================
selectObject: sound
workSound = Copy: "hfl_work"
Shift times to: "start time", 0

if numChannels > 1
    selectObject: workSound
    monoProbe = Convert to mono
    monoRms = Get root-mean-square: 0, 0
    if monoRms <> undefined and monoRms >= 0.0000001
        soundMono = monoProbe
        appendInfoLine: "Analysis source: mono fold"
    else
        removeObject: monoProbe
        bestRms = -1
        pickCh = 1
        for ch from 1 to numChannels
            selectObject: workSound
            probeCh = Extract one channel: ch
            probeRms = Get root-mean-square: 0, 0
            removeObject: probeCh
            if probeRms > bestRms
                bestRms = probeRms
                pickCh = ch
            endif
        endfor
        selectObject: workSound
        soundMono = Extract one channel: pickCh
        appendInfoLine: "Analysis source: channel ", pickCh,
            ... " (mono fold cancelled / near anti-phase)"
    endif
else
    selectObject: workSound
    soundMono = Copy: "hfl_analysis"
    appendInfoLine: "Analysis source: single channel"
endif

# ============================================================
# [1/4] ROBUST FORMANT LANDMARKS - ANALYSIS ONLY
# ============================================================
appendInfoLine: "[1/4] Measuring robust formant landmarks..."
selectObject: soundMono
formantPath = To FormantPath (burg): formant_time_step_s, max_formants, maxFormantHz,
    ... formant_window_s, pre_emphasis, 0.05, 4
formantObj = Extract Formant

validFormants = 0
for fn from 1 to max_formants
    selectObject: formantObj
    formant_'fn' = Get quantile: fn, 0, 0, "Hertz", 0.50
    q25_'fn' = Get quantile: fn, 0, 0, "Hertz", 0.25
    q75_'fn' = Get quantile: fn, 0, 0, "Hertz", 0.75

    if formant_'fn' <> undefined and formant_'fn' > 0 and formant_'fn' < nyquist - 80
        valid_'fn' = 1
        validFormants = validFormants + 1
        if q25_'fn' = undefined
            q25_'fn' = formant_'fn'
        endif
        if q75_'fn' = undefined
            q75_'fn' = formant_'fn'
        endif
        spread_'fn' = max(0, q75_'fn' - q25_'fn')

        if fn = 1
            floorW = region_floor_1
        elsif fn = 2
            floorW = region_floor_2
        elsif fn = 3
            floorW = region_floor_3
        elsif fn = 4
            floorW = region_floor_4
        else
            floorW = region_floor_5
        endif
        width_'fn' = max(floorW, formant_'fn' * region_fraction)
        width_'fn' = max(width_'fn', floorW + spread_factor * spread_'fn')
        width_'fn' = min(width_'fn', region_cap_hz)

        appendInfoLine: "  F", fn, " = ", fixed$(formant_'fn', 1), " Hz | IQR ",
            ... fixed$(q25_'fn', 0), "-", fixed$(q75_'fn', 0),
            ... " | envelope width ", fixed$(width_'fn', 0), " Hz"
    else
        valid_'fn' = 0
        width_'fn' = 0
    endif
endfor

removeObject: formantPath, formantObj
if validFormants < 2
    removeObject: soundMono, workSound
    exitScript: "Fewer than two reliable formant landmarks were found."
endif

# ============================================================
# [2/4] PITCH + INTENSITY
# ============================================================
appendInfoLine: "[2/4] Analyzing F0 and intensity..."
selectObject: soundMono
pitchWide = To Pitch (cc): 0, 50, 15, "no", 0.03, 0.45, 0.01, 0.35, 0.14, 900
q10 = Get quantile: 0, 0, 0.10, "Hertz"
q90 = Get quantile: 0, 0, 0.90, "Hertz"
if q10 = undefined or q90 = undefined
    pitchFloor = 75
    pitchCeiling = 600
else
    pitchFloor = max(50, q10 * 0.80)
    pitchCeiling = min(900, q90 * 1.30)
endif
removeObject: pitchWide

selectObject: soundMono
pitch = To Pitch (cc): 0, pitchFloor, 15, "no", 0.03, 0.45, 0.01, 0.35, 0.14, pitchCeiling
selectObject: soundMono
intensity = To Intensity: 75, 0, "yes"

selectObject: pitch
stableF0 = Get quantile: 0, 0, 0.50, "Hertz"
if stableF0 = undefined or stableF0 <= 0
    removeObject: soundMono, pitch, intensity, workSound
    exitScript: "No reliable voiced F0 was found."
endif
appendInfoLine: "  Pitch range: ", fixed$(pitchFloor, 0), "-", fixed$(pitchCeiling, 0),
    ... " Hz | median F0 ", fixed$(stableF0, 1), " Hz"

# Structural confidence gate. A narrowband tone can make Burg/FormantPath
# report several nearly coincident peaks around the same spectral line. Those
# are not a usable spectral envelope. Require the landmark set to span a
# broad enough range before creative locking is allowed.
lowestLandmark = undefined
highestLandmark = undefined
for fn from 1 to max_formants
    if valid_'fn' = 1
        if lowestLandmark = undefined
            lowestLandmark = formant_'fn'
        endif
        highestLandmark = formant_'fn'
    endif
endfor
if lowestLandmark <> undefined and highestLandmark <> undefined
    envelopeSpan = highestLandmark - lowestLandmark
else
    envelopeSpan = 0
endif
minEnvelopeSpan = max(350, 1.25 * stableF0)
if envelopeSpan < minEnvelopeSpan
    appendInfoLine: "  Envelope confidence: LOW (landmark span ", fixed$(envelopeSpan, 1),
        ... " Hz < ", fixed$(minEnvelopeSpan, 1), " Hz). Returning input unchanged."
    removeObject: soundMono, pitch, intensity, workSound
    selectObject: sound
    finalOutput = Copy: originalName$ + "_HarmonicLock_NoReliableEnvelope"
    selectObject: finalOutput
    if play_result
        Play
    endif
    exitScript: ""
else
    appendInfoLine: "  Envelope confidence: OK (landmark span ", fixed$(envelopeSpan, 0), " Hz)"
endif

# ============================================================
# [3/4] TARGETS
# ============================================================
appendInfoLine: "[3/4] Building harmonic targets..."

targetChanges = 0
hysteresisHolds = 0
gatedCount = 0
lockedCount = 0

# ---------- STABLE NOTE: fixed F0, fixed formants => one static curve ----------
if tracking_mode = 2
    stableExpr$ = ""
    stableTerms = 0
    stableMaxH = min(harmonic_safety_cap, floor((nyquist - 80) / stableF0))

    for fn from 1 to max_formants
        stableTarget_'fn' = undefined
        stableHarm_'fn' = undefined
        if valid_'fn' = 1 and stableMaxH >= min_harmonic
            harmFloat = formant_'fn' / stableF0
            if snap_mode = 1
                harm = round(harmFloat)
            elsif snap_mode = 2
                harm = ceiling(harmFloat)
            elsif snap_mode = 3
                harm = floor(harmFloat)
            else
                harm = 2 ^ round(log2(harmFloat))
                while harm > stableMaxH and harm >= 2
                    harm = harm / 2
                endwhile
                while harm < min_harmonic
                    harm = harm * 2
                endwhile
            endif

            if snap_mode <> 4
                harm = max(min_harmonic, min(harm, stableMaxH))
            endif

            if harm >= min_harmonic and harm <= stableMaxH
                stableHarm_'fn' = harm
                stableTarget_'fn' = harm * stableF0
                amp = max_shape_dB * formant_weights#[fn] * lock_strength_norm
                if amp > 0.001 and abs(stableTarget_'fn' - formant_'fn') > 0.5
                    if stableTerms > 0
                        stableExpr$ = stableExpr$ + " + "
                    endif
                    stableExpr$ = stableExpr$ + fixed$(amp, 5) + " * (exp(-0.5*((x-" +
                        ... fixed$(stableTarget_'fn', 3) + ")/" + fixed$(width_'fn', 3) +
                        ... ")^2) - exp(-0.5*((x-" + fixed$(formant_'fn', 3) + ")/" +
                        ... fixed$(width_'fn', 3) + ")^2))"
                    stableTerms = stableTerms + 1
                endif
                appendInfoLine: "  F", fn, ": ", fixed$(formant_'fn', 0), " -> H",
                    ... fixed$(harm, 0), " = ", fixed$(stableTarget_'fn', 0), " Hz"
            endif
        endif
    endfor
    lockedCount = 1

# ---------- DYNAMIC F0: static formant landmarks, exact n*F0 per grain ----------
else
    # Integer-sample adaptive WOLA geometry. Fixed at 50 updates/s by default:
    # enough for ordinary vibrato, but substantially cheaper than v2's 80/s.
    hopSamples = round(sampleRate / dynamic_update_hz)
    if hopSamples < 1
        hopSamples = 1
    endif
    hopSec = hopSamples / sampleRate

    grainSamples = max(round(min_grain_ms / 1000 * sampleRate), 2 * hopSamples)
    grainSamples = min(grainSamples, round(max_grain_ms / 1000 * sampleRate))
    if grainSamples < 8
        grainSamples = 8
    endif
    grainSec = grainSamples / sampleRate

    selectObject: workSound
    totalSamples = Get number of samples
    padHeadSamples = floor(grainSamples / 2)
    coreEndSample = padHeadSamples + totalSamples
    desiredEndSample = coreEndSample + padHeadSamples
    numGrains = ceiling((desiredEndSample - grainSamples) / hopSamples) + 1
    if numGrains < 1
        numGrains = 1
    endif
    lastStartSample = 1 + (numGrains - 1) * hopSamples
    lastEndSample = lastStartSample + grainSamples - 1
    if lastEndSample < desiredEndSample
        numGrains = numGrains + 1
        lastStartSample = 1 + (numGrains - 1) * hopSamples
        lastEndSample = lastStartSample + grainSamples - 1
    endif
    padTailSamples = max(0, lastEndSample - coreEndSample)
    paddedSamples = padHeadSamples + totalSamples + padTailSamples
    paddedDur = paddedSamples / sampleRate
    padHead = padHeadSamples / sampleRate
    padTail = padTailSamples / sampleRate

    appendInfoLine: "  Dynamic engine: grain ", fixed$(grainSec * 1000, 1), " ms | hop ",
        ... fixed$(hopSec * 1000, 1), " ms | ", numGrains, " grains/channel"

    # Query raw F0/intensity at each grain centre in SOURCE-relative time.
    maxIntensityDb = -300
    for g from 1 to numGrains
        s1 = 1 + (g - 1) * hopSamples
        grainS1[g] = s1
        grainStart = (s1 - 1) / sampleRate
        sourceTime_'g' = grainStart + grainSec / 2 - padHead
        if sourceTime_'g' < 0
            sourceTime_'g' = 0
        endif
        if sourceTime_'g' > duration
            sourceTime_'g' = duration
        endif

        selectObject: pitch
        fv = Get value at time: sourceTime_'g', "Hertz", "Linear"
        if fv = undefined or fv < pitchFloor or fv > pitchCeiling
            f0raw_'g' = 0
        else
            f0raw_'g' = fv
        endif

        selectObject: intensity
        iv = Get value at time: sourceTime_'g', "Linear"
        if iv = undefined
            intDb_'g' = -300
        else
            intDb_'g' = iv
        endif
        if intDb_'g' > maxIntensityDb
            maxIntensityDb = intDb_'g'
        endif
    endfor

    gateThresholdDb = maxIntensityDb + min_intensity_dB

    # Small running median stabilizes isolated pitch errors without following
    # a FormantPath trajectory or introducing any target-frequency average.
    for g from 1 to numGrains
        if stabilize_F0
            tempF0# = zero#(2 * f0_median_half_window + 1)
            cnt = 0
            for off from -f0_median_half_window to f0_median_half_window
                gg = g + off
                if gg >= 1 and gg <= numGrains
                    if f0raw_'gg' > 0
                        cnt = cnt + 1
                        tempF0#[cnt] = f0raw_'gg'
                    endif
                endif
            endfor
            if cnt > 0
                # insertion sort of at most five numbers => O(N), not the old
                # long-file formant-median bottleneck.
                for a from 2 to cnt
                    key = tempF0#[a]
                    b = a - 1
                    while b >= 1 and tempF0#[b] > key
                        b1 = b + 1
                        tempF0#[b1] = tempF0#[b]
                        b = b - 1
                    endwhile
                    b1 = b + 1
                    tempF0#[b1] = key
                endfor
                f0_'g' = tempF0#[ceiling(cnt / 2)]
            else
                f0_'g' = 0
            endif
        else
            f0_'g' = f0raw_'g'
        endif
    endfor

    for fn from 1 to max_formants
        prevH_'fn' = undefined
    endfor

    for g from 1 to numGrains
        f0Here = f0_'g'
        active = 0
        if f0Here > 0
            if gate_weak_unvoiced
                if intDb_'g' > gateThresholdDb
                    active = 1
                else
                    gatedCount = gatedCount + 1
                endif
            else
                active = 1
            endif
        endif
        lockActive_'g' = active
        if active
            lockedCount = lockedCount + 1
        endif

        for fn from 1 to max_formants
            target_'g'_'fn' = undefined
            harm_'g'_'fn' = undefined
            if active and valid_'fn' = 1
                validMaxH = min(harmonic_safety_cap, floor((nyquist - 80) / f0Here))
                if validMaxH >= min_harmonic
                    harmFloat = formant_'fn' / f0Here
                    if snap_mode = 1
                        harm = round(harmFloat)
                    elsif snap_mode = 2
                        harm = ceiling(harmFloat)
                    elsif snap_mode = 3
                        harm = floor(harmFloat)
                    else
                        harm = 2 ^ round(log2(harmFloat))
                        while harm > validMaxH and harm >= 2
                            harm = harm / 2
                        endwhile
                        while harm < min_harmonic
                            harm = harm * 2
                        endwhile
                    endif

                    if snap_mode <> 4
                        harm = max(min_harmonic, min(harm, validMaxH))
                        if harmonic_hysteresis > 0 and prevH_'fn' <> undefined
                            if prevH_'fn' >= min_harmonic and prevH_'fn' <= validMaxH
                                if abs(harmFloat - prevH_'fn') < 0.5 + harmonic_hysteresis
                                    harm = prevH_'fn'
                                    hysteresisHolds = hysteresisHolds + 1
                                endif
                            endif
                        endif
                    else
                        # Octave hysteresis in ratio space. The target remains a
                        # power of two; it never gets clamped to 20/another non-octave.
                        if prevH_'fn' <> undefined and prevH_'fn' >= min_harmonic and prevH_'fn' <= validMaxH
                            lowBound = prevH_'fn' / sqrt(2) / (1 + harmonic_hysteresis)
                            highBound = prevH_'fn' * sqrt(2) * (1 + harmonic_hysteresis)
                            if harmFloat > lowBound and harmFloat < highBound
                                harm = prevH_'fn'
                                hysteresisHolds = hysteresisHolds + 1
                            endif
                        endif
                    endif

                    if harm >= min_harmonic and harm <= validMaxH
                        if prevH_'fn' <> undefined and harm <> prevH_'fn'
                            targetChanges = targetChanges + 1
                        endif
                        prevH_'fn' = harm
                        harm_'g'_'fn' = harm
                        # The defining invariant of v3.0: target is EXACTLY n * F0.
                        target_'g'_'fn' = harm * f0Here
                    endif
                endif
            endif
        endfor
    endfor

    appendInfoLine: "  Gate threshold: ", fixed$(gateThresholdDb, 1), " dB | locked grains ",
        ... lockedCount, " / ", numGrains
    appendInfoLine: "  Harmonic changes: ", targetChanges,
        ... " | hysteresis holds: ", hysteresisHolds
endif

# ============================================================
# [4/4] SPECTRAL ENVELOPE LOCKING
# ============================================================
appendInfoLine: "[4/4] Locking spectral-envelope regions..."
shapeClamp$ = fixed$(max_shape_dB, 4)

# ------------------------------------------------------------
# STABLE NOTE ENGINE: one FFT per channel
# ------------------------------------------------------------
procedure stableChannel: .inputSound
    selectObject: .inputSound
    .inDur = Get total duration
    .spec = To Spectrum: "yes"

    if stableTerms > 0
        selectObject: .spec
        if preserve_frame_energy
            .eIn = Get band energy: 0, 0
        endif
        Formula: "self * 10^(min(" + shapeClamp$ + ",max(-" + shapeClamp$ + "," +
            ... stableExpr$ + "))/20)"
        if preserve_frame_energy
            .eOut = Get band energy: 0, 0
            if .eIn > 0 and .eOut > 0
                .corr = sqrt(.eIn / .eOut)
                selectObject: .spec
                Formula: "self * " + string$(.corr)
            endif
        endif
    endif

    selectObject: .spec
    .backFull = To Sound
    removeObject: .spec
    selectObject: .backFull
    .out = Extract part: 0, .inDur, "rectangular", 1, "no"
    removeObject: .backFull
    selectObject: .out
endproc

# ------------------------------------------------------------
# DYNAMIC ENGINE: integer-sample Hann/Hann^2 WOLA
# ------------------------------------------------------------
if tracking_mode = 1
    Create Sound from formula: "hfl_ones", 1, 0, grainSec, sampleRate, "1"
    ones = selected("Sound")
    selectObject: ones
    synthWin = Extract part: 0, grainSec, "Hanning", 1, "no"
    winNs = Get number of samples
    synthWin$ = string$(synthWin)
    removeObject: ones

    if winNs <> grainSamples
        grainSamples = winNs
        grainSec = grainSamples / sampleRate
    endif

    Create Sound from formula: "hfl_weight", 1, 0, paddedDur, sampleRate, "0"
    weightBuf = selected("Sound")
    weightBuf$ = string$(weightBuf)

    for g from 1 to numGrains
        s1 = grainS1[g]
        s2 = s1 + grainSamples - 1
        if s2 > paddedSamples
            s2 = paddedSamples
        endif
        if s2 >= s1
            off = s1 - 1
            selectObject: weightBuf
            Formula (part): (s1 - 0.75) / sampleRate, (s2 - 0.25) / sampleRate, 1, 1,
                ... "self + object[" + synthWin$ + ",1,col-" + string$(off) +
                ... "] * object[" + synthWin$ + ",1,col-" + string$(off) + "]"
        endif
    endfor

    trimStart = padHeadSamples + 1
    trimEnd = padHeadSamples + totalSamples

    procedure dynamicChannel: .inputSound
        Create Sound from formula: "hfl_head", 1, 0, padHead, sampleRate, "0"
        .head = selected("Sound")
        selectObject: .inputSound
        .mid = Copy: "hfl_mid"
        Create Sound from formula: "hfl_tail", 1, 0, padTail, sampleRate, "0"
        .tail = selected("Sound")
        selectObject: .head
        plusObject: .mid
        plusObject: .tail
        Concatenate
        .padded = selected("Sound")
        removeObject: .head, .mid, .tail

        Create Sound from formula: "hfl_acc", 1, 0, paddedDur, sampleRate, "0"
        .acc = selected("Sound")

        for g from 1 to numGrains
            gIdx = g
            .s1 = grainS1[g]
            .s2 = .s1 + grainSamples - 1
            if .s2 > paddedSamples
                .s2 = paddedSamples
            endif
            .gs = (.s1 - 1) / sampleRate
            .ge = (.s1 - 1 + grainSamples) / sampleRate
            if .ge > paddedDur
                .ge = paddedDur
            endif

            selectObject: .padded
            .grain = Extract part: .gs, .ge, "Hanning", 1, "no"
            selectObject: .grain
            .spec = To Spectrum: "yes"

            .expr$ = ""
            .terms = 0
            if lockActive_'gIdx'
                for fn from 1 to max_formants
                    .target = target_'gIdx'_'fn'
                    if valid_'fn' = 1 and .target <> undefined and .target > 0
                        .amp = max_shape_dB * formant_weights#[fn] * lock_strength_norm
                        if .amp > 0.001 and abs(.target - formant_'fn') > 0.5
                            if .terms > 0
                                .expr$ = .expr$ + " + "
                            endif
                            .expr$ = .expr$ + fixed$(.amp, 5) + " * (exp(-0.5*((x-" +
                                ... fixed$(.target, 3) + ")/" + fixed$(width_'fn', 3) +
                                ... ")^2) - exp(-0.5*((x-" + fixed$(formant_'fn', 3) +
                                ... ")/" + fixed$(width_'fn', 3) + ")^2))"
                            .terms = .terms + 1
                        endif
                    endif
                endfor
            endif

            if .terms > 0
                selectObject: .spec
                if preserve_frame_energy
                    .eIn = Get band energy: 0, 0
                endif
                Formula: "self * 10^(min(" + shapeClamp$ + ",max(-" + shapeClamp$ + "," +
                    ... .expr$ + "))/20)"
                if preserve_frame_energy
                    .eOut = Get band energy: 0, 0
                    if .eIn > 0 and .eOut > 0
                        .corr = sqrt(.eIn / .eOut)
                        selectObject: .spec
                        Formula: "self * " + string$(.corr)
                    endif
                endif
            endif

            selectObject: .spec
            To Sound
            .back = selected("Sound")
            removeObject: .grain, .spec

            if .s2 >= .s1
                .off = .s1 - 1
                selectObject: .acc
                Formula (part): (.s1 - 0.75) / sampleRate, (.s2 - 0.25) / sampleRate, 1, 1,
                    ... "self + object[" + string$(.back) + ",1,col-" + string$(.off) +
                    ... "] * object[" + synthWin$ + ",1,col-" + string$(.off) + "]"
            endif
            removeObject: .back
        endfor

        removeObject: .padded
        selectObject: .acc
        Formula: "if object[" + weightBuf$ + ",1,col] > 0.000001 then self / object[" +
            ... weightBuf$ + ",1,col] else 0 endif"
        selectObject: .acc
        Extract part: (trimStart - 1) / sampleRate, trimEnd / sampleRate, "rectangular", 1, "no"
        .out = selected("Sound")
        removeObject: .acc
        selectObject: .out
    endproc
endif

# Process channels.
for ch from 1 to numChannels
    if numChannels = 1
        selectObject: workSound
        dryCh[ch] = Copy: "hfl_dry"
    else
        selectObject: workSound
        dryCh[ch] = Extract one channel: ch
    endif

    if tracking_mode = 2
        @stableChannel: dryCh[ch]
    else
        @dynamicChannel: dryCh[ch]
    endif
    wetCh[ch] = selected("Sound")

    if dry_wet_mix < 1
        selectObject: wetCh[ch]
        Formula: "self * " + string$(dry_wet_mix) + " + object[" + string$(dryCh[ch]) +
            ... ",1,col] * " + string$(1 - dry_wet_mix)
    endif
endfor

if numChannels = 1
    selectObject: wetCh[1]
    resynth = Copy: "hfl_out"
else
    selectObject: wetCh[1]
    outDur = Get total duration
    Create Sound from formula: "hfl_out", numChannels, 0, outDur, sampleRate, "0"
    resynth = selected("Sound")
    for ch from 1 to numChannels
        selectObject: resynth
        Formula (part): 0, outDur, ch, ch,
            ... "object[" + string$(wetCh[ch]) + ",1,col]"
    endfor
endif

for ch from 1 to numChannels
    removeObject: dryCh[ch], wetCh[ch]
endfor
if tracking_mode = 1
    removeObject: synthWin, weightBuf
endif

# ============================================================
# OUTPUT LEVEL
# ============================================================
selectObject: resynth
preLevelPeak = Get absolute extremum: 0, 0, "None"
preLevelRms = Get root-mean-square: 0, 0
levelGain = 1
levelAction$ = "natural level"

if output_level_mode = 2
    if preLevelPeak > ceiling_peak and preLevelPeak > 0
        Scale peak: ceiling_peak
        levelGain = ceiling_peak / preLevelPeak
        levelAction$ = "ceiling applied"
    else
        levelAction$ = "ceiling not needed"
    endif
elsif output_level_mode = 3
    if preLevelRms > 0 and inputRms > 0
        levelGain = inputRms / preLevelRms
        Formula: "self * " + string$(levelGain)
        levelAction$ = "matched input RMS"
        p = Get absolute extremum: 0, 0, "None"
        if p > ceiling_peak
            Scale peak: ceiling_peak
            levelAction$ = "RMS matched, then ceiling applied"
        endif
    endif
elsif output_level_mode = 4
    if preLevelPeak > 0
        Scale peak: ceiling_peak
        levelGain = ceiling_peak / preLevelPeak
        levelAction$ = "peak normalized"
    endif
endif

selectObject: resynth
outPeak = Get absolute extremum: 0, 0, "None"
outRms = Get root-mean-square: 0, 0

# ============================================================
# VISUALIZATION
# ============================================================
if draw_visualization
    appendInfoLine: "Drawing visualization..."
    Erase all
    pageHeight = 8.00
    Select outer viewport: 0, 8, 0, pageHeight

    vizAmp = max(inputPeak, outPeak)
    if vizAmp < 0.001
        vizAmp = 0.001
    endif
    vizAmp = vizAmp * 1.1
    drawTop = min(5000, nyquist - 80)

    if tracking_mode = 1
        trackStr$ = "Dynamic F0 / stable landmarks"
    else
        trackStr$ = "Stable note"
    endif

    suiteVizName$ = replace$(originalName$, "_", "\_ ", 0)
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Harmonic Formant Locking v3.1##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", suiteVizName$ + " | " + presetName$

    Select outer viewport: 0, 4, 0.6, 2.0
    Select inner viewport: 0.6, 3.75, 0.7, 1.95
    selectObject: workSound
    Colour: "{0.60,0.60,0.60}"
    Draw: 0, duration, -vizAmp, vizAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Input"

    Select outer viewport: 4, 8, 0.6, 2.0
    Select inner viewport: 4.55, 7.70, 0.7, 1.95
    selectObject: resynth
    Colour: "{0.30,0.70,0.50}"
    Draw: 0, duration, -vizAmp, vizAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Locked output"
    Text bottom: "yes", "Time (s)"

    # Harmonic target map.
    Select outer viewport: 0, 8, 2.1, 4.1
    Select inner viewport: 0.6, 7.7, 2.2, 4.05
    Axes: 0, duration, 0, drawTop
    Paint rectangle: "{0.97,0.97,0.97}", 0, duration, 0, drawTop

    # Static measured landmarks.
    Colour: "{0.65,0.65,0.65}"
    Dotted line
    for fn from 1 to min(3, max_formants)
        if valid_'fn' = 1 and formant_'fn' < drawTop
            Draw line: 0, formant_'fn', duration, formant_'fn'
        endif
    endfor
    Solid line

    # Pale harmonic grid from median F0 (reference only).
    Colour: "{0.88,0.88,0.93}"
    maxGridH = min(harmonic_safety_cap, floor(drawTop / stableF0))
    for h from min_harmonic to maxGridH
        hz = h * stableF0
        Draw line: 0, hz, duration, hz
    endfor

    trajCol$# = {"{0.30,0.60,0.90}", "{0.90,0.50,0.30}", "{0.30,0.80,0.50}"}
    if tracking_mode = 2
        for fn from 1 to 3
            if stableTarget_'fn' <> undefined and stableTarget_'fn' < drawTop
                Colour: trajCol$#[fn]
                Line width: 2
                Draw line: 0, stableTarget_'fn', duration, stableTarget_'fn'
                Line width: 1
            endif
        endfor
    else
        drawStep = max(1, ceiling(numGrains / 400))
        for fn from 1 to 3
            Colour: trajCol$#[fn]
            Line width: 2
            g = 1
            while g + drawStep <= numGrains
                g2 = g + drawStep
                y1 = target_'g'_'fn'
                y2 = target_'g2'_'fn'
                if y1 <> undefined and y2 <> undefined and y1 < drawTop and y2 < drawTop
                    Draw line: sourceTime_'g', y1, sourceTime_'g2', y2
                endif
                g = g + drawStep
            endwhile
            Line width: 1
        endfor
    endif

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Frequency (Hz)"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Grey dotted = measured landmarks | colour = exact harmonic targets | pale = median-F0 grid"

    Select outer viewport: 0, 8, 4.2, 5.15
    Select inner viewport: 0.6, 7.7, 4.25, 5.10
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94,0.94,0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.82, "half", "##Summary##"
    Font size: 6
    Colour: "{0.28,0.28,0.28}"
    if tracking_mode = 1
        engineStr$ = "dynamic Hann/Hann^2 WOLA, " + fixed$(1 / hopSec, 0) + " updates/s"
        targetStr$ = "changes " + string$(targetChanges) + " | hysteresis holds " + string$(hysteresisHolds)
    else
        engineStr$ = "static one-FFT/channel"
        targetStr$ = "fixed F0 " + fixed$(stableF0, 1) + " Hz"
    endif
    Text: 0.02, "left", 0.52, "half",
        ... "Engine: " + engineStr$ + " | " + string$(validFormants) + " formant landmarks" +
        ... " | Lock " + fixed$(lock_strength, 0) + "% | +/-" + fixed$(max_shape_dB, 0) + " dB"
    Text: 0.02, "left", 0.20, "half",
        ... targetStr$ + " | Energy preserved: " + string$(preserve_frame_energy) +
        ... " | Peak " + fixed$(inputPeak, 3) + " -> " + fixed$(outPeak, 3) + " | " + levelAction$
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
# Restore complete page for Picture export / clipboard.
Select outer viewport: 0, 8, 0, pageHeight
Font size: 10
Colour: "Black"
Line width: 1
Solid line
endif

# ============================================================
# FINISH
# ============================================================
selectObject: resynth
if originalXmin <> 0
    Shift times to: "start time", originalXmin
endif
Rename: originalName$ + "_HarmonicLock_" + presetName$
finalOutput = selected("Sound")
finalName$ = selected$("Sound")

removeObject: soundMono, pitch, intensity, workSound

appendInfoLine: ""
appendInfoLine: "=== Complete ==="
appendInfoLine: "Output: ", finalName$
appendInfoLine: "Method: broad spectral-envelope landmark locking; target invariant = n x F0"
appendInfoLine: "Channels: ", numChannels, " | Sample rate: ", sampleRate, " Hz"
appendInfoLine: "Peak: ", fixed$(inputPeak, 4), " -> ", fixed$(outPeak, 4), " | ", levelAction$
appendInfoLine: "RMS:  ", fixed$(inputRms, 5), " -> ", fixed$(outRms, 5)
if show_diagnostics
    appendInfoLine: "Diagnostics:"
    if tracking_mode = 1
        appendInfoLine: "  Locked grains: ", lockedCount, " / ", numGrains,
            ... " | gated: ", gatedCount
        appendInfoLine: "  Harmonic target changes: ", targetChanges,
            ... " | hysteresis holds: ", hysteresisHolds
        appendInfoLine: "  Every non-undefined target is exactly integer harmonic x current stabilized F0."
    else
        appendInfoLine: "  Stable-note engine: one FFT/channel, fixed F0 ", fixed$(stableF0, 2), " Hz."
    endif
endif
if output_level_mode <> 4 and outPeak > 1
    appendInfoLine: "WARNING: peak exceeds 1.0 and may clip when saved to integer PCM."
endif

selectObject: finalOutput
if play_result
    if outPeak > 1
        playCopy = Copy: "hfl_play_safe"
        Scale peak: 0.95
        Play
        removeObject: playCopy
    else
        Play
    endif
endif

selectObject: finalOutput