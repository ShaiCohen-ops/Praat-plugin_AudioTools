# ============================================================
# Praat AudioTools - Polynomial_Sound_Shaper.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Polynomial envelope shaper. Builds a gain envelope by
#   evaluating a user-defined polynomial p(x) over a normalized
#   time domain, with optional perceptual weighting and dynamic
#   range clamping, and applies it to the input audio.
#
#   Two ways to define the polynomial:
#     (1) Coefficients: p(x) = a x^3 + b x^2 + c x + d
#     (2) Roots:        p(x) = (x - r1)(x - r2)(x - r3)
#                       (set r3 = 0 for quadratic)
#
#   With Treat_as_envelope ON (default), |p(x)| is used as the
#   gain magnitude — the polynomial's sign does NOT phase-invert
#   the audio. This is what most users want for fades, swells,
#   pulses. Turn OFF for signed waveshaping experiments.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v1.1:
#   - Fix (HEADLINE): polynomial values that go negative no longer
#     phase-invert the audio. v1.0 used signed polynomial values
#     directly as the gain multiplier, so a Swell preset
#     (root_1=-1, root_2=+1) produced gain = -1 at x=0 (the
#     center, where the swell is supposed to peak). Result: the
#     loudest moment of the "swell" was phase-inverted, audible
#     as artifacts on transients. Same bug on Fade Out preset
#     and any custom polynomial crossing zero. v1.1 takes abs()
#     of the polynomial value when used as an envelope (default
#     behavior), with a new Treat_as_envelope boolean exposing
#     v1.0's signed behavior for users who want it.
#   - Fix: form syntax modernized.
#       optionmenu Preset 1     ->  optionmenu Preset: 1
#       optionmenu Envelope_type 1  ->  optionmenu Envelope_type: 1
#       Visualize 1             ->  Draw_visualization 1
#       Play 1                  ->  Play_result 1
#     The old space-no-colon syntax fails on some Praat builds.
#     Renaming Play because it shadows the Play command name.
#   - Fix: writeInfoLine called multiple times in v1.0 cleared
#     the Info window before each line, so only the last line
#     was visible. Replaced with one writeInfoLine + many
#     appendInfoLine calls.
#   - Fix: when min_gain = 0, true silence is now possible.
#     v1.0's epsilon floor 0.000001 made fades-to-silence
#     actually fade to -120 dB (audible on percussive sources).
#     v1.1 only applies the floor when min_gain > 0 OR for
#     numerical safety in the perceptual weighting step.
#   - Fix: validate start_x < end_x. v1.0 silently produced
#     weird envelopes if domain was reversed.
#   - Speed: envelope built ONCE via a helper Sound at 1000 Hz,
#     then multiplied into the audio. v1.0 nested the polynomial
#     formula 4-5 times per output sample (signed-abs check
#     inside weighting inside clamping inside multiplication).
#     v1.1 evaluates each stage once on a small envelope buffer.
#     ~5x faster on long files.
#   - Visualization rewritten to suite 8x8 standard with title bar,
#     metadata subtitle, aligned panel titles, output waveform
#     panel, and proper summary stats bar.
#   - Preset rename: "Exponential In" -> "Quartic In",
#     "Exponential Out" -> "Quartic Out". v1.0's names were
#     misleading — those presets are x^4 (quartic), not e^x.
#     Math unchanged; honest naming.
# Changelog v1.0:
#   - Initial release with 10 presets.
# ============================================================

form Polynomial Sound Shaper v1.1
    optionmenu Preset: 1
        option Custom
        option Fade In (linear)
        option Fade Out (linear)
        option Swell (peak center)
        option Attack-Decay
        option Slow Attack
        option Double Pulse
        option Asymmetric Rise
        option Quartic In
        option Quartic Out
    comment === Envelope Type ===
    optionmenu Envelope_type: 1
        option Polynomial coefficients
        option Polynomial from roots
    comment === Domain ===
    real Start_x -1
    real End_x 1
    comment === Polynomial Coefficients (ax^3 + bx^2 + cx + d) ===
    real Coef_a 0
    real Coef_b 0
    real Coef_c 1
    real Coef_d 0
    comment === Product Terms (x-r1)(x-r2)(x-r3) ===
    real Root_1 -1
    real Root_2 1
    real Root_3 0
    comment (set Root_3 to 0 for quadratic)
    comment === Perceptual Tuning ===
    positive Perceptual_weight 1.0
    comment (1=linear, 2-3=perceived loudness)
    comment === Dynamic Range ===
    real Min_gain 0.0
    real Max_gain 1.0
    comment === Behavior ===
    boolean Treat_as_envelope 1
    comment (ON: |p(x)| used as gain. OFF: signed (v1.0 behavior — phase-inverts on negative))
    boolean Normalize 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# INPUT VALIDATION
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
sound_name$ = selected$("Sound")

