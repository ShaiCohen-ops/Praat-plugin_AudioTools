# ============================================================
# Praat AudioTools - Distortion___Bit-Crusher.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Distortion & Bit-Crusher Suite — two distinct effect modes:
#
#   (1) Bit Crusher: amplitude quantization. Maps each sample to
#       the nearest of N evenly-spaced levels, producing a
#       staircase transfer function. Lower N = harsher lo-fi
#       character, with audible step-quantization noise.
#
#   (2) Harsh Distortion: replaces the input waveform entirely
#       with a synthesized texture whose ONLY connection to the
#       input is the sample-by-sample SIGN (positive vs negative).
#       The result is a square-wave-like signal modulated by an
#       AM oscillator and a periodic gate. The original waveform's
#       amplitude information is discarded; only zero-crossings
#       remain. This is intentionally extreme — useful for
#       industrial / glitch / noise applications.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.3:
#   - Fix (Harsh mode gate logic): v0.2's gate condition was
#       if (x mod gate_period > gate_duty) then 1 else 0 fi
#     which made gate_duty represent the SILENT portion at the
#     start of each cycle, not the ON portion as the parameter
#     name implied. v0.3 flips the comparison:
#       if (x mod gate_period < gate_duty) then 1 else 0 fi
#     so gate_duty_cycle_s now genuinely means "how long the gate
#     is open per cycle," matching the parameter name.
#     Audible effect on sustained sources: identical (the gate
#     pattern is phase-shifted by half a period — same on/off
#     ratio, same modulation rate). Audible effect on transient
#     onsets in the first ~milliseconds: original v0.2 silenced
#     them; v0.3 keeps them. Bit Crusher mode is unchanged.
#   - Form syntax modernized: optionmenu and choice use colons.
#   - Visualization rewritten to suite 8x8 standard:
#       Title bar + metadata subtitle
#       Panel A (left, headline): mode-specific diagnostic —
#         staircase transfer function (Bit Crusher) or
#         component diagram (Harsh Distortion)
#       Panel B (right, headline): parameter report
#       Panel C: zoom overlay (original gray + result colored,
#         first 30 ms) — replaces v0.2's two side-by-side zoom
#         panels with a single overlaid panel that makes the
#         comparison immediately visible
#       Panel D: output waveform (full file, L/R distinguished)
#       Panel E: summary stats bar
#   - Both Bit Crusher and Harsh Distortion modes' AUDIO
#     pipelines are otherwise unchanged. Bit Crusher output is
#     bit-identical to v0.2. Harsh Distortion output for
#     sustained material is essentially identical (phase-shifted
#     gate); transient onsets handled differently per fix above.
# Changelog v0.2:
#   - Added visualization
#   - Improved preset organization
#   - Added detailed info output
# ============================================================

form Distortion and Bit-Crusher Suite v0.3
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset: 1
        option Custom (use settings below)
        option Bit Crush: Default (4 levels)
        option Bit Crush: Mild (8 levels)
        option Bit Crush: Lo-Fi (3 levels)
        option Bit Crush: Extreme (2 levels)
        option Harsh: Balanced
        option Harsh: Light Drive
        option Harsh: Industrial
        option Harsh: Stutter Gate
    
    comment === Mode Selection ===
    choice Effect_type: 1
        button Bit Crusher
        button Harsh Distortion
    
    comment === Bit Crusher Parameters ===
    positive Quantization_levels 4
    comment (2=extreme, 8=mild, 16=subtle)
    
    comment === Harsh Distortion Parameters ===
    positive Base_amplitude 0.5
    positive Mod_amplitude 0.3
    positive Mod_frequency_Hz 100
    positive Gate_period_s 0.05
    positive Gate_duty_cycle_s 0.025
    
    comment === Output ===
    positive Scale_peak 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
original_name$ = selected$("Sound")

selectObject: original
duration = Get total duration
sr = Get sampling frequency
input_n_channels = Get number of channels

# === Apply Presets ===
if preset = 2
    effect_type = 1
    quantization_levels = 4
    presetName$ = "BC_Default"
