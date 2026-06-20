# ============================================================
# Praat AudioTools - Ribbon_Shimmer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026) - Fixed wet/dry mix object[id,col]; speedup (trimmed inaudible taps); house-style viz + full-length result
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Ribbon Shimmer - lush reverb effect with exponentially-
#   spaced delays and high-frequency enhancement. Delay times
#   follow: delay = minD × (maxD/minD)^(k/n), creating dense
#   early reflections that thin out over time. HF sparkle via
#   differentiation adds "air". Polarity alternation creates
#   rich phase texture.
#
# Changelog v0.2:
#   - Added input check
#   - Fixed selection and formula syntax
#   - Fixed variable name mismatches
#   - Added wet/dry mix control
#   - Added visualization
# ============================================================

form Ribbon Shimmer
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Subtle Ribbon
        option Medium Ribbon
        option Heavy Ribbon
        option Extreme Ribbon
    
    comment === Effect Parameters ===
    positive Tail_duration_s 0.5
    natural Number_of_delays 48
    positive Base_amplitude 0.24
    positive Min_delay_s 0.015
    positive Max_delay_s 1.35
    positive Decay_factor 0.955
    
    comment === HF Sparkle ===
    positive Sparkle_amount 0.25
    
    comment === Mix ===
    real Wet_dry_percent 60
    comment (0 = dry only, 100 = wet only)
    
    comment === Output ===
    positive Fadeout_duration_s 1.0
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
    # Subtle Ribbon
    tail_duration_s = 0.3
    number_of_delays = 50
    base_amplitude = 0.16
    min_delay_s = 0.012
    max_delay_s = 0.8
    decay_factor = 0.965
    sparkle_amount = 0.2
    fadeout_duration_s = 0.8
    presetName$ = "Subtle"
elsif preset = 3
    # Medium Ribbon
    tail_duration_s = 0.5
    number_of_delays = 72
    base_amplitude = 0.24
    min_delay_s = 0.015
    max_delay_s = 1.35
    decay_factor = 0.955
    sparkle_amount = 0.25
    fadeout_duration_s = 1.0
    presetName$ = "Medium"
elsif preset = 4
    # Heavy Ribbon
    tail_duration_s = 0.8
    number_of_delays = 90
    base_amplitude = 0.3
    min_delay_s = 0.012
    max_delay_s = 1.8
    decay_factor = 0.945
    sparkle_amount = 0.3
    fadeout_duration_s = 1.4
    presetName$ = "Heavy"
elsif preset = 5
    # Extreme Ribbon
    tail_duration_s = 1.2
    number_of_delays = 100
    base_amplitude = 0.38
    min_delay_s = 0.01
    max_delay_s = 2.5
    decay_factor = 0.935
    sparkle_amount = 0.35
    fadeout_duration_s = 1.8
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

# Pre-calculate delays for visualization
for k from 1 to min(number_of_delays, 100)
    u = k / number_of_delays
    echoDelay[k] = min_delay_s * ((max_delay_s / min_delay_s) ^ u)
    echoAmp[k] = base_amplitude * (decay_factor ^ k)
    if k mod 3 = 0
        echoPol[k] = -1
    else
        echoPol[k] = 1
    endif
endfor

# Sample period for HF calculation
samplePeriod = 1 / sr

# === Info ===
writeInfoLine: "=== Ribbon Shimmer ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Delays: ", number_of_delays
appendInfoLine: "Delay range: ", min_delay_s * 1000, " - ", max_delay_s * 1000, " ms (exponential)"
appendInfoLine: "Decay factor: ", decay_factor
appendInfoLine: "HF sparkle: ", sparkle_amount
appendInfoLine: "Wet/Dry: ", wet_dry_percent, "%"
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

appendInfoLine: "Processing..."

totalDur = originalDur + tail_duration_s

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

