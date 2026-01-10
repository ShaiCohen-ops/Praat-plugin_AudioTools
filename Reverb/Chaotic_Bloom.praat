# ============================================================
# Praat AudioTools - Chaotic_Bloom.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Chaotic Bloom - stochastic diffusion reverb using Poisson
#   processes. Creates organic, evolving reverb tails by
#   convolving input with randomly-distributed impulse clouds.
#   Envelope includes exponential decay with chirping shimmer.
#   Stereo mode uses decorrelated L/R impulse patterns with
#   sinusoidal panning for spatial movement.
#
# Changelog v0.2:
#   - Fixed selection syntax (object IDs)
#   - Fixed name-based references
#   - Added wet/dry mix control
#   - Added visualization
#   - Added info output
# ============================================================

form Chaotic Bloom
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Default (balanced)
        option Dense Bloom
        option Sparse Bloom
        option Wide Stereo Shimmer
        option Custom (use settings below)
    
    comment === Bloom Parameters ===
    positive Tail_duration_s 2.0
    positive Poisson_density 3000
    comment (impulses per second)
    
    comment === Pulse Train ===
    positive Pulse_amplitude 1.0
    positive Pulse_width 0.04
    positive Pulse_period 2500
    
    comment === Mix ===
    positive Convolution_mix 0.4
    real Wet_dry_percent 50
    comment (0 = dry only, 100 = wet only)
    
    comment === Output ===
    positive Scale_peak 0.85
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
    tail_duration_s = 2.0
    poisson_density = 3000
    pulse_amplitude = 1.0
    pulse_width = 0.04
    pulse_period = 2500
    convolution_mix = 0.4
    presetName$ = "Default"
elsif preset = 2
    # Dense Bloom
    tail_duration_s = 3.0
    poisson_density = 4500
    pulse_amplitude = 1.1
    pulse_width = 0.05
    pulse_period = 2200
    convolution_mix = 0.5
    presetName$ = "DenseBloom"
elsif preset = 3
    # Sparse Bloom
    tail_duration_s = 1.5
    poisson_density = 1800
    pulse_amplitude = 0.9
    pulse_width = 0.03
    pulse_period = 2800
    convolution_mix = 0.3
    presetName$ = "SparseBloom"
elsif preset = 4
    # Wide Stereo Shimmer
    tail_duration_s = 2.5
    poisson_density = 3200
    pulse_amplitude = 1.0
    pulse_width = 0.035
    pulse_period = 2600
    convolution_mix = 0.35
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

# === Info ===
writeInfoLine: "=== Chaotic Bloom ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Poisson density: ", poisson_density, " impulses/s"
appendInfoLine: "Tail duration: ", tail_duration_s, " s"
appendInfoLine: "Pulse width: ", pulse_width
appendInfoLine: "Convolution mix: ", convolution_mix
appendInfoLine: "Wet/Dry: ", wet_dry_percent, "%"
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

appendInfoLine: "Processing..."

# IR duration (longer than tail for Poisson to fill)
irDuration = 6

# Create extended sound with tail
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
    
    # === LEFT CHANNEL IR ===
    appendInfoLine: "  Creating left IR..."
    Create Poisson process: "chaos_L", 0, irDuration, poisson_density
    poissonL = selected("PointProcess")
    
    To Sound (pulse train): sr, pulse_amplitude, pulse_width, pulse_period
    irSoundL = selected("Sound")
    
    # Apply envelope: sin² fade × exponential decay × shimmer
    Formula: ~ self * (sin(pi*(x-xmin)/(xmax-xmin))^2) * 80^(-(x-xmin)/(xmax-xmin)) * (1 + 0.8*sin(2*pi*x*200*(x-xmin)/(xmax-xmin)))
    
    # Convolve left
    selectObject: leftChannel, irSoundL
    Convolve: "sum", "zero"
    convL = selected("Sound")
    
    mix_str$ = string$(convolution_mix)
    Formula: "self * " + mix_str$
    
    # === RIGHT CHANNEL IR (different parameters for decorrelation) ===
    appendInfoLine: "  Creating right IR..."
    Create Poisson process: "chaos_R", 0, irDuration, poisson_density * 1.07
    poissonR = selected("PointProcess")
    
    To Sound (pulse train): sr, pulse_amplitude, pulse_width * 0.875, pulse_period * 1.04
    irSoundR = selected("Sound")
    
    # Slightly different envelope for decorrelation
    Formula: ~ self * (sin(pi*(x-xmin)/(xmax-xmin))^2) * 75^(-(x-xmin)/(xmax-xmin)) * (1 + 0.75*sin(2*pi*x*180*(x-xmin)/(xmax-xmin)))
    
    # Convolve right
    selectObject: rightChannel, irSoundR
    Convolve: "sum", "zero"
    convR = selected("Sound")
    
    mix_r_str$ = string$(convolution_mix * 0.95)
    Formula: "self * " + mix_r_str$
    
    # === PANNING MODULATION ===
    appendInfoLine: "  Applying stereo panning..."
    
    # Left channel panning
    selectObject: leftChannel
    Copy: "L_panned"
    lPanned = selected("Sound")
    Formula: ~ self * (0.5 + 0.5*sin(2*pi*(x-xmin)*2))
    
    selectObject: convL
    Copy: "convL_panned"
    convLPanned = selected("Sound")
    Formula: ~ self * (0.5 - 0.5*sin(2*pi*(x-xmin)*2))
    
    # Right channel panning
    selectObject: rightChannel
    Copy: "R_panned"
    rPanned = selected("Sound")
    Formula: ~ self * (0.5 - 0.5*sin(2*pi*(x-xmin)*1.8))
    
    selectObject: convR
    Copy: "convR_panned"
    convRPanned = selected("Sound")
    Formula: ~ self * (0.5 + 0.5*sin(2*pi*(x-xmin)*1.8))
    
    # === MIX FINAL LEFT ===
    lPanned_str$ = string$(lPanned)
    convLPanned_str$ = string$(convLPanned)
    
    selectObject: lPanned
    Formula: "self + object[" + convLPanned_str$ + "]"
    finalLeft = lPanned
    
    # === MIX FINAL RIGHT ===
    rPanned_str$ = string$(rPanned)
    convRPanned_str$ = string$(convRPanned)
    
    selectObject: rPanned
    Formula: "self + object[" + convRPanned_str$ + "]"
    finalRight = rPanned
    
    # === APPLY WET/DRY ===
    if dry_level > 0
        wet_str$ = string$(wet_level)
        dry_str$ = string$(dry_level)
        left_str$ = string$(leftChannel)
        right_str$ = string$(rightChannel)
        
        selectObject: finalLeft
        Formula: "self * " + wet_str$ + " + object[" + left_str$ + "] * " + dry_str$
        
        selectObject: finalRight
        Formula: "self * " + wet_str$ + " + object[" + right_str$ + "] * " + dry_str$
    endif
    
    # === COMBINE TO STEREO ===
    selectObject: finalLeft, finalRight
    Combine to stereo
    result = selected("Sound")
    Scale peak: scale_peak
    Rename: originalName$ + "_bloom_" + presetName$
    
    # Store IR for visualization
    irForViz = irSoundL
    
    # Cleanup
    removeObject: poissonL, poissonR
    removeObject: irSoundR
    removeObject: leftChannel, rightChannel
    removeObject: convL, convR
    removeObject: convLPanned, convRPanned
    removeObject: finalLeft, finalRight
    removeObject: extendedSound

