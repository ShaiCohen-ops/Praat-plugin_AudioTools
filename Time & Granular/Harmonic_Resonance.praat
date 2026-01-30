# ============================================================
# Praat AudioTools - Harmonic_Resonance.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Harmonic Resonance - creates harmonic series resonances through
#   bidirectional sample delay processing. Each iteration adds
#   resonances at harmonicBase^k intervals, creating rich harmonic
#   textures similar to a tuned comb filter bank.
#
# Changelog v0.2:
#   - Modern syntax
#   - Added bounds checking
#   - Added visualization
# ============================================================

form Harmonic Resonance
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom
        option Subtle Harmonics
        option Medium Harmonics
        option Heavy Harmonics
        option Extreme Harmonics
    
    comment === Resonance Parameters ===
    positive Tail_duration_s 2.0
    natural Num_iterations 7
    
    comment === Harmonic Base ===
    positive Harmonic_base_min 1.5
    positive Harmonic_base_max 4.0
    boolean Use_fixed_base 0
    positive Fixed_harmonic_base 2.5
    
    comment === Decay ===
    positive Decay_factor 0.6
    
    comment === Output ===
    positive Scale_peak 0.95
    positive Fadeout_duration_s 1.0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Subtle Harmonics
    tail_duration_s = 1.5
    num_iterations = 4
    harmonic_base_min = 1.3
    harmonic_base_max = 2.2
    use_fixed_base = 0
    fixed_harmonic_base = 1.8
    decay_factor = 0.4
    scale_peak = 0.96
    fadeout_duration_s = 0.8
elsif preset = 3
    # Medium Harmonics
    tail_duration_s = 2.0
    num_iterations = 7
    harmonic_base_min = 1.5
    harmonic_base_max = 4.0
    use_fixed_base = 0
    fixed_harmonic_base = 2.5
    decay_factor = 0.6
    scale_peak = 0.95
    fadeout_duration_s = 1.0
elsif preset = 4
    # Heavy Harmonics
    tail_duration_s = 2.8
    num_iterations = 10
    harmonic_base_min = 2.0
    harmonic_base_max = 4.8
    use_fixed_base = 0
    fixed_harmonic_base = 3.5
    decay_factor = 0.75
    scale_peak = 0.93
    fadeout_duration_s = 1.4
elsif preset = 5
    # Extreme Harmonics
    tail_duration_s = 4.0
    num_iterations = 15
    harmonic_base_min = 2.5
    harmonic_base_max = 6.0
    use_fixed_base = 0
    fixed_harmonic_base = 4.5
    decay_factor = 0.85
    scale_peak = 0.91
    fadeout_duration_s = 1.8
endif

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

# === Determine Harmonic Base ===
if use_fixed_base
    harmonicBase = fixed_harmonic_base
else
    harmonicBase = randomUniform(harmonic_base_min, harmonic_base_max)
endif

# === Info ===
writeInfoLine: "=== Harmonic Resonance ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(originalDuration, 2), " s)"
appendInfoLine: ""
appendInfoLine: "Harmonic base: ", fixed$(harmonicBase, 3)
appendInfoLine: "Iterations: ", num_iterations
appendInfoLine: "Decay factor: ", decay_factor
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
Copy: "harmonic_work"
result = selected("Sound")

totalSamples = Get number of samples

# === Main Harmonic Processing Loop ===
appendInfoLine: "Processing harmonics..."
appendInfoLine: ""
appendInfoLine: "Iter | Shift Factor | Delay (samples) | Delay (ms)"
appendInfoLine: "-----|--------------|-----------------|----------"

for k from 1 to num_iterations
    # Exponential harmonic progression
    shiftFactor = harmonicBase ^ k
    delaySamples = round(totalSamples / shiftFactor)
    halfDelay = round(delaySamples / 2)
    
    # Info
    delayMs = delaySamples / sampling_rate * 1000
    appendInfoLine: "  ", k, "  |     ", fixed$(shiftFactor, 2), "     |      ", delaySamples, "      |  ", fixed$(delayMs, 1)
    
    # Calculate amplitude factors
    iterWeight = 1 / k
    ampDecay = 1 - k / num_iterations * decay_factor
    
    # Bidirectional formula with harmonic weighting and bounds checking
    selectObject: result
    Formula: "if col + delaySamples <= ncol and col - halfDelay >= 1 then (self[col + delaySamples] - self[col - halfDelay]) * iterWeight else self * 0.5 fi"
    
    # Harmonic amplitude decay
    Formula: "self * ampDecay"
endfor

# === Scale Peak ===
selectObject: result
Scale peak: scale_peak

# === Apply Fadeout ===
totalDuration = Get total duration
fadeStart = totalDuration - fadeout_duration_s

Formula: "if x > fadeStart then self * (0.5 + 0.5 * cos(pi * (x - fadeStart) / fadeout_duration_s)) else self fi"

Rename: original_name$ + "_harmonics"

# === Cleanup ===
removeObject: extended

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 2, 8, 0.2, 0.6
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Harmonic Resonance: " + original_name$
    
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
    Colour: "{0.2, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Harmonic"
    Text bottom: "yes", "Time (s)"
    
    # Original spectrum
    Select outer viewport: 0, 4, 3.9, 5.5
    Select inner viewport: 0.6, 3.8, 4.1, 5.4
    selectObject: original
    To Spectrum: "yes"
    origSpec = selected("Spectrum")
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 5000, 0, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "dB"
    Text bottom: "yes", "Original (Hz)"
    removeObject: origSpec
    
    # Result spectrum
    Select outer viewport: 4, 8, 3.9, 5.5
    Select inner viewport: 4.4, 7.6, 4.1, 5.4
    selectObject: result
    To Spectrum: "yes"
    resSpec = selected("Spectrum")
    Colour: "{0.3, 0.6, 0.8}"
    Draw: 0, 5000, 0, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "dB"
    Text bottom: "yes", "Harmonic (Hz)"
    removeObject: resSpec
    
    # Legend
    Select outer viewport: 2, 8, 5.6, 5.9
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Base: " + fixed$(harmonicBase, 2) + " | Iterations: " + string$(num_iterations) + " | Decay: " + fixed$(decay_factor, 2)
    
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