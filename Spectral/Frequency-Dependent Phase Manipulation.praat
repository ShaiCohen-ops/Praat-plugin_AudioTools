# ============================================================
# Praat AudioTools - Frequency-Dependent_Phase_Manipulation.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025) 
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Frequency-dependent phase manipulation for stereo imaging.
#   Creates comb filtering, phaser effects, and formant resonances
#   via spectral phase rotation. NOW WITH SPEED MODES!
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

form Phase Manipulation v1.0 
    optionmenu Preset: 1
        option Custom
        option Subtle Comb
        option Wide Phaser
        option Chaotic Texture
        option Spectral Blur
        option Formant Resonance
        option Extreme Comb
        option Deep Stereo
    comment === Performance ===
    optionmenu Speed_mode: 2
        option Full Quality (original sample rate)
        option Balanced (downsample to 22 kHz)
        option Fast (downsample to 11 kHz)
    comment === Phase Parameters ===
    positive Phase_amount 50.0
    comment (higher = more dramatic effect)
    positive Stereo_width 0.2
    comment (L/R difference: 0.1-1.0)
    optionmenu Phase_mode: 1
        option Comb filter (periodic notches)
        option Chaotic texture (multiple periods)
        option Spectral blur (randomized)
        option Formant-like resonances
    comment === Output ===
    real Dry_wet 1.0
    comment (0 = dry, 1 = wet)
    positive Scale_peak 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Apply presets
if preset = 2
    phase_amount = 20
    stereo_width = 0.15
    phase_mode = 1
    presetName$ = "SubtleComb"
elsif preset = 3
    phase_amount = 60
    stereo_width = 0.4
    phase_mode = 1
    presetName$ = "WidePhaser"
elsif preset = 4
    phase_amount = 80
    stereo_width = 0.3
    phase_mode = 2
    presetName$ = "ChaoticTexture"
elsif preset = 5
    phase_amount = 50
    stereo_width = 0.25
    phase_mode = 3
    presetName$ = "SpectralBlur"
elsif preset = 6
    phase_amount = 40
    stereo_width = 0.2
    phase_mode = 4
    presetName$ = "FormantResonance"
elsif preset = 7
    phase_amount = 100
    stereo_width = 0.1
    phase_mode = 1
    presetName$ = "ExtremeComb"
elsif preset = 8
    phase_amount = 70
    stereo_width = 0.6
    phase_mode = 2
    presetName$ = "DeepStereo"
else
    presetName$ = "Custom"
endif

# Mode name
if phase_mode = 1
    modeName$ = "Comb"
elsif phase_mode = 2
    modeName$ = "Chaos"
elsif phase_mode = 3
    modeName$ = "Blur"
else
    modeName$ = "Formant"
endif

# Set target sample rate
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

# Setup
selectObject: originalID
numChannels = Get number of channels
duration = Get total duration
sampleRate = Get sampling frequency

startTime = stopwatch

clearinfo
writeInfoLine: "=== Phase Manipulation v1.0 (Optimized) ==="
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Speed: ", speedStr$
appendInfoLine: "Duration: ", fixed$(duration, 2), " s"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Mode: ", modeName$
appendInfoLine: "Phase: ", phase_amount, " | Stereo: ", stereo_width
appendInfoLine: ""

# Convert to mono
selectObject: originalID
if numChannels > 1
    Convert to mono
    monoID = selected("Sound")
else
    Copy: "mono_temp"
    monoID = selected("Sound")
endif

# Optional downsampling
if targetSR > 0 and sampleRate > targetSR
    appendInfoLine: "[SPEED] Downsampling to ", targetSR, " Hz"
    selectObject: monoID
    Resample: targetSR, 50
    resampledID = selected("Sound")
    removeObject: monoID
    monoID = resampledID
    workingSR = targetSR
else
    workingSR = sampleRate
endif

# Keep dry copy
selectObject: monoID
Copy: "dry"
dryID = selected("Sound")

# Build phase shift formulas
amtL$ = fixed$(phase_amount, 4)
amtR$ = fixed$(phase_amount * (1 + stereo_width), 4)

if phase_mode = 1
    shiftL$ = amtL$ + " * sin(2 * pi * x / 200)"
    shiftR$ = amtR$ + " * sin(2 * pi * x / 200)"
elsif phase_mode = 2
    shiftL$ = amtL$ + " * (sin(2*pi*x/147) + 0.7*sin(2*pi*x/283) + 0.4*sin(2*pi*x/521))"
    shiftR$ = amtR$ + " * (sin(2*pi*x/147) + 0.7*sin(2*pi*x/283) + 0.4*sin(2*pi*x/521))"
