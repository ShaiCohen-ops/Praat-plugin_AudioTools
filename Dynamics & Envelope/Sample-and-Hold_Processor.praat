# ============================================================
# Praat AudioTools - Sample-and-Hold_Processor.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Sample-and-hold processor with multiple control modes
#   including binary gating, intensity-based, AM, pitch-gated,
#   custom patterns, and spectral centroid gating.
#
# Changelog v1.0:
#   - Added presets, smoothing, play, improved info output
#
# Changelog v1.1:
#   - Smoothing_ms now controls the smoothing: the gate is applied as a
#     gain envelope that is low-passed by Smoothing_ms.
#   - Fixed the info header (was erased by repeated writeInfoLine calls).
#   - Fixed visualization title + parameter centring (0..1 axis).
#
# Changelog v1.2:
#   - Absolute time domain. The gain envelope, all analysis extractions
#     and every plot now use the Sound's own start/end time. Previously
#     everything assumed xmin = 0, so a Sound in [5,6] was multiplied by
#     an envelope defined in [0,1] and the whole output came out silent.
#   - Peak normalization is now optional and OFF by default. It was
#     unconditional, which divided Mute_level and AM depth straight back
#     out (a file muted to 0.1 came back at 0.95).
#   - Smoothing_ms is honest about what it does. New Smoothing_mode:
#     "Crossfade ramp" gives a raised-cosine transition of exactly
#     Smoothing_ms centred on each interval boundary; "Low-pass (legacy)"
#     keeps the v1.1 zero-phase filter, now labelled a time constant.
#   - Pitch Gate uses a pitch floor derived from the file length
#     (Praat needs minPitch >= 3/duration), instead of failing on any
#     file shorter than 40 ms.
#   - Intensity auto-threshold: true median (even/odd) and >= comparison,
#     so a constant-level input is no longer gated 100% shut.
#   - Parameter validation with explicit ranges. Pattern tokens get
#     numeric validation only: out-of-range values are accepted and act
#     as binary extremes against Gate_threshold.
#   - The Gate panel now draws the gain envelope that was actually
#     applied, including Mute_level and smoothing.
#   - Spectral centroid measured through a Hann window (was rectangular,
#     whose leakage biases the centroid upward on short intervals), and
#     the segment is folded to mono first - To Spectrum rejects stereo,
#     so Centroid mode crashed on any multichannel input.
#
# Changelog v1.3:
#   - Centroid mode no longer downmixes to mono. An arithmetic downmix
#     cancels anti-phase channels, so L = s / R = -s measured as silence
#     and gated shut while the spectrally identical L = R = s passed
#     everywhere. Each channel is now transformed separately and the
#     per-bin powers are summed before the centre of gravity is taken.
#   - Crossfade ramps are the requested length wherever there is enough
#     audio; boundaries closer than half the smoothing time to either end
#     of the file get a shortened ramp, and the count is now reported.
#   - The drawn envelope is multiplied by the normalization constant, so
#     the "Applied gain" panel is the total gain applied, not the
#     pre-normalization envelope.
#   - Pitch Gate reports the floor forced by the file length and what
#     that floor makes undetectable; the too-short message no longer
#     implies that 5.3 ms is generally usable.
# ============================================================

