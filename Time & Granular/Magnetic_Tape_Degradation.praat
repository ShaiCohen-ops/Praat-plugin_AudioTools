# ============================================================
# Praat AudioTools - Magnetic_Tape_Degradation.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Magnetic Tape Degradation - simulates analog tape aging:
#   - Hysteresis (magnetic memory effect)
#   - Print-through (signal bleeding between tape layers)
#   - High-frequency loss (tape loses HF over time)
#   - Bias modulation (recorder bias oscillation)
#
# ============================================================

# --- 1. COMPACT STARTUP FORM ---
form Tape Degradation (Compact)
    comment PRESETS:
    optionmenu Preset 1
        option Custom
        option Subtle Tape
        option Medium Tape
        option Heavy Tape
        option Extreme Tape
    
    comment MAIN CONTROLS:
    natural Generations 6
    positive Tail_duration_s 2.0
    
    comment OUTPUT:
    boolean Draw_visualization 1
    boolean Play_result 1
    
    comment ADVANCED:
    boolean Show_advanced_settings 0
endform

# --- 2. DEFINE DEFAULT PARAMETERS ---
# (Used for "Custom" if Advanced is not opened)
hysteresis_current = 0.7
hysteresis_previous = 0.3
print_through_initial = 0.25
print_through_decay = 0.8
print_offset_divisor = 100
bias_min = 0.8
bias_max = 1.2
use_fixed_bias = 0
fixed_bias = 1.0
hf_loss_rate = 0.1
hf_smoothing = 0.9
bias_mod_center = 0.9
bias_mod_depth = 0.1
scale_peak = 0.87
fadeout_duration_s = 1.0

# --- 3. SHOW ADVANCED SETTINGS (If Checked) ---
if show_advanced_settings
    beginPause: "Advanced Tape Physics"
        comment: "Hysteresis (Memory Effect):"
        positive: "Hysteresis current", hysteresis_current
        positive: "Hysteresis previous", hysteresis_previous
        
        comment: "Print-Through (Ghosting):"
        positive: "Print through initial", print_through_initial
        positive: "Print through decay", print_through_decay
        natural: "Print offset divisor", print_offset_divisor
        
        comment: "Tape Bias:"
        positive: "Bias min", bias_min
        positive: "Bias max", bias_max
        boolean: "Use fixed bias", use_fixed_bias
        positive: "Fixed bias", fixed_bias
        
        comment: "Signal Loss:"
        positive: "Hf loss rate", hf_loss_rate
        positive: "Hf smoothing", hf_smoothing
        
        comment: "Bias Modulation (Wow/Flutter):"
        positive: "Bias mod center", bias_mod_center
        positive: "Bias mod depth", bias_mod_depth
        
        comment: "Output Envelope:"
        positive: "Scale peak", scale_peak
        positive: "Fadeout duration s", fadeout_duration_s
        
    clicked = endPause: "Cancel", "OK", 2, 1
    if clicked = 1
        exitScript: "Cancelled."
    endif
endif

# ==============================================================================
# APPLY PRESETS
# ==============================================================================
# Note: Presets override custom settings, except for Generations/Tail
# which are taken from the main form unless hardcoded below.

if preset = 2
    # Subtle Tape
    tail_duration_s = 1.5
    generations = 3
    hysteresis_current = 0.65
    hysteresis_previous = 0.35
    print_through_initial = 0.12
    print_through_decay = 0.85
    print_offset_divisor = 120
    bias_min = 0.92
    bias_max = 1.08
    use_fixed_bias = 0
    hf_loss_rate = 0.06
    hf_smoothing = 0.94
    bias_mod_center = 0.95
    bias_mod_depth = 0.05
    scale_peak = 0.90
    fadeout_duration_s = 0.8
elsif preset = 3
    # Medium Tape
    # (Uses defaults mostly, but explicitly set here for clarity)
    tail_duration_s = 2.0
    generations = 6
    hysteresis_current = 0.7
    hysteresis_previous = 0.3
    print_through_initial = 0.25
    print_through_decay = 0.8
    print_offset_divisor = 100
    bias_min = 0.8
    bias_max = 1.2
    use_fixed_bias = 0
    hf_loss_rate = 0.1
    hf_smoothing = 0.9
    bias_mod_center = 0.9
    bias_mod_depth = 0.1
    scale_peak = 0.87
    fadeout_duration_s = 1.0
elsif preset = 4
    # Heavy Tape
    tail_duration_s = 2.8
    generations = 10
    hysteresis_current = 0.75
    hysteresis_previous = 0.25
    print_through_initial = 0.35
    print_through_decay = 0.75
    print_offset_divisor = 85
    bias_min = 0.7
    bias_max = 1.3
    use_fixed_bias = 0
    hf_loss_rate = 0.15
    hf_smoothing = 0.85
    bias_mod_center = 0.85
    bias_mod_depth = 0.15
    scale_peak = 0.85
    fadeout_duration_s = 1.4
elsif preset = 5
    # Extreme Tape
    tail_duration_s = 4.0
    generations = 15
    hysteresis_current = 0.8
    hysteresis_previous = 0.2
    print_through_initial = 0.45
    print_through_decay = 0.7
    print_offset_divisor = 70
    bias_min = 0.6
    bias_max = 1.5
    use_fixed_bias = 0
    hf_loss_rate = 0.2
    hf_smoothing = 0.8
    bias_mod_center = 0.8
    bias_mod_depth = 0.2
    scale_peak = 0.82
    fadeout_duration_s = 1.8
