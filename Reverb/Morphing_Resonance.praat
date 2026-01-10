# ============================================================
# Praat AudioTools - Morphing_Resonance.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Morphing Resonance - creates reverb with frequency-sweeping
#   (chirp) modulation. The impulse response has a frequency
#   that increases over time, creating shimmering, evolving
#   reverb tails. Includes chorus layer for added thickness.
#   Stereo processing uses decorrelated parameters.
#
# Changelog v0.2:
#   - Fixed selection and formula syntax
#   - Fixed chorus delay formula
#   - Added wet/dry mix control
#   - Added visualization
# ============================================================

form Morphing Resonance
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Subtle Morphing
        option Medium Morphing
        option Heavy Morphing
        option Extreme Morphing
    
    comment === Reverb Parameters ===
    positive Tail_duration_s 2.0
    positive Poisson_density 1800
    positive Exponential_base 85
    
    comment === Chirp Modulation ===
    positive Frequency_start_Hz 220
    positive Frequency_range_Hz 880
    positive Modulation_depth 0.5
    
    comment === Chorus ===
    positive Chorus_mix 0.3
    positive Chorus_delay_ms 10
    
    comment === Mix ===
    positive Convolution_mix 0.32
    real Wet_dry_percent 60
    comment (0 = dry only, 100 = wet only)
    
    comment === Output ===
    positive Fadeout_duration_s 1.0
    positive Scale_peak 0.9
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
    # Subtle Morphing
    tail_duration_s = 1.5
    poisson_density = 1200
    exponential_base = 95
    frequency_start_Hz = 180
    frequency_range_Hz = 600
    modulation_depth = 0.35
    convolution_mix = 0.22
    chorus_mix = 0.2
    chorus_delay_ms = 8
    fadeout_duration_s = 0.8
    presetName$ = "Subtle"
elsif preset = 3
    # Medium Morphing
    tail_duration_s = 2.0
    poisson_density = 1800
    exponential_base = 85
    frequency_start_Hz = 220
    frequency_range_Hz = 880
    modulation_depth = 0.5
    convolution_mix = 0.32
    chorus_mix = 0.3
    chorus_delay_ms = 10
    fadeout_duration_s = 1.0
    presetName$ = "Medium"
elsif preset = 4
    # Heavy Morphing
    tail_duration_s = 2.5
    poisson_density = 2400
    exponential_base = 75
    frequency_start_Hz = 260
    frequency_range_Hz = 1150
    modulation_depth = 0.65
    convolution_mix = 0.42
    chorus_mix = 0.4
    chorus_delay_ms = 12
    fadeout_duration_s = 1.4
    presetName$ = "Heavy"
elsif preset = 5
    # Extreme Morphing
    tail_duration_s = 3.5
    poisson_density = 3200
    exponential_base = 65
    frequency_start_Hz = 300
    frequency_range_Hz = 1500
    modulation_depth = 0.8
    convolution_mix = 0.52
    chorus_mix = 0.5
    chorus_delay_ms = 15
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

# Convert chorus delay to seconds
chorus_delay_s = chorus_delay_ms / 1000

# IR duration
irDuration = 4.5

# === Info ===
writeInfoLine: "=== Morphing Resonance ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Poisson density: ", poisson_density, " impulses/s"
appendInfoLine: "Exponential base: ", exponential_base
appendInfoLine: "Chirp: ", frequency_start_Hz, " → ", frequency_start_Hz + frequency_range_Hz, " Hz"
appendInfoLine: "Modulation depth: ", modulation_depth
appendInfoLine: "Chorus: ", chorus_mix, " @ ", chorus_delay_ms, " ms"
appendInfoLine: "Wet/Dry: ", wet_dry_percent, "%"
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

