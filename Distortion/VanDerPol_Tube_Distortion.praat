# ============================================================
# Praat AudioTools - VanDerPol_Tube_Distortion.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Van der Pol Tube Distortion. Memoryless waveshaping through
#       y = x - mu * (x^3 / 3)
#   which is (up to sign) the LIENARD CHARACTERISTIC
#       F(x) = x^3/3 - x
#   of the Van der Pol oscillator
#       x'' - mu * (1 - x^2) * x' + x = 0
#   -- i.e. van der Pol's own model of the TRIODE's current-
#   voltage curve. This is not an approximation of the tube
#   equation; it is the historical tube nonlinearity the equation
#   was built from. Odd symmetry -> odd harmonics only.
#
#   HONEST BEHAVIOR NOTE (v0.3): the cubic peaks at
#   |x*Drive| = 1/sqrt(mu) (height (2/3)/sqrt(mu), always BELOW
#   the tanh threshold for mu > 0.05), then FOLDS BACK, crosses
#   zero at |x*Drive| = sqrt(3/mu), and INVERTS. The tanh guard
#   engages only deep in the inverted region: it bounds the
#   output but cannot and does not prevent folding or polarity
#   inversion. Two presets stay in the warm monotonic zone at
#   full-scale input (Subtle, Gentle Warmth); the other three are
#   WAVEFOLDERS (Classic Saturation inverts above input 0.69 and
#   nearly annihilates the fundamental of a hot sine -- measured).
#   The Character menu makes the choice explicit:
#     * authentic fold -- the v0.2 curve, bit-identical
#     * monotonic tube -- holds the cubic's peak beyond
#       |x*Drive| = 1/sqrt(mu): classic cubic soft-clip,
#       guaranteed monotonic at any setting
#
#   Pipeline:
#     1. Multiply by Drive
#     2. Waveshaper (per Character, see above)
#     3. Multiply by Output_Gain
#     4. Final hard clamp to +/- 0.999 (last-resort safety net)
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.3 (2026):
#   - Description rewritten: the cubic is the Liénard
#     characteristic -- van der Pol's own triode curve -- not a
#     "restoring-force approximation"; and the old claims of
#     guaranteed monotonicity / no inversion were FALSE (the tanh
#     guard engages only after the fold; measured: Classic
#     Saturation inverts above input 0.69, ramp out(0.95) =
#     -0.999).
#   - Character menu: "authentic fold" (v0.2 curve, verified
#     bit-identical) vs "monotonic tube" (peak-hold cubic soft
#     clip, truly monotonic).
#   - The curve-character diagnostic now reports the actual fold
#     and inversion onset inputs instead of only tanh engagement
#     (which mislabeled folding presets "pure cubic").
#   - VIZ: title strip explicit inner viewport; the transfer
#     panel draws the selected Character's true curve.
#
# Changelog v0.2:
#   - NEW: Preset menu (Manual + 5 curated presets, from subtle
#     coloration to extreme tanh-limited fold-back).
#   - NEW: Suite-standard 8x8 visualization: Panel A = transfer
#     function (headline), Panel B = parameter report, Panel C =
#     output waveform, Panel D = summary bar.
#   - NEW: Draw_visualization and Play_result toggles.
#   - Header, form layout and variable casing aligned with the
#     Praat AudioTools house style.
#   - Audio pipeline UNCHANGED from v0.1: bit-identical output for
#     the same Drive / Mu / Output_Gain values.
# Changelog v0.1:
#   - Initial release: cubic Van der Pol waveshaper with tanh
#     safety-clip fallback, Drive / Mu / Output_Gain controls,
#     native mono/stereo handling via per-channel Formula.
# ============================================================

