# ============================================================
# Praat AudioTools - Harmonic_Resonance.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Harmonic Resonance - creates harmonic series resonances through
#   bidirectional sample delay processing. Each iteration adds
#   resonances at harmonicBase^k intervals, creating rich harmonic
#   textures similar to a tuned comb filter bank.
#
# Changelog v0.4 (2026):
#   - HEADLINE: Character 1 is now a TRUE harmonic resonator bank.
#     v0.3's delays were totalSamples / harmonicBase^k: a geometric comb
#     progression tied to file duration, not a harmonic series tied to F0.
#     v0.4 detects a representative F0 (median voiced Pitch) or accepts a
#     fixed F0, then resonates F0, 2F0, 3F0 ... below Nyquist.
#   - The true-harmonic engine is a causal bank of second-order resonators.
#     It preserves all input channels and rings naturally into the silent tail.
#   - Both historical sounds remain available:
#       * geometric comb (v0.3 corrected feedforward)
#       * legacy feedback comb (v0.2)
#   - Added Fundamental mode, pitch bounds, Resonance Q, and Wet mix.
#   - Harmonic decay now controls relative harmonic weights in Character 1;
#     weights are energy-normalized so harmonic count changes colour more than
#     overall level.
#   - Output is forced to a zero-based time domain, so fade/tail logic works
#     correctly for input Sounds whose start time is not zero.
#   - Scale_peak is a safety ceiling in Character 1 (downward only), preserving
#     the requested dry/wet relationship.
#   - Tail and fadeout may be zero; silent results are normalization-safe.
#   - Spectrum displays stop at min(5 kHz, Nyquist).
#
# Changelog v0.3 (2026):
#   - Character menu (A/B and choose your default -- the
#     Basic_Mirror lesson, applied proactively this time):
#       * corrected: the backward tap reads the FROZEN
#         pre-iteration signal -- the "bidirectional sample
#         delay" the description states. Both taps feedforward.
#       * legacy (v0.2): the backward tap read already-processed
#         samples in the same Formula pass (Praat overwrites left
#         to right) -- a feedback comb through the output,
#         compounding across iterations. Kept VERBATIM as an
#         option; if that texture is this tool's identity, flip
#         the form default and say so.
#   - Viz spectra computed from mono copies (defensive: on
#     6.4.42 To Spectrum averages stereo natively -- probe-
#     verified, correcting an overbroad ledger entry -- but the
#     library targets 6.3+, where behavior has differed). The
#     ENGINE was always stereo-safe: single-index self[expr] is
#     row-aware (verified).
#   - FIX: the "Original" label was drawn on a stray full-width
#     viewport, landing across the title zone.
#   - GUARDS: Decay_factor clamped below 1 (values above flipped
#     polarity on late iterations); Fadeout clamped to the total
#     duration (longer values pushed the cosine past pi into
#     polarity inversion); the silent tail is created with the
#     source's channel count (>2-channel sources used to fail the
#     concatenation).
#
# Changelog v0.2:
#   - Modern syntax
#   - Added bounds checking
#   - Added visualization
# ============================================================

form Harmonic Resonance v0.4
    comment Select a Sound object first

    comment === Preset ===
    optionmenu Preset 1
        option Custom
        option Subtle Harmonics
        option Medium Harmonics
        option Heavy Harmonics
        option Extreme Harmonics

    optionmenu Character: 1
        option true harmonic resonators (pitch-derived)
        option geometric comb (v0.3 corrected)
        option legacy feedback comb (v0.2)

    comment === Resonance Parameters ===
    real Tail_duration_s 2.0
    natural Num_iterations 7
    real Resonance_Q 24
    real Resonance_mix 0.55

    comment === Fundamental for True Harmonic mode ===
    optionmenu Fundamental_mode: 1
        option Pitch-derived median
        option Fixed Hz
    positive Pitch_floor_Hz 50
    positive Pitch_ceiling_Hz 800
    positive Fixed_fundamental_Hz 110

    comment === Geometric Base (Characters 2-3 only) ===
    positive Harmonic_base_min 1.5
    positive Harmonic_base_max 4.0
    boolean Use_fixed_base 0
    positive Fixed_harmonic_base 2.5

    comment === Harmonic Decay ===
    real Decay_factor 0.72

    comment === Output ===
    real Scale_peak 0.95
    real Fadeout_duration_s 1.0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
presetName$ = "Custom"
if preset = 2
    # Subtle Harmonics
    tail_duration_s = 1.5
    num_iterations = 4
    resonance_Q = 18
    resonance_mix = 0.35
    harmonic_base_min = 1.3
    harmonic_base_max = 2.2
    use_fixed_base = 0
    fixed_harmonic_base = 1.8
    decay_factor = 0.62
    scale_peak = 0.96
    fadeout_duration_s = 0.8
    presetName$ = "SubtleHarmonics"