form Sample-and-Hold Processor v1.3
    optionmenu Preset 1
        option Custom
        option Rhythmic Chop (binary)
        option Dynamics Gate (intensity)
        option Tremolo (AM slow)
        option Flutter (AM fast)
        option Voiced Only (pitch-gate)
        option Bright Only (centroid)
        option Morse Code (pattern)
    optionmenu Control_mode 1
        option Binary (alternating)
        option Intensity-based
        option Amplitude Modulation
        option Pitch-gated
        option Custom Pattern
        option Spectral Centroid Gate
    comment === Timing ===
    positive Sample_period_s 0.02
    real Gate_threshold 0.5
    comment (0 to 1)
    comment === Mode Parameters ===
    real Intensity_threshold_dB 0
    comment (0 = auto from median)
    real AM_frequency_Hz 4
    real AM_depth 1.0
    comment (0 to 1; AM freq must be <= 1 / (2 x sample period))
    real Pitch_threshold_Hz 100
    real Centroid_threshold_Hz 1000
    sentence Pattern 1 0 1 1 0 1 0 1
    comment === Gate Character ===
    real Mute_level 0.0
    comment (0 to 1)
    optionmenu Smoothing_mode 1
        option Crossfade ramp (exact length)
        option Low-pass (legacy time constant)
    positive Smoothing_ms 2
    comment (transition length, capped at one sample period)
    comment === Output ===
    boolean Peak_normalize_output 0
    boolean Visualize 1
    boolean Play 1
endform

# === INPUT VALIDATION ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
sound_name$ = selected$("Sound")

selectObject: sound
dur = Get total duration
sr = Get sampling frequency
nChannels = Get number of channels

# Absolute time domain of the source. Everything downstream - analysis
# extraction, the gain envelope, the plots - is expressed in these
# coordinates, not in 0..duration.
sourceStart = Get start time
sourceEnd = Get end time

# === USE WORKING VARIABLES (so presets can override) ===
workingMode = control_mode
workingPeriod = sample_period_s
workingIntensityThresh = intensity_threshold_dB
workingAMFreq = aM_frequency_Hz
workingAMDepth = aM_depth
workingPitchThresh = pitch_threshold_Hz
workingCentroidThresh = centroid_threshold_Hz
workingPattern$ = pattern$

# === APPLY PRESETS ===
if preset = 2
    # Rhythmic Chop
    workingMode = 1
    workingPeriod = 0.05
    presetName$ = "RhythmicChop"
elsif preset = 3
    # Dynamics Gate
    workingMode = 2
    workingIntensityThresh = 0
    workingPeriod = 0.02
    presetName$ = "DynamicsGate"
elsif preset = 4
    # Tremolo (slow AM)
    workingMode = 3
    workingAMFreq = 4
    workingAMDepth = 0.8
    workingPeriod = 0.01
    presetName$ = "Tremolo"
elsif preset = 5
    # Flutter (fast AM)
    workingMode = 3
    workingAMFreq = 12
    workingAMDepth = 1.0
    workingPeriod = 0.005
    presetName$ = "Flutter"
elsif preset = 6
    # Voiced Only
    workingMode = 4
    workingPitchThresh = 80
    workingPeriod = 0.02
    presetName$ = "VoicedOnly"
elsif preset = 7
    # Bright Only
    workingMode = 6
    workingCentroidThresh = 2000
    workingPeriod = 0.03
    presetName$ = "BrightOnly"
elsif preset = 8
    # Morse Code
    workingMode = 5
    workingPattern$ = "1 1 1 0 1 0 1 0 0"
    workingPeriod = 0.1
    presetName$ = "MorseCode"
else
    presetName$ = "Custom"
endif

# === PARAMETER VALIDATION (after presets, so preset values are checked too) ===
maxIntervals = 200000

if gate_threshold < 0 or gate_threshold > 1
    exitScript: "Gate_threshold must be between 0 and 1 (got " + fixed$(gate_threshold, 3) + ")."
endif

if mute_level < 0 or mute_level > 1
    exitScript: "Mute_level must be between 0 and 1 (got " + fixed$(mute_level, 3) + "). " +
    ... "Negative values invert polarity; values above 1 amplify muted intervals."
endif

if workingPeriod < 1 / sr
    exitScript: "Sample_period_s must be at least one audio sample (" +
    ... fixed$(1000 / sr, 4) + " ms at " + fixed$(sr, 0) + " Hz)."
endif

periodTooLong = 0
if workingPeriod > dur
    periodTooLong = 1
endif

numIntervals = ceiling(dur / workingPeriod)

