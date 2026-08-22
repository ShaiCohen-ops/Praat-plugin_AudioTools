# ============================================================
# Praat AudioTools - Undertone Field.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 3.4.1 (2026)
# License: MIT License
#
# Description:
#   Creates undertone layers for a mono or stereo phrase using
#   Output is STEREO: undertones spread spatially
#   across the field using equal-power panning.
#
#   UNDERTONE TECHNIQUE — SR REINTERPRETATION:
#     pitchFactor(n) = 1 / (n+1)^(1 + stretch)
#   stretch = 0  -> pure integer series: 1/2, 1/3, 1/4...
#   stretch > 0  -> stretched (wider, inharmonic field)
#   stretch < 0  -> compressed (tighter cluster)
#
#   STEREO SPATIAL LAYOUT:
#   Original  -> centre (equal power L+R)
#   Partial 1 -> hard left
#   Partial N -> hard right
#   Middle    -> graduated equal-power arc
#   panAngle(n) = (n-1)/max(N-1,1) * pi/2
#   gainL = cos(panAngle),  gainR = sin(panAngle)
#
#   GAIN CURVES (applied before panning):
#   Flat        -- all partials equal
#   Linear      -- base - (n-1)*rolloff per partial
#   Exponential -- fast initial drop then levels off
#   Gaussian    -- peak at middle partial
#   Inverse     -- deeper = louder (spectralist bass build)
#
# Changelog v3.4.1: compact Summary typography/spacing; collision-safe gap after bottom-axis labels; DSP/analysis unchanged.
# Changelog v3.4: visualization standardization only - unified typography, summary/full-page Picture framing; DSP/analysis unchanged.
# Changelog v3.4:
#   - Fixed micro-delay ordering: silence is now truly prepended before
#     each delayed partial (Praat concatenates selected Sounds by object order).
#   - Geometric mode is now genuinely microtonal: at stretch=0 denominators
#     are 2, 2.5, 3.125, 3.906... rather than octave-only 2,4,8,16...
#   - Effective pitch factors are derived from the actual overridden sample
#     rate after safety clamping, so synthesis, reporting and visualization agree.
#   - Presets explicitly select their intended Series_mode.
#   - Custom denominator parser validates tokens and continues missing values
#     upward by +1 instead of silently accepting malformed input.
#   - The mono working source is explicitly rebased to 0 seconds, making all
#     buffer, trim and tail operations safe for non-zero source time domains.
#   - Numeric Sound object IDs use explicit channel indexing in formulas.
#   - Final peak protection is attenuation-only (no automatic loudness boost).
#   - Visualization keeps the existing design while fixing series labels,
#     stereo-field left/right geometry, and waveform amplitude scaling.
#
# Category: Synthesis / Spectral / Composition
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

srcID    = selected("Sound")
srcName$ = selected$("Sound")
selectObject: srcID
origDur = Get total duration
origFs  = Get sampling frequency
nCh     = Get number of channels

if origDur < 0.05
    exitScript: "Sound must be at least 50 ms."
endif

# ============================================================
# FORM
# ============================================================

form Undertone SR Reinterpretation v3.4.1
    comment === Preset ===
    optionmenu Preset: 1
        option Custom
        option Pure Harmonic        (integer series, linear rolloff)
        option Stretched Cloud      (wider intervals, Gaussian)
        option Compressed Cluster   (narrower, exponential decay)
        option Bass Spectral        (6 partials, inverse, spectralist)
        option Spectral Haze        (5 partials, micro-stretch, soft)
        option Dark Undertow        (heavy low, fast rolloff, tight LP)
        option Microtonal Dense     (7 partials, tiny stretch, flat)
    comment === Partial Structure ===
    integer Number_of_undertones 4
    comment Stretch: 0=pure  +0.15=wider  -0.15=compressed (Integer/Geometric modes)
    real    Stretch_factor 0.0
    comment Series mode
    optionmenu Series_mode: 1
        option Integer          (1/2  1/3  1/4  ... standard undertone)
        option Odd denominators (1/3  1/5  1/7  ... odd series)
        option Even denominators (1/2  1/4  1/6  ... even/octave series)
        option Custom list      (type denominators below, e.g. 2,3,5,7)
        option Geometric        (1/2  1/2.5  1/3.1  ... microtonal)
    sentence Custom_denominators 2,3,5,7
    comment === Micro-delay decorrelation (ms, 0=off) ===
    real    Micro_delay_ms 1.2
    comment === Gain Curve ===
    optionmenu Gain_curve: 2
        option Flat             (all partials equal)
        option Linear           (linear rolloff per partial)
        option Exponential      (fast rolloff, warm body)
        option Gaussian         (peak at middle partial)
        option Inverse          (deeper = louder, spectralist build)
    real    Base_gain_dB -12.0
    real    Rolloff_dB 3.0
    comment === Filter ===
    positive Lowpass_Hz 2000.0
    comment === Resonance Tail ===
    real Tail_duration_s 1.5
    comment (0 = no tail, 1-3 = undertones linger after source ends)
    comment === Output ===
    boolean Mute_input 0
    comment (mute original — hear only the undertone field)
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS — override form values when not Custom
# ============================================================

