# ============================================================
# Praat AudioTools - Cascading_Echoes.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Cascading Echoes - multi-tap delay effect with random delay
#   times per iteration. Creates dense, diffuse echo patterns.
#   Stereo mode uses different delay ranges for L/R channels
#   to create width. Exponential amplitude decay per tap.
#
# Changelog v0.2:
#   - Fixed echo formula (was incorrect)
#   - Added bounds checking
#   - Fixed selection syntax
#   - Added wet/dry mix control
#   - Added visualization
# ============================================================

form Cascading Echoes
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Default (balanced)
        option Short and Tight
        option Long Ambient Tail
        option Wide Stereo Delay
        option Custom (use settings below)
    
    comment === Echo Parameters ===
    positive Tail_duration_s 1.0
    natural Iterations 5
    
    comment === Delay Range (ms) ===
    positive Delay_min_ms 10
    positive Delay_max_ms 100
    
    comment === Stereo Offset (ms, for R channel) ===
    positive Stereo_delay_min_ms 12
    positive Stereo_delay_max_ms 120
    
    comment === Decay ===
    positive Decay_left 0.8
    positive Decay_right 0.75
    
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
if preset = 1
    # Default (balanced)
    tail_duration_s = 1.0
    iterations = 5
    delay_min_ms = 10
    delay_max_ms = 100
    stereo_delay_min_ms = 12
    stereo_delay_max_ms = 120
    decay_left = 0.8
    decay_right = 0.75
    presetName$ = "Default"
elsif preset = 2
    # Short & Tight
    tail_duration_s = 0.5
    iterations = 3
    delay_min_ms = 5
    delay_max_ms = 40
    stereo_delay_min_ms = 7
    stereo_delay_max_ms = 50
    decay_left = 0.9
    decay_right = 0.88
    presetName$ = "ShortTight"
elsif preset = 3
    # Long Ambient Tail
    tail_duration_s = 2.5
    iterations = 7
    delay_min_ms = 25
    delay_max_ms = 250
    stereo_delay_min_ms = 30
    stereo_delay_max_ms = 300
    decay_left = 0.85
    decay_right = 0.82
    presetName$ = "LongAmbient"
elsif preset = 4
    # Wide Stereo Delay
    tail_duration_s = 1.5
    iterations = 6
    delay_min_ms = 15
    delay_max_ms = 120
    stereo_delay_min_ms = 40
    stereo_delay_max_ms = 350
    decay_left = 0.78
    decay_right = 0.72
    presetName$ = "WideStereo"
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

# Convert ms to samples
delay_min_samp = round(delay_min_ms / 1000 * sr)
delay_max_samp = round(delay_max_ms / 1000 * sr)
stereo_min_samp = round(stereo_delay_min_ms / 1000 * sr)
stereo_max_samp = round(stereo_delay_max_ms / 1000 * sr)

# Store delay values for visualization
for k from 1 to iterations
    delayL[k] = round(randomUniform(delay_min_samp, delay_max_samp))
    delayR[k] = round(randomUniform(stereo_min_samp, stereo_max_samp))
    ampL[k] = decay_left ^ k
    ampR[k] = decay_right ^ k
endfor

# === Info ===
writeInfoLine: "=== Cascading Echoes ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Iterations: ", iterations
appendInfoLine: "Delay range (L): ", delay_min_ms, "-", delay_max_ms, " ms"
appendInfoLine: "Delay range (R): ", stereo_delay_min_ms, "-", stereo_delay_max_ms, " ms"
appendInfoLine: "Decay (L/R): ", decay_left, " / ", decay_right
appendInfoLine: "Wet/Dry: ", wet_dry_percent, "%"
appendInfoLine: ""
appendInfoLine: "Echo taps:"
for k from 1 to iterations
    appendInfoLine: "  ", k, ": L=", round(delayL[k] * 1000 / sr), "ms (", fixed$(ampL[k], 2), ") | R=", round(delayR[k] * 1000 / sr), "ms (", fixed$(ampR[k], 2), ")"
endfor
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

appendInfoLine: "Processing..."

# Create extended sound with tail
selectObject: original
totalDur = originalDur + tail_duration_s

if numChannels = 2
    Create Sound from formula: "silent_tail", 2, 0, tail_duration_s, sr, "0"
else
    Create Sound from formula: "silent_tail", 1, 0, tail_duration_s, sr, "0"
endif
silentTail = selected("Sound")

selectObject: original, silentTail
Concatenate
extendedSound = selected("Sound")
removeObject: silentTail

nSamples = Get number of samples

