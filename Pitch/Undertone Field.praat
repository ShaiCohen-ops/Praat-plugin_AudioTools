# ============================================================
# Praat AudioTools - Undertone Field.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 3.1 (2025)
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

form Undertone SR Reinterpretation v3.1
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
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS — override form values when not Custom
# ============================================================

if preset = 2
    number_of_undertones = 4
    stretch_factor       = 0.0
    gain_curve           = 2
    base_gain_dB         = -12.0
    rolloff_dB           = 3.0
    lowpass_Hz           = 2000.0
elsif preset = 3
    number_of_undertones = 5
    stretch_factor       = 0.20
    gain_curve           = 4
    base_gain_dB         = -10.0
    rolloff_dB           = 2.0
    lowpass_Hz           = 1800.0
elsif preset = 4
    number_of_undertones = 4
    stretch_factor       = -0.20
    gain_curve           = 3
    base_gain_dB         = -14.0
    rolloff_dB           = 4.0
    lowpass_Hz           = 2500.0
elsif preset = 5
    number_of_undertones = 6
    stretch_factor       = 0.0
    gain_curve           = 5
    base_gain_dB         = -18.0
    rolloff_dB           = 2.0
    lowpass_Hz           = 1500.0
elsif preset = 6
    number_of_undertones = 5
    stretch_factor       = 0.12
    gain_curve           = 4
    base_gain_dB         = -9.0
    rolloff_dB           = 1.5
    lowpass_Hz           = 3000.0
elsif preset = 7
    number_of_undertones = 4
    stretch_factor       = -0.10
    gain_curve           = 3
    base_gain_dB         = -8.0
    rolloff_dB           = 6.0
    lowpass_Hz           = 1200.0
elsif preset = 8
    number_of_undertones = 7
    stretch_factor       = 0.05
    gain_curve           = 1
    base_gain_dB         = -20.0
    rolloff_dB           = 0.0
    lowpass_Hz           = 2000.0
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
# CLAMPS
# ============================================================

if number_of_undertones < 1
    number_of_undertones = 1
endif
if number_of_undertones > 8
    number_of_undertones = 8
endif
if stretch_factor < -0.5
    stretch_factor = -0.5
endif
if stretch_factor > 0.5
    stretch_factor = 0.5
endif
if lowpass_Hz > origFs / 2 - 100
    lowpass_Hz = origFs / 2 - 100
endif
if lowpass_Hz < 50
    lowpass_Hz = 50
endif
if rolloff_dB < 0
    rolloff_dB = 0
endif
if micro_delay_ms < 0
    micro_delay_ms = 0
endif
if micro_delay_ms > 20
    micro_delay_ms = 20
endif

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
writeInfoLine:  "  Undertone SR Reinterpretation v3.1"
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
appendInfoLine: "Output    : STEREO (equal-power pan arc)"
appendInfoLine: ""
appendInfoLine: "n   pitchFactor   overrideSr   gain(dB)   panL    panR"
appendInfoLine: "----------------------------------------------------------"

pitchFactor# = zero#(number_of_undertones)
overrideSr#  = zero#(number_of_undertones)
denom#       = zero#(number_of_undertones)

# ── SERIES MODE: build denominator array ──────────────────────
# Integer:  denom(n) = (n+1)^(1+stretch)   → 2, 3, 4, 5...
# Odd:      denom(n) = (2n+1)^(1+stretch)  → 3, 5, 7, 9...
# Even:     denom(n) = (2n)^(1+stretch)    → 2, 4, 6, 8...
# Custom:   parse comma-separated string, clamp to N values
# Geometric:r = 2^(1+stretch), denom(n) = 2 * r^(n-1)
#           → 2, 2^(1+s), 2^(2+2s)...  microtonal spacing

if series_mode = 4
    # Parse custom_denominators$ into denom# array
    # Walk string char by char, collect digit runs
    parseStr$ = custom_denominators$ + ","
    numBuf$   = ""
    parsedN   = 0
    strLen    = length(parseStr$)

    for ci from 1 to strLen
        ch$ = mid$(parseStr$, ci, 1)
        if ch$ = "," or ch$ = ";" or ch$ = " "
            if length(numBuf$) > 0 and parsedN < number_of_undertones
                parsedN = parsedN + 1
                dv = number(numBuf$)
                if dv < 1.01
                    dv = 1.01
                endif
                denom#[parsedN] = dv
                numBuf$ = ""
            endif
        elsif ch$ >= "0" and ch$ <= "9" or ch$ = "."
            numBuf$ = numBuf$ + ch$
        endif
    endfor
    # If user gave fewer values than N, repeat last value
    if parsedN = 0
        parsedN = 1
        denom#[1] = 2
    endif
    for n from parsedN + 1 to number_of_undertones
        denom#[n] = denom#[parsedN] + (n - parsedN)
    endfor

elsif series_mode = 5
    # Geometric: base ratio r = 2^(1 + stretch_factor)
    # denom(1) = 2, denom(n) = 2 * r^(n-1)
    geoR = 2 ^ (1 + stretch_factor)
    for n from 1 to number_of_undertones
        denom#[n] = 2 * (geoR ^ (n - 1))
    endfor

else
    # Integer, Odd, Even — use stretch exponent
    for n from 1 to number_of_undertones
        if series_mode = 1
            # Integer: 2, 3, 4, 5...
            rawD = n + 1
        elsif series_mode = 2
            # Odd denominators: 3, 5, 7, 9...
            rawD = 2 * n + 1
        elsif series_mode = 3
            # Even denominators: 2, 4, 6, 8...
            rawD = 2 * n
        endif
        denom#[n] = rawD ^ (1 + stretch_factor)
    endfor
