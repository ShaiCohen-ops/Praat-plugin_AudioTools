# ============================================================
# Praat AudioTools - Spectral Swirl Effect.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.3 (2025)
# License: MIT License
#
# Description:
#   Sinusoidal frequency bin shifting - creates swirling,
#   liquid-like spectral movement. Frequencies are displaced
#   up and down in a wave pattern across the spectrum.
#
# Changelog v0.3:
#   - Added wet/dry mix control
#   - Added visualization
#   - Added stereo output option
#   - Added preset name to output filename
#
# Usage:
#   Select a Sound object in Praat and run this script.
# ============================================================

form Spectral Swirl Effect
    optionmenu Preset: 1
        option Custom
        option Gentle Wobble
        option Liquid Metal
        option Alien Voice
        option Underwater Warble
        option Extreme Mangle
    comment === Swirl Parameters ===
    natural number_of_cycles 4
    comment (sinusoidal cycles across spectrum)
    positive maximum_bin_shift 100
    comment (max frequency displacement in bins)
    comment === Mix ===
    real wet_dry_percent 100
    comment (0 = dry, 100 = full wet)
    boolean stereo_output 1
    comment === Output ===
    positive scale_peak 0.95
    boolean draw_visualization 1
    boolean play_after_processing 1
endform

# Apply presets
presetName$ = "Custom"

if preset = 2
    number_of_cycles = 2
    maximum_bin_shift = 30
    presetName$ = "GentleWobble"
elsif preset = 3
    number_of_cycles = 6
    maximum_bin_shift = 80
    presetName$ = "LiquidMetal"
elsif preset = 4
    number_of_cycles = 8
    maximum_bin_shift = 150
    presetName$ = "AlienVoice"
elsif preset = 5
    number_of_cycles = 3
    maximum_bin_shift = 60
    presetName$ = "UnderwaterWarble"
elsif preset = 6
    number_of_cycles = 12
    maximum_bin_shift = 300
    presetName$ = "ExtremeMangle"
endif

# Input validation
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

# Clamp wet/dry
if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif

wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

originalID = selected("Sound")
sound$ = selected$("Sound")
selectObject: originalID
original_sr = Get sampling frequency
duration = Get total duration
n_channels = Get number of channels

writeInfoLine: "=== Spectral Swirl Effect v0.3 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Duration: ", fixed$(duration, 2), " s"
appendInfoLine: "Cycles: ", number_of_cycles
appendInfoLine: "Max shift: ", maximum_bin_shift, " bins"
appendInfoLine: "Wet/Dry: ", fixed$(wet_dry_percent, 0), "%"
appendInfoLine: ""

# Convert to mono
selectObject: originalID
if n_channels > 1
    workingID = Convert to mono
else
    workingID = Copy: "working"
endif

# Keep dry copy for mix
selectObject: originalID
if n_channels > 1
    dry_sound = Convert to mono
else
    dry_sound = Copy: "dry"
endif

# To spectrum
appendInfoLine: "Analyzing spectrum..."
selectObject: workingID
origSpec = To Spectrum: "no"
Rename: "src"

# Convert to Matrix for processing
selectObject: origSpec
origMat = To Matrix
Rename: "srcMat"

selectObject: origMat
nrows = Get number of rows
ncols = Get number of columns

# Create output matrix
selectObject: origMat
swirlMat = Copy: "swirlMat"

# Build the swirl formula
cycStr$ = string$(number_of_cycles)
shiftStr$ = string$(maximum_bin_shift)
twoPi$ = "6.283185307"
ncolStr$ = string$(ncols)

appendInfoLine: "Applying swirl..."

# Shift bins sinusoidally, clamp to valid range
selectObject: swirlMat
Formula: "Matrix_srcMat[row, max(1, min(" + ncolStr$ + ", round(col + " + shiftStr$ + " * sin(" + twoPi$ + " * " + cycStr$ + " * col / " + ncolStr$ + "))))]"

# Back to Spectrum then Sound
selectObject: swirlMat
swirlSpec = To Spectrum
Rename: "swirlSpec"

appendInfoLine: "Reconstructing..."
selectObject: swirlSpec
resultID = To Sound

# Trim to original duration
selectObject: resultID
resultDur = Get total duration
if resultDur > duration
    trimmed = Extract part: 0, duration, "rectangular", 1, "no"
    removeObject: resultID
    resultID = trimmed
endif