# Build formula strings
base_str$ = string$(exponential_base)
depth_str$ = string$(modulation_depth)
fstart_str$ = string$(frequency_start_Hz)
frange_str$ = string$(frequency_range_Hz)
mix_str$ = string$(convolution_mix)
chorus_str$ = string$(chorus_mix)

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
    
    # === LEFT CHANNEL ===
    appendInfoLine: "  Creating left IR..."
    
    selectObject: leftChannel
    Copy: "sound_left"
    aLeft = selected("Sound")
    
    Create Poisson process: "poisson_L", 0, irDuration, poisson_density
    poissonL = selected("PointProcess")
    
    To Sound (pulse train): sr, 1, 0.055, 2200
    irLeftRaw = selected("Sound")
    
    # Apply chirp modulation envelope
    Formula: "self * " + base_str$ + "^(-(x-xmin)/(xmax-xmin)) * (1 + " + depth_str$ + "*sin(2*pi*x*(" + fstart_str$ + " + " + frange_str$ + "*(x-xmin)/(xmax-xmin))) * exp(-3*(x-xmin)/(xmax-xmin)))"
    irLeft = irLeftRaw
    
    # Convolve
    selectObject: aLeft, irLeft
    Convolve: "sum", "zero"
    bLeft = selected("Sound")
    Formula: "self * " + mix_str$
    
    # Add chorus (delayed copy)
    selectObject: bLeft
    Copy: "chorus_left"
    chorusLeft = selected("Sound")
    
    delay_samp = round(chorus_delay_s * sr)
    delay_str$ = string$(delay_samp)
    
    Formula: "if col > " + delay_str$ + " then 0.7 * (self + " + chorus_str$ + " * self[col - " + delay_str$ + "]) else self * 0.7 fi"
    
    # Combine: dry + chorus
    aLeft_str$ = string$(aLeft)
    chorusLeft_str$ = string$(chorusLeft)
    
    selectObject: aLeft
    Copy: "result_left"
    resultLeft = selected("Sound")
    Formula: "self + object[" + chorusLeft_str$ + "]"
    
    # === RIGHT CHANNEL (decorrelated) ===
    appendInfoLine: "  Creating right IR..."
    
    selectObject: rightChannel
    Copy: "sound_right"
    aRight = selected("Sound")
    
    # Slightly different parameters
    densityR = poisson_density * 0.97
    Create Poisson process: "poisson_R", 0, irDuration * 0.96, densityR
    poissonR = selected("PointProcess")
    
    To Sound (pulse train): sr, 1, 0.05, 2100
    irRightRaw = selected("Sound")
    
    # Different chirp parameters
    baseR_str$ = string$(exponential_base * 0.94)
    depthR_str$ = string$(modulation_depth * 0.9)
    fstartR_str$ = string$(frequency_start_Hz * 1.09)
    frangeR_str$ = string$(frequency_range_Hz * 0.91)
    
    Formula: "self * " + baseR_str$ + "^(-(x-xmin)/(xmax-xmin)) * (1 + " + depthR_str$ + "*sin(2*pi*x*(" + fstartR_str$ + " + " + frangeR_str$ + "*(x-xmin)/(xmax-xmin))) * exp(-2.8*(x-xmin)/(xmax-xmin)))"
    irRight = irRightRaw
    
    # Convolve
    selectObject: aRight, irRight
    Convolve: "sum", "zero"
    bRight = selected("Sound")
    mixR_str$ = string$(convolution_mix * 0.94)
    Formula: "self * " + mixR_str$
    
    # Add chorus
    selectObject: bRight
    Copy: "chorus_right"
    chorusRight = selected("Sound")
    
    delayR_samp = round(chorus_delay_s * 0.8 * sr)
    delayR_str$ = string$(delayR_samp)
    chorusR_str$ = string$(chorus_mix * 0.83)
    
    Formula: "if col > " + delayR_str$ + " then 0.7 * (self + " + chorusR_str$ + " * self[col - " + delayR_str$ + "]) else self * 0.7 fi"
    
    # Combine
    chorusRight_str$ = string$(chorusRight)
    
    selectObject: aRight
    Copy: "result_right"
    resultRight = selected("Sound")
    Formula: "self + object[" + chorusRight_str$ + "]"
    
    # === APPLY WET/DRY ===
    if dry_level > 0
        wet_str$ = string$(wet_level)
        dry_str$ = string$(dry_level)
        left_str$ = string$(leftChannel)
        right_str$ = string$(rightChannel)
        
        selectObject: resultLeft
        Formula: "self * " + wet_str$ + " + object[" + left_str$ + "] * " + dry_str$
        
        selectObject: resultRight
        Formula: "self * " + wet_str$ + " + object[" + right_str$ + "] * " + dry_str$
    endif
    
    # Apply fadeout
    fade_start = totalDur - fadeout_duration_s
    fade_str$ = string$(fadeout_duration_s)
    start_str$ = string$(fade_start)
    
    selectObject: resultLeft
    Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"
    Scale peak: scale_peak
    
    selectObject: resultRight
    Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"
    Scale peak: scale_peak
    
    # Combine to stereo
    selectObject: resultLeft, resultRight
    Combine to stereo
    result = selected("Sound")
    Rename: originalName$ + "_morphing_" + presetName$
    
    # Store IR for visualization
    irForViz = irLeft
    
    # Cleanup
    removeObject: poissonL, poissonR
    removeObject: irRight
    removeObject: leftChannel, rightChannel
    removeObject: aLeft, aRight
    removeObject: bLeft, bRight
    removeObject: chorusLeft, chorusRight
    removeObject: resultLeft, resultRight
    removeObject: extendedSound

