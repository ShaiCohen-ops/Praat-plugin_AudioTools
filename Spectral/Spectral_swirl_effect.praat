# ============================================================
# Praat AudioTools - Spectral Swirl Effect.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Sinusoidal spectral shifting: each output bin reads the input
#   spectrum at a sinusoidally displaced position, warping the
#   frequency axis in swirling lobes across the range.
#
# Changelog v0.3 (2026):
#   - FIX: the swirl DEPTH was specified in FFT bins, so its
#     effect in Hz shrank with file duration ("AlienVoice" was
#     ~50 Hz of swirl on a 3 s file, ~15 Hz on 10 s -- fading
#     with length, overshooting on short clips). Depth is now
#     Maximum_shift_hz, converted through the measured bin width:
#     duration-independent. Presets recalibrated to their
#     3-second-equivalent Hz values. (The lobe POSITIONS were
#     always duration-safe -- normalized to the spectrum width.)
#   - REMOVED the speed modes, with a benchmark: full quality
#     processes 60 s in 0.03 s and 300 s in 0.1 s -- and the
#     DEFAULT mode (Balanced/22050) was lowpassing every output
#     at 11 kHz, the same muffle pattern fixed in CA_Reverb_IR.
#   - FIX: info header erased itself (repeated writeInfoLine).
#   - VIZ: the "result spectrum" panel is computed from the
#     actual output (it showed the pre-mix, pre-trim wet
#     spectrum); the swirl-pattern panel now speaks Hz on both
#     axes, matching the parameter.
#   - Reconstructed sample rate pinned (Override) after the
#     Spectrum -> Sound round-trip.
#   - Form title said v1.0 while the header said v0.2; unified.
#   - NOTE: the core swirl formula was verified CORRECT as
#     written -- it reads from a frozen source matrix, row-aware
#     (complex bins move wholesale, phase-coherent). No pattern
#     ledger entry applies to it.
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
# ============================================================

form Spectral Swirl Effect v0.3
    optionmenu Preset: 1
        option Custom
        option Gentle Wobble
        option Liquid Metal
        option Alien Voice
        option Underwater Warble
        option Extreme Mangle
    comment === Swirl Parameters ===
    natural number_of_cycles 4
    positive Maximum_shift_hz 35
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
    maximum_shift_hz = 10
    presetName$ = "GentleWobble"
elsif preset = 3
    number_of_cycles = 6
    maximum_shift_hz = 25
    presetName$ = "LiquidMetal"
elsif preset = 4
    number_of_cycles = 8
    maximum_shift_hz = 50
    presetName$ = "AlienVoice"
elsif preset = 5
    number_of_cycles = 3
    maximum_shift_hz = 20
    presetName$ = "UnderwaterWarble"
elsif preset = 6
    number_of_cycles = 12
    maximum_shift_hz = 100
    presetName$ = "ExtremeMangle"
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
appendInfoLine: "║      SPECTRAL SWIRL v0.3                                    ║"
appendInfoLine: "╚══════════════════════════════════════════════════════════════╝"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Duration: ", fixed$(duration, 2), " s"
appendInfoLine: "Original SR: ", original_sr, " Hz"
appendInfoLine: "Cycles: ", number_of_cycles
appendInfoLine: "Max shift: ", fixed$(maximum_shift_hz, 0), " Hz"
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

# === SPECTRUM PROCESSING ===
# (v0.3: speed modes removed -- full rate swirls 300 s in 0.1 s,
# and the old default lowpassed everything at 11 kHz)
appendInfoLine: ""
appendInfoLine: "[1/4] Analyzing spectrum..."
selectObject: workingID
To Spectrum: "yes"
origSpec = selected("Spectrum")
binWidth = Get bin width

appendInfoLine: "[2/4] Converting to matrix..."
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
appendInfoLine: "[3/4] Applying swirl..."