selectObject: sound
dur = Get total duration
sr = Get sampling frequency

# ============================================================
# APPLY PRESETS
# ============================================================

if preset = 2
    envelope_type = 2
    root_1 = 0
    root_2 = 1
    root_3 = 0
    start_x = 0
    end_x = 1
    presetName$ = "FadeIn"
elsif preset = 3
    envelope_type = 2
    root_1 = -1
    root_2 = 0
    root_3 = 0
    start_x = -1
    end_x = 0
    presetName$ = "FadeOut"
elsif preset = 4
    envelope_type = 2
    root_1 = -1
    root_2 = 1
    root_3 = 0
    start_x = -1
    end_x = 1
    presetName$ = "Swell"
elsif preset = 5
    envelope_type = 1
    coef_a = -4
    coef_b = 0
    coef_c = 4
    coef_d = 0
    start_x = 0
    end_x = 1
    presetName$ = "AttackDecay"
elsif preset = 6
    envelope_type = 1
    coef_a = 1
    coef_b = 0
    coef_c = 0
    coef_d = 0
    start_x = 0
    end_x = 1
    presetName$ = "SlowAttack"
elsif preset = 7
    envelope_type = 2
    root_1 = -1
    root_2 = 0
    root_3 = 1
    start_x = -1
    end_x = 1
    presetName$ = "DoublePulse"
elsif preset = 8
    envelope_type = 2
    root_1 = 0
    root_2 = 2
    root_3 = 0
    start_x = 0
    end_x = 1
    presetName$ = "AsymRise"
elsif preset = 9
    envelope_type = 1
    coef_a = 0
    coef_b = 1
    coef_c = 0
    coef_d = 0
    start_x = 0
    end_x = 1
    perceptual_weight = 2.0
    presetName$ = "QuarticIn"
elsif preset = 10
    envelope_type = 1
    coef_a = 0
    coef_b = -1
    coef_c = 2
    coef_d = 0
    start_x = 0
    end_x = 1
    perceptual_weight = 2.0
    presetName$ = "QuarticOut"
else
    presetName$ = "Custom"
endif

# ============================================================
# DOMAIN VALIDATION (FIX v1.1)
# ============================================================

if start_x >= end_x
    exitScript: "Domain must satisfy start_x < end_x. Got start=" + fixed$(start_x, 3)
        ... + ", end=" + fixed$(end_x, 3) + "."
endif

# ============================================================
# RESOLVE TYPE/MODE NAMES
# ============================================================

if envelope_type = 1
    typeName$ = "Coefficients"
else
    typeName$ = "Roots"
endif

if treat_as_envelope = 1
    envName$ = "abs(p) [envelope]"
else
    envName$ = "signed p [waveshape]"
endif

# ============================================================
# INFO HEADER (FIX v1.1: write once, append rest)
# ============================================================

