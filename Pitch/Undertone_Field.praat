# ============================================================
# Praat AudioTools - Undertone Field.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 3.5 (2026)
# License: MIT License
#
# Description:
#   Creates undertone layers for a mono or stereo phrase using
#   sample-rate reinterpretation. Output is STEREO: undertones
#   spread spatially across the field using equal-power panning.
#
#   UNDERTONE TECHNIQUE — SR REINTERPRETATION:
#     pitchFactor(n) = 1 / (n+1)^(1 + stretch)
#   stretch = 0  -> pure integer series: 1/2, 1/3, 1/4...
#   stretch > 0  -> stretched (wider, inharmonic field)
#   stretch < 0  -> compressed (tighter cluster)
#
#   STEREO SPATIAL LAYOUT:
#   Original  -> centre (equal power L+R)
#   Partial 1 -> left, Partial N -> right, scaled by Stereo_spread
#   panAngle(n) = panNorm * pi/2
#   gainL = cos(panAngle),  gainR = sin(panAngle)
#
#   GAIN CURVES (applied before panning):
#   Flat        -- all partials equal
#   Linear      -- base - (n-1)*rolloff per partial
#   Exponential -- fast initial drop then levels off (saturating)
#   Gaussian    -- peak at middle partial
#   Inverse     -- deeper = louder (spectralist bass build)
#
#   PRESENCE CHAIN (new in 3.5, applied per partial before panning):
#     1. RMS match      -- partial normalised to the source RMS, so the
#                          gain curve is read in dB RELATIVE TO SOURCE
#                          instead of relative to whatever survived the
#                          low-pass filter.
#     2. Presence tilt  -- +dB per octave of downward transposition,
#                          compensating the equal-loudness roll-off that
#                          makes deep partials read as absent.
#     3. Gain curve     -- as above.
#     4. Input trim     -- independent level for the dry original.
#
# Changelog v3.5:
#   PRESENCE (audible behaviour changes):
#   - Per-partial RMS normalisation (Normalise_partials, default on).
#     Base_gain_dB / Rolloff_dB are now dB relative to the source RMS.
#     Previously the gain curve multiplied the raw low-pass output, so a
#     partial's real level depended on how much of the source spectrum
#     happened to survive the filter — the main cause of weak undertones.
#   - Presence_tilt_dB: loudness compensation per octave of transposition
#     (default 3.0 dB/oct). Deep partials no longer read as absent.
#   - Input_gain_dB: independent trim on the dry original so the field can
#     be brought forward without muting the input entirely.
#   - Stereo_spread_pct: hard L/R placement cost roughly 3 dB of perceived
#     centre presence; default 80 keeps the arc but pulls it inward.
#     A single undertone is now centred (was panned to 0.25 = left of centre).
#   - Default Base_gain_dB -12 -> -6, Rolloff_dB 3.0 -> 1.5,
#     Lowpass_Hz 2000 -> 3000 (more definition, less mud). Preset gains
#     rebalanced for the new relative-to-source scale.
#   - Exponential gain curve fixed: the old formula was linear in n with a
#     scaled slope, not exponential. It is now a genuinely saturating
#     curve, so high partials sit higher than before.
#   - Peak-safety attenuation is now measured and reported in dB.
#   VISUALIZATION (rebuilt):
#   - Both spectrogram panels removed.
#   - New LTAS spectral-balance panel on a log-frequency axis, input vs
#     output, with the added energy shaded and each partial's register
#     marked — this is the panel that answers "are the undertones there".
#   - Output waveform split into separate L and R tracks (was an overlay).
#   - Input waveform now shares the output time axis, so the tail region
#     is visible as empty space.
#   - New level-balance panel: measured dB relative to source per partial,
#     with the requested curve value marked, so normalisation and tilt are
#     inspectable.
#   - Stereo field is now a polar level plot: angle = pan, radius = measured
#     level, unit arc = source level.
#   - Drawing order follows the frame rules (font before viewport select,
#     re-select between groups, no Text bottom/left collisions).
#
# Changelog v3.4.1: compact Summary typography/spacing; collision-safe gap
#   after bottom-axis labels; DSP/analysis unchanged.
# Changelog v3.4: micro-delay ordering fix; genuinely microtonal Geometric
#   mode; effective pitch factors derived from the clamped override rate;
#   validated custom denominator parser; 0-based mono working copy;
#   attenuation-only peak protection.
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

form Undertone Field v3.5
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
    comment === Structure ===
    integer Number_of_undertones 4
    optionmenu Series_mode: 1
        option Integer          (1/2  1/3  1/4  ... standard undertone)
        option Odd denominators (1/3  1/5  1/7  ... odd series)
        option Even denominators (1/2  1/4  1/6  ... even/octave series)
        option Custom list      (denominators are set under Advanced)
        option Geometric        (1/2  1/2.5  1/3.1  ... microtonal)
    optionmenu Gain_curve: 2
        option Flat             (all partials equal)
        option Linear           (linear rolloff per partial)
        option Exponential      (fast rolloff, warm body)
        option Gaussian         (peak at middle partial)
        option Inverse          (deeper = louder, spectralist build)
    comment === Level and filter ===
    real Field_level_dB -3.0
    comment (whole undertone bed vs source; 0 = as loud as the original)
    positive Lowpass_Hz 3000.0
    real Tail_duration_s 1.5
    comment === Output ===
    boolean Show_advanced_settings 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# ADVANCED DEFAULTS
# ============================================================
# These are not on the main form. Presets may override them below, and the
# optional Advanced dialog opens pre-filled with whatever value is current,
# so a preset stays inspectable instead of being a black box.

stretch_factor        = 0.0
custom_denominators$  = "2,3,5,7"
micro_delay_ms        = 1.2
rolloff_dB            = 3.0
normalise_partials    = 1
presence_tilt_dB      = 3.0
input_gain_dB         = 0.0
stereo_spread_pct     = 80.0
mute_input            = 0

# ============================================================
# PRESETS — override form values when not Custom
# ============================================================

if preset = 2
    number_of_undertones = 4
    stretch_factor       = 0.0
    series_mode          = 1
    gain_curve           = 2
    rolloff_dB           = 2.5
    field_level_dB       = -3.0
    presence_tilt_dB     = 3.0
    input_gain_dB        = 0.0
    stereo_spread_pct    = 80.0
    lowpass_Hz           = 3000.0
    tail_duration_s      = 1.5
elsif preset = 3
    number_of_undertones = 5
    stretch_factor       = 0.20
    series_mode          = 1
    gain_curve           = 4
    rolloff_dB           = 3.0
    field_level_dB       = -2.0
    presence_tilt_dB     = 3.0
    input_gain_dB        = 0.0
    stereo_spread_pct    = 85.0
    lowpass_Hz           = 2600.0
    tail_duration_s      = 2.0
elsif preset = 4
    number_of_undertones = 4
    stretch_factor       = -0.20
    series_mode          = 1
    gain_curve           = 3
    rolloff_dB           = 4.0
    field_level_dB       = -4.0
    presence_tilt_dB     = 3.0
    input_gain_dB        = 0.0
    stereo_spread_pct    = 75.0
    lowpass_Hz           = 3200.0
    tail_duration_s      = 1.0