sp_str$ = string$(samplePeriod)
sparkle_str$ = string$(sparkle_amount)

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
    
    # Process left channel
    selectObject: leftChannel
    Copy: "shimmer_left"
    shimmerLeft = selected("Sound")
    
    for k from 1 to number_of_delays
        u = k / number_of_delays
        delay = min_delay_s * ((max_delay_s / min_delay_s) ^ u)
        
        if k mod 3 = 0
            a = base_amplitude * (decay_factor ^ k) * (-1)
        else
            a = base_amplitude * (decay_factor ^ k)
        endif
        
        jitter = randomUniform(-0.003, 0.003)
        totalDelay = delay + jitter
        
        delay_str$ = string$(totalDelay)
        a_str$ = string$(a)
        
        selectObject: shimmerLeft
        Formula: "if x > " + delay_str$ + " then self + " + a_str$ + " * (self(x - " + delay_str$ + ") + " + sparkle_str$ + " * (self(x - " + delay_str$ + ") - self(x - " + delay_str$ + " - " + sp_str$ + "))) else self fi"
        
        if k mod 40 = 0
            Scale peak: 0.98
        endif
    endfor
    
    Scale peak: 0.98
    
    # Process right channel (different parameters for decorrelation)
    selectObject: rightChannel
    Copy: "shimmer_right"
    shimmerRight = selected("Sound")
    
    # Slightly different parameters for right channel
    minD_R = min_delay_s * 1.13
    maxD_R = max_delay_s * 0.98
    baseAmp_R = base_amplitude * 0.96
    decay_R = decay_factor - 0.005
    sparkleR_str$ = string$(sparkle_amount * 0.8)
    
    for k from 1 to number_of_delays
        u = k / number_of_delays
        delay = minD_R * ((maxD_R / minD_R) ^ u)
        
        if k mod 4 = 0
            a = baseAmp_R * (decay_R ^ k) * (-1)
        else
            a = baseAmp_R * (decay_R ^ k)
        endif
        
        jitter = randomUniform(-0.002, 0.002)
        totalDelay = delay + jitter
        
        delay_str$ = string$(totalDelay)
        a_str$ = string$(a)
        
        selectObject: shimmerRight
        Formula: "if x > " + delay_str$ + " then self + " + a_str$ + " * (self(x - " + delay_str$ + ") + " + sparkleR_str$ + " * (self(x - " + delay_str$ + ") - self(x - " + delay_str$ + " - " + sp_str$ + "))) else self fi"
        
        if k mod 25 = 0
            Scale peak: 0.98
        endif
    endfor
    
    Scale peak: 0.98
    
    # Apply wet/dry
    if dry_level > 0
        wet_str$ = string$(wet_level)
        dry_str$ = string$(dry_level)
        left_str$ = string$(leftChannel)
        right_str$ = string$(rightChannel)
        
        selectObject: shimmerLeft
        Formula: "self * " + wet_str$ + " + object[" + left_str$ + ", col] * " + dry_str$
        
        selectObject: shimmerRight
        Formula: "self * " + wet_str$ + " + object[" + right_str$ + ", col] * " + dry_str$
    endif
    
    # Apply fadeout
    fade_start = totalDur - fadeout_duration_s
    fade_str$ = string$(fadeout_duration_s)
    start_str$ = string$(fade_start)
    
    selectObject: shimmerLeft
    Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"
    
    selectObject: shimmerRight
    Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"
    
    # Combine
    selectObject: shimmerLeft, shimmerRight
    Combine to stereo
    result = selected("Sound")
    Rename: originalName$ + "_ribbon_" + presetName$
    
    # Cleanup
    removeObject: leftChannel, rightChannel, shimmerLeft, shimmerRight, extendedSound

else
    # === MONO PROCESSING ===
    appendInfoLine: "  Processing mono..."
    
    selectObject: extendedSound
    Copy: "shimmer_mono"
    shimmerMono = selected("Sound")
    
    for k from 1 to number_of_delays
        u = k / number_of_delays
        delay = min_delay_s * ((max_delay_s / min_delay_s) ^ u)
        
        if k mod 3 = 0
            a = base_amplitude * (decay_factor ^ k) * (-1)
        else
            a = base_amplitude * (decay_factor ^ k)
        endif
        
        jitter = randomUniform(-0.003, 0.003)
        totalDelay = delay + jitter
        
        delay_str$ = string$(totalDelay)
        a_str$ = string$(a)
        
        selectObject: shimmerMono
        Formula: "if x > " + delay_str$ + " then self + " + a_str$ + " * (self(x - " + delay_str$ + ") + " + sparkle_str$ + " * (self(x - " + delay_str$ + ") - self(x - " + delay_str$ + " - " + sp_str$ + "))) else self fi"
        
        if k mod 40 = 0
            Scale peak: 0.98
        endif
    endfor
    
    Scale peak: 0.98
    
    # Apply wet/dry
    if dry_level > 0
        wet_str$ = string$(wet_level)
        dry_str$ = string$(dry_level)
        ext_str$ = string$(extendedSound)
        
        selectObject: shimmerMono
        Formula: "self * " + wet_str$ + " + object[" + ext_str$ + ", col] * " + dry_str$
    endif
    
    # Apply fadeout
    fade_start = totalDur - fadeout_duration_s
    fade_str$ = string$(fadeout_duration_s)
    start_str$ = string$(fade_start)
    
    selectObject: shimmerMono
    Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"
    
    Rename: originalName$ + "_ribbon_" + presetName$
    result = shimmerMono
    
    removeObject: extendedSound