if numIntervals > maxIntervals
    exitScript: "This period gives " + string$(numIntervals) + " intervals; the limit is " +
    ... string$(maxIntervals) + ". Use a longer Sample_period_s."
endif

if workingMode = 3
    if workingAMDepth < 0 or workingAMDepth > 1
        exitScript: "AM_depth must be between 0 and 1 (got " + fixed$(workingAMDepth, 3) + ")."
    endif
    amNyquist = 1 / (2 * workingPeriod)
    if workingAMFreq < 0
        exitScript: "AM_frequency_Hz must not be negative."
    endif
    if workingAMFreq > amNyquist
        exitScript: "AM_frequency_Hz (" + fixed$(workingAMFreq, 2) + " Hz) exceeds the sample-and-hold " +
        ... "Nyquist limit of " + fixed$(amNyquist, 2) + " Hz for a " + fixed$(workingPeriod * 1000, 2) +
        ... " ms period. Lower the frequency or shorten the period."
    endif
endif

# The crossfade cannot be longer than the interval it sits between, or
# successive transitions would overwrite each other.
maxSmooth_ms = workingPeriod * 1000
smoothClamped = 0
workingSmooth_ms = smoothing_ms
if workingSmooth_ms > maxSmooth_ms
    workingSmooth_ms = maxSmooth_ms
    smoothClamped = 1
endif

# === GET MODE NAME ===
if workingMode = 1
    modeName$ = "Binary"
elsif workingMode = 2
    modeName$ = "Intensity"
elsif workingMode = 3
    modeName$ = "AM"
elsif workingMode = 4
    modeName$ = "Pitch-Gate"
elsif workingMode = 5
    modeName$ = "Pattern"
else
    modeName$ = "Centroid"
endif

if smoothing_mode = 1
    smoothName$ = "crossfade ramp"
else
    smoothName$ = "low-pass time constant"
endif

# === INFO HEADER ===
clearinfo
appendInfoLine: "=============================================="
appendInfoLine: "  SAMPLE-AND-HOLD PROCESSOR v1.3"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Input: ", sound_name$, " (", fixed$(dur, 2), "s)"
appendInfoLine: "Time domain: ", fixed$(sourceStart, 4), " to ", fixed$(sourceEnd, 4), " s"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Mode: ", modeName$
appendInfoLine: "Sample period: ", fixed$(workingPeriod * 1000, 1), " ms (", numIntervals, " intervals)"
if periodTooLong
    appendInfoLine: "  NOTE: the period is longer than the Sound, so there is a single hold"
    appendInfoLine: "        interval and no sample-and-hold motion."
endif
appendInfoLine: "Smoothing: ", fixed$(workingSmooth_ms, 2), " ms (", smoothName$, ")"
if smoothClamped
    appendInfoLine: "  NOTE: clamped from ", fixed$(smoothing_ms, 2), " ms to one sample period"
endif
appendInfoLine: ""

# === PARSE CUSTOM PATTERN ===
patternLength = 0
if workingMode = 5
    workingPattern$ = replace_regex$(workingPattern$, "^[ \t]+|[ \t]+$", "", 0)
    if length(workingPattern$) = 0
        exitScript: "Custom pattern is empty."
    endif
    @parsePattern: workingPattern$ + " "
    patternLength = parsePattern.count
    if patternLength = 0
        exitScript: "No valid pattern values found."
    endif
    appendInfoLine: "Pattern length: ", patternLength, " steps"
    patOutOfRange = 0
    for k from 1 to patternLength
        if patVal[k] < 0 or patVal[k] > 1
            patOutOfRange = 1
        endif
    endfor
    if patOutOfRange
        appendInfoLine: "  NOTE: some pattern values are outside 0..1; they are still compared"
        appendInfoLine: "        against Gate_threshold, so they act as fully open or fully muted."
    endif
endif

# === PRE-ANALYSIS ===