elsif phase_mode = 3
    shiftL$ = amtL$ + " * sin(x/37) * sin(x/113)"
    shiftR$ = amtR$ + " * sin(x/37) * sin(x/113)"
else
    shiftL$ = amtL$ + " * (exp(-((x-800)/300)^2) + exp(-((x-1500)/400)^2) + exp(-((x-2500)/500)^2))"
    shiftR$ = amtR$ + " * (exp(-((x-800)/300)^2) + exp(-((x-1500)/400)^2) + exp(-((x-2500)/500)^2))"
endif

# # Process LEFT channel
appendInfo: "Processing left channel..."

selectObject: monoID
To Spectrum: "yes"
spectrumL_ID = selected("Spectrum")

To Matrix
matrixL_ID = selected("Matrix")
Rename: "srcL"

Copy: "shiftedL"
matrixL_shifted_ID = selected("Matrix")

# Apply phase rotation
selectObject: matrixL_shifted_ID
Formula: "if row = 1 then sqrt(Matrix_srcL[1,col]^2 + Matrix_srcL[2,col]^2) * cos(arctan2(Matrix_srcL[2,col], Matrix_srcL[1,col]) + " + shiftL$ + ") else sqrt(Matrix_srcL[1,col]^2 + Matrix_srcL[2,col]^2) * sin(arctan2(Matrix_srcL[2,col], Matrix_srcL[1,col]) + " + shiftL$ + ") endif"

To Spectrum
spectrumL_mod_ID = selected("Spectrum")
Rename: "specL"

To Sound
soundL_ID = selected("Sound")

appendInfoLine: " done"

# Process RIGHT channel
appendInfo: "Processing right channel..."

selectObject: monoID
To Spectrum: "yes"
spectrumR_ID = selected("Spectrum")

To Matrix
matrixR_ID = selected("Matrix")
Rename: "srcR"

Copy: "shiftedR"
matrixR_shifted_ID = selected("Matrix")

selectObject: matrixR_shifted_ID
Formula: "if row = 1 then sqrt(Matrix_srcR[1,col]^2 + Matrix_srcR[2,col]^2) * cos(arctan2(Matrix_srcR[2,col], Matrix_srcR[1,col]) + " + shiftR$ + ") else sqrt(Matrix_srcR[1,col]^2 + Matrix_srcR[2,col]^2) * sin(arctan2(Matrix_srcR[2,col], Matrix_srcR[1,col]) + " + shiftR$ + ") endif"

To Spectrum
spectrumR_mod_ID = selected("Spectrum")
Rename: "specR"

To Sound
soundR_ID = selected("Sound")

appendInfoLine: " done"

# Upsample if needed
if targetSR > 0 and sampleRate > targetSR
    appendInfo: "Upsampling to ", sampleRate, " Hz..."
    
    selectObject: soundL_ID
    Resample: sampleRate, 50
    soundL_up = selected("Sound")
    removeObject: soundL_ID
    soundL_ID = soundL_up
    
    selectObject: soundR_ID
    Resample: sampleRate, 50
    soundR_up = selected("Sound")
    removeObject: soundR_ID
    soundR_ID = soundR_up
    
    selectObject: dryID
    Resample: sampleRate, 50
    dry_up = selected("Sound")
    removeObject: dryID
    dryID = dry_up
    
    appendInfoLine: " done"
endif

# Trim to original duration
selectObject: soundL_ID
durL = Get total duration
if durL > duration
    Extract part: 0, duration, "rectangular", 1, "no"
    trimL_ID = selected("Sound")
    removeObject: soundL_ID
    soundL_ID = trimL_ID
endif

selectObject: soundR_ID
durR = Get total duration
if durR > duration
    Extract part: 0, duration, "rectangular", 1, "no"
    trimR_ID = selected("Sound")
    removeObject: soundR_ID
    soundR_ID = trimR_ID
endif

# Dry/wet mix
if dry_wet < 1
    appendInfo: "Mixing dry/wet..."
    
    wetStr$ = fixed$(dry_wet, 4)
    dryStr$ = fixed$(1 - dry_wet, 4)
    dryIdStr$ = string$(dryID)
    
    selectObject: soundL_ID
    Rename: "wetL"
    Formula: "self * " + wetStr$ + " + Object_" + dryIdStr$ + "(x) * " + dryStr$
    
    selectObject: soundR_ID
    Rename: "wetR"
    Formula: "self * " + wetStr$ + " + Object_" + dryIdStr$ + "(x) * " + dryStr$
    
    appendInfoLine: " done"
