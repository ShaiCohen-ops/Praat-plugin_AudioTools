# ============================================================
# Praat AudioTools - Spectral_Drift.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral Drift - frequency-dependent comb filtering with
#   random drift. Creates peaks and notches at harmonic
#   intervals, but with random shifting for organic character.
#   The cosine modulation makes the effect vary with frequency.
#   Creates metallic, phaser-like spectral coloration.
#
# Changelog v0.2:
#   - Added input check
#   - Fixed selection and formula syntax
#   - Fixed out-of-bounds array access
#   - Added wet/dry mix control
#   - Added visualization
# ============================================================

form Spectral Drift
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Subtle Drift
        option Medium Drift
        option Heavy Drift
        option Extreme Drift
    
    comment === Drift Parameters ===
    positive Tail_duration_s 0.5
    natural Number_of_cycles 4
    positive Base_frequency_Hz 100
    positive Effect_strength 0.4
    
    comment === Mix ===
    real Wet_dry_percent 60
    comment (0 = dry only, 100 = wet only)
    
    comment === Output ===
    positive Fadeout_duration_s 1.2
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
numSamples = Get number of samples

# === Apply Presets ===
if preset = 2
    # Subtle Drift
    tail_duration_s = 0.3
    number_of_cycles = 2
    base_frequency_Hz = 150
    effect_strength = 0.2
    fadeout_duration_s = 0.8
    presetName$ = "Subtle"
elsif preset = 3
    # Medium Drift
    tail_duration_s = 0.5
    number_of_cycles = 4
    base_frequency_Hz = 100
    effect_strength = 0.4
    fadeout_duration_s = 1.2
    presetName$ = "Medium"
elsif preset = 4
    # Heavy Drift
    tail_duration_s = 0.8
    number_of_cycles = 6
    base_frequency_Hz = 75
    effect_strength = 0.6
    fadeout_duration_s = 1.5
    presetName$ = "Heavy"
elsif preset = 5
    # Extreme Drift
    tail_duration_s = 1.2
    number_of_cycles = 10
    base_frequency_Hz = 50
    effect_strength = 0.8
    fadeout_duration_s = 2.0
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

# Pre-calculate drift parameters for visualization
for cycle from 1 to number_of_cycles
    cycleFreq[cycle] = base_frequency_Hz * cycle
    cycleDelay[cycle] = sr / cycleFreq[cycle]
    cycleDrift[cycle] = randomUniform(0.5, 2.0)
    cycleActualDelay[cycle] = cycleDelay[cycle] * cycleDrift[cycle]
endfor

# === Info ===
writeInfoLine: "=== Spectral Drift ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Drift cycles: ", number_of_cycles
appendInfoLine: "Base frequency: ", base_frequency_Hz, " Hz"
appendInfoLine: "Effect strength: ", effect_strength
appendInfoLine: "Wet/Dry: ", wet_dry_percent, "%"
appendInfoLine: ""
appendInfoLine: "Cycle frequencies:"
for cycle from 1 to number_of_cycles
    appendInfoLine: "  Cycle ", cycle, ": ", fixed$(cycleFreq[cycle], 1), " Hz, delay ", fixed$(cycleActualDelay[cycle], 1), " samples"
endfor
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

totalSamples = round(totalDur * sr)
sr_str$ = string$(sr)

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
    Copy: "drift_left"
    driftLeft = selected("Sound")
    
    for cycle from 1 to number_of_cycles
        base_freq = base_frequency_Hz * cycle
        delay_samples = round(sr / base_freq)
        drift_amount = randomUniform(0.5, 2.0)
        actual_delay = round(delay_samples * drift_amount)
        
        # Ensure we don't go out of bounds (use backward reference)
        if actual_delay < 1
            actual_delay = 1
        endif
        
        delay_str$ = string$(actual_delay)
        freq_str$ = string$(base_freq)
        strength_str$ = string$(effect_strength)
        
        selectObject: driftLeft
        # Use backward reference to avoid out-of-bounds
        Formula: "if col > " + delay_str$ + " then self + " + strength_str$ + " * (self[col - " + delay_str$ + "] - self) * cos(2*pi*col*" + freq_str$ + "/" + sr_str$ + ") else self fi"
    endfor
    
    Scale peak: 0.98
    
    # Process right channel (slightly different parameters)
    selectObject: rightChannel
    Copy: "drift_right"
    driftRight = selected("Sound")
    
    for cycle from 1 to number_of_cycles
        base_freq = base_frequency_Hz * 1.05 * cycle
        delay_samples = round(sr / base_freq)
        drift_amount = randomUniform(0.6, 1.9)
        actual_delay = round(delay_samples * drift_amount)
        
        if actual_delay < 1
            actual_delay = 1
        endif
        
        delay_str$ = string$(actual_delay)
        freq_str$ = string$(base_freq)
        strength_R = effect_strength * 0.95
        strength_str$ = string$(strength_R)
        
        selectObject: driftRight
        Formula: "if col > " + delay_str$ + " then self + " + strength_str$ + " * (self[col - " + delay_str$ + "] - self) * cos(2*pi*col*" + freq_str$ + "/" + sr_str$ + ") else self fi"
    endfor
    
    Scale peak: 0.98
    
    # Apply wet/dry mix
    if dry_level > 0
        wet_str$ = string$(wet_level)
        dry_str$ = string$(dry_level)
        left_str$ = string$(leftChannel)
        right_str$ = string$(rightChannel)
        
        selectObject: driftLeft
        Formula: "self * " + wet_str$ + " + object[" + left_str$ + "] * " + dry_str$
        
        selectObject: driftRight
        Formula: "self * " + wet_str$ + " + object[" + right_str$ + "] * " + dry_str$
    endif
    
    # Apply fadeout
    fade_start = totalDur - fadeout_duration_s
    fade_str$ = string$(fadeout_duration_s)
    start_str$ = string$(fade_start)
    
    selectObject: driftLeft
    Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"
    
    selectObject: driftRight
    Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"
    
    # Combine
    selectObject: driftLeft, driftRight
    Combine to stereo
    result = selected("Sound")
    Rename: originalName$ + "_drift_" + presetName$
    
    # Cleanup
    removeObject: leftChannel, rightChannel, driftLeft, driftRight, extendedSound