# Intensity: auto-threshold via median
if workingMode = 2 and workingIntensityThresh = 0
    appendInfoLine: "Calculating auto-threshold..."

    selectObject: sound
    Create TableOfReal: "int_vals", numIntervals, 1
    table_id = selected("TableOfReal")

    for i from 1 to numIntervals
        t_start = sourceStart + (i - 1) * workingPeriod
        t_end = min(t_start + workingPeriod, sourceEnd)
        selectObject: sound
        Extract part: t_start, t_end, "rectangular", 1, "no"
        temp_seg = selected("Sound")
        int_val = Get intensity (dB)
        if int_val = undefined
            int_val = -100
        endif
        selectObject: table_id
        Set value: i, 1, int_val
        removeObject: temp_seg
    endfor

    selectObject: table_id
    Sort by column: 1, 0
    # True median: middle value for odd counts, mean of the two middle
    # values for even counts. (v1.1 used floor(n/2), which picks the
    # first of three values and never averages.)
    if numIntervals mod 2 = 1
        workingIntensityThresh = Get value: (numIntervals + 1) / 2, 1
    else
        medLow = Get value: numIntervals / 2, 1
        medHigh = Get value: numIntervals / 2 + 1, 1
        workingIntensityThresh = (medLow + medHigh) / 2
    endif
    intMinVal = Get value: 1, 1
    intMaxVal = Get value: numIntervals, 1

    appendInfoLine: "  Auto threshold: ", fixed$(workingIntensityThresh, 1), " dB (median)"
    if intMaxVal - intMinVal < 0.01
        appendInfoLine: "  NOTE: input has no intensity variation (range ",
        ... fixed$(intMaxVal - intMinVal, 3), " dB)."
        appendInfoLine: "        With a median threshold every interval sits at the threshold,"
        appendInfoLine: "        so all intervals pass (comparison is >=)."
    endif
    removeObject: table_id
endif

# Pitch: analyze full sound once.
# Praat requires minimum pitch >= 3 / duration for the autocorrelation
# window to fit. v1.1 hard-coded 75 Hz, which fails on anything under 40 ms.
if workingMode = 4
    appendInfoLine: "Analyzing pitch..."
    pitchCeiling = 600
    pitchFloor = 75
    requiredFloor = 3.2 / dur
    if requiredFloor > pitchFloor
        pitchFloor = requiredFloor
    endif
    if pitchFloor >= pitchCeiling
        exitScript: "Pitch Gate needs a longer Sound. At " + fixed$(dur * 1000, 1) +
        ... " ms the pitch floor would have to be " + fixed$(pitchFloor, 0) +
        ... " Hz, above the ceiling of " + fixed$(pitchCeiling, 0) +
        ... " Hz. The absolute minimum is about " + fixed$(3200 / pitchCeiling, 1) +
        ... " ms, and that only detects pitches near " + fixed$(pitchCeiling, 0) +
        ... " Hz; lower-pitched material needs a proportionally longer Sound (about " +
        ... fixed$(3200 / 200, 1) + " ms to reach 200 Hz, " + fixed$(3200 / 100, 1) + " ms to reach 100 Hz)."
    endif
    selectObject: sound
    To Pitch: 0.0, pitchFloor, pitchCeiling
    pitch_object = selected("Pitch")
    appendInfoLine: "  Pitch floor: ", fixed$(pitchFloor, 1), " Hz (ceiling ", fixed$(pitchCeiling, 0), " Hz)"
    if pitchFloor > 75
        appendInfoLine: "  NOTE: the file length forces this floor (Praat needs floor >= 3/duration)."
        appendInfoLine: "        Anything below ", fixed$(pitchFloor, 0), " Hz cannot be detected here and"
        appendInfoLine: "        will be gated shut. Use a longer Sound for low-pitched material."
    endif
    appendInfoLine: "  Threshold: ", workingPitchThresh, " Hz"
    if workingPitchThresh < pitchFloor
        appendInfoLine: "  NOTE: the threshold is below the analysis floor, so every voiced"
        appendInfoLine: "        frame passes and the gate is effectively voiced/unvoiced."
    endif
endif

