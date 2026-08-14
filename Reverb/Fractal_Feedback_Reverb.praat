# ============================================================
# Praat AudioTools - Fractal_Feedback_Reverb.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Fractal Feedback Reverb - creates dense reverb with chaotic
#   delay patterns. Uses iterative delay accumulation where
#   delay times follow chaos_factor^(i mod memory_depth) pattern,
#   creating self-similar, fractal-like echo structures. Each
#   iteration adds primary + secondary delays with amplitude
#   modulation. Different from Fractal_Feedback which uses
#   segment-based spatial processing.
#
# Changelog v0.3:
#   - Viz: set world axes explicitly before title & parameters text
#     (parameters line was inheriting the delay panel's axes -> mis-placed)
#
# Changelog v0.2:
#   - Fixed selection syntax
#   - Fixed formula syntax
#   - Added wet/dry mix control
#   - Added visualization
#   - Better object cleanup
# ============================================================

form Fractal Feedback Reverb
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Subtle Fractal
        option Medium Fractal
        option Heavy Fractal
        option Extreme Fractal
    
    comment === Tail ===
    positive Tail_duration_s 2.0
    
    comment === Chaos Parameters ===
    natural Iterations 32
    positive Seed_delay_s 0.08
    positive Chaos_factor 1.8
    natural Memory_depth 4
    
    comment === Amplitude ===
    positive Amplitude_base 0.18
    positive Secondary_factor 0.75
    positive Modulation_freq_Hz 30
    
    comment === Mix ===
    real Wet_dry_percent 60
    comment (0 = dry only, 100 = wet only)
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
originalDur = Get total duration
sr = Get sampling frequency
numChannels = Get number of channels

# === Apply Presets ===
if preset = 2
    # Subtle Fractal
    tail_duration_s = 1.5
    iterations = 20
    seed_delay_s = 0.06
    chaos_factor = 1.5
    memory_depth = 3
    amplitude_base = 0.12
    secondary_factor = 0.65
    modulation_freq_Hz = 25
    presetName$ = "Subtle"
elsif preset = 3
    # Medium Fractal
    tail_duration_s = 2.0
    iterations = 32
    seed_delay_s = 0.08
    chaos_factor = 1.8
    memory_depth = 4
    amplitude_base = 0.18
    secondary_factor = 0.75
    modulation_freq_Hz = 30
    presetName$ = "Medium"
elsif preset = 4
    # Heavy Fractal
    tail_duration_s = 2.8
    iterations = 48
    seed_delay_s = 0.1
    chaos_factor = 2.1
    memory_depth = 5
    amplitude_base = 0.24
    secondary_factor = 0.85
    modulation_freq_Hz = 38
    presetName$ = "Heavy"
elsif preset = 5
    # Extreme Fractal
    tail_duration_s = 4.0
    iterations = 70
    seed_delay_s = 0.12
    chaos_factor = 2.5
    memory_depth = 6
    amplitude_base = 0.3
    secondary_factor = 0.95
    modulation_freq_Hz = 45
    presetName$ = "Extreme"
else
    presetName$ = "Custom"
endif

# Clamp wet/dry
if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif

wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

# Pre-calculate delay pattern for info and visualization
for i from 1 to min(iterations, 20)
    delayPrimary[i] = seed_delay_s * (chaos_factor ^ ((i - 1) mod memory_depth))
    delaySecondary[i] = delayPrimary[i] / chaos_factor
endfor

# === Info ===
writeInfoLine: "=== Fractal Feedback Reverb ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Iterations: ", iterations
appendInfoLine: "Seed delay: ", seed_delay_s * 1000, " ms"
appendInfoLine: "Chaos factor: ", chaos_factor
appendInfoLine: "Memory depth: ", memory_depth
appendInfoLine: "Amplitude base: ", amplitude_base
appendInfoLine: "Wet/Dry: ", wet_dry_percent, "%"
appendInfoLine: ""
appendInfoLine: "First 10 delay times (primary):"
for i from 1 to min(10, iterations)
    appendInfoLine: "  ", i, ": ", fixed$(delayPrimary[i] * 1000, 1), " ms"