endif

# ==============================================================================
# MAIN SCRIPT EXECUTION
# ==============================================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

original = selected("Sound")
original_name$ = selected$("Sound")

selectObject: original
sampling_rate = Get sampling frequency
channels = Get number of channels
originalDuration = Get total duration

# === Determine Bias ===
if use_fixed_bias
    bias = fixed_bias
else
    bias = randomUniform(bias_min, bias_max)
endif

# === Info ===
writeInfoLine: "=== Magnetic Tape Degradation ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(originalDuration, 2), " s)"
appendInfoLine: ""
appendInfoLine: "Generations: ", generations
appendInfoLine: "Hysteresis: ", hysteresis_current, " / ", hysteresis_previous
appendInfoLine: "Print-through: ", print_through_initial, " (decay ", print_through_decay, ")"
appendInfoLine: "HF loss: ", hf_loss_rate, " | Smoothing: ", hf_smoothing
appendInfoLine: "Bias: ", fixed$(bias, 3)
appendInfoLine: ""

# === Create Silent Tail ===
if channels = 2
    Create Sound from formula: "silent_tail", 2, 0, tail_duration_s, sampling_rate, "0"
else
    Create Sound from formula: "silent_tail", 1, 0, tail_duration_s, sampling_rate, "0"
endif
silentTail = selected("Sound")

# === Concatenate ===
selectObject: original, silentTail
Concatenate
extended = selected("Sound")
Rename: "extended"

removeObject: silentTail

# === Copy for Processing ===
selectObject: extended
Copy: "tape_work"
result = selected("Sound")

totalSamples = Get number of samples

# === Initialize Print-Through ===
printThrough = print_through_initial

# === Main Tape Degradation Loop ===
appendInfoLine: "Processing generations..."

for gen from 1 to generations
    selectObject: result
    
    # Calculate parameters for this generation
    hfLossFactor = 1 - hf_loss_rate * gen
    printOffset = round(totalSamples / print_offset_divisor)
    
    appendInfoLine: "  Gen ", gen, ": HF=", fixed$(hfLossFactor, 2), " Print=", fixed$(printThrough, 3)
    
    # Tape hysteresis effect (with bounds check)
    Formula: "if col > 1 then hysteresis_current * self + hysteresis_previous * self[col-1] else self fi"
    
    # Print-through effect (with bounds check)
    Formula: "if col > printOffset and col + printOffset <= ncol then self + printThrough * (self[col - printOffset] + self[col + printOffset])/2 else self fi"
    
    # High-frequency loss per generation (with bounds check)
    Formula: "if col > 1 and col < ncol then self * hfLossFactor + hf_smoothing * (self[col-1] + self[col+1])/2 else self fi"
    
    # Bias modulation
    Formula: "self * (bias_mod_center + bias_mod_depth * sin(2 * pi * bias * col / totalSamples))"
    
    # Decay print-through for next generation
    printThrough = printThrough * print_through_decay
endfor

# === Scale Peak ===
selectObject: result
Scale peak: scale_peak

# === Apply Fadeout ===
totalDuration = Get total duration
fadeStart = totalDuration - fadeout_duration_s

Formula: "if x > fadeStart then self * (0.5 + 0.5 * cos(pi * (x - fadeStart) / fadeout_duration_s)) else self fi"

Rename: original_name$ + "_tape"

# === Cleanup ===
removeObject: extended

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 1, 8, 0.2, 0.6
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Magnetic Tape Degradation: " + original_name$
    
    # Original waveform
    Select outer viewport: 0, 8, 0.8, 2.2
    Select inner viewport: 0.6, 7.6, 0.9, 2.1
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 2.3, 3.7
    Select inner viewport: 0.6, 7.6, 2.4, 3.6
    selectObject: result
    Colour: "{0.6, 0.4, 0.2}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Tape"
    Text bottom: "yes", "Time (s)"
    
    # Original spectrum
    Select outer viewport: 0, 4, 3.9, 5.5
    Select inner viewport: 0.6, 3.8, 4.1, 5.4
    selectObject: original
    To Spectrum: "yes"
    origSpec = selected("Spectrum")
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 8000, 0, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "dB"
    Text bottom: "yes", "Original (Hz)"
    removeObject: origSpec
    
    # Result spectrum (shows HF loss)
    Select outer viewport: 4, 8, 3.9, 5.5
    Select inner viewport: 4.4, 7.6, 4.1, 5.4
    selectObject: result
    To Spectrum: "yes"
    resSpec = selected("Spectrum")
    Colour: "{0.6, 0.4, 0.2}"
    Draw: 0, 8000, 0, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "dB"
    Text bottom: "yes", "Tape (Hz) - HF loss visible"
    removeObject: resSpec
    
    # Legend
    Select outer viewport: 0, 8, 5.6, 5.9
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Generations: " + string$(generations) + " | Hysteresis: " + fixed$(hysteresis_current, 2) + "/" + fixed$(hysteresis_previous, 2) + " | HF loss: " + fixed$(hf_loss_rate, 2)
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
selectObject: result
finalDuration = Get total duration

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Original: ", fixed$(originalDuration, 2), " s"
appendInfoLine: "Result: ", fixed$(finalDuration, 2), " s"
appendInfoLine: "Created: ", selected$("Sound")

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result