endif

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    Select outer viewport: 0, 8, 0, 8

    selectObject: result
    resultDur = Get total duration

    # === TITLE ===
    Select outer viewport: 0, 8, 0.0, 0.6
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.66, "half", "##Ribbon Shimmer##  |  " + presetName$
    Font size: 8
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -1.24, "half", originalName$ + "   |   " + string$(number_of_delays) + " delays   |   wet/dry " + fixed$(wet_dry_percent, 0) + "%"

    # === DRY WAVEFORM ===
    Select outer viewport: 0, 8, 0.7, 2.5
    Select inner viewport: 0.6, 7.6, 0.8, 2.4
    selectObject: original
    Axes: 0, resultDur, -1, 1
    Colour: "{0.55, 0.55, 0.6}"
    Draw: 0, originalDur, -1, 1, "no", "Curve"
    Colour: "{0.75, 0.75, 0.8}"
    Dotted line
    Draw line: originalDur, -1, originalDur, 1
    Solid line
    Colour: "Black"
    Draw inner box
    Font size: 7
    Marks left: 3, "yes", "yes", "no"
    Text left: "yes", "Dry"
    Font size: 9
    Text top: "no", "##Original (dry) — ends before the tail##"

    # === RESULT WAVEFORM (full length, including shimmer tail) ===
    Select outer viewport: 0, 8, 2.6, 4.4
    Select inner viewport: 0.6, 7.6, 2.7, 4.3
    selectObject: result
    Axes: 0, resultDur, -1, 1
    Colour: "{0.55, 0.45, 0.7}"
    Draw: 0, resultDur, -1, 1, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Marks left: 3, "yes", "yes", "no"
    Text left: "yes", "Shimmer " + fixed$(wet_dry_percent, 0) + "%"
    Text bottom: "yes", "Time (s)"
    Font size: 9
    Text top: "no", "##Shimmered Output (full length with tail)##"

    # === DELAY / ECHO PATTERN ===
    Select outer viewport: 0, 8, 4.5, 6.9
    Select inner viewport: 0.6, 7.6, 4.6, 6.8
    maxDelayMs = max_delay_s * 1000 * 1.1
    maxAmp = base_amplitude * 1.2
    Axes: 0, maxDelayMs, -maxAmp, maxAmp
    Paint rectangle: "{0.96, 0.96, 0.97}", 0, maxDelayMs, -maxAmp, maxAmp
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: 0, 0, maxDelayMs, 0

    numShow = min(number_of_delays, 100)
    radius = maxDelayMs * 0.006
    for k from 1 to numShow
        delayMs = echoDelay[k] * 1000
        amp = echoAmp[k] * echoPol[k]
        if echoPol[k] > 0
            col$ = "{0.45, 0.55, 0.80}"
        else
            col$ = "{0.80, 0.45, 0.45}"
        endif
        Colour: col$
        Draw line: delayMs, 0, delayMs, amp
        Paint circle: col$, delayMs, amp, radius
    endfor

    # exponential decay envelope
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    prevX = 0
    prevY = base_amplitude
    for k from 1 to numShow
        delayMs = echoDelay[k] * 1000
        env = base_amplitude * (decay_factor ^ k)
        Draw line: prevX, prevY, delayMs, env
        prevX = delayMs
        prevY = env
    endfor
    Solid line

    Colour: "Black"
    Draw inner box
    Font size: 7
    Marks left: 3, "yes", "yes", "no"
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Delay (ms) — exponential spacing"
    Font size: 9
    Text top: "no", "##Echo Tap Pattern (blue +, red −)##"

    # === GREY SUMMARY PANEL ===
    Select outer viewport: 0, 8, 7.0, 8.0
    Select inner viewport: 0.6, 7.6, 7.05, 7.95
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.70, "half", "##Shimmer Parameters##"
    Font size: 8
    Colour: "{0.25, 0.25, 0.25}"
    Text: 0.02, "left", 0.40, "half", "Delays: " + string$(number_of_delays) + "    Range: " + fixed$(min_delay_s * 1000, 0) + "–" + fixed$(max_delay_s * 1000, 0) + " ms    Decay: " + fixed$(decay_factor, 3) + "    Sparkle: " + fixed$(sparkle_amount, 2)
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.02, "left", 0.12, "half", "Output: " + fixed$(resultDur, 2) + " s  (original " + fixed$(originalDur, 2) + " s + " + fixed$(tail_duration_s, 2) + " s tail)    Wet/dry: " + fixed$(wet_dry_percent, 0) + "%"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

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
