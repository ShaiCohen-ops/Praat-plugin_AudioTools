# ============================================================
# Praat AudioTools - Stereo_Shimmer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025) - OPTIMIZED
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Stereo Shimmer with linear-spaced delays and HF enhancement.
#   NOW WITH SPEED MODES for 4-8× faster processing!
# ============================================================

form Stereo Shimmer v1.0 (Optimized)
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Subtle Shimmer
        option Medium Shimmer
        option Heavy Shimmer
        option Extreme Shimmer
    
    comment === Performance ===
    optionmenu Speed_mode: 2
        option Full Quality (original sample rate)
        option Balanced (downsample to 22 kHz)
        option Fast (downsample to 11 kHz)
    
    comment === Shimmer Parameters ===
    positive Tail_duration_s 2
    natural Number_of_echoes 80
    positive Base_amplitude 0.24
    positive Min_delay_s 0.02
    positive Max_delay_s 1.2
    positive Decay_factor 0.95
    positive Jitter_s 0.012
    
    comment === HF Enhancement ===
    positive HF_enhancement 0.25
    
    comment === Mix ===
    real Wet_dry_percent 60
    comment (0 = dry only, 100 = wet only)
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Check Input
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
originalDur = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels

# Apply Presets
if preset = 2
    tail_duration_s = 1.5
    number_of_echoes = 40
    base_amplitude = 0.15
    min_delay_s = 0.02
    max_delay_s = 0.8
    decay_factor = 0.96
    jitter_s = 0.008
    hF_enhancement = 0.15
    presetName$ = "Subtle"
elsif preset = 3
    tail_duration_s = 2
    number_of_echoes = 80
    base_amplitude = 0.24
    min_delay_s = 0.02
    max_delay_s = 1.2
    decay_factor = 0.95
    jitter_s = 0.012
    hF_enhancement = 0.25
    presetName$ = "Medium"
elsif preset = 4
    tail_duration_s = 3
    number_of_echoes = 120
    base_amplitude = 0.32
    min_delay_s = 0.015
    max_delay_s = 1.8
    decay_factor = 0.94
    jitter_s = 0.018
    hF_enhancement = 0.35
    presetName$ = "Heavy"
elsif preset = 5
    tail_duration_s = 4
    number_of_echoes = 180
    base_amplitude = 0.4
    min_delay_s = 0.01
    max_delay_s = 2.5
    decay_factor = 0.93
    jitter_s = 0.025
    hF_enhancement = 0.45
    presetName$ = "Extreme"
else
    presetName$ = "Custom"
endif

# Set target sample rate
if speed_mode = 1
    targetSR = 0
    speedStr$ = "Full Quality"
elsif speed_mode = 2
    targetSR = 22050
    speedStr$ = "Balanced"
else
    targetSR = 11025
    speedStr$ = "Fast"
endif

# Clamp wet/dry
wet_dry_percent = max(0, min(100, wet_dry_percent))
wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

startTime = stopwatch

# Info
writeInfoLine: "=== Stereo Shimmer v1.0 (Optimized) ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Speed: ", speedStr$
appendInfoLine: ""
appendInfoLine: "Echoes: ", number_of_echoes
appendInfoLine: "Delay range: ", min_delay_s * 1000, " - ", max_delay_s * 1000, " ms"
appendInfoLine: "Wet/Dry: ", wet_dry_percent, "%"
appendInfoLine: ""

# === OPTIONAL DOWNSAMPLING ===
workingSound = original
if targetSR > 0 and sampleRate > targetSR
    appendInfoLine: "[SPEED] Downsampling to ", targetSR, " Hz"
    selectObject: original
    Resample: targetSR, 50
    workingSound = selected("Sound")
    workingSR = targetSR
else
    workingSR = sampleRate
endif

# Sample period for HF
samplePeriod = 1 / workingSR

# Pre-calculate delays for visualization
for k from 1 to min(number_of_echoes, 100)
    echoDelay[k] = min_delay_s + (max_delay_s - min_delay_s) * k / number_of_echoes
    echoAmp[k] = base_amplitude * (decay_factor ^ k)
    if k mod 4 < 2
        echoPol[k] = 1
    else
        echoPol[k] = -1
    endif
endfor

# PROCESSING
appendInfoLine: "Processing..."

selectObject: workingSound
workingDur = Get total duration
workingChannels = Get number of channels

