# ============================================================
# Praat AudioTools - Unified_Chorus_Generator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.2 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Unified Chorus Generator - flexible chorus/ensemble effect
#   offering Dual Tap (2-voice), Tri Tap (3-voice), and Orbit
#   (counter-rotating phase drift) modes. Creates thickening,
#   spatial movement, and ensemble effects.
#
# Changelog v2.2:
#   - VISUALIZATION STANDARDIZATION ONLY; audio/DSP, analysis,
#     parameter mapping and rendering logic are unchanged.
#   - Standardized title/version, Picture-page restoration,
#     typography and summary/export behavior for AudioTools.
#
# Changelog v2.1:
#   - Fixed input check
#   - Fixed formula syntax (use object IDs)
#   - Added bounds checking
#   - Added visualization
#   - Added info output
# ============================================================

form Unified Chorus Generator v2.2
    comment Select a Sound object first
    
    comment === Mode Selection ===
    choice Chorus_Mode 2
        button Dual Tap (Standard 2-Voice)
        button Tri Tap (Rich 3-Voice)
        button Orbit (Counter-Rotating Phase)
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Subtle Chorus
        option Classic Chorus
        option Rich Ensemble
        option Deep Shimmer
        option Space Orbit (Orbit Mode)
    
    comment === Signal Balance ===
    positive Dry_Mix 0.7
    positive Wet_Mix 0.5
    
    comment === Delay Settings ===
    positive Base_delay_ms 10.0
    positive Modulation_depth 0.15
    
    comment === LFO Rates (Hz) ===
    positive Rate_1 2.5
    positive Rate_2 4.2
    positive Rate_3 6.3
    
    comment === Orbit Settings (Mode 3 Only) ===
    positive Phase_drift_hz 0.2
    
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

# ============================================================
# PRESET LOGIC
# ============================================================

if preset = 2
    # Subtle
    base_delay_ms = 8.0
    modulation_depth = 0.08
    rate_1 = 2.0
    rate_2 = 3.5
    rate_3 = 5.0
    presetName$ = "Subtle"
elsif preset = 3
    # Classic
    base_delay_ms = 12.0
    modulation_depth = 0.15
    rate_1 = 2.5
    rate_2 = 4.2
    rate_3 = 6.3
    presetName$ = "Classic"
elsif preset = 4
    # Rich Ensemble
    base_delay_ms = 15.0
    modulation_depth = 0.2
    rate_1 = 1.5
    rate_2 = 3.8
    rate_3 = 5.5
    presetName$ = "RichEnsemble"
elsif preset = 5
    # Deep Shimmer
    base_delay_ms = 20.0
    modulation_depth = 0.25
    rate_1 = 0.8
    rate_2 = 2.4
    rate_3 = 4.0
    presetName$ = "DeepShimmer"
elsif preset = 6
    # Space Orbit
    chorus_Mode = 3
    base_delay_ms = 10.0
    modulation_depth = 0.2
    rate_1 = 3.0 
    phase_drift_hz = 0.15
    presetName$ = "SpaceOrbit"
else
    presetName$ = "Custom"
endif

# Get mode name
if chorus_Mode = 1
    modeName$ = "DualTap"
    suffix$ = "_chorus_dual"
elsif chorus_Mode = 2
    modeName$ = "TriTap"
    suffix$ = "_chorus_tri"
else
    modeName$ = "Orbit"
    suffix$ = "_chorus_orbit"
endif

# Calculate base delay in samples
base = round(base_delay_ms * sr / 1000)

# === Info ===
writeInfoLine: "=== Unified Chorus Generator v2.2 ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Mode: ", modeName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Delay: ", base_delay_ms, " ms (", base, " samples)"
appendInfoLine: "Depth: ", modulation_depth
appendInfoLine: "Dry/Wet: ", dry_Mix, " / ", wet_Mix
appendInfoLine: ""

if chorus_Mode = 1
    appendInfoLine: "Rates: ", rate_1, " Hz, ", rate_2, " Hz"
elsif chorus_Mode = 2
    appendInfoLine: "Rates: ", rate_1, " Hz, ", rate_2, " Hz, ", rate_3, " Hz"