if numChannels = 2
    # === STEREO PROCESSING ===
    
    # Extract channels
    selectObject: extendedSound
    Extract one channel: 1
    leftChannel = selected("Sound")
    
    selectObject: extendedSound
    Extract one channel: 2
    rightChannel = selected("Sound")
    
    # Create wet signal containers (start as copies)
    selectObject: leftChannel
    Copy: "left_wet"
    leftWet = selected("Sound")
    
    selectObject: rightChannel
    Copy: "right_wet"
    rightWet = selected("Sound")
    
    # Process left channel - add each echo tap
    for k from 1 to iterations
        delay = delayL[k]
        amp = ampL[k]
        amp_str$ = string$(amp)
        delay_str$ = string$(delay)
        
        # Add delayed version of original
        left_str$ = string$(leftChannel)
        selectObject: leftWet
        Formula: "self + " + amp_str$ + " * (if col > " + delay_str$ + " then object[" + left_str$ + ", col - " + delay_str$ + "] else 0 fi)"
    endfor
    
    # Process right channel
    for k from 1 to iterations
        delay = delayR[k]
        amp = ampR[k]
        amp_str$ = string$(amp)
        delay_str$ = string$(delay)
        
        right_str$ = string$(rightChannel)
        selectObject: rightWet
        Formula: "self + " + amp_str$ + " * (if col > " + delay_str$ + " then object[" + right_str$ + ", col - " + delay_str$ + "] else 0 fi)"
    endfor
    
    # Apply wet/dry mix
    if dry_level > 0
        wet_str$ = string$(wet_level)
        dry_str$ = string$(dry_level)
        left_str$ = string$(leftChannel)
        right_str$ = string$(rightChannel)
        
        selectObject: leftWet
        Formula: "self * " + wet_str$ + " + object[" + left_str$ + "] * " + dry_str$
        
        selectObject: rightWet
        Formula: "self * " + wet_str$ + " + object[" + right_str$ + "] * " + dry_str$
    endif
    
    # Normalize
    selectObject: leftWet
    Scale peak: 0.95
    
    selectObject: rightWet
    Scale peak: 0.95
    
    # Combine to stereo
    selectObject: leftWet, rightWet
    Combine to stereo
    result = selected("Sound")
    Rename: originalName$ + "_echo_" + presetName$
    
    # Cleanup
    removeObject: leftChannel, rightChannel, leftWet, rightWet, extendedSound
    
else
    # === MONO PROCESSING ===
    
    # Create wet signal (start as copy)
    selectObject: extendedSound
    Copy: "mono_wet"
    monoWet = selected("Sound")
    
    # Add each echo tap
    for k from 1 to iterations
        delay = delayL[k]
        amp = ampL[k]
        amp_str$ = string$(amp)
        delay_str$ = string$(delay)
        
        ext_str$ = string$(extendedSound)
        selectObject: monoWet
        Formula: "self + " + amp_str$ + " * (if col > " + delay_str$ + " then object[" + ext_str$ + ", col - " + delay_str$ + "] else 0 fi)"
    endfor
    
    # Apply wet/dry mix
    if dry_level > 0
        wet_str$ = string$(wet_level)
        dry_str$ = string$(dry_level)
        ext_str$ = string$(extendedSound)
        
        selectObject: monoWet
        Formula: "self * " + wet_str$ + " + object[" + ext_str$ + "] * " + dry_str$
    endif
    
    # Normalize
    selectObject: monoWet
    Scale peak: 0.95
    Rename: originalName$ + "_echo_" + presetName$
    result = monoWet
    
    # Cleanup
    removeObject: extendedSound
endif

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Cascading Echoes: " + originalName$ + " (" + presetName$ + ")"
    
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
    Colour: "{0.5, 0.7, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Wet " + fixed$(wet_dry_percent, 0) + "%"
    Text bottom: "yes", "Time (s)"
    
    # Echo tap diagram
    Select outer viewport: 0, 8, 2.5, 4.2
    Select inner viewport: 0.6, 7.6, 2.6, 4.1
    
    # Find max delay for axis
    maxDelay = 0
    for k from 1 to iterations
        if delayL[k] > maxDelay
            maxDelay = delayL[k]
        endif
        if delayR[k] > maxDelay
            maxDelay = delayR[k]
        endif
    endfor
    maxDelayMs = maxDelay * 1000 / sr * 1.1
    
    Axes: 0, maxDelayMs, 0, 1.1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, maxDelayMs, 0, 1.1
    
    # Draw echo taps
    Font size: 5
    
    for k from 1 to iterations
        # Left tap (green)
        delayMs_L = delayL[k] * 1000 / sr
        Colour: "{0.4, 0.7, 0.4}"
        Draw line: delayMs_L, 0, delayMs_L, ampL[k]
        Paint circle: "{0.4, 0.7, 0.4}", delayMs_L, ampL[k], 0.015 * maxDelayMs
        
        # Right tap (blue)
        delayMs_R = delayR[k] * 1000 / sr
        Colour: "{0.4, 0.4, 0.7}"
        Draw line: delayMs_R, 0, delayMs_R, ampR[k]
        Paint circle: "{0.4, 0.4, 0.7}", delayMs_R, ampR[k], 0.015 * maxDelayMs
    endfor
    
    # Draw dry signal marker
    Colour: "{0.6, 0.6, 0.6}"
    Draw line: 0, 0, 0, 1
    Paint circle: "{0.6, 0.6, 0.6}", 0, 1, 0.02 * maxDelayMs
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Delay (ms)"
    
    # Legend
    Font size: 5
    Colour: "{0.4, 0.7, 0.4}"
    Text: maxDelayMs * 0.85, "centre", 1.0, "half", "L taps"
    Colour: "{0.4, 0.4, 0.7}"
    Text: maxDelayMs * 0.85, "centre", 0.9, "half", "R taps"
    
    # Parameters
    Select outer viewport: 0, 8, 4.3, 4.7
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Iterations: " + string$(iterations) + " | Decay L/R: " + fixed$(decay_left, 2) + "/" + fixed$(decay_right, 2) + " | Tail: " + fixed$(tail_duration_s, 1) + "s"
    
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