if preset = 2
    number_of_undertones = 4
    stretch_factor       = 0.0
    series_mode          = 1
    gain_curve           = 2
    base_gain_dB         = -12.0
    rolloff_dB           = 3.0
    lowpass_Hz           = 2000.0
    tail_duration_s      = 1.5
elsif preset = 3
    number_of_undertones = 5
    stretch_factor       = 0.20
    series_mode          = 1
    gain_curve           = 4
    base_gain_dB         = -10.0
    rolloff_dB           = 2.0
    lowpass_Hz           = 1800.0
    tail_duration_s      = 2.0
elsif preset = 4
    number_of_undertones = 4
    stretch_factor       = -0.20
    series_mode          = 1
    gain_curve           = 3
    base_gain_dB         = -14.0
    rolloff_dB           = 4.0
    lowpass_Hz           = 2500.0
    tail_duration_s      = 1.0
elsif preset = 5
    number_of_undertones = 6
    stretch_factor       = 0.0
    series_mode          = 1
    gain_curve           = 5
    base_gain_dB         = -18.0
    rolloff_dB           = 2.0
    lowpass_Hz           = 1500.0
    tail_duration_s      = 2.5
elsif preset = 6
    number_of_undertones = 5
    stretch_factor       = 0.12
    series_mode          = 5
    gain_curve           = 4
    base_gain_dB         = -9.0
    rolloff_dB           = 1.5
    lowpass_Hz           = 3000.0
    tail_duration_s      = 2.0
elsif preset = 7
    number_of_undertones = 4
    stretch_factor       = -0.10
    series_mode          = 1
    gain_curve           = 3
    base_gain_dB         = -8.0
    rolloff_dB           = 6.0
    lowpass_Hz           = 1200.0
    tail_duration_s      = 1.0
elsif preset = 8
    number_of_undertones = 7
    stretch_factor       = 0.05
    series_mode          = 5
    gain_curve           = 1
    base_gain_dB         = -20.0
    rolloff_dB           = 0.0
    lowpass_Hz           = 2000.0
    tail_duration_s      = 3.0
endif

# ============================================================
# PRESET NAME
# ============================================================

presetName$ = "Custom"
if preset = 2
    presetName$ = "PureHarmonic"
elsif preset = 3
    presetName$ = "StretchedCloud"
elsif preset = 4
    presetName$ = "CompressedCluster"
elsif preset = 5
    presetName$ = "BassSpectral"
elsif preset = 6
    presetName$ = "SpectralHaze"
elsif preset = 7
    presetName$ = "DarkUndertow"
elsif preset = 8
    presetName$ = "MicrotonalDense"
endif

# ============================================================
# STEREO -> MONO WORKING COPY
# ============================================================

selectObject: srcID
if nCh > 1
    monoSrc = Convert to mono
else
    monoSrc = Copy: "UT_src"
endif

# ============================================================
# VALIDATION + 0-BASED WORKING TIME DOMAIN
# ============================================================

if number_of_undertones < 1 or number_of_undertones > 8
    exitScript: "Number_of_undertones must be between 1 and 8."
endif
if stretch_factor < -0.5 or stretch_factor > 0.5
    exitScript: "Stretch_factor must be between -0.5 and +0.5."
endif
if rolloff_dB < 0
    exitScript: "Rolloff_dB must be zero or greater."
endif
if micro_delay_ms < 0 or micro_delay_ms > 20
    exitScript: "Micro_delay_ms must be between 0 and 20 ms."
endif
if tail_duration_s < 0 or tail_duration_s > 10
    exitScript: "Tail_duration_s must be between 0 and 10 seconds."
endif

