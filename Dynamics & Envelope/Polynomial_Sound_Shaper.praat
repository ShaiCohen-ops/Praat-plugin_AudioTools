# ============================================================
# Praat AudioTools - Polynomial_Sound_Shaper.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.3.1 (2026) - Visualization bug-fix pass:
#   - Root-mode Panel A now uses "Create Polynomial from real zeros"
#     (was incorrectly using "from product terms", which does not
#     interpret its arguments as real roots)
#   - Panel A polynomial coefficient string is now built with the
#     shortest valid coefficient list, avoiding invalid Get minimum/
#     maximum results caused by trailing zero high-order coefficients
#   - Fade Out preset corrected to true linear p(x) = 1 - x
#     (was quadratic p(x) = 1 - x^2)
#   - Panel A / Panel B now carry explicit titles distinguishing the
#     raw polynomial p(x) from the applied (clamped, weighted) gain
#   - Histogram (Panel C) now excludes the 5 ms edge-padding samples,
#     so it matches the same interval as Panel B and the output audio
#   - Removed viewport calls where "Select outer viewport" was
#     immediately discarded by a following "Select inner viewport"
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Polynomial gain envelope shaper. Evaluates a user-defined
#   polynomial p(x) over a normalized time domain [start_x, end_x],
#   mapped directly to the audio object's time domain [t_start, t_end].
# ============================================================

# Changelog v1.3.1 (2026):
#   - VISUALIZATION / UI STANDARDIZATION ONLY. Audio analysis,
#     DSP, scheduling and rendering are unchanged from the
#     previous version.
#   - Adopted the Praat AudioTools 8-inch visualization header,
#     suite typography, neutral panel backgrounds, summary-style
#     reporting and full-page Picture export restoration.
#   - Preserved the script-specific diagnostic / transformation
#     views rather than replacing them with generic plots.
#
form Polynomial Sound Shaper v1.3.1
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
    optionmenu Polynomial_degree: 1
        option Quadratic (2 roots)
        option Cubic (3 roots)
    comment === Domain ===
    real Start_x 0.0
    real End_x 1.0
    comment === Polynomial Coefficients (ax^3 + bx^2 + cx + d) ===
    real Coef_a 0.0
    real Coef_b 0.0
    real Coef_c 1.0
    real Coef_d 0.0
    comment === Product Terms (x-r1)(x-r2)(x-r3) ===
    real Root_1 -1.0
    real Root_2 1.0
    real Root_3 0.0
    comment === Perceptual Tuning ===
    positive Perceptual_weight 1.0
    comment (1=linear, 2-3=perceived loudness)
    comment === Dynamic Range ===
    real Min_gain 0.0
    real Max_gain 1.0
    comment === Behavior ===
    boolean Treat_as_envelope 1
    comment (ON: |p(x)| used as gain envelope. OFF: signed polarity envelope)
    boolean Peak_normalize_output 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# INPUT VALIDATION
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Validation Error: Please select exactly one Sound object."
endif

sound = selected("Sound")
sound_name$ = selected$("Sound")

selectObject: sound
dur = Get total duration
t_start = Get start time
t_end = Get end time
sr = Get sampling frequency

if min_gain < 0
    exitScript: "Validation Error: Min_gain must be non-negative (>= 0)."
endif

if max_gain < min_gain
    exitScript: "Validation Error: Max_gain must be >= Min_gain."
endif

if start_x >= end_x
    exitScript: "Validation Error: Domain must satisfy start_x < end_x."
endif

# ============================================================
# APPLY PRESETS
# ============================================================

if preset = 2
    # Fade In (linear: p(x) = x)
    envelope_type = 1
    coef_a = 0.0
    coef_b = 0.0
    coef_c = 1.0
    coef_d = 0.0
    start_x = 0.0
    end_x = 1.0
    presetName$ = "FadeIn"
elsif preset = 3
    # Fade Out (linear: p(x) = 1 - x)
    envelope_type = 1
    coef_a = 0.0
    coef_b = 0.0
    coef_c = -1.0
    coef_d = 1.0
    start_x = 0.0
    end_x = 1.0
    presetName$ = "FadeOut"
elsif preset = 4
    # Swell (peak center: (x+1)(1-x) = 1 - x^2 on [-1, 1])
    envelope_type = 2
    polynomial_degree = 1
    root_1 = -1.0
    root_2 = 1.0
    start_x = -1.0
    end_x = 1.0
    presetName$ = "Swell"
elsif preset = 5
    # Attack-Decay (-4x^2 + 4x on [0, 1])
    envelope_type = 1
    coef_a = 0.0
    coef_b = -4.0
    coef_c = 4.0
    coef_d = 0.0
    start_x = 0.0
    end_x = 1.0
    presetName$ = "AttackDecay"