# === CREATE OUTPUT ===
selectObject: sound
result = Copy: sound_name$ + "_SH"
selectObject: sound
inPeak = Get absolute extremum: 0, 0, "None"

# === STORAGE FOR VISUALIZATION ===
for i from 0 to numIntervals - 1
    controlVal[i] = 0
endfor

passCount = 0
muteCount = 0
gainMin = 1e9
gainMax = -1e9

# === MAIN PROCESSING LOOP ===
appendInfoLine: ""
appendInfoLine: "Processing ", numIntervals, " intervals..."

for i from 0 to numIntervals - 1
    relStart = i * workingPeriod
    t_start = sourceStart + relStart
    t_end = min(t_start + workingPeriod, sourceEnd)
    t_mid = (t_start + t_end) / 2

    selectObject: sound

    if workingMode = 1
        # Binary alternating
        if i mod 2 = 0
            ctrl = 1
        else
            ctrl = 0
        endif

    elsif workingMode = 2
        # Intensity-based. Rectangular on purpose: this is an energy
        # measurement of the interval, not a spectral estimate.
        Extract part: t_start, t_end, "rectangular", 1, "no"
        temp_seg = selected("Sound")
        int_val = Get intensity (dB)
        if int_val = undefined
            int_val = -100
        endif
        if int_val >= workingIntensityThresh
            ctrl = 1
        else
            ctrl = 0
        endif
        removeObject: temp_seg

    elsif workingMode = 3
        # Amplitude modulation. Phase runs from the start of the Sound,
        # not from absolute time zero, so the LFO always starts at the
        # same point regardless of the Sound's xmin.
        phase = 2 * pi * workingAMFreq * relStart
        sineVal = (sin(phase) + 1) / 2
        ctrl = 1 - (workingAMDepth * (1 - sineVal))

    elsif workingMode = 4
        # Pitch-gated
        selectObject: pitch_object
        pitchVal = Get value at time: t_mid, "Hertz", "linear"
        if pitchVal <> undefined and pitchVal > workingPitchThresh
            ctrl = 1
        else
            ctrl = 0
        endif

    elsif workingMode = 5
        # Custom pattern
        patIdx = (i mod patternLength) + 1
        ctrl = patVal[patIdx]

    elsif workingMode = 6
        # Spectral centroid. Hann window: a rectangular frame leaks
        # energy across the whole band and biases the centroid upward,
        # most severely on short intervals.
        Extract part: t_start, t_end, "Hanning", 1, "no"
        temp_seg = selected("Sound")
        if nChannels = 1
            To Spectrum: "yes"
            spectrum = selected("Spectrum")
        else
            # Power-linked, not a mono downmix: an arithmetic downmix
            # cancels anti-phase channels, so L = s / R = -s measured as
            # silence and the gate shut on material that is spectrally
            # identical to L = R = s. Each channel is transformed on its
            # own and the per-bin POWERS are summed. The imaginary part
            # of the accumulator is zeroed - the object is a power
            # container from here on, valid for centre of gravity at
            # power 2, not a reconstructable spectrum.
            selectObject: temp_seg
            Extract one channel: 1
            ch_seg = selected("Sound")
            To Spectrum: "yes"
            spectrum = selected("Spectrum")
            removeObject: ch_seg
            for ch from 2 to nChannels
                selectObject: temp_seg
                Extract one channel: ch
                ch_seg = selected("Sound")
                To Spectrum: "yes"
                ch_spec = selected("Spectrum")
                ch_spec_str$ = string$(ch_spec)
                selectObject: spectrum
                Formula: "if row = 1 then sqrt(self[1,col]^2 + self[2,col]^2 + object(" +
                ... ch_spec_str$ + ",1,col)^2 + object(" + ch_spec_str$ + ",2,col)^2) else self fi"
                Formula: "if row = 2 then 0 else self fi"
                removeObject: ch_spec, ch_seg
            endfor
        endif
        centroid = Get centre of gravity: 2
        if centroid <> undefined and centroid > workingCentroidThresh
            ctrl = 1
        else
            ctrl = 0
        endif
        removeObject: spectrum, temp_seg
    endif

    controlVal[i] = ctrl

    # Statistics (skip for continuous AM)
    if workingMode <> 3
        if ctrl >= gate_threshold
            passCount = passCount + 1
        else
            muteCount = muteCount + 1
        endif
    endif

    # Determine amplitude multiplier (stored; applied after the loop via a
    # smoothed gain envelope so transitions can be crossfaded)
    if workingMode = 3
        ampMult = ctrl
    else
        if ctrl >= gate_threshold
            ampMult = 1
        else
            ampMult = mute_level
        endif
    endif
    gainArr[i] = ampMult
    if ampMult < gainMin
        gainMin = ampMult
    endif
    if ampMult > gainMax
        gainMax = ampMult
    endif
