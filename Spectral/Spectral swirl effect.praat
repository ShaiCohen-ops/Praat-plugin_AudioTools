# ============================================================
# Praat AudioTools - Spectral Swirl Effect.praat
# Author: Shai Cohen
# Version: 1.0 (2025) - OPTIMIZED
# License: MIT License
#
# Description:
#   Sinusoidal frequency bin shifting - OPTIMIZED with:
#   - Optional downsampling (2-10× faster)
#   - Timing display
#   - Fixed object ID tracking
# ============================================================

form Spectral Swirl Effect v1.0 (Optimized)
    optionmenu Preset: 1
        option Custom
        option Gentle Wobble
        option Liquid Metal
        option Alien Voice
        option Underwater Warble
        option Extreme Mangle
    comment === Swirl Parameters ===
    natural number_of_cycles 4
    positive maximum_bin_shift 100
    comment === Performance ===
    optionmenu Speed_mode: 2
        option Full Quality (original sample rate)
        option Balanced (downsample to 22 kHz)
        option Fast (downsample to 11 kHz)
    comment === Mix ===
    real wet_dry_percent 100
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

# Set target sample rate based on speed mode
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

# Input validation
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

wet_dry_percent = max(0, min(100, wet_dry_percent))
wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

originalID = selected("Sound")
sound$ = selected$("Sound")
selectObject: originalID
original_sr = Get sampling frequency
duration = Get total duration
n_channels = Get number of channels

startTime = stopwatch

writeInfoLine: "╔══════════════════════════════════════════════════════════════╗"
writeInfoLine: "║      SPECTRAL SWIRL v1.0 (Optimized)                        ║"
writeInfoLine: "╚══════════════════════════════════════════════════════════════╝"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Speed: ", speedStr$
appendInfoLine: "Duration: ", fixed$(duration, 2), " s"
appendInfoLine: "Original SR: ", original_sr, " Hz"
appendInfoLine: "Cycles: ", number_of_cycles
appendInfoLine: "Max shift: ", maximum_bin_shift, " bins"
appendInfoLine: "Wet/Dry: ", fixed$(wet_dry_percent, 0), "%"
appendInfoLine: ""

# Convert to mono
selectObject: originalID
if n_channels > 1
    Convert to mono
    workingID = selected("Sound")
else
    Copy: "working"
    workingID = selected("Sound")
endif

# Keep dry copy
selectObject: originalID
if n_channels > 1
    Convert to mono
    dry_sound = selected("Sound")
else
    Copy: "dry"
    dry_sound = selected("Sound")
endif

# === OPTIONAL DOWNSAMPLING FOR SPEED ===
if targetSR > 0 and original_sr > targetSR
    appendInfoLine: "[1/5] Downsampling to ", targetSR, " Hz..."
    
    selectObject: workingID
    Resample: targetSR, 50
    resampledID = selected("Sound")
    removeObject: workingID
    workingID = resampledID
    
    selectObject: dry_sound
    Resample: targetSR, 50
    resampledDry = selected("Sound")
    removeObject: dry_sound
    dry_sound = resampledDry
    
    workingSR = targetSR
else
    appendInfoLine: "[1/5] Using original sample rate..."
    workingSR = original_sr
endif

# === SPECTRUM PROCESSING ===
appendInfoLine: ""
appendInfoLine: "[2/5] Analyzing spectrum..."
selectObject: workingID
To Spectrum: "no"
origSpec = selected("Spectrum")

appendInfoLine: "[3/5] Converting to matrix..."
selectObject: origSpec
To Matrix
origMat = selected("Matrix")
Rename: "srcMat"

selectObject: origMat
nrows = Get number of rows
ncols = Get number of columns

appendInfoLine: "      Matrix: ", nrows, " × ", ncols, " (", nrows * ncols, " elements)"

# === APPLY SWIRL ===
appendInfoLine: ""
appendInfoLine: "[4/5] Applying swirl..."

# Pre-build formula string
cycStr$ = string$(number_of_cycles)
shiftStr$ = string$(maximum_bin_shift)
ncolStr$ = string$(ncols)

# Copy and apply formula
selectObject: origMat
Copy: "swirlMat"
swirlMat = selected("Matrix")

Formula: "Matrix_srcMat[row, round(max(1, min(" + ncolStr$ + ", col + " + shiftStr$ + " * sin(6.283185307 * " + cycStr$ + " * col / " + ncolStr$ + "))))]"