else
    # === MONO PROCESSING ===
    appendInfoLine: "  Processing mono..."
    
    # Create IR
    Create Poisson process: "chaos_mono", 0, irDuration, poisson_density
    poissonMono = selected("PointProcess")
    
    To Sound (pulse train): sr, pulse_amplitude, pulse_width, pulse_period
    irSound = selected("Sound")
    
    # Apply envelope
    Formula: ~ self * (sin(pi*(x-xmin)/(xmax-xmin))^2) * 80^(-(x-xmin)/(xmax-xmin)) * (1 + 0.8*sin(2*pi*x*200*(x-xmin)/(xmax-xmin)))
    
    # Convolve
    selectObject: extendedSound, irSound
    Convolve: "sum", "zero"
    convMono = selected("Sound")
    
    mix_str$ = string$(convolution_mix)
    Formula: "self * " + mix_str$
    
    # Mix with dry
    ext_str$ = string$(extendedSound)
    conv_str$ = string$(convMono)
    
    selectObject: extendedSound
    Copy: "result_temp"
    resultTemp = selected("Sound")
    
    wet_str$ = string$(wet_level)
    dry_str$ = string$(dry_level)
    
    Formula: "self * " + dry_str$ + " + object[" + conv_str$ + "] * " + wet_str$
    
    Scale peak: scale_peak
    Rename: originalName$ + "_bloom_" + presetName$
    result = selected("Sound")
    
    # Store IR for visualization
    irForViz = irSound
    
    # Cleanup
    removeObject: poissonMono, convMono, extendedSound
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
    Text: 0.5, "centre", 0.5, "half", "Chaotic Bloom: " + originalName$ + " (" + presetName$ + ")"
    
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
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Bloom " + fixed$(wet_dry_percent, 0) + "%"
    Text bottom: "yes", "Time (s)"
    
    # IR waveform
    Select outer viewport: 0, 4, 2.5, 3.8
    Select inner viewport: 0.6, 3.8, 2.6, 3.7
    selectObject: irForViz
    Colour: "{0.5, 0.7, 0.6}"
    Draw: 0, 3, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "IR"
    Text bottom: "yes", "Time (s)"
    
    # Parameters
    Select outer viewport: 4, 8, 2.5, 3.8
    Select inner viewport: 4.4, 7.6, 2.6, 3.7
    
    Axes: 0, 4, 0, 6
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 4, 0, 6
    
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    
    Text: 0.2, "left", 5.5, "half", "Poisson density: " + string$(poisson_density) + "/s"
    Text: 0.2, "left", 4.7, "half", "Tail: " + fixed$(tail_duration_s, 1) + " s"
    Text: 0.2, "left", 3.9, "half", "Pulse width: " + fixed$(pulse_width, 3)
    Text: 0.2, "left", 3.1, "half", "Conv mix: " + fixed$(convolution_mix, 2)
    Text: 0.2, "left", 2.3, "half", "Wet/Dry: " + fixed$(wet_dry_percent, 0) + "%"
    Text: 0.2, "left", 1.5, "half", "Channels: " + string$(numChannels)
    
    Colour: "Black"
    Draw inner box
    
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