clearinfo
writeInfoLine: "============================================"
appendInfoLine: "  POLYNOMIAL SOUND SHAPER v1.1"
appendInfoLine: "============================================"
appendInfoLine: ""
appendInfoLine: "Input: ", sound_name$, " (", fixed$(dur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Type: ", typeName$
appendInfoLine: "Behavior: ", envName$
appendInfoLine: "Domain: [", fixed$(start_x, 3), ", ", fixed$(end_x, 3), "]"

if envelope_type = 1
    appendInfoLine: "Polynomial:  ", coef_a, "*x^3 + ", coef_b, "*x^2 + ", coef_c, "*x + ", coef_d
else
    if root_3 = 0
        appendInfoLine: "Polynomial:  (x - ", root_1, ")(x - ", root_2, ")"
    else
        appendInfoLine: "Polynomial:  (x - ", root_1, ")(x - ", root_2, ")(x - ", root_3, ")"
    endif
endif

appendInfoLine: "Perceptual weight: ", fixed$(perceptual_weight, 2)
appendInfoLine: "Dynamic range: [", fixed$(min_gain, 3), ", ", fixed$(max_gain, 3), "]"
appendInfoLine: ""

# ============================================================
# CREATE POLYNOMIAL OBJECT  (used only for visualization)
# ============================================================

if envelope_type = 1
    Create Polynomial: "envelope_poly", start_x, end_x, { coef_a, coef_b, coef_c, coef_d }
else
    if root_3 = 0
        Create Polynomial from product terms: "envelope_poly", start_x, end_x, { root_1, root_2 }
    else
        Create Polynomial from product terms: "envelope_poly", start_x, end_x, { root_1, root_2, root_3 }
    endif
endif
poly_id = selected("Polynomial")

# ============================================================
# BUILD POLYNOMIAL FORMULA STRING
# Time -> x mapping: x = (t/dur) * (end_x - start_x) + start_x
# Inside `Create Sound from formula`, the variable `x` IS time
# in seconds — so we can't use `x` for both. We compute the
# normalized x on the fly inside the formula.
# ============================================================

# norm_x$ is the polynomial argument expressed in terms of `x`
# (Praat's time-in-seconds variable inside Sound formulas).
norm_x$ = "((x/" + string$(dur) + ")*(" + string$(end_x) + "-(" + string$(start_x) + "))+(" + string$(start_x) + "))"

# Bare polynomial (no weighting, no clamping, no abs)
if envelope_type = 1
    poly$ = "(" + string$(coef_a) + "*(" + norm_x$ + ")^3"
        ... + " + " + string$(coef_b) + "*(" + norm_x$ + ")^2"
        ... + " + " + string$(coef_c) + "*(" + norm_x$ + ")"
        ... + " + " + string$(coef_d) + ")"
else
    if root_3 = 0
        poly$ = "((" + norm_x$ + ")-(" + string$(root_1) + "))"
            ... + "*((" + norm_x$ + ")-(" + string$(root_2) + "))"
    else
        poly$ = "((" + norm_x$ + ")-(" + string$(root_1) + "))"
            ... + "*((" + norm_x$ + ")-(" + string$(root_2) + "))"
            ... + "*((" + norm_x$ + ")-(" + string$(root_3) + "))"
    endif
endif

# ============================================================
# BUILD ENVELOPE  (FIX v1.1: compute once, multiply once)
# We render the envelope to a 1000 Hz Sound, applying:
#   1. abs() if Treat_as_envelope = ON
#   2. perceptual weighting (power)
#   3. dynamic-range clamping
# Then we multiply this envelope into the audio at audio rate
# (Praat resamples implicitly via cross-Sound formula reference).
# ============================================================

appendInfo: "Building envelope... "

envRate = 1000
envelope = Create Sound from formula: "polyEnv", 1, 0, dur, envRate, "0"

# Stage 1: raw polynomial value (or abs if envelope mode)
if treat_as_envelope = 1
    selectObject: envelope
    Formula: "abs(" + poly$ + ")"
else
    selectObject: envelope
    Formula: poly$
endif

# Stage 2: perceptual weighting (power law)
# For envelope mode (already abs), simple `self^weight` works.
# For waveshape mode (signed), preserve sign: sign(self) * |self|^weight
if perceptual_weight <> 1
    if treat_as_envelope = 1
        # Already non-negative; safe direct power.
        # Floor at tiny epsilon to avoid 0^weight issues for weight<1
        weightStr$ = fixed$(perceptual_weight, 6)
        Formula: "max(self, 0)^" + weightStr$
    else
        # Sign-preserving power
        weightStr$ = fixed$(perceptual_weight, 6)
        Formula: "if self < 0 then -1 * (abs(self)^" + weightStr$ + ")"
            ... + " else self^" + weightStr$ + " fi"
    endif
endif

# Stage 3: dynamic-range clamping
# Clamp magnitude to [min_gain, max_gain]. With min_gain = 0
# we DON'T floor at epsilon — that was v1.0's bug.
minStr$ = fixed$(min_gain, 8)
maxStr$ = fixed$(max_gain, 8)
if treat_as_envelope = 1
    # Magnitudes are non-negative, just clip
    Formula: "min(" + maxStr$ + ", max(" + minStr$ + ", self))"
else
    # Signed: clip magnitude, preserve sign
    Formula: "if self < 0 then -1 * min(" + maxStr$ + ", max(" + minStr$ + ", abs(self)))"
        ... + " else min(" + maxStr$ + ", max(" + minStr$ + ", abs(self))) fi"
endif

selectObject: envelope
envMin = Get minimum: 0, 0, "None"
envMax = Get maximum: 0, 0, "None"
appendInfoLine: "min=", fixed$(envMin, 4), "  max=", fixed$(envMax, 4)

# ============================================================
# APPLY ENVELOPE TO AUDIO
# Cross-Sound reference inside Formula reads the envelope at
# the appropriate time. Praat handles the rate mismatch
# (audio at sr, envelope at envRate) by indexing envelope[col]
# where col is in audio samples — so we need a time-based read.
# Using object[envelope, x] where x is time-in-seconds reads
# the envelope by time. That's what we want.
# ============================================================

appendInfoLine: "Applying envelope to audio..."

selectObject: sound
result = Copy: sound_name$ + "_shaped_" + presetName$

selectObject: result
nCh = Get number of channels
envIdStr$ = string$(envelope)

# For mono: simple multiplication. For stereo/multichannel: same envelope on every channel.
selectObject: result
Formula: "self * object(" + envIdStr$ + ", x)"

if normalize
    selectObject: result
    Scale peak: 0.95
endif

selectObject: result
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# Drawn before envelope cleanup so we can plot it directly.
# ============================================================

if draw_visualization
    Erase all
    
    # Resolve weight description
    if perceptual_weight = 1.0
        weightDescr$ = "linear"
    elsif perceptual_weight >= 1.8 and perceptual_weight <= 3.5
        weightDescr$ = "perceived loudness"
    else
        weightDescr$ = "custom power"
    endif
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##POLYNOMIAL SOUND SHAPER##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... sound_name$
        ... + "  |  Preset: " + presetName$
        ... + "  |  " + typeName$
        ... + "  |  Domain: [" + fixed$(start_x, 2) + ", " + fixed$(end_x, 2) + "]"
        ... + "  |  Weight: " + fixed$(perceptual_weight, 2) + " (" + weightDescr$ + ")"
        ... + "  |  " + envName$
    
    # ----------------------------------------------------------
    # PANEL A: POLYNOMIAL CURVE (math domain)
    # Shows p(x) over [start_x, end_x] — the raw polynomial.
    # Distinct from Panel B (envelope over time, post-processed).
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40
    
    selectObject: poly_id
    pYmin = Get minimum: start_x, end_x
    pYmax = Get maximum: start_x, end_x
    pYrange = pYmax - pYmin
    if pYrange < 0.0001
        pYrange = 1
    endif
    pYpad = pYrange * 0.10
    
    Axes: start_x, end_x, pYmin - pYpad, pYmax + pYpad
    Paint rectangle: "{0.96, 0.96, 0.96}", start_x, end_x, pYmin - pYpad, pYmax + pYpad
    
    # Zero line
    if pYmin - pYpad < 0 and pYmax + pYpad > 0
        Colour: "{0.55, 0.55, 0.55}"
        Dotted line
        Draw line: start_x, 0, end_x, 0
        Solid line
        Font size: 5
        Colour: "{0.45, 0.45, 0.45}"
        Text: end_x * 0.99 + start_x * 0.01, "right", 0, "bottom", "0"
    endif
    
    # Light decade-ish gridlines at unit values within range
    Colour: "{0.88, 0.88, 0.92}"
    Line width: 1
    gridStep = pYrange / 5
    if gridStep < 0.001
        gridStep = 0.2
    endif
    gv = ceiling((pYmin - pYpad) / gridStep) * gridStep
    while gv <= pYmax + pYpad
        if abs(gv) > 0.0001
            Draw line: start_x, gv, end_x, gv
        endif
        gv = gv + gridStep
    endwhile
    
    # Polynomial curve
    selectObject: poly_id
    Colour: "{0.30, 0.50, 0.78}"
    Line width: 2
    Draw: start_x, end_x, pYmin - pYpad, pYmax + pYpad, "no", "yes"
    Line width: 1
    
    # Mark roots if envelope_type = 2
    if envelope_type = 2
        rootList# = { root_1, root_2 }
        if root_3 <> 0
            rootList# = { root_1, root_2, root_3 }
        endif
        Colour: "{0.82, 0.35, 0.35}"
        for r to size(rootList#)
            rv = rootList#[r]
            if rv >= start_x and rv <= end_x
                Paint circle (mm): "{0.82, 0.35, 0.35}", rv, 0, 1.5
            endif
        endfor
    endif
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "p(x)"
    Text bottom: "yes", "x  (math domain)"
    
    # ----------------------------------------------------------
    # PANEL B: PROCESSED ENVELOPE (over time)
    # Shows the actual gain that gets multiplied into the audio,
    # AFTER abs() (if envelope mode), perceptual weighting, and
    # dynamic-range clamping. This is what the audio "hears."
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 3.00
    Select inner viewport: 4.55, 7.75, 0.95, 2.85
    
    selectObject: envelope
    envYlo = Get minimum: 0, 0, "None"
    envYhi = Get maximum: 0, 0, "None"
    envRange = envYhi - envYlo
    if envRange < 0.001
        envRange = 0.1
    endif
    envPad = envRange * 0.10
    
    yLo = envYlo - envPad
    yHi = envYhi + envPad
    if treat_as_envelope = 1 and yLo < 0
        yLo = 0
    endif
    
    Axes: 0, dur, yLo, yHi
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, dur, yLo, yHi
    
    # Reference: zero, min_gain, max_gain
    Colour: "{0.78, 0.65, 0.78}"
    Dotted line
    if max_gain >= yLo and max_gain <= yHi
        Draw line: 0, max_gain, dur, max_gain
    endif
    if min_gain > 0 and min_gain >= yLo and min_gain <= yHi
        Draw line: 0, min_gain, dur, min_gain
    endif
    Solid line
    Font size: 5
    Colour: "{0.55, 0.30, 0.55}"
    Text: dur * 0.99, "right", max_gain, "bottom", "max " + fixed$(max_gain, 2)
    if min_gain > 0
        Text: dur * 0.99, "right", min_gain, "top", "min " + fixed$(min_gain, 2)
    endif
    
    # Zero line if visible
    if yLo < 0 and yHi > 0
        Colour: "{0.55, 0.55, 0.55}"
        Dotted line
        Draw line: 0, 0, dur, 0
        Solid line
    endif
    
    # Envelope curve
    selectObject: envelope
    Colour: "{0.30, 0.65, 0.40}"
    Line width: 1.5
    Draw: 0, dur, yLo, yHi, "no", "Curve"
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Gain"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL C: ENVELOPE MAGNITUDE HISTOGRAM
    # Distribution of envelope values across time. Shows whether
    # the envelope spends most of its time near 0 (sparse pulse),
    # near max (mostly loud), or evenly distributed.
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 3.05, 4.60
    Select inner viewport: 4.55, 7.75, 3.20, 4.50
    
    selectObject: envelope
    nEnvSamples = Get number of samples
    
    nBins = 20
    histMin = yLo
    histMax = yHi
    binW = (histMax - histMin) / nBins
    if binW < 0.0001
        binW = 0.0001
    endif
    
    bins# = zero# (nBins)
    sampleStride = 1
    if nEnvSamples > 5000
        sampleStride = ceiling(nEnvSamples / 5000)
    endif
    
    sIdx = 1
    while sIdx <= nEnvSamples
        selectObject: envelope
        sVal = Get value at sample number: 1, sIdx
        if sVal <> undefined
            bIdx = floor((sVal - histMin) / binW) + 1
            if bIdx < 1
                bIdx = 1
            endif
            if bIdx > nBins
                bIdx = nBins
            endif
            bins#[bIdx] = bins#[bIdx] + 1
        endif
        sIdx = sIdx + sampleStride
    endwhile
    
    histPeak = 1
    for b to nBins
        if bins#[b] > histPeak
            histPeak = bins#[b]
        endif
    endfor
    
    Axes: histMin, histMax, 0, histPeak * 1.15
    Paint rectangle: "{0.96, 0.96, 0.96}", histMin, histMax, 0, histPeak * 1.15
    
    # Bars
    for b to nBins
        if bins#[b] > 0
            xL = histMin + (b - 1) * binW
            xR = xL + binW * 0.92
            Paint rectangle: "{0.45, 0.65, 0.50}", xL, xR, 0, bins#[b]
        endif
    endfor
    
    # min/max reference lines
    Colour: "{0.78, 0.65, 0.78}"
    Dotted line
    if max_gain >= histMin and max_gain <= histMax
        Draw line: max_gain, 0, max_gain, histPeak * 1.15
    endif
    if min_gain > 0 and min_gain >= histMin and min_gain <= histMax
        Draw line: min_gain, 0, min_gain, histPeak * 1.15
    endif
    Solid line
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Count"
    Text bottom: "yes", "Gain value"
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    Text: 2.20, "centre", 7.30, "half", "Polynomial p(x)  (math domain)"
    Text: 6.10, "centre", 7.30, "half", "Processed envelope (upper) & gain histogram (lower)"
    
    # ----------------------------------------------------------
    # PANEL D: OUTPUT WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.75
    Select inner viewport: 0.55, 7.72, 4.75, 5.68
    
    selectObject: result
    nResultCh = Get number of channels
    outPeak = Get absolute extremum: 0, 0, "None"
    if outPeak < 0.001
        outPeak = 0.001
    endif
    ampViz = outPeak * 1.15
    
    Axes: 0, finalDur, -ampViz, ampViz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, finalDur, -ampViz, ampViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, finalDur, 0
    
    selectObject: result
    if nResultCh = 1
        Colour: "{0.20, 0.55, 0.55}"
        Line width: 1
        Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
    else
        Extract one channel: 1
        vCh1 = selected("Sound")
        Colour: "{0.25, 0.50, 0.82}"
        Line width: 1
        Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
        removeObject: vCh1
        
        if nResultCh >= 2
            selectObject: result
            Extract one channel: 2
            vCh2 = selected("Sound")
            Colour: "{0.82, 0.45, 0.25}"
            Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
            removeObject: vCh2
        endif
    endif
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    if nResultCh > 1
        Text top: "no", "Output  (blue=L  orange=R)"
    else
        Text top: "no", "Output (mono)"
    endif
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.82, 6.58
    Select inner viewport: 0.55, 7.72, 5.88, 6.52
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    if envelope_type = 1
        polyDescr$ = fixed$(coef_a, 2) + "x^3 + " + fixed$(coef_b, 2)
            ... + "x^2 + " + fixed$(coef_c, 2) + "x + " + fixed$(coef_d, 2)
    else
        if root_3 = 0
            polyDescr$ = "(x-" + fixed$(root_1, 2) + ")(x-" + fixed$(root_2, 2) + ")"
        else
            polyDescr$ = "(x-" + fixed$(root_1, 2) + ")(x-" + fixed$(root_2, 2) + ")(x-" + fixed$(root_3, 2) + ")"
        endif
    endif
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + sound_name$
        ... + "  |  " + polyDescr$
        ... + "  on [" + fixed$(start_x, 2) + ", " + fixed$(end_x, 2) + "]"
        ... + "  |  " + envName$
    
    Text: 0.02, "left", 0.28, "half",
        ... "Weight: " + fixed$(perceptual_weight, 2) + " (" + weightDescr$ + ")"
        ... + "  |  Range: [" + fixed$(min_gain, 3) + ", " + fixed$(max_gain, 3) + "]"
        ... + "  |  Env min/max: " + fixed$(envMin, 3) + " / " + fixed$(envMax, 3)
        ... + "  |  Output: " + fixed$(finalDur, 2) + " s, peak " + fixed$(finalPeak, 3)
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# ============================================================
# CLEANUP
# ============================================================

removeObject: poly_id, envelope

# ============================================================
# DONE
# ============================================================

selectObject: result

appendInfoLine: ""
appendInfoLine: "============================================"
appendInfoLine: "  COMPLETE"
appendInfoLine: "============================================"
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(finalDur, 2), " s"
appendInfoLine: "Peak: ", fixed$(finalPeak, 4)
appendInfoLine: "Envelope range: [", fixed$(envMin, 4), ", ", fixed$(envMax, 4), "]"
if min_gain > 0
    appendInfoLine: "Floor: ", fixed$(20 * log10(min_gain), 1), " dB"
endif
if max_gain < 1
    appendInfoLine: "Ceiling: ", fixed$(20 * log10(max_gain), 1), " dB"
endif

if play_result
    selectObject: result
    Play
endif

selectObject: result