elsif preset = 3
    effect_type = 1
    quantization_levels = 8
    presetName$ = "BC_Mild"
elsif preset = 4
    effect_type = 1
    quantization_levels = 3
    presetName$ = "BC_LoFi"
elsif preset = 5
    effect_type = 1
    quantization_levels = 2
    presetName$ = "BC_Extreme"
elsif preset = 6
    effect_type = 2
    base_amplitude = 0.5
    mod_amplitude = 0.3
    mod_frequency_Hz = 100
    gate_period_s = 0.05
    gate_duty_cycle_s = 0.025
    presetName$ = "HD_Balanced"
elsif preset = 7
    effect_type = 2
    base_amplitude = 0.4
    mod_amplitude = 0.2
    mod_frequency_Hz = 80
    gate_period_s = 0.07
    gate_duty_cycle_s = 0.035
    presetName$ = "HD_Light"
elsif preset = 8
    effect_type = 2
    base_amplitude = 0.7
    mod_amplitude = 0.4
    mod_frequency_Hz = 150
    gate_period_s = 0.03
    gate_duty_cycle_s = 0.015
    presetName$ = "HD_Industrial"
elsif preset = 9
    effect_type = 2
    base_amplitude = 0.6
    mod_amplitude = 0.25
    mod_frequency_Hz = 90
    gate_period_s = 0.02
    gate_duty_cycle_s = 0.01
    presetName$ = "HD_Stutter"
else
    presetName$ = "Custom"
endif

# Get mode name and suffix
if effect_type = 1
    modeName$ = "BitCrusher"
    modeNameDisplay$ = "Bit Crusher"
    suffix$ = "_crushed"
else
    modeName$ = "HarshDistortion"
    modeNameDisplay$ = "Harsh Distortion"
    suffix$ = "_harsh"
endif

# === Info ===
writeInfoLine: "=== Distortion & Bit-Crusher Suite v0.3 ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(duration, 2), " s, ", input_n_channels, " ch)"
appendInfoLine: "Mode: ", modeNameDisplay$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""

if effect_type = 1
    appendInfoLine: "Quantization levels: ", quantization_levels
    appendInfoLine: "Effective bits: ~", fixed$(ln(quantization_levels)/ln(2), 1)
else
    appendInfoLine: "Base amplitude: ", fixed$(base_amplitude, 2)
    appendInfoLine: "Mod amplitude: ", fixed$(mod_amplitude, 2)
    appendInfoLine: "Mod frequency: ", fixed$(mod_frequency_Hz, 0), " Hz"
    appendInfoLine: "Gate period: ", fixed$(gate_period_s * 1000, 1), " ms"
    appendInfoLine: "Gate duty: ", fixed$(gate_duty_cycle_s * 1000, 1), " ms (",
        ... fixed$(gate_duty_cycle_s / gate_period_s * 100, 0), "% open)"
endif
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

appendInfoLine: "Processing..."

selectObject: original
Copy: original_name$ + suffix$ + "_" + presetName$
result = selected("Sound")

if effect_type = 1
    # === BIT CRUSHER ===
    # round(x * levels) / levels — quantize to evenly-spaced levels
    q_str$ = string$(quantization_levels)
    selectObject: result
    Formula: "round(self * " + q_str$ + ") / " + q_str$
    
else
    # === HARSH DISTORTION ===
    # sign(x) * (base + mod*sin(omega*t)) * gate
    #
    # FIX v0.3: gate condition flipped from "> duty" (v0.2 — duty
    # was actually the silent portion) to "< duty" (v0.3 — duty
    # is now the open portion, matching the parameter name).
    
    base$ = string$(base_amplitude)
    mod_amp$ = string$(mod_amplitude)
    mod_freq$ = string$(mod_frequency_Hz)
    gate_per$ = string$(gate_period_s)
    gate_duty$ = string$(gate_duty_cycle_s)
    
    selectObject: result
    Formula: "if self > 0 then 1 else -1 fi"
        ... + " * (" + base$ + " + " + mod_amp$ + " * sin(2*pi*" + mod_freq$ + " * x))"
        ... + " * (if (x mod " + gate_per$ + " < " + gate_duty$ + ") then 1 else 0 fi)"