nyquistSafe = origFs / 2 - 100
if nyquistSafe < 50
    exitScript: "Sampling frequency is too low for the requested filter safety margin."
endif
if lowpass_Hz < 50 or lowpass_Hz > nyquistSafe
    exitScript: "Lowpass_Hz must be between 50 Hz and Nyquist minus 100 Hz."
endif

# All synthesis buffers in this effect are intentionally 0-based.
# Rebase only the mono working copy; the user's original Sound is untouched.
selectObject: monoSrc
monoXmin = Get start time
if abs(monoXmin) > 1e-12
    Shift times by: -monoXmin
endif

# Total output duration including resonance tail.
totalDur = origDur + tail_duration_s

# ============================================================
# GAIN CURVE COMPUTATION
# ============================================================

gainWeight# = zero#(number_of_undertones)
gainDb#     = zero#(number_of_undertones)

gaussMid   = (number_of_undertones + 1) / 2
gaussSigma = number_of_undertones / (rolloff_dB + 0.5)
if gaussSigma < 0.3
    gaussSigma = 0.3
endif

for n from 1 to number_of_undertones
    db = 0
    if gain_curve = 1
        db = base_gain_dB
    elsif gain_curve = 2
        db = base_gain_dB - (n - 1) * rolloff_dB
    elsif gain_curve = 3
        expK = rolloff_dB * 0.23
        db   = base_gain_dB - (n - 1) * rolloff_dB * (1 - exp(-expK))
    elsif gain_curve = 4
        gaussVal = exp(-((n - gaussMid) ^ 2) / (2 * gaussSigma ^ 2))
        db = base_gain_dB + 20 * log10(gaussVal + 1e-6)
    elsif gain_curve = 5
        db = base_gain_dB + (n - 1) * rolloff_dB
        if db > 0
            db = 0
        endif
    endif
    gainDb#[n]     = db
    gainWeight#[n] = 10 ^ (db / 20)
endfor

# ============================================================
# SPATIAL PAN POSITIONS (equal-power arc)
# panAngle = 0 -> hard left (cos=1, sin=0)
# panAngle = pi/2 -> hard right (cos=0, sin=1)
# ============================================================

panAngle# = zero#(number_of_undertones)
panGainL# = zero#(number_of_undertones)
panGainR# = zero#(number_of_undertones)

for n from 1 to number_of_undertones
    if number_of_undertones = 1
        # Single partial: centre-left
        panNorm = 0.25
    else
        panNorm = (n - 1) / (number_of_undertones - 1)
    endif
    angle = panNorm * pi / 2
    panAngle#[n] = panNorm
    panGainL#[n] = cos(angle)
    panGainR#[n] = sin(angle)
endfor

# ============================================================
# GAIN CURVE NAME
# ============================================================

gainCurveName$ = "Flat"
if gain_curve = 2
    gainCurveName$ = "Linear"
elsif gain_curve = 3
    gainCurveName$ = "Exponential"
elsif gain_curve = 4
    gainCurveName$ = "Gaussian"
elsif gain_curve = 5
    gainCurveName$ = "Inverse"
endif

# ============================================================
# INFO HEADER
# ============================================================

clearinfo
writeInfoLine:  "=================================================="
writeInfoLine:  "  Undertone SR Reinterpretation v3.4.1"
writeInfoLine:  "=================================================="
appendInfoLine: ""
appendInfoLine: "Source    : ", srcName$, "  (", fixed$(origDur, 3), " s  ", nCh, "ch)"
appendInfoLine: "Preset    : ", presetName$
appendInfoLine: "Fs        : ", origFs, " Hz"
appendInfoLine: "Undertones: ", number_of_undertones
seriesModeName$ = "Integer"
if series_mode = 2
    seriesModeName$ = "OddDenominators"
elsif series_mode = 3
    seriesModeName$ = "EvenDenominators"
elsif series_mode = 4
    seriesModeName$ = "Custom[" + custom_denominators$ + "]"
elsif series_mode = 5
    seriesModeName$ = "Geometric"
endif

appendInfoLine: "Series    : ", seriesModeName$
appendInfoLine: "Stretch   : ", fixed$(stretch_factor, 3)
appendInfoLine: "Gain curve: ", gainCurveName$,
    ... "  base=", fixed$(base_gain_dB, 1), " dB  rolloff=", fixed$(rolloff_dB, 1), " dB"