else
    appendInfoLine: "Rate: ", rate_1, " Hz, Drift: ±", phase_drift_hz, " Hz"
endif
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

appendInfoLine: "Applying ", modeName$, " chorus..."

selectObject: original
Copy: original_name$ + suffix$ + "_" + presetName$
result = selected("Sound")

# Build formula strings
orig_str$ = string$(original)
base_str$ = string$(base)
depth_str$ = string$(modulation_depth)
dry_str$ = string$(dry_Mix)
wet_str$ = string$(wet_Mix)
rate1_str$ = string$(rate_1)
rate2_str$ = string$(rate_2)
rate3_str$ = string$(rate_3)
drift_str$ = string$(phase_drift_hz)

if chorus_Mode = 1
    # DUAL TAP (Standard 2-voice)
    # Tap 1: rate_1, phase 0
    # Tap 2: rate_2, phase +2 rad
    
    tap1$ = "object[" + orig_str$ + ", max(1, min(ncol, col - round(" + base_str$ + " * (1 + " + depth_str$ + " * sin(2*pi*" + rate1_str$ + "*x)))))]"
    tap2$ = "object[" + orig_str$ + ", max(1, min(ncol, col - round(" + base_str$ + " * (1 + " + depth_str$ + " * sin(2*pi*" + rate2_str$ + "*x + 2.0)))))]"
    
    Formula: "self * " + dry_str$ + " + " + wet_str$ + " * (" + tap1$ + " + " + tap2$ + ") / 2"

elsif chorus_Mode = 2
    # TRI TAP (Rich 3-voice)
    # Tap 1: rate_1, phase 0
    # Tap 2: rate_2, phase +2.1 rad
    # Tap 3: rate_3, phase +4.2 rad
    
    tap1$ = "object[" + orig_str$ + ", max(1, min(ncol, col - round(" + base_str$ + " * (1 + " + depth_str$ + " * sin(2*pi*" + rate1_str$ + "*x)))))]"
    tap2$ = "object[" + orig_str$ + ", max(1, min(ncol, col - round(" + base_str$ + " * (1 + " + depth_str$ + " * sin(2*pi*" + rate2_str$ + "*x + 2.1)))))]"
    tap3$ = "object[" + orig_str$ + ", max(1, min(ncol, col - round(" + base_str$ + " * (1 + " + depth_str$ + " * sin(2*pi*" + rate3_str$ + "*x + 4.2)))))]"
    
    Formula: "self * " + dry_str$ + " + " + wet_str$ + " * (" + tap1$ + " + " + tap2$ + " + " + tap3$ + ") / 3"

elsif chorus_Mode = 3
    # ORBIT (Counter-rotating phase)
    # Tap 1: rate_1 + drift (phase drifts forward)
    # Tap 2: rate_1 - drift (phase drifts backward), with pi phase offset
    
    tap1$ = "object[" + orig_str$ + ", max(1, min(ncol, col - round(" + base_str$ + " * (1 + " + depth_str$ + " * sin(2*pi*" + rate1_str$ + "*x + 2*pi*" + drift_str$ + "*x)))))]"
    tap2$ = "object[" + orig_str$ + ", max(1, min(ncol, col - round(" + base_str$ + " * (1 + " + depth_str$ + " * sin(2*pi*" + rate1_str$ + "*x - 2*pi*" + drift_str$ + "*x + 3.14)))))]"
    
    Formula: "self * " + dry_str$ + " + " + wet_str$ + " * (" + tap1$ + " + " + tap2$ + ") / 2"

endif

