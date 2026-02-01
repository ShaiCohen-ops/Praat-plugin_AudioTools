# ============================================================
# Praat AudioTools - Polynomial_Sound_Shaper.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Polynomial envelope shaper with perceptual weighting
#   and dynamic range control. Uses polynomial curves to
#   create complex amplitude envelopes.
#
# Changelog v1.0:
#   - Renamed presets to musical terms
#   - Added more intuitive presets
#   - Fixed viewport width
#   - Added Polynomial cleanup
#   - Improved info output
#   - Added normalize option
# ============================================================

form Polynomial Sound Shaper v1.0
    optionmenu Preset 1
        option Custom
        option Fade In (linear)
        option Fade Out (linear)
        option Swell (peak center)
        option Attack-Decay
        option Slow Attack
        option Double Pulse
        option Asymmetric Rise
        option Exponential In
        option Exponential Out
    comment === Envelope Type ===
    optionmenu Envelope_type 1
        option Polynomial coefficients
        option Polynomial from roots
    comment === Domain ===
    real Start_x -1
    real End_x 1
    comment === Polynomial Coefficients (ax³+bx²+cx+d) ===
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
    comment === Output ===
    boolean Normalize 1
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

# === APPLY PRESETS ===
if preset = 2
    # Fade In (linear)
    envelope_type = 2
    root_1 = 0
    root_2 = 1
    root_3 = 0
    start_x = 0
    end_x = 1
    presetName$ = "FadeIn"
elsif preset = 3
    # Fade Out (linear)
    envelope_type = 2
    root_1 = -1
    root_2 = 0
    root_3 = 0
    start_x = -1
    end_x = 0
    presetName$ = "FadeOut"
elsif preset = 4
    # Swell (peak center)
    envelope_type = 2
    root_1 = -1
    root_2 = 1
    root_3 = 0
    start_x = -1
    end_x = 1
    presetName$ = "Swell"
elsif preset = 5
    # Attack-Decay
    envelope_type = 1
    coef_a = -4
    coef_b = 0
    coef_c = 4
    coef_d = 0
    start_x = 0
    end_x = 1
    presetName$ = "AttackDecay"
elsif preset = 6
    # Slow Attack
    envelope_type = 1
    coef_a = 1
    coef_b = 0
    coef_c = 0
    coef_d = 0
    start_x = 0
    end_x = 1
    presetName$ = "SlowAttack"
elsif preset = 7
    # Double Pulse
    envelope_type = 2
    root_1 = -1
    root_2 = 0
    root_3 = 1
    start_x = -1
    end_x = 1
    presetName$ = "DoublePulse"
elsif preset = 8
    # Asymmetric Rise
    envelope_type = 2
    root_1 = 0
    root_2 = 2
    root_3 = 0
    start_x = 0
    end_x = 1
    presetName$ = "AsymRise"
elsif preset = 9
    # Exponential In
    envelope_type = 1
    coef_a = 0
    coef_b = 1
    coef_c = 0
    coef_d = 0
    start_x = 0
    end_x = 1
    perceptual_weight = 2.0
    presetName$ = "ExpIn"
elsif preset = 10
    # Exponential Out
    envelope_type = 1
    coef_a = 0
    coef_b = -1
    coef_c = 2
    coef_d = 0
    start_x = 0
    end_x = 1
    perceptual_weight = 2.0
    presetName$ = "ExpOut"
else
    presetName$ = "Custom"
endif

# === INFO HEADER ===
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  POLYNOMIAL SOUND SHAPER v1.0"
writeInfoLine: "=============================================="
writeInfoLine: ""
writeInfoLine: "Input: ", sound_name$, " (", fixed$(dur, 2), "s)"
writeInfoLine: "Preset: ", presetName$
writeInfoLine: ""

# === CREATE POLYNOMIAL OBJECT ===
if envelope_type = 1
    Create Polynomial: "envelope_poly", start_x, end_x, { coef_a, coef_b, coef_c, coef_d }
    writeInfoLine: "Type: Polynomial coefficients"
    writeInfoLine: "  ", coef_a, "x³ + ", coef_b, "x² + ", coef_c, "x + ", coef_d
else
    if root_3 = 0
        Create Polynomial from product terms: "envelope_poly", start_x, end_x, { root_1, root_2 }
        writeInfoLine: "Type: Polynomial from roots"
        writeInfoLine: "  (x - ", root_1, ")(x - ", root_2, ")"
    else
        Create Polynomial from product terms: "envelope_poly", start_x, end_x, { root_1, root_2, root_3 }
        writeInfoLine: "Type: Polynomial from roots"
        writeInfoLine: "  (x - ", root_1, ")(x - ", root_2, ")(x - ", root_3, ")"
    endif
endif

poly_id = selected("Polynomial")

writeInfoLine: "Domain: [", start_x, ", ", end_x, "]"
writeInfoLine: ""

# === BUILD PROCESSING FORMULA ===
# Normalized time: maps [0, dur] to [start_x, end_x]
norm_x$ = "((x/" + string$(dur) + ") * (" + string$(end_x) + " - " + string$(start_x) + ") + " + string$(start_x) + ")"

# Build polynomial string
if envelope_type = 1
    poly$ = "(" + string$(coef_a) + "*(" + norm_x$ + "^3)) + (" + string$(coef_b) + "*(" + norm_x$ + "^2)) + (" + string$(coef_c) + "*(" + norm_x$ + ")) + " + string$(coef_d)
else
    if root_3 = 0
        poly$ = "(" + norm_x$ + " - " + string$(root_1) + ") * (" + norm_x$ + " - " + string$(root_2) + ")"
    else
        poly$ = "(" + norm_x$ + " - " + string$(root_1) + ") * (" + norm_x$ + " - " + string$(root_2) + ") * (" + norm_x$ + " - " + string$(root_3) + ")"
    endif