endif

# Build pitchFactor# from denom#
for n from 1 to number_of_undertones
    pf  = 1 / denom#[n]
    oSr = round(origFs * pf)
    if oSr < 100
        oSr = 100
    endif
    pitchFactor#[n] = pf
    overrideSr#[n]  = oSr
    appendInfoLine: n, "   denom=", fixed$(denom#[n], 3),
        ... "  pf=", fixed$(pf, 4), "  Fs=", oSr,
        ... "  ", fixed$(gainDb#[n], 1), " dB",
        ... "  L=", fixed$(panGainL#[n], 2), " R=", fixed$(panGainR#[n], 2)
endfor

appendInfoLine: ""

# ============================================================
# UNDERTONE GENERATION LOOP
# ============================================================

appendInfoLine: "Generating undertones..."

# L and R accumulation buffers (mono, will combine to stereo at end)
# Original at centre: gainL = gainR = 1/sqrt(2)
origCentreGain = 1 / sqrt(2)

selectObject: monoSrc
leftBuf = Copy: "UT_L"
selectObject: leftBuf
Formula: "self * " + fixed$(origCentreGain, 8)

selectObject: monoSrc
rightBuf = Copy: "UT_R"
selectObject: rightBuf
Formula: "self * " + fixed$(origCentreGain, 8)

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

    # Step 4: Trim to original duration (resampled is (n+1)x longer)
    selectObject: resampledID
    resampledDur = Get total duration

    if resampledDur > origDur
        trimmedID = Extract part: 0, origDur, "rectangular", 1, "no"
        removeObject: resampledID
    else
        padDur = origDur - resampledDur
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
    # Implemented by padding silence at start and trimming end to origDur.
    if micro_delay_ms > 0.0001
        delayDur = (n - 1) * micro_delay_ms / 1000
        if delayDur > 0
            Create Sound from formula: "UT_delay", 1, 0, delayDur, origFs, "0"
            delayPad = selected("Sound")
            selectObject: delayPad
            plusObject: filteredID
            delayedID = Concatenate
            removeObject: delayPad, filteredID
            # Trim back to origDur
            selectObject: delayedID
            delayedDur = Get total duration
            if delayedDur > origDur
                trimDelID = Extract part: 0, origDur, "rectangular", 1, "no"
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
    Formula: "self + object[" + filtID$ + "] * " + gL$

    selectObject: rightBuf
    Formula: "self + object[" + filtID$ + "] * " + gR$

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
if peakVal > 0.001
    Scale peak: 0.99
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
    if srcPeak < 0.001
        srcPeak = 0.001
    endif
    ampMax = srcPeak * 1.15

    Erase all

    # === TITLE ===
    Select outer viewport: 0, 8, 0, 0.46
    Axes: 0, 1, 0, 1
    Font size: 11
    Colour: "Black"
    Text: 0.5, "centre", 0.73, "half", "##Undertone SR Reinterpretation v3.1  — Stereo##"
    Font size: 7.5
    Colour: "{0.35, 0.35, 0.45}"
    Text: 0.5, "centre", -0.08, "half",
        ... "[" + presetName$ + "]  " + srcName$
        ... + "  |  N=" + string$(number_of_undertones)
        ... + "  stretch=" + fixed$(stretch_factor, 2)
        ... + "  " + gainCurveName$
        ... + "  base=" + fixed$(base_gain_dB, 0) + "dB"
        ... + "  LP=" + fixed$(lowpass_Hz, 0) + "Hz"

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
    Colour: "{0.68, 0.68, 0.72}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text top: "no", outputName$ + "  (stereo)"
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
    Font size: 5
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

        Font size: 5
        Colour: "{" + fixed$(cR * 0.55, 2) + "," + fixed$(cG * 0.55, 2) + "," + fixed$(cB * 0.55, 2) + "}"
        Text: n + 0.5, "centre", pf + 0.04, "half",
            ... "1/" + fixed$((n + 1) ^ (1 + stretch_factor), 2)

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
    Font size: 5
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

    # Draw arc (quarter circle from left to right)
    nArcPts = 30
    Colour: "{0.75, 0.75, 0.80}"
    Line width: 1
    for ai from 2 to nArcPts
        a1 = (ai - 2) / (nArcPts - 1) * pi / 2
        a2 = (ai - 1) / (nArcPts - 1) * pi / 2
        x1 = cos(a1) * 2 - 1
        y1 = sin(a1)
        x2 = cos(a2) * 2 - 1
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
    Font size: 5
    Colour: "{0.55, 0.38, 0.00}"
    Text: 0.0, "centre", 1.12, "half", "orig"

    # Partial dots colored by register
    for n from 1 to number_of_undertones
        angle = panAngle#[n] * pi / 2
        # Map from equal-power arc to x/y:
        # L side: angle=0 -> x=-1, y=0
        # R side: angle=pi/2 -> x=+1, y=0
        # Centre: angle=pi/4 -> x=0, y=1
        xp = (cos(angle) - sin(angle))
        yp = (cos(angle) + sin(angle)) / sqrt(2)

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

        Font size: 5
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
appendInfoLine: "Preset   : ", presetName$
appendInfoLine: "Channels : 2  (original centre, undertones spread L->R)"
appendInfoLine: ""
appendInfoLine: "Objects: original + ", outputName$

selectObject: mixID

if play_result = 1
    Play
endif