elsif preset = 3
    # Medium Harmonics
    tail_duration_s = 2.0
    num_iterations = 7
    resonance_Q = 24
    resonance_mix = 0.50
    harmonic_base_min = 1.5
    harmonic_base_max = 4.0
    use_fixed_base = 0
    fixed_harmonic_base = 2.5
    decay_factor = 0.72
    scale_peak = 0.95
    fadeout_duration_s = 1.0
    presetName$ = "MediumHarmonics"
elsif preset = 4
    # Heavy Harmonics
    tail_duration_s = 2.8
    num_iterations = 10
    resonance_Q = 30
    resonance_mix = 0.65
    harmonic_base_min = 2.0
    harmonic_base_max = 4.8
    use_fixed_base = 0
    fixed_harmonic_base = 3.5
    decay_factor = 0.78
    scale_peak = 0.93
    fadeout_duration_s = 1.4
    presetName$ = "HeavyHarmonics"
elsif preset = 5
    # Extreme Harmonics
    tail_duration_s = 4.0
    num_iterations = 15
    resonance_Q = 36
    resonance_mix = 0.75
    harmonic_base_min = 2.5
    harmonic_base_max = 6.0
    use_fixed_base = 0
    fixed_harmonic_base = 4.5
    decay_factor = 0.84
    scale_peak = 0.91
    fadeout_duration_s = 1.8
    presetName$ = "ExtremeHarmonics"
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

# === Validate ===
if tail_duration_s < 0
    exitScript: "Tail duration must be >= 0"
endif
if num_iterations < 1 or num_iterations > 64
    exitScript: "Number of harmonics/iterations must be 1-64"
endif
if resonance_Q <= 0
    exitScript: "Resonance Q must be > 0"
endif
if resonance_mix < 0 or resonance_mix > 1
    exitScript: "Resonance mix must be 0-1"
endif
if pitch_floor_Hz <= 0 or pitch_ceiling_Hz <= pitch_floor_Hz
    exitScript: "Pitch ceiling must be greater than pitch floor, both > 0"
endif
if fixed_fundamental_Hz <= 0
    exitScript: "Fixed fundamental must be > 0 Hz"
endif
if decay_factor < 0 or decay_factor >= 1
    exitScript: "Decay factor must be >= 0 and < 1"
endif
if scale_peak <= 0 or scale_peak > 1
    exitScript: "Scale peak must be > 0 and <= 1"
endif
if fadeout_duration_s < 0
    exitScript: "Fadeout duration must be >= 0"
endif
if harmonic_base_min <= 1 or harmonic_base_max < harmonic_base_min
    exitScript: "Geometric harmonic-base range must satisfy 1 < min <= max"
endif
if fixed_harmonic_base <= 1
    exitScript: "Fixed geometric harmonic base must be > 1"
endif

original = selected("Sound")
original_name$ = selected$("Sound")

selectObject: original
sourceStart = Get start time
sourceEnd = Get end time
sampling_rate = Get sampling frequency
channels = Get number of channels
originalDuration = Get total duration
nyquist = sampling_rate / 2
spectrumMaxHz = min(5000, nyquist)
originalRms = Get root-mean-square: 0, 0

# === Create zero-based source + silent tail ===
selectObject: original
sourceZero = Copy: "harmonic_source"
Shift times to: "start time", 0

if tail_duration_s > 0
    Create Sound from formula: "silent_tail", channels, 0, tail_duration_s, sampling_rate, "0"
    silentTail = selected("Sound")
    selectObject: sourceZero, silentTail
    Concatenate
    extended = selected("Sound")
    removeObject: sourceZero, silentTail
else
    selectObject: sourceZero
    extended = Copy: "extended"
    removeObject: sourceZero
endif
Rename: "extended"

selectObject: extended
totalDuration = Get total duration
totalSamples = Get number of samples

# === Info ===
writeInfoLine: "=== Harmonic Resonance v0.4 ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(originalDuration, 2), " s; ", channels, " ch)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""