endfor
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

appendInfoLine: "Processing..."

# Create silent tail
if numChannels = 2
    Create Sound from formula: "silent_tail", 2, 0, tail_duration_s, sr, "0"
else
    Create Sound from formula: "silent_tail", 1, 0, tail_duration_s, sr, "0"
endif
silentTail = selected("Sound")

# Concatenate
selectObject: original, silentTail
Concatenate
extendedSound = selected("Sound")
removeObject: silentTail

totalDur = originalDur + tail_duration_s

if numChannels = 2
    # === STEREO PROCESSING ===
    appendInfoLine: "  Processing stereo..."
    
    # Extract channels
    selectObject: extendedSound
    Extract one channel: 1
    leftChannel = selected("Sound")
    
    selectObject: extendedSound
    Extract one channel: 2
    rightChannel = selected("Sound")
    
    # Process left
    selectObject: leftChannel
    Copy: "reverb_left"
    reverbLeft = selected("Sound")
    
    for i from 1 to iterations
        primary_delay = seed_delay_s * (chaos_factor ^ ((i - 1) mod memory_depth))
        secondary_delay = primary_delay / chaos_factor
        amp1 = amplitude_base * (1 - i / iterations) * randomUniform(0.6, 1.4)
        amp2 = amp1 * secondary_factor
        
        amp1_str$ = string$(amp1)
        amp2_str$ = string$(amp2)
        pd_str$ = string$(primary_delay)
        sd_str$ = string$(secondary_delay)
        freq_str$ = string$(modulation_freq_Hz)
        
        selectObject: reverbLeft
        Formula: "self + " + amp1_str$ + " * self(x - " + pd_str$ + ")"
        Formula: "self + " + amp2_str$ + " * self(x - " + sd_str$ + ") * cos(2*pi*x*" + freq_str$ + ")"
    endfor
    
    # Process right (slightly different for decorrelation)
    selectObject: rightChannel
    Copy: "reverb_right"
    reverbRight = selected("Sound")
    
    chaos_R = chaos_factor + 0.02
    seed_R = seed_delay_s + 0.002
    freq_R = modulation_freq_Hz - 2
    
    for i from 1 to iterations
        primary_delay = seed_R * (chaos_R ^ ((i - 1) mod memory_depth))
        secondary_delay = primary_delay / chaos_R
        amp1 = amplitude_base * (1 - i / iterations) * randomUniform(0.55, 1.35)
        amp2 = amp1 * (secondary_factor - 0.03)
        
        amp1_str$ = string$(amp1)
        amp2_str$ = string$(amp2)
        pd_str$ = string$(primary_delay)
        sd_str$ = string$(secondary_delay)
        freq_str$ = string$(freq_R)
        
        selectObject: reverbRight
        Formula: "self + " + amp1_str$ + " * self(x - " + pd_str$ + ")"
        Formula: "self + " + amp2_str$ + " * self(x - " + sd_str$ + ") * cos(2*pi*x*" + freq_str$ + ")"
    endfor
    
    # Apply wet/dry
    if dry_level > 0
        wet_str$ = string$(wet_level)
        dry_str$ = string$(dry_level)
        left_str$ = string$(leftChannel)
        right_str$ = string$(rightChannel)
        
        selectObject: reverbLeft
        Formula: "self * " + wet_str$ + " + object[" + left_str$ + "] * " + dry_str$
        
        selectObject: reverbRight
        Formula: "self * " + wet_str$ + " + object[" + right_str$ + "] * " + dry_str$
    endif
    
    # Normalize
    selectObject: reverbLeft
    Scale peak: 0.95
    
    selectObject: reverbRight
    Scale peak: 0.95
    
    # Combine
    selectObject: reverbLeft, reverbRight
    Combine to stereo
    result = selected("Sound")
    Rename: originalName$ + "_fractalReverb_" + presetName$
    
    # Cleanup
    removeObject: leftChannel, rightChannel, reverbLeft, reverbRight, extendedSound
    