# Scale output
selectObject: result
Scale peak: scale_peak

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    pageHeight = 6.6
    Erase all

    # === Standard header ===
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Unified Chorus Generator v2.2##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", original_name$ + "  |  " + presetName$ + "  |  " + modeName$

    # Input waveform
    Select outer viewport: 0, 4, 0.65, 1.65
    Select inner viewport: 0.60, 3.85, 0.78, 1.52
    selectObject: original
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"

    # Output waveform
    Select outer viewport: 4, 8, 0.65, 1.65
    Select inner viewport: 4.45, 7.70, 0.78, 1.52
    selectObject: result
    Colour: "{0.22, 0.46, 0.82}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"

    # LFO trajectories: the actual delay-control laws used by the selected mode
    Select outer viewport: 0, 8, 1.85, 3.35
    Select inner viewport: 0.60, 7.70, 2.00, 3.20
    vizDur = min(2, duration)
    nPoints = 400
    Axes: 0, vizDur, -1.05, 1.05
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, vizDur, -1.05, 1.05
    Colour: "{0.82, 0.82, 0.82}"
    Dotted line
    Draw line: 0, 0, vizDur, 0
    Solid line
    Line width: 1.5

    if chorus_Mode = 1
        Colour: "{0.22, 0.46, 0.82}"
        for p from 2 to nPoints
            t1 = (p - 2) / (nPoints - 1) * vizDur
            t2 = (p - 1) / (nPoints - 1) * vizDur
            y1 = sin(2*pi*rate_1*t1)
            y2 = sin(2*pi*rate_1*t2)
            Draw line: t1, y1, t2, y2
        endfor
        Colour: "{0.65, 0.35, 0.55}"
        for p from 2 to nPoints
            t1 = (p - 2) / (nPoints - 1) * vizDur
            t2 = (p - 1) / (nPoints - 1) * vizDur
            y1 = sin(2*pi*rate_2*t1 + 2.0)
            y2 = sin(2*pi*rate_2*t2 + 2.0)
            Draw line: t1, y1, t2, y2
        endfor
        trajectoryLabel$ = "Dual tap: two independent delay trajectories"
    elsif chorus_Mode = 2
        Colour: "{0.22, 0.46, 0.82}"
        for p from 2 to nPoints
            t1 = (p - 2) / (nPoints - 1) * vizDur
            t2 = (p - 1) / (nPoints - 1) * vizDur
            y1 = sin(2*pi*rate_1*t1)
            y2 = sin(2*pi*rate_1*t2)
            Draw line: t1, y1, t2, y2
        endfor
        Colour: "{0.30, 0.62, 0.42}"
        for p from 2 to nPoints
            t1 = (p - 2) / (nPoints - 1) * vizDur
            t2 = (p - 1) / (nPoints - 1) * vizDur
            y1 = sin(2*pi*rate_2*t1 + 2.1)
            y2 = sin(2*pi*rate_2*t2 + 2.1)
            Draw line: t1, y1, t2, y2
        endfor
        Colour: "{0.65, 0.35, 0.55}"
        for p from 2 to nPoints
            t1 = (p - 2) / (nPoints - 1) * vizDur
            t2 = (p - 1) / (nPoints - 1) * vizDur
            y1 = sin(2*pi*rate_3*t1 + 4.2)
            y2 = sin(2*pi*rate_3*t2 + 4.2)
            Draw line: t1, y1, t2, y2
        endfor
        trajectoryLabel$ = "Tri tap: three phase-separated delay trajectories"
    else
        Colour: "{0.22, 0.46, 0.82}"
        for p from 2 to nPoints
            t1 = (p - 2) / (nPoints - 1) * vizDur
            t2 = (p - 1) / (nPoints - 1) * vizDur
            y1 = sin(2*pi*rate_1*t1 + 2*pi*phase_drift_hz*t1)
            y2 = sin(2*pi*rate_1*t2 + 2*pi*phase_drift_hz*t2)
            Draw line: t1, y1, t2, y2
        endfor
        Colour: "{0.65, 0.35, 0.55}"
        for p from 2 to nPoints
            t1 = (p - 2) / (nPoints - 1) * vizDur
            t2 = (p - 1) / (nPoints - 1) * vizDur
            y1 = sin(2*pi*rate_1*t1 - 2*pi*phase_drift_hz*t1 + pi)
            y2 = sin(2*pi*rate_1*t2 - 2*pi*phase_drift_hz*t2 + pi)
            Draw line: t1, y1, t2, y2
        endfor
        trajectoryLabel$ = "Orbit: counter-rotating phase-drift trajectories"
    endif
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "LFO"
    Text bottom: "yes", "Time (s)"
    Font size: 6
    Text top: "no", trajectoryLabel$

    # Transformation law / routing diagram
    Select outer viewport: 0, 8, 3.55, 5.05
    Select inner viewport: 0.60, 7.70, 3.70, 4.92
    Axes: 0, 10, 0, 3
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 10, 0, 3
    Font size: 6
    Colour: "Black"

    Paint rectangle: "{0.88, 0.88, 0.88}", 0.3, 1.5, 1.2, 1.8
    Text: 0.9, "centre", 1.5, "half", "Input"
    Draw arrow: 1.5, 1.5, 2.3, 2.35
    Draw arrow: 1.5, 1.5, 2.3, 1.5

    # Dry branch
    Colour: "{0.55, 0.55, 0.55}"
    Text: 2.8, "centre", 2.35, "half", "Dry x " + fixed$(dry_Mix, 2)
    Draw arrow: 3.4, 2.35, 7.0, 1.7

    # Wet branch explicitly represents the average of modulated taps
    Colour: "{0.22, 0.46, 0.82}"
    Paint rectangle: "{0.90, 0.94, 0.98}", 2.3, 5.5, 0.65, 1.65
    Colour: "Black"
    if chorus_Mode = 1
        Text: 3.9, "centre", 1.28, "half", "2 delay taps / 2"
        Text: 3.9, "centre", 0.92, "half", "rates " + fixed$(rate_1, 1) + ", " + fixed$(rate_2, 1) + " Hz"
    elsif chorus_Mode = 2
        Text: 3.9, "centre", 1.28, "half", "3 delay taps / 3"
        Text: 3.9, "centre", 0.92, "half", "rates " + fixed$(rate_1, 1) + ", " + fixed$(rate_2, 1) + ", " + fixed$(rate_3, 1) + " Hz"
    else
        Text: 3.9, "centre", 1.28, "half", "2 counter-rotating taps / 2"
        Text: 3.9, "centre", 0.92, "half", "rate " + fixed$(rate_1, 1) + " Hz, drift +/-" + fixed$(phase_drift_hz, 2)
    endif
    Draw arrow: 5.5, 1.15, 6.4, 1.15
    Text: 5.95, "centre", 0.88, "half", "Wet x " + fixed$(wet_Mix, 2)

    Paint rectangle: "{0.92, 0.92, 0.92}", 6.4, 7.6, 1.0, 1.9
    Text: 7.0, "centre", 1.45, "half", "Sum"
    Draw arrow: 7.6, 1.45, 8.3, 1.45
    Paint rectangle: "{0.88, 0.94, 0.88}", 8.3, 9.5, 1.0, 1.9
    Text: 8.9, "centre", 1.45, "half", "Output"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Transformation law: dry source + averaged modulated taps"

    # Summary strip
    Select outer viewport: 0, 8, 5.25, 6.35
    Select inner viewport: 0.60, 7.70, 5.33, 6.27
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 7
    Text: 0.02, "left", 0.78, "half", "##Summary##"
    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.02, "left", 0.50, "half", modeName$ + "  |  " + presetName$ + "  |  base delay " + fixed$(base_delay_ms, 1) + " ms  |  depth " + fixed$(modulation_depth, 2)
    if chorus_Mode = 1
        rateSummary$ = fixed$(rate_1, 1) + " / " + fixed$(rate_2, 1) + " Hz"
    elsif chorus_Mode = 2
        rateSummary$ = fixed$(rate_1, 1) + " / " + fixed$(rate_2, 1) + " / " + fixed$(rate_3, 1) + " Hz"
    else
        rateSummary$ = fixed$(rate_1, 1) + " Hz +/- " + fixed$(phase_drift_hz, 2) + " Hz drift"
    endif
    Text: 0.02, "left", 0.22, "half", "Rates: " + rateSummary$ + "  |  dry/wet gains " + fixed$(dry_Mix, 2) + "/" + fixed$(wet_Mix, 2) + "  |  target peak " + fixed$(scale_peak, 2) + "  |  " + fixed$(duration, 2) + " s"

    # Restore full Picture page for export
    Select outer viewport: 0, 8, 0, pageHeight
    Axes: 0, 1, 0, 1
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result