appendInfoLine: "Low-pass  : ", fixed$(lowpass_Hz, 0), " Hz"
appendInfoLine: "Tail      : ", fixed$(tail_duration_s, 1), " s"
    ... + " (total: ", fixed$(totalDur, 2), " s)"
appendInfoLine: "Output    : STEREO (equal-power pan arc)"
if mute_input
    appendInfoLine: "Input     : MUTED (undertones only)"
endif
appendInfoLine: ""
appendInfoLine: "n   pitchFactor   overrideSr   gain(dB)   panL    panR"
appendInfoLine: "----------------------------------------------------------"

pitchFactor# = zero#(number_of_undertones)
overrideSr#  = zero#(number_of_undertones)
denom#       = zero#(number_of_undertones)

# ── SERIES MODE: build denominator array ──────────────────────
# Integer:   denom(n) = (n+1)^(1+stretch)
# Odd:       denom(n) = (2n+1)^(1+stretch)
# Even:      denom(n) = (2n)^(1+stretch)
# Custom:    validated comma/semicolon/space separated positive values
# Geometric: denom(1)=2; ratio=1.25^(1+stretch)
#            stretch=0 -> 2, 2.5, 3.125, 3.906... (microtonal)

if series_mode = 4
    parseStr$ = custom_denominators$ + ","
    numBuf$ = ""
    parsedN = 0
    digitCount = 0
    dotCount = 0
    strLen = length(parseStr$)

    for ci from 1 to strLen
        ch$ = mid$(parseStr$, ci, 1)

        if ch$ = "," or ch$ = ";" or ch$ = " "
            if length(numBuf$) > 0
                if digitCount = 0 or dotCount > 1
                    exitScript: "Malformed Custom_denominators token: " + numBuf$
                endif

                parsedN += 1
                if parsedN > number_of_undertones
                    exitScript: "Custom_denominators contains more values than Number_of_undertones."
                endif

                dv = number(numBuf$)
                if dv <= 1
                    exitScript: "Every custom denominator must be greater than 1."
                endif

                denom#[parsedN] = dv
                numBuf$ = ""
                digitCount = 0
                dotCount = 0
            endif
        elsif ch$ >= "0" and ch$ <= "9"
            numBuf$ += ch$
            digitCount += 1
        elsif ch$ = "."
            numBuf$ += ch$
            dotCount += 1
            if dotCount > 1
                exitScript: "Malformed Custom_denominators token: " + numBuf$
            endif
        else
            exitScript: "Unsupported character in Custom_denominators: " + ch$
        endif
    endfor

    if parsedN < 1
        exitScript: "Custom_denominators must contain at least one value."
    endif

    # If fewer values than requested were supplied, continue upward by +1.
    for n from parsedN + 1 to number_of_undertones
        denom#[n] = denom#[n - 1] + 1
    endfor

elsif series_mode = 5
    geoR = 1.25 ^ (1 + stretch_factor)
    for n from 1 to number_of_undertones
        denom#[n] = 2 * (geoR ^ (n - 1))
    endfor

else
    for n from 1 to number_of_undertones
        if series_mode = 1
            rawD = n + 1
        elsif series_mode = 2
            rawD = 2 * n + 1
        else
            rawD = 2 * n
        endif
        denom#[n] = rawD ^ (1 + stretch_factor)
    endfor
endif

# Build nominal and EFFECTIVE pitch factors. Override sampling frequency is
# integer-valued, so the actual factor is oSr/origFs after safety clamping.
nominalPitchFactor# = zero#(number_of_undertones)
pitchFactor# = zero#(number_of_undertones)
overrideSr# = zero#(number_of_undertones)
effectiveDenom# = zero#(number_of_undertones)
srClampCount = 0