endfor

# === BUILD GAIN ENVELOPE, SMOOTH, AND APPLY ===
# One held value per interval at the audio rate, over the SOURCE's own
# time domain so that object(gainEnv, x) is read inside its definition.
Create Sound from formula: "gain_env", 1, sourceStart, sourceEnd, sr, "0"
gainEnv = selected("Sound")
for i from 0 to numIntervals - 1
    t_start = sourceStart + i * workingPeriod
    t_end = min(t_start + workingPeriod, sourceEnd)
    selectObject: gainEnv
    Formula (part): t_start, t_end, 1, 1, string$(gainArr[i])
endfor

if smoothing_mode = 1
    # Crossfade ramp: a raised cosine of the requested length wherever
    # there is enough audio, centred on each interval boundary. The
    # transition therefore begins half the smoothing time before the
    # boundary and ends half after; a boundary closer than half the
    # smoothing time to either end of the file gets a shortened ramp.
    if workingSmooth_ms > 0 and numIntervals > 1
        appendInfoLine: "Crossfading gate transitions (", fixed$(workingSmooth_ms, 2), " ms)..."
        halfRamp = (workingSmooth_ms / 1000) / 2
        rampCount = 0
        rampShort = 0
        selectObject: gainEnv
        for i from 1 to numIntervals - 1
            g0 = gainArr[i - 1]
            g1 = gainArr[i]
            if g0 <> g1
                tb = sourceStart + i * workingPeriod
                rs = max(tb - halfRamp, sourceStart)
                re = min(tb + halfRamp, sourceEnd)
                if re - rs < 2 * halfRamp - 1e-12
                    rampShort = rampShort + 1
                endif
                if re - rs > 0
                    Formula (part): rs, re, 1, 1,
                    ... fixed$(g0, 12) + " + (" + fixed$(g1 - g0, 12) + ") * (0.5 - 0.5 * cos(pi * (x - " +
                    ... fixed$(rs, 9) + ") / " + fixed$(re - rs, 9) + "))"
                    rampCount = rampCount + 1
                endif
            endif
        endfor
        appendInfoLine: "  ", rampCount, " transitions ramped"
        if rampShort > 0
            appendInfoLine: "  ", rampShort, " shortened at the file edges (not enough audio for the"
            appendInfoLine: "     full length; the ramp is truncated to fit inside the Sound)."
        endif
    endif
else
    # Legacy v1.1 behaviour: zero-phase low-pass of the envelope. This is
    # a time CONSTANT, not a ramp length - the audible transition is
    # roughly 3x the requested value and, because the filter is
    # zero-phase, it starts before the boundary.
    smoothCutoff = 1000 / (2 * pi * workingSmooth_ms)
    if workingSmooth_ms > 0 and smoothCutoff < sr / 2
        appendInfoLine: "Smoothing gate transitions (time constant ", fixed$(workingSmooth_ms, 2), " ms)..."
        appendInfoLine: "  NOTE: zero-phase filter - the transition is wider than the requested"
        appendInfoLine: "        value and is centred, not started, on each boundary."
        selectObject: gainEnv
        smoothed = Filter (pass Hann band): 0, smoothCutoff, smoothCutoff * 0.5
        removeObject: gainEnv
        gainEnv = smoothed
        # clamp away filter overshoot, back into the real gain range
        selectObject: gainEnv
        Formula: "min(max(self, " + string$(gainMin) + "), " + string$(gainMax) + ")"
    endif