elsif preset = 6
    # Slow Attack (x^3 on [0, 1])
    envelope_type = 1
    coef_a = 1.0
    coef_b = 0.0
    coef_c = 0.0
    coef_d = 0.0
    start_x = 0.0
    end_x = 1.0
    presetName$ = "SlowAttack"
elsif preset = 7
    # Double Pulse (cubic roots at 0, 0.5, 1)
    envelope_type = 2
    polynomial_degree = 2
    root_1 = 0.0
    root_2 = 0.5
    root_3 = 1.0
    start_x = 0.0
    end_x = 1.0
    presetName$ = "DoublePulse"
elsif preset = 8
    # Asymmetric Rise (x(x-2) on [0, 1])
    envelope_type = 2
    polynomial_degree = 1
    root_1 = 0.0
    root_2 = 2.0
    start_x = 0.0
    end_x = 1.0
    presetName$ = "AsymRise"
elsif preset = 9
    # Quartic In (x^2 with weight 2 => x^4)
    envelope_type = 1
    coef_a = 0.0
    coef_b = 1.0
    coef_c = 0.0
    coef_d = 0.0
    start_x = 0.0
    end_x = 1.0
    perceptual_weight = 2.0
    presetName$ = "QuarticIn"
elsif preset = 10
    # Quartic Out ((1-x)^2 = x^2 - 2x + 1 with weight 2 => (1-x)^4)
    envelope_type = 1
    coef_a = 0.0
    coef_b = 1.0
    coef_c = -2.0
    coef_d = 1.0
    start_x = 0.0
    end_x = 1.0
    perceptual_weight = 2.0
    presetName$ = "QuarticOut"
else
    presetName$ = "Custom"
endif

# ============================================================
# RESOLVE TYPE / MODE NAMES
# ============================================================

if envelope_type = 1
    typeName$ = "Coefficients"
else
    typeName$ = "Roots"
endif

if treat_as_envelope = 1
    envName$ = "abs(p) [envelope]"
else
    envName$ = "signed p [polarity inversion]"
endif

# ============================================================
# INFO HEADER
# ============================================================

clearinfo
writeInfoLine: "============================================"
appendInfoLine: "  POLYNOMIAL SOUND SHAPER v1.3.1"
appendInfoLine: "============================================"
appendInfoLine: ""
appendInfoLine: "Input:  ", sound_name$, " (", fixed$(dur, 3), " s)"
appendInfoLine: "Domain: [", fixed$(t_start, 3), " s - ", fixed$(t_end, 3), " s]"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Type:   ", typeName$
appendInfoLine: "Mode:   ", envName$
appendInfoLine: "Math:   [", fixed$(start_x, 3), ", ", fixed$(end_x, 3), "]"

if envelope_type = 1
    appendInfoLine: "Poly:   ", coef_a, "*x^3 + ", coef_b, "*x^2 + ", coef_c, "*x + ", coef_d
else
    if polynomial_degree = 1
        appendInfoLine: "Poly:   (x - ", root_1, ")(x - ", root_2, ")"
    else
        appendInfoLine: "Poly:   (x - ", root_1, ")(x - ", root_2, ")(x - ", root_3, ")"
    endif
endif

appendInfoLine: "Weight: ", fixed$(perceptual_weight, 2)
appendInfoLine: "Range:  [", fixed$(min_gain, 3), ", ", fixed$(max_gain, 3), "]"
appendInfoLine: ""

# ============================================================
# CREATE POLYNOMIAL OBJECT FOR VISUALIZATION
# Praat expects "c1 c2 c3 c4" (d, c, b, a)
# ============================================================

if envelope_type = 1
    # Build the shortest valid coefficient list (Praat's Polynomial autoscaling
    # can fail / return invalid min-max values when trailing high-order
    # coefficients are zero), from constant term upward.
    if coef_a <> 0
        coefStr$ = string$(coef_d) + " " + string$(coef_c) + " " + string$(coef_b) + " " + string$(coef_a)
    elsif coef_b <> 0
        coefStr$ = string$(coef_d) + " " + string$(coef_c) + " " + string$(coef_b)
    elsif coef_c <> 0
        coefStr$ = string$(coef_d) + " " + string$(coef_c)
    else
        coefStr$ = string$(coef_d)
    endif
    Create Polynomial: "envelope_poly", start_x, end_x, coefStr$