# =====================================================================
# CHARACTER 1: TRUE HARMONIC RESONATOR BANK
# =====================================================================
if character = 1
    usedPitchFallback = 0

    if fundamental_mode = 1
        selectObject: original
        if channels > 1
            pitchAnalysisSound = Convert to mono
        else
            pitchAnalysisSound = Copy: "pitch_analysis"
        endif

        selectObject: pitchAnalysisSound
        To Pitch: 0, pitch_floor_Hz, pitch_ceiling_Hz
        pitchObj = selected("Pitch")
        fundamentalHz = Get quantile: 0, 0, 0.50, "Hertz"

        removeObject: pitchObj, pitchAnalysisSound

        if fundamentalHz = undefined or fundamentalHz <= 0
            fundamentalHz = fixed_fundamental_Hz
            usedPitchFallback = 1
        endif
        fundamentalSource$ = "median Pitch"
    else
        fundamentalHz = fixed_fundamental_Hz
        fundamentalSource$ = "fixed"
    endif

    activeHarmonics = min(num_iterations, floor(0.95 * nyquist / fundamentalHz))
    if activeHarmonics < 1
        removeObject: extended
        exitScript: "Fundamental is too high for this sampling rate"
    endif

    # Normalize the harmonic weight vector by energy.
    sumWeightSq = 0
    for k to activeHarmonics
        harmonicWeight = decay_factor ^ (k - 1)
        sumWeightSq = sumWeightSq + harmonicWeight ^ 2
    endfor
    weightNorm = sqrt(sumWeightSq)

    # Dry path.
    selectObject: extended
    result = Copy: "harmonic_work"
    Formula: "self * (1 - resonance_mix)"

    appendInfoLine: "Character: TRUE harmonic resonators"
    appendInfoLine: "Fundamental: ", fixed$(fundamentalHz, 2), " Hz (", fundamentalSource$, ")"
    if usedPitchFallback
        appendInfoLine: "  Note: no reliable voiced Pitch; used fixed fallback ", fixed$(fixed_fundamental_Hz, 2), " Hz"
    endif
    appendInfoLine: "Active harmonics: ", activeHarmonics, " / requested ", num_iterations
    appendInfoLine: "Resonance Q: ", fixed$(resonance_Q, 2), " | Wet mix: ", fixed$(resonance_mix, 2)
    appendInfoLine: ""
    appendInfoLine: "Harmonic | Frequency (Hz) | Bandwidth (Hz) | Weight"
    appendInfoLine: "---------|----------------|----------------|-------"

    for k to activeHarmonics
        centreHz = fundamentalHz * k
        bandwidthHz = max(2, centreHz / resonance_Q)

        # Causal second-order all-pole resonator:
        # y[n] = x[n] - p*y[n-1] - q*y[n-2]
        poleRadius = exp(-pi * bandwidthHz / sampling_rate)
        pCoeff = -2 * poleRadius * cos(2 * pi * centreHz / sampling_rate)
        qCoeff = poleRadius ^ 2

        selectObject: extended
        resonanceLayer = Copy: "resonance_" + string$(k)

        pStr$ = fixed$(pCoeff, 15)
        qStr$ = fixed$(qCoeff, 15)
        extStr$ = string$(extended)

        selectObject: resonanceLayer
        # Out-of-range previous-sample references evaluate to zero.
        Formula: "object[" + extStr$ + ", row, col] - (" + pStr$ + ") * self[row, col - 1] - (" + qStr$ + ") * self[row, col - 2]"

        layerRms = Get root-mean-square: 0, 0
        harmonicWeight = decay_factor ^ (k - 1)
        normalizedWeight = harmonicWeight / weightNorm

        if layerRms > 0 and originalRms > 0
            layerScale = resonance_mix * normalizedWeight * originalRms / layerRms
            Formula: "self * layerScale"

            layerStr$ = string$(resonanceLayer)
            selectObject: result
            Formula: "self + object[" + layerStr$ + ", row, col]"
        endif

        appendInfoLine: "   ", k, "     |   ", fixed$(centreHz, 2), "      |    ", fixed$(bandwidthHz, 2), "      | ", fixed$(normalizedWeight, 4)
        removeObject: resonanceLayer
    endfor

# =====================================================================
# CHARACTERS 2-3: PRESERVED GEOMETRIC COMB TEXTURES
# =====================================================================
else
    if use_fixed_base
        harmonicBase = fixed_harmonic_base
    else
        harmonicBase = randomUniform(harmonic_base_min, harmonic_base_max)
    endif

    selectObject: extended
    result = Copy: "harmonic_work"

    if character = 2
        appendInfoLine: "Character: geometric comb (v0.3 corrected feedforward)"
    else
        appendInfoLine: "Character: legacy feedback comb (v0.2)"
    endif
    appendInfoLine: "Geometric base: ", fixed$(harmonicBase, 3)
    appendInfoLine: "Iterations: ", num_iterations
    appendInfoLine: "Historical decay parameter: ", decay_factor
    appendInfoLine: ""
    appendInfoLine: "Iter | Shift Factor | Delay (samples) | Delay (ms)"
    appendInfoLine: "-----|--------------|-----------------|----------"

    for k from 1 to num_iterations
        shiftFactor = harmonicBase ^ k
        delaySamples = round(totalSamples / shiftFactor)
        halfDelay = round(delaySamples / 2)

        if delaySamples >= 1
            delayMs = delaySamples / sampling_rate * 1000
            appendInfoLine: "  ", k, "  |     ", fixed$(shiftFactor, 2), "     |      ", delaySamples, "      |  ", fixed$(delayMs, 1)

            iterWeight = 1 / k
            ampDecay = 1 - k / num_iterations * decay_factor

            selectObject: result
            if character = 2
                frozenIt = Copy: "frozen_iter"
                fzStr$ = string$(frozenIt)
                selectObject: result
                Formula: "if col + delaySamples <= ncol and col - halfDelay >= 1 then (object[" + fzStr$ + ", row, col + delaySamples] - object[" + fzStr$ + ", row, col - halfDelay]) * iterWeight else self * 0.5 fi"
                removeObject: frozenIt
            else
                Formula: "if col + delaySamples <= ncol and col - halfDelay >= 1 then (self[row, col + delaySamples] - self[row, col - halfDelay]) * iterWeight else self * 0.5 fi"
            endif

            # Historical v0.2/v0.3 behaviour retained verbatim in spirit.
            Formula: "self * ampDecay"
        endif
    endfor

    fundamentalHz = undefined
    activeHarmonics = 0