endif

# Keep a copy of the envelope that is actually applied, for the plot.
selectObject: gainEnv
gainEnvDraw = Copy: "applied_gain"

gainEnv_str$ = string$(gainEnv)
selectObject: result
Formula: "self * object(" + gainEnv_str$ + ", x)"
removeObject: gainEnv

# === CLEANUP PRE-ANALYSIS ===
if workingMode = 4
    removeObject: pitch_object
endif

# === NORMALIZE (optional) ===
selectObject: result
prePeak = Get absolute extremum: 0, 0, "None"
normGain = 1
if peak_normalize_output
    if prePeak > 0
        Scale peak: 0.95
        normGain = 0.95 / prePeak
    endif
endif
selectObject: result
outPeak = Get absolute extremum: 0, 0, "None"

# The drawn envelope was copied before normalization. Fold the constant
# in so the panel titled "Applied gain" really is the total gain applied.
if normGain <> 1
    selectObject: gainEnvDraw
    Formula: "self * " + fixed$(normGain, 12)
endif

# === STATISTICS ===
if workingMode <> 3
    appendInfoLine: ""
    appendInfoLine: "Results:"
    appendInfoLine: "  Passed: ", passCount, " (", fixed$(100 * passCount / numIntervals, 1), "%)"
    appendInfoLine: "  Muted: ", muteCount, " (", fixed$(100 * muteCount / numIntervals, 1), "%)"

    if passCount = numIntervals
        appendInfoLine: "  WARNING: All segments passed"
    elsif muteCount = numIntervals
        appendInfoLine: "  WARNING: All segments muted"
    endif
endif

appendInfoLine: ""
appendInfoLine: "Levels:"
appendInfoLine: "  Input peak: ", fixed$(inPeak, 4)
appendInfoLine: "  Gain range applied: ", fixed$(gainMin, 3), " to ", fixed$(gainMax, 3)
appendInfoLine: "  Output peak before normalization: ", fixed$(prePeak, 4)
if peak_normalize_output
    appendInfoLine: "  Peak normalization: ON (x", fixed$(normGain, 4), " -> ", fixed$(outPeak, 4), ")"
    appendInfoLine: "  NOTE: normalization is a constant gain over the whole file; it does"
    appendInfoLine: "        not preserve the absolute level set by Mute_level or AM_depth."
else
    appendInfoLine: "  Peak normalization: off"
    if outPeak > 1
        appendInfoLine: "  WARNING: output peak exceeds 1.0 and will clip on playback or save."
    endif
endif