else
    # === MONO PROCESSING ===
    appendInfoLine: "  Processing mono..."
    
    selectObject: extendedSound
    Copy: "reverb_mono"
    reverbMono = selected("Sound")
    
    for i from 1 to iterations
        primary_delay = seed_delay_s * (chaos_factor ^ ((i - 1) mod memory_depth))
        secondary_delay = primary_delay / chaos_factor
        amp1 = amplitude_base * (1 - i / iterations) * randomUniform(0.6, 1.4)
        amp2 = amp1 * secondary_factor
        
        amp1_str$ = string$(amp1)
        amp2_str$ = string$(amp2)
        pd_str$ = string$(primary_delay)
        sd_str$ = string$(secondary_delay)
        freq_str$ = string$(modulation_freq_Hz)
        
        selectObject: reverbMono
        Formula: "self + " + amp1_str$ + " * self(x - " + pd_str$ + ")"
        Formula: "self + " + amp2_str$ + " * self(x - " + sd_str$ + ") * cos(2*pi*x*" + freq_str$ + ")"
    endfor
    
    # Apply wet/dry
    if dry_level > 0
        wet_str$ = string$(wet_level)
        dry_str$ = string$(dry_level)
        ext_str$ = string$(extendedSound)
        
        selectObject: reverbMono
        Formula: "self * " + wet_str$ + " + object[" + ext_str$ + "] * " + dry_str$
    endif
    
    selectObject: reverbMono
    Scale peak: 0.95
    Rename: originalName$ + "_fractalReverb_" + presetName$
    result = reverbMono
    
    removeObject: extendedSound
endif

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Fractal Feedback Reverb: " + originalName$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.6, 7.6, 0.7, 1.3
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Dry"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.5, 2.3
    Select inner viewport: 0.6, 7.6, 1.6, 2.2
    selectObject: result
    Colour: "{0.6, 0.5, 0.7}"
    Draw: 0, originalDur, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Reverb " + fixed$(wet_dry_percent, 0) + "%"
    Text bottom: "yes", "Time (s)"
    
    # Chaotic delay pattern
    Select outer viewport: 0, 8, 2.5, 3.8
    Select inner viewport: 0.6, 7.6, 2.6, 3.7
    
    # Find max delay for scaling
    maxDelay = 0
    for i from 1 to min(iterations, 20)
        if delayPrimary[i] > maxDelay
            maxDelay = delayPrimary[i]
        endif
    endfor
    maxDelay = maxDelay * 1.1
    
    Axes: 0, min(iterations, 20), 0, maxDelay * 1000
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, min(iterations, 20), 0, maxDelay * 1000
    
    # Draw delay pattern
    Colour: "{0.6, 0.5, 0.7}"
    Line width: 2
    for i from 2 to min(iterations, 20)
        Draw line: i - 1, delayPrimary[i-1] * 1000, i, delayPrimary[i] * 1000
    endfor
    
    # Draw secondary delays
    Colour: "{0.7, 0.6, 0.5}"
    Line width: 1
    Dotted line
    for i from 2 to min(iterations, 20)
        Draw line: i - 1, delaySecondary[i-1] * 1000, i, delaySecondary[i] * 1000
    endfor
    Solid line
    
    # Mark memory depth wrap points
    Colour: "{0.8, 0.8, 0.8}"
    for i from 1 to min(iterations, 20)
        if (i - 1) mod memory_depth = 0 and i > 1
            Draw line: i, 0, i, maxDelay * 1000
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Delay (ms)"
    Text bottom: "yes", "Iteration"
    
    # Legend
    Font size: 5
    Colour: "{0.6, 0.5, 0.7}"
    Text: min(iterations, 20) * 0.8, "centre", maxDelay * 950, "half", "Primary"
    Colour: "{0.7, 0.6, 0.5}"
    Text: min(iterations, 20) * 0.8, "centre", maxDelay * 850, "half", "Secondary"
    
    # Parameters
    Select outer viewport: 0, 8, 3.9, 4.3
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Iterations: " + string$(iterations) + " | Chaos: " + fixed$(chaos_factor, 2) + " | Depth: " + string$(memory_depth) + " | Seed: " + fixed$(seed_delay_s * 1000, 0) + "ms"
    
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