endif

# Scale output
selectObject: result
Scale peak: scale_peak

# === Final stats ===
selectObject: result
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"
nResultCh = Get number of channels

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================

if draw_visualization
    Erase all
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##DISTORTION & BIT-CRUSHER SUITE##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    if effect_type = 1
        Text: 0.5, "centre", -0.22, "half",
            ... original_name$
            ... + "  |  " + modeNameDisplay$
            ... + "  |  " + presetName$
            ... + "  |  Levels: " + string$(quantization_levels)
            ... + "  |  Effective bits: ~" + fixed$(ln(quantization_levels)/ln(2), 1)
    else
        Text: 0.5, "centre", -0.22, "half",
            ... original_name$
            ... + "  |  " + modeNameDisplay$
            ... + "  |  " + presetName$
            ... + "  |  Base+Mod: " + fixed$(base_amplitude, 2) + "+" + fixed$(mod_amplitude, 2)
            ... + " @ " + fixed$(mod_frequency_Hz, 0) + " Hz"
            ... + "  |  Gate: " + fixed$(gate_period_s * 1000, 0) + "/"
            ... + fixed$(gate_duty_cycle_s * 1000, 0) + " ms"
    endif
    
    # ----------------------------------------------------------
    # PANEL A: MODE-SPECIFIC DIAGNOSTIC  (left, headline)
    # Bit Crusher: staircase transfer function
    # Harsh Distortion: component pipeline diagram
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40
    
    if effect_type = 1
        # ==== BIT CRUSHER STAIRCASE ====
        Axes: -1.2, 1.2, -1.2, 1.2
        Paint rectangle: "{0.96, 0.96, 0.96}", -1.2, 1.2, -1.2, 1.2
        
        # Grid
        Colour: "{0.85, 0.85, 0.88}"
        Line width: 1
        Draw line: -1.2, 0, 1.2, 0
        Draw line: 0, -1.2, 0, 1.2
        
        # y=x reference
        Dotted line
        Colour: "{0.65, 0.65, 0.70}"
        Draw line: -1.2, -1.2, 1.2, 1.2
        Solid line
        
        # Draw staircase
        Colour: "{0.30, 0.50, 0.78}"
        Line width: 2
        step = 1 / quantization_levels
        for i from -quantization_levels to quantization_levels
            xStart = (i - 0.5) * step
            xEnd = (i + 0.5) * step
            yVal = i * step
            
            if xStart < -1
                xStart = -1
            endif
            if xEnd > 1
                xEnd = 1
            endif
            
            if xStart < xEnd
                Draw line: xStart, yVal, xEnd, yVal
            endif
        endfor
        
        # Vertical risers between steps (so it looks like a true staircase)
        Colour: "{0.55, 0.70, 0.85}"
        Line width: 1
        for i from -quantization_levels to quantization_levels - 1
            xRiser = (i + 0.5) * step
            yLow = i * step
            yHigh = (i + 1) * step
            if xRiser >= -1 and xRiser <= 1 and yLow >= -1.1 and yHigh <= 1.1
                Draw line: xRiser, yLow, xRiser, yHigh
            endif
        endfor
        Line width: 1
        
        Colour: "Black"
        Draw inner box
        Font size: 6
        Text left: "yes", "Output"
        Text bottom: "yes", "Input"
        
    else
        # ==== HARSH DISTORTION COMPONENT DIAGRAM ====
        Axes: 0, 1, 0, 6
        Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 6
        
        # Five vertical stages (input -> sign -> mod -> gate -> output)
        # Stage 1: Input
        yTop = 5.6
        yBot = 5.0
        Paint rectangle: "{0.85, 0.85, 0.88}", 0.10, 0.90, yBot, yTop
        Colour: "Black"
        Font size: 8
        Text: 0.50, "centre", (yTop + yBot) / 2 + 0.10, "half", "INPUT"
        Font size: 7
        Colour: "{0.45, 0.45, 0.45}"
        Text: 0.50, "centre", (yTop + yBot) / 2 - 0.13, "half", "(audio)"
        
        Colour: "{0.45, 0.45, 0.45}"
        Draw arrow: 0.50, 5.0, 0.50, 4.7
        
        # Stage 2: Sign extraction
        yTop = 4.6
        yBot = 4.0
        Paint rectangle: "{0.85, 0.65, 0.65}", 0.10, 0.90, yBot, yTop
        Colour: "Black"
        Font size: 8
        Text: 0.50, "centre", (yTop + yBot) / 2 + 0.10, "half", "SIGN(x)"
        Font size: 7
        Colour: "{0.40, 0.15, 0.15}"
        Text: 0.50, "centre", (yTop + yBot) / 2 - 0.13, "half", "+/- 1"
        
        Colour: "{0.45, 0.45, 0.45}"
        Draw arrow: 0.50, 4.0, 0.50, 3.7
        
        # Stage 3: AM
        yTop = 3.6
        yBot = 3.0
        Paint rectangle: "{0.65, 0.85, 0.65}", 0.10, 0.90, yBot, yTop
        Colour: "Black"
        Font size: 8
        Text: 0.50, "centre", (yTop + yBot) / 2 + 0.10, "half", "AM"
        Font size: 7
        Colour: "{0.15, 0.40, 0.15}"
        Text: 0.50, "centre", (yTop + yBot) / 2 - 0.13, "half",
            ... fixed$(base_amplitude, 2) + " + " + fixed$(mod_amplitude, 2)
            ... + "*sin(" + fixed$(mod_frequency_Hz, 0) + " Hz)"
        
        Colour: "{0.45, 0.45, 0.45}"
        Draw arrow: 0.50, 3.0, 0.50, 2.7
        
        # Stage 4: Gate
        yTop = 2.6
        yBot = 2.0
        Paint rectangle: "{0.65, 0.65, 0.85}", 0.10, 0.90, yBot, yTop
        Colour: "Black"
        Font size: 8
        Text: 0.50, "centre", (yTop + yBot) / 2 + 0.10, "half", "GATE"
        Font size: 7
        Colour: "{0.15, 0.15, 0.40}"
        Text: 0.50, "centre", (yTop + yBot) / 2 - 0.13, "half",
            ... fixed$(gate_duty_cycle_s * 1000, 1) + "/"
            ... + fixed$(gate_period_s * 1000, 1) + " ms ("
            ... + fixed$(gate_duty_cycle_s / gate_period_s * 100, 0) + "% open)"
        
        Colour: "{0.45, 0.45, 0.45}"
        Draw arrow: 0.50, 2.0, 0.50, 1.7
        
        # Stage 5: Output
        yTop = 1.6
        yBot = 1.0
        Paint rectangle: "{0.65, 0.85, 0.75}", 0.10, 0.90, yBot, yTop
        Colour: "Black"
        Font size: 8
        Text: 0.50, "centre", (yTop + yBot) / 2 + 0.10, "half", "OUTPUT"
        Font size: 7
        Colour: "{0.15, 0.40, 0.30}"
        Text: 0.50, "centre", (yTop + yBot) / 2 - 0.13, "half", "(harsh)"
        
        # Formula at bottom
        Font size: 6
        Colour: "{0.35, 0.35, 0.45}"
        Text: 0.50, "centre", 0.50, "half", "y = sign(x) x AM(t) x gate(t)"
        
        Colour: "Black"
        Draw inner box
    endif
    
    # ----------------------------------------------------------
    # PANEL B: PARAMETER REPORT  (right, headline-height)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.55, 7.75, 0.95, 4.40
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 1
    
    if effect_type = 1
        # ==== BIT CRUSHER PARAMS ====
        Font size: 9
        Colour: "{0.30, 0.30, 0.30}"
        Text: 0.05, "left", 0.92, "half", "Mode: Bit Crusher"
        
        Font size: 11
        Colour: "{0.30, 0.45, 0.78}"
        Text: 0.10, "left", 0.82, "half", "Levels:  " + string$(quantization_levels)
        Text: 0.10, "left", 0.74, "half", "Bits:    ~" + fixed$(ln(quantization_levels)/ln(2), 1)
        
        # Character guide
        Font size: 9
        Colour: "{0.30, 0.30, 0.30}"
        Text: 0.05, "left", 0.60, "half", "Character guide:"
        
        Font size: 8
        Colour: "{0.55, 0.55, 0.55}"
        Text: 0.10, "left", 0.51, "half", "2 levels:  extreme square"
        Text: 0.10, "left", 0.43, "half", "3-4 lvl:  heavy lo-fi"
        Text: 0.10, "left", 0.35, "half", "8 lvl:    mild crush"
        Text: 0.10, "left", 0.27, "half", "16+ lvl:  subtle"
        
        # Highlight current setting in the guide
        Font size: 7
        Colour: "{0.78, 0.30, 0.30}"
        if quantization_levels <= 2
            Text: 0.10, "left", 0.16, "half", "(current: extreme)"
        elsif quantization_levels <= 4
            Text: 0.10, "left", 0.16, "half", "(current: heavy lo-fi)"
        elsif quantization_levels <= 8
            Text: 0.10, "left", 0.16, "half", "(current: mild crush)"
        else
            Text: 0.10, "left", 0.16, "half", "(current: subtle)"
        endif
    else
        # ==== HARSH DISTORTION PARAMS ====
        Font size: 9
        Colour: "{0.30, 0.30, 0.30}"
        Text: 0.05, "left", 0.92, "half", "Mode: Harsh Distortion"
        
        Font size: 9
        Colour: "{0.30, 0.30, 0.30}"
        Text: 0.05, "left", 0.82, "half", "Amplitude:"
        
        Font size: 11
        Colour: "{0.30, 0.45, 0.78}"
        Text: 0.10, "left", 0.74, "half", "Base:    " + fixed$(base_amplitude, 2)
        Text: 0.10, "left", 0.66, "half", "Mod:     " + fixed$(mod_amplitude, 2)
        
        Font size: 9
        Colour: "{0.30, 0.30, 0.30}"
        Text: 0.05, "left", 0.55, "half", "Modulator:"
        
        Font size: 11
        Colour: "{0.78, 0.50, 0.30}"
        Text: 0.10, "left", 0.47, "half", "Freq:    " + fixed$(mod_frequency_Hz, 0) + " Hz"
        
        Font size: 9
        Colour: "{0.30, 0.30, 0.30}"
        Text: 0.05, "left", 0.36, "half", "Gate:"
        
        Font size: 11
        Colour: "{0.40, 0.65, 0.40}"
        Text: 0.10, "left", 0.28, "half", "Period:  " + fixed$(gate_period_s * 1000, 1) + " ms"
        Text: 0.10, "left", 0.20, "half", "Open:    " + fixed$(gate_duty_cycle_s * 1000, 1) + " ms"
        
        Font size: 8
        Colour: "{0.55, 0.55, 0.55}"
        Text: 0.10, "left", 0.10, "half", "(" + fixed$(gate_duty_cycle_s / gate_period_s * 100, 0) + "% duty cycle)"
    endif
    
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
    if effect_type = 1
        Text: 2.10, "centre", 7.30, "half", "Quantization staircase"
    else
        Text: 2.10, "centre", 7.30, "half", "Component pipeline"
    endif
    Text: 6.10, "centre", 7.30, "half", "Parameter report"
    
    # ----------------------------------------------------------
    # PANEL C: ZOOM OVERLAY  (full width, first 30 ms)
    # Original (gray) and result (mode color) overlaid.
    # Reveals quantization steps (BC) or gate pattern (HD)
    # that the full-file waveform can't show clearly.
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.55, 7.72, 4.75, 5.48
    
    zoomDur = 0.03
    if zoomDur > duration
        zoomDur = duration
    endif
    
    selectObject: original
    origPeak = Get absolute extremum: 0, zoomDur, "None"
    selectObject: result
    resPeak = Get absolute extremum: 0, zoomDur, "None"
    zoomMax = origPeak
    if resPeak > zoomMax
        zoomMax = resPeak
    endif
    if zoomMax < 0.001
        zoomMax = 0.001
    endif
    zAmpViz = zoomMax * 1.15
    
    Axes: 0, zoomDur, -zAmpViz, zAmpViz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, zoomDur, -zAmpViz, zAmpViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, zoomDur, 0
    
    # Original (gray, behind)
    selectObject: original
    if input_n_channels > 1
        Extract one channel: 1
        zOrig = selected("Sound")
        Colour: "{0.65, 0.65, 0.65}"
        Line width: 1
        Draw: 0, zoomDur, -zAmpViz, zAmpViz, "no", "Curve"
        removeObject: zOrig
    else
        Colour: "{0.65, 0.65, 0.65}"
        Line width: 1
        Draw: 0, zoomDur, -zAmpViz, zAmpViz, "no", "Curve"
    endif
    
    # Result (colored, on top)
    selectObject: result
    if effect_type = 1
        modeColor$ = "{0.30, 0.50, 0.78}"
    else
        modeColor$ = "{0.78, 0.40, 0.40}"
    endif
    if nResultCh > 1
        Extract one channel: 1
        zRes = selected("Sound")
        Colour: modeColor$
        Line width: 1.3
        Draw: 0, zoomDur, -zAmpViz, zAmpViz, "no", "Curve"
        removeObject: zRes
    else
        Colour: modeColor$
        Line width: 1.3
        Draw: 0, zoomDur, -zAmpViz, zAmpViz, "no", "Curve"
    endif
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Zoom: first " + fixed$(zoomDur * 1000, 0) + " ms  (gray = original, color = " + modeNameDisplay$ + ")"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL D: OUTPUT WAVEFORM (full file)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 6.55
    Select inner viewport: 0.55, 7.72, 5.69, 6.48
    
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
        Colour: modeColor$
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
        Text top: "no", "Output (full file)  (blue=L  orange=R)"
    else
        Text top: "no", "Output (full file, mono)"
    endif
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.62, 7.30
    Select inner viewport: 0.55, 7.72, 6.68, 7.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    if effect_type = 1
        Text: 0.02, "left", 0.75, "half",
            ... "##" + presetName$ + "##"
            ... + "  " + original_name$
            ... + "  |  Mode: Bit Crusher"
            ... + "  |  Levels: " + string$(quantization_levels)
            ... + "  |  Effective bits: ~" + fixed$(ln(quantization_levels)/ln(2), 1)
        
        Text: 0.02, "left", 0.28, "half",
            ... "Scale peak: " + fixed$(scale_peak, 2)
            ... + "  |  Output: " + fixed$(finalDur, 2) + " s, peak " + fixed$(finalPeak, 3)
    else
        Text: 0.02, "left", 0.75, "half",
            ... "##" + presetName$ + "##"
            ... + "  " + original_name$
            ... + "  |  Mode: Harsh Distortion"
            ... + "  |  Base: " + fixed$(base_amplitude, 2)
            ... + "  |  Mod: " + fixed$(mod_amplitude, 2) + " @ " + fixed$(mod_frequency_Hz, 0) + " Hz"
        
        Text: 0.02, "left", 0.28, "half",
            ... "Gate: " + fixed$(gate_duty_cycle_s * 1000, 1) + "/"
            ... + fixed$(gate_period_s * 1000, 1) + " ms ("
            ... + fixed$(gate_duty_cycle_s / gate_period_s * 100, 0) + "% open)"
            ... + "  |  Scale peak: " + fixed$(scale_peak, 2)
            ... + "  |  Output: " + fixed$(finalDur, 2) + " s, peak " + fixed$(finalPeak, 3)
    endif
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(finalDur, 2), " s"
appendInfoLine: "Peak: ", fixed$(finalPeak, 4)

if play_result
    selectObject: result
    Play
endif

selectObject: result
