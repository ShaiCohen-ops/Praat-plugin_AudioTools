# ============================================================
# Praat AudioTools - Crystalline_Cascade.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3.1 (2025)
# v0.3.1 (2026): Shared left panel-label rails and user-approved Summary geometry; DSP/analysis unchanged.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Crystalline Cascade - reverse-exponential flutter reverb.
#   Instead of decaying, the reverb BUILDS UP over time,
#   creating ethereal, crystalline textures. Amplitude flutter
#   adds shimmer via FM-modulated amplitude modulation.
#   Triple-layer processing blends dry, scaled, and convolved
#   signals. Stereo mode uses decorrelated L/R parameters.
#
# Changelog v0.2:
#   - Fixed selection syntax (object IDs)
#   - Fixed formula syntax (string building)
#   - Added wet/dry mix control
#   - Added visualization
#   - Renamed form to match filename
# ============================================================

form Crystalline Cascade
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Subtle Flutter
        option Medium Flutter
        option Heavy Flutter
        option Extreme Flutter
    
    comment === Duration ===
    positive Tail_duration_s 2.0
    
    comment === Poisson Process ===
    positive Poisson_density 800
    positive Pulse_width 0.08
    positive Pulse_period 1200
    
    comment === Modulation ===
    positive Exponential_base 120
    positive Modulation_depth 0.6
    positive Modulation_frequency 60
    
    comment === Layer Mix ===
    positive Convolution_mix 0.35
    positive Layer2_amplitude 0.7
    
    comment === Output Mix ===
    real Wet_dry_percent 50
    comment (0 = dry only, 100 = wet only)
    positive Scale_peak 0.88
    
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
    # Subtle Flutter
    tail_duration_s = 1.5
    poisson_density = 500
    pulse_width = 0.06
    pulse_period = 1400
    exponential_base = 100
    modulation_depth = 0.4
    modulation_frequency = 45
    convolution_mix = 0.22
    layer2_amplitude = 0.65
    scale_peak = 0.9
    presetName$ = "Subtle"
elsif preset = 3
    # Medium Flutter
    tail_duration_s = 2.0
    poisson_density = 800
    pulse_width = 0.08
    pulse_period = 1200
    exponential_base = 120
    modulation_depth = 0.6
    modulation_frequency = 60
    convolution_mix = 0.35
    layer2_amplitude = 0.7
    scale_peak = 0.88
    presetName$ = "Medium"
elsif preset = 4
    # Heavy Flutter
    tail_duration_s = 2.8
    poisson_density = 1100
    pulse_width = 0.1
    pulse_period = 1000
    exponential_base = 140
    modulation_depth = 0.75
    modulation_frequency = 75
    convolution_mix = 0.45
    layer2_amplitude = 0.75
    scale_peak = 0.86
    presetName$ = "Heavy"
elsif preset = 5
    # Extreme Flutter
    tail_duration_s = 4.0
    poisson_density = 1500
    pulse_width = 0.12
    pulse_period = 850
    exponential_base = 160
    modulation_depth = 0.85
    modulation_frequency = 90
    convolution_mix = 0.55
    layer2_amplitude = 0.8
    scale_peak = 0.84
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

# IR duration for Poisson process
irDuration = 4

# === Info ===
writeInfoLine: "=== Crystalline Cascade ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Poisson density: ", poisson_density, " impulses/s"
appendInfoLine: "Exponential base: ", exponential_base, " (reverse growth)"
appendInfoLine: "Modulation: depth=", modulation_depth, " freq=", modulation_frequency, "Hz"
appendInfoLine: "Layer2 amplitude: ", layer2_amplitude
appendInfoLine: "Convolution mix: ", convolution_mix
appendInfoLine: "Wet/Dry: ", wet_dry_percent, "%"
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

appendInfoLine: "Processing..."

