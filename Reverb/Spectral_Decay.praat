# ============================================================
# Praat AudioTools - Spectral_Decay.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral Decay Reverb - convolution reverb with bandpass
#   filtering and chirp-modulated Poisson impulse response.
#   The IR has exponential decay with sinusoidal modulation
#   that sweeps in frequency (chirp). Bandpass filter shapes
#   the spectral content of the reverb (100-4000 Hz).
#
# Changelog v0.2:
#   - Added input check
#   - Fixed selection and formula syntax
#   - Fixed wet/dry mixing (proper formula-based)
#   - Added visualization
# ============================================================

form Spectral Decay Reverb
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Subtle Decay
        option Medium Decay
        option Heavy Decay
        option Extreme Decay
    
    comment === IR Parameters ===
    positive Tail_duration_s 2.0
    positive Impulse_duration_s 3.0
    positive Poisson_density 2000
    positive Decay_base 110
    
    comment === Spectral Filtering ===
    positive Low_cutoff_Hz 100
    positive High_cutoff_Hz 4000
    positive Smoothing_Hz 100
    
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
    # Subtle Decay
    tail_duration_s = 1.5
    impulse_duration_s = 2.0
    poisson_density = 1200
    decay_base = 150
    low_cutoff_Hz = 120
    high_cutoff_Hz = 3500
    smoothing_Hz = 80
    fadeout_duration_s = 0.8
    wet_dry_percent = 35
    presetName$ = "Subtle"
elsif preset = 3
    # Medium Decay
    tail_duration_s = 2.0
    impulse_duration_s = 3.0
    poisson_density = 2000
    decay_base = 110
    low_cutoff_Hz = 100
    high_cutoff_Hz = 4000
    smoothing_Hz = 100
    fadeout_duration_s = 1.2
    wet_dry_percent = 50
    presetName$ = "Medium"
elsif preset = 4
    # Heavy Decay
    tail_duration_s = 3.0
    impulse_duration_s = 4.5
    poisson_density = 3000
    decay_base = 80
    low_cutoff_Hz = 80
    high_cutoff_Hz = 4500
    smoothing_Hz = 120
    fadeout_duration_s = 1.8
    wet_dry_percent = 65
    presetName$ = "Heavy"
elsif preset = 5
    # Extreme Decay
    tail_duration_s = 4.5
    impulse_duration_s = 6.5
    poisson_density = 4500
    decay_base = 50
    low_cutoff_Hz = 60
    high_cutoff_Hz = 5000
    smoothing_Hz = 150
    fadeout_duration_s = 2.5
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
writeInfoLine: "=== Spectral Decay Reverb ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "IR duration: ", impulse_duration_s, " s"
appendInfoLine: "Poisson density: ", poisson_density, " events/s"
appendInfoLine: "Decay base: ", decay_base
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

