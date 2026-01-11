# ============================================================
# Praat AudioTools - Temporal_Erosion.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Temporal Erosion - convolution reverb with logarithmic
#   decay envelope and random amplitude "erosion". Unlike
#   Spectral_Decay's exponential chirp, this uses logarithmic
#   decay (faster initial drop, slower tail) with Gaussian
#   random modulation for organic, "weathered" texture.
#
# Changelog v0.2:
#   - Added input check
#   - Fixed selection and formula syntax
#   - Fixed wet/dry mixing (proper formula-based)
#   - Added visualization
# ============================================================

form Temporal Erosion
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Subtle Erosion
        option Medium Erosion
        option Heavy Erosion
        option Extreme Erosion
    
    comment === IR Parameters ===
    positive Tail_duration_s 3.0
    positive Impulse_duration_s 5.0
    positive Poisson_density 2500
    
    comment === Filtering ===
    positive Low_cutoff_Hz 100
    positive High_cutoff_Hz 8000
    positive Smoothing_Hz 100
    
    comment === Erosion ===
    positive Erosion_randomness 0.3
    comment (standard deviation of Gaussian amplitude variation)
    
    comment === Mix ===
    real Wet_dry_percent 50
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

# === Apply Presets ===
if preset = 2
    # Subtle Erosion
    tail_duration_s = 2.0
    impulse_duration_s = 3.0
    poisson_density = 1500
    low_cutoff_Hz = 120
    high_cutoff_Hz = 7000
    smoothing_Hz = 80
    erosion_randomness = 0.2
    fadeout_duration_s = 1.0
    wet_dry_percent = 35
    presetName$ = "Subtle"
elsif preset = 3
    # Medium Erosion
    tail_duration_s = 3.0
    impulse_duration_s = 5.0
    poisson_density = 2500
    low_cutoff_Hz = 100
    high_cutoff_Hz = 8000
    smoothing_Hz = 100
    erosion_randomness = 0.3
    fadeout_duration_s = 1.2
    wet_dry_percent = 50
    presetName$ = "Medium"
elsif preset = 4
    # Heavy Erosion
    tail_duration_s = 4.0
    impulse_duration_s = 7.0
    poisson_density = 4000
    low_cutoff_Hz = 80
    high_cutoff_Hz = 9000
    smoothing_Hz = 120
    erosion_randomness = 0.4
    fadeout_duration_s = 1.5
    wet_dry_percent = 65
    presetName$ = "Heavy"
elsif preset = 5
    # Extreme Erosion
    tail_duration_s = 5.0
    impulse_duration_s = 10.0
    poisson_density = 6000
    low_cutoff_Hz = 60
    high_cutoff_Hz = 10000
    smoothing_Hz = 150
    erosion_randomness = 0.5
    fadeout_duration_s = 2.0
    wet_dry_percent = 80
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

# === Info ===
writeInfoLine: "=== Temporal Erosion ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "IR duration: ", impulse_duration_s, " s"
appendInfoLine: "Poisson density: ", poisson_density, " events/s"
appendInfoLine: "Erosion randomness: ", erosion_randomness
appendInfoLine: "Bandpass: ", low_cutoff_Hz, " - ", high_cutoff_Hz, " Hz"
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