form Van der Pol Tube Distortion v0.3
    comment Select a Preset (overrides sliders below)
    optionmenu Preset: 1
        option Manual (Use settings below)
        option Subtle Coloration
        option Gentle Tube Warmth
        option Classic Tube Saturation
        option Aggressive Drive
        option Fold-back Extreme

    optionmenu Character: 1
        option authentic fold (the original curve)
        option monotonic tube (peak-hold soft clip)

    comment Manual Parameters
    positive Drive 3.0
    real Mu 1.0
    real Output_Gain 1.0

    comment Output
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

# === Handle Presets ===
presetName$ = "Manual"

if preset = 2
    presetName$ = "Subtle"
    drive = 1.05
    mu = 0.2
    output_Gain = 0.98
elsif preset = 3
    presetName$ = "GentleWarmth"
    drive = 1.2
    mu = 0.5
    output_Gain = 0.95
elsif preset = 4
    presetName$ = "ClassicSaturation"
    drive = 2.5
    mu = 1.0
    output_Gain = 0.85
elsif preset = 5
    presetName$ = "Aggressive"
    drive = 5.0
    mu = 1.5
    output_Gain = 0.6
elsif preset = 6
    presetName$ = "FoldbackExtreme"
    drive = 9.0
    mu = 3.0
    output_Gain = 0.4
endif

# === Get original details ===
original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
inputDur = Get total duration
inputCh = Get number of channels

# A fixed ceiling beyond which the cubic term is allowed to fold
# back on itself; past this point the script substitutes a smooth
# tanh() soft-clip instead of the raw cubic, so extreme Drive/Mu
# combinations can never blow up or invert the waveform.
safetyThreshold = 3

# === Info ===
writeInfoLine: "=== Van der Pol Tube Distortion v0.3 ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(inputDur, 2), " s, ", inputCh, " ch)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Drive: ", fixed$(drive, 2), " | Mu: ", fixed$(mu, 2), " | Output_Gain: ", fixed$(output_Gain, 2)
appendInfoLine: ""

# ============================================================
# APPLY WAVE SHAPING  (identical DSP to v0.1)
# ============================================================

appendInfoLine: "Applying Van der Pol waveshaping..."

# --- Duplicate the sound so the original is left untouched -------
# Copy: also assigns the final "..._VdP_Dist" name directly.
selectObject: original
result = Copy: originalName$ + "_VdP_Dist_" + presetName$

# --- Apply the waveshaper to every sample, every channel ---------
# Formula... runs per channel automatically, so this works
# unchanged on mono, stereo, or multi-channel sounds.
selectObject: result
if character = 1
    # authentic fold: the v0.2 curve verbatim
    Formula: ~ if abs(self*drive - mu*((self*drive)^3)/3) > safetyThreshold
        ... then tanh(self*drive - mu*((self*drive)^3)/3) * safetyThreshold
        ... else self*drive - mu*((self*drive)^3)/3 fi
else
    # monotonic tube: hold the cubic's peak (2/3)/sqrt(mu) beyond
    # |x*drive| = 1/sqrt(mu) -- classic cubic soft clip
    if mu > 0
        foldPoint = 1 / sqrt(mu)
        peakHold = (2/3) / sqrt(mu)
        Formula: ~ if abs(self*drive) > foldPoint
            ... then (if self > 0 then peakHold else -peakHold fi)
            ... else self*drive - mu*((self*drive)^3)/3 fi
    else
        Formula: ~ self*drive
    endif
endif

# --- Output gain compensation -------------------------------------
Formula: ~ self * output_Gain

# --- Final hard-clamp safety net ----------------------------------
Formula: ~ if self > 0.999 then 0.999 else if self < -0.999 then -0.999 else self fi fi

# === Final stats ===
selectObject: result
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"
nResultCh = Get number of channels

# Diagnostic (v0.3): where does the curve fold and invert, in
# INPUT units? Fold onset = 1/(sqrt(mu)*drive); inversion onset
# = sqrt(3/mu)/drive. Reported honestly per Character.
if mu > 0
    foldOnset = 1 / (sqrt(mu) * drive)
    invOnset = sqrt(3 / mu) / drive