for n from 1 to number_of_undertones
    nominalPf = 1 / denom#[n]
    oSr = round(origFs * nominalPf)

    if oSr < 100
        oSr = 100
        srClampCount += 1
    endif
    if oSr > origFs
        oSr = origFs
        srClampCount += 1
    endif

    effectivePf = oSr / origFs

    nominalPitchFactor#[n] = nominalPf
    pitchFactor#[n] = effectivePf
    effectiveDenom#[n] = 1 / effectivePf
    overrideSr#[n] = oSr

    appendInfoLine: n, "   denom=", fixed$(denom#[n], 3),
        ... "  nominal=", fixed$(nominalPf, 4),
        ... "  effective=", fixed$(effectivePf, 4),
        ... "  Fs=", oSr,
        ... "  ", fixed$(gainDb#[n], 1), " dB",
        ... "  L=", fixed$(panGainL#[n], 2), " R=", fixed$(panGainR#[n], 2)
endfor

if srClampCount > 0
    appendInfoLine: "SR safety clamp affected ", srClampCount, " partial(s)."
endif

appendInfoLine: ""

# ============================================================
# UNDERTONE GENERATION LOOP
# ============================================================

appendInfoLine: "Generating undertones..."

# L and R accumulation buffers (mono, will combine to stereo at end)
# Buffers extend to totalDur; original source fills only origDur.
# Original at centre: gainL = gainR = 1/sqrt(2)
origCentreGain = 1 / sqrt(2)

# Create extended buffers (silence for the full totalDur)
Create Sound from formula: "UT_L", 1, 0, totalDur, origFs, "0"
leftBuf = selected("Sound")

Create Sound from formula: "UT_R", 1, 0, totalDur, origFs, "0"
rightBuf = selected("Sound")

# Add original source to the first origDur of each buffer
# (skip if mute_input is on — output will be undertones only)
if mute_input = 0
    monoStr$ = string$(monoSrc)
    origGStr$ = fixed$(origCentreGain, 8)
    origDurStr$ = fixed$(origDur, 10)

    selectObject: leftBuf
    Formula (part): 0, origDur, 1, 1,
        ... "object[" + monoStr$ + ", 1, col] * " + origGStr$

    selectObject: rightBuf
    Formula (part): 0, origDur, 1, 1,
        ... "object[" + monoStr$ + ", 1, col] * " + origGStr$
else
    appendInfoLine: "Input MUTED — undertones only"
endif

for n from 1 to number_of_undertones

    pf  = pitchFactor#[n]
    oSr = overrideSr#[n]

    # Step 1: Duplicate mono working copy
    selectObject: monoSrc
    workCopy = Copy: "UT_work"

    # Step 2: Override SR — reinterpret samples at lower clock rate
    # This lowers pitch by pitchFactor without PSOLA or manipulation
    selectObject: workCopy
    Override sampling frequency: oSr

    # Step 3: Resample back to origFs (50-point sinc interpolation)
    selectObject: workCopy
    resampledID = Resample: origFs, 50
    removeObject: workCopy

    # Step 4: Trim to totalDur (undertones ring into the tail region)
    selectObject: resampledID
    resampledDur = Get total duration

    if resampledDur > totalDur
        trimmedID = Extract part: 0, totalDur, "rectangular", 1, "no"
        removeObject: resampledID
    else
        # Pad with silence if shorter than totalDur
        padDur = totalDur - resampledDur
        Create Sound from formula: "UT_pad", 1, 0, padDur, origFs, "0"
        padID = selected("Sound")
        selectObject: resampledID
        plusObject: padID
        trimmedID = Concatenate
        removeObject: resampledID, padID
    endif

    # Step 5: Low-pass filter (removes aliasing above LowpassHz)
    selectObject: trimmedID
    filteredID = Filter (pass Hann band): 0, lowpass_Hz, 100
    removeObject: trimmedID

    # Step 6: Apply gain curve weight
    selectObject: filteredID
    Formula: "self * " + fixed$(gainWeight#[n], 8)

    # Step 6b: Micro-delay decorrelation
    # Each partial gets a tiny independent delay (0..N * micro_delay_ms).
    # Breaks inter-partial phase coherence, reduces comb-filtering on mix.
    # Implemented by padding silence at start and trimming end to totalDur.
    if micro_delay_ms > 0.0001
        delayDur = (n - 1) * micro_delay_ms / 1000
        if delayDur > 0
            # Praat Concatenate follows Objects-list creation order, not
            # selection order. Create silence first, then a fresh audio copy.
            Create Sound from formula: "UT_delay", 1, 0, delayDur, origFs, "0"
            delayPad = selected("Sound")

            selectObject: filteredID
            delaySource = Copy: "UT_delay_source"

            selectObject: delayPad
            plusObject: delaySource
            delayedID = Concatenate

            removeObject: delayPad, delaySource, filteredID

            # Trim back to totalDur.
            selectObject: delayedID
            delayedDur = Get total duration
            if delayedDur > totalDur
                trimDelID = Extract part: 0, totalDur, "rectangular", 1, "no"
                removeObject: delayedID
                filteredID = trimDelID
            else
                filteredID = delayedID
            endif
        endif
    endif

    # Step 7: Accumulate into L and R buffers using equal-power pan
    # panGainL and panGainR already stored in arrays
    leftID$  = string$(leftBuf)
    rightID$ = string$(rightBuf)
    filtID$  = string$(filteredID)

    gL$ = fixed$(panGainL#[n], 8)
    gR$ = fixed$(panGainR#[n], 8)

    selectObject: leftBuf
    Formula: "self + object[" + filtID$ + ", 1, col] * " + gL$

    selectObject: rightBuf
    Formula: "self + object[" + filtID$ + ", 1, col] * " + gR$

    removeObject: filteredID

    appendInfoLine: "  n=", n,
        ... "  pf=", fixed$(pf, 4),
        ... "  gain=", fixed$(gainDb#[n], 1), " dB",
        ... "  pan L=", fixed$(panGainL#[n], 2), " R=", fixed$(panGainR#[n], 2)

endfor

appendInfoLine: ""

# ============================================================
# COMBINE L + R -> STEREO OUTPUT
# ============================================================

appendInfoLine: "Combining to stereo..."

selectObject: leftBuf
plusObject: rightBuf
stereoMix = Combine to stereo
removeObject: leftBuf, rightBuf, monoSrc

selectObject: stereoMix
peakVal = Get absolute extremum: 0, 0, "None"
peakSafetyApplied = 0
if peakVal > 0.99
    Scale peak: 0.99
    peakSafetyApplied = 1
endif

# Apply exponential fade-out over the tail region
# Envelope: exp(-k * (t - origDur)) where k gives -60 dB at tail end
if tail_duration_s > 0.01
    appendInfoLine: "Applying tail fade-out..."
    fadeK = ln(1000) / tail_duration_s
    origDurStr$ = fixed$(origDur, 10)
    fadeKStr$ = fixed$(fadeK, 10)

    selectObject: stereoMix
    Formula (part): origDur, totalDur, 1, 2,
        ... "self * exp(-" + fadeKStr$ + " * (x - " + origDurStr$ + "))"
endif

outputName$ = srcName$ + "_undertones_" + presetName$
Rename: outputName$
mixID  = selected("Sound")
mixDur = Get total duration

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization = 1

    appendInfoLine: "Drawing visualization..."

    selectObject: srcID
    srcPeak = Get absolute extremum: 0, 0, "None"
    selectObject: mixID
    mixPeak = Get absolute extremum: 0, 0, "None"

    ampBase = max(srcPeak, mixPeak)
    if ampBase < 0.001
        ampBase = 0.001
    endif
    ampMax = ampBase * 1.15

    Erase all

    # === TITLE ===
    Select outer viewport: 0, 8, 0, 0.46
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.73, "half", "##Undertone SR Reinterpretation v3.4.1  — Stereo##"
    Font size: 7.5
    Colour: "{0.35, 0.35, 0.45}"
    Text: 0.5, "centre", -0.08, "half",
        ... "[" + presetName$ + "]  " + srcName$
        ... + "  |  N=" + string$(number_of_undertones)
        ... + "  stretch=" + fixed$(stretch_factor, 2)
        ... + "  " + gainCurveName$
        ... + "  base=" + fixed$(base_gain_dB, 0) + "dB"
        ... + "  LP=" + fixed$(lowpass_Hz, 0) + "Hz"
        ... + "  tail=" + fixed$(tail_duration_s, 1) + "s"

    # --- Panel 1: Input waveform ---
    Select outer viewport: 0, 8, 0.50, 1.30
    Select inner viewport: 0.58, 7.65, 0.55, 1.25
    Axes: 0, origDur, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, origDur, -ampMax, ampMax
    Colour: "{0.80, 0.80, 0.80}"
    Draw line: 0, 0, origDur, 0
    selectObject: srcID
    Colour: "{0.42, 0.48, 0.58}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"
    Text top: "no", "Original: " + srcName$

    # --- Panel 2: Output stereo waveform (L grey, R blue) ---
    Select outer viewport: 0, 8, 1.33, 2.13
    Select inner viewport: 0.58, 7.65, 1.38, 2.08
    Axes: 0, mixDur, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, mixDur, -ampMax, ampMax
    Colour: "{0.80, 0.80, 0.80}"
    Draw line: 0, 0, mixDur, 0
    # Draw L channel (grey)
    selectObject: mixID
    Extract one channel: 1
    vizL = selected("Sound")
    Colour: "{0.68, 0.68, 0.72}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    # Overlay R channel (lighter)
    selectObject: mixID
    Extract one channel: 2
    vizR = selected("Sound")
    Colour: "{0.40, 0.50, 0.75}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    removeObject: vizL, vizR
    # Tail boundary marker
    if tail_duration_s > 0.01
        Colour: "{0.80, 0.45, 0.25}"
        Dashed line
        Draw line: origDur, -ampMax, origDur, ampMax
        Solid line
        Font size: 6
        Text: origDur, "left", ampMax * 0.85, "half", " tail"
    endif
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text top: "no", outputName$ + "  (L=grey  R=blue)"
    Text bottom: "yes", "Time (s)"

    # --- Panel 3: Input spectrogram ---
    Select outer viewport: 0, 4, 2.20, 3.55
    Select inner viewport: 0.55, 3.75, 2.25, 3.50
    selectObject: srcID
    To Spectrogram: 0.005, min(origFs / 2, 8000), 0.002, 20, "Gaussian"
    inSpec = selected("Spectrogram")
    selectObject: inSpec
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Input spectrogram"
    removeObject: inSpec

    # --- Panel 4: Output spectrogram ---
    Select outer viewport: 4, 8, 2.20, 3.55
    Select inner viewport: 4.18, 7.65, 2.25, 3.50
    selectObject: mixID
    To Spectrogram: 0.005, min(origFs / 2, 8000), 0.002, 20, "Gaussian"
    outSpec = selected("Spectrogram")
    selectObject: outSpec
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Output spectrogram (mix)"
    removeObject: outSpec

    # --- Panel 5: Partial structure + stereo field diagram ---
    # Height = pitch ratio  Color = register  Bottom label = pan position
    Select outer viewport: 0, 4, 3.62, 5.00
    Select inner viewport: 0.55, 3.75, 3.67, 4.95

    Axes: 0, number_of_undertones + 1.5, 0, 1.18
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, number_of_undertones + 1.5, 0, 1.18

    # Grid lines at musical intervals
    Colour: "{0.88, 0.88, 0.88}"
    Dotted line
    Draw line: 0, 0.5,  number_of_undertones + 1.5, 0.5
    Draw line: 0, 0.25, number_of_undertones + 1.5, 0.25
    Draw line: 0, 0.33, number_of_undertones + 1.5, 0.33
    Solid line

    # Original (amber, centre)
    Paint rectangle: "{0.90, 0.65, 0.15}", 0.15, 0.85, 0, 1.0
    Font size: 6
    Colour: "{0.55, 0.38, 0.00}"
    Text: 0.5, "centre", 1.06, "half", "orig"
    Text: 0.5, "centre", -0.05, "half", "C"

    # Undertones: warm red -> deep indigo, L-R pan below bar
    for n from 1 to number_of_undertones
        pf = pitchFactor#[n]
        cFrac = (n - 1) / (number_of_undertones)
        cR = 0.85 - cFrac * 0.70
        cG = 0.30 - cFrac * 0.05
        cB = 0.15 + cFrac * 0.50

        Paint rectangle: "{" + fixed$(cR, 2) + "," + fixed$(cG, 2) + "," + fixed$(cB, 2) + "}",
            ... n + 0.10, n + 0.90, 0, pf

        Font size: 6
        Colour: "{" + fixed$(cR * 0.55, 2) + "," + fixed$(cG * 0.55, 2) + "," + fixed$(cB * 0.55, 2) + "}"
        Text: n + 0.5, "centre", pf + 0.04, "half",
            ... "1/" + fixed$(effectiveDenom#[n], 2)

        # Pan indicator: L=100, R=100, proportional
        panPct = round(panAngle#[n] * 100)
        panLabel$ = "L"
        if panAngle#[n] > 0.65
            panLabel$ = "R"
        elsif panAngle#[n] > 0.35
            panLabel$ = "C"
        endif
        Text: n + 0.5, "centre", -0.05, "half", panLabel$
    endfor

    # Pitch ratio reference labels on right
    Font size: 6
    Colour: "{0.55, 0.55, 0.60}"
    Text: number_of_undertones + 1.3, "right", 1.00, "half", "P"
    Text: number_of_undertones + 1.3, "right", 0.50, "half", "-8ve"
    Text: number_of_undertones + 1.3, "right", 0.33, "half", "-P5"
    Text: number_of_undertones + 1.3, "right", 0.25, "half", "-2oct"

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Pitch ratio"
    Text bottom: "yes", "Partial n  (C=centre  L=left  R=right)"
    Text top: "no", "Partial structure  (color=register  label=pan)"

    # --- Panel 6: Stereo pan + gain arc diagram ---
    Select outer viewport: 4, 8, 3.62, 5.00
    Select inner viewport: 4.18, 7.65, 3.67, 4.95

    # Semicircle panning diagram
    # X axis: -1 (L) to +1 (R), Y axis: 0 to 1
    Axes: -1.3, 1.3, -0.15, 1.25
    Paint rectangle: "{0.97, 0.97, 0.97}", -1.3, 1.3, -0.15, 1.25

    # Draw a true L-centre-R semicircle.
    nArcPts = 30
    Colour: "{0.75, 0.75, 0.80}"
    Line width: 1
    for ai from 2 to nArcPts
        a1 = (ai - 2) / (nArcPts - 1) * pi
        a2 = (ai - 1) / (nArcPts - 1) * pi
        x1 = -cos(a1)
        y1 = sin(a1)
        x2 = -cos(a2)
        y2 = sin(a2)
        Draw line: x1, y1, x2, y2
    endfor

    # L / R / C labels on arc
    Font size: 6
    Colour: "{0.55, 0.55, 0.60}"
    Text: -1.1, "left", 0.02, "half", "L"
    Text:  1.05, "left", 0.02, "half", "R"
    Text: -0.05, "centre", 1.05, "half", "C"

    # Original at centre top
    Paint circle (mm): "{0.90, 0.65, 0.15}", 0.0, 1.0, 2.2
    Font size: 6
    Colour: "{0.55, 0.38, 0.00}"
    Text: 0.0, "centre", 1.12, "half", "orig"

    # Partial dots colored by register
    for n from 1 to number_of_undertones
        angle = panAngle#[n] * pi / 2
        # Map actual equal-power pan angle onto an L-centre-R semicircle:
        # angle=0 -> L (-1,0); pi/4 -> C (0,1); pi/2 -> R (+1,0)
        xp = -cos(2 * angle)
        yp = sin(2 * angle)

        cFrac = (n - 1) / (number_of_undertones)
        cR = 0.85 - cFrac * 0.70
        cG = 0.30 - cFrac * 0.05
        cB = 0.15 + cFrac * 0.50

        # Dot size proportional to gain (louder = bigger)
        dotR = 1.2 + gainWeight#[n] * 2.5
        if dotR > 4.0
            dotR = 4.0
        endif
        if dotR < 0.8
            dotR = 0.8
        endif

        Paint circle (mm): "{" + fixed$(cR, 2) + "," + fixed$(cG, 2) + "," + fixed$(cB, 2) + "}",
            ... xp, yp, dotR

        Font size: 6
        Colour: "{" + fixed$(cR * 0.55, 2) + "," + fixed$(cG * 0.55, 2) + "," + fixed$(cB * 0.55, 2) + "}"
        Text: xp, "centre", yp + 0.10, "half", string$(n)
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "R gain"
    Text bottom: "yes", "L - Centre - R"
    Text top: "no", "Stereo field  (dot=partial  size=gain  color=register)"

    Font size: 10
    Colour: "Black"
    Line width: 1


    # ----------------------------------------------------------
    # Summary strip
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.12, 5.68
    Select inner viewport: 0.60, 7.70, 5.12 + 0.04, 5.68 - 0.04
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.72, "half", "##Summary##"
    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.02, "left", 0.45, "half", "Undertone mapping • reinterpretation field • reconstructed output"
    Text: 0.02, "left", 0.20, "half", "Undertone Field • run parameters are reported in the Info window"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    pageHeight = 5.78
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# ============================================================
# SUMMARY
# ============================================================

appendInfoLine: ""
appendInfoLine: "=================================================="
appendInfoLine: "  COMPLETE"
appendInfoLine: "=================================================="
appendInfoLine: "Output   : ", outputName$, "  (stereo)"
appendInfoLine: "Duration : ", fixed$(mixDur, 3), " s"
    ... + "  (source: ", fixed$(origDur, 3), " + tail: ", fixed$(tail_duration_s, 1), ")"
appendInfoLine: "Preset   : ", presetName$
appendInfoLine: "Peak safety: ", peakSafetyApplied
appendInfoLine: "Channels : 2  (original centre, undertones spread L->R)"
appendInfoLine: ""
appendInfoLine: "Objects: original + ", outputName$

selectObject: mixID

if play_result = 1
    Play
endif