elsif preset = 5
    number_of_undertones = 6
    stretch_factor       = 0.0
    series_mode          = 1
    gain_curve           = 5
    rolloff_dB           = 2.5
    field_level_dB       = 0.0
    presence_tilt_dB     = 5.0
    input_gain_dB        = -3.0
    stereo_spread_pct    = 85.0
    lowpass_Hz           = 2200.0
    tail_duration_s      = 2.5
elsif preset = 6
    number_of_undertones = 5
    stretch_factor       = 0.12
    series_mode          = 5
    gain_curve           = 4
    rolloff_dB           = 2.0
    field_level_dB       = -4.0
    presence_tilt_dB     = 2.0
    input_gain_dB        = 0.0
    stereo_spread_pct    = 90.0
    lowpass_Hz           = 3600.0
    tail_duration_s      = 2.0
elsif preset = 7
    number_of_undertones = 4
    stretch_factor       = -0.10
    series_mode          = 1
    gain_curve           = 3
    rolloff_dB           = 6.0
    field_level_dB       = 1.0
    presence_tilt_dB     = 5.0
    input_gain_dB        = -4.0
    stereo_spread_pct    = 70.0
    lowpass_Hz           = 1600.0
    tail_duration_s      = 1.0
elsif preset = 8
    number_of_undertones = 7
    stretch_factor       = 0.05
    series_mode          = 5
    gain_curve           = 1
    rolloff_dB           = 0.0
    field_level_dB       = -5.0
    presence_tilt_dB     = 3.0
    input_gain_dB        = 0.0
    stereo_spread_pct    = 100.0
    lowpass_Hz           = 3000.0
    tail_duration_s      = 3.0
endif

# ============================================================
# ADVANCED SETTINGS (optional second dialog)
# ============================================================

if show_advanced_settings = 1
    beginPause: "Undertone Field — advanced settings"
        comment: "Series"
        real: "Stretch_factor", string$(stretch_factor)
        comment: "0 = pure, +0.15 wider, -0.15 compressed (Integer/Geometric)"
        sentence: "Custom_denominators", custom_denominators$
        comment: "Balance between partials (level is set by Field level)"
        real: "Rolloff_dB", string$(rolloff_dB)
        boolean: "Normalise_partials", normalise_partials
        real: "Presence_tilt_dB", string$(presence_tilt_dB)
        comment: "extra dB per octave of downward transposition, 0 = off"
        comment: "Space and mix"
        real: "Micro_delay_ms", string$(micro_delay_ms)
        real: "Stereo_spread_pct", string$(stereo_spread_pct)
        real: "Input_gain_dB", string$(input_gain_dB)
        boolean: "Mute_input", mute_input
    advClicked = endPause: "Cancel", "Continue", 2, 1
    if advClicked = 1
        exitScript: ""
    endif
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
if field_level_dB < -40 or field_level_dB > 12
    exitScript: "Field_level_dB must be between -40 and +12 dB."
endif
if presence_tilt_dB < 0 or presence_tilt_dB > 12
    exitScript: "Presence_tilt_dB must be between 0 and 12 dB per octave."
endif
if input_gain_dB < -60 or input_gain_dB > 12
    exitScript: "Input_gain_dB must be between -60 and +12 dB."
endif
if stereo_spread_pct < 0 or stereo_spread_pct > 100
    exitScript: "Stereo_spread_pct must be between 0 and 100."
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

# Reference level for the presence chain.
selectObject: monoSrc
srcRms = Get root-mean-square: 0, origDur
if srcRms = undefined or srcRms < 1e-7
    srcRms = 1e-7
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
    # The curve sets the BALANCE between partials only. Absolute level is
    # set afterwards by the Field_level_dB normalisation, so no base term.
    db = 0
    if gain_curve = 1
        db = 0
    elsif gain_curve = 2
        db = -(n - 1) * rolloff_dB
    elsif gain_curve = 3
        # Saturating exponential: fast initial drop, then levels off.
        # Asymptotic total drop = 2.2 * rolloff_dB.
        db = -rolloff_dB * 2.2 * (1 - exp(-0.85 * (n - 1)))
    elsif gain_curve = 4
        gaussVal = exp(-((n - gaussMid) ^ 2) / (2 * gaussSigma ^ 2))
        db = 20 * log10(gaussVal + 1e-6)
    elsif gain_curve = 5
        db = (n - 1) * rolloff_dB
    endif
    gainDb#[n] = db
endfor

# The curve is a shape, not a level: slide it so its loudest partial reads
# 0 dB. This keeps the reported curve column readable and keeps the field
# offset below small, whichever curve is chosen.
curveMax = gainDb#[1]
for n from 1 to number_of_undertones
    if gainDb#[n] > curveMax
        curveMax = gainDb#[n]
    endif
endfor
for n from 1 to number_of_undertones
    gainDb#[n] = gainDb#[n] - curveMax
    gainWeight#[n] = 10 ^ (gainDb#[n] / 20)
endfor

# ============================================================
# SPATIAL PAN POSITIONS (equal-power arc, scaled by spread)
# panNorm = 0   -> hard left (cos=1, sin=0)
# panNorm = 0.5 -> centre
# panNorm = 1   -> hard right (cos=0, sin=1)
# ============================================================

panAngle# = zero#(number_of_undertones)
panGainL# = zero#(number_of_undertones)
panGainR# = zero#(number_of_undertones)

spreadLin = stereo_spread_pct / 100

for n from 1 to number_of_undertones
    if number_of_undertones = 1
        rawNorm = 0.5
    else
        rawNorm = (n - 1) / (number_of_undertones - 1)
    endif
    panNorm = 0.5 + (rawNorm - 0.5) * spreadLin
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

normModeName$ = "off (raw filter output)"
if normalise_partials = 1
    normModeName$ = "on (matched to source RMS)"
endif

# ============================================================
# INFO HEADER
# ============================================================

clearinfo
writeInfoLine:  "=================================================="
appendInfoLine: "  Undertone SR Reinterpretation v3.5"
appendInfoLine: "=================================================="
appendInfoLine: ""
appendInfoLine: "Source    : ", srcName$, "  (", fixed$(origDur, 3), " s  ", nCh, "ch)"
appendInfoLine: "Preset    : ", presetName$
appendInfoLine: "Fs        : ", origFs, " Hz"
appendInfoLine: "Undertones: ", number_of_undertones
appendInfoLine: "Series    : ", seriesModeName$
appendInfoLine: "Stretch   : ", fixed$(stretch_factor, 3)
appendInfoLine: "Gain curve: ", gainCurveName$,
    ... "  (balance only, depth=", fixed$(rolloff_dB, 1), " dB)"
appendInfoLine: "Field level: ", fixed$(field_level_dB, 1), " dB vs source RMS"
appendInfoLine: "Normalise : ", normModeName$
appendInfoLine: "Tilt      : ", fixed$(presence_tilt_dB, 1), " dB per octave down"
appendInfoLine: "Input trim: ", fixed$(input_gain_dB, 1), " dB"
appendInfoLine: "Spread    : ", fixed$(stereo_spread_pct, 0), " of full L-R"
appendInfoLine: "Low-pass  : ", fixed$(lowpass_Hz, 0), " Hz"
appendInfoLine: "Tail      : ", fixed$(tail_duration_s, 1), " s",
    ... "  (total: ", fixed$(totalDur, 2), " s)"