else
    foldOnset = 1e9
    invOnset = 1e9
endif
if character = 2
    if foldOnset >= 1
        character$ = "monotonic tube: pure cubic below full scale"
    else
        character$ = "monotonic tube: peak-hold above x = " + fixed$(foldOnset, 2)
    endif
else
    if foldOnset >= 1
        character$ = "warm: no folding below full scale"
    elsif invOnset >= 1
        character$ = "folds above x = " + fixed$(foldOnset, 2) + " (no inversion below full scale)"
    else
        character$ = "folds above x = " + fixed$(foldOnset, 2) + ", INVERTS above x = " + fixed$(invOnset, 2)
    endif
endif

appendInfoLine: "Curve character: ", character$
appendInfoLine: ""

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================

if draw_visualization
    Erase all

    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Select inner viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.72, "half", "##VAN DER POL TUBE DISTORTION v0.3##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", 0.26, "half",
        ... originalName$
        ... + "  |  " + presetName$
        ... + "  |  Drive: " + fixed$(drive, 2)
        ... + "  |  Mu: " + fixed$(mu, 2)
        ... + "  |  Out gain: " + fixed$(output_Gain, 2)

    # ----------------------------------------------------------
    # PANEL A: TRANSFER FUNCTION  (left, headline)
    # The defining diagnostic for any waveshaper.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40

    Axes: -1.5, 1.5, -1.5, 1.5
    Paint rectangle: "{0.96, 0.96, 0.96}", -1.5, 1.5, -1.5, 1.5

    # Grid: zero axes
    Colour: "{0.85, 0.85, 0.88}"
    Line width: 1
    Draw line: -1.5, 0, 1.5, 0
    Draw line: 0, -1.5, 0, 1.5

    # y=x reference (no shaping)
    Dotted line
    Colour: "{0.65, 0.65, 0.70}"
    Draw line: -1.5, -1.5, 1.5, 1.5
    Solid line
    Font size: 5
    Text: -1.45, "left", -1.40, "half", "y = x"

    # Digital ceiling (final hard clamp at +/- 0.999)
    Colour: "{0.78, 0.65, 0.78}"
    Dotted line
    Draw line: -1.5, 1, 1.5, 1
    Draw line: -1.5, -1, 1.5, -1
    Solid line
    Font size: 5
    Colour: "{0.55, 0.30, 0.55}"
    Text: -1.45, "left", 1, "bottom", " ceiling"
    Text: -1.45, "left", -1, "top", " -ceiling"

    # Approximate tanh safety-clip zone (safetyThreshold * output_Gain)
    safetyY = safetyThreshold * output_Gain
    if safetyY < 1.45
        Colour: "{0.55, 0.78, 0.55}"
        Dotted line
        Draw line: -1.5, safetyY, 1.5, safetyY
        Draw line: -1.5, -safetyY, 1.5, -safetyY
        Solid line
        Font size: 5
        Colour: "{0.30, 0.55, 0.30}"
        Text: -1.45, "left", safetyY, "bottom", " tanh safety"
        Text: -1.45, "left", -safetyY, "top", " -tanh safety"
    endif

    # Draw the actual transfer function (matches the audio Formula
    # chain exactly: cubic + tanh fallback, then output gain, then
    # hard clamp).
    Colour: "{0.80, 0.40, 0.40}"
    Line width: 2
    nPoints = 200

    prev_x = -1.5
    prev_driven = prev_x * drive
    prev_cubic = prev_driven - mu * (prev_driven^3) / 3
    if character = 2 and mu > 0 and abs(prev_driven) > 1/sqrt(mu)
        prev_y = (2/3) / sqrt(mu)
        if prev_driven < 0
            prev_y = -prev_y
        endif
    elsif abs(prev_cubic) > safetyThreshold and character = 1
        prev_y = tanh(prev_cubic) * safetyThreshold
    else
        prev_y = prev_cubic
    endif
    prev_y = prev_y * output_Gain
    if prev_y > 1.45
        prev_y = 1.45
    endif
    if prev_y < -1.45
        prev_y = -1.45
    endif

    for i from 1 to nPoints
        curr_x = -1.5 + (i / nPoints) * 3.0
        driven = curr_x * drive
        cubic = driven - mu * (driven^3) / 3
        if character = 2 and mu > 0 and abs(driven) > 1/sqrt(mu)
            curr_y = (2/3) / sqrt(mu)
            if driven < 0
                curr_y = -curr_y
            endif
        elsif abs(cubic) > safetyThreshold and character = 1
            curr_y = tanh(cubic) * safetyThreshold
        else
            curr_y = cubic
        endif
        curr_y = curr_y * output_Gain
        if curr_y > 1.45
            curr_y = 1.45
        endif
        if curr_y < -1.45
            curr_y = -1.45
        endif
        Draw line: prev_x, prev_y, curr_x, curr_y
        prev_x = curr_x
        prev_y = curr_y
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Output"
    Text bottom: "yes", "Input"

    # ----------------------------------------------------------
    # PANEL B: PARAMETER REPORT  (right, headline-height)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.55, 7.75, 0.95, 4.40

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 1

    # Section: Waveshaping
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.93, "half", "Waveshaping parameters:"

    Font size: 11
    Colour: "{0.30, 0.45, 0.78}"
    Text: 0.10, "left", 0.84, "half", "Drive:    " + fixed$(drive, 2)
    Text: 0.10, "left", 0.76, "half", "Mu:       " + fixed$(mu, 2)

    # Section: Safety
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.65, "half", "Safety net:"

    Font size: 11
    Colour: "{0.40, 0.55, 0.78}"
    Text: 0.10, "left", 0.56, "half", "Threshold: " + fixed$(safetyThreshold, 1)

    Font size: 7
    Colour: "{0.55, 0.55, 0.55}"
    Text: 0.10, "left", 0.48, "half", "(" + character$ + ")"

    # Section: Output
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.36, "half", "Output:"

    Font size: 11
    Colour: "{0.40, 0.65, 0.40}"
    Text: 0.10, "left", 0.27, "half", "Gain:     " + fixed$(output_Gain, 2)

    Font size: 7
    Colour: "{0.55, 0.55, 0.55}"
    Text: 0.10, "left", 0.19, "half", "Hard clamp +/- 0.999 (final safety net)"

    Colour: "Black"
    Draw inner box

    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8

    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "Transfer function (input -> output)"
    Text: 6.10, "centre", 7.30, "half", "Parameter report"

    # ----------------------------------------------------------
    # PANEL C: OUTPUT WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.75
    Select inner viewport: 0.55, 7.72, 4.75, 5.68

    selectObject: result
    outPeakViz = Get absolute extremum: 0, 0, "None"
    if outPeakViz < 0.001
        outPeakViz = 0.001
    endif
    ampViz = outPeakViz * 1.15

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
    # PANEL D: SUMMARY BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.82, 6.58
    Select inner viewport: 0.55, 7.72, 5.88, 6.52
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + originalName$
        ... + "  |  Drive: " + fixed$(drive, 2)
        ... + "  |  Mu: " + fixed$(mu, 2)
        ... + "  |  Out gain: " + fixed$(output_Gain, 2)

    Text: 0.02, "left", 0.28, "half",
        ... "Safety threshold: " + fixed$(safetyThreshold, 1)
        ... + "  |  " + character$
        ... + "  |  Output: " + fixed$(finalDur, 2) + " s, peak " + fixed$(finalPeak, 3)

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# === Final ===
selectObject: result

appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(finalDur, 2), " s"
appendInfoLine: "Peak: ", fixed$(finalPeak, 4)

if play_result
    selectObject: result
    Play
endif

selectObject: result