endif

# Apply perceptual weighting with sign preservation
weight$ = string$(perceptual_weight)
thresh$ = "0.000001"

weighted$ = "if (" + poly$ + ") < 0 then -1 * (max(" + thresh$ + ", abs(" + poly$ + "))^" + weight$ + ") else (max(" + thresh$ + ", abs(" + poly$ + "))^" + weight$ + ") fi"

# Apply dynamic range clamping
minG$ = string$(min_gain)
maxG$ = string$(max_gain)

clamped$ = "if (" + weighted$ + ") < 0 then -1 * (max(" + minG$ + ", min(" + maxG$ + ", abs(" + weighted$ + ")))) else (max(" + minG$ + ", min(" + maxG$ + ", abs(" + weighted$ + ")))) fi"

# Final formula
formula$ = "self * (" + clamped$ + ")"

# === VISUALIZATION ===
if visualize
    appendInfoLine: "Creating visualization..."
    
    Erase all
    
    # === TITLE ===
    Select outer viewport: 1, 8, 0, 0.4
    Font size: 11
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Polynomial Shaper## | " + presetName$ + " | Weight: " + fixed$(perceptual_weight, 1)
    
    # === TOP: POLYNOMIAL CURVE ===
    Select outer viewport: 0, 8, 0.5, 2.5
    Select inner viewport: 0.8, 7.6, 0.7, 2.3
    
    selectObject: poly_id
    Colour: "{0.3, 0.5, 0.8}"
    Line width: 2
    Draw: start_x, end_x, 0, 0, "no", "yes"
    Line width: 1
    
    # Get actual y range for proper axes
    yMin = Get minimum: start_x, end_x
    yMax = Get maximum: start_x, end_x
    yRange = yMax - yMin
    if yRange < 0.1
        yRange = 1
    endif
    
    # Zero line
    Axes: start_x, end_x, yMin - yRange * 0.1, yMax + yRange * 0.1
    Colour: "{0.7, 0.7, 0.7}"
    Dashed line
    Draw line: start_x, 0, end_x, 0
    Solid line
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.15, 8, 0.5, 2.5
    Text left: "yes", "Polynomial"
    Text bottom: "yes", "Domain [" + fixed$(start_x, 1) + ", " + fixed$(end_x, 1) + "]"
    
    # === MIDDLE: ENVELOPE OVER TIME ===
    Select outer viewport: 0, 8, 2.6, 4.3
    Select inner viewport: 0.8, 7.6, 2.8, 4.1
    
    # Create preview envelope
    Create Sound from formula: "env_preview", 1, 0, dur, 1000, clamped$
    env_preview = selected("Sound")
    
    # Background
    Axes: 0, dur, -max_gain - 0.1, max_gain + 0.1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, dur, -max_gain - 0.1, max_gain + 0.1
    
    # Range lines
    Colour: "{0.8, 0.8, 0.8}"
    Dashed line
    Draw line: 0, max_gain, dur, max_gain
    Draw line: 0, -max_gain, dur, -max_gain
    if min_gain > 0
        Draw line: 0, min_gain, dur, min_gain
        Draw line: 0, -min_gain, dur, -min_gain
    endif
    Draw line: 0, 0, dur, 0
    Solid line
    
    # Envelope curve
    selectObject: env_preview
    Colour: "{0.3, 0.7, 0.3}"
    Line width: 2
    Draw: 0, dur, -max_gain - 0.1, max_gain + 0.1, "no", "Curve"
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.15, 8, 2.6, 4.3
    Text left: "yes", "Envelope"
    
    removeObject: env_preview
    
    # === BOTTOM: RESULT PREVIEW ===
    Select outer viewport: 0, 8, 4.4, 5.8
    Select inner viewport: 0.8, 7.6, 4.5, 5.6
    
    # Create processed preview
    selectObject: sound
    result_preview = Copy: "preview"
    Formula: formula$
    if normalize
        Scale peak: 0.95
    endif
    
    Colour: "{0.5, 0.4, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.15, 8, 4.4, 5.8
    Text left: "yes", "Result"
    Text bottom: "yes", "Time (s)"
    
    removeObject: result_preview
    
    # === INFO BAR ===
    Select outer viewport: 0, 8, 5.9, 6.3
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Range: " + fixed$(min_gain, 2) + " to " + fixed$(max_gain, 2) + " | Perceptual weight: " + fixed$(perceptual_weight, 1)
    
    Font size: 10
    Colour: "Black"
endif

# === PROCESS AUDIO ===
appendInfoLine: ""
appendInfoLine: "Processing..."

selectObject: sound
result = Copy: sound_name$ + "_shaped"

Formula: formula$

if normalize
    Scale peak: 0.95
endif

# === CLEANUP ===
removeObject: poly_id

# === OUTPUT ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE: ", selected$("Sound")
writeInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Perceptual weight: ", perceptual_weight
if perceptual_weight = 1.0
    appendInfoLine: "  → Linear amplitude"
elsif perceptual_weight >= 2.0 and perceptual_weight <= 3.0
    appendInfoLine: "  → Perceived loudness"
else
    appendInfoLine: "  → Custom power law"
endif
appendInfoLine: ""
appendInfoLine: "Dynamic range: ", min_gain, " to ", max_gain
if min_gain > 0
    appendInfoLine: "  Floor: ", fixed$(20 * log10(min_gain), 1), " dB"
endif
if max_gain < 1
    appendInfoLine: "  Ceiling: ", fixed$(20 * log10(max_gain), 1), " dB"
endif

if play
    appendInfoLine: ""
    appendInfoLine: "Playing..."
    Play
endif

selectObject: result