appendInfoLine: "Output    : STEREO (equal-power pan arc)"
if mute_input
    appendInfoLine: "Input     : MUTED (undertones only)"
endif
appendInfoLine: ""

pitchFactor# = zero#(number_of_undertones)
overrideSr#  = zero#(number_of_undertones)
denom#       = zero#(number_of_undertones)

# ── SERIES MODE: build denominator array ──────────────────────
# Integer:   denom(n) = (n+1)^(1+stretch)
# Odd:       denom(n) = (2n+1)^(1+stretch)
# Even:      denom(n) = (2n)^(1+stretch)
# Custom:    validated comma/semicolon/space separated positive values
# Geometric: denom(1)=2; ratio=1.25^(1+stretch)

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
pitchFactor#        = zero#(number_of_undertones)
overrideSr#         = zero#(number_of_undertones)
effectiveDenom#     = zero#(number_of_undertones)
semitonesDown#      = zero#(number_of_undertones)
octavesDown#        = zero#(number_of_undertones)
tiltDb#             = zero#(number_of_undertones)
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
    pitchFactor#[n]        = effectivePf
    effectiveDenom#[n]     = 1 / effectivePf
    overrideSr#[n]         = oSr
    octavesDown#[n]        = log2(1 / effectivePf)
    semitonesDown#[n]      = 12 * octavesDown#[n]
    tiltDb#[n]             = presence_tilt_dB * octavesDown#[n]
endfor

if srClampCount > 0
    appendInfoLine: "SR safety clamp affected ", srClampCount, " partial(s)."
    appendInfoLine: ""
endif

# ============================================================
# UNDERTONE GENERATION LOOP
# ============================================================

appendInfoLine: "Generating undertones..."
appendInfoLine: ""

# Original at centre: gainL = gainR = 1/sqrt(2), times the input trim.
origCentreGain = (1 / sqrt(2)) * 10 ^ (input_gain_dB / 20)

# The undertone bed is accumulated into its OWN pair of buffers so that the
# whole field can be levelled against the source in one step after the loop.
# The dry original is added last, at its own trim.
Create Sound from formula: "UT_L", 1, 0, totalDur, origFs, "0"
leftBuf = selected("Sound")

Create Sound from formula: "UT_R", 1, 0, totalDur, origFs, "0"
rightBuf = selected("Sound")

# Every partial must end up with EXACTLY this many samples, because the
# accumulation formulas below address the buffers by sample index.
selectObject: leftBuf
targetN = Get number of samples

if mute_input = 1
    appendInfoLine: "Input MUTED — undertones only"
    appendInfoLine: ""
endif

# Presence-chain bookkeeping, used by the report and the visualization.
normDb#     = zero#(number_of_undertones)
appliedDb#  = zero#(number_of_undertones)
partDbRel#  = zero#(number_of_undertones)
rawWinDb#   = zero#(number_of_undertones)
partBandHz# = zero#(number_of_undertones)
normClampCount = 0

normMaxLin = 10 ^ (18 / 20)
normMinLin = 10 ^ (-18 / 20)