else
    # === MONO PROCESSING ===
    appendInfoLine: "  Processing mono..."
    
    selectObject: extendedSound
    Copy: "drift_mono"
    driftMono = selected("Sound")
    
    for cycle from 1 to number_of_cycles
        base_freq = base_frequency_Hz * cycle
        delay_samples = round(sr / base_freq)
        drift_amount = randomUniform(0.5, 2.0)
        actual_delay = round(delay_samples * drift_amount)
        
        if actual_delay < 1
            actual_delay = 1
        endif
        
        delay_str$ = string$(actual_delay)
        freq_str$ = string$(base_freq)
        strength_str$ = string$(effect_strength)
        
        selectObject: driftMono
        Formula: "if col > " + delay_str$ + " then self + " + strength_str$ + " * (self[col - " + delay_str$ + "] - self) * cos(2*pi*col*" + freq_str$ + "/" + sr_str$ + ") else self fi"
    endfor
    
    Scale peak: 0.98
    
    # Apply wet/dry mix
    if dry_level > 0
        wet_str$ = string$(wet_level)
        dry_str$ = string$(dry_level)
        ext_str$ = string$(extendedSound)
        
        selectObject: driftMono
        Formula: "self * " + wet_str$ + " + object[" + ext_str$ + "] * " + dry_str$
    endif
    
    # Apply fadeout
    fade_start = totalDur - fadeout_duration_s
    fade_str$ = string$(fadeout_duration_s)
    start_str$ = string$(fade_start)
    
    selectObject: driftMono
    Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"
    
    Rename: originalName$ + "_drift_" + presetName$
    result = driftMono
    
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
    Text: 0.5, "centre", 0.5, "half", "Spectral Drift: " + originalName$ + " (" + presetName$ + ")"
    
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
    Colour: "{0.6, 0.7, 0.5}"
    Draw: 0, originalDur, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Drift " + fixed$(wet_dry_percent, 0) + "%"
    Text bottom: "yes", "Time (s)"
    
    # Drift cycle diagram
    Select outer viewport: 0, 8, 2.5, 4.0
    Select inner viewport: 0.6, 7.6, 2.6, 3.9
    
    maxFreq = base_frequency_Hz * number_of_cycles * 1.2
    maxDelay = sr / base_frequency_Hz * 2.5
    
    Axes: 0, maxFreq, 0, maxDelay
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, maxFreq, 0, maxDelay
    
    # Draw ideal delay curve (no drift)
    Colour: "{0.85, 0.85, 0.85}"
    Line width: 1.5
    Dotted line
    prevX = base_frequency_Hz
    prevY = sr / base_frequency_Hz
    for f from 1 to 50
        freq = base_frequency_Hz + (maxFreq - base_frequency_Hz) * f / 50
        delay = sr / freq
        Draw line: prevX, prevY, freq, delay
        prevX = freq
        prevY = delay
    endfor
    Solid line
    
    # Draw actual drift points
    for cycle from 1 to number_of_cycles
        freq = cycleFreq[cycle]
        idealDelay = cycleDelay[cycle]
        actualDelay = cycleActualDelay[cycle]
        
        # Ideal point (grey)
        Colour: "{0.7, 0.7, 0.7}"
        Paint circle (mm): "{0.7, 0.7, 0.7}", freq, idealDelay, 1.5
        
        # Actual drifted point (colored)
        if cycleDrift[cycle] > 1
            col$ = "{0.8, 0.5, 0.4}"
        else
            col$ = "{0.4, 0.6, 0.8}"
        endif
        Colour: col$
        Paint circle (mm): col$, freq, actualDelay, 2.5
        
        # Arrow from ideal to actual
        Colour: "{0.6, 0.6, 0.6}"
        Line width: 1
        Arrow size: 0.8
        Draw arrow: freq, idealDelay, freq, actualDelay
    endfor
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Delay (samples)"
    Text bottom: "yes", "Frequency (Hz)"
    
    # Legend
    Font size: 5
    Colour: "{0.8, 0.5, 0.4}"
    Text: maxFreq * 0.85, "centre", maxDelay * 0.9, "half", "● Drift > 1 (longer)"
    Colour: "{0.4, 0.6, 0.8}"
    Text: maxFreq * 0.85, "centre", maxDelay * 0.8, "half", "● Drift < 1 (shorter)"
    Colour: "{0.7, 0.7, 0.7}"
    Text: maxFreq * 0.85, "centre", maxDelay * 0.7, "half", "○ Ideal (no drift)"
    
    # Parameters
    Select outer viewport: 0, 8, 4.1, 4.5
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Cycles: " + string$(number_of_cycles) + " | Base freq: " + string$(base_frequency_Hz) + " Hz | Strength: " + fixed$(effect_strength, 2) + " | Drift range: 0.5-2.0×"
    
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