endif

# Combine to stereo
selectObject: soundL_ID
plusObject: soundR_ID
Combine to stereo
resultID = selected("Sound")

Rename: originalName$ + "_phase_" + modeName$
Scale peak: scale_peak

processingTime = stopwatch - startTime

# Visualization
if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    
    Select outer viewport: 0, 8, 0, 0.5
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Phase Manipulation: " + originalName$ + " [" + presetName$ + "]"
    
    # Original waveform
    Select outer viewport: 0, 4, 0.6, 1.8
    Select inner viewport: 0.5, 3.7, 0.7, 1.7
    selectObject: originalID
    Colour: "{0.7, 0.7, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Original"
    
    # Processed waveform
    Select outer viewport: 4, 8, 0.6, 1.8
    Select inner viewport: 4.5, 7.7, 0.7, 1.7
    selectObject: resultID
    Colour: "{0.2, 0.5, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text top: "no", "Phase Processed (stereo)"
    
    # Original spectrum
    Select outer viewport: 0, 4, 2.0, 3.6
    Select inner viewport: 0.5, 3.7, 2.2, 3.4
    selectObject: spectrumL_ID
    Colour: "{0.7, 0.7, 0.7}"
    Draw: 0, 5000, 0, 80, "no"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Original Spectrum"
    Text left: "yes", "dB"
    
    # Modified spectrum
    Select outer viewport: 4, 8, 2.0, 3.6
    Select inner viewport: 4.5, 7.7, 2.2, 3.4
    selectObject: spectrumL_mod_ID
    Colour: "{0.2, 0.5, 0.8}"
    Draw: 0, 5000, 0, 80, "no"
    Colour: "Black"
    Draw inner box
    Text top: "no", "Phase-Shifted Spectrum (L)"
    Text left: "yes", "dB"
    
    # Phase shift pattern - FIXED with smaller step
    Select outer viewport: 0, 8, 3.8, 5.2
    Select inner viewport: 0.6, 7.6, 4.0, 5.0
    
    Axes: 0, 5000, -phase_amount * 2, phase_amount * 2
    
    Colour: "{0.9, 0.5, 0.2}"
    Line width: 2
    
    # FIXED: Use smaller step to avoid zero-crossings
    step = 25
    
    for f from 0 to 5000
        if phase_mode = 1
            shift = phase_amount * sin(2 * pi * f / 200)
        elsif phase_mode = 2
            shift = phase_amount * (sin(2*pi*f/147) + 0.7*sin(2*pi*f/283) + 0.4*sin(2*pi*f/521))
        elsif phase_mode = 3
            shift = phase_amount * sin(f/37) * sin(f/113)
        else
            shift = phase_amount * (exp(-((f-800)/300)^2) + exp(-((f-1500)/400)^2) + exp(-((f-2500)/500)^2))
        endif
        
        if f = 0
            prevF = 0
            prevShift = shift
        else
            Draw line: prevF, prevShift, f, shift
            prevF = f
            prevShift = shift
        endif
        
        f = f + step
    endfor
    
    # Zero line
    Colour: "{0.5, 0.5, 0.5}"
    Line width: 1
    Dotted line
    Draw line: 0, 0, 5000, 0
    Solid line
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 9
    Text top: "no", "Phase Shift Pattern: " + modeName$
    Text left: "yes", "Shift"
    Text bottom: "yes", "Frequency (Hz)"
    
    # Info panel
    Select outer viewport: 0, 8, 5.3, 5.9
    Select inner viewport: 0.5, 7.7, 5.35, 5.85
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Font size: 9
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.5, "half", "Mode: " + modeName$
    Text: 0.2, "left", 0.5, "half", "Amount: " + fixed$(phase_amount, 0)
    Text: 0.4, "left", 0.5, "half", speedStr$
    Text: 0.65, "left", 0.5, "half", "Time: " + fixed$(processingTime, 2) + " s"
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
endif

# Cleanup
removeObject: monoID, dryID
removeObject: spectrumL_ID, matrixL_ID, matrixL_shifted_ID, spectrumL_mod_ID, soundL_ID
removeObject: spectrumR_ID, matrixR_ID, matrixR_shifted_ID, spectrumR_mod_ID, soundR_ID

# Output
appendInfoLine: ""
appendInfoLine: "Processing time: ", fixed$(processingTime, 2), " seconds"
appendInfoLine: "Created: ", originalName$ + "_phase_", modeName$

selectObject: resultID

if play_result
    Play
endif

selectObject: originalID