totalDur = workingDur + tail_duration_s

# Create silent tail
if workingChannels = 2
    Create Sound from formula: "silent_tail", 2, 0, tail_duration_s, workingSR, "0"
else
    Create Sound from formula: "silent_tail", 1, 0, tail_duration_s, workingSR, "0"
endif
silentTail = selected("Sound")

# Concatenate
selectObject: workingSound, silentTail
Concatenate
extendedSound = selected("Sound")
removeObject: silentTail

sp_str$ = string$(samplePeriod)
hf_str$ = string$(hF_enhancement)

if workingChannels = 2
    # STEREO PROCESSING
    appendInfoLine: "  Processing stereo..."
    
    # Extract channels
    selectObject: extendedSound
    Extract one channel: 1
    leftChannel = selected("Sound")
    
    selectObject: extendedSound
    Extract one channel: 2
    rightChannel = selected("Sound")
    
    # Process left channel
    selectObject: leftChannel
    Copy: "shimmer_left"
    shimmerLeft = selected("Sound")
    
    for k from 1 to number_of_echoes
        delay = min_delay_s + (max_delay_s - min_delay_s) * k / number_of_echoes + randomUniform(-jitter_s, jitter_s)
        
        if k mod 4 < 2
            sgn = 1
        else
            sgn = -1
        endif
        
        a = base_amplitude * (decay_factor ^ k) * sgn
        
        delay_str$ = string$(delay)
        a_str$ = string$(a)
        
        selectObject: shimmerLeft
        Formula: "if x > " + delay_str$ + " then self + " + a_str$ + " * self(x - " + delay_str$ + ") else self fi"
        
        if k mod 20 = 0
            Scale peak: 0.98
            if k mod 40 = 0
                appendInfoLine: "    Left: ", k, "/", number_of_echoes
            endif
        endif
    endfor
    
    # HF enhancement
    Formula: "self + " + hf_str$ + " * (self - self(x - " + sp_str$ + "))"
    Scale peak: 0.98
    
    # Process right channel
    selectObject: rightChannel
    Copy: "shimmer_right"
    shimmerRight = selected("Sound")
    
    jitter_R = jitter_s * 1.25
    decay_R = decay_factor - 0.01
    hf_R = hF_enhancement * 0.92
    hf_R_str$ = string$(hf_R)
    
    for k from 1 to number_of_echoes
        delay = min_delay_s + (max_delay_s - min_delay_s) * k / number_of_echoes + randomUniform(-jitter_R, jitter_R)
        
        if (k + 2) mod 4 < 2
            sgn = 1
        else
            sgn = -1
        endif
        
        a = base_amplitude * (decay_R ^ k) * sgn
        
        delay_str$ = string$(delay)
        a_str$ = string$(a)
        
        selectObject: shimmerRight
        Formula: "if x > " + delay_str$ + " then self + " + a_str$ + " * self(x - " + delay_str$ + ") else self fi"
        
        if k mod 20 = 0
            Scale peak: 0.98
            if k mod 40 = 0
                appendInfoLine: "    Right: ", k, "/", number_of_echoes
            endif
        endif
    endfor
    
    # HF enhancement
    Formula: "self + " + hf_R_str$ + " * (self - self(x - " + sp_str$ + "))"
    Scale peak: 0.98
    
    # Apply wet/dry
    if dry_level > 0
        wet_str$ = string$(wet_level)
        dry_str$ = string$(dry_level)
        left_str$ = string$(leftChannel)
        right_str$ = string$(rightChannel)
        
        selectObject: shimmerLeft
        Formula: "self * " + wet_str$ + " + object[" + left_str$ + "] * " + dry_str$
        
        selectObject: shimmerRight
        Formula: "self * " + wet_str$ + " + object[" + right_str$ + "] * " + dry_str$
    endif
    
    # Combine
    selectObject: shimmerLeft, shimmerRight
    Combine to stereo
    result = selected("Sound")
    
    # Cleanup
    removeObject: leftChannel, rightChannel, shimmerLeft, shimmerRight, extendedSound