# Build formula strings
base_str$ = string$(exponential_base)
depth_str$ = string$(modulation_depth)
freq_str$ = string$(modulation_frequency)
layer2_str$ = string$(layer2_amplitude)
mix_str$ = string$(convolution_mix)

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
    
    To Sound (pulse train): sr, 1, pulse_width, pulse_period
    irLeftRaw = selected("Sound")
    
    # Apply reverse exponential + flutter envelope
    Formula: "self * " + base_str$ + "^((x-xmin)/(xmax-xmin)-1) * (1 + " + depth_str$ + "*cos(2*pi*x*" + freq_str$ + " + 10*sin(2*pi*x*3)))"
    irLeft = irLeftRaw
    
    # Convolve left
    selectObject: aLeft, irLeft
    Convolve: "sum", "zero"
    bLeft = selected("Sound")
    Formula: "self * " + mix_str$
    
    # === RIGHT CHANNEL (different parameters for decorrelation) ===
    appendInfoLine: "  Creating right IR..."
    
    selectObject: rightChannel
    Copy: "sound_right"
    aRight = selected("Sound")
    
    # Slightly different Poisson density
    densityR = poisson_density * 1.0625
    Create Poisson process: "poisson_R", 0, irDuration, densityR
    poissonR = selected("PointProcess")
    
    To Sound (pulse train): sr, 1, pulse_width * 0.9375, pulse_period * 1.04
    irRightRaw = selected("Sound")
    
    # Slightly different modulation
    baseR_str$ = string$(exponential_base * 0.958)
    depthR_str$ = string$(modulation_depth * 0.917)
    freqR_str$ = string$(modulation_frequency * 1.083)
    
    Formula: "self * " + baseR_str$ + "^((x-xmin)/(xmax-xmin)-1) * (1 + " + depthR_str$ + "*cos(2*pi*x*" + freqR_str$ + " + 12*sin(2*pi*x*2.8)))"
    irRight = irRightRaw
    
    # Convolve right
    selectObject: aRight, irRight
    Convolve: "sum", "zero"
    bRight = selected("Sound")
    Formula: "self * " + mix_str$
    
    # === TRIPLE-LAYER LEFT ===
    appendInfoLine: "  Building triple-layer left..."
    
    # Layer 2 (scaled copy)
    selectObject: aLeft
    Copy: "layer2_L"
    layer2L = selected("Sound")
    Formula: "self * " + layer2_str$
    
    # Combine layers: original + layer2 + convolved
    aLeft_str$ = string$(aLeft)
    layer2L_str$ = string$(layer2L)
    bLeft_str$ = string$(bLeft)
    
    selectObject: aLeft
    Copy: "result_left"
    resultLeft = selected("Sound")
    Formula: "self + object[" + layer2L_str$ + "] + object[" + bLeft_str$ + "]"
    
    # === TRIPLE-LAYER RIGHT ===
    appendInfoLine: "  Building triple-layer right..."
    
    selectObject: aRight
    Copy: "layer2_R"
    layer2R = selected("Sound")
    Formula: "self * " + layer2_str$
    
    aRight_str$ = string$(aRight)
    layer2R_str$ = string$(layer2R)
    bRight_str$ = string$(bRight)
    
    selectObject: aRight
    Copy: "result_right"
    resultRight = selected("Sound")
    Formula: "self + object[" + layer2R_str$ + "] + object[" + bRight_str$ + "]"
    
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
    
    # Normalize
    selectObject: resultLeft
    Scale peak: scale_peak
    
    selectObject: resultRight
    Scale peak: scale_peak
    
    # === COMBINE TO STEREO ===
    selectObject: resultLeft, resultRight
    Combine to stereo
    result = selected("Sound")
    Rename: originalName$ + "_cascade_" + presetName$
    
    # Store IR for visualization
    irForViz = irLeft
    
    # Cleanup
    removeObject: poissonL, poissonR
    removeObject: irRight
    removeObject: leftChannel, rightChannel
    removeObject: aLeft, aRight
    removeObject: bLeft, bRight
    removeObject: layer2L, layer2R
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
    
    To Sound (pulse train): sr, 1, pulse_width, pulse_period
    irMono = selected("Sound")
    
    Formula: "self * " + base_str$ + "^((x-xmin)/(xmax-xmin)-1) * (1 + " + depth_str$ + "*cos(2*pi*x*" + freq_str$ + " + 10*sin(2*pi*x*3)))"
    
    # Convolve
    selectObject: aMono, irMono
    Convolve: "sum", "zero"
    bMono = selected("Sound")
    Formula: "self * " + mix_str$
    
    # Layer 2
    selectObject: aMono
    Copy: "layer2_mono"
    layer2Mono = selected("Sound")
    Formula: "self * " + layer2_str$
    
    # Combine layers
    aMono_str$ = string$(aMono)
    layer2Mono_str$ = string$(layer2Mono)
    bMono_str$ = string$(bMono)
    
    selectObject: aMono
    Copy: "result_mono"
    resultMono = selected("Sound")
    Formula: "self + object[" + layer2Mono_str$ + "] + object[" + bMono_str$ + "]"
    
    # Apply wet/dry
    if dry_level > 0
        wet_str$ = string$(wet_level)
        dry_str$ = string$(dry_level)
        ext_str$ = string$(extendedSound)
        
        selectObject: resultMono
        Formula: "self * " + wet_str$ + " + object[" + ext_str$ + "] * " + dry_str$
    endif
    
    selectObject: resultMono
    Scale peak: scale_peak
    Rename: originalName$ + "_cascade_" + presetName$
    result = resultMono
    
    # Store IR for visualization
    irForViz = irMono
    
    # Cleanup
    removeObject: poissonMono, aMono, bMono, layer2Mono, extendedSound