else
    if polynomial_degree = 1
        rootsStr$ = string$(root_1) + " " + string$(root_2)
    else
        rootsStr$ = string$(root_1) + " " + string$(root_2) + " " + string$(root_3)
    endif
    # "Create Polynomial from real zeros" builds a polynomial with the given
    # roots. "Create Polynomial from product terms" is a different command
    # and does NOT interpret its arguments as a list of real roots.
    Create Polynomial from real zeros: "envelope_poly", start_x, end_x, rootsStr$
endif
poly_id = selected("Polynomial")

# ============================================================
# TIME TO MATH DOMAIN MAPPING
# ============================================================

norm_x$ = "((x - (" + string$(t_start) + ")) / " + string$(dur) + " * (" + string$(end_x) + " - (" + string$(start_x) + ")) + (" + string$(start_x) + "))"

if envelope_type = 1
    poly$ = "(" + string$(coef_a) + "*(" + norm_x$ + ")^3 + " + string$(coef_b) + "*(" + norm_x$ + ")^2 + " + string$(coef_c) + "*(" + norm_x$ + ") + " + string$(coef_d) + ")"
else
    if polynomial_degree = 1
        poly$ = "((" + norm_x$ + ")-(" + string$(root_1) + "))*((" + norm_x$ + ")-(" + string$(root_2) + "))"
    else
        poly$ = "((" + norm_x$ + ")-(" + string$(root_1) + "))*((" + norm_x$ + ")-(" + string$(root_2) + "))*((" + norm_x$ + ")-(" + string$(root_3) + "))"
    endif
endif

# ============================================================
# BUILD ENVELOPE (With Edge Padding)
# ============================================================

appendInfo: "Building envelope... "

envRate = 1000
pad_time = 0.005
env_t_start = t_start - pad_time
env_t_end   = t_end + pad_time

envelope = Create Sound from formula: "polyEnv", 1, env_t_start, env_t_end, envRate, "0"

# Stage 1: Absolute / Raw
selectObject: envelope
if treat_as_envelope = 1
    Formula: "abs(" + poly$ + ")"
else
    Formula: poly$
endif

# Stage 2: Perceptual Weighting
if perceptual_weight <> 1.0
    weightStr$ = fixed$(perceptual_weight, 6)
    if treat_as_envelope = 1
        Formula: "self^" + weightStr$
    else
        Formula: "if self < 0 then -1 * (abs(self)^" + weightStr$ + ") else self^" + weightStr$ + " fi"
    endif
endif

# Stage 3: Dynamic Range Clamping
minStr$ = fixed$(min_gain, 8)
maxStr$ = fixed$(max_gain, 8)
if treat_as_envelope = 1
    Formula: "if self > " + maxStr$ + " then " + maxStr$ + " else (if self < " + minStr$ + " then " + minStr$ + " else self fi) fi"
else
    Formula: "if self < 0 then -1 * (if abs(self) > " + maxStr$ + " then " + maxStr$ + " else (if abs(self) < " + minStr$ + " then " + minStr$ + " else abs(self) fi) fi) else (if self > " + maxStr$ + " then " + maxStr$ + " else (if self < " + minStr$ + " then " + minStr$ + " else self fi) fi) fi"
endif

selectObject: envelope
envMin = Get minimum: t_start, t_end, "None"
envMax = Get maximum: t_start, t_end, "None"
appendInfoLine: "min=", fixed$(envMin, 4), "  max=", fixed$(envMax, 4)

# ============================================================
# APPLY ENVELOPE TO AUDIO
# ============================================================

appendInfoLine: "Applying envelope to audio..."

selectObject: sound
result = Copy: sound_name$ + "_shaped_" + presetName$

selectObject: result
envIdStr$ = string$(envelope)
Formula: "self * object(" + envIdStr$ + ", x)"

if peak_normalize_output
    selectObject: result
    Scale peak: 0.95
endif

