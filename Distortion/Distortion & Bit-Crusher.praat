# ============================================================
# Praat AudioTools - Distortion_Bit_Crusher.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Distortion & Bit-Crusher Suite - two distinct effect modes:
#   (1) Bit Crusher: quantizes amplitude to N levels for lo-fi
#   staircase distortion. (2) Harsh Distortion: replaces waveform
#   with synthesized texture based on zero-crossing polarity,
#   with amplitude modulation and periodic gating.
#
# Changelog v0.2:
#   - Added visualization
#   - Improved preset organization
#   - Added detailed info output
# ============================================================

form Distortion and Bit-Crusher Suite
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
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
    choice Effect_type 1
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

# === Apply Presets ===
if preset = 2
    # Bit Crush: Default
    effect_type = 1
    quantization_levels = 4
    presetName$ = "BC_Default"
elsif preset = 3
    # Bit Crush: Mild
    effect_type = 1
    quantization_levels = 8
    presetName$ = "BC_Mild"
elsif preset = 4
    # Bit Crush: Lo-Fi
    effect_type = 1
    quantization_levels = 3
    presetName$ = "BC_LoFi"
elsif preset = 5
    # Bit Crush: Extreme
    effect_type = 1
    quantization_levels = 2
    presetName$ = "BC_Extreme"
elsif preset = 6
    # Harsh: Balanced
    effect_type = 2
    base_amplitude = 0.5
    mod_amplitude = 0.3
    mod_frequency_Hz = 100
    gate_period_s = 0.05
    gate_duty_cycle_s = 0.025
    presetName$ = "HD_Balanced"
elsif preset = 7
    # Harsh: Light
    effect_type = 2
    base_amplitude = 0.4
    mod_amplitude = 0.2
    mod_frequency_Hz = 80
    gate_period_s = 0.07
    gate_duty_cycle_s = 0.035
    presetName$ = "HD_Light"
elsif preset = 8
    # Harsh: Industrial
    effect_type = 2
    base_amplitude = 0.7
    mod_amplitude = 0.4
    mod_frequency_Hz = 150
    gate_period_s = 0.03
    gate_duty_cycle_s = 0.015
    presetName$ = "HD_Industrial"
elsif preset = 9
    # Harsh: Stutter
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
    modeName$ = "Bit Crusher"
    suffix$ = "_crushed"
else
    modeName$ = "Harsh Distortion"
    suffix$ = "_harsh"
endif

# === Info ===
writeInfoLine: "=== Distortion & Bit-Crusher Suite ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Mode: ", modeName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""

if effect_type = 1
    appendInfoLine: "Quantization levels: ", quantization_levels
    appendInfoLine: "Effective bits: ~", fixed$(ln(quantization_levels)/ln(2), 1)
else
    appendInfoLine: "Base amplitude: ", base_amplitude
    appendInfoLine: "Mod amplitude: ", mod_amplitude
    appendInfoLine: "Mod frequency: ", mod_frequency_Hz, " Hz"
    appendInfoLine: "Gate period: ", gate_period_s * 1000, " ms"
    appendInfoLine: "Gate duty: ", gate_duty_cycle_s * 1000, " ms (", fixed$(gate_duty_cycle_s / gate_period_s * 100, 0), "%)"
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
    # round(x * levels) / levels
    q_str$ = string$(quantization_levels)
    Formula: "round(self * " + q_str$ + ") / " + q_str$
    