# === VISUALIZATION ===
if visualize
    appendInfoLine: ""
    appendInfoLine: "Creating visualization..."

    Erase all

    # === TITLE ===
    Select outer viewport: 1, 8, 0, 0.4
    Axes: 0, 1, 0, 1
    Font size: 11
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Sample-and-Hold## | " + presetName$ + " | " + modeName$

    # === ORIGINAL ===
    Select outer viewport: 0, 8, 0.5, 2.0
    Select inner viewport: 0.8, 7.6, 0.6, 1.8

    selectObject: sound
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"

    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.15, 8, 0.5, 2.0
    Text left: "yes", "Input"

    # === APPLIED GAIN ENVELOPE ===
    # This is the envelope the audio was multiplied by: after Mute_level,
    # after smoothing. v1.1 drew a raw 0/1 gate instead, which did not
    # show Mute_level or any transition shape.
    Select outer viewport: 0, 8, 2.1, 3.4
    Select inner viewport: 0.8, 7.6, 2.2, 3.2

    selectObject: gainEnvDraw
    envMin = Get minimum: 0, 0, "None"
    envMax = Get maximum: 0, 0, "None"
    envLo = min(0, envMin) - 0.05
    envHi = max(1, envMax) + 0.05

    # Background
    Axes: sourceStart, sourceEnd, envLo, envHi
    Paint rectangle: "{0.95, 0.95, 0.95}", sourceStart, sourceEnd, envLo, envHi

    # Unity reference
    Colour: "{0.70, 0.70, 0.70}"
    Dotted line
    Draw line: sourceStart, 1, sourceEnd, 1
    Solid line

    # Gain curve
    selectObject: gainEnvDraw
    Colour: "{0.80, 0.40, 0.30}"
    Line width: 2
    Draw: sourceStart, sourceEnd, envLo, envHi, "no", "Curve"
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.15, 8, 2.1, 3.4
    Text left: "yes", "Applied gain"

    # === OUTPUT ===
    Select outer viewport: 0, 8, 3.5, 5.0
    Select inner viewport: 0.8, 7.6, 3.6, 4.8

    selectObject: result
    Colour: "{0.30, 0.60, 0.50}"
    Draw: 0, 0, 0, 0, "no", "Curve"

    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.15, 8, 3.5, 5.0
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"

    # === PARAMETERS ===
    Select outer viewport: 0, 8, 5.1, 5.5
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.40, 0.40, 0.40}"

    if workingMode = 2
        paramText$ = "Threshold: " + fixed$(workingIntensityThresh, 0) + " dB"
    elsif workingMode = 3
        paramText$ = "Freq: " + fixed$(workingAMFreq, 1) + " Hz | Depth: " + fixed$(workingAMDepth, 2)
    elsif workingMode = 4
        paramText$ = "Pitch threshold: " + fixed$(workingPitchThresh, 0) + " Hz"
    elsif workingMode = 6
        paramText$ = "Centroid threshold: " + fixed$(workingCentroidThresh, 0) + " Hz"
    else
        paramText$ = "Period: " + fixed$(workingPeriod * 1000, 1) + " ms"
    endif

    paramText$ = paramText$ + " | Mute: " + fixed$(mute_level, 2)
    paramText$ = paramText$ + " | Smoothing: " + fixed$(workingSmooth_ms, 2) + " ms (" + smoothName$ + ")"
    if peak_normalize_output
        paramText$ = paramText$ + " | Norm: x" + fixed$(normGain, 3)
    else
        paramText$ = paramText$ + " | Norm: off"
    endif

    Text: 0.5, "centre", 0.5, "half", paramText$

    Font size: 10
    Colour: "Black"
endif

removeObject: gainEnvDraw

# === OUTPUT ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE: ", selected$("Sound")
appendInfoLine: "=============================================="

if play
    appendInfoLine: ""
    appendInfoLine: "Playing..."
    Play
endif

selectObject: result

# ============================================================
# PROCEDURES
# ============================================================

# Parses the whitespace-separated pattern once into patVal[1..count].
# Every token must be numeric: v1.1 accepted "1 a 0" silently, where the
# non-numeric token simply behaved as a value below the threshold.
procedure parsePattern: .pattern$
    .count = 0
    .temp$ = .pattern$
    repeat
        .space_pos = index_regex(.temp$, "[ \t]+")
        if .space_pos > 0
            .val_str$ = left$(.temp$, .space_pos - 1)
            if index_regex(.val_str$, "^[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)$") = 0
                exitScript: "Pattern value " + string$(.count + 1) + " (""" + .val_str$ +
                ... """) is not a number. Use whitespace-separated numeric values, e.g. 1 0 1 1 0."
            endif
            .count = .count + 1
            patVal[.count] = number(.val_str$)
            .temp$ = right$(.temp$, length(.temp$) - .space_pos)
            .temp$ = replace_regex$(.temp$, "^[ \t]+", "", 0)
        endif
    until .space_pos = 0 or length(.temp$) = 0
endproc