selectObject: result
finalPeak = Get absolute extremum: t_start, t_end, "None"

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    vizName$ = replace$(sound_name$, "_", "\_ ", 0)
    pageWidth = 8
    # === Header ===
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Polynomial Sound Shaper v1.3.1##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", vizName$ + " | " + presetName$ + " | " + typeName$ + " | domain [" + fixed$(start_x, 2) + ", " + fixed$(end_x, 2) + "]"

    # Panel A: Polynomial Curve
    Select inner viewport: 0.55, 4.00, 0.95, 4.40
    
    selectObject: poly_id
    pYmin = Get minimum: start_x, end_x
    pYmax = Get maximum: start_x, end_x
    pYrange = pYmax - pYmin
    if pYrange < 0.0001
        pYrange = 0.0001
    endif
    pYpad = pYrange * 0.10
    
    Axes: start_x, end_x, pYmin - pYpad, pYmax + pYpad
    Paint rectangle: "{0.97, 0.97, 0.97}", start_x, end_x, pYmin - pYpad, pYmax + pYpad
    
    if pYmin - pYpad < 0 and pYmax + pYpad > 0
        Colour: "{0.55, 0.55, 0.55}"
        Dotted line
        Draw line: start_x, 0, end_x, 0
        Solid line
    endif
    
    selectObject: poly_id
    Colour: "{0.30, 0.50, 0.78}"
    Line width: 2
    Draw: start_x, end_x, pYmin - pYpad, pYmax + pYpad, "no", "yes"
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "p(x)"
    Text bottom: "yes", "x (math domain)"
    Font size: 6
    Text top: "yes", "RAW POLYNOMIAL p(x)"
    
    # Panel B: Processed Envelope
    Select inner viewport: 4.55, 7.75, 0.95, 2.85
    
    selectObject: envelope
    envYlo = Get minimum: t_start, t_end, "None"
    envYhi = Get maximum: t_start, t_end, "None"
    envRange = envYhi - envYlo
    if envRange < 0.001
        envRange = 0.001
    endif
    envPad = envRange * 0.10
    
    yLo = envYlo - envPad
    yHi = envYhi + envPad
    if treat_as_envelope = 1 and yLo < 0
        yLo = 0
    endif
    
    Axes: t_start, t_end, yLo, yHi
    Paint rectangle: "{0.97, 0.97, 0.97}", t_start, t_end, yLo, yHi
    
    Colour: "{0.78, 0.65, 0.78}"
    Dotted line
    if max_gain >= yLo and max_gain <= yHi
        Draw line: t_start, max_gain, t_end, max_gain
    endif
    if min_gain > 0 and min_gain >= yLo and min_gain <= yHi
        Draw line: t_start, min_gain, t_end, min_gain
    endif
    Solid line
    
    selectObject: envelope
    Colour: "{0.30, 0.65, 0.40}"
    Line width: 1.5
    Draw: t_start, t_end, yLo, yHi, "no", "Curve"
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Gain"
    Text bottom: "yes", "Time (s)"
    if treat_as_envelope = 1
        Text top: "yes", "APPLIED GAIN: clamp(|p(x)|^weight)"
    else
        Text top: "yes", "APPLIED SIGNED GAIN: sign(p)|p|^weight"
    endif
    
    # Panel C: Histogram
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
    for sIdx from 1 to nEnvSamples
        selectObject: envelope
        sampleTime = Get time from sample number: sIdx
        if sampleTime >= t_start and sampleTime <= t_end
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
        endif
    endfor
    
    histPeak = 1
    for b to nBins
        if bins#[b] > histPeak
            histPeak = bins#[b]
        endif
    endfor
    
    Axes: histMin, histMax, 0, histPeak * 1.15
    Paint rectangle: "{0.97, 0.97, 0.97}", histMin, histMax, 0, histPeak * 1.15
    
    for b to nBins
        if bins#[b] > 0
            xL = histMin + (b - 1) * binW
            xR = xL + binW * 0.92
            Paint rectangle: "{0.45, 0.65, 0.50}", xL, xR, 0, bins#[b]
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Count"
    Text bottom: "yes", "Gain value"
    
    # Panel D: Output Waveform
    Select inner viewport: 0.55, 7.72, 4.75, 5.68
    
    selectObject: result
    outPeak = Get absolute extremum: t_start, t_end, "None"
    if outPeak < 0.001
        outPeak = 0.001
    endif
    ampViz = outPeak * 1.15
    
    Axes: t_start, t_end, -ampViz, ampViz
    Paint rectangle: "{0.97, 0.97, 0.97}", t_start, t_end, -ampViz, ampViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: t_start, 0, t_end, 0
    
    selectObject: result
    Colour: "{0.20, 0.55, 0.55}"
    Draw: t_start, t_end, -ampViz, ampViz, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # Summary Bar
    Select inner viewport: 0.55, 7.72, 5.88, 6.52
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.5, "half", "##" + presetName$ + "## | Output duration: " + fixed$(dur, 3) + " s | Peak: " + fixed$(finalPeak, 4) + " | Range: [" + fixed$(min_gain, 2) + ", " + fixed$(max_gain, 2) + "]"
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
    # Restore complete page for Picture export / clipboard.
    pageHeight = 6.20
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line

endif

# ============================================================
# CLEANUP & PLAYBACK
# ============================================================

removeObject: poly_id, envelope

selectObject: result

appendInfoLine: ""
appendInfoLine: "============================================"
appendInfoLine: "  COMPLETE: ", selected$("Sound")
appendInfoLine: "============================================"

if play_result
    Play
endif

selectObject: result