else
    # === MONO PROCESSING ===
    appendInfoLine: "  Processing mono..."
    
    selectObject: extendedSound
    Copy: "sound_mono"
    aMono = selected("Sound")
    
    Create Poisson process: "poisson_mono", 0, irDuration, poisson_density
    poissonMono = selected("PointProcess")
    
    To Sound (pulse train): sr, 1, 0.055, 2200
    irMono = selected("Sound")
    
    Formula: "self * " + base_str$ + "^(-(x-xmin)/(xmax-xmin)) * (1 + " + depth_str$ + "*sin(2*pi*x*(" + fstart_str$ + " + " + frange_str$ + "*(x-xmin)/(xmax-xmin))) * exp(-3*(x-xmin)/(xmax-xmin)))"
    
    # Convolve
    selectObject: aMono, irMono
    Convolve: "sum", "zero"
    bMono = selected("Sound")
    Formula: "self * " + mix_str$
    
    # Add chorus
    selectObject: bMono
    Copy: "chorus_mono"
    chorusMono = selected("Sound")
    
    delay_samp = round(chorus_delay_s * sr)
    delay_str$ = string$(delay_samp)
    
    Formula: "if col > " + delay_str$ + " then 0.7 * (self + " + chorus_str$ + " * self[col - " + delay_str$ + "]) else self * 0.7 fi"
    
    # Combine
    chorusMono_str$ = string$(chorusMono)
    
    selectObject: aMono
    Copy: "result_mono"
    resultMono = selected("Sound")
    Formula: "self + object[" + chorusMono_str$ + "]"
    
    # Apply wet/dry
    if dry_level > 0
        wet_str$ = string$(wet_level)
        dry_str$ = string$(dry_level)
        ext_str$ = string$(extendedSound)
        
        selectObject: resultMono
        Formula: "self * " + wet_str$ + " + object[" + ext_str$ + "] * " + dry_str$
    endif
    
    # Apply fadeout
    fade_start = totalDur - fadeout_duration_s
    fade_str$ = string$(fadeout_duration_s)
    start_str$ = string$(fade_start)
    
    selectObject: resultMono
    Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"
    
    Scale peak: scale_peak
    Rename: originalName$ + "_morphing_" + presetName$
    result = resultMono
    
    # Store IR for visualization
    irForViz = irMono
    
    # Cleanup
    removeObject: poissonMono, aMono, bMono, chorusMono, extendedSound
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
    Text: 0.5, "centre", 0.5, "half", "Morphing Resonance: " + originalName$ + " (" + presetName$ + ")"
    
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
    Text left: "yes", "Morph " + fixed$(wet_dry_percent, 0) + "%"
    Text bottom: "yes", "Time (s)"
    
    # IR waveform
    Select outer viewport: 0, 4, 2.5, 3.6
    Select inner viewport: 0.6, 3.8, 2.6, 3.5
    selectObject: irForViz
    Colour: "{0.5, 0.6, 0.7}"
    Draw: 0, min(2, irDuration), 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "IR"
    Text bottom: "yes", "Time (s)"
    
    # Chirp frequency diagram
    Select outer viewport: 4, 8, 2.5, 3.6
    Select inner viewport: 4.4, 7.6, 2.6, 3.5
    
    fEnd = frequency_start_Hz + frequency_range_Hz
    Axes: 0, irDuration, 0, fEnd * 1.1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, irDuration, 0, fEnd * 1.1
    
    # Draw frequency sweep
    Colour: "{0.6, 0.5, 0.7}"
    Line width: 2
    nPoints = 100
    for p from 2 to nPoints
        t1 = (p - 2) / nPoints * irDuration
        t2 = (p - 1) / nPoints * irDuration
        
        f1 = frequency_start_Hz + frequency_range_Hz * (t1 / irDuration)
        f2 = frequency_start_Hz + frequency_range_Hz * (t2 / irDuration)
        
        Draw line: t1, f1, t2, f2
    endfor
    Line width: 1
    
    # Draw modulation envelope
    Colour: "{0.7, 0.6, 0.5}"
    Dotted line
    for p from 2 to nPoints
        t1 = (p - 2) / nPoints * irDuration
        t2 = (p - 1) / nPoints * irDuration
        
        env1 = exp(-3 * t1 / irDuration) * fEnd * 0.3 + frequency_start_Hz
        env2 = exp(-3 * t2 / irDuration) * fEnd * 0.3 + frequency_start_Hz
        
        Draw line: t1, env1, t2, env2
    endfor
    Solid line
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Freq (Hz)"
    Text bottom: "yes", "Time (s)"
    
    # Legend
    Font size: 5
    Colour: "{0.6, 0.5, 0.7}"
    Text: irDuration * 0.75, "centre", fEnd * 1.0, "half", "Chirp freq"
    Colour: "{0.7, 0.6, 0.5}"
    Text: irDuration * 0.75, "centre", fEnd * 0.9, "half", "Mod envelope"
    
    # Parameters
    Select outer viewport: 0, 8, 3.7, 4.1
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Chirp: " + string$(frequency_start_Hz) + "→" + string$(frequency_start_Hz + frequency_range_Hz) + "Hz | Mod: " + fixed$(modulation_depth, 2) + " | Chorus: " + fixed$(chorus_mix, 2) + " @ " + string$(chorus_delay_ms) + "ms"
    
    Font size: 10
    Colour: "Black"
    
    # Cleanup IR
    removeObject: irForViz
endif

# If no visualization, still cleanup IR
if draw_visualization = 0
    removeObject: irForViz
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