else
    # MONO PROCESSING
    appendInfoLine: "  Processing mono..."
    
    selectObject: extendedSound
    Copy: "shimmer_mono"
    shimmerMono = selected("Sound")
    
    for k from 1 to number_of_echoes
        delay = min_delay_s + (max_delay_s - min_delay_s) * k / number_of_echoes + randomUniform(-jitter_s, jitter_s)
        
        if k mod 4 < 2
            sgn = 1
        else
            sgn = -1
        endif
        
        a = base_amplitude * (decay_factor ^ k) * sgn
        
        delay_str$ = string$(delay)
        a_str$ = string$(a)
        
        selectObject: shimmerMono
        Formula: "if x > " + delay_str$ + " then self + " + a_str$ + " * self(x - " + delay_str$ + ") else self fi"
        
        if k mod 20 = 0
            Scale peak: 0.98
            if k mod 40 = 0
                appendInfoLine: "    ", k, "/", number_of_echoes
            endif
        endif
    endfor
    
    # HF enhancement
    Formula: "self + " + hf_str$ + " * (self - self(x - " + sp_str$ + "))"
    Scale peak: 0.98
    
    # Apply wet/dry
    if dry_level > 0
        wet_str$ = string$(wet_level)
        dry_str$ = string$(dry_level)
        ext_str$ = string$(extendedSound)
        
        selectObject: shimmerMono
        Formula: "self * " + wet_str$ + " + object[" + ext_str$ + "] * " + dry_str$
    endif
    
    result = shimmerMono
    removeObject: extendedSound
endif

# === UPSAMPLE IF NEEDED ===
if targetSR > 0 and sampleRate > targetSR
    appendInfoLine: "Upsampling to ", sampleRate, " Hz..."
    selectObject: result
    Resample: sampleRate, 50
    upsampledID = selected("Sound")
    removeObject: result
    result = upsampledID
    
    # Also need to remove working sound
    if workingSound <> original
        removeObject: workingSound
    endif
endif

selectObject: result
Rename: originalName$ + "_shimmer_" + presetName$

processingTime = stopwatch - startTime

# VISUALIZATION
if draw_visualization
    Erase all
    
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Stereo Shimmer: " + originalName$ + " (" + presetName$ + ")"
    
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
    Text left: "yes", "Shimmer " + fixed$(wet_dry_percent, 0) + "%"
    Text bottom: "yes", "Time (s)"
    
    # Linear delay pattern
    Select outer viewport: 0, 8, 2.5, 4.0
    Select inner viewport: 0.6, 7.6, 2.6, 3.9
    
    maxDelayMs = max_delay_s * 1000 * 1.1
    maxAmp = base_amplitude * 1.2
    
    Axes: 0, maxDelayMs, -maxAmp, maxAmp
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, maxDelayMs, -maxAmp, maxAmp
    
    # Zero line
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: 0, 0, maxDelayMs, 0
    
    # Linear reference
    Colour: "{0.8, 0.8, 0.8}"
    Dotted line
    Draw line: min_delay_s * 1000, base_amplitude, max_delay_s * 1000, base_amplitude * (decay_factor ^ number_of_echoes)
    Solid line
    
    # Delay impulses
    numShow = min(number_of_echoes, 100)
    for k from 1 to numShow
        delayMs = echoDelay[k] * 1000
        amp = echoAmp[k] * echoPol[k]
        
        if echoPol[k] > 0
            col$ = "{0.5, 0.6, 0.8}"
        else
            col$ = "{0.8, 0.5, 0.5}"
        endif
        
        Colour: col$
        Draw line: delayMs, 0, delayMs, amp
        Paint circle (mm): col$, delayMs, amp, 0.8
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Delay (ms) — linear spacing"
    
    # Legend
    Font size: 5
    Colour: "{0.5, 0.6, 0.8}"
    Text: maxDelayMs * 0.85, "centre", maxAmp * 0.85, "half", "+ polarity"
    Colour: "{0.8, 0.5, 0.5}"
    Text: maxDelayMs * 0.85, "centre", -maxAmp * 0.85, "half", "- polarity"
    
    # Parameters
    Select outer viewport: 0, 8, 4.1, 4.5
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", speedStr$ + " | Echoes: " + string$(number_of_echoes) + " | Time: " + fixed$(processingTime, 2) + "s | HF: " + fixed$(hF_enhancement, 2)
    
    Font size: 10
    Colour: "Black"
endif

# Final Info
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Processing time: ", fixed$(processingTime, 2), " seconds"
appendInfoLine: "Created: ", selected$("Sound")

# Play
if play_result
    Play
endif

selectObject: result