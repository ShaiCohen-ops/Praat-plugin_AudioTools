# ============================================================
# Praat AudioTools - Dual_Mode_Tremolo_Generator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Dual-Mode Tremolo Generator - two tremolo styles:
#   Adaptive mode varies depth with signal amplitude (louder=more).
#   Strong mode uses rectified sine for hard chopping/gating.
#
# Changelog v0.2:
#   - Modern syntax
#   - Fixed input check
#   - Added presets
#   - Fixed name-based object reference
#   - Added visualization
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
sound$ = selected$("Sound")

selectObject: original
duration = Get total duration
fs = Get sampling frequency

# === Form ===
form Dual-Mode Tremolo Generator
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Classic Tremolo
        option Subtle Shimmer
        option Helicopter Chop
        option Slow Pulse
        option Fast Flutter
        option Dynamic Swell
    
    comment === Mode ===
    choice Mode 1
        button Adaptive (reacts to volume)
        button Strong (absolute pulsing)
    
    comment === Rate ===
    positive Modulation_rate_hz 5
    
    comment === Adaptive Mode Settings ===
    positive Max_modulation_depth 0.7
    positive Signal_sensitivity 0.5
    positive Sensitivity_offset 0.5
    
    comment === Output ===
    positive Scale_peak 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Classic Tremolo
    mode = 1
    modulation_rate_hz = 6
    max_modulation_depth = 0.5
    signal_sensitivity = 0.3
    sensitivity_offset = 0.6
    presetName$ = "Classic"
elsif preset = 3
    # Subtle Shimmer
    mode = 1
    modulation_rate_hz = 8
    max_modulation_depth = 0.25
    signal_sensitivity = 0.2
    sensitivity_offset = 0.7
    presetName$ = "Shimmer"
elsif preset = 4
    # Helicopter Chop
    mode = 2
    modulation_rate_hz = 12
    presetName$ = "Helicopter"
elsif preset = 5
    # Slow Pulse
    mode = 2
    modulation_rate_hz = 2
    presetName$ = "SlowPulse"
elsif preset = 6
    # Fast Flutter
    mode = 1
    modulation_rate_hz = 15
    max_modulation_depth = 0.6
    signal_sensitivity = 0.4
    sensitivity_offset = 0.5
    presetName$ = "Flutter"
elsif preset = 7
    # Dynamic Swell
    mode = 1
    modulation_rate_hz = 3
    max_modulation_depth = 0.8
    signal_sensitivity = 0.7
    sensitivity_offset = 0.3
    presetName$ = "Swell"
else
    presetName$ = "Custom"
endif

# Get mode name
if mode = 1
    modeName$ = "Adaptive"
else
    modeName$ = "Strong"
endif

# === Info ===
writeInfoLine: "=== Dual-Mode Tremolo Generator ==="
appendInfoLine: "Source: ", sound$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Mode: ", modeName$
appendInfoLine: ""
appendInfoLine: "Rate: ", modulation_rate_hz, " Hz"
if mode = 1
    appendInfoLine: "Max depth: ", max_modulation_depth
    appendInfoLine: "Sensitivity: ", signal_sensitivity
    appendInfoLine: "Offset: ", sensitivity_offset
endif
appendInfoLine: ""

# === Process ===
if mode = 1
    # ============================================================
    # MODE 1: ADAPTIVE TREMOLO
    # ============================================================
    appendInfoLine: "Applying adaptive tremolo..."
    
    selectObject: original
    Copy: sound$ + "_adaptive"
    result = selected("Sound")
    
    # Apply adaptive formula
    # Depth scales with signal amplitude
    Formula: ~ self * (1 - max_modulation_depth * (1 + sin(2 * pi * modulation_rate_hz * x)) / 2 * (sensitivity_offset + signal_sensitivity * abs(self)))

else
    # ============================================================
    # MODE 2: STRONG TREMOLO
    # ============================================================
    appendInfoLine: "Creating strong tremolo LFO..."
    
    # Create absolute-sine modulator (0 to 1)
    Create Sound from formula: "tremoloLFO", 1, 0, duration, fs, ~ abs(sin(2 * pi * modulation_rate_hz * x))
    modulator = selected("Sound")
    
    # Apply modulator
    appendInfoLine: "Applying modulator..."
    selectObject: original
    Copy: sound$ + "_strong"
    result = selected("Sound")
    
    # Use object reference instead of name
    Formula: ~ self * object[modulator, col]
    
    # Clean up modulator
    removeObject: modulator