for n from 1 to number_of_undertones

    pf  = pitchFactor#[n]
    oSr = overrideSr#[n]

    # Step 1: Duplicate mono working copy
    selectObject: monoSrc
    workCopy = Copy: "UT_work"

    # Step 2: Override SR — reinterpret samples at lower clock rate
    selectObject: workCopy
    Override sampling frequency: oSr

    # Step 3: Resample back to origFs (50-point sinc interpolation)
    selectObject: workCopy
    resampledID = Resample: origFs, 50
    removeObject: workCopy

    # Step 4: Trim/pad to exactly targetN samples (undertones ring into the
    # tail region). Compared in SAMPLES, not seconds: a partial whose
    # resampled length lands exactly on totalDur used to fall into the pad
    # branch and ask for a zero-duration Sound, which Praat rejects.
    selectObject: resampledID
    nRes = Get number of samples

    if nRes > targetN
        trimmedID = Extract part: 0, totalDur, "rectangular", 1, "no"
        removeObject: resampledID
    elsif nRes < targetN
        padDur = (targetN - nRes) / origFs
        Create Sound from formula: "UT_pad", 1, 0, padDur, origFs, "0"
        padID = selected("Sound")
        selectObject: resampledID
        plusObject: padID
        trimmedID = Concatenate
        removeObject: resampledID, padID
    else
        trimmedID = resampledID
    endif

    # Step 5: Low-pass filter (tonal shaping of the transposed material)
    selectObject: trimmedID
    filteredID = Filter (pass Hann band): 0, lowpass_Hz, 100
    removeObject: trimmedID

    # Effective bandwidth of this partial: the transposed material only
    # reaches oSr/2, so the filter can only ever narrow that further.
    partBandHz#[n] = min(lowpass_Hz, oSr / 2)

    # Step 5b: measure the partial over its ACTIVE region only.
    # The buffer is padded to totalDur; averaging over the silence would
    # under-read the level by a factor that depends on the tail length.
    partActive = origDur / pf
    if partActive > totalDur
        partActive = totalDur
    endif

    selectObject: filteredID
    partRms = Get root-mean-square: 0, partActive
    if partRms = undefined
        partRms = 0
    endif

    # Same partial measured over the SOURCE window, before any gain is
    # applied. This is the "what v3.4 would have produced" reference the
    # level-balance panel marks with a tick.
    selectObject: filteredID
    rawWinRms = Get root-mean-square: 0, origDur
    if rawWinRms = undefined or rawWinRms <= 1e-12
        rawWinDb#[n] = -120
    else
        rawWinDb#[n] = 20 * log10(rawWinRms / srcRms)
    endif

    # Step 5c: PRESENCE CHAIN — RMS match, then loudness tilt.
    normK = 1
    if normalise_partials = 1
        if partRms > 1e-7
            normK = srcRms / partRms
        endif
        if normK > normMaxLin
            normK = normMaxLin
            normClampCount += 1
        elsif normK < normMinLin
            normK = normMinLin
            normClampCount += 1
        endif
    endif
    normDb#[n] = 20 * log10(normK)

    tiltLin = 10 ^ (tiltDb#[n] / 20)

    appliedLin   = gainWeight#[n] * normK * tiltLin
    appliedDb#[n] = 20 * log10(appliedLin)

    # Step 6: Apply the whole chain in one pass
    selectObject: filteredID
    Formula: "self * " + fixed$(appliedLin, 8)

    # Step 6b: measure what actually came out, over the SOURCE window so the
    # per-partial numbers and the bed number below are directly comparable.
    selectObject: filteredID
    partRmsOut = Get root-mean-square: 0, origDur
    if partRmsOut = undefined or partRmsOut <= 1e-12
        partDbRel#[n] = -120
    else
        partDbRel#[n] = 20 * log10(partRmsOut / srcRms)
    endif

    # Step 6c: Micro-delay decorrelation
    # Each partial gets a tiny independent delay (0..N * micro_delay_ms).
    if micro_delay_ms > 0.0001
        delayDur = (n - 1) * micro_delay_ms / 1000
        if delayDur >= 1 / origFs
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

            selectObject: delayedID
            nDel = Get number of samples
            if nDel > targetN
                trimDelID = Extract part: 0, totalDur, "rectangular", 1, "no"
                removeObject: delayedID
                filteredID = trimDelID
            else
                filteredID = delayedID
            endif
        endif
    endif

    # Step 7: Accumulate into L and R buffers using equal-power pan
    filtID$ = string$(filteredID)
    gL$ = fixed$(panGainL#[n], 8)
    gR$ = fixed$(panGainR#[n], 8)

    selectObject: leftBuf
    Formula: "self + object[" + filtID$ + ", 1, col] * " + gL$

    selectObject: rightBuf
    Formula: "self + object[" + filtID$ + ", 1, col] * " + gR$

    removeObject: filteredID

endfor

# ============================================================
# FIELD LEVEL — level the whole bed against the source
# ============================================================
# The gain curve fixes the balance BETWEEN partials; this step fixes the
# level OF the bed. Measured rather than predicted, because the partials
# share a source and therefore add partly coherently.

selectObject: leftBuf
bedRmsL = Get root-mean-square: 0, origDur
selectObject: rightBuf
bedRmsR = Get root-mean-square: 0, origDur
if bedRmsL = undefined
    bedRmsL = 0
endif
if bedRmsR = undefined
    bedRmsR = 0
endif

bedMeasure = sqrt(bedRmsL ^ 2 + bedRmsR ^ 2)
fieldOffsetDb = 0
fieldClamped = 0
if bedMeasure > 1e-9
    measuredBedDb = 20 * log10(bedMeasure / srcRms)
    fieldOffsetDb = field_level_dB - measuredBedDb
    if fieldOffsetDb > 60
        fieldOffsetDb = 60
        fieldClamped = 1
    elsif fieldOffsetDb < -60
        fieldOffsetDb = -60
        fieldClamped = 1
    endif
else
    measuredBedDb = -120
endif

fieldOffsetLin = 10 ^ (fieldOffsetDb / 20)
fieldStr$ = fixed$(fieldOffsetLin, 8)

selectObject: leftBuf
Formula: "self * " + fieldStr$
selectObject: rightBuf
Formula: "self * " + fieldStr$

for n from 1 to number_of_undertones
    partDbRel#[n] = partDbRel#[n] + fieldOffsetDb
    appliedDb#[n] = appliedDb#[n] + fieldOffsetDb
    rawWinDb#[n]  = rawWinDb#[n] + fieldOffsetDb + gainDb#[n]
endfor

bedDb = measuredBedDb + fieldOffsetDb

# ============================================================
# DRY ORIGINAL — added last, at its own trim, panned centre
# ============================================================

if mute_input = 0
    monoStr$  = string$(monoSrc)
    origGStr$ = fixed$(origCentreGain, 8)

    selectObject: leftBuf
    Formula (part): 0, origDur, 1, 1,
        ... "self + object[" + monoStr$ + ", 1, col] * " + origGStr$

    selectObject: rightBuf
    Formula (part): 0, origDur, 1, 1,
        ... "self + object[" + monoStr$ + ", 1, col] * " + origGStr$
endif

# ── Presence report table ─────────────────────────────────────
appendInfoLine: "n   1/denom    st down   Fs      curve dB   norm dB   tilt dB   field dB   -> out dB   panL   panR"
appendInfoLine: "--------------------------------------------------------------------------------------------------"
for n from 1 to number_of_undertones
    @padL: fixed$(effectiveDenom#[n], 3), 8
    c1$ = padL$
    @padL: fixed$(semitonesDown#[n], 1), 8
    c2$ = padL$
    @padL: string$(overrideSr#[n]), 7
    c3$ = padL$
    @padL: fixed$(gainDb#[n], 1), 8
    c4$ = padL$
    @padL: fixed$(normDb#[n], 1), 9
    c5$ = padL$
    @padL: fixed$(tiltDb#[n], 1), 9
    c6$ = padL$
    @padL: fixed$(fieldOffsetDb, 1), 10
    c7$ = padL$
    @padL: fixed$(partDbRel#[n], 1), 11
    c8$ = padL$
    appendInfoLine: n, " 1/", c1$, c2$, c3$, c4$, c5$, c6$, c7$, "  ", c8$,
        ... "   ", fixed$(panGainL#[n], 2), "   ", fixed$(panGainR#[n], 2)
endfor

if normClampCount > 0
    appendInfoLine: "Normalisation clamped at +/-18 dB on ", normClampCount, " partial(s)."
endif

if fieldClamped = 1
    appendInfoLine: "Field level offset clamped at +/-60 dB; bed did not reach the target."
endif
appendInfoLine: ""
appendInfoLine: "Undertone bed, measured: ", fixed$(bedDb, 1),
    ... " dB relative to source RMS  (target ", fixed$(field_level_dB, 1), ")"
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
peakScaleDb = 0
if peakVal > 0.99
    Scale peak: 0.99
    peakScaleDb = 20 * log10(0.99 / peakVal)
    peakSafetyApplied = 1
    appendInfoLine: "Peak safety: attenuated by ", fixed$(peakScaleDb, 1),
        ... " dB (input peak was ", fixed$(peakVal, 3), ")"
endif

# Apply exponential fade-out over the tail region
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

    # ---- Picture-safe copies of machine-generated names ----
    @vizSafe: srcName$
    srcLabel$ = vizSafe$
    @vizSafe: outputName$
    outLabel$ = vizSafe$

    # ---- Palette ----
    bgCol$    = "{0.970, 0.970, 0.970}"
    gridCol$  = "{0.860, 0.860, 0.880}"
    axisCol$  = "{0.200, 0.200, 0.280}"
    dimCol$   = "{0.480, 0.480, 0.550}"
    inCol$    = "{0.420, 0.480, 0.580}"
    outCol$   = "{0.180, 0.280, 0.640}"
    addCol$   = "{0.960, 0.820, 0.560}"
    leftCol$  = "{0.250, 0.420, 0.720}"
    rightCol$ = "{0.820, 0.450, 0.180}"
    srcCol$   = "{0.900, 0.650, 0.150}"
    markCol$  = "{0.800, 0.400, 0.200}"
    panelBg$  = "{0.940, 0.940, 0.940}"

    # ---- Layout (8 inch wide canvas) ----
    vL = 0.60
    vR = 7.70
    halfL1 = 0.60
    halfR1 = 3.85
    halfL2 = 4.45
    railX  = -0.035
    halfR2 = 7.70
    pageHeight = 6.50

    # ---- Mono, time-aligned copies for drawing and analysis ----
    selectObject: srcID
    if nCh > 1
        vizMonoIn = Convert to mono
    else
        vizMonoIn = Copy: "UT_vizsrc"
    endif
    selectObject: vizMonoIn
    vizXmin = Get start time
    if abs(vizXmin) > 1e-12
        Shift times by: -vizXmin
    endif

    Create Sound from formula: "UT_vizin", 1, 0, mixDur, origFs, "0"
    vizIn = selected("Sound")
    Formula: "object(" + string$(vizMonoIn) + ", x)"

    selectObject: mixID
    vizMonoOut = Convert to mono

    selectObject: mixID
    vizL = Extract one channel: 1
    selectObject: mixID
    vizR = Extract one channel: 2

    selectObject: srcID
    srcPeak = Get absolute extremum: 0, 0, "None"
    selectObject: mixID
    mixPeak = Get absolute extremum: 0, 0, "None"

    ampBase = max(srcPeak, mixPeak)
    if ampBase < 0.001
        ampBase = 0.001
    endif
    ampMax = ampBase * 1.15

    # Round time-axis tick step to 1/2/5 x 10^k
    tickRaw = mixDur / 8
    tickPow = 10 ^ floor(log10(tickRaw))
    tickNorm = tickRaw / tickPow
    if tickNorm < 1.5
        tickStep = 1 * tickPow
    elsif tickNorm < 3.5
        tickStep = 2 * tickPow
    elsif tickNorm < 7.5
        tickStep = 5 * tickPow
    else
        tickStep = 10 * tickPow
    endif

    Erase all
    Line width: 1
    Solid line

    # ==========================================================
    # TITLE
    # ==========================================================
    Font size: 13
    Select inner viewport: vL, vR, 0.10, 0.30
    Axes: 0, 1, 0, 1
    Colour: "{0.100, 0.100, 0.160}"
    Text: 0.5, "centre", 0.5, "half", "##Undertone Field — SR Reinterpretation v3.5##"

    Font size: 7
    Select inner viewport: vL, vR, 0.32, 0.46
    Axes: 0, 1, 0, 1
    Colour: "{0.350, 0.350, 0.450}"
    Text: 0.5, "centre", 0.5, "half",
        ... "[" + presetName$ + "]  " + srcLabel$
        ... + "   N=" + string$(number_of_undertones)
        ... + "   " + seriesModeName$
        ... + "   stretch=" + fixed$(stretch_factor, 2)
        ... + "   " + gainCurveName$
        ... + "  depth=" + fixed$(rolloff_dB, 1) + "dB"
        ... + "   field=" + fixed$(field_level_dB, 1) + "dB"
        ... + "   tilt=" + fixed$(presence_tilt_dB, 1) + "dB/oct"
        ... + "   LP=" + fixed$(lowpass_Hz, 0) + "Hz"
        ... + "   tail=" + fixed$(tail_duration_s, 1) + "s"

    # ==========================================================
    # PANEL 1 — Input waveform (shares the output time axis)
    # ==========================================================
    p1T = 0.66
    p1B = 1.22

    Font size: 6
    Select inner viewport: vL, vR, p1T, p1B
    Axes: 0, mixDur, -ampMax, ampMax
    Paint rectangle: bgCol$, 0, mixDur, -ampMax, ampMax

    Select inner viewport: vL, vR, p1T, p1B
    Axes: 0, mixDur, -ampMax, ampMax
    selectObject: vizIn
    Colour: inCol$
    Draw: 0, mixDur, -ampMax, ampMax, "no", "Curve"

    Select inner viewport: vL, vR, p1T, p1B
    Axes: 0, mixDur, -ampMax, ampMax
    Colour: gridCol$
    Draw line: 0, 0, mixDur, 0

    Select inner viewport: vL, vR, p1T, p1B
    Axes: 0, 1, 0, 1
    Colour: dimCol$
    Text special: railX, "centre", 0.5, "bottom", "Helvetica", 6, "90", "Input"

    Select inner viewport: vL, vR, p1T, p1B
    Axes: 0, mixDur, -ampMax, ampMax
    Colour: "Black"
    Draw inner box

    Select inner viewport: vL, vR, p1T, p1B
    Axes: 0, 1, 0, 1
    Colour: axisCol$
    Text top: "no", "##Input## — " + srcLabel$ + "   (drawn on the output time axis)"

    # ==========================================================
    # PANEL 2 — Output, L and R as separate tracks
    # ==========================================================
    p2aT = 1.50
    p2aB = 1.88
    p2bT = 1.90
    p2bB = 2.28

    # --- L track ---
    Font size: 6
    Select inner viewport: vL, vR, p2aT, p2aB
    Axes: 0, mixDur, -ampMax, ampMax
    Paint rectangle: bgCol$, 0, mixDur, -ampMax, ampMax

    Select inner viewport: vL, vR, p2aT, p2aB
    Axes: 0, mixDur, -ampMax, ampMax
    selectObject: vizL
    Colour: leftCol$
    Draw: 0, mixDur, -ampMax, ampMax, "no", "Curve"

    Select inner viewport: vL, vR, p2aT, p2aB
    Axes: 0, mixDur, -ampMax, ampMax
    Colour: gridCol$
    Draw line: 0, 0, mixDur, 0
    if tail_duration_s > 0.01
        Colour: markCol$
        Dashed line
        Draw line: origDur, -ampMax, origDur, ampMax
        Solid line
    endif

    Select inner viewport: vL, vR, p2aT, p2aB
    Axes: 0, 1, 0, 1
    Colour: leftCol$
    Text special: railX, "centre", 0.5, "bottom", "Helvetica", 6, "90", "L"
    if tail_duration_s > 0.01
        Select inner viewport: vL, vR, p2aT, p2aB
        Axes: 0, mixDur, -ampMax, ampMax
        Colour: markCol$
        Text: origDur, "left", ampMax * 0.66, "half", " tail"
    endif

    Select inner viewport: vL, vR, p2aT, p2aB
    Axes: 0, mixDur, -ampMax, ampMax
    Colour: "Black"
    Draw inner box

    Select inner viewport: vL, vR, p2aT, p2aB
    Axes: 0, 1, 0, 1
    Colour: axisCol$
    Text top: "no", "##Output## — " + outLabel$ + "   (time in seconds)"

    # --- R track ---
    Font size: 6
    Select inner viewport: vL, vR, p2bT, p2bB
    Axes: 0, mixDur, -ampMax, ampMax
    Paint rectangle: bgCol$, 0, mixDur, -ampMax, ampMax

    Select inner viewport: vL, vR, p2bT, p2bB
    Axes: 0, mixDur, -ampMax, ampMax
    selectObject: vizR
    Colour: rightCol$
    Draw: 0, mixDur, -ampMax, ampMax, "no", "Curve"

    Select inner viewport: vL, vR, p2bT, p2bB
    Axes: 0, mixDur, -ampMax, ampMax
    Colour: gridCol$
    Draw line: 0, 0, mixDur, 0
    if tail_duration_s > 0.01
        Colour: markCol$
        Dashed line
        Draw line: origDur, -ampMax, origDur, ampMax
        Solid line
    endif

    Select inner viewport: vL, vR, p2bT, p2bB
    Axes: 0, 1, 0, 1
    Colour: rightCol$
    Text special: railX, "centre", 0.5, "bottom", "Helvetica", 6, "90", "R"

    Select inner viewport: vL, vR, p2bT, p2bB
    Axes: 0, mixDur, -ampMax, ampMax
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, tickStep, "yes", "yes", "no"

    # ==========================================================
    # PANEL 3 — Spectral balance (LTAS, log frequency)
    # ==========================================================
    p3T = 2.78
    p3B = 3.82

    # vizIn is the input padded to the output duration, so both long-term
    # averages span the same window. Using the unpadded input here would
    # make the output look quieter by exactly the tail's share of the file.
    selectObject: vizIn
    ltasIn = To Ltas: 40
    selectObject: vizMonoOut
    ltasOut = To Ltas: 40

    selectObject: vizMonoIn
    vizSpec = To Spectrum: "yes"
    selectObject: vizSpec
    cogIn = Get centre of gravity: 2
    removeObject: vizSpec
    if cogIn = undefined or cogIn <= 0
        cogIn = 500
    endif

    fLo = 30
    fHi = origFs / 2
    if fHi > 12000
        fHi = 12000
    endif
    logLo = log10(fLo)
    logHi = log10(fHi)

    nSpecPts = 220
    ltasLogF# = zero#(nSpecPts)
    ltasIdb#  = zero#(nSpecPts)
    ltasOdb#  = zero#(nSpecPts)

    specTop = -400
    for k from 1 to nSpecPts
        lf = logLo + (k - 1) / (nSpecPts - 1) * (logHi - logLo)
        fq = 10 ^ lf
        ltasLogF#[k] = lf

        selectObject: ltasIn
        vi = Get value at frequency: fq, "Cubic"
        if vi = undefined
            vi = -200
        endif
        selectObject: ltasOut
        vo = Get value at frequency: fq, "Cubic"
        if vo = undefined
            vo = -200
        endif

        ltasIdb#[k] = vi
        ltasOdb#[k] = vo
        if vi > specTop
            specTop = vi
        endif
        if vo > specTop
            specTop = vo
        endif
    endfor

    removeObject: ltasIn, ltasOut

    gMax = 10 * ceiling(specTop / 10) + 5
    gMin = gMax - 75

    Font size: 6
    Select inner viewport: vL, vR, p3T, p3B
    Axes: logLo, logHi, gMin, gMax
    Paint rectangle: bgCol$, logLo, logHi, gMin, gMax

    # Shaded region: energy the undertone field adds over the input
    Select inner viewport: vL, vR, p3T, p3B
    Axes: logLo, logHi, gMin, gMax
    for k from 2 to nSpecPts
        yi = (ltasIdb#[k - 1] + ltasIdb#[k]) / 2
        yo = (ltasOdb#[k - 1] + ltasOdb#[k]) / 2
        if yi < gMin
            yi = gMin
        endif
        if yi > gMax
            yi = gMax
        endif
        if yo < gMin
            yo = gMin
        endif
        if yo > gMax
            yo = gMax
        endif
        if yo > yi + 0.05
            Paint rectangle: addCol$, ltasLogF#[k - 1], ltasLogF#[k], yi, yo
        elsif yi > yo + 0.05
            Paint rectangle: "{0.800, 0.820, 0.870}",
                ... ltasLogF#[k - 1], ltasLogF#[k], yo, yi
        endif
    endfor

    # Input curve
    Select inner viewport: vL, vR, p3T, p3B
    Axes: logLo, logHi, gMin, gMax
    Colour: inCol$
    Line width: 1
    for k from 2 to nSpecPts
        ya = ltasIdb#[k - 1]
        yb = ltasIdb#[k]
        if ya < gMin
            ya = gMin
        endif
        if ya > gMax
            ya = gMax
        endif
        if yb < gMin
            yb = gMin
        endif
        if yb > gMax
            yb = gMax
        endif
        Draw line: ltasLogF#[k - 1], ya, ltasLogF#[k], yb
    endfor

    # Output curve
    Select inner viewport: vL, vR, p3T, p3B
    Axes: logLo, logHi, gMin, gMax
    Colour: outCol$
    Line width: 1.5
    for k from 2 to nSpecPts
        ya = ltasOdb#[k - 1]
        yb = ltasOdb#[k]
        if ya < gMin
            ya = gMin
        endif
        if ya > gMax
            ya = gMax
        endif
        if yb < gMin
            yb = gMin
        endif
        if yb > gMax
            yb = gMax
        endif
        Draw line: ltasLogF#[k - 1], ya, ltasLogF#[k], yb
    endfor
    Line width: 1

    # Low-pass corner
    Select inner viewport: vL, vR, p3T, p3B
    Axes: logLo, logHi, gMin, gMax
    if lowpass_Hz > fLo and lowpass_Hz < fHi
        Colour: markCol$
        Dashed line
        Draw line: log10(lowpass_Hz), gMin, log10(lowpass_Hz), gMax
        Solid line
    endif

    # Register stubs: where the source centroid lands for each partial
    Select inner viewport: vL, vR, p3T, p3B
    Axes: logLo, logHi, gMin, gMax
    stubTop = gMin + (gMax - gMin) * 0.14
    Line width: 2
    for n from 1 to number_of_undertones
        cFrac = (n - 1) / max(number_of_undertones - 1, 1)
        cR = 0.85 - cFrac * 0.70
        cG = 0.30 - cFrac * 0.05
        cB = 0.15 + cFrac * 0.50
        fPart = cogIn * pitchFactor#[n]
        if fPart > fLo and fPart < fHi
            Colour: "{" + fixed$(cR, 3) + ", " + fixed$(cG, 3) + ", " + fixed$(cB, 3) + "}"
            Draw line: log10(fPart), gMin, log10(fPart), stubTop
        endif
    endfor
    Line width: 1

    # Source centroid
    Select inner viewport: vL, vR, p3T, p3B
    Axes: logLo, logHi, gMin, gMax
    if cogIn > fLo and cogIn < fHi
        Colour: srcCol$
        Line width: 2
        Draw line: log10(cogIn), gMin, log10(cogIn), stubTop
        Line width: 1
    endif

    Select inner viewport: vL, vR, p3T, p3B
    Axes: logLo, logHi, gMin, gMax
    Colour: "Black"
    Draw inner box
    Marks left every: 1, 15, "yes", "yes", "no"

    Select inner viewport: vL, vR, p3T, p3B
    Axes: logLo, logHi, gMin, gMax
    if fLo <= 50 and fHi >= 50
        One mark bottom: log10(50), "no", "yes", "no", "50"
    endif
    One mark bottom: log10(100), "no", "yes", "no", "100"
    One mark bottom: log10(200), "no", "yes", "no", "200"
    One mark bottom: log10(500), "no", "yes", "no", "500"
    One mark bottom: log10(1000), "no", "yes", "no", "1k"
    One mark bottom: log10(2000), "no", "yes", "no", "2k"
    if fHi >= 5000
        One mark bottom: log10(5000), "no", "yes", "no", "5k"
    endif
    if fHi >= 10000
        One mark bottom: log10(10000), "no", "yes", "no", "10k"
    endif

    # Legend
    Select inner viewport: vL, vR, p3T, p3B
    Axes: 0, 1, 0, 1
    legY = 0.94
    Colour: inCol$
    Text: 0.700, "left", legY, "half", "input"
    Select inner viewport: vL, vR, p3T, p3B
    Axes: 0, 1, 0, 1
    Colour: outCol$
    Text: 0.775, "left", legY, "half", "output"
    Select inner viewport: vL, vR, p3T, p3B
    Axes: 0, 1, 0, 1
    Colour: "{0.700, 0.560, 0.300}"
    Text: 0.865, "left", legY, "half", "added"
    Select inner viewport: vL, vR, p3T, p3B
    Axes: 0, 1, 0, 1
    Colour: markCol$
    Text: 0.945, "left", legY, "half", "LP"

    Select inner viewport: vL, vR, p3T, p3B
    Axes: 0, 1, 0, 1
    Colour: axisCol$
    Text top: "no",
        ... "##Spectral balance## — long-term average spectrum, dB vs frequency (Hz, log)"
        ... + "   stubs = source centroid transposed per partial"

    # ==========================================================
    # PANEL 4 — Level balance (measured, relative to source RMS)
    # ==========================================================
    p4T = 4.36
    p4B = 5.40

    dbLo = 0
    dbHi = 3
    for n from 1 to number_of_undertones
        if partDbRel#[n] < dbLo
            dbLo = partDbRel#[n]
        endif
        if rawWinDb#[n] < dbLo
            dbLo = rawWinDb#[n]
        endif
        if partDbRel#[n] + 3 > dbHi
            dbHi = partDbRel#[n] + 3
        endif
    endfor
    dbLo = 5 * floor(dbLo / 5) - 3
    if dbLo < -60
        dbLo = -60
    endif
    dbHi = 5 * ceiling(dbHi / 5)
    dbTick = 10
    if dbHi - dbLo <= 25
        dbTick = 5
    endif

    rowTop = 0.35
    rowBot = number_of_undertones + 0.65

    Font size: 6
    Select inner viewport: halfL1, halfR1, p4T, p4B
    Axes: dbLo, dbHi, rowBot, rowTop
    Paint rectangle: bgCol$, dbLo, dbHi, rowBot, rowTop

    # Bars: achieved level per partial
    Select inner viewport: halfL1, halfR1, p4T, p4B
    Axes: dbLo, dbHi, rowBot, rowTop
    for n from 1 to number_of_undertones
        cFrac = (n - 1) / max(number_of_undertones - 1, 1)
        cR = 0.85 - cFrac * 0.70
        cG = 0.30 - cFrac * 0.05
        cB = 0.15 + cFrac * 0.50
        barCol$ = "{" + fixed$(cR, 3) + ", " + fixed$(cG, 3) + ", " + fixed$(cB, 3) + "}"
        bv = partDbRel#[n]
        if bv < dbLo
            bv = dbLo
        endif
        if bv > dbHi
            bv = dbHi
        endif
        Paint rectangle: barCol$, dbLo, bv, n - 0.32, n + 0.32
    endfor

    # Tick: where this partial would have landed WITHOUT normalisation and
    # tilt, at the same field level. The gap between tick and bar end is
    # exactly what the presence chain contributed.
    Select inner viewport: halfL1, halfR1, p4T, p4B
    Axes: dbLo, dbHi, rowBot, rowTop
    Colour: "{0.150, 0.150, 0.200}"
    Line width: 1.5
    for n from 1 to number_of_undertones
        rv = rawWinDb#[n]
        if rv >= dbLo and rv <= dbHi
            Draw line: rv, n - 0.34, rv, n + 0.34
        endif
    endfor
    Line width: 1

    # Source reference at 0 dB
    Select inner viewport: halfL1, halfR1, p4T, p4B
    Axes: dbLo, dbHi, rowBot, rowTop
    Colour: srcCol$
    Dashed line
    Line width: 1.5
    Draw line: 0, rowBot, 0, rowTop
    Line width: 1
    Solid line

    Select inner viewport: halfL1, halfR1, p4T, p4B
    Axes: dbLo, dbHi, rowBot, rowTop
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, dbTick, "yes", "yes", "no"

    # Row labels
    for n from 1 to number_of_undertones
        Select inner viewport: halfL1, halfR1, p4T, p4B
        Axes: dbLo, dbHi, rowBot, rowTop
        Colour: "{1.000, 1.000, 1.000}"
        Text: dbLo + (dbHi - dbLo) * 0.02, "left", n, "half",
            ... "1/" + fixed$(effectiveDenom#[n], 2)
        Select inner viewport: halfL1, halfR1, p4T, p4B
        Axes: dbLo, dbHi, rowBot, rowTop
        Colour: axisCol$
        bv = partDbRel#[n]
        if bv < dbLo
            bv = dbLo
        endif
        if bv > dbHi
            bv = dbHi
        endif
        if bv > dbLo + (dbHi - dbLo) * 0.84
            Text: bv - (dbHi - dbLo) * 0.02, "right", n, "half", fixed$(partDbRel#[n], 1)
        else
            Text: bv + (dbHi - dbLo) * 0.02, "left", n, "half", fixed$(partDbRel#[n], 1)
        endif
    endfor

    Select inner viewport: halfL1, halfR1, p4T, p4B
    Axes: 0, 1, 0, 1
    Colour: srcCol$
    Text: 0.985, "right", 0.05, "half", "0 dB = source"
    Select inner viewport: halfL1, halfR1, p4T, p4B
    Axes: 0, 1, 0, 1
    Colour: axisCol$
    Text top: "no", "##Level balance## — measured dB vs source RMS  (tick = before presence chain)"

    # ==========================================================
    # PANEL 5 — Stereo field (angle = pan, radius = level)
    # ==========================================================
    Font size: 6
    Select inner viewport: halfL2, halfR2, p4T, p4B
    Axes: -1.35, 1.35, -0.20, 1.30
    Paint rectangle: bgCol$, -1.35, 1.35, -0.20, 1.30

    # Reference arcs: unit = source level, inner dashed = -12 dB
    rInnerDb = -12
    rInner = (rInnerDb + 36) / 36
    if rInner < 0.1
        rInner = 0.1
    endif

    Select inner viewport: halfL2, halfR2, p4T, p4B
    Axes: -1.35, 1.35, -0.20, 1.30
    nArcPts = 48
    Colour: "{0.720, 0.720, 0.780}"
    Line width: 1
    for ai from 2 to nArcPts
        a1 = (ai - 2) / (nArcPts - 1) * pi
        a2 = (ai - 1) / (nArcPts - 1) * pi
        Draw line: -cos(a1), sin(a1), -cos(a2), sin(a2)
    endfor
    Colour: "{0.840, 0.840, 0.880}"
    Dotted line
    for ai from 2 to nArcPts
        a1 = (ai - 2) / (nArcPts - 1) * pi
        a2 = (ai - 1) / (nArcPts - 1) * pi
        Draw line: -cos(a1) * rInner, sin(a1) * rInner, -cos(a2) * rInner, sin(a2) * rInner
    endfor
    Solid line

    # Radial guides
    Select inner viewport: halfL2, halfR2, p4T, p4B
    Axes: -1.35, 1.35, -0.20, 1.30
    Colour: "{0.890, 0.890, 0.910}"
    for n from 1 to number_of_undertones
        aa = panAngle#[n] * pi
        Draw line: 0, 0, -cos(aa) * 1.05, sin(aa) * 1.05
    endfor

    # Source at centre top
    Select inner viewport: halfL2, halfR2, p4T, p4B
    Axes: -1.35, 1.35, -0.20, 1.30
    Colour: srcCol$
    Paint circle (mm): srcCol$, 0.0, 1.0, 1.6

    # Partial dots: angle = pan, radius = measured level
    Select inner viewport: halfL2, halfR2, p4T, p4B
    Axes: -1.35, 1.35, -0.20, 1.30
    for n from 1 to number_of_undertones
        aa = panAngle#[n] * pi
        rn = (partDbRel#[n] + 36) / 36
        if rn < 0.12
            rn = 0.12
        endif
        if rn > 1.22
            rn = 1.22
        endif
        xp = -cos(aa) * rn
        yp = sin(aa) * rn

        cFrac = (n - 1) / max(number_of_undertones - 1, 1)
        cR = 0.85 - cFrac * 0.70
        cG = 0.30 - cFrac * 0.05
        cB = 0.15 + cFrac * 0.50
        dotCol$ = "{" + fixed$(cR, 3) + ", " + fixed$(cG, 3) + ", " + fixed$(cB, 3) + "}"

        Colour: dotCol$
        Draw line: 0, 0, xp, yp
        Paint circle (mm): dotCol$, xp, yp, 1.5
    endfor

    Select inner viewport: halfL2, halfR2, p4T, p4B
    Axes: -1.35, 1.35, -0.20, 1.30
    Colour: "Black"
    Draw inner box

    # Labels
    Select inner viewport: halfL2, halfR2, p4T, p4B
    Axes: -1.35, 1.35, -0.20, 1.30
    Colour: dimCol$
    Text: -1.30, "left", 0.09, "half", "L"
    Select inner viewport: halfL2, halfR2, p4T, p4B
    Axes: -1.35, 1.35, -0.20, 1.30
    Colour: dimCol$
    Text: 1.30, "right", 0.09, "half", "R"
    Select inner viewport: halfL2, halfR2, p4T, p4B
    Axes: -1.35, 1.35, -0.20, 1.30
    Colour: dimCol$
    Text: 0, "centre", 1.24, "half", "C"
    Select inner viewport: halfL2, halfR2, p4T, p4B
    Axes: -1.35, 1.35, -0.20, 1.30
    Colour: srcCol$
    Text: 0, "centre", 1.12, "half", "orig"

    for n from 1 to number_of_undertones
        Select inner viewport: halfL2, halfR2, p4T, p4B
        Axes: -1.35, 1.35, -0.20, 1.30
        aa = panAngle#[n] * pi
        rn = (partDbRel#[n] + 36) / 36
        if rn < 0.12
            rn = 0.12
        endif
        if rn > 1.22
            rn = 1.22
        endif
        cFrac = (n - 1) / max(number_of_undertones - 1, 1)
        cR = 0.85 - cFrac * 0.70
        cG = 0.30 - cFrac * 0.05
        cB = 0.15 + cFrac * 0.50
        Colour: "{" + fixed$(cR * 0.55, 3) + ", " + fixed$(cG * 0.55, 3) + ", "
            ... + fixed$(cB * 0.55, 3) + "}"
        # Place the number just outside its own dot along the same radius.
        # Neighbouring partials differ in angle, so their labels separate
        # even when their levels are close.
        labR = rn
        if labR > 1.10
            labR = 1.10
        endif
        labR = labR + 0.13
        labX = -cos(aa) * labR
        labY = sin(aa) * labR
        # A centred partial would land under the source marker: shift it aside.
        if abs(labX) < 0.16 and labY > 0.70
            labX = labX - 0.18
        endif
        Text: labX, "centre", labY, "half", string$(n)
    endfor

    Select inner viewport: halfL2, halfR2, p4T, p4B
    Axes: 0, 1, 0, 1
    Colour: dimCol$
    Text: 0.5, "centre", 0.05, "half", "outer arc = source level, dotted ring = -12 dB"
    Select inner viewport: halfL2, halfR2, p4T, p4B
    Axes: 0, 1, 0, 1
    Colour: axisCol$
    Text top: "no", "##Stereo field## — angle = pan, radius = level  (spread "
        ... + fixed$(stereo_spread_pct, 0) + ")"

    # ==========================================================
    # SUMMARY STRIP
    # ==========================================================
    sT = 5.78
    sB = 6.34

    Font size: 7
    Select inner viewport: vL, vR, sT, sB
    Axes: 0, 1, 0, 1
    Paint rectangle: panelBg$, 0, 1, 0, 1

    Select inner viewport: vL, vR, sT, sB
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.012, "left", 0.80, "half", "##Summary##"

    partWord$ = "partials"
    if number_of_undertones = 1
        partWord$ = "partial"
    endif
    peakLine$ = "none"
    if peakSafetyApplied = 1
        peakLine$ = fixed$(peakScaleDb, 1) + " dB"
    endif
    fieldLine$ = fixed$(bedDb, 1) + " dB vs source RMS (target "
        ... + fixed$(field_level_dB, 1) + ")"

    Font size: 6
    Select inner viewport: vL, vR, sT, sB
    Axes: 0, 1, 0, 1
    Colour: "{0.250, 0.250, 0.350}"
    Text: 0.012, "left", 0.52, "half",
        ... "Undertone bed " + fieldLine$
        ... + "     normalisation " + normModeName$
        ... + "     tilt " + fixed$(presence_tilt_dB, 1) + " dB/oct"
        ... + "     input trim " + fixed$(input_gain_dB, 1) + " dB"
    Select inner viewport: vL, vR, sT, sB
    Axes: 0, 1, 0, 1
    Colour: "{0.250, 0.250, 0.350}"
    Text: 0.012, "left", 0.22, "half",
        ... "Peak-safety attenuation " + peakLine$
        ... + "     output " + fixed$(mixDur, 2) + " s stereo"
        ... + "     " + string$(number_of_undertones) + " " + partWord$ + ", "
        ... + seriesModeName$ + " series"
        ... + "     full parameter table in the Info window"

    Select inner viewport: vL, vR, sT, sB
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # ---- Clean up and restore the full-canvas viewport for export ----
    removeObject: vizIn, vizL, vizR, vizMonoIn, vizMonoOut

    Font size: 10
    Select outer viewport: 0, 8, 0, pageHeight
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
appendInfoLine: "Duration : ", fixed$(mixDur, 3), " s",
    ... "  (source: ", fixed$(origDur, 3), " + tail: ", fixed$(tail_duration_s, 1), ")"
appendInfoLine: "Preset   : ", presetName$
appendInfoLine: "Bed level: ", fixed$(bedDb, 1), " dB relative to source RMS"
appendInfoLine: "Peak safe: ", peakSafetyApplied
appendInfoLine: "Channels : 2  (original centre, undertones spread L->R)"
appendInfoLine: ""
appendInfoLine: "Objects: original + ", outputName$

selectObject: mixID

if play_result = 1
    Play
endif

# ============================================================
# HELPERS
# ============================================================

procedure padL: .s$, .w
    padL$ = .s$
    while length(padL$) < .w
        padL$ = " " + padL$
    endwhile
endproc

# Escape Picture-window markup in machine-generated names.
# Order matters: the replacements for #, % and ^ contain no underscore,
# so the underscore pass must run last.
procedure vizSafe: .s$
    vizSafe$ = replace$(.s$, "#", "\# ", 0)
    vizSafe$ = replace$(vizSafe$, "%", "\% ", 0)
    vizSafe$ = replace$(vizSafe$, "^", "\^ ", 0)
    vizSafe$ = replace$(vizSafe$, "_", "\_ ", 0)
endproc
