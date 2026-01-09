# ============================================================
# Praat AudioTools - Unified_Chorus_Generator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Unified Chorus Generator - flexible chorus/ensemble effect
#   offering Dual Tap (2-voice), Tri Tap (3-voice), and Orbit
#   (counter-rotating phase drift) modes. Creates thickening,
#   spatial movement, and ensemble effects.
#
# Changelog v2.1:
#   - Fixed input check
#   - Fixed formula syntax (use object IDs)
#   - Added bounds checking
#   - Added visualization
#   - Added info output
# ============================================================

form Unified Chorus Generator
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
writeInfoLine: "=== Unified Chorus Generator v2.1 ==="
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
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Chorus: " + original_name$ + " (" + modeName$ + " - " + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.6, 7.6, 0.7, 1.4
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.6, 2.5
    Select inner viewport: 0.6, 7.6, 1.7, 2.4
    selectObject: result
    Colour: "{0.5, 0.6, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Chorus"
    Text bottom: "yes", "Time (s)"
    
    # LFO visualization
    Select outer viewport: 0, 8, 2.7, 4.0
    Select inner viewport: 0.6, 7.6, 2.8, 3.9
    
    vizDur = min(2, duration)
    nPoints = 400
    
    Axes: 0, vizDur, -1.2, 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, vizDur, -1.2, 1.2
    
    # Zero line
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: 0, 0, vizDur, 0
    
    # Draw LFOs based on mode
    Line width: 1.5
    
    if chorus_Mode = 1
        # Dual tap - 2 LFOs
        Colour: "{0.5, 0.6, 0.8}"
        for p from 2 to nPoints
            t1 = (p - 2) / nPoints * vizDur
            t2 = (p - 1) / nPoints * vizDur
            lfo1a = modulation_depth * sin(2*pi*rate_1*t1)
            lfo1b = modulation_depth * sin(2*pi*rate_1*t2)
            Draw line: t1, lfo1a * 4, t2, lfo1b * 4
        endfor
        
        Colour: "{0.8, 0.5, 0.5}"
        for p from 2 to nPoints
            t1 = (p - 2) / nPoints * vizDur
            t2 = (p - 1) / nPoints * vizDur
            lfo2a = modulation_depth * sin(2*pi*rate_2*t1 + 2.0)
            lfo2b = modulation_depth * sin(2*pi*rate_2*t2 + 2.0)
            Draw line: t1, lfo2a * 4, t2, lfo2b * 4
        endfor
        
    elsif chorus_Mode = 2
        # Tri tap - 3 LFOs
        Colour: "{0.5, 0.6, 0.8}"
        for p from 2 to nPoints
            t1 = (p - 2) / nPoints * vizDur
            t2 = (p - 1) / nPoints * vizDur
            lfo1a = modulation_depth * sin(2*pi*rate_1*t1)
            lfo1b = modulation_depth * sin(2*pi*rate_1*t2)
            Draw line: t1, lfo1a * 3, t2, lfo1b * 3
        endfor
        
        Colour: "{0.5, 0.8, 0.5}"
        for p from 2 to nPoints
            t1 = (p - 2) / nPoints * vizDur
            t2 = (p - 1) / nPoints * vizDur
            lfo2a = modulation_depth * sin(2*pi*rate_2*t1 + 2.1)
            lfo2b = modulation_depth * sin(2*pi*rate_2*t2 + 2.1)
            Draw line: t1, lfo2a * 3, t2, lfo2b * 3
        endfor
        
        Colour: "{0.8, 0.5, 0.5}"
        for p from 2 to nPoints
            t1 = (p - 2) / nPoints * vizDur
            t2 = (p - 1) / nPoints * vizDur
            lfo3a = modulation_depth * sin(2*pi*rate_3*t1 + 4.2)
            lfo3b = modulation_depth * sin(2*pi*rate_3*t2 + 4.2)
            Draw line: t1, lfo3a * 3, t2, lfo3b * 3
        endfor
        
    elsif chorus_Mode = 3
        # Orbit - counter-rotating
        Colour: "{0.5, 0.6, 0.8}"
        for p from 2 to nPoints
            t1 = (p - 2) / nPoints * vizDur
            t2 = (p - 1) / nPoints * vizDur
            lfo1a = modulation_depth * sin(2*pi*rate_1*t1 + 2*pi*phase_drift_hz*t1)
            lfo1b = modulation_depth * sin(2*pi*rate_1*t2 + 2*pi*phase_drift_hz*t2)
            Draw line: t1, lfo1a * 4, t2, lfo1b * 4
        endfor
        
        Colour: "{0.8, 0.5, 0.5}"
        for p from 2 to nPoints
            t1 = (p - 2) / nPoints * vizDur
            t2 = (p - 1) / nPoints * vizDur
            lfo2a = modulation_depth * sin(2*pi*rate_1*t1 - 2*pi*phase_drift_hz*t1 + 3.14)
            lfo2b = modulation_depth * sin(2*pi*rate_1*t2 - 2*pi*phase_drift_hz*t2 + 3.14)
            Draw line: t1, lfo2a * 4, t2, lfo2b * 4
        endfor
    endif
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "LFO Mod"
    Text bottom: "yes", "Time (s)"
    
    # Mode diagram
    Select outer viewport: 0, 8, 4.2, 5.2
    Select inner viewport: 0.6, 7.6, 4.3, 5.1
    
    Axes: 0, 10, 0, 3
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 10, 0, 3
    
    Font size: 5
    
    # Input
    Paint rectangle: "{0.7, 0.7, 0.7}", 0.3, 1.3, 1.2, 1.8
    Colour: "Black"
    Text: 0.8, "centre", 1.5, "half", "Input"
    
    # Split arrows
    Draw arrow: 1.3, 1.5, 2, 2.5
    Draw arrow: 1.3, 1.5, 2, 1.5
    if chorus_Mode = 2
        Draw arrow: 1.3, 1.5, 2, 0.5
    endif
    
    # Dry path
    Colour: "{0.6, 0.6, 0.6}"
    Text: 2.5, "centre", 2.5, "half", "Dry"
    Draw arrow: 3, 2.5, 6.8, 1.8
    
    # Tap boxes
    if chorus_Mode = 1
        # Dual
        Paint rectangle: "{0.5, 0.6, 0.8}", 2.2, 3.8, 1.2, 1.8
        Colour: "Black"
        Text: 3, "centre", 1.5, "half", "Tap1 @" + fixed$(rate_1, 1) + "Hz"
        
        Paint rectangle: "{0.8, 0.5, 0.5}", 2.2, 3.8, 0.2, 0.8
        Text: 3, "centre", 0.5, "half", "Tap2 @" + fixed$(rate_2, 1) + "Hz"
        
        Draw arrow: 3.8, 1.5, 4.5, 1.5
        Draw arrow: 3.8, 0.5, 4.5, 1.2
        
    elsif chorus_Mode = 2
        # Tri
        Paint rectangle: "{0.5, 0.6, 0.8}", 2.2, 3.5, 2.0, 2.4
        Colour: "Black"
        Text: 2.85, "centre", 2.2, "half", fixed$(rate_1, 1) + "Hz"
        
        Paint rectangle: "{0.5, 0.8, 0.5}", 2.2, 3.5, 1.2, 1.6
        Text: 2.85, "centre", 1.4, "half", fixed$(rate_2, 1) + "Hz"
        
        Paint rectangle: "{0.8, 0.5, 0.5}", 2.2, 3.5, 0.4, 0.8
        Text: 2.85, "centre", 0.6, "half", fixed$(rate_3, 1) + "Hz"
        
        Draw arrow: 3.5, 2.2, 4.2, 1.5
        Draw arrow: 3.5, 1.4, 4.2, 1.4
        Draw arrow: 3.5, 0.6, 4.2, 1.3
        
    else
        # Orbit
        Paint rectangle: "{0.5, 0.6, 0.8}", 2.2, 4, 1.2, 1.8
        Colour: "Black"
        Text: 3.1, "centre", 1.5, "half", "+" + fixed$(phase_drift_hz, 2) + "Hz drift"
        
        Paint rectangle: "{0.8, 0.5, 0.5}", 2.2, 4, 0.2, 0.8
        Text: 3.1, "centre", 0.5, "half", "-" + fixed$(phase_drift_hz, 2) + "Hz drift"
        
        # Circular arrows to show counter-rotation
        Colour: "{0.5, 0.6, 0.8}"
        Draw arrow: 4, 1.5, 4.5, 1.5
        Colour: "{0.8, 0.5, 0.5}"
        Draw arrow: 4, 0.5, 4.5, 1.2
    endif
    
    # Sum
    Paint rectangle: "{0.6, 0.7, 0.6}", 4.5, 5.5, 1.0, 2.0
    Colour: "Black"
    Text: 5, "centre", 1.5, "half", "Sum"
    
    # Mix
    Draw arrow: 5.5, 1.5, 6.2, 1.5
    Paint rectangle: "{0.7, 0.7, 0.6}", 6.2, 7.2, 1.0, 2.0
    Text: 6.7, "centre", 1.5, "half", "Mix"
    
    # Output
    Draw arrow: 7.2, 1.5, 7.8, 1.5
    Paint rectangle: "{0.6, 0.8, 0.6}", 7.8, 8.8, 1.0, 2.0
    Text: 8.3, "centre", 1.5, "half", "Out"
    
    Colour: "Black"
    Draw inner box
    
    # Parameters
    Select outer viewport: 0, 8, 5.3, 5.7
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    
    if chorus_Mode = 1
        param$ = "Rates: " + fixed$(rate_1, 1) + " / " + fixed$(rate_2, 1) + " Hz"
    elsif chorus_Mode = 2
        param$ = "Rates: " + fixed$(rate_1, 1) + " / " + fixed$(rate_2, 1) + " / " + fixed$(rate_3, 1) + " Hz"
    else
        param$ = "Rate: " + fixed$(rate_1, 1) + " Hz | Drift: ±" + fixed$(phase_drift_hz, 2) + " Hz"
    endif
    
    Text: 0.5, "centre", 0.5, "half", "Delay: " + fixed$(base_delay_ms, 1) + " ms | Depth: " + fixed$(modulation_depth, 2) + " | Dry: " + fixed$(dry_Mix, 1) + " | Wet: " + fixed$(wet_Mix, 1) + " | " + param$
    
    Font size: 10
    Colour: "Black"
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