appendInfoLine: "      Swirl complete!"

# === RECONSTRUCTION ===
appendInfoLine: ""
appendInfoLine: "[5/5] Reconstructing audio..."

selectObject: swirlMat
To Spectrum
swirlSpec = selected("Spectrum")

selectObject: swirlSpec
To Sound
resultID = selected("Sound")

# Trim to original duration
selectObject: resultID
resultDur = Get total duration
if resultDur > duration
    Extract part: 0, duration, "rectangular", 1, "no"
    trimmed = selected("Sound")
    removeObject: resultID
    resultID = trimmed
endif

# Upsample back if needed
if targetSR > 0 and original_sr > targetSR
    appendInfoLine: "      Upsampling to ", original_sr, " Hz..."
    
    selectObject: resultID
    Resample: original_sr, 50
    upsampledID = selected("Sound")
    removeObject: resultID
    resultID = upsampledID
    
    selectObject: dry_sound
    Resample: original_sr, 50
    upsampledDry = selected("Sound")
    removeObject: dry_sound
    dry_sound = upsampledDry
endif

# === WET/DRY MIX ===
if dry_level > 0
    appendInfoLine: "      Mixing wet/dry..."
    wet_str$ = string$(wet_level)
    dry_str$ = string$(dry_level)
    dry_id_str$ = string$(dry_sound)
    
    selectObject: resultID
    Formula: "self * " + wet_str$ + " + object[" + dry_id_str$ + "] * " + dry_str$
endif

# === STEREO OUTPUT ===
if stereo_output
    appendInfoLine: "      Creating stereo output..."
    
    if n_channels > 1
        selectObject: resultID
        mono_result = resultID
        Convert to stereo
        resultID = selected("Sound")
        removeObject: mono_result
    elsif n_channels = 1
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
        Combine to stereo
        resultID = selected("Sound")
        
        removeObject: mono_result, left_ch, right_ch
    endif
endif

# Final processing
selectObject: resultID
Rename: sound$ + "_swirl_" + presetName$
Scale peak: scale_peak

# === VISUALIZATION ===
if draw_visualization
    Erase all
    
    Select outer viewport: 1, 8, 0.0, 0.5
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Spectral Swirl: " + presetName$ + " (" + speedStr$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 4, 0.6, 1.6
    Select inner viewport: 0.4, 3.8, 0.7, 1.5
    selectObject: originalID
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"
    
    # Original spectrum
    Select outer viewport: 4, 8, 0.6, 1.6
    Select inner viewport: 4.4, 7.8, 0.7, 1.5
    selectObject: origSpec
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 80, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Spectrum"
    
    # Result waveform
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
    
    # Result spectrum
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
    
    # Swirl pattern
    Select outer viewport: 0, 8, 3.0, 4.2
    Select inner viewport: 0.4, 7.6, 3.1, 4.1
    
    Axes: 0, ncols, -maximum_bin_shift * 1.2, maximum_bin_shift * 1.2
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, ncols, -maximum_bin_shift * 1.2, maximum_bin_shift * 1.2
    
    Colour: "{0.8, 0.8, 0.8}"
    Draw line: 0, 0, ncols, 0
    
    Colour: "{0.2, 0.6, 0.8}"
    Line width: 1.5
    
    # Draw swirl curve
    numPoints = 300
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
    
    # Parameters
    Select outer viewport: 1, 8, 4.3, 4.7
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    processingTime = stopwatch - startTime
    Text: 0.5, "centre", 0.5, "half", 
        ... "Cycles: " + string$(number_of_cycles) +
        ... " | Max shift: " + string$(maximum_bin_shift) + " bins" +
        ... " | Time: " + fixed$(processingTime, 2) + "s"
    
    Font size: 10
    Colour: "Black"
endif

# Cleanup
removeObject: workingID, origSpec, origMat, swirlMat, swirlSpec, dry_sound

processingTime = stopwatch - startTime

# Ensure result is selected for final output
selectObject: resultID

appendInfoLine: ""
appendInfoLine: "╔══════════════════════════════════════════════════════════════╗"
appendInfoLine: "║                    COMPLETE                                  ║"
appendInfoLine: "╚══════════════════════════════════════════════════════════════╝"
appendInfoLine: "Processing time: ", fixed$(processingTime, 2), " seconds"
appendInfoLine: "Output: ", selected$("Sound")

if play_after_processing
    selectObject: resultID
    Play
endif

selectObject: resultID