# === WET/DRY MIX ===
if dry_level > 0
    wet_str$ = string$(wet_level)
    dry_str$ = string$(dry_level)
    dry_id_str$ = string$(dry_sound)
    
    selectObject: resultID
    Formula: "self * " + wet_str$ + " + object[" + dry_id_str$ + "] * " + dry_str$
endif

# === STEREO OUTPUT ===
if stereo_output and n_channels > 1
    selectObject: resultID
    mono_result = resultID
    resultID = Convert to stereo
    removeObject: mono_result
elsif stereo_output and n_channels = 1
    # Create pseudo-stereo with slight delay
    selectObject: resultID
    mono_result = resultID
    delay_samples = round(0.012 * original_sr)
    delay_str$ = string$(delay_samples)
    mono_str$ = string$(mono_result)
    
    Create Sound from formula: "left", 1, 0, duration, original_sr, "object[" + mono_str$ + "]"
    left_ch = selected("Sound")
    
    Create Sound from formula: "right", 1, 0, duration, original_sr, 
        ... "if col > " + delay_str$ + " then object[" + mono_str$ + ", col - " + delay_str$ + "] else 0 fi"
    right_ch = selected("Sound")
    
    selectObject: left_ch
    plusObject: right_ch
    resultID = Combine to stereo
    
    removeObject: mono_result, left_ch, right_ch
endif

selectObject: resultID
Rename: sound$ + "_swirl_" + presetName$
Scale peak: scale_peak

# === VISUALIZATION ===
if draw_visualization
    Erase all
    
    # --- Title ---
    Select outer viewport: 0, 8, 0.0, 0.5
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Spectral Swirl: " + presetName$
    
    # --- Original waveform ---
    Select outer viewport: 0, 4, 0.6, 1.6
    Select inner viewport: 0.4, 3.8, 0.7, 1.5
    selectObject: originalID
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"
    
    # --- Original spectrum ---
    Select outer viewport: 4, 8, 0.6, 1.6
    Select inner viewport: 4.4, 7.8, 0.7, 1.5
    selectObject: origSpec
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 80, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Spectrum"
    
    # --- Result waveform ---
    Select outer viewport: 0, 4, 1.8, 2.8
    Select inner viewport: 0.4, 3.8, 1.9, 2.7
    selectObject: resultID
    Colour: "{0.3, 0.6, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"
    
    # --- Result spectrum ---
    Select outer viewport: 4, 8, 1.8, 2.8
    Select inner viewport: 4.4, 7.8, 1.9, 2.7
    selectObject: swirlSpec
    Colour: "{0.8, 0.4, 0.2}"
    Draw: 0, 0, 0, 80, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Spectrum"
    Text bottom: "yes", "Frequency (Hz)"
    
    # --- Swirl pattern ---
    Select outer viewport: 0, 8, 3.0, 4.2
    Select inner viewport: 0.4, 7.6, 3.1, 4.1
    
    Axes: 0, ncols, -maximum_bin_shift * 1.2, maximum_bin_shift * 1.2
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, ncols, -maximum_bin_shift * 1.2, maximum_bin_shift * 1.2
    
    # Zero line
    Colour: "{0.8, 0.8, 0.8}"
    Draw line: 0, 0, ncols, 0
    
    # Draw swirl curve
    Colour: "{0.2, 0.6, 0.8}"
    Line width: 1.5
    
    numPoints = 500
    for i from 1 to numPoints
        col = (i - 1) / (numPoints - 1) * ncols
        shift = maximum_bin_shift * sin(2 * pi * number_of_cycles * col / ncols)
        
        if i > 1
            Draw line: prev_col, prev_shift, col, shift
        endif
        prev_col = col
        prev_shift = shift
    endfor
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Bin shift"
    Text bottom: "yes", "Frequency bin"
    
    # --- Parameters ---
    Select outer viewport: 0, 8, 4.3, 4.7
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", 
        ... "Cycles: " + string$(number_of_cycles) +
        ... " | Max shift: " + string$(maximum_bin_shift) + " bins" +
        ... " | Wet: " + fixed$(wet_dry_percent, 0) + "%"
    
    Font size: 10
    Colour: "Black"
endif

# Cleanup
removeObject: workingID, origSpec, origMat, swirlMat, swirlSpec, dry_sound

appendInfoLine: ""
appendInfoLine: "Complete!"

selectObject: resultID
if play_after_processing
    Play
endif