# v0.3: depth in Hz -> bins through the measured bin width
# (duration-independent effect)
shiftBins = maximum_shift_hz / binWidth
appendInfoLine: "      ", fixed$(maximum_shift_hz, 0), " Hz = ", fixed$(shiftBins, 1), " bins at this FFT size"

# Pre-build formula string
cycStr$ = string$(number_of_cycles)
shiftStr$ = string$(shiftBins)
ncolStr$ = string$(ncols)

# Copy and apply formula
selectObject: origMat
Copy: "swirlMat"
swirlMat = selected("Matrix")

Formula: "Matrix_srcMat[row, round(max(1, min(" + ncolStr$ + ", col + " + shiftStr$ + " * sin(6.283185307 * " + cycStr$ + " * col / " + ncolStr$ + "))))]"

appendInfoLine: "      Swirl complete!"

# === RECONSTRUCTION ===
appendInfoLine: ""
appendInfoLine: "[4/4] Reconstructing audio..."

selectObject: swirlMat
To Spectrum
swirlSpec = selected("Spectrum")

selectObject: swirlSpec
To Sound
resultID = selected("Sound")
Override sampling frequency: original_sr

# Trim to original duration
selectObject: resultID
resultDur = Get total duration
if resultDur > duration
    Extract part: 0, duration, "rectangular", 1, "no"
    trimmed = selected("Sound")
    removeObject: resultID
    resultID = trimmed
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

processingTime = stopwatch

# === VISUALIZATION ===
if draw_visualization
    Erase all
    
    Select outer viewport: 1, 8, 0.0, 0.5
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Spectral Swirl v0.3: " + presetName$
    
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
    
    # Result spectrum (v0.3: from the ACTUAL output -- swirlSpec is
    # the pre-mix, pre-trim wet spectrum)
    Select outer viewport: 4, 8, 1.8, 2.8
    Select inner viewport: 4.4, 7.8, 1.9, 2.7
    selectObject: resultID
    vizCh = Get number of channels
    if vizCh > 1
        vizOutMono = Extract one channel: 1
    else
        vizOutMono = Copy: "viz_out"
    endif
    vizOutSpec = To Spectrum: "yes"
    Colour: "{0.8, 0.4, 0.2}"
    Draw: 0, 0, 0, 80, "no"
    removeObject: vizOutMono, vizOutSpec
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Spectrum"
    Text bottom: "yes", "Frequency (Hz)"
    
    # Swirl pattern
    Select outer viewport: 0, 8, 3.0, 4.2
    Select inner viewport: 0.4, 7.6, 3.1, 4.1
    
    # v0.3: both axes in Hz, matching the parameter
    nyq = original_sr / 2
    Axes: 0, nyq, -maximum_shift_hz * 1.2, maximum_shift_hz * 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, nyq, -maximum_shift_hz * 1.2, maximum_shift_hz * 1.2
    
    Colour: "{0.8, 0.8, 0.8}"
    Draw line: 0, 0, nyq, 0
    
    Colour: "{0.2, 0.6, 0.8}"
    Line width: 1.5
    
    # Draw swirl curve
    numPoints = 300
    for i from 1 to numPoints
        fHz = (i - 1) / (numPoints - 1) * nyq
        shift = maximum_shift_hz * sin(2 * pi * number_of_cycles * fHz / nyq)
        
        if i > 1
            Draw line: prev_f, prev_shift, fHz, shift
        endif
        prev_f = fHz
        prev_shift = shift
    endfor
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Shift (Hz)"
    Text bottom: "yes", "Frequency (Hz)"
    
    # Parameters
    Select outer viewport: 1, 8, 4.3, 4.7
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", 
        ... "Cycles: " + string$(number_of_cycles) +
        ... " | Max shift: " + fixed$(maximum_shift_hz, 0) + " Hz" +
        ... " | Time: " + fixed$(processingTime, 2) + "s"
    
    Font size: 10
    Colour: "Black"
endif

# Cleanup
removeObject: workingID, origSpec, origMat, swirlMat, swirlSpec, dry_sound

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