else
    # === HARSH DISTORTION ===
    # sign(x) * (base + mod*sin(ωt)) * gate
    
    base$ = string$(base_amplitude)
    mod_amp$ = string$(mod_amplitude)
    mod_freq$ = string$(mod_frequency_Hz)
    gate_per$ = string$(gate_period_s)
    gate_duty$ = string$(gate_duty_cycle_s)
    
    # Components:
    # 1. Sign extraction: if self > 0 then 1 else -1 fi
    # 2. Amplitude mod: (base + mod * sin(2π × freq × x))
    # 3. Gate: if (x mod period > duty) then 1 else 0 fi
    
    Formula: "if self > 0 then 1 else -1 fi * (" + base$ + " + " + mod_amp$ + " * sin(2*pi*" + mod_freq$ + " * x)) * (if (x mod " + gate_per$ + " > " + gate_duty$ + ") then 1 else 0 fi)"
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
    Text: 0.5, "centre", 0.5, "half", modeName$ + ": " + original_name$ + " (" + presetName$ + ")"
    
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
    if effect_type = 1
        Colour: "{0.5, 0.6, 0.8}"
    else
        Colour: "{0.8, 0.5, 0.5}"
    endif
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", modeName$
    Text bottom: "yes", "Time (s)"
    
    # Zoomed comparison
    zoomDur = min(0.03, duration)
    
    Select outer viewport: 0, 4, 2.7, 3.8
    Select inner viewport: 0.6, 3.8, 2.8, 3.7
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, zoomDur, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Orig (zoom)"
    
    Select outer viewport: 4, 8, 2.7, 3.8
    Select inner viewport: 4.4, 7.6, 2.8, 3.7
    selectObject: result
    if effect_type = 1
        Colour: "{0.5, 0.6, 0.8}"
    else
        Colour: "{0.8, 0.5, 0.5}"
    endif
    Draw: 0, zoomDur, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", modeName$ + " (zoom)"
    Text bottom: "yes", "Time (s)"
    
    # Transfer function / Effect diagram
    Select outer viewport: 0, 4, 4.0, 5.3
    Select inner viewport: 0.6, 3.8, 4.1, 5.2
    
    if effect_type = 1
        # Bit crusher transfer function
        Axes: -1.2, 1.2, -1.2, 1.2
        Paint rectangle: "{0.95, 0.95, 0.95}", -1.2, 1.2, -1.2, 1.2
        
        # Grid
        Colour: "{0.85, 0.85, 0.85}"
        Draw line: -1.2, 0, 1.2, 0
        Draw line: 0, -1.2, 0, 1.2
        Dotted line
        Draw line: -1, -1, 1, 1
        Solid line
        
        # Draw staircase transfer
        Colour: "{0.5, 0.6, 0.8}"
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
        Line width: 1
        
        Colour: "Black"
        Draw inner box
        Font size: 5
        Text left: "yes", "Out"
        Text bottom: "yes", "In"
        Text: 0, "centre", 1.35, "half", "Quantization (" + string$(quantization_levels) + " levels)"
        
    else
        # Harsh distortion - show components
        Axes: 0, 5, 0, 4
        Paint rectangle: "{0.95, 0.95, 0.95}", 0, 5, 0, 4
        
        Font size: 5
        
        # Sign box
        Paint rectangle: "{0.8, 0.7, 0.7}", 0.2, 1.2, 2.8, 3.6
        Colour: "Black"
        Text: 0.7, "centre", 3.2, "half", "Sign(x)"
        
        Draw arrow: 1.2, 3.2, 1.5, 3.2
        
        # Mod box
        Paint rectangle: "{0.7, 0.8, 0.7}", 1.5, 2.8, 2.8, 3.6
        Text: 2.15, "centre", 3.2, "half", "Base+Mod"
        
        Draw arrow: 2.8, 3.2, 3.1, 3.2
        
        # Gate box
        Paint rectangle: "{0.7, 0.7, 0.8}", 3.1, 4.2, 2.8, 3.6
        Text: 3.65, "centre", 3.2, "half", "Gate"
        
        Draw arrow: 4.2, 3.2, 4.5, 3.2
        
        # Output
        Paint rectangle: "{0.6, 0.8, 0.6}", 4.5, 4.9, 2.8, 3.6
        Text: 4.7, "centre", 3.2, "half", "Out"
        
        # Parameters
        Font size: 4
        Colour: "{0.5, 0.5, 0.5}"
        Text: 0.7, "centre", 2.4, "half", "±1"
        Text: 2.15, "centre", 2.4, "half", fixed$(base_amplitude, 1) + "+" + fixed$(mod_amplitude, 1) + "×sin"
        Text: 3.65, "centre", 2.4, "half", fixed$(gate_period_s*1000, 0) + "ms"
        
        # Formula
        Font size: 4
        Colour: "{0.4, 0.4, 0.4}"
        Text: 2.5, "centre", 1.5, "half", "sign(x) × (base + mod×sin(ωt)) × gate"
        
        Colour: "Black"
        Draw inner box
    endif
    
    # Parameters display
    Select outer viewport: 4, 8, 4.0, 5.3
    Select inner viewport: 4.4, 7.6, 4.1, 5.2
    
    Axes: 0, 4, 0, 5
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 4, 0, 5
    
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    
    if effect_type = 1
        Text: 0.2, "left", 4.5, "half", "Mode: Bit Crusher"
        Text: 0.2, "left", 3.7, "half", "Levels: " + string$(quantization_levels)
        Text: 0.2, "left", 2.9, "half", "Effective bits: ~" + fixed$(ln(quantization_levels)/ln(2), 1)
        
        # Show level examples
        Colour: "{0.5, 0.5, 0.6}"
        Text: 0.2, "left", 1.8, "half", "2 = extreme square"
        Text: 0.2, "left", 1.2, "half", "4 = heavy lo-fi"
        Text: 0.2, "left", 0.6, "half", "8+ = subtle"
    else
        Text: 0.2, "left", 4.5, "half", "Mode: Harsh Distortion"
        Text: 0.2, "left", 3.8, "half", "Base: " + fixed$(base_amplitude, 2)
        Text: 0.2, "left", 3.1, "half", "Mod: " + fixed$(mod_amplitude, 2) + " @ " + fixed$(mod_frequency_Hz, 0) + " Hz"
        Text: 0.2, "left", 2.4, "half", "Gate: " + fixed$(gate_period_s*1000, 0) + "ms period"
        Text: 0.2, "left", 1.7, "half", "Duty: " + fixed$(gate_duty_cycle_s*1000, 1) + "ms"
        Text: 0.2, "left", 1.0, "half", "(" + fixed$(gate_duty_cycle_s/gate_period_s*100, 0) + "% on)"
    endif
    
    Colour: "Black"
    Draw inner box
    
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