endif

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all

    # Shared left panel-label rail.
    labelX = -0.035
    labelFont = 7

    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Crystalline Cascade: " + originalName$ + " (" + presetName$ + ")" + " | v0.3.1"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.60, 7.70, 0.7, 1.3
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select inner viewport: 0.20, 0.48, 0.7, 1.3
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Dry"
    Select inner viewport: 0.60, 7.70, 0.7, 1.3
    Axes: 0, 1, 0, 1
    
    # Result waveform
    Select outer viewport: 0, 8, 1.5, 2.3
    Select inner viewport: 0.60, 7.70, 1.6, 2.2
    selectObject: result
    Colour: "{0.6, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select inner viewport: 0.20, 0.48, 1.6, 2.2
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Cascade " + fixed$(wet_dry_percent, 0) + "\%  "
    Select inner viewport: 0.60, 7.70, 1.6, 2.2
    Axes: 0, 1, 0, 1
    Text bottom: "yes", "Time (s)"
    
    # IR envelope (reverse exponential)
    Select outer viewport: 0, 4, 2.5, 3.8
    Select inner viewport: 0.60, 3.85, 2.6, 3.7
    
    Axes: 0, irDuration, 0, 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, irDuration, 0, 1.2
    
    # Draw reverse exponential envelope
    Colour: "{0.6, 0.5, 0.7}"
    Line width: 2
    nPoints = 200
    for p from 2 to nPoints
        t1 = (p - 2) / nPoints * irDuration
        t2 = (p - 1) / nPoints * irDuration
        
        # Reverse exponential: base^(t-1)
        norm1 = t1 / irDuration
        norm2 = t2 / irDuration
        y1 = exponential_base ^ (norm1 - 1)
        y2 = exponential_base ^ (norm2 - 1)
        
        Draw line: t1, y1, t2, y2
    endfor
    Line width: 1
    
    # Draw normal decay for comparison
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    for p from 2 to nPoints
        t1 = (p - 2) / nPoints * irDuration
        t2 = (p - 1) / nPoints * irDuration
        norm1 = t1 / irDuration
        norm2 = t2 / irDuration
        y1 = exponential_base ^ (-norm1)
        y2 = exponential_base ^ (-norm2)
        Draw line: t1, y1, t2, y2
    endfor
    Solid line
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Select inner viewport: 0.20, 0.48, 2.6, 3.7
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Envelope"
    Select inner viewport: 0.60, 3.85, 2.6, 3.7
    Axes: 0, irDuration, 0, 1.2
    Text bottom: "yes", "Time (s)"
    
    # Legend
    Font size: 6
    Colour: "{0.6, 0.5, 0.7}"
    Text: irDuration * 0.75, "centre", 1.1, "half", "Reverse (builds up)"
    Colour: "{0.7, 0.7, 0.7}"
    Text: irDuration * 0.75, "centre", 1.0, "half", "Normal (decays)"
    
    # IR waveform
    Select outer viewport: 4, 8, 2.5, 3.8
    Select inner viewport: 4.45, 7.70, 2.6, 3.7
    selectObject: irForViz
    Colour: "{0.5, 0.7, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Select inner viewport: 4.05, 4.33, 2.6, 3.7
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "IR"
    Select inner viewport: 4.45, 7.70, 2.6, 3.7
    Axes: 0, irDuration, 0, 1.2
    Text bottom: "yes", "Time (s)"
    
    # Parameters
    Select outer viewport: 0, 8, 3.9, 4.3
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Base: " + string$(exponential_base) + " | Mod: " + fixed$(modulation_depth, 2) + " @ " + string$(modulation_frequency) + "Hz | Layer2: " + fixed$(layer2_amplitude, 2) + " | Conv: " + fixed$(convolution_mix, 2)
    
    Font size: 10
    Colour: "Black"
    
    # Cleanup IR
    removeObject: irForViz

    # Summary strip - compact house spacing.
    Select outer viewport: 0, 8, 4.40, 5.40
    Select inner viewport: 0.60, 7.70, 4.47, 5.33
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Font size: 7
    Text: 0.02, "left", 0.72, "half", "##Summary##"
    Font size: 6
    Colour: "{0.35, 0.35, 0.50}"
    Font size: 6
    Text: 0.02, "left", 0.48, "half", "Cascade map shows the realized crystalline delay structure"
    Colour: "{0.25, 0.25, 0.35}"
    Font size: 6
    Text: 0.02, "left", 0.24, "half", "Dry/reference remains neutral; coloured structure denotes the processed field"

    # Restore full-page viewport before leaving visualization.
    Select inner viewport: 0.60, 7.70, 4.47, 5.33
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box

    Select outer viewport: 0, 8, 0, 5.50
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
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