# Erosion randomness string
erosion_str$ = string$(erosion_randomness)

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
    # Create Poisson IR for left
    Create Poisson process: "poisson_left", 0, impulse_duration_s, poisson_density
    poissonLeft = selected("PointProcess")
    To Sound (pulse train): sr, 1, 0.02, 4000
    irLeft = selected("Sound")
    
    # Apply logarithmic decay with erosion
    Formula: "self * (1 - log10(1 + 9*(x-xmin)/(xmax-xmin))) * randomGauss(1, " + erosion_str$ + ")"
    
    # Convolve left
    selectObject: leftChannel, irLeft
    Convolve: "sum", "zero"
    convLeft = selected("Sound")
    
    # Bandpass filter
    Filter (pass Hann band): low_cutoff_Hz, high_cutoff_Hz, smoothing_Hz
    filtLeft = selected("Sound")
    removeObject: convLeft
    
    # === RIGHT CHANNEL ===
    # Create Poisson IR for right (slightly different)
    Create Poisson process: "poisson_right", 0, impulse_duration_s * 0.96, poisson_density * 0.92
    poissonRight = selected("PointProcess")
    To Sound (pulse train): sr, 1, 0.018, 3800
    irRight = selected("Sound")
    
    erosion_R = erosion_randomness * 1.17
    erosion_R_str$ = string$(erosion_R)
    Formula: "self * (1 - log10(1 + 8.5*(x-xmin)/(xmax-xmin))) * randomGauss(1, " + erosion_R_str$ + ")"
    
    # Convolve right
    selectObject: rightChannel, irRight
    Convolve: "sum", "zero"
    convRight = selected("Sound")
    
    # Bandpass filter (slightly different)
    Filter (pass Hann band): low_cutoff_Hz * 1.2, high_cutoff_Hz * 0.94, smoothing_Hz * 0.9
    filtRight = selected("Sound")
    removeObject: convRight
    
    # Normalize wet signals
    selectObject: filtLeft
    Scale peak: 0.92
    
    selectObject: filtRight
    Scale peak: 0.92
    
    # Apply wet/dry mix
    wet_str$ = string$(wet_level)
    dry_str$ = string$(dry_level)
    left_str$ = string$(leftChannel)
    right_str$ = string$(rightChannel)
    
    selectObject: filtLeft
    Formula: "self * " + wet_str$ + " + object[" + left_str$ + "] * " + dry_str$
    
    selectObject: filtRight
    Formula: "self * " + wet_str$ + " + object[" + right_str$ + "] * " + dry_str$
    
    # Apply fadeout - handle duration mismatch
    selectObject: filtLeft
    wetDur = Get total duration
    
    if wetDur > totalDur
        selectObject: filtLeft
        Extract part: 0, totalDur, "rectangular", 1, "no"
        filtLeftTrim = selected("Sound")
        removeObject: filtLeft
        filtLeft = filtLeftTrim
        
        selectObject: filtRight
        Extract part: 0, totalDur, "rectangular", 1, "no"
        filtRightTrim = selected("Sound")
        removeObject: filtRight
        filtRight = filtRightTrim
    endif
    
    fade_start = totalDur - fadeout_duration_s
    fade_str$ = string$(fadeout_duration_s)
    start_str$ = string$(fade_start)
    
    selectObject: filtLeft
    Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"
    Scale peak: 0.95
    
    selectObject: filtRight
    Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"
    Scale peak: 0.95
    
    # Combine to stereo
    selectObject: filtLeft, filtRight
    Combine to stereo
    result = selected("Sound")
    Rename: originalName$ + "_erosion_" + presetName$
    
    # Cleanup
    removeObject: leftChannel, rightChannel, extendedSound
    removeObject: poissonLeft, poissonRight, irLeft, irRight
    removeObject: filtLeft, filtRight