# Create impulse response string
decay_str$ = string$(decay_base)

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
    To Sound (pulse train): sr, 1, 0.035, 2800
    irLeft = selected("Sound")
    
    # Apply decay envelope with chirp modulation
    Formula: "self * " + decay_str$ + "^(-(x-xmin)/(xmax-xmin)) * (1 + 0.7*sin(2*pi*x*150 + (x-xmin)*20))"
    
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
    Create Poisson process: "poisson_right", 0, impulse_duration_s * 0.93, poisson_density * 0.95
    poissonRight = selected("PointProcess")
    To Sound (pulse train): sr, 1, 0.032, 2600
    irRight = selected("Sound")
    
    decay_R = decay_base * 0.95
    decay_R_str$ = string$(decay_R)
    Formula: "self * " + decay_R_str$ + "^(-(x-xmin)/(xmax-xmin)) * (1 + 0.65*sin(2*pi*x*140 + (x-xmin)*22))"
    
    # Convolve right
    selectObject: rightChannel, irRight
    Convolve: "sum", "zero"
    convRight = selected("Sound")
    
    # Bandpass filter (slightly different)
    Filter (pass Hann band): low_cutoff_Hz * 1.2, high_cutoff_Hz * 0.95, smoothing_Hz * 0.9
    filtRight = selected("Sound")
    removeObject: convRight
    
    # Normalize wet signals
    selectObject: filtLeft
    Scale peak: 0.95
    
    selectObject: filtRight
    Scale peak: 0.95
    
    # Apply wet/dry mix
    wet_str$ = string$(wet_level)
    dry_str$ = string$(dry_level)
    left_str$ = string$(leftChannel)
    right_str$ = string$(rightChannel)
    
    selectObject: filtLeft
    Formula: "self * " + wet_str$ + " + object[" + left_str$ + "] * " + dry_str$
    
    selectObject: filtRight
    Formula: "self * " + wet_str$ + " + object[" + right_str$ + "] * " + dry_str$
    
    # Apply fadeout
    fade_start = totalDur - fadeout_duration_s
    fade_str$ = string$(fadeout_duration_s)
    start_str$ = string$(fade_start)
    
    # Need to handle duration mismatch - wet is longer due to convolution
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
    
    selectObject: filtLeft
    Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"
    Scale peak: 0.98
    
    selectObject: filtRight
    Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"
    Scale peak: 0.98
    
    # Combine to stereo
    selectObject: filtLeft, filtRight
    Combine to stereo
    result = selected("Sound")
    Rename: originalName$ + "_spectral_" + presetName$
    
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
    To Sound (pulse train): sr, 1, 0.035, 2800
    irMono = selected("Sound")
    
    # Apply decay envelope with chirp modulation
    Formula: "self * " + decay_str$ + "^(-(x-xmin)/(xmax-xmin)) * (1 + 0.7*sin(2*pi*x*150 + (x-xmin)*20))"
    
    # Convolve
    selectObject: extendedSound, irMono
    Convolve: "sum", "zero"
    convMono = selected("Sound")
    
    # Bandpass filter
    Filter (pass Hann band): low_cutoff_Hz, high_cutoff_Hz, smoothing_Hz
    filtMono = selected("Sound")
    removeObject: convMono
    
    Scale peak: 0.95
    
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
    
    Scale peak: 0.98
    Rename: originalName$ + "_spectral_" + presetName$
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
    Text: 0.5, "centre", 0.5, "half", "Spectral Decay Reverb: " + originalName$ + " (" + presetName$ + ")"
    
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
    Colour: "{0.5, 0.6, 0.7}"
    Draw: 0, originalDur, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Spectral " + fixed$(wet_dry_percent, 0) + "%"
    Text bottom: "yes", "Time (s)"
    
    # Bandpass filter shape
    Select outer viewport: 0, 4, 2.5, 4.0
    Select inner viewport: 0.6, 3.7, 2.7, 3.85
    
    Axes: 0, sr / 2 / 1000, 0, 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, sr / 2 / 1000, 0, 1.2
    
    # Draw bandpass shape
    Colour: "{0.5, 0.7, 0.9}"
    Line width: 2
    
    # Rising edge
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
    Paint rectangle: "{0.8, 0.9, 1.0}", lowK, highK, 0, 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Gain"
    Text bottom: "yes", "Frequency (kHz)"
    
    # Title
    Font size: 8
    Select outer viewport: 0, 4, 2.35, 2.55
    Text: 0.5, "centre", 0.5, "half", "BANDPASS FILTER"
    
    # Decay envelope
    Select outer viewport: 4, 8, 2.5, 4.0
    Select inner viewport: 4.5, 7.7, 2.7, 3.85
    
    Axes: 0, impulse_duration_s, -1.2, 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, impulse_duration_s, -1.2, 1.2
    
    # Draw decay envelope with modulation
    Colour: "{0.6, 0.5, 0.7}"
    Line width: 1.5
    
    numPoints = 200
    for i from 1 to numPoints
        t = (i - 1) / (numPoints - 1) * impulse_duration_s
        tNorm = t / impulse_duration_s
        envelope = decay_base ^ (-tNorm) * (1 + 0.7 * sin(2 * pi * t * 150 + t * 20))
        
        if envelope > 1.2
            envelope = 1.2
        elsif envelope < -1.2
            envelope = -1.2
        endif
        
        if i > 1
            Draw line: prevT, prevEnv, t, envelope
        endif
        prevT = t
        prevEnv = envelope
    endfor
    
    # Decay envelope only (dotted)
    Colour: "{0.8, 0.6, 0.4}"
    Dotted line
    for i from 1 to numPoints
        t = (i - 1) / (numPoints - 1) * impulse_duration_s
        tNorm = t / impulse_duration_s
        envelope = decay_base ^ (-tNorm)
        
        if i > 1
            Draw line: prevT2, prevEnv2, t, envelope
        endif
        prevT2 = t
        prevEnv2 = envelope
    endfor
    Solid line
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # Title
    Font size: 8
    Select outer viewport: 4, 8, 2.35, 2.55
    Text: 0.5, "centre", 0.5, "half", "IR ENVELOPE (chirp modulated)"
    
    # Parameters
    Select outer viewport: 0, 8, 4.1, 4.5
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "IR: " + fixed$(impulse_duration_s, 1) + "s | Density: " + string$(poisson_density) + " | Decay: " + string$(decay_base) + " | Band: " + string$(low_cutoff_Hz) + "-" + string$(high_cutoff_Hz) + "Hz"
    
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