endif

# === Peak safety ===
selectObject: result
resultPeak = Get absolute extremum: 0, 0, "Sinc70"
if resultPeak > 0
    if character = 1
        if resultPeak > scale_peak
            Formula: "self * scale_peak / resultPeak"
        endif
    else
        Scale peak: scale_peak
    endif
endif

# === Apply Fadeout ===
selectObject: result
totalDuration = Get total duration
effectiveFadeout = min(fadeout_duration_s, totalDuration)
if effectiveFadeout > 0
    fadeStart = totalDuration - effectiveFadeout
    Formula: "if x > fadeStart then self * (0.5 + 0.5 * cos(pi * (x - fadeStart) / effectiveFadeout)) else self fi"
endif

if character = 1
    Rename: original_name$ + "_harmonicRes_" + presetName$
elsif character = 2
    Rename: original_name$ + "_geoComb_" + presetName$
else
    Rename: original_name$ + "_legacyComb_" + presetName$
endif

# === Cleanup ===
removeObject: extended

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 1, 8, 0.2, 0.6
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Harmonic Resonance: " + original_name$
    
    # Original waveform
    Select outer viewport: 0, 8, 0.8, 2.2
    Select inner viewport: 0.6, 7.6, 0.9, 2.1
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 2.3, 3.7
    Select inner viewport: 0.6, 7.6, 2.4, 3.6
    selectObject: result
    Colour: "{0.2, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Harmonic"
    Text bottom: "yes", "Time (s)"
    
    # Original spectrum
    Select outer viewport: 0, 4, 3.9, 5.5
    Select inner viewport: 0.6, 3.8, 4.1, 5.4
    selectObject: original
    if channels > 1
        vizOrigMono = Convert to mono
    else
        vizOrigMono = Copy: "vizOrig"
    endif
    To Spectrum: "yes"
    origSpec = selected("Spectrum")
    removeObject: vizOrigMono
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, spectrumMaxHz, 0, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "dB"
    Text bottom: "yes", "Original (Hz)"
    removeObject: origSpec
    
    # Result spectrum
    Select outer viewport: 4, 8, 3.9, 5.5
    Select inner viewport: 4.4, 7.6, 4.1, 5.4
    selectObject: result
    if channels > 1
        vizResMono = Convert to mono
    else
        vizResMono = Copy: "vizRes"
    endif
    To Spectrum: "yes"
    resSpec = selected("Spectrum")
    removeObject: vizResMono
    Colour: "{0.3, 0.6, 0.8}"
    Draw: 0, spectrumMaxHz, 0, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "dB"
    Text bottom: "yes", "Harmonic (Hz)"
    removeObject: resSpec
    
    # Legend
    Select outer viewport: 2, 8, 5.6, 5.9
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Axes: 0, 1, 0, 1
    if character = 1
        Text: 0.5, "centre", 0.5, "half", "F0: " + fixed$(fundamentalHz, 1) + " Hz | Harmonics: " + string$(activeHarmonics) + " | Q: " + fixed$(resonance_Q, 1) + " | Wet: " + fixed$(resonance_mix, 2)
    else
        Text: 0.5, "centre", 0.5, "half", "Geometric base: " + fixed$(harmonicBase, 2) + " | Iterations: " + string$(num_iterations) + " | Decay: " + fixed$(decay_factor, 2)
    endif
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
selectObject: result
finalDuration = Get total duration

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Original: ", fixed$(originalDuration, 2), " s"
appendInfoLine: "Result: ", fixed$(finalDuration, 2), " s"
appendInfoLine: "Created: ", selected$("Sound")

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result