else
    # === MONO PROCESSING ===
    appendInfoLine: "  Processing mono..."
    
    # Create Poisson IR
    Create Poisson process: "poisson_mono", 0, impulse_duration_s, poisson_density
    poissonMono = selected("PointProcess")
    To Sound (pulse train): sr, 1, 0.02, 4000
    irMono = selected("Sound")
    
    # Apply logarithmic decay with erosion
    Formula: "self * (1 - log10(1 + 9*(x-xmin)/(xmax-xmin))) * randomGauss(1, " + erosion_str$ + ")"
    
    # Convolve
    selectObject: extendedSound, irMono
    Convolve: "sum", "zero"
    convMono = selected("Sound")
    
    # Bandpass filter
    Filter (pass Hann band): low_cutoff_Hz, high_cutoff_Hz, smoothing_Hz
    filtMono = selected("Sound")
    removeObject: convMono
    
    Scale peak: 0.92
    
    # Apply wet/dry mix
    wet_str$ = string$(wet_level)
    dry_str$ = string$(dry_level)
    ext_str$ = string$(extendedSound)
    
    selectObject: filtMono
    
    # Handle duration mismatch
    wetDur = Get total duration
    if wetDur > totalDur
        Extract part: 0, totalDur, "rectangular", 1, "no"
        filtMonoTrim = selected("Sound")
        removeObject: filtMono
        filtMono = filtMonoTrim
    endif
    
    selectObject: filtMono
    Formula: "self * " + wet_str$ + " + object[" + ext_str$ + "] * " + dry_str$
    
    # Apply fadeout
    fade_start = totalDur - fadeout_duration_s
    fade_str$ = string$(fadeout_duration_s)
    start_str$ = string$(fade_start)
    
    Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"
    
    Scale peak: 0.95
    Rename: originalName$ + "_erosion_" + presetName$
    result = filtMono
    
    # Cleanup
    removeObject: extendedSound, poissonMono, irMono
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
    Text: 0.5, "centre", 0.5, "half", "Temporal Erosion: " + originalName$ + " (" + presetName$ + ")"
    
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
    Colour: "{0.6, 0.5, 0.5}"
    Draw: 0, originalDur, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Erosion " + fixed$(wet_dry_percent, 0) + "%"
    Text bottom: "yes", "Time (s)"
    
    # Decay curve comparison
    Select outer viewport: 0, 4, 2.5, 4.0
    Select inner viewport: 0.5, 3.7, 2.7, 3.85
    
    Axes: 0, 1, 0, 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1.2
    
    # Logarithmic decay (this script)
    Colour: "{0.7, 0.4, 0.4}"
    Line width: 2
    
    prevX = 0
    prevY = 1
    for i from 1 to 50
        t = i / 50
        env = 1 - ln(1 + 9 * t) / ln(10)
        if env < 0
            env = 0
        endif
        Draw line: prevX, prevY, t, env
        prevX = t
        prevY = env
    endfor
    
    # Exponential decay (for comparison)
    Colour: "{0.5, 0.5, 0.7}"
    Dotted line
    prevX = 0
    prevY = 1
    for i from 1 to 50
        t = i / 50
        env = exp(-3 * t)
        Draw line: prevX, prevY, t, env
        prevX = t
        prevY = env
    endfor
    Solid line
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Normalized time"
    
    # Legend
    Font size: 5
    Colour: "{0.7, 0.4, 0.4}"
    Text: 0.7, "centre", 1.1, "half", "— Log: 1-log₁₀(1+9t)"
    Colour: "{0.5, 0.5, 0.7}"
    Text: 0.7, "centre", 0.95, "half", "-- Exp: e^(-3t)"
    
    # Title
    Font size: 8
    Colour: "Black"
    Select outer viewport: 0, 4, 2.35, 2.55
    Text: 0.5, "centre", 0.5, "half", "DECAY COMPARISON"
    
    # Bandpass filter
    Select outer viewport: 4, 8, 2.5, 4.0
    Select inner viewport: 4.5, 7.7, 2.7, 3.85
    
    Axes: 0, sr / 2 / 1000, 0, 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, sr / 2 / 1000, 0, 1.2
    
    # Draw bandpass shape
    Colour: "{0.5, 0.7, 0.6}"
    Line width: 2
    
    lowK = low_cutoff_Hz / 1000
    highK = high_cutoff_Hz / 1000
    smoothK = smoothing_Hz / 1000
    
    Draw line: 0, 0, lowK - smoothK, 0
    Draw line: lowK - smoothK, 0, lowK, 1
    Draw line: lowK, 1, highK, 1
    Draw line: highK, 1, highK + smoothK, 0
    Draw line: highK + smoothK, 0, sr / 2 / 1000, 0
    
    Line width: 1
    
    # Fill passband
    Paint rectangle: "{0.8, 0.9, 0.85}", lowK, highK, 0, 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Gain"
    Text bottom: "yes", "Frequency (kHz)"
    
    # Title
    Font size: 8
    Select outer viewport: 4, 8, 2.35, 2.55
    Text: 0.5, "centre", 0.5, "half", "BANDPASS FILTER"
    
    # Parameters
    Select outer viewport: 0, 8, 4.1, 4.5
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "IR: " + fixed$(impulse_duration_s, 1) + "s | Density: " + string$(poisson_density) + " | Erosion σ: " + fixed$(erosion_randomness, 2) + " | Band: " + string$(low_cutoff_Hz) + "-" + string$(high_cutoff_Hz) + "Hz"
    
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