endif

# === Scale ===
selectObject: result
Scale peak: scale_peak
Rename: sound$ + "_tremolo_" + presetName$

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Dual-Mode Tremolo: " + sound$ + " (" + modeName$ + " - " + presetName$ + ")"
    
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
    if mode = 1
        Colour: "{0.5, 0.7, 0.6}"
    else
        Colour: "{0.7, 0.5, 0.6}"
    endif
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", modeName$
    Text bottom: "yes", "Time (s)"
    
    # LFO shape
    Select outer viewport: 0, 8, 2.7, 3.7
    Select inner viewport: 0.6, 7.6, 2.8, 3.6
    
    # Show ~3 cycles of LFO
    lfoDisplayDur = min(3 / modulation_rate_hz, duration)
    
    Axes: 0, lfoDisplayDur, -0.1, 1.1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, lfoDisplayDur, -0.1, 1.1
    
    # Draw LFO
    nLfoPoints = 200
    if mode = 1
        # Adaptive: show standard sine envelope (shifted to 0-1)
        Colour: "{0.5, 0.7, 0.6}"
        for lp from 2 to nLfoPoints
            t1 = (lp - 2) / nLfoPoints * lfoDisplayDur
            t2 = (lp - 1) / nLfoPoints * lfoDisplayDur
            y1 = (1 + sin(2 * pi * modulation_rate_hz * t1)) / 2
            y2 = (1 + sin(2 * pi * modulation_rate_hz * t2)) / 2
            Draw line: t1, y1, t2, y2
        endfor
        lfoLabel$ = "Sine LFO (depth varies)"
    else
        # Strong: show rectified sine
        Colour: "{0.7, 0.5, 0.6}"
        for lp from 2 to nLfoPoints
            t1 = (lp - 2) / nLfoPoints * lfoDisplayDur
            t2 = (lp - 1) / nLfoPoints * lfoDisplayDur
            y1 = abs(sin(2 * pi * modulation_rate_hz * t1))
            y2 = abs(sin(2 * pi * modulation_rate_hz * t2))
            Draw line: t1, y1, t2, y2
        endfor
        lfoLabel$ = "|sin| LFO (hard chop)"
    endif
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "LFO"
    Text bottom: "yes", lfoLabel$
    
    # Mode comparison diagram
    Select outer viewport: 0, 8, 3.9, 4.8
    Select inner viewport: 0.6, 7.6, 4.0, 4.7
    
    Axes: 0, 2, 0, 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 2, 0, 1.2
    
    # Adaptive box
    if mode = 1
        Paint rectangle: "{0.5, 0.7, 0.6}", 0.1, 0.9, 0.1, 1.0
    else
        Paint rectangle: "{0.8, 0.8, 0.8}", 0.1, 0.9, 0.1, 1.0
    endif
    
    # Strong box
    if mode = 2
        Paint rectangle: "{0.7, 0.5, 0.6}", 1.1, 1.9, 0.1, 1.0
    else
        Paint rectangle: "{0.8, 0.8, 0.8}", 1.1, 1.9, 0.1, 1.0
    endif
    
    Colour: "Black"
    Font size: 6
    Text: 0.5, "centre", 0.55, "half", "Adaptive"
    Text: 1.5, "centre", 0.55, "half", "Strong"
    
    Draw inner box
    Font size: 6
    Text left: "yes", "Mode"
    
    # Stats
    Select outer viewport: 0, 8, 4.9, 5.2
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    if mode = 1
        Text: 0.5, "centre", 0.5, "half", "Rate: " + fixed$(modulation_rate_hz, 1) + " Hz | Depth: " + fixed$(max_modulation_depth, 2) + " | Sensitivity: " + fixed$(signal_sensitivity, 2) + " | Offset: " + fixed$(sensitivity_offset, 2)
    else
        Text: 0.5, "centre", 0.5, "half", "Rate: " + fixed$(modulation_rate_hz, 1) + " Hz | Mode: Rectified sine (|sin|) | Effective rate: " + fixed$(modulation_rate_hz * 2, 1) + " Hz"
    endif
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
selectObject: result

appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result
